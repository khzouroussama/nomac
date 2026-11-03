import CZlib
import Foundation
import NomacCore

/// A PNG decoded to the pixels actool stores, in the forms its outputs have been observed for
/// (docs/adr/0202-png-decoding.md): gray, RGB, palette, gray and alpha, RGBA; bit depths below 8
/// for gray and palettes, scaled to 0–255; `tRNS` keys; Adam7 interlacing.
struct PNGImage: Equatable {
    let width: Int
    let height: Int
    /// BGRA with each color premultiplied by alpha as (c × a + 127) / 255, rows from the top.
    let pixels: [UInt8]
    /// The chunks other than `IHDR`, `PLTE`, `tRNS`, `IDAT` and `IEND`, in file order, which the
    /// icon PNGs actool writes carry over (`IconPNG`).
    var ancillaryChunks: [Chunk] = []
    /// The `IHDR` color type: 0 gray, 2 RGB, 3 palette, 4 gray and alpha, 6 RGBA.
    var colorType: UInt8 = 6
    /// An 8-bit gray or gray-and-alpha image's own samples, without `tRNS`, which actool's
    /// icon PNGs keep (`IconPNG`).
    var graySamples: [UInt8]?
    /// For an image converted from its color profile to sRGB (ADR 0204): the pixels before the
    /// conversion, which the icon PNGs keep, and the profile's name and bytes.
    var unconvertedPixels: [UInt8]?
    var profile: Profile?

    struct Profile: Equatable {
        var name: [UInt8]
        var data: [UInt8]
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

    init(data bytes: [UInt8], path: String) throws {
        func unsupported(_ what: String) -> NomacError {
            NomacError("PNG images with \(what) are not supported yet (BACKLOG B-209)", path: path)
        }
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard bytes.count > 8, Array(bytes[0..<8]) == signature else { throw NomacError("not a PNG file", path: path) }
        func u32(_ offset: Int) -> Int {
            Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
        }
        var header: [UInt8] = []
        var palette: [UInt8] = []
        var transparency: [UInt8] = []
        var gamma: Int?
        var compressed: [UInt8] = []
        var ancillary: [Chunk] = []
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
                if type == "gAMA" && length == 4 { gamma = u32(offset + 8) }
                ancillary.append(Chunk(type: type, data: body))
            }
            offset += 12 + length
        }
        guard header.count == 13 else { throw NomacError("PNG without a header", path: path) }
        let width = Int(header[0]) << 24 | Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
        let height = Int(header[4]) << 24 | Int(header[5]) << 16 | Int(header[6]) << 8 | Int(header[7])
        let depth = Int(header[8]), colorType = header[9]
        guard let channels = Self.channels[colorType] else { throw unsupported("color type \(colorType)") }
        guard Self.depths[colorType]!.contains(depth) else { throw unsupported("bit depth \(depth)") }
        guard depth != 16 || transparency.isEmpty else { throw unsupported("bit depth 16 and a tRNS chunk") }
        if let gamma, !Self.ignoredGammas.contains(gamma) { throw unsupported("gamma \(gamma)") }
        // actool converts images with a profile other than sRGB IEC61966-2.1 to sRGB, then
        // premultiplies; gray images with a gray profile stay gray (`profiles` experiment).
        var conversion: ICCProfile?
        var profileBytes: [UInt8] = []
        if let chunk = ancillary.first(where: { $0.type == "iCCP" }) {
            profileBytes = try Self.profile(chunk.data, path: path)
            if !ICCProfile.isStandardSRGB(profileBytes) {
                do { conversion = try ICCProfile(profileBytes) } catch let error as ICCProfile.Unsupported {
                    throw Self.unsupportedProfile(error.description, path: path)
                }
                guard conversion!.isGray == [0, 4].contains(colorType) else {
                    throw Self.unsupportedProfile("a color space other than the image's", path: path)
                }
            }
        }
        // actool dithers 16-bit samples to 8 bits; nomac reads them only in images it converts
        // from their profile, whose pixels may differ (ADR 0204).
        guard depth != 16 || conversion != nil else {
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
        for pass in passes {
            let size = passSize(pass)
            guard size.width > 0, size.height > 0 else { continue }
            let rows = try Self.unfilter(Array(raw[position..<position + (size.rowBytes + 1) * size.height]), rowBytes: size.rowBytes,
                                         height: size.height, pixelBytes: max(1, channels * depth / 8), path: path)
            position += (size.rowBytes + 1) * size.height
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

        if depth == 16, stride(from: 0, to: samples.count, by: channels).allSatisfy({ samples[$0] == samples[$0 + 1] && samples[$0 + 1] == samples[$0 + 2] }) {
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
        declaresAlpha = [4, 6].contains(colorType) || !transparency.isEmpty
        if conversion != nil, let chunk = ancillary.first(where: { $0.type == "iCCP" }) {
            unconvertedPixels = unconverted
            profile = Profile(name: Array(chunk.data[..<chunk.data.firstIndex(of: 0)!]), data: profileBytes)
            ancillaryChunks = ancillary.filter { $0.type != "iCCP" }
        }
        if [0, 4].contains(colorType) && depth == 8 && transparency.isEmpty {
            graySamples = samples
        }
    }

    static let channels: [UInt8: Int] = [0: 1, 2: 3, 3: 1, 4: 2, 6: 4]

    /// The bit depths of each color type nomac reads: actool dithers 16-bit samples to 8 bits, and
    /// gives gray images (by color type or by their pixels) a second, `GA16` rendition (`images`
    /// png16 cases; BACKLOG B-209).
    static let depths: [UInt8: Set<Int>] = [0: [1, 2, 4, 8], 2: [8, 16], 3: [1, 2, 4, 8], 4: [8], 6: [8, 16]]



    static func unsupportedProfile(_ what: String, path: String) -> NomacError {
        NomacError("PNG images whose color profile has \(what) are not supported yet (BACKLOG B-213)", path: path)
    }

    /// An `iCCP` chunk's profile: its name, a NUL, the compression method and the zlib stream.
    static func profile(_ chunk: [UInt8], path: String) throws -> [UInt8] {
        guard let name = chunk.firstIndex(of: 0), name + 2 < chunk.count else { throw NomacError("malformed iCCP chunk", path: path) }
        var input = Array(chunk[(name + 2)...])
        var stream = z_stream()
        guard inflateInit_(&stream, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw NomacError("could not start inflating the color profile", path: path)
        }
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
        guard status == Z_STREAM_END else { throw NomacError("malformed iCCP chunk", path: path) }
        return output
    }

    /// `gAMA` values actool leaves the pixels alone for (1/2.2); a gamma of 0.5 or 1.0 changes them.
    static let ignoredGammas: Set<Int> = [45_454, 45_455]

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
