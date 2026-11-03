import Foundation
import NomacCore
import NomacPlist

/// The symbol files actool writes for the color and image sets of its catalogs, as Swift Build's
/// `GenerateAssetSymbols` task asks for them (docs/formats/asset-catalog.md, "Asset symbols").
struct AssetSymbols {
    enum Kind: String {
        case color, image
    }

    struct Asset {
        var kind: Kind
        /// A symbol set: an image in the Swift file and the header, under `symbols` in the index.
        var isSymbolSet = false
        /// Without an entry for `universal` or for every target device: its Swift members are
        /// made with `thinnableName:` and are optional in the extensions.
        var isThinnable = false
        /// The namespace folders around the set, outermost first.
        var namespaces: [String]
        /// The set's folder name without its extension.
        var name: String
        var catalog: String
        /// The set's folder from its catalog, as `./Folder/name.imageset`.
        var relativePath: String

        /// The catalog's `generate-swift-asset-symbol-extensions` property: `enabled` or
        /// `disabled`, else the option decides.
        var catalogExtensions: Bool?

        var fullName: String { (namespaces + [name]).joined(separator: "/") }
    }

    /// What the symbols are written against: `DeveloperToolsSupport`'s resource types from iOS 17
    /// on, otherwise the file's own copies of them ("Backwards Deployment Support").
    struct Options {
        var bundleIdentifier: String?
        var backDeployment: Bool
        var extensions: Bool
    }

    var assets: [Asset]
    var options: Options

    // MARK: Reading the catalogs

    /// Color, image and symbol sets for which the build has something: an entry for `universal`
    /// or a target device (colors and symbols also `car` on iPhone) with a color, or naming an
    /// image file. Data sets, app icon sets, launch images, visionOS icon stacks and Icon
    /// Composer icons are left out;
    /// sprite atlases are read as folders (the `symbols` experiment, swiftfin).
    static func scan(_ catalogs: [String], targetDevices: [String], complication: String?) throws -> [Asset] {
        var assets: [Asset] = []
        for catalog in catalogs where (catalog as NSString).pathExtension != "icon" {
            let start = assets.count
            try scan(folder: catalog, relativePath: ".", namespaces: [], catalog: catalog, targetDevices: targetDevices, complication: complication, into: &assets)
            let extensions = try catalogExtensions(catalog)
            for index in start..<assets.count { assets[index].catalogExtensions = extensions }
        }
        return assets
    }

    /// A catalog's own setting for the extensions, which overrides the option for its assets
    /// (home-assistant's Colors.xcassets; `symbol-extensions`; folders inside have none). actool
    /// warns about other values, where nomac stops.
    static func catalogExtensions(_ catalog: String) throws -> Bool? {
        let properties = try AssetCatalog.readContents(catalog, required: false)["properties"] as? [String: Any]
        switch properties?["generate-swift-asset-symbol-extensions"] {
        case nil: return nil
        case "enabled" as String: return true
        case "disabled" as String: return false
        case let value?:
            throw NomacError("asset symbol extensions set to '\(value)' are not supported: actool warns about it (BACKLOG B-204)", path: catalog)
        }
    }

    /// The idioms of entries actool calls unassigned children on iOS, with a warning.
    static let unassignedIdioms: [String: Set<String>] = [
        "colorset": ["ios-marketing"], "imageset": ["car", "watch", "vision", "ios-marketing"], "symbolset": ["ios-marketing"],
    ]

    /// The extensions (case-sensitive) of files no entry names that actool warns about; it
    /// ignores the others (a `README.md`, `.gif`, `.PNG`).
    static let unassignedExtensions: [String: Set<String>] = [
        "colorset": [], "imageset": ["png", "jpg", "jpeg", "pdf", "svg", "heic"], "symbolset": ["svg"],
    ]

    /// The idioms of the entries with something for the build, or nil when there are none.
    static func contentIdioms(_ folder: String, type: String, targetDevices: [String]) throws -> Set<String>? {
        func warned(_ what: String) -> NomacError {
            NomacError("asset symbols for sets actool warns about (\(what)) are not supported yet (BACKLOG B-204)", path: folder)
        }
        guard FileManager.default.fileExists(atPath: folder + "/Contents.json") else { return nil }
        let contents = try AssetCatalog.readContents(folder, required: true)
        let entries = contents[["colorset": "colors", "imageset": "images", "symbolset": "symbols"][type]!] as? [[String: Any]] ?? []
        let files = entries.compactMap { $0["filename"] as? String }
        let present = try FileSystem.sortedContents(of: folder).filter { !$0.hasPrefix(".") && $0 != "Contents.json" }
        if let missing = files.first(where: { !present.contains($0) }) { throw warned("a missing file, \(missing)") }
        if let extra = present.first(where: { !files.contains($0) && unassignedExtensions[type]!.contains(($0 as NSString).pathExtension) }) {
            throw warned("a file no entry names, \(extra)")
        }
        if type == "symbolset", let file = files.first(where: { ($0 as NSString).pathExtension != "svg" }) { throw warned("a symbol file \(file)") }
        // A watch catalog's watch entries are its own (`complications` symbols cases).
        if let entry = entries.first(where: { unassignedIdioms[type]!.subtracting(targetDevices).contains($0["idiom"] as? String ?? "universal") }) {
            throw warned("an entry for \(entry["idiom"] as? String ?? "")")
        }
        var idioms = Set(["universal"] + targetDevices)
        if type != "imageset" && targetDevices.contains("iphone") { idioms.insert("car") }
        let content = Set(entries.compactMap { entry -> String? in
            let idiom = entry["idiom"] as? String ?? "universal"
            return idioms.contains(idiom) && (type == "colorset" ? entry["color"] != nil : entry["filename"] != nil) ? idiom : nil
        })
        return content.isEmpty ? nil : content
    }

    private static func scan(folder: String, relativePath: String, namespaces: [String], catalog: String, targetDevices: [String],
                             complication: String?, into assets: inout [Asset]) throws {
        for entry in try AssetCatalog.subfolders(of: folder) {
            let path = folder + "/" + entry
            let relative = relativePath + "/" + entry
            let base = (entry as NSString).deletingPathExtension
            switch AssetCatalog.assetType(of: entry) {
            case nil, "spriteatlas":
                let name = AssetCatalog.assetType(of: entry) == nil ? entry : base
                let inner = try AssetCatalog.providesNamespace(path) ? namespaces + [name] : namespaces
                try scan(folder: path, relativePath: relative, namespaces: inner, catalog: catalog, targetDevices: targetDevices, complication: complication,
                         into: &assets)
            case "complicationset":
                // The complication set `--complication` names, as a namespace; the others are left out.
                guard (namespaces + [base]).joined(separator: "/") == complication else { continue }
                _ = try ComplicationSet.roles(path, contents: AssetCatalog.readContents(path, required: true))
                try scan(folder: path, relativePath: relative, namespaces: namespaces + [base], catalog: catalog, targetDevices: targetDevices,
                         complication: complication, into: &assets)
            case let type? where ["colorset", "imageset", "symbolset"].contains(type):
                guard let idioms = try contentIdioms(path, type: type, targetDevices: targetDevices) else { continue }
                let isThinnable = !idioms.contains("universal") && !Set(targetDevices).isSubset(of: idioms)
                assets.append(Asset(kind: type == "colorset" ? .color : .image, isSymbolSet: type == "symbolset", isThinnable: isThinnable,
                                    namespaces: namespaces, name: base, catalog: catalog, relativePath: relative))
            case "dataset", "appiconset", "launchimage":
                continue
            case "solidimagestack":
                try SolidImageStack.check(path)
            case let type?:
                throw NomacError("asset symbols for '.\(type)' sets are not supported yet (BACKLOG B-204)", path: path)
            }
        }
    }

    // MARK: Order and names

    /// The Swift file sorts each level by the code points of the names' canonical composition,
    /// the header and the index by those of their canonical decomposition, whichever form the
    /// folder names have on disk. Sets of one kind that share a last path component come out of
    /// actool in an order that changes from run to run; nomac orders them by full name.
    static func codePointsPrecede(_ a: String, _ b: String) -> Bool {
        a.unicodeScalars.map(\.value).lexicographicallyPrecedes(b.unicodeScalars.map(\.value))
    }

    static func composedPrecede(_ a: String, _ b: String) -> Bool {
        codePointsPrecede(a.precomposedStringWithCanonicalMapping, b.precomposedStringWithCanonicalMapping)
    }

    static func decomposedPrecede(_ a: String, _ b: String) -> Bool {
        codePointsPrecede(a.decomposedStringWithCanonicalMapping, b.decomposedStringWithCanonicalMapping)
    }

    func listed(_ kind: Kind) -> [Asset] {
        assets.filter { $0.kind == kind }.sorted { a, b in
            a.name != b.name ? Self.decomposedPrecede(a.name, b.name) : Self.decomposedPrecede(a.fullName, b.fullName)
        }
    }

    static func objectiveCPrefix(_ kind: Kind) -> String {
        kind == .color ? "ACColorName" : "ACImageName"
    }

    // MARK: The Swift tree

    indirect enum Node {
        case member(Asset, symbol: String, path: String)
        case namespace(name: String, symbol: String, children: [Node])
        case assetWarning(String)
        case namespaceWarning(String)
    }

    private struct Level {
        var assets: [String: Asset] = [:]
        var namespaces: [String: Level] = [:]

        /// A symbol set named like an image set is that image in the Swift file.
        mutating func insert(_ asset: Asset, at depth: Int) throws {
            if depth == asset.namespaces.count {
                if let existing = assets[asset.name], existing.isSymbolSet != asset.isSymbolSet {
                    if existing.isSymbolSet { assets[asset.name] = asset }
                    return
                }
                guard assets[asset.name] == nil else {
                    let what = "\(asset.kind.rawValue) '\(asset.fullName)', which more than one catalog has"
                    throw NomacError("asset symbols for \(what), are not supported yet (BACKLOG B-204)")
                }
                assets[asset.name] = asset
            } else {
                try namespaces[asset.namespaces[depth], default: Level()].insert(asset, at: depth + 1)
            }
        }
    }

    func tree(_ kind: Kind, extendedOnly: Bool = false) throws -> [Node] {
        var root = Level()
        for asset in assets where asset.kind == kind && (!extendedOnly || hasExtensions(asset)) {
            try root.insert(asset, at: 0)
        }
        return Self.nodes(root, kind: kind, path: [], symbols: [])
    }

    /// A set named like a namespace folder beside it is left out of the Swift file.
    private static func nodes(_ level: Level, kind: Kind, path: [String], symbols: [String]) -> [Node] {
        let names = (Array(level.namespaces.keys) + level.assets.keys.filter { level.namespaces[$0] == nil })
        var taken: Set<String> = []
        var nodes: [Node] = []
        for name in names.sorted(by: composedPrecede) {
            if let namespace = level.namespaces[name] {
                let fullName = (path + [name]).joined(separator: "/")
                let symbol = AssetSymbolName.namespace(name)
                let what = "The \"\(fullName)\" namespace resolves to"
                if symbol.isEmpty {
                    nodes.append(.namespaceWarning("\(what) an empty symbol. Try renaming the namespace."))
                } else if !taken.insert(symbol).inserted {
                    nodes.append(.namespaceWarning("\(what) the symbol \"\(symbol)\" which already exists. Try renaming the namespace."))
                } else {
                    let children = Self.nodes(namespace, kind: kind, path: path + [name], symbols: symbols + [symbol])
                    nodes.append(.namespace(name: fullName, symbol: symbol, children: children))
                }
            } else if let asset = level.assets[name] {
                let symbol = AssetSymbolName.member(name)
                let what = "The \"\(asset.fullName)\" \(kind.rawValue) asset name resolves to"
                if symbol.isEmpty {
                    nodes.append(.assetWarning("\(what) an empty symbol. Try renaming the asset."))
                } else if !taken.insert(symbol).inserted {
                    nodes.append(.assetWarning("\(what) the symbol \"\(symbol)\" which already exists. Try renaming the asset."))
                } else {
                    nodes.append(.member(asset, symbol: symbol, path: (symbols + [symbol]).joined(separator: ".")))
                }
            }
        }
        return nodes
    }

    // MARK: Writing

    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "'", with: "\\'")
    }

    func index() -> [UInt8] {
        func entries(_ kind: Kind, symbolSets: Bool = false) -> PropertyListValue {
            .array(listed(kind).filter { $0.isSymbolSet == symbolSets }.compactMap { asset in
                let swift = AssetSymbolName.member(asset.name)
                guard !swift.isEmpty else { return nil }
                var entry: [String: PropertyListValue] = [
                    "catalogPath": .string(asset.catalog), "relativePath": .string(asset.relativePath), "swiftSymbol": .string(swift),
                ]
                let objectiveC = AssetSymbolName.objectiveC(asset.name)
                if !objectiveC.isEmpty { entry["objcSymbol"] = .string(Self.objectiveCPrefix(kind) + objectiveC) }
                return .dictionary(entry)
            })
        }
        let lists = ["colors": entries(.color), "images": entries(.image), "symbols": entries(.image, symbolSets: true)]
        return [UInt8](XMLPropertyList.data(.dictionary(lists)))
    }

    func objectiveCHeader() throws -> String {
        var text = """
            #import <Foundation/Foundation.h>

            #if __has_attribute(swift_private)
            #define AC_SWIFT_PRIVATE __attribute__((swift_private))
            #else
            #define AC_SWIFT_PRIVATE
            #endif


            """
        let colors = listed(.color)
        if !colors.isEmpty {
            guard let bundle = options.bundleIdentifier else {
                throw NomacError("actool: asset symbols for colors need --bundle-identifier")
            }
            text += "/// The resource bundle ID.\nstatic NSString * const ACBundleID AC_SWIFT_PRIVATE = @\"\(Self.escaped(bundle))\";\n\n"
        }
        let images = listed(.image)
        for (kind, assets) in [(Kind.color, colors), (.image, images.filter { !$0.isSymbolSet } + images.filter(\.isSymbolSet))] {
            var taken: Set<String> = []
            for asset in assets {
                let name = asset.fullName
                let symbol = AssetSymbolName.objectiveC(name)
                let what = "#warning The \"\(name)\" \(kind.rawValue) asset name resolves to"
                if symbol.isEmpty {
                    text += "\(what) an empty symbol. Try renaming the asset.\n\n"
                } else if !taken.insert(symbol).inserted {
                    text += "\(what) the symbol \"\(Self.objectiveCPrefix(kind) + symbol)\" which already exists. Try renaming the asset.\n\n"
                } else {
                    text += "/// The \"\(Self.escaped(name))\" asset catalog \(kind.rawValue) resource.\n"
                    text += "static NSString * const \(Self.objectiveCPrefix(kind) + symbol) AC_SWIFT_PRIVATE = @\"\(Self.escaped(name))\";\n\n"
                }
            }
        }
        return text + "#undef AC_SWIFT_PRIVATE\n"
    }

    private struct Availability {
        var colorResource, imageResource, appKitColor, appKitImage, uiKit, swiftUI: String
        var colorType, imageType: String

        init(backDeployment: Bool) {
            if backDeployment {
                colorResource = "@available(iOS 11.0, macOS 10.13, tvOS 11.0, *)"
                imageResource = "@available(iOS 11.0, macOS 10.7, tvOS 11.0, *)"
                appKitColor = "@available(macOS 10.13, *)"
                appKitImage = "@available(macOS 10.7, *)"
                uiKit = "@available(iOS 11.0, tvOS 11.0, *)"
                swiftUI = "@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)"
                colorType = "ColorResource"
                imageType = "ImageResource"
            } else {
                colorResource = "@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)"
                imageResource = colorResource
                swiftUI = colorResource
                appKitColor = "@available(macOS 14.0, *)"
                appKitImage = appKitColor
                uiKit = "@available(iOS 17.0, tvOS 17.0, *)"
                colorType = "DeveloperToolsSupport.ColorResource"
                imageType = "DeveloperToolsSupport.ImageResource"
            }
        }
    }

    /// An AppKit or UIKit type the extensions add members to, unavailable on Mac Catalyst or watchOS.
    private struct Platform {
        var module: String
        var type: String

        static let nsColor = Platform(module: "AppKit", type: "NSColor")
        static let uiColor = Platform(module: "UIKit", type: "UIColor")
        static let nsImage = Platform(module: "AppKit", type: "NSImage")
        static let uiImage = Platform(module: "UIKit", type: "UIImage")

        var unavailable: String { module == "AppKit" ? "macCatalyst" : "watchOS" }
        var condition: String { module == "AppKit" ? "!targetEnvironment(macCatalyst)" : "!os(watchOS)" }

        func extensionHeader(_ availability: String) -> String {
            "#if canImport(\(module))\n\(availability)\n@available(\(unavailable), unavailable)\nextension \(module).\(type) {\n\n"
        }
    }

    /// How one section writes a member.
    private enum Section {
        case resource(String)
        case platform(Platform)
        case swiftUI, shapeStyle

        var conflicts: (framework: String, names: Set<String>)? {
            switch self {
            case .resource: return nil
            case .platform(let platform): return (platform.type, AssetSymbolName.conflicts[platform.type] ?? [])
            case .swiftUI, .shapeStyle: return ("Color", AssetSymbolName.conflicts["Color"] ?? [])
            }
        }

        var isResource: Bool {
            if case .resource = self { return true }
            return false
        }

        var isShapeStyle: Bool {
            if case .shapeStyle = self { return true }
            return false
        }
    }

    /// Extension sections leave out the sets the resource section warns about; the
    /// `ShapeStyle` extension also leaves out namespaces and conflicting members.
    private static func render(_ nodes: [Node], kind: Kind, as section: Section, depth: Int) -> String {
        let indent = String(repeating: "    ", count: depth + 1)
        var text = ""
        for node in nodes {
            switch node {
            case .assetWarning(let message):
                if section.isResource { text += "\(indent)#warning(\"\(escaped(message))\")\n\n" }
            case .namespaceWarning(let message):
                if !section.isShapeStyle { text += "\(indent)#warning(\"\(escaped(message))\")\n\n" }
            case .namespace(let name, let symbol, let children):
                guard !section.isShapeStyle else { continue }
                text += "\(indent)/// The \"\(escaped(name))\" asset catalog resource namespace.\n\(indent)enum \(symbol) {\n\n"
                text += render(children, kind: kind, as: section, depth: depth + 1)
                text += "\(indent)}\n\n"
            case .member(let asset, let symbol, let path):
                let name = escaped(asset.fullName)
                if depth == 0, let conflicts = section.conflicts, conflicts.names.contains(symbol) {
                    guard !section.isShapeStyle else { continue }
                    let what = "The \"\(asset.fullName)\" \(kind.rawValue) asset name resolves to"
                    let message = "\(what) a conflicting \(conflicts.framework) symbol \"\(symbol)\". Try renaming the asset."
                    text += "\(indent)#warning(\"\(escaped(message))\")\n\n"
                    continue
                }
                let unavailable = asset.isThinnable ? "\(indent)@available(watchOS, unavailable)\n" : ""
                let optional = asset.isThinnable ? "?" : ""
                switch section {
                case .resource(let type):
                    text += "\(indent)/// The \"\(name)\" asset catalog \(kind.rawValue) resource.\n" + unavailable
                    text += "\(indent)static let \(symbol) = \(type)(\(asset.isThinnable ? "thinnableName" : "name"): \"\(name)\", bundle: resourceBundle)\n\n"
                case .platform(let platform):
                    text += "\(indent)/// The \"\(name)\" asset catalog \(kind.rawValue).\n"
                    text += "\(indent)static var \(symbol): \(platform.module).\(platform.type)\(optional) {\n#if \(platform.condition)\n"
                    text += "\(indent)    .init(\(asset.isThinnable ? "thinnableResource" : "resource"): .\(path))\n#else\n\(indent)    .init()\n#endif\n\(indent)}\n\n"
                case .swiftUI, .shapeStyle:
                    text += "\(indent)/// The \"\(name)\" asset catalog color.\n" + unavailable
                    text += "\(indent)static var \(symbol): SwiftUI.Color\(optional) { .init(\(asset.isThinnable ? "thinnableResource: " : "").\(path)) }\n\n"
                }
            }
        }
        return text
    }

    func hasExtensions(_ asset: Asset) -> Bool { asset.catalogExtensions ?? options.extensions }

    /// The extensions of a kind are written with the option, or for the assets whose catalog
    /// enables them; they list the assets that have them (`symbol-extensions`).
    func swiftSource() throws -> String {
        let a = Availability(backDeployment: options.backDeployment)
        let colors = try tree(.color), images = try tree(.image)
        let extendedColors = try tree(.color, extendedOnly: true), extendedImages = try tree(.image, extendedOnly: true)
        let colorExtensions = options.extensions || assets.contains { $0.kind == .color && hasExtensions($0) }
        let imageExtensions = options.extensions || assets.contains { $0.kind == .image && hasExtensions($0) }
        var text = "import Foundation\n"
        if options.backDeployment || colorExtensions || imageExtensions {
            text += "#if canImport(AppKit)\nimport AppKit\n#endif\n#if canImport(UIKit)\nimport UIKit\n#endif\n#if canImport(SwiftUI)\nimport SwiftUI\n#endif\n"
        }
        text += """
            #if canImport(DeveloperToolsSupport)
            import DeveloperToolsSupport
            #endif

            #if SWIFT_PACKAGE
            private let resourceBundle = Foundation.Bundle.module
            #else
            private class ResourceBundleClass {}
            private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
            #endif


            """
        text += "// MARK: - Color Symbols -\n\n\(a.colorResource)\nextension \(a.colorType) {\n\n"
        text += Self.render(colors, kind: .color, as: .resource(a.colorType), depth: 0) + "}\n\n"
        text += "// MARK: - Image Symbols -\n\n\(a.imageResource)\nextension \(a.imageType) {\n\n"
        text += Self.render(images, kind: .image, as: .resource(a.imageType), depth: 0) + "}\n\n"
        if colorExtensions {
            text += "// MARK: - Color Symbol Extensions -\n\n"
            text += Platform.nsColor.extensionHeader(a.appKitColor)
            text += Self.render(extendedColors, kind: .color, as: .platform(.nsColor), depth: 0) + "}\n#endif\n\n"
            text += Platform.uiColor.extensionHeader(a.uiKit)
            text += Self.render(extendedColors, kind: .color, as: .platform(.uiColor), depth: 0) + "}\n#endif\n\n"
            text += "#if canImport(SwiftUI)\n\(a.swiftUI)\nextension SwiftUI.Color {\n\n"
            text += Self.render(extendedColors, kind: .color, as: .swiftUI, depth: 0) + "}\n\n"
            text += "\(a.swiftUI)\nextension SwiftUI.ShapeStyle where Self == SwiftUI.Color {\n\n"
            text += Self.render(extendedColors, kind: .color, as: .shapeStyle, depth: 0) + "}\n#endif\n\n"
        }
        if imageExtensions {
            text += "// MARK: - Image Symbol Extensions -\n\n"
            text += Platform.nsImage.extensionHeader(a.appKitImage)
            text += Self.render(extendedImages, kind: .image, as: .platform(.nsImage), depth: 0) + "}\n#endif\n\n"
            text += Platform.uiImage.extensionHeader(a.uiKit)
            text += Self.render(extendedImages, kind: .image, as: .platform(.uiImage), depth: 0) + "}\n#endif\n\n"
        }
        if colorExtensions || imageExtensions {
            text += Self.thinnableSupport(a, colors: assets.contains { $0.kind == .color }, images: assets.contains { $0.kind == .image })
        }
        if options.backDeployment {
            text += Self.backDeploymentSupport
        }
        return text
    }

    /// The AppKit initializers are written only for the kinds the catalogs have.
    private static func thinnableSupport(_ a: Availability, colors: Bool, images: Bool) -> String {
        var text = """
            // MARK: - Thinnable Asset Support -

            \(a.colorResource)
            @available(watchOS, unavailable)
            extension \(a.colorType) {

                private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
            #if canImport(AppKit) && os(macOS)
                    if AppKit.NSColor(named: NSColor.Name(thinnableName), bundle: bundle) != nil {
                        self.init(name: thinnableName, bundle: bundle)
                    } else {
                        return nil
                    }
            #elseif canImport(UIKit) && !os(watchOS)
                    if UIKit.UIColor(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
                        self.init(name: thinnableName, bundle: bundle)
                    } else {
                        return nil
                    }
            #else
                    return nil
            #endif
                }

            }


            """
        if colors {
            text += thinnableInitializer(.nsColor, availability: a.appKitColor, resource: a.colorType)
        }
        text += thinnableInitializer(.uiColor, availability: a.uiKit, resource: a.colorType)
        text += """
            #if canImport(SwiftUI)
            \(a.swiftUI)
            extension SwiftUI.Color {

                private init?(thinnableResource: \(a.colorType)?) {
                    if let resource = thinnableResource {
                        self.init(resource)
                    } else {
                        return nil
                    }
                }

            }

            \(a.swiftUI)
            extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

                private init?(thinnableResource: \(a.colorType)?) {
                    if let resource = thinnableResource {
                        self.init(resource)
                    } else {
                        return nil
                    }
                }

            }
            #endif

            \(a.imageResource)
            @available(watchOS, unavailable)
            extension \(a.imageType) {

                private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
            #if canImport(AppKit) && os(macOS)
                    if bundle.image(forResource: NSImage.Name(thinnableName)) != nil {
                        self.init(name: thinnableName, bundle: bundle)
                    } else {
                        return nil
                    }
            #elseif canImport(UIKit) && !os(watchOS)
                    if UIKit.UIImage(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
                        self.init(name: thinnableName, bundle: bundle)
                    } else {
                        return nil
                    }
            #else
                    return nil
            #endif
                }

            }


            """
        if images {
            text += thinnableInitializer(.nsImage, availability: a.appKitImage, resource: a.imageType)
        }
        text += thinnableInitializer(.uiImage, availability: a.uiKit, resource: a.imageType)
        return text
    }

    private static func thinnableInitializer(_ platform: Platform, availability: String, resource: String) -> String {
        platform.extensionHeader(availability) + """
            private convenience init?(thinnableResource: \(resource)?) {
        #if \(platform.condition)
                if let resource = thinnableResource {
                    self.init(resource: resource)
                } else {
                    return nil
                }
        #else
                return nil
        #endif
            }

        }
        #endif


        """
    }

    /// The same text whatever the catalogs hold, and without a final line break.
    static let backDeploymentSupport = """
        // MARK: - Backwards Deployment Support -

        /// A color resource.
        struct ColorResource: Swift.Hashable, Swift.Sendable {

            /// An asset catalog color resource name.
            fileprivate let name: Swift.String

            /// An asset catalog color resource bundle.
            fileprivate let bundle: Foundation.Bundle

            /// Initialize a `ColorResource` with `name` and `bundle`.
            init(name: Swift.String, bundle: Foundation.Bundle) {
                self.name = name
                self.bundle = bundle
            }

        }

        /// An image resource.
        struct ImageResource: Swift.Hashable, Swift.Sendable {

            /// An asset catalog image resource name.
            fileprivate let name: Swift.String

            /// An asset catalog image resource bundle.
            fileprivate let bundle: Foundation.Bundle

            /// Initialize an `ImageResource` with `name` and `bundle`.
            init(name: Swift.String, bundle: Foundation.Bundle) {
                self.name = name
                self.bundle = bundle
            }

        }

        #if canImport(AppKit)
        @available(macOS 10.13, *)
        @available(macCatalyst, unavailable)
        extension AppKit.NSColor {

            /// Initialize a `NSColor` with a color resource.
            convenience init(resource: ColorResource) {
                self.init(named: NSColor.Name(resource.name), bundle: resource.bundle)!
            }

        }

        protocol _ACResourceInitProtocol {}
        extension AppKit.NSImage: _ACResourceInitProtocol {}

        @available(macOS 10.7, *)
        @available(macCatalyst, unavailable)
        extension _ACResourceInitProtocol {

            /// Initialize a `NSImage` with an image resource.
            init(resource: ImageResource) {
                self = resource.bundle.image(forResource: NSImage.Name(resource.name))! as! Self
            }

        }
        #endif

        #if canImport(UIKit)
        @available(iOS 11.0, tvOS 11.0, *)
        @available(watchOS, unavailable)
        extension UIKit.UIColor {

            /// Initialize a `UIColor` with a color resource.
            convenience init(resource: ColorResource) {
        #if !os(watchOS)
                self.init(named: resource.name, in: resource.bundle, compatibleWith: nil)!
        #else
                self.init()
        #endif
            }

        }

        @available(iOS 11.0, tvOS 11.0, *)
        @available(watchOS, unavailable)
        extension UIKit.UIImage {

            /// Initialize a `UIImage` with an image resource.
            convenience init(resource: ImageResource) {
        #if !os(watchOS)
                self.init(named: resource.name, in: resource.bundle, compatibleWith: nil)!
        #else
                self.init()
        #endif
            }

        }
        #endif

        #if canImport(SwiftUI)
        @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
        extension SwiftUI.Color {

            /// Initialize a `Color` with a color resource.
            init(_ resource: ColorResource) {
                self.init(resource.name, bundle: resource.bundle)
            }

        }

        @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
        extension SwiftUI.Image {

            /// Initialize an `Image` with an image resource.
            init(_ resource: ImageResource) {
                self.init(resource.name, bundle: resource.bundle)
            }

        }
        #endif
        """
}
