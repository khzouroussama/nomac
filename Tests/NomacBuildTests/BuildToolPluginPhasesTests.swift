import Foundation
import NomacPackages
@testable import NomacPIF
import Testing
@testable import NomacBuild

/// An Xcode project target's plugin commands in its PIF, as xcodebuild adds them
/// (`build_plugin_experiments.py` project and project-quoting, Xcode 27.0).
@Suite struct BuildToolPluginPhasesTests {
    @Test func addsEachCommandAsAPhaseBeforeTheOthers() throws {
        let document = PIFDocument(objects: [
            .init(type: "workspace", signature: "W", contents: .object(["projects": .array([.string("P")])])),
            .init(type: "project", signature: "P", contents: .object([
                "path": .string("/src/P.xcodeproj"), "targets": .array([.string("T")]),
                "groupTree": .object(["children": .array([.object(["guid": .string("app"), "path": .string("App.swift")])])]),
            ])),
            .init(type: "target", signature: "T", contents: .object([
                "name": .string("App"),
                "buildPhases": .array([.object(["type": .string("com.apple.buildphase.sources"),
                                                "buildFiles": .array([.object(["fileReference": .string("app"), "guid": .string("b")])])])]),
            ])),
        ])
        let work = "/dd/Build/Intermediates.noindex/BuildToolPluginIntermediates/P.output/App/GenPlugin"
        let commands = [ProjectPluginCommands(projectPath: "/src/P.xcodeproj", targetName: "App", commands: [
            .init(displayName: "Generate first", script: "first\n", inputFiles: ["/src/App.swift"], outputFiles: [work + "/First.swift", work + "/Extra.swift"]),
            .init(displayName: "Generate second", script: "second\n", inputFiles: [], outputFiles: [work + "/Second.swift"]),
        ])]
        let result = BuildToolPluginPhases.adding(commands, to: document, fileTypes: nil)

        let target = try #require(result.objects.first { $0.type == "target" })
        #expect(target.signature == "T_nomac-plugins")
        let phases = target.contents.objectValue?["buildPhases"]?.arrayValue ?? []
        #expect(phases.compactMap { $0.objectValue?["name"]?.stringValue } == ["Generate first", "Generate second"])
        let first = try #require(phases.first?.objectValue)
        let objectID = try #require(first["originalObjectID"]?.stringValue)
        #expect(objectID.count == 24 && objectID == objectID.uppercased())
        #expect(first["guid"] == .string(PIFIdentifiers.md5(objectID)))
        #expect(first["inputFilePaths"] == .array([.string("/src/App.swift")]))
        #expect(first["outputFilePaths"] == .array([.string(work + "/First.swift"), .string(work + "/Extra.swift")]))
        #expect(first["scriptContents"] == .string("first\n"))
        #expect(first["sandboxingOverride"] == .string("forceDisabled"))
        #expect(first["alwaysOutOfDate"] == .string("true"))
        let sources = try #require(phases.last?.objectValue?["buildFiles"]?.arrayValue)
        let outputs = [work + "/First.swift", work + "/Extra.swift", work + "/Second.swift"]
        let added: [PIFValue] = outputs.map { output in PIFValue.object(["fileReference": .string(output), "guid": .string("PBXBuildFile-" + output)]) }
        #expect(Array(sources.dropFirst()) == added)

        let project = try #require(result.objects.first { $0.type == "project" })
        #expect(project.signature == "P_nomac-plugins")
        #expect(project.contents.objectValue?["targets"] == .array([.string("T_nomac-plugins")]))
        let children = project.contents.objectValue?["groupTree"]?.objectValue?["children"]?.arrayValue ?? []
        #expect(children.last == .object(["fileType": .string("file"), "guid": .string(work + "/Second.swift"), "path": .string(work + "/Second.swift"),
                                          "sourceTree": .string("<absolute>"), "type": .string("file")]))
        #expect(result.objects.first { $0.type == "workspace" }?.contents.objectValue?["projects"] == .array([.string("P_nomac-plugins")]))
    }
}
