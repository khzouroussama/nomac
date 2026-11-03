import Foundation
import NomacCore
import NomacVerify

/// `nomac verify --build`: builds the app with `nomac build` as the reference capture's
/// xcodebuild built it (`build/build.log.cmd`, corpus/scripts/capture_reference.py), at the same
/// derived-data path, and compares `Build/Products` with the capture's `build/Products`
/// (``BuildProducts``).
public struct BuildVerification {
    public typealias Check = VerificationReport.Check

    public var referenceDirectory: String
    public var sourceRoot: String
    public var developerDirectory: String
    /// The `nomac` executable that runs the build.
    public var nomacExecutable: String
    /// Where the build's output goes.
    public var logPath: String
    /// How many files to list per check.
    public var detailLimit: Int
    /// Whether the build runs the tasks that do not depend on a failed one
    /// (`-IDEBuildingContinueBuildingAfterErrors=YES`), so that their products are compared too.
    public var continueBuildingAfterErrors: Bool

    public init(referenceDirectory: String, sourceRoot: String, developerDirectory: String, nomacExecutable: String, logPath: String,
                detailLimit: Int = 40, continueBuildingAfterErrors: Bool = false) {
        self.referenceDirectory = referenceDirectory
        self.sourceRoot = sourceRoot
        self.developerDirectory = developerDirectory
        self.nomacExecutable = nomacExecutable
        self.logPath = logPath
        self.detailLimit = detailLimit
        self.continueBuildingAfterErrors = continueBuildingAfterErrors
    }

    struct CommandRecord: Decodable { var argv: [String]; var exitStatus: Int32 }
    struct SourceRecord: Decodable { var path: String }

    /// The `build` check, then one check per product.
    public func checks() throws -> [Check] {
        guard let data = FileManager.default.contents(atPath: referenceDirectory + "/build/build.log.cmd") else {
            return [Check(kind: "build", name: "build", status: .referenceFailed, detail: ["the reference has no build capture"])]
        }
        let record = try JSONDecoder().decode(CommandRecord.self, from: data)
        guard record.exitStatus == 0 else {
            return [Check(kind: "build", name: "build", status: .referenceFailed, detail: ["xcodebuild exited with status \(record.exitStatus)"])]
        }
        guard let sourceData = FileSystem.contents(atPath: referenceDirectory + "/source.json") else {
            throw NomacError("missing source.json", path: referenceDirectory)
        }
        let source = try JSONDecoder().decode(SourceRecord.self, from: sourceData)
        let arguments = Self.arguments(record.argv, referenceSource: source.path, sourceRoot: sourceRoot)
        guard let index = arguments.firstIndex(of: "-derivedDataPath"), index + 1 < arguments.count else {
            throw NomacError("the reference build names no -derivedDataPath", path: referenceDirectory + "/build/build.log.cmd")
        }
        let derivedData = arguments[index + 1]
        // The capture starts from an empty derived-data folder.
        if FileSystem.exists(derivedData) { try FileManager.default.removeItem(atPath: derivedData) }
        let options = ["--developer-dir", developerDirectory, "--host-identity", referenceDirectory + "/host.json"]
            + (continueBuildingAfterErrors ? ["-IDEBuildingContinueBuildingAfterErrors=YES"] : [])
        let checkout = try Checkout(sourceRoot)
        let before = try checkout?.status()
        let result = try Subprocess.run(nomacExecutable, ["build"] + arguments + options, currentDirectory: sourceRoot)
        var restored = [String]()
        if let checkout, let before { restored = try checkout.restore(since: before) }
        try FileSystem.write(result.standardOutput + result.standardError + Data(restored.map { $0 + "\n" }.joined().utf8), to: logPath)
        var checks = [Check(kind: "build", name: "build", status: result.exitStatus == 0 ? .identical : .different,
                            detail: result.exitStatus == 0 ? [] : ["nomac build exited with status \(result.exitStatus) (\(logPath))"] + Self.failureSummary(result.outputString + result.errorString))]
        var results = try BuildProducts.compare(reference: referenceDirectory + "/build/Products", other: derivedData + "/Build/Products", sources: [sourceRoot])
        #if !os(macOS)
        let (compared, note) = Self.excludingBuildMachineProducts(results)
        results = compared
        checks[0].detail += note
        #endif
        checks += Self.productChecks(results, detailLimit: detailLimit)
        return checks
    }

    /// The git checkout a build runs in. The capture undoes what the build changed in it
    /// (`restore` in corpus/scripts/capture_reference.py), so the archive capture starts from the
    /// checkout as the build found it: expo-default's script phases switch prebuilt xcframeworks
    /// in `Pods` from their debug to their release copy, which drops the dSYM source maps the
    /// archive's own phases wrote first.
    struct Checkout {
        var git: String
        var top: String

        /// `nil` when `path` is not in a git checkout.
        init?(_ path: String) throws {
            guard let git = Subprocess.locate("git") else { return nil }
            let result = try Subprocess.run(git, ["-C", path, "rev-parse", "--show-toplevel"])
            guard result.exitStatus == 0 else { return nil }
            self.git = git
            top = result.outputString.trimmingCharacters(in: .newlines)
        }

        /// The changed tracked paths and the untracked and ignored ones, as `git status` lists them.
        func status() throws -> (changed: Set<String>, added: Set<String>) {
            let result = try Subprocess.run(git, ["-C", top, "status", "--porcelain", "--ignored", "--untracked-files=all", "-z"])
            guard result.exitStatus == 0 else { throw NomacError("git status failed: \(result.errorString)", path: top) }
            let entries = result.outputString.split(separator: "\0").filter { $0.count > 3 }
            let isAdded = { (entry: Substring) in ["??", "!!"].contains(entry.prefix(2)) }
            return (Set(entries.filter { !isAdded($0) }.map { String($0.dropFirst(3)) }),
                    Set(entries.filter(isAdded).map { String($0.dropFirst(3)) }))
        }

        /// Checks out the tracked paths changed since `before` and removes the paths added since,
        /// with one line per path.
        func restore(since before: (changed: Set<String>, added: Set<String>)) throws -> [String] {
            let now = try status()
            let changed = now.changed.subtracting(before.changed).sorted()
            let added = now.added.subtracting(before.added).sorted()
            if !changed.isEmpty {
                // A switched xcframework is thousands of paths, more than one command line holds.
                let pathspec = NSTemporaryDirectory() + "/nomac-restore-\(UUID().uuidString)"
                try FileSystem.write(Data(changed.joined(separator: "\0").utf8), to: pathspec)
                defer { try? FileManager.default.removeItem(atPath: pathspec) }
                let result = try Subprocess.run(git, ["--literal-pathspecs", "-C", top, "checkout", "--pathspec-from-file=" + pathspec,
                                                      "--pathspec-file-nul", "--"])
                guard result.exitStatus == 0 else { throw NomacError("git checkout failed: \(result.errorString)", path: top) }
            }
            // An added folder's files go with it.
            for path in added where (try? FileManager.default.attributesOfItem(atPath: top + "/" + path)) != nil {
                try FileManager.default.removeItem(atPath: top + "/" + path)
            }
            return changed.map { "restored \($0), which the build changed in the checkout" }
                + added.map { "removed \($0), which the build wrote into the checkout" }
        }
    }

    /// The platforms of `Build/Products/<configuration>-<platform>`; a folder without one holds the
    /// products built for the Mac itself.
    static let productPlatforms = ["iphoneos", "iphonesimulator", "appletvos", "appletvsimulator", "watchos", "watchsimulator",
                                   "xros", "xrsimulator", "driverkit", "maccatalyst"]

    /// Off macOS, the products built for the build machine (macros and the other host tools the
    /// build runs) are Linux's, in `<configuration>-linux-<arch>`, where the reference has macOS's,
    /// in `<configuration>`: neither is compared, and a note says so (docs/VERIFICATION.md "Build
    /// products"; swiftfin's macro packages).
    static func excludingBuildMachineProducts(_ results: [BuildProducts.FileResult]) -> (compared: [BuildProducts.FileResult], note: [String]) {
        func folder(_ result: BuildProducts.FileResult) -> String { String(result.path.prefix { $0 != "/" }) }
        func isMac(_ folder: String) -> Bool { !folder.contains("-linux-") && !productPlatforms.contains { folder.hasSuffix("-" + $0) } }
        var excluded: [String: Int] = [:]
        let compared = results.filter { result in
            let name = folder(result)
            let buildMachine = name.contains("-linux-") ? result.outcome == .extra : isMac(name) && result.outcome == .missing
            if buildMachine { excluded[name, default: 0] += 1 }
            return !buildMachine
        }
        let note = excluded.keys.sorted().map { name in
            name.contains("-linux-")
                ? "\(name) (\(excluded[name]!) files): built for this Linux build machine, not compared"
                : "\(name) (\(excluded[name]!) files): the reference's products for its Mac, not compared"
        }
        return (compared, note)
    }

    /// The capture's xcodebuild arguments for `nomac build`, with the reference checkout's path
    /// replaced by `sourceRoot`.
    static func arguments(_ argv: [String], referenceSource: String, sourceRoot: String) -> [String] {
        // The arguments after xcodebuild: captures run offline record `sandbox-exec -p <profile>`
        // before it.
        let start = argv.firstIndex { ($0 as NSString).lastPathComponent == "xcodebuild" }.map { $0 + 1 } ?? 1
        return argv[start...].map { argument in
            guard referenceSource != sourceRoot, argument == referenceSource || argument.hasPrefix(referenceSource + "/") else { return argument }
            return sourceRoot + argument.dropFirst(referenceSource.count)
        }
    }

    /// xcodebuild's failure summary in `log`, from "The following build commands failed:".
    static func failureSummary(_ log: String) -> [String] {
        let lines = log.components(separatedBy: "\n")
        guard let start = lines.firstIndex(of: "The following build commands failed:") else { return Array(lines.suffix(5)) }
        return Array(lines[start...]).filter { !$0.isEmpty }
    }

    /// One check of `kind` per product: each entry of `Products/<configuration>-<platform>`, or
    /// whatever the first `depth` components of the paths name.
    public static func productChecks(_ results: [BuildProducts.FileResult], kind: String = "build", depth: Int = 2, detailLimit: Int) -> [Check] {
        var products: [String: [BuildProducts.FileResult]] = [:]
        for result in results {
            products[result.path.split(separator: "/").prefix(depth).joined(separator: "/"), default: []].append(result)
        }
        return products.keys.sorted().map { product in
            var status = Check.Status.identical
            var detail: [String] = []
            for result in products[product]! {
                switch result.outcome {
                case .identical:
                    continue
                case .equivalent(let causes):
                    if status == .identical { status = .equivalent }
                    detail.append("equivalent \(result.path): " + causes.joined(separator: "; "))
                case .different(let reasons):
                    status = .different
                    detail.append("different \(result.path): " + reasons.joined(separator: "; "))
                case .missing:
                    status = .different
                    detail.append("missing \(result.path)")
                case .extra:
                    status = .different
                    detail.append("extra \(result.path)")
                }
            }
            if detail.count > detailLimit {
                detail = detail.prefix(detailLimit) + ["... \(detail.count - detailLimit) more files"]
            }
            return Check(kind: kind, name: product, status: status, detail: detail)
        }
    }
}
