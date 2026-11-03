import Foundation
import NomacCore

/// HEIC image set entries (docs/formats/asset-catalog.md, "HEIC images"; `heic` experiment):
/// actool stores the decoded pixels, and the file as ImageIO writes it again for target 2.
/// nomac decodes with libheif's `heif-dec` (HEVC decoding is exact by the standard; the color
/// steps are nomac's, ADR 0204) and rewrites the container itself.
enum HEICImage {
    static func unsupported(_ what: String, path: String) -> NomacError {
        NomacError("HEIC images with \(what) are not supported yet (BACKLOG B-200)", path: path)
    }

    /// The image's pixels, decoded by `heif-dec` into a PNG nomac reads.
    static func decode(_ path: String) throws -> PNGImage {
        let search = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin").split(separator: ":") + ["/opt/homebrew/bin", "/usr/local/bin"]
        guard let tool = search.map({ "\($0)/heif-dec" }).first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw NomacError("HEIC images need libheif's heif-dec (Ubuntu: libheif-examples, Homebrew: libheif)", path: path)
        }
        let output = NSTemporaryDirectory() + "/nomac-heic-\(UUID().uuidString).png"
        defer { try? FileManager.default.removeItem(atPath: output) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = ["--quiet", path, output]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: output) else {
            throw NomacError("heif-dec could not decode the image (status \(process.terminationStatus))", path: path)
        }
        return try PNGImage(contentsOf: output)
    }

    /// The decoded pixels as actool stores them for an opaque image: 1-5-5-5 RGB, little-endian.
    static func rgb555(_ bgra: [UInt8]) -> [UInt8] {
        stride(from: 0, to: bgra.count, by: 4).flatMap { i -> [UInt8] in
            func five(_ value: UInt8) -> UInt16 { (UInt16(value) * 31 + 127) / 255 }
            let pixel = five(bgra[i + 2]) << 10 | five(bgra[i + 1]) << 5 | five(bgra[i])
            return [UInt8(pixel & 0xFF), UInt8(pixel >> 8)]
        }
    }

    struct Box {
        var type: String
        var body: [UInt8]
    }

    static func be16(_ bytes: [UInt8], _ at: Int) -> Int { Int(bytes[at]) << 8 | Int(bytes[at + 1]) }
    static func be32(_ bytes: [UInt8], _ at: Int) -> Int { be16(bytes, at) << 16 | be16(bytes, at + 2) }
    static func bytes16(_ value: Int) -> [UInt8] { [UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)] }
    static func bytes32(_ value: Int) -> [UInt8] { bytes16(value >> 16) + bytes16(value & 0xFFFF) }

    static func boxes(_ bytes: [UInt8], from start: Int = 0, to end: Int? = nil, path: String) throws -> [Box] {
        var out: [Box] = []
        var at = start
        let end = end ?? bytes.count
        while at < end {
            guard at + 8 <= end else { throw unsupported("a truncated box", path: path) }
            var size = be32(bytes, at), header = 8
            if size == 1 {
                guard at + 16 <= end else { throw unsupported("a truncated box", path: path) }
                size = be32(bytes, at + 8) << 32 | be32(bytes, at + 12)
                header = 16
            }
            guard size >= header, at + size <= end else { throw unsupported("a malformed box", path: path) }
            out.append(Box(type: String(decoding: bytes[at + 4..<at + 8], as: UTF8.self), body: Array(bytes[at + header..<at + size])))
            at += size
        }
        return out
    }

    static func box(_ type: String, _ body: [UInt8]) -> [UInt8] { bytes32(body.count + 8) + Array(type.utf8) + body }

    /// The file as ImageIO writes it again (`heic` experiment): the same items, an Exif item
    /// (rewritten, or added with a `cdsc` reference to the primary item) whose data comes first
    /// in a 64-bit `mdat`, and `ftyp` naming `heic` and `mif1` only when the image is under 64
    /// pixels on a side and the file names MIAF brands.
    /// `size`: the image's displayed size (after a `clap` crop), which the ftyp rule takes, and
    /// TileWidth and TileLength in a new Exif item (`heic` Odd case: 61 × 61 coded as 62 × 62); a
    /// rewritten Exif item takes the primary item's coded size (`ispe`) instead (pocket-casts'
    /// 834 × 855 mockup coded as 834 × 856).
    static func rewritten(_ bytes: [UInt8], size: (width: Int, height: Int), path: String) throws -> [UInt8] {
        let top = try boxes(bytes, path: path)
        guard top.map(\.type) == ["ftyp", "meta", "mdat"] else { throw unsupported("boxes \(top.map(\.type))", path: path) }
        let ftyp = top[0].body, metaBody = top[1].body, mdatStart = bytes.count - top[2].body.count
        let children = try boxes(metaBody, from: 4, path: path)
        let known = ["hdlr", "dinf", "pitm", "iinf", "iref", "iprp", "iloc"]
        guard children.allSatisfy({ known.contains($0.type) }), Set(children.map(\.type)).count == children.count,
              let pitm = children.first(where: { $0.type == "pitm" }), let iinf = children.first(where: { $0.type == "iinf" }),
              let iloc = children.first(where: { $0.type == "iloc" }) else {
            throw unsupported("meta boxes \(children.map(\.type))", path: path)
        }
        guard pitm.body.count == 6, pitm.body[0] == 0 else { throw unsupported("a pitm box of version \(pitm.body.first ?? 0)", path: path) }
        let primary = be16(pitm.body, 4)

        // Items: iinf version 0, infe version 2.
        guard iinf.body[0] == 0 else { throw unsupported("an iinf box of version \(iinf.body[0])", path: path) }
        let entries = try boxes(iinf.body, from: 6, path: path)
        guard entries.count == be16(iinf.body, 4), entries.allSatisfy({ $0.type == "infe" && $0.body.count >= 12 && $0.body[0] == 2 }) else {
            throw unsupported("item entries other than infe version 2", path: path)
        }
        let items = entries.map { (id: be16($0.body, 4), type: String(decoding: $0.body[8..<12], as: UTF8.self)) }
        let exifItem = items.first { $0.type == "Exif" }?.id

        // Locations: iloc version 0, 4-byte offsets and lengths, no base offset, one extent each.
        let locations = iloc.body
        guard locations.count >= 8, locations[0] == 0, locations[4] == 0x44, locations[5] == 0 else {
            throw unsupported("an iloc box other than version 0 with 4-byte offsets", path: path)
        }
        var extents: [(id: Int, reference: Int, offset: Int, length: Int)] = []
        var at = 8
        for _ in 0..<be16(locations, 6) {
            guard at + 14 <= locations.count, be16(locations, at + 4) == 1 else { throw unsupported("items of several extents", path: path) }
            extents.append((be16(locations, at), be16(locations, at + 2), be32(locations, at + 6), be32(locations, at + 10)))
            at += 14
        }
        guard extents.allSatisfy({ $0.reference == 0 && $0.offset >= mdatStart && $0.offset + $0.length <= bytes.count }) else {
            throw unsupported("item data outside mdat", path: path)
        }
        let (width, height) = size
        let iprpBody = children.first { $0.type == "iprp" }?.body ?? []

        // The Exif data: the file's rewritten, or a new one.
        let exif: [UInt8]
        if let exifItem, let extent = extents.first(where: { $0.id == exifItem }) {
            let coded = try primarySize(iprpBody, primary: primary, path: path)
            exif = try rewrittenExif(Array(bytes[extent.offset..<extent.offset + extent.length]), width: coded.0, height: coded.1, path: path)
        } else {
            exif = try rewrittenExif(nil, width: width, height: height, path: path)
        }
        let exifID = exifItem ?? (items.map(\.id).max() ?? 0) + 1

        var newIinf = iinf.body
        var newIref = children.first { $0.type == "iref" }?.body
        if exifItem == nil {
            // A hidden item (flag 1).
            let infe = [2, 0, 0, 1] + bytes16(exifID) + [0, 0] + Array("Exif".utf8) + [0]
            newIinf = Array(newIinf[0..<4]) + bytes16(entries.count + 1) + Array(newIinf[6...]) + box("infe", infe)
            let reference = box("cdsc", bytes16(exifID) + bytes16(1) + bytes16(primary))
            if let iref = newIref {
                guard iref[0] == 0 else { throw unsupported("an iref box of version \(iref[0])", path: path) }
                newIref = iref + reference
            } else {
                newIref = [0, 0, 0, 0] + reference
            }
        }

        // The data in mdat: the Exif item first, the others in the file's order.
        let ordered = [(id: exifID, data: exif)] + extents.filter { $0.id != exifID }.sorted { $0.offset < $1.offset }
            .map { (id: $0.id, data: Array(bytes[$0.offset..<$0.offset + $0.length])) }
        func locationBox(base: Int) -> [UInt8] {
            var offsets: [Int: (Int, Int)] = [:]
            var position = base
            for item in ordered {
                offsets[item.id] = (position, item.data.count)
                position += item.data.count
            }
            var body = Array(locations[0..<6]) + bytes16(extents.count + (exifItem == nil ? 1 : 0))
            for id in extents.map(\.id) + (exifItem == nil ? [exifID] : []) {
                body += bytes16(id) + bytes16(0) + bytes16(1) + bytes32(offsets[id]!.0) + bytes32(offsets[id]!.1)
            }
            return box("iloc", body)
        }
        let newProperties = try properties(children.first { $0.type == "iprp" }?.body ?? [], path: path)
        let brands = stride(from: 8, to: ftyp.count, by: 4).map { String(decoding: ftyp[$0..<$0 + 4], as: UTF8.self) }
        let newFtyp = brands.contains("miaf") && (width < 64 || height < 64) ? Array("heic".utf8) + [0, 0, 0, 0] + Array("heicmif1".utf8) : ftyp
        func meta(base: Int) -> [UInt8] {
            var body = Array(metaBody[0..<4])
            for child in children {
                switch child.type {
                case "iinf":
                    body += box("iinf", newIinf)
                    if let newIref, !children.contains(where: { $0.type == "iref" }) { body += box("iref", newIref) }
                case "iref": body += box("iref", newIref!)
                case "iloc": body += locationBox(base: base)
                case "iprp": body += box("iprp", newProperties)
                default: body += box(child.type, child.body)
                }
            }
            return box("meta", body)
        }
        let prefix = box("ftyp", newFtyp)
        let base = prefix.count + meta(base: 0).count + 16
        let data = ordered.flatMap(\.data)
        return prefix + meta(base: base) + [0, 0, 0, 1] + Array("mdat".utf8) + bytes32(0) + bytes32(data.count + 16) + data
    }

    /// The primary item's `ispe` size, through `ipma`.
    static func primarySize(_ iprp: [UInt8], primary: Int, path: String) throws -> (Int, Int) {
        let parts = try boxes(iprp, path: path)
        guard let ipco = parts.first(where: { $0.type == "ipco" }), let ipma = parts.first(where: { $0.type == "ipma" }), ipma.body.count >= 8 else {
            throw unsupported("no ipco or ipma", path: path)
        }
        let properties = try boxes(ipco.body, path: path)
        let wide = ipma.body[3] & 1 == 1
        var at = 8
        for _ in 0..<be32(ipma.body, 4) {
            guard at + 3 <= ipma.body.count else { break }
            let id = ipma.body[0] == 0 ? be16(ipma.body, at) : be32(ipma.body, at)
            at += ipma.body[0] == 0 ? 2 : 4
            let count = Int(ipma.body[at])
            at += 1
            for _ in 0..<count where at + (wide ? 2 : 1) <= ipma.body.count {
                let index = wide ? be16(ipma.body, at) & 0x7FFF : Int(ipma.body[at] & 0x7F)
                at += wide ? 2 : 1
                if id == primary, index >= 1, index <= properties.count, properties[index - 1].type == "ispe", properties[index - 1].body.count >= 12 {
                    return (be32(properties[index - 1].body, 4), be32(properties[index - 1].body, 8))
                }
            }
        }
        throw unsupported("no size for the primary item", path: path)
    }

    /// The item properties as ImageIO orders them (`heic` corpus cases): `ipco` with the codec
    /// configurations (`hvcC`) last, and each item's `ipma` associations by property, the
    /// transformative ones (`clap`, `irot`, `imir`) last.
    static func properties(_ iprp: [UInt8], path: String) throws -> [UInt8] {
        let parts = try boxes(iprp, path: path)
        guard parts.map(\.type) == ["ipco", "ipma"] else { throw unsupported("item properties \(parts.map(\.type))", path: path) }
        let properties = try boxes(parts[0].body, path: path), ipma = parts[1].body
        let order = properties.indices.filter { properties[$0].type != "hvcC" } + properties.indices.filter { properties[$0].type == "hvcC" }
        var newIndex: [Int: Int] = [:]
        for (position, old) in order.enumerated() { newIndex[old + 1] = position + 1 }
        guard ipma.count >= 8 else { throw unsupported("a truncated ipma box", path: path) }
        let version = ipma[0], wide = ipma[3] & 1 == 1
        var out = Array(ipma[0..<8]), at = 8
        for _ in 0..<be32(ipma, 4) {
            let idBytes = version == 0 ? 2 : 4
            guard at + idBytes + 1 <= ipma.count else { throw unsupported("a truncated ipma box", path: path) }
            out += ipma[at..<at + idBytes + 1]
            let count = Int(ipma[at + idBytes])
            at += idBytes + 1
            var associations: [(index: Int, essential: Bool)] = []
            for _ in 0..<count {
                guard at + (wide ? 2 : 1) <= ipma.count else { throw unsupported("a truncated ipma box", path: path) }
                let value = wide ? be16(ipma, at) : Int(ipma[at])
                let index = value & (wide ? 0x7FFF : 0x7F)
                guard let mapped = newIndex[index] else { throw unsupported("a property index out of range", path: path) }
                associations.append((mapped, value & (wide ? 0x8000 : 0x80) != 0))
                at += wide ? 2 : 1
            }
            func transformative(_ index: Int) -> Bool { ["clap", "irot", "imir"].contains(properties[order[index - 1]].type) }
            associations.sort { (transformative($0.index) ? 1 : 0, $0.index) < (transformative($1.index) ? 1 : 0, $1.index) }
            for association in associations {
                out += wide ? bytes16(association.index | (association.essential ? 0x8000 : 0)) : [UInt8(association.index | (association.essential ? 0x80 : 0))]
            }
        }
        return box("ipco", order.flatMap { box(properties[$0].type, properties[$0].body) }) + box("ipma", out)
    }

    /// ImageIO's Exif: the file's first directory (big-endian, without sub-directories) with
    /// Orientation 1 added when missing and TileWidth and TileLength the image's size, in tag
    /// order, values that do not fit in their entry after the directory (`heic` experiment).
    static func rewrittenExif(_ data: [UInt8]?, width: Int, height: Int, path: String) throws -> [UInt8] {
        var entries: [(tag: Int, type: Int, count: Int, value: [UInt8])] = []
        let sizes = [1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, 12: 8]
        if let data {
            guard data.count >= 4 else { throw unsupported("a truncated Exif item", path: path) }
            let tiff = 4 + be32(data, 0)
            guard tiff + 8 <= data.count, Array(data[tiff - 6..<tiff]) == Array("Exif".utf8) + [0, 0], data[tiff] == 0x4D, data[tiff + 1] == 0x4D else {
                throw unsupported("Exif other than big-endian TIFF", path: path)
            }
            let t = Array(data[tiff...])
            let directory = be32(t, 4)
            guard directory + 2 <= t.count else { throw unsupported("a truncated Exif directory", path: path) }
            let count = be16(t, directory)
            guard directory + 2 + 12 * count + 4 <= t.count, be32(t, directory + 2 + 12 * count) == 0 else {
                throw unsupported("Exif with more than one directory", path: path)
            }
            for index in 0..<count {
                let at = directory + 2 + 12 * index
                let tag = be16(t, at), type = be16(t, at + 2), values = be32(t, at + 4)
                guard let size = sizes[type], ![0x8769, 0x8825, 0xA005].contains(tag) else { throw unsupported("the Exif tag \(tag)", path: path) }
                let length = size * values
                let value = length <= 4 ? Array(t[at + 8..<at + 12]) : (be32(t, at + 8) + length <= t.count ? Array(t[be32(t, at + 8)..<be32(t, at + 8) + length]) : [])
                guard length <= 4 || value.count == length else { throw unsupported("truncated Exif values", path: path) }
                entries.append((tag, type, values, value))
            }
        }
        if !entries.contains(where: { $0.tag == 0x112 }) { entries.append((0x112, 3, 1, [0, 1, 0, 0])) }
        entries.removeAll { $0.tag == 0x142 || $0.tag == 0x143 }
        entries += [(0x142, 4, 1, bytes32(width)), (0x143, 4, 1, bytes32(height))]
        entries.sort { $0.tag < $1.tag }
        var directory = bytes16(entries.count), values: [UInt8] = []
        let valuesStart = 8 + 2 + 12 * entries.count + 4
        for entry in entries {
            directory += bytes16(entry.tag) + bytes16(entry.type) + bytes32(entry.count)
            if entry.value.count <= 4 {
                directory += entry.value + [UInt8](repeating: 0, count: 4 - entry.value.count)
            } else {
                directory += bytes32(valuesStart + values.count)
                values += entry.value
            }
        }
        let tiff = Array("MM".utf8) + [0, 42] + bytes32(8) + directory + bytes32(0) + values
        return bytes32(6) + Array("Exif".utf8) + [0, 0] + tiff
    }
}
