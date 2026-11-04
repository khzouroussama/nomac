import Foundation
import NomacCore
import NomacVerify

/// `nomac verify --build` of a reference with an archive capture (`archive/`,
/// corpus/scripts/capture_reference.py --archive): archives the app with `nomac archive` as the
/// capture's xcodebuild did (`archive/archive.log.cmd`, at the same derived-data path, with nomac's
/// codesign for the capture's recording wrapper), exports that archive with `nomac export` and
/// the capture's export options, and compares both with Xcode's (docs/VERIFICATION.md "Archives
/// that nomac built"): the `.xcarchive`'s `Info.plist` but its `CreationDate`, its products,
/// dSYMs and signature records by ``BuildProducts``' rules, and the export's files, an IPA by its
/// entries.
public struct ArchiveBuildVerification {
    public typealias Check = VerificationReport.Check

    public var referenceDirectory: String
    public var sourceRoot: String
    public var developerDirectory: String
    public var nomacExecutable: String
    /// Where nomac's archive, export and extracted IPAs go; emptied first.
    public var scratchDirectory: String
    public var detailLimit: Int
    public var continueBuildingAfterErrors: Bool

    public init(referenceDirectory: String, sourceRoot: String, developerDirectory: String, nomacExecutable: String, scratchDirectory: String,
                detailLimit: Int = 40, continueBuildingAfterErrors: Bool = false) {
        self.referenceDirectory = referenceDirectory
        self.sourceRoot = sourceRoot
        self.developerDirectory = developerDirectory
        self.nomacExecutable = nomacExecutable
        self.scratchDirectory = scratchDirectory
        self.detailLimit = detailLimit
        self.continueBuildingAfterErrors = continueBuildingAfterErrors
    }

    /// The `archive` checks (the archive build, `Info.plist`, each product and dSYM), then the
    /// `ipa` checks (the export); none without an archive capture.
    public func checks() throws -> [Check] {
        let capture = referenceDirectory + "/archive"
        guard let data = FileSystem.contents(atPath: capture + "/archive.log.cmd") else { return [] }
        let record = try JSONDecoder().decode(BuildVerification.CommandRecord.self, from: data)
        guard let sourceData = FileSystem.contents(atPath: referenceDirectory + "/source.json") else {
            throw NomacError("missing source.json", path: referenceDirectory)
        }
        let source = try JSONDecoder().decode(BuildVerification.SourceRecord.self, from: sourceData)
        guard record.exitStatus == 0 else { return [try refusalCheck(record, capture: capture, source: source)] }
        guard let xcodeArchive = try FileSystem.sortedContents(of: capture).first(where: { $0.hasSuffix(".xcarchive") }) else {
            return [Check(kind: "archive", name: "archive", status: .referenceFailed, detail: ["the capture has no .xcarchive"])]
        }
        let ours = scratchDirectory + "/" + xcodeArchive
        let (result, logPath) = try archive(record, source: source, archivePath: ours, continueAfterErrors: continueBuildingAfterErrors)
        var checks = [Check(kind: "archive", name: "archive", status: result.exitStatus == 0 ? .identical : .different,
                            detail: result.exitStatus == 0 ? [] : ["nomac archive exited with status \(result.exitStatus) (\(logPath))"]
                                + BuildVerification.failureSummary(result.outputString))]
        guard FileSystem.isDirectory(ours) else { return checks }
        checks.append(infoCheck(capture + "/" + xcodeArchive + "/Info.plist", ours + "/Info.plist"))
        for folder in ["Products", "dSYMs", "Signatures"] where FileSystem.isDirectory(capture + "/" + xcodeArchive + "/" + folder) || FileSystem.isDirectory(ours + "/" + folder) {
            let results = try Self.compareSigned(reference: capture + "/" + xcodeArchive + "/" + folder, other: ours + "/" + folder)
            checks += BuildVerification.productChecks(results.map { BuildProducts.FileResult(path: folder + "/" + $0.path, outcome: $0.outcome) },
                                                      kind: "archive", depth: folder == "Products" ? 3 : 2, detailLimit: detailLimit)
        }
        checks += try exportChecks(capture: capture, archive: ours)
        return checks
    }

    /// `nomac archive` with the capture's arguments into `archivePath`, in an emptied scratch
    /// folder and derived-data path; its output goes to `archive.log` there.
    func archive(_ record: BuildVerification.CommandRecord, source: BuildVerification.SourceRecord, archivePath: String,
                 continueAfterErrors: Bool) throws -> (Subprocess.Result, String) {
        let manager = FileManager.default
        if manager.fileExists(atPath: scratchDirectory) { try manager.removeItem(atPath: scratchDirectory) }
        try FileSystem.createDirectory(scratchDirectory)
        let arguments = Self.arguments(BuildVerification.arguments(record.argv, referenceSource: source.path, sourceRoot: sourceRoot), archivePath: archivePath)
        if let index = arguments.firstIndex(of: "-derivedDataPath"), index + 1 < arguments.count, FileSystem.exists(arguments[index + 1]) {
            try manager.removeItem(atPath: arguments[index + 1])
        }
        let options = ["--developer-dir", developerDirectory, "--host-identity", referenceDirectory + "/host.json"]
            + (continueAfterErrors ? ["-IDEBuildingContinueBuildingAfterErrors=YES"] : [])
        let logPath = scratchDirectory + "/archive.log"
        let result = try Subprocess.run(nomacExecutable, ["archive"] + arguments + options, currentDirectory: sourceRoot)
        try FileSystem.write(result.standardOutput + result.standardError, to: logPath)
        return (result, logPath)
    }

    /// When xcodebuild refused to archive (an ad hoc capture of targets with entitlements, for
    /// one): identical when `nomac archive` exits with the same status and the same errors, the
    /// source folder's paths aside, run as xcodebuild was (without continuing after errors).
    func refusalCheck(_ record: BuildVerification.CommandRecord, capture: String, source: BuildVerification.SourceRecord) throws -> Check {
        let refused = ["xcodebuild archive exited with status \(record.exitStatus)"]
        guard let log = FileSystem.contents(atPath: capture + "/archive.log") else {
            return Check(kind: "archive", name: "archive", status: .referenceFailed, detail: refused)
        }
        let standardError = FileSystem.contents(atPath: capture + "/archive.stderr") ?? Data()
        let expected = Self.errors(String(decoding: log + standardError, as: UTF8.self), sourceRoot: source.path)
        let name = record.argv.firstIndex(of: "-archivePath").flatMap { $0 + 1 < record.argv.count ? record.argv[$0 + 1] : nil }
            .map { ($0 as NSString).lastPathComponent } ?? "Refused.xcarchive"
        let (result, logPath) = try archive(record, source: source, archivePath: scratchDirectory + "/" + name, continueAfterErrors: false)
        let actual = Self.errors(result.outputString + result.errorString, sourceRoot: sourceRoot)
        guard result.exitStatus == record.exitStatus, actual == expected, !expected.isEmpty else {
            return Check(kind: "archive", name: "archive", status: .different,
                         detail: refused + ["nomac archive exited with status \(result.exitStatus) (\(logPath))"]
                            + (actual == expected ? [] : Self.listDifferences(expected, actual)).prefix(detailLimit))
        }
        return Check(kind: "archive", name: "archive", status: .identical,
                     detail: refused + ["nomac archive exits with the same status and the same \(expected.count) errors"])
    }

    /// The error lines of a log, sorted, with `sourceRoot` (with or without `/private`) as
    /// `<source>`.
    static func errors(_ log: String, sourceRoot: String) -> [String] {
        let other = sourceRoot.hasPrefix("/private/") ? String(sourceRoot.dropFirst("/private".count)) : "/private" + sourceRoot
        let roots = [sourceRoot, other].sorted { $0.count > $1.count }
        return log.components(separatedBy: "\n").filter { $0.hasPrefix("error: ") || $0.contains(": error: ") }
            .map { line in roots.reduce(line) { $0.replacingOccurrences(of: $1, with: "<source>") } }.sorted()
    }

    /// The capture's arguments for `nomac archive`: `-archivePath` into the scratch folder,
    /// without the `CODESIGN` wrapper that recorded the capture's signing steps and the action.
    static func arguments(_ arguments: [String], archivePath: String) -> [String] {
        var result: [String] = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "-archivePath" {
                result += [argument, archivePath]
                index += 2
                continue
            }
            if !argument.hasPrefix("CODESIGN="), argument != "archive" { result.append(argument) }
            index += 1
        }
        return result
    }

    /// The archive's `Info.plist`, without the time it was made.
    func infoCheck(_ reference: String, _ other: String) -> Check {
        func read(_ path: String) -> NSDictionary? {
            guard let data = FileSystem.contents(atPath: path),
                  var dictionary = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
            dictionary["CreationDate"] = nil
            return dictionary as NSDictionary
        }
        guard let left = read(reference), let right = read(other) else {
            return Check(kind: "archive", name: "Info.plist", status: .different, detail: ["missing or unreadable Info.plist"])
        }
        return Check(kind: "archive", name: "Info.plist", status: left.isEqual(right) ? .identical : .different,
                     detail: left.isEqual(right) ? [] : ["the archive's properties differ (CreationDate aside)"])
    }

    /// Every file under the two folders by ``BuildProducts``' rules, then signed code by
    /// ``CodeSignatureFields`` and `_CodeSignature/CodeResources` by the files whose hashes differ.
    static func compareSigned(reference: String, other: String) throws -> [BuildProducts.FileResult] {
        var results = try BuildProducts.compare(reference: reference, other: other)
        let changed = Set(results.filter { $0.outcome != .identical }.map(\.path))
        for index in results.indices {
            let path = results[index].path
            switch results[index].outcome {
            case .equivalent(let causes) where MachOStructure.isMachO(path: reference + "/" + path):
                let left = try CodeSignatureFields(file: MachOReader(path: reference + "/" + path))
                let right = try CodeSignatureFields(file: MachOReader(path: other + "/" + path))
                if left != right {
                    let differences = left.flatMap { a in right.map { CodeSignatureFields.differences(a, $0) } } ?? ["signed on one side only"]
                    results[index].outcome = .different(differences)
                } else if left != nil {
                    results[index].outcome = .equivalent(causes + ["the code signature's hashes follow the signed bytes; its other fields are Xcode's"])
                }
            case .different where path.hasSuffix("/_CodeSignature/CodeResources"):
                let bundle = String(path.dropLast("_CodeSignature/CodeResources".count))
                results[index].outcome = try codeResourcesOutcome(reference + "/" + path, other + "/" + path, bundle: bundle, changed: changed)
            default:
                continue
            }
        }
        return results
    }

    /// Equivalent when the two `CodeResources` hold the same rules and files and differ only in
    /// the hashes of files (or nested code) that differ themselves.
    static func codeResourcesOutcome(_ reference: String, _ other: String, bundle: String, changed: Set<String>) throws -> BuildProducts.Outcome {
        func read(_ path: String) -> [String: Any]? {
            FileSystem.contents(atPath: path).flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
        }
        guard let left = read(reference), let right = read(other) else { return .different(["unreadable CodeResources"]) }
        func same(_ x: Any?, _ y: Any?) -> Bool { NSArray(array: [x ?? NSNull()]).isEqual(to: [y ?? NSNull()]) }
        var reasons: [String] = []
        for key in Set(left.keys).union(right.keys).sorted() {
            guard key.hasPrefix("files"), let a = left[key] as? [String: Any], let b = right[key] as? [String: Any] else {
                if !same(left[key], right[key]) { reasons.append("\(key) differs") }
                continue
            }
            for name in Set(a.keys).union(b.keys).sorted() {
                guard let x = a[name], let y = b[name] else { reasons.append("\(key) \(name) on one side only"); continue }
                if same(x, y) { continue }
                let file = bundle + name
                if !changed.contains(where: { $0 == file || $0.hasPrefix(file + "/") }) {
                    reasons.append("\(key) \(name): another hash for a file that is identical")
                }
            }
        }
        return reasons.isEmpty ? .equivalent(["the hashes of the files that differ themselves"]) : .different(reasons)
    }

    /// `nomac export` of nomac's archive with the capture's options, compared with Xcode's export
    /// of its own: every file but `Packaging.log` (times and the machine) byte for byte, an IPA
    /// by its entries' names and modes in order, then their contents as the archive's are.
    func exportChecks(capture: String, archive: String) throws -> [Check] {
        let xcode = capture + "/export"
        guard FileSystem.isDirectory(xcode) else {
            return [Check(kind: "ipa", name: "export", status: .referenceFailed, detail: ["the capture has no export"])]
        }
        let ours = scratchDirectory + "/export"
        let result = try Subprocess.run(nomacExecutable, ["export", "-archivePath", archive, "-exportPath", ours, "-exportOptionsPlist", capture + "/ExportOptions.plist"])
        guard result.exitStatus == 0 else {
            return [Check(kind: "ipa", name: "export", status: .refused,
                          detail: ["nomac export exited with status \(result.exitStatus)"] + (result.errorString + result.outputString).split(separator: "\n").prefix(detailLimit).map(String.init))]
        }
        var checks: [Check] = []
        let names = Set(try FileSystem.sortedContents(of: xcode)).union(try FileSystem.sortedContents(of: ours)).subtracting(["Packaging.log"])
        for name in names.sorted() {
            let expected = xcode + "/" + name, actual = ours + "/" + name
            guard FileSystem.exists(expected), FileSystem.exists(actual) else {
                checks.append(Check(kind: "ipa", name: name, status: .different, detail: [FileSystem.exists(expected) ? "missing" : "extra"]))
                continue
            }
            if name.hasSuffix(".ipa") {
                checks += try ipaChecks(expected, actual, name: name)
            } else {
                let same = FileSystem.contents(atPath: expected) == FileSystem.contents(atPath: actual)
                checks.append(Check(kind: "ipa", name: name, status: same ? .identical : .different, detail: same ? [] : ["the bytes differ"]))
            }
        }
        return checks
    }

    func ipaChecks(_ expected: String, _ actual: String, name: String) throws -> [Check] {
        let left = try ZipArchive(path: expected), right = try ZipArchive(path: actual)
        let listed = { (archive: ZipArchive) in archive.entries.map { String(format: "%@ %o", $0.name, $0.mode) } }
        var checks = [Check(kind: "ipa", name: name + " entries", status: listed(left) == listed(right) ? .identical : .different,
                            detail: listed(left) == listed(right) ? [] : Array(Self.listDifferences(listed(left), listed(right)).prefix(detailLimit)))]
        let folder = scratchDirectory + "/" + name
        try left.extract(to: folder + "/xcode")
        try right.extract(to: folder + "/nomac")
        let results = try Self.compareSigned(reference: folder + "/xcode", other: folder + "/nomac")
        checks += BuildVerification.productChecks(results, kind: "ipa", depth: 2, detailLimit: detailLimit)
        return checks
    }

    static func listDifferences(_ reference: [String], _ other: [String]) -> [String] {
        let a = Set(reference), b = Set(other)
        let found = reference.filter { !b.contains($0) }.map { "only in Xcode's: \($0)" } + other.filter { !a.contains($0) }.map { "only in nomac's: \($0)" }
        return found.isEmpty ? ["the same entries in another order"] : found
    }
}
