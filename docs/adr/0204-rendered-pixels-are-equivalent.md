# ADR 0204: rendered pixels are equivalent

- Status: accepted (the owner's B-211 decision, 2026-10-30; extended by the B-213 decision the
  same day to colors converted from a PNG's color profile, on 2026-11-02 to PDF images: their
  rasters and the color profiles Quartz embeds in their vector renditions, and on 2026-11-03 to
  the font subsets in those renditions, which must render alike)
- Date: 2026-10-30

## Context

Some of actool's outputs are pixels drawn by Apple's renderers rather than copied from the
catalog's files: Icon Composer icons rendered at 1,024 pixels in each appearance and the icon
PNGs drawn from them, SVG images and symbol-set glyphs rasterized at each scale, and app icons
resized from a 1,024-pixel image (B-211), and the colors of PNGs whose ICC profile is not sRGB
IEC61966-2.1, which actool converts to sRGB with ColorSync (B-213). Reproducing them exactly would mean reimplementing
CoreSVG, IconServices and ImageIO's resampling from observation. The owner decided that these
pixels are *equivalent*: nomac draws them with a renderer of its own, every other byte of
`Assets.car` and of the icon PNGs stays identical to actool's, and `nomac verify` judges the
difference equivalent where, and only where, this ADR says so.

## Decision

nomac renders these images itself. `nomac verify` (`AssetCatalogComparison`) accepts a
difference in rendered pixels only in the files and fields listed here; each kind of rendered
image is added to the list when nomac renders it, with the rule that recognises it.

| Output | Recognised by | May differ | Must be identical |
|---|---|---|---|
| An Icon Composer icon's rendered image in `Assets.car` | a part-220 rendition whose identifier also has an icon stack (part 245) and whose name is `<icon><size>_<appearance>_<UUID>-<digits>-<16 hex digits>.png`, in both files | the rendition's length (CSI offset 180) and its payload after the first 12 bytes (the compressed pixels) | the CSI header up to offset 180 (with the name's end masked, ADR 0203), its properties, the payload's `CELM` tag, flags and compression; the rendition's key and its block's number |
| An image rasterized from an SVG or PDF file or a symbol glyph | an image or link rendition with CSI flag 0x4 (the vector renditions, layout 9, are compared byte for byte, but for a PDF's below); and the atlas a link rendition of such an image points to | the rendition's length and its payload after the first 12 bytes | the CSI header up to offset 180 (its size, flags and slices included), its properties, the payload's first 12 bytes, the rendition's key and block number |
| A HEIC image's decoded pixels | a rendition of pixel format `RGB5` or `ARGB` whose CSI name is a `.heic` file | as for rasterized images (libheif's `heif-dec` decodes the HEVC data, exact by the standard; the color conversion, the 16-bit storing and the JPEG coding of images with alpha are nomac's) | as for rasterized images; the HEIF rendition (target 2) is compared byte for byte |
| A PDF image's vector rendition (the page as Quartz writes it again, docs/formats/asset-catalog.md "PDF images") | a layout 9 rendition with pixel format `PDF ` | the rendition's length; in its PDF (after the `DWAR` payload's LZFSE), the bytes and `/Length` of each ICC profile stream (`/N n /Alternate …`), which nomac writes from the public definitions where Quartz embeds Apple's sRGB, gray and Generic RGB (a transparency group's) profiles; the bytes and lengths of each font program (`<< /Length1 … >>`, `<< /Subtype /Type1C … >>`), which nomac subsets itself from the font the PDF embeds; the 16 hexadecimal digits of a font named `font…` (Quartz's name for a font without a PostScript name, taken from memory); and the byte offsets of the cross-reference table and `startxref`, which they move | the CSI header up to offset 180, its properties, every other byte of the PDF (profiles a PDF brings with it are carried byte for byte) |
| A PDF image's RGB JPEG drawn with a soft mask, which Quartz decodes (the owner's decision of 2026-11-03) | in a PDF image's vector rendition, an 8-bit image XObject with `/SMask` stored with `/FlateDecode` | its `/Length`, and its samples where each differs from Xcode's, once both are premultiplied by the mask's alpha (rounded to 8 bits), by at most 9: the largest difference measured between Quartz's decode and nomac's (`images-4`: JPEGs sips wrote at qualities 100, 80, 50 and 20, 4:4:4 and 4:2:0; 9 at quality 50, 7 where the mask is opaque). nomac does not repeat Quartz's premultiplied round trip, which the bound covers | the number of samples, the mask's samples, and everything the PDF row keeps |
| An image from a PNG with a color profile other than sRGB IEC61966-2.1 (its sRGB rendition and, for colors well outside sRGB, its display-gamut-1 `RGBW` one) | a rendition whose CSI name is the file name of a PNG with such an `iCCP` profile in an image or app icon set of the task's catalogs (for build products: of the source checkout), and whose facet name's last component is that set's folder name; and the atlas a link rendition of such an image points to (property 1010) | the rendition's length and its payload after the first 12 bytes | the CSI header up to offset 180, its properties, the payload's first 12 bytes, the rendition's key and block number |
| An icon PNG drawn from an Icon Composer icon | a `.png` output named `<icon><width>x<height>[@<n>x][~<idiom>].png`, where `<icon>` is the name of an icon stack in Xcode's `Assets.car` beside it | the `IDAT` chunks (their number and contents), the last field of `iDOT` (the offset of the second half of the image data) | the signature, every other chunk, their order and their contents (`CgBI`, `IHDR`, `gAMA`, `sRGB`, `cHRM`, `eXIf`, `iDOT`'s other fields, `IEND`) |
| An icon PNG resized from a single-size app icon | a `.png` output named `<set><width>x<height>[@<n>x][~<idiom>].png`, where `<set>` names a facet in Xcode's `Assets.car` beside it whose app icon images (part 220) are all 1,024 pixels wide | as for Icon Composer icon PNGs | as for Icon Composer icon PNGs |

Everything else in the two files must be identical after ADR 0203's steps: the BOM layout, the
number of blocks, every other block, the variables. A `.car` whose only differences are those
listed is *equivalent*, with "pixels nomac's renderer draws" named as the cause.

## Consequences

- `nomac verify` does not measure how close nomac's pixels are to actool's; that is judged in
  the renderer's own experiments (docs/formats/asset-catalog.md "Icon Composer icons"), not
  hidden behind the comparison. The comparison guarantees that nothing but the listed pixels
  differs.
- Because the rendered images' payloads change size, the blocks after them move: the
  comparison is block by block, with each file's layout checked against the documented one, so
  a layout difference still counts.
- nomac converts profiles by the ICC specification (matrix/TRC profiles: curves, colorants, the
  D50 connection space, sRGB's inverted colorants and curve, rounding to the nearest; `ICCProfile`),
  then premultiplies as for other PNGs. The icon PNGs of an app icon set keep the image's own
  pixels and its profile, as actool's do, so they stay byte for byte. ColorSync's results differ by at most 1 or 2 in some
  values (docs/formats/asset-catalog.md, "Color profiles"); profiles with lookup tables stop
  nomac (B-213).
- A PDF's font subsets may differ only in their bytes: `pdf_experiments.py` renders actool's and
  nomac's PDFs with Quartz (CoreGraphics) at 50 times their size wherever a font is embedded and
  requires every pixel to match (all 85 renditions of `fonts` to `fonts-6` and `cff` to
  `cff-3`, and the 42 corpus sets with embedded TrueType or CFF text that nomac compiles to an
  equivalent Assets.car). Fonts a PDF names without embedding them are
  macOS's, not part of Xcode, and stay refused (the owner's decision, 2026-11-03).
- Symbol glyphs' rasters are recognised as SVG images' are (CSI flag 0x4); single-size app icon sets' own 1,024-pixel images are stored as they are and compared byte for byte.
