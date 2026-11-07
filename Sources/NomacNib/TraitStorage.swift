import Foundation
import NomacCore

/// A size class pair of a `<variation key>` (docs/formats/nib.md "Variations"): 1 compact, 2 regular.
struct SizeClasses: Equatable {
    var horizontal: Int?
    var vertical: Int?

    /// The keys IB writes, in the order ibtool writes a property's records, whatever the
    /// document's order (nib-experiments `vo-font-all`, `vo-font-all-reversed`); the default
    /// record, of no size class, comes last.
    static let keys: [(String, SizeClasses)] = [
        ("heightClass=regular-widthClass=regular", SizeClasses(horizontal: 2, vertical: 2)),
        ("heightClass=regular-widthClass=compact", SizeClasses(horizontal: 1, vertical: 2)),
        ("heightClass=compact-widthClass=regular", SizeClasses(horizontal: 2, vertical: 1)),
        ("heightClass=compact-widthClass=compact", SizeClasses(horizontal: 1, vertical: 1)),
        ("widthClass=regular", SizeClasses(horizontal: 2)),
        ("widthClass=compact", SizeClasses(horizontal: 1)),
        ("heightClass=regular", SizeClasses(vertical: 2)),
        ("heightClass=compact", SizeClasses(vertical: 1)),
    ]

    var order: Int { Self.keys.firstIndex { $0.1 == self }! }
    /// A mask's records: the default first, then the size classes in the reverse of `keys`
    /// (nib-experiments `sc-mask-order-all`, `sc-mask-order-all-reversed`).
    var recordOrder: Int { self == SizeClasses() ? -Self.keys.count : -order }

    /// Whether a device of `device`'s size classes takes this variation.
    func applies(to device: SizeClasses) -> Bool {
        (horizontal == nil || horizontal == device.horizontal) && (vertical == nil || vertical == device.vertical)
    }

    /// The size classes of a storyboard's `<device>`: iPads regular both ways, iPhones compact by
    /// regular in portrait and compact-height in landscape, regular-width on the larger ones
    /// (nib-experiments `sb-vo-all-*`).
    static func device(_ id: String, landscape: Bool) -> SizeClasses {
        if id.lowercased().hasPrefix("ipad") { return SizeClasses(horizontal: 2, vertical: 2) }
        guard landscape else { return SizeClasses(horizontal: 1, vertical: 2) }
        let regularWidth: Set = ["retina5_5", "retina6_1", "retina6_3", "retina6_5", "retina6_7", "retina6_9"]
        return SizeClasses(horizontal: regularWidth.contains(id) ? 2 : 1, vertical: 1)
    }
}

/// One property of one object that varies by size class: the varied values by size class, and its
/// value without one.
struct TraitStorage {
    enum Value {
        case object(NibArchivable)
        case constant(Double)
    }

    let object: NibArchivable
    let keyPath: NibString
    let variations: [(SizeClasses, Value)]
    let defaultValue: Value

    var isConstraint: Bool { object is NibLayoutConstraint }

    /// The value an object takes on a device of `device`'s size classes: the first variation, in
    /// record order, that applies to it, or the default (`sb-vo-all-*`, `sb-vo-partial-*`); a xib
    /// or a storyboard without a device takes the default (`variation-font`, `sb-vo-all-no-device`).
    static func value<Value>(_ variations: [(SizeClasses, Value)], default value: Value, device: SizeClasses?) -> Value {
        guard let device else { return value }
        return variations.sorted { $0.0.order < $1.0.order }.first { $0.0.applies(to: device) }?.1 ?? value
    }
}

/// `_UITraitStorageList`, a top-level object's varied properties, in the order of
/// `XIBCompiler.traitStorageLists`'s walk; `UIDescendants` the varied objects, and a mask's
/// candidates' items but the top-level object, in that order (`vo-two-constants*`,
/// `vo-two-labels*`, `masks-*`). The empty trait collection of the default records is one object;
/// every other trait collection and constant is a new object (`variation-constant`).
final class NibTraitStorageList: NibArchivable {
    enum Entry {
        case attribute(TraitStorage)
        case relationship(NibRelationshipTraitStorage)
    }

    let topLevelObject: NibArchivable
    let entries: [Entry]
    private let noSizeClass = NibTraitCollection(SizeClasses())

    init(topLevelObject: NibArchivable, entries: [Entry]) {
        self.topLevelObject = topLevelObject
        self.entries = entries
        for case .relationship(let relationship) in entries {
            relationship.noSizeClass = noSizeClass
        }
    }

    var className: String { "_UITraitStorageList" }

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(topLevelObject, forKey: "UITopLevelObject")
        var storages: [NibArchivable] = []
        var descendants: [NibArchivable] = []
        for entry in entries {
            let varied: [NibArchivable]
            switch entry {
            case .attribute(let storage):
                storages.append(NibAttributeTraitStorage(storage, noSizeClass: noSizeClass))
                varied = [storage.object]
            case .relationship(let relationship):
                storages.append(relationship)
                varied = relationship.descendants.filter { $0 !== topLevelObject }
            }
            for object in varied where !descendants.contains(where: { $0 === object }) {
                descendants.append(object)
            }
        }
        try encoder.encode(NibArray(storages), forKey: "UITraitStorages")
        try encoder.encode(NibSet(descendants), forKey: "UIDescendants")
    }
}

/// `_UIRelationshipTraitStorage` of a view's `<mask>`s (`mask-*`, `sc-mask-*`): its view, the key
/// path `traitStorageConstraints` or `traitStorageSubviews`, a record per variation, and the view's
/// constraints or subviews as candidates. A list of mask storages has as `UIDescendants` the
/// constraints' items, or the view, but the top-level object, in their order (`mask-subviews-*`).
final class NibRelationshipTraitStorage: NibArchivable {
    /// A variation's objects added and removed, in the candidates' order (`mask-group-tofu`,
    /// `sc-mask-removed-*`).
    struct Record {
        var sizeClasses: SizeClasses
        var added: [NibArchivable]
        var removed: [NibArchivable]

        func ordered(as candidates: [NibArchivable]) -> Record {
            func ordered(_ objects: [NibArchivable]) -> [NibArchivable] {
                candidates.filter { candidate in objects.contains { $0 === candidate } }
            }
            return Record(sizeClasses: sizeClasses, added: ordered(added), removed: ordered(removed))
        }
    }

    let owner: NibView
    let keyPath: NibString
    let candidates: [NibArchivable]
    let records: [Record]
    let descendants: [NibArchivable]
    /// Whether it is a `<mask key="subviews">`, which a view writes before its constraints'.
    var subviews: Bool { keyPath.value == "traitStorageSubviews" }
    /// The list's empty trait collection, which every default record shares.
    var noSizeClass = NibTraitCollection(SizeClasses())

    init(owner: NibView, keyPath: NibString, candidates: [NibArchivable], records: [Record], descendants: [NibArchivable]) {
        self.owner = owner
        self.keyPath = keyPath
        self.candidates = candidates
        self.records = records
        self.descendants = descendants
    }

    func copy() -> NibRelationshipTraitStorage {
        NibRelationshipTraitStorage(owner: owner, keyPath: keyPath, candidates: candidates, records: records, descendants: descendants)
    }

    var className: String { "_UIRelationshipTraitStorage" }

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(owner, forKey: "UIObject")
        try encoder.encode(keyPath, forKey: "UIKeyPath")
        let records = records.map { record in
            NibRelationshipTraitStorageRecord(traits: record.sizeClasses == SizeClasses() ? noSizeClass : NibTraitCollection(record.sizeClasses),
                                              added: record.added, removed: record.removed)
        }
        try encoder.encode(NibArray(records, mutable: true), forKey: "UIRecords")
        try encoder.encode(NibSet(candidates, ordered: true), forKey: "UIRelationshipCandidates")
    }
}

final class NibRelationshipTraitStorageRecord: NibArchivable {
    let traits: NibTraitCollection
    let added: [NibArchivable]
    let removed: [NibArchivable]

    init(traits: NibTraitCollection, added: [NibArchivable], removed: [NibArchivable]) {
        self.traits = traits
        self.added = added
        self.removed = removed
    }

    var className: String { "_UIRelationshipTraitStorageRecord" }

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(traits, forKey: "UITraitCollection")
        try encoder.encode(NibSet(added), forKey: "UIAddedObjects")
        try encoder.encode(NibSet(removed), forKey: "UIRemovedObjects")
    }
}

/// `_UIAttributeTraitStorage`: the object, the property's key path and its records.
final class NibAttributeTraitStorage: NibArchivable {
    let storage: TraitStorage
    let noSizeClass: NibTraitCollection

    init(_ storage: TraitStorage, noSizeClass: NibTraitCollection) {
        self.storage = storage
        self.noSizeClass = noSizeClass
    }

    var className: String { "_UIAttributeTraitStorage" }

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(storage.object, forKey: "UIObject")
        try encoder.encode(storage.keyPath, forKey: "UIKeyPath")
        let records = storage.variations.sorted { $0.0.order < $1.0.order }.map { NibTraitStorageRecord(NibTraitCollection($0.0), $0.1) }
            + [NibTraitStorageRecord(noSizeClass, storage.defaultValue)]
        try encoder.encode(NibArray(records, mutable: true), forKey: "UIRecords")
    }
}

/// `_UIAttributeTraitStorageRecord`: a trait collection and the value for it.
final class NibTraitStorageRecord: NibArchivable {
    let traits: NibTraitCollection
    let value: NibArchivable

    init(_ traits: NibTraitCollection, _ value: TraitStorage.Value) {
        self.traits = traits
        switch value {
        case .object(let object): self.value = object
        case .constant(let constant): self.value = NibConstraintConstant(constant)
        }
    }

    var className: String { "_UIAttributeTraitStorageRecord" }

    func encode(to encoder: NibEncoder) throws {
        try encoder.encode(traits, forKey: "UITraitCollection")
        try encoder.encode(value, forKey: "UIValue")
    }
}

/// `UITraitCollection` of the size classes a record has.
final class NibTraitCollection: NibArchivable {
    let sizeClasses: SizeClasses

    init(_ sizeClasses: SizeClasses) {
        self.sizeClasses = sizeClasses
    }

    var className: String { "UITraitCollection" }

    func encode(to encoder: NibEncoder) throws {
        if let horizontal = sizeClasses.horizontal {
            encoder.encode(.integer(horizontal), forKey: "UITraitCollectionBuiltinTrait-_UITraitNameHorizontalSizeClass")
        }
        if let vertical = sizeClasses.vertical {
            encoder.encode(.integer(vertical), forKey: "UITraitCollectionBuiltinTrait-_UITraitNameVerticalSizeClass")
        }
    }
}

/// `_NSLayoutConstraintConstant`: a constraint's varied constant.
final class NibConstraintConstant: NibArchivable {
    let constant: Double

    init(_ constant: Double) {
        self.constant = constant
    }

    var className: String { "_NSLayoutConstraintConstant" }

    func encode(to encoder: NibEncoder) throws {
        encoder.encode(.null, forKey: "UISymbolicConstant")
        encoder.encode(.double(constant), forKey: "UINumericConstant")
    }
}

/// `NSSet`, or `NSOrderedSet`: `NS.object.<n>` per element.
final class NibSet: NibArchivable {
    let elements: [NibArchivable]
    let ordered: Bool

    init(_ elements: [NibArchivable], ordered: Bool = false) {
        self.elements = elements
        self.ordered = ordered
    }

    var className: String { ordered ? "NSOrderedSet" : "NSSet" }

    func encode(to encoder: NibEncoder) throws {
        for (index, element) in elements.enumerated() {
            try encoder.encode(element, forKey: "NS.object.\(index)")
        }
    }
}
