import Foundation
import NomacCore
import NomacNib
import Testing

@Suite struct IBToolVersionTests {
    /// Swift Build decodes `com.apple.ibtool.version` from `ibtool --version --output-format xml1`,
    /// which nomac answers as the profile's Xcode's ibtool does.
    @Test func answersSwiftBuildsProbeAsXcodesIbtoolAndNamesNomac() throws {
        let plist = try #require(try PropertyListSerialization.propertyList(from: Data(IBToolVersion.report.utf8), format: nil) as? [String: Any])
        let ibtool = XcodeProfile.current.ibtool
        #expect(plist["com.apple.ibtool.version"] as? [String: String] == ["bundle-version": ibtool.bundleVersion, "short-bundle-version": ibtool.shortBundleVersion])
        #expect(plist["nomac"] as? [String: String] == ["version": NomacVersion.current])
    }
}
