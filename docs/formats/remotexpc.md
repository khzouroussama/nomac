# The CoreDevice tunnel and RemoteXPC

Since iOS 17, developer services (launching apps among them) are RemoteXPC services inside a
tunnel to the device. Sources: pymobiledevice3 (`remote/xpc_message.py`, `remote/remotexpc.py`,
`remote/remote_service_discovery.py`, `remote/tunnel_service.py`) and go-ios. nomac implements
the encodings in `Sources/NomacDevice/XPC.swift`, `RemoteXPC.swift` and
`CoreDeviceTunnel.swift`; none has met the iPhone yet (B-403).

## The tunnel

lockdownd starts `com.apple.internal.devicecompute.CoreDeviceProxy` (iOS 17.4 and later, in a
session, docs/formats/lockdown.md). Each side sends one packet: `CDTunnel`, a big-endian 16-bit
length, then JSON. The client asks `{"type": "clientHandshakeRequest", "mtu": 16000}` (as
Python's `json.dumps` writes it); the device answers with `clientParameters` (`address`,
`netmask`, `mtu`), `serverAddress` and `serverRSDPort`. Afterwards the connection carries IPv6
packets: the host takes the client address, and RemoteServiceDiscovery listens on TCP
`serverRSDPort` (58783) of the server address. Packets follow each other without framing,
each read by its IPv6 header's payload length, and each written in one write (pymobiledevice3
measured the device's forwarding slowing down when packets are coalesced). nomac runs TCP over
them itself (`TunnelNetwork`, ADR 0402): segments with the RFC 1071 checksum over IPv6's
pseudo-header, an MSS option on SYN (the tunnel's MTU less 60), no window scaling. The device
probes an idle connection with keepalives every 10 seconds (no data, the sequence number one
before the next byte) and resets it after three without an ACK (the iPhone, 2026-11-03: a
console idle for 3 s got probes at 3, 13 and 23 s and a reset at 33 s); nomac acknowledges them,
as RFC 1122 4.2.3.6 asks, and the console then stayed open past 90 s of silence.

## RemoteXPC over HTTP/2

Each RemoteXPC connection is HTTP/2 (RFC 9113) without TLS and without header blocks: the
client sends the preface `PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n`, then, in the order pymobiledevice3
records devicectl using (the device refuses another order):

1. SETTINGS: `MAX_CONCURRENT_STREAMS` (3) 100, `INITIAL_WINDOW_SIZE` (4) 16 MiB;
2. WINDOW_UPDATE on stream 0 by 16 MiB − 65,535;
3. HEADERS on stream 1, `END_HEADERS`, no header block;
4. DATA on stream 1: a message with flags 0x1 and an empty dictionary, message 0;
5. HEADERS on stream 3;
6. DATA on stream 1: a message with flags 0x201 and no body;
7. DATA on stream 3: a message with flags 0x400001 (`INIT_HANDSHAKE`) and no body.

The client then waits for the device's SETTINGS and acknowledges them. Requests go on stream 1,
their identifiers 0, then 1, 3, 5... (`(id + 1) | 1`); replies come on stream 3, other messages
on stream 1. Messages may span DATA frames (16,384 bytes each at most) and frames may hold
several messages.

## Messages

| Offset | Field |
|---|---|
| 0 | magic `0x29b00b92` (little-endian, as every field here) |
| 4 | flags: 0x1 always, 0x100 a non-empty dictionary, 0x10000 wanting a reply, 0x20000 a reply, 0x400000 the handshake |
| 8 | body size (64 bits) |
| 16 | message identifier (64 bits) |
| 24 | body: magic `0x42133742`, version 5, one XPC object |

## XPC objects

A 32-bit type, then:

| Type | Kind | Bytes |
|---|---|---|
| 0x1000 | null | none |
| 0x2000 | bool | 32 bits, 0 or 1 |
| 0x3000 | int64 | 64 bits |
| 0x4000 | uint64 | 64 bits |
| 0x5000 | double | 64 bits |
| 0x7000 | date | int64 nanoseconds since 1970 |
| 0x8000 | data | 32-bit length, the bytes, padding to 4 |
| 0x9000 | string | 32-bit length counting the NUL, UTF-8 and NUL, padding to 4 |
| 0xa000 | uuid | 16 bytes |
| 0xe000 | array | 32-bit byte count of what follows, 32-bit count, the objects |
| 0xf000 | dictionary | 32-bit byte count, 32-bit count, each key (UTF-8, NUL, padding to 4) then its object |

## RemoteServiceDiscovery

On connection RemoteServiceDiscovery sends a message whose dictionary has `MessageType`
`Handshake`, `Properties` (the device's values) and `Services`: per service name a dictionary
with `Port` (a string), the TCP port of that service in the tunnel.

## CoreDevice services

A CoreDevice service (`com.apple.coredevice.appservice` among them) is a RemoteXPC peer on
its port. A request, sent wanting a reply, is a dictionary with, in this order (as
pymobiledevice3's `core_device_service.py` sends it): `CoreDevice.CoreDeviceDDIProtocolVersion`
(int64 2), `CoreDevice.coreDeviceVersion` (`components` as uint64s, `originalComponentsCount`,
`stringValue`, `629.3`), `CoreDevice.deviceIdentifier` and `CoreDevice.invocationIdentifier`
(fresh UUID strings), `CoreDevice.input`, `CoreDevice.featureIdentifier` and an empty
`CoreDevice.action`. The reply has `CoreDevice.output`, or `CoreDevice.error` with `code` and
`userInfo.NSLocalizedDescription`.

Launching is the feature `com.apple.coredevice.feature.launchapplication` with the input
`applicationSpecifier.bundleIdentifier._0` and `options`: `arguments`,
`environmentVariables`, `standardIOUsesPseudoterminals` true, `startStopped` false,
`terminateExisting` true, `user.shortName` `mobile`, `platformSpecificOptions` (an XML property
list of an empty dictionary, as data); and an empty `standardIOIdentifiers`, or with a console
the identifier of an `openstdiosocket` connection for each standard stream
(docs/formats/crash-report.md). The output's
`processToken.processIdentifier` is the new process. The app service is listed only when the
Developer Disk Image is mounted.

To stop an app (`nomac stop`), from public descriptions of the app service, confirmed on an
iPhone on iOS 27.0.1 (2026-11-03: the app's process was gone after the signal): `com.apple.coredevice.feature.listprocesses` with an empty input lists `processTokens`,
each a `processIdentifier` and an `executableURL` (`relative`, a `file://` URL of the
executable); nomac picks those inside the app's `Path` (installation_proxy's `Lookup`,
docs/formats/lockdown.md; `/var` and `/private/var` alike) and sends each
`com.apple.coredevice.feature.sendsignaltoprocess` with `process.processIdentifier` and
`signal` (SIGTERM, 15, by default), one invocation per connection.

`nomac install` (and `nomac run`) stops an installed app's running processes before replacing it,
SIGTERM then SIGKILL after 5 s: the device ends them during the install itself (observed with
`devicectl device install app` and with installation_proxy, 2026-11-03), and nomac-expo-2 saw a
process launched right after such an install end 3 to 19 s in.
