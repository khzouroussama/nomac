import Foundation
import NomacCore
import NomacPlist

/// Launch image sets (`launch-images`). Only the set `--launch-image` names adds anything, and
/// nothing in `Assets.car`: an icon PNG per slot of a targeted device and the partial Info.plist's
/// `UILaunchImages`, with `UILaunchImageFile` for the slots without a system version. A set no
/// option names adds only its warnings.
enum LaunchImageSet {
    struct Slot {
        var idiom: String
        var version: String?
        var subtype: String?
        var orientation: String
        var scale: Int
        var extent: String
        var name: String
        var points: String
        var pixels: (width: Int, height: Int)
    }

    /// Xcode's slots, in the order `UILaunchImages` lists those with a system version.
    static let slots: [Slot] = {
        func slot(_ idiom: String, _ version: String?, _ subtype: String?, _ orientation: String, _ scale: Int, _ name: String, _ points: String, _ width: Int, _ height: Int,
                  extent: String = "full-screen") -> Slot {
            Slot(idiom: idiom, version: version, subtype: subtype, orientation: orientation, scale: scale, extent: extent, name: name, points: points, pixels: (width, height))
        }
        return [
            slot("iphone", "12.0", "2688h", "portrait", 3, "-1200-Portrait-2688h", "{414, 896}", 1242, 2688),
            slot("iphone", "12.0", "2688h", "landscape", 3, "-1200-Landscape-2688h", "{414, 896}", 2688, 1242),
            slot("iphone", "12.0", "1792h", "portrait", 2, "-1200-Portrait-1792h", "{414, 896}", 828, 1792),
            slot("iphone", "12.0", "1792h", "landscape", 2, "-1200-Landscape-1792h", "{414, 896}", 1792, 828),
            slot("iphone", "11.0", "2436h", "portrait", 3, "-1100-Portrait-2436h", "{375, 812}", 1125, 2436),
            slot("iphone", "11.0", "2436h", "landscape", 3, "-1100-Landscape-2436h", "{375, 812}", 2436, 1125),
            slot("iphone", "8.0", "736h", "portrait", 3, "-800-Portrait-736h", "{414, 736}", 1242, 2208),
            slot("iphone", "8.0", "736h", "landscape", 3, "-800-Landscape-736h", "{414, 736}", 2208, 1242),
            slot("iphone", "8.0", "667h", "portrait", 2, "-800-667h", "{375, 667}", 750, 1334),
            slot("iphone", "7.0", nil, "portrait", 2, "-700", "{320, 480}", 640, 960),
            slot("iphone", "7.0", "retina4", "portrait", 2, "-700-568h", "{320, 568}", 640, 1136),
            slot("ipad", "7.0", nil, "portrait", 1, "-700-Portrait", "{768, 1024}", 768, 1024),
            slot("ipad", "7.0", nil, "portrait", 2, "-700-Portrait", "{768, 1024}", 1536, 2048),
            slot("ipad", "7.0", nil, "landscape", 1, "-700-Landscape", "{768, 1024}", 1024, 768),
            slot("ipad", "7.0", nil, "landscape", 2, "-700-Landscape", "{768, 1024}", 2048, 1536),
            slot("iphone", nil, nil, "portrait", 1, "", "", 320, 480),
            slot("iphone", nil, nil, "portrait", 2, "", "", 640, 960),
            slot("iphone", nil, "retina4", "portrait", 2, "-568h", "", 640, 1136),
            slot("ipad", nil, nil, "portrait", 1, "-Portrait", "", 768, 1024),
            slot("ipad", nil, nil, "portrait", 2, "-Portrait", "", 1536, 2048),
            slot("ipad", nil, nil, "landscape", 1, "-Landscape", "", 1024, 768),
            slot("ipad", nil, nil, "landscape", 2, "-Landscape", "", 2048, 1536),
            slot("ipad", nil, nil, "portrait", 1, "-Portrait", "", 768, 1004, extent: "to-status-bar"),
            slot("ipad", nil, nil, "portrait", 2, "-Portrait", "", 1536, 2008, extent: "to-status-bar"),
            slot("ipad", nil, nil, "landscape", 1, "-Landscape", "", 1024, 748, extent: "to-status-bar"),
            slot("ipad", nil, nil, "landscape", 2, "-Landscape", "", 2048, 1496, extent: "to-status-bar"),
        ]
    }()

    /// Idioms of other platforms: their entries count for nothing, and are no unassigned children.
    static let otherPlatforms: Set<String> = ["tv", "watch", "mac"]

    struct Compiled {
        var pngs: [(filename: String, image: PNGImage, path: String)] = []
        var infoPlist: [String: PropertyListValue] = [:]
        var warnings: [String] = []
        var notices: [String] = []
        var hasContent = false
    }

    private static func slot(of entry: [String: Any]) -> Slot? {
        let scale = ImageSet.scales[entry["scale"] as? String ?? ""]
        let matching = slots.filter {
            $0.idiom == entry["idiom"] as? String && $0.version == entry["minimum-system-version"] as? String && $0.subtype == entry["subtype"] as? String
                && $0.orientation == entry["orientation"] as? String && $0.scale == scale && $0.extent == entry["extent"] as? String
        }
        return matching.first
    }

    /// `named` for the set `--launch-image` names; `catalog` places the messages.
    static func compile(_ asset: AssetCatalog.Asset, named: Bool, catalog: String, targetDevices: [String]) throws -> Compiled {
        var compiled = Compiled()
        let folder = (asset.path as NSString).lastPathComponent
        let entries = asset.contents["images"] as? [[String: Any]] ?? []
        let filesNamed = Set(entries.compactMap { $0["filename"] as? String })
        let strays = ((try? FileManager.default.contentsOfDirectory(atPath: asset.path)) ?? []).sorted().filter { $0 != "Contents.json" && !$0.hasPrefix(".") && !filesNamed.contains($0) }
        var unassigned: [String] = []
        var problems: [String] = []
        var chosen: [(slot: Slot, image: PNGImage, path: String)] = []
        for entry in entries {
            let idiom = entry["idiom"] as? String ?? ""
            guard let slot = slot(of: entry) else {
                if !otherPlatforms.contains(idiom) {
                    let scale = entry["scale"] as? String ?? "", file = (entry["filename"] as? String).map { "[2d][\($0)]" } ?? ""
                    let keys = [idiom, entry["subtype"] as? String ?? "", scale, entry["orientation"] as? String ?? "", entry["extent"] as? String ?? "", entry["minimum-system-version"] as? String ?? ""]
                    unassigned.append(keys.map { "[\($0)]" }.joined() + file)
                }
                continue
            }
            guard targetDevices.contains(slot.idiom), let filename = entry["filename"] as? String else { continue }
            let place = "\(catalog):./\(folder)/[\(slot.idiom)][\(slot.subtype ?? "")][\(slot.scale)x][\(slot.orientation)][\(slot.extent)][\(slot.version ?? "")]"
            let path = asset.path + "/" + filename
            guard let data = FileManager.default.contents(atPath: path) else {
                problems.append("\(place): warning: The file \"\(filename)\" for the image set \"\(asset.name)\" does not exist.")
                continue
            }
            let image: PNGImage
            do { image = try PNGImage(data: [UInt8](data), path: path) } catch is PNGImage.Unreadable { continue }
            guard (image.width, image.height) == slot.pixels else {
                problems.append("\(place): warning: \(folder)/\(filename) is \(image.width)x\(image.height) but should be \(slot.pixels.width)x\(slot.pixels.height).")
                continue
            }
            chosen.append((slot, image, path))
        }
        compiled.hasContent = !chosen.isEmpty
        let children = unassigned.count + strays.count
        if children > 0 {
            let first = strays.first.map { "(null)[2d][\($0)]" } ?? unassigned[0]
            let count = children == 1 ? "an unassigned child" : "\(children) unassigned children"
            problems.insert("\(catalog):./\(folder)/\(first): warning: The launch image set \"\(asset.name)\" has \(count).", at: 0)
        }
        guard named else {
            compiled.warnings = problems + problems
            return compiled
        }
        // Entries without a slot make actool write a slot's PNG from a file of the set, not understood yet.
        guard unassigned.isEmpty && strays.isEmpty else {
            throw NomacError("launch image sets --launch-image names with entries or files without a slot are not supported yet (BACKLOG B-202)", path: asset.path)
        }
        var required: [String] = ["\(catalog):./\(folder): warning: Launch images are deprecated in iOS 13.0. Use a launch storyboard or XIB instead."]
        if targetDevices.contains("iphone"), !chosen.contains(where: { $0.slot.version == "7.0" && $0.slot.subtype == "retina4" }) {
            required.append("\(catalog):./\(folder): warning: An iPhone Retina (4-inch) launch image for iOS 7.0 and later is required.")
        }
        compiled.warnings = problems + required + problems
        var listed: [String] = []
        var images: [PropertyListValue] = []
        for slot in slots where slot.version != nil && chosen.contains(where: { $0.slot.name == slot.name && $0.slot.idiom == slot.idiom }) {
            guard !listed.contains(slot.name) else { continue }
            listed.append(slot.name)
            images.append(.dictionary([
                "UILaunchImageMinimumOSVersion": .string(slot.version!), "UILaunchImageName": .string(asset.name + slot.name),
                "UILaunchImageOrientation": .string(slot.orientation == "portrait" ? "Portrait" : "Landscape"), "UILaunchImageSize": .string(slot.points),
            ]))
        }
        if !images.isEmpty { compiled.infoPlist["UILaunchImages"] = .array(images) }
        if chosen.contains(where: { $0.slot.version == nil }) { compiled.infoPlist["UILaunchImageFile"] = .string(asset.name) }
        for (slot, image, path) in chosen {
            let scale = slot.scale > 1 ? "@\(slot.scale)x" : ""
            compiled.pngs.append((asset.name + slot.name + scale + (slot.idiom == "ipad" ? "~ipad" : "") + ".png", image, path))
            if slot.version == nil && slot.subtype == "retina4" {
                compiled.notices.append("\(catalog):./\(folder)/[iphone][retina4][2x][portrait][full-screen][]: notice: This launch image only applies to iOS 6.x and prior but the minimum deployment is 7.0 or later.")
            }
        }
        return compiled
    }
}
