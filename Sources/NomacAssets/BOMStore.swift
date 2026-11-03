import NomacCore

/// Writes a BOM store, the container format of `Assets.car` (docs/formats/asset-catalog.md,
/// "BOM container"). Blocks are numbered in the order they are added, which is the order
/// actool creates them, and laid out in that order when the store is serialized; a freed block
/// (assetutil's thinning) keeps its number and is not written.
struct BOMStoreWriter {
    private(set) var blocks: [[UInt8]?] = [[]]
    private(set) var variables: [(name: String, block: UInt32)] = []

    init() {}

    /// A store read back: its blocks by number, nil for a freed one, and its variables.
    init(bytes: [UInt8], path: String) throws {
        func be32(_ at: Int) throws -> Int {
            guard at >= 0, at + 4 <= bytes.count else { throw NomacError("truncated BOM store", path: path) }
            return Int(bytes[at]) << 24 | Int(bytes[at + 1]) << 16 | Int(bytes[at + 2]) << 8 | Int(bytes[at + 3])
        }
        guard bytes.count >= Self.headerSize, bytes.starts(with: Array("BOMStore".utf8)), try be32(8) == 1 else {
            throw NomacError("not a BOM store", path: path)
        }
        let highest = try be32(12), index = try be32(16), variablesOffset = try be32(24)
        guard try be32(index) > highest else { throw NomacError("malformed BOM index", path: path) }
        blocks = try (0...highest).map { number in
            let address = try be32(index + 4 + 8 * number), length = try be32(index + 8 + 8 * number)
            if address == 0xFFFF_FFFF { return nil }
            guard address + length <= bytes.count else { throw NomacError("truncated BOM store", path: path) }
            return Array(bytes[address..<(address + length)])
        }
        var at = variablesOffset + 4
        for _ in 0..<(try be32(variablesOffset)) {
            let block = UInt32(try be32(at))
            let length = Int(bytes[at + 4])
            guard at + 5 + length <= bytes.count else { throw NomacError("truncated BOM variables", path: path) }
            variables.append((String(decoding: bytes[(at + 5)..<(at + 5 + length)], as: UTF8.self), block))
            at += 5 + length
        }
    }

    func block(_ index: UInt32) -> [UInt8]? {
        Int(index) < blocks.count ? blocks[Int(index)] : nil
    }

    func variable(_ name: String) -> UInt32? {
        variables.first { $0.name == name }?.block
    }

    mutating func free(_ index: UInt32) {
        blocks[Int(index)] = nil
    }

    mutating func setVariable(_ name: String, block: UInt32) {
        if let position = variables.firstIndex(where: { $0.name == name }) { variables[position].block = block } else { addVariable(name, block: block) }
    }

    /// Adds a block and returns its index.
    mutating func add(_ bytes: [UInt8]) -> UInt32 {
        blocks.append(bytes)
        return UInt32(blocks.count - 1)
    }

    /// Reserves a block whose content is set later with ``set(_:_:)``.
    mutating func reserve() -> UInt32 {
        add([])
    }

    mutating func set(_ index: UInt32, _ bytes: [UInt8]) {
        blocks[Int(index)] = bytes
    }

    /// Names a block. Variables are written in the order they are added.
    mutating func addVariable(_ name: String, block: UInt32) {
        variables.append((name, block))
    }

    /// The store's bytes: a 512-byte header, the blocks at 16-byte boundaries, the variables
    /// and the block index.
    func serialized() -> [UInt8] {
        var out = ByteWriter()
        out.appendZeros(Self.headerSize)
        var addresses: [(UInt32, UInt32)] = [(0, 0)]
        for block in blocks.dropFirst() {
            guard let block else {
                addresses.append((0xFFFF_FFFF, 0xFFFF_FFFF))
                continue
            }
            out.align(to: 16)
            addresses.append((UInt32(out.count), UInt32(block.count)))
            out.append(block)
        }
        out.align(to: 16)
        let variablesOffset = out.count
        out.appendBE(UInt32(variables.count))
        for variable in variables {
            out.appendBE(variable.block)
            let name = Array(variable.name.utf8)
            out.append([UInt8(name.count)])
            out.append(name)
        }
        let variablesLength = out.count - variablesOffset
        out.align(to: 16)
        let indexOffset = out.count
        let capacity = max(256, (addresses.count + 7) / 8 * 8)
        out.appendBE(UInt32(capacity))
        for slot in 0..<capacity {
            let (address, length) = slot < addresses.count ? addresses[slot] : (0, 0)
            out.appendBE(address)
            out.appendBE(length)
        }
        // An empty free list followed by two empty entries.
        out.appendBE(UInt32(0))
        out.appendZeros(16)
        let indexLength = out.count - indexOffset

        var bytes = out.bytes
        var header = ByteWriter()
        header.append(Array("BOMStore".utf8))
        header.appendBE(UInt32(1))
        header.appendBE(UInt32(blocks.count - 1))
        header.appendBE(UInt32(indexOffset))
        header.appendBE(UInt32(indexLength))
        header.appendBE(UInt32(variablesOffset))
        header.appendBE(UInt32(variablesLength))
        bytes.replaceSubrange(0..<header.count, with: header.bytes)
        return bytes
    }

    static let headerSize = 512
}

/// A B+-tree of a BOM store, as the tables of `Assets.car` use it: a header block and one
/// leaf block of entries sorted by key, each key a block of its own (docs/formats/asset-catalog.md,
/// "Trees").
struct BOMTree {
    struct Entry {
        var key: [UInt8]
        var value: UInt32
        var keyBlock: UInt32
    }

    let headerBlock: UInt32
    let leafBlock: UInt32
    let blockSize: Int
    /// The key length a tree read back declares (0xFFFFFFFF for keys of different lengths),
    /// which it keeps when written again.
    private(set) var declaredKeyLength: UInt32?

    /// Reserves the tree's header and leaf blocks, the order actool creates them in.
    init(in store: inout BOMStoreWriter, blockSize: Int) {
        headerBlock = store.reserve()
        leafBlock = store.reserve()
        self.blockSize = blockSize
    }

    /// The one-leaf tree whose header is `headerBlock` in a store read back, and its entries.
    init(reading store: BOMStoreWriter, headerBlock: UInt32, name: String, path: String) throws {
        guard let header = store.block(headerBlock), header.count >= 21, header.starts(with: Array("tree".utf8)) else {
            throw NomacError("malformed \(name) table", path: path)
        }
        func be32(_ bytes: [UInt8], _ at: Int) -> UInt32 { bytes[at..<(at + 4)].reduce(0) { $0 << 8 | UInt32($1) } }
        let root = be32(header, 8)
        guard let leaf = store.block(root), leaf.count >= 12, leaf[0] == 0, leaf[1] == 1 else {
            throw NomacError("asset catalogs whose \(name) table has more than one leaf are not supported yet (BACKLOG B-201)", path: path)
        }
        self.headerBlock = headerBlock
        leafBlock = root
        blockSize = Int(be32(header, 12))
        declaredKeyLength = be32(header, 21)
    }

    /// The (value, key block) pairs of the leaf, in key order.
    func pairs(in store: BOMStoreWriter) -> [(value: UInt32, keyBlock: UInt32)] {
        guard let leaf = store.block(leafBlock) else { return [] }
        func be32(_ at: Int) -> UInt32 { leaf[at..<(at + 4)].reduce(0) { $0 << 8 | UInt32($1) } }
        let count = Int(leaf[2]) << 8 | Int(leaf[3])
        return (0..<count).map { (be32(12 + 8 * $0), be32(16 + 8 * $0)) }
    }

    /// The most entries one leaf holds; actool splits the leaf beyond it.
    var leafCapacity: Int { (blockSize - 12) / 8 }

    /// Writes the header and the leaf for `entries`, which must already be sorted by key; the
    /// leaf also keeps a copy of fixed-length keys.
    func finish(in store: inout BOMStoreWriter, entries: [Entry], name: String) throws {
        guard entries.count <= leafCapacity else {
            throw NomacError("asset catalogs whose \(name) table has more than \(leafCapacity) entries are not supported yet (BACKLOG B-201)")
        }
        let lengths = Set(entries.map(\.key.count))
        let fixedLength: Int? = declaredKeyLength.map { $0 == 0xFFFF_FFFF ? nil : Int($0) } ?? (lengths.count == 1 ? lengths.first : nil)
        store.set(headerBlock, Self.header(root: leafBlock, blockSize: blockSize, count: entries.count, inline: false,
                                           keyLength: fixedLength.map(UInt32.init) ?? 0xFFFF_FFFF))
        var leaf = ByteWriter()
        leaf.appendBE(UInt16(1))
        leaf.appendBE(UInt16(entries.count))
        leaf.appendBE(UInt32(0))
        leaf.appendBE(UInt32(0))
        for entry in entries {
            leaf.appendBE(entry.value)
            leaf.appendBE(entry.keyBlock)
        }
        var length = blockSize
        if let fixedLength {
            leaf.appendZeros(4)
            for entry in entries { leaf.append(entry.key) }
            length += fixedLength * entries.count
        }
        leaf.appendZeros(length - leaf.count)
        store.set(leafBlock, leaf.bytes)
    }

    static func header(root: UInt32, blockSize: Int, count: Int, inline: Bool, keyLength: UInt32) -> [UInt8] {
        var header = ByteWriter()
        header.append(Array("tree".utf8))
        header.appendBE(UInt32(1))
        header.appendBE(root)
        header.appendBE(UInt32(blockSize))
        header.appendBE(UInt32(count))
        header.append([inline ? 1 : 0])
        header.appendBE(keyLength)
        header.appendBE(UInt32(0))
        return header.bytes
    }
}

/// A BOM B+-tree whose keys are 32-bit numbers stored in the entries (`BITMAPKEYS`), built as
/// actool builds it, one entry at a time: a full leaf takes the new entry, keeps the first
/// ⌈n / 2⌉ entries and moves the others to a new leaf created right then, whose separator, the
/// kept leaf's last key, goes to the parent, a new root branch when the leaf was the root
/// (docs/formats/asset-catalog.md, "Trees"; 19 trees of 127 to 510 entries identical).
struct BOMNumberTree {
    struct Node {
        var isLeaf: Bool
        var keys: [UInt32] = []
        /// Value blocks of a leaf, child blocks of a branch (one more than its keys).
        var blocks: [UInt32] = []
        var forward: UInt32 = 0
        var backward: UInt32 = 0
        var parent: UInt32?
    }

    let headerBlock: UInt32
    let blockSize: Int
    private(set) var root: UInt32
    private(set) var nodes: [UInt32: Node]
    private(set) var count = 0

    init(in store: inout BOMStoreWriter, blockSize: Int) {
        headerBlock = store.reserve()
        root = store.reserve()
        nodes = [root: Node(isLeaf: true)]
        self.blockSize = blockSize
    }

    var capacity: Int { (blockSize - 12) / 8 }

    mutating func insert(key: UInt32, value: UInt32, in store: inout BOMStoreWriter) throws {
        var block = root
        while let node = nodes[block], !node.isLeaf {
            block = node.blocks[node.keys.firstIndex { key <= $0 } ?? node.keys.count]
        }
        var leaf = nodes[block]!
        let position = leaf.keys.firstIndex { key <= $0 } ?? leaf.keys.count
        leaf.keys.insert(key, at: position)
        leaf.blocks.insert(value, at: position)
        count += 1
        guard leaf.keys.count > capacity else {
            nodes[block] = leaf
            return
        }
        let kept = (leaf.keys.count + 1) / 2
        let right = store.reserve()
        if leaf.forward != 0 { nodes[leaf.forward]!.backward = right }
        nodes[right] = Node(isLeaf: true, keys: Array(leaf.keys[kept...]), blocks: Array(leaf.blocks[kept...]), forward: leaf.forward,
                            backward: block, parent: leaf.parent)
        leaf.keys.removeSubrange(kept...)
        leaf.blocks.removeSubrange(kept...)
        leaf.forward = right
        let separator = leaf.keys[kept - 1]
        if let parent = leaf.parent {
            nodes[block] = leaf
            var branch = nodes[parent]!
            let index = branch.blocks.firstIndex(of: block)!
            branch.keys.insert(separator, at: index)
            branch.blocks.insert(right, at: index + 1)
            guard branch.keys.count <= capacity else {
                throw NomacError("asset catalogs whose BITMAPKEYS table needs more than one branch level are not supported yet (BACKLOG B-201)")
            }
            nodes[parent] = branch
        } else {
            let newRoot = store.reserve()
            leaf.parent = newRoot
            nodes[block] = leaf
            nodes[right]!.parent = newRoot
            nodes[newRoot] = Node(isLeaf: false, keys: [separator], blocks: [block, right])
            root = newRoot
        }
    }

    /// Writes the header and the nodes: a leaf's entries are (value, key), a branch's (child,
    /// separator) then its last child.
    func finish(in store: inout BOMStoreWriter) {
        store.set(headerBlock, BOMTree.header(root: root, blockSize: blockSize, count: count, inline: true, keyLength: 0))
        for (block, node) in nodes {
            var bytes = ByteWriter()
            bytes.appendBE(UInt16(node.isLeaf ? 1 : 0))
            bytes.appendBE(UInt16(node.keys.count))
            bytes.appendBE(node.forward)
            bytes.appendBE(node.backward)
            for (key, block) in zip(node.keys, node.blocks) {
                bytes.appendBE(block)
                bytes.appendBE(key)
            }
            if !node.isLeaf { bytes.appendBE(node.blocks[node.keys.count]) }
            bytes.appendZeros(blockSize - bytes.count)
            store.set(block, bytes.bytes)
        }
    }
}
