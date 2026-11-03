import Foundation
import NomacBuildService
import NomacCore
import NomacPackages
import NomacPIF
import NomacProject

/// A workspace's complete PIF, with its Swift packages, as `xcodebuild -dumpPIF` writes it.
public struct WorkspacePIF: Sendable {
    public var document: PIFDocument
    /// Things nomac could not reproduce exactly; the PIF is still complete.
    public var warnings: [String]
    /// The packages of the workspace's resolved package graph.
    public var sourcePackages: [SourcePackage]
    /// The file references whose build files Xcode gives GUIDs drawn at random
    /// (``PIFGenerator/randomBuildFileReferences``).
    public var randomBuildFileReferences: Set<String> = []
    /// The absolute paths behind GUIDs that hash a path (``PIFGenerator/hashedBuildFilePaths``).
    public var hashedBuildFilePaths: [String: String] = [:]
    /// The commands the build tool plugins returned for the targets of the workspace's Xcode
    /// projects, which the build adds to their targets (``generate`` with `buildToolPlugins`).
    public var projectPluginCommands: [ProjectPluginCommands] = []

    /// Resolves the workspace's packages and generates the PIF.
    ///
    /// Remote packages are checked out where Xcode checks them out: `SourcePackages` in the
    /// workspace's DerivedData folder under `home`, or in `derivedDataPath` when given (as
    /// `xcodebuild -derivedDataPath` does).
    /// `INFOPLIST_FILE`, `GENERATE_INFOPLIST_FILE`, `CODE_SIGN_STYLE`, the provisioning profiles
    /// and the product's name, set with macros or SDK conditions, and the signing identities of
    /// targets that set no provisioning style, are evaluated as Xcode evaluates them, with Swift
    /// Build loading a first generation of the PIF; the document is then generated again with the
    /// values.
    /// - Parameters:
    ///   - developerDirectory: needed only when the workspace uses Swift packages, or when it sets
    ///     those settings with macros or conditions or has a target that sets no provisioning style
    ///     and `evaluatingSettings` is true.
    ///   - evaluatingSettings: false keeps the first generation, whose `provisioningSourceData`,
    ///     `bundleIdentifierFromInfoPlist` and product names take those settings as written, for
    ///     callers that print none of them (`nomac list`).
    ///   - skipsMacroValidation: approves remote packages' macros, as `-skipMacroValidation` does.
    ///   - buildToolPlugins: applies the package targets' build tool plugins, for a build.
    public static func generate(workspace: XcodeWorkspace, developerDirectory: String?, home: String, derivedDataPath: String? = nil,
                                evaluatingSettings: Bool = true, skipsMacroValidation: Bool = false,
                                buildToolPlugins: BuildToolPlugins? = nil) async throws -> WorkspacePIF {
        let sourcePackages = DerivedData.sourcePackagesPath(
            name: workspace.name, containerPath: DerivedData.containerPath(of: workspace), home: home, customRoot: derivedDataPath)
        var packages = try SwiftPackages(workspace: workspace, sourcePackagesDirectory: sourcePackages, developerDirectory: developerDirectory,
                                         skipsMacroValidation: skipsMacroValidation)
        packages.buildToolPlugins = buildToolPlugins
        let packageProjects = try await packages.load()
        var generator = PIFGenerator(workspace: workspace, packages: packageProjects)
        var document = try generator.generate()
        if evaluatingSettings && !generator.unevaluatedSettings.isEmpty {
            guard let developerDirectory else {
                throw NomacError("INFOPLIST_FILE, GENERATE_INFOPLIST_FILE, CODE_SIGN_STYLE, a provisioning profile or the product's name set with macros or conditions, or the signing identity of a target that sets no provisioning style, needs a developer directory to be evaluated", path: workspace.path)
            }
            let first = WorkspacePIF(document: document, warnings: [], sourcePackages: packages.sourcePackages)
            var host = HostIdentity.current()
            host.homeDirectory = home
            let scratch = FileManager.default.temporaryDirectory.path + "/nomac-pif-\(UUID().uuidString)"
            defer { try? FileManager.default.removeItem(atPath: scratch) }
            let queries = generator.unevaluatedSettings
            let expressions = generator.unevaluatedExpressions
            let values = try await BuildSettingsInspector.with(workspace: workspace, pif: first, developerDirectory: developerDirectory, host: host, scratchDirectory: scratch) {
                try await $0.evaluate(queries, expressions: expressions)
            }
            generator = PIFGenerator(workspace: workspace, fileTypes: generator.fileTypes, packages: packageProjects, evaluatedSettings: values)
            document = try generator.generate()
        }
        var pif = WorkspacePIF(document: document, warnings: generator.warnings + packages.warnings, sourcePackages: packages.sourcePackages,
                               randomBuildFileReferences: generator.randomBuildFileReferences, hashedBuildFilePaths: generator.hashedBuildFilePaths)
        pif.projectPluginCommands = packages.projectPluginCommands
        return pif
    }
}
