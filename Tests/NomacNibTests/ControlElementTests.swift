import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for map views, vibrancy, legacy cells' colors, buttons' title shadows
/// and custom bars in xibs (`.github/scripts/nib_experiments.py` rounds 123 to 130): sizes and SHA-256
/// digests of Xcode's nibs.
@Suite struct ControlElementTests {
    static func constrained(_ subviews: String) -> String { ConstraintTests.constrained(subviews, "") }

    static func map(type: String = "standard", extra: String = "", children: String = "") -> String {
        ConstraintTests.subview("mmm-mm-mm1", (10, 20, 200, 100), tag: "mapView", attributes: " clipsSubviews=\"YES\" multipleTouchEnabled=\"YES\" mapType=\"\(type)\"\(extra)")
            .replacingOccurrences(of: "</mapView>", with: children + "</mapView>")
    }

    static func vibrancy(blur: String, style: String?) -> String {
        "<visualEffectView contentMode=\"scaleToFill\" translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"vev-aa-aa1\">\n"
            + #"<rect key="frame" x="20" y="40" width="200" height="100"/>"# + "\n"
            + "<view key=\"contentView\" opaque=\"NO\" clipsSubviews=\"YES\" multipleTouchEnabled=\"YES\" contentMode=\"center\" id=\"vec-aa-aa1\">\n"
            + #"<rect key="frame" x="0.0" y="0.0" width="200" height="100"/>"# + "\n" + #"<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>"# + "\n</view>\n"
            + "<vibrancyEffect\(style.map { " style=\"\($0)\"" } ?? "")>\n<blurEffect style=\"\(blur)\"/>\n</vibrancyEffect>\n</visualEffectView>\n"
    }

    static func legacyCell(_ contentChildren: String) -> String {
        XIBCompilerTests.xib("""
            <collectionViewCell opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" id="ccc-cc-cc1">
            <rect key="frame" x="0.0" y="0.0" width="50" height="50"/>
            <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
            <view key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center">
            <rect key="frame" x="0.0" y="0.0" width="50" height="50"/>
            <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
            \(contentChildren)
            </view>
            <point key="canvasLocation" x="0" y="0"/>
            </collectionViewCell>

            """)
    }

    static let cases: [(String, String, Int, String)] = [
        ("map-plain", constrained(map()), 1572, "3f69f227be6de3fdd56709931e1fe0519d1062647a19b6d9749f8041468f1d68"),
        ("map-flyover", constrained(map(type: "satelliteFlyover")), 1528, "8bbd10b7c4df15e67b42b5188a268da7a4db139ef956f416687020f8f1d5ce38"),
        ("map-muted", constrained(map(type: "mutedStandard")), 1572, "fbed93b4ecc9d6375399264ac29582c680859f98281f3ebcafaf851689d9c8e2"),
        ("map-traffic-hybrid", constrained(map(type: "hybrid", extra: #" showsTraffic="YES""#)), 1527, "fe6d86eb399e94ae1d0e43dad649819ccabfdc839c23a99d315562c3b4de1de6"),
        ("map-traffic-satellite", constrained(map(type: "satellite", extra: #" showsTraffic="YES""#)), 1528, "0f8b341491978486d450cf0652bf739b6b594117b7b012f3defb9ff999028468"),
        ("map-all-off", constrained(map(extra: #" pitchEnabled="NO" showsBuildings="NO" zoomEnabled="NO" rotateEnabled="NO" scrollEnabled="NO" showsCompass="NO" showsPointsOfInterest="NO" showsScale="YES" showsTraffic="YES" showsUserLocation="YES""#)), 1572, "2d3e0bd210bc062dcdbc44dae5e57e7f69a4e52bc6107636b94c051ff5332850"),
        ("map-configuration-realistic", constrained(map(children: #"<standardMapConfiguration key="preferredConfiguration" elevationStyle="realistic" showsTraffic="YES"/>"# + "\n")), 1572, "c4ce0ade7654f146b676e9d47ccb19bd4e7434c8d2431b51caea2e8fdeee894f"),
        ("vibrancy-grid-regular-none", constrained(vibrancy(blur: "regular", style: nil)), 1443, "2480d84d955184e82421cb1e8968573a896c819445f9bc53c91d77b527867d3e"),
        ("vibrancy-grid-systemMaterial-label", constrained(vibrancy(blur: "systemMaterial", style: "label")), 1503, "52e0699bc6c70531302ea873f95b8933b77bae582466665062e3ef45fc597d92"),
        ("vibrancy-grid-systemMaterialDark-label", constrained(vibrancy(blur: "systemMaterialDark", style: "label")), 1465, "d100dfed255ed1b900d613c7d3354205c47a12f950887891a94687d7a42ab71e"),
        ("vibrancy-grid-systemChromeMaterial-fill", constrained(vibrancy(blur: "systemChromeMaterial", style: "fill")), 1513, "a52548577a003126401e43d53ef9662ffcec7bc2f312d4413734b3aa7a2eda6d"),
        ("cvcell-old-content-color-clear", legacyCell(#"<color key="backgroundColor" white="0.0" alpha="0.0" colorSpace="calibratedWhite"/>"#), 1463, "bc109e56f06cd05d8d3d1d61ac9b428b4bb620d7c5318378ace811348023bee7"),
        ("button-shadow-after-image", ButtonTests.buttonXIB(ButtonTests.attributes, #"<size key="titleShadowOffset" width="1" height="2"/>"# + "\n" + #"<inset key="imageEdgeInsets" minX="1" minY="2" maxX="3" maxY="4"/>"# + "\n" + ButtonTests.title), 1747, "b87b6763fde0ecc429928bb3347eaeb0b555bfcba1471a59f15511678f0d50a7"),
        ("custom-toolbar", constrained(ConstraintTests.subview("cst-aa-aa1", (10, 20, 300, 44), tag: "toolbar", attributes: #" opaque="NO" clearsContextBeforeDrawing="NO" customClass="Custom" customModule="T" customModuleProvider="target""#)), 1099, "2451d7cb196f4343dc8b21552f6f46590d53f053d3cda878c010374741e6c0d3"),
        ("custom-navigation-bar", constrained(ConstraintTests.subview("cst-aa-aa1", (10, 20, 300, 44), tag: "navigationBar", attributes: #" opaque="NO" customClass="Custom" customModule="T" customModuleProvider="target""#)), 1152, "d321d2c79d1eebca7c999c0d6c8a96cdfc85bc1b593692770f91651af271311c"),
    ]

    @Test(arguments: cases)
    func compilesAsXcode(name: String, document: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(document.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }

    /// ibtool warns about a font that adjusts without a text style, on labels, text fields and text
    /// views, and not about a text style's (`warn-adjusts-*`).
    @Test func warnsAboutFontsThatDoNotAdjust() throws {
        let label = { (font: String) in
            "<label opaque=\"NO\" userInteractionEnabled=\"NO\" contentMode=\"left\" text=\"Hi\" adjustsFontForContentSizeCategory=\"YES\" translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"lll-ll-ll1\">\n"
                + #"<rect key="frame" x="10" y="20" width="42" height="21"/>"# + "\n" + font + "\n" + #"<nil key="textColor"/>"# + "\n" + #"<nil key="highlightedColor"/>"# + "\n</label>\n"
        }
        let path = "/tmp/View.xib"
        let plain = try XIBCompiler.compileReportingWarnings(Data(Self.constrained(label(#"<fontDescription key="fontDescription" type="system" pointSize="17"/>"#)).utf8), path: path,
                                                             options: XIBCompilerTests.options)
        #expect(plain.warnings == ["/tmp/View.xib:lll-ll-ll1: warning: Automatically Adjusts Font requires using a Dynamic Type text style [9]"])
        let styled = try XIBCompiler.compileReportingWarnings(Data(Self.constrained(label(#"<fontDescription key="fontDescription" style="UICTFontTextStyleBody"/>"#)).utf8), path: path,
                                                              options: XIBCompilerTests.options)
        #expect(styled.warnings.isEmpty)
    }
}
