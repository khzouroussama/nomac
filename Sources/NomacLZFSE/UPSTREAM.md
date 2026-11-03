# Ported: the reference LZFSE encoder

This module is a Swift port of the encoder of Apple's reference LZFSE implementation
(https://github.com/lzfse/lzfse), commit `e634ca58b4821d9f3d560cdc6df5dec02ffc93fd`, licensed
under the BSD 3-Clause license (`LICENSE.txt` in this directory, Copyright (c) 2015-2016 Apple
Inc.). Each ported file keeps Apple's copyright notice.

The port must stay byte-identical to the reference encoder: Xcode's actool writes the same
bytes as `lzfse -encode`, so every block choice, hash, tie-break and frequency normalization
is the reference's.

| File here | Upstream path |
|---|---|
| `LZFSE.swift` | `src/lzfse_encode.c`, and the destination sizes of `src/lzfse_main.c` |
| `LZFSEEncoder.swift` | `src/lzfse_encode_base.c` |
| `FSE.swift` | `src/lzfse_fse.c`, `src/lzfse_fse.h` (encoder parts) |
| `LZFSEInternal.swift` | `src/lzfse_internal.h`, `src/lzfse_tunables.h`, `src/lzfse_encode_tables.h` (encoder parts) |
| `LZVNEncoder.swift` | `src/lzvn_encode_base.c`, `src/lzvn_encode_base.h` |

## Differences from the C code

None in the bytes written with `LZFSE.Encoder.reference`. `.libcompression` changes two
things, as libcompression on macOS does (docs/adr/0201-lzfse.md): `lzfse_encode_base` emits
pending literals past 3 × `LZFSE_ENCODE_MAX_L_VALUE` instead of 8 ×, and LZVN's `hash3i` is
`(i * 2654435761) >> (32 - LZVN_ENCODE_HASH_BITS)`. In the code:

- Unaligned loads and stores are little-endian byte assembly, so the port does not depend on
  the host's byte order.
- Bytes the reference writes past its output position and then overwrites (8-byte FSE
  flushes, 16-byte literal copies) are not written.
- The FSE streams are the 64-bit ones the reference uses on 64-bit hosts.
- `lzfse_encode_matches` does not restore its state when the destination is full: every
  caller then abandons the LZFSE attempt.
- The decoder is not ported. `LZFSEDecoder.swift` is nomac's own, written from the format the
  encoders here write (the inverse of their FSE streams, v2 block header and LZVN opcodes), and
  checked on their outputs and on Xcode's `nlu.lzfse` against macOS's `compression_tool`.
