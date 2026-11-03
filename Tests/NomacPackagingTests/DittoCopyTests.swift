import Foundation
import Testing
@testable import NomacPackaging
import NomacCore
import NomacTestSupport

/// macOS 27.0.1's `ditto <source> <destination>` in each case of `.github/scripts/ditto_experiments.py`.
@Suite struct DittoCopyTests {
    private static let sourceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func file(_ path: String, _ contents: String, mode: Int = 0o644) throws {
        try FileSystem.write(Data(contents.utf8), to: path)
        try FileManager.default.setAttributes([.posixPermissions: mode, .modificationDate: Self.sourceDate], ofItemAtPath: path)
    }

    private func contents(_ path: String) -> String? {
        FileManager.default.contents(atPath: path).map { String(decoding: $0, as: UTF8.self) }
    }

    private func mode(_ path: String) throws -> Int {
        try (FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    private func keepsTime(_ path: String) throws -> Bool {
        try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date == Self.sourceDate
    }

    @Test func aFileGoesToItsPathInNewFoldersWithItsModeAndTime() throws {
        let tmp = try TemporaryDirectory()
        try file(tmp.path + "/src/A-Swift.h", "header\n", mode: 0o640)
        try DittoCopy.copy(tmp.path + "/src/A-Swift.h", to: tmp.path + "/out/x/y/A-Swift.h")
        #expect(contents(tmp.path + "/out/x/y/A-Swift.h") == "header\n")
        #expect(try mode(tmp.path + "/out/x/y/A-Swift.h") == 0o640)
        #expect(try keepsTime(tmp.path + "/out/x/y/A-Swift.h"))
        #expect(FileSystem.isDirectory(tmp.path + "/out/x/y"))
    }

    @Test func aFileReplacesAFileAndGoesIntoAFolder() throws {
        let tmp = try TemporaryDirectory()
        try file(tmp.path + "/src/a.modulemap", "module A {}\n")
        try FileSystem.write(Data("old, longer contents\n".utf8), to: tmp.path + "/out/a.modulemap")
        try DittoCopy.copy(tmp.path + "/src/a.modulemap", to: tmp.path + "/out/a.modulemap")
        #expect(contents(tmp.path + "/out/a.modulemap") == "module A {}\n")
        try file(tmp.path + "/src/a.h", "a\n", mode: 0o640)
        try FileSystem.write(Data("keep\n".utf8), to: tmp.path + "/folder/keep.txt")
        try DittoCopy.copy(tmp.path + "/src/a.h", to: tmp.path + "/folder")
        #expect(contents(tmp.path + "/folder/a.h") == "a\n")
        #expect(contents(tmp.path + "/folder/keep.txt") == "keep\n")
    }

    @Test func aFolderMergesWithItsLinksAndEmptyFolders() throws {
        let tmp = try TemporaryDirectory()
        try file(tmp.path + "/src/d/a.h", "new a\n", mode: 0o640)
        try file(tmp.path + "/src/d/sub/b.txt", "b\n")
        try FileManager.default.createSymbolicLink(atPath: tmp.path + "/src/d/link", withDestinationPath: "a.h")
        try FileManager.default.createDirectory(atPath: tmp.path + "/src/d/empty", withIntermediateDirectories: true)
        try FileSystem.write(Data("old a\n".utf8), to: tmp.path + "/out/d/a.h")
        try FileSystem.write(Data("kept\n".utf8), to: tmp.path + "/out/d/c.txt")
        try DittoCopy.copy(tmp.path + "/src/d", to: tmp.path + "/out/d")
        #expect(contents(tmp.path + "/out/d/a.h") == "new a\n")
        #expect(try mode(tmp.path + "/out/d/a.h") == 0o640)
        #expect(contents(tmp.path + "/out/d/sub/b.txt") == "b\n")
        #expect(contents(tmp.path + "/out/d/c.txt") == "kept\n")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: tmp.path + "/out/d/link") == "a.h")
        #expect(FileSystem.isDirectory(tmp.path + "/out/d/empty"))
    }

    @Test func aLinkGivenAsTheSourceIsFollowed() throws {
        let tmp = try TemporaryDirectory()
        try file(tmp.path + "/src/real.h", "r\n", mode: 0o640)
        try FileManager.default.createSymbolicLink(atPath: tmp.path + "/src/alias.h", withDestinationPath: "real.h")
        try DittoCopy.copy(tmp.path + "/src/alias.h", to: tmp.path + "/out/alias.h")
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: tmp.path + "/out/alias.h")) == nil)
        #expect(contents(tmp.path + "/out/alias.h") == "r\n")
        #expect(try mode(tmp.path + "/out/alias.h") == 0o640)
    }
}
