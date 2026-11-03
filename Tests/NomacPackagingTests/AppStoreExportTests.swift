import Foundation
import NomacCore
import NomacPlist
import NomacSigning
import NomacTestSupport
import Testing
@testable import NomacPackaging

/// app-store-connect exports of the self-written archive, against what xcodebuild exported for
/// the same archive (`NOMAC_PACKAGING_OBSERVE=<dir>` leaves it in `<dir>/appstore` for
/// `signing_experiments.py synthetic-export`).
@Suite struct AppStoreExportTests {
    /// Info.plists written as Swift Build writes them (binary, keys sorted) come back in
    /// Foundation's order, the top dictionary as copied (`withBuildKeys`), the frameworks'
    /// unchanged; `SwiftSupport` is copied beside `Payload`; without `uploadSymbols` there is no
    /// `Symbols` folder and every summary entry says `symbols` false.
    @Test func writesInfoPlistsAgainAndAddsSwiftSupport() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-export")
        let archive = try ArchiveExporterTests.archive(in: temporary.path)
        let app = archive + "/Products/Applications/App.app"
        for bundle in try ArchiveExporter.nestedCode(in: app) + [app] where FileSystem.isDirectory(bundle) {
            let info = try TextPropertyListParser.parse(String(decoding: try Data(contentsOf: URL(fileURLWithPath: bundle + "/Info.plist")), as: UTF8.self))
            try FileSystem.write(BinaryPropertyList.swiftBuildData(Self.withBuildKeys(info)), to: bundle + "/Info.plist")
            #expect(chmod(bundle + "/Info.plist", 0o644) == 0)
            _ = try CodeSigner.sign(CodeSigner.Request(path: bundle, identity: "-", force: true))
        }
        try FileSystem.createDirectory(archive + "/SwiftSupport/iphoneos")
        try FileManager.default.copyItem(atPath: app + "/Frameworks/libswiftThing.dylib", toPath: archive + "/SwiftSupport/iphoneos/libswiftThing.dylib")
        let options = temporary.path + "/options.plist"
        try FileSystem.write(Data(ArchiveExporterTests.options.replacingOccurrences(of: "release-testing", with: "app-store-connect")
            .replacingOccurrences(of: "\t<key>teamID</key>", with: "\t<key>uploadSymbols</key>\n\t<false/>\n\t<key>teamID</key>").utf8), to: options)
        if let observe = ProcessInfo.processInfo.environment["NOMAC_PACKAGING_OBSERVE"] {
            try? FileManager.default.removeItem(atPath: observe + "/appstore")
            try FileSystem.createDirectory(observe + "/appstore")
            try FileManager.default.copyItem(atPath: archive, toPath: observe + "/appstore/App.xcarchive")
            try FileManager.default.copyItem(atPath: options, toPath: observe + "/appstore/options.plist")
        }
        try ArchiveExporter.export(archive: archive, exportPath: temporary.path + "/out", optionsPath: options)
        #expect(try Self.digests(of: temporary.path + "/out") == [
            "79210a3bfe2ba246aa526d1775999b968de26d8d800ed5c0fad18b2bc6d71eee",
            "1502b4cc49d2ade6b1978f556de49db4c563a7cbca04bcb2c189750a8d1fde5c",
            "90f97d05c6a31c275b57dace3acf08b43ea7fa89a283838614cfda3254997a52",
        ])
    }

    /// The options an export keeps (`distribution_experiments.py` `option-grid`): an unknown one,
    /// `thinning` and `distributionBundleIdentifier` are dropped from an app-store-connect export,
    /// `stripSwiftSymbols` is written true when given false, and `testFlightInternalTestingOnly`
    /// adds `TFInternalTestingOnly` to the app's Info.plist only; as xcodebuild exported this
    /// archive (through `synthetic-export`; without symbols, which record the archive's path).
    /// Thinning in other exports needs the developer directory (`AppThinningTests`).
    @Test func keepsTheOptionsTheMethodUses() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-export")
        let archive = try ArchiveExporterTests.archive(in: temporary.path)
        let options = temporary.path + "/options.plist"
        let extra = """
            \t<key>distributionBundleIdentifier</key>
            \t<string>org.nomac.export</string>
            \t<key>nomacUnknownOption</key>
            \t<string>value</string>
            \t<key>stripSwiftSymbols</key>
            \t<false/>
            \t<key>testFlightInternalTestingOnly</key>
            \t<true/>
            \t<key>thinning</key>
            \t<string>&lt;thin-for-all-variants&gt;</string>
            \t<key>uploadSymbols</key>
            \t<false/>
            \t<key>teamID</key>
            """
        try FileSystem.write(Data(ArchiveExporterTests.options.replacingOccurrences(of: "release-testing", with: "app-store-connect")
            .replacingOccurrences(of: "\t<key>teamID</key>", with: extra).utf8), to: options)
        if let observe = ProcessInfo.processInfo.environment["NOMAC_PACKAGING_OBSERVE"] {
            try? FileManager.default.removeItem(atPath: observe + "/options")
            try FileSystem.createDirectory(observe + "/options")
            try FileManager.default.copyItem(atPath: archive, toPath: observe + "/options/App.xcarchive")
            try FileManager.default.copyItem(atPath: options, toPath: observe + "/options/options.plist")
        }
        try ArchiveExporter.export(archive: archive, exportPath: temporary.path + "/out", optionsPath: options)
        #expect(try Self.digests(of: temporary.path + "/out") == [
            "245a6ef625ebb9e55aef6d143e10401f732f3758986fe3a1202abe4b25150eed",
            "1502b4cc49d2ade6b1978f556de49db4c563a7cbca04bcb2c189750a8d1fde5c",
            "45662144d0166971411fdd887b5ef92e9bab6216ce0ef47ca1dcacc749acdcc4",
        ])
        let thinned = temporary.path + "/thinned.plist"
        try FileSystem.write(Data(ArchiveExporterTests.options.replacingOccurrences(of: "\t<key>teamID</key>", with: """
            \t<key>thinning</key>
            \t<string>&lt;thin-for-all-variants&gt;</string>
            \t<key>teamID</key>
            """).utf8), to: thinned)
        #expect(throws: NomacError("exportArchive app thinning needs the developer directory (--developer-dir, or a nomac sdk install)", exitStatus: 70)) {
            try ArchiveExporter.export(archive: archive, exportPath: temporary.path + "/thin", optionsPath: thinned)
        }
    }

    /// The SHA-256 of each file of an export, the IPA without its entry times and owner ids.
    static func digests(of folder: String) throws -> [String] {
        try FileSystem.sortedContents(of: folder).map { name in
            let bytes = [UInt8](try Data(contentsOf: URL(fileURLWithPath: folder + "/" + name)))
            return SHA256.digest(name.hasSuffix(".ipa") ? ZipMachineFields.cleared(bytes) : bytes).map { String(format: "%02x", $0) }.joined()
        }
    }

    /// An app with on-demand resources (`odr` experiment) exported three ways: the packs in the
    /// app with `AssetPackManifest.plist` (release-testing), beside it with detached signatures
    /// (app-store-connect) or zipped beside the IPA (a base URL), each as xcodebuild exported this
    /// archive (through `synthetic-export`).
    @Test(arguments: [
        ("odr", "release-testing", "", [
            "App.ipa": "f1b6111445b6835195a6dac73c8fe25d696ddeaebb596249e338c119d241191d",
            "DistributionSummary.plist": "785ac583b1701caa31195e31ba44a158fcc962a4d22442fd8195892c5ff70d24",
            "ExportOptions.plist": "9f4fd72841aba6bf545ad509f92990f58f3075b634b36735fd04de17b88faaae",
        ]),
        ("odr-appstore", "app-store-connect", "\t<key>uploadSymbols</key>\n\t<false/>\n", [
            "App.ipa": "ceb1947c739d87eaf08236b0be6c6f87c4d2027673701069686b5f9385570b03",
            "DistributionSummary.plist": "1502b4cc49d2ade6b1978f556de49db4c563a7cbca04bcb2c189750a8d1fde5c",
            "ExportOptions.plist": "90f97d05c6a31c275b57dace3acf08b43ea7fa89a283838614cfda3254997a52",
        ]),
        ("odr-hosted", "release-testing", "\t<key>onDemandResourcesAssetPacksBaseURL</key>\n\t<string>https://example.com/nomac/packs</string>\n", [
            "App.ipa": "5b5c006cf54804eaea0eee1ad2b52f2a3ff7fe8d3721fcc4c63add50345862a3",
            "DistributionSummary.plist": "785ac583b1701caa31195e31ba44a158fcc962a4d22442fd8195892c5ff70d24",
            "ExportOptions.plist": "b9c32a9966248e4a5b492924d8f3a596b201ef49177e60019a4d0d01fd600b2d",
            "OnDemandResources/AssetPackManifest.plist": "168b29513cccc4ae18278a6a215f62880957a62736f41e58335e68ed092f1e12",
            "OnDemandResources/org.nomac.export.level1-0f1e2d3c4b5a69788796a5b4c3d2e1f0.assetpack":
                "77158fcd79a7d0446067d816afcc89b23b9cdcab8cdb58832630b2c2e0e186ee",
            "OnDemandResources/org.nomac.export.level2-00112233445566778899aabbccddeeff.assetpack":
                "7724c25ad63e65ddec5469139df9a0dae76a6677c5f03c57c41e7a5383770c52",
        ]),
    ])
    func exportsOnDemandResources(name: String, method: String, extra: String, expected: [String: String]) throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-export")
        let archive = try ArchiveExporterTests.archive(in: temporary.path)
        let app = archive + "/Products/Applications/App.app"
        var resources: [NomacPlist.PropertyListValue] = []
        for (tag, hash) in [("level1", "0f1e2d3c4b5a69788796a5b4c3d2e1f0"), ("level2", "00112233445566778899aabbccddeeff")] {
            let pack = "org.nomac.export.\(tag)-\(hash).assetpack"
            try FileSystem.write(Data("\(tag)\n".utf8), to: archive + "/Products/OnDemandResources/\(pack)/\(tag).txt")
            try FileSystem.write(BinaryPropertyList.swiftBuildData(.dictionary([
                "CFBundleIdentifier": .string("org.nomac.export.asset-pack-" + hash), "Tags": .array([.string(tag)]),
            ])), to: archive + "/Products/OnDemandResources/\(pack)/Info.plist")
            resources.append(.dictionary([
                "URL": .string("http://127.0.0.1/tmp/build/OnDemandResources/" + pack), "bundleKey": .string("org.nomac.export.asset-pack-" + hash),
                "isStreamable": .boolean(true), "uncompressedSize": .integer(157),
                "primaryContentHash": .dictionary(["hash": .string("2026-10-22T11:20:01.887Z"), "strategy": .string("modtime")]),
            ]))
        }
        try FileSystem.write(BinaryPropertyList.swiftBuildData(.dictionary(["resources": .array(resources)])), to: app + "/AssetPackManifestTemplate.plist")
        _ = try CodeSigner.sign(CodeSigner.Request(path: app, identity: "-", force: true))
        let options = temporary.path + "/options.plist"
        try FileSystem.write(Data(ArchiveExporterTests.options.replacingOccurrences(of: "release-testing", with: method)
            .replacingOccurrences(of: "\t<key>teamID</key>", with: extra + "\t<key>teamID</key>").utf8), to: options)
        if let observe = ProcessInfo.processInfo.environment["NOMAC_PACKAGING_OBSERVE"] {
            try? FileManager.default.removeItem(atPath: observe + "/" + name)
            try FileSystem.createDirectory(observe + "/" + name)
            try FileManager.default.copyItem(atPath: archive, toPath: observe + "/\(name)/App.xcarchive")
            try FileManager.default.copyItem(atPath: options, toPath: observe + "/\(name)/options.plist")
        }
        try ArchiveExporter.export(archive: archive, exportPath: temporary.path + "/out", optionsPath: options)
        #expect(try Self.treeDigests(of: temporary.path + "/out") == expected)
    }

    /// The SHA-256 of every file of an export by its path, zips (the IPA, hosted asset packs)
    /// without their entry times and owner ids, asset packs also without central extra fields.
    static func treeDigests(of folder: String) throws -> [String: String] {
        var digests: [String: String] = [:]
        for path in try FileManager.default.subpathsOfDirectory(atPath: folder) where FileSystem.isFile(folder + "/" + path) {
            let bytes = [UInt8](try Data(contentsOf: URL(fileURLWithPath: folder + "/" + path)))
            let normalized = path.hasSuffix(".assetpack") ? ZipMachineFields.cleared(ZipMachineFields.withoutCentralExtras(bytes))
                : path.hasSuffix(".ipa") ? ZipMachineFields.cleared(bytes) : bytes
            digests[path] = SHA256.digest(normalized).map { String(format: "%02x", $0) }.joined()
        }
        return digests
    }

    /// The keys Swift Build adds to an app's Info.plist, and a dictionary holding the app's 19
    /// keys: in a table of 23 buckets, `UIRequiredDeviceCapabilities` wraps around past
    /// `CFBundleShortVersionString`'s bucket when the keys are inserted in sorted order.
    static func withBuildKeys(_ info: NomacPlist.PropertyListValue) -> NomacPlist.PropertyListValue {
        guard case .dictionary(var entries) = info else { return info }
        for key in ["BuildMachineOSBuild", "DTCompiler", "DTPlatformBuild", "DTPlatformVersion", "DTSDKBuild", "DTSDKName", "DTXcode", "DTXcodeBuild"] {
            entries[key] = .string("value")
        }
        entries["UIRequiredDeviceCapabilities"] = .array([.string("arm64")])
        entries["NSAppTransportSecurity"] = .boolean(true)
        if entries["CFBundlePackageType"] == .string("APPL") {
            entries["NSAppTransportSecurity"] = .dictionary(Dictionary(uniqueKeysWithValues: entries.keys.map { ($0, .boolean(true)) }))
        }
        return .dictionary(entries)
    }

    /// An archive without dSYMs still gets a `Symbols` folder, empty, and `symbols` true in
    /// every summary entry (the export logs "Upload Symbols Failed" for each binary).
    @Test func writesAnEmptySymbolsFolderWithoutDSYMs() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-export")
        let archive = try ArchiveExporterTests.archive(in: temporary.path)
        try FileManager.default.removeItem(atPath: archive + "/dSYMs")
        let options = temporary.path + "/options.plist"
        try FileSystem.write(Data(ArchiveExporterTests.options.replacingOccurrences(of: "release-testing", with: "app-store-connect").utf8), to: options)
        if let observe = ProcessInfo.processInfo.environment["NOMAC_PACKAGING_OBSERVE"] {
            try? FileManager.default.removeItem(atPath: observe + "/nodsyms")
            try FileSystem.createDirectory(observe + "/nodsyms")
            try FileManager.default.copyItem(atPath: archive, toPath: observe + "/nodsyms/App.xcarchive")
            try FileManager.default.copyItem(atPath: options, toPath: observe + "/nodsyms/options.plist")
        }
        try ArchiveExporter.export(archive: archive, exportPath: temporary.path + "/out", optionsPath: options)
        #expect(try Self.digests(of: temporary.path + "/out") == [
            "cb08dceddb3c89d5a3220bf10eeb998efca6f9dcd75721a7662c5415f8e4f0f4",
            "58b6ac222a2e6c0b7b9714bcb34dba510a1e67540cdd5efb92e3c72feaa3adab",
            "0dde0be50f1d2ad7b0e30b407a597a09574eea5403ce36c8e372313edb6c2a81",
        ])
    }

    @Test func refusesToUpload() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-export")
        let archive = try ArchiveExporterTests.archive(in: temporary.path)
        let options = temporary.path + "/options.plist"
        try FileSystem.write(Data(ArchiveExporterTests.options.replacingOccurrences(of: "release-testing", with: "validation").utf8), to: options)
        #expect(throws: NomacError.self) { try ArchiveExporter.export(archive: archive, exportPath: temporary.path + "/out", optionsPath: options) }
    }
}
