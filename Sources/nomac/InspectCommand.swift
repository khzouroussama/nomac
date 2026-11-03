import ArgumentParser
import Foundation
import NomacBuildService
import NomacCore
import NomacInspect
import NomacProject
import NomacSDK
import NomacVerify

/// `nomac inspect`: print resolved build settings exactly as `xcodebuild -showBuildSettings`.
struct InspectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Print build settings (-showBuildSettings).",
        discussion: """
        Accepts xcodebuild's spelling of the options (-project, -workspace, -target, \
        -alltargets, -scheme, -configuration, -destination, -derivedDataPath, -json) as well \
        as the double-dash forms. Trailing KEY=VALUE \
        arguments override build settings, as they do for xcodebuild.

        Examples:
          nomac inspect -project App.xcodeproj -target App -configuration Debug
          nomac inspect -workspace App.xcworkspace -scheme App -destination generic/platform=iOS
          nomac inspect --project App.xcodeproj --all-targets SWIFT_VERSION=6.0
        """
    )

    @Option(name: [.customLong("project", withSingleDash: true), .customLong("project")], help: "The .xcodeproj to load.")
    var project: String?

    @Option(name: [.customLong("workspace", withSingleDash: true), .customLong("workspace")], help: "The .xcworkspace to load.")
    var workspace: String?

    @Option(name: [.customLong("target", withSingleDash: true), .customLong("target")], help: "A target to report (repeatable).")
    var targets: [String] = []

    @Flag(name: [.customLong("alltargets", withSingleDash: true), .customLong("all-targets")], help: "Report every target of the project.")
    var allTargets = false

    @Option(name: [.customLong("scheme", withSingleDash: true), .customLong("scheme")], help: "Report the targets the scheme builds for running.")
    var scheme: String?

    @Option(name: [.customLong("destination", withSingleDash: true), .customLong("destination")], help: "The run destination; nomac supports 'generic/platform=iOS'.")
    var destination: String?

    @Option(name: [.customLong("derivedDataPath", withSingleDash: true), .customLong("derived-data-path")], help: "The build location root, as for xcodebuild.")
    var derivedDataPath: String?

    @Option(name: [.customLong("configuration", withSingleDash: true), .customLong("configuration")], help: "The build configuration (default: the project's default configuration).")
    var configuration: String?

    @Option(name: [.customLong("developer-dir")], help: "An Xcode Contents/Developer directory (default: $NOMAC_DEVELOPER_DIR, else the selected 'nomac sdk' install).")
    var developerDir: String?
    @Flag(name: .customLong("strict-xcode"), help: XcodeCheck.strictHelp)
    var strictXcode = false

    @Option(name: [.customLong("host-identity")], help: "A reference host.json whose user, machine and environment Swift Build should see (see docs/VERIFICATION.md); default: this user and machine, off macOS on the reference Mac of 'nomac sdk profile'.")
    var hostIdentity: String?

    @Flag(name: [.customLong("json", withSingleDash: true), .customLong("json")], help: "Print JSON, as 'xcodebuild -showBuildSettings -json'.")
    var json = false

    @Flag(name: [.customLong("showBuildSettings", withSingleDash: true)], help: .hidden)
    var showBuildSettings = false

    @Argument(help: "Build setting overrides, KEY=VALUE.")
    var overrides: [String] = []

    func run() async throws {
        let container = try Container.path(project: project, workspace: workspace)
        let loaded = try await Container.load(container)
        let developer = try resolveDeveloperDirectory()
        let host: HostIdentity
        if let hostIdentity {
            host = try ReferenceHost.load(path: FileSystem.absolute(hostIdentity)).identity(developerDirectory: developer)
        } else {
            host = .default()
        }
        let selection: BuildSettingsInspector.Selection
        if let scheme {
            guard targets.isEmpty, !allTargets else {
                throw NomacError("-scheme cannot be combined with -target or -alltargets")
            }
            selection = .scheme(scheme)
        } else {
            selection = allTargets ? .allTargets : (targets.isEmpty ? .defaultTarget : .targets(targets))
        }
        var overrideTable: [String: String] = [:]
        for item in overrides {
            guard let equals = item.firstIndex(of: "=") else {
                throw NomacError("expected a build setting override of the form KEY=VALUE, got '\(item)'")
            }
            overrideTable[String(item[..<equals])] = String(item[item.index(after: equals)...])
        }
        let invocation = BuildSettingsInspector.Invocation(
            selection: selection,
            configuration: configuration,
            destination: destination,
            derivedDataPath: derivedDataPath.map(FileSystem.xcodebuildSpelling),
            overrides: overrideTable)
        let blocks = try await BuildSettingsInspector.with(
            workspace: loaded,
            developerDirectory: developer,
            host: host,
            scratchDirectory: SDKStore.default().root + "/scratch",
            derivedDataPath: invocation.derivedDataPath
        ) { inspector in
            for warning in inspector.warnings {
                FileHandle.standardError.write(Data("warning: \(warning)\n".utf8))
            }
            // xcodebuild prints these lines before it evaluates anything, failures included; with
            // -json it prints only the JSON.
            if !json {
                print("Command line invocation:\n    \(CommandLine.arguments.joined(separator: " "))\n")
                print(ShowBuildSettings.renderResolvedPackages(inspector.sourcePackages.map(\.listing)), terminator: "")
            }
            if let unknown = inspector.unknownConfiguration(invocation) {
                FileHandle.standardError.write(Data("--- xcodebuild: WARNING: Configuration \(unknown) is not in the project. Building default configuration.\n".utf8))
            }
            return try await inspector.blocks(invocation)
        }
        print(json ? try ShowBuildSettings.renderJSON(blocks) : ShowBuildSettings.render(blocks), terminator: "")
    }

    private func resolveDeveloperDirectory() throws -> String {
        try DeveloperDirectory.resolve(option: developerDir, strictXcode: strictXcode)
    }
}
