import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for navigation bars among subviews (`.github/scripts/nib_experiments.py`
/// round 64, `nav-bar-sub-*`): sizes and SHA-256 digests of Xcode's nibs.
@Suite struct SubviewNavigationBarTests {
    static func bar(_ item: String = #"<navigationItem id="nvi-aa-aa1"/>"#, attributes: String = "", frame: (Double, Double, Double, Double) = (0, 0, 393, 64),
                    constraints: String = "") -> String {
        ConstraintTests.constrained(ConstraintTests.subview("nvb-aa-aa1", frame, tag: "navigationBar", attributes: attributes, constraints: constraints)
            .replacingOccurrences(of: "</navigationBar>", with: "<items>\n\(item)\n</items>\n</navigationBar>"), "")
    }

    static let cases: [(String, String, Int, String)] = [
        ("nav-bar-sub-empty-item", bar(constraints: #"<constraint firstAttribute="height" constant="64" id="nbh-aa-aa1"/>"# + "\n"), 1452,
         "64b8b7e0c433760ae26afccff1e6b6a163d12668c44a2d4bb6e7cac2d99ea4b0"),
        ("nav-bar-sub-title", bar(#"<navigationItem title="Hello" id="nvi-aa-aa1"/>"#), 1323, "de8c22279fd7b436440534cd3435795222970136ea45697b90b2fec110759944"),
        ("nav-bar-sub-opaque", bar(attributes: #" translucent="NO""#, frame: (0, 48, 393, 54)), 1198, "b7a4887bfc60658c6229648af9de45b0f9c042f0e3f2a89ce345a448bbaa18d8"),
        ("nav-bar-sub-done", bar(#"<navigationItem title="Hello" id="nvi-aa-aa1">"# + "\n" + #"<barButtonItem key="rightBarButtonItem" style="done" systemItem="done" id="dne-aa-aa1"/>"#
                                 + "\n</navigationItem>"), 1472, "27f86f0000da7cb5a34c13141a8f046c3da2c66584762351a23c1fc095ba3623"),
    ]

    /// A view's keys with hugging, zero directional margins and opacity only when not translucent;
    /// its items with the nib's empty array and the bar; the bar position 2.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
