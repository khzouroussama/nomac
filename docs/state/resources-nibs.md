# Resources, second half: strings, Core Data, storyboards and xibs

Branch `res/nibs`. BACKLOG B-250–B-269 and B-280–B-289, ADRs 0250–0259 (B-290–B-299 and ADRs
0260–0269 are `res/nibs-2`'s). The other half (asset catalogs) is B-200–B-249.

## Current step

First, documents that come out different from Xcode's (the integrator's priority, 2026-11-07), then
the coverage survey's split below, weighted toward live projects, with the corpus ranking beside it.
Done for differences: B-266's rule (a walk of the segues, for nib names and references), which strings
references share, placeholders of nested segues numbered breadth first, connections under static and
prototype cells, the layout guides' warning, warnings' order (ADR 0254), colors but for one route
(B-281). Next: constraint ties (B-265): `~/nomac-out/wt-scratch/nibs/ties/NOTES.md` has a rule for ties
between views, 1,349 of 1,352 recorded pairs but not held out, and nothing for a safe area's; test it on
a split by repository, then build it or refuse by name what stays unmeasured. Then the rest of
`~/nomac-out/wt-scratch/nibs/classify/survey-different.txt` by `tools/classify.py` there (a private copy
of part B's: it writes `classified.json` beside it), then B-268, B-267, B-282. Rank refusals with
`nib_survey_split.py` below. To work in parallel, give each agent its own files and observation directory
(`~/nomac-out/wt-scratch/nibs/agents/<family>/nib`) and one build at a time; the tools in
`~/nomac-out/wt-scratch/nibs/color` (`objdiff.py`, `keys.py`, `xibdiff.py`, `sbdiff.py`) read `NIB_OBS` and `NOMAC`.
Earlier state, kept for reference:

Storyboards are split between two agents since 2026-10-31: this one (`res/nibs`) keeps tofu's list
(text fields, switches, control actions, cell styles, `<mask>`, `firstBaseline`) with BACKLOG
B-266–B-269 and B-280–B-289 and ADRs 0252–0259; `res/nibs-2` takes buttons, stack views,
collection views, image and symbol views and the remaining controls (B-290–B-299, ADRs
0260–0269). Shared NomacNib rules (all-objects order, string pools, connection order) are
announced to the owner before they change.

tofu's Main.storyboard compiles, every nib identical to Xcode 27.0's, but its Info.plist order is
not known, so nomac refuses it (B-266). Control actions are general (round 33), buttons' and
segmented controls' included. Next: B-266, then `firstBaseline` constraints (79 corpus documents use
them).

The launch storyboards of the React Native and Expo test apps (docs/state/react-native.md) compile and
link identical to Xcode 27.0's, Debug and Release (rn-bare's `LaunchScreen` at 15.1 on iPhone and
iPad, expo-default's `SplashScreen` at 16.4).

## Survey split

`python3 ~/nomac-out/scripts/nib_survey_split.py <nomac> <out.json> --docs <dir>` overlays each surveyed
project's shell (`~/nomac-out/survey/repos`) with its `.xib` and `.storyboard` blobs (`fetch_docs.py`,
kept in `~/nomac-out/wt-scratch/nibs/survey/docs`) and runs `nomac check --json`: the build's documents
and options, each refusal's own message. Final survey, 2026-11-07: 1,328 projects, 319 of them live
(Xcode 27 accepts them as they are), 747 with a refusal, all measured. Projects (live / all) and
documents, on main 79a3126a with the first batch below.

| Item | Live | All | Documents |
|---|---|---|---|
| B-260 | 50 | 461 | 1,676 |
| B-261 | 18 | 115 | 154 |
| B-281 (colors, split out of B-260) | 16 | 158 | 437 |
| B-265 | 6 | 46 | 79 |
| `document=missing` (was `unexplained`) | 3 | 12 | 18 |
| B-263 | 0 | 171 | 654 |
| B-291 | 0 | 5 | 5 |
| B-266 | 0 | 2 | 2 |

Causes in this workstream's families (sums of a family's messages; a project can count under several):

| Family | Live | All | Documents | Largest causes (live/all) |
|---|---|---|---|---|
| Colors | 32 | 254 | 544 | `displayP3` 10/33, `calibratedRGB` 8/72, `catalog` attribute 3/6, `deviceRGB` 3/4, a text field's colors 2/3, Xcode 11's `labelColor` 1/8 |
| Bars and toolbars | 20 | 104 | 120 | bar button items without one system item or title 3/14, `<barButtonItem>` in `<items>` 2/10, `<navigationBar>`'s `translucent` 2/6 and `barStyle` 1/5, `<rightBarButtonItems>` 2/4 |
| Cells | 19 | 71 | 179 | `insetsLayoutMarginsFromSafeArea` 4/12, `tag` 2/3, `userInteractionEnabled` 2/3, `<animations>` 1/11, Xcode 8's prototype cell 1/5 |
| Constraints and baselines | 9 | 104 | 155 | ties of constants or relations 5/38, the `baseline` attribute 1/12, `Alignment constraints` capabilities 0/20 and 0/16 |
| Text fields and switches | 6 | 30 | 34 | `enabled` 2/3, `decimalPad` 1/5, `keyboardAppearance` 0/4 |
| Masks and variations | 5 | 35 | 50 | size-class masks in a cell's content view 2/3, `<mask>` in `<variation>` 1/22 |
| Document formats (in neither part's list) | 20 | 175 | 355 | `iOS.CocoaTouch.iPad` 5/15, `ipad*` devices 4/10, `customModuleProvider=""` 2/9, `iPad.XIB` 2/5, `<simulatedMetricsContainer>` 1/13, `<archive>` 1/13, `<simulatedStatusBarMetrics>` 1/10 |

- B-263 falls away, as expected: 0 live; of its 654 documents, at the minimum target 15.0, 233 compile
  and the others stop at other items, largely `<archive>` (192) and `defaultVersion` (56). It stays
  low in this list.
- `unexplained` (7.9% of the survey's projects) was nomac's bug, not a refusal: XcodeProj's `fullPath`
  answers a variant group with its base localization's path, so a variant group with its own `path`
  (React Native's old template, `path = iOS`) resolved to
  `Base.lproj/LaunchScreen.xib/Base.lproj/LaunchScreen.xib` and was never read. Fixed; what is left
  is really absent (`Pods/` not installed, files never committed), 0.9%: `nib:document=missing`.

## Just finished

- First parallel round (four agents in this worktree, `bars-*`, `cm-*`, `cs-*`, `mx-*`; their observations are
  merged into `~/nomac-out/wt-scratch/nibs/nib`): toolbars' items, bars' styles and tints, navigation items'
  lists and attributes and the plain style's warning; labels' masks, size-class masks in cells' content views,
  variations' own frames, static cells' row heights, prototype cells without reuse identifiers, the value2
  style, text fields' background images; baseline constraints, classes and symbol types on constraints, margin
  constraints with multipliers and variations; catalog colors, Xcode 11 pairs, undefined named colors, more
  system colors, every accessibility trait observed, data detectors, keyboard layout guides without a safe
  area. Cells' `imageView` right after it (370 uses in the survey). What they deferred is B-265 to B-269 and B-282.
  Two wrong nibs fixed: a prototype cell with an empty
  reuse identifier got a nib, where Xcode leaves the cell out, and `style="plain"` in a navigation item wrote
  `UIStyle` 1, where Xcode writes none and warns. Corpus 462 identical and 14 equivalent (from 456 and 14), 0
  different; experiments 2,858 identical and 7 equivalent, 0 different.

- Colors (`ColorManagement`, docs/formats/nib.md "Color conversions"): every route but one reproduces
  CoreGraphics to the bit, found by observing `CGColor` and `ColorSyncTransformCopyProperty`. The table of
  the corpus's 60 colors is gone. calibratedWhite without colorMatched stays a table of the survey's 97
  values, its route unexplained (B-281). Scratch: `~/nomac-out/wt-scratch/nibs/color` (`val_d`: the
  validation harness against `CGColor`; `gg_d`: the unexplained route).

- Second survey batch: text fields' traits by every value (`tf-trait-*`), disabled text fields and their
  tints, cells' view attributes (`cell-attr-*`, `cell-mode-*`), `propertyAccessControl` and `<animations/>`
  ignored below the document. `tag="0"` on any view wrote `UITag` 0, a wrong nib, where Xcode writes
  nothing; fixed. Corpus 456 identical and 14 equivalent (from 448 and 11), 0 different; 713 of 1,065
  documents compile (from 692).

- First survey batch: variant groups' localizations resolved as the build does, `nib:document=missing`,
  colors under B-281, unmatched `calibratedRGB`, system colors with components. Colors' routes found
  (docs/formats/nib.md); corpus 448 identical and 11 equivalent (from 446), 0 different, 692 of 1,065
  documents compile (from 687).

- Round 64 (`no-translate-mask-*`): a constrained subview that does not translate its mask keeps
  the mask its document gives; the refusal is lifted. Paused again after it.

- Rounds 61 to 63: colors' ColorSync pipeline not reproduced yet (B-281, the grids recorded);
  Xcode 8's `<simulatedMetricsContainer>`, Xcode 5's `<development>`, the multipliers capability
  change nothing; a scene's view keeps its origin (below an opaque bar at 64), a device resizing it.
  10 of the 16 storyboards with the container compile.

- ADR 0253: settled constraint ties (required, satisfied by the frames) compile in document order
  and compare equivalent (`NomacVerify.NibTieComparison`, `nib_compare.py`). Across the corpus,
  holdout and sweep the tie refusal drops from 62 to 14 documents; corpus 440 identical and 9
  equivalent (from 426 and 1), 0 different.

- Rounds 59 and 60 (`safe-tie-grid-*`, `sub-tie-*`): ties of one item to several views, the
  largest refusal across the corpus, holdout and sweep (62 of 1,071 documents), stay refused. The
  rule the self-written documents fit fails the corpus's consistent layouts (B-265).

- Round 58 (`document-version-*`): a document's `<deployment version>` changes no nib from 8.0 to
  27.0; below 5888 (23.0) ibtool prints a global document warning, which `nomac ibtool` now prints
  for xibs too. Corpus 426 identical (from 411), 0 different.

- Round 57 (`same-distance-*`): subviews whose frames lie as far from the origin sort by x;
  the same x above each other stays refused (their constraints interleave).

- Round 56 (`moved-*`): constraints ibtool installs on a descendant of the listing view move to
  their items' nearest common ancestor and sort there; in all objects, a cell's moved constraints
  between its content view's subviews stay after the cell's own. Corpus 411 identical (from 409),
  0 different (pocket-casts' FilterNameCell and PodcastSupporterCell).

- Round 55 (`deep-negative-offset*`): a view inside another listed item sorts right after it even
  when nearer the origin (cwa's OnboardingInfoViewController, with res/nibs-2's B-290 patch);
  an unrelated item between their distances is refused (no single key gives ibtool's order).

- Rounds 53 and 54 (`deep-safe-*`, `masks-walk-*`): a deeper view's constraints to the safe area
  sort before those to the view; the storage walk visits a deeper view only at the first
  constraint naming it, in each of its two passes. Corpus 401 identical and 1 equivalent
  (WelcomeContainerViewController, set order), 0 different.

- Round 52 (`outside-*`): frames wholly outside the view, on its edges or of no size sort by the
  distance rule like any other; the system font named `.AppleSystemUIFont` is the regular system
  font's object (pocket-casts' UserEpisodeDetailViewController). Corpus 397 identical (from 391).

- Round 51 (`scroll-guides-*`, `deep-through-scroll`): constraints to a scroll view's content and
  frame layout guides, each a safe-area-like guide, and to views inside scroll views. Corpus 383
  identical (from 379 on the same main), 0 different; experiments 2135, 0 different; res/nibs-2's
  2881, 0 different.

- Rounds 48 to 50: ties of one first item to two second items (27 of the 28 documents refused as
  "differing only in constants") stay refused: stable under unrelated subviews, but no rule found
  (`tie-probe-*`, `safe-tie-*`, `sub-tie-*`; B-265). Identified constraints with a constant or a
  priority compile (`NSLayoutIdentifier` before `NSConstant`), and a constraint whose second
  attribute alone is a center sorts by it (`norm-cross-*`; cwa's home cells). Corpus 337
  identical (from 333), 0 different; experiments 2131 identical, 0 different.

- Round 47 (`norm-*`, `sub-first-all`): constraints sort by their attributes as written, a view's
  first in one written from the view, in one order of all attributes with margins (each pair's
  margins first, the top margin before the bottom one); views through stack views are named as
  deeper views (`deep-through-stack`, round 42's rules). Corpus 330 identical (from 322), 0
  different; experiments 2126 identical, 3 equivalent, 0 different; res/nibs-2's 2773, 0.

- Rounds 45 and 46: constraints to a scene's top and bottom layout guides compile, the guides
  sorting as sibling subviews at the view's top and bottom edges (`sb-guide-*`); a text view's
  text past 512 characters is two `NSMutableString`s (`text-view-length-*`, res/nibs-2's text
  views). Corpus 320 identical (from 314), 0 different; 322 with res/nibs-2's 884a0d2b, where
  uncloudnotes' five UnCloudNotes storyboards stop next at bar button items outside a navigation
  controller (B-261, res/nibs-2).

- Round 44 (`masks-*`): a nib's trait storages follow a depth-first walk of its views (a view's
  properties, subviews mask, constraints mask, its constraints' constants, all then installed,
  constraints walking the deeper views they name, then subviews), so masks of several views and
  masks beside constants compile. Corpus 314 identical (from 312: wikipedia's ShareViewController
  and PageHistoryCountsViewController), 0 different; experiments 2079 identical, 3 equivalent,
  0 different; res/nibs-2's set 2727 identical, 0 different. WelcomeContainerViewController
  stops next at the stack view's `axis` variation (res/nibs-2's stack views).

- Rounds 42 and 43 (`deep-other-*`, `effect-label-*-sibling*`): a subview's constraints to views
  deeper than the subviews sort first in its group, the deepest first; all objects lists a view a
  constraint names in that constraint's place; an effect view lists its content view's subviews.
  cwa's ExposureDetectionViewController is identical with res/nibs-2's table commits (f1aa707e,
  ae2411f3) applied. Experiments 2060 identical, 3 equivalent, 0 different (res/nibs-2's set with
  its commits: 2656 identical, 0 different); corpus (merged references) 185 identical, 0
  different, 192 with res/nibs-2's commits.
- Set order equivalent (ADR 0252, `NomacVerify.NibSetComparison`): size-class masks of several
  objects compile.

- Rounds 40 and 41, masks by size class (`sc-mask-*`): a record per variation, the default first,
  then size classes in the reverse of the attribute records' order; includes and excludes; subview
  masks; storyboards apply the device's records. Records' `NSSet`s follow ibtool's memory
  addresses (`sc-mask-set-probe-*`), stable run to run: a nib differing only in a set's order is
  equivalent (ADR 0252, `NomacVerify.NibSetComparison`, `nib_compare.py`). Experiments 2045
  identical and 3 equivalent (from 2032 identical), 0 different. Corpus on res/nibs-2's merged
  references (`~/nomac-out/nibs-observations/corpus-merged`): 168 identical, 0 different; the
  size-class documents stop next at masks of several views and other blockers.

- Round 39, deeper constraint items (`deep-*`): views constrained to grandchildren and deeper, cells'
  own constraints to their content views' subviews; moved constraints and deeper views' safe-area
  constraints refused (B-265).
- Round 38, `<mask key="subviews">` defaults (`mask-subviews-*`): subviews left out of their view
  by default (nextcloud's NCShareUserCell); constrained ones refused.
- Round 37 (`baseline-*`, `constraint-user-label`, `tf-enables-return-key*`): first baselines
  between subviews, constraints' user labels, text fields' `enablesReturnKeyAutomatically`; text
  fields' `adjustsFontForContentSizeCategory` and default alignment, switches' tint colors; table
  views' `scrollEnabled="NO"`, cells' own background colors with a selection style; constraints
  holding a subview to its view's center sort by that center (`cross-attribute-*`).
- Round 36, navigation shapes (`sb-nav-*`, `sb-sim-nav-*`): navigation controllers' titles, bars'
  flags and safe-area insets, items without a title, simulated navigation-bar metrics. Corpus 259
  identical, 0 different.
- Round 35, constraint ties (`tie-*`): identical constraints written from the view compile
  (nextcloud's); ties of one item to different subviews stay refused: the subviews' distance fits
  the experiments but not 11 corpus documents (B-265).
- Round 34, cells as the corpus has them (`cell-*`): the cell's and the content view's layout
  margins, plain and directional, constraints to custom margins, separator insets and IB's
  separator moved by them; `userLabel` and an ambiguous content view change nothing; a selection
  style's background view rounded up in height; cells' tint colors (they were ignored: cwa).
- Control actions in general (round 33, `act-*`, `sb-act-controller`): every event type the corpus
  uses (UIControl.Event's values), actions without an event (no mask, sorted first), custom
  controls (`<view>`s of a custom class), any target in the nib; buttons, sliders and page
  controls', buttons' and segmented controls' (`act-slider-value`, `act-page-value`,
  `act-button-*`, `act-segmented-value`), once res/nibs-2's fixes (e50e7114) made the documents
  they open identical. Storyboards with segues among more than 3 scenes whose
  Info.plist order depends on the unknown order are refused (B-266: tofu's, `sb-info-order-graph`).
- tofu's list (round 32: `tf-*`, `sw-*`, `ev-*`, `cell-style-*`, `cell-all-keys`, `table-*`,
  `mask-*`, `sb-extra-view*`, `sb-cellseg-nav-root`, `sb-action-other-scene`, `frames-outside-*`,
  `tie-constant-reversed`, `sb-info-order-graph`): text fields with input traits, switches and
  their `frame` key-value pairs, control actions with event masks (after the outlets, by mask,
  selector, source), actions to other scenes dropped, cells of the built-in styles
  (`UITableViewLabel`s), reorder control and editing accessory, `allowsSelection`,
  `definesPresentationContext`, symbolic constraints' constants dropped, default constraint masks
  (`_UIRelationshipTraitStorage`), views beside a scene's controller kept alive by it, controller
  nibs' all objects breadth first, a cell's content subviews as its own children, cells' segues in
  navigation roots, localizable navigation titles, placeholders, texts and section headers, frames
  partly outside their superview and constant-only ties, key tables of 157–199 keys (383
  buckets, B-259). Experiments 1955 identical, 1 different (`sb-info-order-graph`, B-266), 156
  refused; corpus documents 127 identical (116 before), 1 different (tofu's Info.plist); reference
  compiles 25 of 207 identical (22), 1 different; links 3 of 17 identical, 1 different.
- Cell-triggered segues (round 31, `sb-cellseg-*`, `sb-segorder-*`): templates of the controller
  reached through upstream placeholders numbered from the last cell, outlets reversed per group,
  shared template strings. Experiments 1896 identical.
- Table view controllers (round 30, `sb-tvc-*`, `sb-nav-root-*`): table views as controllers'
  views, prototype cells as nested nibs (alphabetical by reuse identifier), static sections in a
  top-level data source, table view controllers and custom-class roots with outlets in navigation
  controllers. Experiments 1883 identical, corpus 116, reference compiles 22 of 207.
- Table view cells in xibs (round 27, `cell-*`): the cell, its content view and IB's separator,
  selection styles with their background configuration, accessories, indentation, reuse
  identifiers; constraints to layout margins (round 28, `margin-*`: 8 points in every container);
  subviews' groups ordered by their frames' distance from their superview's origin (741 of 758
  corpus views; replaces the pairwise rule); table views in xibs (round 29, `table-*`: styles,
  separators, heights, the grouped and `tableBackgroundColor` backgrounds). Experiments 1863
  identical, corpus 114 identical, reference compiles 21 of 207 identical.
- Constraints between subviews (round 26, `sib-*`): sibling constraints in their first item's
  group after its view and safe-area constraints, in the safe area's attribute order; groups by a
  pairwise frame rule (y within a column, x otherwise) that fits 735 of 758 corpus views.
  flappy-fly-bird's LaunchScreen compiles and links identical to Xcode's; reference compiles 18 of
  207 (all identical), links 3 of 17; corpus documents 86 identical.
- Converted colors (round 25, `converted-*`, `sb-converted-*`): the corpus's 60 `calibratedRGB`,
  `displayP3` and `deviceRGB` colors as the sRGB floats ibtool wrote, alpha unconverted; corpus
  reference compiles re-measured with the restored checkouts: 17 of 207 compile, all identical
  (`runtasks.py` now finds Products references too).
- Navigation controllers (round 24 `sb-nav*`, `sb-bar-*`): the root controller archived in the
  navigation controller's nib, the bar of IB's geometry, navigation items (also on controllers
  outside a navigation controller), done/cancel/add bar button items, their outlets and actions;
  the encoder's conditional references. Experiments 1476 identical, 0 different.
- Scenes and segues (round 24, `sb-scenes-*`, `sb-segue-*`): every scene the initial controller,
  an identifier or a segue reaches; the Info.plist's nib names in a copied Foundation dictionary
  filled in document order; show and presentation segue templates; plain `UIViewController`s for
  controllers only segues reach. `deviceRGB` is not the display's profile (sRGB within 2.4e-4 on
  this Mac's P3 display: `sweep-deviceRGB-*`), so converted colors can be a table.
- Size-class variations (rounds 19 and 22: `variation-*`, `vo-*`, `sb-vo-*`): labels' fonts and
  constraints' constants as `_UITraitStorageList`s, records in a fixed size-class order,
  constraints' storages written twice, a storyboard's objects taking the values of their device's
  size classes (every device and orientation observed), objects of no values numbering their first
  value 0. 78 variation experiments identical; `<mask>`s stay refused (B-260).
- Expo's splash-screen plugin (round 21, `sb-expo-*`, `named-color-255-*`): `resizeMode` contain and
  cover, image widths 100 to 288, the legacy full-screen image, and every k/255 component as the
  plugin writes it (`toPrecision(15)`); all 101 identical without a change to nomac. rn-holdout's
  RNLibs launch screen is React Native's template (identical to rn-bare's but for the name).
- Launch screens (round 20: `sb-launch-*`, `bool-*`, `alpha-*`, `label-*-absent`,
  `constraint-multiplier-*`, `constraint-symbolic`, `color-system-and-cocoa-touch*`): every iOS
  release's deployment target from 8.0 to 26.2; below a document's features (safe areas 11.0,
  named colors 13.0) ibtool writes `objects-<version>+.nib` and `runtime.nib` bundles, which
  nomac refuses (B-263); labels without color elements, `true`/`false` booleans, alpha 1 left
  out, `systemColor` with a `cocoaTouchSystemColor` fallback, multipliers rounded to floats and
  written `a/b`, `symbolic` constraints. Experiments 1239 identical (from 960), 0 different.
- Labels and fonts (`label-*`: the corpus's 106 font descriptions, sizes, weights, text styles,
  named fonts), one string pool per document (`strings-shared`), the class table's unused
  fallbacks by name, and no `UIBounds` for a 0 x 0 frame. Experiments 960 identical, corpus 85.
- Outlets and an outlet collection (sorted by name, ties by source), a storyboard controller's
  outlets through `UpstreamPlaceholder-1`, simulated metrics, freeform scene sizes and
  clearsContextBeforeDrawing on views; flutter's link now checks identical.
- Image views and `<image>` resources, constraints (their keys, and their order by item and
  frames, pinned by `order-*`: every corpus view joined with one subview or its safe area), safe
  area guides in xibs and the guide a constraint names, views without frames, storyboards without
  trait collections (393 x 852 before iOS 17), declared layout guides with safe areas, and the 10
  digits storyboards keep of a color component. Experiments 723 identical, 0 different; corpus 72
  identical (from 41), 0 different.
- Colors the corpus uses: `calibratedWhite` (its values, converted as observed), Xcode 11 system
  colors, colors in documents without `colorMatched` (the observed `calibratedWhite` grays), and a
  storyboard First Responder of class `UIResponder`; the corpus has 41 identical documents.
- Storyboards without a `<device>`: 600 x 600 scenes when deployed before iOS 17.0 (`sb-deployment-*`),
  which made retro-rampage's two storyboards identical inside its app (deployment 11.0); the
  target devices change nothing (`sb-targets-*`); `link-lproj` records the multi-storyboard link.
- The key-table order, from four investigations (`~/nomac-out/wt-scratch/nibs/<family>/REPORT.md`:
  big-tables, temporary-keys, scene-pairs; controller-features still running): keys at first use,
  depth first, `UINibEncoderEmptyKey` uncounted until the archive is finished, tables holding
  Core Foundation's capacity plus one up to 251 buckets. It reproduces every observed nib (510 of
  nib_experiments.py, 1018 of the corpus, 16 to 199 keys) and replaces the held
  `UIAlphaComponent`, the view-controller order and the 33-key limit (B-262 closed; B-259 now past
  156 keys). nib-experiments `ladder-*` pin the thresholds.
- Storyboards: safe areas, the device's size for scenes' views (swapped in landscape, the frame
  without a device), autoresized subviews, `systemVersion`, `<adaptation>`, `layout`, more devices
  and capabilities.
- Storyboards (B-261 in part): `nomac ibtool <storyboard> --compilation-directory` and `--link`
  for one reachable scene with a plain or custom-class controller and view, an identifier, at
  most one subview; 9 of the 16 storyboard experiments identical, the others refused; the
  encoder builds the key table after encoding, in a xib or view-controller order; fallback
  classes no object has go at the end of the class table; tables of 34 to 53 keys without
  colors compile. Of the corpus's 594 documents none differs (593 refused).
  Four investigators work on the key order (`~/nomac-out/wt-scratch/nibs/<family>/REPORT.md`:
  controller-features, big-tables, scene-pairs, temporary-keys).
- For the packaging workstream (B-309): `BinaryPropertyList.foundationData(rereading:)` and
  `FoundationHashTable.created(with:)`, the Info.plist an app-store-connect export writes again
  (20 of 20 observed files byte for byte; docs/formats/property-lists.md).
- Colors (B-260 in part): `UIColor` for gray and sRGB components, system colors with IB's own
  values, named colors, shared colors; a subview's `translatesAutoresizingMaskIntoConstraints`
  ignored (docs/formats/nib.md "UIColor").
- Strings (5bc87ba): `NomacPlist` writers and readers, `nomac builtin-copyStrings` (all 9885
  corpus strings files identical), `nomac xcstringstool compile` (all 49 corpus catalogs).
- Core Data observations (ce8287b): the `.mom` keyed archive, the version hashes (entities solved,
  properties not, B-255), and Foundation's dictionary order, which explains every observed entity
  and property dictionary (docs/formats/foundation-collections.md).
- `NomacNib` and `nomac ibtool --compile` for plain views (ADR 0251, docs/formats/nib.md):
  `NIBArchive` writer (with the `LNE` trailer), depth-first encoder, UIView keys and order,
  subviews, custom classes; everything else refused.
- The review of 5bc87ba..f590d33: numbered objects kept alive, `UINibEncoderEmptyKey` entered
  last, `customModuleProvider="target"` mangled with `--module`, integer sizes, every unobserved
  input and option refused, strings tests stated as format facts, the experiments behind every
  cited observation committed, `\U` surrogate escapes, dead NomacNib code removed.

## Next actions

1. Finished before this pause (round 114 to 116, docs/formats/nib.md): outlets to a controller's
   navigation item and bar button items, from the controller and from its view's subviews;
   collection views' section header and footer views; masks in collection view cells. Still
   refused, with the destination named: a prototype cell's outlet to such an object
   (`sb-outlet-bar-tvc-from-cell`) and toolbar items as outlet destinations (`<barButtonItem>` in a
   toolbar's `<items>` does not compile yet).
2. Paused 2026-11-03 (usage). Assigned order: `layoutMarginsFollowReadableWidth` on cells (11
   documents across corpus, holdout and sweep; not started), then colors (B-281: fit ColorSync's
   pipeline on round 61's grids in `~/nomac-out/wt-scratch/nibs/nib`), then B-266
   (DescriptionWelcome). nibs2-1 owns control actions and `<archive>` documents. Rank refusals
   with `python3 ~/nomac-out/scripts/nib_refusals.py .build/debug/nomac /tmp/nomac-corpus
   /tmp/nomac-holdout ~/nomac-out/sweep/apps`; measure with nib_compare.py on
   `~/nomac-out/wt-scratch/nibs/nib` and `~/nomac-out/nibs-observations/corpus-merged` (0 different).
   variations of other properties the walk meets (stack views' `axis` and `spacing`).
2. B-266: the order of `UIViewControllerIdentifiersToNibNames` when segues reach scenes out of
   document order (graph experiments, `sbinfo_sim.py` in scratch); tofu's Info.plist then.
3. `firstBaseline` and `lastBaseline` constraints (B-265 baselines), then the next blockers of
   this agent's list by `images/rank2.py`.
4. B-259: a ladder past 199 keys. Strings: `xcstringstool generate-symbols` (B-254).

Core Data (B-255, B-256, B-257, B-258, docs/formats/coredata.md, coredata_experiments.py) moved to
its own agent; this workstream keeps NomacPlist and FoundationHashTable, which it reuses.

## Second agent

Branch `res/nibs-2`, BACKLOG B-290–B-299, ADRs 0260–0269. Works on buttons, stack views,
collection views and their cells, image views and symbol images, scroll views, segmented
controls, activity indicators, progress views, page controls, sliders and date pickers, by corpus
impact; the first agent keeps text fields, switches, control actions, cell styles, `<mask>`s and
`firstBaseline`. Element encoders go in their own files (`UIButtonEncoding.swift`); the shared
`view()` of `XIBCompiler.swift` only dispatches to them. Observations in
`~/nomac-out/wt-scratch/nibs2/nib` (a copy of the first agent's plus round 32 on), scratch tools
in `~/nomac-out/wt-scratch/nibs2` (`btn.py <experiment>...`: a nib's buttons, nested objects
inline; `nstruct.py`, `objlist.py`: an experiment's objects and its all-objects list;
`expdiff.sh`, `corpusdiff.sh`: Xcode's nib against nomac's).

Current step: working through part B's refusals from the survey's ranking (2026-11-07): the
survey's `nib:refused=B-260` split by real cause, weighting the projects Xcode 27 accepts, then
B-261's storyboard features outside part A's list. Wrong nibs come before refusals.

Everything below lives in `~/nomac-out/wt-scratch/nibs-2` (outside the repository; none of it is committed):

Next actions:
1. Wrong nibs: none left in this part. Xcode's own outputs for 5,297 documents of the survey are in `survey-obs`, the
   holdout's in `holdout-obs`: `python3 $C survey-obs <nomac> corpus` (`$C` = `.github/scripts/nib_compare.py`) counts them,
   `tools/classify.py <list>` groups them by first difference, `ddiff.py <document> 30` shows one. 28 survey and 5
   holdout documents differed at the last count, in part A's area but for what SF Symbols warn about: `SF Symbol 'x' is
   deprecated, use 'y' instead. [7]` needs ibtool's table of renamed symbols, which nomac does not have, so nomac prints no
   such warning, nib the same (3 survey documents). A xib's warning order changes from run to run and counts as equivalent
   (ADR 0254). The B-291 placeholders stay refused.
2. Refusals, ranked by the projects Xcode 27 accepts: `JOBS=3 TOP=60 python3 tools/rank_survey.py <current nomac> survey-docs
   survey-rank.json`, of 64 such projects with a refused document (`live` in `survey-docs/projects.json`, no `build:*below*`
   feature). Re-rank before starting anything: part A lands the same fixes, and did for bars while this list ran. Done:
   localized button configurations, navigation bars' frames, shadows, shadow images and background, table header and footer views,
   symbol configurations, hosting and player controllers, date pickers' styles, rendering modes. Next: `hasAttributedTitle` (4), a global tint
   with a table as a scene's view (3), `destinationCreationSelector` (3), `translatesAutoresizingMaskIntoConstraints` on a scene's view (3),
   `<date>` in `<datePicker>` (14 documents), a button state's symbol configuration beside a title (9), a hosting controller as a root.
3. B-291, several recognizers in a scene: the placeholders' numbers are not the sorted connections' first reach;
   `sb-gesture-three`, `-nested`, `-predict` and wikipedia's DescriptionEditViewController fit no walk tried (`gsum.py`).

Tools: `measure.sh [full]` (corpus, holdout, experiments), `tools/check_docs.py <nomac> <regex>` (the documents a refusal
stopped, against Xcode's output, the check that keeps a lifted refusal from writing wrong nibs), `cmp.py <round files>`,
`kdiff.py <base> <names>`, `keys.py`, `dumpnib.py`. Round name lists are `round120.txt` to `round133.txt`, observations
`nib/observations.json`. `fam/README.md` and `tools/treelock` are a kit for several agents in this one worktree, never
used yet. Under the CPU rule of 2026-11-07, test with `--filter NomacNibTests` and `swift build -j 4`.

Just finished:
- Rounds 131 to 133: only `Base.lproj` is localizable, frameless views by `toolsVersion` (11019, bisected), sliders
  without a value, accessibility configurations by the walk. Survey (5,297 documents): identical 2,725, equivalent
  60, different 66, refused 2,446, from 2,695, 59, 96, 2,447. Corpus 459 identical, 14 equivalent, 0 different, 115
  refused; holdout 192, 4, 10, 110.
- Rounds 125 to 128: navigation and tab bar controllers' attributes and shapes, children with their own
  identifiers (about 20 survey documents stopped there), table and collection children, tab bar items on
  any controller, rootless navigation controllers and navigation controllers' own segues.
- Rounds 123 and 124: map views (25 survey projects), vibrancy, legacy collection cells' content view
  colors, buttons' title shadows.
- Rounds 120 to 122 and 129, 130: what older documents carry: `<animations/>`, simulated metrics, capabilities,
  `defaultVersion`, development versions, the iPad runtime, more devices, documents without Auto Layout
  (default mask 40, no scene layout guides); labels' minimums by the device's font; the warning about fonts
  that do not adjust. On the first 3,505 survey documents: identical 1,468 (from 1,253), equivalent 19 (8), different
  39 (48), refused 1,979 (2,196); experiments 4,657 identical, 12 equivalent, 0 different, 237 refused.
- Connections of one name, or of one event and selector, go by original class, then a walk of the
  views: xibs depth first, storyboards each view's subviews and then on from the last (rounds 118
  and 119; replaces all objects' order, which made wikipedia's ScrollableEducationPanelView and the
  holdout's FancyAlerts wrong). Two recognizers' actions of one selector compile.
- B-290 closed (round 117): runtime attributes' objects sort by the decimal strings of their places
  plus one, byte by byte; 153 nibs of the corpus and experiments and 48 of the holdout, none seen by
  the rule's finding, and 28 experiments recorded to test it. Ties beside them compile too. Corpus 454
  identical, 14 equivalent, 0 different, 120 refused (from 446, 11, 0, 131); holdout 178 identical, 3
  equivalent, 13 different, 122 refused (from 175, 3, 14, 124).
- Named fonts: every name compiles, by the table of the 309 names ibtool resolves; others as
  unresolved (round 115, `docs/formats/nib.md` "Named fonts").
- Labels' shadow colors and offsets, minimum font sizes and scale factors with and without fitting,
  and the warning of a minimum over the font's size (round 115, 25 experiments identical).
- Web views' configurations, preferences and own attributes (round 114, 44 experiments identical).
- Controllers' simulated bars, which change nothing (round 112).
- Navigation roots that are the initial controller or that segues reach (round 111), the
  retina6_72 device and older header elements (round 110).
- Table view controllers' refresh controls (round 109, 5 experiments identical).
- The corners' content modes as IB spells them (round 108; 7 documents stopped at `TopLeft`).
- Text views of one font, color and alignment sharing their attributes (round 106), and a
  scene's recognizer numbered after its controller when the view nib's connections reach the
  controller first (round 107); wikipedia's EditSaveViewController equivalent under ADR 0260.
- Control actions of every event, date pickers' actions, long press, pinch, rotation and screen
  edge pan recognizers (round 105, 18 experiments identical).
- ADR 0260: outlet collections of several sources, whose order ibtool changes from run to run,
  compiled by name and compared by a canonical form (`nomac verify`, `nib_compare.py`).
- What the holdout stops at next (rounds 103 and 104, 29 experiments identical): cells' and
  content views' layoutMarginsFollowReadableWidth and accessibility, presentation segues'
  presentation and transition styles, text views' adjustsFontForContentSizeCategory and calendar
  event detection, top-level stack views.
- Table view cells' and content views' layoutMarginsFollowReadableWidth (round 103, 6
  experiments identical; 14 holdout documents stopped there).
- Storyboards' global tint (round 102, 15 experiments identical; 17 holdout storyboards stopped
  there).
- User-defined runtime attributes of cells, content views, switches, flow layouts, navigation
  bars and bar button items, and the point, rect, range, nil and localized string types (rounds
  100 and 101, 21 experiments identical).
- Top-level xib views without freeform metrics sized to the device under iOS 17 (round 99).
- Connections without an id dropped, as ibtool does (round 98, `conn-no-id-*`).
- Constraints' identifiers from the document's string pool (round 98, `cid-*`), a private app's
  banner xib.
- Views' content stretch and table view cells' (and their content views')
  clearsContextBeforeDrawing (round 97, 17 experiments identical), refusals of a private app.
- B-290 past place 38: pairs of objects all at places 9 and over keep the rule up to place 97
  (14 corpus nibs); corpus 424 identical, 0 different.
- Storyboard references (round 96, 15 experiments identical): segue destinations, tab bar
  children, navigation roots, the Info.plist's reference table; gomap's MainStoryboard, Display,
  Changeset and nextcloud's Main now stop at other features (constraints, unreached controllers,
  row heights, a tab bar controller's extended layout).
- Outlet collections of several names from one source, in their first connections' document
  order (round 95); of several sources ibtool's order changes run to run, so they stay refused
  (B-291). wikipedia's WMFEditorToolbarHighlightView identical (corpus 399).
- Text styles ibtool does not know (round 94): a font of no name, attributes or size;
  pocket-casts' ProfileViewController identical (corpus 398), PlusLockedInfoView stops at
  constraints.
- Push, modal and custom segues with ibtool's deprecation warnings, nomac's first document
  warnings (round 86); gomap's storyboards now stop at other features (search bars, bar button
  item styles, extended edges...).
- B-290 merged for places 3 to 38: the restricted rule predicted all 34 corpus nibs in range, 11 of
  them unseen; cells' background flag before their separator inset (round 85), info buttons'
  default hugging 750. Corpus 379 identical (from 346), 0 different.
- Storyboard container views (round 84): embed segues, embedded views sized as their containers,
  empty containers. wikipedia's WMFReferencePanels, WMFLoginViewController and
  WMFAccountCreationViewController identical (corpus 346).
- Page view controllers (round 83, 7 experiments identical); wikipedia's DescriptionWelcome now
  stops at a container view, kickstarter's Discovery and BackerDashboard at an unreached scene.
- Stack views' size-class variations of axis, distribution and spacing (round 82): wikipedia's
  InsertMediaImageInfoView identical; WelcomeContainerViewController now stops at a constraint
  (B-265), WMFEditorToolbarExpandingView at a hidden variation.
- Rounds 80 and 81: localizable long text views, empty texts not localized, Xcode 8 cell frame
  insets, presentation settings and bar button items of navigation roots in containers, buttons'
  segues in navigation roots, template outlets by class. All uncloudnotes storyboards in the
  corpus's split chain identical (corpus 338).
- Rounds 78 and 79: navigation controllers' identifiers and toolbars, bar button items outside
  navigation controllers, navigation roots' titles and kept selection, containers' children with
  outlets, Xcode's Master-Detail template. uncloudnotes' three CampgroundManager storyboards
  identical (corpus 318); react-native-image-crop-picker's QBImagePicker storyboard (the RN
  sweep's B-261) now stops at constraints (B-265).
- Segues buttons and bar button items trigger, unwind and popover segues, exits, titled bar button
  items, navigation roots with their own identifiers (round 77, 26 experiments identical).
- showDetail segues and containers' children with segues (round 76): showDetail templates,
  children's templates, table view controller roots in containers, children segues reach compiled
  in their own nibs too; the navigation root code shared with containers. uncloudnotes' split
  storyboards now stop at a navigation root with an identifier (a popover's destination) and a
  table view controller's `title`.
- Split view controllers (rounds 71, 74): master and detail, plain or navigation controllers,
  titles (localized too), identifiers, custom classes, sharing the tab bar controllers' code. All
  31 container experiments identical; uncloudnotes' 8 split storyboards now stop at cells'
  showDetail segues.
- A constraints mask's descendants name a safe area by its placeholder guide (round 75, the
  corpus's pocket-casts ShelfActionsViewController).
- Tab bar controllers (rounds 72, 73): children in segue order with their tab bar items, the tab
  bar, identifiers, custom classes, children's titles, navigation children with their roots; the
  tab bar controller's and navigation controllers' outlets before the view controllers'. 18 of 18
  experiments identical; children with segues or outlets are B-292. Navigation bars' hugging
  string and navigation items' title attributes now pooled in their nib.
- Collection view controllers (round 70), table and collection view controllers' kept selection,
  storyboard identifiers from the document's strings. No corpus document gained yet (netnewswire's
  stop at a split view controller and a navigation controller with segues).
- Table views (round 68): scroll flags in a scroll view's order, the etched separator, estimated
  section heights, multiple selection, safe area insets, separator color and inset, section index
  background, a table's own constraints in all objects. Corpus: 172 identical, 0 different of the
  385 documents measurable while five apps re-clone (gomap, icecubes, mastodon and nextcloud
  against references recaptured at their Xcode 27 pins); pocket-casts' ShelfActionsViewController
  to check when pocket-casts is back.
- Round 69 observed, not compiled yet: cells' accessory-triggered segues (`accessoryActionSegueTemplate`,
  a second placeholder) and the detail button accessory (`UIAccessoryType` 4).
- New scope from nibs-3 (segues and scene shapes, table views, text fields, storyboard container
  views, variations). Text fields (rounds 66, 67): clear buttons, alignments, borders, colors,
  placeholders, every corpus input trait; disabled segmented controls' alpha and stopped activity
  indicators' hidden flag, found by a ladder the text fields unblocked. Corpus 300 identical (from
  293), 0 different; no text field refusal left.
- B-290 corpus round with a held-out half: a rule fitting 16 of 16 documents and 95 self-written
  experiments predicts 10 of 11 held-out nibs (ArticlePopoverViewController's root view misses).
  Not merged; parked with the findings and a restricted rule to validate on unseen apps.
- Round 65: date pickers (date and time, count-down), picker views, IB's userComments, text views'
  nil text and editable text attributes. Corpus 293 identical (from 292), 0 different. Several
  fragments of attributed labels skipped: no corpus document has them.
- Navigation bars among subviews (round 64). Corpus unchanged at 292: uncloudnotes' launch screens
  now stop at a constraint to the controller's bottom layout guide, gomap's display settings at a
  segue's trigger.
- B-290 round 63, timeboxed: no model of the order holds; parked with the findings in BACKLOG
  (deterministic, not addresses, not IB's document ids; a hash table of places fits 60 of 70).
- WebKit views (round 62): IB's web view configuration. Corpus 292 identical (from 291 on main
  with toolbars), 0 different.
- Toolbars among subviews without items (round 61): the nib's shared empty array. Corpus 277
  identical (from 276), 0 different.
- Round 60: symbol images' variable values, hierarchical colors, preferred configurations of
  weights, point sizes and text styles, in image views and buttons' states. Corpus 276 identical
  (from 275), 0 different.
- Round 59: `misplaced` (no change), image views' symbol references and preferred symbol
  configurations, localized segment titles. Corpus 275 identical (from 274), 0 different; the
  other documents stop one layer deeper (variable values, hierarchical colors in button states,
  font-based symbol configurations, masks, constraints).
- `<accessibilityOverrides>` (round 57, no change) and xibs' `<containerView>` (round 58, a plain
  view). Corpus 274 identical (from 272), 0 different.
- Labels' minimum scale factors (round 56): text styles' default sizes, quarter-point rounding.
  Corpus 272 identical (from 268), 0 different.
- Attributed labels of one fragment (round 55, `al-*`): fonts, colors, paragraph styles, the empty
  string. Corpus 268 identical (from 263), 0 different.
- Button configurations (round 54, `bc-*`): styles, titles and their fonts, images and symbol
  configurations, placement, padding, base foreground color. Corpus 263 identical (from 262), 0
  different; the other configured buttons' documents stop at firstBaseline, constraints'
  userLabel, constant-only constraint pairs and text fields' enablesReturnKeyAutomatically.
- Connections of one name (round 53, `oc-*`): placeholders first, then by their sources' original
  classes, then all objects; outlet collections of one name from several sources. Replaces the
  refusal of outlets from objects of different classes. Corpus 262 identical (from 260), 0
  different. Collections of several names stay refused (B-291).
- Gesture recognizers in storyboards (round 52, `sb-gesture-*`), one per scene, and IB's empty
  `<gestureRecognizers/>`; several per scene refused (B-291). Restoration identifiers equal to
  the storyboard identifier share its string. Corpus 260 identical (from 256), 0 different.
- Text views (round 51, `text-view-*`): plain and attributed text, input traits, data detectors,
  no clipping without scrolling. Outlets of one name to one object from objects of different
  classes are refused: pocket-casts' SharePublishViewController orders its three `delegate`
  outlets otherwise. Corpus 256 identical, 0 different.
- Image views' accessibility sizing (round 49) and gesture recognizers in xibs (round 50,
  `gesture-*`). B-290 stays refused (16 corpus documents): no model fits the observed order.
- Collection views in storyboards (round 48, `sb-collection-*`): prototypes' nil delegate, prototype
  cells as nested nibs. Corpus 252 identical (from 244).
- Round 47: restoration identifiers on views and table cells, cells' `opaque`, `<customFonts>`
  (`UIAppFonts` in the partial Info.plist). Corpus 244 identical (from 229).
- View controllers' attributes in storyboards (round 46, `sb-vc-*`): title, restoration identifier,
  presentation and transition styles, bars, insets; segue templates' strings from the document's
  pool. Corpus 184 identical (from 182).
- Collection views in xibs (round 45, `collection-*`): flow and custom layouts, the white
  background rule, automatic estimated sizes. Corpus 182 identical (from 179).
- Fixes before buttons' and segmented controls' actions go live (found by the first agent with
  actions enabled): segments 32 high whatever the control (`segmented-height-*`), sibling
  constraints among safe-area constraints (`sib-safe-*`), safe area guides sharing their identifier
  strings, accessibility configurations in archive order, and runtime attributes of several objects
  past the 9th refused (B-290: the order rule of rounds 41–43 did not hold for wikipedia's
  ArticlePopoverViewController). With the first agent's actions merged locally and button and
  segmented actions enabled: corpus 220 identical, 0 different; experiments 2390, 0 different.
- Rounds 41 to 43: designables (no change), symbolic constraints' constants (not written), margin
  constraints' legacy constants from the item's own layout margins, and the order of runtime
  attribute pairs (places 0–2, 9–38, then 3–8; B-290 past 38). Corpus 182 identical (from 169).
- Accessibility configurations (round 40, `a11y-*`, `sb-a11y`) on views of every kind.
- User-defined runtime attributes (round 39, `udra-*`, `sb-udra`) on views and File's Owner, and
  the encoder's rule that equal `NSNumber`s are one object. Corpus 163 identical (from 157).
- Visual effect views (round 38, `effect-*`): blur styles, the content view. Corpus 157 identical
  (their documents stop at other features).
- Round 37: `customObjectInstantitationMethod="direct"` and storyboards' inferred metrics tie
  breakers (no change), safe areas of subviews, the older cell template's ignored
  `insetsLayoutMarginsFromSafeArea`. Corpus 157 identical.
- Activity indicators, segmented controls, progress views, page controls, sliders (round 36,
  `activity-*`, `segmented-*`, `progress-*`, `page-*`, `slider-*`): per-class hugging defaults,
  segments as subviews, progress heights. Corpus 156 identical (from 153).
- Collection view cells and reusable views in xibs (round 35, `cvcell-*`, `reusable-*`): both
  content view templates, IB's generated constraints, cell constraints moved to the older
  template's content view. Corpus 153 identical (from 145).
- Stack views (round 33, `stack-*`, `sb-stack`), layout margins on every view (`view-margins-*`,
  with the margin keys in ibtool's order: the preserves keys come before
  `UIViewInsetsLayoutMarginsFromSafeArea`, which nomac had reversed: `view-insets-preserves`),
  custom classes on labels and image views (`label-custom-class*`), scroll views (round 34,
  `scroll-*`, `sb-scroll`). Experiments 2081 identical, corpus 145 identical (from 117).
- Buttons (round 32, `button-*`, `sb-button*`, `view-tint-*`, `image-view-symbol`): control and
  button keys, state content by state, default fonts by type, insets, image-only types, SF
  Symbol placeholders, tint colors on every view. Experiments 1985 identical (from 1895), corpus
  117 identical (from 116). Buttons' actions wait for the first agent's control actions; button
  configurations (13 corpus buttons) are refused.

Next actions:
1. Collection views (and their prototype cells in storyboards), date pickers, each by experiment
   first, then the corpus (`rank2.py`, `runtasks.py`).
2. Constraints to scroll views' content and frame layout guides (`scroll-content-guides-pinned`).
3. Button configurations; `<imageReference>` and `<preferredSymbolConfiguration>` in states.

## How to reproduce

```sh
# On the Mac (Xcode 27.0): observations of self-written inputs and corpus files (outside the repo)
export DEVELOPER_DIR=/Applications/Xcode_27.app/Contents/Developer
python3 .github/scripts/strings_experiments.py ~/nomac-out/wt-scratch/nibs/strings
python3 .github/scripts/coredata_experiments.py ~/nomac-out/wt-scratch/nibs/coredata
python3 .github/scripts/nib_experiments.py ~/nomac-out/wt-scratch/nibs/nib
# Anywhere nomac runs: compare (corpus files need the checkouts at /tmp/nomac-corpus)
python3 .github/scripts/strings_compare.py ~/nomac-out/wt-scratch/nibs/strings .build/debug/nomac
python3 .github/scripts/coredata_dictionaries.py ~/nomac-out/wt-scratch/nibs/coredata
python3 .github/scripts/nib_compare.py ~/nomac-out/wt-scratch/nibs/nib .build/debug/nomac
```

Scratch oracles (outside the repository, reusable; `~/nomac-out/wt-scratch/nibs/images/`):

- `tasks.py` writes `tasks.json`, every ibtool task of the reference builds' logs
  (`~/nomac-out/reference/<app>/build/build.log`); `runtasks.py <nomac>` reruns the compilations
  with their options, prints the first refusals by count and compares compiled outputs with the
  reference intermediates; `linktasks.py <nomac>` does the same for the links.
- `rank.py`: which unsupported element sets block the tasks' documents.
- `expdiff.sh <experiment>` and `corpusdiff.sh <document>`: Xcode's nib against nomac's,
  decoded by `../nibarchive.py`; `dumpexp.py <experiment> [classes]`, `objdump.py`,
  `fontfields.py`: read recorded nibs.
- Constraint order: `corder.py` (matches the corpus nibs' constraint lists with their documents),
  `model3.py` (the sort model), `order_experiments.py` (scratch experiments behind round 15).

