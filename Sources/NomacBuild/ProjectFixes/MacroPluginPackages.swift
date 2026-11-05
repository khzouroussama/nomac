import Foundation
import NomacCore
import NomacPackages

/// Swift macro plugins a project names with `-load-plugin-executable` as Mach-O executables, which
/// a build off macOS cannot run, built for the build machine from the Swift package that ships
/// beside them (ADR 0151). The rule behind ``ProjectFixes/macroPluginFromPackage``.
///
/// Xcode 27.0's compiler uses the first `-load-plugin-executable` of a module
/// (`.github/scripts/macro_plugin_experiments.py order`), so the build's own goes before the
/// project's flags, through `-Xfrontend`: the driver passes `-Xfrontend` arguments to the
/// frontend before the `-load-plugin-executable` it forwards itself (`swiftc -###`, swift.org
/// 6.4.0), so a plain flag would come after a project's `-Xfrontend` one.
public enum MacroPluginPackages {
    public struct Plugin: Hashable, Sendable, Comparable {
        /// The executable as the flag names it, absolute.
        public var executable: String
        /// The module names after `#`.
        public var modules: String

        public static func < (a: Plugin, b: Plugin) -> Bool { (a.executable, a.modules) < (b.executable, b.modules) }
    }

    /// The plugins of a flag list (`OTHER_SWIFT_FLAGS` evaluated) whose executable is a Mach-O
    /// file; a relative path is the compiler's, from `directory`. The flag and its value may each
    /// follow a `-Xfrontend`, as the driver passes them on.
    public static func machOPlugins(flags: [String], directory: String) -> [Plugin] {
        var plugins: [Plugin] = []
        for (index, flag) in flags.enumerated() where flag == "-load-plugin-executable" {
            let argument = flags.indices.contains(index + 1) && flags[index + 1] == "-Xfrontend" ? index + 2 : index + 1
            guard flags.indices.contains(argument) else { continue }
            let value = flags[argument]
            guard let separator = value.lastIndex(of: "#") else { continue }
            let path = String(value[..<separator])
            let absolute = ((path.hasPrefix("/") ? path : directory + "/" + path) as NSString).standardizingPath
            if BuildDomain.isMachOExecutable(absolute) {
                plugins.append(Plugin(executable: absolute, modules: String(value[value.index(after: separator)...])))
            }
        }
        return plugins
    }

    /// The folder of the nearest `Package.swift` at or above the executable's folder: the package
    /// that would build it, when its manifest declares a macro target named as the executable
    /// (expo-modules-macros' `apple/ExpoModulesMacros` beside `apple/Package.swift`; SwiftPM's own
    /// products in the package's `.build`).
    public static func nearestPackage(of executable: String) -> String? {
        var folder = (executable as NSString).deletingLastPathComponent
        while folder.count > 1 {
            if FileSystem.isFile(folder + "/Package.swift") { return folder }
            folder = (folder as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// Builds each plugin's package for the build machine in `scratch`, and returns the flags that
    /// load the builds, to go before the project's, with the targets built. A plugin without a
    /// package that declares its macro target is left to the compiler, and reported in `warnings`.
    public static func build(_ plugins: [Plugin], scratch: String, log: (String) -> Void) async throws -> (flags: String, targets: [String], warnings: [String]) {
        var flags: [String] = []
        var targets: [String] = []
        var warnings: [String] = []
        for plugin in Set(plugins).sorted() {
            let name = (plugin.executable as NSString).lastPathComponent
            guard let package = nearestPackage(of: plugin.executable),
                  let target = macroTarget(executable: name, targets: try await SwiftPackages.macroTargets(folder: package)) else {
                warnings.append("the macro plugin \(plugin.executable) is a Mach-O executable, and no Swift package beside it declares the macro target \(name) to build it for this machine: see `nomac check`")
                continue
            }
            log("note: project fix \(ProjectFixes.macroPluginFromPackage.id): building the macro plugin \(target) for this machine from \(package)\n")
            targets.append(target)
            let built = try buildProduct(target, package: package, scratch: scratch + "/" + target + "-" + MD5.hex(package))
            flags += loadFlags(built + "#" + plugin.modules)
        }
        return (flags.joined(separator: " "), targets, warnings)
    }

    /// The macro target an executable is built from: the one of its name, or of its name without
    /// `-tool`, the name SwiftPM's native build system gives a macro target's executable (a
    /// package that ships that build under SwiftPM's name, as `@expo/expo-modules-macros-plugin`'s
    /// `apple/ExpoModulesMacros-tool`).
    static func macroTarget(executable name: String, targets: [String]) -> String? {
        if targets.contains(name) { return name }
        guard name.hasSuffix("-tool") else { return nil }
        let target = String(name.dropLast("-tool".count))
        return targets.contains(target) ? target : nil
    }

    /// The flags that load `plugin` (`<executable>#<modules>`) ahead of any `-load-plugin-executable`
    /// a project passes, plain or through `-Xfrontend`.
    static func loadFlags(_ plugin: String) -> [String] {
        ["-Xfrontend", "-load-plugin-executable", "-Xfrontend", quoted(plugin)]
    }

    /// `word` as one word of a build setting's value (``BuildDomain/words(_:)``).
    static func quoted(_ word: String) -> String {
        word.reduce(into: "") { text, character in
            if character.isWhitespace || "\"'\\".contains(character) { text.append("\\") }
            text.append(character)
        }
    }

    /// SwiftPM's native build system names a macro target's executable `<target>-tool`; its
    /// default one builds no macro target that no product names, as expo-modules-macros' is
    /// ("Could not find target named '<target>-product'"), on the Mac and on Linux
    /// (`macro_plugin_experiments.py generate`). The package's `Package.resolved` pins its
    /// dependencies, swift-syntax among them, as for the binary it ships.
    static func buildProduct(_ name: String, package: String, scratch: String) throws -> String {
        let swift = SwiftPackages.swiftCommand()
        let arguments = Array(swift.dropFirst()) + ["build", "--package-path", package, "--scratch-path", scratch, "--build-system", "native"]
        var environment = ProcessInfo.processInfo.environment
        for name in ["SDKROOT", "TOOLCHAINS", "DEVELOPER_DIR"] { environment[name] = nil }
        let result = try Subprocess.run(swift[0], arguments + ["--product", name], environment: environment)
        guard result.exitStatus == 0 else {
            let output = (result.outputString + result.errorString).split(separator: "\n").suffix(20).joined(separator: "\n")
            throw NomacError("could not build the macro plugin \(name) from \(package) (swift build, status \(result.exitStatus)):\n\(output)")
        }
        let directory = try Subprocess.run(swift[0], arguments + ["--show-bin-path"], environment: environment).outputString
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return directory + "/" + name + "-tool"
    }
}
