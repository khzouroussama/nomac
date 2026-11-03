# Resources: string symbols, intent definitions and the `.omo`

Branch `res/strings`. BACKLOG B-230–B-239 and ADRs 0230–0249, plus B-254 (done here) and B-256.
The strings compiler's history is in `docs/state/resources-nibs.md`, Core Data's in
`docs/state/resources-coredata.md`.

## Current step

Resumed for the RN/Expo sweep (2026-11-02): rocketchat's watch app runs momc with
`--watchos-deployment-target`, which `nomac momc` refused with its usage text. momc and mapc now
take the deployment target of every platform coredata-experiments `platforms` shows equal to iOS;
the rest are B-236. Core Data and strings otherwise stay as below: every observed model nomac
compiles is identical or equivalent (ADR 0230 to 0232, B-235).

## Just finished

- Entity inheritance in the `.omo` (`omo-inh-*`, 25 experiments): members with inherited ones,
  subentity records, family lists, the destination entity column; ADR 0232 (momc's own runs and a
  Simulator run on uncloudnotes, a three-level chain and mixed members). `coredata_compare.py`:
  221 models identical, 0 different; uncloudnotes' final and v4 models compile.
- Fetch request templates in the `.omo` (`omo-fr-several`): records in F, names and a lookup
  table, the S section's template indexes. BubbleTeaFinder compiles; `coredata_compare.py` 193
  models identical, 0 different, only uncloudnotes' two inheritance models refused.
- `.omo` records decoded by experiment (`omo-rel-*`, `omo-fi-*`, `omo-uq-several`, `omo-val-*`):
  ordered relationships (order keys; a to-many without an inverse is a hidden to-one), minimum
  counts, the Deny rule, to-many `maxCount`, fetch indexes (shared with the `.mom`), uniqueness
  constraints, validation bounds and user info. Fixed on the way: Float validation bounds archive
  as doubles in the `.mom`; insecure-transformer warnings come only from the current version.
  `coredata_compare.py`: 188 models identical, 6 refused, 5 files different (lookup split B-256,
  name sharing B-235). wikipedia's Cache, Wikipedia, RemoteNotifications and BowTies now compile.
- ADR 0231: `omo_lookup_experiment.py` on an iOS 27 Simulator; lookups, key-value coding, fetches
  and stores behave the same with nomac's lookup tables for WMFData, mastodon and
  `version-shared-names`; verify compares tables by their keys. `coredata_compare.py`: 191 models
  identical, 0 files different (39 `.omo` and 2 `VersionInfo.plist` equivalent).
- Renaming identifiers (`elementID` on entities, attributes and relationships), which stopped a
  pod's model at planning (B-257): the `.mom` archives them, the `.omo` records them
  (`renaming-*`, `omo-renaming*`: all identical). `nomac check` has a `coredata:` domain that runs
  each model through nomac's momc and reports refusals with their BACKLOG item.
- B-256: `OptimizedModel` writes the `.omo`. Of the 135 observed files 4 are identical, 113
  identical once sorted, 18 refused, none different; `coredata_compare.py` 164 models identical.
  `nomac verify` of moonlight: the coredata check equivalent (was refused). Found on the way
  (`omo-default-class`, `omo-date-defaults`, `omo-coverage`): `NSManagedObject` is class 0 in the
  `.omo` and nil in the `.mom`; Date defaults are floored to whole minutes in both; SQL names are
  interned in an immutable copy's order; lookup tables split on the most distinct position.
- ADR 0230: `omo_equivalence_experiment.py` on an iOS 27 Simulator; stores, migrations and schemas
  are the same with momc's column-name order, reversed or shuffled; the `.omo` is what Core Data loads.
- Intents: `intents_experiments.py` (about 360 self-written definitions and the corpus's and
  holdout's 14, in seven option variants) and `intents_compare.py`: 2,226 of 2,226 Swift outputs
  identical. `compile` is refused (B-232, `INIntentHash`), Objective-C is B-233, verify checks B-234.
- The capture keeps `GeneratedStringSymbols_*.swift`; `capture_reference.py --refill-string-symbols`
  adds them to earlier build captures. `nomac verify` strings checks: gomap 80, netnewswire 13,
  icecubes 130, mastodon 632, nextcloud 697, all identical.
- B-254: `nomac xcstringstool generate-symbols` writes xcstringstool's Swift for manual strings;
  XML keys and strings lose one leading U+FEFF; other languages get a manual string's key when its
  symbol takes arguments. Corpus and holdout catalogs compile identically (77 of 77); the holdout's
  2,269 strings files copy identically.
- B-256 second pass: scratch in `~/nomac-out/res-strings/omo` (`runmodel.py` compiles one model of
  many entities and returns their SQL name orders; `pairs8.json`, `triples8.json`, `sub32.json`;
  solvers `solvem.py`, `solvereh.py`, `zrank.py`; `battery.py` for hash families).

## Next actions

1. B-256: the lookup split rule and the column-name hash, if a new idea appears.
2. B-235: which untagged names momc shares across versions.
3. B-232 (`INIntentHash`), B-233 and B-234 when a project needs them.
4. B-230 if a project needs it; B-231 with probes of language identifier pairs.

## How to reproduce

```sh
# On the Mac (Xcode 27.0), outputs outside the repository
export DEVELOPER_DIR=/Applications/Xcode_27.app/Contents/Developer
python3 .github/scripts/strings_experiments.py ~/nomac-out/res-strings/exp generate-symbols
# Anywhere nomac runs, corpus checkouts in /tmp/nomac-corpus
python3 .github/scripts/strings_compare.py ~/nomac-out/res-strings/exp .build/debug/nomac generate-symbols
```

The random comparison is a scratch tool (`~/nomac-out/wt-scratch/strings-sym/tools/fuzz.py <first
seed> <count>`, then `one.py <failing catalog>` to isolate keys); its cases go into `symbols-*`
catalogs once understood.
