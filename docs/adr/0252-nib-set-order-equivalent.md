# ADR 0252: the order of a nib's `NSSet` elements is an equivalent difference

- Status: accepted (the integrator's conditions, 2026-11-02: the order checked run to run, the
  rule limited to `NSSet` and `NSMutableSet`, a deterministic order in nomac, this ADR)
- Date: 2026-11-02

## Context

A view's `<mask>` variations compile to `_UIRelationshipTraitStorageRecord`s whose
`UIAddedObjects` and `UIRemovedObjects` are `NSSet`s of constraints or subviews
(docs/formats/nib.md "Variations"). With two objects or more, ibtool writes them in an order
the document does not give:

- `sc-mask-set-probe-1` to `-8` (`.github/scripts/nib_experiments.py` round 41) are one
  four-constraint mask with 1, 2, 3, 5 and 8 unrelated subviews added before it. The sets come
  out as rotations of the candidates' order, `[11, 12, 13, 14]`, `[15, 12, 13, 14]`,
  `[15, 16, 13, 14]`, `[15, 16, 17, 18]`, `[18, 19, 20, 21]`, so their order moves with unrelated
  objects;
- the view of `sc-mask-include-two` written in a storyboard (`sb-sc-mask-include-two`) removes
  the same two constraints in the other order;
- in the corpus, wikipedia's WelcomeContainerViewController, Places and nextcloud's NCShareHeader
  have sets out of the candidates' order.

This is the iteration order of a hash table keyed by the objects' memory addresses in ibtool's
process, which nomac cannot reproduce. It is stable, though: five runs of ibtool on each of
`sc-mask-set-probe-2`, `sc-mask-set-probe-3`, `sc-mask-include-two` and `sb-sc-mask-include-two`
wrote the same bytes every time (2026-11-02). So it is deterministic, not run-to-run noise like
actool's (ADR 0203), and it still cannot be derived from the document.

An `NSSet` has no order. UIKit's trait storage uses these sets as the objects to add and remove,
so a nib that differs only in that order decodes to the same objects. As with an `.omo`'s
column-name lists (ADR 0230), the difference is in the order of an unordered collection.

## Decision

1. `nomac verify` compares an ibtool output that differs from Xcode's by sorting, in both files,
   the object references (`NS.object.<n>`) of every object archived as `NSSet` or `NSMutableSet`.
   Nested archives in data values are sorted too, as a storyboard's prototype cells. The file is
   *equivalent* when the results are equal, with this ADR as the reason
   (`NomacVerify.NibSetComparison`). Every other byte must be the same, so a reference to the same
   index names the same decoded object; anything else, `NSOrderedSet` and `NSArray` included, is
   reported as before. `.github/scripts/nib_compare.py` applies the same rule and counts such nibs
   apart as *equivalent*.
2. nomac writes a set's objects in a deterministic order: the candidates' order, the view's
   constraints or subviews as written in its nib. That is ibtool's order in every default-only
   mask observed (the experiments, tofu, nextcloud's NCShareUserCell) and in most size-class ones,
   so most nibs stay byte-identical.
3. nomac no longer refuses size-class masks whose records name several objects (B-280).

## Consequences

- A nib with such a set is equivalent, not identical, when ibtool's addresses happen to rotate
  it. The experiments show `sc-mask-set-probe-2`, `-3` and `sb-sc-mask-include-two` equivalent;
  every other experiment stays identical.
- The rule is limited to unordered Foundation sets. An order nomac gets wrong in an ordered
  collection is still a difference.
