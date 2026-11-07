# Wild sample: state

Workstream: how many open-source iOS projects really build with nomac, measured by building them.
The coverage survey (`feature_survey.py`) only reads projects; this builds a seeded sample of what
it read, end to end on Linux, without changing a project, and gives every failure a verdict: nomac's
fault, the project's own, or not known. Branch `corpus/wild-sample`. BACKLOG B-500–B-509, ADRs
0500–0509.

## Current step

Sample picked, container set up. `wild_sample.py run` works in the container `nomac-wild-run`
(volume `nomac-wild`, nomac `efb6f387`), log `~/nomac-out/wild-sample/run.log`, results
`~/nomac-out/wild-sample/results`, one project at a time. No project's result is in the repository
yet; docs/PROGRESS.md gets the number when the projects have run.

Next actions:

1. `docker exec -u builder -e HOME=/work/home -e PATH=/work/home/.local/bin:/usr/local/bin:/usr/bin:/bin nomac-wild-run python3 -I /src-host/.github/scripts/wild_sample.py triage --root /out`
   prints each stopped project's first errors. Give each a verdict in `corpus/wild-sample.json`
   (`verdicts`: `verdict` nomac, project, unknown, not-ios or no-app; `class`; `xcode`).
2. For failures where Xcode's behavior decides the verdict, `wild_sample.py xcode <project>` on the
   Mac builds the same commit under Xcode 27.0. Project scripts run in a sandbox that denies the
   network during the build and reads of credentials throughout (`mac_sandbox`).
3. `wild_sample.py report --root /out --write` gives the numbers for docs/PROGRESS.md.

## How to rerun

```sh
wild_sample.py pick --survey ~/nomac-out/survey-20261106   # the seeded sample, corpus/wild-sample.json
docker run -d --name nomac-wild-run --cpus 8 --ulimit nofile=65536:65536 -v nomac-wild:/work \
    -v nomac-build:/ref:ro -v <worktree>:/src-host:ro -v ~/nomac-out/wild-sample:/out \
    nomac-linux:6.4.1-noble sleep infinity
```

In the container, as a normal user whose home is `/work/home`: nomac linked at `~/.local/bin/nomac`,
`nomac sdk install` and `nomac toolchain install` as docs/INSTALL.md says, CocoaPods and Node
installed, then `wild_sample.py run --root /out`: one project at a time. A run leaves out projects
that finished, and takes again those the network cut short (`notMeasured`), which count nowhere.

Use a subset fresh from `nomac sdk install`: on 2026-11-07 `/ref/xcode` held 10,048 files and a fresh
subset 61,187. What `/ref/xcode` lacks is 42,014 files of the macOS platform, 7,492 of the watchOS
platform and 1,586 of the toolchain folder; of the iOS platform only `device_traits.db`.

## Findings outside the build

The survey read 18 of the 133 projects it calls clear through a package's or a playground's
workspace (`.swiftpm/xcode/package.xcworkspace`, 13; `*.playground/playground.xcworkspace`, 5),
not the project a developer opens, and 24 of the 133 have no application target in what it read. So
the "nothing may stop a build" share overstates apps: of the 1,328 projects read, 109 are clear and
have an application target in what was read, not 133.
`entry_container` should leave those folders out (`EXCLUDED_DIRECTORIES`).
