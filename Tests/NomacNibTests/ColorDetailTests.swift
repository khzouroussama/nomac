import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for catalog and undefined named colors, system colors, accessibility traits,
/// data detectors and keyboard layout guides (`.github/scripts/nib_experiments.py`, `mx-*`): sizes and SHA-256
/// digests of Xcode's nibs.
@Suite struct ColorDetailTests {
    static let xibs: [(String, String, Int, String)] = [
        ("white-alpha-1-0.4", #"""
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
                <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="cnv-000-aa">
                    <rect key="frame" x="0" y="0" width="10" height="1"/>
                    <color key="backgroundColor" white="1" alpha="0.4" colorSpace="calibratedWhite"/>
                </view>
            </subviews>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 1033, "04ac70727ebb39af68996fa1f7c73f86128375c2e81b637ebc3e05a2ceefb526"),
        ("white-alpha-1-1", #"""
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
                <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="cnv-000-aa">
                    <rect key="frame" x="0" y="0" width="10" height="1"/>
                    <color key="backgroundColor" white="1" alpha="1" colorSpace="calibratedWhite"/>
                </view>
            </subviews>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 1044, "d9c70da50aecd61994436aad65ebe5168e9327e8ab374a0ef684a4189a9c95d9"),
        ("white-alpha-1.2-0.5", #"""
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
                <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="cnv-000-aa">
                    <rect key="frame" x="0" y="0" width="10" height="1"/>
                    <color key="backgroundColor" white="1.2" alpha="0.5" colorSpace="calibratedWhite"/>
                </view>
            </subviews>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 1008, "6ab235a3360490603752caec7f0766218e73914933d59b2e44963f53c7b120f0"),
        ("tint-system-view", #"""
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
                    <color key="tintColor" systemColor="tintColor"/>
                </view>
            </subviews>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 872, "f656183e6e3a29a51ff1b04554564a7464b0f95b9eeaf34c0d58556f00ab8a80"),
        ("tint-system-label", #"""
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
                    <fontDescription key="fontDescription" pointSize="17" type="system"/>
<nil key="textColor"/>
<nil key="highlightedColor"/>
                    <color key="tintColor" systemColor="tintColor"/>
                </label>
            </subviews>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 1809, "d2955d7ebc8908ecefb8c536ab9721e43dab7096a4535b63a3e36cf7797de49d"),
        ("text-view-tint-highlight", #"""
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
                    <color key="tintColor" red="0.0" green="0.4" blue="0.1" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
                </textView>
            </subviews>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 2449, "873be2941eebe3ffde37e530a983f2ad245b1d98925c33e6b382c015d9a007fd"),
        ("progress-bar-tints", #"""
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
                <progressView opaque="NO" contentMode="scaleToFill" verticalHuggingPriority="750" progressViewStyle="bar" progress="0.5" translatesAutoresizingMaskIntoConstraints="NO" id="prg-aa-aa1">
                    <rect key="frame" x="20" y="100" width="200" height="2.5"/>
                    <color key="progressTintColor" white="0" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>
                    <color key="trackTintColor" white="1" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>
                </progressView>
            </subviews>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 1187, "378a3c8f8107c898c7bba8da9abfb00eb7b7377f36844eeab9a092248dfc8f4d"),
        ("label-max-width-zero", #"""
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
                <label preferredMaxLayoutWidth="0.0" opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" text="Label" textAlignment="natural" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="lll-ll-ll1">
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

"""#, 1809, "d2955d7ebc8908ecefb8c536ab9721e43dab7096a4535b63a3e36cf7797de49d"),
        ("cell-style-variation-both-value1", #"""
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
        <tableViewCell contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" textLabel="tlb-aa-aa1" detailTextLabel="dlb-aa-aa1" style="IBUITableViewCellStyleValue1" id="KGk-i7-Jjw">
            <rect key="frame" x="0.0" y="0.0" width="320" height="44"/>
            <autoresizingMask key="autoresizingMask"/>
            <tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="KGk-i7-Jjw" id="H2p-sc-9uM">
                <rect key="frame" x="0.0" y="0.0" width="320" height="44"/>
                <autoresizingMask key="autoresizingMask"/>
                    <subviews>
                        <label opaque="NO" multipleTouchEnabled="YES" contentMode="left" text="Title" textAlignment="natural" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" id="tlb-aa-aa1">
                            <rect key="frame" x="68" y="0" width="236" height="44"/>
                            <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
                            <fontDescription key="fontDescription" type="system" pointSize="16"/>
                            <nil key="textColor"/>
                            <nil key="highlightedColor"/>
                        <variation key="widthClass=compact">
<fontDescription key="fontDescription" type="system" pointSize="20"/>
</variation>
</label>
                        <label opaque="NO" multipleTouchEnabled="YES" contentMode="left" text="Detail" textAlignment="natural" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" id="dlb-aa-aa1">
                            <rect key="frame" x="68" y="25" width="44" height="14.5"/>
                            <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
                            <fontDescription key="fontDescription" type="system" pointSize="12"/>
                            <nil key="textColor"/>
                            <nil key="highlightedColor"/>
                        <variation key="widthClass=compact">
<fontDescription key="fontDescription" type="system" pointSize="20"/>
</variation>
</label>
                    </subviews>
            </tableViewCellContentView>
            <viewLayoutGuide key="safeArea" id="njF-e1-oar"/>
            <point key="canvasLocation" x="0" y="0"/>
        </tableViewCell>
    </objects>
</document>

"""#, 3523, "c75cfb9a8c33aff33b7a3299a77c2c90be58c47b78139d34901560705a4bbbdb"),
        ("cell-style-variation-both-subtitle", #"""
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
        <tableViewCell contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" textLabel="tlb-aa-aa1" detailTextLabel="dlb-aa-aa1" style="IBUITableViewCellStyleSubtitle" id="KGk-i7-Jjw">
            <rect key="frame" x="0.0" y="0.0" width="320" height="44"/>
            <autoresizingMask key="autoresizingMask"/>
            <tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="KGk-i7-Jjw" id="H2p-sc-9uM">
                <rect key="frame" x="0.0" y="0.0" width="320" height="44"/>
                <autoresizingMask key="autoresizingMask"/>
                    <subviews>
                        <label opaque="NO" multipleTouchEnabled="YES" contentMode="left" text="Title" textAlignment="natural" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" id="tlb-aa-aa1">
                            <rect key="frame" x="68" y="0" width="236" height="44"/>
                            <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
                            <fontDescription key="fontDescription" type="system" pointSize="16"/>
                            <nil key="textColor"/>
                            <nil key="highlightedColor"/>
                        <variation key="widthClass=compact">
<fontDescription key="fontDescription" type="system" pointSize="20"/>
</variation>
</label>
                        <label opaque="NO" multipleTouchEnabled="YES" contentMode="left" text="Detail" textAlignment="natural" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" id="dlb-aa-aa1">
                            <rect key="frame" x="68" y="25" width="44" height="14.5"/>
                            <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
                            <fontDescription key="fontDescription" type="system" pointSize="12"/>
                            <nil key="textColor"/>
                            <nil key="highlightedColor"/>
                        <variation key="widthClass=compact">
<fontDescription key="fontDescription" type="system" pointSize="20"/>
</variation>
</label>
                    </subviews>
            </tableViewCellContentView>
            <viewLayoutGuide key="safeArea" id="njF-e1-oar"/>
            <point key="canvasLocation" x="0" y="0"/>
        </tableViewCell>
    </objects>
</document>

"""#, 3523, "a5672c13bd1ddfe5c2334fd2d99f47d6641580faf2d97ab8c649ec67c6370e37"),
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

    /// `mx-detect-seven`, `table-separator-etched`: warnings ibtool prints.
    @Test func printsItsWarnings() throws {
        let detecting = try XIBCompiler.compileReportingWarnings(Data(Self.detectingTextView.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(detecting.warnings == ["/tmp/View.xib:txv-aa-aa1: warning: Data Detection and Editable (These attributes are mutually exclusive) [9]"])
        let etched = try XIBCompiler.compileReportingWarnings(Data(Self.etchedTable.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(etched.warnings == ["/tmp/View.xib:tbl-aa-aaa: warning: Single Line Etched separator on plain style table views [5]"])
    }

    static let detectingTextView = #"""
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
                    <dataDetectorType key="dataDetectorTypes" phoneNumber="YES" link="YES" address="YES" calendarEvent="YES" shipmentTrackingNumber="YES" flightNumber="YES" lookupSuggestion="YES"/>
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

"""#

    static let etchedTable = #"""
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
                <tableView clipsSubviews="YES" contentMode="scaleToFill" alwaysBounceVertical="YES" style="plain" separatorStyle="singleLineEtched" rowHeight="-1" estimatedRowHeight="-1" sectionHeaderHeight="28" sectionFooterHeight="28" translatesAutoresizingMaskIntoConstraints="NO" id="tbl-aa-aaa">
                    <rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
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

"""#
}
