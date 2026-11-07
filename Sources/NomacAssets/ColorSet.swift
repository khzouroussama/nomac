import Foundation
import NomacCore

/// Compiles `.colorset` assets into color renditions (docs/formats/asset-catalog.md,
/// "Colors"), as observed in the `colors` experiments of
/// `.github/scripts/assets_experiments.py`.
enum ColorSet {
    /// Color spaces and the number `COLR` stores for each.
    static let colorSpaces: [String: UInt32] = [
        "srgb": 1, "gray-gamma-22": 2, "display-p3": 3, "extended-srgb": 4, "extended-linear-srgb": 5, "extended-gray": 6,
    ]

    static let displayGamuts: [String: UInt16] = ["sRGB": 0, "display-P3": 1]

    /// watchOS keeps only the colors for any appearance (`image-appearances` watch cases).
    static func renditions(_ asset: AssetCatalog.Asset, idioms: [String: UInt16], watch: Bool) throws -> [CARRendition] {
        guard let colors = asset.contents["colors"] as? [[String: Any]] else { return [] }
        var renditions: [CARRendition] = []
        for entry in colors {
            guard let color = entry["color"] as? [String: Any] else { continue }
            let idiomName = entry["idiom"] as? String ?? "universal"
            guard let idiom = idioms[idiomName] else {
                guard Idiom.ignoredOnIOS.contains(idiomName) || Idiom.devices.contains(idiomName) else {
                    throw NomacError("color idiom '\(idiomName)' is not supported yet (BACKLOG B-203)", path: asset.path)
                }
                continue
            }
            let appearance = try appearance(entry["appearances"] as? [[String: Any]] ?? [], asset: asset)
            if watch && appearance != .any { continue }
            var attributes: [RenditionAttribute: UInt16] = [.scale: 1, .idiom: idiom, .appearance: appearance.rawValue]
            if let gamut = entry["display-gamut"] as? String {
                guard let value = displayGamuts[gamut] else {
                    throw NomacError("display gamut '\(gamut)' is not supported yet (BACKLOG B-203)", path: asset.path)
                }
                attributes[.displayGamut] = value
            }
            let csi = CSI(
                name: asset.name, layout: .color,
                properties: [(1004, [UInt8](repeating: 0, count: 8)), (1006, [1, 0, 0, 0])],
                payload: try payload(color, appearance: appearance, asset: asset))
            renditions.append(CARRendition(name: asset.name, kind: .color, attributes: attributes, csi: csi.bytes))
        }
        return renditions
    }

    static func appearance(_ appearances: [[String: Any]], asset: AssetCatalog.Asset) throws -> RenditionAppearance {
        guard let appearance = RenditionAppearance(entry: appearances) else {
            let pairs = appearances.map { ($0["appearance"] as? String ?? "", $0["value"] as? String ?? "") }
            throw NomacError("color appearances \(pairs) are not supported yet (BACKLOG B-203)", path: asset.path)
        }
        return appearance
    }

    /// The `COLR` payload: tag, version 1, the color space, the component count and each
    /// component as a double; for a system color, the color space has 0x100 and a second `COLR`
    /// block follows with the name's length and the name.
    static func payload(_ color: [String: Any], appearance: RenditionAppearance, asset: AssetCatalog.Asset) throws -> [UInt8] {
        if let reference = color["reference"] as? String {
            return try systemColor(reference, platform: color["platform"] as? String, appearance: appearance, asset: asset)
        }
        guard let spaceName = color["color-space"] as? String, let space = colorSpaces[spaceName],
              let components = color["components"] as? [String: Any] else {
            throw NomacError("colors without a supported color space are not supported yet (BACKLOG B-203)", path: asset.path)
        }
        let names = space == 2 || space == 6 ? ["white", "alpha"] : ["red", "green", "blue", "alpha"]
        var out = ByteWriter()
        out.append(Array("RLOC".utf8))
        out.appendLE(UInt32(1))
        out.appendLE(space)
        out.appendLE(UInt32(names.count))
        for name in names {
            out.appendLE(try component(components[name], name: name, asset: asset))
        }
        return out.bytes
    }

    /// The platforms a reference may name, none meaning macOS: all give the iOS values, with the
    /// same names warned about on all but `ios` (`colors`, system-color-platforms).
    static let systemColorPlatforms: Set<String?> = ["ios", "universal", "osx", "tvos", "watchos", "xros", "visionos", nil]

    /// References for any platform, light or dark; actool's document warnings for unknown names
    /// and iOS-only names referenced for other platforms, whose order changes from run to run,
    /// and the values of other appearances are not reproduced (BACKLOG B-203).
    static func systemColor(_ name: String, platform: String?, appearance: RenditionAppearance, asset: AssetCatalog.Asset) throws -> [UInt8] {
        guard systemColorPlatforms.contains(platform), let entry = SystemColors.values[name], platform == "ios" || entry.universal,
              appearance == .any || appearance == .dark else {
            throw NomacError("the system color \(name) for platform \(platform ?? "(none)") is not supported yet (BACKLOG B-203)", path: asset.path)
        }
        let value = appearance == .dark ? entry.dark : entry.light
        var out = ByteWriter()
        out.append(Array("RLOC".utf8))
        out.appendLE(UInt32(1))
        out.appendLE(value.space | 0x100)
        out.appendLE(UInt32(value.components.count))
        for component in value.components {
            out.appendLE(Double(Float(bitPattern: component)))
        }
        out.append(Array("RLOC".utf8))
        out.appendLE(UInt32(1))
        out.appendLE(UInt32(name.utf8.count))
        out.append(Array(name.utf8))
        return out.bytes
    }

    /// A component as actool reads it: a decimal number as a 32-bit float, one or two `0x`
    /// hexadecimal digits or an integer as a fraction of 255.
    static func component(_ value: Any?, name: String, asset: AssetCatalog.Asset) throws -> Double {
        let text: String
        switch value {
        case let string as String: text = string
        case let number as NSNumber: text = number.stringValue
        default: throw NomacError("color component '\(name)' is missing", path: asset.path)
        }
        if text.contains(".") {
            return Double(Float(text.trimmingCharacters(in: .whitespaces)) ?? 0)
        }
        if text.hasPrefix("0x") || text.hasPrefix("0X") {
            let digits = text.dropFirst(2)
            guard digits.count <= 2, let value = Int(digits, radix: 16) else {
                throw NomacError("color component '\(text)' is not supported yet (BACKLOG B-203)", path: asset.path)
            }
            // One digit stands for itself twice: 0x1 is 0x11.
            return Double(digits.count == 1 ? value * 17 : value) / 255
        }
        return Double(integerPrefix(text)) / 255
    }

    static func integerPrefix(_ text: String) -> Int {
        var digits = Substring(text.drop(while: { $0 == " " }))
        let negative = digits.first == "-"
        if negative || digits.first == "+" { digits = digits.dropFirst() }
        let value = Int(digits.prefix(while: \.isASCII).prefix(while: \.isNumber)) ?? 0
        return negative ? -value : value
    }
}

/// Idioms as rendition keys number them.
enum Idiom {
    static let universal: UInt16 = 0
    static let phone: UInt16 = 1
    static let pad: UInt16 = 2
    static let car: UInt16 = 4
    static let watch: UInt16 = 5
    /// App icon sets' `ios-marketing` entries.
    static let marketing: UInt16 = 6

    /// Idioms of other platforms that actool leaves out of an iOS catalog.
    static let ignoredOnIOS: Set<String> = ["mac", "tv", "watch"]

    /// Device idioms, left out unless `--target-device` names them; `car` goes with iPhone
    /// (`images` and `colors`, car-entries).
    static let devices: Set<String> = ["iphone", "ipad", "car"]

    /// The idioms an iOS catalog keeps for `--target-device` values.
    static func iOS(targetDevices: [String]) -> [String: UInt16] {
        var idioms = ["universal": universal]
        if targetDevices.contains("iphone") {
            idioms["iphone"] = phone
            idioms["car"] = car
        }
        if targetDevices.contains("ipad") { idioms["ipad"] = pad }
        return idioms
    }
}
