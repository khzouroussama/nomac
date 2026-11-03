import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for segues buttons and bar button items trigger, unwind segues,
/// popovers and a navigation controller's root with its own identifier
/// (`.github/scripts/nib_experiments.py` round 77): sizes and SHA-256 digests of Xcode's nibs.
@Suite struct TriggeredSegueTests {
    typealias Navigation = NavigationTests

    static func button(_ number: Int, y: Int, _ segue: String) -> String {
        "<button opaque=\"NO\" contentMode=\"scaleToFill\" contentHorizontalAlignment=\"center\" contentVerticalAlignment=\"center\" buttonType=\"system\" "
            + "lineBreakMode=\"middleTruncation\" id=\"btn-aa-aa\(number)\">\n<rect key=\"frame\" x=\"20\" y=\"\(y)\" width=\"120\" height=\"44\"/>\n"
            + #"<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>"# + "\n" + #"<state key="normal" title="Go"/>"#
            + "\n<connections>\n\(segue)\n</connections>\n</button>\n"
    }

    /// A scene whose view holds `buttons`, with an exit.
    static func scene(_ number: Int, attributes: String = "", buttons: String = "", afterView: String = "", connections: String = "", exit: Bool = true) -> String {
        let resizing = #"<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>"#
        let scene = SceneTests.scene(number, attributes: attributes, afterView: afterView, connections: connections)
            .replacingOccurrences(of: resizing, with: resizing + (buttons.isEmpty ? "" : "\n<subviews>\n\(buttons)</subviews>"))
        guard exit else { return scene }
        return scene.replacingOccurrences(of: "id=\"fr\(number)-aa-aaa\" sceneMemberID=\"firstResponder\"/>",
                                          with: "id=\"fr\(number)-aa-aaa\" sceneMemberID=\"firstResponder\"/>\n<exit id=\"ext-aa-aaa\" userLabel=\"Exit\" sceneMemberID=\"exit\"/>")
    }

    static let subview = "<view contentMode=\"scaleToFill\" id=\"sub-vi-ew1\">\n" + #"<rect key="frame" x="10" y="10" width="50" height="50"/>"# + "\n"
        + #"<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>"# + "\n</view>\n"
    static let boxOutlet = #"<outlet property="box" destination="sub-vi-ew1" id="out-aa-aaa"/>"# + "\n"

    static let unwind = #"<segue destination="ext-aa-aaa" kind="unwind" identifier="unwindBack" unwindAction="back:" id="uws-aa-aaa"/>"#
    static let open = #"<segue destination="vc2-aa-aaa" kind="presentation" identifier="Open" id="osg-aa-aaa"/>"# + "\n"
    static let arrowsUp = "<popoverArrowDirection key=\"popoverArrowDirection\" up=\"YES\"/>\n"
    static let arrowsAll = "<popoverArrowDirection key=\"popoverArrowDirection\" up=\"YES\" down=\"YES\" left=\"YES\" right=\"YES\"/>\n"
    static let popoverBar = "<barButtonItem key=\"rightBarButtonItem\" systemItem=\"add\" id=\"bbi-aa-aa1\">\n<connections>\n"
        + #"<segue destination="vc2-aa-aaa" kind="popoverPresentation" identifier="create" popoverAnchorBarButtonItem="bbi-aa-aa1" id="pop-aa-aaa">"# + "\n"
        + arrowsAll + "</segue>\n</connections>\n</barButtonItem>\n"

    static let toolbar = "<toolbar key=\"toolbar\" opaque=\"NO\" clearsContextBeforeDrawing=\"NO\" contentMode=\"scaleToFill\" id=\"tbr-aa-aaa\">\n"
        + #"<autoresizingMask key="autoresizingMask"/>"# + "\n</toolbar>\n"
    static let createItems = "<barButtonItem key=\"leftBarButtonItem\" title=\"Cancel\" id=\"bbi-aa-aa2\">\n<connections>\n" + unwind
        + "\n</connections>\n</barButtonItem>\n<barButtonItem key=\"rightBarButtonItem\" title=\"Create\" id=\"bbi-aa-aa1\">\n<connections>\n"
        + #"<action selector="save" destination="vc2-aa-aaa" id="act-aa-aa1"/>"# + "\n</connections>\n</barButtonItem>\n"

    static let cases: [(String, String, [(String, Int, String)])] = [
        ("sb-nav-root-button-show", Navigation.storyboard(Navigation.navigation(), scene(1, buttons: button(1, y: 100,
            #"<segue destination="vc2-aa-aaa" kind="show" identifier="Attach" id="bsg-aa-aaa"/>"#), afterView: Navigation.item("Root"), exit: false), SceneTests.scene(2)),
         [("UINavigationController-nvc-aa-aaa.nib", 2169, "20d3d371e1f65aa34341039d176f5fe26ca6a05c6245f80a9d304ee0f3382a3c")]),
        ("sb-nav-root-modal", Navigation.storyboard(Navigation.navigation(), SceneTests.scene(1, attributes: #" modalPresentationStyle="formSheet" hidesBottomBarWhenPushed="YES""#,
                                                                                               afterView: Navigation.item("Root"), connections: SceneTests.segue(2, "show", 1, "Open")),
                                                    SceneTests.scene(2)),
         [("UINavigationController-nvc-aa-aaa.nib", 2185, "6ddbe6a2875343e74e63428dbe9894f8f58ab7f01041443212c99d82303e5cbe")]),
        ("sb-nav-identifier", Navigation.storyboard(Navigation.navigation(attributes: #" storyboardIdentifier="Nav""#), SceneTests.scene(1, afterView: Navigation.item("Root"))),
         [("Nav.nib", 1877, "ec7a83ccb494ff01f1fe0b56bc648e2c88312e9a215b7762caaef795cefbd1bf")]),
        ("sb-nav-toolbar", Navigation.storyboard(Navigation.navigation(extra: "<toolbarItems/>\n").replacingOccurrences(of: "</navigationBar>\n", with: "</navigationBar>\n" + toolbar),
                                                 SceneTests.scene(1, afterView: Navigation.item("Root"))),
         [("UINavigationController-nvc-aa-aaa.nib", 1993, "4745c37ba4dfd939cd10ca7d2ba1fd3e6106858d475d9708c4012371c559f5c7")]),
        ("sb-standalone-bar-items", SceneTests.storyboard(SceneTests.scene(1), scene(2, attributes: #" storyboardIdentifier="Create""#,
                                                                                     afterView: Navigation.item("Create", items: createItems))),
         [("Create.nib", 1727, "d29dbb38571e9f371f4532498d7c7a4ef45bf030ff267f1e0a3c5551a4d5c5e7")]),
        ("sb-vc-title-nav", Navigation.storyboard(Navigation.navigation(), SceneTests.scene(1, attributes: #" title="Detail""#)),
         [("UINavigationController-nvc-aa-aaa.nib", 1816, "f2b513345699b921cb981f881a1d3791a295fc8cb77f836a396ecd2a57f2d4df")]),
        ("sb-nav-root-title", Navigation.storyboard(Navigation.navigation(), SceneTests.scene(1, attributes: #" title="Detail""#, afterView: Navigation.item("Detail"))),
         [("UINavigationController-nvc-aa-aaa.nib", 1847, "e56048b611c9294163c5587d047b983e78115589490bcdab9924f9489c9a565e")]),
        ("sb-button-two", SceneTests.storyboard(scene(1, buttons: button(1, y: 100, #"<segue destination="vc2-aa-aaa" kind="show" identifier="A" id="Qx4-pp-k2L"/>"#)
                                                     + button(2, y: 200, #"<segue destination="vc2-aa-aaa" kind="presentation" identifier="B" id="a1B-zz-9Yt"/>"#)),
                                                SceneTests.scene(2)),
         [("UIViewController-vc1-aa-aaa.nib", 1389, "c543b8eeb56d722357decd8c80f839fd28610c1d5df83d6ed60b916b9fee6632"),
          ("vc1-aa-aaa-view-vw1-aa-aaa.nib", 2919, "a6ae798dfa3b6020bc2bbc5c49a653b20c8673bdff453078d68abcc6b62a8363")]),
        ("sb-button-outlet", SceneTests.storyboard(scene(1, buttons: button(1, y: 100, #"<segue destination="vc2-aa-aaa" kind="show" id="bsg-aa-aaa"/>"#),
                                                         connections: #"<outlet property="go" destination="btn-aa-aa1" id="out-aa-aaa"/>"# + "\n"),
                                                   SceneTests.scene(2)),
         [("UIViewController-vc1-aa-aaa.nib", 1262, "b730a4ec9488d11411fa4458ea850fba9810103204171c90399464cc813aa443"),
          ("vc1-aa-aaa-view-vw1-aa-aaa.nib", 2792, "8d6171ce03d864bbaaec252c040f066b877a8d47bb14e82ce368aa0cbdf1a213")]),
        ("sb-unwind-button-named", SceneTests.storyboard(SceneTests.scene(1, connections: open), scene(2, buttons: button(1, y: 100, unwind))),
         [("UIViewController-vc2-aa-aaa.nib", 1134, "9c427cd947d5a8927e89323faad007e3251b2487e5bc3e3b823c07b3bed4c729"),
          ("vc2-aa-aaa-view-vw2-aa-aaa.nib", 2706, "a9ae41e8e02264ec899e6161d888b681194797234db495801892e82a92cad9e9")]),
        ("sb-unwind-controller", SceneTests.storyboard(SceneTests.scene(1, connections: open), scene(2, connections: unwind + "\n")),
         [("UIViewController-vc2-aa-aaa.nib", 1095, "8b80d5fad5d75db6e777099124d40fcf83e5e03a6ef1a2e5b5c4730dad3c6343")]),
        ("sb-popover-arrow-up", SceneTests.storyboard(scene(1, buttons: button(1, y: 100,
            #"<segue destination="vc2-aa-aaa" kind="popoverPresentation" identifier="pick" popoverAnchorView="btn-aa-aa1" id="pop-aa-aaa">"# + "\n" + arrowsUp + "</segue>")),
                                                      SceneTests.scene(2)),
         [("UIViewController-vc1-aa-aaa.nib", 1306, "fca8d2281db59a6b65b76cbf2e3d2267728b13b4eb3fcc1c7309f607256ca1f5"),
          ("vc1-aa-aaa-view-vw1-aa-aaa.nib", 2751, "c08f22544e0a8457f28833e03e5e89bb097bab8db2dbdb2782b7f21f69230bd0")]),
        ("sb-popover-bar-item", Navigation.storyboard(Navigation.navigation(), SceneTests.scene(1, afterView: Navigation.item("Notes", items: popoverBar)),
                                                      SceneTests.scene(2)),
         [("UINavigationController-nvc-aa-aaa.nib", 2454, "6334072e7685ac9d26eb2f62cb74c32332c39f99beed0638c5c978882c979d9b")]),
        ("sb-bar-segue-then-zzz", Navigation.storyboard(Navigation.navigation(), SceneTests.scene(1, afterView: Navigation.item("Notes", items:
            "<barButtonItem key=\"leftBarButtonItem\" systemItem=\"done\" id=\"bbi-aa-aa2\">\n<connections>\n"
                + #"<segue destination="vc2-aa-aaa" kind="show" identifier="Next" id="bsg-aa-aa2"/>"# + "\n</connections>\n</barButtonItem>\n"
                + Navigation.barItem("rightBarButtonItem", "add", 1, action: "zzz:"))), SceneTests.scene(2)),
         [("UINavigationController-nvc-aa-aaa.nib", 2468, "6eabcf213ffd3952437feefbbb24b4c0cab7e0e391f7745d697a77bb346c0952")]),
        ("sb-nav-root-identifier", Navigation.storyboard(Navigation.navigation(), SceneTests.scene(1, attributes: #" storyboardIdentifier="Root""#,
                                                                                                   afterView: Navigation.item("Root"))),
         [("Root.nib", 1167, "0d7176077a5874244e1676a37d0d92b19dae9d895ba9dc4fe634bc5d466b7121"),
          ("UINavigationController-nvc-aa-aaa.nib", 1883, "baa79cf37d6ca0a2b62da4dac33739510e6325006963b00d62dca3cd690e5da8")]),
    ]

    /// A button's segue is a `perform:` action to its template's upstream placeholder, numbered
    /// after the controller's in document order, a popover's anchor an outlet of it; a bar button
    /// item's segue a `perform:` event among its item's actions, by selector; an unwind template has
    /// no destination; an identified root is also compiled on its own.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, document: String, nibs: [(String, Int, String)]) throws {
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        for (nib, size, digest) in nibs {
            let data = try #require(compiled[nib], "\(name) \(nib)")
            #expect(data.count == size, "\(name) \(nib)")
            #expect(VariationTests.digest(data) == digest, "\(name) \(nib)")
        }
    }

    /// A titled bar button item's title is localizable in an `.lproj` folder.
    @Test func localizedBarItemTitle() throws {
        let item = "<barButtonItem key=\"leftBarButtonItem\" title=\"Cancel\" id=\"bbi-aa-aa2\">\n<connections>\n"
            + #"<action selector="cancel:" destination="vc1-aa-aaa" id="act-aa-aa2"/>"# + "\n</connections>\n</barButtonItem>\n"
        let document = Navigation.storyboard(Navigation.navigation(), SceneTests.scene(1, afterView: Navigation.item("Notes", items: item)))
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Base.lproj/Main.storyboard", options: StoryboardCompilerTests.options)
        let data = try #require(compiled["UINavigationController-nvc-aa-aaa.nib"])
        #expect(data.count == 2164)
        #expect(VariationTests.digest(data) == "839f6befd88129f400d40338433f1c95c21757684a744918fcef34f8995a7450")
    }

    static func controllerSegue(_ kind: String, _ extra: String = "") -> String {
        "<segue destination=\"vc2-aa-aaa\" kind=\"\(kind)\" identifier=\"Next\"\(extra) id=\"lsg-aa-aaa\"/>\n"
    }

    static let legacyCases: [(String, String, String, Int, String)] = [
        ("sb-segue-push", Navigation.storyboard(Navigation.navigation(), SceneTests.scene(1, connections: controllerSegue("push")), SceneTests.scene(2)),
         "UINavigationController-nvc-aa-aaa.nib", 2000, "f165378558ed7a5117df5b542affef6a9bae9e9135940103cabad460a74474b0"),
        ("sb-segue-modal", SceneTests.storyboard(SceneTests.scene(1, connections: controllerSegue("modal")), SceneTests.scene(2)),
         "UIViewController-vc1-aa-aaa.nib", 1163, "ecb7796f6440a4a0a9e69e5847619c54ed549708d8ae684847c902e2318494c6"),
        ("sb-segue-custom", SceneTests.storyboard(SceneTests.scene(1, connections: controllerSegue("custom", " customClass=\"Reveal\" customModule=\"T\" customModuleProvider=\"target\"")),
                                                  SceneTests.scene(2)),
         "UIViewController-vc1-aa-aaa.nib", 1200, "8a6875ff55ceaf3d582a81c57a18fb437684c654263ba9d4deff4d0fc45adfce"),
        ("sb-segue-custom-no-module", SceneTests.storyboard(SceneTests.scene(1, connections: controllerSegue("custom", " customClass=\"SWRevealViewControllerSegueSetController\"")),
                                                            SceneTests.scene(2)),
         "UIViewController-vc1-aa-aaa.nib", 1227, "be4049e0ad190dbbda2ca417bae69f49046810194627e859207e14c82f2f9769"),
    ]

    /// Push, modal and custom segues' templates: the push one's containment context and split
    /// view controller index, the custom one's class name.
    @Test(arguments: legacyCases)
    func legacySegues(name: String, document: String, nib: String, size: Int, digest: String) throws {
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        let data = try #require(compiled[nib], "\(name)")
        #expect(data.count == size, "\(name)")
        #expect(VariationTests.digest(data) == digest, "\(name)")
    }

    /// ibtool's warnings about push and modal segues, ordered as a Foundation hash table of their
    /// ids (`sb-segue-push-three`, `sb-segue-modal-push`).
    @Test func deprecatedSegueWarnings() throws {
        let segues = ["Mmm-aa-aaa", "zzz-aa-aaa", "aaa-zz-zzz", "Qx4-pp-k2L"].map {
            "<segue destination=\"vc2-aa-aaa\" kind=\"\($0 == "aaa-zz-zzz" ? "modal" : "push")\" identifier=\"\($0)\" id=\"\($0)\"/>\n"
        }.joined()
        let document = Navigation.storyboard(Navigation.navigation(), SceneTests.scene(1, connections: segues), SceneTests.scene(2))
        let warnings = try StoryboardCompiler.compileReportingWarnings(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options).warnings
        #expect(warnings == ["zzz-aa-aaa", "aaa-zz-zzz", "Mmm-aa-aaa", "Qx4-pp-k2L"].map {
            "/tmp/Main.storyboard:\($0): warning: \($0 == "aaa-zz-zzz" ? "Modal" : "Push") segues are deprecated since iOS 8.0 [7]"
        })
    }

    /// Edges for extended layout as bits after hiding the bottom bar, before the scroll view insets
    /// (`sb-edges-hides-bottom`).
    @Test func edgesForExtendedLayout() throws {
        let document = SceneTests.storyboard(SceneTests.scene(1, attributes: " hidesBottomBarWhenPushed=\"YES\" automaticallyAdjustsScrollViewInsets=\"NO\"",
                                                              afterView: "<extendedEdge key=\"edgesForExtendedLayout\" bottom=\"YES\"/>\n"))
        let data = try #require(try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)["UIViewController-vc1-aa-aaa.nib"])
        #expect(data.count == 1029)
        #expect(VariationTests.digest(data) == "e2001e3b8e6cb11274b59efc7d61887d4b09141f751d87b0063904e0d1ac6ddb")
    }

    static let barItemCases: [(String, String, Int, String)] = [
        ("sb-bar-back-title", "<barButtonItem key=\"backBarButtonItem\" title=\"Back\" id=\"bbi-aa-aa3\"/>\n", 1931,
         "3ea3bd426f0600ff85bd704506de783867068729b9878881408081d981673ccb"),
        ("sb-bar-title-done", "<barButtonItem key=\"rightBarButtonItem\" title=\"Save\" style=\"done\" id=\"bbi-aa-aa1\"/>\n", 1971,
         "90c5456223a70ee81296f5666c684217824a308c12f9b006f3d94e9798f10f82"),
        ("sb-bar-system-trash", "<barButtonItem key=\"rightBarButtonItem\" systemItem=\"trash\" id=\"bbi-aa-aa1\"/>\n", 1988,
         "ead85d7590e96afe6c3b06c8f3f753485ad7b9ad4553c65b1f59e5b93ff6a875"),
        ("sb-bar-done-style-disabled", "<barButtonItem key=\"rightBarButtonItem\" enabled=\"NO\" style=\"done\" systemItem=\"done\" id=\"bbi-aa-aa1\"/>\n", 1976,
         "1c9dd7c27c6d761a04453bfdb8ed01baeedc30337efadf732c82251c0a3e0c13"),
    ]

    /// Back items, the done style and the system items' values.
    @Test(arguments: barItemCases)
    func barButtonItems(name: String, item: String, size: Int, digest: String) throws {
        let document = Navigation.storyboard(Navigation.navigation(), SceneTests.scene(1, afterView: Navigation.item("Root", items: item)))
        let data = try #require(try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)["UINavigationController-nvc-aa-aaa.nib"])
        #expect(data.count == size, "\(name)")
        #expect(VariationTests.digest(data) == digest, "\(name)")
    }

    /// A controller without a view: no external objects, no nib name, no view nib (`sb-vc-no-view`).
    @Test func controllerWithoutView() throws {
        let scene = "<scene sceneID=\"sc1-aa-aaa\">\n<objects>\n<viewController title=\"Image\" id=\"vc1-aa-aaa\" sceneMemberID=\"viewController\">\n"
            + "<freeformSimulatedSizeMetrics key=\"simulatedDestinationMetrics\"/>\n<size key=\"freeformSize\" width=\"320\" height=\"528\"/>\n</viewController>\n"
            + "<placeholder placeholderIdentifier=\"IBFirstResponder\" id=\"fr1-aa-aaa\" sceneMemberID=\"firstResponder\"/>\n</objects>\n</scene>\n"
        let compiled = try StoryboardCompiler.compile(Data(SceneTests.storyboard(scene).utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        #expect(compiled.keys.sorted() == ["Info.plist", "UIViewController-vc1-aa-aaa.nib"])
        let data = try #require(compiled["UIViewController-vc1-aa-aaa.nib"])
        #expect(data.count == 838)
        #expect(VariationTests.digest(data) == "935d8b3ddc542922f6a0b4d6cf1e782d3d7c33ad6345f867acf6b76f65c12dd8")
    }

    /// A popover content size among the presentation settings, after the presentation style
    /// (`sb-popover-content-size-all`).
    @Test func popoverContentSize() throws {
        let scene = SceneTests.scene(1, attributes: " storyboardIdentifier=\"Share\" modalPresentationStyle=\"formSheet\"",
                                     afterView: "<extendedEdge key=\"edgesForExtendedLayout\"/>\n<value key=\"contentSizeForViewInPopover\" type=\"size\" width=\"300\" height=\"300\"/>\n",
                                     connections: "<segue destination=\"vc2-aa-aaa\" kind=\"show\" identifier=\"Next\" id=\"csg-aa-aa9\"/>\n")
        let document = SceneTests.storyboard(scene, SceneTests.scene(2))
        let data = try #require(try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)["Share.nib"])
        #expect(data.count == 1355)
        #expect(VariationTests.digest(data) == "fc5378eee1b58bfbbdc22e72a09aee24d39e61349b1984ee3627a81e198e75a7")
    }
}

