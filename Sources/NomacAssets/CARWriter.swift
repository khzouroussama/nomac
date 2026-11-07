import Foundation
import NomacCore

/// One rendition of a compiled catalog: a facet name, the key attributes that select it, and
/// its CSI bytes. Atlases of packed images have no facet and identifier 0.
public struct CARRendition: Sendable {
    public var name: String
    public var kind: FacetKind
    /// Key attributes other than the identifier, element and part, which come from the facet.
    public var attributes: [RenditionAttribute: UInt16]
    public var csi: [UInt8]
    public var hasFacet: Bool

    public init(name: String, kind: FacetKind, attributes: [RenditionAttribute: UInt16], csi: [UInt8], hasFacet: Bool = true) {
        self.name = name
        self.kind = kind
        self.attributes = attributes
        self.csi = csi
        self.hasFacet = hasFacet
    }
}

/// Writes `Assets.car` from renditions, block for block as actool lays it out
/// (docs/formats/asset-catalog.md).
public struct CARWriter {
    /// `EXTENDED_METADATA`'s platform (`ios`) and version (the minimum deployment target).
    public var deploymentPlatform: String
    public var deploymentPlatformVersion: String

    public init(deploymentPlatform: String, deploymentPlatformVersion: String) {
        self.deploymentPlatform = deploymentPlatform
        self.deploymentPlatformVersion = deploymentPlatformVersion
    }

    public func write(_ renditions: [CARRendition]) throws -> [UInt8] {
        let names = Array(Set(renditions.filter(\.hasFacet).map(\.name)))
        let identifiers = RenditionIdentifier.assign(names)
        var kinds: [String: FacetKind] = [:]
        for rendition in renditions where rendition.hasFacet {
            if let kind = kinds[rendition.name], kind != rendition.kind {
                throw NomacError("assets of different types named '\(rendition.name)' are not supported yet (BACKLOG B-208)")
            }
            kinds[rendition.name] = rendition.kind
        }
        let used = Set(renditions.flatMap { $0.attributes.filter { $0.value != 0 }.keys })
        let keyFormat = RenditionAttribute.keyFormatOrder.filter { RenditionAttribute.alwaysPresent.contains($0) || used.contains($0) }

        var store = BOMStoreWriter()
        let header = store.reserve()
        var renditionTree = BOMKeyTree(in: &store, blockSize: 4096)
        var facetTree = BOMKeyTree(in: &store, blockSize: 4096)
        // Appearance keys list the appearances of renditions other than data and stickers icons;
        // a catalog of those only has no such table (`stickers`, firefox, wikipedia). actool creates them in an order that changes from one run to
        // the next (docs/formats/asset-catalog.md, "Determinism"); nomac creates them in name order.
        let appearances = Set(renditions.filter { $0.kind != .data && $0.kind != .stickersIcon }.map { RenditionAppearance(rawValue: $0.attributes[.appearance] ?? 0) ?? .any })
        var appearanceTree = appearances.isEmpty ? nil : BOMKeyTree(in: &store, blockSize: 4096)
        for appearance in appearances.sorted(by: { $0.name.utf8.lexicographicallyPrecedes($1.name.utf8) }) {
            let key = Array(appearance.name.utf8)
            let keyBlock = store.add(key)
            var value = ByteWriter()
            value.appendLE(appearance.rawValue)
            try appearanceTree?.insert(key: BOMBlockKey(bytes: key, block: keyBlock), value: store.add(value.bytes), in: &store)
        }

        // Facet names are stored decomposed (NFD); the identifier and the CSI keep the name as
        // the file system spells it.
        let facetKeys = Dictionary(uniqueKeysWithValues: names.map { ($0, Array($0.decomposedStringWithCanonicalMapping.utf8)) })
        for name in names.sorted(by: { facetKeys[$0]!.lexicographicallyPrecedes(facetKeys[$1]!) }) {
            let key = facetKeys[name]!
            let keyBlock = store.add(key)
            let kind = kinds[name]!
            var attributes: [(UInt16, UInt16)] = [(RenditionAttribute.element.rawValue, kind.element)]
            if kind.part != 0 {
                attributes.append((RenditionAttribute.part.rawValue, kind.part))
            }
            if let identifier = identifiers[name], identifier != 0 {
                attributes.append((RenditionAttribute.identifier.rawValue, identifier))
            }
            if kind.target != 0 {
                attributes.append((RenditionAttribute.target.rawValue, kind.target))
            }
            var token = ByteWriter()
            token.appendLE(UInt16(0))
            token.appendLE(UInt16(0))
            token.appendLE(UInt16(attributes.count))
            for (attribute, value) in attributes {
                token.appendLE(attribute)
                token.appendLE(value)
            }
            try facetTree.insert(key: BOMBlockKey(bytes: key, block: keyBlock), value: store.add(token.bytes), in: &store)
        }

        var format = ByteWriter()
        format.append(Array("tmfk".utf8))
        format.appendLE(UInt32(0))
        format.appendLE(UInt32(keyFormat.count))
        for attribute in keyFormat { format.appendLE(UInt32(attribute.rawValue)) }
        let keyFormatBlock = store.add(format.bytes)

        struct Keyed {
            var values: [UInt16]
            var rendition: CARRendition
            var identifier: UInt16
        }
        let keyed = renditions.map { rendition -> Keyed in
            let identifier = rendition.hasFacet ? identifiers[rendition.name] ?? 0 : 0
            let values = keyFormat.map { attribute -> UInt16 in
                switch attribute {
                case .identifier: identifier
                case .element: rendition.kind.element
                case .part: rendition.attributes[.part] ?? rendition.kind.part
                default: rendition.attributes[attribute] ?? 0
                }
            }
            return Keyed(values: values, rendition: rendition, identifier: identifier)
        }.sorted { $0.values.lexicographicallyPrecedes($1.values) }

        var creationOrder: [Keyed] = []
        Self.midpointPreorder(keyed.count) { creationOrder.append(keyed[$0]) }
        for item in creationOrder {
            var key = ByteWriter()
            for value in item.values { key.appendLE(value) }
            let keyBlock = store.add(key.bytes)
            try renditionTree.insert(key: BOMBlockKey(bytes: key.bytes, block: keyBlock), value: store.add(item.rendition.csi), in: &store)
        }

        var metadata = ByteWriter()
        metadata.append(Array("META".utf8))
        metadata.appendFixed("", width: 256)
        metadata.appendFixed(deploymentPlatformVersion, width: 256)
        metadata.appendFixed(deploymentPlatform, width: 256)
        metadata.appendFixed(deploymentPlatform == "watch" ? ActoolVersions.watchOSAuthoringTool : ActoolVersions.authoringTool, width: 256)
        let metadataBlock = store.add(metadata.bytes)
        // A key format with the variant attribute before iOS 9.3 comes with a word per attribute,
        // 25 for that one, the attribute it stands for (`old-targets`).
        let keyFormatWorkaround = keyFormat.contains(.legacyTarget) ? store.add(keyFormat.flatMap { $0 == .legacyTarget ? [25, 0, 0, 0] : [UInt8](repeating: 0, count: 4) }) : nil

        let bitmapTree = try Self.addBitmapKeys(keyFormat: keyFormat, renditions: creationOrder.map { ($0.identifier, $0.values) }, to: &store)

        var carHeader = ByteWriter()
        carHeader.append(Array("RATC".utf8))
        carHeader.appendLE(ActoolVersions.coreUIVersion)
        carHeader.appendLE(UInt32(17))
        carHeader.appendLE(UInt32(0))
        carHeader.appendLE(UInt32(renditions.count))
        carHeader.appendFixed(ActoolVersions.coreUIVersionString, width: 128)
        carHeader.appendFixed(ActoolVersions.carVersionString, width: 256)
        carHeader.appendZeros(16)
        carHeader.appendLE(UInt32(0))
        carHeader.appendLE(UInt32(2))
        carHeader.appendLE(UInt32(1))
        carHeader.appendLE(UInt32(2))
        store.set(header, carHeader.bytes)

        renditionTree.finish(in: &store)
        facetTree.finish(in: &store)
        appearanceTree?.finish(in: &store)
        bitmapTree.finish(in: &store)

        store.addVariable("CARHEADER", block: header)
        store.addVariable("RENDITIONS", block: renditionTree.headerBlock)
        store.addVariable("FACETKEYS", block: facetTree.headerBlock)
        if let appearanceTree { store.addVariable("APPEARANCEKEYS", block: appearanceTree.headerBlock) }
        store.addVariable("KEYFORMAT", block: keyFormatBlock)
        store.addVariable("EXTENDED_METADATA", block: metadataBlock)
        if let keyFormatWorkaround { store.addVariable("KEYFORMATWORKAROUND", block: keyFormatWorkaround) }
        store.addVariable("BITMAPKEYS", block: bitmapTree.headerBlock)
        return store.serialized()
    }

    /// `BITMAPKEYS`: for each identifier but 0, a mask of the values its renditions' keys
    /// (`renditions`, in the order they are created) use, attribute by attribute, created in the
    /// slot order of `BitmapKeyTable`.
    static func addBitmapKeys(keyFormat: [RenditionAttribute], renditions: [(identifier: UInt16, values: [UInt16])],
                              to store: inout BOMStoreWriter) throws -> BOMNumberTree {
        var tree = BOMNumberTree(in: &store, blockSize: 1024)
        var masks: [UInt16: [RenditionAttribute: UInt32]] = [:]
        var order = BitmapKeyTable()
        for item in renditions where item.identifier != 0 {
            if masks[item.identifier] == nil {
                guard order.count < BitmapKeyTable.mostIdentifiers else {
                    throw NomacError("asset catalogs of more than \(BitmapKeyTable.mostIdentifiers) names are not supported yet (BACKLOG B-201)")
                }
                order.insert(item.identifier)
            }
            for (attribute, value) in zip(keyFormat, item.values) where !RenditionAttribute.unmasked.contains(attribute) {
                masks[item.identifier, default: [:]][attribute, default: 0] |= 1 << attribute.maskBit(value)
            }
        }
        for identifier in order.slotOrder {
            var value = ByteWriter()
            value.appendLE(UInt32(1))
            value.appendLE(UInt32(0))
            value.appendLE(UInt32(4 + 4 * keyFormat.count))
            value.appendLE(UInt32(keyFormat.count))
            for attribute in keyFormat {
                value.appendLE(RenditionAttribute.unmasked.contains(attribute) ? 0xFFFF_FFFF : masks[identifier]?[attribute] ?? 0)
            }
            try tree.insert(key: UInt32(identifier), value: store.add(value.bytes), in: &store)
        }
        return tree
    }

    /// Visits `0..<count` in the order actool creates renditions: the middle element of the
    /// sorted range first, then the lower half, then the upper half, recursively.
    static func midpointPreorder(_ count: Int, _ visit: (Int) -> Void) {
        func visitRange(_ lower: Int, _ upper: Int) {
            guard lower < upper else { return }
            let middle = (lower + upper) / 2
            visit(middle)
            visitRange(lower, middle)
            visitRange(middle + 1, upper)
        }
        visitRange(0, count)
    }
}

/// The order actool creates `BITMAPKEYS` values in: the slot order of an open-addressing hash
/// table of identifiers (docs/formats/asset-catalog.md, "Bitmap keys"), observed on 43
/// catalogs of 1 to 126 names and on `large-tables`.
struct BitmapKeyTable {
    private static let sizes = [3, 7, 13, 23, 41, 71, 127, 191, 251, 383, 631, 1087, 1723, 2803, 4523, 7351, 11959, 19447, 31231, 50683]
    private static let capacities = [3, 6, 11, 19, 32, 52, 85, 118, 155, 237, 390, 672, 1065, 1732, 2795, 4543, 7391, 12019, 19302, 31324]
    /// The most identifiers the observed sizes hold (`large-tables`, up to 24,000 names).
    static let mostIdentifiers = capacities.last!

    private var level = 0
    private(set) var slots: [UInt16?] = Array(repeating: nil, count: sizes[0])
    private(set) var count = 0

    mutating func insert(_ identifier: UInt16) {
        if count == slots.count { grow() }
        Self.place(identifier, in: &slots)
        count += 1
        if count > Self.capacities[level] { grow() }
    }

    var slotOrder: [UInt16] { slots.compactMap { $0 } }

    private mutating func grow() {
        level += 1
        var bigger = [UInt16?](repeating: nil, count: Self.sizes[level])
        for identifier in slots.compactMap({ $0 }) { Self.place(identifier, in: &bigger) }
        slots = bigger
    }

    private static func place(_ identifier: UInt16, in slots: inout [UInt16?]) {
        var slot = Int(UInt64(identifier) &* 2_654_435_761 % UInt64(slots.count))
        while slots[slot] != nil { slot = (slot + 1) % slots.count }
        slots[slot] = identifier
    }
}
