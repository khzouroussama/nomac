# ADR 0006: Two more machine-specific roots, and scheme captures always name a destination

- Status: accepted (extends ADR 0004)
- Date: 2026-10-21

## Context

ADR 0004 allows exactly three path rewrites when comparing nomac with a reference, and
requires a new ADR, with the reason, for any addition. The first macOS verification found
two more values that are machine-specific by construction:

1. **Swift Build's plugin resource directory.** `PATH` begins with the resource directory of
   Swift Build's universal-platform plugin. Inside Xcode that is
   `Xcode.app/Contents/SharedFrameworks/SwiftBuild.framework/Versions/A/PlugIns/SWBBuildService.bundle/Contents/PlugIns/SWBUniversalPlatformPlugin.bundle/Contents/Frameworks/SWBUniversalPlatform.framework/Resources`.
   Next to nomac it is `SwiftBuild_SWBUniversalPlatform.bundle` (on macOS, its
   `Contents/Resources`). The value names where the build engine is installed, not anything
   about the project.
2. **The per-user cache directory.** Without `-scheme`, Swift Build puts the module-session
   file, the compilation cache and the SDK stat cache under `userCacheDir()`. On Darwin that is
   `confstr(_CS_DARWIN_USER_CACHE_DIR)` (`/var/folders/…/C/`); elsewhere it is the temporary
   directory. Its `CCHROOT` override cannot reproduce both of its uses at once, because one is
   suffixed `org.llvm.clang` and the other `com.apple.DeveloperTools`.

Separately, `xcodebuild -showBuildSettings -scheme S` without `-destination` uses the first
matching destination, which on a Mac is the Mac itself ("My Mac, Designed for iPad"). That
adds `TARGET_DEVICE_IDENTIFIER` (the Mac's hardware identifier, different on every runner),
`TARGET_DEVICE_MODEL`, and so on. There is no such destination off macOS.

## Decision

- Comparisons also rewrite `<SWIFT_BUILD_RESOURCES:<plugin>>`, for each Swift Build plugin,
  and `<USER_CACHE_DIR>` (recorded as `userCacheDirectory` in the reference's `host.json`).
  These two and the three roots of ADR 0004 are the complete list.
- Reference scheme captures always pass `-destination generic/platform=iOS`, the
  destination nomac builds for.

## Consequences

- On the macOS runner the user cache directory is the same for the capture and verify jobs.
  The new root matters for Linux verification.
- Values that *hash* a path cannot be rewritten: `SDK_STAT_CACHE_PATH` contains
  `$(SDKROOT:__md5)`, and DerivedData folder names hash the project path. Such values only
  match when the paths are identical, which is why CI verifies at the reference's own paths.
  On Linux they additionally need Swift Build to use real MD5, which the owner's fork of Swift
  Build carries (B-005, ADR 0005).
