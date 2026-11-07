import Foundation
import NomacCore

/// visionOS app icon stacks (`.solidimagestack`): an iOS build compiles nothing from them, but
/// actool checks them and reports document errors, each twice, and still exits with 0 (`images`
/// and `icon-stacks` experiments; icecubes, vlc, sdwebimage): a stack holds 2 or 3 layers and its
/// last layer with content fills 512 × 512 points; a stack with no content has no such layer,
/// and the other layers may have any size. The size is the PNG's over the entry's scale, an
/// entry without a scale being 1x, whichever of the idioms below it has.
enum SolidImageStack {
    static let scales: [String: Int] = ["": 1, "2x": 2]
    static let idioms: Set<String> = ["vision", "reality", "universal", "iphone"]

    /// actool's messages for the stack, once each.
    static func errors(_ path: String) throws -> [String] {
        func unsupported(_ what: String) -> NomacError {
            NomacError("visionOS icon stacks with \(what) are not supported yet (BACKLOG B-202)", path: path)
        }
        let layers = try AssetCatalog.readContents(path, required: true)["layers"] as? [[String: Any]] ?? []
        var last: (name: String, width: Int, height: Int, scale: Int)?
        for layer in layers {
            guard let name = layer["filename"] as? String else { throw unsupported("a layer without a folder") }
            let set = path + "/" + name + "/Content.imageset"
            let images = (try AssetCatalog.readContents(set, required: false)["images"] as? [[String: Any]] ?? []).filter { $0["filename"] != nil }
            guard let image = images.first, let file = image["filename"] as? String else { continue }
            guard images.count == 1 else { throw unsupported("layers of several images") }
            guard let scale = scales[image["scale"] as? String ?? ""], idioms.contains(image["idiom"] as? String ?? "") else {
                throw unsupported("images other than 2x ones for vision, reality, universal or iPhone")
            }
            guard let (width, height) = pngSize(set + "/" + file) else { throw unsupported("files other than PNGs") }
            last = ((name as NSString).deletingPathExtension, width, height, scale)
        }
        var messages: [String] = []
        if let last, last.width != 512 * last.scale || last.height != 512 * last.scale {
            func points(_ pixels: Int) -> String {
                pixels % last.scale == 0 ? "\(pixels / last.scale)" : "\(Double(pixels) / Double(last.scale))"
            }
            messages.append("The last visionOS App Icon Layer with content, “\(last.name)”, must exactly fill the image stack. "
                + "Its current frame is {{0, 0}, {\(points(last.width)), \(points(last.height))}} while the visionOS App Icon's size is {512, 512}.")
        }
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        if layers.count < 2 { messages.append("The visionOS App Icon “\(name)” must have at least 2 layers.") }
        if layers.count > 3 { messages.append("The visionOS App Icon “\(name)” may not have more than 3 layers.") }
        return messages
    }

    /// The width and height in a PNG's `IHDR` chunk, which is all the check reads.
    static func pngSize(_ path: String) -> (width: Int, height: Int)? {
        guard let data = FileManager.default.contents(atPath: path), data.count >= 24,
              data.prefix(8).elementsEqual([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) else { return nil }
        let bytes = Array(data[16..<24]).map(Int.init)
        return (bytes[0] << 24 | bytes[1] << 16 | bytes[2] << 8 | bytes[3], bytes[4] << 24 | bytes[5] << 16 | bytes[6] << 8 | bytes[7])
    }
}
