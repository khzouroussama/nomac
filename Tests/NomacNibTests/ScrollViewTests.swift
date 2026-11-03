import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for scroll views in xibs (`.github/scripts/nib_experiments.py`
/// round 34, `scroll`): sizes and SHA-256 digests of Xcode's nibs.
@Suite struct ScrollViewTests {
    static let attributes = #"clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="scaleToFill""#
    static let guides = #"<viewLayoutGuide key="contentLayoutGuide" id="cnt-aa-aa1"/>"# + "\n" + #"<viewLayoutGuide key="frameLayoutGuide" id="frm-aa-aa1"/>"# + "\n"
    static let content = "<subviews>\n<view contentMode=\"scaleToFill\" translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"cnv-aa-aa1\">\n"
        + "<rect key=\"frame\" x=\"0.0\" y=\"0.0\" width=\"393\" height=\"1000\"/>\n</view>\n</subviews>\n"
    static let flags = #" showsHorizontalScrollIndicator="NO" showsVerticalScrollIndicator="NO" alwaysBounceVertical="YES" alwaysBounceHorizontal="YES""#
        + #" directionalLockEnabled="YES" keyboardDismissMode="interactive" delaysContentTouches="NO" canCancelContentTouches="NO" pagingEnabled="YES""#
        + #" bounces="NO" bouncesZoom="NO" scrollEnabled="NO" contentInsetAdjustmentBehavior="never" indicatorStyle="white" minimumZoomScale="0.5""#
        + #" maximumZoomScale="3""#

    static func pinned(_ item: String, _ other: String, from number: Int) -> String {
        ConstraintTests.edges.enumerated().map { ConstraintTests.constraint(number + $0.offset, item, $0.element, other, $0.element) }.joined()
    }

    static func scrollXIB(_ attributes: String = attributes, _ children: String = "", constraints: String = "") -> String {
        ConstraintTests.constrained("<scrollView \(attributes) translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"scr-aa-aa1\">\n"
                                    + #"<rect key="frame" x="0" y="0" width="393" height="852"/>"# + "\n\(children)</scrollView>\n", constraints)
    }

    static let cases: [(String, String, Int, String)] = [
        ("scroll", scrollXIB(), 1040, "ffc69fa32c50a15a77d67793ebffcf9b52b16ece852d6aa3fae36cb08e10b058"),
        ("scroll-flags", scrollXIB(attributes + flags), 1374, "246883c9d34946729639e8f6496f3c2e8bcf5bc9a6db210b6ea3eca4d5320752"),
        ("scroll-guides-constraints", scrollXIB(attributes, content + guides + "<constraints>\n" + pinned("cnv-aa-aa1", "scr-aa-aa1", from: 10)
                                                + "</constraints>\n", constraints: pinned("scr-aa-aa1", ConstraintTests.root, from: 0)),
         1931, "741bc4233f0c6b7522f6caad60adc833e7d174ca5520dd1f46f3e8ad132930ab"),
        ("scroll-content-guides-pinned", scrollXIB(attributes, content + guides + "<constraints>\n" + pinned("cnv-aa-aa1", "cnt-aa-aa1", from: 10)
                                                   + ConstraintTests.constraint(14, "cnv-aa-aa1", "width", "frm-aa-aa1", "width") + "</constraints>\n",
                                                   constraints: pinned("scr-aa-aa1", ConstraintTests.root, from: 0)),
         2694, "2b3b7d748e6251ab54ca570f77be57c238435dfb06914b359b5dc25e1e536725"),
        ("scroll-custom-class", scrollXIB(attributes + #" customClass="MyScroll" customModule="T" customModuleProvider="target""#),
         1125, "89fad187ee22b5241705d30920e1a3a24f68f2e02bc33315d620e4bfe9943249"),
        ("scroll-keyboardDismissMode-onDrag", scrollXIB(attributes + #" keyboardDismissMode="onDrag""#),
         1065, "99cf37a061bed2a55478ac781094d4c133171d24ab131048f189b3ae3367ee96"),
        ("scroll-contentInsetAdjustmentBehavior-always", scrollXIB(attributes + #" contentInsetAdjustmentBehavior="always""#),
         1040, "adc028043fbd1eadf277a8844b771c6c970ab4b09b3be39c3e356d7a3f4c31c6"),
    ]

    /// The scroll view's keys in ibtool's order after a view's, and its unreferenced layout guides
    /// listed as placeholders before its constraints.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }

    /// `scroll-scrollsToTop-NO` (writes nothing: not pinned).
    @Test(arguments: [
        (scrollXIB(attributes + #" scrollsToTop="NO""#), "the scrollsToTop attribute of <scrollView>"),
    ])
    func refusesWhatIsNotObservedYet(xib: String, what: String) throws {
        let error = try #require(throws: NomacError.self) {
            try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        }
        #expect(error.message.contains(what))
    }
}
