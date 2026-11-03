import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for safe areas of subviews and the header attributes that change
/// nothing (`.github/scripts/nib_experiments.py` round 37): sizes and SHA-256 digests of Xcode's nibs.
@Suite struct SubviewSafeAreaTests {
    static let safeArea = #"<viewLayoutGuide key="safeArea" id="ssa-aa-aa1"/>"# + "\n"
    static let inner = "<subviews>\n<view contentMode=\"scaleToFill\" translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"inn-aa-aa1\">\n"
        + #"<rect key="frame" x="10" y="10" width="50" height="20"/>"# + "\n</view>\n</subviews>\n"

    static func withSubview(_ children: String) -> String {
        ConstraintTests.constrained(ConstraintTests.subview().replacingOccurrences(of: "</view>", with: children + "</view>"), "", safeArea: true)
    }

    static let cases: [(String, String, Int, String)] = [
        ("header-instantiation-direct", XIBCompilerTests.xib(XIBCompilerTests.view()).replacingOccurrences(
            of: #" colorMatched="YES">"#, with: #" customObjectInstantitationMethod="direct" colorMatched="YES">"#),
         748, "98a706d2bd8bfb27e933b998222fcc76e85f3dfb2c82172f1feb9fd6f47919f9"),
        ("subview-safe-area", withSubview(safeArea), 1088, "cd7c9a3db5d212fbea53ad3f86358a042f5fb57e447854b1e864d6e4dacf01be"),
        ("subview-safe-area-constrained", withSubview(inner + safeArea + "<constraints>\n"
            + ConstraintTests.constraint(10, "inn-aa-aa1", "top", "ssa-aa-aa1", "top", #" constant="10""#)
            + ConstraintTests.constraint(11, "inn-aa-aa1", "leading", "ssa-aa-aa1", "leading", #" constant="10""#) + "</constraints>\n"),
         2027, "cc8bc9ddc1d264e5da994732e41102c7ec046b248e2a1b64fc8cbe69e85b5880"),
    ]

    /// A subview's safe area is listed and constrained as a top-level view's;
    /// `customObjectInstantitationMethod="direct"` changes nothing.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
