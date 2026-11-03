# ADR 0003: SDK extraction keeps an unmodified subset of the user's Xcode

- Status: accepted
- Date: 2026-10-21

## Context

nomac needs iOS SDK files (headers, `.tbd` stubs, Swift modules) and Xcode's
platform, SDK and toolchain metadata. That metadata is where the platform defaults
behind many build settings come from. nomac may not ship, mirror or commit any of these
files. Users supply their own `Xcode.xip` (or an installed `Xcode.app`).

xtool extracts a Darwin SDK from `Xcode.xip`, but:

1. its SDK builder is internal API (`XToolSupport.SDKBuilder` is not public);
2. it rewrites `Platforms/*.platform/Info.plist` (`CODESIGN`, `ALTERNATE_LINKER`,
   `SWIFT_RESOURCE_DIR`, `CLANG_RESOURCE_DIR`), which changes the resolved build settings;
3. it keeps neither `ToolchainInfo.plist` nor Xcode's `version.plist`, both of which Swift
   Build reads.

The XIP format is decoded by `unxip` (`saagarjha/unxip`), which is LGPL-3.0.
Statically linking it into nomac's Apache-2.0 binary would put relinking obligations on
every redistributor.

## Decision

- `nomac sdk install` copies a fixed subset of `Xcode.app/Contents` into
  `$NOMAC_HOME/xcode/<ProductBuildVersion>/Xcode.app/Contents`, byte for byte, with the
  same relative paths. Nothing is patched. Build-time differences needed on Linux (linker,
  code signing) are applied as build-setting overrides when nomac builds, never written into
  the copied files. (Superseded in part: ADR 0100 and ADR 0102 add open-source tools at paths the
  subset leaves empty, rather than overrides, so command lines name Xcode's paths.)
- `.xip` input is expanded by running the `unxip` executable as a subprocess into a staging
  directory next to the destination. The subset is then copied out and the staging
  directory removed. The `unxip` version is pinned and its install documented.
- `.app` input (an installed Xcode, for example on the macOS reference runner) is copied
  directly, with no staging.
- The subset is defined in one place (`XcodeSubset` in `NomacSDK`) and covered by tests.

## Consequences

- Peak disk use during `.xip` installation is the full expanded Xcode (tens of GB). A native
  streaming XIP reader that filters while it decompresses is tracked as BACKLOG B-002.
- Swift Build sees the same developer directory layout on Linux as on a Mac, so the
  macOS comparison runs validate the subset definition: nomac must produce identical
  output from the subset and from the full Xcode.
