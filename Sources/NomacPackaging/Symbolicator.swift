import Foundation
import NomacCore

/// The functions and source lines at addresses of a binary, from the DWARF of its dSYM, as
/// `atos -i` prints them (docs/formats/crash-report.md, `symbolicate_experiments.py`): the
/// function whose DWARF ranges hold the address, the calls inlined into it there innermost
/// first, each at the line its line table or its caller's call site gives; without DWARF, the
/// symbol table's function and the offset into it.
public final class Symbolicator {
    /// One frame of `atos -i`: `<function> (in <image>) (<file>:<line>)`, or
    /// `<function> (in <image>) + <offset>` without a line.
    public struct Frame: Equatable, Sendable {
        public var function: String
        public var file: String?
        public var line: UInt64?
        public var offset: UInt64?

        public func formatted(image: String) -> String {
            if let file, let line { return "\(function) (in \(image)) (\(file):\(line))" }
            return "\(function) (in \(image))" + (offset.map { " + \($0)" } ?? "")
        }
    }

    public let uuid: String
    /// `arm64`, `arm64e`, `arm64_32`, `x86_64` or `armv7k`.
    public var architecture: String {
        switch (file.cpuType, file.cpuSubtype & 0xff) {
        case (0x0100000c, 2): "arm64e"
        case (0x0100000c, _): "arm64"
        case (0x0200000c, _): "arm64_32"
        case (0x01000007, _): "x86_64"
        case (12, _): "armv7k"
        default: "cpu \(file.cpuType)"
        }
    }
    let file: MachOFile
    let dwarf: DWARF
    public let textAddress: UInt64
    /// The first `__TEXT` section's address: before it are the Mach-O header and load commands.
    let firstSection: UInt64
    let demangle: (String) -> String
    private var functions: [(range: Range<UInt64>, entry: DWARF.Entry)] = []
    /// Text symbols by address, aliases in symbol table order.
    private var symbols: [(address: UInt64, name: String, external: Bool)] = []

    /// The slices of the DWARF file at `path` (`<name>.dSYM/Contents/Resources/DWARF/<name>`).
    public static func slices(dwarfFile path: String, demangle: @escaping (String) -> String) throws -> [Symbolicator] {
        guard let data = FileManager.default.contents(atPath: path) else { throw NomacError("cannot read the dSYM", path: path) }
        return try MachOFile.slices(bytes: [UInt8](data), path: path).map { try Symbolicator(file: $0, path: path, demangle: demangle) }
    }

    init(file: MachOFile, path: String, demangle: @escaping (String) -> String) throws {
        self.file = file
        self.demangle = demangle
        uuid = Self.uuidString(file.uuid)
        dwarf = try DWARF(file, path: path)
        let text = file.segments.first { $0.name == "__TEXT" }
        textAddress = text?.address ?? 0
        firstSection = text?.sections.map(\.address).min() ?? textAddress
        func collect(_ entry: DWARF.Entry) {
            for child in entry.children {
                if child.tag == 0x2e { functions += child.unit.ranges(child).filter { !$0.isEmpty }.map { ($0, child) } }
                collect(child)
            }
        }
        for unit in dwarf.units { collect(unit.root) }
        functions.sort { $0.range.lowerBound < $1.range.lowerBound }
        symbols = file.symbols.filter { $0.type & 0xe0 == 0 && $0.type & 0x0e == 0x0e && $0.value >= textAddress }
            .sorted { ($0.value, $0.index) < ($1.value, $1.index) }.map { ($0.value, String(decoding: $0.name, as: UTF8.self), $0.type & 0x01 != 0) }
    }

    /// The frames at `offset` from the start of the image, innermost first
    /// (`symbolicate_experiments.py`). A DWARF function that starts after the symbol table's
    /// last symbol at or before the address decides alone. Otherwise the address's symbol is
    /// that last symbol; folded code has several, its aliases. With two or more local aliases it is
    /// `<deduplicated_symbol>` and the offset. Otherwise the symbol is the first external alias in
    /// table order, else the first: when the function whose DWARF ranges hold the address has
    /// that linkage name, DWARF gives its frames; when it has another, its frames under the
    /// symbol's name; without a DWARF function, the symbol at the line its unit's line table
    /// gives when that row starts in the symbol, else the symbol and the offset, and nothing past the end of the function DWARF
    /// gives the symbol or in the Mach-O header.
    public func frames(offset: UInt64) -> [Frame] {
        let address = textAddress &+ offset
        guard address >= firstSection else { return [] }
        let function = functions.first { $0.range.contains(address) }?.entry
        let start = symbols.last(where: { $0.address <= address })?.address
        // A DWARF function that starts after the last symbol (one the symbol table lacks)
        // decides alone: its frames, or nothing past its end.
        if let nearest = functions.last(where: { $0.range.lowerBound <= address }), start.map({ nearest.range.lowerBound > $0 }) ?? true {
            return nearest.range.contains(address) ? frames(function: nearest.entry, address: address) : []
        }
        guard let start else { return [] }
        let aliases = symbols.filter { $0.address == start }
        if aliases.filter({ !$0.external }).count >= 2 { return [Frame(function: "<deduplicated_symbol>", offset: address - start)] }
        let symbol = aliases.first(where: \.external) ?? aliases[0]
        guard let function else {
            // Units' ranges overlap (an address can be in three); the first with a line row wins,
            // when the row starts in the symbol.
            let units = dwarf.units.filter { $0.ranges($0.root).contains { $0.contains(address) } }
            if let location = units.lazy.compactMap({ self.line(at: address, unit: $0) }).first, location.start >= start {
                return [Frame(function: name(symbol.name), file: display(location.file), line: location.line)]
            }
            // Past the end of the function DWARF gives the symbol (alignment padding): nothing.
            if functions.contains(where: { $0.range.lowerBound == start }) { return [] }
            return [Frame(function: name(symbol.name), offset: address - start)]
        }
        var frames = frames(function: function, address: address)
        let canonical = symbol.name.hasPrefix("_") ? String(symbol.name.dropFirst()) : symbol.name
        if linkageName(function) != canonical { frames[frames.count - 1].function = name(symbol.name) }
        return frames
    }

    func frames(function: DWARF.Entry, address: UInt64) -> [Frame] {
        var chain = [function]
        while let call = Self.calls(in: chain.last!).first(where: { call in call.unit.ranges(call).contains { $0.contains(address) } }) {
            chain.append(call)
        }
        let location = line(at: address, unit: function.unit)
        var frames: [Frame] = []
        for index in chain.indices.reversed() {
            let entry = chain[index]
            if index == chain.count - 1 {
                frames.append(Frame(function: functionName(entry), file: location.map { display($0.file) }, line: location?.line))
            } else {
                let call = chain[index + 1]
                let file = call.attributes[0x58].flatMap { entry.unit.lineTable?.path($0.unsigned) }
                frames.append(Frame(function: functionName(entry), file: file.map(display), line: call.attributes[0x59]?.unsigned ?? 0))
            }
        }
        return frames
    }

    /// The inlined calls directly in `entry`, looking through lexical blocks.
    static func calls(in entry: DWARF.Entry) -> [DWARF.Entry] {
        entry.children.flatMap { child -> [DWARF.Entry] in
            child.tag == 0x1d ? [child] : child.tag == 0x0b ? calls(in: child) : []
        }
    }

    /// The linkage name through abstract origins and specifications, else the name, as stored.
    func linkageName(_ entry: DWARF.Entry) -> String? {
        var current: DWARF.Entry? = entry
        var plain: [UInt8]?
        var steps = 0
        while let found = current, steps < 16 {
            for attribute: UInt64 in [0x6e, 0x2007] {
                if let name = found.unit.string(found, attribute) { return String(decoding: name, as: UTF8.self) }
            }
            plain = plain ?? found.unit.string(found, 0x03)
            current = found.unit.reference(found, 0x31) ?? found.unit.reference(found, 0x47)
            steps += 1
        }
        return plain.map { String(decoding: $0, as: UTF8.self) }
    }

    /// The linkage name through abstract origins and specifications, demangled, else the name.
    func functionName(_ entry: DWARF.Entry) -> String {
        var current: DWARF.Entry? = entry
        var plain: [UInt8]?
        var steps = 0
        while let found = current, steps < 16 {
            for attribute: UInt64 in [0x6e, 0x2007] {
                if let name = found.unit.string(found, attribute) { return demangle(String(decoding: name, as: UTF8.self)) }
            }
            plain = plain ?? found.unit.string(found, 0x03)
            current = found.unit.reference(found, 0x31) ?? found.unit.reference(found, 0x47)
            steps += 1
        }
        return plain.map { String(decoding: $0, as: UTF8.self) } ?? "???"
    }

    func name(_ symbol: String) -> String {
        let trimmed = symbol.hasPrefix("_") ? String(symbol.dropFirst()) : symbol
        return demangle(trimmed)
    }

    /// The line table row covering `address`: the last row at or before it in its sequence.
    func line(at address: UInt64, unit: DWARF.Unit) -> (file: [UInt8], line: UInt64, start: UInt64)? {
        guard let table = unit.lineTable else { return nil }
        var best: DWARF.LineTable.Row?
        for (index, row) in table.rows.enumerated() where !row.endSequence && row.address <= address {
            let next = index + 1 < table.rows.count ? table.rows[index + 1] : nil
            guard let next, address < next.address else { continue }
            if best == nil || row.address >= best!.address { best = row }
        }
        return best.map { (table.path($0.file), $0.line, $0.address) }
    }

    /// A source path as `atos` prints it: its last component, or the whole path for a file at
    /// the root (`/<compiler-generated>`).
    func display(_ path: [UInt8]) -> String {
        let text = String(decoding: path, as: UTF8.self)
        let name = (text as NSString).lastPathComponent
        return (text as NSString).deletingLastPathComponent == "/" ? text : name
    }

    static func uuidString(_ bytes: [UInt8]) -> String {
        let hex = bytes.map { String(format: "%02X", $0) }.joined()
        guard hex.count == 32 else { return hex }
        let parts = [8, 4, 4, 4, 12]
        var index = hex.startIndex
        return parts.map { length in
            let end = hex.index(index, offsetBy: length)
            defer { index = end }
            return String(hex[index..<end])
        }.joined(separator: "-")
    }
}
