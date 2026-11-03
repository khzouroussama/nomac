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

// Swift port of the encoder parts of src/lzfse_fse.c and src/lzfse_fse.h.

/// `fse_encoder_entry`: how one symbol updates the encoder state.
struct FSEEncoderEntry {
    /// First state requiring a K-bit shift.
    var s0: Int16 = 0
    /// States S >= S0 are shifted K bits. States S < S0 are shifted K-1 bits.
    var k: Int16 = 0
    /// Relative increment used to compute the next state if S >= S0.
    var delta0: Int16 = 0
    /// Relative increment used to compute the next state if S < S0.
    var delta1: Int16 = 0
}

/// `fse_out_stream64`, the stream the reference uses on 64-bit hosts. The bits it writes do
/// not depend on the accumulator width.
struct FSEOutStream {
    var accum: UInt64 = 0
    /// Number of valid bits in `accum`; the other bits are 0.
    var accumNBits = 0

    /// `fse_out_push64`: accumulates the `n` bits of `b`.
    @inline(__always)
    mutating func push(_ n: Int, _ b: UInt64) {
        accum |= b &<< UInt64(accumNBits)
        accumNBits += n
    }

    /// `fse_out_flush64`: writes the full bytes of the accumulator at `position`, leaving 0...7 bits.
    @inline(__always)
    mutating func flush(_ buffer: UnsafeMutableBufferPointer<UInt8>, _ position: inout Int) {
        let nbits = accumNBits & -8
        write(nbits >> 3, to: buffer, &position)
        accum = accum &>> UInt64(nbits)
        accumNBits -= nbits
    }

    /// `fse_out_finish64`: writes the remaining bits, padded with 0, leaving `accumNBits` in -7...0.
    mutating func finish(_ buffer: UnsafeMutableBufferPointer<UInt8>, _ position: inout Int) {
        let nbits = (accumNBits + 7) & -8
        write(nbits >> 3, to: buffer, &position)
        accum = 0
        accumNBits -= nbits
    }

    @inline(__always)
    private func write(_ count: Int, to buffer: UnsafeMutableBufferPointer<UInt8>, _ position: inout Int) {
        for i in 0..<count {
            buffer[position + i] = UInt8(truncatingIfNeeded: accum &>> UInt64(8 * i))
        }
        position += count
    }

    /// `fse_encode`: encodes `symbol` with `table`, updating `state`.
    @inline(__always)
    mutating func encode(_ symbol: Int, _ state: inout UInt16, _ table: [FSEEncoderEntry]) {
        let s = Int(state)
        let e = table[symbol]
        let hi = s >= Int(e.s0)
        let nbits = hi ? Int(e.k) : Int(e.k) - 1
        let delta = UInt16(bitPattern: hi ? e.delta0 : e.delta1)
        push(nbits, UInt64(s & ((1 << nbits) - 1)))
        state = delta &+ UInt16(truncatingIfNeeded: s >> nbits)
    }
}

enum FSE {
    /// `fse_init_encoder_table`. `nstates` is the sum of `freq`, a power of 2; symbols with a
    /// frequency of 0 must not occur in the data.
    static func encoderTable(nstates: Int, freq: [UInt16]) -> [FSEEncoderEntry] {
        var table = [FSEEncoderEntry](repeating: FSEEncoderEntry(), count: freq.count)
        var offset = 0
        let nClz = UInt32(nstates).leadingZeroBitCount
        for i in 0..<freq.count {
            let f = Int(freq[i])
            if f == 0 {
                continue
            }
            let k = UInt32(f).leadingZeroBitCount - nClz
            // With k == 0 (one symbol takes every state) every state is >= s0 == 0, so delta1,
            // whose shift by -1 is undefined in C, is never used.
            table[i] = FSEEncoderEntry(
                s0: Int16(truncatingIfNeeded: (f << k) - nstates),
                k: Int16(k),
                delta0: Int16(truncatingIfNeeded: offset - f + (nstates >> k)),
                delta1: Int16(truncatingIfNeeded: offset - f + (k > 0 ? nstates >> (k - 1) : 0))
            )
            offset += f
        }
        return table
    }

    /// `fse_normalize_freq`: scales the occurrence counts `t` to frequencies summing to `nstates`.
    static func normalizeFreq(nstates: Int, _ t: [UInt32]) -> [UInt16] {
        var freq = [UInt16](repeating: 0, count: t.count)
        var sCount: UInt32 = 0
        var remaining = nstates
        var maxFreq = 0
        var maxFreqSym = 0
        let shift = UInt32(nstates).leadingZeroBitCount - 1

        for count in t {
            sCount &+= count
        }
        let highprecStep: UInt32 = sCount == 0 ? 0 : (1 << 31) / sCount

        for i in 0..<t.count {
            // Rounds to nearest, with integer arithmetic.
            var f = Int((((t[i] &* highprecStep) >> shift) + 1) >> 1)
            // A symbol that occurs gets a nonzero frequency.
            if f == 0 && t[i] != 0 {
                f = 1
            }
            freq[i] = UInt16(truncatingIfNeeded: f)
            remaining -= f
            if f > maxFreq {
                maxFreq = f
                maxFreqSym = i
            }
        }

        // States left over go to the most frequent symbol; a minor overrun is taken from it,
        // a major one from every symbol.
        if -remaining < (maxFreq >> 2) {
            freq[maxFreqSym] = UInt16(truncatingIfNeeded: Int(freq[maxFreqSym]) + remaining)
        } else {
            adjustFreqs(&freq, overrun: -remaining)
        }
        return freq
    }

    /// `fse_adjust_freqs`: removes states from symbols until `overrun` states are freed.
    private static func adjustFreqs(_ freq: inout [UInt16], overrun: Int) {
        var overrun = overrun
        var shift = 3
        while overrun != 0 {
            for sym in 0..<freq.count where freq[sym] > 1 {
                let n = min((Int(freq[sym]) - 1) >> shift, overrun)
                freq[sym] -= UInt16(n)
                overrun -= n
                if overrun == 0 {
                    break
                }
            }
            shift -= 1
        }
    }
}
