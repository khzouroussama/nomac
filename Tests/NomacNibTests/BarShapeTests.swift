import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for navigation bars' frames, shadows and background, localized button configurations
/// and a table's section index colors (`.github/scripts/nib_experiments.py` rounds 146 to 149).
@Suite struct BarShapeTests {
    @Test(arguments: cases) func compilesAsXcode(_ document: ObservedDocument) throws {
        try document.check()
    }

    static let cases = [
        ObservedDocument(name: "bc-lproj-title", path: "/tmp/Base.lproj/View.xib", target: "27.0", digest: "69d792a59239c609f6954963eb64ee67ef19fe4eedcac898c0cf2521abff3d13", warnings: [], document: #"""
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
<button opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" buttonType="system" lineBreakMode="middleTruncation" translatesAutoresizingMaskIntoConstraints="NO" id="bbb-bb-bb1">
<rect key="frame" x="20" y="40" width="75" height="35"/>
<state key="normal" title="Button"/>
<buttonConfiguration key="configuration" style="plain" title="Button"/>
</button>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "bc-lproj-both", path: "/tmp/Base.lproj/View.xib", target: "27.0", digest: "171842cdd2c0ccb5bbd5da330ee24b88eb8c762b8f2a99833a99656ad47cde90", warnings: [], document: #"""
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
<button opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" buttonType="system" lineBreakMode="middleTruncation" translatesAutoresizingMaskIntoConstraints="NO" id="bbb-bb-bb1">
<rect key="frame" x="20" y="40" width="75" height="35"/>
<state key="normal" title="Button"/>
<buttonConfiguration key="configuration" style="plain" title="Button" subtitle="Sub"/>
</button>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "bc-plain-subtitle", path: "/tmp/View.xib", target: "27.0", digest: "5ba172fda945433fe88dd36cbe5b5bf56f799db509775ade5bc518e0feee8e0f", warnings: [], document: #"""
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
<button opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" buttonType="system" lineBreakMode="middleTruncation" translatesAutoresizingMaskIntoConstraints="NO" id="bbb-bb-bb1">
<rect key="frame" x="20" y="40" width="75" height="35"/>
<state key="normal" title="Button"/>
<buttonConfiguration key="configuration" style="plain" subtitle="Sub"/>
</button>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "sb-bc-lproj-filled", path: "/tmp/Base.lproj/Main.storyboard", target: "27.0", digest: "01b460e3f1d67b28724c0d56e82399f28ff83d23019dac14db74011b038e8487", warnings: [], document: #"""
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
<subviews>
<button opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" buttonType="system" lineBreakMode="middleTruncation" translatesAutoresizingMaskIntoConstraints="NO" id="bbb-bb-bb1">
<rect key="frame" x="20" y="40" width="75" height="35"/>
<state key="normal" title="Button"/>
<buttonConfiguration key="configuration" style="filled" title="Button"/>
</button>
</subviews>
</view>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="dkx-z0-nzr" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#),
        ObservedDocument(name: "bc-filled-two", path: "/tmp/View.xib", target: "27.0", digest: "82723c131e73b19fd3be6d76a27ec31689d4460d601bfae0c933ffd01ae3ba2a", warnings: [], document: #"""
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
<button opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" buttonType="system" lineBreakMode="middleTruncation" translatesAutoresizingMaskIntoConstraints="NO" id="bbb-bb-bb1">
<rect key="frame" x="20" y="40" width="75" height="35"/>
<state key="normal" title="Button"/>
<buttonConfiguration key="configuration" style="filled"/>
</button>
<button opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" buttonType="system" lineBreakMode="middleTruncation" translatesAutoresizingMaskIntoConstraints="NO" id="bbb-bb-bb2">
<rect key="frame" x="20" y="40" width="75" height="35"/>
<state key="normal" title="Button"/>
<buttonConfiguration key="configuration" style="filled"/>
</button>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "bc-gray-two", path: "/tmp/View.xib", target: "27.0", digest: "9f01a116246ca5197d1f0b5f0a89e2ee4045e02ccc34328e0196c5315c2c9449", warnings: [], document: #"""
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
<button opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" buttonType="system" lineBreakMode="middleTruncation" translatesAutoresizingMaskIntoConstraints="NO" id="bbb-bb-bb1">
<rect key="frame" x="20" y="40" width="75" height="35"/>
<state key="normal" title="Button"/>
<buttonConfiguration key="configuration" style="gray"/>
</button>
<button opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" buttonType="system" lineBreakMode="middleTruncation" translatesAutoresizingMaskIntoConstraints="NO" id="bbb-bb-bb2">
<rect key="frame" x="20" y="40" width="75" height="35"/>
<state key="normal" title="Button"/>
<buttonConfiguration key="configuration" style="gray"/>
</button>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "bc-plain-two", path: "/tmp/View.xib", target: "27.0", digest: "43ffda2453ffb363db88d6e50943a53b0f359ff72fb62cfe16749b12c4982ab8", warnings: [], document: #"""
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
<button opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" buttonType="system" lineBreakMode="middleTruncation" translatesAutoresizingMaskIntoConstraints="NO" id="bbb-bb-bb1">
<rect key="frame" x="20" y="40" width="75" height="35"/>
<state key="normal" title="Button"/>
<buttonConfiguration key="configuration" style="plain"/>
</button>
<button opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" buttonType="system" lineBreakMode="middleTruncation" translatesAutoresizingMaskIntoConstraints="NO" id="bbb-bb-bb2">
<rect key="frame" x="20" y="40" width="75" height="35"/>
<state key="normal" title="Button"/>
<buttonConfiguration key="configuration" style="plain"/>
</button>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "sb-table-prototype-colors", path: "/tmp/Main.storyboard", target: "27.0", digest: "7b4e19b7c0f4cfb7218346d5d251c9762a4f4e9fb7898c7b9907c9edc6c180d9", warnings: [], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="tvc-aa-aaa">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
</dependencies>
<scenes>
<scene sceneID="tvs-aa-aaa">
<objects>
<tableViewController id="tvc-aa-aaa" sceneMemberID="viewController">
<tableView key="view" clipsSubviews="YES" contentMode="scaleToFill" alwaysBounceVertical="YES" dataMode="prototypes" style="plain" separatorStyle="default" rowHeight="-1" estimatedRowHeight="-1" sectionHeaderHeight="28" sectionFooterHeight="28" id="tbv-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<inset key="separatorInset" minX="10" minY="0.0" maxX="20" maxY="0.0"/>
<color key="separatorColor" red="1" green="0" blue="0" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
<color key="sectionIndexColor" red="1" green="0" blue="0" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
<color key="sectionIndexBackgroundColor" red="1" green="0" blue="0" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
<color key="sectionIndexTrackingBackgroundColor" red="1" green="0" blue="0" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
<prototypes>
<tableViewCell clipsSubviews="YES" contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" reuseIdentifier="Cell" id="cel-aa-aa1">
<rect key="frame" x="0.0" y="28" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="cel-aa-aa1" id="ccv-aa-aa1">
<rect key="frame" x="0.0" y="0.0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
</tableViewCellContentView>
</tableViewCell>
</prototypes>
<connections>
<outlet property="dataSource" destination="tvc-aa-aaa" id="tds-aa-aaa"/>
<outlet property="delegate" destination="tvc-aa-aaa" id="tdl-aa-aaa"/>
</connections>
</tableView>
</tableViewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="tfr-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#),
        ObservedDocument(name: "sb-nav-bar-background", path: "/tmp/Main.storyboard", target: "27.0", digest: "5a7ec5f6576d14f21e19108ff363484ba8853c39962106cbfc3d71358d9e8567", warnings: [], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="nvc-aa-aaa">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
</dependencies>
<scenes>
<scene sceneID="nvs-aa-aaa">
<objects>
<navigationController id="nvc-aa-aaa" sceneMemberID="viewController">
<navigationBar key="navigationBar" contentMode="scaleToFill" id="nvb-aa-aaa">
<rect key="frame" x="0.0" y="59" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<color key="backgroundColor" red="1" green="0" blue="0" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
</navigationBar>
<connections>
<segue destination="vc1-aa-aaa" kind="relationship" relationship="rootViewController" id="rel-aa-aaa"/>
</connections>
</navigationController>
<placeholder placeholderIdentifier="IBFirstResponder" id="nfr-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="-400" y="0"/>
</scene>
<scene sceneID="sc1-aa-aaa">
<objects>
<viewController id="vc1-aa-aaa" sceneMemberID="viewController">
<view key="view" contentMode="scaleToFill" id="vw1-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
</view>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#),
        ObservedDocument(name: "sb-nav-bar-shadow-image-title", path: "/tmp/Main.storyboard", target: "27.0", digest: "f9ababea3fc8d9ad6178ea9e14a817ee3b61a76a4a8eea7a7e3cd01ec60a8c54", warnings: [], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="nvc-aa-aaa">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
</dependencies>
<scenes>
<scene sceneID="nvs-aa-aaa">
<objects>
<navigationController id="nvc-aa-aaa" sceneMemberID="viewController">
<navigationBar key="navigationBar" contentMode="scaleToFill" shadowImage="Logo" id="nvb-aa-aaa">
<rect key="frame" x="0.0" y="59" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<textAttributes key="titleTextAttributes">
<color key="textColor" red="1" green="0" blue="0" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
</textAttributes>
</navigationBar>
<connections>
<segue destination="vc1-aa-aaa" kind="relationship" relationship="rootViewController" id="rel-aa-aaa"/>
</connections>
</navigationController>
<placeholder placeholderIdentifier="IBFirstResponder" id="nfr-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="-400" y="0"/>
</scene>
<scene sceneID="sc1-aa-aaa">
<objects>
<viewController id="vc1-aa-aaa" sceneMemberID="viewController">
<view key="view" contentMode="scaleToFill" id="vw1-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
</view>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#),
        ObservedDocument(name: "sb-nav-bar-title-font-color-shadow", path: "/tmp/Main.storyboard", target: "27.0", digest: "cdadf38f69db0c2c5435309de7a6b40e3dcf9668b064643b202223de04f06f7b", warnings: [], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="nvc-aa-aaa">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
</dependencies>
<scenes>
<scene sceneID="nvs-aa-aaa">
<objects>
<navigationController id="nvc-aa-aaa" sceneMemberID="viewController">
<navigationBar key="navigationBar" contentMode="scaleToFill" id="nvb-aa-aaa">
<rect key="frame" x="0.0" y="59" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<textAttributes key="titleTextAttributes">
<fontDescription key="fontDescription" type="system" weight="light" pointSize="21"/>
<color key="textColor" red="1" green="0" blue="0" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
<color key="textShadowColor" white="1" alpha="1" colorSpace="calibratedWhite"/>
</textAttributes>
</navigationBar>
<connections>
<segue destination="vc1-aa-aaa" kind="relationship" relationship="rootViewController" id="rel-aa-aaa"/>
</connections>
</navigationController>
<placeholder placeholderIdentifier="IBFirstResponder" id="nfr-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="-400" y="0"/>
</scene>
<scene sceneID="sc1-aa-aaa">
<objects>
<viewController id="vc1-aa-aaa" sceneMemberID="viewController">
<view key="view" contentMode="scaleToFill" id="vw1-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
</view>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#),
        ObservedDocument(name: "sb-nav-bar-title-offset-vertical", path: "/tmp/Main.storyboard", target: "27.0", digest: "6621d1b17668ed21daff5b2d523094e5664ac08800b9fbab8a06fabcaae532e4", warnings: [], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="nvc-aa-aaa">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
</dependencies>
<scenes>
<scene sceneID="nvs-aa-aaa">
<objects>
<navigationController id="nvc-aa-aaa" sceneMemberID="viewController">
<navigationBar key="navigationBar" contentMode="scaleToFill" id="nvb-aa-aaa">
<rect key="frame" x="0.0" y="59" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<textAttributes key="titleTextAttributes">
<offsetWrapper key="textShadowOffset" horizontal="0.0" vertical="1"/>
</textAttributes>
</navigationBar>
<connections>
<segue destination="vc1-aa-aaa" kind="relationship" relationship="rootViewController" id="rel-aa-aaa"/>
</connections>
</navigationController>
<placeholder placeholderIdentifier="IBFirstResponder" id="nfr-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="-400" y="0"/>
</scene>
<scene sceneID="sc1-aa-aaa">
<objects>
<viewController id="vc1-aa-aaa" sceneMemberID="viewController">
<view key="view" contentMode="scaleToFill" id="vw1-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
</view>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#),
        ObservedDocument(name: "sb-nav-bar-title-offset-horizontal", path: "/tmp/Main.storyboard", target: "27.0", digest: "63ea5f73e55d83669b8d27ef8e0a4d778a9920b6f00cf5d44f5b71a935aa79a1", warnings: [], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="nvc-aa-aaa">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
</dependencies>
<scenes>
<scene sceneID="nvs-aa-aaa">
<objects>
<navigationController id="nvc-aa-aaa" sceneMemberID="viewController">
<navigationBar key="navigationBar" contentMode="scaleToFill" id="nvb-aa-aaa">
<rect key="frame" x="0.0" y="59" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<textAttributes key="titleTextAttributes">
<offsetWrapper key="textShadowOffset" horizontal="1" vertical="0.0"/>
</textAttributes>
</navigationBar>
<connections>
<segue destination="vc1-aa-aaa" kind="relationship" relationship="rootViewController" id="rel-aa-aaa"/>
</connections>
</navigationController>
<placeholder placeholderIdentifier="IBFirstResponder" id="nfr-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="-400" y="0"/>
</scene>
<scene sceneID="sc1-aa-aaa">
<objects>
<viewController id="vc1-aa-aaa" sceneMemberID="viewController">
<view key="view" contentMode="scaleToFill" id="vw1-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
</view>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#),
        ObservedDocument(name: "sb-nav-bar-title-offset-zero", path: "/tmp/Main.storyboard", target: "27.0", digest: "7fda3f09bcb2c75d1650843b97c7f650bdef477a864f9c621b90788d2ae15201", warnings: [], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="nvc-aa-aaa">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
</dependencies>
<scenes>
<scene sceneID="nvs-aa-aaa">
<objects>
<navigationController id="nvc-aa-aaa" sceneMemberID="viewController">
<navigationBar key="navigationBar" contentMode="scaleToFill" id="nvb-aa-aaa">
<rect key="frame" x="0.0" y="59" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<textAttributes key="titleTextAttributes">
<offsetWrapper key="textShadowOffset" horizontal="0.0" vertical="0.0"/>
</textAttributes>
</navigationBar>
<connections>
<segue destination="vc1-aa-aaa" kind="relationship" relationship="rootViewController" id="rel-aa-aaa"/>
</connections>
</navigationController>
<placeholder placeholderIdentifier="IBFirstResponder" id="nfr-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="-400" y="0"/>
</scene>
<scene sceneID="sc1-aa-aaa">
<objects>
<viewController id="vc1-aa-aaa" sceneMemberID="viewController">
<view key="view" contentMode="scaleToFill" id="vw1-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
</view>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#),
        ObservedDocument(name: "sb-nav-bar-frameless", path: "/tmp/Main.storyboard", target: "27.0", digest: "8ad002b6a673d1441137e8a0290a8a4f9119d7aaeda76da26bc43023dd24cbb2", warnings: [], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="nvc-aa-aaa">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
</dependencies>
<scenes>
<scene sceneID="nvs-aa-aaa">
<objects>
<navigationController id="nvc-aa-aaa" sceneMemberID="viewController">
<navigationBar key="navigationBar" contentMode="scaleToFill" id="nvb-aa-aaa">
<autoresizingMask key="autoresizingMask"/>
</navigationBar>
<connections>
<segue destination="vc1-aa-aaa" kind="relationship" relationship="rootViewController" id="rel-aa-aaa"/>
</connections>
</navigationController>
<placeholder placeholderIdentifier="IBFirstResponder" id="nfr-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="-400" y="0"/>
</scene>
<scene sceneID="sc1-aa-aaa">
<objects>
<viewController id="vc1-aa-aaa" sceneMemberID="viewController">
<view key="view" contentMode="scaleToFill" id="vw1-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
</view>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#),
        ObservedDocument(name: "sb-nav-bar-frameless-no-device-at-15", path: "/tmp/Main.storyboard", target: "15.0", digest: "cf215c8d831fdef91c10f84f69eae0e99a1138f36ae27df3e77b52d5bb076a01", warnings: [], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="nvc-aa-aaa">
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
</dependencies>
<scenes>
<scene sceneID="nvs-aa-aaa">
<objects>
<navigationController id="nvc-aa-aaa" sceneMemberID="viewController">
<navigationBar key="navigationBar" contentMode="scaleToFill" id="nvb-aa-aaa">
<autoresizingMask key="autoresizingMask"/>
</navigationBar>
<connections>
<segue destination="vc1-aa-aaa" kind="relationship" relationship="rootViewController" id="rel-aa-aaa"/>
</connections>
</navigationController>
<placeholder placeholderIdentifier="IBFirstResponder" id="nfr-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="-400" y="0"/>
</scene>
<scene sceneID="sc1-aa-aaa">
<objects>
<viewController id="vc1-aa-aaa" sceneMemberID="viewController">
<view key="view" contentMode="scaleToFill" id="vw1-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
</view>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#),
        ObservedDocument(name: "nav-bar-sub-style-title-shadow", path: "/tmp/View.xib", target: "27.0", digest: "4ec5f696506600578f816dc5b03ecced9b5bd7def776d46e791b0530579e3d77", warnings: [], document: #"""
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
<navigationBar contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="nvb-aa-aa1">
<rect key="frame" x="0" y="0" width="393" height="64"/>
<items>
<navigationItem id="nvi-aa-aa1"/>
</items>
<textAttributes key="titleTextAttributes">
<color key="textColor" red="1" green="0" blue="0" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
<color key="textShadowColor" white="1" alpha="1" colorSpace="calibratedWhite"/>
<offsetWrapper key="textShadowOffset" horizontal="1" vertical="2"/>
</textAttributes>
</navigationBar>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "nav-bar-sub-style-shadow-image", path: "/tmp/View.xib", target: "27.0", digest: "5ea09b7554d60608dea61c20e86eeacecc951addb56e852a7715b85e30b17c83", warnings: [], document: #"""
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
<navigationBar contentMode="scaleToFill" shadowImage="Logo" translatesAutoresizingMaskIntoConstraints="NO" id="nvb-aa-aa1">
<rect key="frame" x="0" y="0" width="393" height="64"/>
<items>
<navigationItem id="nvi-aa-aa1"/>
</items>
</navigationBar>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "sb-nav-bar-title-empty", path: "/tmp/Main.storyboard", target: "27.0", digest: nil, warnings: [], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="nvc-aa-aaa">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
</dependencies>
<scenes>
<scene sceneID="nvs-aa-aaa">
<objects>
<navigationController id="nvc-aa-aaa" sceneMemberID="viewController">
<navigationBar key="navigationBar" contentMode="scaleToFill" id="nvb-aa-aaa">
<rect key="frame" x="0.0" y="59" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<textAttributes key="titleTextAttributes">
</textAttributes>
</navigationBar>
<connections>
<segue destination="vc1-aa-aaa" kind="relationship" relationship="rootViewController" id="rel-aa-aaa"/>
</connections>
</navigationController>
<placeholder placeholderIdentifier="IBFirstResponder" id="nfr-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="-400" y="0"/>
</scene>
<scene sceneID="sc1-aa-aaa">
<objects>
<viewController id="vc1-aa-aaa" sceneMemberID="viewController">
<view key="view" contentMode="scaleToFill" id="vw1-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
</view>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#),
        ObservedDocument(name: "sb-nav-bar-back-image", path: "/tmp/Main.storyboard", target: "27.0", digest: nil, warnings: [], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="nvc-aa-aaa">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
</dependencies>
<scenes>
<scene sceneID="nvs-aa-aaa">
<objects>
<navigationController id="nvc-aa-aaa" sceneMemberID="viewController">
<navigationBar key="navigationBar" contentMode="scaleToFill" backIndicatorImage="Logo" id="nvb-aa-aaa">
<rect key="frame" x="0.0" y="59" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
</navigationBar>
<connections>
<segue destination="vc1-aa-aaa" kind="relationship" relationship="rootViewController" id="rel-aa-aaa"/>
</connections>
</navigationController>
<placeholder placeholderIdentifier="IBFirstResponder" id="nfr-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="-400" y="0"/>
</scene>
<scene sceneID="sc1-aa-aaa">
<objects>
<viewController id="vc1-aa-aaa" sceneMemberID="viewController">
<view key="view" contentMode="scaleToFill" id="vw1-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
</view>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#),
        ObservedDocument(name: "sb-bar-kind-image-landscape", path: "/tmp/Main.storyboard", target: "27.0", digest: nil, warnings: [], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="nvc-aa-aaa">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
</dependencies>
<scenes>
<scene sceneID="nvs-aa-aaa">
<objects>
<navigationController id="nvc-aa-aaa" sceneMemberID="viewController">
<navigationBar key="navigationBar" contentMode="scaleToFill" id="nvb-aa-aaa">
<rect key="frame" x="0.0" y="59" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
</navigationBar>
<connections>
<segue destination="vc1-aa-aaa" kind="relationship" relationship="rootViewController" id="rel-aa-aaa"/>
</connections>
</navigationController>
<placeholder placeholderIdentifier="IBFirstResponder" id="nfr-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="-400" y="0"/>
</scene>
<scene sceneID="sc1-aa-aaa">
<objects>
<viewController id="vc1-aa-aaa" sceneMemberID="viewController">
<view key="view" contentMode="scaleToFill" id="vw1-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
</view>
<navigationItem key="navigationItem" title="T" id="nvi-aa-aaa">
<barButtonItem key="rightBarButtonItem" image="Logo" landscapeImagePhone="Logo" id="itm-aa-aaa"/>
</navigationItem>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#),
    ]
}
