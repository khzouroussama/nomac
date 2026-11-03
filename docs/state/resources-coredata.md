# Resources: Core Data models (momc and mapc replacements)

Branch `res/coredata`. Part of the second resources workstream (strings, Core Data, nibs): BACKLOG
B-255–B-258 and B-270–B-279, ADRs 0270–0279. `nomac momc` (`Sources/NomacCoreData`) compiles
`.xcdatamodel` and `.xcdatamodeld` as Xcode 27.0's momc does (docs/formats/coredata.md, ADR 0270).

## Current step

B-258 done for every observed model: `nomac momc --action generate` writes momc's Swift and
Objective-C classes. Next is B-271 (corpus builds on Linux through the momc and mapc launchers). B-256 (the
`.omo`) is parked by the integrator after a bounded pass. The format is mostly mapped, but the
order of each entity's SQL column names comes from an unidentified hash, so `nomac momc` still
refuses models with a current version: 7 of `nomac verify`'s 11 coredata checks. The other 3
failing checks (mapping models) compile identically with `nomac mapc`.

## Just finished

- B-258: `CodeGenerator` writes Swift and Objective-C classes. 133 generated models are identical
  (`coredata_compare.py`, author line normalized): moonlight (Objective-C), HitList, WMFData, 36
  `objc-*` experiments, `relationships-several` and `relationships-order`. 4 are refused:
  `version-strings` (case collisions), the two versioned experiments without a current version, and
  `configuration` (B-257).
- Found on the way: momc compiles each entity's attributes by name, then its relationships by
  name, and archives entities by name, whatever the file's order. Names compare as
  `localizedStandardCompare` (`sort-order`). Warnings follow the file's entity order. Before this,
  only Xcode-written (sorted) files had been observed, so nothing changed for the corpus.
- Earlier: B-255 (version hashes through Core Data's public API); `nomac momc` (all 84 corpus
  `.mom` files identical, 146 of 146 compiled models with their diagnostics, 168 dry runs); `nomac
  mapc` (B-270: every corpus mapping model identical); the `.omo` mapped (docs/formats/coredata.md
  "`.omo`"), its column-name hash ruled out against 20 families (B-256).

## Next actions

1. B-271: corpus builds on Linux whose models compile through the momc and mapc launchers
   (uncloudnotes' chapters without a current version first; `nomac verify --build`).
2. A `coredata:` domain for `nomac check` (ADR 0011).
3. B-256 when resumed: experiments that tell hash families apart, then subentity records, fetch
   indexes, uniqueness and validation (the scratch writer and notes are in
   `~/nomac-out/wt-scratch/coredata/omo`).
4. B-258 leftovers only if a project needs them (BACKLOG lists the refused cases).

## How to reproduce

```sh
# On the Mac (Xcode 27.0): observations of self-written models and corpus models (outside the repo)
export DEVELOPER_DIR=/Applications/Xcode_27.app/Contents/Developer
python3 .github/scripts/coredata_experiments.py ~/nomac-out/wt-scratch/coredata/obs
python3 .github/scripts/coredata_experiments.py ~/nomac-out/wt-scratch/coredata/mapc mapping-corpus
# Anywhere nomac runs, at the same paths (corpus checkouts in /tmp/nomac-corpus)
python3 .github/scripts/coredata_compare.py ~/nomac-out/wt-scratch/coredata/obs .build/debug/nomac
python3 .github/scripts/coredata_compare.py ~/nomac-out/wt-scratch/coredata/mapc .build/debug/nomac
python3 .github/scripts/coredata_dictionaries.py ~/nomac-out/wt-scratch/coredata/obs
```

One experiment by name: `coredata_experiments.py <obs dir> objc-ordered relationships-order`, then
`coredata_experiments.py <obs dir> dry-runs` to record the dry runs of new models. The compare
script prints what differs; `~/nomac-out/wt-scratch/coredata/gendiff.py <experiment> <file>`
diffs one generated file against momc's.
