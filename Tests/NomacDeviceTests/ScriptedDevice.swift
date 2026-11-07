import Foundation
import NomacCore
import NomacSigning
@testable import NomacDevice

/// A usbmuxd and a device's lockdownd behind `USBMuxClient`, answering by script: the protocol sides
/// of `.github/scripts/fake_device.py`, without TLS (the session answers `EnableSessionSSL` false).
final class ScriptedDevice {
    static let udid = "00008140-00FACE00FACE001E"
    var listed = [ScriptedDevice.udid]
    var records: [String: [UInt8]] = [:]
    var trustedHosts: Set<String> = []
    /// What `Pair` answers, in order, the last repeating.
    var pairAnswers = ["ok"]
    /// What usbmuxd answers to `SavePairRecord` having saved it: 2 from libimobiledevice's usbmuxd on
    /// Ubuntu 24.04 and 25.10 and Debian 13, 0 on Ubuntu 22.04, Debian 12, Fedora 43, Arch and openSUSE Tumbleweed.
    var saveResult: Int64 = 0
    var savesTheRecord = true
    /// usbmuxd pairs by itself after this many `Pair` requests, as its preflight does when the user taps Trust.
    var usbmuxPairsAfter: Int?
    var developerMode: PropertyListValue? = .boolean(true)
    var devicePublicKey = Array(PairingCertificatesFixture.pkcs1.utf8)
    var pairRequests: [[String: PropertyListValue]] = []
    var serviceMessages: [[String: PropertyListValue]] = []
    var amfiReply: [String: PropertyListValue] = ["success": .boolean(true)]
    /// What `StartSession` and Developer Mode's `GetValue` always answer, when set.
    var sessionError: String?
    var developerModeError: String?

    var host = USBMuxHost(isLinux: true, isContainer: { false }, exists: { _ in true }, isWritable: { _ in true }, daemon: { "/usr/sbin/usbmuxd" }, appleDevices: { [] })

    var client: USBMuxClient {
        USBMuxClient(address: .unix("/var/run/usbmuxd"), host: host) { Connection(device: self) }
    }

    static func record(hostID: String) -> [UInt8] {
        PropertyListValue.xmlDocument(.dictionary([
            "HostID": .string(hostID), "SystemBUID": .string("BUID"), "HostCertificate": .data(Array("cert".utf8)), "HostPrivateKey": .data(Array("key".utf8)),
        ]))
    }

    final class Connection: ByteStream {
        enum Mode { case usbmux, lockdown, amfi }

        let device: ScriptedDevice
        var mode = Mode.usbmux
        var pending: [UInt8] = []
        var outgoing: [UInt8] = []

        init(device: ScriptedDevice) { self.device = device }

        func write(_ bytes: [UInt8]) throws {
            pending += bytes
            while let message = try nextMessage() { answer(message) }
        }

        func read(_ count: Int) throws -> [UInt8] {
            guard outgoing.count >= count else { throw NomacError("connection closed by the scripted device") }
            defer { outgoing.removeFirst(count) }
            return Array(outgoing.prefix(count))
        }

        private func nextMessage() throws -> [String: PropertyListValue]? {
            let (headerSize, length): (Int, Int)
            if mode == .usbmux {
                guard pending.count >= USBMux.headerSize else { return nil }
                headerSize = USBMux.headerSize
                length = Int(try USBMux.header(Array(pending.prefix(USBMux.headerSize))).length) - USBMux.headerSize
            } else {
                guard pending.count >= 4 else { return nil }
                headerSize = 4
                length = pending.prefix(4).reduce(0) { $0 << 8 | Int($1) }
            }
            guard pending.count >= headerSize + length else { return nil }
            defer { pending.removeFirst(headerSize + length) }
            return try PropertyListMessages.dictionary(Array(pending[headerSize..<(headerSize + length)]), source: "scripted")
        }

        private func answer(_ message: [String: PropertyListValue]) {
            switch mode {
            case .usbmux: answerUSBMux(message)
            case .lockdown: answerLockdown(message)
            case .amfi:
                device.serviceMessages.append(message)
                outgoing += PropertyListMessages.frame(device.amfiReply)
            }
        }

        private func reply(_ fields: [String: PropertyListValue]) { outgoing += USBMux.message(fields, tag: 1) }
        private func result(_ number: Int64) { reply(["MessageType": .string("Result"), "Number": .integer(number)]) }

        private func answerUSBMux(_ message: [String: PropertyListValue]) {
            guard case .string(let kind)? = message["MessageType"] else { return result(1) }
            switch kind {
            case "ListDevices":
                reply(["DeviceList": .array(device.listed.enumerated().map { index, serial in
                    .dictionary(["DeviceID": .integer(Int64(index + 1)), "MessageType": .string("Attached"),
                                 "Properties": .dictionary(["ConnectionType": .string("USB"), "SerialNumber": .string(serial)])])
                })])
            case "ReadBUID":
                reply(["BUID": .string("BUID")])
            case "ReadPairRecord":
                guard case .string(let udid)? = message["PairRecordID"], let record = device.records[udid] else { return result(2) }
                reply(["PairRecordData": .data(record)])
            case "SavePairRecord":
                if device.savesTheRecord, case .string(let udid)? = message["PairRecordID"], case .data(let record)? = message["PairRecordData"] {
                    device.records[udid] = record
                }
                result(device.saveResult)
            case "Connect":
                result(0)
                switch message["PortNumber"] {
                case .integer(Int64(Lockdown.port.byteSwapped))?: mode = .lockdown
                case .integer(Int64(ScriptedDevice.amfiPort.byteSwapped))?: mode = .amfi
                default: break
                }
            default:
                result(1)
            }
        }

        private func answerLockdown(_ message: [String: PropertyListValue]) {
            guard case .string(let request)? = message["Request"] else { return }
            var reply: [String: PropertyListValue] = ["Request": .string(request)]
            switch request {
            case "GetValue":
                switch message["Key"] {
                case .string("DevicePublicKey")?: reply["Value"] = .data(device.devicePublicKey)
                case .string("WiFiAddress")?: reply["Value"] = .string("00:00:00:00:00:01")
                case .string("ProductVersion")?: reply["Value"] = .string("27.0.1")
                case .string("DeveloperModeStatus")?:
                    if let error = device.developerModeError {
                        reply["Error"] = .string(error)
                    } else if let status = device.developerMode {
                        reply["Value"] = status
                    } else {
                        reply["Error"] = .string("MissingValue")
                    }
                default: reply["Error"] = .string("MissingValue")
                }
            case "Pair":
                device.pairRequests.append(message)
                let answer = device.pairAnswers.count > 1 ? device.pairAnswers.removeFirst() : device.pairAnswers[0]
                switch answer {
                case "pending": reply["Error"] = .string("PairingDialogResponsePending")
                case "locked": reply["Error"] = .string("PasswordProtected")
                case "denied": reply["Error"] = .string("UserDeniedPairing")
                default:
                    if case .dictionary(let record)? = message["PairRecord"], case .string(let hostID)? = record["HostID"] { device.trustedHosts.insert(hostID) }
                    reply["EscrowBag"] = .data([1, 2, 3])
                }
                if device.usbmuxPairsAfter == device.pairRequests.count {
                    device.trustedHosts.insert("USBMUXD")
                    device.records[ScriptedDevice.udid] = ScriptedDevice.record(hostID: "USBMUXD")
                }
            case "StartSession":
                if let error = device.sessionError {
                    reply["Error"] = .string(error)
                    break
                }
                guard case .string(let hostID)? = message["HostID"], device.trustedHosts.contains(hostID) else {
                    reply["Error"] = .string("InvalidHostID")
                    break
                }
                reply["SessionID"] = .string("S")
                reply["EnableSessionSSL"] = .boolean(false)
            case "StartService":
                reply["Port"] = .integer(Int64(ScriptedDevice.amfiPort))
            default:
                reply["Error"] = .string("UnknownRequest")
            }
            outgoing += PropertyListMessages.frame(reply)
        }
    }

    static let amfiPort: UInt16 = 49_160
}

enum PairingCertificatesFixture {
    /// `openssl rsa -RSAPublicKey_out` of the test identity's key.
    static let pkcs1 = """
    -----BEGIN RSA PUBLIC KEY-----
    MIIBCgKCAQEAp7U0GOBUHch4sM0E8TTnWtlB7ISN20Fo9y8QceVhyiNCeC0/cXgo
    ZkerR/Z+k9hdPJxKnEiBtWyYJ63Xbobe8OzKX9zSQu0/op/YNUqVh1uo0j8bBVxk
    ZMwh3/v4ZxadtOvez8VqBfnX6SoPyG56jqRLjVn18gmE3IsKHwDct7zivWwKWvYC
    se9M4vjFX9rnvB2nlqGV3oINi0BPUsP35uMisbGfdzfyjE8ZPdBPqnQvGEmNlDaF
    j3Shj7AiAqdU4JHcK4yMdqu7Lvg4PrXsDcC+9z+hKs8Ik5yR6oSoFcMJiQq9iK5j
    eeJMVyFwcP1Dvn6vaiBgTX9O+Q+SZnSm7QIDAQAB
    -----END RSA PUBLIC KEY-----

    """
}
