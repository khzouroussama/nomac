import Foundation
import NomacCore
import NomacSigning
import NomacTestSupport
import SwiftBuild
import Testing
@testable import NomacBuild

/// Swift Build's provisioning question for manual development signing, answered as Xcode 27.0's
/// build was observed to (docs/formats/ipa.md "Signing with an identity and a profile"), with
/// the self-made Apple-shaped identity and a self-written profile.
@Suite struct ManualSigningTests {
    static let profileName = "nomac Test Wildcard"

    static func material(in directory: TemporaryDirectory, appID: String = "ABCDE12345.*", certificates: [[UInt8]]? = nil,
                         getTaskAllow: Bool = true) throws -> SigningMaterial {
        let identity = try SigningIdentity(named: "Apple Development", pem: TestIdentities.appleShaped, path: "identity.pem")
        try FileSystem.write(Data(TestIdentities.appleShaped.utf8), to: directory.path + "/identity.pem")
        let entitlements = """
        \t<dict>
        \t\t<key>application-identifier</key>
        \t\t<string>\(appID)</string>
        \t\t<key>get-task-allow</key>
        \t\t<\(getTaskAllow)/>
        \t\t<key>keychain-access-groups</key>
        \t\t<array>
        \t\t\t<string>ABCDE12345.*</string>
        \t\t\t<string>com.apple.token</string>
        \t\t</array>
        \t</dict>
        """
        let profile = SyntheticProfile.profile(uuid: "11111111-2222-3333-4444-555555555555", name: profileName, expiration: "2027-10-30T00:00:00Z",
                                               entitlements: entitlements, certificates: certificates ?? [identity.certificate])
        try FileSystem.write(Data(profile), to: directory.path + "/profiles/wildcard.mobileprovision")
        return SigningMaterial(keychain: directory.path + "/identity.pem", profileFolders: [directory.path + "/profiles"], profileRoots: SyntheticProfile.roots)
    }

    static func source(support: SWBProvisioningProfileSupport = .required, style: SWBProvisioningStyle = .manual,
                       bundle: String = "org.nomac.signing", entitlements: [String: SWBPropertyListItem]? = nil,
                       productType: [String: SWBPropertyListItem] = [:], specifier: String = profileName) -> ManualSigning.Source {
        ManualSigning.Source(targetName: "App", signingIdentity: "Apple Development", style: style, profileSupport: support, profileSpecifier: specifier,
                             profileUUID: "", teamID: "ABCDE12345", bundleIdentifier: bundle, projectEntitlements: entitlements,
                             productTypeEntitlements: productType)
    }

    /// Xcode 27.0's `.xcent` for a UI test target under a wildcard development profile
    /// (`xctest_experiments.py` `build-for-testing`): the runner's identifier in both.
    @Test func aUITestRunnerGetsItsKeychainGroup() throws {
        let directory = try TemporaryDirectory()
        let material = try Self.material(in: directory)
        let inputs = ManualSigning.provisioning(Self.source(bundle: "org.nomac.signing.uitests.xctrunner", productType: [
            "get-task-allow": .plBool(true), "keychain-access-groups": .plArray([.plString("$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)")]),
        ]), material: material)
        #expect(inputs.errors.isEmpty)
        #expect(inputs.signedEntitlements == [
            "application-identifier": .plString("ABCDE12345.org.nomac.signing.uitests.xctrunner"),
            "com.apple.developer.team-identifier": .plString("ABCDE12345"),
            "get-task-allow": .plBool(true),
            "keychain-access-groups": .plArray([.plString("ABCDE12345.org.nomac.signing.uitests.xctrunner")]),
        ])
    }

    /// Only a UI test runner's product type entitlements are observed under a profile that allows them.
    @Test func anotherProductTypeEntitlementTheProfileAllowsStops() throws {
        let directory = try TemporaryDirectory()
        let material = try Self.material(in: directory)
        let inputs = ManualSigning.provisioning(Self.source(productType: ["application-identifier": .plString("ABCDE12345.org.nomac.signing")]), material: material)
        #expect(inputs.errors.first?["description"] == "how Xcode merges the product type's entitlement application-identifier with this profile is not observed yet (BACKLOG B-302)")
    }

    @Test func appGetsTheIdentityTheProfileAndThreeEntitlements() throws {
        let directory = try TemporaryDirectory()
        let material = try Self.material(in: directory)
        let answer = ManualSigning.provisioning(Self.source(), material: material)
        #expect(answer.errors.isEmpty)
        #expect(answer.identityHash == "EF637C7AB75E0067594DF81B2D25E6AD1818024A")
        #expect(answer.identityName == "Apple Development: nomac Test (ABCDE12345)")
        #expect(answer.profileName == Self.profileName && answer.profilePath == directory.path + "/profiles/wildcard.mobileprovision")
        #expect(answer.signedEntitlements == [
            "application-identifier": .plString("ABCDE12345.org.nomac.signing"),
            "com.apple.developer.team-identifier": .plString("ABCDE12345"),
            "get-task-allow": .plBool(true),
        ])
        #expect(answer.appIdentifierPrefix == "ABCDE12345." && answer.keychainPath == material.keychain)
    }

    @Test func frameworkGetsTheIdentityAlone() throws {
        let directory = try TemporaryDirectory()
        let material = try Self.material(in: directory)
        let answer = ManualSigning.provisioning(Self.source(support: .unsupported, specifier: ""), material: material)
        #expect(answer.identityHash == "EF637C7AB75E0067594DF81B2D25E6AD1818024A" && answer.profilePath == nil && answer.signedEntitlements == nil)
        // Given a profile, Xcode refuses it (`distribution_experiments.py` `apple-profile`, the build).
        #expect(ManualSigning.provisioning(Self.source(support: .unsupported), material: material).errors == [[
            "description": "App does not support provisioning profiles.",
            "recoverySuggestion": "App does not support provisioning profiles, but provisioning profile \(Self.profileName) has been manually specified. Set the provisioning profile value to \"Automatic\" in the build settings editor.",
        ]])
    }

    /// Xcode's refusals of a profile (`distribution_experiments.py` `apple-profile`, builds with
    /// manual signing): one not signed by Apple is not installed; one that neither covers the
    /// bundle identifier nor includes the certificate gets both errors.
    @Test func profileRefusalsAsXcodeWords() throws {
        let unsigned = try TemporaryDirectory()
        let material = try Self.material(in: unsigned)
        let untrusted = SigningMaterial(keychain: material.keychain, profileFolders: material.profileFolders)
        #expect(ManualSigning.provisioning(Self.source(), material: untrusted).errors == [[
            "description": "No profile for team 'ABCDE12345' matching '\(Self.profileName)' found",
            "recoverySuggestion": "Xcode couldn't find any provisioning profiles matching 'ABCDE12345/\(Self.profileName)'. Install the profile (by dragging and dropping it onto Xcode's dock item) or select a different one in the Signing & Capabilities tab of the target editor.",
        ]])
        let other = try TemporaryDirectory()
        #expect(ManualSigning.provisioning(Self.source(), material: try Self.material(in: other, appID: "ABCDE12345.org.other.*", certificates: [])).errors == [
            ["description": "Provisioning profile \"\(Self.profileName)\" has app ID \"org.other.*\", which does not match the bundle ID \"org.nomac.signing\"."],
            ["description": "Provisioning profile \"\(Self.profileName)\" doesn't include signing certificate \"Apple Development: nomac Test (ABCDE12345)\"."],
        ])
    }

    @Test func refusals() throws {
        let directory = try TemporaryDirectory()
        let material = try Self.material(in: directory)
        #expect(ManualSigning.provisioning(Self.source(style: .automatic), material: material).errors.count == 1)
        #expect(ManualSigning.provisioning(Self.source(entitlements: ["aps-environment": .plString("development")]), material: material).errors.count == 1)
        #expect(ManualSigning.provisioning(Self.source(entitlements: [:]), material: material).errors.isEmpty)
        let other = try TemporaryDirectory()
        #expect(ManualSigning.provisioning(Self.source(), material: try Self.material(in: other, appID: "ABCDE12345.org.other")).errors.count == 1)
        let noCertificate = try TemporaryDirectory()
        #expect(ManualSigning.provisioning(Self.source(), material: try Self.material(in: noCertificate, certificates: [])).errors.count == 1)
        let distribution = try TemporaryDirectory()
        #expect(ManualSigning.provisioning(Self.source(), material: try Self.material(in: distribution, getTaskAllow: false)).errors.count == 1)
    }

    /// A wildcard App ID under a prefix (the developer portal refuses a bare `*`): it covers the
    /// bundle identifiers that begin with the prefix, and no other.
    @Test func prefixWildcardProfiles() throws {
        let directory = try TemporaryDirectory()
        let material = try Self.material(in: directory, appID: "ABCDE12345.org.nomac.*")
        #expect(ManualSigning.provisioning(Self.source(bundle: "org.nomac.signing"), material: material).errors.isEmpty)
        #expect(ManualSigning.provisioning(Self.source(bundle: "org.nomac.signing.Share"), material: material).errors.isEmpty)
        #expect(ManualSigning.provisioning(Self.source(bundle: "org.nomacx.signing"), material: material).errors.count == 1)
        #expect(ManualSigning.provisioning(Self.source(bundle: "dev.nomac.ExpoDefault"), material: material).errors.count == 1)
    }

    /// An entitlements file's entitlements the profile allows join the three, with
    /// `$(AppIdentifierPrefix)` expanded; one it lacks fails the target with Xcode's messages
    /// (observed privately for B-302: a keychain group, an app group).
    @Test func entitlementsFileMergedWithTheProfile() throws {
        let directory = try TemporaryDirectory()
        let material = try Self.material(in: directory)
        let merged = ManualSigning.provisioning(Self.source(entitlements: ["keychain-access-groups": .plArray([.plString("$(AppIdentifierPrefix)org.nomac.signing")])]),
                                                material: material)
        #expect(merged.errors.isEmpty)
        #expect(merged.signedEntitlements?["keychain-access-groups"] == .plArray([.plString("ABCDE12345.org.nomac.signing")]))
        #expect(merged.signedEntitlements?.count == 4)
        let groups = ManualSigning.provisioning(Self.source(entitlements: ["com.apple.security.application-groups": .plArray([.plString("group.org.nomac")])]),
                                                material: material)
        #expect(groups.errors == [
            ["description": "Provisioning profile \"nomac Test Wildcard\" doesn't include the App Groups capability."],
            ["description": "Provisioning profile \"nomac Test Wildcard\" doesn't include the com.apple.security.application-groups entitlement."],
        ])
    }

    /// `$(PRODUCT_BUNDLE_IDENTIFIER)` expands to the bundle's identifier; an App Clip's product
    /// type entitlement the profile lacks fails the target, the capability first (observed
    /// privately for B-302).
    @Test func buildSettingsAndAppClips() throws {
        let directory = try TemporaryDirectory()
        let material = try Self.material(in: directory)
        let expanded = ManualSigning.provisioning(Self.source(entitlements: ["keychain-access-groups": .plArray([.plString("$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)")])]),
                                                  material: material)
        #expect(expanded.signedEntitlements?["keychain-access-groups"] == .plArray([.plString("ABCDE12345.org.nomac.signing")]))
        let clip = ManualSigning.provisioning(Self.source(bundle: "org.nomac.signing.Clip",
                                                          entitlements: ["com.apple.developer.parent-application-identifiers": .plArray([.plString("$(AppIdentifierPrefix)org.nomac.signing")])],
                                                          productType: ["com.apple.developer.on-demand-install-capable": .plBool(true)]), material: material)
        #expect(clip.errors.map { $0["description"] ?? "" } == [
            "Provisioning profile \"nomac Test Wildcard\" doesn't include the App Clip capability.",
            "Entitlement com.apple.developer.on-demand-install-capable not found and could not be included in profile. This likely is not a valid entitlement and should be removed from your entitlements file.",
            "Provisioning profile \"nomac Test Wildcard\" doesn't include the com.apple.developer.parent-application-identifiers entitlement.",
        ])
    }
}
