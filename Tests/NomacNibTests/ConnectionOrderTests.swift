import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for connections of one name from sources of different classes
/// and outlet collections of several names (`.github/scripts/nib_experiments.py` rounds 53 and 95,
/// `oc-*`): sizes and SHA-256 digests of Xcode's nibs.
@Suite struct ConnectionOrderTests {
    static func connected(_ tag: String, _ id: String, y: Double, _ connections: String, attributes: String = "") -> String {
        ConstraintTests.subview(id, (10, y, 100, 50), tag: tag, attributes: attributes)
            .replacingOccurrences(of: "</\(tag)>", with: "<connections>\n\(connections)</connections>\n</\(tag)>")
    }

    static func toOwner(_ property: String, _ number: Int, collection: Bool = false) -> String {
        let element = collection ? #"outletCollection property="\#(property)" destination="-1" collectionClass="NSMutableArray""#
            : #"outlet property="\#(property)" destination="-1""#
        return "<\(element) id=\"c\(String(format: "%02d", number))-aa-aaa\"/>\n"
    }

    static let collectionToSub2 = #"<outletCollection property="items" destination="sub-vi-ew2" collectionClass="NSMutableArray" id="c02-aa-aaa"/>"# + "\n"
    static func collections(_ names: [String], first number: Int = 1) -> String {
        names.enumerated().map { offset, name in
            #"<outletCollection property="\#(name)" destination="sub-vi-ew\#(1 + offset % 2)" collectionClass="NSMutableArray" "#
                + "id=\"c\(String(format: "%02d", number + offset))-aa-aaa\"/>\n"
        }.joined()
    }

    static let sevenNames = ["q", "b", "x", "b", "a", "m", "q", "z", "c"]
    static let ownerFirst = OutletTests.withOutlets(owner: #"<outlet property="label" destination="sub-vi-ew2" id="c01-aa-aaa"/>"# + "\n")
        .replacingOccurrences(of: #"customClass="Owner">"#, with: #"customClass="ZOwner">"#)
        .replacingOccurrences(of: #"<view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="sub-vi-ew1">"#,
                              with: #"<imageView contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="sub-vi-ew1">"#)
        .replacingOccurrences(of: "</view>\n<view", with: "<connections>\n" + #"<outlet property="label" destination="sub-vi-ew2" id="c02-aa-aaa"/>"#
                              + "\n</connections>\n</imageView>\n<view")

    static let cases: [(String, String, Int, String)] = [
        ("oc-class-view-image", ConstraintTests.constrained(connected("view", "sub-vi-ew1", y: 20, toOwner("delegate", 1))
                                                            + connected("imageView", "sub-vi-ew2", y: 120, toOwner("delegate", 2)), ""),
         1103, "6ffe82551bf5e6a7cf88c096e7e633ac87fed4e35c18d3dfdb7e1b2e4573730a"),
        ("oc-class-custom", ConstraintTests.constrained(connected("view", "sub-vi-ew1", y: 20, toOwner("delegate", 1),
                                                                  attributes: #" customClass="Aaa" customModule="T" customModuleProvider="target""#)
                                                        + connected("imageView", "sub-vi-ew2", y: 120, toOwner("delegate", 2)), ""),
         1192, "4b23ab429aa8da8364c8c058a2d226429095b7ad1db81bb3bd8e59d232608134"),
        ("oc-class-three", ConstraintTests.constrained(connected("view", "sub-vi-ew1", y: 20, toOwner("delegate", 1))
                                                       + connected("scrollView", "sub-vi-ew2", y: 120, toOwner("delegate", 2))
                                                       + connected("imageView", "sub-vi-ew3", y: 220, toOwner("delegate", 3)), ""),
         1340, "9771f77f220d8c07cd3ad0bd912367bf92a0ef028e1a2d51ecfc0f18c85c87ad"),
        ("oc-class-collections", ConstraintTests.constrained(connected("view", "sub-vi-ew1", y: 20, toOwner("others", 1, collection: true))
                                                             + connected("imageView", "sub-vi-ew2", y: 120, toOwner("others", 2, collection: true)), ""),
         1228, "9e511d16a271cdf484f8c26c95f6ae589748de1a78e8550ed659e44c7a6a7fb8"),
        ("oc-names-two-sources", OutletTests.withOutlets(owner: collectionToSub2.replacingOccurrences(of: "sub-vi-ew2", with: "sub-vi-ew1"), view: collectionToSub2),
         1296, "7e89aa98b3d28dabe5a4bf570cd6e6043b311b16919a1e0a12cd71ef3ff3dd91"),
        ("oc-class-zowner-image", ownerFirst, 1183, "e34afcb8f186a724eeeaf9bd40daacfa729990d448a66697a6f5eeb35baacc63"),
        ("oc-names", OutletTests.withOutlets(owner: collections(["zeta", "alpha"])), 1306, "91b39124a1af3a1b03ff9ec8fada4c9c674d03a069a93a4b6725761c7c0fadeb"),
        ("oc-names-seven", OutletTests.withOutlets(owner: collections(sevenNames)), 1576, "6ad55dfd263ece8793cf384058307ccbd6beb69d5cff7a9ed8a1e8f5e76e2a3e"),
        ("oc-names-root-seven", OutletTests.withOutlets(owner: "", view: collections(sevenNames, first: 11)),
         1576, "88e3f2b7625d0cf7d4b44c0500a69acb2d1db88cba5bc6a4c1b64a36203e6384"),
    ]

    /// Outlets and outlet collections of one name: placeholders first whatever their class, then by
    /// their sources' original classes (a custom class's original), then by all objects.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }

    /// Collections of several names from File's Owner and a view, whose order ibtool changes from
    /// run to run (ADR 0260): nomac writes them by name, then as those of one name, the order of
    /// one of ibtool's runs each time (`oc-mix-a`: alpha, items, zeta; `oc-mix-h`).
    @Test(arguments: [
        ("oc-mix-a", OutletTests.withOutlets(owner: collections(["zeta", "alpha"]), view: collections(["items"], first: 9)),
         1363, "ae90ef74dada53d5008220a3ad5bf8fc14a719e85e36add3a36e1cb6142d92df"),
        ("oc-mix-h", OutletTests.withOutlets(owner: collections(["pa", "pb", "pc", "pd"]), view: collections(["zz", "aa"], first: 9)),
         1517, "66e4ad544b57f8eb7e7f957f07c2d1ead190f79251a387fa4a942cd78695393c"),
    ])
    func ordersCollectionsOfSeveralSourcesByName(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
