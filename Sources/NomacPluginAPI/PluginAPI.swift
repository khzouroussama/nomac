import Foundation
import NomacCore

/// The `PackagePlugin` and `XcodeProjectPlugin` libraries the build tool plugins of Xcode projects
/// link off macOS (ADR 0105): SwiftPM's open-source `PackagePlugin` with the entry point of
/// `XcodeProjectPlugin` called (`PluginAPI/PackagePlugin/UPSTREAM.md`), and nomac's
/// `XcodeProjectPlugin`, built with the compiler that compiles the plugins.
public enum PluginAPI {
    /// The directory of the libraries' sources.
    public static func sourcesDirectory() throws -> String {
        guard let directory = Bundle.module.resourcePath.map({ $0 + "/PluginAPI" }), FileSystem.isDirectory(directory) else {
            throw NomacError("the plugin libraries' sources are not installed next to nomac (nomac_NomacPluginAPI resources)")
        }
        return directory
    }

    /// The folder holding `PluginAPI`, with both libraries and their modules built by
    /// `swiftCompiler`, under `cache`: built the first time for that compiler and those sources.
    public static func libraries(swiftCompiler: String, cache: String) throws -> String {
        let sources = try sourcesDirectory()
        let version = try Subprocess.run(swiftCompiler, ["--version"])
        var key = version.outputString + version.errorString
        for module in ["PackagePlugin", "XcodeProjectPlugin"] {
            for file in try FileSystem.sortedContents(of: sources + "/" + module) where file.hasSuffix(".swift") {
                key += file + "\n" + String(decoding: FileSystem.contents(atPath: sources + "/" + module + "/" + file) ?? Data(), as: UTF8.self)
            }
        }
        let root = cache + "/" + String(SHA256.hex(key).prefix(16))
        guard !FileSystem.isDirectory(root + "/PluginAPI") else { return root }
        let partial = root + ".partial-\(ProcessInfo.processInfo.processIdentifier)"
        try? FileManager.default.removeItem(atPath: partial)
        try build(swiftCompiler: swiftCompiler, sources: sources, into: partial + "/PluginAPI")
        do {
            try FileManager.default.moveItem(atPath: partial, toPath: root)
        } catch where FileSystem.isDirectory(root + "/PluginAPI") {
            try? FileManager.default.removeItem(atPath: partial)
        }
        return root
    }

    static func build(swiftCompiler: String, sources: String, into directory: String) throws {
        try FileSystem.createDirectory(directory)
        func compile(_ module: String, _ arguments: [String]) throws {
            let files = try FileSystem.sortedContents(of: sources + "/" + module).filter { $0.hasSuffix(".swift") }.map { sources + "/" + module + "/" + $0 }
            let result = try Subprocess.run(swiftCompiler, ["-emit-library", "-emit-module", "-module-name", module, "-parse-as-library",
                                                            "-package-description-version", "999.0", "-Xlinker", "-soname=lib\(module).so"]
                                                + arguments + files + ["-emit-module-path", directory + "/\(module).swiftmodule", "-o", directory + "/lib\(module).so"],
                                            currentDirectory: directory)
            guard result.exitStatus == 0 else {
                throw NomacError("could not compile the \(module) library for build tool plugins:\n" + result.errorString + result.outputString, path: swiftCompiler)
            }
        }
        try compile("PackagePlugin", [])
        try compile("XcodeProjectPlugin", ["-module-link-name", "XcodeProjectPlugin", "-I", directory, "-L", directory, "-lPackagePlugin",
                                           "-Xlinker", "-rpath", "-Xlinker", "$ORIGIN"])
    }
}
