import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for user-defined runtime attributes in xibs
/// (`.github/scripts/nib_experiments.py` round 39, `udra`): sizes and SHA-256 digests of Xcode's nibs.
@Suite struct RuntimeAttributeTests {
    static func attribute(_ keyPath: String, _ type: String, value: String? = nil, child: String? = nil) -> String {
        let valueAttribute = value.map { " value=\"\($0)\"" } ?? ""
        guard let child else { return "<userDefinedRuntimeAttribute type=\"\(type)\" keyPath=\"\(keyPath)\"\(valueAttribute)/>\n" }
        return "<userDefinedRuntimeAttribute type=\"\(type)\" keyPath=\"\(keyPath)\"\(valueAttribute)>\n\(child)\n</userDefinedRuntimeAttribute>\n"
    }

    static func runtime(_ attributes: String...) -> String {
        "<userDefinedRuntimeAttributes>\n" + attributes.joined() + "</userDefinedRuntimeAttributes>\n"
    }

    static func withRuntime(_ attributes: String, id: String = ConstraintTests.sub, inner: String = "") -> String {
        ConstraintTests.subview(id).replacingOccurrences(of: "</view>", with: inner + attributes + "</view>")
    }

    static func xib(_ subviews: String, resources: String = "") -> String {
        ConstraintTests.constrained(subviews, "", resources: resources)
    }

    static let radius = attribute("layer.cornerRadius", "number", child: #"<integer key="value" value="8"/>"#)
    static let width = attribute("borderWidth", "number", child: #"<real key="value" value="1.5"/>"#)
    static let masks = attribute("layer.masksToBounds", "boolean", value: "YES")
    static let nested = "<subviews>\n<view contentMode=\"scaleToFill\" id=\"nst-aa-aa1\">\n" + #"<rect key="frame" x="0" y="0" width="10" height="10"/>"# + "\n"
        + runtime(attribute("nested", "string", value: "n")) + "</view>\n</subviews>\n"
    static let symbol = #"<image name="plus" catalog="system" width="128" height="113"/>"# + "\n"

    static let cases: [(String, String, Int, String)] = [
        ("udra-integer", xib(withRuntime(runtime(radius))), 1002, "e0bd10624b0387e8f9a303750d15ce0bc700dc16231e466f27b9b2363cdbe0c4"),
        ("udra-real", xib(withRuntime(runtime(attribute("layer.cornerRadius", "number", child: #"<real key="value" value="0.5"/>"#)))),
         1009, "40e43d79b8727a18e86a5a7e17dc7fed3f0ebdca5692bea8f7f688d41c446ed7"),
        ("udra-string", xib(withRuntime(runtime(attribute("ibEnaStyle", "string", value: "title1")))),
         979, "dc3c7cf5c48ddcb750e94aaac911affac17cc853187b8483c674d852d5fd5a0c"),
        ("udra-boolean-yes", xib(withRuntime(runtime(masks))), 1003, "3c203c9638d196edec578674f162d2758f6c2ee2a3cc5d5db77d04d70730ff5b"),
        ("udra-color", xib(withRuntime(runtime(attribute("borderColor", "color", child:
            #"<color key="value" red="1" green="0.5" blue="0.25" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>"#)))),
         1108, "85f3669ca57159f9a6a99466db5f42ec15284b5a5754a24cdef92ab3ee22d114"),
        ("udra-size", xib(withRuntime(runtime(attribute("shadowOffset", "size", child: #"<size key="value" width="0.0" height="2"/>"#)))),
         1025, "1c115da587c594e9671334ae2b88d1016712f75d51191bc4fa5d38955224782f"),
        ("udra-image-symbol", xib(withRuntime(runtime(#"<userDefinedRuntimeAttribute type="image" keyPath="imageNormal" value="plus" catalog="system"/>"# + "\n")),
                                  resources: symbol), 1151, "95dc0f0ec5025569e33b1f6bc7e21d63471ae3c7b2f303119cfe6762243d810f"),
        ("udra-three-reversed", xib(withRuntime(runtime(width, masks, radius))), 1127, "f34eb7a156029d8eb5d2ae76f31a212380946ccab9150bfce06d85ded38f6fc1"),
        ("udra-siblings-nested", xib(withRuntime(runtime(attribute("first", "string", value: "a")), inner: nested)
                                     + withRuntime(runtime(attribute("second", "string", value: "b")), id: "sss-ss-ss2")),
         1242, "85ca385a45dfa76c7a8cfe2a18f6bb214383f63a167e37f3c0bd2479e447ea0b"),
        ("udra-owner", xib(withRuntime(runtime(radius))).replacingOccurrences(
            of: #"userLabel="File's Owner"/>"#, with: #"userLabel="File's Owner">"# + "\n" + runtime(attribute("title", "string", value: "Hi")) + "</placeholder>"),
         1048, "74c5b7c3aab098a6622054e4d88b8cf55419786d320b9b61edf8d4c048367162"),
        ("udra-bool-int-one", xib(withRuntime(runtime(attribute("a", "boolean", value: "YES"), attribute("b", "number", child: #"<integer key="value" value="1"/>"#),
                                                      attribute("c", "number", child: #"<real key="value" value="1"/>"#)))),
         1053, "d02a5492c8af3d945574c226dfd277bcc5d09ce3ea32253539ceb361637b4125"),
        ("udra-label-real-17", xib(LabelTests.label(extra: runtime(attribute("size", "number", child: #"<real key="value" value="17"/>"#)))),
         1898, "0333dc818497ec5565b8f0cfd70dad71da1ed48bceeee3c0d3ae4bdea335f42e"),
    ]

    /// Key-value pairs in the order of their objects in all objects, numbers shared by value whatever
    /// their types, sizes as `NSValue`s, images as placeholders.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }

    static func views(_ count: Int) -> String {
        (0..<count).map { Self.withRuntime(Self.runtime(Self.attribute("k", "string", value: String(format: "v%02d", $0))), id: String(format: "v%02d-aa-aa1", $0)) }.joined()
    }

    /// `udra-order-many-8`: pairs of several objects, some past the nib's 9th object, those objects
    /// first, ascending, then the others (B-290).
    @Test func ordersSeveralObjectsPastTheNinth() throws {
        let nib = try XIBCompiler.compile(Data(Self.xib(Self.views(8)).utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == 1827)
        #expect(VariationTests.digest(nib) == "58d551a0df09a0465f802eadddaa1b0a8e80b8f11a5bfc9ccfa0b4402ad9bfee")
    }

    /// Objects holding pairs under the nib's 9th object beside ones past its 39th, where place 3
    /// falls between 38 and 39 (`udra-order-many-40`, B-290).
    @Test func refusesObjectsUnderTheNinthBesidePastTheThirtyNinth() {
        #expect(throws: NomacError("nomac does not order the user-defined runtime attributes of several objects with one at a nib's first three places, "
                                   + "or ones under its 9th beside ones past its 39th, yet (BACKLOG B-290)", path: "/tmp/View.xib")) {
            try XIBCompiler.compile(Data(Self.xib(Self.views(40)).utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        }
    }
}
