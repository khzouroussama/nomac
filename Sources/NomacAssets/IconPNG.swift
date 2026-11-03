import CZlib
import NomacCore

/// The icon PNGs actool writes next to `Assets.car` with `--compress-pngs`: Apple's CgBI PNGs
/// (docs/formats/asset-catalog.md, "Icon PNGs next to Assets.car"; 19 corpus icons and 33
/// self-written ones identical).
enum IconPNG {
    /// Images of more pixels than this are written in two halves, announced by an `iDOT` chunk
    /// (60 × 60 pixels are not, 81 × 60 are; no icon size lies in between).
    static let halvingLimit = 3_600

    /// RGB and RGBA inputs give CgBI PNGs; 8-bit gray and gray-and-alpha ones plain PNGs of
    /// their own samples (wikipedia's sticker icons, `app-icons` icons-gray-type cases).
    static func data(_ image: PNGImage, path: String, smallestWindow: Bool = false) throws -> [UInt8] {
        if let samples = image.graySamples {
            return try grayData(image, samples: samples, path: path, smallestWindow: smallestWindow)
        }
        guard [2, 6].contains(image.colorType) else {
            throw NomacError("icon PNGs from PNGs of color type \(image.colorType) other than 8-bit gray are not supported yet (BACKLOG B-212)", path: path)
        }
        var out: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        func chunk(_ type: String, _ data: [UInt8]) {
            let body = Array(type.utf8) + data
            out += bigEndian(UInt32(data.count)) + body + bigEndian(UInt32(crc32(0, body, uInt(body.count))))
        }
        chunk("CgBI", [0x50, 0x00, 0x20, image.isOpaque ? 6 : 2])
        chunk("IHDR", bigEndian(UInt32(image.width)) + bigEndian(UInt32(image.height)) + [8, 6, 0, 0, 0])
        // An image converted from its color profile keeps its own pixels and the profile, raw
        // deflated (`profiles` experiment: the input's profile, level 9, Z_FILTERED).
        if let profile = image.profile {
            guard image.ancillaryChunks.isEmpty else {
                throw NomacError("icon PNGs with a color profile and chunks \(image.ancillaryChunks.map(\.type)) are not supported yet (BACKLOG B-212)", path: path)
            }
            chunk("iCCP", profile.name + [0, 0] + (try deflate([profile.data])[0]))
        }
        for ancillary in try ancillaryChunks(image, path: path) { chunk(ancillary.type, ancillary.data) }
        let pixels = image.unconvertedPixels ?? image.pixels
        let rowBytes = image.width * 4
        let rows = (0..<image.height).map { [0] + pixels[$0 * rowBytes..<($0 + 1) * rowBytes] }
        if image.width * image.height <= halvingLimit {
            chunk("IDAT", try deflate([rows.flatMap { $0 }])[0])
        } else {
            let top = (image.height + 1) / 2
            let halves = try deflate([rows[..<top].flatMap { $0 }, rows[top...].flatMap { $0 }])
            let offsets = [2, 0, top, 40, top, image.height - top, 40 + 12 + halves[0].count]
            chunk("iDOT", offsets.flatMap { bigEndian(UInt32($0)) })
            chunk("IDAT", halves[0])
            chunk("IDAT", halves[1])
        }
        chunk("IEND", [])
        return out
    }

    /// A plain PNG: `IHDR` with the input's color type, the ancillary chunks, then every row with
    /// filter 0 in a zlib stream (level 9, `Z_FILTERED`, the window reduced as libpng does for
    /// small images), in halves after `iDOT` as CgBI PNGs are. With `smallestWindow` (copypng)
    /// the zlib header names the smallest window of at least 256 bytes that holds the rows, the
    /// stream unchanged (experiment `copypng`).
    static func grayData(_ image: PNGImage, samples: [UInt8], path: String, smallestWindow: Bool = false) throws -> [UInt8] {
        var out: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        func chunk(_ type: String, _ data: [UInt8]) {
            let body = Array(type.utf8) + data
            out += bigEndian(UInt32(data.count)) + body + bigEndian(UInt32(crc32(0, body, uInt(body.count))))
        }
        chunk("IHDR", bigEndian(UInt32(image.width)) + bigEndian(UInt32(image.height)) + [8, image.colorType, 0, 0, 0])
        for ancillary in try ancillaryChunks(image, path: path) { chunk(ancillary.type, ancillary.data) }
        let rowBytes = samples.count / image.height
        let rows = (0..<image.height).map { [0] + samples[$0 * rowBytes..<($0 + 1) * rowBytes] }
        let size = rows.count * (rowBytes + 1)
        var windowBits: Int32 = 15
        while windowBits > 8 && size + 262 <= 1 << (windowBits - 1) { windowBits -= 1 }
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
        if image.width * image.height <= halvingLimit {
            chunk("IDAT", try stream([rows.flatMap { $0 }])[0])
        } else {
            let top = (image.height + 1) / 2
            let halves = try stream([rows[..<top].flatMap { $0 }, rows[top...].flatMap { $0 }])
            chunk("iDOT", [2, 0, top, 40, top, image.height - top, 40 + 12 + halves[0].count].flatMap { bigEndian(UInt32($0)) })
            chunk("IDAT", halves[0])
            chunk("IDAT", halves[1])
        }
        chunk("IEND", [])
        return out
    }

    /// The input's ancillary chunks as actool writes them (`icons` metadata cases, netnewswire,
    /// flappy-fly-bird, uncloudnotes): `gAMA`, `sRGB`, `cHRM`, `eXIf`, `iTXt`, `pHYs`, then the
    /// `tEXt` chunks in their order, each copied; `sRGB` (intent 0) brings `gAMA` 1/2.2 and
    /// sRGB's `cHRM` when the input has none. Other chunks, and repeated ones but `tEXt`, have not
    /// been observed.
    static func ancillaryChunks(_ image: PNGImage, path: String) throws -> [PNGImage.Chunk] {
        let chunks = image.ancillaryChunks
        func one(_ type: String) -> PNGImage.Chunk? { chunks.first { $0.type == type } }
        let chromaticities: [UInt32] = [31_270, 32_900, 64_000, 33_000, 30_000, 60_000, 15_000, 6_000]
        let srgbGamma = PNGImage.Chunk(type: "gAMA", data: bigEndian(45_455))
        let srgbChromaticities = PNGImage.Chunk(type: "cHRM", data: chromaticities.flatMap(bigEndian))
        let singles = ["gAMA", "sRGB", "cHRM", "eXIf", "iTXt", "pHYs"]
        let srgb = one("sRGB")
        guard chunks.allSatisfy({ singles.contains($0.type) || $0.type == "tEXt" }),
              singles.allSatisfy({ type in chunks.filter { $0.type == type }.count < 2 }),
              srgb.map({ $0.data == [0] && [nil, srgbGamma].contains(one("gAMA")) && [nil, srgbChromaticities].contains(one("cHRM")) }) ?? true else {
            throw NomacError("icon PNGs with chunks \(chunks.map(\.type)) are not supported yet (BACKLOG B-212)", path: path)
        }
        var out: [PNGImage.Chunk] = []
        if let gamma = one("gAMA") ?? srgb.map({ _ in srgbGamma }) { out.append(gamma) }
        if let srgb { out.append(srgb) }
        if let chromaticities = one("cHRM") ?? srgb.map({ _ in srgbChromaticities }) { out.append(chromaticities) }
        out += ["eXIf", "iTXt", "pHYs"].compactMap(one)
        return out + chunks.filter { $0.type == "tEXt" }
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
