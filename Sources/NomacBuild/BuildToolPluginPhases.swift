import Foundation
import NomacCore
import NomacPackages
import NomacPIF

/// Adds the commands build tool plugins returned for targets of Xcode projects to those targets'
/// PIF, as xcodebuild does before the build (`build_plugin_experiments.py` project and
/// project-quoting, Xcode 27.0; docs/formats/build.md "Build tool plugins").
///
/// Each command becomes a shell-script phase named after it, before the target's other phases
/// and in the order the plugins returned them, always run, not sandboxed by Swift Build, with the
/// command's inputs and outputs. Its outputs join the target's sources phase and the project's
/// group tree as files at their absolute path. Xcode makes each phase a new object ID per build;
/// nomac's is the first 24 digits of the MD5 of the project, target and command, and the phase's
/// GUID is the MD5 of the object ID, as Xcode's.
public enum BuildToolPluginPhases {
    static let signatureSuffix = "_nomac-plugins"

    public static func adding(_ commands: [ProjectPluginCommands], to document: PIFDocument, fileTypes: FileTypeRegistry?) -> PIFDocument {
        var document = document
        var renamed: [String: String] = [:]
        for entry in commands where !entry.commands.isEmpty {
            let projectPath = (entry.projectPath as NSString).standardizingPath
            guard let projectIndex = document.objects.firstIndex(where: {
                      $0.type == "project" && $0.contents.objectValue?["path"]?.stringValue.map { ($0 as NSString).standardizingPath } == projectPath
                  }),
                  case .object(var project) = document.objects[projectIndex].contents else { continue }
            let targetSignatures = Set(project["targets"]?.arrayValue?.compactMap(\.stringValue) ?? [])
            guard let targetIndex = document.objects.firstIndex(where: {
                      $0.type == "target" && targetSignatures.contains($0.signature) && $0.contents.objectValue?["name"]?.stringValue == entry.targetName
                  }),
                  case .object(var target) = document.objects[targetIndex].contents else { continue }
            let outputs = entry.commands.flatMap(\.outputFiles)
            let phases = entry.commands.enumerated().map { index, command -> PIFValue in
                let objectID = String(PIFIdentifiers.md5("\(projectPath)\n\(entry.targetName)\n\(index)\n\(command.displayName)").prefix(24)).uppercased()
                return .object([
                    "alwaysOutOfDate": .string("true"), "alwaysRunForInstallHdrs": .string("true"), "buildFiles": .array([]),
                    "emitEnvironment": .string("false"), "guid": .string(PIFIdentifiers.md5(objectID)), "inputFileListPaths": .array([]),
                    "inputFilePaths": .array(command.inputFiles.map(PIFValue.string)), "name": .string(command.displayName),
                    "originalObjectID": .string(objectID), "outputFileListPaths": .array([]),
                    "outputFilePaths": .array(command.outputFiles.map(PIFValue.string)), "sandboxingOverride": .string("forceDisabled"),
                    "scriptContents": .string(command.script), "shellPath": .string("/bin/sh"), "type": .string("com.apple.buildphase.shell-script"),
                ])
            }
            var buildPhases = target["buildPhases"]?.arrayValue ?? []
            if let sources = buildPhases.firstIndex(where: { $0.objectValue?["type"]?.stringValue == "com.apple.buildphase.sources" }),
               case .object(var phase) = buildPhases[sources] {
                phase["buildFiles"] = .array((phase["buildFiles"]?.arrayValue ?? [])
                    + outputs.map { .object(["fileReference": .string($0), "guid": .string("PBXBuildFile-" + $0)]) })
                buildPhases[sources] = .object(phase)
            }
            target["buildPhases"] = .array(phases + buildPhases)
            if case .object(var group) = project["groupTree"] {
                group["children"] = .array((group["children"]?.arrayValue ?? []) + outputs.map { output in
                    .object(["fileType": .string(fileTypes?.fileType(atPath: output, isDirectory: false) ?? "file"), "guid": .string(output),
                             "path": .string(output), "sourceTree": .string("<absolute>"), "type": .string("file")])
                })
                project["groupTree"] = .object(group)
            }
            for (index, contents) in [(targetIndex, target), (projectIndex, project)] {
                let signature = document.objects[index].signature
                document.objects[index].contents = .object(contents)
                guard !signature.hasSuffix(signatureSuffix) else { continue }
                renamed[signature] = signature + signatureSuffix
                document.objects[index].signature = signature + signatureSuffix
            }
        }
        guard !renamed.isEmpty else { return document }
        for index in document.objects.indices where ["project", "workspace"].contains(document.objects[index].type) {
            guard case .object(var fields) = document.objects[index].contents else { continue }
            for key in ["targets", "projects"] {
                if let references = fields[key]?.arrayValue {
                    fields[key] = .array(references.map { reference in reference.stringValue.flatMap { renamed[$0] }.map(PIFValue.string) ?? reference })
                }
            }
            document.objects[index].contents = .object(fields)
        }
        return document
    }
}
