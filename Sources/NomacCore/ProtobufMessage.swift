import Foundation

/// A protocol buffer message as a list of its fields in the order they were read, each with its
/// raw payload, so that a message written again keeps every field nomac does not interpret
/// (the wire format: protobuf.dev/programming-guides/encoding).
public struct ProtobufMessage: Sendable, Equatable {
    public enum WireType: UInt8, Sendable {
        case varint = 0, fixed64 = 1, lengthDelimited = 2, fixed32 = 5
    }

    public struct Field: Sendable, Equatable {
        public var number: Int
        public var wireType: WireType
        /// The value's bytes: a varint's or a fixed value's encoding, a length-delimited
        /// field's contents without the length.
        public var payload: [UInt8]

        public init(number: Int, wireType: WireType, payload: [UInt8]) {
            self.number = number
            self.wireType = wireType
            self.payload = payload
        }
    }

    public var fields: [Field]

    public init(fields: [Field] = []) {
        self.fields = fields
    }

    public init(bytes: [UInt8]) throws {
        var reader = Reader(bytes: bytes[...])
        fields = []
        while !reader.isAtEnd {
            let key = try reader.varint()
            guard let wireType = WireType(rawValue: UInt8(key & 7)), key >> 3 > 0 else {
                throw NomacError("malformed protocol buffer: field key \(key)")
            }
            let payload: [UInt8]
            switch wireType {
            case .varint:
                let start = reader.offset
                _ = try reader.varint()
                payload = Array(bytes[start..<reader.offset])
            case .fixed64:
                payload = try reader.take(8)
            case .fixed32:
                payload = try reader.take(4)
            case .lengthDelimited:
                payload = try reader.take(Int(try reader.varint()))
            }
            fields.append(Field(number: Int(key >> 3), wireType: wireType, payload: payload))
        }
    }

    public var bytes: [UInt8] {
        var out: [UInt8] = []
        for field in fields {
            Self.appendVarint(UInt64(field.number) << 3 | UInt64(field.wireType.rawValue), to: &out)
            if field.wireType == .lengthDelimited {
                Self.appendVarint(UInt64(field.payload.count), to: &out)
            }
            out += field.payload
        }
        return out
    }

    public func all(_ number: Int) -> [Field] {
        fields.filter { $0.number == number }
    }

    public func first(_ number: Int) -> Field? {
        fields.first { $0.number == number }
    }

    public func has(_ number: Int) -> Bool {
        first(number) != nil
    }

    public func message(_ number: Int) throws -> ProtobufMessage? {
        try first(number).map { try ProtobufMessage(bytes: $0.payload) }
    }

    public func messages(_ number: Int) throws -> [ProtobufMessage] {
        try all(number).map { try ProtobufMessage(bytes: $0.payload) }
    }

    public func string(_ number: Int) -> String? {
        first(number).map { String(decoding: $0.payload, as: UTF8.self) }
    }

    public func strings(_ number: Int) -> [String] {
        all(number).map { String(decoding: $0.payload, as: UTF8.self) }
    }

    /// The last value of a varint field, as protocol buffers read a repeated scalar into a
    /// singular one; 0 when absent.
    public func integer(_ number: Int) throws -> Int64 {
        guard let field = all(number).last else { return 0 }
        var reader = Reader(bytes: field.payload[...])
        return Int64(bitPattern: try reader.varint())
    }

    public func double(_ number: Int) -> Double {
        guard let field = all(number).last, field.wireType == .fixed64 else { return 0 }
        return Double(bitPattern: field.payload.reversed().reduce(0) { $0 << 8 | UInt64($1) })
    }

    /// A repeated varint field, packed or not.
    public func integers(_ number: Int) throws -> [Int64] {
        var values: [Int64] = []
        for field in all(number) {
            var reader = Reader(bytes: field.payload[...])
            if field.wireType == .lengthDelimited {
                while !reader.isAtEnd { values.append(Int64(bitPattern: try reader.varint())) }
            } else {
                values.append(Int64(bitPattern: try reader.varint()))
            }
        }
        return values
    }

    /// Sets the message field `number` to `message`, after the fields of lower numbers, as a
    /// message protocol buffers' C++ runtime writes keeps its fields in number order.
    public mutating func set(_ number: Int, message: ProtobufMessage) {
        let field = Field(number: number, wireType: .lengthDelimited, payload: message.bytes)
        if let index = fields.firstIndex(where: { $0.number == number }) {
            fields[index] = field
        } else {
            fields.insert(field, at: fields.firstIndex { $0.number > number } ?? fields.count)
        }
    }

    public static func appendVarint(_ value: UInt64, to out: inout [UInt8]) {
        var value = value
        while value >= 0x80 {
            out.append(UInt8(value & 0x7F) | 0x80)
            value >>= 7
        }
        out.append(UInt8(value))
    }

    struct Reader {
        let bytes: ArraySlice<UInt8>
        var offset: Int

        init(bytes: ArraySlice<UInt8>) {
            self.bytes = bytes
            offset = bytes.startIndex
        }

        var isAtEnd: Bool { offset >= bytes.endIndex }

        mutating func varint() throws -> UInt64 {
            var value: UInt64 = 0
            var shift: UInt64 = 0
            while true {
                guard offset < bytes.endIndex, shift < 64 else { throw NomacError("malformed protocol buffer: truncated varint") }
                let byte = bytes[offset]
                offset += 1
                value |= UInt64(byte & 0x7F) << shift
                if byte < 0x80 { return value }
                shift += 7
            }
        }

        mutating func take(_ count: Int) throws -> [UInt8] {
            guard count >= 0, offset + count <= bytes.endIndex else { throw NomacError("malformed protocol buffer: truncated field") }
            defer { offset += count }
            return Array(bytes[offset..<offset + count])
        }
    }
}
