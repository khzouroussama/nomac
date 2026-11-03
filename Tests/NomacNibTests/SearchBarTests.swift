import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for search bars (`.github/scripts/nib_experiments.py` round 93,
/// `search-bar*`): sizes and SHA-256 digests of Xcode's nibs.
@Suite struct SearchBarTests {
    static func searchBar(_ attributes: String, traits: String = "") -> String {
        ConstraintTests.constrained("<searchBar contentMode=\"redraw\"\(attributes) translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"sbr-aa-aa1\">\n"
                                    + "<rect key=\"frame\" x=\"0.0\" y=\"40\" width=\"393\" height=\"56\"/>\n<textInputTraits key=\"textInputTraits\"\(traits)/>\n</searchBar>\n", "")
    }

    static let cases: [(String, String, Int, String)] = [
        ("search-bar-placeholder", searchBar(" searchBarStyle=\"minimal\" placeholder=\"Search for a place or address\""), 1127,
         "16b332cd1439de5f298b9273f791519386a245fc0f37d601895f45066cb3e3bd"),
        ("search-bar-traits", searchBar(" placeholder=\"Niagara Falls\"", traits: " autocorrectionType=\"no\""), 1115,
         "55746d5512d891d1dd2249933d273c336e9a5e32eadbee50a7a5b7ee264efcff"),
        ("search-bar-opaque-hugging", searchBar(" opaque=\"NO\" horizontalHuggingPriority=\"249\" searchBarStyle=\"minimal\""), 1072,
         "703fbe3fb91b9b87000bfd2d7361824301db4dc7fcd2f987f57d5613bb1d00af"),
    ]

    /// Never opaque, its hugging always written, an empty text, its placeholder, autocorrection and
    /// the minimal style.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
