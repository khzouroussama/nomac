# Differential fuzzer: state

Workstream: `.github/scripts/fuzz_experiments.py`, which compares nomac's reading of random projects
with Xcode's, and the loader fixes it leads to. Branch `loader/fuzz`, worktree
`~/nomac-out/wt/fuzz`. BACKLOG B-520–B-529, ADRs 0520–0529. The number per run is in docs/PROGRESS.md
"Differential fuzzer".

## Current step

Run 2's nine differences on generator 2 are fixed: PIF key order (5 projects), per-user build
locations (2), `wasCreatedForAppExtension` schemes (1), synchronized members' phases (1). All four of
the cases checked again are identical. That is fitted to those seeds: the number to publish comes
from run 3 on seeds 500000+.

Run 3 runs unattended: log `~/nomac-out/scratch-fuzz/run3-500000.log`, output
`~/nomac-out/scratch-fuzz/run3-500000`, binary `~/nomac-out/scratch-fuzz/bin-2`. When it has stopped,
`fuzz_experiments.py findings --out <output>` writes the ranking; add the row to docs/PROGRESS.md
and fix from the top. Delete `~/nomac-out/scratch-fuzz` when that is done.

When this was written it stood at 16 identical of 17, too few to publish as the number: replace
the partial row in docs/PROGRESS.md when it stops.

`~/nomac-out/scratch-fuzz/listcheck.log` compares `nomac list` with the references of the nine corpus
apps that have `wasCreatedForAppExtension` schemes, the check on that rule against real apps.
netnewswire and icecubes matched before this was written; read the rest, and fix the rule if any
app shows a scheme on one side only.

Next:
1. Run 1's seed 300048: xcodebuild fails with 64 on a scheme whose name a UI test bundle and a
   referenced project's framework share, nomac prints a block. `same-name-destinations` documents
   64 for two platforms; decide whether `nomac verify` treats this as equivalent.
2. loader/coverage's `list: scheme only in nomac (unit target)` on seeds 91000+, 1 of 20. Probably
   B-090 (which scheme tests a unit bundle changes from run to run); its case is gone, so wait for it
   to appear in a run here.
3. Generator 2 still leaves out `application.watchapp` and `watchkit-extension` (19 survey projects),
   `PBXTargetDependency.productRef` (24) and `XCSwiftPackageProductDependency` plugins (12).

## How to work

```sh
python3 .github/scripts/fuzz_experiments.py run --no-minimize --cases 200 --start <unseen seed> --jobs 2 --out <dir> --nomac <bin>
```

- Take seeds nothing has used: runs so far used 50000+, 70000+, 300000+, 400000+. A new seed range
  per batch, so that progress isn't fitted to the seeds.
- `--jobs 2`: at most two xcodebuilds at once on the shared Mac (~/nomac-out/agent-common.md), counting
  experiments.
- Copy the binary and its `SwiftBuild_*.bundle` to a scratch folder before a long run.
- A case takes 30 s on a quiet Mac and up to 6 minutes at load 400.
- Generator coverage: run `nomac check --json --description-only` on rendered specs and compare the
  feature names with `usage` in `~/nomac-out/survey/summary.json`. Generator 1 wrote 519 of the 1,179
  loader features real projects use, generator 2 723 or more.
- A difference only in shapes no real project has goes in B-520. Search the survey's repositories
  (`~/nomac-out/survey/repos`) before fixing a rare class.
