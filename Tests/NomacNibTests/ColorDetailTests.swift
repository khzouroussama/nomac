import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for catalog and undefined named colors, system colors, accessibility traits,
/// data detectors and keyboard layout guides (`.github/scripts/nib_experiments.py`, `mx-*`): sizes and SHA-256
/// digests of Xcode's nibs.
@Suite struct ColorDetailTests {
    static let xibs: [(String, String, Int, String)] = [
        ("mx-trait-searchField", #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES">
    <device id="retina6_12" orientation="portrait" appearance="light"/>
    <dependencies>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
        <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
    </dependencies>
    <objects>
        <placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File's Owner"/>
        <placeholder placeholderIdentifier="IBFirstResponder" id="-2" customClass="UIResponder"/>
        <view contentMode="scaleToFill" id="iN0-l3-epB">
            <rect key="frame" x="0" y="0" width="393" height="852"/>
            <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
            <subviews>
                <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="sss-ss-ss1">
                    <rect key="frame" x="10" y="20" width="100" height="50"/>
                    <accessibility key="accessibilityConfiguration">
                        <accessibilityTraits key="traits" searchField="YES"/>
                    </accessibility>
                </view>
            </subviews>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 1006, "2bbfbfc5013f7c3277873ff9e9002d9fe96ea968ca559230224377ac6af26c53"),
        ("mx-trait-keyboardKey", #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES">
    <device id="retina6_12" orientation="portrait" appearance="light"/>
    <dependencies>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
        <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
    </dependencies>
    <objects>
        <placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File's Owner"/>
        <placeholder placeholderIdentifier="IBFirstResponder" id="-2" customClass="UIResponder"/>
        <view contentMode="scaleToFill" id="iN0-l3-epB">
            <rect key="frame" x="0" y="0" width="393" height="852"/>
            <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
            <subviews>
                <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="sss-ss-ss1">
                    <rect key="frame" x="10" y="20" width="100" height="50"/>
                    <accessibility key="accessibilityConfiguration">
                        <accessibilityTraits key="traits" keyboardKey="YES"/>
                    </accessibility>
                </view>
            </subviews>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 1005, "5f48cd11e8021974406ebd861419fcc9202fda64d1cac50f16456f98dfdf0ed7"),
        ("mx-trait-updatesFrequently", #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES">
    <device id="retina6_12" orientation="portrait" appearance="light"/>
    <dependencies>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
        <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
    </dependencies>
    <objects>
        <placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File's Owner"/>
        <placeholder placeholderIdentifier="IBFirstResponder" id="-2" customClass="UIResponder"/>
        <view contentMode="scaleToFill" id="iN0-l3-epB">
            <rect key="frame" x="0" y="0" width="393" height="852"/>
            <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
            <subviews>
                <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="sss-ss-ss1">
                    <rect key="frame" x="10" y="20" width="100" height="50"/>
                    <accessibility key="accessibilityConfiguration">
                        <accessibilityTraits key="traits" updatesFrequently="YES"/>
                    </accessibility>
                </view>
            </subviews>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 1006, "a37283d6d537f07ef351cd0e24d247f4a11fec83d53ecba229d79de38d5ffbdd"),
        ("mx-catalog-labelColor", #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES">
    <device id="retina6_12" orientation="portrait" appearance="light"/>
    <dependencies>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
        <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
    </dependencies>
    <objects>
        <placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File's Owner"/>
        <placeholder placeholderIdentifier="IBFirstResponder" id="-2" customClass="UIResponder"/>
        <view contentMode="scaleToFill"  id="iN0-l3-epB">
            <rect key="frame" x="0" y="0" width="393" height="852"/>
            <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
            <color key="backgroundColor" name="labelColor" catalog="System" colorSpace="catalog"/>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 938, "3618e67ba4b2596497524e537eb4ba5f28446940bb8ddc6d8d8e3757951da29a"),
        ("mx-catalog-textColor", #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES">
    <device id="retina6_12" orientation="portrait" appearance="light"/>
    <dependencies>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
        <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
    </dependencies>
    <objects>
        <placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File's Owner"/>
        <placeholder placeholderIdentifier="IBFirstResponder" id="-2" customClass="UIResponder"/>
        <view contentMode="scaleToFill"  id="iN0-l3-epB">
            <rect key="frame" x="0" y="0" width="393" height="852"/>
            <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
            <color key="backgroundColor" name="textColor" catalog="System" colorSpace="catalog"/>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 907, "7e9551778a0ee640f7f1cfb01aa812993aff85661c04198e8d1c541172fbf749"),
        ("mx-system-systemWhiteColor", #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES">
    <device id="retina6_12" orientation="portrait" appearance="light"/>
    <dependencies>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
        <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
    </dependencies>
    <objects>
        <placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File's Owner"/>
        <placeholder placeholderIdentifier="IBFirstResponder" id="-2" customClass="UIResponder"/>
        <view contentMode="scaleToFill"  id="iN0-l3-epB">
            <rect key="frame" x="0" y="0" width="393" height="852"/>
            <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
            <color key="backgroundColor" systemColor="systemWhiteColor"/>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 953, "5557ba1df29c4601a232c6f0e627d02cbd57a181888975e0a5b296d8f8b0e2c8"),
        ("mx-system-underPageBackgroundColor", #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES">
    <device id="retina6_12" orientation="portrait" appearance="light"/>
    <dependencies>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
        <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
    </dependencies>
    <objects>
        <placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File's Owner"/>
        <placeholder placeholderIdentifier="IBFirstResponder" id="-2" customClass="UIResponder"/>
        <view contentMode="scaleToFill"  id="iN0-l3-epB">
            <rect key="frame" x="0" y="0" width="393" height="852"/>
            <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
            <color key="backgroundColor" systemColor="underPageBackgroundColor"/>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 1044, "be41d41846b8a02c441bf103dd702fe11121317a546963c3e148331fec9d1d2c"),
        ("mx-named-undefined", #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES">
    <device id="retina6_12" orientation="portrait" appearance="light"/>
    <dependencies>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
        <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
    </dependencies>
    <objects>
        <placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File's Owner"/>
        <placeholder placeholderIdentifier="IBFirstResponder" id="-2" customClass="UIResponder"/>
        <view contentMode="scaleToFill"  id="iN0-l3-epB">
            <rect key="frame" x="0" y="0" width="393" height="852"/>
            <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
            <color key="backgroundColor" name="ActionTint"/>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 998, "c9a2b69dcbb7bdd9dd2ae8881ea834a6039c9754ff6f61aee1b0784fadfc2813"),
        ("mx-detect-lookupSuggestion", #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES">
    <device id="retina6_12" orientation="portrait" appearance="light"/>
    <dependencies>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
        <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
    </dependencies>
    <objects>
        <placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File's Owner"/>
        <placeholder placeholderIdentifier="IBFirstResponder" id="-2" customClass="UIResponder"/>
        <view contentMode="scaleToFill" id="iN0-l3-epB">
            <rect key="frame" x="0" y="0" width="393" height="852"/>
            <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
            <subviews>
                <textView clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="scaleToFill" textAlignment="natural" translatesAutoresizingMaskIntoConstraints="NO" id="txv-aa-aa1">
                    <rect key="frame" x="16" y="40" width="240" height="128"/>
                    <color key="backgroundColor" systemColor="systemBackgroundColor"/>
                    <string key="text">Lorem ipsum</string>
                    <fontDescription key="fontDescription" pointSize="14" type="system"/>
                    <textInputTraits key="textInputTraits" autocapitalizationType="sentences"/>
                    <dataDetectorType key="dataDetectorTypes" lookupSuggestion="YES"/>
                </textView>
            </subviews>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
    <resources>
        <systemColor name="systemBackgroundColor">
            <color white="1" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>
        </systemColor>
    </resources>
</document>

"""#, 2471, "0f49000b7e28a777f8d28c6950664cdd6c2f3a3297a42069d3706784e31eb977"),
        ("mx-detect-flightNumber", #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES">
    <device id="retina6_12" orientation="portrait" appearance="light"/>
    <dependencies>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
        <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
    </dependencies>
    <objects>
        <placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File's Owner"/>
        <placeholder placeholderIdentifier="IBFirstResponder" id="-2" customClass="UIResponder"/>
        <view contentMode="scaleToFill" id="iN0-l3-epB">
            <rect key="frame" x="0" y="0" width="393" height="852"/>
            <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
            <subviews>
                <textView clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="scaleToFill" textAlignment="natural" translatesAutoresizingMaskIntoConstraints="NO" id="txv-aa-aa1">
                    <rect key="frame" x="16" y="40" width="240" height="128"/>
                    <color key="backgroundColor" systemColor="systemBackgroundColor"/>
                    <string key="text">Lorem ipsum</string>
                    <fontDescription key="fontDescription" pointSize="14" type="system"/>
                    <textInputTraits key="textInputTraits" autocapitalizationType="sentences"/>
                    <dataDetectorType key="dataDetectorTypes" flightNumber="YES"/>
                </textView>
            </subviews>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
    <resources>
        <systemColor name="systemBackgroundColor">
            <color white="1" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>
        </systemColor>
    </resources>
</document>

"""#, 2471, "cdb09c3f2338c97bcdc6fe344b4147bbaee7279dcb4b791aa64c8c2687fb3004"),
        ("mx-keyboard-guide", #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES">
    <device id="retina6_12" orientation="portrait" appearance="light"/>
    <dependencies>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
        <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
    </dependencies>
    <objects>
        <placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File's Owner"/>
        <placeholder placeholderIdentifier="IBFirstResponder" id="-2" customClass="UIResponder"/>
        <view contentMode="scaleToFill" id="iN0-l3-epB">
            <rect key="frame" x="0" y="0" width="393" height="852"/>
            <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
            <subviews>
                <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="sub-aa-aa1">
                    <rect key="frame" x="10" y="20" width="100" height="50"/>
                </view>
            </subviews>
            <keyboardLayoutGuide key="keyboard" id="kbd-gg-aaa"/>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 1112, "c97f6a080991bafcb66c801f1328c47cee2f669a30ff77754b7b5d5c9ea38698"),
    ]

    static let storyboards: [(String, String, [String: String])] = [
        ("mx-sb-catalog-textColor", #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="BYZ-38-t0r">
    <device id="retina6_12" orientation="portrait" appearance="light"/>
    <dependencies>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
        <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
    </dependencies>
    <scenes>
        <scene sceneID="tne-QT-ifu">
            <objects>
                <viewController id="BYZ-38-t0r" sceneMemberID="viewController">
                    <view key="view" contentMode="scaleToFill" id="8bC-Xf-vdC">
                        <rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
                        <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
                        <color key="backgroundColor" name="textColor" catalog="System" colorSpace="catalog"/>
                    </view>
                </viewController>
                <placeholder placeholderIdentifier="IBFirstResponder" id="dkx-z0-nzr" sceneMemberID="firstResponder"/>
            </objects>
            <point key="canvasLocation" x="0" y="0"/>
        </scene>
    </scenes>
</document>

"""#, ["BYZ-38-t0r-view-8bC-Xf-vdC.nib": "45fabead7f2fdc13c2f493427bc254dfddca0c97c3b9bee2c67e10de72677487", "UIViewController-BYZ-38-t0r.nib": "b69dd7e3a282f29506304007dbec6a966adaf07712cbb248f0b29e5691e2bebf"]),
        ("mx-sb-system-systemWhiteColor", #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="BYZ-38-t0r">
    <device id="retina6_12" orientation="portrait" appearance="light"/>
    <dependencies>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
        <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
    </dependencies>
    <scenes>
        <scene sceneID="tne-QT-ifu">
            <objects>
                <viewController id="BYZ-38-t0r" sceneMemberID="viewController">
                    <view key="view" contentMode="scaleToFill" id="8bC-Xf-vdC">
                        <rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
                        <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
                        <color key="backgroundColor" systemColor="systemWhiteColor"/>
                    </view>
                </viewController>
                <placeholder placeholderIdentifier="IBFirstResponder" id="dkx-z0-nzr" sceneMemberID="firstResponder"/>
            </objects>
            <point key="canvasLocation" x="0" y="0"/>
        </scene>
    </scenes>
</document>

"""#, ["BYZ-38-t0r-view-8bC-Xf-vdC.nib": "f9c33bc8ebe3864389abb9d6564f06901126b404ca110b23261176c7576f267b", "UIViewController-BYZ-38-t0r.nib": "b69dd7e3a282f29506304007dbec6a966adaf07712cbb248f0b29e5691e2bebf"]),
        ("mx-sb-named-undefined", #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="BYZ-38-t0r">
    <device id="retina6_12" orientation="portrait" appearance="light"/>
    <dependencies>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
        <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
    </dependencies>
    <scenes>
        <scene sceneID="tne-QT-ifu">
            <objects>
                <viewController id="BYZ-38-t0r" sceneMemberID="viewController">
                    <view key="view" contentMode="scaleToFill" id="8bC-Xf-vdC">
                        <rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
                        <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
                        <color key="backgroundColor" name="ActionTint"/>
                    </view>
                </viewController>
                <placeholder placeholderIdentifier="IBFirstResponder" id="dkx-z0-nzr" sceneMemberID="firstResponder"/>
            </objects>
            <point key="canvasLocation" x="0" y="0"/>
        </scene>
    </scenes>
</document>

"""#, ["BYZ-38-t0r-view-8bC-Xf-vdC.nib": "4f329d2d0cec3a6953ee1fe1e37648bba6db5b639c5a4939cb7228a76244359b", "UIViewController-BYZ-38-t0r.nib": "b69dd7e3a282f29506304007dbec6a966adaf07712cbb248f0b29e5691e2bebf"]),
        ("mx-sb-pair-label", #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="BYZ-38-t0r">
    <device id="retina6_12" orientation="portrait" appearance="light"/>
    <dependencies>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
        <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
    </dependencies>
    <scenes>
        <scene sceneID="tne-QT-ifu">
            <objects>
                <viewController id="BYZ-38-t0r" sceneMemberID="viewController">
                    <view key="view" contentMode="scaleToFill" id="8bC-Xf-vdC">
                        <rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
                        <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
                        <color key="backgroundColor" systemColor="labelColor" cocoaTouchSystemColor="darkTextColor"/>
                    </view>
                </viewController>
                <placeholder placeholderIdentifier="IBFirstResponder" id="dkx-z0-nzr" sceneMemberID="firstResponder"/>
            </objects>
            <point key="canvasLocation" x="0" y="0"/>
        </scene>
    </scenes>
</document>

"""#, ["BYZ-38-t0r-view-8bC-Xf-vdC.nib": "4083284d70e9ef1f71271b7cf6150796ba719684fe0daad0b3215ac194926643", "UIViewController-BYZ-38-t0r.nib": "b69dd7e3a282f29506304007dbec6a966adaf07712cbb248f0b29e5691e2bebf"]),
    ]

    @Test(arguments: xibs)
    func compilesXibsAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }

    @Test(arguments: storyboards)
    func compilesStoryboardsAsXcode(name: String, document: String, digests: [String: String]) throws {
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        for (file, digest) in digests {
            let nib = try #require(compiled[file], "\(name) \(file)")
            #expect(VariationTests.digest(nib) == digest, "\(name) \(file)")
        }
    }
}
