import Foundation
import NomacCore

extension BinaryPropertyList {
    /// The property list of a `bplist00` file, as docs/formats/property-lists.md "Binary" lays it
    /// out (the layout of Core Foundation's open-source `CFBinaryPList.c`): the trailer's offset
    /// and reference sizes, object count, top object and offset table, then each object by its
    /// marker. UIDs, sets, nulls and integers over 64 bits, which Info.plists do not hold, are
    /// refused.
    public static func value(from bytes: [UInt8], path: String) throws -> PropertyListValue {
        guard bytes.count >= 8 + 1 + 32, bytes.starts(with: Array("bplist00".utf8)) else {
            throw NomacError("not a binary property list", path: path)
        }
        let trailer = bytes.count - 32
        var reader = Reader(bytes: bytes, path: path, offsetSize: Int(bytes[trailer + 6]), referenceSize: Int(bytes[trailer + 7]))
        reader.objectCount = try reader.unsigned(at: trailer + 8, size: 8)
        reader.tableOffset = try reader.unsigned(at: trailer + 24, size: 8)
        return try reader.object(reader.unsigned(at: trailer + 16, size: 8), depth: 0)
    }

    /// The objects of a `bplist00` file by index, the top one first in the returned order's
    /// place `top`: for rewriting it with the sharing it was read with.
    public static func objects(from bytes: [UInt8], path: String) throws -> (objects: [Object], top: Int) {
        guard bytes.count >= 8 + 1 + 32, bytes.starts(with: Array("bplist00".utf8)) else {
            throw NomacError("not a binary property list", path: path)
        }
        let trailer = bytes.count - 32
        var reader = Reader(bytes: bytes, path: path, offsetSize: Int(bytes[trailer + 6]), referenceSize: Int(bytes[trailer + 7]))
        reader.objectCount = try reader.unsigned(at: trailer + 8, size: 8)
        reader.tableOffset = try reader.unsigned(at: trailer + 24, size: 8)
        return (try (0..<reader.objectCount).map { try reader.flatObject($0) }, try reader.unsigned(at: trailer + 16, size: 8))
    }

    private struct Reader {
        let bytes: [UInt8]
        let path: String
        let offsetSize: Int
        let referenceSize: Int
        var objectCount = 0
        var tableOffset = 0

        var malformed: NomacError { NomacError("malformed binary property list", path: path) }

        /// A big-endian unsigned number of 1 to 8 bytes that fits in an `Int`.
        func unsigned(at offset: Int, size: Int) throws -> Int {
            let value = try bigEndian(at: offset, size: size)
            guard value <= UInt64(Int.max) else { throw malformed }
            return Int(value)
        }

        func bigEndian(at offset: Int, size: Int) throws -> UInt64 {
            guard (1...8).contains(size), offset >= 0, offset + size <= bytes.count else { throw malformed }
            return bytes[offset..<(offset + size)].reduce(0) { $0 << 8 | UInt64($1) }
        }

        func object(_ index: Int, depth: Int) throws -> PropertyListValue {
            guard index < objectCount, depth < 512 else { throw malformed }
            let start = try unsigned(at: tableOffset + offsetSize * index, size: offsetSize)
            guard start < bytes.count else { throw malformed }
            let marker = bytes[start], low = Int(marker & 0x0f)
            switch marker >> 4 {
            case 0x0 where marker == 0x08 || marker == 0x09:
                return .boolean(marker == 0x09)
            case 0x1 where low <= 3:
                let size = 1 << low, value = try bigEndian(at: start + 1, size: size)
                // 8-byte integers are signed; shorter ones are not.
                return .integer(size == 8 ? Int(Int64(bitPattern: value)) : Int(value))
            case 0x2 where low == 2:
                return .real(Double(Float(bitPattern: UInt32(try bigEndian(at: start + 1, size: 4)))))
            case 0x2 where low == 3:
                return .real(Double(bitPattern: try bigEndian(at: start + 1, size: 8)))
            case 0x3 where marker == 0x33:
                return .date(Double(bitPattern: try bigEndian(at: start + 1, size: 8)))
            case 0x4:
                let (count, contents) = try length(start)
                return .data(try slice(contents, count))
            case 0x5:
                let (count, contents) = try length(start)
                return .string(String(decoding: try slice(contents, count), as: UTF8.self))
            case 0x6:
                let (count, contents) = try length(start)
                let units = try slice(contents, 2 * count)
                return .string(String(decoding: stride(from: 0, to: units.count, by: 2).map { UInt16(units[$0]) << 8 | UInt16(units[$0 + 1]) },
                                      as: UTF16.self))
            case 0xa:
                let (count, contents) = try length(start)
                return .array(try references(contents, count).map { try object($0, depth: depth + 1) })
            case 0xd:
                let (count, contents) = try length(start)
                let keys = try references(contents, count), values = try references(contents + referenceSize * count, count)
                var entries: [String: PropertyListValue] = [:]
                for (key, value) in zip(keys, values) {
                    guard case .string(let name) = try object(key, depth: depth + 1) else { throw malformed }
                    entries[name] = try object(value, depth: depth + 1)
                }
                return .dictionary(entries)
            default:
                throw NomacError(String(format: "binary property list object 0x%02x is not supported", marker), path: path)
            }
        }

        /// Object `index` with its references as indexes.
        func flatObject(_ index: Int) throws -> Object {
            let start = try unsigned(at: tableOffset + offsetSize * index, size: offsetSize)
            guard start < bytes.count else { throw malformed }
            switch bytes[start] >> 4 {
            case 0x8:
                return .uid(try unsigned(at: start + 1, size: Int(bytes[start] & 0x0f) + 1))
            case 0xa:
                let (count, contents) = try length(start)
                return .array(try references(contents, count))
            case 0xd:
                let (count, contents) = try length(start)
                return .dictionary(keys: try references(contents, count), values: try references(contents + referenceSize * count, count))
            default:
                switch try object(index, depth: 0) {
                case .boolean(let value): return .boolean(value)
                case .integer(let value): return .integer(value)
                case .real(let value): return .real(value)
                case .date(let value): return .date(value)
                case .data(let value): return .data(value)
                case .string(let value): return .string(value)
                case .array, .dictionary: throw malformed
                }
            }
        }

        /// A count from the marker's low four bits, or from the integer object after it when
        /// they are all set, and where the contents start.
        func length(_ start: Int) throws -> (count: Int, contents: Int) {
            let low = Int(bytes[start] & 0x0f)
            guard low == 0x0f else { return (low, start + 1) }
            guard start + 1 < bytes.count, bytes[start + 1] >> 4 == 0x1, bytes[start + 1] & 0x0f <= 3 else { throw malformed }
            let size = 1 << Int(bytes[start + 1] & 0x0f)
            return (try unsigned(at: start + 2, size: size), start + 2 + size)
        }

        func slice(_ start: Int, _ count: Int) throws -> [UInt8] {
            guard count >= 0, start + count <= bytes.count else { throw malformed }
            return Array(bytes[start..<(start + count)])
        }

        func references(_ start: Int, _ count: Int) throws -> [Int] {
            guard start + referenceSize * count <= bytes.count else { throw malformed }
            return try (0..<count).map { try unsigned(at: start + referenceSize * $0, size: referenceSize) }
        }
    }
}
