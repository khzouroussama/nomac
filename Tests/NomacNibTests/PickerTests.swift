import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for date pickers, picker views, IB's comments and text views with
/// editable text attributes (`.github/scripts/nib_experiments.py` round 65): sizes and SHA-256
/// digests of Xcode's nibs.
@Suite struct PickerTests {
    static func view(_ tag: String, _ frame: (Double, Double, Double, Double), _ attributes: String = "") -> String {
        ConstraintTests.constrained(ConstraintTests.subview("\(tag == "datePicker" ? "dpk" : "pkv")-aa-aa1", frame, tag: tag, attributes: attributes), "")
    }

    static let datePicker = #" contentHorizontalAlignment="center" contentVerticalAlignment="center""#
    static let comments = "<attributedString key=\"userComments\">\n" + #"<fragment content="Placeholder - Do not translate"/>"# + "\n</attributedString>\n"
    static let editing = #"clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="scaleToFill" scrollEnabled="NO" showsHorizontalScrollIndicator="NO" "#
        + #"showsVerticalScrollIndicator="NO" contentInsetAdjustmentBehavior="never" editable="NO" allowsEditingTextAttributes="YES""#
    static let editingChildren = TextViewTests.background + #"<nil key="text"/>"# + "\n" + LabelTests.font(["type": "system", "pointSize": "17"]) + "\n"
        + #"<textInputTraits key="textInputTraits" autocapitalizationType="sentences" textContentType="url"/>"# + "\n"
        + #"<dataDetectorType key="dataDetectorTypes" link="YES"/>"# + "\n"

    static let cases: [(String, String, Int, String)] = [
        ("date-picker-countdown", view("datePicker", (0, 0, 350, 216), datePicker + #" datePickerMode="countDownTimer" minuteInterval="1" useCurrentDate="NO""#), 976,
         "5e340b7ddf12f79a11dd48413ae1c90650b068674dff4937634884e9b198b716"),
        ("date-picker-date-and-time", view("datePicker", (0, 0, 350, 216), datePicker + #" datePickerMode="dateAndTime" minuteInterval="1""#), 887,
         "69fd227e26fbf5f4a66407ad0f492e0647e0dbe2765822890b5323c602483009"),
        ("picker-view", view("pickerView", (0, 359, 393, 216)), 962, "29133900ff376ffc01e9de63cacc010478a3c5e1770de6665f2fd1b33120fb7f"),
        ("picker-view-margins", view("pickerView", (0, 0, 165, 80), #" preservesSuperviewLayoutMargins="YES""#), 1039,
         "3a5c0fa61fb96807b62357812a90b17a2a29cf82e390036894c610e4a54c90f7"),
        ("user-comments-label", LabelTests.labelled(LabelTests.label(extra: comments)), 1809, "d2955d7ebc8908ecefb8c536ab9721e43dab7096a4535b63a3e36cf7797de49d"),
        ("text-view-editing-attributes", TextViewTests.xib(editing, editingChildren), 2387, "c4e5fa180127aff9e5c30a2e1dd61e0480394647e22e6def47f7cdb49a07bacf"),
        ("text-view-nil-text", TextViewTests.xib(TextViewTests.attributes, TextViewTests.background + #"<nil key="text"/>"# + "\n" + TextViewTests.font + TextViewTests.traits),
         2217, "dfd69ae4050b78fc2412e86eea2d7cea8a3af1a9091b84a16a93bffb157c4890"),
    ]

    /// A date picker of date and time writes nothing, a count-down timer its mode, duration and
    /// current-date flag; a picker view its hugging and selectable cells; IB's comments nothing; a
    /// text view's editable text attributes after its scroll keys.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
