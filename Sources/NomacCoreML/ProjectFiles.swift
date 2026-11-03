import Foundation
import NomacCore
import NomacEnvelope
import NomacProject
import XcodeProj

/// The files of a workspace's targets with some extensions: those of their Sources and Resources
/// phases, and those inside their synchronized folders, where Xcode builds every member of a
/// type its rules compile.
public enum ProjectFiles {
    public static func files(of workspace: XcodeWorkspace, extensions: Set<String>, kind: String, options: CheckOptions,
                             unchecked: inout [UncheckedPart]) -> [String] {
        var found: [String] = []
        for project in workspace.allProjects {
            let containing = (project.path as NSString).deletingLastPathComponent
            let dirPath = project.project.projectDirPath
            let sourceRoot = dirPath.isEmpty ? containing : ((containing as NSString).appendingPathComponent(dirPath) as NSString).standardizingPath
            for target in project.pbxproj.nativeTargets {
                for phase in target.buildPhases where phase is PBXSourcesBuildPhase || phase is PBXResourcesBuildPhase {
                    for file in phase.files ?? [] {
                        guard let element = file.file, let path = try? element.fullPath(sourceRoot: sourceRoot),
                              extensions.contains((path as NSString).pathExtension) else { continue }
                        found.append((path as NSString).standardizingPath)
                    }
                }
                for group in target.fileSystemSynchronizedGroups ?? [] {
                    guard let folder = try? group.fullPath(sourceRoot: sourceRoot) else { continue }
                    if options.descriptionOnly {
                        unchecked.append(UncheckedPart(what: "\(kind) in a synchronized folder", file: folder))
                    } else {
                        found += files(inFolder: folder, extensions: extensions)
                    }
                }
            }
        }
        var seen: Set<String> = []
        return found.filter { seen.insert($0).inserted }
    }

    static func files(inFolder folder: String, extensions: Set<String>) -> [String] {
        guard let entries = try? FileSystem.sortedContents(of: folder) else { return [] }
        var found: [String] = []
        for entry in entries where !entry.hasPrefix(".") {
            let path = folder + "/" + entry
            if extensions.contains((entry as NSString).pathExtension) {
                found.append(path)
            } else if FileSystem.isDirectory(path) {
                found += files(inFolder: path, extensions: extensions)
            }
        }
        return found
    }
}
