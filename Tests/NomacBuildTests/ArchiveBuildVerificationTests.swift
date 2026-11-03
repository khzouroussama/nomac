import Foundation
import NomacCore
import NomacPackaging
import NomacTestSupport
import Testing
@testable import NomacBuild

/// B-188: what `nomac verify` reads of an archive and IPA that nomac built.
@Suite struct ArchiveBuildVerificationTests {
    @Test func readsTheZipArchivesThatExportsWrite() throws {
        let tmp = try TemporaryDirectory()
        let text = String(repeating: "Payload of a test app\n", count: 200)
        try tmp.writeExactly(text, to: "in/Payload/App.app/Info.plist")
        try tmp.writeExactly("", to: "in/Payload/App.app/empty")
        try tmp.writeExactly("#!/bin/sh\n", to: "in/Payload/App.app/App")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path + "/in/Payload/App.app/App")
        try FileManager.default.createSymbolicLink(atPath: tmp.path + "/in/Payload/App.app/Current", withDestinationPath: "Info.plist")
        try DittoArchive.create(from: tmp.path + "/in", to: tmp.path + "/App.ipa")

        let zip = try ZipArchive(path: tmp.path + "/App.ipa")
        let entries = Dictionary(uniqueKeysWithValues: zip.entries.map { ($0.name, $0) })
        #expect(entries["Payload/App.app/Info.plist"]?.contents == Array(text.utf8))
        #expect(entries["Payload/App.app/empty"]?.contents == [])
        #expect(entries["Payload/App.app/App"].map { $0.mode & 0o7777 } == 0o755)
        #expect(entries["Payload/App.app/Current"]?.isSymbolicLink == true)
        #expect(entries["Payload/"]?.isDirectory == true)

        try zip.extract(to: tmp.path + "/out")
        #expect(FileSystem.contents(atPath: tmp.path + "/out/Payload/App.app/Info.plist") == Data(text.utf8))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: tmp.path + "/out/Payload/App.app/Current") == "Info.plist")
    }

    /// A thin arm64 Mach-O header with only `LC_CODE_SIGNATURE`, and a superblob of a version
    /// 0x20400 code directory and an entitlements blob (`<kern/cs_blobs.h>`).
    static func signed(identifier: String, hashes: UInt8, codeLimit: UInt32, entitlements: String = "<dict/>") -> [UInt8] {
        func le(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) } }
        func be(_ value: UInt32) -> [UInt8] { le(value).reversed() }
        func be64(_ value: UInt64) -> [UInt8] { be(UInt32(value >> 32)) + be(UInt32(truncatingIfNeeded: value)) }
        let name = Array(identifier.utf8) + [0]
        let identOffset: UInt32 = 88
        let hashOffset = identOffset + UInt32(name.count) + 32
        var directory = be(0xfade_0c02) + be(0) + be(0x20400) + be(0x2_0002) + be(hashOffset) + be(identOffset)
        directory += be(1) + be(1) + be(codeLimit) + [32, 2, 0, 14] + be(0) + be(0) + be(0) + be(0) + be64(0)
        directory += be64(0) + be64(UInt64(codeLimit)) + be64(1)
        directory += name + [UInt8](repeating: hashes, count: 32 * 2)
        directory.replaceSubrange(4..<8, with: be(UInt32(directory.count)))
        let entitlementsBlob = be(0xfade_7171) + be(UInt32(8 + entitlements.utf8.count)) + Array(entitlements.utf8)
        let superblobHeader = 12 + 2 * 8
        var superblob = be(0xfade_0cc0) + be(UInt32(superblobHeader + directory.count + entitlementsBlob.count)) + be(2)
        superblob += be(0) + be(UInt32(superblobHeader)) + be(5) + be(UInt32(superblobHeader + directory.count))
        superblob += directory + entitlementsBlob
        let header = le(0xfeed_facf) + le(0x0100_000c) + le(0) + le(2) + le(1) + le(16) + le(0) + le(0)
        return header + le(0x1d) + le(16) + le(48) + le(UInt32(superblob.count)) + superblob
    }

    @Test func signaturesOfOtherBytesWithTheSameOptionsAreTheSameFields() throws {
        let path = "/test"
        let xcode = try CodeSignatureFields(file: MachOReader(bytes: Self.signed(identifier: "dev.nomac.App", hashes: 1, codeLimit: 4096), path: path))
        let other = try CodeSignatureFields(file: MachOReader(bytes: Self.signed(identifier: "dev.nomac.App", hashes: 2, codeLimit: 8192), path: path))
        #expect(xcode != nil && xcode == other)
        #expect(xcode?.fields["slot 0x0 identifier"] == "dev.nomac.App")
        #expect(xcode?.fields["slot 0x0 flags"] == "0x20002")

        let renamed = try CodeSignatureFields(file: MachOReader(bytes: Self.signed(identifier: "dev.nomac.Other", hashes: 1, codeLimit: 4096), path: path))
        let entitled = try CodeSignatureFields(file: MachOReader(bytes: Self.signed(identifier: "dev.nomac.App", hashes: 1, codeLimit: 4096, entitlements: "<dict><key>a</key><true/></dict>"), path: path))
        #expect(CodeSignatureFields.differences(xcode!, renamed!) == ["code signature slot 0x0 identifier: dev.nomac.App in Xcode's, dev.nomac.Other in nomac's"])
        #expect(CodeSignatureFields.differences(xcode!, entitled!).count == 1)
        #expect(CodeSignatureFields.differences(xcode!, entitled!).first?.hasPrefix("code signature slot 0x5 blob 0xfade7171:") == true)
    }

    @Test func codeResourcesMayDifferOnlyForFilesThatDiffer() throws {
        let tmp = try TemporaryDirectory()
        func resources(_ hashes: [String: String], rules: String = "a") throws -> String {
            let path = tmp.path + "/\(UUID().uuidString).plist"
            let files = hashes.mapValues { ["hash2": Data($0.utf8)] }
            let data = try PropertyListSerialization.data(fromPropertyList: ["files2": files, "rules2": ["^.*": rules]], format: .xml, options: 0)
            try data.write(to: URL(fileURLWithPath: path))
            return path
        }
        let xcode = try resources(["Info.plist": "1", "main.jsbundle": "2", "Frameworks/A.framework": "3"])
        let changed: Set<String> = ["App.app/Info.plist", "App.app/Frameworks/A.framework/A"]
        let consequence = try resources(["Info.plist": "9", "main.jsbundle": "2", "Frameworks/A.framework": "8"])
        #expect(try ArchiveBuildVerification.codeResourcesOutcome(xcode, consequence, bundle: "App.app/", changed: changed)
            == .equivalent(["the hashes of the files that differ themselves"]))
        let unexplained = try resources(["Info.plist": "1", "main.jsbundle": "7", "Frameworks/A.framework": "3"])
        #expect(try ArchiveBuildVerification.codeResourcesOutcome(xcode, unexplained, bundle: "App.app/", changed: changed)
            == .different(["files2 main.jsbundle: another hash for a file that is identical"]))
        let otherRules = try resources(["Info.plist": "1", "main.jsbundle": "2", "Frameworks/A.framework": "3"], rules: "b")
        #expect(try ArchiveBuildVerification.codeResourcesOutcome(xcode, otherRules, bundle: "App.app/", changed: changed) == .different(["rules2 differs"]))
    }

    @Test func archivesWithTheCapturesCommandButNomacsSigning() {
        let captured = ["-workspace", "App.xcworkspace", "-scheme", "App", "-archivePath", "/ref/archive/App.xcarchive",
                        "CODE_SIGN_IDENTITY=-", "CODESIGN=/ref/archive/codesign-wrapper.sh", "archive"]
        #expect(ArchiveBuildVerification.arguments(captured, archivePath: "/scratch/App.xcarchive")
            == ["-workspace", "App.xcworkspace", "-scheme", "App", "-archivePath", "/scratch/App.xcarchive", "CODE_SIGN_IDENTITY=-"])
    }

    /// netnewswire's ad hoc archive capture: xcodebuild exits with 65 and one "requires a
    /// provisioning profile" error per target with an entitlements file.
    @Test func comparesARefusedArchiveByStatusAndErrors() throws {
        let tmp = try TemporaryDirectory()
        let error = ": error: \"App\" requires a provisioning profile. (in target 'App' from project 'App')"
        let argv = ["sandbox-exec", "-p", "(version 1)", "xcodebuild", "-project", "/private/tmp/ref/App.xcodeproj", "-scheme", "App",
                    "-archivePath", "/ref/archive/App.xcarchive", "CODE_SIGN_IDENTITY=-", "archive"]
        try tmp.writeExactly(String(decoding: try JSONSerialization.data(withJSONObject: ["argv": argv, "exitStatus": 65]), as: UTF8.self),
                             to: "reference/archive/archive.log.cmd")
        try tmp.writeExactly("note: a note\n/tmp/ref/App.xcodeproj\(error)\n", to: "reference/archive/archive.log")
        try tmp.writeExactly(#"{"path": "/private/tmp/ref"}"#, to: "reference/source.json")
        try FileSystem.createDirectory(tmp.path + "/source")
        try tmp.writeExactly(error + "\n", to: "error.txt")
        let printError = "printf '%s' \"$3\"\ncat '\(tmp.path)/error.txt'\n"
        func check(_ script: String) throws -> ArchiveBuildVerification.Check {
            try tmp.writeExactly("#!/bin/sh\n" + script, to: "nomac")
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path + "/nomac")
            let verification = ArchiveBuildVerification(referenceDirectory: tmp.path + "/reference", sourceRoot: tmp.path + "/source",
                                                        developerDirectory: "/Xcode.app/Contents/Developer", nomacExecutable: tmp.path + "/nomac",
                                                        scratchDirectory: tmp.path + "/scratch")
            return try #require(try verification.checks().first)
        }
        let same = try check(printError + "echo '** ARCHIVE FAILED **' >&2\nexit 65\n")
        #expect(same.status == .identical)
        #expect(same.detail == ["xcodebuild archive exited with status 65", "nomac archive exits with the same status and the same 1 errors"])
        #expect(try check(printError + "exit 1\n").status == .different)
        let other = try check("echo 'error: another'\nexit 65\n")
        #expect(other.status == .different)
        #expect(other.detail.suffix(2) == ["only in Xcode's: <source>/App.xcodeproj\(error)", "only in nomac's: error: another"])
    }
}
