import Foundation
import NomacCore

/// What a Mach-O file's code signature says beyond the hashes of the bytes it signs
/// (`<kern/cs_blobs.h>`): each code directory's version, flags, hash type and size, page size,
/// platform, special slot count, identifier, team and executable segment flags, and the
/// requirements, entitlements and CMS blobs. Two signatures of different binaries made with the
/// same options differ only in their hashes, code slot counts, code limits and executable segment
/// limits (docs/VERIFICATION.md "Archives that nomac built").
struct CodeSignatureFields: Equatable {
    var fields: [String: String]

    /// nil when the file has no `LC_CODE_SIGNATURE`.
    init?(file: MachOReader) throws {
        guard let (_, offset, _) = try file.loadCommands().first(where: { $0.0 == 0x1d }) else { return nil }
        let dataOffset = Int(try file.uint32(offset + 8))
        func be32(_ at: Int) throws -> Int { Int(try file.uint32(at).byteSwapped) }
        func be64(_ at: Int) throws -> UInt64 { try file.uint64(at).byteSwapped }
        guard try be32(dataOffset) == 0xfade_0cc0 else { throw NomacError("the code signature is not a superblob", path: file.path) }
        var fields: [String: String] = [:]
        for index in 0..<(try be32(dataOffset + 8)) {
            let type = try be32(dataOffset + 12 + index * 8)
            let blob = dataOffset + (try be32(dataOffset + 16 + index * 8))
            let magic = try be32(blob), length = try be32(blob + 4)
            let key = String(format: "slot 0x%x", type)
            switch magic {
            case 0xfade_0c02:
                let version = try be32(blob + 8)
                fields[key + " version"] = String(format: "0x%x", version)
                fields[key + " flags"] = String(format: "0x%x", try be32(blob + 12))
                fields[key + " special slots"] = String(try be32(blob + 24))
                let header = try file.slice(blob + 36, count: 4)
                fields[key + " hash size, type, platform, page size"] = header.map(String.init).joined(separator: ", ")
                fields[key + " identifier"] = file.string(blob + (try be32(blob + 20)), length: length)
                if version >= 0x20200, case let team = try be32(blob + 48), team != 0 {
                    fields[key + " team"] = file.string(blob + team, length: length)
                }
                if version >= 0x20400 { fields[key + " exec segment flags"] = String(format: "0x%llx", try be64(blob + 80)) }
            case 0xfade_0b01:
                fields[key + " CMS"] = length > 8 ? "signed" : "empty"
            default:
                fields[key + String(format: " blob 0x%x", magic)] = try file.slice(blob, count: length).map { String(format: "%02x", $0) }.joined()
            }
        }
        self.fields = fields
    }

    /// The fields that differ, described.
    static func differences(_ reference: CodeSignatureFields, _ other: CodeSignatureFields) -> [String] {
        Set(reference.fields.keys).union(other.fields.keys).sorted().compactMap { key in
            let left = reference.fields[key], right = other.fields[key]
            guard left != right else { return nil }
            func shown(_ value: String?) -> String { value.map { $0.count > 40 ? String($0.prefix(40)) + "…" : $0 } ?? "none" }
            return "code signature \(key): \(shown(left)) in Xcode's, \(shown(right)) in nomac's"
        }
    }
}

