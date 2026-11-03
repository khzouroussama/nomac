import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for text views in xibs (`.github/scripts/nib_experiments.py`
/// round 51, `text-view`): sizes and SHA-256 digests of Xcode's nibs.
@Suite struct TextViewTests {
    static let attributes = #"clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="scaleToFill" textAlignment="natural""#
    static let text = #"<string key="text">Lorem ipsum</string>"# + "\n"
    static let font = LabelTests.font(["type": "system", "pointSize": "14"]) + "\n"
    static let traits = #"<textInputTraits key="textInputTraits" autocapitalizationType="sentences"/>"# + "\n"
    static let background = #"<color key="backgroundColor" systemColor="systemBackgroundColor"/>"# + "\n"
    static let resources = "<systemColor name=\"systemBackgroundColor\">\n" + XIBCompilerTests.gray("1", "1").replacingOccurrences(of: #" key="backgroundColor""#, with: "")
        + "\n</systemColor>\n"

    static func xib(_ attributes: String = attributes, _ children: String = background + text + font + traits) -> String {
        ConstraintTests.constrained("<textView \(attributes) translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"txv-aa-aa1\">\n"
                                    + #"<rect key="frame" x="16" y="40" width="240" height="128"/>"# + "\n\(children)</textView>\n", "", resources: resources)
    }

    static func traits(_ attributes: String) -> String {
        background + text + font + "<textInputTraits key=\"textInputTraits\" \(attributes)/>\n"
    }

    static let lorem = "Lorem ipsum dolor sit er elit lamet, consectetaur cillium adipisicing pecu, sed do eiusmod tempor incididunt ut labore et dolore "
        + "magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute "
        + "irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non "
        + "proident, sunt in culpa qui officia deserunt mollit anim id est laborum. Nam liber te conscient to factor tum poen legum odioque civiuda."

    static func long(_ length: Int) -> String {
        xib(attributes, background + "<string key=\"text\">\(lorem.prefix(length))</string>\n" + font + traits)
    }

    static let cases: [(String, String, Int, String)] = [
        ("text-view-length-512", long(512), 2950, "c3387485840ced4f8df65d3709d092d69aef3ab2489ff07b622e6a6487f57e9c"),
        ("text-view-length-513", long(513), 3489, "9545bb486f0e2e8a557595de57503f4b0c252f2bd11b1fb6e049b1812ff0a2d5"),
        ("text-view", xib(), 2448, "36a8f6f1673ea7c7dfcd3df024c857a1b316f661ec8ddf6b07b19298729b76d7"),
        ("text-view-text-attribute", xib(attributes + #" text="Lorem ipsum""#, background + font + traits), 2448,
         "36a8f6f1673ea7c7dfcd3df024c857a1b316f661ec8ddf6b07b19298729b76d7"),
        ("text-view-white", xib(attributes, XIBCompilerTests.gray("1", "1") + "\n" + text + font + traits), 2448,
         "36a8f6f1673ea7c7dfcd3df024c857a1b316f661ec8ddf6b07b19298729b76d7"),
        ("text-view-no-text", xib(attributes, background + font + traits), 2217, "dfd69ae4050b78fc2412e86eea2d7cea8a3af1a9091b84a16a93bffb157c4890"),
        ("text-view-text-color", xib(attributes, background + text + XIBCompilerTests.gray("0.5", "1").replacingOccurrences(of: "backgroundColor", with: "textColor")
                                     + "\n" + font + traits), 2506, "5c3e4f07fc8d53b1a8d57a4c8defc55432d98de63efc933673d71c22822c397e"),
        ("text-view-center", xib(attributes.replacingOccurrences(of: #""natural""#, with: #""center""#)), 2448,
         "8f346940c54e4d449fff5d9456e3d3228473c44839b325a49bfa969f27b96975"),
        ("text-view-no-alignment", xib(attributes.replacingOccurrences(of: #" textAlignment="natural""#, with: "")), 2433,
         "e8c0394130bc435afcdf3d417097c29372249096977563a13182d1028d37571e"),
        ("text-view-no-font", xib(attributes, background + text + traits), 2448, "41a72346908842ed41e1bfa9d9677d778d4bc68fd66a08e44b182765785497c4"),
        ("text-view-custom-class", xib(attributes + #" customClass="Notes" customModule="T" customModuleProvider="target""#), 2530,
         "64f6a3a24e2431724c5facbe3f0e2847dff759b6b2d92b86572f3871e9c7f3b0"),
        ("text-view-static", xib(attributes.replacingOccurrences(of: " textAlignment", with: #" scrollEnabled="NO" editable="NO" textAlignment"#)), 2462,
         "f6142d2505574bd4153427f9d2fd69725f3c6ac1699e5bea4b80624659fa1f2b"),
        ("text-view-all-flags", xib(attributes + #" editable="NO" selectable="NO""#, background + text + font + #"<textInputTraits key="textInputTraits"/>"# + "\n"
                                    + #"<dataDetectorType key="dataDetectorTypes" phoneNumber="YES" link="YES" address="YES"/>"# + "\n"), 2527,
         "44e1632db5256bf3f4cb3c531195b3507d86b3dcd0998033f4a6e5337ea13b3f"),
        ("text-view-traits-all", xib(attributes, traits(#"autocapitalizationType="words" autocorrectionType="no" spellCheckingType="no" keyboardType="URL" "#
                                                        + #"keyboardAppearance="alert" returnKeyType="done" enablesReturnKeyAutomatically="YES" smartDashesType="no" "#
                                                        + #"smartInsertDeleteType="no" smartQuotesType="no" textContentType="url""#)), 2735,
         "9903edc900b3a2aba26d620a6591dadfc986d5f6e60bcc0b76b208fdebdd9f60"),
        ("text-view-traits-smart", xib(attributes, traits(#"autocorrectionType="no" spellCheckingType="no" smartDashesType="no" smartInsertDeleteType="no" "#
                                                          + #"smartQuotesType="no""#)), 2605, "3c74ebd189bfcde35a2fc3c7dfbc3e19eb43cd18eef149e6499e71878af92db2"),
        ("text-view-traits-yes", xib(attributes, traits(#"autocapitalizationType="sentences" autocorrectionType="yes" spellCheckingType="yes""#)), 2495,
         "860c780bd40916cfda9027d3f44259c2103be79a89e946287a5b08c0188443f2"),
    ]

    /// The scroll view's keys, the text plain and attributed with its color, font and alignment,
    /// what differs from IB's, UIKit's highlight attributes; no clipping without scrolling, a white
    /// background named `systemBackgroundColor`.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }

    /// `text-view-lproj`: the plain text localizable, the attributed one not.
    @Test func localizesThePlainText() throws {
        let nib = try XIBCompiler.compile(Data(Self.xib().utf8), path: "/tmp/text-view-lproj/Base.lproj/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == 2532)
        #expect(VariationTests.digest(nib) == "f89d211668a0ff0cf942acb2e62507ca1c1b90f3368dbd1671e4418d383c2841")
    }
}
