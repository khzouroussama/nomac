import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for symbolic constraints with constants, constraints to custom
/// layout margins and designables (`.github/scripts/nib_experiments.py` rounds 41 and 42): sizes and
/// SHA-256 digests of Xcode's nibs.
@Suite struct SymbolicAndMarginTests {
    static let sub = ConstraintTests.sub
    static let root = ConstraintTests.root

    static func box(_ margins: String) -> String {
        let pins = ConstraintTests.constraint(10, "inn-aa-aa1", "leading", "box-aa-aa1", "leadingMargin")
            + ConstraintTests.constraint(11, "box-aa-aa1", "trailingMargin", "inn-aa-aa1", "trailing")
            + ConstraintTests.constraint(12, "inn-aa-aa1", "top", "box-aa-aa1", "topMargin")
            + ConstraintTests.constraint(13, "box-aa-aa1", "bottomMargin", "inn-aa-aa1", "bottom")
        return ConstraintTests.constrained("<view contentMode=\"scaleToFill\" translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"box-aa-aa1\">\n"
                                           + #"<rect key="frame" x="10" y="20" width="200" height="100"/>"# + "\n<subviews>\n"
                                           + "<view contentMode=\"scaleToFill\" translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"inn-aa-aa1\">\n"
                                           + #"<rect key="frame" x="2" y="1" width="194" height="96"/>"# + "\n</view>\n</subviews>\n"
                                           + margins + "<constraints>\n\(pins)</constraints>\n</view>\n", "")
    }

    static let designable = ConstraintTests.constrained(ConstraintTests.subview(attributes: #" customClass="MyView" customModule="T" customModuleProvider="target""#), "")
        .replacingOccurrences(of: "</document>\n", with: "<designables>\n<designable name=\"sss-ss-ss1\">\n"
                              + #"<size key="intrinsicContentSize" width="41.5" height="20.5"/>"# + "\n</designable>\n</designables>\n</document>\n")

    static let cases: [(String, String, Int, String)] = [
        ("symbolic-leading-20", ConstraintTests.constrained(ConstraintTests.subview(), ConstraintTests.constraint(0, sub, "leading", root, "leading",
                                                                                                                   #" constant="20" symbolic="YES""#)),
         1185, "130d79e45bc7028005a7e297db76d38a04a738c395337d0654b2dc0695c90006"),
        ("symbolic-trailing-ge-20", ConstraintTests.constrained(ConstraintTests.subview(), ConstraintTests.constraint(0, nil, "trailing", sub, "trailing",
                                                                                                                       #" relation="greaterThanOrEqual" constant="20" symbolic="YES""#)),
         1199, "d23eff3869b3c1d3b9ecf525a63ba96496a168d857836a7833a1e77d3926813e"),
        ("symbolic-width", ConstraintTests.constrained(ConstraintTests.subview(), ConstraintTests.constraint(0, sub, "width", nil, nil, #" constant="20" symbolic="YES""#)),
         1122, "c832e608f80126f8b0f5cd29bd2aaf5fc5c10cbd92fd4578fb3661254192a3a1"),
        ("margin-custom-edge", box(#"<edgeInsets key="layoutMargins" top="1" left="2" bottom="3" right="4"/>"# + "\n"),
         1475, "efa2d39fb37f16394b8ff912ea0a6fcc141094b75c02452811ceb4d7140d16fc"),
        ("margin-custom-directional", box(#"<directionalEdgeInsets key="directionalLayoutMargins" top="1" leading="2" bottom="3" trailing="4"/>"# + "\n"),
         1511, "88f95835249f3bd43bc07aff047ab05f697666b2dec78ee5c2d285381b34f3f5"),
        ("margin-custom-zero", box(#"<edgeInsets key="layoutMargins" top="0.0" left="0.0" bottom="0.0" right="0.0"/>"# + "\n"),
         1424, "a48e6214f4733c1b1968809e9bba9774f600aa434b4772cc516b828355289797"),
        ("designable", designable, 964, "72e9bc079f7915267c52517b3c1220624faeac8fe29c8b8698fd24c8dc9ae05c"),
    ]

    /// A symbolic constraint writes `NSSpace` and no constant; a margin attribute's legacy constant
    /// adds its item's own margin on that side; designables change nothing.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
