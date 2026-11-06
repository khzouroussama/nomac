import ArgumentParser
import Foundation
import NomacCore
import NomacDevice
import NomacDistribution
import NomacSigning

/// `nomac signing`: what Keychain Access and Xcode do for a developer's signing material, for a
/// machine with neither (docs/INSTALL-ON-IPHONE.md).
struct SigningCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "signing",
        abstract: "Make a signing identity without a Mac and check it against a profile.",
        subcommands: [Request.self, Identity.self, Check.self]
    )

    struct Request: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Make a private key and the certificate signing request developer.apple.com takes.",
            discussion: """
            Writes development.key (RSA 2048, readable only by you) and development.csr, as \
            'openssl genrsa' and 'openssl req -new' do. Refuses to replace an existing file: a \
            certificate works only with the key of its request.
            """
        )

        @Option(help: "The request's common name: free text, Apple's certificate replaces it.")
        var commonName = "nomac development"

        @Option(help: "The folder to write into.")
        var outputDirectory = "."

        func run() throws {
            let folder = FileSystem.absolute(outputDirectory)
            let key = try CertificateRequest.newPrivateKey()
            let keyPath = folder + "/development.key"
            let requestPath = folder + "/development.csr"
            guard !FileSystem.exists(requestPath) else { throw NomacError("already exists; move it away first", path: requestPath) }
            try writeNew(Array(key.utf8), to: keyPath, mode: 0o600)
            try writeNew(Array(try CertificateRequest.pem(commonName: commonName, privateKey: key, path: keyPath).utf8), to: requestPath, mode: 0o644)
            print("""
            wrote \(keyPath) (only you can read it; keep it, and out of any repository)
            wrote \(requestPath)
            next: at https://developer.apple.com/account/resources/certificates/add choose Apple Development, upload \
            development.csr and download development.cer; then 'nomac signing identity development.cer --key development.key'
            """)
        }
    }

    struct Identity: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Turn the certificate Apple issued into the identity file --keychain reads.",
            discussion: """
            Checks that the key is the certificate's and that it is in force, adds Apple's \
            intermediate and root (downloaded from apple.com and checked against their published \
            digests, or given with --chain) and writes them with the key to one file only you can \
            read. Prints the team and the identity's name.
            """
        )

        @Argument(help: "The certificate from developer.apple.com (development.cer).")
        var certificate: String

        @Option(help: "The private key of the certificate's request (development.key).")
        var key: String

        @Option(help: "Apple's intermediate, then its root, instead of downloading them (repeatable, in that order).")
        var chain: [String] = []

        @Option(name: .shortAndLong, help: "The file to write.")
        var output = "identity.pem"

        func run() throws {
            let certificatePath = FileSystem.absolute(certificate)
            let keyPath = FileSystem.absolute(key)
            let outputPath = FileSystem.absolute(output)
            guard !FileSystem.exists(outputPath) else { throw NomacError("already exists; move it away first", path: outputPath) }
            guard let certificateBytes = FileSystem.contents(atPath: certificatePath) else { throw NomacError("cannot read the certificate", path: certificatePath) }
            guard let keyBytes = FileSystem.contents(atPath: keyPath) else { throw NomacError("cannot read the key", path: keyPath) }
            let leaf = try IdentityFile.certificate([UInt8](certificateBytes), path: certificatePath)
            let chainCertificates = chain.isEmpty ? try Self.download(try IdentityFile.authorities(above: leaf, path: certificatePath)) : try chain.map { path in
                let absolute = FileSystem.absolute(path)
                guard let bytes = FileSystem.contents(atPath: absolute) else { throw NomacError("cannot read the certificate", path: absolute) }
                return try IdentityFile.certificate([UInt8](bytes), path: absolute)
            }
            let (text, identity) = try IdentityFile.make(certificate: leaf, chain: chainCertificates, privateKey: String(decoding: keyBytes, as: UTF8.self),
                                                         keyPath: keyPath, certificatePath: certificatePath, at: Date())
            try writeNew(Array(text.utf8), to: outputPath, mode: 0o600)
            print("""
            wrote \(outputPath) (only you can read it; keep it out of any repository)
            identity: \(identity.commonName)
            team: \(identity.teamIdentifier ?? "unknown")
            expires: \(identity.expirationDate.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown")
            next: a development profile with this certificate from developer.apple.com, then 'nomac signing check --keychain \(output) --provisioning-profiles <folder>'
            """)
        }

        static func download(_ authorities: [IdentityFile.Authority]) throws -> [[UInt8]] {
            try authorities.map { authority in
                let response: HTTPResponse
                do {
                    response = try URLSessionTransport().send(HTTPRequest(method: "GET", url: authority.url))
                } catch {
                    throw NomacError("cannot download \(authority.name)", notes: ["download \(authority.url) yourself and pass it with --chain"])
                }
                guard response.status == 200 else {
                    throw NomacError("cannot download \(authority.name): HTTP \(response.status)", notes: ["download it from https://www.apple.com/certificateauthority/ and pass it with --chain"])
                }
                return try IdentityFile.verified([UInt8](response.body), as: authority)
            }
        }
    }

    struct Check: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Check an identity against development profiles before a build.",
            discussion: """
            Reports, for each .mobileprovision of the folder, what a build or a device would \
            refuse: not signed by Apple, not a development profile, without the identity's \
            certificate, expired, an App ID that does not cover --bundle-id, a device it does not \
            include. Prints the build settings 'nomac run' takes for the first profile that \
            passes; exits with status 1 when none does.
            """
        )

        @Option(help: "The identity file (see 'nomac signing identity').")
        var keychain: String

        @Option(help: "The folder of .mobileprovision files.")
        var provisioningProfiles: String

        @Option(help: "The name of the identity in the file.")
        var identity = "Apple Development"

        @Option(help: "The bundle identifier the profile must cover.")
        var bundleId: String?

        @Option(help: "The UDID of the device the profile must include.")
        var device: String?

        func run() throws {
            let keychainPath = FileSystem.absolute(keychain)
            guard let pem = FileSystem.contents(atPath: keychainPath) else { throw NomacError("cannot read the identity file", path: keychainPath) }
            let signing = try SigningIdentity(named: identity, pem: String(decoding: pem, as: UTF8.self), path: keychainPath)
            let formatter = ISO8601DateFormatter()
            let now = Date()
            print("identity: \(signing.commonName), team \(signing.teamIdentifier ?? "unknown"), expires \(signing.expirationDate.map { formatter.string(from: $0) } ?? "unknown")")
            if let expiration = signing.expirationDate, expiration <= now {
                throw NomacError("the certificate expired on \(formatter.string(from: expiration))", path: keychainPath)
            }
            let folder = FileSystem.absolute(provisioningProfiles)
            let files = FileSystem.isDirectory(folder) ? try FileSystem.sortedContents(of: folder).filter { $0.hasSuffix(".mobileprovision") } : []
            guard !files.isEmpty else {
                throw NomacError("no .mobileprovision in the folder", path: folder, notes: ["make an iOS App Development profile at https://developer.apple.com/account/resources/profiles/add and download it there"])
            }
            var usable: ProvisioningProfile?
            var refusals: [String] = []
            for file in files {
                guard let bytes = FileSystem.contents(atPath: folder + "/" + file) else { continue }
                let profile = try ProvisioningProfile(bytes: [UInt8](bytes), path: folder + "/" + file)
                let problems = InstallCheck.problems(profile: profile, identity: signing, bundleIdentifier: bundleId, device: device, at: now)
                if problems.isEmpty {
                    print("profile \"\(profile.name)\": App ID \(profile.applicationIdentifier ?? "unknown"), \(profile.provisionedDevices.count) devices, expires \(profile.expirationDate.map { formatter.string(from: $0) } ?? "unknown")")
                    usable = usable ?? profile
                } else {
                    refusals += problems
                }
            }
            guard let usable else { throw NomacError("no profile in the folder can sign with this identity", path: folder, notes: refusals) }
            let name = signing.commonName.split(separator: ":").first.map(String.init) ?? signing.commonName
            print("settings for nomac run and nomac archive:")
            print("  CODE_SIGN_STYLE=Manual \"CODE_SIGN_IDENTITY=\(name)\" DEVELOPMENT_TEAM=\(signing.teamIdentifier ?? "<team>") \"PROVISIONING_PROFILE_SPECIFIER=\(usable.name)\"")
            if bundleId == nil { print("the app's bundle identifier must fall under \(usable.appID ?? "the App ID"): add PRODUCT_BUNDLE_IDENTIFIER=<identifier> if it does not") }
        }
    }
}

/// Writes `bytes` to a new file with permissions `mode` from its creation; an existing file is an error.
private func writeNew(_ bytes: [UInt8], to path: String, mode: mode_t) throws {
    let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL, mode)
    guard descriptor >= 0 else { throw NomacError("cannot create the file: \(String(cString: strerror(errno)))", path: path) }
    defer { close(descriptor) }
    var offset = 0
    while offset < bytes.count {
        let written = bytes[offset...].withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
        guard written > 0 else { throw NomacError("cannot write the file: \(String(cString: strerror(errno)))", path: path) }
        offset += written
    }
}
