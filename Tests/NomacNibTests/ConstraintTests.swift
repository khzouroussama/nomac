import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What `ibtool --compile` (Xcode 27.0) writes for constraints, image views, safe areas and views
/// without frames (`.github/scripts/nib_experiments.py` round 15): sizes and SHA-256 digests of
/// Xcode's nibs.
@Suite struct ConstraintTests {
    static let root = "iN0-l3-epB"
    static let safe = "vUN-kp-3ea"
    static let sub = "sss-ss-ss1"
    static let attributes = ["left", "right", "top", "bottom", "leading", "trailing", "width", "height", "centerX", "centerY"]
    static let edges = ["top", "bottom", "leading", "trailing"]
    static let logo = #"<image name="Logo" width="168" height="185"/>"# + "\n"

    static func subview(_ id: String = sub, _ frame: (Double, Double, Double, Double) = (10, 20, 100, 50), tag: String = "view",
                        attributes: String = "", constraints: String = "", rect: Bool = true) -> String {
        let mode = attributes.contains("contentMode=") ? "" : #" contentMode="scaleToFill""#
        var text = "<\(tag)\(mode)\(attributes) translatesAutoresizingMaskIntoConstraints=\"NO\" id=\"\(id)\">\n"
        if rect { text += "<rect key=\"frame\" x=\"\(frame.0)\" y=\"\(frame.1)\" width=\"\(frame.2)\" height=\"\(frame.3)\"/>\n" }
        if !constraints.isEmpty { text += "<constraints>\n\(constraints)</constraints>\n" }
        return text + "</\(tag)>\n"
    }

    static func constraint(_ number: Int, _ first: String?, _ firstAttribute: String, _ second: String? = nil, _ secondAttribute: String? = nil,
                           _ extra: String = "") -> String {
        let firstItem = first.map { " firstItem=\"\($0)\"" } ?? ""
        let secondItem = second.map { " secondItem=\"\($0)\" secondAttribute=\"\(secondAttribute!)\"" } ?? ""
        return "<constraint\(firstItem) firstAttribute=\"\(firstAttribute)\"\(secondItem)\(extra) id=\"c\(String(format: "%02d", number))-aa-aaa\"/>\n"
    }

    static func constrained(_ subviews: String, _ constraints: String, safeArea: Bool = false, resources: String = "", rootRect: Bool = true) -> String {
        var view = "<view contentMode=\"scaleToFill\" id=\"\(root)\">\n"
        if rootRect { view += #"<rect key="frame" x="0" y="0" width="393" height="852"/>"# + "\n" }
        view += #"<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>"# + "\n<subviews>\n\(subviews)</subviews>\n"
        if safeArea { view += "<viewLayoutGuide key=\"safeArea\" id=\"\(safe)\"/>\n" }
        if !constraints.isEmpty { view += "<constraints>\n\(constraints)</constraints>\n" }
        var document = XIBCompilerTests.xib(view + #"<point key="canvasLocation" x="0" y="0"/>"# + "\n</view>\n",
                                            resources: resources.isEmpty ? [] : [resources])
        if safeArea {
            document = document.replacingOccurrences(of: #" colorMatched="YES""#, with: #" useSafeAreas="YES" colorMatched="YES""#)
        }
        return document
    }

    static func pinned(_ item: String, _ first: Int) -> String {
        edges.enumerated().map { constraint(first + $0.offset, item, $0.element, root, $0.element) }.joined()
    }

    static func edgesToSafeArea(mask: Int) -> String {
        edges.enumerated().map { index, attribute in
            let other = mask >> index & 1 == 1 ? safe : root
            return ["top", "leading"].contains(attribute) ? constraint(index, sub, attribute, other, attribute)
                : constraint(index, other, attribute, sub, attribute)
        }.joined()
    }

    static let centered = constraint(5, sub, "centerX", root, "centerX") + constraint(6, sub, "centerY", root, "centerY")
    static let imageView = (112.0, 333.0, 168.0, 185.0)

    static let cases: [(String, String, Int, String)] = [
        ("constraint-all", constrained(subview(), constraint(0, sub, "top", root, "top", #" relation="greaterThanOrEqual" constant="12" multiplier="2" priority="750""#)),
         1243, "8b980138eaf56f4df06788497920fe78664e256223365725a2a79080b614b15b"),
        ("constraint-identifier", constrained(subview(), constraint(0, sub, "top", root, "top", #" identifier="top-spacing""#)),
         1189, "c082a1af8bc2c6d1bfcd4d0a0a1514ac159e6d8eb495bf7be13cde77061dba9e"),
        ("constraint-placeholder", constrained(subview(), constraint(0, sub, "top", root, "top", #" placeholder="YES""#)),
         928, "bd01b787f5cfa0fa2df54c4669e1db54da87986f34b74aad35c046311f91cb54"),
        ("constraint-multiplier-ratio", constrained(subview(), constraint(0, sub, "top", root, "top", #" multiplier="3:2""#)),
         1170, "19f286d64d682043b66171805c82a9d41be9d688923a6038c636f3df4b2b0ea7"),
        ("constraint-third", constrained(subview(), constraint(0, sub, "top", root, "top", #" constant="0.33333333333333331""#)),
         1191, "2cd5a9786b6bf379947fba512bd38bd52f688c7fa0eb565a848a90f0b5ffe751"),
        ("constraint-self-width", constrained(subview(constraints: constraint(0, nil, "width", nil, nil, #" constant="100""#)), ""),
         1128, "6f7352f5da2815024134d6611186fb5f79a578c6a76fe74d839ad97857d85a01"),
        ("constraint-root-height", constrained(subview(), constraint(0, nil, "height", nil, nil, #" constant="852""#)),
         1072, "1764b1dfc603dadf18f8e5422307e4e20f42a4cd8753f57a8e946279b93878b1"),
        ("constraint-to-safe-area", constrained(subview(), constraint(0, sub, "top", safe, "top"), safeArea: true),
         1799, "f4f1078f58bddd1563907b9840f4dbc3313b21af5a3c6ff0a02bc258981d614f"),
        ("safe-area", constrained(subview(), "", safeArea: true), 1065, "226b9876fdef5306bc1651983730adfe73e1459b6da0c15f902486949a9880fd"),
        ("order-sub-root-shuffled", constrained(subview(), zip([8, 3, 1, 4, 7, 0, 9, 6, 2, 5], attributes).map { constraint($0, sub, $1, root, $1) }.joined()),
         1517, "3e0ffbee49cd57e0ce5c9f67191c5e06c707b7cb0473b2612012b3bfe46c2598"),
        ("order-root-sub-ids", constrained(subview(), attributes.enumerated().map { constraint($0.offset, nil, $0.element, sub, $0.element) }.joined()),
         1517, "1ed4681fca19db841f2f28cce43c6c9ffe4f60dddc54452255a5c8bff3196edd"),
        ("order-alternating", constrained(subview(), attributes.enumerated().map { index, attribute in
            index % 2 == 1 ? constraint(index, sub, attribute, root, attribute) : constraint(index, nil, attribute, sub, attribute)
        }.joined()), 1517, "9a1219e1769ddc439bb7219ff8e00b5d4a628a873ef1f4e27383a2f9a42838b6"),
        ("order-sub-safe", constrained(subview(), attributes.enumerated().map { constraint($0.offset, sub, $0.element, safe, $0.element) }.joined(), safeArea: true),
         2178, "f0875f9ec6b144d380caa1821ea746dd18a223cc519a78a7a2be44997c9a79b6"),
        ("order-safe-sub", constrained(subview(), attributes.enumerated().map { constraint($0.offset, safe, $0.element, sub, $0.element) }.joined(), safeArea: true),
         2178, "3d6d8e9658adebfefebe7c5e93615d7279fba06e85d1898793a8af8f3672d5c7"),
        ("order-edges-safe-05", constrained(subview(), edgesToSafeArea(mask: 5), safeArea: true),
         1925, "e57b89c5fd35603d5c241bce9fdacb24bf1709f24a7d042cbbf536d9aad37df3"),
        ("order-edges-safe-12-origin", constrained(subview(sub, (0, 0, 393, 852)), edgesToSafeArea(mask: 12), safeArea: true),
         1925, "f0dddfd734dc7cbb6067be7a388e28e1ffaf0bff83bbceafdc945ea2689081aa"),
        ("order-twice", constrained(subview(), constraint(0, sub, "top", root, "top", #" constant="20""#)
            + constraint(1, sub, "top", root, "top", #" relation="greaterThanOrEqual" constant="10""#)
            + constraint(2, sub, "top", root, "top", #" constant="30" priority="250""#)
            + constraint(3, sub, "top", root, "top", #" relation="lessThanOrEqual" constant="40""#)
            + constraint(4, sub, "leading", root, "leading", #" constant="5""#) + constraint(5, sub, "leading", root, "trailing", #" constant="-5""#)),
         1535, "6363776d0f17b625e9ae61d2f60286cf799cc8b0debcacddc42ed29db17fa9e3"),
        ("order-cross", constrained(subview(), [("top", "bottom"), ("leading", "trailing"), ("bottom", "top"), ("trailing", "leading"),
                                               ("centerX", "leading"), ("width", "height"), ("height", "width"), ("centerY", "top")]
            .enumerated().map { constraint($0.offset, sub, $0.element.0, root, $0.element.1) }.joined()),
         1434, "dc30de289135eb2c91e41dc3a98ff62c8cea084a8a6d19042f6033060e3ae65a"),
        ("order-size-aspect", constrained(subview(constraints: constraint(0, nil, "width", nil, nil, #" constant="100""#)
            + constraint(1, sub, "width", sub, "height", #" multiplier="2:1""#)), centered),
         1336, "e492621f2ac445fc8eff52508a67fd89b7abca7de1de4a8fdb6a73f4f9cd84cc"),
        ("order-size-relations", constrained(subview(constraints: constraint(0, nil, "height", nil, nil, #" relation="greaterThanOrEqual" constant="10""#)
            + constraint(1, nil, "height", nil, nil, #" relation="lessThanOrEqual" constant="90""#) + constraint(2, nil, "height", nil, nil, #" constant="50""#)), centered),
         1394, "989f4653cafef0abbe7bfd29e594fd75f9018cc4077fcfb266c75be5018bc551"),
        ("order-two-below-ab", constrained(subview("aaa-aa-aa1", (10, 200, 100, 50)) + subview("bbb-bb-bb1", (10, 20, 100, 50)),
                                           pinned("aaa-aa-aa1", 0) + pinned("bbb-bb-bb1", 4)),
         1521, "b2dea11562a4914b8d6bb28309ddaf8fb972913fbe6bfe32da4db8950f26db81"),
        ("order-two-same-ba", constrained(subview("bbb-bb-bb1") + subview("aaa-aa-aa1"), pinned("bbb-bb-bb1", 0) + pinned("aaa-aa-aa1", 4)),
         1521, "e0db9cb4a0a5d85538e7bf6f9232f841f904db3709a25fe6c89b28d9dc5d15b6"),
        ("order-three-120", constrained(["aaa-aa-aa1", "bbb-bb-bb1", "ccc-cc-cc1"].enumerated().map { subview($0.element, (10, 20 + 100 * Double($0.offset), 100, 50)) }.joined(),
                                        pinned("bbb-bb-bb1", 0) + pinned("ccc-cc-cc1", 4) + pinned("aaa-aa-aa1", 8)),
         1777, "81a09e17f5e61e1412e732c40b8bfae1bcadfc63bfd7cfbcdaffaaf790f066ae"),
        ("order-guide-and-two", constrained(subview("aaa-aa-aa1") + subview("bbb-bb-bb1", (10, 200, 100, 50)),
                                            pinned("aaa-aa-aa1", 0) + constraint(4, safe, "bottom", "bbb-bb-bb1", "bottom")
                                                + constraint(5, "bbb-bb-bb1", "top", safe, "top"), safeArea: true),
         2098, "d8c57fc0373f241f059f82d25abbbb38c6136c7240e8ec891b29da045ee889cd"),
        ("image-view-common", constrained(subview("iii-ii-ii1", imageView, tag: "imageView",
                                                  attributes: #" userInteractionEnabled="NO" horizontalHuggingPriority="251" verticalHuggingPriority="251" image="Logo""#), "", resources: logo),
         1158, "ac3000e784df7461aa789e9a77beee1b84ac82eccf6744b311e2a280c397c1d7"),
        ("image-view-flutter", constrained(subview("iii-ii-ii1", imageView, tag: "imageView",
                                                   attributes: #" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" image="Logo""#), "", resources: logo),
         1137, "c8b9b79fe776cd3e161c892474caaa568c5d6defdddeff2699c8235352ccaa7d"),
        ("image-view-clears", constrained(subview("iii-ii-ii1", imageView, tag: "imageView", attributes:
            #" clearsContextBeforeDrawing="NO" userInteractionEnabled="NO" contentMode="scaleAspectFit" horizontalHuggingPriority="251" verticalHuggingPriority="251" image="Logo""#),
                                          "", resources: logo), 1206, "88385518e184d556c72484dc210ee9d5fa22daa824932b5fce54115b178c5457"),
        ("image-view-two-hugging", constrained(["iii-ii-ii1", "iii-ii-ii2"].enumerated().map {
            subview($0.element, $0.offset == 0 ? imageView : (10, 20, 168, 185), tag: "imageView",
                    attributes: #" horizontalHuggingPriority="251" verticalHuggingPriority="251" image="Logo""#)
        }.joined(), "", resources: logo), 1227, "9f83eac8237b8aebdaa18e8a7c8d9e62462fde70e18d57425f6d4380c65a941e"),
        ("image-view-name-png", constrained(subview("iii-ii-ii1", imageView, tag: "imageView", attributes: #" image="982-food-toolbar.png""#), "",
                                            resources: #"<image name="982-food-toolbar.png" width="22" height="18"/>"# + "\n"),
         1095, "dbaf7ae5c55a3caf9dad4455b388f7dfcdcaa29557941554615485ef47cfe937"),
        ("image-view-no-image", constrained(subview("iii-ii-ii1", imageView, tag: "imageView"), ""),
         886, "e2008b73490449127a00c08e3d01b8ad4df78823c0a7c140a799369fe7778495"),
        ("image-view-no-rect", constrained(subview("iii-ii-ii1", tag: "imageView", attributes: #" image="Logo""#, rect: false), "", resources: logo),
         1079, "c10762536541e48f6a7f0f4b59d900f3e1827bf556e85722daec77ddb317f3e7"),
        ("image-view-centered", constrained(subview("iii-ii-ii1", imageView, tag: "imageView", attributes: #" image="Logo""#),
                                            constraint(0, "iii-ii-ii1", "centerX", root, "centerX") + constraint(1, "iii-ii-ii1", "centerY", root, "centerY"),
                                            resources: logo), 1395, "c520b03a85d537e04a9b1203a39f6660e1d55b96e25acc6b0a28682011560648"),
        ("view-no-rect", constrained(subview(rect: false), "", rootRect: false), 872, "e2a86fdecb11326f932ce120e551e122c0bec96ed108a0a1c7c64bd8662f4535"),
        ("precise-n255", XIBCompilerTests.xib(XIBCompilerTests.view(color: XIBCompilerTests.rgb("0.0", "0.50980392156862742", "0.78823529411764703", "1"))),
         963, "ad7d1d1f2ae98739927a6b09d7506ff897ff4103ebfafe93046c9db84ff6507c"),
    ]

    @Test(arguments: cases)
    func compilesAsXcode(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/\(name)/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(SHA256.digest(Array(nib)).map { String(format: "%02x", $0) }.joined() == digest, "\(name)")
    }

    static func outside(_ a: (Double, Double, Double, Double), _ b: (Double, Double, Double, Double)) -> String {
        constrained(subview("aaa-aa-aa1", a) + subview("bbb-bb-bb1", b),
                    TofuFeatureTests.pin("aaa-aa-aa1", 0, Int(a.0), Int(a.1)) + TofuFeatureTests.pin("bbb-bb-bb1", 1, Int(b.0), Int(b.1)))
    }

    /// Frames wholly outside the view, on its edges or of no size sort by the distance rule
    /// (round 52, `outside-*`).
    @Test(arguments: [
        ("outside-above-far", outside((16, -108, 343, 100), (0, 120, 20, 20)), 1441, "6bd90f2d0702a9c526f8092cc24a3fbfdc69130041d485b0cb1f5f828aeb53a6"),
        ("outside-bottom-edge-far", outside((0, 852, 393, 50), (300, 800, 20, 20)), 1441, "006fa77a4a9256ce7547638a2e9c34811b727846b8017d016d3195e80fec1c1e"),
        ("outside-zero-height-near", outside((224, 0, 40, 0), (0, 200, 20, 20)), 1421, "d770fa5461bb277bccf1d5433a3ea9f0e6cfa30490af9e4e5dbf01a313bfb48e"),
    ])
    func sortsFramesOutsideByDistance(name: String, xib: String, size: Int, digest: String) throws {
        let nib = try XIBCompiler.compile(Data(xib.utf8), path: "/tmp/View.xib", options: XIBCompilerTests.options)
        #expect(nib.count == size, "\(name)")
        #expect(SHA256.digest(Array(nib)).map { String(format: "%02x", $0) }.joined() == digest, "\(name)")
    }

    /// `precise-*`, `sb-precise-*`: a xib keeps a component's double, a storyboard 10 significant
    /// digits of it.
    @Test func storyboardsRoundComponents() {
        #expect(NibColor.Components.rgb(red: 0, green: 0.50980392156862742, blue: 0.78823529411764703, alpha: 1).significant(10)
                    == .rgb(red: 0, green: 0.5098039216, blue: 0.7882352941, alpha: 1))
        #expect(NibColor.Components.gray(white: 0.058823529411764705, alpha: 0.12345678901234567).significant(10)
                    == .gray(white: 0.05882352941, alpha: 0.123456789))
    }
}
