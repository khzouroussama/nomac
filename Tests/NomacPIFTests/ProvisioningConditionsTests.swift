import Foundation
import Testing
import NomacPIF
import NomacProject
import NomacTestSupport

/// loader-experiments `provisioning-conditions`, written again here: a target whose xcconfig
/// sets `CODE_SIGN_STYLE` both with and without an SDK condition.
@Suite struct ProvisioningConditionsTests {
    /// The provisioning style of the target whose base xcconfig is `files["Base.xcconfig"]`,
    /// once Swift Build has evaluated its settings and the values with macros in `expressions`,
    /// and the expressions the first generation asked for.
    func style(_ files: [String: String], settings: String = "", expressions: [String: String] = [:]) throws -> (PIFValue?, Set<String>) {
        let directory = try TemporaryDirectory()
        let project = LoaderRulesTests.project(settings: settings, objects: "\t\tB00000000000000000000001 = {isa = PBXFileReference; path = Base.xcconfig; sourceTree = \"<group>\"; };",
                                               groupChildren: "B00000000000000000000001, ")
            .replacingOccurrences(of: "F00000000000000000000007 = {isa = XCBuildConfiguration;", with: "F00000000000000000000007 = {isa = XCBuildConfiguration; baseConfigurationReference = B00000000000000000000001;")
        try LoaderRulesTests.write(files.merging(["P.xcodeproj/project.pbxproj": project]) { $1 }, to: directory.path)
        let workspace = try XcodeWorkspace.load(path: directory.path + "/P.xcodeproj")
        var first = PIFGenerator(workspace: workspace)
        _ = try first.generate()
        let query = TargetSettingsQuery(projectPath: workspace.projects[0].path, targetID: "C00000000000000000000001", configuration: "Debug")
        var generator = PIFGenerator(workspace: workspace, evaluatedSettings: [query: expressions.merging(["SDK_NAME": "iphoneos27.0"]) { $1 }])
        let data = try LoaderRulesTests.target(try generator.generate(), "App")["provisioningSourceData"]?.arrayValue?.first?.objectValue
        return (data?["provisioningStyle"], first.unevaluatedExpressions[query] ?? [])
    }

    /// A level's assignment for the target's SDK wins over its plain one, whatever their order;
    /// one for another SDK does not; a higher level's plain assignment wins over it.
    @Test func aMatchingConditionWinsWithinItsLevel() throws {
        #expect(try style(["Base.xcconfig": "CODE_SIGN_STYLE[sdk=iphoneos*] = Automatic\nCODE_SIGN_STYLE = Manual\n"]).0 == .int(0))
        #expect(try style(["Base.xcconfig": "CODE_SIGN_STYLE[sdk=iphoneos*] = Manual\nCODE_SIGN_STYLE = Automatic\n"]).0 == .int(1))
        #expect(try style(["Base.xcconfig": "CODE_SIGN_STYLE[sdk=macosx*] = Automatic\nCODE_SIGN_STYLE = Manual\n"]).0 == .int(1))
        #expect(try style(["Base.xcconfig": "CODE_SIGN_STYLE[sdk=iphoneos*] = Automatic\n"], settings: "CODE_SIGN_STYLE = Manual;").0 == .int(1))
    }

    /// An included file's assignments belong to the including level, and a chosen value with
    /// macros is evaluated for the target (home-assistant's Release xcconfig).
    @Test func theChosenValueIsEvaluated() throws {
        let files = ["Inner.xcconfig": "CODE_SIGN_STYLE = Manual\nCODE_SIGN_STYLE[sdk=iphoneos*] = $(NOMAC_STYLE_$(TARGET_NAME):default=Automatic)\n",
                     "Base.xcconfig": "#include \"Inner.xcconfig\"\nCODE_SIGN_STYLE = Manual\n"]
        let (style, expressions) = try style(files, expressions: ["$(NOMAC_STYLE_$(TARGET_NAME):default=Automatic)": "Automatic"])
        #expect(style == .int(0))
        #expect(expressions == ["$(NOMAC_STYLE_$(TARGET_NAME):default=Automatic)"])
    }

    @Test func readsConditionsOfEveryForm() {
        #expect(XCConfigFile.key("A[sdk=iphoneos*]")?.conditions == ["sdk": "iphoneos*"])
        #expect(XCConfigFile.key("A[sdk=iphoneos*][arch=arm64]")?.conditions == ["sdk": "iphoneos*", "arch": "arm64"])
        #expect(XCConfigFile.key("A[sdk=iphoneos*,arch=arm64]")?.conditions == ["sdk": "iphoneos*", "arch": "arm64"])
        #expect(XCConfigFile.key("A B") == nil)
    }
}
