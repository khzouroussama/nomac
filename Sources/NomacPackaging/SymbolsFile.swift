import Foundation
import NomacCore

/// The `Symbols/<UUID>.symbols` file `xcodebuild -exportArchive` writes for app-store-connect
/// from a dSYM's DWARF file (docs/formats/symbols.md, observed with `signing_experiments.py`):
/// a signature header, then the file's segments, sections, symbols, inlined calls and line
/// table rows, two name indexes and the strings they share.
public enum SymbolsFile {
    /// The `.symbols` files for the DWARF file at `path`, one per slice, each named by its
    /// slice's UUID (`<UUID>.symbols`), with the DWARF file's path and modification time
    /// (observed: a watch app's universal dSYM gives one file per architecture).
    public static func files(dwarfFile path: String) throws -> [(name: String, bytes: [UInt8])] {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let modified = Int((attributes[.modificationDate] as? Date)?.timeIntervalSince1970.rounded(.down) ?? 0)
        return try slices(at: path).map { slice in
            let hex = slice.uuid.map { String(format: "%02X", $0) }.joined()
            let uuid = [hex.prefix(8), hex.dropFirst(8).prefix(4), hex.dropFirst(12).prefix(4), hex.dropFirst(16).prefix(4), hex.dropFirst(20)]
                .joined(separator: "-")
            return (uuid + ".symbols", try data(slice, path: path, modificationTime: modified))
        }
    }

    static func slices(at path: String) throws -> [MachOFile] {
        guard let bytes = FileManager.default.contents(atPath: path) else { throw NomacError("could not read file", path: path) }
        return try MachOFile.slices(bytes: [UInt8](bytes), path: path)
    }

    /// Segments that hold no part of the image as loaded: laid out after the others, in load
    /// command order, `__LINKEDIT` last.
    static let unmappedSegments: Set<String> = ["__PAGEZERO", "__DWARF", "__LINKEDIT"]

    static func data(_ file: MachOFile, path: String, modificationTime: Int) throws -> [UInt8] {
        let dwarf = try DWARF(file, path: path)
        guard let text = file.segments.first(where: { $0.name == "__TEXT" }) else { throw NomacError("no __TEXT segment", path: path) }
        // A 32-bit file keeps its addresses and segments as they are (observed with the watch
        // experiments' arm64_32 slices); a 64-bit one is made relative to `__TEXT`.
        let base = file.is64Bit ? text.address : 0

        var segmentAddress: [String: UInt64] = [:]
        var mappedEnd: UInt64 = 0
        for segment in file.segments where !file.is64Bit || !unmappedSegments.contains(segment.name) {
            segmentAddress[segment.name] = segment.address &- base
            mappedEnd = max(mappedEnd, segment.address &- base &+ segment.size)
        }
        var cursor = mappedEnd
        let unmapped = file.segments.filter { file.is64Bit && unmappedSegments.contains($0.name) }
        for segment in unmapped.filter({ $0.name != "__LINKEDIT" }) + unmapped.filter({ $0.name == "__LINKEDIT" }) {
            segmentAddress[segment.name] = cursor
            cursor &+= segment.size
        }
        let firstSection = text.sections.map(\.address).min() ?? text.address
        var sectionRecords: [(address: UInt64, size: UInt64, name: [UInt8])] = [
            (text.address &- base, firstSection - text.address, Array("MACH_HEADER".utf8)),
        ]
        for segment in file.segments {
            for section in segment.sections {
                sectionRecords.append((segmentAddress[segment.name]! &+ section.address &- segment.address, section.size,
                                       Array("\(section.segment) \(section.name)".utf8)))
            }
        }
        let mappedSections = file.segments.filter { !unmappedSegments.contains($0.name) }.flatMap(\.sections)

        var functions: [UInt64: DWARF.Entry] = [:]
        func collectFunctions(_ entry: DWARF.Entry) {
            for child in entry.children {
                if child.tag == Tag.subprogram, let start = child.unit.ranges(child).first?.lowerBound, functions[start] == nil {
                    functions[start] = child
                }
                collectFunctions(child)
            }
        }
        for unit in dwarf.units { collectFunctions(unit.root) }

        var symbols = Self.symbols(file, mappedSections: mappedSections, functions: functions)
        var inlined: [Inlined] = []
        for index in symbols.indices {
            guard let function = symbols[index].function else { continue }
            let children = Self.inlined(in: function)
            if !children.isEmpty {
                symbols[index].firstInlined = inlined.count
                inlined += children
            }
        }
        // Breadth first: the calls inlined in each record, in record order.
        var position = 0
        while position < inlined.count {
            let record = inlined[position]
            let children = Self.inlined(in: record.entry).filter { record.range.contains($0.range.lowerBound) }
            if !children.isEmpty {
                inlined[position].firstChild = inlined.count
                inlined += children
            }
            position += 1
        }
        let listStarts = Set(symbols.compactMap(\.firstInlined) + inlined.compactMap(\.firstChild))
        for index in inlined.indices { inlined[index].isLast = index + 1 == inlined.count || listStarts.contains(index + 1) }

        var rows: [(address: UInt64, size: UInt64, path: [UInt8], line: UInt64, column: UInt64)] = []
        for unit in dwarf.units {
            guard let table = unit.lineTable else { continue }
            for (index, row) in table.rows.enumerated() where !row.endSequence && index + 1 < table.rows.count {
                let next = table.rows[index + 1].address
                if next == row.address { continue }
                rows.append((row.address &- base, next &- row.address, table.path(row.file), row.line, row.column))
            }
        }
        rows = rows.enumerated().sorted { ($0.element.address, $0.offset) < ($1.element.address, $1.offset) }.map(\.element)
        // A row belongs to the symbol it starts in and ends with it; rows outside every symbol
        // or in deduplicated functions are left out (observed).
        rows = rows.compactMap { row in
            var low = 0, high = symbols.count
            while low < high {
                let middle = (low + high) / 2
                if symbols[middle].address &- base <= row.address { low = middle + 1 } else { high = middle }
            }
            // Rows in the deduplicated functions are left out too (archive-extensionkit).
            guard low > 0, symbols[low - 1].flags & 0x800 == 0 else { return nil }
            let end = symbols[low - 1].address &- base + symbols[low - 1].size
            guard row.address < end else { return nil }
            return (row.address, min(row.size, end - row.address), row.path, row.line, row.column)
        }

        var strings = StringTable()
        let sectionNames = sectionRecords.map { strings.append($0.name) }
        var symbolNames: [NameKey: Int] = [:]
        let symbolNameOffsets = symbols.map { symbol in
            if let offset = symbolNames[symbol.nameKey] { return offset }
            let offset = strings.append(symbol.name)
            symbolNames[symbol.nameKey] = offset
            return offset
        }
        var inlinedNames = [Int](repeating: 0, count: inlined.count), inlinedPaths = [Int](repeating: 0, count: inlined.count)
        func intern(list first: Int) {
            var index = first
            while true {
                inlinedNames[index] = strings.intern(inlined[index].name)
                inlinedPaths[index] = inlined[index].callFile.map { strings.intern($0) } ?? 0
                if let child = inlined[index].firstChild { intern(list: child) }
                if inlined[index].isLast { break }
                index += 1
            }
        }
        for symbol in symbols { if let first = symbol.firstInlined { intern(list: first) } }
        let rowPaths = rows.map { strings.intern($0.path) }
        let displayPath = Array(path.utf8)
        let pathOffset = strings.append(displayPath)

        // Both indexes list symbols in address order sorted with libc++'s std::sort (observed:
        // the order of symbols that share a name).
        var demangled = symbols.indices.filter { symbols[$0].demangledOffset != nil }
        IntroSort.sort(&demangled) { symbols[$0].demangled.lexicographicallyPrecedes(symbols[$1].demangled) }
        var named = Array(symbols.indices)
        IntroSort.sort(&named) { symbols[$0].name.lexicographicallyPrecedes(symbols[$1].name) }

        var body: [UInt8] = []
        for segment in file.segments {
            body += le(segmentAddress[segment.name]!) + le(segment.size) + padded(segment.name)
        }
        for (record, nameOffset) in zip(sectionRecords, sectionNames) {
            body += le(record.address) + le(record.size) + le(UInt64(nameOffset))
        }
        let symbolStart = 0x70 + body.count
        for (symbol, nameOffset) in zip(symbols, symbolNameOffsets) {
            body += le32(symbol.address &- base) + le32(symbol.size) + le32(UInt64(symbol.flags))
            body += le32(UInt64(symbol.demangledOffset.map { nameOffset + $0 } ?? 0)) + le32(UInt64(nameOffset))
            body += le32(UInt64(UInt32(bitPattern: Int32(symbol.firstInlined ?? -1))))
        }
        for (index, record) in inlined.enumerated() {
            let flags: UInt32 = (record.hasLinkageName ? 0x8561_0101 : 0x8550_8101) | (record.isLast ? 0x4000_0000 : 0)
            body += le32(record.range.lowerBound &- base) + le32(UInt64(record.range.count)) + le32(UInt64(flags))
            body += le32(UInt64(record.isMangled ? 0 : inlinedNames[index] + 1)) + le32(UInt64(inlinedNames[index]))
            body += le32(UInt64(UInt32(bitPattern: Int32(record.firstChild ?? -1))))
            body += le32(UInt64(inlinedPaths[index])) + le32(record.callLine) + le32(record.callColumn)
        }
        for (row, pathOffset) in zip(rows, rowPaths) {
            body += le32(row.address) + le32(row.size) + le32(UInt64(pathOffset)) + le32(row.line) + le32(row.column)
        }
        // Each index entry holds its distance back to the symbol record it names.
        let indexStart = 0x70 + body.count
        for (position, symbol) in (demangled + named).enumerated() {
            body += le32(UInt64(indexStart + 4 * position - (symbolStart + 24 * symbol)))
        }
        let headerAndTables = 0x70 + body.count
        body += strings.bytes
        let stringsEnd = 0x70 + body.count
        body += le32(0x00c0_ffee) + le32(1) + le32(24) + le32(0x2b00) + le32(0x2b00) + le32(0)
        body += [UInt8](repeating: 0, count: (8 - (0x70 + body.count) % 8) % 8)
        let length = 0x70 + body.count
        let counts = [file.segments.count, sectionRecords.count, symbols.count, inlined.count, rows.count]
        let sizeEstimate = headerAndTables + 2 * strings.bytes.count - (displayPath.count + 1) + counts.reduce(0, +) + 32

        let pathLength = (displayPath.count + 1 + 7) / 8 * 8
        var result = le32(0xff01_ff02) + le32(1) + le32(0xffff_ffff) + le32(0) + le32(0x2b00) + le32(1)
        result += file.uuid + le32(UInt64(modificationTime)) + le32(0x1000_0101) + le(0) + le(0x7fff_ffff_ffff_ffff)
        result += le32(UInt64(file.cpuType)) + le32(UInt64(file.cpuSubtype)) + le32(UInt64(file.segments.count)) + le32(UInt64(pathLength))
        result += displayPath + [UInt8](repeating: 0, count: pathLength - displayPath.count)
        for segment in file.segments {
            result += padded(segment.name) + le(segment.address) + le(segment.size)
        }
        result += le32(0xa1b2_2b1a) + le32(7) + le32(0xa1b2_2b1a) + le32(UInt64(length)) + le32(7) + le32(UInt64(stringsEnd + 8))
        result += counts.flatMap { le32(UInt64($0)) } + le32(17) + le32(0) + le32(0)
        result += le(UInt64(pathOffset)) + le32(UInt64(sizeEstimate)) + file.uuid
        result += le32(UInt64(file.cpuType)) + le32(UInt64(file.cpuSubtype)) + le(0)
        result += le32(UInt64(strings.bytes.count)) + le32(UInt64(4 * demangled.count)) + le32(0)
        result += body
        let sequence = (0..<16).map { UInt8($0) }
        result += le32(0x00c0_ffee) + le32(4) + sequence + le(0) + sequence + [UInt8](repeating: 0, count: 16) + le(8) + le32(0)
        return result
    }

    private struct Symbol {
        let address: UInt64
        var size: UInt64
        let flags: UInt32
        let name: [UInt8]
        /// What the string table shares the name by: the symbol table's string offset, so that
        /// equal names at different offsets are written twice (observed).
        let nameKey: NameKey
        /// Where the demangled name starts in `name`, for names that do not look mangled.
        let demangledOffset: Int?
        let function: DWARF.Entry?
        var firstInlined: Int?

        var demangled: ArraySlice<UInt8> { name[(demangledOffset ?? 0)...] }
    }

    enum NameKey: Hashable {
        case symbolTable(UInt32)
        case deduplicated
        case dwarf([UInt8])
    }

    private struct Inlined {
        let entry: DWARF.Entry
        let range: Range<UInt64>
        let name: [UInt8]
        let hasLinkageName: Bool
        let callFile: [UInt8]?
        let callLine: UInt64
        let callColumn: UInt64
        var firstChild: Int?
        var isLast = false

        var isMangled: Bool { SymbolsFile.looksMangled(name) }
    }

    enum Tag {
        static let subprogram: UInt64 = 0x2e
        static let inlinedSubroutine: UInt64 = 0x1d
        static let lexicalBlock: UInt64 = 0x0b
    }

    /// Names the `.symbols` file leaves to demangle later: Swift (`_$s`) and C++ (`_Z`, `__Z`)
    /// prefixes, also `_ZedVersionString` (observed).
    static func looksMangled(_ name: [UInt8]) -> Bool {
        [Array("_$s".utf8), Array("_Z".utf8), Array("__Z".utf8)].contains { name.starts(with: $0) }
    }

    /// The records of the symbol table's defined symbols inside sections and of the functions
    /// only DWARF knows, in address order (observed, docs/formats/symbols.md "Symbols"): symbols
    /// that share an address keep the external ones, the others merging into the first; local
    /// functions that share one are listed after a `<deduplicated_symbol>` record.
    private static func symbols(_ file: MachOFile, mappedSections: [MachOFile.Section], functions: [UInt64: DWARF.Entry]) -> [Symbol] {
        func section(at address: UInt64) -> MachOFile.Section? {
            mappedSections.first { $0.address <= address && address < $0.address + $0.size }
        }
        let defined = file.symbols
            .filter { $0.type & 0xe0 == 0 && $0.type & 0x0e == 0x0e }
            .compactMap { symbol in section(at: symbol.value).map { (symbol: symbol, section: $0) } }
            .sorted { ($0.symbol.value, $0.symbol.index) < ($1.symbol.value, $1.symbol.index) }
        var groups: [[(symbol: MachOFile.Symbol, section: MachOFile.Section)]] = []
        for entry in defined {
            if let last = groups.last?.first, last.symbol.value == entry.symbol.value {
                groups[groups.count - 1].append(entry)
            } else {
                groups.append([entry])
            }
        }
        // Symbols at one address that all have one name are one symbol (observed).
        groups = groups.map { group in group.allSatisfy { $0.symbol.name == group[0].symbol.name } ? [group[0]] : group }
        // Sizes run to the next record's address or the section's end, unless DWARF gives them.
        var records: [(symbol: Symbol, sectionEnd: UInt64?)] = []
        for group in groups {
            let address = group[0].symbol.value, section = group[0].section
            let isCode = section.flags & 0x8000_0400 != 0
            let sectionEnd = section.address + section.size
            func flags(_ symbol: MachOFile.Symbol) -> UInt32 {
                var flags: UInt32 = 0x0348_4000 | (isCode ? 0x1 : 0) | (symbol.type & 0x01 != 0 ? 0x10 : 0) | (symbol.type & 0x10 != 0 ? 0x20 : 0)
                if isObjectiveCMethod(symbol.name) { flags |= 0x4 }
                return flags
            }
            let externals = group.filter { $0.symbol.type & 0x01 != 0 }.map(\.symbol)
            if externals.isEmpty, isCode, group.count > 1 {
                records.append((Symbol(address: address, size: 0, flags: 0x800, name: Array("<deduplicated_symbol>".utf8),
                                       nameKey: .deduplicated, demangledOffset: 0, function: nil), sectionEnd))
                // One former private external marks every entry (archive-extensionkit).
                let privateExternal: UInt32 = group.contains { $0.symbol.type & 0x10 != 0 } ? 0x20 : 0
                records += group.map { (Symbol(address: address, size: 0, flags: flags($0.symbol) | privateExternal | 0x800, name: $0.symbol.name,
                                               nameKey: .symbolTable($0.symbol.nameOffset), demangledOffset: demangledOffset($0.symbol.name),
                                               function: nil), sectionEnd) }
                continue
            }
            let kept = externals.isEmpty ? [group[0].symbol] : externals
            let merged = group.map(\.symbol).filter { symbol in !kept.contains { $0.index == symbol.index } }
            for (position, symbol) in kept.enumerated() {
                var symbolFlags = flags(symbol) | (position > 0 ? 0x200 : 0)
                if !merged.isEmpty { symbolFlags |= 0x2000_0000 | merged.reduce(0) { $0 | ($1.type & 0x10 != 0 ? 0x20 : 0) } }
                var size: UInt64 = 0
                var end: UInt64? = sectionEnd
                var function: DWARF.Entry?
                if position == 0, isCode, let entry = functions[address], let range = entry.unit.ranges(entry).first {
                    function = entry
                    size = UInt64(range.count)
                    end = nil
                    symbolFlags |= 0x2400_0100 | (entry.attributes[0x3fe7] != nil ? 0x80 : 0)
                }
                records.append((Symbol(address: address, size: size, flags: symbolFlags, name: symbol.name, nameKey: .symbolTable(symbol.nameOffset),
                                       demangledOffset: demangledOffset(symbol.name), function: function), end))
            }
        }
        let named = Set(groups.map { $0[0].symbol.value })
        for (address, entry) in functions where !named.contains(address) && section(at: address).map({ $0.flags & 0x8000_0400 != 0 }) == true {
            guard let range = entry.unit.ranges(entry).first else { continue }
            let (name, hasLinkageName) = calledName(entry)
            records.append((Symbol(address: address, size: UInt64(range.count), flags: hasLinkageName ? 0x0561_0101 : 0x0550_8101, name: name,
                                   nameKey: .dwarf(name), demangledOffset: demangledOffset(name), function: entry), nil))
        }
        records = records.enumerated().sorted { ($0.element.symbol.address, $0.offset) < ($1.element.symbol.address, $1.offset) }.map(\.element)
        for index in records.indices {
            guard let sectionEnd = records[index].sectionEnd else { continue }
            let address = records[index].symbol.address
            let next = records[index...].first { $0.symbol.address > address }?.symbol.address ?? sectionEnd
            records[index].symbol.size = min(next, sectionEnd) - address
        }
        return records.map(\.symbol)
    }

    private static func isObjectiveCMethod(_ name: [UInt8]) -> Bool {
        (name.first == UInt8(ascii: "+") || name.first == UInt8(ascii: "-")) && name.dropFirst().first == UInt8(ascii: "[")
            && name.last == UInt8(ascii: "]")
    }

    /// Where the demangled name starts in a name that does not look mangled: after its leading
    /// underscore, if any.
    private static func demangledOffset(_ name: [UInt8]) -> Int? {
        looksMangled(name) ? nil : (name.first == UInt8(ascii: "_") ? 1 : 0)
    }

    /// The calls inlined directly in `entry` (looking through lexical blocks), one record per
    /// address range, in address order.
    private static func inlined(in entry: DWARF.Entry) -> [Inlined] {
        func calls(_ entry: DWARF.Entry) -> [DWARF.Entry] {
            entry.children.flatMap { child -> [DWARF.Entry] in
                child.tag == Tag.inlinedSubroutine ? [child] : child.tag == Tag.lexicalBlock ? calls(child) : []
            }
        }
        let records = calls(entry).flatMap { call -> [Inlined] in
            let unit = call.unit
            let (name, hasLinkageName) = calledName(call)
            let callFile = call.attributes[0x58].flatMap { unit.lineTable?.path($0.unsigned) }
            return unit.ranges(call).map { range in
                Inlined(entry: call, range: range, name: name, hasLinkageName: hasLinkageName, callFile: callFile,
                        callLine: call.attributes[0x59]?.unsigned ?? 0, callColumn: call.attributes[0x57]?.unsigned ?? 0)
            }
        }
        return records.enumerated().sorted { ($0.element.range.lowerBound, $0.offset) < ($1.element.range.lowerBound, $1.offset) }.map(\.element)
    }

    /// `_` and the linkage name of the inlined function, through its abstract origin and
    /// specification, else `_` and its name.
    private static func calledName(_ call: DWARF.Entry) -> (name: [UInt8], hasLinkageName: Bool) {
        var entry: DWARF.Entry? = call
        var steps = 0
        while let current = entry, steps < 16 {
            for attribute: UInt64 in [0x6e, 0x2007] {
                if let name = current.unit.string(current, attribute) { return ([UInt8(ascii: "_")] + name, true) }
            }
            entry = current.unit.reference(current, 0x31) ?? current.unit.reference(current, 0x47)
            if entry == nil { return (current.unit.string(current, 0x03).map { [UInt8(ascii: "_")] + $0 } ?? [], false) }
            steps += 1
        }
        return ([], false)
    }

    private struct StringTable {
        var bytes: [UInt8] = []
        private var interned: [[UInt8]: Int] = [:]

        mutating func append(_ string: [UInt8]) -> Int {
            defer { bytes += string + [0] }
            return bytes.count
        }

        mutating func intern(_ string: [UInt8]) -> Int {
            if let offset = interned[string] { return offset }
            let offset = append(string)
            interned[string] = offset
            return offset
        }
    }

    private static func le(_ value: UInt64) -> [UInt8] { (0..<8).map { UInt8(truncatingIfNeeded: value >> (8 * UInt64($0))) } }
    private static func le32(_ value: UInt64) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * UInt64($0))) } }
    private static func padded(_ name: String) -> [UInt8] { Array(name.utf8) + [UInt8](repeating: 0, count: 16 - name.utf8.count) }
}
