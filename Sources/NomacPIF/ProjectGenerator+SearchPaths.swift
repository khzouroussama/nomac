import Foundation
import NomacCore
import XcodeProj

/// The search paths Xcode adds for the libraries and frameworks of synchronized folders
/// (docs/formats/pif.md, "Synchronized folders").
extension ProjectGenerator {
    /// `FRAMEWORK_SEARCH_PATHS` and `LIBRARY_SEARCH_PATHS` for a target with a Frameworks phase:
    /// the folders of its synchronized members that join Frameworks and are frameworks (by type
    /// or extension) or static or dynamic libraries, `$(PROJECT_DIR)` followed by what follows
    /// the project's directory in the folder's path, decomposed (loader-experiments `unicode-nfc`:
    /// `$(PROJECT_DIR)/He\u{308}aders` for a folder written `Hëaders`), spaces escaped. A folder
    /// the target lists counts all of them, the members its exception sets remove included;
    /// another folder only those its exception sets name for the target; a folder whose path
    /// does not start with the project's directory adds none (`pif-experiments` round 9,
    /// libraries-*: `../zz-elsewhere` adds none, `../libraries-outside-Libs` next to the
    /// project's folder `libraries-outside` adds `$(PROJECT_DIR)-Libs`). Xcode lists the paths of
    /// one synchronized folder in an order that changes from run to run; nomac lists them in
    /// walk order (BACKLOG B-031).
    func synchronizedSearchPaths(of target: PBXTarget) -> [(setting: String, paths: [String])] {
        guard target.buildPhases.contains(where: { $0 is PBXFrameworksBuildPhase }), let registry = fileTypes else { return [] }
        let listed = target.fileSystemSynchronizedGroups ?? []
        var frameworks: [String] = [], libraries: [String] = []
        for root in synchronizedRoots {
            let isListed = listed.contains { $0 === root.group }
            let sets = (root.group.exceptions ?? []).compactMap { $0 as? PBXFileSystemSynchronizedBuildFileExceptionSet }.filter { $0.target === target }
            let named = Set(sets.flatMap { $0.membershipExceptions ?? [] })
            for member in root.folder.members where memberPhase(member) == .frameworks && (isListed || named.contains(member.key)) {
                let types = [member.fileType, registry.type(forExtension: (member.relativePath as NSString).pathExtension)].compactMap { $0 }
                let directory = ((root.folder.directory as NSString).appendingPathComponent(member.relativePath) as NSString).deletingLastPathComponent.decomposed
                let projectDirectory = project.projectDirectory.decomposed
                guard directory.hasPrefix(projectDirectory) else { continue }
                let path = "$(PROJECT_DIR)" + Self.escapedSearchPath(String(directory.dropFirst(projectDirectory.count)))
                if types.contains("wrapper.framework") {
                    if !frameworks.contains(path) { frameworks.append(path) }
                } else if types.contains(where: Self.libraryFileTypes.contains), !libraries.contains(path) {
                    libraries.append(path)
                }
            }
        }
        return [("FRAMEWORK_SEARCH_PATHS", frameworks), ("LIBRARY_SEARCH_PATHS", libraries)].filter { !$0.paths.isEmpty }
    }

    /// The types whose members add a library search path: an archive, a dynamic library or a
    /// text-based one (`libraries-*`: not an object file, `c.o`, nor an `.xcframework`).
    static let libraryFileTypes: Set<String> = ["archive.ar", "compiled.mach-o.dylib", "sourcecode.text-based-dylib-definition"]

    /// A search-path setting with `paths` added: `$(inherited)` and the paths when the
    /// configuration has no value, else its value and the paths it lacks (`libraries-existing-
    /// setting`: `/opt/lib` gives `/opt/lib $(PROJECT_DIR)/Src`; `libraries-setting-names-folder`:
    /// a value naming the folder is kept as it is), only the paths when the value is empty
    /// (loader-experiments `synchronized-search-paths`: Empty).
    static func addingSearchPaths(_ paths: [String], to value: String?) -> String {
        guard let value else { return (["$(inherited)"] + paths).joined(separator: " ") }
        let words = value.split(separator: " ").map(String.init)
        return ((value.isEmpty ? [] : [value]) + paths.filter { !words.contains($0) }).joined(separator: " ")
    }

    /// A folder's path in a search path: spaces, `'` and `"` escaped with a backslash
    /// (loader-experiments `synchronized-search-paths`: `R&D\ (it\'s)\ Ünï/a\ \"b\"`).
    static func escapedSearchPath(_ path: String) -> String {
        var escaped = ""
        for character in path {
            if character == " " || character == "'" || character == "\"" { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped
    }
}
