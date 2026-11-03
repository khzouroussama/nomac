# ADR 0401: TLS for lockdownd's sessions with swift-nio-ssl

- Status: proposed (extends ADR 0002 and ADR 0400)
- Date: 2026-10-30

## Context

After `StartSession`, lockdownd asks for TLS on the rest of the connection
(`EnableSessionSSL`); some services ask for it too (`EnableServiceSSL`). The client presents
the host certificate and key of the pair record and does not verify the device's certificate,
which the device issued itself at pairing (pymobiledevice3's `create_ssl_context`: TLS 1.2 to
1.3, no verification). Installing an app needs a session, so `nomac install` needs a TLS
client with a client certificate on Linux and macOS.

Foundation has no TLS client off Apple platforms. swift-crypto's BoringSSL is built without
its `ssl` library. Writing a TLS client in nomac would be a security-sensitive reimplementation
with nothing to observe it against but the device.

## Decision

nomac uses apple/swift-nio-ssl (BoringSSL's TLS, vendored with its symbols prefixed, so it sits
beside swift-crypto's copy) with swift-nio's `EmbeddedChannel`: `TLSStream` feeds BoringSSL
one TLS record at a time from nomac's blocking stream and writes what it produces back, so no
event loop or thread is added and nothing past the handshake is read before it is needed. The
device's certificate is accepted by a verification callback that accepts every certificate:
with verification `.none`, swift-nio-ssl's client never sends its second flight in an embedded
channel (observed in nomac's tests, TLS 1.2 and 1.3 alike). The pins are exact (`swift-nio`
2.104.0, `swift-nio-ssl` 2.37.5), recorded in `Package.resolved`.

## Consequences

- The same TLS code runs on macOS and Linux; the Mac's Security framework is not used.
- Builds compile BoringSSL's TLS library once more (swift-nio-ssl's copy).
- `TLSStream` is checked in tests against swift-nio-ssl's own server with a self-made identity,
  and on the owner's iPhone once a session is started with the Mac's pair record (approved by
  the owner, 2026-10-30, read-only).
