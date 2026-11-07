import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for toolbars' items, bars' styles and tints and navigation items
/// (`.github/scripts/nib_experiments.py`, `bars-*`): sizes and SHA-256 digests of Xcode's nibs.
@Suite struct BarItemTests {
    static let xibs: [(String, String, Int, String)] = [
        ("bars-tb-width-zero-title", #"""
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
                <toolbar opaque="NO" clearsContextBeforeDrawing="NO" contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="tbr-aa-aa1">
                    <rect key="frame" x="0" y="0" width="393" height="49"/>
                    <items>
                        <barButtonItem width="0.0" title="Item" style="plain" id="flx-aa-aa1"/>
                    </items>
                </toolbar>
            </subviews>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 1090, "1fdc7347661775d4bea0034804d5104bf4f7df350ddd3b4e622de46dd1d65deb"),
        ("bars-tb-width-negative", #"""
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
                <toolbar opaque="NO" clearsContextBeforeDrawing="NO" contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="tbr-aa-aa1">
                    <rect key="frame" x="0" y="0" width="393" height="49"/>
                    <items>
                        <barButtonItem width="-5" title="X" style="plain" id="flx-aa-aa1"/>
                    </items>
                </toolbar>
            </subviews>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 1087, "a6fe40e566662f5b500dbe7df8b9b2333f35d91cce40d2a02ebd0ff58e42974d"),
        ("bars-tb-width-fixed-negative", #"""
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
                <toolbar opaque="NO" clearsContextBeforeDrawing="NO" contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="tbr-aa-aa1">
                    <rect key="frame" x="0" y="0" width="393" height="49"/>
                    <items>
                        <barButtonItem width="-16" style="plain" systemItem="fixedSpace" id="flx-aa-aa1"/>
                    </items>
                </toolbar>
            </subviews>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 1117, "aceacd07e3c7c70f0d2a06295f3c79088b3952b6b7122cf129e2e1527c20ee5d"),
        ("bars-tb-width-fixed", #"""
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
                <toolbar opaque="NO" clearsContextBeforeDrawing="NO" contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="tbr-aa-aa1">
                    <rect key="frame" x="0" y="0" width="393" height="49"/>
                    <items>
                        <barButtonItem width="16" style="plain" systemItem="fixedSpace" id="flx-aa-aa1"/>
                    </items>
                </toolbar>
            </subviews>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 1131, "77b96b65cbe3488b1918bd6382a39f83dd9c03f5f4925d925934a13a43a564c9"),
        ("bars-tb-tag-zero", #"""
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
                <toolbar opaque="NO" clearsContextBeforeDrawing="NO" contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="tbr-aa-aa1">
                    <rect key="frame" x="0" y="0" width="393" height="49"/>
                    <items>
                        <barButtonItem tag="0" title="Item" style="plain" id="flx-aa-aa1"/>
                    </items>
                </toolbar>
            </subviews>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 1090, "1fdc7347661775d4bea0034804d5104bf4f7df350ddd3b4e622de46dd1d65deb"),
        ("bars-tb-title-empty", #"""
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
                <toolbar opaque="NO" clearsContextBeforeDrawing="NO" contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="tbr-aa-aa1">
                    <rect key="frame" x="0" y="0" width="393" height="49"/>
                    <items>
                        <barButtonItem title="" image="Icon" style="plain" id="flx-aa-aa1"/>
                    </items>
                </toolbar>
            </subviews>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 1259, "a6a522d2535a4ac3283fd6a959dc5f14818cebcbbc6a6ef43816afd7999d07e6"),
        ("bars-tb-image-empty", #"""
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
                <toolbar opaque="NO" clearsContextBeforeDrawing="NO" contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="tbr-aa-aa1">
                    <rect key="frame" x="0" y="0" width="393" height="49"/>
                    <items>
                        <barButtonItem image="" title="X" style="plain" id="flx-aa-aa1"/>
                    </items>
                </toolbar>
            </subviews>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 1087, "a6fe40e566662f5b500dbe7df8b9b2333f35d91cce40d2a02ebd0ff58e42974d"),
        ("bars-tb-safe-guide", #"""
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
                <toolbar opaque="NO" clearsContextBeforeDrawing="NO" contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="tbr-aa-aa1">
                    <rect key="frame" x="0" y="0" width="393" height="49"/>
                    <items/>
                    <viewLayoutGuide key="safeArea" id="tbs-aa-aa1"/>
                </toolbar>
            </subviews>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 1209, "2103bb8d71d108c34cfb0888acf081073725f4a57d7261d24f006fb61b2d935a"),
        ("bars-tb-sys-all", #"""
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
                <toolbar opaque="NO" clearsContextBeforeDrawing="NO" contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="tbr-aa-aa1">
                    <rect key="frame" x="0" y="0" width="393" height="49"/>
                    <items>
                        <barButtonItem systemItem="flexibleSpace" id="bbi-aa-aa0"/>
                        <barButtonItem systemItem="fixedSpace" id="bbi-aa-aa1"/>
                        <barButtonItem systemItem="done" id="bbi-aa-aa2"/>
                        <barButtonItem systemItem="cancel" id="bbi-aa-aa3"/>
                        <barButtonItem systemItem="add" id="bbi-aa-aa4"/>
                        <barButtonItem systemItem="save" id="bbi-aa-aa5"/>
                        <barButtonItem systemItem="action" id="bbi-aa-aa6"/>
                        <barButtonItem systemItem="stop" id="bbi-aa-aa7"/>
                        <barButtonItem systemItem="refresh" id="bbi-aa-aa8"/>
                        <barButtonItem systemItem="edit" id="bbi-aa-aa9"/>
                        <barButtonItem systemItem="trash" id="bbi-aa-aa10"/>
                        <barButtonItem systemItem="search" id="bbi-aa-aa11"/>
                        <barButtonItem systemItem="compose" id="bbi-aa-aa12"/>
                        <barButtonItem systemItem="organize" id="bbi-aa-aa13"/>
                        <barButtonItem systemItem="play" id="bbi-aa-aa14"/>
                        <barButtonItem systemItem="reply" id="bbi-aa-aa15"/>
                        <barButtonItem systemItem="bookmarks" id="bbi-aa-aa16"/>
                        <barButtonItem systemItem="rewind" id="bbi-aa-aa17"/>
                        <barButtonItem systemItem="fastForward" id="bbi-aa-aa18"/>
                        <barButtonItem systemItem="undo" id="bbi-aa-aa19"/>
                        <barButtonItem systemItem="camera" id="bbi-aa-aa20"/>
                        <barButtonItem systemItem="redo" id="bbi-aa-aa21"/>
                    </items>
                </toolbar>
            </subviews>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 1663, "fe286faf2500887c2885dbf86888cc980b3cec64da70c6b5e5c9b0118c91425c"),
        ("bars-tb-title-done", #"""
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
                <toolbar opaque="NO" clearsContextBeforeDrawing="NO" contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="tbr-aa-aa1">
                    <rect key="frame" x="0" y="0" width="393" height="49"/>
                    <items>
                        <barButtonItem style="done" title="Item" id="bbi-aa-aa1"/>
                    </items>
                </toolbar>
            </subviews>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 1101, "f9990b622995b176e6b9a6183e1d3c51f593f9b2aec19b6eb57cdee386729979"),
        ("bars-tb-fixed-width", #"""
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
                <toolbar opaque="NO" clearsContextBeforeDrawing="NO" contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="tbr-aa-aa1">
                    <rect key="frame" x="0" y="0" width="393" height="49"/>
                    <items>
                        <barButtonItem width="42" systemItem="fixedSpace" id="bbi-aa-aa1"/>
                    </items>
                </toolbar>
            </subviews>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 1142, "0ff17f0e7efddad96744a50c820e12d56385be622e915c5b703c8d07cfcbe3f4"),
        ("bars-tb-disabled", #"""
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
                <toolbar opaque="NO" clearsContextBeforeDrawing="NO" contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="tbr-aa-aa1">
                    <rect key="frame" x="0" y="0" width="393" height="49"/>
                    <items>
                        <barButtonItem enabled="NO" systemItem="add" id="bbi-aa-aa1"/>
                    </items>
                </toolbar>
            </subviews>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 1098, "8c4d9120e18db7f82a0bff24b09a170526d039ddd71d4ceb5f730dc768bbde49"),
        ("bars-tb-tag", #"""
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
                <toolbar opaque="NO" clearsContextBeforeDrawing="NO" contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="tbr-aa-aa1">
                    <rect key="frame" x="0" y="0" width="393" height="49"/>
                    <items>
                        <barButtonItem tag="3" systemItem="add" id="bbi-aa-aa1"/>
                    </items>
                </toolbar>
            </subviews>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 1119, "f591a175271c91493f5d5b6d234ed5219195dd537e8c8c6e8ec231bcd26c8e48"),
        ("bars-tb-tint", #"""
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
                <toolbar opaque="NO" clearsContextBeforeDrawing="NO" contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="tbr-aa-aa1">
                    <rect key="frame" x="0" y="0" width="393" height="49"/>
                    <items>
                        <barButtonItem title="Item" id="bbi-aa-aa1">
                            <color key="tintColor" red="1" green="0.0" blue="0.0" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
                        </barButtonItem>
                    </items>
                </toolbar>
            </subviews>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 1254, "8e960fc68a69739d4b0e6d6b83a1b25c5eed1bc7d5757907d13d85a63361abea"),
        ("bars-tb-style-black", #"""
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
                <toolbar opaque="NO" clearsContextBeforeDrawing="NO" contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" barStyle="black" id="tbr-aa-aa1">
                    <rect key="frame" x="0" y="0" width="393" height="49"/>
                    <items/>
                </toolbar>
            </subviews>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 1030, "06502b20c4d6941cfaf0761584b0d0f8d1f0bad42510e337c8e8863e88d04777"),
        ("bars-tb-translucent-no", #"""
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
                <toolbar opaque="NO" clearsContextBeforeDrawing="NO" contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" translucent="NO" id="tbr-aa-aa1">
                    <rect key="frame" x="0" y="0" width="393" height="49"/>
                    <items/>
                </toolbar>
            </subviews>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 1016, "d3592757e97dfe47b72eb7e658b245a6943f3b89d0a07b6a9092fae8e329a2d9"),
        ("bars-tb-bartint", #"""
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
                <toolbar opaque="NO" clearsContextBeforeDrawing="NO" contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="tbr-aa-aa1">
                    <rect key="frame" x="0" y="0" width="393" height="49"/>
                    <items/>
                    <color key="barTintColor" red="1" green="0.0" blue="0.0" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
                </toolbar>
            </subviews>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#, 1172, "f5abc88d62571aef9710204b0a225308aa0e1bdc9fe869c4fa447a078919f31d"),
        ("bars-nb-style-black", #"""
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
                <navigationBar contentMode="scaleToFill" barStyle="black" translatesAutoresizingMaskIntoConstraints="NO" id="nvb-aa-aa1">
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

"""#, 1210, "6f58cb5d08913ad40fd6b4de17ab5dd424b23c18c36277a3957ca9fb4eec2630"),
        ("bars-nb-large", #"""
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
                <navigationBar contentMode="scaleToFill" largeTitles="YES" translatesAutoresizingMaskIntoConstraints="NO" id="nvb-aa-aa1">
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

"""#, 1222, "08d0044ccd818d4cbb1df3abd0bd725b750ed2ff2cc27cb436ac411d1c89c606"),
    ]

    static let storyboards: [(String, String, [String: String])] = [
        ("bars-ni-title-space-1-s-lead", #"""
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
                    <navigationItem key="navigationItem" title=" " id="nvi-aa-aaa"/>
                </viewController>
                <placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>
            </objects>
            <point key="canvasLocation" x="0" y="0"/>
        </scene>
    </scenes>
</document>

"""#, ["UINavigationController-nvc-aa-aaa.nib": "7816e3386032de44d0d5d10c44517e6fd49bc1e52b847d8918a19095d10175a4", "vc1-aa-aaa-view-vw1-aa-aaa.nib": "049be9c5b429b28c1f71eea25171cb7965fdc08e25309c3d4c0acc1c04489f4a"]),
        ("bars-ni-title-space-2-x-lead", #"""
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
                    <navigationItem key="navigationItem" title=" x" id="nvi-aa-aaa"/>
                </viewController>
                <placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>
            </objects>
            <point key="canvasLocation" x="0" y="0"/>
        </scene>
    </scenes>
</document>

"""#, ["UINavigationController-nvc-aa-aaa.nib": "63a5954bf2f8fba422de07f3c1d7ec22d50b8b4851e08cecad52381c9442692a", "vc1-aa-aaa-view-vw1-aa-aaa.nib": "049be9c5b429b28c1f71eea25171cb7965fdc08e25309c3d4c0acc1c04489f4a"]),
        ("bars-sbn-style-black", #"""
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
                    <navigationBar key="navigationBar" contentMode="scaleToFill" barStyle="black" id="nvb-aa-aaa">
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

"""#, ["UINavigationController-nvc-aa-aaa.nib": "8b2455e8f565d53351c8e1a922e92d4194795be436d35b6b274e7341191e3164", "vc1-aa-aaa-view-vw1-aa-aaa.nib": "049be9c5b429b28c1f71eea25171cb7965fdc08e25309c3d4c0acc1c04489f4a"]),
        ("bars-sbn-bartint", #"""
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
                        <color key="barTintColor" red="1" green="0.0" blue="0.0" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
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

"""#, ["UINavigationController-nvc-aa-aaa.nib": "7d9f999d9ea61a67f1d39c4c04b9cc447a757ce00955eea7600f2944a772c446", "vc1-aa-aaa-view-vw1-aa-aaa.nib": "049be9c5b429b28c1f71eea25171cb7965fdc08e25309c3d4c0acc1c04489f4a"]),
        ("bars-sbn-text-color", #"""
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
                            <color key="textColor" red="1" green="0.0" blue="0.0" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
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

"""#, ["UINavigationController-nvc-aa-aaa.nib": "50e4e19782d5de354b1555fd82877937068b79cc347c930cf9ccb0bd36af5290", "vc1-aa-aaa-view-vw1-aa-aaa.nib": "049be9c5b429b28c1f71eea25171cb7965fdc08e25309c3d4c0acc1c04489f4a"]),
        ("bars-ni-always", #"""
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
                    <navigationItem key="navigationItem" title="Root" largeTitleDisplayMode="always" id="nvi-aa-aaa"/>
                </viewController>
                <placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>
            </objects>
            <point key="canvasLocation" x="0" y="0"/>
        </scene>
    </scenes>
</document>

"""#, ["UINavigationController-nvc-aa-aaa.nib": "087c598bdc78c8d68171cbccb70b4c7fdd05668a1446874bc81ef7f61676dbcf", "vc1-aa-aaa-view-vw1-aa-aaa.nib": "049be9c5b429b28c1f71eea25171cb7965fdc08e25309c3d4c0acc1c04489f4a"]),
        ("bars-ni-right-two", #"""
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
                    <navigationItem key="navigationItem" title="Root" id="nvi-aa-aaa">
                        <rightBarButtonItems>
                            <barButtonItem systemItem="add" id="bbi-aa-aa1"/>
                            <barButtonItem title="Two" id="bbi-aa-aa2"/>
                        </rightBarButtonItems>
                    </navigationItem>
                </viewController>
                <placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>
            </objects>
            <point key="canvasLocation" x="0" y="0"/>
        </scene>
    </scenes>
</document>

"""#, ["UINavigationController-nvc-aa-aaa.nib": "9064fe885cb162c58ba751001bfe4b81f24a6a16a9b5e9d9fbf2f9dec15191e5", "vc1-aa-aaa-view-vw1-aa-aaa.nib": "049be9c5b429b28c1f71eea25171cb7965fdc08e25309c3d4c0acc1c04489f4a"]),
        ("bars-ni-prompt", #"""
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
                    <navigationItem key="navigationItem" title="Root" prompt="Hello" id="nvi-aa-aaa"/>
                </viewController>
                <placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>
            </objects>
            <point key="canvasLocation" x="0" y="0"/>
        </scene>
    </scenes>
</document>

"""#, ["UINavigationController-nvc-aa-aaa.nib": "9b704ed7fecb3476f276004274678b9bb1b7ee448a2fae5dd1843353c769f6ba", "vc1-aa-aaa-view-vw1-aa-aaa.nib": "049be9c5b429b28c1f71eea25171cb7965fdc08e25309c3d4c0acc1c04489f4a"]),
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

    /// `bars-ni-plain-sys`: ibtool's warning for a plain bar button item in a navigation item.
    @Test func warnsOfAPlainItemInANavigationItem() throws {
        let compiled = try StoryboardCompiler.compileReportingWarnings(Data(Self.plainItem.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        #expect(compiled.warnings == ["/tmp/Main.storyboard:bbi-aa-aa1: warning: Plain Style unsupported in a Navigation Item [9]"])
    }

    static let plainItem = #"""
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
                    <navigationItem key="navigationItem" title="Root" id="nvi-aa-aaa">
                        <barButtonItem key="rightBarButtonItem" style="plain" systemItem="add" id="bbi-aa-aa1"/>
                    </navigationItem>
                </viewController>
                <placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>
            </objects>
            <point key="canvasLocation" x="0" y="0"/>
        </scene>
    </scenes>
</document>

"""#

    /// `bars-nb-plain-sys`: the same warning for a navigation bar among a xib's subviews.
    @Test func warnsOfAPlainItemInAXibsNavigationBar() throws {
        let compiled = try XIBCompiler.compileReportingWarnings(Data(Self.plainNavigationBar.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(compiled.warnings == ["/tmp/View.xib:bbi-aa-aa2: warning: Plain Style unsupported in a Navigation Item [9]"])
    }

    static let plainNavigationBar = #"""
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
                        <navigationItem title="Hello" id="nvi-aa-aa1">
                            <barButtonItem key="rightBarButtonItem" style="plain" systemItem="add" id="bbi-aa-aa2"/>
                        </navigationItem>
                    </items>
                </navigationBar>
            </subviews>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>

"""#
}
