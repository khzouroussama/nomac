import Foundation

/// Helpers for reading Apple property lists (XML, binary or OpenStep) on any platform.
public enum PropertyLists {
    /// Reads a property list file and returns its root object.
    ///
    /// - Throws: ``NomacError`` naming the file when it cannot be read or parsed.
    public static func read(at path: String) throws -> Any {
        guard let data = FileSystem.contents(atPath: path) else {
            throw NomacError("could not read property list", path: path)
        }
        do {
            return try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw NomacError("malformed property list: \(error.localizedDescription)", path: path)
        }
    }

    /// Reads a property list file whose root object must be a dictionary.
    public static func readDictionary(at path: String) throws -> [String: Any] {
        guard let dict = try read(at: path) as? [String: Any] else {
            throw NomacError("property list root is not a dictionary", path: path)
        }
        return dict
    }

    /// Serializes a dictionary as an XML property list.
    public static func xmlData(_ dictionary: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
    }
}
