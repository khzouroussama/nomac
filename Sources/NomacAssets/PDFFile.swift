import CZlib
import Foundation
import NomacCore

/// A PDF value, as the file writes it.
indirect enum PDFValue: Equatable {
    case null
    case bool(Bool)
    case integer(Int)
    case real(Double)
    case string([UInt8])
    case name(String)
    case array([PDFValue])
    case dictionary([String: PDFValue])
    case reference(Int)
    case stream([String: PDFValue], [UInt8])

    var number: Double? {
        switch self {
        case .integer(let value): Double(value)
        case .real(let value): value
        default: nil
        }
    }

    var dictionary: [String: PDFValue]? {
        switch self {
        case .dictionary(let value), .stream(let value, _): value
        default: nil
        }
    }

    var array: [PDFValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var name: String? {
        if case .name(let value) = self { return value }
        return nil
    }
}

/// The objects of a PDF file: the last definition of each number, those of object streams
/// included, and the trailer's catalog. Enough to read the first page of an image set's PDF.
struct PDFFile {
    private(set) var objects: [Int: PDFValue] = [:]
    private(set) var root: Int?
    private(set) var info: Int?
    /// The trailer's `/ID`.
    private(set) var identifiers: [PDFValue]?
    let path: String

    init(data: [UInt8], path: String) throws {
        self.path = path
        guard data.prefix(1024).firstRange(of: Array("%PDF-".utf8)) != nil else {
            throw NomacError("not a PDF file", path: path)
        }
        var lexer = PDFLexer(data: data, path: path)
        var position = 0
        let objMarker = Array(" obj".utf8)
        while let range = data[position...].firstRange(of: objMarker) {
            position = range.upperBound
            guard let start = Self.objectStart(data, before: range.lowerBound) else { continue }
            lexer.position = start
            guard case .integer(let number)? = try? lexer.token(), case .integer? = try? lexer.token(), lexer.keyword() == "obj" else { continue }
            guard let value = try? lexer.value(objects: nil) else { continue }
            objects[number] = value
            position = max(position, lexer.position)
        }
        var trailers: [[String: PDFValue]] = objects.values.compactMap { value in
            guard case .stream(let dictionary, _) = value, dictionary["Type"]?.name == "XRef" else { return nil }
            return dictionary
        }
        for (_, value) in objects {
            guard case .stream(let dictionary, _) = value, dictionary["Type"]?.name == "ObjStm" else { continue }
            try readObjectStream(value, path: path)
        }
        // Every trailer, in file order, a later one overriding the entries it has: a linearized
        // file's Info is in its first-page trailer only (corpus: cwa's Adobe-made icons).
        var searched = 0
        while let trailer = data[searched...].firstRange(of: Array("trailer".utf8)) {
            searched = trailer.upperBound
            lexer.position = trailer.upperBound
            if case .dictionary(let dictionary)? = try? lexer.value(objects: nil) { trailers.append(dictionary) }
        }
        for trailer in trailers {
            if case .reference(let catalog)? = trailer["Root"] { root = catalog }
            if case .reference(let number)? = trailer["Info"] { info = number }
            if let ids = trailer["ID"]?.array { identifiers = ids }
        }
        if root == nil {
            root = objects.first { $0.value.dictionary?["Type"]?.name == "Catalog" }?.key
        }
    }

    /// Where the object number before ` obj` at `end` starts: two integers separated by
    /// whitespace, at the start of a line or after whitespace.
    private static func objectStart(_ data: [UInt8], before end: Int) -> Int? {
        var index = end
        func skip(_ predicate: (UInt8) -> Bool) { while index > 0, predicate(data[index - 1]) { index -= 1 } }
        let digit: (UInt8) -> Bool = { (48...57).contains($0) }
        let space: (UInt8) -> Bool = { PDFLexer.isWhitespace($0) }
        let generationEnd = index
        skip(digit)
        guard index < generationEnd else { return nil }
        let generationStart = index
        skip(space)
        guard index < generationStart else { return nil }
        let numberEnd = index
        skip(digit)
        // After whitespace, `>` or an `endobj` with nothing between (corpus: firefox's Illustrator files).
        let afterEndObj = index >= 6 && Array(data[(index - 6)..<index]) == Array("endobj".utf8)
        guard index < numberEnd, index == 0 || space(data[index - 1]) || data[index - 1] == UInt8(ascii: ">") || afterEndObj else { return nil }
        return index
    }

    private mutating func readObjectStream(_ value: PDFValue, path: String) throws {
        guard case .stream(let dictionary, _) = value, case .integer(let count)? = dictionary["N"], case .integer(let first)? = dictionary["First"] else { return }
        let data = try decodedStream(value)
        var lexer = PDFLexer(data: data, path: path)
        var pairs: [(Int, Int)] = []
        for _ in 0..<count {
            guard case .integer(let number) = try lexer.token(), case .integer(let offset) = try lexer.token() else { break }
            pairs.append((number, offset))
        }
        for (number, offset) in pairs where objects[number] == nil {
            lexer.position = first + offset
            if let object = try? lexer.value(objects: nil) { objects[number] = object }
        }
    }

    /// `value` with indirect references followed.
    func resolve(_ value: PDFValue?) -> PDFValue? {
        var value = value
        var depth = 0
        while case .reference(let number)? = value, depth < 32 {
            value = objects[number]
            depth += 1
        }
        return value
    }

    func number(_ value: PDFValue?) -> Double? { resolve(value)?.number }

    /// The first page's dictionary, its inherited entries (resources, boxes, rotation) merged in.
    func firstPage() throws -> [String: PDFValue] {
        guard let root, let catalog = resolve(.reference(root))?.dictionary, var node = resolve(catalog["Pages"])?.dictionary else {
            throw NomacError("the PDF has no page tree", path: path)
        }
        var inherited: [String: PDFValue] = [:]
        for _ in 0..<64 {
            for key in ["Resources", "MediaBox", "CropBox", "Rotate"] where node[key] != nil { inherited[key] = node[key] }
            guard node["Type"]?.name != "Page", let kids = resolve(node["Kids"])?.array, let kid = resolve(kids.first)?.dictionary else {
                return inherited.merging(node) { $1 }
            }
            node = kid
        }
        throw NomacError("the PDF's page tree is too deep", path: path)
    }

    /// A stream's data, decoded by its filters (FlateDecode with PNG or TIFF predictors).
    func decodedStream(_ value: PDFValue) throws -> [UInt8] {
        guard case .stream(let dictionary, let raw) = value else { throw NomacError("expected a PDF stream", path: path) }
        var data = raw
        let filters: [PDFValue] = resolve(dictionary["Filter"]).map { $0.array ?? [$0] } ?? []
        let parameters: [PDFValue?] = resolve(dictionary["DecodeParms"]).map { $0.array?.map { Optional($0) } ?? [$0] } ?? []
        for (index, filter) in filters.enumerated() {
            switch resolve(filter)?.name {
            case "FlateDecode", "Fl":
                data = try Self.inflate(data, path: path)
                if let parameters = resolve(parameters.indices.contains(index) ? parameters[index] : nil)?.dictionary {
                    data = try Self.unpredict(data, parameters: parameters, path: path)
                }
            case let name:
                throw NomacError("PDF streams with the \(name ?? "unnamed") filter are not supported yet (BACKLOG B-215)", path: path)
            }
        }
        return data
    }

    static func inflate(_ data: [UInt8], path: String) throws -> [UInt8] {
        var stream = z_stream()
        guard inflateInit_(&stream, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw NomacError("zlib failed", path: path) }
        defer { inflateEnd(&stream) }
        var input = data
        var output: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 65536)
        var status: Int32 = Z_OK
        input.withUnsafeMutableBufferPointer { source in
            stream.next_in = source.baseAddress
            stream.avail_in = uInt(source.count)
            repeat {
                buffer.withUnsafeMutableBufferPointer { target in
                    stream.next_out = target.baseAddress
                    stream.avail_out = uInt(target.count)
                    status = CZlib.inflate(&stream, Z_NO_FLUSH)
                    output.append(contentsOf: target[0..<(target.count - Int(stream.avail_out))])
                }
            } while status == Z_OK && (stream.avail_in > 0 || stream.avail_out == 0)
        }
        // Like Quartz, a stream whose end is missing or damaged keeps what decoded.
        guard status == Z_STREAM_END || status == Z_OK || status == Z_BUF_ERROR || !output.isEmpty else {
            throw NomacError("could not decompress a PDF stream", path: path)
        }
        return output
    }

    private static func unpredict(_ data: [UInt8], parameters: [String: PDFValue], path: String) throws -> [UInt8] {
        let predictor = parameters["Predictor"]?.number.map(Int.init) ?? 1
        guard predictor >= 10 else {
            guard predictor == 1 else { throw NomacError("PDF TIFF predictors are not supported yet (BACKLOG B-215)", path: path) }
            return data
        }
        let colors = parameters["Colors"]?.number.map(Int.init) ?? 1
        let bits = parameters["BitsPerComponent"]?.number.map(Int.init) ?? 8
        let columns = parameters["Columns"]?.number.map(Int.init) ?? 1
        let bytesPerPixel = max(1, colors * bits / 8)
        let rowLength = (colors * bits * columns + 7) / 8
        var output: [UInt8] = []
        var previous = [UInt8](repeating: 0, count: rowLength)
        var index = 0
        while index + 1 + rowLength <= data.count {
            let filter = data[index]
            var row = Array(data[(index + 1)..<(index + 1 + rowLength)])
            for i in 0..<rowLength {
                let left = i >= bytesPerPixel ? Int(row[i - bytesPerPixel]) : 0
                let up = Int(previous[i])
                let upLeft = i >= bytesPerPixel ? Int(previous[i - bytesPerPixel]) : 0
                let add: Int
                switch filter {
                case 0: add = 0
                case 1: add = left
                case 2: add = up
                case 3: add = (left + up) / 2
                case 4:
                    let p = left + up - upLeft
                    let (pa, pb, pc) = (abs(p - left), abs(p - up), abs(p - upLeft))
                    add = pa <= pb && pa <= pc ? left : (pb <= pc ? up : upLeft)
                default: throw NomacError("malformed PNG predictor in a PDF stream", path: path)
                }
                row[i] = UInt8((Int(row[i]) + add) & 0xFF)
            }
            output += row
            previous = row
            index += 1 + rowLength
        }
        return output
    }
}

/// The tokens and values of PDF syntax (ISO 32000-1, 7.2 and 7.3).
struct PDFLexer {
    let data: [UInt8]
    let path: String
    var position = 0

    init(data: [UInt8], path: String) {
        self.data = data
        self.path = path
    }

    enum Token: Equatable {
        case integer(Int)
        /// A real as a content stream's operand, and as a value of the file's objects.
        case real(Double, object: Double)
        case name(String)
        case string([UInt8])
        case arrayStart, arrayEnd, dictionaryStart, dictionaryEnd
        case keyword(String)
    }

    static func isWhitespace(_ byte: UInt8) -> Bool { [0, 9, 10, 12, 13, 32].contains(byte) }
    static func isDelimiter(_ byte: UInt8) -> Bool { Array("()<>[]{}/%".utf8).contains(byte) }

    mutating func skipWhitespace() {
        while position < data.count {
            if Self.isWhitespace(data[position]) {
                position += 1
            } else if data[position] == UInt8(ascii: "%") {
                while position < data.count, data[position] != 10, data[position] != 13 { position += 1 }
            } else {
                return
            }
        }
    }

    /// The keyword at the current position, consumed, or `nil` (the position kept).
    mutating func keyword() -> String? {
        let saved = position
        if case .keyword(let word)? = try? token() { return word }
        position = saved
        return nil
    }

    mutating func token() throws -> Token? {
        skipWhitespace()
        guard position < data.count else { return nil }
        let byte = data[position]
        switch byte {
        case UInt8(ascii: "["): position += 1; return .arrayStart
        case UInt8(ascii: "]"): position += 1; return .arrayEnd
        case UInt8(ascii: "<"):
            if position + 1 < data.count, data[position + 1] == UInt8(ascii: "<") { position += 2; return .dictionaryStart }
            return .string(hexString())
        case UInt8(ascii: ">"):
            if position + 1 < data.count, data[position + 1] == UInt8(ascii: ">") { position += 2; return .dictionaryEnd }
            position += 1
            return .keyword(">")
        case UInt8(ascii: "("): return .string(literalString())
        case UInt8(ascii: "/"): return .name(name())
        default:
            var end = position
            while end < data.count, !Self.isWhitespace(data[end]), !Self.isDelimiter(data[end]) { end += 1 }
            if end == position { end += 1 }
            let bytes = data[position..<end]
            position = end
            return Self.number(bytes) ?? .keyword(String(decoding: bytes, as: UTF8.self))
        }
    }

    /// A PDF number: digits with an optional sign and at most one period; anything else (an
    /// exponent, two periods) is not one (`numbers` exponent case: Quartz drops the operator).
    /// A content stream's real operand is read as Quartz reads it, not rounded once: its digits,
    /// the fraction's trailing zeros included, as an integer times 10 to the minus the
    /// fraction's length. Correctly rounded reals put values exactly half way after a
    /// translation on the other side: of the 2,287 such coordinates in the corpus files nomac
    /// writes otherwise than actool, this reading reproduces 2,267 (cwa's `Stars_half.pdf`:
    /// 22.054075 − 2.215820 is written 19.83825; firefox's `firefoxLoader.pdf`: 100.911980 −
    /// 0.002930 is 100.909, and `logo_mastercard.pdf`: 0.000000 + 186.781250 is 186.7812; the
    /// rest B-216). A real in the file's objects is correctly rounded (`shadings` axial-fn3: a
    /// stitching function's bound 0.3, read as 3 × 0.1, puts a sample half way the other side).
    static func number(_ bytes: ArraySlice<UInt8>) -> Token? {
        // Read from the bytes where the digits fit: an integer below 10^18, a real's digits below
        // 10^15, which a Double holds exactly, as `number(_: String)` reads them.
        var index = bytes.startIndex
        let negative = index < bytes.endIndex && bytes[index] == UInt8(ascii: "-")
        if index < bytes.endIndex, bytes[index] == UInt8(ascii: "-") || bytes[index] == UInt8(ascii: "+") { index += 1 }
        var digits: UInt64 = 0, count = 0, fraction = 0, period = false
        for byte in bytes[index...] {
            if byte == UInt8(ascii: ".") {
                guard !period else { return nil }
                period = true
            } else {
                guard (48...57).contains(byte) else { return nil }
                if count < 18 { digits = digits * 10 + UInt64(byte - 48) }
                count += 1
                if period { fraction += 1 }
            }
        }
        guard count > 0 else { return nil }
        if !period, count <= 18 { return .integer(negative ? -Int(digits) : Int(digits)) }
        let word = String(decoding: bytes, as: UTF8.self)
        guard period, count <= 15 else { return number(word) }
        let mantissa = Double(digits)
        let value = fraction == 0 ? mantissa : mantissa * negativePowers[fraction]
        return .real(negative ? -value : value, object: Double(word) ?? value)
    }

    static func number(_ word: String) -> Token? {
        var body = Substring(word)
        let negative = body.first == "-"
        if body.first == "+" || body.first == "-" { body = body.dropFirst() }
        guard !body.isEmpty, body.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }), body.filter({ $0 == "." }).count <= 1,
              body != "." else { return nil }
        if !word.contains("."), let value = Int(word) { return .integer(value) }
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        let fraction = parts.count > 1 ? parts[1] : ""
        let digits = String(parts[0]) + fraction
        guard let mantissa = Double(digits.isEmpty ? "0" : digits) else { return nil }
        let value = fraction.isEmpty ? mantissa : mantissa * (fraction.count < negativePowers.count ? negativePowers[fraction.count] : pow(10, -Double(fraction.count)))
        return .real(negative ? -value : value, object: Double(word) ?? value)
    }

    /// A real of the file's objects read again as a content stream's operand, from its shortest
    /// decimal form: Quartz reads the page's box, form and pattern matrices and bounding boxes,
    /// and shading coordinates so (corpus: kickstarter's `icon-globe.pdf`, 31.200195 is written
    /// 31.20019; a firefox pattern's -56.545895 -56.54589), a function's numbers correctly
    /// rounded (`shadings` axial-fn3).
    static func contentReading(_ value: Double) -> Double {
        if case .real(let reading, _)? = number(String(value)) { return reading }
        return value
    }

    private static let negativePowers: [Double] = [1, 1e-1, 1e-2, 1e-3, 1e-4, 1e-5, 1e-6, 1e-7, 1e-8, 1e-9, 1e-10, 1e-11, 1e-12, 1e-13, 1e-14,
                                                    1e-15, 1e-16, 1e-17, 1e-18, 1e-19, 1e-20, 1e-21, 1e-22]

    private mutating func name() -> String {
        position += 1
        var bytes: [UInt8] = []
        while position < data.count, !Self.isWhitespace(data[position]), !Self.isDelimiter(data[position]) {
            if data[position] == UInt8(ascii: "#"), position + 2 < data.count,
               let value = UInt8(String(decoding: data[(position + 1)...(position + 2)], as: UTF8.self), radix: 16) {
                bytes.append(value)
                position += 3
            } else {
                bytes.append(data[position])
                position += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private mutating func hexString() -> [UInt8] {
        position += 1
        var digits: [UInt8] = []
        while position < data.count, data[position] != UInt8(ascii: ">") {
            if !Self.isWhitespace(data[position]) { digits.append(data[position]) }
            position += 1
        }
        position += 1
        if digits.count % 2 == 1 { digits.append(UInt8(ascii: "0")) }
        return stride(from: 0, to: digits.count, by: 2).compactMap { UInt8(String(decoding: digits[$0...($0 + 1)], as: UTF8.self), radix: 16) }
    }

    private mutating func literalString() -> [UInt8] {
        position += 1
        var bytes: [UInt8] = []
        var depth = 1
        while position < data.count {
            let byte = data[position]
            position += 1
            switch byte {
            case UInt8(ascii: "("): depth += 1; bytes.append(byte)
            case UInt8(ascii: ")"):
                depth -= 1
                if depth == 0 { return bytes }
                bytes.append(byte)
            case UInt8(ascii: "\\"):
                guard position < data.count else { return bytes }
                let next = data[position]
                position += 1
                switch next {
                case UInt8(ascii: "n"): bytes.append(10)
                case UInt8(ascii: "r"): bytes.append(13)
                case UInt8(ascii: "t"): bytes.append(9)
                case UInt8(ascii: "b"): bytes.append(8)
                case UInt8(ascii: "f"): bytes.append(12)
                case 13: if position < data.count, data[position] == 10 { position += 1 }
                case 10: break
                case UInt8(ascii: "0")...UInt8(ascii: "7"):
                    var value = Int(next - 48)
                    for _ in 0..<2 where position < data.count && (48...55).contains(data[position]) {
                        value = value * 8 + Int(data[position] - 48)
                        position += 1
                    }
                    bytes.append(UInt8(value & 0xFF))
                default: bytes.append(next)
                }
            default: bytes.append(byte)
            }
        }
        return bytes
    }

    /// The value at the current position; `R` references and `stream` bodies included. With
    /// `objects`, a stream's indirect `/Length` is looked up there.
    mutating func value(objects: [Int: PDFValue]?) throws -> PDFValue {
        guard let first = try token() else { throw NomacError("unexpected end of the PDF", path: path) }
        return try value(starting: first, objects: objects)
    }

    private mutating func value(starting token: Token, objects: [Int: PDFValue]?) throws -> PDFValue {
        switch token {
        case .integer(let number):
            let saved = position
            if case .integer(let generation)? = try? self.token(), generation >= 0, keyword() == "R" { return .reference(number) }
            position = saved
            return .integer(number)
        case .real(_, let value): return .real(value)
        case .name(let name): return .name(name)
        case .string(let bytes): return .string(bytes)
        case .keyword("true"): return .bool(true)
        case .keyword("false"): return .bool(false)
        case .keyword("null"): return .null
        case .arrayStart:
            var items: [PDFValue] = []
            while let next = try self.token() {
                if next == .arrayEnd { return .array(items) }
                items.append(try value(starting: next, objects: objects))
            }
            throw NomacError("unterminated PDF array", path: path)
        case .dictionaryStart:
            var dictionary: [String: PDFValue] = [:]
            while let next = try self.token() {
                if next == .dictionaryEnd { break }
                guard case .name(let key) = next else { throw NomacError("malformed PDF dictionary", path: path) }
                dictionary[key] = try value(objects: objects)
            }
            let saved = position
            if keyword() == "stream" {
                if position < data.count, data[position] == 13 { position += 1 }
                if position < data.count, data[position] == 10 { position += 1 }
                let start = position
                var length: Int?
                if case .integer(let declared)? = dictionary["Length"] { length = declared }
                if case .reference(let number)? = dictionary["Length"], case .integer(let declared)? = objects?[number] { length = declared }
                let end: Int
                if let length, start + length <= data.count,
                   data[(start + length)...].prefix(12).firstRange(of: Array("endstream".utf8)) != nil {
                    end = start + length
                } else if let marker = data[start...].firstRange(of: Array("endstream".utf8)) {
                    var stop = marker.lowerBound
                    if stop > start, data[stop - 1] == 10 { stop -= 1 }
                    if stop > start, data[stop - 1] == 13 { stop -= 1 }
                    end = stop
                } else {
                    throw NomacError("unterminated PDF stream", path: path)
                }
                position = end
                if let marker = data[end...].firstRange(of: Array("endstream".utf8)) { position = marker.upperBound }
                return .stream(dictionary, Array(data[start..<end]))
            }
            position = saved
            return .dictionary(dictionary)
        default:
            throw NomacError("unexpected PDF token \(token)", path: path)
        }
    }
}
