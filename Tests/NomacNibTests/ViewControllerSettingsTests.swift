import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for view controllers' attributes in storyboards
/// (`.github/scripts/nib_experiments.py` round 46, `sb-vc-*`): sizes and SHA-256 digests of the files of
/// Xcode's `.storyboardc`.
@Suite struct ViewControllerSettingsTests {
    static let all = #" title="Detail" extendedLayoutIncludesOpaqueBars="YES" automaticallyAdjustsScrollViewInsets="NO" hidesBottomBarWhenPushed="YES""#
        + #" modalPresentationStyle="overCurrentContext" modalTransitionStyle="crossDissolve" restorationIdentifier="Restore" storyboardIdentifier="First""#

    static let cases: [(String, String, [(String, Int, String)])] = [
        ("sb-vc-all-segue", SceneTests.storyboard(SceneTests.scene(1, attributes: all, connections: SceneTests.segue(2, "show", 1, "Detail")), SceneTests.scene(2)), [
            ("First.nib", 1481, "faa5dbd206c133e6217119992857016f4063fb34249afeac4d68abd4c384b44b"),
            ("Info.plist", 243, "ad6a2483d4f19075cf80b9f1bc2d62399111f5ca153b021912f8290c6c19bdf7"),
            ("UIViewController-vc2-aa-aaa.nib", 860, "77ea33d9265b1240144062a8c9255bfda38b8956e9a7efea85bcfdd94b4957bf"),
        ]),
        ("sb-vc-restoration-storyboard-id", SceneTests.storyboard(SceneTests.scene(1, attributes: #" storyboardIdentifier="Second" useStoryboardIdentifierAsRestorationIdentifier="YES""#)), [
            ("Info.plist", 181, "d538ae9eb4297968003ae7dcc7e4503507e14bd5c624a56341ac01a26efbffd6"),
            ("Second.nib", 995, "e5268a9ffaf04723295a8fe4af294f314dcfb2c31f40c015e8fa301994efcb2a"),
        ]),
        ("sb-vc-restoration-equal-storyboard-id", SceneTests.storyboard(SceneTests.scene(1, attributes: #" restorationIdentifier="Second" storyboardIdentifier="Second""#)), [
            ("Second.nib", 995, "e5268a9ffaf04723295a8fe4af294f314dcfb2c31f40c015e8fa301994efcb2a"),
        ]),
    ]

    /// The title first (one string with an equal segue identifier), the restoration identifier after the
    /// storyboard identifier, presentation, transition, bars and insets after the segue templates.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, document: String, files: [(String, Int, String)]) throws {
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        for (file, size, digest) in files + [("vc1-aa-aaa-view-vw1-aa-aaa.nib", SceneTests.view.0, SceneTests.view.1)] {
            let data = try #require(compiled[file], "\(name) \(file)")
            #expect(data.count == size, "\(name) \(file)")
            #expect(VariationTests.digest(data) == digest, "\(name) \(file)")
        }
    }
}
