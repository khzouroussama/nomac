import Foundation
import Testing
import NomacBuildService
import NomacCore
import NomacProject
import NomacTestSupport
@testable import NomacInspect

/// Projects shaped like loader-experiments' `autocreate-testables`, `autocreate-ui-targets`,
/// `autocreate-debug-*` and `scheme-name-clashes`, written again here; what Xcode 27.0 did with
/// them is each test's expectation.
@Suite struct AutocreatedTestablesTests {
    static let host = ["TEST_HOST": "$(BUILT_PRODUCTS_DIR)/{0}.app/{0}", "BUNDLE_LOADER": "$(TEST_HOST)"]

    static func hosted(_ app: String) -> [String: String] {
        host.mapValues { $0.replacingOccurrences(of: "{0}", with: app) }
    }

    func testables(_ schemes: [XcodeScheme], _ name: String) -> [String]? {
        schemes.first { $0.name == name && $0.isAutocreated }?.testables.map(\.targetName)
    }

    /// App01 to App06 and App24: an app's scheme tests no bundle a shared scheme tests, builds,
    /// skips or names in a test plan; it still tests the others, with code coverage.
    @Test func bundlesOtherSchemesCoverAreNotTested() async throws {
        let directory = try TemporaryDirectory()
        var project = AutocreationProject(targets: [
            .init(name: "App01", type: "application"), .init(name: "App01Tests", type: "bundle.ui-testing", dependencies: ["App01"], testTarget: "App01"),
            .init(name: "App02", type: "application"), .init(name: "App02Tests", type: "bundle.ui-testing", dependencies: ["App02"], testTarget: "App02"),
            .init(name: "App03", type: "application"), .init(name: "App03Tests", type: "bundle.ui-testing", dependencies: ["App03"], testTarget: "App03"),
            .init(name: "App04", type: "application"), .init(name: "App04Tests", type: "bundle.ui-testing", dependencies: ["App04"], testTarget: "App04"),
            .init(name: "App05", type: "application"),
            .init(name: "App05Tests", type: "bundle.unit-test", settings: Self.hosted("App05"), dependencies: ["App05"], testTarget: "App05"),
            .init(name: "App06", type: "application"), .init(name: "App06Tests", type: "bundle.ui-testing", dependencies: ["App06"], testTarget: "App06"),
            .init(name: "App06MoreTests", type: "bundle.ui-testing", dependencies: ["App06"], testTarget: "App06"),
            .init(name: "App24", type: "application"), .init(name: "App24Tests", type: "bundle.ui-testing", dependencies: ["App24"], testTarget: "App24"),
        ])
        project.files["Plan24.xctestplan"] = project.testPlan(testing: ["App24Tests"])
        project.schemes = [
            "S01": project.scheme(testables: ["App01Tests"]),
            "S02": project.scheme(build: [("App02Tests", false)]),
            "S03": project.scheme(testables: ["App03Tests"], skipped: true),
            "S05": project.scheme(testables: ["App05Tests"]),
            "S06": project.scheme(testables: ["App06Tests"]),
            "S24": project.scheme(plans: [("Plan24.xctestplan", true)]),
        ]
        let schemes = try await project.schemes(in: directory.path)
        for app in ["App01", "App02", "App03", "App05", "App24"] {
            #expect(testables(schemes, app) == [], "\(app)")
            #expect(schemes.first { $0.name == app }?.codeCoverageEnabled == false, "\(app)")
        }
        #expect(testables(schemes, "App04") == ["App04Tests"])
        #expect(testables(schemes, "App06") == ["App06MoreTests"])
        #expect(schemes.filter { $0.name.hasSuffix("Tests") }.isEmpty)
    }

    /// Ext07 to Ext14: an extension's scheme tests the bundles of every app it builds, unless
    /// another scheme covers them; Ext23's app is reached through a framework whose UI test
    /// bundle no scheme tests.
    @Test func extensionSchemesTestTheirAppsBundles() async throws {
        let directory = try TemporaryDirectory()
        var project = AutocreationProject(targets: [
            .init(name: "Ext07", type: "app-extension"), .init(name: "Host07", type: "application", dependencies: ["Ext07"]),
            .init(name: "Host07Tests", type: "bundle.ui-testing", dependencies: ["Host07"], testTarget: "Host07"),
            .init(name: "Ext08", type: "app-extension"), .init(name: "Host08", type: "application", dependencies: ["Ext08"]),
            .init(name: "Host08Tests", type: "bundle.unit-test", settings: Self.hosted("Host08"), dependencies: ["Host08"], testTarget: "Host08"),
            .init(name: "Ext09", type: "app-extension"), .init(name: "Host09", type: "application", dependencies: ["Ext09"]),
            .init(name: "Ext10", type: "app-extension"), .init(name: "Host10", type: "application", dependencies: ["Ext10"]),
            .init(name: "Host10Tests", type: "bundle.ui-testing", dependencies: ["Host10"], testTarget: "Host10"),
            .init(name: "Ext13", type: "app-extension"), .init(name: "Host13", type: "application", dependencies: ["Ext13"]),
            .init(name: "Host13Tests", type: "bundle.ui-testing", dependencies: ["Host13"], testTarget: "Host13"),
            .init(name: "Ext14", type: "app-extension"), .init(name: "Host14", type: "application", dependencies: ["Ext14"]),
            .init(name: "Host14Tests", type: "bundle.ui-testing", dependencies: ["Host14"], testTarget: "Host14"),
            .init(name: "Other14", type: "application", dependencies: ["Ext14"]),
            .init(name: "Other14Tests", type: "bundle.ui-testing", dependencies: ["Other14"], testTarget: "Other14"),
            .init(name: "Ext23", type: "app-extension"), .init(name: "Mid23", type: "framework", dependencies: ["Ext23"]),
            .init(name: "Host23", type: "application", dependencies: ["Mid23"]),
            .init(name: "Mid23Tests", type: "bundle.ui-testing", dependencies: ["Mid23"], testTarget: "Mid23"),
        ])
        project.schemes = [
            "S10": project.scheme(build: [("Host10", true)], launch: "Host10"),
            "S13": project.scheme(testables: ["Host13Tests"]),
        ]
        let schemes = try await project.schemes(in: directory.path)
        #expect(testables(schemes, "Ext07") == ["Host07Tests"])
        #expect(testables(schemes, "Ext08") == ["Host08Tests"])
        #expect(testables(schemes, "Ext09") == [])
        #expect(testables(schemes, "Ext10") == ["Host10Tests"])
        #expect(testables(schemes, "Ext13") == [])
        #expect(Set(try #require(testables(schemes, "Ext14"))) == ["Host14Tests", "Other14Tests"])
        #expect(testables(schemes, "Ext23") == [])
        #expect(testables(schemes, "Mid23") == [])
        #expect(schemes.filter { $0.name.hasSuffix("Tests") }.isEmpty)
    }

    /// `autocreate-ui-targets`: a UI test bundle is tested by the scheme of the app its
    /// `TestTargetID` names, not by that of a framework, an app extension, a bundle or a tool,
    /// and depending on that target, it gets no scheme of its own.
    @Test func uiTestBundlesOfApps() async throws {
        let directory = try TemporaryDirectory()
        let kinds = ["application", "framework", "app-extension", "bundle", "tool"]
        let project = AutocreationProject(targets: kinds.enumerated().flatMap { index, kind -> [AutocreationProject.Target] in
            let name = String(format: "Kind%02d", index + 1)
            return [.init(name: name, type: kind), .init(name: name + "UITests", type: "bundle.ui-testing", dependencies: [name], testTarget: name)]
        })
        let schemes = try await project.schemes(in: directory.path)
        #expect(schemes.map(\.name) == ["Kind01", "Kind02", "Kind03", "Kind04", "Kind05"])
        #expect(schemes.map(\.testables.count) == [1, 0, 0, 0, 0])
    }

    /// `autocreate-debug-dev`, `-suffix`, `-upper`, `-lower`, `-both`: autocreated schemes launch
    /// with Debug, else the first configuration whose name starts with `Debug`, else the default
    /// one; Info.plists and test hosts are still read in Debug, else the first configuration.
    @Test(arguments: [
        (["Adhoc", "Debug-Dev", "Production"], "Adhoc", "Debug-Dev"), (["Release", "MyDebug", "Debugging"], "Release", "Debugging"),
        (["Release", "DEBUG", "Debugger"], "Release", "Debugger"), (["Release", "debug"], "Release", "Release"),
        (["Release", "Debug-Dev", "Debug"], "Release", "Debug"),
    ])
    func launchConfigurations(configurations: [String], defaultConfiguration: String, launched: String) async throws {
        let directory = try TemporaryDirectory()
        let host = ["TEST_HOST": "$(BUILT_PRODUCTS_DIR)/App.app/App", "BUNDLE_LOADER": "$(TEST_HOST)"]
        let project = AutocreationProject(targets: [
            .init(name: "App", type: "application"),
            .init(name: "HostedInFirst", type: "bundle.unit-test", configurationSettings: [configurations[0]: host], dependencies: ["App"]),
            .init(name: "HostedInLaunched", type: "bundle.unit-test", configurationSettings: [launched: host], dependencies: ["App"]),
        ], configurations: configurations, defaultConfiguration: defaultConfiguration)
        let schemes = try await project.schemes(in: directory.path)
        let app = try #require(schemes.first { $0.name == "App" })
        let read = configurations.contains("Debug") ? "Debug" : configurations[0]
        #expect(app.launchConfiguration == launched)
        #expect(app.testables.map(\.targetName) == [("HostedInFirst", configurations[0]), ("HostedInLaunched", launched)].filter { $0.1 == read }.map(\.0))
    }

    /// `autocreate-testables`: Auto16Tests, whose `SDKROOT` is auto, names its app under its own
    /// products folder, `Debug-unknown`, and is tested by the app's scheme.
    @Test func bundlesWhoseSDKIsAuto() async throws {
        let directory = try TemporaryDirectory()
        let project = AutocreationProject(targets: [
            .init(name: "Auto16", type: "application"),
            .init(name: "Auto16Tests", type: "bundle.unit-test", settings: Self.hosted("Auto16").merging(["SDKROOT": "auto"]) { $1 },
                  dependencies: ["Auto16"], testTarget: "Auto16"),
        ])
        let schemes = try await project.schemes(in: directory.path)
        #expect(schemes.map(\.name) == ["Auto16"])
        #expect(testables(schemes, "Auto16") == ["Auto16Tests"])
    }

    /// `autocreate-auto-hosts`: `-showBuildSettings -target` gives an app whose `SDKROOT` is auto
    /// no executable, and a unit test bundle names it by its iOS (or macOS) one: A01 is tested,
    /// A09, naming another app, and A10, naming none, are not.
    @Test func appsWhoseSDKIsAuto() async throws {
        let directory = try TemporaryDirectory()
        let auto = ["SDKROOT": "auto", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator macosx"]
        let project = AutocreationProject(targets: [
            .init(name: "A01", type: "application", settings: auto),
            .init(name: "A01Tests", type: "bundle.unit-test", settings: Self.hosted("A01"), dependencies: ["A01"], testTarget: "A01"),
            .init(name: "A09", type: "application", settings: auto),
            .init(name: "A09Tests", type: "bundle.unit-test", settings: Self.hosted("Elsewhere"), dependencies: ["A09"], testTarget: "A09"),
            .init(name: "A10", type: "application", settings: auto),
            .init(name: "A10Tests", type: "bundle.unit-test", dependencies: ["A10"], testTarget: "A10"),
        ])
        let schemes = try await project.schemes(in: directory.path)
        #expect(schemes.map(\.name) == ["A01", "A09", "A10"])
        #expect(schemes.map(\.testables.count) == [1, 0, 0])
    }

    /// `provisioning-auto`: the signing identity the PIF's provisioning style reads is, for a
    /// target whose `SDKROOT` is auto, the one it has for macOS (here a macro of `SDKROOT`).
    @Test func autoTargetsSignAsForMacOS() async throws {
        let directory = try TemporaryDirectory()
        let identity = ["CODE_SIGN_IDENTITY": "$(NOMAC_IDENTITY_$(SDKROOT))", "NOMAC_IDENTITY_macosx": "Apple Development"]
        let project = AutocreationProject(targets: [
            .init(name: "Auto", type: "application", settings: identity.merging(["SDKROOT": "auto"]) { $1 }),
            .init(name: "Device", type: "application", settings: identity),
        ])
        let identities = try await project.withInspector(in: directory.path) { inspector in
            let path = inspector.workspace.projects[0].path
            let values = try await inspector.evaluate(Set(["Auto", "Device"].map { TargetSettingsQuery(projectPath: path, targetID: project.targetID($0), configuration: "Debug") }))
            return ["Auto", "Device"].map { name in values.first { $0.key.targetID == project.targetID(name) }?.value["CODE_SIGN_IDENTITY"] }
        }
        #expect(identities == ["Apple Development", nil])
    }

    /// `scheme-name-clashes`: `-scheme Dup` uses a shared Dup scheme of Q or R, renamed in
    /// `-list`, never the autocreated scheme of P's target Dup; which of the two changes from one
    /// run to the next, and nomac takes the first (BACKLOG B-065).
    @Test func sharedSchemesBeforeAutocreatedOnes() throws {
        let directory = try TemporaryDirectory()
        var p = AutocreationProject(targets: [.init(name: "Dup", type: "application")])
        p.files = ["W.xcworkspace/contents.xcworkspacedata": #"<?xml version="1.0" encoding="UTF-8"?><Workspace version = "1.0"><FileRef location = "group:P.xcodeproj"></FileRef><FileRef location = "group:Q.xcodeproj"></FileRef><FileRef location = "group:R.xcodeproj"></FileRef></Workspace>"#]
        try p.write(in: directory.path)
        for name in ["Q", "R"] {
            var other = AutocreationProject(targets: [.init(name: name + "App", type: "application")])
            other.name = name
            other.schemes = ["Dup": other.scheme(build: [(name + "App", true)], launch: name + "App")]
            try other.write(in: directory.path)
        }
        let workspace = try XcodeWorkspace.load(path: directory.path + "/W.xcworkspace")
        let schemes = try workspace.schemes(userName: HostIdentity.current().userName)
        #expect(WorkspaceListing(workspace: workspace, schemes: schemes).schemes == ["Dup", "Dup (Q project)", "Dup (R project)"])
        #expect(try XcodeWorkspace.scheme(named: "Dup", in: schemes, workspace: workspace).buildEntries.map(\.targetName) == ["QApp"])
    }

    /// `scheme-name-clashes`: `-scheme Kit` builds the target Kit or the local package's product
    /// Kit, which one changing from one run to the next; nomac's Kit builds the target and has the
    /// product's scheme as its alternative (envelope-experiments `same-name-targets`).
    @Test func aTargetAndAProductWithOneName() throws {
        let directory = try TemporaryDirectory()
        let p = AutocreationProject(targets: [.init(name: "Kit", type: "framework")])
        try p.write(in: directory.path)
        let workspace = try XcodeWorkspace.load(path: directory.path + "/P.xcodeproj")
        let package = SwiftPackageContents(directory: directory.path + "/Packages/Kit", isRoot: false, isLocal: true,
                                           products: [.init(name: "Kit", targets: ["Kit"])], targets: ["Kit"], testTargets: [])
        let schemes = try workspace.schemes(packages: [package], userName: HostIdentity.current().userName)
        #expect(WorkspaceListing(workspace: workspace, schemes: schemes).schemes == ["Kit"])
        let kit = try XcodeWorkspace.scheme(named: "Kit", in: schemes, workspace: workspace)
        #expect(kit.buildEntries.map(\.isInPackage) == [false])
        #expect(kit.alternatives.map { $0.buildEntries.map(\.isInPackage) } == [[true]])
    }
}
