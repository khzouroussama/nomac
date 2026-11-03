import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for text fields' clear buttons, alignments, colors and input
/// traits (`.github/scripts/nib_experiments.py` rounds 66 and 67, `tf-*`): sizes and SHA-256 digests
/// of Xcode's nibs.
@Suite struct TextFieldTests {
    static let attributes = #"opaque="NO" clipsSubviews="YES" contentMode="scaleToFill" contentHorizontalAlignment="left" contentVerticalAlignment="center" "#
        + #"placeholder="Name" textAlignment="natural" minimumFontSize="17""#

    static func field(_ extra: String = "", traits: String = "", children: String = "", attributes: String = attributes) -> String {
        let element = "<textField \(attributes)\(extra) translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"txf-aa-aaa\">\n"
            + #"<rect key="frame" x="16" y="100" width="359" height="44"/>"# + "\n" + LabelTests.font(["type": "system", "pointSize": "17"]) + "\n"
            + "<textInputTraits key=\"textInputTraits\"\(traits)/>\n\(children)</textField>\n"
        return ConstraintTests.constrained(element, "")
    }

    static let cases: [(String, String, Int, String)] = [
        ("tf-clear-whileEditing", field(#" clearButtonMode="whileEditing""#), 1848, "1ac64c646ea473483a10b0f42ff6c2f8a427c278b1c508408d978646ecbe37b4"),
        ("tf-clear-always", field(#" clearButtonMode="always""#), 1848, "fd872ef16c90d06ea31d0bc589778ddea41178cf5ffc2c99580029b2064145f1"),
        ("tf-traits-every", field(traits: #" autocapitalizationType="words" autocorrectionType="no" spellCheckingType="no" keyboardType="emailAddress" "#
                                          + #"returnKeyType="next" enablesReturnKeyAutomatically="YES" secureTextEntry="YES" smartDashesType="no" "#
                                          + #"smartInsertDeleteType="no" smartQuotesType="no" textContentType="username""#),
         2142, "fe346b5bd4abbabe901e533ca4c81c6552de90f4985f093360aab95fe141080c"),
        ("tf-secure", field(traits: #" secureTextEntry="YES""#), 1901, "9b2aa94db10b4f8d7023c905c4996472acac3cef6b5484a09143b631515fd834"),
        ("tf-autocap-sentences", field(traits: #" autocapitalizationType="sentences""#), 1855, "1091ac2dfbfc3b2a68abda1e4f36402f0ee2398d0001818fdaaa37943ce5afb7"),
        ("tf-adjusts-NO", field(#" adjustsFontSizeToFit="NO""#), 1802, "0d9a1f96c22cbfe0e1caef00d8487d4d1c24594ba57be1186e03d3717da646c5"),
        ("tf-clears-rounded-text", field(#" borderStyle="roundedRect" clearsOnBeginEditing="YES""#,
                                         attributes: attributes.replacingOccurrences(of: #"placeholder="Name""#, with: #"text="x" placeholder="Name""#)),
         1935, "66c797f0c1d9fc3c2abdcea83deaeef17288cf2975cc810df79fa9aaff3f2b24"),
        ("tf-border-line", field(#" borderStyle="line""#), 1844, "c4d647ab63227b1f14f58ccb7ae60cd50f7770912def58afb43fc838f6ae9b26"),
        ("tf-text-color", field(children: XIBCompilerTests.gray("0.5", "1").replacingOccurrences(of: "backgroundColor", with: "textColor") + "\n"), 1789,
         "7e11db5b40dc38b086a465d898c425f78716a2e795d2f7bc132018e119be9bee"),
        ("tf-placeholder-string", field(children: #"<string key="placeholder">Name</string>"# + "\n",
                                        attributes: attributes.replacingOccurrences(of: #" placeholder="Name""#, with: "")),
         1827, "2bc1fd0931b2539afaed6ab615abba80929c960c69415ec8bb4c1e1c0bcb859a"),
        ("tf-valign-bottom", field(attributes: attributes.replacingOccurrences(of: #"contentVerticalAlignment="center""#, with: #"contentVerticalAlignment="bottom""#)),
         1888, "aefaee854d72346c54838bc13fd5563439256d36d04935eaa07c272b0024a12c"),
        ("tf-return-done", field(traits: #" returnKeyType="done""#), 1846, "377e2aa647837ee6f8f4fc923f6a444b082a171366e10aedcb203a6a60c532b1"),
        ("tf-keyboard-URL", field(traits: #" keyboardType="URL""#), 1845, "fb61cd906fcb1f1c006a452ea9e2b476a29ba266752c19705855ae7c0a3dc43f"),
        ("tf-content-password", field(traits: #" textContentType="password""#), 1865, "ea9de830cba769639dacb986cfe79361423ac4e76a465ae7f76d4b7ab77905eb"),
        ("tf-align-center", field(attributes: attributes.replacingOccurrences(of: #"textAlignment="natural""#, with: #"textAlignment="center""#)), 1827,
         "ec273f6d700dc8517b9daed837f4ce5016d84cbd1a29add160ad9836e3affe17"),
        ("tf-halign-trailing", field(attributes: attributes.replacingOccurrences(of: #"contentHorizontalAlignment="left""#, with: #"contentHorizontalAlignment="trailing""#)),
         1827, "f041a15bdbcb709cb65ecd28733ef90181f903b847a610a3f7d40d994532a942"),
    ]

    /// Clear button modes, alignments, borders, colors, placeholders and the input traits in
    /// ibtool's order, secure entry with its forced autocorrection and inline prediction.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
