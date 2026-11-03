# ADR 0230: the order of an `.omo`'s SQL column-name lists is an equivalent difference

- Status: accepted (the owner's condition, 2026-10-31: proof on the iOS Simulator first)
- Date: 2026-11-02

## Context

momc writes an `.omo` (an optimized model) beside the `.mom` of a `.momd`'s current version. Its
format is mapped (docs/formats/coredata.md "`.omo`"), but each SQL entity's list of column names
is written in the iteration order of a hash table nobody has identified (BACKLOG B-256: two
passes, no known hash, no simple insertion order). So `nomac momc` refuses every model with a
current version, which keeps the corpus's Core Data checks at 4 of 11 and the Linux builds of
uncloudnotes, wikipedia, mastodon and moonlight from finishing (B-271).

The owner approved writing that list in another order only if a Simulator run showed that (a) a
store an Xcode-built app created opens and reads and writes with the other order, (b) the
reverse, and (c) a lightweight migration between two versions works both ways.

## Evidence

`.github/scripts/omo_equivalence_experiment.py` (Xcode 27.0, iOS 27.0 Simulator, 2026-11-02)
builds a self-written app with xcodebuild, with one model version and with two (v2 adds an
attribute with a default and an entity, so v1 to v2 is a lightweight migration), then copies the
built apps with their current `.omo` changed. In the reordered copies only the column-name lists
change (12 and 18 bytes, the same length): reversed, or shuffled. Every app opens one SQLite
store, inserts an `Item`, its `Note` and a `Tag`, and prints every object it reads:

- (a) a store from the Xcode-built app: the reordered app reads it, writes into it, and the
  Xcode-built app reads both objects back with every value and relationship;
- (b) the same starting from the reordered app;
- (c) a v1 store from the Xcode-built v1 app migrated by the reordered v2 app, and a v1 store
  from the reordered v1 app migrated by the Xcode-built v2 app: the old object gets the new
  attribute's default, the new objects their values, and the other app reads them all;
- the shuffled order behaves the same, and the stores the Xcode-built, reversed and shuffled
  apps create have the same SQLite schema.

Controls show the `.omo` is what Core Data loads: with one attribute renamed inside the `.omo`
(`label` to `lxbel`), the app stops on `setValue:forUndefinedKey:` for `label`; a corrupted
`.omo`, or none, falls back to the `.mom` without a message.

## Decision

1. Each SQL entity's column-name list is the one part of an `.omo` nomac may write in an order of
   its own; every other byte must be momc's. Until B-256 finds the hash, nomac's `.omo` writer
   writes these lists sorted.
2. `nomac verify` is to compare an `.omo`'s column-name lists as sets and the rest of the file
   byte for byte, and to report such a file *equivalent*, with this ADR as the reason.
3. Both land with the Swift `.omo` writer (B-256), which must reproduce the rest of the file
   from observations first; a model using records not decoded yet (subentities, fetch indexes,
   uniqueness, validation, renaming identifiers, fetch request templates) stays refused.

## Consequences

- The hash is no longer a blocker for models whose other records are decoded;
  the hash stays open, so a model's `.omo` is equivalent, not identical, unless its lists happen
  to be sorted.
- The evidence covers attributes, to-one and to-many relationships, a lightweight migration and
  the reading paths of `NSPersistentContainer`; entity inheritance and the undecoded records
  are outside it, which is why they stay refused.
