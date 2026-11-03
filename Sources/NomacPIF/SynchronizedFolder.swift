import Foundation
import NomacCore

/// The contents of one synchronized folder (`PBXFileSystemSynchronizedRootGroup`) as Xcode
/// presents them in the PIF: the folder is read from disk and its items become groups,
/// files and variant groups (docs/formats/pif.md, "Synchronized folders").
///
/// - Items are named as Xcode names what it reads from disk, decomposed. The paths that
///   `explicitFileTypes` names match those names byte for byte, `explicitFolders` in any
///   normalization form (loader-experiments `unicode-nfc`, `unicode-nfd`).
/// - Items Xcode ignores (``isIgnored(_:)``) are skipped; other names starting with `.` are not.
/// - A subfolder is a group, unless the root names it in `explicitFolders` (a `folder` item),
///   its extension names a wrapper or folder type, or it holds a `Package.swift`
///   (``FileTypeRegistry/fileType(atPath:isDirectory:)``).
/// - The items of `<region>.lproj` subfolders become variant groups in the folder that holds
///   them, one per file name; the string tables of other regions join the variant group of a
///   Base Interface Builder document or intent definition of their stem. Base comes first among
///   the variants, then the project's development region, then the rest in order.
/// - Groups come first, then files and variant groups, each in Finder order.
public struct SynchronizedFolder {
    public indirect enum Node {
        case group(name: String, children: [Node], relativePath: String)
        case file(name: String, fileType: String, relativePath: String)
        case variantGroup(name: String, variants: [Variant], relativePath: String)

        public var name: String {
            switch self {
            case .group(let name, _, _), .file(let name, _, _), .variantGroup(let name, _, _): return name
            }
        }
    }

    public struct Variant {
        /// `<region>.lproj/<file name>`.
        public var path: String
        public var fileType: String
        public var region: String

        /// The region `knownRegions` gains: the `.lproj` folder's name without its extension,
        /// which a folder named `.lproj` does not have (`pif-experiments` dot-files: its variant
        /// has no `regionVariantName` and `knownRegions` gains `.lproj`).
        public var knownRegion: String {
            ((path as NSString).pathComponents[0] as NSString).deletingPathExtension
        }
    }

    /// An item that can belong to a target: a file or a variant group.
    public struct Member {
        /// How exception sets name the item: its path in the folder, or
        /// `/Localized/<folder path>/<name>` for a variant group.
        public var key: String
        /// The path that identifies the item within the root, for its generated GUID.
        public var relativePath: String
        /// `nil` for a variant group.
        public var fileType: String?
        public var isVariantGroup: Bool
    }

    public let directory: String
    public let nodes: [Node]
    /// Members in the order a walk of ``nodes`` visits them.
    public let members: [Member]
    /// Members in the order a target that lists the folder takes them: the walk's, except that
    /// the paths named in subfolders that are not on disk come last, a level at a time
    /// (loader-experiments `synchronized-missing-order`: `Sub/m0.swift` before `Sub/Deep/m3.swift`,
    /// `Sub/m1.png` before `Sub2/m2.png`; a target that does not list the folder takes `Sub/m1.png`
    /// in its place).
    public let listedMembers: [Member]
    /// The paths of `exceptedPaths` the folder lists though they are not on disk, decomposed.
    public let missingPaths: Set<String>
    /// Items that were not represented, with the reason.
    public let skipped: [String]

    /// Reads the folder at `directory`. Of the paths its exception sets name (`exceptedPaths`),
    /// those that no item of the folder holding them has as its name, decomposed and compared
    /// byte for byte, are listed too, decomposed, as files of the type their extension names,
    /// when that folder is on disk: at the top level or in a subfolder, not in a subfolder that
    /// does not exist (swiftfin's `DevelopmentTeam.xcconfig`; `pif-experiments` round 5;
    /// loader-experiments `unicode-nfc`: `Ghöst.swift`; `synchronized-exceptions-2`: `B.swift`
    /// next to `b.swift`, `Sub/deep.png`). A folder that is not on disk, or whose path is a file,
    /// is read as an empty folder (home-assistant's `Sources/Shared/Iconic`; loader-experiments
    /// `synchronized-missing`). An item keeps the type `explicitFileTypes` gives it when Xcode
    /// knows that type (`pif-experiments` explicit-types).
    public init(directory: String, explicitFolders: Set<String>, explicitFileTypes: [String: String], developmentRegion: String?, fileTypes: FileTypeRegistry,
         exceptedPaths: [String] = []) {
        self.directory = directory
        var skipped: [String] = []
        let types = Dictionary(explicitFileTypes.filter { fileTypes.isKnown($0.value) }.map { (Array($0.key.utf8), $0.value) }, uniquingKeysWith: { first, _ in first })
        var missing: Set<String> = []
        let nodes = Self.scan(directory: FileSystem.onDisk(directory), relativePath: "", explicitFolders: explicitFolders, explicitFileTypes: types, developmentRegion: developmentRegion,
                              fileTypes: fileTypes, named: exceptedPaths.map(\.decomposed), missingPaths: &missing, skipped: &skipped)
        self.nodes = nodes
        self.skipped = skipped
        var members: [Member] = []
        Self.collect(nodes, folder: "", into: &members)
        self.members = members
        missingPaths = missing
        let nested = missing.filter { $0.contains("/") }
        func depth(_ member: Member) -> Int { member.relativePath.split(separator: "/").count }
        listedMembers = members.filter { !nested.contains($0.relativePath) }
            + members.filter { nested.contains($0.relativePath) }.enumerated().sorted { (depth($0.element), $0.offset) < (depth($1.element), $1.offset) }.map(\.element)
    }

    /// Xcode's name order: names without their extension first, then header extensions before
    /// the others, then extensions, each compared case-insensitively with numbers by value, as
    /// `localizedStandardCompare` compares for the `en_US` locale Xcode runs in (observed:
    /// `NetNewsWire.entitlements` before `NetNewsWire-dev.entitlements`, `IceCubesApp.swift` before
    /// `IceCubesApp+Menu.swift`, `NetNewsWire_project.xcconfig` before
    /// `NetNewsWireTests_target.xcconfig`; `pif-experiments` same-stem: `Y.h, Y.c, Y.m, Y 1.c,
    /// Y_1.c, Y-1.c, Ya.c`, folders `G.h, G.hpp, G.c`).
    static func finderOrder(_ a: String, _ b: String) -> Bool {
        let stems = standardCompare((a as NSString).deletingPathExtension, (b as NSString).deletingPathExtension)
        if stems != .orderedSame { return stems == .orderedAscending }
        let (aExtension, bExtension) = ((a as NSString).pathExtension, (b as NSString).pathExtension)
        let (aHeader, bHeader) = (headerExtensions.contains(aExtension), headerExtensions.contains(bExtension))
        if aHeader != bHeader { return aHeader }
        let extensions = standardCompare(aExtension, bExtension)
        if extensions != .orderedSame { return extensions == .orderedAscending }
        return standardCompare(a, b) == .orderedAscending
    }

    private static func standardCompare(_ a: String, _ b: String) -> ComparisonResult {
        a.compare(b, options: [.caseInsensitive, .numeric, .widthInsensitive, .forcedOrdering], range: nil, locale: finderLocale)
    }

    private static let finderLocale = Locale(identifier: "en_US")

    /// The extensions that sort before the others of their stem, case-sensitively
    /// (`pif-experiments` same-stem, same-stem-2: not `pch`, `pch++`, `H`, `HPP`, `Hh`, `inl`, `tpp`).
    static let headerExtensions: Set<String> = ["h", "h++", "hh", "hp", "hpp", "hxx", "ipp"]

    /// Names Xcode leaves out of a synchronized folder, in any subfolder (`pif-experiments`
    /// dot-files, dot-files-2): `.DS_Store`, version control folders and files (`.git`, `.svn`,
    /// `.hg`, `CVS`, but not `.bzr` or `_darcs`), editor backups (`a.swift~`, `.#lock`) and
    /// AppleDouble files (`._a.swift`). `.gitignore`, `.gitkeep`, `.hidden.swift`, `.build` and
    /// `.lproj` are items like any other.
    static func isIgnored(_ name: String) -> Bool {
        [".DS_Store", ".git", ".svn", ".hg", "CVS"].contains(name) || name.hasSuffix("~") || name.hasPrefix(".#") || name.hasPrefix("._")
    }

    /// Extensions of the Base variants that the string tables of other regions join, whatever
    /// the file's type (`pif-experiments` base-variants, base-variants-2: a plain `R.nib` too; not
    /// `.h`, `.m`, `.json`, `.txt`, `.png`, `.plist`, `.mlmodel`, `.mlpackage`, `.metallib`, `.strings`).
    static let baseDocumentExtensions: Set<String> = ["storyboard", "xib", "nib", "intentdefinition"]
    /// String tables that join them (not `.stringsdict`).
    static let joiningStringTableExtensions: Set<String> = ["strings", "xcstrings"]

    /// Variant groups from the variants of one folder's `.lproj` subfolders: one per file name,
    /// the string tables of other regions joining the group of a Base document of their stem,
    /// where a string table replaces the variant of its region (`base-variants-2`:
    /// `Base.lproj/F2.storyboard`, `Base.lproj/F2.strings` and `en.lproj/F2.strings` give the group
    /// `F2.storyboard` of the two string tables). Without a Base document, a variant group of
    /// the development region's document stays apart (`base-variants`: `en.lproj/E.intentdefinition`
    /// and `fr.lproj/E.strings`).
    private static func variantGroups(_ variants: [Variant]) -> [String: [Variant]] {
        var groups: [String: [Variant]] = [:]
        for variant in variants { groups[(variant.path as NSString).lastPathComponent, default: []].append(variant) }
        let documents = groups.filter { name, members in
            baseDocumentExtensions.contains((name as NSString).pathExtension) && members.contains { $0.region == "Base" }
        }
        let byStem = Dictionary(documents.keys.map { (($0 as NSString).deletingPathExtension, $0) }, uniquingKeysWith: { finderOrder($0, $1) ? $0 : $1 })
        for name in groups.keys.sorted(by: finderOrder) where joiningStringTableExtensions.contains((name as NSString).pathExtension) {
            guard let document = byStem[(name as NSString).deletingPathExtension], let tables = groups.removeValue(forKey: name) else { continue }
            groups[document] = groups[document, default: []].filter { member in !tables.contains { $0.region == member.region } } + tables
        }
        return groups
    }

    private static func join(_ folder: String, _ name: String) -> String {
        folder.isEmpty ? name : folder + "/" + name
    }

    /// The items of the folder at `directory`, its spelling on disk, and the paths of `named` it
    /// holds that are not on disk.
    private static func scan(directory: String, relativePath: String, explicitFolders: Set<String>, explicitFileTypes: [[UInt8]: String], developmentRegion: String?,
                             fileTypes: FileTypeRegistry, named: [String], missingPaths: inout Set<String>, skipped: inout [String]) -> [Node] {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        let present = Set(contents.map { Array($0.decomposed.utf8) })
        var missing: [String] = []
        for path in named where (path as NSString).deletingLastPathComponent == relativePath {
            let name = (path as NSString).lastPathComponent
            if !present.contains(Array(name.utf8)) && !missing.contains(name) { missing.append(name) }
        }
        var groups: [Node] = []
        var items: [Node] = missing.map { name in
            let relative = join(relativePath, name)
            missingPaths.insert(relative)
            return .file(name: name, fileType: explicitFileTypes[Array(relative.utf8)] ?? fileTypes.missingFileType(name: name), relativePath: relative)
        }
        var variants: [Variant] = []
        for entry in contents where !isIgnored(entry) {
            let path = directory + "/" + entry
            let name = entry.decomposed
            let relative = join(relativePath, name)
            let isDirectory = FileSystem.isDirectory(path)
            if isDirectory, explicitFolders.contains(relative) {
                items.append(.file(name: name, fileType: "folder", relativePath: relative))
                continue
            }
            if isDirectory, name.hasSuffix(".lproj") {
                let region = String(name.dropLast(".lproj".count))
                for fileEntry in ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).filter({ !isIgnored($0) }) {
                    let filePath = path + "/" + fileEntry
                    let file = fileEntry.decomposed
                    let fileIsDirectory = FileSystem.isDirectory(filePath)
                    guard let type = explicitFileTypes[Array(join(relative, file).utf8)] ?? fileTypes.fileType(atPath: filePath, isDirectory: fileIsDirectory) else {
                        skipped.append("\(join(relative, file)): a plain folder inside a .lproj folder")
                        continue
                    }
                    variants.append(Variant(path: name + "/" + file, fileType: type, region: region))
                }
                continue
            }
            if let type = explicitFileTypes[Array(relative.utf8)] ?? fileTypes.fileType(atPath: path, isDirectory: isDirectory) {
                items.append(.file(name: name, fileType: type, relativePath: relative))
            } else {
                let children = scan(directory: path, relativePath: relative, explicitFolders: explicitFolders, explicitFileTypes: explicitFileTypes,
                                    developmentRegion: developmentRegion, fileTypes: fileTypes, named: named, missingPaths: &missingPaths, skipped: &skipped)
                groups.append(.group(name: name, children: children, relativePath: relative))
            }
        }
        for (name, members) in variantGroups(variants) {
            // `pif-experiments` variants-order: Base, then the development region, then the others
            // in name order (`Base, en, ab, de, en-GB, fr`; with `fr`: `Base, fr, ab, de, en, en-GB`).
            let ordered = members.sorted { a, b in
                for first in ["Base", developmentRegion] where a.region == first || b.region == first {
                    return a.region == first && b.region != first
                }
                return finderOrder(a.region, b.region)
            }
            items.append(.variantGroup(name: name, variants: ordered, relativePath: join(relativePath, name)))
        }
        groups.sort { finderOrder($0.name, $1.name) }
        items.sort { finderOrder($0.name, $1.name) }
        return groups + items
    }

    /// The paths of the folder's subfolders that are groups.
    var groupPaths: [String] {
        func paths(_ nodes: [Node]) -> [String] {
            nodes.flatMap { node -> [String] in
                guard case .group(_, let children, let relativePath) = node else { return [] }
                return [relativePath] + paths(children)
            }
        }
        return paths(nodes)
    }

    /// The variants of a variant group member.
    func variants(of member: Member) -> [Variant]? {
        func find(_ nodes: [Node]) -> [Variant]? {
            for node in nodes {
                switch node {
                case .group(_, let children, _):
                    if let found = find(children) { return found }
                case .variantGroup(_, let variants, let relativePath) where relativePath == member.relativePath:
                    return variants
                case .file, .variantGroup:
                    continue
                }
            }
            return nil
        }
        return member.isVariantGroup ? find(nodes) : nil
    }

    private static func collect(_ nodes: [Node], folder: String, into members: inout [Member]) {
        for node in nodes {
            switch node {
            case .group(let name, let children, _):
                collect(children, folder: join(folder, name), into: &members)
            case .file(_, let fileType, let relativePath):
                members.append(Member(key: relativePath, relativePath: relativePath, fileType: fileType, isVariantGroup: false))
            case .variantGroup(let name, _, let relativePath):
                members.append(Member(key: "/Localized/" + join(folder, name), relativePath: relativePath, fileType: nil, isVariantGroup: true))
            }
        }
    }
}
