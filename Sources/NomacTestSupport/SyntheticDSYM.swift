import Foundation

/// A self-authored dSYM DWARF file (`MH_DSYM`) for the executable `SyntheticMachO.machO(seed:)`
/// makes, laid out as `<mach-o/loader.h>` and the DWARF 5 standard describe: a symbol table
/// with functions, an Objective-C method, names several symbols share, local functions at one
/// address (twice, once with a name repeated), external and local data at one address and a
/// name that looks mangled, and one
/// compile unit whose functions have inlined calls (one inside a lexical block), two functions
/// the symbol table lacks, and a line table over three files with a row outside every function.
/// With `arm64_32`, the same as a 32-bit file (`mach_header`, `LC_SEGMENT`, `nlist`) with 4-byte
/// DWARF addresses, from 0x4000 as the linker lays out arm64_32 executables.
public enum SyntheticDSYM {
    public static func dwarfFile(seed: UInt8, arm64_32: Bool = false) -> [UInt8] {
        let base: UInt64 = arm64_32 ? 0x4000 : 0x1_0000_0000
        let addressSize: UInt8 = arm64_32 ? 4 : 8
        func address(_ value: UInt64) -> [UInt8] { arm64_32 ? u32(UInt32(value)) : u64(value) }
        func segment(_ name: String, address: UInt64, size: UInt64, offset: UInt64, fileSize: UInt64,
                     sections: [(String, UInt64, UInt64, UInt32, UInt32)]) -> [UInt8] {
            let header = arm64_32 ? 56 : 72, sectionSize = arm64_32 ? 68 : 80
            var bytes = u32(arm64_32 ? 0x1 : 0x19) + u32(UInt32(header + sectionSize * sections.count)) + padded(name)
            bytes += [address, size, offset, fileSize].flatMap { arm64_32 ? u32(UInt32($0)) : u64($0) }
            bytes += u32(7) + u32(5) + u32(UInt32(sections.count)) + u32(0)
            for (section, sectionAddress, sectionSize, sectionOffset, flags) in sections {
                bytes += padded(section) + padded(name) + [sectionAddress, sectionSize].flatMap { arm64_32 ? u32(UInt32($0)) : u64($0) }
                bytes += u32(sectionOffset) + u32(0) + u32(0) + u32(0) + u32(flags) + u32(0) + u32(0) + (arm64_32 ? [] : u32(0))
            }
            return bytes
        }

        let strings = StringSection()
        let lineStrings = StringSection()
        let names = ["Test.swift", "/tmp/nomac", "$s4Test3fooyyF", "foo", "$s4Test6helperyyF", "helper", "bar", "add",
                     "$s4Test6lonelyyyF", "lonely", "solo"]
        let stringIndex = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, $0) })
        for name in names { strings.add(name) }
        let addresses: [UInt64] = [base + 0x4000, base + 0x4008, base + 0x4020, base + 0x4024, base + 0x4060, base + 0x4068]

        // Abbreviations: (code, tag, children, [(attribute, form)]).
        let abbreviations: [(UInt8, UInt8, Bool, [(UInt16, UInt8)])] = [
            (1, 0x11, true, [(0x03, 0x25), (0x1b, 0x25), (0x10, 0x17), (0x72, 0x17), (0x73, 0x17), (0x11, 0x1b), (0x12, 0x06)]),
            (2, 0x2e, true, [(0x11, 0x1b), (0x12, 0x06), (0x3fe7, 0x19), (0x6e, 0x25), (0x03, 0x25)]),
            (3, 0x2e, false, [(0x6e, 0x25), (0x03, 0x25), (0x20, 0x0b)]),
            (4, 0x1d, false, [(0x31, 0x13), (0x11, 0x1b), (0x12, 0x06), (0x58, 0x0b), (0x59, 0x0b), (0x57, 0x0b)]),
            (5, 0x2e, true, [(0x11, 0x1b), (0x12, 0x06), (0x03, 0x25)]),
            (6, 0x2e, false, [(0x03, 0x25), (0x20, 0x0b)]),
            (7, 0x0b, true, [(0x11, 0x1b), (0x12, 0x06)]),
            (8, 0x2e, false, [(0x11, 0x1b), (0x12, 0x06), (0x6e, 0x25), (0x03, 0x25)]),
            (9, 0x2e, false, [(0x11, 0x1b), (0x12, 0x06), (0x03, 0x25)]),
        ]
        var abbreviationBytes: [UInt8] = []
        for (code, tag, children, attributes) in abbreviations {
            abbreviationBytes += [code, tag, children ? 1 : 0]
            for (attribute, form) in attributes { abbreviationBytes += uleb(UInt64(attribute)) + [form] }
            abbreviationBytes += [0, 0]
        }
        abbreviationBytes += [0]

        // The entries, with the declarations last so that references point forward.
        let headerSize = 12
        func str(_ name: String) -> UInt8 { UInt8(stringIndex[name]!) }
        var entries: [UInt8] = [1, str("Test.swift"), str("/tmp/nomac")] + u32(0) + u32(8) + u32(8) + [0] + u32(0x80)
        entries += [2, 0] + u32(0x20) + [str("$s4Test3fooyyF"), str("foo")]
        let fooCallPosition = entries.count + 1
        entries += [4] + u32(0) + [1] + u32(8) + [1, 3, 9]
        entries += [0]
        entries += [5, 2] + u32(0x10) + [str("bar")]
        entries += [7, 3] + u32(8)
        let addCallPosition = entries.count + 1
        entries += [4] + u32(0) + [3] + u32(4) + [2, 7, 5]
        entries += [0, 0]
        entries += [8, 4] + u32(8) + [str("$s4Test6lonelyyyF"), str("lonely")]
        entries += [9, 5] + u32(8) + [str("solo")]
        let helperOffset = headerSize + entries.count
        entries += [3, str("$s4Test6helperyyF"), str("helper"), 1]
        let addOffset = headerSize + entries.count
        entries += [6, str("add"), 3]
        entries += [0]
        entries.replaceSubrange(fooCallPosition..<(fooCallPosition + 4), with: u32(UInt32(helperOffset)))
        entries.replaceSubrange(addCallPosition..<(addCallPosition + 4), with: u32(UInt32(addOffset)))
        let info = u32(UInt32(8 + entries.count)) + u16(5) + [1, addressSize] + u32(0) + entries

        let stringOffsets = u32(UInt32(4 + 4 * names.count)) + u16(5) + u16(0) + strings.offsets.flatMap { u32(UInt32($0)) }
        let addressTable = u32(UInt32(4 + Int(addressSize) * addresses.count)) + u16(5) + [addressSize, 0] + addresses.flatMap(address)

        // The line table: directories and files by DW_FORM_line_strp, the directory index as udata.
        let directories = ["/tmp/nomac", "Sources", "/"]
        let files: [(String, UInt64)] = [("/tmp/nomac/Test.swift", 0), ("Inline.h", 1), ("<compiler-generated>", 2)]
        var header: [UInt8] = [1, 1, 1, UInt8(bitPattern: -5), 14, 13] + [0, 1, 1, 1, 1, 0, 0, 0, 1, 0, 0, 1]
        header += [1] + uleb(1) + uleb(0x1f) + uleb(UInt64(directories.count))
        header += directories.flatMap { u32(UInt32(lineStrings.add($0))) }
        header += [2] + uleb(1) + uleb(0x1f) + uleb(2) + uleb(0x0f) + uleb(UInt64(files.count))
        header += files.flatMap { u32(UInt32(lineStrings.add($0.0))) + uleb($0.1) }
        var program: [UInt8] = [0, 1 + addressSize, 2] + address(base + 0x4000)
        program += [4] + uleb(0) + [1]
        program += [2] + uleb(8) + [4] + uleb(1) + [3] + sleb(2) + [5] + uleb(9) + [1]
        program += [2] + uleb(8) + [4] + uleb(2) + [3] + sleb(-3) + [5] + uleb(0) + [1, 1]
        program += [2] + uleb(0x10) + [4] + uleb(0) + [3] + sleb(10) + [5] + uleb(2) + [1]
        program += [2] + uleb(4) + [4] + uleb(1) + [3] + sleb(-6) + [5] + uleb(5) + [1]
        program += [2] + uleb(4) + [4] + uleb(0) + [3] + sleb(7) + [1]
        program += [2] + uleb(0x38) + [3] + sleb(9) + [5] + uleb(1) + [1]
        program += [2] + uleb(8) + [3] + sleb(1) + [1]
        program += [2] + uleb(8) + [3] + sleb(1) + [1]
        program += [2] + uleb(0x10) + [0, 1, 1]
        let lines = u32(UInt32(2 + 2 + 4 + header.count + program.count)) + u16(5) + [addressSize, 0] + u32(UInt32(header.count)) + header
            + program

        let dwarfSections: [(String, [UInt8])] = [
            ("__debug_line", lines), ("__debug_info", info), ("__debug_abbrev", abbreviationBytes), ("__debug_str", strings.bytes),
            ("__debug_str_offs", stringOffsets), ("__debug_addr", addressTable), ("__debug_line_str", lineStrings.bytes),
        ]

        // nlist_64 or nlist entries: name, type, section, value.
        let symbols: [(String, UInt8, UInt8, UInt64)] = [
            ("_$s4Test3fooyyF", 0x0f, 1, base + 0x4000), ("_bar", 0x0e, 1, base + 0x4020), ("-[Foo bar]", 0x0e, 1, base + 0x4030),
            ("_helper", 0x0e, 1, base + 0x4038), ("_helper", 0x0e, 1, base + 0x4040), ("_helper", 0x0e, 1, base + 0x4048),
            ("_alias", 0x0e, 1, base + 0x4048), ("_helper", 0x0e, 1, base + 0x4048), ("_ZedLike", 0x1e, 1, base + 0x4050),
            ("_twinA", 0x0e, 1, base + 0x4058), ("_twinB", 0x0e, 1, base + 0x4058), ("_dataLocal", 0x1e, 2, base + 0x4080),
            ("_data", 0x0f, 2, base + 0x4080), ("_dataAlias", 0x0f, 2, base + 0x4080), ("__mh_execute_header", 0x0f, 1, base),
        ]
        var symbolNames: [UInt8] = [0x20, 0]
        var symbolTable: [UInt8] = []
        for (name, type, section, value) in symbols {
            symbolTable += u32(UInt32(symbolNames.count)) + [type, section] + u16(0) + address(value)
            symbolNames += Array(name.utf8) + [0]
        }
        while symbolNames.count % 8 != 0 { symbolNames.append(0) }

        var commands: [UInt8] = u32(0x1b) + u32(24) + (0..<16).map { UInt8($0) &* 17 &+ seed }
        commands += u32(0x2) + u32(24) + u32(0) + u32(UInt32(symbols.count)) + u32(0) + u32(UInt32(symbolNames.count))
        commands += segment("__PAGEZERO", address: 0, size: base, offset: 0, fileSize: 0, sections: [])
        commands += segment("__TEXT", address: base, size: 0x8000, offset: 0, fileSize: 0, sections: [
            ("__text", base + 0x4000, 0x80, 0, 0x8000_0400), ("__const", base + 0x4080, 0x20, 0, 0),
        ])
        let headerAndCommandsSize = (arm64_32 ? 28 + 2 * 56 + 68 * dwarfSections.count : 32 + 2 * 72 + 80 * dwarfSections.count) + commands.count
        let linkEditOffset = (headerAndCommandsSize + 0xfff) & ~0xfff
        let linkEditSize = symbolTable.count + symbolNames.count
        let dwarfOffset = (linkEditOffset + linkEditSize + 0xfff) & ~0xfff
        var dwarfBytes: [UInt8] = []
        var dwarfSectionRecords: [(String, UInt64, UInt64, UInt32, UInt32)] = []
        for (name, bytes) in dwarfSections {
            dwarfSectionRecords.append((name, base + 0x9000 + UInt64(dwarfBytes.count), UInt64(bytes.count), UInt32(dwarfOffset + dwarfBytes.count), 0))
            dwarfBytes += bytes
        }
        commands += segment("__LINKEDIT", address: base + 0x8000, size: 0x1000, offset: UInt64(linkEditOffset), fileSize: UInt64(linkEditSize), sections: [])
        commands += segment("__DWARF", address: base + 0x9000, size: UInt64((dwarfBytes.count + 0xfff) & ~0xfff), offset: UInt64(dwarfOffset),
                            fileSize: UInt64(dwarfBytes.count), sections: dwarfSectionRecords)
        commands.replaceSubrange(32..<36, with: u32(UInt32(linkEditOffset)))
        commands.replaceSubrange(40..<44, with: u32(UInt32(linkEditOffset + symbolTable.count)))

        var file = arm64_32
            ? u32(0xfeed_face) + u32(0x0200_000c) + u32(1) + u32(0xa) + u32(6) + u32(UInt32(commands.count)) + u32(0)
            : u32(0xfeed_facf) + u32(0x0100_000c) + u32(0) + u32(0xa) + u32(6) + u32(UInt32(commands.count)) + u32(0) + u32(0)
        file += commands
        file += [UInt8](repeating: 0, count: linkEditOffset - file.count) + symbolTable + symbolNames
        file += [UInt8](repeating: 0, count: dwarfOffset - file.count) + dwarfBytes
        return file
    }

    private final class StringSection {
        var bytes: [UInt8] = []
        var offsets: [Int] = []

        @discardableResult
        func add(_ string: String) -> Int {
            let offset = bytes.count
            offsets.append(offset)
            bytes += Array(string.utf8) + [0]
            return offset
        }
    }

    private static func padded(_ name: String) -> [UInt8] { Array(name.utf8) + [UInt8](repeating: 0, count: 16 - name.utf8.count) }
    private static func u16(_ value: UInt16) -> [UInt8] { [UInt8(value & 0xff), UInt8(value >> 8)] }
    private static func u32(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * UInt32($0))) } }
    private static func u64(_ value: UInt64) -> [UInt8] { (0..<8).map { UInt8(truncatingIfNeeded: value >> (8 * UInt64($0))) } }

    private static func uleb(_ value: UInt64) -> [UInt8] {
        var value = value, bytes: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7f)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while value != 0
        return bytes
    }

    private static func sleb(_ value: Int64) -> [UInt8] {
        var value = value, bytes: [UInt8] = []
        while true {
            let byte = UInt8(value & 0x7f)
            value >>= 7
            if (value == 0 && byte & 0x40 == 0) || (value == -1 && byte & 0x40 != 0) {
                bytes.append(byte)
                return bytes
            }
            bytes.append(byte | 0x80)
        }
    }
}
