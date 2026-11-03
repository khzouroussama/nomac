import Foundation
import NomacCore

/// A static library as Xcode 27.0's `libtool -static` writes it (`Libtool` tasks of CocoaPods'
/// static library targets, expo-default's `lib*.a`): BSD `ar` (`<ar.h>`), every member name
/// written after its header as `#1/<length>` and padded with NULs, the ranlib table
/// (`<mach-o/ranlib.h>`) first as `__.SYMDEF`, each entry's offset that of its member's header.
struct StaticArchive {
    struct Member: Equatable {
        var name: String
        /// The header's date, owner, group and mode fields as written.
        var attributes: String
        var contents: [UInt8]
        /// The offset of the member's header in the archive.
        var offset: Int
    }

    static let magic = Array("!<arch>\n".utf8)

    let members: [Member]

    static func isArchive(path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        return [UInt8](handle.readData(ofLength: magic.count)) == magic
    }

    init(path: String) throws {
        guard let data = FileManager.default.contents(atPath: path) else { throw NomacError("cannot read the file", path: path) }
        try self.init(bytes: [UInt8](data), path: path)
    }

    /// The archive in `bytes` (a slice of a universal file), `path` naming it in errors.
    init(bytes: [UInt8], path: String) throws {
        guard bytes.starts(with: Self.magic) else { throw NomacError("not an ar archive", path: path) }
        var members: [Member] = []
        var offset = Self.magic.count
        while offset < bytes.count {
            guard offset + 60 <= bytes.count, bytes[offset + 58] == 0x60, bytes[offset + 59] == 0x0a else {
                throw NomacError("truncated ar member header at offset \(offset)", path: path)
            }
            let field = { (start: Int, length: Int) in
                String(decoding: bytes[(offset + start)..<(offset + start + length)], as: UTF8.self).trimmingCharacters(in: .whitespaces)
            }
            guard let size = Int(field(48, 10)), offset + 60 + size <= bytes.count else {
                throw NomacError("bad ar member size at offset \(offset)", path: path)
            }
            var name = field(0, 16)
            var start = offset + 60
            if name.hasPrefix("#1/") {
                guard let length = Int(name.dropFirst(3)), length <= size else { throw NomacError("bad ar member name at offset \(offset)", path: path) }
                name = String(decoding: bytes[start..<(start + length)].prefix { $0 != 0 }, as: UTF8.self)
                start += length
            }
            members.append(Member(name: name, attributes: field(16, 32), contents: Array(bytes[start..<(offset + 60 + size)]), offset: offset))
            offset += 60 + size + size % 2
        }
        self.members = members
    }

    static func isSymbolTable(_ member: Member) -> Bool {
        member.name == "__.SYMDEF" || member.name == "__.SYMDEF SORTED"
    }

    /// An entry of the ranlib table: a symbol and the name of the member that defines it.
    struct Entry: Equatable {
        var symbol: String
        var member: String
    }

    /// The ranlib table's entries.
    func symbols(of table: Member) throws -> [Entry] {
        let bytes = table.contents
        func uint32(_ at: Int) throws -> Int {
            guard at >= 0, at + 4 <= bytes.count else { throw NomacError("truncated ranlib table in \(table.name)") }
            return (0..<4).reduce(0) { $0 | Int(bytes[at + $1]) << (8 * $1) }
        }
        let entries = try uint32(0)
        let strings = 4 + entries + 4
        let byOffset = Dictionary(members.map { ($0.offset, $0.name) }, uniquingKeysWith: { first, _ in first })
        return try stride(from: 4, to: 4 + entries, by: 8).map { entry in
            let start = strings + (try uint32(entry))
            guard start < bytes.count else { throw NomacError("ranlib string outside the table in \(table.name)") }
            return Entry(symbol: String(decoding: bytes[start...].prefix { $0 != 0 }, as: UTF8.self), member: byOffset[try uint32(entry + 4)] ?? "")
        }
    }

    /// The private external symbols (`N_PEXT`) of each Mach-O member, by member name.
    func privateExternals() throws -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for member in members where member.contents.starts(with: [0xcf, 0xfa, 0xed, 0xfe]) {
            result[member.name] = try MachOStructure(file: MachOReader(bytes: member.contents, path: member.name)).privateExternals
        }
        return result
    }
}
