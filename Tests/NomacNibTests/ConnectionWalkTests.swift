import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for connections of one name and event from several sources
/// (`.github/scripts/nib_experiments.py` rounds 118 and 119, `act-same-*`, `outlet-same-tree-*`):
/// by original class, then a walk of the views that differs between xibs and storyboards.
@Suite struct ConnectionWalkTests {
    indirect enum Node {
        case button(Int)
        case container([Node])
    }

    /// `[[1, [2, 3], 4], 5, [[6], 7], 8]`, the tree of `act-same-tree-mixed`.
    static let mixed: [Node] = [.container([.button(1), .container([.button(2), .button(3)]), .button(4)]), .button(5),
                                .container([.container([.button(6)]), .button(7)]), .button(8)]

    static func control(_ number: Int, x: Int, connection: String) -> String {
        "<button contentMode=\"scaleToFill\" opaque=\"NO\" contentHorizontalAlignment=\"center\" contentVerticalAlignment=\"center\" buttonType=\"system\" "
            + "lineBreakMode=\"middleTruncation\" translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"b\(String(format: "%02d", number))-aa-aa1\">\n"
            + "<rect key=\"frame\" x=\"\(x)\" y=\"20\" width=\"50\" height=\"30\"/>\n<connections>\n\(connection)\n</connections>\n</button>\n"
    }

    static func tree(_ nodes: [Node], prefix: String = "n", connection: (Int) -> String) -> String {
        nodes.enumerated().map { index, node in
            switch node {
            case .button(let number):
                return control(number, x: 10 * index, connection: connection(number))
            case .container(let children):
                let identifier = prefix.count < 3 ? prefix + String(index) + String(repeating: "x", count: 3 - prefix.count - 1) : prefix.prefix(2) + String(index)
                return "<view contentMode=\"scaleToFill\" translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"\(identifier)-aa-aa1\">\n"
                    + "<rect key=\"frame\" x=\"0\" y=\"\(60 * index)\" width=\"300\" height=\"50\"/>\n<subviews>\n"
                    + tree(children, prefix: prefix + String(index), connection: connection) + "</subviews>\n</view>\n"
            }
        }.joined()
    }

    static func action(destination: String) -> (Int) -> String {
        { "<action selector=\"tapped:\" destination=\"\(destination)\" eventType=\"touchUpInside\" id=\"a\(String(format: "%02d", $0))-aa-aa1\"/>" }
    }

    static func outlet(destination: String) -> (Int) -> String {
        { "<outlet property=\"delegate\" destination=\"\(destination)\" id=\"a\(String(format: "%02d", $0))-aa-aa1\"/>" }
    }

    static func scene(_ subviews: String) -> String {
        """
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
        \(subviews)</subviews>
        </view>
        </viewController>
        <placeholder placeholderIdentifier="IBFirstResponder" id="dkx-z0-nzr" sceneMemberID="firstResponder"/>
        </objects>
        <point key="canvasLocation" x="0" y="0"/>
        </scene>
        </scenes>
        </document>
        """
    }

    /// A xib walks its views depth first, whatever the frames, ids or the actions' ids (`act-same-*`).
    @Test func xibsWalkDepthFirst() throws {
        for (connection, size, digest) in [(Self.action(destination: "-1"), 2938, "3f7fa00bce0882a953ac6400e3e1d5e88c70675a6d8c773764367bcf7e025540"),
                                           (Self.outlet(destination: "-1"), 2904, "91e4d2ee9b3b287e18e5f184d0f82b15962bd609995d531cb8f6e45321ce4387")] {
            let document = ConstraintTests.constrained(Self.tree(Self.mixed, connection: connection), "")
            let nib = try XIBCompiler.compile(Data(document.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
            #expect(nib.count == size)
            #expect(VariationTests.digest(nib) == digest)
        }
    }

    /// A storyboard's view takes its subviews' connections in order, then goes on from its last
    /// subview: 5, 8, 7, 6, 1, 4, 2, 3 (`sb-act-same-mixed`, `sb-outlet-same-tree-mixed`).
    @Test func storyboardsWalkTheLastSubviewFirst() throws {
        for (connection, size, digest) in [(Self.action(destination: "BYZ-38-t0r"), 3883, "7728235ebe8e57a1f39d10be9312c9db7a1a7cfa299a790700dbf5f71f2d741a"),
                                           (Self.outlet(destination: "BYZ-38-t0r"), 3821, "73dda2ca38cb674c86f9b01c4e07ea58ede90bfede48c5fe795928eeb978b9bf")] {
            let document = Self.scene(Self.tree(Self.mixed, connection: connection))
            let files = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
            let nib = try #require(files["BYZ-38-t0r-view-8bC-Xf-vdC.nib"])
            #expect(nib.count == size)
            #expect(VariationTests.digest(nib) == digest)
        }
    }

    /// Two recognizers of one class and selector keep the top-level objects' order; of two
    /// `<connections>` of one view ibtool reads the first (`gesture-two-taps`, `gesture-two`).
    @Test func topLevelObjectsKeepTheirOrder() throws {
        func recognizer(_ tag: String, _ id: String) -> String {
            "<\(tag) id=\"\(id)\">\n<connections>\n<action selector=\"tapped:\" destination=\"-1\" id=\"act-\(id.prefix(3))-aa1\"/>\n</connections>\n</\(tag)>\n"
        }
        let two = ConstraintTests.constrained(ConstraintTests.subview("sss-ss-ss1"), "").replacingOccurrences(
            of: "</objects>", with: recognizer("tapGestureRecognizer", "tap-aa-aa1") + recognizer("tapGestureRecognizer", "tbp-aa-aa1") + "</objects>")
        let nib = try XIBCompiler.compile(Data(two.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == 1216)
        #expect(VariationTests.digest(nib) == "59147fc9926671e7dbaacd0746ed1821142ef051679e109a17e2702236f32b01")
        let attach = { (id: String) in "<connections>\n<outletCollection property=\"gestureRecognizers\" destination=\"\(id)\" appends=\"YES\" id=\"gr\(id.prefix(3))-aa-aa1\"/>\n</connections>\n" }
        let view = ConstraintTests.subview("sss-ss-ss1").replacingOccurrences(of: "</view>", with: attach("tap-aa-aa1") + attach("swp-aa-aa1") + "</view>")
        let swipe = "<swipeGestureRecognizer direction=\"right\" id=\"swp-aa-aa1\">\n<connections>\n<action selector=\"tapped:\" destination=\"-1\" id=\"act-swp-aa1\"/>\n</connections>\n</swipeGestureRecognizer>\n"
        let attached = ConstraintTests.constrained(view, "").replacingOccurrences(of: "</objects>", with: recognizer("tapGestureRecognizer", "tap-aa-aa1") + swipe + "</objects>")
        let attachedNib = try XIBCompiler.compile(Data(attached.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(attachedNib.count == 1414)
        #expect(VariationTests.digest(attachedNib) == "f511c0dd3c00239e3c1af670d9654de23923b0672920d9329493c22d2786a867")
    }
}
