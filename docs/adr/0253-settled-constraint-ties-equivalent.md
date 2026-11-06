# ADR 0253: the order of a settled constraint tie is an equivalent difference

- Status: accepted (the integrator's decision, 2026-11-03: required constraints the document's
  frames satisfy only; anything else stays refused)
- Date: 2026-11-03

## Context

ibtool sorts a view's constraints into its `UIViewAutolayoutConstraints` (docs/formats/nib.md
"Constraints"). When one item is constrained by the same attributes, relation, multiplier and
priority to several views, the sort key ties them, and their order is ibtool's own. That shape is
the largest constraint refusal across the corpus, the holdout and the React Native and Expo sweep:
62 of 1,071 documents (`~/nomac-out/scripts/nib_refusals.py`, 2026-11-03), 32 of them a safe area
constrained to the same edge of 2 to 6 subviews, 27 a subview constrained to two siblings.

The experiments did not find the order:

- rounds 48 and 49 (`tie-probe-*`, `safe-tie-*`, `sub-tie-bottom*`): stable when unrelated
  subviews are added, so not memory addresses; not the document order, the ids, the distance,
  the area or the constants alone;
- rounds 59 and 60 (`safe-tie-grid-*`, `sub-tie-*`): in self-written documents, whose frames do
  not satisfy their constraints, a safe area's ties fit the larger constant first, then the view
  whose far edge across the attribute lies farther, then the view the constraints name first;
- the corpus contradicts that rule where the frames satisfy the constraints, as in documents IB
  saves: nextcloud's NCCreateFormUploadConflict and kickstarter's SettingsPrivacySwitchCell follow
  their constraints' document order, kickstarter's SettingsNotificationPickerCell does not, and the
  self-written documents ignore the document order.

So the order comes from Interface Builder's own order of the constraints, which an unstable sort
then shuffles; neither is in the document.

A view's constraints are a set to Auto Layout as long as none has to be broken: with every tied
constraint required and satisfied by the document's frames, the layout is the same whatever their
order. When constraints conflict, Auto Layout may pick which to break by order, so the order is
not equivalent there.

## Decision

1. nomac compiles a tie when every constraint in it is required (priority 1000) and satisfied by
   the document's frames (within 0.01 point, by its relation), writing it in document order. A
   safe area counts across only (its edges above and below depend on the device's insets); margins,
   and views deeper than the owner's subviews (all objects lists them in the tie's order:
   `deep-other-*`) stay refused (B-265). Ties beside the user-defined runtime attributes of several
   objects, refused at first, compile since round 117: those attributes' order follows their
   objects' places, which swapping constraints within a tie does not move.
2. `nomac verify` and `.github/scripts/nib_compare.py` count an ibtool output equivalent when its
   only difference from nomac's is the order of such ties: both archives become graphs renumbered
   depth first from the root, each settled tie's constraints (consecutive in a view's list, same
   first item, attributes, relation and multiplier, no priority, several second items, all
   satisfied by the archive's frames) in one canonical order (the second item's subview path, then
   the constant) in every array and ordered set that lists them, sets sorted, nested archives
   likewise; equal graphs are equivalent (`NomacVerify.NibTieComparison`).

## Consequences

- 48 of the 62 documents no longer stop at the tie; in the corpus 9 are equivalent and the others identical, with
  0 different (nib_compare.py, merged references); in the experiments `tie-second-items-*-reversed`
  and `sub-tie-bottom*`, whose frames satisfy their ties, are equivalent.
- The equivalence is narrow by construction: an unsatisfied or non-required tie, or any other
  difference, is reported as before.
