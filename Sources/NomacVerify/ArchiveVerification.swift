import Foundation
import NomacCore

/// `nomac verify`'s packaging checks, from a reference's ad-hoc archive capture (`archive/`,
/// corpus/scripts/capture_reference.py --archive): every codesign step of Xcode's archive build
/// replayed with `nomac codesign` on the product as it was before the step (`signing`), and the
/// archive exported with `nomac export` and the capture's export options (`export`)
/// (docs/VERIFICATION.md "Signing and export checks").
public struct ArchiveVerification {
    public typealias Check = VerificationReport.Check

    public var referenceDirectory: String
    /// The `nomac` executable whose `codesign` and `export` run.
    public var nomacExecutable: String
    /// Where the replays write; emptied before each.
    public var scratchDirectory: String
    /// How many lines of a refusal or entries of a difference to list.
    public var detailLimit: Int

    public init(referenceDirectory: String, nomacExecutable: String, scratchDirectory: String, detailLimit: Int = 10) {
        self.referenceDirectory = referenceDirectory
        self.nomacExecutable = nomacExecutable
        self.scratchDirectory = scratchDirectory
        self.detailLimit = detailLimit
    }

    /// The signing checks in the order the steps ran, then the export check; none without an
    /// archive capture.
    public func checks() throws -> [Check] {
        let archive = referenceDirectory + "/archive"
        guard FileSystem.isDirectory(archive + "/codesign") else { return [] }
        let steps = try FileSystem.sortedContents(of: archive + "/codesign").filter { $0.hasPrefix("sign.") }.map { archive + "/codesign/" + $0 }
        let times = Dictionary(uniqueKeysWithValues: steps.map { ($0, Double(text($0 + "/time").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) })
        var checks = try steps.sorted { times[$0]! < times[$1]! }.enumerated().map { try signingCheck(step: $1, number: $0 + 1) }
        checks.append(try exportCheck(archive))
        return checks
    }

    func text(_ path: String) -> String {
        FileSystem.contents(atPath: path).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    func refusal(_ result: Subprocess.Result, _ command: String) -> [String] {
        ["nomac \(command) exited with status \(result.exitStatus)"] + (result.errorString + result.outputString).split(separator: "\n").prefix(detailLimit).map(String.init)
    }

    func limited(_ differences: [String]) -> [String] {
        differences.count > detailLimit ? differences.prefix(detailLimit) + ["... \(differences.count - detailLimit) more"] : differences
    }

    func signingCheck(step: String, number: Int) throws -> Check {
        let arguments = text(step + "/arguments").split(separator: "\n", omittingEmptySubsequences: false).map(String.init).dropLast()
        let product = arguments.last ?? ""
        let name = (product as NSString).lastPathComponent
        var replayed = Array(arguments.dropLast())
        var label = replayed
        if let index = replayed.firstIndex(of: "--entitlements"), index + 1 < replayed.count {
            replayed[index + 1] = step + "/entitlements"
            label.remove(at: index + 1)
        }
        let check = { (status: Check.Status, detail: [String]) in
            Check(kind: "signing", name: "\(number) \(name) \(label.joined(separator: " "))", status: status, detail: detail)
        }
        let work = scratchDirectory + "/signing"
        let manager = FileManager.default
        if manager.fileExists(atPath: work) { try manager.removeItem(atPath: work) }
        try FileSystem.createDirectory(work)
        try manager.copyItem(atPath: step + "/before/" + name, toPath: work + "/" + name)
        let result = try Subprocess.run(nomacExecutable, ["codesign"] + replayed + [work + "/" + name])
        let expectedStatus = Int32(text(step + "/status").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        if result.exitStatus != 0 && expectedStatus == 0 {
            return check(.refused, refusal(result, "codesign"))
        }
        var differences = try Self.treeDifferences(expected: step + "/after/" + name, actual: work + "/" + name)
        if result.exitStatus != expectedStatus {
            differences.insert("exit status \(result.exitStatus), codesign's \(expectedStatus)", at: 0)
        }
        if FileSystem.contents(atPath: step + "/stdout") != result.standardOutput {
            differences.append("standard output differs")
        }
        return check(differences.isEmpty ? .identical : .different, limited(differences))
    }

    func exportCheck(_ archive: String) throws -> Check {
        let options = archive + "/ExportOptions.plist"
        let method = FileSystem.contents(atPath: options)
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }?["method"] as? String ?? ""
        let check = { (status: Check.Status, detail: [String]) in Check(kind: "export", name: method, status: status, detail: detail) }
        let xcode = archive + "/export"
        guard let xcarchive = try FileSystem.sortedContents(of: archive).first(where: { $0.hasSuffix(".xcarchive") }), FileSystem.isDirectory(xcode) else {
            return check(.referenceFailed, ["the capture has no export: xcodebuild's archive or export failed"])
        }
        let ours = scratchDirectory + "/export"
        if FileManager.default.fileExists(atPath: ours) { try FileManager.default.removeItem(atPath: ours) }
        let result = try Subprocess.run(nomacExecutable, ["export", "-archivePath", archive + "/" + xcarchive, "-exportPath", ours, "-exportOptionsPlist", options])
        guard result.exitStatus == 0 else { return check(.refused, refusal(result, "export")) }
        // Packaging.log records times and the machine.
        let names = Set(try FileSystem.sortedContents(of: xcode)).union(try FileSystem.sortedContents(of: ours)).subtracting(["Packaging.log"])
        var differences: [String] = []
        for name in names.sorted() {
            let expected = xcode + "/" + name, actual = ours + "/" + name
            guard FileManager.default.fileExists(atPath: expected) else { differences.append("extra \(name)"); continue }
            guard FileManager.default.fileExists(atPath: actual) else { differences.append("missing \(name)"); continue }
            if FileSystem.isDirectory(expected) {
                differences += try Self.treeDifferences(expected: expected, actual: actual).map { "\(name)/\($0)" }
            } else if name.hasSuffix(".ipa") {
                let left = FileSystem.contents(atPath: expected).flatMap(Self.zipWithoutTimes)
                let right = FileSystem.contents(atPath: actual).flatMap(Self.zipWithoutTimes)
                if left == nil || left != right { differences.append("different \(name)") }
            } else if FileSystem.contents(atPath: expected) != FileSystem.contents(atPath: actual) {
                differences.append("different \(name)")
            }
        }
        return check(differences.isEmpty ? .identical : .different, limited(differences))
    }

    /// What differs between two file trees: an entry on one side only, its kind or permissions,
    /// a link's target, a file's bytes.
    static func treeDifferences(expected: String, actual: String) throws -> [String] {
        let left = try entries(expected), right = try entries(actual)
        var differences = left.keys.filter { right[$0] == nil }.sorted().map { "missing \($0)" }
        differences += right.keys.filter { left[$0] == nil }.sorted().map { "extra \($0)" }
        for name in left.keys.filter({ right[$0] != nil }).sorted() where left[name] != right[name] {
            differences.append("different \(name)")
        }
        return differences.sorted { $0.split(separator: " ", maxSplits: 1).last! < $1.split(separator: " ", maxSplits: 1).last! }
    }

    /// An entry of a file tree: its kind and permissions, and a link's target or a file's contents.
    enum Entry: Equatable {
        case directory(mode: Int)
        case link(mode: Int, target: String)
        case file(mode: Int, contents: Data)
    }

    /// Each entry of a tree by its path relative to the root (`.` for the root).
    static func entries(_ root: String) throws -> [String: Entry] {
        let manager = FileManager.default
        var found: [String: Entry] = [:]
        func visit(_ path: String, _ relative: String) throws {
            let attributes = try manager.attributesOfItem(atPath: path)
            let mode = (attributes[.posixPermissions] as? Int ?? 0) & 0o7777
            switch attributes[.type] as? FileAttributeType {
            case .typeSymbolicLink?:
                found[relative] = .link(mode: mode, target: try manager.destinationOfSymbolicLink(atPath: path))
            case .typeDirectory?:
                found[relative] = .directory(mode: mode)
                for name in try FileSystem.sortedContents(of: path) {
                    try visit(path + "/" + name, relative == "." ? name : relative + "/" + name)
                }
            default:
                found[relative] = .file(mode: mode, contents: FileSystem.contents(atPath: path) ?? Data())
            }
        }
        try visit(root, ".")
        return found
    }

    /// A zip archive with the DOS time and date and the `UX` extra field (times, owner ids) of
    /// every entry zeroed, and the permissions of `Payload/`, which follow the umask, cleared: the
    /// parts of an IPA that depend on when and by whom it was made (the packaging experiments'
    /// comparison, .github/scripts/signing_experiments.py `without_times`). nil when `data` is not
    /// a zip archive.
    static func zipWithoutTimes(_ data: Data) -> Data? {
        var bytes = [UInt8](data)
        func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        func zero(_ range: Range<Int>) { for index in range { bytes[index] = 0 } }
        func clearExtra(_ start: Int, _ length: Int) {
            var position = start
            while position + 4 <= start + length, position + 4 <= bytes.count {
                let size = u16(position + 2)
                if u16(position) == 0x5855, position + 4 + size <= bytes.count { zero((position + 4)..<(position + 4 + size)) }
                position += 4 + size
            }
        }
        guard bytes.count >= 22, let end = (0...(bytes.count - 22)).reversed().first(where: { bytes[$0..<($0 + 4)].elementsEqual([0x50, 0x4b, 0x05, 0x06]) }) else {
            return nil
        }
        var central = u32(end + 16)
        for _ in 0..<u16(end + 10) {
            guard central + 46 <= bytes.count else { return nil }
            let nameLength = u16(central + 28), extraLength = u16(central + 30), commentLength = u16(central + 32)
            let local = u32(central + 42)
            guard central + 46 + nameLength <= bytes.count, local + 30 <= bytes.count else { return nil }
            zero((central + 12)..<(central + 16))
            if bytes[(central + 46)..<(central + 46 + nameLength)].elementsEqual(Array("Payload/".utf8)) {
                zero((central + 38)..<(central + 42))
            }
            clearExtra(central + 46 + nameLength, extraLength)
            zero((local + 10)..<(local + 14))
            clearExtra(local + 30 + u16(local + 26), u16(local + 28))
            central += 46 + nameLength + extraLength + commentLength
        }
        return Data(bytes)
    }
}
