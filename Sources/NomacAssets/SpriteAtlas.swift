import NomacCore

/// Sprite atlases (docs/formats/asset-catalog.md, "Sprite atlases"; flappy-fly-bird, `sprites`):
/// the images of their image sets, trimmed of fully transparent rows and columns, are packed into
/// one atlas of the sprite atlas's own (`ZZZZExplicitlyPackedAsset`), with the growing
/// binary-tree packer of other atlases but neither its area limit nor its split, and a list of
/// the member names.
enum SpriteAtlas {
    /// The largest member observed packed (1,500 × 1,500 pixels; 1,900 × 1,900 stay alone).
    static let largestPackedMember = 2_250_000
    /// Members of at most this many pixels in all share one atlas whatever their order (4 of
    /// 1,000 × 1,000 pixels do, a fifth starts a second atlas).
    static let largestSingleAtlas = 3_000_000

    struct Member {
        var source: ImageSet.Source
        var originalWidth: Int
        var originalHeight: Int
        var left = 0
        var top = 0

        var isTrimmed: Bool { source.image.width != originalWidth || source.image.height != originalHeight }
    }

    /// The member, its image cut to the bounding box of its pixels whose alpha is not 0.
    static func trimmed(_ source: ImageSet.Source) throws -> Member {
        let image = source.image
        var left = image.width, right = -1, top = image.height, bottom = -1
        for y in 0..<image.height {
            for x in 0..<image.width where image.pixels[(y * image.width + x) * 4 + 3] != 0 {
                left = min(left, x)
                right = max(right, x)
                top = min(top, y)
                bottom = max(bottom, y)
            }
        }
        guard right >= 0 else {
            throw NomacError("fully transparent sprite atlas images are not supported yet (BACKLOG B-202)", path: source.path)
        }
        let width = right - left + 1, height = bottom - top + 1
        var pixels: [UInt8] = []
        pixels.reserveCapacity(width * height * 4)
        for y in top...bottom {
            pixels += image.pixels[((y * image.width) + left) * 4..<((y * image.width) + right + 1) * 4]
        }
        var trimmed = source
        trimmed.image = PNGImage(width: width, height: height, pixels: pixels)
        trimmed.isOpaque = trimmed.image.isOpaque
        trimmed.isGray = ImageSet.isGray(pixels)
        return Member(source: trimmed, originalWidth: image.width, originalHeight: image.height, left: left, top: top)
    }

    static func renditions(_ atlas: AssetCatalog.Asset, members sources: [ImageSet.Source], identifiers: [String: UInt16]) throws -> [CARRendition] {
        guard Set(atlas.contents.keys).isSubset(of: ["info"]) else {
            throw NomacError("sprite atlas properties are not supported yet (BACKLOG B-202)", path: atlas.path)
        }
        guard let first = sources.first, sources.allSatisfy({ $0.scale == first.scale && $0.idiom == first.idiom }) else {
            throw NomacError("sprite atlases without images, or with images of several scales or idioms, are not supported yet (BACKLOG B-202)", path: atlas.path)
        }
        let members = try sources.map(trimmed)
        let areas = members.map { $0.source.image.width * $0.source.image.height }
        guard areas.allSatisfy({ $0 <= largestPackedMember }), areas.reduce(0, +) <= largestSingleAtlas else {
            throw NomacError("sprite atlases of images over 2,250,000 pixels, or over 3,000,000 in all, are not supported yet (BACKLOG B-202)", path: atlas.path)
        }
        let atlasIdentifier = identifiers[atlas.name] ?? 0
        let items = Atlas.packingOrder(members.indices.map {
            Atlas.Item(id: $0, width: members[$0].source.image.width, height: members[$0].source.image.height, identifier: identifiers[members[$0].source.name] ?? 0)
        })
        let (positions, width, height) = Atlas.layout(items)
        let pixels = Atlas.compose(width: width, height: height, images: items.map {
            (pixels: members[$0.id].source.image.pixels, width: members[$0.id].source.image.width, height: members[$0.id].source.image.height,
             x: positions[$0.id]!.x, y: positions[$0.id]!.y)
        })
        var attributes = ImageSet.attributes(scale: first.scale, idiom: first.idiom)
        attributes[.part] = FacetKind.packedImage.part
        let atlasKey = ImageSet.keyBytes([(.element, FacetKind.spriteAtlas.element), (.identifier, atlasIdentifier)] + attributes.map { ($0.key, $0.value) })

        let byIdentifier = members.sorted { (identifiers[$0.source.name] ?? 0) < (identifiers[$1.source.name] ?? 0) }
        func table(_ record: (Member) -> [UInt8]) -> [UInt8] { ImageSet.little(UInt32(members.count)) + ImageSet.little(0) + byIdentifier.flatMap(record) }
        let memberKeys = table { member in
            let key = ImageSet.keyBytes([(.element, FacetKind.image.element), (.part, FacetKind.image.part), (.scale, UInt16(first.scale)),
                                         (.identifier, identifiers[member.source.name] ?? 0)])
            return [UInt8](repeating: 0, count: 24) + ImageSet.little(0x3F80_0000) + ImageSet.little(UInt32(key.count)) + key
        }
        let atlasCSI = CSI(name: "ZZZZExplicitlyPackedAsset-\(first.scale).0.0-gamut0", layout: .atlas, width: UInt32(width), height: UInt32(height),
                           colorModel: 1, scale: UInt32(100 * first.scale), pixelFormat: "ARGB",
                           properties: [
                               (1001, ImageSet.little(1) + [UInt8](repeating: 0, count: 16)), (1012, memberKeys),
                               (1020, table { _ in [UInt8](repeating: 0, count: 8) + ImageSet.little(1) + [0] }),
                               (1021, table { _ in [UInt8](repeating: 0, count: 20) }), (1022, table { _ in [UInt8](repeating: 0, count: 12) }),
                           ] + ImageSet.commonProperties + [(1007, ImageSet.little(ImageSet.rowBytes(width: width, opaque: false, gray: false)))],
                           payload: try Deepmap2.payload(pixels, format: .bgra, width: width, height: height, opaque: false))
        var renditions = [CARRendition(name: atlas.name, kind: .spriteAtlas, attributes: attributes, csi: atlasCSI.bytes)]

        let names = members.map(\.source.name).sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        let list = ImageSet.little(UInt32(names.count)) + ImageSet.little(0) + names.flatMap { ImageSet.little(UInt32($0.utf8.count)) + Array($0.utf8) }
        let structured = CSI(name: "CoreStructuredImage", layout: .structuredImage, scale: 100,
                             properties: [(1004, [UInt8](repeating: 0, count: 8)), (1006, ImageSet.little(1)), (1013, list)], payload: [])
        renditions.append(CARRendition(name: atlas.name, kind: .spriteAtlas, attributes: [.scale: 1, .part: 127], csi: structured.bytes))

        for (index, member) in members.enumerated() {
            let source = member.source, position = positions[index]!
            let link = ImageSet.link(x: position.x, y: position.y, width: source.image.width, height: source.image.height, atlasKey: atlasKey)
            let slice = [1, 0, 0, member.originalWidth, member.originalHeight].flatMap { ImageSet.little(UInt32($0)) }
            let metrics = [1, 0, 0, 0, 0, source.image.width, source.image.height].flatMap { ImageSet.little(UInt32($0)) }
            var properties: [(type: UInt32, value: [UInt8])] = [(1001, slice), (1003, metrics), (1010, link)] + ImageSet.commonProperties
            if member.isTrimmed {
                properties.append((1011, trim(member)))
            }
            let csi = ImageSet.imageCSI(source, layout: .packedImage, properties: properties, payload: [])
            renditions.append(CARRendition(name: source.name, kind: .image, attributes: source.attributes, csi: csi.bytes))
        }
        return renditions
    }

    /// Property 1011 of a trimmed member: 1011, 0, the original size, then the kept rectangle,
    /// y from the top (`sprites`, trim cases).
    static func trim(_ member: Member) -> [UInt8] {
        [1011, 0, member.originalWidth, member.originalHeight, member.left, member.top, member.source.image.width, member.source.image.height]
            .flatMap { ImageSet.little(UInt32($0)) }
    }
}
