import Foundation
import NomacCore
import NomacSigning
import NomacTestSupport
import Testing
@testable import NomacPackaging

/// The archive `nomac xcarchive` assembles from an archive build's intermediates, laid out as
/// xcodebuild's archives of the experiments are (`compare-archive`: `archive-names`,
/// `archive-nested-dsyms`, `archive-nodsym`, `archive-products-*`, `span-nested`, `watch-appclip-script`).
@Suite struct XCArchiveTests {
    /// The intermediates of an archive build of the test app with a watch app: the installed
    /// app, and per platform the products with their dSYMs, and `SwiftSupport`.
    static func intermediates(in directory: String) throws -> String {
        let built = try ArchiveExporterTests.archive(in: directory + "/source", watch: true)
        let intermediates = directory + "/ArchiveIntermediates/App"
        try FileSystem.createDirectory(intermediates + "/InstallationBuildProductsLocation/Applications")
        try FileManager.default.moveItem(atPath: built + "/Products/Applications/App.app",
                                         toPath: intermediates + "/InstallationBuildProductsLocation/Applications/App.app")
        let products = intermediates + "/BuildProductsPath"
        try FileSystem.createDirectory(products + "/Release-iphoneos/App.swiftmodule")
        try FileSystem.createDirectory(products + "/Release-watchos")
        try FileManager.default.moveItem(atPath: built + "/dSYMs/App.app.dSYM", toPath: products + "/Release-iphoneos/App.app.dSYM")
        try FileManager.default.moveItem(atPath: built + "/dSYMs/Watch.app.dSYM", toPath: products + "/Release-watchos/Watch.app.dSYM")
        try FileSystem.createDirectory(products + "/SwiftSupport/iphoneos")
        try FileManager.default.copyItem(atPath: intermediates + "/InstallationBuildProductsLocation/Applications/App.app/Frameworks/libswiftThing.dylib",
                                         toPath: products + "/SwiftSupport/iphoneos/libswiftThing.dylib")
        return intermediates
    }

    /// Every entry named `*.signature` under `BuildProductsPath`, at any depth, in one flat folder:
    /// files, folders and links as they are, links not followed (`signature_record_experiments.py` `collect`).
    @Test func collectsTheSignatureRecords() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-archive")
        let intermediates = try Self.intermediates(in: temporary.path)
        let products = intermediates + "/BuildProductsPath"
        let record = products + "/Release-iphoneos/Vendor.xcframework-ios.signature"
        try FileSystem.write(Data("record".utf8), to: record)
        let time = Date(timeIntervalSince1970: 1_792_654_000)
        try FileManager.default.setAttributes([.modificationDate: time, .posixPermissions: 0o644], ofItemAtPath: record)
        try FileSystem.write(Data("watch".utf8), to: products + "/Release-watchos/Vendor.xcframework-watchos.signature")
        try FileSystem.write(Data("below".utf8), to: products + "/Release-iphoneos/sub/below.signature")
        try FileSystem.write(Data("inside".utf8), to: products + "/Release-iphoneos/Folder.signature/inside.signature")
        try FileSystem.write(Data("beside".utf8), to: products + "/beside.signature")
        try FileSystem.write(Data("support".utf8), to: products + "/SwiftSupport/support.signature")
        try FileSystem.write(Data("plain".utf8), to: products + "/Release-iphoneos/plain.txt")
        try FileSystem.write(Data("linked".utf8), to: temporary.path + "/elsewhere/linked.signature")
        try FileManager.default.createSymbolicLink(atPath: products + "/Release-iphoneos/linked", withDestinationPath: temporary.path + "/elsewhere")
        try FileManager.default.createSymbolicLink(atPath: products + "/Release-iphoneos/link.signature", withDestinationPath: "below.signature")

        let archive = temporary.path + "/App.xcarchive"
        try XCArchive.assemble(intermediates: intermediates, archivePath: archive, schemeName: "App", creationDate: Date())
        #expect(try FileSystem.sortedContents(of: archive) == ["Info.plist", "Products", "Signatures", "SwiftSupport", "dSYMs"])
        #expect(try FileSystem.sortedContents(of: archive + "/Signatures") == [
            "Folder.signature", "Vendor.xcframework-ios.signature", "Vendor.xcframework-watchos.signature", "below.signature", "beside.signature",
            "inside.signature", "link.signature", "support.signature",
        ])
        #expect(FileSystem.isFile(archive + "/Signatures/Folder.signature/inside.signature"))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: archive + "/Signatures/link.signature") == "below.signature")
        let attributes = try FileManager.default.attributesOfItem(atPath: archive + "/Signatures/Vendor.xcframework-ios.signature")
        #expect(attributes[.modificationDate] as? Date == time)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o644)
        #expect(FileSystem.isFile(record))
    }

    /// Two records of one name stop the archive, as a record in the build's own `Signatures` does,
    /// a folder the archive starts from (`collect-same`, `collect-root`).
    @Test func refusesTwoSignatureRecordsOfOneName() throws {
        for second in ["Release-iphoneos/sub/same.signature", "Signatures/same.signature"] {
            let temporary = try TemporaryDirectory(prefix: "nomac-archive")
            let intermediates = try Self.intermediates(in: temporary.path)
            let products = intermediates + "/BuildProductsPath"
            try FileSystem.write(Data("first".utf8), to: products + "/Release-iphoneos/same.signature")
            try FileSystem.write(Data("second".utf8), to: products + "/" + second)
            try FileSystem.write(Data("plain".utf8), to: products + "/Signatures/plain.txt")
            let archive = temporary.path + "/App.xcarchive"
            #expect(throws: NomacError("“same.signature” couldn’t be copied to “Signatures” because an item with the same name already exists.: The operation couldn’t be completed. File exists", exitStatus: 70)) {
                try XCArchive.assemble(intermediates: intermediates, archivePath: archive, schemeName: "App", creationDate: Date())
            }
            #expect(FileSystem.isFile(archive + "/Signatures/plain.txt"))
            #expect(!FileSystem.isFile(archive + "/Info.plist"))
        }
    }

    @Test func assemblesTheArchive() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-archive")
        let intermediates = try Self.intermediates(in: temporary.path)
        let archive = temporary.path + "/Shop.xcarchive"
        try XCArchive.assemble(intermediates: intermediates, archivePath: archive, schemeName: "App",
                               creationDate: Date(timeIntervalSince1970: 1_792_654_318))
        #expect(!FileManager.default.fileExists(atPath: intermediates + "/InstallationBuildProductsLocation"))
        #expect(try FileSystem.sortedContents(of: archive) == ["Info.plist", "Products", "SwiftSupport", "dSYMs"])
        #expect(try FileSystem.sortedContents(of: archive + "/dSYMs") == ["App.app.dSYM", "Watch.app.dSYM"])
        let dwarf = archive + "/dSYMs/App.app.dSYM/Contents/Resources/DWARF/App"
        let time = try FileManager.default.attributesOfItem(atPath: dwarf)[.modificationDate] as? Date
        #expect(time == Date(timeIntervalSince1970: ArchiveExporterTests.dwarfTime))
        #expect(FileSystem.isFile(archive + "/SwiftSupport/iphoneos/libswiftThing.dylib"))
        #expect(String(decoding: try Data(contentsOf: URL(fileURLWithPath: archive + "/Info.plist")), as: UTF8.self) == """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
            \t<key>ApplicationProperties</key>
            \t<dict>
            \t\t<key>ApplicationPath</key>
            \t\t<string>Applications/App.app</string>
            \t\t<key>Architectures</key>
            \t\t<array>
            \t\t\t<string>arm64</string>
            \t\t</array>
            \t\t<key>CFBundleIdentifier</key>
            \t\t<string>org.nomac.export</string>
            \t\t<key>CFBundleShortVersionString</key>
            \t\t<string>2.1</string>
            \t\t<key>CFBundleVersion</key>
            \t\t<string>7</string>
            \t\t<key>SigningIdentity</key>
            \t\t<string></string>
            \t\t<key>Team</key>
            \t\t<string></string>
            \t</dict>
            \t<key>ArchiveVersion</key>
            \t<integer>2</integer>
            \t<key>CreationDate</key>
            \t<date>2026-10-22T07:31:58Z</date>
            \t<key>Name</key>
            \t<string>App</string>
            \t<key>SchemeName</key>
            \t<string>App</string>
            </dict>
            </plist>

            """)
    }

    /// `DEBUG_INFORMATION_FORMAT=dwarf` (`archive-nodsym`): an empty `dSYMs` folder.
    @Test func keepsAnEmptyDSYMsFolder() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-archive")
        let intermediates = try Self.intermediates(in: temporary.path)
        try FileManager.default.removeItem(atPath: intermediates + "/BuildProductsPath")
        try XCArchive.assemble(intermediates: intermediates, archivePath: temporary.path + "/App.xcarchive", schemeName: "App", creationDate: Date())
        #expect(try FileSystem.sortedContents(of: temporary.path + "/App.xcarchive/dSYMs").isEmpty)
        #expect(!FileManager.default.fileExists(atPath: temporary.path + "/App.xcarchive/SwiftSupport"))
    }

    /// `archive-nested-dsyms`: every `*.dSYM` under the products folder, CocoaPods' prebuilt pods'
    /// included, depth first in APFS order; names taken get " 1", " 2" in that order.
    @Test func collectsNestedDSYMs() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-archive")
        let products = temporary.path + "/Release-iphoneos"
        for (path, marker) in [("Kit.framework.dSYM", "top"), ("XCFrameworkIntermediates/Dup/dSYMs/Kit.framework.dSYM", "pods"),
                               ("a/Kit.framework.dSYM", "a"), ("XCFrameworkIntermediates/Pod/Pod.framework.dSYM", "pod"),
                               ("XCFrameworkIntermediates/Pod/Pod.framework.dSYM/Contents/Nested.framework.dSYM", "nested"),
                               ("XCFrameworkIntermediates/Pod2/dSYMs/Pod2.framework.dSYM", "pod2"), ("Wrapper.bundle/Inner.framework.dSYM", "inner")] {
            try temporary.writeExactly(marker, to: "Release-iphoneos/\(path)/Contents/Resources/marker")
        }
        try temporary.writeExactly("", to: "Release-iphoneos/XCFrameworkIntermediates/Pod/File.dSYM")
        try FileSystem.createDirectory(products + "/link")
        try FileManager.default.createSymbolicLink(atPath: products + "/link/Linked.framework.dSYM",
                                                   withDestinationPath: "../XCFrameworkIntermediates/Pod/Pod.framework.dSYM")
        try FileManager.default.createSymbolicLink(atPath: products + "/linkdir", withDestinationPath: "XCFrameworkIntermediates/Pod2")
        let destination = temporary.path + "/dSYMs"
        try FileSystem.createDirectory(destination)
        var names = Set<String>()
        try XCArchive.collectDSYMs(in: products, to: destination, names: &names)

        #expect(try FileSystem.sortedContents(of: destination) == [
            "File.dSYM", "Inner.framework.dSYM", "Kit.framework 1.dSYM", "Kit.framework 2.dSYM", "Kit.framework.dSYM",
            "Linked.framework.dSYM", "Nested.framework.dSYM", "Pod.framework.dSYM", "Pod2.framework.dSYM",
        ])
        let marker = { (name: String) in String(decoding: FileSystem.contents(atPath: destination + "/\(name)/Contents/Resources/marker") ?? Data(), as: UTF8.self) }
        #expect([marker("Kit.framework.dSYM"), marker("Kit.framework 1.dSYM"), marker("Kit.framework 2.dSYM")] == ["pods", "top", "a"])
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: destination + "/Linked.framework.dSYM")
            == "../XCFrameworkIntermediates/Pod/Pod.framework.dSYM")
        #expect(FileSystem.exists(destination + "/Pod.framework.dSYM/Contents/Nested.framework.dSYM"))
    }

    /// A framework's archive (`archive-products-framework`) and one of two apps
    /// (`archive-products-apps`) are generic: no `ApplicationProperties`.
    @Test func writesGenericArchives() throws {
        for twoApps in [false, true] {
            let temporary = try TemporaryDirectory(prefix: "nomac-archive")
            let intermediates = try Self.intermediates(in: temporary.path)
            let installed = intermediates + "/InstallationBuildProductsLocation"
            if twoApps {
                try FileManager.default.copyItem(atPath: installed + "/Applications/App.app", toPath: installed + "/Applications/App2.app")
            } else {
                try FileSystem.createDirectory(installed + "/Library/Frameworks")
                try FileManager.default.moveItem(atPath: installed + "/Applications/App.app/Frameworks/Kit.framework", toPath: installed + "/Library/Frameworks/Kit.framework")
                try FileManager.default.removeItem(atPath: installed + "/Applications")
            }
            try XCArchive.assemble(intermediates: intermediates, archivePath: temporary.path + "/Kit.xcarchive", schemeName: "Kit",
                                   creationDate: Date(timeIntervalSince1970: 1_792_654_318))
            #expect(try PropertyListValue.parseXML(try Data(contentsOf: URL(fileURLWithPath: temporary.path + "/Kit.xcarchive/Info.plist")), path: "Info.plist")
                == .dictionary(["ArchiveVersion": .integer(2), "CreationDate": .date("2026-10-22T07:31:58Z"), "Name": .string("Kit"), "SchemeName": .string("Kit")]))
        }
    }

    /// One app beside an installed framework, library or tool is generic
    /// (`archive-products-installs-framework`, `-app-library`, `-app-tool`, `-app-tool-opt`),
    /// beside its on-demand resources' asset packs not (`odr`), and a build that installs
    /// nothing gives an empty `Products` (`archive-products-nothing`).
    @Test func classifiesAppsBesideOtherProducts() throws {
        for (other, generic) in [("Library/Frameworks", true), ("usr/local/lib", true), ("usr/local/bin", true), ("opt/nomac", true),
                                 ("OnDemandResources/org.nomac.level1-0.assetpack", false)] {
            let temporary = try TemporaryDirectory(prefix: "nomac-archive")
            let intermediates = try Self.intermediates(in: temporary.path)
            try FileSystem.createDirectory(intermediates + "/InstallationBuildProductsLocation/" + other)
            try XCArchive.assemble(intermediates: intermediates, archivePath: temporary.path + "/App.xcarchive", schemeName: "App", creationDate: Date())
            let info = try PropertyLists.readDictionary(at: temporary.path + "/App.xcarchive/Info.plist")
            #expect((info["ApplicationProperties"] == nil) == generic, "\(other)")
        }
        let temporary = try TemporaryDirectory(prefix: "nomac-archive")
        let intermediates = try Self.intermediates(in: temporary.path)
        try FileManager.default.removeItem(atPath: intermediates + "/InstallationBuildProductsLocation")
        try XCArchive.assemble(intermediates: intermediates, archivePath: temporary.path + "/Kit.xcarchive", schemeName: "Kit", creationDate: Date())
        #expect(try FileSystem.sortedContents(of: temporary.path + "/Kit.xcarchive/Products").isEmpty)
    }
}
