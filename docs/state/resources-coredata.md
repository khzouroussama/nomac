# Resources: Core Data models (momc and mapc replacements)

Branch `res/coredata`. Part of the second resources workstream (strings, Core Data, nibs): BACKLOG
B-255–B-258 and B-270–B-279, ADRs 0270–0279. `nomac momc` (`Sources/NomacCoreData`) compiles
`.xcdatamodel` and `.xcdatamodeld` as Xcode 27.0's momc does (docs/formats/coredata.md, ADR 0270).

## Current step

Survey-driven: every Core Data model of the coverage survey's repositories, 365 models in 267
repositories (10 of 277 repositories did not fetch), compared with Xcode 27.0's momc file by file
with `coredata_survey.py`. At main 85c5aab0: 146 same, 207 refused, 11 different. Batch 1: 327, 37, 0.
Batch 2: 352 same, 12 refused (11 binary `elements`, 1 derived attribute), 0 different, and 1 model
momc itself fails on. The binary format is the next item.

## Just finished

- Batch 1, bugs no corpus model showed, each one a model nomac wrote differently from momc:
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
- Batch 2: configurations, fetch requests with predicates and limits (`PredicateSyntax`, observed
  forms only), fetched properties and their hash, every shape of compound index, Boolean defaults
  as `NSString.boolValue`, transient attributes without a type, SwiftData warnings, Objective-C
  categories that refer to other classes.
- Earlier: B-258's generator; B-255 (version hashes through Core Data's public API); `nomac momc`
  (all 84 corpus `.mom` files identical); `nomac mapc` (B-270); the `.omo` mapped (B-256).

## Next actions

`coredata_survey.py compare` lists these, most repositories first:

1. Binary `elements` models: 11 models in 10 repositories, 17 versions, the largest refusal. Each
   `.xcdatamodel` holds `elements` (a keyed archive of `XDPMModel`, as `MappingModel` reads) and
   `layout`, no `contents`; momc compiles them. Entities are `XDPMEntity`, properties `XDPMAttribute`
   and `XDPMRelationship`, fetch requests `XDPMFetchRequest` (`_entity`, `_fetchedProperty`, `_name`,
   `_predicateString`, under `XD_PSK_fetchRequestsArray`). Stereotype keys these models use, to map
   onto `DataModel` or refuse: `XD_PSK_` entityClassName, classMapping, elementID, isAbstract, userInfo,
   versionHashModifier, fetchRequestsArray; `XD_PPSK_` elementID, isIndexed, isOptional, isSpotlightIndexed,
   isStoredInTruthFile, isTransient, userInfo, versionHashModifier; `XD_PAttK_` attributeType,
   allowsExternalBinaryDataStorage, defaultValueAsString, minValueString, maxValueString,
   regularExpressionString, valueTransformerName; `XD_PRK_` deleteRule, destination,
   inverseRelationship, isToMany, maxCount, minCount, ordered; `XDPMCompoundIndexes`,
   `XDPMUniquenessConstraints`; `_modelVersionIdentifier` and `_configurationsByName` on the model.
   An inventory script is `b257/xd2.py` in the scratch below. Compare with `coredata_survey.py compare`.
2. Derived attributes (1 model, LeitnerBox).
3. Fetch the 10 repositories that failed (`survey/fetch_models.py`; GitHub was timing out) and add them
   to the measure; `observe` only runs on models it has not recorded.
4. Mapping models of the survey's repositories (`*.xcmappingmodel` are checked out, not measured).
5. B-271: corpus builds on Linux through the momc and mapc launchers.

Scratch, outside the repository, in `~/nomac-out/wt-scratch/coredata`: `survey/` holds the checked-out
models (`repos/`), momc's outputs (`obs/`), the last comparison (`compare.json`) and `diff.py`,
`omodiff.py`, `rawdiff.py`, which show what differs in one model; `b257/vary.py <script>` compiles
variations of a model with momc and prints what changes in the `.mom` and `.omo`. Models are compared
at those paths, since momc's order of versions depends on them.

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
