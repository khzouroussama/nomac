import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for collection view controllers in storyboards
/// (`.github/scripts/nib_experiments.py` round 70, `cvc_scene`): sizes and SHA-256 digests of Xcode's
/// nibs.
@Suite struct CollectionViewControllerTests {
    static let flow = "<collectionViewFlowLayout key=\"collectionViewLayout\" minimumLineSpacing=\"10\" minimumInteritemSpacing=\"10\" id=\"cfl-aa-aa1\">\n"
        + #"<size key="itemSize" width="128" height="128"/>"# + "\n" + #"<size key="headerReferenceSize" width="0.0" height="0.0"/>"# + "\n"
        + #"<size key="footerReferenceSize" width="0.0" height="0.0"/>"# + "\n" + #"<inset key="sectionInset" minX="0.0" minY="0.0" maxX="0.0" maxY="0.0"/>"#
        + "\n</collectionViewFlowLayout>\n"
    static let cell = "<cells>\n" + #"<collectionViewCell opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" reuseIdentifier="Cell" id="cel-aa-aa1">"#
        + "\n" + #"<rect key="frame" x="0" y="0.0" width="128" height="128"/>"# + "\n"
        + #"<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>"# + "\n"
        + #"<view key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center">"# + "\n"
        + #"<rect key="frame" x="0.0" y="0.0" width="128" height="128"/>"# + "\n" + #"<autoresizingMask key="autoresizingMask"/>"# + "\n</view>\n</collectionViewCell>\n</cells>\n"

    static func scene(_ cells: String = "", attributes: String = "", afterView: String = "") -> String {
        "<scene sceneID=\"cvs-aa-aaa\">\n<objects>\n<collectionViewController id=\"cvc-aa-aaa\"\(attributes) sceneMemberID=\"viewController\">\n"
            + #"<collectionView key="view" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="scaleToFill" dataMode="prototypes" id="cvv-aa-aaa">"# + "\n"
            + #"<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>"# + "\n"
            + #"<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>"# + "\n" + flow + cells
            + "<connections>\n" + #"<outlet property="dataSource" destination="cvc-aa-aaa" id="cds-aa-aa1"/>"# + "\n"
            + #"<outlet property="delegate" destination="cvc-aa-aaa" id="cdl-aa-aa1"/>"# + "\n</connections>\n</collectionView>\n\(afterView)</collectionViewController>\n"
            + #"<placeholder placeholderIdentifier="IBFirstResponder" id="cfr-aa-aaa" sceneMemberID="firstResponder"/>"# + "\n</objects>\n"
            + #"<point key="canvasLocation" x="0" y="0"/>"# + "\n</scene>\n"
    }

    static let controller = ("UICollectionViewController-cvc-aa-aaa.nib", 973, "9406f5504b85aabea47e6860abdd04a9b5aa531952d94474f0e966e6909658a0")
    static let viewNib = "cvc-aa-aaa-view-cvv-aa-aaa.nib"
    static let view = (viewNib, 1329, "8d3b1afd305f5f5252321f04ca16a124cdcedf52e803d1d88e4552909c0986e7")
    static let segue = "<connections>\n" + #"<segue destination="vc2-aa-aaa" kind="show" identifier="Open" id="cvg-aa-aaa"/>"# + "\n</connections>\n"

    static let cases: [(String, String, [(String, Int, String)])] = [
        ("sb-cvc", TableViewControllerTests.storyboard(initial: "cvc-aa-aaa", scene()), [controller, view]),
        ("sb-cvc-cell", TableViewControllerTests.storyboard(initial: "cvc-aa-aaa", scene(cell)),
         [controller, (viewNib, 2621, "32edc11dfc904376ad361a120a5cabbed9b46d93716e230e9c671097b6203bae")]),
        ("sb-cvc-netnewswire", TableViewControllerTests.storyboard(initial: "cvc-aa-aaa", scene(attributes: #" storyboardIdentifier="Feeds" title="Feeds" "#
                                                                                                 + #"useStoryboardIdentifierAsRestorationIdentifier="YES" clearsSelectionOnViewWillAppear="NO""#)),
         [("Feeds.nib", 1093, "a0a431365d0128e00b6f97a38d1108cd520f40e406883683dbe49d6db04a79b6"), view]),
        ("sb-cvc-keeps-selection-segue", TableViewControllerTests.storyboard(initial: "cvc-aa-aaa", scene(attributes: #" clearsSelectionOnViewWillAppear="NO""#,
                                                                                                           afterView: segue), SceneTests.scene(2)),
         [("UICollectionViewController-cvc-aa-aaa.nib", 1298, "148dbda849d73a9134c8a85b6b989641a4b6e8402e6c88377b6c8fb6ac8df9d6"), view]),
        ("sb-tvc-keeps-selection", TableViewControllerTests.storyboard(TableViewControllerTests.scene(attributes: #" clearsSelectionOnViewWillAppear="NO""#)),
         [("UITableViewController-tvc-aa-aaa.nib", 1004, "580ecdc704311def516ea0beee2e1a29d478eb88302a1d9c5db73f9d899df76e")]),
    ]

    /// A table view controller's shape with the collection view as the view, no layout guides of the
    /// controller's; the title and storyboard identifier one string; the kept selection after the
    /// segue templates.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, document: String, nibs: [(String, Int, String)]) throws {
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        for (nib, size, digest) in nibs {
            let data = try #require(compiled[nib], "\(name) \(nib)")
            #expect(data.count == size, "\(name) \(nib)")
            #expect(VariationTests.digest(data) == digest, "\(name) \(nib)")
        }
    }
}
