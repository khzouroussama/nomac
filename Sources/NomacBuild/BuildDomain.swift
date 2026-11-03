import Foundation
import NomacCore
import NomacEnvelope
import NomacProject
import XcodeProj

/// `nomac check`'s `build:` domain (ADR 0011): what a project needs from the machine that builds
/// it beyond what nomac provides, its run-script phases' needs among them (``ScriptRequirements``).
///
/// A build setting whose value names a Mach-O executable is a tool a script phase runs, and Linux
/// cannot run it: CocoaPods' xcconfig of a React Native app sets
/// `HERMES_CLI_PATH = $(PODS_ROOT)/../../node_modules/hermes-compiler/hermesc/osx-bin/hermesc`, and
/// the Release build's bundling phase fails with "Exec format error" (docs/state/react-native.md). The
/// project must name a build of the tool for the build machine instead. A Mach-O macro plugin with
/// a Swift package beside it is nomac's to build for the build machine (``MacroPluginPackages``).
/// A script phase can also run a Mach-O executable by its path: wikipedia's "Update Localizations"
/// runs `"$SRCROOT/scripts/localization"`, a universal macOS build committed in its repository (B-134).
public struct BuildDomain: FeatureDomain {
    public let name = "build"
    public var envelope: Envelope { Self.envelope }

    static let machOExecutable = "build:setting=mach-o-executable"
    static let scriptMachOExecutable = "build:script=mach-o-executable"
    static let machONodeModule = "build:node-module=mach-o-only"
    static let macroPluginPackage = "build:macro-plugin=swift-package"
    static let deploymentTargetBelowMinimum = "build:setting=deployment-target-below-minimum"

    /// Each platform's deployment target setting and the oldest version Xcode 27.0's SDK builds
    /// for (its `SDKSettings.json`, `SupportedTargets.<platform>.MinimumDeploymentTarget`).
    static let minimumDeploymentTargets = ["iphoneos": ("IPHONEOS_DEPLOYMENT_TARGET", "15.0"), "appletvos": ("TVOS_DEPLOYMENT_TARGET", "15.0"),
                                           "watchos": ("WATCHOS_DEPLOYMENT_TARGET", "9.0"), "macosx": ("MACOSX_DEPLOYMENT_TARGET", "12.0"),
                                           "xros": ("XROS_DEPLOYMENT_TARGET", "1.0")]

    static let envelope = Envelope(domain: "build", entries: [
        .unverified(machOExecutable, "the setting names a Mach-O executable, which the build runs (a script phase's tool, or the compiler's macro plugin) and a Linux build cannot: build with the setting overridden on the command line, `nomac build ... NAME=<the tool built for the build machine>`, as xcodebuild takes it; for a macro plugin, name the plugin built for the build machine in the flag where the project's files set it (the Linux build or package listed, which npm installs only on Linux; ADR 0151)"),
        .unverified(deploymentTargetBelowMinimum, "a target's deployment target is older than its SDK supports, and Xcode 27.0 fails the build: `error: The iOS deployment target 'IPHONEOS_DEPLOYMENT_TARGET' is set to 12.0, but the range of supported deployment target versions is 15.0 to 27.0.x.` (observed on a self-written static library, below 15.0 only; nomac fails alike). Raise it to the minimum listed; for CocoaPods' targets, in the Podfile's `post_install`: `installer.pods_project.targets.each { |t| t.build_configurations.each { |c| c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0' if c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'].to_f < 15.0 } }`, then `pod install`"),
        .unverified(scriptMachOExecutable, "a script phase runs a Mach-O executable by its path, which a Linux build cannot: put a build of the tool for the build machine at that path before building, or build on a Mac (B-134)"),
        .verified(macroPluginPackage, "macro_plugin_experiments.py:macro-prebuilt", "adr:0151"),
        .unverified(machONodeModule, "a native Node module built only for macOS, which a script phase's Node cannot load on Linux: install the project's Node packages on the build machine (npm installs only the optional packages of the machine it runs on: the Linux packages listed), or rebuild the module there (`npm rebuild`)"),
    ] + ScriptRequirements.entries, family: ScriptRequirements.interpreterEntry)

    public init() {}

    public func scan(_ container: String, options: CheckOptions) throws -> DomainScan {
        let workspace = try XcodeWorkspace.load(path: FileSystem.absolute(container))
        let base = (FileSystem.absolute(container) as NSString).deletingLastPathComponent
        var uses = Set<FeatureUse>()
        for project in workspace.allProjects {
            let directory = (project.path as NSString).deletingLastPathComponent
            let projectConfigurations = project.pbxproj.rootObject?.buildConfigurationList?.buildConfigurations ?? []
            for target in project.pbxproj.nativeTargets {
                for configuration in target.buildConfigurationList?.buildConfigurations ?? [] {
                    let levels = [configuration, projectConfigurations.first { $0.name == configuration.name }].compactMap { $0 }
                        .flatMap { Self.levels(of: $0, project: project, directory: directory) }
                    if let (setting, value, minimum, file) = Self.deploymentTargetBelowMinimum(levels: levels) {
                        uses.insert(FeatureUse(feature: Self.deploymentTargetBelowMinimum, file: file,
                                               object: "\(target.name) (\(configuration.name)): \(setting) = \(value), minimum \(minimum)"))
                    }
                    for phase in target.buildPhases.compactMap({ $0 as? PBXShellScriptBuildPhase }) {
                        for written in Self.scriptMachOExecutables(phase.shellScript ?? "", levels: levels, directory: directory) {
                            uses.insert(FeatureUse(feature: Self.scriptMachOExecutable, file: project.path + "/project.pbxproj",
                                                   object: "\(target.name): \(phase.name ?? "Run Script"): \(written)"))
                        }
                    }
                    for (setting, written, file, executable) in Self.machOExecutables(levels: levels, directory: directory) {
                        if written.hasPrefix("-load-plugin-executable "), let package = MacroPluginPackages.nearestPackage(of: executable) {
                            uses.insert(FeatureUse(feature: Self.macroPluginPackage, file: file,
                                                   object: "\(setting) = \(Self.relative(written, to: base)); package: \(Self.relative(package + "/Package.swift", to: base))"))
                            continue
                        }
                        let builds = Self.linuxBuilds(of: executable)
                        let linux = !builds.installed.isEmpty ? "; Linux build: " + builds.installed.map { Self.relative($0, to: base) }.joined(separator: ", ")
                            : builds.packages.isEmpty ? "" : "; Linux packages: " + builds.packages.joined(separator: ", ")
                        uses.insert(FeatureUse(feature: Self.machOExecutable, file: file, object: "\(setting) = \(Self.relative(written, to: base))" + linux))
                    }
                }
            }
        }
        let index = ScriptRequirements.scriptIndex([base, (base as NSString).deletingLastPathComponent + "/node_modules"])
        for project in workspace.allProjects {
            for (feature, file, object) in ScriptRequirements.scan(project: project, base: base, index: index) {
                uses.insert(FeatureUse(feature: feature, file: file, object: Self.relative(object, to: base)))
            }
        }
        for module in try Self.macOSOnlyNodeModules(near: base) {
            let linux = module.linuxPackages.isEmpty ? "" : "; Linux packages: " + module.linuxPackages.joined(separator: ", ")
            uses.insert(FeatureUse(feature: Self.machONodeModule, file: module.file, object: "package " + module.package + linux))
        }
        return DomainScan(uses: uses.sorted())
    }

    /// `text` with absolute paths under `base`'s parent folders written relative to `base`.
    static func relative(_ text: String, to base: String) -> String {
        var components = (base as NSString).pathComponents
        var prefix = ""
        while components.count > 1 {
            let folder = NSString.path(withComponents: components)
            if text.contains(folder + "/") { return text.replacingOccurrences(of: folder + "/", with: prefix.isEmpty ? "" : prefix) }
            components.removeLast()
            prefix += "../"
        }
        return text
    }

    /// The native Node modules (`.node` files) that are Mach-O, under the `node_modules` folders
    /// Node would search from `base` (it and each folder above), and whose package has no Linux
    /// build: no ELF `.node` beside it, and for npm's platform packages (`"os": ["darwin"]`), no
    /// installed package for Linux among the optional dependencies that name it (expo-default's
    /// `lightningcss-darwin-arm64`, whose JS bundling then fails on Linux). For those, the
    /// alternatives that the lockfile beside the `node_modules` folder lists for Linux with glibc.
    static func macOSOnlyNodeModules(near base: String) throws -> [(file: String, package: String, linuxPackages: [String])] {
        var folders: [String] = []
        var folder = base
        while true {
            if FileSystem.isDirectory(folder + "/node_modules") { folders.append(folder + "/node_modules") }
            let parent = (folder as NSString).deletingLastPathComponent
            if parent == folder || parent.isEmpty { break }
            folder = parent
        }
        var found: [(file: String, package: String, linuxPackages: [String])] = []
        for root in folders {
            let locked = Self.lockedPackages(beside: root)
            var manifests: [String: [String: Any]] = [:]
            var modules: [String] = []
            let enumerator = FileManager.default.enumerator(atPath: root)
            while let relative = enumerator?.nextObject() as? String {
                let path = root + "/" + relative
                if relative.hasSuffix("/package.json") || relative == "package.json",
                   let data = FileManager.default.contents(atPath: path),
                   let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    manifests[(path as NSString).deletingLastPathComponent] = manifest
                } else if relative.hasSuffix(".node") {
                    modules.append(path)
                }
            }
            func package(of file: String) -> String? {
                var folder = (file as NSString).deletingLastPathComponent
                while folder.count > root.count {
                    if manifests[folder] != nil { return folder }
                    folder = (folder as NSString).deletingLastPathComponent
                }
                return nil
            }
            let installed = Dictionary(manifests.compactMap { folder, manifest in (manifest["name"] as? String).map { ($0, manifest) } },
                                       uniquingKeysWith: { first, _ in first })
            var elfPackages = Set<String>()
            for module in modules where magic(module) == .elf {
                if let owner = package(of: module) { elfPackages.insert(owner) }
            }
            for module in modules where magic(module) == .machO {
                guard let owner = package(of: module), !elfPackages.contains(owner) else { continue }
                let manifest = manifests[owner] ?? [:]
                var linuxPackages: [String] = []
                if let systems = manifest["os"] as? [String], systems.contains("darwin"), let name = manifest["name"] as? String {
                    let alternatives = Set(manifests.values.compactMap { ($0["optionalDependencies"] as? [String: Any]).flatMap { $0[name] != nil ? $0.keys : nil } }.joined())
                    if alternatives.contains(where: { ((installed[$0]?["os"] as? [String]) ?? []).contains("linux") }) { continue }
                    linuxPackages = alternatives.filter { alternative in
                        guard let entry = locked[alternative], ((entry["os"] as? [String]) ?? []).contains("linux") else { return false }
                        return !((entry["libc"] as? [String]) ?? []).contains("musl")
                    }.sorted()
                }
                found.append((module, (manifest["name"] as? String) ?? (owner as NSString).lastPathComponent, linuxPackages))
            }
        }
        return found.sorted { $0.file < $1.file }
    }

    /// For an executable in an npm package, the builds of it for Linux (glibc) that the package's
    /// optional dependencies hold, as npm's platform packages do: those installed (an ELF executable
    /// of the same name at the package's root) and, when none is, the packages the lockfile lists
    /// (expo-modules-macros' `ExpoModulesMacros`, in `@expo/modules-macros-linux-arm64` and `-x64`).
    static func linuxBuilds(of executable: String) -> (installed: [String], packages: [String]) {
        var folder = (executable as NSString).deletingLastPathComponent
        var manifest: [String: Any]?
        while folder.contains("/node_modules/") {
            if let data = FileManager.default.contents(atPath: folder + "/package.json"),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                manifest = object
                break
            }
            folder = (folder as NSString).deletingLastPathComponent
        }
        guard let alternatives = (manifest?["optionalDependencies"] as? [String: Any])?.keys,
              let range = folder.range(of: "/node_modules/", options: .backwards) else { return ([], []) }
        let nodeModules = String(folder[..<range.lowerBound]) + "/node_modules"
        let locked = Self.lockedPackages(beside: nodeModules)
        let name = (executable as NSString).lastPathComponent
        var installed: [String] = [], packages: [String] = []
        for alternative in alternatives.sorted() {
            let candidate = nodeModules + "/" + alternative + "/" + name
            if FileManager.default.isExecutableFile(atPath: candidate), Self.magic(candidate) == .elf {
                installed.append(candidate)
            } else if let entry = locked[alternative], ((entry["os"] as? [String]) ?? []).contains("linux"),
                      !((entry["libc"] as? [String]) ?? []).contains("musl") {
                packages.append(alternative)
            }
        }
        return (installed, installed.isEmpty ? packages : [])
    }

    /// npm's `package-lock.json` beside a `node_modules` folder: its package entries by package
    /// name, installed or not (npm records every platform's optional packages).
    static func lockedPackages(beside nodeModules: String) -> [String: [String: Any]] {
        let path = (nodeModules as NSString).deletingLastPathComponent + "/package-lock.json"
        guard let data = FileManager.default.contents(atPath: path),
              let lock = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let packages = lock["packages"] as? [String: Any] else { return [:] }
        var entries: [String: [String: Any]] = [:]
        for (key, value) in packages {
            guard let entry = value as? [String: Any], let range = key.range(of: "node_modules/", options: .backwards) else { continue }
            entries[String(key[range.upperBound...])] = entry
        }
        return entries
    }

    enum Magic { case machO, elf, other }

    static func magic(_ path: String) -> Magic {
        guard let handle = FileHandle(forReadingAtPath: path) else { return .other }
        defer { try? handle.close() }
        let header = [UInt8](handle.readData(ofLength: 4))
        switch header {
        case [0xcf, 0xfa, 0xed, 0xfe], [0xce, 0xfa, 0xed, 0xfe], [0xca, 0xfe, 0xba, 0xbe]: return .machO
        case [0x7f, 0x45, 0x4c, 0x46]: return .elf
        default: return .other
        }
    }

    /// The deployment target setting of the platform `SDKROOT` names, with its value and the file
    /// that sets it, when the value is older than Xcode 27.0's SDK supports.
    static func deploymentTargetBelowMinimum(levels: [(file: String, assignments: [XCConfigFile.Assignment])]) -> (String, String, String, String)? {
        func lookup(_ name: String) -> (value: String, file: String)? {
            for level in levels {
                if let value = level.assignments.last(where: { $0.name == name && $0.conditions.isEmpty })?.value { return (value, level.file) }
            }
            return nil
        }
        func version(_ text: String) -> [Int]? {
            let parts = text.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")).split(separator: ".").map { Int($0) }
            return parts.isEmpty || parts.contains(nil) ? nil : parts.compactMap { $0 }
        }
        guard let sdk = lookup("SDKROOT")?.value, let (setting, minimum) = minimumDeploymentTargets[sdk],
              let (value, file) = lookup(setting), var found = version(value), var oldest = version(minimum) else { return nil }
        while found.count < oldest.count { found.append(0) }
        while oldest.count < found.count { oldest.append(0) }
        guard found.lexicographicallyPrecedes(oldest) else { return nil }
        return (setting, value, minimum, file)
    }

    /// A configuration's own settings, then its base xcconfig's (with what it includes), each
    /// with the file that holds it: the order in which they take precedence.
    static func levels(of configuration: XCBuildConfiguration, project: XcodeProject, directory: String) -> [(file: String, assignments: [XCConfigFile.Assignment])] {
        var levels: [(String, [XCConfigFile.Assignment])] = []
        levels.append((project.path + "/project.pbxproj", configuration.buildSettings.compactMap { key, value in
            guard case .string(let text) = value, let (name, conditions) = XCConfigFile.key(key) else { return nil }
            return XCConfigFile.Assignment(name: name, conditions: conditions, value: text)
        }))
        if let base = configuration.baseConfiguration, let path = try? base.fullPath(sourceRoot: directory) {
            levels.append((path, XCConfigFile.assignments(at: path)))
        }
        return levels
    }

    /// The settings whose unconditional value, expanded with the levels' own settings and the
    /// project's folder as `SRCROOT`, is an executable Mach-O file, with their value as written
    /// and the file that sets them.
    static func machOExecutables(levels: [(file: String, assignments: [XCConfigFile.Assignment])], directory: String) -> [(String, String, String, String)] {
        let lookup = Self.lookup(levels: levels, directory: directory)
        var found: [(String, String, String, String)] = []
        var seen = Set<String>()
        func machOExecutable(written: String) -> String? {
            guard let value = expand(written, lookup: lookup), value.hasPrefix("/") else { return nil }
            let path = (value as NSString).standardizingPath
            return Self.isMachOExecutable(path) && !Self.isProvidedBySystem(path) ? path : nil
        }
        for level in levels {
            for assignment in level.assignments where assignment.conditions.isEmpty && seen.insert(assignment.name).inserted {
                if let path = machOExecutable(written: assignment.value) {
                    found.append((assignment.name, assignment.value, level.file, path))
                    continue
                }
                // A Swift macro plugin the compiler runs: `-load-plugin-executable <path>#<module>`
                // (CocoaPods' OTHER_SWIFT_FLAGS of expo-default's pods), or the same flags each
                // passed through the driver with `-Xfrontend` (other Expo releases' pods).
                let words = Self.words(assignment.value)
                for (index, word) in words.enumerated() where word == "-load-plugin-executable" {
                    let argument = words.indices.contains(index + 1) && words[index + 1] == "-Xfrontend" ? index + 2 : index + 1
                    guard words.indices.contains(argument) else { continue }
                    let plugin = String(words[argument].split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0])
                    if let path = machOExecutable(written: plugin) { found.append((assignment.name, "-load-plugin-executable " + words[argument], level.file, path)) }
                }
            }
        }
        return found
    }

    /// The unconditional value of a setting in `levels`, with the project's folder as `SRCROOT`.
    static func lookup(levels: [(file: String, assignments: [XCConfigFile.Assignment])], directory: String) -> (String) -> String? {
        { name in
            if ["SRCROOT", "PROJECT_DIR", "SOURCE_ROOT"].contains(name) { return directory }
            for level in levels {
                if let value = level.assignments.last(where: { $0.name == name && $0.conditions.isEmpty })?.value { return value }
            }
            return nil
        }
    }

    /// The commands of a script phase's script, unquoted, that name an executable Mach-O file:
    /// the first word of a line and the word after `;`, `&&`, `||`, `|`, `exec`, `then`, `do` or
    /// `else`, expanded with the settings and, when relative, taken from the project's folder,
    /// where Xcode runs the script.
    static func scriptMachOExecutables(_ script: String, levels: [(file: String, assignments: [XCConfigFile.Assignment])], directory: String) -> [String] {
        let lookup = Self.lookup(levels: levels, directory: directory)
        let separators: Set<String> = [";", "&&", "||", "|", "exec", "then", "do", "else"]
        var found: [String] = []
        for line in script.split(whereSeparator: \.isNewline) {
            let words = Self.words(String(line))
            guard let first = words.first, !first.hasPrefix("#") else { continue }
            for (index, word) in words.enumerated() where index == 0 || separators.contains(words[index - 1]) {
                guard let value = expand(word, lookup: lookup), value.contains("/") else { continue }
                let path = ((value.hasPrefix("/") ? value : directory + "/" + value) as NSString).standardizingPath
                if Self.isMachOExecutable(path), !Self.isProvidedBySystem(path) { found.append(word) }
            }
        }
        return found
    }

    /// A setting's value split into words as build settings are: at unquoted white space, with
    /// quotes and backslashes removed.
    static func words(_ value: String) -> [String] {
        var words: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        var inWord = false
        for character in value {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
                inWord = true
            } else if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
                inWord = true
            } else if character.isWhitespace {
                if inWord { words.append(current) }
                current = ""
                inWord = false
            } else {
                current.append(character)
                inWord = true
            }
        }
        if inWord { words.append(current) }
        return words
    }

    /// `value` with every `$(NAME)`, `${NAME}` and `$NAME` replaced by its value, `$(inherited)`
    /// by nothing; nil when a name is unknown or has a modifier.
    static func expand(_ value: String, lookup: (String) -> String?, depth: Int = 0) -> String? {
        guard depth < 16 else { return nil }
        var text = Substring(value.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")))
        var result = ""
        while let dollar = text.firstIndex(of: "$") {
            result += text[..<dollar]
            var rest = text[text.index(after: dollar)...]
            let name: Substring
            if let open = rest.first, open == "(" || open == "{" {
                let close: Character = open == "(" ? ")" : "}"
                guard let end = rest.firstIndex(of: close) else { return nil }
                name = rest[rest.index(after: rest.startIndex)..<end]
                rest = rest[rest.index(after: end)...]
            } else {
                let end = rest.firstIndex { !($0.isLetter || $0.isNumber || $0 == "_") } ?? rest.endIndex
                name = rest[..<end]
                rest = rest[end...]
            }
            guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
            if name != "inherited" {
                guard let definition = lookup(String(name)), let expanded = expand(definition, lookup: lookup, depth: depth + 1) else { return nil }
                result += expanded
            }
            text = rest
        }
        return result + text
    }

    /// Whether `path` is in a folder of the operating system or of Xcode, whose tools are Mach-O
    /// files on a Mac (`/bin/sh` among them) and a project does not ship: a build off macOS runs
    /// the machine's own, or nomac's, and ``ScriptRequirements`` reports the macOS-only commands.
    static func isProvidedBySystem(_ path: String) -> Bool {
        ["/bin/", "/sbin/", "/usr/bin/", "/usr/sbin/", "/usr/libexec/", "/System/", "/Library/Apple/"].contains { path.hasPrefix($0) }
            || path.contains(".app/Contents/Developer/")
    }

    /// Whether `path` is an executable file that starts as a Mach-O file or a universal one does.
    static func isMachOExecutable(_ path: String) -> Bool {
        guard FileSystem.isFile(path), FileManager.default.isExecutableFile(atPath: path),
              let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        let header = [UInt8](handle.readData(ofLength: 8))
        guard header.count == 8 else { return false }
        switch Array(header.prefix(4)) {
        case [0xcf, 0xfa, 0xed, 0xfe], [0xce, 0xfa, 0xed, 0xfe], [0xfe, 0xed, 0xfa, 0xcf], [0xfe, 0xed, 0xfa, 0xce]:
            return true
        case [0xca, 0xfe, 0xba, 0xbe]:
            // A universal file's architecture count; a Java class file has its version there.
            let count = header[4...].reduce(0) { $0 << 8 | Int($1) }
            return count > 0 && count < 20
        default:
            return false
        }
    }
}
