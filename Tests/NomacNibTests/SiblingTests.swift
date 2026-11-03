import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// The order of constraints between two subviews and of subviews' groups by their frames
/// (`.github/scripts/nib_experiments.py` round 26, `sib-*`): sizes and SHA-256 digests of Xcode's
/// nibs.
@Suite struct SiblingTests {
    static let a = "aaa-aa-aa1", b = "bbb-bb-bb1", root = ConstraintTests.root
    typealias Frame = (Double, Double, Double, Double)

    static func siblings(_ constraints: String, a aFrame: Frame = (10, 20, 100, 50), b bFrame: Frame = (10, 200, 100, 50)) -> String {
        ConstraintTests.constrained(ConstraintTests.subview(a, aFrame) + ConstraintTests.subview(b, bFrame), constraints)
    }

    static func constraint(_ number: Int, _ first: String, _ firstAttribute: String, _ second: String, _ secondAttribute: String) -> String {
        ConstraintTests.constraint(number, first, firstAttribute, second, secondAttribute)
    }

    static func frames(bx: Double, by: Double) -> String {
        ConstraintTests.constrained(ConstraintTests.subview(a, (10, 200, 100, 50)) + ConstraintTests.subview(b, (bx, by, 100, 50)),
                                    ConstraintTests.pinned(a, 0) + ConstraintTests.pinned(b, 4))
    }

    static let cases: [(String, String, Int, String)] = [
        ("order-sibling", siblings(ConstraintTests.pinned(a, 0) + ConstraintTests.constraint(4, b, "top", a, "bottom", #" constant="8""#)),
         1442, "d66b235ab5ed81d0182d60c89a4b18e3dd6b34c5f83ddfb3bfaec750c2959c1d"),
        ("sib-pair-leading-centerY", siblings(constraint(0, b, "leading", a, "leading") + constraint(1, b, "centerY", a, "centerY")),
         1275, "ddbe99dc60928ed30b19f1d418fa834aa4331c1f532bbdbd9115118237dcb435"),
        ("sib-mix-centerX-leading", siblings(constraint(0, b, "centerX", a, "centerX") + constraint(1, b, "leading", root, "leading")),
         1275, "aba59054ca062a141ab883269ecf25d721c8085a273de0c731969267db327b3b"),
        ("sib-with-both-a-bottom-top", siblings(constraint(0, a, "bottom", b, "top") + constraint(1, a, "leading", root, "leading")
                                                + constraint(2, b, "leading", root, "leading")),
         1316, "3c8e7a2ac74755f4496951fd52060b0c550c83770524d4a3cfb4625df94baf31"),
        ("order-two-diagonal-ab", frames(bx: 200, by: 20), 1521, "46047dd581ac452db8a4e4d9359911d7dbf0db35f12114b3e33ffb49a7dd60ce"),
        ("sib-frames-x-touching-y-apart-ab", frames(bx: 110, by: 20), 1521, "e838f150ee2f76cbb58ea26d50e510f1e791a41e7f06fe39426f50bf9b1c9452"),
        ("sib-frames-x-touching-y-overlap-ab", frames(bx: 110, by: 180), 1521, "085b5d66943dc82967e8bc4554bcc254c0fdb9796e5d54552be81a8a7c772f85"),
        ("sib-frames-x-overlap-y-overlap-ab", frames(bx: 60, by: 180), 1521, "5fdbbf309e3b1f1513d2cad93b3da6780c267dd6976bb5e5d2da21a8a69fdd56"),
    ]

    /// Sibling constraints in their first item's group after its constraints with the view, by the
    /// safe area's attribute order; groups by y where frames share a column, by x otherwise.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
