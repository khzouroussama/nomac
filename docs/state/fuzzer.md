# Differential fuzzer: state

Workstream: `.github/scripts/fuzz_experiments.py`, which compares nomac's reading of random projects
with Xcode's, and the loader fixes it leads to. Branch `loader/fuzz`, worktree
`~/nomac-out/wt/fuzz`. BACKLOG B-520–B-529, ADRs 0520–0529. The number per run is in docs/PROGRESS.md
"Differential fuzzer".

## Current step

Fixing generator 2's differences from the top of run 2's ranking (51 projects):

| Projects | Class | State |
|---|---|---|
| 5 | PIF key order: `PROVISIONING_PROFILE_SPECIFIER` beside `PROVISIONING_PROFILE[sdk=...]` | fixed |
| 2 | Per-user `BuildLocationStyle` and `DerivedDataLocationStyle` move the build folders | rule observed (`workspace-locations-*`), not in nomac yet |
| 1 | A shared scheme for a watch app: Xcode also lists an autocreated scheme of that name | not analysed |
| 1 | A `.vsh` synchronized member in no phase in Xcode, in Sources in nomac | `synchronized-phases-all` written |

Run 1's one difference (seed 300048: xcodebuild fails with 64 on a scheme whose name a UI test bundle
and a referenced project's framework share, nomac prints a block) is the known case of `same-name-destinations`.

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
