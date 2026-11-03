# ADR 0012: Each nomac release reproduces one Xcode build

- Status: accepted. The owner decided on 2026-10-22 that each nomac release reproduces one Xcode
  build, that outputs carry its version strings, and that a Linux machine records the reference
  Mac (decisions 2 to 5 follow from them), and confirmed decision 1's version scheme on
  2026-11-02.
- Date: 2026-10-22

## Context

nomac's outputs are meant to equal one Xcode's. Every rule it applies was observed with Xcode
27.0 (27A266a), and some of its outputs carry that Xcode's identity outright: the Info.plist keys
`DTXcode`, `DTXcodeBuild`, `DTCompiler`, `DTPlatformBuild`, `DTSDKBuild` and `BuildMachineOSBuild`,
the version strings in an `Assets.car` header, `actool-25098` in actool's dependency info, and the
answers to Swift Build's tool probes (ADR 0102). The owner decided on 2026-10-22 that outputs are
identical to Xcode's, these version strings included.

Until now nothing said so where a user or a contributor would look:

- `nomac --version` printed `0.0.1`, and nothing checked which Xcode a developer directory held:
  a user with Xcode 27.1 got 27.0's rules without a word.
- The values that change with Xcode were spread over the code: the Swift Build and SwiftPM pins
  (Package.swift, ADR 0005, ADR 0010), actool's and ibtool's versions (`Actool`, `IBToolVersion`),
  the `Assets.car` strings (`CARToolVersions`), the Mac's answers to manifest conditions
  (`HostConditions.mac`), the `objectVersion`s Xcode reads, the swift.org and llvm-project tags
  (ADR 0100, ADR 0102, `build-llvm-tools.sh`), the corpus's Xcode (`corpus/corpus.json`).
- Moving to Xcode 27.1 (B-013) meant finding each of them, and re-running every experiment and
  capture by hand to learn which rules changed.
- A Linux machine has no Mac identity to record in `BuildMachineOSBuild` (B-060).

## Decision

1. **One Xcode build per release.** Each nomac release reproduces exactly one Xcode build. Its
   version is `<Xcode major>.<Xcode minor>.<N>`: the Xcode's major and minor version, then nomac's
   own release counter for that Xcode, starting at 1 (`NomacVersion.current`, the one constant that
   spells the scheme, so the owner's answer changes one line). `nomac --version` prints
   `nomac 27.0.1 (Xcode 27.0, 27A266a)`. The counter restarts at 1 when the Xcode's major or minor
   version changes, and keeps counting when the Xcode changes build within them (an Xcode 27.0.1,
   or 27.0 re-released with another build): nomac 27.0.4 may reproduce Xcode 27.0.1, and the build
   in parentheses says which. Milestone tags follow the version (`v27.0.N[-label]`, ADR 0007's
   format); `v0.1.0-loader` stays as it is.
2. **The Xcode is checked.** `nomac sdk install`, `nomac sdk link` and every command that takes
   `--developer-dir` (`build`, `inspect`, `list`, `pif`, `verify`, `toolchain install`; also when
   the developer directory comes from `$NOMAC_DEVELOPER_DIR` or the selected install) read the
   Xcode's `version.plist`. Any `ProductBuildVersion` other than the profile's, or none, prints a
   warning naming both Xcodes; with `--strict-xcode` it is an error (`XcodeBuildCheck`), before a
   command evaluates anything and before `sdk install` copies the subset. An `Xcode.app` is checked
   before anything is copied; a `.xip` holds its `version.plist` inside the archive, so unxip
   expands all of it first (Xcode-sized, into `$NOMAC_HOME/xcode/.expand-*`), and the refusal then
   removes the expanded files. `nomac doctor` marks installed builds that are not the profile's.
   A warning, not an error, by default: loading projects and evaluating settings mostly work with
   a nearby Xcode, and a user should be able to try; only the profile's build is promised Xcode's
   outputs.
3. **One Xcode profile.** `XcodeProfile.current` (`Sources/NomacCore/XcodeProfile.swift`) holds
   every value nomac takes from its Xcode, each with where it was observed:

   | Entry | Values for 27.0 | Read by |
   |---|---|---|
   | `xcode` | 27.0, 27A266a, `XCODE_VERSION_ACTUAL` 2700 | `NomacVersion`, `XcodeBuildCheck`, help texts |
   | `pins` | Swift Build's repository (the owner's fork, ADR 0005) and revision `d1842806` (`2d847030` with the upstream patches), SwiftPM `8054c59f`, the PIF builder's tag `swift-6.4.1-RELEASE`, the swift.org toolchain and llvm-project tag `swift-6.4.0-RELEASE` | XcodeProfileTests (against Package.swift, Package.resolved, UPSTREAM.md, build-llvm-tools.sh), `nomac toolchain install`'s help |
   | `actool`, `ibtool` | bundle version 25098, short version 27.0 | `IBToolVersion` (NomacNib), `ActoolVersions` (NomacAssets) |
   | `assetCatalog` | CoreUI 1010, its version string, `Xcode 27.0 (27A266a) via AssetCatalogAgent-AssetRuntime`, the authoring-tool string | `ActoolVersions` (NomacAssets): the `CARHEADER` and `EXTENDED_METADATA` strings |
   | `sdks` | the ten SDKs of `xcodebuild -showsdks` with versions and builds (iphoneos27.0, 24A430, …) | the upgrade harness |
   | `referenceMac` | macOS 27.0.1, 26A434, arm64 (the corpus references' `host.json`) | `HostIdentity.default()` (NomacBuildService): `inspect`, `list` |
   | `infoPlist` | the `DT*` keys and `BuildMachineOSBuild` of an iOS device build | XcodeProfileTests (against `xcode`, `sdks`, `referenceMac`), the upgrade harness |
   | `xcodeTools` | Xcode's `swiftc`, `clang`, clang's linker version 1166.2, `ld` 27037.1, `tapi`: never written by nomac (ADR 0101), recorded so an upgrade sees them change | the upgrade harness |
   | `manifestHostConditions` | the Mac's answers to manifest conditions (`os`, `arch`, `canImport`, …) | `HostConditions.mac` (NomacPackages) |
   | `readableObjectVersions` | 42–56, 60, 63, 70–77, 90, 100, 110 | `readableObjectVersions` (NomacProject) |

   `nomac sdk profile` prints it as JSON. The values that cannot live in Swift (SwiftPM reads its
   pins from Package.swift and Package.resolved, the scripts read `corpus/corpus.json`,
   `build-llvm-tools.sh` its default tag) are checked against the profile by `XcodeProfileTests`,
   so an upgrade that changes one place and not the other fails the test suite.
4. **The Mac a Linux machine records** (B-060) is the profile's `referenceMac`, the Mac of this
   Xcode's reference captures: off macOS, `HostIdentity.default()` is the current user and
   environment on that Mac, which gives Swift Build `BuildMachineOSBuild` and the `MAC_OS_X_*`
   settings as the reference Mac. `--host-identity <host.json>` names another. On macOS the
   machine is itself.
5. **Upgrades are re-observation.** `.github/scripts/xcode_upgrade.py` reruns, with a new Xcode,
   the experiment suites that observe Xcode (every `*_experiments.py` but shell_experiments.py,
   which observes macOS's `/bin/sh`; pif_stability.py clones an app and is run by hand), the
   corpus captures, the fuzzer's seeds and the coverage survey, probes
   every profile value, and reports what differs from the current Xcode's runs: the profile values
   to update, the experiments whose outputs changed with the tests and docs that cite them, the
   references and fuzz cases that changed. The procedure is docs/UPGRADING.md.

## Alternatives considered

- **SemVer with the Xcode as build metadata** (`0.4.0+27A266a`). SemVer ignores build metadata
  for precedence, and many tools drop it (SwiftPM's version requirements, package managers);
  `0.4.0` alone would not say which Xcode, and nomac's major version would mean little, since what
  breaks the promise of identical outputs is a new Xcode, not a change of nomac's interface.
- **nomac's own SemVer and a compatibility table** (the usual way for tools that follow another
  product): a lookup for every user, for a relation that is one to one.
- **Four components, `27.0.0.N`** (Xcode's full version, then the counter): unambiguous across
  Xcode's patch releases, but not a three-part version (ADR 0007's tags, SwiftPM).
- **The Xcode build as the version** (`27A266a.N`): exact, but not ordered like a version.
- **One release for several Xcodes** (a profile per build, chosen by the developer directory's
  `version.plist`; B-013 planned "support both"): every rule would need observations and tests per
  Xcode, and a build nobody re-observed would still get guesses. The previous release stays
  available for the previous Xcode.
- **Where the profile lives.** A JSON resource read at run time adds a bundle to the install
  layout and fails only when run; a JSON file turned into Swift by a build-tool plugin adds a
  plugin to build on both platforms for about a hundred values. A Swift file is typed and compiled,
  scripts read it through `nomac sdk profile`, and the few pins outside it are tested against it.

## Consequences

- An upgrade changes `XcodeProfile.swift`, the pins the tests point to, the rules whose
  experiments changed, and the release counter in `NomacVersion.current` (back to 1 for a new
  major or minor version, one up for another build of the same, as decision 1 says);
  docs/UPGRADING.md lists each step.
- NomacBuild, being changed on the build driver's branch when this landed, reads the profile
  later: `nomac build`'s default Mac (B-060) and `nomac toolchain install`'s check of the
  swift.org release (B-096).
- References (ADR 0004) and the envelope (ADR 0011) were already per Xcode build; this ADR makes
  nomac itself so.
- With another Xcode, the `DT*` keys Swift Build writes name that Xcode (they come from its
  developer directory), while nomac's reimplemented tools still write the profile's identity; the
  warning says outputs may differ.
