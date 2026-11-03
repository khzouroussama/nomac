import Foundation
import NomacBuild
import NomacBuildService
import NomacInspect
import NomacProject

/// The scheme actions of one `nomac build` or `nomac archive` (B-175, `scheme_action_experiments.py`):
/// build pre-actions before the build, build post-actions after a successful build (or any, with
/// `runPostActionsOnFailure`), then for an archive the archive pre-actions before the archive is
/// written and its post-actions after. Without `-scheme` there are none.
struct BuildSchemeActions {
    var runner: SchemeActions
    var buildPre: [SchemeActions.Script] = []
    var buildPost: [SchemeActions.Script] = []
    var archivePre: [SchemeActions.Script] = []
    var archivePost: [SchemeActions.Script] = []
    var runsPostActionsOnFailure = false

    init(resolution: BuildSettingsInspector.Resolution, inspector: BuildSettingsInspector, request: SettingsRequest,
         developerDirectory: String, workspace: XcodeWorkspace, destination: String?, shell: String?) async throws {
        runner = SchemeActions(
            developerDirectory: developerDirectory, schemeName: resolution.scheme?.name ?? "",
            containerPath: workspace.isImplicit ? (workspace.path as NSString).deletingLastPathComponent : workspace.path,
            workspacePath: workspace.path, destination: SchemeActions.destinationEnvironment(destination), shell: shell ?? "/bin/sh")
        guard let scheme = resolution.scheme else { return }
        func scripts(_ actions: [XcodeScheme.ScriptAction]) async throws -> [SchemeActions.Script] {
            var result: [SchemeActions.Script] = []
            for action in actions {
                let target = action.environmentTarget.flatMap(inspector.target(for:))
                var settings: [String: String]?
                if let target {
                    settings = try await inspector.session.exportedBuildSettings(targetGUID: target.guid, request: request)
                }
                result.append(SchemeActions.Script(title: action.title, text: action.script, settings: settings))
            }
            return result
        }
        buildPre = try await scripts(scheme.buildPreActions)
        buildPost = try await scripts(scheme.buildPostActions)
        archivePre = try await scripts(scheme.archivePreActions)
        archivePost = try await scripts(scheme.archivePostActions)
        runsPostActionsOnFailure = scheme.runsBuildPostActionsOnFailure
    }
}
