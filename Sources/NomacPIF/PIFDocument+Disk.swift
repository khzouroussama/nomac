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

    /// The paths of the files in the target's Sources phases, as the project spells them; a file
    /// whose source tree is a build setting is left out.
    public func compileSources(targetGUID: String) -> [String] {
        var files: [String: String] = [:]
        for object in objects where object.type == "project" {
            guard let contents = object.contents.objectValue, let directory = contents["projectDirectory"]?.stringValue,
                  let tree = contents["groupTree"] else { continue }
            Self.collectFiles(tree, directory: directory, projectDirectory: directory, into: &files)
        }
        guard let target = objects.first(where: { $0.type == "target" && $0.contents.objectValue?["guid"]?.stringValue == targetGUID })?.contents.objectValue else { return [] }
        let phases = (target["buildPhases"]?.arrayValue ?? []).compactMap(\.objectValue).filter { $0["type"]?.stringValue == "com.apple.buildphase.sources" }
        return phases.flatMap { $0["buildFiles"]?.arrayValue ?? [] }.compactMap { $0.objectValue?["fileReference"]?.stringValue.flatMap { files[$0] } }
    }

    /// The targets `guids` depend on, directly or not, after them in the order found: what a scheme
    /// builds besides the targets it names, by explicit dependency or by linking a package's product.
    public func withDependencies(of guids: [String]) -> [String] {
        var targets: [String: [String: PIFValue]] = [:]
        for object in objects where object.type == "target" {
            if let contents = object.contents.objectValue, let guid = contents["guid"]?.stringValue { targets[guid] = contents }
        }
        var result = guids
        var index = 0
        while index < result.count {
            let target = targets[result[index]]
            let linked = (target?["buildPhases"]?.arrayValue ?? []).flatMap { $0.objectValue?["buildFiles"]?.arrayValue ?? [] }.compactMap { $0.objectValue?["targetReference"]?.stringValue }
            let listed = (target?["dependencies"]?.arrayValue ?? []).compactMap { $0.objectValue?["guid"]?.stringValue }
            for guid in listed + linked where targets[guid] != nil && !result.contains(guid) { result.append(guid) }
            index += 1
        }
        return result
    }

    /// The GUID of the target named `name`.
    public func targetGUID(named name: String) -> String? {
        objects.first { $0.type == "target" && $0.contents.objectValue?["name"]?.stringValue == name }?.contents.objectValue?["guid"]?.stringValue
    }

    /// The name of the target `guid`.
    public func targetName(guid: String) -> String? {
        objects.first { $0.type == "target" && $0.contents.objectValue?["guid"]?.stringValue == guid }?.contents.objectValue?["name"]?.stringValue
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
