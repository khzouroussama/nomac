import Foundation
import NomacEnvelope
import Testing
@testable import nomac

/// `nomac check`'s `nib:` domain: a document nomac's ibtool refuses, found where a build finds it.
@Suite struct NibDomainTests {
    @Test func reportsTheCompilersRefusalWithTheTargetsOptions() throws {
        let root = NSTemporaryDirectory() + "nib-domain-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: root + "/App.xcodeproj", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: root + "/App/Base.lproj", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }
        try Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<document type=\"com.apple.InterfaceBuilder3.CocoaTouch.XIB\"><unknownThing/></document>\n".utf8)
            .write(to: URL(fileURLWithPath: root + "/App/Base.lproj/Main.xib"))
        try Data("""
            // !$*UTF8*$!
            {
            \tarchiveVersion = 1;
            \tobjectVersion = 77;
            \tobjects = {
            \t\tA1 = {isa = PBXProject; buildConfigurationList = A3; mainGroup = A2; projectDirPath = ""; projectRoot = ""; targets = (A10, ); };
            \t\tA2 = {isa = PBXGroup; children = (A5, ); sourceTree = "<group>"; };
            \t\tA3 = {isa = XCConfigurationList; buildConfigurations = (A4, ); defaultConfigurationName = Release; };
            \t\tA4 = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; }; name = Release; };
            \t\tA5 = {isa = PBXGroup; children = (A40, ); path = App; sourceTree = "<group>"; };
            \t\tA10 = {isa = PBXNativeTarget; buildConfigurationList = A11; buildPhases = (A20, ); name = App; productType = "com.apple.product-type.application"; };
            \t\tA11 = {isa = XCConfigurationList; buildConfigurations = (A13, ); defaultConfigurationName = Release; };
            \t\tA13 = {isa = XCBuildConfiguration; buildSettings = {IPHONEOS_DEPLOYMENT_TARGET = 15.0; TARGETED_DEVICE_FAMILY = "1,2"; }; name = Release; };
            \t\tA20 = {isa = PBXResourcesBuildPhase; files = (A30, ); };
            \t\tA30 = {isa = PBXBuildFile; fileRef = A40; };
            \t\tA40 = {isa = PBXVariantGroup; children = (A41, ); name = Main.xib; sourceTree = "<group>"; };
            \t\tA41 = {isa = PBXFileReference; name = Base; path = Base.lproj/Main.xib; sourceTree = "<group>"; };
            \t};
            \trootObject = A1;
            }
            """.utf8).write(to: URL(fileURLWithPath: root + "/App.xcodeproj/project.pbxproj"))

        let uses = try NibDomain().scan(root + "/App.xcodeproj", options: CheckOptions()).uses
        #expect(uses.map(\.feature) == ["nib:refused=B-260"])
        #expect(uses.first?.file == root + "/App/Base.lproj/Main.xib")
        #expect(uses.first?.object == "error: nomac does not compile <unknownThing> in a document yet (BACKLOG B-260)")
        #expect(NibDomain.envelope.entry(for: "nib:refused=B-260")?.status == .unverified)
    }
}
