import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes under a document's own `<deployment version>`, in binary-coded decimal
/// (`.github/scripts/nib_experiments.py` rounds 139 to 141): sizes and warnings by it, safe area guides dropped
/// below iOS 11 in xibs, and what would take a bundle or fail refused.
@Suite struct DocumentVersionTests {
    @Test(arguments: cases) func compilesAsXcode(_ document: ObservedDocument) throws {
        try document.check()
    }

    static func versioned(_ document: String, _ version: Int) -> String {
        document.replacingOccurrences(of: "</dependencies>", with: "<deployment version=\"\(version)\" identifier=\"iOS\"/>\n</dependencies>")
    }

    static let base0 = #"""
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
<rect key="frame" x="0" y="0" width="320" height="568"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<subviews>
<view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="sss-ss-ss1">
<rect key="frame" x="10" y="20" width="100" height="50"/>
</view>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#
    static let base1 = #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES">
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
</dependencies>
<objects>
<placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File's Owner"/>
<placeholder placeholderIdentifier="IBFirstResponder" id="-2" customClass="UIResponder"/>
<view contentMode="scaleToFill" id="iN0-l3-epB">
<rect key="frame" x="0" y="0" width="320" height="568"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<subviews>
<view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="sss-ss-ss1">
<rect key="frame" x="10" y="20" width="100" height="50"/>
</view>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#
    static let base2 = #"""
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
<rect key="frame" x="0.0" y="0.0" width="320" height="568"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<subviews>
<view contentMode="scaleToFill" id="sub-vi-ew1">
<rect key="frame" x="10" y="10" width="50" height="50"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
</view>
</subviews>
</view>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="dkx-z0-nzr" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#
    static let base3 = #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" useSafeAreas="YES" colorMatched="YES" initialViewController="BYZ-38-t0r">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
<capability name="Safe area layout guides" minToolsVersion="9.0"/>
</dependencies>
<scenes>
<scene sceneID="tne-QT-ifu">
<objects>
<viewController id="BYZ-38-t0r" sceneMemberID="viewController">
<layoutGuides>
<viewControllerLayoutGuide type="top" id="Llm-lL-Icb"/>
<viewControllerLayoutGuide type="bottom" id="xb3-aO-Qok"/>
</layoutGuides>
<view key="view" contentMode="scaleToFill" id="8bC-Xf-vdC">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<subviews>
<view contentMode="scaleToFill" id="sub-vi-ew1">
<rect key="frame" x="10" y="10" width="50" height="50"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
</view>
</subviews>
<viewLayoutGuide key="safeArea" id="6Tk-OE-BBY"/>
<constraints>
<constraint firstItem="sub-vi-ew1" firstAttribute="top" secondItem="Llm-lL-Icb" secondAttribute="bottom" constant="8" id="gtp-aa-aa1"/>
</constraints>
</view>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="dkx-z0-nzr" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#
    static let base4 = #"""
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
<connections>
<segue destination="vc2-aa-aaa" kind="push" identifier="B" id="zzz-aa-aaa"/>
<segue destination="vc2-aa-aaa" kind="push" identifier="A" id="aaa-zz-zzz"/>
</connections>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
<scene sceneID="sc2-aa-aaa">
<objects>
<viewController id="vc2-aa-aaa" sceneMemberID="viewController">
<view key="view" contentMode="scaleToFill" id="vw2-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
</view>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr2-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#
    static let base5 = #"""
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
<connections>
<segue destination="vc2-aa-aaa" kind="modal" identifier="B" id="aaa-zz-zzz"/>
<segue destination="vc2-aa-aaa" kind="push" identifier="A" id="zzz-aa-aaa"/>
</connections>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
<scene sceneID="sc2-aa-aaa">
<objects>
<viewController id="vc2-aa-aaa" sceneMemberID="viewController">
<view key="view" contentMode="scaleToFill" id="vw2-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
</view>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr2-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#
    static let base6 = #"""
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
<connections>
<segue destination="vc2-aa-aaa" kind="push" identifier="Mmm-aa-aaa" id="Mmm-aa-aaa"/>
<segue destination="vc2-aa-aaa" kind="push" identifier="zzz-aa-aaa" id="zzz-aa-aaa"/>
<segue destination="vc2-aa-aaa" kind="push" identifier="aaa-zz-zzz" id="aaa-zz-zzz"/>
<segue destination="vc2-aa-aaa" kind="push" identifier="Qx4-pp-k2L" id="Qx4-pp-k2L"/>
</connections>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
<scene sceneID="sc2-aa-aaa">
<objects>
<viewController id="vc2-aa-aaa" sceneMemberID="viewController">
<view key="view" contentMode="scaleToFill" id="vw2-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
</view>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr2-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#
    static let base7 = #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" useSafeAreas="YES" colorMatched="YES">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="Safe area layout guides" minToolsVersion="9.0"/>
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
</view>
</subviews>
<viewLayoutGuide key="safeArea" id="vUN-kp-3ea"/>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#
    static let base8 = #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" useSafeAreas="YES" colorMatched="YES">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="Safe area layout guides" minToolsVersion="9.0"/>
<capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
</dependencies>
<objects>
<placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File's Owner"/>
<placeholder placeholderIdentifier="IBFirstResponder" id="-2" customClass="UIResponder"/>
<tableViewCell contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" customClass="Cell" customModule="T" customModuleProvider="target" id="KGk-i7-Jjw">
<rect key="frame" x="0.0" y="0.0" width="320" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="KGk-i7-Jjw" id="H2p-sc-9uM">
<rect key="frame" x="0.0" y="0.0" width="320" height="44"/>
<autoresizingMask key="autoresizingMask"/>
</tableViewCellContentView>
<viewLayoutGuide key="safeArea" id="njF-e1-oar"/>
<point key="canvasLocation" x="0" y="0"/>
</tableViewCell>
</objects>
</document>
"""#
    static let base9 = #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" useSafeAreas="YES" colorMatched="YES">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="Safe area layout guides" minToolsVersion="9.0"/>
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
<viewLayoutGuide key="safeArea" id="sss-gd-sf1"/>
</view>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#
    static let base10 = #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" useSafeAreas="YES" colorMatched="YES">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="Safe area layout guides" minToolsVersion="9.0"/>
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
</view>
</subviews>
<viewLayoutGuide key="safeArea" id="vUN-kp-3ea"/>
<constraints>
<constraint firstItem="sss-ss-ss1" firstAttribute="top" secondItem="vUN-kp-3ea" secondAttribute="top" id="c00-aa-aaa"/>
</constraints>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#
    static let base11 = #"""
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
<color key="backgroundColor" name="Accent"/>
</view>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
<resources>
<namedColor name="Accent">
<color red="1" green="0" blue="0" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
</namedColor>
</resources>
</document>
"""#
    static let base12 = #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" useSafeAreas="YES" colorMatched="YES" initialViewController="BYZ-38-t0r">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
<capability name="Safe area layout guides" minToolsVersion="9.0"/>
</dependencies>
<scenes>
<scene sceneID="tne-QT-ifu">
<objects>
<viewController id="BYZ-38-t0r" sceneMemberID="viewController">
<layoutGuides>
<viewControllerLayoutGuide type="top" id="Llm-lL-Icb"/>
<viewControllerLayoutGuide type="bottom" id="xb3-aO-Qok"/>
</layoutGuides>
<view key="view" contentMode="scaleToFill" id="8bC-Xf-vdC">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<subviews>
<view contentMode="scaleToFill" id="sub-vi-ew1">
<rect key="frame" x="10" y="10" width="50" height="50"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
</view>
</subviews>
<viewLayoutGuide key="safeArea" id="6Tk-OE-BBY"/>
</view>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="dkx-z0-nzr" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#
    static let base13 = #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" useSafeAreas="YES" colorMatched="YES" initialViewController="BYZ-38-t0r">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
<capability name="Safe area layout guides" minToolsVersion="9.0"/>
</dependencies>
<scenes>
<scene sceneID="tne-QT-ifu">
<objects>
<viewController id="BYZ-38-t0r" sceneMemberID="viewController">
<layoutGuides>
<viewControllerLayoutGuide type="top" id="Llm-lL-Icb"/>
<viewControllerLayoutGuide type="bottom" id="xb3-aO-Qok"/>
</layoutGuides>
<view key="view" contentMode="scaleToFill" id="8bC-Xf-vdC">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<subviews>
<view contentMode="scaleToFill" id="sub-vi-ew1">
<rect key="frame" x="10" y="10" width="50" height="50"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
</view>
</subviews>
<viewLayoutGuide key="safeArea" id="6Tk-OE-BBY"/>
<constraints>
<constraint firstItem="sub-vi-ew1" firstAttribute="top" secondItem="6Tk-OE-BBY" secondAttribute="top" id="gsa-aa-aa1"/>
</constraints>
</view>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="dkx-z0-nzr" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#
    static let base14 = #"""
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
<view contentMode="scaleToFill" id="sub-vi-ew1">
<rect key="frame" x="10" y="10" width="50" height="50"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
</view>
</subviews>
<color key="backgroundColor" name="Accent"/>
</view>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="dkx-z0-nzr" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
<resources>
<namedColor name="Accent">
<color red="1" green="0" blue="0" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
</namedColor>
</resources>
</document>
"""#

    static let cases = [
        ObservedDocument(name: "docversion-1000", path: "/tmp/View.xib", target: "27.0", digest: "f656183e6e3a29a51ff1b04554564a7464b0f95b9eeaf34c0d58556f00ab8a80", warnings: [], document: versioned(base0, 0x1000)),
        ObservedDocument(name: "docversion-1640", path: "/tmp/View.xib", target: "27.0", digest: "f656183e6e3a29a51ff1b04554564a7464b0f95b9eeaf34c0d58556f00ab8a80", warnings: [], document: versioned(base0, 0x1640)),
        ObservedDocument(name: "docversion-1700", path: "/tmp/View.xib", target: "27.0", digest: "25a7b1123090aa0f3d8095eb21e09ec0f13b3a3647f045597dc17633be22ea44", warnings: [], document: versioned(base0, 0x1700)),
        ObservedDocument(name: "docversion-1500-at-15", path: "/tmp/View.xib", target: "15.0", digest: "f656183e6e3a29a51ff1b04554564a7464b0f95b9eeaf34c0d58556f00ab8a80", warnings: [], document: versioned(base0, 0x1500)),
        ObservedDocument(name: "docversion-deviceless-1500", path: "/tmp/View.xib", target: "27.0", digest: "a869a985f6d460ae4657f2c1dadbc688beeae6492e6ab2ee6559a6876e1c7817", warnings: [], document: versioned(base1, 0x1500)),
        ObservedDocument(name: "docversion-deviceless-1700", path: "/tmp/View.xib", target: "27.0", digest: "25a7b1123090aa0f3d8095eb21e09ec0f13b3a3647f045597dc17633be22ea44", warnings: [], document: versioned(base1, 0x1700)),
        ObservedDocument(name: "sb-docversion-1500", path: "/tmp/Main.storyboard", target: "27.0", digest: "011d0f56b312d1b8528b4634d6873d5ee1a0c279024c82f03740c44b36b4ded0", warnings: ["/tmp/Main.storyboard:global: warning: This file is set to build for a version older than the deployment target. Functionality may be limited. [9]"], document: versioned(base2, 0x1500)),
        ObservedDocument(name: "sb-docversion-1500-at-15", path: "/tmp/Main.storyboard", target: "15.0", digest: "011d0f56b312d1b8528b4634d6873d5ee1a0c279024c82f03740c44b36b4ded0", warnings: [], document: versioned(base2, 0x1500)),
        ObservedDocument(name: "sb-docversion-1640", path: "/tmp/Main.storyboard", target: "27.0", digest: "011d0f56b312d1b8528b4634d6873d5ee1a0c279024c82f03740c44b36b4ded0", warnings: ["/tmp/Main.storyboard:global: warning: This file is set to build for a version older than the deployment target. Functionality may be limited. [9]"], document: versioned(base2, 0x1640)),
        ObservedDocument(name: "sb-docversion-1700", path: "/tmp/Main.storyboard", target: "27.0", digest: "011d0f56b312d1b8528b4634d6873d5ee1a0c279024c82f03740c44b36b4ded0", warnings: [], document: versioned(base2, 0x1700)),
        ObservedDocument(name: "sb-docversion-1b00-at-15", path: "/tmp/Main.storyboard", target: "15.0", digest: "011d0f56b312d1b8528b4634d6873d5ee1a0c279024c82f03740c44b36b4ded0", warnings: [], document: versioned(base2, 0x1b00)),
        ObservedDocument(name: "sb-docversion-1000-at-15", path: "/tmp/Main.storyboard", target: "15.0", digest: "011d0f56b312d1b8528b4634d6873d5ee1a0c279024c82f03740c44b36b4ded0", warnings: ["/tmp/Main.storyboard:global: warning: This file is set to build for a version older than the deployment target. Functionality may be limited. [9]"], document: versioned(base2, 0x1000)),
        ObservedDocument(name: "sb-warn-guide-docversion-0900", path: "/tmp/Main.storyboard", target: "27.0", digest: "f32beca1f86686e6aa515935f13af5c1c625a9cfaf8f600f2d6ae4754ff7ac4c", warnings: ["/tmp/Main.storyboard:global: warning: This file is set to build for a version older than the deployment target. Functionality may be limited. [9]"], document: versioned(base3, 0x0900)),
        ObservedDocument(name: "sb-warn-guide-docversion-1100", path: "/tmp/Main.storyboard", target: "27.0", digest: "f32beca1f86686e6aa515935f13af5c1c625a9cfaf8f600f2d6ae4754ff7ac4c", warnings: ["/tmp/Main.storyboard:global: warning: This file is set to build for a version older than the deployment target. Functionality may be limited. [9]", "/tmp/Main.storyboard:8bC-Xf-vdC: warning: Top layout guide is deprecated since iOS 11.0 [7]"], document: versioned(base3, 0x1100)),
        ObservedDocument(name: "sb-warn-guide-docversion-1500", path: "/tmp/Main.storyboard", target: "27.0", digest: "f32beca1f86686e6aa515935f13af5c1c625a9cfaf8f600f2d6ae4754ff7ac4c", warnings: ["/tmp/Main.storyboard:global: warning: This file is set to build for a version older than the deployment target. Functionality may be limited. [9]", "/tmp/Main.storyboard:8bC-Xf-vdC: warning: Top layout guide is deprecated since iOS 11.0 [7]"], document: versioned(base3, 0x1500)),
        ObservedDocument(name: "sb-warn-guide-docversion-1700", path: "/tmp/Main.storyboard", target: "27.0", digest: "f32beca1f86686e6aa515935f13af5c1c625a9cfaf8f600f2d6ae4754ff7ac4c", warnings: ["/tmp/Main.storyboard:8bC-Xf-vdC: warning: Top layout guide is deprecated since iOS 11.0 [7]"], document: versioned(base3, 0x1700)),
        ObservedDocument(name: "sb-segue-push-two-docversion-1500", path: "/tmp/Main.storyboard", target: "27.0", digest: "f7a89743055b87f6ac7a6ad230b198bbc926818254923366cacc35c0d28664be", warnings: ["/tmp/Main.storyboard:global: warning: This file is set to build for a version older than the deployment target. Functionality may be limited. [9]", "/tmp/Main.storyboard:aaa-zz-zzz: warning: Push segues are deprecated since iOS 8.0 [7]", "/tmp/Main.storyboard:zzz-aa-aaa: warning: Push segues are deprecated since iOS 8.0 [7]"], document: versioned(base4, 0x1500)),
        ObservedDocument(name: "sb-segue-modal-push-docversion-1500", path: "/tmp/Main.storyboard", target: "27.0", digest: "3876a35c5cfeb62b5ac13f5dd42a336e4d4835550e3fc6a4454aa6e6b18b18f8", warnings: ["/tmp/Main.storyboard:global: warning: This file is set to build for a version older than the deployment target. Functionality may be limited. [9]", "/tmp/Main.storyboard:zzz-aa-aaa: warning: Push segues are deprecated since iOS 8.0 [7]", "/tmp/Main.storyboard:aaa-zz-zzz: warning: Modal segues are deprecated since iOS 8.0 [7]"], document: versioned(base5, 0x1500)),
        ObservedDocument(name: "sb-segue-push-three-docversion-0900", path: "/tmp/Main.storyboard", target: "27.0", digest: "96fe1581ddcd64caebb060992d5bd3fb5995ba80bc5be039d88c1a2340f9e57b", warnings: ["/tmp/Main.storyboard:global: warning: This file is set to build for a version older than the deployment target. Functionality may be limited. [9]", "/tmp/Main.storyboard:zzz-aa-aaa: warning: Push segues are deprecated since iOS 8.0 [7]", "/tmp/Main.storyboard:aaa-zz-zzz: warning: Push segues are deprecated since iOS 8.0 [7]", "/tmp/Main.storyboard:Mmm-aa-aaa: warning: Push segues are deprecated since iOS 8.0 [7]", "/tmp/Main.storyboard:Qx4-pp-k2L: warning: Push segues are deprecated since iOS 8.0 [7]"], document: versioned(base6, 0x0900)),
        ObservedDocument(name: "docbundle-safe-0900", path: "/tmp/View.xib", target: "27.0", digest: "f656183e6e3a29a51ff1b04554564a7464b0f95b9eeaf34c0d58556f00ab8a80", warnings: [], document: versioned(base7, 0x0900)),
        ObservedDocument(name: "docbundle-safe-1000", path: "/tmp/View.xib", target: "27.0", digest: "f656183e6e3a29a51ff1b04554564a7464b0f95b9eeaf34c0d58556f00ab8a80", warnings: [], document: versioned(base7, 0x1000)),
        ObservedDocument(name: "docbundle-safe-1100", path: "/tmp/View.xib", target: "27.0", digest: "226b9876fdef5306bc1651983730adfe73e1459b6da0c15f902486949a9880fd", warnings: [], document: versioned(base7, 0x1100)),
        ObservedDocument(name: "docbundle-safe-1b00", path: "/tmp/View.xib", target: "27.0", digest: "226b9876fdef5306bc1651983730adfe73e1459b6da0c15f902486949a9880fd", warnings: [], document: versioned(base7, 0x1b00)),
        ObservedDocument(name: "docbundle-safe-cell-0930", path: "/tmp/View.xib", target: "27.0", digest: "f14854a81d07d269af8151ddc8edc0a6f315be9828e415f256b05e6635c7ef97", warnings: [], document: versioned(base8, 0x0930)),
        ObservedDocument(name: "docbundle-safe-subview-1000", path: "/tmp/View.xib", target: "27.0", digest: "f656183e6e3a29a51ff1b04554564a7464b0f95b9eeaf34c0d58556f00ab8a80", warnings: [], document: versioned(base9, 0x1000)),
        ObservedDocument(name: "docbundle-safe-pinned-1100", path: "/tmp/View.xib", target: "27.0", digest: "f4f1078f58bddd1563907b9840f4dbc3313b21af5a3c6ff0a02bc258981d614f", warnings: [], document: versioned(base10, 0x1100)),
        ObservedDocument(name: "docbundle-named-1300", path: "/tmp/View.xib", target: "27.0", digest: "7cebdf71a30f4bcbcc7c02d23235dac56847cfdb6d5ec588ab728303bbe2dede", warnings: [], document: versioned(base11, 0x1300)),
        ObservedDocument(name: "sb-docbundle-safe-1000", path: "/tmp/Main.storyboard", target: "27.0", digest: "82ff037aead0a0acd68a8f2340469380f5d9eef6aa52995350493f93a1a56ae2", warnings: ["/tmp/Main.storyboard:global: warning: This file is set to build for a version older than the deployment target. Functionality may be limited. [9]"], document: versioned(base12, 0x1000)),
        ObservedDocument(name: "sb-docbundle-safe-pinned-1100", path: "/tmp/Main.storyboard", target: "27.0", digest: "cc918ffdda1c9a0620a99921129e6f27f092b66c958a9f5934f8e707378f5db1", warnings: ["/tmp/Main.storyboard:global: warning: This file is set to build for a version older than the deployment target. Functionality may be limited. [9]"], document: versioned(base13, 0x1100)),
        ObservedDocument(name: "sb-docbundle-named-1300", path: "/tmp/Main.storyboard", target: "27.0", digest: "53e8d03b9bb08d9ce04b063b8bf867611492ea58a72c203ed3683243c485f08f", warnings: ["/tmp/Main.storyboard:global: warning: This file is set to build for a version older than the deployment target. Functionality may be limited. [9]"], document: versioned(base14, 0x1300)),
        ObservedDocument(name: "docbundle-safe-0800", path: "/tmp/View.xib", target: "27.0", digest: nil, warnings: [], document: versioned(base7, 0x0800)),
        ObservedDocument(name: "docbundle-safe-pinned-1000", path: "/tmp/View.xib", target: "27.0", digest: nil, warnings: [], document: versioned(base10, 0x1000)),
        ObservedDocument(name: "docbundle-named-1000", path: "/tmp/View.xib", target: "27.0", digest: nil, warnings: [], document: versioned(base11, 0x1000)),
        ObservedDocument(name: "docbundle-named-1100", path: "/tmp/View.xib", target: "27.0", digest: nil, warnings: [], document: versioned(base11, 0x1100)),
        ObservedDocument(name: "docbundle-named-1220", path: "/tmp/View.xib", target: "27.0", digest: nil, warnings: [], document: versioned(base11, 0x1220)),
        ObservedDocument(name: "sb-docbundle-safe-pinned-0930", path: "/tmp/Main.storyboard", target: "27.0", digest: nil, warnings: [], document: versioned(base13, 0x0930)),
        ObservedDocument(name: "sb-docbundle-named-1220", path: "/tmp/Main.storyboard", target: "27.0", digest: nil, warnings: [], document: versioned(base14, 0x1220)),
    ]
}
