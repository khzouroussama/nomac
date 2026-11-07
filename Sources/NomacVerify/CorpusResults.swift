import Foundation
import NomacCore

/// Computes the progress lines from verification reports and renders corpus/RESULTS.md and the
/// progress section of docs/PROGRESS.md.
///
/// Percentages are computed, never estimated, each line by the measure corpus.json gives it
/// (``CorpusManifest/ProgressLine/Measure``): the share of corpus apps whose checks of its kinds
/// all pass, or the share of its kinds' checks across the corpus that pass. A check passes when it
/// is identical or equivalent; a refused, different or unsupported one counts against. A line
/// with no check kind yet is at 0%. A line with a host (the build driver's, `Linux`) counts only
/// the reports `nomac verify` wrote on that system; the Mac's are shown beside it.
public struct CorpusResults: Sendable {
    public typealias Line = CorpusManifest.ProgressLine

    /// How a line was measured: passing apps or checks out of the compared ones.
    public struct Measurement: Sendable, Equatable {
        public var passing: Int
        public var total: Int
        /// The apps whose reports have checks of the line's kinds.
        public var apps: Int

        /// Rounded down to a whole number; 0 when nothing was compared.
        public var percentage: Int { total == 0 ? 0 : passing * 100 / total }
    }

    public var manifest: CorpusManifest
    /// Each app's reports, one per system `nomac verify` ran on. Apps without a report count as
    /// failing every line measured by apps.
    public var reports: [String: [VerificationReport]]

    public init(manifest: CorpusManifest, reports: [VerificationReport]) {
        self.manifest = manifest
        self.reports = Dictionary(grouping: reports, by: \.app)
    }

    /// The report `app` is measured by: with a host, the last one written on that system; without,
    /// the last one written off Linux (on the Mac the references come from), or its only one.
    func report(_ app: String, host: String? = nil) -> VerificationReport? {
        let all = reports[app] ?? []
        if let host { return all.last { $0.host?.system == host } }
        return all.last { $0.host?.system != "Linux" } ?? all.last
    }

    /// The checks of `kinds` that were compared (Xcode's side did not fail), in corpus order.
    func compared(_ kinds: [String], host: String? = nil) -> [VerificationReport.Check] {
        manifest.apps.compactMap { report($0.id, host: host) }.flatMap { $0.checks.filter { kinds.contains($0.kind) && $0.status != .referenceFailed } }
    }

    /// The line as measured from the reports of `host`, by default its own.
    public func measurement(_ line: Line, host: String? = nil) -> Measurement {
        let host = host ?? line.host
        let apps = manifest.apps.filter { report($0.id, host: host)?.checks.contains { line.kinds.contains($0.kind) } ?? false }.count
        switch line.measure {
        case .reports:
            // The harness works for an app when the reference was captured and nomac verified it.
            let verified = manifest.apps.filter { !(report($0.id)?.checks.isEmpty ?? true) }.count
            return Measurement(passing: verified, total: manifest.apps.count, apps: verified)
        case .apps:
            let passing = manifest.apps.filter { report($0.id, host: host)?.passes(kinds: Set(line.kinds)) ?? false }.count
            return Measurement(passing: passing, total: manifest.apps.count, apps: apps)
        case .checks:
            let checks = compared(line.kinds, host: host)
            return Measurement(passing: checks.filter { $0.status == .identical || $0.status == .equivalent }.count, total: checks.count, apps: apps)
        }
    }

    /// The apps whose every build check passes, in the reports of `host`.
    func built(on host: String) -> Int {
        manifest.apps.filter { report($0.id, host: host)?.passes(kinds: ["build"]) ?? false }.count
    }

    /// The line's percentage, rounded down to a whole number.
    public func percentage(_ line: Line) -> Int {
        measurement(line).percentage
    }

    /// The weighted overall percentage, rounded down.
    public var overall: Int {
        let total = manifest.progress.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return 0 }
        return manifest.progress.reduce(0) { $0 + $1.weight * percentage($1) } / total
    }

    /// What a line's percentage is made of, as the progress section prints it.
    func basis(_ line: Line) -> String {
        guard !line.kinds.isEmpty || line.measure == .reports else { return "no check kind yet" }
        let measured = measurement(line)
        switch line.measure {
        case .reports:
            return "\(measured.passing) / \(measured.total) apps verified"
        case .apps:
            return "\(measured.passing) / \(measured.total) apps"
        case .checks:
            let kinds = line.kinds.joined(separator: " and ")
            let on = line.host.map { " on \($0)" } ?? ""
            var text = measured.total > 0
                ? "\(measured.passing) / \(measured.total) \(kinds) checks\(on) in \(Self.apps(measured.apps))"
                : "no \(kinds) checks compared\(on) yet"
            if line.host != nil {
                let mac = measurement(line, host: "macOS")
                if mac.total > 0 { text += " · \(mac.passing) / \(mac.total) on the Mac with Xcode's compilers, in \(Self.apps(mac.apps))" }
            }
            return text
        }
    }

    static func apps(_ count: Int) -> String {
        "\(count) \(count == 1 ? "app" : "apps")"
    }

    /// The progress section of docs/PROGRESS.md (also the first section of docs/STATE.md).
    public func progressSection(date: String) -> String {
        let tested = manifest.apps.filter { report($0.id)?.passes(kinds: ["device"]) ?? false }.count
        let count = manifest.apps.count
        var lines = [
            "## Progress toward \"any Xcode project builds on Linux\"",
            "",
            "Overall: \(overall)% (weighted) · Corpus: \(built(on: "Linux")) / \(count) apps build on Linux "
                + "(\(built(on: "macOS")) / \(count) on the Mac with Xcode's compilers) · \(tested) / \(count) pass their tests on device",
            "",
        ]
        for line in manifest.progress {
            let percent = percentage(line)
            lines.append("- [\(percent == 100 ? "x" : " ")] \(line.title) · \(percent)% · weight \(line.weight) · \(basis(line))")
        }
        lines += ["", "Last updated: \(date) · Full per-app results: corpus/RESULTS.md"]
        return lines.joined(separator: "\n") + "\n"
    }

    /// The check kinds RESULTS.md shows per app beside the loader's, with their column titles and
    /// the system whose reports they read (nil: the app's report from the Mac).
    static let toolColumns: [(kind: String, title: String, host: String?)] = [
        ("strings", "Strings", nil), ("nib", "Nibs", nil), ("assets", "Assets", nil), ("coredata", "Core Data", nil),
        ("signing", "Signing", nil), ("export", "Export", nil),
        ("build", "Build on Linux", "Linux"), ("build", "Build on the Mac (Xcode's compilers)", "macOS"),
        ("extension", "Extensions on Linux", "Linux"),
    ]

    /// corpus/RESULTS.md. `source` says where the reports came from.
    public func resultsMarkdown(date: String, source: String = "the `reference` workflow", runURL: String?) -> String {
        var out = "# Corpus results\n\n"
        out += "Generated by `nomac corpus results` on \(date) from \(source)"
        if let runURL { out += " ([run](\(runURL)))" }
        out += ". Reference: Xcode \(manifest.xcode.version) (\(manifest.xcode.build)).\n\n"
        out += "A check is *identical* when nomac's output matches Xcode's byte for byte after the path rewrites "
        out += "in docs/adr/0004-reference-artifacts.md. *Unsupported* checks use an xcodebuild mode nomac does not "
        out += "reproduce yet and count as failures. *Refused* checks are tasks of Xcode's build whose tool nomac stops "
        out += "on, naming what it does not reproduce yet; they count as failures too. *Reference failed* means Xcode "
        out += "itself failed, or the capture did not keep the files, so nothing was compared. "
        out += "A build product is *equivalent* when it comes from a compiler, has Xcode's structure and differs only in "
        out += "documented ways (docs/adr/0101-compiled-code-and-xcodes-compilers.md); it passes as identical ones do. "
        out += "Each progress line is measured as corpus/corpus.json's `progress` says (docs/VERIFICATION.md \"Progress\").\n\n"
        out += progressSection(date: date) + "\n"
        out += "## Per app\n\n"
        out += "Strings to Build: passing / compared checks (– without an Xcode build capture or such tasks, an archive capture, or a report from that system).\n\n"
        out += "| App | Tier | PIF | Settings identical | Unsupported | Reference failed | Loader | "
        out += Self.toolColumns.map(\.title).joined(separator: " | ") + " |\n"
        out += "|---|---|---|---|---|---|---|" + String(repeating: "---|", count: Self.toolColumns.count) + "\n"
        for app in manifest.apps {
            guard let report = report(app.id) else {
                out += "| \(app.id) | \(app.tier) | no report | – | – | – | ✗ |" + String(repeating: " – |", count: Self.toolColumns.count) + "\n"
                continue
            }
            let pif = report.checks.first { $0.kind == "pif" }?.status.rawValue ?? "–"
            let settings = report.tally(kind: "settings")
            let unsupported = report.checks.filter { $0.status == .unsupported }.count
            let failed = report.checks.filter { $0.status == .referenceFailed }.count
            let loader = report.passes(kinds: ["pif", "settings", "list"]) ? "✓" : "✗"
            let tools = Self.toolColumns.map { column in
                let tally = (column.host == nil ? report : self.report(app.id, host: column.host))?.tally(kind: column.kind)
                return tally.map { $0.total == 0 ? "–" : "\($0.identical + $0.equivalent) / \($0.total)" } ?? "–"
            }
            out += "| \(app.id) | \(app.tier) | \(pif) | \(settings.identical) / \(settings.total) | \(unsupported) | \(failed) | \(loader) | "
            out += tools.joined(separator: " | ") + " |\n"
        }
        out += "\n## Per check kind\n\n| Check kind | Identical | Equivalent | Different | Refused | Compared |\n|---|---|---|---|---|---|\n"
        let kinds = Set(reports.values.flatMap { $0.flatMap { $0.checks.map(\.kind) } }).sorted()
        typealias Row = (name: String, kind: String, host: String?)
        let rows = kinds.flatMap { kind -> [Row] in
            kind == "build" ? [("build on Linux", kind, "Linux"), ("build on the Mac (Xcode's compilers)", kind, "macOS")] : [(kind, kind, nil)]
        }
        for row in rows {
            let checks = compared([row.kind], host: row.host)
            let count = { (status: VerificationReport.Check.Status) in checks.filter { $0.status == status }.count }
            out += "| \(row.name) | \(count(.identical)) | \(count(.equivalent)) | \(count(.different)) | \(count(.refused)) | \(checks.count) |\n"
        }
        return out + refusals()
    }

    /// What nomac's tools refused, by kind and message, most frequent first: what each line needs next.
    func refusals() -> String {
        var counts: [Pair: Int] = [:]
        for check in compared(Self.toolColumns.filter { $0.host == nil }.map(\.kind)) where check.status == .refused {
            counts[Pair(kind: check.kind, message: Self.message(check.detail.dropFirst().first ?? check.detail.first ?? "")), default: 0] += 1
        }
        guard !counts.isEmpty else { return "" }
        var out = "\n## Refusals\n\nWhat nomac's tools stopped on, by kind and message (without the path it names), most frequent first.\n\n"
        out += "| Kind | Checks | Message |\n|---|---|---|\n"
        for (pair, count) in counts.sorted(by: { $0.value != $1.value ? $0.value > $1.value : ($0.key.kind, $0.key.message) < ($1.key.kind, $1.key.message) }) {
            out += "| \(pair.kind) | \(count) | \(pair.message.replacingOccurrences(of: "|", with: "\\|")) |\n"
        }
        return out
    }

    struct Pair: Hashable {
        var kind: String
        var message: String
    }

    /// A refusal's message without the path it starts with (`<path>: error: …`).
    static func message(_ line: String) -> String {
        guard let range = line.range(of: "error: ") else { return line }
        return String(line[range.upperBound...])
    }
}

/// The markers that delimit the generated progress section in docs/PROGRESS.md and docs/STATE.md.
public enum ProgressMarkers {
    public static let begin = "<!-- progress:begin -->"
    public static let end = "<!-- progress:end -->"

    /// Replaces the text between the markers with `section`.
    public static func replace(in text: String, with section: String, path: String) throws -> String {
        guard let start = text.range(of: begin), let stop = text.range(of: end), start.upperBound <= stop.lowerBound else {
            throw NomacError("the file has no \(begin) … \(end) section", path: path)
        }
        return String(text[..<start.upperBound]) + "\n" + section + String(text[stop.lowerBound...])
    }
}
