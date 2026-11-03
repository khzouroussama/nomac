import Foundation
import NomacCore
import PathKit
import XcodeProj

/// The objectVersions Xcode reads (`XcodeProfile.readableObjectVersions`); it fails every command
/// with status 74 on the others.
public let readableObjectVersions = Set(XcodeProfile.current.readableObjectVersions)

/// One Xcode project (`.xcodeproj`) loaded from disk.
///
/// Both on-disk formats are supported: the classic OpenStep property list
/// (`project.pbxproj`) and Xcode 27's JSON format (`project.xcproj`). Both are read into
/// XcodeProj's `PBXProj` object graph, which is the single model the PIF generator reads.
public struct XcodeProject: @unchecked Sendable {
    /// The absolute path of the `.xcodeproj` directory.
    public let path: String
    /// The project object graph.
    public let pbxproj: PBXProj
    /// The project's root object.
    public let project: PBXProject
    /// Which file the project was read from.
    public let format: Format
    /// The `dstSubfolderSpec` of copy-files phases whose value XcodeProj does not model (2 to 5,
    /// 8, 9, 17 and above), by phase object ID, read from the project file itself.
    public let unmodeledDestinationSubfolderSpecs: [String: Int]

    public enum Format: String, Sendable {
        case pbxproj
        case xcproj
    }

    /// The project's name: the `.xcodeproj` file name without its extension.
    public var name: String { ((path as NSString).lastPathComponent as NSString).deletingPathExtension }

    /// The `.xcodeproj` file name, for example `Rampage.xcodeproj`.
    public var fileName: String { (path as NSString).lastPathComponent }

    /// The directory containing the `.xcodeproj`.
    public var containingDirectory: String { (path as NSString).deletingLastPathComponent }

    /// The project directory (`PROJECT_DIR`, `SRCROOT`): the containing directory joined with
    /// the project's `projectDirPath`, if any, decomposed as Xcode spells it
    /// (loader-experiments `unicode-project-dir`).
    public var projectDirectory: String {
        let dirPath = project.projectDirPath
        if dirPath.isEmpty { return containingDirectory }
        if dirPath.hasPrefix("/") { return (dirPath as NSString).standardizingPath.decomposed }
        return ((containingDirectory as NSString).appendingPathComponent(dirPath) as NSString).standardizingPath.decomposed
    }

    /// Whether a configuration of the project or of one of its targets, or its base xcconfig file,
    /// assigns `SYMROOT` without a condition: Xcode's scheme builds of such a project opened alone
    /// then use the project's own build locations for every target (loader-experiments
    /// `symroot-targets`, `symroot-project-*`: any value, even empty or the default, and in Debug or
    /// Release only; not under an SDK condition, even one that applies; with -derivedDataPath too;
    /// a referenced project's do not count: `symroot-references-sub`).
    public var assignsSymroot: Bool {
        let lists = [project.buildConfigurationList] + project.targets.map(\.buildConfigurationList)
        return lists.compactMap { $0 }.flatMap(\.buildConfigurations).contains { configuration in
            if configuration.buildSettings.keys.contains(where: { XCConfigFile.key($0).map { $0.name == "SYMROOT" && $0.conditions.isEmpty } ?? false }) {
                return true
            }
            guard let base = configuration.baseConfiguration, let path = try? base.fullPath(sourceRoot: projectDirectory) else { return false }
            return XCConfigFile.assignments(at: path).contains { $0.name == "SYMROOT" && $0.conditions.isEmpty }
        }
    }

    /// The standardized paths of the projects this project references (`projectReferences`), in
    /// the project file's order.
    public var referencedProjectPaths: [String] {
        project.projects.compactMap { reference in
            guard let file = reference["ProjectRef"], let path = try? file.fullPath(sourceRoot: projectDirectory) else { return nil }
            return (path as NSString).standardizingPath.decomposed
        }
    }

    /// Loads the project at `path`, which must be an `.xcodeproj` directory. Its ``path`` is
    /// decomposed, as Xcode spells it.
    public static func load(path: String) throws -> XcodeProject {
        let absolute = FileSystem.xcodePath(path)
        guard absolute.hasSuffix(".xcodeproj") else {
            throw NomacError("not an Xcode project (expected a .xcodeproj directory)", path: absolute)
        }
        guard FileSystem.isDirectory(absolute) else {
            throw NomacError("the project does not exist", path: absolute)
        }
        let jsonPath = absolute + "/project.xcproj"
        let plistPath = absolute + "/project.pbxproj"
        let pbxproj: PBXProj
        let format: Format
        do {
            if FileSystem.isFile(jsonPath) {
                guard let data = FileSystem.contents(atPath: jsonPath) else {
                    throw NomacError("could not read the project file", path: jsonPath)
                }
                let name = ((absolute as NSString).lastPathComponent as NSString).deletingPathExtension
                pbxproj = try PBXProj(xcprojData: data, projectName: name)
                format = .xcproj
            } else if FileSystem.isFile(plistPath) {
                pbxproj = try PBXProj(path: Path(FileSystem.onDisk(plistPath)))
                format = .pbxproj
            } else {
                throw NomacError("the project contains neither project.pbxproj nor project.xcproj", path: absolute)
            }
        } catch let error as NomacError {
            throw error
        } catch {
            throw NomacError("could not parse the project: \(error)", path: absolute)
        }
        guard format == .xcproj || readableObjectVersions.contains(Int(pbxproj.objectVersion)) else {
            let name = ((absolute as NSString).lastPathComponent as NSString).deletingPathExtension
            throw NomacError("Unable to read project '\((absolute as NSString).lastPathComponent)'.", path: absolute, notes: [
                "Reason: Could not open “\(name)”",
                "The project has an unsupported Xcode project file format (objectVersion \(pbxproj.objectVersion)). Adjust the project format using a compatible version of Xcode to allow it to be opened by this version of Xcode.",
            ], exitStatus: 74)
        }
        guard let root = pbxproj.rootObject else {
            throw NomacError("the project has no root object", path: absolute)
        }
        var specs: [String: Int] = [:]
        let unmodeled = Set(pbxproj.copyFilesBuildPhases.filter { $0.dstSubfolderSpec == nil }.map(\.uuid))
        if format == .pbxproj, !unmodeled.isEmpty, let data = FileManager.default.contents(atPath: plistPath),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let objects = plist["objects"] as? [String: Any] {
            for id in unmodeled {
                if let value = (objects[id] as? [String: Any])?["dstSubfolderSpec"] as? String, let spec = Int(value) {
                    specs[id] = spec
                }
            }
        }
        return XcodeProject(path: absolute, pbxproj: pbxproj, project: root, format: format, unmodeledDestinationSubfolderSpecs: specs)
    }
}
