import Foundation
import NomacCore
import NomacEnvelope
import NomacProject
import XcodeProj

/// What a project's run-script phases, and the shell scripts they call, need from macOS beyond what
/// nomac provides (ADR 0183; `.github/scripts/script_phase_survey.py` reads the same scripts the
/// same way): macOS-only commands without a stand-in, BSD `sed -i ''`, tests of the machine's
/// architecture and prebuilt macOS tools. Phases another program than a shell runs are reported
/// with it, not read.
enum ScriptRequirements {
    /// macOS-only commands nomac has no stand-in for, with what a project changes.
    static let commands: [String: String] = {
        let skip = "a macOS-only command: make the script skip it off macOS (`[ \"$(uname -s)\" = Darwin ]`) or use a tool both systems have"
        var notes = Dictionary(uniqueKeysWithValues: ["osascript", "open", "say", "afplay", "pbcopy", "pbpaste", "launchctl", "mdfind", "mdls",
                                                      "hdiutil", "diskutil", "system_profiler", "scutil", "networksetup", "textutil", "xattr",
                                                      "SetFile", "GetFileInfo", "spctl", "security", "sw_vers", "agvtool", "caffeinate"].map { ($0, skip) })
        notes["plutil"] = "macOS's plutil, which nomac does not provide yet (BACKLOG B-190): use PlistBuddy's commands (`/usr/libexec/PlistBuddy -c`, which nomac provides) or make the script skip it off macOS"
        notes["defaults"] = "macOS's defaults, which nomac does not provide yet (BACKLOG B-190): use PlistBuddy's commands (`/usr/libexec/PlistBuddy -c`, which nomac provides) or make the script skip it off macOS"
        notes["ipconfig"] = "macOS's ipconfig, which Linux lacks: the build machine's network address (React Native's Debug `ip.txt` falls back to `ifconfig`); the value is the machine's either way"
        notes["sips"] = "macOS's image tool: convert the images before the build, or with a tool both systems have"
        notes["iconutil"] = "macOS's icon tool: make the icon files before the build, or with a tool both systems have"
        notes["nc"] = "netcat, which macOS has in `/usr/bin` and Linux machines often lack: install it on the build machine (React Native's Start Packager phase falls back to `open` without it, which Linux lacks too; neither changes the products)"
        return notes
    }()

    static let bsdSedInPlace = "build:script=sed-in-place-bsd"
    static let machineArchitecture = "build:script=machine-architecture"
    static let prebuiltUploadSymbols = "build:script=crashlytics-upload-symbols"
    static let sentryReactNativeXcode = "build:script=sentry-cli-react-native-xcode"

    static func feature(_ command: String) -> String { "build:script-command=\(command)" }

    static let interpreterPrefix = "build:script-interpreter="

    /// A phase run by another program than a shell (its `shellPath`, `/usr/bin/env ruby` among
    /// them), which the Linux build machine must have installed.
    static func interpreterEntry(_ feature: String) -> EnvelopeEntry? {
        guard feature.hasPrefix(interpreterPrefix) else { return nil }
        let name = feature.dropFirst(interpreterPrefix.count)
        return .unverified(feature, "a run-script phase runs with `\(name)` (its shell), which macOS has and a Linux build machine needs installed on the `PATH` (macOS 27 has Ruby 2.6 in `/usr/bin`; Bugsnag's dSYM upload phase is Ruby): install it, or skip the phase off macOS")
    }

    static var entries: [EnvelopeEntry] {
        commands.keys.sorted().map { .unverified(feature($0), commands[$0]!) } + [
            .unverified(bsdSedInPlace, "BSD sed's `sed -i ''`, which GNU sed reads as a script and fails on: write `sed -i.bak … && rm …bak` or `perl -pi -e …`, which both systems run alike"),
            .unverified(machineArchitecture, "the script picks a tool by the machine's architecture (`uname -m`, `arch`): arm64 on a Mac, aarch64 or x86_64 on Linux; make sure the Linux branch names a tool built for Linux (ADR 0182)"),
            .unverified(prebuiltUploadSymbols, "Crashlytics' `upload-symbols`, a macOS executable: skip the upload off macOS or upload with a tool built for Linux (ADR 0182)"),
            .unverified(sentryReactNativeXcode, "`sentry-cli react-native xcode`, which sentry-cli's Linux build lacks (`error: unrecognized subcommand 'xcode'`, the RN sweep's expo-with-sentry) and which runs the script it is given, the JavaScript bundling, itself: build with `SENTRY_DISABLE_AUTO_UPLOAD=true` in the environment, with which `sentry-xcode.sh` runs the bundling directly and uploads no source maps (`SENTRY_ALLOW_FAILURE=true` would let the build go on without the bundle)"),
        ]
    }

    static let commandPosition = #"(?:^\s*|[|;&(`]\s*|\$\(\s*|\b(?:then|do|else|xcrun|exec|env|time|sudo)\s+|[\w./${}"-]*/)"#
    static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "ksh"]

    /// The findings of every run-script phase of `project` and of the scripts they call, each as
    /// (feature, file, object). `index` finds a script by name when its path holds settings this
    /// does not resolve.
    static func scan(project: XcodeProject, base: String, index: [String: [String]]) -> [(String, String, String)] {
        let directory = (project.path as NSString).deletingLastPathComponent
        let podsRoot = (project.path as NSString).lastPathComponent == "Pods.xcodeproj" ? directory : directory + "/Pods"
        var queue: [(label: String, file: String, text: String)] = []
        var findings: [(String, String, String)] = []
        for phase in project.pbxproj.shellScriptBuildPhases {
            let words = (phase.shellPath ?? "/bin/sh").split(separator: " ").map { ($0 as NSString).lastPathComponent }
            let interpreter = words.first == "env" ? words.dropFirst().first { !$0.hasPrefix("-") && !$0.contains("=") } : words.first
            let label = "phase '\(phase.name ?? "Run Script")'"
            guard let interpreter, shells.contains(interpreter) else {
                findings.append((interpreterPrefix + (interpreter ?? "env"), project.path + "/project.pbxproj", "\(label): shell \(phase.shellPath ?? "")"))
                continue
            }
            guard let script = phase.shellScript else { continue }
            queue.append((label, project.path + "/project.pbxproj", script))
        }
        var seen = Set<String>()
        while let (label, file, text) = queue.popLast() {
            if let first = text.split(separator: "\n", maxSplits: 1).first, first.hasPrefix("#!"),
               !shells.contains(((first.split(separator: " ").last.map(String.init) ?? "") as NSString).lastPathComponent),
               !shells.contains(((first.dropFirst(2).split(separator: " ").first.map(String.init) ?? "") as NSString).lastPathComponent) {
                continue
            }
            for (number, line) in withoutComments(text).enumerated() {
                let location = "\(label): line \(number + 1): \(line.trimmingCharacters(in: .whitespaces).prefix(100))"
                for command in commands.keys {
                    guard let range = line.range(of: commandPosition + NSRegularExpression.escapedPattern(for: command) + #"(?=[\s"';|)`]|$)"#,
                                                 options: .regularExpression) else { continue }
                    // `command || …` goes on when the command fails: a Linux build then continues without its result.
                    let hidden = line[range.upperBound...].contains("||") ? "; its failure is hidden by `||`, so a Linux build goes on without its result" : ""
                    findings.append((feature(command), file, location + hidden))
                }
                if matches(#"\bsed\b[^\n|;]*\s-i\s*(''|"")"#, line) { findings.append((bsdSedInPlace, file, location)) }
                if matches(#"\buname\s+-[a-z]*m\b|(?:^|[|;&(`]\s*|\$\(\s*)arch(?=[\s)`]|$)"#, line) { findings.append((machineArchitecture, file, location)) }
                if matches(#"upload-symbols\b"#, line) { findings.append((prebuiltUploadSymbols, file, location)) }
                if matches(#"(?i)sentry[\w-]*["\\]*\s+react-native\s+xcode\b"#, line) { findings.append((sentryReactNativeXcode, file, location)) }
            }
            for path in referencedScripts(text) {
                for resolved in resolve(path, directory: directory, podsRoot: podsRoot, index: index) where seen.insert(resolved).inserted {
                    if let contents = FileSystem.contents(atPath: resolved) {
                        queue.append(("script", resolved, String(decoding: contents, as: UTF8.self)))
                    }
                }
            }
        }
        return findings
    }

    static func matches(_ pattern: String, _ line: String) -> Bool {
        line.range(of: pattern, options: .regularExpression) != nil
    }

    static func withoutComments(_ text: String) -> [String] {
        text.components(separatedBy: "\n").map { line in
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("#") { return "" }
            return line.replacingOccurrences(of: #"(^|\s)#(?![!{]).*$"#, with: "", options: .regularExpression)
        }
    }

    /// Shell script paths a script names: quoted or bare words ending in `.sh` or `.bash`.
    static func referencedScripts(_ text: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: #""([^"\n]+\.(?:sh|bash))"|'([^'\n]+\.(?:sh|bash))'|(\S+\.(?:sh|bash))\b"#)
        let body = withoutComments(text).joined(separator: "\n")
        return pattern.matches(in: body, range: NSRange(body.startIndex..., in: body)).compactMap { match in
            (1...3).lazy.compactMap { Range(match.range(at: $0), in: body).map { String(body[$0]) } }.first
        }
    }

    static func resolve(_ path: String, directory: String, podsRoot: String, index: [String: [String]]) -> [String] {
        var text = path
        for (name, value) in [("SRCROOT", directory), ("PROJECT_DIR", directory), ("SOURCE_ROOT", directory), ("PODS_ROOT", podsRoot)] {
            text = text.replacingOccurrences(of: "${\(name)}", with: value).replacingOccurrences(of: "$(\(name))", with: value)
        }
        if !text.contains("$") {
            let candidate = text.hasPrefix("/") ? text : directory + "/" + text
            if FileSystem.isFile(candidate) { return [(candidate as NSString).standardizingPath] }
        }
        return Array((index[(text as NSString).lastPathComponent] ?? []).prefix(5))
    }

    /// Every `.sh` and `.bash` file under `roots` by name, build and version-control folders left out.
    static func scriptIndex(_ roots: [String]) -> [String: [String]] {
        var found: [String: [String]] = [:]
        for root in roots where FileSystem.isDirectory(root) {
            let enumerator = FileManager.default.enumerator(atPath: root)
            while let relative = enumerator?.nextObject() as? String {
                let name = (relative as NSString).lastPathComponent
                if [".git", "DerivedData", ".build", "build", "Build"].contains(name) {
                    enumerator?.skipDescendants()
                } else if name.hasSuffix(".sh") || name.hasSuffix(".bash") {
                    found[name, default: []].append(root + "/" + relative)
                }
            }
        }
        return found
    }
}
