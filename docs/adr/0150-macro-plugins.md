# ADR 0150: Apple's macro plugins, reimplemented in the platform's plugin directory

- Status: accepted (the owner decided the scope in B-121: reimplement each macro from its observed expansions)
- Date: 2026-10-22

## Context

The SDK declares the macros of Apple's frameworks as `#externalMacro(module:type:)`: in the iOS
27.0 SDK, 55 macro types in closed modules (`PreviewsMacros` 6, `SwiftUIMacros` 20,
`SwiftDataMacros` 10, `AppIntentsMacros` 9, `FoundationModelsMacros` 4, `StateReportingMacros` 3,
`TipKitMacros` 2), besides the open-source `ObservationMacros`, `FoundationMacros` and
`SwiftMacros`. Xcode 27.0 keeps their implementations in each platform's
`Developer/usr/lib/swift/host/plugins` (`libPreviewsMacros.dylib`, ...), with the platform's own
swift-syntax libraries one directory up and `Developer/usr/bin/swift-plugin-server`: macOS
binaries a Linux compiler cannot load. In the iOS 27.0 SDK `@State` is one of these macros
(`SwiftUIMacros.StateMacro`), so every SwiftUI view with state needs them: 14 of the 20 corpus
apps (docs/state/macros.md).

Observed with Xcode 27.0 (27A266a) and in the sources Swift Build links:

1. **Search paths.** For a compile for an Apple platform, the driver adds
   `-external-plugin-path <platform>/Developer/usr/lib/swift/host/plugins#<platform>/Developer/usr/bin/swift-plugin-server`
   and the same for `usr/local/lib/swift/host/plugins`, before the toolchain's `-plugin-path`s
   (`swiftc -###`; swift-driver `DarwinToolchain.addPluginPaths`, which also maps a simulator
   platform to its device platform). Swift Build plans compiles with this driver in process, so
   the flags are the same on Linux. The frontend takes the first directory, in command-line
   order, with `lib<Module>` and the host's shared-library suffix: `.so` on Linux.
2. **Traces in outputs.** The `.d` dependency file of a compile lists the plugin library it
   loaded (`.../iPhoneOS.platform/Developer/usr/lib/swift/host/plugins/libPreviewsMacros.dylib`),
   and a module serializes the plugin search paths, which are the flags above.
3. **Loading.** `swift-plugin-server` opens a library plugin with `dlopen`, finds each macro by
   its `<module>.<type>` name in the Swift runtime and casts it to its own swift-syntax `Macro`
   protocol (swift-syntax `LibraryPluginProvider`). A plugin therefore links the server's
   swift-syntax shared libraries; a statically linked copy, as SwiftPM builds macro packages,
   would define another `Macro` protocol.
4. **The swift.org toolchain** ships swift-syntax's modules and libraries in `lib/swift/host`
   and a `bin/swift-plugin-server` linked to them; its own plugins (`libObservationMacros.so`,
   ...) are built so.
5. **Formatting.** swift-syntax formats an expansion on the plugin's side (`BasicFormat`, unless
   a macro opts out), so the text the compiler receives depends on the syntax tree the macro
   returns, including the trivia it keeps from the source, and on the host swift-syntax.

## Options

- **A. Library plugins in each platform's plugin directory**, built against the installed
  toolchain's swift-syntax and served by its `swift-plugin-server`, linked into the platform's
  `usr/bin`. Compile commands stay Xcode's; a `.d` file names Xcode's path with `.so`.
- **B. Library plugins in the toolchain's `usr/lib/swift/host/plugins`**, loaded in process.
  Compile commands stay Xcode's, but `.d` files name the toolchain's directory, and every
  platform gets every plugin, which Xcode does not do.
- **C. Executable plugins built by SwiftPM with swift-syntax as a package**, as open-source
  macro packages are, passed with `-load-plugin-executable`: new compiler flags in every compile
  (Swift Build's command lines change), and a second swift-syntax to keep at the toolchain's
  version.
- **D. A nomac `swift-plugin-server` with the macros built in**: the frontend still needs a
  `lib<Module>.so` in the plugin directory to choose the server, so the libraries would be empty
  files.

## Decision

A.

- The plugins are Swift sources in `Sources/NomacMacros/Plugins/<Module>/`, resources of the
  `NomacMacros` module, one directory per Apple plugin module with Apple's module and type names
  (`PreviewsMacros.SwiftUIView`, ...). Each macro is written from the expansions Xcode 27.0 gives
  for self-written inputs (`.github/scripts/macro_experiments.py`, docs/formats/macros.md); no
  plugin of Apple's is decompiled or disassembled.
- `nomac toolchain install` compiles them with the installed toolchain's `swiftc` against its
  `lib/swift/host`, so swift-syntax is the toolchain's own by construction, and installs them in
  every platform of the developer directory that has a plugin directory (the `nomac sdk`
  subset's iPhoneOS), with run paths to the `XcodeDefault` toolchain's libraries. The platform
  also gets links to the toolchain's open-source plugins Xcode keeps there and that expand as
  Xcode's do (Observation, Swift), and to its `swift-plugin-server` (`MacroPlugins.install`).
  swift-foundation's `FoundationMacros` is vendored and built as Apple's platform copy is, with
  `FOUNDATION_FRAMEWORK` (swift.org's names `FoundationEssentials`, which does not compile for
  iOS; `Plugins/FoundationMacros/UPSTREAM.md`).
- An expansion is correct when its text is Xcode 27.0's for every experiment input. Three checks:
  `macro_experiments.py compare` on a Mac, with Xcode's compiler and nomac's plugins first in the
  plugin search (the driver's `PLATFORM_DIR`); `NomacMacrosTests`, which sends nomac's plugins,
  through the test toolchain's `swift-plugin-server`, every use of a macro in the experiments as
  Xcode's compiler sent it, built from the experiments' self-written sources and where the
  compiler addressed each use (expansions that are inputs of later ones are nomac's own answers),
  and compares the SHA-256 digest of each answer, expansion and diagnostics, with that of the
  answer of Xcode's plugins; and on Linux, the same experiments compiled with the installed
  swift.org toolchain against the SDK subset. Objects compiled from the expansions are judged as
  ADR 0101 says.
- Captures stay outside the repository (CLAUDE.md): `macro_experiments.py record` writes the
  expansions and the plugin protocol of Xcode's plugins under the output directory it is given,
  never in the tree, and `macro_experiments.py facts` prints the tests' data (the sources, the
  compiler's addressing and the digests) without copying any request or answer. Expected texts
  written in tests are observed facts, as the other workstreams' tests write them.

## Consequences

- Swift Build's compile commands are unchanged, and a `.d` file differs from Xcode's only by the
  plugin's suffix.
- A macro nomac has not reimplemented fails to expand with the compiler's own error ("external
  macro implementation type ... could not be found"), as on any machine without the plugin.
- `FinanceMacros`, `MMIOMacros` and `StateReportingMacros` are not reimplemented: no corpus app
  uses them.
- A new Xcode release brings new SDK macros and possibly a new swift-syntax: the experiments are
  recorded again with it and every difference is a bug (B-121's plan, docs/state/macros.md).
- Plugins are compiled at install time, a few seconds per module, and need nothing besides the
  toolchain being installed.
