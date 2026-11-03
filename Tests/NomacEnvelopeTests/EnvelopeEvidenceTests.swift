import Foundation
@testable import NomacEnvelope
import Testing

/// The envelope cites only evidence that exists: corpus apps, experiments, BACKLOG items.
struct EnvelopeEvidenceTests {
    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func read(_ path: String) throws -> String {
        try String(contentsOf: repository.appendingPathComponent(path), encoding: .utf8)
    }

    static func experimentNames(_ script: String) throws -> Set<String> {
        let source = try read(".github/scripts/" + script)
        let expression = try NSRegularExpression(pattern: #"^\s*"([a-z0-9-]+)"\s*:\s*\("#, options: .anchorsMatchLines)
        return Set(expression.matches(in: source, range: NSRange(source.startIndex..., in: source)).compactMap {
            Range($0.range(at: 1), in: source).map { String(source[$0]) }
        })
    }

    @Test func everyCitationResolves() throws {
        let corpus = try JSONSerialization.jsonObject(with: Data(try Self.read("corpus/corpus.json").utf8)) as? [String: Any]
        let apps = Set((corpus?["apps"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String })
        let backlog = try Self.read("docs/BACKLOG.md")
        let packageExperiments = try Self.read(".github/scripts/package_experiments.py")
        let experiments = ["loader-experiments": try Self.experimentNames("loader_experiments.py"), "pif-experiments": try Self.experimentNames("pif_experiments.py"),
                           "envelope-experiments": try Self.experimentNames("envelope_experiments.py")]
        #expect(experiments.values.allSatisfy { $0.count > 5 })
        for entry in LoaderEnvelope.envelope.entries.values {
            if entry.status == .verified { #expect(!entry.evidence.isEmpty, "\(entry.feature)") }
            for evidence in entry.evidence {
                let parts = evidence.split(separator: ":", maxSplits: 1).map(String.init)
                switch parts.first {
                case "corpus":
                    #expect(apps.contains(parts[1]), "\(entry.feature): \(evidence)")
                case "loader-experiments", "pif-experiments", "envelope-experiments":
                    #expect(experiments[parts[0]]!.contains(parts[1]), "\(entry.feature): \(evidence)")
                case "package-experiments":
                    #expect(packageExperiments.contains("- \(parts[1]):"), "\(entry.feature): \(evidence)")
                default:
                    #expect(evidence.hasPrefix("B-") && backlog.contains("| \(evidence) |"), "\(entry.feature): \(evidence)")
                }
            }
            if entry.status == .unverified { #expect(entry.note != nil, "\(entry.feature)") }
        }
    }

    @Test func fileTypesAreTheExperimentsOwn() throws {
        let source = try Self.read(".github/scripts/loader_experiments.py")
        let start = try #require(source.range(of: "ENCODED_FILE_TYPES = ["))
        let end = try #require(source.range(of: "\n]\n", range: start.upperBound..<source.endIndex))
        let list = String(source[start.upperBound..<end.lowerBound])
        let types = try NSRegularExpression(pattern: #""([^"]+)""#).matches(in: list, range: NSRange(list.startIndex..., in: list)).compactMap {
            Range($0.range(at: 1), in: list).map { String(list[$0]) }
        }
        #expect(types == LoaderEnvelope.experimentFileTypes)
        for compiler in LoaderEnvelope.experimentCompilers {
            #expect(source.contains("\"\(compiler)\""), "\(compiler)")
        }
    }
}
