import Foundation
import NomacCore
import NomacPackages
import NomacProject

/// The project or workspace an xcodebuild-style command works on.
enum Container {
    /// `-project` or `-workspace`, or, with neither, the only workspace or else the only project
    /// in the current directory, as xcodebuild chooses; with none of them, a Swift package folder.
    static func path(project: String?, workspace: String?) throws -> String {
        switch (project, workspace) {
        case let (project?, nil): return project
        case let (nil, workspace?): return workspace
        case (.some, .some):
            throw NomacError("-project and -workspace cannot be combined")
        case (nil, nil):
            let entries = try FileSystem.sortedContents(of: FileManager.default.currentDirectoryPath)
            let workspaces = entries.filter { $0.hasSuffix(".xcworkspace") }
            let projects = entries.filter { $0.hasSuffix(".xcodeproj") }
            if workspaces.count == 1 { return workspaces[0] }
            if projects.count == 1 { return projects[0] }
            if workspaces.isEmpty, projects.isEmpty, entries.contains("Package.swift") { return FileManager.default.currentDirectoryPath }
            throw NomacError("the current directory contains \(projects.count) projects and \(workspaces.count) workspaces; specify one with -project or -workspace")
        }
    }

    /// The workspace of a container ``path(project:workspace:)`` chose: a project's, a
    /// workspace's, or a Swift package folder's, named after its manifest.
    static func load(_ path: String) async throws -> XcodeWorkspace {
        let extensionName = (path as NSString).pathExtension
        guard extensionName != "xcodeproj", extensionName != "xcworkspace", FileSystem.isFile(path + "/Package.swift") else {
            return try XcodeWorkspace.load(path: path)
        }
        let folder = FileSystem.absolute(path)
        return .package(folder: folder, name: try await SwiftPackages.manifestName(folder: folder))
    }
}
