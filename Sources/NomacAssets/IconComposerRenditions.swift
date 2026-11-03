import Foundation
import NomacCore
import NomacPlist

extension IconComposerIcon {
    struct Compiled {
        var renditions: [CARRendition]
        var sources: [ImageSet.Source]
        /// The icon PNGs written next to `Assets.car`, by file name.
        var pngs: [(filename: String, image: PNGImage)]
        var infoPlist: [String: PropertyListValue]
    }

    /// The fill's colors and gradients, named in the order actool creates them: white first, the
    /// icon's light fill, its dark fill, then the layers' fills group by group and layer by layer
    /// in `icon.json`'s order, each value once (`icons` colors cases).
    struct Paints {
        var colors = [IconColor(space: 6, components: [1, 1])]
        var gradients: [(paint: Paint, name: String, gradient: Gradient)] = []

        mutating func color(_ color: IconColor) -> String {
            if let index = colors.firstIndex(of: color) { return "Color-\(index + 1)" }
            colors.append(color)
            return "Color-\(colors.count)"
        }

        /// The paint's name and part; system gradients count among the gradients' numbers.
        mutating func register(_ paint: Paint) -> (name: String, part: UInt16) {
            guard let gradient = paint.gradient else {
                guard case .color(let value) = paint else { preconditionFailure("a paint is a color or a gradient") }
                return (color(value), FacetKind.color.part)
            }
            for stop in gradient.stops { _ = color(stop) }
            if let existing = gradients.first(where: { $0.paint == paint }) { return (existing.name, FacetKind.gradient.part) }
            let name = paint == .systemLight ? "system-light" : paint == .systemDark ? "system-dark" : "Gradient-\(gradients.count + 1)"
            gradients.append((paint, name, gradient))
            return (name, FacetKind.gradient.part)
        }
    }

    func paints() -> Paints {
        var paints = Paints()
        _ = paints.register(fill.light)
        _ = paints.register(fill.dark)
        for group in groups {
            for layer in group.layers {
                for appearance in Appearance.allCases {
                    if let paint = layerPaint(layer, appearance) { _ = paints.register(paint) }
                }
            }
        }
        return paints
    }

    /// Every facet name the icon adds, for the identifiers.
    var facetNames: [String] {
        let paints = paints()
        return [name] + groups.map(groupName) + images.map { imageName($0.file) }
            + paints.colors.indices.map { "\(name)_Assets/Color-\($0 + 1)" } + paints.gradients.map { "\(name)_Assets/\($0.name)" }
    }

    /// The renditions in `Assets.car`, the images packed or stored like other images, and for the
    /// icon `--app-icon` names its PNGs and partial Info.plist keys.
    func compile(identifiers: [String: UInt16], appIcon: Bool, alternates: [String] = [], targetDevices: [String]) throws -> Compiled {
        var paints = paints()
        var renditions: [CARRendition] = []
        let common: [(type: UInt32, value: [UInt8])] = [(1004, [UInt8](repeating: 0, count: 8)), (1006, ImageSet.little(1))]
        for (index, color) in paints.colors.enumerated() {
            let name = "\(self.name)_Assets/Color-\(index + 1)"
            renditions.append(CARRendition(name: name, kind: .color, attributes: [.scale: 1],
                                           csi: CSI(name: name, layout: .color, properties: common, payload: Self.colorPayload(color)).bytes))
        }
        for gradient in paints.gradients {
            let name = "\(self.name)_Assets/\(gradient.name)"
            var payload = ByteWriter()
            payload.append(Array("ARGG".utf8))
            payload.appendLE(UInt32(gradient.gradient.stops.count))
            payload.appendLE(UInt32(gradient.gradient.automatic ? 0 : 1))
            for value in [0] + gradient.gradient.orientation { payload.appendLE(Float(value).bitPattern) }
            for (index, stop) in gradient.gradient.stops.enumerated() {
                payload.appendLE(Float(gradient.gradient.stops.count == 1 ? 0 : Double(index) / Double(gradient.gradient.stops.count - 1)).bitPattern)
                Self.appendString(&payload, "\(self.name)_Assets/" + paints.color(stop))
            }
            renditions.append(CARRendition(name: name, kind: .gradient, attributes: [.scale: 1],
                                           csi: CSI(name: name, layout: .gradient, properties: common, payload: payload.bytes).bytes))
        }

        let shapeProperties: [(type: UInt32, value: [UInt8])] = [(1004, ImageSet.little(0) + ImageSet.little(0x3F80_0000))]
        let empty = Array("DWAR".utf8) + [UInt8](repeating: 0, count: 8)
        func key(_ part: UInt16, _ name: String) -> [UInt8] {
            ImageSet.keyBytes([(.element, 85), (.part, part), (.identifier, identifiers[name] ?? 0)])
        }
        for appearance in [Appearance.dark, .light, .tinted] {
            let fillPaint = appearance == .dark ? fill.dark : fill.light
            let fillReference = paints.register(fillPaint)
            let reversed = groups.reversed().map { (group: $0, style: $0.style[appearance]!) }
            let stackLayers = [Self.layerEntry(rect: (0, 0, 0, 0), blend: 0, opacity: 1, key: key(fillReference.part, "\(name)_Assets/\(fillReference.name)"))]
                + reversed.map { Self.layerEntry(rect: (0, 0, 0, 0), blend: $0.style.blendMode, opacity: $0.style.hidden ? 0 : $0.style.opacity, key: key(FacetKind.iconGroup.part, groupName($0.group))) }
            let stackStyles = [(UInt32(0), 0.0, "")] + reversed.map { ($0.style.lighting, $0.style.blurMaterial, "") }
            let stackEffects = [[UInt32(0), 0, 0, 0, 0]] + reversed.map { item in
                [item.style.specular ? 1 : 0, Float(item.style.translucency).bitPattern, item.style.shadowKind, Float(item.style.shadowOpacity).bitPattern, 0]
            }
            let stack = CSI(
                name: name + ".iconstack", layout: .iconStack, width: 1024, height: 1024, scale: 100, pixelFormat: "DATA",
                properties: [(1012, Self.list(stackLayers)), (1020, Self.styles(stackStyles)), (1021, Self.list(stackEffects.map(Self.words))),
                             (1022, Self.list(Array(repeating: [UInt8](repeating: 0, count: 12), count: stackLayers.count)))]
                    + shapeProperties + [(1005, ImageSet.little(20) + ImageSet.little(0) + Array("public.layeredimage".utf8) + [0]), (1006, ImageSet.little(1))],
                payload: empty)
            renditions.append(CARRendition(name: name, kind: .appIcon, attributes: [.scale: 1, .appearance: appearance.stackAppearance.rawValue, .part: 245], csi: stack.bytes))

            for group in groups {
                let layers = Array(group.layers.reversed())
                let entries = layers.map { layer -> [UInt8] in
                    let style = layer.style[appearance]!
                    return Self.layerEntry(rect: rect(layer, in: group, appearance), blend: style.blendMode, opacity: style.hidden ? 0 : style.opacity,
                                           key: key(FacetKind.image.part, imageName(layer.file)))
                }
                // A layer hidden in this appearance, or in a group hidden in it, has no glass (V12, P12).
                let styles = layers.map { layer -> (UInt32, Double, String) in
                    let reference = layerPaint(layer, appearance).map { "\(name)_Assets/" + paints.register($0).name } ?? ""
                    let style = layer.style[appearance]!
                    return (style.glass && !style.hidden && !group.style[appearance]!.hidden ? 1 : 0, 0, reference)
                }
                let groupCSI = CSI(
                    name: "IconGroup", layout: .iconGroup, scale: 100, pixelFormat: "DATA",
                    properties: [(1012, Self.list(entries)), (1020, Self.styles(styles)),
                                 (1021, Self.list(Array(repeating: [UInt8](repeating: 0, count: 20), count: layers.count))),
                                 (1022, Self.list(Array(repeating: [UInt8](repeating: 0, count: 12), count: layers.count)))]
                        + shapeProperties + [(1006, ImageSet.little(1))],
                    payload: empty)
                renditions.append(CARRendition(name: groupName(group), kind: .iconGroup, attributes: [.scale: 1, .appearance: appearance.stackAppearance.rawValue], csi: groupCSI.bytes))
            }
        }

        var sources: [ImageSet.Source] = []
        for (file, image) in images {
            switch image {
            case .svg(_, let data):
                // Color model 3 when untagged SVG colors are Display P3 (signal's icons).
                let csi = CSI(name: "image.svg", layout: .vector, flags: 4, colorModel: untaggedSVGColorsInDisplayP3 ? 3 : 0, pixelFormat: "SVG ",
                              properties: shapeProperties + [(1006, ImageSet.little(1))], payload: ImageSet.vectorPayload(data))
                renditions.append(CARRendition(name: imageName(file), kind: .image, attributes: [.scale: 1], csi: csi.bytes))
            case .png(let png, let path):
                // A layer image is opaque when its PNG has no alpha channel and no tRNS, whatever
                // its pixels (home-assistant's opaque RGBA dev icon is not, signal's palette is).
                var source = ImageSet.Source(name: imageName(file), filename: "image.png", path: path, image: png)
                source.isOpaque = !png.declaresAlpha
                sources.append(source)
            }
        }

        for idiom in [Idiom.phone, Idiom.pad] {
            renditions.append(AppIconSet.sizeTable(name, idiom: idiom, sizes: [(1024, 1)]))
        }
        var rendered: [RenditionAppearance: PNGImage] = [:]
        for (appearance, imageAppearance) in [(Appearance.light, RenditionAppearance.any), (.dark, .dark), (.tinted, .tintable)] {
            let image = PNGImage(width: 1024, height: 1024, pixels: try IconRenderer.render(self, appearance: appearance))
            rendered[imageAppearance] = image
            let filename = name + "1024x1024_" + imageAppearance.name + "_" + renderedSuffix(imageAppearance) + ".png"
            for idiom in [Idiom.phone, Idiom.pad] {
                var source = ImageSet.Source(name: name, filename: filename, path: path, image: image, idiom: idiom)
                source.kind = .appIcon
                source.dimension2 = 1
                source.appearance = imageAppearance.rawValue
                // Rendered images are stored in color even when gray (expo-default's tinted one).
                source.isGray = false
                sources.append(source)
            }
        }

        guard appIcon else { return Compiled(renditions: renditions, sources: sources, pngs: [], infoPlist: [:]) }
        let any = rendered[.any]!
        let pngs = [(name + "60x60@2x.png", 120), (name + "76x76@2x~ipad.png", 152)].map { filename, size in
            var image = PNGImage(width: size, height: size, pixels: IconRenderer.downsample(any.pixels, from: 1024, to: size))
            image.ancillaryChunks = [PNGImage.Chunk(type: "sRGB", data: [0]), PNGImage.Chunk(type: "eXIf", data: Self.exif(width: size, height: size))]
            return (filename, image)
        }
        // The icon's name and the alternate icons are in the keys of the devices the build targets,
        // both without `--target-device` (expo-default's icon compiled for iphone, ipad, both and
        // none; `alternate-icons` cases).
        func icons(_ files: [String], named: Bool) -> PropertyListValue {
            var primary: [String: PropertyListValue] = ["CFBundleIconFiles": .array(files.map { .string($0) })]
            var keys: [String: PropertyListValue] = [:]
            if named {
                primary["CFBundleIconName"] = .string(name)
                if !alternates.isEmpty {
                    keys["CFBundleAlternateIcons"] = .dictionary(Dictionary(uniqueKeysWithValues: alternates.map { ($0, .dictionary(["CFBundleIconName": .string($0)])) }))
                }
            }
            keys["CFBundlePrimaryIcon"] = .dictionary(primary)
            return .dictionary(keys)
        }
        let all = targetDevices.isEmpty
        let infoPlist: [String: PropertyListValue] = [
            "CFBundleIcons": icons([name + "60x60"], named: all || targetDevices.contains("iphone")),
            "CFBundleIcons~ipad": icons([name + "60x60", name + "76x76"], named: all || targetDevices.contains("ipad")),
        ]
        return Compiled(renditions: renditions, sources: sources, pngs: pngs, infoPlist: infoPlist)
    }

    /// actool ends a rendered image's name with a UUID, its process number and a time, which
    /// change from run to run (ADR 0203); nomac derives values of the same form from the icon's
    /// files, so that its output does not change.
    func renderedSuffix(_ appearance: RenditionAppearance) -> String {
        var input = Array(appearance.name.utf8)
        input += Array((try? Data(contentsOf: URL(fileURLWithPath: path + "/icon.json"))) ?? Data())
        for (file, _) in images { input += Array(file.utf8) + Array((try? Data(contentsOf: URL(fileURLWithPath: path + "/Assets/" + file))) ?? Data()) }
        let digest = SHA256.digest(input)
        let hex = digest.map { String(format: "%02X", $0) }.joined()
        let uuid = [hex.prefix(8), hex.dropFirst(8).prefix(4), hex.dropFirst(12).prefix(4), hex.dropFirst(16).prefix(4), hex.dropFirst(20).prefix(12)].joined(separator: "-")
        let process = 10_000 + (Int(digest[16]) << 8 | Int(digest[17])) % 90_000
        return "\(uuid)-\(process)-\(hex.dropFirst(36).prefix(16))"
    }

    static func colorPayload(_ color: IconColor) -> [UInt8] {
        var out = ByteWriter()
        out.append(Array("RLOC".utf8))
        out.appendLE(UInt32(1))
        out.appendLE(color.space)
        out.appendLE(UInt32(color.components.count))
        for component in color.components { out.appendLE(component) }
        return out.bytes
    }

    static func appendString(_ out: inout ByteWriter, _ text: String) {
        out.appendLE(UInt32(text.utf8.count + 1))
        out.append(Array(text.utf8) + [0])
    }

    /// A list property (1012, 1020, 1021, 1022): its count, 0, then its entries.
    static func list(_ entries: [[UInt8]]) -> [UInt8] {
        ImageSet.little(UInt32(entries.count)) + ImageSet.little(0) + entries.flatMap { $0 }
    }

    static func words(_ values: [UInt32]) -> [UInt8] { values.flatMap(ImageSet.little) }

    /// Property 1020's entries: a number, a value and the name of a paint, or nothing.
    static func styles(_ entries: [(UInt32, Double, String)]) -> [UInt8] {
        list(entries.map { kind, value, reference in
            var out = ByteWriter()
            out.appendLE(kind)
            out.appendLE(Float(value).bitPattern)
            appendString(&out, reference)
            return out.bytes
        })
    }

    /// Property 1012's entries: 0, the layer's place, its blend mode and opacity, then the key of
    /// the rendition it draws.
    static func layerEntry(rect: (x: Int, y: Int, width: Int, height: Int), blend: UInt32, opacity: Double, key: [UInt8]) -> [UInt8] {
        var out = ByteWriter()
        out.appendLE(UInt32(0))
        out.appendLE(UInt32(bitPattern: Int32(rect.x)))
        out.appendLE(UInt32(bitPattern: Int32(rect.y)))
        out.appendLE(UInt32(rect.width))
        out.appendLE(UInt32(rect.height))
        out.appendLE(blend)
        out.appendLE(Float(opacity).bitPattern)
        out.appendLE(UInt32(key.count))
        out.append(key)
        return out.bytes
    }

    /// The icon PNGs' `eXIf`: a big-endian TIFF whose Exif directory gives the color space (sRGB)
    /// and the pixel width and height.
    static func exif(width: Int, height: Int) -> [UInt8] {
        var out: [UInt8] = Array("MM".utf8) + [0, 42] + IconPNG.bigEndian(8)
        func entry(_ tag: UInt16, _ type: UInt16, _ value: [UInt8]) {
            out += [UInt8(tag >> 8), UInt8(tag & 0xFF), UInt8(type >> 8), UInt8(type & 0xFF)] + IconPNG.bigEndian(1) + value
        }
        out += [0, 1]
        entry(0x8769, 4, IconPNG.bigEndian(26))
        out += IconPNG.bigEndian(0)
        out += [0, 3]
        entry(0xA001, 3, [0, 1, 0, 0])
        entry(0xA002, 4, IconPNG.bigEndian(UInt32(width)))
        entry(0xA003, 4, IconPNG.bigEndian(UInt32(height)))
        out += IconPNG.bigEndian(0)
        return out
    }
}
