import Basics
import Foundation
import NomacCore
import NomacPluginAPI
import NomacProject
@preconcurrency import PackageGraph
@_spi(SwiftPMInternal) @preconcurrency import PackageModel
import SPMBuildCore
import VendoredPackagePIFBuilder
import XcodeProj

/// Applies the build tool plugins of a workspace's package targets as xcodebuild does before it
/// hands the build to Swift Build (BACKLOG B-009; docs/formats/build.md "Build tool plugins"):
/// each plugin is compiled into `<products>/PluginExecutables`, run once per target that uses
/// it with its work directory `<intermediates>/BuildToolPluginIntermediates/<package>.output/
/// <target>/<plugin>`, and its build commands become the target's custom tasks in the PIF
/// (`build_plugin_experiments.py` buildCommand, Xcode 27.0).
public struct BuildToolPlugins: Sendable {
    /// `$(BUILD_DIR)`: the build's `Build/Products` folder.
    public var buildProducts: String
    /// `$(OBJROOT)`: the build's `Build/Intermediates.noindex` folder.
    public var intermediates: String
    /// The Swift compiler that compiles the plugins (Xcode's on a Mac); without one, the
    /// toolchain that evaluates the manifests, the build machine's.
    public var swiftCompiler: String?
    /// The folder holding `PluginAPI`, the `PackagePlugin` library the plugins link, when not the
    /// compiler's own (Xcode: `SharedFrameworks/SwiftPM.framework/SharedSupport`).
    public var pluginLibraries: String?
    /// Where the build puts the tools built from the packages' executable targets, as the
    /// plugins are told (Xcode: `/${BUILD_DIR}/${CONFIGURATION}`, the products of the macOS
    /// builds of those targets, written with a leading `/`).
    public var builtToolsDirectory: String
    /// Where off macOS nomac's `PackagePlugin` and `XcodeProjectPlugin` libraries are built for the
    /// plugins' compiler, which then link them (ADR 0105); without it, the compiler's own.
    public var pluginAPICache: String?
    /// The triple and SDK the plugins are compiled for, when not the compiler's host ones (Xcode:
    /// `arm64-apple-macos` and the macOS SDK, with no other search paths).
    public var pluginTarget: (triple: String, sdk: String)?
    /// Receives xcodebuild's log lines for the plugins.
    public var log: @Sendable (String) -> Void

    public init(buildProducts: String, intermediates: String, swiftCompiler: String?, pluginLibraries: String?, builtToolsDirectory: String,
                pluginTarget: (triple: String, sdk: String)?, pluginAPICache: String? = nil, log: @escaping @Sendable (String) -> Void) {
        self.pluginTarget = pluginTarget
        self.pluginAPICache = pluginAPICache
        self.buildProducts = buildProducts
        self.intermediates = intermediates
        self.swiftCompiler = swiftCompiler
        self.pluginLibraries = pluginLibraries
        self.builtToolsDirectory = builtToolsDirectory
        self.log = log
    }

    /// What applying the build tool plugins gives: results for the package targets, by package
    /// and target name, and commands for the targets of Xcode projects.
    struct Applied {
        var packageResults: [PackageIdentity: [String: [PackagePIFBuilder.BuildToolPluginInvocationResult]]] = [:]
        var projectCommands: [ProjectPluginCommands] = []
    }

    /// Applies the build tool plugins of `graph`'s package targets and of `projects`' targets, in
    /// the order each target lists them. As xcodebuild does, each plugin is compiled first
    /// ("Compile plug-in"), then applied to each target in turn ("Apply build tool plug-in"), and
    /// the results are processed.
    func apply(to graph: ModulesGraph, projects: [XcodeProject]) async throws -> Applied {
        let pluginsPerModule = graph.pluginsPerModule(satisfying: Self.environment)
        let projectTargets = try Self.pluginTargets(of: projects, in: graph)
        guard !pluginsPerModule.isEmpty || !projectTargets.isEmpty else { return Applied() }
        let (runner, hostTriple, compilerDirectory) = try scriptRunner()
        let silent = ObservabilitySystem { _, _ in }
        let packagesByModule = Dictionary(graph.packages.flatMap { package in package.modules.map { ($0.id, package) } }, uniquingKeysWith: { first, _ in first })
        var compiled = Set<ResolvedModule.ID>()
        for plugin in pluginsPerModule.values.flatMap({ $0 }) + projectTargets.flatMap(\.plugins) where compiled.insert(plugin.id).inserted {
            try await compile(plugin, in: packagesByModule[plugin.id], runner: runner)
        }
        var applied = Applied()
        for package in graph.packages.sorted(by: { $0.identity.description < $1.identity.description }) {
            for module in package.modules.sorted(by: { $0.name < $1.name }) {
                guard let plugins = pluginsPerModule[module.id] else { continue }
                var generated: [Basics.AbsolutePath] = []
                for plugin in plugins {
                    let result = try await apply(plugin, to: module, in: package, graph: graph, generated: generated, runner: runner, hostTriple: hostTriple,
                                                 toolSearchDirectory: compilerDirectory, observability: silent)
                    generated += result.allDerivedOutputPaths
                    applied.packageResults[package.identity, default: [:]][module.name, default: []].append(result)
                }
            }
        }
        for (project, target, plugins) in projectTargets {
            let representation = try Self.representation(of: project)
            var commands: [ProjectPluginCommands.Command] = []
            for plugin in plugins {
                commands += try await apply(plugin, to: target, of: project, representation: representation, graph: graph,
                                            generated: commands.flatMap(\.outputFiles), runner: runner, hostTriple: hostTriple,
                                            toolSearchDirectory: compilerDirectory, observability: silent)
            }
            applied.projectCommands.append(ProjectPluginCommands(projectPath: project.path, targetName: target.name, commands: commands))
        }
        log("Process build tool plug-in results\n\n")
        return applied
    }

    private func compile(_ plugin: ResolvedModule, in package: ResolvedPackage?, runner: DefaultPluginScriptRunner) async throws {
        guard let module = plugin.underlying as? PluginModule else { return }
        let log = self.log
        log("Compile plug-in “\(plugin.name)” in package “\(package?.identity.description ?? "")”\n")
        let observability = ObservabilitySystem { _, diagnostic in
            if diagnostic.severity == .debug { log("[debug]: \(diagnostic.message)\n") }
        }
        let (succeeded, output): (Bool, String) = try await withCheckedThrowingContinuation { continuation in
            runner.compilePluginScript(sourceFiles: module.sources.paths, pluginName: module.name, toolsVersion: module.apiVersion,
                                       workers: UInt32(ProcessInfo.processInfo.activeProcessorCount), observabilityScope: observability.topScope,
                                       callbackQueue: DispatchQueue(label: "nomac.plugin"), delegate: CompilerDelegate()) { result in
                continuation.resume(with: result.map { ($0.succeeded, $0.rawCompilerOutput) })
            }
        }
        guard succeeded else {
            throw NomacError("cannot compile the build tool plug-in “\(plugin.name)”", notes: output.split(whereSeparator: \.isNewline).map(String.init))
        }
        log("\n\n")
    }

    private func apply(_ plugin: ResolvedModule, to module: ResolvedModule, in package: ResolvedPackage, graph: ModulesGraph, generated: [Basics.AbsolutePath],
                       runner: DefaultPluginScriptRunner, hostTriple: Triple, toolSearchDirectory: Basics.AbsolutePath,
                       observability: ObservabilitySystem) async throws -> PackagePIFBuilder.BuildToolPluginInvocationResult {
        guard let pluginModule = plugin.underlying as? PluginModule else { return .init(prebuildCommandOutputPaths: [], buildCommands: []) }
        let identity = package.identity.description
        let workDirectory = try Basics.AbsolutePath(validating: intermediates).appending(
            components: "BuildToolPluginIntermediates", identity + ".output", module.name, plugin.name)
        let tools = try await plugin.preparePluginTools(fileSystem: localFileSystem, environment: Self.environment, for: hostTriple) { name, _ in
            try Basics.AbsolutePath(validating: builtToolsDirectory + "/" + name)
        }
        let application = "Apply build tool plug-in “\(plugin.name)” to target “\(module.name)” in package “\(identity)”"
        log(application + "\n")
        let collector = CommandCollector()
        let succeeded = try await pluginModule.invoke(
            action: .createBuildToolCommands(package: package, target: module, pluginGeneratedSources: generated, pluginGeneratedResources: []),
            buildEnvironment: Self.environment, workers: UInt32(ProcessInfo.processInfo.activeProcessorCount), scriptRunner: runner,
            workingDirectory: package.path, outputDirectory: workDirectory,
            toolSearchDirectories: [toolSearchDirectory],
            accessibleTools: tools, writableDirectories: [workDirectory], readOnlyDirectories: [package.path],
            allowNetworkConnections: [], pkgConfigDirectories: [], sdkRootPath: nil, fileSystem: localFileSystem,
            modulesGraph: graph, observabilityScope: observability.topScope, callbackQueue: DispatchQueue(label: "nomac.plugin"), delegate: collector)
        guard succeeded, collector.errors.isEmpty else {
            throw NomacError("the build tool plug-in “\(plugin.name)” failed for target “\(module.name)” in package “\(identity)”",
                             notes: collector.errors + collector.output.split(whereSeparator: \.isNewline).map(String.init))
        }
        if let prebuild = collector.prebuildCommands.first {
            // SwiftPM's rule: a prebuild command runs before the build, so not a tool it builds.
            guard !prebuild.executable.pathString.hasPrefix(builtToolsDirectory + "/") else {
                let message = "a prebuild command cannot use executables built from source, including executable target '\(prebuild.executable.basename)'"
                log(message + "\n")
                throw BuildToolPluginFailure(message: message, failedCommands: [application, try Self.blueprint(of: package.path.pathString)])
            }
            throw NomacError("the build tool plug-in “\(plugin.name)” defines a prebuild command (\(prebuild.displayName ?? prebuild.executable.pathString)), which nomac does not run yet (BACKLOG B-009)")
        }
        log("\n")
        let commands = collector.buildCommands.map { command in
            PackagePIFBuilder.CustomBuildCommand(
                displayName: command.displayName, executable: command.executable.pathString, arguments: command.arguments,
                environment: command.environment, workingDir: command.workingDirectory, inputPaths: command.inputFiles,
                outputPaths: command.outputFiles.map(\.pathString), pluginOutputDir: workDirectory,
                sandboxProfile: .init(strictness: .writableTemporaryDirectory, writableDirectories: [workDirectory], readOnlyDirectories: [package.path]))
        }
        return PackagePIFBuilder.BuildToolPluginInvocationResult(prebuildCommandOutputPaths: [], buildCommands: commands)
    }

    /// The targets of `projects` that apply build tool plugins (a `plugin:<product>` package
    /// product dependency, which XcodeProj reads without its prefix: a target dependency on a
    /// plugin product of the graph), with the plugins of those products, in the target's order.
    static func pluginTargets(of projects: [XcodeProject], in graph: ModulesGraph) throws -> [(project: XcodeProject, target: PBXNativeTarget, plugins: [ResolvedModule])] {
        var targets: [(XcodeProject, PBXNativeTarget, [ResolvedModule])] = []
        for project in projects {
            for target in project.pbxproj.nativeTargets {
                let plugins = try target.dependencies.compactMap(\.product?.productName).flatMap { name -> [ResolvedModule] in
                    let products = graph.packages.flatMap(\.products).filter { $0.name == name && $0.type == .plugin }
                    guard products.count <= 1 else {
                        throw NomacError("\(project.name): target “\(target.name)” applies the plug-in product “\(name)”, which more than one package of the workspace declares")
                    }
                    return products.first?.modules.filter { $0.underlying is PluginModule } ?? []
                }
                if !plugins.isEmpty { targets.append((project, target, plugins)) }
            }
        }
        return targets
    }

    /// The project as SwiftPM sends it to a plugin: its name, folder, the files its groups
    /// reference (but the build products), and each native target's product and the files of its
    /// build phases (`build_plugin_experiments.py` project).
    static func representation(of project: XcodeProject) throws -> XcodeProjectRepresentation {
        let directory = (project.path as NSString).deletingLastPathComponent
        func path(of element: PBXFileElement?) throws -> Basics.AbsolutePath? {
            guard let element, let full = try element.fullPath(sourceRoot: directory) else { return nil }
            return try Basics.AbsolutePath(validating: (full as NSString).standardizingPath)
        }
        var filePaths: [Basics.AbsolutePath] = []
        func collect(_ group: PBXGroup) throws {
            for child in group.children {
                if let group = child as? PBXGroup {
                    try collect(group)
                } else if child.sourceTree != .buildProductsDir, let path = try path(of: child) {
                    filePaths.append(path)
                }
            }
        }
        if let main = project.pbxproj.rootObject?.mainGroup { try collect(main) }
        let targets = try project.pbxproj.nativeTargets.map { target in
            let inputFiles = try target.buildPhases.flatMap { phase -> [XcodeProjectRepresentation.Target.InputFile] in
                let role: XcodeProjectRepresentation.Target.InputFile.Role = switch phase {
                case is PBXSourcesBuildPhase: .source
                case is PBXResourcesBuildPhase: .resource
                case is PBXHeadersBuildPhase: .header
                default: .unknown
                }
                return try (phase.files ?? []).compactMap { file in try path(of: file.file).map { .init(path: $0, role: role) } }
            }
            let kind: XcodeProjectRepresentation.Target.Product.Kind = switch target.productType {
            case .application: .application
            case .commandLineTool: .executable
            case .framework, .staticFramework: .framework
            case .staticLibrary, .dynamicLibrary: .library
            default: .other(target.productType?.rawValue ?? "")
            }
            return XcodeProjectRepresentation.Target(displayName: target.name, product: .init(name: target.productName ?? target.name, kind: kind), inputFiles: inputFiles)
        }
        return XcodeProjectRepresentation(displayName: project.name, directoryPath: try Basics.AbsolutePath(validating: directory), filePaths: filePaths, targets: targets)
    }

    private func apply(_ plugin: ResolvedModule, to target: PBXNativeTarget, of project: XcodeProject, representation: XcodeProjectRepresentation, graph: ModulesGraph,
                       generated: [String], runner: DefaultPluginScriptRunner, hostTriple: Triple, toolSearchDirectory: Basics.AbsolutePath,
                       observability: ObservabilitySystem) async throws -> [ProjectPluginCommands.Command] {
        guard let pluginModule = plugin.underlying as? PluginModule,
              let xcodeTarget = representation.targets.first(where: { $0.displayName == target.name }) else { return [] }
        let workDirectory = try Basics.AbsolutePath(validating: intermediates).appending(
            components: "BuildToolPluginIntermediates", project.name + ".output", target.name, plugin.name)
        let tools = try await plugin.preparePluginTools(fileSystem: localFileSystem, environment: Self.environment, for: hostTriple) { name, _ in
            try Basics.AbsolutePath(validating: builtToolsDirectory + "/" + name)
        }
        let application = "Apply build tool plug-in “\(plugin.name)” to target “\(target.name)” in project “\(project.name)”"
        log(application + "\n")
        let collector = CommandCollector()
        let succeeded = try await pluginModule.invoke(
            action: .createXcodeProjectBuildToolCommands(project: representation, target: xcodeTarget,
                                                         pluginGeneratedSources: try generated.map { try Basics.AbsolutePath(validating: $0) }, pluginGeneratedResources: []),
            buildEnvironment: Self.environment, workers: UInt32(ProcessInfo.processInfo.activeProcessorCount), scriptRunner: runner,
            workingDirectory: representation.directoryPath, outputDirectory: workDirectory, toolSearchDirectories: [toolSearchDirectory],
            accessibleTools: tools, writableDirectories: [workDirectory], readOnlyDirectories: [representation.directoryPath],
            allowNetworkConnections: [], pkgConfigDirectories: [], sdkRootPath: nil, fileSystem: localFileSystem,
            modulesGraph: graph, observabilityScope: observability.topScope, callbackQueue: DispatchQueue(label: "nomac.plugin"), delegate: collector)
        // xcodebuild prints the plugin's errors and fails the build, naming the project
        // (`build_plugin_experiments.py` project-package-only).
        guard succeeded, collector.errors.isEmpty else {
            let message = collector.errors.isEmpty ? collector.output.trimmingCharacters(in: .newlines) : collector.errors.joined(separator: "\n")
            log(message + "\n")
            throw BuildToolPluginFailure(message: message, failedCommands: [application, try Self.blueprint(of: project.path)])
        }
        if let prebuild = collector.prebuildCommands.first {
            throw NomacError("the build tool plug-in “\(plugin.name)” defines a prebuild command (\(prebuild.displayName ?? prebuild.executable.pathString)) for an Xcode project's target, which nomac does not run yet (BACKLOG B-009)")
        }
        log("\n")
        return try collector.buildCommands.map { command in
            let sandboxed = try Sandbox.apply(command: [command.executable.pathString] + command.arguments, fileSystem: localFileSystem,
                                              strictness: .writableTemporaryDirectory, writableDirectories: [workDirectory],
                                              readOnlyDirectories: [representation.directoryPath])
            let exports = command.environment.sorted { $0.key < $1.key }.map { "export \($0.key)=\(Self.shellWord($0.value))\n" }
            return ProjectPluginCommands.Command(displayName: command.displayName ?? "", script: exports.joined() + sandboxed.map(Self.shellWord).joined(separator: " ") + "\n",
                                                 inputFiles: command.inputFiles.map(\.pathString), outputFiles: command.outputFiles.map(\.pathString))
        }
    }

    /// A word of the script xcodebuild writes for a plugin's command: as it is when it has only
    /// letters, digits and `+,-./=_`, else in double quotes with `"` and `\` escaped, `$` and
    /// the other characters as they are (`build_plugin_experiments.py` project-quoting).
    static func shellWord(_ word: String) -> String {
        let plain = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+,-./=_")
        guard word.isEmpty || !word.allSatisfy(plain.contains) else { return word }
        return "\"" + word.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// How xcodebuild names a package or project among the failed commands of a plugin it could not
    /// apply: its folder, or `.xcodeproj`, in Base64-encoded JSON (`build_plugin_experiments.py`
    /// prebuildCommand, project-package-only).
    static func blueprint(of packageFolder: String) throws -> String {
        let folder = String(decoding: try JSONEncoder().encode(packageFolder), as: UTF8.self)
        return Data("{\"blueprintProvider_providerFilePathString\":\(folder),\"type\":{\"blueprintProvider\":{}}}".utf8).base64EncodedString()
    }

    /// The build environment the plugins' conditions are evaluated in: the iOS devices nomac builds for.
    static let environment = BuildEnvironment(platform: .iOS, configuration: nil)

    /// The script runner that compiles the plugins as Xcode does, into `<products>/PluginExecutables`,
    /// the triple of the machine the plugins and their tools run on, and the compiler's folder.
    func scriptRunner() throws -> (DefaultPluginScriptRunner, Triple, Basics.AbsolutePath) {
        let binDirectory = try swiftCompiler.map { try Basics.AbsolutePath(validating: ($0 as NSString).deletingLastPathComponent) }
            ?? SwiftPackages.toolchainBinDirectory()
        let compiler = try binDirectory.map { $0.appending("swiftc") } ?? UserToolchain(swiftSDK: .hostSwiftSDK(nil, environment: .current), environment: .current,
                                                                                         fileSystem: localFileSystem).swiftCompilerPath
        let root = try pluginLibraries ?? pluginAPICache.map { try PluginAPI.libraries(swiftCompiler: compiler.pathString, cache: $0) }
        let libraries = try root.map { ToolchainConfiguration.SwiftPMLibrariesLocation(root: try Basics.AbsolutePath(validating: $0)) }
        let sdk = try pluginTarget.map { target in
            SwiftSDK(targetTriple: try Triple(target.triple), toolset: Toolset(toolchainBinDir: binDirectory ?? Basics.AbsolutePath.root),
                     swiftSDKManifest: nil, pathsConfiguration: .init(sdkRootPath: try Basics.AbsolutePath(validating: target.sdk)), xctestSupport: .supported)
        } ?? .hostSwiftSDK(binDirectory, environment: .current)
        let toolchain = try UserToolchain(swiftSDK: sdk, environment: .current,
                                          customLibrariesLocation: libraries, fileSystem: localFileSystem)
        let runner = DefaultPluginScriptRunner(fileSystem: localFileSystem, cacheDir: try Basics.AbsolutePath(validating: buildProducts).appending("PluginExecutables"),
                                               toolchain: toolchain)
        return (runner, toolchain.targetTriple, toolchain.swiftCompilerPath.parentDirectory)
    }
}

private struct CompilerDelegate: PluginScriptCompilerDelegate {
    func willCompilePlugin(commandLine: [String], environment: [String: String]) {}
    func didCompilePlugin(result: PluginCompilationResult) {}
    func skippedCompilingPlugin(cachedResult: PluginCompilationResult) {}
}

/// The commands a build tool plugin returned for a target of an Xcode project, which xcodebuild
/// adds to the target as shell-script phases before its other phases.
public struct ProjectPluginCommands: Sendable, Equatable {
    public struct Command: Sendable, Equatable {
        public var displayName: String
        /// The phase's script: the command's environment exported, then the command in macOS's
        /// sandbox (off macOS, the command itself).
        public var script: String
        public var inputFiles: [String]
        public var outputFiles: [String]

        public init(displayName: String, script: String, inputFiles: [String], outputFiles: [String]) {
            self.displayName = displayName
            self.script = script
            self.inputFiles = inputFiles
            self.outputFiles = outputFiles
        }
    }

    /// The `.xcodeproj` the target is in.
    public var projectPath: String
    public var targetName: String
    public var commands: [Command]

    public init(projectPath: String, targetName: String, commands: [Command]) {
        self.projectPath = projectPath
        self.targetName = targetName
        self.commands = commands
    }
}

/// A build tool plugin xcodebuild could not apply: it prints `message` and fails the build with
/// `failedCommands` before planning it.
public struct BuildToolPluginFailure: Error {
    public var message: String
    public var failedCommands: [String]
}

/// Collects what a plugin sends back while it runs.
private final class CommandCollector: PluginInvocationDelegate, @unchecked Sendable {
    struct Command {
        var displayName: String?
        var executable: Basics.AbsolutePath
        var arguments: [String]
        var environment: [String: String]
        var workingDirectory: Basics.AbsolutePath?
        var inputFiles: [Basics.AbsolutePath]
        var outputFiles: [Basics.AbsolutePath]
    }

    var buildCommands: [Command] = []
    var prebuildCommands: [(displayName: String?, executable: Basics.AbsolutePath)] = []
    var errors: [String] = []
    var output = ""

    func pluginCompilationStarted(commandLine: [String], environment: [String: String]) {}
    func pluginCompilationEnded(result: PluginCompilationResult) {}
    func pluginCompilationWasSkipped(cachedResult: PluginCompilationResult) {}
    func pluginEmittedOutput(_ data: Data) { output += String(decoding: data, as: UTF8.self) }
    func pluginEmittedDiagnostic(_ diagnostic: Basics.Diagnostic) {
        if diagnostic.severity == .error { errors.append(diagnostic.message) }
    }
    func pluginEmittedProgress(_ message: String) {}

    func pluginDefinedBuildCommand(displayName: String?, executable: Basics.AbsolutePath, arguments: [String], environment: [String: String],
                                   workingDirectory: Basics.AbsolutePath?, inputFiles: [Basics.AbsolutePath], outputFiles: [Basics.AbsolutePath]) {
        buildCommands.append(Command(displayName: displayName, executable: executable, arguments: arguments, environment: environment,
                                     workingDirectory: workingDirectory, inputFiles: inputFiles, outputFiles: outputFiles))
    }

    func pluginDefinedPrebuildCommand(displayName: String?, executable: Basics.AbsolutePath, arguments: [String], environment: [String: String],
                                      workingDirectory: Basics.AbsolutePath?, outputFilesDirectory: Basics.AbsolutePath) -> Bool {
        prebuildCommands.append((displayName, executable))
        return true
    }
}
