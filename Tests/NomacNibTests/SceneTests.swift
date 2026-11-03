import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for storyboards of several scenes and their segues
/// (`.github/scripts/nib_experiments.py` round 24, `controller_scene`): sizes and SHA-256 digests
/// of the files of Xcode's `.storyboardc`.
@Suite struct SceneTests {
    static func scene(_ number: Int, attributes: String = "", afterView: String = "", connections: String = "") -> String {
        let container = afterView + (connections.isEmpty ? "" : "<connections>\n\(connections)</connections>\n")
        return """
            <scene sceneID="sc\(number)-aa-aaa">
                <objects>
                    <viewController id="vc\(number)-aa-aaa"\(attributes) sceneMemberID="viewController">
                        <view key="view" contentMode="scaleToFill" id="vw\(number)-aa-aaa">
                            <rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
                            <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
                        </view>
            \(container)        </viewController>
                    <placeholder placeholderIdentifier="IBFirstResponder" id="fr\(number)-aa-aaa" sceneMemberID="firstResponder"/>
                </objects>
                <point key="canvasLocation" x="0" y="0"/>
            </scene>

            """
    }

    static func segue(_ destination: Int, _ kind: String, _ number: Int, _ identifier: String?) -> String {
        "<segue destination=\"vc\(destination)-aa-aaa\" kind=\"\(kind)\"\(identifier.map { " identifier=\"\($0)\"" } ?? "") id=\"seg-aa-aa\(number)\"/>\n"
    }

    static func storyboard(_ scenes: String...) -> String {
        StoryboardCompilerTests.storyboard(scenes.joined())
            .replacingOccurrences(of: #"initialViewController="BYZ-38-t0r""#, with: #"initialViewController="vc1-aa-aaa""#)
    }

    static let names = ["Accounts", "Edit", "Scan", "Manual", "Algorithms", "Search", "Settings", "About", "Help"]
    static let view = (1701, "049be9c5b429b28c1f71eea25171cb7965fdc08e25309c3d4c0acc1c04489f4a")

    static let cases: [(String, String, [(String, Int, String)])] = [
        ("sb-scenes-two-identified-both", storyboard(scene(1, attributes: #" storyboardIdentifier="First""#), scene(2, attributes: #" storyboardIdentifier="Second""#)), [
            ("First.nib", 964, "365b0e39fc151eb9a3106c30a66a02bf9013f0206d021a5bafcb1f0a51582390"),
            ("Info.plist", 197, "41a73f44e2bcdc06561b81c6f5d0a0e7e006043b35c0116751947916a0ffdb32"),
            ("Second.nib", 965, "00283b1685f0e957b3d704e6ddafe7724a3015fc5a403d908f1dc7573e9576e9"),
        ]),
        ("sb-scenes-9-identified", storyboard(names.enumerated().map { scene($0.offset + 1, attributes: " storyboardIdentifier=\"\($0.element)\"") }.joined()), [
            ("Info.plist", 351, "4384a8a1da5d7eef88a3d5abd798c5a15ddaa83553f84ee4c5e04b32eae805cf"),
            ("Accounts.nib", 967, "83db2efbffd92a21a415674cf6847d47d7866be7979f606c6b819b718a8ee0cf"),
            ("Help.nib", 963, "6869f2262c518fe3402f08665c5f574d45e4ad2df0afcb6c6be47d92da6a4e91"),
        ]),
        ("sb-segue-two", storyboard(scene(1, connections: segue(2, "show", 1, "Detail") + segue(3, "presentation", 2, "Present")), scene(2), scene(3)), [
            ("Info.plist", 399, "cc27a41f16e3fa6ddcaed99a03a8140726ebe2625d4312b0f3abc33cb5db35fa"),
            ("UIViewController-vc1-aa-aaa.nib", 1355, "25c778787e032ee84fc8fa045e9b42ea8e87e49844d10a8bbcc64679640eacdf"),
            ("UIViewController-vc2-aa-aaa.nib", 860, "77ea33d9265b1240144062a8c9255bfda38b8956e9a7efea85bcfdd94b4957bf"),
            ("UIViewController-vc3-aa-aaa.nib", 860, "bb25185db68ecb9e2cab0a145e36be390099b11c588ab5d1150da767ae426840"),
        ]),
        ("sb-segue-to-custom-class", storyboard(scene(1, connections: segue(2, "show", 1, "Detail")),
                                                scene(2, attributes: #" customClass="DetailController" customModule="T" customModuleProvider="target""#)), [
            ("Info.plist", 333, "c3e09a7af899f0f0cc3ca68f82f29ca91f49a4abf576691e433075cea743b123"),
            ("UIViewController-vc1-aa-aaa.nib", 1215, "fdec64b67432f5ce616e1874a3f5ac1fbd4469c271cf57750372c2ce2ab3a30c"),
            ("UIViewController-vc2-aa-aaa.nib", 954, "28e05bb4bb0b3a889b530aa2d10cfeb301a1026828d33fe3cf9b1a71863264b7"),
        ]),
        ("sb-segue-back", storyboard(scene(1, connections: segue(2, "show", 1, "Next")), scene(2, connections: segue(1, "presentation", 2, "Back"))), [
            ("UIViewController-vc1-aa-aaa.nib", 1213, "b29b9a9682e6756eae65afcb88e042e755cc3175f2587addba0f18be5d654a7e"),
            ("UIViewController-vc2-aa-aaa.nib", 1106, "f72910da5329c61004ca488ea66bcaa693be1ff2e5b73318700f12ef3ad51406"),
        ]),
        ("sb-segue-from-identified", storyboard(scene(1, attributes: #" storyboardIdentifier="First""#, connections: segue(2, "show", 1, "Detail")), scene(2)), [
            ("First.nib", 1255, "3905f6549d247288ea34b5ff053366022d4b64b8ab4b0b4863d44982d731a8ed"),
            ("Info.plist", 243, "ad6a2483d4f19075cf80b9f1bc2d62399111f5ca153b021912f8290c6c19bdf7"),
        ]),
    ]

    /// Entry points and segue destinations get nibs, the Info.plist's names in a copied Foundation
    /// dictionary, segue templates in their sources, plain controllers where only segues reach.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, document: String, files: [(String, Int, String)]) throws {
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        for (file, size, digest) in files + [("vc1-aa-aaa-view-vw1-aa-aaa.nib", Self.view.0, Self.view.1)] {
            let data = try #require(compiled[file], "\(name) \(file)")
            #expect(data.count == size, "\(name) \(file)")
            #expect(VariationTests.digest(data) == digest, "\(name) \(file)")
        }
    }

    /// `sb-segue-show-unnamed` and `sb-unreached-three`: ibtool warns about both, about several
    /// unreachable controllers in an order not known yet.
    @Test(arguments: [
        (storyboard(scene(1, connections: segue(2, "show", 1, nil)), scene(2)), "a controller's segue without an identifier, or a popover one"),
        (storyboard(scene(1), scene(2), scene(3)),
         "several view controllers no entry point, identifier or segue reaches (ibtool skips them with warnings)"),
    ])
    func refusesWhatIbtoolWarnsAbout(document: String, what: String) {
        #expect(throws: NomacError("nomac does not compile \(what) yet (BACKLOG B-261)", path: "/tmp/Main.storyboard")) {
            try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        }
    }

    /// `sb-segue-unreached-source`: ibtool skips the controller nothing reaches, and what only it
    /// reaches, warning about it by name.
    @Test func skipsUnreachedController() throws {
        let document = Self.storyboard(Self.scene(1), Self.scene(2, connections: Self.segue(3, "show", 1, "Next")), Self.scene(3))
        let compiled = try StoryboardCompiler.compileReportingWarnings(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        #expect(compiled.files.keys.sorted() == ["Info.plist", "UIViewController-vc1-aa-aaa.nib", "vc1-aa-aaa-view-vw1-aa-aaa.nib"])
        #expect(compiled.warnings == ["/tmp/Main.storyboard:vc2-aa-aaa: warning: “View Controller“ is unreachable because it has no entry points, and no identifier "
                                      + "for runtime access via -[UIStoryboard instantiateViewControllerWithIdentifier:]. [9]"])
    }
}

