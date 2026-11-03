import Foundation
import NomacCore
import NomacDevice
import NomacSigning

/// An `.xctestrun` file as `xcodebuild build-for-testing` writes it (docs/formats/xctestrun.md):
/// format 1, one entry per test target beside `__xctestrun_metadata__`, or format 2, test
/// configurations each listing `TestTargets`. Paths start with `__TESTROOT__`, the file's folder,
/// or `__TESTHOST__`, the target's host app.
public struct XCTestRun: Sendable {
    public struct Entry: Sendable {
        public var name: String
        public var runOrder: Int
        public var values: [String: PropertyListValue]

        func string(_ key: String) -> String? { if case .string(let text)? = values[key] { text } else { nil } }

        func flag(_ key: String) -> Bool { if case .boolean(true)? = values[key] { true } else { false } }

        func strings(_ key: String) -> [String] {
            guard case .array(let items)? = values[key] else { return [] }
            return items.compactMap { if case .string(let text) = $0 { text } else { nil } }
        }

        func environment(_ key: String) -> [String: String] {
            guard case .dictionary(let items)? = values[key] else { return [:] }
            return items.compactMapValues { if case .string(let text) = $0 { text } else { nil } }
        }

        public var isUITest: Bool { flag("IsUITestBundle") }
        public var hostBundleIdentifier: String? { string("TestHostBundleIdentifier") }
        public var hostPath: String? { string("TestHostPath") }
        public var dependentProductPaths: [String] { strings("DependentProductPaths") }
    }

    public var formatVersion: Int
    public var entries: [Entry]
    /// The folder `__TESTROOT__` stands for.
    public var root: String

    public init(path: String) throws {
        let top = try Self.dictionary(at: path)
        root = (path as NSString).deletingLastPathComponent
        if case .dictionary(let metadata)? = top["__xctestrun_metadata__"], case .integer(let version)? = metadata["FormatVersion"] {
            formatVersion = Int(version)
        } else {
            formatVersion = 1
        }
        switch formatVersion {
        case 1:
            entries = top.compactMap { name, value in
                guard name != "__xctestrun_metadata__", case .dictionary(let values) = value else { return nil }
                let order = if case .integer(let order)? = values["RunOrder"] { Int(order) } else { 0 }
                return Entry(name: name, runOrder: order, values: values)
            }.sorted { ($0.runOrder, $0.name) < ($1.runOrder, $1.name) }
        case 2:
            guard case .array(let configurations)? = top["TestConfigurations"], case .dictionary(let first)? = configurations.first,
                  case .array(let targets)? = first["TestTargets"] else {
                throw NomacError("an .xctestrun of format 2 without TestConfigurations", path: path)
            }
            entries = targets.enumerated().compactMap { index, value in
                guard case .dictionary(let values) = value, case .string(let name)? = values["BlueprintName"] else { return nil }
                return Entry(name: name, runOrder: index, values: values)
            }
        default:
            throw NomacError("an .xctestrun of format \(formatVersion), not 1 or 2", path: path)
        }
    }

    static func dictionary(at path: String) throws -> [String: PropertyListValue] {
        guard let bytes = FileManager.default.contents(atPath: path) else { throw NomacError("cannot read the file", path: path) }
        return try PropertyListMessages.dictionary(Array(bytes), source: path)
    }

    /// `path` with `__TESTROOT__` replaced.
    public func resolve(_ path: String) -> String {
        path.replacingOccurrences(of: "__TESTROOT__", with: root)
    }

    /// The apps to install before testing: the dependent products that are apps.
    public var applications: [String] {
        var seen: Set<String> = []
        return entries.flatMap(\.dependentProductPaths).filter { $0.hasSuffix(".app") && seen.insert($0).inserted }.map(resolve)
    }

    /// The test target of `entry`, with the bundle identifier of the app a UI test drives read
    /// from that app's Info.plist.
    public func target(_ entry: Entry, testsToRun: [String] = [], testsToSkip: [String] = []) throws -> TestTarget {
        guard let host = entry.hostBundleIdentifier, let bundlePath = entry.string("TestBundlePath") else {
            throw NomacError("the .xctestrun's \(entry.name) has no TestHostBundleIdentifier or TestBundlePath")
        }
        var targetApplication: String?
        if entry.isUITest, let path = entry.string("UITargetAppPath") {
            let plist = try Self.dictionary(at: resolve(path) + "/Info.plist")
            guard case .string(let identifier)? = plist["CFBundleIdentifier"] else {
                throw NomacError("no CFBundleIdentifier", path: resolve(path) + "/Info.plist")
            }
            targetApplication = identifier
        }
        var environment = entry.environment("EnvironmentVariables")
        environment.merge(entry.environment("TestingEnvironmentVariables")) { $1 }
        return TestTarget(name: entry.name, hostBundleIdentifier: host,
                          testBundleRelativePath: bundlePath.replacingOccurrences(of: "__TESTHOST__/", with: ""),
                          productModuleName: entry.string("ProductModuleName") ?? entry.name, isUITest: entry.isUITest,
                          targetApplication: targetApplication, arguments: entry.strings("CommandLineArguments"), environment: environment,
                          targetArguments: entry.strings("UITargetAppCommandLineArguments"),
                          targetEnvironment: entry.environment("UITargetAppEnvironmentVariables"),
                          testsToRun: testsToRun, testsToSkip: testsToSkip)
    }
}
