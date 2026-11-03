import Foundation
import NomacCore

/// An XPC object as RemoteXPC carries it (docs/formats/remotexpc.md): a little-endian 32-bit
/// type, then the object's bytes, strings and data padded to 4 bytes. Dictionaries keep their
/// entries in order.
public indirect enum XPCObject: Equatable, Sendable {
    case null
    case bool(Bool)
    case int64(Int64)
    case uint64(UInt64)
    case double(Double)
    /// Nanoseconds since 1970.
    case date(Int64)
    case data([UInt8])
    case string(String)
    case uuid([UInt8])
    case array([XPCObject])
    case dictionary([Entry])

    public struct Entry: Equatable, Sendable {
        public let key: String
        public let value: XPCObject

        public init(_ key: String, _ value: XPCObject) {
            self.key = key
            self.value = value
        }
    }

    enum Kind: UInt32 {
        case null = 0x1000
        case bool = 0x2000
        case int64 = 0x3000
        case uint64 = 0x4000
        case double = 0x5000
        case date = 0x7000
        case data = 0x8000
        case string = 0x9000
        case uuid = 0xa000
        case array = 0xe000
        case dictionary = 0xf000
    }

    /// The value of `key` in a dictionary.
    public subscript(key: String) -> XPCObject? {
        guard case .dictionary(let entries) = self else { return nil }
        return entries.first { $0.key == key }?.value
    }

    public func encoded() -> [UInt8] {
        switch self {
        case .null: Self.word(Kind.null.rawValue)
        case .bool(let value): Self.word(Kind.bool.rawValue) + Self.word(value ? 1 : 0)
        case .int64(let value): Self.word(Kind.int64.rawValue) + Self.littleEndian(UInt64(bitPattern: value))
        case .uint64(let value): Self.word(Kind.uint64.rawValue) + Self.littleEndian(value)
        case .double(let value): Self.word(Kind.double.rawValue) + Self.littleEndian(value.bitPattern)
        case .date(let value): Self.word(Kind.date.rawValue) + Self.littleEndian(UInt64(bitPattern: value))
        case .data(let bytes): Self.word(Kind.data.rawValue) + Self.word(UInt32(bytes.count)) + Self.padded(bytes)
        case .string(let string):
            Self.word(Kind.string.rawValue) + Self.word(UInt32(string.utf8.count + 1)) + Self.padded(Array(string.utf8) + [0])
        case .uuid(let bytes): Self.word(Kind.uuid.rawValue) + bytes
        case .array(let elements):
            Self.word(Kind.array.rawValue) + Self.sized(Self.word(UInt32(elements.count)) + elements.flatMap { $0.encoded() })
        case .dictionary(let entries):
            Self.word(Kind.dictionary.rawValue)
                + Self.sized(Self.word(UInt32(entries.count)) + entries.flatMap { Self.padded(Array($0.key.utf8) + [0]) + $0.value.encoded() })
        }
    }

    public static func decode(_ bytes: [UInt8]) throws -> XPCObject {
        var reader = Reader(bytes: bytes)
        return try reader.object()
    }

    static func word(_ value: UInt32) -> [UInt8] { withUnsafeBytes(of: value.littleEndian, Array.init) }

    static func littleEndian(_ value: UInt64) -> [UInt8] { withUnsafeBytes(of: value.littleEndian, Array.init) }

    static func padded(_ bytes: [UInt8]) -> [UInt8] { bytes + [UInt8](repeating: 0, count: (4 - bytes.count % 4) % 4) }

    /// A 32-bit byte count, then the bytes.
    static func sized(_ bytes: [UInt8]) -> [UInt8] { word(UInt32(bytes.count)) + bytes }

    struct Reader {
        let bytes: [UInt8]
        var offset = 0

        mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
            guard count >= 0, offset + count <= bytes.count else { throw NomacError("truncated XPC object at byte \(offset)") }
            defer { offset += count }
            return bytes[offset..<offset + count]
        }

        mutating func word() throws -> UInt32 { UInt32(truncatingIfNeeded: integer(try take(4))) }

        mutating func quad() throws -> UInt64 { integer(try take(8)) }

        /// `count` bytes and the padding to 4 after them.
        mutating func padded(_ count: Int) throws -> [UInt8] {
            let value = Array(try take(count))
            _ = try take((4 - count % 4) % 4)
            return value
        }

        mutating func cString() throws -> String {
            guard let end = bytes[offset...].firstIndex(of: 0) else { throw NomacError("unterminated XPC string at byte \(offset)") }
            return String(decoding: try padded(end - offset + 1).dropLast(), as: UTF8.self)
        }

        mutating func object() throws -> XPCObject {
            let type = try word()
            guard let kind = Kind(rawValue: type) else { throw NomacError("XPC object of type 0x\(String(type, radix: 16)) at byte \(offset - 4)") }
            switch kind {
            case .null: return .null
            case .bool: return .bool(try word() != 0)
            case .int64: return .int64(Int64(bitPattern: try quad()))
            case .uint64: return .uint64(try quad())
            case .double: return .double(Double(bitPattern: try quad()))
            case .date: return .date(Int64(bitPattern: try quad()))
            case .data: return .data(try padded(Int(try word())))
            case .string:
                let string = try padded(Int(try word()))
                return .string(String(decoding: string.prefix { $0 != 0 }, as: UTF8.self))
            case .uuid: return .uuid(Array(try take(16)))
            case .array:
                _ = try word()
                return .array(try (0..<Int(try word())).map { _ in try object() })
            case .dictionary:
                _ = try word()
                return .dictionary(try (0..<Int(try word())).map { _ in
                    let key = try cString()
                    return Entry(key, try object())
                })
            }
        }

        private func integer(_ slice: ArraySlice<UInt8>) -> UInt64 { slice.reversed().reduce(0) { $0 << 8 | UInt64($1) } }
    }
}

/// The frame of a RemoteXPC message: magic `0x29b00b92`, flags, the body's size and a message
/// identifier, then a body of magic `0x42133742`, protocol version 5 and one XPC object, or no
/// body.
public struct XPCMessage: Equatable, Sendable {
    public struct Flags: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let alwaysSet = Flags(rawValue: 0x1)
        public static let dataPresent = Flags(rawValue: 0x100)
        public static let wantingReply = Flags(rawValue: 0x10000)
        public static let reply = Flags(rawValue: 0x20000)
        public static let initHandshake = Flags(rawValue: 0x400000)
    }

    static let magic: UInt32 = 0x29b0_0b92
    static let bodyMagic: UInt32 = 0x4213_3742
    static let version: UInt32 = 5
    static let headerSize = 24

    public var flags: Flags
    public var messageID: UInt64
    public var payload: XPCObject?

    public init(flags: Flags, messageID: UInt64 = 0, payload: XPCObject? = nil) {
        self.flags = flags
        self.messageID = messageID
        self.payload = payload
    }

    public func encoded() -> [UInt8] {
        let body = payload.map { XPCObject.word(Self.bodyMagic) + XPCObject.word(Self.version) + $0.encoded() } ?? []
        return XPCObject.word(Self.magic) + XPCObject.word(flags.rawValue) + XPCObject.littleEndian(UInt64(body.count))
            + XPCObject.littleEndian(messageID) + body
    }

    /// The size of the message at the start of `bytes`, once its header is there.
    static func size(_ bytes: ArraySlice<UInt8>) throws -> Int? {
        guard bytes.count >= headerSize else { return nil }
        var reader = XPCObject.Reader(bytes: Array(bytes.prefix(headerSize)))
        guard try reader.word() == magic else { throw NomacError("RemoteXPC message without its magic") }
        _ = try reader.word()
        let size = try reader.quad()
        guard size <= 1 << 26 else { throw NomacError("RemoteXPC message of \(size) bytes") }
        return headerSize + Int(size)
    }

    public static func decode(_ bytes: [UInt8]) throws -> XPCMessage {
        var reader = XPCObject.Reader(bytes: bytes)
        guard try reader.word() == magic else { throw NomacError("RemoteXPC message without its magic") }
        let flags = Flags(rawValue: try reader.word())
        let size = Int(try reader.quad())
        let messageID = try reader.quad()
        guard size > 0 else { return XPCMessage(flags: flags, messageID: messageID) }
        guard try reader.word() == bodyMagic, try reader.word() == version else {
            throw NomacError("RemoteXPC body without its magic and version 5")
        }
        return XPCMessage(flags: flags, messageID: messageID, payload: try reader.object())
    }
}
