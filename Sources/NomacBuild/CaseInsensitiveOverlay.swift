import Foundation
import NomacCore
import NomacPIF

/// A virtual file system overlay that makes clang's and the Swift compiler's lookups of headers
/// and frameworks case-insensitive, as on a Mac's default file system, where projects find
/// `#include <openssl/evp.h>` in `OpenSSL.framework` (moonlight). Built only on a case-sensitive
/// file system and passed as `-ivfsoverlay` and `-vfsoverlay`: it lists the header files under
/// the source roots, whose names the compilers then match in any case, and for each framework the
/// build produces or copies, an entry for it in each products folder, which matches it in any
/// case once it is there (BACKLOG B-062). Observed: an overlay that only remaps a root folder onto
/// itself is not enough, the rest of a path being looked up on the real file system.
public enum CaseInsensitiveOverlay {
    static let headerExtensions: Set<String> = ["h", "hh", "hpp", "hxx", "h++", "inc", "inl", "ipp", "tcc", "def", "modulemap", "apinotes"]

    /// Whether the file system holding `path`, an existing item whose name has letters, tells
    /// names apart by case: whether its name with every letter's case swapped names nothing.
    public static func isCaseSensitive(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        let swapped = String(name.map { $0.isUppercase ? Character($0.lowercased()) : Character($0.uppercased()) })
        guard swapped != name else { return true }
        return !FileManager.default.fileExists(atPath: (path as NSString).deletingLastPathComponent + "/" + swapped)
    }

    /// The names of the frameworks the build makes: the framework products of `document`'s
    /// targets, and the frameworks of the xcframeworks under `roots` (the project's own and
    /// packages' binary targets), which the build copies into the products folder.
    public static func frameworkNames(document: PIFDocument, roots: [String]) -> Set<String> {
        var names: Set<String> = []
        for object in document.objects where object.type == "target" {
            if let name = object.contents.objectValue?["productReference"]?.objectValue?["name"]?.stringValue, name.hasSuffix(".framework"), !name.contains("$") {
                names.insert(name)
            }
        }
        for root in roots {
            guard let walker = FileManager.default.enumerator(atPath: root) else { continue }
            while let relative = walker.nextObject() as? String {
                let name = (relative as NSString).lastPathComponent
                if name.hasSuffix(".framework") {
                    if relative.contains(".xcframework/") { names.insert(name) }
                    walker.skipDescendants()
                }
            }
        }
        return names
    }

    /// The overlay, as JSON (a subset of the YAML the compilers read).
    public static func document(sourceRoots: [String], frameworks: Set<String>, productFolders: [String]) throws -> Data {
        var roots: [[String: Any]] = sourceRoots.compactMap { root in headerTree(root).map { $0.merging(["name": root]) { $1 } } }
        for folder in productFolders {
            for name in frameworks.sorted() {
                roots.append(["name": folder + "/" + name, "type": "directory-remap", "external-contents": folder + "/" + name])
            }
        }
        return try JSONSerialization.data(withJSONObject: ["version": 0, "case-sensitive": "false", "roots": roots], options: [.sortedKeys, .withoutEscapingSlashes])
    }

    /// `directory`'s header files and the folders holding them, or `nil` when it has none.
    static func headerTree(_ directory: String) -> [String: Any]? {
        guard let entries = try? FileSystem.sortedContents(of: directory) else { return nil }
        var contents: [[String: Any]] = []
        for entry in entries {
            let path = directory + "/" + entry
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                if (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil { continue }
                if var child = headerTree(path) {
                    child["name"] = entry
                    contents.append(child)
                }
            } else if headerExtensions.contains((entry as NSString).pathExtension.lowercased()) {
                contents.append(["name": entry, "type": "file", "external-contents": path])
            }
        }
        return contents.isEmpty ? nil : ["type": "directory", "contents": contents]
    }
}
