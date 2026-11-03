import Foundation
import NomacBuildService
import NomacCore
import NomacProject

/// Xcode's DerivedData layout for scheme builds (the build "arena").
///
/// Observed (retro-rampage, tofu): with no `-derivedDataPath`, products go to
/// `~/Library/Developer/Xcode/DerivedData/<folder name>-<hash>/Build/Products`, where the
/// folder name is ``folderName(_:)`` of the workspace's name and `<hash>` is
/// ``folderHash(_:)`` of the absolute path of the `.xcodeproj` (or `.xcworkspace`) that was
/// opened, both decomposed (loader-experiments `derived-data-names`). The DerivedData root
/// itself hosts the shared module and SDK stat caches.
public enum DerivedData {
    /// Xcode's default DerivedData root for a home directory.
    public static func defaultRoot(home: String) -> String {
        home + "/Library/Developer/Xcode/DerivedData"
    }

    /// The name of a workspace's folder, before its hash: the workspace's name, decomposed,
    /// with each run of spaces, tabs, carriage returns and line feeds replaced by one `_`
    /// (loader-experiments `derived-data-names`: `App 2` is `App_2`, ` Leading` `_Leading`,
    /// `Space \t Tab` `Space_Tab`, `Under_ Space` `Under__Space`; vertical tabs, form feeds,
    /// other control characters, no-break and other Unicode spaces and every punctuation
    /// character are kept).
    public static func folderName(_ name: String) -> String {
        var result = ""
        var inRun = false
        for scalar in name.decomposed.unicodeScalars {
            if [" ", "\t", "\r", "\n"].contains(scalar) {
                if !inRun { result.append("_") }
                inRun = true
            } else {
                result.unicodeScalars.append(scalar)
                inRun = false
            }
        }
        return result
    }

    /// The folder of the workspace named `name` opened at `containerPath`.
    static func workspaceFolder(name: String, containerPath: String, home: String) -> String {
        defaultRoot(home: home) + "/" + folderName(name) + "-" + folderHash(containerPath.decomposed)
    }

    /// The 28-letter folder hash: the MD5 digest of `path` read as two big-endian 64-bit
    /// integers, each written as 14 base-26 digits (`a` to `z`), most significant first.
    public static func folderHash(_ path: String) -> String {
        let digest = MD5.digest(Array(path.utf8))
        func base26(_ bytes: ArraySlice<UInt8>) -> String {
            var value = bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            var letters = [Character](repeating: "a", count: 14)
            for index in stride(from: 13, through: 0, by: -1) {
                letters[index] = Character(UnicodeScalar(UInt8(97 + value % 26)))
                value /= 26
            }
            return String(letters)
        }
        return base26(digest[0..<8]) + base26(digest[8..<16])
    }

    /// The path whose ``folderHash(_:)`` names a workspace's folder: a project opened on its
    /// own is hashed by its `.xcodeproj` path, a workspace by its own path.
    public static func containerPath(of workspace: XcodeWorkspace) -> String {
        if workspace.isPackage, let folder = workspace.packageFolders.first { return folder }
        return workspace.isImplicit ? (workspace.projects.first?.path ?? workspace.path) : workspace.path
    }

    /// Where Xcode checks out a workspace's remote Swift packages: `SourcePackages` in the
    /// workspace's folder (netnewswire: `DerivedData/NetNewsWire-<hash>/SourcePackages`), or in
    /// the `-derivedDataPath` folder.
    public static func sourcePackagesPath(name: String, containerPath: String, home: String, customRoot: String?) -> String {
        let folder = customRoot ?? workspaceFolder(name: name, containerPath: containerPath, home: home)
        return folder + "/SourcePackages"
    }

    /// The arena for a scheme build of the container at `containerPath` named `name`.
    /// - Parameter customRoot: the `-derivedDataPath` argument, if given; it replaces the
    ///   per-workspace folder, as it does for xcodebuild.
    public static func locations(name: String, containerPath: String, home: String, customRoot: String?) -> BuildLocations {
        let root: String
        let workspaceFolder: String
        if let customRoot {
            root = customRoot
            workspaceFolder = customRoot
        } else {
            root = defaultRoot(home: home)
            workspaceFolder = Self.workspaceFolder(name: name, containerPath: containerPath, home: home)
        }
        let intermediates = workspaceFolder + "/Build/Intermediates.noindex"
        return BuildLocations(
            derivedDataPath: root,
            buildProductsPath: workspaceFolder + "/Build/Products",
            buildIntermediatesPath: intermediates,
            pchPath: intermediates + "/PrecompiledHeaders",
            indexPCHPath: workspaceFolder + "/Index.noindex/PrecompiledHeaders")
    }
}

/// `-destination` values nomac understands.
public enum DestinationSpecifier {
    /// Parses an xcodebuild destination specifier. Only generic device destinations are
    /// accepted: nomac never runs on a Mac, so "My Mac" and simulators do not exist for it.
    public static func parse(_ specifier: String) throws -> RunDestination {
        let normalized = specifier.replacingOccurrences(of: " ", with: "")
        switch normalized {
        case "generic/platform=iOS":
            // Xcode's "Any iOS Device", as modelled by Swift Build's own tests
            // (SWBTestSupport `RunDestinationInfo.anyiOSDevice`).
            return RunDestination(platform: "iphoneos", sdk: "iphoneos", sdkVariant: "iphoneos", targetArchitecture: "undefined_arch",
                                  supportedArchitectures: ["arm64", "arm64e", "armv7", "armv7s"], disableOnlyActiveArch: true)
        default:
            throw NomacError("unsupported destination '\(specifier)'", notes: ["nomac currently supports -destination 'generic/platform=iOS'"])
        }
    }

    /// The specifier as xcodebuild prints it in errors: `generic/platform=iOS` is
    /// `{ generic:1, platform:iOS }`.
    public static func describe(_ specifier: String) -> String {
        var pairs: [String] = []
        for component in specifier.split(separator: ",") {
            var text = component.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("generic/") {
                pairs.append("generic:1")
                text.removeFirst("generic/".count)
            }
            pairs.append(text.replacingOccurrences(of: "=", with: ":"))
        }
        return "{ " + pairs.joined(separator: ", ") + " }"
    }
}
