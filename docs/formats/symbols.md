# `.symbols` files

What `xcodebuild -exportArchive` of Xcode 27.0 (27A266a) writes into `Symbols/<UUID>.symbols`
for an app-store-connect export (`uploadSymbols` true, the default), one file per DWARF file of
the archive's dSYMs and per slice of a universal one, and how `nomac symbols` (module `NomacPackaging`, `SymbolsFile`) writes the
same bytes. Everything below was observed:

- **Exports**: `signing_experiments.py` exports the `adhoc`, `nested` and `symbols` experiments
  (Swift, C, Objective-C and C++, eight static C functions of one name, inlined calls up to six
  levels deep), the `span` experiments, the watch apps of `watch` and `watch-appclip-script`
  (a universal dSYM: arm64 and arm64_32), and the package, ExtensionKit, XPC and on-demand
  resources experiments; `compare-symbols` runs `nomac symbols` on their dSYMs: 60 of 60 files
  identical.
- **A self-written dSYM** (`SyntheticDSYM`, `ArchiveExporterTests.writesTheSymbolsXcodeWrites`,
  and universal with an arm64_32 slice, `writesSymbolsForEachSliceOfAUniversalDSYM`): exported
  by xcodebuild through `synthetic-export`, for the cases the experiments lack.
- **The `symbols` tool** (`xcrun symbols -noTextInSOD -noDaemon -arch all -symbolsPackageDir`) on
  copies of that dSYM with symbols moved, retyped or renamed, to tell rules apart. Its files have
  the same layout and rules; they differ in demangling (below), so their bytes are not Xcode's.

The file is deterministic: the same dSYM at the same path with the same modification time gives
the same bytes (exports repeated). It records the DWARF file's absolute path as the export found
it (the archive's path with symbolic links resolved: `/tmp/x` gives `/private/tmp/x` on a Mac,
and `/private/tmp` is not shortened) and its modification time, so it depends on where the
archive is and when its dSYM was written. `nomac symbols` records the path it is given, made
absolute; `nomac export` resolves the archive's path as xcodebuild does.

A universal DWARF file gives one file per slice, in header order, each named by its slice's
`LC_UUID` and recording the same path and time. All integers are little-endian. Below,
*relative* addresses are the file's addresses minus `__TEXT`'s `vmaddr` for 64-bit files; a
32-bit file (arm64_32) keeps its addresses as they are.

## Header

| Offset | Size | Value |
|---|---|---|
| 0 | 4 | `0xff01ff02` |
| 4 | 4 × 5 | 1, `0xffffffff`, 0, flags `0x2b00` (the `symbols` tool: `0x2b20`), owner count 1 |
| 24 | 16 | `LC_UUID` |
| 40 | 4 | the DWARF file's modification time, whole seconds |
| 44 | 4 | `0x10000101` |
| 48 | 8 | 0 |
| 56 | 8 | `0x7fffffffffffffff` |
| 64 | 4 × 4 | `cputype`, `cpusubtype`, segment count, path field length |
| 80 | | the path, NUL-terminated, zero-padded to a multiple of 8 (the length field) |
| | 32 each | every segment in load command order: name (16, NUL-padded), `vmaddr`, `vmsize` |

## Symbol owner data

Starts right after the header (`base`, a multiple of 8):

| Offset from `base` | Size | Value |
|---|---|---|
| 0 | 8 | `0xa1b22b1a`, 7 |
| 8 | 4 | `0xa1b22b1a` |
| 12 | 4 | length: from `base` to the end of the first trailer record, padded |
| 16 | 4 | 7 |
| 20 | 4 | end of the strings, from `base - 8` |
| 24 | 4 × 5 | segment, section, symbol, inlined-call and line-row counts |
| 44 | 4 | 17 |
| 48 | 8 | 0 |
| 56 | 8 | offset of the path in the strings |
| 64 | 4 | size estimate: (string start − `base`) + 2 × string bytes − (path length + 1) + the five counts + 32 |
| 68 | 16 | `LC_UUID` |
| 84 | 4 × 2 | `cputype`, `cpusubtype` |
| 92 | 8 | 0 |
| 100 | 4 | string bytes |
| 104 | 4 | 4 × the number of demangled names in the symbol records |
| 108 | 4 | 0 |
| 112 | | the tables, the indexes, the strings, then the trailer |

### Segments (32 bytes each)

`address` (8), `size` (8), name (16). Segments other than `__PAGEZERO`, `__DWARF` and
`__LINKEDIT` keep their relative address; those three are laid out one after another from the
end of the last of the others, in load command order with `__LINKEDIT` last (an app's
`__PAGEZERO` at `0x10000`, `__DWARF` at `0x100010000`, `__LINKEDIT` after it). In a 32-bit
file every segment keeps its address (`__PAGEZERO` at 0, `__TEXT` at `0x4000`, `__LINKEDIT`
before `__DWARF` as the file has them).

### Sections (24 bytes each)

`address` (8), `size` (8), name offset (8). The first is `MACH_HEADER`: at `__TEXT`'s
relative address (0, or `0x4000` in a 32-bit file), up to the first `__TEXT` section. Then every section in load command order, named
`"<segment> <section>"`, at its segment's new address plus its offset in the segment.

### Symbols (24 bytes each)

`address` (relative), `size`, flags, demangled name offset (0 for none), name offset, first
inlined call (index, or -1). Records are in address order.

The symbol table's entries count when they are defined in a section (`N_SECT`, not `N_STAB`)
other than those of the three segments above (`__mh_execute_header` lies in no section).
Entries that share an address:

- all with one name: one record, the first in symbol table order;
- else the external ones (`N_EXT`) each make a record, the second and later with flag `0x200`;
  the others merge into each of them (flag `0x20000000`, and `0x20` if one was `N_PEXT`);
- else, in data sections, the first in symbol table order, the others merged into it;
- else, in code sections (`S_ATTR_PURE_INSTRUCTIONS` or `S_ATTR_SOME_INSTRUCTIONS`), a
  `<deduplicated_symbol>` record (flags `0x800`), then every entry, with `0x800` and without
  DWARF (the linker's deduplicated functions), and with `0x20` on every one when one of them
  was `N_PEXT` (`archive-extensionkit`, an async witness thunk and its function).

Every DWARF function (`DW_TAG_subprogram` with an address) whose start no entry names makes a
record of its own: `_` and its linkage name (flags `0x05610101`) or name (`0x05508101`), sized
by its range.

Flags: `0x03484000`, `0x1` in code sections, `0x10` for `N_EXT`, `0x20` for `N_PEXT`, `0x4` for
an Objective-C method name (`+[…]` or `-[…]`). The first record at the start of a DWARF function
takes its size from the function's first range and adds `0x24000100`, and `0x80` with
`DW_AT_APPLE_omit_frame_ptr`. Other records run to the next record's address (any record, DWARF
ones included) or the section's end.

Names are the symbol table's, written once per string table offset: equal names at different
offsets are written twice. A name whose start looks mangled (`_$s`, `_Z`, `__Z`, so also
`_ZedVersionString`) has no demangled name; the others point at their name after its leading
underscore (or at the name, without one). The `symbols` tool demangles every name instead and
stores the results.

### Inlined calls (36 bytes each)

A symbol record's own fields (24 bytes), then call file offset, call line, call column.

Each `DW_TAG_inlined_subroutine` directly in a function (through lexical blocks) makes one
record per address range, in address order; the calls inlined in a record are those of its entry
that start in its range. Lists are laid out breadth first: the top lists of the symbols in
symbol order, then the list of each record in record order, and the record or symbol names the
first index of its list. Flags: `0x85610101` when the called function has a linkage name
(followed through `DW_AT_abstract_origin` and `DW_AT_specification`), else `0x85508101`;
`0x40000000` on the last of a list. The name is `_` and that linkage name or name; the demangled
name follows the symbols' rule. The call file is the line table's path.

### Line rows (20 bytes each)

`address` (relative), `size`, path offset, line, column: one per row of every compile unit's
line table, in address order, except `end_sequence` rows and rows the next row starts at. A
row ends at the next row's address or at the end of the symbol record it starts in, whichever
comes first; rows that start in no record, or in the records of deduplicated functions
(`archive-extensionkit`), are left out. Paths are the file name, under its
directory, under `DW_AT_comp_dir`, each joined only when the part after it is relative.

### Indexes

Two lists of 4-byte entries, each the entry's own offset minus the offset of the symbol record it
names: the symbols with a demangled name sorted by it, then all symbols sorted by name, bytewise.
The symbols are given in address order to libc++'s `std::sort`, whose order the file keeps for
equal names (eight `_helper` functions in two exports); nomac runs the same algorithm
(`IntroSort`, from LLVM's open-source libc++ as Xcode 27.0's SDK ships it).

### Strings

NUL-terminated, in this order: the section names; the symbol names in record order (once per
symbol table offset, `<deduplicated_symbol>` once); the inlined calls' names and call files, in
one pool, interned depth first (a record, its call file, the calls inlined in it, then the next
record); the line rows' paths, in the same pool; the DWARF file's path.

### Trailer

Right after the strings: `0x00c0ffee`, 1, 24, `0x2b00`, `0x2b00`, 0; zeros to a multiple of 8;
then the fixed 76 bytes `0x00c0ffee`, 4, the bytes 0 to 15, 8 zeros, the bytes 0 to 15, 16
zeros, the 8-byte value 8, 4 zeros.

## Not covered yet

64-bit DWARF (nomac stops), DWARF 4 units
(read as the standard says, not observed), `DW_FORM_strp_sup` and other supplementary forms, several DWARF functions starting at one address, and the heap sort libc++
falls back to after `2 log2 n` partitions (implemented as libc++ does for non-arithmetic
elements, never reached by an export observed).
