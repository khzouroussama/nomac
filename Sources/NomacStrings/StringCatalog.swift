import Foundation
import NomacCore

/// A string catalog (`.xcstrings`), the JSON document Xcode edits (docs/formats/strings.md).
/// Only the members the compiler and the symbol generator read are decoded.
public struct StringCatalog: Decodable, Sendable {
    public var sourceLanguage: String
    public var strings: [String: Entry]

    public struct Entry: Decodable, Sendable {
        public var extractionState: String?
        public var comment: String?
        public var localizations: [String: Localization]?
    }

    public struct Localization: Decodable, Sendable {
        public var stringUnit: StringUnit?
        public var stringSet: StringSet?
        public var variations: Variations?
        public var substitutions: [String: Substitution]?
    }

    public struct StringUnit: Decodable, Sendable {
        public var state: String?
        public var value: String
    }

    public struct StringSet: Decodable, Sendable {
        public var values: [String]
    }

    public struct Variations: Decodable, Sendable {
        public var plural: [String: Localization]?
        public var device: [String: Localization]?
        public var width: [String: Localization]?
    }

    public struct Substitution: Decodable, Sendable {
        public var argNum: Int?
        public var formatSpecifier: String?
        public var variations: Variations?
    }

    /// Reads the catalog at `path`.
    public static func read(at path: String) throws -> StringCatalog {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw NomacError("could not read string catalog", path: path)
        }
        do {
            return try JSONDecoder().decode(StringCatalog.self, from: data)
        } catch {
            throw NomacError("malformed string catalog: \(error)", path: path)
        }
    }
}
