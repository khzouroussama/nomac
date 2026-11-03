import ArgumentParser
import Foundation
import NomacCore
import NomacPackaging
import NomacSigning

/// `nomac export`: `xcodebuild -exportArchive` for ad-hoc signed archives.
struct ExportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export an archive to an IPA.",
        discussion: """
        Writes the IPA, DistributionSummary.plist and ExportOptions.plist for the methods \
        debugging, release-testing, enterprise and app-store-connect with signingCertificate "-", \
        and for debugging with an Apple Development identity and manual provisioningProfiles; \
        with thinning <thin-for-all-variants>, the app's variants from the developer directory's \
        device_traits.db (docs/formats/ipa.md).
        """
    )

    @Option(name: [.customLong("archivePath", withSingleDash: true)], help: "The .xcarchive to export.")
    var archivePath: String

    @Option(name: [.customLong("exportPath", withSingleDash: true)], help: "The folder to write the export to.")
    var exportPath: String

    @Option(name: [.customLong("exportOptionsPlist", withSingleDash: true)], help: "The export options, as for xcodebuild.")
    var exportOptionsPlist: String

    @Option(help: "A PEM file with the private key and certificates of the identity signingCertificate names.")
    var keychain: String?

    @Option(name: .customLong("provisioning-profiles"),
            help: "A folder of .mobileprovision files (default: Xcode's folders under the home folder).")
    var provisioningProfiles: String?

    @Option(name: .customLong("developer-dir"), help: "The Xcode developer directory whose device_traits.db app thinning reads (default: the nomac sdk install).")
    var developerDir: String?

    func run() throws {
        let options = FileSystem.absolute(exportOptionsPlist)
        let thinning = (try? PropertyLists.readDictionary(at: options))?["thinning"] as? String
        let developerDirectory = thinning.map { $0 != "<none>" } == true ? try DeveloperDirectory.resolveIfAvailable(option: developerDir, strictXcode: false) : nil
        try ArchiveExporter.export(archive: FileSystem.absolute(archivePath), exportPath: FileSystem.absolute(exportPath),
                                   optionsPath: options, keychain: keychain.map(FileSystem.absolute),
                                   profileFolders: provisioningProfiles.map { [FileSystem.absolute($0)] } ?? ProvisioningProfile.installedFolders,
                                   developerDirectory: developerDirectory)
        print("Exported \((archivePath as NSString).lastPathComponent) to: \(FileSystem.absolute(exportPath))")
    }
}
