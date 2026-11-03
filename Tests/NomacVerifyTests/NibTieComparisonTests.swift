import Foundation
import Testing
@testable import NomacNib
@testable import NomacVerify

/// ADR 0253: a view's constraints from one item by the same attributes to several views, required and
/// satisfied by the document's frames, compare whatever their order.
@Suite struct NibTieComparisonTests {
    static let head = """
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

        """

    static func subview(_ id: String, _ y: Int) -> String {
        "<view contentMode=\"scaleToFill\" translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"\(id)\">\n<rect key=\"frame\" x=\"0\" y=\"\(y)\" width=\"100\" height=\"50\"/>\n</view>\n"
    }

    static func constraint(_ number: Int, _ first: String, _ firstAttribute: String, _ second: String, _ secondAttribute: String, _ constant: Int) -> String {
        "<constraint firstItem=\"\(first)\" firstAttribute=\"\(firstAttribute)\" secondItem=\"\(second)\" secondAttribute=\"\(secondAttribute)\" constant=\"\(constant)\" id=\"c\(number)-aa-aaa\"/>\n"
    }

    /// Two subviews pinned to the view, a third whose top lies 12 below both (`tie-second-items`).
    static func document(tiesReversed: Bool) -> Data {
        let root = "iN0-l3-epB"
        let pins = [("aaa-aa-aa1", 0), ("bbb-bb-bb1", 100), ("xxx-xx-xx1", 300)].enumerated().map { index, entry in
            constraint(index * 2, entry.0, "leading", root, "leading", 0) + constraint(index * 2 + 1, entry.0, "top", root, "top", entry.1)
        }.joined()
        let ties = [constraint(10, "xxx-xx-xx1", "top", "aaa-aa-aa1", "bottom", 250), constraint(11, "xxx-xx-xx1", "top", "bbb-bb-bb1", "bottom", 150)]
        let xib = head + subview("aaa-aa-aa1", 0) + subview("bbb-bb-bb1", 100) + subview("xxx-xx-xx1", 300) + "</subviews>\n<constraints>\n" + pins
            + (tiesReversed ? ties.reversed().joined() : ties.joined()) + "</constraints>\n<point key=\"canvasLocation\" x=\"0\" y=\"0\"/>\n</view>\n</objects>\n</document>\n"
        return Data(xib.utf8)
    }

    static let options = XIBCompiler.Options(module: "T", minimumDeploymentTarget: "27.0", targetDevices: ["iphone"])

    @Test func settledTiesCompareInEitherOrder() throws {
        let written = try XIBCompiler.compile(Self.document(tiesReversed: false), path: "/tmp/View.xib", options: Self.options)
        let reversed = try XIBCompiler.compile(Self.document(tiesReversed: true), path: "/tmp/View.xib", options: Self.options)
        #expect(written != reversed)
        #expect(NibTieComparison.canonical(written) != nil)
        #expect(NibTieComparison.canonical(written) == NibTieComparison.canonical(reversed))
    }

    @Test func otherDifferencesStayDifferent() throws {
        let written = try XIBCompiler.compile(Self.document(tiesReversed: false), path: "/tmp/View.xib", options: Self.options)
        let wider = Self.document(tiesReversed: true).replacingOccurrences(of: "y=\"100\" width=\"100\"", with: "y=\"100\" width=\"120\"")
        let moved = try XIBCompiler.compile(wider, path: "/tmp/View.xib", options: Self.options)
        #expect(NibTieComparison.canonical(written) != NibTieComparison.canonical(moved))
    }
}

private extension Data {
    func replacingOccurrences(of target: String, with replacement: String) -> Data {
        Data(String(decoding: self, as: UTF8.self).replacingOccurrences(of: target, with: replacement).utf8)
    }
}
