import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for masks in collection view cells and empty masks
/// (`.github/scripts/nib_experiments.py` round 116, `cvmask-*`, `sb-cvc-cvmask-*`, `mask-empty-*`):
/// sizes and SHA-256 digests of Xcode's nibs.
@Suite struct CollectionCellMaskTests {
    typealias C = CollectionViewCellTests
    typealias K = ConstraintTests
    typealias V = CollectionViewControllerTests
    static let rc = "heightClass=regular-widthClass=compact"
    static let old = C.safeArea + C.customSize

    static func mask(_ references: [String], key: String = "default", verb: String = "exclude", mask: String = "constraints") -> String {
        "<variation key=\"\(key)\">\n<mask key=\"\(mask)\">\n" + references.map { "<\(verb) reference=\"\($0)\"/>\n" }.joined() + "</mask>\n</variation>\n"
    }

    static func constraints(_ container: String) -> String {
        let label = "lll-ll-ll1"
        return "<constraints>\n" + K.constraint(0, label, "leading", container, "leading", #" constant="4""#) + K.constraint(1, label, "top", container, "top", #" constant="14""#)
            + K.constraint(2, container, "trailing", label, "trailing", #" constant="4""#) + K.constraint(3, container, "bottom", label, "bottom", #" constant="15""#) + "</constraints>\n"
    }

    static let c1 = "c01-aa-aaa", c2 = "c02-aa-aaa"
    static let cases: [(String, String, Int, String)] = [
        ("cvmask-old-one", C.cellXIB(C.labels, old + constraints(C.cell) + mask([c2]), legacy: true), 4014, "cf1810a21c403d4bcf22191a6d2770dfafeffa86b295d05d10008639c4722f83"),
        ("cvmask-old-two", C.cellXIB(C.labels, old + constraints(C.cell) + mask([c1, c2]), legacy: true), 4012, "a502f3bb64b44c10d361fa6cf64dfb1c562784c262190071ec9771a34b130b27"),
        ("cvmask-old-size-class", C.cellXIB(C.labels, old + constraints(C.cell) + mask([c2]) + mask([c2], key: rc, verb: "include"), legacy: true),
         4187, "9fcff22423e577e1b92c2a6de2f0982c8aa89453a22250fb04eec129a02b2ee0"),
        ("cvmask-old-size-class-only", C.cellXIB(C.labels, old + constraints(C.cell) + mask([c2], key: "heightClass=compact"), legacy: true),
         4085, "399b87d60772be6a9261e1d0e64136afaf77a889cc6ea427ae091cc3796c1c75"),
        ("cvmask-old-subviews", C.cellXIB(C.labels, old + mask(["lll-ll-ll1"], mask: "subviews"), legacy: true), 3201, "1708bc725551d2fcef385f6712a2e5da50bb4d70f191b7a32651022d4ecc08d4"),
        ("cvmask-new-content", C.cellXIB(C.labels + constraints(C.content) + mask([c2])), 3417, "26b8e4681ab6187b518114a1b21a48708573be16b7adae35ea86ba50f3025e49"),
    ]

    /// An old cell's mask, whose constraints its content view installs, stays the cell's: its object
    /// is the cell and its descendants leave out the content view; a current cell's content view's
    /// is that view's. An excluded subview does not count for the content view's safe area.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }

    static let prototypeConstraints = "<constraints>\n"
        + #"<constraint firstItem="cvl-aa-aa1" firstAttribute="leading" secondItem="cel-aa-aa1" secondAttribute="leading" constant="10" id="c00-aa-aaa"/>"# + "\n"
        + #"<constraint firstItem="cvl-aa-aa1" firstAttribute="top" secondItem="cel-aa-aa1" secondAttribute="top" constant="10" id="c01-aa-aaa"/>"# + "\n"
        + #"<constraint firstItem="cvl-aa-aa1" firstAttribute="trailing" secondItem="cel-aa-aa1" secondAttribute="trailing" constant="76" id="c02-aa-aaa"/>"# + "\n</constraints>\n"

    static func prototype(_ variations: String = "") -> String {
        let cell = V.cell.replacingOccurrences(of: "</view>\n</collectionViewCell>", with: CollectionSectionViewTests.label.replacingOccurrences(of: "sfl-aa-aa1", with: "cvl-aa-aa1")
            + "</view>\n" + prototypeConstraints + variations + "</collectionViewCell>")
        return NavigationTests.storyboard(initial: "cvc-aa-aaa", V.scene(cell))
    }

    /// A prototype cell with constraints of its own has its content view's generated constraints
    /// and a mask as other cells.
    @Test(arguments: [
        ("sb-cvc-cvmask-none", prototype(), 4259, "b863ef9a952b20ede0661621db6864d30a7ab66d733a416305b45274885aa7f7"),
        ("sb-cvc-cvmask-one", prototype(mask([c2])), 4755, "62a1593b7ba34dda48bcc564ecfefd1af939ef8259b43513a49e8e4be81ca21a"),
        ("sb-cvc-cvmask-size-class", prototype(mask([c2]) + mask([c2], key: rc, verb: "include")), 4936, "9b6d230c76502dbda12dfd05ac94e982d2d9e15768cce8c923ebafc9d7c3d080"),
    ])
    func prototypeCells(name: String, document: String, size: Int, digest: String) throws {
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        let data = try #require(compiled[V.viewNib], "\(name)")
        #expect(data.count == size, "\(name)")
        #expect(VariationTests.digest(data) == digest, "\(name)")
    }

    /// An empty mask changes nothing.
    @Test func emptyMaskIsAsNone() throws {
        let constraints = K.constraint(0, "bbb-bb-bb1", "leading", K.root, "leading", #" constant="10""#) + K.constraint(1, "bbb-bb-bb1", "top", K.root, "top", #" constant="10""#)
        let document = K.constrained(K.subview("bbb-bb-bb1", (10, 10, 100, 50)), constraints)
            .replacingOccurrences(of: "<point key=\"canvasLocation\"", with: "<variation key=\"default\">\n<mask key=\"constraints\"/>\n</variation>\n<point key=\"canvasLocation\"")
        let nib = try XIBCompiler.compile(Data(document.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == 1252)
        #expect(VariationTests.digest(nib) == "bb5fcb06a2615965fa3f8b2de10ce98f3109fd971f3a815f7eb14f4ef3741ca5")
    }

    /// A current cell's own constraints or masks: ibtool fails on a mask on the cell (`cvmask-new-on-cell`).
    @Test func refusesMasksOfACurrentCell() {
        let document = C.cellXIB(C.labels + Self.constraints(C.content), Self.mask([Self.c2]))
        #expect(throws: NomacError("nomac does not compile constraints or variations of a collection view cell of Xcode 12's template yet (BACKLOG B-260)", path: "/tmp/View.xib")) {
            try XIBCompiler.compile(Data(document.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        }
    }
}
