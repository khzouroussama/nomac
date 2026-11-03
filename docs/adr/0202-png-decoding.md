# ADR 0202: PNG decoding in Swift, inflating with the system zlib

- Status: accepted (applies ADR 0001)
- Date: 2026-10-22, updated 2026-10-24 (gray, sub-byte depths, `tRNS` keys, Adam7, `gAMA`)

## Context

Image sets hold PNG files. actool stores their pixels in `Assets.car` (docs/formats/asset-catalog.md,
"Images"), so nomac must read PNGs on Linux to the same pixel values. On macOS, Foundation and
ImageIO decode PNGs; on Linux, swift-corelibs-foundation has no image decoder and no public
inflate.

What actool keeps of a PNG, observed on retro-rampage's 55 images (RGBA, RGB, and palette
images with `tRNS`; with `sRGB`, `iCCP` + `cHRM`, or only text chunks) and self-written ones:
the pixel values exactly as the PNG stores them, with no color conversion even when the file
carries an ICC profile, each color premultiplied by alpha as (c × a + 127) / 255 (all 65,536
color and alpha pairs checked), so fully transparent pixels become zeros.

## Decision

- `NomacAssets` decodes PNGs itself: the chunk structure, `IHDR`, `PLTE`, `tRNS`, the `IDAT`
  stream and the five row filters, into 8-bit RGBA. Ancillary chunks are not interpreted,
  because actool does not apply them to the pixels.
- The `IDAT` stream is inflated with the system zlib through the `CZlib` module the packaging
  workstream already uses (`zlib1g-dev` on Linux, part of macOS). zlib is the reference
  implementation of the format and decompression has one correct output, so no exactness
  question arises.
- The decoder returns the premultiplied BGRA pixels actool stores.
- Only the forms observed in actool's outputs are accepted: color types 0 (gray), 2 (RGB),
  3 (palette), 4 (gray and alpha) and 6 (RGBA) at bit depth 8, and gray and palettes at 1, 2
  and 4 bits, a gray sample scaled to 0–255 (times 255, 85 or 17); `tRNS` palette alphas and
  gray and RGB keys, a pixel equal to the key being transparent; Adam7 interlacing, which
  gives the same pixels; `gAMA` 45,454 and 45,455 (1/2.2), which change nothing, as an ICC
  profile does not on gray images either (tofu's). Compared with actool on self-written PNGs of
  each form (`images`, png-forms) and on 8-bit RGBA PNGs of the expected pixels.
- 16-bit images stop with an error naming BACKLOG B-209: actool stores other values than the
  high byte or the rounded one, and gives a 16-bit gray image a second, `GA16` rendition. So
  does any other gamma: 0.5 and 1.0 change the pixels.

Amended after tofu's compile (docs/formats/asset-catalog.md, "Color profiles"): the absence of
conversion holds for the sRGB IEC61966-2.1 profile, the one retro-rampage's catalog images
carry, and for gray images; actool converts the colors of color images with other profiles.
The decoder now reads `iCCP` and stops (BACKLOG B-213) unless the profile is that one.

## Consequences

- No new dependency: `CZlib` and zlib are already required on Linux.
- Gray pixels are stored as `GA8` (docs/formats/asset-catalog.md, "Images").
