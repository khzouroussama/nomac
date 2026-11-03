import Foundation

/// The result of verifying one corpus app against its Xcode reference (`nomac verify --report`).
public struct VerificationReport: Codable, Sendable, Equatable {
    /// The outcome for one captured artifact.
    public struct Check: Codable, Sendable, Equatable {
        public enum Status: String, Codable, Sendable {
            case identical
            /// A compiled build product with Xcode's structure, whose every difference is
            /// documented (ADR 0101), a tool's output that differs only by a documented cause, or
            /// settings whose only difference is an order xcodebuild changes from one run to the next.
            case equivalent
            case different
            /// The capture uses an xcodebuild mode nomac does not reproduce yet.
            case unsupported
            /// nomac's tool stopped on an input or option it does not reproduce yet; counts
            /// against the component, as a difference does.
            case refused
            /// The reference has nothing to compare (no PIF was captured).
            case referenceFailed
        }

        /// The kind of artifact: `pif`, `list`, `settings`, `build`, `envelope`, the tool checks
        /// `strings`, `nib`, `assets` and `coredata`, and `signing` and `export` (docs/VERIFICATION.md).
        public var kind: String
        public var name: String
        public var status: Status
        public var detail: [String]

        public init(kind: String, name: String, status: Status, detail: [String]) {
            self.kind = kind
            self.name = name
            self.status = status
            self.detail = detail
        }
    }

    /// Where `nomac verify` ran, and so whose compilers and tools built for its `build` checks.
    public struct Host: Codable, Sendable, Equatable {
        /// `macOS` or `Linux`.
        public var system: String
        /// `xcode`: `nomac build` ran the developer directory's compilers and tools, Xcode's on a
        /// Mac. `nomac`: the swift.org toolchain, the LLVM tools and nomac's own tools that
        /// `nomac toolchain install` puts in the developer directory, as on Linux.
        public var toolchain: String

        public init(system: String, toolchain: String) {
            self.system = system
            self.toolchain = toolchain
        }

        /// This machine.
        public static var current: Host {
            #if os(macOS)
            Host(system: "macOS", toolchain: "xcode")
            #else
            Host(system: "Linux", toolchain: "nomac")
            #endif
        }
    }

    public var app: String
    public var xcodeBuild: String
    /// nil in reports written before it was recorded.
    public var host: Host?
    public var checks: [Check]

    public init(app: String, xcodeBuild: String, host: Host? = nil, checks: [Check]) {
        self.app = app
        self.xcodeBuild = xcodeBuild
        self.host = host
        self.checks = checks
    }

    /// Counts for one kind: identical checks, equivalent ones, and checks that could be compared.
    public func tally(kind: String) -> (identical: Int, equivalent: Int, total: Int) {
        let relevant = checks.filter { $0.kind == kind && $0.status != .referenceFailed }
        return (relevant.filter { $0.status == .identical }.count, relevant.filter { $0.status == .equivalent }.count, relevant.count)
    }

    /// `true` when every comparable check of the given kinds is identical or equivalent (and there is one).
    public func passes(kinds: Set<String>) -> Bool {
        let relevant = checks.filter { kinds.contains($0.kind) && $0.status != .referenceFailed }
        return !relevant.isEmpty && relevant.allSatisfy { $0.status == .identical || $0.status == .equivalent }
    }
}

extension VerificationReport {
    /// The `envelope` check (docs/adr/0011-feature-envelope.md). An app whose every feature is inside the
    /// envelope must match Xcode in every comparison: otherwise a verified feature hides a
    /// difference, and the check fails. An app with features outside the envelope lists them:
    /// when it matches Xcode everywhere, its unknown ones are what it would add to the envelope.
    /// - Parameters:
    ///   - unknown: the features the envelope does not list.
    ///   - unverified: the features the envelope lists as unverified (known differences win over
    ///     an app that happens to match).
    ///   - comparisons: the app's other checks.
    public static func envelopeCheck(unknown: [String], unverified: [String], comparisons: [Check], listed: Int = 10) -> Check {
        let differing = comparisons.filter { $0.status == .different || $0.status == .unsupported }
        guard unknown.isEmpty && unverified.isEmpty else {
            var detail = ["features outside the envelope: \(unknown.count + unverified.count)"]
            if differing.isEmpty && !unknown.isEmpty {
                detail.append("every comparison is identical: the app verifies its \(unknown.count) unknown ones")
            }
            detail += (unverified.sorted().prefix(listed).map { "unverified \($0)" } + unknown.sorted().prefix(listed).map { "unknown \($0)" })
            return Check(kind: "envelope", name: "features", status: .identical, detail: detail)
        }
        guard differing.isEmpty else {
            let kinds = Set(differing.map(\.kind)).sorted().joined(separator: ", ")
            return Check(kind: "envelope", name: "features", status: .different,
                         detail: ["every feature is inside the envelope, yet \(kinds) differ from Xcode: a verified feature hides a difference"]
                             + differing.prefix(listed).map { "\($0.kind) \($0.name)" })
        }
        return Check(kind: "envelope", name: "features", status: .identical, detail: ["every feature is inside the envelope"])
    }
}
