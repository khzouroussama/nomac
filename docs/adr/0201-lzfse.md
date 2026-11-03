# ADR 0201: LZFSE and LZVN from a Swift port of Apple's open-source reference encoder

- Status: accepted (applies ADR 0001)
- Date: 2026-10-21

## Context

actool compresses image data in `Assets.car` with LZFSE: deepmap2 data is an LZFSE stream
(`bvx2` blocks), or a raw LZVN stream for small inputs (docs/formats/asset-catalog.md,
"Images"). nomac must write the same bytes on Linux.

Apple publishes LZFSE's reference implementation (github.com/lzfse/lzfse, BSD-3-Clause,
commit e634ca58b4821d9f3d560cdc6df5dec02ffc93fd). On the owner's Mac, its encoder
(`lzfse -encode`) and libcompression (`compression_tool -encode -a lzfse`) produce exactly the
streams actool wrote for every image tried (a 300×200 gradient, a 74×68 atlas), and the
LZVN payload of a small image is the body of the reference encoder's `bvxn` block. LZFSE's
output is a function of its encoder's choices (hash table, match search, FSE normalization),
so another LZFSE implementation would decode the same data but not reproduce the bytes.

ADR 0001 keeps nomac in Swift and lets other languages in only as subprocesses. Linking the C
reference would contradict it; running it as a subprocess would add a native tool to install
for every user.

## Decision

- The encoder (raw, LZVN and LZFSE blocks, the choice between them, the end marker) and the
  LZVN encoder are ported line for line to Swift in their own module, `NomacLZFSE`, keeping
  the reference's constants, hash function, tie-breaking and table normalization. The module
  keeps Apple's copyright notice and license (`LICENSE.txt`) and records the upstream commit
  and the ported files in `UPSTREAM.md`, as `VendoredPackagePIFBuilder` does for SwiftPM.
- The port is correct only if it is byte-identical to the reference encoder. Its tests check
  the digests of the reference's output for generated inputs across the block-type thresholds;
  a differential run against the reference on several hundred inputs is part of any change to
  the module.
- Only the encoder is ported; nomac never needs to decompress LZFSE.

## Consequences

- `NomacLZFSE` has no dependencies and builds on Linux and macOS.
- If a later Xcode's actool stops matching the reference (a libcompression change), the
  `assets-experiments` image cases show it, and the port follows the observed encoder rather
  than the reference.

## Update, 2026-10-22: libcompression is not the reference

Inputs with long runs of literals showed the expected difference: libcompression's
`compression_encode_buffer` makes `lzfse_encode_base` emit pending literals once more than
3 × `LZFSE_ENCODE_MAX_L_VALUE` (945) accumulate, where the reference waits for 8 × (2,520).
It matches 402 of 402 inputs chosen to be sensitive to that value (the reference 41 of 60).
Its LZVN hashes each 3-byte value with Knuth's multiplicative hash, `(i × 2654435761) >> 18`,
where the reference uses `(i × 4161) >> 12`: with that change the reference matches
`compression_encode_buffer(COMPRESSION_LZVN)` on 106,000 generated inputs of 8 to 65,536
bytes and on the 55 LZVN streams actool wrote that were tried (the reference on 38). Everything
else is the reference's. `LZFSE.encode(_:encoder:)` takes `.reference` (the
default, which the module's tests compare with `lzfse -encode`) or `.libcompression`, which
nomac's actool uses for deepmap2.

Its streaming API (`compression_stream`), which actool uses for app icons and for the image
variants of deployment targets before 13.0, is the same encoder driven over windows with an
output buffer (docs/formats/asset-catalog.md, "Deployment-target variants"). `LZFSE.encodeStream`
drives the port the same way: a lookahead of 400 bytes in windows but the last, a destination
end that moves as the output buffer drains, and the reference's state restore when a block does
not fit, which the buffer API never needed. It matches libcompression's streams for generated
inputs and actool's for uncloudnotes' icons.
