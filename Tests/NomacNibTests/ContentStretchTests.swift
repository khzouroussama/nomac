import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for views' content stretch and table view cells'
/// `clearsContextBeforeDrawing` (`.github/scripts/nib_experiments.py` round 97): sizes and SHA-256
/// digests of Xcode's nibs.
@Suite struct ContentStretchTests {
    static func stretch(_ x: String, _ y: String, _ width: String, _ height: String) -> String {
        "<rect key=\"contentStretch\" x=\"\(x)\" y=\"\(y)\" width=\"\(width)\" height=\"\(height)\"/>\n"
    }

    static func stretched(_ rect: String, tag: String = "view", attributes: String = "", inner: String = "") -> String {
        ConstraintTests.constrained(ConstraintTests.subview(tag: tag, attributes: attributes)
            .replacingOccurrences(of: "</\(tag)>", with: "\(rect)\(inner)</\(tag)>"), "")
    }

    static let center = stretch("0.5", "0.5", "0.0", "0.0")
    static let cases: [(String, String, Int, String)] = [
        ("view-stretch", stretched(stretch("0.10000000000000001", "0.20000000000000001", "0.5", "0.69999999999999996")),
         925, "d93a32522fc7da9aea015c34c7bcc2a3c923ee6931443cf6bb03f2da2dd64c6f"),
        ("view-stretch-center", stretched(center), 925, "20a89a9ae79fc2a916279e33216a570c6a7dd87b53d259da62e6a78fbd20bb43"),
        ("view-stretch-default", stretched(stretch("0.0", "0.0", "1", "1")), 872, "f656183e6e3a29a51ff1b04554564a7464b0f95b9eeaf34c0d58556f00ab8a80"),
        ("view-stretch-x", stretched(stretch("0.25", "0.0", "1", "1")), 925, "3fe5fe0cb75842674eab994a70c528d28dca8a905c4d4ed309cb875cf9978148"),
        ("view-stretch-third", stretched(stretch("0.33333333333333331", "0.0", "0.33333333333333337", "1")),
         925, "0fdac6496c77c0024876fb4d176e5169e89c696083f39a5d4dc7be9d41a42100"),
        ("view-stretch-flags", stretched(center, attributes: #" clipsSubviews="YES" clearsContextBeforeDrawing="NO" contentMode="center" tag="3" hidden="YES""#),
         1011, "7f8d22ec7abca5c5af79bfed006604ee27708ca388552d9ce26e68bbcd455b10"),
        ("view-stretch-alpha", stretched(center, attributes: #" alpha="0.5" contentMode="center" clipsSubviews="YES""#),
         974, "7254bcd31f5bc6ff10d69005d864a4064b8f979bdb7bdadad145acdb7faf80b7"),
        ("image-view-stretch", stretched(center, tag: "imageView"), 939, "8b202075486511f4fda9cbb69a0fb405e1ffd228a2fcc67e31895d93119bd4e8"),
        ("label-stretch", stretched(center, tag: "label", attributes: #" opaque="NO" userInteractionEnabled="NO" text="Label""#,
                                    inner: #"<fontDescription key="fontDescription" type="system" pointSize="17"/>"# + "\n" + LabelTests.nilColors),
         1843, "410fbceb9d43e14c99f4475e52b4dcd485831728adc63d8259c0b25da8daa0b8"),
        ("button-stretch", stretched(center, tag: "button", attributes: #" opaque="NO" contentHorizontalAlignment="center" contentVerticalAlignment="center" "#
                                     + #"buttonType="system" lineBreakMode="middleTruncation""#, inner: #"<state key="normal" title="Go"/>"# + "\n"),
         1702, "a12e4a2d687b425b1b8ea902f219083047376b661124da00a4f2015745069a22"),
        ("cell-clears-no", CellTests.cellXIB(#" clearsContextBeforeDrawing="NO""#), 1435, "e6308353080ed162bb961ab4c0ee6b3ccc720050104d31c8533b8e3111db3450"),
        ("cell-clears-yes", CellTests.cellXIB(#" clearsContextBeforeDrawing="YES""#), 1404, "2202b4055e54fde73015034c15a0171e76508710208c5809cb0478c0666b33e0"),
        ("cell-clears-no-opaque", CellTests.cellXIB(#" clearsContextBeforeDrawing="NO" opaque="NO""#),
         1433, "c1b999dfb33b58ab6f59a9a0e9afda0ff26b71ad3a46f2ccf2ec3c04af3f89ed"),
        ("cell-clears-no-content", CellTests.cellXIB(#" clearsContextBeforeDrawing="NO""#, contentAttributes: #" clearsContextBeforeDrawing="NO""#),
         1437, "5a6a01666a87342541efb303efd920642b877fc2868aa31966756fab5a2e1c18"),
        ("cell-content-clears-no", CellTests.cellXIB("", contentAttributes: #" clearsContextBeforeDrawing="NO""#),
         1435, "7ce6e0e90a06450ffa29c190b3acdce9ccbe9e62808cc90df56384cde7c80fe5"),
        ("cell-stretch", CellTests.cellXIB(#" clearsContextBeforeDrawing="NO""#, cellExtra: stretch("0.0", "0.0", "1", "1")),
         1435, "e6308353080ed162bb961ab4c0ee6b3ccc720050104d31c8533b8e3111db3450"),
        ("cell-stretch-center", CellTests.cellXIB(#" clearsContextBeforeDrawing="NO""#, cellExtra: center),
         1488, "ef7e321ea2edf59a7e65251171a48566d159fee0b8b8f6252314c2fc626c5e94"),
    ]

    /// `UIContentStretch`, four doubles after `UIContentMode`, left out at 0, 0, 1, 1; a cell's
    /// `UIClearsContextBeforeDrawing` false where any view writes it, its content view's too.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
