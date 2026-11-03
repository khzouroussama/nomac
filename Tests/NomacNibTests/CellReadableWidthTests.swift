import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for table view cells' and their content views'
/// `layoutMarginsFollowReadableWidth` (`.github/scripts/nib_experiments.py` round 103): sizes and
/// SHA-256 digests of Xcode's nibs.
@Suite struct CellReadableWidthTests {
    static let readable = #" layoutMarginsFollowReadableWidth="YES""#

    static let cases: [(String, String, Int, String)] = [
        ("cell-readable", CellTests.cellXIB(readable), 1445, "6856c6f069fa3afc4e06fe3063cf31410501c54128d6ca54f95432ddd6f0ecfb"),
        ("cell-readable-no", CellTests.cellXIB(#" layoutMarginsFollowReadableWidth="NO""#), 1404, "2202b4055e54fde73015034c15a0171e76508710208c5809cb0478c0666b33e0"),
        ("cell-content-readable", CellTests.cellXIB("", contentAttributes: readable), 1445, "8463dd42325b958a79a1c0d22596601d96611731a69266534f45bd868c828109"),
        ("cell-readable-both", CellTests.cellXIB(readable, contentAttributes: readable), 1447, "9e4286782a4a5035c0e869938b7fe65f5ba00adb80b971c6392d940ac9c795a1"),
        ("cell-readable-preserves", CellTests.cellXIB(readable + #" preservesSuperviewLayoutMargins="YES""#),
         1522, "a96235f85092bcd0e3832e3037b472f18876330d39156ce6af33ee621057ba6a"),
    ]

    /// `UIViewLayoutMarginsFollowReadableWidth` true where any view writes it, before the preserved
    /// superview margins.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
