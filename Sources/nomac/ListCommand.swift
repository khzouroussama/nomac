import ArgumentParser
import Foundation
import NomacBuildService
import NomacCore
import NomacInspect
import NomacProject
import NomacSDK
import NomacVerify

/// `nomac list`: what `xcodebuild -list` prints for a project or workspace.
struct ListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List targets and schemes, as 'xcodebuild -list'.",
        discussion: """
        Schemes include those of the workspace's Swift packages and those Xcode autocreates \
        (docs/formats/list.md). Accepts xcodebuild's spelling of the options.

        Examples:
          nomac list -project App.xcodeproj
          nomac list -workspace App.xcworkspace -json
        """
    )

    @Option(name: [.customLong("project", withSingleDash: true), .customLong("project")], help: "The .xcodeproj to list.")
    var project: String?

    @Option(name: [.customLong("workspace", withSingleDash: true), .customLong("workspace")], help: "The .xcworkspace to list.")
    var workspace: String?

    @Flag(name: [.customLong("json", withSingleDash: true), .customLong("json")], help: "Print JSON, as 'xcodebuild -list -json'.")
    var json = false

    @Option(name: [.customLong("derivedDataPath", withSingleDash: true), .customLong("derived-data-path")], help: "The build location root, as for xcodebuild.")
    var derivedDataPath: String?

    @Option(name: [.customLong("developer-dir")], help: "An Xcode Contents/Developer directory (default: $NOMAC_DEVELOPER_DIR, else the selected 'nomac sdk' install).")
    var developerDir: String?
    @Flag(name: .customLong("strict-xcode"), help: XcodeCheck.strictHelp)
    var strictXcode = false

    @Flag(name: [.customLong("list", withSingleDash: true)], help: .hidden)
    var list = false

    func run() async throws {
        let loaded = try await Container.load(try Container.path(project: project, workspace: workspace))
        // A missing SDK only matters to workspaces with packages, or whose schemes depend on
        // target settings: the list prints no setting the PIF's second generation evaluates.
        let developer = try DeveloperDirectory.resolveIfAvailable(option: developerDir, strictXcode: strictXcode)
        let host = HostIdentity.default()
        let pif = try await WorkspacePIF.generate(workspace: loaded, developerDirectory: developer, home: host.homeDirectory,
                                                  derivedDataPath: derivedDataPath.map(FileSystem.xcodebuildSpelling), evaluatingSettings: false)
        for warning in pif.warnings {
            FileHandle.standardError.write(Data("warning: \(warning)\n".utf8))
        }
        let packages = pif.sourcePackages.map(\.contents)
        let schemes: [XcodeScheme]
        if loaded.schemeSettingsQueries().isEmpty {
            schemes = try loaded.schemes(packages: packages, userName: host.userName)
        } else {
            schemes = try await BuildSettingsInspector.with(workspace: loaded, pif: pif, developerDirectory: developer ?? DeveloperDirectory.resolve(option: nil, strictXcode: strictXcode),
                                                            host: host, scratchDirectory: SDKStore.default().root + "/scratch") {
                try await $0.schemes()
            }
        }
        let listing = WorkspaceListing(workspace: loaded, schemes: schemes)
        if json {
            print(listing.json, terminator: "")
            return
        }
        print("Command line invocation:\n    \(CommandLine.arguments.joined(separator: " "))\n")
        print(ShowBuildSettings.renderResolvedPackages(pif.sourcePackages.map(\.listing)), terminator: "")
        print(listing.text, terminator: "")
    }
}
