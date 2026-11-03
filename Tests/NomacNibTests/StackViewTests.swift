import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for stack views, layout margins and custom classes of labels and
/// image views in xibs (`.github/scripts/nib_experiments.py` round 33, `stack`): sizes and SHA-256
/// digests of Xcode's nibs.
@Suite struct StackViewTests {
    static let attributes = #"opaque="NO" contentMode="scaleToFill""#

    static func label(_ id: String, x: Double, y: Double, text: String = "Label", mask: String = "") -> String {
        "<label opaque=\"NO\" userInteractionEnabled=\"NO\" contentMode=\"left\" horizontalHuggingPriority=\"251\" verticalHuggingPriority=\"251\" "
            + "text=\"\(text)\" textAlignment=\"natural\" lineBreakMode=\"tailTruncation\" baselineAdjustment=\"alignBaselines\" adjustsFontSizeToFit=\"NO\" "
            + "translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"\(id)\">\n\(mask)<rect key=\"frame\" x=\"\(x)\" y=\"\(y)\" width=\"42\" height=\"21\"/>\n"
            + #"<fontDescription key="fontDescription" type="system" pointSize="17"/>"# + "\n<nil key=\"textColor\"/>\n<nil key=\"highlightedColor\"/>\n</label>\n"
    }

    static let horizontal = label("lab-aa-aa1", x: 0, y: 0) + label("lab-aa-aa2", x: 50, y: 0, text: "Other")
    static let vertical = label("lab-aa-aa1", x: 0, y: 0) + label("lab-aa-aa2", x: 0, y: 29, text: "Other")
    static let views = "<view contentMode=\"scaleToFill\" id=\"vvv-aa-aa1\">\n<rect key=\"frame\" x=\"0.0\" y=\"0.0\" width=\"40\" height=\"21\"/>\n</view>\n"
        + "<view contentMode=\"scaleToFill\" id=\"vvv-aa-aa2\">\n<rect key=\"frame\" x=\"50\" y=\"0.0\" width=\"42\" height=\"21\"/>\n</view>\n"
    static let mask = #"<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>"# + "\n"
    static let directional = #"<directionalEdgeInsets key="directionalLayoutMargins" top="1" leading="2" bottom="3" trailing="4"/>"# + "\n"

    static func stackXIB(_ attributes: String = attributes, _ arranged: String? = horizontal, extra: String = "",
                         frame: String = #"x="20" y="40" width="92" height="21""#) -> String {
        let subviews = arranged.map { "<subviews>\n\($0)</subviews>\n" } ?? ""
        return ConstraintTests.constrained("<stackView \(attributes) translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"stk-aa-aa1\">\n"
                                           + "<rect key=\"frame\" \(frame)/>\n\(subviews)\(extra)</stackView>\n", "")
    }

    static let cases: [(String, String, Int, String)] = [
        ("stack", stackXIB(), 2396, "1f1d80b14e6c69317b04887f9d6ebb9cc303c44a4934d0ef223f378c77f6f7e4"),
        ("stack-vertical", stackXIB(attributes + #" axis="vertical""#, vertical, frame: #"x="20" y="40" width="42" height="50""#),
         2396, "9e21e0dc240eeb9f003cee38f3703991f6bff1de3d1831a89fe6381962b5947a"),
        ("stack-empty", stackXIB(attributes, nil, frame: #"x="20" y="40" width="100" height="50""#),
         1104, "ee3e8d4f388d2736f2889cf9af3812b3ce413b3a0d0c2cb09cdeaca570f3f24d"),
        ("stack-all", stackXIB(attributes + #" axis="vertical" distribution="equalSpacing" alignment="center" spacing="12" baselineRelativeArrangement="YES""#,
                               vertical, frame: #"x="20" y="40" width="42" height="50""#),
         2396, "1ef92dcb4d7969c36d6c3a84db52e45933698c9ad5bd6f3406db85a75a37d857"),
        ("stack-views", stackXIB(attributes, views), 1392, "fdef9acaffca15d54f299e67e3654c23c479a127b514427c043d7964f0e4c659"),
        ("stack-arranged-mask", stackXIB(attributes, label("lab-aa-aa1", x: 0, y: 0, mask: mask) + label("lab-aa-aa2", x: 50, y: 0)),
         2385, "a045e0e18be23d57a3407a8b212db5d064497d98c304edae50c2b33e110502e1"),
        ("stack-margins-flags", stackXIB(attributes + #" insetsLayoutMarginsFromSafeArea="NO" preservesSuperviewLayoutMargins="YES" layoutMarginsFollowReadableWidth="YES""#,
                                         extra: directional), 2592, "67d577cc279b678dd8298b5b591fabbb6b6945af9ce433e84aade1774ab0eb91"),
        ("stack-custom-class", stackXIB(attributes + #" customClass="MyStack" customModule="T" customModuleProvider="target""#),
         2480, "c5cc8560c1361e0bb349f4b3bff12bcbb879ca26b5ff6e49a58820d059cf9249"),
        ("view-margins-edge", ConstraintTests.constrained(ConstraintTests.subview().replacingOccurrences(
            of: "</view>", with: #"<edgeInsets key="layoutMargins" top="1" left="2" bottom="3" right="4"/>"# + "\n</view>"), ""),
         928, "a9c6e30708095967e9cd9018b6ace063b297e25e59e80412afbcf6e093cecbde"),
        ("view-insets-preserves", ConstraintTests.constrained(ConstraintTests.subview(
            attributes: #" insetsLayoutMarginsFromSafeArea="NO" preservesSuperviewLayoutMargins="YES""#), ""),
         990, "b079397ae9d5f539717ae71798842907ca6f785b06f3214284f4307a257ff2f1"),
        ("label-custom-class-module", ConstraintTests.constrained(LabelTests.label(LabelTests.attributes
            + #" customClass="MyLabel" customModule="T" customModuleProvider="target""#), ""),
         1893, "78b7f8aa2c6d4b9ebdcb5218c7b00e99855879ef50c57b46593da91d8d3ede8c"),
        ("image-view-custom-class-module", ConstraintTests.constrained(ConstraintTests.subview("iii-ii-ii1", (112, 333, 168, 185), tag: "imageView",
            attributes: #" image="Logo" customClass="MyImage" customModule="T" customModuleProvider="target""#), "", resources: ConstraintTests.logo),
         1163, "1035e361140da0551b4dcbb3d9e9cf9ba24027ffe13745dbbd026389df04b57e"),
    ]

    /// The arranged subviews, axis, distribution, alignment, spacing and arrangement flags after a
    /// view's keys; layout margins (zeros for a stack view without any) and their flags in ibtool's
    /// order; `UIClassSwapper`s naming `UILabel` and `UIImageView`.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }

    static func varied(_ variations: [(String, String)], _ attributes: String = attributes + #" spacing="8""#) -> String {
        stackXIB(attributes, extra: variations.map { "<variation key=\"\($0.0)\"\($0.1)/>\n" }.joined())
    }

    static let variationCases: [(String, String, Int, String)] = [
        ("stack-vary-axis-spacing", varied([("heightClass=compact", #" axis="horizontal" spacing="20""#)], attributes + #" axis="vertical" spacing="8""#),
         2978, "954a2ad8aabeb977e7f9b6f8339bf7886984209e56bdbbbc13787b1a81ab0d62"),
        ("stack-vary-spacing-default", varied([("heightClass=compact", #" spacing="1""#)], attributes), 2861,
         "efaa8d40ba94d7f59d9c98ffe401e5b1e618af165b2457c1833f2aaae32b9c2a"),
        ("stack-vary-distribution-spacing", varied(["heightClass=compact-widthClass=compact", "heightClass=compact-widthClass=regular",
                                                    "heightClass=regular-widthClass=regular"].map { ($0, #" distribution="fillEqually" spacing="20""#) }),
         3182, "ba36afadbe27268b96fdfa2f65b28de05cdbeba8108e65b2f051e6d4c5f906c1"),
        ("stack-vary-spacing-two", varied([("widthClass=regular", #" spacing="30""#), ("heightClass=compact", #" spacing="1""#)]), 2963,
         "b948cd69333af60b1aa1c279cabf08c4df75d65cf13f1e1175feaccda42faa84"),
    ]

    /// Size-class variations of the axis, distribution and spacing: a trait storage each, in that
    /// order, of numbers, an absent spacing's default the integer 0.
    @Test(arguments: variationCases)
    func variations(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
