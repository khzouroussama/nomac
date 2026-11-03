import CSQLite
import Foundation
import NomacAssets
import NomacCore
import NomacSigning

/// App thinning of debugging, release-testing and enterprise exports (`thinning`
/// `<thin-for-all-variants>`; docs/formats/ipa.md "App thinning", `distribution_experiments.py`
/// `thinning`): the device descriptors of the user's Xcode's `device_traits.db` from the app's
/// minimum OS on, grouped by the renditions of the app's `Assets.car` their trait set keeps
/// (one group for an app without a catalog), each group a variant thinned for its first
/// descriptor by product type, then OS version.
enum AppThinning {
    struct Descriptor: Hashable {
        var device: String
        var osVersion: String
        /// The OS version's number in `device_traits.db`'s `DeploymentTarget` table.
        var osNumber: Int
        /// The architecture the device runs the app as (`TargetArchitecture`).
        var architecture: String = ""
    }

    /// A watch app's variant (`thinning` `watch`, `watch-catalog`): its descriptors, the slice of
    /// the watch executable they run, the minimum OS it declares, and its thinned catalog.
    struct WatchVariant {
        var descriptors: [Descriptor]
        var slice: Slice
        var minimum: String
        var catalog: [UInt8]?
    }

    /// A slice of a universal file: its architecture as `device_traits.db` names it, CPU type and
    /// subtype and bytes.
    struct Slice: Equatable {
        var architecture: String
        var cpuType: Int
        var cpuSubtype: Int
        var bytes: [UInt8]
    }

    struct Variant {
        var descriptors: [Descriptor]
        /// The thinned `Assets.car` of each bundle that has one, by the bundle's path.
        var catalogs: [String: [UInt8]]
    }

    static let databasePath = "Platforms/iPhoneOS.platform/usr/standalone/device_traits.db"
    static let watchDatabasePath = "Platforms/WatchOS.platform/usr/standalone/device_traits.db"
    /// The oldest watchOS minimum observed (`thinning` `watch-9`: one variant per slice still).
    static let oldestWatchMinimum = "9.0"
    /// The slices a watch's architecture runs, best first (`watch`: arm64e and arm64e.x1 watches
    /// at 27.0 get the arm64 slice).
    static let sliceFallbacks = ["arm64e.x1": ["arm64e.x1", "arm64e", "arm64"], "arm64e": ["arm64e", "arm64"], "arm64": ["arm64"], "arm64_32": ["arm64_32"]]

    /// The OS from which one deployment target covers every descriptor: below it xcodebuild
    /// splits the variants by OS as well (an app declaring iOS 12.0, `thinning` `catalog-12`),
    /// which nomac does not.
    static let singleDeploymentFrom = "13.0"

    /// Refuses what app thinning was not observed with: watch apps, packs hosted beside the IPA,
    /// a catalog anywhere but at the top of the app or of a bundle of its code, code with other
    /// slices than one arm64, an install manifest. (An App Clip is left out before.)
    static func checkSupported(app: String, items: [String], hostedPacks: Bool, manifest: Bool) throws {
        func refuse(_ what: String) -> NomacError {
            NomacError("exportArchive app thinning of \(what) is not supported yet (BACKLOG B-465)", path: app, exitStatus: 70)
        }
        if hostedPacks { throw refuse("apps with on-demand resources hosted beside the IPA") }
        if manifest { throw refuse("exports with an install manifest") }
        let watches = FileSystem.isDirectory(app + "/Watch") ? try FileSystem.sortedContents(of: app + "/Watch") : []
        if watches.count > 1 || watches.contains(where: { !$0.hasSuffix(".app") }) { throw refuse("a Watch folder other than one watch app") }
        if let watch = watches.first.map({ app + "/Watch/" + $0 }) {
            if items.contains(where: { $0.hasPrefix(watch + "/") }) { throw refuse("watch apps with code of their own bundles") }
            let executable = try PropertyLists.readDictionary(at: watch + "/Info.plist")["CFBundleExecutable"] as? String ?? ""
            let slices = try Self.slices(of: watch + "/" + executable)
            if slices.isEmpty || !slices.allSatisfy({ ["arm64", "arm64_32"].contains($0.architecture) }) { throw refuse("watch apps with slices other than arm64 and arm64_32") }
        }
        let bundles = Set(items.filter(FileSystem.isDirectory).map { $0 + "/Assets.car" })
        for path in try FileManager.default.subpathsOfDirectory(atPath: app) where (path as NSString).lastPathComponent == "Assets.car" {
            if !bundles.contains(app + "/" + path) { throw refuse("asset catalogs outside the top of the app and its bundles of code") }
        }
        for item in items where !item.hasPrefix(app + "/Watch/") {
            var executable = item
            if FileSystem.isDirectory(item) {
                guard let name = try PropertyLists.readDictionary(at: item + "/Info.plist")["CFBundleExecutable"] as? String else { continue }
                executable = item + "/" + name
            }
            if try CodeSigner.architectures(of: executable) != ["arm64"] { throw refuse("code with slices other than one arm64") }
        }
    }

    /// The variants of the app at `app` (its `MinimumOSVersion`, the `Assets.car` at the top of
    /// it and of the bundles `items`) for the descriptors of the database under
    /// `developerDirectory`: grouped by what every catalog keeps, each catalog thinned for the
    /// group's first descriptor (`distribution_experiments.py` `thinning` `nested`).
    static func variants(app: String, items: [String], developerDirectory: String) throws -> [Variant] {
        guard let minimum = try PropertyLists.readDictionary(at: app + "/Info.plist")["MinimumOSVersion"] as? String else {
            throw NomacError("exportArchive app thinning needs the app's MinimumOSVersion", path: app, exitStatus: 70)
        }
        let database = developerDirectory + "/" + databasePath
        guard FileSystem.isFile(database) else {
            throw NomacError("exportArchive app thinning needs Xcode's device_traits.db", path: database,
                             notes: ["install the SDK subset again with this nomac (nomac sdk install), which keeps it"], exitStatus: 70)
        }
        let rows = try descriptors(database: database, minimum: minimum, oldest: singleDeploymentFrom, platform: "iOS")
        var catalogs: [(path: String, bytes: [UInt8])] = []
        for item in items where FileSystem.isDirectory(item) {
            if let data = FileManager.default.contents(atPath: item + "/Assets.car") {
                catalogs.append((String(item.dropFirst(app.count)), [UInt8](data)))
            }
        }
        var groups: [[Set<[UInt8]>]: [(Descriptor, ThinningTraits)]] = [:]
        var kept: [ThinningTraits: [Set<[UInt8]>]] = [:]
        for row in rows {
            if kept[row.1] == nil {
                kept[row.1] = try catalogs.map { try CARThinning.keptRenditions($0.bytes, for: row.1, path: app + $0.path + "/Assets.car") }
            }
            groups[kept[row.1]!, default: []].append(row)
        }
        return try groups.values.map { members in
            let first = members.min { precedes($0.0, $1.0) }!
            let thinned = try catalogs.map { ($0.path, try CARThinning.thin($0.bytes, for: first.1, path: app + $0.path + "/Assets.car")) }
            return Variant(descriptors: members.map(\.0).sorted(by: precedes), catalogs: Dictionary(uniqueKeysWithValues: thinned))
        }
    }

    /// The variants of the watch app at `watch` (its `MinimumOSVersion` and `Assets.car`, the
    /// slices of `executable`) for the watchOS descriptors under `developerDirectory`: grouped by the slice
    /// each runs and what the catalog keeps; a variant declares its earliest descriptor's OS when
    /// that is later than the app's minimum (`thinning` `watch`: arm64's 26.0), whatever its
    /// slice's own minimum (`watch-9`: arm64_32 built for 11.0 keeps 9.0), and its catalog is
    /// thinned for its first descriptor at that minimum.
    static func watchVariants(watch: String, executable: String, developerDirectory: String) throws -> [WatchVariant] {
        let info = try PropertyLists.readDictionary(at: watch + "/Info.plist")
        guard let declared = info["MinimumOSVersion"] as? String else {
            throw NomacError("exportArchive app thinning needs the watch app's MinimumOSVersion", path: watch, exitStatus: 70)
        }
        let database = developerDirectory + "/" + watchDatabasePath
        guard FileSystem.isFile(database) else {
            throw NomacError("exportArchive app thinning needs Xcode's watchOS device_traits.db", path: database,
                             notes: ["install the SDK subset again with this nomac (nomac sdk install), which keeps it"], exitStatus: 70)
        }
        let slices = try Self.slices(of: executable)
        let catalog = FileManager.default.contents(atPath: watch + "/Assets.car").map([UInt8].init)
        var groups: [String: [(Descriptor, ThinningTraits, Slice)]] = [:]
        var order: [String] = []
        for (descriptor, traits) in try descriptors(database: database, minimum: declared, oldest: oldestWatchMinimum, platform: "watchOS") {
            guard let slice = (sliceFallbacks[descriptor.architecture] ?? []).lazy.compactMap({ name in slices.first { $0.architecture == name } }).first else {
                throw NomacError("exportArchive app thinning of a watch app for \(descriptor.device) (\(descriptor.architecture)), which none of its slices runs, is not supported yet (BACKLOG B-465)",
                                 path: watch, exitStatus: 70)
            }
            let kept = try catalog.map { try CARThinning.keptRenditions($0, for: traits, path: watch + "/Assets.car") } ?? []
            let key = slice.architecture + "\n" + kept.map { $0.map(String.init).joined(separator: ",") }.sorted().joined(separator: ";")
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append((descriptor, traits, slice))
        }
        return try order.map { key in
            let members = groups[key]!
            let slice = members[0].2
            let earliest = members.map(\.0.osVersion).min(by: versionPrecedes)!
            let minimum = versionPrecedes(declared, earliest) ? earliest : declared
            var traits = members.min { precedes($0.0, $1.0) }!.1
            traits.deploymentTarget = minimum
            return WatchVariant(descriptors: members.map(\.0).sorted(by: precedes), slice: slice, minimum: minimum,
                                catalog: try catalog.map { try CARThinning.thin($0, for: traits, path: watch + "/Assets.car") })
        }
    }

    /// Whether version `a` is earlier than `b`.
    static func versionPrecedes(_ a: String, _ b: String) -> Bool {
        func components(_ version: String) -> [Int] {
            let parts = version.split(separator: ".").map { Int($0) ?? 0 }
            return parts + Array(repeating: 0, count: max(0, 3 - parts.count))
        }
        return components(a).lexicographicallyPrecedes(components(b))
    }

    /// The slices of the Mach-O file at `path` (`<mach-o/fat.h>`), one for a thin file.
    static func slices(of path: String) throws -> [Slice] {
        guard let data = FileManager.default.contents(atPath: path) else { throw NomacError("cannot read the executable", path: path) }
        let bytes = [UInt8](data)
        func be32(_ at: Int) -> Int { bytes[at..<(at + 4)].reduce(0) { $0 << 8 | Int($1) } }
        func le32(_ slice: [UInt8], _ at: Int) -> Int { slice[at..<(at + 4)].reversed().reduce(0) { $0 << 8 | Int($1) } }
        func slice(_ part: [UInt8]) -> Slice {
            let type = le32(part, 4), subtype = le32(part, 8) & 0x00FF_FFFF
            let name = type == 0x0200_000C ? "arm64_32" : type == 0x0100_000C ? (subtype == 2 ? "arm64e" : "arm64") : "cpu \(type)"
            return Slice(architecture: name, cpuType: type, cpuSubtype: subtype, bytes: part)
        }
        guard bytes.count >= 8, be32(0) == 0xCAFE_BABE else { return bytes.count >= 12 ? [slice(bytes)] : [] }
        return (0..<be32(4)).map { index in
            let entry = 8 + 20 * index, offset = be32(entry + 8), size = be32(entry + 12)
            return slice(Array(bytes[offset..<(offset + size)]))
        }
    }

    /// Product types in byte order, then OS versions in the database's order.
    static func precedes(_ a: Descriptor, _ b: Descriptor) -> Bool {
        a.device == b.device ? a.osNumber < b.osNumber : a.device.utf8.lexicographicallyPrecedes(b.device.utf8)
    }

    /// Each `DeploymentVariant` row from `minimum` on: its board's product type, the OS version
    /// and the trait set, in assetutil's terms with that version as the deployment target.
    static func descriptors(database path: String, minimum: String, oldest: String, platform: String) throws -> [(Descriptor, ThinningTraits)] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else {
            throw NomacError("cannot open the device traits database", path: path)
        }
        defer { sqlite3_close(database) }
        func rows(_ query: String, _ parameter: String) throws -> [[String?]] {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw NomacError("unexpected device traits database: \(String(cString: sqlite3_errmsg(database)))", path: path)
            }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, parameter, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            var result: [[String?]] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                result.append((0..<sqlite3_column_count(statement)).map { column in
                    sqlite3_column_text(statement, column).map { String(cString: $0) }
                })
            }
            return result
        }
        let numbers = Dictionary(uniqueKeysWithValues: try rows("select TargetVersion, DeploymentTarget from DeploymentTarget where ?1 = ?1", "")
            .compactMap { row -> (String, Int)? in
                guard let version = row[0], let number = row[1].flatMap(Int.init) else { return nil }
                return (version, number)
            })
        // A minimum the table does not list counts as the last version before it (an app
        // declaring 18.5 gets the descriptors and the thinning of 18.0, `catalog-185`).
        let listed = numbers.keys.filter { !versionPrecedes(minimum, $0) }
        guard let floor = listed.max(by: versionPrecedes), let minimumNumber = numbers[floor],
              let single = numbers[oldest], minimumNumber >= single else {
            throw NomacError("exportArchive app thinning of apps for \(platform) \(minimum) is not supported yet (BACKLOG B-465)",
                             notes: ["observed for a MinimumOSVersion of \(oldest) or later"], exitStatus: 70)
        }
        let query = """
            select d.ProductType, v.DeploymentTarget, t.ArtworkDeviceIdiom, t.ArtworkScaleFactor, t.ArtworkDeviceSubtype, \
            t.ArtworkDeviceSubtypeFallbacks, t.ArtworkDisplayGamut, t.ArtworkHostedIdioms, t.GraphicsFeatureSetClass, \
            t.GraphicsFeatureSetFallbacks, t.DevicePerformanceMemoryClass, v.TargetArchitecture \
            from DeploymentVariant v \
            join Devices d on d.Target = v.DeviceTarget and ifnull(d.ThinningConfiguration, '') = ifnull(v.ThinningConfiguration, '') \
            join DeviceTraits t on t.DeviceTraitSetID = v.DeviceTraitSet \
            join DeploymentTarget n on n.TargetVersion = v.DeploymentTarget \
            where n.DeploymentTarget >= (select DeploymentTarget from DeploymentTarget where TargetVersion = ?1)
            """
        return try rows(query, floor).map { row in
            guard let device = row[0], let version = row[1], let number = numbers[version], let idiom = row[2], let scale = row[3].flatMap(Int.init),
                  let graphics = row[8], let memory = row[10].flatMap(Int.init) else {
                throw NomacError("unexpected device traits row \(row)", path: path)
            }
            let traits = ThinningTraits(idiom: idiom, scale: scale, subtype: row[4].flatMap(Int.init), subtypeFallbacks: row[5].flatMap { $0.isEmpty ? nil : $0 },
                                        displayGamut: row[6].flatMap { $0.isEmpty ? nil : $0 },
                                        hostedIdioms: (row[7] ?? "").split(separator: ",").map(String.init), graphicsClass: graphics,
                                        graphicsFallbacks: (row[9] ?? "").split(separator: ":").map(String.init), memory: memory, deploymentTarget: floor)
            return (Descriptor(device: device, osVersion: version, osNumber: number, architecture: row[11] ?? ""), traits)
        }
    }

    /// A variant's file name: the IPA's name with a UUID. xcodebuild draws the UUID at random
    /// (another one each run); nomac derives it from the variant's descriptors, so the same
    /// export names its variants the same.
    static func fileName(ipaName: String, descriptors: [Descriptor]) -> String {
        let text = descriptors.map { "\($0.device) \($0.osVersion)" }.joined(separator: "\n")
        var bytes = Array(SHA256.digest(Array(text.utf8)).prefix(16))
        bytes[6] = bytes[6] & 0x0F | 0x40
        bytes[8] = bytes[8] & 0x3F | 0x80
        let hex = bytes.map { String(format: "%02X", $0) }.joined()
        let uuid = [hex.prefix(8), hex.dropFirst(8).prefix(4), hex.dropFirst(12).prefix(4), hex.dropFirst(16).prefix(4), hex.dropFirst(20)].joined(separator: "-")
        return (ipaName as NSString).deletingPathExtension + "-" + uuid + ".ipa"
    }

    /// An embedded asset pack as `app-thinning.plist` lists it.
    struct Pack {
        var name: String
        var identifier: String
        var tags: [String]
        var size: Int
    }

    struct Sizes {
        /// The IPA's size.
        var compressed: Int
        /// The size of what it holds: regular files' sizes and symbolic links' targets.
        var uncompressed: Int
        /// The packs embedded in the app (`OnDemandResources`), and their part of `uncompressed`.
        var packs: [Pack]
        var packsSize: Int { packs.reduce(0) { $0 + $1.size } }
    }

    struct Written {
        var file: String
        /// Its key in `app-thinning.plist`: `Apps/<file>`, or the file alone for one device.
        var key: String
        var sizes: Sizes
        var descriptors: [Descriptor]?
    }

    static func sizes(ipa: String, root: String, app: String) throws -> Sizes {
        func size(of folder: String) throws -> Int {
            var total = 0
            for item in try FileManager.default.subpathsOfDirectory(atPath: folder) {
                let attributes = try FileManager.default.attributesOfItem(atPath: folder + "/" + item)
                switch attributes[.type] as? FileAttributeType {
                case .typeRegular?: total += (attributes[.size] as? NSNumber)?.intValue ?? 0
                case .typeSymbolicLink?: total += try FileManager.default.destinationOfSymbolicLink(atPath: folder + "/" + item).utf8.count
                default: break
                }
            }
            return total
        }
        let compressed = (try FileManager.default.attributesOfItem(atPath: ipa)[.size] as? NSNumber)?.intValue ?? 0
        let packsFolder = app + "/OnDemandResources"
        let packs = try (FileSystem.isDirectory(packsFolder) ? FileSystem.sortedContents(of: packsFolder) : []).filter { $0.hasSuffix(".assetpack") }.map { name in
            let info = try PropertyLists.readDictionary(at: packsFolder + "/" + name + "/Info.plist")
            return Pack(name: name, identifier: info["CFBundleIdentifier"] as? String ?? "", tags: info["Tags"] as? [String] ?? [],
                        size: try size(of: packsFolder + "/" + name))
        }
        return Sizes(compressed: compressed, uncompressed: try size(of: root), packs: packs)
    }

    /// `app-thinning.plist`: each variant's sizes, packs and descriptors (none for the universal
    /// one). With packs the compressed sizes of the app alone and of the packs are not given
    /// (`odr`).
    static func plist(_ variants: [Written]) -> PropertyListValue {
        .dictionary(["variants": .dictionary(Dictionary(uniqueKeysWithValues: variants.map { variant in
            let sizes = variant.sizes
            var entry: [String: PropertyListValue] = [
                "limitUncompressedInitialPrefetchedODR": .integer(2_147_483_648),
                "onDemandResourcesAssetPacks": .dictionary(Dictionary(uniqueKeysWithValues: sizes.packs.map { pack in
                    (pack.name, .dictionary(["identifier": .string(pack.identifier), "limitUncompressed": .integer(536_870_912),
                                             "sizeUncompressed": .integer(Int64(pack.size)), "tags": .array(pack.tags.map(PropertyListValue.string))]))
                })),
                "sizeCompressedAppAndODR": .integer(Int64(sizes.compressed)),
                "sizeUncompressedApp": .integer(Int64(sizes.uncompressed - sizes.packsSize)),
                "sizeUncompressedAppAndODR": .integer(Int64(sizes.uncompressed)), "sizeUncompressedInitialPrefetchedODR": .integer(0),
                "sizeUncompressedInitialPrefetchedODRExceedsLimit": .boolean(false), "sizeUncompressedODR": .integer(Int64(sizes.packsSize)),
                "tagsUncompressedInitialPrefetchedODR": .array([]),
            ]
            if sizes.packs.isEmpty {
                entry["sizeCompressedApp"] = .integer(Int64(sizes.compressed))
                entry["sizeCompressedODR"] = .integer(0)
            }
            if let descriptors = variant.descriptors {
                entry["variantDescriptors"] = .array(descriptors.map { .dictionary(["device": .string($0.device), "os-version": .string($0.osVersion)]) })
            }
            return (variant.key, .dictionary(entry))
        }))])
    }

    /// A size as the report writes it: `Zero KB`, bytes below 1000, whole kilobytes (of 1000
    /// bytes, rounded) below a million, megabytes with one decimal, `.0` left out (2,371,130
    /// bytes are 2.4 MB, 3,000,642 are 3 MB; `thinning` `large`, `large-3`, `odr`).
    static func size(_ bytes: Int) throws -> String {
        if bytes == 0 { return "Zero KB" }
        if bytes < 1000 { return "\(bytes) bytes" }
        if bytes < 999_500 { return "\((bytes + 500) / 1000) KB" }
        guard bytes < 999_950_000 else {
            throw NomacError("exportArchive app thinning of variants of a gigabyte or more is not supported yet (BACKLOG B-465)", exitStatus: 70)
        }
        let tenths = (bytes + 50_000) / 100_000
        return tenths % 10 == 0 ? "\(tenths / 10) MB" : "\(tenths / 10).\(tenths % 10) MB"
    }

    /// `App Thinning Size Report.txt`, the variants in file name order; with packs, the app's and
    /// the packs' sizes uncompressed only.
    static func report(appName: String, _ variants: [Written]) throws -> String {
        let blocks = try variants.sorted { $0.file.utf8.lexicographicallyPrecedes($1.file.utf8) }.map { variant -> String in
            let descriptors = variant.descriptors.map { list -> String in
                let items = list.map { "[device: \($0.device), os-version: \($0.osVersion)]" }
                return items.count > 1 ? items.dropLast().joined(separator: ", ") + ", and " + items.last! : items.joined()
            } ?? "Universal"
            let sizes = variant.sizes
            let app = sizes.packs.isEmpty ? "\(try size(sizes.compressed)) compressed, \(try size(sizes.uncompressed)) uncompressed"
                : "\(try size(sizes.uncompressed - sizes.packsSize)) uncompressed"
            let packs = sizes.packs.isEmpty ? "Zero KB compressed, Zero KB uncompressed" : "\(try size(sizes.packsSize)) uncompressed"
            return """
                Variant: \(variant.file)
                Supported variant descriptors: \(descriptors)
                App + On Demand Resources size: \(try size(sizes.compressed)) compressed, \(try size(sizes.uncompressed)) uncompressed
                App size: \(app)
                On Demand Resources size: \(packs)

                """
        }
        return "\nApp Thinning Size Report for All Variants of \(appName)\n\n" + blocks.joined(separator: "\n\n")
    }
}
