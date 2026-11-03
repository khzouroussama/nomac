import Foundation
import Testing
import NomacBuildService
import NomacCore
import NomacPackages
import NomacPIF
import NomacProject
import NomacTestSupport
@testable import NomacInspect

/// loader-experiments `schemes`, written again here: Xcode 27.0's `-list` for this layout is the
/// expectation of `listsSchemesAsXcodeDoes`.
enum SchemeFixtures {
    static let app = "C00000000000000000000001", tests = "C00000000000000000000002", mac = "C00000000000000000000003"

    /// A shared scheme. `build` holds (blueprint, container, built for running).
    static func scheme(build: [(String, String, Bool)] = [], testables: [(String, String)] = []) -> String {
        func reference(_ blueprint: String, _ container: String) -> String {
            """
                        <BuildableReference
                           BuildableIdentifier = "primary"
                           BlueprintIdentifier = "\(blueprint)"
                           BuildableName = "\(blueprint)"
                           BlueprintName = "\(blueprint)"
                           ReferencedContainer = "\(container)">
                        </BuildableReference>

            """
        }
        let entries = build.map { blueprint, container, running in
            let flag = running ? "YES" : "NO"
            return """
                     <BuildActionEntry
                        buildForTesting = "YES" buildForRunning = "\(flag)" buildForProfiling = "\(flag)" buildForArchiving = "\(flag)" buildForAnalyzing = "YES">

            """ + reference(blueprint, container) + "         </BuildActionEntry>\n"
        }.joined()
        let tests = testables.map { "         <TestableReference skipped = \"NO\">\n" + reference($0.0, $0.1) + "         </TestableReference>\n" }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <Scheme LastUpgradeVersion = "2700" version = "1.7">
           <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
              <BuildActionEntries>
        \(entries)      </BuildActionEntries>
           </BuildAction>
           <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
              <Testables>
        \(tests)      </Testables>
           </TestAction>
           <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
           </LaunchAction>
        </Scheme>

        """
    }

    static func target(_ id: String, _ name: String, _ type: String, list: String, settings: String = "") -> String {
        let product = "R" + id.dropFirst()
        let (fileType, ext) = type.hasSuffix("unit-test") ? ("wrapper.cfbundle", "xctest") : ("wrapper.application", "app")
        return """
        \t\t\(product) = {isa = PBXFileReference; explicitFileType = \(fileType); path = \(name).\(ext); sourceTree = BUILT_PRODUCTS_DIR; };
        \t\t\(id) = {isa = PBXNativeTarget; buildConfigurationList = \(list); buildPhases = (); name = \(name); productName = \(name); productReference = \(product); productType = "\(type)"; };
        \t\t\(list) = {isa = XCConfigurationList; buildConfigurations = (\(list)D, ); defaultConfigurationName = Debug; };
        \t\t\(list)D = {isa = XCBuildConfiguration; buildSettings = {PRODUCT_NAME = "$(TARGET_NAME)"; \(settings)}; name = Debug; };

        """
    }

    /// App (iOS), AppTests (tests App), MacTool (macOS only; the synthetic developer directory
    /// has no macOS SDK, so only its SUPPORTED_PLATFORMS says so) and the folders Kit, Lib and
    /// Solo in the file tree.
    static let project = """
    // !$*UTF8*$!
    {
    \tarchiveVersion = 1;
    \tobjectVersion = 77;
    \tobjects = {
    \t\tA00000000000000000000005 = {isa = PBXFileReference; lastKnownFileType = wrapper; path = Kit; sourceTree = "<group>"; };
    \t\tA00000000000000000000006 = {isa = PBXFileReference; lastKnownFileType = wrapper; path = Lib; sourceTree = "<group>"; };
    \t\tA00000000000000000000007 = {isa = PBXFileReference; lastKnownFileType = wrapper; path = Solo; sourceTree = "<group>"; };
    \t\tF00000000000000000000002 = {isa = PBXGroup; children = (A00000000000000000000005, A00000000000000000000006, A00000000000000000000007, ); sourceTree = "<group>"; };
    \(target(app, "App", "com.apple.product-type.application", list: "F000000000000000000000TL"))\
    \(target(tests, "AppTests", "com.apple.product-type.bundle.unit-test", list: "F000000000000000000000UL"))\
    \(target(mac, "MacTool", "com.apple.product-type.application", list: "F000000000000000000000ML", settings: "SUPPORTED_PLATFORMS = macosx; "))\
    \t\tF00000000000000000000006 = {isa = PBXProject; attributes = {TargetAttributes = {\(tests) = {TestTargetID = \(app); }; }; }; buildConfigurationList = F000000000000000000000PL; mainGroup = F00000000000000000000002; projectDirPath = ""; projectRoot = ""; targets = (\(app), \(tests), \(mac), ); };
    \t\tF000000000000000000000PL = {isa = XCConfigurationList; buildConfigurations = (F000000000000000000000PD, ); defaultConfigurationName = Debug; };
    \t\tF000000000000000000000PD = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; }; name = Debug; };
    \t};
    \trootObject = F00000000000000000000006;
    }

    """

    /// `workspace`'s schemes as nomac computes them: the target settings the autocreation rules
    /// read come from Swift Build, with a synthetic iOS developer directory under `directory`.
    static func schemes(of workspace: XcodeWorkspace, packages: [SwiftPackageContents] = [], in directory: String) async throws -> [XcodeScheme] {
        try await withInspector(of: workspace, packages: packages, in: directory) { try await $0.schemes() }
    }

    /// Runs `body` with an inspector of `workspace`, with `packages` as its resolved graph and a
    /// synthetic iOS developer directory under `directory`.
    static func withInspector<T>(of workspace: XcodeWorkspace, packages: [SwiftPackageContents] = [], in directory: String,
                                 _ body: (BuildSettingsInspector) async throws -> T) async throws -> T {
        var generator = PIFGenerator(workspace: workspace)
        let pif = WorkspacePIF(document: try generator.generate(), warnings: [],
                               sourcePackages: packages.map { SourcePackage(name: ($0.directory as NSString).lastPathComponent, identity: ($0.directory as NSString).lastPathComponent.lowercased(), location: $0.directory, pin: nil, contents: $0) })
        let developer = try SyntheticDeveloperDirectory.create(at: directory + "/xcode")
        return try await BuildSettingsInspector.with(workspace: workspace, pif: pif, developerDirectory: developer, host: HostIdentity.current(), scratchDirectory: directory + "/scratch", body)
    }

    /// Writes the experiment's project and shared schemes under `root`; returns its packages as
    /// the resolved graph describes them.
    static func write(at root: String) throws -> [SwiftPackageContents] {
        let container = "container:P.xcodeproj"
        let files: [String: String] = [
            "P.xcodeproj/project.pbxproj": project,
            "P.xcodeproj/xcshareddata/xcschemes/AppTestsOnly.xcscheme": scheme(testables: [(tests, container)]),
            "P.xcodeproj/xcshareddata/xcschemes/GhostApp.xcscheme": scheme(build: [("C00000000000000000000099", container, true)]),
            "P.xcodeproj/xcshareddata/xcschemes/TestingOnly.xcscheme": scheme(build: [(app, container, false)]),
            "P.xcodeproj/xcshareddata/xcschemes/Both.xcscheme": scheme(build: [(app, container, true), (mac, container, true)]),
            "P.xcodeproj/xcshareddata/xcschemes/AppAndKit.xcscheme": scheme(build: [(app, container, true), ("Kit", "container:Kit", true)]),
            "Lib/.swiftpm/xcode/xcshareddata/xcschemes/Lib.xcscheme": scheme(build: [("Lib", "container:", true)]),
            "Solo/.swiftpm/xcode/xcshareddata/xcschemes/SoloTests.xcscheme": scheme(testables: [("SoloTests", "container:")]),
            "Solo/.swiftpm/xcode/xcshareddata/xcschemes/Ghost.xcscheme": scheme(testables: [("Ghost", "container:")]),
            "Solo/.swiftpm/xcode/xcshareddata/xcschemes/Broken.xcscheme": scheme(build: [("Nope", "container:", true)]),
            "Deps/Dep/.swiftpm/xcode/xcshareddata/xcschemes/DepShared.xcscheme": scheme(build: [("Dep", "container:", true)]),
        ]
        for (path, text) in files {
            let full = root + "/" + path
            try FileManager.default.createDirectory(atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try text.write(toFile: full, atomically: true, encoding: .utf8)
        }
        typealias Product = SwiftPackageContents.Product
        typealias Test = SwiftPackageContents.TestTarget
        return [
            SwiftPackageContents(directory: root + "/Deps/Dep", isRoot: false, isLocal: true, products: [Product(name: "Dep", targets: ["Dep"])], targets: ["Dep"], testTargets: []),
            SwiftPackageContents(
                directory: root + "/Kit", isRoot: true,
                products: [Product(name: "Kit", targets: ["Kit"]), Product(name: "KitExtras", targets: ["KitExtras"]), Product(name: "kit-cli", targets: ["KitCLI"], isExecutable: true)],
                targets: ["Kit", "KitExtras", "KitCLI", "KitInternal"],
                testTargets: [Test(name: "KitTests", dependencies: ["Kit"]), Test(name: "KitExtrasTests", dependencies: ["KitExtras"]), Test(name: "LooseTests", dependencies: ["KitInternal"])]),
            SwiftPackageContents(directory: root + "/Lib", isRoot: true, products: [Product(name: "Lib", targets: ["Lib"])], targets: ["Lib"],
                                 testTargets: [Test(name: "LibTests", dependencies: ["Lib"])]),
            SwiftPackageContents(directory: root + "/Solo", isRoot: true, products: [Product(name: "Solo", targets: ["Solo"])], targets: ["Solo"],
                                 testTargets: [Test(name: "SoloTests", dependencies: ["Solo"])]),
        ]
    }
}

@Suite struct PackageSchemesTests {
    @Test func listsSchemesAsXcodeDoes() async throws {
        let directory = try TemporaryDirectory()
        let packages = try SchemeFixtures.write(at: directory.path + "/app")
        let schemes = try await SchemeFixtures.schemes(of: try XcodeWorkspace.load(path: directory.path + "/app/P.xcodeproj"), packages: packages, in: directory.path)
        // App and MacTool are built by shared schemes that do not launch them, so they keep
        // their autocreated schemes. Not listed: AppTests (tested by AppTestsOnly), Kit (built
        // by AppAndKit), KitExtrasTests (named after KitExtras, whose scheme is listed), Dep
        // (built by DepShared) and DepTests (a dependency's test target).
        #expect(schemes.map(\.name).sorted { $0.lowercased() < $1.lowercased() } == WorkspaceListingTests.schemes)
        let extras = try #require(schemes.first { $0.name == "KitExtras" })
        #expect(extras.isAutocreated && extras.buildEntries.map(\.targetID) == ["KitExtras"] && extras.buildEntries[0].isInPackage)
        #expect(extras.testables.isEmpty)
        let looseTests = try #require(schemes.first { $0.name == "LooseTests" })
        #expect(looseTests.buildEntries.isEmpty && looseTests.testables.map(\.containerPath) == [directory.path + "/app/Kit"])
        let depShared = try #require(schemes.first { $0.name == "DepShared" })
        #expect(depShared.buildEntries.map(\.containerPath) == [directory.path + "/app/Deps/Dep"])
    }

    /// loader-experiments `local-packages`: every local package, a path dependency of another
    /// included, gets a scheme for each product, whether the project uses it or not; remote
    /// packages get none (swiftfin).
    @Test func localPackagesGetProductSchemes() async throws {
        let directory = try TemporaryDirectory()
        let root = directory.path + "/app"
        let project = """
        // !$*UTF8*$!
        {
        \tarchiveVersion = 1;
        \tobjectVersion = 77;
        \tobjects = {
        \t\tF00000000000000000000002 = {isa = PBXGroup; children = (); sourceTree = "<group>"; };
        \(SchemeFixtures.target(SchemeFixtures.app, "App", "com.apple.product-type.application", list: "F000000000000000000000TL"))\
        \t\tF00000000000000000000006 = {isa = PBXProject; buildConfigurationList = F000000000000000000000PL; mainGroup = F00000000000000000000002; projectDirPath = ""; projectRoot = ""; targets = (\(SchemeFixtures.app), ); };
        \t\tF000000000000000000000PL = {isa = XCConfigurationList; buildConfigurations = (F000000000000000000000PD, ); defaultConfigurationName = Debug; };
        \t\tF000000000000000000000PD = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; }; name = Debug; };
        \t};
        \trootObject = F00000000000000000000006;
        }

        """
        try FileSystem.write(Data(project.utf8), to: root + "/P.xcodeproj/project.pbxproj")
        typealias Product = SwiftPackageContents.Product
        func local(_ name: String, _ products: [String], targets: [String]? = nil) -> SwiftPackageContents {
            SwiftPackageContents(directory: root + "/Deps/" + name, isRoot: false, isLocal: true, products: products.map { Product(name: $0, targets: [$0]) },
                                 targets: targets ?? products, testTargets: [])
        }
        let packages = [
            local("Plain", ["Plain"]), local("Inner", ["Inner"]), local("Unused", ["Unused"]),
            local("Multi", ["MultiA", "MultiB", "multi-tool"], targets: ["MultiA", "MultiB", "MultiTool", "MultiInternal"]),
            SwiftPackageContents(directory: directory.path + "/SourcePackages/checkouts/Remote", isRoot: false, products: [Product(name: "RemoteKit", targets: ["RemoteKit"])],
                                 targets: ["RemoteKit"], testTargets: []),
        ]
        let workspace = try XcodeWorkspace.load(path: root + "/P.xcodeproj")
        let listing = WorkspaceListing(workspace: workspace, schemes: try await SchemeFixtures.schemes(of: workspace, packages: packages, in: directory.path))
        #expect(listing.schemes == ["App", "Inner", "multi-tool", "MultiA", "MultiB", "Plain", "Unused"])
    }

    /// loader-experiments `root-package-references` (element-x's MacrosTests): a root package's
    /// test target named after a listed product scheme gets none, whatever it tests; the others get
    /// one, and product schemes test nothing.
    @Test func testTargetsNamedAfterAProductHaveNoScheme() async throws {
        let directory = try TemporaryDirectory()
        let root = directory.path + "/app"
        let project = """
        // !$*UTF8*$!
        {
        \tarchiveVersion = 1;
        \tobjectVersion = 77;
        \tobjects = {
        \t\tF00000000000000000000002 = {isa = PBXGroup; children = (); sourceTree = "<group>"; };
        \(SchemeFixtures.target(SchemeFixtures.app, "App", "com.apple.product-type.application", list: "F000000000000000000000TL"))\
        \t\tF00000000000000000000006 = {isa = PBXProject; buildConfigurationList = F000000000000000000000PL; mainGroup = F00000000000000000000002; projectDirPath = ""; projectRoot = ""; targets = (\(SchemeFixtures.app), ); };
        \t\tF000000000000000000000PL = {isa = XCConfigurationList; buildConfigurations = (F000000000000000000000PD, ); defaultConfigurationName = Debug; };
        \t\tF000000000000000000000PD = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; }; name = Debug; };
        \t};
        \trootObject = F00000000000000000000006;
        }

        """
        try FileSystem.write(Data(project.utf8), to: root + "/P.xcodeproj/project.pbxproj")
        typealias Test = SwiftPackageContents.TestTarget
        let package = SwiftPackageContents(
            directory: root + "/Multi", isRoot: true, products: ["Alpha", "Beta"].map { .init(name: $0, targets: [$0]) }, targets: ["Alpha", "Beta"],
            testTargets: [Test(name: "AlphaTests", dependencies: ["Beta"]), Test(name: "BetaChecks", dependencies: ["Beta"]), Test(name: "GammaTests", dependencies: ["Alpha"])])
        let workspace = try XcodeWorkspace.load(path: root + "/P.xcodeproj")
        let schemes = try await SchemeFixtures.schemes(of: workspace, packages: [package], in: directory.path)
        #expect(WorkspaceListing(workspace: workspace, schemes: schemes).schemes == ["Alpha", "App", "Beta", "BetaChecks", "GammaTests"])
        #expect(schemes.first { $0.name == "Alpha" }?.testables.isEmpty == true)
    }

    /// loader-experiments `scheme-package-clashes` (wordpress's `WordPressKit`): a shared scheme
    /// named after a local package's product, building something else, leaves the product its
    /// scheme, and both are listed.
    @Test func aSharedSchemeNamedAfterAProductLeavesItsScheme() async throws {
        let directory = try TemporaryDirectory()
        let root = directory.path + "/app"
        _ = try SchemeFixtures.write(at: root)
        let shared = root + "/P.xcodeproj/xcshareddata/xcschemes"
        try FileSystem.write(Data(SchemeFixtures.scheme(build: [("C99999999999999999999999", "container:P.xcodeproj", true)]).utf8), to: shared + "/Stale.xcscheme")
        let package = SwiftPackageContents(directory: root + "/Deps/Stale", isRoot: false, isLocal: true,
                                           products: [.init(name: "Stale", targets: ["Stale"])], targets: ["Stale"], testTargets: [])
        let workspace = try XcodeWorkspace.load(path: root + "/P.xcodeproj")
        let schemes = try await SchemeFixtures.schemes(of: workspace, packages: [package], in: directory.path)
        #expect(schemes.filter { $0.name == "Stale" }.map(\.isAutocreated) == [false, true])
    }

    /// loader-experiments `package-target-kinds`: a scheme that builds an executable product for
    /// running leaves it its scheme; one that launches it does not, nor one that names it in a
    /// RemoteRunnable's MacroExpansion (`tool4`).
    @Test func onlyALaunchCoversAnExecutableProduct() async throws {
        let directory = try TemporaryDirectory()
        let root = directory.path + "/app"
        let packages = try SchemeFixtures.write(at: root)
        let schemes = root + "/Kit/.swiftpm/xcode/xcshareddata/xcschemes"
        try FileManager.default.createDirectory(atPath: schemes, withIntermediateDirectories: true)
        let building = SchemeFixtures.scheme(build: [("kit-cli", "container:", true)])
        try building.write(toFile: schemes + "/BuildsCLI.xcscheme", atomically: true, encoding: .utf8)
        let built = try await SchemeFixtures.schemes(of: try XcodeWorkspace.load(path: root + "/P.xcodeproj"), packages: packages, in: directory.path).map(\.name)
        #expect(built.contains("kit-cli"))
        let runnable = """
        <BuildableProductRunnable runnableDebuggingMode = "0"><BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "kit-cli" \
        BuildableName = "kit-cli" BlueprintName = "kit-cli" ReferencedContainer = "container:"></BuildableReference></BuildableProductRunnable>
        </LaunchAction>
        """
        try building.replacingOccurrences(of: "</LaunchAction>", with: runnable).write(toFile: schemes + "/BuildsCLI.xcscheme", atomically: true, encoding: .utf8)
        let launched = try await SchemeFixtures.schemes(of: try XcodeWorkspace.load(path: root + "/P.xcodeproj"), packages: packages, in: directory.path).map(\.name)
        #expect(!launched.contains("kit-cli"))
        let remote = """
        <RemoteRunnable runnableDebuggingMode = "1" BundleIdentifier = "org.nomac" RemotePath = "/kit-cli"></RemoteRunnable>
        <MacroExpansion><BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "kit-cli" \
        BuildableName = "kit-cli" BlueprintName = "kit-cli" ReferencedContainer = "container:"></BuildableReference></MacroExpansion>
        </LaunchAction>
        """
        try building.replacingOccurrences(of: "</LaunchAction>", with: remote).write(toFile: schemes + "/BuildsCLI.xcscheme", atomically: true, encoding: .utf8)
        let expanded = try await SchemeFixtures.schemes(of: try XcodeWorkspace.load(path: root + "/P.xcodeproj"), packages: packages, in: directory.path).map(\.name)
        #expect(!expanded.contains("kit-cli"))
    }

    @Test func aMissingSchemeFailsAsXcodebuild() async throws {
        let directory = try TemporaryDirectory()
        let packages = try SchemeFixtures.write(at: directory.path + "/app")
        let workspace = try XcodeWorkspace.load(path: directory.path + "/app/P.xcodeproj")
        let schemes = try await SchemeFixtures.schemes(of: workspace, packages: packages, in: directory.path)
        #expect(throws: NomacError(#"The project named "P" does not contain a scheme named "Kit". The "-list" option can be used to find the names of the schemes in the project."#,
                                   exitStatus: 65)) {
            try XcodeWorkspace.scheme(named: "Kit", in: schemes, workspace: workspace)
        }
    }

    @Test func testPlansCountAsTested() async throws {
        let directory = try TemporaryDirectory()
        let root = directory.path + "/app"
        var packages = try SchemeFixtures.write(at: root)
        // Lib's shared scheme tests nothing; a test plan of a project scheme tests LibTests.
        let plan = #"{"configurations": [], "testTargets": [{"target": {"containerPath": "container:Lib", "identifier": "LibTests", "name": "LibTests"}}], "version": 1}"#
        try plan.write(toFile: root + "/All.xctestplan", atomically: true, encoding: .utf8)
        let both = root + "/P.xcodeproj/xcshareddata/xcschemes/Both.xcscheme"
        let text = try String(contentsOfFile: both, encoding: .utf8)
            .replacingOccurrences(of: "      <Testables>\n      </Testables>", with: "      <TestPlans>\n         <TestPlanReference reference = \"container:All.xctestplan\" default = \"YES\">\n         </TestPlanReference>\n      </TestPlans>")
        try text.write(toFile: both, atomically: true, encoding: .utf8)
        packages[2].testTargets.append(SwiftPackageContents.TestTarget(name: "LibMoreTests", dependencies: []))
        let names = try await SchemeFixtures.schemes(of: try XcodeWorkspace.load(path: root + "/P.xcodeproj"), packages: packages, in: directory.path).map(\.name)
        #expect(!names.contains("LibTests"))
        #expect(names.contains("LibMoreTests"))
    }
}

/// What `-showBuildSettings -scheme` prints or fails with for the experiment's schemes, through
/// Swift Build with a synthetic iOS developer directory.
@Suite struct PackageSchemeSettingsTests {
    @Test func reportsProjectTargetsOnlyAndFailsAsXcodebuild() async throws {
        let directory = try TemporaryDirectory()
        let packages = try SchemeFixtures.write(at: directory.path + "/app")
        try SchemeFixtures.scheme(build: [(SchemeFixtures.mac, "container:P.xcodeproj", true)])
            .write(toFile: directory.path + "/app/P.xcodeproj/xcshareddata/xcschemes/MacOnly.xcscheme", atomically: true, encoding: .utf8)
        try await SchemeFixtures.withInspector(of: try XcodeWorkspace.load(path: directory.path + "/app/P.xcodeproj"), packages: packages, in: directory.path) { inspector in
            func blocks(_ scheme: String) async throws -> [String] {
                try await inspector.blocks(.init(selection: .scheme(scheme), destination: "generic/platform=iOS")).map(\.target)
            }
            func status(_ scheme: String) async -> Int32? {
                do {
                    _ = try await inspector.blocks(.init(selection: .scheme(scheme), destination: "generic/platform=iOS"))
                    return nil
                } catch {
                    return (error as? NomacError)?.exitStatus
                }
            }
            // Package products build but print no block.
            #expect(try await blocks("AppAndKit") == ["App"])
            #expect(try await blocks("App") == ["App"])
            #expect(try await blocks("KitExtras") == [])
            #expect(try await blocks("kit-cli") == [])
            #expect(try await blocks("DepShared") == [])
            // Nothing built for running supports the destination.
            for scheme in ["TestingOnly", "AppTestsOnly", "KitTests", "LibTests", "LooseTests", "SoloTests", "MacOnly", "MacTool"] {
                #expect(await status(scheme) == 64, "\(scheme)")
            }
            // Nothing the scheme names exists.
            for scheme in ["GhostApp", "Broken", "Ghost"] {
                #expect(await status(scheme) == 66, "\(scheme)")
            }
            #expect(await status("Kit") == 65)
            do {
                _ = try await inspector.blocks(.init(selection: .scheme("MacOnly"), destination: "generic/platform=iOS"))
            } catch let error as NomacError {
                #expect(error.message == "Could not configure request to show build settings: Unable to find a destination matching the provided destination specifier:\n\t\t{ generic:1, platform:iOS }")
            }
        }
    }
}

@Suite struct BuildTargetsTests {
    /// A build configures what the scheme builds for running; package entries name their
    /// product's PIF target, which this fixture's PIF does not have.
    @Test func configuresTheSchemesTargetsAndReportsPackageEntriesWithoutAProductTarget() async throws {
        let directory = try TemporaryDirectory()
        let packages = try SchemeFixtures.write(at: directory.path + "/app")
        try await SchemeFixtures.withInspector(of: try XcodeWorkspace.load(path: directory.path + "/app/P.xcodeproj"), packages: packages, in: directory.path) { inspector in
            let app = try await inspector.resolve(.init(selection: .scheme("App"), destination: "generic/platform=iOS"))
            #expect(app.buildTargets.map(\.name) == ["App"])
            #expect(app.unconfiguredPackageEntries.isEmpty)
            let both = try await inspector.resolve(.init(selection: .scheme("AppAndKit"), destination: "generic/platform=iOS"))
            #expect(both.buildTargets.map(\.name) == ["App"])
            #expect(both.unconfiguredPackageEntries == ["Kit"])
            let target = try await inspector.resolve(.init(selection: .targets(["App"])))
            #expect(target.buildTargets.map(\.name) == ["App"])
        }
    }

    /// An archive builds what the scheme builds for archiving, for Swift Build's install action.
    @Test func archivesWhatTheSchemeBuildsForArchiving() async throws {
        let directory = try TemporaryDirectory()
        let packages = try SchemeFixtures.write(at: directory.path + "/app")
        try await SchemeFixtures.withInspector(of: try XcodeWorkspace.load(path: directory.path + "/app/P.xcodeproj"), packages: packages, in: directory.path) { inspector in
            let archive = try await inspector.resolve(.init(selection: .scheme("App"), configuration: "Release", destination: "generic/platform=iOS", action: .archive))
            #expect(archive.buildTargets.map(\.name) == ["App"])
            #expect(archive.request.action == "install")
            #expect(archive.request.configuration == "Release")
            // App's scheme is autocreated: it archives in the project's default configuration.
            let autocreated = try await inspector.resolve(.init(selection: .scheme("App"), destination: "generic/platform=iOS", action: .archive))
            #expect(autocreated.request.configuration == "Debug")
            // AppAndKit's scheme file has no Archive action: XcodeProj's default configuration.
            let shared = try await inspector.resolve(.init(selection: .scheme("AppAndKit"), destination: "generic/platform=iOS", action: .archive))
            #expect(shared.request.configuration == "Release")
            await #expect(throws: NomacError.self) { try await inspector.resolve(.init(selection: .targets(["App"]), action: .archive)) }
        }
    }
}

/// `xcodebuild -list` in the layout Xcode 27.0 printed for loader-experiments `schemes` and
/// `workspace` (this fixture's project has one configuration where the experiment's has two).
@Suite struct WorkspaceListingTests {
    static let schemes = ["App", "AppAndKit", "AppTestsOnly", "Both", "Broken", "DepShared", "Ghost", "GhostApp", "kit-cli", "KitExtras",
                          "KitTests", "Lib", "LibTests", "LooseTests", "MacTool", "Solo", "SoloTests", "TestingOnly"]

    @Test func listsAProjectAsXcodebuild() async throws {
        let directory = try TemporaryDirectory()
        let packages = try SchemeFixtures.write(at: directory.path + "/app")
        let workspace = try XcodeWorkspace.load(path: directory.path + "/app/P.xcodeproj")
        let listing = WorkspaceListing(workspace: workspace, schemes: try await SchemeFixtures.schemes(of: workspace, packages: packages, in: directory.path))
        #expect(listing.schemes == Self.schemes)
        #expect(listing.text == """
        Information about project "P":
            Targets:
                App
                AppTests
                MacTool

            Build Configurations:
                Debug

            If no build configuration is specified and -scheme is not passed then "Debug" is used.

            Schemes:
        \(Self.schemes.map { "        \($0)\n" }.joined())

        """)
        #expect(listing.json == """
        {
          "project" : {
            "configurations" : [
              "Debug"
            ],
            "name" : "P",
            "schemes" : [
        \(Self.schemes.map { "      \"\($0)\"" }.joined(separator: ",\n"))
            ],
            "targets" : [
              "App",
              "AppTests",
              "MacTool"
            ]
          }
        }

        """)
    }

    @Test func listsAWorkspaceAsXcodebuild() async throws {
        let directory = try TemporaryDirectory()
        let root = directory.path + "/app"
        let packages = try SchemeFixtures.write(at: root)
        try FileManager.default.createDirectory(atPath: root + "/W.xcworkspace", withIntermediateDirectories: true)
        try #"<?xml version="1.0" encoding="UTF-8"?><Workspace version = "1.0"><FileRef location = "group:P.xcodeproj"></FileRef></Workspace>"#
            .write(toFile: root + "/W.xcworkspace/contents.xcworkspacedata", atomically: true, encoding: .utf8)
        let workspace = try XcodeWorkspace.load(path: root + "/W.xcworkspace")
        let listing = WorkspaceListing(workspace: workspace, schemes: try await SchemeFixtures.schemes(of: workspace, packages: packages, in: directory.path))
        #expect(listing.text == "Information about workspace \"W\":\n    Schemes:\n" + Self.schemes.map { "        \($0)\n" }.joined() + "\n")
        #expect(listing.json == "{\n  \"workspace\" : {\n    \"name\" : \"W\",\n    \"schemes\" : [\n"
            + Self.schemes.map { "      \"\($0)\"" }.joined(separator: ",\n") + "\n    ]\n  }\n}\n")
    }
}
