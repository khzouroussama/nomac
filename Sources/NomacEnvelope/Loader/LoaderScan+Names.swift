import Foundation
import NomacCore

/// Names outside ASCII and names whose spelling Xcode rewrites: docs/formats/pif.md "Unicode"
/// and docs/formats/show-build-settings.md (DerivedData folder names).
extension LoaderScan {
    /// Keys of synchronized-folder objects that name an item by its path in the folder, matched
    /// byte for byte with the item's decomposed path.
    static let relativePathKeys: Set<String> = [
        "membershipExceptions", "publicHeaders", "privateHeaders", "attributesByRelativePath", "additionalCompilerFlagsByRelativePath",
        "explicitFileTypes", "baseConfigurationReferenceRelativePath",
    ]

    static func isASCII(_ text: String) -> Bool {
        text.utf8.allSatisfy { $0 < 0x80 }
    }

    /// The opened container's name: outside ASCII, or with the whitespace a DerivedData folder
    /// name replaces with `_`.
    func scanContainerName(_ container: String) {
        let name = ((container as NSString).lastPathComponent as NSString).deletingPathExtension
        if !Self.isASCII(name) { use("names:container=non-ascii", container, name) }
        if name.unicodeScalars.contains(where: { [" ", "\t", "\r", "\n"].contains($0) }) { use("names:container=whitespace", container, name) }
    }

    /// Strings of a project file outside ASCII: as written, or, for the paths of
    /// synchronized-folder items, precomposed or decomposed.
    func scanProjectNames(_ project: RawProject) {
        for id in project.objects.keys.sorted() {
            guard let object = project.objects[id] else { continue }
            for (key, value) in object {
                if Self.relativePathKeys.contains(key) {
                    let paths = (value as? [String: Any]).map { Array($0.keys) } ?? Self.strings(in: value, keys: false)
                    for path in paths where !Self.isASCII(path) {
                        use(path.isIdentical(to: path.decomposed) ? "names:sync-key=decomposed" : "names:sync-key=precomposed", project.file, project.describe(id))
                    }
                } else if key == "explicitFolders" {
                    if Self.strings(in: value, keys: true).contains(where: { !Self.isASCII($0) }) {
                        use("names:sync-explicit-folder=non-ascii", project.file, project.describe(id))
                    }
                } else if Self.strings(in: value, keys: true).contains(where: { !Self.isASCII($0) }) {
                    use("names:pbxproj=non-ascii", project.file, project.describe(id))
                }
            }
        }
    }

    /// Every string in a property-list value, with the keys of its dictionaries when `keys`.
    static func strings(in value: Any, keys: Bool) -> [String] {
        switch value {
        case let string as String: return [string]
        case let array as [Any]: return array.flatMap { strings(in: $0, keys: keys) }
        case let dictionary as [String: Any]: return dictionary.flatMap { (keys ? [$0.key] : []) + strings(in: $0.value, keys: keys) }
        default: return []
        }
    }

    /// Whether the last component of `path` is on disk in another normalization form only.
    static func spelledOtherwiseOnDisk(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        guard !isASCII(name), let entries = try? FileSystem.contentsOfDirectory((path as NSString).deletingLastPathComponent) else { return false }
        return !entries.contains { $0.isIdentical(to: name) } && entries.contains { $0 == name }
    }
}
