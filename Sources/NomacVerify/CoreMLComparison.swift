import Foundation
import NomacCore

/// Compiled Core ML models that differ only where Xcode's own coremlc changes from one run to the
/// next: the order of a model's user metadata entries, in `metadata.json` and in the description
/// `coremldata.bin` archives (docs/formats/coreml.md "Run-to-run variations").
enum CoreMLComparison {
    static func equivalent(fileName: String, xcode: Data, nomac: Data) -> Bool {
        switch fileName {
        case "metadata.json": return canonicalMetadata(xcode) == canonicalMetadata(nomac) && canonicalMetadata(xcode) != nil
        case "coremldata.bin": return canonicalArchive([UInt8](xcode)) == canonicalArchive([UInt8](nomac)) && canonicalArchive([UInt8](xcode)) != nil
        default: return false
        }
    }

    /// `metadata.json` with its `userDefinedMetadata` entries sorted.
    static func canonicalMetadata(_ data: Data) -> String? {
        guard var text = String(data: data, encoding: .utf8), let range = text.range(of: "\"userDefinedMetadata\" : {\n") else { return nil }
        guard let end = text[range.upperBound...].range(of: "\n    }") else { return nil }
        let entries = text[range.upperBound..<end.lowerBound].split(separator: "\n").map { $0.hasSuffix(",") ? String($0.dropLast()) : String($0) }
        text.replaceSubrange(range.upperBound..<end.lowerBound, with: entries.sorted().joined(separator: ",\n"))
        return text
    }

    /// An archive with the user metadata entries of its description sorted: a `spec` archive's
    /// specification (72 bytes of header), or a `generic` one's description (its length at 0x4b).
    static func canonicalArchive(_ bytes: [UInt8]) -> [UInt8]? {
        guard bytes.count >= 0x2B else { return nil }
        if Array(bytes[0x24..<0x28]) == Array("spec".utf8), bytes.count >= 0x48,
           var model = try? ProtobufMessage(bytes: Array(bytes[0x48...])), let description = try? model.message(2) {
            model.set(2, message: sortingUserMetadata(description))
            return Array(bytes[..<0x48]) + model.bytes
        }
        if Array(bytes[0x24..<0x2B]) == Array("generic".utf8), bytes.count >= 0x53 {
            let length = Int(bytes[0x4B..<0x53].reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) })
            guard 0x53 + length <= bytes.count, let description = try? ProtobufMessage(bytes: Array(bytes[0x53..<(0x53 + length)])) else { return nil }
            return Array(bytes[..<0x53]) + sortingUserMetadata(description).bytes + Array(bytes[(0x53 + length)...])
        }
        return nil
    }

    static func sortingUserMetadata(_ description: ProtobufMessage) -> ProtobufMessage {
        guard var metadata = try? description.message(100) else { return description }
        let entries = metadata.fields.filter { $0.number == 100 }.sorted { $0.payload.lexicographicallyPrecedes($1.payload) }
        metadata.fields = metadata.fields.filter { $0.number != 100 } + entries
        var sorted = description
        sorted.set(100, message: metadata)
        return sorted
    }
}
