# AFC, the Apple File Conduit

`com.apple.afc`, started through lockdownd (docs/formats/lockdown.md), reads and writes files
in the device's media folder. Sources: libimobiledevice (`afc.c`, `afc.h`) and pymobiledevice3
(`services/afc.py`). nomac implements what an install needs in `Sources/NomacDevice/AFC.swift`.

## Packets

A packet, request or reply, is a 40-byte header of little-endian fields, its operands, then
its data:

| Offset | Field |
|---|---|
| 0 | `CFA6LPAA` |
| 8 | entire length: header, operands and data |
| 16 | this length: header and operands |
| 24 | packet number, counted from 0 by the client and repeated in the reply |
| 32 | operation |

Operands of path operations are the path in UTF-8 and a NUL; a write's operand is the file
handle (8 bytes) and its data the bytes written, so its this length is 48.

| Operation | Code | Operands | Reply |
|---|---|---|---|
| status (reply) | 0x01 | an 8-byte status, 0 for success | |
| remove path | 0x08 | path | status |
| make directory (with its parents) | 0x09 | path | status |
| open | 0x0d | mode (8 bytes; 3 writes, creates and truncates), path | 0x0e, the handle (8 bytes) |
| write | 0x10 | handle; data: bytes | status |
| close | 0x14 | handle | status |

Statuses nomac names: 7 invalid argument, 8 object not found, 9 object is a directory,
10 permission denied, 16 object exists, 18 no space left. nomac writes files in 1 MiB writes.
