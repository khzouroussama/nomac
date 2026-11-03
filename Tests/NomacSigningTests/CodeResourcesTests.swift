import Foundation
import NomacCore
import NomacTestSupport
import Testing
@testable import NomacSigning

/// The seal of a bundle whose code needs a SHA-1 code directory (a watch app for watchOS 11.0
/// with an asset catalog, `distribution_experiments.py` `thinning` `watch-catalog`, as Xcode's
/// export signed it): each file of `files2` has its SHA-1 `hash` beside `hash2`.
@Suite struct CodeResourcesTests {
    @Test func sha1HashesBesideSHA256OnesWhenTheCodeNeedsThem() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-code-resources")
        for (name, minimum, sha1) in [("old", UInt32(11 << 16), true), ("new", UInt32(26 << 16), false)] {
            let bundle = temporary.path + "/\(name)/Watch.app"
            try FileSystem.write(Data("""
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                <plist version="1.0">
                <dict>
                \t<key>CFBundleExecutable</key>
                \t<string>Watch</string>
                \t<key>CFBundleIdentifier</key>
                \t<string>org.nomac.watch</string>
                </dict>
                </plist>

                """.utf8), to: bundle + "/Info.plist")
            try FileSystem.writeExactly(SyntheticMachO.machO(arm64_32: true, platform: 4, minimumOS: minimum, seed: 30), to: bundle + "/Watch")
            try FileSystem.write(Data("catalog".utf8), to: bundle + "/Assets.car")
            _ = try CodeSigner.sign(CodeSigner.Request(path: bundle, identity: "-", force: true))
            let seal = try PropertyLists.readDictionary(at: bundle + "/_CodeSignature/CodeResources")
            let entry = (seal["files2"] as? [String: Any])?["Assets.car"] as? [String: Any]
            #expect((entry?["hash"] as? Data) == (sha1 ? Data(CodeSignature.sha1(Array("catalog".utf8))) : nil), "\(name)")
            #expect((entry?["hash2"] as? Data) == Data(CodeSignature.sha256(Array("catalog".utf8))))
        }
    }
}
