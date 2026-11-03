import Foundation
import NomacCore

/// Compares a PIF nomac generated with the PIF `xcodebuild -dumpPIF` wrote.
///
/// Four rewrites are applied to both documents before a byte comparison:
///
/// - machine-specific path roots (``PathNormalizer``);
/// - the order of package projects: Xcode lists them in an order that changes with the
///   checkout path (docs/adr/0010-swift-packages.md), so each package project and the target
///   objects that follow it are moved, in GUID order, after the workspace's own projects;
/// - object signatures: opaque transfer keys that only need to be unique within a document
///   (Xcode derives them from its in-memory state), each replaced by `<TYPE-index>`, the type
///   and position of the object it names;
/// - the base64 GUIDs of synchronized-folder members, whose derivation Xcode does not document
///   (docs/adr/0009-synchronized-folder-identifiers.md): each is replaced by `<SYNCHRONIZED-n>`,
///   numbered in order of first appearance. A member's file reference first appears in the
///   group tree, so build phases that list the same members in a different order still differ.
///   The GUIDs Xcode draws at random for a synchronized variant group with neither a
///   development-region nor a `Base` variant, and for its build files, are numbered with them,
///   and so are those of the build files that name the file references the caller gives (the
///   variant group children Xcode lifts out of their group, docs/formats/pif.md).
///
/// Every other byte must match.
public enum PIFComparison {
    public struct Result: Sendable, Equatable {
        public var identical: Bool
        /// The first differing line of each document, when they differ.
        public var firstDifference: (expected: String, actual: String)?

        public static func == (lhs: Result, rhs: Result) -> Bool {
            lhs.identical == rhs.identical && lhs.firstDifference?.expected == rhs.firstDifference?.expected && lhs.firstDifference?.actual == rhs.firstDifference?.actual
        }
    }

    public static func compare(expected: String, actual: String, normalizer: PathNormalizer, randomBuildFileReferences: Set<String> = []) throws -> Result {
        let a = try canonicalize(normalizer.normalize(expected), randomBuildFileReferences: randomBuildFileReferences)
        let b = try canonicalize(normalizer.normalize(actual), randomBuildFileReferences: randomBuildFileReferences)
        if a == b { return Result(identical: true, firstDifference: nil) }
        let linesA = a.split(separator: "\n", omittingEmptySubsequences: false)
        let linesB = b.split(separator: "\n", omittingEmptySubsequences: false)
        for index in 0..<max(linesA.count, linesB.count) {
            let x = index < linesA.count ? String(linesA[index]) : "<end of document>"
            let y = index < linesB.count ? String(linesB[index]) : "<end of document>"
            if x != y {
                return Result(identical: false, firstDifference: ("line \(index + 1): \(x)", "line \(index + 1): \(y)"))
            }
        }
        return Result(identical: false, firstDifference: nil)
    }

    /// Puts package projects in GUID order, then replaces every top-level object's signature
    /// with `<TYPE-index>` and every synchronized-member GUID with `<SYNCHRONIZED-n>`.
    static func canonicalize(_ text: String, randomBuildFileReferences: Set<String> = []) throws -> String {
        try canonicalizeSynchronizedGUIDs(canonicalizeRandomGUIDs(canonicalizeSignatures(canonicalizePackageOrder(text)), buildFileReferences: randomBuildFileReferences))
    }

    /// Replaces the GUIDs Xcode draws at random for a synchronized folder's variant group that
    /// has neither a development-region nor a `Base` variant, and for the build files that name
    /// it, with a synchronized-member GUID derived from each: they change from one dump of a
    /// project to the next (pif-experiments `hexguid-*`; firefox's `InfoPlist.strings` in
    /// `ActionExtension`). Such a group is a variant group whose GUID is not a synchronized
    /// member's while its children's are. So are the GUIDs of the build files that name one of
    /// `buildFileReferences`.
    static func canonicalizeRandomGUIDs(_ text: String, buildFileReferences: Set<String> = []) throws -> String {
        guard let objects = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]] else {
            throw NomacError("a PIF document must be a JSON array of objects")
        }
        let contents = objects.map { $0["contents"] as? [String: Any] ?? [:] }
        var random: Set<String> = []
        func walk(_ node: [String: Any]) {
            let children = node["children"] as? [[String: Any]] ?? []
            if node["type"] as? String == "variantGroup", let guid = node["guid"] as? String, !isSynchronizedGUID(guid), !children.isEmpty,
               children.allSatisfy({ ($0["guid"] as? String).map(isSynchronizedGUID) ?? false }) {
                random.insert(guid)
            }
            children.forEach(walk)
        }
        contents.compactMap { $0["groupTree"] as? [String: Any] }.forEach(walk)
        guard !random.isEmpty || !buildFileReferences.isEmpty else { return text }
        let buildFiles = contents.flatMap { ($0["buildPhases"] as? [[String: Any]] ?? []).flatMap { $0["buildFiles"] as? [[String: Any]] ?? [] } }
        var randomBuildFiles: Set<String> = []
        for file in buildFiles {
            guard let reference = file["fileReference"] as? String, let guid = file["guid"] as? String else { continue }
            if random.contains(reference) || buildFileReferences.contains(reference) { randomBuildFiles.insert(guid) }
        }
        random.formUnion(randomBuildFiles)
        return random.reduce(text) { $0.replacingOccurrences(of: "\"\($1)\"", with: "\"\(SHA256.base64($1))\"") }
    }

    private static func isSynchronizedGUID(_ guid: String) -> Bool {
        let quoted = "\"\(guid)\""
        return synchronizedGUID.firstMatch(in: quoted, range: NSRange(location: 0, length: (quoted as NSString).length)) != nil
    }

    /// Moves each package project (`projectIsPackage`), with the target objects that follow
    /// it, after the other projects in GUID order, and lists the workspace's projects in the
    /// new order. A document without a workspace or package projects is returned unchanged.
    static func canonicalizePackageOrder(_ text: String) throws -> String {
        guard var objects = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]] else {
            throw NomacError("a PIF document must be a JSON array of objects")
        }
        guard var workspace = objects.first, workspace["type"] as? String == "workspace" else { return text }
        var groups: [[[String: Any]]] = []
        for object in objects.dropFirst() {
            if object["type"] as? String == "project" || groups.isEmpty {
                groups.append([object])
            } else {
                groups[groups.count - 1].append(object)
            }
        }
        func contents(_ group: [[String: Any]]) -> [String: Any] { group.first?["contents"] as? [String: Any] ?? [:] }
        func isPackage(_ group: [[String: Any]]) -> Bool { contents(group)["projectIsPackage"] as? String == "true" }
        guard groups.contains(where: isPackage) else { return text }
        let ordered = groups.filter { !isPackage($0) }
            + groups.filter(isPackage).sorted { (contents($0)["guid"] as? String ?? "") < (contents($1)["guid"] as? String ?? "") }
        var workspaceContents = workspace["contents"] as? [String: Any] ?? [:]
        workspaceContents["projects"] = ordered.compactMap { $0.first?["signature"] as? String }
        workspace["contents"] = workspaceContents
        objects = [workspace] + ordered.flatMap { $0 }
        let data = try JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    static func canonicalizeSignatures(_ text: String) throws -> String {
        guard let objects = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]] else {
            throw NomacError("a PIF document must be a JSON array of objects")
        }
        var result = text
        for (index, object) in objects.enumerated() {
            guard let signature = object["signature"] as? String, let type = object["type"] as? String else {
                throw NomacError("PIF object \(index) has no type or signature")
            }
            result = result.replacingOccurrences(of: "\"\(signature)\"", with: "\"<\(type.uppercased())-\(index)>\"")
        }
        return result
    }

    /// A JSON string that is a synchronized-member GUID: the base64 encoding of 32 bytes.
    private static let synchronizedGUID = try! NSRegularExpression(pattern: #""[A-Za-z0-9+/]{43}=""#)

    static func canonicalizeSynchronizedGUIDs(_ text: String) -> String {
        let source = text as NSString
        var numbers: [String: Int] = [:]
        var result = ""
        var position = 0
        for match in synchronizedGUID.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let guid = source.substring(with: match.range)
            let number = numbers[guid] ?? numbers.count
            numbers[guid] = number
            result += source.substring(with: NSRange(location: position, length: match.range.location - position))
            result += "\"<SYNCHRONIZED-\(number)>\""
            position = match.range.location + match.range.length
        }
        return result + source.substring(from: position)
    }
}
