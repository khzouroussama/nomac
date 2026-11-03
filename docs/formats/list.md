# The `xcodebuild -list` format

Observed with Xcode 27.0 (27A266a) on loader-experiments `schemes`, `workspace`, `scheme-order`
and `user-schemes-workspace` and on the corpus (`xcodebuild-list.json` of every reference).
`nomac list` writes the same output.

## Text

```
Command line invocation:
    /Applications/Xcode_27.app/Contents/Developer/usr/bin/xcodebuild -project /path/P.xcodeproj -list

Resolve Package Graph


Resolved source packages:
  Kit: /path/Kit
  Dep: /path/Deps/Dep @ local

Information about project "P":
    Targets:
        App
        AppTests
        MacTool

    Build Configurations:
        Debug
        Release

    If no build configuration is specified and -scheme is not passed then "Release" is used.

    Schemes:
        AppAndKit
        kit-cli
        KitExtras

```

- The two preambles are those of `-showBuildSettings` (docs/formats/show-build-settings.md); the
  package one appears only when the workspace uses Swift packages.
- Targets in project order, those of the projects it references left out (moonlight:
  `Moonlight`, `Moonlight TV`); build configurations in the order of the project's
  configuration list; the quoted configuration is the list's default.
- Schemes as docs/formats/show-build-settings.md "Schemes" describes, shared and per-user,
  ordered by Unicode collation in English (`kit-cli` before `KitExtras`; netnewswire:
  `NetNewsWire Share Extension` before `NetNewsWire-iOS`; loader-experiments `scheme-order`:
  `Émile` before `Eve`, `10lives` before `9lives`, `zed` before `Zed`). A name several shared or
  per-user schemes share is listed once for each, followed by its container (`Same (P project)`,
  `Same (W Workspace)`, `Clash (Kit Folder)`; `user-schemes-workspace`,
  `user-schemes-packages`). A name a shared or per-user and an autocreated scheme share is
  listed twice, unchanged (loader-experiments `test-bundles`: `Shared`); a name two autocreated
  schemes would share, once (`project-references`: `Twin`).
- Each list's entries are indented by eight spaces; each section ends with an empty line.
- Normalization forms (loader-experiments `unicode-nfc`, `unicode-nfd`): the project's name is
  decomposed, whatever its form on disk; target and configuration names are as the project file
  writes them; a shared or per-user scheme's name is its file name as it is on disk. The order
  compares canonically equivalent names as equal (`unicode-list-order`: `a\u0301`, written
  decomposed, sorts as `á`, first; the collation above gives that experiment's whole order, `Aa`,
  `Àa`, `Ab`, `AEa`, `Æb`, ..., `ss`, `ßa`, ..., `Ωb`, `Ωmega`, `日本`).

A workspace lists only its schemes:

```
Information about workspace "W":
    Schemes:
        App
        Client
        Other

```

## JSON (`-list -json`)

No preamble. Keys in order, two-space indentation, ` : ` between a key and its value, `/` not
escaped, a newline at the end:

```json
{
  "project" : {
    "configurations" : [
      "Debug",
      "Release"
    ],
    "name" : "P",
    "schemes" : [
      "AppAndKit"
    ],
    "targets" : [
      "App"
    ]
  }
}
```

A workspace has `"workspace" : { "name", "schemes" }`. An empty array is written `[`, an empty
line, then `]` at the array's indentation, as `-showBuildSettings -json` writes an empty result.

