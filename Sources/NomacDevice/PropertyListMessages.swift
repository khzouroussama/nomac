import Foundation
import NomacCore
import NomacPlist
import NomacSigning

/// A connection that carries a device protocol's bytes: a socket, or TLS over one.
public protocol ByteStream: AnyObject {
    func write(_ bytes: [UInt8]) throws
    /// Exactly `count` bytes.
    func read(_ count: Int) throws -> [UInt8]
}

extension StreamSocket: ByteStream {}

/// The framing of lockdownd and the services it starts (installation_proxy among them): a
/// big-endian 32-bit length, then a property list (libimobiledevice's
/// `property_list_service`, docs/formats/lockdown.md). nomac writes XML; replies may be XML
/// or binary.
public enum PropertyListMessages {
    static let maximumLength = 1 << 26

    public static func frame(_ message: [String: NomacSigning.PropertyListValue]) -> [UInt8] {
        let body = NomacSigning.PropertyListValue.xmlDocument(.dictionary(message))
        return withUnsafeBytes(of: UInt32(body.count).bigEndian, Array.init) + body
    }

    public static func send(_ message: [String: NomacSigning.PropertyListValue], on stream: ByteStream) throws {
        try stream.write(frame(message))
    }

    public static func receive(from stream: ByteStream, source: String) throws -> [String: NomacSigning.PropertyListValue] {
        let length = try stream.read(4).reduce(0) { $0 << 8 | Int($1) }
        guard length > 0, length <= maximumLength else { throw NomacError("\(source) sent a message of \(length) bytes") }
        return try dictionary(try stream.read(length), source: source)
    }

    /// A dictionary from an XML or binary property list.
    public static func dictionary(_ bytes: [UInt8], source: String) throws -> [String: NomacSigning.PropertyListValue] {
        let value = bytes.starts(with: Array("bplist00".utf8))
            ? converted(try BinaryPropertyList.value(from: bytes, path: source))
            : try NomacSigning.PropertyListValue.parseXML(Data(bytes), path: source)
        guard case .dictionary(let fields) = value else { throw NomacError("\(source) sent a property list that is not a dictionary") }
        return fields
    }

    private static func converted(_ value: NomacPlist.PropertyListValue) -> NomacSigning.PropertyListValue {
        switch value {
        case .string(let string): .string(string)
        case .integer(let integer): .integer(Int64(integer))
        case .real(let real): .real(real)
        case .boolean(let boolean): .boolean(boolean)
        case .date(let seconds): .date(ISO8601DateFormatter().string(from: Date(timeIntervalSinceReferenceDate: seconds)))
        case .data(let bytes): .data(bytes)
        case .array(let elements): .array(elements.map(converted))
        case .dictionary(let entries): .dictionary(entries.mapValues(converted))
        }
    }
}
