import Foundation
import NomacCore

extension PDFPage {
    /// A PDF function of one input: sampled (type 0), exponential (2), stitching (3) or a
    /// PostScript calculator program (4).
    indirect enum Function {
        case sampled(Sampled)
        case exponential(domain: [Double], c0: [Double], c1: [Double], exponent: Double)
        case stitching(domain: [Double], functions: [Function], bounds: [Double], encode: [Double])
        case postScript(domain: [Double], range: [Double], program: [UInt8])

        struct Sampled {
            var size: Int
            var bitsPerSample: Int
            var domain: [Double]
            var range: [Double]
            var encode: [Double]
            var decode: [Double]
            var data: [UInt8]
        }

        var domain: [Double] {
            switch self {
            case .sampled(let sampled): sampled.domain
            case .exponential(let domain, _, _, _), .stitching(let domain, _, _, _), .postScript(let domain, _, _): domain
            }
        }

        /// Whether Quartz keeps the function as it is rather than sampling it again (`shadings`:
        /// axial-fn0, axial-fn4).
        var isKept: Bool {
            switch self {
            case .sampled, .postScript: true
            case .exponential, .stitching: false
            }
        }

        func evaluate(_ input: Double) -> [Double] {
            let domain = self.domain
            let x = min(max(input, domain[0]), domain[1])
            switch self {
            case .sampled(let sampled):
                let count = sampled.range.count / 2
                let maximum = Double((1 << sampled.bitsPerSample) - 1)
                let position = sampled.encode[0] + (x - domain[0]) * (sampled.encode[1] - sampled.encode[0]) / max(domain[1] - domain[0], 1e-12)
                let clamped = min(max(position, 0), Double(sampled.size - 1))
                let low = Int(clamped.rounded(.down)), high = min(low + 1, sampled.size - 1), fraction = clamped - Double(low)
                return (0..<count).map { component in
                    func sample(_ index: Int) -> Double {
                        let bit = (index * count + component) * sampled.bitsPerSample
                        var raw = 0
                        for offset in 0..<sampled.bitsPerSample {
                            let position = bit + offset
                            guard position / 8 < sampled.data.count else { break }
                            raw = raw << 1 | Int(sampled.data[position / 8] >> (7 - position % 8)) & 1
                        }
                        return Double(raw)
                    }
                    let raw = sample(low) * (1 - fraction) + sample(high) * fraction
                    let decoded = sampled.decode[2 * component] + raw / maximum * (sampled.decode[2 * component + 1] - sampled.decode[2 * component])
                    return min(max(decoded, sampled.range[2 * component]), sampled.range[2 * component + 1])
                }
            case .exponential(_, let c0, let c1, let exponent):
                let power = pow(x, exponent)
                return zip(c0, c1).map { $0 + power * ($1 - $0) }
            case .stitching(_, let functions, let bounds, let encode):
                let edges = [domain[0]] + bounds + [domain[1]]
                let index = min(bounds.firstIndex(where: { x < $0 }) ?? bounds.count, functions.count - 1)
                let (low, high) = (edges[index], edges[index + 1])
                let (e0, e1) = (encode[2 * index], encode[2 * index + 1])
                let mapped = high == low ? e0 : e0 + (x - low) * (e1 - e0) / (high - low)
                return functions[index].evaluate(mapped)
            case .postScript(_, let range, let program):
                let result = PostScriptCalculator.run(program, input: x, outputs: range.count / 2)
                return result.enumerated().map { min(max($1, range[2 * $0]), range[2 * $0 + 1]) }
            }
        }

        static func read(_ value: PDFValue?, file: PDFFile, outputs: Int) throws -> Function {
            guard let value = file.resolve(value), let dictionary = value.dictionary else {
                throw NomacError("the PDF has a shading without a function", path: file.path)
            }
            let domain = file.resolve(dictionary["Domain"])?.array?.compactMap(file.number) ?? [0, 1]
            let range = file.resolve(dictionary["Range"])?.array?.compactMap(file.number) ?? []
            guard domain.count == 2 else {
                throw NomacError("PDF images with functions of more than one input are not supported yet (BACKLOG B-215)", path: file.path)
            }
            switch Int(file.number(dictionary["FunctionType"]) ?? -1) {
            case 0:
                let size = file.resolve(dictionary["Size"])?.array?.compactMap(file.number) ?? []
                let bits = Int(file.number(dictionary["BitsPerSample"]) ?? 0)
                guard size.count == 1, size[0] >= 1, [1, 2, 4, 8, 12, 16, 24, 32].contains(bits), range.count == 2 * outputs,
                      file.number(dictionary["Order"]).map({ $0 == 1 }) ?? true else {
                    throw NomacError("PDF images with this sampled function are not supported yet (BACKLOG B-215)", path: file.path)
                }
                let encode = file.resolve(dictionary["Encode"])?.array?.compactMap(file.number) ?? [0, size[0] - 1]
                let decode = file.resolve(dictionary["Decode"])?.array?.compactMap(file.number) ?? range
                return .sampled(Sampled(size: Int(size[0]), bitsPerSample: bits, domain: domain, range: range, encode: encode,
                                        decode: decode.count == range.count ? decode : range, data: try file.decodedStream(value)))
            case 2:
                let c0 = file.resolve(dictionary["C0"])?.array?.compactMap(file.number) ?? [0]
                let c1 = file.resolve(dictionary["C1"])?.array?.compactMap(file.number) ?? [1]
                guard c0.count == outputs, c1.count == outputs, let exponent = file.number(dictionary["N"]) else {
                    throw NomacError("the PDF has an exponential function without as many outputs as its colors", path: file.path)
                }
                return .exponential(domain: domain, c0: c0, c1: c1, exponent: exponent)
            case 3:
                let functions = try (file.resolve(dictionary["Functions"])?.array ?? []).map { try read($0, file: file, outputs: outputs) }
                let bounds = file.resolve(dictionary["Bounds"])?.array?.compactMap(file.number) ?? []
                let encode = file.resolve(dictionary["Encode"])?.array?.compactMap(file.number) ?? []
                guard !functions.isEmpty, bounds.count == functions.count - 1, encode.count == 2 * functions.count else {
                    throw NomacError("the PDF has a stitching function whose parts do not match", path: file.path)
                }
                return .stitching(domain: domain, functions: functions, bounds: bounds, encode: encode)
            case 4:
                guard range.count == 2 * outputs else { throw NomacError("the PDF has a PostScript function without a range for its colors", path: file.path) }
                return .postScript(domain: domain, range: range, program: try file.decodedStream(value))
            default:
                throw NomacError("the PDF has a function of an unknown type", path: file.path)
            }
        }
    }

    /// An axial (type 2) or radial (type 3) shading.
    struct Shading {
        var key: Int
        var type: Int
        var space: ColorSpace
        var coords: [Double]
        var domain: [Double]
        var extend: (Bool, Bool)
        var function: Function

        /// The shading's parameter at `point`, in its own space, or `nil` outside it.
        func parameter(at point: Point) -> Double? {
            let s: Double
            if type == 2 {
                let (dx, dy) = (coords[2] - coords[0], coords[3] - coords[1])
                let length = dx * dx + dy * dy
                guard length > 0 else { return nil }
                s = ((point.x - coords[0]) * dx + (point.y - coords[1]) * dy) / length
            } else {
                // The largest s whose circle passes through the point with a radius at least 0.
                let (x0, y0, r0, x1, y1, r1) = (coords[0], coords[1], coords[2], coords[3], coords[4], coords[5])
                let (cx, cy, dr) = (x1 - x0, y1 - y0, r1 - r0)
                let (px, py) = (point.x - x0, point.y - y0)
                let a = cx * cx + cy * cy - dr * dr, b = px * cx + py * cy + r0 * dr, c = px * px + py * py - r0 * r0
                var candidates: [Double] = []
                if abs(a) < 1e-12 {
                    if abs(b) > 1e-12 { candidates = [c / (2 * b)] }
                } else {
                    let discriminant = b * b - a * c
                    guard discriminant >= 0 else { return nil }
                    candidates = [(b + discriminant.squareRoot()) / a, (b - discriminant.squareRoot()) / a]
                }
                let valid = candidates.filter { r0 + $0 * dr >= 0 }.sorted(by: >).filter { ($0 >= 0 || extend.0) && ($0 <= 1 || extend.1) }
                guard let best = valid.first else { return nil }
                s = best
            }
            if s < 0 { return extend.0 ? domain[0] : nil }
            if s > 1 { return extend.1 ? domain[1] : nil }
            return domain[0] + s * (domain[1] - domain[0])
        }

        static func read(_ value: PDFValue, key: Int, file: PDFFile, resources: [String: PDFValue]) throws -> Shading {
            guard let dictionary = value.dictionary else { throw NomacError("the PDF has a shading that is not a dictionary", path: file.path) }
            let type = Int(file.number(dictionary["ShadingType"]) ?? 0)
            guard type == 2 || type == 3 else {
                throw NomacError("PDF images with shadings other than axial and radial ones are not supported yet (BACKLOG B-215)", path: file.path)
            }
            for entry in ["Background", "BBox"] where dictionary[entry] != nil {
                throw NomacError("PDF images with a shading's \(entry) are not supported yet (BACKLOG B-215)", path: file.path)
            }
            let spaceValue = file.resolve(dictionary["ColorSpace"])
            let space: ColorSpace?
            switch spaceValue {
            case .name(let name)?: space = try colorSpace(name, resources: resources, file: file)
            case let value?: space = try colorSpace("CS", resources: ["ColorSpace": .dictionary(["CS": value])], file: file)
            case nil: space = nil
            }
            guard let space else { throw NomacError("PDF images with CMYK shadings are not supported yet (BACKLOG B-215)", path: file.path) }
            let coords = file.resolve(dictionary["Coords"])?.array?.compactMap(file.number).map(PDFLexer.contentReading) ?? []
            guard coords.count == (type == 2 ? 4 : 6) else { throw NomacError("the PDF has a shading without its coordinates", path: file.path) }
            guard file.resolve(dictionary["Function"])?.array == nil else {
                throw NomacError("PDF images with a function per color component are not supported yet (BACKLOG B-215)", path: file.path)
            }
            let extend = file.resolve(dictionary["Extend"])?.array?.map { file.resolve($0) == .bool(true) } ?? []
            return Shading(key: key, type: type, space: space, coords: coords,
                           domain: file.resolve(dictionary["Domain"])?.array?.compactMap(file.number).map(PDFLexer.contentReading) ?? [0, 1],
                           extend: extend.count == 2 ? (extend[0], extend[1]) : (false, false),
                           function: try Function.read(dictionary["Function"], file: file, outputs: space.components))
        }
    }

    /// A shading pattern (type 2): its shading and its matrix to the page.
    struct Pattern {
        var key: Int
        var shading: Shading
        var matrix: Matrix
    }

    /// A `sh` where it is drawn.
    struct ShadingFill {
        var shading: Shading
        var matrix: Matrix
        var clips: [Clip]
        var alpha: Double
        var softMask: SoftMask?
        var renderingIntent: String
        var overprint: Bool
        var overprintMode: Int
    }
}

/// A PostScript calculator function (PDF type 4): numbers and booleans on a stack, the
/// operators of PDF 1.7 § 7.10.5 and `if`/`ifelse` blocks.
enum PostScriptCalculator {
    /// The program as Quartz writes it again, run symbolically: numbers and copies (`dup`) stay
    /// pending above the values on the stack until an operator needs them there; pending
    /// numbers fold through `add`, `sub` and `mul` and swap through `exch`, a value plus or
    /// minus 0 or times 1 stays as it is, a value times 0 is popped for a 0, a pending number or
    /// copy popped is gone; what is pending at a procedure's start or end is written then. Its
    /// tokens one space apart, numbers as ``number(_:)`` writes them (`postscript`,
    /// `postscript-2`; corpus: cwa's pattern functions, `dup 0.000000 sub 0.000000 mul 0.000000
    /// add exch` is written `0 exch`).
    static func rewritten(_ program: [UInt8]) -> [UInt8] {
        let words = String(decoding: program, as: UTF8.self).replacingOccurrences(of: "{", with: " { ").replacingOccurrences(of: "}", with: " } ")
            .split(whereSeparator: \.isWhitespace).map(String.init)
        enum Pending {
            case number(Double)
            case copy
        }
        var output: [String] = []
        // What is pending above the stack's values, for each procedure open.
        var pending: [[Pending]] = [[]]
        func flush() {
            for item in pending[pending.count - 1] {
                switch item {
                case .number(let value): output.append(number(value))
                case .copy: output.append("dup")
                }
            }
            pending[pending.count - 1] = []
        }
        func emit(_ word: String) {
            flush()
            output.append(word)
        }
        for word in words {
            let level = pending.count - 1
            if let value = Double(word) {
                pending[level].append(.number(value))
                continue
            }
            switch word {
            case "{":
                emit(word)
                pending.append([])
            case "}":
                emit(word)
                if level > 0 { pending.removeLast() }
            case "add", "sub", "mul":
                guard case .number(let b)? = pending[level].last else {
                    emit(word)
                    continue
                }
                if pending[level].count >= 2, case .number(let a) = pending[level][pending[level].count - 2] {
                    pending[level].removeLast(2)
                    pending[level].append(.number(word == "add" ? a + b : word == "sub" ? a - b : a * b))
                } else if b == 0 && word != "mul" || b == 1 && word == "mul" {
                    pending[level].removeLast()
                } else if b == 0 {
                    pending[level].removeLast()
                    if case .copy? = pending[level].last { pending[level].removeLast() } else { emit("pop") }
                    pending[level].append(.number(0))
                } else {
                    emit(word)
                }
            case "exch":
                let count = pending[level].count
                if count >= 2, case .number = pending[level][count - 1], case .number = pending[level][count - 2] {
                    pending[level].swapAt(count - 1, count - 2)
                } else {
                    emit(word)
                }
            case "pop":
                if pending[level].isEmpty { emit(word) } else { pending[level].removeLast() }
            case "dup":
                if case .number(let value)? = pending[level].last { pending[level].append(.number(value)) } else { pending[level].append(.copy) }
            default:
                emit(word)
            }
        }
        flush()
        return Array(output.joined(separator: " ").utf8)
    }

    /// A number in a program Quartz writes again: an integer when within a millionth of one,
    /// from 1 seven significant digits, below 1 six decimals, trailing zeros dropped
    /// (`postscript-2`: 123.4567891 is 123.4568, 12345678.5 12345678, 0.1234565 0.123456,
    /// 0.0000006 0; corpus: firefox's `fxLogo.pdf`, -1.860232).
    static func number(_ value: Double) -> String {
        let nearest = value.rounded()
        if abs(value - nearest) < 1e-6 { return nearest == 0 ? "0" : String(Int64(nearest)) }
        let digits = abs(value) < 1 ? 0 : Int(log10(abs(value)).rounded(.down)) + 1
        var text = String(format: "%.\(abs(value) < 1 ? 6 : max(0, 7 - digits))f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text == "-0" ? "0" : text
    }

    private indirect enum Item {
        case number(Double)
        case boolean(Bool)
        case word(String)
        case block([Item])
    }

    static func run(_ program: [UInt8], input: Double, outputs: Int) -> [Double] {
        var position = 0
        let text = Array(String(decoding: program, as: UTF8.self).replacingOccurrences(of: "{", with: " { ").replacingOccurrences(of: "}", with: " } ")
            .split(whereSeparator: \.isWhitespace).map(String.init))
        func parse() -> [Item] {
            var items: [Item] = []
            while position < text.count {
                let word = text[position]
                position += 1
                switch word {
                case "{": items.append(.block(parse()))
                case "}": return items
                case "true": items.append(.boolean(true))
                case "false": items.append(.boolean(false))
                default: items.append(Double(word).map(Item.number) ?? .word(word))
                }
            }
            return items
        }
        let parsed = parse()
        let body: [Item]
        if parsed.count == 1, case .block(let inner) = parsed[0] { body = inner } else { body = parsed }
        var stack: [Item] = [.number(input)]
        func number() -> Double {
            switch stack.popLast() {
            case .number(let value)?: value
            case .boolean(let value)?: value ? 1 : 0
            default: 0
            }
        }
        func boolean() -> Bool {
            switch stack.popLast() {
            case .boolean(let value)?: value
            case .number(let value)?: value != 0
            default: false
            }
        }
        func execute(_ items: [Item]) {
            var index = 0
            while index < items.count {
                defer { index += 1 }
                switch items[index] {
                case .number, .boolean:
                    stack.append(items[index])
                case .block(let block):
                    // A block is an operand of the `if` or `ifelse` after it.
                    if index + 1 < items.count, case .word("if") = items[index + 1] {
                        if boolean() { execute(block) }
                        index += 1
                    } else if index + 2 < items.count, case .block(let other) = items[index + 1], case .word("ifelse") = items[index + 2] {
                        if boolean() { execute(block) } else { execute(other) }
                        index += 2
                    }
                case .word(let word):
                    operate(word)
                }
            }
        }
        func operate(_ word: String) {
            switch word {
            case "add": let b = number(), a = number(); stack.append(.number(a + b))
            case "sub": let b = number(), a = number(); stack.append(.number(a - b))
            case "mul": let b = number(), a = number(); stack.append(.number(a * b))
            case "div": let b = number(), a = number(); stack.append(.number(b == 0 ? 0 : a / b))
            case "idiv": let b = Int(number()), a = Int(number()); stack.append(.number(b == 0 ? 0 : Double(a / b)))
            case "mod": let b = Int(number()), a = Int(number()); stack.append(.number(b == 0 ? 0 : Double(a % b)))
            case "neg": stack.append(.number(-number()))
            case "abs": stack.append(.number(abs(number())))
            case "ceiling": stack.append(.number(number().rounded(.up)))
            case "floor": stack.append(.number(number().rounded(.down)))
            case "round": stack.append(.number(number().rounded(.toNearestOrAwayFromZero)))
            case "truncate", "cvi": stack.append(.number(number().rounded(.towardZero)))
            case "cvr": stack.append(.number(number()))
            case "sqrt": stack.append(.number(max(number(), 0).squareRoot()))
            case "sin": stack.append(.number(sin(number() * .pi / 180)))
            case "cos": stack.append(.number(cos(number() * .pi / 180)))
            case "atan":
                let b = number(), a = number()
                var degrees = atan2(a, b) * 180 / .pi
                if degrees < 0 { degrees += 360 }
                stack.append(.number(degrees))
            case "exp": let b = number(), a = number(); stack.append(.number(pow(a, b)))
            case "ln": stack.append(.number(log(max(number(), 1e-300))))
            case "log": stack.append(.number(log10(max(number(), 1e-300))))
            case "eq", "ne":
                let b = stack.popLast(), a = stack.popLast()
                var equal = false
                if case .number(let x)? = a, case .number(let y)? = b { equal = x == y }
                if case .boolean(let x)? = a, case .boolean(let y)? = b { equal = x == y }
                stack.append(.boolean(word == "eq" ? equal : !equal))
            case "gt": let b = number(), a = number(); stack.append(.boolean(a > b))
            case "ge": let b = number(), a = number(); stack.append(.boolean(a >= b))
            case "lt": let b = number(), a = number(); stack.append(.boolean(a < b))
            case "le": let b = number(), a = number(); stack.append(.boolean(a <= b))
            case "and", "or", "xor":
                let b = stack.popLast(), a = stack.popLast()
                if case .boolean(let x)? = a, case .boolean(let y)? = b {
                    stack.append(.boolean(word == "and" ? x && y : word == "or" ? x || y : x != y))
                } else {
                    var (x, y) = (0, 0)
                    if case .number(let value)? = a { x = Int(value) }
                    if case .number(let value)? = b { y = Int(value) }
                    stack.append(.number(Double(word == "and" ? x & y : word == "or" ? x | y : x ^ y)))
                }
            case "not":
                switch stack.popLast() {
                case .boolean(let value)?: stack.append(.boolean(!value))
                case .number(let value)?: stack.append(.number(Double(~Int(value))))
                default: break
                }
            case "bitshift":
                let shift = Int(number()), value = Int(number())
                stack.append(.number(Double(shift >= 0 ? value << shift : value >> -shift)))
            case "pop": _ = stack.popLast()
            case "exch":
                guard stack.count >= 2 else { break }
                stack.swapAt(stack.count - 1, stack.count - 2)
            case "dup": if let top = stack.last { stack.append(top) }
            case "copy":
                let count = Int(number())
                guard count > 0, count <= stack.count else { break }
                stack += stack.suffix(count)
            case "index":
                let offset = Int(number())
                guard offset >= 0, offset < stack.count else { break }
                stack.append(stack[stack.count - 1 - offset])
            case "roll":
                let shift = Int(number()), count = Int(number())
                guard count > 0, count <= stack.count else { break }
                var top = Array(stack.suffix(count))
                stack.removeLast(count)
                let amount = ((shift % count) + count) % count
                top = Array(top.suffix(amount) + top.prefix(count - amount))
                stack += top
            case "true": stack.append(.boolean(true))
            case "false": stack.append(.boolean(false))
            default: break
            }
        }
        execute(body)
        let values = stack.suffix(outputs).map { item -> Double in
            switch item {
            case .number(let value): value
            case .boolean(let value): value ? 1 : 0
            case .word, .block: 0
            }
        }
        return values.count == outputs ? values : [Double](repeating: 0, count: outputs)
    }
}
