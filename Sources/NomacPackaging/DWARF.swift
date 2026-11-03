import Foundation
import NomacCore

/// The parts of a dSYM's DWARF (versions 4 and 5, as the DWARF 5 standard and its version 4
/// describe them) that `.symbols` files hold: compile units, their entries and attributes,
/// address ranges and line tables.
final class DWARF {
    let info, abbreviations, strings, stringOffsets, addresses, lines, lineStrings, rangeLists, ranges: [UInt8]
    private(set) var units: [Unit] = []
    /// Every entry by its offset in `__debug_info`, for references across units.
    var entries: [Int: Entry] = [:]

    init(_ file: MachOFile, path: String) throws {
        func section(_ name: String) -> [UInt8] { file.contents(segment: "__DWARF", section: name) }
        info = section("__debug_info")
        abbreviations = section("__debug_abbrev")
        strings = section("__debug_str")
        stringOffsets = section("__debug_str_offs")
        addresses = section("__debug_addr")
        lines = section("__debug_line")
        lineStrings = section("__debug_line_str")
        rangeLists = section("__debug_rnglists")
        ranges = section("__debug_ranges")
        var offset = 0
        while offset + 11 <= info.count {
            let unit = try Unit(dwarf: self, offset: offset, path: path)
            units.append(unit)
            offset = unit.end
        }
    }

    enum Value {
        case unsigned(UInt64)
        case signed(Int64)
        case block([UInt8])
        case string([UInt8])
    }

    struct Attribute {
        let form: UInt64
        let value: Value

        var unsigned: UInt64 {
            switch value {
            case .unsigned(let number): number
            case .signed(let number): UInt64(bitPattern: number)
            case .block, .string: 0
            }
        }
    }

    final class Entry {
        let offset: Int
        let tag: UInt64
        var attributes: [UInt64: Attribute] = [:]
        var children: [Entry] = []
        unowned let unit: Unit

        init(offset: Int, tag: UInt64, unit: Unit) {
            self.offset = offset
            self.tag = tag
            self.unit = unit
        }
    }

    final class Unit {
        unowned let dwarf: DWARF
        let offset: Int
        let end: Int
        let version: UInt16
        /// The size of an address: 8, or 4 for arm64_32.
        let addressSize: Int
        private(set) var root: Entry!
        private var stringBase = 8
        private var addressBase = 8
        private var rangeListBase = 12

        init(dwarf: DWARF, offset: Int, path: String) throws {
            self.dwarf = dwarf
            self.offset = offset
            var reader = ByteReader(dwarf.info)
            reader.offset = offset
            let length = Int(reader.u32())
            guard length < 0xffff_fff0 else { throw NomacError("64-bit DWARF is not supported", path: path) }
            end = offset + 4 + length
            version = reader.u16()
            let abbreviationOffset: Int
            if version >= 5 {
                reader.offset += 1
                addressSize = Int(reader.u8())
                abbreviationOffset = Int(reader.u32())
            } else {
                abbreviationOffset = Int(reader.u32())
                addressSize = Int(reader.u8())
            }
            let abbreviations = try Self.abbreviations(dwarf.abbreviations, at: abbreviationOffset, path: path)
            try parse(&reader, abbreviations, path: path)
            stringBase = root.attributes[0x72].map { Int($0.unsigned) } ?? 8
            addressBase = root.attributes[0x73].map { Int($0.unsigned) } ?? 8
            rangeListBase = root.attributes[0x74].map { Int($0.unsigned) } ?? 12
        }

        private typealias Abbreviation = (tag: UInt64, hasChildren: Bool, attributes: [(name: UInt64, form: UInt64, constant: Int64)])

        private static func abbreviations(_ bytes: [UInt8], at offset: Int, path: String) throws -> [UInt64: Abbreviation] {
            var reader = ByteReader(bytes)
            reader.offset = offset
            var table: [UInt64: Abbreviation] = [:]
            while true {
                let code = reader.uleb()
                if code == 0 { return table }
                let tag = reader.uleb()
                let hasChildren = reader.u8() != 0
                var attributes: [(name: UInt64, form: UInt64, constant: Int64)] = []
                while true {
                    let name = reader.uleb(), form = reader.uleb()
                    let constant = form == 0x21 ? reader.sleb() : 0
                    if name == 0, form == 0 { break }
                    attributes.append((name, form, constant))
                }
                table[code] = (tag, hasChildren, attributes)
            }
        }

        private func parse(_ reader: inout ByteReader, _ abbreviations: [UInt64: Abbreviation], path: String) throws {
            var stack: [Entry] = []
            while reader.offset < end {
                let entryOffset = reader.offset
                let code = reader.uleb()
                if code == 0 {
                    stack.removeLast()
                    if stack.isEmpty { return }
                    continue
                }
                guard let abbreviation = abbreviations[code] else { throw NomacError("unknown DWARF abbreviation \(code)", path: path) }
                let entry = Entry(offset: entryOffset, tag: abbreviation.tag, unit: self)
                for attribute in abbreviation.attributes {
                    entry.attributes[attribute.name] = try value(&reader, form: attribute.form, constant: attribute.constant, path: path)
                }
                dwarf.entries[entryOffset] = entry
                if let parent = stack.last { parent.children.append(entry) } else { root = entry }
                if abbreviation.hasChildren {
                    stack.append(entry)
                } else if stack.isEmpty {
                    return
                }
            }
        }

        private func value(_ reader: inout ByteReader, form: UInt64, constant: Int64, path: String) throws -> Attribute {
            var form = form
            if form == 0x16 { form = reader.uleb() }
            let value: Value
            switch form {
            case 0x01: value = .unsigned(reader.unsigned(addressSize))
            case 0x07, 0x14, 0x20, 0x24: value = .unsigned(reader.u64())
            case 0x0b, 0x11, 0x0c, 0x25, 0x29: value = .unsigned(reader.unsigned(1))
            case 0x05, 0x12, 0x26, 0x2a: value = .unsigned(reader.unsigned(2))
            case 0x27, 0x2b: value = .unsigned(reader.unsigned(3))
            case 0x06, 0x13, 0x28, 0x2c, 0x0e, 0x1f, 0x17, 0x10, 0x1d, 0x1c: value = .unsigned(reader.unsigned(4))
            case 0x1e: value = .block(reader.bytes(16))
            case 0x19: value = .unsigned(1)
            case 0x08: value = .string(reader.cString())
            case 0x0f, 0x15, 0x1a, 0x1b, 0x22, 0x23: value = .unsigned(reader.uleb())
            case 0x0d: value = .signed(reader.sleb())
            case 0x18, 0x09: value = .block(reader.bytes(Int(reader.uleb())))
            case 0x0a: value = .block(reader.bytes(Int(reader.u8())))
            case 0x03: value = .block(reader.bytes(Int(reader.u16())))
            case 0x04: value = .block(reader.bytes(Int(reader.u32())))
            case 0x21: value = .signed(constant)
            default: throw NomacError(String(format: "unsupported DWARF form 0x%x", form), path: path)
            }
            return Attribute(form: form, value: value)
        }

        /// A string attribute, whichever form holds it.
        func string(_ entry: Entry, _ name: UInt64) -> [UInt8]? {
            guard let attribute = entry.attributes[name] else { return nil }
            switch attribute.form {
            case 0x08:
                if case .string(let string) = attribute.value { return string }
                return nil
            case 0x0e: return ByteReader(dwarf.strings).cString(at: Int(attribute.unsigned))
            case 0x1f: return ByteReader(dwarf.lineStrings).cString(at: Int(attribute.unsigned))
            case 0x1a, 0x25, 0x26, 0x27, 0x28:
                let offset = ByteReader(dwarf.stringOffsets).u32(at: stringBase + 4 * Int(attribute.unsigned))
                return ByteReader(dwarf.strings).cString(at: Int(offset))
            default: return nil
            }
        }

        func address(_ attribute: Attribute) -> UInt64 {
            switch attribute.form {
            case 0x1b, 0x29, 0x2a, 0x2b, 0x2c: addressAt(index: attribute.unsigned)
            default: attribute.unsigned
            }
        }

        func addressAt(index: UInt64) -> UInt64 {
            var reader = ByteReader(dwarf.addresses)
            reader.offset = addressBase + addressSize * Int(index)
            return reader.unsigned(addressSize)
        }

        /// The entry an attribute refers to, in this unit or (`DW_FORM_ref_addr`) another.
        func reference(_ entry: Entry, _ name: UInt64) -> Entry? {
            guard let attribute = entry.attributes[name] else { return nil }
            switch attribute.form {
            case 0x11, 0x12, 0x13, 0x14, 0x15: return dwarf.entries[offset + Int(attribute.unsigned)]
            case 0x10: return dwarf.entries[Int(attribute.unsigned)]
            default: return nil
            }
        }

        var baseAddress: UInt64 { root.attributes[0x11].map(address) ?? 0 }

        /// The address ranges of an entry: `DW_AT_ranges` (with `DW_AT_low_pc`, a compile unit's
        /// base address), or `DW_AT_low_pc` and `DW_AT_high_pc`.
        func ranges(_ entry: Entry) -> [Range<UInt64>] {
            if let attribute = entry.attributes[0x55] {
                return version >= 5 ? rangeList(attribute) : versionFourRanges(at: Int(attribute.unsigned))
            }
            if let low = entry.attributes[0x11].map(address) {
                guard let high = entry.attributes[0x12] else { return [low..<(low + 1)] }
                let end = [0x01, 0x1b, 0x29, 0x2a, 0x2b, 0x2c].contains(high.form) ? address(high) : low + high.unsigned
                return [low..<end]
            }
            return []
        }

        private func rangeList(_ attribute: Attribute) -> [Range<UInt64>] {
            var reader = ByteReader(dwarf.rangeLists)
            reader.offset = attribute.form == 0x23
                ? rangeListBase + Int(reader.u32(at: rangeListBase + 4 * Int(attribute.unsigned))) : Int(attribute.unsigned)
            var result: [Range<UInt64>] = []
            var base = baseAddress
            while true {
                switch reader.u8() {
                case 0: return result
                case 1: base = addressAt(index: reader.uleb())
                case 2:
                    let start = addressAt(index: reader.uleb()), end = addressAt(index: reader.uleb())
                    result.append(start..<end)
                case 3:
                    let start = addressAt(index: reader.uleb())
                    result.append(start..<(start + reader.uleb()))
                case 4:
                    let start = reader.uleb(), end = reader.uleb()
                    result.append((base + start)..<(base + end))
                case 5: base = reader.unsigned(addressSize)
                case 6:
                    let start = reader.unsigned(addressSize), end = reader.unsigned(addressSize)
                    result.append(start..<end)
                case 7:
                    let start = reader.unsigned(addressSize)
                    result.append(start..<(start + reader.uleb()))
                default: return result
                }
            }
        }

        private func versionFourRanges(at offset: Int) -> [Range<UInt64>] {
            var reader = ByteReader(dwarf.ranges)
            reader.offset = offset
            var result: [Range<UInt64>] = []
            var base = baseAddress
            while reader.offset + 2 * addressSize <= dwarf.ranges.count {
                let start = reader.unsigned(addressSize), end = reader.unsigned(addressSize)
                if start == 0, end == 0 { break }
                if start == UInt64.max >> (64 - 8 * addressSize) { base = end; continue }
                result.append((base + start)..<(base + end))
            }
            return result
        }

        /// The unit's line table, if it has one.
        lazy var lineTable: LineTable? = root.attributes[0x10].map { LineTable(unit: self, offset: Int($0.unsigned)) }
    }

    /// A line number program run to its rows, and the paths of its files.
    struct LineTable {
        struct Row {
            let address: UInt64
            let file: UInt64
            let line: UInt64
            let column: UInt64
            let endSequence: Bool
        }

        private(set) var rows: [Row] = []
        private var directories: [[UInt8]] = []
        private var files: [(name: [UInt8], directory: Int)] = []
        private let compilationDirectory: [UInt8]

        init(unit: Unit, offset: Int) {
            let bytes = unit.dwarf.lines
            var reader = ByteReader(bytes)
            reader.offset = offset
            let end = offset + 4 + Int(reader.u32())
            let version = reader.u16()
            if version >= 5 { reader.offset += 2 }
            let headerLength = Int(reader.u32())
            let program = reader.offset + headerLength
            let minimumInstructionLength = UInt64(reader.u8())
            reader.offset += 2
            let lineBase = Int64(Int8(bitPattern: reader.u8())), lineRange = UInt64(reader.u8()), opcodeBase = reader.u8()
            let standardLengths = (1..<max(Int(opcodeBase), 1)).map { _ in reader.u8() }
            compilationDirectory = unit.string(unit.root, 0x1b) ?? []
            if version >= 5 {
                directories = Self.entries(&reader, unit).map { $0[1] ?? [] }
                files = Self.entries(&reader, unit).map { ($0[1] ?? [], Int(Self.number($0[2] ?? []))) }
            } else {
                directories = [compilationDirectory]
                while reader.bytes[reader.offset] != 0 { directories.append(reader.cString()) }
                reader.offset += 1
                files = [([], 0)]
                while reader.bytes[reader.offset] != 0 {
                    let name = reader.cString()
                    let directory = Int(reader.uleb())
                    _ = reader.uleb()
                    _ = reader.uleb()
                    files.append((name, directory))
                }
            }
            reader.offset = program
            var address: UInt64 = 0, file: UInt64 = 1, line: UInt64 = 1, column: UInt64 = 0
            func reset() { address = 0; file = 1; line = 1; column = 0 }
            func row(end: Bool = false) { rows.append(Row(address: address, file: file, line: line, column: column, endSequence: end)) }
            while reader.offset < end {
                let opcode = reader.u8()
                if opcode >= opcodeBase {
                    let adjusted = UInt64(opcode - opcodeBase)
                    address &+= adjusted / lineRange * minimumInstructionLength
                    line = UInt64(bitPattern: Int64(bitPattern: line) + lineBase + Int64(adjusted % lineRange))
                    row()
                    continue
                }
                switch opcode {
                case 0:
                    let length = Int(reader.uleb())
                    let next = reader.offset + length
                    switch reader.u8() {
                    case 1: row(end: true); reset()
                    case 2: address = reader.unsigned(length - 1)
                    default: break
                    }
                    reader.offset = next
                case 1: row()
                case 2: address &+= reader.uleb() * minimumInstructionLength
                case 3: line = UInt64(bitPattern: Int64(bitPattern: line) + reader.sleb())
                case 4: file = reader.uleb()
                case 5: column = reader.uleb()
                case 6, 7, 10, 11: break
                case 8: address &+= UInt64(255 - opcodeBase) / lineRange * minimumInstructionLength
                case 9: address &+= UInt64(reader.u16())
                case 12: _ = reader.uleb()
                default:
                    for _ in 0..<standardLengths[Int(opcode) - 1] { _ = reader.uleb() }
                }
            }
        }

        /// The directory and file entries of a version 5 header, by content type code.
        private static func entries(_ reader: inout ByteReader, _ unit: Unit) -> [[UInt64: [UInt8]]] {
            let formatCount = Int(reader.u8())
            let format = (0..<formatCount).map { _ in (code: reader.uleb(), form: reader.uleb()) }
            let count = Int(reader.uleb())
            return (0..<count).map { _ in
                var entry: [UInt64: [UInt8]] = [:]
                for (code, form) in format {
                    switch form {
                    case 0x08: entry[code] = reader.cString()
                    case 0x1f: entry[code] = ByteReader(unit.dwarf.lineStrings).cString(at: Int(reader.u32()))
                    case 0x0e: entry[code] = ByteReader(unit.dwarf.strings).cString(at: Int(reader.u32()))
                    case 0x0f: entry[code] = Self.bytes(reader.uleb())
                    case 0x0b: entry[code] = Self.bytes(UInt64(reader.u8()))
                    case 0x05: entry[code] = Self.bytes(UInt64(reader.u16()))
                    case 0x1e: entry[code] = reader.bytes(16)
                    default: break
                    }
                }
                return entry
            }
        }

        private static func bytes(_ number: UInt64) -> [UInt8] { (0..<8).map { UInt8(truncatingIfNeeded: number >> (8 * UInt64($0))) } }
        private static func number(_ bytes: [UInt8]) -> UInt64 { bytes.enumerated().reduce(0) { $0 | UInt64($1.element) << (8 * UInt64($1.offset)) } }

        /// A file's path: its name, under its directory, under the compilation directory, each
        /// joined only when the part after it is relative.
        func path(_ index: UInt64) -> [UInt8] {
            guard Int(index) < files.count else { return [] }
            let file = files[Int(index)]
            let directory = file.directory < directories.count ? directories[file.directory] : []
            return Self.join(compilationDirectory, Self.join(directory, file.name))
        }

        private static func join(_ directory: [UInt8], _ name: [UInt8]) -> [UInt8] {
            if directory.isEmpty || name.first == UInt8(ascii: "/") { return name }
            return directory + (directory.last == UInt8(ascii: "/") ? [] : [UInt8(ascii: "/")]) + name
        }
    }
}
