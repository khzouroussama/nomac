# ADR 0260: ibtool's run-to-run order of outlet collections of several sources is equivalent

- Status: accepted (the maintainers' decision, 2026-11-03: where ibtool's own output order changes
  from run to run, any of the observed orders counts as equivalent, as in ADR 0252)
- Date: 2026-11-03

## Context

A nib lists its outlet collections first in `UINibConnectionsKey`, one
`UIRuntimeOutletCollectionConnection` per collection, its destinations an `NSMutableArray`
numbered where the connection comes (docs/formats/nib.md "Connections"). Collections of one
name follow the outlets' rule, and collections of several names from one source keep the order
of their names' first connections in the document (`oc-names*`, five runs alike).

When File's Owner and a view both have collections, ibtool's order is not a property of the
document: running Xcode 27.0's ibtool four times on each of the same documents
(`.github/scripts/nib_experiments.py` round 95, 2026-11-03) wrote

- `oc-mix-a` (File's Owner's zeta and alpha, the root view's items) in three orders in three runs:
  items, zeta, alpha; zeta, alpha, items; alpha, items, zeta;
- `oc-mix-h` (File's Owner's pa to pd, the view's zz and aa) in three orders in four runs, aa
  sometimes first, zz sometimes among File's Owner's;
- `oc-mix-k` in two orders in three runs, File's Owner's own collections out of document order
  in one.

So the order is not deterministic, unlike the sets of ADR 0252, and no rule derived from the
document reproduces it. The corpus's wikipedia DescriptionHelpViewController,
EditLinkViewController and EditSaveViewController have such collections. Each collection sets a
different property of its source, so the order in which UIKit connects them does not change the
objects a nib decodes to.

Attaching gesture recognizers shows the same: the holdout's vlc VideoPlayerControls, whose Play button attaches a tap and a long
press, came out in three orders in eight runs of Xcode 27.0's ibtool, with the sources in another order and that button's two destinations
swapped (2026-11-07). In small documents the sources go by the first class among what they attach (`gesture-kinds-*`), the order nomac writes.

## Decision

1. `nomac verify` compares an ibtool output that differs from Xcode's, after the sets of ADR
   0252, by a canonical form: the archive's objects walked from the root and numbered where the
   walk first reaches them, the root's outlet collection connections sorted by label, byte by
   byte, then by their sources' place in the walk, and each one's destinations by class (`NomacVerify.NibConnectionComparison`). The
   file is *equivalent* when both forms are equal, with this ADR as the reason; any other
   difference, of a value, a class, a reference or another array's order, is reported as before.
   `.github/scripts/nib_compare.py` applies the same rule.
2. nomac writes collections of several names from several sources in a fixed order: by name, byte
   by byte, those of one name as the outlets' rule orders them. It is one of the orders ibtool
   wrote: `oc-mix-a` and `oc-mix-h` are byte for byte the outputs of one of their runs.
3. nomac no longer refuses outlet collections of several names from several sources (B-291).

## Consequences

- Nibs with such collections are equivalent, not identical, when the reference run happened to
  write another order. Round 95's experiments are identical or equivalent, none different.
- The rule is limited to the leading outlet collection connections of a nib's connections; the
  order of outlets, actions, and every other array is still compared byte for byte.
