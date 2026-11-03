import Foundation
import Testing
import NomacBuildService
import NomacCore
import NomacProject
import NomacTestSupport
@testable import NomacInspect

/// Per-user schemes, the names `-list` gives schemes that share one, the schemes of test bundles,
/// the order of `-list` and the destinations a scheme accepts, each as loader-experiments
/// `user-schemes`, `user-schemes-workspace`, `user-schemes-packages`, `own-test-schemes`,
/// `own-test-schemes-hosts`, `scheme-order` and `scheme-destinations` observed them with Xcode 27.0.
@Suite struct UserSchemesTests {
    static let user = HostIdentity.current().userName

    static func write(_ files: [String: String], in root: String) throws {
        for (path, text) in files {
            let full = root + "/" + path
            try FileManager.default.createDirectory(atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try text.write(toFile: full, atomically: true, encoding: .utf8)
        }
    }

    /// The scheme `-scheme name` uses: the targets its build action builds.
    static func built(_ name: String, in schemes: [XcodeScheme], workspace: XcodeWorkspace) throws -> [String] {
        try XcodeWorkspace.scheme(named: name, in: schemes, workspace: workspace).buildEntries.map(\.targetName)
    }

    /// `user-schemes`: the current user's schemes are listed and cover targets as shared ones do;
    /// another user's, those of the project's own `project.xcworkspace`, and the `isShown` of
    /// xcschememanagement.plist are not read; its SuppressBuildableAutocreation is. A shared and
    /// a per-user scheme with one name are both renamed, and `-scheme` with either name uses the
    /// shared one, whose order hint is the lower; a per-user scheme named like a target is listed
    /// next to its autocreated scheme and wins `-scheme`.
    @Test func perUserSchemes() async throws {
        let directory = try TemporaryDirectory()
        var project = AutocreationProject(targets: [
            .init(name: "AppMine", type: "application"), .init(name: "FwMine", type: "framework"), .init(name: "AppOther", type: "application"),
            .init(name: "FwOther", type: "framework"), .init(name: "FwDup", type: "framework"), .init(name: "LibDup", type: "framework"),
            .init(name: "FwNamed", type: "framework"), .init(name: "LibNamed", type: "framework"), .init(name: "FwSuppressed", type: "framework"),
            .init(name: "FwSuppressedNo", type: "framework"), .init(name: "AppSuppressed", type: "application"),
            .init(name: "FwWsShared", type: "framework"), .init(name: "AppBuildOnly", type: "application"),
            .init(name: "TestsMine", type: "bundle.unit-test"), .init(name: "FwHidden", type: "framework"),
        ])
        project.schemes = ["Dup": project.scheme(build: [("FwDup", true)])]
        project.userSchemes = [
            "MineLaunch": project.scheme(build: [("AppMine", true)], launch: "AppMine"), "MineBuild": project.scheme(build: [("FwMine", true)]),
            "Dup": project.scheme(build: [("LibDup", true)]), "FwNamed": project.scheme(build: [("LibNamed", true)]),
            "MineTests": project.scheme(testables: ["TestsMine"]), "MineBuildApp": project.scheme(build: [("AppBuildOnly", true)]),
            "Hidden": project.scheme(build: [("FwHidden", true)]),
        ]
        let suppressed = [("FwSuppressed", true), ("FwSuppressedNo", false), ("AppSuppressed", true)]
            .map { "<key>\(project.targetID($0.0))</key><dict><key>primary</key><\($0.1)/></dict>" }.joined()
        let other = "P.xcodeproj/xcuserdata/nomac-other-user.xcuserdatad/xcschemes/"
        project.files = [
            other + "OtherLaunch.xcscheme": project.scheme(build: [("AppOther", true)], launch: "AppOther"),
            other + "OtherBuild.xcscheme": project.scheme(build: [("FwOther", true)]),
            "P.xcodeproj/project.xcworkspace/xcshareddata/xcschemes/WsShared.xcscheme": project.scheme(build: [("FwWsShared", true)]),
            project.userFolder + "/xcschememanagement.plist": #"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>SchemeUserState</key><dict>"#
                + #"<key>Hidden.xcscheme</key><dict><key>isShown</key><false/><key>orderHint</key><integer>0</integer></dict>"#
                + #"<key>Dup.xcscheme_^#shared#^_</key><dict><key>orderHint</key><integer>6</integer></dict>"#
                + #"<key>Dup.xcscheme</key><dict><key>orderHint</key><integer>7</integer></dict></dict>"#
                + "<key>SuppressBuildableAutocreation</key><dict>\(suppressed)</dict></dict></plist>\n",
        ]
        let schemes = try await project.schemes(in: directory.path)
        let workspace = try XcodeWorkspace.load(path: directory.path + "/app/P.xcodeproj")
        #expect(WorkspaceListing(workspace: workspace, schemes: schemes).schemes == [
            "AppBuildOnly", "AppOther", "Dup (P project)", "Dup (P project)", "FwNamed", "FwNamed", "FwOther", "FwSuppressedNo", "FwWsShared",
            "Hidden", "MineBuild", "MineBuildApp", "MineLaunch", "MineTests",
        ])
        #expect(try Self.built("Dup", in: schemes, workspace: workspace) == ["FwDup"])
        #expect(try Self.built("Dup (P project)", in: schemes, workspace: workspace) == ["FwDup"])
        #expect(try Self.built("FwNamed", in: schemes, workspace: workspace) == ["LibNamed"])
        #expect(throws: NomacError.self) { try XcodeWorkspace.scheme(named: "OtherLaunch", in: schemes, workspace: workspace) }
    }

    /// `scheme-pairs-hints`, `-hints-reverse`, `-hints-shared-only`, `-hints-user-only`: of a shared
    /// and a per-user scheme of one name, `-scheme` with either name uses the one with an order
    /// hint, the lower of two.
    @Test(arguments: [(6, 7, "Shared"), (7, 6, "User"), (6, nil, "Shared"), (nil, 6, "User")] as [(Int?, Int?, String)])
    func orderHintsDecideAPair(shared: Int?, user: Int?, built: String) async throws {
        let directory = try TemporaryDirectory()
        var project = AutocreationProject(targets: [.init(name: "Shared", type: "framework"), .init(name: "User", type: "framework")])
        project.schemes = ["Dup": project.scheme(build: [("Shared", true)])]
        project.userSchemes = ["Dup": project.scheme(build: [("User", true)])]
        let states = [("Dup.xcscheme_^#shared#^_", shared), ("Dup.xcscheme", user)].compactMap { key, hint in
            hint.map { "<key>\(key)</key><dict><key>orderHint</key><integer>\($0)</integer></dict>" }
        }.joined()
        project.files = [project.userFolder + "/xcschememanagement.plist":
            #"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>SchemeUserState</key><dict>"# + states + "</dict></dict></plist>\n"]
        let schemes = try await project.schemes(in: directory.path)
        let workspace = try XcodeWorkspace.load(path: directory.path + "/app/P.xcodeproj")
        #expect(try Self.built("Dup", in: schemes, workspace: workspace) == [built])
        #expect(try Self.built("Dup (P project)", in: schemes, workspace: workspace) == [built])
    }

    /// `user-schemes-workspace`: a name several shared or per-user schemes of a workspace have is
    /// followed by each one's container, its project or the workspace, even in one container;
    /// autocreated schemes keep their names. `-scheme` with a renamed name uses that scheme.
    @Test func sameNamesAreRenamedByContainer() throws {
        let directory = try TemporaryDirectory()
        var p = AutocreationProject(targets: ["FwA", "FwB", "FwP", "LibU", "FwInner1", "FwInner2", "AppW", "Twin", "Solo", "FwMixedW", "FwMixedP", "FwBothP"]
            .map { .init(name: $0, type: $0.hasPrefix("App") ? "application" : "framework") })
        var q = AutocreationProject(targets: ["FwC", "FwQ", "FwFake", "LibQ", "LibTwin", "LibSolo", "FwQU", "FwBothQ"].map { .init(name: $0, type: "framework") })
        q.name = "Q"
        p.schemes = ["Same": p.scheme(build: [("FwB", true)]), "Pair": p.scheme(build: [("FwP", true)]), "Inner": p.scheme(build: [("FwInner1", true)]),
                     "Mixed": p.scheme(build: [("FwMixedP", true)])]
        p.userSchemes = ["UserPair": p.scheme(build: [("LibU", true)]), "Inner": p.scheme(build: [("FwInner2", true)]),
                         "BothUser": p.scheme(build: [("FwBothP", true)])]
        q.schemes = ["Same": q.scheme(build: [("FwC", true)]), "Pair": q.scheme(build: [("FwQ", true)]), "Pair (P project)": q.scheme(build: [("FwFake", true)]),
                     "UserPair": q.scheme(build: [("LibQ", true)]), "Twin": q.scheme(build: [("LibTwin", true)])]
        q.userSchemes = ["QUser": q.scheme(build: [("FwQU", true)]), "BothUser": q.scheme(build: [("FwBothQ", true)])]
        let workspaceUser = "W.xcworkspace/xcuserdata/\(Self.user).xcuserdatad/xcschemes/"
        p.files = [
            "W.xcworkspace/contents.xcworkspacedata": #"<?xml version="1.0" encoding="UTF-8"?><Workspace version = "1.0"><FileRef location = "group:P.xcodeproj"></FileRef><FileRef location = "group:Q.xcodeproj"></FileRef></Workspace>"#,
            "W.xcworkspace/xcshareddata/xcschemes/Same.xcscheme": p.scheme(build: [("FwA", true)]),
            "W.xcworkspace/xcshareddata/xcschemes/Solo.xcscheme": q.scheme(build: [("LibSolo", true)]),
            workspaceUser + "WUser.xcscheme": p.scheme(build: [("AppW", true)], launch: "AppW"),
            workspaceUser + "Mixed.xcscheme": p.scheme(build: [("FwMixedW", true)]),
        ]
        try p.write(in: directory.path)
        try q.write(in: directory.path)
        let workspace = try XcodeWorkspace.load(path: directory.path + "/W.xcworkspace")
        let schemes = try workspace.schemes(userName: Self.user)
        #expect(WorkspaceListing(workspace: workspace, schemes: schemes).schemes == [
            "BothUser (P project)", "BothUser (Q project)", "Inner (P project)", "Inner (P project)", "Mixed (P project)", "Mixed (W Workspace)",
            "Pair (P project)", "Pair (P project)", "Pair (Q project)", "QUser", "Same (P project)", "Same (Q project)", "Same (W Workspace)",
            "Solo", "Solo", "Twin", "Twin", "UserPair (P project)", "UserPair (Q project)", "WUser",
        ])
        #expect(try Self.built("Same (W Workspace)", in: schemes, workspace: workspace) == ["FwA"])
        #expect(try Self.built("Same (P project)", in: schemes, workspace: workspace) == ["FwB"])
        #expect(try Self.built("Same (Q project)", in: schemes, workspace: workspace) == ["FwC"])
        #expect(try Self.built("Pair (P project)", in: schemes, workspace: workspace) == ["FwP"])
        #expect(try Self.built("Twin", in: schemes, workspace: workspace) == ["LibTwin"])
        #expect(try Self.built("Solo", in: schemes, workspace: workspace) == ["LibSolo"])
    }

    /// `user-schemes-packages`: a package scheme sharing a name is followed by the package's folder
    /// name; a package's per-user schemes are read, and they and a project's cover its products.
    @Test func packageSchemesAreRenamedByFolder() throws {
        let directory = try TemporaryDirectory()
        var project = AutocreationProject(targets: [.init(name: "FwClash", type: "framework")])
        project.schemes = ["Clash": project.scheme(build: [("FwClash", true)])]
        let package = directory.path + "/Kit Folder"
        project.files = [
            project.userFolder + "/MineKitMore.xcscheme": SchemeFixtures.scheme(build: [("KitMore", "container:Kit Folder", true)]),
            "Kit Folder/.swiftpm/xcode/xcshareddata/xcschemes/Clash.xcscheme": SchemeFixtures.scheme(build: [("Kit", "container:", true)]),
            "Kit Folder/.swiftpm/xcode/xcuserdata/\(Self.user).xcuserdatad/xcschemes/KitUser.xcscheme": SchemeFixtures.scheme(build: [("KitExtras", "container:", true)]),
        ]
        try project.write(in: directory.path)
        let workspace = try XcodeWorkspace.load(path: directory.path + "/P.xcodeproj")
        let contents = SwiftPackageContents(directory: package, isRoot: true, products: ["Kit", "KitExtras", "KitMore"].map { .init(name: $0, targets: [$0]) },
                                            targets: ["Kit", "KitExtras", "KitMore"], testTargets: [])
        let schemes = try workspace.schemes(packages: [contents], userName: Self.user)
        #expect(WorkspaceListing(workspace: workspace, schemes: schemes).schemes == ["Clash (Kit Folder)", "Clash (P project)", "KitUser", "MineKitMore"])
    }

    /// `own-test-schemes`, `own-test-schemes-hosts`, `own-test-schemes-more`: a test bundle no
    /// scheme tests or skips gets a scheme of its own unless a target's scheme would test it
    /// (whoever covers that target), or its TEST_HOST is the executable of a target with an
    /// autocreated scheme, or, when it names none, it depends on such a target. A scheme that
    /// only skips its testables fails with 64, not 66.
    @Test func testBundlesOwnSchemes() async throws {
        let directory = try TemporaryDirectory()
        let host = { (app: String) in ["TEST_HOST": "$(BUILT_PRODUCTS_DIR)/\(app).app/\(app)", "BUNDLE_LOADER": "$(TEST_HOST)"] }
        var project = AutocreationProject(targets: [
            .init(name: "Fw01", type: "framework"), .init(name: "Fw01Tests", type: "bundle.unit-test", dependencies: ["Fw01"]),
            .init(name: "Fw02", type: "framework"), .init(name: "Fw02Tests", type: "bundle.unit-test", dependencies: ["Fw02"]),
            .init(name: "Fw03", type: "framework"), .init(name: "Fw03Tests", type: "bundle.unit-test", dependencies: ["Fw03"]),
            .init(name: "App04", type: "application"),
            .init(name: "App04Tests", type: "bundle.unit-test", settings: host("App04"), dependencies: ["App04"], testTarget: "App04"),
            .init(name: "App05", type: "application"), .init(name: "App05Tests", type: "bundle.unit-test", settings: host("App05")),
            .init(name: "App06", type: "application"), .init(name: "App06Tests", type: "bundle.unit-test", settings: host("App06")),
            .init(name: "H1Tests", type: "bundle.unit-test", settings: host("Nowhere")),
            .init(name: "App07", type: "application"), .init(name: "H7Tests", type: "bundle.unit-test", settings: ["TEST_HOST": "$(BUILT_PRODUCTS_DIR)/App07.app"]),
            .init(name: "App08", type: "application"), .init(name: "H8Tests", type: "bundle.unit-test", settings: host("App08")),
            .init(name: "Fw09", type: "framework"), .init(name: "D9Tests", type: "bundle.unit-test", dependencies: ["Fw09"]),
            .init(name: "Messages10", type: "application.messages"), .init(name: "D10Tests", type: "bundle.unit-test", dependencies: ["Messages10"]),
            .init(name: "Agg11", type: "aggregate"), .init(name: "D11Tests", type: "bundle.unit-test", dependencies: ["Agg11"]),
            .init(name: "S12Tests", type: "bundle.unit-test"),
            .init(name: "App13", type: "application"), .init(name: "App13UITests", type: "bundle.ui-testing", dependencies: ["App13"], testTarget: "App13"),
            .init(name: "App14", type: "application"), .init(name: "App14UITests", type: "bundle.ui-testing", dependencies: ["App14"]),
            .init(name: "SkipTests", type: "bundle.unit-test"), .init(name: "SkipDepTests", type: "bundle.unit-test", dependencies: ["Fw02"]),
            .init(name: "A15", type: "application"), .init(name: "F15", type: "framework"),
            .init(name: "B15Tests", type: "bundle.unit-test", settings: host("A15"), dependencies: ["F15"]),
            .init(name: "F16", type: "framework"), .init(name: "B16Tests", type: "bundle.unit-test", settings: host("Nowhere"), dependencies: ["F16"]),
        ])
        for (index, target) in [(2, "Fw02"), (4, "App04"), (5, "App05"), (13, "App13"), (14, "App14")] {
            project.schemes["Cover\(index)"] = project.scheme(build: [(target, true)], launch: target.hasPrefix("App") ? target : nil)
        }
        project.schemes["Cover15"] = project.scheme(build: [("A15", true)], launch: "A15")
        project.schemes["Skip"] = project.scheme(testables: ["SkipTests", "SkipDepTests"], skipped: true)
        project.userSchemes = ["Cover3": project.scheme(build: [("Fw03", true)])]
        project.suppressed = ["App08": true, "Fw09": true, "S12Tests": true]
        let (names, skipStatus) = try await project.withInspector(in: directory.path) { inspector in
            let names = Set(try await inspector.schemes().map(\.name))
            do {
                _ = try await inspector.blocks(.init(selection: .scheme("Skip"), destination: "generic/platform=iOS"))
                return (names, Int32?.none)
            } catch {
                return (names, (error as? NomacError)?.exitStatus)
            }
        }
        #expect(skipStatus == 64)
        #expect(names == ["Cover2", "Cover3", "Cover4", "Cover5", "Cover13", "Cover14", "Cover15", "Skip", "Fw01", "App06", "App07", "Agg11", "F15",
                          "F16", "Fw02Tests", "Fw03Tests", "App05Tests", "H1Tests", "H7Tests", "H8Tests", "D9Tests", "D10Tests", "App14UITests",
                          "B15Tests"])
    }

    /// `own-test-schemes-more`: a TEST_HOST names an executable of another project too, whatever
    /// that project's configurations; that target decides, not the autocreated framework the
    /// bundle depends on (B5Tests).
    @Test func testHostsOfOtherProjects() async throws {
        let directory = try TemporaryDirectory()
        var hosts = AutocreationProject(targets: [.init(name: "X5", type: "application"), .init(name: "Y5", type: "application")],
                                        configurations: ["AppStore", "Production"], defaultConfiguration: "AppStore")
        hosts.name = "S"
        hosts.schemes = ["CoverX5": hosts.scheme(build: [("X5", true)], launch: "X5")]
        let host = { (app: String) in ["TEST_HOST": "$(BUILT_PRODUCTS_DIR)/\(app).app/\(app)", "BUNDLE_LOADER": "$(TEST_HOST)"] }
        var bundles = AutocreationProject(targets: [
            .init(name: "F5", type: "framework"), .init(name: "B5Tests", type: "bundle.unit-test", settings: host("X5"), dependencies: ["F5"]),
            .init(name: "F6", type: "framework"), .init(name: "B6Tests", type: "bundle.unit-test", settings: host("Y5"), dependencies: ["F6"]),
        ])
        bundles.name = "Q"
        bundles.files = ["W.xcworkspace/contents.xcworkspacedata":
            #"<?xml version="1.0" encoding="UTF-8"?><Workspace version = "1.0"><FileRef location = "group:Q.xcodeproj"></FileRef><FileRef location = "group:S.xcodeproj"></FileRef></Workspace>"#]
        try hosts.write(in: directory.path + "/app")
        try bundles.write(in: directory.path + "/app")
        let names = try await SchemeFixtures.withInspector(of: try XcodeWorkspace.load(path: directory.path + "/app/W.xcworkspace"), in: directory.path) {
            Set(try await $0.schemes().map(\.name))
        }
        #expect(names == ["CoverX5", "F5", "F6", "Y5", "B5Tests"])
    }

    /// `scheme-order`, `unicode-list-order`: xcodebuild's order of these names, which nomac gets
    /// from any other order.
    @Test func listOrder() {
        let observed = [" Leading", "_under", "-dash", "🙂 smile", "10lives", "9lives", "a b", "a_b", "a-b", "a.b", "a+b", "ab", "Ab1", "Ab10", "ab2",
                        "Émile", "Eve", "ezra", "ﬁle", "file2", "Ｆull", "item10", "Item2", "Oeuvre", "Œuvre", "strasse", "straße", "u", "U", "Ü",
                        "Uber", "über", "über2", "Ünï Kit", "Unit", "UNIT", "Vendor", "x 1", "x(1)", "x01", "x1", "zed", "Zed", "Ωmega", "Яблоко", "日本"]
        #expect(WorkspaceListing.ordered(observed.reversed()) == observed)
        #expect(WorkspaceListing.ordered(observed.sorted()) == observed)
        // `unicode-list-order`: decomposed names, ligatures, ß and the Angstrom and Ohm signs.
        let normalized = ["a\u{301}", "Aa", "\u{C0}a", "Ab", "AEa", "\u{C6}b", "\u{212B}x", "\u{C5}y", "\u{C9}a", "Eb", "E\u{301}c", "\u{FB01}x", "\u{D8}a",
                          "Ob", "ss", "\u{DF}a", "Ue", "\u{DC}n\u{EF} Kit", "Vendor", "Zz", "\u{3A9}b", "\u{2126}mega", "\u{65E5}\u{672C}"]
        #expect(WorkspaceListing.ordered(normalized.reversed()) == normalized)
    }

    /// `scheme-destinations`: what a scheme launches decides which destinations it accepts, a
    /// profiled target does not; an aggregate target also accepts those of the targets it depends
    /// on, through other aggregates; an autocreated extension scheme launches its first app.
    @Test func destinations() async throws {
        let directory = try TemporaryDirectory()
        let mac = ["SUPPORTED_PLATFORMS": "macosx"]
        var project = AutocreationProject(targets: [
            .init(name: "Tool1", type: "tool", settings: mac), .init(name: "Bundle1", type: "bundle"),
            .init(name: "Tool2", type: "tool", settings: mac), .init(name: "Bundle2", type: "bundle"),
            .init(name: "Tool3", type: "tool", settings: mac), .init(name: "Bundle3", type: "bundle"),
            .init(name: "Tool4", type: "tool", settings: mac), .init(name: "Bundle4", type: "bundle"),
            .init(name: "Fw5", type: "framework"), .init(name: "Agg5", type: "aggregate", settings: mac, dependencies: ["Fw5"]),
            .init(name: "Fw6", type: "framework"), .init(name: "Agg6b", type: "aggregate", settings: mac, dependencies: ["Fw6"]),
            .init(name: "Agg6", type: "aggregate", settings: mac, dependencies: ["Agg6b"]),
            .init(name: "Fw7", type: "framework"), .init(name: "MacFw7", type: "framework", settings: mac, dependencies: ["Fw7"]),
            .init(name: "Agg8", type: "aggregate", settings: mac),
            .init(name: "ExtIOS9", type: "app-extension"), .init(name: "MacHost9", type: "application", settings: mac, dependencies: ["ExtIOS9"]),
            .init(name: "ExtMac10", type: "app-extension", settings: mac), .init(name: "Host10", type: "application", dependencies: ["ExtMac10"]),
        ])
        project.schemes = [
            "LaunchTool": project.scheme(build: [("Tool1", true), ("Bundle1", true)], launch: "Tool1"),
            "BuildToolBundle": project.scheme(build: [("Tool2", true), ("Bundle2", true)]),
            "ProfileTool": project.scheme(build: [("Tool3", true), ("Bundle3", true)], profile: "Tool3"),
            "RemoteTool": project.scheme(build: [("Tool4", true), ("Bundle4", true)], remote: "Tool4"),
            "AggDepIOS": project.scheme(build: [("Agg5", true)]),
            "AggDeep": project.scheme(build: [("Agg6", true)]),
            "MacFwDepIOS": project.scheme(build: [("MacFw7", true)]),
            "AggOnly": project.scheme(build: [("Agg8", true)]),
        ]
        let schemes = ["LaunchTool", "BuildToolBundle", "ProfileTool", "RemoteTool", "AggDepIOS", "AggDeep", "MacFwDepIOS", "AggOnly", "ExtIOS9", "ExtMac10"]
        let results = try await project.withInspector(in: directory.path) { inspector in
            var results: [String] = []
            for scheme in schemes {
                do {
                    results.append(try await inspector.blocks(.init(selection: .scheme(scheme), destination: "generic/platform=iOS")).map(\.target).joined(separator: ","))
                } catch {
                    results.append("\((error as? NomacError)?.exitStatus ?? -1)")
                }
            }
            return results
        }
        #expect(results == ["64", "Tool2,Bundle2", "Tool3,Bundle3", "64", "Agg5", "Agg6", "64", "64", "64", "ExtMac10,Host10"])
    }

    /// `symroot-project-*`: in a project opened alone where a target assigns
    /// SYMROOT without a condition, a scheme's targets get the project's own products,
    /// intermediates and precompiled headers folders, and keep DerivedData's caches; a conditional
    /// assignment does not count.
    @Test(arguments: [("SYMROOT", true), ("\"SYMROOT[sdk=iphoneos*]\"", false)])
    func symrootKeepsTheProjectLocations(key: String, legacy: Bool) async throws {
        let directory = try TemporaryDirectory()
        let project = AutocreationProject(targets: [
            .init(name: "Plain", type: "framework"),
            .init(name: "Other", type: "framework", settings: [key: "Custom"]),
        ])
        let settings = try await project.withInspector(in: directory.path) { inspector in
            try await inspector.blocks(.init(selection: .scheme("Plain"), destination: "generic/platform=iOS")).first?.dictionary ?? [:]
        }
        let app = (directory.path as NSString).resolvingSymlinksInPath + "/app"
        #expect((settings["BUILD_DIR"].map { ($0 as NSString).resolvingSymlinksInPath } == app + "/build") == legacy)
        #expect((settings["SHARED_PRECOMPS_DIR"].map { ($0 as NSString).resolvingSymlinksInPath } == app + "/build/SharedPrecompiledHeaders") == legacy)
        #expect(settings["MODULE_CACHE_DIR"]?.hasSuffix("/DerivedData/ModuleCache.noindex") == true)
    }

    /// `simulator-sdks` (BACKLOG B-089): a target whose SDKROOT, in the scheme's launch
    /// configuration, is a simulator's refuses an iOS device destination whatever its
    /// SUPPORTED_PLATFORMS, also with another `-configuration`; one whose SDKROOT is a device's
    /// goes by its SUPPORTED_PLATFORMS.
    @Test func simulatorSDKs() async throws {
        let directory = try TemporaryDirectory()
        let project = AutocreationProject(targets: [
            .init(name: "SimIOS", type: "framework", settings: ["SDKROOT": "iphonesimulator"]),
            .init(name: "SimIOSBoth", type: "framework", settings: ["SDKROOT": "iphonesimulator", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator"]),
            .init(name: "DevIOSSimOnly", type: "framework", settings: ["SUPPORTED_PLATFORMS": "iphonesimulator"]),
            .init(name: "DevIOS", type: "framework"),
            .init(name: "PerConfigSimDebug", type: "framework", configurationSettings: ["Debug": ["SDKROOT": "iphonesimulator"]]),
            .init(name: "PerConfigSimRelease", type: "framework", configurationSettings: ["Release": ["SDKROOT": "iphonesimulator"]]),
        ])
        let cases: [(String, String?)] = [("SimIOS", nil), ("SimIOSBoth", nil), ("DevIOSSimOnly", nil), ("DevIOS", nil),
                                          ("PerConfigSimDebug", nil), ("PerConfigSimDebug", "Release"), ("PerConfigSimRelease", nil)]
        let results = try await project.withInspector(in: directory.path) { inspector in
            var results: [String] = []
            for (scheme, configuration) in cases {
                do {
                    _ = try await inspector.blocks(.init(selection: .scheme(scheme), configuration: configuration, destination: "generic/platform=iOS"))
                    results.append("0")
                } catch {
                    results.append("\((error as? NomacError)?.exitStatus ?? -1)")
                }
            }
            return results
        }
        #expect(results == ["64", "64", "64", "0", "64", "64", "0"])
    }
}
