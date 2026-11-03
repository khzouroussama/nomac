# Loader and envelope: state

Workstream: project loader, PIF, `-list`, `-showBuildSettings`, `nomac check` (the loader
domain) and the coverage survey. Branch `loader/envelope-12`. BACKLOG B-001–B-099, ADRs
0011–0099.

## Current step

The holdout (`~/nomac-out/holdout`, 19 apps, loader/envelope-11 83fcf9ac on main after
d0afd6be, 2026-11-03): 19 of 19 apps' PIF, `-list` and settings identical, 3509 of 3514
settings identical and vlc's 5 equivalent (B-015, the host apps xcodebuild orders differently
from one run to the next); tca fails to resolve its packages as Xcode does (exit 74, the same
message). The B-098 apps (mattermost, pocket-casts, firefox in Debug and the nine before) are
identical too, so neither set ranks a loader item. Holdout runs delete each app's DerivedData
folder after its report (`holdout/scripts/verify_snapshot_pruned.sh`): the references were
captured at Xcode's default DerivedData, whose paths the PIF and settings checks reproduce.

## Just finished

- B-098 apps after the swap, main d71f3a75: mattermost (1136 settings), pocket-casts (414) and
  firefox in Debug (640): PIF, `-list` and settings identical; their other differences are
  refused nib and asset checks. firefox's `nomac verify` had stopped at "could not launch
  ... Bad file descriptor": `Subprocess.run` left each run's pipes open until Foundation
  released them (2,210 open after about a thousand tool runs); it now closes them.
- B-062, by the owner's decision: builds keep the disk's spelling by default, a known difference
  `nomac build` warns about and `nomac verify` reports as equivalent (`swift.source-path-case`;
  cwa on Linux: ENA.swiftmodule equivalent, build checks 2/66 identical and 61 equivalent, was
  60); `nomac build --case-aliases` links the project's spelling into the checkout for the
  build (refused on a folder it cannot write, removed after a failed build too).
- B-065 without hints: the choice changes from the seventeenth scheme; rule not found yet.
- B-062: on a case-sensitive file system `nomac build` gives Swift Build file references spelled
  in another case by their path on disk (also B-075's normalization forms, any file reference)
  and clang and Swift a case-insensitive overlay (a called-out build-driver change). Linux
  corpus builds, this branch against the corpus agent's earlier reports: cwa no longer stops
  at "Build input files cannot be found", ENA compiles and links (executable equivalent; was
  missing), 2/66 identical and 60 equivalent build checks as before; moonlight's
  `openssl/*.h` errors are gone, Moonlight and libmoonlight-common build (executable
  equivalent; was missing). B-062 keeps the paths the compilers record (cwa's swiftsourceinfo).
- B-035, targets: a scheme named after targets of several projects records the others' as
  alternatives, and `nomac verify` calls a capture matching one of them equivalent
  (envelope-experiments `same-name-targets`: 2 of 2 cases, three runs); then a target and a
  local package's product with one name, and renamed schemes of several containers (B-065's
  run-to-run part), the same way. B-035 done.
- B-065, one project's shared and per-user pair: the scheme with the lower order hint in the
  user's `xcschememanagement.plist` wins, one with a hint over one without (`scheme-pairs-hints`
  and variants: 40 of 40 captures identical; without hints 6 of 8 per experiment differ, as
  before). B-065 keeps pairs without hints, whose choice depends on the other schemes.
- B-098 apps after the swap, main 159b2ae: gomap, icecubes, nextcloud, mastodon: PIF, `-list` and
  settings identical (52, 190, 104, 176 settings); their other differences are tool checks.
- B-009, loader side: a `plugin:` product dependency is the target's dependency on the plugin
  product, and local packages' plugin products and executable targets' implicit products have
  schemes (`build-tool-plugin`: PIF, `-list` and settings identical). B-009 stays for running
  plugins in `nomac build` (build driver).
- B-088: a project opened alone that assigns `SYMROOT` unconditionally anywhere keeps its own
  products, intermediates and precompiled headers folders with `-scheme`, caches in DerivedData
  (`symroot-targets`, `symroot-project-*`: 30 of 30 captures; envelope-experiments
  `unresolved-proxies` 40 of 40, `symroot-locations` 4 of 4); with `-derivedDataPath` too, and
  only the opened project's assignments count (`symroot-references-*`). B-088 done.
- B-089: a target whose `SDKROOT`, in the scheme's launch configuration, is a simulator SDK
  refuses a device destination (64) whatever its `SUPPORTED_PLATFORMS`; Xcode reads that
  `SDKROOT` from the levels itself, `[config=…]` applying only in xcconfig files and `[sdk=…]` to
  the target's own SDK (`simulator-sdks`, `simulator-sdk-conditions` and its `-project` variants:
  106 of 106 device-destination captures' exit status and settings as Xcode's; main d788db9d: 33
  differ). B-089 done; other condition parameters are `settings:SDKROOT=condition-other`.
- B-092: the rule for synchronized members (docs/formats/pif.md "Order in a phase", B-008) holds
  with build files whose reference is missing, which count in the modulus; nomac counted only the
  build files it writes (`dangling-synchronized` and variants, 281 phases: PIF identical; main
  differed in 54 and 90 phases of two). B-092 done.
- B-050: firefox's corpus build names a configuration its project lacks (`Fennec`), so packages
  and targets build into different products folders; corpus.json should say Debug.
- B-098: home-assistant, moonlight, cwa, netnewswire, kickstarter: PIF, `-list` and settings
  identical too.
- B-015, block order: an autocreated extension scheme with several host apps records them as
  unordered; `nomac verify` compares such a capture's blocks in the capture's order and calls it
  equivalent (vlc: 5 equivalent, exit 0). B-015 stays for the app such a scheme launches.
- The SDK subset keeps `usr/lib/swift/apinotes` (the build workstream's request).
- B-091: a storyboard missing from disk anywhere in the workspace gives every watch app
  `(Glance)` and `(Notification)` schemes (bisected from fuzzer seed 70155 by removing one
  project object at a time, then `watch-schemes-missing` and its variants; all 12 `-list`s
  identical, seed 70155's too).
- Outside the loader, as no packaging agent ran: `nomac export` leaves `embeddedBinaries` out
  for an app that embeds nothing, and exports apps signed with an empty entitlements
  dictionary (expo-default's archive); docs/state/packaging.md.
- The corpus and holdout checkouts in `/tmp`, which macOS's `tmp_cleaner` had emptied, cloned
  and prepared again, and kept by a LaunchAgent (docs/VERIFICATION.md "Without CI").
- PIF: an empty product name is the target's (`product-names-empty`); `-Owholemodule` split below
  objectVersion 50 (`swift-wholemodule*`); `migCodegenFiles` (`mig-codegen`); proxies into the
  project and stale remote IDs resolved by `remoteInfo` (`dependency-proxies`,
  `project-references-renamed`); the root group named after the project (`root-group-*`).
- Schemes: product schemes test nothing, and a root package's `<Product>Tests` gets no scheme
  (`root-package-references`); a watch app's `(Complication)` and `(Notification)` schemes
  (`watch-schemes`); a shared scheme named after a product leaves the product's scheme
  (`scheme-package-clashes`).
- Earlier on this branch (merged): B-036's unresolved-proxy GUID and `nomac verify`'s rehash,
  singular platform filters, the survey's per-domain coverage (loader 90.9% on main 8b4253c,
  integrator's run).

## Next actions

1. The survey's next loader features (`~/nomac-out/survey/SUMMARY.md`): `workspace:unreadable`,
   `fileEncoding=undefined` (a per-dump number), B-065.
2. Verify each B-098 app once the RN-holdout agent swaps it into `/tmp/nomac-corpus`.
3. B-065's shared and per-user pair without order hints.

## How to work

- Experiments: `.github/scripts/loader_experiments.py <out> <name>...` (Xcode's PIF and captures
  only; compare with `nomac pif <project> --output` on the same files written by the
  experiment's function) and `.github/scripts/envelope_experiments.py <out> <name> --nomac <bin>`
  (runs `nomac verify` per case; `--table` regenerates the envelope's experiment table).
- Corpus: `~/nomac-out/scripts/verify_all.sh <bin dir> <report dir> <apps>`; corpus table:
  `envelope_corpus.py --reports <dir> --checkouts /tmp/nomac-corpus`.
- Holdout: `nomac verify ~/nomac-out/holdout/reference/<app> --developer-dir "$DEVELOPER_DIR"`.
- Fuzzer: `fuzz_experiments.py run --no-minimize --cases 200 --start 70000 --out <dir> --nomac <bin>`
  (about 17 minutes); compare per seed with `~/nomac-out/fuzz-main-<commit>`. Seed 70199's `Kit`
  scheme capture is sometimes empty in xcodebuild (exit 0), which is not a nomac difference.
- Survey: `feature_survey.py check --out <dir> --nomac <bin>` with `repos` linked to
  `~/nomac-out/survey/repos` and its `contents.json` copied; the headline is the loader's.
- Copy each binary with its `SwiftBuild_*.bundle` to a scratch folder before long runs; delete
  only the DerivedData folders your xcodebuild runs create.
