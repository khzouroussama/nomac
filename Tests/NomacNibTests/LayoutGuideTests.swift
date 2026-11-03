import Foundation
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for constraints to a scene's top and bottom layout guides
/// (`.github/scripts/nib_experiments.py` round 45, `sb-guide-*`): sizes and SHA-256 digests of the
/// scene view's nib.
@Suite struct LayoutGuideTests {
    typealias C = ConstraintTests
    static let top = "Llm-lL-Icb", bottom = "xb3-aO-Qok", view = "8bC-Xf-vdC", sub = "gsb-aa-aa1"
    static let guides = """
                            <layoutGuides>
                                <viewControllerLayoutGuide type="top" id="\(top)"/>
                                <viewControllerLayoutGuide type="bottom" id="\(bottom)"/>
                            </layoutGuides>

        """

    static func document(_ subviews: String, _ constraints: String) -> String {
        StoryboardCompilerTests.storyboard(StoryboardCompilerTests.scene(guides: guides, viewChildren: "<subviews>\n\(subviews)</subviews>\n<constraints>\n\(constraints)</constraints>\n"))
    }

    static let leading = C.constraint(0, sub, "leading", view, "leading", #" constant="20""#)
    static let cases: [(String, String, Int, String)] = [
        ("sb-guide-both", document(C.subview(sub, (20, 40, 100, 804)), leading + C.constraint(1, sub, "top", top, "bottom", #" constant="20""#)
                                   + C.constraint(2, bottom, "top", sub, "bottom", #" constant="8""#)),
         2002, "23a012279f9a323994025e47ca908326c99df4a7e309328bff930bf381c10d60"),
        ("sb-guide-bottom-group", document(C.subview(sub, (20, 744, 100, 100)) + C.subview("gs2-aa-aa1", (0, 800, 20, 20)),
                                           leading + C.constraint(1, bottom, "top", sub, "bottom", #" constant="8""#)
                                               + C.constraint(3, "gs2-aa-aa1", "leading", view, "leading") + C.constraint(4, "gs2-aa-aa1", "top", view, "top", #" constant="800""#)),
         2132, "586c66ce25a8fd99aeeba61d2b2b5f92d71b1b457584c88d18900ca8e7637eba"),
        ("sb-guide-top-and-height", document(C.subview(sub, (20, 40, 100, 100)), leading + C.constraint(1, sub, "top", top, "bottom", #" constant="20""#)
                                             + C.constraint(2, sub, "height", view, "height", #" multiplier="0.117""#)),
         2005, "ed479be7f2f9b4f788f7b9c33ba4229a10a768952854026cd119398469a95a29"),
    ]

    /// Layout guides as sibling subviews: a constraint naming one first in the guide's group, the
    /// guides at the view's top and bottom edges; one naming it second after its subview's
    /// constraints to the view.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, document: String, size: Int, digest: String) throws {
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        let data = try #require(compiled["BYZ-38-t0r-view-8bC-Xf-vdC.nib"], "\(name)")
        #expect(data.count == size, "\(name)")
        #expect(VariationTests.digest(data) == digest, "\(name)")
    }
}
