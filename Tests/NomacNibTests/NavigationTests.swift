import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for navigation controllers, navigation items and bar button items
/// (`.github/scripts/nib_experiments.py` round 24, `navigation_scene`): sizes and SHA-256 digests of
/// Xcode's controller nibs.
@Suite struct NavigationTests {
    static func navigation(root: Int = 1, attributes: String = "", barAttributes: String = "", extra: String = "", y: String = "59") -> String {
        """
            <scene sceneID="nvs-aa-aaa">
                <objects>
                    <navigationController id="nvc-aa-aaa"\(attributes) sceneMemberID="viewController">
        \(extra)                <navigationBar key="navigationBar" contentMode="scaleToFill"\(barAttributes) id="nvb-aa-aaa">
                            <rect key="frame" x="0.0" y="\(y)" width="393" height="44"/>
                            <autoresizingMask key="autoresizingMask"/>
                        </navigationBar>
                        <connections>
                            <segue destination="vc\(root)-aa-aaa" kind="relationship" relationship="rootViewController" id="rel-aa-aaa"/>
                        </connections>
                    </navigationController>
                    <placeholder placeholderIdentifier="IBFirstResponder" id="nfr-aa-aaa" sceneMemberID="firstResponder"/>
                </objects>
                <point key="canvasLocation" x="-400" y="0"/>
            </scene>

        """
    }

    static func item(_ title: String = "Title", attributes: String = "", items: String = "", id: String = "nvi-aa-aaa") -> String {
        items.isEmpty ? "<navigationItem key=\"navigationItem\" title=\"\(title)\"\(attributes) id=\"\(id)\"/>\n"
            : "<navigationItem key=\"navigationItem\" title=\"\(title)\"\(attributes) id=\"\(id)\">\n\(items)</navigationItem>\n"
    }

    static func barItem(_ key: String, _ system: String, _ number: Int, action: String? = nil, attributes: String = "") -> String {
        guard let action else { return "<barButtonItem key=\"\(key)\" systemItem=\"\(system)\"\(attributes) id=\"bbi-aa-aa\(number)\"/>\n" }
        return "<barButtonItem key=\"\(key)\" systemItem=\"\(system)\"\(attributes) id=\"bbi-aa-aa\(number)\">\n<connections>\n"
            + "<action selector=\"\(action)\" destination=\"vc1-aa-aaa\" id=\"act-aa-aa\(number)\"/>\n</connections>\n</barButtonItem>\n"
    }

    static func storyboard(initial: String = "nvc-aa-aaa", _ scenes: String...) -> String {
        StoryboardCompilerTests.storyboard(scenes.joined())
            .replacingOccurrences(of: #"initialViewController="BYZ-38-t0r""#, with: "initialViewController=\"\(initial)\"")
    }

    static let navigationNib = "UINavigationController-nvc-aa-aaa.nib"
    static let cases: [(String, String, [(String, Int, String)])] = [
        ("sb-nav", storyboard(navigation(), SceneTests.scene(1)), [
            ("Info.plist", 276, "02c1faeee9409d348f4376ec556236114e81c4b51dae2d18e9e8301ed6bad3d7"),
            (navigationNib, 1697, "921e1fed13013c8074d6ed1036bd529eee5fb94d1c47253e840fc5d508e6e3b6"),
        ]),
        ("sb-nav-tofu", storyboard(navigation(attributes: #" automaticallyAdjustsScrollViewInsets="NO""#, barAttributes: #" largeTitles="YES""#,
                                              extra: "<toolbarItems/>\n").replacingOccurrences(of: "<connections>\n", with: "<nil name=\"viewControllers\"/>\n<connections>\n"),
                                   SceneTests.scene(1)), [
            (navigationNib, 1768, "d96c6241737b5104f6cfe1ec18f17cc647b566cef3fb66056b5190641f010675"),
        ]),
        ("sb-nav-bar-frame", storyboard(navigation(y: "20"), SceneTests.scene(1)), [
            (navigationNib, 1697, "37af41a9c218c3423a8b71089d9f197b296c0bb64e501843a1352cab156e728a"),
        ]),
        ("sb-nav-item-large-never", storyboard(navigation(), SceneTests.scene(1, afterView: item(attributes: #" largeTitleDisplayMode="never""#))), [
            (navigationNib, 1840, "58996646f2eb284e9466649bb814801e910a432ac2e368a2a7a79159111fe8cb"),
        ]),
        ("sb-bar-cancel-done", storyboard(navigation(), SceneTests.scene(1, afterView: item(items: barItem("leftBarButtonItem", "cancel", 1, action: "didPressCancel:")
            + barItem("rightBarButtonItem", "done", 2, action: "didPressDone:", attributes: #" enabled="NO""#)))), [
            (navigationNib, 2191, "2e015ed51c2a120cfc7b6588efa2684ab2934c05c8c61f22d0e114e7f4864df8"),
        ]),
        ("sb-bar-cancel-outlet", storyboard(navigation(), SceneTests.scene(1, afterView: item(items: barItem("leftBarButtonItem", "cancel", 1, action: "didPressCancel:")),
                                                                         connections: "<outlet property=\"cancelItem\" destination=\"bbi-aa-aa1\" id=\"out-aa-aa1\"/>\n")), [
            (navigationNib, 2105, "117ccc212e5bb8a3696b99b697150e3d5f47c0cfb70194b4233d53ab3e18b6bb"),
        ]),
        ("sb-nav-show", storyboard(navigation(), SceneTests.scene(1, afterView: item(), connections: SceneTests.segue(2, "show", 1, "Detail")),
                                   SceneTests.scene(2, afterView: item("Detail", id: "nvi-aa-aa2"))), [
            ("Info.plist", 351, "74c06d2c1bb23e4e0df58ae51d6a630b4cb372073bd64e311db6c9ef6e43907d"),
            (navigationNib, 2131, "b8c05219e1d637f4ea1e17466de488f065637be23351680ecf9ee88c315ddd22"),
            ("UIViewController-vc2-aa-aaa.nib", 1076, "b22150e830882e0a1f9abc6fbc23734f2c38d16042ff08757df7f318013b2a52"),
        ]),
        ("sb-segue-present-nav", storyboard(initial: "vc1-aa-aaa", SceneTests.scene(1, connections: SceneTests.segue(0, "presentation", 1, "Present")
            .replacingOccurrences(of: "vc0-aa-aaa", with: "nvc-aa-aaa")), navigation(root: 2), SceneTests.scene(2, afterView: item())), [
            ("Info.plist", 345, "406a1a62b089167f3c2fcb75b6ae822deffba72772a00775aba4352fa6fa3139"),
            (navigationNib, 1776, "7f887fc9b8f155378cf309b6f33df6f0169cf03cf43ca68ffed46780466b45f2"),
            ("UIViewController-vc1-aa-aaa.nib", 1179, "53df8d8b1441c60257a0449c94d0ac25f1e512f588a38473a8522b3bd0f23fa4"),
        ]),
        ("sb-nav-item-no-nav", storyboard(initial: "vc1-aa-aaa", SceneTests.scene(1, afterView: item())), [
            ("UIViewController-vc1-aa-aaa.nib", 1139, "abd120f7443b526bcf8ec40801a014dd2913da2955d3a9626a405734780a3ba8"),
        ]),
        ("sb-nav-title", storyboard(navigation(attributes: #" title="Accounts""#), SceneTests.scene(1, afterView: item())),
         [(navigationNib, 1860, "5cf24d1bce378ac903233600ab7a8ac505b3206b4a8296afbd87c44e157dcfd6")]),
        ("sb-nav-bar-flags", storyboard(navigation(barAttributes: #" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES""#), SceneTests.scene(1, afterView: item())),
         [(navigationNib, 1883, "d48b0cbcad338b65ca61cccf98ee5a3334e746406c829bd20139db03601d624d")]),
        ("sb-nav-bar-insets-no", storyboard(navigation(barAttributes: #" insetsLayoutMarginsFromSafeArea="NO""#), SceneTests.scene(1, afterView: item())),
         [(navigationNib, 1881, "7e5f37952cab41b5cf71b196a06711b0ee2d8f7b2720ae9000bd62d562f6c033")]),
        ("sb-nav-item-no-title-add", storyboard(navigation(), SceneTests.scene(1, afterView: "<navigationItem key=\"navigationItem\" id=\"nvi-aa-aaa\">\n"
                                                                                    + barItem("rightBarButtonItem", "add", 1) + "</navigationItem>\n")),
         [(navigationNib, 1877, "28b4bc89652a1092baf63659c8f169636a50361c349504d1cf7dbba23c946668")]),
    ]

    /// The root controller archived in the navigation controller's nib, the bar of IB's geometry,
    /// the item's bar referred to conditionally, the nib's one empty array, actions last.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, document: String, files: [(String, Int, String)]) throws {
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        for (file, size, digest) in files + [("vc1-aa-aaa-view-vw1-aa-aaa.nib", SceneTests.view.0, SceneTests.view.1)] {
            let data = try #require(compiled[file], "\(name) \(file)")
            #expect(data.count == size, "\(name) \(file)")
            #expect(VariationTests.digest(data) == digest, "\(name) \(file)")
        }
    }

    @Test(arguments: [
        (storyboard(navigation(), SceneTests.scene(1), SceneTests.scene(2, connections: SceneTests.segue(1, "show", 1, "Back"))),
         "a navigation controller's root that is no plain view controller or that other controllers reach"),
        (storyboard(initial: "vc1-aa-aaa", SceneTests.scene(1, afterView: item(items: barItem("rightBarButtonItem", "pause", 1)))),
         "a bar button item of a system item not observed yet"),
        (storyboard(navigation(), SceneTests.scene(1, afterView: item(items: barItem("rightBarButtonItem", "pause", 1)))),
         "a bar button item of a system item not observed yet"),
    ])
    func refusesWhatIsNotObservedYet(document: String, what: String) {
        #expect(throws: NomacError("nomac does not compile \(what) yet (BACKLOG B-261)", path: "/tmp/Main.storyboard")) {
            try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        }
    }
}
