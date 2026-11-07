# Cross-platform frameworks other than React Native: state

Workstream: each framework's fresh default app through nomac on Linux, with ad hoc signing and no
change to the app. Branch `corpus/frameworks`. BACKLOG B-510–B-519, ADRs 0510–0519. The results people
read are in docs/PROJECT-COMPATIBILITY.md, Part C; this file is how to carry on.

## Current step

Started 2026-11-07, on a machine at a load of 500 to 860 with GitHub and pub.dev timing out. No framework
has reached an IPA yet. See Part C for each one's last result.

## Next actions

1. Finish the runs in the order of `framework_apps.py`'s table: Flutter Debug, then Capacitor, Cordova, Kotlin
   Multiplatform, NativeScript, Tauri. One at a time (agent-common.md's CPU rule).
2. B-510: the owner decides where a Linux `gen_snapshot` comes from. Then run Flutter Release.
3. `nomac check` reporting Flutter's macOS-only compiler before a build: the change is written and waits to
   compile and pass `swift test --filter reportsFlutterBuildScripts`
   (`~/nomac-out/fw/flutter-check.patch`, plus a row for `build:script=flutter-gen-snapshot` in Part B of
   docs/PROJECT-COMPATIBILITY.md).
4. Repeat a whole-app failure on a fresh `nomac sdk install` before calling it nomac's: these runs used
   nomac-build's `/ref/devdir`, whose SDK subset agent-common.md calls stale.

## Reproduce

```sh
docker run -d --name nomac-frameworks --ulimit nofile=1048576:1048576 -v nomac-frameworks:/work \
    -v nomac-build:/ref:ro nomac-linux:6.4.1-noble sleep infinity
# in it: a Linux nomac at /work/bin/current/nomac, which is the path /ref/devdir's launchers name, and Node 24
export PATH=/work/node/bin:/work/bin/current:$PATH NOMAC_HOME=/work/nomac-home
export DEVELOPER_DIR=/ref/devdir/Xcode_27.app/Contents/Developer NOMAC_DEVELOPER_DIR=$DEVELOPER_DIR
python3 -I .github/scripts/framework_apps.py --work /work/fw --output /work/fw/results.json capacitor
```

`NOMAC_DEVELOPER_DIR` is what `nomac archive` reads. With `DEVELOPER_DIR` alone it stops with "no Xcode is
installed".

Flutter on a machine without `curl`, or with pub.dev down, needs its first run done by hand, which is what
`bin/internal/shared.sh` does: unzip `dart-sdk-linux-arm64.zip` of `bin/internal/engine.version` into
`bin/cache`, write that revision to `engine.stamp` and `engine-dart-sdk.stamp`, `dart pub get --offline` in
`packages/flutter_tools`, compile `flutter_tools.snapshot`, and write `<git HEAD>:` to `flutter_tools.stamp`.

## Facts

- Flutter 3.47.7's `flutter create` makes a Swift Package Manager project with no Podfile. Its Runner
  target links `FlutterGeneratedPluginSwiftPackage` from `ios/Flutter/ephemeral/Packages`, which
  `flutter pub get` writes, and its scheme has a build pre-action that runs `xcode_backend.sh prepare`.
- Release and Profile builds run `bin/cache/artifacts/engine/ios-release/gen_snapshot_arm64` (or
  `ios-profile`'s), a universal Mach-O. The tool's source shows no setting that names another one short of
  `LOCAL_ENGINE`.
- Debug and Profile builds run `plutil` in `embed_and_thin` to add `NSBonjourServices`. nomac has no `plutil`
  yet (B-190).
- `git clone` of a shallow checkout over a shared folder did not finish in 15 minutes at that load; a `tar`
  stream through `docker exec` took about 10.

## Not done

Running a Linux `gen_snapshot` was stopped twice by the session's permission system: the prebuilt one from
`xcross_gen_snapshot`, and the build from Dart's source through depot_tools. Neither has been run, so nothing
here says that either works. Both are B-510, for the owner.
