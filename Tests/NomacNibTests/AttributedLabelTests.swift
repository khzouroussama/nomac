import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for attributed labels in xibs (`.github/scripts/nib_experiments.py`
/// round 55, `al`): sizes and SHA-256 digests of Xcode's nibs.
@Suite struct AttributedLabelTests {
    static let attributes = LabelTests.attributes.replacingOccurrences(of: #"text="Label" textAlignment="natural""#, with: #"usesAttributedText="YES""#)
    static let system15 = #"<font key="NSFont" metaFont="system" size="15"/>"#
    static let paragraph15 = #"<paragraphStyle key="NSParagraphStyle" alignment="left" lineBreakMode="wordWrapping" baseWritingDirection="natural" "#
        + #"lineHeightMultiple="1.2" tighteningFactorForTruncation="0.0"/>"#
    static let textColor = #"<color key="NSColor" name="textColor" catalog="System" colorSpace="catalog"/>"#
    static let gomap = [#"<color key="NSColor" red="1" green="0.8057073951" blue="0.0" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>"#,
                        #"<font key="NSFont" size="36" name="HelveticaNeue-BoldItalic"/>"#, #"<font key="NSOriginalFont" size="36" name="HelveticaNeue-BoldItalic"/>"#,
                        #"<paragraphStyle key="NSParagraphStyle" alignment="center" lineBreakMode="truncatingTail" baseWritingDirection="natural"/>"#]

    static func xib(_ content: String? = "Hello", _ fragment: [String] = [], attributes: String = attributes) -> String {
        let text = content.map { "<attributedString key=\"attributedText\">\n<fragment content=\"\($0)\">\n<attributes>\n" + fragment.map { $0 + "\n" }.joined()
            + "</attributes>\n</fragment>\n</attributedString>\n" } ?? "<attributedString key=\"attributedText\"/>\n"
        return LabelTests.labelled(LabelTests.label(attributes, font: "", colors: #"<nil key="highlightedColor"/>"# + "\n", extra: text))
    }

    static let cases: [(String, String, Int, String)] = [
        ("al-empty", xib(nil), 1890, "3856041f8bdfdda7724f084df152c12921f406b0518d822d476c4e1fec749299"),
        ("al-system-15", xib("Hello", [system15, paragraph15]), 2107, "b536857708e99bc8155933df4d6779dae5d3fd417c9610f9c46a5f68746cf75c"),
        ("al-system-15-text-color", xib("Hello", [textColor, system15, paragraph15]), 2119, "e976ee4c13039de8b4bb21ef58c8d5eb3a14c3673c149b86ef344893d32d95cf"),
        ("al-font-only", xib("Hello", [#"<font key="NSFont" metaFont="system" size="17"/>"#]), 1955, "b63b7b0c8ca6f9fe36e64093e1865f1a312d4bdf0384a719cb838d8d1085efce"),
        ("al-paragraph-plain", xib("Hello", [system15, #"<paragraphStyle key="NSParagraphStyle" alignment="left" lineBreakMode="wordWrapping" "#
                                                       + #"baseWritingDirection="natural" tighteningFactorForTruncation="0.0"/>"#]),
         2076, "6cbe1d66c69fc2d14fa3fb62f979c009b944fc26d47159872ebf6fa367214046"),
        ("al-gomap", xib("Go Map!!", gomap), 2120, "31078463685f88cb5c734e083d1c220c5602fc5487a2a1465643dafa57ac6e18"),
        ("al-named-font", xib("Hello", [#"<font key="NSFont" size="17" name="CourierNewPSMT"/>"#]), 1927, "0c0ecd17356d8b12fcd0caf54a79a8c382db3ec41267da512b7eff63b601d104"),
        ("al-gray-color", xib("Hello", [#"<color key="NSColor" white="0.33333333333333331" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>"#,
                                        system15]), 1969, "e145ffbd05052d2c372a7cea8af49457dc3324d4e1e7a708a1dfec77e93a861d"),
        ("al-gomap-label", xib("Go Map!!", gomap, attributes: #"opaque="NO" clipsSubviews="YES" userInteractionEnabled="NO" contentMode="left" "#
                                + #"horizontalHuggingPriority="251" verticalHuggingPriority="251" usesAttributedText="YES" lineBreakMode="middleTruncation" "#
                                + #"baselineAdjustment="alignBaselines" minimumScaleFactor="0.5" translatesAutoresizingMaskIntoConstraints="NO""#),
         2233, "632faf3414b041ea9de96e8ac089532086d19253a3b5bb7211cb38ec5157652d"),
        ("al-pocket-label", xib("Description goes here ", [textColor, system15, paragraph15],
                                attributes: attributes.replacingOccurrences(of: #" baselineAdjustment"#, with: #" numberOfLines="0" baselineAdjustment"#)),
         2172, "b143f00d12277491a8f3cfc70ed5b2c3c0822501523f0a8a418316113cae51b2"),
    ]

    /// A plain label's keys from the fragment (its text, font, color and alignment), then the
    /// attributed text: a mutable string, the fragment's attributes, the paragraph style with the
    /// label's line break mode.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }

    /// `al-system-15-lproj`: attributed texts are not localized.
    @Test func doesNotLocalize() throws {
        let nib = try XIBCompiler.compile(Data(Self.xib("Hello", [Self.system15, Self.paragraph15]).utf8), path: "/tmp/al-lproj/Base.lproj/View.xib",
                                          options: XIBCompilerTests.options)
        #expect(nib.count == 2107)
        #expect(VariationTests.digest(nib) == "b536857708e99bc8155933df4d6779dae5d3fd417c9610f9c46a5f68746cf75c")
    }
}
