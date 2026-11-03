import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What ibtool (Xcode 27.0) writes for controls' actions (`.github/scripts/nib_experiments.py`
/// round 33, `act-*`): sizes and SHA-256 digests of Xcode's nibs.
@Suite struct ActionTests {
    typealias C = ConstraintTests
    static let events = [("began:", "editingDidBegin"), ("exit:", "editingDidEndOnExit"), ("primary:", "primaryActionTriggered"), ("touched:", "touchUpInside"),
                         ("value:", "valueChanged"), ("ended:", "editingDidEnd"), ("changed:", "editingChanged")]

    static func actions(_ pairs: [(String, String?)], to destination: String = "-1") -> String {
        "<connections>\n" + pairs.enumerated().map { offset, pair in
            "<action selector=\"\(pair.0)\" destination=\"\(destination)\"\(pair.1.map { " eventType=\"\($0)\"" } ?? "") id=\"ac\(offset)-aa-aaa\"/>\n"
        }.joined() + "</connections>\n"
    }

    static func control(_ connections: String = "") -> String {
        #"<view contentMode="scaleToFill" customClass="Dial" customModule="T" customModuleProvider="target" translatesAutoresizingMaskIntoConstraints="NO" id="ctl-aa-aaa">"#
            + "\n<rect key=\"frame\" x=\"10\" y=\"20\" width=\"100\" height=\"50\"/>\n\(connections)</view>\n"
    }

    static func field(_ number: Int, _ y: Int, _ connections: String) -> String {
        TofuFeatureTests.field(id: "tf\(number)-aa-aaa", y: y, connections: connections)
    }

    static let changed = [("changed:", Optional("editingChanged"))]
    static let owner = #"<placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File's Owner"/>"#
    static let ownerOutlets = #"<placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File's Owner">"# + "\n<connections>\n"
        + "<outlet property=\"zeta\" destination=\"tf1-aa-aaa\" id=\"ou1-aa-aaa\"/>\n<outlet property=\"beta\" destination=\"tf2-aa-aaa\" id=\"ou2-aa-aaa\"/>\n"
        + "</connections>\n</placeholder>"

    static let cases: [(String, String, Int, String)] = [
        ("act-field-all-events", C.constrained(field(1, 100, actions(events.map { ($0.0, Optional($0.1)) })), TofuFeatureTests.pin("tf1-aa-aaa", 0, 16, 100)),
         2603, "cbbad4a0f767c83e56473a2a904f0695eb2f4a5da14d8211d4c800faf9b7e220"),
        ("act-field-no-event", C.constrained(field(1, 100, actions([("changed:", nil)])), TofuFeatureTests.pin("tf1-aa-aaa", 0, 16, 100)),
         2311, "1808f580dfbc73295507b89d13c5583a8685e6226337baedcdee3fd6c798c578"),
        ("act-control-touch", C.constrained(control(actions([("tapped:", "touchUpInside")])), TofuFeatureTests.pin("ctl-aa-aaa", 0, 10, 20)),
         1460, "a9ecd2be51b1eaa8675f88551f75b5d72dc7e105a454a77c34670f57f2d28006"),
        ("act-control-no-event", C.constrained(control(actions([("tapped:", nil)])), TofuFeatureTests.pin("ctl-aa-aaa", 0, 10, 20)),
         1445, "d4e29de2f9f9d096f581ea328d1507a5e99b5d99eff7fc41de09c68e9d6123cb"),
        ("act-to-subview", C.constrained(control() + field(1, 100, actions(changed, to: "ctl-aa-aaa")),
                                         TofuFeatureTests.pin("ctl-aa-aaa", 0, 10, 20) + TofuFeatureTests.pin("tf1-aa-aaa", 1, 16, 100)),
         2633, "ec082c7f6872b502aa7d5ad4430cc4166ac18155c5d78c9bbe9dea527c03a182"),
        ("act-with-outlets", C.constrained(field(1, 100, actions(changed)) + field(2, 200, actions([("alpha:", "editingChanged")])),
                                           TofuFeatureTests.pin("tf1-aa-aaa", 0, 16, 100) + TofuFeatureTests.pin("tf2-aa-aaa", 1, 16, 200))
            .replacingOccurrences(of: owner, with: ownerOutlets), 2750, "832801ed450639ca867d28abcd43b4eed7ac84daf53ebc0ca9ddbf5ffaf66a3f"),
        ("act-to-cell", CellTests.cellXIB(content: "<subviews>\n" + field(1, 0, actions(changed, to: CellTests.cell)) + "</subviews>\n<constraints>\n"
                                          + C.constraint(0, "tf1-aa-aaa", "leading", CellTests.content, "leading", #" constant="16""#)
                                          + C.constraint(1, "tf1-aa-aaa", "top", CellTests.content, "top") + "</constraints>\n", size: (375, 44)),
         3027, "6c3a03376dad3dc18865270a2df3ae7121ca2e8f7525db5d4f28d6fbd977fe02"),
        ("act-button-touch", C.constrained("<button opaque=\"NO\" contentMode=\"scaleToFill\" contentHorizontalAlignment=\"center\" contentVerticalAlignment=\"center\" "
                                           + "buttonType=\"system\" lineBreakMode=\"middleTruncation\" translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"bbb-bb-bb1\">\n"
                                           + "<rect key=\"frame\" x=\"20\" y=\"40\" width=\"75\" height=\"35\"/>\n<state key=\"normal\"/>\n"
                                           + actions([("tapped:", "touchUpInside")]) + "</button>\n", ""),
         1639, "2c5e6cdd278e607c4bd88bb60e87c5a4d16cedb86724f2a4ede34501906e749b"),
        ("act-slider-value", ControlTests.controlXIB("slider", ControlTests.slider + #" value="0.5" minValue="0.0" maxValue="1""#,
                                                     actions([("slid:", "valueChanged")]), size: (118, 31)),
         1084, "2d648e600e0f1374df6f7b9a1e4a90652618d0a45af70230ef6bb3018d3b734c"),
    ]

    /// Event masks by `UIControl.Event`, none without an event; actions after the outlets, by
    /// mask, selector and source; custom controls keep a view's keys; any object of the nib as
    /// the target.
    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(VariationTests.digest(nib) == digest, "\(name)")
    }

    /// `sb-act-controller`: a text field's and a custom control's actions to their controller go
    /// through `UpstreamPlaceholder-1`.
    @Test func compilesStoryboardActionsAsXcode() throws {
        let subviews = "<subviews>\n" + Self.field(1, 100, Self.actions(Self.changed, to: "vc1-aa-aaa"))
            + Self.control(Self.actions([("tapped:", "touchUpInside")], to: "vc1-aa-aaa"))
            + "</subviews>\n"
        let document = SceneTests.storyboard(SceneTests.scene(1, attributes: SceneObjectsTests.custom,
                                                              connections: "<outlet property=\"field\" destination=\"tf1-aa-aaa\" id=\"ou1-aa-aaa\"/>\n")
            .replacingOccurrences(of: "heightSizable=\"YES\"/>\n", with: "heightSizable=\"YES\"/>\n\(subviews)"))
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        for (file, size, digest) in [("UIViewController-vc1-aa-aaa.nib", 978, "7cf456539bb3d232f87d7a07a9ed0535be39c9c78daeb26b04d2e48adcc1879a"),
                                     ("vc1-aa-aaa-view-vw1-aa-aaa.nib", 3151, "14654b65ccf3892617b32b8a1129103ea23a117824982369f9cc93242785d06c")] {
            let data = try #require(compiled[file], "\(file)")
            #expect(data.count == size, "\(file)")
            #expect(VariationTests.digest(data) == digest, "\(file)")
        }
    }

    /// `sb-info-order-graph`: six scenes reached by segues out of document order, whose
    /// Info.plist order is not known (B-266).
    @Test func refusesInfoOrderNotKnown() {
        let ids = [1: "CsM-eh-GAk", 2: "Wvj-7F-Ac9", 3: "QeW-JK-Y40", 4: "uvS-wM-FLZ", 5: "Ee5-aa-aaa", 6: "Ff6-aa-aaa"]
        func scene(_ number: Int, _ attributes: String = "", segues: [(Int, String)] = []) -> String {
            SceneTests.scene(number, attributes: attributes, connections: segues.map { SceneTests.segue($0.0, $0.1, number * 10 + $0.0, "S\(number)\($0.0)") }.joined())
        }
        var document = SceneTests.storyboard(scene(4), scene(6, #" storyboardIdentifier="Six""#), scene(2, segues: [(4, "show")]),
                                             scene(5, #" storyboardIdentifier="Five""#), scene(1, segues: [(2, "show"), (3, "show")]), scene(3, segues: [(5, "presentation")]))
        for (number, id) in ids {
            document = document.replacingOccurrences(of: "vc\(number)-aa-aaa", with: id)
        }
        #expect(throws: NomacError("nomac does not compile segues among scenes whose nib names' Info.plist order depends on an order not known yet (BACKLOG B-266)",
                                   path: "/tmp/Main.storyboard")) {
            try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: StoryboardCompilerTests.options)
        }
    }

    /// `act-field-mixed-no-event`: ibtool keeps one of two actions of a control without an event.
    @Test func refusesTwoActionsWithoutAnEvent() {
        let xib = C.constrained(Self.field(1, 100, Self.actions([("zeta:", nil), ("beta:", nil)])), TofuFeatureTests.pin("tf1-aa-aaa", 0, 16, 100))
        #expect(throws: NomacError("nomac does not compile two actions of a control without an event yet (BACKLOG B-260)", path: "/tmp/View.xib")) {
            try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        }
    }
}
