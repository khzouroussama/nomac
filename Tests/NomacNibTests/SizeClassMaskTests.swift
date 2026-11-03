import Foundation
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for masks by size class (`.github/scripts/nib_experiments.py`
/// rounds 40 and 41, `sc-mask-*`): sizes and SHA-256 digests of Xcode's nibs.
@Suite struct SizeClassMaskTests {
    typealias C = ConstraintTests
    static let rc = "heightClass=regular-widthClass=compact", cc = "heightClass=compact-widthClass=compact", cr = "heightClass=compact-widthClass=regular"
    static let all = ["heightClass=regular-widthClass=regular", rc, cr, cc, "heightClass=compact", "heightClass=regular", "widthClass=compact", "widthClass=regular"]

    static func masks(_ entries: [(String, String, String, [String])]) -> String {
        entries.map { key, mask, verb, references in
            "<variation key=\"\(key)\">\n<mask key=\"\(mask)\">\n"
                + references.map { "<\(verb) reference=\"\($0)\"/>\n" }.joined() + "</mask>\n</variation>\n"
        }.joined()
    }

    static func document(_ entries: [(String, String, String, [String])], subviews: String = C.subview()) -> String {
        let constraints = C.constraint(0, C.sub, "leading", C.root, "leading") + C.constraint(1, C.sub, "top", C.root, "top")
            + C.constraint(2, C.sub, "trailing", C.root, "trailing") + C.constraint(3, C.sub, "bottom", C.root, "bottom")
        return C.constrained(subviews, constraints).replacingOccurrences(of: "<point key=\"canvasLocation\"", with: masks(entries) + "<point key=\"canvasLocation\"")
    }

    static let c2 = "c02-aa-aaa", c3 = "c03-aa-aaa"
    static let cases: [(String, String, Int, String)] = [
        ("sc-mask-include-one", document([("default", "constraints", "exclude", [c2]), (rc, "constraints", "include", [c2])]),
         1946, "b12f2cd3785fbdab265087d42e5578bf03ee17a2c6017ed486e91a3805d084b3"),
        ("sc-mask-exclude-only", document([(rc, "constraints", "exclude", [c2])]), 1910, "615e7dcfecd300123d00cbe018bc4ce32b82eefc67764232e768f451be214d8a"),
        ("sc-mask-include-and-exclude", document([("default", "constraints", "exclude", [c2]), (rc, "constraints", "include", [c2]), (cr, "constraints", "exclude", [c3])]),
         1994, "36935fbed7ca2c39d0415b4bf4855f108457c583460f3e11aa97e316e629a673"),
        ("sc-mask-subview-include", document([("default", "subviews", "exclude", ["bbb-bb-bb1"]), (rc, "subviews", "include", ["bbb-bb-bb1"])],
                                             subviews: C.subview() + C.subview("bbb-bb-bb1", (150, 20, 100, 50))),
         1986, "8770070c9354366b1a53ae9edcd547dd8741bb1d9902803ec541bc48d4dd9b52"),
        ("sc-mask-include-two", document([("default", "constraints", "exclude", [c2, c3]), (rc, "constraints", "include", [c2]), (cc, "constraints", "include", [c3])]),
         1994, "fc9e4a833a313958d5e2f6ecdf5ae26876d44e62b5a97dfde371bce8fdf657b6"),
        ("sc-mask-order-all", document([("default", "constraints", "exclude", [c2])] + all.map { ($0, "constraints", "include", [c2]) }),
         2283, "f81b6faa76f3da5082d3dff21ccf3021304c2ea34fbeab350e4b24844a0ff6df"),
    ]

    /// A record per variation, the default first, then by size class in the reverse of the
    /// attribute records' order; the default's exclusions not installed; a record's objects in the
    /// candidates' order, as ibtool's here (its memory-address order, ADR 0252).
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }

    static func safeArea(_ constraints: String) -> String {
        C.constrained(C.subview(), constraints, safeArea: true)
            .replacingOccurrences(of: "<point key=\"canvasLocation\"", with: masks([("default", "constraints", "exclude", [c2])]) + "<point key=\"canvasLocation\"")
    }

    static let safeAreaCases: [(String, String, Int, String)] = [
        ("mask-safe-area", safeArea(C.constraint(0, C.sub, "leading", C.safe, "leading", #" constant="20""#) + C.constraint(1, C.sub, "top", C.safe, "top")
                                    + C.constraint(2, C.sub, "leading", C.root, "leading", #" constant="8""#)),
         2450, "097c631f0169d47b997239d650ce2e10cc13d61461f9cd72f554cedcdd1d9372"),
        ("mask-safe-area-trailing", safeArea(C.constraint(0, C.safe, "trailing", C.sub, "trailing", #" constant="20""#) + C.constraint(1, C.sub, "top", C.root, "top")
                                             + C.constraint(2, C.sub, "leading", C.root, "leading", #" constant="8""#)),
         2450, "55344fac2483b16d7924fd401bbc4e3f505978c5fbc55fbe40498549a6a1eb1d"),
    ]

    /// A safe area among the constraints' items is, in the mask's descendants, its view's
    /// unarchived placeholder guide (round 75).
    @Test(arguments: safeAreaCases)
    func safeAreaDescendants(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
