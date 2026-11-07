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

// Swift port of src/lzvn_encode_base.c and src/lzvn_encode_base.h.

public enum LZVN {
    /// The raw LZVN stream `lzvn_encode_buffer` writes for `input` into a destination large
    /// enough for it (no block header), ending with the end-of-stream opcode.
    ///
    /// `lzvn_encode_buffer` refuses inputs over 4 GiB; passing one is a programming error.
    public static func encode(_ input: [UInt8], encoder: LZFSE.Encoder = .reference) -> [UInt8] {
        encode(input, encoder: encoder, emitsPendingMatch: false)
    }

    /// libcompression's `compression_stream` given all of `input` at once, as actool uses it for
    /// iOS 8's images (`old-targets`: 92 of 92 streams): four no-op opcodes, then
    /// `compression_encode_buffer`'s choices with the last pending match emitted instead of
    /// dropped.
    public static func encodeStream(_ input: [UInt8]) -> [UInt8] {
        [0x0E, 0x16, 0x16, 0x0E] + encode(input, encoder: .libcompression, emitsPendingMatch: true)
    }

    private static func encode(_ input: [UInt8], encoder: LZFSE.Encoder, emitsPendingMatch: Bool) -> [UInt8] {
        precondition(input.count <= LZVNEncoder.maxSourceSize, "lzvn_encode_buffer encodes at most 4 GiB")
        return input.withUnsafeBufferPointer { source in
            // Doubled until the stream fits; once it fits, its bytes do not depend on the size.
            var dstSize = source.count + source.count / 4 + 64
            while true {
                let dst = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: dstSize)
                defer { dst.deallocate() }
                let size = LZVNEncoder.encodeBuffer(dst: dst, source: source, encoder: encoder, emitsPendingMatch: emitsPendingMatch)
                if size > 0 {
                    return Array(dst[0..<size])
                }
                dstSize <<= 1
            }
        }
    }
}

/// `lzvn_match_info`.
struct LZVNMatch {
    /// Beginning of the match, the current position.
    var mBegin = 0
    /// End of the match, where the next literal begins if the whole match is emitted.
    var mEnd = 0
    /// Match length: `mEnd - mBegin`.
    var m = 0
    /// Match distance.
    var d = 0
    /// Match gain: M minus the bytes that store the distance.
    var k = 0
}

/// `lzvn_encoder_state` and the encoder of lzvn_encode_base.c.
struct LZVNEncoder: ~Copyable {
    static let hashBits = 14
    static let hashValues = 1 << hashBits
    static let maxDistance = 0xFFFF
    /// Bytes kept between the current position and the end during the match search.
    static let minMargin = 8
    /// Pending literals beyond which a long literal is emitted.
    static let maxLiteralBacklog = 400
    /// `LZVN_ENCODE_MIN_SRC_SIZE`: smaller sources are emitted as one literal.
    static let minSourceSize = 8
    /// `LZVN_ENCODE_MAX_SRC_SIZE`.
    static let maxSourceSize = 0xFFFF_FFFF
    /// `LZVN_ENCODE_MIN_DST_SIZE`.
    static let minDestinationSize = 8

    let src: UnsafeBufferPointer<UInt8>
    let srcBegin = 0
    let srcEnd: Int
    var srcCurrent = 0
    /// We must have `srcCurrentEnd + 8 <= srcEnd`.
    var srcCurrentEnd = 0
    /// Next byte to encode, before or after `srcCurrent`.
    var srcLiteral = 0
    let dstBuffer: UnsafeMutableBufferPointer<UInt8>
    var dst = 0
    var dstEnd: Int
    var pending = LZVNMatch()
    /// Distance of the last emitted match, or 0.
    var dPrev = 0
    /// Per hash value, four positions (most recent first) and the four bytes at each.
    let tableIndices: UnsafeMutableBufferPointer<Int32>
    let tableValues: UnsafeMutableBufferPointer<UInt32>
    /// libcompression's `hash3i` (see `LZFSE.Encoder`).
    let knuthHash: Bool

    private init(src: UnsafeBufferPointer<UInt8>, dst: UnsafeMutableBufferPointer<UInt8>, encoder: LZFSE.Encoder) {
        self.src = src
        knuthHash = encoder == .libcompression
        srcEnd = src.count
        dstBuffer = dst
        // 8 bytes are reserved for the end-of-stream opcode.
        dstEnd = dst.count - 8
        tableIndices = .allocate(capacity: Self.hashValues * 4)
        tableValues = .allocate(capacity: Self.hashValues * 4)
    }

    deinit {
        tableIndices.deallocate()
        tableValues.deallocate()
    }

    /// `lzvn_encode_buffer`: encodes all of `source` into `dst`, and returns the size written,
    /// or 0 if it does not fit.
    static func encodeBuffer(dst: UnsafeMutableBufferPointer<UInt8>, source: UnsafeBufferPointer<UInt8>, encoder: LZFSE.Encoder = .reference,
                             emitsPendingMatch: Bool = false) -> Int {
        // lzvn_encode_partial
        if dst.count < minDestinationSize {
            return 0
        }
        var state = LZVNEncoder(src: source, dst: dst, encoder: encoder)
        if source.count >= minSourceSize {
            state.srcCurrentEnd = source.count - minMargin
            state.initTable()
            state.encode()
            let last = state.pending
            if emitsPendingMatch && last.m != 0 {
                _ = state.emitMatch(last)
            }
        }
        // On failure srcLiteral stays behind, which fails the check below.
        _ = state.emitLiteral(state.srcEnd - state.srcLiteral)
        state.dstEnd = dst.count
        _ = state.emitEndOfStream()
        return state.srcLiteral == source.count ? state.dst : 0
    }

    // MARK: Emitting

    /// Emits (L, 0, 0) instructions for the `l` bytes at `p`, at `q`. Returns the next output
    /// position, or `q1` if the output is full.
    private func emitLiteral(p: Int, q: Int, q1: Int, l: Int) -> Int {
        var p = p
        var q = q
        var l = l
        while l > 15 {
            let x = l < 271 ? l : 271
            if q + x + 10 >= q1 {
                return q1
            }
            dstBuffer.store2(q, UInt16(truncatingIfNeeded: 0xE0 + ((x - 16) << 8)))
            q += 2
            l -= x
            dstBuffer.copy(q, from: src, p, count: x)
            q += x
            p += x
        }
        if l > 0 {
            if q + l + 10 >= q1 {
                return q1
            }
            dstBuffer[q] = UInt8(truncatingIfNeeded: 0xE0 + l)
            q += 1
            dstBuffer.copy(q, from: src, p, count: l)
            q += l
        }
        return q
    }

    /// Emits (L, M, D) instructions, M >= 3, for the literal at `p` and the match after it, at
    /// `q`. Returns the next output position, or `q1` if the output is full.
    private func emit(p: Int, q: Int, q1: Int, l: Int, m: Int, d: Int, dPrev: Int) -> Int {
        var p = p
        var q = q
        var l = l
        var m = m
        while l > 15 {
            let x = l < 271 ? l : 271
            if q + x + 10 >= q1 {
                return q1
            }
            dstBuffer.store2(q, UInt16(truncatingIfNeeded: 0xE0 + ((x - 16) << 8)))
            q += 2
            l -= x
            dstBuffer.copy(q, from: src, p, count: x)
            q += x
            p += x
        }
        if l > 3 {
            if q + l + 10 >= q1 {
                return q1
            }
            dstBuffer[q] = UInt8(truncatingIfNeeded: 0xE0 + l)
            q += 1
            dstBuffer.copy(q, from: src, p, count: l)
            q += l
            p += l
            l = 0
        }
        var x = m <= 10 - 2 * l ? m : 10 - 2 * l
        m -= x
        // M = (x + 3) + M', x is at most 7 - 2 * L.
        x -= 3

        // A relaxed capacity test covering every case; fewer than 4 literals remain.
        if q + 8 >= q1 {
            return q1
        }

        if d == dPrev {
            if l == 0 {
                dstBuffer[q] = UInt8(truncatingIfNeeded: 0xF0 + (x + 3))
            } else {
                dstBuffer[q] = UInt8(truncatingIfNeeded: (l << 6) + (x << 3) + 6)
            }
            q += 1
        } else if d < 2048 - 2 * 256 {
            // Short distance: D >> 8 in 0...5.
            dstBuffer[q] = UInt8(truncatingIfNeeded: (d >> 8) + (l << 6) + (x << 3))
            dstBuffer[q + 1] = UInt8(truncatingIfNeeded: d)
            q += 2
        } else if d >= (1 << 14) || m == 0 || (x + 3) + m > 34 {
            // Long distance.
            dstBuffer[q] = UInt8(truncatingIfNeeded: (l << 6) + (x << 3) + 7)
            dstBuffer.store2(q + 1, UInt16(truncatingIfNeeded: d))
            q += 3
        } else {
            // Medium distance.
            x += m
            m = 0
            dstBuffer[q] = UInt8(truncatingIfNeeded: 0xA0 + (x >> 2) + (l << 3))
            dstBuffer.store2(q + 1, UInt16(truncatingIfNeeded: d << 2 | (x & 3)))
            q += 3
        }
        dstBuffer.copy(q, from: src, p, count: l)
        q += l

        // The rest of the match.
        while m > 15 {
            if q + 2 >= q1 {
                return q1
            }
            let x = m < 271 ? m : 271
            dstBuffer.store2(q, UInt16(truncatingIfNeeded: 0xF0 + ((x - 16) << 8)))
            q += 2
            m -= x
        }
        if m > 0 {
            if q + 1 >= q1 {
                return q1
            }
            dstBuffer[q] = UInt8(truncatingIfNeeded: 0xF0 + m)
            q += 1
        }
        return q
    }

    /// `lzvn_emit_match`. Returns false, leaving the state unchanged, if the output is full.
    private mutating func emitMatch(_ match: LZVNMatch) -> Bool {
        let q = emit(p: srcLiteral, q: dst, q1: dstEnd, l: match.mBegin - srcLiteral, m: match.m, d: match.d, dPrev: dPrev)
        if q >= dstEnd {
            return false
        }
        dPrev = match.d
        dst = q
        srcLiteral = match.mEnd
        return true
    }

    /// `lzvn_emit_literal`. Returns false, leaving the state unchanged, if the output is full.
    private mutating func emitLiteral(_ n: Int) -> Bool {
        let q = emitLiteral(p: srcLiteral, q: dst, q1: dstEnd, l: n)
        if q >= dstEnd {
            return false
        }
        dst = q
        srcLiteral += n
        return true
    }

    /// `lzvn_emit_end_of_stream`: the end-of-stream opcode 0x06 and 7 bytes of padding.
    private mutating func emitEndOfStream() -> Bool {
        if dstEnd < dst + 8 {
            return false
        }
        dstBuffer.store8(dst, 0x06)
        dst += 8
        return true
    }

    // MARK: Matching

    /// `hash3i`: hash of the 3 low bytes of `i`, in 0..<hashValues; libcompression multiplies
    /// them by Knuth's 2654435761 and keeps the top 14 bits instead.
    @inline(__always)
    private func hash3(_ i: UInt32) -> Int {
        let i = i & 0xFF_FFFF
        if knuthHash {
            return Int((i &* 2_654_435_761) >> (32 - UInt32(Self.hashBits)))
        }
        let h = (i &* (1 + (1 << 6) + (1 << 12))) >> 12
        return Int(h & UInt32(Self.hashValues - 1))
    }

    /// `trailing_zero_bytes`: the number (0...4) of zero bytes in `x` from the least significant.
    @inline(__always)
    private static func trailingZeroBytes(_ x: UInt32) -> Int {
        x == 0 ? 4 : x.trailingZeroBitCount >> 3
    }

    /// `nmatch4`: the number (0...4) of equal bytes at `i` and `j`.
    @inline(__always)
    private func nmatch4(_ i: Int, _ j: Int) -> Int {
        Self.trailingZeroBytes(src.load4(i) ^ src.load4(j))
    }

    /// `lzvn_find_matchN`: the match of the bytes at `mBegin` with those at `m0Begin`, which
    /// `n` bytes are known to match (n <= 4), expanded forward and backward over the literal
    /// that starts at `lBegin`, or nil if it is shorter than 3 bytes or out of reach.
    private func findMatch(lBegin: Int, m0Begin: Int, mBegin: Int, n: Int) -> LZVNMatch? {
        if n < 3 {
            return nil
        }
        let d = mBegin - m0Begin
        if d <= 0 || d > Self.maxDistance {
            return nil
        }

        var n = n
        var mEnd = mBegin + n
        while n == 4 && mEnd + 4 < srcEnd {
            n = nmatch4(mEnd, mEnd - d)
            mEnd += n
        }

        var m0Begin = m0Begin
        var mBegin = mBegin
        while m0Begin > srcBegin && mBegin > lBegin && src[mBegin - 1] == src[m0Begin - 1] {
            m0Begin -= 1
            mBegin -= 1
        }

        let m = mEnd - mBegin
        return LZVNMatch(mBegin: mBegin, mEnd: mEnd, m: m, d: d, k: m - (d < 0x600 ? 2 : 3))
    }

    /// The `UPDATE` macro: whether `candidate` replaces `best`.
    @inline(__always)
    private static func isBetter(_ candidate: LZVNMatch, than best: LZVNMatch) -> Bool {
        candidate.k > best.k || (candidate.k == best.k && candidate.mEnd > best.mEnd + 1)
    }

    // MARK: Encoding

    /// `lzvn_init_table`: every entry points at the first position the table may reference.
    private func initTable() {
        let index = max(-Self.maxDistance, srcBegin)
        tableIndices.initialize(repeating: Int32(truncatingIfNeeded: index))
        tableValues.initialize(repeating: src.load4(index))
    }

    /// `lzvn_encode`: encodes up to `srcCurrentEnd`, stopping when the output is full. The
    /// pending match is not emitted.
    private mutating func encode() {
        while srcCurrent < srcCurrentEnd {
            let vi = src.load4(srcCurrent)
            let entry = hash3(vi) * 4

            // Still in a previously emitted match: no search.
            if srcCurrent >= srcLiteral {
                var incoming = LZVNMatch()

                // Candidates in order, closest first.
                for k in 0..<4 {
                    let ik = Int(tableIndices[entry + k])
                    let nk = Self.trailingZeroBytes(tableValues[entry + k] ^ vi)
                    if let candidate = findMatch(lBegin: srcLiteral, m0Begin: ik, mBegin: srcCurrent, n: nk),
                       Self.isBetter(candidate, than: incoming) {
                        incoming = candidate
                    }
                }

                // The candidate at the previous distance, whose distance costs nothing.
                if dPrev != 0 {
                    let m0Begin = srcCurrent - dPrev
                    if var candidate = findMatch(lBegin: srcLiteral, m0Begin: m0Begin, mBegin: srcCurrent, n: nmatch4(srcCurrent, m0Begin)) {
                        candidate.k = candidate.m - 1
                        if Self.isBetter(candidate, than: incoming) {
                            incoming = candidate
                        }
                    }
                }

                if incoming.m == 0 {
                    // With no incoming match and too many pending literals, emit the pending
                    // match, or the longest literal.
                    if srcCurrent - srcLiteral >= Self.maxLiteralBacklog {
                        if pending.m != 0 {
                            if !emitMatch(pending) {
                                return
                            }
                            pending = LZVNMatch()
                        } else if !emitLiteral(271) {
                            return
                        }
                    }
                } else if pending.m == 0 {
                    pending = incoming
                } else if pending.mEnd <= incoming.mBegin {
                    // No overlap: emit pending, keep incoming.
                    if !emitMatch(pending) {
                        return
                    }
                    pending = incoming
                } else {
                    // Overlap: emit the better one, discard the other.
                    if incoming.k > pending.k {
                        pending = incoming
                    }
                    if !emitMatch(pending) {
                        return
                    }
                    pending = LZVNMatch()
                }
            }

            // Committed only after emitting, so that a full output leaves the table as it was.
            for k in stride(from: 3, to: 0, by: -1) {
                tableIndices[entry + k] = tableIndices[entry + k - 1]
                tableValues[entry + k] = tableValues[entry + k - 1]
            }
            tableIndices[entry] = Int32(truncatingIfNeeded: srcCurrent)
            tableValues[entry] = vi
            srcCurrent += 1
        }
    }
}
