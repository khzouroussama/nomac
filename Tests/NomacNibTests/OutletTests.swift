import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What `ibtool --compile` (Xcode 27.0) writes for outlets and design-time settings
/// (`.github/scripts/nib_experiments.py` rounds 16 and 17): sizes and SHA-256 digests of Xcode's
/// nibs.
@Suite struct OutletTests {
    static let root = ConstraintTests.root

    static func outlet(_ property: String, _ destination: String, _ number: Int) -> String {
        "<outlet property=\"\(property)\" destination=\"\(destination)\" id=\"o\(String(format: "%02d", number))-aa-aaa\"/>\n"
    }

    /// File's Owner of class `Owner` with `owner` outlets, a root view (of class `Root` unless
    /// `viewClass` is empty) with `view` outlets, and two subviews.
    static func withOutlets(owner: String, view: String = "", viewClass: String = #" customClass="Root""#) -> String {
        let subviews = (1...2).map { ConstraintTests.subview("sub-vi-ew\($0)", (10, 20 + 100 * Double($0), 100, 50)) }.joined()
        var document = ConstraintTests.constrained(subviews, "")
            .replacingOccurrences(of: "<view contentMode=\"scaleToFill\" id=\"\(root)\">", with: "<view contentMode=\"scaleToFill\"\(viewClass) id=\"\(root)\">")
        if !view.isEmpty {
            document = document.replacingOccurrences(of: #"<point key="canvasLocation""#, with: "<connections>\n\(view)</connections>\n" + #"<point key="canvasLocation""#)
        }
        let placeholder = #"<placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File's Owner"/>"#
        let ownerElement = #"<placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File's Owner" customClass="Owner""#
            + (owner.isEmpty ? "/>" : ">\n<connections>\n\(owner)</connections>\n</placeholder>")
        return document.replacingOccurrences(of: placeholder, with: ownerElement)
    }

    static func withInnerOutlets(_ outlets: String, view: String = "") -> String {
        withOutlets(owner: "", view: view, viewClass: view.isEmpty ? "" : #" customClass="Root""#)
            .replacingOccurrences(of: #"translatesAutoresizingMaskIntoConstraints="NO" id="sub-vi-ew1">"#,
                                  with: #"customClass="Inner" translatesAutoresizingMaskIntoConstraints="NO" id="sub-vi-ew1">"#)
            .replacingOccurrences(of: "</view>\n<view", with: "<connections>\n\(outlets)</connections>\n</view>\n<view")
    }

    static let names = ["beta", "Beta", "alpha", "_under", "a1", "A2", "a10", "a2", "view"].enumerated().map { index, name in
        outlet(name, index % 2 == 1 ? "sub-vi-ew1" : "sub-vi-ew2", index)
    }.joined()

    static let cases: [(String, String, Int, String)] = [
        ("outlet-view", withOutlets(owner: outlet("view", root, 0), viewClass: ""), 1058, "d25b4f1adadf01d8ab9cd64d58b23ddb15aa4dfde9086a3088959425e5d32351"),
        ("outlet-names", withOutlets(owner: names, viewClass: ""), 1350, "43eb2df8aaab6ce7279bf7834829fc058cdb972d5d0303446107d079efd4cde2"),
        ("outlet-from-both", withOutlets(owner: outlet("view", root, 0) + outlet("label", "sub-vi-ew1", 1),
                                         view: outlet("label", "sub-vi-ew2", 2) + outlet("delegate", "-1", 3)),
         1247, "b0f557344f6cdb464c98b4b97e1a95fdd5d1fa558d8cae00da386041448d5a1e"),
        ("outlet-same-name-two-views", withInnerOutlets(outlet("label", "sub-vi-ew2", 1), view: outlet("label", "sub-vi-ew2", 0)),
         1192, "744a2817f4d763bb8053a38f2bd4114071998b21e9e7a32ed5d677274e6fdc29"),
        ("outlet-to-first-responder", withOutlets(owner: "", view: outlet("responder", "-2", 0)),
         1146, "31e6a2f0890a8a53217b5fba82375b5f94fa61aaf1fe750ad9291acfd36aaae2"),
        ("outlet-subview-class", withInnerOutlets(outlet("sibling", "sub-vi-ew2", 0) + outlet("owner", "-1", 1)),
         1183, "61a598684dbc75f6fc1db471bb61c4f1e51123d0bfe1165ec4b297afcace0452"),
        ("outlet-collection", withOutlets(owner: outlet("view", root, 0)
            + #"<outletCollection property="views" destination="sub-vi-ew1" collectionClass="NSMutableArray" id="o01-aa-aaa"/>"# + "\n"
            + #"<outletCollection property="views" destination="sub-vi-ew2" collectionClass="NSMutableArray" id="o02-aa-aaa"/>"# + "\n", viewClass: ""),
         1238, "4126e1a84cd3c3698418b0a09d484b8adbc43524befb57a03ff16cee7831ee0c"),
        ("view-clears-no", XIBCompilerTests.xib(XIBCompilerTests.view(#"clearsContextBeforeDrawing="NO""#)),
         779, "70bcb597716cd9474c4556b9a6e30dc77bfc1191631a132ba8f29cf20eec74b2"),
        ("subview-clears-no", ConstraintTests.constrained(ConstraintTests.subview(attributes: #" clearsContextBeforeDrawing="NO""#), ""),
         903, "53d50a58767842d31ac0b77e9989f847da2dfe0ddad8c5108a1595644bf52e49"),
        ("view-freeform", XIBCompilerTests.xib(XIBCompilerTests.view(color: #"<freeformSimulatedSizeMetrics key="simulatedDestinationMetrics"/>"#
            + "\n" + #"<nil key="simulatedTopBarMetrics"/>"#)), 748, "98a706d2bd8bfb27e933b998222fcc76e85f3dfb2c82172f1feb9fd6f47919f9"),
    ]

    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/\(name)/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(SHA256.digest(Array(nib)).map { String(format: "%02x", $0) }.joined() == digest, "\(name)")
    }

    /// A controller's outlets come from `UpstreamPlaceholder-1`, which its nib's external objects
    /// name (`sb-controller-outlets`); a freeform size keeps the scene's view at it whatever the
    /// device or deployment target (`sb-freeform`, `sb-freeform-no-device`).
    static let subview = StoryboardCompilerTests.subview(#"flexibleMaxX="YES" flexibleMaxY="YES""#)
    static let controllerOutlets = "<connections>\n" + outlet("titleLabel", "sub-vi-ew1", 0) + outlet("button", "sub-vi-ew1", 1) + "</connections>\n"
    static let freeform = #"<freeformSimulatedSizeMetrics key="simulatedDestinationMetrics"/>"# + "\n" + #"<size key="freeformSize" width="320" height="500"/>"#
    static func controller(_ children: String, frame: String = #"width="393" height="852""#, device: Bool = true) -> String {
        let document = device ? StoryboardCompilerTests.storyboard(StoryboardCompilerTests.scene(viewChildren: subview, frame: frame))
            : StoryboardCompilerTests.storyboard(StoryboardCompilerTests.scene(viewChildren: subview, frame: frame), device: nil)
        return document.replacingOccurrences(of: "</view>\n                </viewController>", with: "</view>\n\(children)\n</viewController>")
    }

    static let storyboardCases: [(String, String, String, [(String, Int, String)])] = [
        ("sb-controller-outlets", "27.0", controller(controllerOutlets).replacingOccurrences(
            of: #"<viewController id="BYZ-38-t0r""#, with: #"<viewController id="BYZ-38-t0r" customClass="Controller" customModule="T" customModuleProvider="target""#),
         [("BYZ-38-t0r-view-8bC-Xf-vdC.nib", 1924, "dcd847099065bf2b13fa1c0ae966974cf579dd0f5109c888f14242d996794687"),
          ("UIViewController-BYZ-38-t0r.nib", 987, "bca997c70a997ea11e18b0e11347f97ea1007682889be9b5291fee5ef71e7681")]),
        ("sb-freeform", "27.0", controller(freeform, frame: #"width="320" height="500""#),
         [("BYZ-38-t0r-view-8bC-Xf-vdC.nib", 1789, "7bed6f27d66da5a07da0e0822ca317a20f91c6851ec2a0e8dc2e3beb0dc720e8"), StoryboardCompilerTests.controller]),
        ("sb-freeform-no-device", "15.0", controller(freeform, frame: #"width="320" height="500""#, device: false),
         [("BYZ-38-t0r-view-8bC-Xf-vdC.nib", 1789, "7bed6f27d66da5a07da0e0822ca317a20f91c6851ec2a0e8dc2e3beb0dc720e8"), StoryboardCompilerTests.controller]),
        ("sb-simulated-nils", "27.0", controller(#"<nil key="simulatedTopBarMetrics"/>"# + "\n" + #"<nil key="simulatedStatusBarMetrics"/>"#),
         [("BYZ-38-t0r-view-8bC-Xf-vdC.nib", 1789, "8454f2295b584cae1dc95e035042943ef4849f097ac88920e5fe677e6248c0ba"), StoryboardCompilerTests.controller]),
    ]

    @Test(arguments: storyboardCases)
    func compilesStoryboardsAsXcode(name: String, deployment: String, document: String, files: [(String, Int, String)]) throws {
        let options = XIBCompiler.Options(module: "T", minimumDeploymentTarget: deployment, targetDevices: ["iphone"])
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/\(name)/Main.storyboard", options: options)
        for (file, size, digest) in files {
            let data = try #require(compiled[file], "\(name) \(file)")
            #expect(data.count == size, "\(name) \(file)")
            #expect(SHA256.digest(Array(data)).map { String(format: "%02x", $0) }.joined() == digest, "\(name) \(file)")
        }
    }
}
