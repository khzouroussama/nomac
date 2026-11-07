import Foundation
import NomacCore
import NomacProject
import XcodeProj

/// Synchronized folders (`PBXFileSystemSynchronizedRootGroup`, docs/formats/pif.md).
///
/// Xcode reads a synchronized folder's items from disk and shows them in the group tree and in
/// the build phases of the targets the folder belongs to. Their GUIDs are base64 strings that
/// depend on the project, the folder's object ID and the item's path in the folder, but not on
/// the folder's own path, file contents or the target (observed with the `pif-experiments`
/// workflow); how Xcode derives them is not documented, so nomac generates its own GUIDs from
/// the same inputs and comparisons treat these GUIDs as opaque identities
/// (docs/adr/0009-synchronized-folder-identifiers.md).
extension ProjectGenerator {
    struct SynchronizedRoot {
        let group: PBXFileSystemSynchronizedRootGroup
        let guid: String
        let folder: SynchronizedFolder

        /// The GUID nomac generates for an item of the folder.
        func itemGUID(_ relativePath: String) -> String {
            SHA256.base64(guid + "\u{0}" + relativePath)
        }

        func memberGUID(_ member: SynchronizedFolder.Member) -> String {
            itemGUID(member.isVariantGroup ? "/Localized/" + member.relativePath : member.relativePath)
        }

        /// The GUID of a variant of a variant group in `folder`.
        func variantGUID(_ variant: SynchronizedFolder.Variant, folder: String) -> String {
            itemGUID(folder.isEmpty ? variant.path : folder + "/" + variant.path)
        }

        /// The GUIDs of the items exception sets can name, by their path: members by their key,
        /// subfolders by their path in the folder.
        var namedItems: [[UInt8]: String] {
            var result: [[UInt8]: String] = [:]
            for member in folder.members { result[Array(member.key.utf8)] = memberGUID(member) }
            for path in folder.groupPaths { result[Array(path.utf8)] = itemGUID(path) }
            return result
        }
    }

    /// The kinds of build phase a synchronized member can join.
    enum MemberPhase: Equatable {
        case sources, headers, frameworks, resources
    }

    /// Finds every synchronized folder under the main group and reads it from disk.
    mutating func prepareSynchronizedRoots() throws {
        guard let mainGroup = project.project.mainGroup else { return }
        var found: [(PBXFileSystemSynchronizedRootGroup, String)] = []
        func walk(_ element: PBXFileElement, parentDirectory: String) throws {
            guard let directory = Self.directory(of: element, parentDirectory: parentDirectory, projectDirectory: project.projectDirectory) else { return }
            if let root = element as? PBXFileSystemSynchronizedRootGroup {
                found.append((root, directory))
            } else if let group = element as? PBXGroup, !(group is PBXVariantGroup), !(group is XCVersionGroup) {
                for child in group.children { try walk(child, parentDirectory: directory) }
            }
        }
        try walk(mainGroup, parentDirectory: project.projectDirectory)
        guard !found.isEmpty else { return }
        for (root, directory) in found {
            let folder = SynchronizedFolder(
                directory: directory,
                explicitFolders: Set(root.explicitFolders ?? []),
                explicitFileTypes: root.explicitFileTypes ?? [:],
                developmentRegion: project.project.developmentRegion,
                fileTypes: fileTypes!,
                exceptedPaths: (root.exceptions ?? []).flatMap(Self.namedPaths))
            for item in folder.skipped {
                warnings.append("\(project.fileName): \((root.path ?? "") + "/" + item) was skipped")
            }
            synchronizedRoots.append(SynchronizedRoot(group: root, guid: guid(root), folder: folder))
        }
    }

    /// The paths an exception set names, which the folder lists when they are not on disk: its
    /// membership exceptions and the keys of its platform filters, attributes and compiler flags
    /// (loader-experiments `synchronized-exceptions-2`: `filtered.swift`, `attributed.swift`,
    /// `flagged.m`, `phased.png`).
    static func namedPaths(_ set: PBXFileSystemSynchronizedExceptionSet) -> [String] {
        if let set = set as? PBXFileSystemSynchronizedBuildFileExceptionSet {
            return (set.membershipExceptions ?? []) + (set.platformFiltersByRelativePath ?? [:]).keys.sorted()
                + (set.attributesByRelativePath ?? [:]).keys.sorted() + (set.additionalCompilerFlagsByRelativePath ?? [:]).keys.sorted()
        }
        return (set as? PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet)?.membershipExceptions ?? []
    }

    /// The directory a group-tree element names, or `nil` when it is not under the project
    /// directory's file system (for example relative to the build products directory).
    static func directory(of element: PBXFileElement, parentDirectory: String, projectDirectory: String) -> String? {
        let path = element.path ?? ""
        switch element.sourceTree {
        case nil, .group?:
            return path.isEmpty ? parentDirectory : ((parentDirectory as NSString).appendingPathComponent(path) as NSString).standardizingPath
        case .sourceRoot?:
            return ((projectDirectory as NSString).appendingPathComponent(path) as NSString).standardizingPath
        case .absolute?:
            return (path as NSString).standardizingPath
        default:
            return nil
        }
    }

    func synchronizedRoot(_ group: PBXFileSystemSynchronizedRootGroup) -> SynchronizedRoot? {
        synchronizedRoots.first { $0.group === group }
    }

    // MARK: Group tree

    func synchronizedGroupReference(_ root: PBXFileSystemSynchronizedRootGroup) throws -> PIFValue {
        guard let synchronized = synchronizedRoot(root) else {
            throw NomacError("synchronized folder \(root.uuid) was not read", path: project.path)
        }
        var contents: [String: PIFValue] = [
            "guid": .string(synchronized.guid),
            "name": .string(root.name ?? root.path ?? ""),
            "path": .string(root.path ?? ""),
            "sourceTree": .string(Self.sourceTree(root.sourceTree)),
            "type": .string("group"),
        ]
        let children = synchronized.folder.nodes.map { synchronizedNode($0, root: synchronized) }
        if !children.isEmpty { contents["children"] = .array(children) }
        return .object(contents)
    }

    func synchronizedNode(_ node: SynchronizedFolder.Node, root: SynchronizedRoot) -> PIFValue {
        switch node {
        case .group(let name, let children, let relativePath):
            var contents: [String: PIFValue] = [
                "guid": .string(root.itemGUID(relativePath)),
                "name": .string(name),
                "path": .string(name),
                "sourceTree": .string("<group>"),
                "type": .string("group"),
            ]
            if !children.isEmpty { contents["children"] = .array(children.map { synchronizedNode($0, root: root) }) }
            return .object(contents)
        case .file(let name, let fileType, let relativePath):
            var contents: [String: PIFValue] = [
                "fileType": .string(fileType),
                "guid": .string(root.itemGUID(relativePath)),
                "path": .string(name),
                "sourceTree": .string("<group>"),
                "type": .string("file"),
            ]
            let directory = root.folder.directory + "/" + relativePath
            if fileType == "wrapper.xcdatamodeld", FileSystem.isDirectory(directory) {
                // A Core Data model's folder is a version group of its `.xcdatamodel` folders, as
                // an `XCVersionGroup` is (loader-experiments `synchronized-phases`: a folder
                // holding a plain file has no children; the differential fuzzer's
                // `Extensions.xcdatamodeld/Model.xcdatamodel`).
                contents["type"] = .string("versionGroup")
                contents["name"] = .string(name)
                let versions = ((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? [])
                    .filter { fileTypes?.fileType(atPath: directory + "/" + $0, isDirectory: FileSystem.isDirectory(directory + "/" + $0)) == "wrapper.xcdatamodel" }
                    .sorted(by: SynchronizedFolder.finderOrder)
                if !versions.isEmpty {
                    contents["children"] = .array(versions.map { version in
                        .object([
                            "fileType": .string("wrapper.xcdatamodel"),
                            "guid": .string(root.itemGUID(relativePath + "/" + version)),
                            "path": .string(version),
                            "sourceTree": .string("<group>"),
                            "type": .string("file"),
                        ])
                    })
                }
            }
            return .object(contents)
        case .variantGroup(let name, let variants, let relativePath):
            let folder = (relativePath as NSString).deletingLastPathComponent
            return .object([
                "children": .array(variants.map { variant in
                    var contents: [String: PIFValue] = [
                        "fileType": .string(variant.fileType),
                        "guid": .string(root.variantGUID(variant, folder: folder)),
                        "path": .string(variant.path),
                        "sourceTree": .string("<group>"),
                        "type": .string("file"),
                    ]
                    if !variant.region.isEmpty { contents["regionVariantName"] = .string(variant.region) }
                    return .object(contents)
                }),
                "guid": .string(root.itemGUID("/Localized/" + relativePath)),
                "name": .string(name),
                "path": .string(""),
                "sourceTree": .string("<group>"),
                "type": .string("variantGroup"),
            ])
        }
    }

    // MARK: Build phases

    /// The phase a member joins by default: compiled source types join Sources, header types
    /// and API notes join Headers (when the target has that phase), linkable binaries join
    /// Frameworks, entitlements, module maps, Rez and TypeScript files, playgrounds and Java
    /// archives join none,
    /// and everything else joins Resources (loader-experiments `synchronized-phases`, -2: one
    /// member of each of 113 extensions).
    func memberPhase(_ member: SynchronizedFolder.Member) -> MemberPhase? {
        guard let fileType = member.fileType, let registry = fileTypes else { return .resources }
        let lineage = registry.lineage(of: fileType)
        if lineage.contains("sourcecode.c.h") || lineage.contains("sourcecode.cpp.h") || fileType == "text.apinotes" { return .headers }
        if Self.frameworkFileTypes.contains(where: lineage.contains) { return .frameworks }
        if Self.unbuiltFileTypes.contains(fileType) { return nil }
        if Self.additionalSourceFileTypes.contains(fileType) { return .sources }
        if lineage.contains("sourcecode"), !Self.nonCompiledSourceFileTypes.contains(where: lineage.contains) { return .sources }
        return .resources
    }

    /// Types that join Frameworks: an object file typed by its Mach-O header, with or without
    /// the `.o` extension, too (`pif-experiments` untyped-frameworks, untyped-macho).
    static let frameworkFileTypes = [
        "wrapper.framework", "wrapper.xcframework", "compiled.mach-o.dylib", "compiled.mach-o.objfile", "archive.ar",
        "sourcecode.text-based-dylib-definition", "archive.jar", "archive.ear", "archive.war",
    ]
    /// Types no phase receives (`synchronized-phases`).
    static let unbuiltFileTypes: Set<String> = [
        "text.plist.entitlements", "sourcecode.module-map", "sourcecode.rez", "sourcecode.typescript", "file.playground",
    ]
    /// Source code types that Xcode copies as resources (observed: `.js` in netnewswire, `.md`
    /// in `synchronized-phases`, the shader types in `synchronized-phases-all`).
    static let nonCompiledSourceFileTypes = ["sourcecode.javascript", "net.daringfireball.markdown", "sourcecode.glsl"]
    /// Types outside the `sourcecode` family that Xcode compiles in the Sources phase.
    static let additionalSourceFileTypes: Set<String> = [
        "file.intentdefinition", "file.mlmodel", "folder.mlpackage", "folder.documentationcatalog", "text.xml.ibArchivingDescription",
    ]

    /// The kind of synchronized members a build phase receives.
    static func memberPhase(of phase: PBXBuildPhase) -> MemberPhase? {
        switch phase {
        case is PBXSourcesBuildPhase: return .sources
        case is PBXHeadersBuildPhase: return .headers
        case is PBXFrameworksBuildPhase: return .frameworks
        case is PBXResourcesBuildPhase: return .resources
        default: return nil
        }
    }

    /// A target's synchronized members: those of the folders the target lists, minus the paths
    /// the folders' exception sets name for the target, and the paths the exception sets of the
    /// folders it does not list name for it.
    func synchronizedMembers(of target: PBXTarget) -> [SynchronizedFolder.Member] {
        let listed = target.fileSystemSynchronizedGroups ?? []
        return synchronizedRoots.flatMap { root -> [SynchronizedFolder.Member] in
            let isListed = listed.contains { $0 === root.group }
            let sets = (root.group.exceptions ?? []).compactMap { $0 as? PBXFileSystemSynchronizedBuildFileExceptionSet }.filter { $0.target === target }
            let excepted = Self.exactPaths(sets.flatMap { $0.membershipExceptions ?? [] })
            return root.folder.members.filter { isListed != excepted.contains(Array($0.key.utf8)) }
        }
    }

    /// Paths an exception set names, to be matched byte for byte with the decomposed paths of
    /// a folder's items: a path written precomposed names no item (loader-experiments
    /// `unicode-nfc`, `unicode-nfd`: membership exceptions, `publicHeaders`, `privateHeaders`,
    /// and the keys of `attributesByRelativePath` and `additionalCompilerFlagsByRelativePath`).
    static func exactPaths(_ paths: [String]) -> Set<[UInt8]> {
        Set(paths.map { Array($0.utf8) })
    }

    /// The value a dictionary of an exception set gives an item's path, matched byte for byte.
    static func exactValue<Value>(_ dictionary: [String: Value]?, _ key: String) -> Value? {
        dictionary?.first { $0.key.isIdentical(to: key) }?.value
    }

    /// A phase's build files: its own, then the members of each synchronized folder that has
    /// some for the phase, folder by folder in group-tree order. A folder's members, in walk
    /// order, go in as one block at position `h % (n + 1)` of the `n` build files so far, a build
    /// file whose reference is missing (`nil` in `own`, left out of the result) counting as one, where
    /// `h` folds `h * 33 + hash(name)` (`FoundationStringHash`) over the names of the folder's
    /// items of the phase's kind: all of them when the target lists the folder, excluded ones
    /// included, else those its exception sets name for the target (`pif-experiments`, 137
    /// phases; icecubes and netnewswire, 12 phases mixing folders or own build files). Only a
    /// target's first phase of each kind receives members.
    ///
    /// Then each `PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet` of the folder
    /// that names the phase, of any kind and target, whether or not the target lists the folder or
    /// excludes the items, adds a block the same way: the items its membership exceptions name,
    /// files, subfolders and variant groups, ordered by those paths and hashed by their last
    /// component (loader-experiments `synchronized-exceptions`, `synchronized-phase-order`: 20
    /// phases, `synchronized-phase-order-2`: 15 phases with variant groups; `dangling-synchronized`
    /// and its variants: 281 phases with missing references).
    func buildFiles(of phase: PBXBuildPhase, phaseGUID: String, target: PBXTarget, own: [PIFValue?]) -> [PIFValue] {
        let kind = Self.memberPhase(of: phase).flatMap { target.buildPhases.first(where: { type(of: $0) == type(of: phase) }) === phase ? $0 : nil }
        let listed = target.fileSystemSynchronizedGroups ?? []
        var result = own
        func insert(_ block: [PIFValue], names: [String]) {
            guard !block.isEmpty else { return }
            let hash = names.reduce(UInt64(0)) { $0 &* 33 &+ FoundationStringHash.hash(($1 as NSString).lastPathComponent) }
            result.insert(contentsOf: block.map(Optional.some), at: Int(hash % UInt64(result.count + 1)))
        }
        for root in synchronizedRoots {
            if let kind {
                let isListed = listed.contains { $0 === root.group }
                let sets = (root.group.exceptions ?? []).compactMap { $0 as? PBXFileSystemSynchronizedBuildFileExceptionSet }.filter { $0.target === target }
                let excepted = Self.exactPaths(sets.flatMap { $0.membershipExceptions ?? [] })
                let candidates = (isListed ? root.folder.listedMembers : root.folder.members).filter { memberPhase($0) == kind && (isListed || excepted.contains(Array($0.key.utf8))) }
                let block = candidates.filter { isListed != excepted.contains(Array($0.key.utf8)) }.flatMap { member in
                    [synchronizedBuildFile(member, kind: kind, root: root, sets: sets, phaseGUID: phaseGUID)]
                        + fallbackBuildFiles(member, root: root, phaseGUID: phaseGUID)
                }
                insert(block, names: candidates.map(\.key))
            }
            let references = root.namedItems
            for set in (root.group.exceptions ?? []).compactMap({ $0 as? PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet }) where set.buildPhase === phase {
                let paths = (set.membershipExceptions ?? []).filter { references[Array($0.utf8)] != nil }.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
                insert(paths.map { path in phaseMemberBuildFile(path, reference: references[Array(path.utf8)]!, set: set, phaseGUID: phaseGUID) }, names: paths)
            }
        }
        return result.compactMap { $0 }
    }

    /// The file types of the items build phase membership exception sets add to the target's
    /// phases, which count for its language as its members do (`synchronized-exceptions`:
    /// PhaseGuest; `synchronized-phase-order`: T14, whose only Swift file a set adds to Resources).
    func phaseMemberFileTypes(of target: PBXTarget) -> [String] {
        synchronizedRoots.flatMap { root -> [String] in
            let types = Dictionary(root.folder.members.map { (Array($0.key.utf8), $0.fileType) }, uniquingKeysWith: { first, _ in first })
            return (root.group.exceptions ?? []).compactMap { $0 as? PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet }
                .filter { set in target.buildPhases.contains { $0 === set.buildPhase } }
                .flatMap { ($0.membershipExceptions ?? []).compactMap { types[Array($0.utf8)] ?? nil } }
        }
    }

    /// The build file of an item a build phase membership exception set names: the item, and the
    /// set's `CodeSignOnCopy` and `RemoveHeadersOnCopy` attributes for it. Its GUID depends on the
    /// set, as the item can also be a member of the phase (`synchronized-exceptions`).
    private func phaseMemberBuildFile(_ path: String, reference: String, set: PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet,
                                      phaseGUID: String) -> PIFValue {
        var contents: [String: PIFValue] = [
            "fileReference": .string(reference),
            "guid": .string(SHA256.base64(phaseGUID + "\u{0}" + set.uuid + "\u{0}" + reference)),
        ]
        let attributes = Self.exactValue(set.attributesByRelativePath, path) ?? []
        if attributes.contains("CodeSignOnCopy") { contents["codeSignOnCopy"] = .bool(true) }
        if attributes.contains("RemoveHeadersOnCopy") { contents["removeHeadersOnCopy"] = .bool(true) }
        return .object(contents)
    }

    /// A member's build file. Members of the Headers phase take their visibility from the
    /// exception sets' `publicHeaders` and `privateHeaders`, members of other phases from their
    /// `Public` or `Private` attributes, and Sources members get the code generation key of own
    /// build files (loader-experiments `synchronized-headers`, `codegen-members`). Members of any
    /// phase, variant groups included, take the `platformFiltersByRelativePath` of their path,
    /// the last set's when two sets name it (`synchronized-exceptions`).
    private func synchronizedBuildFile(_ member: SynchronizedFolder.Member, kind: MemberPhase, root: SynchronizedRoot,
                                       sets: [PBXFileSystemSynchronizedBuildFileExceptionSet], phaseGUID: String) -> PIFValue {
        let reference = root.memberGUID(member)
        var contents: [String: PIFValue] = [
            "fileReference": .string(reference),
            "guid": .string(SHA256.base64(phaseGUID + "\u{0}" + reference)),
        ]
        let attributes = sets.flatMap { Self.exactValue($0.attributesByRelativePath, member.key) ?? [] }
        for set in sets {
            if kind == .headers, (set.publicHeaders ?? []).contains(where: { $0.isIdentical(to: member.key) }) { contents["headerVisibility"] = .string("public") }
            if kind == .headers, (set.privateHeaders ?? []).contains(where: { $0.isIdentical(to: member.key) }) { contents["headerVisibility"] = .string("private") }
            if let flags = Self.exactValue(set.additionalCompilerFlagsByRelativePath, member.key), !flags.isEmpty {
                contents["additionalCompilerOptions"] = .string(flags)
            }
            if let filters = Self.platformFilters(Self.exactValue(set.platformFiltersByRelativePath, member.key)) {
                contents["platformFilters"] = filters
            }
        }
        if attributes.contains("CodeSignOnCopy") { contents["codeSignOnCopy"] = .bool(true) }
        if attributes.contains("RemoveHeadersOnCopy") { contents["removeHeadersOnCopy"] = .bool(true) }
        if attributes.contains("Weak") { contents["shouldLinkWeakly"] = .bool(true) }
        if kind != .headers, let visibility = Self.headerVisibility(attributes: attributes) {
            contents["headerVisibility"] = .string(visibility)
        }
        if kind == .sources, let visibility = Self.intentsCodegenVisibility(fileType: member.fileType, attributes: attributes) {
            contents["intentsCodegenVisibility"] = .string(visibility)
        }
        return .object(contents)
    }

    /// Types whose specification names a fallback build phase (`FallbackAutoroutingBuildPhase =
    /// Resources` in Swift Build's specifications): their variants in a variant group get a
    /// build file of their own after the group's (`pif-experiments` base-variants, -2, -3; the
    /// loader-experiments codegen-members `Base.lproj/D.intentdefinition`).
    static let fallbackRoutedFileTypes: Set<String> = ["file.intentdefinition", "archive.metal-library"]

    /// The build files of a variant group's variants of ``fallbackRoutedFileTypes``. The Base
    /// variant's, else the development region's, has the GUID of the group's build file; the
    /// others have GUIDs of their own. Xcode lists them in an order that changes from one run to
    /// the next (`base-variants-3`, three runs); nomac lists them in variant order (BACKLOG B-034).
    private func fallbackBuildFiles(_ member: SynchronizedFolder.Member, root: SynchronizedRoot, phaseGUID: String) -> [PIFValue] {
        guard member.isVariantGroup, let variants = root.folder.variants(of: member) else { return [] }
        let folder = (member.relativePath as NSString).deletingLastPathComponent
        let primary = variants.first { $0.region == "Base" } ?? variants.first { $0.region == project.project.developmentRegion }
        return variants.filter { Self.fallbackRoutedFileTypes.contains($0.fileType) }.map { variant in
            let reference = root.variantGUID(variant, folder: folder)
            let key = variant.path == primary?.path ? root.memberGUID(member) : reference
            return .object(["fileReference": .string(reference), "guid": .string(SHA256.base64(phaseGUID + "\u{0}" + key))])
        }
    }

    // MARK: Base configurations

    /// The GUID of an xcconfig file named by an anchor folder and a path in it. A path written
    /// precomposed names nothing, as the paths of exception sets (loader-experiments
    /// `unicode-nfc`, `unicode-nfd`: `Ànchored.xcconfig`).
    func anchoredBaseConfigurationGUID(_ configuration: XCBuildConfiguration) -> String? {
        guard let anchor = configuration.baseConfigurationAnchor, let path = configuration.baseConfigurationReferenceRelativePath,
              path.isIdentical(to: path.decomposed), let root = synchronizedRoot(anchor) else { return nil }
        return root.itemGUID(path)
    }
}
