import CSQLite
import Foundation
import NomacAssets
import NomacCore
import NomacPlist
import NomacTestSupport
import Testing
@testable import NomacPackaging

/// App thinning (docs/formats/ipa.md "App thinning"; `distribution_experiments.py thinning`,
/// whose exports `compare-thinning` finds identical to nomac's): here with a self-written
/// `device_traits.db` in the database's layout.
@Suite struct AppThinningTests {
    /// (product type, OS version, trait set) rows, and trait sets as (idiom, scale, subtype,
    /// graphics, its fallbacks, memory).
    static let rows: [(String, String, Int)] = [
        ("iPhone11,8", "18.0", 1), ("iPhone11,8", "26.0", 1), ("iPhone12,3", "18.0", 2), ("iPhone12,3", "26.0", 2),
        ("iPad13,1", "18.0", 3), ("iPad13,1", "26.0", 3), ("MacFamily20,1", "26.0", 4), ("iPhone9,1", "17.0", 1),
    ]
    static let traitSets: [Int: (String, Int, Int?, String, String, Int)] = [
        1: ("phone", 2, 1792, "APPLE5", "APPLE4:APPLE3:APPLE3v1:APPLE2:APPLE1:GLES2,0", 4),
        2: ("phone", 3, 2436, "APPLE6", "APPLE5:APPLE4:APPLE3:APPLE3v1:APPLE2:APPLE1:GLES2,0", 3),
        3: ("pad", 2, 2388, "APPLE8", "APPLE7:APPLE6:APPLE5:APPLE4:APPLE3:APPLE3v1:APPLE2:APPLE1:GLES2,0", 8),
        4: ("pad", 2, 32401, "APPLE6", "APPLE5:APPLE4:APPLE3:APPLE3v1:APPLE2:APPLE1:GLES2,0", 16),
    ]

    static func database(in developerDirectory: String) throws {
        let path = developerDirectory + "/" + AppThinning.databasePath
        try FileSystem.createDirectory((path as NSString).deletingLastPathComponent)
        var database: OpaquePointer?
        #expect(sqlite3_open(path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        var statements = [
            "create table DeploymentTarget (TargetVersion text, DeploymentTarget integer)",
            "create table Devices (Target text, ProductType text, ThinningConfiguration text)",
            "create table DeviceTraits (DeviceTraitSetID integer, ArtworkDeviceIdiom text, ArtworkScaleFactor integer, ArtworkDeviceSubtype integer, "
                + "ArtworkDeviceSubtypeFallbacks text, ArtworkDisplayGamut text, ArtworkHostedIdioms text, GraphicsFeatureSetClass text, "
                + "GraphicsFeatureSetFallbacks text, DevicePerformanceMemoryClass integer)",
            "create table DeploymentVariant (DeploymentTarget text, DeviceTarget text, DeviceTraitSet integer, TargetArchitecture text, ThinningConfiguration text)",
        ]
        statements += [("13.0", 5), ("17.0", 9), ("18.0", 11), ("26.0", 12)].map { "insert into DeploymentTarget values ('\($0.0)', \($0.1))" }
        for product in Set(rows.map(\.0)) { statements.append("insert into Devices values ('board-\(product)', '\(product)', null)") }
        for (id, set) in traitSets {
            let hosted = set.0 == "phone" ? "'car'" : "null"
            statements.append("insert into DeviceTraits values (\(id), '\(set.0)', \(set.1), \(set.2.map(String.init) ?? "null"), null, 'P3', "
                              + "\(hosted), '\(set.3)', '\(set.4)', \(set.5))")
        }
        for (product, version, set) in rows { statements.append("insert into DeploymentVariant values ('\(version)', 'board-\(product)', \(set), 'arm64e', null)") }
        for statement in statements { #expect(sqlite3_exec(database, statement, nil, nil, nil) == SQLITE_OK, "\(statement)") }
    }

    static func options(_ method: String = "release-testing") -> String {
        ArchiveExporterTests.options.replacingOccurrences(of: "release-testing", with: method)
            .replacingOccurrences(of: "\t<key>teamID</key>", with: "\t<key>thinning</key>\n\t<string>&lt;thin-for-all-variants&gt;</string>\n\t<key>teamID</key>")
    }

    /// The synthetic archive's app with its Info.plist binary, as Swift Build writes it.
    static func binaryInfoPlist(_ archive: String) throws {
        let path = archive + "/Products/Applications/App.app/Info.plist"
        let value = try TextPropertyListParser.parse(try String(contentsOfFile: path, encoding: .utf8))
        try FileSystem.write(BinaryPropertyList.swiftBuildData(value), to: path)
    }

    @Test func oneVariantWithoutACatalog() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-thinning")
        let archive = try ArchiveExporterTests.archive(in: temporary.path, embedding: false)
        try Self.binaryInfoPlist(archive)
        try Self.database(in: temporary.path + "/Developer")
        try FileSystem.write(Data(Self.options().utf8), to: temporary.path + "/options.plist")
        try ArchiveExporter.export(archive: archive, exportPath: temporary.path + "/out", optionsPath: temporary.path + "/options.plist",
                                   developerDirectory: temporary.path + "/Developer")
        let out = temporary.path + "/out"
        #expect(try FileSystem.sortedContents(of: out) == ["App Thinning Size Report.txt", "Apps", "DistributionSummary.plist", "ExportOptions.plist", "app-thinning.plist"])
        let variants = try FileSystem.sortedContents(of: out + "/Apps")
        #expect(variants.count == 2 && variants[1] == "App.ipa" && variants[0].hasPrefix("App-") && variants[0].hasSuffix(".ipa"))

        // The universal IPA is the export's without thinning.
        try FileSystem.write(Data(ArchiveExporterTests.options.utf8), to: temporary.path + "/plain.plist")
        try ArchiveExporter.export(archive: archive, exportPath: temporary.path + "/plain", optionsPath: temporary.path + "/plain.plist")
        let universal = [UInt8](try Data(contentsOf: URL(fileURLWithPath: out + "/Apps/App.ipa")))
        let plain = [UInt8](try Data(contentsOf: URL(fileURLWithPath: temporary.path + "/plain/App.ipa")))
        #expect(ZipMachineFields.cleared(universal) == ZipMachineFields.cleared(plain))

        let thinning = try PropertyLists.readDictionary(at: out + "/app-thinning.plist")["variants"] as? [String: [String: Any]] ?? [:]
        let descriptors = (thinning["Apps/" + variants[0]]?["variantDescriptors"] as? [[String: String]] ?? []).map { "\($0["device"]!) \($0["os-version"]!)" }
        #expect(descriptors == ["MacFamily20,1 26.0", "iPad13,1 18.0", "iPad13,1 26.0", "iPhone11,8 18.0", "iPhone11,8 26.0", "iPhone12,3 18.0", "iPhone12,3 26.0"])
        #expect(thinning["Apps/App.ipa"]?["variantDescriptors"] == nil && thinning["Apps/App.ipa"]?["sizeCompressedApp"] as? Int == universal.count)
        let report = try String(contentsOfFile: out + "/App Thinning Size Report.txt", encoding: .utf8)
        #expect(report.hasPrefix("\nApp Thinning Size Report for All Variants of App\n\nVariant: \(variants[0])\nSupported variant descriptors: "
                                 + "[device: MacFamily20,1, os-version: 26.0], [device: iPad13,1, os-version: 18.0], "))
        #expect(report.contains(", and [device: iPhone12,3, os-version: 26.0]\nApp + On Demand Resources size: ")
                && report.hasSuffix("Variant: App.ipa\nSupported variant descriptors: Universal\nApp + On Demand Resources size: \((universal.count + 500) / 1000) KB compressed, "
                                    + "\(((thinning["Apps/App.ipa"]?["sizeUncompressedApp"] as? Int ?? 0) + 500) / 1000) KB uncompressed\n"
                                    + "App size: \((universal.count + 500) / 1000) KB compressed, \(((thinning["Apps/App.ipa"]?["sizeUncompressedApp"] as? Int ?? 0) + 500) / 1000) KB uncompressed\n"
                                    + "On Demand Resources size: Zero KB compressed, Zero KB uncompressed\n"))
        // The same export names its variants the same.
        try ArchiveExporter.export(archive: archive, exportPath: temporary.path + "/again", optionsPath: temporary.path + "/options.plist",
                                   developerDirectory: temporary.path + "/Developer")
        #expect(try FileSystem.sortedContents(of: temporary.path + "/again/Apps") == variants)
    }

    @Test func variantsByWhatTheCatalogKeeps() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-thinning")
        let archive = try ArchiveExporterTests.archive(in: temporary.path, embedding: false)
        try Self.database(in: temporary.path + "/Developer")
        let car = try Self.catalog(in: temporary.path + "/catalog")
        let app = archive + "/Products/Applications/App.app"
        try FileSystem.writeExactly(car, to: app + "/Assets.car")
        let variants = try AppThinning.variants(app: app, items: [app], developerDirectory: temporary.path + "/Developer")
        let groups = Set(variants.map { Set($0.descriptors.map(\.device)) })
        #expect(groups == [["iPhone11,8"], ["iPhone12,3"], ["MacFamily20,1", "iPad13,1"]])
        // Each thinned for its first descriptor: the Mac (trait set 4) for the iPad group.
        let pad = try #require(variants.first { $0.descriptors.contains { $0.device == "iPad13,1" } })
        let mac = ThinningTraits(idiom: "pad", scale: 2, subtype: 32401, subtypeFallbacks: nil, displayGamut: "P3", hostedIdioms: [], graphicsClass: "APPLE6",
                                 graphicsFallbacks: ["APPLE5", "APPLE4", "APPLE3", "APPLE3v1", "APPLE2", "APPLE1", "GLES2,0"], memory: 16, deploymentTarget: "18.0")
        #expect(pad.catalogs == ["": try CARThinning.thin(car, for: mac, path: "Assets.car")])
        // A bundle of the app's code with a catalog: thinned for the same descriptor (`thinning`
        // `nested`).
        try FileSystem.createDirectory(app + "/PlugIns/Share.appex")
        try FileSystem.writeExactly(car, to: app + "/PlugIns/Share.appex/Assets.car")
        let nested = try AppThinning.variants(app: app, items: [app + "/PlugIns/Share.appex", app], developerDirectory: temporary.path + "/Developer")
        let nestedPad = try #require(nested.first { $0.descriptors.contains { $0.device == "iPad13,1" } })
        #expect(Set(nested.map { Set($0.descriptors.map(\.device)) }) == groups && nestedPad.catalogs == pad.catalogs.merging(["/PlugIns/Share.appex": pad.catalogs[""]!]) { $1 })
    }

    /// The thinning experiment's three image sets, compiled by nomac's actool.
    static func catalog(in directory: String) throws -> [UInt8] {
        let catalog = directory + "/Assets.xcassets"
        func json(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }
        try FileSystem.write(json(["info": ["author": "xcode", "version": 1]]), to: catalog + "/Contents.json")
        for (set, renditions) in [("shared", [("universal", 1), ("iphone", 2), ("iphone", 3), ("ipad", 2)]), ("pad-only", [("ipad", 2)]), ("phone-low", [("iphone", 1)])] {
            var entries: [[String: Any]] = []
            for (index, (idiom, scale)) in renditions.enumerated() {
                let width = 8 * scale + index, height = 8 * scale
                let pixel: [UInt8] = [UInt8(40 * scale), UInt8(30 * index), 200]
                let rows = [[UInt8]](repeating: (0..<width).flatMap { _ in pixel }, count: height)
                try FileSystem.write(Data(Self.png(width: width, height: height, rows: rows)), to: "\(catalog)/\(set).imageset/\(idiom)@\(scale)x.png")
                entries.append(["idiom": idiom, "scale": "\(scale)x", "filename": "\(idiom)@\(scale)x.png"])
            }
            try FileSystem.write(json(["images": entries, "info": ["author": "xcode", "version": 1]]), to: "\(catalog)/\(set).imageset/Contents.json")
        }
        _ = try Actool.run(try Actool.Options(arguments: [catalog, "--compile", directory, "--platform", "iphoneos", "--minimum-deployment-target", "18.0",
                                                          "--target-device", "iphone", "--target-device", "ipad", "--output-partial-info-plist", directory + "/partial.plist"]))
        return [UInt8](try Data(contentsOf: URL(fileURLWithPath: directory + "/Assets.car")))
    }

    /// An RGB PNG of `rows`, its image data in one stored zlib block.
    static func png(width: Int, height: Int, rows: [[UInt8]]) -> [UInt8] {
        func be(_ value: UInt32) -> [UInt8] { [UInt8(value >> 24), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)] }
        func crc(_ bytes: [UInt8]) -> UInt32 {
            var c: UInt32 = 0xFFFF_FFFF
            for byte in bytes {
                c ^= UInt32(byte)
                for _ in 0..<8 { c = c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
            }
            return ~c
        }
        func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
            let typed: [UInt8] = Array(type.utf8) + body
            return be(UInt32(body.count)) + typed + be(crc(typed))
        }
        var raw: [UInt8] = []
        for row in rows { raw += [0] + row }
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in raw {
            a = (a + UInt32(byte)) % 65_521
            b = (b + a) % 65_521
        }
        let length = UInt16(raw.count)
        var zlib: [UInt8] = [0x78, 0x01, 1, UInt8(length & 0xFF), UInt8(length >> 8), UInt8(~length & 0xFF), UInt8(~length >> 8)]
        zlib += raw
        zlib += be(b << 16 | a)
        var header = be(UInt32(width)) + be(UInt32(height))
        header += [8, 2, 0, 0, 0]
        var file: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        file += chunk("IHDR", header)
        file += chunk("IDAT", zlib)
        file += chunk("IEND", [])
        return file
    }

    /// The thinning experiment app's Info.plist values (Swift Build's keys and one of each type),
    /// rewritten for its iPhone @2x variant: xcodebuild's file byte for byte.
    @Test func infoPlistAsTheVariantsHaveIt() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-thinning")
        let strings = ["BuildMachineOSBuild": "26A434", "CFBundleDevelopmentRegion": "en", "CFBundleExecutable": "App", "CFBundleIdentifier": "org.nomac.signing",
                       "CFBundleInfoDictionaryVersion": "6.0", "CFBundleName": "App", "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "1.0",
                       "CFBundleVersion": "1", "DTCompiler": "com.apple.compilers.llvm.clang.1_0", "DTPlatformBuild": "24A430", "DTPlatformName": "iphoneos",
                       "DTPlatformVersion": "27.0", "DTSDKBuild": "24A430", "DTSDKName": "iphoneos27.0", "DTXcode": "2700", "DTXcodeBuild": "27A266a",
                       "MinimumOSVersion": "18.0", "NomacEscaped": "a & b < c > d \" ' é", "UILaunchStoryboardName": ""]
        var entries: [String: PropertyListValue] = strings.mapValues { .string($0) }
        entries["CFBundleSupportedPlatforms"] = .array([.string("iPhoneOS")])
        entries["LSRequiresIPhoneOS"] = .boolean(true)
        entries["NomacData"] = .data([0, 1] + Array("nomac".utf8))
        entries["NomacDate"] = .date(815_400_000)
        entries["NomacEmptyArray"] = .array([])
        entries["NomacFalse"] = .boolean(false)
        entries["NomacNegative"] = .integer(-7)
        entries["NomacNested"] = .dictionary(["Alpha": .array([.integer(1), .real(2.5), .boolean(false)]), "Empty": .dictionary([:]), "Zeta": .string("z")])
        entries["NomacReal"] = .real(0.25)
        entries["UIApplicationSupportsIndirectInputEvents"] = .boolean(true)
        entries["UIDeviceFamily"] = .array([.integer(1), .integer(2)])
        entries["UIRequiredDeviceCapabilities"] = .array([.string("arm64")])
        let path = temporary.path + "/Info.plist"
        try FileSystem.write(BinaryPropertyList.swiftBuildData(.dictionary(entries)), to: path)
        try ThinnedInfoPlist.rewrite(at: path, devices: ["iPhone14,6", "iPhone11,8", "iPhone12,8", "iPhone12,1"])
        let written = [UInt8](try Data(contentsOf: URL(fileURLWithPath: path)))
        #expect(SHA256.digest(written).map { String(format: "%02x", $0) }.joined() == "874add3feb90e085a7908536fd3266da281b550f0fe2c28c999ce00f7d574175")
    }

    /// A minimum the database does not list counts as the last listed version before it
    /// (`thinning` `catalog-185`), and thinning for one device writes its variant alone
    /// (`thinning-iPhone12,3`).
    @Test func minimumBetweenVersionsAndOneDevice() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-thinning")
        let archive = try ArchiveExporterTests.archive(in: temporary.path, embedding: false)
        try Self.database(in: temporary.path + "/Developer")
        let app = archive + "/Products/Applications/App.app"
        var info = try PropertyLists.readDictionary(at: app + "/Info.plist")
        info["MinimumOSVersion"] = "18.5"
        try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0).write(to: URL(fileURLWithPath: app + "/Info.plist"))
        let variants = try AppThinning.variants(app: app, items: [app], developerDirectory: temporary.path + "/Developer")
        #expect(variants.flatMap(\.descriptors).map(\.osVersion).sorted().first == "18.0")

        try FileSystem.write(Data(Self.options().replacingOccurrences(of: "&lt;thin-for-all-variants&gt;", with: "iPhone12,3").utf8), to: temporary.path + "/one.plist")
        try ArchiveExporter.export(archive: archive, exportPath: temporary.path + "/one", optionsPath: temporary.path + "/one.plist",
                                   developerDirectory: temporary.path + "/Developer")
        let files = try FileSystem.sortedContents(of: temporary.path + "/one")
        #expect(files.count == 5 && !files.contains("Apps") && files.contains { $0.hasPrefix("App-") && $0.hasSuffix(".ipa") })
        let thinning = try PropertyLists.readDictionary(at: temporary.path + "/one/app-thinning.plist")["variants"] as? [String: Any] ?? [:]
        #expect(Array(thinning.keys) == files.filter { $0.hasPrefix("App-") })
    }

    /// Sizes as the report writes them (`thinning` `large`, `large-3`, `odr` and the others).
    @Test func reportSizes() throws {
        #expect(try [0, 314, 23296, 208_868, 2_371_130, 2_570_513, 3_000_642, 3_199_835].map(AppThinning.size)
            == ["Zero KB", "314 bytes", "23 KB", "209 KB", "2.4 MB", "2.6 MB", "3 MB", "3.2 MB"])
    }

    /// The thinning experiment's watch app's Info.plist values (Swift Build's keys, sorted): its
    /// placeholder as xcodebuild wrote it, byte for byte (`thinning` `watch`).
    @Test func watchPlaceholderAsXcodeWritesIt() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-thinning")
        let strings = ["BuildMachineOSBuild": "26A434", "CFBundleDevelopmentRegion": "en", "CFBundleDisplayName": "Watch", "CFBundleExecutable": "Watch",
                       "CFBundleIdentifier": "org.nomac.signing.watchkitapp", "CFBundleInfoDictionaryVersion": "6.0", "CFBundleName": "Watch",
                       "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1", "DTCompiler": "com.apple.compilers.llvm.clang.1_0",
                       "DTPlatformBuild": "24R360", "DTPlatformName": "watchos", "DTPlatformVersion": "27.0", "DTSDKBuild": "24R360", "DTSDKName": "watchos27.0",
                       "DTXcode": "2700", "DTXcodeBuild": "27A266a", "MinimumOSVersion": "11.0", "MinimumOSVersion~ipad": "9.0",
                       "WKCompanionAppBundleIdentifier": "org.nomac.signing"]
        var entries: [String: PropertyListValue] = strings.mapValues { .string($0) }
        entries["CFBundleSupportedPlatforms"] = .array([.string("WatchOS")])
        entries["UIDeviceFamily"] = .array([.integer(4)])
        entries["UISupportedInterfaceOrientations"] = .array([.string("UIInterfaceOrientationPortrait"), .string("UIInterfaceOrientationPortraitUpsideDown")])
        entries["WKApplication"] = .boolean(true)
        let watch = temporary.path + "/App.app/Watch/Watch.app"
        try FileSystem.write(BinaryPropertyList.swiftBuildData(.dictionary(entries)), to: watch + "/Info.plist")
        let slices = [AppThinning.Slice(architecture: "arm64", cpuType: 0x0100_000C, cpuSubtype: 0, bytes: []),
                      AppThinning.Slice(architecture: "arm64_32", cpuType: 0x0200_000C, cpuSubtype: 1, bytes: [])]
        try WatchPlaceholder.write(watch: watch, slices: slices, into: temporary.path + "/App.app", constructorVersion: "26A434")
        let written = [UInt8](try Data(contentsOf: URL(fileURLWithPath: temporary.path + "/App.app/com.apple.WatchPlaceholder/Watch.app/Info.plist")))
        #expect(SHA256.digest(written).map { String(format: "%02x", $0) }.joined() == "937ed9d7aac2e85d0c03809a448e0b52d811e7c03c14ea61372d529af9793286")
    }

    /// Watch variants by the slice each watch runs (`thinning` `watch`, `watch-9`): arm64e watches
    /// take the arm64 slice and declare its watches' earliest OS; arm64_32 ones keep the app's
    /// minimum, older than their slice's.
    @Test func watchVariantsBySlice() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-thinning")
        let developer = temporary.path + "/Developer"
        let path = developer + "/" + AppThinning.watchDatabasePath
        try FileSystem.createDirectory((path as NSString).deletingLastPathComponent)
        var database: OpaquePointer?
        #expect(sqlite3_open(path, &database) == SQLITE_OK)
        let fallbacks = "APPLE4:APPLE3:APPLE2:GLES2,0"
        var statements = [
            "create table DeploymentTarget (TargetVersion text, DeploymentTarget integer)",
            "create table Devices (Target text, ProductType text, ThinningConfiguration text)",
            "create table DeviceTraits (DeviceTraitSetID integer, ArtworkDeviceIdiom text, ArtworkScaleFactor integer, ArtworkDeviceSubtype integer, "
                + "ArtworkDeviceSubtypeFallbacks text, ArtworkDisplayGamut text, ArtworkHostedIdioms text, GraphicsFeatureSetClass text, "
                + "GraphicsFeatureSetFallbacks text, DevicePerformanceMemoryClass integer)",
            "create table DeploymentVariant (DeploymentTarget text, DeviceTarget text, DeviceTraitSet integer, TargetArchitecture text, ThinningConfiguration text)",
            "insert into DeviceTraits values (1, 'watch', 2, 340, null, 'P3', null, 'APPLE5', '\(fallbacks)', 15)",
        ]
        statements += [("9.0", 8), ("10.0", 9), ("11.0", 11), ("26.0", 12), ("27.0", 13)].map { "insert into DeploymentTarget values ('\($0.0)', \($0.1))" }
        statements += ["Watch5,1", "Watch6,1", "Watch7,1"].map { "insert into Devices values ('board-\($0)', '\($0)', null)" }
        for (product, version, architecture) in [("Watch6,1", "11.0", "arm64_32"), ("Watch6,1", "26.0", "arm64_32"), ("Watch7,1", "26.0", "arm64"),
                                                 ("Watch7,1", "27.0", "arm64e"), ("Watch5,1", "10.0", "arm64_32")] {
            statements.append("insert into DeploymentVariant values ('\(version)', 'board-\(product)', 1, '\(architecture)', null)")
        }
        for statement in statements { #expect(sqlite3_exec(database, statement, nil, nil, nil) == SQLITE_OK, "\(statement)") }
        sqlite3_close(database)

        let watch = temporary.path + "/Watch.app"
        try FileSystem.write(BinaryPropertyList.swiftBuildData(.dictionary(["MinimumOSVersion": .string("10.0"), "CFBundleExecutable": .string("Watch")])),
                             to: watch + "/Info.plist")
        let binary = SyntheticMachO.universal([SyntheticMachO.machO(platform: 4, minimumOS: 26 << 16, seed: 1),
                                               SyntheticMachO.machO(arm64_32: true, platform: 4, minimumOS: 11 << 16, seed: 2)])
        try FileSystem.writeExactly(binary, to: watch + "/Watch")
        let variants = try AppThinning.watchVariants(watch: watch, executable: watch + "/Watch", developerDirectory: developer)
        #expect(variants.map(\.slice.architecture).sorted() == ["arm64", "arm64_32"])
        let arm64 = try #require(variants.first { $0.slice.architecture == "arm64" })
        #expect(arm64.minimum == "26.0" && arm64.descriptors.map { "\($0.device) \($0.osVersion)" } == ["Watch7,1 26.0", "Watch7,1 27.0"])
        let arm64_32 = try #require(variants.first { $0.slice.architecture == "arm64_32" })
        #expect(arm64_32.minimum == "10.0" && arm64_32.descriptors.map { "\($0.device) \($0.osVersion)" } == ["Watch5,1 10.0", "Watch6,1 11.0", "Watch6,1 26.0"])
    }

    @Test func refusesWhatIsNotObserved() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-thinning")
        let archive = try ArchiveExporterTests.archive(in: temporary.path, embedding: false)
        try Self.database(in: temporary.path + "/Developer")
        let app = archive + "/Products/Applications/App.app"
        var info = try PropertyLists.readDictionary(at: app + "/Info.plist")
        info["MinimumOSVersion"] = "12.0"
        try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0).write(to: URL(fileURLWithPath: app + "/Info.plist"))
        #expect(throws: NomacError("exportArchive app thinning of apps for iOS 12.0 is not supported yet (BACKLOG B-465)",
                                   notes: ["observed for a MinimumOSVersion of 13.0 or later"], exitStatus: 70)) {
            try AppThinning.variants(app: app, items: [app], developerDirectory: temporary.path + "/Developer")
        }
        // A universal library (the full archive embeds a back-deployment one, arm64e and arm64).
        let embedding = try TemporaryDirectory(prefix: "nomac-thinning")
        let universal = try ArchiveExporterTests.archive(in: embedding.path)
        try FileSystem.write(Data(Self.options().utf8), to: embedding.path + "/options.plist")
        #expect(throws: NomacError.self) {
            try ArchiveExporter.export(archive: universal, exportPath: embedding.path + "/out", optionsPath: embedding.path + "/options.plist",
                                       developerDirectory: temporary.path + "/Developer")
        }
    }
}
