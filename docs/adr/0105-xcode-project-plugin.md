# ADR 0105: Build tool plugins of Xcode projects, with `XcodeProjectPlugin` reimplemented off macOS

- Status: accepted (the owner's decision, 2026-11-02: on the same basis as Apple's macro plugins, ADR 0150)
- Date: 2026-11-02

## Context

A target of an Xcode project can apply a Swift package's build tool plugin (a `plugin:` product
dependency; loader-experiments `build-tool-plugin`). xcodebuild compiles the plugin, sends it
SwiftPM's `createXcodeProjectBuildToolCommands` message with the project and the target, and adds
each command the plugin returns to the target as a shell-script phase (docs/formats/build.md
"Build tool plugins"). Both ends of that message are open source in SwiftPM: the host serializes
an `XcodeProjectRepresentation` (`SPMBuildCore`), and `PackagePlugin` decodes it in the plugin.

The plugin's own code is the closed part. It conforms to `XcodeBuildToolPlugin` and receives an
`XcodePluginContext` and an `XcodeTarget`, all declared by Apple's `XcodeProjectPlugin` module,
which Xcode 27.0 ships only as a macOS library (`Contents/SharedFrameworks/SwiftPM.framework/
SharedSupport/PluginAPI/libXcodeProjectPlugin.dylib`, with its `.swiftmodule`). `PackagePlugin`
hands the decoded message to it through one C entry point,
`call_XcodeProjectPlugin_build_command_creation_entry_point`, which the library provides. Off
macOS there is no such library: `#if canImport(XcodeProjectPlugin)` is false, a plugin compiles
without its Xcode conformance, and for an Xcode target it returns nothing or fails.

## Options

1. **Run no plugin of an Xcode project off macOS**, and fail the build as a project requirement.
   Projects that use one cannot build on Linux.
2. **Answer the message with the plugin's `PackagePlugin` conformance.** Plugins implement the two
   differently (the experiment's returns no command for a package target), so the commands would
   not be Xcode's.
3. **Reimplement `XcodeProjectPlugin` for the build machine.** The plugin compiles with its Xcode
   conformance, as on a Mac, and the commands are the ones it returns to Xcode.

## Decision

3, on the basis ADR 0150 sets for Apple's macro plugins:

- The module's API (its types, their members, names and signatures) is written from Apple's
  public documentation of `XcodeProjectPlugin` and from the declarations of the module's textual
  interface in the user's Xcode, read as a header is read. The interface is never copied into the
  repository, in part or in whole.
- Its behavior (what each member returns, how the commands reach the host) is written only from
  observed outputs: the messages the plugin sends, the PIF and the logs of Xcode 27.0's builds of
  self-written projects (`.github/scripts/build_plugin_experiments.py`). Nothing of Apple's
  library is decompiled or disassembled, and no binary of it is used off macOS.
- On a Mac, the plugin links Apple's library, as with Xcode; nomac's module is for the machines
  that have none. It is built, with the `PackagePlugin` below, by the compiler that compiles the
  plugins (the toolchain that evaluates the manifests), the first time a build needs it, under
  nomac's home (`scratch/plugin-api/<compiler and sources>`), and the plugins are compiled
  against that folder (`NomacPluginAPI`).
- swift.org's `PackagePlugin` cannot hand the message to such a library off Darwin: its call of
  the entry point is `fatalError("FIXME: Compiler crashes when trying to compile a call to
  callerFunc")` there (SwiftPM `Sources/Runtimes/PackagePlugin/Plugin.swift`, at the pin). So
  off macOS the plugins link nomac's build of SwiftPM's open-source `PackagePlugin`, at nomac's
  SwiftPM pin, with that call made, next to nomac's `XcodeProjectPlugin`: the add-on library
  returns an error as a retained object instead of an existential. The change is kept as a patch
  for upstream (docs/upstream/swift-package-manager.md); proposing it is the owner's decision.
- The host side is SwiftPM's: nomac builds the `XcodeProjectRepresentation` of the project from
  its own model, sends it with `createXcodeProjectBuildToolCommands`, and adds the commands to
  the target as Xcode adds them, by experiment.

## Consequences

- Xcode projects whose targets apply build tool plugins build on Linux with the plugins' Xcode
  code, the commands checked against Xcode's PIF and outputs for the experiments' plugins.
- A member of `XcodeProjectPlugin` no experiment shows a value for is not implemented; a plugin
  that uses one fails to compile off macOS with the compiler's own error, and the gap is a
  BACKLOG item, as for an unreimplemented macro (ADR 0150).
- The module follows Xcode releases: a new Xcode's `XcodeProjectPlugin` is compared again when
  the pin moves (ADR 0012).
