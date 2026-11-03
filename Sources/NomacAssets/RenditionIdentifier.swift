/// The 16-bit identifiers actool gives asset names (docs/formats/asset-catalog.md,
/// "Name identifiers"). Found by experiment on single-name catalogs: the identifier of a name
/// depends only on its UTF-16 code units, and names whose identifiers collide are resolved in
/// name order.
public enum RenditionIdentifier {
    /// A ×33 hash of the name's UTF-16 code units in 64 bits, from the seed 100823.
    static func nameHash(_ name: String) -> UInt64 {
        var hash: UInt64 = 100_823
        for unit in name.utf16 {
            hash = hash &* 33 &+ UInt64(unit)
        }
        return hash
    }

    /// The identifier a name gets when no other name has it: the same ×33 hash over the four
    /// 16-bit words of ``nameHash(_:)``, lowest word first, in 16 bits.
    public static func primary(_ name: String) -> UInt16 {
        fold(nameHash(name))
    }

    static func fold(_ hash: UInt64) -> UInt16 {
        var result: UInt16 = 0
        for shift in stride(from: 0, to: 64, by: 16) {
            result = result &* 33 &+ UInt16(truncatingIfNeeded: hash >> UInt64(shift))
        }
        return result
    }

    /// Identifiers for all names of a catalog. Names are taken in UTF-16 order; a name whose
    /// primary identifier is taken gets the exclusive-or of its hash's four words plus one, or
    /// the next free value after that.
    public static func assign(_ names: [String]) -> [String: UInt16] {
        var taken: Set<UInt16> = []
        var result: [String: UInt16] = [:]
        for name in names.sorted(by: { $0.utf16.lexicographicallyPrecedes($1.utf16) }) {
            let hash = nameHash(name)
            var identifier = fold(hash)
            if taken.contains(identifier) {
                identifier = UInt16(truncatingIfNeeded: hash ^ hash >> 16 ^ hash >> 32 ^ hash >> 48)
                repeat {
                    identifier &+= 1
                } while taken.contains(identifier)
            }
            taken.insert(identifier)
            result[name] = identifier
        }
        return result
    }
}
