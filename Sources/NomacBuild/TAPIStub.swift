import Foundation
import NomacCore

/// `tapi stubify` for a thin arm64 iOS dynamic library, as Xcode 27.0's `tapi` (Apple TAPI
/// 21.0.0, tapi-2100.3.8.1) writes it (docs/formats/tbd.md). Every rule comes from
/// `.github/scripts/tapi_experiments.py` and retro-rampage's `Engine`; inputs no experiment has
/// covered stop with an error (B-106).
enum TAPIStub {
    static func stubify(_ dylib: MachODylib, path: String) throws -> String {
        guard dylib.cpuType == 0x0100_000c, dylib.cpuSubtype & 0x00ff_ffff == 0 else {
            throw NomacError("nomac's tapi stubify writes arm64 libraries only (B-106)", path: path)
        }
        guard dylib.platform == MachOBuildVersion.platformIOS else {
            throw NomacError("nomac's tapi stubify writes iOS libraries only (B-106)", path: path)
        }
        var categories: [String: [String: [String]]] = [:]
        for export in dylib.exports {
            let (category, kind, name) = try classify(export, in: dylib, path: path)
            guard let category else { continue }
            categories[category, default: [:]][kind, default: []].append(name)
        }
        var library: [(String, String)] = []
        if dylib.compatibilityVersion != 0x10000 {
            library.append(("compatibility_versions", "[{\"version\":\(quote(version(dylib.compatibilityVersion)))}]"))
        }
        if dylib.currentVersion != 0x10000 {
            library.append(("current_versions", "[{\"version\":\(quote(version(dylib.currentVersion)))}]"))
        }
        let symbols = categories.keys.sorted().map { category in
            let kinds = categories[category]!.keys.sorted().map { kind in
                let names = categories[category]![kind]!.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
                return quote(kind) + ":[" + names.map(quote).joined(separator: ",") + "]"
            }
            return quote(category) + ":{" + kinds.joined(separator: ",") + "}"
        }
        // A library that exports nothing has no `exported_symbols` (`no-exports`).
        if !symbols.isEmpty {
            library.append(("exported_symbols", "[{" + symbols.joined(separator: ",") + "}]"))
        }
        if dylib.flags & MachODylib.appExtensionSafeFlag == 0 {
            library.append(("flags", "[{\"attributes\":[\"not_app_extension_safe\"]}]"))
        }
        library.append(("install_names", "[{\"name\":\(quote(dylib.installName))}]"))
        if let swift = dylib.swiftABIVersion {
            library.append(("swift_abi", "[{\"abi\":\(swift)}]"))
        }
        library.append(("target_info", "[{\"min_deployment\":\(quote(version(dylib.minimumOS))),\"target\":\"arm64-ios\"}]"))
        let body = library.map { quote($0.0) + ":" + $0.1 }.joined(separator: ",")
        return "{\"main_library\":{" + body + "},\"tapi_tbd_version\":5}\n"
    }

    private static func classify(_ export: MachODylib.Export, in dylib: MachODylib, path: String) throws -> (String?, String, String) {
        let classPrefix = "_OBJC_CLASS_$_"
        if export.name.hasPrefix(classPrefix) {
            return ("data", "objc_class", String(export.name.dropFirst(classPrefix.count)))
        }
        if export.name.hasPrefix("_OBJC_METACLASS_$_") {
            return (nil, "", "")
        }
        // An exported instance variable (`@public` and `@protected`; the others are private
        // externs) and an exception type (`tapi_experiments.py` objc-ivars, objc-exception-type).
        let ivarPrefix = "_OBJC_IVAR_$_", exceptionPrefix = "_OBJC_EHTYPE_$_"
        if export.name.hasPrefix(ivarPrefix) {
            return ("data", "objc_ivar", String(export.name.dropFirst(ivarPrefix.count)))
        }
        if export.name.hasPrefix(exceptionPrefix) {
            return ("data", "objc_eh_type", String(export.name.dropFirst(exceptionPrefix.count)))
        }
        if export.kind == .threadLocal {
            guard !export.isWeak else {
                throw NomacError("'\(export.name)' is a weak thread-local symbol, which nomac's tapi stubify has not observed (B-106)", path: path)
            }
            return ("data", "thread_local", export.name)
        }
        let isText = (dylib.section(containing: export.address)?.hasInstructions ?? false) && !export.name.hasPrefix("_$s")
        return (isText ? "text" : "data", export.isWeak ? "weak" : "global", export.name)
    }

    /// A packed `xxxx.yy.zz` version without its trailing zero components.
    static func version(_ packed: UInt32) -> String {
        let components = [packed >> 16, (packed >> 8) & 0xff, packed & 0xff]
        var shown = components
        while shown.count > 1, shown.last == 0 { shown.removeLast() }
        return shown.map(String.init).joined(separator: ".")
    }

    private static func quote(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\t": result += "\\t"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04x", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result + "\""
    }
}
