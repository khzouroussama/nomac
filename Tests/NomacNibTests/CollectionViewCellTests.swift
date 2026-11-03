import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for collection view cells and reusable views in xibs
/// (`.github/scripts/nib_experiments.py` round 35, `cv_cell`, `reusable`): sizes and SHA-256
/// digests of Xcode's nibs.
@Suite struct CollectionViewCellTests {
    static let cell = "gTV-IL-0wX"
    static let content = "ZTg-uK-7eu"
    static let custom = #" customClass="Cell" customModule="T" customModuleProvider="target""#
    static let flexible = #"<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>"# + "\n"
    static let safeArea = #"<viewLayoutGuide key="safeArea" id="sfa-aa-aa1"/>"# + "\n"
    static let customSize = #"<size key="customSize" width="50" height="50"/>"# + "\n"

    static func label(_ id: String = "lll-ll-ll1", y: Int = 14, height: Int = 21) -> String {
        "<label \(LabelTests.attributes) id=\"\(id)\">\n<rect key=\"frame\" x=\"4\" y=\"\(y)\" width=\"42\" height=\"\(height)\"/>\n"
            + LabelTests.font(["type": "system", "pointSize": "17"]) + "\n" + LabelTests.nilColors + "</label>\n"
    }

    static let labels = "<subviews>\n\(label())</subviews>\n"

    static func constraints(_ container: String) -> String {
        "<constraints>\n" + ConstraintTests.edges.enumerated().map { number, edge in
            ["top", "leading"].contains(edge) ? ConstraintTests.constraint(number, "lll-ll-ll1", edge, container, edge)
                : ConstraintTests.constraint(number, container, edge, "lll-ll-ll1", edge)
        }.joined() + "</constraints>\n"
    }

    static func cellXIB(_ inner: String = "", _ extra: String = "", attributes: String = custom, legacy: Bool = false,
                        contentMask: String = flexible) -> String {
        let contentView = legacy
            ? "<view key=\"contentView\" opaque=\"NO\" clipsSubviews=\"YES\" multipleTouchEnabled=\"YES\" contentMode=\"center\">\n"
                + #"<rect key="frame" x="0.0" y="0.0" width="50" height="50"/>"# + "\n\(contentMask)\(inner)</view>\n"
            : "<collectionViewCellContentView key=\"contentView\" opaque=\"NO\" clipsSubviews=\"YES\" multipleTouchEnabled=\"YES\" contentMode=\"center\" "
                + "insetsLayoutMarginsFromSafeArea=\"NO\" id=\"\(content)\">\n" + #"<rect key="frame" x="0.0" y="0.0" width="50" height="50"/>"#
                + "\n\(contentMask)\(inner)</collectionViewCellContentView>\n"
        var document = XIBCompilerTests.xib("<collectionViewCell opaque=\"NO\" clipsSubviews=\"YES\" multipleTouchEnabled=\"YES\" contentMode=\"center\"\(attributes) id=\"\(cell)\">\n"
                                            + #"<rect key="frame" x="0.0" y="0.0" width="50" height="50"/>"# + "\n" + #"<autoresizingMask key="autoresizingMask"/>"#
                                            + "\n\(contentView)\(extra)</collectionViewCell>\n")
        if extra.contains("safeArea") {
            document = document.replacingOccurrences(of: #" colorMatched="YES""#, with: #" useSafeAreas="YES" colorMatched="YES""#)
        }
        return document
    }

    static func reusableXIB(_ inner: String = "", attributes: String = #" customClass="Header" customModule="T" customModuleProvider="target""#) -> String {
        XIBCompilerTests.xib("<collectionReusableView opaque=\"NO\" clipsSubviews=\"YES\" multipleTouchEnabled=\"YES\" contentMode=\"center\"\(attributes) id=\"U6b-Vx-4bR\">\n"
                             + #"<rect key="frame" x="0.0" y="0.0" width="320" height="50"/>"# + "\n\(flexible)\(inner)</collectionReusableView>\n")
    }

    static let cases: [(String, String, Int, String)] = [
        ("cvcell", cellXIB(), 1584, "627dffd4c62f318723c5f33718e4b1ba47ae6515ae0bc9544df5a0c3bf8d68e3"),
        ("cvcell-reuse", cellXIB(attributes: #" reuseIdentifier="Cell""# + custom), 1618, "5d90fd188887ad7cfbabe70f96133952fee79a08ade1aac667866df8074deabe"),
        ("cvcell-label-content-constraints", cellXIB(labels + constraints(content)), 2790, "9ff731d2ddfee9ae785503827c0b365f8e1feee216474aecf287afcbb035393a"),
        ("cvcell-safe-area-label", cellXIB(labels + constraints(content), safeArea), 2985, "b024109065145e8d74776f50b3888fa5874d4366a0a95fabebe1408c9fa53e63"),
        ("cvcell-content-mask-empty", cellXIB(labels + constraints(content), contentMask: #"<autoresizingMask key="autoresizingMask"/>"# + "\n"),
         2787, "671c69d990a68a1e6a41b308c664a479d57d95c6ab15308e3331b3076fe05ba9"),
        ("cvcell-old", cellXIB("", safeArea + customSize, legacy: true), 1734, "bb0af49c081874e1976f18d1e46ccae0dd17fefc9e53077d32d97a68475482f2"),
        ("cvcell-old-label-cell-constraints", cellXIB(labels, safeArea + customSize + constraints(cell), legacy: true),
         3394, "d1eadba303ba284b0db1bbc65d353fa71b821739f75c5677f5765b3d47e31e4e"),
        ("cvcell-old-two-labels", cellXIB("<subviews>\n\(label())\(label("lll-ll-ll2", y: 0, height: 10))</subviews>\n", safeArea + customSize + constraints(cell),
                                          legacy: true), 3533, "c2ab8c2d5340ea8cadcef19c83e6459c790100c9dcd9f6fa526f1e55c7a41a18"),
        ("reusable-reuse", reusableXIB(attributes: #" reuseIdentifier="Header" customClass="Header" customModule="T" customModuleProvider="target""#),
         934, "749bc2b3fd998597953b4231388a4851f88337f49e5cf4f4ffbdaf5f9bcfaf0f"),
        ("reusable-label-constraints", reusableXIB(labels + constraints("U6b-Vx-4bR")), 2343, "b8b92e201b38014e2d06cfeca2af45be10c9eee7b1cb4017b322e165a335f051"),
    ]

    /// The cell's generated constraints to its content view, its reuse identifier and content view
    /// keys; the older template's content view a plain view taking the cell's constraints and, with
    /// a safe area and subviews, listing its safe area guide; reusable views as views.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }

    /// `cvcell-label-cell-constraints`: ibtool drops a cell's constraints in Xcode 12's template.
    @Test func refusesCellConstraintsOfTheContentViewTemplate() {
        #expect(throws: NomacError("nomac does not compile constraints of a collection view cell of Xcode 12's template yet (BACKLOG B-260)", path: "/tmp/View.xib")) {
            try XIBCompiler.compile(Data(Self.cellXIB(Self.labels, Self.constraints(Self.cell)).utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        }
    }
}
