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

// Swift port of the encoder parts of src/lzfse_internal.h, src/lzfse_tunables.h and src/lzfse_encode_tables.h.

/// Block magic numbers, stored little-endian at the start of each block.
enum BlockMagic {
    /// `bvx$`: end of stream.
    static let endOfStream: UInt32 = 0x2478_7662
    /// `bvx-`: raw data.
    static let uncompressed: UInt32 = 0x2D78_7662
    /// `bvx2`: LZFSE compressed, compressed tables.
    static let compressedV2: UInt32 = 0x3278_7662
    /// `bvxn`: LZVN compressed.
    static let compressedLZVN: UInt32 = 0x6E78_7662
}

/// The constants of lzfse_internal.h and the tunables of lzfse_tunables.h.
enum LZFSEConstant {
    static let hashBits = 14
    static let hashValues = 1 << hashBits
    static let hashWidth = 4
    static let goodMatch: UInt32 = 40
    static let lzvnThreshold = 4096

    static let lSymbols = 20
    static let mSymbols = 20
    static let dSymbols = 64
    static let literalSymbols = 256
    static let lStates = 64
    static let mStates = 64
    static let dStates = 256
    static let literalStates = 1024
    static let matchesPerBlock = 10_000
    static let literalsPerBlock = 4 * matchesPerBlock

    static let maxLValue = 315
    static let maxMValue = 2359
    static let maxDValue = 262_139

    /// `sizeof(lzfse_compressed_block_header_v2)`, with every frequency stored on 16 bits.
    static let v2HeaderCapacity = 752
    /// `sizeof(lzvn_compressed_block_header)`.
    static let lzvnHeaderSize = 12
    /// `sizeof(uncompressed_block_header)`.
    static let uncompressedHeaderSize = 8
}

/// How L (literal length), M (match length) and D (match distance) values split into an
/// FSE-encoded symbol and raw extra bits.
enum LMD {
    static let lExtraBits: [Int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 3, 5, 8]
    static let lBaseValue: [Int32] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 20, 28, 60]
    static let mExtraBits: [Int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 5, 8, 11]
    static let mBaseValue: [Int32] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 24, 56, 312]
    static let dExtraBits: [Int] = [
        0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3,
        4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 6, 6, 7, 7, 7, 7,
        8, 8, 8, 8, 9, 9, 9, 9, 10, 10, 10, 10, 11, 11, 11, 11,
        12, 12, 12, 12, 13, 13, 13, 13, 14, 14, 14, 14, 15, 15, 15, 15,
    ]
    static let dBaseValue: [Int32] = [
        0, 1, 2, 3, 4, 6, 8, 10, 12, 16,
        20, 24, 28, 36, 44, 52, 60, 76, 92, 108,
        124, 156, 188, 220, 252, 316, 380, 444, 508, 636,
        764, 892, 1020, 1276, 1532, 1788, 2044, 2556, 3068, 3580,
        4092, 5116, 6140, 7164, 8188, 10236, 12284, 14332, 16380, 20476,
        24572, 28668, 32764, 40956, 49148, 57340, 65532, 81916, 98300, 114684,
        131068, 163836, 196604, 229372,
    ]

    /// `l_base_from_value`, whose table maps each value to the last symbol whose base is not above it.
    static func lSymbol(_ value: UInt32) -> Int {
        switch value {
        case 0..<16: Int(value)
        case 16..<20: 16
        case 20..<28: 17
        case 28..<60: 18
        default: 19
        }
    }

    /// `m_base_from_value`, whose table maps each value to the last symbol whose base is not above it.
    static func mSymbol(_ value: UInt32) -> Int {
        switch value {
        case 0..<16: Int(value)
        case 16..<24: 16
        case 24..<56: 17
        case 56..<312: 18
        default: 19
        }
    }

    /// `d_base_from_value`.
    static func dSymbol(_ value: Int32) -> Int {
        let index: Int32 = switch value {
        case 0..<60: value
        case 60..<1020: ((value - 60) >> 4) + 64
        case 1020..<16380: ((value - 1020) >> 8) + 128
        case 16380..<262_140: ((value - 16380) >> 12) + 192
        default: 0
        }
        return Int(dSymbolTable[Int(index & 255)])
    }

    private static let dSymbolTable: [UInt8] = [
        0, 1, 2, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 8, 8, 9, 9,
        9, 9, 10, 10, 10, 10, 11, 11, 11, 11, 12, 12, 12, 12, 12, 12, 12, 12,
        13, 13, 13, 13, 13, 13, 13, 13, 14, 14, 14, 14, 14, 14, 14, 14, 15, 15,
        15, 15, 15, 15, 15, 15, 16, 16, 16, 16, 16, 17, 18, 19, 20, 20, 21, 21,
        22, 22, 23, 23, 24, 24, 24, 24, 25, 25, 25, 25, 26, 26, 26, 26, 27, 27,
        27, 27, 28, 28, 28, 28, 28, 28, 28, 28, 29, 29, 29, 29, 29, 29, 29, 29,
        30, 30, 30, 30, 30, 30, 30, 30, 31, 31, 31, 31, 31, 31, 31, 31, 32, 32,
        32, 32, 32, 33, 34, 35, 36, 36, 37, 37, 38, 38, 39, 39, 40, 40, 40, 40,
        41, 41, 41, 41, 42, 42, 42, 42, 43, 43, 43, 43, 44, 44, 44, 44, 44, 44,
        44, 44, 45, 45, 45, 45, 45, 45, 45, 45, 46, 46, 46, 46, 46, 46, 46, 46,
        47, 47, 47, 47, 47, 47, 47, 47, 48, 48, 48, 48, 48, 49, 50, 51, 52, 52,
        53, 53, 54, 54, 55, 55, 56, 56, 56, 56, 57, 57, 57, 57, 58, 58, 58, 58,
        59, 59, 59, 59, 60, 60, 60, 60, 60, 60, 60, 60, 61, 61, 61, 61, 61, 61,
        61, 61, 62, 62, 62, 62, 62, 62, 62, 62, 63, 63, 63, 63, 63, 63, 63, 63,
        0, 0, 0, 0,
    ]
}

// load2/load4/load8 and store2/store4/store8, little-endian whatever the host.

extension UnsafeBufferPointer<UInt8> {
    @inline(__always)
    func load4(_ i: Int) -> UInt32 {
        UInt32(self[i]) | UInt32(self[i + 1]) << 8 | UInt32(self[i + 2]) << 16 | UInt32(self[i + 3]) << 24
    }

    @inline(__always)
    func load8(_ i: Int) -> UInt64 {
        UInt64(load4(i)) | UInt64(load4(i + 4)) << 32
    }
}

extension UnsafeMutableBufferPointer<UInt8> {
    @inline(__always)
    func store2(_ i: Int, _ value: UInt16) {
        self[i] = UInt8(truncatingIfNeeded: value)
        self[i + 1] = UInt8(truncatingIfNeeded: value >> 8)
    }

    @inline(__always)
    func store4(_ i: Int, _ value: UInt32) {
        store2(i, UInt16(truncatingIfNeeded: value))
        store2(i + 2, UInt16(truncatingIfNeeded: value >> 16))
    }

    @inline(__always)
    func store8(_ i: Int, _ value: UInt64) {
        store4(i, UInt32(truncatingIfNeeded: value))
        store4(i + 4, UInt32(truncatingIfNeeded: value >> 32))
    }

    /// Copies `count` bytes of `source` from `sourceIndex` to `index`.
    @inline(__always)
    func copy(_ index: Int, from source: UnsafeBufferPointer<UInt8>, _ sourceIndex: Int, count: Int) {
        for k in 0..<count {
            self[index + k] = source[sourceIndex + k]
        }
    }
}
