import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for the shapes that came out different on the survey's documents
/// (`.github/scripts/nib_experiments.py` rounds 135 to 138 and 142).
@Suite struct SurveyShapeTests {
    @Test(arguments: cases) func compilesAsXcode(_ document: ObservedDocument) throws {
        try document.check()
    }

    static let cases = [
        ObservedDocument(name: "table-estimated-row-half", path: "/tmp/View.xib", target: "27.0", digest: "2d5aa19caaf29106773a20c4eae0e8c0b50cb3b64c2f16e0b085da1871512332", warnings: [], document: #"""
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
<tableView clipsSubviews="YES" contentMode="scaleToFill" alwaysBounceVertical="YES" style="plain" separatorStyle="default" rowHeight="-1" estimatedRowHeight="0.5" sectionHeaderHeight="28" sectionFooterHeight="28" translatesAutoresizingMaskIntoConstraints="NO" id="tbl-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
</tableView>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "table-estimated-header-0", path: "/tmp/View.xib", target: "27.0", digest: "2d08c70fa6bf1c3db4fcb32d178afd43072cf1e11fad90b2efc1113135d94f60", warnings: [], document: #"""
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
<tableView clipsSubviews="YES" contentMode="scaleToFill" alwaysBounceVertical="YES" style="plain" separatorStyle="default" rowHeight="-1" estimatedRowHeight="-1" sectionHeaderHeight="28" sectionFooterHeight="28" estimatedSectionHeaderHeight="0" translatesAutoresizingMaskIntoConstraints="NO" id="tbl-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
</tableView>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "table-estimated-footer-0", path: "/tmp/View.xib", target: "27.0", digest: "2d08c70fa6bf1c3db4fcb32d178afd43072cf1e11fad90b2efc1113135d94f60", warnings: [], document: #"""
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
<tableView clipsSubviews="YES" contentMode="scaleToFill" alwaysBounceVertical="YES" style="plain" separatorStyle="default" rowHeight="-1" estimatedRowHeight="-1" sectionHeaderHeight="28" sectionFooterHeight="28" estimatedSectionFooterHeight="0" translatesAutoresizingMaskIntoConstraints="NO" id="tbl-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
</tableView>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "table-readable", path: "/tmp/View.xib", target: "27.0", digest: "0d8ec6ed3a2b6aa0cd92b9e1597abb0d6ecd5a92c364033d673d207025c8244c", warnings: [], document: #"""
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
<tableView clipsSubviews="YES" contentMode="scaleToFill" alwaysBounceVertical="YES" style="plain" separatorStyle="default" rowHeight="-1" estimatedRowHeight="-1" sectionHeaderHeight="28" sectionFooterHeight="28" layoutMarginsFollowReadableWidth="YES" translatesAutoresizingMaskIntoConstraints="NO" id="tbl-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
</tableView>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "table-separator-inset", path: "/tmp/View.xib", target: "27.0", digest: "ca27b94fe77e6133bff5c2195a9f74ae1dfe6660e3337984cf22041bb2b33db1", warnings: [], document: #"""
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
<tableView clipsSubviews="YES" contentMode="scaleToFill" alwaysBounceVertical="YES" style="plain" separatorStyle="default" rowHeight="-1" estimatedRowHeight="-1" sectionHeaderHeight="28" sectionFooterHeight="28" translatesAutoresizingMaskIntoConstraints="NO" id="tbl-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<inset key="separatorInset" minX="15" minY="0.0" maxX="0.0" maxY="0.0"/>
</tableView>
</subviews>
<constraints>
<constraint firstItem="tbl-aa-aaa" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" id="c00-aa-aaa"/>
<constraint firstItem="tbl-aa-aaa" firstAttribute="bottom" secondItem="iN0-l3-epB" secondAttribute="bottom" id="c01-aa-aaa"/>
<constraint firstItem="tbl-aa-aaa" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" id="c02-aa-aaa"/>
<constraint firstItem="tbl-aa-aaa" firstAttribute="trailing" secondItem="iN0-l3-epB" secondAttribute="trailing" id="c03-aa-aaa"/>
</constraints>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "sb-table-separator-prototype", path: "/tmp/Main.storyboard", target: "27.0", digest: "f0f14cda2a15e5606a0092a7f6b0f8fcc2c97edf6d02a72f6f611757b9834eae", warnings: [], document: #"""
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
        ObservedDocument(name: "sb-table-readable", path: "/tmp/Main.storyboard", target: "27.0", digest: "767b96d3f80c0a362983200f0cbc73f2c886e9c93493722e8886697e404ac58f", warnings: [], document: #"""
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
<tableView key="view" clipsSubviews="YES" contentMode="scaleToFill" alwaysBounceVertical="YES" dataMode="prototypes" style="plain" separatorStyle="default" rowHeight="-1" estimatedRowHeight="-1" sectionHeaderHeight="28" sectionFooterHeight="28" layoutMarginsFollowReadableWidth="YES" id="tbv-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
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
        ObservedDocument(name: "cell-selection-absent", path: "/tmp/View.xib", target: "27.0", digest: "84923973bd1a3783daf08cda25e6d843c76019b7034ebd555b383a2f1da2db7c", warnings: [], document: #"""
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
<tableViewCell contentMode="scaleToFill" indentationWidth="10" customClass="Cell" customModule="T" customModuleProvider="target" id="KGk-i7-Jjw">
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
"""#),
        ObservedDocument(name: "cell-selection-absent-background", path: "/tmp/View.xib", target: "27.0", digest: "f3185b76100f478c98b5a40edc96d846c1cf170cc640ae8febb1ceac05369fb0", warnings: [], document: #"""
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
<tableViewCell contentMode="scaleToFill" indentationWidth="10" customClass="Cell" customModule="T" customModuleProvider="target" id="KGk-i7-Jjw">
<rect key="frame" x="0.0" y="0.0" width="320" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="KGk-i7-Jjw" id="H2p-sc-9uM">
<rect key="frame" x="0.0" y="0.0" width="320" height="44"/>
<autoresizingMask key="autoresizingMask"/>
</tableViewCellContentView>
<viewLayoutGuide key="safeArea" id="njF-e1-oar"/>
<color key="backgroundColor" systemColor="systemRedColor"/>
<point key="canvasLocation" x="0" y="0"/>
</tableViewCell>
</objects>
</document>
"""#),
        ObservedDocument(name: "effect-own-constraint-label", path: "/tmp/View.xib", target: "27.0", digest: "6a6a74f9dd4e86561a73f3e849c9c88e5c9269e1fb6e7a835ab67229d25e9f44", warnings: [], document: #"""
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
<visualEffectView contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="vev-aa-aa1">
<rect key="frame" x="20" y="40" width="200" height="100"/>
<view key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" id="vec-aa-aa1">
<rect key="frame" x="0.0" y="0.0" width="200" height="100"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<subviews>
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" text="Label" textAlignment="natural" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lll-ll-ll1">
<rect key="frame" x="10" y="10" width="42" height="21"/>
<fontDescription key="fontDescription" pointSize="17" type="system"/>
<nil key="textColor"/>
<nil key="highlightedColor"/>
</label>
</subviews>
</view>
<blurEffect style="regular"/>
<constraints>
<constraint firstAttribute="height" constant="100" id="eff-aa-aa1"/>
</constraints>
</visualEffectView>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "label-max-width-zero", path: "/tmp/View.xib", target: "27.0", digest: "d2955d7ebc8908ecefb8c536ab9721e43dab7096a4535b63a3e36cf7797de49d", warnings: [], document: #"""
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
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" text="Label" textAlignment="natural" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" preferredMaxLayoutWidth="0.0" id="lll-ll-ll1">
<rect key="frame" x="20" y="40" width="42" height="21"/>
<fontDescription key="fontDescription" pointSize="17" type="system"/>
<nil key="textColor"/>
<nil key="highlightedColor"/>
</label>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "label-font-zero-system", path: "/tmp/View.xib", target: "27.0", digest: "0b6782057256d308f8a4f65208d76634d662c09a11612e256432c9c114c8f87f", warnings: [], document: #"""
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
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" text="Label" textAlignment="natural" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lll-ll-ll1">
<rect key="frame" x="20" y="40" width="42" height="21"/>
<fontDescription key="fontDescription" pointSize="0.0" type="system"/>
<nil key="textColor"/>
<nil key="highlightedColor"/>
</label>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "label-font-zero-italic", path: "/tmp/View.xib", target: "27.0", digest: "7a073a654522e78c9a178b2232cb14611bfda68eb5d4a7c59a8c537de4456142", warnings: [], document: #"""
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
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" text="Label" textAlignment="natural" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lll-ll-ll1">
<rect key="frame" x="20" y="40" width="42" height="21"/>
<fontDescription key="fontDescription" pointSize="0.0" type="italicSystem"/>
<nil key="textColor"/>
<nil key="highlightedColor"/>
</label>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "button-font-zero-bold", path: "/tmp/View.xib", target: "27.0", digest: "0e3d54999e2afb8180656f02fe9025535d7fb8b8eac2d5e4c36948d443e53528", warnings: [], document: #"""
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
<fontDescription key="fontDescription" pointSize="0.0" type="boldSystem"/>
<state key="normal" title="Button"/>
</button>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "image-preferred-no-image", path: "/tmp/View.xib", target: "27.0", digest: "af916527535148812a34b9f4ae24c5a4827d9a31a238d8223c7de1280ff03089", warnings: [], document: #"""
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
<imageView contentMode="scaleToFill" userInteractionEnabled="NO" translatesAutoresizingMaskIntoConstraints="NO" id="iii-ii-ii1">
<rect key="frame" x="10" y="20" width="100" height="50"/>
<preferredSymbolConfiguration key="preferredSymbolConfiguration" scale="default"/>
</imageView>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "text-view-tint-parent", path: "/tmp/View.xib", target: "27.0", digest: "42b443a478d705e5e6cc5c0eb2bb0d1a9b37af88d190884392129459e847a2ec", warnings: [], document: #"""
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
<view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="ppp-aa-aa1">
<rect key="frame" x="0" y="20" width="300" height="200"/>
<subviews>
<textView clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="scaleToFill" textAlignment="natural" translatesAutoresizingMaskIntoConstraints="NO" id="txv-aa-aa1">
<rect key="frame" x="16" y="40" width="240" height="128"/>
<color key="backgroundColor" systemColor="systemBackgroundColor"/>
<string key="text">Lorem ipsum</string>
<fontDescription key="fontDescription" pointSize="14" type="system"/>
<textInputTraits key="textInputTraits" autocapitalizationType="sentences"/>
</textView>
</subviews>
<color key="tintColor" systemColor="systemRedColor"/>
</view>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "text-view-tint-grandparent", path: "/tmp/View.xib", target: "27.0", digest: "46a753ec60a786bbacf22bf229c17f3a1dd47c473db3fb02934dee380a34d0d9", warnings: [], document: #"""
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
<view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="ggg-aa-aa1">
<rect key="frame" x="0" y="20" width="300" height="200"/>
<subviews>
<view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="ppp-aa-aa1">
<rect key="frame" x="0" y="20" width="300" height="200"/>
<subviews>
<textView clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="scaleToFill" textAlignment="natural" translatesAutoresizingMaskIntoConstraints="NO" id="txv-aa-aa1">
<rect key="frame" x="16" y="40" width="240" height="128"/>
<color key="backgroundColor" systemColor="systemBackgroundColor"/>
<string key="text">Lorem ipsum</string>
<fontDescription key="fontDescription" pointSize="14" type="system"/>
<textInputTraits key="textInputTraits" autocapitalizationType="sentences"/>
</textView>
</subviews>
</view>
</subviews>
<color key="tintColor" systemColor="systemRedColor"/>
</view>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "text-view-tint-root", path: "/tmp/View.xib", target: "27.0", digest: "18ff2a4cc39459d40276425b19c2d8f68045819fea864b7de75bf4fe16f7fdec", warnings: [], document: #"""
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
</textView>
</subviews>
<color key="tintColor" systemColor="systemRedColor"/>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "sb-text-view-tint-global", path: "/tmp/Main.storyboard", target: "27.0", digest: "b0ea97a3f359567dfe95a07f354de236f979b4ae780ba557fba446bc51674f82", warnings: [], document: #"""
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
<textView clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="scaleToFill" textAlignment="natural" translatesAutoresizingMaskIntoConstraints="NO" id="txv-aa-aa1">
<rect key="frame" x="16" y="40" width="240" height="128"/>
<color key="backgroundColor" systemColor="systemBackgroundColor"/>
<string key="text">Lorem ipsum</string>
<fontDescription key="fontDescription" pointSize="14" type="system"/>
<textInputTraits key="textInputTraits" autocapitalizationType="sentences"/>
</textView>
</subviews>
</view>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="dkx-z0-nzr" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
<color key="tintColor" red="0.2" green="0.4" blue="0.6" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
</document>
"""#),
        ObservedDocument(name: "al-break-word-label-word", path: "/tmp/View.xib", target: "27.0", digest: "0ac84a15dbfd9e4c7975590626ef7c2a1cb22fc667a472e50262922141a8734d", warnings: [], document: #"""
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
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" usesAttributedText="YES" lineBreakMode="wordWrap" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lll-ll-ll1">
<rect key="frame" x="20" y="40" width="42" height="21"/>
<nil key="highlightedColor"/>
<attributedString key="attributedText">
<fragment content="Hello">
<attributes>
<font key="NSFont" metaFont="system" size="15"/>
<paragraphStyle key="NSParagraphStyle" alignment="left" lineBreakMode="wordWrapping" baseWritingDirection="natural"/>
</attributes>
</fragment>
</attributedString>
</label>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "al-break-tail-label-word", path: "/tmp/View.xib", target: "27.0", digest: "0ac84a15dbfd9e4c7975590626ef7c2a1cb22fc667a472e50262922141a8734d", warnings: [], document: #"""
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
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" usesAttributedText="YES" lineBreakMode="wordWrap" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lll-ll-ll1">
<rect key="frame" x="20" y="40" width="42" height="21"/>
<nil key="highlightedColor"/>
<attributedString key="attributedText">
<fragment content="Hello">
<attributes>
<font key="NSFont" metaFont="system" size="15"/>
<paragraphStyle key="NSParagraphStyle" alignment="left" lineBreakMode="truncatingTail" baseWritingDirection="natural"/>
</attributes>
</fragment>
</attributedString>
</label>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "text-view-custom-lproj", path: "/tmp/Base.lproj/View.xib", target: "27.0", digest: "4684ebeb84c70f465bc64b952120d0cb0219d81ab0fe68204e9d78140fb9b579", warnings: [], document: #"""
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
<textView clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="scaleToFill" textAlignment="natural" customClass="Note" customModule="T" customModuleProvider="target" translatesAutoresizingMaskIntoConstraints="NO" id="txv-aa-aa1">
<rect key="frame" x="16" y="40" width="240" height="128"/>
<color key="backgroundColor" systemColor="systemBackgroundColor"/>
<string key="text">Lorem ipsum</string>
<fontDescription key="fontDescription" pointSize="14" type="system"/>
<textInputTraits key="textInputTraits" autocapitalizationType="sentences"/>
</textView>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "safe-sub-table", path: "/tmp/View.xib", target: "27.0", digest: "604e65a426b9262f85921c07d54081f7a87074968caa0669e7fc2b3cf353a2d0", warnings: [], document: #"""
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
<tableView clipsSubviews="YES" contentMode="scaleToFill" alwaysBounceVertical="YES" style="plain" separatorStyle="default" rowHeight="-1" estimatedRowHeight="-1" sectionHeaderHeight="28" sectionFooterHeight="28" translatesAutoresizingMaskIntoConstraints="NO" id="tbl-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<viewLayoutGuide key="safeArea" id="gde-aa-aa1"/>
</tableView>
</subviews>
<viewLayoutGuide key="safeArea" id="vUN-kp-3ea"/>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "safe-sub-scroll", path: "/tmp/View.xib", target: "27.0", digest: "ec5e8645de25210d6af278734550af80fc7cf304455d1d840ccfece92b9137bc", warnings: [], document: #"""
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
<scrollView contentMode="scaleToFill" multipleTouchEnabled="YES" translatesAutoresizingMaskIntoConstraints="NO" id="scr-aa-aa1">
<rect key="frame" x="10" y="20" width="100" height="50"/>
<viewLayoutGuide key="safeArea" id="gde-aa-aa1"/>
</scrollView>
</subviews>
<viewLayoutGuide key="safeArea" id="vUN-kp-3ea"/>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "collection-safe-area", path: "/tmp/View.xib", target: "27.0", digest: "34ac26cee54ea787f46742551f0cb0ac3490476863bdd476286d3589fd08781b", warnings: [], document: #"""
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
<collectionView clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="scaleToFill" dataMode="none" translatesAutoresizingMaskIntoConstraints="NO" id="cvw-aa-aa1">
<rect key="frame" x="0" y="0" width="393" height="852"/>
<viewLayoutGuide key="safeArea" id="cvs-aa-aa1"/>
<collectionViewFlowLayout key="collectionViewLayout" minimumLineSpacing="10" minimumInteritemSpacing="10" id="flw-aa-aa1">
<size key="itemSize" width="128" height="128"/>
<size key="headerReferenceSize" width="0.0" height="0.0"/>
<size key="footerReferenceSize" width="0.0" height="0.0"/>
<inset key="sectionInset" minX="0.0" minY="0.0" maxX="0.0" maxY="0.0"/>
</collectionViewFlowLayout>
</collectionView>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "collection-safe-area-constrained", path: "/tmp/View.xib", target: "27.0", digest: "8c834bf316ed32c8e3ce468dd3681b69668216ce187bdba240a6e48a190342c9", warnings: [], document: #"""
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
<collectionView clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="scaleToFill" dataMode="none" translatesAutoresizingMaskIntoConstraints="NO" id="cvw-aa-aa1">
<rect key="frame" x="0" y="0" width="393" height="852"/>
<constraints>
<constraint firstAttribute="height" constant="160" id="cvh-aa-aa1"/>
</constraints>
<viewLayoutGuide key="safeArea" id="cvs-aa-aa1"/>
<collectionViewFlowLayout key="collectionViewLayout" minimumLineSpacing="10" minimumInteritemSpacing="10" id="flw-aa-aa1">
<size key="itemSize" width="128" height="128"/>
<size key="headerReferenceSize" width="0.0" height="0.0"/>
<size key="footerReferenceSize" width="0.0" height="0.0"/>
<inset key="sectionInset" minX="0.0" minY="0.0" maxX="0.0" maxY="0.0"/>
</collectionViewFlowLayout>
</collectionView>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "sb-ref-plist-len-10-5bit", path: "/tmp/Main.storyboard", target: "27.0", digest: "f87ee357f84b3d045d694e49caffbd83990742197ffb99488bf2b39e563904c5", warnings: [], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="tab-aa-aaa">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
</dependencies>
<scenes>
<scene sceneID="tbs-aa-aaa">
<objects>
<tabBarController id="tab-aa-aaa" sceneMemberID="viewController">
<tabBar key="tabBar" contentMode="scaleToFill" id="tbr-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="1000" height="1000"/>
<autoresizingMask key="autoresizingMask"/>
</tabBar>
<connections>
<segue destination="rf1-aa-aaa" kind="relationship" relationship="viewControllers" id="tb0-aa-aaa"/>
<segue destination="rf2-aa-aaa" kind="relationship" relationship="viewControllers" id="tb1-aa-aaa"/>
<segue destination="rf3-aa-aaa" kind="relationship" relationship="viewControllers" id="tb2-aa-aaa"/>
</connections>
</tabBarController>
<placeholder placeholderIdentifier="IBFirstResponder" id="tfr-bb-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="-800" y="0"/>
</scene>
<scene sceneID="rfs-aa-aa1">
<objects>
<viewControllerPlaceholder storyboardName="Main" referencedIdentifier="Moonlights" id="rf1-aa-aaa" sceneMemberID="viewController"/>
<placeholder placeholderIdentifier="IBFirstResponder" id="rfr-aa-aa1" userLabel="First Responder" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
<scene sceneID="rfs-aa-aa2">
<objects>
<viewControllerPlaceholder storyboardName="Main" referencedIdentifier="Moonlights" id="rf2-aa-aaa" sceneMemberID="viewController"/>
<placeholder placeholderIdentifier="IBFirstResponder" id="rfr-aa-aa2" userLabel="First Responder" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
<scene sceneID="rfs-aa-aa3">
<objects>
<viewControllerPlaceholder storyboardName="Other" id="rf3-aa-aaa" sceneMemberID="viewController"/>
<placeholder placeholderIdentifier="IBFirstResponder" id="rfr-aa-aa3" userLabel="First Responder" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#),
        ObservedDocument(name: "sb-ref-plist-len-10-6bit", path: "/tmp/Main.storyboard", target: "27.0", digest: "5ea31cf93cced06aff8f0b499e8f9659ae84ea2fb4db9a34ca2a2311b0d77419", warnings: [], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="tab-aa-aaa">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
</dependencies>
<scenes>
<scene sceneID="tbs-aa-aaa">
<objects>
<tabBarController id="tab-aa-aaa" sceneMemberID="viewController">
<tabBar key="tabBar" contentMode="scaleToFill" id="tbr-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="1000" height="1000"/>
<autoresizingMask key="autoresizingMask"/>
</tabBar>
<connections>
<segue destination="rf1-aa-aaa" kind="relationship" relationship="viewControllers" id="tb0-aa-aaa"/>
<segue destination="rf2-aa-aaa" kind="relationship" relationship="viewControllers" id="tb1-aa-aaa"/>
<segue destination="rf3-aa-aaa" kind="relationship" relationship="viewControllers" id="tb2-aa-aaa"/>
</connections>
</tabBarController>
<placeholder placeholderIdentifier="IBFirstResponder" id="tfr-bb-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="-800" y="0"/>
</scene>
<scene sceneID="rfs-aa-aa1">
<objects>
<viewControllerPlaceholder storyboardName="Main" referencedIdentifier="SettingsBB" id="rf1-aa-aaa" sceneMemberID="viewController"/>
<placeholder placeholderIdentifier="IBFirstResponder" id="rfr-aa-aa1" userLabel="First Responder" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
<scene sceneID="rfs-aa-aa2">
<objects>
<viewControllerPlaceholder storyboardName="Main" referencedIdentifier="SettingsBB" id="rf2-aa-aaa" sceneMemberID="viewController"/>
<placeholder placeholderIdentifier="IBFirstResponder" id="rfr-aa-aa2" userLabel="First Responder" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
<scene sceneID="rfs-aa-aa3">
<objects>
<viewControllerPlaceholder storyboardName="Other" id="rf3-aa-aaa" sceneMemberID="viewController"/>
<placeholder placeholderIdentifier="IBFirstResponder" id="rfr-aa-aa3" userLabel="First Responder" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#),
        ObservedDocument(name: "sb-ref-plist-len-8-other", path: "/tmp/Main.storyboard", target: "27.0", digest: "e70d11ec517c1b054445913504635f4f332f480fdbf56d190af690185a5d4361", warnings: [], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="tab-aa-aaa">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
</dependencies>
<scenes>
<scene sceneID="tbs-aa-aaa">
<objects>
<tabBarController id="tab-aa-aaa" sceneMemberID="viewController">
<tabBar key="tabBar" contentMode="scaleToFill" id="tbr-aa-aaa">
<rect key="frame" x="0.0" y="0.0" width="1000" height="1000"/>
<autoresizingMask key="autoresizingMask"/>
</tabBar>
<connections>
<segue destination="rf1-aa-aaa" kind="relationship" relationship="viewControllers" id="tb0-aa-aaa"/>
<segue destination="rf2-aa-aaa" kind="relationship" relationship="viewControllers" id="tb1-aa-aaa"/>
<segue destination="rf3-aa-aaa" kind="relationship" relationship="viewControllers" id="tb2-aa-aaa"/>
</connections>
</tabBarController>
<placeholder placeholderIdentifier="IBFirstResponder" id="tfr-bb-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="-800" y="0"/>
</scene>
<scene sceneID="rfs-aa-aa1">
<objects>
<viewControllerPlaceholder storyboardName="Main" referencedIdentifier="Sxxxxxxq" id="rf1-aa-aaa" sceneMemberID="viewController"/>
<placeholder placeholderIdentifier="IBFirstResponder" id="rfr-aa-aa1" userLabel="First Responder" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
<scene sceneID="rfs-aa-aa2">
<objects>
<viewControllerPlaceholder storyboardName="Main" referencedIdentifier="Sxxxxxxq" id="rf2-aa-aaa" sceneMemberID="viewController"/>
<placeholder placeholderIdentifier="IBFirstResponder" id="rfr-aa-aa2" userLabel="First Responder" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
<scene sceneID="rfs-aa-aa3">
<objects>
<viewControllerPlaceholder storyboardName="Other" id="rf3-aa-aaa" sceneMemberID="viewController"/>
<placeholder placeholderIdentifier="IBFirstResponder" id="rfr-aa-aa3" userLabel="First Responder" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#),
        ObservedDocument(name: "sb-static-outlets-three", path: "/tmp/Main.storyboard", target: "27.0", digest: "f260a58c06d44d9248b7ffddb15b92233ad50902a8893af6caa0bb3e7b756525", warnings: [], document: #"""
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
<sections>
<tableViewSection id="sec-aa-aa1">
<cells>
<tableViewCell clipsSubviews="YES" contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" id="cel-aa-aa1">
<rect key="frame" x="0.0" y="0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="cel-aa-aa1" id="ccv-aa-aa1">
<rect key="frame" x="0.0" y="0.0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<subviews>
<textField opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="left" contentVerticalAlignment="center" borderStyle="roundedRect" textAlignment="natural" minimumFontSize="17" translatesAutoresizingMaskIntoConstraints="NO" id="fl1-aa-aa1">
<rect key="frame" x="20" y="5" width="200" height="34"/>
<fontDescription key="fontDescription" type="system" pointSize="14"/>
<textInputTraits key="textInputTraits"/>
<connections>
<outlet property="delegate" destination="tvc-aa-aaa" id="dl1-aa-aa1"/>
</connections>
</textField>
</subviews>
</tableViewCellContentView>
</tableViewCell>
<tableViewCell clipsSubviews="YES" contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" id="cel-aa-aa2">
<rect key="frame" x="0.0" y="44" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="cel-aa-aa2" id="ccv-aa-aa2">
<rect key="frame" x="0.0" y="0.0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<subviews>
<textField opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="left" contentVerticalAlignment="center" borderStyle="roundedRect" textAlignment="natural" minimumFontSize="17" translatesAutoresizingMaskIntoConstraints="NO" id="fl2-aa-aa1">
<rect key="frame" x="20" y="5" width="200" height="34"/>
<fontDescription key="fontDescription" type="system" pointSize="14"/>
<textInputTraits key="textInputTraits"/>
<connections>
<outlet property="delegate" destination="tvc-aa-aaa" id="dl2-aa-aa1"/>
</connections>
</textField>
</subviews>
</tableViewCellContentView>
</tableViewCell>
<tableViewCell clipsSubviews="YES" contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" id="cel-aa-aa3">
<rect key="frame" x="0.0" y="88" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="cel-aa-aa3" id="ccv-aa-aa3">
<rect key="frame" x="0.0" y="0.0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<subviews>
<textField opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="left" contentVerticalAlignment="center" borderStyle="roundedRect" textAlignment="natural" minimumFontSize="17" translatesAutoresizingMaskIntoConstraints="NO" id="fl3-aa-aa1">
<rect key="frame" x="20" y="5" width="200" height="34"/>
<fontDescription key="fontDescription" type="system" pointSize="14"/>
<textInputTraits key="textInputTraits"/>
<connections>
<outlet property="delegate" destination="tvc-aa-aaa" id="dl3-aa-aa1"/>
</connections>
</textField>
</subviews>
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
        ObservedDocument(name: "sb-warn-guide-both", path: "/tmp/Main.storyboard", target: "27.0", digest: "e8a227fac82346b78ee1ccd32e1f0012de3367bbe11b273587e759b0a9fc4803", warnings: ["/tmp/Main.storyboard:8bC-Xf-vdC: warning: Top layout guide is deprecated since iOS 11.0 [7]", "/tmp/Main.storyboard:8bC-Xf-vdC: warning: Bottom layout guide is deprecated since iOS 11.0 [7]"], document: #"""
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
<constraint firstItem="xb3-aO-Qok" firstAttribute="top" secondItem="sub-vi-ew1" secondAttribute="bottom" constant="8" id="gbt-aa-aa1"/>
</constraints>
</view>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="dkx-z0-nzr" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#),
        ObservedDocument(name: "sb-warn-guide-both-swapped", path: "/tmp/Main.storyboard", target: "27.0", digest: "e8a227fac82346b78ee1ccd32e1f0012de3367bbe11b273587e759b0a9fc4803", warnings: ["/tmp/Main.storyboard:8bC-Xf-vdC: warning: Top layout guide is deprecated since iOS 11.0 [7]", "/tmp/Main.storyboard:8bC-Xf-vdC: warning: Bottom layout guide is deprecated since iOS 11.0 [7]"], document: #"""
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
<constraint firstItem="xb3-aO-Qok" firstAttribute="top" secondItem="sub-vi-ew1" secondAttribute="bottom" constant="8" id="gbt-aa-aa1"/>
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
"""#),
    ]
}
