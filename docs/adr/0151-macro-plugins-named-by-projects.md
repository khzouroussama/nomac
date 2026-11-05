# ADR 0151: A Mach-O macro plugin a project names is built for the build machine from the package beside it

- Status: accepted (the owner's scope for the macros workstream, 2026-10-31: build a plugin from
  its sources when they ship, else `nomac check` reports it as a project requirement). It takes
  over the Expo workstream's draft of the same day (its observations of Expo's plugin, its
  `nomac check` rule), which chose option C.
- Date: 2026-10-31

## Context

A project can load a Swift macro plugin that is not Apple's in two ways:

1. **A SwiftPM macro target** the app depends on through a package. Xcode builds it for the build
   machine from its sources, against SwiftPM's swift-syntax prebuilts
   (`SourcePackages/prebuilts/swift-syntax/604.0.0/...-MacroSupport`), and passes
   `-load-plugin-executable $(BUILT_PRODUCTS_DIR)/<target>#<target>` to the compiles that use it
   (`macro_plugin_experiments.py` macro-package). Swift Build does the same off macOS, for the
   build machine's system.
2. **A prebuilt plugin executable** the project's `OTHER_SWIFT_FLAGS` name with
   `-load-plugin-executable <path>#<module>`. Expo SDK 58's CocoaPods integration appends
   `-load-plugin-executable "<node_modules>/expo-modules-macros/apple/ExpoModulesMacros#ExpoModulesMacros"`
   to every Expo pod (`expo-modules-autolinking/scripts/ios/project_integrator.rb`,
   `resolve_macros_plugin_dir`, at `pod install`): expo-default's 18 pods, the RN holdout's
   expo-modules app's 21. The file is a universal macOS executable, which a Linux compiler cannot
   start ("compiler plugin ... could not be loaded: Exec format error"), and every pod using
   `@ExpoModule`, `@JS`, `@SharedObject`, … fails on Linux.

Observed:

- **The sources ship beside the binary.** `expo-modules-macros/apple` is a Swift package (tools
  version 6.2, a `.macro(name: "ExpoModulesMacros")` target and no product, swift-syntax
  `from: "604.0.0-latest"` pinned to 604.0.0 by its `Package.resolved`). A pod that builds its
  plugin at `pod install` with `swift build` leaves it in the package's own `.build`.
- **Xcode 27.0's compiler uses the first `-load-plugin-executable` of a module**
  (`macro_plugin_experiments.py order`: of a plugin and an executable that answers nothing,
  given for the same module, whichever comes first is used).
- **SwiftPM builds such a target only with its native build system.** Swift 6.4's default build
  system builds no macro target that no product names, on the Mac and on Linux (`swift build
  --product <target>`: "Could not find target named '<target>-product'"; `--target`: "Found
  multiple targets named"); `--build-system native --product <target>` builds
  `<bin>/<target>-tool`, for the build machine's architecture only.
- **A build from the sources expands as the shipped binary does.** macro-prebuilt's sources with
  `-dump-macro-expansions`: Xcode 27.0's compiler with the Mach-O and swift.org 6.4.0's with
  nomac's Linux build give the same bytes; so do expo-haptics' module with expo-modules-core's
  declarations (`expo_experiments.py macros`) with the Mac's `ExpoModulesMacros` and with the
  one built from `apple/` on Linux, and, as the Expo workstream found, with the Linux build Expo publishes
  as `@expo/modules-macros-linux-arm64` and `-x64` (npm platform packages, optional
  dependencies of `expo-modules-macros`).

## Options

- **A. nomac builds the plugin for the build machine from the package beside it** and loads that
  build first. The rule is SwiftPM's, not one tool's: the nearest `Package.swift` at or above the
  executable's folder whose manifest declares a macro target named as the executable.
- **B. nomac maps a Mach-O plugin path to an ELF one it finds** (an npm platform package): a
  guess about where another build lives, which only npm's layout answers.
- **C. The project names the build machine's plugin** where its files set the flag, as for a
  script phase's tool then (ADR 0182, `HERMES_CLI_PATH`; since ADR 0184 nomac does that too), and
  `nomac check` says which file and which build. The Expo workstream's draft chose this; the owner asked for A wherever the sources ship.

## Decision

A, and C for a plugin whose sources do not ship.

- `nomac build` and `nomac archive` off macOS evaluate every target's `OTHER_SWIFT_FLAGS` with
  the build's request. For each `-load-plugin-executable` whose executable is a Mach-O file,
  the nearest package's manifest is loaded (in-process, as for the workspace's packages); when
  it declares a macro target of the executable's name, `swift build --build-system native
  --product <name>` builds it in nomac's scratch folder (`scratch/macro-plugins/<name>-<hash of
  the package's path>`, kept between builds) with the package's `Package.resolved`, and the
  build's own `-load-plugin-executable <build>#<modules>` goes before the project's flags, each
  word after `-Xfrontend`: the driver passes `-Xfrontend` arguments to the frontend before the
  `-load-plugin-executable` it forwards itself (`swiftc -###`, swift.org 6.4.0), and some pods
  pass theirs through `-Xfrontend`, so a plain flag would come second. The project's files and
  the package's folder are left as they are.
- Without such a package, the compiler gets the project's flag as written and the build warns.
  `nomac check` lists a plugin with a package beside it as `build:macro-plugin=swift-package`
  (verified) and one without as the project requirement `build:setting=mach-o-executable`,
  naming, for an executable in an npm package, its Linux builds: the ELF executable of the same
  name at the root of an installed optional dependency, else the Linux (glibc) packages the
  lockfile lists.

- A SwiftPM macro target is Swift Build's to build, as on a Mac, from the PIF Xcode gives it,
  which builds it against SwiftPM's swift-syntax prebuilts under the name SwiftPM gives them for
  Xcode's toolchain (`swiftlang-6.4.0.34.1-macosx27.0`). Off macOS that folder holds SwiftPM's
  prebuilt of the same version for the installed compiler and the build machine, so the PIF
  stays Xcode's and the macro links (docs/formats/pif.md "Prebuilts").

## Consequences

- Expo's pods compile on Linux with the expansions Xcode's get, from the package Expo ships,
  without a change to the project.
- The first build of such a plugin fetches the package's dependencies (swift-syntax) with
  SwiftPM and compiles them; later builds reuse the scratch folder. An offline build machine
  needs SwiftPM's cache filled, as for the workspace's own packages.
- The build's flag reaches every Swift compile, also of targets that do not name the plugin. A
  plugin is started only for the macros a compile expands, so only the compiles' command lines
  and the plugin search options a Debug `.swiftmodule` records differ (ADR 0101 judges binary
  modules by their `.abi.json`).
- `--build-system native` is deprecated in SwiftPM 6.4; when it goes, a product-less macro
  target needs another way to be built (B-155).
