# ADR 0009: nomac generates synchronized-folder GUIDs and comparisons treat them as opaque

- Status: accepted (extends ADR 0004 and ADR 0006)
- Date: 2026-10-21

## Context

Xcode gives every item of a synchronized folder (`PBXFileSystemSynchronizedRootGroup`), and every
build file for such an item, a GUID that is the base64 encoding of 32 bytes. Observations:

- `pif-stability` (netnewswire, icecubes): the GUIDs are identical across dumps with fresh or
  warm DerivedData, and unchanged when the checkout moves to another path.
- `pif-experiments`: an item's GUID changes with the project name, the folder's object ID and
  the item's path in the folder. It does not change with the folder's own path, the file's
  contents, or the target's ID or name. Build-file GUIDs differ per target.
- SHA-256, SHA3-256, BLAKE2, double SHA-256 and HMAC-SHA-256 over the plausible inputs (the
  folder GUID in text and binary form, the project GUID, the object ID, the item path with and
  without prefixes, 20 separators, UTF-8 and UTF-16) do not produce them.

The derivation is internal to Xcode and is not documented. The legal line forbids learning it
by disassembling Xcode. Swift Build uses these GUIDs only as identities: they name group-tree
items and build files inside the PIF and do not appear in build products.

## Decision

- nomac generates the GUIDs from the same inputs: an item's GUID is the base64 SHA-256 of the
  folder's GUID, a NUL and the item's path in the folder (`/Localized/<path>` for a variant
  group). A build file's GUID is the base64 SHA-256 of the build phase's GUID, a NUL and the
  item's GUID. Like Xcode's, they are stable, independent of the checkout path, and distinct
  per target.
- `nomac verify` replaces every JSON string that is the base64 encoding of 32 bytes with
  `<SYNCHRONIZED-n>`, numbered in order of first appearance, in both PIFs before comparing
  them. A member's file reference first appears in the group tree, so two build phases that
  list the same members in a different order still differ. This is the only rewrite added
  to the list of ADR 0004 and ADR 0006.

## Consequences

- PIF comparisons check everything about synchronized folders except the GUID bytes: the
  group tree, file types, variant groups, membership, build-file attributes and order.
- If Xcode's derivation is ever documented, or shown by observation alone, nomac switches to
  it and the rewrite is removed.
- The order of members from different folders in one build phase is not covered by this ADR.
  It is compared as is and remains an open question (BACKLOG B-007).

## Amendment (2026-10-22): GUIDs Xcode draws at random

A synchronized variant group with neither a development-region nor a `Base` variant, and each
of its build files, gets a 64-digit hex GUID (the project GUID and 32 more digits) instead of a
base64 one, and these change from one dump of a project to the next: every `hexguid-*` project
of `pif-experiments` round 7, dumped twice, gave two different GUIDs, while the base64 GUIDs of
the same dumps were identical (firefox's `InfoPlist.strings` in `ActionExtension`, whose
development region is `en-US`). No implementation can reproduce them. nomac gives such a group
its base64 GUID, and `nomac verify` replaces Xcode's random GUIDs with base64 stand-ins before
numbering synchronized GUIDs: a variant group whose GUID is not base64 while its children's are,
and the build files that name it. The variant group, its children and its build files are still
compared, and an ordinary variant group's GUID is compared as before.

## Amendment (2026-10-22): build files of lifted variant children

An ordinary variant group's child that is not directly in a `.lproj` folder leaves the group in
Xcode's PIF, and each build file that names the group stands for that child first with a build
file of its own, whose GUID (the project GUID and 32 digits) Xcode also draws at random: two
dumps of one project gave two GUIDs (envelope-experiments `variant-groups`, docs/formats/pif.md
"Group tree"). Such build files look like any other in the PIF, so the generator, which knows
which children it lifts, gives `nomac verify` their file references
(`PIFGenerator.randomBuildFileReferences`), and the build files that name them get the same
stand-ins as above, on both sides. The child, its place in the group tree and the build file's
other keys are still compared.
