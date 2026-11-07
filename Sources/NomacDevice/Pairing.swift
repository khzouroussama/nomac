import Foundation
import NomacCore
import NomacSigning

/// Pairing this host with a device through usbmuxd: the requests of libimobiledevice's
/// `idevicepair pair`, recorded against a scripted device (`first_run_experiments.py` `pair-reference`),
/// and its pair record (docs/formats/lockdown.md "Pairing"). On Linux, usbmuxd itself pairs after
/// the Trust dialog (`preflight.c`), so a record it saved first counts.
public enum Pairing {
    public enum Outcome: Equatable, Sendable {
        case alreadyPaired
        case paired
    }

    enum Answer: Equatable {
        case paired(escrowBag: [UInt8]?)
        case waitingForTrust
        case locked
    }

    /// Apple's page on the dialog (support.apple.com/109054): declining keeps the dialog coming back
    /// at each connection, and Reset Location & Privacy forgets the decision.
    static let deniedNote = "the device's user declined to trust this host: unplug it and plug it in again for the dialog to come back; to forget an earlier decision, on the device: Settings > General > Transfer or Reset iPhone > Reset > Reset Location & Privacy"

    static func request(record: [String: PropertyListValue]) -> [String: PropertyListValue] {
        Lockdown.request("Pair", [
            "PairRecord": .dictionary(record),
            "ProtocolVersion": .string("2"),
            "PairingOptions": .dictionary(["ExtendedPairingErrors": .boolean(true)]),
        ])
    }

    static func answer(_ reply: [String: PropertyListValue]) throws -> Answer {
        if case .string(let error)? = reply["Error"] {
            switch error {
            case "PairingDialogResponsePending": return .waitingForTrust
            case "PasswordProtected": return .locked
            default: break
            }
        }
        let fields = try Lockdown.response(reply, to: "Pair")
        if case .data(let escrowBag)? = fields["EscrowBag"] { return .paired(escrowBag: escrowBag) }
        return .paired(escrowBag: nil)
    }

    /// The fields of the pair record the device sees, and what the host adds to keep it.
    static func record(_ certificates: PairingCertificates, hostID: String, systemBUID: String) -> [String: PropertyListValue] {
        [
            "DeviceCertificate": .data(certificates.deviceCertificate),
            "HostCertificate": .data(certificates.hostCertificate),
            "RootCertificate": .data(certificates.rootCertificate),
            "HostID": .string(hostID),
            "SystemBUID": .string(systemBUID),
        ]
    }

    /// Whether a session starts with usbmuxd's record. No record, a device that does not know it and
    /// a refused TLS handshake mean not paired, as usbmuxd's preflight and pymobiledevice3 read them;
    /// anything else (a locked device) is no reason to replace a record, and is thrown.
    static func sessionStarts(usbmux: USBMuxClient, udid: String) throws -> Bool {
        do {
            _ = try DeviceSession(usbmux: usbmux, udid: udid)
            return true
        } catch let error as NomacError where ["usbmuxd holds no pair record", "the TLS handshake", "the pair record"].contains(where: error.message.hasPrefix) || error.message.hasSuffix(": InvalidHostID") {
            return false
        }
    }

    /// Pairs with the device `udid`, unless a session already starts with usbmuxd's record. Waits up
    /// to `timeout` seconds for the Trust dialog's answer and for the device to be unlocked, asking
    /// every second as pymobiledevice3 does. Between attempts it looks for a record first: on Linux
    /// usbmuxd pairs as soon as the user taps Trust (`preflight.c`), and pairing again would only
    /// replace that. The device may be unplugged and plugged in meanwhile, under a new device ID.
    public static func pair(usbmux: USBMuxClient, udid: String, timeout: TimeInterval = 120, at date: () -> Date = Date.init, wait: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }, progress: (String) -> Void) throws -> Outcome {
        let device = try usbmux.device(udid: udid)
        if try sessionStarts(usbmux: usbmux, udid: device.serialNumber) { return .alreadyPaired }
        let lockdown = LockdownClient(stream: try usbmux.connect(deviceID: device.deviceID, port: Lockdown.port))
        guard case .data(let publicKey) = try lockdown.value(key: "DevicePublicKey") else { throw NomacError("lockdownd's DevicePublicKey is not data") }
        let wiFiAddress = try? lockdown.value(key: "WiFiAddress")
        let certificates = try PairingCertificates(devicePublicKey: publicKey, at: date())
        let sent = record(certificates, hostID: UUID().uuidString, systemBUID: try usbmux.systemBUID())
        let deadline = date().addingTimeInterval(timeout)
        var said: Set<String> = []
        func say(_ line: String) { if said.insert(line).inserted { progress(line) } }
        var attempted = false
        while true {
            if attempted {
                guard date() < deadline else {
                    throw NomacError("the device did not answer the pairing in \(Int(timeout)) seconds", notes: [
                        "unlock the device, and tap Trust when it asks; if no dialog shows, unplug it, plug it in again and run 'nomac device pair --device \(device.serialNumber)'",
                    ])
                }
                wait(1)
                if (try? sessionStarts(usbmux: usbmux, udid: device.serialNumber)) == true { return .paired }
            }
            attempted = true
            let current: USBMux.Device
            let answer: Answer
            do {
                current = try usbmux.device(udid: device.serialNumber)
                answer = try LockdownClient(stream: try usbmux.connect(deviceID: current.deviceID, port: Lockdown.port)).pair(record: sent)
            } catch let error as NomacError where error.message.hasPrefix("usbmuxd sees no device") || error.message.hasPrefix("usbmuxd refused Connect") || error.message.hasPrefix("connection closed") {
                say("waiting for the device to come back: plug it in and unlock it")
                continue
            }
            switch answer {
            case .paired(let escrowBag):
                var kept = sent
                kept["HostPrivateKey"] = .data(certificates.hostPrivateKey)
                kept["RootPrivateKey"] = .data(certificates.rootPrivateKey)
                if let escrowBag { kept["EscrowBag"] = .data(escrowBag) }
                if let wiFiAddress { kept["WiFiMACAddress"] = wiFiAddress }
                try usbmux.savePairRecord(udid: device.serialNumber, deviceID: current.deviceID, record: PropertyListValue.xmlDocument(.dictionary(kept)))
                // usbmuxd may be saving its own pairing at this moment; whichever is last serves.
                for _ in 0..<5 {
                    if (try? sessionStarts(usbmux: usbmux, udid: device.serialNumber)) == true { return .paired }
                    wait(1)
                }
                throw NomacError("the device accepted the pairing but no session starts with the record usbmuxd keeps", notes: [
                    "run 'nomac device pair --device \(device.serialNumber)' again; if this stays, check that usbmuxd may write to /var/lib/lockdown",
                ])
            case .waitingForTrust:
                say("waiting for you to tap Trust on the device and enter its passcode")
            case .locked:
                say("waiting for you to unlock the device")
            }
        }
    }
}
