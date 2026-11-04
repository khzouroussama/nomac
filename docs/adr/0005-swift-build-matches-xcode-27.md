# ADR 0005: Pin Swift Build to the release/6.4.2 head, the behavior of Xcode 27.0

- Status: accepted (refines ADR 0002's Swift Build pin)
- Date: 2026-10-21

## Context

ADR 0002 pinned Swift Build to the `swift-6.4.1-RELEASE` tag, on the assumption that the tag
named after the Swift release paired with Xcode 27.0 is the Swift Build inside Xcode 27.0.

The first macOS verification (`reference` run 2, retro-rampage) compared nomac with
`xcodebuild -showBuildSettings` from Xcode 27.0 (27A266a). Out of about 593 settings per
target, these differed in every target:

| Setting | Xcode 27.0 | nomac on the 6.4.1 tag |
|---|---|---|
| `ARCH_COHORT_arm64e` | `arm64e arm64e.x1` | missing |
| `VALID_ARCHS` | `arm64 arm64e arm64e.x1 armv7 armv7s` | no `arm64e.x1` |
| `ENABLE_HARDWARE_CHECKED_POINTER_ARITHMETIC_SLICE` | `NO` | missing |
| `SKIP_COPYING_TEST_FRAMEWORKS` | `YES` | missing |
| `SWIFT_EMIT_CONST_VALUE_PROTOCOLS` | sorted, includes `AppUnionValue*` | unsorted hard-coded list |

All of these come from changes that are on `release/6.4.2` but not in the 6.4.1 tag: "Xcode 27
architecture and version updates", "Support for arm64e.x1", "Stop embedding testing frameworks
into build products", and "Move SWIFT_EMIT_CONST_VALUE_PROTOCOLS list into the toolchain".
The last one reads `usr/share/swift/SwiftConstantValues/*.json` from the Xcode toolchain.

## Decision

- Pin Swift Build to `2d847030c63961cb1cf8cbb6ad2bc7245fdfeb09`, the head of `release/6.4.2`
  on 2026-10-05.
- Since 2026-10-24 (the owner's decision), take that revision from the owner's fork,
  `https://github.com/khzouroussama/swift-build.git`, branch `release/6.4.2-linux-fixes`, at
  `2c105e3a95888becac2ba9f559eea91495c4691c`: the pin with exactly the eleven upstream patches of
  docs/upstream/swift-build.md (deterministic binary property lists, MD5, strings encodings,
  Mach-O parsing, the `derq` and `what` lookups, signature records, directory listings without AppleDouble files, Mach-O
  architecture names and static archives off Darwin, and binary targets' build files with
  platform filters), one commit each, until upstream merges them; the first three came at
  `8d0577c4` (2026-10-24), the fourth on 2026-10-30, the fifth and sixth on 2026-11-01, the
  seventh on 2026-11-02, the eighth and ninth on 2026-11-03, the tenth (`what`) the same day, the eleventh (signature records) on 2026-11-04. A further patch goes onto the fork the
  same way, written first as `.github/upstream/swift-build/<n>-*.patch`. The fork changes nothing
  on Darwin, so this decision's evidence, gathered on macOS, still holds.
- Keep `Toolchains/*.xctoolchain/usr/share/swift/SwiftConstantValues` in the `nomac sdk`
  subset (`XcodeSubset`), because a build setting is derived from it.
- From now on, the pin is chosen by evidence: the Swift Build revision is right when nomac's
  settings for the corpus match the reference Xcode's. A tag name is not evidence.

## Consequences

- Swift Build siblings (`swift-driver`, `swift-llbuild`, `swift-tools-protocols`) stay on the
  `release/6.4.x` revisions in `Package.resolved`. That branch is what `release/6.4.2` itself
  names as its related-dependencies branch.
- When the reference Xcode changes, the pin is re-derived by the same comparison.
- Task construction is evidence too (2026-10-22, B-115): Xcode 27.0 signed ad hoc without
  `--strip-disallowed-xattrs`, which the pin passes on macOS 14 and later (`0b7017c1`, merged
  into `release/6.4.2` by `96fbf769`). No upstream revision fits both observations: every
  revision with "Support for arm64e.x1" (`35984706`, the source of `ARCH_COHORT_arm64e`,
  `VALID_ARCHS` and `ENABLE_HARDWARE_CHECKED_POINTER_ARITHMETIC_SLICE` above) descends from
  `96fbf769`, on `release/6.4.2` and on `main` (`fa73f8e7`, 2026-10-21); the newest revision
  without `0b7017c1`, `3d8f3703`, has no `arm64e.x1`. The integrator decided on 2026-10-22 to
  keep the pin and accept the extra argument, the one known difference in task construction
  (B-115). A swift-build fork without `0b7017c1` would match both; publishing one is the owner's
  decision.
