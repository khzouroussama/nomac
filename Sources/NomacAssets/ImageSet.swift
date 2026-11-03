import Foundation
import NomacCore
import NomacLZFSE

/// Compiles `.imageset` assets for deployment targets of iOS 13.0 and later, where actool writes
/// one deepmap2 rendition per image (docs/formats/asset-catalog.md, "Images"): small images packed
/// into atlases, the others on their own.
enum ImageSet {
    struct Source {
        var name: String
        var filename: String
        var path: String
        var image: PNGImage
        var scale: Int
        var idiom: UInt16
        /// App icons' images (`AppIconSet`): part 220, their size's `dim2` and the iPhone 60 pt
        /// 3x image's subtype 1792 copy.
        var kind = FacetKind.image
        var dimension2: UInt16 = 0
        var subtype: UInt16 = 0
        /// An Icon Composer icon's rendered images are for an appearance.
        var appearance: UInt16 = 0
        /// The set's `template-rendering-intent`, `template` or `original`.
        var renderingIntent: String?
        /// A JPEG file, stored as it is rather than as pixels (`JPEGFile`).
        var jpeg: JPEGFile?
        /// A HEIC file as actool stores it for target 2, beside its decoded pixels.
        var heif: [UInt8]?
        /// An image rasterized from an SVG file by nomac's renderer (ADR 0204), with the file's
        /// bytes on the 1x one for the vector rendition, and the set's
        /// `preserves-vector-representation`.
        var rasterized = false
        var vectorData: [UInt8]?
        var preservesVector = false
        /// The scale of the entry an SVG file is in, which keys its preserved vector rendition.
        var vectorScale: UInt16 = 1
        /// A symbol set's image: the glyph's weight and size and the target (`SymbolSet`).
        var glyph: (weight: UInt16, size: UInt16, target: UInt16)?
        /// A rasterized image's slice (property 1001): its content, at the bottom left.
        var slice: (x: Int, y: Int, width: Int, height: Int)?

        var isOpaque: Bool
        var isGray: Bool

        init(name: String, filename: String, path: String, image: PNGImage, scale: Int = 1, idiom: UInt16 = Idiom.universal) {
            self.name = name
            self.filename = filename
            self.path = path
            self.image = image
            self.scale = scale
            self.idiom = idiom
            isOpaque = image.isOpaque
            isGray = ImageSet.isGray(image.pixels)
        }

        var attributes: [RenditionAttribute: UInt16] { attributes(gamut: 0) }

        func attributes(gamut: UInt16) -> [RenditionAttribute: UInt16] {
            var attributes = ImageSet.attributes(scale: scale, idiom: idiom, subtype: subtype)
            if gamut != 0 { attributes[.displayGamut] = gamut }
            if dimension2 != 0 { attributes[.dimension2] = dimension2 }
            if appearance != 0 { attributes[.appearance] = appearance }
            if let glyph {
                attributes[.glyphWeight] = glyph.weight
                attributes[.glyphSize] = glyph.size
                attributes[.target] = glyph.target
            }
            return attributes
        }

        var packingClass: PackingClass {
            PackingClass(scale: scale, idiom: idiom, subtype: subtype, opaque: isOpaque, gray: isGray, target: glyph?.target ?? 0, appearance: appearance)
        }
    }

    static func attributes(scale: Int, idiom: UInt16, subtype: UInt16 = 0) -> [RenditionAttribute: UInt16] {
        var attributes: [RenditionAttribute: UInt16] = [.scale: UInt16(scale)]
        if idiom != Idiom.universal { attributes[.idiom] = idiom }
        if subtype != 0 { attributes[.subtype] = subtype }
        return attributes
    }

    /// What actool packs together: images of one scale, idiom and subtype, opaque or not, gray or
    /// not (atlas `ZZZZPackedAsset-<scale>.<opaque>.<gray>`), numbered in that order within their
    /// scale and idiom. The subtype keeps an app icon's subtype 1792 image, the only one of its
    /// class, on its own (uncloudnotes, flappy-fly-bird).
    struct PackingClass: Hashable, Comparable {
        var scale: Int
        var idiom: UInt16
        var subtype: UInt16 = 0
        var opaque: Bool
        var gray: Bool
        /// Symbol sets' images are packed apart, their atlas keyed with target 5 (`symbols-sets`).
        var target: UInt16 = 0
        /// Display-gamut-1 `RGBW` renditions are packed apart, in their own atlases (`profiles` wide case).
        var gamut: UInt16 = 0
        /// Each appearance's images are packed apart, their atlas keyed with it (`pdf_experiments.py`
        /// appearances).
        var appearance: UInt16 = 0

        static func < (a: PackingClass, b: PackingClass) -> Bool {
            if a.gamut != b.gamut { return a.gamut < b.gamut }
            if a.appearance != b.appearance { return a.appearance < b.appearance }
            return (a.scale, a.idiom, a.subtype, a.opaque ? 1 : 0, a.gray ? 1 : 0, a.target) < (b.scale, b.idiom, b.subtype, b.opaque ? 1 : 0, b.gray ? 1 : 0, b.target)
        }

        var atlasName: String { "ZZZZPackedAsset-\(scale).\(opaque ? 1 : 0).\(gray ? 1 : 0)-gamut\(gamut)" }
    }

    static let scales = ["1x": 1, "2x": 2, "3x": 3]

    /// The PNG of each entry for a universal or targeted device idiom, an entry without a scale
    /// being 1x; entries without a file, and those of devices the build does not target, add
    /// nothing (`images`, idioms). actool warns about an iPad 3x entry and compiles nothing for it,
    /// where nomac stops.
    static func sources(_ asset: AssetCatalog.Asset, idioms: [String: UInt16], platform: Actool.Platform? = nil) throws -> [Source] {
        let properties = asset.contents["properties"] as? [String: Any] ?? [:]
        let renderingIntent = properties["template-rendering-intent"] as? String
        let preservesVector = (properties["preserves-vector-representation"] as? NSNumber)?.boolValue ?? false
        let unsupported = Set(asset.contents.keys).subtracting(["images", "info", "properties"])
            .union(Set(properties.keys).subtracting(["template-rendering-intent", "preserves-vector-representation"]))
        guard unsupported.isEmpty, [nil, "template", "original"].contains(renderingIntent) else {
            throw NomacError("image set properties \(unsupported.sorted()) are not supported yet (BACKLOG B-200)", path: asset.path)
        }
        var sources: [Source] = []
        for entry in asset.contents["images"] as? [[String: Any]] ?? [] {
            guard let filename = entry["filename"] as? String else { continue }
            let keys = Set(entry.keys).subtracting(["filename", "idiom", "scale"])
            let idiomName = entry["idiom"] as? String ?? "universal"
            // An entry may have an appearance, a watch image a screen width.
            guard keys.subtracting(["appearances"]).isEmpty || keys.subtracting(["appearances"]) == ["screen-width"] && idiomName == "watch" else {
                throw NomacError("image set entries with \(keys.sorted()) are not supported yet (BACKLOG B-200)", path: asset.path)
            }
            let appearance = try entryAppearance(entry, asset: asset)
            // watchOS keeps only the images for any appearance (`image-appearances` watch cases).
            if platform?.watch == true && appearance != .any { continue }
            var subtype: UInt16 = 0
            if let width = entry["screen-width"] {
                guard let value = (width as? String).flatMap({ screenWidthSubtypes[$0] }) else {
                    throw NomacError("image set entries for screen width '\(width)' are not supported yet: actool warns about them (BACKLOG B-204)", path: asset.path)
                }
                subtype = value
            }
            guard let idiom = idioms[idiomName] else {
                guard Idiom.devices.contains(idiomName) else {
                    throw NomacError("image set entries for idiom '\(idiomName)' are not supported yet (BACKLOG B-200)", path: asset.path)
                }
                continue
            }
            guard let scale = scales[entry["scale"] as? String ?? "1x"], idiomName != "ipad" || scale < 3 else {
                throw NomacError("image set entries for \(idiomName) at scale '\(entry["scale"] ?? "")' are not supported yet (BACKLOG B-200)", path: asset.path)
            }
            // watchOS keeps 1x and 2x files (`watchos` experiment).
            if let platform, !platform.fileScales.contains(scale), (filename as NSString).pathExtension.lowercased() != "svg" { continue }
            let type = (filename as NSString).pathExtension.lowercased()
            guard ["png", "jpg", "jpeg", "svg", "pdf", "heic"].contains(type) else {
                throw NomacError("image files other than PNG, JPEG, SVG, PDF and HEIC are not supported yet (BACKLOG B-200)", path: asset.path + "/" + filename)
            }
            guard subtype == 0 || !["svg", "pdf"].contains(type) else {
                throw NomacError("SVG and PDF image set entries with a screen width are not supported yet (BACKLOG B-204)", path: asset.path)
            }
            if type == "pdf" {
                // A PDF in the 1x entry, the others empty, is compiled as one without a scale
                // (`pdf_experiments.py` entries); each luminosity appearance has its own PDF.
                let files = (asset.contents["images"] as? [[String: Any]] ?? []).filter {
                    $0["filename"] != nil && (try? entryAppearance($0, asset: asset)) == appearance
                }.count
                guard idiom == Idiom.universal, entry["scale"] == nil || entry["scale"] as? String == "1x" && files == 1,
                      !sources.contains(where: { $0.idiom == idiom && $0.appearance == appearance.rawValue }) else {
                    throw NomacError("PDF image set entries other than one universal entry without a scale are not supported yet (BACKLOG B-215)", path: asset.path)
                }
                sources += try pdfImages(asset, filename: filename, renderingIntent: renderingIntent, preservesVector: preservesVector,
                                         scales: platform?.rasterScales ?? [1, 2, 3]).map { source in
                    var source = source
                    source.appearance = appearance.rawValue
                    return source
                }
                continue
            }
            if type == "svg" {
                guard idiom == Idiom.universal, !sources.contains(where: { $0.idiom == idiom && $0.appearance == appearance.rawValue }) else {
                    throw NomacError("SVG image set entries other than one universal entry per appearance are not supported yet (BACKLOG B-200)", path: asset.path)
                }
                sources += try rasterized(asset, filename: filename, renderingIntent: renderingIntent, preservesVector: preservesVector,
                                          slot: entry["scale"] == nil ? 1 : scale, scales: platform?.rasterScales ?? [1, 2, 3]).map { source in
                    var source = source
                    source.appearance = appearance.rawValue
                    return source
                }
                continue
            }
            guard !sources.contains(where: { $0.scale == scale && $0.idiom == idiom && $0.subtype == subtype && $0.appearance == appearance.rawValue }) else {
                throw NomacError("image sets with two images of one idiom and scale are not supported yet (BACKLOG B-200)", path: asset.path)
            }
            let path = asset.path + "/" + filename
            var source: Source
            if type == "png" {
                source = Source(name: asset.name, filename: filename, path: path, image: try PNGImage(contentsOf: path), scale: scale, idiom: idiom)
            } else if type == "heic" {
                guard let data = FileManager.default.contents(atPath: path) else { throw NomacError("could not read the image", path: path) }
                let image = try HEICImage.decode(path)
                source = Source(name: asset.name, filename: filename, path: path, image: image, scale: scale, idiom: idiom)
                source.heif = try HEICImage.rewritten([UInt8](data), size: (image.width, image.height), path: path)
            } else {
                guard let data = FileManager.default.contents(atPath: path) else { throw NomacError("could not read the image", path: path) }
                let jpeg = try JPEGFile([UInt8](data), path: path)
                source = Source(name: asset.name, filename: filename, path: path, image: PNGImage(width: jpeg.width, height: jpeg.height, pixels: []),
                                scale: scale, idiom: idiom)
                source.jpeg = jpeg
            }
            if let role = asset.complicationRole {
                try ComplicationSet.checkSize(source.image, role: role, screenWidth: entry["screen-width"] as? String, path: path)
            }
            source.subtype = subtype
            source.appearance = appearance.rawValue
            source.renderingIntent = renderingIntent
            source.preservesVector = preservesVector
            sources.append(source)
        }
        return sources
    }

    /// An entry's appearance (`pdf_experiments.py` and `image-appearances`).
    static func entryAppearance(_ entry: [String: Any], asset: AssetCatalog.Asset) throws -> RenditionAppearance {
        let appearances = entry["appearances"] as? [[String: Any]] ?? []
        guard let appearance = RenditionAppearance(entry: appearances) else {
            let pairs = appearances.map { ($0["appearance"] as? String ?? "", $0["value"] as? String ?? "") }
            throw NomacError("image set entries with the appearances \(pairs) are not supported yet (BACKLOG B-200)", path: asset.path)
        }
        return appearance
    }

    /// The watch subtypes of the screen widths Xcode offers for watch images: 38mm, 42mm, 40mm and
    /// 44mm (`complications` experiment; other values get "Unknown screen-width value").
    static let screenWidthSubtypes: [String: UInt16] = ["<=145": 320, ">145": 384, ">161": 340, ">183": 390]

    /// Images whose premultiplied pixels are all gray (fully transparent ones too) are stored as
    /// `GA8`: color model 2, the gray and alpha of each pixel.
    static func isGray(_ bgra: [UInt8]) -> Bool {
        stride(from: 0, to: bgra.count, by: 4).allSatisfy { bgra[$0] == bgra[$0 + 1] && bgra[$0 + 1] == bgra[$0 + 2] }
    }

    /// The bytes deepmap2 stores: BGRA, or gray and alpha, whose alpha is 255 in an opaque image,
    /// even in the transparent borders of an opaque class's atlas (`images`, classes-gray).
    static func stored(_ bgra: [UInt8], gray: Bool, opaque: Bool) -> [UInt8] {
        guard gray else { return bgra }
        var pixels = [UInt8](repeating: 0, count: bgra.count / 2)
        for pixel in 0..<bgra.count / 4 {
            pixels[pixel * 2] = bgra[pixel * 4]
            pixels[pixel * 2 + 1] = opaque ? 255 : bgra[pixel * 4 + 3]
        }
        return pixels
    }

    /// Property 1007: the width times 4 bytes, or 1 for an opaque gray image, rounded up to 32;
    /// for the payload without deepmap2 the width times the bytes it stores per pixel.
    static func rowBytes(width: Int, opaque: Bool, gray: Bool, plain: Bool = false) -> UInt32 {
        let pixelBytes = plain ? (gray ? 2 : 4) : (opaque && gray ? 1 : 4)
        return UInt32((width * pixelBytes + 31) / 32 * 32)
    }

    static func format(gray: Bool) -> (pixelFormat: String, colorModel: UInt32, deepmap: Deepmap2.Format) {
        gray ? ("GA8 ", 2, .gray) : ("ARGB", 1, .bgra)
    }

    static let commonProperties: [(type: UInt32, value: [UInt8])] = [
        (1004, little(0) + little(0x3F80_0000)),
        (1006, little(1)),
    ]

    static func little(_ value: UInt32) -> [UInt8] {
        var out = ByteWriter()
        out.appendLE(value)
        return out.bytes
    }

    /// Slices (1001) and metrics (1003) of an image shown whole, or of a rasterized one's slice.
    static func geometry(width: Int, height: Int, slice: (x: Int, y: Int, width: Int, height: Int)? = nil) -> [(type: UInt32, value: [UInt8])] {
        let size = little(UInt32(width)) + little(UInt32(height))
        let slice = slice ?? (0, 0, width, height)
        return [(1001, little(1) + little(UInt32(slice.x)) + little(UInt32(slice.y)) + little(UInt32(slice.width)) + little(UInt32(slice.height))),
                (1003, little(1) + [UInt8](repeating: 0, count: 16) + size)]
    }

    /// CSI flags: 0x10 for images without a rendering intent, 0x8 for `template`, 0 for
    /// `original` and app icons (`images` intents, tofu); 0x4 more for an image rasterized from a
    /// vector file and 0x100 for `preserves-vector-representation` (`images` svg cases).
    static func flags(_ source: Source) -> UInt32 {
        if source.kind == .symbol { return 0x4 }
        guard source.kind == .image else { return 0 }
        // `preserves-vector-representation` sets 0x100, on PNG images too (home-assistant).
        let vector: UInt32 = (source.rasterized ? 0x4 : 0) | (source.preservesVector ? 0x100 : 0)
        switch source.renderingIntent {
        case "template": return 0x8 | vector
        case "original": return vector
        default: return 0x10 | vector
        }
    }

    /// An SVG file's images at 1x, 2x and 3x of its size in points, rounded up (10.5 × 7.25 gives
    /// 11 × 8, 21 × 15, 32 × 22), the content drawn at its own size at the bottom left by nomac's
    /// renderer (ADR 0204); their slice is the content's size rounded half up, at the bottom
    /// (`images` svg cases: 10.25 × 7.75 at 3x gives 31 × 23 at y 1 in 31 × 24).
    /// An SVG file in the `slot` scale's entry is drawn at its size divided by that scale, at the
    /// bottom left of images of its full size (`vector-images` svg cases in scale entries).
    static func rasterized(_ asset: AssetCatalog.Asset, filename: String, renderingIntent: String?, preservesVector: Bool, slot: Int = 1,
                           scales: [Int] = [1, 2, 3]) throws -> [Source] {
        let path = asset.path + "/" + filename
        guard let data = FileManager.default.contents(atPath: path) else { throw NomacError("could not read the image", path: path) }
        let svg = try SVGImage(data: data, path: path)
        // The vector rendition goes with the first raster (watchOS rasterizes at 2x only).
        return try scales.map { scale in
            let content = (width: svg.width * Double(scale) / Double(slot), height: svg.height * Double(scale) / Double(slot))
            let width = Int((svg.width * Double(scale)).rounded(.up)), height = Int((svg.height * Double(scale)).rounded(.up))
            let pixels = IconRenderer.bgra(try IconRenderer.draw(.svg(svg, data: [UInt8](data)), width: width, height: height, content: content))
            var source = Source(name: asset.name, filename: filename, path: path, image: PNGImage(width: width, height: height, pixels: pixels), scale: scale)
            let sliceHeight = Int(content.height.rounded(.toNearestOrAwayFromZero))
            source.slice = (0, height - sliceHeight, Int(content.width.rounded(.toNearestOrAwayFromZero)), sliceHeight)
            source.renderingIntent = renderingIntent
            source.rasterized = true
            // Rasterized images are never opaque (a 12.5-point square fills its 25 × 25 2x image
            // and is packed with translucent images, `images` svg cases).
            source.isOpaque = false
            source.preservesVector = preservesVector
            source.vectorScale = UInt16(slot)
            if scale == scales[0] { source.vectorData = [UInt8](data) }
            return source
        }
    }

    /// A vector file's rendition: part 181 without a scale, or with `preserves-vector-representation`
    /// part 42 with the scale of the file's entry (1 without one); flags 4, no size, the file in a `DWAR` payload: an SVG's compressed
    /// when that is smaller, a PDF's as it is (docs/formats/asset-catalog.md, "SVG images", "PDF images").
    static func vectorRendition(_ source: Source, data: [UInt8], pixelFormat: String, colorModel: UInt32 = 0) -> CARRendition {
        let csi = CSI(name: source.filename, layout: .vector, flags: 4, colorModel: colorModel, pixelFormat: pixelFormat,
                      properties: commonProperties, payload: vectorPayload(data, compressed: pixelFormat != "PDF "))
        var attributes: [RenditionAttribute: UInt16] = source.preservesVector ? [.scale: source.vectorScale, .part: 42] : [:]
        if source.appearance != 0 { attributes[.appearance] = source.appearance }
        return CARRendition(name: source.name, kind: source.kind, attributes: attributes, csi: csi.bytes)
    }

    static func vectorPayload(_ data: [UInt8], compressed allowed: Bool = true) -> [UInt8] {
        let compressed = allowed ? LZFSE.encode(data, encoder: .libcompression) : data
        var payload = ByteWriter()
        payload.append(Array("DWAR".utf8))
        payload.appendLE(UInt32(compressed.count < data.count ? 1 : 0))
        payload.appendLE(UInt32(min(compressed.count, data.count)))
        payload.append(compressed.count < data.count ? compressed : data)
        return payload.bytes
    }

    /// deepmap2, or for app icons and their atlases the payload without it.
    static func payload(_ pixels: [UInt8], gray: Bool, width: Int, height: Int, opaque: Bool, plain: Bool) throws -> [UInt8] {
        let format = format(gray: gray).deepmap
        if plain {
            return PlainImagePayload.payload(pixels, format: format, width: width, height: height, opaque: opaque)
        }
        return try Deepmap2.payload(pixels, format: format, width: width, height: height, opaque: opaque)
    }

    /// An image's CSI; `wide`, its display-gamut-1 rendition's: `RGBW`, color model 4.
    static func imageCSI(_ source: Source, layout: CSI.Layout, properties: [(type: UInt32, value: [UInt8])], payload: [UInt8], wide: Bool = false) -> CSI {
        let format = wide ? (pixelFormat: "RGBW", colorModel: UInt32(4), deepmap: Deepmap2.Format.rgbaHalf) : format(gray: source.isGray)
        return CSI(name: source.filename, layout: layout, flags: flags(source), width: UInt32(source.image.width), height: UInt32(source.image.height),
                   colorModel: format.colorModel, scale: UInt32(100 * source.scale), pixelFormat: format.pixelFormat, properties: properties,
                   payload: payload)
    }

    /// Images of at most `Atlas.areaLimit(scale:)` pixels make a class packable when there are
    /// two or more of them; its images below the limit are packed, even a single one
    /// (`images`, scale-limit cases).
    static func renditions(_ sources: [Source], identifiers: [String: UInt16]) throws -> [CARRendition] {
        func area(_ source: Source) -> Int { source.image.width * source.image.height }
        func packing(_ indices: [Int], gamut: UInt16) -> [PackingClass: [Int]] {
            let candidates = indices.filter { sources[$0].jpeg == nil && sources[$0].heif == nil && area(sources[$0]) <= Atlas.areaLimit(scale: sources[$0].scale) }
            return Dictionary(grouping: candidates) { index -> PackingClass in
                var packingClass = sources[index].packingClass
                packingClass.gamut = gamut
                return packingClass
            }
            .filter { $0.value.count > 1 }
            .mapValues { $0.filter { area(sources[$0]) < Atlas.areaLimit(scale: sources[$0].scale) } }
            .filter { !$0.value.isEmpty }
        }
        // An image with colors well outside sRGB also gets a rendition in extended sRGB for
        // display gamut 1, packed by the same rules in atlases of its own (B-213, `profiles`).
        let wideIndices = sources.indices.filter { sources[$0].jpeg == nil && sources[$0].image.widePixels != nil }
        let packable = packing(Array(sources.indices), gamut: 0), widePackable = packing(wideIndices, gamut: 1)
        let packed = Set(packable.values.joined()), widePacked = Set(widePackable.values.joined())
        var renditions: [CARRendition] = []
        // An Icon Composer icon's rendered image is stored once per idiom, with the same pixels.
        var payloads: [(pixels: [UInt8], gray: Bool, opaque: Bool, plain: Bool, payload: [UInt8])] = []
        for source in sources {
            if let data = source.vectorData {
                renditions.append(vectorRendition(source, data: data, pixelFormat: source.filename.lowercased().hasSuffix(".pdf") ? "PDF " : "SVG "))
            }
        }
        for (index, source) in sources.enumerated() where !packed.contains(index) {
            if let jpeg = source.jpeg {
                renditions.append(jpegRendition(source, jpeg))
                continue
            }
            if let heif = source.heif {
                renditions += heicRenditions(source, heif)
                continue
            }
            let image = source.image
            let plain = source.kind == .appIcon
            // A rasterized image stored alone is stored as opaque when all its pixels are, though its
            // flags and packing class stay translucent (`vector-images` opaque cases).
            let opaque = source.isOpaque || source.rasterized && stride(from: 3, to: image.pixels.count, by: 4).allSatisfy { image.pixels[$0] == 255 }
            let rowBytes = rowBytes(width: image.width, opaque: opaque, gray: source.isGray, plain: plain)
            let properties = geometry(width: image.width, height: image.height, slice: source.slice) + commonProperties + [(1007, little(rowBytes))]
            let pixels = stored(image.pixels, gray: source.isGray, opaque: opaque)
            let payload: [UInt8]
            if let earlier = payloads.first(where: { $0.gray == source.isGray && $0.opaque == opaque && $0.plain == plain && $0.pixels == pixels }) {
                payload = earlier.payload
            } else {
                payload = try self.payload(pixels, gray: source.isGray, width: image.width, height: image.height, opaque: opaque, plain: plain)
                payloads.append((pixels, source.isGray, opaque, plain, payload))
            }
            // A symbol set's raster stored alone has layout 0 (home-assistant's watch app).
            let csi = imageCSI(source, layout: source.kind == .symbol ? .none : .image, properties: properties, payload: payload)
            renditions.append(CARRendition(name: source.name, kind: source.kind, attributes: source.attributes, csi: csi.bytes))
        }
        for index in wideIndices where !widePacked.contains(index) {
            let source = sources[index], image = source.image, wide = image.widePixels!, plain = source.kind == .appIcon
            let properties = geometry(width: image.width, height: image.height, slice: source.slice) + commonProperties
                + [(1007, little(UInt32((image.width * 8 + 31) / 32 * 32)))]
            let payload = plain ? PlainImagePayload.payload(wide, format: .rgbaHalf, width: image.width, height: image.height, opaque: source.isOpaque)
                : try Deepmap2.payload(wide, format: .rgbaHalf, width: image.width, height: image.height, opaque: source.isOpaque)
            let csi = imageCSI(source, layout: .image, properties: properties, payload: payload, wide: true)
            renditions.append(CARRendition(name: source.name, kind: source.kind, attributes: source.attributes(gamut: 1), csi: csi.bytes))
        }
        var numbers: [[Int]: UInt16] = [:]
        for (packingClass, members) in (packable.merging(widePackable) { first, _ in first }).sorted(by: { $0.key < $1.key }) {
            let items = members.map {
                Atlas.Item(id: $0, width: sources[$0].image.width, height: sources[$0].image.height, identifier: identifiers[sources[$0].name] ?? 0)
            }
            // actool numbers a class's atlases in the order of their indices as decimal strings
            // ("0", "1", "10", "11", "2", ...; flappy-fly-bird, `packing` many-atlases cases).
            let atlases = Atlas.split(items, scale: packingClass.scale)
            for index in atlases.indices.sorted(by: { String($0).utf8.lexicographicallyPrecedes(String($1).utf8) }) {
                let group = [packingClass.scale, Int(packingClass.idiom), Int(packingClass.subtype), Int(packingClass.gamut), Int(packingClass.appearance)]
                renditions += try atlas(atlases[index], sources: sources, number: numbers[group, default: 0], packingClass: packingClass)
                numbers[group, default: 0] += 1
            }
        }
        return renditions
    }

    /// A JPEG's rendition: no size in the header, its size in the slices and metrics, the file in a
    /// `DWAR` payload (`images` jpeg cases).
    static func jpegRendition(_ source: Source, _ jpeg: JPEGFile) -> CARRendition {
        var payload = ByteWriter()
        payload.append(Array("DWAR".utf8))
        payload.appendLE(UInt32(0))
        payload.appendLE(UInt32(jpeg.stored.count))
        payload.append(jpeg.stored)
        let csi = CSI(name: source.filename, layout: .image, flags: flags(source), scale: UInt32(100 * source.scale), pixelFormat: "JPEG",
                      properties: geometry(width: jpeg.width, height: jpeg.height) + commonProperties, payload: payload.bytes)
        return CARRendition(name: source.name, kind: source.kind, attributes: source.attributes, csi: csi.bytes)
    }

    /// A HEIC entry's renditions (`heic` experiment), never packed: its decoded pixels, and for
    /// target 2 the file as ImageIO writes it again, pixel format `HEIF`, no size in the header,
    /// in a `DWAR` payload. Both have the image's size in their slices and metrics. Opaque pixels
    /// are stored as `RGB5` (1-5-5-5) in the plain payload, rows padded to 32 bytes and stored as
    /// they are below 4,096 bytes; pixels with alpha as premultiplied `ARGB`, in a `jpeg-lzfse`
    /// payload when it takes less than a byte per pixel, else in the plain payload.
    static func heicRenditions(_ source: Source, _ heif: [UInt8]) -> [CARRendition] {
        let image = source.image
        let decoded: CSI
        if image.declaresAlpha {
            let jpeg = jpegLZFSEPayload(image)
            let fits = jpeg.count - 16 < image.width * image.height
            let payload = fits ? jpeg : PlainImagePayload.payload(image.pixels, bytesPerPixel: 4, width: image.width, height: image.height, opaque: false)
            let rowBytes = fits ? image.width * 4 : (image.width * 4 + 31) / 32 * 32
            let properties = geometry(width: image.width, height: image.height) + commonProperties + [(1007, little(UInt32(rowBytes)))]
            decoded = CSI(name: source.filename, layout: .image, flags: flags(source), width: UInt32(image.width), height: UInt32(image.height),
                          colorModel: 1, scale: UInt32(100 * source.scale), pixelFormat: "ARGB", properties: properties, payload: payload)
        } else {
            let payload = PlainImagePayload.payload(HEICImage.rgb555(image.pixels), bytesPerPixel: 2, width: image.width, height: image.height, opaque: true,
                                                    runLengths: false)
            let properties = geometry(width: image.width, height: image.height) + commonProperties + [(1007, little(UInt32((image.width * 2 + 31) / 32 * 32)))]
            decoded = CSI(name: source.filename, layout: .image, flags: flags(source), width: UInt32(image.width), height: UInt32(image.height),
                          colorModel: 1, scale: UInt32(100 * source.scale), pixelFormat: "RGB5", properties: properties, payload: payload)
        }
        var file = ByteWriter()
        file.append(Array("DWAR".utf8))
        file.appendLE(UInt32(0))
        file.appendLE(UInt32(heif.count))
        file.append(heif)
        let stored = CSI(name: source.filename, layout: .image, flags: flags(source), scale: UInt32(100 * source.scale), pixelFormat: "HEIF",
                         properties: geometry(width: image.width, height: image.height) + commonProperties, payload: file.bytes)
        var attributes = source.attributes
        attributes[.target] = 2
        return [CARRendition(name: source.name, kind: source.kind, attributes: source.attributes, csi: decoded.bytes),
                CARRendition(name: source.name, kind: source.kind, attributes: attributes, csi: stored.bytes)]
    }

    /// actool's `CELM` compression 5 (`jpeg-lzfse`, `heic` experiment): two zero words, the alpha
    /// stream's length, the width and the JPEG's length, then the alpha plane as an LZFSE stream
    /// and the premultiplied colors as a JPEG.
    static func jpegLZFSEPayload(_ image: PNGImage) -> [UInt8] {
        let count = image.width * image.height
        var alpha = [UInt8](repeating: 0, count: count), rgb = [UInt8](repeating: 0, count: count * 3)
        for index in 0..<count {
            alpha[index] = image.pixels[index * 4 + 3]
            for channel in 0..<3 { rgb[index * 3 + channel] = image.pixels[index * 4 + 2 - channel] }
        }
        let stream = LZFSE.encodeStream(alpha)
        let jpeg = JPEGEncoder.encode(rgb: rgb, width: image.width, height: image.height)
        var out = ByteWriter()
        out.append(Array("MLEC".utf8))
        for value in [0, 5, 20 + stream.count + jpeg.count, 0, 0, stream.count, image.width, jpeg.count] { out.appendLE(UInt32(value)) }
        out.append(stream)
        out.append(jpeg)
        return out.bytes
    }

    /// An atlas rendition (no facet) and one link rendition per image, whose property 1010
    /// (`KLNI`) gives the image's place, y from the bottom, and the atlas's key.
    static func atlas(_ items: [Atlas.Item], sources: [Source], number: UInt16, packingClass: PackingClass) throws -> [CARRendition] {
        let (positions, width, height) = Atlas.layout(items)
        let wide = packingClass.gamut != 0
        let placed = items.map { item -> (pixels: [UInt8], width: Int, height: Int, x: Int, y: Int) in
            let image = sources[item.id].image
            return (wide ? image.widePixels! : image.pixels, image.width, image.height, positions[item.id]!.x, positions[item.id]!.y)
        }
        let pixels = Atlas.compose(width: width, height: height, images: placed, bytesPerPixel: wide ? 8 : 4)
        let name = packingClass.atlasName
        let format = wide ? (pixelFormat: "RGBW", colorModel: UInt32(4), deepmap: Deepmap2.Format.rgbaHalf) : format(gray: packingClass.gray)
        // App icons packed with images, as on watchOS, are stored as images (pocket-casts' watch catalog).
        let plain = items.allSatisfy { sources[$0.id].kind == .appIcon }
        let rowBytes = wide ? UInt32((width * 8 + 31) / 32 * 32) : rowBytes(width: width, opaque: packingClass.opaque, gray: packingClass.gray, plain: plain)
        let payload = wide ? try Deepmap2.payload(pixels, format: .rgbaHalf, width: width, height: height, opaque: packingClass.opaque)
            : try payload(stored(pixels, gray: packingClass.gray, opaque: packingClass.opaque), gray: packingClass.gray, width: width, height: height,
                          opaque: packingClass.opaque, plain: plain)
        let atlasCSI = CSI(name: name, layout: .atlas, width: UInt32(width), height: UInt32(height), colorModel: format.colorModel,
                           scale: UInt32(100 * packingClass.scale),
                           pixelFormat: format.pixelFormat,
                           properties: [(1001, little(1) + [UInt8](repeating: 0, count: 16))] + commonProperties + [(1007, little(rowBytes))],
                           payload: payload)
        // An atlas is keyed with its class's subtype (watch icons' case sizes, `watchos`).
        var attributes = attributes(scale: packingClass.scale, idiom: packingClass.idiom, subtype: packingClass.subtype)
        if number != 0 { attributes[.dimension1] = number }
        if packingClass.target != 0 { attributes[.target] = packingClass.target }
        if packingClass.appearance != 0 { attributes[.appearance] = packingClass.appearance }
        if wide { attributes[.displayGamut] = 1 }
        var renditions = [CARRendition(name: name, kind: .packedImage, attributes: attributes, csi: atlasCSI.bytes, hasFacet: false)]

        let key = keyBytes([(.element, FacetKind.packedImage.element), (.part, FacetKind.packedImage.part)] + attributes.map { ($0.key, $0.value) })
        for item in items {
            let source = sources[item.id]
            let position = positions[item.id]!
            let link = link(x: position.x, y: position.y, width: item.width, height: item.height, atlasKey: key, layout: source.kind == .symbol ? 0 : 12)
            let properties = geometry(width: item.width, height: item.height, slice: source.slice) + [(1010, link)] + commonProperties
            let csi = imageCSI(source, layout: .packedImage, properties: properties, payload: [], wide: wide)
            renditions.append(CARRendition(name: source.name, kind: source.kind, attributes: source.attributes(gamut: packingClass.gamut), csi: csi.bytes))
        }
        return renditions
    }

    /// A rendition key as property values store it: (attribute, value) pairs sorted by
    /// attribute, ending with (0, 0).
    /// A key's attributes by number, the appearance last (`pdf_experiments.py` appearances: an
    /// atlas link lists element, part, scale, then appearance).
    static func keyBytes(_ pairs: [(RenditionAttribute, UInt16)]) -> [UInt8] {
        var key = ByteWriter()
        func rank(_ attribute: RenditionAttribute) -> UInt32 { attribute == .appearance ? .max : UInt32(attribute.rawValue) }
        for (attribute, value) in pairs.sorted(by: { rank($0.0) < rank($1.0) }) {
            key.appendLE(attribute.rawValue)
            key.appendLE(value)
        }
        key.appendLE(UInt32(0))
        return key.bytes
    }

    /// Property 1010 (`KLNI`): an image's place in its atlas, y from the bottom, 12 (0 for a
    /// symbol set's image, `symbols-sets` cases), and the atlas's key.
    static func link(x: Int, y: Int, width: Int, height: Int, atlasKey: [UInt8], layout: UInt16 = 12) -> [UInt8] {
        var link = ByteWriter()
        link.append(Array("KLNI".utf8))
        for value in [0, x, y, width, height] { link.appendLE(UInt32(value)) }
        link.appendLE(layout)
        link.appendLE(UInt16(atlasKey.count))
        link.appendLE(UInt16(0))
        link.append(atlasKey)
        return link.bytes
    }
}
