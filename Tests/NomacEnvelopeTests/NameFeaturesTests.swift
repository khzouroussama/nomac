import Foundation
@testable import NomacEnvelope
import NomacTestSupport
import Testing

/// `nomac check` on a project shaped like loader-experiments `unicode-nfc`: names outside ASCII
/// in the container, the project file, a synchronized folder and its keys, a scheme, and an
/// xcconfig include spelled otherwise on disk; every file is written with its bytes as given.
struct NameFeaturesTests {
    static func nfc(_ text: String) -> String { text.precomposedStringWithCanonicalMapping }
    static func nfd(_ text: String) -> String { text.decomposedStringWithCanonicalMapping }

    static var project: String {
        """
        // !$*UTF8*$!
        {
        \tarchiveVersion = 1;
        \tobjectVersion = 77;
        \tobjects = {
        \t\tA00000000000000000000001 = {isa = PBXProject; buildConfigurationList = A00000000000000000000003; mainGroup = A00000000000000000000002; projectDirPath = ""; targets = (A00000000000000000000010, ); };
        \t\tA00000000000000000000002 = {isa = PBXGroup; children = (A00000000000000000000030, A00000000000000000000035, A00000000000000000000012, ); name = "\(nfc("Ünïcödé"))"; sourceTree = "<group>"; };
        \t\tA00000000000000000000003 = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000004, ); defaultConfigurationName = Debug; };
        \t\tA00000000000000000000004 = {isa = XCBuildConfiguration; baseConfigurationReference = A00000000000000000000030; buildSettings = {PRODUCT_NAME = App; }; name = Debug; };
        \t\tA00000000000000000000010 = {isa = PBXNativeTarget; buildConfigurationList = A00000000000000000000003; buildPhases = ( ); fileSystemSynchronizedGroups = (A00000000000000000000035, ); name = App; productReference = A00000000000000000000012; productType = "com.apple.product-type.application"; };
        \t\tA00000000000000000000012 = {isa = PBXFileReference; explicitFileType = wrapper.application; path = App.app; sourceTree = BUILT_PRODUCTS_DIR; };
        \t\tA00000000000000000000030 = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Config.xcconfig; sourceTree = "<group>"; };
        \t\tA00000000000000000000035 = {isa = PBXFileSystemSynchronizedRootGroup; exceptions = (A00000000000000000000036, ); explicitFolders = ("\(nfc("Földer"))", ); path = Sources; sourceTree = "<group>"; };
        \t\tA00000000000000000000036 = {isa = PBXFileSystemSynchronizedBuildFileExceptionSet; membershipExceptions = ("\(nfc("Ïgnored.swift"))", "\(nfd("Ïgnored2.swift"))", ); target = A00000000000000000000010; };
        \t};
        \trootObject = A00000000000000000000001;
        }
        """
    }

    @Test func reportsNamesOutsideASCII() throws {
        let directory = try TemporaryDirectory()
        let container = Self.nfc("Café Kit.xcodeproj")
        try directory.writeExactly(Self.project, to: container + "/project.pbxproj")
        try directory.writeExactly(LoaderFeaturesTests.scheme.replacingOccurrences(of: "<LaunchAction", with: "<BuildAction><BuildActionEntries><BuildActionEntry><BuildableReference ReferencedContainer = \"container:\(Self.nfd("Café Kit.xcodeproj"))\"/></BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction"),
                                   to: container + "/xcshareddata/xcschemes/" + Self.nfc("Schémé") + ".xcscheme")
        try directory.writeExactly("#include \"\(Self.nfc("Ödd.xcconfig"))\"\n", to: "Config.xcconfig")
        try directory.writeExactly("A = 1\n", to: Self.nfd("Ödd.xcconfig"))
        try directory.writeExactly("", to: "Sources/" + Self.nfd("Ïgnored.swift"))
        try directory.writeExactly("", to: "Sources/" + Self.nfc("Ïgnored2.swift"))
        try directory.writeExactly("", to: "Sources/" + Self.nfc("Földer") + "/In.txt")
        let report = CheckReport.make(container: directory.path + "/" + container, domains: [LoaderDomain()], options: CheckOptions(descriptionOnly: false))
        let expected: [String: CheckReport.Status] = [
            "names:container=non-ascii": .verified,
            "names:container=whitespace": .verified,
            "names:pbxproj=non-ascii": .verified,
            "names:sync-key=precomposed": .verified,
            "names:sync-key=decomposed": .verified,
            "names:sync-explicit-folder=non-ascii": .verified,
            "names:sync-item=non-ascii": .verified,
            "names:scheme=non-ascii": .verified,
            "names:scheme-container=non-ascii": .verified,
            "xcconfig:include=spelled-otherwise-on-disk": .unverified,
        ]
        for (id, status) in expected {
            #expect(LoaderFeaturesTests.status(report, id) == status, "\(id)")
        }
        // The excepted files are on disk in the other form, so neither is reported missing.
        #expect(LoaderFeaturesTests.status(report, "sync:excepted-path=missing") == nil)
        #expect(LoaderFeaturesTests.status(report, "xcconfig:include=missing") == nil)
    }

    /// A reference whose path names a folder in another case than the disk (cwa's
    /// `PDFGeneration`, `PdfGeneration` on disk) is reported as such, not as missing, on a Mac's
    /// case-insensitive file system too; one spelled as on disk is not (BACKLOG B-062).
    @Test(arguments: [("PDFGeneration/A.swift", CheckReport.Status?.some(.unverified)), ("PdfGeneration/A.swift", nil)])
    func pathsInAnotherCase(path: String, status: CheckReport.Status?) throws {
        let directory = try TemporaryDirectory()
        let project = """
        // !$*UTF8*$!
        {
        \tarchiveVersion = 1;
        \tobjectVersion = 77;
        \tobjects = {
        \t\tP1 = {isa = PBXProject; buildConfigurationList = L1; mainGroup = G1; projectDirPath = ""; targets = (); };
        \t\tL1 = {isa = XCConfigurationList; buildConfigurations = (C1, ); defaultConfigurationName = Debug; };
        \t\tC1 = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; }; name = Debug; };
        \t\tG1 = {isa = PBXGroup; children = (F1, ); sourceTree = "<group>"; };
        \t\tF1 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \(path); sourceTree = "<group>"; };
        \t};
        \trootObject = P1;
        }
        """
        try LoaderFeaturesTests.write(["P.xcodeproj/project.pbxproj": project, "PdfGeneration/A.swift": ""], in: directory.path)
        let report = CheckReport.make(container: directory.path + "/P.xcodeproj", domains: [LoaderDomain()], options: CheckOptions(descriptionOnly: false))
        #expect(LoaderFeaturesTests.status(report, "pbxproj:PBXFileReference.path=case-mismatch") == status)
        #expect(LoaderFeaturesTests.status(report, "pbxproj:PBXFileReference.path=missing") == nil)
    }
}
