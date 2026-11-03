import Foundation
import NomacEnvelope
import Testing
@testable import nomac

/// `nomac check`'s `metal:` domain: shaders in the sources phase and in a synchronized folder.
@Suite struct MetalDomainTests {
    @Test func reportsEveryShaderAsOutsideTheEnvelope() throws {
        let root = NSTemporaryDirectory() + "metal-domain-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: root) }
        func write(_ contents: String, to path: String) throws {
            try FileManager.default.createDirectory(atPath: ((root + "/" + path) as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: URL(fileURLWithPath: root + "/" + path))
        }
        try write("""
            // !$*UTF8*$!
            {
            \tarchiveVersion = 1;
            \tobjectVersion = 77;
            \tobjects = {
            \t\tA1 = {isa = PBXProject; buildConfigurationList = A3; mainGroup = A2; projectDirPath = ""; targets = (A10, ); };
            \t\tA2 = {isa = PBXGroup; children = (A35, A40, ); sourceTree = "<group>"; };
            \t\tA3 = {isa = XCConfigurationList; buildConfigurations = (A4, ); defaultConfigurationName = Release; };
            \t\tA4 = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; }; name = Release; };
            \t\tA10 = {isa = PBXNativeTarget; buildConfigurationList = A3; buildPhases = (A20, ); fileSystemSynchronizedGroups = (A35, ); name = App; productType = "com.apple.product-type.application"; };
            \t\tA20 = {isa = PBXSourcesBuildPhase; files = (A21, ); };
            \t\tA21 = {isa = PBXBuildFile; fileRef = A40; };
            \t\tA35 = {isa = PBXFileSystemSynchronizedRootGroup; path = Sources; sourceTree = "<group>"; };
            \t\tA40 = {isa = PBXFileReference; lastKnownFileType = sourcecode.metal; path = Blur.metal; sourceTree = "<group>"; };
            \t};
            \trootObject = A1;
            }
            """, to: "App.xcodeproj/project.pbxproj")
        try write("#include <metal_stdlib>\n", to: "Blur.metal")
        try write("#include <metal_stdlib>\n", to: "Sources/Effects/Particles.metal")
        try write("", to: "Sources/Effects/View.swift")
        let report = CheckReport.make(container: root + "/App.xcodeproj", domains: [MetalDomain()], options: CheckOptions())
        let feature = try #require(report.features.first)
        #expect(report.features.count == 1)
        #expect(feature.id == "metal:shader" && feature.status == .unverified)
        #expect(feature.uses.map(\.object).sorted() == ["Blur.metal", "Particles.metal"])
    }
}
