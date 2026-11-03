import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for a subview's constraints to views deeper than the subviews
/// (`.github/scripts/nib_experiments.py` round 42, `deep-other-*`): sizes and SHA-256 digests of
/// Xcode's nibs.
@Suite struct DeepOtherTests {
    typealias C = ConstraintTests
    static let b = "bbb-bb-bb1", g = "ggg-gg-gg1", g2 = "gg2-gg-gg2", h = "hhh-hh-hh1"

    /// A view at 100, 100 holding a grandchild at 5, 5 (and its child at 2, 2, or a second
    /// grandchild at 100, 100), and a subview at 320, 320 whose constraints are `constraints`.
    static func document(_ constraints: String, safeArea: Bool = false, great: Bool = false, secondGrandchild: Bool = false) -> String {
        let deepest = great ? "<subviews>\n" + C.subview(h, (2, 2, 10, 10)) + "</subviews>\n" : ""
        let grandchildren = "<view contentMode=\"scaleToFill\" translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"\(g)\">\n"
            + "<rect key=\"frame\" x=\"5\" y=\"5\" width=\"50\" height=\"50\"/>\n\(deepest)</view>\n"
            + (secondGrandchild ? C.subview(g2, (100, 100, 50, 50)) : "")
        let outer = "<view contentMode=\"scaleToFill\" translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"aaa-aa-aa1\">\n"
            + "<rect key=\"frame\" x=\"100\" y=\"100\" width=\"200\" height=\"200\"/>\n<subviews>\n\(grandchildren)</subviews>\n</view>\n"
        return C.constrained(outer + C.subview(b, (320, 320, 20, 20)), TofuFeatureTests.pin("aaa-aa-aa1", 0, 100, 100) + constraints, safeArea: safeArea)
    }

    static func to(_ number: Int, _ attribute: String, _ other: String, _ otherAttribute: String, _ constant: Int) -> String {
        C.constraint(number, b, attribute, other, otherAttribute, " constant=\"\(constant)\"")
    }

    static let pins = to(2, "leading", C.root, "leading", 320) + to(3, "top", C.root, "top", 320)
    static let deepSafe = C.constrained("<view contentMode=\"scaleToFill\" translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"aaa-aa-aa1\">\n"
                                            + "<rect key=\"frame\" x=\"100\" y=\"100\" width=\"200\" height=\"200\"/>\n<subviews>\n"
                                            + C.subview(g, (5, 5, 50, 50)) + "</subviews>\n</view>\n",
                                        TofuFeatureTests.pin("aaa-aa-aa1", 0, 100, 100) + C.constraint(10, g, "top", C.safe, "top", #" constant="46""#)
                                            + C.constraint(11, g, "leading", C.safe, "leading", #" constant="105""#)
                                            + C.constraint(12, g, "width", C.root, "width", #" multiplier="0.127""#), safeArea: true)
    /// A view at 100, 100 holding a grandchild at -90, -90, held at 10, 10 by the root, and a sibling.
    static func negative(sibling: (Double, Double)?) -> String {
        let outer = "<view contentMode=\"scaleToFill\" translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"aaa-aa-aa1\">\n"
            + "<rect key=\"frame\" x=\"100\" y=\"100\" width=\"200\" height=\"200\"/>\n<subviews>\n" + C.subview(g, (-90, -90, 50, 50)) + "</subviews>\n</view>\n"
        let siblingView = sibling.map { C.subview(b, ($0.0, $0.1, 20, 20)) } ?? ""
        let pins = TofuFeatureTests.pin("aaa-aa-aa1", 0, 100, 100) + (sibling.map { TofuFeatureTests.pin(b, 1, Int($0.0), Int($0.1)) } ?? "")
        return C.constrained(outer + siblingView, pins + C.constraint(10, g, "leading", C.root, "leading", #" constant="10""#)
                                 + C.constraint(11, g, "top", C.root, "top", #" constant="10""#))
    }

    static let cases: [(String, String, Int, String)] = [
        ("deep-negative-offset", negative(sibling: nil), 1472, "876a3b43ee20f21a3e0098ccf43470cd3320c8a3897f0022c75997c0b54b51d3"),
        ("deep-negative-offset-sibling-far", negative(sibling: (300, 300)), 1682, "12a6eee1ac4be77b2ab258abc10ee882853e860b195cd894a4482e62c1d8476d"),
        ("deep-safe-two-and-view", deepSafe, 2196, "c9baeddadee96f5f4b38997ef942baf13fd0228e1a5ec7aa00f0d17be8245495"),
        ("deep-other-sibling", document(pins + to(10, "top", "aaa-aa-aa1", "bottom", 20) + to(11, "leading", g, "trailing", 165)),
         1682, "36c71526dc62f3a519fdf752ec23cecbb614a385c4a96cb0751c5fe18515d8cb"),
        ("deep-other-safe", document(to(2, "leading", C.root, "leading", 320) + to(3, "top", C.safe, "top", 320) + to(10, "leading", g, "trailing", 165), safeArea: true),
         2284, "1769ca8b77427482c5060ea6ee9a4e3223d82d02035f4c5006e84c2ec39e17ca"),
        ("deep-other-great-top-grand-leading", document(pins + to(10, "top", h, "bottom", 203) + to(11, "leading", g, "trailing", 165), great: true),
         1781, "6df0860ee020a37cbc09dbd146b2d6151f21a895a5e252e20bf2f47add0f3bb6"),
        ("deep-other-grand2-top-grand-leading", document(pins + to(10, "top", g2, "bottom", 70) + to(11, "leading", g, "trailing", 165), secondGrandchild: true),
         1770, "0ba4add41831e974c24586ad5cbe09ad3819b6ab4ba98cb6ef7dfcedc0476159"),
        ("deep-other-trailing-view", document(C.constraint(2, nil, "trailing", b, "trailing", #" constant="53""#) + to(3, "top", C.root, "top", 320)
                                              + to(10, "top", g, "bottom", 165)),
         1620, "3348208c2fc1ea777536ca9b67c23879a4d40bf0ff89999c1d0916adcbc0cc8b"),
    ]

    /// A grandchild nearer the origin than its parent right after it; constraints to deeper views first in their group, the deepest first, then by attribute; a
    /// deeper view's constraints to the safe area before those to the view; a deeper view a
    /// constraint names listed in all objects in that constraint's place.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }

    /// `deep-negative-offset-sibling`: a sibling between the grandchild's and its parent's distances
    /// gives an order no single key gives.
    @Test func refusesItemsAroundANearerDescendant() {
        #expect(throws: NomacError("nomac does not compile constraints of a view nearer the origin than the subview holding it, with another between them yet (BACKLOG B-265)",
                                   path: "/tmp/View.xib")) {
            try XIBCompiler.compile(Data(Self.negative(sibling: (50, 50)).utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        }
    }
}
