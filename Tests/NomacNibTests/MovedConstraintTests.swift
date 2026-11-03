import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for constraints installed on a descendant of the view that lists
/// them (`.github/scripts/nib_experiments.py` round 56, `moved-*`): sizes and SHA-256 digests of
/// Xcode's nibs.
@Suite struct MovedConstraintTests {
    typealias C = ConstraintTests
    static let s = "sss-ss-ss1", t = "ttt-tt-tt1", g = "ggg-gg-gg1", a = "aaa-aa-aa1"

    static func movedView(_ rootConstraints: String, own: String) -> String {
        let holder = "<view contentMode=\"scaleToFill\" translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"\(a)\">\n"
            + "<rect key=\"frame\" x=\"100\" y=\"100\" width=\"200\" height=\"200\"/>\n<subviews>\n" + C.subview(g, (5, 5, 50, 50))
            + "</subviews>\n<constraints>\n\(own)</constraints>\n</view>\n"
        return C.constrained(holder + C.subview("bbb-bb-bb1", (300, 300, 20, 20)),
                             TofuFeatureTests.pin(a, 0, 100, 100) + TofuFeatureTests.pin("bbb-bb-bb1", 1, 300, 300) + rootConstraints)
    }

    static let cellMixed = CellTests.cellXIB(content: "<subviews>\n" + C.subview(s, (16, 11, 100, 22)) + C.subview(t, (200, 11, 50, 22)) + "</subviews>\n"
                                                 + "<constraints>\n" + C.constraint(3, s, "top", CellTests.content, "top", #" constant="11""#) + "</constraints>\n",
                                             cellExtra: "<constraints>\n" + C.constraint(0, t, "top", s, "top")
                                                 + C.constraint(1, s, "leading", CellTests.cell, "leading", #" constant="16""#)
                                                 + C.constraint(2, t, "leading", s, "trailing", #" constant="84""#) + "</constraints>\n")

    static let cases: [(String, String, Int, String)] = [
        ("moved-view-two", movedView(C.constraint(10, nil, "trailing", g, "trailing", #" constant="145""#)
                                         + C.constraint(13, g, "bottom", a, "bottom", #" constant="-145""#),
                                     own: C.constraint(11, g, "top", a, "top", #" constant="5""#)),
         1755, "c62cb9d384a50fdfbb95eff309bb3207b6346be37012265fed13fbb64495708e"),
        ("moved-view-with-own", movedView(C.constraint(10, g, "leading", a, "leading", #" constant="5""#),
                                          own: C.constraint(11, g, "top", a, "top", #" constant="5""#) + C.constraint(12, g, "width", a, "width", #" multiplier="0.25""#)),
         1758, "d007f4b09102a0c02fa099caad1d6e2d3d3041410fe5ecfd933ae018d3658b42"),
        ("moved-cell-mixed", cellMixed, 2183, "5b016208406e854ea27107033f3080c51da547c508501aa1b950d47e016b9a84"),
    ]

    /// A constraint moves to its items' nearest common ancestor and sorts among that view's own; in
    /// all objects one between that view's subviews stays with the cell that listed it.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }

    /// A constraint between a subview's two subviews listed by a view: not observed.
    @Test func refusesSiblingsMovedOutOfAView() {
        let inner = C.subview(Self.g, (5, 5, 50, 50)) + C.subview("hhh-hh-hh1", (100, 5, 50, 50))
        let holder = "<view contentMode=\"scaleToFill\" translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"\(Self.a)\">\n"
            + "<rect key=\"frame\" x=\"100\" y=\"100\" width=\"200\" height=\"200\"/>\n<subviews>\n\(inner)</subviews>\n</view>\n"
        let xib = C.constrained(holder, TofuFeatureTests.pin(Self.a, 0, 100, 100) + C.constraint(10, "hhh-hh-hh1", "leading", Self.g, "trailing", #" constant="45""#))
        #expect(throws: NomacError("nomac does not compile a constraint between a subview's subviews listed by another view than a cell yet (BACKLOG B-265)",
                                   path: "/tmp/View.xib")) {
            try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        }
    }
}
