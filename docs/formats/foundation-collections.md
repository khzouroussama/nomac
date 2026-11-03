# The order of Foundation's dictionaries in Xcode's archives

Keyed archives (`.mom`, docs/formats/coredata.md) and NIB archives write dictionaries and key
tables in the order of Foundation's hash tables on a Mac. Observed with Xcode 27.0 (27A266a) on
`.github/scripts/coredata_experiments.py` (`entities-*`, `attributes-*`, `hash-7`, `hash-23`,
`threshold-41-*`, `threshold-71-*`) and the 34 corpus models: the rules below give the order of
all 174 entity dictionaries and 548 property dictionaries of the 174 observed `.mom` files
(`.github/scripts/coredata_dictionaries.py` checks them), and the key tables of every observed
nib (`nib_experiments.py`).

## Placement

A table has one of the bucket counts 3, 7, 13, 23, 41, 71 and 127 (observed; Core Foundation's
public size list continues 191, 251, 383, 631, 1087, ...).
A string key goes to bucket `hash mod count`, where `hash` is `NSString`'s hash (`NomacCore`'s
`FoundationStringHash`, docs/formats/pif.md), and to the next free bucket after it (wrapping to 0)
when that one is taken. Iteration is in bucket order.

## Growth

A mutable dictionary starts empty and, before an insertion that would exceed what its table holds,
moves to the next bucket count, re-inserting its keys in their old bucket order. A table holds:

| Buckets | 3 | 7 | 13 | 23 | 41 | 71 | 127 | 191 | 251 |
|---|---|---|---|---|---|---|---|---|---|
| Keys held | 3 | 7 | 12 | 20 | 33 | 53 | 86 | 119 | 156 |

That is Core Foundation's capacity for the bucket count (3, 6, 11, 19, 32, 52, 85, 118, 155) plus
one, at most the bucket count. The 13 to 71 rows are each pinned by a `.mom` threshold experiment
whose names order differently on either side of the limit (`threshold-*`), the 41 to 251 rows by
nib key-table ladders one key at a time (nib-experiments `ladder-*`: 33 and 34, 53 and 54, 86 and
87, 119 and 120 keys) and the corpus's nibs of 156 and 158 keys. Past 156 keys the table has 383
buckets, observed up to 199 keys (the corpus's nib key tables; tofu's 180-key view nib is
identical); what 383 buckets hold, and larger tables, are not observed, and nomac refuses tables
of more than 199 keys (BACKLOG B-259).

A nib's `UINibEncoderEmptyKey` takes a bucket without counting toward what its table holds until
the archive is finished (docs/formats/nib.md "Encoding"); so the table also grows before an
insertion that would give it more keys than buckets, and once more, if needed, when that key is
counted.

## Immutable copies

A copy takes the bucket count whose Core Foundation capacity (3, 6, 11, 19, 32, 52, 85) fits its keys;
when that is the source's count the copy keeps the source's layout, otherwise its keys are inserted
in the source's iteration order. Twelve keys thus fill 13 buckets, then are copied into 23.

## What uses which

- `.mom` property dictionaries: a copy of a mutable dictionary built in the order of the
  entity's `attribute`, `relationship` and `fetchedProperty` elements in the model file
  (548 of 548).
- `.mom` entities dictionaries: the same twice: a copy of a mutable dictionary built in the
  iteration order of a copy of a mutable dictionary built in file order (174 of 174; one copy
  explains only 34 of the 64 corpus ones).
- NIB key tables: a mutable dictionary, keys inserted when first encoded, `UINibEncoderEmptyKey`
  at its first use but uncounted until the archive is finished, not copied (every observed xib and
  storyboard nib, 16 to 199 keys: docs/formats/nib.md "Encoding").
- Info.plists an app-store-connect export writes again: each dictionary created with its keys
  in Swift's order (20 of 20, docs/formats/property-lists.md "Dictionary key order by tool").
- The per-object dictionaries of a keyed archive: a mutable dictionary filled in encoding order,
  `$class` last, then copied (196 of 196 `NSKeyedArchiver` archives of self-written classes with 1
  to 49 keys, and every `.mom` nomac writes, docs/formats/coredata.md "Keyed archives"). The
  top-level dictionary's keys are always `$version`, `$archiver`, `$top`, `$objects`.
- `VersionInfo.plist`: mutable dictionaries of version names filled in compilation order, itself
  the order of a mutable table of the versions' paths; each version's entities put twice in a
  dictionary created with them, from the model's order (docs/formats/coredata.md
  "`VersionInfo.plist`").
