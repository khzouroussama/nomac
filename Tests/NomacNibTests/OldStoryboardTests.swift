import Foundation
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for storyboards saved by old Xcodes (`.github/scripts/
/// nib_experiments.py` rounds 62 and 63): Xcode 8's default simulated metrics, a scene's view below
/// an opaque navigation bar, Xcode 5's development version; sizes and SHA-256 digests of the view nib.
@Suite struct OldStoryboardTests {
    typealias S = StoryboardCompilerTests
    static let container = """
        <simulatedMetricsContainer key="defaultSimulatedMetrics">
        <simulatedStatusBarMetrics key="statusBar"/>
        <simulatedOrientationMetrics key="orientation"/>
        <simulatedScreenMetrics key="destination" type="retina4_7.fullscreen"/>
        </simulatedMetricsContainer>

        """
    static let opaqueBar = #"<simulatedNavigationBarMetrics key="simulatedTopBarMetrics" translucent="NO" prompted="NO"/>"# + "\n"

    static func document(device: Bool, y: Int, size: (Int, Int)) -> String {
        let scene = S.scene(frame: "width=\"\(size.0)\" height=\"\(size.1)\"").replacingOccurrences(of: #"x="0.0" y="0.0" width"#, with: "x=\"0.0\" y=\"\(y)\" width")
            .replacingOccurrences(of: "</viewController>", with: opaqueBar + "</viewController>")
        let document = device ? S.storyboard(scene) : S.storyboard(scene, device: nil)
        return document.replacingOccurrences(of: "</document>", with: container + "</document>")
    }

    static let cases: [(String, String, Int, String)] = [
        ("sb-metrics-retina4_7.fullscreen", S.storyboard(S.scene(frame: #"width="375" height="667""#), device: nil)
            .replacingOccurrences(of: "</document>", with: container + "</document>"), 1701, "7b4ff2f71fef9e5a87ecc4c6441416a814e12247785cb3ab0737ac8dfcee1444"),
        ("sb-view-at-64-603", document(device: false, y: 64, size: (375, 603)), 1701, "735381ea2274625ca91ba7a31b92fc1388131944a194f3e1324c3b248ed9fd58"),
        ("sb-view-at-64-device", document(device: true, y: 64, size: (393, 788)), 1701, "ac39947d625b3a1cb049240ae759c5f6477b896cbaa8bcc3c1b9450acebfd70c"),
    ]

    /// The metrics container changes nothing; a scene's view keeps its origin, a device resizing it.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, document: String, size: Int, digest: String) throws {
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: S.options)
        let data = try #require(compiled["BYZ-38-t0r-view-8bC-Xf-vdC.nib"], "\(name)")
        #expect(data.count == size, "\(name)")
        #expect(VariationTests.digest(data) == digest, "\(name)")
    }
}
