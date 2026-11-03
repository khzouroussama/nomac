# ADR 0203: actool's run-to-run variations in catalogs with an Icon Composer icon

- Status: accepted (extends ADR 0200)
- Date: 2026-10-30

## Context

Xcode 27.0's `actool` does not write the same `Assets.car` twice for a catalog compiled with an
Icon Composer icon (`.icon`, B-180). Eight runs of expo-default's `CompileAssetCatalogVariant`
command line (`Images.xcassets` and `expo.icon`, `--app-icon expo`) gave files of the same
6,025,128 bytes that differ in three ways, and in nothing else:

1. The order of the appearance-key blocks, as in every catalog with several appearances (ADR 0200).
2. The names of the icon's rendered images, the part-220 renditions in each appearance (`Any`,
   `Dark`, `Tintable`) and idiom: `expo1024x1024_UIAppearanceAny_<UUID>-<process>-<time>.png`,
   an uppercase UUID, actool's process number in decimal and 16 uppercase hexadecimal digits that
   grow from run to run, in the CSI's 128-byte name field.
3. The part of the icon's facet: 220 (the rendered images) in four runs, 245 (the icon stack) in
   the other four.

With the appearance-key blocks in name order, the end of those names masked and the facet's
part written as 220, the eight files are byte-identical. The rendered pixels can vary too: in
two runs of the `icons` experiment's composite icon, 206 pixels of the any-appearance image
differed by up to 2 (the dark and tinted images did not); ADR 0204 accepts rendered pixels
anyway. The icon PNGs (`expo60x60@2x.png`,
`expo76x76@2x~ipad.png`), the partial Info.plist and the report are identical in every run.

## Decision

- nomac writes the appearance-key blocks in name order (ADR 0200), the facet of an Icon Composer
  icon with part 220, and the end of each rendered image's name from values of its own in
  actool's form (a UUID, a number, 16 hexadecimal digits), derived from its inputs so that
  nomac's output does not change from run to run.
- `nomac verify` (`AssetCatalogComparison`, in `NomacVerify`) compares a `.car` that differs
  from Xcode's by reading both as BOM stores, checking that each is laid out as
  docs/formats/asset-catalog.md describes, and comparing them block by block after, on both
  sides: the appearance-key blocks put in name order; in the facets of names that have an icon
  stack (a part-245 rendition), part 245 written as 220; in those names' part-220 renditions
  whose name ends in `_<UUID>-<digits>-<16 hexadecimal digits>.png`, that end masked. A file
  equal after these steps is *equivalent*, with each step that was needed named. Any other
  difference is a difference, unless ADR 0204 accepts it.

## Consequences

- expo-default's `Assets.car` can be judged by `nomac verify`, against one Xcode run, as
  equivalent when nomac's bytes are those of Xcode's but for these variations and the rendered
  pixels of ADR 0204.
- The masking touches only the names of renditions that belong to an Icon Composer icon and end
  in that pattern; a name of another rendition, or one that differs elsewhere, still differs.
- This replaces B-207's plan: the comparison is in `NomacVerify`, used by the tool checks and the
  build product checks alike.
