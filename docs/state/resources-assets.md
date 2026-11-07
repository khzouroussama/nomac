# Resources: asset catalogs (actool replacement)

Branch `res/assets`. nomac's `actool` (`nomac actool`, `Sources/NomacAssets`) compiles
`.xcassets` folders into what Xcode 27.0's actool writes: `Assets.car`, the partial
Info.plist, the dependency info and the report on standard output. The format is in
docs/formats/asset-catalog.md, the decisions in ADRs 0200, 0201 and 0202. BACKLOG range B-200–B-249, ADRs
0200–0249 (B-250–B-299 belong to nibs, strings and Core Data).

## Current step

Almost every catalog compiles: of the coverage survey's sample of 60 projects, 53 at iOS 15 and 46 of
52 at their own deployment targets; what is left is ranked under Measure and Next actions. Bytes
match actool except rendered pixels, which ADR 0204 calls equivalent, and what is measured there as
different: mostly PDF vector renditions (B-215, B-216) and large images at old targets (B-220).

## Measure

`.github/scripts/catalog_sweep.py` compiles every catalog of the corpus, the holdout, the sweep and
the coverage survey's sample of 60 projects with actool and with nomac on the same command line
(Xcode's, from the build logs, where there is one) and ranks what stops or changes the most apps.
The work order follows the sample, the only set not chosen by hand: well-kept corpus apps have
complete icon sets, and 20 of those 60 projects did not.

| 2026-11-07 | sample at iOS 15: compile all, match actool | sample at each project's own target | corpus: compile all, match, of 19 | holdout, of 20 | sweep, of 98 |
|---|---|---|---|---|---|
| main 85c5aab0 | 23, 14 of 60 | not measured | 7, 6 | 3, 2 | 95, 94 |
| this branch | 53, 51 of 60 | 46, 33 of 52 | 9, 6 | 11, 8 | 96, 94 |

Loose PNGs (`loose_png_sweep.py`): 468 of 468 files of the corpus, holdout and sample identical to
copypng, against 17 apps stopped on main.

The survey's own count was 21 of 60 with a debug binary, 3 projects timing out at 600 s. The 3 watch
catalogs it counts as refused also stop actool on its iOS command line. The column that matters
most is the own-target one: 824 of 1,413 surveyed projects (58%) target before iOS 13 (8.x 303, 9.x
149, 10.x 93, 12.x 86, 7.x 60, 11.x 65) and 23 of those 50 stop on that refusal alone.

Not covered: catalogs of apps that never built on the sweep (`rocketchat`, `graysky`, `bluesky`,
`obytes-template`, `expo-with-libsql`: 14 tasks whose catalogs `expo prebuild` or a package
writes); `expo-with-webrtc`, whose prebuild fails with the shared install; holdout and signal
catalogs compiled alone with settings from their captures, packages' catalogs left out of the
holdout; tvOS targets, which nomac does not build (B-206).

## Just finished

- Deployment targets before iOS 13 (`old-targets`): every image per variant from 8.0 up. The top cause
  at projects' own targets: 23 of 50 sampled projects stopped on it alone.
- `copypng` as Xcode's on every loose PNG measured: other depths and APNGs copied, chunks by the icon
  rules, `IDAT` of at most 524,288 bytes, files libpng cannot read reported without output.
- Launch image sets (`launch-images`), PNG gamma (`png-gamma`), tvOS brand assets on iOS, JPEG Exif as
  ImageIO writes it (`jpeg-exif`), tables past one leaf (`large-tables`), and the families in
  `catalog_rules_experiments.py`. SVG drawing over the rows a shape reaches and PDF image colors
  without per-pixel arrays: duckduckgo's `HomeMessage` catalog went from 151 s to 33 s in release.
- Incomplete app icon sets: required-icon warnings, entries without a slot, images of the wrong size,
  missing files, car icons, the error for a set of other platforms only (`incomplete-icons` 25
  cases, `icon-entries` 32). `--warnings` and `--notices` now choose what prints.
- Icon PNGs: every chunk's place, palette and low-depth inputs as plain PNGs, interlacing, halves
  from 4,096 pixels (`icon-chunks` 66 cases); `copypng` shares them.
- Damaged `iCCP` chunks no longer stop nomac; actool treats the image as untagged (`bad-profiles`).
- Image set entries: `language-direction`, `alignment-insets`, `resizing` (`image-traits`); luminosity
  with high contrast (`appearance-pairs`); PDF `DefaultRGB` and `DefaultGray` (`default-spaces`);
  `--enable-icon-stack-fallback-generation=disabled` changes nothing.

- Image set appearances (B-200): luminosity dark and light and high contrast for every image
  type, packed apart per appearance; watchOS keeps only the any appearance, images and colors;
  deepmap2 takes the planes before LZ on a tie. `assets_experiments.py image-appearances`: 2
  cases identical, 2 equivalent (SVG rasters). Corpus: mattermost 4 of 4 asset tasks
  identical; home-assistant's and mastodon's appearance sets compile; home-assistant's watch
  catalogs differ only in PDF vector renditions (stored uncompressed by actool) and rasters.
- A catalog's `generate-swift-asset-symbol-extensions` property (home-assistant):
  `symbol-extensions` 13 of 13 cases identical, home-assistant's Shared-iOS symbol files
  identical.

- Complications (B-204): `--complication` compiles the complication set it names as a
  namespace of image sets and adds `CLKComplicationDefaultImagesAssetName`; screen widths are
  watch subtypes; watch-idiom entries compile with idiom 5; app icons packed with images get
  image atlases; PDF images rasterize at 2x only on watchOS; `BITMAPKEYS` bits of 40 mm and
  42 mm corrected. `assets_experiments.py complications`: 8 of 8 cases without warnings
  identical (car, plist, deps, report, symbol files); the 4 that warn stop. pocket-casts'
  watch catalogs: plist, deps and report identical; the car differs only in its 4 PDF vector
  renditions, which actool stores uncompressed (as its 40 iOS ones) where nomac's PDF code
  compresses them (the PDF workstream's); without its PDF sets the car is equivalent.

- HEIC files with alpha: the `jpeg-lzfse` payload (`CELM` compression 5: the alpha plane in
  LZFSE, the premultiplied colors in a baseline JPEG nomac codes itself), chosen as actool does
  when it takes less than a byte per pixel, else the plain payload. `assets_experiments.py heic`
  (5 alpha cases added): car equivalent, 11 of 11 HEIF renditions identical, compression as
  actool's in 5 of 5, alpha streams and JPEG headers identical in 2 of 2. pocket-casts' two
  mockups and its avatar: car equivalent.

- HEIC image sets: decoded with libheif's `heif-dec` into `RGB5` renditions (ADR 0204's new
  row), and the file rewritten as ImageIO does for target 2 (Exif item, ipco/ipma order, ftyp
  rule, 64-bit mdat). `assets_experiments.py heic`: car equivalent, 6 of 6 HEIF renditions
  identical; the corpus's 3 HEIC files' HEIF renditions identical. README names
  `libheif-examples`.

- Multi-size watch icon sets (Xcode's watch template: roles, case-size subtypes, their mask
  bits, atlases keyed per subtype). `assets_experiments.py watchos` 3 of 3; `app-icons` 31
  unchanged. The corpus's watch icon sets sit in catalogs that also need PDF image sets.

- watchOS catalogs (B-206): platform `watch` and its authoring tool string, 1x/2x files, SVG
  rasters at 2x, symbol sets scaled 0.94634 with one 17-point 2x raster, `watchos` single-size
  icons. `assets_experiments.py watchos` 2 of 2; home-assistant's two watch widget catalogs
  equivalent; its other watch catalogs wait on PDF image sets, pocket-casts' on
  `--complication` (B-204). PNG sets with `preserves-vector-representation` get flag 0x100.

- icecubes' main catalog compiles (its HEIC image aside, next): Icon Composer icons and app icon
  sets as alternates together; 16-bit PNGs with a color profile (converted, ADR 0204; untagged
  ones stop, actool dithers them); the gamut-1 threshold measured per side (below −0.0015 or
  above 1.0078 in linear sRGB) and `RGBW` renditions packed in `-gamut1` atlases; the target
  before the display gamut in `KEYFORMAT`; an empty accent color set gives no warning. The
  scratch comparison of its whole catalog: every difference within ADR 0203/0204.

- B-213's display-gamut-1 renditions: RGB images more than 1.08% outside sRGB get an `RGBW`
  rendition (extended sRGB, premultiplied RGBA half floats, deepmap2 format 20 for image sets,
  the plain payload for app icons, never packed). `assets_experiments.py profiles` 14 of 14
  (p3 cases and a new wide case: packing beside plain images, a single-size app icon).
  icecubes' main catalog next stops on a 16-bit PNG (B-209).

- Alternate app icon sets (`--include-all-app-icons`, `--alternate-app-icon` for
  `.appiconset`): renditions as primary sets, no PNGs, the alternates listed under the icon keys
  whose device has icons. `assets_experiments.py alternate-app-icons` 13 of 13; `app-icons`
  31 and `icons` 18 unchanged. icecubes' main catalog now stops on B-213 (Display P3 alternate
  icon PNGs outside sRGB).

- SVG strokes (caps, joins, miter limits, opacity, gradient paints, `<line>`) and masks (by
  luminance, as CoreSVG does even for `mask-type` alpha; `maskUnits`, `maskContentUnits`) in
  image sets and Icon Composer layers; SVG files in a scale entry (1,144 corpus sets);
  `currentColor`, `rgba()`, CSS's named colors, unreadable paints dropped as CoreSVG does.
  `assets_experiments.py svg-masks-strokes` 15 of 15 equivalent, `svg-colors` identical,
  `vector-images` equivalent. HEIC observed: a decoded RGB565 rendition (needs HEVC decoding) and the HEIF
  re-muxed for target 2; waiting on the decoder question.

- Single-size iOS app icons (a universal 1,024-point entry, with dark and tinted appearances):
  renditions per targeted idiom, resized 60 pt and 76 pt 2x PNGs (RGBA, fixed chunks, nomac's
  pixels under ADR 0204's new row), the partial Info.plist. `assets_experiments.py
  single-size-icons`: 33 of 33 cases (targets, appearances, PNG forms,
  `--standalone-icon-behavior`), `Assets.car` and the plist identical, PNGs equivalent. firefox's
  main catalog now verifies identical (3 of its 5 asset compiles).

- `nomac copypng` (Xcode's copypng for loose PNGs; launcher `usr/bin/copypng` in the Linux
  toolchain): plain copies, CgBI and gray PNGs as actool's icon PNGs, text stripped, pngcrush's
  zlib window. `assets_experiments.py copypng`: 256 of 256 identical; corpus loose PNGs 188
  identical, 28 stop (B-214).

- Symbol sets: vector glyph renditions (the glyph's SVG as actool re-writes it, metrics,
  rendering intent) and monochrome rasters at 15/17/20 points, templates 1 to 6 (path guides,
  rectangle margins, nested and scaled glyphs, style-sheet strokes). 46 of the corpus's 47
  symbol sets equivalent compiled alone (nextcloud's template-6 layer tree stops, B-202);
  `assets_experiments.py symbol-sets`: 13 of 13 equivalent.

- JPEG image sets (stored as files: kept and dropped segments, Exif kept or dropped as ImageIO
  does, APPn order; 55 of the corpus's 64 image set JPEGs identical, 9 stop on rewritten Exif)
  and SVG image sets with and without `preserves-vector-representation` (vector rendition,
  rasterized 1x/2x/3x images with their slices, never opaque; ADR 0204's new row for them).
  `assets_experiments.py vector-images`: SVG equivalent, JPEG identical.

- `--alternate-app-icon` and `--include-all-app-icons` for Icon Composer icons: which icons
  compile, `CFBundleAlternateIcons` by target device (8 of 8 self-written cases equivalent).
  icecubes' and swiftfin's main catalogs now stop on symbol sets.

- The corpus's `.icon` files: 32 of 33 compile to actool's outputs, `Assets.car` and icon PNGs
  equivalent (firefox 3, gomap, home-assistant 2, icecubes 4, nextcloud, signal 12, swiftfin 6,
  wikipedia 3); mastodon's stops on B-213 (a Display P3 PNG layer with colors outside sRGB).
  New rules: every property's specializations per appearance (direct value wins; own, else
  base, else default; layer fills fall back to light, `automatic` defers, `none` keeps a white
  layer unfilled), group names, `color-space-for-untagged-svg-colors` (vector color model 3),
  layer PNGs opaque by format not pixels, components rounded from their double. SVG: linear
  and radial gradients (`href`, units, transforms), clip paths, simple style sheets, `skewX`,
  `color(display-p3 …)`, `inherit`, editors' attributes. Scratch `corpus-icons/run.py`.

- PNG color profiles (B-213, the owner's decision of 2026-10-30: converted pixels are
  equivalent, ADR 0204 extended): `ICCProfile` (NomacCore) reads RGB and gray matrix/TRC
  profiles and converts to sRGB IEC61966-2.1 by the ICC specification (63–92% of a million
  colors as ColorSync, the rest within 1); RGB images more than 1.08% outside sRGB stop (actool
  adds a 16-bit Display P3 rendition, B-213); icon PNGs keep the unconverted pixels and the
  profile (byte for byte); `nomac verify` finds the converted PNGs in the task's catalogs (the
  source checkout for build products) and lets only their renditions' and atlases' payloads
  differ. `assets_experiments.py profiles`: every case identical or equivalent, Display P3 and
  Adobe RGB-like million-color cubes refused.
- Speed: expo-default's catalog takes 4.6 s with a release build of nomac (21 s debug), actool
  3.2 s; the output is the same.

- Icon Composer icons (B-210, B-180): the `.icon` model (fills and their specializations,
  groups, layers, hidden layers, positions, blend modes, glass, shadows, translucency,
  lighting, blur), the colors, gradients, icon stacks, groups and layer images (SVG vector
  renditions, PNG images) byte for byte, the white-layer rule of the dark appearance (Display
  P3 lightness 0.85, 27 colors bisected), the rendered images and icon PNGs from nomac's own
  renderer (`IconRenderer`, `Rasterizer`, `SVGImage`), the partial Info.plist keys by target
  device. `assets_experiments.py icons`.
- `AssetCatalogComparison` (`NomacVerify`, used by tool checks and build products): BOM layout,
  block-by-block comparison after ADR 0200/0203's normalizations, rendered pixels per ADR 0204,
  icon PNGs by chunk. B-207 resolved.

- Sticker catalogs (B-202, B-204): the Messages App Store icon in `Assets.car`, the other icon
  sizes as PNGs, the pack folder with renamed sticker files and a binary `Info.plist`, the
  partial Info.plist keys; gray icon PNGs (plain zlib PNGs of the input's samples). firefox's
  and wikipedia's compiles give their Xcode builds' outputs.
- App icon sets `--app-icon` does not name add nothing (kickstarter's catalogs have four).
- Icon PNG metadata (B-212): `gAMA`, `sRGB`, `cHRM`, `eXIf`, `iTXt`, `pHYs` and `tEXt` copied
  in actool's order; netnewswire's widget compile gives its Xcode build's outputs.
- `template-rendering-intent` (CSI flags) and image set folders without `Contents.json`
  (skipped) for tofu, which now stops on B-213: actool converts the colors of images whose ICC
  profile is not sRGB IEC61966-2.1 (tofu's "sRGB built-in"), which the format doc and ADR 0202
  had stated otherwise. nomac now stops on those instead of writing other pixels; this is
  rendered-pixel work for the owner's B-211 decision.
- Sprite atlases (B-202): members trimmed to their non-transparent pixels (property 1011 when
  cut), packed by the same packer into `ZZZZExplicitlyPackedAsset` without the area limit,
  properties 1012/1020/1021/1022, the part-127 name list, facets without part; flappy-fly-bird's
  compile gives its Xcode build's outputs. Limits not yet bisected (large images alone, atlas
  splits) stop (B-202).
- `BITMAPKEYS` beyond 126 identifiers (B-201): actool's insertion with leaf splits keeping
  ⌈n / 2⌉ (`BOMNumberTree`), 25 catalogs of 127 to 510 names and flappy-fly-bird identical.
- Atlases of a class numbered by their indices as decimal strings (0, 1, 10, 11, 2, ...), and
  deepmap2 mode 3 in chunks of ⌊2^21 / row bytes⌋ rows: both seen first in flappy-fly-bird,
  then reproduced on self-written catalogs.
- Multi-size app icon sets (B-202): part-218 size tables (`MSIS`), part-220 images with `dim2`
  and the 60 pt 3x image's subtype-1792 copy, packed by class, stored without deepmap2 (the
  deployment-target-0 format, `PlainImagePayload`), the PNGs per `--standalone-icon-behavior`,
  `CFBundleIcons` and `CFBundleIcons~ipad`, the notices for older sizes; launch image sets
  without files. uncloudnotes' compile gives its Xcode build's `Assets.car`, PNG and partial
  Info.plist.
- CgBI icon PNGs (`IconPNG`, CZlib): flags by opacity, `iDOT` halves above 3,600 pixels, the
  `sRGB` and `tEXt` mappings; 19 corpus icons and 33 self-written ones identical. Other
  ancillary chunks and gray inputs are B-212 (netnewswire's widget needs `eXIf`/`iTXt`/`pHYs`).
- `LZFSE.encodeStream`: libcompression's `compression_stream` (windows, output-buffer stops,
  the reference's state restore on a full block, LZVN below 4,096 bytes), from the previous
  agent's C model (scratch `lzstream/enc/drv.c`, `drv_stream_actool`); identical to
  libcompression on 5 generated inputs up to 3 MB.
- The `.car` container and tables, from actool's output for self-written catalogs
  (`.github/scripts/assets_experiments.py`): the BOM layout, trees and their key copies,
  `CARHEADER`, `EXTENDED_METADATA`, `KEYFORMAT`, facet tokens, the color CSI and `COLR`
  payload, `BITMAPKEYS` masks.
- Name identifiers: a ×33 hash of the name's UTF-16 units from 100823 in 64 bits, folded by the
  same hash over its 16-bit words; collisions resolved in name order by an exclusive-or fold
  and linear probing. Found by measuring one-name catalogs character by character, then
  recovering the 64-bit seed from carry patterns (the `identifiers` experiment checks the rule
  on every name it compiles).
- Creation orders: renditions middle-first over their sorted keys; `BITMAPKEYS` values in the
  slot order of an open-addressing hash table (43 catalogs).
- actool is deterministic except for the order of the appearance-key blocks, which changes
  from run to run; comparisons put actool's in name order (ADR 0200).
- Data sets: the data CSI and its uncompressed `RAWD` payload, type identifiers from file
  extensions (41 observed), no appearance keys in a catalog of data only.
- Images of retro-rampage: the deployment-target variants and encodings 0 (`KCBC` LZFSE bands)
  and 3 (`0xCAFEF00D` palette), deepmap2 mode 4's layout, the atlas pixels and the growing
  binary-tree packer (`packing`: 38 one-atlas cases match; retro-rampage's three atlases
  reproduced); not yet the atlas split and the mode-4 color order.
- Images, observed only (no writer yet): the image CSI and its properties, the `CELM`
  payload, deepmap2 modes 1 to 4, mode 2's planes, its lossy color transform (even with
  `compression-type` `lossless`) and predictors 1, 2 and 4, atlas packing of small images, and
  what a single-size app icon produces.
- `NomacLZFSE`: Apple's open-source LZFSE and LZVN encoders ported to Swift (ADR 0201);
  identical to the reference on 399 generated inputs and to two streams actool wrote.
- `nomac check`'s `assets:` domain (ADR 0011): the catalogs a project's targets compile, read
  from their `Contents.json` files; color and data set features verified by the experiments,
  images, app icons and symbol sets outside the envelope with their BACKLOG items.
- App icon sets without image files (retro-rampage's) compile to nothing; `--app-icon` naming
  no set is actool's error, with exit status 1 (`app-icons`: 4 cases identical).
- Partial Info.plists and xml1 reports written with `NomacPlist`.
- `nomac actool`: `--compile`, `--version`, `--print-asset-tag-combinations` (catalogs without
  tags), accent colors and their warning, catalogs without renditions.
- Image sets (B-200) for deployment targets of 13.0 and later, universal 1x PNGs: the PNG
  decoder with actool's premultiplication (ADR 0202), packing by opacity and grayness, the atlas
  split (3,131 of 3,131 observed splits), placement and even atlas sizes, standalone, atlas and
  link renditions, and deepmap2: bands, the mode choice (smallest candidate when 10 bytes or
  more under raw), the palette order (357 of 357 palettes), mode 2's transform, filters, float
  costs and their ties (4,100 rows) and chunks, and libcompression's LZFSE literal threshold
  (ADR 0201). Reports list their outputs in path order.
- Asset symbols (B-204): `--generate-swift-asset-symbols`, `--generate-objc-asset-symbols`,
  `--generate-asset-symbol-index` and extensions `YES`, `NO` or not passed, for color and image
  sets: the name rules (words, type words dropped, capitals, keywords, Objective-C's ASCII
  filter), namespaces as nested enums, the two sort orders, warnings for empty, duplicate and
  conflicting symbols (the framework members a name can shadow, from every candidate in the
  SDK's headers), the iOS 17 switch to `DeveloperToolsSupport` and the fixed sections; symbol
  sets, which sets the build has something for (idioms, files, colors), thinnable sets, Icon
  Composer inputs and visionOS icon stacks, which add nothing, and icecubes' app icon options.
  All 33 `GenerateAssetSymbols` tasks of the corpus's reference builds give actool's files (31
  byte for byte, 2 but for the order of tied sets, which actool changes from run to run).
- visionOS icon stacks compile to nothing on iOS (icecubes'); SVG images observed (vector
  renditions and the sizes of their rasterized ones, docs/formats/asset-catalog.md).
- Gray images (`GA8`): gray and alpha bytes, alpha 255 in opaque images and their atlases, one
  residual per pixel in mode 2, no palette mode, row bytes of one byte per opaque pixel.
- Scales and idioms: renditions per scale and idiom, atlases per scale and idiom numbered within
  them, the packing limit of 18,050 pixels times the scale (an image at the limit still makes
  its class packable), splits at 2x and 3x, untargeted devices left out.
- `--widget-background-color` (`NSWidgetBackgroundColorName` and its warning) and
  `--standalone-icon-behavior all` and `none`, which change nothing without app icon images.
- System color references for `ios` and `universal`, light and dark: the 39 names actool
  knows, with the components it stores (iOS 26's colors), from a table observed on
  self-written catalogs.
- PNG forms (ADR 0202): gray and gray-and-alpha PNGs, 1, 2 and 4-bit gray and palettes, `tRNS`
  keys, Adam7 interlacing, `gAMA` 1/2.2.

Result (`assets_experiments.py <dir> --nomac .build/debug/nomac icons`, 2026-10-31): 12 of 12
cases match (expo-like icon with --app-icon for iPhone, iPad, both and no device and without
it, the composite icon, the fills, groups, specializations, positions, svg and white batches): `Assets.car` and the
icon PNGs equivalent (ADR 0204: only rendered pixels differ), the partial Info.plist,
dependency info and report identical; actool's two runs of the composite icon equivalent
(206 rendered pixels differed by up to 2 between them). `profiles` (2026-10-31): srgb-like
identical; table, gamma 2.2, muted Display P3 and gray-and-palette equivalent (92%, 63%, 90%
of a million colors exact, all within 1); Display P3 and Adobe RGB-like cubes refused (B-213). expo-default's own command line gives `Assets.car` block for block
actool's but for the six rendered payloads; `nomac products` against its Xcode build: 3 of 3
equivalent. nomac takes 17 s for it in a debug build, actool 5 s.

Result (`assets_experiments.py <dir> --nomac .build/debug/nomac colors data collisions
appearance-order identifiers bitmap-order`, 2026-10-21): every case identical (`Assets.car`,
partial Info.plist, dependency info, standard output): one color, eight names, every color space, appearance,
idiom, display gamut and component spelling with an accent color, a missing accent color, a
catalog without renditions, a dark-only color, namespaces, data sets (text, 25,000 bytes,
explicit type, next to colors, 41 extensions), 104 colliding names, six runs of a
three-appearance catalog, 44 catalogs of 1 to 126 names; the rule for name identifiers holds
on 583 one-name catalogs. Catalogs of 127 and more names stop with B-201's error.

Result (`assets_experiments.py <dir> --nomac .build/debug/nomac images packing`, 2026-10-22): 9
image and 47 packing cases identical (`Assets.car`, partial Info.plist, dependency info, standard
output): every deepmap2 mode, translucent, palette and RGB PNGs, an odd width, bands, several
mode-2 chunks, deployment targets 13.0, 15.0 and 18.0, the packing classes, 1 to 40 images in
one or more atlases. retro-rampage's `CompileAssetCatalogVariant` command line, rerun with
`nomac actool`, gives its Xcode build's `Assets.car`, partial Info.plist, dependency info and
report; the Linux build of nomac gives the same `Assets.car`. Of the 154 images a subagent
compiled with actool to find deepmap2's rules, nomac writes 76 of the 79 color images byte for
byte and stops on the other 3 (data 9 bytes under raw); the other 75 are gray.

Result (`assets_experiments.py <dir> --nomac .build/debug/nomac symbols`, 2026-10-22, later
26 of 26 with symbol sets, an Icon Composer input and which sets are listed and thinnable): 21 of 21
cases identical (the three symbol files, standard output, nothing else written): 233 names as
color and image sets, names stored decomposed, 114 color and 99 image member names, namespaces,
a mixed catalog with deployment targets 15.0, 16.4 and 17.0 and every extensions setting, an
empty catalog; for sets sharing a name the Swift file is identical and the header and index
identical but for their order, which changes between actool's own runs. The `GenerateAssetSymbols`
command lines of retro-rampage, tofu, flappy-fly-bird, uncloudnotes and swiftfin, rerun with
`nomac actool`, give files identical to those of their Xcode builds.

## Next actions

By the sample's ranking, with `catalog_sweep.py run <root> --only refused,different` after each:

1. SVG (filters stop 4 apps, patterns 2, dashes, `xlink:href`, `isolation`, a px height): the rule is
   found, a patch written outside the repository, in `~/nomac-out/wt-scratch/assets/agents/svg/`
   (`rule.md`, `svg.diff`, `cases.py`, `tests.swift`), not compiled, conflicting with the row-based
   drawing in `IconRenderer.draw`. CoreSVG applies no filter: a shape with one is not drawn.
2. JPEG: rewritten IPTC APP13 (4 apps stop, B-200), whose dataset order was not found, and Apple
   maker notes. nomac dropped IPTC silently before, and differed; deciding between stopping and
   that was left as stopping, AGENTS.md's rule.
3. PDF: blend modes (3 apps), then the single causes in B-215.
4. Old-target payloads of large images (B-220), 16-bit PNGs (B-209).

To test with the machine loaded, build one target (`swift build --target NomacAssetsTests -j 4`) and
run its bundle with `swiftpm-testing-helper --test-bundle-path <bundle>/Contents/MacOS/<name>
--testing-library swift-testing`, `DYLD_FRAMEWORK_PATH` and `DYLD_LIBRARY_PATH` set to the macOS
platform's Developer `Library/Frameworks` and `usr/lib`: stopping a release build invalidated the
whole debug tree, 648 steps.

### Parked: PDF image sets (B-200)

Observed with self-written PDFs (scratch `pdf/probe*.py`) and corpus files; nothing written yet.
actool stores a PDF image set like an SVG one (vector rendition, pixel format `PDF `, layout 9,
flags 4, part 181; rasters at 1x/2x/3x, flags 0x14, packed), but the vector rendition is the
PDF as Quartz writes it again, not the file:

- Objects: content stream, page, resources, (ExtGStates), ICC stream, `[ /ICCBased n 0 R ]`,
  pages (MediaBox), catalog, an empty Info; `/ID` of zeros; `%PDF-1.3`; every stream zlib
  level 1. The numbering varies (content 4 and resources 3, or content 3 and resources 4 for
  a Figma file): to be found.
- Content: `q Q q … Q`, lines wrapped near 76 columns, numbers to 7 significant digits,
  operators with exponents dropped, `v`/`y` as `c`, empty paths dropped; fills with the CTM
  baked into the coordinates and nested `q`/`Q` gone, strokes keeping `q … cm … S Q`; the line
  width before colors; `/Cs1 cs` (or `CS`) before each color; ExtGStates `/Gs1` with only the
  used parameters (`/ca` for fills, `/CA` for strokes).
- Colors: DeviceRGB through the 3,144-byte HP "sRGB IEC61966-2.1" profile (no public copy
  found: equivalent under ADR 0204 per the 2026-11-02 decision, nomac embeds its own); gray
  through an Apple gray profile (equivalent too); DeviceCMYK kept without a profile; a source
  ICCBased profile carried over (Figma's Display P3: byte for byte possible).
- Corpus: 2,382 image-set PDFs (Figma 264, macOS-written ~260, Adobe ~140, 1,641 without a
  readable producer); features: fill 2,367, stroke ~1,485, clip 1,331, ICC 1,298, XObject 525,
  transparency group 514, soft mask 257, text 246, opacity 185, image 145, shading 127; 723
  use only fills and clips.
- Plan: an experiment of self-written PDFs for the numbering, wrapping, resources and `q`/`Q`
  rules; a PDF reader and Quartz-style writer for paths, fills, clips, strokes, colors and
  opacity, refusing the rest; rasters for those features; then groups, soft masks, shadings,
  text and images by corpus use.

## How to reproduce

```sh
export DEVELOPER_DIR=/Applications/Xcode_27.app/Contents/Developer   # a Mac with Xcode 27.0
swift build -j 4
python3 .github/scripts/assets_experiments.py ~/nomac-out/assets-experiments --nomac .build/debug/nomac
# summary.json lists each case and its comparison; outputs stay outside the repository.
# One experiment: append its name (colors, data, identifiers, collisions, bitmap-order,
# appearance-order, packing, app-icons, images, sprites, symbols, icons). Expected: every case
# identical (images 30, packing 47, colors 13, app-icons 31, sprites 12, stickers 6, bitmap-order 53, symbols 26),
# icons 12 with Assets.car and icon PNGs equivalent, profiles 13 (4 refused on B-213).
```

Icon Composer: `python3 .github/scripts/assets_experiments.py <dir> --nomac .build/debug/nomac icons`
(every case identical but `Assets.car` and icon PNGs "equivalent"; `composite-runs` also
compares actool's two runs). Scratch `expoicon/` holds expo-default's eight actool runs
(`r1`–`r8`), `blocks.py` (block-by-block comparison), `rend.py` (decode rendered images) and
`nrun.sh`; `icons/lib/summ.py` and `diffsumm.py` print and diff the icon renditions; `icons/x1.py`
to `x4.py` are the white-layer bisection.

Scratch tools, outside the repository in `~/nomac-out/wt-scratch/assets/` (observation
outputs stay there too):

- `refusals/run.py`: reruns every actool task of the corpus's reference build logs
  (`~/nomac-out/reference/<app>/build/build.log`) with `.build/debug/nomac`, prints the
  refusals by count; then fix the `kind` field (`symbols` when an argument starts with
  `--generate-`) and run `refusals/compare.py`, which compares the compiles that ran with the
  reference outputs (12 identical on 2026-10-24: retro-rampage 58, uncloudnotes 64,
  flappy-fly-bird 6, firefox 0, wikipedia 65, netnewswire 38, gomap 10, icecubes 11 and 16,
  kickstarter 23 and 24, nextcloud 43); it compares sticker pack folders too. `refusals/features.py` lists every unsupported
  feature of each compile and a greedy order; its supported set is edited by hand.
- `pngforms/harness.py`: compiles a PNG and 8-bit RGBA PNGs of candidate pixels with actool
  and tells which candidate gives the same `Assets.car` (`pngforms/pngdec.py` decodes and
  encodes every PNG form); `e1.py` and `e2.py` are the PNG-form checks.
- `scales/obs.py`: builds image sets and dumps each rendition's key, CSI and properties
  (`dump(car)`); `tools/car.py`, `tools/dmp.py` (renditions and deepmap2 blobs), `gray/lz.py`
  (libcompression decoding), `dm2/dmoracle.py` (cached single-image actool runs).
- `syscolors/s1.py`: the system color table (`table18.json`), from which
  `SystemColors.swift` was generated.
- `corpus-sym/run.py`: the corpus's `GenerateAssetSymbols` tasks against their references.
- `cgbi/`: icon PNG tools (`chunks.py`, `idot.py`, `writer.py`, the CgBI model checked on
  reference and self-written icons), the app icon observations (`e2.py`, `e3.py`),
  `p218.py` (size tables), `cardiff.py` (which tables of two cars differ), `atl.py` (decoded
  atlas bands), `v0check.py` (variant-0 payloads against the C stream model), `members.py`
  (atlas members by `dim1`), `dm.py` and `big.py` (deepmap2 bands and mode-3 chunks).
- `stickers/e1.py` (sticker catalog observations), `cgbi/gray.py` and `gray4.py` (gray icon
  PNGs).
- `template/e1.py` (rendering intents, sets without `Contents.json`), `pngforms/profiles.py`
  and `proftest.py` (the corpus's ICC profiles, converted or not), `cgbi/meta.py` (icon PNG
  chunks).
- `sprite/e1.py` (sprite atlas observations), `b201/` (`obs.py`, `sim.py`: `BITMAPKEYS` trees
  and the split model), `order/e1.py` (atlas numbering).

Linux: `bash ~/nomac-out/wt-scratch/assets/tools/linux-test.sh` (Docker, volume
`nomac-assets-build`, `swift:6.4.1-noble` with the build libraries). Rules from the
integrator: no subagents, small tool output, background jobs instead of polling, the full Mac
and Linux suites once per "ready to merge".
