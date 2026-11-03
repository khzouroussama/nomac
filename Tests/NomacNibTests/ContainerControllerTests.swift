import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for tab bar and split view controllers in storyboards
/// (`.github/scripts/nib_experiments.py` rounds 71 to 74, `sb-tab-*`, `sb-split-*`): sizes and
/// SHA-256 digests of Xcode's container nibs.
@Suite struct ContainerControllerTests {
    static func tab(_ children: [String] = ["vc1-aa-aaa", "vc2-aa-aaa"], attributes: String = "") -> String {
        let segues = children.enumerated().map {
            "<segue destination=\"\($0.element)\" kind=\"relationship\" relationship=\"viewControllers\" id=\"tb\($0.offset)-aa-aaa\"/>\n"
        }.joined()
        return "<scene sceneID=\"tbs-aa-aaa\">\n<objects>\n<tabBarController id=\"tab-aa-aaa\"\(attributes) sceneMemberID=\"viewController\">\n"
            + #"<tabBar key="tabBar" contentMode="scaleToFill" id="tbr-aa-aaa">"# + "\n" + #"<rect key="frame" x="0.0" y="0.0" width="1000" height="1000"/>"# + "\n"
            + #"<autoresizingMask key="autoresizingMask"/>"# + "\n</tabBar>\n<connections>\n\(segues)</connections>\n</tabBarController>\n"
            + #"<placeholder placeholderIdentifier="IBFirstResponder" id="tfr-bb-aaa" sceneMemberID="firstResponder"/>"# + "\n</objects>\n"
            + #"<point key="canvasLocation" x="-800" y="0"/>"# + "\n</scene>\n"
    }

    static func item(_ number: Int, _ attributes: String) -> String {
        "<tabBarItem key=\"tabBarItem\"\(attributes) id=\"tbi-aa-aa\(number)\"/>\n"
    }

    static func navigation(_ letters: String, root: Int, item: String = "") -> String {
        ["nvs", "nvc", "nvb", "nfr", "rel"].reduce(NavigationTests.navigation(root: root, extra: item)) {
            $0.replacingOccurrences(of: "\($1)-aa-aaa", with: "\($1)-\(letters)-aaa")
        }
    }

    static func navigationItem(_ title: String, _ number: Int) -> String {
        "<navigationItem key=\"navigationItem\" title=\"\(title)\" id=\"nvi-aa-aa\(number)\"/>\n"
    }

    static func split(master: String = "vc1-aa-aaa", detail: String = "vc2-aa-aaa", attributes: String = "") -> String {
        "<scene sceneID=\"sps-aa-aaa\">\n<objects>\n<splitViewController id=\"spl-aa-aaa\"\(attributes) sceneMemberID=\"viewController\">\n<connections>\n"
            + "<segue destination=\"\(master)\" kind=\"relationship\" relationship=\"masterViewController\" id=\"spm-aa-aaa\"/>\n"
            + "<segue destination=\"\(detail)\" kind=\"relationship\" relationship=\"detailViewController\" id=\"spd-aa-aaa\"/>\n"
            + "</connections>\n</splitViewController>\n"
            + #"<placeholder placeholderIdentifier="IBFirstResponder" id="sfr-aa-aaa" sceneMemberID="firstResponder"/>"# + "\n</objects>\n"
            + #"<point key="canvasLocation" x="-800" y="0"/>"# + "\n</scene>\n"
    }

    static func storyboard(_ scenes: String..., initial: String = "tab-aa-aaa", resources: Bool = false) -> String {
        let document = TableViewControllerTests.storyboard(initial: initial, scenes.joined())
        guard resources else { return document }
        return document.replacingOccurrences(of: "    </scenes>\n", with: "    </scenes>\n<resources>\n"
                                             + #"<image name="square" catalog="system" width="128" height="114"/>"# + "\n"
                                             + #"<image name="circle" catalog="system" width="128" height="121"/>"# + "\n</resources>\n")
    }

    static let nib = "UITabBarController-tab-aa-aaa.nib"
    static let cases: [(String, String, String, Int, String)] = [
        ("sb-tab-plain", storyboard(tab(), SceneTests.scene(1), SceneTests.scene(2)), nib, 1747,
         "4dd0fc5c73eb1b9e8056a7524d91625e8ea69cc8a7676f147f8d6a5f46f38dd2"),
        ("sb-tab-items", storyboard(tab(), SceneTests.scene(1, afterView: item(1, #" title="First" image="square" catalog="system""#)),
                                    SceneTests.scene(2, afterView: item(2, #" title="Second" image="circle" catalog="system""#)), resources: true),
         nib, 2031, "6b5d206e2c6377c2de1b01dca6fdbd3921b189913024e937ff646d5c1c17b3a2"),
        ("sb-tab-order", storyboard(tab(["vc2-aa-aaa", "vc1-aa-aaa"]), SceneTests.scene(1), SceneTests.scene(2)), nib, 1747,
         "7a75fc505683661f2015eebfe02ee06fb84491389dfd58c9bad16fef9931e46e"),
        ("sb-tab-three", storyboard(tab(["vc1-aa-aaa", "vc2-aa-aaa", "vc3-aa-aaa"]), SceneTests.scene(1), SceneTests.scene(2), SceneTests.scene(3)),
         nib, 1891, "a57a245e9cba1d61ed83f62508370e05cbcaa5d3464e52f3cd7805031ad239d5"),
        ("sb-tab-custom", storyboard(tab(attributes: #" customClass="MainTabs" customModule="T" customModuleProvider="target""#),
                                     SceneTests.scene(1), SceneTests.scene(2)),
         nib, 1768, "3260f631277df46d537096390e8beb14b6d2c9eb2cc4729a22c1558de77e48de"),
        ("sb-tab-identifier", storyboard(tab(attributes: #" storyboardIdentifier="Tabs""#), SceneTests.scene(1), SceneTests.scene(2)),
         "Tabs.nib", 1786, "5ea909075f75b0605de31aa3e6e53b899d9dc9d619cd926d9ffabb29fb69c89b"),
        ("sb-tab-child-title", storyboard(tab(), SceneTests.scene(1, attributes: #" title="One""#), SceneTests.scene(2)), nib, 1776,
         "e2e4ad8e6ca989ceaf1f9c910321a50b2652d1f2e34144b7ddeb954775b5232e"),
        ("sb-tab-nav-item", storyboard(tab(["nvc-aa-aaa", "vc2-aa-aaa"]), navigation("aa", root: 1, item: item(1, #" title="Home" image="square" catalog="system""#)),
                                       SceneTests.scene(1), SceneTests.scene(2), resources: true),
         nib, 2453, "5f6c5244afaeb272dc163f6af6fd9fcf51cd957a87a74543b8eab97074475f11"),
        ("sb-tab-nav-two", storyboard(tab(["nvc-aa-aaa", "nvc-bb-aaa"]), navigation("aa", root: 1, item: item(1, #" title="First""#)),
                                      navigation("bb", root: 2, item: item(2, #" title="Second""#)), SceneTests.scene(1, afterView: navigationItem("One", 1)),
                                      SceneTests.scene(2, afterView: navigationItem("Two", 2))),
         nib, 2722, "9d5b39cc427ccf19826763d70d2e894d20ac47ec5e18d72ff2baa874846fa0e4"),
        ("sb-tab-plain-then-nav", storyboard(tab(["vc2-aa-aaa", "nvc-aa-aaa"]), navigation("aa", root: 1), SceneTests.scene(1), SceneTests.scene(2)),
         nib, 2222, "016665d95ba6fad7172935dfc3dfb4cc942fa33e15f56bce7cf169a258a76114"),
    ]

    static let splitNib = "UISplitViewController-spl-aa-aaa.nib"
    static let splitCases: [(String, String, String, Int, String)] = [
        ("sb-split-plain", storyboard(split(), SceneTests.scene(1), SceneTests.scene(2), initial: "spl-aa-aaa"), splitNib, 1240,
         "3c098e684ff57daee5850ebaae42f91d3a9b226e26d1f7740bd46ddbd6141c52"),
        ("sb-split-segue-order", storyboard(split(master: "vc2-aa-aaa", detail: "vc1-aa-aaa"), SceneTests.scene(1), SceneTests.scene(2), initial: "spl-aa-aaa"),
         splitNib, 1240, "420b65023699a8e3cb10f4c340a86faad1d145e131a8a60fa2825c5a8b3a4707"),
        ("sb-split-title", storyboard(split(attributes: #" title="Notes""#), SceneTests.scene(1), SceneTests.scene(2), initial: "spl-aa-aaa"), splitNib, 1265,
         "ce36f62283df4ec2cd5eb4481bd310ec1875f6250093bb4fc6fb04a4ca752b0d"),
        ("sb-split-identifier-title", storyboard(split(attributes: #" title="Notes" storyboardIdentifier="Root""#), SceneTests.scene(1), SceneTests.scene(2),
                                                 initial: "spl-aa-aaa"),
         "Root.nib", 1304, "f274abb6e24c0e5da0ac8fb0ea44d5d9c8c6eacc7185d47220c24c9b083df029"),
        ("sb-split-custom", storyboard(split(attributes: #" customClass="Splits" customModule="T" customModuleProvider="target""#), SceneTests.scene(1),
                                       SceneTests.scene(2), initial: "spl-aa-aaa"),
         splitNib, 1259, "23270d5b167a51c34105a5fcf890191b91fbe494c6c7bb69e7df655df56dae41"),
        ("sb-split-nav-detail", storyboard(split(detail: "nvc-aa-aaa"), navigation("aa", root: 2), SceneTests.scene(1), SceneTests.scene(2), initial: "spl-aa-aaa"),
         splitNib, 1950, "d25e8d3d014b3985eb7148efc57c2a8e2a12c9724d41bcfc73bf1bcf48f85a8f"),
        ("sb-split-nav-both", storyboard(split(master: "nvc-aa-aaa", detail: "nvc-bb-aaa"), navigation("aa", root: 1), navigation("bb", root: 2),
                                         SceneTests.scene(1, afterView: navigationItem("Notes", 1)), SceneTests.scene(2, afterView: navigationItem("Detail", 2)),
                                         initial: "spl-aa-aaa"),
         splitNib, 2426, "3a0a6a89d90a4491865c561bea767513179760b060adce6b948601e6b88751b4"),
    ]

    static func show(_ number: Int, _ identifier: String) -> String {
        "<segue destination=\"vc3-aa-aaa\" kind=\"show\" identifier=\"\(identifier)\" id=\"tsh-aa-aa\(number)\"/>\n"
    }

    static let tableMaster = navigation("aa", root: 0).replacingOccurrences(of: "vc0-aa-aaa", with: "tvc-aa-aaa")
    static func tableScene(_ destination: String) -> String {
        TableViewControllerTests.scene(TableViewControllerTests.prototypes(CellSegueTests.withConnections(TableViewControllerTests.cell(1),
            CellSegueTests.segue("showDetail", "showDetail").replacingOccurrences(of: "vc2-aa-aaa", with: destination))),
                                       afterView: navigationItem("Notes", 1))
    }

    static let segueCases: [(String, String, String, Int, String)] = [
        ("sb-tab-two-show", storyboard(tab(), SceneTests.scene(1, connections: show(1, "Open")), SceneTests.scene(2, connections: show(2, "Two")), SceneTests.scene(3)),
         nib, 2116, "595f3b3104a873f8082c7429effe7d15582167caf60a31dd6a0acec2d54becd1"),
        ("sb-tab-child-show-item", storyboard(tab(), SceneTests.scene(1, afterView: item(1, #" title="First""#), connections: show(1, "Open")), SceneTests.scene(2),
                                              SceneTests.scene(3)),
         nib, 2065, "cda73931adb6f912e289648e676874220dbb4e3e44f40adaaadbdb2e5849236b"),
        ("sb-tab-nav-root-show", storyboard(tab(["nvc-aa-aaa", "vc2-aa-aaa"]), navigation("aa", root: 1), SceneTests.scene(1, connections: show(1, "Open")),
                                            SceneTests.scene(2), SceneTests.scene(3)),
         nib, 2517, "d72dbcfa704cacc928321ecd231e1c2bd158fc4f7265390248d77c2ab083d111"),
        ("sb-split-showdetail", storyboard(split(master: "nvc-aa-aaa"), tableMaster, tableScene("vc2-aa-aaa"), SceneTests.scene(2), initial: "spl-aa-aaa"),
         splitNib, 2505, "e3054501e114d6d61f40ea9815fb691e1d445d2496aa046e5faa1d90a0d32a85"),
        ("sb-split-showdetail (detail)", storyboard(split(master: "nvc-aa-aaa"), tableMaster, tableScene("vc2-aa-aaa"), SceneTests.scene(2), initial: "spl-aa-aaa"),
         "UIViewController-vc2-aa-aaa.nib", 860, "77ea33d9265b1240144062a8c9255bfda38b8956e9a7efea85bcfdd94b4957bf"),
        ("sb-split-showdetail-nav", storyboard(split(master: "nvc-aa-aaa", detail: "nvc-bb-aaa"), tableMaster, navigation("bb", root: 2), tableScene("nvc-bb-aaa"),
                                               SceneTests.scene(2, afterView: navigationItem("Detail", 2)), initial: "spl-aa-aaa"),
         splitNib, 2845, "4614a29b1a5ef6c47fe369f0b4c836ec560a5bbbd624d1fb631d45abf8854c53"),
        ("sb-split-showdetail-nav (detail)", storyboard(split(master: "nvc-aa-aaa", detail: "nvc-bb-aaa"), tableMaster, navigation("bb", root: 2),
                                                        tableScene("nvc-bb-aaa"), SceneTests.scene(2, afterView: navigationItem("Detail", 2)), initial: "spl-aa-aaa"),
         "UINavigationController-nvc-bb-aaa.nib", 1777, "d1612825ce43f30ac6d4c6e95dcf6b54d9f191b55be745c5ab3e5fa9cb75161e"),
    ]

    /// The children inlined, tab bar controllers' with their tab bar items, navigation children
    /// with their roots; split view controllers' master then detail, all objects listing them last
    /// first; one placeholder per inlined controller, the container's and navigation controllers'
    /// outlets before the view controllers', their templates' outlets last; a child a segue reaches
    /// also in its own nib.
    @Test(arguments: cases + splitCases + segueCases)
    func compilesAsXcode(name: String, document: String, nib: String, size: Int, digest: String) throws {
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        let data = try #require(compiled[nib], "\(name)")
        #expect(data.count == size, "\(name)")
        #expect(VariationTests.digest(data) == digest, "\(name)")
    }

    /// A split view controller's title in an `.lproj` folder is localizable, keyed by its id.
    @Test func localizedSplitTitle() throws {
        let document = Self.storyboard(Self.split(attributes: #" title="Notes""#), SceneTests.scene(1), SceneTests.scene(2), initial: "spl-aa-aaa")
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Base.lproj/Main.storyboard", options: StoryboardCompilerTests.options)
        let data = try #require(compiled[Self.splitNib])
        #expect(data.count == 1344)
        #expect(VariationTests.digest(data) == "69655792f5c12a770fccddabbfdc51eebb7e31f4e2a2f202903441f01cfc38c7")
    }

    /// A child with outlets to its view has its own external objects (`sb-tab-child-outlet`).
    @Test func childOutlets() throws {
        let child = TriggeredSegueTests.scene(1, buttons: TriggeredSegueTests.subview, connections: TriggeredSegueTests.boxOutlet, exit: false)
        let document = Self.storyboard(Self.tab(), child, SceneTests.scene(2))
        let data = try #require(try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)[Self.nib])
        #expect(data.count == 1791)
        #expect(VariationTests.digest(data) == "230da07eac9d5269a86567ea51a2ff04bfa4647c6014e496223fc1655939f211")
    }

    /// A view controller child's navigation item is not observed yet.
    @Test func refusesChildNavigationItem() {
        let child = SceneTests.scene(1, afterView: NavigationTests.item(items: NavigationTests.barItem("rightBarButtonItem", "add", 1)))
        let document = Self.storyboard(Self.tab(["vc1-aa-aaa"]), child)
        #expect(throws: NomacError.self) {
            try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        }
    }
}
