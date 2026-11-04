import Basics
import Foundation
import NomacCore
import NomacPIF
import NomacProject
@preconcurrency import PackageGraph
import PackageLoading
@preconcurrency import PackageModel
import SourceControl
import SwiftBuild
import VendoredPackagePIFBuilder
@preconcurrency import Workspace
import XcodeProj
import struct TSCUtility.Version

/// Resolves a workspace's Swift packages with SwiftPM and builds their PIF as Xcode 27.0 does
/// (docs/adr/0010-swift-packages.md).
///
/// Packages are loaded as Xcode loads them: package folders in the file tree as roots, with
/// one test product per test target and Xcode's file rules; manifests evaluated as on a Mac;
/// remote packages checked out in the workspace's `SourcePackages` folder and pinned by its
/// `Package.resolved`. Each package becomes a PIF project through the PIF builder Xcode uses,
/// answered as Xcode answers it (``XcodeBuildDelegate``).
public struct SwiftPackages {
    public let workspace: XcodeWorkspace
    public let references: PackageReferences
    /// Where remote packages are checked out (Xcode: `DerivedData/<name>-<hash>/SourcePackages`).
    public let sourcePackagesDirectory: String
    /// The Xcode developer directory, for the testing frameworks' deployment targets and the
    /// SDKs' platform version maps; required only when the workspace uses packages.
    public let developerDirectory: String?
    /// Whether remote packages' macros are approved, as with xcodebuild's `-skipMacroValidation`.
    public let skipsMacroValidation: Bool
    /// Things nomac could not reproduce exactly; the PIF is still generated.
    public private(set) var warnings: [String] = []
    /// Every package of the resolved graph, by identity; empty until ``load()``.
    public private(set) var sourcePackages: [SourcePackage] = []
    /// Applies the package targets' build tool plugins while loading, for a build; without it
    /// the PIF has none of their commands, as for the commands that do not build.
    public var buildToolPlugins: BuildToolPlugins?
    /// The commands the plugins returned for the targets of the workspace's Xcode projects; empty
    /// until ``load()``, and without ``buildToolPlugins``.
    public private(set) var projectPluginCommands: [ProjectPluginCommands] = []

    public init(workspace: XcodeWorkspace, sourcePackagesDirectory: String, developerDirectory: String?, skipsMacroValidation: Bool = false) throws {
        self.workspace = workspace
        self.references = try PackageReferences.find(in: workspace)
        self.sourcePackagesDirectory = sourcePackagesDirectory
        self.developerDirectory = developerDirectory
        self.skipsMacroValidation = skipsMacroValidation
    }

    /// xcodebuild's status when it cannot resolve the packages ("Could not resolve package
    /// dependencies"; envelope-experiments `survey-shapes-2`, a local package not on disk).
    static let resolutionFailure: Int32 = 74

    /// The name the manifest of the package in `folder` gives it, which names the workspace
    /// xcodebuild makes of the folder (``XcodeWorkspace/package(folder:name:)``).
    public static func manifestName(folder: String) async throws -> String {
        try await rootManifest(folder: folder).displayName
    }

    /// The names of the macro targets the manifest of the package in `folder` declares.
    public static func macroTargets(folder: String) async throws -> [String] {
        try await rootManifest(folder: folder).targets.filter { $0.type == .macro }.map(\.name)
    }

    private static func rootManifest(folder: String) async throws -> Manifest {
        let scratch = FileManager.default.temporaryDirectory.path + "/nomac-manifest-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: scratch) }
        let packages = try SwiftPackages(workspace: .package(folder: folder, name: ""), sourcePackagesDirectory: scratch, developerDirectory: nil)
        let diagnostics = DiagnosticsCollector()
        let observability = ObservabilitySystem { _, diagnostic in diagnostics.add(diagnostic) }
        let (workspace, _) = try packages.makeWorkspace()
        return try await workspace.loadRootManifest(at: Basics.AbsolutePath(validating: FileSystem.onDisk(folder)),
                                                    observabilityScope: observability.topScope)
    }

    /// The package projects and the products that the workspace's targets depend on.
    public mutating func load() async throws -> PackageProjects {
        guard !references.isEmpty else { return PackageProjects() }
        guard let developerDirectory else {
            throw NomacError("\(workspace.path) uses Swift packages; nomac needs an Xcode developer directory to resolve them as Xcode does",
                             notes: ["install one with 'nomac sdk install', or pass --developer-dir"])
        }
        let diagnostics = DiagnosticsCollector()
        let observability = ObservabilitySystem { _, diagnostic in diagnostics.add(diagnostic) }

        let xctest = XCTestDeploymentTargets.compute(developerDirectory: developerDirectory)
        if !xctest.missing.isEmpty {
            warnings.append("testing frameworks not found for \(xctest.missing.map(\.name).sorted().joined(separator: ", ")) in \(developerDirectory); package test products may get lower deployment targets than in Xcode (reinstall the SDK with `nomac sdk install`)")
        }
        let alignment = PlatformAlignment(developerDirectory: developerDirectory)

        // Without the Package.resolved that pins the packages, Xcode creates the workspace's
        // `xcshareddata/swiftpm/configuration` folder, whatever of that path is missing, for
        // remote, local and root packages, keeps it, and writes the file next to it when the graph
        // has remote packages (envelope-experiments `package-resolved`); SwiftPM writes the file
        // only into an existing folder.
        if !FileSystem.isFile(references.resolvedFile) {
            try FileSystem.createDirectory((references.resolvedFile as NSString).deletingLastPathComponent + "/configuration")
        }
        let (workspace, manifestLoader) = try makeWorkspace()
        let rootInput = PackageGraphRootInput(
            packages: try references.rootPackages.map { try Basics.AbsolutePath(validating: FileSystem.onDisk($0)) },
            dependencies: try references.localDependencies.map(Self.localDependency) + references.remoteDependencies.map(Self.remoteDependency))
        let graph: ModulesGraph
        do {
            graph = try await workspace.loadPackageGraph(
                rootInput: rootInput,
                customXCTestMinimumDeploymentTargets: xctest.targets,
                observabilityScope: observability.topScope)
        } catch {
            throw NomacError("cannot resolve the workspace's Swift packages: \(error)", notes: diagnostics.errors, exitStatus: Self.resolutionFailure)
        }
        guard diagnostics.errors.isEmpty else {
            throw NomacError("cannot resolve the workspace's Swift packages", notes: diagnostics.errors, exitStatus: Self.resolutionFailure)
        }
        for (manifest, conditions) in manifestLoader.unansweredConditions.sorted(by: { $0.key < $1.key }) {
            #if os(macOS)
            warnings.append("\(manifest): \(conditions.joined(separator: ", ")) answered by this Mac's Swift compiler; nomac on Linux does not know how a Mac answers them")
            #else
            warnings.append("\(manifest): \(conditions.joined(separator: ", ")) evaluated as on Linux; nomac does not know how a Mac answers them")
            #endif
        }
        try await useBuildMachinePrebuilts(workspace, graph: graph)
        ModuleGraphFacts.register(graph)
        sourcePackages = sourcePackages(of: graph)

        let plugins = try await buildToolPlugins?.apply(to: graph, projects: self.workspace.allProjects)
        projectPluginCommands = plugins?.projectCommands ?? []
        let pluginResults = plugins?.packageResults ?? [:]
        var projects: [PackageProjects.Project] = []
        for package in graph.packages.sorted(by: { $0.identity.description < $1.identity.description }) {
            let delegate = XcodeBuildDelegate(
                package: package, alignment: alignment,
                // A remote package checked out at a branch or revision was loaded without a version.
                isBranchOrRevisionBased: package.manifest.packageKind.isRemote && package.manifest.version == nil,
                skipsMacroValidation: skipsMacroValidation, isPackageWorkspace: self.workspace.isPackage)
            let builder = PackagePIFBuilder(
                modulesGraph: graph, resolvedPackage: package, packageManifest: package.manifest, delegate: delegate,
                buildToolPluginResultsByTargetName: pluginResults[package.identity] ?? [:],
                addLocalRpaths: .debugOnly,
                packageDisplayVersion: nil, pkgConfigDirectories: [], fileSystem: localFileSystem,
                observabilityScope: observability.topScope)
            let built = try builder.build()
            let project = builder.pifProject
            projects.append(PackageProjects.Project(
                contents: try PIFValue(encoding: project),
                targets: try project.targets.map { try PIFValue(encoding: $0) },
                documentOrder: Self.documentOrder(of: project, built: built)))
            withExtendedLifetime(delegate) {}
        }
        guard diagnostics.errors.isEmpty else {
            throw NomacError("cannot build the PIF of the workspace's Swift packages", notes: diagnostics.errors)
        }
        warnings += diagnostics.warnings
        return PackageProjects(projects: projects, products: products(in: graph))
    }

    // MARK: Workspace

    private func makeWorkspace() throws -> (Workspace, MacManifestLoader) {
        let scratch = try Basics.AbsolutePath(validating: sourcePackagesDirectory)
        let location = Workspace.Location(
            scratchDirectory: scratch,
            editsDirectory: scratch.appending("edits"),
            resolvedVersionsFile: try Basics.AbsolutePath(validating: FileSystem.onDisk(references.resolvedFile)),
            localConfigurationDirectory: try Basics.AbsolutePath(validating: FileSystem.onDisk(workspace.path)).appending(components: "xcshareddata", "swiftpm", "configuration"),
            sharedConfigurationDirectory: nil,
            sharedSecurityDirectory: nil,
            sharedCacheDirectory: Self.sharedCacheDirectory,
            emitDeprecatedConfigurationWarning: false)
        var configuration = WorkspaceConfiguration.default
        configuration.shouldCreateMultipleTestProducts = true
        configuration.additionalFileRules = PackagePIFBuilder.xcodeFileRules
        let toolchain = try Self.hostToolchain()
        configuration.usePrebuilts = true
        let manifestLoader = MacManifestLoader(underlying: ManifestLoader(toolchain: toolchain))
        let workspace = try Workspace._init(
            fileSystem: localFileSystem, environment: .current, location: location, configuration: configuration,
            customHostToolchain: toolchain, customManifestLoader: manifestLoader,
            customPrebuiltsManager: Workspace.CustomPrebuiltsManager(swiftVersion: Self.xcodePrebuiltName(), hostPlatform: .macos_universal))
        return (workspace, manifestLoader)
    }

    private static func hostToolchain() throws -> UserToolchain {
        do {
            return try UserToolchain(swiftSDK: .hostSwiftSDK(toolchainBinDirectory(), environment: .current), environment: .current, fileSystem: localFileSystem)
        } catch {
            throw NomacError("cannot find a Swift toolchain to evaluate package manifests: \(error)",
                             notes: ["nomac evaluates Package.swift with the Swift toolchain on PATH, as SwiftPM does, or the one install.sh put beside nomac"])
        }
    }

    /// The name SwiftPM gives the prebuilts it uses with Xcode's toolchain: the compiler's
    /// `swiftlang-` version and the macOS SDK's canonical name, `swiftlang-6.4.0.34.1-macosx27.0`
    /// for Xcode 27.0, whose PIF builds a remote swift-syntax's macro targets against
    /// `SourcePackages/prebuilts/swift-syntax/<version>/swiftlang-6.4.0.34.1-macosx27.0-MacroSupport`
    /// (`macro_plugin_experiments.py` macro-package; firefox's swift-syntax 603.0.2).
    static func xcodePrebuiltName(profile: XcodeProfile = .current) -> String {
        let compiler = profile.xcodeTools.swiftCompiler
        let version = compiler.range(of: "swiftlang-[0-9.]+", options: .regularExpression).map { String(compiler[$0]) } ?? compiler
        let sdk = profile.sdks.first { $0.platform == "macosx" }?.canonicalName ?? "macosx"
        return version + "-" + sdk
    }

    /// Off macOS, each prebuilt the workspace uses holds macOS's libraries under Xcode's name.
    /// The build machine's build of the same library replaces them: a workspace of the prebuilt
    /// package alone, at its version, gets it from SwiftPM under SwiftPM's name for the compiler
    /// that builds the macro, the toolchain `nomac toolchain install` installs, and this machine
    /// (`swift-6.4.0-RELEASE-ubuntu_noble_aarch64-MacroSupport`, the same `lib` and `Modules`;
    /// binary modules load only in the compiler that wrote them).
    /// The PIF keeps naming Xcode's folder; a marker file there records the replacement.
    private mutating func useBuildMachinePrebuilts(_ workspace: Workspace, graph: ModulesGraph) async throws {
        #if !os(macOS)
        let prebuilts = Array(await workspace.state.prebuilts)
        guard !prebuilts.isEmpty, let platform = PrebuiltsPlatform.hostPlatform else { return }
        for prebuilt in prebuilts {
            let marker = prebuilt.path.pathString + "/" + Self.buildMachinePrebuiltMarker
            guard !FileSystem.isFile(marker),
                  let package = graph.packages.first(where: { $0.identity == prebuilt.identity }),
                  case .remoteSourceControl(let url) = package.manifest.packageKind else { continue }
            let scratch = FileManager.default.temporaryDirectory.path + "/nomac-prebuilts-\(UUID().uuidString)"
            defer { try? FileManager.default.removeItem(atPath: scratch) }
            let root = try Basics.AbsolutePath(validating: scratch)
            let location = Workspace.Location(
                scratchDirectory: root, editsDirectory: root.appending("edits"), resolvedVersionsFile: root.appending("Package.resolved"),
                localConfigurationDirectory: root.appending("configuration"), sharedConfigurationDirectory: nil, sharedSecurityDirectory: nil,
                sharedCacheDirectory: Self.sharedCacheDirectory, emitDeprecatedConfigurationWarning: false)
            var configuration = WorkspaceConfiguration.default
            configuration.usePrebuilts = true
            let helper = try Workspace._init(
                fileSystem: localFileSystem, environment: .current, location: location, configuration: configuration,
                customHostToolchain: try Self.hostToolchain(),
                customPrebuiltsManager: Workspace.CustomPrebuiltsManager(swiftVersion: XcodeProfile.current.pins.swiftToolchainTag + "-\(platform)", hostPlatform: platform))
            let dependency = PackageDependency.remoteSourceControl(
                identity: prebuilt.identity, nameForTargetDependencyResolutionOnly: nil, url: url,
                requirement: .exact(prebuilt.version), productFilter: .everything)
            let observability = ObservabilitySystem { _, _ in }
            _ = try await helper.loadPackageGraph(rootInput: PackageGraphRootInput(packages: [], dependencies: [dependency]),
                                                  observabilityScope: observability.topScope)
            guard let built = await helper.state.prebuilts.first(where: { $0.identity == prebuilt.identity && $0.libraryName == prebuilt.libraryName }) else {
                warnings.append("SwiftPM has no prebuilt \(prebuilt.libraryName) of \(prebuilt.identity) \(prebuilt.version) for this machine; the macro targets that Xcode builds against it cannot link here")
                continue
            }
            try FileManager.default.removeItem(atPath: prebuilt.path.pathString)
            try FileManager.default.copyItem(atPath: built.path.pathString, toPath: prebuilt.path.pathString)
            try FileSystem.write(Data(built.path.basename.utf8), to: marker)
        }
        #endif
    }

    static let buildMachinePrebuiltMarker = ".nomac-build-machine"

    /// SwiftPM's cache of the remote repositories and binary artifacts it fetched, shared by every
    /// workspace, as Xcode shares `~/Library/Caches/org.swift.swiftpm` (`repositories` and
    /// `artifacts`, filled by Xcode's resolutions of the corpus apps on the reference Mac); off
    /// macOS SwiftPM's own location, `$XDG_CACHE_HOME` or `~/.cache`. SwiftPM caches no
    /// repository at a file URL.
    static var sharedCacheDirectory: Basics.AbsolutePath? { try? localFileSystem.swiftPMCacheDirectory }

    /// The directory of the first `swiftc` on `PATH` that, once symbolic links are resolved, sits
    /// in a toolchain with `lib/swift/pm/ManifestAPI`, so that a toolchain linked into
    /// `/usr/local/bin` finds its own manifest API, else the toolchain install.sh keeps beside
    /// nomac. `nil` when `SWIFT_EXEC` names the compiler or there is no such `swiftc`, as on a
    /// Mac, whose `/usr/bin/swiftc` runs the selected
    /// Xcode's compiler; SwiftPM then searches itself (`xcrun` there, honouring `DEVELOPER_DIR`).
    static func toolchainBinDirectory(environment: [String: String] = ProcessInfo.processInfo.environment,
                                      executable: String? = Bundle.main.executablePath) -> Basics.AbsolutePath? {
        guard environment["SWIFT_EXEC"] == nil else { return nil }
        let installed = executable.map { path in
            FileSystem.resolvingSymbolicLinks(path).split(separator: "/").dropLast(2).reduce("") { $0 + "/" + $1 } + "/swift/usr/bin"
        }
        let directories = (environment["PATH"] ?? "").split(separator: ":").map(String.init) + (installed.map { [$0] } ?? [])
        for directory in directories where directory.hasPrefix("/") {
            let candidate = directory + "/swiftc"
            guard FileManager.default.isExecutableFile(atPath: candidate) else { continue }
            let resolved = (FileSystem.resolvingSymbolicLinks(candidate) as NSString).deletingLastPathComponent
            guard FileSystem.isDirectory(resolved + "/../lib/swift/pm/ManifestAPI") else { continue }
            return try? Basics.AbsolutePath(validating: resolved)
        }
        return nil
    }

    /// The `swift` of the toolchain that evaluates manifests (``toolchainBinDirectory(environment:)``),
    /// else the first on `PATH`.
    public static func swiftCommand() -> [String] {
        toolchainBinDirectory().map { [$0.appending("swift").pathString] } ?? ["/usr/bin/env", "swift"]
    }

    private static func localDependency(_ path: String) throws -> PackageDependency {
        let absolute = try Basics.AbsolutePath(validating: FileSystem.onDisk(path))
        return .fileSystem(identity: PackageIdentity(path: absolute), nameForTargetDependencyResolutionOnly: nil, path: absolute, productFilter: .everything)
    }

    private static func remoteDependency(_ remote: PackageReferences.Remote) -> PackageDependency {
        let url = SourceControlURL(remote.url)
        let requirement: PackageDependency.SourceControl.Requirement
        switch remote.requirement {
        case .upToNextMajorVersion(let version): requirement = .range(.upToNextMajor(from: Self.version(version)))
        case .upToNextMinorVersion(let version): requirement = .range(.upToNextMinor(from: Self.version(version)))
        case .range(let from, let to): requirement = .range(Self.version(from)..<Self.version(to))
        case .exact(let version): requirement = .exact(Self.version(version))
        case .branch(let branch): requirement = .branch(branch)
        case .revision(let revision): requirement = .revision(revision)
        }
        return .remoteSourceControl(identity: PackageIdentity(url: url), nameForTargetDependencyResolutionOnly: nil, url: url, requirement: requirement, productFilter: .everything)
    }

    private static func version(_ text: String) -> Version {
        (try? Version(versionString: text, usesLenientParsing: true)) ?? Version(0, 0, 0)
    }

    /// The order Xcode writes a package's target objects in: the builder's modules and
    /// products in the order it reports them, dynamic-library variants last, then any target it
    /// did not report, in the project's order.
    private static func documentOrder(of project: ProjectModel.Project, built: [PackagePIFBuilder.ModuleOrProduct]) -> [Int] {
        let index = Dictionary(project.targets.enumerated().map { ($1.common.id, $0) }, uniquingKeysWith: { first, _ in first })
        let reported = built.filter { !$0.isDynamicLibraryVariant } + built.filter(\.isDynamicLibraryVariant)
        var order: [Int] = []
        var seen: Set<Int> = []
        for position in reported.compactMap({ $0.pifTarget.flatMap { index[$0.common.id] } }) + Array(project.targets.indices) {
            if seen.insert(position).inserted { order.append(position) }
        }
        return order
    }

    // MARK: Source packages

    private func sourcePackages(of graph: ModulesGraph) -> [SourcePackage] {
        let pins = SourcePackage.pins(resolvedFile: references.resolvedFile) { PackageIdentity(url: SourceControlURL($0)).description }
        return graph.packages.sorted(by: { $0.identity.description < $1.identity.description }).map { package in
            let kind = package.manifest.packageKind
            let pin = kind.isRemote ? pins[package.identity.description] : nil
            return SourcePackage(
                name: package.manifest.displayName,
                identity: package.identity.description,
                location: pin?.location ?? package.manifest.packageLocation,
                // A local dependency (XCLocalSwiftPackageReference) is listed `@ local`, a root package without a pin.
                pin: kind.isRemote ? pin?.description : (kind.isRoot ? nil : "local"),
                contents: Self.contents(of: package))
        }
    }

    /// A package's schemeable products and targets. Targets are those its PIF project has: no
    /// binary targets, and in a dependency only the modules its products use (loader-experiments
    /// `package-target-kinds`: a scheme building only a binary target, or a dependency's unused
    /// plugin or target in no product, fails with 66; kickstarter: facebook-ios-sdk's
    /// `FBSDKCoreKit`). Test targets count for root packages only: Xcode loads none of a
    /// dependency's (`shouldCreateMultipleTestProducts` aside, their schemes fail as if the test
    /// target did not exist: icecubes, `RevenueCatUITests`).
    static func contents(of package: ResolvedPackage) -> SwiftPackageContents {
        let manifest = package.manifest
        // Plugin products, and the products SwiftPM makes for executable targets no product
        // names, have schemes too (loader-experiments `build-tool-plugin`: GenPlugin, GenTool).
        var products = manifest.products.filter { product in
            switch product.type {
            case .library, .executable, .plugin: return true
            default: return false
            }
        }.map { SwiftPackageContents.Product(name: $0.name, targets: $0.targets, isExecutable: $0.type == .executable) }
        let declared = Set(products.map(\.name))
        for product in package.products where product.type == .executable && !declared.contains(product.name) {
            products.append(SwiftPackageContents.Product(name: product.name, targets: product.modules.map(\.name), isExecutable: true))
        }
        let names = Set(manifest.targets.map(\.name))
        let tests = manifest.packageKind.isRoot ? manifest.targets.filter { $0.type == .test } : []
        return SwiftPackageContents(
            directory: package.path.pathString,
            isRoot: manifest.packageKind.isRoot,
            isLocal: !manifest.packageKind.isRemote,
            products: products,
            targets: package.modules.filter { $0.type != .test && $0.type != .binary }.map(\.name).sorted(),
            testTargets: tests.map { test in
                SwiftPackageContents.TestTarget(name: test.name, dependencies: test.dependencies.compactMap { dependency in
                    switch dependency {
                    case .target(let name, _): return name
                    case .byName(let name, _): return names.contains(name) ? name : nil
                    case .product: return nil
                    }
                })
            })
    }

    // MARK: Products

    /// The product each `XCSwiftPackageProductDependency` of the workspace names: in the
    /// package it names when it names a remote one that has it, otherwise in the first package
    /// (roots first) that has a product of that name (swiftfin: `PulseLogHandler`, named in the
    /// Pulse package, is the PulseLogHandler package's).
    private mutating func products(in graph: ModulesGraph) -> [String: PackageProjects.Product] {
        let packages = graph.rootPackages + graph.packages.filter { !$0.manifest.packageKind.isRoot }
        var products: [String: PackageProjects.Product] = [:]
        for project in workspace.allProjects {
            for dependency in Self.productDependencies(of: project) {
                var candidates = packages
                if let url = dependency.package?.repositoryURL {
                    let identity = PackageIdentity(url: SourceControlURL(url))
                    candidates = packages.filter { $0.identity == identity } + packages.filter { $0.identity != identity }
                }
                guard let product = candidates.lazy.compactMap({ package in
                    package.products.first { $0.name == dependency.productName && $0.type != .test }
                }).first else {
                    warnings.append("\(project.fileName): no package has the product \(dependency.productName) (\(dependency.uuid))")
                    continue
                }
                products[dependency.uuid] = PackageProjects.Product(guid: PackagePIFBuilder.targetGUID(of: product), name: product.name)
            }
        }
        return products
    }

    /// The project's `XCSwiftPackageProductDependency` objects: those targets list, those build
    /// files link or copy and those target dependencies name, each once.
    private static func productDependencies(of project: XcodeProject) -> [XCSwiftPackageProductDependency] {
        let all = project.project.targets.flatMap { $0.packageProductDependencies ?? [] } + project.pbxproj.buildFiles.compactMap(\.product)
            + project.pbxproj.targetDependencies.compactMap(\.product)
        var seen: Set<String> = []
        return all.filter { seen.insert($0.uuid).inserted }
    }
}

/// Diagnostics from SwiftPM, collected from concurrent callbacks.
private final class DiagnosticsCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [Basics.Diagnostic] = []

    func add(_ diagnostic: Basics.Diagnostic) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(diagnostic)
    }

    private func messages(_ severity: Basics.Diagnostic.Severity) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries.filter { $0.severity == severity }.map { diagnostic in
            if let package = diagnostic.metadata?.packageIdentity { return "\(package): \(diagnostic.message)" }
            return diagnostic.message
        }
    }

    var errors: [String] { messages(.error) }
    var warnings: [String] { messages(.warning) }
}

extension PIFValue {
    /// The JSON a SwiftBuild PIF model object encodes to, as a PIF value.
    init<T: Encodable>(encoding value: T) throws {
        let data = try JSONEncoder().encode(value)
        try self.init(json: JSONSerialization.jsonObject(with: data))
    }

    init(json: Any) throws {
        switch json {
        case let string as String: self = .string(string)
        case let array as [Any]: self = .array(try array.map(PIFValue.init(json:)))
        case let object as [String: Any]: self = .object(try object.mapValues(PIFValue.init(json:)))
        case let number as NSNumber: self = .int(number.intValue)
        default: throw NomacError("unexpected value in a package PIF object: \(json)")
        }
    }
}
