import Foundation
import NomacBuildService
import NomacCore
import NomacPIF
import NomacProject
import NomacVerify

/// Replays a reference capture (corpus/scripts/capture_reference.py output) with nomac and
/// compares every artifact nomac can currently produce.
public struct ReferenceVerifier {
    public typealias Check = VerificationReport.Check
    public typealias Report = VerificationReport

    public var referenceDirectory: String
    public var sourceRoot: String
    public var developerDirectory: String
    public var scratchDirectory: String
    /// How many differences to list per failing check.
    public var detailLimit: Int
    /// The container's features outside the envelope (`nomac check`, given the folder holding the
    /// remote packages' checkouts), for the `envelope` check; without it there is none.
    public var envelope: (@Sendable (_ container: String, _ sourcePackages: String) -> (unknown: [String], unverified: [String]))?

    public init(referenceDirectory: String, sourceRoot: String, developerDirectory: String, scratchDirectory: String, detailLimit: Int = 40,
                envelope: (@Sendable (_ container: String, _ sourcePackages: String) -> (unknown: [String], unverified: [String]))? = nil) {
        self.referenceDirectory = referenceDirectory
        self.sourceRoot = sourceRoot
        self.developerDirectory = developerDirectory
        self.scratchDirectory = scratchDirectory
        self.detailLimit = detailLimit
        self.envelope = envelope
    }

    private struct AppRecord: Decodable { var id: String; var container: String }
    private struct SourceRecord: Decodable { var path: String }
    private struct CaptureRecord: Decodable { var name: String; var arguments: [String]; var exitStatus: Int32 }

    public func run() async throws -> Report {
        let app: AppRecord = try decode(referenceDirectory + "/app.json")
        let source: SourceRecord = try decode(referenceDirectory + "/source.json")
        let referenceHost = try ReferenceHost.load(path: referenceDirectory + "/host.json")
        let captures: [CaptureRecord] = try decode(referenceDirectory + "/settings/index.json")

        let roots = MachineRoots.roots(referenceHost: referenceHost, referenceSource: source.path, sourceRoot: sourceRoot, developerDirectory: developerDirectory)
        let normalizer = PathNormalizer(roots: roots)

        // The PIF, with packages checked out where the reference Xcode checked them out.
        let host = referenceHost.identity(developerDirectory: developerDirectory)
        let workspace: XcodeWorkspace
        let pif: WorkspacePIF
        do {
            workspace = try XcodeWorkspace.load(path: sourceRoot + "/" + app.container)
            pif = try await WorkspacePIF.generate(workspace: workspace, developerDirectory: developerDirectory, home: host.homeDirectory)
        } catch let error as NomacError {
            let checks = failedChecks(error, captures: captures)
            return VerificationReport(app: app.id, xcodeBuild: referenceHost.xcodeBuild, checks: checks + envelopeChecks(checks, container: app.container, sourcePackages: nil))
        }
        var checks: [Check] = []
        if let expected = try? String(contentsOfFile: referenceDirectory + "/pif/workspace.pif", encoding: .utf8) {
            let actual = Self.rehashed(pif.document.serialized(), hashedPaths: pif.hashedBuildFilePaths, sourceRoot: sourceRoot, referenceSource: source.path)
            let result = try PIFComparison.compare(expected: expected, actual: actual, normalizer: normalizer,
                                                   randomBuildFileReferences: pif.randomBuildFileReferences)
            var detail: [String] = []
            if let difference = result.firstDifference {
                detail = ["Xcode: \(difference.expected)", "nomac: \(difference.actual)"]
            }
            checks.append(Check(kind: "pif", name: "workspace.pif", status: result.identical ? .identical : .different, detail: detail + pif.warnings))
        } else if let record: CommandRecord = try? decode(referenceDirectory + "/pif/dumpPIF.stdout.cmd"), record.exitStatus != 0 {
            checks.append(Check(kind: "pif", name: "workspace.pif", status: .different, detail: ["xcodebuild exited with status \(record.exitStatus); nomac wrote a PIF"]))
        } else {
            checks.append(Check(kind: "pif", name: "workspace.pif", status: .referenceFailed, detail: ["no reference PIF"]))
        }

        checks += try await BuildSettingsInspector.with(workspace: workspace, pif: pif, developerDirectory: developerDirectory, host: host,
                                                        scratchDirectory: scratchDirectory) { inspector in
            var checks: [Check] = []
            // The project's targets, configurations and schemes, as `xcodebuild -list -json` printed them.
            if let expected = try? String(contentsOfFile: referenceDirectory + "/xcodebuild-list.json", encoding: .utf8) {
                let actual = try await WorkspaceListing(workspace: workspace, schemes: inspector.schemes()).json
                let expectedLines = expected.split(separator: "\n", omittingEmptySubsequences: false)
                let actualLines = actual.split(separator: "\n", omittingEmptySubsequences: false)
                var detail: [String] = []
                let common = min(expectedLines.count, actualLines.count)
                if let index = (0..<common).first(where: { expectedLines[$0] != actualLines[$0] }) ?? (expectedLines.count == actualLines.count ? nil : common) {
                    detail = ["line \(index + 1)", "Xcode: \(index < expectedLines.count ? String(expectedLines[index]) : "(end)")", "nomac: \(index < actualLines.count ? String(actualLines[index]) : "(end)")"]
                }
                checks.append(Check(kind: "list", name: "xcodebuild-list.json", status: detail.isEmpty ? .identical : .different, detail: detail))
            }

            // Build settings, one check per captured xcodebuild invocation.
            let schemes = try await inspector.schemes()
            for capture in captures where !capture.name.hasSuffix(".json") {
                guard let invocation = Self.parse(capture.arguments) else {
                    checks.append(Check(kind: "settings", name: capture.name, status: .unsupported, detail: ["xcodebuild arguments not reproduced yet: \(capture.arguments.joined(separator: " "))"]))
                    continue
                }
                let outcome: Result<[ShowBuildSettings.Block], Error>
                do {
                    outcome = .success(try await inspector.blocks(invocation))
                } catch {
                    outcome = .failure(error)
                }
                var selected: XcodeScheme?
                if case .scheme(let name) = invocation.selection {
                    selected = try? XcodeWorkspace.scheme(named: name, in: schemes, workspace: workspace)
                }
                let unordered = selected?.unorderedTargetNames ?? []
                // The outcomes of the other targets xcodebuild may build for the scheme's name.
                var alternatives: [(scheme: XcodeScheme, outcome: Result<[ShowBuildSettings.Block], Error>)] = []
                for alternative in selected?.alternatives ?? [] {
                    var other = invocation
                    other.alternative = alternative
                    do {
                        alternatives.append((alternative, .success(try await inspector.blocks(other))))
                    } catch {
                        alternatives.append((alternative, .failure(error)))
                    }
                }
                func check(_ name: String, status: Int32, json: Bool) throws -> Check {
                    let check = try settingsCheck(name: name, status: status, outcome: outcome, normalizer: normalizer, unordered: unordered, json: json)
                    guard check.status == .different else { return check }
                    for (alternative, outcome) in alternatives {
                        let other = try settingsCheck(name: name, status: status, outcome: outcome, normalizer: normalizer, unordered: unordered, json: json)
                        if other.status != .different {
                            let container = alternative.buildEntries.first.map { ($0.containerPath as NSString).lastPathComponent } ?? "?"
                            return Check(kind: "settings", name: name, status: .equivalent, detail: [
                                "the target of \(container) of those named \(alternative.name), one of which xcodebuild builds from one run to the next",
                            ])
                        }
                    }
                    return check
                }
                checks.append(try check(capture.name, status: capture.exitStatus, json: false))
                // The same invocation with -json, captured next to the text.
                let jsonName = capture.name + ".json"
                if let record: CommandRecord = try? decode(referenceDirectory + "/settings/\(jsonName).cmd") {
                    checks.append(try check(jsonName, status: record.exitStatus, json: true))
                }
            }
            return checks
        }
        let sourcePackages = DerivedData.sourcePackagesPath(
            name: workspace.name, containerPath: DerivedData.containerPath(of: workspace), home: host.homeDirectory, customRoot: nil,
            user: UserBuildLocations(workspacePath: workspace.path, userName: host.userName))
        return VerificationReport(app: app.id, xcodeBuild: referenceHost.xcodeBuild,
                                  checks: checks + envelopeChecks(checks, container: app.container, sourcePackages: sourcePackages))
    }

    /// `serialized` with each GUID that hashes a path under `sourceRoot` (``WorkspacePIF/hashedBuildFilePaths``)
    /// replaced by the GUID of the same path under `referenceSource`, where Xcode hashed it.
    static func rehashed(_ serialized: String, hashedPaths: [String: String], sourceRoot: String, referenceSource: String) -> String {
        let local = (sourceRoot as NSString).standardizingPath.decomposed
        let reference = (referenceSource as NSString).standardizingPath.decomposed
        var result = serialized
        for (guid, path) in hashedPaths.sorted(by: { $0.key < $1.key }) where path.hasPrefix(local + "/") {
            let rehashed = PIFIdentifiers.objectGUID(projectGUID: String(guid.dropLast(32)), objectID: reference + path.dropFirst(local.count))
            result = result.replacingOccurrences(of: guid, with: rehashed)
        }
        return result
    }

    /// The `envelope` check of `comparisons`, when the verifier has an envelope.
    private func envelopeChecks(_ comparisons: [Check], container: String, sourcePackages: String?) -> [Check] {
        guard let envelope else { return [] }
        let outside = envelope(sourceRoot + "/" + container, sourcePackages ?? "")
        return [Report.envelopeCheck(unknown: outside.unknown, unverified: outside.unverified, comparisons: comparisons)]
    }

    /// The checks of a reference nomac fails to load or to generate the PIF of: each command
    /// xcodebuild ran must have failed with nomac's status (envelope-experiments: objectVersions
    /// Xcode refuses, a local package not on disk, both 74).
    private func failedChecks(_ error: NomacError, captures: [CaptureRecord]) -> [Check] {
        func check(kind: String, name: String, record path: String) -> Check {
            guard let record: CommandRecord = try? decode(referenceDirectory + "/" + path) else {
                return Check(kind: kind, name: name, status: .referenceFailed, detail: ["no record of xcodebuild's status", "nomac failed with status \(error.exitStatus): \(error)"])
            }
            return failure(kind: kind, name: name, status: record.exitStatus, error: error)
        }
        var checks = [check(kind: "pif", name: "workspace.pif", record: "pif/dumpPIF.stdout.cmd"), check(kind: "list", name: "xcodebuild-list.json", record: "xcodebuild-list.json.cmd")]
        for capture in captures where !capture.name.hasSuffix(".json") {
            checks.append(failure(kind: "settings", name: capture.name, status: capture.exitStatus, error: error))
        }
        return checks
    }

    private func failure(kind: String, name: String, status: Int32, error: NomacError) -> Check {
        let same = status != 0 && Self.shellStatus(status) == error.exitStatus
        return Check(kind: kind, name: name, status: same ? .identical : .different,
                     detail: same ? [] : ["xcodebuild exited with status \(status)", "nomac failed with status \(error.exitStatus): \(error)"])
    }

    private struct CommandRecord: Decodable { var exitStatus: Int32 }

    /// A capture records a command killed by a signal as Python does, `-<signal>`; a shell reports
    /// it as `128 + <signal>`, the status nomac exits with in its place.
    static func shellStatus(_ recorded: Int32) -> Int32 {
        recorded < 0 ? 128 - recorded : recorded
    }

    /// Compares nomac's outcome for one captured invocation with xcodebuild's: the same
    /// settings, or, where xcodebuild failed, a failure with the same exit status. With `json`,
    /// the output is compared byte for byte (after path normalization) with the `-json` capture.
    /// The blocks of `unordered` targets, whose order xcodebuild changes from one run to the next,
    /// are compared again in the capture's order when that is their only difference, and the
    /// capture is then equivalent.
    private func settingsCheck(name: String, status: Int32, outcome: Result<[ShowBuildSettings.Block], Error>, normalizer: PathNormalizer,
                               unordered: Set<String> = [], json: Bool = false) throws -> Check {
        let blocks: [ShowBuildSettings.Block]
        switch outcome {
        case .failure(let error):
            let nomacStatus = (error as? NomacError)?.exitStatus ?? 1
            let same = status != 0 && nomacStatus == Self.shellStatus(status)
            return Check(kind: "settings", name: name, status: same ? .identical : .different,
                         detail: same ? [] : ["xcodebuild exited with status \(status)", "nomac failed with status \(nomacStatus): \(error)"])
        case .success(let result):
            blocks = result
        }
        if status != 0 {
            return Check(kind: "settings", name: name, status: .different,
                         detail: ["xcodebuild exited with status \(status); nomac printed \(blocks.count) settings blocks"])
        }
        let check = try compareSettings(name: name, blocks: blocks, normalizer: normalizer, json: json)
        guard check.status == .different, !unordered.isEmpty,
              let expectedTargets = try? expectedTargets(name: name, normalizer: normalizer, json: json),
              let reordered = Self.reordered(blocks, like: expectedTargets, unordered: unordered),
              try compareSettings(name: name, blocks: reordered, normalizer: normalizer, json: json).status == .identical else { return check }
        return Check(kind: "settings", name: name, status: .equivalent, detail: [
            "blocks of \(unordered.sorted().joined(separator: ", ")) in another order, which xcodebuild changes from one run to the next",
        ])
    }

    /// The targets of a capture's blocks in Xcode's order; a `-json` capture is its own
    /// xcodebuild run, whose order can differ from its text capture's.
    private func expectedTargets(name: String, normalizer: PathNormalizer, json: Bool) throws -> [String] {
        let text = try String(contentsOfFile: referenceDirectory + "/settings/" + (json ? name : name + ".txt"), encoding: .utf8)
        guard json else { return ShowBuildSettings.parse(normalizer.normalize(text)).map(\.target) }
        let entries = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]] ?? []
        return entries.compactMap { $0["target"] as? String }
    }

    /// `blocks` in the order of `expectedTargets`, when the two differ only in where the blocks of
    /// `unordered` targets are; `nil` otherwise.
    static func reordered(_ blocks: [ShowBuildSettings.Block], like expectedTargets: [String], unordered: Set<String>) -> [ShowBuildSettings.Block]? {
        let targets = blocks.map(\.target)
        guard targets != expectedTargets, targets.sorted() == expectedTargets.sorted(),
              zip(targets, expectedTargets).allSatisfy({ $0 == $1 || (unordered.contains($0) && unordered.contains($1)) }) else { return nil }
        var remaining = blocks
        return expectedTargets.map { target in remaining.remove(at: remaining.firstIndex { $0.target == target }!) }
    }

    private func compareSettings(name: String, blocks: [ShowBuildSettings.Block], normalizer: PathNormalizer, json: Bool) throws -> Check {
        let expectedPath = referenceDirectory + "/settings/" + (json ? name : name + ".txt")
        let expected = try String(contentsOfFile: expectedPath, encoding: .utf8)
        if json {
            let expectedLines = normalizer.normalize(expected).split(separator: "\n", omittingEmptySubsequences: false)
            let actualLines = normalizer.normalize(try ShowBuildSettings.renderJSON(blocks)).split(separator: "\n", omittingEmptySubsequences: false)
            let common = min(expectedLines.count, actualLines.count)
            guard let index = (0..<common).first(where: { expectedLines[$0] != actualLines[$0] }) ?? (expectedLines.count == actualLines.count ? nil : common) else {
                return Check(kind: "settings", name: name, status: .identical, detail: [])
            }
            return Check(kind: "settings", name: name, status: .different, detail: [
                "line \(index + 1)",
                "Xcode: \(index < expectedLines.count ? String(expectedLines[index]) : "(end)")",
                "nomac: \(index < actualLines.count ? String(actualLines[index]) : "(end)")",
            ])
        }
        let comparison = SettingsComparison.compare(expected: expected, actual: ShowBuildSettings.render(blocks), normalizer: normalizer)
        let detail = comparison.differences.prefix(detailLimit).map(\.description)
            + (comparison.differences.count > detailLimit ? ["... \(comparison.differences.count - detailLimit) more differences"] : [])
        return Check(kind: "settings", name: name, status: comparison.identical ? .identical : .different, detail: detail)
    }

    /// Maps captured xcodebuild arguments to an inspector invocation, or `nil` for arguments
    /// nomac does not reproduce (for example a scheme with no destination, where xcodebuild
    /// picks the reference Mac itself as the run destination).
    static func parse(_ arguments: [String]) -> BuildSettingsInspector.Invocation? {
        var targets: [String] = []
        var scheme: String?
        var configuration: String?
        var destination: String?
        var derivedDataPath: String?
        var allTargets = false
        var index = 0
        func value() -> String? {
            guard index + 1 < arguments.count else { return nil }
            defer { index += 2 }
            return arguments[index + 1]
        }
        while index < arguments.count {
            switch arguments[index] {
            case "-target":
                guard let name = value() else { return nil }
                targets.append(name)
            case "-scheme":
                guard let name = value() else { return nil }
                scheme = name
            case "-configuration":
                guard let name = value() else { return nil }
                configuration = name
            case "-destination":
                guard let specifier = value() else { return nil }
                destination = specifier
            case "-derivedDataPath":
                guard let path = value() else { return nil }
                derivedDataPath = path
            case "-alltargets":
                allTargets = true
                index += 1
            default:
                return nil
            }
        }
        let selection: BuildSettingsInspector.Selection
        if let scheme {
            guard destination != nil else { return nil }
            selection = .scheme(scheme)
        } else {
            selection = allTargets ? .allTargets : (targets.isEmpty ? .defaultTarget : .targets(targets))
        }
        return BuildSettingsInspector.Invocation(selection: selection, configuration: configuration, destination: destination, derivedDataPath: derivedDataPath)
    }

    private func decode<T: Decodable>(_ path: String) throws -> T {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw NomacError("missing reference file", path: path)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw NomacError("malformed reference file: \(error)", path: path)
        }
    }
}
