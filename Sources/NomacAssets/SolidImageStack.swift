import Foundation
import NomacCore

/// visionOS app icon stacks (`.solidimagestack`): an iOS build compiles nothing from them, but
/// actool checks them, and reports an error when the last layer with content does not fill the
/// stack's 512 × 512 points (the `images` experiment, icecubes). nomac accepts the stacks whose
/// layers with content all hold one vision 2x PNG of 1,024 × 1,024 pixels.
enum SolidImageStack {
    static func check(_ path: String) throws {
        func unsupported(_ what: String) -> NomacError {
            NomacError("visionOS icon stacks with \(what) are not supported yet (BACKLOG B-202)", path: path)
        }
        let layers = try AssetCatalog.readContents(path, required: true)["layers"] as? [[String: Any]] ?? []
        var filled = false
        for layer in layers {
            guard let name = layer["filename"] as? String else { throw unsupported("a layer without a folder") }
            let set = path + "/" + name + "/Content.imageset"
            let images = try AssetCatalog.readContents(set, required: false)["images"] as? [[String: Any]] ?? []
            for image in images {
                guard let file = image["filename"] as? String else { continue }
                guard image["idiom"] as? String == "vision", image["scale"] as? String == "2x" else {
                    throw unsupported("images other than vision 2x ones")
                }
                let png = try PNGImage(contentsOf: set + "/" + file)
                guard png.width == 1024, png.height == 1024 else { throw unsupported("layers of \(png.width) × \(png.height) pixels") }
                filled = true
            }
        }
        guard filled else { throw unsupported("no layer with content") }
    }
}
