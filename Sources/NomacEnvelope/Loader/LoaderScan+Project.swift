import Foundation
import NomacCore
import NomacPIF

extension LoaderScan {
    enum Spelling { case exact, otherCase, missing }

    /// Whether `path` names an item on disk with this spelling, only with another case in some
    /// component, or not at all, whatever the file system's own case sensitivity: macOS's default
    /// file system finds `PdfGeneration` for `PDFGeneration`, Linux's does not (cwa's
    /// `PDFGeneration` folder, `PdfGeneration` on disk; BACKLOG B-062).
    func spelling(of path: String) -> Spelling {
        var directory = "/"
        var spelling = Spelling.exact
        for component in path.split(separator: "/").map(String.init) {
            if component == "." { continue }
            if component == ".." {
                directory = (directory as NSString).deletingLastPathComponent
                continue
            }
            if listings[directory] == nil {
                listings[directory] = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
            }
            let entries = listings[directory] ?? []
            if !entries.contains(component) {
                guard let other = entries.first(where: { $0.caseInsensitiveCompare(component) == .orderedSame }) else { return .missing }
                spelling = .otherCase
                directory = (directory as NSString).appendingPathComponent(other)
                continue
            }
            directory = (directory as NSString).appendingPathComponent(component)
        }
        return spelling
    }

    /// Keys whose values are features of their own, for any object type.
    static let valueKeys: Set<String> = [
        "sourceTree", "buildActionMask", "runOnlyForDeploymentPostprocessing", "platformFilter", "proxyType", "productType",
        "fileEncoding", "dstSubfolderSpec", "dstSubfolder", "showEnvVarsInLog", "alwaysOutOfDate", "compilerSpec", "isEditable",
        "runOncePerArchitecture", "passBuildSettingsInEnvironment", "defaultConfigurationIsVisible", "versionGroupType",
        "minimizedProjectReferenceProxies",
    ]

    /// The settings nomac reads itself, not only through Swift Build (docs/formats/pif.md
    /// "Target object"): how they are written decides whether nomac reads them as Xcode does.
    static let readSettings = ["INFOPLIST_FILE", "CODE_SIGN_STYLE", "PROVISIONING_PROFILE_SPECIFIER", "PROVISIONING_PROFILE", "GENERATE_INFOPLIST_FILE",
                               "CODE_SIGN_IDENTITY", "PRODUCT_NAME"]

    /// Reads a project and reports its features; nil when it cannot be read.
    func scanProject(_ path: String) -> RawProject? {
        if FileSystem.isFile(path + "/project.xcproj") {
            use("pbxproj:format=xcproj", path + "/project.xcproj", "project.xcproj")
            unchecked.append(UncheckedPart(what: "objects of a project.xcproj (BACKLOG B-083)", file: path + "/project.xcproj"))
            return nil
        }
        let project: RawProject
        do {
            project = try RawProject.load(path)
        } catch .missing {
            use("pbxproj:file=missing", path, (path as NSString).lastPathComponent)
            return nil
        } catch {
            use("pbxproj:file=unreadable", path + "/project.pbxproj", "project.pbxproj")
            return nil
        }
        let file = project.file
        use("pbxproj:format=pbxproj", file, "project.pbxproj")
        for (key, value) in project.topLevel.sorted(by: { $0.key < $1.key }) {
            switch key {
            case "objects", "rootObject":
                continue
            case "archiveVersion", "objectVersion":
                use("pbxproj:\(key)=\(value)", file, key)
            case "classes":
                if let classes = value as? [String: Any], classes.isEmpty { continue }
                use("pbxproj:classes", file, key)
            default:
                use("pbxproj:\(key)", file, key)
            }
        }
        for id in project.objects.keys.sorted() {
            scanObject(id, in: project)
        }
        scanProjectShapes(project)
        scanProjectNames(project)
        scanSharedSchemes(in: path + "/xcshareddata/xcschemes", containerDirectory: (path as NSString).deletingLastPathComponent)
        scanUserData(of: path)
        return project
    }

    private func scanObject(_ id: String, in project: RawProject) {
        guard let object = project.objects[id] else { return }
        let file = project.file
        let label = project.describe(id)
        guard let isa = object["isa"] as? String else {
            use("pbxproj:object=without-isa", file, label)
            return
        }
        use("pbxproj:\(isa)", file, label)
        if !RawProject.isObjectID(id) { use("pbxproj:object-id=not-hexadecimal", file, label) }
        for (key, value) in object.sorted(by: { $0.key < $1.key }) where key != "isa" {
            let feature = "pbxproj:\(isa).\(key)"
            use(feature, file, label)
            if Self.valueKeys.contains(key), let string = value as? String {
                use("\(feature)=\(string)", file, label)
            }
            switch (isa, key) {
            case (_, "platformFilters"):
                for filter in value as? [String] ?? [] { use("\(feature)=\(filter)", file, label) }
            case ("PBXReferenceProxy", "fileType"), ("PBXBuildRule", "fileType"):
                if let string = value as? String { use("\(feature)=\(string)", file, label) }
            case ("PBXProject", "attributes"):
                scanProjectAttributes(value as? [String: Any] ?? [:], file: file, object: label)
            case ("PBXProject", "projectReferences"):
                for reference in value as? [[String: Any]] ?? [] {
                    for referenceKey in reference.keys.sorted() { use("\(feature).\(referenceKey)", file, label) }
                }
            case ("PBXProject", "projectDirPath"):
                if let string = value as? String, !string.isEmpty { use("\(feature)=set", file, label) }
            case ("PBXBuildFile", "settings"):
                for (setting, settingValue) in (value as? [String: Any] ?? [:]).sorted(by: { $0.key < $1.key }) {
                    use("\(feature).\(setting)", file, label)
                    if setting == "ATTRIBUTES" {
                        for attribute in settingValue as? [String] ?? [] { use("\(feature).ATTRIBUTES=\(attribute)", file, label) }
                    }
                }
            case ("XCBuildConfiguration", "buildSettings"):
                scanBuildSettings(value as? [String: Any] ?? [:], file: file, object: label, level: "\(file)#\(id)")
            case ("XCRemoteSwiftPackageReference", "requirement"):
                for (requirementKey, requirementValue) in (value as? [String: Any] ?? [:]).sorted(by: { $0.key < $1.key }) {
                    use("\(feature).\(requirementKey)", file, label)
                    if requirementKey == "kind", let kind = requirementValue as? String { use("\(feature).kind=\(kind)", file, label) }
                }
            case ("XCSwiftPackageProductDependency", "productName"):
                if (value as? String)?.hasPrefix("plugin:") == true { use("\(feature)=plugin", file, label) }
            case ("PBXFileSystemSynchronizedRootGroup", "explicitFileTypes"):
                for type in (value as? [String: String] ?? [:]).values.sorted() { use("\(feature)=\(type)", file, label) }
            case ("PBXFileSystemSynchronizedBuildFileExceptionSet", "attributesByRelativePath"), ("PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet", "attributesByRelativePath"),
                 ("PBXFileSystemSynchronizedBuildFileExceptionSet", "platformFiltersByRelativePath"):
                let values = (value as? [String: [String]] ?? [:]).values.flatMap { $0 }
                for value in Set(values).sorted() { use("\(feature)=\(value)", file, label) }
            default:
                break
            }
            if RawProject.referenceKeys.contains(key) {
                let targets = (value as? [String]) ?? [value as? String].compactMap { $0 }
                for target in targets where project.objects[target] == nil {
                    // Such a build file counts where a phase's synchronized members go
                    // (envelope-experiments `survey-shapes-4`; docs/formats/pif.md "Order in a phase").
                    let besideMembers = isa == "PBXBuildFile" && key == "fileRef" && isBesideSynchronizedMembers(id, in: project)
                    use("pbxproj:\(isa).\(key)=dangling" + (besideMembers ? "-beside-synchronized-members" : ""), file, label)
                }
            }
        }
        switch isa {
        case "PBXFileReference":
            let type = (object["explicitFileType"] as? String) ?? (object["lastKnownFileType"] as? String)
            use("pbxproj:PBXFileReference.fileType=\(type ?? untypedKind(object))", file, label)
            if !options.descriptionOnly, let path = project.fullPath(id), (object["sourceTree"] as? String) != "BUILT_PRODUCTS_DIR" {
                switch spelling(of: path) {
                case .exact: break
                case .otherCase: use("pbxproj:PBXFileReference.path=case-mismatch", file, label)
                case .missing:
                    use("pbxproj:PBXFileReference.path=missing", file, label)
                    if let type, Self.retypedTypes.contains(type) { use("pbxproj:PBXFileReference.path=missing-\(type)", file, label) }
                }
            }
        case "PBXCopyFilesBuildPhase":
            if object["dstSubfolderSpec"] == nil && object["dstSubfolder"] == nil { use("pbxproj:PBXCopyFilesBuildPhase.dstSubfolderSpec=none", file, label) }
        case "PBXVariantGroup":
            scanVariantGroup(id, in: project)
        case "PBXNativeTarget":
            if object["productReference"] == nil { use("pbxproj:PBXNativeTarget.productReference=absent", file, label) }
        case "XCBuildConfiguration":
            scanBaseConfiguration(id, in: project)
        case "XCLocalSwiftPackageReference":
            if let relative = object["relativePath"] as? String {
                addPackageDirectory(((project.projectDirectory as NSString).appendingPathComponent(relative) as NSString).standardizingPath)
            }
        case "XCRemoteSwiftPackageReference":
            if let url = object["repositoryURL"] as? String { remotePackageURLs.append(url) }
        case "PBXFileSystemSynchronizedRootGroup":
            scanSynchronizedRoot(id, in: project)
        default:
            break
        }
    }

    /// A reference without a type gets the one its extension names, unless the extension names
    /// none or is `.plist`: then its contents decide (docs/formats/project-file.md).
    private func untypedKind(_ object: [String: Any]) -> String {
        let ext = (((object["path"] as? String) ?? (object["name"] as? String) ?? "") as NSString).pathExtension
        guard let type = fileTypeRegistry()?.type(forExtension: ext), type != "text.plist" else { return "none-by-contents" }
        return "none"
    }

    /// The project's `attributes`, and the keys of each target's `TargetAttributes` entry.
    private func scanProjectAttributes(_ attributes: [String: Any], file: String, object: String) {
        for (key, value) in attributes.sorted(by: { $0.key < $1.key }) {
            use("pbxproj:PBXProject.attributes.\(key)", file, object)
            guard key == "TargetAttributes", let targets = value as? [String: [String: Any]] else { continue }
            for (target, targetAttributes) in targets.sorted(by: { $0.key < $1.key }) {
                for (attribute, attributeValue) in targetAttributes.sorted(by: { $0.key < $1.key }) {
                    use("pbxproj:PBXProject.attributes.TargetAttributes.\(attribute)", file, "\(object) target \(target)")
                    if attribute == "ProvisioningStyle", let style = attributeValue as? String {
                        use("pbxproj:PBXProject.attributes.TargetAttributes.ProvisioningStyle=\(style)", file, "\(object) target \(target)")
                    }
                }
            }
        }
    }

    /// Declared types Xcode types again from disk, which a missing file of codegen-file-types
    /// shows as `text` (docs/formats/pif.md "Group tree").
    static let retypedTypes: Set<String> = [
        "file", "file.icon", "file.strings", "file.usdz", "image.heic", "image.svg", "wrapper.framework.static", "wrapper.rcproject",
        "folder.mlmodelc", "wrapper.mlmodelc", "file.mlmodelc", "folder.rcproject", "file.realitycomposerpro",
    ]

    /// The regions other than `mul` of a variant group's children in `.lproj` folders that
    /// `knownRegions` lacks, compared without case.
    private func missingRegions(_ id: String, in project: RawProject) -> Set<String> {
        let known = Set((project.root["knownRegions"] as? [String] ?? []).map { $0.lowercased() })
        return Set(project.strings(id, "children").compactMap { region(of: $0, in: project)?.lowercased() }.filter { !known.contains($0) && $0 != "mul" })
    }

    /// The region of a variant group's child: its folder's name without `.lproj`; `nil` when the
    /// child is not directly in a `.lproj` folder.
    private func region(of child: String, in project: RawProject) -> String? {
        let path = project.fullPath(child) ?? project.string(child, "path") ?? ""
        let folder = ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
        return folder.hasSuffix(".lproj") ? String(folder.dropLast(".lproj".count)) : nil
    }

    /// Children of a classic variant group that are not directly in a `.lproj` folder, their
    /// groups' paths included, and regions `knownRegions` lacks (docs/formats/pif.md "Group tree").
    private func scanVariantGroup(_ id: String, in project: RawProject) {
        let known = Set((project.root["knownRegions"] as? [String] ?? []).map { $0.lowercased() })
        for child in project.strings(id, "children") {
            guard let region = region(of: child, in: project) else {
                use("pbxproj:PBXVariantGroup.children=outside-lproj", project.file, project.describe(child))
                continue
            }
            if !known.contains(region.lowercased()) {
                use(region == "mul" ? "pbxproj:PBXVariantGroup.children=mul-not-in-knownRegions" : "pbxproj:PBXVariantGroup.children=region-not-in-knownRegions",
                    project.file, project.describe(child))
            }
        }
    }

    /// A configuration's base xcconfig: on disk or not, and its own features.
    private func scanBaseConfiguration(_ id: String, in project: RawProject) {
        let label = project.describe(id)
        if let reference = project.string(id, "baseConfigurationReference") {
            guard let path = project.fullPath(reference) else {
                use("pbxproj:XCBuildConfiguration.baseConfigurationReference=outside-source-tree", project.file, label)
                return
            }
            scanXCConfig(path, from: project.file, object: label, level: path)
        } else if let anchor = project.string(id, "baseConfigurationReferenceAnchor"), let relative = project.string(id, "baseConfigurationReferenceRelativePath"),
                  let folder = project.fullPath(anchor) {
            let path = (folder as NSString).appendingPathComponent(relative)
            scanXCConfig(path, from: project.file, object: label, level: path)
        }
    }

    /// Shapes that involve several objects of one project.
    private func scanProjectShapes(_ project: RawProject) {
        // Xcode appends the regions several variant groups add in an order that changes from one
        // run to the next (envelope-experiments `variant-groups`: `regions-two-groups`; BACKLOG B-030).
        let added = project.objects.keys.sorted().filter { project.isa($0) == "PBXVariantGroup" }.map { missingRegions($0, in: project) }.filter { !$0.isEmpty }
        if added.count > 1, added.reduce(Set<String>(), { $0.union($1) }).count > 1 {
            use("pbxproj:PBXVariantGroup.children=regions-from-several-groups", project.file, project.describe(project.rootID))
        }
        let file = project.file
        let targets = project.targetIDs
        let projectDefault = project.string(project.string(project.rootID, "buildConfigurationList") ?? "", "defaultConfigurationName")
        func productType(_ target: String) -> String { project.string(target, "productType") ?? "" }
        func dependencies(_ target: String) -> [String] { project.strings(target, "dependencies") }
        func localTargets(_ target: String) -> [String] { dependencies(target).compactMap { project.string($0, "target") } }
        for target in targets {
            let label = project.describe(target)
            if let list = project.string(target, "buildConfigurationList"), let defaultName = project.string(list, "defaultConfigurationName"),
               let projectDefault, defaultName != projectDefault {
                use("pbxproj:XCConfigurationList.defaultConfigurationName=differs-from-project", file, label)
            }
            let type = productType(target)
            if Self.testBundleTypes.contains(type) {
                let deps = dependencies(target)
                if deps.isEmpty && !project.strings(target, "packageProductDependencies").isEmpty {
                    use("pbxproj:PBXNativeTarget.testBundle=package-products-only", file, label)
                }
                if deps.contains(where: { project.string($0, "target") == nil && project.string($0, "targetProxy").map { isRemoteProxy($0, in: project) } == true }) {
                    use("pbxproj:PBXNativeTarget.testBundle=depends-on-other-project", file, label)
                }
            }
            if Self.extensionTypes.contains(type) {
                let direct = targets.filter { localTargets($0).contains(target) }
                let hosts = targets.filter { host in
                    Self.hostAppTypes.contains(productType(host)) && (direct.contains(host) || direct.contains { localTargets(host).contains($0) })
                }
                if hosts.count > 1 { use("pbxproj:PBXNativeTarget.extension=several-host-apps", file, label) }
            }
            scanPackageProductLinking(target, in: project)
        }
        let buildFolder = legacyBuildFolder(of: project)
        for proxy in project.objects.keys.sorted() where project.isa(proxy) == "PBXReferenceProxy" {
            guard let remote = project.string(proxy, "remoteRef") else { continue }
            if !resolvesInOtherProject(remote, in: project) {
                // nomac computes the GUID Xcode gives its build files only for a proxy relative to the
                // products folder of a project whose legacy build folder it computes (B-036).
                let computed = buildFolder != nil && project.string(proxy, "sourceTree") == "BUILT_PRODUCTS_DIR" && project.string(proxy, "path") != nil
                use("pbxproj:PBXReferenceProxy.remoteRef=" + (computed ? "unresolved" : "unresolved-other-build-folder"), file, project.describe(proxy))
            }
        }
        for dependency in project.objects.keys.sorted() where project.isa(dependency) == "PBXTargetDependency" {
            // A proxy into this project that names no target (loader-experiments `dependency-proxies`).
            if let proxy = project.string(dependency, "targetProxy"), project.string(proxy, "containerPortal") == project.rootID,
               project.string(dependency, "target").map({ project.objects[$0] == nil }) ?? true,
               project.string(proxy, "remoteGlobalIDString").map({ project.isa($0) == nil }) ?? true,
               Self.target(named: project.string(proxy, "remoteInfo"), in: project) == nil {
                use("pbxproj:PBXTargetDependency.targetProxy=unresolved-in-project", file, project.describe(dependency))
            }
            guard project.string(dependency, "target") == nil, let proxy = project.string(dependency, "targetProxy"), isRemoteProxy(proxy, in: project) else { continue }
            guard let remote = remoteObject(proxy, in: project) else {
                use("pbxproj:PBXTargetDependency.targetProxy=unresolved", file, project.describe(dependency))
                continue
            }
            use("pbxproj:PBXTargetDependency.targetProxy=other-project", file, project.describe(dependency))
            // Xcode's autocreated scheme of an extension also builds the apps of other projects that
            // depend on it, which nomac's does not (envelope-experiments `proxy-file-types`, B-014).
            if Self.extensionTypes.contains(remote["productType"] as? String ?? "") {
                use("pbxproj:PBXTargetDependency.targetProxy=other-project-extension", file, project.describe(dependency))
            }
        }
        for reference in project.root["projectReferences"] as? [[String: Any]] ?? [] {
            guard let ref = reference["ProjectRef"] as? String, let path = project.fullPath(ref) else { continue }
            if !FileSystem.isDirectory(path) { use("pbxproj:PBXProject.projectReferences=missing-project", file, project.describe(ref)) }
        }
        if options.descriptionOnly {
            unchecked.append(UncheckedPart(what: "presence of the files the project references, which decides the types Xcode gives some of them", file: file))
        }
        if let mainGroup = project.string(project.rootID, "mainGroup") { collectRootPackages(mainGroup, in: project) }
    }

    static let testBundleTypes: Set<String> = ["com.apple.product-type.bundle.unit-test", "com.apple.product-type.bundle.ui-testing"]
    static let extensionTypes: Set<String> = Set(["app-extension", "extensionkit-extension", "app-extension.messages-sticker-pack", "app-extension.messages",
                                                  "tv-app-extension", "xcode-extension"].map { "com.apple.product-type." + $0 })
    static let hostAppTypes: Set<String> = Set(["application", "application.on-demand-install-capable", "application.watchapp2", "application.messages"]
        .map { "com.apple.product-type." + $0 })

    /// Whether a container item proxy points into another project (through a file reference).
    private func isRemoteProxy(_ proxy: String, in project: RawProject) -> Bool {
        guard let portal = project.string(proxy, "containerPortal") else { return false }
        return project.isa(portal) == "PBXFileReference"
    }

    /// Whether a proxy's remote object exists in the project its container portal names.
    private func resolvesInOtherProject(_ proxy: String, in project: RawProject) -> Bool {
        remoteObject(proxy, in: project) != nil
    }

    /// Whether a build file is in a phase of a target that has synchronized folders.
    private func isBesideSynchronizedMembers(_ buildFile: String, in project: RawProject) -> Bool {
        project.targetIDs.contains { target in
            !project.strings(target, "fileSystemSynchronizedGroups").isEmpty
                && project.strings(target, "buildPhases").contains { project.strings($0, "files").contains(buildFile) }
        }
    }

    /// The project's ``LegacyBuildFolder``, as the PIF generator reads it; a base xcconfig in a
    /// synchronized folder is not read here, so it leaves the folder unknown.
    private func legacyBuildFolder(of project: RawProject) -> String? {
        let configurations = project.string(project.rootID, "buildConfigurationList").map { project.strings($0, "buildConfigurations") } ?? []
        guard let name = LegacyBuildFolder.configuration(among: configurations.compactMap { project.string($0, "name") }),
              let configuration = configurations.first(where: { project.string($0, "name") == name }),
              project.string(configuration, "baseConfigurationReferenceAnchor") == nil else { return nil }
        let settings = (project.objects[configuration]?["buildSettings"] as? [String: Any] ?? [:]).mapValues { $0 as? String }
        return LegacyBuildFolder.path(projectDirectory: project.projectDirectory, configuration: name, settings: settings,
                                      xcconfig: project.string(configuration, "baseConfigurationReference").flatMap(project.fullPath))
    }

    /// The object a proxy's remote ID names in the project its container portal names, else the
    /// target its `remoteInfo` names there (loader-experiments `project-references-renamed`).
    private func remoteObject(_ proxy: String, in project: RawProject) -> [String: Any]? {
        guard let portal = project.string(proxy, "containerPortal"), let path = project.fullPath(portal),
              let remoteID = project.string(proxy, "remoteGlobalIDString"),
              let other = (projects.first { $0.path == path }) ?? (try? RawProject.load(path)) else { return nil }
        return other.objects[remoteID] ?? Self.target(named: project.string(proxy, "remoteInfo"), in: other).flatMap { other.objects[$0] }
    }

    /// The first target of `project` named `name`.
    static func target(named name: String?, in project: RawProject) -> String? {
        project.targetIDs.first { name != nil && project.string($0, "name") == name }
    }

    /// How a target names the package products and targets of its PIF `dependencies`
    /// (docs/formats/pif.md "Target object"): products it lists that only a second Frameworks
    /// phase links, product build files outside its first Frameworks phase, and a product or a
    /// target named several times.
    private func scanPackageProductLinking(_ target: String, in project: RawProject) {
        let phases = project.strings(target, "buildPhases")
        let frameworks = phases.filter { project.isa($0) == "PBXFrameworksBuildPhase" }
        func linked(_ phase: String) -> [String] { project.strings(phase, "files").compactMap { project.string($0, "productRef") } }
        let listed = project.strings(target, "packageProductDependencies")
        let first = frameworks.first.map(linked) ?? []
        let later = Set(frameworks.dropFirst().flatMap(linked))
        for product in listed where !first.contains(product) && later.contains(product) {
            use("pbxproj:XCSwiftPackageProductDependency.linked=second-frameworks-phase", project.file, project.describe(product))
        }
        for phase in phases where phase != frameworks.first {
            for file in project.strings(phase, "files") where project.string(file, "productRef") != nil {
                use("pbxproj:PBXBuildFile.productRef=outside-first-frameworks-phase", project.file, project.describe(file))
            }
        }
        let dependencies = project.strings(target, "dependencies")
        let unlinked = frameworks.isEmpty ? [] : listed.filter { !first.contains($0) }
        let products = (dependencies.compactMap { project.string($0, "productRef") } + unlinked + first).map { project.string($0, "productName") ?? $0 }
        if Set(products).count < products.count {
            use("pbxproj:PBXNativeTarget.dependencies=product-several-times", project.file, project.describe(target))
        }
        let targets = dependencies.compactMap { project.string($0, "target") ?? project.string($0, "targetProxy").flatMap { project.string($0, "remoteGlobalIDString") } }
        if Set(targets).count < targets.count {
            use("pbxproj:PBXNativeTarget.dependencies=target-several-times", project.file, project.describe(target))
        }
    }

    /// Package folders in the group tree are root packages (docs/formats/pif.md "Swift packages").
    private func collectRootPackages(_ id: String, in project: RawProject) {
        switch project.isa(id) {
        case "PBXGroup":
            for child in project.strings(id, "children") { collectRootPackages(child, in: project) }
        case "PBXFileReference":
            if let path = project.fullPath(id), FileSystem.isFile(path + "/Package.swift") {
                use("pbxproj:PBXFileReference=package-folder", project.file, project.describe(id))
                addPackageDirectory(path, root: true)
            }
        case "PBXFileSystemSynchronizedRootGroup":
            if let path = project.fullPath(id) { packageFolders(under: path) }
        default:
            break
        }
    }

    private func packageFolders(under directory: String) {
        if FileSystem.isFile(directory + "/Package.swift") {
            addPackageDirectory(directory, root: true)
            return
        }
        for name in (try? FileSystem.sortedContents(of: directory)) ?? [] where !name.hasPrefix(".") && FileSystem.isDirectory(directory + "/" + name) {
            packageFolders(under: directory + "/" + name)
        }
    }

    func addPackageDirectory(_ directory: String, root: Bool = false) {
        if root { rootPackageDirectories.insert(directory) }
        if !packageDirectories.contains(directory) { packageDirectories.append(directory) }
    }

    /// Shapes across the workspace's projects.
    func scanAcrossProjects() {
        var owners: [String: Set<String>] = [:]
        var first: [String: (String, String)] = [:]
        for project in projects {
            for target in project.targetIDs {
                guard let name = project.string(target, "name") else { continue }
                owners[name, default: []].insert(project.path)
                if first[name] == nil { first[name] = (project.file, project.describe(target)) }
            }
        }
        for (name, paths) in owners.sorted(by: { $0.key < $1.key }) where paths.count > 1 {
            if let (file, object) = first[name] { use("workspace:target-name=in-several-projects", file, object) }
        }
    }
}
