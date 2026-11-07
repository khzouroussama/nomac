import NomacCore
import NomacLZFSE

/// What a minimum deployment target before iOS 13 makes of image renditions
/// (docs/formats/asset-catalog.md, "Deployment-target variants"; `old-targets` experiment): every
/// image is compiled once per variant, each variant packed on its own, its key carrying the
/// variant's value.
struct ImageVariants {
    enum Encoding {
        case deepmap2
        /// `PlainImagePayload`.
        case plain
        /// `PlainImagePayload.lzvn`, iOS 8's: rows without padding, LZVN streams.
        case plainLZVN
        /// `PaletteImagePayload`.
        case palette
    }

    struct Variant {
        var value: UInt16
        var encoding: Encoding
    }

    var attribute: RenditionAttribute = .target
    var variants: [Variant]
    /// iOS 8 packs nothing and stores gray images as `ARGB`.
    var packs = true
    var keepsGray = true
    /// Before iOS 10 a language direction adds a rendition without the direction, for a variant
    /// that changes with the target (9.3: 5, 9.0: 0, 8.0: 3); not understood.
    var refusesDirections = false
    var iconEncoding = Encoding.plain

    /// iOS 13 and later: one rendition per image.
    static let current = ImageVariants(variants: [Variant(value: 0, encoding: .deepmap2)])

    /// Bisected over every minor version from 3.0 to 13.0: 12.0 to 12.5 have 0 and 5, 9.3 to 11.4
    /// have 0, 3 and 5 with attribute 25, 9.0 to 9.2 the same with attribute 5, 8.0 to 8.4 no
    /// atlases and LZVN streams.
    init(iOSTarget target: String) throws {
        let parts = target.split(separator: ".").map { Int($0) ?? 0 }
        let version = (parts.first ?? 0, parts.count > 1 ? parts[1] : 0)
        let deep = Variant(value: 5, encoding: .deepmap2), palette = Variant(value: 3, encoding: .palette)
        switch version {
        case (13..., _): self = .current
        case (12, _): variants = [Variant(value: 0, encoding: .palette), deep]
        case (10...11, _): variants = [Variant(value: 0, encoding: .plain), palette, deep]
        case (9, _):
            if version.1 < 3 { attribute = .legacyTarget }
            variants = [Variant(value: 0, encoding: .plain), palette, deep]
            refusesDirections = true
        case (8, _):
            attribute = .legacyTarget
            refusesDirections = true
            variants = [Variant(value: 0, encoding: .plainLZVN), palette, deep]
            packs = false
            keepsGray = false
            iconEncoding = .plainLZVN
        default:
            // iOS 7 stores gzip streams (zlib's deflate); before it image sets become loose PNGs.
            throw NomacError("actool: image sets for deployment targets before iOS 8.0 are not supported yet (BACKLOG B-200)")
        }
    }

    init(variants: [Variant]) {
        self.variants = variants
    }

    /// Before iOS 11 actool writes the icon PNGs `--standalone-icon-behavior all` writes, and
    /// resizes a single-size icon to more of them than nomac knows (`old-targets`).
    static func writesAllIconFiles(iOSTarget target: String) -> Bool {
        Actool.majorVersion(target) < 11
    }

    /// What is not observed before iOS 13 stops the build.
    func check(_ sources: [ImageSet.Source]) throws {
        guard variants.count > 1 else { return }
        for source in sources {
            if source.direction != 0 && refusesDirections {
                throw NomacError("actool: image set entries with a language direction before iOS 10.0 are not supported yet (BACKLOG B-200)", path: source.path)
            }
            guard source.kind == .image || source.kind == .appIcon, source.heif == nil, source.image.widePixels == nil else {
                throw NomacError("actool: HEIC, wide-gamut, sticker and symbol images before iOS 13.0 are not supported yet (BACKLOG B-200)", path: source.path)
            }
        }
    }
}

/// `CELM` compression 8 and 10 (`old-targets`, payloads of 53 and 54 images equal): at most 1,024
/// colors, gray images excepted, as a palette image; else `dmap` blobs of deepmap2's modes.
enum PaletteImagePayload {
    static func payload(_ pixels: [UInt8], format: Deepmap2.Format, width: Int, height: Int, opaque: Bool) throws -> [UInt8] {
        var out = ByteWriter()
        out.append(Array("MLEC".utf8))
        let flags: UInt32 = opaque ? 2 : 0
        if format == .bgra, let body = paletteImage(pixels, width: width, height: height) {
            let stream = LZFSE.encode(body, encoder: .libcompression)
            for value in [flags, 8, UInt32(stream.count)] { out.appendLE(value) }
            out.append(stream)
            return out.bytes
        }
        let size = format.bytesPerPixel
        // 71 × 72 stays whole, 65 × 79 is banded: the rows' bytes before padding.
        guard width * size * height >= 20_480 else {
            let whole = try blob(pixels, format: format, width: width, height: height)
            for value in [flags, 10, UInt32(whole.count)] { out.appendLE(value) }
            out.append(whole)
            return out.bytes
        }
        let bandRows = height / 3
        let starts = Array(stride(from: 0, to: height, by: bandRows))
        for value in [flags | 1, 10, UInt32(starts.count)] { out.appendLE(value) }
        for start in starts {
            let rows = min(bandRows, height - start)
            let band = try blob(Array(pixels[start * width * size..<(start + rows) * width * size]), format: format, width: width, height: rows)
            out.append(Array("KCBC".utf8))
            for value in [0, 0, rows, band.count] { out.appendLE(UInt32(value)) }
            out.append(band)
        }
        return out.bytes
    }

    /// `0xCAFEF00D`, 1, the color count, the colors in the order they first occur as ARGB bytes,
    /// then rows of 16-bit little-endian words filled from the top bit, 1, 2, 4, 8 or 16 bits per
    /// pixel. The free low bits of a row's last word keep the low bits of the index of the pixel
    /// whose row-major number is that word's number: an in-place compaction of 16-bit indices
    /// leaves them there.
    static func paletteImage(_ pixels: [UInt8], width: Int, height: Int) -> [UInt8]? {
        var numbers: [UInt32: UInt16] = [:]
        var colors: [UInt32] = []
        var indices = [UInt16](repeating: 0, count: width * height)
        for pixel in 0..<width * height {
            let at = pixel * 4
            let color = UInt32(pixels[at]) | UInt32(pixels[at + 1]) << 8 | UInt32(pixels[at + 2]) << 16 | UInt32(pixels[at + 3]) << 24
            if let number = numbers[color] {
                indices[pixel] = number
                continue
            }
            guard colors.count < 1_024 else { return nil }
            numbers[color] = UInt16(colors.count)
            indices[pixel] = UInt16(colors.count)
            colors.append(color)
        }
        var out = ByteWriter()
        out.appendLE(UInt32(0xCAFE_F00D))
        out.appendLE(UInt32(1))
        out.appendLE(UInt16(colors.count))
        for color in colors { out.appendLE(color.byteSwapped) }
        let bits = colors.count <= 2 ? 1 : colors.count <= 4 ? 2 : colors.count <= 16 ? 4 : colors.count <= 256 ? 8 : 16
        let perWord = 16 / bits
        let wordsPerRow = (width + perWord - 1) / perWord
        var wordNumber = 0
        for row in 0..<height {
            for word in 0..<wordsPerRow {
                var value: UInt32 = 0
                var used = 0
                for x in word * perWord..<min(width, (word + 1) * perWord) {
                    value = value << UInt32(bits) | UInt32(indices[row * width + x])
                    used += bits
                }
                if used < 16 {
                    let free = 16 - used
                    value = value << UInt32(free) | UInt32(indices[wordNumber]) & (UInt32(1) << UInt32(free) - 1)
                }
                out.appendLE(UInt16(value))
                wordNumber += 1
            }
        }
        return out.bytes
    }

    /// 5, the bytes per pixel, the length, 0, then `dmap`, the mode, 1, 10, the bytes per pixel:
    /// the smallest of modes 2, 3 and 4 (the first of equals) when at least 10 bytes smaller than
    /// mode 1, the pixels, per tile of at most 256 columns.
    static func blob(_ pixels: [UInt8], format: Deepmap2.Format, width: Int, height: Int) throws -> [UInt8] {
        let size = format.bytesPerPixel
        func head(_ mode: UInt8) -> [UInt8] { Array("dmap".utf8) + [mode, 1, 10, UInt8(size)] }
        let tiles = stride(from: 0, to: width, by: 256).map { left -> [UInt8] in
            let columns = min(256, width - left)
            var tile: [UInt8] = []
            tile.reserveCapacity(columns * height * size)
            for row in 0..<height { tile += pixels[(row * width + left) * size..<(row * width + left + columns) * size] }
            return tile
        }
        func lengthPrefixed(_ stream: [UInt8]) -> [UInt8] {
            var out = ByteWriter()
            out.appendLE(UInt32(stream.count))
            out.append(stream)
            return out.bytes
        }
        var candidates: [[UInt8]] = []
        var planes = head(2)
        for tile in tiles {
            let columns = tile.count / size / height
            planes += lengthPrefixed(Deepmap2.compressed(Deepmap2Planes.chunk(tile, format: format, width: columns, height: height, alignment: 8)))
        }
        candidates.append(planes)
        var streams = head(3)
        for tile in tiles { streams += lengthPrefixed(Deepmap2.compressed(tile)) }
        candidates.append(streams)
        if format == .bgra, let palette = alphaPalette(pixels, tiles: tiles, head: head(4)) { candidates.append(palette) }
        let smallest = candidates.min { $0.count < $1.count }!
        let raw = head(1) + pixels
        let saved = raw.count - smallest.count
        if saved == 9 { throw NomacError("dmap data 9 bytes smaller than its raw pixels is not known yet (BACKLOG B-200)") }
        let data = saved >= 10 ? smallest : raw
        var out = ByteWriter()
        for value in [5, size, data.count, 0] { out.appendLE(UInt32(value)) }
        out.append(data)
        return out.bytes
    }

    /// Mode 4 (`old-targets`, gray and red-only colors: 4 bands): the color count (4 bytes), the
    /// colors sorted, blue, green, red and red again, per tile the LZ stream of its alpha plane
    /// and its indices.
    static func alphaPalette(_ pixels: [UInt8], tiles: [[UInt8]], head: [UInt8]) -> [UInt8]? {
        var seen = Set<UInt32>()
        for at in stride(from: 0, to: pixels.count, by: 4) {
            seen.insert(UInt32(pixels[at + 2]) << 16 | UInt32(pixels[at + 1]) << 8 | UInt32(pixels[at]))
            if seen.count > 256 { return nil }
        }
        let colors = seen.sorted()
        var numbers: [UInt32: UInt8] = [:]
        for (number, color) in colors.enumerated() { numbers[color] = UInt8(number) }
        var out = ByteWriter()
        out.append(head)
        out.appendLE(UInt32(colors.count))
        for color in colors {
            let red = UInt8(color >> 16)
            out.append([UInt8(color & 0xFF), UInt8(color >> 8 & 0xFF), red, red])
        }
        for tile in tiles {
            var stream = stride(from: 3, to: tile.count, by: 4).map { tile[$0] }
            for at in stride(from: 0, to: tile.count, by: 4) {
                stream.append(numbers[UInt32(tile[at + 2]) << 16 | UInt32(tile[at + 1]) << 8 | UInt32(tile[at])]!)
            }
            let packed = Deepmap2.compressed(stream)
            out.appendLE(UInt32(packed.count))
            out.append(packed)
        }
        return out.bytes
    }
}
