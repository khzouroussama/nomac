# usbmuxd's protocol

usbmuxd multiplexes TCP connections to an iOS device's ports over USB and lists the devices
it sees, by USB and on the network. macOS's usbmuxd listens on `/var/run/usbmuxd`; on Linux,
libimobiledevice's usbmuxd on the same path speaks the same protocol. Sources: libusbmuxd's
and usbmuxd's sources (`usbmuxd-proto.h`), and observation of macOS 27.0.1's usbmuxd
(`.github/scripts/device_experiments.py`, 2026-10-30) and of libimobiledevice's usbmuxd 1.1.1
from Ubuntu 24.04, run in a container with no device (the same script, 2026-11-02). nomac implements it in
`Sources/NomacDevice/USBMux.swift`.

## Messages

Each message, request or reply, is a 16-byte header of four little-endian 32-bit integers and
a body:

| Offset | Field | Value |
|---|---|---|
| 0 | length | header and body, in bytes |
| 4 | version | 1 |
| 8 | message type | 8, a property list |
| 12 | tag | chosen by the client, echoed in the reply |

The body is an XML property list. A request's dictionary has `MessageType` and the client
fields libusbmuxd sends: `ClientVersionString`, `ProgName` and `kLibUSBMuxVersion` (3).
macOS's usbmuxd answers with a CoreFoundation-written XML property list, version 1, type 8
and the request's tag (observed).

## Requests and replies

- `ListDevices`: the reply is `{DeviceList: [...]}`, one dictionary per device with
  `DeviceID` (an integer for later requests), `MessageType` `Attached` and `Properties`:
  `ConnectionType` (`USB` or `Network`), `SerialNumber` (the UDID) and further keys (location,
  product and speed). Observed with no device attached: `{DeviceList: []}`; nomac reads
  `DeviceID`, `SerialNumber` and `ConnectionType`, which an attached iPhone gave through macOS's.
- `ReadBUID`: `{BUID: <string>}`, the host's system BUID, from both.
- `SavePairRecord` with `PairRecordID`, `PairRecordData` (an XML or binary property list; libusbmuxd
  sends binary, nomac XML) and `DeviceID`: libimobiledevice's usbmuxd writes
  `/var/lib/lockdown/<UDID>.plist`, as XML. Its `Result` says nothing: 2 with the record written on
  Ubuntu 24.04 and 25.10 and Debian 13, 0 on Ubuntu 22.04, Debian 12, Fedora 43, Arch and openSUSE
  Tumbleweed; 22 without data (`first_run_experiments.py`). nomac checks by starting a session.
- `DeletePairRecord` with `PairRecordID`: `Result` 0, then 2 once there is none.
- `ReadPairRecord` with `PairRecordID` (the UDID): `{PairRecordData: <data>}`, an XML property
  list from both (macOS's adds `EscrowBag`, which nomac does not send, docs/formats/lockdown.md).
  libimobiledevice's usbmuxd serves `/var/lib/lockdown/<UDID>.plist` as it is, and writes
  `/var/lib/lockdown/SystemConfiguration.plist` when it starts. A UDID without a record gets
  `Result` 22 from macOS's usbmuxd and 2 from libimobiledevice's.
- Any other request is answered with `{MessageType: Result, Number: n}`: 0 success,
  1 bad command (observed for an unknown `MessageType` from both), 2 bad device,
  3 connection refused, 6 bad version.

## On Linux

Observed with no device (`first_run_experiments.py`, 2026-11-06), usbmuxd 1.1.1 or a later
snapshot from Ubuntu 22.04, 24.04 and 25.10, Debian 12 and 13, Fedora 42 and 43, Arch and openSUSE
Tumbleweed, each from a package named `usbmuxd`:

- The executable is in `/usr/sbin` (Fedora and Arch: `/usr/bin`, linked from `/usr/sbin`), which a
  user's `PATH` may not hold.
- It runs only while needed: udev starts the `usbmuxd` service when an Apple device appears
  (`39-usbmuxd.rules`, products `5ac/12[9a]x`, newer packages also `5ac/190[1-5]`), and `usbmuxd -x`
  ends it when the last one leaves. So no socket does not mean not installed.
- No daemon: no socket, `connect` gives `ENOENT`. A killed daemon leaves its socket: `ECONNREFUSED`.
  The socket is mode 666 once it runs; a stricter one gives another user `EACCES`.
- `/var/lib/lockdown` appears when it first runs. It lists `ListDevices` `{DeviceList: []}` with no
  device, and answers `Connect` to an unknown device with `Result` 2.
- Its preflight (`preflight.c`) connects to each new device. An unpaired one gets `Pair`, which
  raises the Trust dialog; the device is listed anyway, and when the user taps Trust usbmuxd pairs
  and saves the record itself. If that first connection fails, the device is never listed, which is
  why the kernel can see an iPhone usbmuxd does not.

`nomac device list`, `pair` and `status` say which of these holds (`USBMuxHost`).

## The socket

libusbmuxd and nomac read `USBMUXD_SOCKET_ADDRESS`: `UNIX:<path>` for another Unix socket,
`<host>:<port>` for TCP. With a TCP forward of the Mac's socket on the loopback interface, a
Docker container reaches the Mac's devices (ADR 0400): `nomac device list` was checked through
such a forward on the Mac, and a `ListDevices` from a Docker Desktop container to
`host.docker.internal` got the Mac's usbmuxd's reply (2026-10-30).
