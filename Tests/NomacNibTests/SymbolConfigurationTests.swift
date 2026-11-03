import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for symbol images' variable values, hierarchical rendering and
/// preferred configurations (`.github/scripts/nib_experiments.py` round 60, `symbol-*`): sizes and
/// SHA-256 digests of Xcode's nibs.
@Suite struct SymbolConfigurationTests {
    static let hierarchical = "<hierarchicalColors>\n" + #"<color systemColor="labelColor"/>"# + "\n" + #"<color systemColor="secondaryLabelColor"/>"# + "\n"
        + #"<color systemColor="tertiaryLabelColor"/>"# + "\n</hierarchicalColors>\n"
    static let resources = ButtonTests.symbol + ["labelColor", "secondaryLabelColor", "tertiaryLabelColor"].map {
        "<systemColor name=\"\($0)\">\n" + #"<color white="0.0" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>"# + "\n</systemColor>\n"
    }.joined()

    static func reference(_ attributes: String, colors: Bool = false) -> String {
        colors ? "<imageReference key=\"image\" image=\"plus\" catalog=\"system\"\(attributes)>\n\(hierarchical)</imageReference>\n"
            : "<imageReference key=\"image\" image=\"plus\" catalog=\"system\"\(attributes)/>\n"
    }

    static func preferred(_ attributes: String, _ children: String = "") -> String {
        children.isEmpty ? "<preferredSymbolConfiguration key=\"preferredSymbolConfiguration\"\(attributes)/>\n"
            : "<preferredSymbolConfiguration key=\"preferredSymbolConfiguration\"\(attributes)>\n\(children)</preferredSymbolConfiguration>\n"
    }

    static func view(_ children: String, attributes: String = "") -> String {
        ConstraintTests.constrained(ConstraintTests.subview("iii-ii-ii1", (112, 333, 168, 185), tag: "imageView", attributes: attributes)
            .replacingOccurrences(of: "</imageView>", with: children + "</imageView>"), "", resources: resources)
    }

    static func button(_ state: String) -> String {
        let attributes = #"opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" lineBreakMode="middleTruncation""#
        let element = "<button \(attributes) translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"bbb-bb-bb1\">\n"
            + #"<rect key="frame" x="20" y="40" width="23" height="23"/>"# + "\n<state key=\"normal\">\n\(state)</state>\n</button>\n"
        return ConstraintTests.constrained(element, "", resources: resources)
    }

    static let symbol = #" image="plus" catalog="system""#

    static let cases: [(String, String, Int, String)] = [
        ("symbol-view-variable-0", view(reference(#" symbolScale="large" variableValue="0.0""#) + preferred(#" scale="large""#)), 1208,
         "2147ce7ef6ed4462658f5e02c26ae6833bf3165a77cf011016eeade4594f551f"),
        ("symbol-view-variable-08", view(reference(#" variableValue="0.80000000000000004""#)), 1114, "eb1c8fe7d3b94b368922a1670e18f817598c40379bdb674e30dac5672a26112b"),
        ("symbol-view-hierarchical-scale", view(reference(#" symbolScale="large" renderingMode="hierarchical""#, colors: true)), 1814,
         "c7eec91afb731ee78ec04f20395d7d93d628d08b5c2f33dd704345110aaf965c"),
        ("symbol-view-font", view(preferred(#" configurationType="font""#, LabelTests.font(["style": "UICTFontTextStyleHeadline"]) + "\n"), attributes: symbol), 1217,
         "d87ad7840ef1161c2b9cc8e87671be112190dfc405f7095a5fc71e566f0b4c89"),
        ("symbol-view-scale-weight", view(preferred(#" scale="small" weight="regular""#), attributes: symbol), 1185,
         "6ff5a57c930ea645b306d865593f334e3fff841a5fc4be6dd45959734ac4ce51"),
        ("symbol-view-preferred-empty", view(preferred(""), attributes: symbol), 1083, "b1e0d695bcba7ba394b91def6f1a20429032e0edefb6ade2a1ac3b44e9a564dd"),
        ("symbol-view-point-size", view(preferred(#" configurationType="pointSize" pointSize="12""#), attributes: symbol), 1168,
         "f9753faa31f018de568849a9ee3c7f7f68e5b4bf60b204aab3e1a06d803bbb90"),
        ("symbol-button-hierarchical-light", button(reference(#" renderingMode="hierarchical" variableValue="1""#, colors: true) + preferred(#" weight="light""#)),
         2607, "ad1a84a5551c98a7e171c2fe5646fcebf9ffa8151713d853abb083e1b6aa0699"),
        ("symbol-button-scale", button(reference(#" symbolScale="large""#)), 1861, "d4a2ed09f3984671da37fa5eb7d245a0894205bcd9727b03bbcec05793aac765"),
    ]

    /// Variable values on the placeholder, hierarchical colors and scales in its symbol
    /// configuration; preferred configurations of scales, weights, point sizes and text styles, an
    /// empty one none; a button state's after its image.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
