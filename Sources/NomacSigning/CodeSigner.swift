import Foundation
import NomacCore

/// Signs bundles and Mach-O files as `codesign --sign -` does (ad-hoc), with the options
/// Xcode 27.0 passes to it (docs/formats/code-signature.md "Invocations").
public enum CodeSigner {
    /// What to sign and how; ``CodesignArguments`` reads it from codesign's command line.
    public struct Request: Equatable, Sendable {
        public var path: String
        /// `-` for ad-hoc signing, else the SHA-1 or common name of a certificate in `keychain`.
        public var identity: String
        /// `--keychain`: for nomac, a PEM file holding the RSA private key and the certificate
        /// chain of the identity (Linux has no keychains).
        public var keychain: String?
        /// The CMS signing time; the current time when nil.
        public var signingTime: Date?
        /// `--force`: replace an existing signature.
        public var force: Bool
        /// `--entitlements`: an XML property list file.
        public var entitlementsPath: String?
        /// `--preserve-metadata`: which parts of the existing signature to keep.
        public var preservedMetadata: Set<String>
        /// `--identifier`.
        public var identifier: String?
        /// `--verbose` given at least once.
        public var verbose: Bool
        /// `--generate-pre-encrypt-hashes`, which Swift Build passes for static and codeless
        /// frameworks (`CodeSignTaskAction`).
        public var preEncryptHashes: Bool

        public init(path: String, identity: String, keychain: String? = nil, signingTime: Date? = nil, force: Bool = false,
                    entitlementsPath: String? = nil, preservedMetadata: Set<String> = [], identifier: String? = nil, verbose: Bool = false,
                    preEncryptHashes: Bool = false) {
            self.path = path
            self.identity = identity
            self.keychain = keychain
            self.signingTime = signingTime
            self.force = force
            self.entitlementsPath = entitlementsPath
            self.preservedMetadata = preservedMetadata
            self.identifier = identifier
            self.verbose = verbose
            self.preEncryptHashes = preEncryptHashes
        }
    }

    /// Signs `request.path`; returns the lines codesign prints on standard error.
    public static func sign(_ request: Request) throws -> [String] {
        try sign(request, identity: request.identity == "-" ? nil : signingIdentity(request))
    }

    /// Signs `request.path` with `identity`, or ad hoc when it is nil.
    public static func sign(_ request: Request, identity: SigningIdentity?) throws -> [String] {
        let path = request.path.hasSuffix("/") && request.path.count > 1 ? String(request.path.dropLast()) : request.path
        if FileSystem.isDirectory(path) {
            return try signBundle(path, request, identity)
        }
        return try signFile(path, request, identity)
    }

    private static func signBundle(_ bundle: String, _ request: Request, _ identity: SigningIdentity?) throws -> [String] {
        let infoPath = bundle + "/Info.plist"
        guard let infoData = FileManager.default.contents(atPath: infoPath) else {
            throw NomacError("bundle format unrecognized, invalid, or unsuitable", path: bundle)
        }
        let info = try PropertyLists.readDictionary(at: infoPath)
        guard let executableName = info["CFBundleExecutable"] as? String else {
            return try signDetached(bundle, request, identity, info: info, infoData: [UInt8](infoData), code: nil)
        }
        let executablePath = bundle + "/" + executableName
        let executable = try read(executablePath)
        guard MachOContainer.isMachO(executable) else {
            return try signDetached(bundle, request, identity, info: info, infoData: [UInt8](infoData), code: (executableName, executable))
        }
        guard !request.preEncryptHashes else {
            throw NomacError("--generate-pre-encrypt-hashes on a Mach-O bundle is not observed from Xcode (Swift Build passes it for static and codeless frameworks only)",
                             path: bundle)
        }
        var container = try MachOContainer(bytes: executable, path: executablePath)
        let existing = try ExistingSignature(image: container.slices[container.mainIndex].image, path: executablePath)
        var messages = try checkReplacing(bundle, existing != nil, request)
        let main = container.slices[container.mainIndex].image
        guard let defaultIdentifier = bundleIdentifier(info) ?? (identity == nil ? defaultIdentifier(bundle, main, adHoc: true) : nil) else {
            throw NomacError("signing a bundle without CFBundleIdentifier or CFBundleName with a certificate is not observed yet (BACKLOG B-302)", path: bundle)
        }
        // A detached signature left by an earlier signing (a static framework's, whose binary the
        // build then replaced with a Mach-O one) goes; only CodeResources stays (signing experiments
        // `framework-static`, the embedded framework's signing step).
        for name in ["CodeDirectory", "CodeRequirements", "CodeSignature"] where FileSystem.isFile(bundle + "/_CodeSignature/" + name) {
            try FileManager.default.removeItem(atPath: bundle + "/_CodeSignature/" + name)
        }
        let resources = try CodeResources.document(bundle: bundle, executable: executableName,
                                                   withSHA1: container.slices.contains { $0.image.needsSHA1CodeDirectory })
        // codesign makes `_CodeSignature` 0755 and `CodeResources` 0644 whatever the umask, and
        // keeps the modes of existing ones (observed with umask 002, `umask` experiment).
        let folder = bundle + "/_CodeSignature"
        if !FileSystem.isDirectory(folder) {
            try FileSystem.createDirectory(folder)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder)
        }
        let resourcesPath = folder + "/CodeResources"
        let existingMode = (try? FileManager.default.attributesOfItem(atPath: resourcesPath))?[.posixPermissions] as? Int
        try writeFile(Data(resources), to: resourcesPath, mode: existingMode ?? 0o644)
        let identifier = resolvedIdentifier(request, existing) { defaultIdentifier }
        try signSlices(&container, request, identity, path: executablePath, identifier: identifier) { _ in
            [.infoPlist: [UInt8](infoData), .resources: resources]
        }
        try replaceContents(of: executablePath, with: container.bytes)
        if request.verbose {
            // "app bundle" for a CFBundlePackageType of APPL, whatever the extension (observed).
            let kind = info["CFBundlePackageType"] as? String == "APPL" ? "app bundle" : "bundle"
            messages.append("\(request.path): signed \(kind) with \(container.formatDescription) [\(identifier)]")
        }
        return messages
    }

    /// A lone file takes its identifier and the Info.plist slot from an Info.plist linked into
    /// it (`__TEXT,__info_plist`, as Swift's back-deployment libraries have; observed).
    private static func signFile(_ path: String, _ request: Request, _ identity: SigningIdentity?) throws -> [String] {
        var container = try MachOContainer(bytes: try read(path), path: path)
        let main = container.slices[container.mainIndex].image
        let existing = try ExistingSignature(image: main, path: path)
        var messages = try checkReplacing(path, existing != nil, request)
        let identifier = resolvedIdentifier(request, existing) {
            embeddedIdentifier(main) ?? defaultIdentifier(path, main, adHoc: identity == nil)
        }
        try signSlices(&container, request, identity, path: path, identifier: identifier) { image in
            image.infoPlist.map { [.infoPlist: $0] } ?? [:]
        }
        try replaceContents(of: path, with: container.bytes)
        if request.verbose {
            messages.append("\(request.path): signed \(container.formatDescription) [\(identifier)]")
        }
        return messages
    }

    /// Signs every slice as a thin file of its own, with the file's identifier (observed: each
    /// slice of a signed universal file is the thin file signed alone with that identifier).
    private static func signSlices(_ container: inout MachOContainer, _ request: Request, _ identity: SigningIdentity?, path: String,
                                   identifier: String, specialSlots: (MachOImage) -> [CodeSignature.Slot: [UInt8]]) throws {
        // A SHA-1 code directory goes into every slice when one slice needs it (observed).
        let withSHA1 = container.slices.contains { $0.image.needsSHA1CodeDirectory }
        for index in container.slices.indices {
            let image = container.slices[index].image
            try sign(&container.slices[index].image, request, identity, existing: ExistingSignature(image: image, path: path),
                     identifier: identifier, specialSlots: specialSlots(image), withSHA1: withSHA1)
        }
    }

    private static func embeddedIdentifier(_ image: MachOImage) -> String? {
        guard let plist = image.infoPlist,
              let info = try? PropertyListSerialization.propertyList(from: Data(plist), format: nil) as? [String: Any] else { return nil }
        return info["CFBundleIdentifier"] as? String
    }

    /// The identifier of a file signed without one: its name up to the last dot, and for ad-hoc
    /// signing, when that has no dot, `-` and the hex of "UUID" and the LC_UUID bytes, or without
    /// LC_UUID of the SHA-1 of the 28-byte `mach_header` and the load commands (observed:
    /// `lib.foo.dylib` is `lib.foo`, `a.b.c` is `a.b`, `tool.bin` and `noext` get
    /// `-555549441b8e…`, `.hidden` only the suffix, `tool` without LC_UUID `-f8d2feb4…`; `t2`
    /// signed with a certificate stays `t2`; Security's `signer.cpp` adds the suffix to ad-hoc
    /// identifiers only, and `machorep.cpp` hashes the header and commands).
    private static func defaultIdentifier(_ path: String, _ image: MachOImage, adHoc: Bool) -> String {
        let name = (path as NSString).lastPathComponent
        let stem = name.lastIndex(of: ".").map { String(name[..<$0]) } ?? name
        if stem.contains(".") || !adHoc { return stem }
        let identification: [UInt8]
        if let uuid = image.uuid {
            identification = Array("UUID".utf8) + uuid
        } else {
            identification = CodeSignature.sha1(Array(image.bytes[0..<28] + image.bytes[32..<(32 + image.commandsSize)]))
        }
        return stem + "-" + identification.map { String(format: "%02x", $0) }.joined()
    }

    /// `--identifier`, else the kept one with `--preserve-metadata=identifier`, else the default.
    /// A bundle without an executable (an asset pack) or whose executable is not Mach-O (a static
    /// framework's `ar` archive) gets a detached signature: its `_CodeSignature` holds
    /// `CodeDirectory` (the executable, else the Info.plist, as the code, one hash of it all),
    /// `CodeRequirements`, `CodeResources` and `CodeSignature`, empty ad hoc (observed:
    /// `CodeSignerTests.signsABundleWithoutCode`, the `odr` experiment's exports, signing
    /// experiments `framework-static`).
    private static func signDetached(_ bundle: String, _ request: Request, _ identity: SigningIdentity?, info: [String: Any],
                                     infoData: [UInt8], code: (name: String, bytes: [UInt8])?) throws -> [String] {
        guard identity == nil || bundleIdentifier(info) != nil else {
            throw NomacError("signing a bundle without CFBundleIdentifier or CFBundleName with a certificate is not observed yet (BACKLOG B-303)", path: bundle)
        }
        let stem = ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension
        let defaultIdentifier = bundleIdentifier(info)
            ?? stem + "-" + CodeSignature.sha1(code?.bytes ?? infoData).map { String(format: "%02x", $0) }.joined()
        let folder = bundle + "/_CodeSignature"
        let existing = FileManager.default.contents(atPath: folder + "/CodeDirectory").map(CodeSignature.detachedIdentity)
        var messages = try checkReplacing(bundle, existing != nil, request)
        let identifier = request.identifier ?? (request.preservedMetadata.contains("identifier") ? existing??.identifier : nil) ?? defaultIdentifier
        let flags = (request.preservedMetadata.contains("flags") ? (existing??.flags ?? 0) & ~CodeSignature.adHocFlag : 0)
            | (identity == nil ? CodeSignature.adHocFlag : 0)
        // With a certificate: the designated requirement in CodeRequirements, the team in the
        // code directory and the CMS, unwrapped, in CodeSignature (observed privately for B-302).
        let requirements = identity.map { CodeSignature.designatedRequirement(identifier: identifier, identity: $0) } ?? CodeSignature.emptyRequirements
        // The code is left out of the resources, the Info.plist when it is the code.
        let resources = try CodeResources.document(bundle: bundle, executable: code?.name ?? "Info.plist")
        if !FileSystem.isDirectory(folder) {
            try FileSystem.createDirectory(folder)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder)
        }
        let directory = CodeSignature.detachedDirectory(identifier: identifier, flags: flags, code: code?.bytes ?? infoData,
                                                        specialSlots: [.infoPlist: infoData, .requirements: requirements, .resources: resources],
                                                        preEncryptHashes: request.preEncryptHashes,
                                                        teamIdentifier: identity.flatMap { $0.isApple ? $0.leaf.organizationalUnit : nil })
        let signature = try identity.map { try CMSSignature.sign(codeDirectories: [(.sha256, directory)], identity: $0, time: request.signingTime ?? Date()) } ?? []
        for (name, contents) in [("CodeResources", resources), ("CodeDirectory", directory), ("CodeRequirements", requirements),
                                 ("CodeSignature", signature)] {
            let path = folder + "/" + name
            let mode = (try? FileManager.default.attributesOfItem(atPath: path))?[.posixPermissions] as? Int
            try writeFile(Data(contents), to: path, mode: mode ?? 0o644)
        }
        if request.verbose {
            let kind = (info["CFBundlePackageType"] as? String == "APPL" ? "app bundle" : "bundle") + (code == nil ? "" : " with generic")
            messages.append("\(request.path): signed \(kind) [\(identifier)]")
        }
        return messages
    }

    /// A bundle's identifier: `CFBundleIdentifier`, else `CFBundleName`; without either, codesign
    /// takes the folder's name and a hash, the Mach-O identification of a file signed alone, or
    /// the SHA-1 of a detached signature's code (observed: an app, a static framework and a
    /// bundle without an executable signed ad hoc, B-303).
    private static func bundleIdentifier(_ info: [String: Any]) -> String? {
        (info["CFBundleIdentifier"] as? String) ?? (info["CFBundleName"] as? String)
    }

    private static func resolvedIdentifier(_ request: Request, _ existing: ExistingSignature?, default makeDefault: () -> String) -> String {
        if let identifier = request.identifier { return identifier }
        if request.preservedMetadata.contains("identifier"), let existing, !existing.isLinkerSigned { return existing.identifier }
        return makeDefault()
    }

    private static func checkReplacing(_ path: String, _ signed: Bool, _ request: Request) throws -> [String] {
        guard signed else { return [] }
        guard request.force else { throw NomacError("is already signed", path: path) }
        return ["\(request.path): replacing existing signature"]
    }

    /// Lays out and writes the signature into `image`.
    private static func sign(_ image: inout MachOImage, _ request: Request, _ identity: SigningIdentity?, existing: ExistingSignature?,
                             identifier: String, specialSlots: [CodeSignature.Slot: [UInt8]], withSHA1: Bool) throws {
        let preserved = request.preservedMetadata
        let entitlements: Entitlements?
        if image.fileType != MachOImage.executeFileType {
            // codesign leaves entitlements out of libraries and bundles (MH_DYLIB, MH_BUNDLE),
            // also when given --entitlements (observed).
            entitlements = nil
        } else if let entitlementsPath = request.entitlementsPath {
            entitlements = try Entitlements(xml: try read(entitlementsPath), path: entitlementsPath)
        } else if preserved.contains("entitlements"), existing?.isLinkerSigned == false, let xml = existing?.entitlements {
            entitlements = try Entitlements(xml: xml, path: request.path)
        } else {
            entitlements = nil
        }
        let preservedFlags = preserved.contains("flags") && existing?.isLinkerSigned == false ? (existing?.flags ?? 0) & ~CodeSignature.adHocFlag : 0
        let flags = preservedFlags | (identity == nil ? CodeSignature.adHocFlag : 0)
        let requirements = identity.map { CodeSignature.designatedRequirement(identifier: identifier, identity: $0) } ?? CodeSignature.emptyRequirements

        var slots = specialSlots
        slots[.requirements] = requirements
        var blobs: [(CodeSignature.Slot, [UInt8])] = [(.requirements, requirements)]
        if let entitlements {
            let xmlBlob = CodeSignature.blob(CodeSignature.entitlementsMagic, entitlements.xml)
            let derBlob = CodeSignature.blob(CodeSignature.derEntitlementsMagic, try entitlements.der(path: request.entitlementsPath ?? request.path))
            slots[.entitlements] = xmlBlob
            slots[.derEntitlements] = derBlob
            blobs += [(.entitlements, xmlBlob), (.derEntitlements, derBlob)]
        }

        let codeLimit = image.signatureOffset
        let directory = CodeSignature.Directory(
            identifier: identifier, flags: flags, codeLimit: codeLimit, specialSlots: slots,
            executableSegmentBase: image.text.fileOffset, executableSegmentLimit: image.text.fileSize,
            executableSegmentFlags: (image.fileType == MachOImage.executeFileType ? CodeSignature.mainBinaryFlag : 0)
                | (entitlements?.executableSegmentFlags ?? 0),
            pageSizeShift: image.pageSizeShift,
            teamIdentifier: identity.flatMap { $0.isApple ? $0.leaf.organizationalUnit : nil })
        // With SHA-1, its code directory comes first and the SHA-256 one after the other blobs
        // (slots 0, 2, 5, 7, 0x1000, 0x10000; observed for watchOS below 12.0).
        var sha1Directory = directory
        sha1Directory.hashType = .sha1
        let directories = withSHA1 ? [sha1Directory, directory] : [directory]
        // codesign's estimate counts one index entry more with SHA-1 (observed: 16 bytes more
        // for a watchOS executable signed again with entitlements).
        let length = 12 + 8 * (blobs.count + 1 + directories.count + (withSHA1 ? 1 : 0)) + directories.reduce(0) { $0 + $1.size }
            + blobs.reduce(0) { $0 + $1.1.count } + CodeSignature.emptySignature.count
        let allocated = CodeSignature.allocatedSize(forLength: length, adHoc: identity == nil)
        let previous = try image.reserveSignature(size: allocated)
        let codeDirectories = directories.map { (hashType: $0.hashType, blob: $0.blob(code: image.bytes)) }
        let signature = try identity.map {
            CodeSignature.blob(CodeSignature.wrapperMagic,
                               try CMSSignature.sign(codeDirectories: codeDirectories, identity: $0, time: request.signingTime ?? Date()))
        } ?? CodeSignature.emptySignature
        let superBlob = CodeSignature.superBlob(withSHA1
            ? [(.codeDirectory, codeDirectories[0].blob)] + blobs + [(.alternateCodeDirectory, codeDirectories[1].blob), (.signature, signature)]
            : [(.codeDirectory, codeDirectories[0].blob)] + blobs + [(.signature, signature)])
        guard superBlob.count <= allocated else {
            throw NomacError("the signature (\(superBlob.count) bytes) is larger than the space codesign reserves (\(allocated) bytes)", path: request.path)
        }
        image.bytes += superBlob + previous[superBlob.count...]
    }

    /// The identity `request` names, from the PEM file given as its keychain.
    private static func signingIdentity(_ request: Request) throws -> SigningIdentity {
        guard let keychain = request.keychain else {
            throw NomacError("signing with a certificate needs --keychain <PEM file with the key and certificates>", path: request.path)
        }
        let identity = try SigningIdentity(named: request.identity, pem: String(decoding: try read(keychain), as: UTF8.self), path: keychain)
        // Of the chains to Apple's root, only iOS ones are observed; Developer ID and others get
        // other requirements.
        guard !identity.isApple || identity.isIOSChain else {
            throw NomacError("signing with this Apple-issued certificate is not supported yet (BACKLOG B-302)", path: keychain)
        }
        return identity
    }

    /// The entitlements in the current signature of the bundle or Mach-O file at `path`, as
    /// embedded (nil when it is unsigned or signed without entitlements).
    public static func entitlements(of path: String) throws -> [UInt8]? {
        var executable = path
        if FileSystem.isDirectory(path) {
            let info = try PropertyLists.readDictionary(at: path + "/Info.plist")
            guard let name = info["CFBundleExecutable"] as? String else { return nil }
            executable = path + "/" + name
        }
        let container = try MachOContainer(bytes: read(executable), path: executable)
        return try ExistingSignature(image: container.slices[container.mainIndex].image, path: executable)?.entitlements
    }

    /// Whether the bundle or Mach-O file at `path` is signed ad hoc (`CS_ADHOC` in its code
    /// directory's flags); false when it is unsigned or signed with a certificate.
    public static func isSignedAdHoc(_ path: String) throws -> Bool {
        var executable = path
        if FileSystem.isDirectory(path) {
            guard let name = try PropertyLists.readDictionary(at: path + "/Info.plist")["CFBundleExecutable"] as? String else { return false }
            executable = path + "/" + name
        }
        let container = try MachOContainer(bytes: read(executable), path: executable)
        return try ExistingSignature(image: container.slices[container.mainIndex].image, path: executable).map { $0.flags & CodeSignature.adHocFlag != 0 } ?? false
    }

    /// The common name of the certificate that signed the bundle or Mach-O file at `path` and the
    /// team identifier of its code directory; nil when it is unsigned or signed ad hoc. The leaf
    /// is the certificate of the CMS that issued none of the others.
    public static func signingCertificate(of path: String) throws -> (commonName: String, teamIdentifier: String?)? {
        var executable = path
        if FileSystem.isDirectory(path) {
            guard let name = try PropertyLists.readDictionary(at: path + "/Info.plist")["CFBundleExecutable"] as? String else { return nil }
            executable = path + "/" + name
        }
        let container = try MachOContainer(bytes: read(executable), path: executable)
        guard let signature = try ExistingSignature(image: container.slices[container.mainIndex].image, path: executable),
              let cms = signature.cms else { return nil }
        // codesign's CMS has its outer layers in indefinite-length form, which the reader walks as
        // siblings; the certificates are the `[0]` with contents.
        guard let set = DERReader.elements(cms).first(where: { $0.tag == 0xa0 && !$0.content.isEmpty }) else { return nil }
        let certificates = try DERReader.elements(set.content).map { try X509Certificate(der: $0.encoded, path: executable) }
        guard let leaf = certificates.first(where: { candidate in !certificates.contains { $0.issuer == candidate.subject && $0.der != candidate.der } }) else {
            return nil
        }
        return (leaf.commonName ?? "", signature.teamIdentifier)
    }

    /// The architecture names of the Mach-O file at `path` (`arm64`), a universal file's in the
    /// order of its slices.
    public static func architectures(of path: String) throws -> [String] {
        try MachOContainer(bytes: read(path), path: path).slices.map(\.image.architectureName)
    }

    /// The identifier in the current signature of the Mach-O file at `path`, nil when unsigned.
    public static func identifier(of path: String) throws -> String? {
        let container = try MachOContainer(bytes: read(path), path: path)
        return try ExistingSignature(image: container.slices[container.mainIndex].image, path: path)?.identifier
    }

    /// What `codesign -r- --display <path>` prints: `Executable=` and the real path of the file
    /// (of a bundle's executable) on standard error, and on standard output its designated
    /// requirement, or for code without one, `# designated => ` and the code directory hash of
    /// each slice, the main one first, joined by ` or ` (observed).
    public static func designatedRequirement(of path: String) throws -> (output: String, error: String) {
        let trimmed = path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path
        var executable = trimmed
        if FileSystem.isDirectory(trimmed) {
            guard let name = try PropertyLists.readDictionary(at: trimmed + "/Info.plist")["CFBundleExecutable"] as? String else {
                throw NomacError("bundle format unrecognized, invalid, or unsuitable", path: path)
            }
            executable = trimmed + "/" + name
        }
        let container = try MachOContainer(bytes: read(executable), path: executable)
        let order = [container.mainIndex] + container.slices.indices.filter { $0 != container.mainIndex }
        let signatures = try order.map { try ExistingSignature(image: container.slices[$0].image, path: path) }
        guard let main = signatures[0] else { throw NomacError("code object is not signed at all", path: path) }
        let text: String
        if let requirement = main.designatedRequirement {
            text = "designated => " + (try RequirementText.text(requirement, path: path))
        } else {
            text = "# designated => " + signatures.compactMap { $0 }.map {
                "cdhash H\"" + CodeSignature.sha256($0.codeDirectory).prefix(20).map { String(format: "%02x", $0) }.joined() + "\""
            }.joined(separator: " or ")
        }
        return (text + "\n", "Executable=\(FileSystem.resolvingSymbolicLinks(executable))\n")
    }

    /// What `--preserve-metadata` can keep from a file's current signature, and what
    /// `--display` shows of it.
    struct ExistingSignature {
        var identifier: String
        var flags: UInt32
        var entitlements: [UInt8]?
        var codeDirectory: [UInt8]
        /// The requirement of type 3 (designated) in the requirement set, if any.
        var designatedRequirement: [UInt8]?
        /// The CMS of a signature made with a certificate.
        var cms: [UInt8]?

        /// The team identifier in the code directory, if any (`teamOffset`, version 0x20200 on).
        /// A signature the linker wrote (`CS_LINKER_SIGNED`): `--preserve-metadata` keeps nothing
        /// of it, the identifier coming from the Info.plist and the flags reset (signing
        /// experiments `framework-static`: the embedded copy of a static framework, whose binary
        /// the build replaced with a linker-signed one, re-signed with
        /// `--preserve-metadata=identifier,entitlements,flags`).
        var isLinkerSigned: Bool { flags & 0x20000 != 0 }

        var teamIdentifier: String? {
            guard codeDirectory.count >= 52 else { return nil }
            let offset = codeDirectory[48..<52].reduce(0) { $0 << 8 | Int($1) }
            guard offset > 0, offset < codeDirectory.count else { return nil }
            return String(decoding: codeDirectory[offset...].prefix { $0 != 0 }, as: UTF8.self)
        }

        init?(image: MachOImage, path: String) throws {
            guard let (offset, size) = image.codeSignature, size >= 12, offset + size <= image.bytes.count else { return nil }
            let bytes = Array(image.bytes[offset..<(offset + size)])
            func uint32(_ at: Int) -> Int { Int(bytes[at]) << 24 | Int(bytes[at + 1]) << 16 | Int(bytes[at + 2]) << 8 | Int(bytes[at + 3]) }
            guard UInt32(uint32(0)) == CodeSignature.superBlobMagic else { throw NomacError("malformed code signature", path: path) }
            var identifier: String?
            var flags: UInt32 = 0
            var entitlements: [UInt8]?
            var codeDirectory: [UInt8] = []
            var designated: [UInt8]?
            var cms: [UInt8]?
            for index in 0..<uint32(8) {
                let type = uint32(12 + 8 * index), blob = uint32(16 + 8 * index)
                guard blob + 8 <= bytes.count else { throw NomacError("malformed code signature", path: path) }
                let length = uint32(blob + 4)
                guard blob + length <= bytes.count else { throw NomacError("malformed code signature", path: path) }
                switch UInt32(type) {
                case CodeSignature.Slot.codeDirectory.rawValue:
                    flags = UInt32(uint32(blob + 12))
                    let start = blob + uint32(blob + 20)
                    identifier = String(decoding: bytes[start...].prefix { $0 != 0 }, as: UTF8.self)
                    codeDirectory = Array(bytes[blob..<(blob + length)])
                case CodeSignature.Slot.requirements.rawValue:
                    for entry in 0..<uint32(blob + 8) where uint32(blob + 12 + 8 * entry) == 3 {
                        let requirement = blob + uint32(blob + 16 + 8 * entry)
                        guard requirement + 8 <= blob + length else { throw NomacError("malformed code signature", path: path) }
                        designated = Array(bytes[requirement..<(requirement + uint32(requirement + 4))])
                    }
                case CodeSignature.Slot.entitlements.rawValue:
                    entitlements = Array(bytes[(blob + 8)..<(blob + length)])
                case CodeSignature.Slot.signature.rawValue where length > 8:
                    cms = Array(bytes[(blob + 8)..<(blob + length)])
                default:
                    break
                }
            }
            guard let identifier else { throw NomacError("code signature without a code directory", path: path) }
            self.identifier = identifier
            self.flags = flags
            self.entitlements = entitlements
            self.codeDirectory = codeDirectory
            designatedRequirement = designated
            self.cms = cms
        }
    }

    private static func read(_ path: String) throws -> [UInt8] {
        guard let data = FileManager.default.contents(atPath: path) else { throw NomacError("could not read file", path: path) }
        return [UInt8](data)
    }

    /// Rewrites a file in place, keeping its permissions.
    private static func replaceContents(of path: String, with bytes: [UInt8]) throws {
        guard let handle = FileHandle(forWritingAtPath: path) else { throw NomacError("could not write file", path: path) }
        defer { try? handle.close() }
        do {
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: Data(bytes))
        } catch {
            throw NomacError("could not write file: \(error.localizedDescription)", path: path)
        }
    }

    private static func writeFile(_ data: Data, to path: String, mode: Int) throws {
        guard FileManager.default.createFile(atPath: path, contents: data, attributes: [.posixPermissions: mode]) else {
            throw NomacError("could not write file", path: path)
        }
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: path)
    }
}
