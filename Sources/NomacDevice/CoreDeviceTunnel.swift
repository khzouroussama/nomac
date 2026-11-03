import Foundation
import NomacCore

/// The CoreDevice tunnel lockdownd starts as `com.apple.internal.devicecompute.CoreDeviceProxy`
/// (iOS 17.4 and later, docs/formats/remotexpc.md): one `CDTunnel` handshake each way (the
/// magic, a big-endian 16-bit length, JSON), then IPv6 packets in which RemoteServiceDiscovery
/// listens on the server address.
public enum CoreDeviceTunnel {
    public static let serviceName = "com.apple.internal.devicecompute.CoreDeviceProxy"
    static let magic = Array("CDTunnel".utf8)
    /// The MTU pymobiledevice3 asks for over this service.
    public static let requestedMTU = 16_000

    public struct Parameters: Equatable, Sendable {
        public let clientAddress: String
        public let mtu: Int
        public let serverAddress: String
        public let serverRSDPort: UInt16
    }

    /// The client's request, its JSON as Python's `json.dumps` writes it for pymobiledevice3.
    public static func handshakeRequest(mtu: Int = requestedMTU) -> [UInt8] {
        packet(Array("{\"type\": \"clientHandshakeRequest\", \"mtu\": \(mtu)}".utf8))
    }

    static func packet(_ body: [UInt8]) -> [UInt8] {
        magic + withUnsafeBytes(of: UInt16(body.count).bigEndian, Array.init) + body
    }

    public static func handshake(on stream: ByteStream, mtu: Int = requestedMTU) throws -> Parameters {
        try stream.write(handshakeRequest(mtu: mtu))
        let header = try stream.read(magic.count + 2)
        guard header.starts(with: magic) else { throw NomacError("the CoreDevice tunnel did not answer with CDTunnel") }
        return try parameters(try stream.read(Int(header[magic.count]) << 8 | Int(header[magic.count + 1])))
    }

    static func parameters(_ body: [UInt8]) throws -> Parameters {
        guard let reply = try JSONSerialization.jsonObject(with: Data(body)) as? [String: Any],
              let client = reply["clientParameters"] as? [String: Any], let address = client["address"] as? String,
              let mtu = client["mtu"] as? Int, let server = reply["serverAddress"] as? String,
              let port = reply["serverRSDPort"] as? Int, let rsdPort = UInt16(exactly: port) else {
            throw NomacError("unexpected CoreDevice tunnel handshake: \(String(decoding: body, as: UTF8.self))")
        }
        return Parameters(clientAddress: address, mtu: mtu, serverAddress: server, serverRSDPort: rsdPort)
    }
}

/// RemoteServiceDiscovery, the first RemoteXPC peer in the tunnel: on connection it sends a
/// `Handshake` message with the device's `Properties` and its `Services`, each with its `Port`
/// (a string, as pymobiledevice3 reads it, or an integer).
public enum RemoteServiceDiscovery {
    public static func servicePorts(_ handshake: XPCObject) throws -> [String: UInt16] {
        guard handshake["MessageType"] == .string("Handshake"), case .dictionary(let services)? = handshake["Services"] else {
            throw NomacError("RemoteServiceDiscovery's first message is not a Handshake with Services")
        }
        var ports: [String: UInt16] = [:]
        for service in services {
            switch service.value["Port"] {
            case .string(let port)?: if let number = UInt16(port) { ports[service.key] = number }
            case .uint64(let port)?: if let number = UInt16(exactly: port) { ports[service.key] = number }
            case .int64(let port)?: if let number = UInt16(exactly: port) { ports[service.key] = number }
            default: break
            }
        }
        return ports
    }
}
