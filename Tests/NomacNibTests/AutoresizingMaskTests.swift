import Foundation
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for a subview that does not translate its autoresizing mask
/// into constraints and has a mask (`.github/scripts/nib_experiments.py` round 64,
/// `no-translate-mask-*`): sizes and SHA-256 digests of Xcode's nibs.
@Suite struct AutoresizingMaskTests {
    typealias C = ConstraintTests

    static func masked(_ bits: String) -> String {
        C.subview(C.sub, (20, 40, 100, 50)).replacingOccurrences(of: #"height="50.0"/>"#,
                                                                   with: #"height="50.0"/>"# + "\n<autoresizingMask key=\"autoresizingMask\"\(bits)/>")
    }

    static let all = #" flexibleMinX="YES" widthSizable="YES" flexibleMaxX="YES" flexibleMinY="YES" heightSizable="YES" flexibleMaxY="YES""#
    static let cases: [(String, String, Int, String)] = [
        ("no-translate-mask-sizable", C.constrained(masked(#" widthSizable="YES" heightSizable="YES""#), TofuFeatureTests.pin(C.sub, 0, 20, 40)),
         1252, "aa5c61d6fe8c1fafbcf2fd93c696fa00357588bc5162bd676f86848aa6440fa7"),
        ("no-translate-mask-empty", C.constrained(masked(""), TofuFeatureTests.pin(C.sub, 0, 20, 40)),
         1249, "e7f6ae082c9383811ed6eebd6179859064cd4558e438e52fc6f6450e4f1bc687"),
        ("no-translate-mask-all-unconstrained", C.constrained(masked(all), ""), 872, "09522c5441779cd5795a9eca734809b4be0bb3b90f497f93b51637519c2a2d01"),
    ]

    /// The document's mask as written, an empty one writing none; does-not-translate only when
    /// constrained.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
