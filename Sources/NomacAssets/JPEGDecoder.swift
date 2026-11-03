import Foundation
import NomacCore

/// A baseline JPEG's pixels (ITU T.81 sequential DCT, Huffman coded, 8-bit, any sampling, with
/// restart intervals), for nomac's drawing of PDF images that hold one: gray, or RGB from YCbCr
/// unless an Adobe segment says the three components are RGB already.
enum JPEGDecoder {
    /// Pixels row by row from the top, one byte per component.
    static func decode(_ data: [UInt8], path: String) throws -> (width: Int, height: Int, components: Int, pixels: [UInt8]) {
        var decoder = Decoder(data: data, path: path)
        return try decoder.run()
    }

    private struct Component {
        var id: Int
        var horizontal: Int
        var vertical: Int
        var table: Int
        var dc = 0
        var ac = 0
        var blocksWide = 0
        var blocksHigh = 0
        var samples: [UInt8] = []
        var previous = 0
    }

    /// A canonical Huffman table: per code length, the first code, the last and the index of
    /// its first symbol.
    private struct Huffman {
        var first = [Int](repeating: 0, count: 17)
        var last = [Int](repeating: -1, count: 17)
        var offset = [Int](repeating: 0, count: 17)
        var symbols: [UInt8]

        init(counts: [Int], symbols: [UInt8]) {
            self.symbols = symbols
            var code = 0, index = 0
            for length in 1...16 {
                first[length] = code
                offset[length] = index
                code += counts[length - 1]
                index += counts[length - 1]
                last[length] = code - 1
                code <<= 1
            }
        }
    }

    private struct Decoder {
        let data: [UInt8]
        let path: String
        var position = 0
        var quantization: [Int: [Int]] = [:]
        var dcTables: [Int: Huffman] = [:]
        var acTables: [Int: Huffman] = [:]
        var components: [Component] = []
        var width = 0, height = 0
        var restartInterval = 0
        var adobeTransform: Int?
        var bitBuffer = 0, bitCount = 0

        init(data: [UInt8], path: String) {
            self.data = data
            self.path = path
        }

        func error(_ message: String) -> NomacError { NomacError("the PDF has a JPEG image nomac cannot read: \(message)", path: path) }

        mutating func byte() throws -> Int {
            guard position < data.count else { throw error("it ends early") }
            position += 1
            return Int(data[position - 1])
        }

        mutating func word() throws -> Int { try byte() << 8 | byte() }

        mutating func run() throws -> (width: Int, height: Int, components: Int, pixels: [UInt8]) {
            guard try word() == 0xFFD8 else { throw error("no start of image") }
            while true {
                var marker = try byte()
                guard marker == 0xFF else { throw error("a segment without a marker") }
                while marker == 0xFF { marker = try byte() }
                switch marker {
                case 0xD9:
                    throw error("no scan")
                case 0xC0, 0xC1:
                    try frame()
                case 0xC2, 0xC3, 0xC5...0xC7, 0xC9...0xCB, 0xCD...0xCF:
                    throw error("it is not baseline")
                case 0xC4:
                    try huffmanTables()
                case 0xDB:
                    try quantizationTables()
                case 0xDD:
                    _ = try word()
                    restartInterval = try word()
                case 0xEE:
                    let length = try word()
                    let start = position
                    if length >= 14, Array(data[start..<min(start + 5, data.count)]) == Array("Adobe".utf8) { adobeTransform = Int(data[start + 11]) }
                    position = start + length - 2
                case 0xDA:
                    try scan()
                    return try pixels()
                default:
                    position += try word() - 2
                }
            }
        }

        mutating func frame() throws {
            _ = try word()
            guard try byte() == 8 else { throw error("it is not 8-bit") }
            height = try word()
            width = try word()
            let count = try byte()
            guard width > 0, height > 0, count == 1 || count == 3 else { throw error("an unsupported frame") }
            for _ in 0..<count {
                let id = try byte(), sampling = try byte(), table = try byte()
                components.append(Component(id: id, horizontal: max(sampling >> 4, 1), vertical: max(sampling & 15, 1), table: table))
            }
        }

        mutating func huffmanTables() throws {
            let end = position + (try word())
            while position < end {
                let kind = try byte()
                var counts: [Int] = []
                for _ in 0..<16 { counts.append(try byte()) }
                var symbols: [UInt8] = []
                for _ in 0..<counts.reduce(0, +) { symbols.append(UInt8(try byte())) }
                let table = Huffman(counts: counts, symbols: symbols)
                if kind >> 4 == 0 { dcTables[kind & 15] = table } else { acTables[kind & 15] = table }
            }
        }

        mutating func quantizationTables() throws {
            let end = position + (try word())
            while position < end {
                let kind = try byte()
                var values: [Int] = []
                for _ in 0..<64 { values.append(kind >> 4 == 0 ? try byte() : try word()) }
                quantization[kind & 15] = values
            }
        }

        mutating func bit() throws -> Int {
            if bitCount == 0 {
                var value = try byte()
                if value == 0xFF {
                    let next = try byte()
                    if next != 0 { position -= 2; value = 0 }
                }
                bitBuffer = value
                bitCount = 8
            }
            bitCount -= 1
            return (bitBuffer >> bitCount) & 1
        }

        mutating func bits(_ count: Int) throws -> Int {
            var value = 0
            for _ in 0..<count { value = value << 1 | (try bit()) }
            return value
        }

        mutating func symbol(_ table: Huffman) throws -> Int {
            var code = 0
            for length in 1...16 {
                code = code << 1 | (try bit())
                if code <= table.last[length], code >= table.first[length] {
                    let index = table.offset[length] + code - table.first[length]
                    guard index < table.symbols.count else { break }
                    return Int(table.symbols[index])
                }
            }
            throw error("a bad Huffman code")
        }

        static func extend(_ value: Int, _ count: Int) -> Int { count == 0 ? 0 : value < 1 << (count - 1) ? value - (1 << count) + 1 : value }

        mutating func scan() throws {
            _ = try word()
            let count = try byte()
            for _ in 0..<count {
                let id = try byte(), tables = try byte()
                guard let index = components.firstIndex(where: { $0.id == id }) else { throw error("a scan of an unknown component") }
                components[index].dc = tables >> 4
                components[index].ac = tables & 15
            }
            position += 3
            guard count == components.count else { throw error("components in several scans") }
            let maxH = components.map(\.horizontal).max()!, maxV = components.map(\.vertical).max()!
            let unitsWide = (width + 8 * maxH - 1) / (8 * maxH), unitsHigh = (height + 8 * maxV - 1) / (8 * maxV)
            for index in components.indices {
                components[index].blocksWide = unitsWide * components[index].horizontal
                components[index].blocksHigh = unitsHigh * components[index].vertical
                components[index].samples = [UInt8](repeating: 0, count: components[index].blocksWide * 8 * components[index].blocksHigh * 8)
            }
            var units = 0
            for unitY in 0..<unitsHigh {
                for unitX in 0..<unitsWide {
                    if restartInterval > 0, units > 0, units % restartInterval == 0 {
                        bitCount = 0
                        while position + 1 < data.count, !(data[position] == 0xFF && (0xD0...0xD7).contains(data[position + 1])) { position += 1 }
                        position += 2
                        for index in components.indices { components[index].previous = 0 }
                    }
                    for index in components.indices {
                        for v in 0..<components[index].vertical {
                            for h in 0..<components[index].horizontal {
                                try block(index, x: unitX * components[index].horizontal + h, y: unitY * components[index].vertical + v)
                            }
                        }
                    }
                    units += 1
                }
            }
        }

        static let zigzag = [0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21,
                             28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61,
                             54, 47, 55, 62, 63]

        static let cosines: [[Double]] = (0..<8).map { x -> [Double] in
            (0..<8).map { u -> Double in
                let scale: Double = u == 0 ? 1 / 2.0.squareRoot() : 1
                let angle = Double(2 * x + 1) * Double(u) * Double.pi / 16
                return scale * cos(angle)
            }
        }

        mutating func block(_ index: Int, x: Int, y: Int) throws {
            guard let dcTable = dcTables[components[index].dc], let acTable = acTables[components[index].ac],
                  let quantizer = quantization[components[index].table] else { throw error("a missing table") }
            var coefficients = [Double](repeating: 0, count: 64)
            let size = try symbol(dcTable)
            components[index].previous += Self.extend(try bits(size), size)
            coefficients[0] = Double(components[index].previous * quantizer[0])
            var k = 1
            while k < 64 {
                let value = try symbol(acTable)
                let run = value >> 4, length = value & 15
                if length == 0 {
                    if run != 15 { break }
                    k += 16
                    continue
                }
                k += run
                guard k < 64 else { break }
                coefficients[Self.zigzag[k]] = Double(Self.extend(try bits(length), length) * quantizer[k])
                k += 1
            }
            // The inverse DCT, rows then columns.
            var rows = [Double](repeating: 0, count: 64)
            for v in 0..<8 where coefficients[(v * 8)..<(v * 8 + 8)].contains(where: { $0 != 0 }) {
                for column in 0..<8 {
                    var sum = 0.0
                    for u in 0..<8 { sum += Self.cosines[column][u] * coefficients[v * 8 + u] }
                    rows[v * 8 + column] = sum
                }
            }
            let stride = components[index].blocksWide * 8
            for row in 0..<8 {
                for column in 0..<8 {
                    var sum = 0.0
                    for v in 0..<8 { sum += Self.cosines[row][v] * rows[v * 8 + column] }
                    let value = Int((sum / 4 + 128).rounded())
                    components[index].samples[(y * 8 + row) * stride + x * 8 + column] = UInt8(min(max(value, 0), 255))
                }
            }
        }

        func pixels() throws -> (width: Int, height: Int, components: Int, pixels: [UInt8]) {
            let maxH = components.map(\.horizontal).max()!, maxV = components.map(\.vertical).max()!
            var result = [UInt8](repeating: 0, count: width * height * components.count)
            for y in 0..<height {
                for x in 0..<width {
                    var values = components.map { component -> Double in
                        let sx = x * component.horizontal / maxH, sy = y * component.vertical / maxV
                        return Double(component.samples[sy * component.blocksWide * 8 + sx])
                    }
                    if components.count == 3, adobeTransform != 0 {
                        let (luma, blue, red) = (values[0], values[1] - 128, values[2] - 128)
                        values = [luma + 1.402 * red, luma - 0.344136 * blue - 0.714136 * red, luma + 1.772 * blue]
                    }
                    for (channel, value) in values.enumerated() {
                        result[(y * width + x) * components.count + channel] = UInt8(min(max(value.rounded(), 0), 255))
                    }
                }
            }
            return (width, height, components.count, result)
        }
    }
}
