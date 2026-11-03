import Foundation
import NomacCore
import NomacPIF
import NomacProject
import SPMBuildCore
import NomacTestSupport
import Testing
@testable import NomacPackages

/// A package target applying a build tool plugin of its package (`build_plugin_experiments.py`
/// buildCommand): the plugin is compiled and run, and its build command becomes the target's
/// custom task in the PIF, as Xcode 27.0's.
@Suite struct BuildToolPluginsTests {
    final class Lines: @unchecked Sendable {
        var text = ""
    }

    @Test func appliesAPackageTargetsPluginAsXcodeDoes() async throws {
        let directory = try TemporaryDirectory()
        let developer = try PackageFixtures.developerDirectory(at: directory.path + "/sdk")
        let files = [
            "Package.swift": """
            // swift-tools-version: 6.1
            import PackageDescription

            let package = Package(
                name: "Gen",
                products: [.library(name: "Lib", targets: ["Lib"])],
                targets: [.executableTarget(name: "GenTool"), .plugin(name: "GenPlugin", capability: .buildTool(), dependencies: ["GenTool"]),
                          .target(name: "Lib", plugins: ["GenPlugin"])]
            )

            """,
            "Sources/GenTool/main.swift": "print(1)\n",
            "Sources/Lib/Lib.swift": "public func value() -> Int { generated }\n",
            "Plugins/GenPlugin/plugin.swift": """
            import PackagePlugin

            @main
            struct GenPlugin: BuildToolPlugin {
                func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
                    let output = context.pluginWorkDirectoryURL.appending(path: "Generated.swift")
                    return [.buildCommand(displayName: "Generate \\(target.name)", executable: try context.tool(named: "GenTool").url,
                                          arguments: [output.path], outputFiles: [output])]
                }
            }

            """,
        ]
        for (path, text) in files {
            try directory.writeExactly(text, to: "Gen/" + path)
        }
        let folder = (directory.path as NSString).standardizingPath + "/Gen"
        let workspace = XcodeWorkspace.package(folder: folder, name: "Gen")
        let derived = directory.path + "/dd/Build"
        let lines = Lines()
        var packages = try SwiftPackages(workspace: workspace, sourcePackagesDirectory: directory.path + "/dd/SourcePackages", developerDirectory: developer)
        packages.buildToolPlugins = BuildToolPlugins(buildProducts: derived + "/Products", intermediates: derived + "/Intermediates.noindex", swiftCompiler: nil,
                                                     pluginLibraries: nil, builtToolsDirectory: "/${BUILD_DIR}/${CONFIGURATION}", pluginTarget: nil,
                                                     log: { lines.text += $0 })
        var generator = PIFGenerator(workspace: workspace, packages: try await packages.load())
        let document = try generator.generate()

        let work = derived + "/Intermediates.noindex/BuildToolPluginIntermediates/gen.output/Lib/GenPlugin"
        let target = try #require(document.objects.first { $0.type == "target" && $0.contents.objectValue?["name"]?.stringValue == "Lib" }?.contents.objectValue)
        let tasks = target["customTasks"]?.arrayValue ?? []
        #expect(tasks.count == 1)
        let task = try #require(tasks.first?.objectValue)
        #expect(task["executionDescription"] == .string("Generate Lib"))
        #expect(task["outputFilePaths"] == .array([.string(work + "/Generated.swift")]))
        #expect(task["inputFilePaths"] == .array([.string("/${BUILD_DIR}/${CONFIGURATION}/GenTool")]))
        #expect(task["environment"] == .array([]))
        let commandLine = task["commandLine"]?.arrayValue?.compactMap(\.stringValue) ?? []
        #expect(commandLine.suffix(2) == ["/${BUILD_DIR}/${CONFIGURATION}/GenTool", work + "/Generated.swift"])
        #expect(FileSystem.isFile(derived + "/Products/PluginExecutables/GenPlugin"))
        #expect(lines.text.hasPrefix("Compile plug-in “GenPlugin” in package “gen”\n[debug]: Compiling plugin to executable at "))
        #expect(lines.text.hasSuffix("\n\n\nApply build tool plug-in “GenPlugin” to target “Lib” in package “gen”\n\nProcess build tool plug-in results\n\n"))
    }

    /// How xcodebuild names a package among the failed commands of a plugin it could not apply
    /// (`build_plugin_experiments.py` prebuildCommand, Xcode 27.0).
    @Test func namesThePackageOfAFailedPluginAsXcodeDoes() throws {
        #expect(try BuildToolPlugins.blueprint(of: "/src/Gen")
                == "eyJibHVlcHJpbnRQcm92aWRlcl9wcm92aWRlckZpbGVQYXRoU3RyaW5nIjoiXC9zcmNcL0dlbiIsInR5cGUiOnsiYmx1ZXByaW50UHJvdmlkZXIiOnt9fX0=")
    }

    /// The words of the script xcodebuild writes for an Xcode project's plugin command
    /// (`build_plugin_experiments.py` project-quoting, Xcode 27.0).
    @Test func quotesScriptWordsAsXcodeDoes() {
        let plain = ["/usr/bin/sandbox-exec", "-p", "/dd/Build/First.swift", "a+b", "a,b", "a-b", "a.b", "a/b", "a=b", "a_b"]
        for word in plain { #expect(BuildToolPlugins.shellWord(word) == word) }
        let quoted = ["a b": #""a b""#, #"q"uote"#: #""q\"uote""#, "$HOME": #""$HOME""#, #"back\slash"#: #""back\\slash""#,
                      "/${BUILD_DIR}/${CONFIGURATION}/GenTool": #""/${BUILD_DIR}/${CONFIGURATION}/GenTool""#]
        for (word, written) in quoted { #expect(BuildToolPlugins.shellWord(word) == written) }
        for character in "!#$%&'()*:;<>?@[]^{|}~" { #expect(BuildToolPlugins.shellWord("a\(character)b") == "\"a\(character)b\"") }
    }

    /// An Xcode project as SwiftPM sends it to a plugin: the file its group references but not the
    /// product, and the target's product and sources (`build_plugin_experiments.py` project).
    @Test func representsAProjectAsXcodeDoes() throws {
        let directory = try TemporaryDirectory()
        try directory.writeExactly(Self.project, to: "app/P.xcodeproj/project.pbxproj")
        try directory.writeExactly("@main struct App { static func main() {} }\n", to: "app/App.swift")
        let folder = (directory.path as NSString).standardizingPath + "/app"
        let representation = try BuildToolPlugins.representation(of: try XcodeProject.load(path: folder + "/P.xcodeproj"))
        #expect(representation.displayName == "P")
        #expect(representation.directoryPath.pathString == folder)
        #expect(representation.filePaths.map(\.pathString) == [folder + "/App.swift"])
        let target = try #require(representation.targets.first)
        #expect(representation.targets.count == 1)
        #expect(target.displayName == "App")
        #expect(target.product == .init(name: "App", kind: .application))
        #expect(target.inputFiles == [.init(path: try .init(validating: folder + "/App.swift"), role: .source)])
    }

    static let project = """
        // !$*UTF8*$!
        {
        \tarchiveVersion = 1;
        \tobjectVersion = 77;
        \tobjects = {
        \t\tA1 = {isa = PBXProject; buildConfigurationList = A3; mainGroup = A2; projectDirPath = ""; projectRoot = ""; targets = (A10, ); };
        \t\tA2 = {isa = PBXGroup; children = (A20, A21, ); sourceTree = "<group>"; };
        \t\tA21 = {isa = PBXGroup; children = (A22, ); name = Products; sourceTree = "<group>"; };
        \t\tA3 = {isa = XCConfigurationList; buildConfigurations = (A4, ); defaultConfigurationName = Release; };
        \t\tA4 = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; }; name = Release; };
        \t\tA10 = {isa = PBXNativeTarget; buildConfigurationList = A11; buildPhases = (A12, ); name = App; productName = App; productReference = A22; productType = "com.apple.product-type.application"; };
        \t\tA11 = {isa = XCConfigurationList; buildConfigurations = (A13, ); defaultConfigurationName = Release; };
        \t\tA12 = {isa = PBXSourcesBuildPhase; files = (A30, ); };
        \t\tA13 = {isa = XCBuildConfiguration; buildSettings = {PRODUCT_NAME = App; }; name = Release; };
        \t\tA20 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = App.swift; sourceTree = "<group>"; };
        \t\tA22 = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = App.app; sourceTree = BUILT_PRODUCTS_DIR; };
        \t\tA30 = {isa = PBXBuildFile; fileRef = A20; };
        \t};
        \trootObject = A1;
        }
        """
}
