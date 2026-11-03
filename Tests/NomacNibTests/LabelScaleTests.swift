import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for labels' minimum scale factors (`.github/scripts/nib_experiments.py`
/// round 56, `label-style-scale-*`, `label-system-scale-*`): sizes and SHA-256 digests of Xcode's nibs.
@Suite struct LabelScaleTests {
    static func scaled(_ factor: String, style: String? = nil) -> String {
        let attributes = LabelTests.attributes.replacingOccurrences(of: #"adjustsFontSizeToFit="NO""#, with: "minimumScaleFactor=\"\(factor)\"")
        let font = style.map { LabelTests.font(["style": "UICTFontTextStyle\($0)"]) } ?? LabelTests.font(["type": "system", "pointSize": "17"])
        return LabelTests.labelled(LabelTests.label(attributes, font: font))
    }

    static let cases: [(String, String, Int, String)] = [
        ("label-style-scale-Body-0.5", scaled("0.5", style: "Body"), 1663, "739993bc6261e84ee5ee002525c6192cf0d9a3723d7082b43e5a3f96f8e4221b"),
        ("label-style-scale-Headline-0.7", scaled("0.7", style: "Headline"), 1668, "bd06b01a00afdbc05f9cd532fd9edd49621b69cafebcc6e98a9188c12de3cf62"),
        ("label-style-scale-Title0-0.5", scaled("0.5", style: "Title0"), 1665, "b48d0b00f39e0ad2b43238c71023b003d8bd5f2bac31ed508dd46720d1739c9d"),
        ("label-style-scale-Caption2-0.5", scaled("0.5", style: "Caption2"), 1667, "d87dcc89f35c10909011da3418454bb2ae57a392474ab5ff659ecd66e1e1f1eb"),
        ("label-system-scale-0.8", scaled("0.8"), 1885, "5727336728fe135ba7030b148757f19d7f554b53afa810a653c1d6792080e050"),
        ("label-system-scale-0.75", scaled("0.75"), 1885, "20d1e50ef85d986edcd12b62133d0d27b54745cb7f6ec5f28bf2912396acb729"),
    ]

    /// The minimum font size: the font's size, or a text style's at the default content size, times
    /// the factor, to the nearest quarter point.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
