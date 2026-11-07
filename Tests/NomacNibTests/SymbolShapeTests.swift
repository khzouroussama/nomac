import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for symbol configurations (`.github/scripts/nib_experiments.py` round 157): every weight,
/// a font of a text style or of the system beside a scale and a weight, and a font without its type, which changes nothing.
@Suite struct SymbolShapeTests {
    @Test(arguments: cases) func compilesAsXcode(_ document: ObservedDocument) throws {
        try document.check()
    }

    static let cases = [
        ObservedDocument(name: "symbol-weight-ultraLight", path: "/tmp/View.xib", target: "27.0", digest: "4970c7b1732094d8106081b5d33262d0bb5867c67b2051da69e5880ea77b5d27", warnings: [], document: #"""
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
<imageView contentMode="scaleToFill" image="plus" catalog="system" translatesAutoresizingMaskIntoConstraints="NO" id="iii-ii-ii1">
<rect key="frame" x="112" y="333" width="168" height="185"/>
<preferredSymbolConfiguration key="preferredSymbolConfiguration" weight="ultraLight"/>
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
        ObservedDocument(name: "symbol-weight-thin", path: "/tmp/View.xib", target: "27.0", digest: "384d4889de7f8f20cec73c9813d7ce7fac3e274e7db35d8648db6b218f93dbdd", warnings: [], document: #"""
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
<imageView contentMode="scaleToFill" image="plus" catalog="system" translatesAutoresizingMaskIntoConstraints="NO" id="iii-ii-ii1">
<rect key="frame" x="112" y="333" width="168" height="185"/>
<preferredSymbolConfiguration key="preferredSymbolConfiguration" weight="thin"/>
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
        ObservedDocument(name: "symbol-weight-medium", path: "/tmp/View.xib", target: "27.0", digest: "bbdc8037ff128a69f54ba32f61f9a5702e91ba68f495eb068a6dcde794321652", warnings: [], document: #"""
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
<imageView contentMode="scaleToFill" image="plus" catalog="system" translatesAutoresizingMaskIntoConstraints="NO" id="iii-ii-ii1">
<rect key="frame" x="112" y="333" width="168" height="185"/>
<preferredSymbolConfiguration key="preferredSymbolConfiguration" weight="medium"/>
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
        ObservedDocument(name: "symbol-weight-semibold", path: "/tmp/View.xib", target: "27.0", digest: "fd2c102b87c981f46ea185229550594599bbcbc1590d69eb66708f4e4544a8ee", warnings: [], document: #"""
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
<imageView contentMode="scaleToFill" image="plus" catalog="system" translatesAutoresizingMaskIntoConstraints="NO" id="iii-ii-ii1">
<rect key="frame" x="112" y="333" width="168" height="185"/>
<preferredSymbolConfiguration key="preferredSymbolConfiguration" weight="semibold"/>
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
        ObservedDocument(name: "symbol-weight-heavy", path: "/tmp/View.xib", target: "27.0", digest: "6db36ee4d07c6c1645fb82c174d4f7e165f9c5729265a7caa7bdaf584e78f0e5", warnings: [], document: #"""
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
<imageView contentMode="scaleToFill" image="plus" catalog="system" translatesAutoresizingMaskIntoConstraints="NO" id="iii-ii-ii1">
<rect key="frame" x="112" y="333" width="168" height="185"/>
<preferredSymbolConfiguration key="preferredSymbolConfiguration" weight="heavy"/>
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
        ObservedDocument(name: "symbol-weight-black", path: "/tmp/View.xib", target: "27.0", digest: "1392a35ca7358b240bab516be89869611c29ab0f06151823b68f17d9cd425132", warnings: [], document: #"""
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
<imageView contentMode="scaleToFill" image="plus" catalog="system" translatesAutoresizingMaskIntoConstraints="NO" id="iii-ii-ii1">
<rect key="frame" x="112" y="333" width="168" height="185"/>
<preferredSymbolConfiguration key="preferredSymbolConfiguration" weight="black"/>
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
        ObservedDocument(name: "symbol-weight-medium-large", path: "/tmp/View.xib", target: "27.0", digest: "608229fb212b532efc09bca886e09f2b1feb8e0c0d57fea975b33974c3398926", warnings: [], document: #"""
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
<imageView contentMode="scaleToFill" image="plus" catalog="system" translatesAutoresizingMaskIntoConstraints="NO" id="iii-ii-ii1">
<rect key="frame" x="112" y="333" width="168" height="185"/>
<preferredSymbolConfiguration key="preferredSymbolConfiguration" scale="large" weight="medium"/>
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
        ObservedDocument(name: "symbol-weight-medium-size", path: "/tmp/View.xib", target: "27.0", digest: "937c30d7c38bd3376069ddf30cdc74b24f99bd7a399a7b75921d743a1f5ca08f", warnings: [], document: #"""
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
<imageView contentMode="scaleToFill" image="plus" catalog="system" translatesAutoresizingMaskIntoConstraints="NO" id="iii-ii-ii1">
<rect key="frame" x="112" y="333" width="168" height="185"/>
<preferredSymbolConfiguration key="preferredSymbolConfiguration" configurationType="pointSize" pointSize="21" weight="medium"/>
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
        ObservedDocument(name: "symbol-size-scale-weight", path: "/tmp/View.xib", target: "27.0", digest: "618644aa055ab11b59186d169c2a3bfab0e5efe1cb201b4d1e0af15580140aca", warnings: [], document: #"""
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
<imageView contentMode="scaleToFill" image="plus" catalog="system" translatesAutoresizingMaskIntoConstraints="NO" id="iii-ii-ii1">
<rect key="frame" x="112" y="333" width="168" height="185"/>
<preferredSymbolConfiguration key="preferredSymbolConfiguration" configurationType="pointSize" pointSize="17" scale="large" weight="regular"/>
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
        ObservedDocument(name: "symbol-size-scale", path: "/tmp/View.xib", target: "27.0", digest: "ac378b260a3c9c9405587cf7c9cb46d4631d036c3cb2d0ecae9e59eee1838410", warnings: [], document: #"""
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
<imageView contentMode="scaleToFill" image="plus" catalog="system" translatesAutoresizingMaskIntoConstraints="NO" id="iii-ii-ii1">
<rect key="frame" x="112" y="333" width="168" height="185"/>
<preferredSymbolConfiguration key="preferredSymbolConfiguration" configurationType="pointSize" pointSize="17" scale="default"/>
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
        ObservedDocument(name: "symbol-font-scale-large-regular", path: "/tmp/View.xib", target: "27.0", digest: "eeb652a3a5b6d3b1035072b5244d3196d831ac537114fb788ce27197161c9421", warnings: [], document: #"""
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
<imageView contentMode="scaleToFill" image="plus" catalog="system" translatesAutoresizingMaskIntoConstraints="NO" id="iii-ii-ii1">
<rect key="frame" x="112" y="333" width="168" height="185"/>
<preferredSymbolConfiguration key="preferredSymbolConfiguration" configurationType="font" scale="large" weight="regular">
<fontDescription key="fontDescription" style="UICTFontTextStyleHeadline"/>
</preferredSymbolConfiguration>
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
        ObservedDocument(name: "symbol-font-scale-default", path: "/tmp/View.xib", target: "27.0", digest: "7fc96b36c4affa57c2ad0daec6ef2b69f949f1d18002032833e61952950d29f1", warnings: [], document: #"""
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
<imageView contentMode="scaleToFill" image="plus" catalog="system" translatesAutoresizingMaskIntoConstraints="NO" id="iii-ii-ii1">
<rect key="frame" x="112" y="333" width="168" height="185"/>
<preferredSymbolConfiguration key="preferredSymbolConfiguration" configurationType="font" scale="default">
<fontDescription key="fontDescription" style="UICTFontTextStyleHeadline"/>
</preferredSymbolConfiguration>
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
        ObservedDocument(name: "symbol-font-weight-medium", path: "/tmp/View.xib", target: "27.0", digest: "9aabdda09167f5ee8f873a615039ddac07cbfc4eaa6a2358cf5a6a3142c897c1", warnings: [], document: #"""
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
<imageView contentMode="scaleToFill" image="plus" catalog="system" translatesAutoresizingMaskIntoConstraints="NO" id="iii-ii-ii1">
<rect key="frame" x="112" y="333" width="168" height="185"/>
<preferredSymbolConfiguration key="preferredSymbolConfiguration" configurationType="font" weight="medium">
<fontDescription key="fontDescription" style="UICTFontTextStyleHeadline"/>
</preferredSymbolConfiguration>
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
        ObservedDocument(name: "symbol-font-style-Body", path: "/tmp/View.xib", target: "27.0", digest: "7849986d35be56d12b73027799ba946aa1421ec0634177d21c8ccb9f8056d90b", warnings: [], document: #"""
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
<imageView contentMode="scaleToFill" image="plus" catalog="system" translatesAutoresizingMaskIntoConstraints="NO" id="iii-ii-ii1">
<rect key="frame" x="112" y="333" width="168" height="185"/>
<preferredSymbolConfiguration key="preferredSymbolConfiguration" configurationType="font">
<fontDescription key="fontDescription" style="UICTFontTextStyleBody"/>
</preferredSymbolConfiguration>
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
        ObservedDocument(name: "symbol-font-style-Subhead", path: "/tmp/View.xib", target: "27.0", digest: "bdb514221004893c8d72ba6a6875006af59236f63bd87c6b1e088a4b8d529e77", warnings: [], document: #"""
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
<imageView contentMode="scaleToFill" image="plus" catalog="system" translatesAutoresizingMaskIntoConstraints="NO" id="iii-ii-ii1">
<rect key="frame" x="112" y="333" width="168" height="185"/>
<preferredSymbolConfiguration key="preferredSymbolConfiguration" configurationType="font">
<fontDescription key="fontDescription" style="UICTFontTextStyleSubhead"/>
</preferredSymbolConfiguration>
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
        ObservedDocument(name: "symbol-font-style-Title0", path: "/tmp/View.xib", target: "27.0", digest: "eb2b65525d4d9c538e3feb1c878d75a6f2f797f57906980cbcff5ae1b007b67e", warnings: [], document: #"""
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
<imageView contentMode="scaleToFill" image="plus" catalog="system" translatesAutoresizingMaskIntoConstraints="NO" id="iii-ii-ii1">
<rect key="frame" x="112" y="333" width="168" height="185"/>
<preferredSymbolConfiguration key="preferredSymbolConfiguration" configurationType="font">
<fontDescription key="fontDescription" style="UICTFontTextStyleTitle0"/>
</preferredSymbolConfiguration>
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
        ObservedDocument(name: "symbol-font-style-Headline-large", path: "/tmp/View.xib", target: "27.0", digest: "eeb652a3a5b6d3b1035072b5244d3196d831ac537114fb788ce27197161c9421", warnings: [], document: #"""
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
<imageView contentMode="scaleToFill" image="plus" catalog="system" translatesAutoresizingMaskIntoConstraints="NO" id="iii-ii-ii1">
<rect key="frame" x="112" y="333" width="168" height="185"/>
<preferredSymbolConfiguration key="preferredSymbolConfiguration" configurationType="font" scale="large" weight="regular">
<fontDescription key="fontDescription" style="UICTFontTextStyleHeadline"/>
</preferredSymbolConfiguration>
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
        ObservedDocument(name: "symbol-font-system", path: "/tmp/View.xib", target: "27.0", digest: "ce0553f89f9cb7516613bac8612a001195d0ebe040212225271c3e4d8a69641d", warnings: [], document: #"""
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
<imageView contentMode="scaleToFill" image="plus" catalog="system" translatesAutoresizingMaskIntoConstraints="NO" id="iii-ii-ii1">
<rect key="frame" x="112" y="333" width="168" height="185"/>
<preferredSymbolConfiguration key="preferredSymbolConfiguration" configurationType="font">
<fontDescription key="fontDescription" pointSize="17" type="system"/>
</preferredSymbolConfiguration>
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
        ObservedDocument(name: "symbol-font-system-weight", path: "/tmp/View.xib", target: "27.0", digest: "5c0d341443f3340b8fecf11b56f1eb0880f2ddd12695c247d1786f2aa8562b31", warnings: [], document: #"""
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
<imageView contentMode="scaleToFill" image="plus" catalog="system" translatesAutoresizingMaskIntoConstraints="NO" id="iii-ii-ii1">
<rect key="frame" x="112" y="333" width="168" height="185"/>
<preferredSymbolConfiguration key="preferredSymbolConfiguration" configurationType="font">
<fontDescription key="fontDescription" pointSize="17" type="system" weight="semibold"/>
</preferredSymbolConfiguration>
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
        ObservedDocument(name: "symbol-font-system-scale", path: "/tmp/View.xib", target: "27.0", digest: "618644aa055ab11b59186d169c2a3bfab0e5efe1cb201b4d1e0af15580140aca", warnings: [], document: #"""
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
<imageView contentMode="scaleToFill" image="plus" catalog="system" translatesAutoresizingMaskIntoConstraints="NO" id="iii-ii-ii1">
<rect key="frame" x="112" y="333" width="168" height="185"/>
<preferredSymbolConfiguration key="preferredSymbolConfiguration" configurationType="font" scale="large">
<fontDescription key="fontDescription" pointSize="17" type="system"/>
</preferredSymbolConfiguration>
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
        ObservedDocument(name: "symbol-font-no-type", path: "/tmp/View.xib", target: "27.0", digest: "b1e0d695bcba7ba394b91def6f1a20429032e0edefb6ade2a1ac3b44e9a564dd", warnings: [], document: #"""
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
<imageView contentMode="scaleToFill" image="plus" catalog="system" translatesAutoresizingMaskIntoConstraints="NO" id="iii-ii-ii1">
<rect key="frame" x="112" y="333" width="168" height="185"/>
<preferredSymbolConfiguration key="preferredSymbolConfiguration">
<fontDescription key="fontDescription" style="UICTFontTextStyleHeadline"/>
</preferredSymbolConfiguration>
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
        ObservedDocument(name: "symbol-font-no-type-scale", path: "/tmp/View.xib", target: "27.0", digest: "235a1d585ddf8f847aa1973113671ab7794e3a889edc4442b2743fdfb8dee61c", warnings: [], document: #"""
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
<imageView contentMode="scaleToFill" image="plus" catalog="system" translatesAutoresizingMaskIntoConstraints="NO" id="iii-ii-ii1">
<rect key="frame" x="112" y="333" width="168" height="185"/>
<preferredSymbolConfiguration key="preferredSymbolConfiguration" scale="large">
<fontDescription key="fontDescription" style="UICTFontTextStyleHeadline"/>
</preferredSymbolConfiguration>
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
        ObservedDocument(name: "symbol-font-no-type-weight", path: "/tmp/View.xib", target: "27.0", digest: "6f68648f4e049c93e7eb346f70cdd80d9bf43beb2f77d3d5bc96c4794bea9ef8", warnings: [], document: #"""
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
<imageView contentMode="scaleToFill" image="plus" catalog="system" translatesAutoresizingMaskIntoConstraints="NO" id="iii-ii-ii1">
<rect key="frame" x="112" y="333" width="168" height="185"/>
<preferredSymbolConfiguration key="preferredSymbolConfiguration" weight="bold">
<fontDescription key="fontDescription" style="UICTFontTextStyleHeadline"/>
</preferredSymbolConfiguration>
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
    ]
}
