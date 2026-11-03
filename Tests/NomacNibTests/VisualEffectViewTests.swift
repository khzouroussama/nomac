import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for visual effect views in xibs (`.github/scripts/nib_experiments.py`
/// rounds 38 and 43, `effect_view`): sizes and SHA-256 digests of Xcode's nibs.
@Suite struct VisualEffectViewTests {
    static func effectXIB(_ style: String = "regular", attributes: String = #"contentMode="scaleToFill""#, content: String = "",
                          constraints: String = "", after: String = "") -> String {
        ConstraintTests.constrained("<visualEffectView \(attributes) translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"vev-aa-aa1\">\n"
                                    + #"<rect key="frame" x="20" y="40" width="200" height="100"/>"# + "\n"
                                    + "<view key=\"contentView\" opaque=\"NO\" clipsSubviews=\"YES\" multipleTouchEnabled=\"YES\" contentMode=\"center\" id=\"vec-aa-aa1\">\n"
                                    + #"<rect key="frame" x="0.0" y="0.0" width="200" height="100"/>"# + "\n"
                                    + #"<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>"# + "\n\(content)</view>\n"
                                    + "<blurEffect style=\"\(style)\"/>\n</visualEffectView>\n\(after)", constraints)
    }

    static let label = "<subviews>\n<label \(LabelTests.attributes) id=\"lll-ll-ll1\">\n" + #"<rect key="frame" x="10" y="10" width="42" height="21"/>"# + "\n"
        + LabelTests.font(["type": "system", "pointSize": "17"]) + "\n" + LabelTests.nilColors + "</label>\n</subviews>\n<constraints>\n"
        + ConstraintTests.constraint(10, "lll-ll-ll1", "top", "vec-aa-aa1", "top", #" constant="10""#)
        + ConstraintTests.constraint(11, "lll-ll-ll1", "leading", "vec-aa-aa1", "leading", #" constant="10""#) + "</constraints>\n"

    static let cases: [(String, String, Int, String)] = [
        ("effect", effectXIB(), 1257, "036149e8ef96116d15fc394bf3d18dcf8850b13f3b68e1cbc0609c06dc7169d4"),
        ("effect-label-constraints", effectXIB(content: label), 2657, "ff17f0732af0fdc9883d767b7dfb014f972ee05647c9dad54d07c751b0d5112e"),
        ("effect-label-constraints-sibling", effectXIB(content: label, after: "<view contentMode=\"scaleToFill\" translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"nsv-aa-aa1\">\n"
                                                       + #"<rect key="frame" x="20" y="300" width="200" height="100"/>"# + "\n<subviews>\n"
                                                       + ConstraintTests.subview("nsw-aa-aa1", (10, 10, 50, 50)) + "</subviews>\n</view>\n"),
         2841, "ca79608023c449da1f013885e7ccf2fcb6a9e0c8f8d72e91eb4524facf035748"),
        ("effect-flags", effectXIB(attributes: #"userInteractionEnabled="NO" contentMode="scaleAspectFill""#),
         1288, "4963d81b368e3b72a227a49711f03193a8df6aca140492235ab0926d68cfb9e2"),
        ("effect-style-extraLight", effectXIB("extraLight"), 1227, "a0f6e0a007df423a77506f1d04ad9b101c477ed2d670b0806a8232d1a5b48d99"),
        ("effect-style-systemUltraThinMaterial", effectXIB("systemUltraThinMaterial"), 1286, "b61bf5ecc0592b62b7646f2e626d6e9a8e8b27c02426fce877b9330c290198bb"),
        ("effect-pinned", effectXIB(constraints: ConstraintTests.edges.enumerated().map {
            ConstraintTests.constraint($0.offset, "vev-aa-aa1", $0.element, ConstraintTests.root, $0.element)
        }.joined()), 1655, "31820d5051a57c113b1da02a6f78ddfc9e58a1008285502e690086d7964d4745"),
    ]

    /// The effect view without subviews, its blur's styles, its content view listing its subviews
    /// before its constraints, both not adapting to materials.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
