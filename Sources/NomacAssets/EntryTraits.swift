import Foundation
import NomacCore

/// An image set entry's `language-direction`, `alignment-insets` and `resizing`, as actool applies
/// them to its images (`image-traits`; docs/formats/asset-catalog.md, "Entry traits").
struct EntryTraits {
    static let keys: Set<String> = ["language-direction", "alignment-insets", "resizing"]

    struct Insets {
        var left: Int, top: Int, right: Int, bottom: Int

        func metrics(width: Int, height: Int) -> [UInt8] {
            var out = ByteWriter()
            out.appendLE(UInt32(1))
            for value in [left, top, right, bottom, width - left - right, height - top - bottom] {
                out.appendLE(UInt32(bitPattern: Int32(value)))
            }
            return out.bytes
        }
    }

    struct Resizing {
        var horizontal: Bool, vertical: Bool
        var layout: CSI.Layout
        var left = 0, top = 0, right = 0, bottom = 0, centerWidth = 0, centerHeight = 0
    }

    /// What an image keeps of its `resizing`: the layout and the slices, row by row from the top,
    /// y from the bottom.
    struct Applied {
        var layout: CSI.Layout
        var slices: [(x: Int, y: Int, width: Int, height: Int)]

        var sliceProperty: [UInt8] {
            var out = ByteWriter()
            out.appendLE(UInt32(slices.count))
            for slice in slices {
                for value in [slice.x, slice.y, slice.width, slice.height] { out.appendLE(UInt32(value)) }
            }
            return out.bytes
        }
    }

    var direction: UInt16
    /// One language direction in the set, whichever: flag 0x40.
    var flippable: Bool
    var insets: Insets?
    var resizing: Resizing?

    var isEmpty: Bool { direction == 0 && insets == nil && resizing == nil }

    /// The key value of a `language-direction`: 5 left to right, 4 right to left.
    static func direction(_ entry: [String: Any]) -> UInt16 {
        switch entry["language-direction"] as? String {
        case "left-to-right": 5
        case "right-to-left": 4
        default: 0
        }
    }

    init(_ entry: [String: Any], allEntries: [[String: Any]], path: String) throws {
        direction = Self.direction(entry)
        if let value = entry["language-direction"], direction == 0 {
            throw NomacError("image set entries with the language direction '\(value)' are not supported yet (BACKLOG B-200)", path: path)
        }
        let directions = Set(allEntries.filter { $0["filename"] != nil }.map(Self.direction))
        // Entries with a direction beside one without it: actool keeps one of them (`png-three`).
        if directions.count > 1 && directions.contains(0) {
            throw NomacError("image sets with entries with and without a language direction are not supported yet (BACKLOG B-200)", path: path)
        }
        flippable = direction != 0 && directions.count == 1
        if let value = entry["alignment-insets"] {
            guard let box = value as? [String: Any], let left = box["left"] as? Int, let top = box["top"] as? Int, let right = box["right"] as? Int,
                  let bottom = box["bottom"] as? Int else {
                throw NomacError("image set entries with alignment insets other than whole numbers are not supported yet (BACKLOG B-200)", path: path)
            }
            insets = Insets(left: left, top: top, right: right, bottom: bottom)
        }
        if let value = entry["resizing"] {
            resizing = try Self.resizing(value, path: path)
        }
    }

    private static func resizing(_ value: Any, path: String) throws -> Resizing {
        let unsupported = NomacError("image set entries with this resizing are not supported yet (BACKLOG B-200)", path: path)
        guard let box = value as? [String: Any], let center = box["center"] as? [String: Any], let caps = box["cap-insets"] as? [String: Any] else { throw unsupported }
        let tile = center["mode"] as? String == "tile"
        guard tile || center["mode"] as? String == "stretch" else { throw unsupported }
        var result: Resizing
        switch box["mode"] as? String {
        case "9-part": result = Resizing(horizontal: true, vertical: true, layout: tile ? .ninePartTile : .ninePartStretch)
        case "3-part-horizontal": result = Resizing(horizontal: true, vertical: false, layout: tile ? .threePartHorizontalTile : .threePartHorizontalStretch)
        case "3-part-vertical": result = Resizing(horizontal: false, vertical: true, layout: tile ? .threePartVerticalTile : .threePartVerticalStretch)
        default: throw unsupported
        }
        func whole(_ box: [String: Any], _ key: String) throws -> Int {
            guard let number = box[key] as? Int else { throw unsupported }
            return number
        }
        if result.horizontal {
            (result.left, result.right, result.centerWidth) = (try whole(caps, "left"), try whole(caps, "right"), try whole(center, "width"))
        }
        if result.vertical {
            (result.top, result.bottom, result.centerHeight) = (try whole(caps, "top"), try whole(caps, "bottom"), try whole(center, "height"))
        }
        return result
    }

    /// Applies the traits to an image: `factor` pixels per unit, the scale of an image rasterized
    /// from a vector file and 1 for a file's pixels.
    func apply(to source: inout ImageSet.Source, factor: Int, path: String) throws {
        source.direction = direction
        source.flippable = flippable
        if let insets {
            source.insets = Insets(left: insets.left * factor, top: insets.top * factor, right: insets.right * factor, bottom: insets.bottom * factor)
        }
        if let resizing {
            guard source.image.widePixels == nil else {
                throw NomacError("resizable images in a wide color gamut are not supported yet (BACKLOG B-200)", path: path)
            }
            guard source.slice == nil || source.slice?.width == source.image.width && source.slice?.height == source.image.height else {
                throw NomacError("resizable images rasterized from a vector file of a fractional size are not supported yet (BACKLOG B-200)", path: path)
            }
            try crop(&source, resizing, factor: factor, path: path)
        }
    }

    /// actool keeps the caps and `center` pixels of the center's start, and writes those as the
    /// image (`png-9part`, `png-9part-center`).
    private func crop(_ source: inout ImageSet.Source, _ resizing: Resizing, factor: Int, path: String) throws {
        let image = source.image
        let left = resizing.left * factor, right = resizing.right * factor, top = resizing.top * factor, bottom = resizing.bottom * factor
        let centerWidth = resizing.centerWidth * factor, centerHeight = resizing.centerHeight * factor
        let width = resizing.horizontal ? left + centerWidth + right : image.width
        let height = resizing.vertical ? top + centerHeight + bottom : image.height
        guard width <= image.width, height <= image.height else {
            throw NomacError("image set entries whose resizing is larger than the image are not supported yet (BACKLOG B-200)", path: path)
        }
        let columns = Array(0..<(left + centerWidth)) + Array((image.width - right)..<image.width)
        let rows = Array(0..<(top + centerHeight)) + Array((image.height - bottom)..<image.height)
        var pixels: [UInt8] = []
        pixels.reserveCapacity(width * height * 4)
        for row in resizing.vertical ? rows : Array(0..<image.height) {
            for column in resizing.horizontal ? columns : Array(0..<image.width) {
                let offset = (row * image.width + column) * 4
                pixels += image.pixels[offset..<offset + 4]
            }
        }
        let cropped = PNGImage(width: width, height: height, pixels: pixels)
        source.image = cropped
        if !source.rasterized { source.isOpaque = cropped.isOpaque }
        source.isGray = ImageSet.isGray(pixels)
        source.slice = nil
        let xs = resizing.horizontal ? [(0, left), (left, centerWidth), (left + centerWidth, right)] : [(0, width)]
        let ys = resizing.vertical ? [(bottom + centerHeight, top), (bottom, centerHeight), (0, bottom)] : [(0, height)]
        source.resizing = Applied(layout: resizing.layout, slices: ys.flatMap { y in xs.map { (x: $0.0, y: y.0, width: $0.1, height: y.1) } })
    }
}
