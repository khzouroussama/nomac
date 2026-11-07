import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// A table's header and footer views and what an embedded controller's segues reach, as ibtool (Xcode 27.0) lays them out
/// (`.github/scripts/nib_experiments.py` rounds 155 and 156).
@Suite struct TableViewHeaderTests {
    @Test(arguments: cases) func compilesAsXcode(_ document: ObservedDocument) throws {
        try document.check()
    }

    static let cases = [
        ObservedDocument(name: "sb-table-view-both", path: "/tmp/Main.storyboard", target: "27.0", digest: "a6b5f0908a7bdbc336b38e4323e07bd83f9c782001972b60d1e2a852e4a35f41", warnings: [], document: #"""
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
<view key="tableHeaderView" contentMode="scaleToFill" id="hdr-aa-aaa">
<rect key="frame" x="0.0" y="0" width="393" height="34"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
</view>
<view key="tableFooterView" contentMode="scaleToFill" id="ftr-aa-aaa">
<rect key="frame" x="0.0" y="78" width="393" height="34"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
</view>
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
        ObservedDocument(name: "sb-table-view-footer-first", path: "/tmp/Main.storyboard", target: "27.0", digest: "a6b5f0908a7bdbc336b38e4323e07bd83f9c782001972b60d1e2a852e4a35f41", warnings: [], document: #"""
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
<view key="tableFooterView" contentMode="scaleToFill" id="ftr-aa-aaa">
<rect key="frame" x="0.0" y="78" width="393" height="34"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
</view>
<view key="tableHeaderView" contentMode="scaleToFill" id="hdr-aa-aaa">
<rect key="frame" x="0.0" y="0" width="393" height="34"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
</view>
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
        ObservedDocument(name: "sb-table-view-header-label", path: "/tmp/Main.storyboard", target: "27.0", digest: "fd6228e0c5109f48921578bfc90ebdf51d1f4db45c7031ee9371c9592d605858", warnings: [], document: #"""
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
<view key="tableHeaderView" contentMode="scaleToFill" id="hdr-aa-aaa">
<rect key="frame" x="0.0" y="0" width="393" height="34"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
<subviews>
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" text="L" fixedFrame="YES" translatesAutoresizingMaskIntoConstraints="NO" id="hlb-aa-aaa">
<rect key="frame" x="0" y="0" width="10" height="10"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
<fontDescription key="fontDescription" type="system" pointSize="17"/>
</label>
</subviews>
</view>
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
        ObservedDocument(name: "sb-table-view-header-pinned", path: "/tmp/Main.storyboard", target: "27.0", digest: "a64ee766ecf7b997709355d1469df9720e42be62491afffbc62eedf63d9c84ca", warnings: [], document: #"""
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
<view key="tableHeaderView" contentMode="scaleToFill" id="hdr-aa-aaa">
<rect key="frame" x="0.0" y="0" width="393" height="34"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
<subviews>
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" text="L" translatesAutoresizingMaskIntoConstraints="NO" id="hlb-aa-aaa">
<rect key="frame" x="0" y="0" width="10" height="10"/>
<fontDescription key="fontDescription" type="system" pointSize="17"/>
</label>
</subviews>
<constraints>
<constraint firstItem="hlb-aa-aaa" firstAttribute="top" secondItem="hdr-aa-aaa" secondAttribute="top" id="hct-aa-aaa"/>
</constraints>
</view>
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
        ObservedDocument(name: "sb-table-view-proto-both", path: "/tmp/Main.storyboard", target: "27.0", digest: "f26682da1b43ee3203dd73c9a98cc0bb0fd5ff576e8b7fa5ff43e732d427825d", warnings: [], document: #"""
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
<view key="tableHeaderView" contentMode="scaleToFill" id="hdr-aa-aaa">
<rect key="frame" x="0.0" y="0" width="393" height="34"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
</view>
<view key="tableFooterView" contentMode="scaleToFill" id="ftr-aa-aaa">
<rect key="frame" x="0.0" y="78" width="393" height="34"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
</view>
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
        ObservedDocument(name: "sb-table-view-static-both", path: "/tmp/Main.storyboard", target: "27.0", digest: "42115735a7de60e707dda3ccea5c354d33fbce3bd3376e623d2b0bf359126a3c", warnings: [], document: #"""
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
<tableView key="view" clipsSubviews="YES" contentMode="scaleToFill" alwaysBounceVertical="YES" dataMode="static" style="plain" separatorStyle="default" rowHeight="-1" estimatedRowHeight="-1" sectionHeaderHeight="28" sectionFooterHeight="28" id="tbv-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<view key="tableHeaderView" contentMode="scaleToFill" id="hdr-aa-aaa">
<rect key="frame" x="0.0" y="0" width="393" height="34"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
</view>
<view key="tableFooterView" contentMode="scaleToFill" id="ftr-aa-aaa">
<rect key="frame" x="0.0" y="78" width="393" height="34"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
</view>
<sections>
<tableViewSection id="sec-aa-aa1">
<cells>
<tableViewCell clipsSubviews="YES" contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" id="cel-aa-aa1">
<rect key="frame" x="0.0" y="0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="cel-aa-aa1" id="ccv-aa-aa1">
<rect key="frame" x="0.0" y="0.0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
</tableViewCellContentView>
</tableViewCell>
</cells>
</tableViewSection>
</sections>
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
        ObservedDocument(name: "sb-table-view-colored-both", path: "/tmp/Main.storyboard", target: "27.0", digest: "621d59c9c893c59c0e3eaa9027055ae3c85edba4c0dcaebff4921a14ef080507", warnings: [], document: #"""
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
<color key="separatorColor" red="1" green="0" blue="0" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
<view key="tableHeaderView" contentMode="scaleToFill" id="hdr-aa-aaa">
<rect key="frame" x="0.0" y="0" width="393" height="34"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
</view>
<view key="tableFooterView" contentMode="scaleToFill" id="ftr-aa-aaa">
<rect key="frame" x="0.0" y="78" width="393" height="34"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
</view>
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
        ObservedDocument(name: "sb-table-header-frame-narrow-label", path: "/tmp/Main.storyboard", target: "27.0", digest: "fd6228e0c5109f48921578bfc90ebdf51d1f4db45c7031ee9371c9592d605858", warnings: [], document: #"""
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
<view key="tableHeaderView" contentMode="scaleToFill" id="hdr-aa-aaa">
<rect key="frame" x="0.0" y="0" width="100" height="34"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
<subviews>
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" text="L" fixedFrame="YES" translatesAutoresizingMaskIntoConstraints="NO" id="hlb-aa-aaa">
<rect key="frame" x="0" y="0" width="10" height="10"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
<fontDescription key="fontDescription" type="system" pointSize="17"/>
</label>
</subviews>
</view>
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
        ObservedDocument(name: "sb-table-header-frame-x-y", path: "/tmp/Main.storyboard", target: "27.0", digest: "4738ab3ce3650f119b863a32b85152731d5606988f48871dcd92aad1317b0586", warnings: [], document: #"""
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
<view key="tableHeaderView" contentMode="scaleToFill" id="hdr-aa-aaa">
<rect key="frame" x="20" y="40" width="393" height="34"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
</view>
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
        ObservedDocument(name: "sb-table-footer-frame-x", path: "/tmp/Main.storyboard", target: "27.0", digest: "2fb71823b8ca9b9ba87e14c0feaf78c7de4fb53078b842901955d1e421d685fc", warnings: [], document: #"""
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
<view key="tableFooterView" contentMode="scaleToFill" id="ftr-aa-aaa">
<rect key="frame" x="30" y="78" width="393" height="34"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
</view>
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
        ObservedDocument(name: "sb-table-footer-frame-narrow", path: "/tmp/Main.storyboard", target: "27.0", digest: "0af1631895609ac25e7a1fa92fe36be20ec518a290e86bed7fcc676cece0bf36", warnings: [], document: #"""
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
<view key="tableFooterView" contentMode="scaleToFill" id="ftr-aa-aaa">
<rect key="frame" x="0.0" y="78" width="100" height="34"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
</view>
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
        ObservedDocument(name: "sb-table-footer-grouped-static-2", path: "/tmp/Main.storyboard", target: "27.0", digest: "3ab3c439d7c7fdbc304752406ea133a6c70298ffc9f910f7d40285ae88d4dd1c", warnings: [], document: #"""
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
<tableView key="view" clipsSubviews="YES" contentMode="scaleToFill" alwaysBounceVertical="YES" dataMode="static" style="grouped" separatorStyle="default" rowHeight="-1" estimatedRowHeight="-1" sectionHeaderHeight="18" sectionFooterHeight="18" id="tbv-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<view key="tableFooterView" contentMode="scaleToFill" id="ftr-aa-aaa">
<rect key="frame" x="0.0" y="400" width="393" height="44"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
</view>
<sections>
<tableViewSection id="sec-aa-a0">
<cells>
<tableViewCell clipsSubviews="YES" contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" id="cel-aa-aa0">
<rect key="frame" x="0.0" y="0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="cel-aa-aa0" id="ccv-aa-aa0">
<rect key="frame" x="0.0" y="0.0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
</tableViewCellContentView>
</tableViewCell>
<tableViewCell clipsSubviews="YES" contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" id="cel-aa-aa1">
<rect key="frame" x="0.0" y="0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="cel-aa-aa1" id="ccv-aa-aa1">
<rect key="frame" x="0.0" y="0.0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
</tableViewCellContentView>
</tableViewCell>
</cells>
</tableViewSection>
</sections>
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
        ObservedDocument(name: "sb-table-footer-grouped-header", path: "/tmp/Main.storyboard", target: "27.0", digest: "039a4731ce3d3a37a0d73bd2e7d77772be0dca9b1de9097f4265f9854e6ae229", warnings: [], document: #"""
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
<tableView key="view" clipsSubviews="YES" contentMode="scaleToFill" alwaysBounceVertical="YES" dataMode="prototypes" style="grouped" separatorStyle="default" rowHeight="-1" estimatedRowHeight="-1" sectionHeaderHeight="18" sectionFooterHeight="18" id="tbv-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<view key="tableHeaderView" contentMode="scaleToFill" id="hdr-aa-aaa">
<rect key="frame" x="0.0" y="0" width="393" height="34"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
</view>
<view key="tableFooterView" contentMode="scaleToFill" id="ftr-aa-aaa">
<rect key="frame" x="0.0" y="400" width="393" height="44"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
</view>
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
        ObservedDocument(name: "sb-table-footer-grouped-heights", path: "/tmp/Main.storyboard", target: "27.0", digest: "1b9a25fcfa6a25d8944f95ca09e6a2b85ac66eb91f2bc68ea0ac4be654d2138f", warnings: [], document: #"""
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
<tableView key="view" clipsSubviews="YES" contentMode="scaleToFill" alwaysBounceVertical="YES" dataMode="prototypes" style="grouped" separatorStyle="default" rowHeight="-1" estimatedRowHeight="-1" sectionHeaderHeight="30" sectionFooterHeight="30" id="tbv-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<view key="tableFooterView" contentMode="scaleToFill" id="ftr-aa-aaa">
<rect key="frame" x="0.0" y="400" width="393" height="44"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
</view>
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
        ObservedDocument(name: "sb-table-footer-grouped-footer-height", path: "/tmp/Main.storyboard", target: "27.0", digest: "257cc00430bb4c60cce1034064aaff40ae687d880d3a103b4150c4cad3f3b014", warnings: [], document: #"""
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
<tableView key="view" clipsSubviews="YES" contentMode="scaleToFill" alwaysBounceVertical="YES" dataMode="prototypes" style="grouped" separatorStyle="default" rowHeight="-1" estimatedRowHeight="-1" sectionHeaderHeight="18" sectionFooterHeight="40" id="tbv-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<view key="tableFooterView" contentMode="scaleToFill" id="ftr-aa-aaa">
<rect key="frame" x="0.0" y="400" width="393" height="44"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
</view>
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
        ObservedDocument(name: "sb-table-footer-plain-static-3", path: "/tmp/Main.storyboard", target: "27.0", digest: "df0cbbe1031df5de42d0370aaa47dcfdc6030fdf9e3e2a610fbbd5fed42f0b7a", warnings: [], document: #"""
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
<tableView key="view" clipsSubviews="YES" contentMode="scaleToFill" alwaysBounceVertical="YES" dataMode="static" style="plain" separatorStyle="default" rowHeight="-1" estimatedRowHeight="-1" sectionHeaderHeight="28" sectionFooterHeight="28" id="tbv-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<view key="tableFooterView" contentMode="scaleToFill" id="ftr-aa-aaa">
<rect key="frame" x="0.0" y="400" width="393" height="44"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
</view>
<sections>
<tableViewSection id="sec-aa-a0">
<cells>
<tableViewCell clipsSubviews="YES" contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" id="cel-aa-aa0">
<rect key="frame" x="0.0" y="0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="cel-aa-aa0" id="ccv-aa-aa0">
<rect key="frame" x="0.0" y="0.0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
</tableViewCellContentView>
</tableViewCell>
<tableViewCell clipsSubviews="YES" contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" id="cel-aa-aa1">
<rect key="frame" x="0.0" y="0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="cel-aa-aa1" id="ccv-aa-aa1">
<rect key="frame" x="0.0" y="0.0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
</tableViewCellContentView>
</tableViewCell>
<tableViewCell clipsSubviews="YES" contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" id="cel-aa-aa2">
<rect key="frame" x="0.0" y="0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="cel-aa-aa2" id="ccv-aa-aa2">
<rect key="frame" x="0.0" y="0.0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
</tableViewCellContentView>
</tableViewCell>
</cells>
</tableViewSection>
</sections>
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
        ObservedDocument(name: "sb-embed-nav-push-push", path: "/tmp/Main.storyboard", target: "27.0", digest: "3aca7ff1d5ed7bc35f4c301fab5dc6dc9184b404cdbe7840d963770341669dc1", warnings: ["/tmp/Main.storyboard:psh-aa-aa1: warning: Push segues are deprecated since iOS 8.0 [7]", "/tmp/Main.storyboard:psh-aa-aa2: warning: Push segues are deprecated since iOS 8.0 [7]"], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="vc9-aa-aaa">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
</dependencies>
<scenes>
<scene sceneID="sc9-aa-aaa">
<objects>
<viewController id="vc9-aa-aaa" sceneMemberID="viewController">
<view key="view" contentMode="scaleToFill" id="vw9-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<subviews>
<containerView opaque="NO" contentMode="scaleToFill" id="cnt-aa-aa1">
<rect key="frame" x="20" y="100" width="200" height="300"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
<connections>
<segue destination="nvc-aa-aaa" kind="embed" id="emb-aa-aaa"/>
</connections>
</containerView>
</subviews>
</view>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr9-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
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
<rect key="frame" x="0.0" y="0.0" width="449" height="485"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
</view>
<connections>
<segue destination="vc2-aa-aaa" kind="push" identifier="N1" id="psh-aa-aa1"/>
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
<rect key="frame" x="0.0" y="0.0" width="449" height="485"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
</view>
<connections>
<segue destination="vc3-aa-aaa" kind="push" identifier="N2" id="psh-aa-aa2"/>
</connections>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr2-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
<scene sceneID="sc3-aa-aaa">
<objects>
<viewController id="vc3-aa-aaa" sceneMemberID="viewController">
<view key="view" contentMode="scaleToFill" id="vw3-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="449" height="485"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
</view>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr3-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#),
        ObservedDocument(name: "sb-embed-nav-presentation-show", path: "/tmp/Main.storyboard", target: "27.0", digest: "ba6a9191f9256c2c74e667d57788fd8d469f117bc246dbab02dec44cc0f1b859", warnings: [], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="vc9-aa-aaa">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
</dependencies>
<scenes>
<scene sceneID="sc9-aa-aaa">
<objects>
<viewController id="vc9-aa-aaa" sceneMemberID="viewController">
<view key="view" contentMode="scaleToFill" id="vw9-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<subviews>
<containerView opaque="NO" contentMode="scaleToFill" id="cnt-aa-aa1">
<rect key="frame" x="20" y="100" width="200" height="300"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
<connections>
<segue destination="nvc-aa-aaa" kind="embed" id="emb-aa-aaa"/>
</connections>
</containerView>
</subviews>
</view>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr9-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
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
<rect key="frame" x="0.0" y="0.0" width="449" height="485"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
</view>
<connections>
<segue destination="vc2-aa-aaa" kind="presentation" identifier="N1" id="psh-aa-aa1"/>
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
<rect key="frame" x="0.0" y="0.0" width="449" height="485"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
</view>
<connections>
<segue destination="vc3-aa-aaa" kind="show" identifier="N2" id="psh-aa-aa2"/>
</connections>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr2-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
<scene sceneID="sc3-aa-aaa">
<objects>
<viewController id="vc3-aa-aaa" sceneMemberID="viewController">
<view key="view" contentMode="scaleToFill" id="vw3-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="449" height="485"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
</view>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr3-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#),
    ]
}
