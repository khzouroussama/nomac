# Release preparation: state

Workstream: nomac's public releases, starting with an early preview. Announcing is the owner's.
Branch `release/prep`; BACKLOG
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

v27.0.3 is built by `release-tools` on the public repository for both architectures, reusing run
41841448959's tools (`tools_run_id`), and its release jobs attach the archives to the draft release
(`release_tag`). v27.0.2 has the arm64 download only; v27.0.1-preview stays, an older build.

1. Before publishing a release: install it with `curl | bash` on a fresh ubuntu:24.04 as a user
   with sudo, `nomac sdk install` a real Xcode_27.xip, `nomac toolchain install`, then archive and
   export a sample app and one with a Swift package from GitHub, on both architectures (x86_64
   under emulation on an arm64 Mac). Each of the first three of these runs on 2026-11-04 found a
   bug no earlier test had shown.

## Where development happens

Since 2026-11-04 the public repository, khzouroussama/nomac, is the only origin, as the owner asked
when it was published. Merges pass the gate and push its main as a fast-forward (docs/RELEASES.md).
nomac-dev is the private archive of the history before: public 18dfabb is nomac-dev e39a9bd5, and
public fdf254d0 is nomac-dev b406fe78, the last commit copied across. A branch still on that
history moves over by replaying its own commits (`git rebase --onto main <its base on nomac-dev>`).

## Reproduce

```sh
python3 .github/scripts/third_party_notices.py --check
NOMAC_LEAK_SCAN=<leak_scan.py> python3 .github/scripts/public_snapshot.py /tmp/snapshot --ref main
.github/scripts/package-toolchain.sh /ref/llvm-tools <llvm-project source> <swift source> /tmp/dist
```
