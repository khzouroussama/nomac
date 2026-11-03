import Foundation
import NomacCore

/// The text codesign prints for a requirement program (`codesign -r- --display`), for the
/// operators nomac signs with or meets in Swift's back-deployment libraries (opcodes from the
/// public `<Security/CSCommon.h>` requirement language; printing as Security's open-source
/// `reqdumper.cpp` does, ADR 0301, and as observed).
enum RequirementText {
    /// The text of a requirement blob (`0xfade0c00`, kind 1, then the expression).
    static func text(_ requirement: [UInt8], path: String) throws -> String {
        var reader = Reader(bytes: requirement, offset: 12)
        return try reader.expression(level: .top, path: path)
    }

    private enum Level: Int, Comparable {
        case primary, and, or, top
        static func < (left: Level, right: Level) -> Bool { left.rawValue < right.rawValue }
    }

    /// Words of the requirement language, which identifiers that equal one are quoted against.
    private static let keywords: Set<String> = [
        "guest", "host", "designated", "library", "plugin", "or", "and", "always", "true", "never", "false", "identifier", "cdhash",
        "platform", "notarized", "legacy", "anchor", "apple", "generic", "certificate", "cert", "trusted", "info", "entitlement",
        "exists", "absent", "leaf", "root", "timestamp", "",
    ]

    private struct Reader {
        let bytes: [UInt8]
        var offset: Int

        mutating func word(path: String) throws -> UInt32 {
            guard offset + 4 <= bytes.count else { throw NomacError("malformed requirement", path: path) }
            defer { offset += 4 }
            return (0..<4).reduce(0) { $0 << 8 | UInt32(bytes[offset + $1]) }
        }

        mutating func data(path: String) throws -> [UInt8] {
            let length = Int(try word(path: path))
            guard offset + length <= bytes.count else { throw NomacError("malformed requirement", path: path) }
            defer { offset += (length + 3) / 4 * 4 }
            return Array(bytes[offset..<(offset + length)])
        }

        mutating func expression(level: Level, path: String) throws -> String {
            let operation = try word(path: path) & 0x00ff_ffff
            switch operation {
            case 0: return "never"
            case 1: return "always"
            case 2: return "identifier " + Self.printed(try data(path: path))
            case 3: return "anchor apple"
            case 15: return "anchor apple generic"
            case 4:
                let slot = Int32(bitPattern: try word(path: path))
                return "certificate\(Self.slot(slot)) = H\"\(Self.hex(try data(path: path)))\""
            case 8: return "cdhash H\"\(Self.hex(try data(path: path)))\""
            case 6, 7:
                let (word, own): (String, Level) = operation == 6 ? ("and", .and) : ("or", .or)
                let left = try expression(level: own, path: path), right = try expression(level: own, path: path)
                let text = "\(left) \(word) \(right)"
                return level < own ? "(\(text))" : text
            case 9: return "! " + (try expression(level: .primary, path: path))
            case 11:
                let slot = Int32(bitPattern: try word(path: path))
                return "certificate\(Self.slot(slot))[\(Self.printed(try data(path: path), dotted: true))]" + (try match(path: path))
            case 14:
                let slot = Int32(bitPattern: try word(path: path))
                return "certificate\(Self.slot(slot))[field.\(Self.objectIdentifier(try data(path: path)))]" + (try match(path: path))
            default:
                throw NomacError("requirement operator \(operation) is not supported yet (BACKLOG B-302)", path: path)
            }
        }

        /// The match suffix of a field operator.
        mutating func match(path: String) throws -> String {
            let operation = try word(path: path)
            switch operation {
            case 0: return " /* exists */"
            case 14: return " absent "
            case 1...8:
                let value = Self.printed(try data(path: path))
                return [" = \(value)", " ~ \(value)", " = \(value)*", " = *\(value)", " < \(value)", " > \(value)", " <= \(value)",
                        " >= \(value)"][Int(operation) - 1]
            default:
                throw NomacError("requirement match operation \(operation) is not supported yet (BACKLOG B-302)", path: path)
            }
        }

        /// A DER object identifier's contents in dotted form: 40 × X + Y, then base-128 arcs.
        static func objectIdentifier(_ bytes: [UInt8]) -> String {
            var arcs: [UInt64] = []
            var value: UInt64 = 0
            for byte in bytes {
                value = value << 7 | UInt64(byte & 0x7f)
                if byte & 0x80 == 0 {
                    if arcs.isEmpty { arcs += value < 80 ? [value / 40, value % 40] : [2, value - 80] } else { arcs.append(value) }
                    value = 0
                }
            }
            return arcs.map(String.init).joined(separator: ".")
        }

        static func slot(_ slot: Int32) -> String {
            switch slot {
            case -1: " root"
            case 0: " leaf"
            default: " \(slot)"
            }
        }

        static func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

        /// Bare when alphanumeric (dots allowed in field names), not starting with a digit and
        /// not a keyword; quoted (with `\` and `"` escaped) when printable; else `0x` and the hex.
        static func printed(_ bytes: [UInt8], dotted: Bool = false) -> String {
            func isAlphanumeric(_ byte: UInt8) -> Bool {
                (0x30...0x39).contains(byte) || (0x41...0x5a).contains(byte) || (0x61...0x7a).contains(byte) || (dotted && byte == 0x2e)
            }
            func isPrintable(_ byte: UInt8) -> Bool { (0x21...0x7e).contains(byte) || (0x09...0x0d).contains(byte) || byte == 0x20 }
            guard bytes.allSatisfy({ isAlphanumeric($0) || isPrintable($0) }) else { return "0x" + hex(bytes) }
            let text = String(decoding: bytes, as: UTF8.self)
            let simple = bytes.allSatisfy(isAlphanumeric) && !(bytes.first.map { (0x30...0x39).contains($0) } ?? false) && !keywords.contains(text)
            if simple { return text }
            return "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
    }
}
