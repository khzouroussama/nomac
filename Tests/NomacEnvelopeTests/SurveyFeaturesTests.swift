import Foundation
@testable import NomacEnvelope
import NomacTestSupport
import Testing

/// Features the survey ranks first and rules landed since the envelope (docs/formats/project-file.md,
/// docs/formats/pif.md), as `nomac check` reports them.
struct SurveyFeaturesTests {
    static func report(objects: String, files: [String: String] = [:], objectVersion: Int = 77, settings: String = "SDKROOT = iphoneos; ",
                       target: String = "", container: String = "P.xcodeproj") throws -> CheckReport {
        let directory = try TemporaryDirectory()
        let project = """
        // !$*UTF8*$!
        {
        	archiveVersion = 1;
        	objectVersion = \(objectVersion);
        	objects = {
        		P1 = {isa = PBXProject; buildConfigurationList = L1; mainGroup = G1; projectDirPath = ""; targets = (T1, ); };
        		L1 = {isa = XCConfigurationList; buildConfigurations = (C1, ); defaultConfigurationName = Debug; };
        		C1 = {isa = XCBuildConfiguration; buildSettings = {\(settings)}; name = Debug; };
        		T1 = {isa = PBXNativeTarget; buildConfigurationList = L1; buildPhases = (B1, ); \(target)name = App; productReference = R1; productType = "com.apple.product-type.application"; };
        		R1 = {isa = PBXFileReference; explicitFileType = wrapper.application; path = App.app; sourceTree = BUILT_PRODUCTS_DIR; };
        \(objects)
        	};
        	rootObject = P1;
        }
        """
        try LoaderFeaturesTests.write(["P.xcodeproj/project.pbxproj": project].merging(files) { $1 }, in: directory.path)
        return CheckReport.make(container: directory.path + "/" + container, domains: [LoaderDomain()], options: CheckOptions(descriptionOnly: true))
    }

    static func status(_ report: CheckReport, _ id: String) -> CheckReport.Status? {
        report.features.first { $0.id == id }?.status
    }

    /// envelope-experiments `object-versions`: Xcode reads some versions and refuses the others, as nomac does.
    @Test func objectVersionsAreVerified() throws {
        let group = "G1 = {isa = PBXGroup; children = (); sourceTree = \"<group>\"; };"
        #expect(Self.status(try Self.report(objects: group, objectVersion: 46), "pbxproj:objectVersion=46") == .verified)
        #expect(Self.status(try Self.report(objects: group, objectVersion: 57), "pbxproj:objectVersion=57") == .verified)
        #expect(Self.status(try Self.report(objects: group, objectVersion: 112), "pbxproj:objectVersion=112") == .unknown)
    }

    /// loader-experiments `copy-files`: every destination from 0 to 17 and none; 18 and above stop xcodebuild.
    @Test func copyFilesDestinations() throws {
        let report = try Self.report(objects: """
            G1 = {isa = PBXGroup; children = (); sourceTree = "<group>"; };
            B1 = {isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; files = (); runOnlyForDeploymentPostprocessing = 0; };
            """)
        #expect(Self.status(report, "pbxproj:PBXCopyFilesBuildPhase.dstSubfolderSpec=none") == .verified)
        let envelope = LoaderEnvelope.envelope
        #expect(envelope.entry(for: "pbxproj:PBXCopyFilesBuildPhase.dstSubfolderSpec=0")?.status == .verified)
        #expect(envelope.entry(for: "pbxproj:PBXCopyFilesBuildPhase.dstSubfolderSpec=17")?.status == .verified)
        #expect(envelope.entry(for: "pbxproj:PBXCopyFilesBuildPhase.dstSubfolderSpec=18")?.evidence == ["B-040"])
        #expect(envelope.entry(for: "pbxproj:PBXCopyFilesBuildPhase.dstSubfolderSpec=sixteen") == nil)
    }

    /// envelope-experiments `identity-conditions`: the SDK's conditional assignment of a signing
    /// identity wins at one level, as Swift Build evaluates it, `-` on either side.
    @Test func signingIdentitiesWithAndWithoutACondition() throws {
        let report = try Self.report(objects: """
            G1 = {isa = PBXGroup; children = (); sourceTree = "<group>"; };
            B1 = {isa = PBXSourcesBuildPhase; files = (); };
            C2 = {isa = XCBuildConfiguration; buildSettings = {CODE_SIGN_IDENTITY = "-"; "CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "iPhone Developer"; }; name = Debug; };
            L2 = {isa = XCConfigurationList; buildConfigurations = (C2, ); defaultConfigurationName = Debug; };
            T2 = {isa = PBXNativeTarget; buildConfigurationList = L2; buildPhases = (); name = Other; productType = "com.apple.product-type.framework"; };
            """)
        #expect(Self.status(report, "settings:CODE_SIGN_IDENTITY=condition") == .verified)
        #expect(Self.status(report, "settings:CODE_SIGN_IDENTITY=condition-and-plain") == .verified)
    }

    /// envelope-experiments `file-type-none`: the extension decides, unless it names no type or is `.plist`.
    @Test func untypedReferences() throws {
        let report = try Self.report(objects: """
            G1 = {isa = PBXGroup; children = (F1, F2, F3, ); sourceTree = "<group>"; };
            F1 = {isa = PBXFileReference; path = Helper.swift; sourceTree = "<group>"; };
            F2 = {isa = PBXFileReference; path = Notes; sourceTree = "<group>"; };
            F3 = {isa = PBXFileReference; path = Settings.plist; sourceTree = "<group>"; };
            B1 = {isa = PBXSourcesBuildPhase; files = (); };
            """)
        let untyped = report.features.filter { $0.id.hasPrefix("pbxproj:PBXFileReference.fileType=none") }
        #expect(untyped.map(\.id) == ["pbxproj:PBXFileReference.fileType=none", "pbxproj:PBXFileReference.fileType=none-by-contents"])
        #expect(untyped.map(\.uses.count) == [1, 2])
        #expect(untyped.map(\.status) == [.verified, .verified])
    }

    /// loader-experiments `product-duplicates`: a product a target names several times, and a
    /// product build file outside the first Frameworks phase (home-assistant's `WatchApp`).
    @Test func productsNamedTwiceOrOutsideTheFirstFrameworksPhase() throws {
        let products = """
            G1 = {isa = PBXGroup; children = (); sourceTree = "<group>"; };
            X1 = {isa = XCSwiftPackageProductDependency; productName = LocalKit; };
            X2 = {isa = XCSwiftPackageProductDependency; productName = LocalKit; };
            F1 = {isa = PBXBuildFile; productRef = X1; };
            F2 = {isa = PBXBuildFile; productRef = X2; };

            """
        let linked = try Self.report(objects: products + "B1 = {isa = PBXFrameworksBuildPhase; files = (F1, F2, ); };")
        #expect(Self.status(linked, "pbxproj:PBXNativeTarget.dependencies=product-several-times") == .verified)
        #expect(Self.status(linked, "pbxproj:PBXBuildFile.productRef=outside-first-frameworks-phase") == nil)
        let embedded = try Self.report(objects: products + "B1 = {isa = PBXCopyFilesBuildPhase; dstPath = \"\"; dstSubfolderSpec = 10; files = (F1, F2, ); };")
        #expect(Self.status(embedded, "pbxproj:PBXBuildFile.productRef=outside-first-frameworks-phase") == .verified)
        #expect(Self.status(embedded, "pbxproj:PBXNativeTarget.dependencies=product-several-times") == nil)
    }

    /// envelope-experiments `unresolved-proxies`: nomac gives the build file of a product it does
    /// not find Xcode's GUID when the project's location settings are plain; `SYMROOT` and a
    /// conditional SDK change what xcodebuild shows (BACKLOG B-089).
    @Test func unresolvedProxies() throws {
        func features(_ settings: String) throws -> [String: CheckReport.Status] {
            let report = try Self.report(objects: """
                G1 = {isa = PBXGroup; children = (S1, ); sourceTree = "<group>"; };
                S1 = {isa = PBXFileReference; lastKnownFileType = "wrapper.pb-project"; path = Sub/Sub.xcodeproj; sourceTree = "<group>"; };
                X1 = {isa = PBXContainerItemProxy; containerPortal = S1; proxyType = 2; remoteGlobalIDString = R9; remoteInfo = Gone; };
                Y1 = {isa = PBXReferenceProxy; fileType = archive.ar; path = libGone.a; remoteRef = X1; sourceTree = BUILT_PRODUCTS_DIR; };
                B1 = {isa = PBXFrameworksBuildPhase; files = (); };
                """, settings: settings)
            let ids = ["pbxproj:PBXReferenceProxy.remoteRef=unresolved", "pbxproj:PBXReferenceProxy.remoteRef=unresolved-other-build-folder",
                       "settings:SYMROOT", "settings:SDKROOT=simulator", "settings:SDKROOT=condition", "settings:SDKROOT=condition-other"]
            return Dictionary(uniqueKeysWithValues: report.features.filter { ids.contains($0.id) }.map { ($0.id, $0.status) })
        }
        #expect(try features("SDKROOT = iphoneos; ") == ["pbxproj:PBXReferenceProxy.remoteRef=unresolved": .verified])
        #expect(try features("SDKROOT = iphoneos; SYMROOT = \"$(HOME)/b\"; ") == [
            "pbxproj:PBXReferenceProxy.remoteRef=unresolved-other-build-folder": .unverified, "settings:SYMROOT": .verified,
        ])
        // Through a workspace, Xcode's scheme builds put products in DerivedData whatever SYMROOT is
        // (envelope-experiments `symroot-locations`; mattermost's Pods).
        let workspace = ["W.xcworkspace/contents.xcworkspacedata": #"<?xml version="1.0" encoding="UTF-8"?><Workspace version = "1.0"><FileRef location = "group:P.xcodeproj"></FileRef></Workspace>"#]
        let throughWorkspace = try Self.report(objects: "G1 = {isa = PBXGroup; children = (); sourceTree = \"<group>\"; };\nB1 = {isa = PBXSourcesBuildPhase; files = (); };",
                                               files: workspace, settings: "SDKROOT = iphoneos; SYMROOT = Out; ", container: "W.xcworkspace")
        #expect(Self.status(throughWorkspace, "settings:SYMROOT") == nil)
        // loader-experiments `simulator-sdks`, `simulator-sdk-conditions`: a simulator SDKROOT is
        // refused for a device destination as Xcode refuses it, also under sdk, config and arch
        // conditions; other conditions are not observed.
        #expect(try features("SDKROOT = iphonesimulator; ") == [
            "pbxproj:PBXReferenceProxy.remoteRef=unresolved": .verified, "settings:SDKROOT=simulator": .verified,
        ])
        #expect(try features("SDKROOT = iphoneos; \"SDKROOT[config=Debug]\" = iphonesimulator; ")["settings:SDKROOT=condition"] == .verified)
        #expect(try features("SDKROOT = iphoneos; \"SDKROOT[variant=debug]\" = iphonesimulator; ")["settings:SDKROOT=condition-other"] == .unverified)
    }

    /// loader-experiments `blueprint-names`, `coverage-autocreated-plan`.
    @Test func schemeReferencesWithoutBlueprintNames() throws {
        let scheme = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Scheme LastUpgradeVersion = "2700" version = "1.7">
           <TestAction buildConfiguration = "Debug" shouldAutocreateTestPlan = "YES">
              <Testables>
                 <TestableReference skipped = "NO">
                    <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "T1" BuildableName = "App.app" ReferencedContainer = "container:P.xcodeproj"/>
                 </TestableReference>
              </Testables>
           </TestAction>
        </Scheme>
        """
        let report = try Self.report(objects: """
            G1 = {isa = PBXGroup; children = (); sourceTree = "<group>"; };
            B1 = {isa = PBXSourcesBuildPhase; files = (); };
            """, files: ["P.xcodeproj/xcshareddata/xcschemes/App.xcscheme": scheme])
        #expect(Self.status(report, "scheme:BuildableReference@BlueprintName=missing") == .verified)
        #expect(Self.status(report, "scheme:TestAction@shouldAutocreateTestPlan=YES") == .verified)
    }

    /// envelope-experiments `variant-groups` (`regions-two-groups`) and `survey-shapes-4`
    /// (`dangling-file-reference`): shapes whose outputs Xcode orders otherwise (BACKLOG B-030; the dangling
    /// build file's order is verified by loader-experiments `dangling-synchronized`).
    @Test func shapesXcodeOrdersOtherwise() throws {
        let report = try Self.report(objects: """
            G1 = {isa = PBXGroup; children = (V1, V2, S1, ); sourceTree = "<group>"; };
            V1 = {isa = PBXVariantGroup; children = (F1, ); name = A.strings; sourceTree = "<group>"; };
            F1 = {isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = it; path = it.lproj/A.strings; sourceTree = "<group>"; };
            V2 = {isa = PBXVariantGroup; children = (F2, ); name = B.strings; sourceTree = "<group>"; };
            F2 = {isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = ja; path = ja.lproj/B.strings; sourceTree = "<group>"; };
            S1 = {isa = PBXFileSystemSynchronizedRootGroup; path = Feature; sourceTree = "<group>"; };
            B1 = {isa = PBXSourcesBuildPhase; files = (D1, ); };
            D1 = {isa = PBXBuildFile; fileRef = Z9; };
            """, target: "fileSystemSynchronizedGroups = (S1, ); ")
        #expect(Self.status(report, "pbxproj:PBXVariantGroup.children=regions-from-several-groups") == .unverified)
        #expect(Self.status(report, "pbxproj:PBXBuildFile.fileRef=dangling-beside-synchronized-members") == .verified)
        #expect(Self.status(report, "pbxproj:PBXBuildFile.fileRef=dangling") == nil)
    }
}
