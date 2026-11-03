import Foundation
import Testing
@testable import NomacPlist

/// What macOS's PlistBuddy does with the commands build scripts run (plistbuddy_experiments.py).
@Suite struct PlistBuddyTests {
    private func file(_ xml: String) throws -> String {
        let path = NSTemporaryDirectory() + "plistbuddy-\(UUID().uuidString).plist"
        try Data(xml.utf8).write(to: URL(fileURLWithPath: path))
        return path
    }

    private let info = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>CFBundleName</key><string>App</string><key>Flag</key><false/>
        <key>Items</key><array><dict><key>Key</key><string>version</string><key>DefaultValue</key><string>0</string></dict></array></dict></plist>
        """

    @Test func printsValuesAndLeavesTheFile() throws {
        let path = try file(info)
        let before = FileManager.default.contents(atPath: path)
        var buddy = try PlistBuddy(path: path)
        let outcome = try buddy.run(["Print :CFBundleName", "print Flag", "Print :Items:0:DefaultValue", "Print :Missing"])
        #expect(outcome.standardOutput == "App\nfalse\n0\n")
        #expect(outcome.standardError == "Print: Entry, \":Missing\", Does Not Exist\n")
        #expect(outcome.failed)
        #expect(FileManager.default.contents(atPath: path) == before)
    }

    @Test func addsSetsAndDeletesThenWritesSortedXML() throws {
        let path = try file(info)
        var buddy = try PlistBuddy(path: path)
        let outcome = try buddy.run(["Delete Missing", "add Build dict", "add :Build:Version string '27.0'", "Set :Items:0:DefaultValue 2.3.4",
                                     "Add :CFBundleName string Other"])
        #expect(outcome.standardError == "Delete: Entry, \"Missing\", Does Not Exist\nAdd: \":CFBundleName\" Entry Already Exists\n")
        let written = String(decoding: try #require(FileManager.default.contents(atPath: path)), as: UTF8.self)
        #expect(written.contains("\t<key>Build</key>\n\t<dict>\n\t\t<key>Version</key>\n\t\t<string>27.0</string>\n\t</dict>\n\t<key>CFBundleName</key>"))
        #expect(written.contains("<key>DefaultValue</key>\n\t\t\t<string>2.3.4</string>"))
    }

    @Test func aFailedChangeStillRewritesAndAMissingFileIsAnnounced() throws {
        let path = try file(info)
        var buddy = try PlistBuddy(path: path)
        _ = try buddy.run(["Set :Missing x"])
        #expect(String(decoding: try #require(FileManager.default.contents(atPath: path)), as: UTF8.self).hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist"))
        let missing = NSTemporaryDirectory() + "plistbuddy-\(UUID().uuidString).plist"
        var created = try PlistBuddy(path: missing)
        let outcome = try created.run(["Print :Key"])
        #expect(outcome.standardOutput == "File Doesn't Exist, Will Create: \(missing)\n")
        #expect(!FileManager.default.fileExists(atPath: missing))
    }

    @Test func printsADictionaryInFoundationsOrder() throws {
        var buddy = try PlistBuddy(path: try file(info))
        let outcome = try buddy.run(["Print :Items:0"])
        #expect(outcome.standardOutput == "Dict {\n    Key = version\n    DefaultValue = 0\n}\n")
    }
}
