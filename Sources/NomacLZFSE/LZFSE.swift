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

// Swift port of src/lzfse_encode.c, with the destination sizes of src/lzfse_main.c.

public enum LZFSE {
    /// Whose choices to reproduce: the reference's, or those of libcompression's
    /// `compression_encode_buffer` on macOS, which flushes pending literals once more than
    /// 3 × `LZFSE_ENCODE_MAX_L_VALUE` accumulate instead of 8 ×, and hashes LZVN's 3-byte
    /// values with Knuth's multiplicative hash (docs/adr/0201-lzfse.md).
    public enum Encoder: Sendable {
        case reference
        case libcompression

        var literalFlush: Int { self == .reference ? 8 * LZFSEConstant.maxLValue : 3 * LZFSEConstant.maxLValue }
    }

    /// The bytes Apple's reference `lzfse_encode_buffer` writes for `input` (bvx-/bvxn/bvx2
    /// blocks and the bvx$ end marker), as `lzfse -encode` gets them: its destination starts
    /// at the input's size and doubles until the encoder returns a nonzero size.
    ///
    /// For an empty input `lzfse -encode` never returns (its destination stays empty); this
    /// returns what `lzfse_encode_buffer` writes into any destination of 12 bytes or more.
    public static func encode(_ input: [UInt8], encoder: Encoder = .reference) -> [UInt8] {
        input.withUnsafeBufferPointer { source in
            var dstSize = source.isEmpty ? LZFSEConstant.uncompressedHeaderSize + 4 : source.count
            while true {
                let dst = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: dstSize)
                defer { dst.deallocate() }
                let size = encodeBuffer(dst: dst, source: source, encoder: encoder)
                if size > 0 {
                    return Array(dst[0..<size])
                }
                dstSize <<= 1
            }
        }
    }

    /// libcompression's `compression_stream` given all of `input` at once, as actool uses it for
    /// image data it stores without deepmap2 (docs/formats/asset-catalog.md, "Deployment-target
    /// variants"; every stream actool wrote in 19 bands of up to 22 MB): the encoder sees windows
    /// of 786,432 bytes, each next one starting 262,144 bytes before where the previous one's
    /// searches ended, which stop 400 bytes before a window's end but the last one's. Its output
    /// buffer of 786,432 bytes is half drained whenever the encoder fills it, which also moves the
    /// window to 262,144 bytes before the stop when that is more than 524,288 bytes into it.
    /// Inputs below `lzvnThreshold` get what `compression_encode_buffer` writes (uncloudnotes'
    /// one-row atlas bands).
    public static func encodeStream(_ input: [UInt8]) -> [UInt8] {
        if input.count < LZFSEConstant.lzvnThreshold {
            return encode(input, encoder: .libcompression)
        }
        let window = 786_432, history = 262_144, windowLookahead = 400, outputBuffer = 786_432
        let capacity = 2 * input.count + 65_536
        return input.withUnsafeBufferPointer { source in
            let dst = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: capacity)
            defer { dst.deallocate() }
            var state = LZFSEEncoder(source: source, dst: dst, literalFlush: Encoder.libcompression.literalFlush)
            var extent = min(window, input.count), outputStart = 0, finishing = false
            while true {
                precondition(outputStart < capacity, "LZFSE stream output exceeds its bound")
                state.dstEnd = min(outputStart + outputBuffer, capacity)
                let final = extent == input.count
                state.srcEnd = extent - state.base
                state.lookahead = final ? 8 : windowLookahead
                if finishing || state.encodeBase() {
                    if final {
                        finishing = true
                        if state.finish() {
                            return Array(dst[..<state.dstPosition])
                        }
                        outputStart += outputBuffer / 2
                    } else {
                        state.translate(state.srcEncodeEnd - history)
                        extent = min(state.base + window, input.count)
                    }
                    continue
                }
                if !final && state.srcEncodeI > 2 * history {
                    state.translate(state.srcEncodeI - history)
                    extent = min(state.base + window, input.count)
                }
                outputStart += outputBuffer / 2
            }
        }
    }

    /// `lzfse_encode_buffer_with_scratch`: the size written into `dst`, or 0 when the
    /// encoding does not fit.
    static func encodeBuffer(dst: UnsafeMutableBufferPointer<UInt8>, source: UnsafeBufferPointer<UInt8>, encoder: Encoder = .reference) -> Int {
        // LZVN refuses inputs this small.
        if source.count >= LZVNEncoder.minSourceSize {
            let size = source.count < LZFSEConstant.lzvnThreshold
                ? encodeLZVNBlock(dst: dst, source: source, encoder: encoder)
                : encodeLZFSEBlocks(dst: dst, source: source, encoder: encoder)
            if size > 0 {
                return size
            }
        }
        return encodeUncompressedBlock(dst: dst, source: source)
    }

    /// A bvxn block and the end-of-stream marker, or 0 if they do not fit or do not compress.
    private static func encodeLZVNBlock(dst: UnsafeMutableBufferPointer<UInt8>, source: UnsafeBufferPointer<UInt8>, encoder: Encoder) -> Int {
        let headerSize = LZFSEConstant.lzvnHeaderSize
        let extraSize = headerSize + 4
        if dst.count <= extraSize {
            return 0
        }
        let payload = UnsafeMutableBufferPointer(rebasing: dst[headerSize..<(dst.count - 4)])
        let size = LZVNEncoder.encodeBuffer(dst: payload, source: source, encoder: encoder)
        if size == 0 || size >= source.count {
            return 0
        }
        dst.store4(0, BlockMagic.compressedLZVN)
        dst.store4(4, UInt32(source.count))
        dst.store4(8, UInt32(size))
        dst.store4(headerSize + size, BlockMagic.endOfStream)
        return size + extraSize
    }

    /// bvx2 blocks and the end-of-stream marker, or 0 if they do not fit.
    private static func encodeLZFSEBlocks(dst: UnsafeMutableBufferPointer<UInt8>, source: UnsafeBufferPointer<UInt8>, encoder: Encoder) -> Int {
        var state = LZFSEEncoder(source: source, dst: dst, literalFlush: encoder.literalFlush)
        var srcSize = source.count
        if srcSize >= 0xFFFF_FFFF {
            // Offsets are 32-bit, so huge inputs go in chunks: the first one normally, then
            // from blockSize to 2 * blockSize, translating back by blockSize after each.
            let blockSize = 262_144
            state.srcEnd = blockSize
            if !state.encodeBase() {
                return 0
            }
            srcSize -= blockSize
            while srcSize >= blockSize {
                state.srcEnd = 2 * blockSize
                if !state.encodeBase() {
                    return 0
                }
                state.translate(blockSize)
                srcSize -= blockSize
            }
            state.srcEnd = blockSize + srcSize
        } else {
            state.srcEnd = srcSize
        }
        if !state.encodeBase() || !state.finish() {
            return 0
        }
        return state.dstPosition
    }

    /// A bvx- block with the input and the end-of-stream marker, or 0 if they do not fit.
    private static func encodeUncompressedBlock(dst: UnsafeMutableBufferPointer<UInt8>, source: UnsafeBufferPointer<UInt8>) -> Int {
        let headerSize = LZFSEConstant.uncompressedHeaderSize
        if source.count + headerSize + 4 > dst.count || source.count >= Int(Int32.max) {
            return 0
        }
        dst.store4(0, BlockMagic.uncompressed)
        dst.store4(4, UInt32(source.count))
        dst.copy(headerSize, from: source, 0, count: source.count)
        dst.store4(headerSize + source.count, BlockMagic.endOfStream)
        return source.count + headerSize + 4
    }
}
