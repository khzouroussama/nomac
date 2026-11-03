import Foundation
import NomacCore
import NomacPlist

/// The Info.plist an app-store-connect export writes again (docs/formats/ipa.md): the same
/// values in the file's own format, binary with every dictionary in Foundation's order
/// (`nested`, `span`, watch and App Clip experiments), XML as Core Foundation writes it, keys in
/// UTF-16 order and tab indentation (observed through xcodebuild with an unsorted XML
/// Info.plist indented with spaces). An asset pack's gets the app's version strings `adding`
/// (`odr` experiment: `CFBundleShortVersionString` and `CFBundleVersion`), the app
/// `TFInternalTestingOnly` with `testFlightInternalTestingOnly` (`distribution_experiments.py`
/// `export-options`).
enum ExportedInfoPlist {
    static func rewrite(at path: String, adding strings: [String: String] = [:], flags: [String: Bool] = [:]) throws {
        let added = strings.mapValues(PropertyListValue.string).merging(flags.mapValues(PropertyListValue.boolean)) { _, flag in flag }
        guard let data = FileManager.default.contents(atPath: path) else { throw NomacError("could not read file", path: path) }
        let bytes = [UInt8](data)
        let rewritten: Data
        if bytes.starts(with: Array("bplist00".utf8)) {
            var value = try BinaryPropertyList.value(from: bytes, path: path)
            if case .dictionary(var entries) = value, !added.isEmpty {
                entries.merge(added) { _, new in new }
                value = .dictionary(entries)
            }
            rewritten = try BinaryPropertyList.foundationData(rereading: value)
        } else if bytes.starts(with: Array("<?xml".utf8)) {
            // An asset pack's XML Info.plist stays XML with the versions added (signing
            // experiments `odr-shapes`, `app-store-connect-xml`).
            var value = try TextPropertyListParser.parse(String(decoding: bytes, as: UTF8.self))
            if case .dictionary(var entries) = value, !added.isEmpty {
                entries.merge(added) { _, new in new }
                value = .dictionary(entries)
            }
            rewritten = XMLPropertyList.data(value)
        } else {
            throw NomacError("exportArchive an Info.plist neither binary nor XML is not supported", path: path, exitStatus: 70)
        }
        let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int ?? 0o644
        try FileSystem.write(rewritten, to: path)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: path)
    }
}
