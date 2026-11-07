import Foundation
import NomacCore
import NomacSigning

/// `xcodebuild -exportArchive` for archives signed ad-hoc (docs/formats/ipa.md "The export
/// pipeline"): the app is copied to `Root/Payload` (for app-store-connect, its Info.plists
/// written again, `Symbols` and `SwiftSupport` beside it), its nested code and then the app are
/// signed again, `Root` is archived as ditto does, and the export folder gets the IPA,
/// `DistributionSummary.plist` and `ExportOptions.plist`.
public enum ArchiveExporter {
    /// The methods xcodebuild accepts, in the order its error message lists them.
    static let methods = ["app-store-connect", "release-testing", "enterprise", "debugging", "validation"]
    /// Names xcodebuild still takes, logging that they are deprecated: the same export under the
    /// new name, which `ExportOptions.plist` holds (observed with an ad hoc archive, 2026-11-07).
    static let deprecatedMethods = ["development": "debugging", "ad-hoc": "release-testing", "app-store": "app-store-connect"]
    /// What to do about an archive's ad hoc signature, for an export that needs another.
    static let signingNote = "to install on a device, set signingStyle to manual, signingCertificate to \"Apple Development\" and provisioningProfiles in the export options and pass --keychain (docs/INSTALL-ON-IPHONE.md); signingCertificate \"-\" signs ad hoc, which installs on no device"

    /// The `--preserve-metadata` list of the export's codesign invocations (its Packaging.log).
    static let preservedMetadata: Set<String> = ["identifier", "flags", "runtime", "launch-constraints", "library-constraints"]

    /// Exports the archive at `archive` into `exportPath` with the options in `optionsPath`; a
    /// `signingCertificate` other than `-` names an identity of the PEM file `keychain`, and
    /// `provisioningProfiles` profiles installed in `profileFolders` and signed by a root of
    /// `profileRoots` (Apple's).
    public static func export(archive: String, exportPath: String, optionsPath: String, keychain: String? = nil,
                              profileFolders: [String] = ProvisioningProfile.installedFolders,
                              profileRoots: Set<[UInt8]> = ProvisioningProfile.appleRoots, developerDirectory: String? = nil) throws {
        try export(archive: archive, exportPath: exportPath, optionsPath: optionsPath, profileFolders: profileFolders, profileRoots: profileRoots,
                   developerDirectory: developerDirectory, identityNamed: { name in
            guard let keychain, let pem = FileManager.default.contents(atPath: keychain) else {
                throw NomacError("exportArchive signing with \"\(name)\" needs --keychain <PEM file with the key and certificates>", exitStatus: 70)
            }
            return try SigningIdentity(named: name, pem: String(decoding: pem, as: UTF8.self), path: keychain)
        }, signingTime: { _ in nil })
    }

    /// The export, with the identity a `signingCertificate` names and the signing time of each
    /// item (by its path in the payload; nil for the current time) given.
    static func export(archive: String, exportPath: String, optionsPath: String, profileFolders: [String],
                       profileRoots: Set<[UInt8]> = ProvisioningProfile.appleRoots, developerDirectory: String? = nil,
                       identityNamed: (String) throws -> SigningIdentity, signingTime: (String) -> Date?) throws {
        guard let optionsData = FileManager.default.contents(atPath: optionsPath),
              case .dictionary(var options) = try PropertyListValue.parseXML(optionsData, path: optionsPath) else {
            throw NomacError("exportArchive the export options are not a dictionary", path: optionsPath, exitStatus: 70)
        }
        if case .string(let name)? = options["method"], let current = deprecatedMethods[name] {
            FileHandle.standardError.write(Data("warning: Command line name \"\(name)\" is deprecated. Use \"\(current)\" instead.\n".utf8))
            options["method"] = .string(current)
        }
        let given = options
        let methodValue = options["method"] ?? .string("debugging")
        guard case .string(let method) = methodValue, methods.contains(method) else {
            let found = if case .string(let text) = methodValue { text } else { "\(methodValue)" }
            throw NomacError("exportArchive exportOptionsPlist error for key \"method\" expected one {\(methods.joined(separator: ", "))} but found \(found)",
                             exitStatus: 70)
        }
        guard method != "validation", options["destination"] != .string("upload") else {
            throw NomacError("exportArchive uploading to App Store Connect (method validation, destination upload) is not supported", exitStatus: 70)
        }
        guard case .string(let certificate)? = options["signingCertificate"] else {
            throw NomacError("exportArchive exports without signingCertificate are not supported yet (BACKLOG B-302)", notes: [signingNote], exitStatus: 70)
        }
        if method == "app-store-connect" {
            // Ignored for the App Store: no manifest.plist, and gone from ExportOptions.plist
            // (signing experiments `odr-shapes`, `app-store-connect-manifest`).
            options.removeValue(forKey: "manifest")
        }
        let manifest = try installManifestURLs(options)
        let identity = certificate == "-" ? nil : try identityNamed(certificate)

        let archiveInfo = try PropertyLists.readDictionary(at: archive + "/Info.plist")
        let properties = archiveInfo["ApplicationProperties"] as? [String: Any] ?? [:]
        guard let applicationPath = properties["ApplicationPath"] as? String else {
            throw NomacError("exportArchive the archive has no application", path: archive, exitStatus: 70)
        }
        let archiveTeam = properties["Team"] as? String ?? ""
        guard case .string(let team)? = options["teamID"] ?? (archiveTeam.isEmpty ? nil : .string(archiveTeam)) else {
            throw NomacError("exportArchive No Team Found in Archive", notes: [
                "Use the Signing & Capabilities editor to assign a team to the targets and build a new archive.",
            ], exitStatus: 70)
        }
        options["teamID"] = .string(team)
        options["destination"] = options["destination"] ?? .string("export")
        let forAppStore = method == "app-store-connect"
        // ExportOptions.plist keeps only the options the method uses, its defaults filled in, and
        // `stripSwiftSymbols` true whatever was given; the on-demand resources and App Clip
        // options are written below when the archive has packs or clips
        // (`distribution_experiments.py` `option-grid`, `export-options`).
        options = options.filter { Self.keptOptions.contains($0.key) || (forAppStore ? Self.appStoreOptions : Self.otherOptions).contains($0.key) }
        options["stripSwiftSymbols"] = .boolean(true)
        let defaults: [String: PropertyListValue] = forAppStore
            ? ["generateAppStoreInformation": .boolean(false), "manageAppVersionAndBuildNumber": .boolean(true),
               "testFlightInternalTestingOnly": .boolean(false), "uploadSymbols": .boolean(true)]
            : ["thinning": .string("<none>")]
        options.merge(defaults) { given, _ in given }
        // Thinning for all variants writes the IPA and a variant per group of devices into
        // `Apps`; for one device (a product type), that device's variant alone (`AppThinning`).
        let thinned = !forAppStore && options["thinning"] != .string("<none>")
        var thinningDevice: String?
        if thinned, case .string(let value)? = options["thinning"], value != "<thin-for-all-variants>" { thinningDevice = value }
        if thinned, developerDirectory == nil {
            throw NomacError("exportArchive app thinning needs the developer directory (--developer-dir, or a nomac sdk install)", exitStatus: 70)
        }
        let uploadSymbols = forAppStore ? options["uploadSymbols"] == .boolean(true) : nil

        let application = archive + "/Products/" + applicationPath
        let assetPacks = archive + "/Products/OnDemandResources"
        var packBase: String?
        if FileSystem.isDirectory(assetPacks), !forAppStore {
            // Outside the App Store the packs go into the app unless a base URL hosts them, and
            // embedding wins over a base URL; the option is written as a string (observed: given
            // `<true/>`, written "true"; with a base URL, "false"; with both, "true" and the base
            // URL kept, signing experiments `odr-shapes`).
            let embed = given["embedOnDemandResourcesAssetPacksInBundle"]
            let embedded = [.boolean(true), .string("true")].contains(embed)
            if case .string(let base)? = given["onDemandResourcesAssetPacksBaseURL"], !embedded {
                guard [nil, .boolean(false), .string("false")].contains(embed) else {
                    throw NomacError("exportArchive on-demand resources neither embedded nor hosted are not supported", path: archive, exitStatus: 70)
                }
                packBase = base
            } else if !embedded, embed != nil {
                throw NomacError("exportArchive on-demand resources neither embedded nor hosted are not supported", path: archive, exitStatus: 70)
            }
            options["embedOnDemandResourcesAssetPacksInBundle"] = .string(packBase == nil ? "true" : "false")
            options["onDemandResourcesAssetPacksBaseURL"] = given["onDemandResourcesAssetPacksBaseURL"]
        }
        let appName = (applicationPath as NSString).lastPathComponent
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("nomac-export-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: work) }
        let root = work + "/Root"
        let payloadApp = root + "/Payload/" + appName
        try FileSystem.createDirectory(root + "/Payload")
        try TreeCopy.copy(from: application, to: payloadApp)
        var packs: [String] = []
        var packManifest: Data?
        if FileSystem.isDirectory(assetPacks), forAppStore || packBase != nil {
            // For the App Store or a base URL the packs go beside the app, each signed after it
            // (detached); for the App Store the app keeps neither the template nor a manifest,
            // hosted it gets one with the packs' URLs (`odr` experiment).
            try TreeCopy.copy(from: assetPacks, to: root + "/Payload/OnDemandResources")
            packs = try FileSystem.sortedContents(of: root + "/Payload/OnDemandResources").map { root + "/Payload/OnDemandResources/" + $0 }
            if let packBase {
                packManifest = try AssetPackManifest.write(in: payloadApp, base: packBase)
            } else if FileSystem.isFile(payloadApp + "/AssetPackManifestTemplate.plist") {
                try FileManager.default.removeItem(atPath: payloadApp + "/AssetPackManifestTemplate.plist")
            }
        } else if FileSystem.isDirectory(assetPacks) {
            try TreeCopy.copy(from: assetPacks, to: payloadApp + "/OnDemandResources")
            try AssetPackManifest.write(in: payloadApp, base: nil)
        }
        // All but app-store-connect leave App Clips out and name the app they were exported for
        // (observed with a clip the experiments sign by a script: real ones need a profile, B-302).
        if !forAppStore, FileSystem.isDirectory(payloadApp + "/AppClips") {
            try FileManager.default.removeItem(atPath: payloadApp + "/AppClips")
            if let identifier = properties["CFBundleIdentifier"] as? String { options["distributionBundleIdentifier"] = .string(identifier) }
        }

        let items = try nestedCode(in: payloadApp) + [payloadApp] + packs
        // Only a framework has been observed inside a framework (docs/formats/extensions.md).
        if let held = items.first(where: { item in !item.hasSuffix(".framework") && items.contains { $0.hasSuffix(".framework") && item.hasPrefix($0 + "/") } }) {
            throw NomacError("exportArchive \((held as NSString).lastPathComponent) inside a framework is not supported yet (BACKLOG B-314)", exitStatus: 70)
        }
        if thinned {
            try AppThinning.checkSupported(app: payloadApp, items: items, hostedPacks: packBase != nil, manifest: manifest != nil)
        }
        if forAppStore {
            try addAppStoreContent(archive: archive, root: root, items: items, payloadApp: payloadApp, symbols: uploadSymbols == true,
                                   testFlightInternalOnly: options["testFlightInternalTestingOnly"] == .boolean(true))
        }
        var profiles: [String: ProvisioningProfile] = [:]
        var addedProfiles: Set<String> = []
        if let identity {
            profiles = try embeddedProfiles(items: items, payloadApp: payloadApp, options: options, identity: identity, folders: profileFolders,
                                            roots: profileRoots, method: method, team: team)
            // A development export with manual signing and an Apple Development identity is the
            // only one observed (docs/formats/ipa.md "Signing with an identity and a profile");
            // xcodebuild finds the profiles first, for every method (`distribution_experiments.py`).
            guard method == "debugging", options["signingStyle"] == .string("manual"), identity.commonName.hasPrefix("Apple Development: ") else {
                throw NomacError("exportArchive only debugging exports with manual signing and an Apple Development identity are supported yet (BACKLOG B-460)",
                                 exitStatus: 70)
            }
            // An ad hoc archive's bundles get the profile, 0644 (observed privately for B-302).
            for (item, profile) in profiles where !FileSystem.isFile(item + "/embedded.mobileprovision") {
                try FileSystem.writeExactly(profile.bytes, to: item + "/embedded.mobileprovision")
                try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: item + "/embedded.mobileprovision")
                addedProfiles.insert(item)
            }
        }
        // An empty entitlements dictionary needs no profile (signing-experiments `entitlements-empty`).
        for item in items where identity == nil {
            if let entitlements = try CodeSigner.entitlements(of: item),
               try PropertyListValue.parseXML(Data(entitlements), path: item) != .dictionary([:]) {
                throw NomacError("exportArchive \"\((item as NSString).lastPathComponent)\" requires a provisioning profile.", notes: [
                    "Enable development signing and select a provisioning profile in the Signing & Capabilities editor.",
                    signingNote,
                ], exitStatus: 70)
            }
        }
        // Each item is signed with the entitlements of its current signature, written to a file
        // (`{}` without any); a bundle of an ad hoc archive, which the export gives its profile,
        // gets the development entitlements the profile gives, as the build would (observed
        // privately for B-302: an ad hoc archive exported for debugging with a profile).
        let entitlementsFile = work + "/entitlements"
        var summaries: [(item: String, fields: [String: PropertyListValue])] = []
        for item in items {
            var entitlements = try CodeSigner.entitlements(of: item).map { try PropertyListValue.parseXML(Data($0), path: item) } ?? .dictionary([:])
            if addedProfiles.contains(item), let profile = profiles[item], entitlements == .dictionary([:]) {
                entitlements = try developmentEntitlements(of: item, profile: profile)
            }
            try FileSystem.write(Data(PropertyListValue.xmlDocument(entitlements)), to: entitlementsFile)
            // An asset pack is signed preserving its entitlements, without a file (its signature has
            // none), and is not listed in the summary.
            let isPack = packs.contains(item)
            var request = CodeSigner.Request(path: item, identity: identity?.certificateSHA1 ?? "-", force: true,
                                             entitlementsPath: isPack ? nil : entitlementsFile,
                                             preservedMetadata: isPack ? preservedMetadata.union(["entitlements"]) : preservedMetadata, verbose: true)
            request.signingTime = signingTime(String(item.dropFirst(root.count + 1)))
            _ = try CodeSigner.sign(request, identity: identity)
            if isPack { continue }
            var entry: PropertyListValue
            if FileSystem.isDirectory(item) {
                entry = try summary(of: item, team: team, identity: identity)
            } else if try !(CodeSigner.identifier(of: item) ?? "").hasPrefix("com.apple.dt.runtime.") {
                // Swift's runtime libraries are not listed (observed: `com.apple.dt.runtime.` is
                // left out, `com.apple.dt.` and `com.apple.` are listed).
                entry = try librarySummary(of: item, team: team, identity: identity)
            } else {
                continue
            }
            guard case .dictionary(var fields) = entry else { continue }
            if let uploadSymbols { fields["symbols"] = .boolean(uploadSymbols) }
            if FileSystem.isDirectory(item), case .dictionary(let granted) = entitlements, !granted.isEmpty { fields["entitlements"] = entitlements }
            if let profile = profiles[item] {
                fields["profile"] = .dictionary(["UUID": .string(profile.uuid), "dateExpires": .string(profile.expirationDate.map(shortDate) ?? ""),
                                                 "name": .string(profile.name)])
            }
            // An entry lists what its own bundle holds, and an app that embeds nothing has no
            // `embeddedBinaries` (`watch-widget`, `watch-framework`, `extension-framework`, `alone`).
            // A framework held by a framework takes its name (`framework-framework-deep`).
            let held = summaries.filter { $0.item.hasPrefix(item + "/") }.map { child -> PropertyListValue in
                var entry = child.fields
                if item.hasSuffix(".framework") { entry["name"] = .string((item as NSString).lastPathComponent) }
                return .dictionary(entry)
            }
            if !held.isEmpty { fields["embeddedBinaries"] = .array(held) }
            summaries.removeAll { $0.item.hasPrefix(item + "/") }
            summaries.append((item, fields))
        }

        try FileSystem.createDirectory(exportPath)
        if let packManifest {
            // Hosted packs leave the IPA: each zipped beside it with the manifest.
            let hosted = exportPath + "/OnDemandResources"
            try? FileManager.default.removeItem(atPath: hosted)
            for pack in packs {
                try AssetPackZip.write(pack: pack, to: hosted + "/" + (pack as NSString).lastPathComponent)
            }
            try FileSystem.write(packManifest, to: hosted + "/AssetPackManifest.plist")
            try FileManager.default.removeItem(atPath: root + "/Payload/OnDemandResources")
        }
        // Named after the app's CFBundleName, else its file name (observed: `Named.ipa` for
        // App.app named Named).
        let appInfo = try PropertyLists.readDictionary(at: application + "/Info.plist")
        let ipaName = (appInfo["CFBundleName"] as? String ?? (appName as NSString).deletingPathExtension) + ".ipa"
        try DittoArchive.create(from: root, to: work + "/" + ipaName)
        if thinned, let developerDirectory {
            try writeVariants(root: root, payloadApp: payloadApp, archivedApp: application, items: items, ipa: work + "/" + ipaName, exportPath: exportPath,
                              identity: identity, developerDirectory: developerDirectory, device: thinningDevice)
        } else {
            try? FileManager.default.removeItem(atPath: exportPath + "/" + ipaName)
            try FileManager.default.moveItem(atPath: work + "/" + ipaName, toPath: exportPath + "/" + ipaName)
        }

        try FileSystem.write(Data(PropertyListValue.xmlDocument(.dictionary([ipaName: .array(summaries.map { .dictionary($0.fields) })]))),
                             to: exportPath + "/DistributionSummary.plist")
        try FileSystem.write(Data(PropertyListValue.xmlDocument(.dictionary(options))), to: exportPath + "/ExportOptions.plist")
        if let manifest {
            try FileSystem.write(Data(PropertyListValue.xmlDocument(installManifest(manifest, appInfo: appInfo, appName: appName))),
                                 to: exportPath + "/manifest.plist")
        }
    }

    /// A thinned export's `Apps` (the IPA and a variant per group of devices), or for one
    /// `device` that device's variant alone beside the plists, `app-thinning.plist` and the size
    /// report (docs/formats/ipa.md "App thinning"): each variant is the IPA's root with the
    /// catalogs thinned, the app's Info.plist given `DTAppStoreToolsBuild` and
    /// `UISupportedDevices`, and each changed bundle, then the app, signed again as before.
    static func writeVariants(root: String, payloadApp: String, archivedApp: String, items: [String], ipa: String, exportPath: String,
                              identity: SigningIdentity?, developerDirectory: String, device: String?) throws {
        let ipaName = (ipa as NSString).lastPathComponent
        // A watch app thins apart: its variants of its own, a placeholder in the iPhone ones.
        let watch = FileSystem.isDirectory(payloadApp + "/Watch") ? try FileSystem.sortedContents(of: payloadApp + "/Watch").first.map { payloadApp + "/Watch/" + $0 } : nil
        let appItems = items.filter { !$0.hasPrefix(payloadApp + "/Watch/") }
        var variants = try AppThinning.variants(app: payloadApp, items: appItems, developerDirectory: developerDirectory)
        var written: [AppThinning.Written] = []
        let folder: String
        if let device {
            guard watch == nil else {
                throw NomacError("exportArchive app thinning for one device of an app with a watch app is not supported yet (BACKLOG B-465)", exitStatus: 70)
            }
            guard let variant = variants.first(where: { $0.descriptors.contains { $0.device == device } }) else {
                throw NomacError("exportArchive app thinning for \(device), which is not among the app's devices, is not supported", exitStatus: 70)
            }
            variants = [variant]
            folder = exportPath
        } else {
            folder = exportPath + "/Apps"
            try? FileManager.default.removeItem(atPath: folder)
            try FileSystem.createDirectory(folder)
            written.append(.init(file: ipaName, key: "Apps/" + ipaName, sizes: try AppThinning.sizes(ipa: ipa, root: root, app: payloadApp), descriptors: nil))
            try FileManager.default.moveItem(atPath: ipa, toPath: folder + "/" + ipaName)
        }
        let work = (root as NSString).deletingLastPathComponent
        let variantRoot = work + "/Variant"
        let variantApp = variantRoot + String(payloadApp.dropFirst(root.count))
        for variant in variants {
            try? FileManager.default.removeItem(atPath: variantRoot)
            try TreeCopy.copy(from: root, to: variantRoot)
            for (path, catalog) in variant.catalogs { try FileSystem.writeExactly(catalog, to: variantApp + path + "/Assets.car") }
            if let watch {
                let variantWatch = variantApp + String(watch.dropFirst(payloadApp.count))
                let executable = try PropertyLists.readDictionary(at: watch + "/Info.plist")["CFBundleExecutable"] as? String ?? ""
                try WatchPlaceholder.write(watch: variantWatch, slices: try AppThinning.slices(of: watch + "/" + executable), into: variantApp)
                try FileManager.default.removeItem(atPath: variantWatch)
            }
            try ThinnedInfoPlist.rewrite(at: variantApp + "/Info.plist", devices: Array(Set(variant.descriptors.map(\.device))))
            for item in appItems.map({ variantApp + String($0.dropFirst(payloadApp.count)) }) where item == variantApp || variant.catalogs[String(item.dropFirst(variantApp.count))] != nil {
                try signAgain(item, identity: identity, entitlements: work + "/variant-entitlements")
            }
            let file = AppThinning.fileName(ipaName: ipaName, descriptors: variant.descriptors)
            try DittoArchive.create(from: variantRoot, to: folder + "/" + file)
            written.append(.init(file: file, key: device == nil ? "Apps/" + file : file, sizes: try AppThinning.sizes(ipa: folder + "/" + file, root: variantRoot, app: variantApp),
                                 descriptors: variant.descriptors))
        }
        if let watch {
            // Each watch variant is the watch app alone, its executable the variant's slice of the
            // archive's executable, as it was before the export signed it again (`thinning`
            // `watch`: the space left after the new signature is zeros, not the export's bytes).
            let watchRoot = work + "/WatchVariant"
            let variantWatch = watchRoot + "/Payload/" + (watch as NSString).lastPathComponent
            let executable = try PropertyLists.readDictionary(at: watch + "/Info.plist")["CFBundleExecutable"] as? String ?? ""
            let declared = try PropertyLists.readDictionary(at: watch + "/Info.plist")["MinimumOSVersion"] as? String
            let archivedWatch = archivedApp + String(watch.dropFirst(payloadApp.count))
            for variant in try AppThinning.watchVariants(watch: watch, executable: archivedWatch + "/" + executable, developerDirectory: developerDirectory) {
                try? FileManager.default.removeItem(atPath: watchRoot)
                try FileSystem.createDirectory(watchRoot + "/Payload")
                try TreeCopy.copy(from: watch, to: variantWatch)
                try FileSystem.writeExactly(variant.slice.bytes, to: variantWatch + "/" + executable)
                if let catalog = variant.catalog { try FileSystem.writeExactly(catalog, to: variantWatch + "/Assets.car") }
                try ThinnedInfoPlist.rewrite(at: variantWatch + "/Info.plist", devices: Array(Set(variant.descriptors.map(\.device))),
                                             replacing: variant.minimum == declared ? [:] : ["MinimumOSVersion": variant.minimum])
                try signAgain(variantWatch, identity: identity, entitlements: work + "/variant-entitlements")
                let file = AppThinning.fileName(ipaName: ipaName, descriptors: variant.descriptors)
                try DittoArchive.create(from: watchRoot, to: folder + "/" + file)
                written.append(.init(file: file, key: "Apps/" + file, sizes: try AppThinning.sizes(ipa: folder + "/" + file, root: watchRoot, app: variantWatch),
                                     descriptors: variant.descriptors))
            }
        }
        try FileSystem.write(Data(PropertyListValue.xmlDocument(AppThinning.plist(written))), to: exportPath + "/app-thinning.plist")
        try FileSystem.write(Data(try AppThinning.report(appName: (ipaName as NSString).deletingPathExtension, written).utf8),
                             to: exportPath + "/App Thinning Size Report.txt")
    }

    /// Signs `item` again as the export signed it: its current signature's entitlements.
    static func signAgain(_ item: String, identity: SigningIdentity?, entitlements file: String) throws {
        let current = try CodeSigner.entitlements(of: item).map { try PropertyListValue.parseXML(Data($0), path: item) } ?? .dictionary([:])
        try FileSystem.write(Data(PropertyListValue.xmlDocument(current)), to: file)
        _ = try CodeSigner.sign(CodeSigner.Request(path: item, identity: identity?.certificateSHA1 ?? "-", force: true, entitlementsPath: file,
                                                   preservedMetadata: preservedMetadata, verbose: true), identity: identity)
    }

    /// The URLs of a `manifest` export option: `appURL`, `displayImageURL` and
    /// `fullSizeImageURL`, all three required (xcodebuild's help; without the image URLs it
    /// refuses the options as below).
    static func installManifestURLs(_ options: [String: PropertyListValue]) throws -> [String]? {
        guard let manifest = options["manifest"] else { return nil }
        guard case .dictionary(let entries) = manifest else { throw missingManifestData }
        return try ["appURL", "displayImageURL", "fullSizeImageURL"].map { key in
            guard case .string(let url)? = entries[key] else { throw missingManifestData }
            return url
        }
    }

    static let missingManifestData = NomacError("Couldn't load -exportOptionsPlist The data couldn\u{2019}t be read because it is missing.", exitStatus: 70)

    /// The OTA install manifest (`manifest` experiment, the same for debugging, release-testing
    /// and enterprise): one item with the IPA, display image and full-size image as assets, and
    /// the app's identifier, version (`CFBundleShortVersionString`) and file name as metadata.
    static func installManifest(_ urls: [String], appInfo: [String: Any], appName: String) -> PropertyListValue {
        let assets = zip(["software-package", "display-image", "full-size-image"], urls).map { kind, url in
            PropertyListValue.dictionary(["kind": .string(kind), "url": .string(url)])
        }
        let metadata: [String: PropertyListValue] = [
            "bundle-identifier": .string(appInfo["CFBundleIdentifier"] as? String ?? ""),
            "bundle-version": .string(appInfo["CFBundleShortVersionString"] as? String ?? ""),
            "kind": .string("software"),
            "platform-identifier": .string("com.apple.platform.iphoneos"),
            "title": .string((appName as NSString).deletingPathExtension),
        ]
        return .dictionary(["items": .array([.dictionary(["assets": .array(assets), "metadata": .dictionary(metadata)])])])
    }

    /// The options every method keeps in ExportOptions.plist, and those only app-store-connect
    /// or only the other methods keep (`distribution_experiments.py` `option-grid`).
    static let keptOptions: Set<String> = ["method", "destination", "signingStyle", "signingCertificate", "teamID", "provisioningProfiles"]
    static let appStoreOptions: Set<String> = ["generateAppStoreInformation", "manageAppVersionAndBuildNumber", "testFlightInternalTestingOnly", "uploadSymbols"]
    static let otherOptions: Set<String> = ["thinning", "manifest"]

    /// The kind of profile each method looks for, as xcodebuild names it when none is installed.
    static let profileKinds = ["app-store-connect": "iOS App Store", "release-testing": "iOS Ad Hoc", "enterprise": "iOS In House",
                               "debugging": "iOS App Development"]

    /// The profile each bundle is exported with, by its path: the one `provisioningProfiles`
    /// names for its bundle identifier, for every bundle but frameworks and what they hold (the
    /// export's `IDEDistributionEmbedProfileStep` skips the framework). It must be installed and
    /// signed by Apple, cover the bundle identifier and include the identity's certificate, or
    /// xcodebuild reports each problem of each bundle (`distribution_experiments.py`, in an order
    /// that varies from run to run; nomac's is the signing order); and it must be the profile the
    /// archive embeds, or the archive embeds none (an ad hoc archive, observed privately for B-302).
    static func embeddedProfiles(items: [String], payloadApp: String, options: [String: PropertyListValue], identity: SigningIdentity,
                                 folders: [String], roots: Set<[UInt8]>, method: String, team: String) throws -> [String: ProvisioningProfile] {
        guard case .dictionary(let specifiers)? = options["provisioningProfiles"] else {
            throw NomacError("exportArchive signing with a certificate needs provisioningProfiles in the export options", exitStatus: 70)
        }
        var profiles: [String: ProvisioningProfile] = [:]
        var errors: [NomacError] = []
        for item in items where FileSystem.isDirectory(item) && !isInFramework(item, payloadApp: payloadApp) {
            let bundleIdentifier = try PropertyLists.readDictionary(at: item + "/Info.plist")["CFBundleIdentifier"] as? String ?? ""
            guard case .string(let specifier)? = specifiers[bundleIdentifier] else {
                throw NomacError("exportArchive no provisioning profile for \(bundleIdentifier) in provisioningProfiles", exitStatus: 70)
            }
            guard let profile = try ProvisioningProfile.installed(specifier, in: folders, roots: roots) else {
                errors.append(NomacError("exportArchive No \"\(profileKinds[method] ?? "")\" profiles for team '\(team)' matching '\(specifier)' are installed.", notes: [
                    "Install a profile (by dragging and dropping it onto Xcode's dock item) or specify a different profile in your Export Options property list.",
                ], exitStatus: 70))
                continue
            }
            let problems = (profile.covers(bundleIdentifier: bundleIdentifier) ? [] : [
                NomacError("exportArchive Provisioning profile \"\(profile.name)\" has app ID \"\(profile.appID ?? "")\", which does not match the bundle ID \"\(bundleIdentifier)\".",
                           exitStatus: 70),
            ]) + (profile.includes(identity) ? [] : [
                NomacError("exportArchive Provisioning profile \"\(profile.name)\" doesn't include signing certificate \"\(identity.commonName)\".", exitStatus: 70),
            ])
            errors += problems
            guard problems.isEmpty else { continue }
            // An ad hoc archive embeds none; another profile than the archive's is not observed.
            if let embedded = FileManager.default.contents(atPath: item + "/embedded.mobileprovision").map([UInt8].init), embedded != profile.bytes {
                throw NomacError("exportArchive exporting with a profile other than the one the archive embeds is not supported yet (BACKLOG B-302)",
                                 path: item, exitStatus: 70)
            }
            profiles[item] = profile
        }
        if var first = errors.first {
            first.following = Array(errors.dropFirst())
            throw first
        }
        return profiles
    }

    /// `application-identifier` (the profile's team and the bundle's identifier),
    /// `com.apple.developer.team-identifier` and the profile's `get-task-allow`.
    static func developmentEntitlements(of item: String, profile: ProvisioningProfile) throws -> PropertyListValue {
        let bundleIdentifier = try PropertyLists.readDictionary(at: item + "/Info.plist")["CFBundleIdentifier"] as? String ?? ""
        guard let applicationIdentifier = profile.applicationIdentifier, let dot = applicationIdentifier.firstIndex(of: "."),
              case .dictionary(let granted) = profile.entitlements, case .boolean(let getTaskAllow)? = granted["get-task-allow"] else {
            throw NomacError("exportArchive the profile \"\(profile.name)\" has no application-identifier or get-task-allow", exitStatus: 70)
        }
        let team = String(applicationIdentifier[..<dot])
        return .dictionary([
            "application-identifier": .string(team + "." + bundleIdentifier),
            "com.apple.developer.team-identifier": .string(team),
            "get-task-allow": .boolean(getTaskAllow),
        ])
    }

    /// Whether `item` is a framework or inside one, for the steps that skip them ("is a
    /// framework or embedded in a framework").
    static func isInFramework(_ item: String, payloadApp: String) -> Bool {
        let payload = (payloadApp as NSString).deletingLastPathComponent + "/"
        return item.hasPrefix(payload) && item.dropFirst(payload.count).split(separator: "/").contains { $0.hasSuffix(".framework") }
    }

    /// `M/d/yy`, as the summary writes dates (observed for a certificate's and a profile's end,
    /// whose day is the same in UTC and in the Mac's time zone).
    static func shortDate(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.month!)/\(parts.day!)/\(String(format: "%02d", parts.year! % 100))"
    }

    /// What app-store-connect adds before signing (docs/formats/ipa.md, observed in the
    /// experiments' exports): every bundle's Info.plist written again but those of frameworks and
    /// what they hold ("is a framework or embedded in a framework"), one `.symbols` file per slice
    /// of each dSYM's DWARF files in `Root/Symbols`, recording the archive's path with symbolic
    /// links resolved (`/tmp` gives `/private/tmp`), and the archive's `SwiftSupport`.
    static func addAppStoreContent(archive: String, root: String, items: [String], payloadApp: String, symbols: Bool,
                                   testFlightInternalOnly: Bool) throws {
        let appInfo = try PropertyLists.readDictionary(at: payloadApp + "/Info.plist")
        let versions = ["CFBundleShortVersionString", "CFBundleVersion"].reduce(into: [String: String]()) { $0[$1] = appInfo[$1] as? String }
        for item in items where FileSystem.isDirectory(item) && FileSystem.isFile(item + "/Info.plist") && !isInFramework(item, payloadApp: payloadApp) {
            try ExportedInfoPlist.rewrite(at: item + "/Info.plist", adding: item.hasSuffix(".assetpack") ? versions : [:],
                                          flags: item == payloadApp && testFlightInternalOnly ? ["TFInternalTestingOnly": true] : [:])
        }
        if symbols {
            guard let resolved = realpath(archive, nil) else { throw NomacError("could not resolve the path", path: archive) }
            defer { free(resolved) }
            let dsyms = String(cString: resolved) + "/dSYMs"
            try FileSystem.createDirectory(root + "/Symbols")
            for dsym in FileSystem.isDirectory(dsyms) ? try FileSystem.sortedContents(of: dsyms) : [] where dsym.hasSuffix(".dSYM") {
                let dwarf = dsyms + "/" + dsym + "/Contents/Resources/DWARF"
                for name in FileSystem.isDirectory(dwarf) ? try FileSystem.sortedContents(of: dwarf) : [] {
                    for file in try SymbolsFile.files(dwarfFile: dwarf + "/" + name) {
                        try FileSystem.write(Data(file.bytes), to: root + "/Symbols/" + file.name)
                    }
                }
            }
        }
        if FileSystem.isDirectory(archive + "/SwiftSupport") {
            try TreeCopy.copy(from: archive + "/SwiftSupport", to: root + "/SwiftSupport")
        }
    }

    /// The bundles and libraries inside `bundle` that carry code, deepest first, names in
    /// bytewise order: the order the export signs them in (observed: `Extensions/Intents.appex`,
    /// `Frameworks/Alpha.framework`, `Kit.framework`, `Zed.framework`,
    /// `libswiftCompatibilitySpan.dylib`, `zeta.framework`, `PlugIns/Action.appex`, `Share.appex`,
    /// `Plugin.bundle`, `XPCServices/Helper.xpc`).
    static func nestedCode(in bundle: String) throws -> [String] {
        var result: [String] = []
        for name in try FileSystem.sortedContents(of: bundle) {
            let path = bundle + "/" + name
            guard (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) == nil else { continue }
            if FileSystem.isDirectory(path) {
                result += try nestedCode(in: path)
                let kind = (name as NSString).pathExtension
                if ["framework", "appex", "app", "xpc"].contains(kind), FileSystem.isFile(path + "/Info.plist") {
                    result.append(path)
                } else if kind == "bundle", FileSystem.isFile(path + "/Info.plist"),
                          try PropertyLists.readDictionary(at: path + "/Info.plist")["CFBundleExecutable"] != nil {
                    // A loadable bundle in the app's resources is signed and listed like the
                    // others (`archive-products-app`); a bundle without code is a resource.
                    result.append(path)
                }
            } else if (name as NSString).pathExtension == "dylib" {
                result.append(path)
            }
        }
        return result
    }

    /// The `DistributionSummary.plist` entry of a signed ad-hoc library outside bundles: its
    /// architectures in slice order, certificate, name and team.
    static func librarySummary(of library: String, team: String, identity: SigningIdentity?) throws -> PropertyListValue {
        var entry = commonSummary(name: (library as NSString).lastPathComponent, team: team, identity: identity)
        entry["architectures"] = .array(try CodeSigner.architectures(of: library).map(PropertyListValue.string))
        return .dictionary(entry)
    }

    /// The certificate is the identity's SHA-1, end date and kind (`Apple Development`), or for
    /// ad-hoc signing empty with `Sign to Run Locally`.
    private static func commonSummary(name: String, team: String, identity: SigningIdentity?) -> [String: PropertyListValue] {
        let certificate: [String: PropertyListValue] = identity.map {
            ["SHA1": .string($0.certificateSHA1), "dateExpires": .string($0.expirationDate.map(shortDate) ?? ""),
             "type": .string(String($0.commonName.prefix { $0 != ":" }))]
        } ?? ["SHA1": .string(""), "dateExpires": .string(""), "type": .string("Sign to Run Locally")]
        return [
            "certificate": .dictionary(certificate),
            "name": .string(name),
            "team": .dictionary(["id": .string(team), "name": .string("")]),
        ]
    }

    /// The `DistributionSummary.plist` entry of a signed ad-hoc bundle.
    static func summary(of bundle: String, team: String, identity: SigningIdentity?) throws -> PropertyListValue {
        let info = try PropertyLists.readDictionary(at: bundle + "/Info.plist")
        var entry = commonSummary(name: (bundle as NSString).lastPathComponent, team: team, identity: identity)
        if let executable = info["CFBundleExecutable"] as? String {
            entry["architectures"] = .array(try CodeSigner.architectures(of: bundle + "/" + executable).map(PropertyListValue.string))
        }
        if let build = info["CFBundleVersion"] as? String { entry["buildNumber"] = .string(build) }
        if let version = info["CFBundleShortVersionString"] as? String { entry["versionNumber"] = .string(version) }
        return .dictionary(entry)
    }
}

/// Copies a folder as ditto does for the export: contents, permissions, and access and
/// modification times, the names' bytes as they are (signing experiments `names`: Xcode's IPA
/// keeps precomposed names precomposed).
enum TreeCopy {
    static func copy(from source: String, to destination: String) throws {
        var info = stat()
        guard lstat(source, &info) == 0 else { throw NomacError("could not read file information", path: source) }
        switch UInt32(info.st_mode) & 0o170000 {
        case 0o040000:
            try FileSystem.createDirectoryExactly(destination)
            for name in try FileSystem.sortedContents(of: source) {
                try copy(from: source + "/" + name, to: destination + "/" + name)
            }
        case 0o120000:
            try FileSystem.createSymbolicLinkExactly(destination, to: FileManager.default.destinationOfSymbolicLink(atPath: source))
        default:
            guard let data = FileManager.default.contents(atPath: source) else { throw NomacError("could not copy file", path: source) }
            try FileSystem.writeExactly([UInt8](data), to: destination)
        }
        if UInt32(info.st_mode) & 0o170000 != 0o120000 {
            guard chmod(destination, info.st_mode & 0o7777) == 0 else { throw NomacError("could not set permissions", path: destination) }
        }
        #if canImport(Darwin)
        var times = [timeval(tv_sec: info.st_atimespec.tv_sec, tv_usec: 0), timeval(tv_sec: info.st_mtimespec.tv_sec, tv_usec: 0)]
        #else
        var times = [timeval(tv_sec: info.st_atim.tv_sec, tv_usec: 0), timeval(tv_sec: info.st_mtim.tv_sec, tv_usec: 0)]
        #endif
        guard lutimes(destination, &times) == 0 else { throw NomacError("could not set file times", path: destination) }
    }
}
