import Foundation
import NomacCore

/// nomac's reimplementations of the macro plugins of Apple's frameworks, which Xcode keeps as
/// macOS libraries in each platform's `Developer/usr/lib/swift/host/plugins` and the compiler
/// loads through the platform's `swift-plugin-server` (docs/adr/0150-macro-plugins.md).
///
/// Each plugin module is a directory of Swift sources in this module's resources, written from
/// the expansions Xcode 27.0 gives (docs/formats/macros.md). `nomac toolchain install` compiles
/// them with the installed swift.org toolchain against its own swift-syntax (`lib/swift/host`),
/// the libraries that toolchain's `swift-plugin-server` loads them with.
public enum MacroPlugins {
    /// The swift-syntax libraries of a toolchain's `lib/swift/host` the plugins link.
    static let hostLibraries = ["SwiftBasicFormat", "SwiftDiagnostics", "SwiftIfConfig", "SwiftOperators", "SwiftParser", "SwiftSyntax",
                                "SwiftSyntaxBuilder", "SwiftSyntaxMacros"]

    /// The plugins Xcode keeps in the platform's plugin directory that swift.org's toolchain has
    /// too (open source) and that expand there as Xcode's do; the platform gets links to the
    /// toolchain's.
    static let toolchainPlugins = ["ObservationMacros", "SwiftMacros"]

    /// The compilation conditions of a plugin module: swift-foundation's `FoundationMacros` (vendored,
    /// `Plugins/FoundationMacros/UPSTREAM.md`) is built as Apple's platform copy is, which names
    /// `Foundation` where swift.org's names `FoundationEssentials`.
    static let compilationConditions = ["FoundationMacros": ["FOUNDATION_FRAMEWORK"]]

    /// The file name suffix of a shared library on this machine, the one the compiler looks for.
    static let libraryExtension: String = {
        #if os(macOS)
        ".dylib"
        #else
        ".so"
        #endif
    }()

    /// The directory of the plugin modules' sources.
    public static func sourcesDirectory() throws -> String {
        guard let directory = Bundle.module.resourcePath.map({ $0 + "/Plugins" }), FileSystem.isDirectory(directory) else {
            throw NomacError("the macro plugins' sources are not installed next to nomac (nomac_NomacMacros resources)")
        }
        return directory
    }

    /// The plugin modules nomac provides, by module name.
    public static func modules() throws -> [String] {
        let directory = try sourcesDirectory()
        return try FileSystem.sortedContents(of: directory).filter { FileSystem.isDirectory(directory + "/" + $0) }
    }

    /// Compiles every plugin module with the `swiftc` of the toolchain whose `usr` directory is
    /// `toolchain`, against that toolchain's swift-syntax, into `destination` as
    /// `lib<Module>.so` (`.dylib` on macOS). `runPaths` are the library's run paths.
    public static func build(toolchain: String, into destination: String, runPaths: [String]) throws -> [String] {
        let usr = FileSystem.absolute(toolchain)
        let swiftc = usr + "/bin/swiftc"
        let host = usr + "/lib/swift/host"
        guard FileManager.default.isExecutableFile(atPath: swiftc), FileSystem.isDirectory(host) else {
            throw NomacError("not the usr directory of a Swift toolchain with swift-syntax (no bin/swiftc or lib/swift/host)", path: usr)
        }
        try FileSystem.createDirectory(destination)
        let sources = try sourcesDirectory()
        var libraries: [String] = []
        for module in try modules() {
            let files = try FileSystem.sortedContents(of: sources + "/" + module).filter { $0.hasSuffix(".swift") }.map { sources + "/" + module + "/" + $0 }
            let library = destination + "/lib" + module + libraryExtension
            let arguments = ["-emit-library", "-module-name", module, "-parse-as-library", "-O", "-I", host, "-L", host]
                + (compilationConditions[module] ?? []).map { "-D" + $0 }
                + hostLibraries.map { "-l" + $0 }
                + runPaths.flatMap { ["-Xlinker", "-rpath", "-Xlinker", $0] }
                + files + ["-o", library]
            let result = try Subprocess.run(swiftc, arguments, currentDirectory: destination)
            guard result.exitStatus == 0 else {
                throw NomacError("could not compile the \(module) macro plugin:\n" + result.errorString + result.outputString, path: swiftc)
            }
            libraries.append(library)
        }
        return libraries
    }

    /// The result of an installation.
    public struct Installation: Sendable, Equatable {
        /// The platforms' plugin directories that got the plugins.
        public var pluginDirectories: [String]
        public var modules: [String]
    }

    /// The run paths of an installed plugin, from its platform's plugin directory to the
    /// `XcodeDefault` toolchain's libraries, whose `swift-plugin-server` loads it.
    static let installedRunPaths = ["lib/swift/host", "lib/swift/linux"].map { "$ORIGIN/../../../../../../../../Toolchains/XcodeDefault.xctoolchain/usr/" + $0 }

    /// The plugin modules this nomac provides that a platform of `developerDirectory` with nomac's
    /// plugins lacks: a developer directory installed by an older nomac, which installs again
    /// into a fresh `nomac sdk` subset (TipKitMacros and later modules are missing from those
    /// installed before them; wikipedia's TipKit then is "plugin for module 'TipKitMacros' not
    /// found").
    public static func missing(developerDirectory: String) throws -> [String] {
        let developer = FileSystem.absolute(developerDirectory)
        guard FileSystem.isDirectory(developer + "/Platforms") else { return [] }
        let installed = try FileSystem.sortedContents(of: developer + "/Platforms").map { developer + "/Platforms/" + $0 + "/Developer/usr" }
            .filter { FileSystem.exists($0 + "/bin/swift-plugin-server") }
        return try modules().filter { module in installed.contains { !FileSystem.isFile($0 + "/lib/swift/host/plugins/lib" + module + libraryExtension) } }
    }

    /// Builds the plugins with the toolchain whose `usr` directory is `toolchain` (the one
    /// `LinuxToolchain.install` copied) and installs them where Xcode keeps Apple's: in the
    /// plugin directory of every platform of `developerDirectory` that has one (the platforms a
    /// `nomac sdk` subset keeps). Each such platform also gets the toolchain's own open-source
    /// plugins and a `swift-plugin-server`, links into the `XcodeDefault` toolchain.
    public static func install(toolchain: String, developerDirectory: String) throws -> Installation {
        let developer = FileSystem.absolute(developerDirectory)
        let toolchainUsr = developer + "/Toolchains/XcodeDefault.xctoolchain/usr"
        guard FileManager.default.isExecutableFile(atPath: toolchainUsr + "/bin/swift-plugin-server") else {
            throw NomacError("the developer directory's XcodeDefault toolchain has no swift-plugin-server (run 'nomac toolchain install' first)", path: developer)
        }
        let platforms = try FileSystem.sortedContents(of: developer + "/Platforms").filter { $0.hasSuffix(".platform") }
        let platformUsrs = platforms.map { developer + "/Platforms/" + $0 + "/Developer/usr" }.filter { FileSystem.isDirectory($0 + "/lib/swift/host/plugins") }
        guard !platformUsrs.isEmpty else {
            throw NomacError("no platform of the developer directory has a plugin directory (Developer/usr/lib/swift/host/plugins)", path: developer)
        }
        let toolchainPluginFiles = toolchainPlugins.map { "lib" + $0 + libraryExtension }.filter { FileSystem.isFile(toolchainUsr + "/lib/swift/host/plugins/" + $0) }
        let names = try modules().map { "lib" + $0 + libraryExtension } + toolchainPluginFiles
        for usr in platformUsrs {
            for path in names.map({ usr + "/lib/swift/host/plugins/" + $0 }) + [usr + "/bin/swift-plugin-server"] where FileSystem.exists(path) {
                throw NomacError("the platform already has this macro plugin or plugin server", path: path)
            }
        }
        let staging = NSTemporaryDirectory() + "/nomac-macro-plugins-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: staging) }
        let built = try build(toolchain: toolchain, into: staging, runPaths: installedRunPaths)
        let manager = FileManager.default
        do {
            for usr in platformUsrs {
                let directory = usr + "/lib/swift/host/plugins"
                for library in built {
                    try manager.copyItem(atPath: library, toPath: directory + "/" + (library as NSString).lastPathComponent)
                }
                for name in toolchainPluginFiles {
                    try manager.createSymbolicLink(atPath: directory + "/" + name, withDestinationPath: "../../../../../../../../Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins/" + name)
                }
                try FileSystem.createDirectory(usr + "/bin")
                try manager.createSymbolicLink(atPath: usr + "/bin/swift-plugin-server", withDestinationPath: "../../../../../Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-plugin-server")
            }
        } catch {
            throw NomacError("could not install the macro plugins: \(error.localizedDescription)", path: developer)
        }
        return Installation(pluginDirectories: platformUsrs.map { $0 + "/lib/swift/host/plugins" }, modules: try modules())
    }
}
