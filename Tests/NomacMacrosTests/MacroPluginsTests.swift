import Foundation
import NomacCore
@testable import NomacMacros
import NomacTestSupport
import Testing

@Suite(.serialized) struct MacroPluginsTests {
    /// A developer directory as `nomac toolchain install` leaves it: the subset's iPhoneOS platform
    /// with its plugin directory, and a toolchain with a plugin server and Observation's plugin.
    private func makeDeveloperDirectory(at root: String) throws -> String {
        let developer = try SyntheticDeveloperDirectory.create(at: root)
        let usr = developer + "/Toolchains/XcodeDefault.xctoolchain/usr"
        try FileSystem.write(Data("#!/bin/sh\n".utf8), to: usr + "/bin/swift-plugin-server")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: usr + "/bin/swift-plugin-server")
        try FileSystem.write(Data("observation".utf8), to: usr + "/lib/swift/host/plugins/libObservationMacros" + MacroPlugins.libraryExtension)
        try FileSystem.write(Data("swift.org's foundation".utf8), to: usr + "/lib/swift/host/plugins/libFoundationMacros" + MacroPlugins.libraryExtension)
        try FileSystem.createDirectory(developer + "/Platforms/iPhoneOS.platform/Developer/usr/lib/swift/host/plugins")
        return developer
    }

    @Test func installsThePluginsWhereXcodeKeepsApples() throws {
        let tmp = try TemporaryDirectory()
        let developer = try makeDeveloperDirectory(at: tmp.path)
        let platform = developer + "/Platforms/iPhoneOS.platform/Developer/usr"

        let installation = try MacroPlugins.install(toolchain: PluginServer.hostToolchain(), developerDirectory: developer)

        #expect(installation == MacroPlugins.Installation(pluginDirectories: [platform + "/lib/swift/host/plugins"], modules: try MacroPlugins.modules()))
        for module in try MacroPlugins.modules() {
            #expect(FileSystem.isFile(platform + "/lib/swift/host/plugins/lib" + module + MacroPlugins.libraryExtension))
        }
        // The toolchain's open-source plugins and its plugin server, at the platform's paths.
        let observation = "libObservationMacros" + MacroPlugins.libraryExtension
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: platform + "/lib/swift/host/plugins/" + observation)
            == "../../../../../../../../Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins/" + observation)
        #expect(FileManager.default.contents(atPath: platform + "/lib/swift/host/plugins/" + observation) == Data("observation".utf8))
        // nomac builds Foundation's macros itself, as Apple's platform copy is built.
        #expect(try FileManager.default.attributesOfItem(atPath: platform + "/lib/swift/host/plugins/libFoundationMacros" + MacroPlugins.libraryExtension)[.type] as? FileAttributeType == .typeRegular)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: platform + "/bin/swift-plugin-server")
            == "../../../../../Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-plugin-server")
        #expect(FileManager.default.isExecutableFile(atPath: platform + "/bin/swift-plugin-server"))
    }

    @Test func refusesAPlatformThatAlreadyHasThePlugins() throws {
        let tmp = try TemporaryDirectory()
        let developer = try makeDeveloperDirectory(at: tmp.path)
        let plugins = developer + "/Platforms/iPhoneOS.platform/Developer/usr/lib/swift/host/plugins"
        try FileSystem.write(Data("Apple's".utf8), to: plugins + "/libPreviewsMacros" + MacroPlugins.libraryExtension)

        #expect(throws: NomacError.self) { try MacroPlugins.install(toolchain: PluginServer.hostToolchain(), developerDirectory: developer) }
        #expect(FileManager.default.contents(atPath: plugins + "/libPreviewsMacros" + MacroPlugins.libraryExtension) == Data("Apple's".utf8))
    }

    @Test func needsTheInstalledToolchainsPluginServer() throws {
        let tmp = try TemporaryDirectory()
        let developer = try SyntheticDeveloperDirectory.create(at: tmp.path)
        #expect(throws: NomacError.self) { try MacroPlugins.install(toolchain: PluginServer.hostToolchain(), developerDirectory: developer) }
    }

    /// A developer directory an older nomac installed (wikipedia's TipKit on Linux: "plugin for
    /// module 'TipKitMacros' not found") lacks the modules added since; one without nomac's
    /// plugins lacks none of them.
    @Test func namesTheModulesAnOlderInstallationLacks() throws {
        let tmp = try TemporaryDirectory()
        let usr = tmp.path + "/Platforms/iPhoneOS.platform/Developer/usr"
        try FileSystem.createDirectory(usr + "/lib/swift/host/plugins")
        #expect(try MacroPlugins.missing(developerDirectory: tmp.path) == [])
        try tmp.writeExactly("", to: "Platforms/iPhoneOS.platform/Developer/usr/bin/swift-plugin-server")
        let modules = try MacroPlugins.modules()
        for module in modules where module != "TipKitMacros" {
            try tmp.writeExactly("", to: "Platforms/iPhoneOS.platform/Developer/usr/lib/swift/host/plugins/lib\(module)\(MacroPlugins.libraryExtension)")
        }
        #expect(try MacroPlugins.missing(developerDirectory: tmp.path) == ["TipKitMacros"])
    }
}
