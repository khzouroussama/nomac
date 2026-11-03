import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for table view controllers in storyboards
/// (`.github/scripts/nib_experiments.py` round 30, `tvc_scene`): sizes and SHA-256 digests of
/// Xcode's nibs.
@Suite struct TableViewControllerTests {
    static let tableAttributes = TableViewTests.attributes.replacingOccurrences(of: #" translatesAutoresizingMaskIntoConstraints="NO""#, with: "")
    static let custom = #" customClass="ListController" customModule="T" customModuleProvider="target""#

    static func cell(_ number: Int, y: Int = 28, contentSubviews: String = "", attributes: String = #" reuseIdentifier="Cell""#) -> String {
        """
        <tableViewCell clipsSubviews="YES" contentMode="scaleToFill" selectionStyle="default" indentationWidth="10"\(attributes) id="cel-aa-aa\(number)">
        <rect key="frame" x="0.0" y="\(y)" width="393" height="44"/>
        <autoresizingMask key="autoresizingMask"/>
        <tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="cel-aa-aa\(number)" id="ccv-aa-aa\(number)">
        <rect key="frame" x="0.0" y="0.0" width="393" height="44"/>
        <autoresizingMask key="autoresizingMask"/>
        \(contentSubviews)</tableViewCellContentView>
        </tableViewCell>

        """
    }

    static func scene(_ body: String = "", attributes: String = "", afterView: String = "", dataMode: String = "prototypes") -> String {
        let table = tableAttributes.replacingOccurrences(of: " style=", with: " dataMode=\"\(dataMode)\" style=")
        return """
                <scene sceneID="tvs-aa-aaa">
                    <objects>
                        <tableViewController id="tvc-aa-aaa"\(attributes) sceneMemberID="viewController">
                            <tableView key="view" \(table) id="tbv-aa-aaa">
                                <rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
                                <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
            \(body)                    <connections>
                                    <outlet property="dataSource" destination="tvc-aa-aaa" id="tds-aa-aaa"/>
                                    <outlet property="delegate" destination="tvc-aa-aaa" id="tdl-aa-aaa"/>
                                </connections>
                            </tableView>
            \(afterView)            </tableViewController>
                        <placeholder placeholderIdentifier="IBFirstResponder" id="tfr-aa-aaa" sceneMemberID="firstResponder"/>
                    </objects>
                    <point key="canvasLocation" x="0" y="0"/>
                </scene>

            """
    }

    static func prototypes(_ cells: String...) -> String { "<prototypes>\n" + cells.joined() + "</prototypes>\n" }

    static func label(text: String = "Title") -> String {
        "<subviews>\n<label opaque=\"NO\" userInteractionEnabled=\"NO\" contentMode=\"left\" horizontalHuggingPriority=\"251\" verticalHuggingPriority=\"251\" "
            + "text=\"\(text)\" textAlignment=\"natural\" lineBreakMode=\"tailTruncation\" baselineAdjustment=\"alignBaselines\" adjustsFontSizeToFit=\"NO\" "
            + "translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"tlb-aa-aa1\">\n<rect key=\"frame\" x=\"20\" y=\"11\" width=\"353\" height=\"21\"/>\n"
            + LabelTests.font(["type": "system", "pointSize": "17"]) + "\n" + LabelTests.nilColors + "</label>\n</subviews>\n"
    }

    static let labelMargins = "<constraints>\n"
        + "<constraint firstItem=\"tlb-aa-aa1\" firstAttribute=\"leading\" secondItem=\"ccv-aa-aa1\" secondAttribute=\"leadingMargin\" id=\"tl1-aa-aaa\"/>\n"
        + "<constraint firstItem=\"tlb-aa-aa1\" firstAttribute=\"centerY\" secondItem=\"ccv-aa-aa1\" secondAttribute=\"centerY\" id=\"tl2-aa-aaa\"/>\n</constraints>\n"

    static func staticSection(header: String = "", _ cells: String) -> String {
        "<sections>\n<tableViewSection\(header) id=\"sec-aa-aa1\">\n<cells>\n\(cells)</cells>\n</tableViewSection>\n</sections>\n"
    }

    static func storyboard(initial: String = "tvc-aa-aaa", _ scenes: String...) -> String {
        StoryboardCompilerTests.storyboard(scenes.joined())
            .replacingOccurrences(of: #"initialViewController="BYZ-38-t0r""#, with: "initialViewController=\"\(initial)\"")
    }

    static let controller = ("UITableViewController-tvc-aa-aaa.nib", 968, "2de1ef5b3f10569b0c84da37e8d420a2ca793b0736c32bf066b8b1aa15a04816")
    static let viewNib = "tvc-aa-aaa-view-tbv-aa-aaa.nib"
    static let cases: [(String, String, [(String, Int, String)])] = [
        ("sb-tvc-empty", storyboard(scene()), [controller, (viewNib, 1546, "c2760f4fad9b845586e973c253b7a4b50bd12904cc591a1b5cab88a5ccd62870")]),
        ("sb-tvc-prototype-label", storyboard(scene(prototypes(cell(1, contentSubviews: label() + labelMargins)))),
         [controller, (viewNib, 4405, "baab7231f4842873ef59b7634474d09e38ef0c2b2b126ce6b552fb8261f63033")]),
        ("sb-tvc-prototype-five", storyboard(scene(prototypes(["Zeta", "Alpha", "Mid", "Beta", "Cell"].enumerated().map {
            cell($0.offset + 1, y: 28 + 44 * $0.offset, attributes: " reuseIdentifier=\"\($0.element)\"")
        }.joined()))), [controller, (viewNib, 8245, "b353d3523fe0697a1d4843f5062ca19c7d6f5d51277e91361db3b59d6f9edbce")]),
        ("sb-tvc-static-two-cells", storyboard(scene(staticSection(cell(1, y: 0, attributes: "") + cell(2, y: 44, attributes: "")), dataMode: "static")),
         [controller, (viewNib, 2659, "abe9bdbbbca6b3f92dbd227795a996acd4e95f67d6df86fef9ea1eb151f6e394")]),
        ("sb-tvc-static-header", storyboard(scene(staticSection(header: #" headerTitle="Display""#, cell(1, y: 0, attributes: "")), dataMode: "static")),
         [controller, (viewNib, 2398, "35f2348abd9c00e005af3f3464ad554193451d9b9365a7c3cb8a81d4f1d0132c")]),
        ("sb-tvc-in-nav-custom", storyboard(initial: "nvc-aa-aaa",
                                            NavigationTests.navigation(root: 0, attributes: #" automaticallyAdjustsScrollViewInsets="NO""#, barAttributes: #" largeTitles="YES""#)
                                                .replacingOccurrences(of: "vc0-aa-aaa", with: "tvc-aa-aaa"),
                                            scene(prototypes(cell(1)), attributes: custom, afterView: NavigationTests.item())),
         [("UINavigationController-nvc-aa-aaa.nib", 1998, "40b937dec799cd6ea29804f8dbb442717f9f320aacda4799d13f807eeb645f43"),
          (viewNib, 3029, "e61d5fd800ac3ad2dce03c0a66183a667ab8d37aabbd64732160a57082e690c4")]),
    ]

    /// Table views as controllers' views, prototype cells as nested nibs by reuse identifier, static
    /// cells in a top-level data source, table view controllers as navigation roots.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, document: String, files: [(String, Int, String)]) throws {
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        for (file, size, digest) in files {
            let data = try #require(compiled[file], "\(name) \(file)")
            #expect(data.count == size, "\(name) \(file)")
            #expect(VariationTests.digest(data) == digest, "\(name) \(file)")
        }
    }

    /// A table view controller's view without a safe area guide in a document using safe areas
    /// compiles as without them (`sb-tvc-safe-areas-no-guide`).
    @Test func safeAreasWithoutGuide() throws {
        let document = StoryboardCompilerTests.storyboard(Self.scene(Self.prototypes(Self.cell(1))), attributes: " useSafeAreas=\"YES\"",
                                                          capabilities: "<capability name=\"Safe area layout guides\" minToolsVersion=\"9.0\"/>")
            .replacingOccurrences(of: "initialViewController=\"BYZ-38-t0r\"", with: "initialViewController=\"tvc-aa-aaa\"")
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        let data = try #require(compiled[Self.viewNib])
        #expect(data.count == 3029)
        #expect(VariationTests.digest(data) == "e61d5fd800ac3ad2dce03c0a66183a667ab8d37aabbd64732160a57082e690c4")
    }
}

