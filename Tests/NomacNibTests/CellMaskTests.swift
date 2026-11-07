import Foundation
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for a label's masks, size-class masks inside a cell's content
/// view, a variation's own frame and flags, the value2 cell style, `colorLabel` and text fields'
/// background images (`.github/scripts/nib_experiments.py`, `cm-*`): sizes and SHA-256 digests of
/// Xcode's nibs.
@Suite struct CellMaskTests {
    static let cases: [(String, String, Int, String)] = [
        ("cm-image-default", #"""
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
        <tableViewCell contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" textLabel="tlb-aa-aa1" imageView="img-aa-aa1" style="IBUITableViewCellStyleDefault" id="KGk-i7-Jjw">
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
                        </label>
                        <imageView opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="scaleToFill" image="Logo" id="img-aa-aa1">
                            <rect key="frame" x="16" y="3" width="37" height="37"/>
                            <autoresizingMask key="autoresizingMask"/>
                        </imageView>
                    </subviews>
            </tableViewCellContentView>
            <viewLayoutGuide key="safeArea" id="njF-e1-oar"/>
            <point key="canvasLocation" x="0" y="0"/>
        </tableViewCell>
    </objects>
    <resources>
        <image name="Logo" width="37" height="37"/>
    </resources>
</document>

"""#, 2675, "01bfc9ae33a686121c047191a5bf03352f7be0ddff9cb02307f250ddefa0f0b6"),
        ("cm-image-first", #"""
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
        <tableViewCell contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" textLabel="tlb-aa-aa1" imageView="img-aa-aa1" style="IBUITableViewCellStyleDefault" id="KGk-i7-Jjw">
            <rect key="frame" x="0.0" y="0.0" width="320" height="44"/>
            <autoresizingMask key="autoresizingMask"/>
            <tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" tableViewCell="KGk-i7-Jjw" id="H2p-sc-9uM">
                <rect key="frame" x="0.0" y="0.0" width="320" height="44"/>
                <autoresizingMask key="autoresizingMask"/>
                    <subviews>
                        <imageView opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="scaleToFill" image="Logo" id="img-aa-aa1">
                            <rect key="frame" x="16" y="3" width="37" height="37"/>
                            <autoresizingMask key="autoresizingMask"/>
                        </imageView>
                        <label opaque="NO" multipleTouchEnabled="YES" contentMode="left" text="Title" textAlignment="natural" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" id="tlb-aa-aa1">
                            <rect key="frame" x="68" y="0" width="236" height="44"/>
                            <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
                            <fontDescription key="fontDescription" type="system" pointSize="16"/>
                            <nil key="textColor"/>
                            <nil key="highlightedColor"/>
                        </label>
                    </subviews>
            </tableViewCellContentView>
            <viewLayoutGuide key="safeArea" id="njF-e1-oar"/>
            <point key="canvasLocation" x="0" y="0"/>
        </tableViewCell>
    </objects>
    <resources>
        <image name="Logo" width="37" height="37"/>
    </resources>
</document>

"""#, 2675, "2df3b6adf604b694d126e4bdc9cb96e8562b1e3a357372d924d5d51742b222ef"),
        ("cm-image-value1", #"""
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
        <tableViewCell contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" textLabel="tlb-aa-aa1" detailTextLabel="dlb-aa-aa1" imageView="img-aa-aa1" style="IBUITableViewCellStyleValue1" id="KGk-i7-Jjw">
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
                        </label>
                        <label opaque="NO" multipleTouchEnabled="YES" contentMode="left" text="Detail" textAlignment="natural" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" id="dlb-aa-aa1">
                            <rect key="frame" x="68" y="25" width="44" height="14.5"/>
                            <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
                            <fontDescription key="fontDescription" type="system" pointSize="12"/>
                            <nil key="textColor"/>
                            <nil key="highlightedColor"/>
                        </label>
                        <imageView opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="scaleToFill" id="img-aa-aa1">
                            <rect key="frame" x="16" y="3" width="37" height="37"/>
                            <autoresizingMask key="autoresizingMask"/>
                        </imageView>
                    </subviews>
            </tableViewCellContentView>
            <viewLayoutGuide key="safeArea" id="njF-e1-oar"/>
            <point key="canvasLocation" x="0" y="0"/>
        </tableViewCell>
    </objects>
</document>

"""#, 2786, "745d7bee6d491f42ed9151ca28a76297a7fbfdbb5a8836e9c82e6b28621bb3a6"),
        ("cm-image-custom", #"""
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
        <tableViewCell contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" textLabel="tlb-aa-aa1" imageView="img-aa-aa1" style="IBUITableViewCellStyleDefault" id="KGk-i7-Jjw">
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
                        </label>
                        <imageView opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="scaleToFill" customClass="Icon" customModule="T" customModuleProvider="target" id="img-aa-aa1">
                            <rect key="frame" x="16" y="3" width="37" height="37"/>
                            <autoresizingMask key="autoresizingMask"/>
                        </imageView>
                    </subviews>
            </tableViewCellContentView>
            <viewLayoutGuide key="safeArea" id="njF-e1-oar"/>
            <point key="canvasLocation" x="0" y="0"/>
        </tableViewCell>
    </objects>
</document>

"""#, 2561, "eb7ae8540c73a7e3434287dff9aee0d9c2a78b2995c03f6e22c10de1831ab3ce"),
        ("cm-label-mask-default", #"""
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
                    <constraints>
                        <constraint firstAttribute="width" constant="42" id="c10-aa-aaa"/>
                        <constraint firstAttribute="height" constant="21" id="c11-aa-aaa"/>
                    </constraints>
                    <variation key="default">
                        <mask key="constraints">
                            <exclude reference="c10-aa-aaa"/>
                        </mask>
                    </variation>
                </label>
            </subviews>
            <constraints>
                <constraint firstItem="lll-ll-ll1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" id="c00-aa-aaa"/>
                <constraint firstItem="lll-ll-ll1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" id="c01-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>
"""#, 2734, "cf1eaa7ddb679eb28b65aa5f593697f5d04adfe3664e787a77285cccc0884e44"),
        ("cm-label-mask-sc", #"""
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
                    <constraints>
                        <constraint firstAttribute="width" constant="42" id="c10-aa-aaa"/>
                        <constraint firstAttribute="height" constant="21" id="c11-aa-aaa"/>
                    </constraints>
                    <variation key="default">
                        <mask key="constraints">
                            <exclude reference="c10-aa-aaa"/>
                        </mask>
                    </variation>
                    <variation key="heightClass=regular-widthClass=compact">
                        <mask key="constraints">
                            <include reference="c10-aa-aaa"/>
                        </mask>
                    </variation>
                </label>
            </subviews>
            <constraints>
                <constraint firstItem="lll-ll-ll1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" id="c00-aa-aaa"/>
                <constraint firstItem="lll-ll-ll1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" id="c01-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>
"""#, 2907, "330aa6f536a4e3e88d9fc011010c24d0a3944a31fd157c98ab947771d4027c36"),
        ("cm-label-mask-font", #"""
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
                    <constraints>
                        <constraint firstAttribute="width" constant="42" id="c10-aa-aaa"/>
                        <constraint firstAttribute="height" constant="21" id="c11-aa-aaa"/>
                    </constraints>
                    <variation key="default">
                        <mask key="constraints">
                            <exclude reference="c10-aa-aaa"/>
                        </mask>
                    </variation>
                    <variation key="heightClass=regular-widthClass=compact">
                        <fontDescription key="fontDescription" type="system" pointSize="22"/>
                        <mask key="constraints">
                            <include reference="c10-aa-aaa"/>
                        </mask>
                    </variation>
                </label>
            </subviews>
            <constraints>
                <constraint firstItem="lll-ll-ll1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" id="c00-aa-aaa"/>
                <constraint firstItem="lll-ll-ll1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" id="c01-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>
"""#, 3207, "efa17c9ca1903acb34a30e9788c8f7191c245afd2864963e7540af96c38a2332"),
        ("cm-label-mask-font-two", #"""
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
                    <constraints>
                        <constraint firstAttribute="width" constant="42" id="c10-aa-aaa"/>
                        <constraint firstAttribute="height" constant="21" id="c11-aa-aaa"/>
                    </constraints>
                    <variation key="default">
                        <mask key="constraints">
                            <exclude reference="c10-aa-aaa"/>
                        </mask>
                    </variation>
                    <variation key="heightClass=regular-widthClass=compact">
                        <mask key="constraints">
                            <include reference="c10-aa-aaa"/>
                        </mask>
                    </variation>
                    <variation key="heightClass=compact-widthClass=compact">
                        <fontDescription key="fontDescription" type="system" pointSize="22"/>
                    </variation>
                </label>
            </subviews>
            <constraints>
                <constraint firstItem="lll-ll-ll1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" id="c00-aa-aaa"/>
                <constraint firstItem="lll-ll-ll1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" id="c01-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>
"""#, 3207, "22a51242527d062c09f16e2250773d20e106956e9ea096f351bd7c410bddf32b"),
        ("cm-label-mask-empty", #"""
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
                    <constraints>
                        <constraint firstAttribute="width" constant="42" id="c10-aa-aaa"/>
                        <constraint firstAttribute="height" constant="21" id="c11-aa-aaa"/>
                    </constraints>
                    <variation key="default">
                        <mask key="constraints"/>
                    </variation>
                </label>
            </subviews>
            <constraints>
                <constraint firstItem="lll-ll-ll1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" id="c00-aa-aaa"/>
                <constraint firstItem="lll-ll-ll1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" id="c01-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>
"""#, 2258, "41a54b66f05404ca33207745e2b3eba00d3874cffb1a8520ad6f8e5ff025cd58"),
        ("cm-cell-sub-mask-sc", #"""
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
                    <subviews>
                <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="sss-ss-ss1">
                    <rect key="frame" x="10" y="5" width="42" height="21"/>
                    <constraints>
                        <constraint firstAttribute="width" constant="42" id="c10-aa-aaa"/>
                        <constraint firstAttribute="height" constant="21" id="c11-aa-aaa"/>
                    </constraints>
                    <variation key="default">
                        <mask key="constraints">
                            <exclude reference="c10-aa-aaa"/>
                        </mask>
                    </variation>
                    <variation key="heightClass=regular-widthClass=compact">
                        <mask key="constraints">
                            <include reference="c10-aa-aaa"/>
                        </mask>
                    </variation>
                </view>
                    </subviews>
            </tableViewCellContentView>
            <viewLayoutGuide key="safeArea" id="njF-e1-oar"/>
            <point key="canvasLocation" x="0" y="0"/>
        </tableViewCell>
    </objects>
</document>
"""#, 2693, "e244728f61a6de9085004a3fdfe7b1399bd4e7765a10a3d658cb7d5a36ae0f6b"),
        ("cm-cell-deep-mask-sc", #"""
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
                    <subviews>
                <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="ddd-dd-dd1">
                    <rect key="frame" x="0" y="0" width="100" height="40"/>
                    <subviews>
                <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="sss-ss-ss1">
                    <rect key="frame" x="10" y="5" width="42" height="21"/>
                    <constraints>
                        <constraint firstAttribute="width" constant="42" id="c10-aa-aaa"/>
                        <constraint firstAttribute="height" constant="21" id="c11-aa-aaa"/>
                    </constraints>
                    <variation key="default">
                        <mask key="constraints">
                            <exclude reference="c10-aa-aaa"/>
                        </mask>
                    </variation>
                    <variation key="heightClass=regular-widthClass=compact">
                        <mask key="constraints">
                            <include reference="c10-aa-aaa"/>
                        </mask>
                    </variation>
                </view>
                    </subviews>
                </view>
                    </subviews>
            </tableViewCellContentView>
            <viewLayoutGuide key="safeArea" id="njF-e1-oar"/>
            <point key="canvasLocation" x="0" y="0"/>
        </tableViewCell>
    </objects>
</document>
"""#, 2795, "94dd2adae5e162500535cb720d0e10f16f78c3f2c39b78cfb27ff9fcaedcf784"),
        ("cm-var-misplaced-label", #"""
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
                    <constraints>
                        <constraint firstAttribute="width" constant="42" id="c10-aa-aaa"/>
                        <constraint firstAttribute="height" constant="21" id="c11-aa-aaa"/>
                    </constraints>
                    <variation key="heightClass=regular" misplaced="YES">
                        <rect key="frame" x="9" y="7" width="42" height="21"/>
                    </variation>
                </label>
            </subviews>
            <constraints>
                <constraint firstItem="lll-ll-ll1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" id="c00-aa-aaa"/>
                <constraint firstItem="lll-ll-ll1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" id="c01-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>
"""#, 2258, "41a54b66f05404ca33207745e2b3eba00d3874cffb1a8520ad6f8e5ff025cd58"),
        ("cm-var-ambiguous-misplaced-label", #"""
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
                    <constraints>
                        <constraint firstAttribute="width" constant="42" id="c10-aa-aaa"/>
                        <constraint firstAttribute="height" constant="21" id="c11-aa-aaa"/>
                    </constraints>
                    <variation key="heightClass=compact" ambiguous="YES" misplaced="YES">
                        <rect key="frame" x="9" y="7" width="42" height="21"/>
                    </variation>
                </label>
            </subviews>
            <constraints>
                <constraint firstItem="lll-ll-ll1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" id="c00-aa-aaa"/>
                <constraint firstItem="lll-ll-ll1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" id="c01-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>
"""#, 2258, "41a54b66f05404ca33207745e2b3eba00d3874cffb1a8520ad6f8e5ff025cd58"),
        ("cm-var-fixed-view", #"""
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
                    <variation key="heightClass=regular" fixedFrame="YES">
                        <rect key="frame" x="9" y="7" width="100" height="50"/>
                    </variation>
                </view>
            </subviews>
            <constraints>
                <constraint firstItem="sss-ss-ss1" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" id="c00-aa-aaa"/>
                <constraint firstItem="sss-ss-ss1" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" id="c01-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
</document>
"""#, 1188, "b30ed580c11b470322347fcd0e49b3849556189f61b135914691c1be49e56cf5"),
        ("cm-value2", #"""
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
        <tableViewCell contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" textLabel="tlb-aa-aa1" detailTextLabel="dlb-aa-aa1" style="IBUITableViewCellStyleValue2" id="KGk-i7-Jjw">
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
                        </label>
                        <label opaque="NO" multipleTouchEnabled="YES" contentMode="left" text="Detail" textAlignment="natural" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" id="dlb-aa-aa1">
                            <rect key="frame" x="68" y="25" width="44" height="14.5"/>
                            <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
                            <fontDescription key="fontDescription" type="system" pointSize="12"/>
                            <nil key="textColor"/>
                            <nil key="highlightedColor"/>
                        </label>
                    </subviews>
            </tableViewCellContentView>
            <viewLayoutGuide key="safeArea" id="njF-e1-oar"/>
            <point key="canvasLocation" x="0" y="0"/>
        </tableViewCell>
    </objects>
</document>
"""#, 2682, "ad851d0a63dd8c1e4c28eb558294609d56a054e308f23b2b188ea7c19979b2ed"),
        ("cm-color-label-red", #"""
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
        <tableViewCell contentMode="scaleToFill" selectionStyle="default" indentationWidth="10" colorLabel="IBBuiltInLabel-Red" customClass="Cell" customModule="T" customModuleProvider="target" id="KGk-i7-Jjw">
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
"""#, 1485, "f2ee43836202de873180c2d8e6e1d7a09a49165d4595291bfdc54ca5fcf0ccac"),
        ("cm-tf-background", #"""
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
                <textField opaque="NO" clipsSubviews="YES" contentMode="scaleToFill" contentHorizontalAlignment="left" contentVerticalAlignment="center" placeholder="Name" background="Logo" textAlignment="natural" minimumFontSize="17" translatesAutoresizingMaskIntoConstraints="NO" id="txf-aa-aaa">
                    <rect key="frame" x="16" y="100" width="359" height="44"/>
                    <fontDescription key="fontDescription" type="system" pointSize="17"/>
                    <textInputTraits key="textInputTraits"/>
                </textField>
            </subviews>
            <constraints>
                <constraint firstItem="txf-aa-aaa" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="16" id="c00-aa-aaa"/>
                <constraint firstItem="txf-aa-aaa" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="100" id="c01-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
    <resources>
        <image name="Logo" width="37" height="37"/>
    </resources>
</document>
"""#, 2460, "6692fcc69811ef77517f8c19ebb22f23dec6774380d04bbfac1e66d4ecef0920"),
        ("cm-tf-disabled", #"""
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
                <textField opaque="NO" clipsSubviews="YES" contentMode="scaleToFill" contentHorizontalAlignment="left" contentVerticalAlignment="center" placeholder="Name" disabledBackground="Logo" textAlignment="natural" minimumFontSize="17" translatesAutoresizingMaskIntoConstraints="NO" id="txf-aa-aaa">
                    <rect key="frame" x="16" y="100" width="359" height="44"/>
                    <fontDescription key="fontDescription" type="system" pointSize="17"/>
                    <textInputTraits key="textInputTraits"/>
                </textField>
            </subviews>
            <constraints>
                <constraint firstItem="txf-aa-aaa" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="16" id="c00-aa-aaa"/>
                <constraint firstItem="txf-aa-aaa" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="100" id="c01-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
    <resources>
        <image name="Logo" width="37" height="37"/>
    </resources>
</document>
"""#, 2422, "ad1b03f76ad38765bc99b88d55c1cae7be0569f1f8baa9781df217ade3b2ea99"),
        ("cm-tf-both", #"""
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
                <textField opaque="NO" clipsSubviews="YES" contentMode="scaleToFill" contentHorizontalAlignment="left" contentVerticalAlignment="center" placeholder="Name" background="Logo" disabledBackground="Other" textAlignment="natural" minimumFontSize="17" translatesAutoresizingMaskIntoConstraints="NO" id="txf-aa-aaa">
                    <rect key="frame" x="16" y="100" width="359" height="44"/>
                    <fontDescription key="fontDescription" type="system" pointSize="17"/>
                    <textInputTraits key="textInputTraits"/>
                </textField>
            </subviews>
            <constraints>
                <constraint firstItem="txf-aa-aaa" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="16" id="c00-aa-aaa"/>
                <constraint firstItem="txf-aa-aaa" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="100" id="c01-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
    <resources>
        <image name="Logo" width="37" height="37"/>
        <image name="Other" width="20" height="20"/>
    </resources>
</document>
"""#, 2534, "c372084e1e2a720fe076185c263d2f46596375580f4417d6ed8b9e222bc4803a"),
        ("cm-tf-same", #"""
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
                <textField opaque="NO" clipsSubviews="YES" contentMode="scaleToFill" contentHorizontalAlignment="left" contentVerticalAlignment="center" placeholder="Name" background="Logo" disabledBackground="Logo" textAlignment="natural" minimumFontSize="17" translatesAutoresizingMaskIntoConstraints="NO" id="txf-aa-aaa">
                    <rect key="frame" x="16" y="100" width="359" height="44"/>
                    <fontDescription key="fontDescription" type="system" pointSize="17"/>
                    <textInputTraits key="textInputTraits"/>
                </textField>
            </subviews>
            <constraints>
                <constraint firstItem="txf-aa-aaa" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="16" id="c00-aa-aaa"/>
                <constraint firstItem="txf-aa-aaa" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="100" id="c01-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
    <resources>
        <image name="Logo" width="37" height="37"/>
    </resources>
</document>
"""#, 2496, "d484ee037139e8f5a735ed23e8c3ce4696ded14d4d42d3b4347323b21a6df43a"),
        ("cm-tf-disabled-rounded", #"""
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
                <textField opaque="NO" clipsSubviews="YES" contentMode="scaleToFill" contentHorizontalAlignment="left" contentVerticalAlignment="center" placeholder="Name" borderStyle="roundedRect" disabledBackground="Logo" clearsOnBeginEditing="YES" textAlignment="natural" minimumFontSize="17" translatesAutoresizingMaskIntoConstraints="NO" id="txf-aa-aaa">
                    <rect key="frame" x="16" y="100" width="359" height="44"/>
                    <fontDescription key="fontDescription" type="system" pointSize="17"/>
                    <textInputTraits key="textInputTraits"/>
                </textField>
            </subviews>
            <constraints>
                <constraint firstItem="txf-aa-aaa" firstAttribute="leading" secondItem="iN0-l3-epB" secondAttribute="leading" constant="16" id="c00-aa-aaa"/>
                <constraint firstItem="txf-aa-aaa" firstAttribute="top" secondItem="iN0-l3-epB" secondAttribute="top" constant="100" id="c01-aa-aaa"/>
            </constraints>
            <point key="canvasLocation" x="0" y="0"/>
        </view>
    </objects>
    <resources>
        <image name="Logo" width="37" height="37"/>
    </resources>
</document>
"""#, 2510, "7c1b81237087f10eb65582c4bab3f223b7af18d7f718d7059a042aea79e0f5ae"),
    ]

    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }
}
