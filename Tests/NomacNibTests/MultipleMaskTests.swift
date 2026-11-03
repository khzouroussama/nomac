import Foundation
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for masks of several views and masks beside constants varied by
/// size class (`.github/scripts/nib_experiments.py` round 44, `masks-*`): sizes and SHA-256
/// digests of Xcode's nibs.
@Suite struct MultipleMaskTests {
    typealias C = ConstraintTests

    static func mask(_ references: [String], subviews: [String] = []) -> String {
        "<variation key=\"default\">\n" + (subviews.isEmpty ? "" : "<mask key=\"subviews\">\n" + subviews.map { "<exclude reference=\"\($0)\"/>\n" }.joined() + "</mask>\n")
            + "<mask key=\"constraints\">\n" + references.map { "<exclude reference=\"\($0)\"/>\n" }.joined() + "</mask>\n</variation>\n"
    }

    /// A view holding one subview pinned by its leading and top, the top excluded by default.
    static func masked(_ id: String, _ frame: (Double, Double, Double, Double), inner: String = "", mask: Bool = true, subviewsMask: [String] = []) -> String {
        let prefix = String(id.prefix(3)), child = prefix + "c-cc-cc1"
        return "<view contentMode=\"scaleToFill\" translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"\(id)\">\n"
            + "<rect key=\"frame\" x=\"\(frame.0)\" y=\"\(frame.1)\" width=\"\(frame.2)\" height=\"\(frame.3)\"/>\n<subviews>\n"
            + C.subview(child, (5, 5, 20, 20)) + inner + "</subviews>\n<constraints>\n"
            + "<constraint firstItem=\"\(child)\" firstAttribute=\"leading\" secondItem=\"\(id)\" secondAttribute=\"leading\" constant=\"5\" id=\"\(prefix)l-ll-ll1\"/>\n"
            + "<constraint firstItem=\"\(child)\" firstAttribute=\"top\" secondItem=\"\(id)\" secondAttribute=\"top\" constant=\"5\" id=\"\(prefix)t-tt-tt1\"/>\n"
            + "</constraints>\n" + (mask ? Self.mask([prefix + "t-tt-tt1"], subviews: subviewsMask) : "") + "</view>\n"
    }

    static func rootMasked(_ subviews: String, _ constraints: String, excluded: [String]) -> String {
        C.constrained(subviews, constraints).replacingOccurrences(of: "<point key=\"canvasLocation\"", with: mask(excluded) + "<point key=\"canvasLocation\"")
    }

    static func varied(_ number: Int, _ attribute: String, _ constant: Int) -> String {
        C.constraint(number, C.sub, attribute, C.root, attribute, " constant=\"\(constant)\"")
            .replacingOccurrences(of: "/>\n", with: ">\n<variation key=\"heightClass=regular-widthClass=regular\" constant=\"40\"/>\n</constraint>\n")
    }

    static let pins = TofuFeatureTests.pin("aaa-aa-aa1", 0, 20, 40) + TofuFeatureTests.pin("bbb-bb-bb1", 1, 20, 200)
    static let grandchild = masked("ggg-gg-gg1", (50, 50, 100, 100))
    static func grandWalk(_ constraints: String, excluded: [String] = []) -> String {
        let holder = masked("aaa-aa-aa1", (20, 40, 200, 200), inner: grandchild, mask: false)
        let all = TofuFeatureTests.pin("aaa-aa-aa1", 0, 20, 40) + constraints
        return excluded.isEmpty ? C.constrained(holder, all) : rootMasked(holder, all, excluded: excluded)
    }

    static let width = C.constraint(5, "ggg-gg-gg1", "width", C.root, "width", #" multiplier="0.25""#)
    static let height = C.constraint(6, "ggg-gg-gg1", "height", C.root, "height", #" multiplier="0.117""#)
    static let cases: [(String, String, Int, String)] = [
        ("masks-walk-plain-two", grandWalk(width + height), 2601, "7cdaf4b021a6cdfdd6533c9eeb70a829dd11b2fe61e8b5ad4972342ba5c64e43"),
        ("masks-walk-plain-two-first-excluded", grandWalk(width + height, excluded: ["c05-aa-aaa"]),
         2636, "8e1c68c40f48fe9bc32c83547de501f631177a2150963919276bd3eaf3104f41"),
        ("masks-two-siblings", C.constrained(masked("aaa-aa-aa1", (20, 40, 100, 100)) + masked("bbb-bb-bb1", (20, 200, 100, 100)), pins),
         2540, "6fad0319e66f11681f3ea5f2db022bae5530318bf3b75aec9272f2b250bdd041"),
        ("masks-root-and-sibling", rootMasked(masked("aaa-aa-aa1", (20, 40, 100, 100)) + masked("bbb-bb-bb1", (20, 200, 100, 100), mask: false), pins, excluded: ["c03-aa-aaa"]),
         2546, "40a077dd7cc62d8ac0f6fb58294dd9e74020d154174f2fd87e895f20dedb109d"),
        ("masks-walk-order", C.constrained(masked("aaa-aa-aa1", (20, 40, 200, 200), inner: grandchild) + masked("bbb-bb-bb1", (20, 300, 100, 100)),
                                           TofuFeatureTests.pin("aaa-aa-aa1", 0, 20, 40) + TofuFeatureTests.pin("bbb-bb-bb1", 1, 20, 300)),
         2991, "39c9a1923612ead2e4d5d07f163f64fc5f6900db17b80a8cd1e8fa5ab97c9a03"),
        ("masks-root-to-grandchild", rootMasked(masked("aaa-aa-aa1", (20, 40, 200, 200), inner: grandchild, mask: false),
                                                TofuFeatureTests.pin("aaa-aa-aa1", 0, 20, 40) + C.constraint(5, "ggg-gg-gg1", "width", C.root, "width", #" multiplier="0.25""#),
                                                excluded: ["c01-aa-aaa"]),
         2663, "bac2f40ffb2438f67947e90f0a34684e1fa50594ca1b4eaa42d45774b83ef2b4"),
        ("masks-constants-root-excluded", rootMasked(C.subview(C.sub, (20, 40, 100, 100)),
                                                     varied(0, "leading", 20) + varied(1, "top", 40) + varied(2, "trailing", 273)
                                                         + C.constraint(3, C.sub, "bottom", C.root, "bottom", #" constant="712""#), excluded: ["c02-aa-aaa"]),
         2771, "f110e258b62cff7d273714cb6053d755e614a42758ca24a06140b1f6be8a694c"),
        ("masks-subviews-and-constraints", C.constrained(masked("aaa-aa-aa1", (20, 40, 200, 200), inner: C.subview("xxx-xx-xx1", (100, 100, 20, 20)), subviewsMask: ["xxx-xx-xx1"]),
                                                         TofuFeatureTests.pin("aaa-aa-aa1", 0, 20, 40)),
         2165, "082097112963a1d6ae49f516bc2381ac5a4717bc43b814eea55e7b8881e6b832"),
    ]

    /// A walk of the views, depth first: a view's subviews mask and constraints mask, its
    /// constraints' constants (all of them, then the installed ones again), the first constraint
    /// naming a deeper view walking it in each, then its subviews.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
