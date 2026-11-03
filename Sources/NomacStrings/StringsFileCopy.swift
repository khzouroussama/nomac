import Foundation
import NomacCore
import NomacPlist

/// What Swift Build's `builtin-copyStrings` makes of a `.strings` or `.stringsdict` file on a
/// Mac (docs/formats/strings.md "Copied strings files", ADR 0250). Off Darwin, Swift Build
/// detects no encoding and its binary property lists differ, so nomac does it here.
public enum StringsFileCopy {
    /// `--outputencoding`: `binary`, or a text encoding the input is converted to.
    public enum OutputEncoding: Equatable, Sendable {
        case binary
        /// `UTF-16`: a byte order mark, then little-endian code units.
        case utf16
        case utf8

        public init(_ name: String) throws {
            switch name.lowercased() {
            case "binary": self = .binary
            case "utf-16": self = .utf16
            case "utf-8": self = .utf8
            default: throw NomacError("output encoding '\(name)' is not supported; nomac writes binary, UTF-16 and UTF-8 (BACKLOG B-252)")
            }
        }
    }

    public struct Result: Equatable, Sendable {
        public var contents: Data
        /// The notes Swift Build prints for the file, without their location.
        public var notes: [String]
    }

    /// Copies `input`. `inputEncoding` is `--inputencoding` (the file reference's encoding);
    /// without it the encoding is detected. With `validate` or binary output the contents
    /// must be a property list.
    public static func copy(_ input: [UInt8], inputEncoding: String? = nil, outputEncoding: OutputEncoding, validate: Bool) throws -> Result {
        var notes: [String] = []
        var string: String
        if let inputEncoding {
            string = try decode(input, as: inputEncoding)
        } else {
            let (decoded, name) = try detect(input)
            string = decoded
            if !string.isEmpty {
                notes.append("detected encoding of input file as \(name)")
            }
        }
        if string.unicodeScalars.first == "\u{FEFF}" {
            notes.append("ignoring byte-order mark in input file")
            string.unicodeScalars.removeFirst()
        }
        var plist: PropertyListValue?
        if outputEncoding == .binary || validate {
            if string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                plist = .dictionary([:])
            } else {
                do {
                    plist = try TextPropertyListParser.parse(string)
                } catch is TextPropertyListParser.Failure {
                    throw NomacError("validation failed: Couldn't parse property list because the input data was in an invalid format")
                }
            }
        }
        switch outputEncoding {
        case .binary:
            return Result(contents: BinaryPropertyList.swiftBuildData(plist!), notes: notes)
        case .utf16:
            guard !string.isEmpty else { return Result(contents: Data(), notes: notes) }
            var bytes: [UInt8] = [0xFF, 0xFE]
            for unit in string.utf16 {
                bytes += [UInt8(unit & 0xFF), UInt8(unit >> 8)]
            }
            return Result(contents: Data(bytes), notes: notes)
        case .utf8:
            return Result(contents: Data(string.utf8), notes: notes)
        }
    }

    /// The encodings a Mac detects in strings files (strings-experiments `copy`): a UTF-8 or
    /// UTF-16 byte order mark, else valid UTF-8 (ASCII included). The mark is not part of
    /// the decoded text.
    static func detect(_ input: [UInt8]) throws -> (String, String) {
        if input.starts(with: [0xEF, 0xBB, 0xBF]) {
            return (String(decoding: input.dropFirst(3), as: UTF8.self), "Unicode (UTF-8)")
        }
        if input.starts(with: [0xFF, 0xFE]) || input.starts(with: [0xFE, 0xFF]) {
            return (try utf16(input.dropFirst(2), littleEndian: input[0] == 0xFF), "Unicode (UTF-16)")
        }
        if let string = validated(input, as: UTF8.self) {
            return (string, "Unicode (UTF-8)")
        }
        throw NomacError("no --inputencoding specified and could not detect encoding from input file", notes: ["nomac detects UTF-8 and UTF-16 with a byte order mark (BACKLOG B-252)"])
    }

    static func decode(_ input: [UInt8], as encoding: String) throws -> String {
        switch encoding.lowercased() {
        case "utf-8":
            guard let string = validated(input, as: UTF8.self) else { break }
            return string
        case "utf-16":
            guard input.starts(with: [0xFF, 0xFE]) || input.starts(with: [0xFE, 0xFF]) else { break }
            return try utf16(input.dropFirst(2), littleEndian: input[0] == 0xFF)
        case "utf-16le":
            return try utf16(input[...], littleEndian: true)
        case "utf-16be":
            return try utf16(input[...], littleEndian: false)
        default:
            throw NomacError("input encoding '\(encoding)' is not supported; nomac reads UTF-8 and UTF-16 (BACKLOG B-252)")
        }
        throw NomacError("could not decode input file using specified encoding: \(encoding)")
    }

    private static func utf16(_ bytes: ArraySlice<UInt8>, littleEndian: Bool) throws -> String {
        guard bytes.count.isMultiple(of: 2) else { throw NomacError("could not decode input file as UTF-16") }
        let units = stride(from: bytes.startIndex, to: bytes.endIndex, by: 2).map { index in
            littleEndian ? UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8 : UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])
        }
        guard let string = validated(units, as: UTF16.self) else { throw NomacError("could not decode input file as UTF-16") }
        return string
    }

    private static func validated<Encoding: Unicode.Encoding, Units: Collection>(_ units: Units, as encoding: Encoding.Type) -> String?
        where Units.Element == Encoding.CodeUnit {
        var scalars = String.UnicodeScalarView()
        let failed = transcode(units.makeIterator(), from: encoding, to: UTF32.self, stoppingOnError: true) { scalars.append(Unicode.Scalar($0)!) }
        return failed ? nil : String(scalars)
    }
}
