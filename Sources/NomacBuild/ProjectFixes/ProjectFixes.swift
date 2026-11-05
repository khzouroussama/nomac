import Foundation
import NomacCore
import NomacEnvelope
import NomacProject

/// One thing nomac changes about how a project's tools run in a Linux build, as data. The fixes live
/// in this folder and are told to the user (docs/PROJECT-COMPATIBILITY.md, ADR 0184): a `note:` when
/// one applies, a summary at the end of the build, a list in `nomac check`, and `--no-project-fixes`
/// turns them all off. None of them touches the user's files.
public struct ProjectFix: Sendable {
    public enum Change: Sendable {
        /// The file's text, replaced in Node's memory while script phases run.
        case inMemoryEdit(file: String, old: String, new: String)
        /// A rule for any project, in plain words.
        case rule(String)
    }

    public var id: String
    public var tool: String
    public var change: Change
    public var why: String
    public var dropWhen: String
    public var upstream: String?
    /// The `nomac check` feature that reports the projects it applies to.
    public var feature: String
}

public enum ProjectFixes {
    public static let expoAutolinkingScan = ProjectFix(
        id: "expo-autolinking-scan",
        tool: "expo-modules-autolinking",
        change: .inMemoryEdit(file: "expo-modules-autolinking/build/platforms/apple/apple.js",
                              old: "if (process.platform !== 'darwin') {",
                              new: "if (process.platform !== 'darwin' && process.platform !== 'linux') {"),
        why: "its @ExpoModule scan refuses every system but macOS, although expo-modules-macros installs the scanner for Linux and the provider it writes is the Mac's byte for byte; the build otherwise stops in [Expo] Configure project",
        dropWhen: "Expo accepts Linux there: without the exact text the fix does nothing (the text is still in 58.0.17)",
        upstream: nil,
        feature: "build:project-fix=expo-autolinking-scan")

    public static let machOToolLinuxBuild = ProjectFix(
        id: "mach-o-tool-linux-build",
        tool: "any build setting that names a Mach-O executable (React Native's HERMES_CLI_PATH)",
        change: .rule("the setting becomes the one ELF executable of the same name, in a folder beside the tool's, that this machine runs; when it runs none of them, a stand-in that stops the build, if the build runs the tool, and says what to install"),
        why: "Linux cannot run a macOS executable (\"Exec format error\"), and the package ships a Linux build beside it",
        dropWhen: "no app in the corpus or the React Native and Expo sweep needs it",
        upstream: nil,
        feature: "build:setting=mach-o-executable-linux-build")

    public static let macroPluginFromPackage = ProjectFix(
        id: "macro-plugin-from-package",
        tool: "any Swift macro plugin a project names as a Mach-O executable (Expo's ExpoModulesMacros)",
        change: .rule("the plugin is built for this machine from the Swift package beside it, in nomac's scratch folder, and the compiler loads that build first"),
        why: "the compiler cannot run a macOS plugin on Linux, and the package holds the plugin's sources (ADR 0151)",
        dropWhen: "no app in the corpus or the React Native and Expo sweep needs it",
        upstream: nil,
        feature: BuildDomain.macroPluginPackage)

    public static let all = [expoAutolinkingScan, machOToolLinuxBuild, macroPluginFromPackage]

    /// The text of a fix's change for people.
    static func plain(_ change: ProjectFix.Change) -> String {
        switch change {
        case .inMemoryEdit(let file, let old, let new):
            return "in memory, \(file): \"\(old)\" is read as \"\(new)\""
        case .rule(let rule):
            return rule
        }
    }

    /// The fixes that `report`'s features show would apply to the project in a Linux build.
    public static func listing(in report: CheckReport) -> [CheckReport.Fix] {
        all.compactMap { fix in
            report.features.first { $0.id == fix.feature }.map { feature in
                CheckReport.Fix(id: fix.id, tool: fix.tool, change: plain(fix.change), why: fix.why, dropWhen: fix.dropWhen,
                                upstream: fix.upstream, uses: feature.uses)
            }
        }
    }
}

/// The fixes of one build: sets them up, and tells what applied at the end.
public struct ProjectFixRun: Sendable {
    public private(set) var notes: [String] = []
    public private(set) var warnings: [String] = []
    private var applied: [(fix: String, detail: String)] = []
    private let record: String

    public init(workspace: XcodeWorkspace, commandLine: [String: String], scratch: String,
                overrides: inout [String: String], synthesized: inout [String: String]) throws {
        // A stable path: an environment that changes from build to build would run every phase again.
        record = scratch + "/project-fixes-" + MD5.hex(workspace.path) + ".log"
        try? FileManager.default.removeItem(atPath: record)
        NodePreload.apply(preload: try NodePreload.write(in: scratch), record: record, to: &overrides, synthesized: &synthesized)

        let tools = try MachOToolBuilds.resolve(workspace: workspace, commandLine: commandLine, scratch: scratch)
        synthesized.merge(tools.settings) { _, build in build }
        let id = ProjectFixes.machOToolLinuxBuild.id
        notes += tools.notes.map { "note: project fix \(id): \($0)" }
        warnings += tools.warnings
        applied += tools.applied.map { (id, $0) }
    }

    public mutating func builtMacroPlugins(_ targets: [String]) {
        applied += targets.map { (ProjectFixes.macroPluginFromPackage.id, "\($0) built for this machine") }
    }

    /// The summary for the end of the build, with the edits Node recorded; empty when none applied.
    public func summary() -> [String] {
        var details = applied
        let recorded = FileSystem.contents(atPath: record).map { String(decoding: $0, as: UTF8.self).split(separator: "\n").map(String.init) } ?? []
        for fix in ProjectFixes.all where recorded.contains(fix.id) {
            if case .inMemoryEdit(let file, _, _) = fix.change { details.append((fix.id, "\(file) changed in memory")) }
        }
        guard !details.isEmpty else { return [] }
        let order = Dictionary(uniqueKeysWithValues: ProjectFixes.all.enumerated().map { ($1.id, $0) })
        let sorted = details.enumerated().sorted { (order[$0.element.fix] ?? 0, $0.offset) < (order[$1.element.fix] ?? 0, $1.offset) }.map(\.element)
        let fixes = Set(sorted.map(\.fix)).count
        return ["note: nomac applied \(fixes) project \(fixes == 1 ? "fix" : "fixes") to how this project's tools run; your files on disk are not changed:"]
            + sorted.map { "note:   \($0.fix): \($0.detail)" }
            + ["note: what they do, what you may have to change yourself, and --no-project-fixes to turn them off: \(CheckReport.projectCompatibilityDocument)"]
    }
}
