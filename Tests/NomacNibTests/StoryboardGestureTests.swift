import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for gesture recognizers in storyboards (`.github/scripts/nib_experiments.py`
/// round 52, `sb_gestures`): sizes and SHA-256 digests of Xcode's view and controller nibs.
@Suite struct StoryboardGestureTests {
    static func subview(_ id: String, y: Int = 10, recognizer: String? = nil, extra: String = "") -> String {
        "<view contentMode=\"scaleToFill\"\(extra) id=\"\(id)\">\n<rect key=\"frame\" x=\"10\" y=\"\(y)\" width=\"50\" height=\"50\"/>\n"
            + #"<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>"# + "\n<gestureRecognizers/>\n"
            + (recognizer.map { "<connections>\n" + attachment($0) + "</connections>\n" } ?? "") + "</view>\n"
    }

    static func attachment(_ recognizer: String) -> String {
        "<outletCollection property=\"gestureRecognizers\" destination=\"\(recognizer)\" appends=\"YES\" id=\"o\(recognizer.prefix(2))-aa-aa1\"/>\n"
    }

    static func recognizer(_ tag: String = "tapGestureRecognizer", attributes: String = "", action: Bool = true) -> String {
        guard action else { return "<\(tag)\(attributes) id=\"tap-aa-aa1\"/>\n" }
        return "<\(tag)\(attributes) id=\"tap-aa-aa1\">\n<connections>\n" + #"<action selector="tapped:" destination="BYZ-38-t0r" id="ata-aa-aa1"/>"#
            + "\n</connections>\n</\(tag)>\n"
    }

    static func document(_ subviews: String, recognizers: String = recognizer(), rootChildren: String = "") -> String {
        StoryboardCompilerTests.storyboard(StoryboardCompilerTests.scene(viewChildren: rootChildren + "<subviews>\n\(subviews)</subviews>\n"))
            .replacingOccurrences(of: #"sceneMemberID="firstResponder"/>"#, with: #"sceneMemberID="firstResponder"/>"# + "\n" + recognizers)
    }

    static let owner = subview("sub-vi-ew2", y: 70, extra: #" customClass="Box" customModule="T" customModuleProvider="target""#)
        .replacingOccurrences(of: "<gestureRecognizers/>\n", with: "<connections>\n" + #"<outlet property="owner" destination="BYZ-38-t0r" id="own-aa-aa1"/>"#
                              + "\n</connections>\n")
    static let root = "<gestureRecognizers/>\n<connections>\n" + attachment("tap-aa-aa1") + "</connections>\n"

    static let cases: [(String, String, [(String, Int, String)])] = [
        ("sb-gesture", document(subview("sub-vi-ew1", recognizer: "tap-aa-aa1")), [
            ("BYZ-38-t0r-view-8bC-Xf-vdC", 2022, "247a67b1b60114b2d7bb29c0c05ae4c54ba69f828985d47a47ace38dc5514d6a"),
            ("UIViewController-BYZ-38-t0r", 1275, "67fb9321e361a20892ddcd9258faf1aab59cb23bc22d9a923de77b17de27a243"),
        ]),
        ("sb-gesture-root", document(subview("sub-vi-ew1"), rootChildren: root), [
            ("BYZ-38-t0r-view-8bC-Xf-vdC", 2022, "dd6b4fd1d859863cc97f64b2ac2c0ac1cfbbb981779adb5c1f9b797c09327942"),
        ]),
        ("sb-gesture-and-controller", document(subview("sub-vi-ew1", recognizer: "tap-aa-aa1") + owner), [
            ("BYZ-38-t0r-view-8bC-Xf-vdC", 2286, "9dae083c6a1c9392b513ba6bb501929f274967e96613fb7dfd699ced229ed8dd"),
            ("UIViewController-BYZ-38-t0r", 1314, "de685573449a0537f0a6baf9a093a55ee4fd5b671ee0767020cdd5e9702646e9"),
        ]),
        ("sb-gesture-no-action", document(subview("sub-vi-ew1", recognizer: "tap-aa-aa1"), recognizers: recognizer(action: false)), [
            ("UIViewController-BYZ-38-t0r", 1208, "5b72fdcef3ce331ee451eda6723bb52c0b4ed7fed91f4197a3e43217115dfbcc"),
        ]),
        ("sb-gesture-swipe", document(subview("sub-vi-ew1", recognizer: "tap-aa-aa1"), recognizers: recognizer("swipeGestureRecognizer", attributes: #" direction="right""#)), [
            ("UIViewController-BYZ-38-t0r", 1222, "924ee8e9fdee71ac89af8b08a3ff9488849e07015008d8dbbc8a01c2d94abcb1"),
        ]),
    ]

    /// The recognizer a top-level object of the controller's nib, kept alive and loaded by the view
    /// nib as `UpstreamPlaceholder-1`, the controller then 2; its actions in the controller's nib;
    /// IB's empty `<gestureRecognizers/>` ignored.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, document: String, nibs: [(String, Int, String)]) throws {
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        for (nib, size, digest) in nibs {
            let data = try #require(compiled["\(nib).nib"], "\(name) \(nib)")
            #expect(data.count == size, "\(name) \(nib)")
            #expect(VariationTests.digest(data) == digest, "\(name) \(nib)")
        }
    }

    /// `sb-gesture-three*`, `sb-gesture-nested`: placeholders of several recognizers numbered by a
    /// rule the corpus contradicts (B-291).
    @Test func refusesSeveralRecognizers() {
        let document = Self.document(Self.subview("sub-vi-ew1", recognizer: "tap-aa-aa1") + Self.subview("sub-vi-ew2", y: 70, recognizer: "tbp-aa-aa1"),
                                     recognizers: Self.recognizer() + Self.recognizer().replacingOccurrences(of: "tap-aa-aa1", with: "tbp-aa-aa1")
                                        .replacingOccurrences(of: "ata-aa-aa1", with: "atb-aa-aa1"))
        #expect(throws: NomacError("nomac does not compile several gesture recognizers in a scene yet (BACKLOG B-291)", path: "/tmp/Main.storyboard")) {
            try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        }
    }
}
