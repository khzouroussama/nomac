import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for accessibility configurations in xibs
/// (`.github/scripts/nib_experiments.py` round 40, `accessibility`): sizes and SHA-256 digests of
/// Xcode's nibs.
@Suite struct AccessibilityTests {
    static func accessibility(_ attributes: String = "", _ children: String = "") -> String {
        let head = #"<accessibility key="accessibilityConfiguration""# + attributes
        return children.isEmpty ? head + "/>\n" : head + ">\n\(children)</accessibility>\n"
    }

    static let element = #"<bool key="isElement" value="YES"/>"# + "\n"
    static let all = RuntimeAttributeTests.xib(RuntimeAttributeTests.withRuntime(accessibility(#" identifier="close" label="Close" hint="Closes""#,
                                                                                               element + #"<accessibilityTraits key="traits" button="YES"/>"# + "\n")))

    static let cases: [(String, String, Int, String)] = [
        ("a11y-all", all, 1155, "a71dfa329b4e62ccd540484cf5fa92da1a835654eca1e6e4a8fe3f86c005ed6d"),
        ("a11y-empty", RuntimeAttributeTests.xib(RuntimeAttributeTests.withRuntime(accessibility())), 950, "54be52f60d0bc34db8a5d5af4b9ebddfc178a403e63460c9c8e9ba576017ea74"),
        ("a11y-element-no", RuntimeAttributeTests.xib(RuntimeAttributeTests.withRuntime(accessibility("", #"<bool key="isElement" value="NO"/>"# + "\n"))),
         1008, "04b3e382ecfcddd174a71b5343bf8cdad56119b88c7e10cbb2f8fb6a1975860b"),
        ("a11y-parent-child", RuntimeAttributeTests.xib(RuntimeAttributeTests.withRuntime(accessibility(#" label="child""#))).replacingOccurrences(
            of: #"<point key="canvasLocation""#, with: accessibility(#" label="parent""#) + #"<point key="canvasLocation""#),
         1021, "091fb72c64ea479890767459151edbf7b920371329f479efb9797823aff1de36"),
        ("a11y-traits-image-notEnabled", RuntimeAttributeTests.xib(RuntimeAttributeTests.withRuntime(accessibility(
            "", #"<accessibilityTraits key="traits" image="YES" notEnabled="YES"/>"# + "\n"))),
         1006, "0240f37b3b88e545f66912028255bb92a97a38424c3ec875eb8e3ab72619866d"),
        ("a11y-traits-header", RuntimeAttributeTests.xib(RuntimeAttributeTests.withRuntime(accessibility("", #"<accessibilityTraits key="traits" header="YES"/>"# + "\n"))),
         1008, "41b1b6a81d12aff66e176f4bd0f5ef4e0889336d5e817de13225739690863606"),
        ("a11y-with-udra", RuntimeAttributeTests.xib(RuntimeAttributeTests.withRuntime(RuntimeAttributeTests.runtime(RuntimeAttributeTests.radius)
                                                                                         + accessibility(#" label="Close""#))),
         1118, "79739857714599ecf9eb50860a20198c823d22679c8da077206f02d86fcff529"),
    ]

    /// One `UIRuntimeAccessibilityConfiguration` per object, in the order of all objects, its
    /// texts, trait bits and element flag as numbers shared with the nib's others.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }

    /// In an `.lproj` folder the label and hint are localizable, the identifier not (`a11y-lproj`).
    @Test func localizesLabelAndHint() throws {
        let nib = try XIBCompiler.compile(Data(Self.all.utf8), path: "/tmp/a11y-lproj/Base.lproj/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == 1305)
        #expect(VariationTests.digest(nib) == "ab11ef3072b58b0c661f9009ff40390197f132465c8439d0d9bab54b97d271e6")
    }
}
