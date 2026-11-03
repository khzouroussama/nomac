/// A FlatBuffers buffer written back to front as the format's reference builder lays it out
/// (flatbuffers.dev, "Internals"): every scalar aligned to its size, strings and vectors aligned
/// for their length prefix, a table's fields in the order they are added, its vtable written just
/// before it unless an identical one was written earlier, and the root offset aligned to the
/// largest scalar. Xcode 27.0's App Shortcuts training writes `nlu/nlu.lzfse` so
/// (docs/formats/app-intents.md).
struct FlatBufferBuilder {
    /// The bytes written so far, last byte first.
    private var reversed: [UInt8] = []
    private var minimumAlignment = 1
    private var vtables: [(offset: Int, entries: [UInt16])] = []
    private var tableStart = 0
    private var fields: [(slot: Int, end: Int)] = []

    /// An object's position: the number of bytes from its start to the end of the buffer.
    typealias Offset = Int

    private var size: Int { reversed.count }

    private mutating func align(_ alignment: Int, after length: Int = 0) {
        minimumAlignment = max(minimumAlignment, alignment)
        reversed += repeatElement(0, count: (-(size + length)) & (alignment - 1))
    }

    private mutating func push<T: FixedWidthInteger>(_ value: T) {
        align(MemoryLayout<T>.size)
        reversed += withUnsafeBytes(of: value.littleEndian) { Array($0) }.reversed()
    }

    private mutating func pushOffset(_ offset: Offset) {
        align(4)
        push(UInt32(size - offset + 4))
    }

    mutating func string(_ value: String) -> Offset {
        let bytes = Array(value.utf8)
        align(4, after: bytes.count + 1)
        reversed.append(0)
        reversed += bytes.reversed()
        push(UInt32(bytes.count))
        return size
    }

    mutating func vector(_ offsets: [Offset]) -> Offset {
        align(4, after: 4 * offsets.count)
        for offset in offsets.reversed() { pushOffset(offset) }
        push(UInt32(offsets.count))
        return size
    }

    mutating func startTable() {
        tableStart = size
        fields = []
    }

    mutating func add<T: FixedWidthInteger>(_ slot: Int, _ value: T) {
        push(value)
        fields.append((slot, size))
    }

    mutating func add(_ slot: Int, offset: Offset) {
        pushOffset(offset)
        fields.append((slot, size))
    }

    mutating func endTable() -> Offset {
        push(Int32(0))
        let table = size
        let slots = (fields.map(\.slot).max() ?? -1) + 1
        var entries = [UInt16(4 + 2 * slots), UInt16(table - tableStart)] + repeatElement(0, count: slots)
        for field in fields { entries[2 + field.slot] = UInt16(table - field.end) }
        let vtable: Offset
        if let existing = vtables.first(where: { $0.entries == entries }) {
            vtable = existing.offset
        } else {
            for entry in entries.reversed() { push(entry) }
            vtable = size
            vtables.append((vtable, entries))
        }
        let value = withUnsafeBytes(of: Int32(vtable - table).littleEndian) { Array($0) }
        for (index, byte) in value.enumerated() { reversed[table - 1 - index] = byte }
        return table
    }

    /// The buffer with `root` as its root table.
    mutating func finish(_ root: Offset) -> [UInt8] {
        align(minimumAlignment, after: 4)
        pushOffset(root)
        return reversed.reversed()
    }
}
