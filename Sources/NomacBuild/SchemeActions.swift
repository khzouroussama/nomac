import Foundation
import NomacCore

/// A scheme's shell script actions, run as xcodebuild runs them (`scheme_action_experiments.py`,
/// docs/formats/build.md "Scheme actions"): each written to `<TMPDIR>/SchemeScriptAction-XXXXXX.sh`
/// and run as `/bin/sh -c <file>` from TMPDIR, with the environment xcodebuild gives it, which its
/// log lists sorted.
public struct SchemeActions {
    /// One action to run.
    public struct Script: Sendable {
        public var title: String
        public var text: String
        /// The exported build settings of the action's environment buildable, when it has one.
        public var settings: [String: String]?

        public init(title: String, text: String, settings: [String: String]?) {
            self.title = title
            self.text = text
            self.settings = settings
        }
    }

    public var developerDirectory: String
    public var schemeName: String
    /// The project or workspace the scheme belongs to.
    public var containerPath: String
    /// The workspace path xcodebuild exports: a project's `project.xcworkspace` for a project opened alone.
    public var workspacePath: String
    /// The run destination's variables (``destinationEnvironment(_:)``).
    public var destination: [String: String]
    /// The shell for `-c`: `/bin/sh`, or off macOS the macOS-like shell nomac installs (ADR 0103).
    public var shell: String
    public var environment: [String: String]

    public init(developerDirectory: String, schemeName: String, containerPath: String, workspacePath: String,
                destination: [String: String], shell: String, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.developerDirectory = developerDirectory
        self.schemeName = schemeName
        self.containerPath = containerPath
        self.workspacePath = workspacePath
        self.destination = destination
        self.shell = shell
        self.environment = environment
    }

    /// The variables xcodebuild sets for `generic/platform=iOS`, the one destination observed.
    public static func destinationEnvironment(_ specifier: String?) -> [String: String] {
        guard specifier == "generic/platform=iOS" else { return [:] }
        return ["DEVICE_NAME": "Any iOS Device", "RUN_DESTINATION_DEVICE_MODEL": "GenericiOS",
                "RUN_DESTINATION_DEVICE_NAME": "Any iOS Device",
                "RUN_DESTINATION_DEVICE_PLATFORM_IDENTIFIER": "com.apple.platform.iphoneos",
                "RUN_DESTINATION_DEVICE_PLATFORM_NAME": "iphoneos",
                "RUN_DESTINATION_DEVICE_UDID": "dvtdevice-DVTiPhonePlaceholder-iphoneos:placeholder"]
    }

    /// Runs every script in order, under `heading` in the log when given (`Run pre-actions`;
    /// archive actions print nothing), and returns the failure summary's lines of those that
    /// failed: a failed action does not stop the next.
    public func run(_ scripts: [Script], heading: String?, log: (String) -> Void) throws -> [String] {
        guard !scripts.isEmpty else { return [] }
        if let heading { log("\(heading)\n\n") }
        var failures: [String] = []
        for script in scripts {
            let status = try run(script, logging: heading != nil, log: log)
            if status != 0 {
                failures += ["Run custom shell script '\(script.title)'", blueprintProvider]
            }
        }
        return failures
    }

    private func run(_ script: Script, logging: Bool, log: (String) -> Void) throws -> Int32 {
        let directory = environment["TMPDIR"] ?? NSTemporaryDirectory()
        let temporary = directory.hasSuffix("/") ? directory : directory + "/"
        var template = Array((temporary + "SchemeScriptAction-XXXXXX.sh").utf8CString)
        let descriptor = mkstemps(&template, 3)
        guard descriptor >= 0 else { throw NomacError("could not create the scheme action's script", path: temporary) }
        close(descriptor)
        let path = String(cString: template)
        defer { try? FileManager.default.removeItem(atPath: path) }
        try FileSystem.write(Data(script.text.utf8), to: path)
        chmod(path, 0o755)

        var variables = environment
        variables["PATH"] = developerDirectory + "/usr/bin" + (environment["PATH"].map { ":" + $0 } ?? "")
        variables["MANPATH"] = developerDirectory + "/usr/share/man:" + developerDirectory + "/Toolchains/XcodeDefault.xctoolchain/usr/share/man:"
        variables["SCHEME_ACTION_NAME"] = script.title
        variables["SCHEME_NAME"] = schemeName
        variables["WORKSPACE_PATH"] = workspacePath
        variables.merge(destination) { _, new in new }
        if let settings = script.settings {
            variables.merge(settings) { _, new in new }
        }
        if logging {
            var text = "SchemeAction \(script.title.replacingOccurrences(of: " ", with: "\\ ")) \(path)\n    cd \(temporary)\n"
            for (key, value) in variables.sorted(by: { Array($0.key.utf8).lexicographicallyPrecedes(Array($1.key.utf8)) }) {
                text += "    export \(key)=\(Self.quoted(value))\n"
            }
            log(text + "    /bin/sh -c \(path)\n")
        }
        let result = try Subprocess.run(shell, ["-c", path], currentDirectory: temporary, environment: variables)
        if logging {
            log(String(decoding: result.standardOutput + result.standardError, as: UTF8.self) + "\n")
        }
        return result.exitStatus
    }

    /// The failure summary's second line for a failed action: the scheme's container as Xcode's
    /// blueprint provider, base64 JSON with escaped slashes.
    var blueprintProvider: String {
        let path = containerPath.replacingOccurrences(of: "/", with: "\\/")
        return Data(#"{"blueprintProvider_providerFilePathString":"\#(path)","type":{"blueprintProvider":{}}}"#.utf8).base64EncodedString()
    }

    /// An exported value as xcodebuild's log writes it: bare when every character is a letter, a
    /// digit or one of `+,-./=_` (or empty), else in double quotes with `"` and `\` escaped.
    static func quoted(_ value: String) -> String {
        let bare = value.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "+,-./=_".unicodeScalars.contains(scalar))
        }
        guard !bare else { return value }
        return "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
