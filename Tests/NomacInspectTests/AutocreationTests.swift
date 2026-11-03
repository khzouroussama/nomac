import Foundation
import Testing
import NomacBuildService
import NomacCore
@testable import NomacProject
import NomacTestSupport
@testable import NomacInspect

/// Projects shaped like loader-experiments' `extension-points`, `product-types`,
/// `autocreate-hosts`, `scheme-coverage`, `test-hosts`, `autocreate-names`, `user-schemes`,
/// `own-test-schemes` and `scheme-destinations`, written again here; what Xcode 27.0 autocreated
/// for them is each test's expectation.
struct AutocreationProject {
    struct Target {
        var name: String
        /// The product type without `com.apple.product-type.`, or `aggregate`.
        var type: String
        /// Settings of every configuration, then of single configurations.
        var settings: [String: String] = [:]
        var configurationSettings: [String: [String: String]] = [:]
        var dependencies: [String] = []
        var testTarget: String?
        /// The paths of the files its Sources phase compiles.
        var sources: [String] = []
    }

    var targets: [Target]
    var configurations = ["Debug", "Release"]
    var defaultConfiguration = "Release"
    /// Shared schemes by name.
    var schemes: [String: String] = [:]
    /// Other files by path.
    var files: [String: String] = [:]
    /// Whether it is opened through `W.xcworkspace`, which lists only it.
    var workspace = false
    /// The project's name.
    var name = "P"
    /// The current user's schemes by name.
    var userSchemes: [String: String] = [:]
    /// The targets the current user's xcschememanagement.plist names in
    /// SuppressBuildableAutocreation, with their `primary` value.
    var suppressed: [String: Bool] = [:]

    static func id(_ prefix: Character, _ index: Int) -> String {
        String(prefix) + String(repeating: "0", count: 23 - String(index).count) + String(index)
    }

    func targetID(_ name: String) -> String {
        Self.id("C", targets.firstIndex { $0.name == name }! + 1)
    }

    private static let products: [String: (String, String)] = [
        "application": ("wrapper.application", "app"), "app-extension": ("wrapper.app-extension", "appex"),
        "framework": ("wrapper.framework", "framework"), "bundle.unit-test": ("wrapper.cfbundle", "xctest"),
        "bundle.ui-testing": ("wrapper.cfbundle", "xctest"), "application.watchapp2-container": ("wrapper.application", "app"),
        "watchkit2-extension": ("wrapper.app-extension", "appex"), "application.messages": ("wrapper.application", "app"),
        "application.watchapp2": ("wrapper.application", "app"),
        "bundle": ("wrapper.cfbundle", "bundle"), "tool": ("compiled.mach-o.executable", ""),
    ]

    private func configurationList(_ id: String, index: Int, settings: (String) -> [String: String]) -> String {
        var text = "\t\t\(id) = {isa = XCConfigurationList; buildConfigurations = ("
        text += configurations.indices.map { "\(Self.id("G", index * 10 + $0)), " }.joined()
        text += "); defaultConfigurationName = \(defaultConfiguration); };\n"
        for (position, name) in configurations.enumerated() {
            let body = settings(name).sorted { $0.key < $1.key }.map { "\($0.key) = \"\($0.value)\"; " }.joined()
            text += "\t\t\(Self.id("G", index * 10 + position)) = {isa = XCBuildConfiguration; buildSettings = {\(body)}; name = \(name); };\n"
        }
        return text
    }

    var pbxproj: String {
        var objects = configurationList("F000000000000000000000PL", index: 0) { _ in ["SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "18.0"] }
        var attributes = ""
        var dependencyCount = 0
        for (offset, target) in targets.enumerated() {
            let index = offset + 1
            if let (fileType, extensionName) = Self.products[target.type] {
                let path = extensionName.isEmpty ? target.name : "\(target.name).\(extensionName)"
                objects += "\t\t\(Self.id("P", index)) = {isa = PBXFileReference; explicitFileType = \(fileType); path = \"\(path)\"; sourceTree = BUILT_PRODUCTS_DIR; };\n"
            }
            var dependencies = ""
            for dependency in target.dependencies {
                dependencyCount += 1
                let proxy = Self.id("X", dependencyCount), link = Self.id("T", dependencyCount)
                objects += "\t\t\(proxy) = {isa = PBXContainerItemProxy; containerPortal = F00000000000000000000006; proxyType = 1; remoteGlobalIDString = \(targetID(dependency)); remoteInfo = \(dependency); };\n"
                objects += "\t\t\(link) = {isa = PBXTargetDependency; target = \(targetID(dependency)); targetProxy = \(proxy); };\n"
                dependencies += "\(link), "
            }
            objects += configurationList(Self.id("L", index), index: index) { configuration in
                ["PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "org.nomac.target\(index)", "GENERATE_INFOPLIST_FILE": "YES"]
                    .merging(target.settings) { $1 }.merging(target.configurationSettings[configuration] ?? [:]) { $1 }
            }
            var phases = ""
            if !target.sources.isEmpty {
                let files = target.sources.indices.map { "\(Self.id("E", index * 10 + $0)), " }.joined()
                for (position, source) in target.sources.enumerated() {
                    objects += "\t\t\(Self.id("R", index * 10 + position)) = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \"\(source)\"; sourceTree = \"<group>\"; };\n"
                    objects += "\t\t\(Self.id("E", index * 10 + position)) = {isa = PBXBuildFile; fileRef = \(Self.id("R", index * 10 + position)); };\n"
                }
                objects += "\t\t\(Self.id("B", index)) = {isa = PBXSourcesBuildPhase; files = (\(files)); };\n"
                phases = "\(Self.id("B", index)), "
            }
            if target.type == "aggregate" {
                objects += "\t\t\(Self.id("C", index)) = {isa = PBXAggregateTarget; buildConfigurationList = \(Self.id("L", index)); buildPhases = (); dependencies = (\(dependencies)); name = \"\(target.name)\"; productName = \"\(target.name)\"; };\n"
            } else {
                objects += "\t\t\(Self.id("C", index)) = {isa = PBXNativeTarget; buildConfigurationList = \(Self.id("L", index)); buildPhases = (\(phases)); dependencies = (\(dependencies)); name = \"\(target.name)\"; productName = \"\(target.name)\"; productReference = \(Self.id("P", index)); productType = \"com.apple.product-type.\(target.type)\"; };\n"
            }
            if let tested = target.testTarget {
                attributes += "\(Self.id("C", index)) = {TestTargetID = \(targetID(tested)); }; "
            }
        }
        let products = targets.indices.filter { targets[$0].type != "aggregate" }.map { "\(Self.id("P", $0 + 1)), " }.joined()
        let sources = targets.indices.flatMap { index in targets[index].sources.indices.map { "\(Self.id("R", (index + 1) * 10 + $0)), " } }.joined()
        let ids = targets.indices.map { "\(Self.id("C", $0 + 1)), " }.joined()
        objects += "\t\tF00000000000000000000002 = {isa = PBXGroup; children = (\(sources)\(products)); sourceTree = \"<group>\"; };\n"
        objects += "\t\tF00000000000000000000006 = {isa = PBXProject; attributes = {TargetAttributes = {\(attributes)}; }; buildConfigurationList = F000000000000000000000PL; mainGroup = F00000000000000000000002; projectDirPath = \"\"; projectRoot = \"\"; targets = (\(ids)); };\n"
        return "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tobjectVersion = 77;\n\tobjects = {\n\(objects)\t};\n\trootObject = F00000000000000000000006;\n}\n"
    }

    /// A scheme: `build` holds (target, built for running), where a name ending in `.xctestplan`
    /// is an entry that builds that test plan and `autocreated` one that holds an
    /// `AutocreatedTestPlanReference`; `launch` and `profile` name
    /// buildable product runnables, `remote` a remote launch runnable's macro expansion;
    /// `testables` the bundles it tests, or skips with `skipped`; `coverage` sets
    /// codeCoverageEnabled and `plans` holds (test plan path, default).
    func scheme(build: [(String, Bool)] = [], launch: String? = nil, profile: String? = nil, remote: String? = nil, testables: [String] = [],
                skipped: Bool = false, coverage: Bool = false, plans: [(String, Bool)] = []) -> String {
        func reference(_ name: String) -> String {
            "<BuildableReference BuildableIdentifier = \"primary\" BlueprintIdentifier = \"\(targetID(name))\" BuildableName = \"\(name).app\" BlueprintName = \"\(name)\" ReferencedContainer = \"container:\(self.name).xcodeproj\"></BuildableReference>\n"
        }
        func runnable(_ name: String?) -> String {
            name.map { "<BuildableProductRunnable runnableDebuggingMode = \"0\">\n" + reference($0) + "</BuildableProductRunnable>\n" } ?? ""
        }
        let entries = build.map { name, running in
            let built = name == "autocreated" ? "<AutocreatedTestPlanReference></AutocreatedTestPlanReference>\n"
                : name.hasSuffix(".xctestplan") ? "<TestPlanReference reference = \"container:\(name)\"></TestPlanReference>\n" : reference(name)
            return "<BuildActionEntry buildForTesting = \"YES\" buildForRunning = \"\(running ? "YES" : "NO")\" buildForProfiling = \"\(running ? "YES" : "NO")\" buildForArchiving = \"\(running ? "YES" : "NO")\" buildForAnalyzing = \"YES\">\n"
                + built + "</BuildActionEntry>\n"
        }.joined()
        let remoteRunnable = remote.map {
            "<RemoteRunnable runnableDebuggingMode = \"1\" BundleIdentifier = \"org.nomac\" RemotePath = \"/App.app\"></RemoteRunnable>\n<MacroExpansion>\n" + reference($0) + "</MacroExpansion>\n"
        } ?? ""
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <Scheme LastUpgradeVersion = "2700" version = "1.7">
        <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
        <BuildActionEntries>
        \(entries)</BuildActionEntries>
        </BuildAction>
        <TestAction buildConfiguration = "Debug"\(coverage ? " codeCoverageEnabled = \"YES\"" : "")>
        <TestPlans>
        \(plans.map { "<TestPlanReference reference = \"container:\($0.0)\"\($0.1 ? " default = \"YES\"" : "")></TestPlanReference>\n" }.joined())</TestPlans>
        <Testables>
        \(testables.map { "<TestableReference skipped = \"\(skipped ? "YES" : "NO")\">\n" + reference($0) + "</TestableReference>\n" }.joined())</Testables>
        </TestAction>
        <LaunchAction buildConfiguration = "Debug" launchStyle = "0">
        \(runnable(launch))\(remoteRunnable)</LaunchAction>
        <ProfileAction buildConfiguration = "Release">
        \(runnable(profile))</ProfileAction>
        </Scheme>

        """
    }

    /// The folder of the current user's schemes in the project.
    var userFolder: String { "\(name).xcodeproj/xcuserdata/\(HostIdentity.current().userName).xcuserdatad/xcschemes" }

    /// Writes the project, its schemes and its files into the folder `root`.
    func write(in root: String) throws {
        var all = files
        all["\(name).xcodeproj/project.pbxproj"] = pbxproj
        for (scheme, text) in schemes {
            all["\(name).xcodeproj/xcshareddata/xcschemes/\(scheme).xcscheme"] = text
        }
        for (scheme, text) in userSchemes {
            all["\(userFolder)/\(scheme).xcscheme"] = text
        }
        if !suppressed.isEmpty {
            let entries = suppressed.map { "<key>\(targetID($0.key))</key><dict><key>primary</key><\($0.value)/></dict>" }.joined()
            all["\(userFolder)/xcschememanagement.plist"] = #"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>SuppressBuildableAutocreation</key><dict>"#
                + entries + "</dict></dict></plist>\n"
        }
        if workspace {
            all["W.xcworkspace/contents.xcworkspacedata"] = #"<?xml version="1.0" encoding="UTF-8"?><Workspace version = "1.0"><FileRef location = "group:\#(name).xcodeproj"></FileRef></Workspace>"#
        }
        for (path, text) in all {
            let full = root + "/" + path
            try FileManager.default.createDirectory(atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try text.write(toFile: full, atomically: true, encoding: .utf8)
        }
    }

    /// Writes the project under `directory` and runs `body` with an inspector of it.
    func withInspector<T>(in directory: String, _ body: (BuildSettingsInspector) async throws -> T) async throws -> T {
        try write(in: directory + "/app")
        return try await SchemeFixtures.withInspector(of: try XcodeWorkspace.load(path: directory + (workspace ? "/app/W.xcworkspace" : "/app/\(name).xcodeproj")), in: directory, body)
    }

    func schemes(in directory: String) async throws -> [XcodeScheme] {
        try await withInspector(in: directory) { try await $0.schemes() }
    }

    /// A test plan whose default options are `options` (JSON), with a configuration whose id is
    /// `configurationID`.
    static func testPlan(options: String, configurationID: String = "A11977F5-134B-4CB5-B798-B2F3F30138CD", testTargets: String = "") -> String {
        #"{"configurations": [{"id": "\#(configurationID)", "name": "Configuration 1", "options": {}}], "defaultOptions": \#(options), "testTargets": [\#(testTargets)], "version": 1}"#
    }

    /// A test plan that tests `names`, in that order.
    func testPlan(testing names: [String]) -> String {
        Self.testPlan(options: "{}", testTargets: names.map {
            #"{"target": {"containerPath": "container:P.xcodeproj", "identifier": "\#(targetID($0))", "name": "\#($0)"}}"#
        }.joined(separator: ", "))
    }

    static func workspaceSettings(autocreate: Bool) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded</key><\(autocreate)/></dict></plist>

        """
    }

    static func infoPlist(point: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>NSExtension</key><dict><key>NSExtensionPointIdentifier</key><string>\(point)</string></dict></dict></plist>

        """
    }
}

@Suite struct AutocreationTests {
    static let plists = ["Safari.plist": AutocreationProject.infoPlist(point: "com.apple.Safari.extension"),
                         "Web.plist": AutocreationProject.infoPlist(point: "com.apple.Safari.web-extension"),
                         "Share.plist": AutocreationProject.infoPlist(point: "com.apple.share-services")]

    /// `extension-points`: the Info.plist is read in Debug, through the evaluated INFOPLIST_FILE;
    /// only app extensions with a Safari extension point lose their scheme.
    @Test func safariExtensionsGetNoScheme() async throws {
        let directory = try TemporaryDirectory()
        let project = AutocreationProject(targets: [
            .init(name: "App", type: "application"),
            .init(name: "DebugSafari", type: "app-extension", configurationSettings: ["Debug": ["INFOPLIST_FILE": "Safari.plist"], "Release": ["INFOPLIST_FILE": "Share.plist"]]),
            .init(name: "ReleaseSafari", type: "app-extension", configurationSettings: ["Debug": ["INFOPLIST_FILE": "Share.plist"], "Release": ["INFOPLIST_FILE": "Safari.plist"]]),
            .init(name: "MacroWeb", type: "app-extension", settings: ["INFOPLIST_FILE": "$(NOMAC_PLIST).plist", "NOMAC_PLIST": "Web"]),
            .init(name: "Share", type: "app-extension", settings: ["INFOPLIST_FILE": "Share.plist"]),
            .init(name: "AppSafari", type: "application", settings: ["INFOPLIST_FILE": "Safari.plist"]),
        ], files: Self.plists)
        #expect(try await project.schemes(in: directory.path).map(\.name) == ["App", "ReleaseSafari", "Share", "AppSafari"])
    }

    static var settingsProject: AutocreationProject {
        var project = AutocreationProject(targets: [.init(name: "App", type: "application"), .init(name: "Hosted", type: "application"),
                                                    .init(name: "Kit", type: "framework")])
        project.schemes = ["Hosted": project.scheme(build: [("Hosted", true)], launch: "Hosted")]
        return project
    }

    /// `autocreate-contexts-user-off`, `-shared-off-user-on`, `-off-user`: the project workspace's
    /// shared settings turn autocreation off and leave the shared and per-user schemes
    /// (kickstarter); the current user's own copy is not read, to turn it off or back on.
    @Test func sharedWorkspaceSettingsTurnAutocreationOff() async throws {
        var project = Self.settingsProject
        let user = "P.xcodeproj/project.xcworkspace/xcuserdata/\(NSUserName()).xcuserdatad/WorkspaceSettings.xcsettings"
        project.files = [user: AutocreationProject.workspaceSettings(autocreate: false)]
        let userOff = try TemporaryDirectory()
        #expect(try await project.schemes(in: userOff.path).map(\.name) == ["Hosted", "App", "Kit"])
        project.files = [user: AutocreationProject.workspaceSettings(autocreate: true),
                         "P.xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings": AutocreationProject.workspaceSettings(autocreate: false)]
        let sharedOff = try TemporaryDirectory()
        #expect(try await project.schemes(in: sharedOff.path).map(\.name) == ["Hosted"])
        project.userSchemes = ["MineKit": project.scheme(build: [("Kit", true)])]
        let userScheme = try TemporaryDirectory()
        #expect(try await project.schemes(in: userScheme.path).map(\.name) == ["Hosted", "MineKit"])
    }

    /// `autocreate-contexts-workspace-off`, `-workspace-project-off`: through an `.xcworkspace`,
    /// its own shared settings decide, and the project's `project.xcworkspace` is not read.
    @Test func anOpenedWorkspaceDecidesAutocreation() async throws {
        var project = Self.settingsProject
        project.workspace = true
        project.files = ["P.xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings": AutocreationProject.workspaceSettings(autocreate: false)]
        let projectOff = try TemporaryDirectory()
        #expect(try await project.schemes(in: projectOff.path).map(\.name) == ["Hosted", "App", "Kit"])
        project.files = ["W.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings": AutocreationProject.workspaceSettings(autocreate: false)]
        let workspaceOff = try TemporaryDirectory()
        #expect(try await project.schemes(in: workspaceOff.path).map(\.name) == ["Hosted"])
    }

    /// `product-types`: watch app containers, WatchKit 2 extensions and iMessage apps get none.
    @Test func someProductTypesGetNoScheme() async throws {
        let directory = try TemporaryDirectory()
        let project = AutocreationProject(targets: [
            .init(name: "Container", type: "application.watchapp2-container"), .init(name: "WatchExtension", type: "watchkit2-extension"),
            .init(name: "Messages", type: "application.messages"), .init(name: "Kit", type: "framework"),
        ])
        #expect(try await project.schemes(in: directory.path).map(\.name) == ["Kit"])
    }

    /// `autocreate-hosts`: an extension's scheme builds the apps that depend on it directly or
    /// through one other target, each followed by that target.
    @Test func extensionSchemesBuildTheirApps() async throws {
        let directory = try TemporaryDirectory()
        let project = AutocreationProject(targets: [
            .init(name: "Lone", type: "app-extension"),
            .init(name: "Direct", type: "app-extension"),
            .init(name: "HostA", type: "application", dependencies: ["Direct"]),
            .init(name: "Inner", type: "app-extension"),
            .init(name: "Outer", type: "app-extension", dependencies: ["Inner"]),
            .init(name: "HostB", type: "application", dependencies: ["Outer"]),
            .init(name: "ViaFramework", type: "app-extension"),
            .init(name: "Middle", type: "framework", dependencies: ["ViaFramework"]),
            .init(name: "User", type: "application", dependencies: ["Middle"]),
            .init(name: "Far", type: "app-extension"),
            .init(name: "Link1", type: "app-extension", dependencies: ["Far"]),
            .init(name: "Link2", type: "app-extension", dependencies: ["Link1"]),
            .init(name: "FarApp", type: "application", dependencies: ["Link2"]),
            .init(name: "Library", type: "framework"),
            .init(name: "LibraryUser", type: "application", dependencies: ["Library"]),
        ])
        let schemes = try await project.schemes(in: directory.path)
        func entries(_ name: String) -> [String] { schemes.first { $0.name == name }?.buildEntries.map(\.targetName) ?? [] }
        #expect(entries("Lone") == ["Lone"])
        #expect(entries("Direct") == ["Direct", "HostA"])
        #expect(entries("Inner") == ["Inner", "HostB", "Outer"])
        #expect(entries("ViaFramework") == ["ViaFramework", "User", "Middle"])
        #expect(entries("Far") == ["Far"])
        #expect(entries("Library") == ["Library"])
        #expect(schemes.allSatisfy { $0.unorderedTargetNames.isEmpty })
    }

    /// `autocreate-hosts` (ManyHosts, Mixed: six runs each; vlc): xcodebuild prints the blocks of an
    /// extension scheme's apps, when there are several, in an order that changes from one run to
    /// the next.
    @Test func severalHostsAreUnordered() async throws {
        let directory = try TemporaryDirectory()
        let project = AutocreationProject(targets: [
            .init(name: "Shared", type: "app-extension"),
            .init(name: "Middle", type: "app-extension", dependencies: ["Shared"]),
            .init(name: "Beta", type: "application", dependencies: ["Middle"]),
            .init(name: "Alpha", type: "application", dependencies: ["Shared"]),
        ])
        let schemes = try await project.schemes(in: directory.path)
        let shared = try #require(schemes.first { $0.name == "Shared" })
        #expect(shared.buildEntries.map(\.targetName) == ["Shared", "Beta", "Middle", "Alpha"])
        #expect(shared.unorderedTargetNames == ["Beta", "Middle", "Alpha"])
    }

    /// `scheme-coverage`: a shared scheme covers an app only by launching or profiling it, and
    /// builds what it launches, in its entry's place or after the entries.
    @Test func sharedSchemesCoverAppsTheyRun() async throws {
        let directory = try TemporaryDirectory()
        var project = AutocreationProject(targets: [
            .init(name: "Built", type: "application"), .init(name: "Launched", type: "application"), .init(name: "Profiled", type: "application"),
            .init(name: "Remote", type: "application"), .init(name: "Kit", type: "framework"), .init(name: "Extension", type: "app-extension"),
            .init(name: "Other", type: "application"), .init(name: "TestingOnly", type: "application"),
        ])
        project.schemes = [
            "S1": project.scheme(build: [("Built", true)]),
            "S2": project.scheme(launch: "Launched"),
            "S3": project.scheme(profile: "Profiled"),
            "S4": project.scheme(build: [("Remote", true), ("Kit", true), ("Extension", true)], remote: "Remote"),
            "S5": project.scheme(build: [("Kit", true)], launch: "Other"),
            "S6": project.scheme(build: [("TestingOnly", false), ("Kit", true)], launch: "TestingOnly"),
        ]
        let (names, launched, afterEntries, inPlace, profiledStatus) = try await project.withInspector(in: directory.path) { inspector in
            func blocks(_ scheme: String) async throws -> [String] {
                try await inspector.blocks(.init(selection: .scheme(scheme), destination: "generic/platform=iOS")).map(\.target)
            }
            var profiledStatus: Int32?
            do {
                _ = try await inspector.blocks(.init(selection: .scheme("S3"), destination: "generic/platform=iOS"))
            } catch {
                profiledStatus = (error as? NomacError)?.exitStatus
            }
            return (try await inspector.schemes().map(\.name), try await blocks("S2"), try await blocks("S5"), try await blocks("S6"), profiledStatus)
        }
        #expect(names == ["S1", "S2", "S3", "S4", "S5", "S6", "Built"])
        #expect(launched == ["Launched"])
        #expect(afterEntries == ["Kit", "Other"])
        #expect(inPlace == ["TestingOnly", "Kit"])
        #expect(profiledStatus == 64)
    }

    /// `test-bundles`, `test-hosts`: which bundles an app's autocreated scheme tests, and which
    /// get a scheme of their own.
    @Test func testBundleSchemes() async throws {
        let directory = try TemporaryDirectory()
        let host = ["TEST_HOST": "$(BUILT_PRODUCTS_DIR)/App.app/App", "BUNDLE_LOADER": "$(TEST_HOST)"]
        let project = AutocreationProject(targets: [
            .init(name: "App", type: "application"),
            .init(name: "Hosted", type: "bundle.unit-test", settings: host, dependencies: ["App"], testTarget: "App"),
            .init(name: "HostedWithoutTarget", type: "bundle.unit-test", settings: host, dependencies: ["App"]),
            .init(name: "HostWithoutLoader", type: "bundle.unit-test", settings: ["TEST_HOST": "$(BUILT_PRODUCTS_DIR)/App.app/App"], dependencies: ["App"]),
            .init(name: "Unhosted", type: "bundle.unit-test", dependencies: ["App"], testTarget: "App"),
            .init(name: "UI", type: "bundle.ui-testing", dependencies: ["App"], testTarget: "App"),
            .init(name: "TargetOnly", type: "bundle.unit-test", testTarget: "App"),
            .init(name: "Loose", type: "bundle.ui-testing"),
            .init(name: "LooseHostedInRelease", type: "bundle.unit-test", configurationSettings: ["Release": host]),
            .init(name: "LooseHostedInDebug", type: "bundle.unit-test", configurationSettings: ["Debug": host]),
        ])
        let schemes = try await project.schemes(in: directory.path)
        #expect(schemes.map(\.name) == ["App", "TargetOnly", "Loose", "LooseHostedInDebug"])
        #expect(schemes[0].testables.map(\.targetName) == ["Hosted", "HostedWithoutTarget", "UI"])
        #expect(schemes[1].buildEntries.isEmpty && schemes[1].testables.map(\.targetName) == ["TargetOnly"])
    }

    /// `coverage`: without test plans the scheme's codeCoverageEnabled decides, with them the
    /// default plan (or the first): on unless it sets codeCoverage to false or cannot be read.
    @Test func codeCoverageComesFromTheTestPlan() async throws {
        let directory = try TemporaryDirectory()
        var project = AutocreationProject(targets: [.init(name: "App", type: "application")], files: [
            "On.xctestplan": AutocreationProject.testPlan(options: #"{"codeCoverage": true}"#),
            "Off.xctestplan": AutocreationProject.testPlan(options: #"{"codeCoverage": false}"#),
            "Unset.xctestplan": AutocreationProject.testPlan(options: "{}"),
            "Targets.xctestplan": AutocreationProject.testPlan(options: #"{"codeCoverage": {"targets": []}}"#),
            "NotUUID.xctestplan": AutocreationProject.testPlan(options: #"{"codeCoverage": true}"#, configurationID: "C1"),
        ])
        let cases: [(String, Bool, [(String, Bool)], Bool)] = [
            ("SchemeOn", true, [], true), ("SchemeOff", false, [], false),
            ("PlanOnSchemeOff", false, [("On.xctestplan", true)], true), ("PlanOffSchemeOn", true, [("Off.xctestplan", true)], false),
            ("PlanUnset", false, [("Unset.xctestplan", true)], true), ("PlanTargets", false, [("Targets.xctestplan", true)], true),
            ("FirstPlan", true, [("Off.xctestplan", false), ("On.xctestplan", false)], false),
            ("DefaultPlan", false, [("Off.xctestplan", false), ("On.xctestplan", true)], true),
            ("MissingPlan", true, [("Missing.xctestplan", true)], false), ("UnreadablePlan", true, [("NotUUID.xctestplan", true)], false),
        ]
        for (name, coverage, plans, _) in cases {
            project.schemes[name] = project.scheme(launch: "App", coverage: coverage, plans: plans)
        }
        let schemes = try await project.schemes(in: directory.path)
        for (name, _, _, expected) in cases {
            #expect(schemes.first { $0.name == name }?.codeCoverageEnabled == expected, "\(name)")
        }
    }

    /// `test-plan-entries` (wikipedia's WikipediaUITests): an entry that builds a test plan
    /// stands for the plan's bundles, in its place, built for what the entry is; they count as
    /// built, so they get no scheme of their own; a target is reported once, where it is first
    /// built for running.
    @Test func entriesThatBuildTestPlans() async throws {
        let directory = try TemporaryDirectory()
        let loose = ["Loose01", "Loose02", "Loose03", "Loose04", "Loose05", "Loose11", "Loose12", "Loose14", "Loose16", "Loose18"]
        var project = AutocreationProject(targets: [.init(name: "App", type: "application")] + loose.map { .init(name: $0, type: "bundle.unit-test") })
        for (plan, names) in [("P01", ["Loose01"]), ("P02", ["Loose02"]), ("P03", ["Loose03"]), ("P04", ["Loose04"]), ("P05", ["Loose05"]),
                              ("P11", ["Loose12", "Loose11"]), ("P16", ["Loose16"])] {
            project.files[plan + ".xctestplan"] = project.testPlan(testing: names)
        }
        project.schemes = [
            "S01": project.scheme(build: [("App", true), ("P01.xctestplan", false)], launch: "App"),
            "S02": project.scheme(build: [("App", true), ("P02.xctestplan", true)], launch: "App"),
            "S03": project.scheme(build: [("P03.xctestplan", true)]),
            "S04": project.scheme(build: [("P04.xctestplan", false)]),
            "S05": project.scheme(build: [("P05.xctestplan", true), ("App", true)], launch: "App"),
            "S06": project.scheme(build: [("App", true), ("Missing.xctestplan", true)], launch: "App"),
            "S11": project.scheme(build: [("App", true), ("P11.xctestplan", true)], launch: "App"),
            "S14": project.scheme(build: [("P16.xctestplan", false), ("App", true), ("Loose16", true)], launch: "App"),
            "S16": project.scheme(build: [("Loose18", true), ("App", true), ("Loose18", true)], launch: "App"),
        ]
        let (names, blocks, planOnlyStatus) = try await project.withInspector(in: directory.path) { inspector in
            var blocks: [String: [String]] = [:]
            for scheme in ["S01", "S02", "S03", "S05", "S06", "S11", "S14", "S16"] {
                blocks[scheme] = try await inspector.blocks(.init(selection: .scheme(scheme), destination: "generic/platform=iOS")).map(\.target)
            }
            var status: Int32?
            do {
                _ = try await inspector.blocks(.init(selection: .scheme("S04"), destination: "generic/platform=iOS"))
            } catch {
                status = (error as? NomacError)?.exitStatus
            }
            return (try await inspector.schemes().map(\.name), blocks, status)
        }
        #expect(names == ["S01", "S02", "S03", "S04", "S05", "S06", "S11", "S14", "S16", "Loose14"])
        #expect(blocks["S01"] == ["App"])
        #expect(blocks["S02"] == ["App", "Loose02"])
        #expect(blocks["S03"] == ["Loose03"])
        #expect(blocks["S05"] == ["Loose05", "App"])
        #expect(blocks["S06"] == ["App"])
        #expect(blocks["S11"] == ["App", "Loose12", "Loose11"])
        #expect(blocks["S14"] == ["App", "Loose16"])
        #expect(blocks["S16"] == ["Loose18", "App"])
        #expect(planOnlyStatus == 64)
    }

    /// envelope-experiments `autocreated-test-plan`, `autocreated-test-plan-running`: an entry
    /// that holds an `AutocreatedTestPlanReference` builds nothing, whatever it is built for.
    @Test func entriesOfAutocreatedTestPlansBuildNothing() async throws {
        let directory = try TemporaryDirectory()
        var project = AutocreationProject(targets: [.init(name: "App", type: "application"), .init(name: "AppTests", type: "bundle.unit-test")])
        project.schemes = [
            "Testing": project.scheme(build: [("App", true), ("autocreated", false)], launch: "App", testables: ["AppTests"]),
            "Running": project.scheme(build: [("App", true), ("autocreated", true)], launch: "App", testables: ["AppTests"]),
        ]
        let blocks = try await project.withInspector(in: directory.path) { inspector in
            var blocks: [[String]] = []
            for scheme in ["Testing", "Running"] {
                blocks.append(try await inspector.blocks(.init(selection: .scheme(scheme), destination: "generic/platform=iOS")).map(\.target))
            }
            return blocks
        }
        #expect(blocks == [["App"], ["App"]])
    }

    /// loader-experiments `watch-schemes` (octopod): a watch app's autocreated scheme comes with
    /// `(Complication)` when its extension's Info.plist names a complication principal class, and
    /// `(Notification)` when the extension compiles `NotificationController.swift`.
    @Test func watchAppsGetComplicationAndNotificationSchemes() async throws {
        let directory = try TemporaryDirectory()
        let plist = { (complication: Bool) in
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict>"
                + (complication ? "<key>CLKComplicationPrincipalClass</key><string>Complications</string>" : "") + "</dict></plist>\n"
        }
        let watch = ["SDKROOT": "watchos", "GENERATE_INFOPLIST_FILE": "NO"]
        let project = AutocreationProject(targets: [
            .init(name: "WatchExt", type: "watchkit2-extension", settings: watch.merging(["INFOPLIST_FILE": "Ext.plist"]) { $1 },
                  sources: ["NotificationController.swift"]),
            .init(name: "Watch", type: "application.watchapp2", settings: ["SDKROOT": "watchos"], dependencies: ["WatchExt"]),
            .init(name: "PlainExt", type: "watchkit2-extension", settings: watch.merging(["INFOPLIST_FILE": "Plain.plist"]) { $1 },
                  sources: ["Sub/NotificationController.swift"]),
            .init(name: "Plain", type: "application.watchapp2", settings: ["SDKROOT": "watchos"], dependencies: ["PlainExt"]),
        ], files: ["Ext.plist": plist(true), "Plain.plist": plist(false)])
        let schemes = try await project.schemes(in: directory.path)
        #expect(schemes.map(\.name).sorted() == ["Plain", "Watch", "Watch (Complication)", "Watch (Notification)"])
        #expect(schemes.first { $0.name == "Watch (Notification)" }?.buildEntries == schemes.first { $0.name == "Watch" }?.buildEntries)
    }

    /// loader-experiments `watch-schemes-missing` (fuzzer seed 70155): a storyboard missing from
    /// disk, in any target, gives every watch app `(Glance)` and `(Notification)`, after
    /// `(Complication)` (`-complication`); an empty storyboard (`-empty`) or a missing xib
    /// (`-xib`) gives neither.
    @Test(arguments: [("Missing.storyboard", nil, true), ("Empty.storyboard", "", false), ("Missing.xib", nil, false)] as [(String, String?, Bool)])
    func missingStoryboardsGiveWatchAppsGlanceAndNotificationSchemes(interface: String, content: String?, listed: Bool) async throws {
        let directory = try TemporaryDirectory()
        let complication = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict>"
            + "<key>CLKComplicationPrincipalClass</key><string>Complications</string></dict></plist>\n"
        let project = AutocreationProject(targets: [
            .init(name: "App", type: "application", sources: [interface]),
            .init(name: "WatchExt", type: "watchkit2-extension", settings: ["SDKROOT": "watchos", "GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": "Ext.plist"]),
            .init(name: "Watch", type: "application.watchapp2", settings: ["SDKROOT": "watchos"], dependencies: ["WatchExt"]),
        ], files: ["Ext.plist": complication].merging(content.map { [interface: $0] } ?? [:]) { $1 })
        let schemes = try await project.schemes(in: directory.path)
        #expect(schemes.map(\.name) == ["App", "Watch", "Watch (Complication)"] + (listed ? ["Watch (Glance)", "Watch (Notification)"] : []))
    }

    /// `symroot-project-*`: a SYMROOT in a base xcconfig counts, one under an SDK
    /// condition does not.
    @Test(arguments: [("SYMROOT = Out\n", true), ("SYMROOT[sdk=iphoneos*] = Out\n", false)])
    func symrootInBaseXCConfig(line: String, assigns: Bool) throws {
        let directory = try TemporaryDirectory()
        try FileSystem.write(Data(line.utf8), to: directory.path + "/Base.xcconfig")
        try FileSystem.write(Data("""
        // !$*UTF8*$!
        {
        \tarchiveVersion = 1;
        \tobjectVersion = 77;
        \tobjects = {
        \t\tA1 = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Base.xcconfig; sourceTree = "<group>"; };
        \t\tA4 = {isa = PBXGroup; children = (A1, ); sourceTree = "<group>"; };
        \t\tA5 = {isa = XCBuildConfiguration; baseConfigurationReference = A1; buildSettings = {}; name = Debug; };
        \t\tA6 = {isa = XCConfigurationList; buildConfigurations = (A5, ); defaultConfigurationName = Debug; };
        \t\tA7 = {isa = PBXProject; buildConfigurationList = A6; mainGroup = A4; projectDirPath = ""; projectRoot = ""; targets = (); };
        \t};
        \trootObject = A7;
        }

        """.utf8), to: directory.path + "/P.xcodeproj/project.pbxproj")
        #expect(try XcodeProject.load(path: directory.path + "/P.xcodeproj").assignsSymroot == assigns)
    }

    /// `watch-schemes-variant` and `-variant-missing` (fuzzer seed 70101): a variant group's
    /// storyboard is looked for under the variant group's own group.
    @Test(arguments: [true, false])
    func storyboardsInVariantGroups(written: Bool) throws {
        let directory = try TemporaryDirectory()
        try FileSystem.write(Data("""
        // !$*UTF8*$!
        {
        	archiveVersion = 1;
        	objectVersion = 77;
        	objects = {
        		A1 = {isa = PBXFileReference; lastKnownFileType = file.storyboard; name = Base; path = Base.lproj/Main.storyboard; sourceTree = "<group>"; };
        		A2 = {isa = PBXVariantGroup; children = (A1, ); name = Main.storyboard; sourceTree = "<group>"; };
        		A3 = {isa = PBXGroup; children = (A2, ); path = Desktop; sourceTree = "<group>"; };
        		A4 = {isa = PBXGroup; children = (A3, ); sourceTree = "<group>"; };
        		A5 = {isa = XCBuildConfiguration; buildSettings = {}; name = Debug; };
        		A6 = {isa = XCConfigurationList; buildConfigurations = (A5, ); defaultConfigurationName = Debug; };
        		A7 = {isa = PBXProject; buildConfigurationList = A6; mainGroup = A4; projectDirPath = ""; projectRoot = ""; targets = (); };
        	};
        	rootObject = A7;
        }

        """.utf8), to: directory.path + "/P.xcodeproj/project.pbxproj")
        if written {
            try FileSystem.write(Data(), to: directory.path + "/Desktop/Base.lproj/Main.storyboard")
        }
        let project = try XcodeProject.load(path: directory.path + "/P.xcodeproj")
        #expect(AutocreationRules.referencesMissingStoryboard(project) == !written)
    }

    /// `autocreate-names`: without Debug, Info.plists are read in the first configuration and
    /// autocreated schemes launch with the default one.
    @Test func configurationsWithoutDebug() async throws {
        let directory = try TemporaryDirectory()
        let project = AutocreationProject(targets: [
            .init(name: "App", type: "application"),
            .init(name: "AlphaSafari", type: "app-extension", configurationSettings: ["Alpha": ["INFOPLIST_FILE": "Safari.plist"], "Beta": ["INFOPLIST_FILE": "Share.plist"]]),
            .init(name: "BetaSafari", type: "app-extension", configurationSettings: ["Alpha": ["INFOPLIST_FILE": "Share.plist"], "Beta": ["INFOPLIST_FILE": "Safari.plist"]]),
        ], configurations: ["Alpha", "Beta"], defaultConfiguration: "Beta", files: Self.plists)
        let schemes = try await project.schemes(in: directory.path)
        #expect(schemes.map(\.name) == ["App", "BetaSafari"])
        #expect(schemes.allSatisfy { $0.launchConfiguration == "Beta" })
        // build_experiments.py `autocreate-names`: App's autocreated scheme archives in Beta too.
        #expect(schemes.allSatisfy { $0.archiveConfiguration == "Beta" })
    }
}
