# Release preparation: state

Workstream: nomac's first public release, an early preview. Nothing is published, pushed to a
new repository, tagged or announced until the owner says go. Branch `release/prep`; BACKLOG
B-070, B-074, B-079 (the numbers of B-070–B-079 never used in the history), ADRs 0070–0079.

## Current step

First batch: the tree's privacy and legal sweep, NOTICE, the release downloads' packaging, the
public snapshot script, CI for hosted Linux runners, and the README's install and quick start
as tested on a clean Ubuntu 24.04 container.

## Just finished

- Privacy and legal sweep of the tree at main `6bc9dca1`: the owner's leak scan (history and
  tree, 368 identifiers) finds nothing; no binary but the two logos; no Mach-O, archive,
  compiled resource or signing file; the vendored files keep their headers. Two tests named the
  owner's home folder; they use neutral paths now, one with a new observation.
- NOTICE (`third_party_notices.py`), `package-toolchain.sh` and docs/RELEASES.md,
  `public_snapshot.py`.

- The `release-tools` workflow for both architectures' downloads; `public_snapshot.py --onto`
  for later snapshots as fast-forward commits on the public main.

- `ci` green on nomac-dev's hosted runners, x86_64 and arm64 (2026-11-03, release/prep
  f8eab7dd): the one failure of the first run was a test expecting `/root` where a GitHub job
  container's `$HOME` is `/github/home`.

- The README rewritten short (status, diagram, labeled bars, commands, four-step install),
  with docs/PROGRESS.md, INSTALL.md, LEGAL.md, COMPARISON.md, CONTRIBUTING.md and AGENTS.md
  (CLAUDE.md imports it), and the release notes draft in docs/RELEASES.md.
- The release download is a prebuilt nomac (`--static-swift-stdlib`) with its resources and the
  tools, installed by `install.sh`; `nomac toolchain install` defaults to what it installed.
  `release-tools` run 41665929346 (nomac-dev, release/prep-2) built nomac statically on x86_64
  and arm64; its `release` jobs waited on tools not built yet.

## Next actions

1. When `release-tools` run 41661442245 (the tools, both architectures) finishes: dispatch
   `release-tools` with `tools_run_id=41661442245` on main; its `release` jobs assemble both
   archives and install each with install.sh on a fresh ubuntu:24.04 (installer packages only,
   no Swift 6.4.1). Check the result before publishing.
2. When docs/DEMO.md lands: the demo's numbers in the release notes, the snapshot and leak scan
   again, then the owner's go: `gh repo create khzouroussama/nomac --public`, push the snapshot as
   main, Linux CI there, `gh release create v27.0.1-preview` after CI is green, with both archives.
3. Later snapshots: `public_snapshot.py <dir> --ref main --onto https://github.com/khzouroussama/nomac.git`,
   then push main from `<dir>`.

## Reproduce

```sh
python3 .github/scripts/third_party_notices.py --check
NOMAC_LEAK_SCAN=<leak_scan.py> .github/scripts/public_snapshot.py /tmp/snapshot --ref main
.github/scripts/package-toolchain.sh /ref/llvm-tools <llvm-project source> <swift source> /tmp/dist
```
