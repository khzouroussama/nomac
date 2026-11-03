import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for xibs' container views and IB's accessibility overrides
/// (`.github/scripts/nib_experiments.py` rounds 57 and 58, `a11y-overrides-*`, `container-*`): sizes
/// and SHA-256 digests of Xcode's nibs.
@Suite struct ContainerAndOverridesTests {
    static func overridden(_ document: String) -> String {
        document.replacingOccurrences(of: "<dependencies>", with: #"<accessibilityOverrides isEnabled="YES" dynamicTypePreference="11"/>"# + "\n<dependencies>")
    }

    static func container(_ attributes: String, children: String = "") -> String {
        ConstraintTests.constrained(ConstraintTests.subview("ccc-cc-cc1", tag: "containerView", attributes: attributes)
            .replacingOccurrences(of: "</containerView>", with: children + "</containerView>"), "")
    }

    static let cases: [(String, String, Int, String)] = [
        ("a11y-overrides-11", overridden(XIBCompilerTests.xib(XIBCompilerTests.view())), 748,
         "98a706d2bd8bfb27e933b998222fcc76e85f3dfb2c82172f1feb9fd6f47919f9"),
        ("a11y-overrides-style", overridden(LabelScaleTests.scaled("0.5", style: "Body")), 1663,
         "739993bc6261e84ee5ee002525c6192cf0d9a3723d7082b43e5a3f96f8e4221b"),
        ("container-panel-containerView", container(#" opaque="NO" clearsContextBeforeDrawing="NO" userInteractionEnabled="NO""#), 929,
         "8462ac35aea4338ebaceebbccd85104462de90145ddd889ef67a424616e530c1"),
        ("container-background-containerView", container(#" opaque="NO""#, children: #"<color key="backgroundColor" white="0.0" alpha="0.0" colorSpace="calibratedWhite"/>"# + "\n"),
         1044, "b5890418a28e75fd8cedf7d12d137481ba47f77f76c39a5e991bd3a14289f6a4"),
    ]

    /// The dynamic type preview changes nothing, text styles included; a container view is a view.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
