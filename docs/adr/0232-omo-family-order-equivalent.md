# ADR 0232: the order of an `.omo` entity's list of itself and its subentities is an equivalent difference

- Status: accepted
- Date: 2026-11-02

## Context

Each entity record of an `.omo` ends with the indexes of the entity and all its subentities
(docs/formats/coredata.md "Inheritance"). momc writes that list in an order that changes from one
compilation to the next: `omo-inheritance`'s `Base` and uncloudnotes v4's `Attachment` list
`0 1` or `1 0` over three compilations each (coredata-experiments `omo-runs`; "Run to run"). No
order nomac picks can match every momc output, so models with inheritance would be different
however they are written.

## Evidence

- momc itself writes both orders of a two-entity list for one input, so either is an Xcode
  output.
- `.github/scripts/omo_lookup_experiment.py` (Xcode 27.0, iOS 27.0 Simulator, 2026-11-02) on
  uncloudnotes' `UnCloudNotesDataModel` (final), `omo-inh-chain` (three levels) and
  `omo-inh-members` (inherited attributes and a relationship): the app built with momc's `.omo`
  and the same app with nomac's (its families sorted) print the same lookups, key-value coding,
  fetches and predicate counts, on their own stores and on each other's; the controls (ADR 0231)
  differ, so Core Data reads both files.

## Decision

1. nomac writes each family list sorted by entity index.
2. `nomac verify` and `coredata_compare.py` sort that list on both sides before comparing; a file
   that matches then is *equivalent*.

## Consequences

- Models with entity inheritance compile on Linux with an equivalent `.omo` (every observed one:
  uncloudnotes' final and v4 models and the `omo-inh-*` experiments).
- For lists of three entities or more, which orders momc produces is not observed; the Simulator
  run covers a three-level hierarchy.
