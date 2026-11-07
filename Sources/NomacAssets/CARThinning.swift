import Foundation
import NomacCore

/// A device's traits as `assetutil` takes them to thin a catalog (`-i`, `-s`, `-t`, `-u`, `-p`,
/// `-h`, `-g`, `-k`, `-M`, `-r`), in the spellings of Xcode's `device_traits.db`.
public struct ThinningTraits: Sendable, Hashable {
    public var idiom: String
    public var scale: Int
    public var subtype: Int?
    public var subtypeFallbacks: String?
    public var displayGamut: String?
    public var hostedIdioms: [String]
    public var graphicsClass: String
    public var graphicsFallbacks: [String]
    public var memory: Int
    public var deploymentTarget: String

    public init(idiom: String, scale: Int, subtype: Int?, subtypeFallbacks: String?, displayGamut: String?, hostedIdioms: [String],
                graphicsClass: String, graphicsFallbacks: [String], memory: Int, deploymentTarget: String) {
        self.idiom = idiom
        self.scale = scale
        self.subtype = subtype
        self.subtypeFallbacks = subtypeFallbacks
        self.displayGamut = displayGamut
        self.hostedIdioms = hostedIdioms
        self.graphicsClass = graphicsClass
        self.graphicsFallbacks = graphicsFallbacks
        self.memory = memory
        self.deploymentTarget = deploymentTarget
    }
}

/// `assetutil`'s thinning of an `Assets.car` for one device (docs/formats/asset-catalog.md,
/// "Thinning"; `distribution_experiments.py` `car-thinning`, every trait set of the iOS 18.0
/// descriptors on catalogs of images, colors and an app icon): the store is edited in place.
/// Renditions the device would not pick are removed, with their key and CSI blocks, and so is a
/// facet left without renditions; the rendition and facet leaves are written again in their
/// blocks, `BITMAPKEYS` again in new blocks, `CARHEADER` gets the new rendition count and
/// `EXTENDED_METADATA` the thinning parameters.
public enum CARThinning {
    static let idioms = ["universal": 0, "phone": 1, "pad": 2, "car": 4, "watch": 5]
    /// The numbers the thinning parameters give graphics feature set classes and deployment
    /// targets (`car-thinning`'s parameters for the classes; the deployment targets as
    /// `device_traits.db`'s `DeploymentTarget` table numbers them, 18.0 observed as 11).
    static let graphicsClasses = ["GLES2,0", "APPLE1", "APPLE2", "APPLE3v1", "APPLE3", "APPLE4", "APPLE5", "APPLE6", "APPLE7", "APPLE8",
                                  "APPLE9", "APPLE10", "APPLE11"]
    /// By the catalog's platform (`EXTENDED_METADATA`), as each platform's database numbers them
    /// (a watch app's catalog thinned for watchOS 11.0 and 26.0 gives 11 and 12, `thinning`
    /// `watch-catalog`).
    static let deploymentTargets = [
        "ios": ["9.0", "10.0", "11.0", "12.0", "12.2", "13.0", "14.0", "15.0", "16.0", "17.0", "17.4", "18.0", "26.0", "27.0"],
        "watchos": ["2.0", "3.0", "4.0", "5.0", "5.2", "6.0", "7.0", "8.0", "9.0", "10.0", "10.4", "11.0", "26.0", "27.0"],
    ]
    /// Attributes whose values do not depend on the device: every rendition of a facet keeps
    /// them apart (appearances, app icon sizes in `dimension2`, atlas numbers in `dimension1`).
    static let independent: Set<RenditionAttribute> = [.appearance, .localization, .identifier, .element, .part, .dimension1, .dimension2]

    public static func thin(_ bytes: [UInt8], for traits: ThinningTraits, path: String) throws -> [UInt8] {
        guard let deviceIdiom = idioms[traits.idiom], deviceIdiom != 0 else {
            throw NomacError("thinning for idiom '\(traits.idiom)' is not supported yet (BACKLOG B-465)", path: path)
        }
        let hosted = try traits.hostedIdioms.map { name -> Int in
            guard let idiom = idioms[name], idiom == 4 else {
                throw NomacError("thinning for hosted idiom '\(name)' is not supported yet (BACKLOG B-465)", path: path)
            }
            return idiom
        }
        guard let graphics = graphicsClasses.firstIndex(of: traits.graphicsClass) else {
            throw NomacError("thinning for graphics class '\(traits.graphicsClass)' is not supported yet (BACKLOG B-465)", path: path)
        }
        let fallbacks = try traits.graphicsFallbacks.map { name -> Int in
            guard let number = graphicsClasses.firstIndex(of: name) else {
                throw NomacError("thinning for graphics class '\(name)' is not supported yet (BACKLOG B-465)", path: path)
            }
            return number
        }
        guard traits.subtypeFallbacks == nil, [nil, "P3", "sRGB"].contains(traits.displayGamut) else {
            throw NomacError("thinning with subtype fallbacks or display gamut '\(traits.displayGamut ?? "")' is not supported yet (BACKLOG B-465)", path: path)
        }

        let catalog = try Catalog(bytes: bytes, path: path)
        let kept = try catalog.kept(idiom: deviceIdiom, scale: traits.scale, path: path)
        var store = catalog.store
        let keyFormat = catalog.keyFormat, renditions = catalog.renditions
        let renditionTree = catalog.renditionTree, facetTree = catalog.facetTree
        func variable(_ name: String) throws -> UInt32 {
            guard let block = store.variable(name) else { throw NomacError("the catalog has no \(name)", path: path) }
            return block
        }
        let removed = renditions.indices.filter { !kept.contains($0) }
        for index in removed {
            store.free(renditions[index].keyBlock)
            store.free(renditions[index].value)
        }
        let remaining = renditions.indices.filter { kept.contains($0) }.map { renditions[$0] }
        renditionTree.finish(in: &store, entries: remaining.map { .init(key: $0.key, value: $0.value, keyBlock: $0.keyBlock) })

        let identifiers = Set(remaining.compactMap { $0.values[.identifier] })
        var facets: [BOMTree.Entry] = []
        for pair in facetTree.pairs(in: store) {
            guard let token = store.block(pair.value), let name = store.block(pair.keyBlock) else { throw NomacError("malformed facet", path: path) }
            if Self.identifier(ofFacetToken: token).map(identifiers.contains) ?? true {
                facets.append(.init(key: name, value: pair.value, keyBlock: pair.keyBlock))
            } else {
                store.free(pair.keyBlock)
                store.free(pair.value)
            }
        }
        facetTree.finish(in: &store, entries: facets)

        let bitmapKeys = try variable("BITMAPKEYS")
        for block in Self.numberTreeBlocks(store, header: bitmapKeys) { store.free(block) }
        let bitmapTree = try CARWriter.addBitmapKeys(keyFormat: keyFormat, renditions: remaining.map { rendition in
            (rendition.values[.identifier] ?? 0, keyFormat.map { rendition.values[$0] ?? 0 })
        }, to: &store)
        bitmapTree.finish(in: &store)
        store.setVariable("BITMAPKEYS", block: bitmapTree.headerBlock)

        let header = try variable("CARHEADER")
        guard var carHeader = store.block(header), carHeader.count >= 20 else { throw NomacError("malformed CARHEADER", path: path) }
        carHeader.replaceSubrange(16..<20, with: withUnsafeBytes(of: UInt32(remaining.count).littleEndian, Array.init))
        store.set(header, carHeader)

        let platform = try Self.platform(store.block(try variable("EXTENDED_METADATA")) ?? [], path: path)
        guard let deployment = deploymentTargets[platform]?.firstIndex(of: traits.deploymentTarget) else {
            throw NomacError("thinning a \(platform) catalog for deployment target \(traits.deploymentTarget) is not supported yet (BACKLOG B-465)", path: path)
        }
        let parameters = "carutil \(ActoolVersions.coreUIVersion).000000, thinned <mode app> <idiom \(deviceIdiom)> <subtype \(traits.subtype.map(String.init) ?? "*")> "
            + "<subtypefallback *> <scale \(traits.scale)> <gamut \(traits.displayGamut == "P3" ? 1 : 0)> <graphics \(graphics)> "
            + "<graphicsfallback (\(fallbacks.map(String.init).joined(separator: ",")))> <memory \(traits.memory)> <deployment- \(deployment)> "
            + "<hostedIdioms \(hosted.isEmpty ? "*" : "(" + hosted.map(String.init).joined(separator: ",") + ")")> <removed \(removed.count)>"
        let metadataBlock = try variable("EXTENDED_METADATA")
        guard var metadata = store.block(metadataBlock), metadata.count >= 260 else { throw NomacError("malformed EXTENDED_METADATA", path: path) }
        var field = Array(parameters.utf8.prefix(255))
        field += [UInt8](repeating: 0, count: 256 - field.count)
        metadata.replaceSubrange(4..<260, with: field)
        store.set(metadataBlock, metadata)
        return store.serialized()
    }

    /// The renditions a device keeps, by their keys: what app thinning groups devices by.
    public static func keptRenditions(_ bytes: [UInt8], for traits: ThinningTraits, path: String) throws -> Set<[UInt8]> {
        guard let deviceIdiom = idioms[traits.idiom], deviceIdiom != 0, deviceIdiom != 4 else {
            throw NomacError("thinning for idiom '\(traits.idiom)' is not supported yet (BACKLOG B-465)", path: path)
        }
        let catalog = try Catalog(bytes: bytes, path: path)
        return Set(try catalog.kept(idiom: deviceIdiom, scale: traits.scale, path: path).map { catalog.renditions[$0].key })
    }

    /// A catalog read back for thinning: its store, key format, rendition and facet trees and
    /// renditions in key order.
    struct Catalog {
        struct Rendition {
            var value: UInt32
            var keyBlock: UInt32
            var key: [UInt8]
            var values: [RenditionAttribute: UInt16]
        }

        var store: BOMStoreWriter
        let keyFormat: [RenditionAttribute]
        let renditionTree: BOMTree
        let facetTree: BOMTree
        let renditions: [Rendition]

        init(bytes: [UInt8], path: String) throws {
            let store = try BOMStoreWriter(bytes: bytes, path: path)
            func variable(_ name: String) throws -> UInt32 {
                guard let block = store.variable(name) else { throw NomacError("the catalog has no \(name)", path: path) }
                return block
            }
            let keyFormat = try CARThinning.keyFormat(store.block(try variable("KEYFORMAT")) ?? [], path: path)
            renditionTree = try BOMTree(reading: store, headerBlock: try variable("RENDITIONS"), name: "RENDITIONS", path: path)
            facetTree = try BOMTree(reading: store, headerBlock: try variable("FACETKEYS"), name: "FACETKEYS", path: path)
            renditions = try renditionTree.pairs(in: store).map { pair -> Rendition in
                guard let key = store.block(pair.keyBlock), key.count == 2 * keyFormat.count else { throw NomacError("malformed rendition key", path: path) }
                let values = Dictionary(uniqueKeysWithValues: keyFormat.enumerated().map { ($1, UInt16(key[2 * $0]) | UInt16(key[2 * $0 + 1]) << 8) })
                return Rendition(value: pair.value, keyBlock: pair.keyBlock, key: key, values: values)
            }
            self.store = store
            self.keyFormat = keyFormat
        }

        /// The indexes of the renditions a device of `idiom` and `scale` keeps. Of each set of
        /// renditions that differ only in scale and idiom it keeps one: of its own idiom or
        /// universal (others are left out), the nearest scale (its own, then lower ones from
        /// the closest, then higher ones), then its own idiom over universal; an atlas stays
        /// when a kept rendition links into it.
        func kept(idiom deviceIdiom: Int, scale deviceScale: Int, path: String) throws -> Set<Int> {
            let traitsUsed = Set(renditions.flatMap { $0.values.filter { $0.value != 0 }.keys }).subtracting(independent).subtracting([.scale, .idiom])
            guard traitsUsed.isEmpty, renditions.allSatisfy({ [0, 1, 2, 5].contains($0.values[.idiom] ?? 0) }) else {
                throw NomacError("thinning catalogs whose renditions depend on \(traitsUsed.map { "\($0)" }.sorted()) or on idioms other than iPhone, iPad and watch is not supported yet (BACKLOG B-465)",
                                 path: path)
            }
            func rank(_ rendition: Rendition) -> (Int, Int)? {
                let idiom = Int(rendition.values[.idiom] ?? 0)
                guard idiom == 0 || idiom == deviceIdiom else { return nil }
                let scale = Int(rendition.values[.scale] ?? 0)
                let scaleRank = scale == deviceScale ? 0 : scale < deviceScale ? deviceScale - scale : 100 + scale
                return (scaleRank, idiom == deviceIdiom ? 0 : 1)
            }
            var chosen: [[UInt16]: (rendition: Int, rank: (Int, Int))] = [:]
            for (index, rendition) in renditions.enumerated() where (rendition.values[.identifier] ?? 0) != 0 {
                guard let rank = rank(rendition) else { continue }
                let group = keyFormat.filter { independent.contains($0) }.map { rendition.values[$0] ?? 0 }
                if let current = chosen[group], current.rank <= rank { continue }
                chosen[group] = (index, rank)
            }
            var kept = Set(chosen.values.map(\.rendition))
            let linked = Set(try kept.compactMap { try CARThinning.linkedAtlasKey(store.block(renditions[$0].value) ?? [], path: path) })
            for (index, rendition) in renditions.enumerated() where (rendition.values[.identifier] ?? 0) == 0 {
                if linked.contains(CARThinning.keyBytes(rendition.values.filter { $0.value != 0 })) { kept.insert(index) }
            }
            return kept
        }
    }

    /// The platform `EXTENDED_METADATA` names (`ios`; `watch` for a watch app's catalog).
    static func platform(_ metadata: [UInt8], path: String) throws -> String {
        guard metadata.count >= 772, metadata.starts(with: Array("META".utf8)) else { throw NomacError("malformed EXTENDED_METADATA", path: path) }
        let name = String(decoding: metadata[516..<772].prefix { $0 != 0 }, as: UTF8.self)
        return name == "watch" ? "watchos" : name
    }

    static func keyFormat(_ block: [UInt8], path: String) throws -> [RenditionAttribute] {
        func le32(_ at: Int) -> UInt32 { block[at..<(at + 4)].reversed().reduce(0) { $0 << 8 | UInt32($1) } }
        guard block.count >= 12, block.starts(with: Array("tmfk".utf8)), block.count >= 12 + 4 * Int(le32(8)) else {
            throw NomacError("malformed KEYFORMAT", path: path)
        }
        return try (0..<Int(le32(8))).map { index in
            guard let attribute = RenditionAttribute(rawValue: UInt16(le32(12 + 4 * index))) else {
                throw NomacError("thinning catalogs with rendition attribute \(le32(12 + 4 * index)) is not supported yet (BACKLOG B-465)", path: path)
            }
            return attribute
        }
    }

    /// The key of the atlas a packed image's CSI links to (property 1010, `KLNI`), as
    /// `ImageSet.keyBytes` writes it.
    static func linkedAtlasKey(_ csi: [UInt8], path: String) throws -> [UInt8]? {
        func le32(_ at: Int) -> Int { csi[at..<(at + 4)].reversed().reduce(0) { $0 << 8 | Int($1) } }
        guard csi.count >= 0xB8, csi.starts(with: Array("ISTC".utf8)) else { throw NomacError("malformed CSI", path: path) }
        var at = 0xB8
        let end = 0xB8 + le32(0xA8)
        while at + 8 <= end {
            let type = le32(at), length = le32(at + 4)
            if type == 1010, length >= 28 {
                let keyLength = Int(csi[at + 8 + 26]) | Int(csi[at + 8 + 27]) << 8
                return Array(csi[(at + 8 + 30)..<(at + 8 + 30 + keyLength)])
            }
            at += 8 + length
        }
        return nil
    }

    static func keyBytes(_ values: [RenditionAttribute: UInt16]) -> [UInt8] {
        ImageSet.keyBytes(values.map { ($0.key, $0.value) })
    }

    /// The identifier a facet's token names (attribute 17), if any.
    static func identifier(ofFacetToken token: [UInt8]) -> UInt16? {
        guard token.count >= 6 else { return nil }
        let count = Int(token[4]) | Int(token[5]) << 8
        for index in 0..<count where 6 + 4 * index + 4 <= token.count {
            let attribute = UInt16(token[6 + 4 * index]) | UInt16(token[7 + 4 * index]) << 8
            if attribute == RenditionAttribute.identifier.rawValue { return UInt16(token[8 + 4 * index]) | UInt16(token[9 + 4 * index]) << 8 }
        }
        return nil
    }

    /// Every block of the number tree whose header is `header`: the header, its nodes and the
    /// leaves' values.
    static func numberTreeBlocks(_ store: BOMStoreWriter, header: UInt32) -> [UInt32] {
        func be32(_ bytes: [UInt8], _ at: Int) -> UInt32 { bytes[at..<(at + 4)].reduce(0) { $0 << 8 | UInt32($1) } }
        guard let headerBytes = store.block(header), headerBytes.count >= 12 else { return [header] }
        var blocks = [header]
        func visit(_ node: UInt32) {
            guard let bytes = store.block(node), bytes.count >= 12 else { return }
            blocks.append(node)
            let isLeaf = bytes[1] == 1
            let count = Int(bytes[2]) << 8 | Int(bytes[3])
            for index in 0..<count {
                let block = be32(bytes, 12 + 8 * index)
                if isLeaf { blocks.append(block) } else { visit(block) }
            }
            if !isLeaf, bytes.count >= 16 + 8 * count { visit(be32(bytes, 12 + 8 * count)) }
        }
        visit(be32(headerBytes, 8))
        return blocks
    }
}
