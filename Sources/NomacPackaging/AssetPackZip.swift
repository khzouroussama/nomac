import Foundation
import NomacCore
import NomacPlist

/// The zip of a signed asset pack that an export with `onDemandResourcesAssetPacksBaseURL` puts
/// beside the IPA (`odr` experiment; docs/formats/ipa.md "On-demand resources"): stored entries
/// with their sizes and CRC in the local header, `META-INF/` and
/// `META-INF/com.apple.ZipMetadata.plist` first (dated 1980-01-01), then the pack's contents in
/// ditto's order. Each local header has the "UX" field (access and modification times, owner
/// ids; the user's id twice for `META-INF`), the central directory the times only for a file
/// whose access time is not its modification time; an entry of another mode than the standard
/// ones (a file not 0644, a link, whose target is its data) has its mode in an "SZ" field first.
/// Every name but the metadata's has the UTF-8 flag; version made by 0x031e, needed 20.
enum AssetPackZip {
    static func write(pack: String, to path: String) throws {
        let entries = try DittoArchive.entries(of: pack)
        // Folders of another mode than the metadata's standard one are not observed.
        guard entries.allSatisfy({ entry in
            if case .directory = entry.kind { entry.mode == 0o40755 } else { true }
        }) else {
            throw NomacError("exportArchive asset packs with folders of modes other than 0755 are not supported yet (BACKLOG B-312)", path: pack,
                             exitStatus: 70)
        }
        var records: [Record] = []
        var total = 0
        for entry in entries {
            var data: [UInt8] = []
            switch entry.kind {
            case .file(let file):
                guard let contents = FileManager.default.contents(atPath: file) else { throw NomacError("could not read file", path: file) }
                data = [UInt8](contents)
            case .symbolicLink(let target):
                data = Array(target.utf8)
            case .directory:
                break
            }
            total += data.count
            let (time, date) = DOSTime.of(entry.modificationTime, in: .current)
            records.append(Record(name: entry.name, unicode: true, time: time, date: date, data: data, mode: entry.mode,
                                  times: (entry.accessTime, entry.modificationTime), owners: (entry.userID, entry.groupID)))
        }
        let user = UInt32(getuid())
        // The metadata's five keys come in this order (observed); the modes are 16-bit, sign
        // extended (0o100644 is -32348); equal integers are one object.
        let keys = ["StandardDirectoryPerms", "Version", "TotalUncompressedBytes", "RecordCount", "StandardFilePerms"]
        let values = [0o40755, 2, total, entries.count, Int(Int16(bitPattern: UInt16(0o100644)))]
        var objects: [BinaryPropertyList.Object] = [.dictionary(keys: [], values: [])] + keys.map { .string($0) }
        var references: [Int] = [], shared: [Int: Int] = [:]
        for value in values {
            if shared[value] == nil {
                shared[value] = objects.count
                objects.append(.integer(value))
            }
            references.append(shared[value]!)
        }
        objects[0] = .dictionary(keys: Array(1...keys.count), values: references)
        let metadata = BinaryPropertyList.data(objects: objects)
        records.insert(contentsOf: [
            Record(name: "META-INF/", unicode: true, time: 0, date: 0x21, data: [], mode: 0o40755, times: (0, 0), owners: (user, user)),
            Record(name: "META-INF/com.apple.ZipMetadata.plist", unicode: false, time: 0, date: 0x21, data: [UInt8](metadata), mode: 0o100644,
                   times: (0, 0), owners: (user, user)),
        ], at: 0)

        var archive: [UInt8] = [], central: [UInt8] = []
        for record in records {
            let name = Array(record.name.utf8)
            let crc = Zlib.crc32(Data(record.data))
            let times = LittleEndian.u32(UInt32(truncatingIfNeeded: record.times.access)) + LittleEndian.u32(UInt32(truncatingIfNeeded: record.times.modification))
            // An entry whose mode is not the metadata's standard one (a file not 0644, a link)
            // carries it in an "SZ" field (0x5a53) before "UX" (signing experiments `odr-shapes`).
            let standard = [UInt32(0o40755), 0o100644].contains(record.mode)
            let modeExtra: [UInt8] = standard ? [] : [0x53, 0x5a, 2, 0] + LittleEndian.u16(UInt16(truncatingIfNeeded: record.mode))
            let localExtra = modeExtra + [0x55, 0x58, 12, 0] + times + LittleEndian.u16(UInt16(truncatingIfNeeded: record.owners.user))
                + LittleEndian.u16(UInt16(truncatingIfNeeded: record.owners.group))
            let centralExtra: [UInt8] = record.times.access == record.times.modification ? [] : [0x55, 0x58, 8, 0] + times
            let flags: UInt16 = record.unicode ? 0x800 : 0
            let common = LittleEndian.u16(flags) + LittleEndian.u16(0) + LittleEndian.u16(record.time) + LittleEndian.u16(record.date)
                + LittleEndian.u32(crc) + LittleEndian.u32(UInt32(record.data.count)) + LittleEndian.u32(UInt32(record.data.count))
            central += [0x50, 0x4b, 0x01, 0x02] + LittleEndian.u16(0x031e) + LittleEndian.u16(20) + common
            central += LittleEndian.u16(UInt16(name.count)) + LittleEndian.u16(UInt16(centralExtra.count)) + LittleEndian.u16(0) + LittleEndian.u16(0)
            central += LittleEndian.u16(0) + LittleEndian.u32(record.mode << 16 | 0x4000) + LittleEndian.u32(UInt32(archive.count)) + name + centralExtra
            archive += [0x50, 0x4b, 0x03, 0x04] + LittleEndian.u16(20) + common
            archive += LittleEndian.u16(UInt16(name.count)) + LittleEndian.u16(UInt16(localExtra.count)) + name + localExtra + record.data
        }
        guard archive.count + central.count <= UInt32.max, records.count <= UInt16.max else {
            throw NomacError("archives that need Zip64 are not supported (BACKLOG B-306)", path: pack)
        }
        let start = archive.count
        archive += central + [0x50, 0x4b, 0x05, 0x06, 0, 0, 0, 0] + LittleEndian.u16(UInt16(records.count)) + LittleEndian.u16(UInt16(records.count))
        archive += LittleEndian.u32(UInt32(central.count)) + LittleEndian.u32(UInt32(start)) + LittleEndian.u16(0)
        try FileSystem.write(Data(archive), to: path)
    }

    private struct Record {
        var name: String
        var unicode: Bool
        var time: UInt16
        var date: UInt16
        var data: [UInt8]
        var mode: UInt32
        var times: (access: Int, modification: Int)
        var owners: (user: UInt32, group: UInt32)
    }
}
