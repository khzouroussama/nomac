import Foundation
import NomacCore
import NomacPackaging
import NomacTestSupport
import Testing
@testable import nomac

/// The bundle identifier `nomac install` stops before replacing an app: a .app's, or the app's
/// in an IPA's `Payload`.
@Suite struct BundleIdentifierTests {
    @Test func ofAnAppAndOfAnIPA() throws {
        let tmp = try TemporaryDirectory()
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "org.nomac.app"], format: .binary, options: 0)
        try FileSystem.write(plist, to: tmp.path + "/in/Payload/App.app/Info.plist")
        try FileSystem.write(Data("plugin".utf8), to: tmp.path + "/in/Payload/App.app/PlugIns/Tests.xctest/Info.plist")
        try DittoArchive.create(from: tmp.path + "/in", to: tmp.path + "/App.ipa")
        #expect(try bundleIdentifier(of: tmp.path + "/in/Payload/App.app") == "org.nomac.app")
        #expect(try bundleIdentifier(of: tmp.path + "/App.ipa") == "org.nomac.app")
    }

    /// `nomac install` of an IPA says what a device would refuse, without asking one.
    @Test func anAdHocIPAIsRefusedWithTheNextStep() throws {
        let tmp = try TemporaryDirectory()
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "org.nomac.app"], format: .binary, options: 0)
        try FileSystem.write(plist, to: tmp.path + "/in/Payload/App.app/Info.plist")
        try DittoArchive.create(from: tmp.path + "/in", to: tmp.path + "/App.ipa")
        let problems = try ipaProblems(tmp.path + "/App.ipa", device: "00008140-00FACE00FACE001E", at: Date())
        #expect(problems == ["the app has no embedded.mobileprovision: an app signed ad hoc installs on no device; sign it with a development identity and profile"])
    }

    @Test func anIPAWithAProfileIsCheckedAgainstIt() throws {
        let tmp = try TemporaryDirectory()
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "org.nomac.app"], format: .binary, options: 0)
        let entitlements = "\t<dict>\n\t\t<key>application-identifier</key>\n\t\t<string>ABCDE12345.org.other.*</string>\n\t</dict>"
        let profile = SyntheticProfile.profile(uuid: "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0", name: "nomac Development", expiration: "2099-01-01T00:00:00Z", entitlements: entitlements,
                                               certificates: [], otherKeys: "\t<key>ProvisionedDevices</key>\n\t<array>\n\t\t<string>00008140-00FACE00FACE001E</string>\n\t</array>\n")
        try FileSystem.write(plist, to: tmp.path + "/in/Payload/App.app/Info.plist")
        try FileSystem.write(Data(profile), to: tmp.path + "/in/Payload/App.app/embedded.mobileprovision")
        try DittoArchive.create(from: tmp.path + "/in", to: tmp.path + "/App.ipa")
        #expect(try ipaProblems(tmp.path + "/App.ipa", device: "00008140-00FACE00FACE001E", at: Date())
            == ["the profile's App ID ABCDE12345.org.other.* does not cover the bundle identifier org.nomac.app"])
    }
}
