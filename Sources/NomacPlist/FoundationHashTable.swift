import NomacCore

/// The iteration order of Foundation's hash tables of strings on a Mac, as Xcode's archives show
/// it (docs/formats/foundation-collections.md): `NSString` hashes, linear probing, and tables
/// that grow when full.
public struct FoundationHashTable: Sendable {
    /// Bucket counts, and how many counted keys a mutable table of each count holds before it
    /// grows: Core Foundation's capacity plus one, the bucket count itself at 3 and 7. Pinned by
    /// threshold experiments up to 251 buckets (`threshold-*` for `.mom` dictionaries,
    /// nib-experiments `ladder-*` for nib key tables). 383 buckets are observed holding up to 199
    /// keys (the corpus's nibs, tofu's of 180 keys identical), what they hold past that is BACKLOG
    /// B-259.
    static let bucketCounts = [3, 7, 13, 23, 41, 71, 127, 191, 251, 383]
    static let held = [3, 7, 12, 20, 33, 53, 86, 119, 156, 199]
    /// The capacities a copy is sized by; 53 keys are copied into 127 buckets (`threshold-71-53`),
    /// 86 and up into 191 (the survey's entities of more than 85 properties, coredata_survey.py).
    public static let copyCapacities = [3, 6, 11, 19, 32, 52, 85, 118, 155, 198]

    private var buckets: [String?] = []
    private var count = 0
    private var uncounted: Set<String> = []

    public init() {}

    /// The keys in iteration order.
    public var keys: [String] { buckets.compactMap { $0 } }

    /// Inserts `key` if it is not in the table yet. The table first grows if it would hold more
    /// counted keys than it may, or more keys than it has buckets, re-inserting every key in
    /// iteration order. A key inserted uncounted takes a bucket but does not count toward what
    /// the table holds until `count(_:)` (a nib's `UINibEncoderEmptyKey`: docs/formats/nib.md
    /// "Encoding").
    public mutating func insert(_ key: String, counted: Bool = true) throws {
        if buckets.contains(key) { return }
        let counting = count + (counted ? 1 : 0)
        if buckets.isEmpty || counting > held(buckets.count) || keys.count + 1 > buckets.count {
            try grow(holding: counting, occupying: keys.count + 1)
        }
        place(key)
        if counted {
            count += 1
        } else {
            uncounted.insert(key)
        }
    }

    /// Counts `key`, inserted uncounted, growing the table first if it would then hold more
    /// counted keys than it may; inserts it if it is not in the table.
    public mutating func count(_ key: String) throws {
        guard uncounted.remove(key) != nil else { return try insert(key) }
        if count + 1 > held(buckets.count) {
            try grow(holding: count + 1, occupying: keys.count)
        }
        count += 1
    }

    /// An immutable table created with `keys`: the bucket count whose copy capacity fits them,
    /// the keys inserted in order (an `NSDictionary` read from a property list:
    /// signing-experiments `nested`, an app-store-connect export's Info.plist).
    public static func created(with keys: [String]) throws -> FoundationHashTable {
        guard let size = zip(bucketCounts, copyCapacities).first(where: { $0.1 >= keys.count })?.0 else {
            throw NomacError("more than \(copyCapacities.last!) keys in one copied table (BACKLOG B-259)")
        }
        var table = FoundationHashTable()
        table.buckets = Array(repeating: nil, count: size)
        for key in keys where !table.buckets.contains(key) {
            table.place(key)
            table.count += 1
        }
        return table
    }

    /// An immutable copy of the table: created with its keys in iteration order, unless the copy
    /// takes the same bucket count, which keeps the layout.
    public func copied() throws -> FoundationHashTable {
        guard !buckets.isEmpty else { return self }
        let copy = try Self.created(with: keys)
        return copy.buckets.count == buckets.count ? self : copy
    }

    /// A mutable table built by inserting `keys` in order.
    public static func inserting(_ keys: [String]) throws -> FoundationHashTable {
        var table = FoundationHashTable()
        for key in keys {
            try table.insert(key)
        }
        return table
    }

    private func held(_ bucketCount: Int) -> Int {
        Self.held[Self.bucketCounts.firstIndex(of: bucketCount)!]
    }

    /// Moves to the smallest larger bucket count that holds `counted` keys and has `occupied`
    /// buckets.
    private mutating func grow(holding counted: Int, occupying occupied: Int) throws {
        guard let size = zip(Self.bucketCounts, Self.held).first(where: { $0.0 > buckets.count && $0.1 >= counted && $0.0 >= occupied })?.0 else {
            throw NomacError("more than \(Self.held.last!) keys in one table; larger Foundation tables are not observed yet (BACKLOG B-259)")
        }
        let old = keys
        buckets = Array(repeating: nil, count: size)
        for key in old {
            place(key)
        }
    }

    private mutating func place(_ key: String) {
        var index = Int(FoundationStringHash.hash(key) % UInt64(buckets.count))
        while buckets[index] != nil {
            index = (index + 1) % buckets.count
        }
        buckets[index] = key
    }
}
