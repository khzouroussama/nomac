import Foundation
import NomacEnvelope
import NomacTestSupport
import Testing
@testable import NomacPackaging

/// `nomac check`'s `signing:` domain on a self-written project: an ad-hoc app below iOS 16 that
/// embeds a framework and a watch app, a framework whose identity an xcconfig sets for the iOS
/// SDK and whose style is a macro, and a watch app below watchOS 12 with an entitlements file and
/// an architecture-conditional identity.
@Suite struct SigningDomainTests {
    static let project = """
        // !$*UTF8*$!
        {
        \tarchiveVersion = 1;
        \tobjectVersion = 77;
        \tobjects = {
        \t\tA00000000000000000000001 = {isa = PBXProject; buildConfigurationList = A00000000000000000000003; mainGroup = A00000000000000000000002; projectDirPath = ""; targets = (A00000000000000000000010, A00000000000000000000020, A00000000000000000000030, ); };
        \t\tA00000000000000000000002 = {isa = PBXGroup; children = (A00000000000000000000012, A00000000000000000000022, A00000000000000000000032, A00000000000000000000040, ); sourceTree = "<group>"; };
        \t\tA00000000000000000000003 = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000004, ); defaultConfigurationName = Release; };
        \t\tA00000000000000000000004 = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; }; name = Release; };
        \t\tA00000000000000000000010 = {isa = PBXNativeTarget; buildConfigurationList = A00000000000000000000011; buildPhases = (A00000000000000000000015, A00000000000000000000016, ); name = App; productReference = A00000000000000000000012; productType = "com.apple.product-type.application"; };
        \t\tA00000000000000000000011 = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000013, ); defaultConfigurationName = Release; };
        \t\tA00000000000000000000012 = {isa = PBXFileReference; explicitFileType = wrapper.application; path = App.app; sourceTree = BUILT_PRODUCTS_DIR; };
        \t\tA00000000000000000000013 = {isa = XCBuildConfiguration; buildSettings = {CODE_SIGN_IDENTITY = "-"; CODE_SIGN_STYLE = Manual; IPHONEOS_DEPLOYMENT_TARGET = 15.0; DEBUG_INFORMATION_FORMAT = dwarf; }; name = Release; };
        \t\tA00000000000000000000015 = {isa = PBXCopyFilesBuildPhase; dstPath = ""; dstSubfolderSpec = 10; files = (A00000000000000000000017, ); };
        \t\tA00000000000000000000016 = {isa = PBXCopyFilesBuildPhase; dstPath = "$(CONTENTS_FOLDER_PATH)/Watch"; dstSubfolderSpec = 16; files = (A00000000000000000000018, ); };
        \t\tA00000000000000000000017 = {isa = PBXBuildFile; fileRef = A00000000000000000000022; settings = {ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }; };
        \t\tA00000000000000000000018 = {isa = PBXBuildFile; fileRef = A00000000000000000000032; };
        \t\tA00000000000000000000020 = {isa = PBXNativeTarget; buildConfigurationList = A00000000000000000000021; buildPhases = (); name = Kit; productReference = A00000000000000000000022; productType = "com.apple.product-type.framework"; };
        \t\tA00000000000000000000021 = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000023, ); defaultConfigurationName = Release; };
        \t\tA00000000000000000000022 = {isa = PBXFileReference; explicitFileType = wrapper.framework; path = Kit.framework; sourceTree = BUILT_PRODUCTS_DIR; };
        \t\tA00000000000000000000023 = {isa = XCBuildConfiguration; baseConfigurationReference = A00000000000000000000040; buildSettings = {}; name = Release; };
        \t\tA00000000000000000000030 = {isa = PBXNativeTarget; buildConfigurationList = A00000000000000000000031; buildPhases = (); name = Watch; productReference = A00000000000000000000032; productType = "com.apple.product-type.application"; };
        \t\tA00000000000000000000031 = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000033, ); defaultConfigurationName = Release; };
        \t\tA00000000000000000000032 = {isa = PBXFileReference; explicitFileType = wrapper.application; path = Watch.app; sourceTree = BUILT_PRODUCTS_DIR; };
        \t\tA00000000000000000000033 = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = watchos; WATCHOS_DEPLOYMENT_TARGET = 11.0; CODE_SIGN_ENTITLEMENTS = Watch/Watch.entitlements; "CODE_SIGN_IDENTITY[arch=arm64]" = "-"; }; name = Release; };
        \t\tA00000000000000000000040 = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Kit.xcconfig; sourceTree = "<group>"; };
        \t};
        \trootObject = A00000000000000000000001;
        }
        """

    @Test func reportsWhatEachTargetAsksOfSigning() throws {
        let directory = try TemporaryDirectory()
        try directory.writeExactly(Self.project, to: "App.xcodeproj/project.pbxproj")
        try directory.writeExactly("CODE_SIGN_IDENTITY[sdk=iphoneos*] = Apple Development\nCODE_SIGN_IDENTITY[sdk=macosx*] = -\nCODE_SIGN_STYLE = $(STYLE)\n",
                                   to: "Kit.xcconfig")
        let report = CheckReport.make(container: directory.path + "/App.xcodeproj", domains: [SigningDomain()], options: CheckOptions())
        let statuses = Dictionary(uniqueKeysWithValues: report.features.map { ($0.id, $0.status) })
        #expect(statuses == [
            "signing:product=com.apple.product-type.application": .verified,
            "signing:product=com.apple.product-type.framework": .verified,
            "signing:product=com.apple.product-type.application@watchos": .verified,
            "signing:identity=ad-hoc": .verified,
            "signing:identity=apple-development": .unverified,
            "signing:identity=conditional": .unknown,
            "signing:style=manual": .verified,
            "signing:style=expression": .unknown,
            "signing:style=default": .unverified,
            "signing:pages=4k": .verified,
            "signing:code-directory=sha1": .verified,
            "signing:dsym=none": .verified,
            "signing:embed=frameworks": .verified,
            "signing:embed=watch": .verified,
            "signing:entitlements": .unverified,
        ])
    }

    /// Every verified feature cites an experiment of `signing_experiments.py`, every unverified
    /// one a note and, when it has one, a BACKLOG item that exists.
    @Test func everyCitationResolves() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let script = try String(contentsOf: repository.appendingPathComponent(".github/scripts/signing_experiments.py"), encoding: .utf8)
        let backlog = try String(contentsOf: repository.appendingPathComponent("docs/BACKLOG.md"), encoding: .utf8)
        for entry in SigningEnvelope.envelope.entries.values {
            if entry.status == .verified { #expect(!entry.evidence.isEmpty, "\(entry.feature)") } else { #expect(entry.note != nil, "\(entry.feature)") }
            for evidence in entry.evidence {
                if evidence.hasPrefix("signing-experiments:") {
                    #expect(script.contains("    \"\(evidence.dropFirst("signing-experiments:".count))\": ("), "\(entry.feature): \(evidence)")
                } else {
                    #expect(backlog.contains("| \(evidence) |"), "\(entry.feature): \(evidence)")
                }
            }
        }
    }
}
