import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for navigation and tab bar controllers' attributes and shapes in
/// storyboards (`.github/scripts/nib_experiments.py` rounds 125 to 128): sizes and SHA-256 digests.
@Suite struct ControllerShapeTests {
    static let identified = #" storyboardIdentifier="First""#
    static let navItem = #"<tabBarItem key="tabBarItem" title="Item" id="tbi-aa-aa1"/>"# + "\n"
    static let navigationItem = #"<navigationItem key="navigationItem" title="Top" id="nvi-aa-aaa"/>"# + "\n"
    static let rootless = NavigationTests.navigation().replacingOccurrences(of: #"<connections>\s*<segue [^>]*rootViewController[^>]*/>\s*</connections>"#, with: "", options: .regularExpression)
    static let showing = NavigationTests.navigation().replacingOccurrences(of: #"id="rel-aa-aaa"/>"#, with: #"id="rel-aa-aaa"/>"# + "\n" + #"<segue destination="vc2-aa-aaa" kind="show" identifier="Next" id="sho-aa-aaa"/>"#)
    static let childless = ContainerControllerTests.tab([]).replacingOccurrences(of: "<connections>\n</connections>\n", with: "")

    static func tabs(_ scenes: String...) -> String {
        NavigationTests.storyboard(initial: "tab-aa-aaa", ContainerControllerTests.tab() + scenes.joined())
    }

    static func single(_ scene: String) -> String {
        NavigationTests.storyboard(initial: "vc1-aa-aaa", scene)
    }

    static let cases: [(String, String, String, Int, String)] = [
        ("sb-navattr-all", NavigationTests.storyboard(NavigationTests.navigation(attributes: #" customClass="Stack" customModule="T" customModuleProvider="target" definesPresentationContext="YES" navigationBarHidden="YES" toolbarHidden="NO" modalPresentationStyle="formSheet" modalTransitionStyle="crossDissolve" extendedLayoutIncludesOpaqueBars="YES" hidesBottomBarWhenPushed="YES" hidesBarsWhenKeyboardAppears="YES" automaticallyAdjustsScrollViewInsets="NO" title="Stack" storyboardIdentifier="Stack" restorationIdentifier="Keep""#, extra: navItem), SceneTests.scene(1)), "Stack.nib", 2178, "a1b041889c6b4af14aa32d05f84a31ea53998a89ca2b2a0f7de0bb490333094b"),
        ("sb-tab-id-child (tab)", tabs(SceneTests.scene(1, attributes: identified), SceneTests.scene(2)), "UITabBarController-tab-aa-aaa.nib", 1821, "9609d1f8fe70e9b2f29369f1bb5b48c6f726516d388aae6b8bd096a66f6c2eff"),
        ("sb-tab-id-child (own)", tabs(SceneTests.scene(1, attributes: identified), SceneTests.scene(2)), "First.nib", 964, "365b0e39fc151eb9a3106c30a66a02bf9013f0206d021a5bafcb1f0a51582390"),
        ("sb-vcattr-tab-and-nav-item", single(SceneTests.scene(1, attributes: #" title="One""#, afterView: navigationItem + ContainerControllerTests.item(1, #" title="First""#))), "UIViewController-vc1-aa-aaa.nib", 1224, "5bf77694c3bf6c432813da5a06da1da16e1bf711bd57ba87b1586b3e6c026a8b"),
        ("sb-tabattr-no-children", ContainerControllerTests.storyboard(childless), "UITabBarController-tab-aa-aaa.nib", 1263, "69071a62288b008fa573527c61f6ef1191500a47b1728204b496c7e373f2bf5a"),
        ("sb-shape-nav-no-root", NavigationTests.storyboard(rootless), "UINavigationController-nvc-aa-aaa.nib", 1286, "ce08f050eb672ac0f02a5342cafd76cbfe4f6a7e8db27ffa5419866d288d047b"),
        ("sb-shape-nav-show", NavigationTests.storyboard(showing, SceneTests.scene(1), SceneTests.scene(2)), "UINavigationController-nvc-aa-aaa.nib", 1986, "d831f288f4ad83ecadd64bd6f59addb036ca295b5dcfaffdce1912156eb7254d"),
        ("sb-tabattr-item-system-search", tabs(SceneTests.scene(1, afterView: ContainerControllerTests.item(1, #" systemItem="search""#)), SceneTests.scene(2)), "UITabBarController-tab-aa-aaa.nib", 1767, "f8b528714bee12324751b50567b4d51940473208ecfd3f53639e4c5fafdb859d"),
    ]

    @Test(arguments: cases)
    func compilesAsXcode(name: String, document: String, nib: String, size: Int, digest: String) throws {
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        let data = try #require(compiled[nib], "\(name)")
        #expect(data.count == size, "\(name)")
        #expect(VariationTests.digest(data) == digest, "\(name)")
    }
}
