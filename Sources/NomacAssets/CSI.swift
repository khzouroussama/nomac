/// A rendition's CSI ("CoreUI Structured Image") bytes: a 184-byte header, type-length-value
/// properties and the payload (docs/formats/asset-catalog.md, "CSI").
struct CSI {
    enum Layout: UInt16 {
        case none = 0
        case image = 12
        /// Resizable images by their `resizing` mode and center mode (`image-traits`).
        case threePartHorizontalTile = 20
        case threePartHorizontalStretch = 21
        case threePartVerticalTile = 23
        case threePartVerticalStretch = 24
        case ninePartTile = 30
        case ninePartStretch = 31
        case data = 1000
        /// An image packed into an atlas: no payload, a link property to its place.
        case packedImage = 1003
        case atlas = 1004
        case color = 1009
        case iconSizes = 1010
        case structuredImage = 1005
        /// An SVG file kept as it is (`DWAR`).
        case vector = 9
        /// Icon Composer icons' stacks, groups and gradients (`IconComposerIcon`).
        case iconStack = 1019
        case iconGroup = 1020
        case gradient = 1021
        /// A symbol set's glyph (`SymbolSet`).
        case symbolGlyph = 1017
    }

    var name: String
    var layout: Layout
    /// 0x10 for images.
    var flags: UInt32 = 0
    var width: UInt32 = 0
    var height: UInt32 = 0
    /// 1 for RGB images.
    var colorModel: UInt32 = 0
    /// The scale times 100 (0 for colors).
    var scale: UInt32 = 0
    /// Four characters stored as a little-endian number (`DATA` is written `ATAD`), or none.
    var pixelFormat: String?
    var properties: [(type: UInt32, value: [UInt8])]
    var payload: [UInt8]

    var bytes: [UInt8] {
        var properties = ByteWriter()
        for property in self.properties {
            properties.appendLE(property.type)
            properties.appendLE(UInt32(property.value.count))
            properties.append(property.value)
        }
        var out = ByteWriter()
        out.append(Array("ISTC".utf8))
        out.appendLE(UInt32(1))
        out.appendLE(flags)
        out.appendLE(width)
        out.appendLE(height)
        out.appendLE(scale)
        out.append(pixelFormat.map { Array($0.utf8.reversed()) } ?? [0, 0, 0, 0])
        out.appendLE(colorModel)
        out.appendLE(UInt32(0))
        out.appendLE(layout.rawValue)
        out.appendLE(UInt16(0))
        out.appendFixed(name, width: 128)
        out.appendLE(UInt32(properties.count))
        out.appendLE(UInt32(1))
        out.appendLE(UInt32(0))
        out.appendLE(UInt32(payload.count))
        out.append(properties.bytes)
        out.append(payload)
        return out.bytes
    }
}
