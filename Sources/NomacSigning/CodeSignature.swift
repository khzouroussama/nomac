import Crypto
import Foundation
import NomacCore

/// The blobs of an embedded code signature, as codesign writes them for ad-hoc signing.
///
/// Magic numbers, slot numbers and the `CS_CodeDirectory` layout are those of the public xnu
/// header `<kern/cs_blobs.h>`; which blobs codesign writes, their order and every value below
/// were observed in Xcode 27.0's codesign output (docs/formats/code-signature.md). All
/// integers in the blobs are big-endian.
enum CodeSignature {
    static let superBlobMagic: UInt32 = 0xfade_0cc0
    static let codeDirectoryMagic: UInt32 = 0xfade_0c02
    static let requirementsMagic: UInt32 = 0xfade_0c01
    static let requirementMagic: UInt32 = 0xfade_0c00
    static let entitlementsMagic: UInt32 = 0xfade_7171
    static let derEntitlementsMagic: UInt32 = 0xfade_7172
    static let wrapperMagic: UInt32 = 0xfade_0b01

    enum Slot: UInt32 {
        case codeDirectory = 0
        case infoPlist = 1
        case requirements = 2
        case resources = 3
        case entitlements = 5
        case derEntitlements = 7
        /// The SHA-256 code directory beside a SHA-1 one (`CSSLOT_ALTERNATE_CODEDIRECTORIES`).
        case alternateCodeDirectory = 0x1000
        case signature = 0x10000
    }

    /// `kSecCodeSignatureAdhoc`, set for ad-hoc signatures only.
    static let adHocFlag: UInt32 = 0x2
    /// The code directory version codesign writes: 0x20400, with the executable segment fields.
    static let codeDirectoryVersion: UInt32 = 0x20400
    /// The size of a version 0x20400 `CS_CodeDirectory` header; the identifier follows it.
    static let codeDirectoryHeaderSize = 88
    /// The hashes of a code directory: SHA-256 (`CS_HASHTYPE_SHA256`), the only one for iOS 12.2
    /// to 18.0 and watchOS from 12.0, and SHA-1 (`CS_HASHTYPE_SHA1`), first beside it for watchOS
    /// below 12.0 (observed).
    enum HashType: UInt8 {
        case sha1 = 1
        case sha256 = 2

        var size: Int { self == .sha1 ? 20 : 32 }

        func hash(_ bytes: [UInt8]) -> [UInt8] { self == .sha1 ? CodeSignature.sha1(bytes) : CodeSignature.sha256(bytes) }
    }

    /// `CS_EXECSEG_MAIN_BINARY`, set for `MH_EXECUTE` files.
    static let mainBinaryFlag: UInt64 = 0x1

    /// Executable segment flags codesign derives from boolean entitlements set to true
    /// (observed one entitlement at a time; `com.apple.security.cs.debugger` and
    /// `com.apple.security.cs.allow-jit` set none).
    static let entitlementExecutableSegmentFlags: [(String, UInt64)] = [
        ("get-task-allow", 0x10),
        ("dynamic-codesigning", 0x40),
        ("com.apple.private.skip-library-validation", 0x80),
        ("com.apple.private.amfi.can-load-cdhash", 0x100),
        ("com.apple.private.amfi.can-execute-cdhash", 0x200),
    ]

    /// An empty requirement set: an ad-hoc signature has no designated requirement.
    static let emptyRequirements = blob(requirementsMagic, [0, 0, 0, 0])

    /// The signature slot of an ad-hoc signature: an empty wrapper blob.
    static let emptySignature = blob(wrapperMagic, [])

    /// `payload` behind a magic number and the blob's total length.
    static func blob(_ magic: UInt32, _ payload: [UInt8]) -> [UInt8] {
        var writer = BigEndianWriter()
        writer.uint32(magic)
        writer.uint32(UInt32(payload.count + 8))
        writer.bytes += payload
        return writer.bytes
    }

    /// A super blob of `blobs` in the given order, each indexed by its slot.
    static func superBlob(_ blobs: [(Slot, [UInt8])]) -> [UInt8] {
        let headerSize = 12 + 8 * blobs.count
        var writer = BigEndianWriter()
        writer.uint32(superBlobMagic)
        writer.uint32(UInt32(headerSize + blobs.reduce(0) { $0 + $1.1.count }))
        writer.uint32(UInt32(blobs.count))
        var offset = headerSize
        for (slot, blob) in blobs {
            writer.uint32(slot.rawValue)
            writer.uint32(UInt32(offset))
            offset += blob.count
        }
        for (_, blob) in blobs { writer.bytes += blob }
        return writer.bytes
    }

    /// The bytes reserved for a signature whose super blob, with an empty signature blob, is
    /// `length` bytes long: 8 more for ad-hoc signing, 18000 more with a certificate, rounded up
    /// to 16. Observed for 16 ad-hoc lengths from 306 to 40634 bytes and for certificate
    /// signatures; 18000 is the CMS size estimate of Security's `CodeSigner.cpp`.
    static func allocatedSize(forLength length: Int, adHoc: Bool) -> Int {
        MachOImage.roundUp(length + (adHoc ? 8 : 18000), 16)
    }

    /// The requirement set holding the designated requirement of code signed by a certificate,
    /// as Security's `drmaker.cpp` builds it: for an iOS chain to Apple's root, `identifier
    /// <id> and anchor apple generic and certificate leaf[subject.CN] = <CN> and certificate
    /// 1[field.1.2.840.113635.100.6.2.1] exists`; for other roots, `identifier <id> and
    /// certificate <slot> = H"<SHA-1>"`. Opcodes and layout from Security's `requirement.h`
    /// (data as a length and bytes padded to 4, the root as certificate index -1), checked
    /// against codesign's output.
    static func designatedRequirement(identifier: String, identity: SigningIdentity) -> [UInt8] {
        var expression = BigEndianWriter()
        expression.uint32(1) // exprForm
        expression.uint32(6) // opAnd
        expression.uint32(2) // opIdent
        expression.data(Array(identifier.utf8))
        if identity.isApple {
            expression.uint32(6) // opAnd
            expression.uint32(15) // opAppleGenericAnchor
            expression.uint32(6) // opAnd
            expression.uint32(11) // opCertField
            expression.uint32(0) // the leaf
            expression.data(Array("subject.CN".utf8))
            expression.uint32(1) // matchEqual
            expression.data(Array((identity.leaf.commonName ?? "").utf8))
            expression.uint32(14) // opCertGeneric
            expression.uint32(1)
            expression.data(SigningIdentity.iOSIntermediateMarker)
            expression.uint32(0) // matchExists
        } else {
            // The last certificate up the chain whose organization is the leaf's, `root` when it
            // is the anchor (`DRMaker::nonAppleAnchor`).
            var slot = 0
            if let organization = identity.leaf.organization {
                while slot + 1 < identity.chain.count, identity.chain[slot + 1].organization == organization { slot += 1 }
            }
            expression.uint32(4) // opAnchorHash
            expression.uint32(slot == identity.chain.count - 1 ? 0xffff_ffff : UInt32(slot))
            expression.data(sha1(identity.chain[slot].der))
        }
        let requirement = blob(requirementMagic, expression.bytes)
        var set = BigEndianWriter()
        set.uint32(1)
        set.uint32(3) // kSecDesignatedRequirementType
        set.uint32(20)
        return blob(requirementsMagic, set.bytes + requirement)
    }

    /// The code directory of a detached signature: version 0x20100 (48-byte header, no scatter,
    /// team or executable segment), SHA-256, page size 0, `code` (the executable, else the
    /// Info.plist) hashed whole (`codeLimit` its size, one code slot), then the identifier and the
    /// special slots (observed, `CodeSignerTests.signsABundleWithoutCode`). With
    /// `--generate-pre-encrypt-hashes`, version 0x20500: the header runs to `preEncryptOffset`
    /// (96 bytes, the fields between zero), and the pre-encrypt hashes, equal to the code
    /// hashes, follow the identifier (signing experiments `framework-static`). Signed with a
    /// certificate, version 0x20200 (the header runs to `teamOffset`, 52 bytes) with the team
    /// identifier after the identifier (observed privately for B-302 with an Apple Development
    /// identity).
    static func detachedDirectory(identifier: String, flags: UInt32, code: [UInt8], specialSlots: [Slot: [UInt8]],
                                  preEncryptHashes: Bool = false, teamIdentifier: String? = nil) -> [UInt8] {
        let slotCount = Int(specialSlots.keys.map(\.rawValue).max() ?? 0)
        let headerSize = preEncryptHashes ? 96 : teamIdentifier == nil ? 48 : 52
        let identifierEnd = headerSize + identifier.utf8.count + 1
        let teamEnd = identifierEnd + (teamIdentifier.map { $0.utf8.count + 1 } ?? 0)
        let hashOffset = teamEnd + (preEncryptHashes ? 32 : 0) + 32 * slotCount
        var writer = BigEndianWriter()
        writer.uint32(codeDirectoryMagic)
        writer.uint32(UInt32(hashOffset + 32))
        writer.uint32(preEncryptHashes ? 0x20500 : teamIdentifier == nil ? 0x20100 : 0x20200)
        writer.uint32(flags)
        writer.uint32(UInt32(hashOffset))
        writer.uint32(UInt32(headerSize))
        writer.uint32(UInt32(slotCount))
        writer.uint32(1)
        writer.uint32(UInt32(code.count))
        writer.bytes += [32, HashType.sha256.rawValue, 0, 0]
        writer.uint32(0) // spare2
        writer.uint32(0) // scatterOffset
        if teamIdentifier != nil || preEncryptHashes {
            writer.uint32(teamIdentifier == nil ? 0 : UInt32(identifierEnd))
        }
        if preEncryptHashes {
            // spare3, codeLimit64, the executable segment and runtime: none.
            writer.bytes += [UInt8](repeating: 0, count: 40)
            writer.uint32(UInt32(teamEnd))
        }
        writer.bytes += Array(identifier.utf8) + [0]
        if let teamIdentifier { writer.bytes += Array(teamIdentifier.utf8) + [0] }
        if preEncryptHashes { writer.bytes += sha256(code) }
        for index in stride(from: slotCount, through: 1, by: -1) {
            writer.bytes += Slot(rawValue: UInt32(index)).flatMap { specialSlots[$0] }.map(sha256) ?? [UInt8](repeating: 0, count: 32)
        }
        writer.bytes += sha256(code)
        return writer.bytes
    }

    /// The identifier and flags of a detached signature's `CodeDirectory`, nil when malformed.
    static func detachedIdentity(_ data: Data) -> (identifier: String, flags: UInt32)? {
        let bytes = [UInt8](data)
        guard bytes.count >= 48 else { return nil }
        func word(_ at: Int) -> Int { bytes[at..<(at + 4)].reduce(0) { $0 << 8 | Int($1) } }
        let offset = word(20)
        guard offset < bytes.count else { return nil }
        return (String(decoding: bytes[offset...].prefix { $0 != 0 }, as: UTF8.self), UInt32(word(12)))
    }

    /// The fields of a code directory other than its code hashes.
    struct Directory {
        var identifier: String
        var flags: UInt32
        var codeLimit: Int
        /// The contents each special slot hashes: Info.plist, requirements, CodeResources, the
        /// entitlements blobs.
        var specialSlots: [Slot: [UInt8]]
        var executableSegmentBase: UInt64
        var executableSegmentLimit: UInt64
        var executableSegmentFlags: UInt64
        /// The page size as a power of two: 12 (4 KB) or 14 (16 KB).
        var pageSizeShift: UInt8
        var hashType = HashType.sha256
        /// The team identifier, written after the identifier (Apple-issued certificates).
        var teamIdentifier: String?

        /// The number of special slots: up to the highest one in use.
        var specialSlotCount: Int { Int(specialSlots.keys.map(\.rawValue).max() ?? 0) }

        var codeSlotCount: Int { (codeLimit + (1 << Int(pageSizeShift)) - 1) >> Int(pageSizeShift) }

        var teamSize: Int { teamIdentifier.map { $0.utf8.count + 1 } ?? 0 }

        /// The size of the code directory blob.
        var size: Int {
            codeDirectoryHeaderSize + identifier.utf8.count + 1 + teamSize + (specialSlotCount + codeSlotCount) * hashType.size
        }

        /// The code directory of `code`, the file's bytes up to the signature.
        func blob(code: [UInt8]) -> [UInt8] {
            let identifierOffset = codeDirectoryHeaderSize
            let teamOffset = identifierOffset + identifier.utf8.count + 1
            let hashOffset = teamOffset + teamSize + specialSlotCount * hashType.size
            var writer = BigEndianWriter()
            writer.uint32(codeDirectoryMagic)
            writer.uint32(UInt32(size))
            writer.uint32(codeDirectoryVersion)
            writer.uint32(flags)
            writer.uint32(UInt32(hashOffset))
            writer.uint32(UInt32(identifierOffset))
            writer.uint32(UInt32(specialSlotCount))
            writer.uint32(UInt32(codeSlotCount))
            writer.uint32(UInt32(codeLimit))
            writer.bytes += [UInt8(hashType.size), hashType.rawValue, 0, pageSizeShift]
            writer.uint32(0) // spare2
            writer.uint32(0) // scatterOffset
            writer.uint32(teamIdentifier == nil ? 0 : UInt32(teamOffset))
            writer.uint32(0) // spare3
            writer.uint64(0) // codeLimit64
            writer.uint64(executableSegmentBase)
            writer.uint64(executableSegmentLimit)
            writer.uint64(executableSegmentFlags)
            writer.bytes += Array(identifier.utf8) + [0]
            if let teamIdentifier { writer.bytes += Array(teamIdentifier.utf8) + [0] }
            for index in stride(from: specialSlotCount, through: 1, by: -1) {
                writer.bytes += Slot(rawValue: UInt32(index)).flatMap { specialSlots[$0] }.map(hashType.hash)
                    ?? [UInt8](repeating: 0, count: hashType.size)
            }
            let pageSize = 1 << Int(pageSizeShift)
            code.withUnsafeBytes { buffer in
                for start in stride(from: 0, to: codeLimit, by: pageSize) {
                    let page = UnsafeRawBufferPointer(rebasing: buffer[start..<min(start + pageSize, codeLimit)])
                    switch hashType {
                    case .sha1:
                        var hasher = Insecure.SHA1()
                        hasher.update(bufferPointer: page)
                        writer.bytes.append(contentsOf: hasher.finalize())
                    case .sha256:
                        var hasher = Crypto.SHA256()
                        hasher.update(bufferPointer: page)
                        writer.bytes.append(contentsOf: hasher.finalize())
                    }
                }
            }
            return writer.bytes
        }
    }

    /// The SHA-256 digest of `bytes`.
    static func sha256(_ bytes: [UInt8]) -> [UInt8] {
        Array(Crypto.SHA256.hash(data: bytes))
    }

    /// The SHA-1 digest of `bytes`.
    static func sha1(_ bytes: [UInt8]) -> [UInt8] {
        Array(Insecure.SHA1.hash(data: bytes))
    }
}

/// Appends big-endian integers to a byte array.
struct BigEndianWriter {
    var bytes: [UInt8] = []

    mutating func uint32(_ value: UInt32) {
        bytes += [UInt8(value >> 24), UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]
    }

    mutating func uint64(_ value: UInt64) {
        uint32(UInt32(value >> 32))
        uint32(UInt32(truncatingIfNeeded: value))
    }

    /// A length, then `data` padded with zeros to a multiple of 4.
    mutating func data(_ data: [UInt8]) {
        uint32(UInt32(data.count))
        bytes += data + [UInt8](repeating: 0, count: (4 - data.count % 4) % 4)
    }
}
