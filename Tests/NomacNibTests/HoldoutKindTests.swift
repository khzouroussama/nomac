import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for presentation segues' styles, text views adjusting their font
/// and detecting calendar events, table view cells' accessibility and top-level stack views
/// (`.github/scripts/nib_experiments.py` round 104): sizes and SHA-256 digests of Xcode's nibs.
@Suite struct HoldoutKindTests {
    static func presenting(_ extra: String) -> String {
        let segue = "<segue destination=\"vc2-aa-aaa\" kind=\"presentation\"\(extra) id=\"bsg-aa-aaa\"/>"
        return SceneTests.storyboard(TriggeredSegueTests.scene(1, buttons: TriggeredSegueTests.button(1, y: 100, segue), exit: false), SceneTests.scene(2))
    }

    static let segueCases: [(String, String, Int, String)] = [
        ("sb-segue-style-fullScreen", presenting(#" modalPresentationStyle="fullScreen""#), 1208, "8ab32a250f42ec0840afc3fd8536d357abf428093d5d81952fa415832fc7fb1c"),
        ("sb-segue-style-automatic", presenting(#" modalPresentationStyle="automatic""#), 1215, "c2245d19baa19eac489f560eb27ab156e86d0975b7a4318f695367f8cefc0307"),
        ("sb-segue-style-popover", presenting(#" modalPresentationStyle="popover""#), 1208, "86dea77b87bb60659b517f47741205abb08e14dc6f28fb850c7bf43675c6bda8"),
        ("sb-segue-transition-coverVertical", presenting(#" modalTransitionStyle="coverVertical""#), 1206, "28393ee51e96aa6bae2d387f102e722cfb1b924d6da2711615b070f5cd5e8374"),
        ("sb-segue-transition-partialCurl", presenting(#" modalTransitionStyle="partialCurl""#), 1206, "0ea2179205224ab0a5825511cf562a970a2a2e484fa78fb8e1ef97cb7c138e41"),
        ("sb-segue-style-both", presenting(#" modalPresentationStyle="overFullScreen" modalTransitionStyle="crossDissolve""#),
         1234, "efb9ae9748812af83eb112a4900a680127218e5f9ecb62d5ad5a1a6f98108b80"),
        ("sb-segue-style-controller", SceneTests.storyboard(SceneTests.scene(1, connections: #"<segue destination="vc2-aa-aaa" kind="presentation" identifier="Go" "#
                                                                                 + #"modalPresentationStyle="fullScreen" id="csg-aa-aa1"/>"# + "\n"), SceneTests.scene(2)),
         1196, "fced8e750f58b474b0a2c6430c2f8af9c4403c1bf55a9e815a33502b13dd05e1"),
    ]

    /// A presentation segue's template writes its styles after its destination, coverVertical too.
    @Test(arguments: segueCases)
    func compilesSeguesAsXcode(name: String, document: String, size: Int, digest: String) throws {
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        let nib = try #require(compiled["UIViewController-vc1-aa-aaa.nib"], "\(name)")
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }

    static let stack = "<stackView opaque=\"NO\" contentMode=\"scaleToFill\" axis=\"vertical\" id=\"iN0-l3-epB\">\n"
        + #"<rect key="frame" x="0.0" y="0.0" width="200" height="100"/>"# + "\n"
        + #"<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>"# + "\n"
        + #"<point key="canvasLocation" x="0" y="0"/>"# + "\n</stackView>\n"
    static let styleFont = #"<fontDescription key="fontDescription" style="UICTFontTextStyleBody"/>"# + "\n"
    static let xibCases: [(String, String, Int, String)] = [
        ("text-view-adjusts", TextViewTests.xib(TextViewTests.attributes + #" adjustsFontForContentSizeCategory="YES""#,
                                                TextViewTests.background + TextViewTests.text + styleFont + TextViewTests.traits),
         2279, "c3ef2566350ed1a8e99ce52f85d7943aa9b679766a62baa12ab71b78ff9a936d"),
        ("text-view-detect-all", TextViewTests.xib(TextViewTests.attributes, TextViewTests.background + TextViewTests.text + TextViewTests.font + TextViewTests.traits
                                                   + #"<dataDetectorType key="dataDetectorTypes" phoneNumber="YES" link="YES" address="YES" calendarEvent="YES"/>"# + "\n"),
         2471, "05c0d2bc8c5e1b189856a5adcad7cde08b9f7bd0c2a2a76a871d17de1da644a4"),
        ("cell-a11y", CellTests.cellXIB("", cellExtra: #"<accessibility key="accessibilityConfiguration" identifier="cell"/>"# + "\n"),
         1524, "02e86d34dd7a61c83a11ab20a6f3287e7a6d6ba103db145b6bf05e204c0b8950"),
        ("cell-a11y-label", CellTests.cellXIB("", cellExtra: #"<accessibility key="accessibilityConfiguration" label="Row">"# + "\n"
                                                + #"<bool key="isElement" value="YES"/>"# + "\n</accessibility>\n"),
         1576, "e8e7be7540fa86b4d8a0f2a96fa59fa440a936189a3aaffb0b17c25a1e8548f0"),
        ("tl-stack", XIBCompilerTests.xib(stack), 962, "4921ed165d0f03d8a570de182e9b7265abc1211211446c3b67180707d206ebe6"),
    ]

    /// `UIAdjustsFontForContentSizeCategory` before the font, calendar events as data detector bit 8,
    /// a cell's accessibility configuration as a view's, a top-level stack view as any view.
    @Test(arguments: xibCases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
