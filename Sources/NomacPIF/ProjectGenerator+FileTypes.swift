import Foundation
import XcodeProj

/// The types of file references (docs/formats/pif.md, "Group tree").
extension ProjectGenerator {
    /// The absolute path of every file reference under `mainGroup` whose location is on the
    /// file system: relative to its group, the project's directory or absolute.
    static func referencePaths(mainGroup: PBXGroup, projectDirectory: String) -> [String: String] {
        var paths: [String: String] = [:]
        func walk(_ element: PBXFileElement, parentDirectory: String?) {
            let path: String?
            switch element.sourceTree {
            case nil, .group?:
                path = parentDirectory.flatMap { directory(of: element, parentDirectory: $0, projectDirectory: projectDirectory) }
            default:
                path = directory(of: element, parentDirectory: projectDirectory, projectDirectory: projectDirectory)
            }
            if element is PBXFileReference {
                paths[element.uuid] = path
            } else if let group = element as? PBXGroup {
                for child in group.children { walk(child, parentDirectory: path) }
            }
        }
        walk(mainGroup, parentDirectory: projectDirectory)
        return paths
    }

    /// The type Xcode gives a file reference: its declared type when Xcode knows it, else the
    /// type of what is on disk (``FileTypeRegistry/referenceFileType(explicit:lastKnown:name:path:)``).
    /// nomac types a reference relative to the SDK, the developer directory or the build
    /// products as a path that is not on disk; Xcode finds the first two (BACKLOG B-033).
    func fileType(of reference: PBXFileReference) -> String {
        let name = ((reference.path ?? reference.name ?? "") as NSString).lastPathComponent
        return fileTypes!.referenceFileType(explicit: reference.explicitFileType, lastKnown: reference.lastKnownFileType, name: name,
                                            path: referencePaths[reference.uuid])
    }
}
