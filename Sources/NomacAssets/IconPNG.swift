import CZlib
import Foundation
import NomacCore

/// The icon PNGs actool writes next to `Assets.car` with `--compress-pngs`: Apple's CgBI PNGs
/// (docs/formats/asset-catalog.md, "Icon PNGs next to Assets.car"; 19 corpus icons and 33
/// self-written ones identical).
enum IconPNG {
    /// 8-bit images of at least this many pixels in two rows or more, not interlaced, are written
    /// in two halves, announced by an `iDOT` chunk (`copypng` halves cases: 65 × 63 are not, 64 × 64
    /// and 2,048 × 2 are, 4,097 × 1 is not, whatever the color type).
    static func isHalved(_ image: PNGImage) -> Bool {
        image.width * image.height >= 4_096 && image.height > 1 && image.stored.depth == 8 && !image.stored.interlaced
    }

    /// 8-bit RGB and RGBA inputs give CgBI PNGs; every other form a plain PNG of its own samples
    /// (wikipedia's sticker icons, `app-icons` icons-gray-type cases, `icon-chunks` form cases).
    static func data(_ image: PNGImage, path: String, smallestWindow: Bool = false) throws -> [UInt8] {
        guard [2, 6].contains(image.colorType), image.stored.depth == 8 else {
            return try plainData(image, path: path, smallestWindow: smallestWindow)
        }
        var out: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        func chunk(_ type: String, _ data: [UInt8]) {
            let body = Array(type.utf8) + data
            out += bigEndian(UInt32(data.count)) + body + bigEndian(UInt32(crc32(0, body, uInt(body.count))))
        }
        // RGB counts as opaque, even with `tRNS` (`icon-chunks` form-rgb-trns).
        chunk("CgBI", [0x50, 0x00, 0x20, image.colorType == 2 || image.isOpaque ? 6 : 2])
        chunk("IHDR", bigEndian(UInt32(image.width)) + bigEndian(UInt32(image.height)) + [8, 6, 0, 0, image.stored.interlaced ? 1 : 0])
        let chunks = try ancillaryChunks(image, path: path, plain: false)
        for ancillary in chunks.early + chunks.late { chunk(ancillary.type, ancillary.data) }
        let pixels = image.unconvertedPixels ?? image.pixels
        let rowBytes = image.width * 4
        let rows = image.stored.interlaced ? PNGImage.adam7Rows(pixels, width: image.width, height: image.height)
            : (0..<image.height).map { [0] + pixels[$0 * rowBytes..<($0 + 1) * rowBytes] }
        if !isHalved(image) {
            chunk("IDAT", try deflate([rows.flatMap { $0 }])[0])
        } else {
            let top = (image.height + 1) / 2
            let halves = try deflate([rows[..<top].flatMap { $0 }, rows[top...].flatMap { $0 }])
            let offsets = [2, 0, top, 40, top, image.height - top, 40 + 12 + halves[0].count]
            chunk("iDOT", offsets.flatMap { bigEndian(UInt32($0)) })
            chunk("IDAT", halves[0])
            chunk("IDAT", halves[1])
        }
        for ancillary in chunks.tail { chunk(ancillary.type, ancillary.data) }
        chunk("IEND", [])
        return out
    }

    /// A plain PNG: `IHDR` with the input's form, the ancillary chunks around its `PLTE` and
    /// `tRNS`, then every row of its samples with filter 0 in a zlib stream (level 9, `Z_FILTERED`,
    /// the window reduced as libpng does for small images), in halves after `iDOT` as CgBI PNGs
    /// are. With `smallestWindow` (copypng) the zlib header names the smallest window of at least
    /// 256 bytes that holds the rows, the stream unchanged (experiment `copypng`).
    static func plainData(_ image: PNGImage, path: String, smallestWindow: Bool = false) throws -> [UInt8] {
        var out: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        func chunk(_ type: String, _ data: [UInt8]) {
            let body = Array(type.utf8) + data
            out += bigEndian(UInt32(data.count)) + body + bigEndian(UInt32(crc32(0, body, uInt(body.count))))
        }
        let stored = image.stored
        chunk("IHDR", bigEndian(UInt32(image.width)) + bigEndian(UInt32(image.height)) + [UInt8(stored.depth), image.colorType, 0, 0, stored.interlaced ? 1 : 0])
        let chunks = try ancillaryChunks(image, path: path, plain: true)
        for ancillary in chunks.early { chunk(ancillary.type, ancillary.data) }
        if !stored.palette.isEmpty { chunk("PLTE", stored.palette) }
        if !stored.transparency.isEmpty { chunk("tRNS", stored.transparency) }
        for ancillary in chunks.late { chunk(ancillary.type, ancillary.data) }
        var rows: [[UInt8]] = []
        var position = 0
        for pass in stored.passes {
            for _ in 0..<pass.rows {
                rows.append([0] + stored.samples[position..<position + pass.rowBytes])
                position += pass.rowBytes
            }
        }
        let size = rows.reduce(0) { $0 + $1.count }
        // Only 8-bit samples get the smaller window (`icon-chunks` form-palette-4, form-gray-1).
        var windowBits: Int32 = 15
        while stored.depth == 8 && windowBits > 8 && size + 262 <= 1 << (windowBits - 1) { windowBits -= 1 }
        func stream(_ parts: [[UInt8]]) throws -> [[UInt8]] {
            var streams = try deflate(parts, windowBits: windowBits)
            if smallestWindow {
                let bits = (8...15).first { size <= 1 << $0 } ?? 15
                let header = UInt16(bits - 8) << 12 | 0x0800 | UInt16(streams[0][1] & 0xC0)
                streams[0][0] = UInt8(header >> 8)
                streams[0][1] = UInt8((header + (31 - header % 31) % 31) & 0xFF)
            }
            return streams
        }
        if !isHalved(image) {
            chunk("IDAT", try stream([rows.flatMap { $0 }])[0])
        } else {
            let top = (rows.count + 1) / 2
            let halves = try stream([rows[..<top].flatMap { $0 }, rows[top...].flatMap { $0 }])
            chunk("iDOT", [2, 0, top, 40, top, rows.count - top, 40 + 12 + halves[0].count].flatMap { bigEndian(UInt32($0)) })
            chunk("IDAT", halves[0])
            chunk("IDAT", halves[1])
        }
        for ancillary in chunks.tail { chunk(ancillary.type, ancillary.data) }
        chunk("IEND", [])
        return out
    }

    /// The chunks PNG icons keep, `early` before a palette, `late` after it and `tail` after the
    /// image data (`icon-chunks`): `gAMA`, `sRGB`, `iCCP`, `sBIT`, `cHRM`, the others safe to copy
    /// in their order, which is what `iTXt` and `eXIf` count as; after the palette `bKGD` of the
    /// image's form, `hIST`, `oFFs`, `pCAL`, `sCAL` (its numbers rewritten), `pHYs`, `tIME`, `sPLT`,
    /// then `tEXt` and `zTXt` in their order, `zTXt` deflated again. `sRGB` brings the `gAMA`
    /// 1/2.2 and the `cHRM` of sRGB in place of the file's, and leaves `iCCP` out. After the image
    /// data only `tIME` and the text chunks are read, and stay there; of the others the first of
    /// each counts. `plain` PNGs deflate with a zlib header, CgBI ones without.
    static func ancillaryChunks(_ image: PNGImage, path: String, plain: Bool) throws -> (early: [PNGImage.Chunk], late: [PNGImage.Chunk], tail: [PNGImage.Chunk]) {
        let before = image.ancillaryChunks.filter { !$0.afterData }, after = image.ancillaryChunks.filter(\.afterData)
        func one(_ type: String) -> PNGImage.Chunk? { before.first { $0.type == type } }
        let chromaticities: [UInt32] = [31_270, 32_900, 64_000, 33_000, 30_000, 60_000, 15_000, 6_000]
        let srgb = one("sRGB")
        var early: [PNGImage.Chunk] = []
        if let srgb {
            early += [PNGImage.Chunk(type: "gAMA", data: bigEndian(45_455)), srgb]
        } else {
            if let gamma = one("gAMA") { early.append(gamma) }
            if let profile = before.lazy.filter({ $0.type == "iCCP" }).compactMap({ iconProfile($0, plain: plain) }).first { early.append(profile) }
        }
        if let significant = one("sBIT") { early.append(significant) }
        if srgb != nil {
            early.append(PNGImage.Chunk(type: "cHRM", data: chromaticities.flatMap(bigEndian)))
        } else if let chromaticities = one("cHRM") {
            early.append(chromaticities)
        }
        let named: Set<String> = ["gAMA", "sRGB", "iCCP", "sBIT", "cHRM", "bKGD", "hIST", "oFFs", "pCAL", "sCAL", "pHYs", "tIME", "sPLT", "tEXt", "zTXt"]
        func copied(_ chunk: PNGImage.Chunk) -> Bool { !named.contains(chunk.type) && chunk.type.utf8.last.map { $0 >= 0x61 } == true }
        early += before.filter { copied($0) && !$0.afterPalette }
        var late: [PNGImage.Chunk] = []
        let backgroundLength = [0: 2, 4: 2, 2: 6, 6: 6, 3: 1][Int(image.colorType)]
        if let background = one("bKGD"), background.data.count == backgroundLength { late.append(background) }
        if image.colorType == 3, let histogram = one("hIST") { late.append(histogram) }
        for type in ["oFFs", "pCAL"] { if let chunk = one(type) { late.append(chunk) } }
        if let scale = one("sCAL") { late.append(rewrittenScale(scale)) }
        for type in ["pHYs", "tIME", "sPLT"] { if let chunk = one(type) { late.append(chunk) } }
        func texts(_ chunks: [PNGImage.Chunk]) throws -> [PNGImage.Chunk] {
            try chunks.filter { ["tEXt", "zTXt"].contains($0.type) }.map { $0.type == "zTXt" ? try rewrittenText($0, plain: plain) : $0 }
        }
        late += try texts(before)
        late += before.filter { copied($0) && $0.afterPalette }
        let tail = (one("tIME") == nil ? after.first { $0.type == "tIME" }.map { [$0] } ?? [] : []) + (try texts(after))
        return (early, late, tail)
    }

    /// An `iCCP` chunk as the icon PNGs keep it (`bad-profiles`): a name of at least a byte; a zlib
    /// stream with its checksum right, whose profile's size field, at most its length, cuts it;
    /// compression method 0. A name over 79 bytes keeps 80 and one NUL. Others are left out.
    static func iconProfile(_ chunk: PNGImage.Chunk, plain: Bool) -> PNGImage.Chunk? {
        guard let name = chunk.data.firstIndex(of: 0), name > 0, name + 2 < chunk.data.count,
              let profile = PNGImage.inflated(Array(chunk.data[(name + 2)...]), windowBits: 15), profile.count >= 4 else { return nil }
        let size = profile[..<4].reduce(0) { $0 << 8 | Int($1) }
        guard size <= profile.count, let deflated = try? deflate([Array(profile[..<size])], windowBits: plain ? 15 : -15)[0] else { return nil }
        let prefix = name > 79 ? Array(chunk.data[..<80]) + [0] : Array(chunk.data[..<name]) + [0, 0]
        return PNGImage.Chunk(type: "iCCP", data: prefix + deflated)
    }

    private static func rewrittenText(_ chunk: PNGImage.Chunk, plain: Bool) throws -> PNGImage.Chunk {
        guard let name = chunk.data.firstIndex(of: 0), name + 2 < chunk.data.count,
              let text = PNGImage.inflated(Array(chunk.data[(name + 2)...]), windowBits: 15) else { return chunk }
        return PNGImage.Chunk(type: "zTXt", data: chunk.data[...name] + [0] + (try deflate([text], windowBits: plain ? 15 : -15)[0]), afterData: chunk.afterData)
    }

    /// `sCAL`'s unit, then its two numbers written as `%.12e` (`icon-chunks` alone-sCAL).
    private static func rewrittenScale(_ chunk: PNGImage.Chunk) -> PNGImage.Chunk {
        let parts = chunk.data.dropFirst().split(separator: 0, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
        guard let unit = chunk.data.first, parts.count == 2, let width = Double(parts[0]), let height = Double(parts[1]) else { return chunk }
        return PNGImage.Chunk(type: "sCAL", data: [unit] + Array(String(format: "%.12e", width).utf8) + [0] + Array(String(format: "%.12e", height).utf8))
    }

    static func bigEndian(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    /// One deflate stream (level 9, memory level 9, `Z_FILTERED`; raw for window bits −15) of the
    /// parts, each but the last ended by a full flush; the bytes written for each part.
    static func deflate(_ parts: [[UInt8]], windowBits: Int32 = -15) throws -> [[UInt8]] {
        var stream = z_stream()
        guard deflateInit2_(&stream, 9, Z_DEFLATED, windowBits, 9, Z_FILTERED, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw NomacError("zlib could not start compressing")
        }
        defer { deflateEnd(&stream) }
        var buffer = [UInt8](repeating: 0, count: 1 << 16)
        var outputs: [[UInt8]] = []
        for (index, var part) in parts.enumerated() {
            let flush = index == parts.count - 1 ? Z_FINISH : Z_FULL_FLUSH
            var output: [UInt8] = []
            var status = Z_OK
            part.withUnsafeMutableBufferPointer { input in
                stream.next_in = input.baseAddress
                stream.avail_in = uInt(input.count)
                repeat {
                    buffer.withUnsafeMutableBufferPointer { out in
                        stream.next_out = out.baseAddress
                        stream.avail_out = uInt(out.count)
                        status = CZlib.deflate(&stream, flush)
                    }
                    output += buffer[..<(buffer.count - Int(stream.avail_out))]
                } while status == Z_OK && stream.avail_out == 0
            }
            let finished = flush == Z_FINISH ? status == Z_STREAM_END : status == Z_OK || status == Z_BUF_ERROR
            guard finished else { throw NomacError("zlib could not compress (status \(status))") }
            outputs.append(output)
        }
        return outputs
    }
}
