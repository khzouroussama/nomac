import Foundation
import NomacCore
import NomacSigning
import NomacTestSupport
import Testing
@testable import NomacPackaging

/// `nomac export` on a self-written archive gives what `xcodebuild -exportArchive` gave for the
/// same archive and options (the IPA without its entry times and owner ids). On a Mac, `NOMAC_PACKAGING_OBSERVE=<dir>` leaves the archive and the
/// options in `<dir>/export` for `signing_experiments.py synthetic-export`, which prints the
/// values these tests expect.
@Suite struct ArchiveExporterTests {
    static let options = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
    	<key>method</key>
    	<string>release-testing</string>
    	<key>signingCertificate</key>
    	<string>-</string>
    	<key>signingStyle</key>
    	<string>manual</string>
    	<key>teamID</key>
    	<string>NOMAC00000</string>
    </dict>
    </plist>

    """

    /// An ad-hoc signed archive of an app embedding two frameworks and two extensions (and an
    /// App Clip, signed ad hoc as no Xcode build can; and a watch app, arm64 for watchOS 26.0 and
    /// arm64_32 for 11.0, with its universal dSYM). Without `embedding`, the app alone.
    static func archive(in directory: String, team: String = "", clip: Bool = false, watch: Bool = false,
                        appInfo: [String: PropertyListValue] = [:], scheme: String = "App", embedding: Bool = true) throws -> String {
        let archive = directory + "/App.xcarchive"
        let app = archive + "/Products/Applications/App.app"
        let bundles: [(path: String, identifier: String, type: String, executable: Bool, seed: UInt8)] = (!embedding ? [] : [
            ("Frameworks/Zed.framework", "org.nomac.export.Zed", "FMWK", false, 2),
            ("Frameworks/Kit.framework", "org.nomac.export.Kit", "FMWK", false, 3),
            ("PlugIns/Share.appex", "org.nomac.export.Share", "XPC!", true, 4),
            ("PlugIns/Action.appex", "org.nomac.export.Action", "XPC!", true, 5),
        ]) + (clip ? [("AppClips/Clip.app", "org.nomac.export.Clip", "APPL", true, 9)] : [])
            + (watch ? [("Watch/Watch.app", "org.nomac.export.watchkitapp", "APPL", true, 10)] : []) + [
            ("", "org.nomac.export", "APPL", true, 6),
        ]
        for bundle in bundles {
            let path = bundle.path.isEmpty ? app : app + "/" + bundle.path
            let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            try FileSystem.createDirectory(path)
            // Without the platform keys, xcodebuild takes the archive for a macOS one. Written as
            // XML in key order: a binary plist of a Swift dictionary changes from run to run.
            // xcodebuild's App Clip remover needs the bundles' names ("could not discover target
            // bundle name").
            var info: [String: PropertyListValue] = [
                "CFBundleExecutable": .string(name), "CFBundleIdentifier": .string(bundle.identifier),
                "CFBundlePackageType": .string(bundle.type), "CFBundleVersion": .string("7"), "CFBundleShortVersionString": .string("2.1"),
                "CFBundleSupportedPlatforms": .array([.string("iPhoneOS")]), "DTPlatformName": .string("iphoneos"),
                "MinimumOSVersion": .string("18.0"), "UIDeviceFamily": .array([.integer(1), .integer(2)]),
            ]
            if clip { info["CFBundleName"] = .string(name) }
            if bundle.path.isEmpty { info.merge(appInfo) { $1 } }
            let executable: [UInt8]
            if bundle.path.hasPrefix("Watch/") {
                info.merge(["CFBundleSupportedPlatforms": .array([.string("WatchOS")]), "DTPlatformName": .string("watchos"),
                            "MinimumOSVersion": .string("11.0"), "UIDeviceFamily": .array([.integer(4)]), "WKApplication": .boolean(true),
                            "WKCompanionAppBundleIdentifier": .string("org.nomac.export")]) { $1 }
                executable = SyntheticMachO.universal([SyntheticMachO.machO(platform: 4, minimumOS: 26 << 16, seed: bundle.seed),
                                                       SyntheticMachO.machO(arm64_32: true, platform: 4, minimumOS: 11 << 16, seed: bundle.seed + 1)])
            } else {
                executable = SyntheticMachO.machO(executable: bundle.executable, seed: bundle.seed)
            }
            try FileSystem.write(Data(PropertyListValue.xmlDocument(.dictionary(info))), to: path + "/Info.plist")
            try FileSystem.write(Data(executable), to: path + "/" + name)
            #expect(chmod(path + "/" + name, 0o755) == 0)
            _ = try CodeSigner.sign(CodeSigner.Request(path: path, identity: "-"))
        }
        try FileSystem.write(Data("{}\n".utf8), to: app + "/data.json")
        if embedding {
            // A back-deployment library: universal, its Info.plist linked in, signed by the archive.
            let library = app + "/Frameworks/libswiftThing.dylib"
            let embeddedInfo = PropertyListValue.xmlDocument(.dictionary(["CFBundleIdentifier": .string("org.nomac.export.thing")]))
            try FileSystem.write(Data(SyntheticMachO.universal([
                SyntheticMachO.machO(executable: false, cpuSubtype: 0x8000_0002, infoPlist: embeddedInfo, minimumOS: 12 << 16 | 2 << 8, seed: 8),
                SyntheticMachO.machO(executable: false, infoPlist: embeddedInfo, minimumOS: 12 << 16 | 2 << 8, seed: 7),
            ])), to: library)
            _ = try CodeSigner.sign(CodeSigner.Request(path: library, identity: "-", force: true))
        }
        // Modes as under the usual umask (022), whatever the test's.
        for path in [app] + (try FileManager.default.subpathsOfDirectory(atPath: app)).map({ app + "/" + $0 }) {
            let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as! Int
            try FileManager.default.setAttributes([.posixPermissions: FileSystem.isDirectory(path) || mode & 0o100 != 0 ? 0o755 : 0o644],
                                                  ofItemAtPath: path)
        }
        let properties: [String: PropertyListValue] = [
            "ApplicationPath": .string("Applications/App.app"), "Architectures": .array([.string("arm64")]),
            "CFBundleIdentifier": .string("org.nomac.export"), "CFBundleShortVersionString": .string("2.1"), "CFBundleVersion": .string("7"),
            "SigningIdentity": .string(""), "Team": .string(team),
        ]
        let info: [String: PropertyListValue] = [
            "ApplicationProperties": .dictionary(properties), "ArchiveVersion": .integer(2), "Name": .string(scheme), "SchemeName": .string(scheme),
        ]
        try FileSystem.write(Data(PropertyListValue.xmlDocument(.dictionary(info))), to: archive + "/Info.plist")
        let dsyms: [(name: String, identifier: String, dwarf: [UInt8])] = [("App", "org.nomac.export", SyntheticDSYM.dwarfFile(seed: 6))]
            + (watch ? [("Watch", "org.nomac.export.watchkitapp", SyntheticMachO.universal([
                SyntheticDSYM.dwarfFile(seed: 10), SyntheticDSYM.dwarfFile(seed: 11, arm64_32: true),
            ]))] : [])
        for dsym in dsyms {
            let contents = archive + "/dSYMs/\(dsym.name).app.dSYM/Contents"
            try FileSystem.createDirectory(contents + "/Resources/DWARF")
            try FileSystem.write(Data(PropertyListValue.xmlDocument(.dictionary([
                "CFBundleDevelopmentRegion": .string("English"), "CFBundleIdentifier": .string("com.apple.xcode.dsym." + dsym.identifier),
                "CFBundleInfoDictionaryVersion": .string("6.0"), "CFBundlePackageType": .string("dSYM"), "CFBundleShortVersionString": .string("2.1"),
                "CFBundleSignature": .string("????"), "CFBundleVersion": .string("7"),
            ]))), to: contents + "/Info.plist")
            try FileSystem.write(Data(dsym.dwarf), to: contents + "/Resources/DWARF/" + dsym.name)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Self.dwarfTime)],
                                                  ofItemAtPath: contents + "/Resources/DWARF/" + dsym.name)
        }
        return archive
    }

    /// The DWARF file's modification time, which the `.symbols` file records.
    static let dwarfTime: TimeInterval = 1_767_323_045

    /// What an app-store-connect export of the archive at `/tmp/observe/symbols` (as
    /// `signing_experiments.py synthetic-export` makes it) wrote for the archive's dSYM: the file
    /// records the DWARF file's real path.
    @Test func writesTheSymbolsXcodeWrites() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-export")
        let archive = try Self.archive(in: temporary.path)
        if let observe = ProcessInfo.processInfo.environment["NOMAC_PACKAGING_OBSERVE"] {
            try? FileManager.default.removeItem(atPath: observe + "/symbols")
            try FileSystem.createDirectory(observe + "/symbols")
            try FileManager.default.copyItem(atPath: archive, toPath: observe + "/symbols/App.xcarchive")
            try FileSystem.write(Data(Self.options.replacingOccurrences(of: "release-testing", with: "app-store-connect").utf8),
                                 to: observe + "/symbols/options.plist")
        }
        let dwarfFile = archive + "/dSYMs/App.app.dSYM/Contents/Resources/DWARF/App"
        #expect(try SymbolsFile.files(dwarfFile: dwarfFile).map(\.name) == ["06172839-4A5B-6C7D-8E9F-B0C1D2E3F405.symbols"])
        let bytes = try SymbolsFile.data(SymbolsFile.slices(at: dwarfFile)[0],
                                         path: "/private/tmp/observe/symbols/App.xcarchive/dSYMs/App.app.dSYM/Contents/Resources/DWARF/App",
                                         modificationTime: Int(Self.dwarfTime))
        #expect(SHA256.digest(bytes).map { String(format: "%02x", $0) }.joined() == "8585ba58e838c175da4827d3b2321dd62550c51710c4c754a41f0ff1693aae07")
    }

    /// A watch app's universal dSYM gives one file per slice; the arm64_32 one keeps the file's
    /// addresses (what the export of `/tmp/observe/watch` wrote, through `synthetic-export`).
    @Test func writesSymbolsForEachSliceOfAUniversalDSYM() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-export")
        let archive = try Self.archive(in: temporary.path, watch: true)
        if let observe = ProcessInfo.processInfo.environment["NOMAC_PACKAGING_OBSERVE"] {
            try? FileManager.default.removeItem(atPath: observe + "/watch")
            try FileSystem.createDirectory(observe + "/watch")
            try FileManager.default.copyItem(atPath: archive, toPath: observe + "/watch/App.xcarchive")
            try FileSystem.write(Data(Self.options.replacingOccurrences(of: "release-testing", with: "app-store-connect").utf8),
                                 to: observe + "/watch/options.plist")
        }
        let dwarfFile = archive + "/dSYMs/Watch.app.dSYM/Contents/Resources/DWARF/Watch"
        #expect(try SymbolsFile.files(dwarfFile: dwarfFile).map(\.name) == [
            "0A1B2C3D-4E5F-7081-92A3-B4C5D6E7F809.symbols", "0B1C2D3E-4F60-7182-93A4-B5C6D7E8F90A.symbols",
        ])
        let digests = try SymbolsFile.slices(at: dwarfFile).map { slice in
            let bytes = try SymbolsFile.data(slice, path: "/private/tmp/observe/watch/App.xcarchive/dSYMs/Watch.app.dSYM/Contents/Resources/DWARF/Watch",
                                             modificationTime: Int(Self.dwarfTime))
            return SHA256.digest(bytes).map { String(format: "%02x", $0) }.joined()
        }
        #expect(digests == [
            "9fe89f497c47837b800d75e4ac6cd88d4d6986760926e1957d60975d4c438358",
            "9962fece6b36bfb0d069c2bc49d20c5a351c18a6462b83825f9d019fd58f2e30",
        ])
    }

    @Test func signsNestedCodeDeepestFirstInNameOrder() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-export")
        let app = try Self.archive(in: temporary.path) + "/Products/Applications/App.app"
        #expect(try ArchiveExporter.nestedCode(in: app) == [
            "Frameworks/Kit.framework", "Frameworks/Zed.framework", "Frameworks/libswiftThing.dylib", "PlugIns/Action.appex", "PlugIns/Share.appex",
        ].map { app + "/" + $0 })
    }

    @Test func exportsWhatXcodeExports() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-export")
        let archive = try Self.archive(in: temporary.path)
        let options = temporary.path + "/options.plist"
        try FileSystem.write(Data(Self.options.utf8), to: options)
        if let observe = ProcessInfo.processInfo.environment["NOMAC_PACKAGING_OBSERVE"] {
            try? FileManager.default.removeItem(atPath: observe + "/export")
            try FileSystem.createDirectory(observe + "/export")
            try FileManager.default.copyItem(atPath: archive, toPath: observe + "/export/App.xcarchive")
            try FileManager.default.copyItem(atPath: options, toPath: observe + "/export/options.plist")
        }
        try ArchiveExporter.export(archive: archive, exportPath: temporary.path + "/out", optionsPath: options)
        let files = try FileSystem.sortedContents(of: temporary.path + "/out")
        #expect(files == ["App.ipa", "DistributionSummary.plist", "ExportOptions.plist"])
        let digests = try files.map { name -> String in
            let bytes = [UInt8](try Data(contentsOf: URL(fileURLWithPath: temporary.path + "/out/" + name)))
            return SHA256.digest(name.hasSuffix(".ipa") ? ZipMachineFields.cleared(bytes) : bytes).map { String(format: "%02x", $0) }.joined()
        }
        #expect(digests == [
            "51ca4a553aee53092d6f2cbfa92e9b33e1493a58f0eab76bb53aac6572896a4f",
            "785ac583b1701caa31195e31ba44a158fcc962a4d22442fd8195892c5ff70d24",
            "6f88b207463dbe41e1295052a537641f797ea4b6eae68b39b0fd02b49b86fd56",
        ])
    }

    /// An app that embeds nothing has no `embeddedBinaries` in its summary (observed with
    /// xcodebuild through `synthetic-export`, and in the `alone` experiment for every method).
    @Test func summarizesAnAppEmbeddingNothing() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-export")
        let archive = try Self.archive(in: temporary.path, embedding: false)
        let options = temporary.path + "/options.plist"
        try FileSystem.write(Data(Self.options.utf8), to: options)
        if let observe = ProcessInfo.processInfo.environment["NOMAC_PACKAGING_OBSERVE"] {
            try? FileManager.default.removeItem(atPath: observe + "/alone")
            try FileSystem.createDirectory(observe + "/alone")
            try FileManager.default.copyItem(atPath: archive, toPath: observe + "/alone/App.xcarchive")
            try FileManager.default.copyItem(atPath: options, toPath: observe + "/alone/options.plist")
        }
        try ArchiveExporter.export(archive: archive, exportPath: temporary.path + "/out", optionsPath: options)
        let digests = try FileSystem.sortedContents(of: temporary.path + "/out").map { name -> String in
            let bytes = [UInt8](try Data(contentsOf: URL(fileURLWithPath: temporary.path + "/out/" + name)))
            return SHA256.digest(name.hasSuffix(".ipa") ? ZipMachineFields.cleared(bytes) : bytes).map { String(format: "%02x", $0) }.joined()
        }
        #expect(digests == [
            "c9110fe33d3a43c68dc171172a328b868a1fbb9c7f94a14ee30ce20e5f5ec0b8",
            "be9e168cc4788ad473a513e12f2d96c7a042f0bea6f3a4a87026a456d520b183",
            "6f88b207463dbe41e1295052a537641f797ea4b6eae68b39b0fd02b49b86fd56",
        ])
    }

    /// debugging, release-testing and enterprise leave App Clips out and name the app's
    /// identifier in `distributionBundleIdentifier` (observed with xcodebuild through
    /// `synthetic-export`).
    @Test func leavesAppClipsOut() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-export")
        let archive = try Self.archive(in: temporary.path, clip: true)
        let options = temporary.path + "/options.plist"
        try FileSystem.write(Data(Self.options.utf8), to: options)
        if let observe = ProcessInfo.processInfo.environment["NOMAC_PACKAGING_OBSERVE"] {
            try? FileManager.default.removeItem(atPath: observe + "/clip")
            try FileSystem.createDirectory(observe + "/clip")
            try FileManager.default.copyItem(atPath: archive, toPath: observe + "/clip/App.xcarchive")
            try FileManager.default.copyItem(atPath: options, toPath: observe + "/clip/options.plist")
        }
        try ArchiveExporter.export(archive: archive, exportPath: temporary.path + "/out", optionsPath: options)
        let digests = try FileSystem.sortedContents(of: temporary.path + "/out").map { name -> String in
            let bytes = [UInt8](try Data(contentsOf: URL(fileURLWithPath: temporary.path + "/out/" + name)))
            return SHA256.digest(name.hasSuffix(".ipa") ? ZipMachineFields.cleared(bytes) : bytes).map { String(format: "%02x", $0) }.joined()
        }
        #expect(digests == [
            "3bb073bc61e92b573c60397ba88de8715b5d58669edd233969b59482a5c91892",
            "785ac583b1701caa31195e31ba44a158fcc962a4d22442fd8195892c5ff70d24",
            "90fbd521b85f93ef7643a5ffdf5799e60dc63a57f805e3433abc802fffdc2493",
        ])
    }

    /// Observed in the `refusals` experiment (an export without `teamID`).
    /// The OTA install manifest of a `manifest` export option (`manifest` experiment), for an
    /// app whose bundle name, display name, file name and scheme differ (what xcodebuild wrote
    /// for this archive, through `synthetic-export`); without the image URLs xcodebuild refuses
    /// the options.
    @Test(arguments: [("manifest", true), ("manifest-app-url", false)])
    func writesTheInstallManifest(name: String, images: Bool) throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-export")
        let archive = try Self.archive(in: temporary.path, appInfo: ["CFBundleName": .string("Named"), "CFBundleDisplayName": .string("Shown")],
                                       scheme: "Scheme")
        let manifest = "\t<key>manifest</key>\n\t<dict>\n\t\t<key>appURL</key>\n\t\t<string>https://example.com/nomac/App.ipa</string>\n"
            + (images ? "\t\t<key>displayImageURL</key>\n\t\t<string>https://example.com/nomac/display.png</string>\n"
                + "\t\t<key>fullSizeImageURL</key>\n\t\t<string>https://example.com/nomac/full-size.png</string>\n" : "")
            + "\t</dict>\n"
        let options = temporary.path + "/options.plist"
        try FileSystem.write(Data(Self.options.replacingOccurrences(of: "\t<key>method</key>", with: manifest + "\t<key>method</key>").utf8), to: options)
        if let observe = ProcessInfo.processInfo.environment["NOMAC_PACKAGING_OBSERVE"] {
            try? FileManager.default.removeItem(atPath: observe + "/" + name)
            try FileSystem.createDirectory(observe + "/" + name)
            try FileManager.default.copyItem(atPath: archive, toPath: observe + "/\(name)/App.xcarchive")
            try FileManager.default.copyItem(atPath: options, toPath: observe + "/\(name)/options.plist")
        }
        guard images else {
            #expect(throws: ArchiveExporter.missingManifestData) {
                try ArchiveExporter.export(archive: archive, exportPath: temporary.path + "/out", optionsPath: options)
            }
            return
        }
        try ArchiveExporter.export(archive: archive, exportPath: temporary.path + "/out", optionsPath: options)
        #expect(try FileSystem.sortedContents(of: temporary.path + "/out") == ["DistributionSummary.plist", "ExportOptions.plist", "Named.ipa", "manifest.plist"])
        #expect(try AppStoreExportTests.digests(of: temporary.path + "/out") == [
            "52ff81e86070aa9afa98cdb5820dd385ee69f674f429a61b135e2559c645862a",
            "eb928b078cd7f517117222f03a9bf60d53c4c55b6d36e0ea8f7bbf00cb542a77",
            "c9bde07c631f9e3ac7814cce4896e977a7b1234b1af2bb8ed0d817de2d2bbb00",
            "11d73a3fc7dddcba3a387061070a38b862ffca7193b4ad416faf7fc332b7081f",
        ])
    }

    @Test func needsATeam() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-export")
        let archive = try Self.archive(in: temporary.path)
        let options = temporary.path + "/options.plist"
        try FileSystem.write(Data(Self.options.replacingOccurrences(of: "\t<key>teamID</key>\n\t<string>NOMAC00000</string>\n", with: "").utf8), to: options)
        #expect(throws: NomacError("exportArchive No Team Found in Archive", notes: [
            "Use the Signing & Capabilities editor to assign a team to the targets and build a new archive.",
        ], exitStatus: 70)) {
            try ArchiveExporter.export(archive: archive, exportPath: temporary.path + "/out", optionsPath: options)
        }
    }

    /// Xcode refuses to export an ad-hoc signed app with entitlements (`refusals` experiment: an
    /// archive whose app was signed again with an entitlements file).
    /// An item signed with an empty entitlements dictionary needs no profile (signing-experiments
    /// `entitlements-empty`, expo-default's archive); what xcodebuild exported for this archive
    /// through `synthetic-export`.
    @Test func exportsAnAppWithEmptyEntitlements() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-export")
        let archive = try Self.archive(in: temporary.path, embedding: false)
        let entitlements = temporary.path + "/app.entitlements"
        try FileSystem.write(Data(PropertyListValue.xmlDocument(.dictionary([:]))), to: entitlements)
        _ = try CodeSigner.sign(CodeSigner.Request(path: archive + "/Products/Applications/App.app", identity: "-", force: true, entitlementsPath: entitlements))
        let options = temporary.path + "/options.plist"
        try FileSystem.write(Data(Self.options.utf8), to: options)
        if let observe = ProcessInfo.processInfo.environment["NOMAC_PACKAGING_OBSERVE"] {
            try? FileManager.default.removeItem(atPath: observe + "/empty-entitlements")
            try FileSystem.createDirectory(observe + "/empty-entitlements")
            try FileManager.default.copyItem(atPath: archive, toPath: observe + "/empty-entitlements/App.xcarchive")
            try FileManager.default.copyItem(atPath: options, toPath: observe + "/empty-entitlements/options.plist")
        }
        try ArchiveExporter.export(archive: archive, exportPath: temporary.path + "/out", optionsPath: options)
        let digests = try FileSystem.sortedContents(of: temporary.path + "/out").map { name -> String in
            let bytes = [UInt8](try Data(contentsOf: URL(fileURLWithPath: temporary.path + "/out/" + name)))
            return SHA256.digest(name.hasSuffix(".ipa") ? ZipMachineFields.cleared(bytes) : bytes).map { String(format: "%02x", $0) }.joined()
        }
        #expect(digests == [
            "c9110fe33d3a43c68dc171172a328b868a1fbb9c7f94a14ee30ce20e5f5ec0b8",
            "be9e168cc4788ad473a513e12f2d96c7a042f0bea6f3a4a87026a456d520b183",
            "6f88b207463dbe41e1295052a537641f797ea4b6eae68b39b0fd02b49b86fd56",
        ])
    }

    /// xcodebuild takes the old names, logging that they are deprecated, and gives the same export
    /// with the new name in `ExportOptions.plist` (observed with an ad hoc archive, 2026-11-07).
    @Test(arguments: [("development", "debugging"), ("ad-hoc", "release-testing")])
    func deprecatedMethodNames(old: String, current: String) throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-export")
        let archive = try Self.archive(in: temporary.path)
        let options = temporary.path + "/options.plist"
        try FileSystem.write(Data(Self.options.replacingOccurrences(of: "release-testing", with: old).utf8), to: options)
        try ArchiveExporter.export(archive: archive, exportPath: temporary.path + "/out", optionsPath: options)
        let written = try #require(FileManager.default.contents(atPath: temporary.path + "/out/ExportOptions.plist"))
        #expect(String(decoding: written, as: UTF8.self).contains("<string>\(current)</string>"))
        #expect(!String(decoding: written, as: UTF8.self).contains("<string>\(old)</string>"))
    }

    @Test func anExportWithoutACertificateSaysWhatToSet() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-export")
        let archive = try Self.archive(in: temporary.path)
        let options = temporary.path + "/options.plist"
        try FileSystem.write(Data("<plist version=\"1.0\"><dict><key>method</key><string>debugging</string></dict></plist>".utf8), to: options)
        #expect(throws: NomacError("exportArchive exports without signingCertificate are not supported yet (BACKLOG B-302)", notes: [ArchiveExporter.signingNote], exitStatus: 70)) {
            try ArchiveExporter.export(archive: archive, exportPath: temporary.path + "/out", optionsPath: options)
        }
    }

    @Test func refusesItemsWithEntitlements() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-export")
        let archive = try Self.archive(in: temporary.path)
        let entitlements = temporary.path + "/app.entitlements"
        try FileSystem.write(Data(PropertyListValue.xmlDocument(.dictionary(["get-task-allow": .boolean(true)]))), to: entitlements)
        _ = try CodeSigner.sign(CodeSigner.Request(path: archive + "/Products/Applications/App.app", identity: "-", force: true, entitlementsPath: entitlements))
        let options = temporary.path + "/options.plist"
        try FileSystem.write(Data(Self.options.utf8), to: options)
        #expect(throws: NomacError("exportArchive \"App.app\" requires a provisioning profile.", notes: [
            "Enable development signing and select a provisioning profile in the Signing & Capabilities editor.",
            ArchiveExporter.signingNote,
        ], exitStatus: 70)) {
            try ArchiveExporter.export(archive: archive, exportPath: temporary.path + "/out", optionsPath: options)
        }
    }
}

/// A zip archive with what depends on the machine and the clock cleared: the DOS time and date of
/// every local and central header, the whole "UX" extra field (times, owner and group) and the
/// mode of `Payload/`, which follows the umask (Xcode's too: 040775 under umask 002, `umask`
/// experiment).
enum ZipMachineFields {
    /// `archive` without the central directory's extra fields: an asset pack's zip has one only
    /// for a file whose access time is not its modification time, which depends on the machine.
    static func withoutCentralExtras(_ archive: [UInt8]) -> [UInt8] {
        func u16(_ at: Int) -> Int { Int(archive[at]) | Int(archive[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        let end = archive.count - 22, start = u32(end + 16)
        var central: [UInt8] = [], position = start
        for _ in 0..<u16(end + 10) {
            let nameEnd = position + 46 + u16(position + 28), extraLength = u16(position + 30), commentLength = u16(position + 32)
            central += archive[position..<(position + 30)] + [0, 0] + archive[(position + 32)..<nameEnd]
            central += archive[(nameEnd + extraLength)..<(nameEnd + extraLength + commentLength)]
            position = nameEnd + extraLength + commentLength
        }
        var record = Array(archive[end...])
        record.replaceSubrange(12..<16, with: LittleEndian.u32(UInt32(central.count)))
        return Array(archive[..<start]) + central + record
    }

    static func cleared(_ archive: [UInt8]) -> [UInt8] {
        var bytes = archive
        func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        func clearExtra(_ start: Int, _ length: Int) {
            var field = start
            while field + 4 <= start + length {
                if u16(field) == 0x5855 {
                    bytes.replaceSubrange((field + 4)..<(field + 4 + u16(field + 2)), with: [UInt8](repeating: 0, count: u16(field + 2)))
                }
                field += 4 + u16(field + 2)
            }
        }
        let end = bytes.count - 22
        var central = u32(end + 16)
        for _ in 0..<u16(end + 10) {
            let nameLength = u16(central + 28), extraLength = u16(central + 30), commentLength = u16(central + 32)
            let local = u32(central + 42)
            bytes.replaceSubrange((central + 12)..<(central + 16), with: [0, 0, 0, 0])
            if Array(bytes[(central + 46)..<(central + 46 + nameLength)]) == Array("Payload/".utf8) {
                bytes.replaceSubrange((central + 38)..<(central + 42), with: [0, 0, 0, 0])
            }
            clearExtra(central + 46 + nameLength, extraLength)
            bytes.replaceSubrange((local + 10)..<(local + 14), with: [0, 0, 0, 0])
            clearExtra(local + 30 + u16(local + 26), u16(local + 28))
            central += 46 + nameLength + extraLength + commentLength
        }
        return bytes
    }
}
