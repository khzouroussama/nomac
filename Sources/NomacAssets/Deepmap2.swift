import Foundation
import NomacCore
import NomacLZFSE

/// actool's deepmap2 image payloads (`CELM` compression 11) of premultiplied BGRA or gray and
/// alpha pixels, as observed on retro-rampage and self-written images (docs/formats/asset-catalog.md,
/// "Images", "deepmap2 payload").
enum Deepmap2 {
    enum Format {
        case bgra
        /// `GA8`: each pixel's premultiplied gray, then its alpha.
        case gray
        /// `RGBW`: premultiplied RGBA half floats in extended sRGB (format 20, B-213).
        case rgbaHalf

        var bytesPerPixel: Int {
            switch self {
            case .bgra: 4
            case .gray: 2
            case .rgbaHalf: 8
            }
        }

        /// The number the header and blob give the format: the bytes per pixel, 20 for `RGBW`.
        var code: Int { self == .rgbaHalf ? 20 : bytesPerPixel }
    }

    /// LZVN without a header below 4,096 bytes, LZFSE from there, as libcompression's buffer API
    /// writes them.
    static func compressed(_ bytes: [UInt8]) -> [UInt8] {
        bytes.count < 4096 ? LZVN.encode(bytes, encoder: .libcompression) : LZFSE.encode(bytes, encoder: .libcompression)
    }

    static func header(mode: UInt8, format: Format, width: Int, height: Int) -> [UInt8] {
        var out = ByteWriter()
        out.append(Array("dmp2".utf8))
        out.append([mode, 1, 10, UInt8(format.code)])
        out.appendLE(UInt16(width))
        out.appendLE(UInt16(height))
        return out.bytes
    }

    static func raw(_ pixels: [UInt8], format: Format, width: Int, height: Int) -> [UInt8] {
        header(mode: 1, format: format, width: width, height: height) + pixels
    }

    /// Mode 3: chunks of as many rows as fit in 2 MiB, the header's height, each a 4-byte length
    /// and the LZ stream of its pixels (flappy-fly-bird's images 1,920 pixels wide: 273 rows).
    static func lzCompressed(_ pixels: [UInt8], format: Format, width: Int, height: Int) -> [UInt8] {
        let rowBytes = width * format.bytesPerPixel
        let rows = min(height, max(1, (1 << 21) / rowBytes))
        var out = ByteWriter()
        out.append(header(mode: 3, format: format, width: width, height: rows))
        for top in stride(from: 0, to: height, by: rows) {
            let stream = compressed(Array(pixels[top * rowBytes..<min(height, top + rows) * rowBytes]))
            out.appendLE(UInt32(stream.count))
            out.append(stream)
        }
        return out.bytes
    }

    /// Mode 4: the distinct colors in `PaletteOrder`, then one index byte per pixel. With an
    /// alpha plane, the colors have alpha 0 and the stream starts with every pixel's alpha.
    static func palette(_ bgra: [UInt8], width: Int, height: Int, alphaPlane: Bool) -> [UInt8]? {
        let pixels = stride(from: 0, to: bgra.count, by: 4).map { i -> UInt32 in
            UInt32(bgra[i]) | UInt32(bgra[i + 1]) << 8 | UInt32(bgra[i + 2]) << 16 | (alphaPlane ? 0 : UInt32(bgra[i + 3]) << 24)
        }
        let distinct = Set(pixels)
        guard distinct.count <= 256 else { return nil }
        let colors = PaletteOrder.sorted(Array(distinct))
        var index: [UInt32: UInt8] = [:]
        for (position, color) in colors.enumerated() { index[color] = UInt8(position) }
        var stream: [UInt8] = alphaPlane ? stride(from: 3, to: bgra.count, by: 4).map { bgra[$0] } : []
        stream += pixels.map { index[$0]! }
        let packed = compressed(stream)
        var out = ByteWriter()
        out.append(header(mode: 4, format: .bgra, width: width, height: height))
        out.appendLE(UInt16(colors.count))
        out.appendLE(UInt16(alphaPlane ? 3 : 4))
        for color in colors { out.appendLE(color) }
        out.appendLE(UInt32(packed.count))
        out.append(packed)
        return out.bytes
    }

    /// The smallest compressed candidate (the first of equals in this order: planes before LZ,
    /// `image-appearances` image-contrast) when it is at least
    /// 10 bytes smaller than the raw pixels, which stay when it saves 8 or fewer; at exactly 9
    /// actool goes either way (5 of 6 images raw), and nomac stops (BACKLOG B-200). Gray images
    /// have no palette candidates (`images`: none of 25 gray images took mode 4, two-level ones
    /// included).
    static func best(_ pixels: [UInt8], format: Format, width: Int, height: Int) throws -> [UInt8] {
        // `RGBW` data is stored raw or LZ-compressed; its other modes are not known.
        var candidates = format == .rgbaHalf ? [] : [Deepmap2Planes.encode(pixels, format: format, width: width, height: height)]
        candidates.append(lzCompressed(pixels, format: format, width: width, height: height))
        if format == .bgra {
            candidates += [
                palette(pixels, width: width, height: height, alphaPlane: false),
                palette(pixels, width: width, height: height, alphaPlane: true),
            ].compactMap { $0 }
        }
        let smallest = candidates.min { $0.count < $1.count }!
        let uncompressed = raw(pixels, format: format, width: width, height: height)
        switch uncompressed.count - smallest.count {
        case 10...: return smallest
        case 9: throw NomacError("deepmap2 data 9 bytes smaller than its raw pixels is not known yet (BACKLOG B-200)")
        default: return uncompressed
        }
    }

    static func blob(_ data: [UInt8], format: Format) -> [UInt8] {
        var out = ByteWriter()
        out.appendLE(UInt32(1))
        out.appendLE(UInt32(format.code))
        out.appendLE(UInt32(data.count))
        out.appendLE(UInt32(0))
        out.append(data)
        return out.bytes
    }

    /// The `CELM` payload: one blob, or `KCBC` bands of ⌊2^20 / width⌋ rows (the last one the rest),
    /// each band choosing its mode. `opaque` comes from the source images, even for an atlas whose
    /// borders are transparent.
    static func payload(_ pixels: [UInt8], format: Format, width: Int, height: Int, opaque: Bool) throws -> [UInt8] {
        let bandRows = (1 << 20) / width
        let rowBytes = width * format.bytesPerPixel
        var out = ByteWriter()
        out.append(Array("MLEC".utf8))
        if height <= bandRows {
            let data = blob(try best(pixels, format: format, width: width, height: height), format: format)
            out.appendLE(UInt32(opaque ? 2 : 0))
            out.appendLE(UInt32(11))
            out.appendLE(UInt32(data.count))
            out.append(data)
            return out.bytes
        }
        var bands = ByteWriter()
        var count: UInt32 = 0
        for top in stride(from: 0, to: height, by: bandRows) {
            let rows = min(bandRows, height - top)
            let band = Array(pixels[top * rowBytes..<(top + rows) * rowBytes])
            let data = blob(try best(band, format: format, width: width, height: rows), format: format)
            bands.append(Array("KCBC".utf8))
            bands.appendLE(UInt32(0))
            bands.appendLE(UInt32(0))
            bands.appendLE(UInt32(rows))
            bands.appendLE(UInt32(data.count))
            bands.append(data)
            count += 1
        }
        out.appendLE(UInt32(opaque ? 3 : 1))
        out.appendLE(UInt32(11))
        out.appendLE(count)
        out.append(bands.bytes)
        return out.bytes
    }
}

/// The order of a mode-4 palette: the colors by their little-endian value, then sorted again by
/// the exclusive-or of their four bytes with the Bentley–McIlroy quicksort whose unstable order
/// actool's palettes show (357 of 357 palettes).
enum PaletteOrder {
    static func key(_ color: UInt32) -> Int {
        Int((color ^ color >> 8 ^ color >> 16 ^ color >> 24) & 0xFF)
    }

    static func sorted(_ colors: [UInt32]) -> [UInt32] {
        var a = colors.sorted()
        quicksort(&a, 0, a.count)
        return a
    }

    private static func compare(_ a: [UInt32], _ i: Int, _ j: Int) -> Int {
        key(a[i]) - key(a[j])
    }

    private static func median(_ a: [UInt32], _ i: Int, _ j: Int, _ k: Int) -> Int {
        if compare(a, i, j) < 0 {
            return compare(a, j, k) < 0 ? j : (compare(a, i, k) < 0 ? k : i)
        }
        return compare(a, j, k) > 0 ? j : (compare(a, i, k) < 0 ? i : k)
    }

    /// Insertion sort of `a[low..<low + n]`, giving up after more than `limit` swaps (the swaps
    /// made stay); true when it finished.
    private static func insertionSort(_ a: inout [UInt32], _ low: Int, _ n: Int, limit: Int = .max) -> Bool {
        var swaps = 0
        for m in low + 1..<max(low + 1, low + n) {
            var l = m
            while l > low, compare(a, l - 1, l) > 0 {
                a.swapAt(l, l - 1)
                l -= 1
                swaps += 1
                if swaps > limit { return false }
            }
        }
        return true
    }

    private static func quicksort(_ a: inout [UInt32], _ start: Int, _ count: Int) {
        var low = start, n = count
        while true {
            if n < 8 {
                _ = insertionSort(&a, low, n)
                return
            }
            var pm = low + n / 2
            var pl = low, pn = low + n - 1
            if n > 40 {
                let d = n / 8
                pl = median(a, pl, pl + d, pl + 2 * d)
                pm = median(a, pm - d, pm, pm + d)
                pn = median(a, pn - 2 * d, pn - d, pn)
            }
            pm = median(a, pl, pm, pn)
            a.swapAt(low, pm)
            var pa = low + 1, pb = low + 1, pc = low + n - 1, pd = low + n - 1
            var swapped = false
            while true {
                while pb <= pc {
                    let r = compare(a, pb, low)
                    if r > 0 { break }
                    if r == 0 {
                        swapped = true
                        a.swapAt(pa, pb)
                        pa += 1
                    }
                    pb += 1
                }
                while pb <= pc {
                    let r = compare(a, pc, low)
                    if r < 0 { break }
                    if r == 0 {
                        swapped = true
                        a.swapAt(pc, pd)
                        pd -= 1
                    }
                    pc -= 1
                }
                if pb > pc { break }
                a.swapAt(pb, pc)
                swapped = true
                pb += 1
                pc -= 1
            }
            let end = low + n
            var r = min(pa - low, pb - pa)
            for t in 0..<r { a.swapAt(low + t, pb - r + t) }
            r = min(pd - pc, end - pd - 1)
            for t in 0..<r { a.swapAt(pb + t, end - r + t) }
            if !swapped, insertionSort(&a, low, n, limit: 1 + n / 4) { return }
            let left = pb - pa, right = pd - pc
            if left > 1 { quicksort(&a, low, left) }
            guard right > 1 else { return }
            low = end - right
            n = right
        }
    }
}

/// Mode 2: each pixel as (Y, A, C) from its premultiplied blue, green and red, or its gray alone,
/// predicted along its row by the filter whose residuals cost least, the earlier of 0, 2, 3, 4, 1
/// on equal costs (the first row of a chunk only 0 or 2), in chunks of an alpha plane, the filter
/// bytes and the residuals' high and low bytes, padded to 16 bytes and compressed. A cost is the
/// float sum of ln(1 + |r|) as floats, residual by residual, except for filter 1, which adds each
/// pixel's (Y + A) + C first: what decides actool's exact ties (4,100 rows). A gray pixel is the
/// value (gray, 0, 0), whose zero residuals add nothing to a cost.
enum Deepmap2Planes {
    typealias Value = (y: Int, a: Int, c: Int)

    static func value(blue b: Int, green g: Int, red r: Int) -> Value {
        let a = (b - r) / 2
        let t = r + a
        let c = (g - t) / 2
        return (t + c, a, c)
    }

    static let filters = [0, 2, 3, 4, 1]

    static func prediction(_ filter: Int, left: Value, up: Value, upLeft: Value) -> Value {
        switch filter {
        case 2: return left
        case 3: return up
        case 4: return ((left.y + up.y + 1) / 2, (left.a + up.a + 1) / 2, (left.c + up.c + 1) / 2)
        case 1: return abs(up.y - upLeft.y) <= abs(left.y - upLeft.y) ? left : up
        default: return (0, 0, 0)
        }
    }

    /// ln(1 + n) rounded to a float, which equals macOS's `logf` for every residual a pixel can have.
    static let costs: [Float] = (0...1_024).map { Float(log(1 + Double($0))) }

    static func channels(_ format: Deepmap2.Format) -> Int { format == .bgra ? 3 : 1 }

    /// The rows of a chunk: as many as fit in 2 MiB with each row's bytes (the alpha and two per
    /// residual: 7 per pixel, 3 for gray) and filter byte rounded up to 16 bytes (24 widths
    /// predicted, and gray images of 1,024 and 2,000 pixels).
    static func chunkRows(width: Int, height: Int, format: Deepmap2.Format = .bgra) -> Int {
        min(height, (1 << 21) / (((1 + 2 * channels(format)) * width + 1 + 15) & ~15))
    }

    static func encode(_ pixels: [UInt8], format: Deepmap2.Format, width: Int, height: Int) -> [UInt8] {
        let rows = chunkRows(width: width, height: height, format: format)
        let size = format.bytesPerPixel
        var values = [Value](repeating: (0, 0, 0), count: width * height)
        var alpha = [UInt8](repeating: 0, count: width * height)
        for pixel in 0..<width * height {
            if format == .bgra {
                values[pixel] = value(blue: Int(pixels[pixel * 4]), green: Int(pixels[pixel * 4 + 1]), red: Int(pixels[pixel * 4 + 2]))
            } else {
                values[pixel] = (Int(pixels[pixel * 2]), 0, 0)
            }
            alpha[pixel] = pixels[pixel * size + size - 1]
        }
        var out = ByteWriter()
        out.append(Deepmap2.header(mode: 2, format: format, width: width, height: rows))
        for top in stride(from: 0, to: height, by: rows) {
            let count = min(rows, height - top)
            let stream = Deepmap2.compressed(chunk(values, alpha: alpha, channels: channels(format), width: width, top: top, rows: count))
            out.appendLE(UInt32(stream.count))
            out.append(stream)
        }
        return out.bytes
    }

    /// A whole image as one chunk, `dmap` tiles padded to 8 bytes (`old-targets`).
    static func chunk(_ pixels: [UInt8], format: Deepmap2.Format, width: Int, height: Int, alignment: Int) -> [UInt8] {
        let size = format.bytesPerPixel
        var values = [Value](repeating: (0, 0, 0), count: width * height)
        var alpha = [UInt8](repeating: 0, count: width * height)
        for pixel in 0..<width * height {
            if format == .bgra {
                values[pixel] = value(blue: Int(pixels[pixel * 4]), green: Int(pixels[pixel * 4 + 1]), red: Int(pixels[pixel * 4 + 2]))
            } else {
                values[pixel] = (Int(pixels[pixel * 2]), 0, 0)
            }
            alpha[pixel] = pixels[pixel * size + size - 1]
        }
        return chunk(values, alpha: alpha, channels: channels(format), width: width, top: 0, rows: height, alignment: alignment)
    }

    static func chunk(_ values: [Value], alpha: [UInt8], channels: Int, width: Int, top: Int, rows: Int, alignment: Int = 16) -> [UInt8] {
        var filterBytes: [UInt8] = []
        var codes: [UInt16] = []
        codes.reserveCapacity(width * rows * channels)
        var residuals = [Int](repeating: 0, count: width * 3)
        var bestResiduals = residuals
        for row in 0..<rows {
            let base = (top + row) * width
            var best: (cost: Float, filter: Int)?
            for filter in row == 0 ? [0, 2] : filters {
                var cost: Float = 0
                for x in 0..<width {
                    let current = values[base + x]
                    let up: Value = row == 0 ? (0, 0, 0) : values[base - width + x]
                    let predicted: Value
                    if x == 0 {
                        predicted = filter == 0 || filter == 2 ? (0, 0, 0) : up
                    } else {
                        let upLeft: Value = row == 0 ? (0, 0, 0) : values[base - width + x - 1]
                        predicted = prediction(filter, left: values[base + x - 1], up: up, upLeft: upLeft)
                    }
                    let r = (current.y - predicted.y, current.a - predicted.a, current.c - predicted.c)
                    residuals[x * 3] = r.0
                    residuals[x * 3 + 1] = r.1
                    residuals[x * 3 + 2] = r.2
                    if filter == 1 {
                        cost += (costs[abs(r.0)] + costs[abs(r.1)]) + costs[abs(r.2)]
                    } else {
                        cost += costs[abs(r.0)]
                        cost += costs[abs(r.1)]
                        cost += costs[abs(r.2)]
                    }
                }
                if best == nil || cost < best!.cost {
                    best = (cost, filter)
                    swap(&residuals, &bestResiduals)
                }
            }
            filterBytes.append(UInt8(best!.filter))
            for (index, r) in bestResiduals.enumerated() where channels == 3 || index % 3 == 0 {
                codes.append(r >= 0 ? UInt16(2 * r) : UInt16(-2 * r + 1))
            }
        }
        var body = Array(alpha[top * width..<(top + rows) * width]) + filterBytes + codes.map { UInt8($0 >> 8) } + codes.map { UInt8($0 & 0xFF) }
        body += [UInt8](repeating: 0, count: (alignment - body.count % alignment) % alignment)
        return body
    }
}
