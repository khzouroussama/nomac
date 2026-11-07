# Progress, measured

Every number here comes from real open-source apps: nomac's output for an app is compared with
Xcode 27.0's output for the same app (docs/VERIFICATION.md). A total counts what those apps
contain, not everything Xcode can do. Where nomac meets something it has not matched to Xcode's
behavior yet, it stops with a message rather than guessing (`nomac check` lists those things
before a build).

The README shows these as bars; this page has the dates and sources.

## Apps nomac was never developed against

These say the most about an app nomac has not seen.

| Set | What is counted | Result | Measured |
|---|---|---|---|
| React Native and Expo sweep: 106 public Expo examples and open-source apps, unmodified (corpus/rn-sweep.json) | Install, `nomac check`, build, archive and export an IPA on Linux | Partial: round 2 stopped at 61 of the 106 apps. 49 reach an IPA; 8 stop on the app's own errors; 3 stop at the build (a compile error, a nomac refusal, a tool without that Linux subcommand); 1 did not install. | 2026-11-03, `.github/scripts/rn_sweep.py`, nomac a9b571ab and ad202e5b; docs/state/rn-sweep.md |
| Holdout: 19 open-source apps never used for development | Project loading: the PIF, `-list` and every build setting as Xcode 27.0 gives them | 19 of 19 apps identical; 3,509 of 3,514 settings identical, the other 5 equivalent (B-015) | 2026-11-03, docs/state/loader.md |

## The 20 apps nomac was developed against (corpus/)

| Area | What is counted | Result | Measured |
|---|---|---|---|
| Whole apps | Apps whose every build check passes on Linux | 2 of 20 (Retro Rampage, Flappy Fly Bird) | 2026-11-02, corpus/RESULTS.md |
| Project loading | Apps whose PIF, `-list` and every build setting are Xcode's | 19 of 19 measured; signal not measured yet (its Xcode reference waits on the Metal Toolchain). corpus/RESULTS.md's 17 of 20 predates the B-098 references. | 2026-11-03, main d71f3a75, docs/state/loader.md |
| Build | Build products the same as Xcode's (compiled code counts when equivalent, ADR 0101), on Linux | 929 of 1,198, in 16 apps | 2026-11-02 |
| Storyboards and xibs | Documents in the 20 apps | 476 of 588: 462 identical to ibtool's, 14 equivalent, 0 different, 112 refused | 2026-11-07, `res/nibs` 7259a137, `nib_compare.py` |
| | Documents in the 20 apps and the holdout that compile | 759 of 1,065 | 2026-11-07, `res/nibs` 7259a137 |
| | `nomac verify`'s nib checks | 271 of 485, in 15 apps | 2026-11-02 |
| Asset catalogs | `nomac verify`'s catalog checks | 54 of 99, in 18 apps | 2026-11-02 |
| | Image sets drawn from PDFs | 1,328 of 1,535 the same as Xcode's (5 identical, the rest with rendered pixels judged equivalent, ADR 0204), 201 different, 6 refused | 2026-11-03, assets/pdf-10, docs/state/assets-pdf.md |
| Strings | `.strings`, `.stringsdict` and `.xcstrings` checks | 3,022 of 3,022, in 13 apps | 2026-11-02 |
| Core Data | Models and mapping models | 11 of 11 checks, in 5 apps | 2026-11-02 |
| Signing and export | Code signatures and exported IPAs, ad hoc and development only | 12 of 12 checks, in 4 apps | 2026-11-02 |
| Tests on a device | Apps whose tests pass on an iPhone | 0 of 20 | 2026-11-02 |

Outside the corpus, `nomac test` ran a self-written app's hosted unit-test bundle on an iPhone
from Linux: 2 tests, 0 failures, `** TEST EXECUTE SUCCEEDED **` (2026-11-03, docs/state/device.md).
UI tests have not run yet.

Rows dated 2026-11-02 are older than a day and have not been measured again.

Outside the corpus: an iPhone (iOS 27.0.1) installed and launched two apps nomac built and signed
on Linux, through a Mac's usbmuxd forwarded into a Linux container (docs/state/device.md);
`nomac upload` has not uploaded to App Store Connect yet (docs/state/distribution.md).

## Not supported yet

The tables above count what is measured, so they do not show these. BACKLOG numbers are in
docs/BACKLOG.md.

| What | State | BACKLOG |
|---|---|---|
| Metal shaders | No open-source compiler writes AIR or metallib files; `nomac check` reports `metal:shader` | B-241 |
| Core ML pipelines and tree ensembles; neural networks | Refused, not observed yet; neural networks need a translation per layer | B-240; B-242 |
| Simulator, macOS, tvOS and visionOS builds | `-destination` takes `generic/platform=iOS` only | B-066, B-206 |
| watchOS | Only as a watch app inside an iOS app, with parts verified (signing, catalogs, thinning) | B-206, B-465 |
| Distribution signing for the App Store and TestFlight | With an identity, `nomac export` refuses all but development exports; no distribution signature has been observed | B-302, B-460 |
| A real upload | `nomac upload` is tested against scripted answers; nothing has been sent to Apple | B-463 |
| UI tests on a device | The UI test runner is not signed yet | B-302 |
| `.xcresult`, coverage and test plans on a device | `.xcresult` is the device workstream's next action; a scheme with coverage or a test plan is not taken yet | docs/state/device.md, B-433, B-434 |
| On-demand resources and other rare asset types | Not compiled yet | B-205, B-202 |

## Coverage survey

`nomac check` over 1,490 open-source apps (`feature_survey.py`): the share entirely inside what
nomac has verified. These are the last recorded numbers, from B-081 (2026-10-22). They predate this
week's work.

| Domain | Apps inside | 95% CI |
|---|---|---|
| Project loader | 83.6% | 81.6–85.4% |
| Asset catalogs | 99.3% | 98.7–99.6% |
| Signing | 1.9% | 1.4–2.8% |
| All domains | 1.9% | 1.4–2.8% |

## Differential fuzzer

Random projects read by Xcode 27.0 and by nomac, compared in full: `-dumpPIF`, `-list` and a sample
of `-showBuildSettings` (`fuzz_experiments.py`, docs/VERIFICATION.md). Every run uses seeds no
earlier run used, so progress isn't fitted to them. Generator 2 adds the shapes of real projects
that generator 1 never wrote, which is why the number falls between runs 1 and 2. "Equivalent"
cases differ only in outputs that xcodebuild itself changes from one run to the next.

| Run | nomac | Generator | Seeds | Projects | Identical | Equivalent | Different | Not compared |
|---|---|---|---|---|---|---|---|---|
| Last before this table | `e7e8a13` | 1 | 50000+ | 200 | 25 (12.5%) | counted as different | 175 | 0 |
| 1 | `efb6f387` | 1 | 300000+ | 55 (of 200; stopped to free CPU) | 51 (94.4% of 54 compared) | 2 | 1 | 1 (xcodebuild killed) |
| 2 | `efb6f387` | 2 | 400000+ | 51 (of 60; stopped to free CPU) | 39 (79.6% of 49 compared) | 1 | 9 | 2 (manifests Xcode rejected, a generator bug since fixed) |
| 3 (running; partial) | `loader/fuzz`, run 2's fixes | 2 | 500000+ | 17 of 100 so far | 16 | 0 | 1 | 0 |

## Generated by `nomac corpus results`

The section below is written from `nomac verify` reports
(`nomac corpus results --reports <dir> --update docs/PROGRESS.md --update docs/STATE.md`).

<!-- progress:begin -->
## Progress toward "any Xcode project builds on Linux"

Overall: 63% (weighted) · Corpus: 2 / 20 apps build on Linux (4 / 20 on the Mac with Xcode's compilers) · 0 / 20 pass their tests on device

- [ ] Project loader (xcodeproj, xcworkspace, xcconfig, schemes → PIF) · 85% · weight 20 · 17 / 20 apps
- [ ] Build driver (Swift Build on Linux, Swift/ObjC/C/C++, pods, SwiftPM, xcframeworks) · 77% · weight 25 · 929 / 1198 build checks on Linux in 16 apps · 21 / 21 on the Mac with Xcode's compilers, in 4 apps
- [ ] Asset catalogs (actool replacement, .car writer) · 54% · weight 10 · 54 / 99 assets checks in 18 apps
- [ ] Storyboards and xibs (ibtool replacement) · 55% · weight 10 · 271 / 485 nib checks in 15 apps
- [x] Strings and localization · 100% · weight 3 · 3022 / 3022 strings checks in 13 apps
- [x] Core Data models (momc replacement) · 100% · weight 4 · 11 / 11 coredata checks in 5 apps
- [x] Packaging and signing (IPA, entitlements, dSYM) · 100% · weight 8 · 12 / 12 signing and export checks in 4 apps
- [ ] Extensions, App Clips, widgets, watch targets · 0% · weight 5 · no check kind yet
- [ ] Device workflow (install, launch, XCTest on device) · 0% · weight 6 · no check kind yet
- [ ] Distribution (TestFlight, App Store Connect) · 0% · weight 3 · no check kind yet
- [ ] Rare file types (intents, SceneKit, texture atlases) · 0% · weight 2 · no check kind yet
- [ ] Metal and CoreML (Wine-hosted tools, runtime fallbacks) · 0% · weight 2 · no check kind yet
- [ ] Verification harness (corpus, macOS reference builds, nomac verify) · 90% · weight 2 · 18 / 20 apps verified

Last updated: 2026-11-02 · Full per-app results: corpus/RESULTS.md
<!-- progress:end -->

Deferred work, with reasons, is in docs/BACKLOG.md; the current step and the workstreams are in
docs/STATE.md.
