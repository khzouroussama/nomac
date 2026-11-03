# ADR 0402: TCP in the CoreDevice tunnel, in userspace

- Status: proposed (extends ADR 0400)
- Date: 2026-10-30

## Context

After the CDTunnel handshake, lockdownd's CoreDeviceProxy connection carries raw IPv6
packets (docs/formats/remotexpc.md). RemoteServiceDiscovery and the CoreDevice services are TCP
ports of the device's tunnel address, so `nomac run` needs TCP over those packets.

pymobiledevice3 offers two ways: a kernel TUN interface (root, or `CAP_NET_ADMIN` and
`/dev/net/tun` in a container, plus routes) and, since its userspace backend, a TCP/IP stack in
the process (PyTCP). go-ios uses gVisor's userspace stack.

## Decision

nomac runs TCP itself, in `TunnelNetwork`: IPv6 packets with TCP segments (RFC 8200, RFC
9293, checksums per RFC 1071), one connection per service, multiplexed by local port over the
tunnel stream, read one packet at a time by its payload length. The tunnel's carrier is TCP
through usbmuxd (or the network), reliable and ordered, so nomac keeps no retransmission
timers and drops out-of-order segments with a duplicate acknowledgement; it sends no more than
the device's window and acknowledges each segment it receives, advertising a 65,535-byte window
without window scaling. No root, no TUN device and no new dependency are needed, on Linux, in a
container and on macOS alike.

## Consequences

- A segment the device drops (it should not, on a reliable carrier and within its window) is
  not resent: the read fails after the tunnel socket's 120-second timeout. If the iPhone shows
  otherwise, retransmission is added with its timers.
- Throughput is bounded by the unscaled window; the services `nomac run` uses exchange small
  messages.
- The tests check the packet format (a checksum computed separately) and the exchanges against
  a scripted device; the iPhone checks the rest (B-403).
