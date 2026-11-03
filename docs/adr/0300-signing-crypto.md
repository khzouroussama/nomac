# ADR 0300: Code signing in Swift, with swift-crypto for digests and signatures

- Status: accepted (extends ADR 0001 and ADR 0002); amended 2026-10-22 for certificate signing
- Date: 2026-10-21

## Context

An IPA matches Xcode's only if every signature in it does: the code directory of each Mach-O
file, the entitlements blobs and `_CodeSignature/CodeResources` (docs/formats/code-signature.md).
Signing hashes every 16 KB page of every executable with SHA-256 and every bundle file with
SHA-1 and SHA-256; signing with a certificate adds an RSA signature in a CMS structure.

ARCHITECTURE.md planned rcodesign (indygreg/apple-platform-rs) as a subprocess. Reproducing
codesign byte for byte needs control over every choice codesign makes (the identifier rules,
the allocation size, which blobs are written and in which order, the CodeResources rules and
their XML form), and those choices differ from rcodesign's own. The formats are small and
documented by `<kern/cs_blobs.h>` and by observation, so nomac writes them itself
(`NomacSigning`), in Swift as ADR 0001 prefers.

Foundation offers no digests off Apple platforms. `NomacCore` has a SHA-256 written for the
short strings of PIF identifiers; hashing whole apps needs a fast implementation, and SHA-1 and
RSA are needed too.

## Decision

`NomacSigning` depends on `Crypto` from apple/swift-crypto, declared at the revision SwiftPM
itself requires (`revision: "3.12.5"`, Package.swift), so the pin in `Package.resolved` does not
change and nothing new is fetched or compiled: SwiftPM's package graph already builds it. On
Apple platforms `Crypto` is CryptoKit; elsewhere it is BoringSSL. `_CryptoExtras` (RSA) is
added the same way for certificate signing.

Amendment (certificate signing): the CMS SignedData and the few X.509 fields signing reads
(serial number, issuer, subject, public key, common name) are written by hand in
`NomacSigning` instead of with apple/swift-asn1 and swift-certificates. codesign's CMS blob is
not DER: its outer structures use indefinite lengths and its sets are sorted shorter first, as
Security's encoder does (ADR 0301, docs/formats/code-signature.md); swift-certificates' CMS
encoder writes DER and cannot give those bytes, and reading five fields does not need an X.509
library. This keeps the dependency graph at SwiftPM's own.

rcodesign is dropped from the plan.

## Consequences

- No new download or build step; swift-crypto moves with SwiftPM's pin (ADR 0002).
- Signing speed is BoringSSL's or CryptoKit's, not a hand-written loop's.
- Every codesign behavior nomac reproduces is written down in docs/formats/code-signature.md
  and checked against codesign on self-written inputs (`NomacSigningTests`) and on Xcode's own
  signing steps (`signing_experiments.py compare`).
