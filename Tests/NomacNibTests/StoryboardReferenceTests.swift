import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for storyboard references (`.github/scripts/nib_experiments.py`
/// round 96, `sb-ref-*`): sizes and SHA-256 digests of the files of Xcode's `.storyboardc`.
@Suite struct StoryboardReferenceTests {
    static func reference(_ number: Int, _ attributes: String = #" storyboardName="Other" referencedIdentifier="Ref""#, item: Bool = false) -> String {
        let element = "<viewControllerPlaceholder\(attributes) id=\"ref-aa-aa\(number)\" sceneMemberID=\"viewController\""
            + (item ? ">\n<navigationItem key=\"navigationItem\" id=\"rni-aa-aa\(number)\"/>\n</viewControllerPlaceholder>\n" : "/>\n")
        return "<scene sceneID=\"rsc-aa-aa\(number)\">\n<objects>\n\(element)"
            + "<placeholder placeholderIdentifier=\"IBFirstResponder\" id=\"rfr-aa-aa\(number)\" sceneMemberID=\"firstResponder\"/>\n</objects>\n"
            + "<point key=\"canvasLocation\" x=\"\(400 * number)\" y=\"400\"/>\n</scene>\n"
    }

    static let view = SceneTests.view
    static let tabNib = ContainerControllerTests.nib
    static let cases: [(String, String, [(String, Int, String)])] = [
        ("sb-ref-controller-segue",
         SceneTests.storyboard(SceneTests.scene(1, connections: #"<segue destination="ref-aa-aa1" kind="show" identifier="Go" id="rsg-aa-aa1"/>"# + "\n"),
                               reference(1)),
         [("Info.plist", 523, "6cd8f0a64e32d8afce8a9073dde7f8c4a0cd0b7fa0d1538bd56200933588e80c"),
          ("UIViewController-ref-aa-aa1.nib", 789, "a7c72da013920865df3731805da86e84c8ee9ba3b767360621c7bdf290988b8d"),
          ("UIViewController-vc1-aa-aaa.nib", 1211, "c86a09a5f20026d03ac6fa2a19862e8255373336454cf91c94e1263bc4536e78"),
          ("vc1-aa-aaa-view-vw1-aa-aaa.nib", view.0, view.1)]),
        ("sb-ref-tab", ContainerControllerTests.storyboard(ContainerControllerTests.tab(["vc1-aa-aaa", "ref-aa-aa1"]), SceneTests.scene(1), reference(1, item: true)),
         [("Info.plist", 463, "040db812a25645894a3b89800123f2cf32a35ea8f9540ee5a3d07070ea45fb3a"),
          (tabNib, 1852, "955ffe9b53a51d9bd67663568c70d2d07f7fd861cb3b1243597798444176d67b"),
          ("vc1-aa-aaa-view-vw1-aa-aaa.nib", view.0, view.1)]),
        ("sb-ref-tab-two",
         ContainerControllerTests.storyboard(ContainerControllerTests.tab(["ref-aa-aa1", "ref-aa-aa2"]), reference(1, item: true),
                                             reference(2, #" storyboardName="Third" referencedIdentifier="Three""#, item: true)),
         [("Info.plist", 520, "0aabf48f1266908962556b8b711dcd396f61beb3e713baa9fad92357e536e0e2"),
          (tabNib, 1733, "b5641090f9c37d1481846f74a750e204ce0e0924fc9efcad00b46bb890f88d1c")]),
        ("sb-ref-nav-root",
         NavigationTests.storyboard(NavigationTests.navigation().replacingOccurrences(of: "vc1-aa-aaa", with: "ref-aa-aa1"), reference(1, item: true)),
         [("Info.plist", 475, "d838d6505cae8675ae0c47a1d0ebbd954e4dd489b7fe3ac15c19f0f766fdd154"),
          (NavigationTests.navigationNib, 1650, "e8097ae00b85aaefe141be8062dc328135b2e6666c8cb2faeaad1561f71b9b52")]),
        ("sb-ref-tab-nav-root",
         ContainerControllerTests.storyboard(ContainerControllerTests.tab(["nvc-aa-aaa", "vc2-aa-aaa"]),
                                             ContainerControllerTests.navigation("aa", root: 1, item: ContainerControllerTests.item(1, #" title="Files""#))
                                                 .replacingOccurrences(of: "vc1-aa-aaa", with: "ref-aa-aa1"),
                                             reference(1, item: true), SceneTests.scene(2)),
         [("Info.plist", 463, "040db812a25645894a3b89800123f2cf32a35ea8f9540ee5a3d07070ea45fb3a"),
          (tabNib, 2289, "961a827af75e791d922199c5065c33825d83c843c932be13cb2c8117cdb66368"),
          ("vc2-aa-aaa-view-vw2-aa-aaa.nib", view.0, view.1)]),
    ]

    /// A reference's own nib of its placeholder, or the tab bar or navigation controller inlining
    /// it, and the `Info.plist`'s table of references.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, document: String, files: [(String, Int, String)]) throws {
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        #expect(compiled.keys.sorted() == files.map(\.0).sorted(), "\(name)")
        for (file, size, digest) in files {
            let data = try #require(compiled[file], "\(name) \(file)")
            #expect(data.count == size, "\(name) \(file)")
            #expect(VariationTests.digest(data) == digest, "\(name) \(file)")
        }
    }

    /// `sb-ref-unreached`: a reference nothing reaches is skipped with ibtool's warning, named by its
    /// referenced identifier, and left out of the `Info.plist`.
    @Test func skipsUnreachedReference() throws {
        let document = SceneTests.storyboard(SceneTests.scene(1), Self.reference(1))
        let compiled = try StoryboardCompiler.compileReportingWarnings(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        #expect(compiled.files.keys.sorted() == ["Info.plist", "UIViewController-vc1-aa-aaa.nib", "vc1-aa-aaa-view-vw1-aa-aaa.nib"])
        #expect(VariationTests.digest(try #require(compiled.files["Info.plist"])) == "f6d6c234c4a66f41512f6d252feb69932754237f0784700e4205ab951a49606e")
        #expect(compiled.warnings == ["/tmp/Main.storyboard:ref-aa-aa1: warning: “Ref“ is unreachable because it has no entry points, and no identifier "
                                      + "for runtime access via -[UIStoryboard instantiateViewControllerWithIdentifier:]. [9]"])
    }

    /// A showDetail segue to a reference is not observed.
    @Test func refusesShowDetailToReference() {
        let segue = #"<segue destination="ref-aa-aa1" kind="showDetail" identifier="Go" id="rsg-aa-aa1"/>"# + "\n"
        let document = SceneTests.storyboard(SceneTests.scene(1, connections: segue), Self.reference(1))
        #expect(throws: NomacError("nomac does not compile a storyboard reference reached by a showDetail segue or a bar button item's yet (BACKLOG B-261)",
                                   path: "/tmp/Main.storyboard")) {
            try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        }
    }
}
