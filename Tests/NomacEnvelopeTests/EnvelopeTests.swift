import Foundation
@testable import NomacEnvelope
import Testing

struct EnvelopeTests {
    @Test func anUnverifiedEntryWinsOverEvidence() {
        let envelope = Envelope(domain: "d", entries: [
            .verified("f", "corpus:a"), .unverified("f", "differs", backlog: "B-001"), .verified("f", "corpus:b"),
            .verified("g", "corpus:a"), .verified("g", "corpus:b"),
        ])
        #expect(envelope.entry(for: "f")?.status == .unverified)
        #expect(envelope.entry(for: "f")?.evidence == ["B-001"])
        #expect(envelope.entry(for: "g")?.evidence == ["corpus:a", "corpus:b"])
        #expect(envelope.entry(for: "h") == nil)
    }

    @Test func familiesClassifyWhatTheEntriesLack() {
        let envelope = Envelope(domain: "d", entries: [.unverified("x:1", "no")], family: { $0.hasPrefix("x:") ? .verified($0, "rule") : nil })
        #expect(envelope.entry(for: "x:1")?.status == .unverified)
        #expect(envelope.entry(for: "x:2")?.status == .verified)
        #expect(envelope.entry(for: "y:1") == nil)
    }

    @Test func hostConditionsAreThoseAMacWasObservedToAnswer() {
        let envelope = LoaderEnvelope.envelope
        #expect(envelope.entry(for: "package:condition=os(Linux)")?.status == .verified)
        #expect(envelope.entry(for: "package:condition=canImport(Darwin)")?.status == .verified)
        #expect(envelope.entry(for: "package:condition=canImport(SomeVendorKit)")?.status == .unverified)
        #expect(envelope.entry(for: "package:condition=swift")?.status == .verified)
        #expect(envelope.entry(for: "package:condition=hasFeature") == nil)
    }

    struct Domain: FeatureDomain {
        let name = "test"
        let envelope = Envelope(domain: "test", entries: [.verified("known", "corpus:a"), .unverified("risky", "differs", backlog: "B-001")])

        func scan(_ container: String, options: CheckOptions) throws -> DomainScan {
            DomainScan(uses: [FeatureUse(feature: "known", file: "/w/A.xcodeproj/project.pbxproj", object: "PBXProject 1"),
                              FeatureUse(feature: "risky", file: "/w/A.xcodeproj/project.pbxproj", object: "PBXNativeTarget 2 (App)"),
                              FeatureUse(feature: "new", file: "/w/x.xcconfig", object: "line 3")],
                       unchecked: [UncheckedPart(what: "contents of a synchronized folder", file: "/w/App")])
        }
    }

    struct FailingDomain: FeatureDomain {
        struct Unreadable: Error {}
        let name = "broken"
        let envelope = Envelope(domain: "broken", entries: [])

        func scan(_ container: String, options: CheckOptions) throws -> DomainScan { throw Unreadable() }
    }

    /// A domain that cannot read the container leaves the project outside; the others still report.
    @Test func aDomainThatCannotScanLeavesTheProjectOutside() {
        let report = CheckReport.make(container: "/w/A.xcodeproj", domains: [Domain(), FailingDomain()], options: CheckOptions())
        #expect(report.features.map(\.id) == ["broken:scan=failed", "known", "new", "risky"])
        #expect(report.features.first?.status == .unknown)
        #expect(report.features.first?.uses.map(\.file) == ["/w/A.xcodeproj"])
    }

    @Test func reportsWhatIsOutsideAndWhere() throws {
        let report = CheckReport.make(container: "/w/A.xcodeproj", domains: [Domain()], options: CheckOptions(descriptionOnly: true))
        #expect(report.features.map(\.id) == ["known", "new", "risky"])
        #expect(report.outside.map(\.status) == [.unknown, .unverified])
        #expect(report.text() == """
            A.xcodeproj: 3 features used, 1 verified, 1 unverified, 1 unknown

            Outside the envelope:
              unknown    new
                  x.xcconfig: line 3
              unverified risky
                  differs
                  evidence: B-001
                  A.xcodeproj/project.pbxproj: PBXNativeTarget 2 (App)

            Not checked:
              test: contents of a synchronized folder: App

            2 of 3 features are outside the envelope.

            """)
        let json = try JSONSerialization.jsonObject(with: Data(try report.json().utf8)) as? [String: Any]
        #expect(json?["inside"] as? Bool == false)
        #expect(json?["outside"] as? Int == 2)
        let features = json?["features"] as? [[String: Any]] ?? []
        #expect(features.first?["uses"] == nil)
        #expect((features.last?["uses"] as? [[String: String]])?.first?["file"] == "A.xcodeproj/project.pbxproj")
    }

    @Test func listsEachObjectBeforeItsRepeats() {
        let uses = ["a", "a", "a", "b", "a", "c"].enumerated().map { FeatureUse(feature: "f", file: "/\($0.offset)", object: $0.element) }
        #expect(CheckReport.sample(uses, count: 4).map(\.file) == ["/0", "/1", "/3", "/5"])
        #expect(CheckReport.sample(uses, count: 2).map(\.object) == ["a", "b"])
    }
}
