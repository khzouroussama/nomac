import Foundation
import NomacCore
import NomacProject

/// A complete PIF document: an ordered list of top-level objects (one workspace, its
/// projects, their targets), each with a type, a signature and contents.
public struct PIFDocument: Sendable, Equatable {
    /// One top-level PIF object.
    public struct Object: Sendable, Equatable {
        public var type: String
        public var signature: String
        public var contents: PIFValue

        var value: PIFValue {
            .object(["type": .string(type), "signature": .string(signature), "contents": contents])
        }
    }

    public var objects: [Object]

    /// The document in the exact text format `xcodebuild -dumpPIF` writes.
    public func serialized() -> String {
        PIFValue.array(objects.map(\.value)).serialized()
    }
}

/// GUID and signature conventions.
///
/// Observed from `xcodebuild -dumpPIF` (docs/formats/pif.md, "Identifiers"):
///
/// * workspace GUID: the MD5 hex digest of the workspace name;
/// * project GUID: the MD5 hex digest of the `.xcodeproj` path relative to the workspace's
///   folder: its file name for a project opened on its own (`loader-experiments`:
///   `One/P.xcodeproj` and `Two/P.xcodeproj` in one workspace), and a project it references
///   relative to the opened project's folder (moonlight, `project-references`);
/// * every other object: the project GUID followed by the MD5 hex digest of the object's
///   24-character identifier in the project file.
///
/// Signatures only have to be unique and stable; nomac uses the MD5 of the object's
/// serialized contents.
public enum PIFIdentifiers {
    public static func md5(_ text: String) -> String {
        MD5.hex(text)
    }

    public static func workspaceGUID(name: String) -> String {
        md5(name)
    }

    public static func projectGUID(fileName: String) -> String {
        md5(fileName)
    }

    /// The GUID of the project at `projectPath` in `workspace`.
    public static func projectGUID(projectPath: String, workspace: XcodeWorkspace) -> String {
        md5(relativeProjectPath(projectPath, workspace: workspace))
    }

    /// `projectPath` relative to the folder of `workspace` (for a project opened on its own,
    /// the folder that holds the project), with `..` components where it lies outside.
    static func relativeProjectPath(_ projectPath: String, workspace: XcodeWorkspace) -> String {
        let project = (projectPath as NSString).standardizingPath
        let projectComponents = (project as NSString).pathComponents
        let baseComponents = (workspace.directory as NSString).pathComponents
        var common = 0
        while common < min(projectComponents.count, baseComponents.count), projectComponents[common] == baseComponents[common] {
            common += 1
        }
        let up = Array(repeating: "..", count: baseComponents.count - common)
        return (up + projectComponents[common...]).joined(separator: "/")
    }

    public static func objectGUID(projectGUID: String, objectID: String) -> String {
        projectGUID + md5(objectID)
    }

    static func signature(prefix: String, contents: PIFValue) -> String {
        "\(prefix)@v11_hash=\(md5(contents.serialized()))"
    }
}
