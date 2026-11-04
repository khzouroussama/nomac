# Code signatures

What Xcode 27.0 (27A266a) writes when it signs an iOS product, ad-hoc (`-`) or with a
certificate, and how `nomac codesign` (module `NomacSigning`) reproduces it. Blob magic numbers,
slot numbers and the `CS_CodeDirectory` layout are those of the public xnu header
`<kern/cs_blobs.h>`; Apple's open-source Security release (`libsecurity_codesigning`,
`libsecurity_smime`, `libsecurity_utilities`) explains several rules below (ADR 0301);
everything was observed:

- **Xcode builds**: `signing_experiments.py adhoc` archives a self-written app with a framework
  and a share extension, with `CODESIGN` pointed at a wrapper that keeps every signing step's
  arguments and the product before and after codesign. `signing_experiments.py compare`
  replays each step with `nomac codesign` and compares the results file by file.
- **codesign on self-written inputs**: Mach-O files and bundles built byte by byte by the
  NomacSigning tests (`SyntheticBundle`, `SyntheticMachO`), signed by codesign through
  `signing_experiments.py synthetic`: executables, libraries and loadable bundles, file names
  that give each default identifier, files without `LC_UUID`, every entitlement value type and
  the entitlements that set `execSegFlags`, an unaligned `__LINKEDIT`, and certificate identities
  imported into a throwaway keychain.
- **Exports**: `signing_experiments.py` exports each experiment's archive, also with umask 002
  (`umask`), and `compare-export` runs `nomac export` on the same archives.
- **Watch apps**: the `watch` and `watch-appclip-script` experiments embed a watchOS app whose
  executable has an arm64 slice (watchOS 26.0) and an arm64_32 one (11.0); clang-built watchOS
  executables of each deployment target from 5.0 to 26.0, thin and universal, and
  `SyntheticMachO` files signed by codesign through `synthetic` give the thresholds below.

## Invocations (ad-hoc)

Swift Build runs `$(CODESIGN)` (default `/usr/bin/codesign`) for each CodeSign task and for the
Swift libraries it embeds. In an archive of an app embedding a framework and an extension, in
this order:

| Step | Arguments |
|---|---|
| framework target | `--force --sign - --generate-entitlement-der <UninstalledProducts>/Kit.framework` |
| extension target | `--force --sign - --generate-entitlement-der <UninstalledProducts>/Share.appex` |
| app target, embedded framework (`CodeSignOnCopy`) | `--force --sign - --preserve-metadata=identifier,entitlements,flags --generate-entitlement-der App.app/Frameworks/Kit.framework` |
| app target, Swift back-deployment library (`swift-stdlib-tool`) | `-r- --display <lib>`, `--force --sign - --verbose App.app/Frameworks/libswiftCompatibilitySpan.dylib`, `-r- --display <lib>` |
| app target | `--force --sign - --generate-entitlement-der App.app` |
| command-line tool target (`archive-products-tool`) | `--force --sign - --entitlements <Tool.xcent> --generate-entitlement-der Tool`, the `.xcent` holding `application-identifier` `""` and `keychain-access-groups` `[""]` |

Extensions are copied without being signed again. Swift Build's `EmbedSwiftStdLib` compares
the two `-r- --display` outputs and puts the copied library back when they are equal (its
open-source `EmbedSwiftStdLibTaskAction.swift`); the library is signed after every embedded
framework and before the app (`span` experiments). Through a link named `codesign`, `nomac`
runs as `nomac codesign`, which Swift Build can take as `CODESIGN`: `compare` replays the 138
steps of the experiments' archives, probes included, identically. With an entitlements file, Xcode refuses
ad-hoc signing for iOS ("requires a provisioning profile"), and also without
`AD_HOC_CODE_SIGNING_ALLOWED=YES PROVISIONING_PROFILE_REQUIRED=NO`.

`xcodebuild -exportArchive` signs again, nested code first, with
`-f -s - --entitlements <file> --preserve-metadata=identifier,flags,runtime,launch-constraints,library-constraints --generate-entitlement-der --strip-disallowed-xattrs -vvv <path>`
(its `Packaging.log`).

## Layout in the Mach-O file

- Without `LC_CODE_SIGNATURE`, codesign appends one (16 bytes) after the last load command
  (`ncmds` + 1, `sizeofcmds` + 16). With one, the signature is rewritten at its `dataoff`.
- The signature starts at the end of `__LINKEDIT` rounded up to 16 bytes (zero-filled in
  between); the code it hashes ends there (`codeLimit`).
- `datasize` is the super blob's length plus 8, rounded up to 16; the rest keeps what the file
  had there before, zeros past its old end (zeros for a new signature; the bytes of Apple's
  larger signature when Swift Build signs a back-deployment library again, `span`).
- `__LINKEDIT` grows to cover the signature; its `vmsize` becomes its `filesize` rounded up to
  16 KB, also when the signature shrinks.

## Super blob

`0xfade0cc0`, then the blobs in slot order, each indexed by `(slot, offset)`:

| Slot | Blob | When |
|---|---|---|
| 0 | code directory `0xfade0c02` | always |
| 2 | requirements `0xfade0c01`: an empty set, `fade0c01 0000000c 00000000` | always (ad-hoc) |
| 5 | entitlements `0xfade7171`: the entitlements file byte for byte | with entitlements, `MH_EXECUTE` only |
| 7 | DER entitlements `0xfade7172` | with entitlements, `MH_EXECUTE` only, with or without `--generate-entitlement-der` |
| 0x1000 | the SHA-256 code directory, when slot 0 holds a SHA-1 one | watchOS below 12.0 (below) |
| 0x10000 | signature wrapper `0xfade0b01`, empty (8 bytes) | always (ad-hoc) |

codesign leaves the entitlements out of libraries and loadable bundles (`MH_DYLIB`,
`MH_BUNDLE`) even when `--entitlements` is given: the export signs frameworks with an
entitlements file and their signature has none.

## Code directory

Version 0x20400 (88-byte header), flags `0x2` (ad-hoc, plus the old flags with
`--preserve-metadata=flags`), SHA-256 (`hashType` 2, 32-byte hashes; also for iOS 12.2 to
15.99), pages of 16 KB, or of 4 KB (`pageSize` 12) for iOS (`LC_BUILD_VERSION` platform 2)
below 16.0 and watchOS (platform 4) below 9.0 (clang-built libraries for iOS 12.2 to 18.0: 15.99
gives 4 KB, 16.0 16 KB; watchOS executables: 8.99 4 KB, 9.0 16 KB; other platforms not
observed), `platform` 0, no scatter, no team, `codeLimit64` 0. The identifier follows the
header; the special slots follow it in descending order (-n … -1), then one hash per page.

- Special slots: -1 SHA-256 of `Info.plist` (bundles; for a lone file, of the Info.plist linked
  into it, `__TEXT,__info_plist`), -2 of the requirements blob, -3 of
  `_CodeSignature/CodeResources` (bundles), -5 of the entitlements blob (header included), -7 of
  the DER blob; slots up to the highest one used, unused ones zero.
- `execSegBase`/`execSegLimit`: `__TEXT`'s `fileoff` and `filesize`. `execSegFlags`: 0x1 for
  `MH_EXECUTE`, plus, for entitlements set to `true`: `get-task-allow` 0x10,
  `dynamic-codesigning` 0x40, `com.apple.private.skip-library-validation` 0x80,
  `com.apple.private.amfi.can-load-cdhash` 0x100, `com.apple.private.amfi.can-execute-cdhash`
  0x200 (`com.apple.security.cs.debugger` and `com.apple.security.cs.allow-jit` add nothing).
- Identifier: `--identifier`, else the kept one with `--preserve-metadata=identifier`, else
  `CFBundleIdentifier` for a bundle, or of a lone file's linked-in Info.plist (Swift's
  back-deployment libraries: `com.apple.dt.runtime.swiftCompatibilitySpan`); for other lone
  files, the name up to the last dot, and when that
  has no dot, `-` and the hex of `"UUID"` followed by the 16 `LC_UUID` bytes (`lib.foo.dylib`:
  `lib.foo`; `a.b.c`: `a.b`; `tool.bin`: `tool-555549441b8e…`; `.hidden`: `-555549441b8e…`),
  or without `LC_UUID` of the SHA-1 of the 28-byte `mach_header` and the load commands as they
  were before signing (`MachORep::identificationFor` in Security's `machorep.cpp`).

Below watchOS 12.0 (11.99; arm64 and arm64_32 alike), slot 0 holds a code directory of SHA-1
hashes (`hashType` 1, 20-byte hashes, otherwise the same fields) and slot 0x1000 the SHA-256
one. Its special slots hash the same blobs with SHA-1. codesign's size estimate then counts one
index entry more than the super blob has (8 bytes; a watchOS executable signed again with
entitlements gets 16 bytes more than the blobs and that entry rounded up). With a certificate
(a universal watch executable signed with a self-made identity, `CertificateSigningTests`), each
slice's CMS signs the SHA-1 directory of slot 0 (its SHA-256 is the message digest); `cdhashes`
lists the SHA-1 directory's SHA-1 and the first 20 bytes of the SHA-256 directory's SHA-256,
and `1.2.840.113635.100.9.2` holds `SEQUENCE { sha1, <SHA-1> }` then `SEQUENCE { sha256,
<SHA-256> }`.

## Bundles without an executable

A bundle whose Info.plist has no `CFBundleExecutable` (an asset pack of on-demand resources) gets
a detached signature: `_CodeSignature/` (0755) holds `CodeResources` (as for other bundles,
the Info.plist left out like an executable), `CodeDirectory` (version 0x20100: a 48-byte header
without scatter, team or executable segment fields, ad-hoc flag, SHA-256, page size 0, the
identifier, three special slots, and one code slot, the Info.plist's hash, `codeLimit` its
size), `CodeRequirements` (the empty requirement set) and `CodeSignature`, empty ad hoc; all
0644. Messages and `--force` are as for other bundles (`signed bundle [<identifier>]`, `replacing
existing signature`, `is already signed`). Observed with a self-written pack
(`CodeSignerTests.signsABundleWithoutCode`) and in the `odr` exports; certificate signatures of
such bundles are not observed (B-303).

A bundle whose executable is not a Mach-O file (a static framework, whose binary is an `ar`
archive) gets the same detached signature with the executable as the code: one code slot, its
hash, `codeLimit` its size, the executable left out of `CodeResources`; codesign calls it
`signed bundle with generic [<identifier>]` (signing experiments `framework-static`,
`CodeSignerTests.signsAStaticFramework`).

`--generate-pre-encrypt-hashes`, which Swift Build adds as codesign's first argument when the
framework it signs is static or has no binary (its note: "Signing static framework with
--generate-pre-encrypt-hashes"), makes such a detached `CodeDirectory` version 0x20500: the
header runs to `preEncryptOffset` (96 bytes; team, `codeLimit64`, executable segment and
runtime fields zero), the identifier follows, then one pre-encrypt hash per code slot (the code
hashes themselves for an unencrypted binary), the special slots and the code slots. The same
for a bundle without an executable. nomac refuses the option on a Mach-O bundle, for which
Swift Build does not pass it.

A bundle's identifier is its `CFBundleIdentifier`, else its `CFBundleName`; without either,
codesign signing ad hoc takes the folder's name without its extension, a hyphen and a hash: the
identification of the main Mach-O slice signed alone (`UUID` and its LC_UUID, as for a file), or
the SHA-1 of a detached signature's code (the binary, or the Info.plist of a bundle without
one): `App-55554944…`, `Lib-1303d9be…` (observed with an app, a static framework and a bundle
without an executable; `CodeSignerTests.identifiesBundlesWithoutCFBundleIdentifier`).
Signed with a certificate, a detached signature has a version 0x20200 `CodeDirectory` without
flags whose header runs to `teamOffset` (52 bytes), the team identifier (of an Apple chain)
after the identifier; the designated requirement in `CodeRequirements`; and the CMS, without the
super blob's wrapper, in `CodeSignature`. With `--generate-pre-encrypt-hashes`, version 0x20500
with the team after the identifier and the pre-encrypt hashes after the team. Observed privately
with the nomac development identity on an asset pack and a static framework (every file
identical to codesign's at the same signing time), and with the self-made identities
(`CertificateSigningTests.signsDetachedBundlesWithACertificate`). A bundle without
`CFBundleIdentifier` and `CFBundleName` signed with a certificate is not observed (B-303).

When the build later replaces such a framework's binary with a linker-signed Mach-O one (the
copy embedded in the app) and signs it with `--preserve-metadata=identifier,entitlements,flags`,
codesign removes the old `CodeDirectory`, `CodeRequirements` and `CodeSignature`, keeps nothing
of the linker's signature (the identifier comes from the Info.plist, the `linker-signed` flag
goes) and embeds the signature as for any Mach-O bundle (`framework-static`'s embedded step).

## Universal files

A universal file (big-endian `fat_header` and `fat_arch` entries, `<mach-o/fat.h>`) is signed
slice by slice: each slice becomes what signing it alone with the file's identifier gives
(observed with clang-built arm64 and arm64e slices, both orders, and watch executables), except
that the SHA-1 code directory goes into every slice when one slice needs it (arm64_32 for
watchOS 11.0 with arm64 for 26.0: both slices have both; 26.0 with 26.0: neither) while each
slice keeps its own page size (5.0 with 26.0: 4 KB and 16 KB). The main slice, which gives the
default identifier's suffix and comes first in messages, is arm64e when there is one (codesign
on an Apple silicon Mac), else arm64, else the first. arm64_32 slices are 32-bit Mach-O files
(`MH_MAGIC`, CPU type `0x0200000c`, 28-byte header, `LC_SEGMENT` with 68-byte sections). The
header keeps each entry's CPU type and subtype, and its alignment except for ARM slices, written
with 2^14 (a lipo-made arm64 slice aligned to 2^15 comes back with 2^14); each slice is written
at the next multiple of its alignment after the previous one, zeros between, and the file ends
with the last slice. Messages name `Mach-O universal (arm64e arm64)` or `Mach-O universal (arm64
arm64_32)`, the main slice first whatever the order of the slices.

## Display (`-r- --display`)

`Executable=` and the file's real path (a bundle's executable) on standard error, and on
standard output `designated => ` and the designated requirement, as Security's open-source
`reqdumper.cpp` writes it (`identifier "com.apple…" and anchor apple`, `identifier t2 and
certificate root = H"…"`, an Apple Development signature's `… and anchor apple generic and
certificate leaf[subject.CN] = "…" and certificate 1[field.1.2.840.113635.100.6.2.1] /* exists
*/`; an identifier is quoted unless alphanumeric, not starting with a digit and no keyword;
field names may hold dots), or for code without one, `# designated => cdhash H"<cdhash>"` for each
slice, the main one first, joined by ` or `. Unsigned files: `<path>: code object is not signed
at all`, status 1. nomac prints the operators of these requirements (identifier, anchors,
anchor hashes, cdhash, and, or, not, certificate fields and fields by OID with their match
operators); timestamps and named anchors are not observed yet.

## DER entitlements

`[APPLICATION 16] { INTEGER 1, dict }` (`70 … 02 01 01 b0 …`). A dictionary is `[CONTEXT 16]`
(`b0`) holding `SEQUENCE { UTF8String key, value }` per entry, sorted by key; an array is a
`SEQUENCE`, a string a `UTF8String`, a boolean `BOOLEAN` (`ff` or `00`), an integer the shortest
two's-complement `INTEGER` (128 is `02 02 00 80`, -129 `02 02 ff 7f`). codesign refuses
`<data>` ("unknown exception"), `<real>` and `<date>` ("AMFIUnserializeXML: syntax error").

## `_CodeSignature/CodeResources`

For iOS bundles (no `Contents` folder) every file and symbolic link under the bundle is sealed,
except the main executable and `_CodeSignature/`; nested frameworks and extensions are sealed
file by file like resources (their own `_CodeSignature/CodeResources` included).

- `files`: the SHA-1 of each regular file (`<data>`, or `{hash, optional}`), no symbolic links.
- `files2`: `{hash2}` (SHA-256), with `optional` when the rule says so, or `{symlink: target}`.
  When the bundle's code gets a SHA-1 code directory (a watchOS 11.0 watch app), each file's
  entry also has its SHA-1 `hash` (an `Assets.car` in such a watch app, as Xcode's export sealed
  it: `distribution_experiments.py` `thinning` `watch-catalog`).
- A path takes the rule of highest weight among those whose pattern matches (weight 1 when
  none is given); `omit` leaves it out.

| Pattern | `rules` | `rules2` |
|---|---|---|
| `^.*` | true | true |
| `^.*\.lproj/` | optional, 1000 | optional, 1000 |
| `^.*\.lproj/locversion.plist$` | omit, 1100 | omit, 1100 |
| `^Base\.lproj/` | 1010 | 1010 |
| `^version.plist$` | true | |
| `.*\.dSYM($|/)` | | 11 |
| `^(.*/)?\.DS_Store$` | | omit, 2000 |
| `^Info\.plist$`, `^PkgInfo$` | | omit, 20 |
| `^embedded\.provisionprofile$`, `^version\.plist$` | | 20 |

The file is CoreFoundation's XML property list format: the XML declaration and DOCTYPE, tab
indentation, keys sorted, `<dict/>` when empty, `&`, `<` and `>` escaped, `<real>` as `%.17g`,
and `<data>` in base64 lines of `76 - 8 × depth` characters at the element's indentation
(depths 1 and 3, `plutil -convert xml1` through `synthetic`). A new `_CodeSignature` folder is
made 0755 and a new `CodeResources` 0644 whatever the umask; existing ones keep their modes
(an embedded framework copied under umask 002 keeps 0775 and 0664, `umask` experiment).

## Messages

codesign prints `<path>: replacing existing signature` when it replaces one, and with `-v`
`<path>: signed app bundle with Mach-O thin (arm64) [<identifier>]` (`app bundle` when
`CFBundlePackageType` is `APPL`, whatever the extension; `bundle` otherwise;
`signed Mach-O thin (arm64)` for a lone file). Without `--force`, an already signed file fails
with `<path>: is already signed` and status 1.

## Signing with a certificate

Observed with self-made identities (a self-signed certificate, a leaf issued by a self-made
root CA, two certificates whose names contain one another, and a chain shaped like an Apple
Development one: leaf, intermediate with Apple's iOS marker, root) in a throwaway keychain, on
self-authored Mach-O files and bundles (`CertificateSigningTests`), and privately with an
Apple Development identity of the owner's (below). nomac reads the identity from a PEM file
holding the RSA private key and the certificates (`--keychain <file>`; codesign's keychains do
not exist on Linux).

- `--sign` names the identity by its certificate's SHA-1 (all 40 hex digits, any case) or
  common name: the one equal to the name, else the only one containing it, both ignoring case
  (codesign's manual says case sensitive; codesign 27.0 is not). When several contain it and
  none is equal, codesign fails with `<name>: ambiguous (matches "<second>" and "<first>" in
  <keychain>)`, naming the first two matches in keychain order (nomac: the file's order);
  without a match, `<name>: no identity found`.

- The code directory has no ad-hoc flag (flags 0). For a chain to Apple's root (Security's
  `isAppleCA`: Apple Root CA, SHA-1 `611e5b66…6c60`) it carries the team identifier, the
  leaf's organizational unit (`OU`), NUL-terminated right after the identifier, `teamOffset`
  pointing at it; for other roots none, also with an `OU`.
- A lone file's default identifier gets no `-UUID…` suffix (`signer.cpp` adds it to ad-hoc
  identifiers only).
- Requirements: `fade0c01`, count 1, type 3 (designated) at offset 20, then `fade0c00`, kind
  1 and the expression (`requirement.h`; data as length and bytes padded to 4), as Security's
  `drmaker.cpp` builds it:
  - other roots: `identifier <id> and certificate <slot> = H"<SHA-1>"` (`opAnd` 6, `opIdent` 2,
    `opAnchorHash` 4), the slot being the last certificate up the chain whose organization
    (`O`) is the leaf's, printed `leaf` (0) or `root` (-1, written as -1): a leaf issued by a
    root of another organization gives `certificate leaf` (the Apple-shaped chain), one of the
    same organization `certificate root`;
  - an iOS chain to Apple's root (three certificates, the intermediate with the extension
    `1.2.840.113635.100.6.2.1`): `identifier <id> and anchor apple generic and certificate
    leaf[subject.CN] = "<leaf's common name>" and certificate
    1[field.1.2.840.113635.100.6.2.1] /* exists */` (`opAnd`, `opAppleGenericAnchor` 15,
    `opCertField` 11 with match equal, `opCertGeneric` 14 with match exists). Other chains to
    Apple's root (Developer ID, Mac) are refused (B-302).
- The chain goes up to a self-signed root; without one codesign fails ("unable to build chain to
  self-signed root for signer …", errSecInternalComponent).
- `datasize` is the super blob's length with an empty signature blob plus 18000 (the CMS size
  estimate of `CodeSigner.cpp`), rounded up to 16; the rest is zeros.
- The signature blob (`0xfade0b01`) holds a CMS ContentInfo: SignedData (version 1, SHA-256),
  the outer `SEQUENCE`, its `[0]`, the SignedData and the detached encapsulated content
  (`pkcs7-data` without content) in indefinite-length form, everything else in DER; the
  certificates of the chain, leaf to root; one SignerInfo (version 1, issuer and serial number,
  SHA-256, `sha256WithRSAEncryption`, RSA PKCS #1 v1.5) with five signed attributes: content
  type (`pkcs7-data`), signing time (`UTCTime`), message digest (SHA-256 of the code directory),
  `1.2.840.113635.100.9.2` (`SEQUENCE { sha256, the code directory's SHA-256 }`) and
  `1.2.840.113635.100.9.1` (an XML property list `{cdhashes: [<first 20 bytes>]}` in
  CoreFoundation's format). Certificates and attributes are sorted shorter first, then
  bytewise (`SecCmsUtilDERCompare`); the signature covers the attributes' DER `SET`.

Everything but the signing time and so the signature is deterministic; with the same time,
nomac's signatures are codesign's byte for byte. For the owner's Apple Development identity,
whose private key stays in the keychain (exporting it would be a risk the check does not need),
nomac built the signature of a self-written file from the public chain and codesign's signing
time, taking the RSA value from codesign's CMS: the file is codesign's byte for byte, and
`codesign --verify --strict` and `openssl cms -verify` (against the chain's root, Apple's
critical extensions ignored) accept it; one second later, with the same RSA value, both reject
it. The RSA value nomac computes itself is only checked that way, by verification, and byte for
byte with self-made keys.

## Signature records

An archive build (`ENABLE_SIGNATURE_AGGREGATION=YES`, which `xcodebuild archive` sets and `build`
does not) runs Swift Build's `builtin-collectSignature` on each xcframework a target uses, directly
or as a package's `binaryTarget`, and writes
`<name>.xcframework-<platform>[-<environment>].signature` beside the target's products
(`BuildProductsPath/Release-iphoneos/Vendor.xcframework-ios.signature`, the platform being the
slice's `SupportedPlatform`). The archive takes them (docs/formats/xcarchive.md "Signatures"). A
record is an XML property list from Foundation's `PropertyListEncoder`, its fields those of
`CodeSignatureInfo`. Observed with Xcode 27.0 (`signature_record_experiments.py`), on self-written
xcframeworks and SentryObjC-Static 9.32.0, signed by Apple Distribution: GetSentry LLC with a secure
timestamp:

| Key | Unsigned | `codesign -s -` | Self-signed certificate | Apple Distribution |
|---|---|---|---|---|
| `signed` | false | true | true | true |
| `bundleIndentifier` (so spelled) | absent | code directory's identifier | the same | the same |
| `source` | absent | `embedded` | `embedded` | `embedded` |
| `cdhashes` | absent | one per code directory | the same | the same |
| `certificates` | absent | absent | the certificate's DER | signer, intermediate, root |
| `signatureType` | absent | absent | `SelfSigned` | `AppleDeveloperProgram` |
| `signatureIdentifier` | absent | absent | SHA-256 of the certificate, uppercase hex | code directory's team |
| `isSecureTimestamp` | false | false | false | false |
| `metadata` | `library`, `platform` | the same | the same | the same |

`timestamp`, `mainExecutable` and `runtimeVersion` are never written, the secure timestamp of the
Apple Distribution signature included: Swift Build reads them as strings where
`SecCodeCopySigningInformation` gives a date, a URL and a number.

A bundle signature is read from `_CodeSignature` (Swift Build patch 11 off macOS, from these bytes;
every record compared is byte for byte Xcode's):

- Without `CodeDirectory` the bundle is unsigned, whatever else the folder holds (`direct-partial`).
- An xcframework has neither `CFBundleIdentifier` nor `CFBundleName`, so its identifier is
  `<name>-<SHA-1>` ad hoc, as above, and just `<name>` under a certificate (`direct-identity`,
  `direct-vendor`), which is what B-303 had not observed.
- `CodeDirectory` is a code directory blob as above, without a super blob. With
  `--digest-algorithm=sha1,sha256` (in either order; codesign refuses SHA-1 alone), `CodeDirectory` is
  the SHA-1 one and `CodeRequirements-1` the SHA-256 one; `cdhashes` lists them in that order
  (`direct-digests`). Each entry is the first 20 bytes of the blob's digest by its `hashType`. Other
  hash types are not observed and are refused off macOS.
- `CodeSignature` is a bare CMS `ContentInfo`, not a `0xfade0b01` blob, in the form of
  "Signing with a certificate" above; empty or absent, no certificates (`direct-nosignature`). The record
  orders the certificates from the signer, by the first `SignerInfo`'s issuer and serial number, to
  the self-signed root; the signature holds them sorted by size. On macOS that is `SecCode`'s chain, so
  off macOS a signature whose certificates do not reach a self-signed root is refused rather than
  given a chain that may be wrong.

What Xcode refuses, with `The signature of “<name>” cannot be verified.` and codesign's words as a
note, which fails `build` and `archive` alike:

| Case | Note | Off macOS |
|---|---|---|
| A file added, changed or removed after signing (`direct-tampered`, `-modified`, `-removed`) | `a sealed resource is missing or invalid` | accepted, with a warning (B-198) |
| `CodeRequirements` removed (`direct-norequirements`) | `invalid signature (code or signature have been modified)` | accepted, with a warning (B-198) |
| `CodeDirectory` cut short (`direct-corrupt`) | `unsupported type or version of signature` | refused |
| `CodeSignature` cut short (`direct-badcms`) | `Unknown format in import.` | refused |

A signed xcframework whose identity the project does not record gets the note `The identity of
“<name>” is not recorded in your project.`, unless it is ad hoc, which has no identity. With an
`expectedSignature` in the file reference, `<signature type>:<identifier>:<name>` with the name ignored
(`AppleDeveloperProgram:97JCY7859U:GetSentry LLC`), one that differs, or an unsigned xcframework, stops
`build` and `archive` with `“<name>” is not signed with the expected identity and may have been
compromised.` and the note `Expected team identifier: <team>` (`expected-*`, `build-expected-*`). Off
macOS the comparison is the same, against what the signature says of itself.

Off macOS `codesign -vvvv` does not run and nothing checks a signature's seals, its CMS signature or
its certificates, so a signature that is forged or no longer matches its files gets the record Xcode
would have refused to write, and an `expectedSignature` is compared against an unverified claim.
ProcessXCFramework says so in a warning for each signed xcframework: `The signature of “<name>” was
read but not verified: without `codesign`, its sealed resources and certificates are not checked.`
This warning is not Xcode's. A certificate that was revoked (`CSSMERR_TP_CERT_REVOKED`), or a chain
that `SecCode` would complete differently from the one in the signature, is not observed.

## Not covered yet

Provisioning profiles and Apple chains other than iOS ones (B-302), macOS style bundles and file names outside ASCII:
docs/BACKLOG.md B-302 to B-305; page sizes and hash types for platforms other than iOS and
watchOS.
