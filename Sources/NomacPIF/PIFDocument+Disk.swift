import Foundation
import NomacCore

extension PIFDocument {
    /// The document Swift Build loads: the same, except that each file reference whose path is
    /// spelled otherwise on disk is named by its absolute path on disk. Xcode finds such a file on
    /// a Mac in either normalization form (loader-experiments `unicode-nfc`, `unicode-nfd`:
    /// `Ödd.xcconfig`) and in any case (cwa's `PDFGeneration` folder, `PdfGeneration` on disk);
    /// Swift Build opens files by the bytes of their paths, which on Linux find a file only as
    /// spelled on disk ("Build input file cannot be found"; BACKLOG B-062). The PIF nomac writes
    /// and compares keeps Xcode's spelling.
    public func resolvingPathsOnDisk() -> PIFDocument {
        var document = self
        for index in document.objects.indices where document.objects[index].type == "project" {
            guard var contents = document.objects[index].contents.objectValue, let directory = contents["projectDirectory"]?.stringValue,
                  let tree = contents["groupTree"] else { continue }
            contents["groupTree"] = Self.resolve(tree, directory: directory, projectDirectory: directory)
            document.objects[index].contents = .object(contents)
        }
        return document
    }

    /// The paths of the projects' file references, as the project spells them.
    public func fileReferencePaths() -> [String] {
        var files: [String: String] = [:]
        for object in objects where object.type == "project" {
            guard let contents = object.contents.objectValue, let directory = contents["projectDirectory"]?.stringValue,
                  let tree = contents["groupTree"] else { continue }
            Self.collectFiles(tree, directory: directory, projectDirectory: directory, into: &files)
        }
        return files.values.sorted()
    }

    /// `node` with the file references under it named by their paths on disk; `directory` is the
    /// folder its `<group>` paths are relative to.
    private static func resolve(_ node: PIFValue, directory: String?, projectDirectory: String) -> PIFValue {
        guard var contents = node.objectValue else { return node }
        let location = Self.location(contents, directory: directory, projectDirectory: projectDirectory)
        if contents["type"]?.stringValue == "file", let location {
            let disk = FileSystem.onDisk(location)
            if !disk.isIdentical(to: location) {
                contents["path"] = .string(disk)
                contents["sourceTree"] = .string("<absolute>")
            }
        }
        if let children = contents["children"]?.arrayValue {
            contents["children"] = .array(children.map { resolve($0, directory: location, projectDirectory: projectDirectory) })
        }
        return .object(contents)
    }

    /// The paths of the file references under `node`, by GUID.
    static func collectFiles(_ node: PIFValue, directory: String?, projectDirectory: String, into files: inout [String: String]) {
        guard let contents = node.objectValue else { return }
        let location = Self.location(contents, directory: directory, projectDirectory: projectDirectory)
        if contents["type"]?.stringValue == "file", let location, let guid = contents["guid"]?.stringValue {
            files[guid] = location
        }
        for child in contents["children"]?.arrayValue ?? [] {
            collectFiles(child, directory: location, projectDirectory: projectDirectory, into: &files)
        }
    }

    /// Where a group tree node is: its `path` against the folder of its source tree; `nil` for a
    /// source tree that is a build setting.
    static func location(_ contents: [String: PIFValue], directory: String?, projectDirectory: String) -> String? {
        let path = contents["path"]?.stringValue ?? ""
        switch contents["sourceTree"]?.stringValue {
        case "<group>": return directory.map { path.isEmpty ? $0 : $0 + "/" + path }
        case "SOURCE_ROOT": return path.isEmpty ? projectDirectory : projectDirectory + "/" + path
        case "<absolute>": return path
        default: return nil
        }
    }
}
