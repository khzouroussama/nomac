import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// Hosting and player view controllers, date pickers' styles, symbols' rendering modes and the order of attaching collections, as
/// ibtool (Xcode 27.0) writes them (`.github/scripts/nib_experiments.py` rounds 158 and 159).
@Suite struct ControllerKindTests {
    @Test(arguments: cases) func compilesAsXcode(_ document: ObservedDocument) throws {
        try document.check()
    }

    static let cases = [
        ObservedDocument(name: "sb-hosting-plain", path: "/tmp/Main.storyboard", target: "27.0", digest: "9d1b8ad8e2580e9f71c7a2ae86edee18f4eec29a2dc7b7602812c313f99286b3", warnings: [], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="vc1-aa-aaa">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
</dependencies>
<scenes>
<scene sceneID="sc1-aa-aaa">
<objects>
<hostingController id="vc1-aa-aaa" sceneMemberID="viewController"/>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#),
        ObservedDocument(name: "sb-hosting-class", path: "/tmp/Main.storyboard", target: "27.0", digest: "70eb8f2ff0e73a6f8e94aa75a2a41fb783c4a07b2f5d15fd82e0cf7fa0aa963f", warnings: [], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="vc1-aa-aaa">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
</dependencies>
<scenes>
<scene sceneID="sc1-aa-aaa">
<objects>
<hostingController id="vc1-aa-aaa" customClass="Host" customModule="T" customModuleProvider="target" sceneMemberID="viewController"/>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#),
        ObservedDocument(name: "sb-hosting-identifier", path: "/tmp/Main.storyboard", target: "27.0", digest: "b96f63b47f560d13821651d5e5934dd641985e0a1282de24bd999b2eeb048121", warnings: [], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="vc1-aa-aaa">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
</dependencies>
<scenes>
<scene sceneID="sc1-aa-aaa">
<objects>
<hostingController storyboardIdentifier="Host" id="vc1-aa-aaa" customClass="Host" customModule="T" customModuleProvider="target" sceneMemberID="viewController"/>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#),
        ObservedDocument(name: "sb-hosting-item", path: "/tmp/Main.storyboard", target: "27.0", digest: "3488812364a91f9dc04f57c5a7407f1ca93e3a4220826e054aa136f1f83feaf5", warnings: [], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="vc1-aa-aaa">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
</dependencies>
<scenes>
<scene sceneID="sc1-aa-aaa">
<objects>
<hostingController id="vc1-aa-aaa" customClass="Host" customModule="T" customModuleProvider="target" sceneMemberID="viewController">
<navigationItem key="navigationItem" title="Title" id="nvi-aa-aaa"/>
</hostingController>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#),
        ObservedDocument(name: "sb-hosting-tab-item", path: "/tmp/Main.storyboard", target: "27.0", digest: "64c2f12f076a029aa6180eec20614619059edc871c816607f16de837dd0d27ab", warnings: [], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="vc1-aa-aaa">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
</dependencies>
<scenes>
<scene sceneID="sc1-aa-aaa">
<objects>
<hostingController id="vc1-aa-aaa" customClass="Host" customModule="T" customModuleProvider="target" sceneMemberID="viewController">
<tabBarItem key="tabBarItem" title="Map" id="tbi-aa-aaa"/>
<navigationItem key="navigationItem" id="nvi-aa-aaa"/>
</hostingController>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#),
        ObservedDocument(name: "sb-avplayer-plain", path: "/tmp/Main.storyboard", target: "27.0", digest: "956f6b7de4d113236290d27209062ddffeeefce5f9949f79d63e5b19890ee926", warnings: [], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="vc1-aa-aaa">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
</dependencies>
<scenes>
<scene sceneID="sc1-aa-aaa">
<objects>
<avPlayerViewController videoGravity="AVLayerVideoGravityResizeAspect" id="vc1-aa-aaa" sceneMemberID="viewController"/>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#),
        ObservedDocument(name: "sb-avplayer-identifier", path: "/tmp/Main.storyboard", target: "27.0", digest: "8c9a8b9a3416805850461cb90780fd7db2498b1df1d567adaa52822ff560448d", warnings: [], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="vc1-aa-aaa">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
</dependencies>
<scenes>
<scene sceneID="sc1-aa-aaa">
<objects>
<avPlayerViewController storyboardIdentifier="Player" title="Video" videoGravity="AVLayerVideoGravityResizeAspect" id="vc1-aa-aaa" sceneMemberID="viewController"/>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#),
        ObservedDocument(name: "sb-avplayer-class", path: "/tmp/Main.storyboard", target: "27.0", digest: "2a06f9ba7408e27e9b825aab10f13cc1b48e2ccfd92401945727726eed68f236", warnings: [], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="vc1-aa-aaa">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
</dependencies>
<scenes>
<scene sceneID="sc1-aa-aaa">
<objects>
<avPlayerViewController videoGravity="AVLayerVideoGravityResizeAspect" id="vc1-aa-aaa" customClass="Player" customModule="T" customModuleProvider="target" sceneMemberID="viewController"/>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#),
        ObservedDocument(name: "sb-avplayer-no-gravity", path: "/tmp/Main.storyboard", target: "27.0", digest: "956f6b7de4d113236290d27209062ddffeeefce5f9949f79d63e5b19890ee926", warnings: [], document: #"""
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="vc1-aa-aaa">
<device id="retina6_12" orientation="portrait" appearance="light"/>
<dependencies>
<plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
<capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
</dependencies>
<scenes>
<scene sceneID="sc1-aa-aaa">
<objects>
<avPlayerViewController id="vc1-aa-aaa" sceneMemberID="viewController"/>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#),
        ObservedDocument(name: "sb-avplayer-segue", path: "/tmp/Main.storyboard", target: "27.0", digest: "fce31310a0884b8a50dcfc61e9d1c1b6d6076c7ef7f6bd579b9924e3c1635215", warnings: [], document: #"""
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
</view>
<connections>
<segue destination="vc1-aa-aaa" kind="presentation" identifier="P" id="sgp-aa-aaa"/>
</connections>
</viewController>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr9-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
<scene sceneID="sc1-aa-aaa">
<objects>
<avPlayerViewController videoGravity="AVLayerVideoGravityResizeAspect" id="vc1-aa-aaa" sceneMemberID="viewController"/>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#),
        ObservedDocument(name: "date-picker-style-wheels", path: "/tmp/View.xib", target: "27.0", digest: "5be199b775fe1edb81c248abdb74c5002d576b1b87c57e6f1995c1b3905cd799", warnings: [], document: #"""
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
<datePicker contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" datePickerMode="dateAndTime" minuteInterval="1" style="wheels" translatesAutoresizingMaskIntoConstraints="NO" id="dpk-aa-aa1">
<rect key="frame" x="0" y="0" width="350" height="216"/>
</datePicker>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "date-picker-style-compact", path: "/tmp/View.xib", target: "27.0", digest: "36513c945c483f7c9070a0d7022d0853cfeeaa0494be35f102b5e44b0cd869f7", warnings: [], document: #"""
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
<datePicker contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" datePickerMode="dateAndTime" minuteInterval="1" style="compact" translatesAutoresizingMaskIntoConstraints="NO" id="dpk-aa-aa1">
<rect key="frame" x="0" y="0" width="350" height="216"/>
</datePicker>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "date-picker-style-inline", path: "/tmp/View.xib", target: "27.0", digest: "583aaf3140175de4603ad8e86af08c7a361cd17ca3a86b25e1c7979f39f2a93f", warnings: [], document: #"""
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
<datePicker contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" datePickerMode="dateAndTime" minuteInterval="1" style="inline" translatesAutoresizingMaskIntoConstraints="NO" id="dpk-aa-aa1">
<rect key="frame" x="0" y="0" width="350" height="216"/>
</datePicker>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "date-picker-style-automatic", path: "/tmp/View.xib", target: "27.0", digest: "69fd227e26fbf5f4a66407ad0f492e0647e0dbe2765822890b5323c602483009", warnings: [], document: #"""
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
<datePicker contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" datePickerMode="dateAndTime" minuteInterval="1" style="automatic" translatesAutoresizingMaskIntoConstraints="NO" id="dpk-aa-aa1">
<rect key="frame" x="0" y="0" width="350" height="216"/>
</datePicker>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "date-picker-style-wheels-time", path: "/tmp/View.xib", target: "27.0", digest: "08c37ec3073cc749bc4a5674a4779141b8d3e20045fe93dcce579c391ca21fe6", warnings: [], document: #"""
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
<datePicker contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" datePickerMode="time" minuteInterval="5" style="wheels" translatesAutoresizingMaskIntoConstraints="NO" id="dpk-aa-aa1">
<rect key="frame" x="0" y="0" width="350" height="216"/>
</datePicker>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "date-picker-style-compact-date", path: "/tmp/View.xib", target: "27.0", digest: "c311de3559139e7e3511412461e4a64c11c2c92332ed05b2b6c4b9cd03200f2f", warnings: [], document: #"""
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
<datePicker contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" datePickerMode="date" minuteInterval="1" style="compact" translatesAutoresizingMaskIntoConstraints="NO" id="dpk-aa-aa1">
<rect key="frame" x="0" y="0" width="350" height="216"/>
</datePicker>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "date-picker-frame-wheels-50", path: "/tmp/View.xib", target: "27.0", digest: "6202654a5a4703c4c6f35727b54972ab40549b51c146059d0427acecf7971cc6", warnings: [], document: #"""
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
<datePicker contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" datePickerMode="dateAndTime" minuteInterval="1" style="wheels" translatesAutoresizingMaskIntoConstraints="NO" id="dpk-aa-aa1">
<rect key="frame" x="5" y="6" width="50" height="40"/>
</datePicker>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "date-picker-frame-wheels-320", path: "/tmp/View.xib", target: "27.0", digest: "2500bdf5bec269f9ab869890ebd8243e4aca6c1f3677af1e97453b1e55b5c6d2", warnings: [], document: #"""
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
<datePicker contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" datePickerMode="dateAndTime" minuteInterval="1" style="wheels" translatesAutoresizingMaskIntoConstraints="NO" id="dpk-aa-aa1">
<rect key="frame" x="10" y="20" width="320" height="216"/>
</datePicker>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "date-picker-frame-compact-leading", path: "/tmp/View.xib", target: "27.0", digest: "8cf7f7319332036bcf43ec580d66a5eb9f2a52d5d414df88b1e20800ca25ea3d", warnings: [], document: #"""
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
<datePicker contentMode="scaleToFill" contentHorizontalAlignment="leading" contentVerticalAlignment="center" datePickerMode="dateAndTime" minuteInterval="1" style="compact" translatesAutoresizingMaskIntoConstraints="NO" id="dpk-aa-aa1">
<rect key="frame" x="0" y="0" width="350" height="216"/>
</datePicker>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "date-picker-shape-time-5", path: "/tmp/View.xib", target: "27.0", digest: "404135b241850ec36e7d70e2622f8c1910e13e89366f5d1d1d4591cabd81242b", warnings: [], document: #"""
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
<datePicker contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" datePickerMode="time" minuteInterval="5" translatesAutoresizingMaskIntoConstraints="NO" id="dpk-aa-aa1">
<rect key="frame" x="0" y="0" width="350" height="216"/>
</datePicker>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "date-picker-shape-count-down-5", path: "/tmp/View.xib", target: "27.0", digest: nil, warnings: [], document: #"""
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
<datePicker contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" datePickerMode="countDownTimer" minuteInterval="5" translatesAutoresizingMaskIntoConstraints="NO" id="dpk-aa-aa1">
<rect key="frame" x="0" y="0" width="350" height="216"/>
</datePicker>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "sb-hosting-root", path: "/tmp/Main.storyboard", target: "27.0", digest: nil, warnings: [], document: #"""
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
<hostingController id="vc1-aa-aaa" customClass="Host" customModule="T" customModuleProvider="target" sceneMemberID="viewController"/>
<placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>
</objects>
<point key="canvasLocation" x="0" y="0"/>
</scene>
</scenes>
</document>
"""#),
        ObservedDocument(name: "symbol-rendering-template", path: "/tmp/View.xib", target: "27.0", digest: "c77d70cd0d67f28f5d6a0e20dc988817f914b0ce05b832bc30d17d76e32900f8", warnings: [], document: #"""
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
<imageView contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="iii-ii-ii1">
<rect key="frame" x="112" y="333" width="168" height="185"/>
<imageReference key="image" image="plus" catalog="system" renderingMode="template"/>
</imageView>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
<resources>
<image name="plus" catalog="system" width="128" height="113"/>
<systemColor name="labelColor">
<color white="0" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>
</systemColor>
<systemColor name="secondaryLabelColor">
<color red="0.2352941176" green="0.2352941176" blue="0.262745098" alpha="0.6" colorSpace="custom" customColorSpace="sRGB"/>
</systemColor>
<systemColor name="tertiaryLabelColor">
<color red="0.2352941176" green="0.2352941176" blue="0.262745098" alpha="0.3" colorSpace="custom" customColorSpace="sRGB"/>
</systemColor>
</resources>
</document>
"""#),
        ObservedDocument(name: "symbol-rendering-original", path: "/tmp/View.xib", target: "27.0", digest: "52f902f1e1fb78b2b5da4f0c57857724af5cf866e5848949c8841f1850c089ea", warnings: [], document: #"""
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
<imageView contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="iii-ii-ii1">
<rect key="frame" x="112" y="333" width="168" height="185"/>
<imageReference key="image" image="plus" catalog="system" renderingMode="original"/>
</imageView>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
<resources>
<image name="plus" catalog="system" width="128" height="113"/>
<systemColor name="labelColor">
<color white="0" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>
</systemColor>
<systemColor name="secondaryLabelColor">
<color red="0.2352941176" green="0.2352941176" blue="0.262745098" alpha="0.6" colorSpace="custom" customColorSpace="sRGB"/>
</systemColor>
<systemColor name="tertiaryLabelColor">
<color red="0.2352941176" green="0.2352941176" blue="0.262745098" alpha="0.3" colorSpace="custom" customColorSpace="sRGB"/>
</systemColor>
</resources>
</document>
"""#),
        ObservedDocument(name: "symbol-rendering-named-template-large", path: "/tmp/View.xib", target: "27.0", digest: "23962cbc7a616cdacf93330cdccd1e2c8b2e99310b8ef993580311bc18585ffc", warnings: [], document: #"""
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
<imageView contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="iii-ii-ii1">
<rect key="frame" x="112" y="333" width="168" height="185"/>
<imageReference key="image" image="Logo" symbolScale="large" renderingMode="template"/>
</imageView>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
<resources>
<image name="plus" catalog="system" width="128" height="113"/>
<systemColor name="labelColor">
<color white="0" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>
</systemColor>
<systemColor name="secondaryLabelColor">
<color red="0.2352941176" green="0.2352941176" blue="0.262745098" alpha="0.6" colorSpace="custom" customColorSpace="sRGB"/>
</systemColor>
<systemColor name="tertiaryLabelColor">
<color red="0.2352941176" green="0.2352941176" blue="0.262745098" alpha="0.3" colorSpace="custom" customColorSpace="sRGB"/>
</systemColor>
</resources>
</document>
"""#),
        ObservedDocument(name: "symbol-rendering-button-template", path: "/tmp/View.xib", target: "27.0", digest: "a12429aa71f6a10df4c1f951173d6b8ffdd8aff66f541eb3c7ad52bb7cf6d91c", warnings: [], document: #"""
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
<state key="normal">
<imageReference key="image" image="plus" catalog="system" renderingMode="template"/>
</state>
</button>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
</document>
"""#),
        ObservedDocument(name: "symbol-rendering-template-large", path: "/tmp/View.xib", target: "27.0", digest: "5d4924b2e2bb70566d526ace0feb009771908fe96da0ea45f0e34d002d32eaef", warnings: [], document: #"""
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
<imageView contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="iii-ii-ii1">
<rect key="frame" x="112" y="333" width="168" height="185"/>
<imageReference key="image" image="plus" catalog="system" symbolScale="large" renderingMode="template"/>
</imageView>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
</objects>
<resources>
<image name="plus" catalog="system" width="128" height="113"/>
<systemColor name="labelColor">
<color white="0" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>
</systemColor>
<systemColor name="secondaryLabelColor">
<color red="0.2352941176" green="0.2352941176" blue="0.262745098" alpha="0.6" colorSpace="custom" customColorSpace="sRGB"/>
</systemColor>
<systemColor name="tertiaryLabelColor">
<color red="0.2352941176" green="0.2352941176" blue="0.262745098" alpha="0.3" colorSpace="custom" customColorSpace="sRGB"/>
</systemColor>
</resources>
</document>
"""#),
        ObservedDocument(name: "gesture-kinds-press-middle", path: "/tmp/View.xib", target: "27.0", digest: "eb22d1e4c67cc26c365444ff8399198dd0f544920ed77bbdcbd0f95c80ec0816", warnings: [], document: #"""
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
<view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="src-aa-a0">
<rect key="frame" x="0" y="20" width="10" height="10"/>
<connections>
<outletCollection property="gestureRecognizers" destination="tap-aa-a01" appends="YES" id="occ-aa-a01"/>
</connections>
</view>
<view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="src-aa-a1">
<rect key="frame" x="10" y="20" width="10" height="10"/>
<connections>
<outletCollection property="gestureRecognizers" destination="tap-aa-a02" appends="YES" id="occ-aa-a02"/>
</connections>
</view>
<view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="src-aa-a2">
<rect key="frame" x="20" y="20" width="10" height="10"/>
<connections>
<outletCollection property="gestureRecognizers" destination="tap-aa-a03" appends="YES" id="occ-aa-a03"/>
</connections>
</view>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
<tapGestureRecognizer id="tap-aa-a01"/>
<pongPressGestureRecognizer id="tap-aa-a02" minimumPressDuration="0.5"/>
<tapGestureRecognizer id="tap-aa-a03"/>
</objects>
</document>
"""#),
        ObservedDocument(name: "gesture-kinds-tap-swipe-press", path: "/tmp/View.xib", target: "27.0", digest: "5033045bcacaf519fae3f4501362ea1df283f31195ccc8840febdb39e0cde735", warnings: [], document: #"""
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
<view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="src-aa-a0">
<rect key="frame" x="0" y="20" width="10" height="10"/>
<connections>
<outletCollection property="gestureRecognizers" destination="tap-aa-a01" appends="YES" id="occ-aa-a01"/>
</connections>
</view>
<view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="src-aa-a1">
<rect key="frame" x="10" y="20" width="10" height="10"/>
<connections>
<outletCollection property="gestureRecognizers" destination="tap-aa-a02" appends="YES" id="occ-aa-a02"/>
</connections>
</view>
<view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="src-aa-a2">
<rect key="frame" x="20" y="20" width="10" height="10"/>
<connections>
<outletCollection property="gestureRecognizers" destination="tap-aa-a03" appends="YES" id="occ-aa-a03"/>
</connections>
</view>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
<tapGestureRecognizer id="tap-aa-a01"/>
<swipeGestureRecognizer id="tap-aa-a02"/>
<pongPressGestureRecognizer id="tap-aa-a03" minimumPressDuration="0.5"/>
</objects>
</document>
"""#),
        ObservedDocument(name: "gesture-kinds-press-tap-then-swipe", path: "/tmp/View.xib", target: "27.0", digest: "2d78b1b42a9e7cbbff00ef3a0788bf32bee725857a9b3d5b4068293cba2cf953", warnings: [], document: #"""
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
<view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="src-aa-a0">
<rect key="frame" x="0" y="20" width="10" height="10"/>
<connections>
<outletCollection property="gestureRecognizers" destination="tap-aa-a01" appends="YES" id="occ-aa-a01"/>
<outletCollection property="gestureRecognizers" destination="tap-aa-a02" appends="YES" id="occ-aa-a02"/>
</connections>
</view>
<view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="src-aa-a1">
<rect key="frame" x="10" y="20" width="10" height="10"/>
<connections>
<outletCollection property="gestureRecognizers" destination="tap-aa-a03" appends="YES" id="occ-aa-a03"/>
</connections>
</view>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
<pongPressGestureRecognizer id="tap-aa-a01" minimumPressDuration="0.5"/>
<tapGestureRecognizer id="tap-aa-a02"/>
<swipeGestureRecognizer id="tap-aa-a03"/>
</objects>
</document>
"""#),
        ObservedDocument(name: "gesture-counts-1-2-1", path: "/tmp/View.xib", target: "27.0", digest: "278bc65a4a4c9eb9e3e08caaeff46f04bdc5d4ace3b57ba4192989fb1722c9ad", warnings: [], document: #"""
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
<view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="src-aa-a0">
<rect key="frame" x="0" y="20" width="10" height="10"/>
<connections>
<outletCollection property="gestureRecognizers" destination="tap-aa-a01" appends="YES" id="occ-aa-a01"/>
</connections>
</view>
<view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="src-aa-a1">
<rect key="frame" x="10" y="20" width="10" height="10"/>
<connections>
<outletCollection property="gestureRecognizers" destination="tap-aa-a02" appends="YES" id="occ-aa-a02"/>
<outletCollection property="gestureRecognizers" destination="tap-aa-a03" appends="YES" id="occ-aa-a03"/>
</connections>
</view>
<view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="src-aa-a2">
<rect key="frame" x="20" y="20" width="10" height="10"/>
<connections>
<outletCollection property="gestureRecognizers" destination="tap-aa-a04" appends="YES" id="occ-aa-a04"/>
</connections>
</view>
</subviews>
<point key="canvasLocation" x="0" y="0"/>
</view>
<tapGestureRecognizer id="tap-aa-a01"/>
<tapGestureRecognizer id="tap-aa-a02"/>
<tapGestureRecognizer id="tap-aa-a03"/>
<tapGestureRecognizer id="tap-aa-a04"/>
</objects>
</document>
"""#),
    ]
}
