import Foundation
import NomacCore

/// The directory where nomac keeps the Xcode subsets it has installed.
///
/// Layout (`$NOMAC_HOME`, default `~/.nomac`):
///
/// ```
/// xcode/
///   <ProductBuildVersion>/
///     Xcode.app/Contents/...   copied subset, or a symbolic link to an installed Xcode.app
///     DeveloperDiskImages/iOS_DDI   the Developer Disk Image, from Xcode's XcodeSystemResources.pkg
///     install.json             how this entry was created
///   selected                   the build used when none is named
/// ```
public struct SDKStore: Sendable {
    /// The root of the store (`$NOMAC_HOME`).
    public let root: String

    public init(root: String) {
        self.root = root
    }

    /// The store at `$NOMAC_HOME`, or `~/.nomac` when it is unset.
    public static func `default`(environment: [String: String] = ProcessInfo.processInfo.environment) -> SDKStore {
        if let home = environment["NOMAC_HOME"], !home.isEmpty {
            return SDKStore(root: FileSystem.absolute(home))
        }
        return SDKStore(root: NSHomeDirectory() + "/.nomac")
    }

    var xcodeRoot: String { root + "/xcode" }
    var selectedFile: String { xcodeRoot + "/selected" }

    /// One installed Xcode.
    public struct Entry: Sendable, Equatable, Codable {
        public var version: XcodeVersionInfo
        /// How the entry was created: `copy` (subset copied) or `link` (links to an installed Xcode).
        public var kind: String
        /// The `.xip` or `.app` the entry was created from.
        public var source: String
        /// The platforms whose SDK payload was copied (empty for `link`, which has everything).
        public var payloadPlatforms: [String]
        /// The `Xcode.app` inside the store.
        public var appPath: String

        /// The `Contents/Developer` directory handed to Swift Build.
        public var developerDirectory: String { appPath + "/Contents/Developer" }

        /// The Developer Disk Image extracted from the Xcode at install time, when 7-Zip and xz
        /// were there (ADR 0403).
        public var developerDiskImage: String { (appPath as NSString).deletingLastPathComponent + "/DeveloperDiskImages/iOS_DDI" }
    }

    /// All installed entries, sorted by build.
    public func entries() throws -> [Entry] {
        guard FileSystem.isDirectory(xcodeRoot) else { return [] }
        var result: [Entry] = []
        for name in try FileSystem.sortedContents(of: xcodeRoot) where !name.hasPrefix(".") && name != "selected" {
            let manifest = xcodeRoot + "/" + name + "/install.json"
            guard let data = FileManager.default.contents(atPath: manifest) else { continue }
            do {
                result.append(try JSONDecoder().decode(Entry.self, from: data))
            } catch {
                throw NomacError("corrupt install record: \(error)", path: manifest)
            }
        }
        return result
    }

    /// The build named by `selected`, if any.
    public func selectedBuild() -> String? {
        guard let data = FileManager.default.contents(atPath: selectedFile) else { return nil }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Marks `build` as the default Xcode.
    public func select(build: String) throws {
        guard try entries().contains(where: { $0.version.build == build }) else {
            throw NomacError("no Xcode with build \(build) is installed", notes: ["run 'nomac sdk list' to see installed builds"])
        }
        try FileSystem.write(Data((build + "\n").utf8), to: selectedFile)
    }

    /// Resolves an entry: the one named by `build`, else the selected one, else the only one.
    public func resolve(build: String?) throws -> Entry {
        let all = try entries()
        if let build {
            guard let entry = all.first(where: { $0.version.build == build }) else {
                throw NomacError("no Xcode with build \(build) is installed", notes: ["run 'nomac sdk list' to see installed builds"])
            }
            return entry
        }
        if let selected = selectedBuild(), let entry = all.first(where: { $0.version.build == selected }) {
            return entry
        }
        if all.count == 1 { return all[0] }
        if all.isEmpty {
            throw NomacError("no Xcode is installed", notes: ["run 'nomac sdk install <Xcode.xip | Xcode.app>' first"])
        }
        throw NomacError("several Xcode builds are installed and none is selected", notes: ["run 'nomac sdk select <build>'"])
    }

    /// Removes an installed entry.
    public func remove(build: String) throws {
        let dir = xcodeRoot + "/" + build
        guard FileSystem.isDirectory(dir) else {
            throw NomacError("no Xcode with build \(build) is installed")
        }
        try FileManager.default.removeItem(atPath: dir)
        if selectedBuild() == build {
            try? FileManager.default.removeItem(atPath: selectedFile)
        }
    }

    /// Records an existing `Xcode.app` without copying it (for a Mac that has Xcode installed).
    /// `accept` sees its version first and may refuse it by throwing.
    public func link(app: String, accept: (XcodeVersionInfo) throws -> Void = { _ in }) throws -> Entry {
        let appPath = FileSystem.absolute(app)
        let version = try XcodeVersionInfo.read(appPath: appPath)
        try accept(version)
        let dir = xcodeRoot + "/" + version.build
        if FileManager.default.fileExists(atPath: dir) {
            try FileManager.default.removeItem(atPath: dir)
        }
        try FileSystem.createDirectory(dir)
        do {
            try FileManager.default.createSymbolicLink(atPath: dir + "/Xcode.app", withDestinationPath: appPath)
        } catch {
            throw NomacError("could not link Xcode: \(error.localizedDescription)", path: dir)
        }
        let entry = Entry(version: version, kind: "link", source: appPath, payloadPlatforms: [], appPath: dir + "/Xcode.app")
        try writeRecord(entry, in: dir)
        return entry
    }

    /// Copies the subset of `app` (an `Xcode.app`) into the store.
    ///
    /// The copy is assembled in a hidden staging directory and moved into place only when
    /// complete, so an interrupted install never leaves a half-copied entry behind. `accept`
    /// sees the Xcode's version before anything is copied and may refuse it by throwing.
    public func install(app: String, subset: XcodeSubset, source: String? = nil, accept: (XcodeVersionInfo) throws -> Void = { _ in },
                        progress: @escaping (String) -> Void = { _ in }) throws -> Entry {
        let appPath = FileSystem.absolute(app)
        let version = try XcodeVersionInfo.read(appPath: appPath)
        try accept(version)
        let staging = xcodeRoot + "/.staging-" + version.build
        if FileManager.default.fileExists(atPath: staging) {
            try FileManager.default.removeItem(atPath: staging)
        }
        let stagedApp = staging + "/Xcode.app"
        try FileSystem.createDirectory(stagedApp)
        var copier = SubsetCopier(subset: subset, sourceRoot: appPath, destinationRoot: stagedApp, progress: progress)
        try copier.copy()
        try extractDeveloperDiskImage(app: appPath, to: staging + "/DeveloperDiskImages/iOS_DDI", progress: progress)
        let dir = xcodeRoot + "/" + version.build
        let entry = Entry(version: version, kind: "copy", source: source ?? appPath, payloadPlatforms: subset.payloadPlatforms.sorted(), appPath: dir + "/Xcode.app")
        try writeRecord(entry, in: staging)
        if FileManager.default.fileExists(atPath: dir) {
            try FileManager.default.removeItem(atPath: dir)
        }
        do {
            try FileManager.default.moveItem(atPath: staging, toPath: dir)
        } catch {
            throw NomacError("could not move the installed Xcode into place: \(error.localizedDescription)", path: dir)
        }
        progress("installed \(copier.filesCopied) files (\(ByteCountFormatter.string(fromByteCount: copier.bytesCopied, countStyle: .file)))")
        return entry
    }

    /// Expands `xip` with the `unxip` tool into a staging directory, then installs the subset.
    public func install(xip: String, subset: XcodeSubset, unxip: String, accept: (XcodeVersionInfo) throws -> Void = { _ in },
                        progress: @escaping (String) -> Void = { _ in }) throws -> Entry {
        let xipPath = FileSystem.absolute(xip)
        guard FileSystem.isFile(xipPath) else {
            throw NomacError("no such file", path: xipPath)
        }
        let staging = xcodeRoot + "/.expand-\(UUID().uuidString)"
        try FileSystem.createDirectory(staging)
        defer { try? FileManager.default.removeItem(atPath: staging) }
        progress("expanding \(xipPath) with \(unxip) (this needs as much free disk space as Xcode itself)")
        let result = try Subprocess.run(unxip, [xipPath, staging], passthrough: true)
        guard result.exitStatus == 0 else {
            throw NomacError("unxip failed with exit status \(result.exitStatus)", path: xipPath)
        }
        let apps = try FileSystem.sortedContents(of: staging).filter { $0.hasSuffix(".app") }
        guard apps.count == 1 else {
            throw NomacError("expected exactly one .app inside the .xip, found \(apps.count)", path: xipPath)
        }
        return try install(app: staging + "/" + apps[0], subset: subset, source: xipPath, accept: accept, progress: progress)
    }

    /// The Developer Disk Image when the Xcode ships it and 7-Zip and xz are installed; without
    /// them a note says what launching on a device then lacks.
    func extractDeveloperDiskImage(app: String, to destination: String, progress: (String) -> Void) throws {
        guard FileSystem.isFile(app + "/" + DeveloperDiskImageExtraction.package) else { return }
        guard let sevenZip = ExternalTools.sevenZip.locate(), let xz = ExternalTools.xz.locate() else {
            progress("note: without 7z and xz the Developer Disk Image is not extracted; 'nomac device mount' then needs --ddi (\(ExternalTools.sevenZip.installation), \(ExternalTools.xz.installation))")
            return
        }
        progress("extracting the Developer Disk Image")
        try DeveloperDiskImageExtraction.extract(app: app, to: destination, sevenZip: sevenZip, xz: xz)
    }

    private func writeRecord(_ entry: Entry, in dir: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileSystem.write(try encoder.encode(entry), to: dir + "/install.json")
    }
}

/// Walks an `Xcode.app` and copies the paths an ``XcodeSubset`` keeps.
struct SubsetCopier {
    let subset: XcodeSubset
    let sourceRoot: String
    let destinationRoot: String
    let progress: (String) -> Void
    private(set) var filesCopied = 0
    private(set) var bytesCopied: Int64 = 0

    init(subset: XcodeSubset, sourceRoot: String, destinationRoot: String, progress: @escaping (String) -> Void) {
        self.subset = subset
        self.sourceRoot = sourceRoot
        self.destinationRoot = destinationRoot
        self.progress = progress
    }

    mutating func copy() throws {
        try walk([])
    }

    private mutating func walk(_ relative: [String]) throws {
        let dir = path(sourceRoot, relative)
        for name in try FileSystem.sortedContents(of: dir) {
            let child = relative + [name]
            let source = path(sourceRoot, child)
            let type = try fileType(source)
            switch subset.decide(child, isDirectory: type == .typeDirectory) {
            case .skip:
                continue
            case .descend:
                if type == .typeDirectory {
                    try FileSystem.createDirectory(path(destinationRoot, child))
                    try walk(child)
                }
            case .keep:
                try copyTree(child)
            }
        }
    }

    /// Copies `relative` and everything below it, preserving symbolic links and permissions.
    private mutating func copyTree(_ relative: [String]) throws {
        let source = path(sourceRoot, relative)
        let destination = path(destinationRoot, relative)
        let type = try fileType(source)
        let fm = FileManager.default
        switch type {
        case .typeSymbolicLink:
            let target = try fm.destinationOfSymbolicLink(atPath: source)
            try fm.createSymbolicLink(atPath: destination, withDestinationPath: target)
        case .typeDirectory:
            try FileSystem.createDirectory(destination)
            for name in try FileSystem.sortedContents(of: source) {
                try copyTree(relative + [name])
            }
        case .typeRegular:
            let attributes = try fm.attributesOfItem(atPath: source)
            try fm.copyItem(atPath: source, toPath: destination)
            if let permissions = attributes[.posixPermissions] {
                try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: destination)
            }
            filesCopied += 1
            bytesCopied += (attributes[.size] as? NSNumber)?.int64Value ?? 0
            if filesCopied % 5000 == 0 {
                progress("copied \(filesCopied) files")
            }
        default:
            // Sockets, devices and FIFOs never occur in an Xcode bundle; skip them silently.
            break
        }
    }

    private func fileType(_ path: String) throws -> FileAttributeType {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            return attributes[.type] as? FileAttributeType ?? .typeUnknown
        } catch {
            throw NomacError("could not read file attributes: \(error.localizedDescription)", path: path)
        }
    }

    private func path(_ root: String, _ relative: [String]) -> String {
        relative.isEmpty ? root : root + "/" + relative.joined(separator: "/")
    }
}
