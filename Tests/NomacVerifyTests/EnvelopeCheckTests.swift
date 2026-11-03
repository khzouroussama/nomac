import Testing
import NomacVerify

/// `nomac verify`'s envelope check (docs/adr/0011-feature-envelope.md).
@Suite struct EnvelopeCheckTests {
    typealias Check = VerificationReport.Check

    static let identical = [Check(kind: "pif", name: "workspace.pif", status: .identical, detail: []),
                            Check(kind: "settings", name: "default", status: .identical, detail: [])]
    static let differing = [Check(kind: "pif", name: "workspace.pif", status: .identical, detail: []),
                            Check(kind: "settings", name: "default", status: .different, detail: ["SDKROOT"])]

    @Test func anAppInsideTheEnvelopeThatDiffersFails() {
        let check = VerificationReport.envelopeCheck(unknown: [], unverified: [], comparisons: Self.differing)
        #expect(check.kind == "envelope")
        #expect(check.status == .different)
        #expect(check.detail == ["every feature is inside the envelope, yet settings differ from Xcode: a verified feature hides a difference",
                                 "settings default"])
    }

    @Test func anAppInsideTheEnvelopeThatMatchesPasses() {
        let check = VerificationReport.envelopeCheck(unknown: [], unverified: [], comparisons: Self.identical)
        #expect(check.status == .identical)
        #expect(check.detail == ["every feature is inside the envelope"])
    }

    @Test func anAppOutsideTheEnvelopeListsWhatItWouldVerify() {
        let matching = VerificationReport.envelopeCheck(unknown: ["scheme:b", "scheme:a"], unverified: ["pbxproj:c"], comparisons: Self.identical)
        #expect(matching.status == .identical)
        #expect(matching.detail == ["features outside the envelope: 3", "every comparison is identical: the app verifies its 2 unknown ones",
                                    "unverified pbxproj:c", "unknown scheme:a", "unknown scheme:b"])
        let different = VerificationReport.envelopeCheck(unknown: ["scheme:a"], unverified: [], comparisons: Self.differing)
        #expect(different.status == .identical)
        #expect(different.detail == ["features outside the envelope: 1", "unknown scheme:a"])
    }
}
