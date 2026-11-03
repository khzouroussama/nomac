import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for top-level views without freeform simulated metrics
/// (`.github/scripts/nib_experiments.py` round 99, `tl-*`): sizes and SHA-256 digests of Xcode's
/// nibs.
@Suite struct TopLevelSizeTests {
    static let small = #"x="0" y="0" width="320" height="100""#
    static let freeform = #"<freeformSimulatedSizeMetrics key="simulatedDestinationMetrics"/>"# + "\n"

    static func options(_ deployment: String, _ devices: [String] = ["iphone"]) -> XIBCompiler.Options {
        XIBCompiler.Options(module: "T", minimumDeploymentTarget: deployment, targetDevices: devices)
    }

    static func plain(frame: String = small, extra: String = "", subviews: [String] = []) -> String {
        XIBCompilerTests.xib(XIBCompilerTests.view(frame: frame, subviews: subviews).replacingOccurrences(of: "<point key", with: "\(extra)<point key"))
    }

    static let sub = XIBCompilerTests.view(frame: #"x="10" y="10" width="50" height="50""#, id: "sub-vi-ew1")
        .replacingOccurrences(of: #"<point key="canvasLocation" x="0" y="0"/>"# + "\n", with: "")

    static let cases: [(String, String, XIBCompiler.Options, Int, String)] = [
        ("tl-plain", plain(), options("27.0"), 748, "982f7f29471fcffdb97b03c82cfcf23eef03b2d6900a326c299c915f4f37d466"),
        ("tl-iphone-17", plain(), options("17.0"), 748, "982f7f29471fcffdb97b03c82cfcf23eef03b2d6900a326c299c915f4f37d466"),
        ("tl-iphone-16", plain(), options("16.0"), 748, "98a706d2bd8bfb27e933b998222fcc76e85f3dfb2c82172f1feb9fd6f47919f9"),
        ("tl-iphone-15", plain(), options("15.0"), 748, "98a706d2bd8bfb27e933b998222fcc76e85f3dfb2c82172f1feb9fd6f47919f9"),
        ("tl-freeform-both-15", plain(extra: freeform), options("15.0", ["iphone", "ipad"]),
         748, "982f7f29471fcffdb97b03c82cfcf23eef03b2d6900a326c299c915f4f37d466"),
        ("tl-origin-both-15", plain(frame: #"x="10" y="20" width="320" height="100""#), options("15.0", ["iphone", "ipad"]),
         748, "2731443426666b3b5c61453f62079e81e9a40b6855d847a49826bd3440d8dfc2"),
        ("tl-retina4_7-both-15", plain().replacingOccurrences(of: #"<device id="retina6_12""#, with: #"<device id="retina4_7""#),
         options("15.0", ["iphone", "ipad"]), 748, "6cf7d27c560f631ff3d0536ab607438d71941469a4b035fd8159f98f485f1671"),
        ("tl-landscape-15", plain().replacingOccurrences(of: #"<device id="retina6_12" orientation="portrait""#, with: #"<device id="retina6_12" orientation="landscape""#),
         options("15.0"), 748, "9cb1176823823f1513855bbd8cba01914e80bce1cb885ecc3b7f5d7196aa9444"),
        ("tl-subview-15", plain(subviews: [sub]), options("15.0"), 872, "65c90e02831605176c8e0d53ed03036b2fbdcd3d7a365e2105f361ad8d19c7a5"),
    ]

    /// Under iOS 17, the device's size in its orientation, keeping the origin, subviews autoresized;
    /// from 17 on, or with freeform metrics, the document's frame.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, options: XIBCompiler.Options, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
