import Foundation
import Testing
import NomacCore
import NomacPackages
import NomacPIF
import NomacProject
import NomacTestSupport
@testable import NomacInspect

/// Projects shaped like loader-experiments' `project-references`, `project-references-workspace`,
/// `project-references-missing`, `project-references-packages`, `project-references-stale`,
/// `project-references-bundles`, `project-reference-names` and `workspace-names`, written again here; what Xcode 27.0 did with them is each test's expectation.
struct ReferencedProjects {
    struct Target {
        var name: String
        /// The product type without `com.apple.product-type.`.
        var type = "library.static"
        /// The targets it depends on and the products it links, each (referenced project, target).
        var dependencies: [(String, String)] = []
        var links: [(String, String)] = []
    }

    struct Project {
        var prefix: Character
        var targets: [Target]
        /// Referenced projects, relative to the project's folder.
        var references: [String] = []
    }

    /// Projects by path; those in `missing` are referenced but not written.
    var projects: [String: Project]
    var missing: Set<String> = []
    var files: [String: String] = [:]

    static func id(_ prefix: Character, _ kind: Character, _ index: Int) -> String {
        "\(prefix)\(kind)" + String(repeating: "0", count: 22 - String(index).count) + String(index)
    }

    /// `reference`, relative to the folder of the project at `path`, as a path from the root.
    static func resolve(_ reference: String, from path: String) -> String {
        var components = (path as NSString).deletingLastPathComponent.split(separator: "/").map(String.init)
        for component in reference.split(separator: "/") {
            if component == ".." { components.removeLast() } else { components.append(String(component)) }
        }
        return components.joined(separator: "/")
    }

    func targetGUID(_ path: String, _ name: String) -> String {
        let project = projects[path]!
        return MD5.hex(path) + MD5.hex(Self.id(project.prefix, "T", project.targets.firstIndex { $0.name == name }!))
    }

    func pbxproj(_ path: String) -> String {
        let project = projects[path]!
        var objects = "", children = "", references = "", count = 0
        func next(_ kind: Character) -> String {
            count += 1
            return Self.id(project.prefix, kind, count)
        }
        func product(_ target: Target) -> (String, String) {
            switch target.type {
            case "application": ("wrapper.application", "\(target.name).app")
            case "bundle.unit-test": ("wrapper.cfbundle", "\(target.name).xctest")
            case "app-extension": ("wrapper.app-extension", "\(target.name).appex")
            default: ("archive.ar", "lib\(target.name).a")
            }
        }
        var files: [String: String] = [:], proxies: [String: String] = [:]
        for reference in project.references {
            let file = next("R"), group = next("G")
            files[reference] = file
            let other = projects[Self.resolve(reference, from: path)]!
            var proxyIDs = ""
            for (index, target) in other.targets.enumerated() {
                let proxy = next("Y"), item = next("X")
                let (fileType, name) = product(target)
                objects += "\(proxy) = {isa = PBXReferenceProxy; fileType = \(fileType); path = \"\(name)\"; remoteRef = \(item); sourceTree = BUILT_PRODUCTS_DIR; };\n"
                objects += "\(item) = {isa = PBXContainerItemProxy; containerPortal = \(file); proxyType = 2; remoteGlobalIDString = \(Self.id(other.prefix, "P", index)); remoteInfo = \(target.name); };\n"
                proxyIDs += "\(proxy), "
                proxies[reference + "/" + target.name] = proxy
            }
            objects += "\(file) = {isa = PBXFileReference; lastKnownFileType = \"wrapper.pb-project\"; name = \((reference as NSString).lastPathComponent); path = \"\(reference)\"; sourceTree = \"<group>\"; };\n"
            objects += "\(group) = {isa = PBXGroup; children = (\(proxyIDs)); name = Products; sourceTree = \"<group>\"; };\n"
            children += "\(file), "
            references += "{ProductGroup = \(group); ProjectRef = \(file); }, "
        }
        for (index, target) in project.targets.enumerated() {
            var dependencies = "", buildFiles = ""
            for (reference, name) in target.dependencies {
                let other = projects[Self.resolve(reference, from: path)]!
                let item = next("X"), dependency = next("D")
                let remote = Self.id(other.prefix, "T", other.targets.firstIndex { $0.name == name }!)
                objects += "\(item) = {isa = PBXContainerItemProxy; containerPortal = \(files[reference]!); proxyType = 1; remoteGlobalIDString = \(remote); remoteInfo = \(name); };\n"
                objects += "\(dependency) = {isa = PBXTargetDependency; name = \(name); targetProxy = \(item); };\n"
                dependencies += "\(dependency), "
            }
            for (reference, name) in target.links {
                let buildFile = next("B")
                objects += "\(buildFile) = {isa = PBXBuildFile; fileRef = \(proxies[reference + "/" + name]!); };\n"
                buildFiles += "\(buildFile), "
            }
            let phase = next("F"), list = next("L"), configuration = next("C")
            let (fileType, name) = product(target)
            objects += "\(phase) = {isa = PBXFrameworksBuildPhase; files = (\(buildFiles)); };\n"
            objects += "\(list) = {isa = XCConfigurationList; buildConfigurations = (\(configuration), ); defaultConfigurationName = Debug; };\n"
            objects += "\(configuration) = {isa = XCBuildConfiguration; buildSettings = {PRODUCT_NAME = \"$(TARGET_NAME)\"; }; name = Debug; };\n"
            objects += "\(Self.id(project.prefix, "P", index)) = {isa = PBXFileReference; explicitFileType = \(fileType); path = \"\(name)\"; sourceTree = BUILT_PRODUCTS_DIR; };\n"
            objects += "\(Self.id(project.prefix, "T", index)) = {isa = PBXNativeTarget; buildConfigurationList = \(list); buildPhases = (\(phase), ); dependencies = (\(dependencies)); name = \(target.name); productName = \(target.name); productReference = \(Self.id(project.prefix, "P", index)); productType = \"com.apple.product-type.\(target.type)\"; };\n"
            children += "\(Self.id(project.prefix, "P", index)), "
        }
        let root = Self.id(project.prefix, "J", 0), mainGroup = Self.id(project.prefix, "M", 0)
        let list = Self.id(project.prefix, "K", 0), configuration = Self.id(project.prefix, "K", 1)
        let targets = project.targets.indices.map { "\(Self.id(project.prefix, "T", $0)), " }.joined()
        objects += "\(mainGroup) = {isa = PBXGroup; children = (\(children)); sourceTree = \"<group>\"; };\n"
        objects += "\(list) = {isa = XCConfigurationList; buildConfigurations = (\(configuration), ); defaultConfigurationName = Debug; };\n"
        objects += "\(configuration) = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; }; name = Debug; };\n"
        objects += "\(root) = {isa = PBXProject; buildConfigurationList = \(list); mainGroup = \(mainGroup); projectDirPath = \"\"; projectReferences = (\(references)); projectRoot = \"\"; targets = (\(targets)); };\n"
        return "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tobjectVersion = 77;\n\tobjects = {\n\(objects)\t};\n\trootObject = \(root);\n}\n"
    }

    /// A shared scheme that builds `target` of the project at `path` and launches it if `launch`;
    /// `container` is the project's path relative to the scheme's project.
    func scheme(_ path: String, _ target: String, container: String, launch: Bool) -> String {
        let project = projects[path]!
        let reference = """
        <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "\(Self.id(project.prefix, "T", project.targets.firstIndex { $0.name == target }!))" \
        BuildableName = "\(target)" BlueprintName = "\(target)" ReferencedContainer = "container:\(container)"></BuildableReference>

        """
        let runnable = launch ? "<BuildableProductRunnable runnableDebuggingMode = \"0\">\n\(reference)</BuildableProductRunnable>\n" : ""
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <Scheme LastUpgradeVersion = "2700" version = "1.7">
        <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
        <BuildActionEntries>
        <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
        \(reference)</BuildActionEntry>
        </BuildActionEntries>
        </BuildAction>
        <LaunchAction buildConfiguration = "Debug" launchStyle = "0">
        \(runnable)</LaunchAction>
        </Scheme>

        """
    }

    func write(at root: String) throws {
        var all = files
        for path in projects.keys where !missing.contains(path) {
            all[path + "/project.pbxproj"] = pbxproj(path)
        }
        for (path, text) in all {
            try FileSystem.write(Data(text.utf8), to: root + "/" + path)
        }
    }

    /// `project-references`: P references Sub before Alpha, Sub references Deep through `..`; P's
    /// shared scheme builds Sub's Covered, Sub's builds and launches SubApp.
    static func experiment(workspace: Bool = false) -> ReferencedProjects {
        var fixture = ReferencedProjects(projects: [
            "P.xcodeproj": Project(prefix: "A", targets: [
                Target(name: "App", type: "application", dependencies: [("Sub/Sub.xcodeproj", "Lib"), ("Alpha/A.xcodeproj", "AlphaLib")], links: [("Sub/Sub.xcodeproj", "Lib")]),
                Target(name: "Twin"),
            ], references: ["Sub/Sub.xcodeproj", "Alpha/A.xcodeproj"]),
            "Sub/Sub.xcodeproj": Project(prefix: "B", targets: [
                Target(name: "Lib", dependencies: [("../Deep/Deep.xcodeproj", "DeepLib")]), Target(name: "SubApp", type: "application"),
                Target(name: "Covered"), Target(name: "Twin"),
            ], references: ["../Deep/Deep.xcodeproj"]),
            "Alpha/A.xcodeproj": Project(prefix: "C", targets: [Target(name: "AlphaLib")]),
            "Deep/Deep.xcodeproj": Project(prefix: "D", targets: [Target(name: "DeepLib")]),
        ])
        fixture.files["Sub/Sub.xcodeproj/xcshareddata/xcschemes/SubShared.xcscheme"] = fixture.scheme("Sub/Sub.xcodeproj", "SubApp", container: "Sub.xcodeproj", launch: true)
        fixture.files["P.xcodeproj/xcshareddata/xcschemes/PShared.xcscheme"] = fixture.scheme("Sub/Sub.xcodeproj", "Covered", container: "Sub/Sub.xcodeproj", launch: false)
        if workspace {
            fixture.files["W.xcworkspace/contents.xcworkspacedata"] = #"<?xml version="1.0" encoding="UTF-8"?><Workspace version = "1.0"><FileRef location = "group:P.xcodeproj"></FileRef></Workspace>"#
        }
        return fixture
    }
}

@Suite struct ProjectReferencesTests {
    static func target(_ document: PIFDocument, _ name: String) throws -> [String: PIFValue] {
        try #require(document.objects.first { $0.type == "target" && $0.contents.objectValue?["name"]?.stringValue == name }?.contents.objectValue)
    }

    /// `project-references`, `project-references-workspace`: referenced projects, and those they
    /// reference, are projects of the workspace, in path order, identified by their path from the
    /// opened container's folder; a product linked through a reference proxy is its target.
    @Test(arguments: ["P.xcodeproj", "W.xcworkspace"])
    func referencedProjectsJoinTheWorkspace(container: String) throws {
        let directory = try TemporaryDirectory()
        let fixture = ReferencedProjects.experiment(workspace: container == "W.xcworkspace")
        try fixture.write(at: directory.path)
        var generator = PIFGenerator(workspace: try XcodeWorkspace.load(path: directory.path + "/" + container))
        let document = try generator.generate()
        let projects = document.objects.filter { $0.type == "project" }.compactMap { $0.contents.objectValue?["guid"] }
        #expect(projects == ["Alpha/A.xcodeproj", "Deep/Deep.xcodeproj", "P.xcodeproj", "Sub/Sub.xcodeproj"].map { .string(MD5.hex($0)) })
        let app = try Self.target(document, "App")
        #expect(app["dependencies"] == .array([
            .object(["guid": .string(fixture.targetGUID("Sub/Sub.xcodeproj", "Lib")), "name": .string("Lib (from Sub.xcodeproj)")]),
            .object(["guid": .string(fixture.targetGUID("Alpha/A.xcodeproj", "AlphaLib")), "name": .string("AlphaLib (from A.xcodeproj)")]),
        ]))
        let linked = app["buildPhases"]?.arrayValue?.first?.objectValue?["buildFiles"]?.arrayValue?.first?.objectValue
        #expect(linked?["targetReference"] == .string(fixture.targetGUID("Sub/Sub.xcodeproj", "Lib")))
        #expect(linked?["fileReference"] == nil)
        #expect(try Self.target(document, "Lib")["dependencies"] == .array([
            .object(["guid": .string(fixture.targetGUID("Deep/Deep.xcodeproj", "DeepLib")), "name": .string("DeepLib (from Deep.xcodeproj)")]),
        ]))
    }

    /// The GUID Xcode gives the build file of a product it does not find: the project GUID and the
    /// MD5 of the product's path in the project's legacy build folder (envelope-experiments
    /// `unresolved-proxies`).
    static func unresolvedGUID(_ workspace: XcodeWorkspace, _ product: String) -> String {
        MD5.hex("P.xcodeproj") + MD5.hex(workspace.projects[0].projectDirectory + "/build/Debug-iphoneos/" + product)
    }

    /// `project-references-missing`: a referenced project that is not on disk is left out; a
    /// dependency on its target has a name only, a product linked from it its type and name.
    @Test func aMissingReferencedProjectIsLeftOut() throws {
        let directory = try TemporaryDirectory()
        let fixture = ReferencedProjects(projects: [
            "P.xcodeproj": .init(prefix: "A", targets: [.init(name: "App", type: "application", dependencies: [("Sub/Sub.xcodeproj", "Lib"), ("Gone/Gone.xcodeproj", "GoneLib")],
                                                              links: [("Gone/Gone.xcodeproj", "GoneLib")])],
                                 references: ["Gone/Gone.xcodeproj", "Sub/Sub.xcodeproj"]),
            "Gone/Gone.xcodeproj": .init(prefix: "E", targets: [.init(name: "GoneLib")]),
            "Sub/Sub.xcodeproj": .init(prefix: "B", targets: [.init(name: "Lib")]),
        ], missing: ["Gone/Gone.xcodeproj"])
        try fixture.write(at: directory.path)
        let workspace = try XcodeWorkspace.load(path: directory.path + "/P.xcodeproj")
        var generator = PIFGenerator(workspace: workspace)
        let document = try generator.generate()
        #expect(document.objects.filter { $0.type == "project" }.compactMap { $0.contents.objectValue?["guid"] } == [.string(MD5.hex("P.xcodeproj")), .string(MD5.hex("Sub/Sub.xcodeproj"))])
        let app = try Self.target(document, "App")
        #expect(app["dependencies"] == .array([
            .object(["guid": .string(fixture.targetGUID("Sub/Sub.xcodeproj", "Lib")), "name": .string("Lib (from Sub.xcodeproj)")]),
            .object(["name": .string("GoneLib (from Gone.xcodeproj)")]),
        ]))
        let linked = try #require(app["buildPhases"]?.arrayValue?.first?.objectValue?["buildFiles"]?.arrayValue?.first?.objectValue)
        let guid = Self.unresolvedGUID(workspace, "libGoneLib.a")
        #expect(linked == ["fileType": .string("archive.ar"), "guid": .string(guid), "name": .string("libGoneLib.a")])
        #expect(generator.hashedBuildFilePaths == [guid: workspace.projects[0].projectDirectory + "/build/Debug-iphoneos/libGoneLib.a"])
    }

    /// `project-references-renamed` (delta's Harmony): a remote ID the referenced project no longer
    /// has resolves by the proxy's `remoteInfo`, for the dependency and the linked product.
    @Test func staleRemoteIDsResolveByTheTargetsName() throws {
        let directory = try TemporaryDirectory()
        let sub = "Sub/Sub.xcodeproj"
        var fixture = ReferencedProjects(projects: [
            "P.xcodeproj": .init(prefix: "A", targets: [.init(name: "App", type: "application", dependencies: [(sub, "Lib")], links: [(sub, "Lib")])],
                                 references: [sub]),
            sub: .init(prefix: "B", targets: [.init(name: "Lib")]),
        ])
        try fixture.write(at: directory.path)
        fixture.projects[sub]?.prefix = "C"
        try FileSystem.write(Data(fixture.pbxproj(sub).utf8), to: directory.path + "/" + sub + "/project.pbxproj")
        var generator = PIFGenerator(workspace: try XcodeWorkspace.load(path: directory.path + "/P.xcodeproj"))
        let app = try Self.target(try generator.generate(), "App")
        let lib = fixture.targetGUID(sub, "Lib")
        #expect(app["dependencies"] == .array([.object(["guid": .string(lib), "name": .string("Lib (from Sub.xcodeproj)")])]))
        #expect(app["buildPhases"]?.arrayValue?.first?.objectValue?["buildFiles"]?.arrayValue?.first?.objectValue?["targetReference"] == .string(lib))
    }

    /// `nomac verify` hashes such a path again under the reference's source root, where Xcode
    /// hashed it; a path outside the source root is the same on both machines.
    @Test func verifyRehashesPathsUnderTheReferenceSource() {
        let local = "/local/src/build/Debug-iphoneos/libGone.a"
        let guid = MD5.hex("P.xcodeproj") + MD5.hex(local)
        let text = #"{ "guid" : "\#(guid)" }"#
        let rehashed = MD5.hex("P.xcodeproj") + MD5.hex("/ci/work/src/build/Debug-iphoneos/libGone.a")
        #expect(ReferenceVerifier.rehashed(text, hashedPaths: [guid: local], sourceRoot: "/local/src", referenceSource: "/ci/work/src") == #"{ "guid" : "\#(rehashed)" }"#)
        #expect(ReferenceVerifier.rehashed(text, hashedPaths: [guid: local], sourceRoot: "/elsewhere", referenceSource: "/ci/work/src") == text)
    }

    /// `project-references-stale`: a target, and its product, that a referenced project on disk
    /// no longer has are written as those of a project that is not on disk.
    @Test func aTargetMissingFromAReferencedProjectIsWrittenAsMissing() throws {
        let directory = try TemporaryDirectory()
        let sub = "Sub/Sub.xcodeproj"
        var fixture = ReferencedProjects(projects: [
            "P.xcodeproj": .init(prefix: "A", targets: [.init(name: "App", type: "application", dependencies: [(sub, "Lib"), (sub, "Gone")], links: [(sub, "Lib"), (sub, "Gone")])],
                                 references: [sub]),
            sub: .init(prefix: "B", targets: [.init(name: "Lib"), .init(name: "Gone")]),
        ])
        try fixture.write(at: directory.path)
        fixture.projects[sub]?.targets.removeLast()
        try FileSystem.write(Data(fixture.pbxproj(sub).utf8), to: directory.path + "/" + sub + "/project.pbxproj")
        let workspace = try XcodeWorkspace.load(path: directory.path + "/P.xcodeproj")
        var generator = PIFGenerator(workspace: workspace)
        let app = try Self.target(try generator.generate(), "App")
        #expect(app["dependencies"] == .array([
            .object(["guid": .string(fixture.targetGUID(sub, "Lib")), "name": .string("Lib (from Sub.xcodeproj)")]),
            .object(["name": .string("Gone (from Sub.xcodeproj)")]),
        ]))
        let buildFiles = try #require(app["buildPhases"]?.arrayValue?.first?.objectValue?["buildFiles"]?.arrayValue)
        #expect(buildFiles.first?.objectValue?["targetReference"] == .string(fixture.targetGUID(sub, "Lib")))
        let gone = try #require(buildFiles.last?.objectValue)
        #expect(gone == ["fileType": .string("archive.ar"), "guid": .string(Self.unresolvedGUID(workspace, "libGone.a")), "name": .string("libGone.a")])
    }

    /// `project-references`: the targets and shared schemes of referenced projects have schemes,
    /// `-list` names only the opened project's targets, and `-target` and `-alltargets` see only
    /// those (`-target Lib` fails with 65).
    @Test func referencedProjectsHaveSchemes() async throws {
        let directory = try TemporaryDirectory()
        try ReferencedProjects.experiment().write(at: directory.path + "/app")
        let workspace = try XcodeWorkspace.load(path: directory.path + "/app/P.xcodeproj")
        try await SchemeFixtures.withInspector(of: workspace, in: directory.path) { inspector in
            let listing = WorkspaceListing(workspace: workspace, schemes: try await inspector.schemes())
            #expect(listing.schemes == ["AlphaLib", "App", "DeepLib", "Lib", "PShared", "SubShared", "Twin"])
            #expect(listing.targets == ["App", "Twin"])
            let lib = try await inspector.blocks(.init(selection: .scheme("Lib"), destination: "generic/platform=iOS"))
            #expect(lib.map(\.target) == ["Lib"])
            #expect(lib.first?.dictionary["PROJECT_NAME"] == "Sub")
            #expect(try await inspector.blocks(.init(selection: .allTargets)).map(\.target) == ["App", "Twin", "App"])
            await #expect(throws: NomacError("The project '\(workspace.projects[0].path)' does not contain a target named 'Lib'.", exitStatus: 65)) {
                try await inspector.blocks(.init(selection: .targets(["Lib"])))
            }
        }
    }

    /// `project-references-bundles`: a referenced project's unit test bundle and app extension
    /// get schemes, which the autocreation rules decide from their evaluated settings.
    @Test func referencedTestBundlesAndExtensionsHaveSchemes() async throws {
        let directory = try TemporaryDirectory()
        let fixture = ReferencedProjects(projects: [
            "P.xcodeproj": .init(prefix: "A", targets: [.init(name: "App", type: "application", dependencies: [("Sub/Sub.xcodeproj", "Lib")])], references: ["Sub/Sub.xcodeproj"]),
            "Sub/Sub.xcodeproj": .init(prefix: "B", targets: [.init(name: "Lib"), .init(name: "SubTests", type: "bundle.unit-test"),
                                                              .init(name: "SubExtension", type: "app-extension")]),
        ])
        try fixture.write(at: directory.path + "/app")
        let workspace = try XcodeWorkspace.load(path: directory.path + "/app/P.xcodeproj")
        let listing = WorkspaceListing(workspace: workspace, schemes: try await SchemeFixtures.schemes(of: workspace, in: directory.path))
        #expect(listing.schemes == ["App", "Lib", "SubExtension", "SubTests"])
    }

    /// `project-reference-names`, `workspace-names`: targets of different projects that share a
    /// name have one scheme, the first project's, which records the others' as alternatives:
    /// xcodebuild builds one of them from one run to the next.
    @Test(arguments: [false, true])
    func targetsWithOneNameHaveOneScheme(workspace: Bool) throws {
        let directory = try TemporaryDirectory()
        var fixture = ReferencedProjects(projects: [
            "Q.xcodeproj": .init(prefix: "A", targets: [.init(name: "One"), .init(name: "Two")], references: workspace ? [] : ["Z/Z.xcodeproj", "A/A.xcodeproj"]),
            "A/A.xcodeproj": .init(prefix: "B", targets: [.init(name: "One"), .init(name: "Three")]),
            "Z/Z.xcodeproj": .init(prefix: "C", targets: [.init(name: "Two"), .init(name: "Three")]),
        ])
        if workspace {
            let references = ["Z/Z.xcodeproj", "Q.xcodeproj", "A/A.xcodeproj"].map { "<FileRef location = \"group:\($0)\"></FileRef>" }.joined()
            fixture.files["W.xcworkspace/contents.xcworkspacedata"] = #"<?xml version="1.0" encoding="UTF-8"?><Workspace version = "1.0">"# + references + "</Workspace>"
        }
        try fixture.write(at: directory.path)
        let loaded = try XcodeWorkspace.load(path: directory.path + (workspace ? "/W.xcworkspace" : "/Q.xcodeproj"))
        let schemes = try loaded.schemes(userName: "me")
        #expect(WorkspaceListing(workspace: loaded, schemes: schemes).schemes == ["One", "Three", "Two"])
        func containers(_ name: String) -> [String] {
            guard let scheme = schemes.first(where: { $0.name == name }) else { return [] }
            return ([scheme] + scheme.alternatives).compactMap { $0.buildEntries.first.map { ($0.containerPath as NSString).lastPathComponent } }
        }
        #expect(containers("One") == ["Q.xcodeproj", "A.xcodeproj"])
        #expect(containers("Three") == ["Z.xcodeproj", "A.xcodeproj"])
        #expect(containers("Two") == (workspace ? ["Z.xcodeproj", "Q.xcodeproj"] : ["Q.xcodeproj", "Z.xcodeproj"]))
    }

    /// `project-references-packages`: the packages a referenced project uses are the workspace's,
    /// and the products its targets use are linked as in any project.
    @Test func packagesOfReferencedProjectsAreResolved() async throws {
        let directory = try TemporaryDirectory()
        let root = (directory.path as NSString).standardizingPath
        let fixture = ReferencedProjects(projects: [
            "P.xcodeproj": .init(prefix: "A", targets: [.init(name: "App", type: "application", dependencies: [("Sub/Sub.xcodeproj", "Lib")])], references: ["Sub/Sub.xcodeproj"]),
            "Sub/Sub.xcodeproj": .init(prefix: "B", targets: [.init(name: "Lib")]),
        ])
        try fixture.write(at: root)
        let sub = root + "/Sub/Sub.xcodeproj/project.pbxproj"
        let text = try String(contentsOfFile: sub, encoding: .utf8)
            .replacingOccurrences(of: "\tobjects = {\n", with: "\tobjects = {\nBZ0000000000000000000001 = {isa = XCLocalSwiftPackageReference; relativePath = Kit; };\n"
                                  + "BZ0000000000000000000002 = {isa = XCSwiftPackageProductDependency; package = BZ0000000000000000000001; productName = Kit; };\n")
            .replacingOccurrences(of: "projectDirPath = \"\";", with: "packageReferences = (BZ0000000000000000000001, ); projectDirPath = \"\";")
            .replacingOccurrences(of: "name = Lib; productName", with: "name = Lib; packageProductDependencies = (BZ0000000000000000000002, ); productName")
        try FileSystem.write(Data(text.utf8), to: sub)
        let manifest = #"// swift-tools-version: 6.0\#nimport PackageDescription\#nlet package = Package(name: "Kit", products: [.library(name: "Kit", targets: ["Kit"])], targets: [.target(name: "Kit")])\#n"#
        try FileSystem.write(Data(manifest.utf8), to: root + "/Sub/Kit/Package.swift")
        try FileSystem.write(Data("public let kit = 1\n".utf8), to: root + "/Sub/Kit/Sources/Kit/Kit.swift")
        let workspace = try XcodeWorkspace.load(path: root + "/P.xcodeproj")
        #expect(try PackageReferences.find(in: workspace).localDependencies == [root + "/Sub/Kit"])
        var packages = try SwiftPackages(workspace: workspace, sourcePackagesDirectory: root + "/SourcePackages",
                                         developerDirectory: try SyntheticDeveloperDirectory.create(at: root + "/xcode"))
        var generator = PIFGenerator(workspace: workspace, packages: try await packages.load())
        let lib = try Self.target(try generator.generate(), "Lib")
        #expect(lib["dependencies"] == .array([.object(["guid": .string("PACKAGE-PRODUCT:kit_Kit.Kit"), "name": .string("Kit")])]))
        #expect(lib["buildPhases"]?.arrayValue?.first?.objectValue?["buildFiles"] == .array([
            .object(["guid": .string(MD5.hex("BZ0000000000000000000002")), "targetReference": .string("PACKAGE-PRODUCT:kit_Kit.Kit")]),
        ]))
    }
}
