import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for constraints' identifiers beside other strings of the same
/// text (`.github/scripts/nib_experiments.py` round 98, `cid-*`): sizes and SHA-256 digests of
/// Xcode's nibs.
@Suite struct ConstraintIdentifierTests {
    static let sub = "sub-vi-ew1"

    static func pinned(owner: String = "", identifiers: [String?] = ["pin", nil, nil, nil], subAttributes: String = "", subExtra: String = "",
                       extraSubviews: String = "") -> String {
        let pairs = [("leading", "leading"), ("trailing", "trailing"), ("top", "top"), ("bottom", "bottom")]
        let constraints = pairs.enumerated().map { k, pair in
            ConstraintTests.constraint(k, k % 2 == 0 ? sub : ConstraintTests.root, pair.0, k % 2 == 0 ? ConstraintTests.root : sub, pair.1,
                                       identifiers[k].map { " identifier=\"\($0)\"" } ?? "")
        }.joined()
        let subview = ConstraintTests.subview(sub, attributes: subAttributes).replacingOccurrences(of: "</view>", with: "\(subExtra)</view>")
        return ConstraintTests.constrained(subview + extraSubviews, constraints)
            .replacingOccurrences(of: "<view contentMode=\"scaleToFill\" id=\"\(ConstraintTests.root)\">",
                                  with: "<view contentMode=\"scaleToFill\" customClass=\"Root\" id=\"\(ConstraintTests.root)\">")
            .replacingOccurrences(of: #"<placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File's Owner"/>"#,
                                  with: #"<placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File's Owner" customClass="Owner""#
                                    + (owner.isEmpty ? "/>" : ">\n<connections>\n\(owner)</connections>\n</placeholder>"))
    }

    static func outlet(_ property: String, _ destination: String = sub, number: Int = 1) -> String {
        "<outlet property=\"\(property)\" destination=\"\(destination)\" id=\"o\(String(format: "%02d", number))-aa-aaa\"/>\n"
    }

    static let label = #"<label opaque="NO" userInteractionEnabled="NO" contentMode="left" text="Label" translatesAutoresizingMaskIntoConstraints="NO" id="lbl-aa-aa1">"#
        + "\n" + #"<rect key="frame" x="10" y="200" width="42" height="21"/>"# + "\n"
        + #"<fontDescription key="fontDescription" type="system" pointSize="17"/>"# + "\n" + LabelTests.nilColors + "</label>\n"

    static let cases: [(String, String, Int, String)] = [
        ("cid-plain", pinned(), 1387, "8608f3f15c60e4c7013dd2034e60fed3c2a5de0fbb7e33d1fb570a897362d159"),
        ("cid-outlet", pinned(owner: outlet("pin")), 1478, "9720370131527d9b360d316603364938d99323a7663695e6f9b6da282e2f217e"),
        ("cid-outlet-other", pinned(owner: outlet("box")), 1487, "5da26e92329386908d83b3134bd47fc3de97dc26ca828d391bb49c3ad133b401"),
        ("cid-two-same", pinned(identifiers: ["pin", nil, "pin", nil]), 1393, "510f18f0ffc934e065c5fbd5d8f457cd44470c02a95a0c15208486553bd95272"),
        ("cid-two-same-outlet", pinned(owner: outlet("pin"), identifiers: ["pin", nil, "pin", nil]),
         1484, "ac9bc1d4d066676bfe025bcf24f1fe93ba4ccde17fba836c905296a31daed294"),
        ("cid-two-differ", pinned(identifiers: ["pin", nil, "pan", nil]), 1402, "3d8b1441d7d4b68be25b5f6217520f67e5ae89617ff2c443ac43a3c579a32915"),
        ("cid-restoration", pinned(subAttributes: #" restorationIdentifier="pin""#), 1417, "447a87043044e965e49687152a3416849995a4f54c619076a31924eac79a4532"),
        ("cid-a11y", pinned(subExtra: #"<accessibility key="accessibilityConfiguration" identifier="pin"/>"# + "\n"),
         1497, "1ccb92357a945b47055eb3e0f35a295aa62d3aea56079a466e79ef39707e15c8"),
        ("cid-label", pinned(owner: outlet("pin"), identifiers: ["Label", nil, nil, nil], extraSubviews: label),
         2502, "692f2ce1039799dccb60acd136c2eb437800ccc05a5de6c10342546d6a56cdf1"),
    ]

    static let viewOutlet = outlet("view", ConstraintTests.root, number: 2)
    static let withoutID: [(String, String)] = [
        ("cid-outlet-no-id-two", pinned(owner: outlet("box").replacingOccurrences(of: #" id="o01-aa-aaa""#, with: "") + viewOutlet)),
        ("conn-no-id-collection", pinned(owner: #"<outletCollection property="boxes" destination="sub-vi-ew1" collectionClass="NSMutableArray"/>"# + "\n" + viewOutlet)),
        ("conn-no-id-view-outlet", pinned(owner: viewOutlet, subExtra: "<connections>\n" + #"<outlet property="owner" destination="-1"/>"# + "\n</connections>\n")),
    ]

    /// ibtool drops connections without an id, whatever their kind or source: each nib is the one
    /// of File's Owner's `view` outlet alone.
    @Test(arguments: withoutID)
    func dropsConnectionsWithoutID(name: String, xib: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == 1488, "\(name)")
        #expect(VariationTests.digest(nib) == "fd4a5ab22fb6f89a4069b76e867d9352211c292fb4fbff1310e3c616ff1a8bfe", "\(name)")
    }

    /// A constraint's identifier is the document's one string of its text, shared with outlets'
    /// labels, other constraints' identifiers, restoration and accessibility identifiers and texts.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
