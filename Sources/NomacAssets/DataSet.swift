import Foundation
import NomacCore

/// Compiles `.dataset` assets into data renditions (docs/formats/asset-catalog.md, "Data"),
/// as observed in the `data` experiments of `.github/scripts/assets_experiments.py`.
enum DataSet {
    /// The identifier macOS gives a file name: its extension's, in lowercase and decomposed, or a
    /// dynamic one for an extension it does not know (`data`, dynamic-identifiers). An extension
    /// holding a space counts as none, as a hidden file's and a trailing dot's do.
    static func typeIdentifier(filename: String) -> String {
        let parts = filename.split(separator: ".", omittingEmptySubsequences: false)
        let last = parts.count > 2 || parts.count == 2 && !parts[0].isEmpty ? String(parts[parts.count - 1]) : ""
        let pathExtension = last.contains(" ") ? "" : last.lowercased().decomposedStringWithCanonicalMapping
        return typeIdentifiers[pathExtension] ?? dynamicIdentifier(pathExtension: pathExtension)
    }

    /// `dyn.a` and the bits of `1=<extension>` (UTF-8, with a backslash before `=`, `,`, `:` and
    /// `\\`) five at a time from the top, zero-padded, in the alphabet below: `db` gives
    /// `dyn.age80k2u`, no extension `dyn.age8u` (`data`, dynamic-identifiers, 91 extensions).
    static func dynamicIdentifier(pathExtension: String) -> String {
        let alphabet = Array("abcdefghkmnpqrstuvwxyz0123456789")
        var escaped = ""
        for character in pathExtension {
            if "=,:\\".contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        var identifier = "dyn.a"
        var accumulator = 0, bits = 0
        for byte in Array(("1=" + escaped).utf8) {
            accumulator = accumulator << 8 | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                identifier.append(alphabet[accumulator >> bits & 31])
            }
            accumulator &= (1 << bits) - 1
        }
        if bits > 0 { identifier.append(alphabet[accumulator << (5 - bits) & 31]) }
        return identifier
    }

    static func renditions(_ asset: AssetCatalog.Asset, idioms: [String: UInt16]) throws -> [CARRendition] {
        guard let entries = asset.contents["data"] as? [[String: Any]] else { return [] }
        var renditions: [CARRendition] = []
        for entry in entries {
            guard let filename = entry["filename"] as? String else { continue }
            let unsupported = Set(entry.keys).subtracting(["filename", "idiom", "universal-type-identifier"])
            guard unsupported.isEmpty else {
                throw NomacError("data set properties \(unsupported.sorted()) are not supported yet (BACKLOG B-208)", path: asset.path)
            }
            let idiomName = entry["idiom"] as? String ?? "universal"
            // actool warns about `car` entries of data sets and compiles nothing (car-entries).
            guard idiomName != "car", let idiom = idioms[idiomName] else {
                guard idiomName != "car", Idiom.ignoredOnIOS.contains(idiomName) || Idiom.devices.contains(idiomName) else {
                    throw NomacError("data set idiom '\(idiomName)' is not supported yet (BACKLOG B-208)", path: asset.path)
                }
                continue
            }
            let path = asset.path + "/" + filename
            guard let data = FileManager.default.contents(atPath: path) else {
                throw NomacError("data sets with missing files are not supported yet (BACKLOG B-208)", path: path)
            }
            let type = entry["universal-type-identifier"] as? String ?? typeIdentifier(filename: filename)
            var typeProperty = ByteWriter()
            typeProperty.appendLE(UInt32(type.utf8.count + 1))
            typeProperty.appendLE(UInt32(0))
            typeProperty.append(Array(type.utf8) + [0])
            var payload = ByteWriter()
            payload.append(Array("DWAR".utf8))
            payload.appendLE(UInt32(0))
            payload.appendLE(UInt32(data.count))
            payload.append(Array(data))
            let csi = CSI(
                name: "CoreStructuredImage", layout: .data, scale: 100, pixelFormat: "DATA",
                properties: [(1004, [0, 0, 0, 0, 0, 0, 0x80, 0x3F]), (1005, typeProperty.bytes), (1006, [1, 0, 0, 0])],
                payload: payload.bytes)
            renditions.append(CARRendition(name: asset.name, kind: .data, attributes: [.scale: 1, .idiom: idiom], csi: csi.bytes))
        }
        return renditions
    }
}
