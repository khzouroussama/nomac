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

    /// Pairs with the device `udid`, unless a session already starts with usbmuxd's record. Waits up
    /// to `timeout` seconds for the Trust dialog's answer and for the device to be unlocked, asking
    /// every second as pymobiledevice3 does.
    public static func pair(usbmux: USBMuxClient, udid: String, timeout: TimeInterval = 120, at date: () -> Date = Date.init, wait: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }, progress: (String) -> Void) throws -> Outcome {
        let device = try usbmux.device(udid: udid)
        func sessionStarts() -> Bool { (try? DeviceSession(usbmux: usbmux, udid: device.serialNumber)) != nil }
        if sessionStarts() { return .alreadyPaired }
        let lockdown = LockdownClient(stream: try usbmux.connect(deviceID: device.deviceID, port: Lockdown.port))
        guard case .data(let publicKey) = try lockdown.value(key: "DevicePublicKey") else { throw NomacError("lockdownd's DevicePublicKey is not data") }
        let wiFiAddress = try? lockdown.value(key: "WiFiAddress")
        let hostID = UUID().uuidString
        let certificates = try PairingCertificates(devicePublicKey: publicKey, at: date())
        let sent = record(certificates, hostID: hostID, systemBUID: try usbmux.systemBUID())
        let deadline = date().addingTimeInterval(timeout)
        var said: Set<String> = []
        func say(_ line: String) { if said.insert(line).inserted { progress(line) } }
        while true {
            switch try LockdownClient(stream: try usbmux.connect(deviceID: device.deviceID, port: Lockdown.port)).pair(record: sent) {
            case .paired(let escrowBag):
                var kept = sent
                kept["HostPrivateKey"] = .data(certificates.hostPrivateKey)
                kept["RootPrivateKey"] = .data(certificates.rootPrivateKey)
                if let escrowBag { kept["EscrowBag"] = .data(escrowBag) }
                if let wiFiAddress { kept["WiFiMACAddress"] = wiFiAddress }
                try usbmux.savePairRecord(udid: device.serialNumber, deviceID: device.deviceID, record: PropertyListValue.xmlDocument(.dictionary(kept)))
                guard sessionStarts() else {
                    throw NomacError("the device accepted the pairing but no session starts with the record usbmuxd keeps", notes: [
                        "usbmuxd may not have saved it: check that it may write to /var/lib/lockdown, then run 'nomac device pair --device \(device.serialNumber)' again",
                    ])
                }
                return .paired
            case .waitingForTrust:
                say("waiting for you to tap Trust on the device and enter its passcode")
            case .locked:
                say("waiting for you to unlock the device")
            }
            if sessionStarts() { return .paired }
            guard date() < deadline else {
                throw NomacError("the device did not answer the pairing in \(Int(timeout)) seconds", notes: [
                    "unlock the device, and tap Trust when it asks; if no dialog shows, unplug it, plug it in again and run 'nomac device pair --device \(device.serialNumber)'",
                ])
            }
            wait(1)
        }
    }
}
