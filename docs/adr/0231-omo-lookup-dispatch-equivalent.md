# ADR 0231: the byte positions an `.omo`'s lookup tables dispatch on are an equivalent difference

- Status: accepted (the owner's condition, 2026-11-02: proof on the iOS Simulator, as ADR 0230)
- Date: 2026-11-02

## Context

An `.omo`'s lookup tables (docs/formats/coredata.md "`.omo`", K) find a name's slot: the first
node dispatches on the key's length, each later node on one byte position, which the node
records. nomac picks the first position with the most distinct bytes; momc picks that position
for 152 of 159 observed groups, and another one, of fewer distinct bytes, for the other 7
(wikipedia's WMFData, mastodon, coredata-experiments `version-shared-names`). No rule tried
explains them (BACKLOG B-256). Since nomac writes those models' `.omo`, they would go from refused
to different.

## Evidence

`.github/scripts/omo_lookup_experiment.py` (Xcode 27.0, iOS 27.0 Simulator, 2026-11-02) builds a
generic app with xcodebuild for each of the three models (copied without `codeGenerationType`),
then installs it with momc's `.omo` (X), with the one `nomac momc` writes for the same model (N;
its `.mom` files identical to momc's), and two controls. The app looks up every entity and
property by name, and four near names per character, through Core Data's own `entitiesByName`,
`propertiesByName`, `attributesByName` and `relationshipsByName` (`objectForKey:`, not bridged to
Swift dictionaries); inserts an object of each entity through key-value coding into a SQLite
store; fetches every entity; and counts a predicate's matches on each string attribute.

- WMFData (14 dispatch nodes, 59 entities and properties, 9 entities saved), mastodon (68, 151, 6)
  and `version-shared-names` (6, 48, 24): X and N print the same, each on its own store and each
  on a store the other wrote.
- Control K, momc's `.omo` with every dispatch node moved to another position: WMFData's lookups
  answer differently; mastodon's and `version-shared-names`'s stores fail to open (Core Data
  throws while migrating and while creating indexes). The tables are what Core Data looks names
  up in.
- Control NR, nomac's `.omo` with its first entity's name changed: 90, 86 and 110 lines change.
  Core Data loads nomac's file, not the `.mom` it falls back to on a corrupted `.omo` (ADR 0230).

## Decision

1. A lookup table may dispatch on positions of nomac's choosing, provided every key leads to its
   own slot; the keys and their slots must be momc's.
2. `nomac verify` and `coredata_compare.py` compare an `.omo` with its column-name lists sorted
   (ADR 0230), its section offsets cleared and each lookup table reduced to its keys, after
   checking that every key reaches its slot in both files; such a file is *equivalent*.

## Consequences

- WMFData's and mastodon's `.omo`, and any whose table momc splits otherwise, are equivalent, not
  different; the rule momc follows stays open (B-256), so these files are not identical.
- The evidence covers name lookups, key-value coding, fetches, predicates and stores written by
  either file; the check of every key's path is what keeps a table nomac gets wrong from passing.
