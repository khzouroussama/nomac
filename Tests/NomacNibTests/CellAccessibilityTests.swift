import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for the accessibility of table view cells' content views, and of
/// prototype cells in storyboards (`.github/scripts/nib_experiments.py` round 113): sizes and SHA-256
/// digests of Xcode's nibs.
@Suite struct CellAccessibilityTests {
    typealias T = TableViewControllerTests
    static let row = #"<accessibility key="accessibilityConfiguration" label="Row" identifier="row">"# + "\n"
        + #"<bool key="isElement" value="YES"/>"# + "\n</accessibility>\n"
    static let content = #"<accessibility key="accessibilityConfiguration" identifier="content"/>"# + "\n"

    static let xibCases: [(String, String, Int, String)] = [
        ("cell-content-a11y", CellTests.cellXIB("", content: row), 1617, "fd826b35fd565fbb20436e45158a15d53a1e12ba0f0e5a16990ccb697067a285"),
        ("cell-content-a11y-id", CellTests.cellXIB("", content: content), 1527, "178f294586e9bee3bf41f1336ff43e92ae6a96603f46fea84ab805ace2a7b335"),
        ("cell-both-a11y", CellTests.cellXIB("", content: content, cellExtra: row), 1651, "4c5797730be92fb4879dee0133a1c210a53b47e17f0df0dc71a57017c3b972d1"),
    ]

    /// A content view's accessibility configuration as any view's, beside its cell's.
    @Test(arguments: xibCases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }

    static let storyboardCases: [(String, String, Int, String)] = [
        ("sb-cell-a11y", T.storyboard(initial: "tvc-aa-aaa", T.scene(T.prototypes(T.cell(1).replacingOccurrences(of: "</tableViewCell>", with: row + "</tableViewCell>")))),
         3242, "5003bce8da3e627e2e9903f4ce1b2127d1d4b98842e6a73cd63aae75af3956da"),
        ("sb-cell-content-a11y", T.storyboard(initial: "tvc-aa-aaa", T.scene(T.prototypes(T.cell(1, contentSubviews: row)))),
         3242, "ec994345f8746ea9d16d41f8ec45262c9645c2e2a789803faae5f02b24eb60c0"),
    ]

    /// A prototype cell's nested nib keeps its accessibility configurations.
    @Test(arguments: storyboardCases)
    func compilesPrototypesAsXcode(name: String, document: String, size: Int, digest: String) throws {
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        let nib = try #require(compiled["tvc-aa-aaa-view-tbv-aa-aaa.nib"], "\(name)")
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
