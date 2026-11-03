import Foundation
import NomacCore
import NomacTestSupport
import Testing
@testable import NomacPackaging
@testable import NomacSigning

/// A development export with an identity and profiles, as observed privately with an Apple
/// Development identity and an installed development profile (docs/formats/ipa.md "Signing with
/// an identity and a profile"), here with the self-made Apple-shaped identity and a self-written
/// profile.
@Suite struct ProfileExportTests {
    static let identityName = "Apple Development: nomac Test (ABCDE12345)"
    static let uuid = "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0"
    static let entitlements = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
    \t<key>application-identifier</key>
    \t<string>ABCDE12345.org.nomac.export</string>
    \t<key>com.apple.developer.team-identifier</key>
    \t<string>ABCDE12345</string>
    \t<key>get-task-allow</key>
    \t<true/>
    </dict>
    </plist>

    """

    /// The test archive signed with the identity, every bundle but the frameworks embedding the
    /// profile, the app with the entitlements a development profile gives; the PEM file and the
    /// profile folder beside it.
    static func archive(in directory: String, profileCertificates: [[UInt8]]? = nil) throws -> (archive: String, keychain: String, profiles: String) {
        let archive = try ArchiveExporterTests.archive(in: directory, team: "ABCDE12345")
        let keychain = directory + "/identity.pem"
        try FileSystem.write(Data(TestIdentities.appleShaped.utf8), to: keychain)
        let identity = try SigningIdentity(named: identityName, pem: TestIdentities.appleShaped, path: keychain)
        let profile = SyntheticProfile.profile(uuid: uuid, name: "nomac Development", expiration: "2027-08-26T11:00:00Z", entitlements: """
            \t<dict>
            \t\t<key>application-identifier</key>
            \t\t<string>ABCDE12345.*</string>
            \t\t<key>get-task-allow</key>
            \t\t<true/>
            \t</dict>
            """, certificates: profileCertificates ?? [identity.certificate])
        try FileSystem.write(Data(profile), to: directory + "/profiles/development.mobileprovision")
        try FileSystem.write(Data(entitlements.utf8), to: directory + "/App.entitlements")
        let app = archive + "/Products/Applications/App.app"
        for item in try ArchiveExporter.nestedCode(in: app) + [app] {
            if FileSystem.isDirectory(item), !item.hasSuffix(".framework") {
                try FileSystem.write(Data(profile), to: item + "/embedded.mobileprovision")
            }
            _ = try CodeSigner.sign(CodeSigner.Request(path: item, identity: identityName, keychain: keychain, force: true,
                                                       entitlementsPath: item == app ? directory + "/App.entitlements" : nil))
        }
        return (archive, keychain, directory + "/profiles")
    }

    static func options(method: String = "debugging", profiles: [String] = ["org.nomac.export", "org.nomac.export.Share", "org.nomac.export.Action"]) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>method</key>
        \t<string>\(method)</string>
        \t<key>provisioningProfiles</key>
        \t<dict>
        \(profiles.map { "\t\t<key>\($0)</key>\n\t\t<string>\(uuid)</string>" }.joined(separator: "\n"))
        \t</dict>
        \t<key>signingCertificate</key>
        \t<string>\(identityName)</string>
        \t<key>signingStyle</key>
        \t<string>manual</string>
        \t<key>teamID</key>
        \t<string>ABCDE12345</string>
        </dict>
        </plist>

        """
    }

    static func export(_ prepared: (archive: String, keychain: String, profiles: String), options: String, to directory: String,
                       roots: Set<[UInt8]> = SyntheticProfile.roots) throws {
        try FileSystem.write(Data(options.utf8), to: directory + "/options.plist")
        try ArchiveExporter.export(archive: prepared.archive, exportPath: directory + "/out", optionsPath: directory + "/options.plist",
                                   keychain: prepared.keychain, profileFolders: [prepared.profiles], profileRoots: roots)
    }

    @Test func signsWithTheIdentityAndListsCertificateEntitlementsAndProfiles() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-export")
        let prepared = try Self.archive(in: temporary.path)
        try Self.export(prepared, options: Self.options(), to: temporary.path)
        let summary = try PropertyListValue.parseXML(try Data(contentsOf: URL(fileURLWithPath: temporary.path + "/out/DistributionSummary.plist")),
                                                     path: "summary")
        guard case .dictionary(let ipas) = summary, case .array(let entries)? = ipas["App.ipa"], case .dictionary(let app) = entries[0],
              case .array(let nested)? = app["embeddedBinaries"] else {
            Issue.record("unexpected summary")
            return
        }
        let certificate = PropertyListValue.dictionary([
            "SHA1": .string("EF637C7AB75E0067594DF81B2D25E6AD1818024A"), "dateExpires": .string("10/19/36"), "type": .string("Apple Development"),
        ])
        let profile = PropertyListValue.dictionary(["UUID": .string(Self.uuid), "dateExpires": .string("8/26/27"), "name": .string("nomac Development")])
        #expect(app["certificate"] == certificate)
        #expect(app["profile"] == profile)
        #expect(app["entitlements"] == (try PropertyListValue.parseXML(Data(Self.entitlements.utf8), path: "entitlements")))
        for case .dictionary(let entry) in nested {
            #expect(entry["certificate"] == certificate)
            let name = entry["name"]
            #expect(entry["profile"] == ([.string("Share.appex"), .string("Action.appex")].contains(name) ? profile : nil))
            #expect(entry["entitlements"] == nil)
        }

        let unzipped = temporary.path + "/ipa"
        // unzip is there wherever SwiftPM is (it extracts binary artifacts with it on Linux).
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        unzip.arguments = ["unzip", "-q", temporary.path + "/out/App.ipa", "-d", unzipped]
        try unzip.run()
        unzip.waitUntilExit()
        let exported = unzipped + "/Payload/App.app"
        #expect(try CodeSigner.signingCertificate(of: exported)?.commonName == Self.identityName)
        #expect(try CodeSigner.entitlements(of: exported).map { String(decoding: $0, as: UTF8.self) } == Self.entitlements)
        #expect(FileManager.default.contents(atPath: exported + "/embedded.mobileprovision")
            == FileManager.default.contents(atPath: prepared.profiles + "/development.mobileprovision"))
    }

    @Test func refusesWhatIsNotObserved() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-export")
        let prepared = try Self.archive(in: temporary.path)
        #expect(throws: NomacError.self) { try Self.export(prepared, options: Self.options(method: "release-testing"), to: temporary.path) }
        #expect(throws: NomacError.self) { try Self.export(prepared, options: Self.options(profiles: ["org.nomac.export"]), to: temporary.path) }
        let other = try TemporaryDirectory(prefix: "nomac-export")
        let withoutCertificate = try Self.archive(in: other.path, profileCertificates: [])
        // One error per bundle the profile does not let the identity sign.
        let certificate = NomacError("exportArchive Provisioning profile \"nomac Development\" doesn't include signing certificate \"\(Self.identityName)\".",
                                     exitStatus: 70)
        #expect(throws: NomacError(certificate.message, exitStatus: 70, following: [certificate, certificate])) {
            try Self.export(withoutCertificate, options: Self.options(), to: other.path)
        }
    }

    /// A profile not signed by Apple is not installed, for each bundle, named by the kind of
    /// profile the method looks for (`distribution_experiments.py` `apple-profile` and
    /// `missing-profile`); found first, for every method.
    @Test func profilesNotSignedByAppleAreNotInstalled() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-export")
        let prepared = try Self.archive(in: temporary.path)
        for (method, kind) in [("debugging", "iOS App Development"), ("release-testing", "iOS Ad Hoc"), ("enterprise", "iOS In House"),
                               ("app-store-connect", "iOS App Store")] {
            let missing = NomacError("exportArchive No \"\(kind)\" profiles for team 'ABCDE12345' matching '\(Self.uuid)' are installed.", notes: [
                "Install a profile (by dragging and dropping it onto Xcode's dock item) or specify a different profile in your Export Options property list.",
            ], exitStatus: 70)
            var expected = missing
            expected.following = [missing, missing]
            #expect(throws: expected) {
                try Self.export(prepared, options: Self.options(method: method), to: temporary.path, roots: ProvisioningProfile.appleRoots)
            }
        }
    }

    /// An app signed with an Apple Development identity: `SigningIdentity` is its certificate's
    /// common name and `Team` the signature's team (observed privately; the self-made chain taken
    /// as Apple's, so that the code directory carries the team).
    @Test func archivesAnAppleDevelopmentSignature() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-archive")
        let intermediates = try XCArchiveTests.intermediates(in: temporary.path)
        let shaped = try SigningIdentity(named: Self.identityName, pem: TestIdentities.appleShaped, path: "identity.pem")
        let identity = SigningIdentity(chain: shaped.chain, appleRoots: [shaped.chain.last!.sha1Hex], sign: shaped.sign)
        let app = intermediates + "/InstallationBuildProductsLocation/Applications/App.app"
        _ = try CodeSigner.sign(CodeSigner.Request(path: app, identity: Self.identityName, force: true), identity: identity)
        try XCArchive.assemble(intermediates: intermediates, archivePath: temporary.path + "/App.xcarchive", schemeName: "App", creationDate: Date())
        let info = try PropertyLists.readDictionary(at: temporary.path + "/App.xcarchive/Info.plist")
        let properties = info["ApplicationProperties"] as? [String: Any]
        #expect(properties?["SigningIdentity"] as? String == Self.identityName)
        #expect(properties?["Team"] as? String == "ABCDE12345")
    }

    /// An ad hoc archive exported with a profile: each bundle but the frameworks gets the profile
    /// and the development entitlements it gives (observed privately for B-302).
    @Test func exportsAnAdHocArchiveWithAProfile() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-export")
        let archive = try ArchiveExporterTests.archive(in: temporary.path, team: "ABCDE12345")
        let keychain = temporary.path + "/identity.pem"
        try FileSystem.write(Data(TestIdentities.appleShaped.utf8), to: keychain)
        let identity = try SigningIdentity(named: Self.identityName, pem: TestIdentities.appleShaped, path: keychain)
        let profile = SyntheticProfile.profile(uuid: Self.uuid, name: "nomac Development", expiration: "2027-08-26T11:00:00Z", entitlements: """
            \t<dict>
            \t\t<key>application-identifier</key>
            \t\t<string>ABCDE12345.*</string>
            \t\t<key>get-task-allow</key>
            \t\t<true/>
            \t</dict>
            """, certificates: [identity.certificate])
        try FileSystem.write(Data(profile), to: temporary.path + "/profiles/development.mobileprovision")
        try Self.export((archive, keychain, temporary.path + "/profiles"), options: Self.options(), to: temporary.path)
        let unzipped = temporary.path + "/ipa"
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        unzip.arguments = ["unzip", "-q", temporary.path + "/out/App.ipa", "-d", unzipped]
        try unzip.run()
        unzip.waitUntilExit()
        let exported = unzipped + "/Payload/App.app"
        #expect(FileManager.default.contents(atPath: exported + "/embedded.mobileprovision").map([UInt8].init) == profile)
        #expect(try CodeSigner.entitlements(of: exported).map { String(decoding: $0, as: UTF8.self) } == Self.entitlements)
        #expect(try CodeSigner.signingCertificate(of: exported)?.commonName == Self.identityName)
    }
}
