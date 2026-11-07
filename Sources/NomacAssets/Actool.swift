import Foundation
import NomacCore
import NomacPlist

/// nomac's replacement for Xcode's `actool`: the same command line, the same outputs
/// (`Assets.car`, the partial Info.plist, the dependency info and the report on standard
/// output), as Xcode 27.0's actool writes them (docs/formats/asset-catalog.md).
public struct Actool {
    public enum Mode: Equatable {
        case compile(String)
        case version
        case printAssetTagCombinations
    }

    public struct Options {
        public var mode: Mode
        public var catalogs: [String] = []
        public var outputFormat = "human-readable-text"
        public var dependencyInfo: String?
        public var partialInfoPlist: String?
        public var appIcon: String?
        public var alternateAppIcons: [String] = []
        public var widgetBackgroundColor: String?
        public var standaloneIconBehavior: String?
        public var includeAllAppIcons = false
        public var accentColor: String?
        public var complication: String?
        public var targetDevices: [String] = []
        public var minimumDeploymentTarget: String?
        public var platform: String?
        public var bundleIdentifier: String?
        public var swiftSymbols: String?
        public var objectiveCSymbols: String?
        public var symbolIndex: String?
        public var swiftSymbolExtensions = true
        public var compressPNGs = false
        public var includeStickerContent = false
        public var stickersIconRole: String?
        public var stickerPackIdentifierPrefix: String?
        /// `--warnings`, which `--notices` includes, and `--notices` print the document's messages.
        public var printsDocumentWarnings = false
        public var printsDocumentNotices = false

        /// Any of the symbol files makes actool write those and nothing else, even with `--compile`.
        var generatesSymbols: Bool { swiftSymbols != nil || objectiveCSymbols != nil || symbolIndex != nil }

        /// Options that change nothing in the outputs nomac writes so far.
        static let acceptedFlags: Set<String> = ["--errors", "--enable-icon-stack-fallback-generation=disabled"]
        static let acceptedValues: Set<String> = ["--enable-on-demand-resources", "--development-region"]

        public init(arguments: [String]) throws {
            var mode: Mode?
            var iterator = arguments.makeIterator()
            func value(_ flag: String) throws -> String {
                guard let next = iterator.next() else { throw NomacError("actool: \(flag) needs a value") }
                return next
            }
            var catalogs: [String] = []
            while let argument = iterator.next() {
                switch argument {
                case "--compile": mode = .compile(try value(argument))
                case "--version": mode = .version
                case "--print-asset-tag-combinations": mode = .printAssetTagCombinations
                case "--output-format": outputFormat = try value(argument)
                case "--export-dependency-info": dependencyInfo = try value(argument)
                case "--output-partial-info-plist": partialInfoPlist = try value(argument)
                case "--app-icon": appIcon = try value(argument)
                case "--alternate-app-icon": alternateAppIcons.append(try value(argument))
                case "--widget-background-color": widgetBackgroundColor = try value(argument)
                case "--standalone-icon-behavior": standaloneIconBehavior = try value(argument)
                case "--include-all-app-icons": includeAllAppIcons = true
                case "--compress-pngs": compressPNGs = true
                case "--warnings": printsDocumentWarnings = true
                case "--notices": (printsDocumentWarnings, printsDocumentNotices) = (true, true)
                case "--include-sticker-content": includeStickerContent = true
                case "--stickers-icon-role": stickersIconRole = try value(argument)
                case "--sticker-pack-identifier-prefix": stickerPackIdentifierPrefix = try value(argument)
                case "--accent-color": accentColor = try value(argument)
                case "--complication": complication = try value(argument)
                case "--target-device": targetDevices.append(try value(argument))
                case "--minimum-deployment-target": minimumDeploymentTarget = try value(argument)
                case "--platform": platform = try value(argument)
                case "--bundle-identifier": bundleIdentifier = try value(argument)
                case "--generate-swift-asset-symbols": swiftSymbols = try value(argument)
                case "--generate-objc-asset-symbols": objectiveCSymbols = try value(argument)
                case "--generate-asset-symbol-index": symbolIndex = try value(argument)
                case "--generate-swift-asset-symbol-extensions":
                    switch try value(argument) {
                    case "YES": swiftSymbolExtensions = true
                    case "NO": swiftSymbolExtensions = false
                    case let other: throw NomacError("actool: --generate-swift-asset-symbol-extensions takes YES or NO, not \(other)")
                    }
                case _ where Self.acceptedFlags.contains(argument): break
                case _ where Self.acceptedValues.contains(argument): _ = try value(argument)
                case _ where argument.hasPrefix("--"):
                    throw NomacError("actool: option \(argument) is not supported yet (BACKLOG B-204)")
                default: catalogs.append(argument)
                }
            }
            guard let mode else { throw NomacError("actool: one of --compile, --version or --print-asset-tag-combinations is required") }
            self.mode = mode
            self.catalogs = catalogs
        }
    }

    /// What a run printed and wrote.
    public struct Result {
        public var standardOutput: String
        public var writtenFiles: [String]
        /// actool reported an error: it still writes its outputs but exits with 1.
        public var failed = false
    }

    public static func run(_ options: Options) throws -> Result {
        switch options.mode {
        case .version:
            return Result(standardOutput: versionReport(format: options.outputFormat), writtenFiles: [])
        case .printAssetTagCombinations:
            guard options.outputFormat == "xml1" else {
                throw NomacError("actool: --print-asset-tag-combinations is supported with --output-format xml1 only (BACKLOG B-204)")
            }
            let catalog = try AssetCatalog.load(options.catalogs.map(FileSystem.absolute))
            if catalog.assets.contains(where: { $0.contents["properties"] != nil && ($0.contents["properties"] as? [String: Any])?["on-demand-resource-tags"] != nil }) {
                throw NomacError("actool: on-demand resource tags are not supported yet (BACKLOG B-205)")
            }
            return Result(standardOutput: xml(.dictionary(["com.apple.actool.asset-tag-combinations": .array([])])), writtenFiles: [])
        case .compile where options.generatesSymbols:
            return try generateSymbols(options)
        case .compile(let directory):
            return try compile(options, into: FileSystem.absolute(directory))
        }
    }

    static func versionReport(format: String) -> String {
        if format == "xml1" {
            // Xcode 27.0's actool version, which Swift Build's probe reads, and nomac's own under
            // `nomac` (docs/adr/0102-linker.md, "Tool probes").
            return xml(.dictionary([
                "com.apple.actool.version": .dictionary([
                    "bundle-version": .string(ActoolVersions.bundleVersion), "short-bundle-version": .string(ActoolVersions.shortBundleVersion),
                ]),
                "nomac": .dictionary(["version": .string(NomacVersion.current)]),
            ]))
        }
        return "/* com.apple.actool.version */\nbundle-version: \(ActoolVersions.bundleVersion)\nshort-bundle-version: \(ActoolVersions.shortBundleVersion)\n\n"
    }

    /// Values of `--standalone-icon-behavior` that change nothing without app icon images, where
    /// nomac stops (`colors`, standalone-icon-behavior cases).
    static let standaloneIconBehaviors: Set<String> = ["all", "none"]

    static func compile(_ options: Options, into directory: String) throws -> Result {
        guard options.outputFormat == "human-readable-text" else {
            throw NomacError("actool: --output-format \(options.outputFormat) is not supported yet (BACKLOG B-204)")
        }
        let platform = try Platform(options)
        guard let deploymentTarget = options.minimumDeploymentTarget else {
            throw NomacError("actool: --minimum-deployment-target is required")
        }
        let catalogPaths = options.catalogs.map(FileSystem.absolute)
        let iconPaths = catalogPaths.filter { ($0 as NSString).pathExtension == "icon" }
        func iconName(_ path: String) -> String { ((path as NSString).lastPathComponent as NSString).deletingPathExtension }
        // Icon Composer icons compile when `--app-icon` or `--alternate-app-icon` names them, all of
        // them with `--include-all-app-icons` or when no icon is named (`alternate-icons` cases).
        let named = Set([options.appIcon].compactMap { $0 } + options.alternateAppIcons)
        let compiledIconPaths = options.includeAllAppIcons || named.isEmpty ? iconPaths : iconPaths.filter { named.contains(iconName($0)) }
        let icons = try compiledIconPaths.map(IconComposerIcon.init)
        if let behavior = options.standaloneIconBehavior, !Self.standaloneIconBehaviors.contains(behavior) {
            throw NomacError("actool: --standalone-icon-behavior \(behavior) is not supported yet (BACKLOG B-202)")
        }
        let catalog = try AssetCatalog.load(catalogPaths.filter { !iconPaths.contains($0) }, complication: options.complication)
        // Alternate icons: Icon Composer icons, or app icon sets with images (`alternate-icons`,
        // `alternate-app-icons` cases); all of them with `--include-all-app-icons`.
        let iconSetNames = catalog.assets.filter { $0.type == "appiconset" && !(($0.contents["images"] as? [[String: Any]]) ?? []).allSatisfy { $0["filename"] == nil } }.map(\.name)
        let alternates = (options.includeAllAppIcons ? iconPaths.map(iconName) + iconSetNames : options.alternateAppIcons).filter { $0 != options.appIcon }
        let iconAlternates = alternates.filter { name in iconPaths.contains { iconName($0) == name } }, setAlternates = alternates.filter(iconSetNames.contains)
        guard iconAlternates.count + setAlternates.count == alternates.count else {
            throw NomacError("actool: alternate app icons other than Icon Composer icons or app icon sets are not supported yet (BACKLOG B-202)")
        }
        var errors: [String] = []
        var appIcons: [AppIconSet.Compiled] = []
        // App icon sets neither `--app-icon` nor an alternate names add nothing (`app-icons`
        // icons-not-named); alternates give renditions only.
        for asset in catalog.assets where asset.type == "appiconset" && (asset.name == options.appIcon || setAlternates.contains(asset.name)) {
            var problems = AppIconSet.Problems()
            let icons = try AppIconSet.icons(asset, watch: platform.watch, problems: &problems)
            guard !icons.isEmpty else {
                // Files only of other platforms: actool's error; no files at all: nothing (`app-icons`).
                if asset.name == options.appIcon, (asset.contents["images"] as? [[String: Any]] ?? []).contains(where: { $0["filename"] != nil }) {
                    errors.append("\(catalogPaths[0]): error: The stickers icon set, app icon set, or icon stack named \"\(asset.name)\" did not have any applicable content.")
                }
                continue
            }
            let catalogPath = catalogPaths.first { asset.path.hasPrefix($0 + "/") } ?? catalogPaths[0]
            var compiled = try AppIconSet.compile(asset, icons: icons, problems: problems, catalog: catalogPath, standaloneBehavior: options.standaloneIconBehavior,
                                                  targetDevices: options.targetDevices, alternate: asset.name != options.appIcon)
            if asset.name != options.appIcon {
                guard compiled.notices.isEmpty else { throw NomacError("actool: alternate app icon sets of legacy sizes are not supported yet (BACKLOG B-202)", path: asset.path) }
                compiled.pngs = []
                compiled.infoPlist = [:]
            }
            appIcons.append(compiled)
        }
        if !setAlternates.isEmpty, let primary = options.appIcon {
            AppIconSet.addAlternates(alternates.sorted(), primary: primary, idioms: Set(appIcons.flatMap { $0.sources.map(\.idiom) }), to: &appIcons)
        }
        if appIcons.contains(where: { !$0.pngs.isEmpty }) && !options.compressPNGs {
            throw NomacError("actool: app icons without --compress-pngs are not supported yet (BACKLOG B-202)")
        }
        for asset in catalog.assets where asset.type == "launchimage" {
            try LaunchImageSet.check(asset)
        }
        let iconSets = catalog.assets.filter { $0.type == "stickersiconset" }, packs = catalog.assets.filter { $0.type == "stickerpack" }
        var stickers: StickerCatalog.Compiled?
        if options.includeStickerContent || !iconSets.isEmpty || !packs.isEmpty {
            guard options.includeStickerContent, options.stickersIconRole == "extension", let prefix = options.stickerPackIdentifierPrefix,
                  iconSets.count == 1, packs.count == 1, iconSets[0].name == options.appIcon, options.compressPNGs else {
                throw NomacError("actool: sticker catalogs other than one stickers icon set named by --app-icon and one sticker pack, compiled with --include-sticker-content, --stickers-icon-role extension and --compress-pngs, are not supported yet (BACKLOG B-204)")
            }
            stickers = try StickerCatalog.compile(iconSet: iconSets[0], pack: packs[0], identifierPrefix: prefix)
        }
        if let appIcon = options.appIcon, !catalog.assets.contains(where: { ["appiconset", "stickersiconset"].contains($0.type) && $0.name == appIcon }),
           !icons.contains(where: { $0.name == appIcon }) {
            errors.append("\(catalogPaths[0]): error: None of the input catalogs contained a matching stickers icon set, app icon set, or icon stack named  \"\(appIcon)\".")
        }
        let idioms = platform.idioms(targetDevices: options.targetDevices)
        var renditions: [CARRendition] = []
        for asset in catalog.assets {
            switch asset.type {
            case "colorset": renditions += try ColorSet.renditions(asset, idioms: idioms, watch: platform.watch)
            case "dataset": renditions += try DataSet.renditions(asset, idioms: idioms)
            default: break
            }
        }
        for stack in catalog.assets where stack.type == "solidimagestack" {
            try SolidImageStack.check(stack.path)
        }
        renditions += appIcons.flatMap(\.sizeTables)
        if let member = catalog.assets.first(where: { $0.spriteAtlas != nil && $0.type != "imageset" }) {
            throw NomacError("sprite atlases holding assets other than image sets are not supported yet (BACKLOG B-202)", path: member.path)
        }
        let imageSets = catalog.assets.filter { $0.type == "imageset" }
        let symbolSets = try catalog.assets.filter { $0.type == "symbolset" }.map { try SymbolSet.compile($0, watch: platform.watch) }
        renditions += symbolSets.flatMap(\.renditions)
        let images = try imageSets.filter { $0.spriteAtlas == nil }.flatMap { try ImageSet.sources($0, idioms: idioms, platform: platform) } + appIcons.flatMap(\.sources)
            + (stickers.map { [$0.storeIcon] } ?? []) + symbolSets.flatMap(\.sources)
        let spriteAtlases = try catalog.assets.filter { $0.type == "spriteatlas" }.map { atlas in
            (atlas: atlas, members: try imageSets.filter { $0.spriteAtlas == atlas.name }.flatMap { try ImageSet.sources($0, idioms: idioms, platform: platform) })
        }
        var compiledIcons: [(icon: IconComposerIcon, compiled: IconComposerIcon.Compiled)] = []
        if !images.isEmpty || !spriteAtlases.isEmpty || !icons.isEmpty {
            guard platform.iOSMajorVersion(deploymentTarget) >= 13 else {
                throw NomacError("actool: image sets for deployment targets before iOS 13.0 are not supported yet (BACKLOG B-200)")
            }
            let names = renditions.map(\.name) + images.map(\.name) + spriteAtlases.flatMap { [$0.atlas.name] + $0.members.map(\.name) }
                + icons.flatMap(\.facetNames)
            let identifiers = RenditionIdentifier.assign(Array(Set(names)))
            for icon in icons {
                let compiled = try icon.compile(identifiers: identifiers, appIcon: icon.name == options.appIcon, alternates: alternates.sorted(),
                                                targetDevices: options.targetDevices)
                compiledIcons.append((icon, compiled))
                renditions += compiled.renditions
            }
            if compiledIcons.contains(where: { !$0.compiled.pngs.isEmpty }) && !options.compressPNGs {
                throw NomacError("actool: Icon Composer icons without --compress-pngs are not supported yet (BACKLOG B-210)")
            }
            renditions += try ImageSet.renditions(images + compiledIcons.flatMap(\.compiled.sources), identifiers: identifiers)
            for (atlas, members) in spriteAtlases {
                renditions += try SpriteAtlas.renditions(atlas, members: members, identifiers: identifiers)
            }
        }

        var notices: [String] = []
        var partial: [String: PropertyListValue] = [:]
        for appIcon in appIcons { partial.merge(appIcon.infoPlist) { $1 } }
        for (_, compiled) in compiledIcons { partial.merge(compiled.infoPlist) { $1 } }
        if let stickers { partial.merge(stickers.infoPlist) { $1 } }
        for (key, label, name) in [("NSAccentColorName", "Accent", options.accentColor), ("NSWidgetBackgroundColorName", "Background", options.widgetBackgroundColor)] {
            guard let name else { continue }
            // A color set without a color gives neither the key nor the warning (icecubes).
            if renditions.contains(where: { $0.kind == .color && $0.name == name }) {
                partial[key] = .string(name)
            } else if !catalog.assets.contains(where: { $0.type == "colorset" && $0.name == name }) {
                notices.append("\(catalogPaths[0]): warning: \(label) color ‘\(name)’ is not present in any asset catalogs.")
            }
        }
        if let complication = options.complication {
            if catalog.assets.contains(where: { $0.type == "complicationset" }) {
                partial["CLKComplicationDefaultImagesAssetName"] = .string(complication)
            } else {
                notices.append("\(catalogPaths[0]): warning: The asset catalog does not contain a complication named \"\(complication)\".")
            }
        }

        let documentWarnings = options.printsDocumentWarnings ? appIcons.flatMap(\.warnings) : []
        let documentNotices = options.printsDocumentNotices ? appIcons.flatMap(\.notices) : []

        var outputs: [String] = []
        try FileSystem.createDirectory(directory)
        let pngs = appIcons.flatMap { $0.pngs.map { ($0.filename, $0.icon.image, $0.icon.path) } } + (stickers?.pngs.map { ($0.filename, $0.image, $0.path) } ?? [])
            + compiledIcons.flatMap { icon in icon.compiled.pngs.map { ($0.filename, $0.image, icon.icon.path) } }
        for (filename, image, source) in pngs {
            let path = directory + "/" + filename
            if !image.iconIsUnwritable { try FileSystem.write(Data(try IconPNG.data(image, path: source)), to: path) }
            outputs.append(path)
        }
        if let pack = stickers?.pack {
            let folder = directory + "/" + pack.folder
            for file in pack.files {
                guard let data = FileManager.default.contents(atPath: file.path) else { throw NomacError("could not read the sticker", path: file.path) }
                try FileSystem.write(data, to: folder + "/" + file.name)
            }
            try FileSystem.write(pack.infoPlist, to: folder + "/Info.plist")
            outputs.append(folder)
        }
        if !renditions.isEmpty {
            let car = CARWriter(deploymentPlatform: platform.carName, deploymentPlatformVersion: deploymentTarget)
            let path = directory + "/Assets.car"
            try FileSystem.write(Data(try car.write(renditions)), to: path)
            outputs.append(path)
        }
        if let plist = options.partialInfoPlist.map(FileSystem.absolute) {
            try FileSystem.write(XMLPropertyList.data(.dictionary(partial)), to: plist)
            outputs.append(plist)
        }
        outputs.sort(by: pathPrecedes)
        if let dependencies = options.dependencyInfo.map(FileSystem.absolute) {
            try FileSystem.write(Data(dependencyInfo(inputs: catalogPaths, outputs: outputs)), to: dependencies)
        }

        var report = ""
        if !errors.isEmpty {
            report += "/* com.apple.actool.errors */\n" + errors.map { $0 + "\n" }.joined()
        }
        if !notices.isEmpty {
            report += "/* com.apple.actool.notices */\n" + notices.map { $0 + "\n" }.joined()
        }
        if !documentWarnings.isEmpty {
            report += "/* com.apple.actool.document.warnings */\n" + documentWarnings.map { $0 + "\n" }.joined()
        }
        if !documentNotices.isEmpty {
            report += "/* com.apple.actool.document.notices */\n" + documentNotices.map { $0 + "\n" }.joined()
        }
        report += "/* com.apple.actool.compilation-results */\n" + outputs.map { $0 + "\n" }.joined() + "\n"
        return Result(standardOutput: report, writtenFiles: outputs, failed: !errors.isEmpty)
    }

    /// Swift Build's `GenerateAssetSymbols` task (docs/formats/asset-catalog.md, "Asset symbols").
    static func generateSymbols(_ options: Options) throws -> Result {
        guard options.outputFormat == "human-readable-text" else {
            throw NomacError("actool: --output-format \(options.outputFormat) is not supported yet (BACKLOG B-204)")
        }
        let platform = try Platform(options)
        guard let deploymentTarget = options.minimumDeploymentTarget else {
            throw NomacError("actool: --minimum-deployment-target is required")
        }
        let symbols = AssetSymbols(
            assets: try AssetSymbols.scan(options.catalogs.map(FileSystem.absolute), targetDevices: options.targetDevices, complication: options.complication),
            options: AssetSymbols.Options(bundleIdentifier: options.bundleIdentifier, backDeployment: platform.iOSMajorVersion(deploymentTarget) < 17, extensions: options.swiftSymbolExtensions))
        var outputs: [String] = []
        if let path = options.symbolIndex.map(FileSystem.absolute) {
            try FileSystem.write(Data(symbols.index()), to: path)
            outputs.append(path)
        }
        if let path = options.objectiveCSymbols.map(FileSystem.absolute) {
            try FileSystem.write(Data(try symbols.objectiveCHeader().utf8), to: path)
            outputs.append(path)
        }
        if let path = options.swiftSymbols.map(FileSystem.absolute) {
            try FileSystem.write(Data(try symbols.swiftSource().utf8), to: path)
            outputs.append(path)
        }
        outputs.sort(by: pathPrecedes)
        let report = "/* com.apple.actool.compilation-results */\n" + outputs.map { $0 + "\n" }.joined() + "\n"
        return Result(standardOutput: report, writtenFiles: outputs)
    }

    /// actool reports its outputs, and lists them in the dependency info, in path order
    /// (retro-rampage's thinned variant: the partial Info.plist before `Assets.car`).
    static func pathPrecedes(_ a: String, _ b: String) -> Bool {
        a.utf8.lexicographicallyPrecedes(b.utf8)
    }

    /// The platforms nomac compiles for: iOS devices, and watchOS (`watchos` experiment, B-206).
    struct Platform {
        var name: String
        /// The deployment platform `Assets.car`'s header names.
        var carName: String
        /// The scales of image files kept, and those SVG files are rasterized at.
        var fileScales: Set<Int>
        var rasterScales: [Int]

        init(_ options: Options) throws {
            switch (options.platform, options.targetDevices) {
            case ("iphoneos", _): (name, carName, fileScales, rasterScales) = ("iphoneos", "ios", [1, 2, 3], [1, 2, 3])
            case ("watchos", ["watch"]): (name, carName, fileScales, rasterScales) = ("watchos", "watch", [1, 2], [2])
            default:
                throw NomacError("actool: platform \(options.platform ?? "(none)") for devices \(options.targetDevices) is not supported yet (BACKLOG B-206)")
            }
            if name == "watchos", let target = options.minimumDeploymentTarget, iOSMajorVersion(target) < 13 {
                throw NomacError("actool: watchOS before 6.0 is not supported yet (BACKLOG B-206)")
            }
        }

        var watch: Bool { name == "watchos" }

        /// The idioms a catalog keeps: universal, and the targeted iOS devices.
        func idioms(targetDevices: [String]) -> [String: UInt16] {
            watch ? ["universal": Idiom.universal, "watch": Idiom.watch] : Idiom.iOS(targetDevices: targetDevices)
        }

        /// The iOS release a deployment target matches (watchOS 6 shipped with iOS 13).
        func iOSMajorVersion(_ version: String) -> Int {
            Actool.majorVersion(version) + (watch ? 7 : 0)
        }
    }

    static func majorVersion(_ version: String) -> Int {
        Int(version.prefix { $0 != "." }) ?? 0
    }

    static func xml(_ value: PropertyListValue) -> String {
        String(decoding: XMLPropertyList.data(value), as: UTF8.self)
    }

    /// ld64's dependency-info format: a version record, then one record per input and output.
    static func dependencyInfo(inputs: [String], outputs: [String]) -> [UInt8] {
        var bytes: [UInt8] = []
        func record(_ opcode: UInt8, _ text: String) {
            bytes.append(opcode)
            bytes += Array(text.utf8)
            bytes.append(0)
        }
        record(0x00, "actool-\(ActoolVersions.bundleVersion)")
        for input in inputs { record(0x10, input) }
        for output in outputs { record(0x40, output) }
        return bytes
    }
}
