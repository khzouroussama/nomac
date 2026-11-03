import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for table view cells in xibs, constraints to layout margins and
/// the order of subviews' groups (`.github/scripts/nib_experiments.py` rounds 27, 28 and 34,
/// `cell_xib`): sizes and SHA-256 digests of Xcode's nibs.
@Suite struct CellTests {
    static let cell = "KGk-i7-Jjw", content = "H2p-sc-9uM", label = "lbl-aa-aa1"
    static let customClass = #" customClass="Cell" customModule="T" customModuleProvider="target""#

    static func cellXIB(_ attributes: String = customClass, content inner: String = "", cellExtra: String = "", size: (Int, Int) = (320, 44),
                        contentAttributes: String = "", selection: String = "default") -> String {
        let (w, h) = size
        let cellElement = """
            <tableViewCell contentMode="scaleToFill" selectionStyle="\(selection)" indentationWidth="10"\(attributes) id="\(cell)">
            <rect key="frame" x="0.0" y="0.0" width="\(w)" height="\(h)"/>
            <autoresizingMask key="autoresizingMask"/>
            <tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center"\(contentAttributes) tableViewCell="\(cell)" id="\(content)">
            <rect key="frame" x="0.0" y="0.0" width="\(w)" height="\(h)"/>
            <autoresizingMask key="autoresizingMask"/>
            \(inner)</tableViewCellContentView>
            <viewLayoutGuide key="safeArea" id="njF-e1-oar"/>
            \(cellExtra)<point key="canvasLocation" x="0" y="0"/>
            </tableViewCell>

            """
        return XIBCompilerTests.xib(cellElement)
            .replacingOccurrences(of: #" colorMatched="YES""#, with: #" useSafeAreas="YES" colorMatched="YES""#)
            .replacingOccurrences(of: "<capability name=\"documents saved", with: StoryboardCompilerTests.safeAreaCapability + "\n<capability name=\"documents saved")
    }

    static func cellLabel(_ id: String = label, frame: (Int, Int, Int, Int) = (20, 11, 280, 21), text: String = "Title") -> String {
        "<label opaque=\"NO\" userInteractionEnabled=\"NO\" contentMode=\"left\" horizontalHuggingPriority=\"251\" verticalHuggingPriority=\"251\" text=\"\(text)\" "
            + "textAlignment=\"natural\" lineBreakMode=\"tailTruncation\" baselineAdjustment=\"alignBaselines\" adjustsFontSizeToFit=\"NO\" "
            + "translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"\(id)\">\n"
            + "<rect key=\"frame\" x=\"\(frame.0)\" y=\"\(frame.1)\" width=\"\(frame.2)\" height=\"\(frame.3)\"/>\n"
            + LabelTests.font(["type": "system", "pointSize": "17"]) + "\n" + LabelTests.nilColors + "</label>\n"
    }

    static func inside(_ subviews: String, _ constraints: String = "") -> String {
        "<subviews>\n\(subviews)</subviews>\n" + (constraints.isEmpty ? "" : "<constraints>\n\(constraints)</constraints>\n")
    }

    static func constraint(_ number: String, _ first: String?, _ firstAttribute: String, _ second: String, _ secondAttribute: String, _ extra: String = "") -> String {
        "<constraint\(first.map { " firstItem=\"\($0)\"" } ?? "") firstAttribute=\"\(firstAttribute)\" secondItem=\"\(second)\" secondAttribute=\"\(secondAttribute)\"\(extra) id=\"cc\(number)-aa-aaa\"/>\n"
    }

    static let edgesToContent = ConstraintTests.edges.enumerated().map { constraint("\($0.offset)", label, $0.element, content, $0.element) }.joined()

    static func pair(_ a: (Double, Double, Double, Double), _ b: (Double, Double, Double, Double)) -> String {
        let views = [("aaa-aa-aa1", a), ("bbb-bb-bb1", b)].map { id, f in
            "<view contentMode=\"scaleToFill\" translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"\(id)\">\n<rect key=\"frame\" x=\"\(f.0)\" y=\"\(f.1)\" width=\"\(f.2)\" height=\"\(f.3)\"/>\n</view>\n"
        }.joined()
        let lines = ["aaa-aa-aa1", "bbb-bb-bb1"].enumerated().flatMap { k, id in
            ConstraintTests.edges.enumerated().map { constraint("\(k)\($0.offset)", id, $0.element, content, $0.element) }
        }.joined()
        return cellXIB(content: inside(views, lines), size: (320, 300))
    }

    static let cases: [(String, String, Int, String)] = [
        ("cell-template", cellXIB(), 1485, "f2ee43836202de873180c2d8e6e1d7a09a49165d4595291bfdc54ca5fcf0ccac"),
        ("cell-plain", cellXIB(""), 1404, "2202b4055e54fde73015034c15a0171e76508710208c5809cb0478c0666b33e0"),
        ("cell-selection-none", cellXIB(selection: "none"), 2913, "435521a97321dbbe776438a952d8a89166b8b7cbe018d60481f5ed0a821cd198"),
        ("cell-accessory", cellXIB(#" accessoryType="disclosureIndicator""# + customClass), 1504, "26ae3c04daabb1776220245e73f59e50afb470b28a9f3a312cdab42c28d45f08"),
        ("cell-background", cellXIB(cellExtra: XIBCompilerTests.rgb("0.2", "0.4", "0.6", "1") + "\n"), 1754, "6f5d31fccfee35030a62524b070260d6ebd9cd78f85eb16052b74e6b8fdcc650"),
        ("cell-preserves-margins", cellXIB(#" preservesSuperviewLayoutMargins="YES""# + customClass, contentAttributes: #" preservesSuperviewLayoutMargins="YES""#),
         1567, "0ba965f01bb36dd197a97eeb8c9a85585d0e93f7ab6565147f0ef572f1d04fd8"),
        ("cell-label-edges", cellXIB(content: inside(cellLabel(), edgesToContent)), 2928, "67ed75eafee201f00237c5f5be9e5e88ea129c2425a4fc14dab053ddce99032c"),
        ("cell-two-labels", cellXIB(content: inside(cellLabel() + cellLabel("lbl-aa-aa2", frame: (20, 40, 280, 21), text: "Detail"),
                                                    constraint("0", label, "leading", content, "leading", #" constant="20""#)
                                                    + constraint("1", "lbl-aa-aa2", "top", label, "bottom", #" constant="8""#)
                                                    + constraint("2", "lbl-aa-aa2", "leading", label, "leading")), size: (320, 80)),
         3104, "93d547caf9ef9c7b2cebd277610a64b731bde993a1bbaea1cc8a0cbcb6dc2b3b"),
        ("margin-cell-leading-10", cellXIB(content: inside(cellLabel(), "<constraint firstItem=\"\(label)\" firstAttribute=\"leading\" secondItem=\"\(content)\" secondAttribute=\"leadingMargin\" constant=\"10\" id=\"mc0-aa-aaa\"/>\n")),
         2844, "cfa1fd105bf6b4557a5d3aae5f85decf61fe8e48bae17f9702e69ec9249c8bfa"),
        ("margin-root-trailing-10-reversed", LabelTests.labelled(LabelTests.label(),
                                                                 constraints: "<constraint firstAttribute=\"trailingMargin\" secondItem=\"lll-ll-ll1\" secondAttribute=\"trailing\" constant=\"10\" id=\"mc0-aa-aaa\"/>\n"),
         2128, "e82031b96b5a60554aeb79a2cd8ad028f6913b297286e8b016010e97d96e0d59"),
        ("margin-root-centerX-10", LabelTests.labelled(LabelTests.label(),
                                                       constraints: "<constraint firstItem=\"lll-ll-ll1\" firstAttribute=\"centerX\" secondItem=\"\(ConstraintTests.root)\" secondAttribute=\"centerXWithinMargins\" constant=\"10\" id=\"mc0-aa-aaa\"/>\n"),
         2128, "62ef3ed99e6968598c4c8e88ec7b788e425e8b2e13c089efd49b7180806dd43d"),
        ("margin-order-leadingMargin-leading", LabelTests.labelled(LabelTests.label(), constraints:
            "<constraint firstItem=\"lll-ll-ll1\" firstAttribute=\"leading\" secondItem=\"\(ConstraintTests.root)\" secondAttribute=\"leadingMargin\" id=\"mo0-aa-aaa\"/>\n"
            + "<constraint firstItem=\"lll-ll-ll1\" firstAttribute=\"leading\" secondItem=\"\(ConstraintTests.root)\" secondAttribute=\"leading\" id=\"mo1-aa-aaa\"/>\n"),
         2146, "08dc8c1cce3d0ade5f68dd04ce131638f9b8f89496818db58ad106695c0520b5"),
        ("view-frames-partial-above", ConstraintTests.constrained(ConstraintTests.subview("aaa-aa-aa1", (100, 7, 150, 22)) + ConstraintTests.subview("bbb-bb-bb1", (0, 34, 200, 1)),
                                                                 ConstraintTests.pinned("aaa-aa-aa1", 0) + ConstraintTests.pinned("bbb-bb-bb1", 4)),
         1521, "a989e9fe94cc1face4468dce088289b48d316c4ecbca776160d03f2a7a8c8385"),
        ("cell-frames-inside-above", pair((141, 7, 37, 22), (0, 34, 320, 1)), 2256, "0784f70114501ec4e25962c638d99344c70d40cb88c085df03ea6eb4945eb5ba"),
        ("cell-content-margins-constraint", cellXIB(content: marginSubview + contentMargins, size: (320, 60)),
         2003, "a8d90aa43d09e6068f06f3c8dc0017e7ec193c191d7dddf18db888a38af0e632"),
        ("cell-content-directional-constraint", cellXIB(content: marginSubview + contentDirectional, size: (320, 60)),
         2039, "ef7fdc5000db7389bae55fd6024e15ea3b2457d88e2d3411420329a1d8ad5e7b"),
        ("cell-directional-both", cellXIB(content: contentDirectional, cellExtra: #"<directionalEdgeInsets key="directionalLayoutMargins" top="8" leading="24" bottom="8" trailing="24"/>"# + "\n"),
         1615, "08271820dc1359484ac188f003b6f8e57fdcf57886aa3baaa29a4c17f97cb2cf"),
        ("cell-separator-inset-60", cellXIB(cellExtra: separatorInset(60, 0)), 1538, "10801cadc8c7f36b030ec18266e5da51b2c3054176e26e0973be3cd81ecd579e"),
        ("cell-selection-none-height-44.1", cellXIB(size: (320, 44), selection: "none").replacingOccurrences(of: #"height="44""#, with: #"height="44.1""#),
         2913, "b6a495d6e000034884d5ab615af3d9fc615e88704fbf9ca9c23a0cd2d95f31aa"),
        ("cell-selection-gray-background-srgb", cellXIB(cellExtra: XIBCompilerTests.rgb("0.2", "0.4", "0.6", "1") + "\n", selection: "gray"),
         1774, "eca64fb360b12014eab6fb9b834666c360c3f33942c56af77c1547868881f03e"),
        ("cell-separator-inset-both", cellXIB(cellExtra: separatorInset(20, 30)), 1538, "e41742230d1a6ba84c88d03bf2d90077cfc732b25e044407c4e6176ae7c45488"),
    ]

    /// Round 34: a subview pinned to its content view's margins, which the content view sets.
    static let marginSubview = "<subviews>\n" + ConstraintTests.subview(ConstraintTests.sub, (24, 11, 100, 22)) + "</subviews>\n<constraints>\n"
        + ConstraintTests.constraint(0, ConstraintTests.sub, "leading", content, "leadingMargin")
        + ConstraintTests.constraint(1, ConstraintTests.sub, "top", content, "topMargin") + "</constraints>\n"
    static let contentMargins = #"<edgeInsets key="layoutMargins" top="16" left="16" bottom="16" right="16"/>"# + "\n"
    static let contentDirectional = #"<directionalEdgeInsets key="directionalLayoutMargins" top="8" leading="32" bottom="8" trailing="32"/>"# + "\n"

    static func separatorInset(_ minX: Int, _ maxX: Int) -> String {
        "<inset key=\"separatorInset\" minX=\"\(minX)\" minY=\"0.0\" maxX=\"\(maxX)\" maxY=\"0.0\"/>\n"
    }

    /// Cells with their content view and IB's separator; margins as their plain attributes moved by
    /// 8 points, or by the content view's own margins; groups by their frames' distance from their
    /// superview's origin; cells' and content views' margins and separator insets.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }

    /// Frames as far from the origin as each other: the order between them is not observed.
    @Test func refusesFramesAtTheSameDistance() {
        let xib = ConstraintTests.constrained(ConstraintTests.subview("aaa-aa-aa1", (0, 50, 100, 20)) + ConstraintTests.subview("bbb-bb-bb1", (50, 0, 100, 20)),
                                              ConstraintTests.pinned("aaa-aa-aa1", 0) + ConstraintTests.pinned("bbb-bb-bb1", 4))
        #expect(throws: NomacError("nomac does not compile constraints of subviews whose frames lie as far from their superview's origin yet (BACKLOG B-265)",
                                   path: "/tmp/View.xib")) {
            try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        }
    }

    /// A background color's flag before the separator inset (`cell-bg-sep`; cwa's ErrorReportHistoryCell).
    @Test func backgroundColorBeforeSeparatorInset() throws {
        let extra = "<color key=\"backgroundColor\" white=\"0.0\" alpha=\"0.0\" colorSpace=\"custom\" customColorSpace=\"genericGamma22GrayColorSpace\"/>\n"
            + "<inset key=\"separatorInset\" minX=\"15\" minY=\"0.0\" maxX=\"0.0\" maxY=\"0.0\"/>\n"
        let nib = try XIBCompiler.compile(Data(Self.cellXIB(cellExtra: extra).utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == 1744)
        #expect(VariationTests.digest(nib) == "6c24b63de3b8997b658600000a4f27e367d4b8b351351712c3b46266546d6cd1")
    }
}

