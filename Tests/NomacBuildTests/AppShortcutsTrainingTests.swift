import Foundation
import NomacCore
import NomacTestSupport
import NomacLZFSE
import Testing
@testable import NomacBuild

/// App Shortcuts training on hand-written metadata shaped as `.github/scripts/app_intents_experiments.py`'s
/// `training` case writes it.
@Suite struct AppShortcutsTrainingTests {
    static func string(_ key: String) -> [String: Any] { ["alternatives": [Any](), "key": key] }

    static var actionsData: [String: Any] { [
        "actions": [
            "SetMood": ["title": string("Set Mood"), "parameters": [["name": "mood", "valueType": ["linkEnumeration": ["wrapper": ["identifier": "Mood"]]]]]],
            "OpenNote": ["title": string("Open Note"), "parameters": [["name": "note", "valueType": ["entity": ["wrapper": ["typeName": "Note"]]]]]],
            "Search": ["title": string("Search"), "parameters": [[String: Any]]()],
        ],
        "enums": [["identifier": "Mood", "cases": ["Happy", "Sad", "Calm"].map { ["displayRepresentation": ["title": string($0)]] }]],
        "entities": ["Note": ["displayTypeName": string("Memo")]],
        "autoShortcuts": [
            ["actionIdentifier": "SetMood", "phraseTemplates": [string("Set my mood to ${mood} in ${applicationName}"), string("${applicationName} mood")]],
            ["actionIdentifier": "OpenNote", "phraseTemplates": [string("Open ${note} in ${applicationName}")]],
            ["actionIdentifier": "Search", "phraseTemplates": [string("Search ${applicationName}")]],
        ],
    ] }

    static let english = AppShortcutsTraining.Locale(name: "en", applicationName: "Mike's Notes", lists: "en")

    func training(_ locales: [AppShortcutsTraining.Locale] = [english]) throws -> AppShortcutsTraining {
        try AppShortcutsTraining(actionsData: Self.actionsData, bundleIdentifier: "org.nomac.experiment", locales: locales)
    }

    @Test func writesRootSSUYAML() throws {
        let yaml = try training().ssuRoot
        #expect(yaml.hasPrefix("apiVersion: ssu/v1\nnlu:\n  shortcuts:\n    bundleIdentifier: org.nomac.experiment\n    intents:\n    - metadata:\n        name: SetMood_0\n        title: Set Mood\n"))
        #expect(yaml.contains("          utterances:\n          - '{${+prefix} }Set my mood to ${Mood} in ${+applicationName}'\n          - '{${+prefix} }${+applicationName} mood'\n"))
        #expect(yaml.contains("variables:\n- name: +applicationName\n  type: ssu/expansion\n  definitions:\n  - locale: en\n    synomyms:\n    - Mike's Notes\n"
            + "- name: Mood\n  type: ssu/parameter\n  definitions:\n  - locale: en\n    synomyms:\n    - Happy\n    - Sad\n    - Calm\n"
            + "- name: Note\n  type: ssu/parameter\n  definitions:\n  - locale: en\n    synomyms:\n    - Memo\n"))
        #expect(yaml.hasSuffix("- name: +standardAppShortcutNegatives\n  type: ssu/expansion\n  definitions:\n  - locale: en\n    synomyms:\n      $ref: ssu://Resources/standardAppShortcutNegatives/en.yaml\n"))
    }

    @Test func expandsPrefixThenPhraseThenParameter() throws {
        let variables = ["+prefix": ["hey Siri", "Siri"], "Mood": ["Happy", "Sad"], "+applicationName": ["App"]]
        #expect(try AppShortcutsTraining.expand("{${+prefix} }Set ${Mood} in ${+applicationName}", variables)
            == ["Set Happy in App", "Set Sad in App", "hey Siri Set Happy in App", "hey Siri Set Sad in App", "Siri Set Happy in App", "Siri Set Sad in App"])
        #expect(throws: NomacError.self) { try AppShortcutsTraining.expand("${Other}", variables) }
    }

    /// The FlatBuffers layout of `basic`'s and `training`'s `nlu.lzfse`: the header's fields at 20,
    /// 12, 8 and 4 of a 24-byte table, the first utterance table 10 bytes long with its kind at 9,
    /// the later ones 12 with it at 11, each intent's parameter and utterances in order.
    @Test func writesTheNLUBuffer() throws {
        let buffer = try training().nlu(Self.english, lists: (["hey Siri", "Siri"], ["${+applicationName}", "quit ${+applicationName}"]),
                                        hash: String(repeating: "0", count: 32), time: 0x6ae7_d5bd)
        let reader = Reader(bytes: buffer)
        let root = reader.root
        #expect(reader.layout(root) == ([18, 12, 8, 4], 20) && reader.u16(root + 18) == 1)
        let header = reader.table(root, 1)
        #expect(reader.layout(header) == ([20, 12, 8, 4], 24))
        #expect(reader.string(reader.table(header, 0)) == String(repeating: "0", count: 32) && reader.u32(header + 12) == 0x6ae7_d5bd)
        #expect(reader.u32(reader.table(header, 2)) == 0 && reader.string(reader.table(header, 3)) == "1.0")
        #expect(reader.string(reader.table(root, 2)) == "en")
        let bundle = reader.vector(reader.vector(reader.table(root, 3))[0], field: 1)[0]
        #expect(reader.string(reader.table(bundle, 0)) == "org.nomac.experiment")
        let intents = reader.vector(bundle, field: 1)
        func utterances(_ table: Int, field: Int) -> [String] {
            reader.vector(table, field: field).map { reader.string(reader.table(reader.table($0, 1), 0)) }
        }
        #expect(intents.map { reader.string(reader.table($0, 0)) } == ["SetMood_0", "OpenNote_1", "Search_2"])
        #expect(reader.vector(intents[0], field: 1).map { [reader.string(reader.table($0, 0)), reader.string(reader.table($0, 1))] } == [["Mood", "Happy"]])
        #expect(reader.vector(intents[2], field: 1).isEmpty)
        #expect(utterances(intents[0], field: 2) == [
            "Set my mood to Happy in Mike's Notes", "Set my mood to Sad in Mike's Notes", "Set my mood to Calm in Mike's Notes",
            "hey Siri Set my mood to Happy in Mike's Notes", "hey Siri Set my mood to Sad in Mike's Notes", "hey Siri Set my mood to Calm in Mike's Notes",
            "Siri Set my mood to Happy in Mike's Notes", "Siri Set my mood to Sad in Mike's Notes", "Siri Set my mood to Calm in Mike's Notes",
            "Mike's Notes mood", "hey Siri Mike's Notes mood", "Siri Mike's Notes mood",
        ])
        #expect(utterances(intents[1], field: 2) == ["Open Memo in Mike's Notes", "hey Siri Open Memo in Mike's Notes", "Siri Open Memo in Mike's Notes"])
        #expect(utterances(bundle, field: 2) == ["Mike's Notes", "quit Mike's Notes", "hey Siri Mike's Notes", "hey Siri quit Mike's Notes", "Siri Mike's Notes", "Siri quit Mike's Notes"])
        let first = reader.vector(intents[0], field: 2)
        #expect(reader.layout(first[0]) == ([9, 4], 10) && reader.layout(first[1]) == ([11, 4], 12) && buffer[first[0] + 9] == 1)
        #expect(buffer.count % 8 == 0)
    }

    /// nomac verify: the training's time counts as equivalent; the digest, whose input is not
    /// known, and the utterances are reported.
    @Test func judgesTrainingsThatDifferOnlyInTimeEquivalent() throws {
        let tmp = try TemporaryDirectory()
        func nlu(_ name: String, digest: String, time: UInt64, applicationName: String = "Mike's Notes") throws -> String {
            let locale = AppShortcutsTraining.Locale(name: "en", applicationName: applicationName, lists: "en")
            let buffer = try training([locale]).nlu(locale, lists: (["Siri"], ["${+applicationName}"]), hash: digest, time: time)
            let path = tmp.path + "/\(name)/App.app/Metadata.appintents/nlu/nlu.lzfse"
            try FileSystem.write(Data(LZFSE.encode(buffer)), to: path)
            return path
        }
        let digest = String(repeating: "a", count: 32)
        let reference = try nlu("xcode", digest: digest, time: 1_793_578_429)
        let compressed = try #require(FileManager.default.contents(atPath: reference))
        let header = try #require(AppShortcutsTraining.header(try LZFSE.decode([UInt8](compressed))))
        #expect(header.digest.count == 32 && header.time.count == 8)
        #expect(try BuildProducts.compareFile(reference, try nlu("later", digest: digest, time: 1_793_579_000))
            == .equivalent([BuildProducts.documented["appintents.training-time"]!]))
        #expect(try BuildProducts.compareFile(reference, try nlu("digest", digest: String(repeating: "b", count: 32), time: 1_793_579_000))
            == .different(["the header's digest differs (\(digest) in Xcode's), whose input is not known (B-159)"]))
        #expect(try BuildProducts.compareFile(reference, try nlu("name", digest: digest, time: 1_793_578_429, applicationName: "Notes"))
            == .different(["the training's utterances differ"]))
    }

    /// One shortcut whose phrases use two parameters (`phrases`): both are listed, in the order
    /// the phrases first use them; verify reads them as a set, Xcode writing them in set order.
    @Test func trainsSeveralParametersOfOneShortcut() throws {
        var data = Self.actionsData
        data["actions"] = ["Log": ["title": Self.string("Log"), "parameters": [
            ["name": "mood", "valueType": ["linkEnumeration": ["wrapper": ["identifier": "Mood"]]]],
            ["name": "note", "valueType": ["entity": ["wrapper": ["typeName": "Note"]]]],
        ]]]
        data["autoShortcuts"] = [["actionIdentifier": "Log", "phraseTemplates": [Self.string("Log ${mood} in ${applicationName}"), Self.string("Log ${note} in ${applicationName}")]]]
        let training = try AppShortcutsTraining(actionsData: data, bundleIdentifier: "org.nomac.experiment", locales: [Self.english])
        let buffer = try training.nlu(Self.english, lists: (["Siri"], []), hash: String(repeating: "0", count: 32), time: 0)
        let contents = try #require(AppShortcutsTraining.contents(buffer))
        #expect(contents.prefix(4) == ["locale en", "bundle org.nomac.experiment", "intent Log_0", "parameter Mood=Happy"])
        #expect(contents[4] == "parameter Note=Memo" && contents.contains("utterance Siri Log Memo in Mike's Notes"))
        let reader = Reader(bytes: buffer)
        let intent = reader.vector(reader.vector(reader.vector(reader.table(reader.root, 3))[0], field: 1)[0], field: 1)[0]
        #expect(reader.vector(intent, field: 1).map { reader.string(reader.table($0, 0)) } == ["Mood", "Note"])
    }

    @Test func trainsFromTheBuildsOptions() throws {
        let tmp = try TemporaryDirectory()
        let app = tmp.path + "/App.app"
        try FileSystem.write(try JSONSerialization.data(withJSONObject: Self.actionsData), to: app + "/Metadata.appintents/extract.actionsdata")
        try FileSystem.write(try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "org.nomac.experiment", "CFBundleDisplayName": "Mike's Notes"],
                                                                 format: .binary, options: 0), to: app + "/Info.plist")
        let resources = tmp.path + "/Xcode.app/Contents/Frameworks/SiriSSUKitModel.framework/Resources"
        try FileSystem.write(Data("- hey Siri\n- Siri\n".utf8), to: resources + "/prefix/en.yaml")
        try FileSystem.write(Data("- ${+applicationName}\n".utf8), to: resources + "/standardAppShortcutNegatives/en.yaml")
        let options = ["--infoplist-path", app + "/Info.plist", "--temp-dir-path", tmp.path + "/ssu", "--bundle-id", "org.nomac.experiment", "--product-path", app,
                       "--extracted-metadata-path", app + "/Metadata.appintents", "--source-file", app + "/Info.plist", "--archive-ssu-assets"]
        try AppIntentsTools.trainShortcuts(options, developerDirectory: tmp.path + "/Xcode.app/Contents/Developer")
        let yaml = try #require(FileManager.default.contents(atPath: tmp.path + "/ssu/root.ssu.yaml"))
        #expect(FileManager.default.contents(atPath: app + "/Metadata.appintents/root.ssu.yaml") == yaml)
        #expect(FileManager.default.contents(atPath: app + "/Metadata.appintents/nlu/\(MD5.hex("en:" + String(decoding: yaml, as: UTF8.self))).version") == Data([0]))
        #expect(FileManager.default.contents(atPath: app + "/Metadata.appintents/nlu/nlu.lzfse")?.starts(with: Array("bvx".utf8)) == true)
        var mismatched = options
        mismatched[5] = "org.nomac.other"
        #expect(throws: NomacError.self) { try AppIntentsTools.trainShortcuts(mismatched, developerDirectory: tmp.path + "/Xcode.app/Contents/Developer") }
        #expect(throws: NomacError.self) { try AppIntentsTools.trainShortcuts(options, developerDirectory: nil) }

        // With `.lproj` folders, each is trained into its own `nlu.appintents` (`localized`).
        for (locale, strings) in [("de", ["AppShortcuts": ["Search ${applicationName}": "Suche in ${applicationName}"], "InfoPlist": ["CFBundleDisplayName": "Notizen"]]),
                                  ("ca", [:])] {
            try FileManager.default.createDirectory(atPath: app + "/\(locale).lproj", withIntermediateDirectories: true)
            for (table, values) in strings {
                try FileSystem.write(try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0), to: app + "/\(locale).lproj/\(table).strings")
            }
        }
        try FileSystem.write(Data("- hallo Siri\n".utf8), to: resources + "/prefix/de.yaml")
        try FileSystem.write(Data("-  ${+applicationName} \n".utf8), to: resources + "/standardAppShortcutNegatives/de.yaml")
        try AppIntentsTools.trainShortcuts(options, developerDirectory: tmp.path + "/Xcode.app/Contents/Developer")
        let localized = String(decoding: try #require(FileManager.default.contents(atPath: app + "/Metadata.appintents/root.ssu.yaml")), as: UTF8.self)
        #expect(localized.contains("        - locale: ca\n          utterances:\n          - Search ${+applicationName}\n        - locale: de\n          utterances:\n          - '{${+prefix} }Suche in ${+applicationName}'\n"))
        #expect(localized.contains("        - locale: ca\n          utterances: []\n"))
        #expect(localized.contains("  - locale: de\n    synomyms:\n    - Notizen\n"))
        #expect(localized.hasSuffix("- name: +standardAppShortcutNegatives\n  type: ssu/expansion\n  definitions:\n  - locale: de\n    synomyms:\n      $ref: ssu://Resources/standardAppShortcutNegatives/de.yaml\n"))
        for locale in ["ca", "de"] {
            #expect(FileManager.default.contents(atPath: app + "/\(locale).lproj/nlu.appintents/\(MD5.hex(locale + ":" + localized)).version") == Data([0]))
        }
    }

    /// Siri's phrase lists by locale (`localized`), and their entries as YAML reads them.
    @Test func readsThePhraseListsOfEachLocale() throws {
        let available: Set<String> = ["en", "pt", "zh_CN", "de"]
        #expect(try AppShortcutsTraining.lists(for: "de", available: available) == "de")
        #expect(try AppShortcutsTraining.lists(for: "pt-BR", available: available) == "pt")
        #expect(try AppShortcutsTraining.lists(for: "en-GB", available: available) == nil)
        #expect(try AppShortcutsTraining.lists(for: "pl", available: available) == nil)
        #expect(throws: NomacError.self) { try AppShortcutsTraining.lists(for: "zh-CN", available: available) }
        #expect(try AppShortcutsTraining.phraseList("- hey Siri\n-  close ${+applicationName} \n- \"h\\xE9 Siri\"\n- \"\\u041F Siri\"\n", path: "x")
            == ["hey Siri", "close ${+applicationName}", "hé Siri", "П Siri"])
        #expect(throws: NomacError.self) { try AppShortcutsTraining.phraseList("- \"a\\nb\"\n", path: "x") }
    }

    /// A locale's `Localizable` table translates case titles and entity names (`localized`,
    /// icecubes); a scalar ending in a blank is single-quoted (icecubes' `'Anasayfa '`).
    @Test func translatesSynonymsAndQuotesTrailingBlanks() throws {
        var locale = AppShortcutsTraining.Locale(name: "de", applicationName: "Notizen", lists: "de")
        locale.strings = ["Happy": "Froh", "Memo": "Notiz"]
        let training = try training([locale])
        #expect(training.parameterTypes.map { training.synonyms($0, in: locale) } == [["Froh", "Sad", "Calm"], ["Notiz"]])
        #expect(try AppShortcutsTraining.scalar("Anasayfa ") == "'Anasayfa '")
        #expect(try AppShortcutsTraining.scalar("Send image(s) to Mastodon") == "Send image(s) to Mastodon")
    }

    /// YAML scalars as Xcode writes them, and synonyms read as templates (`quoting`).
    @Test func quotesScalarsAndExpandsSynonyms() throws {
        for (value, written) in [("Note: daily", "'Note: daily'"), ("Tag #1", "'Tag #1'"), ("- dash", "'- dash'"), ("123", "'123'"), ("true", "'true'"),
                                 ("@home", "'@home'"), ("100%", "100%"), ("[list]", "'[list]'"), ("Say \"hi\"", "Say \"hi\""), ("Café", "Café"),
                                 ("null", "'null'"), ("What's new?", "What's new?"), ("Log: today's #1 entry", "'Log: today''s #1 entry'"),
                                 ("{${+prefix} }What's new", "'{${+prefix} }What''s new'")] {
            #expect(try AppShortcutsTraining.scalar(value) == written, "\(value)")
        }
        #expect(try AppShortcutsTraining.expandSynonym("{set}") == ["", "set"])
        #expect(try AppShortcutsTraining.expandSynonym("back\\slash") == [])
        #expect(try AppShortcutsTraining.expandSynonym("plain") == ["plain"])
    }

    /// nomac verify: root.ssu.yaml's locales come in set order (`localized`).
    @Test func judgesLocalesInAnotherOrderEquivalent() {
        let a = "variables:\n- name: +applicationName\n  definitions:\n  - locale: de\n    synomyms:\n    - A\n  - locale: ca\n    synomyms:\n    - B\n"
        let b = "variables:\n- name: +applicationName\n  definitions:\n  - locale: ca\n    synomyms:\n    - B\n  - locale: de\n    synomyms:\n    - A\n"
        #expect(AppIntentsMetadata.sameButForSetOrder("root.ssu.yaml", a, b))
        #expect(!AppIntentsMetadata.sameButForSetOrder("root.ssu.yaml", a, b.replacingOccurrences(of: "- B", with: "- C")))
    }

    @Test func refusesWhatNoExperimentShowed() throws {
        var data = Self.actionsData
        data["autoShortcuts"] = [["actionIdentifier": "Search", "phraseTemplates": [Self.string("Search {quoted} ${applicationName}")]]]
        #expect(throws: NomacError.self) { try AppShortcutsTraining(actionsData: data, bundleIdentifier: "a", locales: [Self.english]).ssuRoot }
        data["autoShortcuts"] = [["actionIdentifier": "Search", "phraseTemplates": [["alternatives": ["Look"], "key": "Search ${applicationName}"]]]]
        #expect(throws: NomacError.self) { try AppShortcutsTraining(actionsData: data, bundleIdentifier: "a", locales: [Self.english]) }
        #expect(throws: NomacError.self) { try AppShortcutsTraining.scalar("two\nlines") }
        #expect(throws: NomacError.self) { try AppShortcutsTraining.expandSynonym("{a|b}") }
        #expect(throws: NomacError.self) { try AppShortcutsTraining.expandSynonym("{}") }
    }

    /// A schema-less reader of the tables, vectors and strings the training writes.
    struct Reader {
        let bytes: [UInt8]

        func u16(_ offset: Int) -> Int { Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 }
        func u32(_ offset: Int) -> Int { u16(offset) | u16(offset + 2) << 16 }
        var root: Int { u32(0) }

        func vtable(_ table: Int) -> Int { table - Int(Int32(truncatingIfNeeded: u32(table))) }
        func layout(_ table: Int) -> ([Int], Int) {
            let vtable = vtable(table)
            return ((0..<(u16(vtable) - 4) / 2).map { u16(vtable + 4 + 2 * $0) }, u16(vtable + 2))
        }
        /// The object the offset in field `index` of `table` refers to.
        func table(_ table: Int, _ index: Int) -> Int {
            let field = table + u16(vtable(table) + 4 + 2 * index)
            return field + u32(field)
        }
        func vector(_ vector: Int) -> [Int] { (0..<u32(vector)).map { vector + 4 + 4 * $0 + u32(vector + 4 + 4 * $0) } }
        func vector(_ table: Int, field: Int) -> [Int] { vector(self.table(table, field)) }
        func string(_ string: Int) -> String { String(decoding: bytes[(string + 4)..<(string + 4 + u32(string))], as: UTF8.self) }
    }
}
