import Foundation
import NomacCore
import NomacSigning

/// The `.xcarchive` `xcodebuild archive` assembles once Swift Build's archive build is done
/// (docs/formats/xcarchive.md, `signing_experiments.py` `compare-archive`): the installed
/// products moved to `Products`, a copy of every dSYM the build made in `dSYMs`, the build's
/// `SwiftSupport`, its xcframeworks' signature records in `Signatures`, and `Info.plist`, with
/// `ApplicationProperties` for an app's archive.
public enum XCArchive {
    /// Assembles the archive at `archivePath` from `intermediates`, the scheme's folder in
    /// `ArchiveIntermediates` (`InstallationBuildProductsLocation` and `BuildProductsPath`).
    public static func assemble(intermediates: String, archivePath: String, schemeName: String, creationDate: Date) throws {
        guard !FileManager.default.fileExists(atPath: archivePath) else { throw NomacError("the archive already exists", path: archivePath) }
        let installed = intermediates + "/InstallationBuildProductsLocation", built = intermediates + "/BuildProductsPath"
        let application = try Self.application(installed: installed)
        let signer = try application.map { try Self.signer(of: installed + "/Applications/" + $0) }

        try FileSystem.createDirectory(archivePath)
        if FileSystem.isDirectory(installed) {
            try FileManager.default.moveItem(atPath: installed, toPath: archivePath + "/Products")
        } else {
            try FileSystem.createDirectory(archivePath + "/Products")
        }
        // Every platform's products folder (`Release-iphoneos`, `Release-watchos`); the copies
        // keep the files' times, which the `.symbols` files of an export record.
        try FileSystem.createDirectory(archivePath + "/dSYMs")
        var names = Set<String>()
        for folder in FileSystem.isDirectory(built) ? APFSOrder.sorted(try FileSystem.sortedContents(of: built)) : [] where folder != "SwiftSupport" {
            guard FileSystem.isDirectory(built + "/" + folder) else { continue }
            try collectDSYMs(in: built + "/" + folder, to: archivePath + "/dSYMs", names: &names)
        }
        if FileSystem.isDirectory(built + "/SwiftSupport") {
            try TreeCopy.copy(from: built + "/SwiftSupport", to: archivePath + "/SwiftSupport")
        }
        try collectSignatures(built: built, to: archivePath + "/Signatures")

        let date = ISO8601DateFormatter()
        date.formatOptions = [.withInternetDateTime]
        var plist: [String: PropertyListValue] = [
            "ArchiveVersion": .integer(2), "CreationDate": .date(date.string(from: creationDate)), "Name": .string(schemeName),
            "SchemeName": .string(schemeName),
        ]
        if let application, let signer {
            plist["ApplicationProperties"] = .dictionary(try properties(app: archivePath + "/Products/Applications/" + application,
                                                                         path: "Applications/" + application, signer: signer))
        }
        try FileSystem.write(Data(PropertyListValue.xmlDocument(.dictionary(plist))), to: archivePath + "/Info.plist")
    }

    /// Every entry named `*.dSYM` under `folder`, at any depth (CocoaPods' prebuilt pods put theirs
    /// in `XCFrameworkIntermediates/<pod>/` and `<pod>/dSYMs/`): depth first in APFS order, a
    /// collected dSYM searched too, links copied as links and not followed; a name already taken
    /// gets " 1", " 2" before `.dSYM` in that order (`archive-nested-dsyms`).
    static func collectDSYMs(in folder: String, to destination: String, names: inout Set<String>) throws {
        for name in APFSOrder.sorted(try FileSystem.sortedContents(of: folder)) {
            let path = folder + "/" + name
            if name.hasSuffix(".dSYM") {
                var copy = name
                var number = 0
                while names.contains(copy) {
                    number += 1
                    copy = "\(name.dropLast(".dSYM".count)) \(number).dSYM"
                }
                names.insert(copy)
                try TreeCopy.copy(from: path, to: destination + "/" + copy)
            }
            var info = stat()
            if lstat(path, &info) == 0, UInt32(info.st_mode) & 0o170000 == 0o040000 {
                try collectDSYMs(in: path, to: destination, names: &names)
            }
        }
    }

    /// `Signatures`, for the build's `BuildProductsPath`: a copy of its own `Signatures` folder if it
    /// has one, then every entry named `*.signature` at any depth (`signature_record_experiments.py`
    /// `collect`): one flat folder, files, folders and links copied as they are, links not followed,
    /// a collected folder searched too; a name already taken stops the archive (exit status 70,
    /// `collect-same`, and `collect-root`, for the build's own `Signatures`). No such entry, no folder.
    static func collectSignatures(built: String, to destination: String) throws {
        guard FileSystem.isDirectory(built) else { return }
        if FileSystem.isDirectory(built + "/Signatures") {
            try TreeCopy.copy(from: built + "/Signatures", to: destination)
        }
        func collect(in folder: String) throws {
            for name in APFSOrder.sorted(try FileSystem.sortedContents(of: folder)) {
                let path = folder + "/" + name
                if name.hasSuffix(".signature") {
                    try FileSystem.createDirectory(destination)
                    var taken = stat()
                    guard lstat(destination + "/" + name, &taken) != 0 else {
                        throw NomacError("“\(name)” couldn’t be copied to “Signatures” because an item with the same name already exists.: The operation couldn’t be completed. File exists", exitStatus: 70)
                    }
                    try TreeCopy.copy(from: path, to: destination + "/" + name)
                }
                var info = stat()
                if lstat(path, &info) == 0, UInt32(info.st_mode) & 0o170000 == 0o040000 {
                    try collect(in: path)
                }
            }
        }
        try collect(in: built)
    }

    /// The app of an archive with `ApplicationProperties`: one app in `Applications`, alone or
    /// beside the asset packs of its on-demand resources (`odr`). An archive without an app (a
    /// framework, a static library, a tool, or nothing installed), of several apps, or of one app
    /// beside any other installed product (a framework, a static library, a tool in
    /// `usr/local/bin` or in `/opt`) is generic, without them (`archive-products-*` experiments).
    static func application(installed: String) throws -> String? {
        let top = FileSystem.isDirectory(installed) ? try FileSystem.sortedContents(of: installed) : []
        let applications = top.contains("Applications") ? try FileSystem.sortedContents(of: installed + "/Applications") : []
        let apps = applications.filter { $0.hasSuffix(".app") }
        guard apps.count == 1, applications == apps, Set(top).isSubset(of: ["Applications", "OnDemandResources"]) else { return nil }
        return apps[0]
    }

    /// Ad hoc, the identity and team are empty; with an Apple Development certificate, its common
    /// name and the signature's team (observed privately, B-302).
    static func signer(of app: String) throws -> (identity: String, team: String) {
        guard try !CodeSigner.isSignedAdHoc(app) else { return ("", "") }
        guard let certificate = try CodeSigner.signingCertificate(of: app), certificate.commonName.hasPrefix("Apple Development: "),
              let team = certificate.teamIdentifier else {
            throw NomacError("archives of apps signed other than ad hoc or with an Apple Development certificate are not supported yet (BACKLOG B-302)",
                             path: app)
        }
        return (certificate.commonName, team)
    }

    /// `ApplicationProperties`: the app's path, architectures and versions, and the signer.
    static func properties(app: String, path: String, signer: (identity: String, team: String)) throws -> [String: PropertyListValue] {
        let info = try PropertyLists.readDictionary(at: app + "/Info.plist")
        guard let executable = info["CFBundleExecutable"] as? String else { throw NomacError("the app has no CFBundleExecutable", path: app) }
        var properties: [String: PropertyListValue] = [
            "ApplicationPath": .string(path),
            "Architectures": .array(try CodeSigner.architectures(of: app + "/" + executable).map(PropertyListValue.string)),
            "SigningIdentity": .string(signer.identity),
            "Team": .string(signer.team),
        ]
        for key in ["CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion"] {
            if let value = info[key] as? String { properties[key] = .string(value) }
        }
        return properties
    }
}
