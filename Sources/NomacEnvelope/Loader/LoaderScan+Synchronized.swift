import Foundation
import NomacCore
import NomacPIF

extension LoaderScan {
    /// File types of library members, which Xcode links with a search path (docs/formats/pif.md
    /// "Synchronized folders").
    static let libraryTypes: Set<String> = [
        "archive.ar", "compiled.mach-o.dylib", "compiled.mach-o.objfile", "wrapper.framework", "wrapper.xcframework",
        "sourcecode.text-based-dylib-definition",
    ]
    /// The types of members that add a search path: libraries, stubs and frameworks.
    static let searchPathTypes: Set<String> = ["archive.ar", "compiled.mach-o.dylib", "sourcecode.text-based-dylib-definition", "wrapper.framework"]
    static let headerExtensions: Set<String> = ["h", "h++", "hh", "hp", "hpp", "hxx", "ipp"]

    /// A synchronized folder's items as nomac reads them from disk (docs/formats/pif.md
    /// "Synchronized folders").
    func scanSynchronizedRoot(_ id: String, in project: RawProject) {
        let label = project.describe(id)
        guard let directory = project.fullPath(id) else {
            use("sync:folder=outside-source-tree", project.file, label)
            return
        }
        guard !options.descriptionOnly else {
            unchecked.append(UncheckedPart(what: "contents of a synchronized folder", file: directory))
            return
        }
        guard FileSystem.isDirectory(directory) else {
            use("sync:folder=missing", project.file, label)
            return
        }
        guard let fileTypes = fileTypeRegistry() else {
            unchecked.append(UncheckedPart(what: "contents of a synchronized folder (Swift Build's file types not found)", file: directory))
            return
        }
        let named = project.strings(id, "exceptions").flatMap { set -> [String] in
            switch project.isa(set) {
            case "PBXFileSystemSynchronizedBuildFileExceptionSet":
                return project.strings(set, "membershipExceptions") + ["platformFiltersByRelativePath", "attributesByRelativePath", "additionalCompilerFlagsByRelativePath"]
                    .flatMap { ((project.objects[set]?[$0] as? [String: Any]) ?? [:]).keys.sorted() }
            case "PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet":
                return project.strings(set, "membershipExceptions")
            default:
                return []
            }
        }
        let developmentRegion = project.root["developmentRegion"] as? String
        let folder = SynchronizedFolder(directory: directory, explicitFolders: Set(project.strings(id, "explicitFolders")),
                                        explicitFileTypes: project.objects[id]?["explicitFileTypes"] as? [String: String] ?? [:],
                                        developmentRegion: developmentRegion, fileTypes: fileTypes, exceptedPaths: named)
        for path in folder.missingPaths.sorted() {
            use(path.contains("/") ? "sync:excepted-path=missing-in-existing-subfolder" : "sync:excepted-path=missing", project.file, "\(label) \(path)")
        }
        for path in Set(named.map(\.decomposed)).sorted() where path.contains("/") && !path.hasPrefix("/") && !folder.missingPaths.contains(path)
            && !FileSystem.exists(directory + "/" + path) {
            use("sync:excepted-path=missing-in-subfolder", project.file, "\(label) \(path)")
        }
        for item in folder.skipped { use("sync:item=skipped", directory, item) }
        let known = Set(project.root["knownRegions"] as? [String] ?? [])
        let explicitFolders = Set(project.strings(id, "explicitFolders"))
        func walk(_ nodes: [SynchronizedFolder.Node]) {
            var stems: [String: [String]] = [:]
            for node in nodes {
                if !Self.isASCII(node.name) { use("names:sync-item=non-ascii", directory, node.name) }
                switch node {
                case .group(_, let children, let relativePath):
                    use("sync:group", directory, relativePath)
                    walk(children)
                case .file(let name, let fileType, let relativePath):
                    use("sync:fileType=\(fileType)", directory, relativePath)
                    if explicitFolders.contains(relativePath) { use("sync:explicit-folder", directory, relativePath) }
                    if FileSystem.isFile(directory + "/" + relativePath + "/Package.swift") { use("sync:package-folder", directory, relativePath) }
                    if Self.libraryTypes.contains(fileType) { use("sync:member=library", directory, relativePath) }
                    stems[(name as NSString).deletingPathExtension, default: []].append((name as NSString).pathExtension)
                case .variantGroup(_, let variants, let relativePath):
                    use("sync:variant-group", directory, relativePath)
                    for variant in variants { use("sync:fileType=\(variant.fileType)", directory, relativePath + "/" + variant.path) }
                    let regions = variants.map(\.region)
                    let hasBase = regions.contains("Base")
                    let hasDevelopment = developmentRegion.map(regions.contains) ?? false
                    if !hasBase && !hasDevelopment { use("sync:variant-group=no-base-or-development-region", directory, relativePath) }
                    if hasBase && hasDevelopment { use("sync:variant-group=base-and-development-region", directory, relativePath) }
                    var added: [String] = []
                    for region in regions where region != "mul" && region != developmentRegion && !known.contains(region) && !added.contains(region) {
                        added.append(region)
                    }
                    if added.count == 1 { use("sync:variant-group=adds-a-region", directory, relativePath) }
                    if added.count > 1 { use("sync:variant-group=adds-several-regions", directory, relativePath) }
                }
            }
            // Xcode puts a stem's headers first (pif-experiments same-stem).
            for (stem, extensions) in stems.sorted(by: { $0.key < $1.key }) {
                guard let header = extensions.filter(Self.headerExtensions.contains).min() else { continue }
                if extensions.contains(where: { !Self.headerExtensions.contains($0) && $0.lowercased() < header.lowercased() }) {
                    use("sync:same-stem=header-after-other", directory, stem)
                }
            }
        }
        walk(folder.nodes)
        // Xcode orders the paths of one folder's libraries, or of its frameworks, differently from
        // run to run (B-031).
        let searchPathFolders = Dictionary(grouping: folder.members.filter { $0.fileType.map(Self.searchPathTypes.contains) == true }) {
            $0.fileType == "wrapper.framework"
        }.mapValues { Set($0.map { ($0.relativePath as NSString).deletingLastPathComponent }) }
        if searchPathFolders.values.contains(where: { $0.count > 1 }) { use("sync:member=libraries-in-several-folders", directory, label) }
    }

    /// Swift Build's file types, loaded once; nil when they are not installed next to nomac.
    func fileTypeRegistry() -> FileTypeRegistry? {
        if !fileTypesLoaded {
            fileTypes = try? FileTypeRegistry.installed()
            fileTypesLoaded = true
        }
        return fileTypes
    }
}
