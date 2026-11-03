import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for activity indicators, segmented controls, progress views,
/// page controls and sliders in xibs (`.github/scripts/nib_experiments.py` round 36, `control`):
/// sizes and SHA-256 digests of Xcode's nibs.
@Suite struct ControlTests {
    static let activity = #"opaque="NO" contentMode="scaleToFill" horizontalHuggingPriority="750" verticalHuggingPriority="750" style="medium""#
    static let segmented = #"opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="left" contentVerticalAlignment="top" segmentControlStyle="plain""#
    static let progress = #"opaque="NO" contentMode="scaleToFill" verticalHuggingPriority="750" progress="0.5""#
    static let page = #"opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" numberOfPages="3""#
    static let slider = #"opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center""#

    static func controlXIB(_ tag: String, _ attributes: String, _ children: String = "", size: (Double, Double), resources: String = "") -> String {
        ConstraintTests.constrained("<\(tag) \(attributes) translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"ctl-aa-aa1\">\n"
                                    + "<rect key=\"frame\" x=\"20\" y=\"40\" width=\"\(size.0)\" height=\"\(size.1)\"/>\n\(children)</\(tag)>\n", "",
                                    resources: resources)
    }

    static func color(_ key: String, _ white: String) -> String {
        XIBCompilerTests.gray(white, "1").replacingOccurrences(of: "backgroundColor", with: key) + "\n"
    }

    static func rgb(_ key: String, _ components: String) -> String {
        "<color key=\"\(key)\" \(components) colorSpace=\"custom\" customColorSpace=\"sRGB\"/>\n"
    }

    static func segments(_ count: Int) -> String {
        "<segments>\n" + (0..<count).map { "<segment title=\"S\($0)\"/>\n" }.joined() + "</segments>\n"
    }

    static let orange = #"red="1" green="0.5" blue="0.25" alpha="1""#
    static let blue = #"red="0.2" green="0.4" blue="0.6" alpha="1""#
    static let cases: [(String, String, Int, String)] = [
        ("activity", controlXIB("activityIndicatorView", activity, size: (20, 20)), 1313, "9cd145975fa8a1987fcc7c605ea234581f73f707ec86c9b6bd27962b4278e8cd"),
        ("activity-color", controlXIB("activityIndicatorView", activity, rgb("color", orange), size: (20, 20)),
         1206, "2f60d3b7194adcf1c3955d540e4ca6acad8a0846982b622ee54fe10d833b636f"),
        ("activity-animating-shows", controlXIB("activityIndicatorView", activity.replacingOccurrences(
            of: #"style="medium""#, with: #"hidesWhenStopped="NO" animating="YES" style="medium""#), size: (20, 20)),
         1327, "370117bdf7a999d998442eb8b84adaf05db1553beea9d0603061bc8eb61997e2"),
        ("activity-style-whiteLarge", controlXIB("activityIndicatorView", activity.replacingOccurrences(of: "\"medium\"", with: "\"whiteLarge\""), size: (37, 37)),
         998, "f50212866290ff3c63ec208f1e88fc210f6a3424776e2ad642342fcddac1091c"),
        ("activity-hugging", controlXIB("activityIndicatorView", activity.replacingOccurrences(of: #"horizontalHuggingPriority="750""#,
                                                                                               with: #"horizontalHuggingPriority="765""#), size: (20, 20)),
         1364, "cf91cc998639645353c88bbb8b0a55f43dd76755aff40d986c735d4fa6616283"),
        ("segmented", controlXIB("segmentedControl", segmented + #" selectedSegmentIndex="0""#,
                                 "<segments>\n<segment title=\"First\"/>\n<segment title=\"Second\"/>\n</segments>\n", size: (121, 32)),
         1387, "21c529494c8e9631271ad33b093fdb5f7c197e8cbed7a1750e787cbba8347e9f"),
        ("segmented-tints", controlXIB("segmentedControl", segmented + #" selectedSegmentIndex="0""#,
                                       "<segments>\n<segment title=\"First\"/>\n<segment title=\"Second\"/>\n</segments>\n" + rgb("tintColor", blue)
                                       + color("selectedSegmentTintColor", "1"), size: (121, 32)),
         1764, "df98c82ee253e10bcb63668b4b2fb986b608c57504d6c492a3dda7528f87c261"),
        ("segmented-positions-4-2", controlXIB("segmentedControl", segmented + #" selectedSegmentIndex="2""#, segments(4), size: (240, 32)),
         1580, "0b2f812504b354b1d014a3bca4319879bf6228671aa6bc5606c295b92b299f00"),
        ("segmented-width", controlXIB("segmentedControl", segmented + #" selectedSegmentIndex="0""#,
                                       "<segments>\n<segment title=\"First\" width=\"80\"/>\n<segment title=\"Second\"/>\n</segments>\n", size: (160, 32)),
         1408, "1676882e23bbfea64b13c83762e6201db1f7f8103a6bac869f5e8bfb19c84c0b"),
        ("progress-height-2", controlXIB("progressView", progress, size: (150, 2)), 904, "85a3797eb0ff4f4eba8843ca2ef705771a8700d4a47016257967280187fc66d1"),
        ("progress-bar-height-10", controlXIB("progressView", progress + #" progressViewStyle="bar""#, size: (150, 10)),
         927, "0d633900c277140e8f3c395173d3dfd44260adf0d4e020362d8d270ce86974de"),
        ("page-all", controlXIB("pageControl", page + #" currentPage="2" hidesForSinglePage="YES" defersCurrentPageDisplay="YES""#,
                                color("pageIndicatorTintColor", "0.5") + rgb("currentPageIndicatorTintColor", blue), size: (115, 26)),
         1349, "7c3912f7ddd5879a360ced83e0eaada5474b40b06aee4fc3396010d3a28c8ec6"),
        ("slider-all", controlXIB("slider", slider + #" value="20" minValue="1" maxValue="100" continuous="NO" minimumValueImage="Logo" maximumValueImage="Logo""#,
                                  rgb("minimumTrackTintColor", blue) + color("maximumTrackTintColor", "0.5") + color("thumbTintColor", "1"),
                                  size: (118, 31), resources: #"<image name="Logo" width="168" height="185"/>"# + "\n"),
         1641, "46fdb41eb8177e8dd6292e4b25cfb4da7e1dbce9e3bde42f5fb1e3e76d1edafd"),
    ]

    /// Each control's keys after a view's and a control's; activity indicators' styles and implicit
    /// tint, segments as zero-wide subviews with the selected one last, progress views' heights,
    /// the content hugging priorities each class writes.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
