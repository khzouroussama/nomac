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
  product and speed). Observed with no device attached: `{DeviceList: []}`. The properties of
  an attached iPhone are to be observed (B-400).
- `ReadBUID`: `{BUID: <string>}`, the host's system BUID, from both.
- `ReadPairRecord` with `PairRecordID` (the UDID): `{PairRecordData: <data>}`, an XML property
  list from both (macOS's adds `EscrowBag`, which nomac does not send, docs/formats/lockdown.md).
  libimobiledevice's usbmuxd serves `/var/lib/lockdown/<UDID>.plist` as it is, and writes
  `/var/lib/lockdown/SystemConfiguration.plist` when it starts. A UDID without a record gets
  `Result` 22 from macOS's usbmuxd and 2 from libimobiledevice's.
- Any other request is answered with `{MessageType: Result, Number: n}`: 0 success,
  1 bad command (observed for an unknown `MessageType` from both), 2 bad device,
  3 connection refused, 6 bad version.

## The socket

libusbmuxd and nomac read `USBMUXD_SOCKET_ADDRESS`: `UNIX:<path>` for another Unix socket,
`<host>:<port>` for TCP. With a TCP forward of the Mac's socket on the loopback interface, a
Docker container reaches the Mac's devices (ADR 0400): `nomac device list` was checked through
such a forward on the Mac, and a `ListDevices` from a Docker Desktop container to
`host.docker.internal` got the Mac's usbmuxd's reply (2026-10-30).
