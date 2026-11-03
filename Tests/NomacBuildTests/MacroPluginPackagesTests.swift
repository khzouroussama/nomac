import Foundation
import NomacCore
import NomacPackages
import NomacTestSupport
import Testing
@testable import NomacBuild

/// Mach-O macro plugins named in a target's flags, and the packages beside them
/// (`macro_plugin_experiments.py`'s macro-prebuilt layout, expo-modules-macros' too).
@Suite struct MacroPluginPackagesTests {
    private func executable(_ bytes: [UInt8], at path: String) throws {
        try FileSystem.write(Data(bytes), to: path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    }

    @Test func findsMachOPluginsInFlags() throws {
        let directory = try TemporaryDirectory()
        let machO: [UInt8] = [0xca, 0xfe, 0xba, 0xbe, 0x00, 0x00, 0x00, 0x01]
        try executable(machO, at: directory.path + "/Plugin/apple/GreetMacros")
        try executable([0x7f, 0x45, 0x4c, 0x46, 2, 1, 1, 0], at: directory.path + "/Linux/GreetMacros")
        let flags = ["-D", "COCOAPODS", "-load-plugin-executable", directory.path + "/Plugin/apple/GreetMacros#GreetMacros",
                     "-load-plugin-executable", directory.path + "/Linux/GreetMacros#GreetMacros",
                     "-load-plugin-executable", "Plugin/apple/../apple/GreetMacros#GreetMacros,Other", "-load-plugin-executable"]
        #expect(MacroPluginPackages.machOPlugins(flags: flags, directory: directory.path) == [
            .init(executable: directory.path + "/Plugin/apple/GreetMacros", modules: "GreetMacros"),
            .init(executable: directory.path + "/Plugin/apple/GreetMacros", modules: "GreetMacros,Other"),
        ])
    }

    @Test func findsMachOPluginsPassedToTheFrontend() throws {
        let directory = try TemporaryDirectory()
        try executable([0xca, 0xfe, 0xba, 0xbe, 0x00, 0x00, 0x00, 0x01], at: directory.path + "/Plugin/apple/GreetMacros-tool")
        let flags = ["-Xfrontend", "-load-plugin-executable", "-Xfrontend", directory.path + "/Plugin/apple/GreetMacros-tool#GreetMacros",
                     "-Xfrontend", "-load-plugin-executable", "-Xfrontend"]
        #expect(MacroPluginPackages.machOPlugins(flags: flags, directory: directory.path) == [
            .init(executable: directory.path + "/Plugin/apple/GreetMacros-tool", modules: "GreetMacros"),
        ])
    }

    @Test func loadsTheBuildThroughTheFrontend() {
        #expect(MacroPluginPackages.loadFlags("/scratch/Greet Macros-tool#GreetMacros") == [
            "-Xfrontend", "-load-plugin-executable", "-Xfrontend", "/scratch/Greet\\ Macros-tool#GreetMacros",
        ])
    }

    @Test func namesTheMacroTargetOfAnExecutable() {
        #expect(MacroPluginPackages.macroTarget(executable: "GreetMacros", targets: ["GreetMacros"]) == "GreetMacros")
        #expect(MacroPluginPackages.macroTarget(executable: "GreetMacros-tool", targets: ["GreetMacros"]) == "GreetMacros")
        #expect(MacroPluginPackages.macroTarget(executable: "GreetMacros-tool", targets: ["GreetMacros-tool"]) == "GreetMacros-tool")
        #expect(MacroPluginPackages.macroTarget(executable: "OtherMacros-tool", targets: ["GreetMacros"]) == nil)
    }

    @Test func findsTheNearestPackage() throws {
        let directory = try TemporaryDirectory()
        try directory.writeExactly("// swift-tools-version: 6.0\n", to: "Package.swift")
        try directory.writeExactly("// swift-tools-version: 6.0\n", to: "Plugin/Package.swift")
        #expect(MacroPluginPackages.nearestPackage(of: directory.path + "/Plugin/.build/release/GreetMacros-tool") == directory.path + "/Plugin")
        #expect(MacroPluginPackages.nearestPackage(of: directory.path + "/Other/GreetMacros") == directory.path)
    }

    @Test func quotesWordsAsBuildSettingsSplitThem() {
        let word = "/path with space/it's \"quoted\"\\#Module"
        #expect(BuildDomain.words(MacroPluginPackages.quoted(word)) == [word])
    }

    @Test func readsTheManifestsMacroTargets() async throws {
        let directory = try TemporaryDirectory()
        try directory.writeExactly("""
            // swift-tools-version: 6.0
            import CompilerPluginSupport
            import PackageDescription

            let package = Package(
                name: "Greet",
                targets: [.macro(name: "GreetMacros"), .target(name: "Greet", dependencies: ["GreetMacros"])]
            )

            """, to: "Package.swift")
        try directory.writeExactly("", to: "Sources/GreetMacros/Plugin.swift")
        try directory.writeExactly("", to: "Sources/Greet/Greet.swift")
        #expect(try await SwiftPackages.macroTargets(folder: directory.path) == ["GreetMacros"])
    }
}
