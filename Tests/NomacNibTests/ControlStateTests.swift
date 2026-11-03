import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for disabled segmented controls and hidden activity indicators
/// (`.github/scripts/nib_experiments.py` round 67, `segmented-control-disabled*`, `activity-hidden-*`):
/// sizes and SHA-256 digests of Xcode's nibs.
@Suite struct ControlStateTests {
    static let segments = "<segments>\n<segment title=\"First\"/>\n<segment title=\"Second\"/>\n</segments>\n"

    static func activity(stops: String) -> String {
        ConstraintTests.constrained("<activityIndicatorView opaque=\"NO\" contentMode=\"scaleToFill\" style=\"medium\" hidesWhenStopped=\"\(stops)\" animating=\"NO\" "
                                    + "hidden=\"YES\" translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"ctl-aa-aa1\">\n"
                                    + #"<rect key="frame" x="10" y="24" width="20" height="20"/>"# + "\n</activityIndicatorView>\n", "")
    }

    static let cases: [(String, String, Int, String)] = [
        ("segmented-control-disabled", ControlTests.controlXIB("segmentedControl", ControlTests.segmented + #" enabled="NO" selectedSegmentIndex="0""#, segments,
                                                               size: (121, 32)), 1414, "609e210fccde2871d57f1aeb8bf6e7d411b821e4f7996253e93ec9a4a1f6c464"),
        ("segmented-control-disabled-alpha", ControlTests.controlXIB("segmentedControl", ControlTests.segmented
                                                                         + #" enabled="NO" alpha="0.80000000000000004" selectedSegmentIndex="0""#, segments, size: (121, 32)),
         1414, "609e210fccde2871d57f1aeb8bf6e7d411b821e4f7996253e93ec9a4a1f6c464"),
        ("activity-hidden-stops-NO-animating-NO", activity(stops: "NO"), 1364, "e710bc1a391d7714d6f2ce6b9709a1fac891dfd755a3ab9cb93594f0483a5797"),
        ("activity-hidden-stops-YES-animating-NO", activity(stops: "YES"), 1354, "b34db1f071f1092e57175f634d76a9ffadd99b4fa7ef342c6c6570d2c53d8bf1"),
    ]

    /// A disabled segmented control's alpha 0.5 whatever its own; a stopped activity indicator that
    /// does not hide when stopped is not hidden.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
