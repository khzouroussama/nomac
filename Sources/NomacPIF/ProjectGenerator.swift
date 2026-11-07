import Foundation
import NomacCore
import NomacProject
import XcodeProj

/// Generates the PIF objects for one project: the project object and its targets.
struct ProjectGenerator {
    let project: XcodeProject
    let context: WorkspaceContext
    let projectGUID: String
    var warnings: [String] = []
    /// File types for file references and synchronized folders; read from Swift Build's
    /// specifications when none were given.
    var fileTypes: FileTypeRegistry?
    /// The project's synchronized folders, in group-tree order, read by ``generate()``.
    var synchronizedRoots: [SynchronizedRoot] = []
    /// The absolute paths of the project's file references on the file system, by object ID.
    var referencePaths: [String: String] = [:]
    /// Evaluated build settings of the target configurations that set a setting the PIF needs
    /// with macros or conditions.
    var evaluatedSettings: [TargetSettingsQuery: [String: String]] = [:]
    /// Object IDs of every target's product reference in this project. Product references
    /// are represented inside their targets, so they are omitted from the group tree.
    let productReferenceIDs: Set<String>
    /// The project's ``LegacyBuildFolder``, read by ``generate()``.
    var legacyBuildFolder: String?

    init(project: XcodeProject, context: WorkspaceContext, fileTypes: FileTypeRegistry? = nil) {
        self.project = project
        self.context = context
        self.fileTypes = fileTypes
        self.projectGUID = PIFIdentifiers.projectGUID(projectPath: project.path, workspace: context.workspace)
        self.productReferenceIDs = Set(project.project.targets.compactMap { $0.product?.uuid })
    }

    /// The GUIDs of the variant group children the group tree lists outside their group
    /// (``listedElements(_:)``), whose build files Xcode gives GUIDs drawn at random.
    func liftedChildGUIDs() -> [String] {
        func walk(_ element: PBXFileElement) -> [String] {
            switch element {
            case let variantGroup as PBXVariantGroup: return listedElements(variantGroup).filter { $0 !== variantGroup }.map(guid)
            case let group as PBXGroup where !(group is XCVersionGroup): return group.children.flatMap(walk)
            default: return []
            }
        }
        return project.project.mainGroup.map(walk) ?? []
    }


    func guid(_ object: PBXObject) -> String {
        PIFIdentifiers.objectGUID(projectGUID: projectGUID, objectID: object.uuid)
    }

    mutating func generate() throws -> (PIFDocument.Object, [PIFDocument.Object]) {
        let root = project.project
        if fileTypes == nil { fileTypes = try FileTypeRegistry.installed() }
        if let mainGroup = root.mainGroup {
            referencePaths = Self.referencePaths(mainGroup: mainGroup, projectDirectory: project.projectDirectory)
            for reference in recoveredReferences(mainGroup) {
                referencePaths[reference.uuid] = Self.directory(of: reference, parentDirectory: project.projectDirectory, projectDirectory: project.projectDirectory)
            }
        }
        try prepareSynchronizedRoots()
        legacyBuildFolder = readLegacyBuildFolder()
        var targetObjects: [PIFDocument.Object] = []
        for target in root.targets {
            let contents = try targetContents(target)
            targetObjects.append(PIFDocument.Object(type: "target", signature: PIFIdentifiers.signature(prefix: "TARGET", contents: contents), contents: contents))
        }

        var contents: [String: PIFValue] = [
            "appPreferencesBuildSettings": .object([:]),
            "buildConfigurations": .array(try buildConfigurations(root.buildConfigurationList)),
            "classPrefix": .string(Self.stringAttribute(root.attributes["CLASSPREFIX"]) ?? ""),
            "defaultConfigurationName": .string(root.buildConfigurationList?.defaultConfigurationName ?? "Release"),
            "guid": .string(projectGUID),
            "groupTree": try groupTree(root.mainGroup),
            "path": .string(project.path),
            "projectDirectory": .string(project.projectDirectory),
            "targets": .array(targetObjects.map { .string($0.signature) }),
        ]
        if let region = root.developmentRegion {
            contents["developmentRegion"] = .string(region)
        }
        contents["knownRegions"] = .array(knownRegions().map(PIFValue.string))
        let value = PIFValue.object(contents)
        let projectObject = PIFDocument.Object(type: "project", signature: PIFIdentifiers.signature(prefix: "PROJECT", contents: value), contents: value)
        return (projectObject, targetObjects)
    }

    // MARK: Build configurations

    /// The configurations of a list, with `searchPaths` added to each one's settings.
    func buildConfigurations(_ list: XCConfigurationList?, searchPaths: [(setting: String, paths: [String])] = []) throws -> [PIFValue] {
        guard let list else { return [] }
        return list.buildConfigurations.map { configuration in
            var settings = Self.buildSettings(configuration.buildSettings)
            if project.pbxproj.objectVersion < 50 { Self.splitWholeModuleOptimization(&settings) }
            for (setting, paths) in searchPaths {
                settings[setting] = .string(Self.addingSearchPaths(paths, to: settings[setting]?.stringValue))
            }
            var contents: [String: PIFValue] = [
                "buildSettings": .object(settings),
                "guid": .string(guid(configuration)),
                "name": .string(configuration.name),
            ]
            if let base = configuration.baseConfiguration {
                contents["baseConfigurationFileReference"] = .string(guid(base))
            } else if let anchored = anchoredBaseConfigurationGUID(configuration) {
                contents["baseConfigurationFileReference"] = .string(anchored)
            }
            return .object(contents)
        }
    }

    /// Below objectVersion 50, Xcode writes a configuration's `SWIFT_OPTIMIZATION_LEVEL =
    /// -Owholemodule`, the value from before `SWIFT_COMPILATION_MODE`, as `-O` and
    /// `SWIFT_COMPILATION_MODE = wholemodule`, unless the configuration sets the mode; a
    /// condition, an xcconfig and `OTHER_SWIFT_FLAGS` keep the value (loader-experiments
    /// `swift-wholemodule`, `-42` to `-70`; delta's objectVersion-46 projects).
    static func splitWholeModuleOptimization(_ settings: inout [String: PIFValue]) {
        guard settings["SWIFT_OPTIMIZATION_LEVEL"]?.stringValue == "-Owholemodule",
              !settings.keys.contains(where: { XCConfigFile.key($0)?.name == "SWIFT_COMPILATION_MODE" }) else { return }
        settings["SWIFT_OPTIMIZATION_LEVEL"] = .string("-O")
        settings["SWIFT_COMPILATION_MODE"] = .string("wholemodule")
    }

    /// Project-file build settings become PIF strings. A list value in the project file is
    /// written as one string, its elements joined with single spaces as they are, without
    /// quoting (retro-rampage `GCC_PREPROCESSOR_DEFINITIONS`; `loader-experiments`: the element
    /// `FLAG WITH SPACE` becomes three words, `quote"inside` keeps its bare quote).
    static func buildSettings(_ settings: BuildSettings) -> [String: PIFValue] {
        var result: [String: PIFValue] = [:]
        for (key, value) in settings {
            switch value {
            case .string(let string):
                result[key] = .string(string)
            case .array(let array):
                result[key] = .string(array.joined(separator: " "))
            }
        }
        return result
    }

    static func stringAttribute(_ attribute: ProjectAttribute?) -> String? {
        if case .string(let value)? = attribute { return value }
        return nil
    }

    // MARK: Group tree

    func groupTree(_ mainGroup: PBXGroup?) throws -> PIFValue {
        guard let mainGroup else {
            throw NomacError("the project has no main group", path: project.path)
        }
        let tree = try reference(mainGroup, isRoot: true)
        let recovered = recoveredReferences(mainGroup)
        guard !recovered.isEmpty, var contents = tree.objectValue else { return tree }
        contents["children"] = .array((contents["children"]?.arrayValue ?? []) + [.object([
            "children": .array(try recovered.map { try reference($0) }),
            "guid": .string(projectGUID + MD5.hex(Self.recoveredGroupName)),
            "name": .string(Self.recoveredGroupName),
            "path": .string(""),
            "sourceTree": .string("<group>"),
            "type": .string("group"),
        ])])
        return .object(contents)
    }

    /// The group Xcode makes for file references that a build phase or a base configuration names and no
    /// group holds, as Expo's config plugins write them (`orphan_reference_experiments.py`, docs/formats/pif.md
    /// "Group tree"). Its GUID changes from run to run of the same project in Xcode.
    static let recoveredGroupName = "Recovered References"

    /// Those file references, the build phases' in their order and then the base configurations'. Product
    /// references, which are represented inside their targets, are not among them (`orphan-product`).
    func recoveredReferences(_ mainGroup: PBXGroup) -> [PBXFileReference] {
        var held = Set<String>()
        func walk(_ element: PBXFileElement) {
            held.insert(element.uuid)
            if let group = element as? PBXGroup { group.children.forEach(walk) }
        }
        walk(mainGroup)
        let root = project.project
        let targets = root.targets
        let named: [PBXFileElement?] = targets.flatMap { $0.buildPhases.flatMap { ($0.files ?? []).map(\.file) } }
            + (targets.map(\.buildConfigurationList) + [root.buildConfigurationList]).flatMap { $0?.buildConfigurations ?? [] }.map(\.baseConfiguration)
        var recovered: [PBXFileReference] = []
        for case let reference as PBXFileReference in named.compactMap({ $0 })
        where !productReferenceIDs.contains(reference.uuid) && held.insert(reference.uuid).inserted {
            recovered.append(reference)
        }
        return recovered
    }

    /// `folder` is a path the element's own is listed under.
    func reference(_ element: PBXFileElement, isRoot: Bool = false, regionVariant: Bool = false, folder: String? = nil) throws -> PIFValue {
        var contents: [String: PIFValue] = [
            "guid": .string(guid(element)),
            "sourceTree": .string(Self.sourceTree(element.sourceTree)),
        ]
        switch element {
        case let synchronized as PBXFileSystemSynchronizedRootGroup:
            return try synchronizedGroupReference(synchronized)
        case let variantGroup as PBXVariantGroup:
            contents["type"] = .string("variantGroup")
            contents["name"] = .string(element.name ?? element.path ?? "")
            contents["path"] = .string(element.path ?? "")
            let children = try variantGroup.children.filter { region(of: $0) != nil }.map { try reference($0, regionVariant: true) }
            if !children.isEmpty { contents["children"] = .array(children) }
        case let versionGroup as XCVersionGroup:
            contents["type"] = .string("versionGroup")
            contents["name"] = .string(element.name ?? ((element.path ?? "") as NSString).lastPathComponent)
            contents["path"] = .string(element.path ?? "")
            // The type of the folder's extension (`loader-experiments`: Model.xcdatamodeld is
            // `wrapper.xcdatamodeld`, although its versionGroupType is wrapper.xcdatamodel).
            if let fileType = fileTypes?.type(forExtension: ((element.path ?? "") as NSString).pathExtension) {
                contents["fileType"] = .string(fileType)
            }
            let children = try versionGroup.children.map { try reference($0) }
            if !children.isEmpty { contents["children"] = .array(children) }
        case let group as PBXGroup:
            contents["type"] = .string("group")
            // The root group is named after the project, whatever the main group's `name`
            // (loader-experiments `root-group-name`, `-path`, `-name-path`; wordpress's `CustomTemplate`).
            if isRoot {
                contents["name"] = .string(project.name)
            } else {
                contents["name"] = .string(element.name ?? ((element.path ?? "") as NSString).lastPathComponent)
            }
            contents["path"] = .string(element.path ?? "")
            let children = try children(of: group)
            if !children.isEmpty { contents["children"] = .array(children) }
        case let file as PBXFileReference:
            contents["type"] = .string("file")
            contents["path"] = .string(folder.map { ($0 as NSString).appendingPathComponent(file.path ?? file.name ?? "") } ?? file.path ?? file.name ?? "")
            let fileType = self.fileType(of: file)
            contents["fileType"] = .string(fileType)
            if let encoding = file.fileEncoding, !Self.typesWithoutTextEncoding.contains(fileType), let name = Self.textEncodingName(encoding) {
                contents["fileTextEncoding"] = .string(name)
            }
            if regionVariant, let region = region(of: file) {
                contents["regionVariantName"] = .string(region)
            }
            if let signature = file.expectedSignature {
                contents["expectedSignature"] = .string(signature)
            }
        default:
            throw NomacError("unsupported group-tree element \(type(of: element)) (\(element.uuid))", path: project.path)
        }
        return .object(contents)
    }

    /// The PIF spelling of a source tree: the same string the project file uses.
    static func sourceTree(_ tree: PBXSourceTree?) -> String {
        switch tree {
        case nil, .group?: return "<group>"
        case .none?: return "<none>"
        case .absolute?: return "<absolute>"
        case .sourceRoot?: return "SOURCE_ROOT"
        case .buildProductsDir?: return "BUILT_PRODUCTS_DIR"
        case .sdkRoot?: return "SDKROOT"
        case .developerDir?: return "DEVELOPER_DIR"
        case .custom(let value)?: return value
        }
    }

    /// The IANA character-set name Xcode records for a project file's `fileEncoding`
    /// (an `NSStringEncoding` value), as `CFStringConvertEncodingToIANACharSetName` names it.
    static func textEncodingName(_ encoding: UInt) -> String? {
        switch encoding {
        case 1: return "us-ascii"
        case 3: return "euc-jp"
        case 4: return "utf-8"
        case 5: return "iso-8859-1"
        case 8: return "cp932"
        case 9: return "iso-8859-2"
        case 10: return "utf-16"
        case 11: return "windows-1251"
        case 12: return "windows-1252"
        case 13: return "windows-1253"
        case 14: return "windows-1254"
        case 15: return "windows-1250"
        case 21: return "iso-2022-jp"
        case 30: return "macintosh"
        case 0x9000_0100: return "utf-16be"
        case 0x9400_0100: return "utf-16le"
        case 0x8C00_0100: return "utf-32"
        case 0x9800_0100: return "utf-32be"
        case 0x9C00_0100: return "utf-32le"
        default: return nil
        }
    }
}
