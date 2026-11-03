import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for misplaced views, image views of symbol references and
/// localized segmented controls (`.github/scripts/nib_experiments.py` round 59): sizes and SHA-256
/// digests of Xcode's nibs.
@Suite struct SymbolAndMisplacedTests {
    static func symbolView(_ children: String, attributes: String = "") -> String {
        ConstraintTests.constrained(ConstraintTests.subview("iii-ii-ii1", (112, 333, 168, 185), tag: "imageView", attributes: attributes)
            .replacingOccurrences(of: "</imageView>", with: children + "</imageView>"), "", resources: ButtonTests.symbol)
    }

    static func reference(_ scale: String) -> String {
        "<imageReference key=\"image\" image=\"plus\" catalog=\"system\" symbolScale=\"\(scale)\"/>\n"
    }

    static func preferred(_ scale: String) -> String {
        "<preferredSymbolConfiguration key=\"preferredSymbolConfiguration\" scale=\"\(scale)\"/>\n"
    }

    static let segmented = ControlTests.controlXIB("segmentedControl", ControlTests.segmented + #" selectedSegmentIndex="0""#,
                                                   "<segments>\n<segment title=\"First\"/>\n<segment title=\"Second\"/>\n</segments>\n", size: (121, 32))

    static let cases: [(String, String, Int, String)] = [
        ("misplaced-view", ConstraintTests.constrained(ConstraintTests.subview("ccc-cc-cc1", attributes: #" misplaced="YES""#), ""), 872,
         "f656183e6e3a29a51ff1b04554564a7464b0f95b9eeaf34c0d58556f00ab8a80"),
        ("misplaced-scroll", ConstraintTests.constrained(ConstraintTests.subview("ccc-cc-cc1", tag: "scrollView", attributes: #" misplaced="YES""#), ""), 997,
         "a1fd4067db382bfe5b46c30aef3fb90d0341419691c82175f4cd6ca373a00b6c"),
        ("image-view-symbol-reference", symbolView(reference("small")), 1136, "177d0f01a9bd6d5f5e3530b50b90841d2c6231d5faa47d3fb2cae2b31d32182d"),
        ("image-view-symbol-reference-preferred", symbolView(reference("small") + preferred("small")), 1177,
         "a2524bc10b2dc9f225c23a4c960ca6dedd5bb71f13343775cbb5e945f16395ed"),
        ("image-view-symbol-preferred-medium", symbolView(reference("default") + preferred("medium")), 1184,
         "99fbb99fe0d3244c01fcee7138b4da73358b79d426a42f2991348ecc01926fab"),
        ("image-view-symbol-preferred-only", symbolView(preferred("small"), attributes: #" image="plus" catalog="system""#), 1167,
         "f42bb1d27c0eaa28c40d4df050d4aeb4eeae3c1441169715475ede23e62ef8a0"),
    ]

    /// `misplaced` changes nothing; an image reference is an image placeholder with its symbol
    /// configuration; a preferred symbol configuration follows the image and drops `UIOpaque`.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }

    /// `segmented-lproj`: segment titles keyed `<id>.segmentTitles[<index>]`.
    @Test func localizesSegmentTitles() throws {
        let nib = try XIBCompiler.compile(Data(Self.segmented.utf8), path: "/tmp/segmented-lproj/Base.lproj/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == 1534)
        #expect(VariationTests.digest(nib) == "d4f207d27dcdca06b6a871c6ed321e1b03bfc4e62f677865da465ad7029219ad")
    }
}
