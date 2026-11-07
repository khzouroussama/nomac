import ArgumentParser
import Foundation
import NomacBuild
import NomacCore
import NomacEnvelope
import NomacInspect
import NomacSDK
import NomacVerify

/// `nomac verify`: compare nomac's output with an Xcode reference capture.
struct VerifyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "verify",
        abstract: "Compare nomac's output for an app with Xcode's.",
        discussion: """
        <reference> is one app's directory from a 'reference' workflow artifact. <source> is \
        a checkout of the same app at the same commit. Every artifact nomac can produce is \
        regenerated and compared byte for byte after the path rewrites defined in \
        docs/adr/0004-reference-artifacts.md. The envelope check fails when every feature of \
        the app is inside the envelope and anything differs (docs/adr/0011-feature-envelope.md). \
        When the reference has an Xcode build, each of its tasks that runs a tool nomac \
        reimplements (strings, nibs, asset catalogs, Core Data models) is run again with nomac's \
        tool and its outputs compared byte for byte; when it has an ad-hoc archive, each codesign \
        step is replayed with nomac's codesign and the archive exported with nomac's export. \
        With --build, the app is also built as the reference built it, at the same derived-data \
        path, and its products are compared: compiled files by structure, the others byte for \
        byte (docs/adr/0101-compiled-code-and-xcodes-compilers.md). Exits with status 1 if \
        anything differs.
        """
    )

    @Argument(help: "The reference capture directory for one app.")
    var reference: String

    @Option(help: "The app's checkout (default: the path recorded in the reference).")
    var source: String?

    @Option(name: .customLong("developer-dir"), help: "An Xcode Contents/Developer directory (default: $NOMAC_DEVELOPER_DIR, else the selected 'nomac sdk' install).")
    var developerDir: String?
    @Flag(name: .customLong("strict-xcode"), help: XcodeCheck.strictHelp)
    var strictXcode = false

    @Option(help: "Write the full report as JSON to this file.")
    var report: String?

    @Flag(help: "Also build the app as the reference's build capture did, and compare the products.")
    var build = false

    @Flag(help: "With --build, run the tasks that do not depend on a failed one, so that their products are compared too.")
    var continueBuildingAfterErrors = false

    func run() async throws {
        let referenceDirectory = FileSystem.absolute(reference)
        let sourceRoot: String
        if let source {
            sourceRoot = FileSystem.absolute(source)
        } else {
            struct SourceRecord: Decodable { var path: String }
            guard let data = FileManager.default.contents(atPath: referenceDirectory + "/source.json") else {
                throw NomacError("missing source.json; pass --source", path: referenceDirectory)
            }
            sourceRoot = try JSONDecoder().decode(SourceRecord.self, from: data).path
        }
        let developer = try DeveloperDirectory.resolve(option: developerDir, strictXcode: strictXcode)
        let verifier = ReferenceVerifier(
            referenceDirectory: referenceDirectory,
            sourceRoot: sourceRoot,
            developerDirectory: developer,
            scratchDirectory: SDKStore.default().root + "/scratch",
            envelope: { container, sourcePackages in
                let options = CheckOptions(sourcePackages: FileSystem.isDirectory(sourcePackages) ? sourcePackages : nil)
                // The domain whose outputs verify compares (pif, list, settings): another domain's
                // features outside its envelope must not hide a loader difference.
                let outside = CheckReport.make(container: container, domains: [LoaderDomain()], options: options).outside
                return (outside.filter { $0.status == .unknown }.map(\.id), outside.filter { $0.status == .unverified }.map(\.id))
            })
        var result = try await verifier.run()
        result.host = .current
        let scratch = SDKStore.default().root + "/scratch"
        let nomac = FileSystem.resolvingSymbolicLinks(Bundle.main.executablePath ?? CommandLine.arguments[0])
        result.checks += try ToolVerification(
            referenceDirectory: referenceDirectory, sourceRoot: sourceRoot, developerDirectory: developer,
            nomacExecutable: nomac,
            scratchDirectory: scratch + "/tools-\(result.app)").checks()
        result.checks += try ArchiveVerification(
            referenceDirectory: referenceDirectory,
            nomacExecutable: nomac,
            scratchDirectory: scratch + "/archive-\(result.app)").checks()
        if build {
            result.checks += try BuildVerification(
                referenceDirectory: referenceDirectory, sourceRoot: sourceRoot, developerDirectory: developer,
                nomacExecutable: nomac,
                logPath: scratch + "/build-\(result.app).log", continueBuildingAfterErrors: continueBuildingAfterErrors).checks()
            result.checks += try ArchiveBuildVerification(
                referenceDirectory: referenceDirectory, sourceRoot: sourceRoot, developerDirectory: developer,
                nomacExecutable: nomac, scratchDirectory: scratch + "/archive-build-\(result.app)",
                continueBuildingAfterErrors: continueBuildingAfterErrors).checks()
        }
        for check in result.checks {
            print("[\(check.status.rawValue)] \(check.kind) \(check.name)")
            for line in check.detail {
                print("    " + line.replacingOccurrences(of: "\n", with: "\n    "))
            }
        }
        for kind in ["pif", "list", "settings"] {
            let tally = result.tally(kind: kind)
            print("\(result.app) \(kind): \(tally.identical)/\(tally.total) identical" + (tally.equivalent > 0 ? ", \(tally.equivalent) equivalent" : ""))
        }
        for kind in ["strings", "nib", "assets", "coredata", "signing", "export"] + (build ? ["build", "archive", "ipa", "extension"] : []) where result.checks.contains(where: { $0.kind == kind }) {
            let tally = result.tally(kind: kind)
            let refused = result.checks.filter { $0.kind == kind && $0.status == .refused }.count
            print("\(result.app) \(kind): \(tally.identical)/\(tally.total) identical, \(tally.equivalent) equivalent, \(refused) refused")
        }
        if let report {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try FileSystem.write(try encoder.encode(result), to: FileSystem.absolute(report))
        }
        if result.checks.contains(where: { [.different, .unsupported, .refused].contains($0.status) }) {
            throw ExitCode(1)
        }
    }
}
