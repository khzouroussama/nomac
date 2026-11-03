import Foundation
import NomacCore
import NomacTestSupport
import Testing
@testable import NomacPackaging

/// `DittoArchive` writes what `ditto -c -k --norsrc` wrote for the same self-written folder: the
/// expected digest is that of ditto's archive, made with `TZ=UTC` by the user 501, group 20.
/// On a Mac, `NOMAC_PACKAGING_OBSERVE=<dir>` makes the test archive the folder with ditto first
/// (`<dir>/ditto.zip`), before anything reads the files and changes their access times.
@Suite struct DittoArchiveTests {
    /// Folders, an empty file, a symbolic link, NFC and NFD names, compressible text and
    /// incompressible bytes, with fixed access and modification times (odd and even seconds, and
    /// 23:59:59 UTC for `late.txt`); returns the folder and the times by archive entry name.
    static func folder(in directory: URL) throws -> (URL, [String: (access: Int, modification: Int)]) {
        let root = directory.appendingPathComponent("Root")
        var noise: UInt32 = 1
        let incompressible = (0..<70_000).map { _ -> UInt8 in
            noise = noise &* 1_664_525 &+ 1_013_904_223
            return UInt8(truncatingIfNeeded: noise >> 24)
        }
        let files: [(String, [UInt8])] = [
            ("Payload/Foo.app/a.txt", Array("hello\n".utf8)),
            ("Payload/Foo.app/empty", []),
            // Foundation on Apple platforms writes file names decomposed; elsewhere as given.
            ("Payload/Foo.app/\u{e9}-nfc.txt".decomposedStringWithCanonicalMapping, Array("x".utf8)),
            ("Payload/Foo.app/e\u{301}-nfd.txt", Array("y".utf8)),
            ("Payload/Foo.app/big.txt", Array(String(repeating: "abc", count: 50_000).utf8)),
            ("Payload/Foo.app/random.bin", incompressible),
            ("Payload/Foo.app/Sub/b.txt", Array("b".utf8)),
            ("Payload/Foo.app/late.txt", Array("late".utf8)),
            ("Symbols/x.symbols", Array("s".utf8)),
        ]
        for (path, bytes) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(bytes).write(to: url)
        }
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("Payload/Foo.app/link").path, withDestinationPath: "a.txt")
        let paths = files.map(\.0) + ["Payload/Foo.app/link", "Payload/Foo.app/Sub", "Payload/Foo.app", "Payload", "Symbols"]
        var times: [String: (access: Int, modification: Int)] = [:]
        for (index, path) in paths.enumerated() {
            let url = root.appendingPathComponent(path)
            let isDirectory = FileSystem.isDirectory(url.path)
            if !path.hasSuffix("link") {
                try FileManager.default.setAttributes([.posixPermissions: isDirectory ? 0o755 : 0o644], ofItemAtPath: url.path)
            }
            let access = 1_767_323_045 + index
            let modification = path.hasSuffix("late.txt") ? 1_767_398_399 : 1_767_323_045 + 2 * index
            var values = [timeval(tv_sec: access, tv_usec: 0), timeval(tv_sec: modification, tv_usec: 0)]
            #expect(lutimes(url.path, &values) == 0)
            times[path + (isDirectory && !path.hasSuffix("link") ? "/" : "")] = (access, modification)
        }
        return (root, times)
    }

    @Test func writesWhatDittoWrites() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-zip")
        let directory = URL(fileURLWithPath: temporary.path)
        let (root, times) = try Self.folder(in: directory)
        if let observe = ProcessInfo.processInfo.environment["NOMAC_PACKAGING_OBSERVE"] {
            try FileManager.default.createDirectory(atPath: observe, withIntermediateDirectories: true)
            _ = try Subprocess.run("/usr/bin/ditto", ["-c", "-k", "--norsrc", root.path, observe + "/ditto.zip"], environment: ["TZ": "UTC"])
        }
        let entries = try DittoArchive.entries(of: root.path).map { entry in
            var entry = entry
            entry.userID = 501
            entry.groupID = 20
            (entry.accessTime, entry.modificationTime) = times[entry.name]!
            return entry
        }
        #expect(entries.map(\.name) == [
            "Payload/", "Payload/Foo.app/", "Payload/Foo.app/\u{e9}-nfc.txt", "Payload/Foo.app/e\u{301}-nfd.txt", "Payload/Foo.app/empty",
            "Payload/Foo.app/big.txt", "Payload/Foo.app/Sub/", "Payload/Foo.app/Sub/b.txt", "Payload/Foo.app/link", "Payload/Foo.app/a.txt",
            "Payload/Foo.app/late.txt", "Payload/Foo.app/random.bin", "Symbols/", "Symbols/x.symbols",
        ])
        let archive = directory.appendingPathComponent("out.zip")
        try DittoArchive.write(entries, to: archive.path, timeZone: TimeZone(identifier: "UTC")!)
        let digest = SHA256.digest([UInt8](try Data(contentsOf: archive))).map { String(format: "%02x", $0) }.joined()
        #expect(digest == "512027ba938c879a9fa38e9b27508b83f1dbe2bc446bb1ce92e596a7fdae81a2")
    }

    /// The entry count field holds 0xffff for Zip64; nomac stops before writing it (B-306).
    @Test func stopsWhereZip64WouldStart() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-zip")
        let entries = (0..<65_535).map { DittoArchive.Entry(name: "d\($0)/", kind: .directory, mode: 0o40755, accessTime: 0, modificationTime: 0,
                                                             userID: 0, groupID: 0) }
        #expect(throws: NomacError("archives that need Zip64 are not supported (BACKLOG B-306)", path: "d65534/")) {
            try DittoArchive.write(entries, to: temporary.path + "/out.zip", timeZone: TimeZone(identifier: "UTC")!)
        }
    }

    @Test func roundsOddSecondsUp() {
        let utc = TimeZone(identifier: "UTC")!
        // 2026-01-02 03:04:05 and :06 UTC.
        #expect(DOSTime.of(1_767_323_045, in: utc) == (0x1883, 0x5c22))
        #expect(DOSTime.of(1_767_323_046, in: utc) == (0x1883, 0x5c22))
        // 23:59:59 rounds into the next day (as ditto wrote `late.txt` in writesWhatDittoWrites).
        #expect(DOSTime.of(1_767_398_399, in: utc) == (0, 0x5c23))
    }
}
