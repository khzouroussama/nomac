import Foundation

/// The result of `nomac check`: every feature a project uses, each with its envelope status and
/// the places it is used (docs/formats/check.md).
public struct CheckReport: Sendable {
    public enum Status: String, Sendable, Codable {
        case verified, unverified, unknown
    }

    public struct Feature: Sendable {
        public var id: String
        public var domain: String
        public var status: Status
        public var evidence: [String]
        public var note: String?
        public var uses: [FeatureUse]
    }

    /// A project fix a Linux build applies to the project (ADR 0184): no problem, so outside the count
    /// of features and the exit status.
    public struct Fix: Sendable {
        public var id: String
        public var tool: String
        public var change: String
        public var why: String
        public var dropWhen: String
        public var upstream: String?
        public var uses: [FeatureUse]

        public init(id: String, tool: String, change: String, why: String, dropWhen: String, upstream: String?, uses: [FeatureUse]) {
            self.id = id
            self.tool = tool
            self.change = change
            self.why = why
            self.dropWhen = dropWhen
            self.upstream = upstream
            self.uses = uses
        }
    }

    public static let projectCompatibilityDocument = "https://github.com/khzouroussama/nomac/blob/main/docs/PROJECT-COMPATIBILITY.md"

    public var container: String
    public var descriptionOnly: Bool
    public var features: [Feature]
    public var unchecked: [String: [UncheckedPart]]
    public var fixes: [Fix] = []

    /// The features outside the envelope: unverified and unknown ones.
    public var outside: [Feature] { features.filter { $0.status != .verified } }

    public static func make(container: String, domains: [any FeatureDomain], options: CheckOptions) -> CheckReport {
        var features: [Feature] = []
        var unchecked: [String: [UncheckedPart]] = [:]
        for domain in domains {
            let scan: DomainScan
            do {
                scan = try domain.scan(container, options: options)
            } catch {
                // A domain that cannot read the container leaves the project outside its envelope,
                // and the other domains still report.
                let use = FeatureUse(feature: "\(domain.name):scan=failed", file: container, object: "\(error)")
                scan = DomainScan(uses: [use], unchecked: [])
            }
            for (id, uses) in Dictionary(grouping: scan.uses, by: \.feature) {
                let entry = domain.envelope.entry(for: id)
                features.append(Feature(id: id, domain: domain.name, status: entry.map { Status(rawValue: $0.status.rawValue)! } ?? .unknown,
                                        evidence: entry?.evidence ?? [], note: entry?.note, uses: Array(Set(uses)).sorted()))
            }
            unchecked[domain.name] = Array(Set(scan.unchecked)).sorted()
        }
        features.sort { ($0.domain, $0.id) < ($1.domain, $1.id) }
        return CheckReport(container: container, descriptionOnly: options.descriptionOnly, features: features, unchecked: unchecked)
    }

    /// Paths are written relative to the folder that holds the container, with `..` for those
    /// outside it (a project's `node_modules` beside its `ios` folder).
    private var root: String { (container as NSString).deletingLastPathComponent }

    private func relative(_ path: String) -> String {
        guard path.hasPrefix("/"), root.hasPrefix("/") else { return path }
        let from = (root as NSString).pathComponents, to = (path as NSString).pathComponents
        let common = zip(from, to).prefix { $0 == $1 }.count
        guard common > 1 else { return path }
        return (Array(repeating: "..", count: from.count - common) + to.dropFirst(common)).joined(separator: "/")
    }

    // MARK: Text

    public func text(all: Bool = false, usesPerFeature: Int = 5) -> String {
        let counts = Dictionary(grouping: features, by: \.status).mapValues(\.count)
        var lines = ["\(relative(container)): \(features.count) features used, \(counts[.verified] ?? 0) verified, "
            + "\(counts[.unverified] ?? 0) unverified, \(counts[.unknown] ?? 0) unknown"]
        let listed = all ? features : outside
        if !listed.isEmpty {
            lines.append("")
            lines.append(all ? "Features:" : "Outside the envelope:")
        }
        for feature in listed {
            lines.append("  \(feature.status.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)) \(feature.id)")
            if let note = feature.note { lines.append("      \(note)") }
            if !feature.evidence.isEmpty { lines.append("      evidence: \(feature.evidence.joined(separator: ", "))") }
            guard feature.status != .verified else { continue }
            for use in Self.sample(feature.uses, count: usesPerFeature) {
                lines.append("      \(relative(use.file)): \(use.object)")
            }
            if feature.uses.count > usesPerFeature {
                lines.append("      and \(feature.uses.count - usesPerFeature) more")
            }
        }
        let parts = unchecked.flatMap { domain, parts in parts.map { (domain, $0) } }.sorted { ($0.0, $0.1) < ($1.0, $1.1) }
        if !parts.isEmpty {
            lines.append("")
            lines.append("Not checked:")
            for (domain, part) in parts {
                lines.append("  \(domain): \(part.what): \(relative(part.file))")
            }
        }
        if !fixes.isEmpty {
            lines.append("")
            lines.append("Project fixes a Linux build applies to this project (not problems; they do not change the exit status):")
            for fix in fixes {
                lines.append("  \(fix.id): \(fix.tool)")
                lines.append("      \(fix.change)")
                for use in Self.sample(fix.uses, count: usesPerFeature) {
                    lines.append("      \(relative(use.file)): \(use.object)")
                }
                if fix.uses.count > usesPerFeature {
                    lines.append("      and \(fix.uses.count - usesPerFeature) more")
                }
            }
            lines.append("  Why, your files stay as they are, and 'nomac build --no-project-fixes': \(Self.projectCompatibilityDocument)")
        }
        lines.append("")
        lines.append(outside.isEmpty ? "Every feature is inside the envelope." : "\(outside.count) of \(features.count) features are outside the envelope.")
        return lines.joined(separator: "\n") + "\n"
    }

    /// `count` of `uses` in their order, each object's first use before any repeated object.
    static func sample(_ uses: [FeatureUse], count: Int) -> [FeatureUse] {
        var objects = Set<String>()
        let firsts = uses.indices.filter { objects.insert(uses[$0].object).inserted }
        let first = Set(firsts)
        let repeats = uses.indices.filter { !first.contains($0) }
        return (firsts + repeats).prefix(count).sorted().map { uses[$0] }
    }

    // MARK: JSON

    private struct JSONReport: Encodable {
        struct Use: Encodable {
            var file: String
            var object: String
        }

        struct Feature: Encodable {
            var id: String
            var domain: String
            var status: Status
            var evidence: [String]?
            var note: String?
            var count: Int
            var uses: [Use]?
        }

        struct Part: Encodable {
            var domain: String
            var what: String
            var file: String
        }

        struct Fix: Encodable {
            var id: String
            var tool: String
            var change: String
            var why: String
            var dropWhen: String
            var upstream: String?
            var uses: [Use]
        }

        var container: String
        var descriptionOnly: Bool
        var inside: Bool
        var outside: Int
        var features: [Feature]
        var unchecked: [Part]
        var projectFixes: [Fix]
    }

    /// Uses are listed for features outside the envelope; verified ones give their count only.
    public func json() throws -> String {
        let report = JSONReport(
            container: relative(container),
            descriptionOnly: descriptionOnly,
            inside: outside.isEmpty,
            outside: outside.count,
            features: features.map { feature in
                JSONReport.Feature(id: feature.id, domain: feature.domain, status: feature.status,
                                   evidence: feature.evidence.isEmpty ? nil : feature.evidence, note: feature.note, count: feature.uses.count,
                                   uses: feature.status == .verified ? nil : feature.uses.map { JSONReport.Use(file: relative($0.file), object: $0.object) })
            },
            unchecked: unchecked.flatMap { domain, parts in parts.map { JSONReport.Part(domain: domain, what: $0.what, file: relative($0.file)) } }
                .sorted { ($0.domain, $0.what, $0.file) < ($1.domain, $1.what, $1.file) },
            projectFixes: fixes.map { fix in
                JSONReport.Fix(id: fix.id, tool: fix.tool, change: fix.change, why: fix.why, dropWhen: fix.dropWhen, upstream: fix.upstream,
                               uses: fix.uses.map { JSONReport.Use(file: relative($0.file), object: $0.object) })
            })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(report), as: UTF8.self) + "\n"
    }

    // MARK: The envelope itself

    /// Every entry of the domains' envelopes, as `nomac check --envelope` prints them.
    public static func envelopeText(_ domains: [any FeatureDomain]) -> String {
        var lines: [String] = []
        for domain in domains {
            let entries = domain.envelope.entries.values.sorted { $0.feature < $1.feature }
            let verified = entries.filter { $0.status == .verified }.count
            lines.append("\(domain.name): \(verified) verified, \(entries.count - verified) unverified")
            for entry in entries {
                var line = "  \(entry.status.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)) \(entry.feature)"
                if !entry.evidence.isEmpty { line += "  [\(entry.evidence.joined(separator: ", "))]" }
                lines.append(line)
                if let note = entry.note { lines.append("      \(note)") }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
