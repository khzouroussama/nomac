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
}
