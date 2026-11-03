import Foundation
import NomacCore

/// What ADR 0101 compares in a thin 64-bit Mach-O file built by a compiler and a linker (an
/// image, or a dSYM's DWARF file): its header, its load commands, its segments and sections by
/// name, the libraries it loads, its exports and its imports (`<mach-o/loader.h>`,
/// `<mach-o/nlist.h>`). Section contents, sizes and addresses, `LC_UUID`, the code signature,
/// local symbols and fixups follow the compiler's code and are not compared.
struct MachOStructure: Equatable {
    struct Library: Equatable {
        /// The load command: `LC_LOAD_DYLIB`, weak, re-exported, lazy or upward.
        var command: UInt32
        var name: String
        var currentVersion: UInt32
        var compatibilityVersion: UInt32
    }

    struct BuildVersion: Equatable {
        var platform: UInt32
        var minimumOS: UInt32
        var sdk: UInt32
        /// `build_tool_version`: the tool (`TOOL_LD` = 3, `TOOL_LLD` = 4, ...) and its version.
        var tools: [[UInt32]]
    }

    struct Import: Equatable {
        /// The library that defines it, or a special ordinal (`self`, `dynamic lookup`, `executable`).
        var library: String
        /// `N_WEAK_REF`.
        var isWeak: Bool
        /// `N_REF_TO_WEAK`: a reference to a weak definition.
        var refersToWeakDefinition: Bool
    }

    var fileType: UInt32
    var cpuType: UInt32
    var cpuSubtype: UInt32
    var flags: UInt32
    /// Every load command's kind, in file order.
    var commands: [UInt32]
    /// `SEGMENT,section`, in file order.
    var sections: [String]
    var identity: Library?
    var libraries: [Library]
    var rpaths: [String]
    var buildVersions: [BuildVersion]
    var sourceVersion: UInt64?
    /// The export trie's names and `EXPORT_SYMBOL_FLAGS_*`; nil without a trie.
    var exports: [String: UInt64]?
    /// The symbol table's defined external symbols (`N_EXT`, not `N_PEXT`).
    var definedSymbols: Set<String>
    /// The symbol table's private external symbols (`N_PEXT`), which are not compared.
    var privateExternals: Set<String>
    /// The symbol table's undefined external symbols.
    var imports: [String: Import]

    static let libraryCommands: Set<UInt32> = [0xc, 0x8000_0018, 0x8000_001f, 0x20, 0x8000_0023]

    /// Whether the file at `path` starts as a 64-bit little-endian Mach-O file does.
    static func isMachO(path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        return handle.readData(ofLength: 4) == Data([0xcf, 0xfa, 0xed, 0xfe])
    }

    init(path: String) throws {
        try self.init(file: MachOReader(path: path))
    }

    init(file: MachOReader) throws {
        cpuType = try file.uint32(4)
        cpuSubtype = try file.uint32(8)
        fileType = try file.uint32(12)
        flags = try file.uint32(24)
        commands = []
        sections = []
        identity = nil
        libraries = []
        rpaths = []
        buildVersions = []
        sourceVersion = nil
        exports = nil
        definedSymbols = []
        privateExternals = []
        imports = [:]
        var symbolTable: (symbols: Int, count: Int, strings: Int, size: Int)?
        for (command, offset, size) in try file.loadCommands() {
            commands.append(command)
            switch command {
            case 0x19: // LC_SEGMENT_64
                // A section names its own segment: an object file's one segment has no name.
                for index in 0..<Int(try file.uint32(offset + 64)) {
                    let header = offset + 72 + index * 80
                    sections.append(file.string(header + 16, length: 16) + "," + file.string(header, length: 16))
                }
            case 0xd: // LC_ID_DYLIB
                identity = Library(command: command, name: try file.dylibName(offset, size: size),
                                   currentVersion: try file.uint32(offset + 16), compatibilityVersion: try file.uint32(offset + 20))
            case _ where Self.libraryCommands.contains(command):
                libraries.append(Library(command: command, name: try file.dylibName(offset, size: size),
                                         currentVersion: try file.uint32(offset + 16), compatibilityVersion: try file.uint32(offset + 20)))
            case 0x8000_001c: // LC_RPATH
                rpaths.append(try file.dylibName(offset, size: size))
            case 0x32: // LC_BUILD_VERSION
                let tools = try (0..<Int(try file.uint32(offset + 20))).map { index in
                    [try file.uint32(offset + 24 + index * 8), try file.uint32(offset + 28 + index * 8)]
                }
                buildVersions.append(BuildVersion(platform: try file.uint32(offset + 8), minimumOS: try file.uint32(offset + 12),
                                                  sdk: try file.uint32(offset + 16), tools: tools))
            case 0x2a: // LC_SOURCE_VERSION
                sourceVersion = try file.uint64(offset + 8)
            case 0x8000_0033: // LC_DYLD_EXPORTS_TRIE
                exports = try Self.exports(file, offset: Int(try file.uint32(offset + 8)), size: Int(try file.uint32(offset + 12)))
            case 0x22, 0x8000_0022: // LC_DYLD_INFO(_ONLY)
                exports = try Self.exports(file, offset: Int(try file.uint32(offset + 40)), size: Int(try file.uint32(offset + 44)))
            case 0x2: // LC_SYMTAB
                symbolTable = (Int(try file.uint32(offset + 8)), Int(try file.uint32(offset + 12)),
                               Int(try file.uint32(offset + 16)), Int(try file.uint32(offset + 20)))
            default:
                break
            }
        }
        guard let symbolTable else { return }
        for index in 0..<symbolTable.count {
            let entry = symbolTable.symbols + index * 16
            let type = try file.slice(entry + 4, count: 1)[0]
            // N_STAB entries are debugging records; only external symbols are compared.
            guard type & 0xe0 == 0, type & 0x01 != 0 else { continue }
            let nameOffset = Int(try file.uint32(entry))
            guard nameOffset < symbolTable.size else { throw NomacError("symbol name outside the string table", path: file.path) }
            let name = file.string(symbolTable.strings + nameOffset, length: symbolTable.size - nameOffset)
            let description = try file.uint16(entry + 6)
            let value = try file.uint64(entry + 8)
            switch type & 0x0e {
            case 0x0 where value == 0: // N_UNDF, not a common symbol
                imports[name] = Import(library: library(ordinal: Int(description >> 8)), isWeak: description & 0x40 != 0,
                                       refersToWeakDefinition: description & 0x80 != 0)
            case 0xe where type & 0x10 == 0: // N_SECT, not N_PEXT
                definedSymbols.insert(name)
            case 0xe:
                privateExternals.insert(name)
            default:
                break
            }
        }
    }

    /// The name `GET_LIBRARY_ORDINAL(n_desc)` designates.
    private func library(ordinal: Int) -> String {
        switch ordinal {
        case 0: return "self"
        case 0xfe: return "dynamic lookup"
        case 0xff: return "executable"
        default: return ordinal <= libraries.count ? libraries[ordinal - 1].name : "ordinal \(ordinal)"
        }
    }

    private static func exports(_ file: MachOReader, offset: Int, size: Int) throws -> [String: UInt64] {
        guard size > 0 else { return [:] }
        return Dictionary(try file.trie(offset: offset, size: size).map { ($0.name, $0.flags) }, uniquingKeysWith: { first, _ in first })
    }

    /// A way two files differ, with a stable key that ``BuildEquivalence`` documents.
    struct Difference: Equatable {
        var key: String
        var description: String
    }

    /// How `other` differs from `reference`, structure by structure.
    static func differences(_ reference: MachOStructure, _ other: MachOStructure) -> [Difference] {
        var result: [Difference] = []
        func header(_ field: String, _ a: UInt32, _ b: UInt32) {
            if a != b { result.append(Difference(key: "header.\(field)", description: "\(field): Xcode \(hex(a)), nomac \(hex(b))")) }
        }
        header("filetype", reference.fileType, other.fileType)
        header("cputype", reference.cpuType, other.cpuType)
        header("cpusubtype", reference.cpuSubtype, other.cpuSubtype)
        header("flags", reference.flags, other.flags)

        let ownCommands = libraryCommands.union([0x19, 0x8000_001c])
        let commandCounts = { (commands: [UInt32]) in
            Dictionary(commands.filter { !ownCommands.contains($0) }.map { ($0, 1) }, uniquingKeysWith: +)
        }
        let referenceCounts = commandCounts(reference.commands)
        let otherCounts = commandCounts(other.commands)
        for command in Set(referenceCounts.keys).union(otherCounts.keys).sorted() {
            let (a, b) = (referenceCounts[command] ?? 0, otherCounts[command] ?? 0)
            if a > b { result.append(Difference(key: "command.missing.\(commandName(command))", description: "\(commandName(command)) only in Xcode's")) }
            if b > a { result.append(Difference(key: "command.extra.\(commandName(command))", description: "\(commandName(command)) only in nomac's")) }
        }
        let firstAppearances = { (commands: [UInt32], kept: Set<UInt32>) -> [UInt32] in
            var seen = Set<UInt32>()
            return commands.filter { kept.contains($0) && seen.insert($0).inserted }
        }
        let shared = Set(reference.commands).intersection(other.commands)
        if firstAppearances(reference.commands, shared) != firstAppearances(other.commands, shared) {
            result.append(Difference(key: "command.order", description: "load commands in another order"))
        }

        result += listDifferences("section", reference.sections, other.sections)
        result += listDifferences("library", reference.libraries.map(\.name), other.libraries.map(\.name))
        let otherLibraries = Dictionary(other.libraries.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        for library in reference.libraries {
            guard let match = otherLibraries[library.name] else { continue }
            if match.command != library.command {
                result.append(Difference(key: "library.kind.\(library.name)",
                                         description: "\(library.name): \(commandName(library.command)) in Xcode's, \(commandName(match.command)) in nomac's"))
            }
            if (match.currentVersion, match.compatibilityVersion) != (library.currentVersion, library.compatibilityVersion) {
                result.append(Difference(key: "library.version.\(library.name)",
                                         description: "\(library.name): Xcode \(version(library.currentVersion)) (compatibility \(version(library.compatibilityVersion))), nomac \(version(match.currentVersion)) (compatibility \(version(match.compatibilityVersion)))"))
            }
        }
        if reference.identity != other.identity {
            result.append(Difference(key: "identity", description: "LC_ID_DYLIB: Xcode \(describe(reference.identity)), nomac \(describe(other.identity))"))
        }
        if reference.rpaths != other.rpaths {
            result.append(Difference(key: "rpaths", description: "LC_RPATH: Xcode \(reference.rpaths), nomac \(other.rpaths)"))
        }
        let targets = { (versions: [BuildVersion]) in versions.map { [$0.platform, $0.minimumOS, $0.sdk] } }
        if targets(reference.buildVersions) != targets(other.buildVersions) {
            result.append(Difference(key: "build-version", description: "LC_BUILD_VERSION platform, minimum OS or SDK differ"))
        }
        if reference.buildVersions.map(\.tools) != other.buildVersions.map(\.tools) {
            let tools = { (versions: [BuildVersion]) in versions.flatMap(\.tools).map { "tool \($0[0]) \(version($0[1]))" }.joined(separator: ", ") }
            result.append(Difference(key: "build-version.tools", description: "LC_BUILD_VERSION tools: Xcode \(tools(reference.buildVersions)), nomac \(tools(other.buildVersions))"))
        }
        if let a = reference.sourceVersion, let b = other.sourceVersion, a != b {
            result.append(Difference(key: "source-version", description: "LC_SOURCE_VERSION: Xcode \(a), nomac \(b)"))
        }

        if let a = reference.exports, let b = other.exports {
            result += setDifferences("export", Set(a.keys), Set(b.keys))
            for (name, flags) in a.sorted(by: { $0.key < $1.key }) where b[name].map({ $0 != flags }) ?? false {
                result.append(Difference(key: "export.flags.\(name)", description: "export \(name): flags Xcode \(hex(flags)), nomac \(hex(b[name]!))"))
            }
        } else if (reference.exports == nil) != (other.exports == nil) {
            result.append(Difference(key: "exports", description: "an export trie in only one of the files"))
        } else {
            result += setDifferences("symbol", reference.definedSymbols, other.definedSymbols)
        }
        result += setDifferences("import", Set(reference.imports.keys), Set(other.imports.keys))
        for (name, symbol) in reference.imports.sorted(by: { $0.key < $1.key }) {
            guard let match = other.imports[name] else { continue }
            if match.library != symbol.library {
                result.append(Difference(key: "import.library.\(name)", description: "import \(name): from \(symbol.library) in Xcode's, \(match.library) in nomac's"))
            }
            if match.isWeak != symbol.isWeak {
                result.append(Difference(key: "import.weak.\(name)", description: "import \(name): \(symbol.isWeak ? "weak" : "strong") in Xcode's, \(match.isWeak ? "weak" : "strong") in nomac's"))
            }
            if match.refersToWeakDefinition != symbol.refersToWeakDefinition {
                result.append(Difference(key: "import.weak-definition", description: "import \(name): N_REF_TO_WEAK \(symbol.refersToWeakDefinition ? "set" : "clear") in Xcode's, \(match.refersToWeakDefinition ? "set" : "clear") in nomac's"))
            }
        }
        return result
    }

    /// Names in one list only, then whether the shared ones come in another order.
    private static func listDifferences(_ kind: String, _ reference: [String], _ other: [String]) -> [Difference] {
        let result = setDifferences(kind, Set(reference), Set(other))
        let shared = Set(reference).intersection(other)
        guard reference.filter(shared.contains) != other.filter(shared.contains) else { return result }
        return result + [Difference(key: "\(kind).order", description: "\(kind) names in another order")]
    }

    private static func setDifferences(_ kind: String, _ reference: Set<String>, _ other: Set<String>) -> [Difference] {
        reference.subtracting(other).sorted().map { Difference(key: "\(kind).missing.\($0)", description: "\(kind) \($0) only in Xcode's") }
            + other.subtracting(reference).sorted().map { Difference(key: "\(kind).extra.\($0)", description: "\(kind) \($0) only in nomac's") }
    }

    private static func describe(_ library: Library?) -> String {
        library.map { "\($0.name) \(version($0.currentVersion)) (compatibility \(version($0.compatibilityVersion)))" } ?? "none"
    }

    /// `xxxx.yy.zz` in nibbles, as `otool -L` prints it.
    private static func version(_ value: UInt32) -> String {
        "\(value >> 16).\((value >> 8) & 0xff).\(value & 0xff)"
    }

    private static func hex<T: BinaryInteger>(_ value: T) -> String {
        "0x" + String(value, radix: 16)
    }

    /// `<mach-o/loader.h>`'s name for a load command.
    static func commandName(_ command: UInt32) -> String {
        let names: [UInt32: String] = [
            0x2: "LC_SYMTAB", 0xb: "LC_DYSYMTAB", 0xc: "LC_LOAD_DYLIB", 0xd: "LC_ID_DYLIB", 0xe: "LC_LOAD_DYLINKER",
            0x19: "LC_SEGMENT_64", 0x1b: "LC_UUID", 0x1d: "LC_CODE_SIGNATURE", 0x1e: "LC_SEGMENT_SPLIT_INFO",
            0x20: "LC_LAZY_LOAD_DYLIB", 0x21: "LC_ENCRYPTION_INFO", 0x22: "LC_DYLD_INFO", 0x25: "LC_VERSION_MIN_IPHONEOS",
            0x26: "LC_FUNCTION_STARTS", 0x29: "LC_DATA_IN_CODE", 0x2a: "LC_SOURCE_VERSION", 0x2c: "LC_ENCRYPTION_INFO_64",
            0x2d: "LC_LINKER_OPTION", 0x2e: "LC_LINKER_OPTIMIZATION_HINT", 0x31: "LC_NOTE", 0x32: "LC_BUILD_VERSION",
            0x8000_0018: "LC_LOAD_WEAK_DYLIB", 0x8000_001c: "LC_RPATH", 0x8000_001f: "LC_REEXPORT_DYLIB",
            0x8000_0022: "LC_DYLD_INFO_ONLY", 0x8000_0023: "LC_LOAD_UPWARD_DYLIB", 0x8000_0028: "LC_MAIN",
            0x8000_0033: "LC_DYLD_EXPORTS_TRIE", 0x8000_0034: "LC_DYLD_CHAINED_FIXUPS",
        ]
        return names[command] ?? hex(command)
    }
}
