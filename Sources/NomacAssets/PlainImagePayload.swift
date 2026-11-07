import NomacLZFSE

/// The `CELM` payload of images actool stores without deepmap2: app icons and their atlases, and
/// the deployment-target-0 variant of images (docs/formats/asset-catalog.md, "Deployment-target
/// variants"; uncloudnotes' and flappy-fly-bird's icons, 552 self-written images). Rows are
/// padded with zeros to a multiple of 32 bytes; below 4,096 bytes they are stored run-length
/// encoded when that is smaller, else as they are; from there as LZFSE streams, in bands when the
/// image has 4,096 pixels or more.
enum PlainImagePayload {
    static func payload(_ pixels: [UInt8], format: Deepmap2.Format, width: Int, height: Int, opaque: Bool) -> [UInt8] {
        payload(pixels, bytesPerPixel: format.bytesPerPixel, width: width, height: height, opaque: opaque)
    }

    /// `runLengths: false`: rows below 4,096 bytes stored as they are (HEIC images' `RGB5`).
    static func payload(_ pixels: [UInt8], bytesPerPixel pixelBytes: Int, width: Int, height: Int, opaque: Bool, runLengths: Bool = true) -> [UInt8] {
        let rowBytes = width * pixelBytes, paddedRowBytes = (rowBytes + 31) / 32 * 32
        var rows: [UInt8] = []
        rows.reserveCapacity(paddedRowBytes * height)
        for row in 0..<height {
            rows += pixels[row * rowBytes..<(row + 1) * rowBytes]
            rows += [UInt8](repeating: 0, count: paddedRowBytes - rowBytes)
        }
        var out = ByteWriter()
        out.append(Array("MLEC".utf8))
        let flags: UInt32 = opaque ? 2 : 0
        if rows.count < 4_096 {
            let encoded = runLengths ? runLengthEncoded(pixels, pixelBytes: pixelBytes, width: width, height: height) : rows
            let compressed = encoded.count < rows.count
            out.appendLE(flags)
            out.appendLE(UInt32(compressed ? 1 : 0))
            out.appendLE(UInt32(compressed ? encoded.count : rows.count))
            out.append(compressed ? encoded : rows)
            return out.bytes
        }
        let bandRows = height / (rows.count >= 20_480 ? 3 : 2)
        guard width * height >= 4_096, bandRows >= 1 else {
            let stream = LZFSE.encodeStream(rows)
            out.appendLE(flags)
            out.appendLE(UInt32(4))
            out.appendLE(UInt32(stream.count))
            out.append(stream)
            return out.bytes
        }
        let starts = Array(stride(from: 0, to: height, by: bandRows))
        out.appendLE(flags | 1)
        out.appendLE(UInt32(4))
        out.appendLE(UInt32(starts.count))
        for start in starts {
            let count = min(bandRows, height - start)
            let stream = LZFSE.encodeStream(Array(rows[start * paddedRowBytes..<(start + count) * paddedRowBytes]))
            out.append(Array("KCBC".utf8))
            for value in [0, 0, count, stream.count] { out.appendLE(UInt32(value)) }
            out.append(stream)
        }
        return out.bytes
    }

    /// iOS 8's (`old-targets`, 91 images, 130 streams): the rows without padding, below 4,096 bytes
    /// run-length encoded when smaller, else as they are; from there `LZVN.encodeStream`, in bands
    /// as `payload` counts them from these rows' bytes.
    static func lzvn(_ pixels: [UInt8], width: Int, height: Int, opaque: Bool) -> [UInt8] {
        var out = ByteWriter()
        out.append(Array("MLEC".utf8))
        let flags: UInt32 = opaque ? 2 : 0
        if pixels.count < 4_096 {
            let encoded = runLengthEncoded(pixels, pixelBytes: 4, width: width, height: height)
            let compressed = encoded.count < pixels.count
            for value in [flags, compressed ? 1 : 0, UInt32(compressed ? encoded.count : pixels.count)] { out.appendLE(value) }
            out.append(compressed ? encoded : pixels)
            return out.bytes
        }
        let bandRows = height / (pixels.count >= 20_480 ? 3 : 2)
        guard width * height >= 4_096, bandRows >= 1 else {
            let whole = LZVN.encodeStream(pixels)
            for value in [flags, 3, UInt32(whole.count)] { out.appendLE(value) }
            out.append(whole)
            return out.bytes
        }
        let starts = Array(stride(from: 0, to: height, by: bandRows))
        for value in [flags | 1, 3, UInt32(starts.count)] { out.appendLE(value) }
        for start in starts {
            let count = min(bandRows, height - start)
            let band = LZVN.encodeStream(Array(pixels[start * width * 4..<(start + count) * width * 4]))
            out.append(Array("KCBC".utf8))
            for value in [0, 0, count, band.count] { out.appendLE(UInt32(value)) }
            out.append(band)
        }
        return out.bytes
    }

    /// The bytes per pixel (4, or 3 for gray and alpha), width and height, each row's offset (a
    /// row equal to the one above reuses its offset), then per row runs of at least 4 (6 for gray)
    /// equal pixels as `0x80000000 | n` and the pixel, the pixels between them as `n` and the
    /// pixels.
    static func runLengthEncoded(_ pixels: [UInt8], pixelBytes: Int, width: Int, height: Int) -> [UInt8] {
        let minimumRun = pixelBytes == 4 ? 4 : 6
        let rowBytes = width * pixelBytes
        var offsets: [Int] = []
        var body = ByteWriter()
        let start = 12 + 4 * height
        for row in 0..<height {
            let line = Array(pixels[row * rowBytes..<(row + 1) * rowBytes])
            if row > 0 && line == Array(pixels[(row - 1) * rowBytes..<row * rowBytes]) {
                offsets.append(offsets[row - 1])
                continue
            }
            offsets.append(start + body.bytes.count)
            func pixel(_ x: Int) -> ArraySlice<UInt8> { line[x * pixelBytes..<(x + 1) * pixelBytes] }
            var literal: [UInt8] = []
            func flushLiteral() {
                guard !literal.isEmpty else { return }
                body.appendLE(UInt32(literal.count / pixelBytes))
                body.append(literal)
                literal = []
            }
            var x = 0
            while x < width {
                var end = x + 1
                while end < width && pixel(end) == pixel(x) { end += 1 }
                if end - x >= minimumRun {
                    flushLiteral()
                    body.appendLE(UInt32(0x8000_0000) | UInt32(end - x))
                    body.append(Array(pixel(x)))
                } else {
                    literal += line[x * pixelBytes..<end * pixelBytes]
                }
                x = end
            }
            flushLiteral()
        }
        var out = ByteWriter()
        for value in [pixelBytes == 4 ? 4 : 3, width, height] + offsets { out.appendLE(UInt32(value)) }
        out.append(body.bytes)
        return out.bytes
    }
}
