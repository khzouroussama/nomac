# PDF images in asset catalogs: state

Workstream: PDF image sets (B-200's PDF part, B-211's PDF rasters), in `NomacAssets`
(`PDFFile`, `PDFPage`, `QuartzPDF`, `PDFProfiles`, `PDFImageSet`) and `NomacVerify`
(`PDFRenditionComparison`). BACKLOG B-215 and B-216 (resources range).

## Current step

nomac compiles PDF image sets with paths, fills, strokes, clips, form XObjects, transparency
groups, Type 3 text, text in embedded TrueType and CFF fonts, image XObjects (TIFF predictor 2,
soft masks with a Matte, RGB JPEGs with a soft mask decoded as Quartz does), alpha and
luminosity soft masks with transfer functions, axial and radial shadings and shading patterns,
colors (DeviceRGB, DeviceGray, ICCBased, DeviceCMYK grays as actool's rasters show them),
opacity, overprinting, smoothness, stroke adjustment and rendering intents, luminosity
appearances and a PDF per idiom: the vector rendition by Quartz's rules, stored uncompressed as
actool stores it, the rasters drawn by nomac (ADR 0204). Corpus (1,535 image sets with a PDF):
1,328 Assets.car equivalent (5 identical), 201 different, 6 refused (B-215). The slowest
firefox app icon compiles in 14.9 s of CPU in release (88 s before), output unchanged (110
experiment cars and 80 corpus sets byte for byte).

## Just finished

- `assets/pdf-10`: shading speed; a PDF per idiom (`entries-2`); TIFF predictor 2 and `/Matte`
  (`images-3`); DeviceCMYK grays from a table measured on actool's rasters (`cmyk-k`; other
  CMYK colors refused, the owner's decision of 2026-11-03); RGB JPEGs with a soft mask decoded,
  chroma upsampled inside each 8×8 block, compared within ADR 0204's measured bound of 9
  premultiplied (`images-4`, the owner's decision of 2026-11-03).
- Corpus: 1,320 equivalent before, 1,328 after; refused 19 before, 6 after.

## Next actions

1. The 7 firefox onboarding sets whose only difference is decoded JPEG samples beyond the bound
   (`onboardingSyncWithIconsJapan`, `onboardingToolbarIcon{Bottom,Top}Japan[Selected]`,
   `onboardingTrackersBrandRefresh`, `onboardingWelcomeJapan`): find what their JPEGs use that `images-4`'s do not, add it to `images-4`, match it.
2. The sets still different: firefox's resampled functions, the rounding rule; last digits and
   `0.10` (B-216); `/AAPL:Style` marked content (2 wikipedia sets); single causes in B-215.
3. The single refusals: a CID font, a blend mode, another shading type, a PDF per scale; then
   the rasters' opaque flag and payload.

No run is left in progress: the corpus totals above come from a release build of this branch,
each corpus set with a PDF compiled by actool and nomac and compared by `pdf_experiments.py`'s
rules.

## How to work

```sh
export DEVELOPER_DIR=/Applications/Xcode_27.app/Contents/Developer
python3 .github/scripts/pdf_experiments.py ~/nomac-out/pdf-experiments --nomac .build/debug/nomac [experiment ...]
# summary.json: per experiment, the vector renditions compared and the Assets.car comparison.
```
