import Foundation
import NomacCore
import NomacEnvelope
import NomacTestSupport
import Testing
@testable import NomacCoreML

/// `nomac check`'s `coreml:` domain on a self-written app: a model in the sources phase, a
/// package in a synchronized folder, and a file that is not a model.
@Suite struct CoreMLDomainTests {
    static let project = """
        // !$*UTF8*$!
        {
        \tarchiveVersion = 1;
        \tobjectVersion = 77;
        \tobjects = {
        \t\tA00000000000000000000001 = {isa = PBXProject; buildConfigurationList = A00000000000000000000003; mainGroup = A00000000000000000000002; projectDirPath = ""; targets = (A00000000000000000000010, ); };
        \t\tA00000000000000000000002 = {isa = PBXGroup; children = (A00000000000000000000035, A00000000000000000000040, A00000000000000000000041, A00000000000000000000012, ); sourceTree = "<group>"; };
        \t\tA00000000000000000000003 = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000004, ); defaultConfigurationName = Debug; };
        \t\tA00000000000000000000004 = {isa = XCBuildConfiguration; buildSettings = {PRODUCT_NAME = App; }; name = Debug; };
        \t\tA00000000000000000000010 = {isa = PBXNativeTarget; buildConfigurationList = A00000000000000000000003; buildPhases = (A00000000000000000000020, ); fileSystemSynchronizedGroups = (A00000000000000000000035, ); name = App; productReference = A00000000000000000000012; productType = "com.apple.product-type.application"; };
        \t\tA00000000000000000000012 = {isa = PBXFileReference; explicitFileType = wrapper.application; path = App.app; sourceTree = BUILT_PRODUCTS_DIR; };
        \t\tA00000000000000000000020 = {isa = PBXSourcesBuildPhase; files = (A00000000000000000000021, A00000000000000000000022, ); };
        \t\tA00000000000000000000021 = {isa = PBXBuildFile; fileRef = A00000000000000000000040; };
        \t\tA00000000000000000000022 = {isa = PBXBuildFile; fileRef = A00000000000000000000041; };
        \t\tA00000000000000000000035 = {isa = PBXFileSystemSynchronizedRootGroup; path = Sources; sourceTree = "<group>"; };
        \t\tA00000000000000000000040 = {isa = PBXFileReference; lastKnownFileType = file.mlmodel; path = Linear.mlmodel; sourceTree = "<group>"; };
        \t\tA00000000000000000000041 = {isa = PBXFileReference; lastKnownFileType = file.mlmodel; path = Broken.mlmodel; sourceTree = "<group>"; };
        \t};
        \trootObject = A00000000000000000000001;
        }
        """

    /// A specification of version 1 whose type is `field`, with an empty model of that type.
    static func model(type field: Int) -> Data {
        var message = ProtobufMessage()
        message.fields.append(.init(number: 1, wireType: .varint, payload: [1]))
        message.set(field, message: ProtobufMessage())
        return Data(message.bytes)
    }

    func check(descriptionOnly: Bool = false) throws -> CheckReport {
        let directory = try TemporaryDirectory()
        try directory.writeExactly(Self.project, to: "App.xcodeproj/project.pbxproj")
        try Self.model(type: 300).write(to: URL(fileURLWithPath: directory.path + "/Linear.mlmodel"))
        try directory.writeExactly("\u{7}", to: "Broken.mlmodel")
        try directory.writeExactly(#"{"fileFormatVersion":"1.0.0","itemInfoEntries":{"A":{"path":"com.apple.CoreML/model.mlmodel"}},"rootModelIdentifier":"A"}"#,
                                   to: "Sources/Nested/Program.mlpackage/Manifest.json")
        try directory.writeExactly("", to: "Sources/Nested/Program.mlpackage/Data/com.apple.CoreML/model.mlmodel")
        try Self.model(type: 502).write(to: URL(fileURLWithPath: directory.path + "/Sources/Nested/Program.mlpackage/Data/com.apple.CoreML/model.mlmodel"))
        return CheckReport.make(container: directory.path + "/App.xcodeproj", domains: [CoreMLDomain()],
                                options: CheckOptions(descriptionOnly: descriptionOnly))
    }

    /// A type nomac compiles is verified, unless nomac refuses the model itself (an ML program
    /// without a function).
    @Test func reportsEachModelByItsType() throws {
        let report = try check()
        let features = Dictionary(uniqueKeysWithValues: report.features.map { ($0.id, $0) })
        #expect(features.keys.sorted() == ["coreml:model=glmRegressor", "coreml:model=mlProgram", "coreml:model=unreadable",
                                           "coreml:refused=B-240"])
        #expect(features["coreml:model=glmRegressor"]?.status == .verified)
        #expect(features["coreml:model=mlProgram"]?.status == .verified)
        #expect(features["coreml:model=unreadable"]?.status == .unverified)
        #expect(features["coreml:refused=B-240"]?.uses.map(\.object.isEmpty) == [false])
        #expect(features["coreml:refused=B-240"]?.uses.map { ($0.file as NSString).lastPathComponent } == ["Program.mlpackage"])
    }

    @Test func descriptionOnlyListsModelsAsNotChecked() throws {
        let report = try check(descriptionOnly: true)
        #expect(report.features.isEmpty)
        #expect(Set(report.unchecked["coreml"]?.map(\.what) ?? []) == ["Core ML model contents", "Core ML models in a synchronized folder"])
    }
}
