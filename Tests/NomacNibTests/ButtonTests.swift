import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for buttons in xibs (`.github/scripts/nib_experiments.py` round
/// 32, `button`): sizes and SHA-256 digests of Xcode's nibs.
@Suite struct ButtonTests {
    static let attributes = #"opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" buttonType="system" lineBreakMode="middleTruncation""#
    static let title = #"<state key="normal" title="Button"/>"# + "\n"
    static let symbol = #"<image name="plus" catalog="system" width="128" height="113"/>"# + "\n"
    static let logo = ConstraintTests.logo

    static func buttonXIB(_ attributes: String = attributes, _ children: String = title, resources: String = "") -> String {
        let button = "<button \(attributes) translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"bbb-bb-bb1\">\n"
            + "<rect key=\"frame\" x=\"20\" y=\"40\" width=\"75\" height=\"35\"/>\n\(children)</button>\n"
        return ConstraintTests.constrained(button, "", resources: resources)
    }

    static func color(_ key: String, _ white: String) -> String {
        XIBCompilerTests.gray(white, "1").replacingOccurrences(of: "backgroundColor", with: key) + "\n"
    }

    static let cases: [(String, String, Int, String)] = [
        ("button", buttonXIB(), 1653, "96452c4e722a607260a29761c68ba22205c3702afed0d270581c25e283df4284"),
        ("button-font-bold", buttonXIB(attributes, #"<fontDescription key="fontDescription" pointSize="17" type="boldSystem"/>"# + "\n" + title),
         1709, "e38dd6bff28ee02b0e55d0fd16f47ee348cf2c669c2ec08aa990e67851523b7e"),
        ("button-title-colors", buttonXIB(attributes, "<state key=\"normal\" title=\"Button\">\n" + color("titleColor", "1") + color("titleShadowColor", "0.5")
                                          + "</state>\n"), 1867, "a5655eb47ec6af4cc79fe533498c22f7b4af2d9bdbed36dacb1a633c1849a644"),
        ("button-states-all", buttonXIB(attributes, ["normal": "Button", "highlighted": "H", "selected": "S", "disabled": "D"]
            .sorted { $0.key > $1.key }.map { "<state key=\"\($0.key)\" title=\"\($0.value)\"/>\n" }.joined()),
         1755, "17c3b2c5eea63afc1e1fc14b4a72931f0c0c988694b6821910be78871ca4007f"),
        ("button-state-content", buttonXIB(attributes, "<state key=\"normal\" title=\"Button\" image=\"Logo\" backgroundImage=\"Logo\">\n"
                                           + color("titleColor", "1") + color("titleShadowColor", "0.5") + "</state>\n", resources: logo),
         2084, "86ba6e71e5cd1098b5682d83666257f59a2e06f8a7c7407916e5d241e7938097"),
        ("button-image-symbol", buttonXIB(attributes, #"<state key="normal" image="plus" catalog="system"/>"# + "\n", resources: symbol),
         1824, "490e19d4aa5dc79fda81af4689891027a95402ed9e26c272f1f206f67ff8abc4"),
        ("button-control-flags", buttonXIB(attributes.replacingOccurrences(of: #"contentHorizontalAlignment="center""#, with: #"contentHorizontalAlignment="leading""#)
            .replacingOccurrences(of: #"contentVerticalAlignment="center""#, with: #"contentVerticalAlignment="top""#)
            + #" enabled="NO" selected="YES" highlighted="YES" pointerInteraction="YES" hidden="YES" tag="3""#,
            title + XIBCompilerTests.gray("0.5", "1") + "\n"
            + #"<color key="tintColor" red="0.2" green="0.4" blue="0.6" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>"# + "\n"),
         2136, "0f5beba347b816e931d2fa9013c1b68abafa51ef9bc653a2b54868e371ca1f83"),
        ("button-button-flags", buttonXIB(attributes.replacingOccurrences(of: "middleTruncation", with: "wordWrap")
            + #" showsTouchWhenHighlighted="YES" reversesTitleShadowWhenHighlighted="YES" adjustsImageWhenHighlighted="NO""#
            + #" adjustsImageWhenDisabled="NO" adjustsImageSizeForAccessibilityContentSizeCategory="YES" role="primary""#
            + #" springLoaded="YES" changesSelectionAsPrimaryAction="YES""#,
            #"<fontDescription key="fontDescription" pointSize="15" type="system"/>"# + "\n"
            + #"<inset key="contentEdgeInsets" minX="1" minY="2" maxX="3" maxY="4"/>"# + "\n"
            + #"<inset key="titleEdgeInsets" minX="5" minY="6" maxX="7" maxY="8"/>"# + "\n"
            + #"<inset key="imageEdgeInsets" minX="9" minY="10" maxX="11" maxY="12"/>"# + "\n" + title),
         1975, "5855387cf09b9883860a88d7a573d5954bb2fdccc71b31baf2ff533d7d0c06e3"),
        ("button-type-custom", buttonXIB(attributes.replacingOccurrences(of: #" buttonType="system""#, with: "")),
         1637, "c78cf00fa4c308efd2f65ee5dceb2877da68009f42b5e1884610eef3b890b60e"),
        ("button-type-infoLight-untitled", buttonXIB(attributes.replacingOccurrences(of: "\"system\"", with: "\"infoLight\""), ""),
         1033, "026700ebb3ccff7930915315a45c7f926629e5df674dd0876b03d17dd4e0996a"),
        ("button-custom-class-module", buttonXIB(attributes + #" customClass="MyButton" customModule="T" customModuleProvider="target""#),
         1738, "4104d44790000c587cb2b713d50f657435b082b544c7ca05aed38bd546089b8d"),
    ]

    /// The control's and the button's keys after the view's: states' content in a mutable
    /// dictionary by state, IB's default fonts, insets top, left, bottom, right, SF Symbols of no
    /// size, and the image-only types without content or font.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }

    /// `button-type-infoLight` (ibtool drops the title with a warning), `button-configuration-*`.
    @Test(arguments: [
        (buttonXIB(attributes.replacingOccurrences(of: "\"system\"", with: "\"infoLight\"")), "a title on a button of type 3 (ibtool drops it with a warning)"),
    ])
    func refusesWhatIsNotObservedYet(xib: String, what: String) {
        #expect(throws: NomacError("nomac does not compile \(what) yet (BACKLOG B-260)", path: "/tmp/View.xib")) {
            try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        }
    }

    /// An info button's default hugging is 750, written only when it differs (`button-info-hugging-750`; cwa's HomeLinkCardView).
    @Test func infoButtonHugging() throws {
        let button = "<button opaque=\"NO\" contentMode=\"scaleToFill\" horizontalHuggingPriority=\"750\" verticalHuggingPriority=\"750\" "
            + "contentHorizontalAlignment=\"center\" contentVerticalAlignment=\"center\" buttonType=\"infoLight\" showsTouchWhenHighlighted=\"YES\" "
            + "lineBreakMode=\"middleTruncation\" id=\"bbb-bb-bb1\">\n<rect key=\"frame\" x=\"20\" y=\"40\" width=\"22\" height=\"22\"/>\n</button>\n"
        let nib = try XIBCompiler.compile(Data(ConstraintTests.constrained(button, "").utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == 1012)
        #expect(VariationTests.digest(nib) == "5fe0df89cdd90dab2aba7eb513198412aed2e8af6876ee0fa23312525709ce06")
    }
}

