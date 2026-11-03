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
}
