import Foundation
import NomacCore
import NomacPackages

extension LoaderScan {
    /// PackageDescription calls (`.binaryTarget(`, `.unsafeFlags(`) whose use is a feature.
    static let manifestCalls: Set<String> = [
        "library", "executable", "plugin", "package", "target", "executableTarget", "testTarget", "systemLibrary", "binaryTarget", "macro",
        "product", "byName", "when", "process", "copy", "embedInCode", "headerSearchPath", "define", "unsafeFlags", "enableUpcomingFeature",
        "enableExperimentalFeature", "interoperabilityMode", "swiftLanguageMode", "linkedLibrary", "linkedFramework", "treatAllWarnings",
        "treatWarning", "strictMemorySafety", "defaultIsolation", "buildTool", "command", "trait", "default", "iOS", "macOS", "tvOS",
        "watchOS", "visionOS", "macCatalyst", "driverKit", "custom", "brew", "apt", "yum", "upToNextMajor", "upToNextMinor", "exact",
        "allowNetworkConnections", "writeToPackageDirectory", "sourceCodeFormatting", "documentationGeneration",
    ]

    /// PackageDescription argument labels whose use is a feature.
    static let manifestLabels: Set<String> = [
        "defaultLocalization", "platforms", "pkgConfig", "providers", "traits", "swiftLanguageModes", "swiftLanguageVersions",
        "cLanguageStandard", "cxxLanguageStandard", "exclude", "sources", "resources", "publicHeadersPath", "packageAccess", "cSettings",
        "cxxSettings", "swiftSettings", "linkerSettings", "plugins", "capability", "condition", "checksum", "branch", "revision", "exact",
        "from", "enabledTraits", "localization",
    ]

    /// The workspace's `Package.resolved`, which pins its remote packages.
    func scanResolvedPackages(_ workspace: String) {
        let resolved = workspace + "/xcshareddata/swiftpm/Package.resolved"
        guard FileSystem.isFile(resolved) else {
            if !remotePackageURLs.isEmpty { use("package:resolved=missing", workspace, "xcshareddata/swiftpm/Package.resolved") }
            return
        }
        guard let data = FileSystem.contents(atPath: resolved),
              let pins = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            use("package:resolved=unreadable", resolved, "Package.resolved")
            return
        }
        use("package:resolved.version=\(pins["version"].map { "\($0)" } ?? "none")", resolved, "Package.resolved")
        let entries = (pins["pins"] as? [[String: Any]]) ?? ((pins["object"] as? [String: Any])?["pins"] as? [[String: Any]]) ?? []
        for pin in entries where (pin["state"] as? [String: Any])?["version"] as? String == nil {
            guard let location = (pin["location"] ?? pin["repositoryURL"]) as? String else { continue }
            var name = (location as NSString).lastPathComponent.lowercased()
            if name.hasSuffix(".git") { name.removeLast(4) }
            branchPinnedPackages.insert(name)
        }
    }

    /// Local packages, the local packages they depend on, and with `--source-packages` the
    /// checkouts of remote ones.
    func scanPackages() {
        var index = 0
        while index < packageDirectories.count {
            scanManifest(packageDirectories[index], remote: false)
            index += 1
        }
        guard !remotePackageURLs.isEmpty else { return }
        if let sourcePackages = options.sourcePackages {
            let checkouts = sourcePackages + "/checkouts"
            for name in (try? FileSystem.sortedContents(of: checkouts)) ?? [] where FileSystem.isFile(checkouts + "/" + name + "/Package.swift") {
                scanManifest(checkouts + "/" + name, remote: true)
            }
        } else if let project = projects.first {
            unchecked.append(UncheckedPart(what: "manifests of remote packages (no --source-packages; BACKLOG B-080)", file: project.file))
        }
    }

    private func scanManifest(_ directory: String, remote: Bool) {
        let manifest = directory + "/Package.swift"
        let kind = remote ? "remote" : rootPackageDirectories.contains(directory) ? "root" : "local-dependency"
        use("package:kind=\(kind)", manifest, (directory as NSString).lastPathComponent)
        if !remote, !Self.isASCII(directory) { use("names:package=non-ascii", manifest, (directory as NSString).lastPathComponent) }
        guard let data = FileSystem.contents(atPath: manifest) else {
            use("package:manifest=missing", directory, (directory as NSString).lastPathComponent)
            return
        }
        for name in (try? FileSystem.sortedContents(of: directory)) ?? [] where name.hasPrefix("Package@swift-") && name.hasSuffix(".swift") {
            use("package:manifest=version-specific", directory + "/" + name, name)
        }
        let source = String(decoding: data, as: UTF8.self)
        let lines = source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let toolsVersion = lines.first.flatMap { Self.toolsVersion(String($0)) } ?? "none"
        use("package:tools-version=\(toolsVersion)", manifest, "line 1")
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let object = "line \(index + 1)"
            if trimmed.hasPrefix("#if ") || trimmed.hasPrefix("#elseif ") {
                for condition in Self.conditions(in: String(trimmed.drop { $0 != " " })) { use("package:condition=\(condition)", manifest, object) }
            } else if trimmed.hasPrefix("import ") {
                use("package:import=\(trimmed.dropFirst("import ".count).trimmingCharacters(in: .whitespaces))", manifest, object)
            }
        }
        let code = Self.withoutCommentsAndStrings(source)
        // Only these packages' unsafe flags depend on answers no comparison has checked (B-010).
        if code.range(of: #"\.unsafeFlags\s*\("#, options: .regularExpression) != nil {
            if !remote {
                use("package:unsafe-flags=\(kind)", manifest, (directory as NSString).lastPathComponent)
            } else if branchPinnedPackages.contains((directory as NSString).lastPathComponent.lowercased()) {
                use("package:unsafe-flags=branch-or-revision", manifest, (directory as NSString).lastPathComponent)
            }
        }
        for (index, line) in code.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            let object = "line \(index + 1)"
            let text = String(line)
            for name in Self.matches(#"\.([A-Za-z_][A-Za-z0-9_]*)\s*\("#, in: text) where Self.manifestCalls.contains(name) {
                use("package:api=.\(name)", manifest, object)
            }
            for name in Self.matches(#"(?<![.A-Za-z0-9_])([A-Za-z_][A-Za-z0-9_]*)\s*:"#, in: text) where Self.manifestLabels.contains(name) {
                use("package:api=\(name):", manifest, object)
            }
            for kind in Self.matches(#"\.package\s*\(\s*(url|path|id|name)\s*:"#, in: text) { use("package:api=.package(\(kind):)", manifest, object) }
            for type in Self.matches(#"type\s*:\s*\.(static|dynamic)"#, in: text) { use("package:api=type: .\(type)", manifest, object) }
        }
        for path in Self.matches(#"\.package\s*\(\s*(?:name\s*:\s*"[^"]*"\s*,\s*)?path\s*:\s*"([^"]+)""#, in: source) {
            let dependency = (((path.hasPrefix("/") ? path : directory + "/" + path)) as NSString).standardizingPath
            if FileSystem.isFile(dependency + "/Package.swift") {
                addPackageDirectory(dependency)
            } else {
                use("package:dependency=path-missing", manifest, path)
            }
        }
        scanSharedSchemes(in: directory + "/.swiftpm/xcode/xcshareddata/xcschemes", containerDirectory: directory)
    }

    /// `5.9` from `// swift-tools-version:5.9.2`.
    static func toolsVersion(_ line: String) -> String? {
        guard let version = matches(#"^//\s*swift-tools-version\s*:\s*([0-9]+\.[0-9]+)"#, in: line).first else { return nil }
        return version
    }

    /// The conditions of an `#if` or `#elseif` line: host conditions with their argument
    /// (`os(iOS)`, `canImport(UIKit)`), other kinds by name (`swift`, `compiler`), custom flags as `flag`.
    static func conditions(in expression: String) -> [String] {
        var result: [String] = []
        let calls = matches(#"([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*([^()]*?)\s*\)"#, in: expression, groups: 2)
        for pair in stride(from: 0, to: calls.count - 1, by: 2) {
            let kind = calls[pair]
            result.append(HostConditions.hostKinds.contains(kind) ? "\(kind)(\(calls[pair + 1]))" : kind)
        }
        let withoutCalls = expression.replacingOccurrences(of: #"[A-Za-z_][A-Za-z0-9_]*\s*\([^()]*\)"#, with: "", options: .regularExpression)
        if matches(#"([A-Za-z_][A-Za-z0-9_]*)"#, in: withoutCalls).contains(where: { !["true", "false"].contains($0) }) {
            result.append("flag")
        }
        return result
    }

    /// The manifest with comments and string literals blanked out, line breaks kept, so API
    /// names are matched in code only.
    static func withoutCommentsAndStrings(_ source: String) -> String {
        var output: [Character] = []
        let characters = Array(source)
        var index = 0
        func at(_ offset: Int) -> Character? { index + offset < characters.count ? characters[index + offset] : nil }
        while index < characters.count {
            let character = characters[index]
            if character == "/", at(1) == "/" {
                while index < characters.count, characters[index] != "\n" { index += 1 }
            } else if character == "/", at(1) == "*" {
                index += 2
                while index < characters.count, !(characters[index] == "*" && at(1) == "/") {
                    if characters[index] == "\n" { output.append("\n") }
                    index += 1
                }
                index += 2
            } else if character == "\"" {
                let multiline = at(1) == "\"" && at(2) == "\""
                index += multiline ? 3 : 1
                while index < characters.count {
                    if characters[index] == "\\" {
                        index += 2
                        continue
                    }
                    if multiline ? (characters[index] == "\"" && at(1) == "\"" && at(2) == "\"") : characters[index] == "\"" {
                        index += multiline ? 3 : 1
                        break
                    }
                    if characters[index] == "\n" { output.append("\n") }
                    index += 1
                }
                output.append(contentsOf: "\"\"")
            } else {
                output.append(character)
                index += 1
            }
        }
        return String(output)
    }

    /// The first capture group of every match of `pattern`, or the first `groups` groups.
    static func matches(_ pattern: String, in text: String, groups: Int = 1) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range).flatMap { match in
            (1...groups).compactMap { group in Range(match.range(at: group), in: text).map { String(text[$0]) } }
        }
    }
}
