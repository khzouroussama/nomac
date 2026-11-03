import Foundation
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for text fields, switches, their actions, cells of the built-in
/// styles, masks and the constraint orders tofu's storyboard needs (`.github/scripts/nib_experiments.py`
/// round 32): sizes and SHA-256 digests of Xcode's nibs.
@Suite struct TofuFeatureTests {
    typealias C = ConstraintTests
    static let textField = #"opaque="NO" clipsSubviews="YES" contentMode="scaleToFill" contentHorizontalAlignment="left" contentVerticalAlignment="center" "#
        + #"placeholder="Name" textAlignment="natural" minimumFontSize="17" translatesAutoresizingMaskIntoConstraints="NO""#
    static let switchAttributes = #"opaque="NO" contentMode="scaleToFill" horizontalHuggingPriority="750" verticalHuggingPriority="750" "#
        + #"contentHorizontalAlignment="center" contentVerticalAlignment="center" translatesAutoresizingMaskIntoConstraints="NO""#

    static func field(_ attributes: String = textField, id: String = "txf-aa-aaa", y: Int = 100, traits: String = "", connections: String = "") -> String {
        "<textField \(attributes) id=\"\(id)\">\n<rect key=\"frame\" x=\"16\" y=\"\(y)\" width=\"359\" height=\"44\"/>\n"
            + #"<fontDescription key="fontDescription" type="system" pointSize="17"/>"# + "\n<textInputTraits key=\"textInputTraits\"\(traits)/>\n\(connections)</textField>\n"
    }

    static func toggle(_ attributes: String = switchAttributes, connections: String = "") -> String {
        "<switch \(attributes) id=\"swt-aa-aaa\">\n<rect key=\"frame\" x=\"302\" y=\"100\" width=\"51\" height=\"31\"/>\n\(connections)</switch>\n"
    }

    static func actions(_ pairs: (String, String)...) -> String {
        "<connections>\n" + pairs.enumerated().map {
            "<action selector=\"\($0.element.0)\" destination=\"-1\" eventType=\"\($0.element.1)\" id=\"ac\($0.offset)-aa-aaa\"/>\n"
        }.joined() + "</connections>\n"
    }

    static func pin(_ id: String, _ number: Int, _ x: Int, _ y: Int) -> String {
        C.constraint(2 * number, id, "leading", C.root, "leading", " constant=\"\(x)\"") + C.constraint(2 * number + 1, id, "top", C.root, "top", " constant=\"\(y)\"")
    }

    static func styleLabel(_ id: String, _ text: String, _ frame: (Double, Double, Double, Double), size: Int = 16, alignment: String = "natural",
                           color: String = "<nil key=\"textColor\"/>\n") -> String {
        "<label opaque=\"NO\" multipleTouchEnabled=\"YES\" contentMode=\"left\" text=\"\(text)\" textAlignment=\"\(alignment)\" lineBreakMode=\"tailTruncation\" "
            + "baselineAdjustment=\"alignBaselines\" adjustsFontSizeToFit=\"NO\" id=\"\(id)\">\n"
            + "<rect key=\"frame\" x=\"\(frame.0)\" y=\"\(frame.1)\" width=\"\(frame.2)\" height=\"\(frame.3)\"/>\n"
            + "<autoresizingMask key=\"autoresizingMask\" flexibleMaxX=\"YES\" flexibleMaxY=\"YES\"/>\n"
            + LabelTests.font(["type": "system", "pointSize": "\(size)"]) + "\n\(color)<nil key=\"highlightedColor\"/>\n</label>\n"
    }

    static let detailColor = #"<color key="textColor" red="0.55686274509803924" green="0.55686274509803924" blue="0.57647058823529407" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>"# + "\n"

    static func styledCell(_ style: String, _ labels: [String], _ ids: [(String, String)], _ extra: String = "") -> String {
        CellTests.cellXIB(extra + " " + ids.map { "\($0.0)=\"\($0.1)\"" }.joined(separator: " ") + " style=\"\(style)\"",
                          content: "<subviews>\n" + labels.joined() + "</subviews>\n")
    }

    static func mask(_ excluded: [Int]) -> String {
        "<variation key=\"default\">\n<mask key=\"constraints\">\n"
            + excluded.map { "<exclude reference=\"c\(String(format: "%02d", $0))-aa-aaa\"/>\n" }.joined() + "</mask>\n</variation>\n"
    }

    /// tofu's code view: two labels in a view whose default leaves out three of its constraints.
    static func maskGroup(_ excluded: [Int]) -> String {
        let constraints: [(Int, String?, String, String, String, String)] = [
            (10, "sss-aa-aaa", "top", "kkk-aa-aaa", "bottom", #" constant="-4""#), (11, "kkk-aa-aaa", "top", "own-aa-aaa", "top", #" constant="-4""#),
            (12, "kkk-aa-aaa", "top", "sss-aa-aaa", "bottom", ""), (13, nil, "bottom", "sss-aa-aaa", "bottom", ""),
            (14, "sss-aa-aaa", "leading", "own-aa-aaa", "leading", #" constant="1""#), (15, nil, "trailing", "sss-aa-aaa", "trailing", ""),
            (16, "kkk-aa-aaa", "top", "sss-aa-aaa", "bottom", ""), (17, "kkk-aa-aaa", "leading", "own-aa-aaa", "leading", ""),
            (18, "sss-aa-aaa", "top", "kkk-aa-aaa", "top", ""), (19, nil, "trailing", "kkk-aa-aaa", "trailing", ""),
        ]
        return "<view contentMode=\"scaleToFill\" translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"own-aa-aaa\">\n"
            + "<rect key=\"frame\" x=\"90\" y=\"10.5\" width=\"259\" height=\"63\"/>\n<subviews>\n"
            + C.subview("kkk-aa-aaa", (0, -4, 259, 53)) + C.subview("sss-aa-aaa", (1, 45, 258, 18)) + "</subviews>\n<constraints>\n"
            + constraints.map { C.constraint($0.0, $0.1, $0.2, $0.3, $0.4, $0.5) }.joined() + "</constraints>\n" + mask(excluded) + "</view>\n"
    }

    static let pinGroup = C.constraint(0, "own-aa-aaa", "leading", C.root, "leading", #" constant="90""#)
        + C.constraint(1, "own-aa-aaa", "top", C.root, "top", #" constant="10.5""#)
    static let custom = CellTests.customClass

    static let cases: [(String, String, Int, String)] = [
        ("tf-template", C.constrained(field(), pin("txf-aa-aaa", 0, 16, 100)), 2207, "25f08fcce4d1514f6872e0b52c7edae26909502548a82d9f905a605ed89f28d2"),
        ("tf-text", C.constrained(field(textField.replacingOccurrences(of: #"placeholder="Name""#, with: #"text="test@example.com" placeholder="Name""#)),
                                  pin("txf-aa-aaa", 0, 16, 100)), 2242, "6f9b0edbb888142c7adcfccb1ac7c03a06ff41f4fcd1d851ace7702eb5174a6c"),
        ("tf-border-rounded", C.constrained(field(textField.replacingOccurrences(of: #"textAlignment="natural""#, with: #"borderStyle="roundedRect" textAlignment="natural""#)),
                                            pin("txf-aa-aaa", 0, 16, 100)), 2270, "92cb516d8b7971a046b49fd0d2550c919458dc8baca681bc965aa5844ca32ed2"),
        ("tf-traits-all", C.constrained(field(textField.replacingOccurrences(of: #"placeholder="Name""#, with: #"text="x" placeholder="Name""#),
                                              traits: #" autocorrectionType="no" spellCheckingType="no" keyboardType="numberPad""#), pin("txf-aa-aaa", 0, 16, 100)),
         2292, "6e2c43454be4306e7ffb5984d342cd3fa747ee4205d58d95c6487024b716eae7"),
        ("tf-action", C.constrained(field(connections: actions(("editingChanged:", "editingChanged"))), pin("txf-aa-aaa", 0, 16, 100)),
         2336, "6dcdeccec75708b4402916ca84ee079f4a0db4eac8827c40a8fa5db1253d89fd"),
        ("sw-template", C.constrained(toggle(), pin("swt-aa-aaa", 0, 302, 100)), 1441, "f876f1e9853c70b0bf025c6e3654de9e8db752ba4ce513209a419dee0405df9f"),
        ("sw-on", C.constrained(toggle(switchAttributes + #" on="YES""#), pin("swt-aa-aaa", 0, 302, 100)), 1454, "96141edc9fe754e55d7c93c915a182285cd08229cec7675f4ef551122de3f2a1"),
        ("ev-switch-alpha-field-zeta", C.constrained(toggle(connections: actions(("alpha", "valueChanged")))
                                                     + field(id: "tf1-aa-aaa", y: 200, connections: actions(("zeta:", "editingChanged"))),
                                                     pin("swt-aa-aaa", 0, 302, 100) + pin("tf1-aa-aaa", 1, 16, 200)),
         2777, "d0885a1a78a4e084a1d67b8046544cea74481c4d81ec47c7589c73d2ed589877"),
        ("ev-field-two-events", C.constrained(field(id: "tf1-aa-aaa", y: 200, connections: actions(("alpha:", "editingDidEnd"), ("beta:", "editingChanged"))),
                                              pin("tf1-aa-aaa", 0, 16, 200)), 2371, "2678da65ee8797246e312d89caaf532d108e4e05d718e78807e3dfad238ff633"),
        ("cell-all-keys", CellTests.cellXIB(#" showsReorderControl="YES" reuseIdentifier="Cell" editingAccessoryType="disclosureIndicator" accessoryType="disclosureIndicator" indentationLevel="1""#
                                            + custom, selection: "none"), 3040, "396e2d52ce0a5e9ad151285bc49d8ad6a103c5837246c5e9b4e30377f844c89b"),
        ("cell-style-default", styledCell("IBUITableViewCellStyleDefault", [styleLabel("tlb-aa-aa1", "Title", (16, 0, 288, 44))], [("textLabel", "tlb-aa-aa1")]),
         2378, "f43b05a9a37683e552c9d286b3557b5bcdae91a9492b65b47b9c1a4fdfbdeaac"),
        ("cell-style-value1", styledCell("IBUITableViewCellStyleValue1", [styleLabel("tlb-aa-aa1", "Algorithm", (16, 13, 70.5, 19.5)),
                                                                         styleLabel("dlb-aa-aa1", "SHA1", (265.5, 13, 38.5, 19.5), alignment: "right", color: detailColor)],
                                         [("textLabel", "tlb-aa-aa1"), ("detailTextLabel", "dlb-aa-aa1")]),
         2706, "b40550b38dc618c065201e450a29728a6260ebf64c146f22287bac91ba1bb004"),
        ("cell-style-subtitle", styledCell("IBUITableViewCellStyleSubtitle", [styleLabel("tlb-aa-aa1", "Title", (16, 5, 33, 20.5), size: 17),
                                                                             styleLabel("dlb-aa-aa1", "Subtitle", (16, 25.5, 44, 14.5), size: 12)],
                                           [("textLabel", "tlb-aa-aa1"), ("detailTextLabel", "dlb-aa-aa1")]),
         2684, "870c57514f1500b6f29bbbdc5580d4f152d6aab574f05c0f671af071e91f7e5b"),
        ("table-selection-flags", TableViewTests.tableXIB(TableViewTests.attributes + #" allowsSelectionDuringEditing="YES" allowsSelection="NO""#),
         1897, "a85accd67c7e59acdad08ece9587ad20b18ad391f2e68d5f09ef0331731baa6c"),
        ("symbolic-constant", C.constrained(C.subview("aaa-aa-aa1") + C.subview("bbb-bb-bb1", (200, 20, 100, 50)),
                                            C.constraint(0, "bbb-bb-bb1", "leading", "aaa-aa-aa1", "trailing", #" constant="8" symbolic="YES""#)),
         1272, "000b025dd8ceda45088e10a01379a6e4d9a7184232795573a9f25399c1e8aca7"),
        ("mask-group-tofu", C.constrained(maskGroup([12, 16, 18]), pinGroup), 2560, "8bcdb71d5208951a6c49d7d14350b066ee010ebbc86f46a66c6e1407b32ddb6c"),
        ("mask-root-two", C.constrained(C.subview(), C.constraint(0, C.sub, "leading", C.root, "leading") + C.constraint(1, C.sub, "top", C.root, "top")
                                        + C.constraint(2, C.sub, "leading", C.root, "leading", #" constant="8""#)
                                        + C.constraint(3, C.sub, "top", C.root, "top", #" constant="8""#))
            .replacingOccurrences(of: "<point key=\"canvasLocation\"", with: mask([2, 3]) + "<point key=\"canvasLocation\""),
         1840, "41f929dcf01c30483d5d9a05178d4e2b2cf720a2b1030ef3d2576481457faf1b"),
        ("mask-cell-group", CellTests.cellXIB(content: "<subviews>\n" + maskGroup([12, 16, 18]) + "</subviews>\n<constraints>\n"
                                              + C.constraint(0, "own-aa-aaa", "leading", CellTests.content, "leading", #" constant="90""#)
                                              + C.constraint(1, "own-aa-aaa", "top", CellTests.content, "top", #" constant="10.5""#) + "</constraints>\n",
                                              size: (375, 84)), 3454, "b8aece1e94f535042aa6fd186965246b65d7c9eb88e9e7778a74c29f3bb633fb"),
        ("mask-cell-content", CellTests.cellXIB(content: "<subviews>\n" + C.subview(C.sub, (16, 11, 100, 22)) + "</subviews>\n<constraints>\n"
                                                + C.constraint(0, C.sub, "leading", CellTests.content, "leadingMargin") + C.constraint(1, C.sub, "top", CellTests.content, "top", #" constant="11""#)
                                                + C.constraint(2, C.sub, "leading", CellTests.content, "leadingMargin", #" constant="8""#) + "</constraints>\n" + mask([2]),
                                                size: (375, 44)), 2528, "19e24dfae9ad9743b0e08fd139016922aee1fa5e5e7cdd4bd397f9dd66f3141b"),
        ("frames-outside-left", C.constrained(C.subview("aaa-aa-aa1", (-20, 30, 100, 20)) + C.subview("bbb-bb-bb1", (10, 5, 100, 20)),
                                              pin("aaa-aa-aa1", 0, -20, 30) + pin("bbb-bb-bb1", 1, 10, 5)),
         1461, "39c8f6c755ed6f4288c46f28c1acc716a4b1549989b1ec57248c7c64751b864a"),
        ("tf-enables-return-key-all", C.constrained(field(traits: #" autocorrectionType="no" spellCheckingType="no" keyboardType="numberPad" enablesReturnKeyAutomatically="YES""#),
                                                    pin("txf-aa-aaa", 0, 16, 100)), 2306, "9a2c6a1f47d8280d7688359918ffe8ca6061f0196ade17f925336922ab354407"),
        ("baseline-firstBaseline-siblings", C.constrained(C.subview("xxx-xx-xx1") + C.subview("yyy-yy-yy1", (150, 20, 100, 50)),
                                                          pin("xxx-xx-xx1", 0, 10, 20) + pin("yyy-yy-yy1", 1, 150, 20)
                                                          + ["centerX", "leading", "centerY", "bottom", "firstBaseline", "top", "height"].enumerated().map {
                                                              C.constraint(10 + $0.offset, "xxx-xx-xx1", $0.element, "yyy-yy-yy1", $0.element)
                                                          }.joined()), 1751, "0420691cfa137ebc748d4f696346eb529ba77d23fc29d8f4b2d828ec3f04b2c9"),
        ("constraint-user-label", C.constrained(C.subview(), C.constraint(0, C.sub, "leading", C.root, "leading", #" userLabel="Leading""#)
                                                + C.constraint(1, C.sub, "top", C.root, "top")), 1188, "b30ed580c11b470322347fcd0e49b3849556189f61b135914691c1be49e56cf5"),
        ("sw-on-both-tints", C.constrained(toggle(switchAttributes + #" on="YES""#, connections:
            #"<color key="onTintColor" red="0.2" green="0.4" blue="0.6" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>"# + "\n"
            + #"<color key="thumbTintColor" red="0.8" green="0.4" blue="0.6" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>"# + "\n"),
                                           pin("swt-aa-aaa", 0, 302, 100)), 1799, "3544c7294cf108f824bb5d8c630007122358b34516ffa88266ba31dbe9f7705f"),
        ("cross-attribute-group", C.constrained(C.subview(), C.constraint(0, nil, "trailing", C.sub, "trailing") + C.constraint(1, C.sub, "leading", C.root, "leading")
                                                + C.constraint(2, C.sub, "bottom", C.root, "centerY") + C.constraint(3, C.sub, "top", C.root, "top")),
         1270, "c7a74e3b9d1b6da96a58228f59337e68385340e6d1685f02d0263ee14fa09438"),
        ("mask-subviews-cell", CellTests.cellXIB(content: "<subviews>\n" + C.subview("aaa-aa-aa1", (10, 5, 100, 30)) + C.subview("bbb-bb-bb1", (150, 5, 100, 30))
                                                 + "</subviews>\n<constraints>\n" + C.constraint(0, "aaa-aa-aa1", "leading", CellTests.content, "leading", #" constant="10""#)
                                                 + C.constraint(1, "aaa-aa-aa1", "top", CellTests.content, "top", #" constant="5""#) + "</constraints>\n"
                                                 + "<variation key=\"default\">\n<mask key=\"subviews\">\n<exclude reference=\"bbb-bb-bb1\"/>\n</mask>\n</variation>\n"),
         2535, "55208acc1b5543e6f67459385b742f278fa9bc80f4b9c631df920dcb0d6953a7"),
        ("deep-grandchild-absolute-near", C.constrained("<view contentMode=\"scaleToFill\" translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"aaa-aa-aa1\">\n"
                                                        + "<rect key=\"frame\" x=\"0\" y=\"0\" width=\"200\" height=\"200\"/>\n<subviews>\n"
                                                        + C.subview("ggg-gg-gg1", (5, 5, 50, 50)) + "</subviews>\n</view>\n" + C.subview("bbb-bb-bb1", (50, 50, 20, 20)),
                                                        pin("aaa-aa-aa1", 0, 0, 0) + pin("bbb-bb-bb1", 1, 50, 50)
                                                        + C.constraint(10, "ggg-gg-gg1", "leading", C.root, "leading", #" constant="5""#)
                                                        + C.constraint(11, "ggg-gg-gg1", "top", C.root, "top", #" constant="5""#)),
         1642, "7b069c748080c259761d1e6398bf5a5006f12f5fc20be9d16d3edbf33dba0c42"),
        ("deep-cell-both", CellTests.cellXIB(content: "<subviews>\n" + C.subview("sss-ss-ss1", (16, 11, 100, 22)) + C.subview("ttt-tt-tt1", (200, 11, 50, 22))
                                             + "</subviews>\n<constraints>\n" + C.constraint(2, "ttt-tt-tt1", "leading", CellTests.content, "leading", #" constant="200""#)
                                             + C.constraint(3, "ttt-tt-tt1", "top", CellTests.content, "top", #" constant="11""#) + "</constraints>\n",
                                             cellExtra: "<constraints>\n" + C.constraint(0, "sss-ss-ss1", "leading", CellTests.cell, "leading", #" constant="16""#)
                                             + C.constraint(1, "sss-ss-ss1", "top", CellTests.cell, "top", #" constant="11""#) + "</constraints>\n"),
         2203, "a39702b903f43c8644bf0bcc6c4cdac4784382717473f413941fd3e76be73c48"),
        ("tie-identical-normalized", C.constrained(C.subview(), C.constraint(0, C.sub, "leading", C.root, "leading") + C.constraint(1, C.sub, "top", C.root, "top")
                                                   + C.constraint(2, nil, "trailing", C.sub, "trailing", #" constant="5""#)
                                                   + C.constraint(3, nil, "trailing", C.sub, "trailing", #" constant="5""#)),
         1334, "f060b0116ccbdbb9ebaa24885543c0097bcc39676cee651db6b190554221e3e0"),
        ("tie-constant-reversed", C.constrained(C.subview(), C.constraint(0, C.sub, "leading", C.root, "leading", #" constant="8""#)
                                                + C.constraint(1, C.sub, "leading", C.root, "leading") + C.constraint(2, C.sub, "top", C.root, "top")
                                                + C.constraint(3, C.sub, "top", C.root, "top", #" constant="-4""#)),
         1334, "700cf0d182f3d9cd814c3ca49b9b5c309a0477163357e0185ed5714c972f62c3"),
    ]

    /// Text fields' and switches' keys, a switch's frame pair, actions by event, selector and
    /// source, cells' styles and keys, masks' relationship storages, constraints tied but for
    /// their constants in document order.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
