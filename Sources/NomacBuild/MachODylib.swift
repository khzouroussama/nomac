import Foundation
import NomacCore

/// What `tapi stubify` and the App Intents tools read from a thin 64-bit Mach-O file
/// (`<mach-o/loader.h>`): its identity, platform, sections and the symbols its export trie lists.
struct MachODylib {
    struct Export: Equatable {
        enum Kind: Equatable {
            case regular
            case threadLocal
        }

        var name: String
        var address: UInt64
        var kind: Kind
        var isWeak: Bool
    }

    struct Section {
        var name: String
        var address: UInt64
        var size: UInt64
        var flags: UInt32

        /// `S_ATTR_PURE_INSTRUCTIONS` or `S_ATTR_SOME_INSTRUCTIONS`.
        var hasInstructions: Bool { flags & 0x8000_0400 != 0 }
    }

    var cpuType: UInt32
    var cpuSubtype: UInt32
    var flags: UInt32
    var installName: String
    var currentVersion: UInt32
    var compatibilityVersion: UInt32
    var platform: UInt32
    var minimumOS: UInt32
    var sections: [Section]
    var exports: [Export]
    /// The Swift ABI version in `__objc_imageinfo`, if the image has Swift code.
    var swiftABIVersion: UInt8?

    static let dylibFileType: UInt32 = 6
    /// `MH_APP_EXTENSION_SAFE`.
    static let appExtensionSafeFlag: UInt32 = 0x0200_0000

    init(path: String) throws {
        let file = try MachOReader(path: path)
        cpuType = try file.uint32(4)
        cpuSubtype = try file.uint32(8)
        guard try file.uint32(12) == Self.dylibFileType else { throw NomacError("not a dynamic library", path: path) }
        flags = try file.uint32(24)
        var installName: String?
        var current: UInt32 = 0
        var compatibility: UInt32 = 0
        var platform: UInt32?
        var minimumOS: UInt32 = 0
        var sections: [Section] = []
        var segments: [(address: UInt64, size: UInt64, fileOffset: UInt64)] = []
        var trie: (offset: Int, size: Int)?
        for (command, offset, size) in try file.loadCommands() {
            switch command {
            case 0x19: // LC_SEGMENT_64
                segments.append((try file.uint64(offset + 24), try file.uint64(offset + 32), try file.uint64(offset + 40)))
                for index in 0..<Int(try file.uint32(offset + 64)) {
                    let header = offset + 72 + index * 80
                    sections.append(Section(name: file.string(header, length: 16), address: try file.uint64(header + 32),
                                            size: try file.uint64(header + 40), flags: try file.uint32(header + 64)))
                }
            case 0xd: // LC_ID_DYLIB
                installName = try file.dylibName(offset, size: size)
                current = try file.uint32(offset + 16)
                compatibility = try file.uint32(offset + 20)
            case 0x32: // LC_BUILD_VERSION
                platform = try file.uint32(offset + 8)
                minimumOS = try file.uint32(offset + 12)
            case 0x8000_0033: // LC_DYLD_EXPORTS_TRIE
                trie = (Int(try file.uint32(offset + 8)), Int(try file.uint32(offset + 12)))
            case 0x22, 0x8000_0022: // LC_DYLD_INFO(_ONLY)
                trie = (Int(try file.uint32(offset + 40)), Int(try file.uint32(offset + 44)))
            default:
                break
            }
        }
        guard let installName else { throw NomacError("no LC_ID_DYLIB", path: path) }
        guard let platform else { throw NomacError("no LC_BUILD_VERSION", path: path) }
        self.installName = installName
        currentVersion = current
        compatibilityVersion = compatibility
        self.platform = platform
        self.minimumOS = minimumOS
        self.sections = sections
        // __objc_imageinfo: version, then flags whose second byte is the Swift ABI version.
        swiftABIVersion = nil
        if let imageInfo = sections.first(where: { $0.name == "__objc_imageinfo" }),
           let segment = segments.first(where: { imageInfo.address >= $0.address && imageInfo.address < $0.address + $0.size }) {
            let swift = UInt8((try file.uint32(Int(segment.fileOffset + imageInfo.address - segment.address) + 4) >> 8) & 0xff)
            swiftABIVersion = swift == 0 ? nil : swift
        }
        exports = []
        for entry in try trie.map({ try file.trie(offset: $0.offset, size: $0.size) }) ?? [] {
            // EXPORT_SYMBOL_FLAGS_REEXPORT, _STUB_AND_RESOLVER and the absolute kind: tapi's
            // output for them has not been observed (docs/BACKLOG.md B-106).
            guard entry.flags & 0x18 == 0, entry.flags & 0x3 != 0x2, let address = entry.address else {
                throw NomacError("'\(entry.name)' is a re-export, a resolver or an absolute symbol, which nomac's tapi stubify does not write yet (B-106)", path: path)
            }
            exports.append(Export(name: entry.name, address: address, kind: entry.flags & 0x3 == 0x1 ? .threadLocal : .regular, isWeak: entry.flags & 0x4 != 0))
        }
    }

    /// The libraries a thin 64-bit Mach-O file of any kind loads (`LC_LOAD_DYLIB`, weak,
    /// re-exported, lazy and upward).
    /// The strings of every `LC_LINKER_OPTION` (`-framework`, `AppIntents`, `-lc++`, ...).
    static func linkerOptions(_ file: MachOReader) throws -> [String] {
        var options: [String] = []
        for command in try file.loadCommands() where command.command == 0x2d {
            var offset = command.offset + 12
            for _ in 0..<Int(try file.uint32(command.offset + 8)) where offset < command.offset + command.size {
                let option = file.string(offset, length: command.offset + command.size - offset)
                options.append(option)
                offset += option.utf8.count + 1
            }
        }
        return options
    }

    static func dependencies(path: String) throws -> [String] {
        try dependencies(try MachOReader(path: path))
    }

    static func dependencies(_ file: MachOReader) throws -> [String] {
        try file.loadCommands().filter { MachOStructure.libraryCommands.contains($0.command) }
            .map { try file.dylibName($0.offset, size: $0.size) }
    }

    /// The section that contains `address`.
    func section(containing address: UInt64) -> Section? {
        sections.first { address >= $0.address && address < $0.address + $0.size }
    }
}
