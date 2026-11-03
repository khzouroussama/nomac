# ADR 0270: nomac compiles Core Data models itself, from what Core Data's public API shows

- Status: accepted
- Date: 2026-10-22

## Context

iOS builds compile `.xcdatamodel` and `.xcdatamodeld` files with `momc`, a closed tool that links
Core Data; nothing of it runs on Linux. Its outputs are an `NSKeyedArchiver` archive of the
`NSManagedObjectModel` (`.mom`), a property list of version hashes (`VersionInfo.plist`) and, for a
current version, an `.omo` (docs/formats/coredata.md). Three things decide their bytes:

- what each Core Data class encodes, in which order;
- how `NSKeyedArchiver` and Core Foundation's binary writer lay objects out, which follows object
  identity: which strings and numbers are one object in momc's process (interned strings, tagged
  pointers) changes the file;
- Core Data's version hashes, whose preimages are not documented.

The legal line (CLAUDE.md) excludes disassembling momc or Core Data.

## Decision

1. **Observe through public interfaces only.** The hashes are fitted to `versionHash` and
   `versionChecksum` of objects built through Core Data's API (coredata-experiments
   `version-hashes`); what each class encodes is recorded by an `NSCoder` subclass passed to its
   public `encode(with:)`; the archiver's and the writer's rules come from `NSKeyedArchiver` run on
   self-written `NSCoding` classes. Each rule is then checked on every momc output observed.
2. **`NomacCoreData` reproduces the process, not the files.** It builds the objects momc would,
   encodes them through a model of `NSKeyedArchiver` (numbering, conditional objects, class
   descriptions, per-object dictionaries as Foundation tables) and writes them with a model of
   Core Foundation's writer whose sharing follows identities: one string per text for momc's
   interned strings and Foundation's class names, tagged-pointer strings shared everywhere, a new
   string for each Core Data class name. The objects are serialized by
   `BinaryPropertyList.data(objects:)`, which gains 4-byte reals and UIDs; dictionary orders come
   from `FoundationHashTable`.
3. **Only what is observed is compiled.** Every model element, attribute and combination outside
   what the experiments and the corpus show stops `nomac momc` with the BACKLOG item that covers it
   (B-256 for `.omo`, B-257 for model features, B-258 for code generation, B-259 for large tables).
4. **momc's diagnostics are part of the output**: the version checksum notes and the warnings are
   printed as momc prints them, in its order.

## Consequences

- `nomac mapc` follows the same decisions. Mapping models embed Xcode's model documents
  (`XDPMModel` keyed archives), which `NomacCoreData` reads for the version hashes. mapc does not
  intern its strings, so the archiver also shares strings and data by object.

- Every `.mom` momc wrote for the corpus (84 files of 34 models) and for the self-written models
  nomac accepts is reproduced byte for byte, with `VersionInfo.plist` and the diagnostics of every
  model without a current version (`coredata_compare.py`); models with a current version wait on
  the `.omo` (B-256).
- The order of versions depends on their paths and on how a Mac's APFS volume lists a directory,
  which nomac computes; outputs compared with Xcode's must be compiled at the same path.
- momc's `.omo` is not deterministic in one place: in models with a subentity, two u64 slots of the
  superentity's record hold the indexes of the entity and its subentity in an order that changes from
  run to run. Observed on three compilations each of the 72 `.omo` files of `omo-runs`: only
  `omo-inheritance` (bytes 2423 and 2431) and uncloudnotes final v4 (4943 and 4951) vary. The
  integrator's decision (2026-10-24): bytes Xcode varies between runs may differ once identified
  and documented, and `nomac verify` masks exactly these. Everything else must match. nomac does
  not write `.omo` files yet (B-256).
- If a later Xcode changes Core Data's encoding, the recording coder and `coredata_compare.py`
  show which class changed.
