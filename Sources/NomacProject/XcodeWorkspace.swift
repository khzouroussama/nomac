import Foundation
import NomacCore
import PathKit
import XcodeProj

/// A workspace: the set of projects Xcode builds together.
///
/// Opening a bare `.xcodeproj` in Xcode opens its implicit workspace,
/// `<name>.xcodeproj/project.xcworkspace`, which contains only that project. nomac models
/// both cases the same way, as Xcode does.
public struct XcodeWorkspace: @unchecked Sendable {
    /// The workspace path: an `.xcworkspace`, or the implicit `project.xcworkspace` inside a project.
    public let path: String
    /// The workspace name: the `.xcworkspace` (or `.xcodeproj`) file name without extension.
    public let name: String
    /// The projects in the workspace, in workspace order.
    public let projects: [XcodeProject]
    /// The project the user opened, when a bare `.xcodeproj` was loaded.
    public let isImplicit: Bool
    /// The projects the workspace's projects reference (`projectReferences`), directly or
    /// through each other, that the workspace does not list, in the order they are reached. Xcode
    /// loads them as projects of the workspace (moonlight: `moonlight-common.xcodeproj`;
    /// loader-experiments `project-references`: a project referenced by a referenced project
    /// too). A referenced project that is not on disk is left out (`project-references-missing`).
    public private(set) var referencedProjects: [XcodeProject] = []
    /// Swift package folders the workspace references itself (not through a project), in
    /// workspace order (cwa: `ENA/ENASecurity`, `ENA/HealthCertificateToolkit`).
    public var packageFolders: [String] = []
    /// Whether the workspace is a Swift package folder's (``package(folder:name:)``).
    public private(set) var isPackage = false

    /// Whether Xcode autocreates schemes for this workspace: yes, unless its shared settings
    /// (`xcshareddata/WorkspaceSettings.xcsettings`) set
    /// `IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded` to false. A per-user copy in
    /// `xcuserdata` is not read, nor a member project's own `project.xcworkspace` when an
    /// `.xcworkspace` is opened (loader-experiments `autocreate-contexts`; kickstarter).
    public var autocreatesSchemes: Bool {
        guard let data = FileSystem.contents(atPath: path + "/xcshareddata/WorkspaceSettings.xcsettings"),
              let settings = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let autocreate = settings["IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded"] as? Bool else { return true }
        return autocreate
    }

    /// Loads an `.xcodeproj` or `.xcworkspace`. Its ``path`` and ``name`` are decomposed, as
    /// Xcode spells them.
    public static func load(path: String) throws -> XcodeWorkspace {
        let absolute = FileSystem.xcodePath(path)
        switch (absolute as NSString).pathExtension {
        case "xcodeproj":
            let project = try XcodeProject.load(path: absolute)
            var workspace = XcodeWorkspace(path: absolute + "/project.xcworkspace", name: project.name, projects: [project], isImplicit: true)
            try workspace.loadReferencedProjects()
            return workspace
        case "xcworkspace":
            return try loadWorkspace(absolute)
        default:
            throw NomacError("not an Xcode project or workspace (expected .xcodeproj or .xcworkspace)", path: absolute)
        }
    }

    /// A Swift package folder, as xcodebuild opens one in a folder with a `Package.swift` and
    /// neither `-project` nor `-workspace` (expo-default's nested build of ExpoModulesJSI, Xcode
    /// 27.0): the workspace `<folder>/.swiftpm/xcode/package.xcworkspace`, named after the
    /// package (`name`, its manifest's, not the folder's), with the folder as its one root package.
    public static func package(folder: String, name: String) -> XcodeWorkspace {
        let absolute = FileSystem.xcodePath(folder)
        var workspace = XcodeWorkspace(path: absolute + "/.swiftpm/xcode/package.xcworkspace", name: name, projects: [], isImplicit: false)
        workspace.packageFolders = [absolute]
        workspace.isPackage = true
        return workspace
    }

    private static func loadWorkspace(_ path: String) throws -> XcodeWorkspace {
        guard FileSystem.isDirectory(path) else {
            throw NomacError("the workspace does not exist", path: path)
        }
        let dataPath = path + "/contents.xcworkspacedata"
        guard FileSystem.isFile(dataPath) else {
            throw NomacError("the workspace has no contents.xcworkspacedata", path: path)
        }
        let data: XCWorkspaceData
        do {
            data = try XCWorkspaceData(path: Path(FileSystem.onDisk(dataPath)))
        } catch {
            throw NomacError("could not parse the workspace: \(error)", path: dataPath)
        }
        let workspaceDirectory = (path as NSString).deletingLastPathComponent
        var references: [String] = []
        collectFileReferences(data.children, base: workspaceDirectory, workspaceDirectory: workspaceDirectory, into: &references)
        let projectPaths = references.filter { $0.hasSuffix(".xcodeproj") }
        // A project the workspace lists that is not on disk leaves no trace in Xcode's outputs
        // (envelope-experiments `workspace-refs`: CocoaPods' Pods.xcodeproj before `pod install`).
        let projects = try projectPaths.filter(FileSystem.isDirectory).map { try XcodeProject.load(path: $0) }
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        var workspace = XcodeWorkspace(path: path, name: name, projects: projects, isImplicit: false)
        workspace.packageFolders = references.filter { FileSystem.isFile($0 + "/Package.swift") }
        try workspace.loadReferencedProjects()
        return workspace
    }

    /// Every project of the workspace: its own, then those they reference.
    public var allProjects: [XcodeProject] { projects + referencedProjects }

    /// The folder project GUIDs are relative to: the workspace's, or for a project opened on its
    /// own, the folder that holds it (moonlight: `md5("moonlight-common/moonlight-common.xcodeproj")`).
    public var directory: String {
        let path = (self.path as NSString).standardizingPath as NSString
        return isImplicit ? (path.deletingLastPathComponent as NSString).deletingLastPathComponent : path.deletingLastPathComponent
    }

    private mutating func loadReferencedProjects() throws {
        var loaded = Set(projects.map { ($0.path as NSString).standardizingPath })
        var pending = projects
        while !pending.isEmpty {
            let project = pending.removeFirst()
            for path in project.referencedProjectPaths where loaded.insert(path).inserted && FileSystem.isDirectory(path) {
                let referenced = try XcodeProject.load(path: path)
                referencedProjects.append(referenced)
                pending.append(referenced)
            }
        }
    }

    /// Walks workspace elements depth first, resolving each file reference once.
    private static func collectFileReferences(_ elements: [XCWorkspaceDataElement], base: String, workspaceDirectory: String, into result: inout [String]) {
        for element in elements {
            switch element {
            case .file(let file):
                let resolved = resolve(file.location, base: base, workspaceDirectory: workspaceDirectory)
                if !result.contains(resolved) {
                    result.append(resolved)
                }
            case .group(let group), .fileSystemSynchronizedGroup(let group):
                let groupBase = resolve(group.location, base: base, workspaceDirectory: workspaceDirectory)
                collectFileReferences(group.children, base: groupBase, workspaceDirectory: workspaceDirectory, into: &result)
            }
        }
    }

    /// Resolves a workspace location (`group:`, `container:`, `absolute:`, `self:`, ...)
    /// to an absolute path.
    static func resolve(_ location: XCWorkspaceDataElementLocationType, base: String, workspaceDirectory: String) -> String {
        let joined: String
        switch location {
        case .absolute(let path):
            joined = path
        case .container(let path):
            joined = (workspaceDirectory as NSString).appendingPathComponent(path)
        case .group(let path):
            joined = (base as NSString).appendingPathComponent(path)
        case .current(let path):
            joined = (base as NSString).appendingPathComponent(path)
        case .developer(let path):
            joined = path
        case .other(_, let path):
            joined = (base as NSString).appendingPathComponent(path)
        }
        return (joined as NSString).standardizingPath.decomposed
    }
}
