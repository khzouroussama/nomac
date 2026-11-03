#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import Foundation

/// Small, explicit file-system helpers used across nomac.
public enum FileSystem {
    /// Returns `true` if a directory exists at `path`, spelled in any normalization form and case.
    public static func isDirectory(_ path: String) -> Bool {
        kind(path) == true
    }

    /// Returns `true` if a regular file (or symlink to one) exists at `path`, spelled in any
    /// normalization form and case.
    public static func isFile(_ path: String) -> Bool {
        kind(path) == false
    }

    /// Returns `true` if anything exists at `path`, spelled in any normalization form and case.
    public static func exists(_ path: String) -> Bool {
        kind(path) != nil
    }

    /// Whether `path` is a directory, or `nil` when nothing is there.
    private static func kind(_ path: String) -> Bool? {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) { return isDir.boolValue }
        let found = onDisk(path)
        guard !found.isIdentical(to: path), FileManager.default.fileExists(atPath: found, isDirectory: &isDir) else { return nil }
        return isDir.boolValue
    }

    /// The spelling on disk of `path`. A Mac's default file systems find a file by a name in any
    /// normalization form and any case, a Linux file system only by the bytes of its name: there
    /// each component of a path that does not exist as given is matched to the entry of its
    /// directory that is canonically equivalent (a file written `Café` in NFC is found by the
    /// NFD path Xcode uses), else to one that differs only in case (cwa's `PDFGeneration`, on
    /// disk `PdfGeneration`; BACKLOG B-062). A component that exists as given is kept, and of
    /// several entries that match it otherwise (possible only where names are compared by their
    /// bytes, as on Linux), the first in byte order. The components after the first that nothing
    /// matches are kept as they are.
    public static func onDisk(_ path: String) -> String {
        if FileManager.default.fileExists(atPath: path) { return path }
        var resolved = path.hasPrefix("/") ? "/" : ""
        var searching = true
        for component in path.split(separator: "/").map(String.init) {
            var name = component
            if searching, component != ".", component != "..", !FileManager.default.fileExists(atPath: join(resolved, component)) {
                let entries = ((try? FileManager.default.contentsOfDirectory(atPath: resolved.isEmpty ? "." : resolved)) ?? [])
                    .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
                if let entry = entries.first(where: { $0 == component }) ?? entries.first(where: { $0.caseInsensitiveCompare(component) == .orderedSame }) {
                    name = entry
                } else {
                    searching = false
                }
            }
            resolved = join(resolved, name)
        }
        return resolved
    }

    private static func join(_ directory: String, _ name: String) -> String {
        directory.isEmpty ? name : (directory.hasSuffix("/") ? directory + name : directory + "/" + name)
    }

    /// The contents of the file at `path`, spelled in any normalization form.
    public static func contents(atPath path: String) -> Data? {
        FileManager.default.contents(atPath: path) ?? FileManager.default.contents(atPath: onDisk(path))
    }

    /// The names of the entries of the directory at `path`, spelled in any normalization form,
    /// as they are on disk.
    public static func contentsOfDirectory(_ path: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: onDisk(path))
    }

    /// Creates the directory `path`, its name's bytes as given, unless it exists: Foundation on
    /// macOS writes the names of what it creates decomposed (NFD), ditto keeps them.
    public static func createDirectoryExactly(_ path: String) throws {
        guard mkdir(path, 0o755) == 0 || errno == EEXIST else {
            throw NomacError("could not create directory: \(String(cString: strerror(errno)))", path: path)
        }
    }

    /// Writes `bytes` to the file `path`, its name's bytes as given (see `createDirectoryExactly`).
    public static func writeExactly(_ bytes: [UInt8], to path: String) throws {
        let descriptor = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard descriptor >= 0 else { throw NomacError("could not create file: \(String(cString: strerror(errno)))", path: path) }
        defer { close(descriptor) }
        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes { Foundation.write(descriptor, $0.baseAddress, $0.count) }
            guard written > 0 else { throw NomacError("could not write file: \(String(cString: strerror(errno)))", path: path) }
            offset += written
        }
    }

    /// Creates the symbolic link `path` to `target`, its name's bytes as given.
    public static func createSymbolicLinkExactly(_ path: String, to target: String) throws {
        guard symlink(target, path) == 0 else { throw NomacError("could not create link: \(String(cString: strerror(errno)))", path: path) }
    }

    /// Creates a directory and any missing parents.
    public static func createDirectory(_ path: String) throws {
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        } catch {
            throw NomacError("could not create directory: \(error.localizedDescription)", path: path)
        }
    }

    /// Writes `data` to `path` atomically, creating parent directories first.
    public static func write(_ data: Data, to path: String) throws {
        try createDirectory((path as NSString).deletingLastPathComponent)
        #if os(Linux)
        // Foundation's atomic write leaves its temporary file's descriptor open across exec, so a
        // process another thread starts meanwhile keeps the file open for writing, and running
        // the file then fails with ETXTBSY ("Text file busy"; 196 to 215 of 1,200 parallel
        // writes and runs of a script, none with O_CLOEXEC and Subprocess's retry).
        let temporary = path + ".nomac-\(getpid())-\(UInt32.random(in: 0 ... .max))"
        let descriptor = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o666)
        guard descriptor >= 0 else { throw NomacError("could not write file: \(String(cString: strerror(errno)))", path: path) }
        var existing = stat()
        if stat(path, &existing) == 0 { fchmod(descriptor, existing.st_mode & 0o7777) }
        let written = data.withUnsafeBytes { buffer -> Bool in
            var offset = 0
            while offset < buffer.count {
                let count = Glibc.write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { return false }
                offset += count
            }
            return true
        }
        let failure = written ? nil : String(cString: strerror(errno))
        close(descriptor)
        guard failure == nil, rename(temporary, path) == 0 else {
            let message = failure ?? String(cString: strerror(errno))
            unlink(temporary)
            throw NomacError("could not write file: \(message)", path: path)
        }
        #else
        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            throw NomacError("could not write file: \(error.localizedDescription)", path: path)
        }
        #endif
    }

    /// Returns the absolute, standardized form of `path`, resolved against the current directory.
    public static func absolute(_ path: String) -> String {
        let url: URL
        if path.hasPrefix("/") {
            url = URL(fileURLWithPath: path)
        } else {
            url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(path)
        }
        return url.standardizedFileURL.path
    }

    /// A path as xcodebuild spells it: absolute, with `/private/tmp` spelled `/tmp`, for
    /// `-derivedDataPath` (`-showBuildSettings -derivedDataPath /private/tmp/D` prints
    /// `BUILD_DIR = /tmp/D/Build/Products`; retro-rampage's dSYM relocation maps name `/tmp/…` for a
    /// build given `/private/tmp/…`) and in its build log, sources included.
    public static func xcodebuildSpelling(_ path: String) -> String {
        let absolute = absolute(path)
        return absolute == "/private/tmp" || absolute.hasPrefix("/private/tmp/") ? String(absolute.dropFirst("/private".count)) : absolute
    }

    /// The absolute path of a project or workspace as Xcode spells it: decomposed, whatever
    /// the form on disk or on the command line (``Swift/String/decomposed``).
    public static func xcodePath(_ path: String) -> String {
        absolute(path).decomposed
    }

    /// Returns `path` with every symbolic link in it resolved, or `path` itself if it does not exist.
    public static func resolvingSymbolicLinks(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Lists the entries of a directory sorted by name, so iteration order is deterministic.
    public static func sortedContents(of path: String) throws -> [String] {
        do {
            return try contentsOfDirectory(path).sorted()
        } catch {
            throw NomacError("could not list directory: \(error.localizedDescription)", path: path)
        }
    }
}

extension String {
    /// The string in Unicode normalization form D. macOS hands Xcode the paths and names it
    /// reads from the file system in this form, which Xcode keeps: the project and workspace
    /// paths and names, and the items of synchronized folders, are decomposed in its PIF and
    /// settings whatever their form on disk (loader-experiments `unicode-nfc`, `unicode-nfd`).
    public var decomposed: String {
        decomposedStringWithCanonicalMapping
    }

    /// Whether the two strings have the same bytes. Swift's `==` treats canonically equivalent
    /// strings as equal; Xcode's lookups by name mostly do not (docs/formats/pif.md "Unicode").
    public func isIdentical(to other: String) -> Bool {
        utf8.elementsEqual(other.utf8)
    }
}
