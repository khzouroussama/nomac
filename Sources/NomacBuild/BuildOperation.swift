import Foundation
import NomacBuildService
import NomacCore
import SwiftBuild

/// Builds targets with Swift Build in-process, as `xcodebuild build` does, and writes the log
/// in xcodebuild's format: each task's rule, `(in target … from project …)`, its command line,
/// then its output.
///
/// The request is the one xcodebuild hands Swift Build, which Swift Build records in
/// `Build/Intermediates.noindex/XCBuildData/<id>.xcbuilddata/build-request.json` (observed for
/// retro-rampage's `Engine` and icecubes' `Models` schemes, and `.github/scripts/build_experiments.py`,
/// with Xcode 27.0). xcodebuild adds `generatePrecompiledModulesReport` only with
/// `-showBuildTimingSummary`, which nomac does not take yet (B-108), and sets
/// `continueBuildingAfterErrors` with the user default `-IDEBuildingContinueBuildingAfterErrors=YES`.
public enum BuildOperation {
    /// The targets and request of one build.
    public struct Request: Sendable {
        public var targets: [WorkspaceTarget]
        public var settings: SettingsRequest
        /// The `.xcodeproj` or `.xcworkspace` the build was started with.
        public var containerPath: String
        /// Whether tasks that do not depend on a failed one still run.
        public var continueBuildingAfterErrors: Bool
        /// The scheme archived, for `xcodebuild archive`'s build; none for a build.
        public var archivedScheme: String?
        /// The identity and profiles for signing with a certificate.
        public var signing: SigningMaterial?

        public init(targets: [WorkspaceTarget], settings: SettingsRequest, containerPath: String, continueBuildingAfterErrors: Bool = false,
                    archivedScheme: String? = nil, signing: SigningMaterial? = nil) {
            self.targets = targets
            self.settings = settings
            self.containerPath = containerPath
            self.continueBuildingAfterErrors = continueBuildingAfterErrors
            self.archivedScheme = archivedScheme
            self.signing = signing
        }
    }

    /// How a build ended.
    public struct Outcome: Sendable, Equatable {
        public var succeeded: Bool
        /// The rule of every task that failed, with its target, in the order they failed.
        public var failedTasks: [String]
    }

    /// Settings xcodebuild synthesizes for every build.
    static let synthesizedOverrides = ["ACTION": "build", "ENABLE_PREVIEWS": "NO", "ENABLE_XOJIT_PREVIEWS": "YES"]

    /// The settings `xcodebuild archive` synthesizes, its build installing into
    /// `<intermediates>/ArchiveIntermediates/<scheme>` (retro-rampage's `Rampage` and tofu
    /// archived, `build_experiments.py`).
    public static func archiveOverrides(buildIntermediatesPath intermediates: String, scheme: String) -> [String: String] {
        let archive = archiveIntermediates(buildIntermediatesPath: intermediates, scheme: scheme)
        let products = archive + "/BuildProductsPath"
        let installation = archive + "/InstallationBuildProductsLocation"
        return [
            "ACTION": "install",
            "ASSET_PACK_FOLDER_PATH": installation + "/OnDemandResources",
            "ASSETCATALOG_COMPILER_FLATTENED_APP_ICON_PATH": products + "/ProductIcon.png",
            "DEPLOYMENT_LOCATION": "YES",
            "DEPLOYMENT_POSTPROCESSING": "YES",
            "DSTROOT": installation,
            "EMBED_ASSET_PACKS_IN_PRODUCT_BUNDLE": "NO",
            "ENABLE_PREVIEWS": "NO",
            "ENABLE_SIGNATURE_AGGREGATION": "YES",
            "ENABLE_XOJIT_PREVIEWS": "YES",
            "INDEX_ENABLE_DATA_STORE": "NO",
            "MESSAGES_APPLICATION_EXTENSION_SUPPORT_FOLDER_PATH": products + "/MessagesApplicationExtensionSupport",
            "MESSAGES_APPLICATION_SUPPORT_FOLDER_PATH": products + "/MessagesApplicationSupport",
            "OBJROOT": archive + "/IntermediateBuildFilesPath",
            "SHARED_PRECOMPS_DIR": archive + "/PrecompiledHeaders",
            "SIGNATURE_METADATA_FOLDER_PATH": products + "/Signatures",
            "SWIFT_STDLIB_TOOL_UNSIGNED_DESTINATION_DIR": products + "/SwiftSupport",
            "SYMROOT": products,
            "WATCHKIT_2_SUPPORT_FOLDER_PATH": products + "/WatchKitSupport2",
        ]
    }

    /// The scheme's folder of `ArchiveIntermediates`, which `nomac xcarchive` assembles from.
    public static func archiveIntermediates(buildIntermediatesPath: String, scheme: String) -> String {
        buildIntermediatesPath + "/ArchiveIntermediates/" + scheme
    }

    /// The architectures of xcodebuild's `generic/platform=iOS` destination in a build.
    static let genericIOSArchitectures = ["armv4t", "armv5", "armv6", "armv7", "armv7f", "armv7s", "armv7k", "arm64", "arm64e"]

    /// The Swift Build request xcodebuild makes for `request`.
    static func buildRequest(_ request: Request, sdkCanonicalName: String?) -> SWBBuildRequest {
        var settings = request.settings
        if let scheme = request.archivedScheme, let intermediates = settings.locations?.buildIntermediatesPath {
            settings.synthesizedOverrides.merge(archiveOverrides(buildIntermediatesPath: intermediates, scheme: scheme)) { current, _ in current }
        } else {
            settings.synthesizedOverrides.merge(synthesizedOverrides) { current, _ in current }
        }
        if var destination = settings.destination, destination.platform == "iphoneos", destination.targetArchitecture == "undefined_arch" {
            destination.sdk = sdkCanonicalName ?? destination.sdk
            destination.supportedArchitectures = genericIOSArchitectures
            settings.destination = destination
        }
        var parameters = settings.buildParameters
        if let derivedData = parameters.arenaInfo?.derivedDataPath {
            parameters.arenaInfo?.indexDataStoreFolderPath = derivedData + "/Index.noindex/DataStore"
            parameters.arenaInfo?.indexEnableDataStore = true
        }
        var buildRequest = SWBBuildRequest()
        buildRequest.parameters = parameters
        buildRequest.configuredTargets = request.targets.map { SWBConfiguredTarget(guid: $0.guid, parameters: nil) }
        buildRequest.containerPath = request.containerPath
        // What the observed requests had, for schemes that keep Xcode's defaults ("Parallelize
        // Build" and "Find Implicit Dependencies" on); other scheme settings are B-111.
        buildRequest.useParallelTargets = true
        buildRequest.useImplicitDependencies = true
        buildRequest.hideShellScriptEnvironment = false
        buildRequest.continueBuildingAfterErrors = request.continueBuildingAfterErrors
        if request.archivedScheme != nil {
            buildRequest.schemeCommand = .archive
            buildRequest.buildCommand = .build(style: .buildAndRun)
        }
        return buildRequest
    }

    /// Runs the build. Every log line goes to `log`.
    public static func run(_ request: Request, session: WorkspaceSession, quiet: Bool = false, log: @escaping @Sendable (String) -> Void) async throws -> Outcome {
        // The destination names the SDK by its canonical name (`iphoneos27.0`).
        var sdkCanonicalName: String?
        if let first = request.targets.first {
            sdkCanonicalName = try await session.evaluate("$(SDK_NAME)", targetGUID: first.guid, request: request.settings)
        }
        let buildRequest = buildRequest(request, sdkCanonicalName: sdkCanonicalName)
        let targetNames = Dictionary(try await session.targets().map { ($0.guid, $0.name) }) { first, _ in first }
        let operation: SWBBuildOperation
        do {
            operation = try await session.session.createBuildOperation(request: buildRequest, delegate: PlanningDelegate(signing: request.signing, targetNames: targetNames))
        } catch {
            throw NomacError("Swift Build could not plan the build: \(error)")
        }
        var printer = LogPrinter(log: log, quiet: quiet)
        for try await message in try await operation.start() {
            printer.handle(message)
        }
        await operation.waitForCompletion()
        printer.finish()
        return Outcome(succeeded: operation.state == .succeeded, failedTasks: printer.failedTasks)
    }

    /// The summary xcodebuild prints after `** BUILD FAILED **` or `** ARCHIVE FAILED **`, both on
    /// standard error: each failed task in the order they failed, then for a scheme the build itself
    /// (`schemeAction`), then the count of those lines; nothing when there is no line, as for a
    /// `-target` build that fails while planning (`.github/scripts/failure_experiments.py`).
    public static func failureSummary(failedTasks: [String], schemeAction: String?) -> String? {
        let lines = failedTasks + (schemeAction.map { [$0] } ?? [])
        guard !lines.isEmpty else { return nil }
        return "\nThe following build commands failed:\n" + lines.map { "\t" + $0 + "\n" }.joined()
            + "(\(lines.count) failure\(lines.count == 1 ? "" : "s"))\n"
    }

    /// The scheme's line of the failure summary: `Building <container> <name> with scheme <scheme>
    /// and configuration <configuration>`, or for an archive `Archiving <container> <name> with
    /// scheme <scheme>`; the container is `project` for a project opened alone and `workspace` for
    /// a workspace or a Swift package's folder (`failure_experiments.py`, retro-rampage's `Engine`).
    /// Without a configuration, before the build has one: a plugin that could not be applied
    /// (`build_plugin_experiments.py` prebuildCommand).
    /// The failure summary's last line. `build-for-testing` names no configuration
    /// (`xctest_experiments.py` `xctestrun-failing`).
    public static func schemeAction(archive: Bool, testing: Bool = false, container: String, name: String, scheme: String, configuration: String?) -> String {
        if testing { return "Building \(container) \(name) for testing with scheme \(scheme)" }
        return archive ? "Archiving \(container) \(name) with scheme \(scheme)"
            : "Building \(container) \(name) with scheme \(scheme)" + (configuration.map { " and configuration \($0)" } ?? "")
    }
}

/// Answers Swift Build's questions while it plans. Tools it probes run as they are.
/// True the first time it is asked.
final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func first() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        defer { done = true }
        return !done
    }
}

final class PlanningDelegate: SWBPlanningOperationDelegate, Sendable {
    let signing: SigningMaterial?
    /// Target names by GUID, which Xcode's provisioning errors name.
    let targetNames: [String: String]

    init(signing: SigningMaterial?, targetNames: [String: String]) {
        self.signing = signing
        self.targetNames = targetNames
    }

    func provisioningTaskInputs(targetGUID: String, provisioningSourceData: SWBProvisioningTaskInputsSourceData) async -> SWBProvisioningTaskInputs {
        let requested = provisioningSourceData.signingCertificateIdentifier
        if let signing, requested != "-", !requested.isEmpty {
            return ManualSigning.provisioning(ManualSigning.Source(
                targetName: targetNames[targetGUID] ?? "", signingIdentity: requested, style: provisioningSourceData.provisioningStyle,
                profileSupport: provisioningSourceData.provisioningProfileSupport,
                profileSpecifier: provisioningSourceData.provisioningProfileSpecifier, profileUUID: provisioningSourceData.provisioningProfileUUID,
                teamID: provisioningSourceData.teamID, bundleIdentifier: provisioningSourceData.bundleIdentifier,
                projectEntitlements: provisioningSourceData.projectEntitlements,
                productTypeEntitlements: provisioningSourceData.productTypeEntitlements), material: signing)
        }
        #if os(macOS)
        let identity = requested
        #else
        let identity = LinuxSigning.identity(for: requested)
        #endif
        let inputs = Self.provisioning(signingIdentity: identity, entitlementsFile: provisioningSourceData.projectEntitlementsFile,
                                       entitlements: provisioningSourceData.projectEntitlements, targetName: targetNames[targetGUID] ?? "")
        if !inputs.errors.isEmpty, signingHint.first() { FileHandle.standardError.write(Data((Self.signingHintText + "\n").utf8)) }
        return inputs
    }

    /// Beside Xcode's refusal, whose next step is an editor nomac does not have.
    static let signingHintText = "note: to sign for a device, pass --keychain, --provisioning-profiles and CODE_SIGN_STYLE=Manual with PROVISIONING_PROFILE_SPECIFIER (docs/INSTALL-ON-IPHONE.md); to build without a device, CODE_SIGN_ENTITLEMENTS= signs ad hoc without the entitlements"
    private let signingHint = OnceFlag()

    /// What Xcode 27.0 answers for `CODE_SIGN_IDENTITY=-`: identity `-`, shown as "Sign to Run
    /// Locally", with no entitlements (retro-rampage's `Engine` and `build_experiments.py`'s
    /// `App`, neither with an entitlements file: `codesign --force --sign - --timestamp=none
    /// --generate-entitlement-der`, no .xcent). With an entitlements file holding an empty
    /// dictionary (expo-default's; signing-experiments `entitlements-empty`), the same answer:
    /// Swift Build then writes an empty .xcent and signs with `--entitlements` it. With
    /// entitlements in the file (an app group, `aps-environment` or a keychain group:
    /// `entitlements-groups`, `-push`, `-keychain`), Xcode refuses the target with the error
    /// below and the build fails (exit status 65). Identities are `ManualSigning`'s.
    static func provisioning(signingIdentity: String, entitlementsFile: String?, entitlements: [String: SWBPropertyListItem]?,
                             targetName: String) -> SWBProvisioningTaskInputs {
        guard signingIdentity == "-" else { return SWBProvisioningTaskInputs() }
        guard entitlementsFile?.isEmpty ?? true || entitlements?.isEmpty == true else {
            return SWBProvisioningTaskInputs(errors: [[
                "description": "\"\(targetName)\" requires a provisioning profile.",
                "recoverySuggestion": "Enable development signing and select a provisioning profile in the Signing & Capabilities editor.",
            ]])
        }
        return SWBProvisioningTaskInputs(identityHash: "-", identityName: "Sign to Run Locally")
    }

    func executeExternalTool(commandLine: [String], workingDirectory: String?, environment: [String: String]) async throws -> SWBExternalToolResult {
        .deferred
    }
}

/// Turns build messages into xcodebuild's log lines; with `quiet`, as `xcodebuild -quiet`, only
/// the diagnostics.
struct LogPrinter {
    let log: @Sendable (String) -> Void
    let quiet: Bool
    private var targets: [Int: (name: String, project: String, projectPath: String)] = [:]
    /// Started tasks by ID, with their signature: a task can complete under another signature
    /// than it started with (rn-bare's SDK explicit-module tasks), never under another ID.
    private var tasks: [Int: (header: String, signature: String)] = [:]
    private var output: [String: Data] = [:]
    private(set) var failedTasks: [String] = []

    init(log: @escaping @Sendable (String) -> Void, quiet: Bool = false) {
        self.log = log
        self.quiet = quiet
    }

    mutating func handle(_ message: SwiftBuildMessage) {
        switch message {
        case .targetStarted(let info):
            targets[info.targetID] = (info.targetName, info.projectName, info.projectPath.pathString)
        case .taskStarted(let info):
            var header = info.ruleInfo
            if let targetID = info.targetID, let target = targets[targetID] {
                header += " (in target '\(target.name)' from project '\(target.project)')"
            }
            tasks[info.taskID] = (header + "\n" + (info.commandLineDisplayString ?? ""), info.taskSignature)
        case .output(let info):
            // A task's output without its signature (codesign's "replacing existing signature")
            // still belongs to the task's block, by the task's ID.
            if let signature = info.locationContext2.taskSignature ?? Self.taskID(of: info.locationContext).flatMap({ tasks[$0]?.signature }) {
                output[signature, default: Data()].append(info.data)
            } else if !quiet {
                log(String(decoding: info.data, as: UTF8.self))
            }
        case .taskComplete(let info):
            guard let (header, signature) = tasks.removeValue(forKey: info.taskID) else { return }
            if info.result == .failed, let rule = header.split(separator: "\n", maxSplits: 1).first {
                failedTasks.append(String(rule))
            }
            var text = header
            var data = output.removeValue(forKey: signature)
            if info.taskSignature != signature, let more = output.removeValue(forKey: info.taskSignature) {
                data = (data ?? Data()) + more
            }
            guard !quiet else { return }
            if let data, !data.isEmpty {
                text += String(decoding: data, as: UTF8.self)
                if !text.hasSuffix("\n") { text += "\n" }
            }
            log(text + "\n")
        case .diagnostic(let info):
            let target = info.locationContext2.targetID.flatMap { targets[$0] }
            // A task's own diagnostic, which xcodebuild prints in the task's block after its
            // command line, with the target when it has no location (a framework's Copy in the
            // device workstream's signing app: "warning: not stripping binary because it is signed").
            if info.appendToOutputStream, let taskID = Self.taskID(of: info.locationContext), let task = tasks[taskID] {
                var line = Self.render(info, target: target)
                if case .unknown = info.location, let target { line += " (in target '\(target.name)' from project '\(target.project)')" }
                output[task.signature, default: Data()].append(Data((line + "\n").utf8))
                return
            }
            log(Self.render(info, target: target) + "\n")
        default:
            break
        }
    }

    static func taskID(of context: SwiftBuildMessage.LocationContext) -> Int? {
        switch context {
        case .task(let taskID, _), .globalTask(let taskID): taskID
        default: nil
        }
    }

    func finish() {
        guard !quiet else { return }
        for header in tasks.values.map(\.header).sorted() {
            log(header + "\n")
        }
    }

    /// A diagnostic as xcodebuild prints it: at its file and line, or, located at build settings
    /// in a target, at the target's project with the target named after the message (Xcode's
    /// provisioning errors, signing-experiments `entitlements-push`).
    static func render(_ info: SwiftBuildMessage.DiagnosticInfo, target: (name: String, project: String, projectPath: String)? = nil) -> String {
        var prefix = ""
        var suffix = ""
        switch info.location {
        case .path(let path, let fileLocation):
            prefix = path
            if case .textual(let line, let column)? = fileLocation {
                prefix += ":\(line)" + (column.map { ":\($0)" } ?? "")
            }
            prefix += ": "
        case .buildSettings:
            if let target {
                prefix = target.projectPath + ": "
                suffix = " (in target '\(target.name)' from project '\(target.project)')"
            }
        default:
            break
        }
        // A diagnostic's notes follow it, indented (xcodebuild's words for a signature it refuses,
        // `signature_record_experiments.py` `build-corrupt`, `build-expected-other`).
        return prefix + "\(info.kind.rawValue): \(info.message)" + suffix
            + info.childDiagnostics.map { "\n    " + render($0, target: target) }.joined()
    }
}
