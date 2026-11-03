import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import NomacCore

/// A property list value that keeps the types Foundation merges off Apple platforms (a boolean
/// and the integer 1 are both `NSNumber` there), as the DER entitlements need them.
public indirect enum PropertyListValue: Equatable, Sendable {
    case dictionary([String: PropertyListValue])
    case array([PropertyListValue])
    case string(String)
    case integer(Int64)
    case boolean(Bool)
    case real(Double)
    case data([UInt8])
    case date(String)

    /// Parses an XML property list.
    public static func parseXML(_ data: Data, path: String) throws -> PropertyListValue {
        let delegate = XMLPropertyListParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else {
            throw NomacError("malformed XML property list\(delegate.error.map { ": \($0)" } ?? "")", path: path)
        }
        return root
    }

    /// `value` written the way CoreFoundation writes XML property lists (observed in
    /// `_CodeSignature/CodeResources`, in the `ExportOptions.plist` Xcode writes and with
    /// `plutil -convert xml1`): tab indentation, dictionary keys in order, `<dict/>` and
    /// `<array/>` when empty, `&`, `<` and `>` escaped, reals as `%.17g` prints them, and data in
    /// base64 lines of `76 - 8 × depth` characters at the data element's indentation.
    public static func xmlDocument(_ value: PropertyListValue) -> [UInt8] {
        var text = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">

        """
        value.appendXML(to: &text, depth: 0)
        text += "</plist>\n"
        return Array(text.utf8)
    }

    private func appendXML(to text: inout String, depth: Int) {
        let indent = String(repeating: "\t", count: depth)
        switch self {
        case .dictionary(let entries) where entries.isEmpty:
            text += "\(indent)<dict/>\n"
        case .dictionary(let entries):
            text += "\(indent)<dict>\n"
            for key in entries.keys.sorted(by: Self.precedes) {
                text += "\(indent)\t<key>\(Self.escaped(key))</key>\n"
                entries[key]!.appendXML(to: &text, depth: depth + 1)
            }
            text += "\(indent)</dict>\n"
        case .array(let elements) where elements.isEmpty:
            text += "\(indent)<array/>\n"
        case .array(let elements):
            text += "\(indent)<array>\n"
            for element in elements { element.appendXML(to: &text, depth: depth + 1) }
            text += "\(indent)</array>\n"
        case .string(let string):
            text += "\(indent)<string>\(Self.escaped(string))</string>\n"
        case .integer(let integer):
            text += "\(indent)<integer>\(integer)</integer>\n"
        case .boolean(let boolean):
            text += "\(indent)<\(boolean)/>\n"
        case .real(let real):
            text += "\(indent)<real>\(String(format: "%.17g", real))</real>\n"
        case .data(let bytes):
            let base64 = Array(Data(bytes).base64EncodedString().utf8)
            let width = 76 - 8 * depth
            text += "\(indent)<data>\n"
            for start in stride(from: 0, to: base64.count, by: width) {
                text += indent + String(decoding: base64[start..<min(start + width, base64.count)], as: UTF8.self) + "\n"
            }
            text += "\(indent)</data>\n"
        case .date(let date):
            text += "\(indent)<date>\(date)</date>\n"
        }
    }

    /// Key order: by UTF-16 code unit, as CoreFoundation compares strings.
    static func precedes(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf16.lexicographicallyPrecedes(rhs.utf16)
    }

    private static func escaped(_ string: String) -> String {
        guard string.contains(where: { $0 == "&" || $0 == "<" || $0 == ">" }) else { return string }
        return string.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

/// Builds a ``PropertyListValue`` from `XMLParser` events.
private final class XMLPropertyListParser: NSObject, XMLParserDelegate {
    private enum Container {
        case dictionary([String: PropertyListValue], pendingKey: String?)
        case array([PropertyListValue])
    }

    var root: PropertyListValue?
    var error: String?
    private var stack: [Container] = []
    private var characters = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        characters = ""
        switch elementName {
        case "dict": stack.append(.dictionary([:], pendingKey: nil))
        case "array": stack.append(.array([]))
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        characters += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let text = characters
        characters = ""
        switch elementName {
        case "plist":
            return
        case "key":
            guard case .dictionary(let entries, nil)? = stack.last else { return fail(parser, "misplaced <key>") }
            stack[stack.count - 1] = .dictionary(entries, pendingKey: text)
        case "dict":
            guard case .dictionary(let entries, nil)? = stack.popLast() else { return fail(parser, "unbalanced <dict>") }
            add(.dictionary(entries), parser)
        case "array":
            guard case .array(let elements)? = stack.popLast() else { return fail(parser, "unbalanced <array>") }
            add(.array(elements), parser)
        case "string":
            add(.string(text), parser)
        case "integer":
            guard let integer = Int64(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return fail(parser, "bad <integer>") }
            add(.integer(integer), parser)
        case "real":
            guard let real = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return fail(parser, "bad <real>") }
            add(.real(real), parser)
        case "true", "false":
            add(.boolean(elementName == "true"), parser)
        case "data":
            guard let data = Data(base64Encoded: text.filter { !$0.isWhitespace }) else { return fail(parser, "bad <data>") }
            add(.data([UInt8](data)), parser)
        case "date":
            add(.date(text), parser)
        default:
            fail(parser, "unknown element <\(elementName)>")
        }
    }

    private func add(_ value: PropertyListValue, _ parser: XMLParser) {
        switch stack.last {
        case nil:
            root = value
        case .dictionary(var entries, let key?)?:
            entries[key] = value
            stack[stack.count - 1] = .dictionary(entries, pendingKey: nil)
        case .dictionary(_, nil)?:
            fail(parser, "value without a <key>")
        case .array(var elements)?:
            elements.append(value)
            stack[stack.count - 1] = .array(elements)
        }
    }

    private func fail(_ parser: XMLParser, _ message: String) {
        error = message
        parser.abortParsing()
    }
}
