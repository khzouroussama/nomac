import Foundation
import NIOSSL
import NomacCore
import NomacSigning
import NomacTestSupport
import Testing
@testable import NomacDevice

/// `nomac device pair` and what a machine says on its way to a device, against a scripted device.
/// `first_run_experiments.py` runs the same against libimobiledevice's usbmuxd and tools.
@Suite struct PairingTests {
    static let udid = ScriptedDevice.udid

    func pair(_ device: ScriptedDevice, timeout: TimeInterval = 120) throws -> (outcome: Pairing.Outcome, lines: [String], waits: Int) {
        var lines: [String] = []
        var waits = 0
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let outcome = try Pairing.pair(usbmux: device.client, udid: Self.udid, timeout: timeout, at: { now }, wait: {
            waits += 1
            now.addTimeInterval($0)
        }, progress: { lines.append($0) })
        return (outcome, lines, waits)
    }

    @Test func waitsForTrustAndTheLockThenSavesTheRecord() throws {
        let device = ScriptedDevice()
        device.pairAnswers = ["pending", "pending", "locked", "ok"]
        let (outcome, lines, waits) = try pair(device)
        #expect(outcome == .paired)
        #expect(lines == ["waiting for you to tap Trust on the device and enter its passcode", "waiting for you to unlock the device"])
        #expect(waits == 3)
        #expect(device.pairRequests.count == 4)
        let saved = try PropertyListMessages.dictionary(try #require(device.records[Self.udid]), source: "test")
        #expect(saved.keys.sorted() == ["DeviceCertificate", "EscrowBag", "HostCertificate", "HostID", "HostPrivateKey", "RootCertificate", "RootPrivateKey", "SystemBUID", "WiFiMACAddress"])
        #expect(saved["EscrowBag"] == .data([1, 2, 3]))
        #expect(saved["WiFiMACAddress"] == .string("00:00:00:00:00:01"))
        #expect(saved["SystemBUID"] == .string("BUID"))
    }

    /// The fields libimobiledevice 1.3.0's `idevicepair pair` sends (`pair-reference`); every attempt
    /// offers the same pairing, and no private key leaves the host.
    @Test func theRequestIsIdevicepairs() throws {
        let device = ScriptedDevice()
        device.pairAnswers = ["pending", "ok"]
        _ = try pair(device)
        let request = device.pairRequests[0]
        #expect(request.keys.sorted() == ["Label", "PairRecord", "PairingOptions", "ProtocolVersion", "Request"])
        #expect(request["ProtocolVersion"] == .string("2"))
        #expect(request["PairingOptions"] == .dictionary(["ExtendedPairingErrors": .boolean(true)]))
        guard case .dictionary(let record)? = request["PairRecord"] else {
            Issue.record("no PairRecord")
            return
        }
        #expect(record.keys.sorted() == ["DeviceCertificate", "HostCertificate", "HostID", "RootCertificate", "SystemBUID"])
        #expect(device.pairRequests[0] == device.pairRequests[1])
    }

    /// libimobiledevice's usbmuxd on Ubuntu 24.04 and 25.10 and Debian 13 answers `Result` 2 with the
    /// record written (`usbmuxd-records`).
    @Test func aSaveReportedAsFailedThatWroteTheRecordCounts() throws {
        let device = ScriptedDevice()
        device.saveResult = 2
        #expect(try pair(device).outcome == .paired)
    }

    @Test func aRecordNotSavedIsAnError() throws {
        let device = ScriptedDevice()
        device.savesTheRecord = false
        #expect(throws: NomacError.self) { try pair(device) }
    }

    @Test func aSessionThatStartsNeedsNoPairing() throws {
        let device = ScriptedDevice()
        device.records[Self.udid] = ScriptedDevice.record(hostID: "KNOWN")
        device.trustedHosts = ["KNOWN"]
        #expect(try pair(device).outcome == .alreadyPaired)
        #expect(device.pairRequests.isEmpty)
    }

    @Test func aDeviceThatForgotThisHostPairsAgainAndReplacesTheRecord() throws {
        let device = ScriptedDevice()
        device.records[Self.udid] = ScriptedDevice.record(hostID: "FORGOTTEN")
        #expect(try pair(device).outcome == .paired)
        let saved = try PropertyListMessages.dictionary(try #require(device.records[Self.udid]), source: "test")
        #expect(saved["HostID"] != .string("FORGOTTEN"))
    }

    /// On Linux usbmuxd's preflight pairs when the user taps Trust (`preflight.c`): its record serves.
    @Test func aPairingUSBMuxdMadeWhileWaitingServes() throws {
        let device = ScriptedDevice()
        device.pairAnswers = ["pending"]
        device.usbmuxPairsAfter = 2
        let (outcome, _, _) = try pair(device)
        #expect(outcome == .paired)
        #expect(try PropertyListMessages.dictionary(try #require(device.records[Self.udid]), source: "test")["HostID"] == .string("USBMUXD"))
    }

    @Test func aRefusalSaysHowToAskAgain() throws {
        let device = ScriptedDevice()
        device.pairAnswers = ["denied"]
        do {
            _ = try pair(device)
            Issue.record("a refusal paired")
        } catch let error as NomacError {
            #expect(error.message == "lockdownd refused Pair: UserDeniedPairing")
            #expect(error.notes.first?.contains("Reset Location & Privacy") == true)
        }
    }

    @Test func noAnswerStopsAfterTheTimeout() throws {
        let device = ScriptedDevice()
        device.pairAnswers = ["pending"]
        do {
            _ = try pair(device, timeout: 3)
            Issue.record("no answer paired")
        } catch let error as NomacError {
            #expect(error.message == "the device did not answer the pairing in 3 seconds")
            #expect(error.notes.first?.contains("nomac device pair --device \(Self.udid)") == true)
        }
    }

    @Test func aMissingDeviceStopsBeforeAnyKeyIsMade() {
        let device = ScriptedDevice()
        device.listed = []
        #expect(throws: NomacError.self) { try pair(device) }
        #expect(device.pairRequests.isEmpty)
    }

    @Test func aDevicePublicKeyThatIsNotPEMIsSaid() {
        let device = ScriptedDevice()
        device.devicePublicKey = Array("garbage".utf8)
        #expect(throws: NomacError("the device's public key is neither an RSA PUBLIC KEY nor a PUBLIC KEY in PEM")) { try pair(device) }
    }

    /// A client with a pairing's host certificate, against swift-nio-ssl's server: BoringSSL takes
    /// the empty names and PKCS #8 key, and the server sees that certificate.
    @Test func theHostCertificateServesTLS() throws {
        let chain = try PairingCertificates(devicePublicKey: Array(PairingCertificatesFixture.pkcs1.utf8), at: Date())
        let pipe = try TLSStreamTests.ServerPipe()
        let tls = try TLSStream(over: pipe, certificate: chain.hostCertificate, privateKey: chain.hostPrivateKey)
        try tls.write(Array("QueryType".utf8))
        #expect(try pipe.received() == Array("QueryType".utf8))
        #expect(pipe.clientCertificate.value == (try NIOSSLCertificate.fromPEMBytes(chain.hostCertificate)).first)
    }
}

@Suite struct DeveloperModeTests {
    func session(_ device: ScriptedDevice) throws -> DeviceSession {
        device.records[ScriptedDevice.udid] = ScriptedDevice.record(hostID: "KNOWN")
        device.trustedHosts = ["KNOWN"]
        return try DeviceSession(usbmux: device.client, udid: ScriptedDevice.udid)
    }

    @Test func offSaysHowToTurnItOnAndHowToShowIt() throws {
        let device = ScriptedDevice()
        device.developerMode = .boolean(false)
        let session = try session(device)
        do {
            _ = try session.checkDeveloperMode()
            Issue.record("off passed")
        } catch let error as NomacError {
            #expect(error.message == "Developer Mode is off")
            #expect(error.notes[0].contains("Settings > Privacy & Security > Developer Mode"))
            #expect(error.notes[1].contains("nomac device developer-mode --device \(ScriptedDevice.udid)"))
        }
    }

    @Test func onAndNotReported() throws {
        let device = ScriptedDevice()
        #expect(try session(device).checkDeveloperMode() == true)
        device.developerMode = nil
        #expect(try session(device).checkDeveloperMode() == nil)
    }

    /// A broken connection is not a device that does not report Developer Mode.
    @Test func aBrokenConnectionIsNotNotReported() throws {
        final class Broken: ByteStream {
            var fails = false
            func write(_ bytes: [UInt8]) throws { if fails { throw NomacError("connection closed") } }
            func read(_ count: Int) throws -> [UInt8] { throw NomacError("connection closed") }
        }
        let lockdown = LockdownClient(stream: Broken())
        #expect(throws: NomacError("connection closed")) { try lockdown.value(domain: "com.apple.security.mac.amfi", key: "DeveloperModeStatus") }
    }

    /// `idevicedevmodectl reveal` and pymobiledevice3's `reveal_developer_mode_option_in_ui`: action 0.
    @Test func revealSendsActionZero() throws {
        let device = ScriptedDevice()
        try session(device).revealDeveloperMode()
        #expect(device.serviceMessages == [["action": .integer(0)]])
    }

    @Test func aRefusedRevealIsSaid() throws {
        let device = ScriptedDevice()
        device.amfiReply = ["Error": .string("nope")]
        #expect(throws: NomacError("the device refused to show Developer Mode: nope")) { try session(device).revealDeveloperMode() }
        device.amfiReply = ["status": .boolean(false)]
        #expect(throws: NomacError("AMFI did not say it showed Developer Mode")) { try session(device).revealDeveloperMode() }
    }
}

@Suite struct SessionStartTests {
    @Test func aPeerThatRefusesTheCertificateAfterTheHandshakeIsSaid() throws {
        final class Refusing: ByteStream {
            func write(_ bytes: [UInt8]) throws {}
            func read(_ count: Int) throws -> [UInt8] { throw NomacError("alert unknown CA") }
        }
        let stream = ReplayStream(replies: [["Request": .string("StartSession"), "SessionID": .string("S"), "EnableSessionSSL": .boolean(true)]])
        do {
            try LockdownClient(stream: stream).startSession(hostID: "H", systemBUID: "B") { _ in Refusing() }
            Issue.record("a refused session started")
        } catch let error as NomacError {
            #expect(error.message == "the TLS handshake of the lockdown session failed: alert unknown CA")
            #expect(error.notes.first?.contains("nomac device pair") == true)
        }
    }

    @Test func aMissingRecordNamesTheCommandOnBothUSBMuxds() {
        for number: Int64 in [22, 2] {
            #expect(USBMux.pairRecordFailure(.result(number), udid: "U").notes.first?.contains("nomac device pair --device U") == true)
        }
    }

    @Test func lockdownErrorsSayTheNextStep() throws {
        #expect(Lockdown.hint(for: "InvalidHostID")?.contains("nomac device pair") == true)
        #expect(Lockdown.hint(for: "UserDeniedPairing")?.contains("Reset Location & Privacy") == true)
        #expect(Lockdown.hint(for: "EscrowLocked")?.contains("unlock") == true)
    }

    @Test func aPairRecordFromLibimobiledeviceIsReadInBinaryToo() throws {
        let device = ScriptedDevice()
        device.records[ScriptedDevice.udid] = ScriptedDevice.record(hostID: "KNOWN")
        #expect(try device.client.pairRecord(udid: ScriptedDevice.udid).hostID == "KNOWN")
        #expect(try device.client.systemBUID() == "BUID")
    }
}

/// What a Linux machine says at each state of usbmuxd, observed with libimobiledevice's on nine
/// distribution releases with no device (`first_run_experiments.py`, docs/formats/usbmux.md "On Linux").
@Suite struct USBMuxHostTests {
    static let socket = StreamSocket.Address.unix("/var/run/usbmuxd")

    func host(linux: Bool = true, exists: Bool = false, writable: Bool = true, daemon: String? = nil, apple: [String] = []) -> USBMuxHost {
        USBMuxHost(isLinux: linux, exists: { _ in exists }, isWritable: { _ in writable }, daemon: { daemon }, appleDevices: { apple })
    }

    @Test func notInstalledNamesEachDistributionsPackage() {
        let notes = USBMuxHost.unreachableNotes(address: Self.socket, host: host())
        #expect(notes[0].hasPrefix("usbmuxd is not installed"))
        for command in ["sudo apt-get install -y usbmuxd", "sudo dnf install -y usbmuxd", "sudo pacman -S usbmuxd", "sudo zypper install usbmuxd"] {
            #expect(notes.contains { $0.contains(command) })
        }
    }

    @Test func installedAndNotRunningSaysToPlugIn() {
        let notes = USBMuxHost.unreachableNotes(address: Self.socket, host: host(daemon: "/usr/sbin/usbmuxd"))
        #expect(notes[0] == "usbmuxd (/usr/sbin/usbmuxd) is installed but not running: it starts when an iPhone is plugged in")
        #expect(notes[1].contains("sudo systemctl start usbmuxd"))
    }

    /// `kill -9` leaves the socket behind: ECONNREFUSED.
    @Test func aStoppedDaemonsSocketSaysToRestart() {
        let notes = USBMuxHost.unreachableNotes(address: Self.socket, host: host(exists: true, daemon: "/usr/sbin/usbmuxd"))
        #expect(notes == ["/var/run/usbmuxd exists but nothing answers: usbmuxd stopped without removing it. 'sudo systemctl restart usbmuxd', or without systemd 'sudo rm /var/run/usbmuxd' and 'sudo usbmuxd'"])
    }

    @Test func aSocketThisUserMayNotWriteSaysSo() {
        let notes = USBMuxHost.unreachableNotes(address: Self.socket, host: host(exists: true, writable: false, daemon: "/usr/sbin/usbmuxd"))
        #expect(notes[0].hasPrefix("this user may not write to /var/run/usbmuxd"))
    }

    @Test func aForwardAndAMacSayTheirOwn() {
        #expect(USBMuxHost.unreachableNotes(address: .tcp(host: "h", port: 1), host: host())[0].contains("USBMUXD_SOCKET_ADDRESS"))
        #expect(USBMuxHost.unreachableNotes(address: Self.socket, host: host(linux: false)) == ["usbmuxd does not answer at /var/run/usbmuxd"])
    }

    @Test func noDeviceSaysWhatTheKernelSees() {
        #expect(USBMuxHost.noDeviceNotes(seen: [], address: Self.socket, host: host()) == ["the kernel sees no iPhone on USB: unlock it and check the cable (some only charge) and the port"])
        let seen = USBMuxHost.noDeviceNotes(seen: [], address: Self.socket, host: host(apple: ["iPhone"]))
        #expect(seen[0].hasPrefix("the kernel sees iPhone on USB but usbmuxd lists nothing"))
        #expect(USBMuxHost.noDeviceNotes(seen: ["A (USB)"], address: Self.socket, host: host())[0].hasPrefix("usbmuxd sees A (USB)"))
        #expect(USBMuxHost.noDeviceNotes(seen: [], address: Self.socket, host: host(linux: false))[0].hasPrefix("usbmuxd sees no device at all"))
    }

    /// The products of usbmuxd's udev rule: 5ac/12[9a]x and 5ac/190[1-5].
    @Test func appleDevicesOnUSBAreThoseUSBMuxdServes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nomac-sysfs-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: folder) }
        for (name, vendor, product, label) in [("1-1", "05ac", "12a8", "iPhone"), ("1-2", "05ac", "1460", "Keyboard"), ("1-3", "1d6b", "0002", "Hub"), ("1-4", "05ac", "1902", nil), ("usb1", nil, nil, nil)] as [(String, String?, String?, String?)] {
            try FileSystem.createDirectory(folder + "/" + name)
            if let vendor { try FileSystem.write(Data((vendor + "\n").utf8), to: "\(folder)/\(name)/idVendor") }
            if let product { try FileSystem.write(Data((product + "\n").utf8), to: "\(folder)/\(name)/idProduct") }
            if let label { try FileSystem.write(Data((label + "\n").utf8), to: "\(folder)/\(name)/product") }
        }
        #expect(USBMuxHost.appleDevices(sysfs: folder) == ["iPhone", "Apple device"])
        #expect(USBMuxHost.appleDevices(sysfs: folder + "/none").isEmpty)
    }

    /// Debian and Ubuntu put it in /usr/sbin, Fedora in /usr/bin as well: a user's PATH may hold neither.
    @Test func theDaemonIsFoundOutsidePATH() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nomac-path-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: folder) }
        try FileSystem.createDirectory(folder)
        FileManager.default.createFile(atPath: folder + "/usbmuxd", contents: Data(), attributes: [.posixPermissions: 0o755])
        #expect(USBMuxHost.locateDaemon(environment: ["PATH": folder]) == folder + "/usbmuxd")
    }

    @Test func noDeviceListedIsAnErrorWithTheNote() {
        let device = ScriptedDevice()
        device.listed = []
        do {
            _ = try device.client.device(udid: ScriptedDevice.udid)
            Issue.record("a device was found")
        } catch let error as NomacError {
            #expect(error.message == "usbmuxd sees no device \(ScriptedDevice.udid)")
            #expect(error.notes.first?.hasPrefix("the kernel sees no iPhone") == true)
        } catch {
            Issue.record("\(error)")
        }
    }
}
