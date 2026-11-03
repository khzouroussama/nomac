import Foundation
import NomacCore
import NomacPIF

/// The loader's features: everything that decides the PIF, `-list` and `-showBuildSettings`
/// (docs/formats/check.md). Files are read as written, so keys and elements nomac does not
/// know are reported too.
public struct LoaderDomain: FeatureDomain {
    public let name = "loader"
    public var envelope: Envelope { LoaderEnvelope.envelope }

    public init() {}

    public func scan(_ container: String, options: CheckOptions) throws -> DomainScan {
        let scan = LoaderScan(options: options)
        try scan.run(container: (FileSystem.absolute(container) as NSString).standardizingPath)
        return DomainScan(uses: scan.uses, unchecked: scan.unchecked)
    }
}

/// One `nomac check` pass over a workspace or project.
final class LoaderScan {
    let options: CheckOptions
    var uses: [FeatureUse] = []
    var unchecked: [UncheckedPart] = []
    /// Loaded projects by path, in the order they were reached.
    var projects: [RawProject] = []
    private var visitedProjects: Set<String> = []
    var visitedXCConfigs: Set<String> = []
    var visitedLevels: Set<String> = []
    var xcconfigSummaries: [String: XCConfigSummary] = [:]
    var visitedSchemeFolders: Set<String> = []
    var visitedTestPlans: Set<String> = []
    var packageDirectories: [String] = []
    /// Directory listings ``spelling(of:)`` read, by path.
    var listings: [String: [String]] = [:]
    /// Package folders in the file tree or the workspace: root packages, not dependencies.
    var rootPackageDirectories: Set<String> = []
    var remotePackageURLs: [String] = []
    /// Checkout names of remote packages pinned to a branch or a revision, not a version.
    var branchPinnedPackages: Set<String> = []
    var fileTypes: FileTypeRegistry?
    var fileTypesLoaded = false
    /// The container is a project opened alone, whose scheme builds honor `SYMROOT`
    /// (envelope-experiments `symroot-locations`; docs/formats/show-build-settings.md).
    var opensProject = false

    init(options: CheckOptions) {
        self.options = options
    }

    func use(_ feature: String, _ file: String, _ object: String) {
        uses.append(FeatureUse(feature: feature, file: file, object: object))
    }

    func run(container: String) throws {
        let workspacePath: String
        var pending: [String]
        switch (container as NSString).pathExtension {
        case "xcworkspace":
            guard FileSystem.isDirectory(container) else { throw NomacError("the workspace does not exist", path: container) }
            workspacePath = container
            pending = scanWorkspaceContents(container, implicit: false)
            scanSharedSchemes(in: container + "/xcshareddata/xcschemes", containerDirectory: (container as NSString).deletingLastPathComponent)
            scanUserData(of: container)
        case "xcodeproj":
            guard FileSystem.isDirectory(container) else { throw NomacError("the project does not exist", path: container) }
            opensProject = true
            workspacePath = container + "/project.xcworkspace"
            if FileSystem.isFile(workspacePath + "/contents.xcworkspacedata") { _ = scanWorkspaceContents(workspacePath, implicit: true) }
            pending = [container]
        default:
            throw NomacError("not an Xcode project or workspace (expected .xcodeproj or .xcworkspace)", path: container)
        }
        scanContainerName(container)
        scanWorkspaceSettings(workspacePath)
        while !pending.isEmpty {
            let path = pending.removeFirst()
            guard visitedProjects.insert(path).inserted, let project = scanProject(path) else { continue }
            projects.append(project)
            pending += project.referencedProjectPaths.filter { FileSystem.isDirectory($0) }
        }
        scanAcrossProjects()
        scanResolvedPackages(workspacePath)
        scanPackages()
    }

    // MARK: Workspace

    /// Reads `contents.xcworkspacedata`; returns the projects it lists that are on disk.
    private func scanWorkspaceContents(_ workspace: String, implicit: Bool) -> [String] {
        let file = workspace + "/contents.xcworkspacedata"
        guard let data = FileSystem.contents(atPath: file), let document = XMLTree.parse(data) else {
            use("workspace:unreadable", file, "contents.xcworkspacedata")
            return []
        }
        let directory = (workspace as NSString).deletingLastPathComponent
        var projects: [String] = []
        func walk(_ element: XMLTree, parent: String, base: String) {
            let path = parent.isEmpty ? element.name : parent + "/" + element.name
            use("workspace:\(parent.isEmpty ? "" : (parent as NSString).lastPathComponent + "/")\(element.name)", file, path)
            var location: String?
            for (attribute, value) in element.attributes.sorted(by: { $0.key < $1.key }) {
                use("workspace:\(element.name)@\(attribute)", file, path)
                if attribute == "location" {
                    let scheme = value.firstIndex(of: ":").map { String(value[..<$0]) } ?? ""
                    use("workspace:\(element.name)@location=\(scheme)", file, path)
                    location = value
                } else if attribute == "version" {
                    use("workspace:\(element.name)@version=\(value)", file, path)
                }
            }
            let resolved = location.map { Self.resolveWorkspaceLocation($0, base: base, workspaceDirectory: directory) } ?? base
            if element.name == "FileRef", let location {
                let kind = workspaceItemKind(resolved, implicit: implicit, location: location)
                use("workspace:FileRef=\(kind)", file, "\(path) \(location)")
                if kind == "project" { projects.append(resolved) }
                if kind == "package" { addPackageDirectory(resolved, root: true) }
            }
            for child in element.children { walk(child, parent: path, base: element.name == "Group" ? resolved : base) }
        }
        walk(document, parent: "", base: directory)
        return projects
    }

    private func workspaceItemKind(_ path: String, implicit: Bool, location: String) -> String {
        if implicit && location.hasPrefix("self:") { return "self" }
        switch (path as NSString).pathExtension {
        case "xcodeproj": return FileSystem.isDirectory(path) ? "project" : "project-missing"
        case "xcworkspace": return "workspace"
        case "playground": return "playground"
        default: return FileSystem.isFile(path + "/Package.swift") ? "package" : "other"
        }
    }

    /// A workspace location (`group:`, `container:`, `absolute:`, `self:`, ...) as a path.
    static func resolveWorkspaceLocation(_ location: String, base: String, workspaceDirectory: String) -> String {
        let colon = location.firstIndex(of: ":")
        let scheme = colon.map { String(location[..<$0]) } ?? ""
        let path = colon.map { String(location[location.index(after: $0)...]) } ?? location
        let joined: String
        switch scheme {
        case "absolute", "developer": joined = path
        case "container": joined = (workspaceDirectory as NSString).appendingPathComponent(path)
        default: joined = (base as NSString).appendingPathComponent(path)
        }
        return (joined as NSString).standardizingPath
    }

    /// The opened workspace's shared settings, workspace checks and package configuration.
    private func scanWorkspaceSettings(_ workspace: String) {
        let shared = workspace + "/xcshareddata"
        for (name, namespace) in [("WorkspaceSettings.xcsettings", "workspace-settings"), ("IDEWorkspaceChecks.plist", "workspace-checks")] {
            let file = shared + "/" + name
            guard FileSystem.isFile(file) else { continue }
            guard let data = FileSystem.contents(atPath: file),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                use("\(namespace):unreadable", file, name)
                continue
            }
            for (key, value) in plist.sorted(by: { $0.key < $1.key }) {
                use("\(namespace):\(key)", file, key)
                if let scalar = Self.scalar(value) { use("\(namespace):\(key)=\(scalar)", file, key) }
            }
        }
        if FileSystem.isDirectory(shared + "/swiftpm/configuration") {
            for name in (try? FileSystem.sortedContents(of: shared + "/swiftpm/configuration")) ?? [] where !name.hasPrefix(".") {
                use("package:configuration=\(name)", shared + "/swiftpm/configuration/" + name, name)
            }
        }
        scanUserData(of: workspace)
    }

    /// Per-user data committed with a workspace or project: user schemes and settings. Xcode reads
    /// them only for the user they belong to.
    func scanUserData(of container: String) {
        let userData = container + "/xcuserdata"
        guard FileSystem.isDirectory(userData) else { return }
        for user in (try? FileSystem.sortedContents(of: userData)) ?? [] where user.hasSuffix(".xcuserdatad") {
            let directory = userData + "/" + user
            for name in (try? FileSystem.sortedContents(of: directory + "/xcschemes")) ?? [] {
                if name.hasSuffix(".xcscheme") { use("scheme:location=user", directory + "/xcschemes/" + name, "Scheme") }
                if name == "xcschememanagement.plist" { use("scheme:management=user", directory + "/xcschemes/" + name, "xcschememanagement") }
            }
            if FileSystem.isFile(directory + "/WorkspaceSettings.xcsettings") {
                use("workspace-settings:user", directory + "/WorkspaceSettings.xcsettings", user)
            }
        }
    }

    /// A property list value as a feature value: booleans, numbers and short strings.
    static func scalar(_ value: Any) -> String? {
        switch value {
        case let bool as Bool: return bool ? "true" : "false"
        case let number as NSNumber: return number.stringValue
        case let string as String where string.count <= 40 && !string.contains("/"): return string
        default: return nil
        }
    }
}
