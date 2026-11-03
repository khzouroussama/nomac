import Foundation
import NomacTestSupport

/// A minimal thin arm64 iOS Mach-O image, built byte by byte for tests (`<mach-o/loader.h>`,
/// `<mach-o/nlist.h>`): `__TEXT` with `__text` (instructions) and `__const`, `__DATA` with
/// `__objc_imageinfo` and `__data`, an identity, a build version, an export trie whose root
/// names every symbol, and a symbol table of the imports.
struct SyntheticDylib {
    struct Import {
        var name: String
        /// The 1-based index of the library in `loadedLibraries`.
        var library: UInt16 = 1
        var isWeak = false
        var refersToWeakDefinition = false
    }

    enum Place {
        case text, constant, data
        var address: UInt64 {
            switch self {
            case .text: 0x1000
            case .constant: 0x2000
            case .data: 0x4100
            }
        }
    }

    struct Export {
        var name: String
        var place: Place
        /// `EXPORT_SYMBOL_FLAGS_*`.
        var flags: UInt64 = 0
    }

    var exports: [Export]
    var fileType: UInt32 = 6
    var flags: UInt32 = 0
    var currentVersion: UInt32 = 0
    var compatibilityVersion: UInt32 = 0
    var minimumOS: UInt32 = 0x000f_0000
    var swiftABI: UInt32 = 0
    var loadedLibraries: [String] = []
    /// Current versions of `loadedLibraries`, 1.0.0 otherwise.
    var libraryVersions: [String: UInt32] = [:]
    var imports: [Import] = []
    /// Defined symbols that are private externals (`N_PEXT`), as a compiler's weak caches are.
    var privateExternals: [String] = []
    var extraTextSections: [String] = []
    var sourceVersion: UInt64?
    /// `build_tool_version` entries of `LC_BUILD_VERSION`.
    var tools: [(tool: UInt32, version: UInt32)] = []
    var payload: UInt8 = 0
    /// Segment commands without a name, as in an object file, whose sections name their segments.
    var unnamedSegments = false

    private static let trieOffset = 0x4800
    private static let symbolsOffset = 0x5000

    func bytes() -> [UInt8] {
        typealias M = SyntheticMachO
        func segment(_ name: String, address: UInt64, sections: [(String, UInt64, UInt32)]) -> [UInt8] {
            var command = M.words([0x19, UInt32(72 + 80 * sections.count)]) + M.padded(unnamedSegments ? "" : name)
            command += M.quads([address, 0x4000, address, 0x1000]) + M.words([7, 7, UInt32(sections.count), 0])
            for (section, sectionAddress, sectionFlags) in sections {
                command += M.padded(section) + M.padded(name) + M.quads([sectionAddress, 0x100])
                command += M.words([UInt32(sectionAddress), 0, 0, 0, sectionFlags, 0, 0, 0])
            }
            return command
        }
        func dylib(_ command: UInt32, _ name: String, current: UInt32, compatibility: UInt32) -> [UInt8] {
            let size = (24 + name.utf8.count + 1 + 7) / 8 * 8
            return M.words([command, UInt32(size), 24, 2, current, compatibility]) + Array(name.utf8) + [UInt8](repeating: 0, count: size - 24 - name.utf8.count)
        }
        func uleb(_ value: UInt64) -> [UInt8] {
            var value = value
            var result: [UInt8] = []
            repeat {
                var byte = UInt8(value & 0x7f)
                value >>= 7
                if value != 0 { byte |= 0x80 }
                result.append(byte)
            } while value != 0
            return result
        }
        // The trie: a root with one edge per symbol to a terminal node (two-byte child offsets).
        let nodes = exports.map { export -> [UInt8] in
            let info = uleb(export.flags) + uleb(export.place.address)
            return uleb(UInt64(info.count)) + info + [0]
        }
        var root: [UInt8] = [0, UInt8(exports.count)]
        var nodeOffset = 2 + exports.reduce(0) { $0 + $1.name.utf8.count + 3 }
        for (index, export) in exports.enumerated() {
            root += Array(export.name.utf8) + [0, UInt8(nodeOffset & 0x7f) | 0x80, UInt8(nodeOffset >> 7)]
            nodeOffset += nodes[index].count
        }
        let trie = root + nodes.joined()

        let extra = extraTextSections.enumerated().map { ($0.element, UInt64(0x3000 + 0x100 * $0.offset), UInt32(0)) }
        var commands = [segment("__TEXT", address: 0, sections: [("__text", 0x1000, 0x8000_0400), ("__const", 0x2000, 0)] + extra),
                        segment("__DATA", address: 0x4000, sections: [("__objc_imageinfo", 0x4000, 0), ("__data", 0x4100, 0)])]
        if fileType == 6 {
            commands.append(dylib(0xd, "@rpath/libNomac.dylib", current: currentVersion, compatibility: compatibilityVersion))
        }
        commands += loadedLibraries.map { dylib(0xc, $0, current: libraryVersions[$0] ?? 0x10000, compatibility: 0x10000) }
        commands.append(M.words([0x32, UInt32(24 + 8 * tools.count), 2, minimumOS, 0x001b_0000, UInt32(tools.count)] + tools.flatMap { [$0.tool, $0.version] }))
        if let sourceVersion {
            commands.append(M.words([0x2a, 16]) + M.quads([sourceVersion]))
        }
        commands.append(M.words([0x8000_0033, 16, UInt32(Self.trieOffset), UInt32(trie.count)]))
        var strings: [UInt8] = [0x20, 0]
        var symbols: [UInt8] = []
        for symbol in imports {
            symbols += M.words([UInt32(strings.count)]) + [0x01, 0] + [(symbol.isWeak ? 0x40 : 0) | (symbol.refersToWeakDefinition ? 0x80 : 0), UInt8(symbol.library)] + M.quads([0])
            strings += Array(symbol.name.utf8) + [0]
        }
        for name in privateExternals {
            symbols += M.words([UInt32(strings.count)]) + [0x1f, 1, 0, 0] + M.quads([0x4000])
            strings += Array(name.utf8) + [0]
        }
        commands.append(M.words([0x2, 24, UInt32(Self.symbolsOffset), UInt32(imports.count + privateExternals.count), UInt32(Self.symbolsOffset + symbols.count), UInt32(strings.count)]))
        let loadCommands = Array(commands.joined())

        var file = M.words([0xfeed_facf, 0x0100_000c, 0, fileType, UInt32(commands.count), UInt32(loadCommands.count), flags, 0]) + loadCommands
        file += [UInt8](repeating: 0, count: 0x4000 - file.count)
        file += M.words([0, swiftABI << 8]) + [payload]
        file += [UInt8](repeating: 0, count: Self.trieOffset - file.count) + trie
        file += [UInt8](repeating: 0, count: Self.symbolsOffset - file.count) + symbols + strings
        return file
    }

    func write(to path: String) throws {
        try Data(bytes()).write(to: URL(fileURLWithPath: path))
    }
}
