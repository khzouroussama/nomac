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

    static let fitting = attributes.replacingOccurrences(of: #" adjustsFontSizeToFit="NO""#, with: "")
    static let body = font(["style": "UICTFontTextStyleBody"])
    static let white = #"<color key="shadowColor" white="1" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>"# + "\n"

    static func shadowed(_ width: String, _ height: String) -> String {
        "<size key=\"shadowOffset\" width=\"\(width)\" height=\"\(height)\"/>\n"
    }

    static let shadowAndMinimumCases: [(String, String, Int, String)] = [
        ("label-shadow-0-1", labelled(label(extra: shadowed("0.0", "1"))), 1809, "d427d4b0218cdd20582d7ed845231d72b3fc8dd05d2f2b8ce9daa508b39c70e0"),
        ("label-shadow-0-0", labelled(label(extra: shadowed("0.0", "0.0"))), 1774, "9577b4025c2b6436c943d11ac2e4c8b69c60497eaa1da2fcfa5b7c26603c8dfe"),
        ("label-shadow-minus-1", labelled(label(extra: shadowed("-1", "-1"))), 1809, "bee371ac12e5970f120d39bd0744bdd4ef4991b46a627f9cc65c4f74b46e8487"),
        ("label-shadow-fraction", labelled(label(extra: shadowed("1.5", "2.5"))), 1809, "f320771f01fd1c14a5563a2c1c3f4a59a97010656e545e054c37f32ec8e76797"),
        ("label-shadow-color", labelled(label(extra: white)), 1876, "e19bd8a1359f2c8c1be99d4c22f70d514f9e570de1c87b49209d3f4dce270f19"),
        ("label-shadow-color-offset", labelled(label(extra: white + shadowed("0.0", "1"))), 1876, "3cd41cc5acf1f84040a338742560e1766f8e2260779cee7b05746b244797c03b"),
        ("label-min-20-no", labelled(label(attributes + #" minimumFontSize="20""#)), 1809, "d2955d7ebc8908ecefb8c536ab9721e43dab7096a4535b63a3e36cf7797de49d"),
        ("label-scale-half-no", labelled(label(attributes + #" minimumScaleFactor="0.5""#)), 1809, "d2955d7ebc8908ecefb8c536ab9721e43dab7096a4535b63a3e36cf7797de49d"),
        ("label-min-20-no-style", labelled(label(attributes + #" minimumFontSize="20""#, font: body)), 1587, "300fb535ab122631df5f50d517180a619ac1ba34eed88ddf37010306620e7180"),
        ("label-min-20-absent", labelled(label(fitting + #" minimumFontSize="20""#)), 1885, "95047ecd2917b65bfa300436fbaba4699f1bca3b3a4ecf2e91c60dc7d38b159e"),
        ("label-min-17-yes", labelled(label(fitting + #" minimumFontSize="17""#)), 1885, "f914686953c3b6be3f5f683b49951963d30c7bded68a57f79c7902d7291e01d8"),
        ("label-min-and-scale-yes", labelled(label(fitting + #" minimumFontSize="10" minimumScaleFactor="0.5""#)), 1885, "1ad36ee7b717e50bfd1b5eb88ef1d1e97cae780cdc629cdc75101829ae49d01c"),
        ("label-scale-over-one", labelled(label(fitting + #" minimumScaleFactor="1.5""#)), 1885, "9cdc37f341dc77c56840ea247e362efa14a67994218ecfe9d4bff33a6a6ab450"),
    ]

    /// A shadow's color and offset, left out at 0, 0; without fitting neither a minimum font size nor
    /// a scale factor is written; with both, the factor makes the minimum.
    @Test(arguments: shadowAndMinimumCases)
    func compilesShadowsAndMinimumsAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/\(name)/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }

    /// A minimum over the font's size warns, by the labels' ids in a Foundation table's order
    /// (`label-min-20-two`); a text style's default size counts (`label-min-20-yes-style`).
    @Test func warnsOfMinimumsOverTheFontSize() throws {
        let over = Self.fitting + #" minimumFontSize="20""#
        let xib = Self.labelled(Self.label(over) + Self.label(over, id: "zzz-zz-zz2", y: 80) + Self.label(Self.fitting + #" minimumFontSize="30""#, id: "mmm-mm-mm3", y: 120))
        let compiled = try XIBCompiler.compileReportingWarnings(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(compiled.nib.count == 2187)
        #expect(VariationTests.digest(compiled.nib) == "6fda3d3a3557e56f6e2672da8cadb98adfbbcb02275320c02c1bd4e831dfceb5")
        #expect(compiled.warnings == ["lll-ll-ll1", "mmm-mm-mm3", "zzz-zz-zz2"].map { "/tmp/View.xib:\($0): warning: Minimum Font Size greater than current font size [9]" })
        let style = Self.labelled(Self.label(over, font: Self.body))
        let styled = try XIBCompiler.compileReportingWarnings(Data(style.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(VariationTests.digest(styled.nib) == "8894479c16f1f5a8d08319cb3f3040d65780b7684c5c2e65271897046931bee1")
        #expect(styled.warnings.count == 1)
    }

    /// A scale factor with a text style ibtool does not know, whose size is not known.
    @Test(arguments: [
        (labelled(label(fitting + #" minimumScaleFactor="0.5""#, font: font(["style": "UICTFontTextStyleMadeUp"]))), "this minimum font size of a label"),
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
