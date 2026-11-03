# Vendored: swift-foundation's predicate macro, as TipKit's `#Rule` uses it

`PredicateMacro.swift` is a copy of open-source code from swift-foundation
(https://github.com/swiftlang/swift-foundation), licensed under the Apache License v2.0
(`LICENSE.md` in this directory, with swift-foundation's `NOTICE.txt`). It keeps its original
header.

## Origin

Tag `swift-6.3-RELEASE` (commit `60bd7a1d8a730ebdeab2cb037b0519ef3b010ed3`),
`Sources/FoundationMacros/PredicateMacro.swift`: the last release whose builder calls are written
without a module selector (`PredicateExpressions.build_Equal`, where 6.4's write
`PredicateExpressions.Foundation::build_Equal`), as TipKit 27.0's `#Rule` writes them; its
messages are those `#Rule` gives inside a rule ("The uppercased() function is not supported in
this predicate"). swift-6.2-RELEASE's file is the same.

## Changes

TipKit's `#Rule` translates `donatedWithin` as a known function whose argument is passed as
written (`PredicateExpressions.build_donatedWithin(<donations>, .week)`, the
`tipkit-rule-forms` experiment of `.github/scripts/macro_experiments.py`), so the copy adds
`donatedWithin` to the known functions and does not visit its argument. Nothing else changes.
