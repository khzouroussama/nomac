import Foundation
import NomacCore

/// The assets of one or more `.xcassets` folders, as actool reads them: every asset folder
/// (`Name.colorset`, ...) under the catalog, named by its folder name prefixed with the names
/// of the enclosing folders that provide a namespace.
public struct AssetCatalog {
    public struct Asset {
        public var name: String
        public var type: String
        public var path: String
        public var contents: [String: Any]
        /// The sprite atlas whose folder holds the asset.
        public var spriteAtlas: String?
        /// The role of an image set in the compiled complication set.
        public var complicationRole: String?
    }

    public var paths: [String]
    public var assets: [Asset]

    /// Asset folder extensions nomac compiles.
    static let supportedTypes: Set<String> = [
        "colorset", "dataset", "appiconset", "imageset", "launchimage", "solidimagestack", "spriteatlas", "stickersiconset", "stickerpack", "symbolset",
    ]

    /// `complication`: the complication set `--complication` names, the only one compiled.
    public static func load(_ paths: [String], complication: String? = nil) throws -> AssetCatalog {
        var assets: [Asset] = []
        for path in paths {
            try scan(folder: path, namespace: "", complication: complication, into: &assets)
        }
        return AssetCatalog(paths: paths, assets: assets)
    }

    private static func scan(folder: String, namespace: String, spriteAtlas: String? = nil, complication: String?, into assets: inout [Asset]) throws {
        for entry in try subfolders(of: folder) {
            let path = folder + "/" + entry
            guard let type = assetType(of: entry) else {
                try scan(folder: path, namespace: try providesNamespace(path) ? namespace + entry + "/" : namespace, spriteAtlas: spriteAtlas,
                         complication: complication, into: &assets)
                continue
            }
            if type == "complicationset" {
                let name = namespace + (entry as NSString).deletingPathExtension
                guard name == complication, spriteAtlas == nil else { continue }
                let contents = try readContents(path, required: true)
                assets.append(Asset(name: name, type: type, path: path, contents: contents))
                for (folder, role) in try ComplicationSet.roles(path, contents: contents) {
                    let member = path + "/" + folder
                    guard FileManager.default.fileExists(atPath: member + "/Contents.json") else { continue }
                    let base = (folder as NSString).deletingPathExtension
                    assets.append(Asset(name: name + "/" + base, type: "imageset", path: member, contents: try readContents(member, required: true),
                                        complicationRole: role))
                }
                continue
            }
            guard supportedTypes.contains(type) else {
                throw NomacError("asset type '.\(type)' is not supported yet (BACKLOG B-202)", path: path)
            }
            let base = (entry as NSString).deletingPathExtension
            // actool skips an image set folder without `Contents.json`, silently (tofu's
            // `Philips.imageset`, `images` no-contents).
            if type == "imageset" && !FileManager.default.fileExists(atPath: path + "/Contents.json") {
                continue
            }
            let asset = Asset(name: namespace + base, type: type, path: path, contents: try readContents(path, required: true), spriteAtlas: spriteAtlas)
            assets.append(asset)
            if type == "spriteatlas" {
                guard spriteAtlas == nil, try !providesNamespace(path) else {
                    throw NomacError("sprite atlases in sprite atlases or providing a namespace are not supported yet (BACKLOG B-202)", path: path)
                }
                try scan(folder: path, namespace: namespace, spriteAtlas: asset.name, complication: complication, into: &assets)
            }
        }
    }

    /// The asset folder extensions of Apple's asset catalog format reference. A folder with any
    /// other extension (`ABC.DEF`) is a group, as actool reads it (the `symbols` experiment).
    static let assetTypes: Set<String> = [
        "appiconset", "arimageset", "arresourcegroup", "brandassets", "colorset", "complicationset",
        "cubetextureset", "dataset", "gcdashboardimage", "gcleaderboard", "gcleaderboardset", "iconset", "imageset",
        "imagestack", "imagestacklayer", "launchimage", "mipmapset", "solidimagestack", "solidimagestacklayer",
        "spriteatlas", "sticker", "stickerpack", "stickersequence", "stickersiconset", "symbolset", "textureset",
    ]

    static func assetType(of entry: String) -> String? {
        let type = (entry as NSString).pathExtension
        return assetTypes.contains(type) ? type : nil
    }

    /// The folders in a catalog folder, by name, without hidden ones.
    static func subfolders(of folder: String) throws -> [String] {
        try FileSystem.sortedContents(of: folder).filter { !$0.hasPrefix(".") && FileSystem.isDirectory(folder + "/" + $0) }
    }

    static func providesNamespace(_ folder: String) throws -> Bool {
        let properties = try readContents(folder, required: false)["properties"] as? [String: Any]
        return properties?["provides-namespace"] as? Bool ?? false
    }

    static func readContents(_ folder: String, required: Bool) throws -> [String: Any] {
        let path = folder + "/Contents.json"
        guard let data = FileManager.default.contents(atPath: path) else {
            if required { throw NomacError("missing Contents.json", path: folder) }
            return [:]
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NomacError("malformed Contents.json", path: path)
        }
        return object
    }
}
