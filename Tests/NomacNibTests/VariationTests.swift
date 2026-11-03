import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for size-class variations of labels' fonts and constraints'
/// constants (`.github/scripts/nib_experiments.py` rounds 19 and 22): sizes and SHA-256 digests of
/// Xcode's nibs.
@Suite struct VariationTests {
    static let regular = "heightClass=regular-widthClass=regular"
    static let compact = "heightClass=regular-widthClass=compact"
    /// The keys of `SIZE_CLASS_KEYS`, in its order.
    static let allKeys = ["heightClass=compact", "heightClass=regular", "widthClass=compact", "widthClass=regular", compact, regular,
                          "heightClass=compact-widthClass=compact", "heightClass=compact-widthClass=regular"]

    static func fonts(_ keys: [String], sizes: [Int]) -> String {
        zip(keys, sizes).map { key, size in
            "<variation key=\"\(key)\">\n" + LabelTests.font(["type": "system", "pointSize": "\(size)"]) + "\n</variation>\n"
        }.joined()
    }

    static func constant(_ number: Int, _ item: String, _ attribute: String, _ owner: String, constant: Int, varied: [(String, Int)]) -> String {
        "<constraint firstItem=\"\(item)\" firstAttribute=\"\(attribute)\" secondItem=\"\(owner)\" secondAttribute=\"\(attribute)\" "
            + "constant=\"\(constant)\" id=\"c\(String(format: "%02d", number))-aa-aaa\">\n"
            + varied.map { "<variation key=\"\($0.0)\" constant=\"\($0.1)\"/>\n" }.joined() + "</constraint>\n"
    }

    static func digest(_ data: Data) -> String {
        SHA256.digest(Array(data)).map { String(format: "%02x", $0) }.joined()
    }

    static let root = ConstraintTests.root
    static let xibCases: [(String, String, Int, String)] = [
        ("variation-font", LabelTests.labelled(LabelTests.label(extra: fonts([compact, regular], sizes: [16, 20]))),
         2590, "d4ee8ff2aeaab34c1bee8ceb3fd078306203a477490c2cb28fba79cd49c0c201"),
        ("variation-constant", LabelTests.labelled(LabelTests.label(), constraints: constant(0, "lll-ll-ll1", "top", root, constant: 120, varied: [(regular, 250)])),
         2841, "7b88f258cee1735715634daad017b3283a50391789d78bc1eefa047ee1bba20c"),
        ("variation-font-and-constant", LabelTests.labelled(LabelTests.label(extra: fonts([compact, regular], sizes: [16, 20])),
                                                             constraints: constant(0, "lll-ll-ll1", "top", root, constant: 120, varied: [(regular, 250)])),
         3257, "b36c42d76fd9bacd05e52482923f3dd3c607585179b8f85bc5d09842fe9a3b76"),
        ("vo-two-labels-constant", LabelTests.labelled(LabelTests.label(extra: fonts([regular], sizes: [16]))
                                                       + LabelTests.label(extra: fonts([regular], sizes: [22]), id: "lll-ll-ll2", y: 80),
                                                       constraints: constant(0, "lll-ll-ll2", "top", root, constant: 80, varied: [(regular, 200)])),
         3476, "ac00530981a0df393202276a5dc80617b5c309823eabe7b689a4fb9ebdcfc28d"),
        ("vo-font-all-reversed", LabelTests.labelled(LabelTests.label(extra: fonts(
            ["heightClass=compact-widthClass=regular", "heightClass=compact-widthClass=compact", regular, compact, "widthClass=regular",
             "widthClass=compact", "heightClass=regular", "heightClass=compact"], sizes: Array(16...23)))),
         3435, "971b069b83a9fb4258aad0f95c32b388073b9aeb979b29690c59daee3bf93281"),
    ]

    /// Records in a fixed order of size classes, constraints' storages twice before labels', the
    /// empty trait collection one object, and an object of no values numbering its first value 0.
    @Test(arguments: xibCases)
    func compilesXIBsAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(Self.digest(nib) == digest, "\(name)")
    }

    /// `sb-vo-all-*`: every key at once; a storyboard's label and constraint take the values of the
    /// first record their device has (fonts 16 to 23 and constants 101 to 108 by `allKeys`).
    static func allVariations(device: String?) -> String {
        let label = LabelTests.label(extra: fonts(allKeys, sizes: Array(16...23)))
        let constraint = constant(0, "lll-ll-ll1", "top", "8bC-Xf-vdC", constant: 120, varied: Array(zip(allKeys, 101...108)))
        return StoryboardCompilerTests.storyboard(StoryboardCompilerTests.scene(viewChildren: "<subviews>\n\(label)</subviews>\n<constraints>\n\(constraint)</constraints>\n"),
                                                  device: device)
    }

    @Test(arguments: [
        ("sb-vo-all-retina6_12", #"<device id="retina6_12" orientation="portrait" appearance="light"/>"#, "554e260b6d9fe285d70ea812caf9ecb1503f44b4e4f8f6bb9dd6eaa6585d70b2"),
        ("sb-vo-all-retina3_5-landscape", #"<device id="retina3_5" orientation="landscape" appearance="light"/>"#, "554e260b6d9fe285d70ea812caf9ecb1503f44b4e4f8f6bb9dd6eaa6585d70b2"),
        ("sb-vo-all-ipad9_7", #"<device id="ipad9_7" orientation="portrait" appearance="light"/>"#, "dffbd83d74475f7e4cf794819e8766bbae9111a96be171525834b186793760f5"),
        ("sb-vo-all-retina6_7-landscape", #"<device id="retina6_7" orientation="landscape" appearance="light"/>"#, "af1470289b3151a761679ed245165f3a5805cda9d00245341714645617980679"),
        ("sb-vo-all-no-device", nil, "593958de998e439f064cf79b29145476264e6117239d8efe93ee76a5fc4244b9"),
    ])
    func compilesStoryboardsAsXcode(name: String, device: String?, digest: String) throws {
        let files = try StoryboardCompiler.compile(Data(Self.allVariations(device: device).utf8), path: "/tmp/Main.storyboard",
                                                   options: StoryboardCompilerTests.options)
        let nib = try #require(files["BYZ-38-t0r-view-8bC-Xf-vdC.nib"])
        #expect(nib.count == 5459, "\(name)")
        #expect(Self.digest(nib) == digest, "\(name)")
    }

    @Test(arguments: [
        (SizeClasses.device("retina6_12", landscape: false), SizeClasses(horizontal: 1, vertical: 2)),
        (SizeClasses.device("retina6_12", landscape: true), SizeClasses(horizontal: 1, vertical: 1)),
        (SizeClasses.device("retina6_1", landscape: true), SizeClasses(horizontal: 2, vertical: 1)),
        (SizeClasses.device("ipad11_0rounded", landscape: false), SizeClasses(horizontal: 2, vertical: 2)),
    ])
    func sizesClassesByDevice(device: SizeClasses, expected: SizeClasses) {
        #expect(device == expected)
    }

    /// `mask-subviews-root-constrained`: a mask excluding a subview that constraints name, which
    /// ibtool warns about and drops with it.
    @Test func refusesMasksOfConstrainedSubviews() {
        let masks = "<variation key=\"default\">\n<mask key=\"subviews\">\n<exclude reference=\"\(ConstraintTests.sub)\"/>\n</mask>\n</variation>\n"
        let xib = ConstraintTests.constrained(ConstraintTests.subview(), ConstraintTests.pinned(ConstraintTests.sub, 0))
            .replacingOccurrences(of: "<point key=\"canvasLocation\"", with: masks + "<point key=\"canvasLocation\"")
        #expect(throws: NomacError("nomac does not compile a mask excluding a constrained subview (ibtool warns) yet (BACKLOG B-260)", path: "/tmp/View.xib")) {
            try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        }
    }
}
