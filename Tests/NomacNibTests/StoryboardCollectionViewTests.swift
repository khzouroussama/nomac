import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for collection views in storyboards (`.github/scripts/nib_experiments.py`
/// round 48, `sb_collection`): sizes and SHA-256 digests of Xcode's view nibs.
@Suite struct StoryboardCollectionViewTests {
    static func cell(_ id: String, _ reuse: String, x: Int = 0) -> String {
        "<collectionViewCell opaque=\"NO\" clipsSubviews=\"YES\" multipleTouchEnabled=\"YES\" contentMode=\"center\" reuseIdentifier=\"\(reuse)\" id=\"\(id)\">\n"
            + "<rect key=\"frame\" x=\"\(x)\" y=\"0.0\" width=\"128\" height=\"128\"/>\n"
            + #"<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>"# + "\n"
            + "<view key=\"contentView\" opaque=\"NO\" clipsSubviews=\"YES\" multipleTouchEnabled=\"YES\" contentMode=\"center\">\n"
            + #"<rect key="frame" x="0.0" y="0.0" width="128" height="128"/>"# + "\n" + #"<autoresizingMask key="autoresizingMask"/>"# + "\n</view>\n</collectionViewCell>\n"
    }

    static func document(_ cells: String) -> String {
        let collection = "<collectionView clipsSubviews=\"YES\" multipleTouchEnabled=\"YES\" contentMode=\"scaleToFill\" dataMode=\"prototypes\" "
            + "translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"cvw-aa-aa1\">\n" + #"<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>"# + "\n"
            + CollectionViewTests.flow() + cells + "</collectionView>\n"
        return StoryboardCompilerTests.storyboard(StoryboardCompilerTests.scene(viewChildren: "<subviews>\n\(collection)</subviews>\n"))
    }

    static let cases: [(String, String, Int, String)] = [
        ("sb-collection-empty-cells", document("<cells/>\n"), 2148, "607f3dce34c1752239091ccd521db0d740a56f8c6aac75a37c6c86d30feb2d1d"),
        ("sb-collection-two-cells", document("<cells>\n" + cell("cel-aa-aa1", "Second") + cell("cel-aa-aa2", "First", x: 138) + "</cells>\n"),
         4559, "e4d68583ecb221d2e4ec168a69638047a340e8b0f313436ab918d423157264f5"),
    ]

    /// A nil delegate for prototypes; prototype cells as nested nibs by reuse identifier, alphabetical,
    /// without the generated constraints of xib cells.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, document: String, size: Int, digest: String) throws {
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        let data = try #require(compiled["BYZ-38-t0r-view-8bC-Xf-vdC.nib"], "\(name)")
        #expect(data.count == size, "\(name)")
        #expect(VariationTests.digest(data) == digest, "\(name)")
    }
}
