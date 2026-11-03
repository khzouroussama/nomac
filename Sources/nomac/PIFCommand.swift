import ArgumentParser
import Foundation
import NomacBuildService
import NomacCore
import NomacInspect
import NomacProject

/// `nomac pif`: write the PIF Xcode would generate for a project or workspace.
struct PIFCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pif",
        abstract: "Write the project as Swift Build reads it (PIF).",
        discussion: """
        The output is byte-compatible with 'xcodebuild -dumpPIF', except for object \
        signatures, which are opaque transfer keys (see docs/formats/pif.md). Swift packages \
        are resolved as Xcode resolves them: remote ones are checked out in the workspace's \
        DerivedData folder (or under --derived-data-path) and pinned by its Package.resolved.
        """
    )

    @Argument(help: "An .xcodeproj or .xcworkspace.")
    var container: String

    @Option(name: .shortAndLong, help: "Write the PIF to this file instead of standard output.")
    var output: String?

    @Option(name: [.customLong("developer-dir")], help: "An Xcode Contents/Developer directory (default: $NOMAC_DEVELOPER_DIR, else the selected 'nomac sdk' install).")
    var developerDir: String?
    @Flag(name: .customLong("strict-xcode"), help: XcodeCheck.strictHelp)
    var strictXcode = false

    @Option(name: [.customLong("derivedDataPath", withSingleDash: true), .customLong("derived-data-path")], help: "The build location root, as for xcodebuild.")
    var derivedDataPath: String?

    @Flag(name: .customLong("skipMacroValidation", withSingleDash: true), help: "Approve the macros of remote packages, as xcodebuild's option does.")
    var skipMacroValidation = false

    func run() async throws {
        let workspace = try await Container.load(container)
        let pif = try await WorkspacePIF.generate(
            workspace: workspace,
            // Without --developer-dir, a missing SDK only matters to workspaces with packages, and
            // to those whose provisioning or Info.plist settings Swift Build must evaluate.
            developerDirectory: try DeveloperDirectory.resolveIfAvailable(option: developerDir, strictXcode: strictXcode),
            home: HostIdentity.current().homeDirectory,
            derivedDataPath: derivedDataPath.map(FileSystem.xcodebuildSpelling),
            skipsMacroValidation: skipMacroValidation)
        for warning in pif.warnings {
            FileHandle.standardError.write(Data("warning: \(warning)\n".utf8))
        }
        let text = pif.document.serialized()
        if let output {
            try FileSystem.write(Data(text.utf8), to: FileSystem.absolute(output))
        } else {
            print(text)
        }
    }
}
