import Foundation
import NomacCore

/// The `Contents/Info.plist` dsymutil writes into a dSYM.
///
/// LLVM's dsymutil reads the bundle of the binary (its identifier and versions) with Core
/// Foundation, which it only does on Apple platforms (`tools/dsymutil/CFBundle.cpp`); elsewhere
/// it writes its defaults. On retro-rampage's `Engine`, LLVM 21.1.6's dsymutil on Linux wrote
/// Xcode's DWARF and relocations byte for byte, and this file with `com.apple.xcode.dsym.Engine.framework`
/// where Xcode's has the framework's `com.charcoaldesign.Engine`. nomac finds the bundle as
/// dsymutil does on macOS and writes dsymutil's template with its values.
public enum DSYMInfoPlist {
    struct BundleInfo: Equatable {
        var identifier: String?
        var version = "1"
        var shortVersion = "1.0"
    }

    /// The bundle dsymutil finds for `executable`: the nearest directory, from the executable's
    /// real path up to the root, whose Info.plist has a `CFBundleIdentifier`.
    static func bundleInfo(executable: String) -> BundleInfo {
        var directory = FileSystem.resolvingSymbolicLinks(executable)
        while directory != "/" && !directory.isEmpty {
            directory = (directory as NSString).deletingLastPathComponent
            for candidate in ["Contents/Info.plist", "Resources/Info.plist", "Info.plist"] {
                guard let data = FileManager.default.contents(atPath: directory + "/" + candidate) else { continue }
                guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let identifier = plist["CFBundleIdentifier"] as? String else { break }
                var info = BundleInfo(identifier: identifier)
                if let version = plist["CFBundleVersion"] as? String { info.version = version }
                if let shortVersion = plist["CFBundleShortVersionString"] as? String { info.shortVersion = shortVersion }
                return info
            }
        }
        return BundleInfo()
    }

    /// dsymutil's template (`createPlistFile` in `tools/dsymutil/dsymutil.cpp`).
    static func render(_ info: BundleInfo, bundleRoot: String, toolchain: String?) -> String {
        var identifier = info.identifier ?? ""
        if identifier.isEmpty {
            let name = (bundleRoot as NSString).lastPathComponent
            identifier = name.hasSuffix(".dSYM") ? (name as NSString).deletingPathExtension : name
        }
        var text = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            + "<!DOCTYPE plist PUBLIC \"-//Apple Computer//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
            + "<plist version=\"1.0\">\n"
            + "\t<dict>\n"
            + "\t\t<key>CFBundleDevelopmentRegion</key>\n"
            + "\t\t<string>English</string>\n"
            + "\t\t<key>CFBundleIdentifier</key>\n"
            + "\t\t<string>com.apple.xcode.dsym.\(escaped(identifier))</string>\n"
            + "\t\t<key>CFBundleInfoDictionaryVersion</key>\n"
            + "\t\t<string>6.0</string>\n"
            + "\t\t<key>CFBundlePackageType</key>\n"
            + "\t\t<string>dSYM</string>\n"
            + "\t\t<key>CFBundleSignature</key>\n"
            + "\t\t<string>????</string>\n"
        if !info.shortVersion.isEmpty {
            text += "\t\t<key>CFBundleShortVersionString</key>\n\t\t<string>\(escaped(info.shortVersion))</string>\n"
        }
        text += "\t\t<key>CFBundleVersion</key>\n\t\t<string>\(escaped(info.version))</string>\n"
        if let toolchain, !toolchain.isEmpty {
            text += "\t\t<key>Toolchain</key>\n\t\t<string>\(escaped(toolchain))</string>\n"
        }
        return text + "\t</dict>\n</plist>\n"
    }

    /// Rewrites the Info.plist of the dSYM dsymutil wrote for `executable` at `bundleRoot`.
    public static func rewrite(bundleRoot: String, executable: String, toolchain: String?) throws {
        let text = render(bundleInfo(executable: executable), bundleRoot: bundleRoot, toolchain: toolchain)
        try FileSystem.write(Data(text.utf8), to: bundleRoot + "/Contents/Info.plist")
    }

    /// `llvm::printHTMLEscaped`.
    private static func escaped(_ value: String) -> String {
        var result = ""
        for character in value {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            default: result.append(character)
            }
        }
        return result
    }
}
