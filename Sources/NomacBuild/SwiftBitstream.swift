import Foundation
import NomacCore

/// The records of a file in LLVM's bitstream container, which the Swift compiler writes for
/// `.swiftmodule`, `.swiftdoc` and `.swiftsourceinfo` (LLVM's "LLVM Bitcode File Format": a
/// 32-bit magic, then abbreviation-coded blocks and records, with `BLOCKINFO` defining
/// abbreviations for other blocks).
struct SwiftBitstream {
    struct Record: Equatable {
        /// The IDs of the enclosing blocks, outermost first.
        var blocks: [UInt64]
        var code: UInt64
        var fields: [UInt64]
        var blob: [UInt8]?
    }

    /// Swift's control block (`CONTROL_BLOCK_ID` in swift's `include/swift/Serialization/ModuleFormat.h`).
    static let controlBlock: UInt64 = 9
    /// The control block's `METADATA` record: the format version and, as its blob, the
    /// version of the compiler that wrote the file.
    static let metadataRecord: UInt64 = 1

    private enum Operand {
        case literal(UInt64)
        case fixed(Int)
        case vbr(Int)
        case array
        case char6
        case blob
    }

    private struct Bits {
        let bytes: [UInt8]
        let path: String
        var position: Int

        var atEnd: Bool { position >= bytes.count * 8 }

        mutating func read(_ width: Int) throws -> UInt64 {
            guard width <= 64, position + width <= bytes.count * 8 else { throw NomacError("truncated bitstream", path: path) }
            var value: UInt64 = 0
            for bit in 0..<width {
                let index = position + bit
                value |= UInt64((bytes[index >> 3] >> UInt8(index & 7)) & 1) << UInt64(bit)
            }
            position += width
            return value
        }

        mutating func vbr(_ width: Int) throws -> UInt64 {
            guard width > 1 else { throw NomacError("malformed bitstream", path: path) }
            var value: UInt64 = 0
            var shift: UInt64 = 0
            while true {
                let piece = try read(width)
                guard shift < 64 else { throw NomacError("malformed bitstream", path: path) }
                value |= (piece & ((1 << UInt64(width - 1)) - 1)) << shift
                if piece & (1 << UInt64(width - 1)) == 0 { return value }
                shift += UInt64(width - 1)
            }
        }

        mutating func align() {
            position = (position + 31) & ~31
        }
    }

    let records: [Record]

    init(path: String) throws {
        guard let data = FileManager.default.contents(atPath: path), data.count >= 4 else { throw NomacError("cannot read the file", path: path) }
        var bits = Bits(bytes: [UInt8](data), path: path, position: 32)
        var records: [Record] = []
        var blockInfo: [UInt64: [[Operand]]] = [:]

        func operand(_ bits: inout Bits) throws -> Operand {
            if try bits.read(1) == 1 { return .literal(try bits.vbr(8)) }
            switch try bits.read(3) {
            case 1: return .fixed(Int(try bits.vbr(5)))
            case 2: return .vbr(Int(try bits.vbr(5)))
            case 3: return .array
            case 4: return .char6
            case 5: return .blob
            default: throw NomacError("unknown bitstream operand encoding", path: path)
            }
        }
        func scalar(_ operand: Operand, _ bits: inout Bits) throws -> UInt64 {
            switch operand {
            case .literal(let value): return value
            case .fixed(let width): return try bits.read(width)
            case .vbr(let width): return try bits.vbr(width)
            case .char6: return try bits.read(6)
            case .array, .blob: throw NomacError("malformed bitstream abbreviation", path: path)
            }
        }
        func block(width: Int, id: UInt64?, path blocks: [UInt64], _ bits: inout Bits) throws {
            var abbreviations = id.flatMap { blockInfo[$0] } ?? []
            var infoTarget: UInt64?
            while !bits.atEnd {
                let abbreviation = try bits.read(width)
                switch abbreviation {
                case 0: // END_BLOCK
                    bits.align()
                    return
                case 1: // ENTER_SUBBLOCK
                    let child = try bits.vbr(8)
                    let childWidth = Int(try bits.vbr(4))
                    bits.align()
                    _ = try bits.read(32)
                    try block(width: childWidth, id: child, path: blocks + [child], &bits)
                case 2: // DEFINE_ABBREV
                    let operands = try (0..<Int(try bits.vbr(5))).map { _ in try operand(&bits) }
                    if id == 0 {
                        guard let infoTarget else { throw NomacError("BLOCKINFO abbreviation without SETBID", path: path) }
                        blockInfo[infoTarget, default: []].append(operands)
                    } else {
                        abbreviations.append(operands)
                    }
                case 3: // UNABBREV_RECORD
                    let code = try bits.vbr(6)
                    let fields = try (0..<Int(try bits.vbr(6))).map { _ in try bits.vbr(6) }
                    if id == 0, code == 1, let target = fields.first { infoTarget = target }
                    records.append(Record(blocks: blocks, code: code, fields: fields, blob: nil))
                default:
                    let index = Int(abbreviation) - 4
                    guard index < abbreviations.count else { throw NomacError("undefined bitstream abbreviation", path: path) }
                    let operands = abbreviations[index]
                    var values: [UInt64] = []
                    var blob: [UInt8]?
                    var position = 0
                    while position < operands.count {
                        switch operands[position] {
                        case .array:
                            guard position + 1 < operands.count else { throw NomacError("malformed bitstream abbreviation", path: path) }
                            let element = operands[position + 1]
                            values += try (0..<Int(try bits.vbr(6))).map { _ in try scalar(element, &bits) }
                            position += 2
                        case .blob:
                            let count = Int(try bits.vbr(6))
                            bits.align()
                            let start = bits.position >> 3
                            guard start + count <= bits.bytes.count else { throw NomacError("truncated bitstream", path: path) }
                            blob = Array(bits.bytes[start..<(start + count)])
                            bits.position += count * 8
                            bits.align()
                            position += 1
                        default:
                            values.append(try scalar(operands[position], &bits))
                            position += 1
                        }
                    }
                    guard let code = values.first else { throw NomacError("bitstream record without a code", path: path) }
                    if id == 0, code == 1, values.count > 1 { infoTarget = values[1] }
                    records.append(Record(blocks: blocks, code: code, fields: Array(values.dropFirst()), blob: blob))
                }
            }
        }
        try block(width: 2, id: nil, path: [], &bits)
        self.records = records
    }

    /// The `.swiftsourceinfo` block of declaration locations (`DECL_LOCS_BLOCK_ID`, observed as 193).
    static let declarationLocationsBlock: UInt64 = 193
    /// Its `SOURCE_FILE_LIST` record (swift's `lib/Serialization/SourceInfoFormat.h`): one
    /// 84-byte entry per source file, written by `emitFileListRecord` in
    /// `lib/Serialization/SerializeDoc.cpp`: the path's offset in the text data (4 bytes), two
    /// interface hashes (32 characters each), the file's modification time in nanoseconds
    /// (8 bytes) and its size (8 bytes).
    static let sourceFileListRecord: UInt64 = 5
    static let sourceFileEntrySize = 84
    static let sourceFileModificationTime = 68..<76

    /// Its record of the source files' paths, one after another (cwa's
    /// `ENA.swiftmodule/Project/arm64-apple-ios.swiftsourceinfo`, observed as code 3).
    static let sourcePathTextRecord: UInt64 = 3

    /// Whether `record` is a `.swiftsourceinfo` record of source paths.
    static func isSourcePathText(_ record: Record) -> Bool {
        record.blocks.last == declarationLocationsBlock && record.code == sourcePathTextRecord
    }

    /// Whether `record` is a control block's `METADATA` record.
    static func isCompilerVersion(_ record: Record) -> Bool {
        record.blocks.last == controlBlock && record.code == metadataRecord
    }

    /// Whether `record` is a `.swiftsourceinfo` source file list.
    static func isSourceFileList(_ record: Record) -> Bool {
        record.blocks.last == declarationLocationsBlock && record.code == sourceFileListRecord
    }

    /// Whether two source file lists have the same files, hashes and sizes, whatever their
    /// modification times.
    static func sameSourceFiles(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count, a.count % sourceFileEntrySize == 0 else { return false }
        return a.indices.allSatisfy { a[$0] == b[$0] || sourceFileModificationTime.contains($0 % sourceFileEntrySize) }
    }
}
