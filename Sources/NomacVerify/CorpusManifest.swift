import Foundation
import NomacCore

/// `corpus/corpus.json`: the reference Xcode and the corpus apps (see corpus/README.md).
public struct CorpusManifest: Codable, Sendable, Equatable {
    public struct Xcode: Codable, Sendable, Equatable {
        public var version: String
        public var build: String
        public var runner: String
        public var path: String
    }

    public struct BuildEntry: Codable, Sendable, Equatable {
        public var scheme: String
        public var configuration: String?
        public var settings: [String: String]?
    }

    public struct TestEntry: Codable, Sendable, Equatable {
        public var scheme: String
    }

    public struct App: Codable, Sendable, Equatable {
        public var id: String
        public var name: String
        public var repository: String
        public var commit: String
        public var license: String
        public var container: String
        public var tier: String
        public var submodules: Bool
        public var prepare: [String]
        public var build: BuildEntry?
        public var test: TestEntry?
        public var exercises: [String]
        public var notes: String
    }

    /// A line of the progress list (docs/PROGRESS.md): its weight in the overall figure and the check kinds
    /// that measure it (docs/VERIFICATION.md "Progress").
    public struct ProgressLine: Codable, Sendable, Equatable {
        public enum Measure: String, Codable, Sendable {
            /// The share of corpus apps whose every check of the kinds passes.
            case apps
            /// The share of the kinds' checks across the corpus that pass.
            case checks
            /// The share of corpus apps with a verification report.
            case reports
        }

        public var title: String
        public var weight: Int
        public var kinds: [String]
        public var measure: Measure
        /// When set (`Linux`), only the reports `nomac verify` wrote on that system count for the
        /// line: the build driver's goal is a build on Linux, and a Mac build runs Xcode's compilers.
        public var host: String?
    }

    public var schemaVersion: Int
    public var xcode: Xcode
    public var progress: [ProgressLine]
    public var apps: [App]

    public static func load(path: String) throws -> CorpusManifest {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw NomacError("could not read the corpus manifest", path: path)
        }
        do {
            return try JSONDecoder().decode(CorpusManifest.self, from: data)
        } catch {
            throw NomacError("malformed corpus manifest: \(error)", path: path)
        }
    }
}
