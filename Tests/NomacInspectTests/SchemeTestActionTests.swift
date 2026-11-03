import Foundation
import Testing
import NomacProject
import NomacTestSupport

/// Schemes shaped like loader-experiments' `blueprint-names` and `coverage-autocreated-plan`,
/// written again here; what Xcode 27.0 reported for them is each test's expectation.
@Suite struct SchemeTestActionTests {
    static let project = AutocreationProject(targets: [
        .init(name: "App", type: "application"),
        .init(name: "Kit", type: "framework"),
        .init(name: "AppTests", type: "bundle.unit-test", testTarget: "App"),
    ])

    /// A scheme that builds App for running; `testables` holds (target, BlueprintName or nil,
    /// skipped), `autocreatesPlan` sets shouldAutocreateTestPlan and `plan` names a default test
    /// plan.
    static func scheme(launchName: String? = "App", testables: [(String, String?, Bool)] = [], autocreatesPlan: Bool = false, plan: String? = nil) -> String {
        func reference(_ target: String, _ name: String?) -> String {
            "<BuildableReference BuildableIdentifier = \"primary\" BlueprintIdentifier = \"\(project.targetID(target))\" BuildableName = \"\(target).app\" "
                + (name.map { "BlueprintName = \"\($0)\" " } ?? "") + "ReferencedContainer = \"container:P.xcodeproj\"></BuildableReference>\n"
        }
        let tests = testables.map { "<TestableReference skipped = \"\($0.2 ? "YES" : "NO")\">\n" + reference($0.0, $0.1) + "</TestableReference>\n" }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <Scheme LastUpgradeVersion = "2700" version = "1.8">
        <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
        <BuildActionEntries>
        <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
        \(reference("App", launchName))</BuildActionEntry>
        </BuildActionEntries>
        </BuildAction>
        <TestAction buildConfiguration = "Debug"\(autocreatesPlan ? " shouldAutocreateTestPlan = \"YES\"" : "")>
        <TestPlans>
        \(plan.map { "<TestPlanReference reference = \"container:\($0)\" default = \"YES\"></TestPlanReference>\n" } ?? "")</TestPlans>
        <Testables>
        \(tests)</Testables>
        </TestAction>
        <LaunchAction buildConfiguration = "Debug" launchStyle = "0">
        <BuildableProductRunnable runnableDebuggingMode = "0">
        \(reference("App", launchName))</BuildableProductRunnable>
        </LaunchAction>
        </Scheme>

        """
    }

    /// Xcode finds a scheme's targets by BlueprintIdentifier: a reference without BlueprintName
    /// is read, and one naming another target means the target it identifies (home-assistant's
    /// `WatchApp` schemes).
    @Test func readsReferencesWithoutBlueprintNames() async throws {
        let directory = try TemporaryDirectory()
        var project = Self.project
        project.schemes = [
            "Unnamed": Self.scheme(launchName: nil, testables: [("AppTests", nil, false)]),
            "WrongNames": Self.scheme(launchName: "Kit", testables: [("AppTests", "App", false)]),
        ]
        let schemes = try await project.schemes(in: directory.path)
        for name in ["Unnamed", "WrongNames"] {
            let scheme = try #require(schemes.first { $0.name == name })
            #expect(scheme.buildEntries.map(\.targetID) == [project.targetID("App")], "\(name)")
            #expect(scheme.runs.map(\.targetID) == [project.targetID("App")], "\(name)")
            #expect(scheme.testables.map(\.targetID) == [project.targetID("AppTests")], "\(name)")
        }
    }

    /// A test plan Xcode autocreates for a scheme's testables, skipped ones included, gathers
    /// coverage; without testables there is none, and a test plan of the scheme decides
    /// (pocket-casts' `Pocket Casts Prototype Build`).
    @Test func autocreatedTestPlansGatherCoverage() async throws {
        let directory = try TemporaryDirectory()
        var project = Self.project
        project.files["Off.xctestplan"] = AutocreationProject.testPlan(options: #"{"codeCoverage": false}"#)
        let cases: [(String, String, Bool)] = [
            ("Testables", Self.scheme(testables: [("AppTests", "AppTests", false)], autocreatesPlan: true), true),
            ("NoTestables", Self.scheme(autocreatesPlan: true), false),
            ("Skipped", Self.scheme(testables: [("AppTests", "AppTests", true)], autocreatesPlan: true), true),
            ("PlanOff", Self.scheme(testables: [("AppTests", "AppTests", false)], autocreatesPlan: true, plan: "Off.xctestplan"), false),
            ("NotAutocreated", Self.scheme(testables: [("AppTests", "AppTests", false)]), false),
        ]
        project.schemes = Dictionary(uniqueKeysWithValues: cases.map { ($0.0, $0.1) })
        let schemes = try await project.schemes(in: directory.path)
        for (name, _, expected) in cases {
            #expect(schemes.first { $0.name == name }?.codeCoverageEnabled == expected, "\(name)")
        }
    }
}
