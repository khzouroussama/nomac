# Crash reports, symbolication and the app's console

What `nomac device crashes`, `nomac device symbolicate`, `nomac atos` and `nomac launch
--console` read and print. nomac implements them in `Sources/NomacDevice/CrashReports.swift`,
`Sources/NomacPackaging/CrashReport.swift`, `Symbolicator.swift`, `Demangler.swift` and
`AppService.launchInput` (`CoreDeviceService.swift`).

## The report (`.ips`)

Observed on an iPhone on iOS 27.0.1 (2026-11-02/03, reports copied with `devicectl`): one JSON
object on the first line, the header (`app_name`, `app_version`, `bug_type` `309`,
`build_version`, `bundleID`, `incident_id`, `is_first_party`, `name`, `os_version`, `platform`,
`roots_installed`, `share_with_app_devs`, `slice_uuid`, `timestamp`), then the report, one JSON
object: `procName`, `pid`, `exception` (`type`, `signal`, `codes`), `termination` (`namespace`,
`code`, `indicator`), `asi` (each library's application-specific messages), `faultingThread`,
`threads` (each with `queue` or `name` and `frames`), `lastExceptionBacktrace` for an uncaught
Objective-C exception, and `usedImages` (`name`, `uuid` lowercase, `base`, `size`, `path`,
`arch`, `source`). A frame is `imageIndex` and `imageOffset`; the device adds `symbol` and
`symbolLocation` for its own libraries and leaves the app's frames without them.

The exception's message is not in the report: an uncaught exception's reason reaches the app's
standard error, which `nomac launch --console` prints.

## Symbolication, as `atos -i`

`nomac atos -i -o <dSYM or DWARF file> -arch <arch> -l <load address> <addresses>` prints what
Xcode 27.0's `atos -i` prints, byte for byte, on every address `symbolicate_experiments.py`
sampled: 14,645 addresses of seven dSYMs (Retro Rampage's app and two frameworks, rn-bare's and
expo-default's apps in Release and Debug: Swift, C, C++, Objective-C) and every address of the
self-authored `SyntheticDSYM` (2026-11-03), on macOS and on Ubuntu 24.04 with `libc++abi1`. For each address: its frames, innermost first, one
per line, `<function> (in <image>) (<file>:<line>)` or `<function> (in <image>) + <offset>`, then
an empty line (an address without a function is an empty line, then the empty line). The rules:

- **The Mach-O header**: before the first `__TEXT` section, nothing.
- **A DWARF function the symbol table lacks**: when the last DWARF function (`DW_TAG_subprogram`
  range) starting at or before the address starts after the symbol table's last symbol, it
  decides alone: its frames if its ranges hold the address, nothing past its end.
- **The symbol**: otherwise, the symbol table's last `N_SECT` symbol at or before the address.
  Code the linker folded has several symbols there (aliases): with two or more local
  (non-external) aliases the function is `<deduplicated_symbol>` and the offset from the
  aliases' address. Otherwise the symbol is the first external alias in symbol table order,
  else the first alias.
- **DWARF frames**: the DWARF function whose ranges hold the address (`DW_AT_ranges` first;
  a compile unit's `DW_AT_low_pc` with them is only its base address), then the inlined calls
  (`DW_TAG_inlined_subroutine`, through lexical blocks) whose ranges hold it, recursively. The
  innermost frame's line is the line table row covering the address (the last row at or
  before it in its sequence); each outer frame's is the inner call's `DW_AT_call_file` and
  `DW_AT_call_line`. A frame's name is its linkage name (`DW_AT_linkage_name`, through
  `DW_AT_abstract_origin` and `DW_AT_specification`), demangled, else `DW_AT_name`. When the
  outermost function's linkage name is not the symbol's, the symbol's name replaces it.
- **Without a DWARF function**: the symbol at the line of the first compile unit whose ranges
  hold the address and whose line table covers it with a row starting at or after the symbol
  (units' ranges overlap: an expo-default address is in three), else the symbol and the
  offset into it, and nothing past the end of a DWARF function that starts at the symbol.
- **Files**: a path's last component; a file in `/` keeps its path (`/<compiler-generated>`).
- **Names**: Swift symbols in the Swift demangler's simplified form
  (`swift_demangle_getSimplifiedDemangledName` of the toolchain's `libswiftDemangle`:
  `Player.isDead.getter`, `outlined destroy of Monster`); C++ through LLVM's `__cxa_demangle`
  (libc++abi's: the system's on a Mac, Ubuntu's `libc++abi1` on Linux; GNU's libstdc++ words
  some names otherwise: `> >`, ABI tags left mangled), and a
  block in a C++ function (`___Z<function>_block_invoke`) as `invocation function for block in
  <function>`; Objective-C and C names as they are, without the leading underscore.

`nomac device symbolicate <report.ips> --dsym <dSYM, folder or .xcarchive>` prints the report:
process, identifier, OS, exception, termination, application-specific messages, the last
exception backtrace and every thread, the crashed one marked; a frame is `atos -i`'s lines for
an image whose UUID a dSYM has (even where the report names it: a Mac's crash reporter names a
simulator app's frames, without lines), else `<index> <image> <symbol> + <offset>` from the
report, else the image's offset. This layout is nomac's. End to end
(`symbolicate_experiments.py --report`): a self-written app (`nomac archive`, an Objective-C
exception three calls deep in a framework) crashed on the iPhone; its report, copied with
`nomac device crashes`, symbolicated with the archive's dSYMs gives every app frame (6) as
`atos -i` does at the frame's address; the same app's simulator report, 7 of 7.
`symbolicate_experiments.py --crash-demo` repeats both: on a simulator it creates and deletes,
or with `--device` and an archive of the app nomac built and signed.

## Reading the device's reports

From libimobiledevice's public description of `idevicecrashreport`, confirmed on an iPhone on
iOS 27.0.1 (2026-11-03: `nomac device crashes` listed the reports newest first and copied one
byte for byte as `devicectl` does): lockdownd's `com.apple.crashreportmover` moves the reports written since it last ran and sends
`ping` (4 bytes) when done; `com.apple.crashreportcopymobile` then serves the reports' folder
over AFC (docs/formats/afc.md), `.ips` files at its root and in folders such as `Retired`. AFC's
`ReadDirectory` (`0x03`) lists names ending in zero bytes, `.` and `..` included;
`GetFileInfo` (`0x0a`) gives zero-ended key and value strings (`st_size`, `st_ifmt` `S_IFREG` or
`S_IFDIR`, `st_mtime` in nanoseconds); `FileOpen` in mode 1 (read only), `FileRead` (`0x0f`,
the handle and a length) and `FileClose` read a file.

## The console

From public descriptions of CoreDevice's app service, confirmed on the same iPhone
(2026-11-03: a React Native app's log lines streamed; a self-written app's output, then its
uncaught exception's message, then the connection closed as the app died): RemoteService
Discovery lists `com.apple.coredevice.openstdiosocket`; a connection to it first sends a
16-byte identifier, and a launch whose `standardIOIdentifiers` name it (as an XPC UUID) for
`standardInput`, `standardOutput` and `standardError` writes the process's standard streams
to that connection (a pseudoterminal, `standardIOUsesPseudoterminals`) until the process exits.
When the connection fails instead, `nomac launch --console` asks the app service's
`listprocesses` in a new session and says which happened: the app exited, or the device closed
the console while the app keeps running (with `nomac stop` to stop it).
