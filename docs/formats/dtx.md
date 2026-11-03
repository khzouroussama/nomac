# DTX

The message protocol of Apple's developer services on a device: testmanagerd (XCTest) and
instruments' service hub speak it, over a TCP connection in the CoreDevice tunnel
(docs/formats/remotexpc.md) since iOS 17. Learned from the open-source implementations
pymobiledevice3 (`pymobiledevice3/dtx`) and go-ios (`ios/dtx_codec`); nomac implements it in
`Sources/NomacDeviceTest/DTX.swift` and `KeyedArchive.swift`. All integers are little-endian.

## Fragments

Every message is sent as one or more fragments, each a 32-byte header and a body:

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | magic `0x1F3D5B79` |
| 4 | 4 | header size, 32 (a larger value has extra header bytes, skipped) |
| 8 | 2 | fragment index |
| 10 | 2 | fragment count |
| 12 | 4 | body size of this fragment; for the first of several, the whole message's size |
| 16 | 4 | message identifier |
| 20 | 4 | conversation index: 0 for a message that starts a conversation, 1 for its reply |
| 24 | 4 | channel code (signed) |
| 28 | 4 | flags: bit 0, the sender expects a reply |

A message of at most 128 KiB is one fragment. A larger one is a header-only first fragment
(index 0, count n + 1, size = the whole message), then n fragments of at most 128 KiB.

## Messages

The reassembled body is a 16-byte message header, the auxiliary dictionary and the payload:

| Offset | Size | Field |
|---|---|---|
| 0 | 1 | type: 0 OK (an empty reply), 1 data, 2 dispatch (a method call), 3 object (a reply with a value), 4 error, 5 barrier, 6 primitive, 7 compressed |
| 1 | 3 | zero |
| 4 | 4 | auxiliary size |
| 8 | 8 | auxiliary size + payload size |

A dispatch's payload is the selector, an `NSString` in a keyed archive; its arguments are the
auxiliary dictionary's. A reply (`object`) carries the method's value as a keyed archive; an
error reply carries an archived `NSError`. Each side numbers the messages it starts from 1; a
reply repeats the identifier with conversation index 1.

## Auxiliary

`u32 0x1F0`, `u32 0`, `u64` length of what follows, then each argument after a null key
(`u32 10`). Arguments by type:

| Type | Layout |
|---|---|
| 1 string | `u32` length, UTF-8 |
| 2 buffer | `u32` length, bytes: a keyed archive, or empty for `nil` |
| 3 int32 | `i32` |
| 6 int64 | `i64` |
| 9 double | `f64` |
| 10 null | nothing |

A message without arguments has no auxiliary bytes at all.

## Channels

Channel 0 is the connection's own. `_requestChannelWithCode:identifier:` on channel 0 (an
`int32` code and an archived identifier string, expecting a reply) opens a channel to one of the
peer's services. Codes count up from 1 on each side; the peer's channels are kept as the
negation of the code it asked for. A message is written with the channel's code (from the
writer's side) when it starts a conversation, and with its negation when it replies, so a reader
negates the code of a conversation's start and keeps a reply's as is. A peer's channel request
is acknowledged with an OK reply. `_notifyOfPublishedCapabilities:` is the instruments
handshake; testmanagerd's connections work without it.

## Keyed archives

`NSKeyedArchiver`'s binary property list: `$archiver` `NSKeyedArchiver`, `$version` 100000,
`$top` `{root: UID}`, `$objects` starting with `$null`. An object is a dictionary with
`$class`, the UID of `{$classname, $classes}` (its class chain to `NSObject`); scalars an
object encodes with `encodeBool:`/`encodeInteger:`/`encodeDouble:` are inline, everything else
a UID. Foundation's classes: `NSArray` and `NSSet` (`NS.objects`), `NSDictionary` (`NS.keys`,
`NS.objects`), `NSUUID` (`NS.uuidbytes`, 16 bytes), `NSURL` (`NS.base`, `NS.relative`),
`NSDate` (`NS.time`, seconds since 2001), strings and numbers as plain objects. Foundation's own
`NSKeyedUnarchiver` reads what nomac writes (`KeyedArchiveTests`).
