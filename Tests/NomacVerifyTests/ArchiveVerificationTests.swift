import Foundation
import Testing
@testable import NomacVerify

/// The signing and export checks against an archive capture made in a temporary folder, with a
/// stand-in for nomac whose codesign and export write what codesign and xcodebuild wrote.
@Suite struct ArchiveVerificationTests {
    let root: String
    var archive: String { root + "/reference/archive" }

    init() throws {
        root = NSTemporaryDirectory() + "nomac-archive-verification-" + UUID().uuidString
        let kit = archive + "/codesign/sign.B"
        try write("1.5\n", to: kit + "/time")
        try write("--force\n--sign\n-\n--entitlements\n/dd/Kit.xcent\n/dd/App.app/Frameworks/Kit.framework\n", to: kit + "/arguments")
        try write("<plist/>", to: kit + "/entitlements")
        try write("0\n", to: kit + "/status")
        try write("", to: kit + "/stdout")
        try write("kit", to: kit + "/before/Kit.framework/Kit")
        try write("kit, signed", to: kit + "/after/Kit.framework/Kit")
        let app = archive + "/codesign/sign.A"
        try write("2.25\n", to: app + "/time")
        try write("--force\n--sign\n-\n/dd/App.app\n", to: app + "/arguments")
        try write("0\n", to: app + "/status")
        try write("", to: app + "/stdout")
        try write("app", to: app + "/before/App.app/App")
        try write("app, signed", to: app + "/after/App.app/App")
        try write("resources", to: app + "/after/App.app/_CodeSignature/CodeResources")
        try write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\">\n<dict>\n\t<key>method</key>\n\t<string>debugging</string>\n</dict>\n</plist>\n",
                  to: archive + "/ExportOptions.plist")
        try write("<plist/>", to: archive + "/App.xcarchive/Info.plist")
        try write("summary", to: archive + "/export/DistributionSummary.plist")
        try write("Xcode's log", to: archive + "/export/Packaging.log")
        try Self.zip(time: 0x1234, owner: 501, payloadMode: 0o755).write(to: URL(fileURLWithPath: archive + "/export/App.ipa"))
        try write("summary", to: root + "/nomac-export/DistributionSummary.plist")
        try write("nomac's log", to: root + "/nomac-export/Packaging.log")
        try Self.zip(time: 0x4321, owner: 1001, payloadMode: 0o775).write(to: URL(fileURLWithPath: root + "/nomac-export/App.ipa"))
        try write("""
            #!/bin/sh
            command=$1; shift
            if [ "$command" = export ]; then mkdir -p "$4" && cp "\(root)/nomac-export/"* "$4/"; exit; fi
            for product; do :; done
            case "$product" in
              */Kit.framework) [ "$4" = --entitlements ] && [ -f "$5" ] && [ "${5##*/}" = entitlements ] || exit 1
                               printf 'kit, signed' > "$product/Kit";;
              */App.app) printf 'app, signed' > "$product/App"
                         mkdir "$product/_CodeSignature" && printf resources > "$product/_CodeSignature/CodeResources";;
            esac
            """, to: root + "/nomac")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root + "/nomac")
    }

    func write(_ text: String, to path: String) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: URL(fileURLWithPath: path))
    }

    func checks() throws -> [VerificationReport.Check] {
        try ArchiveVerification(referenceDirectory: root + "/reference", nomacExecutable: root + "/nomac", scratchDirectory: root + "/scratch").checks()
    }

    /// A stored zip of `Payload/` and one file, with the given DOS time, owner in each `UX` field,
    /// and permissions of `Payload/`.
    static func zip(time: UInt16, owner: UInt16, payloadMode: UInt32, contents: String = "binary") -> Data {
        var local = Data(), central = Data()
        func le<T: FixedWidthInteger>(_ value: T) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        let entries: [(String, String, UInt32)] = [("Payload/", "", (0o40000 | payloadMode) << 16), ("Payload/App.app/App", contents, 0o100755 << 16)]
        for (name, contents, attributes) in entries {
            let extra = le(UInt16(0x5855)) + le(UInt16(8)) + le(UInt32(time)) + le(owner) + le(UInt16(20))
            let offset = UInt32(local.count)
            let common = le(UInt16(20)) + le(UInt16(0)) + le(UInt16(0)) + le(time) + le(UInt16(0x5a21)) + le(UInt32(0))
                + le(UInt32(contents.utf8.count)) + le(UInt32(contents.utf8.count)) + le(UInt16(name.utf8.count)) + le(UInt16(extra.count))
            local += le(UInt32(0x04034b50)) + common + Data(name.utf8) + extra + Data(contents.utf8)
            central += le(UInt32(0x02014b50)) + le(UInt16(0x031e)) + common + le(UInt16(0)) + le(UInt16(0)) + le(UInt16(0))
                + le(attributes) + le(offset) + Data(name.utf8) + extra
        }
        return local + central + le(UInt32(0x06054b50)) + le(UInt16(0)) + le(UInt16(0)) + le(UInt16(2)) + le(UInt16(2))
            + le(UInt32(central.count)) + le(UInt32(local.count)) + le(UInt16(0))
    }

    @Test func replaysEachSigningStepAndTheExport() throws {
        defer { try? FileManager.default.removeItem(atPath: root) }
        let checks = try checks()
        #expect(checks.map(\.name) == ["1 Kit.framework --force --sign - --entitlements", "2 App.app --force --sign -", "debugging"])
        #expect(checks.map(\.kind) == ["signing", "signing", "export"])
        #expect(checks.map(\.status) == [.identical, .identical, .identical])
    }

    @Test func listsWhatASigningStepOrTheExportChanged() throws {
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("app, signed by codesign", to: archive + "/codesign/sign.A/after/App.app/App")
        try write("other", to: archive + "/codesign/sign.A/after/App.app/Info.plist")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: archive + "/codesign/sign.A/after/App.app/_CodeSignature/CodeResources")
        try write("summary with embeddedBinaries", to: root + "/nomac-export/DistributionSummary.plist")
        let checks = try checks()
        #expect(checks[1].status == .different)
        #expect(checks[1].detail == ["different App", "missing Info.plist", "different _CodeSignature/CodeResources"])
        #expect(checks[2].status == .different)
        #expect(checks[2].detail == ["different DistributionSummary.plist"])
    }

    @Test func aRefusalCountsAsRefused() throws {
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write("--force\n--sign\n-\n/dd/App.app/Frameworks/Kit.framework\n", to: archive + "/codesign/sign.B/arguments")
        #expect(try checks()[0].status == .refused)
    }

    @Test func zipsDifferingInTimesAndOwnersOnlyAreTheSame() throws {
        let made = ArchiveVerification.zipWithoutTimes(Self.zip(time: 0x1234, owner: 501, payloadMode: 0o755))
        #expect(made != nil)
        #expect(made == ArchiveVerification.zipWithoutTimes(Self.zip(time: 0x4321, owner: 1001, payloadMode: 0o775)))
        #expect(made != ArchiveVerification.zipWithoutTimes(Self.zip(time: 0x1234, owner: 501, payloadMode: 0o755, contents: "BINARY")))
        #expect(ArchiveVerification.zipWithoutTimes(Data("not a zip".utf8)) == nil)
    }
}
