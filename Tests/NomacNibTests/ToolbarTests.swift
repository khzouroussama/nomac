import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for toolbars among subviews (`.github/scripts/nib_experiments.py`
/// round 61, `toolbar-*`, `sb-toolbar`): sizes and SHA-256 digests of Xcode's nibs.
@Suite struct ToolbarTests {
    static let attributes = #" opaque="NO" clearsContextBeforeDrawing="NO" contentMode="scaleToFill""#

    static func toolbar(_ frame: (Double, Double, Double, Double) = (0, 0, 393, 49), items: String = "<items/>\n", constraints: String = "") -> String {
        ConstraintTests.subview("tbr-aa-aa1", frame, tag: "toolbar", attributes: attributes, constraints: constraints)
            .replacingOccurrences(of: "</toolbar>", with: items + "</toolbar>")
    }

    static let cases: [(String, String, Int, String)] = [
        ("toolbar-empty", ConstraintTests.constrained(toolbar(), ""), 1016, "dc8862b6e45571c88adb0a271e52abe9fe2f8fcba73eab34fd6cad84fdb80192"),
        ("toolbar-no-items", ConstraintTests.constrained(toolbar(items: ""), ""), 1016, "dc8862b6e45571c88adb0a271e52abe9fe2f8fcba73eab34fd6cad84fdb80192"),
        ("toolbar-height-constraint", ConstraintTests.constrained(toolbar((0, 808, 393, 44), constraints: #"<constraint firstAttribute="height" constant="44" id="tbh-aa-aa1"/>"# + "\n"), ""),
         1272, "edff81058854afa8a47d94f163f1cca61124f0855d42261c3ad69ca41d931b2d"),
        ("toolbar-negative-x", ConstraintTests.constrained(toolbar((-8, 0, 423, 49)), ""), 1016, "86037f6da17a86ca287f7fd93d751f20d3122bac540b81fa8778f9e52ae82590"),
    ]

    /// A view's keys with its content hugging priorities, then the nib's empty array as items, the
    /// bar position and translucence 1.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }

    /// `sb-toolbar`: the view nib's empty array, as in a xib.
    @Test func compilesInAStoryboard() throws {
        let document = StoryboardCompilerTests.storyboard(StoryboardCompilerTests.scene(viewChildren: "<subviews>\n\(Self.toolbar((0, 808, 393, 44)))</subviews>\n"))
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        let nib = try #require(compiled["BYZ-38-t0r-view-8bC-Xf-vdC.nib"])
        #expect(nib.count == 1933)
        #expect(VariationTests.digest(nib) == "45ac88c3b3cf4b81cf85ddc953af6189aca5a71791b99a87c314a8c252eec72e")
    }
}
