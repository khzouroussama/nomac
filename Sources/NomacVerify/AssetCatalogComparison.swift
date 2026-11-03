import CZlib
import Foundation
import NomacCore

/// Compares actool's outputs with nomac's where bytes alone cannot: an `Assets.car` and the icon
/// PNGs written beside it (docs/VERIFICATION.md "Asset catalogs"). Two kinds of difference are
/// accepted, nothing else:
///
/// - actool's run-to-run variations: the order of the appearance-key blocks (ADR 0200), and in a
///   catalog with an Icon Composer icon the UUID, process number and time that end the names of
///   its rendered images and the part of its facet, 220 or 245 (ADR 0203);
/// - rendered pixels (ADR 0204): the payloads of an Icon Composer icon's rendered images and the
///   pixels of the icon PNGs drawn from it, and those of images whose PNG has a color profile
///   other than sRGB IEC61966-2.1 and of their atlases, whose every other byte must match.
public enum AssetCatalogComparison {
    public enum Result: Equatable, Sendable {
        case identical
        /// The documented causes of the differences.
        case equivalent([String])
        /// The differences no cause explains.
        case different([String])
    }

    static let appearanceOrder = "actool's appearance-key blocks put in name order (ADR 0200)"
    static let facetPart = "the facet of an Icon Composer icon names part 220 or part 245 from one actool run to the next (ADR 0203)"
    static let renderedNames = "the names of an Icon Composer icon's rendered images end in a UUID, a process number and a time that change from one actool run to the next (ADR 0203)"
    static let renderedPixels = "pixels nomac's renderer draws for an Icon Composer icon (ADR 0204)"
    static let convertedPixels = "colors nomac converts from an image's color profile to sRGB (ADR 0204)"
    static let rasterizedPixels = "pixels nomac's renderer draws for an image from a vector file (ADR 0204)"
    static let decodedPixels = "pixels heif-dec decodes for a HEIC image and nomac stores in 16 bits or as a JPEG (ADR 0204)"

    /// A PNG of an image or app icon set that actool converts to sRGB: the set's folder name
    /// without its extension and the file's name.
    public struct ConvertedImage: Hashable, Sendable {
        public var set: String
        public var file: String

        public init(set: String, file: String) {
            self.set = set
            self.file = file
        }
    }

    /// The PNGs of the image and app icon sets under `roots` (catalogs or folders holding them)
    /// whose `iCCP` profile is not sRGB IEC61966-2.1.
    public static func convertedImages(under roots: [String]) -> Set<ConvertedImage> {
        var result = Set<ConvertedImage>()
        for root in roots {
            guard let walker = FileManager.default.enumerator(atPath: root) else { continue }
            while let relative = walker.nextObject() as? String {
                let folder = (relative as NSString).deletingLastPathComponent
                let type = (folder as NSString).pathExtension
                guard ["imageset", "appiconset"].contains(type), relative.lowercased().hasSuffix(".png"),
                      let data = FileManager.default.contents(atPath: root + "/" + relative), convertsColors(Array(data)) else { continue }
                result.insert(ConvertedImage(set: ((folder as NSString).lastPathComponent as NSString).deletingPathExtension,
                                             file: (relative as NSString).lastPathComponent))
            }
        }
        return result
    }

    /// A PNG with an `iCCP` profile other than sRGB IEC61966-2.1.
    static func convertsColors(_ png: [UInt8]) -> Bool {
        guard let chunks = pngChunks(png), let chunk = chunks.first(where: { $0.type == "iCCP" }),
              let name = chunk.data.firstIndex(of: 0), name + 2 < chunk.data.count else { return false }
        guard let profile = inflated(Array(chunk.data[(name + 2)...])) else { return false }
        return !ICCProfile.isStandardSRGB(profile)
    }

    /// zlib data decompressed, or `nil` when it does not end.
    static func inflated(_ data: [UInt8]) -> [UInt8]? {
        var input = data
        var stream = z_stream()
        guard inflateInit_(&stream, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return nil }
        defer { inflateEnd(&stream) }
        var output: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 1 << 14)
        var status = Z_OK
        input.withUnsafeMutableBufferPointer { source in
            stream.next_in = source.baseAddress
            stream.avail_in = UInt32(source.count)
            repeat {
                buffer.withUnsafeMutableBufferPointer { target in
                    stream.next_out = target.baseAddress
                    stream.avail_out = UInt32(target.count)
                    status = inflate(&stream, Z_NO_FLUSH)
                }
                output += buffer[..<(buffer.count - Int(stream.avail_out))]
            } while status == Z_OK
        }
        return status == Z_STREAM_END ? output : nil
    }

    /// The comparison for one of actool's outputs, or `nil` when the file is not one this
    /// comparison knows. `xcodeCatalog` is the `Assets.car` beside Xcode's file, which tells
    /// which PNGs are drawn from an Icon Composer icon.
    public static func compare(fileName: String, xcode: Data, nomac: Data, xcodeCatalog: Data?, converted: Set<ConvertedImage> = []) -> Result? {
        if xcode == nomac { return .identical }
        if fileName.hasSuffix(".car") { return compareCatalogs(xcode, nomac, converted: converted) }
        if fileName.hasSuffix(".png"), let catalog = xcodeCatalog, renderedIconNames(catalog).contains(where: { isIconPNG(fileName, of: $0) }) {
            return compareIconPNGs(xcode, nomac)
        }
        return nil
    }

    /// Xcode's `Assets.car` and nomac's.
    public static func compareCatalogs(_ xcode: Data, _ nomac: Data, converted: Set<ConvertedImage> = []) -> Result {
        if xcode == nomac { return .identical }
        guard var left = Store(Array(xcode)), var right = Store(Array(nomac)) else {
            return .different(["not a BOM store"])
        }
        guard left.serialized() == Array(xcode) else { return .different(["Xcode's file is not laid out as docs/formats/asset-catalog.md describes"]) }
        guard right.serialized() == Array(nomac) else { return .different(["nomac's file is not laid out as docs/formats/asset-catalog.md describes"]) }
        var causes: [String] = []
        let leftBefore = left.blocks, rightBefore = right.blocks
        let sorted = left.sortAppearanceKeys().union(right.sortAppearanceKeys())
        if sorted.contains(where: { $0 < rightBefore.count && leftBefore[$0] != rightBefore[$0] }) { causes.append(appearanceOrder) }
        let leftRendered = left.normalizeIconComposer(), rightRendered = right.normalizeIconComposer()
        if leftRendered.facets.union(rightRendered.facets).contains(where: { $0 < rightBefore.count && leftBefore[$0] != rightBefore[$0] }) {
            causes.append(facetPart)
        }
        if leftRendered.renditions.contains(where: { left.renditionNames[$0] != right.renditionNames[$0] }) { causes.append(renderedNames) }
        guard left.variables.elementsEqual(right.variables, by: ==) else { return .different(["the stores name other blocks"]) }
        guard left.blocks.count == right.blocks.count else {
            return .different(["\(left.blocks.count - 1) blocks in Xcode's file, \(right.blocks.count - 1) in nomac's"])
        }
        let pixelBlocks = left.pixelRenditions(converted)
        var differences: [String] = []
        var pixels = false
        var pixelCauses: [String] = []
        for index in left.blocks.indices where left.blocks[index] != right.blocks[index] {
            if leftRendered.renditions.contains(index), rightRendered.renditions.contains(index),
               renderedRenditionsMatch(left.blocks[index], right.blocks[index]) {
                pixels = true
            } else if let cause = pixelBlocks[index], renderedRenditionsMatch(left.blocks[index], right.blocks[index]) {
                if !pixelCauses.contains(cause) { pixelCauses.append(cause) }
            } else if pdfRenditionsMatch(left.blocks[index], right.blocks[index]) {
                if !pixelCauses.contains(pdfProfiles) { pixelCauses.append(pdfProfiles) }
            } else {
                differences.append("block \(index)\(left.renditionNames[index].map { " (rendition \($0))" } ?? "") differs")
            }
        }
        if !differences.isEmpty { return .different(differences) }
        if pixels { causes.append(renderedPixels) }
        causes += pixelCauses.sorted()
        return causes.isEmpty ? .identical : .equivalent(causes)
    }

    /// Xcode's icon PNG drawn from an Icon Composer icon and nomac's: the same chunks in the
    /// same order with the same contents, but for the image data and the offset of the second
    /// half of it in `iDOT`.
    public static func compareIconPNGs(_ xcode: Data, _ nomac: Data) -> Result {
        guard let left = pngChunks(Array(xcode)), let right = pngChunks(Array(nomac)) else { return .different(["not a PNG file"]) }
        guard left.map(\.type) == right.map(\.type) else {
            return .different(["chunks \(left.map(\.type).joined(separator: " ")) in Xcode's file, \(right.map(\.type).joined(separator: " ")) in nomac's"])
        }
        for (x, y) in zip(left, right) where x.type != "IDAT" {
            let masked = { (chunk: (type: String, data: [UInt8])) -> [UInt8] in
                chunk.type == "iDOT" && chunk.data.count == 28 ? Array(chunk.data[0..<24]) : chunk.data
            }
            if masked(x) != masked(y) { return .different(["the \(x.type) chunks differ"]) }
        }
        return .equivalent([renderedPixels])
    }

    /// The names of the icons whose PNGs actool draws: the Icon Composer icons (facets whose
    /// identifier has an icon stack, part 245) and the single-size app icon sets (every app icon
    /// image, part 220, 1,024 pixels wide), whose PNGs it resizes.
    public static func renderedIconNames(_ catalog: Data) -> Set<String> {
        guard let store = Store(Array(catalog)) else { return [] }
        let stacks = store.iconStackIdentifiers()
        var widths: [Int: Set<UInt32>] = [:]
        for rendition in store.renditionKeys() where rendition.key[2] == 220 {
            if let identifier = rendition.key[17] { widths[identifier, default: []].insert(le32(store.blocks[rendition.value], 12)) }
        }
        return Set(store.facets().filter { stacks.contains($0.identifier) || widths[$0.identifier] == [1024] }.map(\.name))
    }

    /// `true` for an icon PNG actool writes for the icon `icon`: its name followed by a size, a
    /// scale and an idiom suffix (`expo60x60@2x.png`, `expo76x76@2x~ipad.png`).
    static func isIconPNG(_ fileName: String, of icon: String) -> Bool {
        guard fileName.hasPrefix(icon) else { return false }
        return fileName.dropFirst(icon.count).wholeMatch(of: /\d+(\.\d+)?x\d+(\.\d+)?(@\dx)?(~[a-z]+)?\.png/) != nil
    }

    /// Two rendered renditions match when their headers, but for the rendition's length, their
    /// properties and the first 12 bytes of their payloads (the `CELM` tag, its flags and its
    /// compression) are identical.
    static func renderedRenditionsMatch(_ x: [UInt8], _ y: [UInt8]) -> Bool {
        guard x.count >= CSI.headerSize, y.count >= CSI.headerSize,
              x[0..<CSI.lengthOffset] == y[0..<CSI.lengthOffset] else { return false }
        let properties = Int(le32(x, CSI.propertiesOffset))
        let end = CSI.headerSize + properties + 12
        guard x.count >= end, y.count >= end else { return false }
        return x[CSI.headerSize..<end] == y[CSI.headerSize..<end]
    }

    static func pngChunks(_ bytes: [UInt8]) -> [(type: String, data: [UInt8])]? {
        guard bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) else { return nil }
        var chunks: [(type: String, data: [UInt8])] = []
        var offset = 8
        while offset + 12 <= bytes.count {
            let length = Int(be32(bytes, offset))
            guard offset + 12 + length <= bytes.count else { return nil }
            let type = String(decoding: bytes[offset + 4..<offset + 8], as: UTF8.self)
            if !(type == "IDAT" && chunks.last?.type == "IDAT") {
                chunks.append((type, Array(bytes[offset + 8..<offset + 8 + length])))
            }
            offset += 12 + length
        }
        return offset == bytes.count ? chunks : nil
    }

    /// The fields of a rendition's CSI header the comparison reads (docs/formats/asset-catalog.md).
    enum CSI {
        static let nameOffset = 40
        static let nameLength = 128
        static let propertiesOffset = 168
        static let lengthOffset = 180
        static let headerSize = 184
    }

    /// A BOM store's blocks and variables, as docs/formats/asset-catalog.md "BOM container"
    /// describes them.
    struct Store {
        var blocks: [[UInt8]]
        var variables: [Variable]
        var renditionNames: [Int: String] = [:]

        struct Variable: Equatable {
            var name: String
            var block: Int
        }

        init(blocks: [[UInt8]], variables: [Variable]) {
            self.blocks = blocks
            self.variables = variables
        }

        init?(_ bytes: [UInt8]) {
            guard bytes.count >= 32, bytes.starts(with: Array("BOMStore".utf8)) else { return nil }
            let count = Int(be32(bytes, 12)), indexOffset = Int(be32(bytes, 16)), variablesOffset = Int(be32(bytes, 24))
            guard indexOffset + 4 + 8 * (count + 1) <= bytes.count, variablesOffset + 4 <= bytes.count else { return nil }
            blocks = []
            for index in 0...count {
                let address = Int(be32(bytes, indexOffset + 4 + 8 * index)), length = Int(be32(bytes, indexOffset + 8 + 8 * index))
                guard address + length <= bytes.count else { return nil }
                blocks.append(Array(bytes[address..<address + length]))
            }
            variables = []
            var offset = variablesOffset + 4
            for _ in 0..<be32(bytes, variablesOffset) {
                guard offset + 5 <= bytes.count, offset + 5 + Int(bytes[offset + 4]) <= bytes.count else { return nil }
                let length = Int(bytes[offset + 4])
                let block = Int(be32(bytes, offset))
                guard block < blocks.count else { return nil }
                variables.append(Variable(name: String(decoding: bytes[offset + 5..<offset + 5 + length], as: UTF8.self), block: block))
                offset += 5 + length
            }
            for entry in treeEntries("RENDITIONS") where blocks[entry.value].count >= CSI.headerSize {
                let name = blocks[entry.value][CSI.nameOffset..<CSI.nameOffset + CSI.nameLength].prefix { $0 != 0 }
                renditionNames[entry.value] = String(decoding: name, as: UTF8.self)
            }
        }

        /// The layout actool writes: a 512-byte header, the blocks at 16-byte boundaries, the
        /// variables and the block index.
        func serialized() -> [UInt8] {
            var out = [UInt8](repeating: 0, count: 512)
            func align() { out += [UInt8](repeating: 0, count: (16 - out.count % 16) % 16) }
            func append(_ value: Int) { out += withUnsafeBytes(of: UInt32(value).bigEndian, Array.init) }
            var addresses: [(Int, Int)] = [(0, 0)]
            for block in blocks.dropFirst() {
                align()
                addresses.append((out.count, block.count))
                out += block
            }
            align()
            let variablesOffset = out.count
            append(variables.count)
            for variable in variables {
                append(variable.block)
                out.append(UInt8(variable.name.utf8.count))
                out += Array(variable.name.utf8)
            }
            let variablesLength = out.count - variablesOffset
            align()
            let indexOffset = out.count
            let capacity = max(256, (addresses.count + 7) / 8 * 8)
            append(capacity)
            for slot in 0..<capacity {
                append(slot < addresses.count ? addresses[slot].0 : 0)
                append(slot < addresses.count ? addresses[slot].1 : 0)
            }
            append(0)
            out += [UInt8](repeating: 0, count: 16)
            var header = Array("BOMStore".utf8)
            for value in [1, blocks.count - 1, indexOffset, out.count - indexOffset, variablesOffset, variablesLength] {
                header += withUnsafeBytes(of: UInt32(value).bigEndian, Array.init)
            }
            out.replaceSubrange(0..<header.count, with: header)
            return out
        }

        func block(named name: String) -> Int? {
            variables.first { $0.name == name }?.block
        }

        /// The (key block, value block) pairs of a tree, leaf by leaf.
        func treeEntries(_ name: String) -> [(key: Int, value: Int)] {
            guard let tree = block(named: name), blocks[tree].count >= 12 else { return [] }
            var entries: [(key: Int, value: Int)] = []
            func visit(_ page: Int, depth: Int) {
                guard depth < 32, page < blocks.count, blocks[page].count >= 12 else { return }
                let bytes = blocks[page]
                let leaf = be16(bytes, 0) != 0, count = Int(be16(bytes, 2))
                guard bytes.count >= 12 + 8 * count + (leaf ? 0 : 4) else { return }
                for index in 0..<count {
                    let value = Int(be32(bytes, 12 + 8 * index)), key = Int(be32(bytes, 16 + 8 * index))
                    if leaf {
                        if key < blocks.count, value < blocks.count { entries.append((key, value)) }
                    } else {
                        visit(value, depth: depth + 1)
                    }
                }
                if !leaf { visit(Int(be32(bytes, 12 + 8 * count)), depth: depth + 1) }
            }
            visit(Int(be32(blocks[tree], 8)), depth: 0)
            return entries
        }

        /// Puts the appearance-key blocks in name order, as ADR 0200 does with actool's file;
        /// returns the blocks that changed.
        mutating func sortAppearanceKeys() -> Set<Int> {
            guard let tree = block(named: "APPEARANCEKEYS"), blocks[tree].count >= 12 else { return [] }
            let leafIndex = Int(be32(blocks[tree], 8))
            guard leafIndex < blocks.count, blocks[leafIndex].count >= 12, be16(blocks[leafIndex], 0) != 0 else { return [] }
            let entries = treeEntries("APPEARANCEKEYS")
            guard let first = entries.flatMap({ [$0.key, $0.value] }).min() else { return [] }
            let pairs = entries.map { (blocks[$0.key], blocks[$0.value]) }
                .sorted { $0.0 == $1.0 ? $0.1.lexicographicallyPrecedes($1.1) : $0.0.lexicographicallyPrecedes($1.0) }
            let before = blocks
            var leaf = blocks[leafIndex]
            for (index, pair) in pairs.enumerated() {
                blocks[first + 2 * index] = pair.0
                blocks[first + 2 * index + 1] = pair.1
                leaf.replaceSubrange(12 + 8 * index..<20 + 8 * index, with: be32Bytes(first + 2 * index + 1) + be32Bytes(first + 2 * index))
            }
            blocks[leafIndex] = leaf
            return Set(blocks.indices.filter { blocks[$0] != before[$0] })
        }

        /// The value blocks whose pixels nomac draws or converts, with the cause: the renditions of
        /// converted images (a rendition named for the file whose facet is named for the set, last
        /// path component), images rasterized from vector files (CSI flag 0x4 on an image or link
        /// rendition), and the atlases their link renditions (property 1010, `KLNI`) point to.
        func pixelRenditions(_ converted: Set<ConvertedImage>) -> [Int: String] {
            let facetNames = Dictionary(facets().map { ($0.identifier, $0.name) }, uniquingKeysWith: { first, _ in first })
            let keys = renditionKeys()
            var result: [Int: String] = [:]
            var atlasKeys: [([Int: Int], String)] = []
            for rendition in keys {
                guard let name = renditionNames[rendition.value] else { continue }
                let csi = blocks[rendition.value]
                let cause: String
                if le32(csi, 8) & 0x4 != 0, [0, 12, 1003].contains(le16(csi, 36)) {
                    cause = rasterizedPixels
                } else if name.lowercased().hasSuffix(".heic"), ["5BGR", "BGRA"].contains(String(decoding: csi[24..<28], as: UTF8.self)) {
                    cause = decodedPixels
                } else if let identifier = rendition.key[17], let facet = facetNames[identifier],
                          converted.contains(where: { $0.set == (facet.split(separator: "/").last.map(String.init) ?? facet) && $0.file == name }) {
                    cause = convertedPixels
                } else {
                    continue
                }
                result[rendition.value] = cause
                var offset = CSI.headerSize
                let end = CSI.headerSize + Int(le32(csi, CSI.propertiesOffset))
                while offset + 8 <= end {
                    let type = le32(csi, offset), length = Int(le32(csi, offset + 4))
                    if type == 1010, length >= 34 {
                        let link = offset + 8
                        let count = Int(le16(csi, link + 26)) / 4
                        var attributes: [Int: Int] = [:]
                        for pair in 0..<count where le16(csi, link + 30 + 4 * pair) != 0 {
                            attributes[Int(le16(csi, link + 30 + 4 * pair))] = Int(le16(csi, link + 32 + 4 * pair))
                        }
                        atlasKeys.append((attributes, cause))
                    }
                    offset += 8 + length
                }
            }
            for rendition in keys {
                if let atlas = atlasKeys.first(where: { $0.0 == rendition.key.filter { $0.value != 0 } }) { result[rendition.value] = atlas.1 }
            }
            return result
        }

        /// The rendition keys' attributes by number, from `KEYFORMAT`.
        func renditionKeys() -> [(key: [Int: Int], value: Int)] {
            guard let format = block(named: "KEYFORMAT"), blocks[format].count >= 12 else { return [] }
            let bytes = blocks[format]
            let count = Int(le32(bytes, 8))
            guard bytes.count >= 12 + 4 * count else { return [] }
            let attributes = (0..<count).map { Int(le32(bytes, 12 + 4 * $0)) }
            return treeEntries("RENDITIONS").compactMap { entry in
                let key = blocks[entry.key]
                guard key.count >= 2 * count else { return nil }
                return (Dictionary(uniqueKeysWithValues: attributes.enumerated().map { ($1, Int(le16(key, 2 * $0))) }), entry.value)
            }
        }

        func iconStackIdentifiers() -> Set<Int> {
            Set(renditionKeys().filter { $0.key[2] == 245 }.compactMap { $0.key[17] })
        }

        /// The facets' names, identifiers and value blocks.
        func facets() -> [(name: String, identifier: Int, value: Int)] {
            treeEntries("FACETKEYS").compactMap { entry in
                let bytes = blocks[entry.value]
                guard bytes.count >= 6 else { return nil }
                let count = Int(le16(bytes, 4))
                guard bytes.count >= 6 + 4 * count else { return nil }
                let identifier = (0..<count).first { le16(bytes, 6 + 4 * $0) == 17 }.map { Int(le16(bytes, 8 + 4 * $0)) } ?? -1
                return (String(decoding: blocks[entry.key], as: UTF8.self), identifier, entry.value)
            }
        }

        /// Writes part 220 in Icon Composer icons' facets and masks the varying end of their
        /// rendered images' names (ADR 0203); returns the facets' value blocks and the rendered
        /// renditions'.
        mutating func normalizeIconComposer() -> (facets: Set<Int>, renditions: Set<Int>) {
            let stacks = iconStackIdentifiers()
            guard !stacks.isEmpty else { return ([], []) }
            var iconFacets = Set<Int>()
            var rendered = Set<Int>()
            for facet in facets() where stacks.contains(facet.identifier) {
                iconFacets.insert(facet.value)
                for index in 0..<Int(le16(blocks[facet.value], 4)) where le16(blocks[facet.value], 6 + 4 * index) == 2 && le16(blocks[facet.value], 8 + 4 * index) == 245 {
                    blocks[facet.value].replaceSubrange(8 + 4 * index..<10 + 4 * index, with: [220, 0])
                }
            }
            for rendition in renditionKeys() where rendition.key[2] == 220 && stacks.contains(rendition.key[17] ?? -1) {
                guard let name = renditionNames[rendition.value],
                      let match = name.wholeMatch(of: /(.+_)[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}-[0-9]+-[0-9A-F]{16}\.png/) else { continue }
                var field = Array((match.1 + "UUID-PID-TIME.png").utf8).prefix(CSI.nameLength)
                field += [UInt8](repeating: 0, count: CSI.nameLength - field.count)
                blocks[rendition.value].replaceSubrange(CSI.nameOffset..<CSI.nameOffset + CSI.nameLength, with: field)
                rendered.insert(rendition.value)
            }
            return (iconFacets, rendered)
        }
    }
}

private func be32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
    bytes[offset..<offset + 4].reduce(0) { $0 << 8 | UInt32($1) }
}

private func be16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
    UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
}

private func le32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
    bytes[offset..<offset + 4].reversed().reduce(0) { $0 << 8 | UInt32($1) }
}

private func le16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
    UInt16(bytes[offset + 1]) << 8 | UInt16(bytes[offset])
}

private func be32Bytes(_ value: Int) -> [UInt8] {
    withUnsafeBytes(of: UInt32(value).bigEndian, Array.init)
}
