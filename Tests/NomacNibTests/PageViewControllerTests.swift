import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for page view controllers in storyboards
/// (`.github/scripts/nib_experiments.py` round 83, `sb-page-*`): sizes and SHA-256 digests of Xcode's
/// nibs.
@Suite struct PageViewControllerTests {
    static func scene(_ attributes: String = #" transitionStyle="scroll" navigationOrientation="horizontal" spineLocation="none""#, extra: String = "") -> String {
        "<scene sceneID=\"pgs-aa-aaa\">\n<objects>\n<pageViewController\(extra) autoresizesArchivedViewToFullSize=\"NO\"\(attributes) id=\"pvc-aa-aaa\" "
            + "sceneMemberID=\"viewController\"/>\n"
            + #"<placeholder placeholderIdentifier="IBFirstResponder" id="pfr-aa-aaa" sceneMemberID="firstResponder"/>"# + "\n</objects>\n"
            + #"<point key="canvasLocation" x="0" y="0"/>"# + "\n</scene>\n"
    }

    static func storyboard(_ scenes: String..., initial: String = "pvc-aa-aaa") -> String {
        TableViewControllerTests.storyboard(initial: initial, scenes.joined())
    }

    static let nib = "UIPageViewController-pvc-aa-aaa.nib"
    static let cases: [(String, String, String, Int, String)] = [
        ("sb-page-scroll", storyboard(scene()), nib, 939, "e06cb967dd4ad76f0621f64b7a613ac905bc25ed6fb2334b203e1103f37c6cbc"),
        ("sb-page-curl", storyboard(scene(#" transitionStyle="pageCurl" navigationOrientation="horizontal" spineLocation="min""#)), nib, 939,
         "4088dc09f50882ebd44f175c87237eeccffec99ac979f6f32467c2cc78f00ba4"),
        ("sb-page-spacing", storyboard(scene(#" transitionStyle="scroll" pageSpacing="16" navigationOrientation="horizontal" spineLocation="none""#)), nib, 939,
         "6a477a9ac9b52e6bef822fd5f60ea8b4d5b1b0bd6185a361d912f010a821572c"),
        ("sb-page-custom", storyboard(scene(extra: #" storyboardIdentifier="Pages""#).replacingOccurrences(
            of: #"id="pvc-aa-aaa""#, with: #"id="pvc-aa-aaa" customClass="Pages" customModule="T" customModuleProvider="target""#)),
         "Pages.nib", 997, "9798c3568b7769e96ebc6eca103ef4aa5341385893d44fa205a2c0ee42cc979a"),
        ("sb-page-presented", storyboard(SceneTests.scene(1, connections: #"<segue destination="pvc-aa-aaa" kind="presentation" identifier="Pages" id="psg-aa-aaa"/>"# + "\n"),
                                         scene(), initial: "vc1-aa-aaa"),
         nib, 875, "de9cdfc9ff0308579677cb3c40b4ec40414530b76cb9a4c6912ed9f11295e07c"),
    ]

    /// One nib without a view nib: the transition style, orientation, spine location and page
    /// spacing as integers, the class names for an entry point or a custom class.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, document: String, nib: String, size: Int, digest: String) throws {
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        let data = try #require(compiled[nib], "\(name)")
        #expect(data.count == size, "\(name)")
        #expect(VariationTests.digest(data) == digest, "\(name)")
    }
}
