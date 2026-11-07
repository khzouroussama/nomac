import CZlib
import Foundation
import NomacCore

/// A PNG decoded to the pixels actool stores, in the forms its outputs have been observed for
/// (docs/adr/0202-png-decoding.md): gray, RGB, palette, gray and alpha, RGBA; bit depths below 8
/// for gray and palettes, scaled to 0–255; `tRNS` keys; Adam7 interlacing.
struct PNGImage: Equatable {
    /// A file ImageIO does not read: actool leaves its entry out without a word (`icon-entries`
    /// not-an-image, `icon-chunks` alone-UnSf).
    struct Unreadable: Error, CustomStringConvertible {
        var description: String
        var path: String
    }

    let width: Int
    let height: Int
    /// BGRA with each color premultiplied by alpha as (c × a + 127) / 255, rows from the top.
    let pixels: [UInt8]
    /// The chunks other than `IHDR`, `PLTE`, `tRNS`, `IDAT` and `IEND`, in file order, which the
    /// icon PNGs actool writes carry over (`IconPNG`).
    var ancillaryChunks: [Chunk] = []
    /// The `IHDR` color type: 0 gray, 2 RGB, 3 palette, 4 gray and alpha, 6 RGBA.
    var colorType: UInt8 = 6
    /// The image data as the file has it, unfiltered, one row after another pass by pass, with
    /// what actool's plain icon PNGs repeat (`IconPNG`).
    var stored = Stored()
    /// A chunk's checksum is wrong: the icon PNGs actool lists but does not write (`icon-chunks`
    /// crc cases).
    var iconIsUnwritable = false
    /// For an image converted from its color profile to sRGB (ADR 0204): the pixels before the
    /// conversion, which the icon PNGs keep.
    var unconvertedPixels: [UInt8]?

    struct Stored: Equatable {
        var depth = 8
        var interlaced = false
        var palette: [UInt8] = []
        var transparency: [UInt8] = []
        /// The file itself when it is not 8-bit or is an APNG: pngcrush copies those as they are.
        var verbatim: [UInt8]?
        /// The (row bytes, rows) of each pass.
        var passes: [(rowBytes: Int, rows: Int)] = []
        var samples: [UInt8] = []

        static func == (a: Stored, b: Stored) -> Bool {
            a.depth == b.depth && a.interlaced == b.interlaced && a.palette == b.palette && a.transparency == b.transparency
                && a.samples == b.samples && a.passes.map(\.rowBytes) == b.passes.map(\.rowBytes) && a.passes.map(\.rows) == b.passes.map(\.rows)
        }
    }

    var convertedColors: Bool { unconvertedPixels != nil }
    /// For an RGB image whose colors lie well outside sRGB: its pixels in extended sRGB as
    /// premultiplied RGBA half floats (little-endian), for actool's display-gamut-1 rendition.
    var widePixels: [UInt8]?
    /// The PNG has an alpha channel or a `tRNS` chunk.
    var declaresAlpha = true

    struct Chunk: Equatable {
        var type: String
        var data: [UInt8]
        var afterPalette = false
        var afterData = false
    }

    var isOpaque: Bool { stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 255 } }

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// A float as IEEE 754 half precision, rounded to nearest even.
    static func half(_ value: Float) -> UInt16 {
        let bits = value.bitPattern
        let sign = UInt16(bits >> 16) & 0x8000
        let exponent = Int((bits >> 23) & 0xFF) - 127 + 15
        var mantissa = bits & 0x7F_FFFF
        if exponent >= 31 { return sign | 0x7C00 }
        if exponent <= 0 {
            guard exponent >= -10 else { return sign }
            mantissa |= 0x80_0000
            let shift = UInt32(14 - exponent)
            var half = mantissa >> shift
            let remainder = mantissa & ((1 << shift) - 1), halfway = UInt32(1) << (shift - 1)
            if remainder > halfway || remainder == halfway && half & 1 == 1 { half += 1 }
            return sign | UInt16(half)
        }
        var half = UInt32(exponent) << 10 | mantissa >> 13
        let remainder = mantissa & 0x1FFF
        if remainder > 0x1000 || remainder == 0x1000 && half & 1 == 1 { half += 1 }
        return sign | UInt16(half)
    }

    init(contentsOf path: String) throws {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw NomacError("could not read the image", path: path)
        }
        try self.init(data: [UInt8](data), path: path)
    }

    /// What libpng says when pngcrush copies a file as it is: not 8-bit, or an APNG (`copypng` forms).
    static func copiedAsIs(_ bytes: [UInt8]) -> String? {
        guard bytes.count > 33 else { return nil }
        if bytes[24] != 8 { return "Warning: Input PNG does not have an 8 bit input depth.  Please convert your PNG to 8-bit for optimal performance on iPhone OS." }
        var offset = 8
        while offset + 12 <= bytes.count {
            let type = bytes[offset + 4..<offset + 8]
            if type.elementsEqual(Array("IDAT".utf8)) { return nil }
            if type.elementsEqual(Array("acTL".utf8)) { return "Input PNG is an APNG.  Copying source file to destination..." }
            offset += 12 + bytes[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
        }
        return nil
    }

    /// `colorManaged` false reads what the icon PNGs need, the samples and chunks as they are,
    /// without what `Assets.car`'s pixels take from gamma and profiles (copypng).
    init(data bytes: [UInt8], path: String, colorManaged: Bool = true) throws {
        func unsupported(_ what: String) -> NomacError {
            NomacError("PNG images with \(what) are not supported yet (BACKLOG B-209)", path: path)
        }
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard bytes.count > 8, Array(bytes[0..<8]) == signature else {
            if bytes.starts(with: [0xFF, 0xD8]) { throw NomacError("JPEG files named .png are not supported yet (BACKLOG B-200)", path: path) }
            throw Unreadable(description: "not a PNG file", path: path)
        }
        func u32(_ offset: Int) -> Int {
            Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
        }
        var header: [UInt8] = []
        var palette: [UInt8] = []
        var transparency: [UInt8] = []
        var compressed: [UInt8] = []
        var ancillary: [Chunk] = []
        var iconIsUnwritable = false
        var offset = 8
        while offset + 12 <= bytes.count {
            let length = u32(offset)
            let type = String(decoding: bytes[offset + 4..<offset + 8], as: UTF8.self)
            guard offset + 12 + length <= bytes.count else { throw NomacError("truncated PNG chunk \(type)", path: path) }
            let body = Array(bytes[offset + 8..<offset + 8 + length])
            switch type {
            case "IHDR": header = body
            case "PLTE": palette = body
            case "tRNS": transparency = body
            case "IDAT": compressed += body
            case "IEND": offset = bytes.count
            default:
                let stated = u32(offset + 8 + length)
                let actual = bytes[offset + 4..<offset + 8 + length].withUnsafeBufferPointer { crc32(0, $0.baseAddress, uInt($0.count)) }
                if Int(actual) != stated { iconIsUnwritable = true }
                if bytes[offset + 4] < 0x61 { throw Unreadable(description: "PNG with the unknown critical chunk \(type)", path: path) }
                ancillary.append(Chunk(type: type, data: body, afterPalette: !palette.isEmpty, afterData: !compressed.isEmpty))
            }
            offset += 12 + length
        }
        guard header.count == 13 else { throw NomacError("PNG without a header", path: path) }
        let width = Int(header[0]) << 24 | Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
        let height = Int(header[4]) << 24 | Int(header[5]) << 16 | Int(header[6]) << 8 | Int(header[7])
        let depth = Int(header[8]), colorType = header[9]
        guard let channels = Self.channels[colorType] else { throw unsupported("color type \(colorType)") }
        guard Self.depths[colorType]!.contains(depth) else { throw unsupported("bit depth \(depth)") }
        guard !colorManaged || depth != 16 || transparency.isEmpty else { throw unsupported("bit depth 16 and a tRNS chunk") }
        // actool converts images with a profile other than sRGB IEC61966-2.1 to sRGB, then
        // premultiplies; gray images with a gray profile stay gray (`profiles` experiment).
        let conversion = colorManaged ? try Self.conversion(ancillary, grayImage: [0, 4].contains(colorType), path: path) : nil
        // actool dithers 16-bit samples to 8 bits; nomac reads them only in images it converts
        // from their profile, whose pixels may differ (ADR 0204).
        guard !colorManaged || depth != 16 || conversion != nil else {
            throw unsupported("bit depth 16 without a color profile other than sRGB (actool dithers them)")
        }
        let passes = header[12] == 1 ? Self.adam7 : [(x: 0, y: 0, dx: 1, dy: 1)]
        func passSize(_ pass: (x: Int, y: Int, dx: Int, dy: Int)) -> (width: Int, height: Int, rowBytes: Int) {
            let passWidth = (width - pass.x + pass.dx - 1) / pass.dx, passHeight = (height - pass.y + pass.dy - 1) / pass.dy
            return (passWidth, passHeight, (passWidth * channels * depth + 7) / 8)
        }
        let expected = passes.map(passSize).filter { $0.width > 0 && $0.height > 0 }.reduce(0) { $0 + ($1.rowBytes + 1) * $1.height }
        let raw = try Self.inflate(compressed, expected: expected, path: path)
        var samples = [UInt8](repeating: 0, count: width * height * channels)
        var position = 0
        var stored = Stored(depth: depth, interlaced: header[12] == 1, palette: palette, transparency: transparency)
        if Self.copiedAsIs(bytes) != nil { stored.verbatim = bytes }
        for pass in passes {
            let size = passSize(pass)
            guard size.width > 0, size.height > 0 else { continue }
            let rows = try Self.unfilter(Array(raw[position..<position + (size.rowBytes + 1) * size.height]), rowBytes: size.rowBytes,
                                         height: size.height, pixelBytes: max(1, channels * depth / 8), path: path)
            position += (size.rowBytes + 1) * size.height
            stored.passes.append((size.rowBytes, size.height))
            stored.samples += rows
            if depth == 8 && passes.count == 1 {
                samples = rows
                break
            }
            if depth == 16 {
                for y in 0..<size.height {
                    for x in 0..<size.width {
                        let target = ((pass.y + y * pass.dy) * width + pass.x + x * pass.dx) * channels
                        for channel in 0..<channels {
                            let offset = y * size.rowBytes + (x * channels + channel) * 2
                            samples[target + channel] = rows[offset]
                        }
                    }
                }
                continue
            }
            for y in 0..<size.height {
                for x in 0..<size.width {
                    let target = ((pass.y + y * pass.dy) * width + pass.x + x * pass.dx) * channels
                    for channel in 0..<channels {
                        let bit = (x * channels + channel) * depth
                        let byte = rows[y * size.rowBytes + bit / 8]
                        samples[target + channel] = depth == 8 ? byte : byte >> (8 - depth - bit % 8) & UInt8((1 << depth) - 1)
                    }
                }
            }
        }

        if colorManaged, depth == 16, stride(from: 0, to: samples.count, by: channels).allSatisfy({ samples[$0] == samples[$0 + 1] && samples[$0 + 1] == samples[$0 + 2] }) {
            throw unsupported("bit depth 16 and only gray pixels (actool adds a GA16 rendition)")
        }
        let scale = depth == 16 ? 1 : 255 / ((1 << depth) - 1)
        func key(_ index: Int) -> Int { Int(transparency[index * 2]) << 8 | Int(transparency[index * 2 + 1]) }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var under = 0.0, over = 0.0
        var extended = [Float](repeating: 0, count: conversion.map { $0.isGray } == false ? width * height * 4 : 0)
        var unconverted = conversion == nil ? [] : pixels
        for index in 0..<width * height {
            let source = index * channels
            let red, green, blue, alpha: UInt8
            switch colorType {
            case 0:
                let gray = samples[source]
                (red, green, blue) = (gray * UInt8(scale), gray * UInt8(scale), gray * UInt8(scale))
                alpha = transparency.count >= 2 && Int(gray) == key(0) ? 0 : 255
            case 2:
                (red, green, blue) = (samples[source], samples[source + 1], samples[source + 2])
                let keyed = transparency.count >= 6 && (0..<3).allSatisfy { Int(samples[source + $0]) == key($0) }
                alpha = keyed ? 0 : 255
            case 3:
                let entry = Int(samples[source])
                guard entry * 3 + 2 < palette.count else { throw NomacError("PNG palette index out of range", path: path) }
                (red, green, blue) = (palette[entry * 3], palette[entry * 3 + 1], palette[entry * 3 + 2])
                alpha = entry < transparency.count ? transparency[entry] : 255
            case 4:
                (red, green, blue, alpha) = (samples[source], samples[source], samples[source], samples[source + 1])
            default:
                (red, green, blue, alpha) = (samples[source], samples[source + 1], samples[source + 2], samples[source + 3])
            }
            var (r, g, b) = (red, green, blue)
            if let conversion {
                if conversion.isGray {
                    let gray = conversion.convertGray(red)
                    (r, g, b) = (gray, gray, gray)
                } else {
                    let converted = conversion.convert(red, green, blue)
                    under = max(under, converted.under)
                    over = max(over, converted.over)
                    let wide = conversion.extended(red, green, blue)
                    let scale = Double(alpha) / 255
                    for (offset, value) in [wide.red, wide.green, wide.blue, 1].enumerated() {
                        extended[index * 4 + offset] = Float(value * scale)
                    }
                    (r, g, b) = (converted.red, converted.green, converted.blue)
                }
            }
            func premultiplied(_ color: UInt8) -> UInt8 { UInt8((Int(color) * Int(alpha) + 127) / 255) }
            pixels[index * 4] = premultiplied(b)
            pixels[index * 4 + 1] = premultiplied(g)
            pixels[index * 4 + 2] = premultiplied(r)
            pixels[index * 4 + 3] = alpha
            if conversion != nil {
                unconverted[index * 4] = premultiplied(blue)
                unconverted[index * 4 + 1] = premultiplied(green)
                unconverted[index * 4 + 2] = premultiplied(red)
                unconverted[index * 4 + 3] = alpha
            }
        }
        self.init(width: width, height: height, pixels: pixels)
        // RGB images with colors outside sRGB get a rendition in extended sRGB, 16 bits per
        // channel (display gamut 1), from a linear component below −0.0015 or above 1.0078
        // (`profiles` threshold cases: −0.0012 and 1.0073 add none, −0.0017 and 1.0083 do);
        // palette images never do.
        if (under > 0.0015 || over > 0.0078) && colorType != 3 {
            widePixels = extended.flatMap { value -> [UInt8] in
                let half = Self.half(value)
                return [UInt8(half & 0xFF), UInt8(half >> 8)]
            }
        }
        ancillaryChunks = ancillary
        self.colorType = colorType
        self.stored = stored
        self.iconIsUnwritable = iconIsUnwritable
        declaresAlpha = [4, 6].contains(colorType) || !transparency.isEmpty
        if conversion != nil { unconvertedPixels = unconverted }
    }

    static let channels: [UInt8: Int] = [0: 1, 2: 3, 3: 1, 4: 2, 6: 4]

    /// Four-byte pixels as filter 0 rows of Adam7's passes.
    static func adam7Rows(_ pixels: [UInt8], width: Int, height: Int) -> [[UInt8]] {
        adam7.flatMap { pass in
            stride(from: pass.y, to: height, by: pass.dy).compactMap { y -> [UInt8]? in
                let row = stride(from: pass.x, to: width, by: pass.dx).flatMap { x in pixels[(y * width + x) * 4..<(y * width + x) * 4 + 4] }
                return row.isEmpty ? nil : [0] + row
            }
        }
    }

    /// The bit depths of each color type nomac reads: actool dithers 16-bit samples to 8 bits, and
    /// gives gray images (by color type or by their pixels) a second, `GA16` rendition (`images`
    /// png16 cases; BACKLOG B-209).
    static let depths: [UInt8: Set<Int>] = [0: [1, 2, 4, 8], 2: [8, 16], 3: [1, 2, 4, 8], 4: [8], 6: [8, 16]]



    static func unsupportedProfile(_ what: String, path: String) -> NomacError {
        NomacError("PNG images whose color profile has \(what) are not supported yet (BACKLOG B-213)", path: path)
    }

    /// The profile the pixels convert from (`bad-profiles`): an `sRGB` chunk before any `iCCP`
    /// chunk means none; of those before `PLTE` and the image data, the last one ImageIO can read
    /// and that fits the image. Others leave the image untagged, actool saying nothing of them, and
    /// then a `gAMA` chunk counts.
    static func conversion(_ chunks: [Chunk], grayImage: Bool, path: String) throws -> ICCProfile? {
        let before = chunks.filter { !$0.afterData }
        let candidates = before.filter { !$0.afterPalette && ["iCCP", "sRGB"].contains($0.type) }
        if candidates.first?.type == "iCCP" {
            for chunk in candidates.reversed() where chunk.type == "iCCP" {
                guard let bytes = readableProfile(chunk.data) else { continue }
                if ICCProfile.isStandardSRGB(bytes) { return nil }
                do {
                    let profile = try ICCProfile(bytes)
                    if profile.isGray == grayImage { return profile }
                } catch let error as ICCProfile.Unsupported {
                    if !error.isInvalid { throw unsupportedProfile(error.description, path: path) }
                }
            }
        }
        // An `sRGB` chunk, or a second `gAMA` or one of another length, leaves the gamma out (`png-gamma`).
        let gammas = before.filter { $0.type == "gAMA" }
        guard !before.contains(where: { $0.type == "sRGB" }), gammas.count == 1, gammas[0].data.count == 4 else { return nil }
        func numbers(_ data: [UInt8]) -> [Int] {
            stride(from: 0, to: data.count, by: 4).map { data[$0..<$0 + 4].reduce(0) { $0 << 8 | Int($1) } }
        }
        let chromaticities = before.first { $0.type == "cHRM" && $0.data.count == 32 }.map { numbers($0.data) }
        return ICCProfile(pngGamma: numbers(gammas[0].data)[0], chromaticities: chromaticities, gray: grayImage)
    }

    /// An `iCCP` chunk's profile as ImageIO reads it: a name of 1 to 79 bytes, a NUL, compression
    /// method 0 and a zlib stream whose checksum it does not look at, trailing bytes ignored.
    static func readableProfile(_ chunk: [UInt8]) -> [UInt8]? {
        guard let name = chunk.firstIndex(of: 0), (1...79).contains(name), name + 3 < chunk.count, chunk[name + 1] == 0 else { return nil }
        let first = Int(chunk[name + 2]), second = Int(chunk[name + 3])
        guard first & 0x0F == 8, (first * 256 + second) % 31 == 0 else { return nil }
        return inflated(Array(chunk[(name + 4)...]), windowBits: -15)
    }

    /// The whole of a zlib or raw deflate stream's output; nil when the stream is damaged or cut.
    static func inflated(_ data: [UInt8], windowBits: Int32) -> [UInt8]? {
        var input = data
        var stream = z_stream()
        guard inflateInit2_(&stream, windowBits, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return nil }
        defer { inflateEnd(&stream) }
        var output: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 1 << 14)
        var status = Z_OK
        input.withUnsafeMutableBufferPointer { source in
            stream.next_in = source.baseAddress
            stream.avail_in = UInt32(source.count)
            repeat {
                buffer.withUnsafeMutableBufferPointer { target in
                    stream.next_out = target.baseAddress
                    stream.avail_out = UInt32(target.count)
                    status = CZlib.inflate(&stream, Z_NO_FLUSH)
                }
                output += buffer[..<(buffer.count - Int(stream.avail_out))]
            } while status == Z_OK
        }
        return status == Z_STREAM_END ? output : nil
    }

    static let adam7: [(x: Int, y: Int, dx: Int, dy: Int)] = [
        (0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2),
    ]

    static func inflate(_ input: [UInt8], expected: Int, path: String) throws -> [UInt8] {
        var stream = z_stream()
        guard inflateInit_(&stream, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw NomacError("could not start inflating the PNG", path: path)
        }
        defer { inflateEnd(&stream) }
        var output = [UInt8](repeating: 0, count: expected)
        var input = input
        let status = input.withUnsafeMutableBufferPointer { source in
            output.withUnsafeMutableBufferPointer { target in
                stream.next_in = source.baseAddress
                stream.avail_in = UInt32(source.count)
                stream.next_out = target.baseAddress
                stream.avail_out = UInt32(target.count)
                return CZlib.inflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END, Int(stream.total_out) == expected else {
            throw NomacError("malformed PNG image data", path: path)
        }
        return output
    }

    /// Undoes the five PNG row filters.
    static func unfilter(_ raw: [UInt8], rowBytes: Int, height: Int, pixelBytes: Int, path: String) throws -> [UInt8] {
        var out = [UInt8](repeating: 0, count: rowBytes * height)
        for row in 0..<height {
            let filter = raw[row * (rowBytes + 1)]
            let source = row * (rowBytes + 1) + 1, target = row * rowBytes
            for column in 0..<rowBytes {
                let value = raw[source + column]
                let left = column >= pixelBytes ? Int(out[target + column - pixelBytes]) : 0
                let up = row > 0 ? Int(out[target - rowBytes + column]) : 0
                let upLeft = row > 0 && column >= pixelBytes ? Int(out[target - rowBytes + column - pixelBytes]) : 0
                let predicted: Int
                switch filter {
                case 0: predicted = 0
                case 1: predicted = left
                case 2: predicted = up
                case 3: predicted = (left + up) / 2
                case 4:
                    let estimate = left + up - upLeft
                    let (a, b, c) = (abs(estimate - left), abs(estimate - up), abs(estimate - upLeft))
                    predicted = a <= b && a <= c ? left : (b <= c ? up : upLeft)
                default: throw NomacError("PNG row filter \(filter) does not exist", path: path)
                }
                out[target + column] = value &+ UInt8(truncatingIfNeeded: predicted)
            }
        }
        return out
    }
}
