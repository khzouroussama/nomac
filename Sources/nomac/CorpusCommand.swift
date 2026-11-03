import ArgumentParser
import Foundation
import NomacCore
import NomacVerify

/// `nomac corpus`: corpus bookkeeping.
struct CorpusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "corpus",
        abstract: "Work with the verification corpus.",
        subcommands: [Results.self]
    )

    struct Results: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Render corpus/RESULTS.md and the progress section of docs/PROGRESS.md from 'nomac verify' reports.")

        @Option(help: "The corpus manifest.")
        var manifest = "corpus/corpus.json"

        @Option(help: "A directory of 'nomac verify --report' JSON files (searched recursively).")
        var reports: String

        @Option(help: "Write RESULTS.md here.")
        var output: String?

        @Option(help: "Write the progress section (docs/PROGRESS.md) here.")
        var progress: String?

        @Option(help: "The date to print, YYYY-MM-DD (default: today, UTC).")
        var date: String?

        @Option(help: "Where the reports came from, as RESULTS.md says it.")
        var source = "the `reference` workflow"

        @Option(help: "A link to the workflow run the reports came from.")
        var runURL: String?

        @Option(name: .customLong("update"), help: "A file whose progress section (between <!-- progress:begin --> and <!-- progress:end -->) is replaced (repeatable).")
        var updates: [String] = []

        func run() throws {
            let loaded = try CorpusManifest.load(path: FileSystem.absolute(manifest))
            var found: [VerificationReport] = []
            let root = FileSystem.absolute(reports)
            let enumerator = FileManager.default.enumerator(atPath: root)
            while let relative = enumerator?.nextObject() as? String {
                guard relative.hasSuffix(".json"), let data = FileManager.default.contents(atPath: root + "/" + relative) else { continue }
                if let report = try? JSONDecoder().decode(VerificationReport.self, from: data) {
                    found.append(report)
                }
            }
            let results = CorpusResults(manifest: loaded, reports: found)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "UTC")
            let day = date ?? formatter.string(from: Date())
            let markdown = results.resultsMarkdown(date: day, source: source, runURL: runURL)
            if let output {
                try FileSystem.write(Data(markdown.utf8), to: FileSystem.absolute(output))
            } else {
                print(markdown, terminator: "")
            }
            let section = results.progressSection(date: day)
            if let progress {
                try FileSystem.write(Data(section.utf8), to: FileSystem.absolute(progress))
            }
            for file in updates {
                let path = FileSystem.absolute(file)
                guard let data = FileManager.default.contents(atPath: path) else {
                    throw NomacError("could not read the file to update", path: path)
                }
                let updated = try ProgressMarkers.replace(in: String(decoding: data, as: UTF8.self), with: section, path: path)
                try FileSystem.write(Data(updated.utf8), to: path)
            }
        }
    }
}
