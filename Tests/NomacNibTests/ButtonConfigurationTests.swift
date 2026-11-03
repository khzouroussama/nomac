import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for button configurations in xibs (`.github/scripts/nib_experiments.py`
/// round 54, `bc`): sizes and SHA-256 digests of Xcode's nibs.
@Suite struct ButtonConfigurationTests {
    static func configuration(_ attributes: String = #"style="plain" title="Button""#, _ children: String = "") -> String {
        children.isEmpty ? "<buttonConfiguration key=\"configuration\" \(attributes)/>\n"
            : "<buttonConfiguration key=\"configuration\" \(attributes)>\n\(children)</buttonConfiguration>\n"
    }

    static func configured(_ configuration: String = configuration(), state: String = ButtonTests.title, resources: String = "") -> String {
        ButtonTests.buttonXIB(ButtonTests.attributes, state + configuration, resources: resources)
    }

    static func titleFont(_ attributes: [String: String]) -> String {
        LabelTests.font(attributes).replacingOccurrences(of: #"key="fontDescription""#, with: #"key="titleFontDescription""#) + "\n"
    }

    static func symbolScale(_ scale: String, preferred: String? = nil) -> String {
        "<imageReference key=\"image\" image=\"plus\" catalog=\"system\" symbolScale=\"\(scale)\"/>\n"
            + (preferred.map { "<preferredSymbolConfiguration key=\"preferredSymbolConfigurationForImage\" \($0)/>\n" } ?? "")
    }

    static let red = "<systemColor name=\"systemRedColor\">\n" + #"<color red="1" green="0.23" blue="0.19" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>"#
        + "\n</systemColor>\n"
    static let two = configured().replacingOccurrences(of: "</button>\n", with: "</button>\n"
        + "<button \(ButtonTests.attributes) translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"bbb-bb-bb2\">\n"
        + #"<rect key="frame" x="20" y="100" width="75" height="35"/>"# + "\n" + ButtonTests.title + configuration(#"style="filled" title="Go""#) + "</button>\n")

    static let cases: [(String, String, Int, String)] = [
        ("bc-plain-title", configured(), 2949, "b7e36db1952c2537ecb14c1fd8abe94cc1f5aad486dca81ecdf0974157ff95be"),
        ("bc-no-state", configured(state: ""), 2949, "b7e36db1952c2537ecb14c1fd8abe94cc1f5aad486dca81ecdf0974157ff95be"),
        ("bc-font-on-button", configured(state: LabelTests.font(["type": "system", "pointSize": "12"]) + "\n" + ButtonTests.title), 2949,
         "b7e36db1952c2537ecb14c1fd8abe94cc1f5aad486dca81ecdf0974157ff95be"),
        ("bc-plain", configured(configuration(#"style="plain""#)), 2898, "4023063785eb56e52ec0b30efdb39435b7766768a9f48eb15d3725e5e4dd85e4"),
        ("bc-filled-title", configured(configuration(#"style="filled" title="Button""#)), 3046, "4636da93d1126e8c67e20c6a2da23aea550ff3b8588d2c0fe9540e6ef4113283"),
        ("bc-gray-title", configured(configuration(#"style="gray" title="Button""#)), 3131, "ee3168e941001d985be125dc76e6b4b8e309e8a4825bcb157530c6592c3ecb56"),
        ("bc-tinted-title", configured(configuration(#"style="tinted" title="Button""#)), 3076, "3744be05335505f9b384c315905624e15d94bffe0932496f2ef98911ffff89ef"),
        ("bc-image-symbol", configured(configuration(#"style="plain" image="plus" catalog="system""#), resources: ButtonTests.symbol), 3085,
         "ac352bb45388060b656d7dfa014b8886e0221a4843501d854211397df4845908"),
        ("bc-image-asset", configured(configuration(#"style="plain" image="Logo""#), resources: ButtonTests.logo), 3081,
         "3ca42fd8b058f56ee9d772b8e0b0c5b400d203bda42884d158bbea89bfe4a254"),
        ("bc-title-font", configured(configuration(#"style="plain" title="Button""#, titleFont(["type": "system", "pointSize": "12"]))), 3486,
         "4fa476e5ca67213a58dffbbdd5c07c6282548b696d82bfa6e442838cf431e7fe"),
        ("bc-title-font-style", configured(configuration(#"style="plain" title="Button""#, titleFont(["style": "UICTFontTextStyleHeadline"]))), 3282,
         "1b428e02736ad247b293d96ee7c9315c22e26db4eaaee030155bcb4b1060d83b"),
        ("bc-image-leading", configured(configuration(#"style="filled" image="plus" catalog="system" imagePlacement="leading" title="Button" imagePadding="8""#),
                                        resources: ButtonTests.symbol), 3233, "65918ca6141e9bd2c4411c46fbdc4d92fed537d1bc18d54c30ee7fe26eb8df8d"),
        ("bc-image-trailing", configured(configuration(#"style="plain" image="plus" catalog="system" imagePlacement="trailing" title="Button" imagePadding="5""#),
                                         resources: ButtonTests.symbol), 3136, "470cf9e4c67942367b678bfd4f93b713d36bc4e743c83dcaaae29b7600d598f5"),
        ("bc-base-foreground", configured(configuration(#"style="plain" title="Button""#, #"<color key="baseForegroundColor" systemColor="systemRedColor"/>"# + "\n"),
                                          resources: red), 3103, "e8f1d747b5a39c82fc7671407a4576ff8991c016dd230416388542007c72a5d8"),
        ("bc-two", two, 3360, "cf54adaab0f6614684613411b02ea5be283c0dbd7730772d277d5df4830dfb03"),
        ("bc-symbol-scale", configured(configuration(#"style="plain" title="Button""#, symbolScale("large", preferred: #"scale="large""#)), resources: ButtonTests.symbol),
         3199, "a94b7601c28b4ec2ff6304feb30b4179e21f12bd16f3c9e644b059ad9e7e1dd9"),
        ("bc-symbol-scale-default", configured(configuration(#"style="plain" title="Button""#, symbolScale("default", preferred: #"scale="default""#)),
                                               resources: ButtonTests.symbol), 3213, "6a4b951427116169b78c4f8ba1cc1dff3a89050882751da7d75079800d9d55b0"),
        ("bc-symbol-point-size", configured(configuration(#"style="plain" title="Button""#,
                                                          symbolScale("small", preferred: #"configurationType="pointSize" pointSize="8" scale="small""#)),
                                            resources: ButtonTests.symbol), 3217, "015bdfaf0c2347e01702b4d3d876ee50437f532ba3998fc86b4e0412b9bf7b7c"),
        ("bc-image-reference-only", configured(configuration(#"style="plain" title="Button""#, symbolScale("medium")), resources: ButtonTests.symbol), 3189,
         "8589992478283eb733819bc0db9aa816f242f8966d84f8291293cdc63c1e903f"),
    ]

    /// The configuration instead of the states' content and font: its style's background, its
    /// title with its font, its image and symbol configurations, placement, padding and colors.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
