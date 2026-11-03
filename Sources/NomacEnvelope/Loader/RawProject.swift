import Foundation
import NomacCore

/// A project file read as written: every object with every key, unlike XcodeProj's model,
/// which keeps only the keys it knows. `nomac check` needs the keys it does not know.
struct RawProject {
    /// The `.xcodeproj` directory.
    let path: String
    /// The file the objects were read from.
    let file: String
    let topLevel: [String: Any]
    let objects: [String: [String: Any]]
    let rootID: String
    /// Each group child's group.
    private let parents: [String: String]

    var root: [String: Any] { objects[rootID] ?? [:] }

    /// The directory that holds the `.xcodeproj`, joined with `projectDirPath`.
    var projectDirectory: String {
        let containing = (path as NSString).deletingLastPathComponent
        let dirPath = root["projectDirPath"] as? String ?? ""
        if dirPath.isEmpty { return containing }
        if dirPath.hasPrefix("/") { return (dirPath as NSString).standardizingPath }
        return ((containing as NSString).appendingPathComponent(dirPath) as NSString).standardizingPath
    }

    enum LoadError: Error {
        case missing, unreadable(String)
    }

    static func load(_ path: String) throws(LoadError) -> RawProject {
        let file = path + "/project.pbxproj"
        guard let data = FileSystem.contents(atPath: file) else { throw .missing }
        let plist: Any
        do {
            plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        } catch {
            throw .unreadable("\(error)")
        }
        guard let topLevel = plist as? [String: Any], let objects = topLevel["objects"] as? [String: [String: Any]],
              let rootID = topLevel["rootObject"] as? String, objects[rootID] != nil else {
            throw .unreadable("no objects or root object")
        }
        var parents: [String: String] = [:]
        for (id, object) in objects {
            for child in object["children"] as? [String] ?? [] { parents[child] = id }
        }
        return RawProject(path: path, file: file, topLevel: topLevel, objects: objects, rootID: rootID, parents: parents)
    }

    func isa(_ id: String) -> String? { objects[id]?["isa"] as? String }

    func string(_ id: String, _ key: String) -> String? { objects[id]?[key] as? String }

    func strings(_ id: String, _ key: String) -> [String] { objects[id]?[key] as? [String] ?? [] }

    /// `PBXNativeTarget 1D6058900D05DD3D006BFB54 (App)`: how check reports name an object.
    func describe(_ id: String) -> String {
        guard let object = objects[id] else { return id }
        let isa = object["isa"] as? String ?? "object"
        let label = (object["name"] as? String) ?? (object["path"] as? String) ?? (object["productName"] as? String)
        return label.map { "\(isa) \(id) (\($0))" } ?? "\(isa) \(id)"
    }

    /// The absolute path a file element names, or nil when it is relative to a build setting
    /// other than `SOURCE_ROOT` (the products directory, the SDK, ...).
    func fullPath(_ id: String) -> String? {
        guard let object = objects[id] else { return nil }
        let path = object["path"] as? String ?? ""
        let base: String
        switch object["sourceTree"] as? String ?? "<group>" {
        case "<absolute>":
            return (path as NSString).standardizingPath
        case "SOURCE_ROOT":
            base = projectDirectory
        case "<group>":
            if let parent = parents[id] {
                guard let parentPath = fullPath(parent) else { return nil }
                base = parentPath
            } else {
                base = projectDirectory
            }
        default:
            return nil
        }
        return path.isEmpty ? base : ((base as NSString).appendingPathComponent(path) as NSString).standardizingPath
    }

    /// The targets of the project, in the project's order.
    var targetIDs: [String] { root["targets"] as? [String] ?? [] }

    /// The standardized paths of the projects `projectReferences` names.
    var referencedProjectPaths: [String] {
        (root["projectReferences"] as? [[String: Any]] ?? []).compactMap { reference in
            (reference["ProjectRef"] as? String).flatMap(fullPath)
        }
    }

    /// Keys whose values are object IDs of the same project.
    static let referenceKeys: Set<String> = [
        "buildConfigurationList", "buildConfigurations", "buildPhases", "buildRules", "children", "dependencies", "exceptions", "fileRef",
        "files", "fileSystemSynchronizedGroups", "mainGroup", "package", "packageProductDependencies", "packageReferences", "productRef",
        "productRefGroup", "productReference", "remoteRef", "target", "targetProxy", "targets", "baseConfigurationReference",
        "baseConfigurationReferenceAnchor", "currentVersion", "containerPortal",
    ]

    static func isObjectID(_ value: String) -> Bool {
        value.utf8.count == 24 && value.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
    }
}
