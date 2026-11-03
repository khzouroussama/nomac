import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for navigation controllers' roots that are also the initial
/// controller or that segues reach, for documents of the retina6_72 device or of older header
/// elements, and for controllers' simulated bars (`.github/scripts/nib_experiments.py` rounds 110 to
/// 112): sizes and SHA-256 digests of
/// the files of Xcode's `.storyboardc` and nibs.
@Suite struct NavigationRootTests {
    static let view = SceneTests.view
    static let back = #"<segue destination="vc1-aa-aaa" kind="show" identifier="Back" id="bck-aa-aaa"/>"# + "\n"
    static let go = #"<segue destination="vc2-aa-aaa" kind="show" identifier="Go" id="gog-aa-aaa"/>"# + "\n"
    static let device = #"<device id="retina6_12" orientation="portrait" appearance="light"/>"#

    static let cases: [(String, String, [(String, Int, String)])] = [
        ("sb-nav-root-initial", NavigationTests.storyboard(initial: "vc1-aa-aaa", NavigationTests.navigation(attributes: #" storyboardIdentifier="Nav""#), SceneTests.scene(1)),
         [("Info.plist", 270, "c8d856cc93d9e355d92c560ff30b9a98aaa7ad0052fe36c69414dcd54873fa53"),
          ("Nav.nib", 1750, "c754e5ab28c5f34261bd398c566259baa15999837d74f797fd22c6dabb5fd67c"),
          ("UIViewController-vc1-aa-aaa.nib", 924, "14045505a14f06410f7666e5cf1ccfdfc42f725a3aae7cdc9f9a7ce0640d5506"),
          ("vc1-aa-aaa-view-vw1-aa-aaa.nib", view.0, view.1)]),
        ("sb-nav-root-reached", NavigationTests.storyboard(NavigationTests.navigation(), SceneTests.scene(1, connections: go), SceneTests.scene(2, connections: back)),
         [("Info.plist", 417, "89baf6fc03ed2cdb3207371815d81f029aca1caf8853ff623cb4fdcab456c706"),
          (NavigationTests.navigationNib, 1984, "df66e9970dabe0a01a9e5eb9e8f13123bc6aeb78ec4d921cbe0aa41d5e52e96f"),
          ("UIViewController-vc1-aa-aaa.nib", 1147, "247ac9456cc69b18fcb1c7bdb93fc23e42c6abd363332080e4010c05f50d7f89"),
          ("UIViewController-vc2-aa-aaa.nib", 1149, "87c084fc215e05e425ae19a44b98a776bbab9fa9c16c71bf538bd5cf7dbb26a1"),
          ("vc1-aa-aaa-view-vw1-aa-aaa.nib", view.0, view.1), ("vc2-aa-aaa-view-vw2-aa-aaa.nib", view.0, view.1)]),
        ("sb-device-retina6_72-landscape", SceneTests.storyboard(SceneTests.scene(1))
            .replacingOccurrences(of: device, with: #"<device id="retina6_72" orientation="landscape" appearance="light"/>"#),
         [("vc1-aa-aaa-view-vw1-aa-aaa.nib", view.0, view.1)]),
    ]

    /// A root that is the initial controller or that segues reach has a nib of its own besides its
    /// navigation controller's, which writes it as a class swapper when it is an entry point; a
    /// retina6_72 scene is 393 x 852 in either orientation.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, document: String, files: [(String, Int, String)]) throws {
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        for (file, size, digest) in files {
            let data = try #require(compiled[file], "\(name) \(file)")
            #expect(data.count == size, "\(name) \(file)")
            #expect(VariationTests.digest(data) == digest, "\(name) \(file)")
        }
    }

    /// The constraints-with-multipliers capability and Xcode 5's `<development>` change nothing.
    @Test func olderHeaderElementsChangeNothing() throws {
        let plain = try XIBCompiler.compile(Data(XIBCompilerTests.xib(XIBCompilerTests.view()).utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(VariationTests.digest(plain) == "98a706d2bd8bfb27e933b998222fcc76e85f3dfb2c82172f1feb9fd6f47919f9")
        for xib in [XIBCompilerTests.xib(XIBCompilerTests.view()).replacingOccurrences(of: "<capability name=\"documents saved",
                                                                                   with: "<capability name=\"Constraints with non-1.0 multipliers\" minToolsVersion=\"5.1\"/>\n<capability name=\"documents saved"),
                    XIBCompilerTests.xib(XIBCompilerTests.view()).replacingOccurrences(of: "<dependencies>", with: "<dependencies>\n<development version=\"5100\" identifier=\"xcode\"/>")] {
            #expect(try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options) == plain)
        }
    }

    /// A controller's simulated tab bar, toolbar and opaque or black navigation bar change nothing
    /// (round 112, `sb-sim-*`).
    @Test func simulatedBarsChangeNothing() throws {
        let plain = try StoryboardCompiler.compile(Data(SceneTests.storyboard(SceneTests.scene(1)).utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        #expect(plain["UIViewController-vc1-aa-aaa.nib"].map(VariationTests.digest) == "14045505a14f06410f7666e5cf1ccfdfc42f725a3aae7cdc9f9a7ce0640d5506")
        for bar in [#"<simulatedTabBarMetrics key="simulatedBottomBarMetrics"/>"#, #"<simulatedToolbarMetrics key="simulatedBottomBarMetrics" translucent="NO"/>"#,
                    #"<simulatedNavigationBarMetrics key="simulatedTopBarMetrics" barStyle="black" prompted="NO"/>"#] {
            let document = SceneTests.storyboard(SceneTests.scene(1, afterView: bar + "\n"))
            #expect(try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options) == plain)
        }
    }
}
