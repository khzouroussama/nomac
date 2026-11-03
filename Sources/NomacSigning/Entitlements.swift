import Foundation
import NomacCore

/// Entitlements as codesign embeds them: the file's bytes as given (the XML blob) and their DER
/// encoding, which codesign 27 writes whether or not `--generate-entitlement-der` is passed.
struct Entitlements {
    /// The property list file, byte for byte.
    var xml: [UInt8]
    var value: [String: PropertyListValue]

    init(xml: [UInt8], path: String) throws {
        guard case .dictionary(let entries) = try PropertyListValue.parseXML(Data(xml), path: path) else {
            throw NomacError("Failed to parse entitlements: the root is not a dictionary", path: path)
        }
        self.xml = xml
        value = entries
    }

    /// The executable segment flags these entitlements add (``CodeSignature/entitlementExecutableSegmentFlags``).
    var executableSegmentFlags: UInt64 {
        CodeSignature.entitlementExecutableSegmentFlags.reduce(0) { flags, entry in
            value[entry.0] == .boolean(true) ? flags | entry.1 : flags
        }
    }

    /// The DER form, observed in codesign's output for every value type it accepts:
    /// `[APPLICATION 16] { INTEGER 1, <dictionary> }`, where a dictionary is `[CONTEXT 16]`
    /// holding one `SEQUENCE { UTF8String key, value }` per entry in key order, an array a
    /// `SEQUENCE`, a string a `UTF8String`, a boolean a `BOOLEAN` (0xff or 0) and an integer
    /// the shortest two's-complement `INTEGER`. codesign refuses data, real and date values.
    func der(path: String) throws -> [UInt8] {
        try DER.element(0x70, DER.element(0x02, [1]) + Self.encode(.dictionary(value), path: path))
    }

    private static func encode(_ value: PropertyListValue, path: String) throws -> [UInt8] {
        switch value {
        case .dictionary(let entries):
            var content: [UInt8] = []
            for key in entries.keys.sorted(by: { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }) {
                content += DER.element(0x30, DER.element(0x0c, Array(key.utf8)) + (try encode(entries[key]!, path: path)))
            }
            return DER.element(0xb0, content)
        case .array(let elements):
            return DER.element(0x30, try elements.flatMap { try encode($0, path: path) })
        case .string(let string):
            return DER.element(0x0c, Array(string.utf8))
        case .boolean(let boolean):
            return DER.element(0x01, [boolean ? 0xff : 0])
        case .integer(let integer):
            return DER.element(0x02, DER.integer(integer))
        case .data, .real, .date:
            throw NomacError("Failed to parse entitlements: data, real and date values are not allowed", path: path)
        }
    }
}

/// Distinguished Encoding Rules (ITU-T X.690) for the few element kinds code signing writes.
enum DER {
    /// A tag, its definite length (short form below 128, else long form) and `content`.
    static func element(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        [tag] + length(content.count) + content
    }

    static func length(_ count: Int) -> [UInt8] {
        if count < 0x80 { return [UInt8(count)] }
        var bytes: [UInt8] = []
        var remaining = count
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0xff), at: 0)
            remaining >>= 8
        }
        return [0x80 | UInt8(bytes.count)] + bytes
    }

    /// The shortest two's-complement big-endian form of `value`.
    static func integer(_ value: Int64) -> [UInt8] {
        var bytes = (0..<8).map { UInt8(truncatingIfNeeded: value >> (8 * (7 - $0))) }
        while bytes.count > 1, (bytes[0] == 0 && bytes[1] & 0x80 == 0) || (bytes[0] == 0xff && bytes[1] & 0x80 != 0) {
            bytes.removeFirst()
        }
        return bytes
    }
}

/// The DER form of an XML entitlements file, as `derq query -f xml -i <file> -o <file>` writes it
/// for Swift Build's `ProcessProductPackagingDER` task (`.github/scripts/derq_experiments.py`).
public enum EntitlementsDER {
    public static func encode(xml: [UInt8], path: String) throws -> [UInt8] {
        try Entitlements(xml: xml, path: path).der(path: path)
    }
}
