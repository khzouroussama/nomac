import Testing
import NomacVerify

/// How a report's checks count toward a component (docs/VERIFICATION.md).
@Suite struct VerificationReportTests {
    typealias Check = VerificationReport.Check

    @Test func equivalentBuildProductsPass() {
        let report = VerificationReport(app: "app", xcodeBuild: "27A266a", checks: [
            Check(kind: "build", name: "build", status: .identical, detail: []),
            Check(kind: "build", name: "Release-iphoneos/App.app", status: .equivalent, detail: []),
            Check(kind: "build", name: "Release-iphoneos/App.app.dSYM", status: .referenceFailed, detail: []),
        ])
        #expect(report.passes(kinds: ["build"]))
        #expect(report.tally(kind: "build") == (identical: 1, equivalent: 1, total: 2))
        var different = report
        different.checks[1].status = .different
        #expect(!different.passes(kinds: ["build"]))
    }
}
