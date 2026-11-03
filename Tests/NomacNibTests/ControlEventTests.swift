import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for controls' actions of every event, a date picker's action, and
/// long press, pinch, rotation and screen edge pan recognizers (`.github/scripts/nib_experiments.py`
/// round 105): sizes and SHA-256 digests of Xcode's nibs.
@Suite struct ControlEventTests {
    typealias A = ActionTests
    static let more = ["touchDown", "touchDownRepeat", "touchDragInside", "touchDragOutside", "touchDragEnter", "touchDragExit", "touchUpOutside",
                       "touchCancel", "menuActionTriggered"]

    static func acting(_ pairs: [(String, String?)]) -> String {
        ConstraintTests.constrained(A.control(A.actions(pairs)), TofuFeatureTests.pin("ctl-aa-aaa", 0, 10, 20))
    }

    static let datePicker = ConstraintTests.subview("dpk-aa-aa1", (0, 0, 350, 216), tag: "datePicker",
                                                    attributes: #" contentHorizontalAlignment="center" contentVerticalAlignment="center" datePickerMode="countDownTimer" "#
                                                        + #"minuteInterval="1" useCurrentDate="NO""#)
        .replacingOccurrences(of: "</datePicker>", with: A.actions([("picked:", "valueChanged")]) + "</datePicker>")

    static let cases: [(String, String, Int, String)] = [
        ("act-control-touchDown", acting([("acted:", "touchDown")]), 1459, "69c3a559aad0ed87e970c3c328a79efef6da373ab0249f9bd05b695944669261"),
        ("act-control-touchCancel", acting([("acted:", "touchCancel")]), 1460, "61fc9315d9a5cae06fdbe4cebcc07b3e6f0c95a2d390a3f0aea70960a42a4a3b"),
        ("act-control-menuActionTriggered", acting([("acted:", "menuActionTriggered")]), 1444, "d47f4a7cfb34e1a7b67c6f8dff7c6df53aac821409601f7f78d498e10aee579a"),
        ("act-control-every-event", acting((more + ["touchUpInside", "valueChanged"]).map { ("\($0):", Optional($0)) }),
         1979, "3cf25c0cc289714b5c745dc18fb9d8c8b4aa901d1d83ba70d6c5a028180ec75c"),
        ("act-date-picker", ConstraintTests.constrained(datePicker, ""), 1095, "89c9b2121a99953318157f07dc4a0f392e850539984a9a45f8af40e39027e66a"),
        ("gesture-long-press", GestureRecognizerTests.gesture("pongPressGestureRecognizer", "lpr-aa-aa1", #" allowableMovement="10" minimumPressDuration="0.5""#),
         1392, "d13226454d5825bb1288a66a98b55af86b9c1bf7daaece14722429b65f49853e"),
        ("gesture-long-press-long", GestureRecognizerTests.gesture("pongPressGestureRecognizer", "lpr-aa-aa1", #" allowableMovement="20" minimumPressDuration="5""#),
         1501, "622e02087ff155b30dc59bbfa1d33069a7cbeaea7ed3f18804d7d5de3fff4169"),
        ("gesture-pinch", GestureRecognizerTests.gesture("pinchGestureRecognizer", "pnc-aa-aa1"), 1287, "854390b15cf1032f71fc78c94dad6a3024c3a825108aa8df4e9e13304285f0a5"),
        ("gesture-rotation", GestureRecognizerTests.gesture("rotationGestureRecognizer", "rot-aa-aa1"), 1290, "4d39f772cfbdcab9942d53c0132ad0d9bb4194c69999d19c21f74a6d96f55e95"),
        ("gesture-edge-pan", GestureRecognizerTests.gesture("screenEdgePanGestureRecognizer", "edg-aa-aa1", #" minimumNumberOfTouches="1""#),
         1386, "673c59d40d7effbc0783050003fa5d19afe52e653dcbfc37a821928cc5731c85"),
    ]

    /// Every `UIControl.Event` bit, `menuActionTriggered` without a mask, sorted as before; a long
    /// press's inner tap recognizer of no taps and its non-default duration and movement; a screen
    /// edge pan's touch types 11 and edges 0.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
