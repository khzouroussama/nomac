import Foundation
import NomacCore
import NomacEnvelope
import NomacTestSupport
import Testing
@testable import NomacCoreData

/// `nomac check`'s `coredata:` domain on a self-written app: a model with renaming identifiers in
/// the sources phase, and one with a configuration nomac refuses in a synchronized folder.
@Suite struct CoreDataDomainTests {
    static let project = """
        // !$*UTF8*$!
        {
        \tarchiveVersion = 1;
        \tobjectVersion = 77;
        \tobjects = {
        \t\tA00000000000000000000001 = {isa = PBXProject; buildConfigurationList = A00000000000000000000003; mainGroup = A00000000000000000000002; projectDirPath = ""; targets = (A00000000000000000000010, ); };
        \t\tA00000000000000000000002 = {isa = PBXGroup; children = (A00000000000000000000035, A00000000000000000000040, A00000000000000000000012, ); sourceTree = "<group>"; };
        \t\tA00000000000000000000003 = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000004, ); defaultConfigurationName = Debug; };
        \t\tA00000000000000000000004 = {isa = XCBuildConfiguration; buildSettings = {PRODUCT_NAME = App; }; name = Debug; };
        \t\tA00000000000000000000010 = {isa = PBXNativeTarget; buildConfigurationList = A00000000000000000000003; buildPhases = (A00000000000000000000020, ); fileSystemSynchronizedGroups = (A00000000000000000000035, ); name = App; productReference = A00000000000000000000012; productType = "com.apple.product-type.application"; };
        \t\tA00000000000000000000012 = {isa = PBXFileReference; explicitFileType = wrapper.application; path = App.app; sourceTree = BUILT_PRODUCTS_DIR; };
        \t\tA00000000000000000000020 = {isa = PBXSourcesBuildPhase; files = (A00000000000000000000021, ); };
        \t\tA00000000000000000000021 = {isa = PBXBuildFile; fileRef = A00000000000000000000040; };
        \t\tA00000000000000000000035 = {isa = PBXFileSystemSynchronizedRootGroup; path = Sources; sourceTree = "<group>"; };
        \t\tA00000000000000000000040 = {isa = XCVersionGroup; children = (A00000000000000000000041, ); currentVersion = A00000000000000000000041; path = Renamed.xcdatamodeld; sourceTree = "<group>"; versionGroupType = wrapper.xcdatamodel; };
        \t\tA00000000000000000000041 = {isa = PBXFileReference; lastKnownFileType = wrapper.xcdatamodel; path = Renamed.xcdatamodel; sourceTree = "<group>"; };
        \t};
        \trootObject = A00000000000000000000001;
        }
        """

    static func model(_ body: String) -> String {
        #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"# + "\n"
            + #"<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">"#
            + "\n\(body)</model>\n"
    }

    func check(descriptionOnly: Bool = false) throws -> CheckReport {
        let directory = try TemporaryDirectory()
        try directory.writeExactly(Self.project, to: "App.xcodeproj/project.pbxproj")
        try directory.writeExactly(Self.model("""
                <entity name="Item" representedClassName="Item" elementID="OldItem" syncable="YES" codeGenerationType="class">
                    <attribute name="t" optional="YES" attributeType="String" elementID="oldT"/>
                </entity>

            """), to: "Renamed.xcdatamodeld/Renamed.xcdatamodel/contents")
        try directory.writeExactly(#"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>_XCCurrentVersionName</key><string>Renamed.xcdatamodel</string></dict></plist>"#,
                                   to: "Renamed.xcdatamodeld/.xccurrentversion")
        try directory.writeExactly(Self.model("""
                <entity name="Item" representedClassName="Item" syncable="YES"/>
                <configuration name="Cloud"><memberEntity name="Item"/></configuration>

            """), to: "Sources/Store/Local.xcdatamodel/contents")
        return CheckReport.make(container: directory.path + "/App.xcodeproj", domains: [CoreDataDomain()],
                                options: CheckOptions(descriptionOnly: descriptionOnly))
    }

    @Test func reportsWhatMomcRefuses() throws {
        let report = try check()
        let features = Dictionary(uniqueKeysWithValues: report.features.map { ($0.id, $0) })
        #expect(features["coredata:model=versioned"]?.status == .verified)
        #expect(features["coredata:model"]?.status == .verified)
        let refused = try #require(features["coredata:refused=B-257"])
        #expect(refused.status == .unverified)
        #expect(refused.uses.map { ($0.file as NSString).lastPathComponent } == ["Local.xcdatamodel"])
        #expect(refused.uses.first?.object.contains("<configuration>") == true)
        #expect(features.count == 3)
    }

    @Test func descriptionOnlyListsModelsAsNotChecked() throws {
        let report = try check(descriptionOnly: true)
        #expect(report.features.isEmpty)
        #expect(report.unchecked["coredata"]?.map(\.what) == ["Core Data model contents", "Core Data models in a synchronized folder"])
    }
}
