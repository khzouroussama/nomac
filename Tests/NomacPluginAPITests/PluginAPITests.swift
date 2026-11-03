import Foundation
import NomacCore
import NomacTestSupport
import Testing
@testable import NomacPluginAPI

/// nomac's `PackagePlugin` and `XcodeProjectPlugin`, which the plugins of Xcode projects link off
/// macOS (ADR 0105).
@Suite struct PluginAPITests {
    #if os(Linux)
    @Test func buildsBothLibrariesOnceForACompiler() throws {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let compiler = try #require(path.split(separator: ":").map { $0 + "/swiftc" }.first { FileManager.default.isExecutableFile(atPath: $0) })
        let cache = try TemporaryDirectory()
        let root = try PluginAPI.libraries(swiftCompiler: compiler, cache: cache.path)
        for file in ["libPackagePlugin.so", "PackagePlugin.swiftmodule", "libXcodeProjectPlugin.so", "XcodeProjectPlugin.swiftmodule"] {
            #expect(FileSystem.exists(root + "/PluginAPI/" + file), "\(file)")
        }
        let symbols = try Subprocess.run("/usr/bin/nm", ["-D", "--defined-only", root + "/PluginAPI/libXcodeProjectPlugin.so"])
        #expect(symbols.outputString.contains(" call_XcodeProjectPlugin_build_command_creation_entry_point\n"))
        let built = try FileManager.default.attributesOfItem(atPath: root + "/PluginAPI/libPackagePlugin.so")[.modificationDate] as? Date
        #expect(try PluginAPI.libraries(swiftCompiler: compiler, cache: cache.path) == root)
        #expect(try FileManager.default.attributesOfItem(atPath: root + "/PluginAPI/libPackagePlugin.so")[.modificationDate] as? Date == built)
    }
    #endif

    @Test func shipsTheVendoredAndNomacSources() throws {
        let sources = try PluginAPI.sourcesDirectory()
        #expect(FileSystem.isFile(sources + "/PackagePlugin/Plugin.swift"))
        #expect(FileSystem.isFile(sources + "/PackagePlugin/LICENSE.txt"))
        #expect(FileSystem.isFile(sources + "/XcodeProjectPlugin/XcodeProjectPlugin.swift"))
    }
}
