import Foundation
import NomacCore

/// Xcode's App Intents tools, which Swift Build runs for every Swift target
/// (`ExtractAppIntentsMetadata`, `AppIntentsSSUTraining`), for targets that use no App Intents.
///
/// Observed on retro-rampage's `Engine` (Xcode 27.0): `appintentsmetadataprocessor` reports
/// "Metadata extraction skipped, no AppIntents.framework dependency found" and writes only its
/// strings data, an empty table set; `appintentsnltrainingprocessor` reports "No AppShortcuts
/// found - Skipping." and writes nothing. A target that uses App Intents gets its metadata from
/// ``AppIntentsMetadata``, one with App Shortcuts their training from ``AppShortcutsTraining``.
public enum AppIntentsTools {
    /// The strings data `appintentsmetadataprocessor` wrote for a target without App Intents.
    static let emptyStringsData = "{\n  \"source\" : \"ExtractedAppShortcutsMetadata\",\n  \"tables\" : {\n\n  },\n  \"version\" : 2\n}"

    /// `appintentsmetadataprocessor <options>`.
    public static func extractMetadata(_ arguments: [String]) throws {
        let options = try parse(arguments)
        guard let binary = options["--binary-file"], let stringsData = options["--stringsdata-file"] else {
            throw NomacError("appintentsmetadataprocessor needs --binary-file and --stringsdata-file")
        }
        // A dependency's metadata (`--metadata-file-list`: an embedded extension's, a framework's)
        // adds nothing to the target's own (`embedded`); the dependencies' entities and enums are
        // the types of the target's parameters and results that its own constant values lack
        // (`dependency`).
        guard try usesAppIntents(binary) else {
            try FileSystem.write(Data(emptyStringsData.utf8), to: stringsData)
            return
        }
        guard options["--compile-time-extraction"] != nil, let list = options["--swift-const-vals-list"], let output = options["--output"],
              let version = options["--xcode-version"] else {
            throw NomacError("the target uses App Intents: nomac extracts their metadata from the Swift compiler's constant values only (--compile-time-extraction, --swift-const-vals-list, --output, --xcode-version)", path: binary)
        }
        // One list per architecture (`watch`: arm64 and arm64_32); the strings data goes to the
        // last `--stringsdata-file` only, as Xcode writes it.
        let files = values(of: "--swift-const-vals-list", in: arguments, default: list).flatMap { list in
            constValuesList(FileManager.default.contents(atPath: list).map { String(decoding: $0, as: UTF8.self) } ?? "")
        }
        let dependencies = try listedFiles(options["--metadata-file-list"]).compactMap { try actionsData($0) }
        let metadata = try AppIntentsMetadata(constValueFiles: files, moduleName: options["--module-name"] ?? "", dependencies: dependencies)
        // Linking App Intents without declaring any of its types: "Extracted no relevant App Intents
        // symbols, skipping writing output", only the empty strings data (`linked`).
        guard metadata.usesAppIntents else {
            try FileSystem.write(Data(emptyStringsData.utf8), to: stringsData)
            return
        }
        try metadata.write(output: output, stringsData: stringsData, xcodeVersion: version)
    }

    /// The files of `--swift-const-vals-list`, which Swift Build writes with each path's blanks and
    /// punctuation escaped by backslashes (`quotedStringListRepresentation`); Xcode's tool splits it
    /// by line and removes every backslash (SWBApplePlatform `AppIntentsMetadataCompiler`; gomap's
    /// `Go\ Map\!\!-primary.swiftconstvalues`).
    static func constValuesList(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { $0.replacingOccurrences(of: "\\", with: "") }
    }

    /// Whether the target's binary links App Intents: an image through its libraries, a static
    /// library (CocoaPods' pods: Xcode's tool writes the same strings data for expo-default's 17)
    /// through the linker options of its objects, which name each framework they import. A
    /// universal file (watchOS's arm64 and arm64_32, `watch`) by its 64-bit slices.
    static func usesAppIntents(_ binary: String) throws -> Bool {
        guard let data = FileManager.default.contents(atPath: binary) else { throw NomacError("cannot read the file", path: binary) }
        return try slices([UInt8](data), path: binary).contains { slice in
            if slice.starts(with: StaticArchive.magic) {
                return try StaticArchive(bytes: slice, path: binary).members.contains { member in
                    guard member.contents.starts(with: [0xcf, 0xfa, 0xed, 0xfe]) else { return false }
                    return try MachODylib.linkerOptions(MachOReader(bytes: member.contents, path: binary + "(" + member.name + ")")).contains("AppIntents")
                }
            }
            return try MachODylib.dependencies(MachOReader(bytes: slice, path: binary)).contains { $0.hasSuffix("/AppIntents.framework/AppIntents") }
        }
    }

    /// The 64-bit slices of a universal file (`fat_header` and `fat_arch`, big-endian, from
    /// `<mach-o/fat.h>`), or the file itself; a universal file without one is refused.
    static func slices(_ bytes: [UInt8], path: String) throws -> [[UInt8]] {
        func be32(_ offset: Int) -> Int { (0..<4).reduce(0) { $0 << 8 | Int(bytes[offset + $1]) } }
        guard bytes.count >= 8, be32(0) == 0xcafe_babe else { return [bytes] }
        let slices = try (0..<be32(4)).compactMap { index -> [UInt8]? in
            let entry = 8 + 20 * index
            guard entry + 20 <= bytes.count else { throw NomacError("a truncated universal file", path: path) }
            let offset = be32(entry + 8), size = be32(entry + 12)
            guard offset + size <= bytes.count else { throw NomacError("a truncated universal file", path: path) }
            return be32(entry) & 0x0100_0000 != 0 ? Array(bytes[offset..<(offset + size)]) : nil
        }
        guard !slices.isEmpty else { throw NomacError("a universal file without a 64-bit slice, whose App Intents nomac has not observed (B-159)", path: path) }
        return slices
    }

    /// `appintentsnltrainingprocessor <options>`, with the phrase lists of the developer
    /// directory's Xcode (`SiriSSUKitModel.framework/Resources`).
    public static func trainShortcuts(_ arguments: [String], developerDirectory: String?, time: Date = Date()) throws {
        let options = try parse(arguments)
        // Dependencies' App Shortcuts (an embedded extension's) are refused: no experiment has
        // trained a target with them; without any the target's training is its own (`embedded`).
        for file in listedFiles(options["--metadata-file-list"]) where try hasShortcuts(actionsData(file)) {
            throw NomacError("a dependency of the target has App Shortcuts, whose training with the target's no experiment has shown (B-159)", path: file)
        }
        // A target without App Shortcuts gets nothing: "No AppShortcuts found - Skipping."
        // (`no-shortcuts`).
        guard let metadata = options["--extracted-metadata-path"], let data = try actionsData(metadata + "/extract.actionsdata"), hasShortcuts(data) else { return }
        guard let plistPath = options["--infoplist-path"], let temporary = options["--temp-dir-path"], let bundleIdentifier = options["--bundle-id"],
              options["--archive-ssu-assets"] != nil, options["--vocabulary-file"] == nil else {
            throw NomacError("nomac trains App Shortcuts as Xcode's build does (--infoplist-path, --temp-dir-path, --bundle-id, --archive-ssu-assets, no --vocabulary-file)", path: metadata)
        }
        let plist = (try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: plistPath)), format: nil)) as? [String: Any] ?? [:]
        guard plist["CFBundleIdentifier"] as? String == bundleIdentifier else {
            throw NomacError("Mismatch bundle identifier values between Info.plist and --bundle-id.", path: plistPath)
        }
        // `${+applicationName}`: the bundle's display name, else its name (`training`, `basic`).
        let bundle = ((plistPath as NSString).deletingLastPathComponent as NSString).lastPathComponent
        let name = plist["CFBundleDisplayName"] as? String ?? plist["CFBundleName"] as? String ?? (bundle as NSString).deletingPathExtension
        guard let developerDirectory else {
            throw NomacError("App Shortcuts training needs Xcode's phrase lists: run it from the launcher 'nomac toolchain install' writes, or set DEVELOPER_DIR")
        }
        let phraseLists = (developerDirectory as NSString).deletingLastPathComponent + "/Frameworks/SiriSSUKitModel.framework/Resources"
        let available = Set(((try? FileManager.default.contentsOfDirectory(atPath: phraseLists + "/prefix")) ?? []).filter { $0.hasSuffix(".yaml") }.map { String($0.dropLast(5)) })
        guard !available.isEmpty else { throw NomacError("Xcode's App Shortcuts phrase lists are missing (nomac sdk keeps them)", path: phraseLists) }
        // Every `.lproj` folder of the product is a locale of its own (`localized`: 31 of them,
        // Base too); without any, English (`training`).
        let product = options["--product-path"]
        let folders = product.map { product in ((try? FileManager.default.contentsOfDirectory(atPath: product)) ?? []).filter { $0.hasSuffix(".lproj") }.sorted() } ?? []
        guard folders != ["Base.lproj"] else {
            throw NomacError("an app whose only localization is Base, whose App Shortcuts training no experiment has shown (B-159)", path: product)
        }
        let locales = try folders.isEmpty ? [AppShortcutsTraining.Locale(name: "en", applicationName: name, lists: try AppShortcutsTraining.lists(for: "en", available: available))]
            : folders.map { folder in
                let directory = product! + "/" + folder
                let locale = String(folder.dropLast(".lproj".count))
                func table(_ name: String) throws -> [String: String] {
                    guard let data = FileManager.default.contents(atPath: directory + "/" + name + ".strings") else { return [:] }
                    guard let table = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] else {
                        throw NomacError("a strings table that is no dictionary of strings", path: directory + "/" + name + ".strings")
                    }
                    return table
                }
                return AppShortcutsTraining.Locale(name: locale, applicationName: try table("InfoPlist")["CFBundleDisplayName"] ?? name,
                                                   shortcutPhrases: try table("AppShortcuts"), strings: try table("Localizable"),
                                                   lists: try AppShortcutsTraining.lists(for: locale, available: available))
            }
        let training = try AppShortcutsTraining(actionsData: data, bundleIdentifier: bundleIdentifier, locales: locales)
        try training.write(product: folders.isEmpty ? nil : product, metadata: metadata, temporary: temporary, phraseLists: phraseLists, time: time)
    }

    private static func hasShortcuts(_ data: [String: Any]?) -> Bool {
        !(data?["autoShortcuts"] as? [Any] ?? []).isEmpty
    }

    private static func actionsData(_ path: String) throws -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw NomacError("not App Intents metadata", path: path) }
        return object
    }

    /// The files a metadata file list names that exist. Swift Build lists the
    /// `Metadata.appintents/extract.actionsdata` of every bundle the target depends on, whether
    /// or not it was written (SWBApplePlatform `AppIntentsMetadataTaskProducer`); a dependency
    /// without App Intents has none.
    static func listedFiles(_ list: String?) -> [String] {
        guard let list, let contents = FileManager.default.contents(atPath: list) else { return [] }
        return String(decoding: contents, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init)
            .filter { !$0.isEmpty && FileManager.default.fileExists(atPath: $0) }
    }

    /// Every value of an option given once per architecture.
    static func values(of option: String, in arguments: [String], default value: String) -> [String] {
        let all = arguments.indices.dropLast().filter { arguments[$0] == option }.map { arguments[$0 + 1] }
        return all.isEmpty ? [value] : all
    }

    /// The `--name value` options of a command line, the last value of a repeated one; flags
    /// without a value map to "".
    private static func parse(_ arguments: [String]) throws -> [String: String] {
        var options: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            guard argument.hasPrefix("--") else { throw NomacError("unexpected argument '\(argument)'") }
            if index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") {
                options[argument] = arguments[index + 1]
                index += 2
            } else {
                options[argument] = ""
                index += 1
            }
        }
        return options
    }
}
