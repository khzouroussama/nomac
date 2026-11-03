# Workstream: distribution

App Store and TestFlight from Linux: app-store-connect exports as Xcode makes them, distribution
signing, and the upload. Branch `dist/upload`; BACKLOG B-460–B-499, ADRs 0460–0499.

## Current step

`nomac upload` (ADR 0460, docs/formats/app-store-connect-upload.md) uploads an IPA through the
App Store Connect API's build uploads with an API key, tested up to the network; no upload has
run. Exports take profiles, options and app thinning as Xcode 27.0 does: `nomac export` thins
for all variants (apps declaring iOS 13.0 or later, catalogs by idiom and scale) and `nomac
assetutil` thins a catalog for one device as assetutil does.

## Just finished

- B-461: nomac checks a profile's CMS signature and its chain to Apple Root CA
  (`ProfileSignature`), as xcodebuild ignores profiles re-signed by a self-signed certificate, by
  a self-made chain with Apple's names, or changed after signing; the export reports Xcode's
  "No "<kind>" profiles … are installed", app ID and certificate errors for every bundle, the
  build (ManualSigning) Xcode's "No profile for team …", the same two errors per target and the
  refusal of a profile specifier on a target that takes none. `distribution_experiments.py
  compare`: 11 of 11 refusals identical. Tests sign their synthetic profiles with the self-made
  test chain (`SyntheticProfile.roots`).
- Export options (`option-grid`, `export-options`): which options each method keeps, always
  `stripSwiftSymbols` true (nothing is stripped either way), `TFInternalTestingOnly` in the app's
  Info.plist for `testFlightInternalTestingOnly`; app thinning refused (B-465). `compare-export`:
  the 50 new exports identical but the three thinning ones (refused), the packaging
  experiments' 57 still identical.
- Earlier: `nomac upload`, its spec check, and the first observations (self-signed identities and
  profiles are not installed, `generateAppStoreInformation` fails offline in an XPC helper,
  B-462). No archive or app-store-connect export of the signing experiments has BCSymbolMaps.

- B-466: an asset pack base URL given to app-store-connect is left out, `provisioningProfiles`
  with ad hoc signing kept (`option-archives`, identical in nomac); only the iCloud case, which
  needs an Apple-issued profile, is left.
- B-465 observed (`thinning`, docs/formats/ipa.md "App thinning"): the universal IPA is the plain
  export's; descriptors from the user's Xcode's `device_traits.db`, grouped by the traits the
  app's catalog depends on; each variant a thinned `Assets.car`, two Info.plist keys and a new
  app signature; UUIDs and descriptor order vary per run. Still refused: thinned catalogs are the
  assets workstream's CAR writer's to make, and an app without a catalog is the only case
  nomac could do alone.

- B-465, app thinning: `CARThinning` (assets module) edits an `Assets.car` as assetutil does,
  identical on 284 of 284 thinnings (`compare-car`: four catalogs, every iOS 18.0 trait set);
  `AppThinning` reads `device_traits.db` (kept by the `nomac sdk` subset since this change),
  groups descriptors by what the catalog keeps and writes the variants, `app-thinning.plist` and
  the report; `compare-thinning`: the adhoc app and the catalog copy identical (variants matched
  by descriptors), the iOS 12.0 copy refused. What is left is in B-465.

- B-465's refused shapes, ranked by the corpus (catalogs in extensions or frameworks: 11 of 19
  apps; minimums between the database's versions: 4; watch apps: 2; App Clips, packs, minimums
  below 13.0: none): catalogs of every bundle of code, minimums like 18.5, one-device thinning,
  App Clips, embedded packs and the report's byte, kilobyte and megabyte sizes now as Xcode
  writes them (`compare-thinning`: ten cases identical); watch apps observed and still refused.

- Watch apps in thinning (`thinning` `watch`, `watch-build`, `watch-catalog`, `watch-9`): watch
  variants by slice from the watchOS traits database, for watch apps declaring watchOS 9.0 or
  later, the slice cut from the archive's executable, the placeholder in the iPhone variants,
  the summary's three run-to-run forms; codesign seals a watchOS 11.0 bundle's files with SHA-1
  too (NomacSigning). `compare-thinning`: thirteen cases identical; the watch catalog case
  differs only in the trait set its watch catalogs are thinned for, which is still unknown
  (B-465).

## Next actions

1. Waiting on the owner: an App Store Connect API key and an app record for a self-written app,
   then the go-ahead for the first upload (B-463); an Apple Distribution certificate and App
   Store profile for distribution signing (B-460).
2. B-465: the trait set a group is thinned for (open for watch groups), then the other refused
   shapes when an app needs them.

## How to reproduce

```sh
export DEVELOPER_DIR=/Applications/Xcode_27.app/Contents/Developer
python3 .github/scripts/distribution_experiments.py ~/nomac-out/wt-scratch/dist/exp
python3 .github/scripts/distribution_experiments.py report ~/nomac-out/wt-scratch/dist/exp
# with the nomac development profile and identity (outputs private):
python3 .github/scripts/distribution_experiments.py compare ~/nomac-out/wt-scratch/dist/exp .build/debug/nomac
python3 .github/scripts/signing_experiments.py compare-export ~/nomac-out/wt-scratch/dist/exp .build/debug/nomac
python3 .github/scripts/distribution_experiments.py <private dir> apple-profile \
    --apple-profile <nomac_Development.mobileprovision> --identity <nomac-development.pem>
swift build && .build/debug/nomac upload <App.ipa> --dry-run
python3 .github/scripts/upload_spec_check.py .build/debug/nomac <App.ipa>
python3 .github/scripts/distribution_experiments.py ~/nomac-out/wt-scratch/dist/exp thinning car-thinning
python3 .github/scripts/distribution_experiments.py compare-car ~/nomac-out/wt-scratch/dist/exp .build/debug/nomac
python3 .github/scripts/distribution_experiments.py compare-thinning ~/nomac-out/wt-scratch/dist/exp .build/debug/nomac
```
