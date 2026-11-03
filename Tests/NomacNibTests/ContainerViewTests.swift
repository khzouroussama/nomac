import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for storyboard container views and their embed segues
/// (`.github/scripts/nib_experiments.py` round 84, `sb-embed*`, `sb-container-empty`): sizes and
/// SHA-256 digests of Xcode's nibs.
@Suite struct ContainerViewTests {
    static func container(_ segue: String?) -> String {
        "<containerView opaque=\"NO\" contentMode=\"scaleToFill\" id=\"cnt-aa-aa1\">\n" + #"<rect key="frame" x="20" y="100" width="200" height="300"/>"# + "\n"
            + #"<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>"# + "\n"
            + (segue.map { "<connections>\n\($0)\n</connections>\n" } ?? "") + "</containerView>\n"
    }

    static let embed = #"<segue destination="vc2-aa-aaa" kind="embed" id="emb-aa-aaa"/>"#
    static func storyboard(_ segue: String?, connections: String = "", child: Bool = true) -> String {
        SceneTests.storyboard(TriggeredSegueTests.scene(1, buttons: container(segue), connections: connections, exit: false) + (child ? SceneTests.scene(2) : ""))
    }

    static let cases: [(String, String, [(String, Int, String)])] = [
        ("sb-embed", storyboard(embed),
         [("UIViewController-vc1-aa-aaa.nib", 1213, "8f9f9b78769c24a95066897b01b5c773aaab77f07449f5f559b00521b7f69796"),
          ("vc1-aa-aaa-view-vw1-aa-aaa.nib", 1883, "8fff0b590d4107e9044abec6036a3bc36d6f9d96fd82617d2bbf7819d0e8ef98"),
          ("vc2-aa-aaa-view-vw2-aa-aaa.nib", 1701, "4c0e6da8676bcb2b2096ac22729ab3e74a9560aa20d80d11e97f36f0fba4779e")]),
        ("sb-embed-named", storyboard(embed.replacingOccurrences(of: #"kind="embed""#, with: #"kind="embed" identifier="Child""#)),
         [("UIViewController-vc1-aa-aaa.nib", 1243, "d55f75b6ba3b74c02e3367d44d8272ae177e43bc781d830037ef6cbb188c7024")]),
        ("sb-embed-outlet", storyboard(embed, connections: #"<outlet property="box" destination="cnt-aa-aa1" id="out-aa-aaa"/>"# + "\n"),
         [("vc1-aa-aaa-view-vw1-aa-aaa.nib", 1970, "f7c8be3cb9d35cc5a5a7ed7fb3f435c805295a68ee440ea31d1f0633f78e3423")]),
        ("sb-container-empty", storyboard(nil, child: false),
         [("vc1-aa-aaa-view-vw1-aa-aaa.nib", 1787, "8df0b65fddb874c49394f8dff5b7f45d278ea1b41d26fb131919b8179337c267")]),
    ]

    /// An embed segue's template, its upstream placeholder's `containerView` outlet, the embedded
    /// controller's view sized as its container view; an empty container view a plain view.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, document: String, nibs: [(String, Int, String)]) throws {
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        for (nib, size, digest) in nibs {
            let data = try #require(compiled[nib], "\(name) \(nib)")
            #expect(data.count == size, "\(name) \(nib)")
            #expect(VariationTests.digest(data) == digest, "\(name) \(nib)")
        }
    }

    /// A freeform size without freeform metrics sizes the scene's view whatever its frame
    /// (`sb-freeform-size-only-device-frame`).
    @Test func freeformSizeWithoutMetrics() throws {
        let document = SceneTests.storyboard(SceneTests.scene(1, afterView: "<size key=\"freeformSize\" width=\"375\" height=\"60\"/>\n"))
        let data = try #require(try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)["vc1-aa-aaa-view-vw1-aa-aaa.nib"])
        #expect(data.count == 1701)
        #expect(VariationTests.digest(data) == "dc9970c0b97c4ebde46ac5e658e87dfe20db3b179acd53148d750f1123956f40")
    }
}

