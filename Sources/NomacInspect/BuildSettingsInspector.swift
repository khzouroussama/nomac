import Foundation
import NomacBuildService
import NomacCore
import NomacPackages
import NomacPIF
import NomacProject
import NomacVerify

/// Computes `xcodebuild -showBuildSettings` output for a project or workspace.
///
/// The project is converted to PIF by ``PIFGenerator`` and loaded into Swift Build once;
/// each call to ``blocks(_:)`` then evaluates settings with
/// the same exported-settings computation Xcode uses. Only the invocation modes listed in
/// ``Selection`` are supported; each mirrors one way of calling `xcodebuild`. An inspector
/// exists only inside ``with(workspace:pif:developerDirectory:host:scratchDirectory:_:)``,
/// which releases its Swift Build session on every path.
public final class BuildSettingsInspector {
    /// Which targets to report, mirroring xcodebuild's command-line forms.
    public enum Selection: Sendable, Equatable {
        /// No `-target` or `-scheme`: the first target of the first project.
        case defaultTarget
        /// `-target <name>` (repeatable).
        case targets([String])
        /// `-alltargets`: every target of the first project, then its first target again.
        case allTargets
        /// `-scheme <name>`: the targets the scheme's build action builds for running.
        case scheme(String)
    }

    /// The xcodebuild action an invocation resolves for.
    public enum Action: Sendable, Equatable {
        /// `build` (and `-showBuildSettings`): the scheme's entries built for running.
        case build
        /// `archive`: the entries built for archiving, in the scheme's archive configuration,
        /// evaluated for Swift Build's `install` action (`build_experiments.py`, retro-rampage
        /// and tofu archived).
        case archive
        /// `build-for-testing` (and `test`): the entries built for testing, then the Test
        /// action's testables, in its configuration, with `build`'s settings
        /// (`xctest_experiments.py`: `-showBuildSettings` prints the same settings for both
        /// actions, coverage's included, and the testables after the app).
        case buildForTesting
    }

    /// Everything an xcodebuild invocation contributes to settings evaluation.
    public struct Invocation: Sendable, Equatable {
        public var selection: Selection
        public var configuration: String?
        /// The `-destination` specifier, if any.
        public var destination: String?
        /// The `-derivedDataPath` argument, if any.
        public var derivedDataPath: String?
        public var overrides: [String: String]
        public var action: Action
        /// A scheme to resolve in place of the one `selection` names: one of its
        /// ``XcodeScheme/alternatives``.
        public var alternative: XcodeScheme?

        public init(selection: Selection, configuration: String? = nil, destination: String? = nil, derivedDataPath: String? = nil,
                    overrides: [String: String] = [:], action: Action = .build, alternative: XcodeScheme? = nil) {
            self.alternative = alternative
            self.selection = selection
            self.configuration = configuration
            self.destination = destination
            self.derivedDataPath = derivedDataPath
            self.overrides = overrides
            self.action = action
        }
    }

    public let workspace: XcodeWorkspace
    /// Warnings from PIF generation (project content nomac could not represent exactly).
    public let warnings: [String]
    /// The packages of the workspace's resolved package graph.
    public let sourcePackages: [SourcePackage]
    package let session: WorkspaceSession
    private let targets: [WorkspaceTarget]
    /// The GUIDs of the targets each aggregate target depends on, by the aggregate's GUID.
    private let aggregateDependencies: [String: [String]]
    private let document: PIFDocument
    private let host: HostIdentity
    private var cachedSchemes: [XcodeScheme]?

    private init(workspace: XcodeWorkspace, pif: WorkspacePIF, session: WorkspaceSession, targets: [WorkspaceTarget], host: HostIdentity) {
        self.workspace = workspace
        self.warnings = pif.warnings
        self.sourcePackages = pif.sourcePackages
        self.session = session
        self.targets = targets
        self.host = host
        document = pif.document
        aggregateDependencies = Dictionary(pif.document.objects.compactMap { object -> (String, [String])? in
            guard object.type == "target", let contents = object.contents.objectValue, contents["type"]?.stringValue == "aggregate",
                  let guid = contents["guid"]?.stringValue else { return nil }
            return (guid, (contents["dependencies"]?.arrayValue ?? []).compactMap { $0.objectValue?["guid"]?.stringValue })
        }, uniquingKeysWith: { first, _ in first })
    }

    /// Generates the workspace's PIF, with its Swift packages, loads it into Swift Build and
    /// runs `body` with an inspector of it.
    /// - Parameter derivedDataPath: the `-derivedDataPath` argument, if given; packages are
    ///   checked out under it.
    public static func with<T>(workspace: XcodeWorkspace, developerDirectory: String, host: HostIdentity, scratchDirectory: String, derivedDataPath: String? = nil,
                               _ body: (BuildSettingsInspector) async throws -> T) async throws -> T {
        let pif = try await WorkspacePIF.generate(workspace: workspace, developerDirectory: developerDirectory, home: host.homeDirectory, derivedDataPath: derivedDataPath)
        return try await with(workspace: workspace, pif: pif, developerDirectory: developerDirectory, host: host, scratchDirectory: scratchDirectory, body)
    }

    /// Writes an already generated PIF into `scratchDirectory`, loads it into Swift Build and
    /// runs `body` with an inspector of it.
    public static func with<T>(workspace: XcodeWorkspace, pif: WorkspacePIF, developerDirectory: String, host: HostIdentity, scratchDirectory: String,
                               _ body: (BuildSettingsInspector) async throws -> T) async throws -> T {
        let pifPath = scratchDirectory + "/workspace-\(MD5.hex(workspace.path)).pif"
        try FileSystem.write(Data(pif.document.resolvingPathsOnDisk().serialized().utf8), to: pifPath)
        return try await SwiftBuildEngine.withWorkspace(developerDirectory: developerDirectory, pifPath: pifPath, host: host) { session in
            let inspector = BuildSettingsInspector(workspace: workspace, pif: pif, session: session, targets: try await session.targets(), host: host)
            return try await body(inspector)
        }
    }

    /// The workspace's schemes, with the target settings Xcode's autocreation rules read.
    public func schemes() async throws -> [XcodeScheme] {
        if let cachedSchemes { return cachedSchemes }
        let schemes = try workspace.schemes(packages: sourcePackages.map(\.contents), settings: try await evaluate(workspace.schemeSettingsQueries()),
                                            userName: host.userName)
        cachedSchemes = schemes
        return schemes
    }

    /// Every target of the workspace.
    public var workspaceTargets: [WorkspaceTarget] { targets }

    /// Evaluates each query as `xcodebuild -showBuildSettings -target -configuration` does, and
    /// the query's `expressions` for its target, each value under the expression's text.
    /// `-showBuildSettings -target` leaves a target whose `SDKROOT` is `auto` without a signing
    /// identity or an executable, so for such a target `CODE_SIGN_IDENTITY` is macOS's, which the
    /// PIF's provisioning style reads: `-` without a `DEVELOPMENT_TEAM` and `Apple Development`
    /// with one (loader-experiments `provisioning-auto`: style 1 without a team and 0 with one,
    /// whatever the supported platforms); and ``TargetSettingsQuery/platformExecutablePaths``
    /// holds its `EXECUTABLE_PATH` for iOS and for macOS, either of which a test bundle's
    /// `TEST_HOST` can name (`autocreate-auto-hosts`).
    public func evaluate(_ queries: Set<TargetSettingsQuery>, expressions: [TargetSettingsQuery: Set<String>] = [:]) async throws -> [TargetSettingsQuery: [String: String]] {
        var result: [TargetSettingsQuery: [String: String]] = [:]
        for query in queries {
            let guid = PIFIdentifiers.projectGUID(projectPath: query.projectPath, workspace: workspace) + MD5.hex(query.targetID)
            let request = SettingsRequest(configuration: query.configuration, synthesizedOverrides: MacHostSettings.overrides(host: host))
            var settings = try await session.exportedBuildSettings(targetGUID: guid, request: request)
            for expression in expressions[query] ?? [] {
                settings[expression] = try await session.evaluate(expression, targetGUID: guid, request: request)
            }
            if settings["SDKROOT"] == "auto" {
                var iOS = request, macOS = request
                iOS.overrides["SDKROOT"] = "iphoneos"
                macOS.overrides["SDKROOT"] = "macosx"
                settings["CODE_SIGN_IDENTITY"] = try await session.evaluate("$(CODE_SIGN_IDENTITY)", targetGUID: guid, request: macOS)
                var paths: [String] = []
                for platform in [iOS, macOS] {
                    paths.append(try await session.evaluate("$(EXECUTABLE_PATH)", targetGUID: guid, request: platform))
                }
                settings[TargetSettingsQuery.platformExecutablePaths] = paths.joined(separator: "\n")
            }
            result[query] = settings
        }
        return result
    }

    /// Computes one settings block per selected target, in the order xcodebuild prints them.
    ///
    /// Fails as xcodebuild fails, with its exit status: 65 for a scheme the workspace does not
    /// have, 66 for a scheme naming nothing the workspace contains, 64 when what the scheme
    /// launches, or else nothing it builds for running, supports the destination
    /// (loader-experiments `schemes`, `scheme-destinations`).
    public func blocks(_ invocation: Invocation) async throws -> [ShowBuildSettings.Block] {
        let resolution = try await resolve(invocation)
        var request = resolution.request
        request.synthesizedOverrides.merge(MacHostSettings.overrides(host: host)) { current, _ in current }
        var blocks: [ShowBuildSettings.Block] = []
        var evaluated: [String: [String: String]] = [:]
        for target in resolution.targets {
            let settings = try await session.exportedBuildSettings(targetGUID: target.guid, request: request)
            evaluated[target.guid] = settings
            blocks.append(ShowBuildSettings.Block(action: request.action, target: target.name, settings: settings))
        }
        // The destination must suit what the scheme launches, else something it builds for
        // running: a package product (packages support every platform) or a target that supports
        // it. A macOS target in a scheme with an iOS target is still reported (loader-experiments
        // `schemes`: Both); netnewswire's macOS-only scheme fails; `scheme-destinations`:
        // LaunchTool, which builds an iOS bundle and launches a macOS tool, fails.
        if case .scheme = invocation.selection, let specifier = invocation.destination, let destination = request.destination {
            var own = request
            own.destination = nil
            own.configuration = resolution.scheme?.launchConfiguration ?? request.configuration
            let check = DestinationCheck(request: request, ownPlatformRequest: own)
            var visited: Set<String> = []
            var supported = resolution.launchesPackageProduct
            if let launched = resolution.launchedTarget {
                supported = try await supports(launched.guid, destination.platform, check: check, evaluated: &evaluated, visited: &visited)
            } else if !supported {
                supported = resolution.runsPackageProducts
                for target in resolution.targets where !supported {
                    supported = try await supports(target.guid, destination.platform, check: check, evaluated: &evaluated, visited: &visited)
                }
            }
            guard supported else {
                throw NomacError("Could not configure request to show build settings: Unable to find a destination matching the provided destination specifier:\n\t\t\(DestinationSpecifier.describe(specifier))",
                                 exitStatus: 64)
            }
        }
        return blocks
    }

    /// The targets an invocation selects and the request their settings are evaluated with.
    public struct Resolution: Sendable {
        public var targets: [WorkspaceTarget]
        public var request: SettingsRequest
        /// Whether the scheme also builds a Swift package product for running.
        public var runsPackageProducts: Bool
        /// The targets a build of the invocation configures: as ``targets``, with the package
        /// products a scheme builds for running.
        public var buildTargets: [WorkspaceTarget]
        /// Package entries the scheme builds for running that have no product target in the PIF
        /// (a package target that is not a product): what xcodebuild configures for them has not
        /// been observed (B-104).
        public var unconfiguredPackageEntries: [String]
        /// What the scheme's Launch action runs, when that is a target of the workspace.
        public var launchedTarget: WorkspaceTarget?
        /// Whether the scheme's Launch action runs a Swift package product.
        public var launchesPackageProduct = false
        /// The scheme the invocation builds.
        public var scheme: XcodeScheme?
    }

    /// The workspace's target a scheme entry names, when it is one (not a package's).
    public func target(for entry: XcodeScheme.BuildEntry) -> WorkspaceTarget? {
        if case .target(let target)? = resolve(entry) { return target }
        return nil
    }

    /// Resolves an invocation as xcodebuild does, failing with its messages and exit statuses.
    public func resolve(_ invocation: Invocation) async throws -> Resolution {
        var chosen: [WorkspaceTarget]
        var configuration = invocation.configuration
        var locations: BuildLocations?
        var synthesized: [String: String] = [:]
        var runsPackageProducts = false
        var launched: Buildable?
        var buildTargets: [WorkspaceTarget] = []
        var unconfiguredPackageEntries: [String] = []
        var selectedScheme: XcodeScheme?
        if case .scheme(let name) = invocation.selection {
            let named = try XcodeWorkspace.scheme(named: name, in: try await schemes(), workspace: workspace)
            let scheme = invocation.alternative ?? named
            selectedScheme = scheme
            let entries = scheme.buildEntries.map { ($0, resolve($0)) }
            // A skipped testable is enough (loader-experiments `own-test-schemes-more`: SkipScheme,
            // which only skips its testables, fails with 64, not 66).
            let tested = scheme.testables + scheme.skippedTestables + scheme.testPlanTestables
            guard entries.contains(where: { $0.1 != nil }) || tested.contains(where: { resolve($0) != nil }) else {
                throw NomacError("Scheme \(name) is not currently configured for the build action.", exitStatus: 66)
            }
            let purpose = switch invocation.action {
            case .build: "running"
            case .archive: "archiving"
            case .buildForTesting: "testing"
            }
            var running = entries.filter { $0.0.buildFor.contains(purpose) }.compactMap(\.1)
            if invocation.action == .buildForTesting {
                running += (scheme.testables + scheme.testPlanTestables).compactMap(resolve)
            }
            // Package products are built but have no settings blocks of their own (icecubes'
            // package schemes print none; AppAndKit prints App only). A target several entries
            // build for running is reported once, where it first is (loader-experiments
            // `test-plan-entries`: S14 to S16).
            var reported = Set<String>()
            chosen = running.compactMap { if case .target(let target) = $0, reported.insert(target.guid).inserted { return target } else { return nil } }
            runsPackageProducts = running.contains { if case .package = $0 { return true } else { return false } }
            launched = scheme.launched.flatMap(resolve)
            // What a build configures: every target and package product the scheme builds for
            // running, in scheme order.
            var configured = Set<String>()
            for buildable in running {
                switch buildable {
                case .target(let target), .package(let target?, _):
                    if configured.insert(target.guid).inserted { buildTargets.append(target) }
                case .package(nil, let name):
                    unconfiguredPackageEntries.append(name)
                }
            }
            if invocation.action == .archive {
                guard let archiveConfiguration = configuration ?? scheme.archiveConfiguration else {
                    throw NomacError("nomac has not observed which configuration xcodebuild archives scheme \(name) with (an autocreated scheme of a package or a test bundle)")
                }
                configuration = archiveConfiguration
            } else {
                configuration = configuration ?? (invocation.action == .buildForTesting ? scheme.testConfiguration : scheme.launchConfiguration)
            }
            let container = DerivedData.containerPath(of: workspace)
            let user = UserBuildLocations(workspacePath: workspace.path, userName: host.userName)
            let arena = DerivedData.locations(name: workspace.name, containerPath: container, home: host.homeDirectory, customRoot: invocation.derivedDataPath, user: user)
            // A project opened alone that assigns SYMROOT builds products, intermediates and
            // precompiled headers in its own locations, its caches still under DerivedData
            // (XcodeProject.assignsSymroot; loader-experiments `symroot-project-*`: SYMROOT, OBJROOT
            // and SHARED_PRECOMPS_DIR are the project's, MODULE_CACHE_DIR and SDK_STAT_CACHE_DIR
            // DerivedData's, or -derivedDataPath's: `-derived`). Only the opened project's
            // assignments count, and they apply to the projects it references too
            // (`symroot-references-sub`, `-top`).
            let ownLocations = user.usesTargetSettings || (workspace.isImplicit && workspace.projects.first?.assignsSymroot == true)
            locations = ownLocations ? BuildLocations(derivedDataPath: arena.derivedDataPath, buildProductsPath: "", buildIntermediatesPath: "",
                                                      pchPath: "", indexPCHPath: "") : arena
            // A scheme that gathers code coverage makes xcodebuild synthesize these two settings
            // for every target it builds (observed: tofu; cwa; loader-experiments `coverage`).
            if scheme.codeCoverageEnabled, invocation.action != .archive {
                synthesized["CLANG_COVERAGE_MAPPING"] = "YES"
                synthesized["CLANG_PROFILE_DATA_DIRECTORY"] = (arena.buildProductsPath as NSString).deletingLastPathComponent + "/ProfileData"
            }
        } else {
            guard invocation.action == .build else {
                throw NomacError(invocation.action == .archive ? "archiving needs a scheme (-scheme)" : "building for testing needs a scheme (-scheme)")
            }
            // A workspace needs a scheme (loader-experiments `workspace`: without one, with
            // -target and with -alltargets, xcodebuild fails with 64 and these messages).
            if !workspace.isImplicit {
                let message = "If you specify a workspace then you must also specify a scheme.  Use -list to see the schemes in this workspace."
                switch invocation.selection {
                case .targets: throw NomacError("You cannot specify targets with a workspace.\n" + message, exitStatus: 64)
                case .allTargets: throw NomacError("You cannot specify -alltargets with a workspace.\n" + message, exitStatus: 64)
                default: throw NomacError(message, exitStatus: 64)
                }
            }
            chosen = try select(invocation.selection)
            buildTargets = chosen
            if unknownConfiguration(invocation) != nil {
                configuration = nil
            }
            if let custom = invocation.derivedDataPath {
                locations = DerivedData.locations(name: workspace.name, containerPath: workspace.path, home: host.homeDirectory, customRoot: custom)
            }
        }
        let destination = try invocation.destination.map(DestinationSpecifier.parse)
        let request = SettingsRequest(action: invocation.action == .archive ? "install" : "build", configuration: configuration, destination: destination, locations: locations, overrides: invocation.overrides, synthesizedOverrides: synthesized)
        var launchedTarget: WorkspaceTarget?
        if case .target(let target)? = launched {
            launchedTarget = target
        }
        var launchesPackageProduct = false
        if case .package? = launched {
            launchesPackageProduct = true
        }
        return Resolution(targets: chosen, request: request, runsPackageProducts: runsPackageProducts, buildTargets: buildTargets,
                          unconfiguredPackageEntries: unconfiguredPackageEntries, launchedTarget: launchedTarget,
                          launchesPackageProduct: launchesPackageProduct, scheme: selectedScheme)
    }

    /// The requests a destination check evaluates targets with: the invocation's, and the one
    /// that keeps a target's own SDK (no destination, the scheme's launch configuration).
    private struct DestinationCheck {
        var request: SettingsRequest
        var ownPlatformRequest: SettingsRequest
    }

    /// Whether the target `guid` supports `platform`. A target whose own SDK, in the scheme's
    /// launch configuration, is a simulator's supports that simulator only, whatever its
    /// SUPPORTED_PLATFORMS (loader-experiments `simulator-sdks`: SimIOS, SimIOSBoth,
    /// SimIOSDeviceOnly, PerConfigSimDebug, also with `-configuration Release`, fail with an iOS
    /// destination; PerConfigSimRelease and LaunchRelease do not). Xcode reads that SDK from the
    /// target's levels itself, with other conditions than Swift Build applies
    /// (``PIFDocument/SettingLevel``, `simulator-sdk-conditions`; BACKLOG B-089).
    /// Otherwise its SUPPORTED_PLATFORMS has it, or, for an aggregate target, a target it depends
    /// on supports it (loader-experiments `scheme-destinations`: AggDepIOS and AggDeep, macOS
    /// aggregates depending on an iOS framework directly or through another aggregate, accept iOS;
    /// MacFwDepIOS, a macOS framework depending on one, does not).
    private func supports(_ guid: String, _ platform: String, check: DestinationCheck, evaluated: inout [String: [String: String]],
                          visited: inout Set<String>) async throws -> Bool {
        guard visited.insert(guid).inserted, targets.contains(where: { $0.guid == guid }) else { return false }
        let own = try await session.exportedBuildSettings(targetGUID: guid, request: check.ownPlatformRequest)
        let configuration = own["CONFIGURATION"] ?? ""
        let read = document.settingLevels(target: guid, configuration: configuration)
            .xcodeValue("SDKROOT", sdk: own["SDK_NAME"] ?? "", configuration: configuration, evaluated: own)
        if let ownPlatform = read.map(Self.sdkName) ?? own["PLATFORM_NAME"], ownPlatform.hasSuffix("simulator") {
            return ownPlatform == platform
        }
        let request = check.request
        let settings: [String: String]
        if let known = evaluated[guid] {
            settings = known
        } else {
            settings = try await session.exportedBuildSettings(targetGUID: guid, request: request)
            evaluated[guid] = settings
        }
        if (settings["SUPPORTED_PLATFORMS"] ?? "").split(separator: " ").contains(Substring(platform)) {
            return true
        }
        for dependency in aggregateDependencies[guid] ?? [] {
            if try await supports(dependency, platform, check: check, evaluated: &evaluated, visited: &visited) {
                return true
            }
        }
        return false
    }

    /// The SDK an `SDKROOT` value names, without its version: `iphonesimulator` for
    /// `iphonesimulator`, `iphonesimulator27.0` and a path ending in `iPhoneSimulator27.0.sdk`.
    static func sdkName(_ sdkroot: String) -> String {
        var name = ((sdkroot as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()
        while let last = name.last, last.isNumber || last == "." { name.removeLast() }
        return name
    }

    /// The `-configuration` of an invocation without a scheme that the opened project lacks.
    /// xcodebuild compares the names byte for byte, warns and uses the default configuration
    /// (loader-experiments `unicode-nfc`: `Bêta` written in the other form; `Nonexistent`); with
    /// a scheme, the name goes to Swift Build, which compares canonically equivalent names equal.
    public func unknownConfiguration(_ invocation: Invocation) -> String? {
        if case .scheme = invocation.selection { return nil }
        guard let name = invocation.configuration, let project = workspace.projects.first else { return nil }
        let names = project.project.buildConfigurationList?.buildConfigurations.map(\.name) ?? []
        return names.contains { $0.isIdentical(to: name) } ? nil : name
    }

    /// What a scheme's entry names, if the workspace has it.
    private enum Buildable {
        case target(WorkspaceTarget)
        /// A product or target of one of the workspace's Swift packages, with the PIF target
        /// a build configures for it when it is a product.
        case package(WorkspaceTarget?, name: String)
    }

    private func resolve(_ entry: XcodeScheme.BuildEntry) -> Buildable? {
        if entry.isInPackage {
            let directory = (entry.containerPath as NSString).standardizingPath
            guard let package = sourcePackages.first(where: { ($0.contents.directory as NSString).standardizingPath == directory && $0.contents.contains(entry.targetID) }) else {
                return nil
            }
            // A product's PIF target (SwiftPM's builder: `PACKAGE-PRODUCT:<identity>_<product>.<product>`),
            // which xcodebuild configures for icecubes' `Models` scheme (its build-request.json).
            let guid = "PACKAGE-PRODUCT:\(package.identity)_\(entry.targetID).\(entry.targetID)"
            let isProduct = package.contents.products.contains { $0.name == entry.targetID }
            return .package(isProduct ? targets.first { $0.guid == guid } : nil, name: entry.targetID)
        }
        let guid = PIFIdentifiers.projectGUID(projectPath: entry.containerPath, workspace: workspace) + MD5.hex(entry.targetID)
        return targets.first(where: { $0.guid == guid }).map(Buildable.target)
    }

    private func select(_ selection: Selection) throws -> [WorkspaceTarget] {
        // Targets of the first project, in project order: what `xcodebuild -project` sees, not
        // those of the projects it references (loader-experiments `project-references`).
        let firstProject = workspace.projects.first
        let projectGUID = firstProject.map { PIFIdentifiers.projectGUID(projectPath: $0.path, workspace: workspace) }
        let projectTargets = targets.filter { projectGUID.map($0.guid.hasPrefix) ?? false }
        switch selection {
        case .defaultTarget:
            guard let first = projectTargets.first else {
                throw NomacError("the project has no targets", path: firstProject?.path)
            }
            return [first]
        case .allTargets:
            // xcodebuild prints the first target once more after all of them (loader-experiments:
            // settings App, App; targets App, Agg, Legacy, App; target-names, 34 targets and Plain).
            return projectTargets + projectTargets.prefix(1)
        case .scheme:
            return []
        case .targets(let names):
            return try names.map { name in
                guard let target = projectTargets.first(where: { $0.name.isIdentical(to: name) }) else {
                    throw NomacError("The project '\(firstProject?.path ?? "")' does not contain a target named '\(name)'.", exitStatus: 65)
                }
                return target
            }
        }
    }
}
