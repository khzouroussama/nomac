# Wild sample: state

Workstream: how many open-source iOS projects really build with nomac, measured by building them.
The coverage survey (`feature_survey.py`) only reads projects; this builds a seeded sample of what
it read, end to end on Linux, without changing a project, and gives every failure a verdict: nomac's
fault, the project's own, or not known. Branch `corpus/wild-sample`. BACKLOG B-500–B-509, ADRs
0500–0509.

## Current step

A detached run started on 2026-11-07 at 03:52 on the Mac's clock (the logs' times are UTC, an hour
behind), nomac `efb6f387`, in the container `nomac-wild-run` (volume `nomac-wild`). It takes the 48 projects of `corpus/wild-sample.json` one at a time, in four
rounds at most, 20 minutes apart, and nothing needs to watch it. It runs from a frozen copy of the
script and manifest in `/work/driver`, so a change to this branch or worktree does not reach it.

No result is in docs/PROGRESS.md: a number goes there only after someone has read the results and
given the failures their verdicts.

## Where to look

All on the Mac, under `~/nomac-out/wild-sample`, and in the container under `/out`:

| File | What it holds |
|---|---|
| `results.log` | One line per attempt: time, project, frames, seconds, nomac, then `IPA`, `stopped at <step>` (with what is known), `not-measured: <reason>` or `no-app`. The last attempt at a project counts. The last line starts with `END` when the run has finished. |
| `STOPPED` | Exists only if the run ended itself, and says why: the Mac under 15 GB free, or the preflight failed. |
| `run.log` | The driver's own lines: rounds, retries, waits for disk. |
| `tools.log` | Ruby, CocoaPods and Node being installed, each `ready` or `NOT installed`. |
| `results/<owner>__<name>.json` | Each step's status, seconds and first errors. |
| `results/<owner>__<name>/` | That project's logs, gzipped, and `check.json`. Never in the repository. |

To see whether it is alive: `docker exec nomac-wild-run pgrep -af wild_sample.py`.

## How to read the results

From a worktree of this branch or of main, on the Mac:

```sh
python3 -I .github/scripts/wild_sample.py report   # shares with 95% CI, what is not measured, the bounds
python3 -I .github/scripts/wild_sample.py triage   # each stopped project's step and first errors
python3 -I .github/scripts/wild_sample.py classes  # the verdicts given so far, nomac's ranked by projects
```

Then:

1. Give each stopped project a verdict in `corpus/wild-sample.json`, under `verdicts`:
   `"owner/name": {"verdict": "nomac" | "project" | "unknown" | "not-ios", "class": "...", "xcode": "..."}`.
   Say `unknown` where nothing shows whether Xcode would fail too. `class` is a general name such as
   a refusal's BACKLOG number, never the project's contents.
2. Where Xcode's behavior decides the verdict, `wild_sample.py xcode <owner/name>` on the Mac builds
   the same commit under Xcode 27.0. The project's scripts run in a sandbox with no network during
   the build and no read access to credentials (`mac_sandbox`).
3. `wild_sample.py report --write` writes `corpus/wild-sample-results.json`: names, classes and counts
   only. Put the number in docs/PROGRESS.md stated as what was measured, with the date, the nomac
   commit, the interval and the not-measured count.

Read these with the numbers:

- Only what the network cut is not measured: an attempt whose reason reads `<step>: <message>`, or
  `GitHub did not answer`, and a project the run's own stop for disk ended. Those count in no share,
  and `report` prints their count and the worst-case bounds they leave. Every other failure counts as
  stopped until a verdict by hand moves it, so a share here errs low: `pod install` failing could be
  nomac's launchers. Labels say what is known: `stopped at install, cause not read`, `stopped at clone,
  cause not read`, `stopped at archive, timed out`, `stopped at install, this machine has no <tool>`.
  The driver takes the failed installs and clones again in later rounds.
- `immich-app/immich` needs Flutter and `flutter` is not installed, so it counts as stopped at install.
- `audiokit/AudioKit` has no app to archive and is left out of the shares (`noApp`).
- Each project's dependency commands, container and scheme come from reading its README, recorded
  in the manifest; a project without those keys uses what its files imply and its first app scheme.
- The two frames overlap: 12 of the 48 projects are in both, built once. Each frame is a simple
  random sample of its own population, and the manifest's order is random, so a partial run is still
  an unbiased subset.

## How to resume

If `results.log` has no `END` line and nothing is running (a Docker or Mac restart, or a stop for
disk), start the same driver again. It leaves out what was measured, takes the rest, and clears
leftover checkouts first. After a stop for disk, free the space and delete `STOPPED` first.

```sh
docker start nomac-wild-run
docker exec -d nomac-wild-run bash -c 'python3 -I /work/driver/.github/scripts/wild_sample.py tools >> /out/tools.log 2>&1'
docker exec -d -u builder -e HOME=/work/home -e PATH=/work/home/.local/bin:/usr/local/bin:/usr/bin:/bin -w /work \
    nomac-wild-run bash -c 'python3 -I /work/driver/.github/scripts/wild_sample.py run --root /out >> /out/run.log 2>&1'
```

Starting a run while one is alive would build two projects at once, so check first. To take one
project again, add its name after `run`. `--rounds 1` skips the waits between rounds.

When the results are read, free the disk: `docker rm -f nomac-wild-run`, `docker volume rm nomac-wild`,
then `~/nomac-out/wild-sample/xcode` and `~/nomac-out/wild-sample/scratch`, keeping `results`.

## How to rerun from nothing

```sh
wild_sample.py pick --survey ~/nomac-out/survey-20261106   # the seeded sample, corpus/wild-sample.json
docker run -d --name nomac-wild-run --cpus 8 --ulimit nofile=65536:65536 -v nomac-wild:/work \
    -v nomac-build:/ref:ro -v <worktree>:/src-host:ro -v ~/nomac-out/wild-sample:/out \
    nomac-linux:6.4.1-noble sleep infinity
```

In the container, as a normal user whose home is `/work/home`: nomac linked at `~/.local/bin/nomac`,
`nomac sdk install` and `nomac toolchain install` as docs/INSTALL.md says; then as root
`wild_sample.py tools`, and copy the three scripts and the manifest to `/work/driver` as above.

Use a subset fresh from `nomac sdk install`: on 2026-11-07 `/ref/xcode` held 10,048 files and a fresh
subset 61,187. What `/ref/xcode` lacks is 42,014 files of the macOS platform, 7,492 of the watchOS
platform, 1,586 of the toolchain folder and 46 under `Contents`; of the iOS platform only
`device_traits.db`. This run's subset is `/ref/xcode` with the fresh subset's other files added.
Those files, macOS last, were still being copied when the run began, so a project stopped by a
missing macOS SDK file in the first hour should be taken again.

Never kill a `tar` that is extracting into a developer directory. GNU tar writes each symlink as an
empty `0600` file and swaps in the links when it finishes, so a killed one leaves those files behind.
That happened here on 2026-11-07: `usr/lib/swift/clang` stayed an empty file, clang lost its resource
directory, and a one-line Swift file failed with `module '_c_standard_library_obsolete' requires
feature 'found_incompatible_headers__check_search_paths'`. So the first run's two projects were not
measured: their results are in `void-subset-1`, not `results`, and say nothing about nomac. The
preflight now catches this. After a killed copy, compare every path's type and size with the source.

## Findings outside the build

The survey read 18 of the 133 projects it calls clear through a package's or a playground's
workspace (`.swiftpm/xcode/package.xcworkspace`, 13; `*.playground/playground.xcworkspace`, 5),
not the project a developer opens, and 24 of the 133 have no application target in what it read. So
the "nothing may stop a build" share overstates apps: of the 1,328 projects read, 109 are clear and
have an application target in what was read, not 133. `entry_container` should leave those folders
out (`EXCLUDED_DIRECTORIES`); passed to loader/coverage on 2026-11-07.

## Not covered

No project had finished when this was written, so the driver has not yet carried a real project
through `nomac archive` and `nomac export`; `results.log` shows whether it did. A drill with a stand-in
for nomac and real clones from GitHub went through every other path: an IPA, a failed archive, a
missing tool, a failed install, a clone that fails, no app, and the second round taking only the not
measured. It left no run folder behind. A preflight that fails writes `STOPPED` and the next run
refuses to start. Not drilled: a stop for disk, an archive timeout, a resume.

The preflight compiles with `swiftc` directly, passing the `-fclang-abi-compat=4.0` that nomac passes,
and does not go through `nomac archive`. It shows the toolchain and SDK work, not that nomac does.
