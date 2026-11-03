# ADR 0200: nomac writes `Assets.car` itself, and comparisons order actool's appearance keys

- Status: accepted (extends ADR 0004)
- Date: 2026-10-21

## Context

actool compiles asset catalogs into `Assets.car`, a BOM store of CoreUI tables
(docs/formats/asset-catalog.md). There is no documentation of the format from Apple and no
open-source writer that matches actool byte for byte; the legal line rules out learning it from
actool, CoreUI or CoreThemeDefinition themselves. What can be observed is actool's output for
catalogs we write (`.github/scripts/assets_experiments.py`).

The experiments show that actool is deterministic except in one place: with renditions for
more than one appearance, the order in which it creates the `APPEARANCEKEYS` name and value
blocks changes from one run to the next (`appearance-order`: six runs, five orders). The
blocks differ in length, so every later block moves and most of the file's bytes change,
although the tables hold the same data.

Some values in the file name the Mac actool ran on rather than the catalog: the CoreUI version
in `CARHEADER`, the Xcode version and build, and the authoring-tool string in
`EXTENDED_METADATA` (CoreThemeDefinition, ImageIO, AppleJPEG and CMPhoto versions, and
`IR-120(hw)`).

## Decision

- nomac's `NomacAssets` module writes the BOM container and the CAR tables in Swift, from the
  observed layout: block numbering in actool's creation order, the 16-byte block alignment,
  index capacity, tree leaves with their key copies, name identifiers and their collision
  rule, rendition and bitmap-key creation orders. No third-party library is used.
- nomac creates the appearance-key blocks in name order. A comparison of `Assets.car` first
  rewrites actool's file with its appearance-key blocks in name order (renumbering only those
  blocks and the `APPEARANCEKEYS` leaf, then laying the store out again with the documented
  layout, which reproduces every unmodified actool file exactly); after that the files must be
  byte-identical. No other difference is accepted.
- The Mac-specific strings are those of the reference setup (Xcode 27.0, 27A266a, on macOS
  27.0.1, Apple silicon) and live in one place, the Xcode profile (`XcodeProfile.assetCatalog`,
  ADR 0012), which `ActoolVersions` reads. When the reference Xcode or Mac changes, they are
  observed again.
- Anything actool accepts that nomac has not observed yet is an error naming the BACKLOG
  item, never a guess.

## Consequences

- Catalogs whose renditions use one appearance (most of them) are compared byte for byte
  without any rewriting.
- The rewriting needs a BOM reader in the comparison; the experiment script has one, and
  `nomac verify` has one since ADR 0203 (`AssetCatalogComparison`).
- The authoring-tool string may differ on other Macs (for example Intel or virtual machines,
  where `(hw)` may read otherwise); a reference captured elsewhere is checked against it before
  being trusted.
