import Foundation
@testable import NomacDeviceTest
import NomacPlist
import Testing

/// The `.xctestrun` of coverage and test plans, against what Xcode 27.0 wrote for
/// `xctest_experiments.py`'s project (`xctestrun-coverage-*`, `-plan-*`, `-autocreated-plan*`).
@Suite struct XCTestPlanTests {
    func plan(_ json: String, name: String = "App", isDefault: Bool = true) throws -> XCTestPlan {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("xctestplan-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let path = folder + "/\(name).xctestplan"
        try Data(json.utf8).write(to: URL(fileURLWithPath: path))
        return try XCTestPlan(path: path, isDefault: isDefault)
    }

    static let targets = """
    "testTargets": [{"target": {"containerPath": "container:App.xcodeproj", "identifier": "T1", "name": "AppTests"}},
                    {"target": {"containerPath": "container:App.xcodeproj", "identifier": "T2", "name": "AppUITests"}}], "version": 1
    """

    func document(defaults: String = "{}", configurations: String = #"[{"id": "11111111-2222-3333-4444-555555555555", "name": "Configuration 1", "options": {}}]"#) -> String {
        #"{"configurations": \#(configurations), "defaultOptions": \#(defaults), \#(Self.targets)}"#
    }

    func dictionary(_ value: PropertyListValue) -> [String: PropertyListValue] {
        if case .dictionary(let fields) = value { fields } else { [:] }
    }

    func entries(_ build: TestBuildDescription, _ plan: XCTestPlan) -> [[String: PropertyListValue]] {
        guard case .array(let configurations)? = dictionary(XCTestRunWriter.value(build, plan: plan))["TestConfigurations"],
              case .array(let targets)? = dictionary(configurations[0])["TestTargets"] else { return [] }
        return targets.map(dictionary)
    }

    @Test func aFileForEachPlanNamedByIt() throws {
        var build = XCTestRunTests.build
        build.plans = [try plan(document()), try plan(document(), name: "Other", isDefault: false)]
        #expect(XCTestRunWriter.files(build).map(\.name) == ["App_App_iphoneos27.0-arm64.xctestrun", "App_Other_iphoneos27.0-arm64.xctestrun"])
        let top = dictionary(XCTestRunWriter.value(build, plan: build.plans[1]))
        #expect(top["TestPlan"] == .dictionary(["IsDefault": .boolean(false), "Name": .string("Other")]))
        #expect(top["__xctestrun_metadata__"] == .dictionary(["FormatVersion": .integer(2)]))
        #expect(top["ContainerInfo"] == .dictionary(["ContainerName": .string("App"), "SchemeName": .string("App")]))
    }

    /// `xctestrun-test-plan` against the base file: no `RunOrder` or `TestInteropMode`, the plan's
    /// name for the test and the app it drives.
    @Test func aPlansEntriesDifferFromTheSchemesThisWay() throws {
        var build = XCTestRunTests.build
        build.coverage = []
        let plan = try plan(document(defaults: #"{"codeCoverage": false, "environmentVariableEntries": [{"key": "PLAN_VARIABLE", "value": "1"}]}"#))
        let targets = entries(build, plan)
        #expect(targets.map { $0["BlueprintName"] } == [.string("AppTests"), .string("AppUITests")])
        for entry in targets {
            #expect(entry["RunOrder"] == nil && entry["TestInteropMode"] == nil && entry["ClangProfileDataDirectoryPath"] == nil)
            #expect(dictionary(entry["TestingEnvironmentVariables"]!)["XCODE_TEST_PLAN_NAME"] == .string("App"))
            #expect(dictionary(entry["EnvironmentVariables"]!)["PLAN_VARIABLE"] == .string("1"))
        }
        #expect(dictionary(targets[1]["UITargetAppEnvironmentVariables"]!)["XCODE_TEST_PLAN_NAME"] == .string("App"))
    }

    /// `xctestrun-plan-launch-env`: the scheme's arguments and variables stay out of a plan's file.
    @Test func theSchemesVariablesDoNotJoinAPlans() throws {
        var build = XCTestRunTests.build
        build.arguments = ["-Scheme"]
        build.environment = ["SCHEME": "1"]
        let entry = entries(build, try plan(document(defaults: #"{"codeCoverage": false}"#)))[0]
        #expect(entry["CommandLineArguments"] == .array([]))
        #expect(dictionary(entry["EnvironmentVariables"]!)["SCHEME"] == nil)
    }

    /// `xctestrun-plan-configurations` and `-config-overrides`: a configuration's option replaces the
    /// default's whole, disabled entries stay out, and others come from the defaults.
    @Test func configurationOptionsReplaceDefaultsKeyByKey() throws {
        let plan = try plan(document(defaults: #"{"defaultTestExecutionTimeAllowance": 100, "environmentVariableEntries": [{"key": "SHARED", "value": "default"}], "language": "fr"}"#,
                                     configurations: #"""
        [{"id": "11111111-2222-3333-4444-555555555555", "name": "One", "options": {"language": "de", "region": "DE",
          "environmentVariableEntries": [{"key": "ONE", "value": "1"}, {"key": "OFF", "value": "1", "enabled": false}],
          "commandLineArgumentEntries": [{"argument": "-One"}, {"argument": "-Off", "enabled": false}], "defaultTestExecutionTimeAllowance": 200}},
         {"id": "11111111-2222-3333-4444-555555555556", "name": "Two", "options": {}}]
        """#))
        #expect(plan.configurations.map(\.name) == ["One", "Two"])
        var one: [String: PropertyListValue] = ["EnvironmentVariables": .dictionary([:]), "UITargetAppCommandLineArguments": .array([])]
        XCTestRunWriter.apply(plan.configurations[0].options, to: &one)
        #expect(one["EnvironmentVariables"] == .dictionary(["ONE": .string("1")]))
        let localization = ["-AppleLanguages", "(de)", "-AppleTextDirection", "NO", "-AppleLocale", "de_DE"]
        #expect(one["CommandLineArguments"] == .array((["-One"] + localization).map { .string($0) }))
        #expect(one["UITargetAppCommandLineArguments"] == .array(localization.map { .string($0) }))
        #expect(one["TestLanguage"] == .string("de") && one["TestRegion"] == .string("DE"))
        #expect(one["DefaultTestExecutionTimeAllowance"] == .integer(200))
        var two: [String: PropertyListValue] = ["EnvironmentVariables": .dictionary([:])]
        XCTestRunWriter.apply(plan.configurations[1].options, to: &two)
        #expect(two["EnvironmentVariables"] == .dictionary(["SHARED": .string("default")]))
        #expect(two["CommandLineArguments"] == .array(["-AppleLanguages", "(fr)", "-AppleTextDirection", "NO"].map { .string($0) }))
        #expect(two["DefaultTestExecutionTimeAllowance"] == .integer(100))
    }

    /// `xctestrun-plan-languages`.
    @Test(arguments: [
        ("IDELaunchSchemeLanguageRLO", nil, ["-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES", "-NSForceRightToLeftLocalizedStrings", "YES"]),
        ("IDELaunchSchemeLanguageDoubleLocalizedStrings", nil, ["-NSDoubleLocalizedStrings", "YES"]),
        ("IDELaunchSchemeLanguageAccentedPseudolanguage", nil, ["-AppleLanguages", "(IDELaunchSchemeLanguageAccentedPseudolanguage)", "-AppleTextDirection", "NO"]),
        ("ar", "AE", ["-AppleLanguages", "(ar)", "-AppleTextDirection", "YES", "-AppleLocale", "ar_AE"]),
        (nil, "GB", ["-AppleLocale", "en_GB"]),
        ("zh-Hans", "CN", ["-AppleLanguages", "(zh-Hans)", "-AppleTextDirection", "NO", "-AppleLocale", "zh-Hans_CN"]),
    ] as [(String?, String?, [String])])
    func languageArguments(language: String?, region: String?, expected: [String]) {
        #expect(XCTestRunWriter.languageArguments(language: language, region: region) == expected)
    }

    /// `xctestrun-plan-options` and `-never`.
    @Test func optionsWithAKeyOfTheirOwn() throws {
        let plan = try plan(document(defaults: #"""
        {"testTimeoutsEnabled": true, "defaultTestExecutionTimeAllowance": 300, "maximumTestExecutionTimeAllowance": 900, "testExecutionOrdering": "random",
         "testRepetitionMode": "retryOnFailure", "maximumTestRepetitions": 3, "mainThreadCheckerEnabled": false, "userAttachmentLifetime": "keepAlways",
         "uiTestingScreenshotsLifetime": "keepAlways", "diagnosticCollectionPolicy": "Always", "preferredScreenCaptureFormat": "screenshots",
         "performanceAntipatternCheckerEnabled": true, "locationScenario": {"identifier": "London, England", "referenceType": "built-in"}}
        """#))
        var entry: [String: PropertyListValue] = [:]
        XCTestRunWriter.apply(plan.configurations[0].options, to: &entry)
        #expect(entry == [
            "CommandLineArguments": .array([]),
            "DefaultTestExecutionTimeAllowance": .integer(300),
            "DiagnosticCollectionPolicy": .integer(2),
            "MaximumTestExecutionTimeAllowance": .integer(900),
            "PreferredScreenCaptureFormat": .string("screenshots"),
            "SystemAttachmentLifetime": .string("keepAlways"),
            "TestExecutionOrdering": .string("random"),
            "TestRepetitionPolicy": .dictionary(["XCTMaximumIterations": .integer(3), "XCTRepeatInNewRunnerProcess": .boolean(false), "XCTRepetitionMode": .integer(2)]),
            "TestTimeoutsEnabled": .boolean(true),
            "UserAttachmentLifetime": .string("keepAlways"),
        ])
        var never: [String: PropertyListValue] = [:]
        XCTestRunWriter.apply(try self.plan(document(defaults: #"{"diagnosticCollectionPolicy": "Never", "maximumTestExecutionTimeAllowance": null}"#)).configurations[0].options, to: &never)
        #expect(never["DiagnosticCollectionPolicy"] == .integer(0) && never["MaximumTestExecutionTimeAllowance"] == nil)
    }

    /// `xctestrun-plan-target-fields`, `-target-disabled`, `-order`.
    @Test func targetFieldsAndOrder() throws {
        let plan = try plan(#"""
        {"configurations": [{"id": "11111111-2222-3333-4444-555555555555", "name": "C", "options": {}}], "defaultOptions": {"codeCoverage": false}, "testTargets": [
          {"selectedTests": ["AppUITests/testIncrement"], "target": {"identifier": "T2", "name": "AppUITests"}},
          {"parallelizable": true, "skippedTests": ["CounterTests/testNext"], "target": {"identifier": "T1", "name": "AppTests"}}], "version": 1}
        """#)
        let targets = entries(XCTestRunTests.build, plan)
        #expect(targets.map { $0["BlueprintName"] } == [.string("AppUITests"), .string("AppTests")])
        #expect(targets[0]["OnlyTestIdentifiers"] == .array([.string("AppUITests/testIncrement")]))
        #expect(targets[1]["ParallelizationEnabled"] == .boolean(true))
        #expect(targets[1]["SkipTestIdentifiers"] == .array([.string("CounterTests/testNext")]))
        let disabled = try self.plan(#"""
        {"configurations": [{"id": "11111111-2222-3333-4444-555555555555", "name": "C", "options": {}}], "defaultOptions": {"codeCoverage": false}, "testTargets": [
          {"enabled": false, "target": {"identifier": "T2", "name": "AppUITests"}}, {"target": {"identifier": "T1", "name": "AppTests"}}], "version": 1}
        """#)
        #expect(entries(XCTestRunTests.build, disabled).map { $0["BlueprintName"] } == [.string("AppTests")])
    }

    /// `xctestrun-autocreated-plan` and `-env`.
    @Test func anAutocreatedPlanCarriesTheSchemesArgumentsAndGathersCoverage() {
        var build = XCTestRunTests.build
        let plan = XCTestPlan(autocreatedFor: "App", testables: [.init(name: "AppTests", identifier: "T1"), .init(name: "AppUITests", identifier: "T2")],
                              arguments: ["-TestArgument"], environment: ["TEST_VARIABLE": "1"])
        build.coverage = [.init(identifier: "A", name: "App.app", binaryPath: "Debug-iphoneos/App.app/App", isStatic: false, sources: ["/s/a.swift"])]
        build.plans = [plan]
        #expect(XCTestRunWriter.files(build).map(\.name) == ["App_App_iphoneos27.0-arm64.xctestrun"])
        let top = dictionary(XCTestRunWriter.value(build, plan: plan))
        guard case .array(let configurations)? = top["TestConfigurations"] else { return #expect(Bool(false)) }
        #expect(dictionary(configurations[0])["Name"] == .string("Test Scheme Action"))
        #expect(top["CodeCoverageBuildableInfos"] != nil)
        let entry = entries(build, plan)[0]
        #expect(entry["TestInteropMode"] == .string("complete"))
        #expect(entry["CommandLineArguments"] == .array([.string("-TestArgument")]))
        #expect(dictionary(entry["EnvironmentVariables"]!)["TEST_VARIABLE"] == .string("1"))
        #expect(entry["ClangProfileDataDirectoryPath"] == .string("__DERIVEDDATA__/Build/ProfileData"))
    }

    @Test func aSanitizerOrAnUnknownOptionStopsWithItsName() throws {
        #expect(throws: (any Error).self) { try plan(document(configurations: #"[{"id": "11111111-2222-3333-4444-555555555555", "name": "C", "options": {"addressSanitizer": {"enabled": true}}}]"#)) }
        #expect(throws: (any Error).self) { try plan(document(defaults: #"{"testRepetitionMode": "fixedIterations"}"#)) }
    }

    @Test func coverageOfAPlan() throws {
        #expect(try plan(document()).coverage == .all)
        #expect(try plan(document(defaults: #"{"codeCoverage": true}"#)).coverage == .all)
        #expect(try plan(document(defaults: #"{"codeCoverage": false}"#)).coverage == .off)
        #expect(try plan(document(defaults: #"{"codeCoverage": {"targets": [{"identifier": "A", "name": "App"}]}}"#)).coverage == .targets(["A"]))
    }

    /// `xctestrun-plan-expansion` and `-no-expansion`.
    @Test func variablesExpandOnlyWithATargetForThem() async throws {
        let expanding = try plan(document(defaults: #"{"targetForVariableExpansion": {"identifier": "A", "name": "App"}, "environmentVariableEntries": [{"key": "E", "value": "$(PRODUCT_NAME)"}], "commandLineArgumentEntries": [{"argument": "-Name $(PRODUCT_NAME)"}]}"#))
        let expanded = try await expanding.expandingVariables { text, target in text.replacingOccurrences(of: "$(PRODUCT_NAME)", with: "App-\(target)") }
        var entry: [String: PropertyListValue] = ["EnvironmentVariables": .dictionary([:])]
        XCTestRunWriter.apply(expanded.configurations[0].options, to: &entry)
        #expect(entry["EnvironmentVariables"] == .dictionary(["E": .string("App-A")]))
        #expect(entry["CommandLineArguments"] == .array([.string("-Name App-A")]))
        let plain = try plan(document(defaults: #"{"environmentVariableEntries": [{"key": "E", "value": "$(PRODUCT_NAME)"}]}"#))
        let unchanged = try await plain.expandingVariables { _, _ in "changed" }
        var other: [String: PropertyListValue] = ["EnvironmentVariables": .dictionary([:])]
        XCTestRunWriter.apply(unchanged.configurations[0].options, to: &other)
        #expect(other["EnvironmentVariables"] == .dictionary(["E": .string("$(PRODUCT_NAME)")]))
    }
}

/// `CodeCoverageBuildableInfos` as `xctestrun-coverage-*` shows it.
@Suite struct CoverageInformationTests {
    @Test func sortedByNameWithTheObservedFields() {
        var build = XCTestRunTests.build
        build.coverage = [
            .init(identifier: "S", name: "libStat.a", binaryPath: "Debug-iphoneos/libStat.a", isStatic: true, sources: ["/w/Stat/Stat.swift"]),
            .init(identifier: "A", name: "App.app", binaryPath: "Debug-iphoneos/App.app/App", isStatic: false, sources: ["/w/App/Zed.swift", "/w/App/Views/Screen.swift", "/w/App/Counter.swift", "/w/App/apple.swift"]),
            .init(identifier: "B", name: "Stat.bundle", binaryPath: "Debug-iphoneos/Stat.bundle/Stat", isStatic: false, sources: []),
        ]
        build.coverageReportTargets = ["A"]
        let top = XCTestRunWriter.value(build)
        let plural = XCTestRunWriter.coverageInformation(build, reported: nil, plural: true)
        if case .array(let lists) = plural, case .dictionary(let first) = lists[0] {
            #expect(first["Architectures"] == .array([.string("arm64")]) && first["Architecture"] == nil)
            #expect(first["ProductPaths"] == .array([.string("__TESTROOT__/Debug-iphoneos/App.app/App")]) && first["ProductPath"] == nil)
        }
        guard case .dictionary(let fields) = top, case .dictionary(let metadata)? = fields["__xctestrun_metadata__"],
              case .array(let infos)? = metadata["CodeCoverageBuildableInfos"] else { return #expect(Bool(false)) }
        #expect(metadata["FormatVersion"] == .integer(1))
        func info(_ index: Int) -> [String: PropertyListValue] { if case .dictionary(let values) = infos[index] { values } else { [:] } }
        #expect(info(0) == [
            "Architecture": .string("arm64"), "BuildableIdentifier": .string("A:primary"), "IncludeInReport": .boolean(true), "IsStatic": .boolean(false), "Name": .string("App.app"),
            "ProductPath": .string("__TESTROOT__/Debug-iphoneos/App.app/App"), "SourceFiles": .array(["Counter.swift", "Views/Screen.swift", "Zed.swift", "apple.swift"].map { .string($0) }),
            "SourceFilesCommonPathPrefix": .string("/w/App/"), "Toolchains": .array([.string("com.apple.dt.toolchain.XcodeDefault")]),
        ])
        #expect(info(1)["Name"] == .string("Stat.bundle") && info(1)["SourceFiles"] == .array([]) && info(1)["SourceFilesCommonPathPrefix"] == nil && info(1)["IncludeInReport"] == .boolean(false))
        #expect(info(2)["Name"] == .string("libStat.a") && info(2)["IsStatic"] == .boolean(true) && info(2)["SourceFiles"] == .array([.string("/w/Stat/Stat.swift")]) && info(2)["SourceFilesCommonPathPrefix"] == nil)
        if case .dictionary(let entry)? = fields["AppTests"] { #expect(entry["ClangProfileDataDirectoryPath"] == .string("__DERIVEDDATA__/Build/ProfileData")) }
    }

    /// `xctestrun-coverage-prefix`: `CounterMore.swift` and `CounterTests.swift` share a folder, not `Counter`.
    @Test func thePrefixIsAFolder() {
        #expect(XCTestRunWriter.sourceFiles(["/w/T/CounterTests.swift", "/w/T/CounterMore.swift"]).prefix == "/w/T/")
        #expect(XCTestRunWriter.sourceFiles(["/w/T/CounterTests.swift", "/w/T/CounterMore.swift"]).relative == ["CounterMore.swift", "CounterTests.swift"])
        #expect(XCTestRunWriter.sourceFiles(["/w/T/Sub/Deep/Others.swift", "/w/T/Sub/More.swift", "/w/T/Counter.swift"]).relative == ["Counter.swift", "Sub/Deep/Others.swift", "Sub/More.swift"])
        #expect(XCTestRunWriter.sourceFiles(["/a/one.swift", "/b/two.swift"]).prefix == "/")
    }
}
