import Foundation

/// JSON as Darwin's Foundation writes it, which corelibs Foundation does not reproduce: keys
/// sorted, or in the order of the dictionary written (`orderedObject`), `/` escaped as `\/`,
/// compact without spaces or pretty with two-space indentation, ` : ` between a key and its
/// value, and an empty object or array written open with an empty line (`{\n\n  }`). Observed in
/// Xcode 27.0's App Intents outputs (`extract.actionsdata`, `version.json`, the strings data;
/// `.github/scripts/app_intents_experiments.py`) and Core ML's `metadata.json`
/// (`coreml_experiments.py`).
public indirect enum FoundationJSON: Equatable, Sendable {
    case string(String)
    case int(Int)
    /// A number written as Darwin's encoder writes it: `0.5`, `1` for 1.0 (`types`).
    case double(Double)
    case bool(Bool)
    case array([FoundationJSON])
    case object([String: FoundationJSON])
    /// An object whose keys are written in the order given: an `NSDictionary`'s iteration order.
    case orderedObject([Member])

    public struct Member: Equatable, Sendable {
        public var key: String
        public var value: FoundationJSON

        public init(_ key: String, _ value: FoundationJSON) {
            self.key = key
            self.value = value
        }
    }

    /// The value written on one line.
    public var compact: String {
        var text = ""
        write(into: &text, indent: nil)
        return text
    }

    /// The value written over lines, indented by two spaces per level.
    public var pretty: String {
        var text = ""
        write(into: &text, indent: 0)
        return text
    }

    private func write(into text: inout String, indent: Int?) {
        switch self {
        case .string(let value):
            Self.quote(value, into: &text)
        case .int(let value):
            text += String(value)
        case .double(let value):
            text += value.rounded() == value && abs(value) < 1e15 ? String(Int(value)) : "\(value)"
        case .bool(let value):
            text += value ? "true" : "false"
        case .array(let values):
            Self.container("[", "]", values.map { (nil, $0) }, into: &text, indent: indent)
        case .object(let members):
            Self.container("{", "}", members.keys.sorted().map { ($0, members[$0]!) }, into: &text, indent: indent)
        case .orderedObject(let members):
            Self.container("{", "}", members.map { ($0.key, $0.value) }, into: &text, indent: indent)
        }
    }

    private static func container(_ open: String, _ close: String, _ items: [(String?, FoundationJSON)], into text: inout String, indent: Int?) {
        text += open
        guard let indent else {
            for (index, (key, value)) in items.enumerated() {
                if index > 0 { text += "," }
                if let key { quote(key, into: &text); text += ":" }
                value.write(into: &text, indent: nil)
            }
            text += close
            return
        }
        let inner = String(repeating: "  ", count: indent + 1)
        if items.isEmpty {
            text += "\n\n" + String(repeating: "  ", count: indent) + close
            return
        }
        for (index, (key, value)) in items.enumerated() {
            text += (index > 0 ? ",\n" : "\n") + inner
            if let key { quote(key, into: &text); text += " : " }
            value.write(into: &text, indent: indent + 1)
        }
        text += "\n" + String(repeating: "  ", count: indent) + close
    }

    private static func quote(_ value: String, into text: inout String) {
        text += "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": text += "\\\""
            case "\\": text += "\\\\"
            case "/": text += "\\/"
            case "\n": text += "\\n"
            case "\r": text += "\\r"
            case "\t": text += "\\t"
            case _ where scalar.value < 0x20: text += String(format: "\\u%04x", scalar.value)
            default: text.unicodeScalars.append(scalar)
            }
        }
        text += "\""
    }
}
