import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for what older documents carry (`.github/scripts/nib_experiments.py`
/// rounds 120 to 122 and 129): their canvas elements change nothing; without Auto Layout a view's default
/// mask and a scene's guides do; devices it does not know are as no device.
@Suite struct OlderDocumentTests {
    static let base = ConstraintTests.constrained(ConstraintTests.subview("sss-ss-ss1"), "")
    static func options(_ target: String) -> XIBCompiler.Options {
        XIBCompiler.Options(module: "T", minimumDeploymentTarget: target, targetDevices: ["iphone"])
    }

    /// Each changes no nib against the document without it (`old-*`, `header-capability-*`,
    /// `header-default-version-*`, `animations-*`).
    @Test(arguments: [#"<simulatedStatusBarMetrics key="statusBar"/>"#, #"<simulatedOrientationMetrics key="simulatedOrientationMetrics" orientation="landscapeRight"/>"#,
                      #"<simulatedScreenMetrics key="simulatedDestinationMetrics" type="retina4"/>"#, #"<simulatedNavigationBarMetrics key="simulatedTopBarMetrics" translucent="NO" prompted="NO"/>"#,
                      #"<simulatedToolbarMetrics key="simulatedBottomBarMetrics" barStyle="black" translucent="NO"/>"#, "<animations/>"])
    func canvasElementsChangeNothing(element: String) throws {
        let plain = try XIBCompiler.compile(Data(Self.base.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        let with = Self.base.replacingOccurrences(of: #"<point key="canvasLocation""#, with: element + "\n" + #"<point key="canvasLocation""#)
        #expect(try XIBCompiler.compile(Data(with.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options) == plain)
    }

    @Test(arguments: [#"<capability name="Map view configurations" minToolsVersion="8.0"/>"#, #"<deployment defaultVersion="1792" identifier="iOS"/>"#, #"<development version="7000" identifier="xcode"/>"#])
    func headerElementsChangeNothing(element: String) throws {
        let plain = try XIBCompiler.compile(Data(Self.base.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        let with = Self.base.replacingOccurrences(of: "</dependencies>", with: element + "\n</dependencies>")
        #expect(try XIBCompiler.compile(Data(with.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options) == plain)
    }

    /// Values nobody observed stay refused, by the element holding them (`animations-not-empty`).
    @Test func refusesOtherCanvasValues() {
        let with = Self.base.replacingOccurrences(of: #"<point key="canvasLocation""#, with: #"<simulatedScreenMetrics key="destination" type="someday"/>"# + "\n" + #"<point key="canvasLocation""#)
        #expect(throws: NomacError.self) { try XIBCompiler.compile(Data(with.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options) }
    }

    static let old = XIBCompilerTests.xib("""
        <view contentMode="scaleToFill" id="iN0-l3-epB">
        <rect key="frame" x="0" y="0" width="320" height="568"/>
        <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
        <subviews>
        \(ConstraintTests.subview("sss-ss-ss1", (10, 20, 100, 50)))</subviews>
        <point key="canvasLocation" x="0" y="0"/>
        </view>

        """)
    static let device = #"<device id="retina6_12" orientation="portrait" appearance="light"/>"#

    /// Below 17, without a device or trait collections, a view takes the runtime's default device,
    /// 393 x 852 or 820 x 1180, whatever its frame (`header-traitless-320-*`).
    @Test(arguments: [("iOS.CocoaTouch", "com.apple.InterfaceBuilder3.CocoaTouch.XIB", 872, "f656183e6e3a29a51ff1b04554564a7464b0f95b9eeaf34c0d58556f00ab8a80"), ("iOS.CocoaTouch.iPad", "com.apple.InterfaceBuilder3.CocoaTouch.iPad.XIB", 872, "394fa58befd92ce932a530db66a9f891992998e38dae6540ee674069a366567b")])
    func documentsWithoutDevices(runtime: String, type: String, size: Int, digest: String) throws {
        let document = Self.old.replacingOccurrences(of: #" useTraitCollections="YES""#, with: "").replacingOccurrences(of: Self.device, with: "")
            .replacingOccurrences(of: #"targetRuntime="iOS.CocoaTouch""#, with: "targetRuntime=\"\(runtime)\"")
            .replacingOccurrences(of: #"type="com.apple.InterfaceBuilder3.CocoaTouch.XIB""#, with: "type=\"\(type)\"")
        let nib = try XIBCompiler.compile(Data(document.utf8), path: "/tmp/View.xib", options: Self.options("15.0"))
        #expect(nib.count == size)
        #expect(VariationTests.digest(nib) == digest)
    }

    /// A device ibtool does not know is as no device (`header-device-ipad12_9-*`, 600 x 600 below 17).
    @Test func unknownDevices() throws {
        let document = Self.base.replacingOccurrences(of: Self.device, with: #"<device id="ipad12_9" orientation="portrait"/>"#)
        let nib = try XIBCompiler.compile(Data(document.utf8), path: "/tmp/View.xib", options: Self.options("15.0"))
        #expect(nib.count == 872)
        #expect(VariationTests.digest(nib) == "a869a985f6d460ae4657f2c1dadbc688beeae6492e6ab2ee6559a6876e1c7817")
    }

    /// Without Auto Layout a view without a mask has flexible top and bottom margins, with it flexible
    /// right and bottom ones (`noauto-view`, `auto-view-unmasked`).
    @Test func viewsWithoutAutoLayout() throws {
        let view = ConstraintTests.subview("sss-ss-ss1").replacingOccurrences(of: #" translatesAutoresizingMaskIntoConstraints="NO""#, with: "")
        let document = ConstraintTests.constrained(view, "")
        let auto = try XIBCompiler.compile(Data(document.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(auto.count == 872)
        #expect(VariationTests.digest(auto) == "f656183e6e3a29a51ff1b04554564a7464b0f95b9eeaf34c0d58556f00ab8a80")
        let none = try XIBCompiler.compile(Data(document.replacingOccurrences(of: #" useAutolayout="YES""#, with: "").utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(none.count == 872)
        #expect(VariationTests.digest(none) == "4be37b8b65bd3293c9eaac442a84d9eb8b8f5c39a9666d9eaa71600dee3b9a96")
    }
}
