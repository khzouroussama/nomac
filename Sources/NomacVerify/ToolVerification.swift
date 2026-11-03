import Foundation
import NomacCore

/// `nomac verify`'s tool checks: every task of the reference's Xcode build (`build/build.log`,
/// corpus/scripts/capture_reference.py) that runs a tool nomac reimplements is run again with
/// nomac's tool of the same name, on the same inputs and with the same options, and the files it
/// writes are compared byte for byte with those Xcode's tool wrote, which the capture kept
/// (docs/VERIFICATION.md "Tool checks").
public struct ToolVerification {
    public typealias Check = VerificationReport.Check

    /// The check kind of each rule whose task runs one of these tools.
    public static let kinds: [String: String] = [
        "CopyStringsFile": "strings",
        "CompileXCStrings": "strings",
        "GenerateStringSymbols": "strings",
        "CompileStoryboard": "nib",
        "CompileXIB": "nib",
        "LinkStoryboards": "nib",
        "CompileAssetCatalog": "assets",
        "CompileAssetCatalogVariant": "assets",
        "GenerateAssetSymbols": "assets",
        "DataModelCompile": "coredata",
        "MappingModelCompile": "coredata",
        "CoreMLModelCompile": "coreml",
        "CoreMLModelCodegen": "coreml",
    ]

    /// The tools Swift Build runs under `sandbox-exec`.
    static let sandboxedTools: Set<String> = ["coremlc"]

    /// The options whose value is a path the tool writes: a file, or a directory it writes into.
    static let outputOptions: Set<String> = [
        "--compile", "--compilation-directory", "--link", "--output-partial-info-plist", "--export-dependency-info",
        "--generate-swift-asset-symbols", "--generate-objc-asset-symbols", "--generate-asset-symbol-index",
        "--outdir", "--output-directory",
    ]

    public var referenceDirectory: String
    public var sourceRoot: String
    public var developerDirectory: String
    /// The `nomac` executable whose tools run.
    public var nomacExecutable: String
    /// Where the tools write; emptied before each task.
    public var scratchDirectory: String
    /// How many lines of a refusal or files of a difference to list.
    public var detailLimit: Int

    public init(referenceDirectory: String, sourceRoot: String, developerDirectory: String, nomacExecutable: String, scratchDirectory: String, detailLimit: Int = 10) {
        self.referenceDirectory = referenceDirectory
        self.sourceRoot = sourceRoot
        self.developerDirectory = developerDirectory
        self.nomacExecutable = nomacExecutable
        self.scratchDirectory = scratchDirectory
        self.detailLimit = detailLimit
    }

    /// Whether two property lists decode to equal values (a `.momd`'s `VersionInfo.plist`, whose
    /// entity names momc shares across versions by a rule not known yet: B-235).
    static func sameValues(_ left: Data, _ right: Data) -> Bool {
        guard let left = try? PropertyListSerialization.propertyList(from: left, format: nil) as? NSDictionary,
              let right = try? PropertyListSerialization.propertyList(from: right, format: nil) as? NSDictionary else { return false }
        return left.isEqual(right)
    }

    /// The declarations of an asset symbol header, or the entries of each kind of an asset symbol
    /// index, in a fixed order. actool lists sets that share their last path component in an
    /// order that changes from run to run in these two files (docs/formats/asset-catalog.md,
    /// "Asset symbols"), so they are compared without their order.
    static func assetSymbolEntries(_ path: String, _ data: Data) -> [String]? {
        if path.hasSuffix("/GeneratedAssetSymbols.h") {
            return String(decoding: data, as: UTF8.self).components(separatedBy: "\n\n").sorted()
        }
        guard path.hasSuffix("/GeneratedAssetSymbols-Index.plist"),
              let index = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [[String: String]]] else { return nil }
        return index.keys.sorted().flatMap { kind in
            index[kind]!.map { entry in kind + ": " + entry.keys.sorted().map { $0 + "=" + entry[$0]! }.joined(separator: ", ") }.sorted()
        }
    }

    private struct CommandRecord: Decodable { var argv: [String] }
    private struct SourceRecord: Decodable { var path: String }
    private struct HostRecord: Decodable { var developerDirectory: String }

    /// One check per task, in the log's order; none without a build capture.
    public func checks() throws -> [Check] {
        let build = referenceDirectory + "/build"
        guard let log = FileSystem.contents(atPath: build + "/build.log"), let commandData = FileSystem.contents(atPath: build + "/build.log.cmd") else {
            return []
        }
        let argv = try JSONDecoder().decode(CommandRecord.self, from: commandData).argv
        guard let index = argv.firstIndex(of: "-derivedDataPath"), index + 1 < argv.count else {
            throw NomacError("the reference build names no -derivedDataPath", path: build + "/build.log.cmd")
        }
        guard let sourceData = FileSystem.contents(atPath: referenceDirectory + "/source.json"),
              let hostData = FileSystem.contents(atPath: referenceDirectory + "/host.json") else {
            throw NomacError("missing source.json or host.json", path: referenceDirectory)
        }
        let reference = Roots(derivedData: FileSystem.xcodebuildSpelling(argv[index + 1]),
                              source: FileSystem.xcodebuildSpelling(try JSONDecoder().decode(SourceRecord.self, from: sourceData).path),
                              developer: try JSONDecoder().decode(HostRecord.self, from: hostData).developerDirectory)
        let local = Roots(derivedData: scratchDirectory + "/DerivedData", source: sourceRoot, developer: developerDirectory)
        let stderr = FileSystem.contents(atPath: build + "/build.stderr").map { String(decoding: $0, as: UTF8.self) } ?? ""
        let parsed = BuildLog(String(decoding: log, as: UTF8.self) + "\n" + stderr)
        return try parsed.tasks.compactMap { task in
            guard let kind = Self.kinds[task.rule] else { return nil }
            let run = TaskRun(task: task, kind: kind, reference: reference, local: local, verification: self)
            return parsed.failed.contains(task.header) ? run.check(.referenceFailed, ["Xcode's task failed"]) : try run.check()
        }
    }
}

/// The three roots a task's paths are under, on the reference's machine or this one.
private struct Roots {
    var derivedData: String
    var source: String
    var developer: String

    var pairs: [String] { [derivedData, source, developer] }
}

/// One task of the log, run with nomac's tool.
private struct TaskRun {
    typealias Check = VerificationReport.Check

    var task: BuildLog.Task
    var kind: String
    var reference: Roots
    var local: Roots
    var verification: ToolVerification

    /// The tool's command line, without the `sandbox-exec` Swift Build runs some tools under
    /// (coremlc: coreml-experiments `build`).
    var command: [String] {
        guard task.command.first.map({ ($0 as NSString).lastPathComponent }) == "sandbox-exec",
              let start = task.command.firstIndex(where: { ToolVerification.sandboxedTools.contains(($0 as NSString).lastPathComponent) }) else {
            return task.command
        }
        return Array(task.command[start...])
    }

    var tool: String { (command.first.map { ($0 as NSString).lastPathComponent }) ?? "" }
    var arguments: [String] { Array(command.dropFirst()) }

    func check(_ status: Check.Status, _ detail: [String]) -> Check {
        let normalizer = PathNormalizer(roots: [
            .init(path: reference.derivedData, symbol: "<DERIVED_DATA>"),
            .init(path: reference.source, symbol: "<SOURCE_ROOT>"),
            .init(path: "/private" + reference.source, symbol: "<SOURCE_ROOT>"),
            .init(path: reference.developer, symbol: "<DEVELOPER_DIR>"),
        ])
        let subject = task.headerArguments.last.map { " " + normalizer.normalize($0) } ?? ""
        return Check(kind: kind, name: "\(task.target ?? "") \(task.rule)\(subject)", status: status,
                     detail: detail.map { normalizer.normalize($0) })
    }

    func check() throws -> Check {
        let outputs = outputArguments()
        let manager = FileManager.default
        let scratch = verification.scratchDirectory
        if manager.fileExists(atPath: scratch) { try manager.removeItem(atPath: scratch) }
        try FileSystem.createDirectory(local.derivedData)
        var staged = Set<String>()
        for (position, argument) in arguments.enumerated() where !outputs.contains(position) && isDerived(argument) {
            guard let kept = keptCopy(of: argument, allowingLiveDerivedData: true) else {
                return check(.referenceFailed, ["the capture did not keep the input \(argument)"])
            }
            let destination = localPath(argument)
            guard !manager.fileExists(atPath: destination) else { continue }
            try FileSystem.createDirectory((destination as NSString).deletingLastPathComponent)
            try manager.copyItem(atPath: kept, toPath: destination)
            staged.formUnion(try files(under: destination).map { relative(fromLocal: $0) })
        }
        // The folders Swift Build creates before the task (its MkDir and CreateBuildDirectory tasks).
        for position in outputs.sorted() {
            let path = localPath(arguments[position])
            let option = position > 0 ? arguments[position - 1] : ""
            let isDirectory = path.hasSuffix("/") || ["--compilation-directory", "--link", "--outdir", "--output-directory"].contains(option)
                || (tool == "actool" && option == "--compile") || (tool == "coremlc" && position == 2)
            try FileSystem.createDirectory(isDirectory ? path : (path as NSString).deletingLastPathComponent)
        }
        // Tasks of package targets run in the package's checkout, inside the derived data.
        try FileSystem.createDirectory(localPath(task.directory))
        var environment = ProcessInfo.processInfo.environment
        for (name, value) in task.environment { environment[name] = localPath(value) }
        let result = try Subprocess.run(verification.nomacExecutable, [tool] + arguments.map(localPath),
                                        currentDirectory: localPath(task.directory), environment: environment)
        guard result.exitStatus == 0 else {
            let lines = (result.errorString + result.outputString).split(separator: "\n").map(String.init).filter { !$0.hasPrefix("/* com.apple.") }
            let scratch = PathNormalizer(roots: [.init(path: local.derivedData, symbol: reference.derivedData)])
            return check(.refused, ["nomac \(tool) exited with status \(result.exitStatus)"] + lines.prefix(verification.detailLimit).map(scratch.normalize))
        }
        var expected = Set<String>()
        for output in xcodeOutputs() {
            guard let kept = keptCopy(of: output, allowingLiveDerivedData: false) else {
                return check(.referenceFailed, ["the capture did not keep the output \(output)"])
            }
            let base = relative(fromReference: output)
            expected.formUnion(try files(under: kept).map { base + String($0.dropFirst(kept.count)) })
        }
        let written = Set(try files(under: local.derivedData).map { relative(fromLocal: $0) }).subtracting(staged)
        var differences: [String] = []
        var equivalent: [String] = []
        let converted = tool == "actool" ? AssetCatalogComparison.convertedImages(under: positionalArguments().filter { $0.hasSuffix(".xcassets") }.map(localPath)) : []
        for path in expected.union(written).sorted() {
            switch (expected.contains(path), written.contains(path)) {
            case (true, false): differences.append("missing \(reference.derivedData + path)")
            case (false, true): differences.append("extra \(reference.derivedData + path)")
            default:
                let xcode = FileSystem.contents(atPath: keptCopy(of: reference.derivedData + path, allowingLiveDerivedData: false)!) ?? Data()
                let nomac = rewritten(FileSystem.contents(atPath: local.derivedData + path) ?? Data())
                if xcode == nomac { continue }
                let catalog = keptCopy(of: reference.derivedData + (path as NSString).deletingLastPathComponent + "/Assets.car", allowingLiveDerivedData: false).flatMap(FileSystem.contents(atPath:))
                if tool == "actool", let left = ToolVerification.assetSymbolEntries(path, xcode), left == ToolVerification.assetSymbolEntries(path, nomac) {
                    equivalent.append("equivalent \(reference.derivedData + path): identical but for the order of sets sharing a name")
                } else if tool == "actool", let result = AssetCatalogComparison.compare(fileName: (path as NSString).lastPathComponent, xcode: xcode, nomac: nomac, xcodeCatalog: catalog, converted: converted) {
                    switch result {
                    case .identical: continue
                    case .equivalent(let causes): equivalent.append("equivalent \(reference.derivedData + path): " + causes.joined(separator: "; "))
                    case .different(let reasons): differences.append("different \(reference.derivedData + path): " + reasons.prefix(3).joined(separator: "; "))
                    }
                } else if path.hasSuffix(".omo"), let left = OptimizedModelComparison.canonical(xcode),
                          left == OptimizedModelComparison.canonical(nomac) {
                    equivalent.append("equivalent \(reference.derivedData + path): identical but for the order of the SQL column-name lists and the positions lookup tables dispatch on (ADR 0230, ADR 0231)")
                } else if tool == "coremlc", CoreMLComparison.equivalent(fileName: (path as NSString).lastPathComponent, xcode: xcode, nomac: nomac) {
                    equivalent.append("equivalent \(reference.derivedData + path): identical but for the order of the model's user metadata entries, which Xcode's coremlc changes from run to run")
                } else if path.hasSuffix(".momd/VersionInfo.plist"), ToolVerification.sameValues(xcode, nomac) {
                    equivalent.append("equivalent \(reference.derivedData + path): the same values, entity names shared as other string objects (B-235)")
                } else if tool == "ibtool", let left = NibSetComparison.sortingSets(xcode), left == NibSetComparison.sortingSets(nomac) {
                    equivalent.append("equivalent \(reference.derivedData + path): identical but for the order of sets' elements (ADR 0252)")
                } else if tool == "ibtool", let left = NibSetComparison.sortingSets(xcode), let right = NibSetComparison.sortingSets(nomac),
                          let canonical = NibConnectionComparison.canonical(left), canonical == NibConnectionComparison.canonical(right) {
                    equivalent.append("equivalent \(reference.derivedData + path): identical but for the order of outlet collections of several sources (ADR 0260)")
                } else {
                    differences.append("different \(reference.derivedData + path)")
                }
            }
        }
        var detail = differences + equivalent
        if detail.count > verification.detailLimit {
            detail = detail.prefix(verification.detailLimit) + ["... \(detail.count - verification.detailLimit) more files"]
        }
        return check(!differences.isEmpty ? .different : equivalent.isEmpty ? .identical : .equivalent, detail)
    }

    /// The positions of the arguments that are paths the tool writes.
    func outputArguments() -> Set<Int> {
        var positions = Set(arguments.indices.filter { $0 > 0 && ToolVerification.outputOptions.contains(arguments[$0 - 1]) })
        if tool == "momc" || tool == "mapc", !arguments.isEmpty { positions.insert(arguments.count - 1) }
        // `coremlc compile|generate <model> <directory>`.
        if tool == "coremlc", arguments.count > 2 { positions.insert(2) }
        return positions
    }

    /// The outputs of Xcode's task, files or directories, at the reference's paths.
    func xcodeOutputs() -> [String] {
        func value(_ option: String) -> String? {
            arguments.firstIndex(of: option).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
        }
        let positional = positionalArguments()
        func stem(_ path: String) -> String { ((path as NSString).lastPathComponent as NSString).deletingPathExtension }
        switch task.rule {
        case "CompileAssetCatalog", "CompileAssetCatalogVariant", "GenerateAssetSymbols":
            // actool's results, which xcodebuild prints after the command, and the dependency info
            // it writes when it compiles: generating asset symbols, Xcode 27.0's actool writes the
            // three symbol files only (retro-rampage's GenerateAssetSymbols command line, run alone;
            // the build's `assetcatalog_dependencies` is LinkAssetCatalog's copy of the thinned one).
            guard let start = task.output.firstIndex(of: "/* com.apple.actool.compilation-results */") else { return [] }
            let generates = ["--generate-swift-asset-symbols", "--generate-objc-asset-symbols", "--generate-asset-symbol-index"].contains(where: arguments.contains)
            return Array(task.output[(start + 1)...].prefix { $0.hasPrefix("/") }) + (generates ? [] : [value("--export-dependency-info")].compactMap { $0 })
        case "CompileStoryboard":
            return [value("--compilation-directory").map { $0 + "/" + stem(positional.first ?? "") + ".storyboardc" }, value("--output-partial-info-plist")].compactMap { $0 }
        case "CompileXIB":
            return [value("--compile"), value("--output-partial-info-plist")].compactMap { $0 }
        case "LinkStoryboards":
            guard let directory = value("--link") else { return [] }
            return positional.map { storyboard in
                let folder = ((storyboard as NSString).deletingLastPathComponent as NSString).lastPathComponent
                return directory + ((folder as NSString).pathExtension == "lproj" ? "/" + folder : "") + "/" + (storyboard as NSString).lastPathComponent
            }
        case "DataModelCompile":
            guard let input = positional.first, let directory = positional.last else { return [] }
            return [(directory.hasSuffix("/") ? String(directory.dropLast()) : directory) + "/" + stem(input) + ((input as NSString).pathExtension == "xcdatamodeld" ? ".momd" : ".mom")]
        case "MappingModelCompile":
            return positional.last.map { [$0] } ?? []
        case "CopyStringsFile":
            guard let directory = value("--outdir"), let separator = arguments.firstIndex(of: "--") else { return [] }
            return arguments[(separator + 1)...].map { directory + "/" + (value("--outfilename") ?? ($0 as NSString).lastPathComponent) }
        case "CompileXCStrings":
            guard let directory = value("--output-directory"), let input = positional.last,
                  let kept = keptCopy(of: directory, allowingLiveDerivedData: false) else { return [] }
            let names = [stem(input) + ".strings", stem(input) + ".stringsdict"]
            return ((try? FileSystem.sortedContents(of: kept)) ?? []).filter { $0.hasSuffix(".lproj") }.flatMap { folder in
                names.filter { FileSystem.isFile(kept + "/" + folder + "/" + $0) }.map { directory + "/" + folder + "/" + $0 }
            }
        case "GenerateStringSymbols":
            return task.headerArguments.first.map { [$0] } ?? []
        case "CoreMLModelCompile":
            guard positional.count > 2 else { return [] }
            let directory = positional[2].hasSuffix("/") ? String(positional[2].dropLast()) : positional[2]
            return [directory + "/" + stem(positional[1]) + ".mlmodelc", value("--output-partial-info-plist")].compactMap { $0 }
        case "CoreMLModelCodegen":
            guard positional.count > 2, let kept = keptCopy(of: positional[2], allowingLiveDerivedData: false) else { return [] }
            return ((try? FileSystem.sortedContents(of: kept)) ?? []).map { positional[2] + "/" + $0 }
        default:
            return []
        }
    }

    /// The arguments that are neither options nor their values (Xcode's tools take every option
    /// with one value but these flags).
    func positionalArguments() -> [String] {
        let flags: Set<String> = ["--errors", "--warnings", "--notices", "--auto-activate-custom-fonts", "--compress-pngs", "--validate", "--dry-run",
                                  "--public-access", "--globalmodule"]
        var result: [String] = []
        var position = 0
        while position < arguments.count {
            let argument = arguments[position]
            if argument == "--" || tool == "xcstringstool" && position == 0 {
                position += 1
                continue
            }
            if argument.hasPrefix("-") && argument.count > 1 {
                position += flags.contains(argument) ? 1 : 2
                continue
            }
            result.append(argument)
            position += 1
        }
        return result
    }

    func isDerived(_ path: String) -> Bool {
        path == reference.derivedData || path.hasPrefix(reference.derivedData + "/")
    }

    /// The path relative to the derived-data root (starting with `/`), on the reference's side.
    func relative(fromReference path: String) -> String {
        String(path.dropFirst(reference.derivedData.count))
    }

    func relative(fromLocal path: String) -> String {
        String(path.dropFirst(local.derivedData.count))
    }

    /// `path` with the reference's roots replaced by this run's.
    func localPath(_ path: String) -> String {
        for (from, to) in zip(reference.pairs, local.pairs) where from != to {
            if path == from || path.hasPrefix(from + "/") { return to + path.dropFirst(from.count) }
        }
        return path
    }

    /// Where the capture kept a file or directory of Xcode's derived data: `Build/Products` and
    /// `Build/Intermediates.noindex` in the reference's `build` folder, and package checkouts
    /// (`SourcePackages`) in the derived data itself while it is there.
    func keptCopy(of path: String, allowingLiveDerivedData: Bool) -> String? {
        let relative = relative(fromReference: path)
        let candidates = [("/Build/Products", "/build/Products"), ("/Build/Intermediates.noindex", "/build/Intermediates")].compactMap { prefix, kept in
            relative == prefix || relative.hasPrefix(prefix + "/") ? verification.referenceDirectory + kept + relative.dropFirst(prefix.count) : nil
        } + (allowingLiveDerivedData && relative.hasPrefix("/SourcePackages/") ? [path] : [])
        return candidates.first { FileSystem.exists($0) }
    }

    /// The files under `path` (itself when it is a file), with absolute paths.
    func files(under path: String) throws -> [String] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else { return [path] }
        return try FileSystem.sortedContents(of: path).flatMap { try files(under: path + "/" + $0) }
    }

    /// nomac's output with this run's roots written as the reference's (docs/adr/0004-reference-artifacts.md).
    func rewritten(_ data: Data) -> Data {
        var result = data
        for (from, to) in zip(local.pairs, reference.pairs) where from != to {
            result = result.replacing(Data(from.utf8), with: Data(to.utf8))
        }
        return result
    }
}

private extension Data {
    func replacing(_ needle: Data, with replacement: Data) -> Data {
        guard !needle.isEmpty, range(of: needle) != nil else { return self }
        var result = Data()
        var start = startIndex
        while let found = range(of: needle, in: start..<endIndex) {
            result.append(self[start..<found.lowerBound])
            result.append(replacement)
            start = found.upperBound
        }
        result.append(self[start..<endIndex])
        return result
    }
}
