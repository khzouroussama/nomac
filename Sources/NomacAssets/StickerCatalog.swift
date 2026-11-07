import Foundation
import NomacCore
import NomacPlist

/// iMessage sticker catalogs (docs/formats/asset-catalog.md, "Sticker packs"; firefox's and
/// wikipedia's, `stickers`): the stickers icon set `--app-icon` names gives its Messages App Store
/// image to `Assets.car` and its other sizes as icon PNGs; with `--include-sticker-content`, the
/// sticker pack is a folder of the stickers' files and a binary `Info.plist`.
enum StickerCatalog {
    /// The icon set entries actool assigns, and which of them it writes as PNGs.
    static let iconSlots: Set<String> = [
        "iphone 29x29 2", "iphone 29x29 3", "iphone 60x45 2", "iphone 60x45 3", "ipad 29x29 2", "ipad 67x50 2", "ipad 74x55 2",
        "universal 27x20 2", "universal 27x20 3", "universal 32x24 2", "universal 32x24 3", "ios-marketing 1024x768 1", "ios-marketing 1024x1024 1",
    ]
    static let pngSlots = ["universal 27x20 2", "universal 27x20 3", "universal 32x24 2", "universal 32x24 3", "iphone 60x45 2", "iphone 60x45 3",
                           "ipad 67x50 2", "ipad 74x55 2"]
    /// `CFBundleIconFiles` in actool's order, whatever the set's (`stickers` reversed).
    static let iconFileSizes = ["60x45", "67x50", "74x55", "27x20", "32x24"]
    static let layouts = ["small": "MSStickerSizeClassSmall", "regular": "MSStickerSizeClassRegular", "large": "MSStickerSizeClassLarge"]

    struct Compiled {
        var storeIcon: ImageSet.Source
        var pngs: [(filename: String, image: PNGImage, path: String)]
        var pack: (folder: String, files: [(name: String, path: String)], infoPlist: Data)?
        var infoPlist: [String: PropertyListValue]
    }

    static func compile(iconSet: AssetCatalog.Asset, pack: (asset: AssetCatalog.Asset, identifierPrefix: String)?) throws -> Compiled {
        guard Set(iconSet.contents.keys).isSubset(of: ["images", "info"]) else {
            throw NomacError("stickers icon set properties are not supported yet (BACKLOG B-202)", path: iconSet.path)
        }
        var icons: [String: (filename: String, path: String)] = [:]
        for entry in iconSet.contents["images"] as? [[String: Any]] ?? [] {
            guard let filename = entry["filename"] as? String else { continue }
            let slot = "\(entry["idiom"] as? String ?? "") \(entry["size"] as? String ?? "") \(ImageSet.scales[entry["scale"] as? String ?? ""] ?? 0)"
            guard iconSlots.contains(slot), icons[slot] == nil, (filename as NSString).pathExtension.lowercased() == "png" else {
                throw NomacError("stickers icon set entries other than one PNG per Messages size are not supported yet (BACKLOG B-202)", path: iconSet.path + "/" + filename)
            }
            icons[slot] = (filename, iconSet.path + "/" + filename)
        }
        guard let store = icons["ios-marketing 1024x768 1"], pngSlots.allSatisfy({ icons[$0] != nil }) else {
            throw NomacError("stickers icon sets without every Messages size are not supported yet (BACKLOG B-202)", path: iconSet.path)
        }
        var storeIcon = ImageSet.Source(name: iconSet.name, filename: store.filename, path: store.path, image: try PNGImage(contentsOf: store.path),
                                        idiom: Idiom.marketing)
        storeIcon.kind = .stickersIcon
        let pngs = try pngSlots.map { slot -> (filename: String, image: PNGImage, path: String) in
            let parts = slot.split(separator: " ")
            return ("\(iconSet.name)\(parts[1])@\(parts[2])x.png", try PNGImage(contentsOf: icons[slot]!.path), icons[slot]!.path)
        }
        let files = iconFileSizes.map { PropertyListValue.string(iconSet.name + $0) }
        var infoPlist: [String: PropertyListValue] = [
            "CFBundleIcons": .dictionary(["CFBundlePrimaryIcon": .dictionary(["CFBundleIconFiles": .array(files)])]),
            "MSMessagesExtensionStoreIconName": .string(iconSet.name),
        ]
        if let pack { infoPlist["IMStickerPackPath"] = .string((pack.asset.path as NSString).lastPathComponent) }
        return Compiled(storeIcon: storeIcon, pngs: pngs, pack: try pack.map { try compilePack($0.asset, identifierPrefix: $0.identifierPrefix) }, infoPlist: infoPlist)
    }

    /// The pack's stickers in its list's order, each file named after its sticker folder with
    /// the file's extension, and the pack's `Info.plist`.
    static func compilePack(_ pack: AssetCatalog.Asset, identifierPrefix: String) throws -> (folder: String, files: [(name: String, path: String)], infoPlist: Data) {
        let properties = pack.contents["properties"] as? [String: Any] ?? [:]
        guard Set(pack.contents.keys).isSubset(of: ["info", "properties", "stickers"]), Set(properties.keys).isSubset(of: ["grid-size"]),
              let layout = layouts[properties["grid-size"] as? String ?? ""] else {
            throw NomacError("sticker packs with properties other than a grid size are not supported yet (BACKLOG B-202)", path: pack.path)
        }
        var files: [(name: String, path: String)] = []
        var stickers: [PropertyListValue] = []
        for entry in pack.contents["stickers"] as? [[String: Any]] ?? [] {
            let folder = entry["filename"] as? String ?? ""
            let path = pack.path + "/" + folder
            let contents = try AssetCatalog.readContents(path, required: true)
            let sticker = contents["properties"] as? [String: Any] ?? [:]
            guard (folder as NSString).pathExtension == "sticker", Set(entry.keys) == ["filename"], Set(contents.keys).isSubset(of: ["info", "properties"]),
                  Set(sticker.keys).isSubset(of: ["filename", "accessibility-label"]), let filename = sticker["filename"] as? String else {
                throw NomacError("stickers other than a file with an accessibility label are not supported yet (BACKLOG B-202)", path: path)
            }
            let name = (folder as NSString).deletingPathExtension + "." + (filename as NSString).pathExtension
            files.append((name, path + "/" + filename))
            var record: [String: PropertyListValue] = ["IMStickerIdentifier": .string(name)]
            if let label = sticker["accessibility-label"] as? String { record["IMStickerAccessibilityLabel"] = .string(label) }
            stickers.append(.dictionary(record))
        }
        let name = (pack.path as NSString).lastPathComponent.replacingOccurrences(of: ".stickerpack", with: "")
        let info: [String: PropertyListValue] = [
            "CFBundleIdentifier": .string(identifierPrefix + name.replacingOccurrences(of: " ", with: "-")), "CFBundleName": .string(name),
            "CFBundlePackageType": .string("BUNDL"), "CFBundleShortVersionString": .string("1.0"), "CFBundleVersion": .string("1"),
            "IMStickerPackLayout": .string(layout), "IMStickers": .array(stickers),
        ]
        return ((pack.path as NSString).lastPathComponent, files, try BinaryPropertyList.foundationData(rereading: .dictionary(info)))
    }
}
