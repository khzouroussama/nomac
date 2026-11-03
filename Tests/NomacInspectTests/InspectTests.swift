import Foundation
import Testing
import NomacBuildService
import NomacCore
import NomacProject
import NomacTestSupport
import NomacVerify
@testable import NomacInspect

@Suite struct DerivedDataTests {
    /// Folder names observed in Xcode 27.0's -showBuildSettings for retro-rampage and tofu.
    @Test func folderHashMatchesXcode() {
        #expect(DerivedData.folderHash("/Users/runner/work/_temp/nomac-corpus/retro-rampage/Source/Rampage.xcodeproj") == "cbdyreovfumezygpxosxersinwuz")
        #expect(DerivedData.folderHash("/Users/runner/work/_temp/nomac-corpus/tofu/Tofu.xcodeproj") == "bsgkytiblhgllkemmihwvpjynehg")
    }

    @Test func defaultAndCustomArenas() {
        let defaultArena = DerivedData.locations(name: "Tofu", containerPath: "/Users/runner/work/_temp/nomac-corpus/tofu/Tofu.xcodeproj", home: "/Users/runner", customRoot: nil)
        #expect(defaultArena.derivedDataPath == "/Users/runner/Library/Developer/Xcode/DerivedData")
        #expect(defaultArena.buildProductsPath == "/Users/runner/Library/Developer/Xcode/DerivedData/Tofu-bsgkytiblhgllkemmihwvpjynehg/Build/Products")
        #expect(defaultArena.pchPath == "/Users/runner/Library/Developer/Xcode/DerivedData/Tofu-bsgkytiblhgllkemmihwvpjynehg/Build/Intermediates.noindex/PrecompiledHeaders")
        let custom = DerivedData.locations(name: "Tofu", containerPath: "/x/Tofu.xcodeproj", home: "/h", customRoot: "/dd")
        #expect(custom.derivedDataPath == "/dd")
        #expect(custom.buildIntermediatesPath == "/dd/Build/Intermediates.noindex")
    }

    @Test func genericIOSDestination() throws {
        let destination = try DestinationSpecifier.parse("generic/platform=iOS")
        #expect(destination.targetArchitecture == "undefined_arch")
        #expect(destination.disableOnlyActiveArch)
        #expect(throws: NomacError.self) { try DestinationSpecifier.parse("platform=iOS Simulator,name=iPhone 17") }
    }
}

@Suite struct ReferenceArgumentTests {
    /// nomac's blocks in Xcode's order when only the blocks of unordered targets moved; none when
    /// another block moved or the targets differ.
    @Test func reordersOnlyUnorderedBlocks() {
        func blocks(_ targets: [String]) -> [ShowBuildSettings.Block] { targets.map { ShowBuildSettings.Block(action: "build", target: $0, settings: [:]) } }
        let unordered: Set<String> = ["A", "B"]
        #expect(ReferenceVerifier.reordered(blocks(["Ext", "A", "B"]), like: ["Ext", "B", "A"], unordered: unordered)?.map(\.target) == ["Ext", "B", "A"])
        #expect(ReferenceVerifier.reordered(blocks(["Ext", "A", "B"]), like: ["Ext", "A", "B"], unordered: unordered) == nil)
        #expect(ReferenceVerifier.reordered(blocks(["Ext", "A", "B"]), like: ["A", "Ext", "B"], unordered: unordered) == nil)
        #expect(ReferenceVerifier.reordered(blocks(["Ext", "A"]), like: ["Ext", "B"], unordered: unordered) == nil)
    }

    @Test func mapsXcodebuildArguments() {
        #expect(ReferenceVerifier.parse([]) == .init(selection: .defaultTarget))
        #expect(ReferenceVerifier.parse(["-target", "App", "-configuration", "Debug"]) == .init(selection: .targets(["App"]), configuration: "Debug"))
        #expect(ReferenceVerifier.parse(["-scheme", "App", "-destination", "generic/platform=iOS"]) == .init(selection: .scheme("App"), destination: "generic/platform=iOS"))
        // A scheme without a destination resolves to the reference Mac itself: not reproducible.
        #expect(ReferenceVerifier.parse(["-scheme", "App"]) == nil)
        #expect(ReferenceVerifier.parse(["-sdk", "iphoneos"]) == nil)
    }
}

@Suite struct SchemeTests {
    static let fixture = Bundle.module.resourcePath! + "/Fixtures/Fixture.xcodeproj"

    @Test func readsSharedSchemes() async throws {
        let tmp = try TemporaryDirectory()
        let workspace = try XcodeWorkspace.load(path: Self.fixture)
        let schemes = try await SchemeFixtures.schemes(of: workspace, in: tmp.path)
        // App is shared and launches App; Kit is built by no scheme, so it is autocreated;
        // AppTests is built by App's scheme.
        #expect(schemes.map(\.name) == ["App", "Kit"])
        #expect(schemes[1].isAutocreated)
        let app = schemes[0]
        #expect(!app.isAutocreated)
        #expect(app.launchConfiguration == "Release")
        #expect(app.archiveConfiguration == "Release")
        #expect(app.buildEntries.map(\.targetName) == ["App", "AppTests"])
        #expect(app.buildEntries[0].containerPath == FileSystem.absolute(Self.fixture))
        #expect(app.buildEntries[0].buildFor == ["running", "testing", "profiling", "archiving", "analyzing"])
        #expect(app.buildEntries[1].buildFor == ["testing"])
        #expect(app.runs.map(\.targetName) == ["App", "App"])
        #expect(throws: NomacError.self) { try XcodeWorkspace.scheme(named: "Missing", in: schemes, workspace: workspace) }
    }

    /// The Test action's configuration, and the arguments and variables tests get: the Launch
    /// action's when the Test action uses them, else its own, the enabled ones only
    /// (`xctest_experiments.py` `xctestrun-test-env`, `xctestrun-launch-env`).
    @Test func readsTheTestActionsArgumentsAndEnvironment() async throws {
        let tmp = try TemporaryDirectory()
        let project = tmp.path + "/Fixture.xcodeproj"
        try FileManager.default.copyItem(atPath: Self.fixture, toPath: project)
        let file = project + "/xcshareddata/xcschemes/App.xcscheme"
        let original = try String(contentsOfFile: file, encoding: .utf8)
        let launch = """
              <CommandLineArguments><CommandLineArgument argument = "-Launch" isEnabled = "YES"/></CommandLineArguments>
              <EnvironmentVariables><EnvironmentVariable key = "LAUNCH" value = "1" isEnabled = "YES"/></EnvironmentVariables>
           </LaunchAction>
        """
        let shared = original.replacingOccurrences(of: "   </LaunchAction>", with: launch)
        try shared.write(toFile: file, atomically: true, encoding: .utf8)
        var schemes = try await SchemeFixtures.schemes(of: try XcodeWorkspace.load(path: project), in: tmp.path + "/a")
        #expect(schemes[0].testConfiguration == "Debug")
        #expect(schemes[0].testArguments == ["-Launch"])
        #expect(schemes[0].testEnvironment == ["LAUNCH": "1"])

        let own = shared.replacingOccurrences(of: "      shouldUseLaunchSchemeArgsEnv = \"YES\">\n   </TestAction>", with: """
              shouldUseLaunchSchemeArgsEnv = "NO">
              <CommandLineArguments><CommandLineArgument argument = "-Test" isEnabled = "YES"/><CommandLineArgument argument = "-Off" isEnabled = "NO"/></CommandLineArguments>
              <EnvironmentVariables><EnvironmentVariable key = "TEST" value = "2" isEnabled = "YES"/><EnvironmentVariable key = "OFF" value = "3" isEnabled = "NO"/></EnvironmentVariables>
           </TestAction>
        """).replacingOccurrences(of: "<TestAction\n      buildConfiguration = \"Debug\"", with: "<TestAction\n      buildConfiguration = \"Release\"")
        try own.write(toFile: file, atomically: true, encoding: .utf8)
        schemes = try await SchemeFixtures.schemes(of: try XcodeWorkspace.load(path: project), in: tmp.path + "/b")
        #expect(schemes[0].testConfiguration == "Release")
        #expect(schemes[0].testArguments == ["-Test"])
        #expect(schemes[0].testEnvironment == ["TEST": "2"])
    }

    @Test func autocreatesOneSchemePerNonTestTarget() async throws {
        let tmp = try TemporaryDirectory()
        let copy = tmp.path + "/Fixture.xcodeproj"
        try FileManager.default.createDirectory(atPath: copy, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: Self.fixture + "/project.pbxproj", toPath: copy + "/project.pbxproj")
        let schemes = try await SchemeFixtures.schemes(of: try XcodeWorkspace.load(path: copy), in: tmp.path)
        #expect(schemes.map(\.name) == ["App", "Kit"])
        #expect(schemes.allSatisfy { $0.isAutocreated && $0.launchConfiguration == "Debug" && $0.archiveConfiguration == "Release" })
        // AppTests depends on App and names it as its TestTargetID and test host, so App's
        // autocreated scheme tests it (tofu).
        #expect(schemes[0].testables.map(\.targetName) == ["AppTests"])
        #expect(schemes[1].testables.isEmpty)
        // An autocreated scheme gathers coverage when it tests something (tofu; retro-rampage's Renderer).
        #expect(schemes.map(\.codeCoverageEnabled) == [true, false])
    }

    @Test func coverageSettingsAreSynthesizedForSchemesWithTestables() async throws {
        let tmp = try TemporaryDirectory()
        let copy = tmp.path + "/Fixture.xcodeproj"
        try FileManager.default.createDirectory(atPath: copy, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: Self.fixture + "/project.pbxproj", toPath: copy + "/project.pbxproj")
        let developer = try SyntheticDeveloperDirectory.create(at: tmp.path + "/xcode")
        var host = HostIdentity.current()
        host.homeDirectory = "/home/tester"
        let (app, kit) = try await BuildSettingsInspector.with(workspace: try XcodeWorkspace.load(path: copy), developerDirectory: developer, host: host,
                                                               scratchDirectory: tmp.path + "/scratch") { inspector in
            (try await inspector.blocks(.init(selection: .scheme("App"), destination: "generic/platform=iOS"))[0].dictionary,
             try await inspector.blocks(.init(selection: .scheme("Kit"), destination: "generic/platform=iOS"))[0].dictionary)
        }
        let folder = "/home/tester/Library/Developer/Xcode/DerivedData/Fixture-\(DerivedData.folderHash(copy))"
        #expect(app["CLANG_COVERAGE_MAPPING"] == "YES")
        #expect(app["CLANG_PROFILE_DATA_DIRECTORY"] == folder + "/Build/ProfileData")
        #expect(kit["CLANG_COVERAGE_MAPPING"] == nil)
    }

    @Test func schemeInvocationUsesTheSchemeTargetsAndArena() async throws {
        let tmp = try TemporaryDirectory()
        let developer = try SyntheticDeveloperDirectory.create(at: tmp.path + "/xcode")
        let workspace = try XcodeWorkspace.load(path: Self.fixture)
        var host = HostIdentity.current()
        host.homeDirectory = "/home/tester"
        let blocks = try await BuildSettingsInspector.with(workspace: workspace, developerDirectory: developer, host: host, scratchDirectory: tmp.path + "/scratch") {
            try await $0.blocks(.init(selection: .scheme("App"), destination: "generic/platform=iOS"))
        }
        #expect(blocks.map(\.target) == ["App"])
        let settings = blocks[0].dictionary
        #expect(settings["CONFIGURATION"] == "Release")
        #expect(settings["ONLY_ACTIVE_ARCH"] == "NO")
        let hash = DerivedData.folderHash(FileSystem.absolute(Self.fixture))
        #expect(settings["BUILD_DIR"] == "/home/tester/Library/Developer/Xcode/DerivedData/Fixture-\(hash)/Build/Products")
    }

    /// loader-experiments `workspace`: without a scheme, xcodebuild fails with 64.
    @Test func aWorkspaceNeedsAScheme() async throws {
        let tmp = try TemporaryDirectory()
        try FileManager.default.createDirectory(atPath: tmp.path + "/W.xcworkspace", withIntermediateDirectories: true)
        try #"<?xml version="1.0" encoding="UTF-8"?><Workspace version = "1.0"><FileRef location = "absolute:\#(Self.fixture)"></FileRef></Workspace>"#
            .write(toFile: tmp.path + "/W.xcworkspace/contents.xcworkspacedata", atomically: true, encoding: .utf8)
        let developer = try SyntheticDeveloperDirectory.create(at: tmp.path + "/xcode")
        try await BuildSettingsInspector.with(workspace: try XcodeWorkspace.load(path: tmp.path + "/W.xcworkspace"), developerDirectory: developer,
                                              host: HostIdentity.current(), scratchDirectory: tmp.path + "/scratch") { inspector in
            for selection in [BuildSettingsInspector.Selection.defaultTarget, .targets(["App"]), .allTargets] {
                do {
                    _ = try await inspector.blocks(.init(selection: selection))
                    Issue.record("\(selection) succeeded")
                } catch {
                    #expect((error as? NomacError)?.exitStatus == 64)
                }
            }
            let blocks = try await inspector.blocks(.init(selection: .scheme("App"), destination: "generic/platform=iOS"))
            #expect(blocks.map(\.target) == ["App"])
        }
    }

    /// loader-experiments `infoplist-macros` and `provisioning-style`: settings written with
    /// macros are evaluated by Swift Build for the PIF (flappy-fly-bird).
    @Test func settingsWithMacrosAreEvaluatedForThePIF() async throws {
        let tmp = try TemporaryDirectory()
        let copy = tmp.path + "/Fixture.xcodeproj"
        try FileManager.default.createDirectory(atPath: copy, withIntermediateDirectories: true)
        let text = try String(contentsOfFile: Self.fixture + "/project.pbxproj", encoding: .utf8)
        let edited = text.replacingOccurrences(of: "INFOPLIST_FILE = App/Info.plist;", with: "INFOPLIST_FILE = \"$(SRCROOT)/$(TARGET_NAME)/Info.plist\"; CODE_SIGN_STYLE = \"$(NOMAC_STYLE)\"; NOMAC_STYLE = Manual;")
        #expect(edited != text)
        try edited.write(toFile: copy + "/project.pbxproj", atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(atPath: tmp.path + "/App", withIntermediateDirectories: true)
        try #"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.nomac.evaluated</string></dict></plist>"#
            .write(toFile: tmp.path + "/App/Info.plist", atomically: true, encoding: .utf8)
        let developer = try SyntheticDeveloperDirectory.create(at: tmp.path + "/xcode")
        let pif = try await WorkspacePIF.generate(workspace: try XcodeWorkspace.load(path: copy), developerDirectory: developer, home: "/home/tester")
        let target = try #require(pif.document.objects.first { $0.type == "target" && $0.contents.objectValue?["name"] == .string("App") }?.contents.objectValue)
        let data = (target["provisioningSourceData"]?.arrayValue ?? []).compactMap(\.objectValue)
        #expect(!data.isEmpty)
        #expect(data.allSatisfy { $0["bundleIdentifierFromInfoPlist"] == .string("org.nomac.evaluated") && $0["provisioningStyle"] == .int(1) })
    }

    /// loader-experiments `infoplist-macros`, `provisioning-profile`: settings written with an SDK
    /// condition are evaluated for the target's SDK, and a provisioning profile makes a target
    /// without CODE_SIGN_STYLE manual (mastodon's `PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]`).
    @Test func conditionalSettingsAreEvaluatedForThePIF() async throws {
        let tmp = try TemporaryDirectory()
        let copy = tmp.path + "/Fixture.xcodeproj"
        try FileManager.default.createDirectory(atPath: copy, withIntermediateDirectories: true)
        let text = try String(contentsOfFile: Self.fixture + "/project.pbxproj", encoding: .utf8)
        let edited = text.replacingOccurrences(of: "INFOPLIST_FILE = App/Info.plist;", with: #""INFOPLIST_FILE[sdk=iphoneos*]" = Conditional/Info.plist; PROVISIONING_PROFILE_SPECIFIER = ""; "PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]" = "Some Profile";"#)
        #expect(edited != text)
        try edited.write(toFile: copy + "/project.pbxproj", atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(atPath: tmp.path + "/Conditional", withIntermediateDirectories: true)
        try #"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.nomac.conditional</string></dict></plist>"#
            .write(toFile: tmp.path + "/Conditional/Info.plist", atomically: true, encoding: .utf8)
        let developer = try SyntheticDeveloperDirectory.create(at: tmp.path + "/xcode")
        let pif = try await WorkspacePIF.generate(workspace: try XcodeWorkspace.load(path: copy), developerDirectory: developer, home: "/home/tester")
        let target = try #require(pif.document.objects.first { $0.type == "target" && $0.contents.objectValue?["name"] == .string("App") }?.contents.objectValue)
        let data = (target["provisioningSourceData"]?.arrayValue ?? []).compactMap(\.objectValue)
        #expect(!data.isEmpty)
        #expect(data.allSatisfy { $0["bundleIdentifierFromInfoPlist"] == .string("org.nomac.conditional") && $0["provisioningStyle"] == .int(1) })
    }

    /// loader-experiments `provisioning-defaults`: without CODE_SIGN_STYLE or the attribute, the
    /// style is Manual when some configuration of the target signs to run locally (`-`) or names
    /// a provisioning profile, whether or not that configuration sets the style.
    @Test func provisioningStyleFollowsSigningWhenNothingSetsIt() async throws {
        let tmp = try TemporaryDirectory()
        let copy = tmp.path + "/Fixture.xcodeproj"
        try FileManager.default.createDirectory(atPath: copy, withIntermediateDirectories: true)
        var text = try String(contentsOfFile: Self.fixture + "/project.pbxproj", encoding: .utf8)
        // Kit (05, 06) names a profile in Release only; AppTests (07, 08) signs to run locally in
        // Debug, which sets the style.
        for (configuration, settings) in [("05 /* Debug */", #"CODE_SIGN_IDENTITY = "Apple Development";"#),
                                          ("06 /* Release */", #"CODE_SIGN_IDENTITY = "Apple Development"; PROVISIONING_PROFILE_SPECIFIER = Profile;"#),
                                          ("07 /* Debug */", #"CODE_SIGN_IDENTITY = "-"; CODE_SIGN_STYLE = Automatic;"#),
                                          ("08 /* Release */", #"CODE_SIGN_IDENTITY = "Apple Development";"#)] {
            let opening = "AD00000000000000000000\(configuration) = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n"
            #expect(text.contains(opening))
            text = text.replacingOccurrences(of: opening, with: opening + "\t\t\t\t" + settings + "\n")
        }
        try text.write(toFile: copy + "/project.pbxproj", atomically: true, encoding: .utf8)
        let developer = try SyntheticDeveloperDirectory.create(at: tmp.path + "/xcode")
        let pif = try await WorkspacePIF.generate(workspace: try XcodeWorkspace.load(path: copy), developerDirectory: developer, home: "/home/tester")
        func isManual(_ name: String) throws -> [Bool] {
            let target = try #require(pif.document.objects.first { $0.type == "target" && $0.contents.objectValue?["name"] == .string(name) }?.contents.objectValue)
            return (target["provisioningSourceData"]?.arrayValue ?? []).map { $0.objectValue?["provisioningStyle"] == .int(1) }
        }
        #expect(try isManual("App") == [true, true])
        #expect(try isManual("Kit") == [true, true])
        #expect(try isManual("AppTests") == [false, true])
    }

    /// `nomac list` prints no setting the PIF's second generation evaluates: a macOS tool that
    /// sets no provisioning style, whose signing identity Swift Build evaluates for `nomac pif`,
    /// lists without a developer directory.
    @Test func listingNeedsNoDeveloperDirectoryForSigning() async throws {
        let tmp = try TemporaryDirectory()
        let project = """
        // !$*UTF8*$!
        {
        \tarchiveVersion = 1;
        \tobjectVersion = 77;
        \tobjects = {
        \t\tA1 = {isa = PBXFileReference; explicitFileType = compiled.mach-o.executable; path = Tool; sourceTree = BUILT_PRODUCTS_DIR; };
        \t\tG1 = {isa = PBXGroup; children = (A1, ); sourceTree = "<group>"; };
        \t\tT1 = {isa = PBXNativeTarget; buildConfigurationList = L1; buildPhases = ( ); name = Tool; productName = Tool; productReference = A1; productType = "com.apple.product-type.tool"; };
        \t\tC1 = {isa = XCBuildConfiguration; buildSettings = {PRODUCT_NAME = "$(TARGET_NAME)"; }; name = Debug; };
        \t\tC2 = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = macosx; }; name = Debug; };
        \t\tL1 = {isa = XCConfigurationList; buildConfigurations = (C1, ); defaultConfigurationName = Debug; };
        \t\tL2 = {isa = XCConfigurationList; buildConfigurations = (C2, ); defaultConfigurationName = Debug; };
        \t\tP1 = {isa = PBXProject; buildConfigurationList = L2; mainGroup = G1; projectDirPath = ""; projectRoot = ""; targets = (T1, ); };
        \t};
        \trootObject = P1;
        }
        """
        try FileSystem.write(Data(project.utf8), to: tmp.path + "/Tool.xcodeproj/project.pbxproj")
        let workspace = try XcodeWorkspace.load(path: tmp.path + "/Tool.xcodeproj")
        await #expect(throws: NomacError.self) { _ = try await WorkspacePIF.generate(workspace: workspace, developerDirectory: nil, home: "/home/tester") }
        let pif = try await WorkspacePIF.generate(workspace: workspace, developerDirectory: nil, home: "/home/tester", evaluatingSettings: false)
        let listing = WorkspaceListing(workspace: workspace, schemes: try workspace.schemes(packages: pif.sourcePackages.map(\.contents), userName: "me"))
        #expect(listing.json.contains("\"Tool\""))
    }

    @Test func allTargetsEndsWithTheFirstTargetAgain() async throws {
        let tmp = try TemporaryDirectory()
        let developer = try SyntheticDeveloperDirectory.create(at: tmp.path + "/xcode")
        let workspace = try XcodeWorkspace.load(path: Self.fixture)
        let blocks = try await BuildSettingsInspector.with(workspace: workspace, developerDirectory: developer, host: HostIdentity.current(), scratchDirectory: tmp.path + "/scratch") {
            try await $0.blocks(.init(selection: .allTargets))
        }
        let names = workspace.projects[0].project.targets.map(\.name)
        #expect(blocks.map(\.target) == names + [names[0]])
        #expect(blocks.first == blocks.last)
    }

    /// capture_reference.py keeps capture file names unique without case (`-2` after a taken
    /// name), because mattermost's scheme `React` in Debug and its scheme `React-debug` would
    /// share one file on a Mac's disk. Verify reads each capture under the name
    /// settings/index.json records, not one derived from its arguments.
    @Test func verifyReadsEachCaptureUnderItsRecordedName() async throws {
        let tmp = try TemporaryDirectory()
        let developer = try SyntheticDeveloperDirectory.create(at: tmp.path + "/xcode")
        let source = (Self.fixture as NSString).deletingLastPathComponent
        let reference = tmp.path + "/reference"
        try FileManager.default.createDirectory(atPath: reference + "/settings", withIntermediateDirectories: true)
        func write(_ text: String, _ name: String) throws {
            try text.write(toFile: reference + "/" + name, atomically: true, encoding: .utf8)
        }
        try write(#"{"id": "fixture", "container": "Fixture.xcodeproj"}"#, "app.json")
        try write(#"{"path": "\#(source)"}"#, "source.json")
        try write("""
            {"xcodeVersion": "27.0", "xcodeBuild": "27A266a", "developerDirectory": "\(developer)",
             "operatingSystemVersion": "27.0.1", "operatingSystemBuild": "27A1", "nativeArchitecture": "arm64",
             "userName": "tester", "groupName": "staff", "uid": 501, "gid": 20,
             "homeDirectory": "/home/tester", "environment": {}}
            """, "host.json")
        try write("""
            [{"name": "target-App-Debug", "arguments": ["-target", "App", "-configuration", "Debug"], "exitStatus": 0},
             {"name": "target-App-debug-2", "arguments": ["-target", "App", "-configuration", "Release"], "exitStatus": 0}]
            """, "settings/index.json")

        let host = try ReferenceHost.load(path: reference + "/host.json").identity(developerDirectory: developer)
        let (debug, release) = try await BuildSettingsInspector.with(workspace: try XcodeWorkspace.load(path: Self.fixture), developerDirectory: developer,
                                                                     host: host, scratchDirectory: tmp.path + "/expected") { inspector in
            (try await inspector.blocks(.init(selection: .targets(["App"]), configuration: "Debug")),
             try await inspector.blocks(.init(selection: .targets(["App"]), configuration: "Release")))
        }
        #expect(debug != release)
        try write(ShowBuildSettings.render(debug), "settings/target-App-Debug.txt")
        try write(ShowBuildSettings.render(release), "settings/target-App-debug-2.txt")
        try write(try ShowBuildSettings.renderJSON(release), "settings/target-App-debug-2.json")
        try write(#"{"exitStatus": 0}"#, "settings/target-App-debug-2.json.cmd")

        let report = try await ReferenceVerifier(referenceDirectory: reference, sourceRoot: source, developerDirectory: developer,
                                                 scratchDirectory: tmp.path + "/scratch").run()
        let settings = report.checks.filter { $0.kind == "settings" }
        #expect(settings.map(\.name) == ["target-App-Debug", "target-App-debug-2", "target-App-debug-2.json"])
        #expect(settings.map(\.status) == [.identical, .identical, .identical])
    }
}

@Suite struct MacHostSettingsTests {
    /// The reference Mac of the local captures (`host.json`).
    static func mac(architecture: String = "arm64") -> HostIdentity {
        HostIdentity(userName: "tester", groupName: "staff", uid: 501, gid: 20, homeDirectory: "/Users/tester", operatingSystemVersion: [27, 0, 1],
                     operatingSystemBuild: "26A434", nativeArchitecture: architecture, isMacOS: true, environment: [:])
    }

    /// What the reference Mac printed in every settings capture of the corpus, where Swift Build
    /// on Linux arm64 printed `linux`, `aarch64` and none of the others.
    @Test func offMacOSTheSettingsAreTheIdentitysMacs() {
        #expect(MacHostSettings.overrides(host: Self.mac(), onMacOS: false) == [
            "HOST_PLATFORM": "macosx", "NATIVE_ARCH": "arm64", "NATIVE_ARCH_ACTUAL": "arm64", "NATIVE_ARCH_32_BIT": "arm", "NATIVE_ARCH_64_BIT": "arm64",
            "MAC_OS_X_PRODUCT_BUILD_VERSION": "26A434", "MAC_OS_X_VERSION_ACTUAL": "270001", "MAC_OS_X_VERSION_MAJOR": "270000", "MAC_OS_X_VERSION_MINOR": "270000",
        ])
        #expect(MacHostSettings.overrides(host: Self.mac(), onMacOS: true).isEmpty)
        var catalina = Self.mac(architecture: "x86_64")
        catalina.operatingSystemVersion = [10, 15, 7]
        #expect(MacHostSettings.macOSVersionSettings(catalina)["MAC_OS_X_VERSION_MAJOR"] == "101500")
        #expect(MacHostSettings.macOSVersionSettings(catalina)["MAC_OS_X_VERSION_MINOR"] == "1507")
    }

    /// A Linux machine's own identity has no macOS version to report.
    @Test func aLinuxIdentityHasNoMacOSVersion() {
        var linux = Self.mac()
        linux.isMacOS = false
        linux.operatingSystemVersion = [6, 10, 14]
        linux.operatingSystemBuild = "6.10.14-linuxkit"
        #expect(MacHostSettings.overrides(host: linux, onMacOS: false) == [
            "HOST_PLATFORM": "macosx", "NATIVE_ARCH": "arm64", "NATIVE_ARCH_ACTUAL": "arm64", "NATIVE_ARCH_32_BIT": "arm", "NATIVE_ARCH_64_BIT": "arm64",
        ])
        #expect(MacHostSettings.buildOverrides(host: linux, onMacOS: false).isEmpty)
    }

    /// A build keeps the machine's host platform and architecture, for the host tools it builds,
    /// and takes the Mac's version (retro-rampage `Engine`'s Info.plist: `BuildMachineOSBuild`).
    @Test func buildsGetOnlyTheMacOSVersion() {
        #expect(MacHostSettings.buildOverrides(host: Self.mac(), onMacOS: false) == [
            "MAC_OS_X_PRODUCT_BUILD_VERSION": "26A434", "MAC_OS_X_VERSION_ACTUAL": "270001",
            "MAC_OS_X_VERSION_MAJOR": "270000", "MAC_OS_X_VERSION_MINOR": "270000",
        ])
        #expect(MacHostSettings.buildOverrides(host: Self.mac(), onMacOS: true).isEmpty)
    }

    /// Swift Build derives other settings from the overriding ones: `HOST_ARCH` is
    /// `$(NATIVE_ARCH_ACTUAL)`, so an Intel Mac's identity gives `x86_64` on any machine.
    @Test func derivedSettingsFollowTheOverrides() async throws {
        let tmp = try TemporaryDirectory()
        let developer = try SyntheticDeveloperDirectory.create(at: tmp.path + "/xcode")
        let pif = try await WorkspacePIF.generate(workspace: try XcodeWorkspace.load(path: SchemeTests.fixture), developerDirectory: developer, home: "/Users/tester")
        let pifPath = tmp.path + "/fixture.pif"
        try FileSystem.write(Data(pif.document.serialized().utf8), to: pifPath)
        let intel = Self.mac(architecture: "x86_64")
        let request = SettingsRequest(configuration: "Debug", synthesizedOverrides: MacHostSettings.overrides(host: intel, onMacOS: false))
        let settings = try await SwiftBuildEngine.withWorkspace(developerDirectory: developer, pifPath: pifPath, host: intel) { session in
            let app = try #require(try await session.targets().first { $0.name == "App" })
            return try await session.exportedBuildSettings(targetGUID: app.guid, request: request)
        }
        #expect(settings["HOST_PLATFORM"] == "macosx")
        #expect(settings["HOST_ARCH"] == "x86_64")
        #expect(settings["NATIVE_ARCH_32_BIT"] == "i386")
        #expect(settings["MAC_OS_X_VERSION_ACTUAL"] == "270001")
    }
}
