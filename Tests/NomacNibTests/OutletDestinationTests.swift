import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for outlets to a controller's navigation item and bar button
/// items, from the controller and from a view of its scene (`.github/scripts/nib_experiments.py`
/// round 114, `sb-outlet-*`): sizes and SHA-256 digests of Xcode's nibs.
@Suite struct OutletDestinationTests {
    typealias N = NavigationTests
    typealias T = TableViewControllerTests
    typealias V = CollectionViewControllerTests
    static let custom = #" customClass="Controller" customModule="T" customModuleProvider="target""#
    static let doneOutlet = outlet("doneButton", "bbi-aa-aa1", 1)
    static let done = N.item(items: N.barItem("rightBarButtonItem", "done", 1, action: "done:"))

    static func outlet(_ name: String, _ destination: String, _ number: Int) -> String {
        "<outlet property=\"\(name)\" destination=\"\(destination)\" id=\"out-aa-aa\(number)\"/>\n"
    }

    static func connections(_ outlets: String) -> String { "<connections>\n\(outlets)</connections>\n" }

    static func table(_ afterView: String, attributes: String = "") -> String {
        T.storyboard(initial: "tvc-aa-aaa", T.scene(T.prototypes(T.cell(1)), attributes: attributes,
                                                    afterView: afterView.replacingOccurrences(of: "vc1-aa-aaa", with: "tvc-aa-aaa")))
    }

    static func collection(_ afterView: String, attributes: String = "") -> String {
        N.storyboard(initial: "cvc-aa-aaa", V.scene(attributes: attributes, afterView: afterView.replacingOccurrences(of: "vc1-aa-aaa", with: "cvc-aa-aaa")))
    }

    /// A view controller with the done item whose subview's outlets are `outlets`.
    static func fromView(_ outlets: String) -> String {
        let holder = #"<subviews>\#n<view contentMode="scaleToFill" customClass="Holder" customModule="T" customModuleProvider="target" id="hld-aa-aa1">\#n"#
            + #"<rect key="frame" x="0.0" y="100" width="100" height="100"/>\#n<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>\#n"#
            + connections(outlets) + "</view>\n</subviews>\n</view>\n"
        return N.storyboard(initial: "vc1-aa-aaa", SceneTests.scene(1, afterView: done).replacingOccurrences(of: "</view>\n", with: holder))
    }

    static let tableNib = "UITableViewController-tvc-aa-aaa.nib", collectionNib = V.controller.0, viewControllerNib = "UIViewController-vc1-aa-aaa.nib"
    static let viewNib = "vc1-aa-aaa-view-vw1-aa-aaa.nib"
    static let cases: [(String, String, [(String, Int, String)])] = [
        ("sb-outlet-bar-tvc-custom", table(done + connections(doneOutlet), attributes: custom),
         [(tableNib, 1464, "f1a5a82618c681d9049e6a050d6dec02a2554411af92222c2608c6d2c10c5c54")]),
        ("sb-outlet-item-tvc", table(N.item() + connections(outlet("item", "nvi-aa-aaa", 1))),
         [(tableNib, 1220, "2c957b73f70cbed3ac5f603bb1e6af3b5c2a8ea3a20d302d490b9efa3b616171")]),
        ("sb-outlet-item-and-bar-tvc", table(done + connections(doneOutlet + outlet("item", "nvi-aa-aaa", 2))),
         [(tableNib, 1477, "8cdea9096bb4737c32c5e91d19b45eb7956aeeba8aadbd3ed496f32e5dcb5167")]),
        ("sb-outlet-bar-cvc", collection(done + connections(doneOutlet)),
         [(collectionNib, 1445, "9bfbee8a847e43a8b52b7c2abb42a1303dd650ca7fe48bff4efafebf881dbb18")]),
        ("sb-outlet-bar-vc", N.storyboard(initial: "vc1-aa-aaa", SceneTests.scene(1, afterView: done, connections: doneOutlet)),
         [(viewControllerNib, 1396, "c875795a5f54a4b4cd77351f0b7c0e179b6a4775416c26d953c97cae1551dbc7"),
          (viewNib, 1701, "049be9c5b429b28c1f71eea25171cb7965fdc08e25309c3d4c0acc1c04489f4a")]),
        ("sb-outlet-bar-from-view", fromView(outlet("doneButton", "bbi-aa-aa1", 1)),
         [(viewControllerNib, 1392, "8aa8821e735d7ab98f7f9421c8c671766e4dc169087993ff0f99357814495603"),
          (viewNib, 1975, "c786c7a4fc2947a298f32679865fcaf8dd41b8b84f086205d1fd5d6233f7933b")]),
        ("sb-outlet-bar-from-view-and-controller", fromView(outlet("doneButton", "bbi-aa-aa1", 1) + outlet("owner", "vc1-aa-aaa", 2)),
         [(viewControllerNib, 1431, "0748491af1a404ebd30c0ef0690a42f5ce89895d8ce40e3bfb39792bd597647b"),
          (viewNib, 2064, "f94e3a6bf193b0eadf692101f95cf8398a2724efa4c96c4b818378f2703cf30d")]),
        ("sb-outlet-bar-from-view-controller-first", fromView(outlet("doneButton", "bbi-aa-aa1", 1) + outlet("aaa", "vc1-aa-aaa", 2)),
         [(viewControllerNib, 1431, "577c4a5c155eeab6dc360abfb12203b7bf09ced821ebf7471cb8da8a57d4f0c3"),
          (viewNib, 2062, "affd9d7757c4bcbd522c738a13138d40ab49659ce26c4c80c33be8830cb10731")]),
        ("sb-bar-same-selector", N.storyboard(initial: "vc1-aa-aaa", SceneTests.scene(1, afterView: N.item(items: N.barItem("leftBarButtonItem", "cancel", 2, action: "done:")
                                                                                                           + N.barItem("rightBarButtonItem", "done", 1, action: "done:")))),
         [(viewControllerNib, 1463, "2bfe838ae1176ff5fcd4005ab0873e445357a36708c7597a456ca4673829b988")]),
    ]

    /// The controller's outlets go by name between `storyboard` and `sceneViewController`; a view's
    /// reach the objects through upstream placeholders, numbered with the controller as the sorted
    /// connections first reach them; of one selector, the right item's action comes first.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, document: String, files: [(String, Int, String)]) throws {
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        for (file, size, digest) in files {
            let data = try #require(compiled[file], "\(name) \(file)")
            #expect(data.count == size, "\(name) \(file)")
            #expect(VariationTests.digest(data) == digest, "\(name) \(file)")
        }
    }

    static let navigationBarItem = #"<navigationItem title="Hello" id="nvi-aa-aa1">"# + "\n" + #"<barButtonItem key="rightBarButtonItem" style="done" systemItem="done" id="dne-aa-aa1"/>"#
        + "\n</navigationItem>"

    static func ownerOutlet(_ name: String, _ destination: String) -> String {
        SubviewNavigationBarTests.bar(navigationBarItem).replacingOccurrences(
            of: #"<placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File's Owner"/>"#,
            with: #"<placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File's Owner" customClass="Owner">"# + "\n" + connections(outlet(name, destination, 1)) + "</placeholder>")
    }

    /// A xib's navigation bar's item and bar button items are outlets' destinations too.
    @Test(arguments: [
        ("outlet-nav-bar-button", ownerOutlet("doneButton", "dne-aa-aa1"), 1579, "dd6320510353f22306a8499237b07646679c56b0d582a43dba82b702275da4e7"),
        ("outlet-nav-bar-item", ownerOutlet("item", "nvi-aa-aa1"), 1573, "88f2881260910b7a36df1fd9f45b8f437a0ad2f00089fe4fd4b757a625948f2c"),
    ])
    func navigationBarObjects(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }

    /// A prototype cell's outlet to a bar button item crosses two nibs (`sb-outlet-bar-tvc-from-cell`).
    @Test func refusalNamesTheDestination() {
        let cell = T.cell(1).replacingOccurrences(of: "</tableViewCell>", with: Self.connections(Self.outlet("doneButton", "bbi-aa-aa1", 2)) + "</tableViewCell>")
        let document = T.storyboard(initial: "tvc-aa-aaa", T.scene(T.prototypes(cell), afterView: Self.done.replacingOccurrences(of: "vc1-aa-aaa", with: "tvc-aa-aaa")))
        #expect(throws: NomacError("nomac does not compile an outlet to <barButtonItem> (bbi-aa-aa1) outside its nib or of a kind nomac does not compile yet (BACKLOG B-260)",
                                   path: "/tmp/Main.storyboard")) {
            try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        }
    }
}
