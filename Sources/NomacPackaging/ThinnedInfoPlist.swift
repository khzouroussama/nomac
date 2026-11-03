import Foundation
import NomacCore
import NomacPlist

/// The Info.plist a thinned variant's app gets (docs/formats/ipa.md "App thinning",
/// `distribution_experiments.py` `thinning`): the app's binary property list as Foundation reads
/// it, each dictionary's keys in the order of a Foundation dictionary created with them in the
/// file's order (`catalog-185`, whose file `plutil` wrote in another order than Swift Build's),
/// the added keys after the top one's, written as XML indented by two spaces, data as base64 on
/// a line of its own, `&`, `<` and `>` escaped.
struct ThinnedInfoPlist {
    /// A value to write: an object of the file, or one of the added values.
    enum Item {
        case object(Int)
        case value(PropertyListValue)
    }

    let objects: [BinaryPropertyList.Object]
    let path: String

    /// Adds `DTAppStoreToolsBuild` (Xcode's build) and `UISupportedDevices` (the variant's
    /// product types, in byte order); `replacing` gives existing keys other strings in their place
    /// (a watch variant's `MinimumOSVersion`).
    static func rewrite(at path: String, devices: [String], replacing: [String: String] = [:]) throws {
        guard let data = FileManager.default.contents(atPath: path) else { throw NomacError("could not read file", path: path) }
        let bytes = [UInt8](data)
        guard bytes.starts(with: Array("bplist00".utf8)) else {
            throw NomacError("exportArchive app thinning of an app whose Info.plist is not a binary property list is not supported yet (BACKLOG B-465)",
                             path: path, exitStatus: 70)
        }
        let (objects, top) = try BinaryPropertyList.objects(from: bytes, path: path)
        let plist = ThinnedInfoPlist(objects: objects, path: path)
        guard case .dictionary(let keys, let values) = objects[top] else { throw NomacError("the app's Info.plist is not a dictionary", path: path) }
        let added: [(String, Item)] = [
            ("DTAppStoreToolsBuild", .value(.string(XcodeProfile.current.xcode.build))),
            ("UISupportedDevices", .value(.array(devices.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }.map(PropertyListValue.string)))),
        ]
        var text = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            + "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
            + "<plist version=\"1.0\">\n"
        let entries = try plist.entries(keys: keys, values: values).map { key, item in (key, replacing[key].map { Item.value(.string($0)) } ?? item) }
        try plist.append(entries: entries + added, depth: 1, to: &text)
        text += "</plist>\n"
        let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int ?? 0o644
        try FileSystem.write(Data(text.utf8), to: path)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: path)
    }

    /// A dictionary's entries in Foundation's order for keys read in the file's order.
    func entries(keys: [Int], values: [Int]) throws -> [(String, Item)] {
        let names = try keys.map { key -> String in
            guard case .string(let name) = objects[key] else { throw NomacError("a dictionary key that is not a string", path: path) }
            return name
        }
        let byName = Dictionary(zip(names, values.map(Item.object)), uniquingKeysWith: { first, _ in first })
        return try FoundationHashTable.created(with: names).keys.map { ($0, byName[$0]!) }
    }

    func append(entries: [(String, Item)], depth: Int, to text: inout String) throws {
        let indent = String(repeating: "  ", count: depth)
        guard !entries.isEmpty else {
            text += indent + "<dict/>\n"
            return
        }
        text += indent + "<dict>\n"
        for (key, item) in entries {
            text += indent + "  <key>" + Self.escaped(key) + "</key>\n"
            try append(item, depth: depth + 1, to: &text)
        }
        text += indent + "</dict>\n"
    }

    func append(_ item: Item, depth: Int, to text: inout String) throws {
        let indent = String(repeating: "  ", count: depth)
        func items(_ list: [Item]) throws {
            guard !list.isEmpty else {
                text += indent + "<array/>\n"
                return
            }
            text += indent + "<array>\n"
            for element in list { try append(element, depth: depth + 1, to: &text) }
            text += indent + "</array>\n"
        }
        switch item {
        case .object(let index):
            switch objects[index] {
            case .array(let elements): try items(elements.map(Item.object))
            case .dictionary(let keys, let values): try append(entries: try entries(keys: keys, values: values), depth: depth, to: &text)
            case .string(let string): try append(.value(.string(string)), depth: depth, to: &text)
            case .integer(let integer): try append(.value(.integer(integer)), depth: depth, to: &text)
            case .real(let real): try append(.value(.real(real)), depth: depth, to: &text)
            case .boolean(let boolean): try append(.value(.boolean(boolean)), depth: depth, to: &text)
            case .date(let date): try append(.value(.date(date)), depth: depth, to: &text)
            case .data(let data): try append(.value(.data(data)), depth: depth, to: &text)
            case .float, .uid:
                throw NomacError("exportArchive app thinning of an Info.plist with a 4-byte real or a keyed-archive reference is not supported yet (BACKLOG B-465)",
                                 path: path, exitStatus: 70)
            }
        case .value(let value):
            switch value {
            case .string(let string): text += indent + "<string>" + Self.escaped(string) + "</string>\n"
            case .integer(let integer): text += indent + "<integer>\(integer)</integer>\n"
            case .real(let real):
                let written = "\(real)"
                guard !written.contains("e"), !written.contains("n"), !written.contains("i") else {
                    throw NomacError("exportArchive app thinning of an Info.plist with the real number \(written) is not supported yet (BACKLOG B-465)", path: path, exitStatus: 70)
                }
                text += indent + "<real>" + written + "</real>\n"
            case .boolean(let boolean): text += indent + (boolean ? "<true/>" : "<false/>") + "\n"
            case .date(let seconds):
                let formatter = ISO8601DateFormatter()
                formatter.timeZone = TimeZone(identifier: "UTC")
                text += indent + "<date>" + formatter.string(from: Date(timeIntervalSinceReferenceDate: seconds)) + "</date>\n"
            case .data(let bytes):
                let base64 = Data(bytes).base64EncodedString()
                guard base64.count <= 60 else {
                    throw NomacError("exportArchive app thinning of an Info.plist with data over 45 bytes is not supported yet (BACKLOG B-465)", path: path, exitStatus: 70)
                }
                text += indent + "<data>\n" + base64 + "\n</data>\n"
            case .array(let elements): try items(elements.map(Item.value))
            case .dictionary(let entries):
                try append(entries: try FoundationHashTable.created(with: entries.keys.sorted()).keys.map { ($0, Item.value(entries[$0]!)) }, depth: depth, to: &text)
            }
        }
    }

    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}
