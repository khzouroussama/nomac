# Asset catalogs: actool's outputs and the `.car` format

What Xcode 27.0 (27A266a)'s `actool` writes for an asset catalog, as nomac reproduces it
(`Sources/NomacAssets`). Everything here comes from actool's outputs for self-written
catalogs (`.github/scripts/assets_experiments.py`, experiment names in parentheses) and from
Swift Build's open-source specification of the asset catalog compiler
(`AssetCatalogCompiler.xcspec`); nothing comes from Apple binaries. All byte offsets are from
the start of the structure described.

## How Swift Build runs actool (`app-build`)

For an app target with an asset catalog, Swift Build runs actool four times:

1. `actool --print-asset-tag-combinations --output-format xml1 <catalogs>` and
   `actool --version --output-format xml1` while it creates the build description.
2. `GenerateAssetSymbols`: `actool <catalogs> --compile <app> ... --bundle-identifier <id>
   [--generate-swift-asset-symbol-extensions NO] --generate-swift-asset-symbols <file>
   --generate-objc-asset-symbols <file> --generate-asset-symbol-index <file>`, which writes
   only the symbol files ("Asset symbols" below). The extensions option is passed only when
   `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS` is `NO` (tofu leaves it `YES`).
3. `CompileAssetCatalogVariant thinned <app> <catalogs>`: `actool <catalogs> --compile
   <TARGET_TEMP_DIR>/assetcatalog_output/thinned --output-format human-readable-text --notices
   --warnings --export-dependency-info <TARGET_TEMP_DIR>/assetcatalog_dependencies_thinned
   --output-partial-info-plist <TARGET_TEMP_DIR>/assetcatalog_generated_info.plist_thinned
   [--app-icon <name>] [--accent-color <name>] --compress-pngs --enable-on-demand-resources
   YES --development-region en --target-device iphone --target-device ipad
   --minimum-deployment-target 18.0 --platform iphoneos`. An `unthinned` variant runs only when
   the build thins resources.
4. `builtin-linkAssetCatalog` (Swift Build itself) copies the variant's outputs into the
   product and the partial Info.plist to `assetcatalog_generated_info.plist`, which
   `ProcessInfoPlistFile` merges into the app's Info.plist.

The options come from the build settings listed in `AssetCatalogCompiler.xcspec`
(`ASSETCATALOG_COMPILER_APPICON_NAME` → `--app-icon`, `TARGETED_DEVICE_FAMILY` →
`--target-device`, ...).

## actool's command line (`colors`)

- `--version --output-format human-readable-text` prints
  `/* com.apple.actool.version */`, `bundle-version: 25098`, `short-bundle-version: 27.0`
  and an empty line; with `xml1` the same as a property list under `com.apple.actool.version`.
- `--print-asset-tag-combinations --output-format xml1` prints a property list whose
  `com.apple.actool.asset-tag-combinations` is an empty array for a catalog without
  on-demand resource tags.
- `--compile <dir>` prints, with `human-readable-text`, an optional
  `/* com.apple.actool.notices */` section (one `<first catalog>: warning: <text>` line per
  warning), then `/* com.apple.actool.compilation-results */`, one line per output file
  (`Assets.car` first, then the partial Info.plist) and an empty line. Paths are absolute.
- A catalog without any rendition (for example only an empty `AccentColor` color set)
  writes no `Assets.car`; the partial Info.plist is still written.

### The partial Info.plist

An XML property list in the format of Apple's serializer: the XML declaration, the DOCTYPE,
`<plist version="1.0">`, keys sorted, nested values indented by one tab per level, an empty
dictionary as `<dict/>`. With `--accent-color <name>` and a color set of that name with at
least one color, it has `NSAccentColorName = <name>`; with a color set of that name without a
color it is empty and nothing is reported (icecubes); without such a color set it is empty and
the report warns ``Accent color ‘<name>’ is not present in any asset catalogs.`` (with
typographic quotes). `--widget-background-color <name>` does the same with
`NSWidgetBackgroundColorName` and ``Background color ‘<name>’ is not present in any asset
catalogs.``, after the accent color's warning; neither changes `Assets.car`.
`--standalone-icon-behavior all` and `none` change nothing without app icon images (`colors`,
`app-icons`).

### The dependency info

ld64's dependency-info format: records of one opcode byte and a NUL-terminated string. First
`0x00 actool-25098`, then `0x10 <catalog>` for each catalog (absolute), then `0x40 <output>`
for each output in the order of the report.

## Asset symbols (`symbols`)

With any of `--generate-swift-asset-symbols <file>`, `--generate-objc-asset-symbols <file>` and
`--generate-asset-symbol-index <file>`, actool writes those files and nothing else: no
`Assets.car`, partial Info.plist or dependency info, and the `--compile` folder is not created.
It prints `/* com.apple.actool.compilation-results */`, the index, header and Swift paths in
that order, and an empty line. Checked against the 33 `GenerateAssetSymbols` tasks of the corpus's
reference builds (31 identical, 2 identical but for the order of tied sets below) and 26
self-written cases. `--app-icon`, `--alternate-app-icon`, `--include-all-app-icons`,
`--standalone-icon-behavior` and `--widget-background-color` change nothing in these files.

**What is listed.** Color, image and symbol sets, including those inside sprite atlases, that
the build has something for: an entry for `universal` or a target device that names a file
(image and symbol sets) or has a color (color sets; a dark-only color counts). On iPhone,
`car` entries count too; entries for `mac`, `tv`, `watch` or `vision` never count. Not listed: data sets, app icon sets, launch images (uncloudnotes'
catalog), visionOS icon stacks, Icon Composer `.icon` inputs (swiftfin's six), a set folder
without a `Contents.json` (tofu's `IssuerIcons/Philips.imageset`). A set without an entry for `universal`
or for every target device is thinnable (below). actool warns, in a
`/* com.apple.actool.document.warnings */` section printed twice in an order that changes, about
an entry naming a missing file, a file no entry names with an extension it reads (in image sets
`png`, `jpg`, `jpeg`, `pdf`, `svg` and `heic`, in symbol sets `svg`, case-sensitive; others such
as flutter's `README.md` are ignored), a symbol file without the `svg` extension, and entries
it calls unassigned children, with or without a file: `ios-marketing` ones of every kind of
set, and image entries of a scale their idiom does not have (`image-entry-scales`: `car` 1x,
`ipad`, `mac` and `tv` 3x, `vision` and `watch` 1x and 3x; no scale is never one); those sets
are not listed. nomac stops on them (B-204). Sticker catalogs add nothing to these files. A folder whose extension is not an
asset type (`ABC.DEF`) is a group like one without an extension. A folder or a sprite atlas
whose `Contents.json` has `provides-namespace` is a namespace; a set's name is its folder name
without extension, after its namespaces (`Space/Inner/deep`). Names keep the form the file
system gives them: a name stored decomposed (`E` + U+0301) is written decomposed.

**Words.** A name is split into words: characters that are neither letters, marks nor numbers
separate words and are dropped (`_ - . , ' " ( ) /`, spaces, emoji, `·`); within a run, a word
starts where a number starts or ends (`17thShard`: `17`, `th`, `Shard`; `x½y`: `x`, `½`, `y`),
at a capital after a small or uncased letter (`redColor`, `日Ab`), and at the last capital of
two or more capitals followed by a small letter (`HTTPSConnection`: `HTTPS`, `Connection`;
`IDme`: `I`, `Dme`). Capitals are Unicode's upper- and titlecase letters (`ǅ`), so `Ⅻ` is not one.

**Swift members** (of sets) and **enums** (of namespaces) use the last path component:
- Trailing words `Color` or `Image` (any case) are dropped while another word remains:
  `AccentColor` → `accent`, `redColorImage` → `red`, `MyCOLOR` → `my`, `Color` → `color`.
- If every remaining character is a capital or a decimal digit (combining marks fail this), the
  words keep their case joined by `_`: `ABC.DEF` → `ABC_DEF`, `4K` → `4_K`, `NSImage` → `NS`,
  `١٢٣` → `١٢٣`. Otherwise members are lower camel case (the first word lowercased, later
  words with their first character uppercased: `URLString` → `urlString`, `İstanbul` →
  `i̇stanbul`) and enums upper camel case (`my folder` → `MyFolder`, `redColor` → `Red`).
- An ASCII digit first gets `_` (`_17ThShard`, `_4_K`, `_3_D`); a member that is one of 51
  reserved words gets backticks (`` `default` ``, `` `self` `` for `Self`; contextual keywords
  such as `open`, `some`, `any`, `async` do not; `AssetSymbolName.keywords`).

**Objective-C constants** are `ACColorName` or `ACImageName` and the whole name, namespaces
included, without dropping type words: capitals-only names as above but with a leading `_`
when there are several words (`ACColorName_ABC_DEF`, `ACColorNameABC`); otherwise every word
with its first character uppercased (`ß` → `SS`, `ﬁ` → `FI`), then only the ASCII characters
kept (`café` → `Caf`, `Ünïcödé` → `ncd`, `ÉTÉColor` → `TColor`, `日本` → none).

**Order.** The Swift file sorts each level by the code points of the names' canonical
composition, namespaces among sets; the header and the index sort all sets of a kind by the
code points of the canonical decomposition of their last path component. Sets that share that
component (in two namespaces or catalogs) come out of actool in an order that changes from run
to run in the header and the index, never in the Swift file (`ties`: three runs); nomac orders
them by full name.

**Index** (`GeneratedAssetSymbols-Index.plist`): an XML property list with `colors`, `images` and
`symbols` (symbol sets) arrays of `catalogPath` (the catalog as passed), `objcSymbol` (from the last
path component only, unlike the header; absent when empty), `relativePath`
(`./Folder/name.imageset`) and `swiftSymbol` (the member, backticks included). Sets whose member
is empty are left out; duplicates are listed.

**Header** (`GeneratedAssetSymbols.h`): `#import <Foundation/Foundation.h>`, the
`AC_SWIFT_PRIVATE` definition, `ACBundleID` (the `--bundle-identifier`) when there are colors,
then per color, then per image: `/// The "<name>" asset catalog <kind> resource.` and
`static NSString * const <constant> AC_SWIFT_PRIVATE = @"<name>";` (symbol sets as images,
after all the image sets), or
`#warning The "<name>" <kind> asset name resolves to an empty symbol. Try renaming the asset.`,
or, for a constant already declared, `... resolves to the symbol "<constant>" which already
exists. Try renaming the asset.`; then `#undef AC_SWIFT_PRIVATE`. Names in quotes escape `\`,
`"` and `'` with a backslash.

**Swift file** (`GeneratedAssetSymbols.swift`), in this order:
- The imports (Foundation; AppKit, UIKit and SwiftUI unless the target is iOS 17 or later
  without extensions; DeveloperToolsSupport) and the `resourceBundle` definition.
- `Color Symbols` and `Image Symbols`: `extension ColorResource` and `ImageResource` (from iOS
  17.0 on `DeveloperToolsSupport.ColorResource`, ...), with `static let <member> =
  ColorResource(name: "<name>", bundle: resourceBundle)` per set and `enum <Enum>` per
  namespace; symbol sets are images among the image sets, one of the same name as an image set
  is that image. Empty and duplicate members and enums are `#warning(...)` lines in their place
  ("namespace" and "Try renaming the namespace." for enums); a set named like a namespace
  folder beside it is left out. A thinnable set's member is `@available(watchOS, unavailable)`
  and `ColorResource(thinnableName: ...)`, and its extension members are optional, made with
  `.init(thinnableResource: ...)` (SwiftUI's also `@available(watchOS, unavailable)`).
- With extensions (`YES` or not passed): `Color Symbol Extensions` (`AppKit.NSColor`,
  `UIKit.UIColor`, `SwiftUI.Color`, and `SwiftUI.ShapeStyle where Self == SwiftUI.Color`
  without namespaces), `Image Symbol Extensions` (`AppKit.NSImage`, `UIKit.UIImage`) and
  `Thinnable Asset Support`, whose AppKit initializer for colors (images) is there only when the
  catalogs have colors (images). Members that warned in the resource section are left out
  without a warning; enum warnings repeat. A top-level member that is one of the type's own
  class members (`red`, `systemBlue`, `label`, `add`, `cautionName`, ...;
  `AssetSymbolName.conflicts`, every candidate from the SDK's headers tried) is
  ``#warning("The \"<name>\" color asset name resolves to a conflicting UIColor symbol
  \"<member>\". Try renaming the asset.")`` (`ShapeStyle` leaves it out).
- A catalog's own `generate-swift-asset-symbol-extensions` property (its `Contents.json`
  `properties`; home-assistant's Colors.xcassets; `symbol-extensions`) overrides the option for
  its assets: `enabled` gives them extension members with `NO`, `disabled` leaves them out with
  `YES`; on a folder inside it does nothing. A kind's extension sections are written with the
  option, or without it when one of its assets is enabled, then listing only the enabled ones;
  `Thinnable Asset Support` comes with either section and is as with the option. Another value
  gets a document warning (``The manifest for "<catalog>" contained invalid content for the
  "generate-swift-asset-symbol-extensions" key. The string "<value>" was not valid.``), where
  nomac stops.
- Before iOS 17.0: `Backwards Deployment Support`, the same text whatever the catalogs hold,
  with no line break at the end.
- Availability: before iOS 17.0 `iOS 11.0, macOS 10.13` for colors and `macOS 10.7` for images,
  SwiftUI `iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0`; from 17.0 `iOS 17.0, macOS 14.0,
  tvOS 17.0, watchOS 10.0`, AppKit `macOS 14.0`, UIKit `iOS 17.0, tvOS 17.0`. 16.4 is still
  before.

## Determinism (`appearance-order`)

actool's outputs depend only on the catalog's content and the options: catalog paths and
names, the order files were created in and the output directory change nothing, and repeated
runs are identical, with one exception: when renditions use more than one appearance, the
order in which actool creates the appearance-key blocks (below) changes from one run to the
next (six runs of one catalog gave five orders). Since the blocks have different lengths,
every later block moves. nomac creates them in name order; comparisons put actool's in name
order first (ADR 0200). The asset symbol header and index have the same kind of exception for
sets sharing a name ("Asset symbols"). A catalog compiled with an Icon Composer icon varies in
two more ways ("Icon Composer icons", ADR 0203).

## BOM container

`Assets.car` is a BOM store. Integers of the container are big-endian.

| Offset | Size | Field |
|---|---|---|
| 0 | 8 | `BOMStore` |
| 8 | 4 | version, 1 |
| 12 | 4 | number of blocks, not counting block 0 |
| 16 | 4 | offset of the block index |
| 20 | 4 | length of the block index |
| 24 | 4 | offset of the variables |
| 28 | 4 | length of the variables |

The header is followed by zeros up to offset 512. Blocks are numbered from 1 in the order
actool creates them and laid out in that order from offset 512, each at the next multiple of
16 (the gaps are zeros). Then, at the next multiple of 16 after the last block:

- **Variables**: a count, then per variable its block (4 bytes), the length of its name
  (1 byte) and the name (no terminator). actool writes `CARHEADER`, `RENDITIONS`,
  `FACETKEYS`, `APPEARANCEKEYS`, `KEYFORMAT`, `EXTENDED_METADATA`, `BITMAPKEYS`, in that
  order.
- **Block index**, at the next multiple of 16 after the variables, ending the file: a count,
  then (offset, length) per block starting with block 0 (0, 0). The count is 256, or the
  number of blocks plus one rounded up to a multiple of 8 when that is larger (389 → 392, 1146
  → 1152, 1247 → 1248). Unused entries are zeros. A free list follows: a count of 0 and 16
  zero bytes.

### Trees

The tables are B+-trees of the store. A tree is a 29-byte header block:

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | `tree` |
| 4 | 4 | version, 1 |
| 8 | 4 | block of the root node |
| 12 | 4 | block size: 4096, 1024 for `BITMAPKEYS` |
| 16 | 4 | number of entries |
| 20 | 1 | 1 when keys are stored in the entries (`BITMAPKEYS`), else 0 |
| 21 | 4 | the length of every key when all keys have the same length, `0xFFFFFFFF` when they differ, 0 for `BITMAPKEYS` |
| 25 | 4 | 0 |

A leaf node starts with 1 (2 bytes), the entry count (2 bytes), the next and previous leaf (4
bytes each, 0 for a single leaf), then per entry the value's block and the key's block (or the
key itself in `BITMAPKEYS`), 4 bytes each, sorted by key: byte order for keys in blocks, and
for strings a shorter prefix first; numeric order in `BITMAPKEYS`. When all keys have the same
length, 4 zero bytes and a copy of every key in entry order follow. The node's block is as long
as the tree's block size plus, for that key copy, the key length times the entry count; the
rest is zeros.

A leaf holds at most (block size − 12) / 8 entries: 126 in `BITMAPKEYS` (a catalog of 127
names already splits it), 510 in the others. Larger trees have branch nodes: 0 instead of 1,
the separator count, next and previous 0, then (child, separator key) entries and a trailing
child block, padded to the block size. A separator refers to the block of the kept leaf's last
key, no new block; when all keys have the same length a branch also copies its separators after
the trailing child, and its block is as long as the block size plus the key length times the
separators. A branch holds as many separators as a leaf holds entries.

actool builds every table one entry at a time, in the order it creates the values (below): each
key block, then its value block, is created, then the entry inserted. A full leaf takes the new
entry, keeps its first ⌈n / 2⌉ entries (64 of 127, 256 of 511) and moves the others to a new leaf
block created right then, after the value; the kept leaf's last key becomes the separator in
the parent, and when the leaf was the root a new root branch block is created next, holding
(kept leaf, separator) and the new leaf as its last child. Leaves are linked forward and backward
in key order. So `FACETKEYS`, created in key order, fills its last leaf and leaves the others
at 256, and `RENDITIONS`, created middle-first, splits where the middles fall.

A full `BITMAPKEYS` branch (127 separators) keeps its first ⌊n / 2⌋ (63), gives the next to its
parent and moves the other 63 and their children to a new branch block, created right after the
new leaf and before a new root; branches have no links (`large-tables`: 12,000 and 24,000 names,
a root over branches and a branch under the root overflowing, whole stores identical). The
4,096-byte tables would need about 130,000 entries for it, more than `large-tables` reached, and
nomac stops there (BACKLOG B-201).

`large-tables`: 53 catalogs of 510 to 24,000 names, three appearances, three idioms, display gamuts,
data sets, image sets with atlases and a mix of them, every table past one leaf, reproduced whole
after the appearance keys' order (Determinism). `APPEARANCEKEYS` holds a few names and has
not been seen past one leaf.

Each tree's header and root blocks are created together, before the blocks of its entries:
`RENDITIONS`, `FACETKEYS` and `APPEARANCEKEYS` right after `CARHEADER`, `BITMAPKEYS` after
`EXTENDED_METADATA`.

## Block order

For a catalog of colors: `CARHEADER`; the `RENDITIONS`, `FACETKEYS` and `APPEARANCEKEYS`
trees (header, root); each appearance's name and value; each facet's name and token in name
order; `KEYFORMAT`; each rendition's key and CSI in rendition order (below);
`EXTENDED_METADATA`; the `BITMAPKEYS` tree; the `BITMAPKEYS` values.

## CARHEADER

436 bytes, little-endian like everything inside the blocks.

| Offset | Size | Field | Value |
|---|---|---|---|
| 0 | 4 | tag | `RATC` |
| 4 | 4 | CoreUI version | 1010 |
| 8 | 4 | storage version | 17 |
| 12 | 4 | storage timestamp | 0 |
| 16 | 4 | number of renditions | |
| 20 | 128 | main version string | `@(#)PROGRAM:CoreUI  PROJECT:CoreUI-1010 [LAR]` |
| 148 | 256 | version string | `Xcode 27.0 (27A266a) via AssetCatalogAgent-AssetRuntime` |
| 404 | 16 | UUID | zeros |
| 420 | 4 | associated checksum | 0 |
| 424 | 4 | schema version | 2 |
| 428 | 4 | color space | 1 |
| 432 | 4 | key semantics | 2 |

Strings are NUL-padded.

## EXTENDED_METADATA

1028 bytes: `META`, then four NUL-padded 256-byte strings: the thinning arguments (empty), the
deployment platform version (`--minimum-deployment-target`, `18.0`), the deployment platform
(`ios` for `iphoneos`) and the authoring tool,
`@(#)PROGRAM:CoreThemeDefinition  PROJECT:CoreThemeDefinition-664 [LAR] [IIO-2851][LAR] AppleJPEG[1][32]  CMPhoto[1][219]] [IR-120(hw)]`
(Xcode 27.0 on macOS 27.0.1, Apple silicon).

## Key format

`KEYFORMAT`: `tmfk`, 0, the attribute count, then the attributes (4 bytes each). A rendition
key is one 2-byte value per attribute in this order.

| Number | Attribute | Values seen |
|---|---|---|
| 7 | appearance | 0 any, 1 dark, 2 high contrast, 3 high contrast dark, 4 light, 5 high contrast light |
| 13 | localization | 0 |
| 12 | scale | 1 for colors |
| 15 | idiom | 0 universal, 1 iPhone, 2 iPad |
| 16 | subtype | 0 |
| 24 | display gamut | 0 sRGB, 1 Display P3 |
| 4 | direction | 5 left to right, 4 right to left |
| 17 | identifier | the name identifier |
| 1 | element | 85 |
| 2 | part | 217 colors, 181 data and images |

The table is in key-format order. Every key format has these attributes except display gamut,
which is there only when a rendition has a gamut other than sRGB (`colors` variants).

## Name identifiers (`identifiers`, `collisions`)

Each asset name gets a 16-bit identifier, its rendition keys' identifier attribute. Found from
one-name catalogs (no collisions possible) by measuring how the identifier changes with each
character, then confirmed on 583 one-name catalogs (`identifiers`), including names built to
collide, and on every multi-name catalog of the experiments:

1. `h = 100823`; for each UTF-16 code unit `u` of the name: `h = h × 33 + u`, in 64 bits.
2. The identifier is the same ×33 hash, from 0 in 16 bits, over the four 16-bit words of `h`,
   lowest first: `((w0 × 33 + w1) × 33 + w2) × 33 + w3`.

Names are taken in code-unit order (only ASCII collisions have been observed). When a name's
identifier is already taken, it gets `(w0 ⊕ w1 ⊕ w2 ⊕ w3) + 1`, or the next free value after
that (the 104-name `pairs` case probes up to 9 values). An identifier of 0 is kept: the facet
then has no identifier attribute and `BITMAPKEYS` no entry. A name in a folder that provides
a namespace is `Folder/Name` (`F/Red` → `0xC2EF`).

Examples: `Red` → `0x896A`, `a` → `0xA2CA`, `zztcqgmy` → 0; `ac` and `bB` both hash to
`0xAFE6`, `ac` keeps it and `bB` gets `0x6EF1`.

## APPEARANCEKEYS and FACETKEYS

`APPEARANCEKEYS` maps appearance names to their numbers (2 bytes): `UIAppearanceAny` 0,
`UIAppearanceDark` 1, `UIAppearanceHighContrastAny` 2, `UIAppearanceLight` 4. It lists the
appearances that renditions other than data use (a color for the dark appearance only gives
`UIAppearanceDark` alone); a catalog of data sets only has no `APPEARANCEKEYS` variable, tree
or blocks.

`FACETKEYS` maps each asset name, decomposed (NFD: `é` is stored as `e` and U+0301), to a
token; the identifier and the CSI's name field use the name as the file system spells it
(`identifiers`, non-ASCII names). The token is a hot spot (two 2-byte zeros), the attribute
count (2 bytes) and (attribute, value) pairs of 2 bytes each: element, part and identifier
(left out when 0).

## Rendition order

`RENDITIONS` maps rendition keys to CSIs. actool creates the renditions' blocks in a fixed
order: sort the keys by their values compared in key-format order, then take the middle key
(index ⌊n/2⌋), then the lower half and the upper half in the same way, recursively. For eight
keys that is 4, 2, 1, 0, 3, 6, 5, 7. Confirmed on every catalog of the experiments, up to 246
renditions.

## BITMAPKEYS

Keyed by identifier, one value per identifier with renditions: 1, 0, the length of what
follows (4 + 4 × attribute count), the attribute count, then per key-format attribute
`0xFFFFFFFF` for appearance, identifier, element and part, else the mask of the values the
identifier's renditions use (bit *v* for value *v*: scale 1 → 2, idioms 0, 1, 2 → 7).

actool creates the values in the slot order of an open-addressing hash table filled in
rendition creation order, each identifier once (`bitmap-order`, 50 catalogs of 1 to 510
names; `large-tables`, up to 24,000): slots `[3, 7, 13, 23, 41, 71, 127, 191, 251, 383, 631, 1087,
1723, 2803, 4523, 7351, 11959, 19447, 31231, 50683, ...]`, home slot
`identifier × 2654435761` (64 bits) modulo the size, linear probing upwards with wrap-around;
after an insertion that makes the count exceed `[3, 6, 11, 19, 32, 52, 85, 118, 155, 237, 390, 672,
1065, 1732, 2795, 4543, 7391, 12019, 19302, 31324, ...]` for the current size, and before inserting
into a full table, the table moves to the next size, re-inserting the identifiers in slot order.
These are CFBasicHash's tables (CF-Lite, public); nomac stops past 31,324 identifiers, the
largest table seen in use (BACKLOG B-201).

## Thinning (`car-thinning`)

App thinning (docs/formats/ipa.md "App thinning") thins the app's `Assets.car` for each group of
devices with `assetutil` (macOS's `/usr/bin/assetutil`; given a trait set of Xcode's
`device_traits.db`, its output is byte for byte the variant's catalog): `-i` idiom, `-s` scale,
`-t` subtype, `-u` subtype fallbacks, `-p` display gamut, `-h` hosted idioms, `-g` graphics
feature set class, `-k` its fallbacks (`:`-separated), `-M` memory class, `-r` deployment target,
`-o` the output. `distribution_experiments.py` `car-thinning` runs it for each of the 71 trait sets
of the iOS 18.0 descriptors on four catalogs (images by idiom and scale, packed into atlases; a
color set with a dark appearance; a single-size app icon with a dark one); `nomac assetutil`
(`CARThinning`) gives the same bytes for all 284.

- **What is kept.** Renditions are grouped by what does not depend on the device (identifier,
  element, part, appearance, localization, `dimension1`, `dimension2`: dark colors and each app
  icon size stay apart); in each group the device keeps one: of its own idiom or universal (an
  iPhone-only image leaves an iPad's catalog, and its facet goes when no rendition is left), the
  nearest scale (its own, then lower ones from the closest, then higher ones: 1x of 1x and 3x on
  a 2x device, 2x of 1x and 2x on a 3x one), then its own idiom over universal at that scale (a
  universal 3x image wins over an iPhone 2x one on a 3x iPhone). An atlas stays when a kept image
  links into it (property 1010). Renditions that depend on subtype, gamut, memory, graphics or
  other idioms (CarPlay, TV, marketing) are not observed, and nomac refuses them (B-465).
- **How the store changes.** The BOM store is edited, not written again: the removed renditions'
  key and CSI blocks and a removed facet's name and token blocks are freed (index entry
  `0xFFFFFFFF`, `0xFFFFFFFF`; the free list stays empty); `RENDITIONS` and
  `FACETKEYS` keep their header and leaf blocks, written again with the remaining entries (the
  leaf keeps the tree's declared key length and copies of fixed-length keys; nomac stops on a table
  of several leaves, whose nodes assetutil removes and merges by a rule not known yet, BACKLOG
  B-201); `BITMAPKEYS` is
  built again for the remaining renditions as actool builds it, in new blocks after the last one
  (its old blocks freed, its variable moved); `CARHEADER`'s rendition count is updated; the other
  blocks are kept, and the store is laid out again in block order.
- **`EXTENDED_METADATA`'s thinning arguments** (empty in actool's output): `carutil 1010.000000,
  thinned <mode app> <idiom N> <subtype N|*> <subtypefallback *> <scale N> <gamut 0|1> <graphics N>
  <graphicsfallback (N,…)> <memory N> <deployment- N> <hostedIdioms *|(N,…)> <removed N>`: idioms
  numbered as in keys (phone 1, pad 2, CarPlay 4), gamut sRGB 0 and P3 1, graphics classes
  `GLES2,0` 0, `APPLE1` 1, `APPLE2` 2, `APPLE3v1` 3, `APPLE3` 4, `APPLE4` 5 … `APPLE11` 12, the
  deployment target as the catalog's platform's `device_traits.db` numbers it (iOS 18.0 is 11,
  watchOS 11.0 and 26.0 are 11 and 12), `*` for a missing subtype or no hosted idioms, and the
  number of renditions removed.
- A watch app's catalog (`EXTENDED_METADATA` platform `watch`) thins the same way for a watch
  (idiom 5): the watch's own idiom or universal, the nearest scale (`thinning` `watch-catalog`,
  as the WatchOS platform's assetutil writes it, given the export's arguments).

## CSI

Every rendition value is a CSI:

| Offset | Size | Field | Colors |
|---|---|---|---|
| 0 | 4 | tag | `ISTC` |
| 4 | 4 | version | 1 |
| 8 | 4 | flags | 0 |
| 12 | 4 | width | 0 |
| 16 | 4 | height | 0 |
| 20 | 4 | scale | 0 |
| 24 | 4 | pixel format | 0 |
| 28 | 4 | color model | 0 |
| 32 | 4 | modification time | 0 |
| 36 | 2 | layout | 1009 |
| 38 | 2 | | 0 |
| 40 | 128 | name | the asset name, NUL-padded |
| 168 | 4 | length of the properties | |
| 172 | 4 | | 1 |
| 176 | 4 | | 0 |
| 180 | 4 | length of the payload | |
| 184 | | properties, then the payload | |

Properties are (type, length, value) with 4-byte type and length. Colors have type 1004
with 8 zero bytes and type 1006 with the value 1 (4 bytes).

### Data (`data`)

A data set gives one rendition per entry of `data` with a `filename`: scale 1 and its idiom;
the facet's part is 181. The CSI: scale 100, pixel format `DATA` (stored as the little-endian
number, so the bytes read `ATAD`), layout 1000, the name `CoreStructuredImage`, and three
properties: 1004 with 0 and the float 1.0, 1005 with the type identifier (its length plus one,
0, the identifier and a NUL; 4-byte numbers), 1006 with 1. The payload is the tag `RAWD`
(bytes `DWAR`), 0, the file's length and the file's bytes as they are, without compression
(25,000 bytes stay 25,000).

The type identifier is `universal-type-identifier` when the entry has one, else the one macOS
gives the file's extension, in lowercase and canonically decomposed: `txt` `public.plain-text`,
`json` `public.json`, `bin` `com.apple.macbinary-archive`, `PNG` `public.png`, ... (the table in
`DataTypeIdentifiers.swift`: the 800 extensions `lsregister -dump` declares for types of macOS,
its applications and Xcode, each compiled once, `type-identifier-table`; those only other
applications declare are left out, a Mac with such an application may differ). An extension
macOS does not know gets a dynamic identifier (`dynamic-identifiers`, 91 extensions): `dyn.a`
and the bits of `1=<extension>` (UTF-8, with a backslash before `=`, `,`, `:` and `\`), five at
a time from the top and zero-padded, each in the alphabet `abcdefghkmnpqrstuvwxyz0123456789`:
`db` → `dyn.age80k2u`, `a=b` → `dyn.age80c1b7qk`. No extension, a hidden file's, a trailing
dot's and one holding a space are `1=`: `dyn.age8u`.

### Colors (`colors`)

A color set gives one rendition per entry of `colors` that has a `color`: scale 1, its idiom,
appearance and display gamut. Entries for the `mac`, `tv` and `watch` idioms are left out of
an iOS catalog. The appearance comes from `appearances`: none → any; `luminosity` `dark` or
`light`; `contrast` `high` → high contrast.

The payload: `RLOC`, 1, the color space (4 bytes), the component count (4 bytes) and the
components as doubles. Color spaces: `srgb` 1, `gray-gamma-22` 2, `display-p3` 3,
`extended-srgb` 4, `extended-linear-srgb` 5, `extended-gray` 6; red, green, blue, alpha or
white, alpha.

A component string containing `.` is read as a 32-bit float (leading spaces allowed; `0.2` is
stored as 0.20000000298023224, `1.000000001` as 1); `0x` or `0X` and one or two hexadecimal
digits are that byte divided by 255, one digit standing for itself twice (`0x1` is 17/255);
anything else is its leading integer divided by 255, in double precision (`1` is 1/255, `128`
is 128/255, `1e-1` is 1/255).

System colors (`"color": {"platform": "ios", "reference": "systemBlueColor"}`, `colors`,
system-colors): the `COLR` block's color space has 0x100 added to the space actool resolves
the name in (sRGB, gray, extended sRGB or extended gray, which can differ between light and
dark: `secondarySystemGroupedBackgroundColor` is gray 1.0 in light and extended sRGB in dark),
the components it resolves, 32-bit floats stored as doubles, and a second `COLR` block of
version 1, the name's length and the name. The values are iOS 26's colors (`systemBlueColor`
0, 0.533, 1, 1, that is #0088FF), the same at deployment targets 15.0 and 18.0, for every idiom
and display gamut, and for every platform: `ios`, `universal`, `osx`, `tvos`, `watchos`, `xros`,
`visionos` and none, which actool calls macOS (`system-color-platforms`); `luminosity` `light`
and `contrast` `high` give other values. 40 names are known (17 without a warning for any
platform, 23 iOS-only ones, `groupTableViewBackgroundColor` among them; it is the only name of
real catalogs that was missing, and UIKit's other old names such as `viewFlipsideBackgroundColor`
are unknown). An iOS-only name for another platform gets the document warning ``<set>
references a system color named <name> for platform Universal, but the catalog is building
for iOS. The color may appear differently at runtime.``; a name actool does not know gets
(0.567, 0.464, 1, 1) in sRGB and ``Unable to find iOS system color named: <name>, older
systems will not see the expected value`` (the platform's name instead of iOS, after the other
warning). Those warnings come in an order that changes from run to run; nomac stops on them
and on other appearances (BACKLOG B-203).

## Images (`images`, `packing`)

What nomac reproduces: image sets for deployment targets of iOS 13.0 and later whose entries
are PNGs (gray, RGB, palette, gray and alpha, RGBA; 8-bit, and 1, 2 and 4 bits for gray and
palettes; `tRNS`; interlaced or not: ADR 0202) of each scale for universal, iPhone and iPad,
color or gray; entries without a file add nothing. Checked against
retro-rampage's Xcode build (`Assets.car` identical, on macOS and on Linux), the corpus
catalogs of gomap's, icecubes', kickstarter's and nextcloud's that use nothing else, and the
`images` and `packing` experiments (75 cases identical). The rest is BACKLOG B-200 and B-209.

- **Scales and idioms.** Each entry with a file is one rendition: key scale 1, 2 or 3 (an entry
  without a scale is 1x) and idiom 1 for `iphone`, 2 for `ipad`, none for `universal`; CSI scale
  100 times the scale, sizes in pixels. Entries for a device `--target-device` does not name
  add nothing, and a set left without renditions has no facet. `car` entries get renditions
  (idiom 4) with iPhone among the targets, also for colors (`car-entries`); of data sets, an
  unassigned child warning and nothing, where nomac stops; `vision` and `ios-marketing` entries, and iPad 3x ones, document warnings and
  nothing else (B-200).
- **Pixels.** The PNG's own values, without color conversion for color images without an ICC
  profile or with sRGB IEC61966-2.1's, and for gray images with any (other profiles convert
  the colors: B-213, below), each
  color premultiplied by alpha as (c × a + 127) / 255, so fully transparent pixels are zeros;
  stored BGRA, rows from the top. An image whose premultiplied pixels all have B = G = R
  (fully transparent ones too) is gray: `GA8` (bytes ` 8AG`), color model 2, each pixel its
  gray and its alpha, the alpha 255 throughout in an opaque image, the transparent borders of
  an opaque class's atlas included (gray 0 there).
- **One variant.** From 13.0 on every image has one rendition, deepmap2 (below); before, more
  ("Deployment-target variants").
- **Rendering intent** (`images` intents, tofu): the set's `template-rendering-intent` only
  changes the CSI flags of its images: 0x10 without it, 0x8 for `template`, 0 for `original`
  (app icons have 0). Templates pack with the other images of their class.
- **Sets without `Contents.json`** (tofu's `Philips.imageset`, `images` no-contents) are
  skipped, without a message.
- **Color profiles** (observed, B-213): with an ICC profile other than sRGB IEC61966-2.1's
  (the same body after the 128-byte header), actool stores converted colors: tofu's "sRGB
  built-in" (a version-4 profile with sRGB's primaries and parametric curve) changes a few
  values of some images and none of others, icecubes' Display P3 and wikipedia's "Display"
  more; with the profile removed, the same files give the raw values. nomac stops on them.
- **Standalone images**: CSI flags 0x10, the image's size, scale 100, `ARGB`, color model 1,
  layout 12, the PNG's file name; properties 1001 (one slice: 0, 0, width, height), 1003
  (metrics: 1, four zeros, width, height), 1004 (0 and the float 1.0), 1006 (1), 1007 (row
  bytes: the width times 4, or times 1 for an opaque gray image, rounded up to 32: 40 opaque
  gray pixels give 64, 150 translucent gray ones 608); the deepmap2 payload. Key: scale 1 and the
  set's identifier, element 85, part 181.
- **Packing.** Images are packed into atlases by class: scale, idiom, opaque or not, gray or
  not. The limit is 18,050 pixels times the scale (at 2x, 189 × 191 = 36,099 pixels are packed,
  190 × 190 are not). A class is packed when two or more of its images have at most that many
  pixels; then its images below the limit are packed, even a single one, and an image of
  exactly the limit stays standalone (1x: next to a 95 × 190 image, an 8 × 8 one is packed
  alone; next to 33 × 547, it is standalone). Each atlas is a rendition named
  `ZZZZPackedAsset-<scale>.<opaque>.<gray>-gamut0`, without facet (identifier 0, element 9,
  part 181, the class's scale and idiom, `dim1` numbering the atlases of a scale and idiom over
  their classes in that order, 0 written as no attribute; within a class in the order of the
  atlases' indices as decimal strings, `0`, `1`, `10`, `11`, `2`, ..., which shows from 11
  atlases on, `sprites` atlases-12 and atlases-14, flappy-fly-bird): flags 0, the atlas size, layout
  1004, properties 1001 (one slice of zeros),
  1004, 1006, 1007, and the deepmap2 payload of its pixels, opaque when the class is (even
  though its borders are transparent). Each packed image is a layout-1003 rendition without
  payload: its CSI as a standalone image's without 1007, plus 1010 (`KLNI`, 0, x, y, width,
  height, then `12`, the length and 0 as 2-byte numbers, and the atlas key's nonzero
  attributes as (attribute, value) pairs sorted by attribute, ending with (0, 0)).
  - **Order**: by area, largest first, then by identifier.
  - **Split** (3,131 of 3,131 observed splits at 1x, and 5 at 2x and 3x; fitted, not
    explained): an atlas takes images while the area already taken is below the limit, the one
    reaching it included (c1). Unless
    image c1 made the bin's last growth, k more images plus one join when the next k fit the
    bin's free space without growing it, k counting the cells inside the last growth's strip,
    plus one if image c1's cell is not inside it, plus one if that growth was the bin's only
    one. The remaining images start the next atlas.
  - **Placement**: each image takes a cell of its size plus 2 pixels, placed with the growing
    binary-tree packer of sprite-sheet tools: into the first free node, searching the part to
    the right before the part above; when none fits, the bin grows to the right if the image is
    no taller than the bin and the bin's height is at least its width plus the image's, else
    upward if the image is no wider and the bin's width is at least its height plus the
    image's, else to the right if it can, else upward. Images sit 2 pixels into their cells;
    link y counts from the bottom. The atlas is the bin plus 1, rounded up to an even size (a
    bin of 27 gives 28).
  - **Pixels**: each image's pixels extended by its edge pixels one pixel on every side, zeros
    elsewhere.
- **deepmap2 payload** (`CELM` compression 11): `MLEC`, flags (bit 0 banded, bit 1 opaque), 11,
  then the blob's length and the blob, or for images of more than ⌊2^20 / width⌋ rows the band
  count and per band of that many rows (the last one the rest) `KCBC`, 0, 0, its rows, its
  blob's length and the blob. A blob is 1, the bytes per pixel (4, or 2 for `GA8`), the data's
  length, 0, then `dmp2`, the mode, 1, 10, the bytes per pixel, width and height (2 bytes each)
  and the mode's data. Each band
  takes the smallest of modes 2, 3 and 4 (two forms; not for gray images: none of 25 took it,
  two-level ones included), the first of equals in that order (the `image-appearances`
  image-contrast case: modes 2 and 3 of one size give 2), when it
  is at least 10 bytes smaller than mode 1, which stays when it saves 8 bytes or fewer; at
  exactly 9, 5 of 6 images stayed raw and nomac stops. LZ streams are libcompression's
  `compression_encode_buffer`: raw LZVN below 4,096 bytes, LZFSE from there, both differing from
  Apple's open-source encoders on some inputs (ADR 0201).
  - 1: the pixels.
  - 3: chunks of ⌊2^21 / row bytes⌋ rows (the header's height; 273 at 1,920 pixels), each a
    4-byte length and the LZ stream of its pixels (flappy-fly-bird's 1,920-pixel-wide images).
  - 4 (at most 256 colors): the color count, 4, the colors as BGRA, a 4-byte length and the LZ
    stream of one index byte per pixel. The colors are sorted by their little-endian value, then
    by the exclusive-or of their four bytes with the Bentley–McIlroy quicksort (insertion sort
    below 8 colors; a median of three, of nine above 40; three-way partition; after a partition
    without swaps, an insertion sort that gives up after more than 1 + n/4 swaps), whose
    unstable order the palettes show (357 of 357). The other form has 3 instead of 4, the colors
    with alpha 0, and the alpha plane before the indices.
  - 2: chunks, each a 4-byte length and the LZ stream of an alpha plane, one filter byte per
    row, then each pixel's three residuals (one for gray) as 16-bit values `2|r| + (r < 0)`, a
    plane of high bytes and a plane of low bytes, padded with zeros to 16 bytes. The header's
    height is the chunk's rows, ⌊2^21 / r⌋ with r the row's 7 bytes per pixel (3 for gray) and
    filter byte rounded up to 16 (111 at width 2,688, 291 at 1,024; 24 widths predicted; gray:
    679 at 1,024, 348 at 2,000). A gray pixel is predicted and costed as the color value
    (gray, 0, 0), the rules below unchanged (25 gray images). Pixels become (Y, A, C) from the premultiplied
    colors, `A = trunc((B − R) / 2)`, `C = trunc((G − (R + A)) / 2)`, `Y = R + A + C`, predicted
    by the row's filter: 0 none, 2 left, 3 up, 4 `trunc((L + U + 1) / 2)`, 1 left if
    |U.Y − UL.Y| ≤ |L.Y − UL.Y| else up (neighbors outside the image are 0; the first pixel of a
    row is predicted from above for 1, 3 and 4, from 0 for 0 and 2). Each row takes the filter
    whose residuals cost least, the earlier of 0, 2, 3, 4, 1 on equal costs, the first row of a
    chunk only 0 or 2. A cost is a float sum of ln(1 + |r|) as floats (macOS's `logf`), residual
    by residual in pixel order, except for filter 1, which adds each pixel's (Y + A) + C first;
    those roundings decide actool's exact ties (4,100 rows, among them 800 designed ties).
- **Appearances** (`image-appearances`; home-assistant's, mastodon's, mattermost's and
  pocket-casts' widget images): an entry of any image type may name one appearance, luminosity
  dark or light, or contrast high, without a warning. Its image is compiled as any other, keyed
  with the appearance (1, 4, 2), and packed apart from other appearances as PDF images are
  (below); an empty entry for an appearance adds nothing, and a set may have an appearance
  without its any image. Two appearances in one entry stop nomac.
- **Reports.** The compilation results, and the dependency info's outputs, are in path order
  (retro-rampage's thinned variant lists its partial Info.plist before `Assets.car`).

### SVG images (`vector-images`)

An image set whose entry is an SVG file (the `svg1` and `svg2` observations, swiftfin):

- A vector rendition, the CSI name the file's, flags 4, no size, pixel format `SVG ` (bytes
  ` GVS`), layout 9, properties 1004 and 1006, payload `DWAR`, a flag, the length and the data:
  the file's bytes as they are (flag 0), or libcompression's LZFSE stream of them (flag 1) when
  that is smaller (24 sizes from 121 to 5,000 bytes, compressible or not). With
  `preserves-vector-representation` its key is part 42 with scale 1, otherwise part 181 without
  scale.
- Rasterized renditions at 1x, 2x and 3x of the SVG's size in points (its `width` and `height`,
  in px or pt, else its `viewBox`) times the scale, rounded up (10.5 × 7.25 gives 11 × 8, 21 ×
  15, 32 × 22), packed or standalone like PNG images, gray ones as `GA8`, in atlases named per
  scale (`ZZZZPackedAsset-2.0.0-gamut0`); their flags have 0x100 with
  `preserves-vector-representation` (0x114, else 0x14). The content is drawn at its own size
  at the bottom left; the slices (property 1001) are its size times the scale rounded half up,
  at the bottom (10.25 × 7.75 at 3x: 31 × 23 at y 1 in the 31 × 24 image; x is 0). The images
  are never opaque, even when the content fills them (a 12.5-point square at 2x is packed with
  translucent images). Their pixels are CoreSVG's; nomac draws its own (ADR 0204).
  A rasterized image stored alone whose pixels are all opaque has an opaque payload (`CELM`
  flag 2, a gray one stored as opaque gray: property 1007 the width rounded up to 32), its flags
  and packing class staying translucent (`vector-images` Opaque cases; PDF rasters alike).
- Strokes and masks (`svg-masks-strokes`, 15 cases equivalent): nomac outlines strokes from
  their width, caps, joins and miter limit (dashes stop it, B-210) and draws masks by
  luminance inside their region (`maskUnits`, by default the masked box grown by 10% on each
  side; `maskContentUnits`). CoreSVG masks by luminance whatever `mask-type` says: an alpha
  mask of black content hides everything, giving an empty, gray image.
- `preserves-vector-representation` gives flag 0x100 to PNG images too (home-assistant).
- The file in a 1x, 2x or 3x entry (most corpus sets: the SVG in the 1x entry, the others
  empty; `vector-images` Slot cases): in the 1x entry as without a scale; in the N× entry the
  content is drawn at the SVG's size divided by N at the bottom left of images of the full
  size (slices at that size, 10.5 × 7.25 in the 2x entry: 5 × 4 at y 4 of 11 × 8 at 1x), and
  the preserved vector rendition is keyed with scale N.
- Paints (`svg-colors`, identical): names (CSS's list), `#rgb`, `#rrggbb`, `rgb()`, `rgba()`
  with its alpha, `transparent`, `currentColor` (the inherited `color`, black by default).
  CoreSVG reads no other form: `#rrggbbaa`, `#rgba` and unknown words are dropped like an
  invalid CSS declaration, the inherited value staying (black for a fill, none for a stroke
  at the root; a group's red fill for its child).

### PDF images (`pdf_experiments.py`)

An image set whose one universal entry, without a scale, is a PDF file (1,848 image sets in 11
corpus apps). Observed with self-written PDFs (`.github/scripts/pdf_experiments.py`, Xcode
27.0) and corpus files:

- A vector rendition as for SVG files (pixel format `PDF `, bytes ` FDP`, layout 9, flags 4,
  part 181 or with `preserves-vector-representation` part 42), holding the first page **as
  Quartz writes it again**, not the file, in a `DWAR` payload never compressed (flag 0: all
  535 experiment renditions, 153 corpus ones up to 1.5 MB, pocket-casts' 44).
- Idioms (`entries-2`): an entry per idiom (universal, iphone, ipad) has its own PDF, compiled
  as it alone, its vector rendition and rasters keyed with the idiom. A file per scale (1x, 2x,
  3x entries) is rasterized at its own scale, a missing scale from the 1x file, the vector
  rendition from the highest scale's file; not reproduced yet.
- Appearances (`appearances`): an entry with a luminosity appearance (dark, light) has its own
  PDF, written as any other, its vector rendition and rasters keyed with the appearance; its
  rasters are packed in atlases of their own, keyed with it and numbered apart, an atlas link
  listing element, part, scale, then appearance (and see "Appearances" above).
- Rasterized renditions at 1x, 2x and 3x of the page's size (its CropBox, else its MediaBox)
  times the scale, each side rounded to the nearest pixel, halves up (12.5 × 7.25 points: 13 ×
  7, 25 × 15, 38 × 22), the slice the whole image, flags 0x14 as SVG rasters. Colors outside sRGB
  (an ICCBased Display P3 red) add the display gamut 1 `RGBW` renditions, as for PNGs with
  such profiles (B-213). The pixels are Quartz's; nomac draws its own (ADR 0204).

The rewritten file (`structure`, `info`, `ids`):

- `%PDF-1.3`, then `%` and the bytes `C4 E5 F2 E5 EB A7 F3 A0 D0 C4 C6`; objects `N 0 obj` /
  `endobj` on their own lines; every stream zlib level 1 (window 15, memory level 8: all 114
  streams of the first experiments), `/Length` before `/Filter /FlateDecode`.
- Numbers: 4 the content, 1 the page (`<< /Type /Page /Parent 2 0 R /Resources 3 0 R /Contents
  4 0 R >>`), 3 the resources (`/ProcSet [ /PDF ]`, `/ColorSpace`, `/ExtGState`, `/XObject`).
  From 5, a content stream numbers the color spaces and the group forms it uses as it uses them
  (a form's resources, then the form), then the ExtGStates new to it; a form, written after the
  stream that uses it, numbers its group's color space before its content's. Then the profile
  streams in their color spaces' order, the catalog and the Info. Written in the order content,
  page, resources; each form followed by its resources and its own forms; the patterns and
  shadings; the page's and the forms' new ExtGStates, in number order (`groups-5`; firefox's
  `kitCircle.pdf`); each profile followed by its `[ /ICCBased n 0 R ]` array; the
  pages node (`/MediaBox [x0 y0 x1 y1]` of the CropBox or MediaBox, no `/Rotate`), the catalog
  (`/Version /1.4` when there is a group form), the Info. Names count up across the file:
  `/CsN` by color space, a group's included (`groups`, `groups-2`).
- Info: a non-empty `/Producer` (ASCII kept, anything else as UTF-16BE after a byte order mark;
  `(`, `)` and `\` escaped, control bytes in octal) and, for a valid `/CreationDate`, both
  `/CreationDate` and `/ModDate` set to it in UTC (`D:YYYYMMDDHHmmSSZ00'00'`, missing fields
  their least; an offset counts written `HH'` or `HH'mm'`, otherwise, cairo's `+02'00` among
  them, the time is taken as UTC); every other entry dropped. The Info is found in any trailer,
  a later one overriding the entries it has (a linearized file's first-page trailer).
- Trailer: `/Size`, `/Root`, `/Info`, `/ID` of the source's two identifiers in lower-case hex
  when the source has an Info dictionary and both are 16 bytes, else 32 zeros twice.
- Lines: units separated by spaces, a line break instead once the line is past column 72;
  each number, name and operator a unit, but a rectangle's four numbers one, a matrix's six
  (`cm`, `Tm`) one, a reference `n 0 R` one, and `/MediaBox`, a form's `/BBox` and `/Matrix`
  and a font's `/FontBBox` arrays one (every experiment's content stream, and dictionaries
  alike, the pages node included: cwa's `Icon_CurrentlyUsedCertificate_grey.pdf` breaks its
  line before `>>`; wikipedia's `description-cat.pdf` breaks a `cm` before the operator).
- Numbers: within a millionth of an integer, that integer. From 1 up, seven significant digits
  without trailing zeros. Below 1, the fewest decimals for which the value times 10 to their
  count is within 1e-5 of an integer (0.1000010 is written 0.1, 0.1200001 0.12, 0.1000011 and
  0.0700007 stay), else seven significant digits with their trailing zeros (0.095999904 is
  written 0.09599990). Never an exponent (`numbers`, `number-values` to `number-values-5`).
  Quartz reads a real operand as its digits, trailing zeros included, as an integer, times 10
  to the minus the fraction's length, which puts values that land exactly half way after a
  translation on the side it writes them (2,267 of the 2,287 such coordinates in the corpus
  files nomac wrote otherwise: cwa's `Stars_half.pdf` 22.054075 − 2.215820 is written
  19.83825, firefox's `firefoxLoader.pdf` 100.911980 − 0.002930 100.909, `logo_mastercard.pdf`
  0.000000 + 186.781250 186.7812). A real in the file's objects (dictionaries, arrays) is read
  correctly rounded (`shadings` axial-fn3: a stitching bound 0.3), but the page's box, form and
  pattern matrices and bounding boxes and shading coordinates as operands are (kickstarter's
  `icon-globe.pdf`: 31.200195 is written 31.20019; a firefox pattern's -56.545895 -56.54589).
  Open: two of 133 experiment values, 0.025000025 and 0.000100001, sit exactly on a limit and
  are written otherwise, and 20 of those corpus coordinates are written one last digit up
  (BACKLOG B-216).

The content (`paths`, `colors`, `clips`, `details`, `extgstate`, `state-changes`, `icc`):

- `q Q`, then a `q … Q` block per clip operation in force when something is drawn (a clip set
  again with the same path after a `Q` is another block: Quartz-written corpus files), with the
  clip's paths each followed by `W n` or `W* n` (the paths that are not rectangles in order,
  then the rectangles, even-odd ones too, intersected into one with `W n`), then the fills. A
  clip nothing is drawn under is dropped; so is a rectangle around the rectangles in force,
  which changes nothing (kickstarter's `icon-expansion.pdf`); a clip without area hides what is
  drawn under it, which is dropped too (cwa's `Flags - Liechtenstein.pdf`, `x y m x y2 l W n`).
- Each fill's path in page coordinates (the transformation applied), one closed axis-aligned
  four-sided subpath (`m` and three `l`, or four back to the start, then `h`, either direction;
  not an `re` made under a transformation that flips) as `x y w h re` (normalized), anything else element by element (`v` and `y`
  as `c`, `re` among other subpaths as `m l l l h`), with `f` or `f*` (`F` is `f`). A move
  right after a move replaces it and a move after the last subpath stays (`x y m W* n` in corpus
  files); paths of moves alone and operators with malformed operands (an exponent) are dropped,
  as are comments, marked content, stroke settings and flatness.
- Before a fill, from the block's start (black, opaque, the relative colorimetric intent,
  smoothness 0, no overprinting), what changed, in this order (strokes below): `/Intent ri`, the smoothness
  (`/GsN gs`), the color (when it or the opacity changed), the opacity, fill overprinting
  (`op`, else `OP`) and its mode, each an ExtGState with that one entry (`/Type /ExtGState /ca
  0.5`), one per entry and value. An ExtGState's `RI` sets the intent; `CA`, `LW`, `SA`, `FL`
  and the like change nothing for a fill.
- Strokes (`strokes`): `S`, `B`, `B*` as given, `s` and `b` as `h S` and `h B`. A drawing that
  strokes under a transformation other than the identity (a translation too) is written in
  its own `q a b c d e f cm … Q` with the path in user space, the colors set before the `q`;
  fills alone are not. Before a stroke, the line settings that differ from the block's (width
  1, cap 0, join 0, miter limit 10, no dash) come first, `w J j M` then `[ … ] phase d`; then
  stroke adjustment (`/SA true`, false by default: `strokes-2`; uncloudnotes' `blue.pdf`); then
  the rendering intent and smoothness, the fill's color and states, then the stroke's color
  (`/CsN CS … SC`, `c m y k K`) and states: `/CA`, and `/OP`, followed by `/op` with the fill's
  value when it differs, since `OP` also sets fill overprinting where `op` is absent. An
  ExtGState's `LW`, `LC`, `LJ` and `ML` set the line; its `D` is not applied. A zero width is a
  one-pixel hairline in the rasters.
- Form XObjects (`xobjects`) are drawn in place: their content with their `/Matrix` and the
  transformation in force, clipped by their `/BBox` (one more clip rectangle, intersected with
  the others), with their own resources or else the page's; a form drawn twice is written
  twice.
- Transparency groups (`groups`, `groups-2`, `groups-3`): a form with a `/Group << /S
  /Transparency >>` stays a form, one `/FmN` per `Do`, its content in page coordinates written
  as a page's, from `q Q`, every drawing in it clipped to one rectangle: the bounding box of
  the clips around the `Do` (their curves' control points included) and the form's `/BBox`,
  rounded out to whole units, within the page's box (`groups-2` in-path-clip, in-two-clips,
  in-evenodd-clip; corpus: kickstarter's `icon--apple-pay.pdf`, 0.026 0.43 71.79 45.98 is
  written 0 0 72 46; cwa's `FamilyMember_CoronaTest_invalid_expired.pdf`, a page of 84.676758
  by 107.020996 is not rounded). In the stream that draws
  it, `/FmN Do` after the opacity in force (`/GsN gs` with `/ca`, which applies to the group
  as a whole; its content starts opaque) and fill overprinting and its mode as for a fill,
  which its content keeps; a stroke opacity is dropped, outside and inside (`groups-4`); in a
  `q … Q` block of its own that a drawing after it may join. A shading in a group is drawn
  with `/Perceptual ri`, whatever intent is set (`groups-6`). The form: `<< /Type /XObject /Subtype /Form /FormType 1 /BBox [x0 y0 x1 y1]
  /Resources n 0 R /Group << /S /Transparency /CS n 0 R /I true /K false >> /Length … >>`,
  whatever the source's `/I` and `/K`. `/CS` is the group's space: Apple's Generic RGB profile
  (1,992 bytes) when the source names none, DeviceRGB's sRGB one, an ICC profile byte for byte.
  `/BBox` is the union of what the content draws, each within the clips its content sets
  (counting their curves' control points) and the form's own `/BBox`, not the page or the clips
  around the `Do`: a fill's path, curves by their extremes; a stroke's path grown by half its width times the miter limit for miter
  joins (at least 2) and times 2 otherwise, before its transformation; a zero width
  everywhere. A group that draws nothing is dropped (no form, no `/Version`). Blend modes
  other than Normal put drawings in groups too (`groups` blend-multiply), not reproduced yet.
- Shadings (`shadings`): axial and radial ones, drawn by `sh` (`/ShN sh` after the rendering
  intent, the opacity, fill overprinting and its mode, as for a fill: `shadings-2`; under its own `q a b c d e f cm … Q` when the transformation is not
  the identity) or as a shading pattern's color (`/Pattern cs /PN scn`, `/Pattern cs` only
  when the space changes; `CS` and `SCN` for strokes). The shading: `<< /ColorSpace n 0 R
  /ShadingType t /Coords [ … ] /Domain [ … ] /Extend [ a b ] /Function n 0 R >>`, its color
  space as for colors; a pattern `<< /Type /Pattern /PatternType 2 /Matrix [its matrix]
  /Shading n 0 R >>`, numbered after a number it takes and never writes. Numbered when drawn;
  written before the ExtGStates, the patterns first (each numbering its shading), then the
  shadings (each numbering its function). Functions: a sampled one and a PostScript program
  kept, written after the catalog, the last first, then the fonts (kickstarter's
  `icon--currency-header.pdf`). A program is run symbolically (`postscript`, `postscript-2`):
  numbers and copies (`dup`) stay pending above the stack's values until an operator needs
  them there; pending numbers fold through `add`, `sub` and `mul` and swap through `exch`; a
  value plus or minus 0, or times 1, stays as it is; a value times 0 is `pop` and a pending 0
  (a copy times 0 just the 0); popping something pending drops it; what is pending at a
  procedure's start and end is written then (`{ 0 mul 1 add 0 exch 0 exch }` is `{ pop 0 0 1
  }`, `{ dup 0 mul pop 1 exch 0 exch }` is `{ 1 exch 0 exch }`). Tokens one space apart in
  braces; a number within a millionth of an integer as that integer, from 1 with seven
  significant digits, below 1 with six decimals, trailing zeros dropped (123.4567891 is
  123.4568, 12345678.5 is 12345678, 0.1234565 is 0.123456). The sampled one's entries `/Range /Order 1 /Decode
  /BitsPerSample /Domain /Encode /FunctionType /Size`); exponential and stitching ones sampled
  again right after the color spaces: `<< /FunctionType 0 /BitsPerSample 8 /Size [ 4096 ÷
  components ] /Domain [ … ] /Range [ each component's extremes ] >>`, the samples at even
  steps, rounded within the range (a value nomac puts a hair above a half, firefox's app icons'
  42.50008, Quartz rounds either way: B-215). nomac draws a shading through a 1,024-step table of its
  colors. Tiling patterns, shadings of other types and a function per component are not
  reproduced yet.
- Image XObjects (`images`) stay images, one object `/ImN` per image however often drawn:
  `q a b c d e f cm /ImN Do Q` in the block, after the rendering intent, the opacity, fill
  overprinting and its mode (`images-2`) and, for a stencil mask, the fill color; the stream's `/ProcSet` becomes `[ /PDF /ImageB /ImageC /ImageI ]`.
  The image: `<< /Type /XObject /Subtype /Image /Width w /Height h`, `/Interpolate true`, then
  `/ImageMask true` or `/ColorSpace n 0 R` (DeviceRGB's sRGB, DeviceGray's gray, an ICC
  profile byte for byte, as for colors) and the image's own `/Intent`, `/SMask n 0 R`, `/Decode [ … ]`, `/BitsPerComponent`
  `>>`, the samples compressed again (only the rows the size holds), a JPEG's bytes kept as
  they are with `/DCTDecode`, but an RGB JPEG with a soft mask's, which Quartz decodes and
  compresses with Flate, each sample premultiplied by the mask's alpha and divided again in 8
  bits (0 where the alpha is 0; a gray JPEG with a mask and an RGB one without are kept,
  `images-4`); TIFF predictor 2 samples decoded (`images-3`). A soft mask follows its image (its `/Matte` dropped,
  its samples as they are), `/ColorSpace /DeviceGray
  /BitsPerComponent 8`, and makes the catalog `/Version /1.4`. Numbered when first drawn,
  before a stencil's color space; written after the stream that draws it, as forms are, its
  color space numbered then and its soft mask after it. nomac draws each pixel with the sample
  under its center (a baseline JPEG decoded by nomac: half-size chroma upsampled with a
  triangle filter inside each 8×8 block, as Quartz's samples show in `images-4`; within ADR
  0204's bound of Quartz's own).
- Alpha soft masks (`smasks`): in force, an ExtGState `<< /Type /ExtGState /SMask << /G n 0 R
  /S /Alpha >> >>` written after everything else a drawing, group or image sets, and `/SMask
  /None` when it goes away; numbered with the stream's other ExtGStates, its form's resources
  and form numbered when it is written. The form follows the color spaces of what drew it:
  `<< /Type /XObject /Subtype /Form /FormType 1 /Resources n 0 R /BBox [the source's] /Matrix
  [the form's matrix then the transformation at the gs] /Group << /S /Transparency /CS
  /DeviceGray /I true /K false >>`, its content in its own space from `q Q` without clips,
  then the color spaces it adds. A mask whose form has no transparency group is ignored.
  A luminosity mask (`smasks-2`, `smasks-3`) is `/SMask << /G n 0 R /S /Luminosity /BC [ … ]
  >>`, the backdrop as given or 0 for each component of its group's space; its form's group
  takes that space as `/CS n 0 R`, numbered before the form's content: a space of its own (a
  `/CsN` name never written) whose object it shares with the space it names (DeviceRGB's,
  DeviceGray's, an ICC profile's), an ICC space also named for itself. A luminosity mask whose
  group names no space is ignored. A transfer function (`/TR`, alpha or luminosity) other than
  `/Identity` follows `/BC` as `/TR n 0 R`, numbered after the form, kept or sampled again as a
  shading's function is (pocket-casts' `Effects.pdf`: `{ 1 exch sub }`). nomac's rasters take the
  content's luminance (0.3 R + 0.59 G + 0.11 B) over the backdrop, the backdrop's outside the
  form's box, then the transfer function (PDF 1.7 § 11.5.3).
- Text in a Type 3 font (`text`) is written as what its glyphs draw: each glyph's procedure
  run as content under the font matrix, the size with the horizontal scaling, the rise and the
  text matrix, the colors it sets applied (`d0` and `d1` alike), the rendering mode ignored;
  the text matrix moves by the glyph's width times the size plus the character spacing (and
  the word spacing for byte 32), times the horizontal scaling, and by a `TJ` number's
  thousandths of the size. An empty glyph draws nothing (Figma's placeholders, all 137 Type 3
  glyphs of the corpus).
- Text in an embedded TrueType or CFF font (`fonts` to `fonts-6`, `cff` to `cff-3`) is
  written again as text, with fonts Quartz subsets from the embedded program. A TrueType
  code's glyph is found through the encoding's Unicode value in the font's Windows cmap, else
  the code in its Macintosh cmap, else the symbol range (0xF000 + code), else the code in the
  Windows cmap; a CFF code's by its name in `/Differences`, else in MacRomanEncoding, else in
  the font's standard encoding (a name the font lacks is `.notdef`). Each PDF font
  becomes up to two Quartz fonts, made at its first glyph shown and numbered then (each first
  takes the next object number and the next name index): a *MacRoman* font, made first even
  when unused, for the glyphs whose name (TrueType: `post`) MacRomanEncoding has (PDF 1.7
  annex D: not the mathematical symbols, `apple` or `Euro`; `currency` at 219, `space` at 32;
  `.notdef` at 0), at that code;
  and an *identity* font, for the other glyphs (all of them in a font without names, `post`
  format 3), at codes from 33 in the order first shown. A show is `BT`, the first space
  between glyphs as `x Tc` unless a space is 0, the first glyph's em (`[size × scaling, 0, 0,
  size, 0, rise]` times the text matrix) as one unit `a b c d e f Tm`, then per run of glyphs
  in one Quartz font `/TTn 1 Tf` and `(codes) Tj`, or `[ (codes) n (codes) ] TJ` where a
  space differs from the `Tc` (n = (Tc − space) × 1000, rounded to a whole number after a
  `Tc`, left out when that is 0), then `0 Tc` after a `Tc` unless the show is inside `q … Q`,
  then `ET` (`fonts-6`). A space is a glyph's advance in the PDF (width, character spacing,
  word spacing for byte 32, a `TJ` number) less its width as Quartz writes it, in whole
  thousandths of the em (cwa's `-0.0002 Tc` stays). Codes below 32 are written in octal
  (`\000`). Before `BT` come the fill color (rendering
  modes 0 and 2), the stroke color and line (1 and 2), as for a fill or stroke, nothing for
  mode 3, then `n Tr` when the mode changed; under a transformation, `q a b c d e f cm` (one
  unit) before `BT` and `Q` after `ET`. Every show has its own `BT`; colors set between
  shows are written between them. The resources take `/ProcSet [ /PDF /Text … ]` and `/Font
  << /TTn … /Tcn … >>` between `/ExtGState` and `/Pattern`; n counts the fonts of the kind
  (`TT` TrueType, `Tc` CFF), the subset tag all of them (cwa's `Icons_FaceID_light.pdf`:
  `/TT1`, then `/Tc2` tagged `AAAAAD`).
  After the catalog, each Quartz font used, in number order: `<< /Type /Font /Subtype
  /TrueType (or /Type1) /BaseFont /TAG+Name /FontDescriptor d 0 R [/Encoding
  /MacRomanEncoding | /ToUnicode t 0 R] /FirstChar f /LastChar l /Widths [ … ] >>` (a CFF
  identity font names its glyphs first: `/Encoding << /Type /Encoding /Differences [ 33 /name
  … ] >>`), then for an identity font the
  ToUnicode CMap (Adobe-Identity-UCS, `<00><FF>`, its codes as `<21><22><0041>` ranges of
  consecutive codes with consecutive values), then `<< /Type /FontDescriptor /FontName
  /TAG+Name /Flags 32 (MacRoman) or 4 /FontBBox [x y X Y] /ItalicAngle a /Ascent /Descent
  /CapHeight /StemV 0 /XHeight [/AvgWidth] /MaxWidth /FontFile2 n 0 R >>`, then the program
  `<< /Length1 … /Length … /Filter /FlateDecode >>` (CFF: `/StemV v /XHeight x [/StemH h]
  [/AvgWidth w] /MaxWidth m /FontFile3 n 0 R` and `<< /Subtype /Type1C /Length … >>`); the
  descriptor, CMap and program are
  numbered as they are written. The tag counts the name index from `AAAAAA` (index 1
  `AAAAAB`), `/TTn` is the index too; the name is the font's PostScript name without a subset
  tag of its own, and `font` with 16 hexadecimal digits Quartz takes from memory without one.
  Widths (the font's advances, 0 for codes not shown) and metrics are in thousandths of the
  em, rounded: the box's origin and size each from `head` (its far corner their sum: SF Pro's
  1249.51 is written 1249), ascent, descent and maximum advance from `hhea`, the italic angle
  from `post`, cap and x heights from OS/2 (version 2 on), else the means of the tops of `H`
  and `O`, `x` and `o` (a letter the font lacks counting 0), else 8/9 and 2/3 of the ascent in
  font units, truncated; the average width from OS/2 when the font has one. A CFF font's box
  is its top DICT's grown on each side by 6% of the em, at most 31 font units (`cff-3`: 16 to
  4,096 units per em), origin and size rounded each, the maximum width that box's width; its
  ascent and descent the box's top and bottom before growing, its cap and x heights 8/9 and
  2/3 of the ascent in thousandths, truncated; `StemV` and `StemH` the Private DICT's `StdVW`
  and `StdHW`, the average width its `defaultWidthX` when not 0. The glyph's
  Unicode value is the PDF's `/ToUnicode` one, else its name's for WinAnsi names outside
  MacRomanEncoding (`Euro`, `Scaron`, `onehalf`…), else for TrueType the encoding's (MacRoman
  without one).
  Quartz draws a glyph with its left edge at its `hmtx` side bearing. The program is Quartz's
  own subset (TrueType: its tables but `name` and `maxp` kept, a new `name`, or eight tables
  for an identity font): nomac writes a subset of its own, which renders alike (ADR 0204);
  CFF ones keep the subroutines and Private DICT. TrueType codes of other encodings
  (Differences, StandardEncoding), CFF codes of WinAnsiEncoding, CID-keyed fonts, clipping
  rendering modes and a show spaced across both Quartz fonts stop nomac. Other fonts are
  refused, saying when the font is not embedded and Quartz would take macOS's own.
- Colors: DeviceRGB and DeviceGray become ICCBased spaces with Apple's sRGB (3,144 bytes) and
  gray (4,508 bytes) profiles, written `/CsN cs … sc` at each change; an ICCBased space keeps its
  own profile, byte for byte (one space for all copies of a profile), its `cs` written only when
  the space changes. A `DefaultRGB` or `DefaultGray` resource makes the device space that ICCBased
  space in colors and images, in the resources in force (a form with its own resources has its
  own, one without them the page's), but not in a shading's dictionary (`default-spaces`).
  DeviceCMYK stays `c m y k k`. Quartz's rasters convert CMYK through its CMYK
  profile; nomac's do so for grays only (C, M and Y 0), with the sRGB measured on actool's rasters
  at each quarter of 1/255 of K (`cmyk-k`: 0 is white, 1 is 26 26 26, 1/255 is 255 254 253, the
  same at 1x and 3x); other CMYK colors, and K between those steps, stop nomac. A page with no color set has no color space.

nomac writes its own sRGB and gray profiles (`PDFProfiles`) where Quartz embeds Apple's; `nomac
verify` accepts that difference (ADR 0204), and its sRGB one in place of Generic RGB. JPEG
2000, JBIG2 and fax images, color-keyed and CMYK images, text in fonts other than Type 3 and
embedded TrueType and CFF ones, tiling patterns, shadings other than axial and radial ones,
luminosity soft masks other than gray and RGB ones, blend modes and a PDF per scale stop nomac
(BACKLOG B-215).

### JPEG images (`vector-images`)

A JPEG file in an image set is stored as a file, not pixels, one rendition per entry: flags as
a PNG's, no size in the header, the size in the slices and metrics (1001, 1003), scale ×
100, pixel format `JPEG`, color model 0, layout 12, properties 1001, 1003, 1004, 1006, payload
`DWAR`, 0, the length and the bytes, never packed. The bytes are the file's as ImageIO writes
it again: the APPn segments other than JFIF's APP0, Exif's APP1, the ICC profile's APP2 and
Adobe's APP14 are left out, and comments (XMP, APP9, APP12, Photoshop's APP13, COM seen), the
kept APPn segments first in marker order, the other segments as they are; an Exif segment
whose first directory is empty is left out, one that is big-endian with only orientation,
resolution, software and date beside a resolution, and an Exif directory of color space, pixel
size and user comment is kept as it is (55 of the corpus's 64 image set JPEGs identical); other
Exif forms are rewritten (little-endian ones become big-endian, YCbCrPositioning goes, camera
tags change), where nomac stops (B-200).

### Symbol sets (`symbol-sets`)

A symbol set's template (SF Symbols' SVG template, versions 1 to 6 seen) gives one vector
rendition per glyph and nine monochrome rasters (46 of the corpus's 47 symbol sets equivalent):

- **Template.** Glyphs are the `Symbols` group's `<weight>-<size>` groups, placed by their own
  transform and their groups' translations. Guides are the `Baseline-`/`Capline-` and
  `left-margin-`/`right-margin-` elements: a `line`'s first point; a `path`'s `M` (mastodon's
  Phosphor symbols), its x moved half the inherited stroke width left when the path is stroked
  (a stroke of 2 moves it 1, no `stroke` paint leaves it), y unchanged. The version is a `text`
  element's own text `Template v.N`; template 1 writes it in a `tspan`, which reads as 0. Below
  version 2 the margins are the sidebearings themselves: a `rect`'s width (template 1's
  rectangles), a vertical line's stroke width; unsuffixed `left-margin`/`right-margin` are
  Regular-M's. Points per unit: 17 over the medium cap height in units divided by 1443/2048,
  rounded half to even.
- **Vector renditions.** Key: weight (attribute 26, 1 to 9), size (27, 1 to 3), target 25 = 5,
  scale 1, part 59; CSI flags 4, pixel format `SVG `, layout 1017, properties 1004, 1006, 1018
  (7 for interpolatable templates of version 3 and later, else 3; 17; floats: the glyph's
  bottom below the baseline, the cap height, the version, each sidebearing and its unit 140 ×
  17 / 2048 times the size factor; and for the reference glyph the raster point sizes) and
  1019 (1; the set's `symbol-rendering-intent`: `template` 1, `multicolor` 2, `hierarchical` 3,
  others 0; 1 for multicolor rules plus 2 for hierarchical ones). The payload is the glyph as its
  own SVG: a viewBox of its bounding box in points (a stroked path's box grows by half its
  stroke width, including strokes from style-sheet classes such as template 5's
  `SFSymbolsPreviewWireframe`); the style sheet's rules but the preview's, sorted by name, each
  rule's standard declarations then vendor-prefixed ones, each sorted; a group `s` whose matrix
  is the point scale, the translation to the box and the glyph's own transform (icecubes'
  Inkscape-scaled masters); the paths with numbers as `%g`, their attributes sorted with
  namespaced ones last by local name, style properties as attributes in CSS precedence
  (attribute, class rule, `style`) without vendor-prefixed ones, stroke widths in points, an
  emptied `class` kept; nested groups with their attributes as they are.
- **Rasters.** Regular-M (or Regular-M interpolated from the S masters, then placed by
  Regular-S's transform) at 15, 17 and 20 points (dimension 2 = 0, 1, 2) and scales 1 to 3,
  sized by the glyph's box rounded up, drawn monochrome (every layer opaque black, no
  strokes), flags 4, gray, packed in atlases keyed with target 5; links' `KLNI` layout field is
  0. Their pixels are CoreSVG's; nomac draws its own (ADR 0204).
- Template 6's `LayerTree` (nextcloud) is not written yet (B-202).

### watchOS catalogs (`watchos`)

`--platform watchos --target-device watch` (home-assistant's watch app and widgets; watchOS 9.0
and 6.0 give the same outputs): `Assets.car`'s header names the platform `watch` and its
authoring tool string the watchOS SDK's `CMPhoto[1][218]` (iOS: 219). Universal entries only;
PNG and JPEG files at 1x and 2x, a 3x file left out; an SVG rasterized at 2x only, its vector
rendition as on iOS. A symbol set's glyphs have every metric 0.94634 times iOS's (16.088 points
for iOS's 17: cap height, sidebearings, margin units) and one raster, 17 points (dim2 0) at
2x, stored alone with CSI layout 0. A single-size app icon of platform `watchos` gives its size
table and images for the watch idiom (5), no PNG, and `CFBundleIcons` with only
`CFBundleIconName`. A multi-size watch icon set (Xcode's watch template: notification center,
companion settings, app launcher and quick look icons, `watch-marketing`) gives images keyed with
the watch idiom and their case size's subtype (38 mm 320, 40 mm 340, 41 mm 430, 42 mm 384,
44 mm 390, 45 mm 484, 49 mm 502; an app launcher icon for 38 mm and companion settings icons
none; `watch-marketing`: idiom 6), `dim2` numbering the distinct point sizes, a size table per
idiom and subtype, packed per subtype with the subtype in the atlas's key and its numbering, no
PNG, and only the icon's name in the partial Info.plist. In `BITMAPKEYS` masks a subtype has a
bit of its own: 320 → 8, 384 → 9, 340 → 13, 390 → 14, 430 → 23, 484 → 24, 502 → 28 (1792 →
16; 42 mm's bit before 40 mm's, seen with one screen width per set). Color and data sets are as
on iOS but for appearances: only the entries for any appearance are kept, images and colors
alike (dark, light and high-contrast ones are left out; home-assistant's watch catalogs,
`image-appearances` watch cases). Entries for the watch idiom are compiled with idiom 5, images,
colors and asset symbols alike; app icons and images of one scale, idiom and subtype are packed together, the atlas
stored as images' are (deepmap2); PDF images are rasterized at 2x only, as SVG images
(pocket-casts' watch catalog). Not observed yet: watchOS before 6.0 (B-206).

### Complications (`complications`)

An image entry for the watch idiom may name a screen width: `<=145`, `>145`, `>161` and `>183`
(38, 42, 40 and 44 mm) give subtypes 320, 384, 340 and 390; others get ``Unknown screen-width
value "<value>"`` and an unassigned-child warning, where nomac stops. A complication set
(`.complicationset`, pocket-casts' watch app) lists image sets with the watch idiom and a role
(`circular`, `extra-large`, `graphic-bezel`, `graphic-circular`, `graphic-corner`,
`graphic-extra-large`, `graphic-large-rectangular`, `modular`, `utilitarian`). actool compiles
only the one `--complication` names: its image sets as image sets named `<set>/<image set>`, as
in a folder providing a namespace, in `Assets.car` and in the asset symbols; the partial
Info.plist gets `CLKComplicationDefaultImagesAssetName` with the name. Other complication sets,
and all of them without the option, are left out silently; a name the catalog lacks gets the
notice ``<first catalog>: warning: The asset catalog does not contain a complication named
"<name>".`` and no key. An entry for a missing folder is passed over. Each role has an image
size per screen width (pixels at 2x for 38, 42, 40 and 44 mm): circular 32, 36, 36, 40;
extra-large 182, 203, 203, 224; graphic-bezel and graphic-circular 84 and 94 (40 and 44 mm);
graphic-corner 40 and 44; graphic-extra-large 206, 240, 240, 264; graphic-large-rectangular
300 × 94 and 342 × 108; modular 52, 58, 58, 64; utilitarian 40, 44, 44, 50. Another size gets
warnings repeated a varying number of times; an unknown role gets ``Unknown role value
"<role>"``, an image set the list leaves out ``The watch complication set "<set>" has an
unassigned item "<image set>".`` printed twice, both still compiled. nomac stops on these three.
The 8 cases without warnings are identical.

### HEIC images (`heic`)

An opaque HEIC file in an image set (icecubes; files written by sips in the experiment) gives
two renditions, never packed, both with the image's size in their slices and metrics and the
set's rendering-intent flags (0x10 by default):

- Its decoded pixels: pixel format `RGB5` (1-5-5-5, the top bit 0, little-endian), color model
  1, property 1007 the width × 2 rounded up to 32, in the plain payload (rows padded to 32
  bytes; raw below 4,096 bytes, one LZFSE stream below 4,096 pixels, LZFSE bands from there;
  `CELM` flag 2). nomac decodes with libheif's `heif-dec` (Ubuntu `libheif-examples`) and
  stops with a message when it is missing; the pixels are equivalent (ADR 0204).
- For target 2 (attribute 25), the file as ImageIO writes it again: pixel format `HEIF`, no
  size in the header, color model 0, no property 1007, in a `DWAR` payload (flag 0). The HEVC
  data is not re-encoded: the items stay; an Exif item, the file's or a new hidden one (infe
  version 2, flag 1, the next item ID, an `iref` `cdsc` to the primary item), holds ImageIO's
  big-endian Exif (the file's first directory, Orientation 1 added when missing, TileWidth and
  TileLength the image's size: a new item's the displayed size after `clap`, a rewritten one's
  the coded `ispe` size), its data first in a 64-bit `mdat`, the others in the file's order;
  `ipco` has the `hvcC` boxes last and each `ipma` lists its properties in order, the
  transformative ones (`clap`, `irot`, `imir`) last; `ftyp` names `heic` and `mif1` only when
  the file names MIAF brands and the image is under 64 pixels on a side. The 6 experiment cases
  and the corpus's 3 HEIC files give it byte for byte.
- A HEIC file with an alpha plane (pocket-casts' mockups; the experiment's alpha cases) gives
  the same HEIF rendition, and for its decoded pixels pixel format `ARGB`, color model 1, the
  colors premultiplied. Its payload is `CELM` compression 5 (`jpeg-lzfse` in `assetutil`), flags
  0, when that payload takes less than a byte per pixel, with property 1007 the width × 4
  unpadded: two zero words, the alpha stream's length, the width and the JPEG's length (32-bit,
  little-endian), the alpha plane (a byte per pixel, rows from the top) as an LZFSE stream, then
  the premultiplied colors as a baseline JPEG. Otherwise it is the plain payload of PNG images
  (raw, run-length or LZFSE, property 1007 the width × 4 rounded up to 32). Neither the image's
  size nor the smaller payload decides it: in a 9 × 9 grid of sizes from 16 to 300 pixels the 57
  `jpeg-lzfse` payloads all take under a byte per pixel (the largest 0.99), the JPEGs of the
  others, estimated with libjpeg at the same tables, over it; and a flat 120 × 100 image gets
  2,089 bytes of `jpeg-lzfse` where LZFSE would take 219.
  The JPEG: JFIF 1.1 with a 72:72 aspect ratio, an Exif segment (big-endian, a first directory
  holding only the Exif directory's offset, which holds ColorSpace 1 and the pixel size), a
  Photoshop 3.0 segment with an empty IPTC record and its MD5 digest, an 8-bit YCbCr frame
  without subsampling, the four standard Huffman tables of ITU T.81 Annex K, the quantization
  tables of AppleJPEG's quality 0.9 (`sips -s formatOptions 90` writes the same), a restart
  interval of one row of blocks. nomac's alpha streams and JPEG headers are identical to
  actool's; its own JPEG coder's scan differs from AppleJPEG's (ADR 0204). Its sizes are within
  about 5 % of AppleJPEG's, so images whose payload comes within that of a byte per pixel may
  get the other format than actool's.

### Sprite atlases (`sprites`)

A `.spriteatlas` folder (flappy-fly-bird's two; `sprites`: 12 cases identical) holds image
sets, which keep their names and facets; their images, at one scale and idiom, go into an
atlas of the sprite atlas's own instead of the classes above:

- Each image is cut to the bounding box of its pixels whose alpha is not 0. Its link
  rendition is a packed image's (layout 1003, flags 0x10, its class's pixel format, `GA8` for
  gray) with the cut size, property 1001 the original size, 1003 the cut size, and, when
  something was cut, after 1006, property 1011: 1011, 0, the original width and height, then
  the kept rectangle's x, y from the top, width and height (4-byte numbers).
- The images are placed by the growing binary-tree packer in packing order, all of them: four
  images of 120 × 100 pixels share one atlas, past the classes' area limit. The atlas is
  `ZZZZExplicitlyPackedAsset-<scale>.0.0-gamut0` whatever its images' opacity and grayness:
  key scale (and idiom), the sprite atlas's identifier, element 9, part 181; CSI flags 0,
  `ARGB`, color model 1, layout 1004, deepmap2 not flagged opaque, properties 1001 (1, zeros),
  1012, 1020, 1021, 1022, 1004, 1006, 1007. Each of 1012 to 1022 is the image count, 0, then
  per image in identifier order: 1012 six zero words, the float 1.0, 20 and the image's key
  ((1, 85), (2, 181), (12, scale), (17, identifier), (0, 0)); 1020 eight zero bytes, 1 and a
  zero byte; 1021 20 zero bytes; 1022 12 zero bytes.
- A part-127 rendition `CoreStructuredImage` (key scale 1, the sprite atlas's identifier,
  element 9): CSI scale 100, layout 1005, properties 1004 (eight zeros), 1006 (1) and 1013:
  the image count, 0, then each image name in name order as a 4-byte length and its bytes.
- The sprite atlas's facet has element 9 and the identifier, no part.
- Observed, not reproduced (B-202): images of 1,900 × 1,900 pixels stay alone (1,500 × 1,500
  are packed), and four of 1,000 × 1,000 share an atlas but a fifth starts a second one (and
  two of 1,500 × 1,500 do); nomac stops beyond 2,250,000 pixels per image or 3,000,000 in all,
  and on sprite atlases of several scales or idioms.

### visionOS icon stacks (`images`)

An iOS build writes nothing for a `.solidimagestack`: the car and the partial Info.plist are
identical with and without it. actool checks it (`icon-stacks`, 30 cases), and reports twice,
under `/* com.apple.actool.document.errors */` before the document warnings, as
`<catalog>:./<stack>: error: <message>`, and still exits with 0, also when generating symbols:

- `The last visionOS App Icon Layer with content, “Back”, must exactly fill the image stack. Its
  current frame is {{0, 0}, {242, 256}} while the visionOS App Icon's size is {512, 512}.` for a
  layer of 484 × 512 pixels at 2x. Only the last layer in the `layers` list with an entry naming
  a file counts: other layers may have any size (vlc's), and a stack without content has no
  such layer (sdwebimage's). The size in points is the PNG's over the entry's scale, no scale
  being 1x (`{242.5, 256.5}` for 485 × 513), for the idioms `vision`, `reality` (a former name;
  NetflixVisionPro's), `universal` and `iphone` alike.
- `The visionOS App Icon “Icon” must have at least 2 layers.` and `... may not have more than 3
  layers.`, counting layers in the list with or without content or folders, after the message above.

A `vision` entry at 1x or 3x adds an unassigned child warning, and an entry naming a missing file
a warning; nomac stops on those, on layers of several images (one of them is called unassigned)
and on files other than PNGs (B-202), and on stacks with errors when generating symbols (B-204).

### Deployment-target variants (observed; variant 0's format reproduced for app icons)

With a minimum deployment target of 11.x every image rendition exists three times, with the
deployment-target attribute (25) 0, 3 and 5, and the key format has `dim1` and the deployment
target between subtype and identifier; 12.x has 0 and 5; 13.0 and later one, without that
attribute.

- 5: deepmap2, as above.
- 3: `CELM` compression 8, one LZFSE stream of a palette image: `0xCAFEF00D`, 1, the color
  count (2 bytes), the colors (4 bytes, the BGRA bytes reversed) in the order they first occur
  in rows from the top, then one index byte per pixel with every pair of bytes swapped.
- 0 (552 self-written images): rows padded with zeros to a multiple of 32 bytes (8 BGRA or 16
  gray pixels). Below 4,096 bytes of rows: RLE (compression 1) if strictly smaller, else the
  rows (compression 0). RLE is the bytes per pixel (4, or 3 for `GA8`), width and height, one
  row offset per row (a row equal to the one above reuses its offset), then per row runs of at
  least 4 (BGRA) or 6 (gray) equal pixels as `0x80000000 | n` and the pixel, and the pixels in
  between as `n` and the pixels, unaligned. From 4,096 bytes: compression 4, LZFSE: with
  n = 3 bands from 20,480 bytes, else 2, of ⌊height / n⌋ rows (the last band the rest) when the
  image has at least 4,096 pixels and a band has a row, each `KCBC`, 0, 0, rows, length and
  the stream, the rows left over making one more band (1,024 rows give 341, 341, 341 and 1);
  otherwise one stream. App icons and their atlases use this format at every deployment
  target; nomac writes it (`PlainImagePayload`, uncloudnotes' icons). These streams are libcompression's `compression_stream`
  given the whole input: in windows of 786,432 bytes, the next starting 262,144 bytes before the
  previous one's end minus 400, matches not starting in the last 400 bytes of a window but the
  last one's, and an internal output buffer of 786,432 bytes that, when full at a block, makes
  the window restart 262,144 bytes before that point if it advanced more than 524,288 bytes
  (every stream actool wrote in 19 bands of up to 22 MB matches this). Below 4,096 bytes the
  stream is what `compression_encode_buffer` writes (LZVN). The encoder restores its state when
  its output is full, as the reference's does, and goes on once half of it is drained.
  `LZFSE.encodeStream` ports this; it matches libcompression on generated inputs over windows
  and output-buffer stops and on uncloudnotes' 1,024-pixel icon.

### App icons (`app-icons`)

- **App icon sets without images** (`app-icons`): a set whose entries list sizes but no
  `filename`, as new projects and retro-rampage have, compiles to nothing, with or without
  `--app-icon` naming it: no rendition, no facet, no Info.plist key, no warning. `--app-icon`
  naming no set prints `/* com.apple.actool.errors */` and `<first catalog>: error: None of the
  input catalogs contained a matching stickers icon set, app icon set, or icon stack named
  "<name>".` (two spaces before the quote) before the compilation results; actool still writes
  its outputs and exits with 1.
- **App icons.** A single-size 1024×1024 icon (`--app-icon AppIcon`) gives two PNGs next to
  `Assets.car` (`AppIcon60x60@2x.png`, `AppIcon76x76@2x~ipad.png`, resized by actool), a
  partial Info.plist with `CFBundleIcons` and `CFBundleIcons~ipad` (`CFBundlePrimaryIcon`:
  `CFBundleIconFiles` `AppIcon60x60` (and `AppIcon76x76` for iPad), `CFBundleIconName`
  `AppIcon`), the report listing the PNGs before `Assets.car`, and per device idiom a
  layout-1010 rendition (part 218, 24-byte payload) and the 1024 image (part 220, `dim2` 1).
  (`single-size-icons`, 33 cases: the car and partial Info.plist identical, the PNGs but their
  image data.) `--standalone-icon-behavior all` changes nothing; `none` writes no PNG and no
  `CFBundleIconFiles`; iOS 15.0 gives the same renditions. Only the targeted idioms get renditions, each appearance's image (dark:
  appearance 1, tinted: 10) for each; both PNGs are written for any target, and each idiom's
  key names the icon only when that idiom is targeted. The PNGs are CgBI RGBA whatever the
  input's form (gray, palette and `tRNS` inputs included), the input's chunks replaced by
  `gAMA`, `sRGB` (intent 0), `cHRM` and an `eXIf` (big-endian, an Exif directory of color space
  1 and the pixel width and height), in halves after `iDOT`; their pixels are nomac's own (ADR
  0204).
- Mac entries (`mac` idiom, 16 to 512 points) in an iOS app icon set are left out entirely
  (`alternate-app-icons` with-mac; flutter-platform-channels, home-assistant, netnewswire).
- **Multi-size app icon sets** (`app-icons`, 17 cases identical with their PNGs;
  uncloudnotes' Xcode build): the set `--app-icon` names, whose entries with files are iPhone
  (20 and 40 pt at 2x and 3x, 29 pt at 1x to 3x, 57 pt at 1x and 2x, 60 pt at 2x and 3x), iPad
  (20, 29, 40, 50, 72 and 76 pt at 1x and 2x, 83.5 pt at 2x) and `ios-marketing` (1024 pt at
  1x) sizes. `--target-device` changes nothing but the notices; nomac stops on sets without an
  iPhone 60 pt 2x or an App Store icon, on iPad builds without an iPad 76 pt 2x (actool warns;
  not reproduced). App icon sets `--app-icon` does not name add nothing, without a message
  (icons-not-named, icons-other-set-named).
  - `dim2` numbers the set's distinct point sizes from 1 in increasing order, a 90 pt size
    included when there is an iPhone 60 pt 3x image (83.5 sorts as itself).
  - One part-220 image per entry (key idiom 1, 2 or 6 for `ios-marketing`, scale, `dim2`;
    CSI flags 0, the file's name), and the iPhone 60 pt 3x image a second time at scale 2 with
    `subtype` 1792 and the 90 pt `dim2` (CSI scale 200); packed by class like other images
    (`subtype` is part of the class, so that copy stays alone), their payloads and their
    atlases' without deepmap2 (the deployment-target-0 format, below), property 1007 the width
    times 4 bytes (2 for gray) rounded up to 32. nomac stops when an app icon would share an
    atlas class with an image set's image (not observed).
  - Per idiom with images (1, 2, 6), and for idiom 1 with `subtype` 1792 when that copy exists,
    a part-218 rendition named after the set: scale 1, flags 0, no size, layout 1010,
    properties 1004 (eight zeros) and 1006 (1), payload `MSIS`, 1, the count and per size in
    increasing order its width and height in whole points and its `dim2` (the 1792 one lists
    only 90 × 90). The facet is the set's name with part 220; `BITMAPKEYS` gives `subtype` 1792
    bit 16.
  - PNGs next to `Assets.car` (`AppIcon60x60@2x.png`, `AppIcon76x76~ipad.png`, ...: the name,
    the size as written, `@<n>x` above 1x, `~ipad`): without `--standalone-icon-behavior` the
    iPhone 60 pt 2x and iPad 76 pt 2x images, with `all` every iPhone and iPad image, with
    `none` none; CgBI PNGs (below). nomac stops without `--compress-pngs` (not observed).
  - Partial Info.plist: `CFBundleIcons`, and `CFBundleIcons~ipad` when the set has iPad
    images, each `CFBundlePrimaryIcon` with `CFBundleIconName` the set's name and, when PNGs
    were written, `CFBundleIconFiles`: the iPhone PNGs' names without scale and extension in
    increasing size, once each, and for iPad those then the iPad ones not already listed.
  - Notices, under `/* com.apple.actool.document.notices */`, for entries of targeted devices
    in idiom, size and scale order, as `<catalog>:./AppIcon.appiconset/[][<idiom>][<size>][][][<scale>][][][][]: notice: <text>`:
    iPhone 57 pt (`57x57 app icons ...` and `57x57@2x app icons only apply to iPhone apps
    targeting releases of iOS prior to 7.0`), iPad 50 pt (`50x50 iPad spotlight icons ...`),
    72 pt (`72x72 app icons ...`, `72x72@2x ...`) and 76 pt 1x (`76x76@1x app icons only apply
    to iPad apps targeting releases of iOS prior to 10.0.`, with the final period).
- **Launch image sets** whose entries all have an `extent` and no file, as uncloudnotes' has,
  add nothing and print nothing. An entry without an `extent` is reported twice under
  `/* com.apple.actool.document.warnings */` as `... has an unassigned child.`, where nomac
  stops; launch images with files are B-202.

### Icon PNGs next to Assets.car (`app-icons`)

With `--compress-pngs`, actool writes the icon PNGs of RGB and RGBA inputs as Apple's CgBI PNGs
(19 corpus icons of uncloudnotes, flappy-fly-bird, tofu and netnewswire and 33 self-written
ones identical, gray, translucent and every icon size included):

- `CgBI` (`50 00 20 06` for an opaque image, `50 00 20 02` otherwise), `IHDR` (8-bit, color type
  6), the ancillary chunks, then the image data and `IEND`. The data is every row with filter 0
  and the premultiplied BGRA pixels `Assets.car` stores, as a raw deflate stream (no zlib
  header) equal to zlib's at level 9, window bits −15, memory level 9, `Z_FILTERED`.
- Images of more than 3,600 pixels (60 × 60 has one `IDAT`, 81 × 60 two; no icon size lies in
  between) are written in halves: the top ⌈h / 2⌉ rows ended by a full flush, then the rest,
  in one `IDAT` each, announced by `iDOT` (2, 0, the top's rows, 40, the top's rows, the
  bottom's rows, the second `IDAT`'s offset from the start of `iDOT`, as 4-byte numbers).
- Ancillary chunks follow the input (`app-icons` icon-chunks cases, netnewswire), copied as
  they are in the order `gAMA`, `sRGB`, `cHRM`, `eXIf`, `iTXt`, `pHYs`, then the `tEXt` chunks
  in their order; `sRGB` (intent 0) brings `gAMA` 45,455 and sRGB's `cHRM` (31,270, 32,900,
  64,000, 33,000, 30,000, 60,000, 15,000, 6,000) when the input has none. Observed, not
  reproduced (BACKLOG B-212): `bKGD` and `tIME` are copied (their place among the others is not
  known); `zTXt` is rewritten as a raw deflate stream without zlib's header and checksum.
- 8-bit gray and gray-and-alpha inputs without `tRNS` (wikipedia's sticker icons, `app-icons`
  icon-gray-type cases) give plain PNGs: no `CgBI`, `IHDR` with the input's color type, the
  same ancillary chunks, then the input's own samples (not premultiplied), each row with filter
  0, as a zlib stream at level 9 with `Z_FILTERED` whose window bits are libpng's for small
  data (from 15 down while the data plus 262 bytes fit in half the window), in halves after
  `iDOT` as above.


### Which chunks an icon PNG keeps (`icon-chunks`)

The icon PNG takes each chunk as this table says, whatever order the input has them in; of a
repeated chunk the first counts, but the text chunks. `early` chunks come right after `IHDR`:

| Place | Chunks |
|---|---|
| early | `gAMA`, `sRGB`, `iCCP`, `sBIT`, `cHRM`, then every other ancillary chunk safe to copy (a lower-case fourth letter) in file order, which is where `iTXt`, `eXIf`, `caNv` and `vpAg` go; `prVW`, `cICP`, `mDCV` and `cLLI` are not safe to copy and are left out |
| plain PNGs only | `PLTE`, `tRNS` |
| late | `bKGD` of the image's length (1 byte for a palette, 2 for gray, 6 for RGB; others are left out), `hIST` with a palette, `oFFs`, `pCAL`, `sCAL` with its numbers written as `%.12e`, `pHYs`, `tIME`, `sPLT`, then `tEXt` and `zTXt` in file order, `zTXt` deflated again |
| after the image data | `tIME` when none came before, then `tEXt` and `zTXt` read after the data; every other chunk there is left out |

`sRGB` brings `gAMA` 45,455 and sRGB's `cHRM` in place of the file's and leaves `iCCP` out. CgBI
PNGs deflate raw (no zlib header), plain ones with one. A wrong checksum on any ancillary chunk:
actool lists the PNG and does not write it, and `copypng -compress` prints pngcrush's error,
writes nothing and exits with 0. An unknown critical chunk: ImageIO cannot read the file and the
entry is left out without a word.

8-bit RGB and RGBA inputs give CgBI PNGs (RGB with `tRNS` still has the opaque flag); every other
form gives a plain PNG of its own samples at its own depth, palette and `tRNS` included, each row
with filter 0. Interlaced inputs stay interlaced, CgBI ones too, rows pass by pass. Images of at
least 4,096 pixels in two rows or more are written in halves, 8-bit and not interlaced only (65 ×
63 no, 64 × 64 and 2,048 × 2 yes, 4,097 × 1 no). The smaller zlib window is for 8-bit samples only.

### Damaged color profiles (`bad-profiles`)

actool never stops on an `iCCP` chunk, and says nothing about one it cannot use. `Assets.car` and
the icon PNG read it by two rules:

- Pixels (ImageIO): an `sRGB` chunk before any `iCCP` chunk means no conversion. Of the `iCCP` chunks
  before `PLTE` and the image data, the last one that passes converts: a name of 1 to 79 bytes,
  method 0, a zlib stream whose checksum and trailing bytes are not looked at (the chunk's own
  checksum neither), a profile whose size field is its length, with `acsp`, version 2 or 4, class
  `mntr` or `scnr`, the image's color space (RGB on RGB, gray on gray), XYZ connection space, its
  colorants and curves. Anything else leaves the image untagged: as if the chunk were not there.
- Icon PNG (pngcrush): the first `iCCP` chunk before the image data with a name of at least one
  byte, a zlib stream with its checksum right, and a profile of at least 4 bytes whose size field
  is at most its length, the profile cut to that size. The method byte is not looked at; a name
  over 79 bytes is written as 80 bytes and one NUL. So a profile can be in the icon PNG and not
  in the pixels (`bad-signature`, `wrong-method`), or the reverse (`bad-adler`).

### Entries an app icon set does not use (`incomplete-icons`, `icon-entries`)

A set compiles whatever it has. With `--warnings` actool prints, for what the targeted devices
lack, `A 60x60@2x app icon is required for iPhone apps targeting iOS 7.0 and later` (iPhone), `A
76x76@2x app icon ... iPad apps targeting iOS 7.0 and later` and `A 83.5x83.5@2x app icon ...
targeting iOS 9.0 and later` (iPad) and `A 1024x1024 app store icon is required for iOS apps`
(always). `CFBundleIcons~ipad` is there when the set has iPad entries or the build targets iPads;
its `CFBundleIconFiles` only when an iPad PNG is written, the iPhone's first.

Entries:

- Car entries of 60 × 60 at 2x and 3x are renditions of idiom 4, for any target.
- Other sizes, scales and idioms (`tv`, `vision`, `watch` beside iOS entries, universal entries
  without a platform), and files no entry names, add nothing. They give `The app icon set "X" has
  an unassigned child.` or `has N unassigned children.`, naming a stray file before the entry with
  the lowest file name. Mac entries give nothing at all. Keys such as `expected-size` and `folder`,
  and the set's `properties`, change nothing.
- An image of the wrong size (`X.appiconset/f.png is 100x100 but should be 120x120.`) or a missing
  file (`The file "f.png" for the image set "X" does not exist.`) is left out, then counted as
  lacking. A file that is no image is left out without a word. A `.jpg` is stored as an image
  set's JPEG; one in the 60 pt or 76 pt 2x slot also gives a plain PNG, which nomac does not write yet.
- A named set with files of other platforms only (mac, watch on iOS) gives actool's error `The
  stickers icon set, app icon set, or icon stack named "X" did not have any applicable content.`
  and status 1; one without any file gives nothing.

These warnings go over a set three times: the unassigned line and the entries' lines, the required
ones once after the first pass, and the second pass does not count `tv` entries. The order of the
entries' lines changes from run to run (ADR 0203); comparisons sort them.

`--warnings` and `--notices` choose what prints: `document.warnings` with either, `document.notices`
with `--notices`; `com.apple.actool.errors` and `com.apple.actool.notices` print with neither, in
the order errors, notices, document warnings, document notices.

### Entry traits (`image-traits`)

- `language-direction`: key attribute 4, after the display gamut and before the identifier, 5 for
  left to right and 4 for right to left. A set with one direction has flag 0x40 on all its
  renditions, a set with both has not. Directions do not split packing classes; within a size
  images pack in key order, the direction before the identifier. Entries with and without a
  direction beside each other keep only one of them; nomac stops on that.
- `alignment-insets`: property 1003's four numbers are left, top, right, bottom, as signed words, and
  its size what they leave of the image; a PNG's in its pixels, a vector file's rasters' times the
  raster's scale.
- `resizing`: the image is cut to caps and center (from the center's start), and that is the
  image. Layout 31 or 30 for `9-part` with a `stretch` or `tile` center, 21 or 20 for
  `3-part-horizontal`, 24 or 23 for `3-part-vertical`. Property 1001 has one slice per part, row by
  row from the top, y from the bottom: a 640 × 320 image with caps 20, 30, 18, 24 and a center of
  1 × 1 becomes 43 × 51 with slices (0, 31, 18, 20), (18, 31, 1, 20), (19, 31, 24, 20), (0, 30, 18,
  1), ... A vector file's numbers are multiplied by the raster's scale. Packed images keep their
  layout in the link.
- Luminosity with high contrast (`appearance-pairs`), either order: appearance 3
  `UIAppearanceHighContrastDark` and 5 `UIAppearanceHighContrastLight`, in colors and images.

### Launch image sets (`launch-images`)

Only the set `--launch-image` names adds anything, and nothing in `Assets.car`: an icon PNG per slot of
a targeted device, `<set><suffix>[@Nx][~ipad].png`, and the partial Info.plist's `UILaunchImages`
(version, name, orientation and size in points, for slots with a `minimum-system-version`, newest
first, in the table's order) with `UILaunchImageFile` `<set>` when a slot has none. Other sets add
only their warnings. Slots, by idiom, system version, subtype and orientation:

| Slot | Suffix | Points | Pixels |
|---|---|---|---|
| iPhone 12.0 `2688h` | `-1200-Portrait-2688h`, `-1200-Landscape-2688h` | 414 × 896 | 1242 × 2688 at 3x |
| iPhone 12.0 `1792h` | `-1200-Portrait-1792h`, `-1200-Landscape-1792h` | 414 × 896 | 828 × 1792 at 2x |
| iPhone 11.0 `2436h` | `-1100-Portrait-2436h`, `-1100-Landscape-2436h` | 375 × 812 | 1125 × 2436 at 3x |
| iPhone 8.0 `736h` | `-800-Portrait-736h`, `-800-Landscape-736h` | 414 × 736 | 1242 × 2208 at 3x |
| iPhone 8.0 `667h` | `-800-667h` | 375 × 667 | 750 × 1334 at 2x |
| iPhone 7.0 | `-700` | 320 × 480 | 640 × 960 at 2x |
| iPhone 7.0 `retina4` | `-700-568h` | 320 × 568 | 640 × 1136 at 2x |
| iPad 7.0 | `-700-Portrait`, `-700-Landscape` | 768 × 1024 | 768 × 1024 at 1x, twice that at 2x |
| iPhone, no version | none; `retina4`: `-568h` | | 320 × 480 at 1x, 640 × 960 and 640 × 1136 at 2x |
| iPad, no version | `-Portrait`, `-Landscape` | | 768 × 1024 at 1x, twice at 2x; `to-status-bar` 768 × 1004 and 1024 × 748 |

The named set always warns `Launch images are deprecated in iOS 13.0. Use a launch storyboard or XIB
instead.`, and `An iPhone Retina (4-inch) launch image for iOS 7.0 and later is required.` for an
iPhone target without that slot. The legacy `retina4` slot has a notice. A file of the wrong size or
missing gets a warning like an app icon's, in `[idiom][subtype][scale][orientation][extent][version]`
form, in two passes around those. Entries without a slot and stray files are unassigned children,
two lines. Other platforms' entries are ignored without a word. A named set with nothing to write
is the error `The launch image set named "X" did not have any applicable content.`; a name no set
has, `None of the input catalogs contained a matching launch image set named  "X".`. A named set with
entries without a slot makes actool write a slot's PNG from one of its files, not understood; nomac stops.

### PNG gamma (`png-gamma`)

Without a usable profile and without `sRGB`, one `gAMA` chunk of 4 bytes before the image data
converts the pixels as a profile would: the sRGB primaries (or `cHRM`'s, adapted to D50 with
Bradford's matrix) and the curve x^(1/gamma). It leaves them alone at 1/2.2 ± 0.0001, at 2.2 ± 0.0001
when there is no `cHRM` (219,998 is a common way of writing it wrong) and up to the value 15. `cHRM`
alone changes nothing. Two `gAMA` chunks, a chunk of another length or one after the data count as
none. Icon PNGs keep the file's pixels and the chunk. Converted pixels are equivalent (ADR 0204).

### Loose PNGs (`copypng`)

Swift Build copies a bundle's loose PNGs with Xcode's `copypng` (`COMPRESS_PNG_FILES`,
`STRIP_PNG_TEXT`, both on for iOS). Without options it copies the file as it is; with
`-compress` or `-strip-PNG-text` it writes the PNG actool writes next to `Assets.car` (above:
CgBI for RGB and RGBA, plain PNGs for gray and gray-and-alpha, the same chunks), and
`-strip-PNG-text` leaves out `tEXt`, `iTXt` and `zTXt`. One difference: a plain PNG's zlib
header names the smallest window of at least 256 bytes that holds the filtered rows (252 bytes:
256, header `08 D7`; 273: 512; 2,040: 2,048), the deflate stream itself unchanged. copypng takes
any argument containing an option's name for that option, and ignores other options, printing `WARNING: Ignoring unknown option <option>` on standard output without a line end. `nomac copypng` (64 self-written
PNGs × 4 option sets, and 188 of 188 written of 108 corpus loose PNGs × 2 option sets,
identical); palette PNGs, color profiles, APNG and other chunks stop (B-214).
### Color profiles (`profiles`)

actool stores the colors of a PNG whose `iCCP` profile is not sRGB IEC61966-2.1 converted to
sRGB; PNGs without a profile or with sRGB IEC61966-2.1 keep theirs. RGB, RGBA and palette PNGs
are converted with their RGB profile, gray ones with their gray profile (and stay gray). The
conversion is ColorSync's. Observed on self-written profiles (Display P3, an Adobe RGB-like
profile with a `curv` gamma, sRGB primaries with a 256-entry `curv` table and with a `para`
gamma of 2.2, an sRGB-like v4 profile, which changes nothing, a gray profile of gamma 2.2) on a
million colors each, decoded from an app icon's 1,024-pixel image: decoding by the profile's
curves, its colorants to XYZ (D50), sRGB's inverted colorants, sRGB's curve and rounding to the
nearest give 63 to 92% of the values exactly and the rest within 1 (Display P3 and Adobe RGB:
within 2 for 0.01%). The differences form a fixed function of each input value that oscillates
by a few hundredths of a level, as lookup tables in ColorSync would; nomac does not reproduce
them, and `nomac verify` judges the converted images equivalent (ADR 0204). Translucent pixels
are converted first, then premultiplied as other PNGs.

- RGB and RGBA images with colors well outside sRGB also get a second rendition with display
  gamut 1 in the key, pixel format `RGBW`, color model 4, 8 bytes per pixel (property 1007 the
  width times 8) and deepmap2 format 20: a Display P3 cube of a million colors does (22% beyond
  sRGB's range in linear values), muted Display P3 colors, grays and a profile slightly wider
  than sRGB do not, nor a palette PNG with saturated Display P3 colors. The threshold, from
  single-color Display P3 images: a linear component below −0.0015 or above 1.0078 (−0.0012 and
  1.0073 give none, −0.0017 and 1.0083 do; `profiles` wide case). The pixels are extended sRGB: sRGB's components unclamped, each
  encoded by sRGB's curve mirrored for negative values, premultiplied, as RGBA half floats
  (Display P3 red is 1.0928, −0.2266, −0.1497). These renditions are packed by the same rules
  as the sRGB ones but apart, in `ZZZZPackedAsset-<scale>.<opaque>.<gray>-gamut1` atlases
  (`RGBW`, keyed with display gamut 1, numbered apart from the gamut-0 atlases, `dim1` after
  `dim2` and before the gamut in `KEYFORMAT`, the target before the gamut when symbol sets are
  there too); image sets store them in deepmap2 (mode 1 raw or 3 LZ seen, mode 2 for some; nomac
  writes raw or LZ, whichever is smaller), app icons in the plain payload (`CELM` compression
  4) at 8 bytes per pixel, per idiom as their sRGB rendition (`profiles` p3, wide cases).
- The icon PNGs written from a converted app icon image keep its unconverted pixels and its
  profile: an `iCCP` chunk after `IHDR` with the input's profile name and the profile raw
  deflated (level 9, `Z_FILTERED`).

### Icon Composer icons (`icons`)

An `.icon` input (a folder of `icon.json` and `Assets/`) compiles whether or not `--app-icon`
names it (observed on expo-default's icon and the self-written icons of the `icons` experiment;
nomac writes all of it but the rendered pixels, ADR 0204):

- Facets: `<icon>` (part 220 or 245, below), `<icon>/<group name>` (246) for the visible groups
  in `icon.json`'s order, the name being the group's `name` with `/` written `_`, else `Group`,
  and a name already taken getting ` 2`, ` 3`, … (`Group`, `Group 2`; `Same`, `Same 2`), `<icon>_Assets/<image file without extension>` (181)
  for each layer image used (two layers of one file make one), `<icon>_Assets/Color-<n>` (217),
  `<icon>_Assets/Gradient-<n>`, `system-light` and `system-dark` (247).
- Colors and gradients: `Color-1` is always extended-gray white (space 6, 1, 1); then, in
  creation order and each value once, the icon's light fill, its dark fill, then the layers'
  fills group by group and layer by layer in `icon.json`'s order (light, dark, tinted). A
  gradient's colors come before it; gradients are numbered with the system ones counted.
  Spaces: `srgb` 1, `gray` 2, `display-p3` 3, `extended-srgb` 4, `extended-gray` 6; each
  component is its value rounded to three decimals (`%.3f`: 0.47843 → 0.478, 0.0005 → 0.001,
  0.9995 → 1, 0.0065 → 0.006), then single precision, stored as a double. `automatic` and
  `system-light` are a gradient of gray 1 and 0.925, `system-dark` one of 0.192 and 0.078.
  The gradient payload: `ARGG`, the stop count, 0 for an automatic gradient (one stop) or 1,
  then floats 0, start x, start y, stop x, stop y (default 0.5, 0, 0.5, 1), and per stop its
  location and the color's facet name (length with the NUL, then the name and NUL).
- Specializations (`<property>-specializations`, a list of values with an optional
  `appearance`: `light`, `dark` or `tinted`): a property given directly applies to every
  appearance and its specializations are ignored; otherwise each appearance takes its own
  value, else the one without an appearance, else the default (opacity 1, blend `normal`,
  glass, not hidden, translucency 0.3, shadow neutral 0.5, specular, lighting individual, blur
  0, no position change). `image-name` keeps its direct value. A layer's fill differs: dark and
  tinted fall back to the light value last, and `automatic` defers to the next value.
- The icon's fill: `fill` is the light fill and the dark one is `system-dark`; with
  `fill-specializations`, the `light` one (else the one without an appearance) is the light
  fill and `dark` the dark one (else `system-dark`). `automatic` and `none` are the system fill of their
  appearance; no fill is `Color-1`. The tinted stack uses the light fill; a tinted
  specialization of the icon's fill is ignored.
- Layers: layers and groups hidden in every appearance are left out; a layer hidden in some
  appearances only is kept there with opacity 0 and glass 0; a group hidden in some
  appearances only has opacity 0 in their stack and its layers glass 0. A layer's dark and
  tinted fills default to its light one (the property, or the specialization without an
  appearance, else `light`); `automatic` and `none` mean none. In the dark appearance an SVG
  layer without a fill (`none` in the dark appearance keeps it without) whose every color
  (fills and gradient stops) has a lightness ((max + min) / 2) of 0.85 or more in Display P3
  (white: #D9D9D9 is, #D8D8D8 is not; 0.8499 is not, 0.8501 is) takes the icon's light fill;
  PNG layers never do. `color-space-for-untagged-svg-colors` `display-p3` makes the SVG's
  colors Display P3 values (and its vector rendition's color model 3); `srgb` fails Icon
  export.
- Position: a layer's size is its image's (an SVG's `width` and `height` in px, pt or no unit,
  else its viewBox; a PNG's pixels, whatever its resolution) times the group's and the layer's
  scales, rounded to the nearest with ties to even; its origin is 512 plus the group's
  translation plus the layer's times the group's scale, less half the unrounded size, rounded
  down (y grows downwards).
- Per appearance `UIAppearanceDark` (1), `UIAppearanceLight` (4) and `ISAppearanceTintable` (10):
  an icon stack (part 245, `<icon>.iconstack`, 1,024 × 1,024, scale 100, pixel format `DATA`,
  layout 1019, payload `DWAR` 0 0) and per group a group (part 246, `IconGroup`, 0 × 0, scale
  100, `DATA`, layout 1020, same payload), both with scale 1 in their key. Their list
  properties are a count, 0 and the entries: 1012 per layer 0, x, y, width, height, the blend
  mode (CoreGraphics': normal 0, multiply 1, screen 2, overlay 3, darken 4, lighten 5, soft-light
  8, hard-light 9, plus-darker 26, plus-lighter 27), the opacity and the drawn rendition's key
  ((element, part, identifier) pairs and a zero pair); 1020 per layer a number, a float and a
  paint's facet name; 1021 five words; 1022 three zero floats. The stack's layers are the fill
  (0, 0, '', zeros) and the groups bottom first (1020: lighting `individual` 2 or `combined` 0,
  the blur material; 1021: specular 1 or 0, the translucency's value when enabled else 0 (no
  `translucency`: 0.3), the shadow kind (`none` 0, `layer-color` 2, `neutral` 3, the default),
  its opacity (default 0.5), 0; 1012: the group's opacity). A group's layers are bottom first
  (1020: glass 1 or 0, 0, the layer's fill or ''; 1021 zeros). Then 1004 (0, 1.0), on the
  stack 1005 (20, 0, `public.layeredimage`), and 1006 (1).
- Layer images: an SVG as a vector rendition (above, CSI name `image.svg`, key scale 1); a PNG
  as an image named `image.png`, packed or standalone like an image set's, opaque when the PNG
  has no alpha channel and no `tRNS` whatever its pixels (an RGBA PNG of opaque pixels is not).
  Position, opacity, blend mode, glass, hidden, translucency, shadow, specular, lighting and blur
  are taken per appearance, so each stack and group has its appearance's values.
- The icon rendered at 1,024 pixels for `UIAppearanceAny` (0), `UIAppearanceDark` (1) and
  `ISAppearanceTintable` (10), for idioms 1 and 2 (part 220, `dim2` 1, stored as an app icon's
  1,024-pixel image, always in color, `BGRA`), named
  `<icon>1024x1024_<appearance>_<UUID>-<process number>-<16 hex digits>.png`, beside a part-218
  size table of 1,024 points per idiom. `--target-device` and the deployment target change
  nothing in `Assets.car` but `EXTENDED_METADATA`.
- For the icon `--app-icon` names: `<icon>60x60@2x.png` and `<icon>76x76@2x~ipad.png` drawn from
  the rendered any-appearance image (CgBI with `gAMA`, `sRGB`, `cHRM` and an `eXIf` giving the
  color space and the pixel size), whatever `--target-device`; `CFBundleIcons` lists
  `<icon>60x60`, `CFBundleIcons~ipad` `<icon>60x60` and `<icon>76x76`, and `CFBundleIconName`
  is in the keys of the devices `--target-device` names (both without it).

- Alternate icons: when `--app-icon` or `--alternate-app-icon` names Icon Composer icons, only
  the named ones compile (`--include-all-app-icons` compiles them all; with no icon named, all
  compile). The alternates add no PNGs (nor does `--standalone-icon-behavior` for an icon); the
  primary icon's `CFBundleIcons` and `CFBundleIcons~ipad`, for the targeted devices as
  `CFBundleIconName`, get `CFBundleAlternateIcons`, each alternate's name mapped to its
  `CFBundleIconName`; without `--app-icon` there are no keys (`icons` alternate cases).
- A compiled Icon Composer icon replaces the app icon set of its name, whichever input comes
  first, as primary and as alternate: the set adds nothing and the name is listed once (firefox,
  home-assistant; `same-name-icons`). actool still writes the set's document warnings (B-202).
- Alternate app icon sets (`alternate-app-icons`, 17 cases identical or equivalent): the sets
  `--alternate-app-icon` names, or with `--include-all-app-icons` every set with an image
  besides `--app-icon`'s, give their renditions as a primary set would (single-size sets for
  the targeted devices, multi-size sets for all their own) and no PNG, no check and no warning
  (a multi-size alternate without iPad icons compiles for iPad). Each icon key names the
  primary icon and lists every alternate (`CFBundleIconName` only) when `Assets.car` has app
  icons for its device, otherwise neither. A primary multi-size set for iPad without an 83.5 pt
  2x icon gets actool's warning "A 83.5x83.5@2x app icon is required for iPad apps targeting
  iOS 9.0 and later"; nomac stops on it. Icon Composer icons and app icon sets can be
  alternates together, the primary icon either kind (icecubes): every key lists them all.
- 16-bit PNGs (`profiles` wide case; icecubes' icons): actool dithers their samples to 8 bits
  (one value gives 2s and 3s by position), so nomac reads only those it converts from a color
  profile (their pixels equivalent, ADR 0204), using the samples' high bytes; untagged ones stop
  it (B-209), as do 16-bit images whose pixels are all gray, which get a second, `GA16`
  rendition (gray and alpha half floats, color model 6, deepmap2 format 18).

actool varies two things from run to run (eight runs of expo-default's command line), besides
the appearance-key order: the rendered images' names after the appearance, and the facet
`<icon>`'s part, 220 in four runs and 245 in the other four. Everything else is identical,
including the rendered pixels and the icon PNGs (ADR 0203), though another icon's rendered
any image once differed in 206 pixels by up to 2 between two runs. Icon export (actool's separate
tool) refuses some inputs, which fail the whole compile (`Icon export exited with status 255`):
three-stop gradients, unknown fill names, `{}` fills, some blend modes, `visionOS` squares.

nomac's renderer (`IconRenderer`, ADR 0204) draws the fill over the canvas, then each group's
layers bottom first in their rectangles (SVGs filled with eight sample rows per pixel and exact
horizontal coverage, PNGs resampled), recolored by their paint and in gray for the tinted
appearance, the group's translucency letting the fill through more towards the bottom, a
blurred shadow 12 pixels below, and the group's opacity. An automatic gradient goes from its
color with 30% white at the top to 3% at the bottom. Its pixels differ from IconServices'
(expo-default's icon: a mean absolute difference per channel of 10.4, 7.8 and 10.9 out of 255
for the any, dark and tinted images, 95% of pixels within 34, 39 and 30); `nomac verify` judges
them equivalent (ADR 0204).

### Sticker packs (`stickers`)

Sticker catalogs (firefox's `.xcstickers` and wikipedia's `.xcassets`; `stickers`: 6 cases
identical) compiled with `--include-sticker-content`, `--stickers-icon-role extension`,
`--sticker-pack-identifier-prefix <prefix>` and `--app-icon` naming the stickers icon set:

- The icon set's entries are Messages sizes: iPhone 29 pt at 2x and 3x, 60 × 45 at 2x and 3x,
  iPad 29 pt, 67 × 50 and 74 × 55 at 2x, universal (platform `ios`) 27 × 20 and 32 × 24 at 2x
  and 3x, App Store 1024 × 768 (platform `ios`) and 1024 × 1024 at 1x. `Assets.car` holds only
  the 1024 × 768 image: a part-181 image of the set's name, idiom 6, scale 1, CSI flags 0,
  deepmap2 (it is standalone), and no `APPEARANCEKEYS` when nothing else is in the car.
- The 27 × 20, 32 × 24, 60 × 45, 67 × 50 and 74 × 55 images are written as icon PNGs named
  `<set><size>@<n>x.png`, without `~ipad`; the 29 pt and 1024 × 1024 images are not written.
- Partial Info.plist: `CFBundleIcons` → `CFBundlePrimaryIcon` → `CFBundleIconFiles` the five
  sizes' names in the order 60 × 45, 67 × 50, 74 × 55, 27 × 20, 32 × 24 whatever the set's, and
  no `CFBundleIconName`; `IMStickerPackPath` the pack's folder name;
  `MSMessagesExtensionStoreIconName` the set's name.
- Stickers count only under `--app-icon` (`sticker-options`, 28 cases): without it icon sets and
  packs add nothing, whatever the other options, and a stickers icon set it does not name never
  adds anything, beside any other assets (bluewallet's, rainbow's). Without
  `--include-sticker-content` there is no pack and no `IMStickerPackPath`, as without a pack in the
  catalog. List entries without a folder give the warning `No source image for sticker.`
  and folders the list leaves out add nothing.
- Observed, nomac stops (B-204): without a role, `--app-icon` alone puts the 1024 × 1024 image in
  the car with only `MSMessagesExtensionStoreIconName`, and with `--include-sticker-content` the
  1024 × 768 image and the pack, without PNGs; `--stickers-icon-role host-app` puts the 1024 × 1024
  image in the car, writes `<set>29x29`, and omits the store icon key; several packs give
  `warning: Only one sticker pack is supported per extension. Using Abe.` under the first in
  name order, the only one written; `--app-icon` naming an app icon set with
  `--include-sticker-content` writes the pack and icons named `<set>1024x1024`; PNGs without
  `--compress-pngs` differ. `--include-sticker-content` with a pack and without a prefix makes
  actool crash.
- A name `--app-icon` gives that nothing has: the usual error says `stickers icon set or app icon
  set` with `--stickers-icon-role` and `stickers icon set, app icon set, or icon stack` without.
- `<pack>.stickerpack/` (one output in the report and the dependency info) holds each sticker
  of the pack's `stickers` list, the file its `.sticker` folder names copied as it is under the
  folder's name with the file's extension (wikipedia's `Astronaut animated.sticker` holds
  `Astronaut_2.gif`, written `Astronaut animated.gif`), and a binary `Info.plist` written as
  Foundation writes a re-read property list (`BinaryPropertyList.foundationData`):
  `CFBundleIdentifier` the prefix plus the pack's name with `-` for spaces, `CFBundleName`,
  `CFBundlePackageType` `BUNDL`, `CFBundleShortVersionString` 1.0, `CFBundleVersion` 1,
  `IMStickerPackLayout` from `grid-size` (`small`, `regular`, `large` →
  `MSStickerSizeClassSmall`, `...Regular`, `...Large`), `IMStickers` one dictionary per sticker
  in list order: `IMStickerIdentifier` the written name and, when the sticker has an
  `accessibility-label` (even empty), `IMStickerAccessibilityLabel`.
