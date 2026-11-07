# Resources: Core Data models (momc and mapc replacements)

Branch `res/coredata`. Part of the second resources workstream (strings, Core Data, nibs): BACKLOG
B-255–B-258 and B-270–B-279, ADRs 0270–0279. `nomac momc` (`Sources/NomacCoreData`) compiles
`.xcdatamodel` and `.xcdatamodeld` as Xcode 27.0's momc does (docs/formats/coredata.md, ADR 0270).

## Current step

Survey-driven: every Core Data model of the coverage survey's repositories, 365 models in 267
repositories (10 of 277 repositories did not fetch), compared with Xcode 27.0's momc file by file
with `coredata_survey.py`. At main 85c5aab0: 146 same, 207 refused, 11 different. Now: 327 same, 37
refused, 0 different. Next are the refusals, most common first (next actions).

## Just finished

- Bugs no corpus model showed, each one a model nomac wrote differently from momc:
  - subentity dictionaries: nomac linked them in Swift `Dictionary` order, which also varied from
    run to run; the rule is in docs/formats/foundation-collections.md (302 of 302);
  - the order of versions at 7, 12 and 20 versions (a copied table);
  - warnings printed once across versions, a rule wrongly inferred from mastodon;
  - `NSDecimalNumber` and `T.Class` strings are new for each attribute and entity;
  - `.omo` entity numbers are depth first, its column dictionary fills from the root down (766 of
    766), to-ones of one name in a family get `_Z<NAME>1`, its subentity lists are by name, and
    a subentity's member list starts with aligned zeros;
  - a relationship that is its own inverse hashes as one without, and an `inverseName` that names
    no relationship counts as none;
  - `minimumToolsVersion="Automatic"` acts as an old Xcode for files last saved by builds 2 to
    11116, and `syncable` marks everything without the attribute up to Xcode 10.0.
- Features: see B-257 "Done"; in the `.omo` too (docs/formats/coredata.md).
- Code generation: no `sourceLanguage`, the only version without a current one, `.Name` classes,
  transformables of a module, the input's letters in typealiases (B-258).
- Earlier: B-258's generator; B-255 (version hashes through Core Data's public API); `nomac momc`
  (all 84 corpus `.mom` files identical); `nomac mapc` (B-270); the `.omo` mapped (B-256).

## Next actions

1. Refusals of `coredata_survey.py compare`, most repositories first: binary `elements` models (the
   same `XDPMModel` archive `MappingModel` reads, 10 models), configurations (notes below), compound
   indexes under old tools, fetched properties, fetch request predicates and limits, the rest.
2. Fetch the 10 repositories that failed and add them to the measure.
3. Mapping models of the survey's repositories (`*.xcmappingmodel` are checked out, not measured).
4. B-271: corpus builds on Linux through the momc and mapc launchers; a run of `nomac verify --build`.

Configurations, observed so far: `NSConfigurations` is a mutable dictionary of names to `NSSet`s of
entities, whose order is a Foundation table of the entities' names (9 of 9 for one model). In the
`.omo`, S lists each configuration and `PF_DEFAULT_CONFIGURATION_NAME` in the order of a table of
their names, sorted before inserting, each with its C index, five zero words, its count of members
and their indexes as u64s.

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
# The survey: its repositories' models sparse-checked out under one directory, at the survey's commits
python3 .github/scripts/coredata_survey.py features ~/nomac-out/wt-scratch/coredata/survey/repos
python3 .github/scripts/coredata_survey.py observe ~/nomac-out/wt-scratch/coredata/survey/repos ~/nomac-out/wt-scratch/coredata/survey/obs
python3 .github/scripts/coredata_survey.py compare ~/nomac-out/wt-scratch/coredata/survey/repos ~/nomac-out/wt-scratch/coredata/survey/obs .build/debug/nomac
```

One experiment by name: `coredata_experiments.py <obs dir> objc-ordered relationships-order`, then
`coredata_experiments.py <obs dir> dry-runs` to record the dry runs of new models. The compare
script prints what differs; `~/nomac-out/wt-scratch/coredata/gendiff.py <experiment> <file>`
diffs one generated file against momc's.
