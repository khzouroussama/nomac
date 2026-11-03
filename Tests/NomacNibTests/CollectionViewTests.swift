import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for collection views in xibs (`.github/scripts/nib_experiments.py`
/// round 45, `collection`): sizes and SHA-256 digests of Xcode's nibs.
@Suite struct CollectionViewTests {
    static let attributes = #"clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="scaleToFill" dataMode="none""#

    static func flow(_ attributes: String = #"minimumLineSpacing="10" minimumInteritemSpacing="10""#, item: String = #"width="128" height="128""#,
                     header: String = #"width="0.0" height="0.0""#, footer: String = #"width="0.0" height="0.0""#,
                     inset: String = #"minX="0.0" minY="0.0" maxX="0.0" maxY="0.0""#) -> String {
        "<collectionViewFlowLayout key=\"collectionViewLayout\" \(attributes) id=\"flw-aa-aa1\">\n<size key=\"itemSize\" \(item)/>\n"
            + "<size key=\"headerReferenceSize\" \(header)/>\n<size key=\"footerReferenceSize\" \(footer)/>\n<inset key=\"sectionInset\" \(inset)/>\n"
            + "</collectionViewFlowLayout>\n"
    }

    static func collectionXIB(_ attributes: String = attributes, layout: String = flow(), extra: String = "") -> String {
        ConstraintTests.constrained("<collectionView \(attributes) translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"cvw-aa-aa1\">\n"
                                    + #"<rect key="frame" x="0" y="0" width="393" height="852"/>"# + "\n\(extra)\(layout)</collectionView>\n", "")
    }

    static let cases: [(String, String, Int, String)] = [
        ("collection", collectionXIB(), 1216, "4f606ae2da3781871d973a6ec136be99625fca3bc700e76135d25aeefd2605ad"),
        ("collection-background", collectionXIB(extra: XIBCompilerTests.gray("1", "1") + "\n"), 1399, "b8d4e544705ab7513fac7a411a18034a3f0dfe6e9d2776e687d5ddd846a6e110"),
        ("collection-custom-layout", collectionXIB(layout: #"<collectionViewLayout key="collectionViewLayout" id="lay-aa-aa1" customClass="GridLayout" customModule="T" customModuleProvider="target"/>"# + "\n"),
         1269, "32a869929d70bea06e3f54b9d66f9ba378ac3dff1812c6e02dc79658053a83e3"),
        ("collection-flow-all", collectionXIB(layout: flow(#"minimumLineSpacing="5" minimumInteritemSpacing="6" scrollDirection="horizontal" automaticEstimatedItemSize="YES" sectionInsetReference="safeArea""#,
                                                          header: #"width="50" height="50""#, footer: #"width="20" height="30""#, inset: #"minX="1" minY="2" maxX="3" maxY="4""#)),
         1646, "f3a76b0eb9bbb1fab5a0b0c11692b3caf7f97c524d94598ea5fc9aad18598f8e"),
        ("collection-flow-item-50", collectionXIB(layout: flow(item: #"width="50" height="50""#)), 1185, "83f02604e53e8d681cf669fb98fb2d85b4ce9a8b745ba16e71eaa4cfed05d3e1"),
        ("collection-prefetchingEnabled-NO", collectionXIB(attributes + #" prefetchingEnabled="NO""#), 1216, "55a9387058c62eead28c63db7a6c1d66326600f3067e97081af83de168385503"),
    ]

    /// The scroll view's keys, the layout (a flow layout's values that differ from its defaults, a
    /// custom layout's class), multiple selection and prefetching; a white background named
    /// `systemBackgroundColor`; automatic estimated sizes as a runtime attribute.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
