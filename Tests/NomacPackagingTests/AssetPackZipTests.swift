import Foundation
import NomacCore
import NomacTestSupport
import Testing
@testable import NomacPackaging

/// A hosted asset pack's zip, as Xcode 27.0's export writes it (signing experiments `odr` and
/// `odr-shapes`): an entry whose mode is not the standard 0644 or 0755 (a 0600 file, a link)
/// carries it in an "SZ" field before "UX"; a link's data is its target.
@Suite struct AssetPackZipTests {
    /// Each local header's name, extra field and data.
    static func localRecords(_ zip: [UInt8]) -> [String: (extra: [UInt8], data: [UInt8])] {
        var records: [String: (extra: [UInt8], data: [UInt8])] = [:]
        var offset = 0
        func u16(_ at: Int) -> Int { Int(zip[at]) | Int(zip[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        while zip.count >= offset + 30, zip[offset..<offset + 4] == [0x50, 0x4b, 0x03, 0x04] {
            let size = u32(offset + 18), nameLength = u16(offset + 26), extraLength = u16(offset + 28)
            let name = String(decoding: zip[offset + 30..<offset + 30 + nameLength], as: UTF8.self)
            let extraStart = offset + 30 + nameLength
            records[name] = (Array(zip[extraStart..<extraStart + extraLength]), Array(zip[extraStart + extraLength..<extraStart + extraLength + size]))
            offset = extraStart + extraLength + size
        }
        return records
    }

    @Test func modesOtherThanTheStandardOnesAndLinks() throws {
        let directory = try TemporaryDirectory()
        let pack = directory.path + "/org.nomac.level1.assetpack"
        try FileSystem.createDirectory(pack)
        try FileSystem.write(Data("level1\n".utf8), to: pack + "/level1.txt")
        try FileSystem.write(Data("private\n".utf8), to: pack + "/private.txt")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: pack + "/level1.txt")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: pack + "/private.txt")
        try FileManager.default.createSymbolicLink(atPath: pack + "/link.txt", withDestinationPath: "level1.txt")
        try AssetPackZip.write(pack: pack, to: directory.path + "/pack.zip")
        let records = Self.localRecords([UInt8](FileManager.default.contents(atPath: directory.path + "/pack.zip")!))
        #expect(records["level1.txt"]?.extra.prefix(2) == [0x55, 0x58])
        #expect(records["private.txt"]?.extra.prefix(6) == [0x53, 0x5a, 2, 0, 0x80, 0x81])
        #expect(records["link.txt"]?.extra.prefix(4) == [0x53, 0x5a, 2, 0])
        #expect(records["link.txt"]?.data == Array("level1.txt".utf8))
    }
}
