import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import NomacCore
import NomacPlist

/// `momc` as an iOS build runs it (`DataModelCompile`): a `.xcdatamodel` into `<name>.mom`, a
/// `.xcdatamodeld` into `<name>.momd` (docs/formats/coredata.md).
public enum ModelCompiler {
    public struct Output: Sendable {
        /// Paths relative to the output directory, and their contents.
        public var files: [(path: String, contents: [UInt8])]
        /// What momc prints on standard error: notes, then warnings.
        public var diagnostics: [String]
    }

    public static func compile(_ input: String, module: String?) throws -> Output {
        let name = (input as NSString).lastPathComponent
        switch (name as NSString).pathExtension {
        case "xcdatamodel":
            let model = try DataModel.read(contentsOf: (input as NSString).appendingPathComponent("contents")).sortingProperties()
            return Output(files: [((name as NSString).deletingPathExtension + ".mom", try ModelArchive.data(model.sortingEntities(), module: module))],
                          diagnostics: ModelWarnings.of(model, location: input))
        case "xcdatamodeld":
            return try compileVersions(input, module: module)
        default:
            throw NomacError("momc compiles .xcdatamodel and .xcdatamodeld inputs, not \(name)", path: input)
        }
    }

    /// What `momc --dry-run --action generate` prints: the files code generation would write in
    /// `destination`, for the entities with a `codeGenerationType` in file order, then the model's
    /// own file named after the input (docs/formats/coredata.md "Code generation").
    public static func generatedFiles(_ input: String, destination: String) throws -> [String] {
        let (model, name) = try generatingModel(input)
        let extensions: [String]
        // No sourceLanguage generates Swift (coredata-experiments `no-language`).
        switch model.sourceLanguage ?? "Swift" {
        case "Swift": extensions = ["swift"]
        case "Objective-C": extensions = ["h", "m"]
        default: throw NomacError("\(input): code generation for sourceLanguage \(model.sourceLanguage ?? "") is not observed yet (BACKLOG B-258)", path: input)
        }
        var files: [String] = []
        for entity in model.entities {
            guard let generation = entity.codeGeneration else { continue }
            guard let className = entity.className?.split(separator: ".").last.map(String.init) else {
                throw NomacError("entity \(entity.name) generates code but has no class name", path: input)
            }
            let kinds = generation == .class ? ["CoreDataClass", "CoreDataProperties"] : ["CoreDataProperties"]
            files += kinds.flatMap { kind in extensions.map { "\(className)+\(kind).\($0)" } }
        }
        guard !files.isEmpty else { return [] }
        files += extensions.map { "\(name)+CoreDataModel.\($0)" }
        return files.map { destination + "/" + $0 }
    }

    /// The version momc treats as current without a declared one, for generated classes and
    /// insecure transformer warnings: the last file name in byte order, `Model.xcdatamodel` after
    /// `Model 2.xcdatamodel` (coredata-experiments `no-current-*`, 20 of 20; the survey's models).
    private static func lastByName(_ files: [String]) -> String? {
        files.max { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
    }

    /// The model version code generation uses, and the name of the input: the current version of
    /// a `.xcdatamodeld`, or the one `lastByName` picks.
    static func generatingModel(_ input: String) throws -> (DataModel, String) {
        let name = ((input as NSString).lastPathComponent as NSString).deletingPathExtension
        switch (input as NSString).pathExtension {
        case "xcdatamodel":
            return (try DataModel.read(contentsOf: (input as NSString).appendingPathComponent("contents")), name)
        case "xcdatamodeld":
            let versions = try FileManager.default.contentsOfDirectory(atPath: input).filter { ($0 as NSString).pathExtension == "xcdatamodel" }
            let models = try versions.map { try DataModel.read(contentsOf: (input as NSString).appendingPathComponent($0 + "/contents")) }
            if let current = try currentVersion(input), let index = versions.firstIndex(of: current + ".xcdatamodel") {
                return (models[index], name)
            }
            guard let file = lastByName(versions), let index = versions.firstIndex(of: file) else {
                return (DataModel(entities: [], fetchRequests: [], minimumToolsVersion: nil, sourceLanguage: "Swift"), name)
            }
            return (models[index], name)
        default:
            throw NomacError("momc compiles .xcdatamodel and .xcdatamodeld inputs, not \(name)", path: input)
        }
    }

    private static func compileVersions(_ input: String, module: String?) throws -> Output {
        let bundle = ((input as NSString).lastPathComponent as NSString).deletingPathExtension + ".momd"
        let entries = try FileManager.default.contentsOfDirectory(atPath: input)
        let versionFiles = APFSDirectoryOrder.sorted(entries).filter { ($0 as NSString).pathExtension == "xcdatamodel" }
        // momc compiles the versions in the order of a copy of a table of their paths, filled in
        // the order the directory lists them (the notes of every observed .xcdatamodeld; the copy
        // shows at 7, 12 and 20 versions, which it moves to a larger table).
        let paths = versionFiles.map { (input as NSString).appendingPathComponent($0) }
        let order = try FoundationHashTable.inserting(paths).copied().keys.map { ($0 as NSString).lastPathComponent }
        var files: [(path: String, contents: [UInt8])] = []
        var versions: [VersionInfo.Version] = []
        var notes: [String] = []
        var warnings: [String] = []
        var models: [String: DataModel] = [:]
        let current = try currentVersion(input).flatMap { name in order.contains(name + ".xcdatamodel") ? name : nil }
        for file in order {
            let version = (file as NSString).deletingPathExtension
            let fileModel = try DataModel.read(contentsOf: (input as NSString).appendingPathComponent(file + "/contents")).sortingProperties()
            let dataModel = try fileModel.sortingEntities()
            let hashes = try VersionHash.entities(of: dataModel)
            let checksum = Data(VersionHash.checksum(hashes)).base64EncodedString()
            // The archived entities (copied twice from name order), then two dictionaries created
            // with them (64 of 64 observed hash dictionaries of more than one entity).
            let once = try FoundationHashTable.inserting(dataModel.entities.map(\.name)).copied().keys
            let entities = try FoundationHashTable.inserting(once).copied().keys
            let entityOrder = try FoundationHashTable.created(with: FoundationHashTable.created(with: entities).keys).keys
            versions.append(VersionInfo.Version(name: version, checksum: checksum, entityHashes: hashes, entityOrder: entityOrder))
            models[version] = dataModel
            files.append(("\(bundle)/\(version).mom", try ModelArchive.data(dataModel, module: module)))
            notes.append("\(file): note: Model \(version) version checksum: \(checksum)")
            warnings += ModelWarnings.of(fileModel, location: (input as NSString).appendingPathComponent(file), transformers: file == current.map({ $0 + ".xcdatamodel" }) ?? lastByName(order))
        }
        if let current {
            let path = (input as NSString).appendingPathComponent(current + ".xcdatamodel")
            files.append(("\(bundle)/\(current).omo", try OptimizedModel.data(models[current]!, module: module, path: path)))
        }
        files.append(("\(bundle)/VersionInfo.plist", try VersionInfo.data(versions, current: current)))
        // Only models of several versions warn (DogWalk's one version does not, versioned-no-current's do).
        if current == nil, versions.count > 1 {
            warnings.append("\(input):: warning: Missing current version declaration [0]")
        }
        return Output(files: files.sorted { $0.path < $1.path }, diagnostics: notes + warnings)
    }

    /// `_XCCurrentVersionName` of `.xccurrentversion` without its extension, if it names one.
    private static func currentVersion(_ input: String) throws -> String? {
        let path = (input as NSString).appendingPathComponent(".xccurrentversion")
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let root = try ModelElement.read(Data(contentsOf: URL(fileURLWithPath: path)), path: path)
        guard let dictionary = root.children.first(where: { $0.name == "dict" }) else { return nil }
        let keys = dictionary.children
        for (index, key) in keys.enumerated() where key.name == "key" && key.text == "_XCCurrentVersionName" && index + 1 < keys.count {
            return (keys[index + 1].text as NSString).deletingPathExtension
        }
        return nil
    }
}

/// The order in which a Mac's default APFS volume (case-insensitive) lists a directory: by the
/// 22-bit CRC-32C of the case-folded, decomposed name in UTF-32, then by the name's length
/// (Apple File System Reference, "Directory entries"; all 15 observed `.xcdatamodeld` listings).
enum APFSDirectoryOrder {
    static func sorted(_ names: [String]) -> [String] {
        let keyed: [(key: UInt32, name: String)] = names.map { (key($0), $0) }
        return keyed.sorted { ($0.key, $0.name) < ($1.key, $1.name) }.map(\.name)
    }

    static func key(_ name: String) -> UInt32 {
        let folded = name.decomposedStringWithCanonicalMapping.lowercased()
        var crc: UInt32 = 0xFFFF_FFFF
        for scalar in folded.unicodeScalars {
            for shift in stride(from: 0, to: 32, by: 8) {
                crc ^= (scalar.value >> UInt32(shift)) & 0xFF
                for _ in 0..<8 {
                    crc = (crc >> 1) ^ (0x82F6_3B78 & (0 &- (crc & 1)))
                }
            }
        }
        let length = UInt32(name.utf8.count + 1) & 0x3FF
        return (crc & 0x3F_FFFF) << 10 | length
    }
}
