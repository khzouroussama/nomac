import Foundation

/// Writes XML property lists byte for byte as Xcode's tools write them
/// (docs/formats/property-lists.md "XML"): tab indentation, `&`, `<` and `>` escaped and nothing
/// else, empty containers as `<dict/>` and `<array/>`, reals with 17 significant digits, data as
/// indented base64 lines, dates in ISO 8601 UTC.
public enum XMLPropertyList {
    /// How dictionary keys are sorted.
    public enum KeyOrder: Sendable {
        /// By UTF-16 code units, as Core Foundation sorts them (`plutil`, `.strings` tables).
        case utf16CodeUnits
        /// As Swift compares strings, by the scalars of their canonical composition
        /// (`xcstringstool`'s `.stringsdict` tables).
        case swiftString

        func sorted(_ keys: Dictionary<String, PropertyListValue>.Keys) -> [String] {
            switch self {
            case .utf16CodeUnits: keys.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
            case .swiftString: keys.sorted()
            }
        }
    }

    static let header = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">

        """

    /// The XML property list of `value`.
    public static func data(_ value: PropertyListValue, keyOrder: KeyOrder = .utf16CodeUnits) -> Data {
        var text = header
        append(value, depth: 0, keyOrder: keyOrder, to: &text)
        text += "</plist>\n"
        return Data(text.utf8)
    }

    private static func append(_ value: PropertyListValue, depth: Int, keyOrder: KeyOrder, to text: inout String) {
        let indent = String(repeating: "\t", count: depth)
        switch value {
        case .string(let string):
            text += "\(indent)<string>\(escaped(string))</string>\n"
        case .integer(let integer):
            text += "\(indent)<integer>\(integer)</integer>\n"
        case .real(let real):
            text += "\(indent)<real>\(String(format: "%.17g", real))</real>\n"
        case .boolean(let boolean):
            text += "\(indent)<\(boolean ? "true" : "false")/>\n"
        case .date(let date):
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = TimeZone(identifier: "UTC")
            text += "\(indent)<date>\(formatter.string(from: Date(timeIntervalSinceReferenceDate: date)))</date>\n"
        case .data(let bytes):
            // Base64 lines of 76 - 8 * depth characters (`plutil -convert xml1`, depths 1 to 8).
            let encoded = Array(Data(bytes).base64EncodedString().utf8)
            let lineLength = max(4, 76 - 8 * depth)
            text += "\(indent)<data>\n"
            for start in stride(from: 0, to: encoded.count, by: lineLength) {
                text += indent + String(decoding: encoded[start..<min(start + lineLength, encoded.count)], as: UTF8.self) + "\n"
            }
            text += "\(indent)</data>\n"
        case .array(let elements):
            guard !elements.isEmpty else {
                text += "\(indent)<array/>\n"
                return
            }
            text += "\(indent)<array>\n"
            for element in elements {
                append(element, depth: depth + 1, keyOrder: keyOrder, to: &text)
            }
            text += "\(indent)</array>\n"
        case .dictionary(let entries):
            guard !entries.isEmpty else {
                text += "\(indent)<dict/>\n"
                return
            }
            text += "\(indent)<dict>\n"
            for key in keyOrder.sorted(entries.keys) {
                text += "\(indent)\t<key>\(escaped(key))</key>\n"
                append(entries[key]!, depth: depth + 1, keyOrder: keyOrder, to: &text)
            }
            text += "\(indent)</dict>\n"
        }
    }

    private static func escaped(_ string: String) -> String {
        var result = ""
        result.reserveCapacity(string.utf8.count)
        for character in string.unicodeScalars {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            default: result.unicodeScalars.append(character)
            }
        }
        return result
    }
}
