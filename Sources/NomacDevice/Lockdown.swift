import Foundation
import NomacCore
import NomacSigning

/// lockdownd, the device's service on port 62078 that reports the device's values, opens
/// sessions with a paired host and starts services (docs/formats/lockdown.md). Each request is
/// a dictionary with `Label` and `Request`; the reply repeats `Request` and has `Error` when
/// it fails.
public enum Lockdown {
    public static let port: UInt16 = 62078
    static let label = "nomac"

    public struct Service: Equatable, Sendable {
        public let port: UInt16
        /// Whether the service's connection starts with a TLS handshake.
        public let usesTLS: Bool
    }

    public static func request(_ name: String, _ fields: [String: PropertyListValue] = [:]) -> [String: PropertyListValue] {
        fields.merging(["Label": .string(label), "Request": .string(name)]) { _, new in new }
    }

    /// What to do about lockdownd's errors (their names in libimobiledevice's and pymobiledevice3's
    /// error tables).
    static func hint(for error: String) -> String? {
        switch error {
        case "PasswordProtected": "the device is locked: unlock it and run the command again"
        case "PairingDialogResponsePending": "the device shows a Trust dialog: answer it on the device"
        case "UserDeniedPairing": "the device's user declined to trust this host"
        case "InvalidHostID": "the device no longer knows this host's pairing: unplug it, plug it in again and trust this host on the device"
        case "InvalidService": "the device does not offer this service (an older iOS, or a service only a mounted Developer Disk Image adds)"
        case "SessionInactive": "the lockdown session ended: run the command again"
        default: nil
        }
    }

    /// The reply to the request `name`, or lockdownd's error.
    public static func response(_ reply: [String: PropertyListValue], to name: String) throws -> [String: PropertyListValue] {
        if case .string(let error)? = reply["Error"] {
            throw NomacError("lockdownd refused \(name): \(error)", notes: hint(for: error).map { [$0] } ?? [])
        }
        guard reply["Request"] == .string(name) else {
            throw NomacError("lockdownd answered \(name) with \(reply["Request"].map { "\($0)" } ?? "no Request")")
        }
        return reply
    }
}

/// A client of lockdownd over a stream to port 62078.
public final class LockdownClient {
    public private(set) var stream: ByteStream

    public init(stream: ByteStream) { self.stream = stream }

    /// `com.apple.mobile.lockdown` from lockdownd itself.
    public func queryType() throws -> String {
        guard case .string(let type)? = try send("QueryType")["Type"] else { throw NomacError("lockdownd's QueryType reply has no Type") }
        return type
    }

    /// The value of `key` in `domain`, or every value of the domain without a key; before a
    /// session lockdownd answers only some of them.
    public func value(domain: String? = nil, key: String? = nil) throws -> PropertyListValue {
        var fields: [String: PropertyListValue] = [:]
        if let domain { fields["Domain"] = .string(domain) }
        if let key { fields["Key"] = .string(key) }
        guard let value = try send("GetValue", fields)["Value"] else { throw NomacError("lockdownd's GetValue reply has no Value") }
        return value
    }

    /// Starts a session as the paired host `hostID`; when lockdownd asks for it, the rest of the
    /// connection is TLS, which `secure` wraps around the stream.
    public func startSession(hostID: String, systemBUID: String, secure: (ByteStream) throws -> ByteStream) throws {
        let reply = try send("StartSession", ["HostID": .string(hostID), "SystemBUID": .string(systemBUID)])
        if reply["EnableSessionSSL"] == .boolean(true) { stream = try secure(stream) }
    }

    /// Starts the service `name`, which listens on the port of the reply for one connection.
    public func startService(_ name: String) throws -> Lockdown.Service {
        let reply = try send("StartService", ["Service": .string(name)])
        guard case .integer(let port)? = reply["Port"], let servicePort = UInt16(exactly: port) else {
            throw NomacError("lockdownd's StartService reply for \(name) has no Port")
        }
        return Lockdown.Service(port: servicePort, usesTLS: reply["EnableServiceSSL"] == .boolean(true))
    }

    private func send(_ name: String, _ fields: [String: PropertyListValue] = [:]) throws -> [String: PropertyListValue] {
        try PropertyListMessages.send(Lockdown.request(name, fields), on: stream)
        return try Lockdown.response(try PropertyListMessages.receive(from: stream, source: "lockdownd"), to: name)
    }
}
