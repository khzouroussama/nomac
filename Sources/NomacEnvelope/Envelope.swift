import Foundation

/// Where a project uses a feature: a file and the object in it.
public struct FeatureUse: Hashable, Sendable, Comparable {
    /// The feature's identifier (docs/formats/check.md "Feature identifiers").
    public var feature: String
    /// Absolute path of the file that uses it.
    public var file: String
    /// The object in that file: `PBXNativeTarget 1D60… (App)`, `Scheme/BuildAction`, `line 12`.
    public var object: String

    public init(feature: String, file: String, object: String) {
        self.feature = feature
        self.file = file
        self.object = object
    }

    public static func < (a: FeatureUse, b: FeatureUse) -> Bool {
        (a.feature, a.file, a.object) < (b.feature, b.file, b.object)
    }
}

/// What nomac knows about one feature (docs/adr/0011-feature-envelope.md).
public struct EnvelopeEntry: Sendable, Equatable {
    public enum Status: String, Sendable, Codable {
        /// nomac's output for the feature matched Xcode's in a documented comparison.
        case verified
        /// nomac handles the feature but no comparison has confirmed it, or one showed a difference.
        case unverified
    }

    public var feature: String
    public var status: Status
    /// For a verified feature, where it matched: `corpus:<app>`, `<experiment script>:<name>`,
    /// `adr:<number>`. For an unverified one, the BACKLOG item or the reason.
    public var evidence: [String]
    public var note: String?

    public init(feature: String, status: Status, evidence: [String], note: String? = nil) {
        self.feature = feature
        self.status = status
        self.evidence = evidence
        self.note = note
    }

    public static func verified(_ feature: String, _ evidence: String...) -> EnvelopeEntry {
        EnvelopeEntry(feature: feature, status: .verified, evidence: evidence)
    }

    public static func unverified(_ feature: String, _ note: String, backlog: String? = nil) -> EnvelopeEntry {
        EnvelopeEntry(feature: feature, status: .unverified, evidence: backlog.map { [$0] } ?? [], note: note)
    }
}

/// The features of one domain whose handling nomac knows, verified or not. A feature the envelope
/// does not list is unknown, and outside it like an unverified one.
public struct Envelope: Sendable {
    public let domain: String
    public let entries: [String: EnvelopeEntry]
    /// Classifies features of a family too large to list, such as every host condition a
    /// package manifest can test; asked only for features `entries` lacks.
    public let family: (@Sendable (String) -> EnvelopeEntry?)?

    /// Several entries for one feature merge their evidence; an unverified entry wins over
    /// verified ones, so a known difference is never hidden by a corpus app that matched.
    public init(domain: String, entries: [EnvelopeEntry], family: (@Sendable (String) -> EnvelopeEntry?)? = nil) {
        self.domain = domain
        self.family = family
        var merged: [String: EnvelopeEntry] = [:]
        for entry in entries {
            guard var existing = merged[entry.feature] else {
                merged[entry.feature] = entry
                continue
            }
            if entry.status == .unverified && existing.status == .verified {
                merged[entry.feature] = entry
                continue
            }
            if entry.status == existing.status {
                existing.evidence += entry.evidence.filter { !existing.evidence.contains($0) }
                existing.note = existing.note ?? entry.note
                merged[entry.feature] = existing
            }
        }
        self.entries = merged
    }

    public func entry(for feature: String) -> EnvelopeEntry? {
        entries[feature] ?? family?(feature)
    }
}

/// Options shared by every domain.
public struct CheckOptions: Sendable {
    /// The checkout holds only project-description files (ADR 0011): features that depend on
    /// other files, such as the contents of synchronized folders, are listed as not checked.
    public var descriptionOnly: Bool
    /// A `SourcePackages` folder with the checkouts of the workspace's remote packages.
    public var sourcePackages: String?

    public init(descriptionOnly: Bool = false, sourcePackages: String? = nil) {
        self.descriptionOnly = descriptionOnly
        self.sourcePackages = sourcePackages
    }
}

/// A part of the project a domain did not read, so its features are not reported.
public struct UncheckedPart: Hashable, Sendable, Comparable {
    public var what: String
    public var file: String

    public init(what: String, file: String) {
        self.what = what
        self.file = file
    }

    public static func < (a: UncheckedPart, b: UncheckedPart) -> Bool { (a.what, a.file) < (b.what, b.file) }
}

/// What a domain found in a project.
public struct DomainScan: Sendable {
    public var uses: [FeatureUse]
    public var unchecked: [UncheckedPart]

    public init(uses: [FeatureUse] = [], unchecked: [UncheckedPart] = []) {
        self.uses = uses
        self.unchecked = unchecked
    }
}

/// One area of what nomac reproduces (the loader, asset catalogs, nibs, signing, ...): the
/// features a project uses there and the envelope that classifies them.
public protocol FeatureDomain: Sendable {
    var name: String { get }
    var envelope: Envelope { get }
    /// The features the project or workspace at `container` uses.
    func scan(_ container: String, options: CheckOptions) throws -> DomainScan
}
