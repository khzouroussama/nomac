import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for table view controllers' refresh controls
/// (`.github/scripts/nib_experiments.py` round 109, `sb-tvc-refresh*`): sizes and SHA-256 digests of
/// Xcode's view nibs.
@Suite struct RefreshControlTests {
    typealias T = TableViewControllerTests

    static func refresh(_ attributes: String = "", enabled: Bool = false, action: Bool = false) -> String {
        "<refreshControl key=\"refreshControl\" opaque=\"NO\" multipleTouchEnabled=\"YES\" contentMode=\"center\"\(attributes)\(enabled ? "" : #" enabled="NO""#) "
            + #"contentHorizontalAlignment="center" contentVerticalAlignment="center" id="rfc-aa-aa1">"# + "\n" + #"<autoresizingMask key="autoresizingMask"/>"# + "\n"
            + (action ? "<connections>\n" + #"<action selector="refresh:" destination="tvc-aa-aaa" eventType="valueChanged" id="rfa-aa-aa1"/>"# + "\n</connections>\n" : "")
            + "</refreshControl>\n"
    }

    static func document(_ refresh: String) -> String {
        T.storyboard(initial: "tvc-aa-aaa", T.scene(T.prototypes(T.cell(1)), afterView: refresh))
    }

    static let viewNib = "tvc-aa-aaa-view-tbv-aa-aaa.nib"
    static let cases: [(String, String, Int, String)] = [
        ("sb-tvc-refresh", document(refresh()), 3225, "4da6020e6c584bf6afdc8239023664f2f57018189e3129432033f1cf10193d05"),
        ("sb-tvc-refresh-action", document(refresh(action: true)), 3309, "834fa476e16a946c8ab49ddf2d86a17a67ffd399bba9a405cc82798268837ba5"),
        ("sb-tvc-refresh-enabled", document(refresh(enabled: true)), 3212, "e51685c33f388d87da4469de768ac606ce4b5d633c3dc15d49aecd359c37292d"),
        ("sb-tvc-refresh-margins", document(refresh(#" insetsLayoutMarginsFromSafeArea="NO""#)), 3266, "3a60e8dc9bb166c1fc5e071fef130ad59dd9933febb67e1564cb4a6084827462"),
    ]

    /// The table view's `UIRefreshControl` after its bounce, a `UIRefreshControl` of IB's 1000 x 1000
    /// frame, disabled or not, of style 2, its action an event connection to the controller.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, document: String, size: Int, digest: String) throws {
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        let nib = try #require(compiled[Self.viewNib], "\(name)")
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
