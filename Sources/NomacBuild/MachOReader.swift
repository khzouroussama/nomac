import Foundation
import NomacCore

/// Bounds-checked little-endian reads of a thin 64-bit Mach-O file (`<mach-o/loader.h>`).
struct MachOReader {
    /// An entry of the export trie (`<mach-o/loader.h>`, "dyld export trie").
    struct TrieEntry: Equatable {
        var name: String
        /// `EXPORT_SYMBOL_FLAGS_*`.
        var flags: UInt64
        /// The symbol's offset from the image; none for a re-export.
        var address: UInt64?

        static let reexportFlag: UInt64 = 0x8
    }

    let bytes: [UInt8]
    let path: String

    init(path: String) throws {
        guard let data = FileManager.default.contents(atPath: path) else { throw NomacError("cannot read the file", path: path) }
        try self.init(bytes: [UInt8](data), path: path)
    }

    /// `bytes` read from `path`, which may name a member of an archive.
    init(bytes: [UInt8], path: String) throws {
        self.bytes = bytes
        self.path = path
        guard try uint32(0) == 0xfeed_facf else { throw NomacError("not a thin 64-bit little-endian Mach-O file", path: path) }
    }

    func uint32(_ offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= bytes.count else { throw NomacError("truncated Mach-O file", path: path) }
        return (0..<4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << (8 * UInt32($1)) }
    }

    func uint16(_ offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= bytes.count else { throw NomacError("truncated Mach-O file", path: path) }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    func uint64(_ offset: Int) throws -> UInt64 {
        UInt64(try uint32(offset)) | UInt64(try uint32(offset + 4)) << 32
    }

    func slice(_ offset: Int, count: Int) throws -> [UInt8] {
        guard offset >= 0, count >= 0, offset + count <= bytes.count else { throw NomacError("data outside the file", path: path) }
        return Array(bytes[offset..<(offset + count)])
    }

    func string(_ offset: Int, length: Int) -> String {
        let end = min(bytes.count, offset + length)
        return String(decoding: bytes[min(offset, end)..<end].prefix { $0 != 0 }, as: UTF8.self)
    }

    /// The name of a `dylib_command` at `offset`.
    func dylibName(_ offset: Int, size: Int) throws -> String {
        let nameOffset = Int(try uint32(offset + 8))
        guard nameOffset < size else { throw NomacError("malformed load command", path: path) }
        return string(offset + nameOffset, length: size - nameOffset)
    }

    /// Every load command: its kind, offset and size.
    func loadCommands() throws -> [(command: UInt32, offset: Int, size: Int)] {
        var commands: [(UInt32, Int, Int)] = []
        var offset = 32
        for _ in 0..<Int(try uint32(16)) {
            let size = Int(try uint32(offset + 4))
            guard size >= 8 else { throw NomacError("malformed load command", path: path) }
            commands.append((try uint32(offset), offset, size))
            offset += size
        }
        return commands
    }

    /// Every entry of the export trie at `offset`.
    func trie(offset: Int, size: Int) throws -> [TrieEntry] {
        let trie = try slice(offset, count: size)
        func uleb(_ cursor: inout Int) throws -> UInt64 {
            var value: UInt64 = 0
            var shift: UInt64 = 0
            while true {
                guard cursor < trie.count, shift < 64 else { throw NomacError("malformed export trie", path: path) }
                let byte = trie[cursor]
                cursor += 1
                value |= UInt64(byte & 0x7f) << shift
                if byte & 0x80 == 0 { return value }
                shift += 7
            }
        }
        var result: [TrieEntry] = []
        var pending: [(node: Int, prefix: [UInt8])] = [(0, [])]
        var visited = Set<Int>()
        while let (node, prefix) = pending.popLast() {
            guard node < trie.count, visited.insert(node).inserted else { throw NomacError("malformed export trie", path: path) }
            var cursor = node
            let terminalSize = try uleb(&cursor)
            let children = cursor + Int(terminalSize)
            if terminalSize > 0 {
                let flags = try uleb(&cursor)
                let address = flags & TrieEntry.reexportFlag == 0 ? try uleb(&cursor) : nil
                result.append(TrieEntry(name: String(decoding: prefix, as: UTF8.self), flags: flags, address: address))
            }
            cursor = children
            guard cursor < trie.count else { throw NomacError("malformed export trie", path: path) }
            let childCount = Int(trie[cursor])
            cursor += 1
            for _ in 0..<childCount {
                var label: [UInt8] = []
                while cursor < trie.count, trie[cursor] != 0 {
                    label.append(trie[cursor])
                    cursor += 1
                }
                cursor += 1
                let child = Int(try uleb(&cursor))
                pending.append((child, prefix + label))
            }
        }
        return result
    }
}
