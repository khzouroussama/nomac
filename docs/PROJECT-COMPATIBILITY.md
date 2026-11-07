# Project compatibility: what nomac changes for you, and what you may have to change

nomac is a general runner for iOS projects on Linux, not an Expo or React Native tool. A project
written for a Mac can name macOS tools or test for macOS, and Linux cannot run those as they are.
A few such cases nomac handles itself, and it always tells you when it does (Part A). The rest are
your project's to change (Part B). Part C is how far other cross-platform frameworks' fresh apps have got.

## Part A: What nomac changes for you

These fixes apply only in Linux builds, never on a Mac. **None of them changes your files on disk.**

You can't miss them. Each fix prints a `note:` line when it applies, and the end of the build repeats
them in a short summary, even with `-quiet`:

```
note: nomac applied 3 project fixes to how this project's tools run; your files on disk are not changed:
note:   expo-autolinking-scan: expo-modules-autolinking/build/platforms/apple/apple.js changed in memory
note:   mach-o-tool-linux-build: HERMES_CLI_PATH is <app>/node_modules/hermes-compiler/hermesc/linux64-bin/hermesc (x86_64, through this machine's user-mode emulation)
note:   macro-plugin-from-package: ExpoModulesMacros built for this machine
note: what they do, what you may have to change yourself, and --no-project-fixes to turn them off: https://github.com/khzouroussama/nomac/blob/main/docs/PROJECT-COMPATIBILITY.md
```

`nomac check` lists the fixes that would apply to your project, in a section of their own. They are
not problems and do not change its exit status. `nomac check --json` has them under `projectFixes`.

**To turn them all off**, give a build `--no-project-fixes`. It then behaves as if the fixes did not
exist, and stops with the original error. There is no switch for a single fix, apart from the one
`mach-o-tool-linux-build` has below.

### `expo-autolinking-scan`: Expo's platform check accepts Linux

- **What it changes:** while your build's script phases run, Node reads one statement of
  `expo-modules-autolinking/build/platforms/apple/apple.js` differently:

  ```diff
  -    if (process.platform !== 'darwin') {
  +    if (process.platform !== 'darwin' && process.platform !== 'linux') {
  ```

- **How:** nomac adds a small script to `NODE_OPTIONS` in script phases, after any value you set, and
  that script changes the text in memory. Every other file loads as it is, and `process.platform`
  still says `linux`.
- **Why:** Expo's scan for `@ExpoModule` classes refuses every system but macOS, although Expo installs
  the scanner for Linux too. Without this, the build stops in `[Expo] Configure project`: "Scanning for
  @ExpoModule classes didn't complete". With it, `ExpoModulesProvider.swift` is the Mac's byte for byte.
- **When it goes away:** when Expo accepts Linux there. If the exact statement is not in the file, the
  fix does nothing. The statement is still there in `expo-modules-autolinking` 58.0.17.
- **Upstream issue:** none filed yet.
- **To turn it off:** `--no-project-fixes`.
- **Limits:** a script phase that sets `NODE_OPTIONS` itself, without keeping the value it had, drops
  the fix, and the build fails with Expo's own message. `nomac check` looks for the file only in the
  `node_modules` folders Node would search from your project's folder, so it can miss a nested copy;
  the build's `note:` is what counts.

### `mach-o-tool-linux-build`: a setting that names a macOS tool uses the Linux build beside it

- **What it changes:** when a build setting's value is a Mach-O executable, nomac looks in the folders
  beside that executable's folder for ELF executables of the same name. If exactly one fits this
  machine, the setting is overridden with it for the build. A build for this machine's own
  architecture comes first, then one the machine runs through user-mode emulation.
- **Example:** React Native's `HERMES_CLI_PATH` names
  `node_modules/hermes-compiler/hermesc/osx-bin/hermesc`, and the same package ships
  `linux64-bin/hermesc`.
- **Why:** Linux cannot run a macOS executable ("Exec format error"). The Hermes bytecode is the same.
- **On arm64 Linux:** `linux64-bin/hermesc` is x86_64 only, so it needs user-mode emulation. Docker
  Desktop has it; elsewhere install `qemu-user-static`. Without emulation the build, if it comes to run
  the tool, stops with an error that says this, instead of "Exec format error". A Debug build that never
  runs the tool is not stopped. `nomac check` reports it as your project's to fix (Part B).
- **When it goes away:** the rule is general, not tied to a release. It goes when no app nomac measures
  needs it.
- **Upstream issue:** none; shipping a macOS tool in a setting is how these packages work on a Mac.
- **To turn it off:** name the tool yourself, which always wins: `nomac build ...
  HERMES_CLI_PATH=<path>`, or `--no-project-fixes` for all the fixes. A value that a phase's own shell
  code sets, as in `ios/.xcode.env.local`, also wins.

### `macro-plugin-from-package`: a macOS macro plugin is built for this machine

- **What it changes:** when a project's flags load a Swift macro plugin that is a Mach-O executable
  (`-load-plugin-executable`), and a Swift package beside it declares that macro, nomac builds the
  plugin from the package into its own scratch folder, and the compiler loads that build first.
- **Example:** Expo's `ExpoModulesMacros`.
- **Why:** the compiler cannot run a macOS plugin on Linux. See
  [ADR 0151](adr/0151-macro-plugins-named-by-projects.md).
- **When it goes away:** the rule is general; it goes when no app nomac measures needs it.
- **Upstream issue:** none.
- **To turn it off:** `--no-project-fixes`.

### `sentry-auto-upload`: Sentry's bundling script runs without its upload

- **What it changes:** when a script phase runs `sentry-cli react-native xcode` from a script that reads
  `SENTRY_DISABLE_AUTO_UPLOAD`, as `@sentry/react-native`'s `sentry-xcode.sh` does, script phases run
  with `SENTRY_DISABLE_AUTO_UPLOAD=true`. The script then bundles the JavaScript itself.
- **What you should know:** this build uploads no source maps or debug files to Sentry. The source map
  is still written, so upload it afterwards with `sentry-cli sourcemaps upload`, which the Linux build has.
- **Why:** sentry-cli's Linux build has no `react-native xcode` (`error: unrecognized subcommand
  'xcode'`), and that command is what runs the bundling and the upload.
- **When it goes away:** when sentry-cli's Linux build has `react-native xcode`.
- **Upstream issue:** none.
- **To turn it off:** `--no-project-fixes`. Setting `SENTRY_DISABLE_AUTO_UPLOAD` yourself, on the
  command line or in the environment, also leaves it to you.

### Not fixes, but you should know

To run a project's scripts as a Mac would, a Linux build provides what macOS provides. These are the
build machine, not changes to your tools, so they are not in the summary and `--no-project-fixes`
leaves them on:

- Script phases run under a bash set up to behave as macOS's `/bin/sh`
  ([ADR 0103](adr/0103-script-phase-shell.md), [ADR 0180](adr/0180-scripts-run-by-path.md)).
- nomac's own `xcodebuild`, `xcrun`, `ditto`, `file`, `md5`, `PlistBuddy` and other macOS and Xcode
  commands, which script phases find on `PATH` or by the path they use on a Mac.
- On a case-sensitive disk, the compilers get a case-insensitive view of your headers and frameworks, as
  a Mac's disk gives them.
- nomac raises its limit on open files to the most the system allows, and the tools a build runs inherit
  it. A user's shell on Ubuntu starts at 1024, and a fresh Expo app's archive had about 2,700 files open
  at once.

## Part B: What you may have to change yourself

nomac stops, or the tool fails, in these cases. Some need a change in your project, and some need
something installed on the build machine.

**How to find out:** run `nomac check` before you build. It reads your project's files, and what it
cannot see only shows up when you build. It exits with 1 when any feature is outside what nomac has
verified, and a fresh app is no exception: on 2026-11-05 a fresh React Native 0.88 app listed 5 of 253
features and a fresh Expo SDK 58 app 7 of 269, mostly signing settings and `ipconfig`, and both archived
and exported. Read the list rather than the exit status.

### What `nomac check` reports

| What | Feature | What to do |
|---|---|---|
| A setting names a Mach-O tool with no Linux build beside it, or a macro plugin with no package | `build:setting=mach-o-executable` | Name a build of the tool for the build machine on the command line (`nomac build ... NAME=<path>`). The report names any Linux builds or npm packages it found. It also shows when several builds fit, or only other machines' do (install `qemu-user-static`). It reads settings without conditions only, so `NAME[sdk=iphoneos*]` is not seen |
| A script phase runs a Mach-O executable by its path | `build:script=mach-o-executable` | Put a build for the build machine at that path, or build on a Mac |
| A native Node module exists only for macOS | `build:node-module=mach-o-only` | Install your Node packages on the build machine, because npm installs only that machine's optional packages; or `npm rebuild` |
| A script runs a macOS-only command, for example `build:script-command=plutil`, `build:script-command=defaults`, `build:script-command=ipconfig` or `build:script-command=open` | The command's own feature | The report says what to change for each. Make the script skip it off macOS, or use a tool both systems have. `plutil` and `defaults` are not provided yet (B-190) |
| A script needs `nc` | `build:script-command=nc` | Install netcat on the build machine |
| A phase runs with something other than a shell, such as Bugsnag's dSYM upload | `build:script-interpreter=ruby` | Install that program on the build machine |
| BSD `sed -i ''` | `build:script=sed-in-place-bsd` | Write `sed -i.bak … && rm …bak`, which both systems run |
| A script picks a tool by `uname -m` or `arch` | `build:script=machine-architecture` | Make sure its Linux branch names a Linux tool |
| Crashlytics' `upload-symbols` | `build:script=crashlytics-upload-symbols` | Skip the upload off macOS, or use a Linux tool |
| `sentry-cli react-native xcode` in a script that has no `SENTRY_DISABLE_AUTO_UPLOAD` | `build:script=sentry-cli-react-native-xcode` | Call the bundling directly on Linux; `sentry-xcode.sh` needs nothing (`sentry-auto-upload` above) |
| A deployment target older than Xcode 27's SDK supports | `build:setting=deployment-target-below-minimum` | Raise it; the report gives the Podfile `post_install` for CocoaPods' targets |
| Metal shaders | `metal:shader` | nomac has no Metal compiler yet (B-241) |

Other features outside what nomac has verified are listed too; `nomac check --all` shows every feature
with its evidence, and [docs/formats/check.md](formats/check.md) describes them. Script commands are
found by reading run-script phases and the shell scripts they name. A command that JavaScript, Ruby
or a computed path runs is not seen.

### What `nomac check` does not report

| What | How you find out | What to do |
|---|---|---|
| **The iOS 27 scene manifest** ([TN3187](https://developer.apple.com/documentation/technotes/tn3187-migrating-to-the-uikit-scene-based-life-cycle)): an app built with the iOS 27 SDK and no `UIApplicationSceneManifest` stops at launch, unless its app delegate configures scenes in code | `nomac archive`, `nomac install` and `nomac device check` warn from the built app's `Info.plist`. `nomac build` does not, and `nomac check` cannot yet (B-467) | Adopt the scene life cycle in your app |
| A tool's own test for macOS that is not in Part A: `process.platform`, `uname` or similar inside the tool's code | The build fails with the tool's own message | Ask the tool's maintainers, or change the check in your project's patches. nomac does not make programs believe they run on macOS ([ADR 0182](adr/0182-tools-that-test-the-build-machine.md)) |
| A project moved after `pod install`: Expo's phase script records absolute paths | The phase still names the old location | Run `pod install` again in the new location |
| Pods or `node_modules` installed on a Mac and copied over, such as a Sentry xcframework that is a symbolic link into the Mac's `~/Library/Caches` | The build fails on the missing file | Run `npm install` and `pod install` on the build machine |
| A library that does not compile with Xcode 27, or a mix of package versions, such as RevenueCat 5.50.1 | The build fails with the compiler's error, which Xcode 27 gives too | Update the library, or align the versions |
| What the build machine needs for your project's tools: Node, Ruby and CocoaPods for React Native and Expo | The tool is not found. `nomac doctor` checks nomac's own tools, not these | Install them ([docs/DEMO.md](DEMO.md) lists them) |
| A system's hard limit on open files too low for your project. Ubuntu's is 1048576, so this is rare | The build fails with "Too many open files" | Raise the hard limit: `/etc/security/limits.conf`, or `--ulimit nofile=` for a container |

## Part C: Fresh apps of other cross-platform frameworks

**No framework on this list has reached an IPA through nomac yet, so none of them is claimed to work.**
These are the results so far, from 2026-11-07, on a machine overloaded enough that the runs did not finish.
`.github/scripts/framework_apps.py` repeats them. Whether an app launches on a phone is not tested for any
of them. These runs used an older copy of the Xcode SDK subset, so a failure here is not yet a verdict on nomac.

| Framework | What ran on Linux | Stopped at | Reached an IPA |
|---|---|---|---|
| Flutter 3.47.7 | `flutter create --platforms=ios` succeeded and wrote `ios/Flutter/Generated.xcconfig` and the Swift package the project needs. `flutter precache --ios` started downloading the iOS engine | `flutter build ios --config-only` is refused (below). `nomac check` and `nomac archive` have not run on Linux yet | No |
| Capacitor 8 | `npm init @capacitor/app`, `npm install @capacitor/ios`, `npx cap add ios` and `npx cap sync ios` all succeeded | `nomac check` reports that nomac cannot compile its launch screen (below). `nomac archive` was stopped unfinished after 7 minutes with no output | No |
| Cordova | Stopped during `cordova create` | Not run | No |
| Kotlin Multiplatform | Nothing | Not run | No |
| NativeScript | Nothing | Not run | No |
| Tauri mobile | Nothing | Not run | No |

### Flutter

Seen on a Mac with Xcode 27.0: `flutter create`, `flutter pub get` and an ad hoc `xcodebuild archive` of the
result succeed, and `nomac check` lists only signing settings for that project (4 of 270 features).

Seen on Linux: `flutter build ios --config-only` stops with `Could not find an option named "--config-only".`
Nothing needs it for a fresh app, because `flutter create` has already written what the project needs.

What you should expect next on Linux, from Flutter 3.47.7's sources and its macOS files, not from a run:

- **Release and Profile builds need a Linux build of `gen_snapshot_arm64`.** Flutter ships that compiler only
  as a macOS executable, and it has to match Flutter's Dart revision exactly. nomac does not provide one and
  has not tested one, so a Release build, which is what `nomac archive` makes by default, is the open question
  (BACKLOG B-510).
- Debug builds do not run that compiler, but they and Profile builds run `plutil`, which nomac does not provide
  yet (B-190).

### Capacitor

`nomac check` reports `nib:refused=B-260` for the launch screen `cap add ios` writes, because its view
controller's root view is an `imageView` (BACKLOG B-511).

If nomac fails on something not in either part, it is a bug or a gap in this list: please open an issue.
