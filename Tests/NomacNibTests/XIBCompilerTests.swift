import Foundation
import Testing
import NomacCore
@testable import NomacNib

/// What `ibtool --compile` (Xcode 27.0) writes for self-written xibs
/// (`.github/scripts/nib_experiments.py`): sizes and SHA-256 digests of Xcode's nibs.
@Suite struct XIBCompilerTests {
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

        """
    static let tail = "    </objects>\n</document>\n"
    /// The options of every experiment but `deployment-*`, `devices-*` and `*-zed`.
    static let options = XIBCompiler.Options(module: "T", minimumDeploymentTarget: "27.0", targetDevices: ["iphone"])

    static func view(_ attributes: String = "", contentMode: String = "scaleToFill", frame: String = #"x="0" y="0" width="393" height="852""#,
                     mask: String? = #"widthSizable="YES" heightSizable="YES""#, id: String = "iN0-l3-epB", color: String? = nil,
                     subviews: [String] = []) -> String {
        var text = "<view contentMode=\"\(contentMode)\" \(attributes) id=\"\(id)\">\n<rect key=\"frame\" \(frame)/>\n"
        if let mask { text += "<autoresizingMask key=\"autoresizingMask\" \(mask)/>\n" }
        if let color { text += color + "\n" }
        if !subviews.isEmpty { text += "<subviews>\n" + subviews.joined() + "</subviews>\n" }
        return text + "<point key=\"canvasLocation\" x=\"0\" y=\"0\"/>\n</view>\n"
    }

    static func xib(_ objects: String..., resources: [String] = []) -> String {
        let tail = resources.isEmpty ? tail : "    </objects>\n<resources>\n" + resources.joined() + "</resources>\n</document>\n"
        return head + objects.joined() + tail
    }

    static func gray(_ white: String, _ alpha: String) -> String {
        #"<color key="backgroundColor" white="\#(white)" alpha="\#(alpha)" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>"#
    }

    static func rgb(_ red: String, _ green: String, _ blue: String, _ alpha: String) -> String {
        #"<color key="backgroundColor" red="\#(red)" green="\#(green)" blue="\#(blue)" alpha="\#(alpha)" colorSpace="custom" customColorSpace="sRGB"/>"#
    }

    static func system(_ name: String) -> String {
        #"<color key="backgroundColor" systemColor="\#(name)"/>"#
    }

    /// A `<systemColor>` or `<namedColor>` of the document's resources.
    static func resource(_ element: String, _ name: String, _ color: String) -> String {
        "<\(element) name=\"\(name)\">\n" + color.replacingOccurrences(of: #" key="backgroundColor""#, with: "") + "\n</\(element)>\n"
    }

    static func subview(_ attributes: String = "", frame: String = #"x="10" y="10" width="50" height="50""#, id: String = "sub-vi-ew1",
                        color: String? = nil) -> String {
        view(attributes, frame: frame, id: id, color: color)
    }

    static let cases: [(String, String, Int, String)] = [
        ("view", xib(view()), 748, "98a706d2bd8bfb27e933b998222fcc76e85f3dfb2c82172f1feb9fd6f47919f9"),
        ("view-frame", xib(view(frame: #"x="10" y="20" width="100" height="50""#)), 748, "cef7618d1030d27b08994ea670fedad06330edc97b57b98ce8104dd300a1c7a6"),
        ("view-fractional", xib(view(frame: #"x="0.5" y="1.25" width="100.5" height="50.75""#)), 748, "26225f6ed7cff849aa7b4fee72b9809b081d58410baec012022fb15343b0a7a8"),
        ("view-no-mask", xib(view(mask: nil)), 748, "8cc00c1d564fc166d7ea8991147de79108651c5e7aea9770194cf9a3ce5cde16"),
        ("view-mask-flexible-all", xib(view(mask: #"flexibleMinX="YES" widthSizable="YES" flexibleMaxX="YES" flexibleMinY="YES" heightSizable="YES" flexibleMaxY="YES""#)), 748, "7c40ba0f42d04b6a78fb6f96b05aeedb933cdf56d35ae8385cca9ae797dde899"),
        ("view-mask-left", xib(view(mask: #"flexibleMinX="YES""#)), 748, "3497dbc936032a184b17966ee3342d1049c0f6bd86aab06e65cc7591975f3163"),
        ("view-opaque-no", xib(view(#"opaque="NO""#)), 737, "453cc806ff92c1b64aac6890aaf896641b0687a1878196a952bc7d1df55b766a"),
        ("view-semantic", xib(view(#"semanticContentAttribute="forceRightToLeft""#)), 748, "ebc4329ee48fc0ba0a4025badbdf5fc61be91386e29ca9a73aaba637d50fc82d"),
        ("view-custom-class", xib(view(#"customClass="MyView""#)), 824, "5378d2e8c18db05c8163a2a185e16ac0df5c56f7e4d71bc4ab8f503ec6e94b22"),
        ("view-custom-class-module", xib(view(#"customClass="MyView" customModule="T" customModuleProvider="target""#)), 831, "4624019d1ad4f94c0a9ed3ad7b62eba950d681255434f7ac680458b63d7c1fd5"),
        ("two-views", xib(view(), view(frame: #"x="0" y="0" width="10" height="10""#, id: "abc-de-fgh")), 833, "1ef6aef8b459b562299b5f182e045c2cc4445b72d755b9d655e15df2f2ec18ed"),
        ("view-flags-1", xib(view(#"opaque="YES" hidden="YES" tag="3" userInteractionEnabled="NO" multipleTouchEnabled="YES" clipsSubviews="YES" alpha="0.5""#, contentMode: "center")), 870, "4cda3ae04f2eb75b2c267923b823b8b4637a0010c543bd4338ab3ea19124c706"),
        ("view-flags-2", xib(view(#"hidden="YES" multipleTouchEnabled="YES" translatesAutoresizingMaskIntoConstraints="NO" alpha="0.25""#, contentMode: "redraw")), 871, "583031c26e2855f0389c8de1ed063a495ac40199030fc8ca0baf17daa40e82dc"),
        ("view-flags-3", xib(view(#"tag="1" userInteractionEnabled="NO" clipsSubviews="YES" semanticContentAttribute="playback""#, contentMode: "bottomRight")), 820, "44b4bb300288e8651652b5fca416646df07bccaa02b692c6637e112f1e591ce3"),
        ("custom-class-subview", xib(view(#"customClass="Outer""#, subviews: [view(#"customClass="Inner" customModule="T""#, frame: #"x="10" y="10" width="50" height="50""#, id: "sub-vi-ew1")])), 977, "60409b55a39f3b267630f99410c8482046419e498446284f568a39f5bc8e0ed5"),
        ("same-custom-class", xib(view(subviews: [
            view(#"customClass="Same""#, frame: #"x="10" y="10" width="50" height="50""#, id: "sub-vi-ew1"),
            view(#"customClass="Same""#, frame: #"x="1" y="2" width="3" height="4""#, id: "sub-vi-ew2"),
        ])), 1052, "4754a8ecf0b6f53ff30cd7903d3130302de7cb0ba5e22508d5d4e5e31f069be6"),
        ("view-clips", xib(view(#"clipsSubviews="YES""#)), 766, "0e4b2f42cf784e681554fd862de86eb506bad4609f4bd759ab5c3cffbc63b041"),
        ("view-hidden", xib(view(#"hidden="YES""#)), 759, "84710e935694fad5a9351e92c6349bd44155855749b9605818c40bba8f1371d3"),
        ("view-alpha", xib(view(#"alpha="0.5""#)), 762, "6e1c56936cd483b8160649215a54c3ceec3bc92ea49260147d9fb0f897e490c5"),
        ("view-tag", xib(view(#"tag="7""#)), 757, "95341edc144bbd8bcebce2f14dfceee879e0fb0ef24709bad2e14b5fb0cf5b1e"),
        ("view-no-interaction", xib(view(#"userInteractionEnabled="NO""#)), 776, "5012a2f7dce8c8ec0d2c02673e5e2eb897b3aa92ace0399e4d981016f5558af2"),
        ("view-multitouch", xib(view(#"multipleTouchEnabled="YES""#)), 773, "6c5218f9400687add628991c68c2f4b6b4d4063e22fae4b75b33f5e43d8f7e4f"),
        ("view-content-mode", xib(view(contentMode: "center")), 765, "4485824c53d20281440b7ae7fdd5bbfe27211a93695d26c8cbcecd426c0be0f5"),
        ("view-no-autoresize-subviews", xib(view(#"autoresizesSubviews="NO""#)), 725, "0fdc1d591d7531bdbeec05dea2b6e51739f744784fad174c9b7f10e5cd25e3f1"),
        ("view-translates-no", xib(view(#"translatesAutoresizingMaskIntoConstraints="NO""#)), 804, "95716536d54394d2c130f146d15966f4cb59aaf6f1491b8a268725be7a21cd88"),
        ("view-mask-none", xib(view(mask: "")), 726, "1e04924dd1765cb5b4a6f5a6f7bb4afc40d313d8df1235374e84e5196d293aca"),
        ("subview", xib(view(subviews: [view(frame: #"x="10" y="10" width="50" height="50""#, id: "sub-vi-ew1")])), 872, "939f3976cddf1bce13cef3226a1fcc4846a27bd06c3756bea4d380896e84dd0c"),
        ("nested-subviews", xib(view(subviews: [
            view(frame: #"x="10" y="10" width="50" height="50""#, id: "sub-vi-ew1", subviews: [view(frame: #"x="1" y="2" width="3" height="4""#, id: "sub-vi-ew2")]),
            view(frame: #"x="5" y="6" width="7" height="8""#, id: "sub-vi-ew3"),
        ])), 1053, "927d991d951f270b27dffa656255d3a19f04da2346fac967fe41faaee644dd99"),
        ("no-first-responder-class", xib(view()).replacingOccurrences(of: #" customClass="UIResponder""#, with: ""), 748, "98a706d2bd8bfb27e933b998222fcc76e85f3dfb2c82172f1feb9fd6f47919f9"),
        // Two arrays of subviews, one after the other: each is its own object.
        ("sibling-subviews", xib(
            view(subviews: [view(frame: #"x="1" y="1" width="10" height="10""#, id: "aaa-aa-aaa")]),
            view(frame: #"x="0" y="0" width="100" height="100""#, id: "vv2-vv-vv2", subviews: [view(frame: #"x="2" y="2" width="20" height="20""#, id: "bbb-bb-bbb")])),
         1053, "8740b235b05f49dd554bd990e4b5e042f07d7b0bdbd9d1606060d3d5ef20c663"),
        ("nested-siblings", xib(view(subviews: [
            view(frame: #"x="10" y="10" width="50" height="50""#, id: "ss1-ss-ss1", subviews: [view(frame: #"x="1" y="1" width="5" height="5""#, id: "xxx-xx-xxx")]),
            view(frame: #"x="60" y="60" width="50" height="50""#, id: "ss2-ss-ss2", subviews: [view(frame: #"x="2" y="2" width="6" height="6""#, id: "yyy-yy-yyy")]),
        ])), 1149, "e59da58b22a95eb7a49a6ed1287edd734ad1c4b47c53cc9767405235badd11e2"),
        ("owner-custom-class", xib(view()).replacingOccurrences(of: #"id="-1""#, with: #"id="-1" customClass="Owner""#), 748, "98a706d2bd8bfb27e933b998222fcc76e85f3dfb2c82172f1feb9fd6f47919f9"),
    ]

    /// Colors (`gray-*`, `rgb-*`, `system-*`, `systemColor-*`, `cocoa-*`, `named-color`,
    /// `same-*`, `color-key-*`, `two-system-colors`, `rgb-then-same-gray`): components that a
    /// float does not hold, key tables that grow while a color is written or when the empty key
    /// is counted (34 keys in 71 buckets), and a subview whose
    /// `translatesAutoresizingMaskIntoConstraints="NO"` is ignored.
    static let colorCases: [(String, String, Int, String)] = [
        ("gray-0-1", xib(view(color: gray("0", "1"))), 920, "a04c96734d5d950e9cd87356d61ab687c0bfe8d1af37e3302959066e59ae1142"),
        ("gray-0.5-0.5", xib(view(color: gray("0.5", "0.5"))), 886, "7ca18952d9fa0789f52c1f40d1587fb06cf1798c53606192862d69be7396d9a1"),
        ("gray-1-0.6", xib(view(color: gray("1", "0.6"))), 909, "5159f75f5766bc172bc4c30d73ea8e23fc0231e73f7f82be1bbdce2e7d7e2ee6"),
        ("rgb-0.2-0.4-0.6-1", xib(view(color: rgb("0.2", "0.4", "0.6", "1"))), 985, "930a761595b9c026bc7fb0320548af81d7fee3b5d82dffe891b8636eec5cffd5"),
        ("rgb-0.12345678901234568-0.5-0.9876543209876543-0.8", xib(view(color: rgb("0.12345678901234568", "0.5", "0.9876543209876543", "0.8"))), 993,
         "8d1c967e5c57e33cfa4499648911bae11804f37cc5026b0d27cda94f9e34db8c"),
        ("rgb-1-0-0-1", xib(view(color: rgb("1", "0", "0", "1"))), 907, "f8611842477bda272373ac07f43c2339cd3009f92df3d274dc57716f8afdd4ae"),
        ("system-red", xib(view(color: system("systemRedColor")), resources: [resource("systemColor", "systemRedColor",
                                                                                         rgb("1", "0.23137254901960785", "0.18823529411764706", "1"))]),
         1007, "bb31320bf5140ca05d738be11070526f0320cbded64314b1b60193875a9f130d"),
        ("systemColor-placeholderTextColor", xib(view(color: system("placeholderTextColor")), resources: [resource("systemColor", "placeholderTextColor", gray("0", "1"))]),
         1072, "78fdf9d0306d1eac8e427d7428ab036cea90de5b47b47d7bbe69d6b1d4e7a951"),
        ("cocoa-group-background", xib(view(color: #"<color key="backgroundColor" cocoaTouchSystemColor="groupTableViewBackgroundColor"/>"#)), 1050,
         "9534e0e510308c39b418a7d3dfa8a7eb6c8c98a0a0251f567f46407014171574"),
        ("named-color", xib(view(color: #"<color key="backgroundColor" name="Brand"/>"#), resources: [resource("namedColor", "Brand", rgb("0.2", "0.4", "0.6", "1"))]),
         1054, "459e8c86290f7ffae657968310b6d4b5b39f2b6715ae58020cff24ce53ab024d"),
        ("same-color-twice", xib(view(color: rgb("0.2", "0.4", "0.6", "1"), subviews: [subview(color: rgb("0.2", "0.4", "0.6", "1"))])), 1115,
         "3f9e9f480330626b46e31ea993abb288b1d5ef453db8079c64f5ab1ee03192b5"),
        ("same-system-color-twice", xib(view(color: system("systemRedColor"), subviews: [subview(color: system("systemRedColor"))]),
                                        resources: [resource("systemColor", "systemRedColor", gray("0", "1"))]),
         1137, "2d1cb965b229e9dce1b5216f33dd94cdc435ae4db7126aa447e92632256c0685"),
        ("view-background-and-subview", xib(view(color: rgb("1", "0.5", "0.25", "1"), subviews: [subview()])), 1036,
         "9eb3b8db4e7342268ca6912d20bf1ab927f42e5321bf47d36c551c889524ffa0"),
        ("color-key-outer-alpha-1-0", xib(view(color: rgb("1", "0.5", "0.25", "0.8"), subviews: [subview(#"hidden="YES""#)])), 1076,
         "8c96387a069c1c454b314672caf4cb4e9e75d2a1adecb57fbf42fe8de0840aaa"),
        ("color-key-outer-gray-3-4", xib(view(color: gray("0.5", "1"), subviews: [
            subview(#"userInteractionEnabled="NO" multipleTouchEnabled="YES" translatesAutoresizingMaskIntoConstraints="NO""#),
        ])), 1059, "75035e6fee50d499cbc6b12086abaf8ec2bf0d0d265d11cde18d79f09561d6f3"),
        ("two-system-colors", xib(view(color: system("systemBlueColor"), subviews: [subview(frame: #"x="1" y="1" width="10" height="10""#, color: system("systemRedColor"))]),
                                  resources: [resource("systemColor", "systemBlueColor", gray("0", "1")), resource("systemColor", "systemRedColor", gray("0", "1"))]),
         1219, "2b86ae7cbc5f8ccf4ed0401e21dde3deddcecf2479ff91fd2a58cd3fa56ddfa6"),
        ("cw-0.66666666666666663-1", xib(view(color: #"<color key="backgroundColor" white="0.66666666666666663" alpha="1" colorSpace="calibratedWhite"/>"#)),
         884, "9bc573303e9ebe691766ad0e19ec4545ef07b8aa8bc6fae73946ed64c4b5087d"),
        ("cw-1-1", xib(view(color: #"<color key="backgroundColor" white="1" alpha="1" colorSpace="calibratedWhite"/>"#)),
         920, "42350c46188e46a9e945d5646ee5aef9ca6fc505f27595bf2a35adeb06b71a54"),
        ("cw-custom-1-1", xib(view(color: #"<color key="backgroundColor" white="1" alpha="1" colorSpace="custom" customColorSpace="calibratedWhite"/>"#)),
         920, "42350c46188e46a9e945d5646ee5aef9ca6fc505f27595bf2a35adeb06b71a54"),
        ("x11-system-background", xib(view(color: #"<color key="backgroundColor" xcode11CocoaTouchSystemColor="systemBackgroundColor" cocoaTouchSystemColor="whiteColor"/>"#)),
         931, "ed87933165963877f4d014bfd49a4e6f2e64535dc5809adc8caea65bd1d22963"),
        ("unmatched-cw-0.5", xib(view(color: #"<color key="backgroundColor" white="0.5" alpha="1" colorSpace="custom" customColorSpace="calibratedWhite"/>"#))
            .replacingOccurrences(of: #" colorMatched="YES""#, with: ""), 913, "a7f8720311bda932b0d4ffe22e99c3267f4f47169df17707721e8d369d578555"),
        ("unmatched-cw-1", xib(view(color: #"<color key="backgroundColor" white="1" alpha="1" colorSpace="custom" customColorSpace="calibratedWhite"/>"#))
            .replacingOccurrences(of: #" colorMatched="YES""#, with: ""), 907, "26966cbd11fe8f09b57921de25492865fe581d30b1a8969a75bced0d1ff37971"),
        ("color-key-outer-rgb-2-4", xib(view(color: rgb("0.2", "0.4", "0.6", "1"), subviews: [
            subview(#"userInteractionEnabled="NO" multipleTouchEnabled="YES""#),
        ])), 1162, "a4a41dc1728f234aa03bad47f4dde091e7cab434028924102bc9cda9af2e38ab"),
        ("rgb-then-same-gray", xib(view(subviews: [
            subview(frame: #"x="1" y="1" width="10" height="10""#, color: rgb("1", "0", "0", "1")),
            subview(frame: #"x="2" y="2" width="10" height="10""#, id: "sub-vi-ew2", color: gray("0.5", "1")),
            subview(frame: #"x="3" y="3" width="10" height="10""#, id: "sub-vi-ew3", color: gray("0.5", "1")),
        ])), 1256, "975ebe591479ab71acbc245cd6df41aab04009dae28aeb286b9b671c16287485"),
    ]

    @Test(arguments: cases + colorCases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/\(name)/View.xib", options: Self.options)
        #expect(nib.count == size, "\(name)")
        #expect(SHA256.digest(Array(nib)).map { String(format: "%02x", $0) }.joined() == digest, "\(name)")
    }

    /// The simplest nib, structurally: header fields, the `LNE` trailer, the class table.
    /// `provider-target-*`, `module-without-provider-*`: the class name each module setting gives.
    @Test(arguments: [
        (#"customModule="Other" customModuleProvider="target""#, "T", "_TtC1T6MyView"),
        (#"customModuleProvider="target""#, "T", "_TtC1T6MyView"),
        (#"customModule="Other""#, "T", "_TtC5Other6MyView"),
        (#"customModule="Other" customModuleProvider="target""#, "Zed", "_TtC3Zed6MyView"),
        (#"customModule="Other""#, "Zed", "_TtC5Other6MyView"),
    ])
    func customClassModules(attributes: String, module: String, className: String) throws {
        let nib = try XIBCompiler.compile(Data(Self.xib(Self.view(#"customClass="MyView" "# + attributes)).utf8), path: "/tmp/View.xib",
                                         options: XIBCompiler.Options(module: module, minimumDeploymentTarget: "27.0", targetDevices: ["iphone"]))
        for name in ["_TtC1T6MyView", "_TtC3Zed6MyView", "_TtC5Other6MyView"] {
            #expect((nib.range(of: Data(name.utf8)) != nil) == (name == className), "\(attributes) --module \(module)")
        }
    }

    @Test func archiveLayout() throws {
        let nib = Array(try XIBCompiler.compile(Data(Self.xib(Self.view()).utf8), path: "/tmp/View.xib", options: Self.options))
        #expect(Array(nib.prefix(10)) == Array("NIBArchive".utf8))
        let fields = (0..<10).map { index in (0..<4).reduce(0) { $0 | Int(nib[10 + index * 4 + $1]) << ($1 * 8) } }
        #expect(fields == [1, 10, 9, 50, 20, 77, 29, 484, 5, 687])
        #expect(Array(nib.suffix(4)) == Array("LNE".utf8) + [0])
        #expect(Array(nib[687..<698]) == [0x89, 0x80] + Array("NSObject".utf8) + [0])
    }

    /// `tag-*`: the size of each integer, as a view's tag.
    @Test(arguments: [
        (127, [0, 127]), (128, [1, 128, 0]), (32767, [1, 0xFF, 0x7F]), (32768, [2, 0, 0x80, 0, 0]),
        (2_147_483_647, [2, 0xFF, 0xFF, 0xFF, 0x7F]), (2_147_483_648, [3, 0, 0, 0, 0x80, 0, 0, 0, 0]),
        (-1, [3, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]), (-128, [3, 0x80, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]),
    ] as [(Int, [UInt8])])
    func integerSizes(value: Int, encoded: [UInt8]) {
        #expect(NibArchive.encoded(.integer(value)) == encoded)
    }

    @Test func varints() {
        #expect(NibArchive.varint(0) == [0x80])
        #expect(NibArchive.varint(20) == [0x94])
        #expect(NibArchive.varint(300) == [0x2C, 0x82])
    }

    /// Every input outside what the experiments observed is refused, naming its BACKLOG item.
    @Test(arguments: [
        (xib(view()).replacingOccurrences(of: #"useAutolayout="YES""#, with: #"useAutolayout="NO""#), "useAutolayout=\"NO\"", "B-260"),
        (xib(view()).replacingOccurrences(of: "retina6_12", with: "ipad10_2"), "id=\"ipad10_2\" in <device>", "B-260"),
        (xib(view()).replacingOccurrences(of: "documents saved in the Xcode 8 format", with: "Pointer interactions"), "name=\"Pointer interactions\" in <capability>", "B-260"),
        (xib(view()).replacingOccurrences(of: "IBFilesOwner", with: "IBOther"), "the placeholder IBOther", "B-260"),
        (xib(view()).replacingOccurrences(of: #"id="-2""#, with: #"id="-2" sceneMemberID="firstResponder""#), "the sceneMemberID attribute of <placeholder>", "B-260"),
        (xib(view(#"accessibilityIgnoresInvertColors="YES""#)), "the accessibilityIgnoresInvertColors attribute of <view>", "B-260"),
        (xib(view(#"customClass="MyView" customModuleProvider="other""#)), "customModuleProvider=\"other\"", "B-260"),
    ])
    func refusesUnobservedDocuments(document: String, what: String, item: String) {
        #expect(throws: NomacError("nomac does not compile \(what) yet (BACKLOG \(item))", path: "/tmp/View.xib")) {
            try XIBCompiler.compile(Data(document.utf8), path: "/tmp/View.xib", options: Self.options)
        }
    }

    /// `deployment-7.0` writes a `~iphone.nib` bundle; other unobserved targets and devices are refused too.
    @Test(arguments: [
        ("7.0", ["iphone"], "nibs for --minimum-deployment-target 7.0"),
        ("16.8", ["iphone"], "nibs for --minimum-deployment-target 16.8"),
        ("27.0", ["iphone", "iphone"], "nibs for --target-device iphone, iphone"),
        ("27.0", ["watch"], "nibs for --target-device watch"),
    ])
    func refusesUnobservedOptions(deployment: String, devices: [String], what: String) {
        let options = XIBCompiler.Options(module: "T", minimumDeploymentTarget: deployment, targetDevices: devices)
        #expect(throws: NomacError("nomac does not compile \(what) yet (BACKLOG B-263)", path: "/tmp/View.xib")) {
            try XIBCompiler.compile(Data(Self.xib(Self.view()).utf8), path: "/tmp/View.xib", options: options)
        }
    }

    /// The header, device and option values observed to give the same nib as `view`.
    @Test(arguments: [
        (xib(view()).replacingOccurrences(of: #"toolsVersion="23504""#, with: #"toolsVersion="17701""#), "27.0", ["iphone"]),
        (xib(view()).replacingOccurrences(of: #"colorMatched="YES">"#, with: #"useSafeAreas="YES" colorMatched="YES">"#), "27.0", ["iphone"]),
        (xib(view()).replacingOccurrences(of: #"appearance="light""#, with: #"appearance="dark""#), "15.0", ["iphone", "ipad"]),
        (xib(view()).replacingOccurrences(of: #"id="-1" userLabel"#, with: #"id="-1" customClass="Owner" customModule="T" customModuleProvider="target" userLabel"#), "17.6", ["ipad"]),
    ])
    func observedVariationsChangeNothing(document: String, deployment: String, devices: [String]) throws {
        let options = XIBCompiler.Options(module: "T", minimumDeploymentTarget: deployment, targetDevices: devices)
        let nib = try XIBCompiler.compile(Data(document.utf8), path: "/tmp/View.xib", options: options)
        #expect(SHA256.digest(Array(nib)).map { String(format: "%02x", $0) }.joined() == "98a706d2bd8bfb27e933b998222fcc76e85f3dfb2c82172f1feb9fd6f47919f9")
    }

    /// `calibrated-rgb`, `display-p3`: ibtool converts these with color management, and so it does
    /// a `calibratedWhite` value not observed.
    @Test(arguments: [
        (#"<color key="backgroundColor" white="0.25" alpha="1" colorSpace="calibratedWhite"/>"#, "the calibratedWhite 0.25"),
        (#"<color key="backgroundColor" red="0.2" green="0.4" blue="0.6" alpha="1" colorSpace="calibratedRGB"/>"#, "the calibratedRGB color 0.2 0.4 0.6"),
        (#"<color key="backgroundColor" red="1" green="0" blue="0" alpha="1" colorSpace="custom" customColorSpace="displayP3"/>"#, "the displayP3 color 1 0 0"),
    ])
    func refusesUnobservedColorSpaces(color: String, what: String) {
        #expect(throws: NomacError("nomac does not compile \(what) yet (BACKLOG B-281)", path: "/tmp/View.xib")) {
            try XIBCompiler.compile(Data(Self.xib(Self.view(color: color)).utf8), path: "/tmp/View.xib", options: Self.options)
        }
    }

    /// `unmatched-grid-calibratedRGB`, `unmatched-rgb-digits`: without `colorMatched`, `calibratedRGB`
    /// components are written as sRGB ones, unconverted.
    @Test func writesCalibratedComponentsUnconvertedWithoutColorMatching() throws {
        func nib(_ color: String) throws -> Data {
            let document = Self.xib(Self.view(color: color)).replacingOccurrences(of: #" colorMatched="YES""#, with: "")
            return try XIBCompiler.compile(Data(document.utf8), path: "/tmp/View.xib", options: Self.options)
        }
        let components = #"red="0.25" green="0.5" blue="0.75" alpha="1""#
        let calibrated = try nib(#"<color key="backgroundColor" \#(components) colorSpace="calibratedRGB"/>"#)
        let srgb = try XIBCompiler.compile(Data(Self.xib(Self.view(color: #"<color key="backgroundColor" \#(components) colorSpace="custom" customColorSpace="sRGB"/>"#)).utf8),
                                           path: "/tmp/View.xib", options: Self.options)
        #expect(calibrated == srgb)
    }

    /// `system-components-*`: a `systemColor`'s components change nothing.
    @Test func ignoresTheComponentsOfASystemColor() throws {
        func nib(_ color: String) throws -> Data {
            try XIBCompiler.compile(Data(Self.xib(Self.view(color: color)).utf8), path: "/tmp/View.xib", options: Self.options)
        }
        let plain = try nib(#"<color key="backgroundColor" systemColor="secondaryLabelColor"/>"#)
        #expect(try nib(#"<color key="backgroundColor" systemColor="secondaryLabelColor" red="0.2" green="0.4" blue="0.6" alpha="0.7" colorSpace="custom" customColorSpace="sRGB"/>"#) == plain)
        #expect(try nib(#"<color key="backgroundColor" systemColor="secondaryLabelColor" red="0.9" green="0.1" blue="0.3" alpha="0.5" colorSpace="calibratedRGB"/>"#) == plain)
    }

    /// `unmatched-gray-0.5`: without `colorMatched`, ibtool converts a generic gray with color
    /// management.
    @Test func refusesConvertedColorsWithoutColorMatching() {
        let document = Self.xib(Self.view(color: Self.gray("0.5", "1"))).replacingOccurrences(of: #" colorMatched="YES""#, with: "")
        #expect(throws: NomacError(#"nomac does not compile this color in a document without colorMatched="YES" yet (BACKLOG B-281)"#, path: "/tmp/View.xib")) {
            try XIBCompiler.compile(Data(document.utf8), path: "/tmp/View.xib", options: Self.options)
        }
    }

}
