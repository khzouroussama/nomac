import Foundation
import NomacCore

/// What `.symbols` files need of a thin Mach-O file (a dSYM's DWARF file or one slice of it):
/// its segments and sections, `LC_UUID` and the symbol table, as `<mach-o/loader.h>`,
/// `<mach-o/nlist.h>` and `<mach-o/fat.h>` lay them out, 64-bit or 32-bit (arm64_32).
struct MachOFile {
    struct Section {
        let segment: String
        let name: String
        let address: UInt64
        let size: UInt64
        let offset: Int
        let flags: UInt32
    }

    struct Segment {
        let name: String
        let address: UInt64
        let size: UInt64
        let sections: [Section]
    }

    /// An `nlist_64` or `nlist` entry, with its position in the symbol table.
    struct Symbol {
        let name: [UInt8]
        /// `n_strx`, the name's offset in the string table.
        let nameOffset: UInt32
        let type: UInt8
        let value: UInt64
        let index: Int
    }

    let bytes: [UInt8]
    let is64Bit: Bool
    let cpuType: UInt32
    let cpuSubtype: UInt32
    let segments: [Segment]
    let uuid: [UInt8]
    let symbols: [Symbol]

    /// The thin files of `bytes`: itself, or each slice of a universal file in header order.
    static func slices(bytes: [UInt8], path: String) throws -> [MachOFile] {
        guard bytes.count >= 8, bytes[0..<4] == [0xca, 0xfe, 0xba, 0xbe] else { return [try MachOFile(bytes: bytes, path: path)] }
        func bigEndian(_ index: Int) -> Int { (0..<4).reduce(0) { $0 << 8 | Int(bytes[index + $1]) } }
        return try (0..<bigEndian(4)).map { index in
            let offset = bigEndian(8 + 20 * index + 8), size = bigEndian(8 + 20 * index + 12)
            guard offset + size <= bytes.count else { throw NomacError("malformed universal file", path: path) }
            return try MachOFile(bytes: Array(bytes[offset..<(offset + size)]), path: path)
        }
    }

    init(bytes: [UInt8], path: String) throws {
        var reader = ByteReader(bytes)
        guard bytes.count >= 28, [0xfeed_facf, 0xfeed_face].contains(reader.u32(at: 0)) else { throw NomacError("not a Mach-O file", path: path) }
        let wide = reader.u32(at: 0) == 0xfeed_facf
        is64Bit = wide
        func word(_ reader: inout ByteReader) -> UInt64 { wide ? reader.u64() : UInt64(reader.u32()) }
        self.bytes = bytes
        cpuType = reader.u32(at: 4)
        cpuSubtype = reader.u32(at: 8)
        let commandCount = Int(reader.u32(at: 16))
        reader.offset = wide ? 32 : 28
        var segments: [Segment] = []
        var uuid: [UInt8]?
        var symbolTable: (offset: Int, count: Int, strings: Int)?
        for _ in 0..<commandCount {
            let start = reader.offset
            let command = reader.u32(), size = Int(reader.u32())
            switch command {
            case 0x19, 0x1:
                let name = reader.name()
                let address = word(&reader), vmSize = word(&reader)
                let sectionCount = Int(reader.u32(at: start + (wide ? 64 : 48)))
                var sections: [Section] = []
                for index in 0..<sectionCount {
                    reader.offset = wide ? start + 72 + 80 * index : start + 56 + 68 * index
                    let sectionName = reader.name(), segmentName = reader.name()
                    let sectionAddress = word(&reader), sectionSize = word(&reader)
                    let offset = Int(reader.u32())
                    reader.offset += 12
                    sections.append(Section(segment: segmentName, name: sectionName, address: sectionAddress, size: sectionSize,
                                            offset: offset, flags: reader.u32()))
                }
                segments.append(Segment(name: name, address: address, size: vmSize, sections: sections))
            case 0x1b:
                uuid = Array(bytes[(start + 8)..<(start + 24)])
            case 0x2:
                symbolTable = (Int(reader.u32()), Int(reader.u32()), Int(reader.u32()))
            default:
                break
            }
            reader.offset = start + size
        }
        guard let uuid else { throw NomacError("no LC_UUID", path: path) }
        self.segments = segments
        self.uuid = uuid
        var symbols: [Symbol] = []
        if let symbolTable {
            for index in 0..<symbolTable.count {
                let entry = symbolTable.offset + (wide ? 16 : 12) * index
                let nameOffset = reader.u32(at: entry)
                let name = ByteReader(bytes).cString(at: symbolTable.strings + Int(nameOffset))
                let value = wide ? reader.u64(at: entry + 8) : UInt64(reader.u32(at: entry + 8))
                symbols.append(Symbol(name: name, nameOffset: nameOffset, type: bytes[entry + 4], value: value, index: index))
            }
        }
        self.symbols = symbols
    }

    var sections: [Section] { segments.flatMap(\.sections) }

    /// The contents of a section, empty when the file has none of that name.
    func contents(segment: String, section: String) -> [UInt8] {
        guard let found = sections.first(where: { $0.segment == segment && $0.name == section }), found.size > 0 else { return [] }
        return Array(bytes[found.offset..<(found.offset + Int(found.size))])
    }
}

/// Little-endian reads from a byte array, with LEB128 and C strings.
struct ByteReader {
    let bytes: [UInt8]
    var offset = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    func u16(at index: Int) -> UInt16 { UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8 }
    func u32(at index: Int) -> UInt32 { (0..<4).reduce(0) { $0 | UInt32(bytes[index + $1]) << (8 * UInt32($1)) } }
    func u64(at index: Int) -> UInt64 { (0..<8).reduce(0) { $0 | UInt64(bytes[index + $1]) << (8 * UInt64($1)) } }

    func cString(at index: Int) -> [UInt8] {
        var end = index
        while end < bytes.count, bytes[end] != 0 { end += 1 }
        return Array(bytes[index..<end])
    }

    mutating func u8() -> UInt8 { defer { offset += 1 }; return bytes[offset] }
    mutating func u16() -> UInt16 { defer { offset += 2 }; return u16(at: offset) }
    mutating func u32() -> UInt32 { defer { offset += 4 }; return u32(at: offset) }
    mutating func u64() -> UInt64 { defer { offset += 8 }; return u64(at: offset) }

    mutating func unsigned(_ count: Int) -> UInt64 {
        defer { offset += count }
        return (0..<count).reduce(0) { $0 | UInt64(bytes[offset + $1]) << (8 * UInt64($1)) }
    }

    mutating func uleb() -> UInt64 {
        var result: UInt64 = 0, shift: UInt64 = 0
        while true {
            let byte = u8()
            if shift < 64 { result |= UInt64(byte & 0x7f) << shift }
            shift += 7
            if byte < 0x80 { return result }
        }
    }

    mutating func sleb() -> Int64 {
        var result: Int64 = 0, shift: Int64 = 0, byte: UInt8 = 0
        repeat {
            byte = u8()
            if shift < 64 { result |= Int64(byte & 0x7f) << shift }
            shift += 7
        } while byte >= 0x80
        if shift < 64, byte & 0x40 != 0 { result |= -(Int64(1) << shift) }
        return result
    }

    mutating func cString() -> [UInt8] {
        let string = cString(at: offset)
        offset += string.count + 1
        return string
    }

    mutating func bytes(_ count: Int) -> [UInt8] {
        defer { offset += count }
        return Array(bytes[offset..<(offset + count)])
    }

    /// A 16-byte, NUL-padded name.
    mutating func name() -> String {
        defer { offset += 16 }
        return String(decoding: bytes[offset..<(offset + 16)].prefix { $0 != 0 }, as: UTF8.self)
    }
}
