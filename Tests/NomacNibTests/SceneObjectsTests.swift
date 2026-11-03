import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for views beside a scene's controller, cells' segues in a
/// navigation controller's root, and actions to another scene (`.github/scripts/nib_experiments.py`
/// round 32: `sb-extra-view*`, `sb-cellseg-nav-root`, `sb-action-other-scene`): sizes and SHA-256
/// digests of the files of Xcode's `.storyboardc`.
@Suite struct SceneObjectsTests {
    typealias Controllers = TableViewControllerTests

    static func extraView(_ number: Int, subview: Bool = true) -> String {
        let inner = subview ? "<subviews>\n" + ConstraintTests.subview("xs\(number)-aa-aaa", (16, 21, 208, 86)) + "</subviews>\n<constraints>\n"
            + "<constraint firstItem=\"xs\(number)-aa-aaa\" firstAttribute=\"leading\" secondItem=\"xv\(number)-aa-aaa\" secondAttribute=\"leadingMargin\" id=\"xc\(number)-aa-aaa\"/>\n"
            + "<constraint firstItem=\"xs\(number)-aa-aaa\" firstAttribute=\"centerY\" secondItem=\"xv\(number)-aa-aaa\" secondAttribute=\"centerY\" id=\"xd\(number)-aa-aaa\"/>\n"
            + "</constraints>\n" : ""
        return "<view contentMode=\"scaleToFill\" id=\"xv\(number)-aa-aaa\">\n<rect key=\"frame\" x=\"0.0\" y=\"0.0\" width=\"240\" height=\"128\"/>\n"
            + "<autoresizingMask key=\"autoresizingMask\" flexibleMaxX=\"YES\" flexibleMaxY=\"YES\"/>\n\(inner)</view>\n"
    }

    static func withViews(_ scene: String, _ views: String...) -> String {
        scene.replacingOccurrences(of: "</objects>", with: views.joined() + "</objects>")
    }

    static func outlet(_ number: Int) -> String {
        "<outlet property=\"emptyView\(number)\" destination=\"xv\(number)-aa-aaa\" id=\"xo\(number)-aa-aaa\"/>\n"
    }

    static let custom = Controllers.custom.replacingOccurrences(of: "ListController", with: "VC")
    static let next = "<segue destination=\"vc2-aa-aaa\" kind=\"show\" identifier=\"Next\" id=\"tsg-aa-aaa\"/>\n"
    static let root = NavigationTests.navigation(root: 0).replacingOccurrences(of: "vc0-aa-aaa", with: "tvc-aa-aaa")
    static let field = TofuFeatureTests.field(connections: "<connections>\n<action selector=\"changed:\" destination=\"vc2-aa-aaa\" eventType=\"editingChanged\" id=\"act-aa-aaa\"/>\n</connections>\n")
    static let navigationNib = NavigationTests.navigationNib, rootView = "tvc-aa-aaa-view-tbv-aa-aaa.nib"

    static let cases: [(String, String, [(String, Int, String)])] = [
        ("sb-extra-view-two", SceneTests.storyboard(withViews(SceneTests.scene(1, attributes: custom, connections: outlet(2) + outlet(1)), extraView(1), extraView(2, subview: false))),
         [("UIViewController-vc1-aa-aaa.nib", 1879, "47ff760837cee1de5ccb57927091c9ef7de1f11810a8c173b2e1b3f1bcb95261")]),
        ("sb-extra-view-nav-root", NavigationTests.storyboard(root, withViews(Controllers.scene(Controllers.prototypes(Controllers.cell(1)),
                                                                                                 attributes: #" definesPresentationContext="YES""# + Controllers.custom,
                                                                                                 afterView: NavigationTests.item() + "<connections>\n" + outlet(1) + next + "</connections>\n"),
                                                                               extraView(1)), SceneTests.scene(2)),
         [(navigationNib, 2907, "b7776b5a2f551349e5f9ecce96c395e6ef44a211d8223da1d4deb555c83afad5"),
          (rootView, 3029, "e61d5fd800ac3ad2dce03c0a66183a667ab8d37aabbd64732160a57082e690c4")]),
        ("sb-cellseg-nav-root", NavigationTests.storyboard(root, Controllers.scene(Controllers.staticSection(CellSegueTests.withConnections(Controllers.cell(1, y: 0, attributes: ""),
                                                                                                                                          CellSegueTests.segue("show"))
                                                                                                             + Controllers.cell(2, y: 44, attributes: "")),
                                                                                   attributes: Controllers.custom,
                                                                                   afterView: NavigationTests.item() + "<connections>\n"
                                                                                       + next.replacingOccurrences(of: #"kind="show" identifier="Next""#, with: #"kind="presentation" identifier="Edit""#)
                                                                                       + "</connections>\n", dataMode: "static"), SceneTests.scene(2)),
         [(navigationNib, 2343, "6f40c8e27ede7d2d7052592b3a33fea0decf4a777670ad8fa105f5562db18785"),
          (rootView, 2764, "f2bcbf223c908f1de60974e6544a8aa3683056f07c5dbc84a451f5da34883ff9")]),
        ("sb-action-other-scene", SceneTests.storyboard(SceneTests.scene(1, connections: SceneTests.segue(2, "show", 1, "Next"))
            .replacingOccurrences(of: "heightSizable=\"YES\"/>\n", with: "heightSizable=\"YES\"/>\n<subviews>\n\(field)</subviews>\n"), SceneTests.scene(2)),
         [("vc1-aa-aaa-view-vw1-aa-aaa.nib", 2752, "4f43cd9b2b8a8f517c01b2bb068260248662d8e32503ba1ac97e6447b7dbb9a4")]),
    ]

    /// Views beside the controller in its nib, kept alive by it, its outlets to them; all objects
    /// breadth first; a root's cells' segue placeholders; an action to another scene left out.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, document: String, files: [(String, Int, String)]) throws {
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        for (file, size, digest) in files {
            let data = try #require(compiled[file], "\(name) \(file)")
            #expect(data.count == size, "\(name) \(file)")
            #expect(VariationTests.digest(data) == digest, "\(name) \(file)")
        }
    }
}
