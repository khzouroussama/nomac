import Foundation
import NomacCore
import Testing
@testable import NomacNib

/// What `ibtool --compilation-directory` (Xcode 27.0) writes for self-written storyboards
/// (`.github/scripts/nib_experiments.py` STORYBOARDS): sizes and SHA-256 digests of the files of
/// Xcode's `.storyboardc`.
@Suite struct StoryboardCompilerTests {
    static let safeAreaCapability = #"<capability name="Safe area layout guides" minToolsVersion="9.0"/>"#

    static func storyboard(_ scene: String, attributes: String = "", device: String? = #"<device id="retina6_12" orientation="portrait" appearance="light"/>"#,
                           capabilities: String = "") -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="BYZ-38-t0r"\(attributes)>
            \(device ?? "")
            <dependencies>
                <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
                <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
                \(capabilities)
            </dependencies>
            <scenes>
        \(scene)    </scenes>
        </document>

        """
    }

    static func scene(attributes: String = "", guides: String = "", viewAttributes: String = "", viewChildren: String = "",
                      frame: String = #"width="393" height="852""#) -> String {
        """
                <scene sceneID="tne-QT-ifu">
                    <objects>
                        <viewController id="BYZ-38-t0r"\(attributes) sceneMemberID="viewController">
        \(guides)                    <view key="view" contentMode="scaleToFill"\(viewAttributes) id="8bC-Xf-vdC">
                                <rect key="frame" x="0.0" y="0.0" \(frame)/>
                                <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
        \(viewChildren)                    </view>
                        </viewController>
                        <placeholder placeholderIdentifier="IBFirstResponder" id="dkx-z0-nzr" sceneMemberID="firstResponder"/>
                    </objects>
                    <point key="canvasLocation" x="0" y="0"/>
                </scene>

        """
    }

    static let options = XIBCompiler.Options(module: "T", minimumDeploymentTarget: "27.0", targetDevices: ["iphone"])

    static let view = ("BYZ-38-t0r-view-8bC-Xf-vdC.nib", 1701, "049be9c5b429b28c1f71eea25171cb7965fdc08e25309c3d4c0acc1c04489f4a")
    static let info = ("Info.plist", 258, "3e9bdaa408d1eb6ae5e989b813a8644e0a4a981202c536905de52a7291e69aa4")
    static let controller = ("UIViewController-BYZ-38-t0r.nib", 924, "b69dd7e3a282f29506304007dbec6a966adaf07712cbb248f0b29e5691e2bebf")

    static let cases: [(String, String, [(String, Int, String)])] = [
        ("storyboard", storyboard(scene()), [view, info, controller]),
        ("sb-custom-class", storyboard(scene(attributes: #" customClass="ViewController" customModule="T" customModuleProvider="target""#)),
         [view, info, ("UIViewController-BYZ-38-t0r.nib", 952, "4c111bc823cd58879cad26c0017edf307b53eabe129bd700c6337eec1c9f10a2")]),
        ("sb-custom-class-plain", storyboard(scene(attributes: #" customClass="ViewController""#)),
         [view, info, ("UIViewController-BYZ-38-t0r.nib", 944, "97cf075eeacce839f6baa5c6745d24257ba923f55ca5df429cba4476d5da94ad")]),
        ("sb-identifier", storyboard(scene(attributes: #" storyboardIdentifier="Detail""#)),
         [view, ("Detail.nib", 965, "8ac3f3715a297264b2ef532c0a8b149cbf12cf3f12e2d906843cbdfdfba7abcf"),
          ("Info.plist", 181, "fa026c92afe9c5b8c11b9f2d25c77245721f52d959ded4e260d6f3deff465f3f")]),
        ("sb-layout-guides", storyboard(scene(guides: """
                                <layoutGuides>
                                    <viewControllerLayoutGuide type="top" id="Llm-lL-Icb"/>
                                    <viewControllerLayoutGuide type="bottom" id="xb3-aO-Qok"/>
                                </layoutGuides>

            """)), [view, info, controller]),
        ("sb-launch-screen", storyboard(scene(), attributes: #" launchScreen="YES""#), [view, info, controller]),
        ("sb-subview", storyboard(scene(viewChildren: """
                                <subviews>
                                    <view contentMode="scaleToFill" id="sub-vi-ew1">
                                        <rect key="frame" x="10" y="10" width="50" height="50"/>
                                        <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
                                    </view>
                                </subviews>

            """)), [("BYZ-38-t0r-view-8bC-Xf-vdC.nib", 1789, "8454f2295b584cae1dc95e035042943ef4849f097ac88920e5fe677e6248c0ba"), info, controller]),
        ("sb-view-custom-class", storyboard(scene(viewAttributes: #" customClass="SKView""#)),
         [("BYZ-38-t0r-view-8bC-Xf-vdC.nib", 1788, "92f598d6d48a8be3a343c39dfd6362a93cb1af75e147247eead9ebfc39df8808"), info, controller]),
        ("sb-view-multitouch", storyboard(scene(viewAttributes: #" multipleTouchEnabled="YES""#)),
         [("BYZ-38-t0r-view-8bC-Xf-vdC.nib", 1727, "5d7bb2c744b1275264bef670ca7c406069c5547d15b402365ae780ce10ea8a3c"), info, controller]),
        ("sb-background-rgb", storyboard(scene(viewChildren: black + "\n")),
         [("BYZ-38-t0r-view-8bC-Xf-vdC.nib", 1863, "45fabead7f2fdc13c2f493427bc254dfddca0c97c3b9bee2c67e10de72677487"), info, controller]),
        ("sb-safe-area", storyboard(scene(viewChildren: safeArea), attributes: #" useSafeAreas="YES""#, capabilities: safeAreaCapability),
         [("BYZ-38-t0r-view-8bC-Xf-vdC.nib", 1042, "7522ccbbfc02678f7f3384681147816fde73f8b8f3a3cfe5d84be0587ed878c8"), info, controller]),
        ("sb-game", storyboard(scene(attributes: #" customClass="GameViewController" customModule="T" customModuleProvider="target""#,
                                     viewAttributes: #" multipleTouchEnabled="YES" customClass="SKView""#, viewChildren: black + "\n" + safeArea),
                               attributes: #" useSafeAreas="YES""#, capabilities: safeAreaCapability),
         [("BYZ-38-t0r-view-8bC-Xf-vdC.nib", 1302, "8b136bf6651470e6b95929ec5e8ac028c415487d12552f563943c69a89795010"), info,
          ("UIViewController-BYZ-38-t0r.nib", 956, "61d3fbe546e7fd584091a71e383e998ac27eb03ecd5c8094eab4342c52297419")]),
        ("sb-device-retina4_7", storyboard(scene(), device: #"<device id="retina4_7" orientation="portrait" appearance="light"/>"#),
         [("BYZ-38-t0r-view-8bC-Xf-vdC.nib", 1701, "7b4ff2f71fef9e5a87ecc4c6441416a814e12247785cb3ab0737ac8dfcee1444"), info, controller]),
        ("sb-landscape", storyboard(scene(), device: #"<device id="retina6_12" orientation="landscape" appearance="light"/>"#),
         [("BYZ-38-t0r-view-8bC-Xf-vdC.nib", 1701, "51d0f66e255ecaa1a372263bc98f6b2bc7093987baa6d165ce5bf3a7aa7c9441"), info, controller]),
        ("sb-device-subview-both", storyboard(scene(viewChildren: subview(#"flexibleMinX="YES" widthSizable="YES" flexibleMaxY="YES""#)),
                                              device: #"<device id="retina4_7" orientation="portrait" appearance="light"/>"#),
         [("BYZ-38-t0r-view-8bC-Xf-vdC.nib", 1789, "2c991bfb7d12af7157d423b418dec6d8f309556701a655484c5dacf555519099"), info, controller]),
        ("sb-no-device-frame", storyboard(scene(frame: #"width="320" height="480""#), device: nil),
         [("BYZ-38-t0r-view-8bC-Xf-vdC.nib", 1701, "2628358080bcc0d74c6fa87fefeca84ea6fe55cf854ea466155f7e17b14e5f61"), info, controller]),
        ("sb-system-version", storyboard(scene(), attributes: #" systemVersion="15C50""#), [view, info, controller]),
        ("sb-first-responder-class", storyboard(scene()).replacingOccurrences(of: #"id="dkx-z0-nzr""#, with: #"id="dkx-z0-nzr" customClass="UIResponder""#),
         [view, info, controller]),
        ("sb-unmatched-cw-1", storyboard(scene(viewChildren: #"<color key="backgroundColor" white="1" alpha="1" colorSpace="custom" customColorSpace="calibratedWhite"/>"# + "\n"))
            .replacingOccurrences(of: #" colorMatched="YES""#, with: ""),
         [("BYZ-38-t0r-view-8bC-Xf-vdC.nib", 1863, "fc62f13acf7ad3eb9949c04057865e1cdbc0186f045d04d40937aa1150b27847"), info, controller]),
    ]

    static let black = #"<color key="backgroundColor" red="0" green="0" blue="0" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>"#
    static let safeArea = "<viewLayoutGuide key=\"safeArea\" id=\"6Tk-OE-BBY\"/>\n"

    static func subview(_ mask: String, width: Int = 50) -> String {
        """
        <subviews>
        <view contentMode="scaleToFill" id="sub-vi-ew1">
        <rect key="frame" x="10" y="10" width="\(width)" height="50"/>
        <autoresizingMask key="autoresizingMask" \(mask)/>
        </view>
        </subviews>

        """
    }

    @Test(arguments: cases)
    func compilesAsXcode(name: String, document: String, files: [(String, Int, String)]) throws {
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/\(name)/Main.storyboard", options: Self.options)
        #expect(compiled.keys.sorted() == files.map(\.0).sorted(), "\(name)")
        for (file, size, digest) in files {
            let data = try #require(compiled[file], "\(name) \(file)")
            #expect(data.count == size, "\(name) \(file)")
            #expect(SHA256.digest(Array(data)).map { String(format: "%02x", $0) }.joined() == digest, "\(name) \(file)")
        }
    }

    /// Scenes without a `<device>` (their frame 375 x 667) take 600 x 600 when deployed before 17.0,
    /// their subviews resized as for a device; a declared device wins (`sb-deployment-*`).
    static let noDevice = storyboard(scene(frame: #"width="375" height="667""#), device: nil)
    static let deploymentCases: [(String, String, String, [(String, Int, String)])] = [
        ("sb-deployment-11.0-no-device", "11.0", noDevice,
         [("BYZ-38-t0r-view-8bC-Xf-vdC.nib", 1701, "4cc36030663e379d1ed734ee91dbdb44d24b075f9cf8556b48422d3d4ef10f4f"), info, controller]),
        ("sb-deployment-16.6-no-device", "16.6", noDevice,
         [("BYZ-38-t0r-view-8bC-Xf-vdC.nib", 1701, "4cc36030663e379d1ed734ee91dbdb44d24b075f9cf8556b48422d3d4ef10f4f"), info, controller]),
        ("sb-deployment-17.0-no-device", "17.0", noDevice,
         [("BYZ-38-t0r-view-8bC-Xf-vdC.nib", 1701, "7b4ff2f71fef9e5a87ecc4c6441416a814e12247785cb3ab0737ac8dfcee1444"), info, controller]),
        ("sb-deployment-11.0-retina4_7", "11.0", storyboard(scene(), device: #"<device id="retina4_7" orientation="portrait" appearance="light"/>"#),
         [("BYZ-38-t0r-view-8bC-Xf-vdC.nib", 1701, "7b4ff2f71fef9e5a87ecc4c6441416a814e12247785cb3ab0737ac8dfcee1444"), info, controller]),
        ("sb-deployment-11.0-safe-area-subview", "11.0",
         storyboard(scene(viewChildren: subview(#"widthSizable="YES" flexibleMaxY="YES""#) + safeArea, frame: #"width="375" height="667""#),
                    attributes: #" useSafeAreas="YES""#, device: nil, capabilities: safeAreaCapability),
         [("BYZ-38-t0r-view-8bC-Xf-vdC.nib", 1166, "4b416fd847162800eea7696082718cf8726ae6af3a1325f175abdfbc0f01f5c4"), info, controller]),
    ]

    @Test(arguments: deploymentCases)
    func sizesScenesByDeploymentTarget(name: String, deployment: String, document: String, files: [(String, Int, String)]) throws {
        let options = XIBCompiler.Options(module: "T", minimumDeploymentTarget: deployment, targetDevices: ["iphone"])
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/\(name)/Main.storyboard", options: options)
        for (file, size, digest) in files {
            let data = try #require(compiled[file], "\(name) \(file)")
            #expect(data.count == size, "\(name) \(file)")
            #expect(SHA256.digest(Array(data)).map { String(format: "%02x", $0) }.joined() == digest, "\(name) \(file)")
        }
    }

    /// The corpus's launch-screen shapes (`sb-image-view*`, `sb-flutter-launch-*`, `sb-no-traits-*`,
    /// `sb-safe-area-layout-guides`, `sb-precise-n255`): an image view centered by constraints;
    /// flutter's, without a device or frames, is 600 x 600 before 17.0 with trait collections,
    /// 393 x 852 without, and 1000 x 1000 from 17.0; a storyboard keeps 10 digits of a component.
    static let launchGuides = """
                            <layoutGuides>
                                <viewControllerLayoutGuide type="top" id="Llm-lL-Icb"/>
                                <viewControllerLayoutGuide type="bottom" id="xb3-aO-Qok"/>
                            </layoutGuides>

        """
    static func imageScene(rect: Bool = true, safeArea: Bool = false, other: String = "8bC-Xf-vdC") -> String {
        """
                                <subviews>
                                    <imageView opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" image="LaunchImage" translatesAutoresizingMaskIntoConstraints="NO" id="YRO-k0-Ey4">
                                        \(rect ? #"<rect key="frame" x="112.5" y="333.5" width="168" height="185"/>"# : "")
                                    </imageView>
                                </subviews>
                                <color key="backgroundColor" red="1" green="1" blue="1" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
                                \(safeArea ? Self.safeArea : "")
                                <constraints>
                                    <constraint firstItem="YRO-k0-Ey4" firstAttribute="centerX" secondItem="\(other)" secondAttribute="centerX" id="1a2-6s-vTC"/>
                                    <constraint firstItem="YRO-k0-Ey4" firstAttribute="centerY" secondItem="\(other)" secondAttribute="centerY" id="4X2-HB-R7a"/>
                                </constraints>

        """
    }
    static func launch(_ scene: String, attributes: String = "", device: String? = #"<device id="retina6_12" orientation="portrait" appearance="light"/>"#,
                       capabilities: String = "") -> String {
        storyboard(scene, attributes: attributes, device: device, capabilities: capabilities)
            .replacingOccurrences(of: "    </scenes>\n", with: "    </scenes>\n<resources>\n<image name=\"LaunchImage\" width=\"168\" height=\"185\"/>\n</resources>\n")
    }
    static let flutter = launch(scene(guides: launchGuides, viewChildren: imageScene(rect: false)), device: nil)
        .replacingOccurrences(of: #"<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>"#, with: "")
    static let launchCases: [(String, String, [String], String, (Int, String))] = [
        ("sb-image-view", "27.0", ["iphone"], launch(scene(guides: launchGuides, viewChildren: imageScene())),
         (2309, "2823fb4b8f1b43bae198bf04340018222cda5b80513f04772a16a1c57252bd59")),
        ("sb-image-view-safe-area", "27.0", ["iphone"], launch(scene(viewChildren: imageScene(safeArea: true, other: "6Tk-OE-BBY")),
                                                               attributes: #" useSafeAreas="YES""#, capabilities: safeAreaCapability),
         (2378, "9413528fa9cb74b82941323c47cf4a0e824d2043534cf0bf09e1cb1bd10199e6")),
        ("sb-safe-area-layout-guides", "27.0", ["iphone"], launch(scene(guides: launchGuides, viewChildren: imageScene(safeArea: true)),
                                                                  attributes: #" useSafeAreas="YES""#, capabilities: safeAreaCapability),
         (2504, "4868e710ec0bec7f781a7892dbe6ea62f68120363dfcbd5987ab485c9f6b30f5")),
        ("sb-image-view-resized", "15.0", ["iphone"], launch(scene(guides: launchGuides, viewChildren: imageScene()), device: nil),
         (2309, "a2590b061bf98593831f06c441f953d5a21ac3ad8fb02e8429abe34f104242a1")),
        ("sb-flutter-launch-15.0-both", "15.0", ["iphone", "ipad"], flutter, (2309, "ae15e87b38d85235c4045e457c41bc41662442ecc34d2e740cf27831cc397aa7")),
        ("sb-flutter-launch-27.0-iphone", "27.0", ["iphone"], flutter, (2309, "327856c799afe87571d54ed1cc781fd94cd93433ed515c17cd8c9f82cdab785f")),
        ("sb-no-traits-flutter-launch-15.0", "15.0", ["iphone", "ipad"], flutter.replacingOccurrences(of: #" useTraitCollections="YES""#, with: ""),
         (2309, "a241c1e1652c6231e5c157a595dd9095ddee4b6243c6e6bdbe17fb27d63791ed")),
        ("sb-precise-n255", "27.0", ["iphone"],
         storyboard(scene(viewChildren: #"<color key="backgroundColor" red="0.0" green="0.50980392156862742" blue="0.78823529411764703" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>"# + "\n")),
         (1919, "d29151817baa6c945ad3c8703a56dd734272bc69557a0df1e3a9ac8efd2bd1c5")),
    ]

    @Test(arguments: launchCases)
    func compilesLaunchScreensAsXcode(name: String, deployment: String, devices: [String], document: String, view: (Int, String)) throws {
        let options = XIBCompiler.Options(module: "T", minimumDeploymentTarget: deployment, targetDevices: devices)
        let compiled = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/\(name)/Main.storyboard", options: options)
        for (file, size, digest) in [("BYZ-38-t0r-view-8bC-Xf-vdC.nib", view.0, view.1), Self.info, Self.controller] {
            let data = try #require(compiled[file], "\(name) \(file)")
            #expect(data.count == size, "\(name) \(file)")
            #expect(SHA256.digest(Array(data)).map { String(format: "%02x", $0) }.joined() == digest, "\(name) \(file)")
        }
    }

    /// Autoresizing to fractions of a point (rounded by a rule not pinned yet:
    /// `sb-device-subview-fraction`), and a safe area guide without `useSafeAreas`.
    @Test(arguments: [
        (storyboard(scene(viewChildren: subview(#"flexibleMinX="YES" widthSizable="YES" flexibleMaxY="YES""#, width: 40)),
                    device: #"<device id="retina4_7" orientation="portrait" appearance="light"/>"#),
         "autoresizing a subview to fractions of a point", "B-261"),
        (storyboard(scene(viewChildren: safeArea)), "a safe area layout guide without useSafeAreas", "B-261"),
    ])
    func refusesWhatIsNotObservedYet(document: String, what: String, item: String) {
        #expect(throws: NomacError.self) {
            try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: Self.options)
        }
        do {
            _ = try StoryboardCompiler.compile(Data(document.utf8), path: "/tmp/Main.storyboard", options: Self.options)
        } catch let error as NomacError {
            #expect(error.message == "nomac does not compile \(what) yet (BACKLOG \(item))")
        } catch {
            Issue.record(error)
        }
    }
}
