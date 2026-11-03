import NomacPlist

/// `VersionInfo.plist` of a `.momd` (docs/formats/coredata.md "`VersionInfo.plist`"), written by
/// Core Foundation from momc's objects, so its sharing follows which strings are one object.
enum VersionInfo {
    struct Version {
        let name: String
        let checksum: String
        let entityHashes: [String: [UInt8]]
        /// The order of the version's dictionary of entity hashes.
        let entityOrder: [String]
    }

    /// `versions` in the order momc compiled them.
    static func data(_ versions: [Version], current: String?) throws -> [UInt8] {
        typealias Node = CFPropertyListWriter.Node
        let checksumOrder = try FoundationHashTable.inserting(versions.map(\.name)).keys
        let byName = Dictionary(versions.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let checksums = Node.dictionary(checksumOrder.map { (versionName($0), .string(byName[$0]!.checksum, shared: nil)) })
        let hashes = Node.dictionary(checksumOrder.map { name in
            let version = byName[name]!
            return (versionName(name), .dictionary(version.entityOrder.map { entity in
                (.string(entity, shared: TaggedPointerString.fits(entity) ? "tagged" : nil), .data(version.entityHashes[entity]!))
            }))
        })
        var entries: [(Node, Node)] = [
            (.constant("NSManagedObjectModel_VersionHashes"), hashes),
            (.constant("NSManagedObjectModel_VersionChecksums"), checksums),
        ]
        if let current {
            entries = [
                (.constant("NSManagedObjectModel_VersionChecksums"), checksums),
                (.constant("NSManagedObjectModel_VersionHashes"), hashes),
                (.constant("NSManagedObjectModel_CurrentVersionName"), .string(current, shared: nil)),
            ]
        }
        return CFPropertyListWriter.data(.dictionary(entries))
    }

    /// A version's name is one object in both dictionaries when it is a tagged pointer of at least
    /// six characters (coredata-experiments `version-strings`: names of 1 to 5 characters are two).
    private static func versionName(_ name: String) -> CFPropertyListWriter.Node {
        .string(name, shared: name.count >= 6 && TaggedPointerString.fits(name) ? "tagged" : nil)
    }
}
