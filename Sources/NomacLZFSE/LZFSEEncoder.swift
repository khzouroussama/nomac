/*
Copyright (c) 2015-2016, Apple Inc. All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1.  Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

2.  Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer
    in the documentation and/or other materials provided with the distribution.

3.  Neither the name of the copyright holder(s) nor the names of any contributors may be used to endorse or promote products derived
    from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

// Swift port of src/lzfse_encode_base.c.

/// `lzfse_match`: `length` bytes at `pos` that repeat the bytes at `ref`.
struct LZFSEMatch {
    var pos = 0
    var ref = 0
    var length: UInt32 = 0
}

/// `lzfse_encoder_state`, with the functions of lzfse_encode_base.c that update it. Every
/// function returning `Bool` returns false where the reference returns `LZFSE_STATUS_DST_FULL`.
struct LZFSEEncoder: ~Copyable {
    /// Forward match length limit, so that a match never splits into too many L, M, D triplets.
    static let maxMatchLength = UInt32(100 * LZFSEConstant.maxMValue)
    static let invalidPosition = Int32(-4 * LZFSEConstant.maxDValue)

    let source: UnsafeBufferPointer<UInt8>
    /// Offset in `source` of `s->src`, which `translate` moves forward.
    var base = 0
    var srcEnd = 0
    var srcLiteral = 0
    var srcEncodeI = 0
    var srcEncodeEnd = 0
    /// The destination buffer.
    let dst: UnsafeMutableBufferPointer<UInt8>
    /// `s->dst_end`: where the destination ends for the encoder, which a stream moves forward.
    var dstEnd: Int
    /// Offset in `dst` of the next byte to write.
    var dstPosition = 0
    var pending = LZFSEMatch()
    var nMatches = 0
    var nLiterals = 0
    let lValues: UnsafeMutableBufferPointer<UInt32>
    let mValues: UnsafeMutableBufferPointer<UInt32>
    let dValues: UnsafeMutableBufferPointer<UInt32>
    let literals: UnsafeMutableBufferPointer<UInt8>
    /// `history_table`: `hashWidth` positions per hash line, most recent first, and the four
    /// bytes at each.
    let historyPos: UnsafeMutableBufferPointer<Int32>
    let historyValue: UnsafeMutableBufferPointer<UInt32>
    /// How many pending literals make `lzfse_encode_base` emit some (see `LZFSE.Encoder`).
    let literalFlush: Int
    /// The bytes before `srcEnd` `lzfse_encode_base` starts no search in: 8, or 400 in a stream
    /// window that is not the last (`LZFSE.encodeStream`).
    var lookahead = 8

    /// The state `lzfse_encode_buffer_with_scratch` sets up, after `lzfse_encode_init`.
    init(source: UnsafeBufferPointer<UInt8>, dst: UnsafeMutableBufferPointer<UInt8>, literalFlush: Int) {
        self.source = source
        self.dst = dst
        dstEnd = dst.count
        self.literalFlush = literalFlush
        lValues = .allocate(capacity: LZFSEConstant.matchesPerBlock)
        mValues = .allocate(capacity: LZFSEConstant.matchesPerBlock)
        dValues = .allocate(capacity: LZFSEConstant.matchesPerBlock)
        literals = .allocate(capacity: LZFSEConstant.literalsPerBlock)
        historyPos = .allocate(capacity: LZFSEConstant.hashValues * LZFSEConstant.hashWidth)
        historyPos.initialize(repeating: Self.invalidPosition)
        historyValue = .allocate(capacity: LZFSEConstant.hashValues * LZFSEConstant.hashWidth)
        historyValue.initialize(repeating: 0)
    }

    deinit {
        lValues.deallocate()
        mValues.deallocate()
        dValues.deallocate()
        literals.deallocate()
        historyPos.deallocate()
        historyValue.deallocate()
    }

    @inline(__always)
    private func load4(_ i: Int) -> UInt32 {
        source.load4(base + i)
    }

    @inline(__always)
    private func load8(_ i: Int) -> UInt64 {
        source.load8(base + i)
    }

    @inline(__always)
    private func byte(_ i: Int) -> UInt8 {
        source[base + i]
    }

    /// `hashX`: Knuth's multiplicative hash of 4 bytes, in 0..<hashValues.
    @inline(__always)
    private static func hash(_ x: UInt32) -> Int {
        Int((x &* 2_654_435_761) >> UInt32(32 - LZFSEConstant.hashBits))
    }

    // MARK: Encoder back end

    /// `lzfse_encode_matches`: encodes the stored matches into a bvx2 block. When the
    /// destination is full the state is restored, as the reference does, so that a stream can
    /// go on once its output is drained (`LZFSE.encodeStream`).
    private mutating func encodeMatches() -> Bool {
        if nLiterals == 0 && nMatches == 0 {
            return true
        }
        let savedLiterals = nLiterals, savedDst = dstPosition
        if encodeBlock() {
            return true
        }
        var dPrev: UInt32 = 0
        for i in 0..<nMatches {
            if dValues[i] == 0 {
                dValues[i] = dPrev
            } else {
                dPrev = dValues[i]
            }
        }
        nLiterals = savedLiterals
        dstPosition = savedDst
        return false
    }

    private mutating func encodeBlock() -> Bool {
        // Four interleaved literal streams.
        while nLiterals & 3 != 0 {
            literals[nLiterals] = 0
            nLiterals += 1
        }

        // A distance equal to the previous one is stored as 0.
        var dPrev: UInt32 = 0
        for i in 0..<nMatches {
            let d = dValues[i]
            if d == dPrev {
                dValues[i] = 0
            } else {
                dPrev = d
            }
        }

        var lOcc = [UInt32](repeating: 0, count: LZFSEConstant.lSymbols)
        var mOcc = [UInt32](repeating: 0, count: LZFSEConstant.mSymbols)
        var dOcc = [UInt32](repeating: 0, count: LZFSEConstant.dSymbols)
        var literalOcc = [UInt32](repeating: 0, count: LZFSEConstant.literalSymbols)
        var lSum: UInt32 = 0
        var mSum: UInt32 = 0
        for i in 0..<nMatches {
            let l = lValues[i]
            lSum &+= l
            lOcc[LMD.lSymbol(l)] += 1
        }
        for i in 0..<nMatches {
            let m = mValues[i]
            mSum &+= m
            mOcc[LMD.mSymbol(m)] += 1
        }
        for i in 0..<nMatches {
            dOcc[LMD.dSymbol(Int32(bitPattern: dValues[i]))] += 1
        }
        for i in 0..<nLiterals {
            literalOcc[Int(literals[i])] += 1
        }

        if dstPosition + LZFSEConstant.v2HeaderCapacity > dstEnd {
            return false
        }
        let header = dstPosition

        let lFreq = FSE.normalizeFreq(nstates: LZFSEConstant.lStates, lOcc)
        let mFreq = FSE.normalizeFreq(nstates: LZFSEConstant.mStates, mOcc)
        let dFreq = FSE.normalizeFreq(nstates: LZFSEConstant.dStates, dOcc)
        let literalFreq = FSE.normalizeFreq(nstates: LZFSEConstant.literalStates, literalOcc)

        let headerSize = writeFreqTables(lFreq + mFreq + dFreq + literalFreq, header: header)
        dstPosition += headerSize

        let lEncoder = FSE.encoderTable(nstates: LZFSEConstant.lStates, freq: lFreq)
        let mEncoder = FSE.encoderTable(nstates: LZFSEConstant.mStates, freq: mFreq)
        let dEncoder = FSE.encoderTable(nstates: LZFSEConstant.dStates, freq: dFreq)
        let literalEncoder = FSE.encoderTable(nstates: LZFSEConstant.literalStates, freq: literalFreq)

        // Literals, from the last so that they decode from the first.
        var out = FSEOutStream()
        var state0: UInt16 = 0
        var state1: UInt16 = 0
        var state2: UInt16 = 0
        var state3: UInt16 = 0
        var buf = dstPosition
        var i = nLiterals
        while i > 0 {
            if buf + 16 > dstEnd {
                return false
            }
            i -= 4
            out.encode(Int(literals[i + 3]), &state3, literalEncoder)
            out.encode(Int(literals[i + 2]), &state2, literalEncoder)
            out.encode(Int(literals[i + 1]), &state1, literalEncoder)
            out.encode(Int(literals[i + 0]), &state0, literalEncoder)
            out.flush(dst, &buf)
        }
        out.finish(dst, &buf)
        let literalBits = out.accumNBits
        let nLiteralPayloadBytes = buf - dstPosition
        dstPosition = buf

        // L, M, D, from the last match, after 8 bytes of padding.
        out = FSEOutStream()
        var lState: UInt16 = 0
        var mState: UInt16 = 0
        var dState: UInt16 = 0
        buf = dstPosition
        if buf + 8 > dstEnd {
            return false
        }
        dst.store8(buf, 0)
        buf += 8
        i = nMatches
        while i > 0 {
            if buf + 16 > dstEnd {
                return false
            }
            i -= 1

            let dValue = Int32(bitPattern: dValues[i])
            let dSymbol = LMD.dSymbol(dValue)
            out.push(LMD.dExtraBits[dSymbol], UInt64(truncatingIfNeeded: dValue - LMD.dBaseValue[dSymbol]))
            out.encode(dSymbol, &dState, dEncoder)

            let mValue = Int32(bitPattern: mValues[i])
            let mSymbol = LMD.mSymbol(mValues[i])
            out.push(LMD.mExtraBits[mSymbol], UInt64(truncatingIfNeeded: mValue - LMD.mBaseValue[mSymbol]))
            out.encode(mSymbol, &mState, mEncoder)

            let lValue = Int32(bitPattern: lValues[i])
            let lSymbol = LMD.lSymbol(lValues[i])
            out.push(LMD.lExtraBits[lSymbol], UInt64(truncatingIfNeeded: lValue - LMD.lBaseValue[lSymbol]))
            out.encode(lSymbol, &lState, lEncoder)

            out.flush(dst, &buf)
        }
        out.finish(dst, &buf)
        let nLMDPayloadBytes = buf - dstPosition
        let lmdBits = out.accumNBits
        dstPosition = buf

        // lzfse_encode_v1_state
        let packed0 = UInt64(nLiterals) | UInt64(nLiteralPayloadBytes) << 20 | UInt64(nMatches) << 40
            | UInt64(7 + literalBits) << 60
        let packed1 = UInt64(state0) | UInt64(state1) << 10 | UInt64(state2) << 20 | UInt64(state3) << 30
            | UInt64(nLMDPayloadBytes) << 40 | UInt64(7 + lmdBits) << 60
        let packed2 = UInt64(headerSize) | UInt64(lState) << 32 | UInt64(mState) << 42 | UInt64(dState) << 52
        dst.store4(header, BlockMagic.compressedV2)
        dst.store4(header + 4, mSum &+ lSum)
        dst.store8(header + 8, packed0)
        dst.store8(header + 16, packed1)
        dst.store8(header + 24, packed2)

        nLiterals = 0
        nMatches = 0
        return true
    }

    /// `lzfse_encode_v1_freq_table`: writes the frequency tables after the 32 bytes of fixed
    /// header fields at `header`, and returns the size of the whole header.
    private func writeFreqTables(_ freq: [UInt16], header: Int) -> Int {
        var accum: UInt32 = 0
        var accumNBits = 0
        var position = header + 32
        for value in freq {
            let (bits, nbits) = Self.freqValueCode(Int(value))
            accum |= bits << UInt32(accumNBits)
            accumNBits += nbits
            while accumNBits >= 8 {
                dst[position] = UInt8(truncatingIfNeeded: accum)
                accum >>= 8
                accumNBits -= 8
                position += 1
            }
        }
        if accumNBits > 0 {
            dst[position] = UInt8(truncatingIfNeeded: accum)
            position += 1
        }
        return position - header
    }

    /// `lzfse_encode_v1_freq_value`: a fixed Huffman code, read from the least significant bit.
    private static func freqValueCode(_ value: Int) -> (bits: UInt32, nbits: Int) {
        switch value {
        case 0: (0, 2)
        case 1: (2, 2)
        case 2: (1, 3)
        case 3: (5, 3)
        case 4: (3, 5)
        case 5: (11, 5)
        case 6: (19, 5)
        case 7: (27, 5)
        case 8..<24: (UInt32(7 + ((value - 8) << 4)), 8)
        default: (UInt32(((value - 24) << 4) + 15), 14)
        }
    }

    /// `lzfse_push_lmd`: stores one L, M, D triplet and its literals.
    private mutating func pushLMD(_ l: UInt32, _ m: UInt32, _ d: UInt32) -> Bool {
        // The margins are the reference's, which copies literals 16 bytes at a time.
        if nMatches + 1 + 8 > LZFSEConstant.matchesPerBlock {
            return false
        }
        if nLiterals + Int(l) + 16 > LZFSEConstant.literalsPerBlock {
            return false
        }
        lValues[nMatches] = l
        mValues[nMatches] = m
        dValues[nMatches] = d
        nMatches += 1
        literals.copy(nLiterals, from: source, base + srcLiteral, count: Int(l))
        nLiterals += Int(l)
        srcLiteral += Int(l) + Int(m)
        return true
    }

    /// `lzfse_push_match`: splits `match` into triplets whose L and M are in range. When they
    /// do not all fit, the state is left as before.
    private mutating func pushMatch(_ match: LZFSEMatch) -> Bool {
        let saved = (nMatches, nLiterals, srcLiteral)
        var l = UInt32(truncatingIfNeeded: match.pos - srcLiteral)
        var m = match.length
        let d = UInt32(truncatingIfNeeded: match.pos - match.ref)
        let maxL = UInt32(LZFSEConstant.maxLValue)
        let maxM = UInt32(LZFSEConstant.maxMValue)
        var ok = true
        // D = 1 for literal-only triplets: the most frequent distance, never used.
        while ok && l > maxL {
            ok = pushLMD(maxL, 0, 1)
            l -= maxL
        }
        while ok && m > maxM {
            ok = pushLMD(l, maxM, d)
            l = 0
            m -= maxM
        }
        if ok && (l > 0 || m > 0) {
            ok = pushLMD(l, m, d)
        }
        if !ok {
            (nMatches, nLiterals, srcLiteral) = saved
        }
        return ok
    }

    /// `lzfse_backend_match`: adds `match`, emitting a block first when the state is full.
    private mutating func backendMatch(_ match: LZFSEMatch) -> Bool {
        if pushMatch(match) {
            return true
        }
        if !encodeMatches() {
            return false
        }
        return pushMatch(match)
    }

    /// `lzfse_backend_literals`: adds `l` literals as a match with M = 0 and D = 1.
    private mutating func backendLiterals(_ l: Int) -> Bool {
        let pos = srcLiteral + l
        return backendMatch(LZFSEMatch(pos: pos, ref: pos - 1, length: 0))
    }

    /// `lzfse_backend_end_of_stream`: emits the final block and the end-of-stream marker.
    private mutating func backendEndOfStream() -> Bool {
        if !encodeMatches() {
            return false
        }
        if dstPosition + 4 > dstEnd {
            return false
        }
        dst.store4(dstPosition, BlockMagic.endOfStream)
        dstPosition += 4
        return true
    }

    // MARK: Encoder state management

    /// `lzfse_encode_translate`: moves the source forward by `delta`, keeping every offset on
    /// the same bytes and clamping history positions at the invalid position.
    mutating func translate(_ delta: Int) {
        if delta == 0 {
            return
        }
        base += delta
        srcEnd -= delta
        srcEncodeI -= delta
        srcEncodeEnd -= delta
        srcLiteral -= delta
        pending.pos -= delta
        pending.ref -= delta
        let invalidPosition = Int(Self.invalidPosition)
        for i in 0..<historyPos.count {
            let newPos = Int(historyPos[i]) - delta
            historyPos[i] = Int32(truncatingIfNeeded: newPos < invalidPosition ? invalidPosition : newPos)
        }
    }

    // MARK: Encoder front end

    /// `lzfse_encode_base`: searches matches for every position up to `lookahead` bytes before
    /// `srcEnd`.
    mutating func encodeBase() -> Bool {
        srcEncodeEnd = srcEnd - lookahead
        while srcEncodeI < srcEncodeEnd {
            let pos = srcEncodeI
            let x = load4(pos)
            let line = Self.hash(x) * LZFSEConstant.hashWidth

            // Positions still covered by an emitted match are not searched.
            if pos >= srcLiteral && !searchMatch(at: pos, value: x, line: line) {
                return false
            }

            for k in stride(from: LZFSEConstant.hashWidth - 1, to: 0, by: -1) {
                historyPos[line + k] = historyPos[line + k - 1]
                historyValue[line + k] = historyValue[line + k - 1]
            }
            historyPos[line] = Int32(truncatingIfNeeded: pos)
            historyValue[line] = x
            srcEncodeI += 1
        }
        return true
    }

    /// The body of the `lzfse_encode_base` loop for a position past the emitted matches: finds
    /// the longest match among the history line's candidates, then emits or keeps it.
    private mutating func searchMatch(at pos: Int, value x: UInt32, line: Int) -> Bool {
        var incoming = LZFSEMatch(pos: pos, ref: 0, length: 0)

        // Matches of 4 bytes or more only.
        for k in 0..<LZFSEConstant.hashWidth {
            if historyValue[line + k] != x {
                continue
            }
            let ref = Int(historyPos[line + k])
            if ref + LZFSEConstant.maxDValue < pos {
                continue
            }
            var length: UInt32 = 4
            let maxLength = UInt32(truncatingIfNeeded: srcEnd - pos - 8)
            while length < maxLength {
                let d = load8(ref + Int(length)) ^ load8(pos + Int(length))
                if d == 0 {
                    length += 8
                    continue
                }
                length += UInt32(d.trailingZeroBitCount >> 3)
                break
            }
            if length > incoming.length {
                incoming.length = length
                incoming.ref = ref
            }
        }

        if incoming.length == 0 {
            // Consume literals well before a block's worth accumulates.
            if pos - srcLiteral > literalFlush {
                if pending.length > 0 {
                    if !backendMatch(pending) {
                        return false
                    }
                    pending = LZFSEMatch()
                } else if !backendLiterals(LZFSEConstant.maxLValue) {
                    return false
                }
            }
            return true
        }

        if incoming.length > Self.maxMatchLength {
            incoming.length = Self.maxMatchLength
        }

        while incoming.pos > srcLiteral && incoming.ref > 0 && byte(incoming.ref - 1) == byte(incoming.pos - 1) {
            incoming.pos -= 1
            incoming.ref -= 1
        }
        incoming.length += UInt32(truncatingIfNeeded: pos - incoming.pos)

        // The match filtering heuristic of LZVN.
        if incoming.length >= LZFSEConstant.goodMatch {
            if !backendMatch(incoming) {
                return false
            }
            pending = LZFSEMatch()
            return true
        }
        if pending.length == 0 {
            pending = incoming
            return true
        }
        if pending.pos + Int(pending.length) <= incoming.pos {
            if !backendMatch(pending) {
                return false
            }
            pending = incoming
            return true
        }
        if !backendMatch(incoming.length > pending.length ? incoming : pending) {
            return false
        }
        pending = LZFSEMatch()
        return true
    }

    /// `lzfse_encode_finish`: emits the pending match, the final literals, the last block and
    /// the end-of-stream marker.
    mutating func finish() -> Bool {
        if pending.length > 0 {
            if !backendMatch(pending) {
                return false
            }
            pending = LZFSEMatch()
        }
        let l = srcEnd - srcLiteral
        if l > 0 && !backendLiterals(l) {
            return false
        }
        return backendEndOfStream()
    }
}
