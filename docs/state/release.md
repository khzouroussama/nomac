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

v27.0.2 is the release with the arm64 download (v27.0.1-preview stays, an older build);
`install.sh` on x86_64 says its download comes later and points to the source build.

1. The x86_64 download (B-070). `release-tools` run 41694202819 (nomac-dev, release/prep-4, reusing
   run 41661442245's LLVM and cctools) did not make it: its x86_64 `swift-frontend` job reached the
   workflow's 355-minute limit and was cancelled, with no build error, so the `release` jobs were
   skipped. Setup took until 19:00 UTC, the LLVM tree until 23:56 UTC (3,915 steps, about 5 hours),
   and the Swift compile was at step 286 of 1,173 at 00:24 UTC. arm64's job finished in 4.5 hours.
   `build-swift-frontend.sh` now builds only the LLVM targets Swift's two targets take. The next
   run goes on the public repository, whose hosted runners have 4 vCPUs where nomac-dev's have 2;
   it cannot reuse nomac-dev's artifacts, so it builds LLVM and cctools too.
2. When the bundle exists: check its `release` job's install test, verify the `.sha256`, then
   `gh release upload v27.0.2` both files to the public repository. `install.sh` needs no
   change: it looks for the architecture's archive in the release.

## Continuous publishing

The public repository is khzouroussama/nomac (published on 2026-11-03 from nomac-dev e39a9bd5 as
public 18dfabb). nomac-dev keeps the full history and stays the development repository for now.

Phase 1 (running): every commit that lands on nomac-dev main goes to public main as its own
commit. `~/nomac-out/scripts/public_sync.sh`, run after each merge, keeps a map of nomac-dev
commits to public commits, gives each new nomac-dev commit's tree to `public_snapshot.py
--follow` (the snapshot's transforms: NOTICE written again, `.github/tags` without tag lines;
its checks; the commit's own message, author, committer and dates; nothing when the public
tree would not change), runs the leak scan over the result and pushes main as a fast-forward.
It never forces: when public main is not the last commit it published, it stops. A rerun
drops only unpushed local commits.

Phase 2 (planned): the public repository becomes the only origin.
1. Freeze merges for one round; run public_sync.sh so public main matches nomac-dev main.
2. Each agent rebases its branch once, from nomac-dev main onto public main: the trees are
   the same, so `git rebase --onto public/main <nomac-dev main> <branch>` replays only its own
   commits; history is never rewritten on public main.
3. The merge gate pushes to public main directly (fast-forward), with the leak scan of each
   push before it; public_sync.sh is retired.
4. nomac-dev stays read-only as the archive of the history before 2026-11-03.

## Reproduce

```sh
python3 .github/scripts/third_party_notices.py --check
NOMAC_LEAK_SCAN=<leak_scan.py> .github/scripts/public_snapshot.py /tmp/snapshot --ref main
.github/scripts/package-toolchain.sh /ref/llvm-tools <llvm-project source> <swift source> /tmp/dist
```
