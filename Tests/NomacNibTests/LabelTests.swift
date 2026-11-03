import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What `ibtool --compile` (Xcode 27.0) writes for labels and their fonts
/// (`.github/scripts/nib_experiments.py` round 18): sizes and SHA-256 digests of Xcode's nibs.
@Suite struct LabelTests {
    static let attributes = #"opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" text="Label" textAlignment="natural" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO""#
    static let nilColors = #"<nil key="textColor"/>"# + "\n" + #"<nil key="highlightedColor"/>"# + "\n"

    static func font(_ attributes: [String: String]) -> String {
        #"<fontDescription key="fontDescription" "# + attributes.sorted { $0.key < $1.key }.map { "\($0.key)=\"\($0.value)\"" }.joined(separator: " ") + "/>"
    }

    static func label(_ attributes: String = attributes, font: String = font(["type": "system", "pointSize": "17"]), colors: String = nilColors,
                      extra: String = "", id: String = "lll-ll-ll1", y: Int = 40) -> String {
        "<label \(attributes) id=\"\(id)\">\n<rect key=\"frame\" x=\"20\" y=\"\(y)\" width=\"42\" height=\"21\"/>\n\(font)\n\(colors)\(extra)</label>\n"
    }

    static func labelled(_ labels: String, constraints: String = "") -> String {
        ConstraintTests.constrained(labels, constraints)
    }

    static let cases: [(String, String, Int, String)] = [
        ("label-plain", labelled(label()), 1809, "d2955d7ebc8908ecefb8c536ab9721e43dab7096a4535b63a3e36cf7797de49d"),
        ("label-minimal", labelled(label(#"text="Label""#)), 1764, "7561ea5f1c811fddbb25843b0e749ce14fbce81041bedc7773af028ef8b7bf06"),
        ("label-all-options-2", labelled(label(attributes.replacingOccurrences(of: "alignBaselines", with: "none")
            .replacingOccurrences(of: #"adjustsFontSizeToFit="NO""#, with: #"adjustsFontSizeToFit="YES" minimumScaleFactor="0.25""#)
            + #" numberOfLines="0" verticalCompressionResistancePriority="749" insetsLayoutMarginsFromSafeArea="NO" enabled="NO" preferredMaxLayoutWidth="120""#)),
         2078, "4bbf5604faf5492037bc2197474054b829819db6eb07a83509905daa8803d5b7"),
        ("label-minimum-font-size", labelled(label(attributes.replacingOccurrences(of: #"adjustsFontSizeToFit="NO""#, with: #"minimumFontSize="10""#))),
         1885, "b558ecff11cba9514fd69a564a27827b78d47d9ff5bda47578cfc656aa013000"),
        ("label-no-colors", labelled(label(colors: "")), 1881, "8a1568f3ca47b8f0f8c0217cf97930531013986a8bcefcf77644c5becb71545c"),
        ("label-two", labelled(label() + label(id: "lll-ll-ll2", y: 80)), 1946, "be3ecb609dc7974598b974031093817f320528c9884b988af9c10e4ae0361401"),
        ("label-two-sizes", labelled(label() + label(font: font(["type": "system", "pointSize": "14"]), id: "lll-ll-ll2", y: 80)),
         2075, "af16e88f138d529eb2a0bf1da5352fb2584d6aca85f3095048911bff2743df24"),
        ("label-text-child", labelled(label(attributes.replacingOccurrences(of: #"text="Label" "#, with: ""), extra: "<string key=\"text\">Two\nlines</string>\n")),
         1813, "bea1ede63e56aad59bc845ede48d1a86dbcb3612bcec5859e4d7315c905ba2d6"),
        ("label-no-text", labelled(label(attributes.replacingOccurrences(of: #"text="Label" "#, with: ""))),
         1794, "5b51e2ea3a55e80c17e9b86a35a9f0dbc2369c48bbb5207cdc22bf46022c080a"),
        ("label-middle", labelled(label(attributes.replacingOccurrences(of: "tailTruncation", with: "middleTruncation"))),
         1828, "2f3c84e97e7022d93cf54e8639375d830b5150f4e1b252e3a6c79acf95dd5699"),
        ("label-size-bold-17", labelled(label(font: font(["type": "boldSystem", "pointSize": "17"]))),
         1887, "33a438fc4ef553814aae68e3c7a78edd5ecbeeed03716f4bfaea74a144dd40ae"),
        ("label-weight-thin", labelled(label(font: font(["type": "system", "weight": "thin", "pointSize": "17"]))),
         1803, "9884ae149690b762513c62690862c8e904fc2ae5cc0863d8de717bd631c3b0c5"),
        ("label-style-Headline-adjusts", labelled(label(attributes + #" adjustsFontForContentSizeCategory="YES""#, font: font(["style": "UICTFontTextStyleHeadline"]))),
         1630, "7f758087217bcd29007a8200482df26e1781b3e03689d91bea8a729d368313fd"),
        ("label-style-subheadline", labelled(label(font: font(["style": "UICTFontTextStyleSubheadline"]))),
         1614, "b3c2df9d4a76fcd8077726fa22c59b1a194556eb11d2164c330b7fb42cc2a150"),
        ("label-style-made-up", labelled(label(font: font(["style": "UICTFontTextStyleMadeUp"]))),
         1614, "b3c2df9d4a76fcd8077726fa22c59b1a194556eb11d2164c330b7fb42cc2a150"),
        ("label-font-italic", labelled(label(font: font(["type": "italicSystem", "pointSize": "16"]))),
         1916, "e542df5412e4c9a694ce392569e55d0e904e4223992ae483a8cf4f1674cb0074"),
        ("label-font-courier-bold", labelled(label(font: font(["family": "Courier", "name": "Courier-Bold", "pointSize": "17"]))),
         1663, "4cacc6145a8ccd1e67789d510ada51306f7fb6180842d62c2fdb431ea585b558"),
        ("label-font-futura", labelled(label(font: font(["family": "Futura", "name": "Futura-Medium", "pointSize": "74"]))),
         1780, "320ea479d0bd6e312bf697d3c3e8660e93ab81dab10b7f85fdb019e950f41ad1"),
        ("label-text-rgb", labelled(label(colors: #"<color key="textColor" red="0.2" green="0.4" blue="0.6" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>"#
            + "\n" + #"<nil key="highlightedColor"/>"# + "\n")), 1874, "7480854bd283c37e63de25d5a37576bcfe90a5119b6ae5b4dcf5f2cd2daab26f"),
        ("label-constrained", labelled(label(), constraints: ConstraintTests.constraint(0, "lll-ll-ll1", "centerX", ConstraintTests.root, "centerX")
            + ConstraintTests.constraint(1, "lll-ll-ll1", "centerY", ConstraintTests.root, "centerY")),
         2125, "d524099ba1dc6777031e9bee036dd6aae143604536be25b9cbb3809121502fea"),
    ]

    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/\(name)/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(SHA256.digest(Array(nib)).map { String(format: "%02x", $0) }.joined() == digest, "\(name)")
    }

    /// A document in an `.lproj` folder writes its texts as `NSLocalizableString`s, keyed by the
    /// label's id (`label-lproj`); elsewhere they are strings (`label-plain`).
    @Test func localizesTextsInLprojFolders() throws {
        let nib = try XIBCompiler.compile(Data(Self.labelled(Self.label()).utf8), path: "/tmp/label-lproj/Base.lproj/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == 1887)
        #expect(SHA256.digest(Array(nib)).map { String(format: "%02x", $0) }.joined() == "b2f981440154b90b3570e26f7c10e0fff0bf27cf1b19f0f76a65707566e74b49")
    }

    /// An empty text is not localized (`label-empty-lproj`).
    @Test func emptyTextInLprojFolder() throws {
        let label = Self.label(Self.attributes.replacingOccurrences(of: "text=\"Label\"", with: "text=\"\""))
        let nib = try XIBCompiler.compile(Data(Self.labelled(label).utf8), path: "/tmp/label-lproj/Base.lproj/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == 1804)
        #expect(SHA256.digest(Array(nib)).map { String(format: "%02x", $0) }.joined() == "c498f35fdf479843f5683a972409cb7521f261c7bbb0dd8b8b7f46f4c6a1f081")
    }

    /// A minimum font size with `adjustsFontSizeToFit="NO"`, and a minimum font size, not a scale
    /// factor, with a text style.
    @Test(arguments: [
        (labelled(label(attributes + #" minimumScaleFactor="0.5""#)), "this minimum font size of a label"),
        (labelled(label(attributes.replacingOccurrences(of: #"adjustsFontSizeToFit="NO""#, with: #"minimumFontSize="9""#),
                        font: font(["style": "UICTFontTextStyleBody"]))), "this minimum font size of a label"),
    ])
    func refusesWhatIsNotObservedYet(xib: String, what: String) {
        do {
            _ = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
            Issue.record("compiled \(what)")
        } catch let error as NomacError {
            #expect(error.message == "nomac does not compile \(what) yet (BACKLOG B-260)")
        } catch {
            Issue.record(error)
        }
    }
}
