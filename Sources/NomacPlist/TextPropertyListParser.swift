import Foundation
import NomacCore

/// Reads the text property list formats a `.strings` or `.stringsdict` file is written in: the
/// old-style (OpenStep) format, including the strings-file form of top-level `key = value;`
/// pairs, and XML (docs/formats/property-lists.md "Reading"). Text that is not a property list
/// throws ``Failure``; what nomac does not read yet throws a `NomacError` naming its BACKLOG item.
public enum TextPropertyListParser {
    public struct Failure: Error, Equatable, CustomStringConvertible {
        public var message: String
        public var description: String { message }
    }

    /// The property list in `text`: XML when it starts with `<?xml`, `<!DOCTYPE` or `<plist`
    /// after white space, old-style otherwise.
    public static func parse(_ text: String) throws -> PropertyListValue {
        let scalars = Array(text.unicodeScalars)
        var start = 0
        while start < scalars.count, scalars[start].properties.isWhitespace {
            start += 1
        }
        let head = String(String.UnicodeScalarView(scalars[start..<min(scalars.count, start + 9)]))
        if head.hasPrefix("<?xml") || head.hasPrefix("<!DOCTYPE") || head.hasPrefix("<plist") {
            var parser = XMLPlistParser(scalars: scalars, index: start)
            return try parser.document()
        }
        var parser = OldStyleParser(scalars: scalars)
        return try parser.document()
    }
}

private struct OldStyleParser {
    let scalars: [Unicode.Scalar]
    var index = 0

    init(scalars: [Unicode.Scalar]) {
        self.scalars = scalars
    }

    /// One value, or the pairs of a strings file when the first value is followed by `=` or `;`.
    mutating func document() throws -> PropertyListValue {
        skipWhitespaceAndComments()
        if index == scalars.count {
            return .dictionary([:])
        }
        let start = index
        let first = try value()
        skipWhitespaceAndComments()
        if index == scalars.count {
            return first
        }
        guard case .string = first, scalars[index] == "=" || scalars[index] == ";" else {
            throw failure("junk after the property list")
        }
        index = start
        var entries: [String: PropertyListValue] = [:]
        while true {
            skipWhitespaceAndComments()
            if index == scalars.count { return .dictionary(entries) }
            try pair(into: &entries, allowingShorthand: true)
        }
    }

    /// `key = value;`, or `key;` for `key = key;` at the top level of a strings file.
    private mutating func pair(into entries: inout [String: PropertyListValue], allowingShorthand: Bool) throws {
        guard case .string(let key) = try value() else { throw failure("a key is not a string") }
        skipWhitespaceAndComments()
        if allowingShorthand, peek(";") {
            index += 1
            entries[key] = .string(key)
            return
        }
        guard peek("=") else { throw failure("missing '=' after a key") }
        index += 1
        let element = try value()
        skipWhitespaceAndComments()
        guard peek(";") else { throw failure("missing ';' after a value") }
        index += 1
        entries[key] = element
    }

    private mutating func value() throws -> PropertyListValue {
        skipWhitespaceAndComments()
        guard index < scalars.count else { throw failure("unexpected end of input") }
        switch scalars[index] {
        case "{":
            index += 1
            var entries: [String: PropertyListValue] = [:]
            while true {
                skipWhitespaceAndComments()
                if peek("}") {
                    index += 1
                    return .dictionary(entries)
                }
                try pair(into: &entries, allowingShorthand: false)
            }
        case "(":
            index += 1
            var elements: [PropertyListValue] = []
            skipWhitespaceAndComments()
            if peek(")") {
                index += 1
                return .array(elements)
            }
            while true {
                elements.append(try value())
                skipWhitespaceAndComments()
                if peek(",") {
                    index += 1
                    skipWhitespaceAndComments()
                }
                if peek(")") {
                    index += 1
                    return .array(elements)
                }
                guard index < scalars.count else { throw failure("unterminated array") }
            }
        case "<":
            index += 1
            return .data(try hexData())
        case "\"", "'":
            return .string(try quotedString())
        default:
            let start = index
            while index < scalars.count, Self.isUnquoted(scalars[index]) {
                index += 1
            }
            guard index > start else { throw failure("unexpected character") }
            return .string(String(String.UnicodeScalarView(scalars[start..<index])))
        }
    }

    private static func isUnquoted(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCII && (scalar.properties.isAlphabetic || ("0"..."9").contains(scalar) || "_$/:.-".unicodeScalars.contains(scalar))
    }

    /// A quoted string. Escapes: `\a \b \f \n \r \t \v`, `\U` with up to four hex digits for a
    /// UTF-16 code unit, up to three octal digits for an ASCII character, and any other character
    /// for itself. Each surrogate unit that is not half of a pair becomes U+FFFD (the
    /// `copy-escapes` experiment).
    private mutating func quotedString() throws -> String {
        let quote = scalars[index]
        index += 1
        var units: [UInt16] = []
        while index < scalars.count, scalars[index] != quote {
            let scalar = scalars[index]
            index += 1
            if scalar == "\\" {
                guard index < scalars.count else { break }
                units.append(contentsOf: try escape())
            } else {
                units.append(contentsOf: scalar.utf16)
            }
        }
        guard index < scalars.count else { throw failure("unterminated string") }
        index += 1
        return String(decoding: units, as: UTF16.self)
    }

    private mutating func escape() throws -> [UInt16] {
        let scalar = scalars[index]
        index += 1
        switch scalar {
        case "a": return [0x07]
        case "b": return [0x08]
        case "f": return [0x0C]
        case "n": return [0x0A]
        case "r": return [0x0D]
        case "t": return [0x09]
        case "v": return [0x0B]
        case "U":
            var value: UInt16 = 0
            var digits = 0
            while digits < 4, index < scalars.count, let digit = hexValue(scalars[index]) {
                value = value * 16 + UInt16(digit)
                index += 1
                digits += 1
            }
            return [value]
        case "0"..."7":
            var value = scalar.value - 0x30
            var digits = 1
            while digits < 3, index < scalars.count, ("0"..."7").contains(scalars[index]) {
                value = value * 8 + scalars[index].value - 0x30
                index += 1
                digits += 1
            }
            guard value < 0x80 else {
                throw NomacError("nomac does not read octal escapes above \\177 yet (BACKLOG B-252)")
            }
            return [UInt16(value)]
        default:
            return Array(scalar.utf16)
        }
    }

    private func hexValue(_ scalar: Unicode.Scalar) -> UInt32? {
        switch scalar {
        case "0"..."9": scalar.value - 0x30
        case "a"..."f": scalar.value - 0x61 + 10
        case "A"..."F": scalar.value - 0x41 + 10
        default: nil
        }
    }

    private mutating func hexData() throws -> [UInt8] {
        var bytes: [UInt8] = []
        var high: UInt32?
        while index < scalars.count, scalars[index] != ">" {
            let scalar = scalars[index]
            index += 1
            if scalar.properties.isWhitespace { continue }
            guard let nibble = hexValue(scalar) else { throw failure("invalid data") }
            if let first = high {
                bytes.append(UInt8(first * 16 + nibble))
                high = nil
            } else {
                high = nibble
            }
        }
        guard index < scalars.count, high == nil else { throw failure("unterminated data") }
        index += 1
        return bytes
    }

    private mutating func skipWhitespaceAndComments() {
        while index < scalars.count {
            if scalars[index].properties.isWhitespace {
                index += 1
            } else if scalars[index] == "/", index + 1 < scalars.count, scalars[index + 1] == "/" {
                while index < scalars.count, scalars[index] != "\n", scalars[index] != "\r" {
                    index += 1
                }
            } else if scalars[index] == "/", index + 1 < scalars.count, scalars[index + 1] == "*" {
                index += 2
                while index < scalars.count, !(scalars[index] == "*" && index + 1 < scalars.count && scalars[index + 1] == "/") {
                    index += 1
                }
                index = min(scalars.count, index + 2)
            } else {
                return
            }
        }
    }

    private func peek(_ scalar: Unicode.Scalar) -> Bool {
        index < scalars.count && scalars[index] == scalar
    }

    private func failure(_ message: String) -> TextPropertyListParser.Failure {
        TextPropertyListParser.Failure(message: message)
    }
}

/// The XML property list format: `plist`, `dict`, `key`, `array`, `string`, `integer`,
/// `real`, `true`, `false`, `data` and `date` elements, the five predefined entities and
/// character references, comments, processing instructions, a document type declaration
/// and CDATA sections.
private struct XMLPlistParser {
    let scalars: [Unicode.Scalar]
    var index: Int

    struct Tag {
        var name: String
        var isClosing: Bool
        var isEmpty: Bool
    }

    /// A key or string loses one U+FEFF at its start, written as such or as `&#xFEFF;`, as in
    /// Xcode's XML property list reading (strings-experiments `xml-bom-values`, `xml-bom-keys`,
    /// `bom-forms`; `plutil -convert` does the same). Old-style files keep it.
    static func droppingLeadingByteOrderMark(_ string: String) -> String {
        string.unicodeScalars.first == "\u{FEFF}" ? String(string.unicodeScalars.dropFirst()) : string
    }

    mutating func document() throws -> PropertyListValue {
        var tag = try nextTag()
        if tag.name == "plist" {
            guard !tag.isEmpty else { return .dictionary([:]) }
            tag = try nextTag()
            let result = try element(tag)
            guard try nextTag().name == "plist" else { throw failure("missing </plist>") }
            return result
        }
        return try element(tag)
    }

    private mutating func element(_ tag: Tag) throws -> PropertyListValue {
        guard !tag.isClosing else { throw failure("unexpected </\(tag.name)>") }
        switch tag.name {
        case "dict":
            var entries: [String: PropertyListValue] = [:]
            guard !tag.isEmpty else { return .dictionary(entries) }
            while true {
                let next = try nextTag()
                if next.isClosing, next.name == "dict" { return .dictionary(entries) }
                guard next.name == "key" else { throw failure("expected <key>") }
                let key = Self.droppingLeadingByteOrderMark(try text(of: next))
                entries[key] = try element(try nextTag())
            }
        case "array":
            var elements: [PropertyListValue] = []
            guard !tag.isEmpty else { return .array(elements) }
            while true {
                let next = try nextTag()
                if next.isClosing, next.name == "array" { return .array(elements) }
                elements.append(try element(next))
            }
        case "string":
            return .string(Self.droppingLeadingByteOrderMark(try text(of: tag)))
        case "true", "false":
            if !tag.isEmpty {
                guard try nextTag().name == tag.name else { throw failure("expected </\(tag.name)>") }
            }
            return .boolean(tag.name == "true")
        case "integer":
            let content = try text(of: tag).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let integer = Int(content) else { throw failure("invalid integer '\(content)'") }
            return .integer(integer)
        case "real":
            let content = try text(of: tag).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let real = Double(content) else { throw failure("invalid real '\(content)'") }
            return .real(real)
        case "data":
            let content = try text(of: tag).filter { !$0.isWhitespace }
            guard let data = Data(base64Encoded: content) else { throw failure("invalid data") }
            return .data(Array(data))
        case "date":
            let content = try text(of: tag).trimmingCharacters(in: .whitespacesAndNewlines)
            let formatter = ISO8601DateFormatter()
            guard let date = formatter.date(from: content) else { throw failure("invalid date '\(content)'") }
            return .date(date.timeIntervalSinceReferenceDate)
        default:
            throw failure("unknown element <\(tag.name)>")
        }
    }

    /// The character data up to the end tag of `tag`.
    private mutating func text(of tag: Tag) throws -> String {
        guard !tag.isEmpty else { return "" }
        var result = String.UnicodeScalarView()
        while index < scalars.count {
            if scalars[index] == "<" {
                if starts(with: "<![CDATA[") {
                    index += 9
                    while index < scalars.count, !starts(with: "]]>") {
                        result.append(scalars[index])
                        index += 1
                    }
                    index += 3
                    continue
                }
                if starts(with: "<!--") {
                    try skipComment()
                    continue
                }
                let end = try nextTag()
                guard end.isClosing, end.name == tag.name else { throw failure("expected </\(tag.name)>") }
                return String(result)
            }
            if scalars[index] == "&" {
                result.append(try entity())
            } else {
                result.append(scalars[index])
                index += 1
            }
        }
        throw failure("unterminated <\(tag.name)>")
    }

    private mutating func entity() throws -> Unicode.Scalar {
        guard let semicolon = scalars[index...].firstIndex(of: ";") else { throw failure("unterminated entity") }
        let name = String(String.UnicodeScalarView(scalars[(index + 1)..<semicolon]))
        index = semicolon + 1
        switch name {
        case "lt": return "<"
        case "gt": return ">"
        case "amp": return "&"
        case "quot": return "\""
        case "apos": return "'"
        default:
            let value = name.hasPrefix("#x") ? UInt32(name.dropFirst(2), radix: 16) : name.hasPrefix("#") ? UInt32(name.dropFirst()) : nil
            guard let value, let scalar = Unicode.Scalar(value) else { throw failure("unknown entity &\(name);") }
            return scalar
        }
    }

    /// The next tag, skipping white space, the XML declaration, processing instructions,
    /// comments and the document type declaration.
    private mutating func nextTag() throws -> Tag {
        while true {
            while index < scalars.count, scalars[index].properties.isWhitespace {
                index += 1
            }
            guard index < scalars.count, scalars[index] == "<" else { throw failure("expected a tag") }
            if starts(with: "<?") {
                try skip(past: "?>")
            } else if starts(with: "<!--") {
                try skipComment()
            } else if starts(with: "<!") {
                try skip(past: ">")
            } else {
                break
            }
        }
        index += 1
        let isClosing = peek("/")
        if isClosing { index += 1 }
        let nameStart = index
        while index < scalars.count, !scalars[index].properties.isWhitespace, scalars[index] != ">", scalars[index] != "/" {
            index += 1
        }
        let name = String(String.UnicodeScalarView(scalars[nameStart..<index]))
        while index < scalars.count, scalars[index] != ">" {
            index += 1
        }
        guard index < scalars.count else { throw failure("unterminated tag") }
        let isEmpty = scalars[index - 1] == "/"
        index += 1
        return Tag(name: name, isClosing: isClosing, isEmpty: isEmpty)
    }

    private mutating func skipComment() throws {
        try skip(past: "-->")
    }

    private mutating func skip(past terminator: String) throws {
        while index < scalars.count, !starts(with: terminator) {
            index += 1
        }
        guard index < scalars.count else { throw failure("unterminated markup") }
        index += terminator.unicodeScalars.count
    }

    private func starts(with prefix: String) -> Bool {
        let prefix = Array(prefix.unicodeScalars)
        return index + prefix.count <= scalars.count && Array(scalars[index..<(index + prefix.count)]) == prefix
    }

    private func peek(_ scalar: Unicode.Scalar) -> Bool {
        index < scalars.count && scalars[index] == scalar
    }

    private func failure(_ message: String) -> TextPropertyListParser.Failure {
        TextPropertyListParser.Failure(message: message)
    }
}
