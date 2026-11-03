import Foundation
import NomacCore
import NomacEnvelope
import NomacProject
import XcodeProj

/// `nomac check`'s `assets:` domain (ADR 0011): the features of the asset catalogs a project's
/// targets compile, read from each catalog's `Contents.json` files (docs/formats/check.md).
public struct AssetsDomain: FeatureDomain {
    public let name = "assets"
    public var envelope: Envelope { AssetsEnvelope.envelope }

    public init() {}

    public func scan(_ container: String, options: CheckOptions) throws -> DomainScan {
        let workspace = try XcodeWorkspace.load(path: FileSystem.absolute(container))
        var scan = CatalogScan()
        for catalog in Self.catalogs(of: workspace, options: options, unchecked: &scan.unchecked) {
            if options.descriptionOnly {
                scan.unchecked.append(UncheckedPart(what: "asset catalog contents", file: catalog))
            } else {
                scan.scanCatalog(catalog)
            }
        }
        scan.finish()
        return DomainScan(uses: scan.uses, unchecked: scan.unchecked.sorted())
    }

    /// The `.xcassets` folders targets compile: files of resources phases, and catalogs inside
    /// the synchronized folders of targets.
    static func catalogs(of workspace: XcodeWorkspace, options: CheckOptions, unchecked: inout [UncheckedPart]) -> [String] {
        var found: [String] = []
        for project in workspace.allProjects {
            let containing = (project.path as NSString).deletingLastPathComponent
            let dirPath = project.project.projectDirPath
            let sourceRoot = dirPath.isEmpty ? containing : ((containing as NSString).appendingPathComponent(dirPath) as NSString).standardizingPath
            for target in project.pbxproj.nativeTargets {
                for phase in target.buildPhases.compactMap({ $0 as? PBXResourcesBuildPhase }) {
                    for file in phase.files ?? [] {
                        guard let element = file.file, let path = try? element.fullPath(sourceRoot: sourceRoot),
                              (path as NSString).pathExtension == "xcassets" else { continue }
                        found.append((path as NSString).standardizingPath)
                    }
                }
                for group in target.fileSystemSynchronizedGroups ?? [] {
                    guard let folder = try? group.fullPath(sourceRoot: sourceRoot) else { continue }
                    if options.descriptionOnly {
                        unchecked.append(UncheckedPart(what: "asset catalogs in a synchronized folder", file: folder))
                    } else {
                        found += catalogs(inFolder: folder)
                    }
                }
            }
        }
        var seen: Set<String> = []
        return found.filter { seen.insert($0).inserted }
    }

    static func catalogs(inFolder folder: String) -> [String] {
        guard let entries = try? FileSystem.sortedContents(of: folder) else { return [] }
        var found: [String] = []
        for entry in entries where !entry.hasPrefix(".") {
            let path = folder + "/" + entry
            guard FileSystem.isDirectory(path) else { continue }
            if (entry as NSString).pathExtension == "xcassets" {
                found.append(path)
            } else {
                found += catalogs(inFolder: path)
            }
        }
        return found
    }
}

/// One pass over asset catalogs, recording each feature where a `Contents.json` uses it.
struct CatalogScan {
    var uses: [FeatureUse] = []
    var unchecked: [UncheckedPart] = []
    private var typesByName: [String: Set<String>] = [:]
    private var catalogs: [String] = []

    mutating func use(_ feature: String, _ file: String, _ object: String) {
        uses.append(FeatureUse(feature: feature, file: file, object: object))
    }

    mutating func scanCatalog(_ catalog: String) {
        catalogs.append(catalog)
        use("assets:catalog", catalog, (catalog as NSString).lastPathComponent)
        scanFolder(catalog, namespace: "", catalog: catalog)
    }

    private mutating func scanFolder(_ folder: String, namespace: String, catalog: String) {
        guard let entries = try? FileSystem.sortedContents(of: folder) else {
            unchecked.append(UncheckedPart(what: "unreadable asset catalog folder", file: folder))
            return
        }
        for entry in entries where !entry.hasPrefix(".") {
            let path = folder + "/" + entry
            guard FileSystem.isDirectory(path) else { continue }
            if let type = AssetCatalog.assetType(of: entry) {
                scanAsset(path, type: type, name: namespace + (entry as NSString).deletingPathExtension)
                if type == "spriteatlas" {
                    scanFolder(path, namespace: namespace, catalog: catalog)
                }
            } else {
                let contents = (try? AssetCatalog.readContents(path, required: false)) ?? [:]
                let properties = contents["properties"] as? [String: Any] ?? [:]
                let providesNamespace = properties["provides-namespace"] as? Bool ?? false
                use(providesNamespace ? "assets:folder=namespace" : "assets:folder=group", path, entry)
                for key in properties.keys.sorted() where key != "provides-namespace" {
                    use("assets:folder.properties.\(key)", path + "/Contents.json", entry)
                }
                scanFolder(path, namespace: providesNamespace ? namespace + entry + "/" : namespace, catalog: catalog)
            }
        }
    }

    private mutating func scanAsset(_ path: String, type: String, name: String) {
        let file = path + "/Contents.json"
        use("assets:\(type)", path, name)
        typesByName[name, default: []].insert(type)
        if name.unicodeScalars.contains(where: { !$0.isASCII }) {
            use("assets:name=non-ascii", path, name)
        }
        // The keys of types nomac does not compile are not listed: the type itself is outside.
        guard AssetCatalog.supportedTypes.contains(type) else { return }
        if type == "imageset" && !FileManager.default.fileExists(atPath: path + "/Contents.json") {
            use("assets:imageset.contents=missing", path, name)
            return
        }
        guard let contents = try? AssetCatalog.readContents(path, required: true) else {
            use("assets:\(type).contents=unreadable", path, name)
            return
        }
        for key in contents.keys.sorted() where !["info", "colors", "data", "images", "layers", "properties", "symbols"].contains(key) {
            use("assets:\(type).key=\(key)", file, name)
        }
        for key in (contents["properties"] as? [String: Any] ?? [:]).keys.sorted() {
            use("assets:\(type).properties.\(key)", file, name)
        }
        switch type {
        case "colorset": scanColors(contents["colors"] as? [[String: Any]] ?? [], file: file, name: name)
        case "dataset": scanData(contents["data"] as? [[String: Any]] ?? [], file: file, name: name)
        case "imageset": scanImages(contents["images"] as? [[String: Any]] ?? [], folder: path, file: file, name: name)
        case "appiconset":
            let files = (contents["images"] as? [[String: Any]] ?? []).filter { $0["filename"] != nil }
            let multiSize = files.allSatisfy { entry in
                AppIconSet.slots[entry["idiom"] as? String ?? ""]?[entry["size"] as? String ?? ""] != nil
            }
            let singleSize = files.allSatisfy { $0["idiom"] as? String == "universal" && $0["platform"] as? String == "ios" && $0["size"] as? String == "1024x1024" }
            use("assets:appiconset.images=\(files.isEmpty ? "none" : multiSize ? "multi-size" : singleSize ? "single-size" : "other")", file, name)
        case "launchimage":
            let images = contents["images"] as? [[String: Any]] ?? []
            use("assets:launchimage.images=\(images.contains { $0["filename"] != nil } ? "files" : "none")", file, name)
        case "symbolset":
            for entry in contents["symbols"] as? [[String: Any]] ?? [] {
                guard let filename = entry["filename"] as? String, let data = FileManager.default.contents(atPath: path + "/" + filename) else { continue }
                let layerTree = String(decoding: data, as: UTF8.self).contains(#"id="LayerTree""#)
                use("assets:symbolset.template=\(layerTree ? "layer-tree" : "glyphs")", path + "/" + filename, name)
            }
        default: break
        }
    }

    private mutating func scanColors(_ entries: [[String: Any]], file: String, name: String) {
        for entry in entries {
            use("assets:colorset.idiom=\(entry["idiom"] as? String ?? "universal")", file, name)
            for key in entry.keys.sorted() where !["color", "idiom", "appearances", "display-gamut"].contains(key) {
                use("assets:colorset.entry.\(key)", file, name)
            }
            let appearances = (entry["appearances"] as? [[String: Any]] ?? []).map { "\($0["appearance"] as? String ?? ""):\($0["value"] as? String ?? "")" }
            if !appearances.isEmpty {
                use("assets:colorset.appearance=\(appearances.joined(separator: "+"))", file, name)
            }
            if let gamut = entry["display-gamut"] as? String {
                use("assets:colorset.display-gamut=\(gamut)", file, name)
            }
            guard let color = entry["color"] as? [String: Any] else {
                use("assets:colorset.color=none", file, name)
                continue
            }
            if color["reference"] != nil || color["platform"] != nil {
                let platform = color["platform"] as? String
                let known = (color["reference"] as? String).flatMap { SystemColors.values[$0] }
                let reproduced = known.map { platform == "ios" || (platform == "universal" && $0.universal) } ?? false
                    && (appearances.isEmpty || appearances == ["luminosity:dark"])
                use(reproduced ? "assets:colorset.color=reference" : "assets:colorset.color=reference-other", file, name)
                continue
            }
            use("assets:colorset.color-space=\(color["color-space"] as? String ?? "none")", file, name)
            for value in (color["components"] as? [String: Any] ?? [:]).values {
                use("assets:colorset.component=\(Self.componentSpelling(value))", file, name)
            }
        }
    }

    /// How a color component is written, in the classes actool reads differently
    /// (docs/formats/asset-catalog.md, "Colors").
    static func componentSpelling(_ value: Any) -> String {
        guard let text = value as? String else { return "not-a-string" }
        if text.contains(".") { return "decimal" }
        if text.hasPrefix("0x") || text.hasPrefix("0X") { return text.count <= 4 ? "hexadecimal" : "hexadecimal-long" }
        return "integer"
    }

    private mutating func scanData(_ entries: [[String: Any]], file: String, name: String) {
        for entry in entries {
            use("assets:dataset.idiom=\(entry["idiom"] as? String ?? "universal")", file, name)
            for key in entry.keys.sorted() where !["filename", "idiom", "universal-type-identifier"].contains(key) {
                use("assets:dataset.entry.\(key)", file, name)
            }
            guard let filename = entry["filename"] as? String else { continue }
            if entry["universal-type-identifier"] != nil {
                use("assets:dataset.type=explicit", file, name)
            } else if DataSet.typeIdentifiers[(filename as NSString).pathExtension] != nil {
                use("assets:dataset.type=from-extension", file, name)
            } else {
                use("assets:dataset.type=unknown-extension", file, name)
            }
        }
    }

    /// Each entry's idiom and scale, and of the image files their type, PNG form and whether
    /// their pixels are gray (stored as `GA8`).
    private mutating func scanImages(_ entries: [[String: Any]], folder: String, file: String, name: String) {
        let files = entries.compactMap { $0["filename"] as? String }
        if files.count > 1 {
            use("assets:imageset.images=several", file, name)
        }
        for entry in entries {
            for key in entry.keys.sorted() where !["filename", "idiom", "scale"].contains(key) {
                use("assets:imageset.entry.\(key)", file, name)
            }
            guard let filename = entry["filename"] as? String else {
                use("assets:imageset.image=none", file, name)
                continue
            }
            use("assets:imageset.image=\(entry["idiom"] as? String ?? "universal")-\(entry["scale"] as? String ?? "1x")", file, name)
            let type = (filename as NSString).pathExtension.lowercased()
            use("assets:imageset.file=\(type)", file, name)
            guard type == "png" else { continue }
            let path = folder + "/" + filename
            guard FileManager.default.fileExists(atPath: path) else {
                use("assets:imageset.file=missing", file, name)
                continue
            }
            let image: PNGImage
            do {
                image = try PNGImage(contentsOf: path)
            } catch let error as NomacError where error.message.contains("BACKLOG B-213") {
                use("assets:imageset.png=color-profile-other", path, name)
                continue
            } catch {
                use("assets:imageset.png=unsupported", path, name)
                continue
            }
            if image.convertedColors {
                use("assets:imageset.png=color-profile", path, name)
            }
            if ImageSet.isGray(image.pixels) {
                use("assets:imageset.pixels=gray", path, name)
            }
        }
    }

    /// Features of the catalogs taken together, which actool compiles into one `Assets.car`:
    /// names of several asset types, identifier collisions and the size of `BITMAPKEYS`.
    mutating func finish() {
        guard let file = catalogs.first else { return }
        let names = typesByName.keys.sorted()
        for name in names where typesByName[name]!.count > 1 {
            use("assets:names=same-name-several-types", file, name)
        }
        let identifiers = RenditionIdentifier.assign(names)
        if names.contains(where: { identifiers[$0] != RenditionIdentifier.primary($0) }) {
            use("assets:identifiers=collision", file, "\(names.count) names")
        }
        if names.count > 126 {
            use("assets:identifiers=more-than-126", file, "\(names.count) names")
        }
    }
}
