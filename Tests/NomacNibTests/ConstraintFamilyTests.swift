import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for baselines, constraints' custom classes and anchors, margins
/// with multipliers, symbolic constants and variations, `verifyAmbiguity`, and a cell's safe area
/// (`.github/scripts/nib_experiments.py`, `cs-*`): sizes and SHA-256 digests of Xcode's nibs.
@Suite struct ConstraintFamilyTests {
    static let cases: [(String, String, Int, String)] = [
        ("cs-baseline-crossed", #"""
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
            <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="xxx-xx-xx1">
            <rect key="frame" x="10" y="20" width="100" height="50"/>
            </view>
            <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="yyy-yy-yy1">
            <rect key="frame" x="150" y="20" width="100" height="50"/>
            </view>
            </subviews>
            <constraints>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="10" id="c00-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="20" id="c01-aa-aaa"/>
            <constraint firstItem="yyy-yy-yy1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="150" id="c02-aa-aaa"/>
            <constraint firstItem="yyy-yy-yy1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="20" id="c03-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="baseline" secondItem="yyy-yy-yy1" secondAttribute="firstBaseline" constant="0" id="c10-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="firstBaseline" secondItem="yyy-yy-yy1" secondAttribute="baseline" constant="1" id="c11-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="baseline" secondItem="yyy-yy-yy1" secondAttribute="baseline" constant="2" id="c12-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="top" secondItem="yyy-yy-yy1" secondAttribute="baseline" constant="3" id="c13-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="baseline" secondItem="yyy-yy-yy1" secondAttribute="top" constant="4" id="c14-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="centerY" secondItem="yyy-yy-yy1" secondAttribute="baseline" constant="5" id="c15-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="baseline" secondItem="yyy-yy-yy1" secondAttribute="centerY" constant="6" id="c16-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="bottom" secondItem="yyy-yy-yy1" secondAttribute="baseline" constant="7" id="c17-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="baseline" secondItem="yyy-yy-yy1" secondAttribute="bottom" constant="8" id="c18-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="firstBaseline" secondItem="yyy-yy-yy1" secondAttribute="firstBaseline" constant="9" id="c19-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="top" secondItem="yyy-yy-yy1" secondAttribute="firstBaseline" constant="10" id="c20-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="firstBaseline" secondItem="yyy-yy-yy1" secondAttribute="top" constant="11" id="c21-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="bottom" secondItem="yyy-yy-yy1" secondAttribute="firstBaseline" constant="12" id="c22-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="firstBaseline" secondItem="yyy-yy-yy1" secondAttribute="bottom" constant="13" id="c23-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="centerY" secondItem="yyy-yy-yy1" secondAttribute="firstBaseline" constant="14" id="c24-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="firstBaseline" secondItem="yyy-yy-yy1" secondAttribute="centerY" constant="15" id="c25-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
            </view>
            </objects>
            </document>
            """#, 2432, "fc22553825c055d57921ead8b0f8322dde86dbaee4382e8c127239e050bc67e3"),
        ("cs-baseline-attributes", #"""
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
            <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="xxx-xx-xx1">
            <rect key="frame" x="10" y="20" width="100" height="50"/>
            </view>
            <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="yyy-yy-yy1">
            <rect key="frame" x="150" y="20" width="100" height="50"/>
            </view>
            </subviews>
            <constraints>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="10" id="c00-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="20" id="c01-aa-aaa"/>
            <constraint firstItem="yyy-yy-yy1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="150" id="c02-aa-aaa"/>
            <constraint firstItem="yyy-yy-yy1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="20" id="c03-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="centerX" secondItem="yyy-yy-yy1" secondAttribute="centerX" id="c10-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="leading" secondItem="yyy-yy-yy1" secondAttribute="leading" id="c11-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="centerY" secondItem="yyy-yy-yy1" secondAttribute="centerY" id="c12-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="bottom" secondItem="yyy-yy-yy1" secondAttribute="bottom" id="c13-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="baseline" secondItem="yyy-yy-yy1" secondAttribute="baseline" id="c14-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="firstBaseline" secondItem="yyy-yy-yy1" secondAttribute="firstBaseline" id="c15-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="top" secondItem="yyy-yy-yy1" secondAttribute="top" id="c16-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="height" secondItem="yyy-yy-yy1" secondAttribute="height" id="c17-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
            </view>
            </objects>
            </document>
            """#, 1793, "00aa22a24cfb05a0be4f014559bd12e766684e9fa093ba245eacb8b76423e0e4"),
        ("cs-pairs-sub-first", #"""
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
            <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="xxx-xx-xx1">
            <rect key="frame" x="10" y="20" width="100" height="50"/>
            </view>
            </subviews>
            <constraints>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="centerY" secondItem="iN0-l3-epB" secondAttribute="centerY" constant="1" id="c00-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="centerY" secondItem="iN0-l3-epB" secondAttribute="bottom" constant="2" id="c01-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="centerY" secondItem="iN0-l3-epB" secondAttribute="top" constant="3" id="c02-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="centerY" secondItem="iN0-l3-epB" secondAttribute="baseline" constant="4" id="c03-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="centerY" secondItem="iN0-l3-epB" secondAttribute="firstBaseline" constant="5" id="c04-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="bottom" secondItem="iN0-l3-epB" secondAttribute="centerY" constant="6" id="c05-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="bottom" secondItem="iN0-l3-epB" secondAttribute="bottom" constant="7" id="c06-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="bottom" secondItem="iN0-l3-epB" secondAttribute="top" constant="8" id="c07-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="bottom" secondItem="iN0-l3-epB" secondAttribute="baseline" constant="9" id="c08-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="bottom" secondItem="iN0-l3-epB" secondAttribute="firstBaseline" constant="10" id="c09-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="centerY" constant="11" id="c10-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="bottom" constant="12" id="c11-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="13" id="c12-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="baseline" constant="14" id="c13-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="firstBaseline" constant="15" id="c14-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="baseline" secondItem="iN0-l3-epB" secondAttribute="centerY" constant="16" id="c15-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="baseline" secondItem="iN0-l3-epB" secondAttribute="bottom" constant="17" id="c16-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="baseline" secondItem="iN0-l3-epB" secondAttribute="top" constant="18" id="c17-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="baseline" secondItem="iN0-l3-epB" secondAttribute="baseline" constant="19" id="c18-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="baseline" secondItem="iN0-l3-epB" secondAttribute="firstBaseline" constant="20" id="c19-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="firstBaseline" secondItem="iN0-l3-epB" secondAttribute="centerY" constant="21" id="c20-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="firstBaseline" secondItem="iN0-l3-epB" secondAttribute="bottom" constant="22" id="c21-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="firstBaseline" secondItem="iN0-l3-epB" secondAttribute="top" constant="23" id="c22-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="firstBaseline" secondItem="iN0-l3-epB" secondAttribute="baseline" constant="24" id="c23-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="firstBaseline" secondItem="iN0-l3-epB" secondAttribute="firstBaseline" constant="25" id="c24-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="centerX" secondItem="iN0-l3-epB" secondAttribute="centerX" constant="26" id="c25-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="width" secondItem="iN0-l3-epB" secondAttribute="width" constant="27" id="c26-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="height" secondItem="iN0-l3-epB" secondAttribute="height" constant="28" id="c27-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="trailing" secondItem="iN0-l3-epB" secondAttribute="trailing" constant="29" id="c28-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="30" id="c29-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
            </view>
            </objects>
            </document>
            """#, 2985, "83876179780b44c90017e78adbe50bfadac90f5143cbe661be8c47d4cc71b8eb"),
        ("cs-pairs-view-first", #"""
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
            <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="xxx-xx-xx1">
            <rect key="frame" x="10" y="20" width="100" height="50"/>
            </view>
            </subviews>
            <constraints>
            <constraint firstAttribute="centerY" secondItem="xxx-xx-xx1" secondAttribute="centerY" constant="1" id="c00-aa-aaa"/>
            <constraint firstAttribute="centerY" secondItem="xxx-xx-xx1" secondAttribute="bottom" constant="2" id="c01-aa-aaa"/>
            <constraint firstAttribute="centerY" secondItem="xxx-xx-xx1" secondAttribute="top" constant="3" id="c02-aa-aaa"/>
            <constraint firstAttribute="centerY" secondItem="xxx-xx-xx1" secondAttribute="baseline" constant="4" id="c03-aa-aaa"/>
            <constraint firstAttribute="centerY" secondItem="xxx-xx-xx1" secondAttribute="firstBaseline" constant="5" id="c04-aa-aaa"/>
            <constraint firstAttribute="bottom" secondItem="xxx-xx-xx1" secondAttribute="centerY" constant="6" id="c05-aa-aaa"/>
            <constraint firstAttribute="bottom" secondItem="xxx-xx-xx1" secondAttribute="bottom" constant="7" id="c06-aa-aaa"/>
            <constraint firstAttribute="bottom" secondItem="xxx-xx-xx1" secondAttribute="top" constant="8" id="c07-aa-aaa"/>
            <constraint firstAttribute="bottom" secondItem="xxx-xx-xx1" secondAttribute="baseline" constant="9" id="c08-aa-aaa"/>
            <constraint firstAttribute="bottom" secondItem="xxx-xx-xx1" secondAttribute="firstBaseline" constant="10" id="c09-aa-aaa"/>
            <constraint firstAttribute="top" secondItem="xxx-xx-xx1" secondAttribute="centerY" constant="11" id="c10-aa-aaa"/>
            <constraint firstAttribute="top" secondItem="xxx-xx-xx1" secondAttribute="bottom" constant="12" id="c11-aa-aaa"/>
            <constraint firstAttribute="top" secondItem="xxx-xx-xx1" secondAttribute="top" constant="13" id="c12-aa-aaa"/>
            <constraint firstAttribute="top" secondItem="xxx-xx-xx1" secondAttribute="baseline" constant="14" id="c13-aa-aaa"/>
            <constraint firstAttribute="top" secondItem="xxx-xx-xx1" secondAttribute="firstBaseline" constant="15" id="c14-aa-aaa"/>
            <constraint firstAttribute="baseline" secondItem="xxx-xx-xx1" secondAttribute="centerY" constant="16" id="c15-aa-aaa"/>
            <constraint firstAttribute="baseline" secondItem="xxx-xx-xx1" secondAttribute="bottom" constant="17" id="c16-aa-aaa"/>
            <constraint firstAttribute="baseline" secondItem="xxx-xx-xx1" secondAttribute="top" constant="18" id="c17-aa-aaa"/>
            <constraint firstAttribute="baseline" secondItem="xxx-xx-xx1" secondAttribute="baseline" constant="19" id="c18-aa-aaa"/>
            <constraint firstAttribute="baseline" secondItem="xxx-xx-xx1" secondAttribute="firstBaseline" constant="20" id="c19-aa-aaa"/>
            <constraint firstAttribute="firstBaseline" secondItem="xxx-xx-xx1" secondAttribute="centerY" constant="21" id="c20-aa-aaa"/>
            <constraint firstAttribute="firstBaseline" secondItem="xxx-xx-xx1" secondAttribute="bottom" constant="22" id="c21-aa-aaa"/>
            <constraint firstAttribute="firstBaseline" secondItem="xxx-xx-xx1" secondAttribute="top" constant="23" id="c22-aa-aaa"/>
            <constraint firstAttribute="firstBaseline" secondItem="xxx-xx-xx1" secondAttribute="baseline" constant="24" id="c23-aa-aaa"/>
            <constraint firstAttribute="firstBaseline" secondItem="xxx-xx-xx1" secondAttribute="firstBaseline" constant="25" id="c24-aa-aaa"/>
            <constraint firstAttribute="centerX" secondItem="xxx-xx-xx1" secondAttribute="centerX" constant="26" id="c25-aa-aaa"/>
            <constraint firstAttribute="width" secondItem="xxx-xx-xx1" secondAttribute="width" constant="27" id="c26-aa-aaa"/>
            <constraint firstAttribute="height" secondItem="xxx-xx-xx1" secondAttribute="height" constant="28" id="c27-aa-aaa"/>
            <constraint firstAttribute="trailing" secondItem="xxx-xx-xx1" secondAttribute="trailing" constant="29" id="c28-aa-aaa"/>
            <constraint firstAttribute="leading" secondItem="xxx-xx-xx1" secondAttribute="leading" constant="30" id="c29-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
            </view>
            </objects>
            </document>
            """#, 2985, "15c88c96e8d7cd66622c9d9fa484312380f64117ba8703de74bf2229e59b343a"),
        ("cs-pairs-sub-safe", #"""
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
            <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="xxx-xx-xx1">
            <rect key="frame" x="10" y="20" width="100" height="50"/>
            </view>
            </subviews>
            <viewLayoutGuide key="safeArea" id="vUN-kp-3ea"/>
            <constraints>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="centerY" secondItem="vUN-kp-3ea" secondAttribute="centerY" constant="1" id="c00-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="centerY" secondItem="vUN-kp-3ea" secondAttribute="bottom" constant="2" id="c01-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="centerY" secondItem="vUN-kp-3ea" secondAttribute="top" constant="3" id="c02-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="centerY" secondItem="vUN-kp-3ea" secondAttribute="baseline" constant="4" id="c03-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="centerY" secondItem="vUN-kp-3ea" secondAttribute="firstBaseline" constant="5" id="c04-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="bottom" secondItem="vUN-kp-3ea" secondAttribute="centerY" constant="6" id="c05-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="bottom" secondItem="vUN-kp-3ea" secondAttribute="bottom" constant="7" id="c06-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="bottom" secondItem="vUN-kp-3ea" secondAttribute="top" constant="8" id="c07-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="bottom" secondItem="vUN-kp-3ea" secondAttribute="baseline" constant="9" id="c08-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="bottom" secondItem="vUN-kp-3ea" secondAttribute="firstBaseline" constant="10" id="c09-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="top" secondItem="vUN-kp-3ea" secondAttribute="centerY" constant="11" id="c10-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="top" secondItem="vUN-kp-3ea" secondAttribute="bottom" constant="12" id="c11-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="top" secondItem="vUN-kp-3ea" secondAttribute="top" constant="13" id="c12-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="top" secondItem="vUN-kp-3ea" secondAttribute="baseline" constant="14" id="c13-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="top" secondItem="vUN-kp-3ea" secondAttribute="firstBaseline" constant="15" id="c14-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="baseline" secondItem="vUN-kp-3ea" secondAttribute="centerY" constant="16" id="c15-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="baseline" secondItem="vUN-kp-3ea" secondAttribute="bottom" constant="17" id="c16-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="baseline" secondItem="vUN-kp-3ea" secondAttribute="top" constant="18" id="c17-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="baseline" secondItem="vUN-kp-3ea" secondAttribute="baseline" constant="19" id="c18-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="baseline" secondItem="vUN-kp-3ea" secondAttribute="firstBaseline" constant="20" id="c19-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="firstBaseline" secondItem="vUN-kp-3ea" secondAttribute="centerY" constant="21" id="c20-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="firstBaseline" secondItem="vUN-kp-3ea" secondAttribute="bottom" constant="22" id="c21-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="firstBaseline" secondItem="vUN-kp-3ea" secondAttribute="top" constant="23" id="c22-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="firstBaseline" secondItem="vUN-kp-3ea" secondAttribute="baseline" constant="24" id="c23-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="firstBaseline" secondItem="vUN-kp-3ea" secondAttribute="firstBaseline" constant="25" id="c24-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="centerX" secondItem="vUN-kp-3ea" secondAttribute="centerX" constant="26" id="c25-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="width" secondItem="vUN-kp-3ea" secondAttribute="width" constant="27" id="c26-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="height" secondItem="vUN-kp-3ea" secondAttribute="height" constant="28" id="c27-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="trailing" secondItem="vUN-kp-3ea" secondAttribute="trailing" constant="29" id="c28-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="leading" secondItem="vUN-kp-3ea" secondAttribute="leading" constant="30" id="c29-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
            </view>
            </objects>
            </document>
            """#, 3645, "4c87eb40b41c41bc078f452c32c8aef90ce5652740450b0d67639db0a4131498"),
        ("cs-pairs-safe-sub", #"""
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
            <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="xxx-xx-xx1">
            <rect key="frame" x="10" y="20" width="100" height="50"/>
            </view>
            </subviews>
            <viewLayoutGuide key="safeArea" id="vUN-kp-3ea"/>
            <constraints>
            <constraint firstItem="vUN-kp-3ea" firstAttribute="centerY" secondItem="xxx-xx-xx1" secondAttribute="centerY" constant="1" id="c00-aa-aaa"/>
            <constraint firstItem="vUN-kp-3ea" firstAttribute="centerY" secondItem="xxx-xx-xx1" secondAttribute="bottom" constant="2" id="c01-aa-aaa"/>
            <constraint firstItem="vUN-kp-3ea" firstAttribute="centerY" secondItem="xxx-xx-xx1" secondAttribute="top" constant="3" id="c02-aa-aaa"/>
            <constraint firstItem="vUN-kp-3ea" firstAttribute="centerY" secondItem="xxx-xx-xx1" secondAttribute="baseline" constant="4" id="c03-aa-aaa"/>
            <constraint firstItem="vUN-kp-3ea" firstAttribute="centerY" secondItem="xxx-xx-xx1" secondAttribute="firstBaseline" constant="5" id="c04-aa-aaa"/>
            <constraint firstItem="vUN-kp-3ea" firstAttribute="bottom" secondItem="xxx-xx-xx1" secondAttribute="centerY" constant="6" id="c05-aa-aaa"/>
            <constraint firstItem="vUN-kp-3ea" firstAttribute="bottom" secondItem="xxx-xx-xx1" secondAttribute="bottom" constant="7" id="c06-aa-aaa"/>
            <constraint firstItem="vUN-kp-3ea" firstAttribute="bottom" secondItem="xxx-xx-xx1" secondAttribute="top" constant="8" id="c07-aa-aaa"/>
            <constraint firstItem="vUN-kp-3ea" firstAttribute="bottom" secondItem="xxx-xx-xx1" secondAttribute="baseline" constant="9" id="c08-aa-aaa"/>
            <constraint firstItem="vUN-kp-3ea" firstAttribute="bottom" secondItem="xxx-xx-xx1" secondAttribute="firstBaseline" constant="10" id="c09-aa-aaa"/>
            <constraint firstItem="vUN-kp-3ea" firstAttribute="top" secondItem="xxx-xx-xx1" secondAttribute="centerY" constant="11" id="c10-aa-aaa"/>
            <constraint firstItem="vUN-kp-3ea" firstAttribute="top" secondItem="xxx-xx-xx1" secondAttribute="bottom" constant="12" id="c11-aa-aaa"/>
            <constraint firstItem="vUN-kp-3ea" firstAttribute="top" secondItem="xxx-xx-xx1" secondAttribute="top" constant="13" id="c12-aa-aaa"/>
            <constraint firstItem="vUN-kp-3ea" firstAttribute="top" secondItem="xxx-xx-xx1" secondAttribute="baseline" constant="14" id="c13-aa-aaa"/>
            <constraint firstItem="vUN-kp-3ea" firstAttribute="top" secondItem="xxx-xx-xx1" secondAttribute="firstBaseline" constant="15" id="c14-aa-aaa"/>
            <constraint firstItem="vUN-kp-3ea" firstAttribute="baseline" secondItem="xxx-xx-xx1" secondAttribute="centerY" constant="16" id="c15-aa-aaa"/>
            <constraint firstItem="vUN-kp-3ea" firstAttribute="baseline" secondItem="xxx-xx-xx1" secondAttribute="bottom" constant="17" id="c16-aa-aaa"/>
            <constraint firstItem="vUN-kp-3ea" firstAttribute="baseline" secondItem="xxx-xx-xx1" secondAttribute="top" constant="18" id="c17-aa-aaa"/>
            <constraint firstItem="vUN-kp-3ea" firstAttribute="baseline" secondItem="xxx-xx-xx1" secondAttribute="baseline" constant="19" id="c18-aa-aaa"/>
            <constraint firstItem="vUN-kp-3ea" firstAttribute="baseline" secondItem="xxx-xx-xx1" secondAttribute="firstBaseline" constant="20" id="c19-aa-aaa"/>
            <constraint firstItem="vUN-kp-3ea" firstAttribute="firstBaseline" secondItem="xxx-xx-xx1" secondAttribute="centerY" constant="21" id="c20-aa-aaa"/>
            <constraint firstItem="vUN-kp-3ea" firstAttribute="firstBaseline" secondItem="xxx-xx-xx1" secondAttribute="bottom" constant="22" id="c21-aa-aaa"/>
            <constraint firstItem="vUN-kp-3ea" firstAttribute="firstBaseline" secondItem="xxx-xx-xx1" secondAttribute="top" constant="23" id="c22-aa-aaa"/>
            <constraint firstItem="vUN-kp-3ea" firstAttribute="firstBaseline" secondItem="xxx-xx-xx1" secondAttribute="baseline" constant="24" id="c23-aa-aaa"/>
            <constraint firstItem="vUN-kp-3ea" firstAttribute="firstBaseline" secondItem="xxx-xx-xx1" secondAttribute="firstBaseline" constant="25" id="c24-aa-aaa"/>
            <constraint firstItem="vUN-kp-3ea" firstAttribute="centerX" secondItem="xxx-xx-xx1" secondAttribute="centerX" constant="26" id="c25-aa-aaa"/>
            <constraint firstItem="vUN-kp-3ea" firstAttribute="width" secondItem="xxx-xx-xx1" secondAttribute="width" constant="27" id="c26-aa-aaa"/>
            <constraint firstItem="vUN-kp-3ea" firstAttribute="height" secondItem="xxx-xx-xx1" secondAttribute="height" constant="28" id="c27-aa-aaa"/>
            <constraint firstItem="vUN-kp-3ea" firstAttribute="trailing" secondItem="xxx-xx-xx1" secondAttribute="trailing" constant="29" id="c28-aa-aaa"/>
            <constraint firstItem="vUN-kp-3ea" firstAttribute="leading" secondItem="xxx-xx-xx1" secondAttribute="leading" constant="30" id="c29-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
            </view>
            </objects>
            </document>
            """#, 3645, "c61299993fc40e5d3de2cf2f3c3fc3a47961804b6cd3600f9c55359f2a8b6236"),
        ("cs-first-baseline-view", #"""
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
            <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="xxx-xx-xx1">
            <rect key="frame" x="10" y="20" width="100" height="50"/>
            </view>
            <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="yyy-yy-yy1">
            <rect key="frame" x="150" y="20" width="100" height="50"/>
            </view>
            </subviews>
            <constraints>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="10" id="c00-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="20" id="c01-aa-aaa"/>
            <constraint firstItem="yyy-yy-yy1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="150" id="c02-aa-aaa"/>
            <constraint firstItem="yyy-yy-yy1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="20" id="c03-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="firstBaseline" secondItem="iN0-l3-epB" secondAttribute="centerY" id="c10-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="firstBaseline" secondItem="iN0-l3-epB" secondAttribute="bottom" constant="-3" id="c11-aa-aaa"/>
            <constraint firstItem="iN0-l3-epB" firstAttribute="bottom" secondItem="yyy-yy-yy1" secondAttribute="firstBaseline" constant="4" id="c12-aa-aaa"/>
            <constraint firstAttribute="top" secondItem="yyy-yy-yy1" secondAttribute="firstBaseline" constant="-5" id="c13-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="centerY" secondItem="iN0-l3-epB" secondAttribute="firstBaseline" id="c14-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
            </view>
            </objects>
            </document>
            """#, 1728, "b8997fe0aed6330945b1a589c1142f8304d1c84a51622023f23be3577ad8ba25"),
        ("cs-baseline-view", #"""
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
            <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="xxx-xx-xx1">
            <rect key="frame" x="10" y="20" width="100" height="50"/>
            </view>
            <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="yyy-yy-yy1">
            <rect key="frame" x="150" y="20" width="100" height="50"/>
            </view>
            </subviews>
            <constraints>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="10" id="c00-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="20" id="c01-aa-aaa"/>
            <constraint firstItem="yyy-yy-yy1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="150" id="c02-aa-aaa"/>
            <constraint firstItem="yyy-yy-yy1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="20" id="c03-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="baseline" secondItem="iN0-l3-epB" secondAttribute="centerY" id="c10-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="baseline" secondItem="iN0-l3-epB" secondAttribute="bottom" constant="-3" id="c11-aa-aaa"/>
            <constraint firstItem="iN0-l3-epB" firstAttribute="bottom" secondItem="yyy-yy-yy1" secondAttribute="baseline" constant="4" id="c12-aa-aaa"/>
            <constraint firstAttribute="top" secondItem="yyy-yy-yy1" secondAttribute="baseline" constant="-5" id="c13-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="centerY" secondItem="iN0-l3-epB" secondAttribute="baseline" id="c14-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
            </view>
            </objects>
            </document>
            """#, 1728, "5643fbf5b01dcafc3cc87b687a283ff14bb2e07d201db1bac3dc7bb3f1f78996"),
        ("cs-custom-other-module", #"""
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
            <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="xxx-xx-xx1">
            <rect key="frame" x="10" y="20" width="100" height="50"/>
            </view>
            <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="yyy-yy-yy1">
            <rect key="frame" x="150" y="20" width="100" height="50"/>
            </view>
            </subviews>
            <constraints>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="10" id="c00-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="20" id="c01-aa-aaa"/>
            <constraint firstItem="yyy-yy-yy1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="150" id="c02-aa-aaa"/>
            <constraint firstItem="yyy-yy-yy1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="20" id="c03-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="bottom" secondItem="yyy-yy-yy1" secondAttribute="bottom" customClass="KeyboardLayoutConstraint" customModule="Spring" id="c10-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
            </view>
            </objects>
            </document>
            """#, 1630, "4294c60b98f60e0b8e2b64f9c83bf90d29ea5dbd395b59ab74c2b8353ea2434a"),
        ("cs-custom-sibling", #"""
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
            <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="xxx-xx-xx1">
            <rect key="frame" x="10" y="20" width="100" height="50"/>
            </view>
            <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="yyy-yy-yy1">
            <rect key="frame" x="150" y="20" width="100" height="50"/>
            </view>
            </subviews>
            <constraints>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="10" id="c00-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="20" id="c01-aa-aaa"/>
            <constraint firstItem="yyy-yy-yy1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="150" id="c02-aa-aaa"/>
            <constraint firstItem="yyy-yy-yy1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="20" id="c03-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="bottom" secondItem="yyy-yy-yy1" secondAttribute="bottom" constant="1" customClass="HairlineConstraint" customModule="T" customModuleProvider="target" id="c10-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
            </view>
            </objects>
            </document>
            """#, 1639, "a23271811390ad7941e0410eaeec1ec17f0c878f0df95f9749397c91fcd73fc7"),
        ("cs-custom-two", #"""
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
            <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="xxx-xx-xx1">
            <rect key="frame" x="10" y="20" width="100" height="50"/>
            </view>
            <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="yyy-yy-yy1">
            <rect key="frame" x="150" y="20" width="100" height="50"/>
            </view>
            </subviews>
            <constraints>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="10" id="c00-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="20" id="c01-aa-aaa"/>
            <constraint firstItem="yyy-yy-yy1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="150" id="c02-aa-aaa"/>
            <constraint firstItem="yyy-yy-yy1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="20" id="c03-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="bottom" secondItem="yyy-yy-yy1" secondAttribute="bottom" customClass="A1" id="c10-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="top" secondItem="yyy-yy-yy1" secondAttribute="top" customClass="A1" id="c11-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="leading" secondItem="yyy-yy-yy1" secondAttribute="leading" customClass="B2" id="c12-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
            </view>
            </objects>
            </document>
            """#, 1710, "c05b9ce2ff25ac1378cd435c13b71bc195188cc595c229caf30188478adb1225"),
        ("cs-custom-no-module", #"""
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
            <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="xxx-xx-xx1">
            <rect key="frame" x="10" y="20" width="100" height="50"/>
            </view>
            <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="yyy-yy-yy1">
            <rect key="frame" x="150" y="20" width="100" height="50"/>
            </view>
            </subviews>
            <constraints>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="10" id="c00-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="20" id="c01-aa-aaa"/>
            <constraint firstItem="yyy-yy-yy1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="150" id="c02-aa-aaa"/>
            <constraint firstItem="yyy-yy-yy1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="20" id="c03-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="bottom" secondItem="yyy-yy-yy1" secondAttribute="bottom" customClass="I" id="c10-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
            </view>
            </objects>
            </document>
            """#, 1594, "b7368d7a8e40b1d435bd6aecb7a565e5156669cfffc0fe542bf2d358e79f1c01"),
        ("cs-symbol-anchor", #"""
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
            <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="xxx-xx-xx1">
            <rect key="frame" x="10" y="20" width="100" height="50"/>
            </view>
            <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="yyy-yy-yy1">
            <rect key="frame" x="150" y="20" width="100" height="50"/>
            </view>
            </subviews>
            <constraints>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="10" id="c00-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="20" id="c01-aa-aaa"/>
            <constraint firstItem="yyy-yy-yy1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="150" id="c02-aa-aaa"/>
            <constraint firstItem="yyy-yy-yy1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="20" id="c03-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="top" secondItem="yyy-yy-yy1" secondAttribute="bottom" constant="8" symbolType="layoutAnchor" id="c10-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
            </view>
            </objects>
            </document>
            """#, 1562, "f8399f3915367acd74a21ac6e51edfd9f68f675dc932d2277eefad739e159691"),
        ("cs-symbol-anchor-relation", #"""
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
            <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="xxx-xx-xx1">
            <rect key="frame" x="10" y="20" width="100" height="50"/>
            </view>
            <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="yyy-yy-yy1">
            <rect key="frame" x="150" y="20" width="100" height="50"/>
            </view>
            </subviews>
            <constraints>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="10" id="c00-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="20" id="c01-aa-aaa"/>
            <constraint firstItem="yyy-yy-yy1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="150" id="c02-aa-aaa"/>
            <constraint firstItem="yyy-yy-yy1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="20" id="c03-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="firstBaseline" secondItem="yyy-yy-yy1" secondAttribute="baseline" relation="greaterThanOrEqual" constant="21" symbolType="layoutAnchor" id="c10-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
            </view>
            </objects>
            </document>
            """#, 1576, "45526982fff829515d8d26ffee5b950adb82dfc772b7796fb70f2aaec709f5e8"),
        ("cs-margin-multiplier", #"""
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
            <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="xxx-xx-xx1">
            <rect key="frame" x="10" y="20" width="100" height="50"/>
            </view>
            <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="yyy-yy-yy1">
            <rect key="frame" x="150" y="20" width="100" height="50"/>
            </view>
            </subviews>
            <constraints>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="10" id="c00-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="20" id="c01-aa-aaa"/>
            <constraint firstItem="yyy-yy-yy1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="150" id="c02-aa-aaa"/>
            <constraint firstItem="yyy-yy-yy1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="20" id="c03-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="leadingMargin" secondItem="iN0-l3-epB" secondAttribute="leading" multiplier="0.5" id="c10-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
            </view>
            </objects>
            </document>
            """#, 1535, "40fb73a9a0e582a8f5b91bf0e73c2e973784cbded57e110dd436d1dd35218469"),
        ("cs-margin-symbolic", #"""
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
            <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="xxx-xx-xx1">
            <rect key="frame" x="10" y="20" width="100" height="50"/>
            </view>
            <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="yyy-yy-yy1">
            <rect key="frame" x="150" y="20" width="100" height="50"/>
            </view>
            </subviews>
            <constraints>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="10" id="c00-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="20" id="c01-aa-aaa"/>
            <constraint firstItem="yyy-yy-yy1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="150" id="c02-aa-aaa"/>
            <constraint firstItem="yyy-yy-yy1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="20" id="c03-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leadingMargin" constant="8" symbolic="YES" id="c10-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
            </view>
            </objects>
            </document>
            """#, 1550, "e47918db24a5945a654700ef406c73d44ce08b2321c84526a00d86bf46370b8e"),
        ("cs-margin-variation", #"""
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
            <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="xxx-xx-xx1">
            <rect key="frame" x="10" y="20" width="100" height="50"/>
            </view>
            <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="yyy-yy-yy1">
            <rect key="frame" x="150" y="20" width="100" height="50"/>
            </view>
            </subviews>
            <constraints>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="10" id="c00-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="20" id="c01-aa-aaa"/>
            <constraint firstItem="yyy-yy-yy1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="150" id="c02-aa-aaa"/>
            <constraint firstItem="yyy-yy-yy1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="20" id="c03-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leadingMargin" constant="3" id="c10-aa-aaa"><variation key="heightClass=compact" constant="7"/></constraint>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
            </view>
            </objects>
            </document>
            """#, 2174, "9757c298b70dc5ad0f773a1acfb0d107770708be4f4b8f847540b71a561f7cd5"),
        ("cs-verify-off", #"""
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
            <view contentMode="scaleToFill" verifyAmbiguity="off" translatesAutoresizingMaskIntoConstraints="NO" id="xxx-xx-xx1">
            <rect key="frame" x="10" y="20" width="100" height="50"/>
            </view>
            </subviews>
            <constraints>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="10" id="c00-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="20" id="c01-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
            </view>
            </objects>
            </document>
            """#, 1252, "cd7ae79a94bb999b9392d5e1bde00ee47f4e2829be400f103c6d8f3442e593e4"),
        ("cs-verify-ignore", #"""
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
            <view contentMode="scaleToFill" verifyAmbiguity="ignoreSizes" translatesAutoresizingMaskIntoConstraints="NO" id="xxx-xx-xx1">
            <rect key="frame" x="10" y="20" width="100" height="50"/>
            </view>
            </subviews>
            <constraints>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="10" id="c00-aa-aaa"/>
            <constraint firstItem="xxx-xx-xx1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="20" id="c01-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
            </view>
            </objects>
            </document>
            """#, 1252, "cd7ae79a94bb999b9392d5e1bde00ee47f4e2829be400f103c6d8f3442e593e4"),
        ("cs-cvsafe-center", #"""
            <?xml version="1.0" encoding="UTF-8"?>
            <document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" useSafeAreas="YES" colorMatched="YES">
            <device id="retina6_12" orientation="portrait" appearance="light"/>
            <dependencies>
            <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
            <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
            </dependencies>
            <objects>
            <placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File's Owner"/>
            <placeholder placeholderIdentifier="IBFirstResponder" id="-2" customClass="UIResponder"/>
            <collectionViewCell opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" customClass="Cell" customModule="T" customModuleProvider="target" id="gTV-IL-0wX">
            <rect key="frame" x="0.0" y="0.0" width="50" height="50"/>
            <autoresizingMask key="autoresizingMask"/>
            <view key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center">
            <rect key="frame" x="0.0" y="0.0" width="50" height="50"/>
            <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
            <subviews>
            <label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" text="Label" textAlignment="natural" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lll-ll-ll1">
            <rect key="frame" x="4" y="14" width="42" height="21"/>
            <fontDescription key="fontDescription" pointSize="17" type="system"/>
            <nil key="textColor"/>
            <nil key="highlightedColor"/>
            </label>
            </subviews>
            </view>
            <viewLayoutGuide key="safeArea" id="sfa-aa-aa1"/>
            <size key="customSize" width="50" height="50"/>
            <constraints>
            <constraint firstItem="lll-ll-ll1" firstAttribute="centerX" secondItem="sfa-aa-aa1" secondAttribute="centerX" id="c00-aa-aaa"/>
            <constraint firstItem="lll-ll-ll1" firstAttribute="centerY" secondItem="sfa-aa-aa1" secondAttribute="centerY" id="c01-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
            </collectionViewCell>
            </objects>
            </document>
            """#, 3307, "0d606a20551ee02916c1e809d285635e276e22bf8a01a61eb12f9842005fb629"),
        ("cs-cvsafe-edges", #"""
            <?xml version="1.0" encoding="UTF-8"?>
            <document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" useSafeAreas="YES" colorMatched="YES">
            <device id="retina6_12" orientation="portrait" appearance="light"/>
            <dependencies>
            <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
            <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
            </dependencies>
            <objects>
            <placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File's Owner"/>
            <placeholder placeholderIdentifier="IBFirstResponder" id="-2" customClass="UIResponder"/>
            <collectionViewCell opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" customClass="Cell" customModule="T" customModuleProvider="target" id="gTV-IL-0wX">
            <rect key="frame" x="0.0" y="0.0" width="50" height="50"/>
            <autoresizingMask key="autoresizingMask"/>
            <view key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center">
            <rect key="frame" x="0.0" y="0.0" width="50" height="50"/>
            <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
            <subviews>
            <label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" text="Label" textAlignment="natural" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lll-ll-ll1">
            <rect key="frame" x="4" y="14" width="42" height="21"/>
            <fontDescription key="fontDescription" pointSize="17" type="system"/>
            <nil key="textColor"/>
            <nil key="highlightedColor"/>
            </label>
            </subviews>
            </view>
            <viewLayoutGuide key="safeArea" id="sfa-aa-aa1"/>
            <size key="customSize" width="50" height="50"/>
            <constraints>
            <constraint firstItem="lll-ll-ll1" firstAttribute="leading" secondItem="sfa-aa-aa1" secondAttribute="leading" id="c00-aa-aaa"/>
            <constraint firstItem="lll-ll-ll1" firstAttribute="top" secondItem="sfa-aa-aa1" secondAttribute="top" id="c01-aa-aaa"/>
            <constraint firstItem="sfa-aa-aa1" firstAttribute="trailing" secondItem="lll-ll-ll1" secondAttribute="trailing" id="c02-aa-aaa"/>
            <constraint firstItem="sfa-aa-aa1" firstAttribute="bottom" secondItem="lll-ll-ll1" secondAttribute="bottom" id="c03-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
            </collectionViewCell>
            </objects>
            </document>
            """#, 3393, "38ca0e204d13c8fd3e0511f6178627cf95695a585c5f029aac761416a701f49c"),
        ("cs-cvsafe-mixed", #"""
            <?xml version="1.0" encoding="UTF-8"?>
            <document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" useSafeAreas="YES" colorMatched="YES">
            <device id="retina6_12" orientation="portrait" appearance="light"/>
            <dependencies>
            <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
            <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
            </dependencies>
            <objects>
            <placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File's Owner"/>
            <placeholder placeholderIdentifier="IBFirstResponder" id="-2" customClass="UIResponder"/>
            <collectionViewCell opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" customClass="Cell" customModule="T" customModuleProvider="target" id="gTV-IL-0wX">
            <rect key="frame" x="0.0" y="0.0" width="50" height="50"/>
            <autoresizingMask key="autoresizingMask"/>
            <view key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center">
            <rect key="frame" x="0.0" y="0.0" width="50" height="50"/>
            <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
            <subviews>
            <label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" text="Label" textAlignment="natural" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lll-ll-ll1">
            <rect key="frame" x="4" y="14" width="42" height="21"/>
            <fontDescription key="fontDescription" pointSize="17" type="system"/>
            <nil key="textColor"/>
            <nil key="highlightedColor"/>
            </label>
            </subviews>
            </view>
            <viewLayoutGuide key="safeArea" id="sfa-aa-aa1"/>
            <size key="customSize" width="50" height="50"/>
            <constraints>
            <constraint firstItem="lll-ll-ll1" firstAttribute="leading" secondItem="gTV-IL-0wX" secondAttribute="leading" id="c00-aa-aaa"/>
            <constraint firstItem="lll-ll-ll1" firstAttribute="top" secondItem="sfa-aa-aa1" secondAttribute="top" id="c01-aa-aaa"/>
            <constraint firstItem="sfa-aa-aa1" firstAttribute="trailing" secondItem="lll-ll-ll1" secondAttribute="trailing" id="c02-aa-aaa"/>
            <constraint firstAttribute="bottom" secondItem="lll-ll-ll1" secondAttribute="bottom" id="c03-aa-aaa"/>
            <constraint firstItem="lll-ll-ll1" firstAttribute="centerY" secondItem="sfa-aa-aa1" secondAttribute="centerY" id="c04-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
            </collectionViewCell>
            </objects>
            </document>
            """#, 3435, "539b0c8df1141751e4738bbe85e70b8bc5afc5a08ec15052818d5e6ea8642758"),
    ]

    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
