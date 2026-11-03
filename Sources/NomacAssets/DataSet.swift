import Foundation
import NomacCore

/// Compiles `.dataset` assets into data renditions (docs/formats/asset-catalog.md, "Data"),
/// as observed in the `data` experiments of `.github/scripts/assets_experiments.py`.
enum DataSet {
    /// The type identifier actool records for a file without `universal-type-identifier`, by
    /// file extension, as observed on macOS 27.0.1.
    static let typeIdentifiers: [String: String] = [
        "aiff": "public.aiff-audio", "bin": "com.apple.macbinary-archive", "caf": "com.apple.coreaudio-format",
        "css": "public.css", "csv": "public.comma-separated-values-text", "gif": "com.compuserve.gif",
        "glb": "org.khronos.glb", "gltf": "org.khronos.gltf", "gz": "org.gnu.gnu-zip-archive", "htm": "public.html",
        "html": "public.html", "jpeg": "public.jpeg", "jpg": "public.jpeg", "js": "com.netscape.javascript-source",
        "json": "public.json", "m4a": "com.apple.m4a-audio", "md": "net.daringfireball.markdown",
        "mlmodel": "com.apple.coreml.model", "mlmodelc": "com.apple.coreml.mlmodelc", "mov": "com.apple.quicktime-movie",
        "mp3": "public.mp3", "mp4": "public.mpeg-4", "obj": "public.geometry-definition-format", "otf": "public.opentype-font",
        "pdf": "com.adobe.pdf", "plist": "com.apple.property-list", "png": "public.png", "rtf": "public.rtf",
        "scn": "com.apple.scenekit.scene", "strings": "com.apple.xcode.strings-text", "svg": "public.svg-image",
        "tar": "public.tar-archive", "ttf": "public.truetype-ttf-font", "txt": "public.plain-text",
        "usdz": "com.pixar.universal-scene-description-mobile", "wav": "com.microsoft.waveform-audio", "xml": "public.xml",
        "yaml": "public.yaml", "yml": "public.yaml", "zip": "public.zip-archive",
    ]

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
            guard let idiom = idioms[idiomName] else {
                guard Idiom.ignoredOnIOS.contains(idiomName) || Idiom.devices.contains(idiomName) else {
                    throw NomacError("data set idiom '\(idiomName)' is not supported yet (BACKLOG B-208)", path: asset.path)
                }
                continue
            }
            let path = asset.path + "/" + filename
            guard let data = FileManager.default.contents(atPath: path) else {
                throw NomacError("data sets with missing files are not supported yet (BACKLOG B-208)", path: path)
            }
            let type: String
            if let explicit = entry["universal-type-identifier"] as? String {
                type = explicit
            } else if let known = typeIdentifiers[(filename as NSString).pathExtension] {
                type = known
            } else {
                throw NomacError("the type identifier of '\(filename)' is not known yet (BACKLOG B-208)", path: asset.path)
            }
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
