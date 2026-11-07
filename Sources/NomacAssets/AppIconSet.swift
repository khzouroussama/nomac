import Foundation
import NomacCore
import NomacPlist

/// Multi-size app icon sets (docs/formats/asset-catalog.md, "Multi-size app icon sets"), as the
/// Xcode builds of uncloudnotes, flappy-fly-bird, tofu and netnewswire and the self-written sets
/// of `assets-experiments app-icons` show them: one part-220 image per entry, a part-218 table of
/// sizes per idiom, the icon PNGs next to `Assets.car` and the partial Info.plist's icon keys.
/// `--target-device` changes none of it.
enum AppIconSet {
    /// The entries actool assigns: sizes in points and their scales per idiom.
    static let slots: [String: [String: Set<Int>]] = [
        "iphone": ["20x20": [2, 3], "29x29": [1, 2, 3], "40x40": [2, 3], "57x57": [1, 2], "60x60": [2, 3]],
        "ipad": ["20x20": [1, 2], "29x29": [1, 2], "40x40": [1, 2], "50x50": [1, 2], "72x72": [1, 2], "76x76": [1, 2], "83.5x83.5": [2]],
        "ios-marketing": ["1024x1024": [1]],
        "car": ["60x60": [2, 3]],
    ]
    static let idioms: [String: UInt16] = ["iphone": Idiom.phone, "ipad": Idiom.pad, "car": Idiom.car, "ios-marketing": Idiom.marketing]

    /// What actool warns about in a set's entries (`icon-entries`).
    struct Problems {
        struct Unassigned {
            var idiom: String, size: String, scale: String, filename: String
        }

        /// Images of the wrong size and missing files: where, and the message.
        var entries: [(slot: String, message: String)] = []
        /// Entries of a size or idiom without a slot, and files no entry names.
        var unassigned: [Unassigned] = []
        var strayFiles: [String] = []

        /// actool goes over a set three times, the second time without counting `tv` entries,
        /// with the warnings for what is required after the first (`icon-entries`; the order of
        /// the messages within a pass changes from run to run, ADR 0203).
        func warnings(folder: String, name: String, required: [String]) -> [(where: String, message: String)] {
            func line(tv: Bool) -> [(where: String, message: String)] {
                let counted = unassigned.filter { tv || $0.idiom != "tv" }
                let count = counted.count + strayFiles.count
                guard count > 0 else { return [] }
                let place: String
                if let file = strayFiles.first {
                    place = "./\(folder)/(null)[2d][\(file)]"
                } else {
                    let first = counted.min { $0.filename.utf8.lexicographicallyPrecedes($1.filename.utf8) }!
                    let idiom = first.idiom == "vision" ? "" : first.idiom
                    place = "./\(folder)/[][\(idiom)][\(first.size)][][][\(first.scale)][][][][][2d][\(first.filename)]"
                }
                let children = count == 1 ? "an unassigned child" : "\(count) unassigned children"
                return [(place, "The app icon set \"\(name)\" has \(children).")]
            }
            let pass = entries.map { (where: $0.slot, message: $0.message) }
            return line(tv: true) + pass + required.map { (where: "./\(folder)", message: $0) } + line(tv: false) + pass + line(tv: true) + pass
        }
    }

    /// The iPhone 60 pt 3x image is also a 90 pt 2x image of subtype 1792.
    static let largePhoneSubtype: UInt16 = 1792
    static let largePhonePoints = 90.0

    struct Icon {
        var idiom: String
        var size: String
        var scale: Int
        var filename: String
        var path: String
        var image: PNGImage
        /// A single-size icon's appearance: 0, dark 1 or tinted 10.
        var appearance: UInt16 = 0
        /// A single-size icon's platform: `ios` or `watchos`.
        var platform = "ios"
        /// A watch icon's subtype, from its case size.
        var subtype: UInt16 = 0
        /// A JPEG file, stored as it is.
        var jpeg: JPEGFile?

        var points: Double { Double(size.prefix { $0 != "x" })! }
    }

    struct Compiled {
        var sources: [ImageSet.Source]
        var sizeTables: [CARRendition]
        /// The PNGs written next to `Assets.car`, by file name.
        var pngs: [(filename: String, icon: Icon)]
        var infoPlist: [String: PropertyListValue]
        var notices: [String]
        var warnings: [String] = []
    }

    /// The notices actool prints for entries of sizes only older releases use, for the devices
    /// the build targets (`app-icons`, icons-legacy-all, icons-both-target-iphone), by idiom, size
    /// and scale.
    static let legacyNotices: [String: String] = [
        "iphone 57x57 1": "57x57 app icons only apply to iPhone apps targeting releases of iOS prior to 7.0",
        "iphone 57x57 2": "57x57@2x app icons only apply to iPhone apps targeting releases of iOS prior to 7.0",
        "ipad 50x50 1": "50x50 iPad spotlight icons only apply to iPad apps targeting releases of iOS prior to 7.0",
        "ipad 50x50 2": "50x50 iPad spotlight icons only apply to iPad apps targeting releases of iOS prior to 7.0",
        "ipad 72x72 1": "72x72 app icons only apply to iPad apps targeting releases of iOS prior to 7.0",
        "ipad 72x72 2": "72x72@2x app icons only apply to iPad apps targeting releases of iOS prior to 7.0",
        "ipad 76x76 1": "76x76@1x app icons only apply to iPad apps targeting releases of iOS prior to 10.0.",
    ]

    /// The set's images; `problems` gets actool's warnings about entries it does not use: images
    /// of the wrong size and missing files, left out (`icon-entries`), and entries of other sizes
    /// and idioms and files no entry names. Files that are no images are left out without a word.
    static func icons(_ asset: AssetCatalog.Asset, watch: Bool = true, problems: inout Problems) throws -> [Icon] {
        var icons: [Icon] = []
        let entries = asset.contents["images"] as? [[String: Any]] ?? []
        let filesNamed = Set(entries.compactMap { $0["filename"] as? String })
        for file in ((try? FileManager.default.contentsOfDirectory(atPath: asset.path)) ?? []).sorted()
        where file != "Contents.json" && !file.hasPrefix(".") && !filesNamed.contains(file) {
            problems.strayFiles.append(file)
        }
        let multiSize = entries.contains { $0["filename"] != nil && ["iphone", "ipad", "ios-marketing", "car"].contains($0["idiom"] as? String ?? "") }
        for entry in entries {
            guard let filename = entry["filename"] as? String else { continue }
            let idiom = entry["idiom"] as? String ?? "", size = entry["size"] as? String ?? "", scaleName = entry["scale"] as? String ?? ""
            if idiom == "universal" && (!multiSize || entry["platform"] != nil) {
                icons.append(try singleSizeIcon(entry, filename: filename, asset: asset))
                continue
            }
            // Mac sizes in a set are left out (`app-icons` icons-with-mac; flutter, netnewswire).
            if idiom == "mac" { continue }
            if !multiSize, ["watch", "watch-marketing"].contains(idiom) {
                if watch { icons.append(try watchIcon(entry, filename: filename, asset: asset)) }
                continue
            }
            guard Set(entry.keys).isSubset(of: ["filename", "idiom", "scale", "size", "expected-size", "folder"]) else {
                throw NomacError("app icon entries with \(Set(entry.keys).subtracting(["filename", "idiom", "scale", "size"]).sorted()) are not supported yet (BACKLOG B-202)", path: asset.path + "/" + filename)
            }
            guard let scale = ImageSet.scales[scaleName], slots[idiom]?[size]?.contains(scale) == true else {
                problems.unassigned.append(.init(idiom: idiom, size: size, scale: scaleName, filename: filename))
                continue
            }
            guard !icons.contains(where: { $0.idiom == idiom && $0.size == size && $0.scale == scale }) else {
                throw NomacError("app icon sets with two images of one size are not supported yet (BACKLOG B-202)", path: asset.path)
            }
            let slot = "./\((asset.path as NSString).lastPathComponent)/[][\(idiom)][\(size)][][][\(scaleName)][][][][]"
            let path = asset.path + "/" + filename
            guard let data = FileManager.default.contents(atPath: path) else {
                problems.entries.append((slot, "The file \"\(filename)\" for the image set \"\(asset.name)\" does not exist."))
                continue
            }
            let pixels = (Double(size.prefix { $0 != "x" }) ?? 0) * Double(scale)
            var icon = Icon(idiom: idiom, size: size, scale: scale, filename: filename, path: path, image: PNGImage(width: 0, height: 0, pixels: []))
            let type = (filename as NSString).pathExtension.lowercased()
            if ["jpg", "jpeg"].contains(type) {
                guard let jpeg = try? JPEGFile([UInt8](data), path: path) else { continue }
                icon.jpeg = jpeg
                icon.image = PNGImage(width: jpeg.width, height: jpeg.height, pixels: [])
            } else if type == "png" {
                do { icon.image = try PNGImage(data: [UInt8](data), path: path) } catch is PNGImage.Unreadable { continue }
            } else {
                throw NomacError("image files other than PNG and JPEG are not supported yet (BACKLOG B-200)", path: path)
            }
            guard Double(icon.image.width) == pixels, Double(icon.image.height) == pixels else {
                let expected = pixels.rounded(), wanted = "\(Int(expected))x\(Int(expected))"
                problems.entries.append((slot, "\((asset.path as NSString).lastPathComponent)/\(filename) is \(icon.image.width)x\(icon.image.height) but should be \(wanted)."))
                continue
            }
            icons.append(icon)
        }
        let singleSize = icons.filter { $0.idiom == "universal" }
        guard singleSize.isEmpty || singleSize.count == icons.count else {
            throw NomacError("app icon sets with single-size and multi-size entries are not supported yet (BACKLOG B-202)", path: asset.path)
        }
        guard Set(singleSize.map(\.platform)).count <= 1, Set(singleSize.map(\.appearance)).count == singleSize.count,
              singleSize.isEmpty || singleSize.contains(where: { $0.appearance == 0 }) else {
            throw NomacError("single-size app icon sets without one image per appearance, the default one included, are not supported yet (BACKLOG B-202)", path: asset.path)
        }
        return icons
    }

    /// The roles and sizes of a multi-size watch icon set (Xcode's watch template), each with its
    /// case sizes and scales.
    static let watchSlots: [String: [String: (subtypes: Set<String?>, scales: Set<Int>)]] = [
        "notificationCenter": ["24x24": (["38mm"], [2]), "27.5x27.5": (["42mm"], [2]), "33x33": (["45mm"], [2])],
        "companionSettings": ["29x29": ([nil], [2, 3])],
        "appLauncher": ["40x40": (["38mm"], [2]), "44x44": (["40mm"], [2]), "46x46": (["41mm"], [2]), "50x50": (["44mm"], [2]), "51x51": (["45mm"], [2]),
                        "54x54": (["49mm"], [2])],
        "quickLook": ["86x86": (["38mm"], [2]), "98x98": (["42mm"], [2]), "108x108": (["44mm"], [2]), "117x117": (["45mm"], [2]), "129x129": (["49mm"], [2])],
    ]

    /// A watch case size's subtype in the rendition key (`watchos` multi-size case); an app
    /// launcher icon for 38 mm has none.
    static let watchSubtypes: [String: UInt16] = ["38mm": 320, "40mm": 340, "41mm": 430, "42mm": 384, "44mm": 390, "45mm": 484, "49mm": 502]

    /// An entry of a multi-size watch icon set, or its `watch-marketing` image.
    static func watchIcon(_ entry: [String: Any], filename: String, asset: AssetCatalog.Asset) throws -> Icon {
        let idiom = entry["idiom"] as? String ?? "", size = entry["size"] as? String ?? "", role = entry["role"] as? String
        let subtypeName = entry["subtype"] as? String
        guard let scale = ImageSet.scales[entry["scale"] as? String ?? ""], (filename as NSString).pathExtension.lowercased() == "png",
              idiom == "watch-marketing" ? size == "1024x1024" && scale == 1 && role == nil
                  : role.flatMap({ watchSlots[$0]?[size] }).map({ $0.subtypes.contains(subtypeName) && $0.scales.contains(scale) }) == true,
              Set(entry.keys).isSubset(of: ["filename", "idiom", "size", "scale", "role", "subtype"]) else {
            throw NomacError("watch app icon entries other than Xcode's watch template are not supported yet (BACKLOG B-206)", path: asset.path + "/" + filename)
        }
        let path = asset.path + "/" + filename
        let subtype = role == "appLauncher" && subtypeName == "38mm" ? 0 : subtypeName.flatMap { watchSubtypes[$0] } ?? 0
        return Icon(idiom: idiom, size: size, scale: scale, filename: filename, path: path, image: try PNGImage(contentsOf: path), platform: "watchos", subtype: subtype)
    }

    /// A single-size iOS icon: 1,024 points, the default, dark or tinted appearance.
    static func singleSizeIcon(_ entry: [String: Any], filename: String, asset: AssetCatalog.Asset) throws -> Icon {
        let appearances = entry["appearances"] as? [[String: Any]] ?? []
        let value = appearances.first?["value"] as? String
        guard Set(entry.keys).isSubset(of: ["filename", "idiom", "platform", "size", "appearances"]), let platform = entry["platform"] as? String,
              ["ios", "watchos"].contains(platform),
              entry["size"] as? String == "1024x1024", appearances.count <= 1,
              appearances.allSatisfy({ $0.count == 2 && $0["appearance"] as? String == "luminosity" }),
              let appearance = [nil: RenditionAppearance.any, "dark": .dark, "tinted": .tintable][value]?.rawValue else {
            throw NomacError("app icon entries other than iPhone, iPad and App Store sizes and single-size iOS icons are not supported yet (BACKLOG B-202)",
                             path: asset.path + "/" + filename)
        }
        guard (filename as NSString).pathExtension.lowercased() == "png" else {
            throw NomacError("image files other than PNG are not supported yet (BACKLOG B-200)", path: asset.path + "/" + filename)
        }
        let path = asset.path + "/" + filename
        let image = try PNGImage(contentsOf: path)
        guard image.width == 1024, image.height == 1024 else {
            throw NomacError("single-size app icons of other than 1,024 × 1,024 pixels are not supported yet (BACKLOG B-202)", path: path)
        }
        return Icon(idiom: "universal", size: "1024x1024", scale: 1, filename: filename, path: path, image: image, appearance: appearance, platform: platform)
    }

    /// What actool warns a set of the targeted devices lacks, in this order (`incomplete-icons`).
    /// An alternate set is neither checked nor warned about (`alternate-app-icons`).
    static func requiredIconWarnings(_ icons: [Icon], targetDevices: [String]) -> [String] {
        func lacks(_ idiom: String, _ size: String, _ scale: Int) -> Bool { !icons.contains { $0.idiom == idiom && $0.size == size && $0.scale == scale } }
        var warnings: [String] = []
        if targetDevices.contains("iphone"), lacks("iphone", "60x60", 2) { warnings.append("A 60x60@2x app icon is required for iPhone apps targeting iOS 7.0 and later") }
        if targetDevices.contains("ipad") {
            if lacks("ipad", "76x76", 2) { warnings.append("A 76x76@2x app icon is required for iPad apps targeting iOS 7.0 and later") }
            if lacks("ipad", "83.5x83.5", 2) { warnings.append("A 83.5x83.5@2x app icon is required for iPad apps targeting iOS 9.0 and later") }
        }
        if lacks("ios-marketing", "1024x1024", 1) { warnings.append("A 1024x1024 app store icon is required for iOS apps") }
        return warnings
    }

    static func compile(_ asset: AssetCatalog.Asset, icons: [Icon], problems: Problems = Problems(), catalog: String, standaloneBehavior: String?, targetDevices: [String],
                        alternate: Bool = false) throws -> Compiled {
        if icons.first?.idiom == "universal" {
            return try compileSingleSize(asset, icons: icons, standaloneBehavior: standaloneBehavior, targetDevices: targetDevices)
        }
        if icons.contains(where: { $0.platform == "watchos" }) {
            return try compileWatchMultiSize(asset, icons: icons, targetDevices: targetDevices)
        }
        let largePhone = icons.first { $0.idiom == "iphone" && $0.size == "60x60" && $0.scale == 3 }
        let allPoints = Set(icons.map(\.points) + (largePhone == nil ? [] : [largePhonePoints])).sorted()
        func dimension2(_ points: Double) -> UInt16 { UInt16(allPoints.firstIndex(of: points)! + 1) }

        var sources = icons.map { icon in
            var source = ImageSet.Source(name: asset.name, filename: icon.filename, path: icon.path, image: icon.image, scale: icon.scale, idiom: idioms[icon.idiom]!)
            source.kind = .appIcon
            source.dimension2 = dimension2(icon.points)
            source.jpeg = icon.jpeg
            return source
        }
        var sizeTables: [CARRendition] = []
        for (name, idiom) in idioms.sorted(by: { $0.value < $1.value }) {
            let sizes = Set(icons.filter { $0.idiom == name }.map(\.points)).sorted()
            guard !sizes.isEmpty else { continue }
            sizeTables.append(sizeTable(asset.name, idiom: idiom, sizes: sizes.map { ($0, dimension2($0)) }))
        }
        if let largePhone {
            var source = ImageSet.Source(name: asset.name, filename: largePhone.filename, path: largePhone.path, image: largePhone.image, scale: 2, idiom: Idiom.phone)
            source.kind = .appIcon
            source.dimension2 = dimension2(largePhonePoints)
            source.subtype = largePhoneSubtype
            sources.append(source)
            sizeTables.append(sizeTable(asset.name, idiom: Idiom.phone, subtype: largePhoneSubtype, sizes: [(largePhonePoints, dimension2(largePhonePoints))]))
        }

        let written: [Icon]
        switch standaloneBehavior {
        case nil: written = icons.filter { ($0.idiom == "iphone" && $0.size == "60x60" || $0.idiom == "ipad" && $0.size == "76x76") && $0.scale == 2 }
        case "all": written = icons.filter { $0.idiom != "ios-marketing" }
        default: written = []
        }
        if let jpeg = written.first(where: { $0.jpeg != nil }) {
            throw NomacError("icon PNGs from JPEG files are not supported yet (BACKLOG B-212)", path: jpeg.path)
        }
        func baseNames(_ idiom: String) -> [String] {
            var names: [String] = []
            for icon in written.filter({ $0.idiom == idiom }).sorted(by: { $0.points < $1.points }) where !names.contains(asset.name + icon.size) {
                names.append(asset.name + icon.size)
            }
            return names
        }
        func iconsKey(_ files: [String]) -> PropertyListValue {
            var primary: [String: PropertyListValue] = ["CFBundleIconName": .string(asset.name)]
            if !files.isEmpty { primary["CFBundleIconFiles"] = .array(files.map { .string($0) }) }
            return .dictionary(["CFBundlePrimaryIcon": .dictionary(primary)])
        }
        let phoneFiles = baseNames("iphone")
        var infoPlist = ["CFBundleIcons": iconsKey(phoneFiles)]
        // Beside an iPad's icon files the iPhone's; without any, none (`incomplete-icons`).
        if icons.contains(where: { $0.idiom == "ipad" }) || targetDevices.contains("ipad") {
            let padFiles = baseNames("ipad").filter { !phoneFiles.contains($0) }
            infoPlist["CFBundleIcons~ipad"] = iconsKey(padFiles.isEmpty ? [] : phoneFiles + padFiles)
        }
        let pngs = written.map { icon in
            (asset.name + icon.size + (icon.scale > 1 ? "@\(icon.scale)x" : "") + (icon.idiom == "ipad" ? "~ipad" : "") + ".png", icon)
        }
        let folder = (asset.path as NSString).lastPathComponent
        let notices = icons.filter { targetDevices.contains($0.idiom) }.sorted { (idioms[$0.idiom]!, $0.points, $0.scale) < (idioms[$1.idiom]!, $1.points, $1.scale) }.compactMap { icon in
            legacyNotices["\(icon.idiom) \(icon.size) \(icon.scale)"].map {
                "\(catalog):./\(folder)/[][\(icon.idiom)][\(icon.size)][][][\(icon.scale)x][][][][]: notice: \($0)"
            }
        }
        let required = alternate ? [] : requiredIconWarnings(icons, targetDevices: targetDevices)
        let warnings = problems.warnings(folder: folder, name: asset.name, required: required).map { "\(catalog):\($0.where): warning: \($0.message)" }
        return Compiled(sources: sources, sizeTables: sizeTables, pngs: pngs, infoPlist: infoPlist, notices: notices, warnings: warnings)
    }

    /// A single-size set (`app-icons` single-size cases): per targeted idiom a size table of
    /// 1,024 points and each appearance's image; the iPhone 60 pt and iPad 76 pt 2x PNGs resized
    /// from the default image, for any target, unless `--standalone-icon-behavior none` (`all`
    /// changes nothing); each idiom's icon name only when it is targeted.
    static func compileSingleSize(_ asset: AssetCatalog.Asset, icons: [Icon], standaloneBehavior: String?, targetDevices: [String]) throws -> Compiled {
        if icons[0].platform == "watchos" { return try compileWatch(asset, icons: icons, targetDevices: targetDevices) }
        guard [nil, "all", "none"].contains(standaloneBehavior), !targetDevices.isEmpty, Set(targetDevices).isSubset(of: ["iphone", "ipad"]) else {
            throw NomacError("single-size app icons for devices other than iPhone and iPad are not supported yet (BACKLOG B-202)", path: asset.path)
        }
        let targeted = [("iphone", Idiom.phone), ("ipad", Idiom.pad)].filter { targetDevices.contains($0.0) }
        var sources: [ImageSet.Source] = []
        for (_, idiom) in targeted {
            for icon in icons.sorted(by: { $0.appearance < $1.appearance }) {
                var source = ImageSet.Source(name: asset.name, filename: icon.filename, path: icon.path, image: icon.image, scale: 1, idiom: idiom)
                source.kind = .appIcon
                source.dimension2 = 1
                source.appearance = icon.appearance
                sources.append(source)
            }
        }
        let sizeTables = targeted.map { sizeTable(asset.name, idiom: $0.1, sizes: [(1024, 1)]) }
        let base = icons.first { $0.appearance == 0 }!
        let pngs = standaloneBehavior == "none" ? [] : [("60x60", 120, ""), ("76x76", 152, "~ipad")].map { size, pixels, suffix in
            (asset.name + size + "@2x" + suffix + ".png", Icon(idiom: "universal", size: size, scale: 2, filename: base.filename, path: base.path, image: resized(base.image, to: pixels)))
        }
        func iconsKey(_ files: [String], named: Bool) -> PropertyListValue {
            var primary: [String: PropertyListValue] = pngs.isEmpty ? [:] : ["CFBundleIconFiles": .array(files.map { .string(asset.name + $0) })]
            if named { primary["CFBundleIconName"] = .string(asset.name) }
            return .dictionary(["CFBundlePrimaryIcon": .dictionary(primary)])
        }
        let infoPlist = ["CFBundleIcons": iconsKey(["60x60"], named: targetDevices.contains("iphone")),
                         "CFBundleIcons~ipad": iconsKey(["60x60", "76x76"], named: targetDevices.contains("ipad"))]
        return Compiled(sources: sources, sizeTables: sizeTables, pngs: pngs, infoPlist: infoPlist, notices: [])
    }

    /// A single-size watchOS icon for a watch target (`watchos` experiment): its size table and
    /// each appearance's image for the watch idiom, no PNG, and only the icon's name in the
    /// partial Info.plist.
    static func compileWatch(_ asset: AssetCatalog.Asset, icons: [Icon], targetDevices: [String]) throws -> Compiled {
        guard targetDevices == ["watch"] else {
            throw NomacError("watchOS app icons for devices other than the watch are not supported yet (BACKLOG B-206)", path: asset.path)
        }
        let sources = icons.sorted(by: { $0.appearance < $1.appearance }).map { icon in
            var source = ImageSet.Source(name: asset.name, filename: icon.filename, path: icon.path, image: icon.image, scale: 1, idiom: Idiom.watch)
            source.kind = .appIcon
            source.dimension2 = 1
            source.appearance = icon.appearance
            return source
        }
        let infoPlist: [String: PropertyListValue] = ["CFBundleIcons": .dictionary(["CFBundlePrimaryIcon": .dictionary(["CFBundleIconName": .string(asset.name)])])]
        return Compiled(sources: sources, sizeTables: [sizeTable(asset.name, idiom: Idiom.watch, sizes: [(1024, 1)])], pngs: [], infoPlist: infoPlist, notices: [])
    }

    /// A multi-size watch icon set for a watch target (`watchos` multi-size case): images keyed
    /// with the watch idiom and their case size's subtype (`watch-marketing`: idiom 6), `dim2`
    /// numbering the distinct point sizes, a size table per idiom and subtype, no PNG, and only
    /// the icon's name in the partial Info.plist.
    static func compileWatchMultiSize(_ asset: AssetCatalog.Asset, icons: [Icon], targetDevices: [String]) throws -> Compiled {
        guard targetDevices == ["watch"], icons.allSatisfy({ $0.platform == "watchos" }) else {
            throw NomacError("watch app icon sets with other entries or for other devices are not supported yet (BACKLOG B-206)", path: asset.path)
        }
        let allPoints = Set(icons.map(\.points)).sorted()
        func dimension2(_ points: Double) -> UInt16 { UInt16(allPoints.firstIndex(of: points)! + 1) }
        func idiom(_ icon: Icon) -> UInt16 { icon.idiom == "watch-marketing" ? Idiom.marketing : Idiom.watch }
        let sources = icons.map { icon in
            var source = ImageSet.Source(name: asset.name, filename: icon.filename, path: icon.path, image: icon.image, scale: icon.scale, idiom: idiom(icon))
            source.kind = .appIcon
            source.dimension2 = dimension2(icon.points)
            source.subtype = icon.subtype
            return source
        }
        let groups = Dictionary(grouping: icons) { [idiom($0), $0.subtype] }
        let sizeTables = groups.keys.sorted { ($0[0], $0[1]) < ($1[0], $1[1]) }.map { key in
            sizeTable(asset.name, idiom: key[0], subtype: key[1], sizes: Set(groups[key]!.map(\.points)).sorted().map { ($0, dimension2($0)) })
        }
        let infoPlist: [String: PropertyListValue] = ["CFBundleIcons": .dictionary(["CFBundlePrimaryIcon": .dictionary(["CFBundleIconName": .string(asset.name)])])]
        return Compiled(sources: sources, sizeTables: sizeTables, pngs: [], infoPlist: infoPlist, notices: [])
    }

    /// An icon PNG resized from a single-size image: RGBA whatever the input's form, its chunks
    /// replaced by `sRGB` and an `eXIf` of color space 1 and the pixel size (`app-icons`
    /// single-size forms); the pixels are nomac's own (ADR 0204).
    static func resized(_ image: PNGImage, to size: Int) -> PNGImage {
        var resized = PNGImage(width: size, height: size, pixels: IconRenderer.downsample(image.pixels, from: image.width, to: size))
        var exif: [UInt8] = Array("MM".utf8) + [0, 42] + IconPNG.bigEndian(8) + [0, 1, 0x87, 0x69, 0, 4] + IconPNG.bigEndian(1) + IconPNG.bigEndian(26) + IconPNG.bigEndian(0)
        exif += [0, 3, 0xA0, 0x01, 0, 3] + IconPNG.bigEndian(1) + [0, 1, 0, 0]
        for tag: UInt8 in [0x02, 0x03] { exif += [0xA0, tag, 0, 4] + IconPNG.bigEndian(1) + IconPNG.bigEndian(UInt32(size)) }
        resized.ancillaryChunks = [PNGImage.Chunk(type: "sRGB", data: [0]), PNGImage.Chunk(type: "eXIf", data: exif + IconPNG.bigEndian(0))]
        return resized
    }

    /// The primary set's icon keys with alternate app icon sets (`alternate-app-icons`): a key
    /// names the primary icon and lists every alternate when `Assets.car` has app icons for its
    /// device (single-size sets for the targeted devices, multi-size sets for their own), else
    /// neither.
    static func addAlternates(_ alternates: [String], primary: String, idioms: Set<UInt16>, to compiled: inout [Compiled]) {
        let list = PropertyListValue.dictionary(Dictionary(uniqueKeysWithValues: alternates.map { ($0, .dictionary(["CFBundleIconName": .string($0)])) }))
        for index in compiled.indices {
            for (key, idiom) in [("CFBundleIcons", Idiom.phone), ("CFBundleIcons~ipad", Idiom.pad)] {
                guard case .dictionary(var keys)? = compiled[index].infoPlist[key], case .dictionary(var icon)? = keys["CFBundlePrimaryIcon"] else { continue }
                if idioms.contains(idiom) {
                    icon["CFBundleIconName"] = .string(primary)
                    keys["CFBundleAlternateIcons"] = list
                } else {
                    icon["CFBundleIconName"] = nil
                }
                keys["CFBundlePrimaryIcon"] = .dictionary(icon)
                compiled[index].infoPlist[key] = .dictionary(keys)
            }
        }
    }

    /// A part-218 rendition: `MSIS`, version 1, the count, then each size's width and height in
    /// whole points and its `dim2`.
    static func sizeTable(_ name: String, idiom: UInt16, subtype: UInt16 = 0, sizes: [(points: Double, dimension2: UInt16)]) -> CARRendition {
        var table = ByteWriter()
        table.append(Array("SISM".utf8))
        table.appendLE(UInt32(1))
        table.appendLE(UInt32(sizes.count))
        for size in sizes {
            table.appendLE(UInt32(size.points))
            table.appendLE(UInt32(size.points))
            table.appendLE(UInt32(size.dimension2))
        }
        let csi = CSI(name: name, layout: .iconSizes, properties: [(1004, [UInt8](repeating: 0, count: 8)), (1006, ImageSet.little(1))], payload: table.bytes)
        var attributes = ImageSet.attributes(scale: 1, idiom: idiom, subtype: subtype)
        attributes[.part] = 218
        return CARRendition(name: name, kind: .appIcon, attributes: attributes, csi: csi.bytes)
    }
}
