import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for a storyboard's global tint, its `<color key="tintColor">`
/// (`.github/scripts/nib_experiments.py` round 102, `sb-tint-*`): sizes and SHA-256 digests of
/// Xcode's nibs.
@Suite struct GlobalTintTests {
    static let tint = #"<color key="tintColor" red="0.2" green="0.4" blue="0.6" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>"# + "\n"

    static func tinted(_ document: String, _ color: String = tint) -> String {
        document.replacingOccurrences(of: "</document>", with: color + "</document>")
    }

    static let viewNib = ("vc1-aa-aaa-view-vw1-aa-aaa.nib", 1935, "32bb86362d15ec7bd692b6d7a2fd95f86a71f911e9253c86e60250d876fb8eaf")
    static let cases: [(String, String, [(String, Int, String)])] = [
        ("sb-tint-plain", tinted(SceneTests.storyboard(SceneTests.scene(1))), [viewNib]),
        ("sb-tint-gray", tinted(SceneTests.storyboard(SceneTests.scene(1)),
                                #"<color key="tintColor" white="0.25" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>"# + "\n"),
         [("vc1-aa-aaa-view-vw1-aa-aaa.nib", 1833, "879ede4faf20d499feccd3b43c2abe24d8c146b26afc276e53cde1e9186cf9a8")]),
        ("sb-tint-view-tint", tinted(SceneTests.storyboard(SceneTests.scene(1).replacingOccurrences(
            of: "</view>", with: #"<color key="tintColor" white="0.5" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>"# + "\n</view>"))),
         [("vc1-aa-aaa-view-vw1-aa-aaa.nib", 1832, "ada70a7428431c76f5d4ba85157c88c98bcc473f7154fc95168be86d230f243e")]),
        ("sb-tint-nav", tinted(NavigationTests.storyboard(NavigationTests.navigation(), SceneTests.scene(1))),
         [(NavigationTests.navigationNib, 1928, "d03ec32de1dbb694061d7ace69bb5055a828177bdc25080350ab52f0e721dd47"), viewNib]),
        ("sb-tint-tab-nav", tinted(ContainerControllerTests.storyboard(ContainerControllerTests.tab(["nvc-aa-aaa", "vc2-aa-aaa"]),
                                                                       ContainerControllerTests.navigation("aa", root: 1), SceneTests.scene(1), SceneTests.scene(2))),
         [(ContainerControllerTests.nib, 2457, "bcdf761b552cb44ef19d51dc885acd5210c0ad9d50a1dae81e842acf93ae7fa6"), viewNib,
          ("vc2-aa-aaa-view-vw2-aa-aaa.nib", 1935, "32bb86362d15ec7bd692b6d7a2fd95f86a71f911e9253c86e60250d876fb8eaf")]),
    ]

    /// The tint of each scene's view without one of its own, and of navigation bars, in tab bar
    /// controllers too; tab bars and buttons keep none.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, document: String, files: [(String, Int, String)]) throws {
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        for (file, size, digest) in files {
            let data = try #require(compiled[file], "\(name) \(file)")
            #expect(data.count == size, "\(name) \(file)")
            #expect(VariationTests.digest(data) == digest, "\(name) \(file)")
        }
    }
}
