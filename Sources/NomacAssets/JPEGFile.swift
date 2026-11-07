import NomacCore

/// JPEG images in image sets, which actool stores as files rather than pixels (pixel format
/// `JPEG`, docs/formats/asset-catalog.md "JPEG images"): their size, from the frame header, and
/// their bytes with the metadata ImageIO writes again.
struct JPEGFile {
    let width: Int
    let height: Int
    /// The file as actool stores it: every segment but the APPn ones other than JFIF's APP0, the
    /// Exif APP1 ImageIO writes (`JPEGMetadata`), the ICC profile's APP2 and Adobe's APP14, and
    /// but comments (`vector-images` jpeg cases: XMP, APP9, APP12, Photoshop's APP13 and COM are
    /// left out), the APPn ones first.
    let stored: [UInt8]

    init(_ bytes: [UInt8], path: String) throws {
        func malformed() -> NomacError { NomacError("malformed JPEG image", path: path) }
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { throw malformed() }
        var segments: [(marker: UInt8, range: Range<Int>)] = []
        var offset = 2
        var size: (Int, Int)?
        while true {
            guard offset + 4 <= bytes.count, bytes[offset] == 0xFF else { throw malformed() }
            let marker = bytes[offset + 1]
            let length = Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            guard length >= 2, offset + 2 + length <= bytes.count else { throw malformed() }
            let body = bytes[(offset + 4)..<(offset + 2 + length)]
            if (0xC0...0xCF).contains(marker), ![0xC4, 0xC8, 0xCC].contains(marker), body.count >= 5 {
                size = (Int(body[body.startIndex + 3]) << 8 | Int(body[body.startIndex + 4]), Int(body[body.startIndex + 1]) << 8 | Int(body[body.startIndex + 2]))
            }
            if marker == 0xDA {
                segments.append((marker, offset..<bytes.count))
                break
            }
            segments.append((marker, offset..<(offset + 2 + length)))
            offset += 2 + length
        }
        guard let size else { throw malformed() }
        (width, height) = size

        func body(_ range: Range<Int>) -> ArraySlice<UInt8> { bytes[(range.lowerBound + 4)..<range.upperBound] }
        let packets = segments.filter { $0.marker == 0xE1 && body($0.range).starts(with: JPEGMetadata.xmpPrefix) }
        let xmp = packets.last.map { Array(body($0.range).dropFirst(JPEGMetadata.xmpPrefix.count)) }
        let tiff = segments.first { $0.marker == 0xE1 && body($0.range).starts(with: Array("Exif\0".utf8)) }.map { Array(body($0.range).dropFirst(6)) }

        var applications: [(marker: UInt8, bytes: [UInt8])] = []
        if tiff != nil || xmp != nil, let exif = try JPEGMetadata.exif(tiff ?? [], xmp: xmp, path: path) {
            applications.append((0xE1, exif))
        }
        var others: [UInt8] = []
        for segment in segments {
            switch segment.marker {
            case 0xED:
                if JPEGMetadata.photoshopIsRewritten(body(segment.range), hasXMP: xmp != nil) { throw JPEGMetadata.refusal("IPTC metadata", path: path) }
            case 0xE1, 0xE3...0xEC, 0xEF, 0xFE: break
            case 0xE0, 0xE2, 0xEE: applications.append((segment.marker, Array(bytes[segment.range])))
            default: others += bytes[segment.range]
            }
        }
        // The kept APPn segments come first, in marker order (the corpus's JPEGs with their ICC
        // profile before their Exif get them the other way round).
        let ordered = applications.enumerated().sorted { ($0.element.marker, $0.offset) < ($1.element.marker, $1.offset) }.flatMap { $0.element.bytes }
        stored = [0xFF, 0xD8] + ordered + others
    }
}

/// The Exif segment ImageIO writes for a JPEG's metadata (`assets-experiments jpeg-exif`, and the
/// 110 image set JPEGs of the corpus, the holdout and the sweep): not the input's segment but a
/// new one from what it could read, big-endian, each directory's tags in ascending order and
/// their out-of-line values after it in that order, each padded to even: IFD0, the Exif
/// directory, a thumbnail's directory and the thumbnail.
enum JPEGMetadata {
    static let xmpPrefix = Array("http://ns.adobe.com/xap/1.0/\0".utf8)

    static func refusal(_ what: String, path: String) -> NomacError {
        NomacError("JPEG images with \(what) that ImageIO rewrites are not supported yet (BACKLOG B-200)", path: path)
    }

    /// One tag's accepted form. Any other type or count leaves the tag out; so do all tags not in
    /// `firstDirectory` and `exifDirectory` (every tag and type tried; GPS, Interop, CFAPattern
    /// and other maker notes are gone).
    private enum Kind {
        case short, shorts, twoShorts, twoShortsCountedOne, long, longOrShort, orientation, transfer
        case rational, rationals(Int), rationalsAsFloat(of: Int), signedRational
        case text, date, offsetTime, uniqueID, undefined(Int), comment, makerNote
    }

    private static let firstDirectory: [Int: Kind] = [
        0x0106: .short, 0x010D: .text, 0x010E: .text, 0x010F: .text, 0x0110: .text, 0x0112: .orientation, 0x011A: .rational, 0x011B: .rational,
        0x011E: .rational, 0x011F: .rational, 0x0128: .short, 0x012D: .transfer, 0x0131: .text, 0x0132: .date, 0x013B: .text, 0x013C: .text,
        0x013E: .rationalsAsFloat(of: 2), 0x013F: .rationalsAsFloat(of: 6), 0x0142: .longOrShort, 0x0143: .longOrShort, 0x8298: .text,
    ]

    private static let exifDirectory: [Int: Kind] = [
        0x829A: .rational, 0x829D: .rational, 0x8822: .short, 0x8824: .text, 0x8827: .shorts, 0x8830: .short, 0x8831: .long, 0x8832: .long,
        0x8833: .long, 0x8834: .long, 0x8835: .long, 0x9000: .undefined(4), 0x9003: .date, 0x9004: .date, 0x9010: .offsetTime, 0x9011: .offsetTime,
        0x9012: .offsetTime, 0x9101: .undefined(4), 0x9102: .rational, 0x9201: .signedRational, 0x9202: .rational, 0x9203: .signedRational,
        0x9204: .signedRational, 0x9205: .rational, 0x9206: .rational, 0x9207: .short, 0x9208: .short, 0x9209: .short, 0x920A: .rational,
        0x9214: .shorts, 0x927C: .makerNote, 0x9286: .comment, 0x9290: .text, 0x9291: .text, 0x9292: .text, 0xA000: .undefined(4), 0xA001: .short,
        0xA002: .longOrShort, 0xA003: .longOrShort, 0xA20B: .rational, 0xA20E: .rational, 0xA20F: .rational, 0xA210: .short,
        0xA214: .twoShortsCountedOne, 0xA215: .rational, 0xA217: .short, 0xA300: .undefined(1), 0xA301: .undefined(1), 0xA401: .short, 0xA402: .short,
        0xA403: .short, 0xA404: .rational, 0xA405: .short, 0xA406: .short, 0xA407: .short, 0xA408: .short, 0xA409: .short, 0xA40A: .short,
        0xA40C: .short, 0xA420: .uniqueID, 0xA430: .text, 0xA431: .text, 0xA432: .rationals(4), 0xA433: .text, 0xA434: .text, 0xA435: .text,
        0xA460: .short, 0xA461: .twoShorts, 0xA500: .rational,
    ]

    private typealias Value = (type: Int, count: Int, bytes: [UInt8])

    private static func be16(_ value: Int) -> [UInt8] { [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)] }
    private static func be32(_ value: Int) -> [UInt8] { be16((value >> 16) & 0xFFFF) + be16(value & 0xFFFF) }

    /// The Exif APP1 segment, nil when ImageIO writes none: the first directory cannot be read or
    /// nothing is left. Only the file's first Exif segment counts. A segment past 65535 bytes is
    /// written all the same, its length field wrapped to 16 bits (`seg-65536`: 0, the file broken).
    static func exif(_ tiff: [UInt8], xmp: [UInt8]?, path: String) throws -> [UInt8]? {
        var tags: [Int: Value] = [:]
        var exif: [Int: Value] = [:]
        var thumbnail: ArraySlice<UInt8>?
        let reader = tiff.count >= 8 && (tiff.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) || tiff.starts(with: [0x49, 0x49, 0x2A, 0x00])) ? Reader(tiff) : nil
        if let reader, let first = reader.directory(reader.u32(4)) {
            tags = try collect(first.entries, firstDirectory, reader, path: path)
            for entry in first.entries where entry.tag == 0x8769 {
                exif = [:]
                if entry.type == 4, entry.count == 1, let raw = entry.raw, let directory = reader.directory(reader.u32(raw.startIndex)) {
                    exif = try collect(directory.entries, exifDirectory, reader, path: path)
                }
            }
            thumbnail = reader.thumbnail(next: first.next)
        }
        if let xmp { try merge(XMP(bytes: xmp), &tags, &exif, path: path) }
        // Description, software, date and artist are written only beside another first directory
        // tag (`alone-*`): on their own they go, with or without an Exif directory.
        if Set(tags.keys).isSubset(of: [0x010E, 0x0131, 0x0132, 0x013B]) { tags = [:] }
        if tags.isEmpty && exif.isEmpty { return nil }

        if !exif.isEmpty { tags[0x8769] = (4, 1, [0, 0, 0, 0]) }
        let exifOffset = 8 + size(tags)
        if !exif.isEmpty { tags[0x8769] = (4, 1, be32(exifOffset)) }
        let thumbnailOffset = exifOffset + (exif.isEmpty ? 0 : size(exif))
        var out: [UInt8] = Array("MM".utf8) + [0, 42, 0, 0, 0, 8] + layout(tags, at: 8, next: thumbnail == nil ? 0 : thumbnailOffset)
        if !exif.isEmpty { out += layout(exif, at: exifOffset, next: 0) }
        if let thumbnail {
            // The directory is new too: compression 6 and, from the first directory, the
            // orientation, resolutions and unit (`thumb-*`); the file's own values do not count.
            var directory: [Int: Value] = [0x0103: (3, 1, be16(6)), 0x0201: (4, 1, [0, 0, 0, 0]), 0x0202: (4, 1, be32(thumbnail.count))]
            for tag in [0x0112, 0x011A, 0x011B, 0x0128] { directory[tag] = tags[tag] }
            directory[0x0201] = (4, 1, be32(thumbnailOffset + size(directory)))
            out += layout(directory, at: thumbnailOffset, next: 0) + thumbnail
        }
        return [0xFF, 0xE1] + be16((out.count + 8) & 0xFFFF) + Array("Exif\0\0".utf8) + out
    }

    private static func size(_ tags: [Int: Value]) -> Int {
        2 + 12 * tags.count + 4 + tags.values.reduce(0) { $0 + ($1.bytes.count > 4 ? ($1.bytes.count + 1) & ~1 : 0) }
    }

    private static func layout(_ tags: [Int: Value], at offset: Int, next: Int) -> [UInt8] {
        var table = be16(tags.count)
        var values: [UInt8] = []
        let base = offset + 2 + 12 * tags.count + 4
        for (tag, value) in tags.sorted(by: { $0.key < $1.key }) {
            table += be16(tag) + be16(value.type) + be32(value.count)
            if value.bytes.count <= 4 {
                table += value.bytes + [UInt8](repeating: 0, count: 4 - value.bytes.count)
            } else {
                table += be32(base + values.count)
                values += value.bytes
                if value.bytes.count % 2 == 1 { values.append(0) }
            }
        }
        return table + be32(next) + values
    }

    private struct Entry {
        let tag: Int, type: Int, count: Int
        let raw: ArraySlice<UInt8>?
    }

    private struct Reader {
        let tiff: [UInt8]
        let little: Bool

        init(_ tiff: [UInt8]) {
            self.tiff = tiff
            little = tiff[0] == 0x49
        }

        func u16(_ o: Int) -> Int { little ? Int(tiff[o + 1]) << 8 | Int(tiff[o]) : Int(tiff[o]) << 8 | Int(tiff[o + 1]) }
        func u32(_ o: Int) -> Int { little ? u16(o + 2) << 16 | u16(o) : u16(o) << 16 | u16(o + 2) }

        /// A directory, nil when it does not fit or holds more than 254 entries (`dir-*`).
        func directory(_ offset: Int) -> (entries: [Entry], next: Int)? {
            guard offset + 2 <= tiff.count else { return nil }
            let count = u16(offset)
            guard count <= 254, offset + 2 + 12 * count <= tiff.count else { return nil }
            let widths = [1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, 12: 8]
            let entries = (0..<count).map { i -> Entry in
                let p = offset + 2 + 12 * i
                let type = u16(p + 2), number = u32(p + 4)
                let length = (widths[type] ?? 0) * number
                let start = length <= 4 ? p + 8 : u32(p + 8)
                return Entry(tag: u16(p), type: type, count: number, raw: start + length <= tiff.count ? tiff[start..<(start + length)] : nil)
            }
            let end = offset + 2 + 12 * count
            return (entries, end + 4 <= tiff.count ? u32(end) : 0)
        }

        /// The thumbnail: LONG offset and length that hold at least a start-of-image marker.
        func thumbnail(next: Int) -> ArraySlice<UInt8>? {
            guard next != 0, let directory = directory(next) else { return nil }
            func long(_ tag: Int) -> Int? {
                guard let entry = directory.entries.last(where: { $0.tag == tag }), entry.type == 4, entry.count == 1, let raw = entry.raw else { return nil }
                return u32(raw.startIndex)
            }
            guard let offset = long(0x0201), let length = long(0x0202), length >= 2, offset + length <= tiff.count, tiff[offset] == 0xFF, tiff[offset + 1] == 0xD8 else { return nil }
            return tiff[offset..<(offset + length)]
        }

        func shorts(_ raw: ArraySlice<UInt8>) -> [Int] { stride(from: raw.startIndex, to: raw.endIndex, by: 2).map(u16) }
        func longs(_ raw: ArraySlice<UInt8>) -> [Int] { stride(from: raw.startIndex, to: raw.endIndex, by: 4).map(u32) }
    }

    private static func collect(_ entries: [Entry], _ table: [Int: Kind], _ reader: Reader, path: String) throws -> [Int: Value] {
        var out: [Int: Value] = [:]
        for entry in entries {
            guard let kind = table[entry.tag] else { continue }
            // A repeated tag: the last one's value (`dup-tag`).
            if let value = try value(entry, kind, reader, path: path) {
                out[entry.tag] = value
            } else if out[entry.tag] != nil {
                throw refusal("a repeated tag whose last value is not readable", path: path)
            }
        }
        return out
    }

    private static func value(_ entry: Entry, _ kind: Kind, _ reader: Reader, path: String) throws -> Value? {
        guard let raw = entry.raw else { return nil }
        let shortOne = entry.type == 3 && entry.count == 1
        switch kind {
        case .orientation:
            guard shortOne else { return nil }
            let orientation = reader.shorts(raw)[0]
            return (3, 1, be16((1...8).contains(orientation) ? orientation : 1))
        case .short:
            return shortOne ? (3, 1, be16(reader.shorts(raw)[0])) : nil
        case .long:
            return entry.type == 4 && entry.count == 1 ? (4, 1, be32(reader.longs(raw)[0])) : nil
        case .longOrShort:
            guard entry.count == 1, entry.type == 3 || entry.type == 4 else { return nil }
            return (4, 1, be32(entry.type == 3 ? reader.shorts(raw)[0] : reader.longs(raw)[0]))
        case .shorts:
            // 40 stay, 41 go (`lengths`).
            guard entry.type == 3, (1...40).contains(entry.count) else { return nil }
            return (3, entry.count, reader.shorts(raw).flatMap(be16))
        case .twoShorts:
            return entry.type == 3 && entry.count == 2 ? (3, 2, reader.shorts(raw).flatMap(be16)) : nil
        case .twoShortsCountedOne:
            return entry.type == 3 && entry.count == 2 ? (3, 1, reader.shorts(raw).flatMap(be16)) : nil
        case .transfer:
            guard entry.type == 3, entry.count >= 1 else { return nil }
            guard entry.count == 1 else { throw refusal("a TransferFunction of several values", path: path) }
            return (3, 1, be16(reader.shorts(raw)[0]))
        case .rational:
            return entry.type == 5 && entry.count == 1 ? (5, 1, rationals(raw, reader)) : nil
        case .rationals(let count):
            return entry.type == 5 && entry.count == count ? (5, count, rationals(raw, reader)) : nil
        case .rationalsAsFloat(let count):
            guard entry.type == 5, entry.count == count else { return nil }
            // Count 1, all the values still there, each through a 32-bit float, stopping too when
            // the remainder is at most 1e-6 (4e-7 to 1.2e-6 fit the 21 values seen: 313/1000 comes
            // out 48320/154377, 64/100 out 16/25).
            let longs = reader.longs(raw)
            return (5, 1, stride(from: 0, to: longs.count, by: 2).flatMap { i -> [UInt8] in
                let (p, q) = fraction(Double(Float(longs[i + 1] == 0 ? 0 : Double(longs[i]) / Double(longs[i + 1]))), limit: 0xFFFF_FFFF, remainder: 1e-6)
                return be32(p) + be32(q)
            })
        case .signedRational:
            guard entry.type == 10, entry.count == 1 else { return nil }
            let longs = reader.longs(raw)
            let a = Int(Int32(truncatingIfNeeded: longs[0])), b = Int(Int32(truncatingIfNeeded: longs[1]))
            if b == Int(Int32.min) { return (10, 1, be32(0) + be32(1)) }
            let (p, q) = b == 0 ? (0, 1) : fraction(Double(abs(a)) / Double(abs(b)), limit: 0x7FFF_FFFF)
            return (10, 1, be32((a < 0) != (b < 0) ? -p : p) + be32(q))
        case .text, .date, .offsetTime, .uniqueID:
            guard entry.type == 2 else { return nil }
            let text = Array(raw.prefix { $0 != 0 })
            // A count of 10000 stays, 10001 goes (`lengths`); invalid UTF-8 goes, a NUL ends the text.
            guard !text.isEmpty, entry.count <= 10000, Array(String(decoding: text, as: UTF8.self).utf8) == text else { return nil }
            if case .date = kind, !matches(text[...], "dddd:dd:dd dd:dd:dd") { return nil }
            if case .offsetTime = kind, text.count != 6 { return nil }
            if case .uniqueID = kind, entry.count != 33 { return nil }
            return (2, text.count + 1, text + [0])
        case .undefined(let count):
            return entry.type == 7 && entry.count == count ? (7, count, Array(raw)) : nil
        case .comment:
            guard entry.type == 7 else { return nil }
            if raw.starts(with: Array("UNICODE\0".utf8)) { throw refusal("a UNICODE user comment", path: path) }
            return raw.starts(with: Array("ASCII\0\0\0".utf8)) && entry.count > 8 ? (7, entry.count, Array(raw)) : nil
        case .makerNote:
            if entry.type == 7, raw.starts(with: Array("Apple iOS\0".utf8)) { throw refusal("an Apple maker note", path: path) }
            return nil
        }
    }

    private static func rationals(_ raw: ArraySlice<UInt8>, _ reader: Reader) -> [UInt8] {
        let longs = reader.longs(raw)
        return stride(from: 0, to: longs.count, by: 2).flatMap { i -> [UInt8] in
            let (p, q) = longs[i + 1] == 0 ? (0, 1) : fraction(Double(longs[i]) / Double(longs[i + 1]), limit: 0xFFFF_FFFF)
            return be32(p) + be32(q)
        }
    }

    /// A rational's value as ImageIO writes it again: a double, then Euclid's algorithm on doubles
    /// with a fused multiply-subtract until a convergent is within 1e-9 of it, relative (4400 of
    /// 4400 random rationals: 4643856/1000000 comes out 274633/59139).
    static func fraction(_ x: Double, limit: Int, remainder: Double = 0) -> (Int, Int) {
        guard x != 0 else { return (0, 1) }
        var n = x, d = 1.0
        var (h0, h1, k0, k1) = (0, 1, 1, 0)
        while true {
            let t = (n / d).rounded(.down)
            let whole = Int(t)
            (h0, h1) = (h1, whole &* h1 &+ h0)
            (k0, k1) = (k1, whole &* k1 &+ k0)
            if abs(x - Double(h1) / Double(k1)) <= 1e-9 * x { break }
            let r = n.addingProduct(-t, d)
            if abs(r) <= remainder { break }
            (n, d) = (d, r)
        }
        return (min(h1, limit), min(k1, limit))
    }

    private static func matches(_ value: ArraySlice<UInt8>, _ pattern: String) -> Bool {
        let shape = Array(pattern.utf8)
        return value.count == shape.count && zip(value, shape).allSatisfy { $1 == 0x64 ? (0x30...0x39).contains($0) : $0 == $1 }
    }

    /// ImageIO's APP13 holds what it read from IPTC, in an order not found yet, with a new digest:
    /// it is written again when the input's holds IPTC, or other resources beside an XMP packet
    /// (the corpus's 10), and left out otherwise (`p-*`).
    static func photoshopIsRewritten(_ body: ArraySlice<UInt8>, hasXMP: Bool) -> Bool {
        let prefix = Array("Photoshop 3.0\0".utf8)
        guard body.starts(with: prefix) else { return false }
        let bytes = Array(body)
        var offset = prefix.count
        var iptc = false, other = false
        while offset + 12 <= bytes.count, bytes[offset..<(offset + 4)].elementsEqual(Array("8BIM".utf8)) {
            let id = Int(bytes[offset + 4]) << 8 | Int(bytes[offset + 5])
            let nameLength = Int(bytes[offset + 6])
            let sizeAt = offset + 7 + nameLength + ((nameLength + 1) & 1)
            guard sizeAt + 4 <= bytes.count else { break }
            let length = bytes[sizeAt..<(sizeAt + 4)].reduce(0) { $0 << 8 | Int($1) }
            if id == 0x0404 && length > 0 { iptc = true } else if id != 0x0404 && id != 0x0425 { other = true }
            offset = sizeAt + 4 + length + (length & 1)
        }
        return iptc || (other && hasXMP)
    }

    private struct XMP {
        let bytes: [UInt8]

        func find(_ needle: [UInt8], from start: Int = 0) -> Int? {
            guard !needle.isEmpty, bytes.count >= needle.count, start <= bytes.count - needle.count else { return nil }
            return (start...(bytes.count - needle.count)).first { bytes[$0] == needle[0] && bytes[$0..<($0 + needle.count)].elementsEqual(needle) }
        }

        func startsName(_ index: Int) -> Bool {
            guard index > 0 else { return true }
            let c = bytes[index - 1]
            return !(c == 0x5F || c == 0x3A || (0x30...0x39).contains(c) || (0x41...0x5A).contains(c) || (0x61...0x7A).contains(c))
        }

        func attribute(_ name: String) -> Int? {
            let needle = Array(name.utf8) + [0x3D, 0x22]
            var at = 0
            while let i = find(needle, from: at) {
                if startsName(i) { return i + needle.count }
                at = i + 1
            }
            return nil
        }

        func until(_ stop: UInt8, from start: Int) -> [UInt8]? {
            bytes[start...].firstIndex(of: stop).map { Array(bytes[start..<$0]) }
        }

        /// An attribute's or a simple element's text.
        func property(_ name: String) -> [UInt8]? {
            if let start = attribute(name) { return until(0x22, from: start) }
            let open = Array("<\(name)>".utf8)
            guard let i = find(open), let text = until(0x3C, from: i + open.count), bytes[(i + open.count + text.count)...].starts(with: Array("</".utf8)) else { return nil }
            return text
        }

        /// The one item of a `dc:` array (several, or an attribute, have not been observed).
        func item(_ name: String, path: String) throws -> [UInt8]? {
            let open = Array("<\(name)>".utf8), close = Array("</\(name)>".utf8)
            guard let i = find(open), let end = find(close, from: i) else {
                if attribute(name) != nil { throw refusal("XMP \(name) as an attribute", path: path) }
                return nil
            }
            let li = Array("<rdf:li".utf8)
            var at = i, items: [[UInt8]] = []
            while let start = find(li, from: at), start < end, let body = bytes[start...].firstIndex(of: 0x3E) {
                if let text = until(0x3C, from: body + 1), bytes[(body + 1 + text.count)...].starts(with: Array("</rdf:li>".utf8)) { items.append(text) }
                at = body + 1
            }
            if items.count > 1 { throw refusal("XMP \(name) of several values", path: path) }
            return items.first
        }

        /// Names in the `tiff`, `exif` and `exifEX` namespaces, whose tags ImageIO fills from XMP.
        func exifProperties() -> [String] {
            var names: [String] = []
            for prefix in ["tiff:", "exif:", "exifEX:"] {
                let needle = Array(prefix.utf8)
                var at = 0
                while let i = find(needle, from: at) {
                    at = i + 1
                    guard startsName(i) else { continue }
                    let tail = bytes[(i + needle.count)...].prefix { $0 == 0x5F || (0x30...0x39).contains($0) || (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0) }
                    if !tail.isEmpty { names.append(prefix + String(decoding: tail, as: UTF8.self)) }
                }
            }
            return names
        }
    }

    /// What XMP adds: a tag the Exif segment lacks, from the properties seen doing it (`xmp-*`,
    /// `xe-*`). An Exif value stays. Other `tiff`, `exif` and `exifEX` properties fill tags too
    /// (Make, resolution, ISO, lens model seen), which is not modeled.
    private static func merge(_ xmp: XMP, _ tags: inout [Int: Value], _ exif: inout [Int: Value], path: String) throws {
        if let name = xmp.exifProperties().first(where: { !["exif:DateTimeOriginal", "exif:DateTimeDigitized"].contains($0) }) {
            throw refusal("XMP \(name)", path: path)
        }
        func text(_ value: [UInt8]) throws -> Value? {
            if value.contains(0x26) { throw refusal("an XML entity in XMP", path: path) }
            return value.isEmpty ? nil : (2, value.count + 1, value + [0])
        }
        func date(_ names: [String], _ fill: (Value, Value?) -> Void) throws {
            let found = Set(names.compactMap { xmp.property($0) })
            if found.count > 1 { throw refusal("XMP dates that differ", path: path) }
            guard let value = found.first else { return }
            if matches(value[...], "dddd") || matches(value[...], "dddd-dd") { throw refusal("an XMP date of a year or a month", path: path) }
            guard let parsed = xmpDate(value), let date = try text(parsed.date) else { return }
            fill(date, try parsed.fraction.flatMap(text))
        }
        try date(["xmp:ModifyDate"]) { date, fraction in
            guard tags[0x0132] == nil else { return }
            tags[0x0132] = date
            if exif[0x9290] == nil { exif[0x9290] = fraction }
        }
        try date(["photoshop:DateCreated", "exif:DateTimeOriginal"]) { date, fraction in
            guard exif[0x9003] == nil else { return }
            exif[0x9003] = date
            if exif[0x9291] == nil { exif[0x9291] = fraction }
        }
        try date(["xmp:CreateDate", "exif:DateTimeDigitized"]) { date, fraction in
            guard exif[0x9004] == nil else { return }
            exif[0x9004] = date
            if exif[0x9292] == nil { exif[0x9292] = fraction }
        }
        if tags[0x0131] == nil, let value = xmp.property("xmp:CreatorTool") { tags[0x0131] = try text(value) }
        for (tag, name) in [(0x013B, "dc:creator"), (0x8298, "dc:rights"), (0x010E, "dc:description")] where tags[tag] == nil {
            if let value = try xmp.item(name, path: path) { tags[tag] = try text(value) }
        }
    }

    /// `2021-02-03` (midnight) and `2021-02-03T04:05:06` with a fraction and a zone (dropped) are
    /// read; `2021-02-03T04:05` and other text are not. The fraction's digits make the sub-second tag.
    private static func xmpDate(_ value: [UInt8]) -> (date: [UInt8], fraction: [UInt8]?)? {
        func date(_ time: ArraySlice<UInt8>) -> [UInt8] {
            Array(value[0..<10].map { $0 == 0x2D ? 0x3A : $0 }) + [0x20] + time
        }
        if matches(value[...], "dddd-dd-dd") { return (date(Array("00:00:00".utf8)[...]), nil) }
        guard value.count >= 19, matches(value[0..<19], "dddd-dd-ddTdd:dd:dd") else { return nil }
        var rest = value[19...]
        var fraction: [UInt8]?
        if rest.first == 0x2E {
            let digits = rest.dropFirst().prefix { (0x30...0x39).contains($0) }
            guard !digits.isEmpty else { return nil }
            fraction = Array(digits)
            rest = rest.dropFirst(digits.count + 1)
        }
        guard rest.isEmpty || rest.elementsEqual([0x5A]) || matches(rest, "+dd:dd") || matches(rest, "-dd:dd") else { return nil }
        return (date(value[11..<19]), fraction)
    }
}
