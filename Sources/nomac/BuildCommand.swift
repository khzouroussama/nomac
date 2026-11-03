import ArgumentParser
import Foundation
import NomacBuild
import NomacBuildService
import NomacCore
import NomacDeviceTest
import NomacInspect
import NomacMacros
import NomacPackages
import NomacPIF
import NomacPackaging
import NomacProject
import NomacSDK
import NomacSigning

/// `nomac build`: build a project's targets or scheme with Swift Build, as `xcodebuild build` does.
struct BuildCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build a scheme or target, as 'xcodebuild build'.",
        discussion: """
        Accepts xcodebuild's spelling of the options (-project, -workspace, -target, -scheme, \
        -configuration, -destination, -derivedDataPath). Trailing KEY=VALUE arguments override \
        build settings; a trailing 'build' action is accepted. The developer directory needs a \
        toolchain ('nomac toolchain install') to build on Linux.

        Example:
          nomac build -project App.xcodeproj -scheme App -configuration Release \\
              -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO
        """
    )

    @OptionGroup var options: BuildOptions

    func run() async throws {
        try await options.run(archivePath: nil)
    }
}

/// What `nomac build` and `nomac archive` take, in xcodebuild's spelling.
struct BuildOptions: ParsableArguments {
    @Option(name: [.customLong("project", withSingleDash: true), .customLong("project")], help: "The .xcodeproj to load.")
    var project: String?

    @Option(name: [.customLong("workspace", withSingleDash: true), .customLong("workspace")], help: "The .xcworkspace to load.")
    var workspace: String?

    @Option(name: [.customLong("target", withSingleDash: true), .customLong("target")], help: "A target to build (repeatable).")
    var targets: [String] = []

    @Option(name: [.customLong("scheme", withSingleDash: true), .customLong("scheme")], help: "Build the targets the scheme builds for running.")
    var scheme: String?

    @Option(name: [.customLong("destination", withSingleDash: true), .customLong("destination")], help: "The run destination; nomac supports 'generic/platform=iOS'.")
    var destination: String?

    @Option(name: [.customLong("derivedDataPath", withSingleDash: true), .customLong("derived-data-path")], help: "The build location root, as for xcodebuild.")
    var derivedDataPath: String?

    @Option(name: [.customLong("configuration", withSingleDash: true), .customLong("configuration")], help: "The build configuration.")
    var configuration: String?

    @Option(name: [.customLong("developer-dir")], help: "An Xcode Contents/Developer directory (default: $NOMAC_DEVELOPER_DIR, else the selected 'nomac sdk' install).")
    var developerDir: String?
    @Flag(name: .customLong("strict-xcode"), help: XcodeCheck.strictHelp)
    var strictXcode = false

    @Option(name: [.customLong("host-identity")], help: "A reference host.json whose user, machine and environment Swift Build should see (default: this user and machine, off macOS on the reference Mac of nomac's Xcode, ADR 0012).")
    var hostIdentity: String?

    @Option(name: .customLong("IDEBuildingContinueBuildingAfterErrors", withSingleDash: true),
            help: "YES to run the tasks that do not depend on a failed one, as xcodebuild's user default does.")
    var continueBuildingAfterErrors: String?

    @Flag(name: .customLong("case-aliases"),
          help: "On a case-sensitive file system, link the paths the project spells in another case than the disk into the checkout for the build's duration, so debug paths keep the project's spelling (BACKLOG B-062).")
    var caseAliases = false

    @Flag(name: .customLong("skipMacroValidation", withSingleDash: true), help: "Approve the macros of remote packages, as xcodebuild's option does.")
    var skipMacroValidation = false

    @Option(name: .customLong("sdk", withSingleDash: true), help: "The SDK, as xcodebuild's option: SDKROOT set to its canonical name.")
    var sdk: String?

    @Flag(name: .customLong("quiet", withSingleDash: true), help: "Print only diagnostics, as xcodebuild's option does.")
    var quiet = false

    @Flag(name: .customLong("parallelizeTargets", withSingleDash: true), help: "Build independent targets in parallel, which nomac's builds always do.")
    var parallelizeTargets = false

    @Flag(name: .customLong("disableAutomaticPackageResolution", withSingleDash: true),
          help: "Accepted as xcodebuild's option; nomac resolves packages from their Package.resolved when it has one.")
    var disableAutomaticPackageResolution = false

    @Flag(name: .customLong("skipPackagePluginValidation", withSingleDash: true), help: "Accepted as xcodebuild's option; nomac runs no package plugins (B-009).")
    var skipPackagePluginValidation = false

    @Option(help: "A PEM file with the private key and certificates of the identity CODE_SIGN_IDENTITY names, to sign with a certificate (CODE_SIGN_STYLE=Manual).")
    var keychain: String?

    @Option(name: .customLong("provisioning-profiles"), help: "A folder of .mobileprovision files for PROVISIONING_PROFILE_SPECIFIER (default: Xcode's folders under the home folder).")
    var provisioningProfiles: String?

    @Argument(help: "Build setting overrides, KEY=VALUE, and optionally the action ('build', 'build-for-testing' or 'archive').")
    var arguments: [String] = []

    /// Builds, or with `archivePath` archives as `xcodebuild archive` does: the scheme's install
    /// build into `ArchiveIntermediates/<scheme>`, then the archive (`nomac xcarchive`).
    func run(archivePath: String?) async throws {
        let forTesting = archivePath == nil && arguments.contains("build-for-testing")
        let action = archivePath != nil ? "archive" : forTesting ? "build-for-testing" : "build"
        let verb = archivePath != nil ? "ARCHIVE" : forTesting ? "TEST BUILD" : "BUILD"
        let container = try Container.path(project: project, workspace: workspace)
        let loaded = try await Container.load(container)
        let developer = try DeveloperDirectory.resolve(option: developerDir, strictXcode: strictXcode)
        #if !os(macOS)
        try LinuxToolchain.checkClangConfiguration(developerDirectory: developer)
        let scriptShell = ScriptShell.installed(developerDirectory: developer)
        if scriptShell == nil, let warning = ScriptShell.warning() {
            FileHandle.standardError.write(Data("warning: \(warning)\n".utf8))
        }
        #else
        let scriptShell: String? = nil
        #endif
        let host = try hostIdentity.map { try ReferenceHost.load(path: FileSystem.absolute($0)).identity(developerDirectory: developer) } ?? .default()
        #if !os(macOS)
        try HostTemporaryDirectory.prepare(host)
        #endif
        var overrides: [String: String] = [:]
        for item in arguments where item != action {
            guard let equals = item.firstIndex(of: "=") else {
                throw NomacError("expected a build setting override of the form KEY=VALUE or the action '\(action)', got '\(item)'")
            }
            overrides[String(item[..<equals])] = String(item[item.index(after: equals)...])
        }
        let continueAfterErrors: Bool
        switch continueBuildingAfterErrors {
        case nil, "NO": continueAfterErrors = false
        case "YES": continueAfterErrors = true
        case let value?: throw NomacError("-IDEBuildingContinueBuildingAfterErrors takes YES or NO, got '\(value)'")
        }
        let selection: BuildSettingsInspector.Selection
        if let scheme {
            guard targets.isEmpty else { throw NomacError("-scheme cannot be combined with -target") }
            selection = .scheme(scheme)
        } else {
            selection = targets.isEmpty ? .defaultTarget : .targets(targets)
        }
        let locations = DerivedData.locations(name: loaded.name, containerPath: DerivedData.containerPath(of: loaded), home: host.homeDirectory,
                                              customRoot: derivedDataPath.map(FileSystem.xcodebuildSpelling))
        let quiet = self.quiet
        let pluginLog: @Sendable (String) -> Void = { text in
            if !quiet { FileHandle.standardOutput.write(Data(text.utf8)) }
        }
        let plugins = BuildToolPluginStep.plugins(buildProducts: locations.buildProductsPath, intermediates: locations.buildIntermediatesPath,
                                                  developerDirectory: developer, log: pluginLog)
        var pif: WorkspacePIF
        do {
            pif = try await WorkspacePIF.generate(workspace: loaded, developerDirectory: developer, home: host.homeDirectory,
                                                  derivedDataPath: derivedDataPath.map(FileSystem.xcodebuildSpelling), skipsMacroValidation: skipMacroValidation,
                                                  buildToolPlugins: plugins)
        } catch let failure as BuildToolPluginFailure {
            let schemeAction = scheme.map {
                BuildOperation.schemeAction(archive: archivePath != nil, testing: forTesting, container: loaded.isImplicit ? "project" : "workspace",
                                            name: loaded.name, scheme: $0, configuration: nil)
            }
            FileHandle.standardError.write(Data(("** \(verb) FAILED **\n\n"
                + (BuildOperation.failureSummary(failedTasks: failure.failedCommands, schemeAction: schemeAction) ?? "")).utf8))
            throw ExitCode(65)
        }
        pif.document = BuildToolPluginPhases.adding(pif.projectPluginCommands, to: pif.document, fileTypes: try? FileTypeRegistry.installed())
        if let scriptShell {
            pif.document = ScriptShell.redirecting(pif.document, to: scriptShell)
        }
        var aliases = CaseAliases(paths: pif.document.fileReferencePaths())
        if caseAliases {
            try aliases.make()
        } else if !aliases.links.isEmpty {
            let count = aliases.links.count == 1 ? "1 folder or file" : "\(aliases.links.count) folders or files"
            FileHandle.standardError.write(Data(("warning: the project names \(count) in another case than the disk, which the build uses as the disk "
                + "spells it, and so do debug information and .swiftsourceinfo files (BACKLOG B-062); --case-aliases keeps the project's\n").utf8))
        }
        defer { aliases.remove() }
        let log: (String) -> Void = quiet ? { _ in } : write
        let (outcome, resolution, actions, actionFailures, testBuild) = try await BuildSettingsInspector.with(
            workspace: loaded,
            pif: pif,
            developerDirectory: developer,
            host: host,
            scratchDirectory: SDKStore.default().root + "/scratch"
        ) { inspector -> (BuildOperation.Outcome?, BuildSettingsInspector.Resolution, BuildSchemeActions, [String], (TestBuildDescription, String)?) in
            for warning in inspector.warnings {
                FileHandle.standardError.write(Data("warning: \(warning)\n".utf8))
            }
            if !quiet {
                write("Command line invocation:\n    \(CommandLine.arguments.joined(separator: " "))\n\n")
            }
            let resolution = try await inspector.resolve(BuildSettingsInspector.Invocation(
                selection: selection,
                configuration: configuration,
                destination: destination,
                derivedDataPath: derivedDataPath.map(FileSystem.xcodebuildSpelling),
                overrides: overrides,
                action: archivePath != nil ? .archive : forTesting ? .buildForTesting : .build))
            if forTesting, let scheme = resolution.scheme { try TestBuildSettings.check(scheme) }
            var settings = resolution.request
            // xcodebuild sets SDKROOT to the canonical name of -sdk's SDK, and the TOOLCHAINS of
            // its environment as an override and the toolchain override (expo-default's nested
            // build of ExpoModulesJSI: `iphoneos27.0`, `com.apple.dt.toolchain.XcodeDefault`).
            if let sdk, let first = resolution.buildTargets.first {
                settings.overrides["SDKROOT"] = sdk
                settings.overrides["SDKROOT"] = try await inspector.session.evaluate("$(SDK_NAME)", targetGUID: first.guid, request: settings)
            }
            if let toolchains = ProcessInfo.processInfo.environment["TOOLCHAINS"], !toolchains.isEmpty {
                settings.overrides["TOOLCHAINS"] = toolchains
                settings.toolchainOverride = toolchains
            }
            #if !os(macOS)
            settings.synthesizedOverrides.merge(MacHostSettings.buildOverrides(host: host)) { current, _ in current }
            settings.synthesizedOverrides.merge(LinuxSigning.overrides) { current, _ in current }
            settings.synthesizedOverrides.merge(InstallAttributes.overrides(developerDirectory: developer)) { current, _ in current }
            settings.synthesizedOverrides.merge(TaskSandbox.overrides) { current, _ in current }
            LinuxCompiler.apply(to: &settings.overrides, synthesized: &settings.synthesizedOverrides)
            let stale = try MacroPlugins.missing(developerDirectory: developer)
            if !stale.isEmpty {
                FileHandle.standardError.write(Data("warning: the developer directory has no macro plugins \(stale.joined(separator: ", ")), which this nomac provides: it was installed by an older nomac; run 'nomac toolchain install' again into a fresh 'nomac sdk install'\n".utf8))
            }
            let pluginFlags = try await macroPluginFlags(inspector: inspector, request: resolution.request)
            if !pluginFlags.isEmpty {
                if let commandLine = settings.overrides["OTHER_SWIFT_FLAGS"] {
                    settings.overrides["OTHER_SWIFT_FLAGS"] = pluginFlags + " " + commandLine
                } else {
                    settings.synthesizedOverrides["OTHER_SWIFT_FLAGS"] = pluginFlags + " " + (settings.synthesizedOverrides["OTHER_SWIFT_FLAGS"] ?? "$(inherited)")
                }
            }
            #endif
            if CaseInsensitiveOverlay.isCaseSensitive(FileSystem.absolute(container)) {
                try await addCaseInsensitiveOverlay(to: &settings, inspector: inspector, resolution: resolution, workspace: loaded, pif: pif.document,
                                                    sourcePackages: locations.derivedDataPath + "/SourcePackages")
            }
            guard resolution.unconfiguredPackageEntries.isEmpty else {
                throw NomacError("the scheme builds Swift package entries without a product target in the PIF (\(resolution.unconfiguredPackageEntries.joined(separator: ", "))), which nomac has not observed xcodebuild build (B-104)")
            }
            let signing = keychain.map {
                SigningMaterial(keychain: FileSystem.absolute($0),
                                profileFolders: provisioningProfiles.map { [FileSystem.absolute($0)] } ?? ProvisioningProfile.installedFolders)
            }
            #if os(macOS)
            // Apple's codesign takes keychains, not PEM files: sign through nomac's own.
            if signing != nil {
                settings.synthesizedOverrides["CODESIGN"] = try CodesignLink.create(in: SDKStore.default().root + "/scratch/bin")
            }
            #endif
            let actions = try await BuildSchemeActions(resolution: resolution, inspector: inspector, request: settings, developerDirectory: developer,
                                                       workspace: loaded, destination: destination, shell: scriptShell)
            var actionFailures = try actions.runner.run(actions.buildPre, heading: "Run pre-actions", log: log)
            guard actionFailures.isEmpty else { return (nil, resolution, actions, actionFailures, nil) }
            let outcome = try await BuildOperation.run(
                BuildOperation.Request(targets: resolution.buildTargets, settings: settings, containerPath: FileSystem.absolute(container),
                                       continueBuildingAfterErrors: continueAfterErrors, archivedScheme: archivePath == nil ? nil : scheme,
                                       signing: signing),
                session: inspector.session,
                quiet: quiet,
                log: write)
            if outcome.succeeded || actions.runsPostActionsOnFailure {
                actionFailures += try actions.runner.run(actions.buildPost, heading: "Run post-actions", log: log)
            }
            var testBuild: (TestBuildDescription, String)?
            if forTesting, outcome.succeeded, let scheme = resolution.scheme {
                testBuild = try await TestBuildSettings.describe(scheme: scheme, targets: resolution.buildTargets, inspector: inspector, request: settings,
                                                                 workspace: loaded)
            }
            return (outcome, resolution, actions, actionFailures, testBuild)
        }
        let succeeded = outcome?.succeeded == true && actionFailures.isEmpty
        if succeeded, let archivePath, let scheme, let intermediates = resolution.request.locations?.buildIntermediatesPath {
            _ = try actions.runner.run(actions.archivePre, heading: nil, log: log)
            try XCArchive.assemble(intermediates: BuildOperation.archiveIntermediates(buildIntermediatesPath: intermediates, scheme: scheme),
                                   archivePath: FileSystem.absolute(archivePath), schemeName: scheme, creationDate: Date())
            _ = try actions.runner.run(actions.archivePost, heading: nil, log: log)
        }
        if succeeded, let (description, folder) = testBuild {
            try FileSystem.write(XCTestRunWriter.data(description), to: folder + "/" + XCTestRunWriter.fileName(description))
        }
        guard !succeeded else {
            if !quiet { write("** \(verb) SUCCEEDED **\n\n") }
            return
        }
        // xcodebuild reports a failure on standard error (failure_experiments.py).
        var schemeAction: String?
        if outcome != nil, let scheme, let configuration = resolution.request.configuration {
            schemeAction = BuildOperation.schemeAction(archive: archivePath != nil, testing: forTesting, container: loaded.isImplicit ? "project" : "workspace",
                                                       name: loaded.name,
                                                       scheme: scheme, configuration: configuration)
        }
        FileHandle.standardError.write(Data(("** \(verb) FAILED **\n\n"
            + (BuildOperation.failureSummary(failedTasks: (outcome?.failedTasks ?? []) + actionFailures, schemeAction: schemeAction) ?? "")).utf8))
        throw ExitCode(65)
    }

    #if !os(macOS)
    /// The flags that load, for every Mach-O macro plugin a target's `OTHER_SWIFT_FLAGS` names, its
    /// build for this machine (``MacroPluginPackages``).
    private func macroPluginFlags(inspector: BuildSettingsInspector, request: SettingsRequest) async throws -> String {
        var plugins: [MacroPluginPackages.Plugin] = []
        for target in inspector.workspaceTargets {
            let flags = try await inspector.session.evaluateList("$(OTHER_SWIFT_FLAGS)", targetGUID: target.guid, request: request)
            guard flags.contains("-load-plugin-executable") else { continue }
            let directory = try await inspector.session.evaluate("$(PROJECT_DIR)", targetGUID: target.guid, request: request)
            plugins += MacroPluginPackages.machOPlugins(flags: flags, directory: directory)
        }
        guard !plugins.isEmpty else { return "" }
        let built = try await MacroPluginPackages.build(plugins, scratch: SDKStore.default().root + "/scratch/macro-plugins") { if !quiet { write($0) } }
        for warning in built.warnings {
            FileHandle.standardError.write(Data("warning: \(warning)\n".utf8))
        }
        return built.flags
    }
    #endif

    /// On a case-sensitive file system, a case-insensitive overlay of the source roots' headers
    /// and of the frameworks the build makes, for clang and the Swift compiler
    /// (`CaseInsensitiveOverlay`), before the project's own flags.
    private func addCaseInsensitiveOverlay(to settings: inout SettingsRequest, inspector: BuildSettingsInspector, resolution: BuildSettingsInspector.Resolution,
                                           workspace: XcodeWorkspace, pif: PIFDocument, sourcePackages: String) async throws {
        let projects = Set(workspace.allProjects.map(\.projectDirectory)).sorted()
        let roots = projects.filter { root in !projects.contains { $0 != root && root.hasPrefix($0 + "/") } } + [sourcePackages + "/checkouts"]
        var folders: [String] = []
        for target in resolution.buildTargets {
            let products = try await inspector.session.evaluate("$(BUILT_PRODUCTS_DIR)", targetGUID: target.guid, request: settings)
            for folder in [products, products + "/PackageFrameworks"] where !folders.contains(folder) { folders.append(folder) }
        }
        let frameworks = CaseInsensitiveOverlay.frameworkNames(document: pif, roots: roots + [sourcePackages + "/artifacts"])
        let overlay = SDKStore.default().root + "/scratch/case-insensitive-\(MD5.hex(workspace.path)).yaml"
        try FileSystem.write(try CaseInsensitiveOverlay.document(sourceRoots: roots, frameworks: frameworks, productFolders: folders), to: overlay)
        for (setting, flag) in [("OTHER_CFLAGS", "-ivfsoverlay"), ("OTHER_SWIFT_FLAGS", "-vfsoverlay")] {
            if let commandLine = settings.overrides[setting] {
                settings.overrides[setting] = "\(flag) \(overlay) " + commandLine
            } else {
                settings.synthesizedOverrides[setting] = "\(flag) \(overlay) " + (settings.synthesizedOverrides[setting] ?? "$(inherited)")
            }
        }
    }

    /// Every line of the build's output goes through one unbuffered path, so a redirected log
    /// keeps its order.
    private func write(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }
}
