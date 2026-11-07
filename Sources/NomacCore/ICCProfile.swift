import Foundation

/// Color profiles of the matrix/TRC kind (ICC.1:2010, sections 8.3.4.2 and 8.3.3): an RGB
/// profile's three colorants in the D50 profile connection space and three tone curves, or a gray
/// profile's one curve, the forms of every color profile embedded in the corpus's PNGs. actool converts the colors of PNGs whose profile is not sRGB
/// IEC61966-2.1 to that space; nomac converts them with this profile's curves and matrix and
/// sRGB's (docs/formats/asset-catalog.md, "Color profiles"; ADR 0204).
public struct ICCProfile: Sendable {
    /// The colorants as columns: XYZ = matrix × linear RGB (the identity for a gray profile).
    public let matrix: [[Double]]
    public let isGray: Bool
    public let curves: [Curve]
    /// Each channel's 256 decoded values.
    let linear: [[Double]]

    public enum Curve: Sendable {
        case identity
        case gamma(Double)
        case table([Double])
        /// A parametric curve (`para`) of function type 0 to 4 and its parameters.
        case parametric(Int, [Double])

        public func apply(_ x: Double) -> Double {
            switch self {
            case .identity: return x
            case .gamma(let g): return pow(x, g)
            case .table(let values):
                let position = min(max(x, 0), 1) * Double(values.count - 1)
                let low = Int(position.rounded(.down)), high = min(low + 1, values.count - 1)
                return values[low] + (values[high] - values[low]) * (position - Double(low))
            case .parametric(let type, let p):
                switch type {
                case 0: return pow(x, p[0])
                case 1: return x >= -p[2] / p[1] ? pow(p[1] * x + p[2], p[0]) : 0
                case 2: return x >= -p[2] / p[1] ? pow(p[1] * x + p[2], p[0]) + p[3] : p[3]
                case 3: return x >= p[4] ? pow(p[1] * x + p[2], p[0]) : p[3] * x
                default: return x >= p[4] ? pow(p[1] * x + p[2], p[0]) + p[5] : p[3] * x + p[6]
                }
            }
        }
    }

    /// A profile nomac cannot convert with; `isInvalid` when ColorSync does not use it either and
    /// the image counts as untagged (`bad-profiles`).
    public struct Unsupported: Error, CustomStringConvertible {
        public var description: String
        public var isInvalid = false
    }

    public init(_ data: [UInt8]) throws {
        func u32(_ offset: Int) -> UInt32 { data[offset..<offset + 4].reduce(0) { $0 << 8 | UInt32($1) } }
        func s15(_ offset: Int) -> Double { Double(Int32(bitPattern: u32(offset))) / 65536 }
        func invalid(_ what: String) -> Unsupported { Unsupported(description: what, isInvalid: true) }
        guard data.count >= 132, Int(u32(0)) == data.count, data[36..<40].elementsEqual(Array("acsp".utf8)) else { throw invalid("not an ICC profile") }
        isGray = data[16..<20].elementsEqual(Array("GRAY".utf8))
        var tags: [String: (offset: Int, size: Int)] = [:]
        for index in 0..<Int(u32(128)) {
            let entry = 132 + 12 * index
            guard entry + 12 <= data.count else { throw invalid("a truncated tag table") }
            let offset = Int(u32(entry + 4)), size = Int(u32(entry + 8))
            guard offset + size <= data.count else { throw invalid("a truncated tag") }
            tags[String(decoding: data[entry..<entry + 4], as: UTF8.self)] = (offset, size)
        }
        if let lut = ["A2B0", "A2B1", "B2A0"].first(where: { tags[$0] != nil }) {
            throw Unsupported(description: "a \(lut) table")
        }
        // Versions 2 and 4 of monitor and input classes, RGB or gray to XYZ (`bad-profiles`).
        guard [2, 4].contains(data[8]), ["mntr", "scnr"].contains(String(decoding: data[12..<16], as: UTF8.self)),
              isGray || data[16..<20].elementsEqual(Array("RGB ".utf8)), data[20..<24].elementsEqual(Array("XYZ ".utf8)) else {
            throw invalid("a profile other than a version 2 or 4 monitor or input one, RGB or gray to XYZ")
        }
        var columns: [[Double]] = isGray ? [[1, 0, 0], [0, 1, 0], [0, 0, 1]] : []
        for name in isGray ? [] : ["rXYZ", "gXYZ", "bXYZ"] {
            guard let tag = tags[name], tag.size >= 20, data[tag.offset..<tag.offset + 4].elementsEqual(Array("XYZ ".utf8)) else {
                throw invalid("no \(name) colorant")
            }
            columns.append([s15(tag.offset + 8), s15(tag.offset + 12), s15(tag.offset + 16)])
        }
        matrix = (0..<3).map { row in columns.map { $0[row] } }
        curves = try (isGray ? ["kTRC"] : ["rTRC", "gTRC", "bTRC"]).map { name in
            guard let tag = tags[name], tag.size >= 12 else { throw invalid("no \(name) curve") }
            let type = String(decoding: data[tag.offset..<tag.offset + 4], as: UTF8.self)
            switch type {
            case "curv":
                let count = Int(u32(tag.offset + 8))
                guard tag.size >= 12 + 2 * count else { throw invalid("a truncated curve") }
                func entry(_ index: Int) -> UInt16 { UInt16(data[tag.offset + 12 + 2 * index]) << 8 | UInt16(data[tag.offset + 13 + 2 * index]) }
                switch count {
                case 0: return .identity
                case 1: return .gamma(Double(entry(0)) / 256)
                default: return .table((0..<count).map { Double(entry($0)) / 65535 })
                }
            case "para":
                let function = Int(data[tag.offset + 8]) << 8 | Int(data[tag.offset + 9])
                let counts = [1, 3, 4, 5, 7]
                guard function < counts.count, tag.size >= 12 + 4 * counts[function] else { throw Unsupported(description: "parametric curve type \(function)") }
                return .parametric(function, (0..<counts[function]).map { s15(tag.offset + 12 + 4 * $0) })
            default:
                throw Unsupported(description: "a \(type) curve")
            }
        }
        linear = curves.map { curve in (0..<256).map { curve.apply(Double($0) / 255) } }
    }

    /// The SHA-256 of the sRGB IEC61966-2.1 profile but its 128-byte header: actool stores the
    /// colors of images with this profile as they are (flappy-fly-bird's, nextcloud's and
    /// retro-rampage's) and converts those of color images with other profiles (`pngforms`
    /// profile checks).
    public static let standardSRGBBody = "2c4d46e1e255995e1d2592fecec4d8bf7e1dc78179a1cbf2d607301debc630b3"

    public static func isStandardSRGB(_ profile: [UInt8]) -> Bool {
        profile.count > 128 && SHA256.digest(Array(profile[128...])).map { String(format: "%02x", $0) }.joined() == standardSRGBBody
    }

    /// sRGB IEC61966-2.1's colorants in the D50 connection space, as s15Fixed16 numbers.
    static let sRGBMatrix: [[Double]] = [[0.4361, 0.3851, 0.1431], [0.2225, 0.7169, 0.0606], [0.0139, 0.0971, 0.7141]]
        .map { $0.map { ($0 * 65536).rounded() / 65536 } }

    /// The 8-bit sRGB values of each 8-bit value of this profile's channels: decoded by its
    /// curves, to XYZ by its colorants, to linear sRGB by sRGB's inverted colorants, clamped,
    /// encoded by sRGB's curve and rounded to the nearest (`profiles` experiment: 63 to 92% of a
    /// million colors as actool converts them, the others within 1, rarely 2); and how far the
    /// linear sRGB value lies outside 0 to 1 before the clamping.
    /// The color in sRGB, clamped, and how far its linear components fall below 0 (`under`) and
    /// above 1 (`over`).
    public func convert(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> (red: UInt8, green: UInt8, blue: UInt8, under: Double, over: Double) {
        let r = linear[0][Int(red)], g = linear[1][Int(green)], b = linear[2][Int(blue)]
        let x = matrix[0][0] * r + matrix[0][1] * g + matrix[0][2] * b
        let y = matrix[1][0] * r + matrix[1][1] * g + matrix[1][2] * b
        let z = matrix[2][0] * r + matrix[2][1] * g + matrix[2][2] * b
        let inverse = Self.sRGBInverse
        var under = 0.0, over = 0.0
        func encoded(_ row: Int) -> UInt8 {
            let unclamped = inverse[row][0] * x + inverse[row][1] * y + inverse[row][2] * z
            under = max(under, -unclamped)
            over = max(over, unclamped - 1)
            return Self.encode(min(max(unclamped, 0), 1))
        }
        return (encoded(0), encoded(1), encoded(2), under, over)
    }

    /// The color in extended sRGB: sRGB's components without clamping, each encoded by sRGB's
    /// curve mirrored for negative values, as actool's 16-bit display-gamut renditions hold them
    /// (B-213, `profiles` p3 cases: Display P3 red is (1.093, −0.227, −0.150)).
    public func extended(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> (red: Double, green: Double, blue: Double) {
        let r = linear[0][Int(red)], g = linear[1][Int(green)], b = linear[2][Int(blue)]
        let x = matrix[0][0] * r + matrix[0][1] * g + matrix[0][2] * b
        let y = matrix[1][0] * r + matrix[1][1] * g + matrix[1][2] * b
        let z = matrix[2][0] * r + matrix[2][1] * g + matrix[2][2] * b
        func encoded(_ row: Int) -> Double {
            let value = Self.sRGBInverse[row][0] * x + Self.sRGBInverse[row][1] * y + Self.sRGBInverse[row][2] * z
            let magnitude = abs(value) <= 0.0031308 ? 12.92 * abs(value) : 1.055 * pow(abs(value), 1 / 2.4) - 0.055
            return value < 0 ? -magnitude : magnitude
        }
        return (encoded(0), encoded(1), encoded(2))
    }

    /// A gray profile's value as an sRGB gray: decoded by its curve, encoded by sRGB's (`profiles`
    /// probes: 240 of 256 values as actool converts them, the others within 1).
    public func convertGray(_ gray: UInt8) -> UInt8 {
        Self.encode(min(max(linear[0][Int(gray)], 0), 1))
    }

    static func encode(_ value: Double) -> UInt8 {
        let encoded = value <= 0.0031308 ? 12.92 * value : 1.055 * pow(value, 1 / 2.4) - 0.055
        return UInt8(min(max((encoded * 255).rounded(), 0), 255))
    }

    static let sRGBInverse: [[Double]] = {
        let m = sRGBMatrix
        let determinant = m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
            + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
        return [
            [(m[1][1] * m[2][2] - m[1][2] * m[2][1]) / determinant, (m[0][2] * m[2][1] - m[0][1] * m[2][2]) / determinant, (m[0][1] * m[1][2] - m[0][2] * m[1][1]) / determinant],
            [(m[1][2] * m[2][0] - m[1][0] * m[2][2]) / determinant, (m[0][0] * m[2][2] - m[0][2] * m[2][0]) / determinant, (m[0][2] * m[1][0] - m[0][0] * m[1][2]) / determinant],
            [(m[1][0] * m[2][1] - m[1][1] * m[2][0]) / determinant, (m[0][1] * m[2][0] - m[0][0] * m[2][1]) / determinant, (m[0][0] * m[1][1] - m[0][1] * m[1][0]) / determinant],
        ]
    }()
}
