import Foundation
import NomacCore
import NomacSigning
import NomacTestSupport
import Testing
@testable import NomacDevice

/// The provisioning rules of TN3125 a device applies to an app, on self-written profiles.
@Suite struct InstallCheckTests {
    static let device = "00008140-0001234567890ABC"
    static let now = ISO8601DateFormatter().date(from: "2026-10-30T12:00:00Z")!

    static func profile(appID: String, expiration: String = "2027-01-01T00:00:00Z", otherKeys: String = "") throws -> ProvisioningProfile {
        let entitlements = "\t<dict>\n\t\t<key>application-identifier</key>\n\t\t<string>\(appID)</string>\n\t</dict>"
        let bytes = SyntheticProfile.profile(uuid: "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0", name: "nomac Development", expiration: expiration,
                                             entitlements: entitlements, certificates: [], otherKeys: otherKeys)
        return try ProvisioningProfile(bytes: bytes, path: "test.mobileprovision")
    }

    static let devices = "\t<key>ProvisionedDevices</key>\n\t<array>\n\t\t<string>\(device)</string>\n\t</array>\n"

    @Test func explicitProfileWithTheDevice() throws {
        let profile = try Self.profile(appID: "ABCDE12345.org.nomac.app", otherKeys: Self.devices)
        #expect(profile.provisionedDevices == [Self.device])
        #expect(InstallCheck.problems(profile: profile, bundleIdentifier: "org.nomac.app", device: Self.device, at: Self.now).isEmpty)
        #expect(InstallCheck.problems(profile: profile, bundleIdentifier: "org.nomac.app.extra", device: nil, at: Self.now)
            == ["the profile's App ID ABCDE12345.org.nomac.app does not cover the bundle identifier org.nomac.app.extra"])
    }

    @Test func wildcardProfiles() throws {
        #expect(InstallCheck.covers("ABCDE12345.*", "org.nomac.app"))
        #expect(InstallCheck.covers("ABCDE12345.org.nomac.*", "org.nomac.app"))
        #expect(!InstallCheck.covers("ABCDE12345.org.nomac.*", "org.other.app"))
        #expect(!InstallCheck.covers("ABCDE12345.org.nomac.*", "org.nomacx.app"))
        #expect(InstallCheck.covers("ABCDE12345.org.nomac.*", "org.nomac.demo.Kit"))
        #expect(ProvisioningProfile.unauthorized(["application-identifier": .string("ABCDE12345.org.nomac.demo")],
                                          ["application-identifier": .string("ABCDE12345.org.nomac.*")]).isEmpty)
    }

    @Test func deviceNotInTheProfile() throws {
        let profile = try Self.profile(appID: "ABCDE12345.*", otherKeys: Self.devices)
        #expect(InstallCheck.problems(profile: profile, bundleIdentifier: "org.nomac.app", device: "00008140-000AAAAAAAAAAAAA", at: Self.now)
            == ["the profile \"nomac Development\" does not include the device 00008140-000AAAAAAAAAAAAA"])
    }

    @Test func profileForAllDevices() throws {
        let profile = try Self.profile(appID: "ABCDE12345.*", otherKeys: "\t<key>ProvisionsAllDevices</key>\n\t<true/>\n")
        #expect(profile.provisionsAllDevices)
        #expect(InstallCheck.problems(profile: profile, bundleIdentifier: "org.nomac.app", device: Self.device, at: Self.now).isEmpty)
    }

    @Test func expiredProfile() throws {
        let profile = try Self.profile(appID: "ABCDE12345.*", expiration: "2026-10-01T00:00:00Z", otherKeys: Self.devices)
        #expect(InstallCheck.problems(profile: profile, bundleIdentifier: "org.nomac.app", device: Self.device, at: Self.now)
            == ["the profile \"nomac Development\" expired on 2026-10-01T00:00:00Z"])
    }

    @Test func appSignedAdHoc() throws {
        let directory = try TemporaryDirectory()
        let app = directory.path + "/App.app"
        try FileSystem.createDirectory(app)
        try FileSystem.write(Data(PropertyListValue.xmlDocument(.dictionary(["CFBundleIdentifier": .string("org.nomac.app")]))), to: app + "/Info.plist")
        let problems = try InstallCheck.problems(app: app, device: Self.device, at: Self.now)
        #expect(problems.count == 1 && problems[0].hasPrefix("the app has no embedded.mobileprovision"))
        try FileSystem.write(Data(SyntheticProfile.profile(uuid: "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0", name: "nomac Development",
                                                           expiration: "2027-01-01T00:00:00Z",
                                                           entitlements: "\t<dict>\n\t\t<key>application-identifier</key>\n\t\t<string>ABCDE12345.*</string>\n\t</dict>",
                                                           certificates: [], otherKeys: Self.devices)), to: app + "/embedded.mobileprovision")
        #expect(try InstallCheck.problems(app: app, device: Self.device, at: Self.now).isEmpty)
    }

    @Test func entitlementsAWildcardProfileAllows() {
        let allowed: [String: PropertyListValue] = [
            "application-identifier": .string("ABCDE12345.*"), "com.apple.developer.team-identifier": .string("ABCDE12345"),
            "get-task-allow": .boolean(true), "keychain-access-groups": .array([.string("ABCDE12345.*"), .string("com.apple.token")]),
        ]
        let claimed: [String: PropertyListValue] = [
            "application-identifier": .string("ABCDE12345.org.nomac.app"), "com.apple.developer.team-identifier": .string("ABCDE12345"),
            "get-task-allow": .boolean(true), "keychain-access-groups": .array([.string("ABCDE12345.org.nomac.app")]),
            "aps-environment": .string("development"), "com.apple.developer.associated-domains": .array([.string("applinks:nomac.org")]),
        ]
        #expect(ProvisioningProfile.unauthorized(claimed, allowed) == ["aps-environment", "com.apple.developer.associated-domains"])
        #expect(ProvisioningProfile.unauthorized(["application-identifier": .string("OTHER12345.org.nomac.app")], allowed) == ["application-identifier"])
        #expect(ProvisioningProfile.unauthorized(["get-task-allow": .boolean(true)], ["get-task-allow": .boolean(false)]) == ["get-task-allow"])
    }

    /// TN3187: no scene manifest under the iOS 27 SDK stops the app at launch.
    @Test func sceneLifecycleWarning() throws {
        let directory = try TemporaryDirectory()
        func app(_ info: [String: PropertyListValue]) throws -> String {
            let path = directory.path + "/\(UUID().uuidString).app"
            try FileSystem.createDirectory(path)
            try FileSystem.write(Data(PropertyListValue.xmlDocument(.dictionary(info.merging(["CFBundleIdentifier": .string("org.nomac.app")]) { a, _ in a }))),
                                 to: path + "/Info.plist")
            return path
        }
        #expect(try InstallCheck.warnings(app: app(["DTPlatformVersion": .string("27.0")])).count == 1)
        #expect(try InstallCheck.warnings(app: app(["DTPlatformVersion": .string("26.4")])).isEmpty)
        #expect(try InstallCheck.warnings(app: app(["DTPlatformVersion": .string("27.0"),
                                                    "UIApplicationSceneManifest": .dictionary(["UISceneConfigurations": .dictionary([:])])])).isEmpty)
    }
}
