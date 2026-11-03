/// How actool packs small images into atlases (docs/formats/asset-catalog.md, "Images", "Packing").
enum Atlas {
    /// Images of fewer pixels than this are packed, larger ones get renditions of their own, and
    /// an atlas stops taking images once theirs reach it (bisected at 1x at heights 1, 2, 3, 16,
    /// 64 and 128, and at 2x and 3x: 36,099 pixels are packed at 2x, 36,100 are not). An image of
    /// exactly this many pixels still counts toward its class (`ImageSet.renditions`).
    static func areaLimit(scale: Int) -> Int { 18_050 * scale }

    struct Item {
        var id: Int
        var width: Int
        var height: Int
        var identifier: UInt16
    }

    /// The order actool places images in: largest area first, then by identifier.
    static func packingOrder(_ items: [Item]) -> [Item] {
        items.sorted { ($0.width * $0.height, $1.identifier) > ($1.width * $1.height, $0.identifier) }
    }

    /// The growing binary-tree packer over cells of the image size plus 2: each cell goes into the
    /// first free node, right part before upper part; when none fits, the bin grows by a strip.
    final class Packer {
        final class Node {
            let x, y, width, height: Int
            var used = false
            var right: Node?
            var up: Node?

            init(_ x: Int, _ y: Int, _ width: Int, _ height: Int) {
                (self.x, self.y, self.width, self.height) = (x, y, width, height)
            }
        }

        struct Rect {
            var x, y, width, height: Int

            func contains(_ other: Rect) -> Bool {
                x <= other.x && other.x + other.width <= x + width && y <= other.y && other.y + other.height <= y + height
            }
        }

        private(set) var root: Node?
        /// Each placed cell, in placement order.
        private(set) var cells: [Rect] = []
        /// Each growth: the index of the cell that caused it, and the strip it added.
        private(set) var growths: [(cell: Int, strip: Rect)] = []

        private func find(_ node: Node?, _ width: Int, _ height: Int) -> Node? {
            guard let node else { return nil }
            if node.used { return find(node.right, width, height) ?? find(node.up, width, height) }
            return width <= node.width && height <= node.height ? node : nil
        }

        /// Places an image; without `grow`, only into free space (false when there is none).
        @discardableResult
        func place(width imageWidth: Int, height imageHeight: Int, grow: Bool = true) -> Bool {
            let width = imageWidth + 2, height = imageHeight + 2
            let bin = root ?? Node(0, 0, width, height)
            root = bin
            var node = find(bin, width, height)
            if node == nil {
                guard grow else { return false }
                let canGrowUp = width <= bin.width, canGrowRight = height <= bin.height
                let shouldGrowRight = canGrowRight && bin.height >= bin.width + width
                let shouldGrowUp = canGrowUp && bin.width >= bin.height + height
                let top: Node
                if shouldGrowRight || (!shouldGrowUp && canGrowRight) {
                    top = Node(0, 0, bin.width + width, bin.height)
                    top.right = Node(bin.width, 0, width, bin.height)
                    top.up = bin
                    growths.append((cells.count, Rect(x: bin.width, y: 0, width: width, height: bin.height)))
                } else {
                    top = Node(0, 0, bin.width, bin.height + height)
                    top.up = Node(0, bin.height, bin.width, height)
                    top.right = bin
                    growths.append((cells.count, Rect(x: 0, y: bin.height, width: bin.width, height: height)))
                }
                top.used = true
                root = top
                node = find(top, width, height)
            }
            let placed = node!
            placed.used = true
            placed.up = Node(placed.x, placed.y + height, placed.width, placed.height - height)
            placed.right = Node(placed.x + width, placed.y, placed.width - width, height)
            cells.append(Rect(x: placed.x, y: placed.y, width: width, height: height))
            return true
        }
    }

    /// How many of `items` (in packing order) the next atlas takes: items while the image area
    /// already taken is below `limit`, the one reaching it included (c1); then,
    /// unless item c1 made the bin's last growth, k more items plus one when the next k fit the
    /// free space without growing, k counting the cells inside that growth's strip, plus one if
    /// item c1 is not inside it, plus one if it was the bin's only growth. 3,131 of 3,131 splits
    /// observed (fitted, not explained).
    static func takenCount(_ items: [Item], limit: Int) -> Int {
        var area = 0, first = items.count
        for (index, item) in items.enumerated() {
            if index > 0 && area >= limit {
                first = index
                break
            }
            area += item.width * item.height
        }
        guard first < items.count else { return first }
        let packer = Packer()
        for item in items[..<first] { packer.place(width: item.width, height: item.height) }
        let (cause, strip) = packer.growths[packer.growths.count - 1]
        guard cause != first - 1 else { return first }
        var extra = packer.cells.filter { strip.contains($0) }.count
        if !strip.contains(packer.cells[first - 1]) { extra += 1 }
        if packer.growths.count == 1 { extra += 1 }
        guard items.count >= first + extra + 1 else { return first }
        for item in items[first..<first + extra] where !packer.place(width: item.width, height: item.height, grow: false) {
            return first
        }
        return first + extra + 1
    }

    /// The atlases of one class of images, each in packing order.
    static func split(_ items: [Item], scale: Int = 1) -> [[Item]] {
        var atlases: [[Item]] = []
        var rest = packingOrder(items)[...]
        while !rest.isEmpty {
            let count = takenCount(Array(rest), limit: areaLimit(scale: scale))
            atlases.append(Array(rest.prefix(count)))
            rest = rest.dropFirst(count)
        }
        return atlases
    }

    /// Positions (x, y from the bottom-left) of each image and the atlas size: what the images
    /// and their edge pixels need, the bin plus 1, rounded up to an even number (a bin of 27
    /// gives 28).
    static func layout(_ ordered: [Item]) -> (positions: [Int: (x: Int, y: Int)], width: Int, height: Int) {
        let packer = Packer()
        var positions: [Int: (x: Int, y: Int)] = [:]
        for item in ordered {
            packer.place(width: item.width, height: item.height)
            let cell = packer.cells[packer.cells.count - 1]
            positions[item.id] = (cell.x + 2, cell.y + 2)
        }
        return (positions, (packer.root!.width + 2) & ~1, (packer.root!.height + 2) & ~1)
    }

    /// The atlas's pixels, rows from the top: each image's pixels at its place, extended by its
    /// edge pixels one pixel on every side, and zeros elsewhere.
    static func compose(width: Int, height: Int, images: [(pixels: [UInt8], width: Int, height: Int, x: Int, y: Int)], bytesPerPixel: Int = 4) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        for image in images {
            let top = height - image.y - image.height
            for row in -1...image.height {
                let sourceRow = min(max(row, 0), image.height - 1)
                for column in -1...image.width {
                    let sourceColumn = min(max(column, 0), image.width - 1)
                    let source = (sourceRow * image.width + sourceColumn) * bytesPerPixel
                    let target = ((top + row) * width + image.x + column) * bytesPerPixel
                    pixels.replaceSubrange(target..<target + bytesPerPixel, with: image.pixels[source..<source + bytesPerPixel])
                }
            }
        }
        return pixels
    }
}
