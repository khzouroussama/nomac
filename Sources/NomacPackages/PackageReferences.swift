import Foundation
import NomacCore
import NomacProject
import XcodeProj

/// The Swift packages a workspace uses, found as Xcode finds them.
///
/// Observed (netnewswire, icecubes, `package-experiments`):
///
/// * A folder holding `Package.swift` in a project's file tree, added as a file reference
///   (icecubes) or inside a synchronized folder (netnewswire), is a **root** package: its test
///   targets become test products and its settings carry no `dependency` tag.
/// * A package added with `XCLocalSwiftPackageReference` is a **dependency**, like a remote
///   package (`XCRemoteSwiftPackageReference`).
/// * Versions are pinned by `xcshareddata/swiftpm/Package.resolved` in the workspace (for a
///   project opened on its own, its `project.xcworkspace`), or by a single root package's own
///   `Package.resolved` when the workspace has none (``resolvedFile(workspace:rootPackages:)``).
public struct PackageReferences: Equatable, Sendable {
    /// Root packages, as absolute directory paths, in the order of the file trees.
    public var rootPackages: [String]
    /// Local packages referenced with `XCLocalSwiftPackageReference`, as absolute paths.
    public var localDependencies: [String]
    /// Remote packages referenced with `XCRemoteSwiftPackageReference`.
    public var remoteDependencies: [Remote]
    /// The `Package.resolved` file that pins the packages (it may not exist).
    public var resolvedFile: String

    public struct Remote: Equatable, Sendable {
        public var url: String
        public var requirement: Requirement

        public init(url: String, requirement: Requirement) {
            self.url = url
            self.requirement = requirement
        }
    }

    /// The version requirement of a remote package, as the project file states it.
    public enum Requirement: Equatable, Sendable {
        case upToNextMajorVersion(String)
        case upToNextMinorVersion(String)
        case range(from: String, to: String)
        case exact(String)
        case branch(String)
        case revision(String)
    }

    public init(rootPackages: [String], localDependencies: [String], remoteDependencies: [Remote], resolvedFile: String) {
        self.rootPackages = rootPackages
        self.localDependencies = localDependencies
        self.remoteDependencies = remoteDependencies
        self.resolvedFile = resolvedFile
    }

    public var isEmpty: Bool {
        rootPackages.isEmpty && localDependencies.isEmpty && remoteDependencies.isEmpty
    }

    /// The packages of `workspace` and of every project in it, those its projects reference
    /// included (loader-experiments `project-references-packages`): the package folders the
    /// workspace references are root packages too. A package referenced twice is listed once.
    public static func find(in workspace: XcodeWorkspace) throws -> PackageReferences {
        var references = PackageReferences(
            rootPackages: workspace.packageFolders, localDependencies: [], remoteDependencies: [],
            resolvedFile: workspace.path + "/xcshareddata/swiftpm/Package.resolved")
        for project in workspace.allProjects {
            let sourceRoot = project.projectDirectory
            if let mainGroup = project.project.mainGroup {
                try collectRootPackages(in: mainGroup, sourceRoot: sourceRoot, into: &references.rootPackages)
            }
            for local in project.project.localPackages {
                let path = ((sourceRoot as NSString).appendingPathComponent(local.relativePath) as NSString).standardizingPath
                if !references.localDependencies.contains(path) { references.localDependencies.append(path) }
            }
            for remote in project.project.remotePackages {
                guard let url = remote.repositoryURL, let requirement = remote.versionRequirement.map(Requirement.init) else { continue }
                let reference = Remote(url: url, requirement: requirement)
                if !references.remoteDependencies.contains(reference) { references.remoteDependencies.append(reference) }
            }
        }
        references.resolvedFile = resolvedFile(workspace: workspace.path, rootPackages: references.rootPackages)
        return references
    }

    /// The `Package.resolved` that pins a workspace's packages: the workspace's own when it has
    /// one, even if a root package pins other versions; otherwise that of the workspace's only
    /// root package, which resolution reads and leaves as it is (pocket-casts' `Modules`);
    /// otherwise the workspace's, which resolution writes. Two root packages, an unpinned one or
    /// a local dependency's own `Package.resolved` pin nothing (loader-experiments
    /// `package-pins-*`).
    static func resolvedFile(workspace: String, rootPackages: [String]) -> String {
        let shared = workspace + "/xcshareddata/swiftpm/Package.resolved"
        guard !FileManager.default.fileExists(atPath: shared), rootPackages.count == 1,
              FileManager.default.fileExists(atPath: rootPackages[0] + "/Package.resolved") else { return shared }
        return rootPackages[0] + "/Package.resolved"
    }

    /// Package folders under `element`: file references to a folder with `Package.swift`, and
    /// such folders inside synchronized folders (not descending into a package).
    private static func collectRootPackages(in element: PBXFileElement, sourceRoot: String, into packages: inout [String]) throws {
        switch element {
        case let synchronized as PBXFileSystemSynchronizedRootGroup:
            guard let path = try synchronized.fullPath(sourceRoot: sourceRoot) else { return }
            packageFolders(under: path, into: &packages)
        case let group as PBXGroup:
            for child in group.children {
                try collectRootPackages(in: child, sourceRoot: sourceRoot, into: &packages)
            }
        case let reference as PBXFileReference:
            guard let path = try reference.fullPath(sourceRoot: sourceRoot) else { return }
            let standardized = (path as NSString).standardizingPath
            if isPackage(standardized), !packages.contains(standardized) { packages.append(standardized) }
        default:
            return
        }
    }

    private static func isPackage(_ directory: String) -> Bool {
        FileSystem.exists(directory + "/Package.swift")
    }

    /// Package folders inside a synchronized folder, in name order, skipping hidden items as
    /// Xcode does in synchronized folders.
    private static func packageFolders(under directory: String, into packages: inout [String]) {
        let standardized = (directory as NSString).standardizingPath
        if isPackage(standardized) {
            if !packages.contains(standardized) { packages.append(standardized) }
            return
        }
        guard let names = try? FileSystem.contentsOfDirectory(standardized) else { return }
        for name in names.sorted() where !name.hasPrefix(".") {
            let path = standardized + "/" + name
            if FileSystem.isDirectory(path) {
                packageFolders(under: path, into: &packages)
            }
        }
    }
}

extension PackageReferences.Requirement {
    init(_ requirement: XCRemoteSwiftPackageReference.VersionRequirement) {
        switch requirement {
        case .upToNextMajorVersion(let version): self = .upToNextMajorVersion(version)
        case .upToNextMinorVersion(let version): self = .upToNextMinorVersion(version)
        case .range(let from, let to): self = .range(from: from, to: to)
        case .exact(let version): self = .exact(version)
        case .branch(let branch): self = .branch(branch)
        case .revision(let revision): self = .revision(revision)
        }
    }
}
