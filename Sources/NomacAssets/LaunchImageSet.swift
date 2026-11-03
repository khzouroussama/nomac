import NomacCore

/// Launch image sets whose entries all have an `extent` and no file, as uncloudnotes' has, add
/// nothing and print nothing (`assets-experiments app-icons`); an entry without an `extent` is an
/// "unassigned child" actool warns about twice.
enum LaunchImageSet {
    static func check(_ asset: AssetCatalog.Asset) throws {
        let entries = asset.contents["images"] as? [[String: Any]] ?? []
        guard Set(asset.contents.keys).isSubset(of: ["images", "info"]), entries.allSatisfy({ $0["filename"] == nil && $0["extent"] != nil }) else {
            throw NomacError("launch image sets with images, or entries without an extent, are not supported yet (BACKLOG B-202)", path: asset.path)
        }
    }
}
