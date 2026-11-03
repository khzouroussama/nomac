import Foundation

/// A JSON value in a PIF document.
///
/// PIF only uses strings, arrays and objects: booleans are the strings `"true"` and
/// `"false"`, and numbers appear only where Swift Build expects them (provisioning style).
public indirect enum PIFValue: Equatable, Sendable {
    case string(String)
    case int(Int)
    case array([PIFValue])
    case object([String: PIFValue])

    /// A PIF boolean (`"true"` or `"false"`).
    public static func bool(_ value: Bool) -> PIFValue { .string(value ? "true" : "false") }

    /// The value as a string, if it is one.
    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// The value as an object, if it is one.
    public var objectValue: [String: PIFValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// The value as an array, if it is one.
    public var arrayValue: [PIFValue]? {
        if case .array(let value) = self { return value }
        return nil
    }
}

extension PIFValue {
    /// Serializes the value exactly as Foundation's `JSONSerialization` does on Apple
    /// platforms with `[.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]`, which is the
    /// format `xcodebuild -dumpPIF` writes: two-space indentation, `" : "` between keys and
    /// values, keys in ascending order, empty containers printed with an empty line inside,
    /// and no trailing newline. The format is documented in docs/formats/pif.md.
    public func serialized() -> String {
        var out = ""
        write(into: &out, indent: 0)
        return out
    }

    private func write(into out: inout String, indent: Int) {
        switch self {
        case .string(let value):
            Self.writeString(value, into: &out)
        case .int(let value):
            out += String(value)
        case .array(let elements):
            out += "[\n"
            if elements.isEmpty {
                out += "\n"
            } else {
                for (index, element) in elements.enumerated() {
                    out += String(repeating: " ", count: indent + 2)
                    element.write(into: &out, indent: indent + 2)
                    out += index == elements.count - 1 ? "\n" : ",\n"
                }
            }
            out += String(repeating: " ", count: indent) + "]"
        case .object(let members):
            out += "{\n"
            if members.isEmpty {
                out += "\n"
            } else {
                let keys = members.keys.sorted(by: Self.keyOrder)
                for (index, key) in keys.enumerated() {
                    out += String(repeating: " ", count: indent + 2)
                    Self.writeString(key, into: &out)
                    out += " : "
                    members[key]!.write(into: &out, indent: indent + 2)
                    out += index == keys.count - 1 ? "\n" : ",\n"
                }
            }
            out += String(repeating: " ", count: indent) + "}"
        }
    }

    /// Key order used by Foundation's `JSONSerialization` `.sortedKeys`: the comparison
    /// `String.compare(_:options:)` makes with `[.numeric, .caseInsensitive, .forcedOrdering]`.
    /// Letters compare without regard to case (so `_` sorts before letters), runs of digits
    /// compare by numeric value, and strings that are equal under those rules are ordered by
    /// their UTF-16 code units.
    static func keyOrder(_ lhs: String, _ rhs: String) -> Bool {
        let order = foldedCompare(Array(lhs.utf16), Array(rhs.utf16))
        if order != 0 { return order < 0 }
        return Array(lhs.utf16).lexicographicallyPrecedes(Array(rhs.utf16))
    }

    private static func isDigit(_ unit: UInt16) -> Bool { unit >= 0x30 && unit <= 0x39 }

    private static func folded(_ unit: UInt16) -> UInt16 {
        (unit >= 0x41 && unit <= 0x5A) ? unit + 0x20 : unit
    }

    /// Compares case-insensitively with numeric digit runs; returns -1, 0 or 1.
    private static func foldedCompare(_ a: [UInt16], _ b: [UInt16]) -> Int {
        var i = 0, j = 0
        while i < a.count && j < b.count {
            if isDigit(a[i]) && isDigit(b[j]) {
                var iEnd = i, jEnd = j
                while iEnd < a.count && isDigit(a[iEnd]) { iEnd += 1 }
                while jEnd < b.count && isDigit(b[jEnd]) { jEnd += 1 }
                var x = Array(a[i..<iEnd]), y = Array(b[j..<jEnd])
                while x.count > 1 && x.first == 0x30 { x.removeFirst() }
                while y.count > 1 && y.first == 0x30 { y.removeFirst() }
                if x.count != y.count { return x.count < y.count ? -1 : 1 }
                if x != y { return x.lexicographicallyPrecedes(y) ? -1 : 1 }
                i = iEnd
                j = jEnd
                continue
            }
            let x = folded(a[i]), y = folded(b[j])
            if x != y { return x < y ? -1 : 1 }
            i += 1
            j += 1
        }
        if i < a.count { return 1 }
        if j < b.count { return -1 }
        return 0
    }

    private static func writeString(_ value: String, into out: inout String) {
        out += "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
    }
}
