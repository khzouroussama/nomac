import Foundation
import NomacCore

/// Watch complication sets (`.complicationset`, pocket-casts' watch app; `complications`
/// experiment). actool compiles only the one `--complication` names: its image sets as image
/// sets named under its name, as in a folder providing a namespace, whether its list names them
/// or not; other complication sets are left out of `Assets.car` and the asset symbols.
enum ComplicationSet {
    /// Each role's image size in pixels for the 38mm, 42mm, 40mm and 44mm screen widths (actool's
    /// size warnings, pocket-casts' images); the graphic roles have none for 38mm and 42mm but
    /// graphic-extra-large.
    static let sizes: [String: [String: [Int]]] = [
        "circular": ["<=145": [32, 32], ">145": [36, 36], ">161": [36, 36], ">183": [40, 40]],
        "extra-large": ["<=145": [182, 182], ">145": [203, 203], ">161": [203, 203], ">183": [224, 224]],
        "graphic-bezel": [">161": [84, 84], ">183": [94, 94]],
        "graphic-circular": [">161": [84, 84], ">183": [94, 94]],
        "graphic-corner": [">161": [40, 40], ">183": [44, 44]],
        "graphic-extra-large": ["<=145": [206, 206], ">145": [240, 240], ">161": [240, 240], ">183": [264, 264]],
        "graphic-large-rectangular": [">161": [300, 94], ">183": [342, 108]],
        "modular": ["<=145": [52, 52], ">145": [58, 58], ">161": [58, 58], ">183": [64, 64]],
        "utilitarian": ["<=145": [40, 40], ">145": [44, 44], ">161": [44, 44], ">183": [50, 50]],
    ]

    /// The set's image set folders and their roles, in folder order. An entry for a folder that
    /// does not exist is passed over silently; actool warns about an unknown role and about an
    /// image set the list leaves out, where nomac stops.
    static func roles(_ path: String, contents: [String: Any]) throws -> [(folder: String, role: String)] {
        guard Set(contents.keys).isSubset(of: ["assets", "info"]) else {
            throw NomacError("complication set properties \(Set(contents.keys).subtracting(["assets", "info"]).sorted()) are not supported yet (BACKLOG B-204)", path: path)
        }
        var roles: [String: String] = [:]
        for entry in contents["assets"] as? [[String: Any]] ?? [] {
            guard let folder = entry["filename"] as? String, let role = entry["role"] as? String, entry["idiom"] as? String == "watch",
                  Set(entry.keys).isSubset(of: ["filename", "idiom", "role"]) else {
                throw NomacError("complication set entries other than a watch image set with a role are not supported yet (BACKLOG B-204)", path: path)
            }
            guard sizes[role] != nil else {
                throw NomacError("complication role '\(role)' is not supported: actool warns about it (BACKLOG B-204)", path: path)
            }
            roles[folder] = role
        }
        return try AssetCatalog.subfolders(of: path).map { folder in
            guard AssetCatalog.assetType(of: folder) == "imageset", let role = roles[folder] else {
                throw NomacError("complication set items other than the image sets its list names are not supported: actool warns about them (BACKLOG B-204)",
                                 path: path + "/" + folder)
            }
            return (folder, role)
        }
    }

    /// An image of another size than its role's gets warnings that actool prints in an order that
    /// changes from run to run; nomac stops on it.
    static func checkSize(_ image: PNGImage, role: String, screenWidth: String?, path: String) throws {
        guard let size = screenWidth.flatMap({ sizes[role]?[$0] }) else {
            throw NomacError("complication images for role '\(role)' without one of its screen widths are not supported yet (BACKLOG B-204)", path: path)
        }
        guard [image.width, image.height] == size else {
            throw NomacError("complication images of another size than \(size[0]) x \(size[1]) are not supported: actool warns about them (BACKLOG B-204)", path: path)
        }
    }
}
