import Foundation
import NomacCore

/// The file types Xcode gives files on disk: the members of synchronized folders, and file
/// references whose declared type Xcode does not know.
///
/// The types come from the `FileType` specifications Swift Build ships in its universal and
/// Apple platform plugins (the platforms Xcode builds for), refined the way Xcode was observed
/// to refine them (docs/formats/pif.md, "Synchronized folders" and "Group tree"):
///
/// - extensions match case-sensitively first (`h` is C, `H` is C++), then case-insensitively;
///   when two types claim an extension, the last one read keeps it (`.o` is
///   `compiled.object-library`, `.ll` `sourcecode.asm.llvm`, `.appex`
///   `wrapper.extensionkit-extension`);
/// - a file keeps its extension's type unless that type is a folder type (`IsFolder`, inherited
///   through `BasedOn`): a plain file named `X.framework` is typed by its contents;
/// - a `.plist` file is `text.plist.xml` when it holds an XML property list, and
///   `text.plist.binary` when it holds a binary one; a Mach-O or archive header decides the
///   type of a file whose extension names a `compiled.mach-o` type (`.dylib`, `.o`);
/// - any other file is typed by its name and its first 1,024 bytes: a `FilenamePatterns` match
///   (`Makefile`), a `MagicWord` prefix (`#!/bin/sh`, `<?xml`, `bplist00`), a Mach-O header (by
///   its file type) or `!<arch>`, then `text` unless the bytes look binary; a path that is not
///   on disk is `text` without an extension and `file` with one (nextcloud's `.tx/config` is
///   `text`);
/// - a directory takes its extension's type unless that type is a text type (`IsTextFile`,
///   inherited); a directory whose extension no type claims is a `wrapper` when the Mac
///   registers the extension as a package or the directory holds a `Package.swift`; any other
///   directory is a group.
public struct FileTypeRegistry: Sendable {
    struct FileType: Sendable {
        var identifier: String
        var basedOn: String?
        var extensions: [String]
        var isFolder: Bool?
        var isTextFile: Bool?
    }

    struct Pattern: Sendable {
        var pattern: String
        var identifier: String
    }

    struct MagicWord: Sendable {
        var bytes: [UInt8]
        var identifier: String
    }

    private var types: [String: FileType] = [:]
    private var byExtension: [String: String] = [:]
    private var byLowercasedExtension: [String: String] = [:]
    private var filenamePatterns: [Pattern] = []
    private var magicWords: [MagicWord] = []

    /// Swift Build modules whose specifications define the file types Xcode uses.
    public static let specificationModules = ["SWBUniversalPlatform", "SWBApplePlatform"]

    /// Extensions no type claims that the Mac registers as packages: a directory with one of
    /// them is a `wrapper` (`pif-experiments` untyped folders: `.key`, `.mlmodelc`, `.pages`,
    /// `.photoslibrary` and `.plugin` are; `.rcproject`, `.reality`, `.usdz`, `.ttf`, `.zzz` and
    /// others are groups).
    static let packageExtensions: Set<String> = ["key", "mlmodelc", "pages", "photoslibrary", "plugin"]

    /// Reads every `FileType` specification in the given `.xcspec` files, in order.
    public init(specificationFiles: [String]) throws {
        for path in specificationFiles {
            guard let data = FileManager.default.contents(atPath: path) else {
                throw NomacError("could not read the specification file", path: path)
            }
            let plist: Any
            do {
                plist = try PropertyListSerialization.propertyList(from: data, format: nil)
            } catch {
                throw NomacError("malformed specification file: \(error)", path: path)
            }
            for case let item as [String: Any] in (plist as? [Any]) ?? [plist] where item["Type"] as? String == "FileType" {
                guard let identifier = item["Identifier"] as? String else { continue }
                let type = FileType(identifier: identifier, basedOn: item["BasedOn"] as? String, extensions: item["Extensions"] as? [String] ?? [],
                                    isFolder: Self.flag(item["IsFolder"]), isTextFile: Self.flag(item["IsTextFile"]))
                types[identifier] = type
                for ext in type.extensions where !ext.isEmpty {
                    byExtension[ext] = identifier
                    byLowercasedExtension[ext.lowercased()] = identifier
                }
                for pattern in item["FilenamePatterns"] as? [String] ?? [] {
                    filenamePatterns.append(Pattern(pattern: pattern, identifier: identifier))
                }
                for word in item["MagicWord"] as? [Any] ?? [] {
                    if let string = word as? String {
                        magicWords.append(MagicWord(bytes: Array(string.utf8), identifier: identifier))
                    } else if let data = word as? Data {
                        magicWords.append(MagicWord(bytes: Array(data), identifier: identifier))
                    }
                }
            }
        }
    }

    private static func flag(_ value: Any?) -> Bool? {
        if let string = value as? String { return string.uppercased() == "YES" }
        return value as? Bool
    }

    /// The registry built from the Swift Build specifications installed next to nomac.
    public static func installed() throws -> FileTypeRegistry {
        var files: [String] = []
        for module in specificationModules {
            guard let directory = SwiftBuildResources.directory(module: module) else {
                throw NomacError("Swift Build's \(module) resources are not installed next to nomac")
            }
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
            files += names.filter { $0.hasSuffix(".xcspec") }.sorted().map { directory + "/" + $0 }
        }
        return try FileTypeRegistry(specificationFiles: files)
    }

    /// The identifiers from `identifier` up through its `BasedOn` chain.
    public func lineage(of identifier: String) -> [String] {
        var result: [String] = []
        var current: String? = identifier
        while let name = current, !result.contains(name) {
            result.append(name)
            current = types[name]?.basedOn
        }
        return result
    }

    /// Whether a type is a folder or wrapper type, which a directory that is one item has.
    public func isDirectoryType(_ identifier: String) -> Bool {
        identifier.hasPrefix("wrapper") || identifier.hasPrefix("folder")
            || lineage(of: identifier).contains { $0 == "wrapper" || $0 == "folder" }
    }

    /// Whether a type of the specifications is the folder kind, which only a directory has.
    func isFolderType(_ identifier: String) -> Bool {
        lineage(of: identifier).lazy.compactMap { types[$0]?.isFolder }.first ?? false
    }

    /// Whether a type of the specifications is a text type, which a directory never has.
    func isTextType(_ identifier: String) -> Bool {
        lineage(of: identifier).lazy.compactMap { types[$0]?.isTextFile }.first ?? false
    }

    public func type(forExtension ext: String) -> String? {
        guard !ext.isEmpty else { return nil }
        return byExtension[ext] ?? byLowercasedExtension[ext.lowercased()]
    }

    /// The file type of the item at `path`, or `nil` for a directory that is a group.
    public func fileType(atPath path: String, isDirectory: Bool) -> String? {
        let name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension
        if isDirectory {
            if let identifier = type(forExtension: ext), !isTextType(identifier) {
                return identifier
            }
            if Self.packageExtensions.contains(ext) || FileManager.default.fileExists(atPath: path + "/Package.swift") {
                return "wrapper"
            }
            return nil
        }
        guard let head = Self.head(of: path) else { return missingFileType(name: name) }
        if let identifier = type(forExtension: ext), !isFolderType(identifier) {
            if identifier == "text.plist" {
                if head.starts(with: Array("bplist".utf8)) { return "text.plist.binary" }
                if Self.isXML(head, alsoAccepting: ["<!DOCTYPE plist", "<plist"]) { return "text.plist.xml" }
            }
            if lineage(of: identifier).contains("compiled.mach-o") {
                return Self.machOType(head) ?? (Self.isArchive(head) ? "archive.ar" : identifier)
            }
            return identifier
        }
        if let match = filenamePatterns.first(where: { fnmatch($0.pattern, name, 0) == 0 }) { return match.identifier }
        if let match = magicWords.first(where: { head.starts(with: $0.bytes) }) { return match.identifier }
        if let identifier = Self.machOType(head) { return identifier }
        if Self.isArchive(head) { return "archive.ar" }
        return Self.looksBinary(head) ? "file" : "text"
    }

    /// The type Xcode gives a file reference with neither `lastKnownFileType` nor
    /// `explicitFileType` (envelope-experiments `file-type-none`, docs/formats/project-file.md):
    ///
    /// - a folder on disk is the type its extension names when that is a folder or wrapper type
    ///   (`folder.assetcatalog`, `wrapper.plug-in` for `.bundle`), else `folder`;
    /// - otherwise the type its extension names, on disk or not, except `.plist`, whose contents
    ///   decide: `text.plist.xml` for XML, `file.bplist` for a binary property list, `text.plist`
    ///   for the old ASCII format;
    /// - a missing file whose extension names no type is `text` without an extension, `file`
    ///   with one;
    /// - a file on disk whose extension names no type is read in its first 1024 bytes:
    ///   `file.bplist` for a binary property list; after a UTF-16 or UTF-32 byte order mark,
    ///   `text.xml` for an XML declaration and `text` otherwise; else `file` when a control byte
    ///   other than tab, line feed, vertical tab, form feed and carriage return occurs,
    ///   `text.xml` for an XML declaration (after a UTF-8 mark too), a script type for a `#!`
    ///   line at its very start (``scriptInterpreters``), and `text` otherwise (empty, bytes
    ///   above 127, DEL).
    /// - Parameters:
    ///   - name: the reference's path as written, whose extension counts.
    ///   - path: where it is on disk, nil when its source tree is a build setting's.
    public func referenceType(name: String, at path: String?) -> String {
        let ext = (name as NSString).pathExtension
        var isDirectory: ObjCBool = false
        let exists = path.map { FileManager.default.fileExists(atPath: $0, isDirectory: &isDirectory) } ?? false
        let claimed = type(forExtension: ext)
        if exists && isDirectory.boolValue {
            if let claimed, isDirectoryType(claimed) { return claimed }
            return "folder"
        }
        guard exists, let path else { return claimed ?? (ext.isEmpty ? "text" : "file") }
        let head = Self.head(of: path) ?? []
        if claimed == "text.plist" || claimed == nil, head.starts(with: Array("bplist".utf8)) { return "file.bplist" }
        switch claimed {
        case "text.plist"?:
            return Self.isXML(head, alsoAccepting: ["<!DOCTYPE plist", "<plist"]) ? "text.plist.xml" : "text.plist"
        case let claimed?:
            return claimed
        case nil:
            if let text = Self.wideText(head) { return text.hasPrefix("<?xml") ? "text.xml" : "text" }
            if head.contains(where: { $0 < 0x09 || (0x0E...0x1F).contains($0) }) { return "file" }
            if Self.isXML(head) { return "text.xml" }
            return Self.scriptType(head) ?? "text"
        }
    }

    /// The `#!` interpreters whose script type Xcode gives a file without a known extension
    /// (envelope-experiments `file-type-none`); any other, `dash`, `ksh`, `fish`, `php`, `node`,
    /// `swift`, `osascript` and `env` with any interpreter included, gives `text`.
    static let scriptInterpreters = ["sh": "text.script.sh", "bash": "text.script.sh", "zsh": "text.script.sh", "csh": "text.script.csh",
                                     "tcsh": "text.script.csh", "perl": "text.script.perl", "ruby": "text.script.ruby",
                                     "python": "text.script.python", "python3": "text.script.python"]

    /// The text of a head that starts with a UTF-32 or UTF-16 byte order mark.
    private static func wideText(_ head: [UInt8]) -> String? {
        let marks: [([UInt8], String.Encoding, Int)] = [([0xFF, 0xFE, 0, 0], .utf32LittleEndian, 4), ([0, 0, 0xFE, 0xFF], .utf32BigEndian, 4),
                                                       ([0xFF, 0xFE], .utf16LittleEndian, 2), ([0xFE, 0xFF], .utf16BigEndian, 2)]
        guard let (mark, encoding, width) = marks.first(where: { head.starts(with: $0.0) }) else { return nil }
        let body = head.dropFirst(mark.count)
        return String(data: Data(body.prefix(body.count - body.count % width)), encoding: encoding) ?? ""
    }

    private static func scriptType(_ head: [UInt8]) -> String? {
        guard head.starts(with: Array("#!".utf8)) else { return nil }
        let line = String(decoding: head.dropFirst(2).prefix { $0 != 0x0A }, as: UTF8.self)
        guard let interpreter = line.split(separator: " ").first else { return nil }
        return scriptInterpreters[(String(interpreter) as NSString).lastPathComponent]
    }

    /// Whether Xcode knows a declared type: it is a type of the specifications.
    public func isKnown(_ identifier: String) -> Bool {
        types[identifier] != nil
    }

    /// The type Xcode gives a file reference: its `explicitFileType` when Xcode knows that type,
    /// else its `lastKnownFileType` when Xcode knows it and does not type it again, else the type
    /// of what is at `path` (`nil` when the reference is not on the file system nomac sees),
    /// `folder` for a directory that is no item of its own (loader-experiments
    /// `declared-types`: every type of the specifications is kept on a file, a folder and a
    /// missing path, but `file` and `wrapper.framework.static` as `lastKnownFileType`; the
    /// types they lack are not, such as CocoaPods' `sourcecode.module` in signal or
    /// `wrapper.mlmodelc`). A reference that declares no type is ``referenceType(name:at:)``'s.
    public func referenceFileType(explicit: String?, lastKnown: String?, name: String, path: String?) -> String {
        if explicit == nil, lastKnown == nil { return referenceType(name: name, at: path) }
        if let explicit, isKnown(explicit) { return explicit }
        if let lastKnown, isKnown(lastKnown), !Self.retypedLastKnownTypes.contains(lastKnown) { return lastKnown }
        guard let path, FileManager.default.fileExists(atPath: path) else { return missingFileType(name: name) }
        return fileType(atPath: path, isDirectory: FileSystem.isDirectory(path)) ?? "folder"
    }

    static let retypedLastKnownTypes: Set<String> = ["file", "wrapper.framework.static"]

    /// The type of a file that is not on disk: its extension's type, else `text` without an
    /// extension and `file` with one, whatever its name (`pif-experiments` untyped files: a
    /// missing `Makefile` is `text`).
    func missingFileType(name: String) -> String {
        let ext = (name as NSString).pathExtension
        return type(forExtension: ext) ?? (ext.isEmpty ? "text" : "file")
    }

    /// A Mach-O header's type: `MH_OBJECT` to `MH_DYLIB_STUB` by `filetype`, other values
    /// `compiled.mach-o` (`pif-experiments` untyped files, 32- and 64-bit headers).
    static func machOType(_ head: [UInt8]) -> String? {
        guard head.count >= 16, head[0] == 0xCF || head[0] == 0xCE, Array(head[1..<4]) == [0xFA, 0xED, 0xFE] else { return nil }
        let types = [1: "objfile", 2: "executable", 3: "fvmlib", 4: "corefile", 5: "preload", 6: "dylib", 7: "dylinker", 8: "bundle", 9: "dylib"]
        let fileType = head[12..<16].reversed().reduce(0) { $0 << 8 | Int($1) }
        return types[fileType].map { "compiled.mach-o." + $0 } ?? "compiled.mach-o"
    }

    private static func isArchive(_ head: [UInt8]) -> Bool {
        head.starts(with: Array("!<arch>\n".utf8))
    }

    /// Whether the first bytes of a file no name or magic word types are binary: a UTF-8 or
    /// UTF-16 byte order mark makes them text, a NUL binary, and so does a share of control
    /// characters other than tab, line feed, vertical tab, form feed and carriage return above
    /// one tenth (`pif-experiments` untyped files: 10 of 100 bytes is text, 11 binary; 102 of
    /// 1,024 text, 103 binary, whatever the bytes after the first 1,024).
    static func looksBinary(_ head: [UInt8]) -> Bool {
        if [[0xEF, 0xBB, 0xBF], [0xFF, 0xFE], [0xFE, 0xFF]].contains(where: { head.starts(with: $0) }) { return false }
        if head.contains(0) { return true }
        return head.filter { $0 < 0x20 && !(0x09...0x0D).contains($0) }.count * 10 > head.count
    }

    private static func head(of path: String) -> [UInt8]? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        return Array((try? handle.read(upToCount: 1024)) ?? Data())
    }

    private static func isXML(_ head: [UInt8], alsoAccepting prefixes: [String] = []) -> Bool {
        var bytes = head[...]
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        bytes = bytes.drop { $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }
        return (["<?xml"] + prefixes).contains { bytes.starts(with: Array($0.utf8)) }
    }
}
