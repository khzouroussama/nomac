import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for restoration identifiers, cells' opacity and custom fonts
/// (`.github/scripts/nib_experiments.py` round 47): sizes and SHA-256 digests of Xcode's nibs.
@Suite struct RestorationAndFontsTests {
    static let fonts = "<customFonts key=\"customFonts\">\n<array key=\"Georgia.ttf\">\n<string>Georgia</string>\n</array>\n</customFonts>\n"
    static let georgia = LabelTests.font(["name": "Georgia", "family": "Georgia", "pointSize": "17"])

    static let cases: [(String, String, Int, String)] = [
        ("restoration-label", ConstraintTests.constrained(LabelTests.label(LabelTests.attributes + #" restorationIdentifier="Title""#), ""),
         1850, "32e69ed03319ee5ba915f6fe293e5852e02020e806e7fb3a35ca96b6b8450102"),
        ("restoration-margins", ConstraintTests.constrained(ConstraintTests.subview(attributes: #" restorationIdentifier="Box" insetsLayoutMarginsFromSafeArea="NO" preservesSuperviewLayoutMargins="YES" layoutMarginsFollowReadableWidth="YES""#)
            .replacingOccurrences(of: "</view>", with: #"<edgeInsets key="layoutMargins" top="1" left="2" bottom="3" right="4"/>"# + "\n</view>"), ""),
         1126, "571a647f12291f5eacca9dabadd1139f7c2ca3deb30d063dcf61780d36a941b6"),
        ("restoration-cell", CellTests.cellXIB(#" restorationIdentifier="Cell""# + CellTests.customClass), 1525, "75f4de1e7f9983db2cc9ce7dca3d05d9b59076994e64aee3aec905bf40a7161f"),
        ("cell-opaque-no", CellTests.cellXIB(#" opaque="NO""# + CellTests.customClass), 1483, "bf210398399d1d5277194c61cbc71538449440450d93ba57b984367be7f23973"),
        ("custom-fonts", ConstraintTests.constrained(LabelTests.label(font: georgia), "").replacingOccurrences(of: "<objects>", with: fonts + "<objects>"),
         1774, "e74bca80b311640f0a33b43cae3d7d73763533e41d7758b35ef713577b48f0f0"),
    ]

    /// `UIRestorationIdentifier` just before the semantic content attribute, a cell's opacity, and
    /// custom fonts changing no nib.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }

    /// The font files the partial Info.plist lists as `UIAppFonts` (`custom-fonts`).
    @Test func listsCustomFontFiles() throws {
        let xib = ConstraintTests.constrained(LabelTests.label(), "").replacingOccurrences(of: "<objects>", with: Self.fonts + "<objects>")
        #expect(try XIBCompiler.customFontFiles(Data(xib.utf8), path: "/tmp/View.xib") == ["Georgia.ttf"])
    }
}
