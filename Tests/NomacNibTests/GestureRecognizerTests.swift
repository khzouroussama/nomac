import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for gesture recognizers and image views' accessibility sizing in
/// xibs (`.github/scripts/nib_experiments.py` rounds 49 and 50): sizes and SHA-256 digests of Xcode's nibs.
@Suite struct GestureRecognizerTests {
    static func gesture(_ tag: String, _ id: String, _ attributes: String = "") -> String {
        let view = ConstraintTests.subview().replacingOccurrences(of: "</view>", with: "<connections>\n"
            + "<outletCollection property=\"gestureRecognizers\" destination=\"\(id)\" appends=\"YES\" id=\"gr\(id.prefix(3))-aa-aa1\"/>\n</connections>\n</view>")
        let recognizer = "<\(tag)\(attributes) id=\"\(id)\">\n<connections>\n<action selector=\"tapped:\" destination=\"-1\" id=\"act-\(id.prefix(3))-aa1\"/>\n</connections>\n</\(tag)>\n"
        return ConstraintTests.constrained(view, "").replacingOccurrences(of: "</objects>", with: recognizer + "</objects>")
    }

    static let cases: [(String, String, Int, String)] = [
        ("image-view-adjusts", ConstraintTests.constrained(ConstraintTests.subview("iii-ii-ii1", (112, 333, 168, 185), tag: "imageView",
                                                                                   attributes: #" image="Logo" adjustsImageSizeForAccessibilityContentSizeCategory="YES""#),
                                                           "", resources: ConstraintTests.logo), 1135, "808975417a2053539c1e1413f870a084151061dc4d621f1d28c7991e03646984"),
        ("gesture-tap-two-taps", gesture("tapGestureRecognizer", "tap-aa-aa1", #" numberOfTapsRequired="2" numberOfTouchesRequired="2""#),
         1423, "aba47c0f6538f6b90ebabc72f89152526025eb3fcf605b267693a514c15ab480"),
        ("gesture-swipe-left-disabled", gesture("swipeGestureRecognizer", "swp-aa-aa1", #" enabled="NO" direction="left""#),
         1356, "66cef668de93c26f81ab19bee3052178105ef3347356e30ac5f4012fc87d6539"),
        ("gesture-empty-element-only", ConstraintTests.constrained(ConstraintTests.subview("sss-ss-ss1").replacingOccurrences(of: "</view>", with: "<gestureRecognizers/>\n</view>"), ""),
         872, "f656183e6e3a29a51ff1b04554564a7464b0f95b9eeaf34c0d58556f00ab8a80"),
        ("gesture-pan", gesture("panGestureRecognizer", "pan-aa-aa1", #" minimumNumberOfTouches="1""#), 1334, "5aed7e5084f31978116df7d0e950186cd860218286daf48407f885dc6426fc3c"),
    ]

    /// Recognizers as top-level objects with their kinds' keys, attached by an appending outlet
    /// collection of class `NSArray`, their actions target-action connections.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
