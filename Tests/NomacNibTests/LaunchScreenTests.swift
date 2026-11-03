import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for launch screens shaped as React Native's and Expo's app
/// templates write them, and the attribute spellings they use (`.github/scripts/nib_experiments.py`
/// round 20): sizes and SHA-256 digests of Xcode's files.
@Suite struct LaunchScreenTests {
    static let reactNative = """
        <?xml version="1.0" encoding="UTF-8"?>
        <document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="15702" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" launchScreen="YES" useTraitCollections="YES" useSafeAreas="YES" colorMatched="YES" initialViewController="Lc1-aa-aaa">
            <device id="retina4_7" orientation="portrait" appearance="light"/>
            <dependencies>
                <deployment identifier="iOS"/>
                <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="15704"/>
                <capability name="Safe area layout guides" minToolsVersion="9.0"/>
                <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
            </dependencies>
            <scenes>
                <!--View Controller-->
                <scene sceneID="Ls1-aa-aaa">
                    <objects>
                        <viewController id="Lc1-aa-aaa" sceneMemberID="viewController">
                            <view key="view" contentMode="scaleToFill" id="Lv1-aa-aaa">
                                <rect key="frame" x="0.0" y="0.0" width="375" height="667"/>
                                <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
                                <subviews>
                                    <label opaque="NO" clipsSubviews="YES" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" text="Sample" textAlignment="center" lineBreakMode="middleTruncation" baselineAdjustment="alignBaselines" minimumFontSize="18" translatesAutoresizingMaskIntoConstraints="NO" id="Ll1-aa-aaa">
                                        <rect key="frame" x="0.0" y="202" width="375" height="43"/>
                                        <fontDescription key="fontDescription" type="boldSystem" pointSize="36"/>
                                        <nil key="highlightedColor"/>
                                    </label>
                                    <label opaque="NO" clipsSubviews="YES" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" text="Made with a template" textAlignment="center" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" minimumFontSize="9" translatesAutoresizingMaskIntoConstraints="NO" id="Ll2-aa-aaa">
                                        <rect key="frame" x="0.0" y="626" width="375" height="21"/>
                                        <fontDescription key="fontDescription" type="system" pointSize="17"/>
                                        <nil key="highlightedColor"/>
                                    </label>
                                </subviews>
                                <color key="backgroundColor" systemColor="systemBackgroundColor" cocoaTouchSystemColor="whiteColor"/>
                                <constraints>
                                    <constraint firstItem="Lg1-aa-aaa" firstAttribute="bottom" secondItem="Ll2-aa-aaa" secondAttribute="bottom" constant="20" id="Lk1-aa-aaa"/>
                                    <constraint firstItem="Lg1-aa-aaa" firstAttribute="centerX" secondItem="Ll1-aa-aaa" secondAttribute="centerX" id="Lk2-aa-aaa"/>
                                    <constraint firstItem="Ll2-aa-aaa" firstAttribute="centerX" secondItem="Lg1-aa-aaa" secondAttribute="centerX" id="Lk3-aa-aaa"/>
                                    <constraint firstItem="Ll2-aa-aaa" firstAttribute="leading" secondItem="Lg1-aa-aaa" secondAttribute="leading" id="Lk4-aa-aaa"/>
                                    <constraint firstItem="Ll1-aa-aaa" firstAttribute="centerY" secondItem="Lv1-aa-aaa" secondAttribute="bottom" multiplier="1/3" constant="1" id="Lk5-aa-aaa"/>
                                    <constraint firstItem="Ll1-aa-aaa" firstAttribute="leading" secondItem="Lg1-aa-aaa" secondAttribute="leading" symbolic="YES" id="Lk6-aa-aaa"/>
                                </constraints>
                                <viewLayoutGuide key="safeArea" id="Lg1-aa-aaa"/>
                            </view>
                        </viewController>
                        <placeholder placeholderIdentifier="IBFirstResponder" id="Lr1-aa-aaa" userLabel="First Responder" sceneMemberID="firstResponder"/>
                    </objects>
                    <point key="canvasLocation" x="52.173913043478265" y="375"/>
                </scene>
            </scenes>
        </document>

        """
    static let expo = """
        <?xml version="1.0" encoding="UTF-8"?>
        <document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="24093.7" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" launchScreen="YES" useTraitCollections="YES" useSafeAreas="YES" colorMatched="YES" initialViewController="SAMPLE-CONTROLLER-1">
            <device id="retina6_12" orientation="portrait" appearance="light"/>
            <dependencies>
                <deployment identifier="iOS"/>
                <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="24053.1"/>
                <capability name="Named colors" minToolsVersion="9.0"/>
                <capability name="Safe area layout guides" minToolsVersion="9.0"/>
                <capability name="System colors in document resources" minToolsVersion="11.0"/>
                <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
            </dependencies>
            <scenes>
                <scene sceneID="SAMPLE-SCENE-1">
                    <objects>
                        <viewController storyboardIdentifier="LaunchController" id="SAMPLE-CONTROLLER-1" sceneMemberID="viewController">
                            <view key="view" userInteractionEnabled="NO" contentMode="scaleToFill" insetsLayoutMarginsFromSafeArea="NO" id="SAMPLE-Container" userLabel="Container">
                                <rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
                                <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
                                <subviews>
                                    <imageView id="SAMPLE-Logo" userLabel="Logo" image="LaunchLogo" contentMode="scaleAspectFit" clipsSubviews="true" userInteractionEnabled="false" translatesAutoresizingMaskIntoConstraints="false">
                                        <rect key="frame" x="158.5" y="388" width="76" height="76"/>
                                    </imageView>
                                </subviews>
                                <viewLayoutGuide key="safeArea" id="Sg1-aa-aaa"/>
                                <constraints>
                                    <constraint firstItem="SAMPLE-Logo" firstAttribute="centerX" secondItem="SAMPLE-Container" secondAttribute="centerX" id="0f3a9c1d2b4e5f60718293a4b5c6d7e8f9012345"/>
                                    <constraint firstItem="SAMPLE-Logo" firstAttribute="centerY" secondItem="SAMPLE-Container" secondAttribute="centerY" id="9e8d7c6b5a4f3e2d1c0b9a8f7e6d5c4b3a291807"/>
                                </constraints>
                                <color key="backgroundColor" name="LaunchBackground"/>
                            </view>
                        </viewController>
                        <placeholder placeholderIdentifier="IBFirstResponder" id="SAMPLE-PLACEHOLDER-1" userLabel="First Responder" sceneMemberID="firstResponder"/>
                    </objects>
                    <point key="canvasLocation" x="0.0" y="0.0"/>
                </scene>
            </scenes>
            <resources>
                <image name="LaunchLogo" width="76" height="76"/>
                <systemColor name="systemBackgroundColor">
                    <color white="1" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>
                </systemColor>
                <namedColor name="LaunchBackground">
                    <color alpha="1.000" blue="0.937254901960784" green="0.541176470588235" red="0.125490196078431" customColorSpace="sRGB" colorSpace="custom"/>
                </namedColor>
            </resources>
        </document>

        """

    static let reactNativeFiles = [
        ("Info.plist", 258, "0f6ae85b392a678500a33ed5f46e8af936be7263000e04e683cf90d9478ef5b0"),
        ("Lc1-aa-aaa-view-Lv1-aa-aaa.nib", 3840, "97bea81827d22f442dd5b9fecea29f4e54db33af973fb6fa6296a08d863be600"),
        ("UIViewController-Lc1-aa-aaa.nib", 924, "cedf42c20bd84bf0c1366da2e26b4760a0fde9a3f034eebdf97f7996db4fc252"),
    ]
    static let expoFiles = [
        ("Info.plist", 205, "41588c61466aeade7b154b232fe87c37e4954c2f303813c962163df3549123db"),
        ("LaunchController.nib", 990, "9af4ef3d4df638658d5bd61ba5c4116f7ec2835782f8840db495f4854de50951"),
        ("SAMPLE-CONTROLLER-1-view-SAMPLE-Container.nib", 2124, "3ff41df37b348371465eedd1a705ac16faa67a964dd219676643cd24abf9b457"),
    ]

    static func digest(_ data: Data) -> String {
        SHA256.digest(Array(data)).map { String(format: "%02x", $0) }.joined()
    }

    /// `sb-launch-rn-at-*`, `sb-launch-expo-at-*`: the same files from 11.0 and from 13.0 to 26.2 and
    /// at 27.0, on the devices the templates' projects target.
    @Test(arguments: [
        ("react-native", "15.1", ["iphone", "ipad"]), ("react-native", "11.0", ["iphone", "ipad"]), ("react-native", "27.0", ["iphone"]),
        ("expo", "16.4", ["iphone"]), ("expo", "13.0", ["iphone"]), ("expo", "26.2", ["iphone"]),
    ])
    func compilesTemplatesAsXcode(template: String, deployment: String, devices: [String]) throws {
        let options = XIBCompiler.Options(module: "T", minimumDeploymentTarget: deployment, targetDevices: devices)
        let (document, files) = template == "expo" ? (Self.expo, Self.expoFiles) : (Self.reactNative, Self.reactNativeFiles)
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: options)
        #expect(compiled.keys.sorted() == files.map(\.0).sorted())
        for (file, size, digest) in files {
            let data = try #require(compiled[file], "\(file)")
            #expect(data.count == size, "\(template) \(deployment) \(file)")
            #expect(Self.digest(data) == digest, "\(template) \(deployment) \(file)")
        }
    }

    /// Below the version a feature needs, ibtool writes each nib as `objects-<version>+.nib` and
    /// `runtime.nib` (safe area guides need 11.0, named colors 13.0), or fails (safe areas before 9.0,
    /// named colors before 11.0); nomac refuses those targets, and targets that are no iOS release.
    @Test(arguments: [
        ("react-native", "10.3", "nibs that need iOS 11.0 for --minimum-deployment-target 10.3"),
        ("react-native", "8.0", "nibs that need iOS 11.0 for --minimum-deployment-target 8.0"),
        ("expo", "12.5", "nibs that need iOS 13.0 for --minimum-deployment-target 12.5"),
        ("expo", "15.9", "nibs for --minimum-deployment-target 15.9"),
        ("expo", "16", "nibs for --minimum-deployment-target 16"),
    ])
    func refusesTargetsBelowTheirFeatures(template: String, deployment: String, what: String) {
        let options = XIBCompiler.Options(module: "T", minimumDeploymentTarget: deployment, targetDevices: ["iphone"])
        #expect(throws: NomacError("nomac does not compile \(what) yet (BACKLOG B-263)", path: "/tmp/Main.storyboard")) {
            try StoryboardCompiler.compile(Data((template == "expo" ? Self.expo : Self.reactNative).utf8), path: "/tmp/Main.storyboard", options: options)
        }
    }

    static func compiled(_ document: String, deployment: String = "27.0") throws -> Data {
        let options = XIBCompiler.Options(module: "T", minimumDeploymentTarget: deployment, targetDevices: ["iphone"])
        return try XIBCompiler.compile(Data(document.utf8), path: "/tmp/View.xib", options: options)
    }

    /// `bool-*`, `alpha-*`, `color-system-and-cocoa-touch`, `constraint-multiplier-*`,
    /// `deployment-*`: spellings ibtool reads as the same value.
    @Test(arguments: [
        ([#"hidden="YES""#, #"hidden="true""#, #"hidden="yes""#, #"hidden="1""#]),
        ([#"opaque="NO""#, #"opaque="false""#]),
        ([#"userInteractionEnabled="NO""#, #"userInteractionEnabled="false""#]),
        ([#"clipsSubviews="YES""#, #"clipsSubviews="true""#]),
        (["", #"hidden="false""#, #"hidden="no""#, #"hidden="0""#, #"alpha="1.000""#, #"alpha="1.0""#]),
        ([#"alpha="0.5""#, #"alpha="0.500""#, #"alpha=".5""#]),
    ])
    func readsSpellingsAlike(attributes: [String]) throws {
        let nibs = try attributes.map { try Self.compiled(XIBCompilerTests.xib(XIBCompilerTests.view($0))) }
        #expect(Set(nibs).count == 1, "\(attributes)")
    }

    @Test func readsSystemColorsWithACocoaTouchFallbackAsTheSystemColor() throws {
        let plain = try Self.compiled(XIBCompilerTests.xib(XIBCompilerTests.view(color: XIBCompilerTests.system("systemBackgroundColor"))))
        let paired = try Self.compiled(XIBCompilerTests.xib(XIBCompilerTests.view(
            color: #"<color key="backgroundColor" systemColor="systemBackgroundColor" cocoaTouchSystemColor="whiteColor"/>"#)))
        #expect(paired == plain)
    }

    @Test func readsDeploymentTargetsOfEveryReleaseAlike() throws {
        let document = XIBCompilerTests.xib(XIBCompilerTests.view())
        let nibs = try ["8.0", "8.4", "10.3", "15.1", "16.7", "26.2", "27.0"].map { try Self.compiled(document, deployment: $0) }
        #expect(Set(nibs).count == 1)
    }

    static func centered(_ extra: String) -> String {
        ConstraintTests.constrained(ConstraintTests.subview(), ConstraintTests.constraint(0, ConstraintTests.sub, "centerY", ConstraintTests.root, "bottom", extra))
    }

    /// `constraint-multiplier-*`: a multiplier is rounded to a float, a ratio written with `:` or `/`.
    @Test func roundsMultipliersToFloats() throws {
        let nibs = try [#" multiplier="1/3" constant="1""#, #" multiplier="1:3" constant="1""#, #" multiplier="0.33333333333333331" constant="1""#]
            .map { try Self.compiled(Self.centered($0)) }
        #expect(Set(nibs).count == 1)
        #expect(nibs[0].count == 1214)
        #expect(Self.digest(nibs[0]) == "2e6a28999ab57688eb4aab2c19148b95d46197345cc53ada684d96d5f1762ca2")
    }

    /// `constraint-symbolic`, `label-text-absent`, `label-highlighted-absent`.
    @Test(arguments: [
        ("constraint-symbolic", ConstraintTests.constrained(ConstraintTests.subview(), ConstraintTests.constraint(
            0, ConstraintTests.sub, "leading", ConstraintTests.root, "leading", #" symbolic="YES""#)),
         1185, "130d79e45bc7028005a7e297db76d38a04a738c395337d0654b2dc0695c90006"),
        ("label-text-absent", LabelTests.labelled(LabelTests.label(colors: #"<nil key="highlightedColor"/>"# + "\n")),
         1809, "3837b0d91d8e27ead07146a02e5a53e885a8e0308ad7038edebeef94fba8eed3"),
        ("label-highlighted-absent", LabelTests.labelled(LabelTests.label(colors: #"<nil key="textColor"/>"# + "\n")),
         1881, "7b11bacf37048c6915b2834148580ed64baceeac05605a220934d9d7bc66509e"),
    ])
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try Self.compiled(xib)
        #expect(nib.count == size, "\(name)")
        #expect(Self.digest(nib) == digest, "\(name)")
    }
}
