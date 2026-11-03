import Foundation
@testable import NomacEnvelope
import NomacTestSupport
import Testing

struct LoaderFeaturesTests {
    static let project = """
    // !$*UTF8*$!
    {
    	archiveVersion = 1;
    	objectVersion = 77;
    	objects = {
    		A00000000000000000000001 = {isa = PBXProject; attributes = {CLASSPREFIX = XY; TargetAttributes = {A00000000000000000000010 = {ProvisioningStyle = Manual; }; }; };
    			buildConfigurationList = A00000000000000000000003; developmentRegion = en; knownRegions = (en, Base, );
    			mainGroup = A00000000000000000000002; packageReferences = (A00000000000000000000040, ); projectDirPath = "";
    			targets = (A00000000000000000000010, A00000000000000000000011, ); };
    		A00000000000000000000002 = {isa = PBXGroup; children = (A00000000000000000000020, A00000000000000000000030, A00000000000000000000035, ); sourceTree = "<group>"; };
    		A00000000000000000000003 = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000004, ); defaultConfigurationName = Debug; };
    		A00000000000000000000004 = {isa = XCBuildConfiguration; baseConfigurationReference = A00000000000000000000030;
    			buildSettings = {GCC_PREPROCESSOR_DEFINITIONS = ("A=1", "$(inherited)", ); GENERATE_INFOPLIST_FILE = "$(GENERATE)"; }; name = Debug; };
    		A00000000000000000000005 = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000004, ); defaultConfigurationName = Release; };
    		A00000000000000000000010 = {isa = PBXNativeTarget; buildConfigurationList = A00000000000000000000005; buildPhases = ( ); dependencies = ( );
    			madeUpKey = 1; name = App; productReference = A00000000000000000000012; productType = "com.apple.product-type.application"; };
    		A00000000000000000000011 = {isa = PBXNativeTarget; buildConfigurationList = A00000000000000000000003; buildPhases = ( ); dependencies = ( );
    			name = Lib; productType = "com.apple.product-type.framework"; };
    		A00000000000000000000012 = {isa = PBXFileReference; explicitFileType = wrapper.application; path = App.app; sourceTree = BUILT_PRODUCTS_DIR; };
    		A00000000000000000000020 = {isa = PBXVariantGroup; children = (A00000000000000000000021, A00000000000000000000022, ); name = Main.strings; sourceTree = "<group>"; };
    		A00000000000000000000021 = {isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = fr; path = fr.lproj/Main.strings; sourceTree = "<group>"; };
    		A00000000000000000000022 = {isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = de; path = Other.strings; sourceTree = "<group>"; };
    		A00000000000000000000030 = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Config.xcconfig; sourceTree = "<group>"; };
    		A00000000000000000000035 = {isa = PBXFileSystemSynchronizedRootGroup; path = Sources; sourceTree = "<group>"; };
    		A00000000000000000000040 = {isa = XCLocalSwiftPackageReference; relativePath = Kit; };
    	};
    	rootObject = A00000000000000000000001;
    }
    """

    static let scheme = """
    <?xml version="1.0" encoding="UTF-8"?>
    <Scheme LastUpgradeVersion = "2700" version = "1.7">
       <TestAction buildConfiguration = "Debug" codeCoverageEnabled = "YES">
          <TestPlans>
             <TestPlanReference reference = "container:Gone.xctestplan" default = "YES"/>
          </TestPlans>
       </TestAction>
       <LaunchAction buildConfiguration = "Debug" enableAddressSanitizer = "YES"/>
    </Scheme>
    """

    static func write(_ files: [String: String], in directory: String) throws {
        for (path, contents) in files {
            let full = directory + "/" + path
            try FileManager.default.createDirectory(atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try contents.write(toFile: full, atomically: true, encoding: .utf8)
        }
    }

    static func check(descriptionOnly: Bool) throws -> (CheckReport, TemporaryDirectory) {
        let directory = try TemporaryDirectory()
        try write([
            "P.xcodeproj/project.pbxproj": project,
            "P.xcodeproj/xcshareddata/xcschemes/App.xcscheme": scheme,
            "P.xcodeproj/xcuserdata/someone.xcuserdatad/xcschemes/Mine.xcscheme": scheme,
            "Config.xcconfig": "#include? \"Missing.xcconfig\"\nCODE_SIGN_STYLE = Automatic\nCODE_SIGN_STYLE[sdk=iphoneos*] = Manual\nOTHER = ;\n",
            "Kit/Package.swift": """
                // swift-tools-version: 6.0
                import PackageDescription
                #if canImport(SomeVendorKit) || os(Linux)
                let flags = ["-DVENDOR"]
                #endif
                let package = Package(name: "Kit", targets: [.target(name: "Kit", swiftSettings: [.unsafeFlags(["-Onone"])])])
                """,
            "Sources/A.swift": "",
        ], in: directory.path)
        let report = CheckReport.make(container: directory.path + "/P.xcodeproj", domains: [LoaderDomain()], options: CheckOptions(descriptionOnly: descriptionOnly))
        return (report, directory)
    }

    static func status(_ report: CheckReport, _ id: String) -> CheckReport.Status? {
        report.features.first { $0.id == id }?.status
    }

    @Test func reportsKnownDifferencesAndUnknownFeatures() throws {
        let (report, directory) = try Self.check(descriptionOnly: true)
        let expected: [String: CheckReport.Status] = [
            "pbxproj:PBXNativeTarget": .verified,
            "pbxproj:PBXNativeTarget.productType=com.apple.product-type.application": .verified,
            "pbxproj:PBXNativeTarget.productReference=absent": .unverified,
            "pbxproj:PBXNativeTarget.madeUpKey": .unknown,
            "pbxproj:PBXVariantGroup.children=region-not-in-knownRegions": .verified,
            "pbxproj:PBXVariantGroup.children=outside-lproj": .verified,
            "pbxproj:XCConfigurationList.defaultConfigurationName=differs-from-project": .unverified,
            "settings:value=list": .verified,
            "settings:GENERATE_INFOPLIST_FILE=macro": .verified,
            "settings:CODE_SIGN_STYLE=condition-and-plain-in-xcconfig": .verified,
            "xcconfig:include-optional=missing": .verified,
            "package:unsafe-flags=local-dependency": .unverified,
            "package:condition=canImport(SomeVendorKit)": .unverified,
            "package:condition=os(Linux)": .verified,
            "scheme:LaunchAction@enableAddressSanitizer=YES": .unknown,
            "scheme:location=user": .verified,
            "testplan:file=missing": .verified,
        ]
        for (id, status) in expected {
            #expect(Self.status(report, id) == status, "\(id)")
        }
        let absent = report.features.first { $0.id == "pbxproj:PBXNativeTarget.productReference=absent" }
        #expect(absent?.uses.map(\.object) == ["PBXNativeTarget A00000000000000000000011 (Lib)"])
        #expect(absent?.uses.first?.file == directory.path + "/P.xcodeproj/project.pbxproj")
        let condition = report.features.first { $0.id == "settings:CODE_SIGN_STYLE=condition-and-plain-in-xcconfig" }
        #expect(condition?.uses.first?.file == directory.path + "/Config.xcconfig")
        #expect(report.unchecked["loader"]?.map(\.what).contains("contents of a synchronized folder") == true)
    }

    @Test func aFullCheckoutReadsSynchronizedFolders() throws {
        let (report, _) = try Self.check(descriptionOnly: false)
        #expect(report.unchecked["loader"]?.contains { $0.what.hasPrefix("contents of a synchronized folder") } == false)
        #expect(Self.status(report, "sync:fileType=sourcecode.swift") == .verified)
    }

    @Test func xcconfigKeysKeepTheirConditions() {
        #expect(LoaderScan.parseSettingKey("CODE_SIGN_IDENTITY[sdk=macosx*][arch=arm64]")! == ("CODE_SIGN_IDENTITY", ["sdk", "arch"]))
        #expect(LoaderScan.parseSettingKey("A[sdk=x]junk") == nil)
        let line = "CODE_SIGN_IDENTITY[sdk=macosx*] = Mac Developer"
        #expect(LoaderScan.assignmentEquals(line).map { line.distance(from: line.startIndex, to: $0) } == 32)
    }

    @Test func manifestConditionsAndCode() {
        #expect(LoaderScan.conditions(in: " canImport(UIKit) && !os(macOS) || swift(>=5.9) || DEBUG") == ["canImport(UIKit)", "os(macOS)", "swift", "flag"])
        #expect(LoaderScan.withoutCommentsAndStrings("a(\"x.unsafeFlags(\") // .b(\n/* .c( */ .d(") == "a(\"\") \n .d(")
    }
}
