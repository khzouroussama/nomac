import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What a nib shares between objects, as ibtool (Xcode 27.0) writes it, and what follows from the document as a whole
/// (`.github/scripts/nib_experiments.py` rounds 150 to 153).
@Suite struct ShareTests {
    @Test(arguments: cases) func compilesAsXcode(_ document: ObservedDocument) throws {
        try document.check()
    }

    static let cases = [
        ObservedDocument(name: "sb-segue-push-two-no-traits", path: "/tmp/Main.storyboard", target: "27.0", digest: "f7a89743055b87f6ac7a6ad230b198bbc926818254923366cacc35c0d28664be", warnings: [], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" colorMatched="YES" initialViewController="nvc-aa-aaa">
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
"""#),
        ObservedDocument(name: "sb-segue-modal-push-no-traits", path: "/tmp/Main.storyboard", target: "27.0", digest: "3876a35c5cfeb62b5ac13f5dd42a336e4d4835550e3fc6a4454aa6e6b18b18f8", warnings: [], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" colorMatched="YES" initialViewController="nvc-aa-aaa">
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
"""#),
        ObservedDocument(name: "sb-cellseg-sections-two-two-one", path: "/tmp/Main.storyboard", target: "27.0", digest: "5452dbfe92903b8edab7ff4b3fe05ae3e56764837951737c36b766cf56e56521", warnings: [], document: #"""
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
<tableViewSection id="sec-aa-a0">
<cells>
<tableViewCell clipsSubviews="YES" contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" id="cel-aa-aa1">
<rect key="frame" x="0.0" y="0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="cel-aa-aa1" id="ccv-aa-aa1">
<rect key="frame" x="0.0" y="0.0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
</tableViewCellContentView>
<connections>
<segue destination="vc2-aa-aaa" kind="show" identifier="A" id="csg-aa-a01"/>
</connections>
</tableViewCell>
<tableViewCell clipsSubviews="YES" contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" id="cel-aa-aa2">
<rect key="frame" x="0.0" y="44" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="cel-aa-aa2" id="ccv-aa-aa2">
<rect key="frame" x="0.0" y="0.0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
</tableViewCellContentView>
<connections>
<segue destination="vc2-aa-aaa" kind="show" identifier="B" id="csg-aa-a02"/>
</connections>
</tableViewCell>
</cells>
</tableViewSection>
<tableViewSection id="sec-aa-a1">
<cells>
<tableViewCell clipsSubviews="YES" contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" id="cel-aa-aa3">
<rect key="frame" x="0.0" y="88" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="cel-aa-aa3" id="ccv-aa-aa3">
<rect key="frame" x="0.0" y="0.0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
</tableViewCellContentView>
<connections>
<segue destination="vc2-aa-aaa" kind="show" identifier="C" id="csg-aa-a03"/>
</connections>
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
"""#),
        ObservedDocument(name: "sb-cellseg-sections-three-sections", path: "/tmp/Main.storyboard", target: "27.0", digest: "b44b976bda80774c9aaed9ee0879ee14e07e71c1a395b2edaf693f38fc4f32ca", warnings: [], document: #"""
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
<tableViewSection id="sec-aa-a0">
<cells>
<tableViewCell clipsSubviews="YES" contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" id="cel-aa-aa1">
<rect key="frame" x="0.0" y="0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="cel-aa-aa1" id="ccv-aa-aa1">
<rect key="frame" x="0.0" y="0.0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
</tableViewCellContentView>
<connections>
<segue destination="vc2-aa-aaa" kind="show" identifier="A" id="csg-aa-a01"/>
</connections>
</tableViewCell>
</cells>
</tableViewSection>
<tableViewSection id="sec-aa-a1">
<cells>
<tableViewCell clipsSubviews="YES" contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" id="cel-aa-aa2">
<rect key="frame" x="0.0" y="44" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="cel-aa-aa2" id="ccv-aa-aa2">
<rect key="frame" x="0.0" y="0.0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
</tableViewCellContentView>
<connections>
<segue destination="vc2-aa-aaa" kind="show" identifier="B" id="csg-aa-a02"/>
</connections>
</tableViewCell>
<tableViewCell clipsSubviews="YES" contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" id="cel-aa-aa3">
<rect key="frame" x="0.0" y="88" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="cel-aa-aa3" id="ccv-aa-aa3">
<rect key="frame" x="0.0" y="0.0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
</tableViewCellContentView>
<connections>
<segue destination="vc2-aa-aaa" kind="show" identifier="C" id="csg-aa-a03"/>
</connections>
</tableViewCell>
<tableViewCell clipsSubviews="YES" contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" id="cel-aa-aa4">
<rect key="frame" x="0.0" y="132" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="cel-aa-aa4" id="ccv-aa-aa4">
<rect key="frame" x="0.0" y="0.0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
</tableViewCellContentView>
<connections>
<segue destination="vc2-aa-aaa" kind="show" identifier="D" id="csg-aa-a04"/>
</connections>
</tableViewCell>
</cells>
</tableViewSection>
<tableViewSection id="sec-aa-a2">
<cells>
<tableViewCell clipsSubviews="YES" contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" id="cel-aa-aa5">
<rect key="frame" x="0.0" y="176" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="cel-aa-aa5" id="ccv-aa-aa5">
<rect key="frame" x="0.0" y="0.0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
</tableViewCellContentView>
<connections>
<segue destination="vc2-aa-aaa" kind="show" identifier="E" id="csg-aa-a05"/>
</connections>
</tableViewCell>
<tableViewCell clipsSubviews="YES" contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" id="cel-aa-aa6">
<rect key="frame" x="0.0" y="220" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="cel-aa-aa6" id="ccv-aa-aa6">
<rect key="frame" x="0.0" y="0.0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
</tableViewCellContentView>
<connections>
<segue destination="vc2-aa-aaa" kind="show" identifier="F" id="csg-aa-a06"/>
</connections>
</tableViewCell>
<tableViewCell clipsSubviews="YES" contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" id="cel-aa-aa7">
<rect key="frame" x="0.0" y="264" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="cel-aa-aa7" id="ccv-aa-aa7">
<rect key="frame" x="0.0" y="0.0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
</tableViewCellContentView>
<connections>
<segue destination="vc2-aa-aaa" kind="show" identifier="G" id="csg-aa-a07"/>
</connections>
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
"""#),
        ObservedDocument(name: "sb-cellseg-sections-gap", path: "/tmp/Main.storyboard", target: "27.0", digest: "418b36bf87f8ae1e2fa5ed55edb27a1833b2638bca390ba94de5361b37221d03", warnings: [], document: #"""
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
<tableViewSection id="sec-aa-a0">
<cells>
<tableViewCell clipsSubviews="YES" contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" id="cel-aa-aa1">
<rect key="frame" x="0.0" y="0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="cel-aa-aa1" id="ccv-aa-aa1">
<rect key="frame" x="0.0" y="0.0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
</tableViewCellContentView>
<connections>
<segue destination="vc2-aa-aaa" kind="show" identifier="A" id="csg-aa-a01"/>
</connections>
</tableViewCell>
<tableViewCell clipsSubviews="YES" contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" id="cel-aa-aa2">
<rect key="frame" x="0.0" y="44" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="cel-aa-aa2" id="ccv-aa-aa2">
<rect key="frame" x="0.0" y="0.0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
</tableViewCellContentView>
</tableViewCell>
<tableViewCell clipsSubviews="YES" contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" id="cel-aa-aa3">
<rect key="frame" x="0.0" y="88" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="cel-aa-aa3" id="ccv-aa-aa3">
<rect key="frame" x="0.0" y="0.0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
</tableViewCellContentView>
<connections>
<segue destination="vc2-aa-aaa" kind="show" identifier="B" id="csg-aa-a03"/>
</connections>
</tableViewCell>
</cells>
</tableViewSection>
<tableViewSection id="sec-aa-a1">
<cells>
<tableViewCell clipsSubviews="YES" contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" id="cel-aa-aa4">
<rect key="frame" x="0.0" y="132" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="cel-aa-aa4" id="ccv-aa-aa4">
<rect key="frame" x="0.0" y="0.0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
</tableViewCellContentView>
</tableViewCell>
</cells>
</tableViewSection>
<tableViewSection id="sec-aa-a2">
<cells>
<tableViewCell clipsSubviews="YES" contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" id="cel-aa-aa5">
<rect key="frame" x="0.0" y="176" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="cel-aa-aa5" id="ccv-aa-aa5">
<rect key="frame" x="0.0" y="0.0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
</tableViewCellContentView>
<connections>
<segue destination="vc2-aa-aaa" kind="show" identifier="C" id="csg-aa-a05"/>
</connections>
</tableViewCell>
<tableViewCell clipsSubviews="YES" contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" id="cel-aa-aa6">
<rect key="frame" x="0.0" y="220" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="cel-aa-aa6" id="ccv-aa-aa6">
<rect key="frame" x="0.0" y="0.0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
</tableViewCellContentView>
</tableViewCell>
<tableViewCell clipsSubviews="YES" contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" id="cel-aa-aa7">
<rect key="frame" x="0.0" y="264" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
<tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="cel-aa-aa7" id="ccv-aa-aa7">
<rect key="frame" x="0.0" y="0.0" width="393" height="44"/>
<autoresizingMask key="autoresizingMask"/>
</tableViewCellContentView>
<connections>
<segue destination="vc2-aa-aaa" kind="show" identifier="D" id="csg-aa-a07"/>
</connections>
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
"""#),
        ObservedDocument(name: "sb-section-safe-safe", path: "/tmp/Main.storyboard", target: "27.0", digest: "4ba80d6354ec674d59de428a4b6f15d68c150e167c0c1dd8bf72ca05f305efe0", warnings: [], document: #"""
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
<view key="view" contentMode="scaleToFill" id="8bC-Xf-vdC">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<subviews>
<collectionView clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="scaleToFill" dataMode="prototypes" translatesAutoresizingMaskIntoConstraints="NO" id="cvw-aa-aa1">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<collectionViewFlowLayout key="collectionViewLayout" minimumLineSpacing="10" minimumInteritemSpacing="10" id="flw-aa-aa1">
<size key="itemSize" width="128" height="128"/>
<size key="headerReferenceSize" width="50" height="50"/>
<size key="footerReferenceSize" width="50" height="50"/>
<inset key="sectionInset" minX="0.0" minY="0.0" maxX="0.0" maxY="0.0"/>
</collectionViewFlowLayout>
<cells>
<collectionViewCell opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" reuseIdentifier="Cell" id="cel-aa-aa1">
<rect key="frame" x="0" y="0.0" width="128" height="128"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
<view key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center">
<rect key="frame" x="0.0" y="0.0" width="128" height="128"/>
<autoresizingMask key="autoresizingMask"/>
</view>
</collectionViewCell>
</cells>
<collectionReusableView key="sectionHeaderView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" reuseIdentifier="Header" id="shv-aa-aa1">
<rect key="frame" x="0.0" y="0" width="393" height="50"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
</collectionReusableView>
</collectionView>
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
"""#),
        ObservedDocument(name: "sb-section-safe-safe-insets-both", path: "/tmp/Main.storyboard", target: "27.0", digest: "d9f397371f707936f99d4b69f12277f7659a9d6966cc5d7bc26e547eb0fc8107", warnings: [], document: #"""
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
<view key="view" contentMode="scaleToFill" id="8bC-Xf-vdC">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<subviews>
<collectionView clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="scaleToFill" dataMode="prototypes" translatesAutoresizingMaskIntoConstraints="NO" id="cvw-aa-aa1">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<collectionViewFlowLayout key="collectionViewLayout" minimumLineSpacing="10" minimumInteritemSpacing="10" id="flw-aa-aa1">
<size key="itemSize" width="128" height="128"/>
<size key="headerReferenceSize" width="50" height="50"/>
<size key="footerReferenceSize" width="50" height="50"/>
<inset key="sectionInset" minX="0.0" minY="0.0" maxX="0.0" maxY="0.0"/>
</collectionViewFlowLayout>
<cells>
<collectionViewCell opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" reuseIdentifier="Cell" id="cel-aa-aa1">
<rect key="frame" x="0" y="0.0" width="128" height="128"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
<view key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center">
<rect key="frame" x="0.0" y="0.0" width="128" height="128"/>
<autoresizingMask key="autoresizingMask"/>
</view>
</collectionViewCell>
</cells>
<collectionReusableView key="sectionHeaderView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" reuseIdentifier="Header" insetsLayoutMarginsFromSafeArea="NO" id="shv-aa-aa1">
<rect key="frame" x="0.0" y="0" width="393" height="50"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
</collectionReusableView>
<collectionReusableView key="sectionFooterView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" reuseIdentifier="Footer" insetsLayoutMarginsFromSafeArea="NO" id="sfv-aa-aa1">
<rect key="frame" x="0.0" y="128" width="393" height="50"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
</collectionReusableView>
</collectionView>
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
"""#),
        ObservedDocument(name: "sb-section-safe-label-pinned", path: "/tmp/Main.storyboard", target: "27.0", digest: "070683e44b3061c25a9462801d557babd3f2c4eaf4c287ea2ce2362ce328c9b6", warnings: [], document: #"""
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
<view key="view" contentMode="scaleToFill" id="8bC-Xf-vdC">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<subviews>
<collectionView clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="scaleToFill" dataMode="prototypes" translatesAutoresizingMaskIntoConstraints="NO" id="cvw-aa-aa1">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<collectionViewFlowLayout key="collectionViewLayout" minimumLineSpacing="10" minimumInteritemSpacing="10" id="flw-aa-aa1">
<size key="itemSize" width="128" height="128"/>
<size key="headerReferenceSize" width="50" height="50"/>
<size key="footerReferenceSize" width="50" height="50"/>
<inset key="sectionInset" minX="0.0" minY="0.0" maxX="0.0" maxY="0.0"/>
</collectionViewFlowLayout>
<cells>
<collectionViewCell opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" reuseIdentifier="Cell" id="cel-aa-aa1">
<rect key="frame" x="0" y="0.0" width="128" height="128"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
<view key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center">
<rect key="frame" x="0.0" y="0.0" width="128" height="128"/>
<autoresizingMask key="autoresizingMask"/>
</view>
</collectionViewCell>
</cells>
<collectionReusableView key="sectionHeaderView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" reuseIdentifier="Header" id="shv-aa-aa1">
<rect key="frame" x="0.0" y="0" width="393" height="50"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
<subviews>
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" text="L" translatesAutoresizingMaskIntoConstraints="NO" id="lbl-aa-aa1">
<rect key="frame" x="0" y="0" width="10" height="10"/>
<fontDescription key="fontDescription" type="system" pointSize="17"/>
</label>
</subviews>
<constraints>
<constraint firstItem="lbl-aa-aa1" firstAttribute="top" secondItem="shv-aa-aa1" secondAttribute="top" id="cst-aa-aa1"/>
</constraints>
</collectionReusableView>
</collectionView>
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
"""#),
        ObservedDocument(name: "sb-section-safe-guide", path: "/tmp/Main.storyboard", target: "27.0", digest: "4ba80d6354ec674d59de428a4b6f15d68c150e167c0c1dd8bf72ca05f305efe0", warnings: [], document: #"""
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
<view key="view" contentMode="scaleToFill" id="8bC-Xf-vdC">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
<subviews>
<collectionView clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="scaleToFill" dataMode="prototypes" translatesAutoresizingMaskIntoConstraints="NO" id="cvw-aa-aa1">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<collectionViewFlowLayout key="collectionViewLayout" minimumLineSpacing="10" minimumInteritemSpacing="10" id="flw-aa-aa1">
<size key="itemSize" width="128" height="128"/>
<size key="headerReferenceSize" width="50" height="50"/>
<size key="footerReferenceSize" width="50" height="50"/>
<inset key="sectionInset" minX="0.0" minY="0.0" maxX="0.0" maxY="0.0"/>
</collectionViewFlowLayout>
<cells>
<collectionViewCell opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" reuseIdentifier="Cell" id="cel-aa-aa1">
<rect key="frame" x="0" y="0.0" width="128" height="128"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
<view key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center">
<rect key="frame" x="0.0" y="0.0" width="128" height="128"/>
<autoresizingMask key="autoresizingMask"/>
</view>
</collectionViewCell>
</cells>
<collectionReusableView key="sectionHeaderView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" reuseIdentifier="Header" id="shv-aa-aa1">
<rect key="frame" x="0.0" y="0" width="393" height="50"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
<viewLayoutGuide key="safeArea" id="sgd-aa-aa1"/>
</collectionReusableView>
</collectionView>
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
"""#),
        ObservedDocument(name: "sb-section-safe-insets", path: "/tmp/Main.storyboard", target: "27.0", digest: "88111e5492e475af0b395758eb9976f6794cadae1e9396fecfa1e3856a23ac5f", warnings: [], document: #"""
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
<collectionView clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="scaleToFill" dataMode="prototypes" translatesAutoresizingMaskIntoConstraints="NO" id="cvw-aa-aa1">
<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
<collectionViewFlowLayout key="collectionViewLayout" minimumLineSpacing="10" minimumInteritemSpacing="10" id="flw-aa-aa1">
<size key="itemSize" width="128" height="128"/>
<size key="headerReferenceSize" width="50" height="50"/>
<size key="footerReferenceSize" width="50" height="50"/>
<inset key="sectionInset" minX="0.0" minY="0.0" maxX="0.0" maxY="0.0"/>
</collectionViewFlowLayout>
<cells>
<collectionViewCell opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" reuseIdentifier="Cell" id="cel-aa-aa1">
<rect key="frame" x="0" y="0.0" width="128" height="128"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
<view key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center">
<rect key="frame" x="0.0" y="0.0" width="128" height="128"/>
<autoresizingMask key="autoresizingMask"/>
</view>
</collectionViewCell>
</cells>
<collectionReusableView key="sectionHeaderView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" reuseIdentifier="Header" insetsLayoutMarginsFromSafeArea="NO" id="shv-aa-aa1">
<rect key="frame" x="0.0" y="0" width="393" height="50"/>
<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
</collectionReusableView>
</collectionView>
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
        ObservedDocument(name: "font-share-italic-two-sizes", path: "/tmp/View.xib", target: "27.0", digest: "0f12b5a4a47b6ee69bc100730218cf88b1b2ff4ab9e0b0719c0d96abd8a5a385", warnings: [], document: #"""
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
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" text="Label" textAlignment="natural" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lbl-aa-aa1">
<rect key="frame" x="10" y="40" width="42" height="21"/>
<fontDescription key="fontDescription" type="italicSystem" pointSize="13"/>

<nil key="textColor"/>
<nil key="highlightedColor"/>
</label>
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" text="Label" textAlignment="natural" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lbl-aa-aa2">
<rect key="frame" x="120" y="40" width="42" height="21"/>
<fontDescription key="fontDescription" type="italicSystem" pointSize="15"/>

<nil key="textColor"/>
<nil key="highlightedColor"/>
</label>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "font-share-bold-two-sizes", path: "/tmp/View.xib", target: "27.0", digest: "5408138ef151f89842fe1b36017ec449921e28f3845031a9418ba2af28e9da57", warnings: [], document: #"""
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
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" text="Label" textAlignment="natural" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lbl-aa-aa1">
<rect key="frame" x="10" y="40" width="42" height="21"/>
<fontDescription key="fontDescription" type="boldSystem" pointSize="13"/>

<nil key="textColor"/>
<nil key="highlightedColor"/>
</label>
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" text="Label" textAlignment="natural" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lbl-aa-aa2">
<rect key="frame" x="120" y="40" width="42" height="21"/>
<fontDescription key="fontDescription" type="boldSystem" pointSize="15"/>

<nil key="textColor"/>
<nil key="highlightedColor"/>
</label>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "al-share-two-fragments", path: "/tmp/View.xib", target: "27.0", digest: "631223ec29cac79b6be4dfaad27dd2c5a898363ba2cb5fe326700788249db7ba", warnings: [], document: #"""
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
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" usesAttributedText="YES" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lbl-aa-aa1">
<rect key="frame" x="10" y="40" width="42" height="21"/>
<nil key="highlightedColor"/>
<attributedString key="attributedText">
<fragment content="Hello">
<attributes>
<color key="NSColor" red="1" green="0" blue="0" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
<font key="NSFont" metaFont="system" size="15"/>
</attributes>
</fragment>
</attributedString>
</label>
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" usesAttributedText="YES" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lbl-aa-aa2">
<rect key="frame" x="120" y="40" width="42" height="21"/>
<nil key="highlightedColor"/>
<attributedString key="attributedText">
<fragment content="Hello">
<attributes>
<color key="NSColor" red="1" green="0" blue="0" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
<font key="NSFont" metaFont="system" size="15"/>
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
        ObservedDocument(name: "al-share-two-fragments-paragraph", path: "/tmp/View.xib", target: "27.0", digest: "556581a306d83dfa2423ced4bbdef8aa68600fe87114fb5e9755760911b8ec9b", warnings: [], document: #"""
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
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" usesAttributedText="YES" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lbl-aa-aa1">
<rect key="frame" x="10" y="40" width="42" height="21"/>
<nil key="highlightedColor"/>
<attributedString key="attributedText">
<fragment content="Hello">
<attributes>
<color key="NSColor" red="1" green="0" blue="0" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
<font key="NSFont" metaFont="system" size="15"/>
<paragraphStyle key="NSParagraphStyle" alignment="left" lineBreakMode="wordWrapping" baseWritingDirection="natural" lineHeightMultiple="1.2" tighteningFactorForTruncation="0.0"/>
</attributes>
</fragment>
</attributedString>
</label>
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" usesAttributedText="YES" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lbl-aa-aa2">
<rect key="frame" x="120" y="40" width="42" height="21"/>
<nil key="highlightedColor"/>
<attributedString key="attributedText">
<fragment content="Hello">
<attributes>
<color key="NSColor" red="1" green="0" blue="0" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
<font key="NSFont" metaFont="system" size="15"/>
<paragraphStyle key="NSParagraphStyle" alignment="left" lineBreakMode="wordWrapping" baseWritingDirection="natural" lineHeightMultiple="1.2" tighteningFactorForTruncation="0.0"/>
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
        ObservedDocument(name: "al-share-two-fragments-other-text", path: "/tmp/View.xib", target: "27.0", digest: "2cbcd5de7c41cd4ff2ce290b01b7191c524f80e7bb8332b6adf5c0b0cd8a112f", warnings: [], document: #"""
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
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" usesAttributedText="YES" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lbl-aa-aa1">
<rect key="frame" x="10" y="40" width="42" height="21"/>
<nil key="highlightedColor"/>
<attributedString key="attributedText">
<fragment content="Hello">
<attributes>
<font key="NSFont" metaFont="system" size="15"/>
</attributes>
</fragment>
</attributedString>
</label>
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" usesAttributedText="YES" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lbl-aa-aa2">
<rect key="frame" x="120" y="40" width="42" height="21"/>
<nil key="highlightedColor"/>
<attributedString key="attributedText">
<fragment content="Other">
<attributes>
<font key="NSFont" metaFont="system" size="15"/>
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
        ObservedDocument(name: "al-share-two-fragments-sizes", path: "/tmp/View.xib", target: "27.0", digest: "e5e954792e7ce258c39c3328aaad2cd8cfd91d36e874fff85e1dc11d0e390eb0", warnings: [], document: #"""
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
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" usesAttributedText="YES" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lbl-aa-aa1">
<rect key="frame" x="10" y="40" width="42" height="21"/>
<nil key="highlightedColor"/>
<attributedString key="attributedText">
<fragment content="Hello">
<attributes>
<font key="NSFont" metaFont="system" size="15"/>
</attributes>
</fragment>
</attributedString>
</label>
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" usesAttributedText="YES" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lbl-aa-aa2">
<rect key="frame" x="120" y="40" width="42" height="21"/>
<nil key="highlightedColor"/>
<attributedString key="attributedText">
<fragment content="Hello">
<attributes>
<font key="NSFont" metaFont="system" size="16"/>
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
        ObservedDocument(name: "al-font-sfns-sibling", path: "/tmp/View.xib", target: "27.0", digest: "9857d5edc390659da468612024622b0e73fbc517cb2c6375f14f00b46d49c609", warnings: [], document: #"""
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
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" text="Label" textAlignment="natural" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lbl-aa-aa1">
<rect key="frame" x="10" y="40" width="42" height="21"/>
<fontDescription key="fontDescription" type="system" pointSize="11"/>

<nil key="textColor"/>
<nil key="highlightedColor"/>
</label>
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" usesAttributedText="YES" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lbl-aa-aa2">
<rect key="frame" x="120" y="40" width="42" height="21"/>
<nil key="highlightedColor"/>
<attributedString key="attributedText">
<fragment content="Hello">
<attributes>
<font key="NSFont" size="11" name=".SFNSText"/>
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
        ObservedDocument(name: "al-font-name-SFUIText", path: "/tmp/View.xib", target: "27.0", digest: "415cf0d770068965910894adcbf1a920752a99e638748475c1ebc1c587000e1e", warnings: [], document: #"""
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
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" usesAttributedText="YES" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lll-ll-ll1">
<rect key="frame" x="20" y="40" width="42" height="21"/>
<nil key="highlightedColor"/>
<attributedString key="attributedText">
<fragment content="Hello">
<attributes>
<font key="NSFont" size="11" name=".SFUIText"/>
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
        ObservedDocument(name: "al-font-name-SFUI-Regular", path: "/tmp/View.xib", target: "27.0", digest: "415cf0d770068965910894adcbf1a920752a99e638748475c1ebc1c587000e1e", warnings: [], document: #"""
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
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" usesAttributedText="YES" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lll-ll-ll1">
<rect key="frame" x="20" y="40" width="42" height="21"/>
<nil key="highlightedColor"/>
<attributedString key="attributedText">
<fragment content="Hello">
<attributes>
<font key="NSFont" size="11" name=".SFUI-Regular"/>
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
        ObservedDocument(name: "al-font-name-SFNSDisplay", path: "/tmp/View.xib", target: "27.0", digest: "415cf0d770068965910894adcbf1a920752a99e638748475c1ebc1c587000e1e", warnings: [], document: #"""
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
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" usesAttributedText="YES" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lll-ll-ll1">
<rect key="frame" x="20" y="40" width="42" height="21"/>
<nil key="highlightedColor"/>
<attributedString key="attributedText">
<fragment content="Hello">
<attributes>
<font key="NSFont" size="11" name=".SFNSDisplay"/>
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
        ObservedDocument(name: "al-font-name-SFUIDisplay", path: "/tmp/View.xib", target: "27.0", digest: "415cf0d770068965910894adcbf1a920752a99e638748475c1ebc1c587000e1e", warnings: [], document: #"""
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
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" usesAttributedText="YES" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lll-ll-ll1">
<rect key="frame" x="20" y="40" width="42" height="21"/>
<nil key="highlightedColor"/>
<attributedString key="attributedText">
<fragment content="Hello">
<attributes>
<font key="NSFont" size="11" name=".SFUIDisplay"/>
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
        ObservedDocument(name: "al-unmatched-white", path: "/tmp/View.xib", target: "27.0", digest: "dc1d53d10f69254c3d852e97b44112cffc18d384c0ca8b05038fd07bdb3cd4c6", warnings: [], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES">
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
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" usesAttributedText="YES" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lll-ll-ll1">
<rect key="frame" x="20" y="40" width="42" height="21"/>
<nil key="highlightedColor"/>
<attributedString key="attributedText">
<fragment content="Hello">
<attributes>
<color key="NSColor" white="0.5" alpha="1" colorSpace="calibratedWhite"/>
<font key="NSFont" metaFont="system" size="15"/>
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
        ObservedDocument(name: "al-unmatched-rgb", path: "/tmp/View.xib", target: "27.0", digest: "aac0ff40543f3a9fa2c2c03a1216b66fb59fc13252dd2ccb9f08cd56ad6a5f74", warnings: [], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES">
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
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" usesAttributedText="YES" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lll-ll-ll1">
<rect key="frame" x="20" y="40" width="42" height="21"/>
<nil key="highlightedColor"/>
<attributedString key="attributedText">
<fragment content="Hello">
<attributes>
<color key="NSColor" red="1" green="0" blue="0" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
<font key="NSFont" metaFont="system" size="15"/>
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
        ObservedDocument(name: "al-unmatched-calibrated", path: "/tmp/View.xib", target: "27.0", digest: "48be7545424f9df265008ffe84133a9657407515621c0198c107e376281fa80b", warnings: [], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES">
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
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" usesAttributedText="YES" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lll-ll-ll1">
<rect key="frame" x="20" y="40" width="42" height="21"/>
<nil key="highlightedColor"/>
<attributedString key="attributedText">
<fragment content="Hello">
<attributes>
<color key="NSColor" red="0.5" green="0.25" blue="0.75" alpha="1" colorSpace="calibratedRGB"/>
<font key="NSFont" metaFont="system" size="15"/>
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
        ObservedDocument(name: "al-unmatched-sibling", path: "/tmp/View.xib", target: "27.0", digest: "4612355598561ae39c7eb11bc31d020d6b4451a9ebcdf979a86c5317017b025c", warnings: [], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES">
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
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" text="Label" textAlignment="natural" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lbl-aa-aa1">
<rect key="frame" x="10" y="40" width="42" height="21"/>
<fontDescription key="fontDescription" pointSize="17" type="system"/>
<color key="textColor" white="0.5" alpha="1" colorSpace="calibratedWhite"/>
<nil key="highlightedColor"/>
</label>
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" usesAttributedText="YES" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lbl-aa-aa2">
<rect key="frame" x="120" y="40" width="42" height="21"/>
<nil key="highlightedColor"/>
<attributedString key="attributedText">
<fragment content="Hello">
<attributes>
<color key="NSColor" white="0.5" alpha="1" colorSpace="calibratedWhite"/>
<font key="NSFont" metaFont="system" size="15"/>
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
    ]
}
