# PDF images in asset catalogs: state

Workstream: PDF image sets (B-200's PDF part, B-211's PDF rasters), in `NomacAssets`
(`PDFFile`, `PDFPage`, `QuartzPDF`, `PDFProfiles`, `PDFImageSet`) and `NomacVerify`
(`PDFRenditionComparison`). BACKLOG B-215 and B-216 (resources range).

## Current step

nomac compiles PDF image sets with paths, fills, strokes, clips, form XObjects, transparency
groups, Type 3 text, text in embedded TrueType and CFF fonts, image XObjects, alpha and
luminosity soft masks with transfer functions, axial and radial shadings and shading patterns,
colors (DeviceRGB, DeviceGray, ICCBased), opacity, overprinting, smoothness, stroke adjustment
and rendering intents, and luminosity appearances: the vector rendition by Quartz's rules,
stored uncompressed as actool stores it, the rasters drawn by nomac (ADR 0204). Corpus (1,535
image sets with a PDF): 1,320 Assets.car equivalent, 196 different, 19 refused (B-215).
`pdf_experiments.py` (49 experiments): every experiment equivalent but two values exactly on a
limit (`number-values-4`, `-5`) and the refused CMYK, blend mode and CFF-in-WinAnsi cases; every
PDF with an embedded font renders pixel for pixel like actool's. Release builds compile the
slowest corpus PDF in 3.8 s of CPU (14.9 s before the rasterizer's active edges).

## Just finished

- Luminosity soft masks and transfer functions (`smasks-2`, `smasks-3`).
- What the corpus sets they reached showed: stroke adjustment (`strokes-2`); intents and
  overprinting for shadings, images and groups, the ExtGStates in number order, shadings in
  groups perceptual (`shadings-2`, `images-2`, `groups-4` to `groups-6`); PostScript functions
  run symbolically (`postscript-2`); kept functions before fonts.
- Corpus: 1,287 equivalent before, 1,320 after; 64 refused sets compile now, 49 of them still
  different (the causes in B-215).

## Next actions

1. The per-pixel shading path's speed (firefox's app icons: 15 s each in release).
2. The sets still different: firefox's resampled functions, the rounding rule; last digits
   (B-216); single causes in B-215.
3. RGB JPEGs with soft masks (an ADR 0204 decision), the rasters' opaque flag and payload.

## How to work

```sh
export DEVELOPER_DIR=/Applications/Xcode_27.app/Contents/Developer
python3 .github/scripts/pdf_experiments.py ~/nomac-out/pdf-experiments --nomac .build/debug/nomac [experiment ...]
# summary.json: per experiment, the vector renditions compared and the Assets.car comparison.
```
