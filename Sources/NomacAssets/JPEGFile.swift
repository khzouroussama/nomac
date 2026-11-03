import NomacCore

/// JPEG images in image sets, which actool stores as files rather than pixels (pixel format
/// `JPEG`, docs/formats/asset-catalog.md "JPEG images"): their size, from the frame header, and
/// their bytes without the segments actool leaves out.
struct JPEGFile {
    let width: Int
    let height: Int
    /// The file as actool stores it: every segment but the APPn ones other than JFIF's APP0,
    /// Exif's APP1 (see `keepsExif`), the ICC profile's APP2 and Adobe's APP14, and but comments
    /// (`vector-images` jpeg cases: XMP, APP9, APP12, Photoshop's APP13 and COM are left out),
    /// the APPn ones first.
    let stored: [UInt8]

    init(_ bytes: [UInt8], path: String) throws {
        func malformed() -> NomacError { NomacError("malformed JPEG image", path: path) }
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { throw malformed() }
        var applications: [(marker: UInt8, bytes: ArraySlice<UInt8>)] = []
        var others: [UInt8] = []
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
                others += bytes[offset...]
                break
            }
            let kept: Bool
            switch marker {
            case 0xE1: kept = body.starts(with: Array("Exif\0".utf8)) ? try Self.keepsExif(Array(body.dropFirst(6)), path: path) : false
            case 0xE0, 0xE2, 0xEE: kept = true
            case 0xE3...0xEF, 0xFE: kept = false
            default: kept = true
            }
            if kept && (0xE0...0xEF).contains(marker) {
                applications.append((marker, bytes[offset..<(offset + 2 + length)]))
            } else if kept {
                others += bytes[offset..<(offset + 2 + length)]
            }
            offset += 2 + length
        }
        guard let size else { throw malformed() }
        (width, height) = size
        // The kept APPn segments come first, in marker order (the corpus's JPEGs with their ICC
        // profile before their Exif get them the other way round).
        let ordered = applications.enumerated().sorted { ($0.element.marker, $0.offset) < ($1.element.marker, $1.offset) }.flatMap { $0.element.bytes }
        stored = [0xFF, 0xD8] + ordered + others
    }

    /// ImageIO keeps an Exif segment as it is when it is big-endian and holds only the tags seen
    /// kept so (the corpus's 64 image set JPEGs and the `images` jpeg cases: orientation,
    /// resolution, the Exif directory's color space, pixel size and user comment, and software
    /// and date beside a resolution), and leaves it out when its first directory is empty; it
    /// rewrites other forms (little-endian ones, YCbCrPositioning, camera tags), where nomac stops.
    static func keepsExif(_ tiff: [UInt8], path: String) throws -> Bool {
        func unsupported() -> NomacError {
            NomacError("JPEG images with Exif metadata ImageIO rewrites (other byte orders or tags) are not supported yet (BACKLOG B-200)", path: path)
        }
        let little = tiff.starts(with: [0x49, 0x49, 0x2A, 0x00])
        guard tiff.count >= 8, little || tiff.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) else { throw unsupported() }
        func u16(_ offset: Int) -> Int { little ? Int(tiff[offset + 1]) << 8 | Int(tiff[offset]) : Int(tiff[offset]) << 8 | Int(tiff[offset + 1]) }
        func u32(_ offset: Int) -> Int { little ? u16(offset + 2) << 16 | u16(offset) : u16(offset) << 16 | u16(offset + 2) }
        func directory(_ offset: Int) throws -> [(tag: Int, value: Int)] {
            guard offset + 2 <= tiff.count, offset + 2 + 12 * u16(offset) <= tiff.count else { throw unsupported() }
            return (0..<u16(offset)).map { (u16(offset + 2 + 12 * $0), u32(offset + 10 + 12 * $0)) }
        }
        let first = try directory(u32(4))
        if first.isEmpty { return false }
        guard !little else { throw unsupported() }
        let firstTags = Set(first.map(\.tag))
        guard firstTags.isSubset(of: [0x0112, 0x011A, 0x011B, 0x0128, 0x0131, 0x0132, 0x8769]),
              firstTags.isDisjoint(with: [0x0131, 0x0132]) || firstTags.contains(0x011A) else { throw unsupported() }
        if let exif = first.first(where: { $0.tag == 0x8769 }) {
            guard Set(try directory(exif.value).map(\.tag)).isSubset(of: [0x9286, 0xA001, 0xA002, 0xA003]) else { throw unsupported() }
        }
        return true
    }
}
