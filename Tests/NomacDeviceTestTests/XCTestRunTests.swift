import Foundation
@testable import NomacDeviceTest
import NomacPlist
import Testing

/// The `.xctestrun` of `xctest_experiments.py`'s base project (an app, a hosted unit test, a UI
/// test), as Xcode 27.0 wrote it.
@Suite struct XCTestRunTests {
    static let build = TestBuildDescription(
        schemeName: "App", containerName: "App", projectName: "App", projectPath: "App.xcodeproj",
        products: [
            .init(name: "App", moduleName: "App", bundleIdentifier: "org.example.app", path: "Debug-iphoneos/App.app", executableName: "App", kind: .application),
            .init(name: "AppTests", moduleName: "AppTests", bundleIdentifier: "org.example.app.tests", path: "Debug-iphoneos/App.app/PlugIns/AppTests.xctest",
                  executableName: "AppTests", kind: .unitTest, hostPath: "Debug-iphoneos/App.app"),
            .init(name: "AppUITests", moduleName: "AppUITests", bundleIdentifier: "org.example.app.uitests",
                  path: "Debug-iphoneos/AppUITests-Runner.app/PlugIns/AppUITests.xctest", executableName: "AppUITests", kind: .uiTest,
                  targetApplicationPath: "Debug-iphoneos/App.app"),
        ],
        testables: ["AppTests", "AppUITests"], arguments: [], environment: [:], sdkName: "iphoneos27.0", architecture: "arm64")

    func entries() throws -> [String: PropertyListValue] {
        guard case .dictionary(let top) = XCTestRunWriter.value(Self.build) else { throw XCTestRunTestError.notADictionary }
        return top
    }

    enum XCTestRunTestError: Error { case notADictionary }

    @Test func fileName() {
        #expect(XCTestRunWriter.fileName(Self.build) == "App_iphoneos27.0-arm64.xctestrun")
    }

    @Test func hostedUnitTest() throws {
        guard case .dictionary(let entry)? = try entries()["AppTests"] else { Issue.record("no AppTests"); return }
        #expect(entry["TestBundlePath"] == .string("__TESTHOST__/PlugIns/AppTests.xctest"))
        #expect(entry["TestHostPath"] == .string("__TESTROOT__/Debug-iphoneos/App.app"))
        #expect(entry["TestHostBundleIdentifier"] == .string("org.example.app"))
        #expect(entry["IsAppHostedTestBundle"] == .boolean(true))
        #expect(entry["RunOrder"] == .integer(0))
        #expect(entry["DependentProductPaths"] == .array([
            "__TESTROOT__/Debug-iphoneos/App.app", "__TESTROOT__/Debug-iphoneos/App.app/PlugIns/AppTests.xctest",
            "__TESTROOT__/Debug-iphoneos/AppUITests-Runner.app", "__TESTROOT__/Debug-iphoneos/AppUITests-Runner.app/PlugIns/AppUITests.xctest",
        ].map { .string($0) }))
        #expect(entry["ProcessNamesForCrashReportCollection"] == .array([.string("App"), .string("AppUITests-Runner")]))
        guard case .dictionary(let testing)? = entry["TestingEnvironmentVariables"] else { Issue.record("no testing variables"); return }
        #expect(testing["DYLD_INSERT_LIBRARIES"] == .string("__TESTHOST__/Frameworks/libXCTestBundleInject.dylib:/usr/lib/libRPAC.dylib"))
        #expect(testing["XCInjectBundleInto"] == .string("unused"))
    }

    @Test func uiTestRunsInTheRunner() throws {
        guard case .dictionary(let entry)? = try entries()["AppUITests"] else { Issue.record("no AppUITests"); return }
        #expect(entry["TestHostBundleIdentifier"] == .string("org.example.app.uitests.xctrunner"))
        #expect(entry["TestHostPath"] == .string("__TESTROOT__/Debug-iphoneos/AppUITests-Runner.app"))
        #expect(entry["UITargetAppPath"] == .string("__TESTROOT__/Debug-iphoneos/App.app"))
        #expect(entry["IsAppHostedTestBundle"] == nil)
        #expect(entry["RunOrder"] == .integer(1))
    }

    @Test func unhostedUnitTestRunsInTheXctestAgent() throws {
        var build = Self.build
        build.products[1].path = "Debug-iphoneos/AppTests.xctest"
        build.products[1].hostPath = nil
        guard case .dictionary(let top) = XCTestRunWriter.value(build), case .dictionary(let entry)? = top["AppTests"] else { Issue.record("no AppTests"); return }
        #expect(entry["TestHostPath"] == .string("__PLATFORMS__/iPhoneOS.platform/Developer/Library/Xcode/Agents/xctest"))
        #expect(entry["TestBundlePath"] == .string("__TESTROOT__/Debug-iphoneos/AppTests.xctest"))
        #expect(entry["TestHostBundleIdentifier"] == nil)
    }

    /// Format 2: each enabled configuration's targets in turn, with what the plan selects.
    @Test func readsEveryConfigurationOfAPlan() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("xctestrun-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: folder) }
        func target(_ name: String, _ extra: [String: PropertyListValue] = [:]) -> PropertyListValue {
            .dictionary(["BlueprintName": .string(name), "TestHostBundleIdentifier": .string("org.example.app"), "TestBundlePath": .string("__TESTHOST__/PlugIns/\(name).xctest")].merging(extra) { $1 })
        }
        let file: PropertyListValue = .dictionary([
            "__xctestrun_metadata__": .dictionary(["FormatVersion": .integer(2)]),
            "TestConfigurations": .array([
                .dictionary(["IsEnabled": .boolean(true), "Name": .string("One"), "TestTargets": .array([
                    target("A", ["OnlyTestIdentifiers": .array([.string("C/test")]), "SkipTestIdentifiers": .array([.string("C/other")]), "TestRepetitionPolicy": .dictionary([:]), "ParallelizationEnabled": .boolean(true)]), target("B"),
                ])]),
                .dictionary(["IsEnabled": .boolean(false), "Name": .string("Off"), "TestTargets": .array([target("Z")])]),
                .dictionary(["IsEnabled": .boolean(true), "Name": .string("Two"), "TestTargets": .array([target("A")])]),
            ]),
        ])
        let path = folder + "/App_App_iphoneos27.0-arm64.xctestrun"
        try XMLPropertyList.data(file).write(to: URL(fileURLWithPath: path))
        let run = try XCTestRun(path: path)
        #expect(run.entries.map(\.name) == ["A", "B", "A"])
        #expect(run.entries.map(\.configuration) == ["One", "One", "Two"])
        let first = try run.target(run.entries[0])
        #expect(first.testsToRun == ["C/test"] && first.testsToSkip == ["C/other"])
        #expect(try run.target(run.entries[0], testsToRun: ["D/given"], testsToSkip: ["D/skip"]).testsToRun == ["D/given"])
        #expect(try run.target(run.entries[0], testsToSkip: ["D/skip"]).testsToSkip == ["C/other", "D/skip"])
        #expect(run.entries[0].unappliedOptions == ["repeating tests", "parallel tests"])
        #expect(run.entries[1].unappliedOptions.isEmpty)
    }

    @Test func readsWhatItWrites() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("xctestrun-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: folder + "/Debug-iphoneos/App.app", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: folder) }
        try XMLPropertyList.data(.dictionary(["CFBundleIdentifier": .string("org.example.app")])).write(to: URL(fileURLWithPath: folder + "/Debug-iphoneos/App.app/Info.plist"))
        let path = folder + "/" + XCTestRunWriter.fileName(Self.build)
        try XCTestRunWriter.files(Self.build)[0].data.write(to: URL(fileURLWithPath: path))
        let run = try XCTestRun(path: path)
        #expect(run.entries.map(\.name) == ["AppTests", "AppUITests"])
        #expect(run.applications == [folder + "/Debug-iphoneos/App.app", folder + "/Debug-iphoneos/AppUITests-Runner.app"])
        let ui = try run.target(run.entries[1])
        #expect(ui.targetApplication == "org.example.app")
        #expect(ui.testBundleRelativePath == "PlugIns/AppUITests.xctest")
        let unit = try run.target(run.entries[0], testsToRun: ["CounterTests/testNext"])
        #expect(unit.environment["XCInjectBundleInto"] == "unused")
        #expect(unit.environment["OS_ACTIVITY_DT_MODE"] == "YES")
        let environment = DeviceTestSession.launchEnvironment(unit, hostPath: "/private/var/containers/Bundle/Application/X/App.app", session: UUID())
        #expect(environment["DYLD_INSERT_LIBRARIES"] == "/System/Developer/usr/lib/libXCTestBundleInject.dylib:/usr/lib/libRPAC.dylib")
        #expect(environment["XCTestBundlePath"] == "/private/var/containers/Bundle/Application/X/App.app/PlugIns/AppTests.xctest")
    }
}
