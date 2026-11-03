import Foundation
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for constraints written from the view to a subview, with
/// margins and centers (`.github/scripts/nib_experiments.py` rounds 47 and 50, `norm-*`), identified
/// constraints with a constant and a priority (`identified-constant-priority`), and for a view constrained
/// to a stack view's arranged subview (`deep-through-stack`): sizes and SHA-256 digests of Xcode's
/// nibs.
@Suite struct NormalizedMarginTests {
    typealias C = ConstraintTests
    static let sub = C.subview(C.sub, (8, 8, 100, 100))
    static let all = [("leftMargin", "left"), ("rightMargin", "right"), ("topMargin", "top"), ("bottomMargin", "bottom"), ("leadingMargin", "leading"),
                      ("trailingMargin", "trailing"), ("centerXWithinMargins", "centerX"), ("centerYWithinMargins", "centerY"), ("left", "left"),
                      ("right", "right"), ("top", "top"), ("bottom", "bottom"), ("leading", "leading"), ("trailing", "trailing"), ("centerX", "centerX"),
                      ("centerY", "centerY"), ("width", "width"), ("height", "height")]

    static func norm(_ number: Int, _ viewAttribute: String, _ subAttribute: String, _ extra: String = "") -> String {
        C.constraint(number, nil, viewAttribute, C.sub, subAttribute, extra)
    }

    static let stack = "<stackView opaque=\"NO\" contentMode=\"scaleToFill\" axis=\"vertical\" spacing=\"10\" translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"stk-aa-aa1\">\n"
        + "<rect key=\"frame\" x=\"0\" y=\"60\" width=\"200\" height=\"200\"/>\n<subviews>\n" + C.subview("ar1-aa-aa1", (0, 0, 200, 95))
        + C.subview("ar2-aa-aa1", (0, 105, 200, 95)) + "</subviews>\n</stackView>\n"
    static let cases: [(String, String, Int, String)] = [
        ("norm-all", C.constrained(sub, all.enumerated().map { norm($0.offset, $0.element.0, $0.element.1) }.joined()),
         1925, "0c18a9dfee1e0a8373cb673260ad96288eaa5631cdf41c3b11f45fe6fb081db3"),
        ("norm-margin-friends", C.constrained(sub, C.constraint(0, C.sub, "leading", C.root, "leadingMargin")
                                              + C.constraint(1, C.sub, "trailing", C.root, "trailingMargin", #" constant="-277""#)
                                              + norm(2, "topMargin", "top") + norm(3, "bottomMargin", "bottom", #" constant="736""#)),
         1354, "3f3d87412ea1b2b4a4d5fe24e3c97da676b898c7229defa3d3f69e0e3d2668ce"),
        ("norm-margin-top-plain-bottom", C.constrained(sub, C.constraint(0, C.sub, "leading", C.root, "leading", #" constant="8""#)
                                                       + norm(1, "topMargin", "top") + norm(2, "bottom", "bottom", #" constant="744""#)),
         1303, "b481698044148a37907681f7c80fddf1840c1ed34f510540e3e7650a2b565829"),
        ("norm-cross-margin-center", C.constrained(sub, C.constraint(0, C.sub, "top", C.root, "top", #" constant="8""#)
                                                   + norm(1, "trailingMargin", "centerX", #" constant="319""#)
                                                   + C.constraint(2, C.sub, "centerY", C.root, "centerY", #" constant="-368""#)),
         1313, "7ea5982a45ee872f4b0e5441a3dd5a8ac1bfc8ac2ad8f8503e1c179896efa254"),
        ("norm-cross-top-center", C.constrained(sub, C.constraint(0, C.sub, "leading", C.root, "leading", #" constant="8""#) + norm(1, "top", "centerY", #" constant="-58""#)),
         1252, "a61964851a7ac37f4899b1ec9404cd61703c63385ae7892bc0df06b986395539"),
        ("norm-cross-top-bottom", C.constrained(sub, C.constraint(0, C.sub, "leading", C.root, "leading", #" constant="8""#)
                                                + norm(1, "top", "bottom", #" constant="-108""#) + C.constraint(2, C.sub, "top", C.root, "topMargin")),
         1303, "b893ff3303eed2f52fa3f3fdd1992861d1cee62c150628eb91a059103909471c"),
        ("identified-constant-priority", C.constrained(sub, C.constraint(0, C.sub, "leading", C.root, "leading", #" priority="999" constant="8" identifier="a.leading""#)
                                                       + C.constraint(1, C.sub, "top", C.root, "top", #" constant="8" identifier="a.top""#)
                                                       + C.constraint(2, C.sub, "width", nil, nil, #" priority="250" constant="100" identifier="a.width""#)
                                                       + C.constraint(3, C.sub, "height", nil, nil,
                                                                      #" relation="greaterThanOrEqual" priority="750" constant="100" identifier="a.height""#)),
         1483, "d692936bfb49645742ece09d439fdeb6490fb318e87cd3ef53a09212cad73f30"),
        ("deep-through-stack", C.constrained(stack + C.subview("bbb-bb-bb1", (100, 100, 20, 20)),
                                             TofuFeatureTests.pin("stk-aa-aa1", 0, 0, 60) + TofuFeatureTests.pin("bbb-bb-bb1", 1, 100, 100)
                                                 + C.constraint(10, "ar2-aa-aa1", "trailing", C.root, "trailing", #" constant="-193""#)),
         1972, "77cbd07fb62be3bc1c4b759fee33ef0fe8940f9ce536f302d9a91151b5bb8c59"),
    ]

    /// Constraints sort by their attributes as written, the view's first in one written from the
    /// view, but by the second when it alone is a center; each pair's margins before its plain
    /// attributes and the top margin before the bottom one; an identifier before the constant's
    /// legacy key; a stack view's arranged subviews are named as deeper views.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
