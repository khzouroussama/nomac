// Written for nomac from the LZFSE format as this module's encoder writes it (the inverse of
// LZFSEEncoder.swift, FSE.swift and LZVNEncoder.swift); not a port of the reference decoder.

extension LZFSE {
    /// Why a stream could not be decoded.
    public struct DecodingError: Error, CustomStringConvertible, Sendable {
        public let description: String
    }

    /// The bytes an LZFSE stream encodes: its uncompressed (`bvx-`), LZVN (`bvxn`) and LZFSE v2
    /// (`bvx2`) blocks up to the end-of-stream marker (`bvx$`). Version 1 headers (`bvx1`), which
    /// no encoder of this module writes, are refused.
    public static func decode(_ input: [UInt8]) throws -> [UInt8] {
        var output: [UInt8] = []
        var position = 0
        func u32(_ index: Int) throws -> UInt32 {
            guard index + 4 <= input.count else { throw DecodingError(description: "a block header past the end of the input") }
            return UInt32(input[index]) | UInt32(input[index + 1]) << 8 | UInt32(input[index + 2]) << 16 | UInt32(input[index + 3]) << 24
        }
        while true {
            let magic = try u32(position)
            switch magic {
            case BlockMagic.endOfStream:
                return output
            case BlockMagic.uncompressed:
                let count = Int(try u32(position + 4))
                guard position + 8 + count <= input.count else { throw DecodingError(description: "an uncompressed block past the end of the input") }
                output += input[(position + 8)..<(position + 8 + count)]
                position += 8 + count
            case BlockMagic.compressedLZVN:
                let count = Int(try u32(position + 4))
                let payload = Int(try u32(position + 8))
                let start = position + LZFSEConstant.lzvnHeaderSize
                guard start + payload <= input.count else { throw DecodingError(description: "an LZVN block past the end of the input") }
                let expected = output.count + count
                try LZVNDecoder.decode(input[start..<(start + payload)], into: &output)
                guard output.count == expected else { throw DecodingError(description: "an LZVN block of another size than its header's") }
                position = start + payload
            case BlockMagic.compressedV2:
                position = try LZFSEBlockDecoder.decode(input, at: position, into: &output)
            default:
                throw DecodingError(description: "an unknown block magic 0x\(String(magic, radix: 16)) at \(position)")
            }
        }
    }
}

/// The bits of an FSE stream, read from its last bit back to its first: the encoder pushes each
/// value's bits after the previous ones and encodes from the last symbol, so the decoder pulls
/// the last pushed bits first.
struct FSEInStream {
    let bytes: ArraySlice<UInt8>
    /// Bits not read yet, from the first bit of `bytes`.
    var remaining: Int

    init(_ bytes: ArraySlice<UInt8>, paddingBits: Int) throws {
        guard (0...7).contains(paddingBits), bytes.count > 0 || paddingBits == 0 else {
            throw LZFSE.DecodingError(description: "an FSE stream with \(paddingBits) bits of padding")
        }
        self.bytes = bytes
        remaining = 8 * bytes.count - paddingBits
    }

    mutating func pull(_ n: Int) throws -> Int {
        guard n > 0 else { return 0 }
        guard n <= remaining else { throw LZFSE.DecodingError(description: "an FSE stream read past its start") }
        remaining -= n
        var value: UInt64 = 0
        let first = remaining >> 3
        for index in 0..<min(8, bytes.count - first) {
            value |= UInt64(bytes[bytes.startIndex + first + index]) << UInt64(8 * index)
        }
        return Int((value >> UInt64(remaining & 7)) & ((1 << UInt64(n)) - 1))
    }
}

/// For each decoder state, the symbol it stands for and how the previous state follows from it:
/// `base` plus the next `bits` bits of the stream (the inverse of `FSE.encoderTable`).
struct FSEDecoderTable {
    let entries: [(symbol: Int, bits: Int, base: Int)]

    init(nstates: Int, freq: [UInt16]) throws {
        guard freq.reduce(0, { $0 + Int($1) }) == nstates else {
            throw LZFSE.DecodingError(description: "frequencies that do not sum to \(nstates)")
        }
        var entries: [(symbol: Int, bits: Int, base: Int)] = []
        entries.reserveCapacity(nstates)
        let nClz = UInt32(nstates).leadingZeroBitCount
        for (symbol, value) in freq.enumerated() where value > 0 {
            let f = Int(value)
            let offset = entries.count
            let k = UInt32(f).leadingZeroBitCount - nClz
            let high = 2 * (nstates >> k) - f
            for j in 0..<f {
                let state = offset + j
                if j < high {
                    entries.append((symbol, k, (state - (offset - f + (nstates >> k))) << k))
                } else {
                    entries.append((symbol, k - 1, (state - (offset - f + (nstates >> (k - 1)))) << (k - 1)))
                }
            }
        }
        self.entries = entries
    }

    func decode(_ state: inout Int, _ stream: inout FSEInStream) throws -> Int {
        guard entries.indices.contains(state) else { throw LZFSE.DecodingError(description: "an FSE state out of range") }
        let entry = entries[state]
        state = entry.base + (try stream.pull(entry.bits))
        return entry.symbol
    }
}

/// An LZFSE v2 block (`bvx2`): the frequency tables, then the literals in four interleaved FSE
/// streams, then the L, M, D values of the matches in one.
enum LZFSEBlockDecoder {
    static func decode(_ input: [UInt8], at header: Int, into output: inout [UInt8]) throws -> Int {
        guard header + 32 <= input.count else { throw LZFSE.DecodingError(description: "an LZFSE block header past the end of the input") }
        func u64(_ index: Int) -> UInt64 { (0..<8).reduce(0) { $0 | UInt64(input[index + $1]) << UInt64(8 * $1) } }
        func field(_ value: UInt64, _ offset: Int, _ bits: Int) -> Int { Int((value >> UInt64(offset)) & ((1 << UInt64(bits)) - 1)) }
        let rawBytes = field(u64(header + 4), 0, 32)
        let packed0 = u64(header + 8), packed1 = u64(header + 16), packed2 = u64(header + 24)
        let nLiterals = field(packed0, 0, 20), nLiteralPayloadBytes = field(packed0, 20, 20), nMatches = field(packed0, 40, 20)
        let literalBits = field(packed0, 60, 3) - 7
        let literalStates = [field(packed1, 0, 10), field(packed1, 10, 10), field(packed1, 20, 10), field(packed1, 30, 10)]
        let nLMDPayloadBytes = field(packed1, 40, 20), lmdBits = field(packed1, 60, 3) - 7
        let headerSize = field(packed2, 0, 32)
        var lState = field(packed2, 32, 10), mState = field(packed2, 42, 10), dState = field(packed2, 52, 10)
        guard nLiterals % 4 == 0, headerSize >= 32, header + headerSize + nLiteralPayloadBytes + nLMDPayloadBytes <= input.count else {
            throw LZFSE.DecodingError(description: "an LZFSE block header with inconsistent sizes")
        }

        let freq = try frequencies(input[(header + 32)..<(header + headerSize)],
                                   count: LZFSEConstant.lSymbols + LZFSEConstant.mSymbols + LZFSEConstant.dSymbols + LZFSEConstant.literalSymbols)
        var start = 0
        func next(_ count: Int) -> [UInt16] {
            defer { start += count }
            return Array(freq[start..<(start + count)])
        }
        let lTable = try FSEDecoderTable(nstates: LZFSEConstant.lStates, freq: next(LZFSEConstant.lSymbols))
        let mTable = try FSEDecoderTable(nstates: LZFSEConstant.mStates, freq: next(LZFSEConstant.mSymbols))
        let dTable = try FSEDecoderTable(nstates: LZFSEConstant.dStates, freq: next(LZFSEConstant.dSymbols))
        let literalTable = try FSEDecoderTable(nstates: LZFSEConstant.literalStates, freq: next(LZFSEConstant.literalSymbols))

        let literalStart = header + headerSize
        var literalStream = try FSEInStream(input[literalStart..<(literalStart + nLiteralPayloadBytes)], paddingBits: -literalBits)
        var states = literalStates
        var literals = [UInt8](repeating: 0, count: nLiterals)
        for i in stride(from: 0, to: nLiterals, by: 4) {
            for lane in 0..<4 {
                literals[i + lane] = UInt8(try literalTable.decode(&states[lane], &literalStream))
            }
        }

        let lmdStart = literalStart + nLiteralPayloadBytes
        var lmdStream = try FSEInStream(input[lmdStart..<(lmdStart + nLMDPayloadBytes)], paddingBits: -lmdBits)
        let expected = output.count + rawBytes
        var literal = 0
        var distance = 0
        for _ in 0..<nMatches {
            let lSymbol = try lTable.decode(&lState, &lmdStream)
            let l = Int(LMD.lBaseValue[lSymbol]) + (try lmdStream.pull(LMD.lExtraBits[lSymbol]))
            let mSymbol = try mTable.decode(&mState, &lmdStream)
            let m = Int(LMD.mBaseValue[mSymbol]) + (try lmdStream.pull(LMD.mExtraBits[mSymbol]))
            let dSymbol = try dTable.decode(&dState, &lmdStream)
            let d = Int(LMD.dBaseValue[dSymbol]) + (try lmdStream.pull(LMD.dExtraBits[dSymbol]))
            if d != 0 { distance = d }
            guard literal + l <= nLiterals, output.count + l + m <= expected else {
                throw LZFSE.DecodingError(description: "an LZFSE match out of range")
            }
            output += literals[literal..<(literal + l)]
            literal += l
            try LZVNDecoder.copyMatch(distance: distance, count: m, into: &output)
        }
        guard output.count == expected else { throw LZFSE.DecodingError(description: "an LZFSE block of another size than its header's") }
        return lmdStart + nLMDPayloadBytes
    }

    /// The frequency tables' values, each in the fixed code `lzfse_encode_v1_freq_value` writes,
    /// read from the least significant bit.
    static func frequencies(_ bytes: ArraySlice<UInt8>, count: Int) throws -> [UInt16] {
        var values: [UInt16] = []
        var accum: UInt32 = 0
        var accumBits = 0
        var index = bytes.startIndex
        while values.count < count {
            while accumBits < 14, index < bytes.endIndex {
                accum |= UInt32(bytes[index]) << UInt32(accumBits)
                accumBits += 8
                index += 1
            }
            let (value, bits): (Int, Int)
            switch accum & 3 {
            case 0: (value, bits) = (0, 2)
            case 2: (value, bits) = (1, 2)
            case 1: (value, bits) = accum & 4 == 0 ? (2, 3) : (3, 3)
            default:
                if accum & 4 == 0 {
                    (value, bits) = (4 + Int((accum >> 3) & 3), 5)
                } else if accum & 8 == 0 {
                    (value, bits) = (8 + Int((accum >> 4) & 0xF), 8)
                } else {
                    (value, bits) = (24 + Int((accum >> 4) & 0x3FF), 14)
                }
            }
            guard bits <= accumBits else { throw LZFSE.DecodingError(description: "frequency tables past the end of the block header") }
            values.append(UInt16(value))
            accum >>= UInt32(bits)
            accumBits -= bits
        }
        return values
    }
}

/// An LZVN stream: opcodes each with up to 3 literal bytes inline, a match length and a distance,
/// as `LZVNEncoder` emits them, up to the end-of-stream opcode 0x06.
enum LZVNDecoder {
    static func decode(_ input: ArraySlice<UInt8>, into output: inout [UInt8]) throws {
        var index = input.startIndex
        var distance = 0
        func byte(_ offset: Int) throws -> Int {
            guard index + offset < input.endIndex else { throw LZFSE.DecodingError(description: "an LZVN opcode past the end of the block") }
            return Int(input[index + offset])
        }
        func literals(_ count: Int, after opcodeBytes: Int) throws {
            let start = index + opcodeBytes
            guard start + count <= input.endIndex else { throw LZFSE.DecodingError(description: "LZVN literals past the end of the block") }
            output += input[start..<(start + count)]
            index = start + count
        }
        while true {
            let opcode = try byte(0)
            switch opcode {
            case 0x06:
                return
            case 0x0E, 0x16:
                index += 1
            case 0xF0:
                let m = try byte(1) + 16
                index += 2
                try copyMatch(distance: distance, count: m, into: &output)
            case 0xF1...0xFF:
                index += 1
                try copyMatch(distance: distance, count: opcode & 0xF, into: &output)
            case 0xE0:
                try literals(try byte(1) + 16, after: 2)
            case 0xE1...0xEF:
                try literals(opcode & 0xF, after: 1)
            case 0xA0...0xBF:
                let operand = try byte(1) | (try byte(2)) << 8
                let m = ((opcode & 7) << 2 | operand & 3) + 3
                distance = operand >> 2
                try literals((opcode >> 3) & 3, after: 3)
                try copyMatch(distance: distance, count: m, into: &output)
            case 0x70...0x7F, 0xD0...0xDF:
                throw LZFSE.DecodingError(description: "an undefined LZVN opcode 0x\(String(opcode, radix: 16))")
            default:
                let l = opcode >> 6
                let m = ((opcode >> 3) & 7) + 3
                switch opcode & 7 {
                case 6:
                    guard l > 0 else { throw LZFSE.DecodingError(description: "an undefined LZVN opcode 0x\(String(opcode, radix: 16))") }
                    try literals(l, after: 1)
                case 7:
                    distance = try byte(1) | (try byte(2)) << 8
                    try literals(l, after: 3)
                default:
                    distance = (opcode & 7) << 8 | (try byte(1))
                    try literals(l, after: 2)
                }
                try copyMatch(distance: distance, count: m, into: &output)
            }
        }
    }

    /// Appends `count` bytes copied from `distance` bytes back, one at a time, so that a match may
    /// overlap the bytes it writes.
    static func copyMatch(distance: Int, count: Int, into output: inout [UInt8]) throws {
        guard count > 0 else { return }
        guard distance > 0, distance <= output.count else { throw LZFSE.DecodingError(description: "a match distance of \(distance) past the start of the output") }
        let start = output.count - distance
        for i in 0..<count { output.append(output[start + i]) }
    }
}
