# ADR 0250: nomac writes strings outputs and property lists itself

- Status: accepted
- Date: 2026-10-21

## Context

An iOS build turns localization files into resources with two tools (docs/formats/strings.md):

- `builtin-copyStrings`, a task of Swift Build itself, for every `.strings` and `.stringsdict`
  file and every output of a string catalog. On a Mac it detects the input encoding with
  `NSString`, then writes a binary property list through Core Foundation, after sorting keys
  and interning strings so the bytes are stable.
- `xcstringstool compile` (and `generate-symbols`), a closed tool of Xcode, for `.xcstrings`.

Running Swift Build on Linux does not reproduce the first: off Darwin,
`FileTextEncoding.string(from:encoding:)` detects no encoding, so every copy without
`--inputencoding` fails, and `FileTextEncoding.stringEncoding` is nil, so UTF-16 and UTF-8
output fail too. With the text decoded by hand, the binary property lists `SWBUtil` writes on
Linux (`PropertyListItem.asBytes(.binary)`, swift-corelibs-foundation) differed from Xcode's in
13 of 36 self-written cases: keys in hash order and no shared strings (a probe on Linux against
strings-experiments `copy`). The same writer produces every binary property list of Swift
Build's builtin tasks.

## Decision

1. **`NomacPlist`** writes property lists byte for byte as Xcode's tools do, on every platform,
   without `PropertyListSerialization`: XML as Core Foundation writes it, and binary as Swift
   Build's builtins write it on a Mac (docs/formats/property-lists.md). It also reads the text
   formats, so reading does not depend on the platform either.
2. **`NomacStrings.StringsFileCopy`** is `builtin-copyStrings` as observed: encoding detection,
   byte order marks, validation, binary, UTF-16 and UTF-8 output, and the notes. `nomac
   builtin-copyStrings` takes Swift Build's command line. How a Linux build runs it instead of
   Swift Build's task is the build driver's decision (BACKLOG B-253); the two Swift Build
   changes that would make the builtin correct off Darwin are listed there.
3. **`NomacStrings.StringCatalogCompiler`** replaces `xcstringstool compile`, as `nomac
   xcstringstool compile` with its command line, from observed outputs only.

## Consequences

- nomac reproduces every observed strings output byte for byte on Linux and macOS: 44
  self-written strings files in three encodings, 8 of `\U` surrogate escapes, the 9885 corpus
  strings files, 268 self-written catalogs in three variants and 49 corpus catalogs, diagnostics
  included. The comparison is
  `.github/scripts/strings_compare.py`.
- Other builtins that write binary property lists (Info.plist processing, `builtin-copyPlist`)
  can use `BinaryPropertyList.swiftBuildData` once their own rules are observed.
- Behaviors not observed yet are refused with an error naming the BACKLOG item, never guessed:
  other input encodings, binary inputs, octal escapes above `\177`, binary catalog
  serialization (B-250, B-252).
