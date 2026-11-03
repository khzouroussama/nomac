import Foundation
import NomacCore
import NomacTestSupport
import Testing
@testable import NomacSigning

/// Which profiles count as installed (docs/formats/ipa.md "Which installed profiles xcodebuild
/// uses"): only those whose signature verifies and chains to a trusted root, Apple Root CA
/// outside tests; the synthetic profiles chain to the self-made test root.
@Suite struct ProfileSignatureTests {
    static func profile(_ name: String = "nomac Test") -> [UInt8] {
        SyntheticProfile.profile(uuid: "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0", name: name, expiration: "2027-08-26T11:00:00Z",
                                 entitlements: "\t<dict/>", certificates: [])
    }

    @Test func trustsOnlyTheRootItChainsTo() throws {
        let profile = try ProvisioningProfile(bytes: Self.profile(), path: "test.mobileprovision")
        #expect(profile.isSigned(byRootIn: SyntheticProfile.roots))
        #expect(!profile.isSigned(byRootIn: ProvisioningProfile.appleRoots))
    }

    @Test func contentChangedAfterSigningIsNotTrusted() throws {
        var bytes = Self.profile("nomac Test")
        let name = Array("nomac Test".utf8)
        let index = try #require((0...(bytes.count - name.count)).first { bytes[$0..<($0 + name.count)].elementsEqual(name) })
        bytes[index + name.count - 1] = UInt8(ascii: "X")
        let profile = try ProvisioningProfile(bytes: bytes, path: "test.mobileprovision")
        #expect(profile.name == "nomac TesX")
        #expect(!profile.isSigned(byRootIn: SyntheticProfile.roots))
    }

    @Test func installedFindsOnlyTrustedProfiles() throws {
        let directory = try TemporaryDirectory()
        try FileSystem.write(Data(Self.profile()), to: directory.path + "/a.mobileprovision")
        #expect(try ProvisioningProfile.installed("nomac Test", in: [directory.path], roots: SyntheticProfile.roots)?.name == "nomac Test")
        #expect(try ProvisioningProfile.installed("0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0", in: [directory.path], roots: SyntheticProfile.roots) != nil)
        #expect(try ProvisioningProfile.installed("nomac Test", in: [directory.path]) == nil)
        #expect(try ProvisioningProfile.installed("other", in: [directory.path], roots: SyntheticProfile.roots) == nil)
    }

    @Test func appIDsAndTheBundlesTheyCover() throws {
        let wildcard = try ProvisioningProfile(bytes: SyntheticProfile.profile(uuid: "U", name: "W", expiration: "2027-08-26T11:00:00Z", entitlements: """
            \t<dict>
            \t\t<key>application-identifier</key>
            \t\t<string>ABCDE12345.org.nomac.*</string>
            \t</dict>
            """, certificates: []), path: "w.mobileprovision")
        #expect(wildcard.appID == "org.nomac.*")
        #expect(wildcard.covers(bundleIdentifier: "org.nomac.signing") && !wildcard.covers(bundleIdentifier: "org.nomacx"))
    }
}
