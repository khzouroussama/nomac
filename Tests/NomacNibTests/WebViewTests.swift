import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for WebKit views (`.github/scripts/nib_experiments.py` round 62,
/// `web-view*`): sizes and SHA-256 digests of Xcode's nibs.
@Suite struct WebViewTests {
    static func webView(_ attributes: String = "", preferences: String = #"<wkPreferences key="preferences"/>"#, extra: String = "") -> String {
        let configuration = "<wkWebViewConfiguration key=\"configuration\">\n"
            + #"<audiovisualMediaTypes key="mediaTypesRequiringUserActionForPlayback" none="YES"/>"# + "\n\(preferences)\n</wkWebViewConfiguration>\n"
        return ConstraintTests.constrained(ConstraintTests.subview("wkw-aa-aa1", (16, 118, 361, 587), tag: "wkWebView", attributes: attributes)
            .replacingOccurrences(of: "</wkWebView>", with: extra + configuration + "</wkWebView>"), "")
    }

    static let cases: [(String, String, Int, String)] = [
        ("web-view", webView(), 1988, "4a85b40557ace574698cc39a23a7777eb686b4a5d0c1ede85ff9f0daa6472bb2"),
        ("web-view-clear", webView(extra: XIBCompilerTests.gray("0.0", "0.0") + "\n"), 2162, "d2dbad99fb06816024a47e07efd7c29e1adbd3ccf74eed662342336787519932"),
        ("web-view-minimum-font", webView(preferences: #"<wkPreferences key="preferences" minimumFontSize="6"/>"#), 1988,
         "ca78502653754ae90596a3fb497c529830227488233390dd2f5f590a90b5fe49"),
        ("web-view-custom-class", webView(#" customClass="HTMLView" customModule="T" customModuleProvider="target""#), 2073,
         "7736ab0236d21d9f66fb927bbd846194bee7e818a6591687931f3d4a992db080"),
    ]

    /// A view's keys, then IB's web view configuration with its preferences' minimum font size, and
    /// the empty user agent.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }

    static func configured(_ attributes: String = "", media: String = #" none="YES""#, preferences: String = #"<wkPreferences key="preferences"/>"#, children: String = "",
                           view: String = "") -> String {
        webView(view, preferences: preferences + children)
            .replacingOccurrences(of: #"<wkWebViewConfiguration key="configuration">"#, with: "<wkWebViewConfiguration key=\"configuration\"\(attributes)>")
            .replacingOccurrences(of: #"<audiovisualMediaTypes key="mediaTypesRequiringUserActionForPlayback" none="YES"/>"#,
                                  with: "<audiovisualMediaTypes key=\"mediaTypesRequiringUserActionForPlayback\"\(media)/>")
    }

    static let configurations: [(String, String, Int, String)] = [
        ("web-config-inline", configured(#" allowsInlineMediaPlayback="YES""#), 1988, "1b37143b87922d5b297771adfe08a12c10b931c9e6d01714771abc9585b2012f"),
        ("web-config-all", configured(#" allowsInlineMediaPlayback="YES" allowsAirPlayForMediaPlayback="NO" allowsPictureInPictureMediaPlayback="NO" suppressesIncrementalRendering="YES""#),
         1988, "e5d46c3016e5be2c2c76c2443e96c5903e206afeb6a207725e858b99ba1d663e"),
        ("web-config-app-name", configured(#" applicationNameForUserAgent="Tester""#), 2000, "e94b8e163cb84191afd08646c185bb296e17fa5396c41ea7a4136c788c549933"),
        ("web-config-viewport", configured(#" ignoresViewportScaleLimits="YES""#), 1988, "3e4ff7fda28e44f59d61ce3bb3bbb7ff9bddc991e8700728bb229bcd40d62075"),
        ("web-config-granularity", configured(#" selectionGranularity="character""#), 1988, "c17f64bbca91ad22aba2842b55e2a5468032e415fca7c99f7af5b05fb953670e"),
        ("web-media-audio", configured(media: #" audio="YES""#), 1988, "60a191271f237d3675c4a3e2a5c30a731adc7f9f0b0bd66ca73f2899fe9fc49c"),
        ("web-detect-none", configured(children: "\n" + #"<dataDetectorTypes key="dataDetectorTypes" none="YES"/>"#), 1988, "96a0171e0eef7b2d13119d6e461bfeb8b5e02550bc8c8b3fe462933c79d08888"),
        ("web-detect-two", configured(children: "\n" + #"<dataDetectorTypes key="dataDetectorTypes" phoneNumber="YES" link="YES"/>"#),
         1988, "0bb3c63c1f83fd9c9a4c3ed1d8ed54055052d316554d5bed0853e634a7ade68a"),
        ("web-prefs-font-popups", configured(preferences: #"<wkPreferences key="preferences" minimumFontSize="6" javaScriptCanOpenWindowsAutomatically="YES"/>"#),
         1988, "a44bf08180182d7ec03677ec92467395554e1969b1922670223c419a0aeac1cc"),
        ("web-prefs-no-js", configured(preferences: #"<wkPreferences key="preferences" javaScriptEnabled="NO"/>"#), 1988, "8cc581dfb0dd92be560d0ffbedfddf2f3ac5979390a4a54f7efeb1e09412f3e2"),
        ("web-view-gestures", configured(view: #" allowsBackForwardNavigationGestures="YES""#), 1988, "d9179c125f1ba613982ad57a10fa2c09d2ad83365c4b49fcb5ac1a5c19651d80"),
        ("web-view-no-preview", configured(view: #" allowsLinkPreview="NO""#), 1988, "11de1db9f0c24cccd464ba283cb7034424ddc2ccde63a2d15986cba716e6fa68"),
        ("web-view-agent", configured(view: #" customUserAgent="Agent""#), 1999, "6630ecebbf0077fc49b4c3cfe5c5f0f03e89a4c0cd520d2944e8464455fe0b51"),
        ("web-same-agent-and-name", configured(#" applicationNameForUserAgent="Same""#, view: #" customUserAgent="Same""#),
         1992, "7b19a6757b3481d1015a509d25d020a4ff364933c37e5930e9127c288d5406ed"),
    ]

    /// The document's settings among IB's defaults; media types other than `none` require a user
    /// action; data detectors as their bits; equal agent and application names are one string.
    @Test(arguments: configurations)
    func compilesConfigurationsAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }

    /// No media types element requires a user action too (`web-media-absent`).
    @Test func missingMediaTypesRequireUserAction() throws {
        let xib = Self.configured().replacingOccurrences(of: #"<audiovisualMediaTypes key="mediaTypesRequiringUserActionForPlayback" none="YES"/>"#, with: "")
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(VariationTests.digest(nib) == "60a191271f237d3675c4a3e2a5c30a731adc7f9f0b0bd66ca73f2899fe9fc49c")
    }
}
