import Foundation
import NomacCore
import Testing

/// The profile is the one place an Xcode upgrade changes (docs/adr/0012-one-xcode-per-release.md):
/// its values agree with one another, and the pins kept outside it agree with it.
@Suite struct XcodeProfileTests {
    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let profile = XcodeProfile.current

    static func read(_ path: String) throws -> String {
        try String(contentsOf: repository.appendingPathComponent(path), encoding: .utf8)
    }

    static func json(_ path: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(read(path).utf8)) as? [String: Any])
    }

    @Test func infoPlistKeysAreTheXcodeSDKAndMacOfTheProfile() throws {
        let name = try #require(profile.infoPlist["DTSDKName"])
        let sdk = try #require(profile.sdk(name))
        #expect(sdk.platform == "iphoneos")
        #expect(profile.infoPlist["DTPlatformName"] == sdk.platform)
        #expect(profile.infoPlist["DTPlatformVersion"] == sdk.version)
        #expect(profile.infoPlist["DTSDKBuild"] == sdk.build)
        #expect(profile.infoPlist["DTXcode"] == profile.xcode.versionActual)
        #expect(profile.infoPlist["DTXcodeBuild"] == profile.xcode.build)
        #expect(profile.infoPlist["BuildMachineOSBuild"] == profile.referenceMac.operatingSystemBuild)
    }

    @Test func assetCatalogNamesTheProfilesXcode() {
        #expect(profile.assetCatalog.versionString.hasPrefix("Xcode \(profile.xcode.version) (\(profile.xcode.build)) "))
    }

    @Test func tablesAreSortedAndUnique() {
        #expect(profile.readableObjectVersions == Array(Set(profile.readableObjectVersions)).sorted())
        #expect(profile.manifestHostConditions.closedKinds == Array(Set(profile.manifestHostConditions.closedKinds)).sorted())
        #expect(profile.sdks.count == Set(profile.sdks.map(\.canonicalName)).count)
    }

    @Test func versionLineNamesTheXcode() {
        #expect(profile.xcode.majorMinor == "\(profile.xcode.version.split(separator: ".")[0]).\(profile.xcode.version.split(separator: ".")[1])")
        #expect(NomacVersion.full == "nomac \(NomacVersion.current) (Xcode \(profile.xcode.version), \(profile.xcode.build))")
    }

    @Test func majorMinorOfPatchAndMajorOnlyVersions() {
        var release = profile.xcode
        release.version = "27.0.1"
        #expect(release.majorMinor == "27.0")
        release.version = "28"
        #expect(release.majorMinor == "28.0")
    }

    @Test func swiftPackagePinsAreTheProfiles() throws {
        let manifest = try Self.read("Package.swift")
        #expect(manifest.contains("let swiftBuildRepository = \"\(profile.pins.swiftBuildRepository)\""))
        #expect(manifest.contains("let swiftBuildRevision = \"\(profile.pins.swiftBuildRevision)\""))
        #expect(manifest.contains("let swiftPMRevision = \"\(profile.pins.swiftPMRevision)\""))
        let pins = try #require(try Self.json("Package.resolved")["pins"] as? [[String: Any]])
        let revisions = Dictionary(uniqueKeysWithValues: pins.compactMap { pin -> (String, String)? in
            guard let identity = pin["identity"] as? String, let revision = (pin["state"] as? [String: Any])?["revision"] as? String else { return nil }
            return (identity, revision)
        })
        #expect(revisions["swift-build"] == profile.pins.swiftBuildRevision)
        #expect(pins.first { $0["identity"] as? String == "swift-build" }?["location"] as? String == profile.pins.swiftBuildRepository)
        #expect(revisions["swift-package-manager"] == profile.pins.swiftPMRevision)
        #expect(try Self.read("Sources/VendoredPackagePIFBuilder/UPSTREAM.md").contains("Tag `\(profile.pins.packagePIFBuilderTag)`"))
    }

    @Test func llvmToolsAreBuiltAtTheProfilesTag() throws {
        #expect(try Self.read(".github/scripts/build-llvm-tools.sh").contains("tag=${LLVM_TAG:-\(profile.pins.llvmProjectTag)}"))
        #expect(try Self.read(".github/scripts/build-swift-frontend.sh").contains("tag=${SWIFT_TAG:-\(profile.pins.swiftToolchainTag)}"))
    }

    @Test func corpusReferencesAreTheProfilesXcode() throws {
        let xcode = try #require(try Self.json("corpus/corpus.json")["xcode"] as? [String: Any])
        #expect(xcode["version"] as? String == profile.xcode.version)
        #expect(xcode["build"] as? String == profile.xcode.build)
    }
}
