import Foundation
import NomacCore

/// A CFF font program as a PDF embeds it (`FontFile3` of subtype `Type1C`): its glyphs by name,
/// their Type 2 charstrings drawn and measured, its box and Private DICT values, which nomac
/// subsets again (`pdf_experiments.py` cff, cff-2, cff-3).
struct CFFFont {
    let name: String
    /// The font matrix's scale, from font units to the em.
    let scale: Double
    let bounds: (Double, Double, Double, Double)
    let stemV: Double?
    let stemH: Double?
    let defaultWidth: Double
    private let names: [String]
    private let charStrings: [[UInt8]]
    private let globalSubrs: [[UInt8]]
    private let localSubrs: [[UInt8]]
    private let nominalWidth: Double
    private let topEntries: [(op: [UInt8], operands: [UInt8])]
    private let stringItems: [[UInt8]]
    private let globalSubrsIndex: [UInt8]
    private let privateDictionary: [UInt8]
    private let localSubrsOffset: Int?
    private let localSubrsIndex: [UInt8]

    init(_ data: [UInt8], path: String) throws {
        let unsupported = NomacError("PDF images with text in this kind of CFF font are not supported yet (BACKLOG B-215)", path: path)
        guard data.count >= 4 else { throw unsupported }
        var position = Int(data[2])
        let fontNames = try Self.index(data, at: &position, path: path)
        let tops = try Self.index(data, at: &position, path: path)
        let stringItems = try Self.index(data, at: &position, path: path)
        self.stringItems = stringItems
        let globalStart = position
        globalSubrs = try Self.index(data, at: &position, path: path)
        globalSubrsIndex = Array(data[globalStart..<position])
        guard fontNames.count == 1, let top = tops.first else { throw unsupported }
        name = String(decoding: fontNames[0], as: UTF8.self)
        topEntries = Self.entries(top)
        let topValues = Dictionary(topEntries.map { ($0.op, Self.numbers($0.operands)) }, uniquingKeysWith: { first, _ in first })
        guard topValues[[12, 30]] == nil, (topValues[[12, 6]]?.first ?? 2) == 2, let charStringsAt = topValues[[17]]?.first,
              let privateEntry = topValues[[18]], privateEntry.count == 2 else { throw unsupported }
        let matrix = topValues[[12, 7]] ?? [0.001, 0, 0, 0.001, 0, 0]
        guard matrix.count == 6, matrix[1] == 0, matrix[2] == 0, matrix[0] == matrix[3], matrix[4] == 0, matrix[5] == 0, matrix[0] > 0 else { throw unsupported }
        scale = matrix[0]
        let box = topValues[[5]] ?? [0, 0, 0, 0]
        bounds = box.count == 4 ? (box[0], box[1], box[2], box[3]) : (0, 0, 0, 0)
        var at = Int(charStringsAt)
        charStrings = try Self.index(data, at: &at, path: path)
        let privateStart = Int(privateEntry[1]), privateEnd = privateStart + Int(privateEntry[0])
        guard privateStart >= 0, privateEnd <= data.count else { throw unsupported }
        privateDictionary = Array(data[privateStart..<privateEnd])
        let privateValues = Dictionary(Self.entries(privateDictionary).map { ($0.op, Self.numbers($0.operands)) }, uniquingKeysWith: { first, _ in first })
        defaultWidth = privateValues[[20]]?.first ?? 0
        nominalWidth = privateValues[[21]]?.first ?? 0
        stemH = privateValues[[10]]?.first
        stemV = privateValues[[11]]?.first
        if let subrs = privateValues[[19]]?.first {
            var subrsAt = privateStart + Int(subrs)
            localSubrs = try Self.index(data, at: &subrsAt, path: path)
            localSubrsOffset = Int(subrs)
            localSubrsIndex = Array(data[(privateStart + Int(subrs))..<subrsAt])
        } else {
            (localSubrs, localSubrsOffset, localSubrsIndex) = ([], nil, [])
        }
        func string(_ sid: Int) -> String {
            if sid < 391 { return sid < PDFEncoding.cffStandardStrings.count ? PDFEncoding.cffStandardStrings[sid] : "" }
            let index = sid - 391
            return index >= 0 && index < stringItems.count ? String(decoding: stringItems[index], as: UTF8.self) : ""
        }
        var glyphNames = [".notdef"]
        let charsetAt = Int(topValues[[15]]?.first ?? 0)
        guard charsetAt > 2, charsetAt < data.count else { throw unsupported }
        var cursor = charsetAt + 1
        func u16(_ at: Int) -> Int { at + 1 < data.count ? Int(data[at]) << 8 | Int(data[at + 1]) : 0 }
        switch data[charsetAt] {
        case 0:
            while glyphNames.count < charStrings.count, cursor + 1 < data.count {
                glyphNames.append(string(u16(cursor)))
                cursor += 2
            }
        case 1, 2:
            let wide = data[charsetAt] == 2
            while glyphNames.count < charStrings.count, cursor + 2 < data.count {
                let first = u16(cursor), count = wide ? u16(cursor + 2) : Int(data[cursor + 2])
                for sid in first...(first + count) where glyphNames.count < charStrings.count { glyphNames.append(string(sid)) }
                cursor += wide ? 4 : 3
            }
        default:
            throw unsupported
        }
        names = glyphNames
        guard (topValues[[16]]?.first ?? 0) == 0 else { throw unsupported }
    }

    /// A glyph's name, `nil` past the font's glyphs.
    func name(_ glyph: Int) -> String? { glyph < names.count ? names[glyph] : nil }

    /// The glyph of a name, 0 when the font has none.
    func glyph(named name: String) -> Int { names.firstIndex(of: name) ?? 0 }

    /// The glyph the font's built-in (standard) encoding gives a code.
    func glyph(code: Int) -> Int { PDFEncoding.standardNames[code].map(glyph(named:)) ?? 0 }

    /// A glyph's advance in ems.
    func advance(_ glyph: Int) -> Double { (try? run(glyph).width).map { $0 * scale } ?? 0 }

    /// A glyph's outline as a path in ems.
    func path(_ glyph: Int) -> PDFPage.Path {
        guard let elements = try? run(glyph).elements else { return PDFPage.Path() }
        return PDFPage.Path(elements: elements.map { element in
            switch element {
            case .move(let point): .move(PDFPage.Point(x: point.x * scale, y: point.y * scale))
            case .line(let point): .line(PDFPage.Point(x: point.x * scale, y: point.y * scale))
            case .curve(let a, let b, let point):
                .curve(PDFPage.Point(x: a.x * scale, y: a.y * scale), PDFPage.Point(x: b.x * scale, y: b.y * scale),
                       PDFPage.Point(x: point.x * scale, y: point.y * scale))
            case .close: .close
            }
        })
    }

    private struct Failure: Error {}

    /// A glyph's Type 2 charstring run: its advance in font units and its outline.
    private func run(_ glyph: Int) throws -> (width: Double, elements: [PDFPage.Element]) {
        guard glyph < charStrings.count else { throw Failure() }
        var stack: [Double] = []
        var elements: [PDFPage.Element] = []
        var x = 0.0, y = 0.0
        var width: Double?
        var stems = 0
        var open = false
        var depth = 0
        func bias(_ count: Int) -> Int { count < 1240 ? 107 : count < 33900 ? 1131 : 32768 }
        /// The width before the first stack-clearing operator: an extra first operand when the
        /// count is odd for operators taking an even count (`even`), even for the others.
        func takeWidth(_ even: Bool) {
            if width == nil {
                width = (stack.count % 2 == 1) == even && !stack.isEmpty ? nominalWidth + stack.removeFirst() : defaultWidth
            }
        }
        func move(_ dx: Double, _ dy: Double) {
            if open { elements.append(.close) }
            x += dx; y += dy
            elements.append(.move(PDFPage.Point(x: x, y: y)))
            open = true
        }
        func line(_ dx: Double, _ dy: Double) {
            x += dx; y += dy
            elements.append(.line(PDFPage.Point(x: x, y: y)))
        }
        func curve(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ e: Double, _ f: Double) {
            let first = PDFPage.Point(x: x + a, y: y + b), second = PDFPage.Point(x: x + a + c, y: y + b + d)
            x += a + c + e; y += b + d + f
            elements.append(.curve(first, second, PDFPage.Point(x: x, y: y)))
        }
        func execute(_ code: [UInt8]) throws -> Bool {
            depth += 1
            defer { depth -= 1 }
            guard depth < 12 else { throw Failure() }
            var i = 0
            while i < code.count {
                let byte = Int(code[i])
                if byte >= 32 || byte == 28 || byte == 255 {
                    switch byte {
                    case 28:
                        guard i + 2 < code.count else { throw Failure() }
                        stack.append(Double(Int16(bitPattern: UInt16(code[i + 1]) << 8 | UInt16(code[i + 2])))); i += 3
                    case 32...246: stack.append(Double(byte - 139)); i += 1
                    case 247...250:
                        guard i + 1 < code.count else { throw Failure() }
                        stack.append(Double((byte - 247) * 256 + Int(code[i + 1]) + 108)); i += 2
                    case 251...254:
                        guard i + 1 < code.count else { throw Failure() }
                        stack.append(Double(-(byte - 251) * 256 - Int(code[i + 1]) - 108)); i += 2
                    default:
                        guard i + 4 < code.count else { throw Failure() }
                        let fixed = Int32(bitPattern: UInt32(code[i + 1]) << 24 | UInt32(code[i + 2]) << 16 | UInt32(code[i + 3]) << 8 | UInt32(code[i + 4]))
                        stack.append(Double(fixed) / 65536); i += 5
                    }
                    continue
                }
                i += 1
                switch byte {
                case 1, 3, 18, 23:
                    takeWidth(true)
                    stems += stack.count / 2
                    stack = []
                case 19, 20:
                    takeWidth(true)
                    stems += stack.count / 2
                    stack = []
                    i += (stems + 7) / 8
                case 21:
                    takeWidth(true)
                    guard stack.count >= 2 else { throw Failure() }
                    move(stack[stack.count - 2], stack[stack.count - 1]); stack = []
                case 22:
                    takeWidth(false)
                    guard let dx = stack.last else { throw Failure() }
                    move(dx, 0); stack = []
                case 4:
                    takeWidth(false)
                    guard let dy = stack.last else { throw Failure() }
                    move(0, dy); stack = []
                case 5:
                    for at in stride(from: 0, to: stack.count - 1, by: 2) { line(stack[at], stack[at + 1]) }
                    stack = []
                case 6, 7:
                    var horizontal = byte == 6
                    for value in stack {
                        horizontal ? line(value, 0) : line(0, value)
                        horizontal.toggle()
                    }
                    stack = []
                case 8:
                    for at in stride(from: 0, to: stack.count - 5, by: 6) {
                        curve(stack[at], stack[at + 1], stack[at + 2], stack[at + 3], stack[at + 4], stack[at + 5])
                    }
                    stack = []
                case 24:
                    var at = 0
                    while at + 6 <= stack.count - 2 {
                        curve(stack[at], stack[at + 1], stack[at + 2], stack[at + 3], stack[at + 4], stack[at + 5]); at += 6
                    }
                    if at + 1 < stack.count { line(stack[at], stack[at + 1]) }
                    stack = []
                case 25:
                    var at = 0
                    while at + 2 <= stack.count - 6 { line(stack[at], stack[at + 1]); at += 2 }
                    if at + 5 < stack.count { curve(stack[at], stack[at + 1], stack[at + 2], stack[at + 3], stack[at + 4], stack[at + 5]) }
                    stack = []
                case 26:
                    var at = 0
                    var dx1 = 0.0
                    if stack.count % 4 == 1 { dx1 = stack[0]; at = 1 }
                    while at + 3 < stack.count {
                        curve(dx1, stack[at], stack[at + 1], stack[at + 2], 0, stack[at + 3]); dx1 = 0; at += 4
                    }
                    stack = []
                case 27:
                    var at = 0
                    var dy1 = 0.0
                    if stack.count % 4 == 1 { dy1 = stack[0]; at = 1 }
                    while at + 3 < stack.count {
                        curve(stack[at], dy1, stack[at + 1], stack[at + 2], stack[at + 3], 0); dy1 = 0; at += 4
                    }
                    stack = []
                case 30, 31:
                    var horizontal = byte == 31
                    var at = 0
                    while at + 3 < stack.count {
                        let last = at + 4 == stack.count - 1 ? stack[at + 4] : 0
                        if horizontal {
                            curve(stack[at], 0, stack[at + 1], stack[at + 2], last, stack[at + 3])
                        } else {
                            curve(0, stack[at], stack[at + 1], stack[at + 2], stack[at + 3], last)
                        }
                        horizontal.toggle()
                        at += 4
                    }
                    stack = []
                case 10, 29:
                    guard let number = stack.popLast() else { throw Failure() }
                    let subrs = byte == 10 ? localSubrs : globalSubrs
                    let index = Int(number) + bias(subrs.count)
                    guard index >= 0, index < subrs.count else { throw Failure() }
                    if try !execute(subrs[index]) { return false }
                case 11:
                    return true
                case 14:
                    takeWidth(true)
                    if open { elements.append(.close); open = false }
                    guard stack.count < 4 else { throw Failure() }
                    return false
                case 12:
                    guard i < code.count else { throw Failure() }
                    let escape = code[i]
                    i += 1
                    let s = stack
                    switch escape {
                    case 35 where s.count >= 12:
                        curve(s[0], s[1], s[2], s[3], s[4], s[5]); curve(s[6], s[7], s[8], s[9], s[10], s[11])
                    case 34 where s.count >= 7:
                        curve(s[0], 0, s[1], s[2], s[3], 0); curve(s[4], 0, s[5], -s[2], s[6], 0)
                    case 36 where s.count >= 9:
                        curve(s[0], s[1], s[2], s[3], s[4], 0); curve(s[5], 0, s[6], s[7], s[8], -(s[1] + s[3] + s[7]))
                    case 37 where s.count >= 11:
                        let dx = s[0] + s[2] + s[4] + s[6] + s[8], dy = s[1] + s[3] + s[5] + s[7] + s[9]
                        curve(s[0], s[1], s[2], s[3], s[4], s[5])
                        if abs(dx) > abs(dy) { curve(s[6], s[7], s[8], s[9], s[10], -dy) } else { curve(s[6], s[7], s[8], s[9], -dx, s[10]) }
                    default:
                        throw Failure()
                    }
                    stack = []
                default:
                    throw Failure()
                }
            }
            return true
        }
        _ = try execute(charStrings[glyph])
        if open { elements.append(.close) }
        return (width ?? defaultWidth, elements)
    }

    /// A CFF font of glyph 0 and `glyphs`, in that order: the top DICT's other entries, the
    /// strings, the global and local subroutines and the Private DICT kept, a format 0 charset.
    /// Its bytes are nomac's own (ADR 0204).
    func subset(_ glyphs: [Int]) -> [UInt8] {
        func be16(_ value: Int) -> [UInt8] { [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)] }
        func int32(_ value: Int) -> [UInt8] { [29] + be16(value >> 16) + be16(value & 0xFFFF) }
        let all = [0] + glyphs
        var sids: [Int] = []
        var added: [[UInt8]] = []
        var existing: [String: Int] = [:]
        for (index, item) in stringItems.enumerated() { existing[String(decoding: item, as: UTF8.self)] = 391 + index }
        for glyph in glyphs {
            let glyphName = names[glyph]
            if let standard = PDFEncoding.cffStandardStrings.firstIndex(of: glyphName) {
                sids.append(standard)
            } else if let sid = existing[glyphName] {
                sids.append(sid)
            } else {
                added.append(Array(glyphName.utf8))
                existing[glyphName] = 391 + stringItems.count + added.count - 1
                sids.append(391 + stringItems.count + added.count - 1)
            }
        }
        let stringsIndex = Self.indexBytes(stringItems + added)
        let charset = [0] + sids.flatMap(be16)
        let charStringsIndex = Self.indexBytes(all.map { charStrings[$0] })
        let header: [UInt8] = [1, 0, 4, 4] + Self.indexBytes([Array(name.utf8)])
        let kept = topEntries.filter { ![[15], [16], [17], [18]].contains($0.op) }.flatMap { $0.operands + $0.op }
        let topLength = kept.count + 5 * 4 + 3
        let topIndexLength = Self.indexBytes([[UInt8](repeating: 0, count: topLength)]).count
        let charsetAt = header.count + topIndexLength + stringsIndex.count + globalSubrsIndex.count
        let charStringsAt = charsetAt + charset.count
        let privateAt = charStringsAt + charStringsIndex.count
        var privatePart = privateDictionary
        if let offset = localSubrsOffset {
            privatePart += [UInt8](repeating: 0, count: max(0, offset - privatePart.count)) + localSubrsIndex
        }
        let top = kept + int32(charsetAt) + [15] + int32(charStringsAt) + [17] + int32(privateDictionary.count) + int32(privateAt) + [18]
        return header + Self.indexBytes([top]) + stringsIndex + globalSubrsIndex + charset + charStringsIndex + privatePart
    }

    static func indexBytes(_ items: [[UInt8]]) -> [UInt8] {
        guard !items.isEmpty else { return [0, 0] }
        var offsets = [1]
        for item in items { offsets.append(offsets.last! + item.count) }
        return [UInt8(items.count >> 8), UInt8(items.count & 0xFF), 4]
            + offsets.flatMap { [UInt8($0 >> 24 & 0xFF), UInt8($0 >> 16 & 0xFF), UInt8($0 >> 8 & 0xFF), UInt8($0 & 0xFF)] } + items.flatMap { $0 }
    }

    /// An INDEX's items, `position` moved past it.
    static func index(_ data: [UInt8], at position: inout Int, path: String) throws -> [[UInt8]] {
        let failure = NomacError("the PDF embeds a CFF font nomac cannot read", path: path)
        guard position + 2 <= data.count else { throw failure }
        let count = Int(data[position]) << 8 | Int(data[position + 1])
        guard count > 0 else { position += 2; return [] }
        guard position + 3 <= data.count else { throw failure }
        let size = Int(data[position + 2])
        guard (1...4).contains(size), position + 3 + (count + 1) * size <= data.count else { throw failure }
        let offsets = (0...count).map { item in
            (0..<size).reduce(0) { $0 << 8 | Int(data[position + 3 + item * size + $1]) }
        }
        let base = position + 3 + (count + 1) * size - 1
        guard offsets.allSatisfy({ $0 >= 1 }), base + offsets[count] <= data.count, zip(offsets, offsets.dropFirst()).allSatisfy({ $0 <= $1 }) else { throw failure }
        position = base + offsets[count]
        return (0..<count).map { Array(data[(base + offsets[$0])..<(base + offsets[$0 + 1])]) }
    }

    /// A DICT's entries in order: each operator with its operands' bytes.
    static func entries(_ bytes: [UInt8]) -> [(op: [UInt8], operands: [UInt8])] {
        var result: [(op: [UInt8], operands: [UInt8])] = []
        var start = 0, i = 0
        while i < bytes.count {
            let byte = bytes[i]
            switch byte {
            case 0...21:
                let op: [UInt8] = byte == 12 && i + 1 < bytes.count ? [12, bytes[i + 1]] : [byte]
                result.append((op, Array(bytes[start..<i])))
                i += op.count
                start = i
            case 28: i += 3
            case 29: i += 5
            case 30:
                i += 1
                while i < bytes.count, bytes[i] & 0x0F != 0x0F, bytes[i] >> 4 != 0x0F { i += 1 }
                i += 1
            case 247...254: i += 2
            default: i += 1
            }
        }
        return result
    }

    /// A DICT operand list's numbers.
    static func numbers(_ bytes: [UInt8]) -> [Double] {
        var result: [Double] = []
        var i = 0
        func at(_ index: Int) -> Int { index < bytes.count ? Int(bytes[index]) : 0 }
        while i < bytes.count {
            let byte = Int(bytes[i])
            switch byte {
            case 28: result.append(Double(Int16(bitPattern: UInt16(at(i + 1) << 8 | at(i + 2))))); i += 3
            case 29: result.append(Double(Int32(bitPattern: UInt32(at(i + 1) << 24 | at(i + 2) << 16 | at(i + 3) << 8 | at(i + 4))))); i += 5
            case 30:
                var text = ""
                i += 1
                reading: while i < bytes.count {
                    for nibble in [Int(bytes[i]) >> 4, Int(bytes[i]) & 0x0F] {
                        switch nibble {
                        case 0...9: text += String(nibble)
                        case 0xA: text += "."
                        case 0xB: text += "E"
                        case 0xC: text += "E-"
                        case 0xE: text += "-"
                        case 0xF: i += 1; break reading
                        default: break
                        }
                    }
                    i += 1
                }
                result.append(Double(text) ?? 0)
            case 32...246: result.append(Double(byte - 139)); i += 1
            case 247...250: result.append(Double((byte - 247) * 256 + at(i + 1) + 108)); i += 2
            case 251...254: result.append(Double(-(byte - 251) * 256 - at(i + 1) - 108)); i += 2
            default: i += 1
            }
        }
        return result
    }
}
