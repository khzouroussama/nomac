import Foundation
import NomacCore
import NomacLZFSE

/// What Xcode 27.0's `appintentsnltrainingprocessor` writes for a target with App Shortcuts:
/// `root.ssu.yaml`, which it generates from `extract.actionsdata`, the Info.plist and the app's
/// localizations into its temporary directory and copies into `Metadata.appintents`, and for each
/// locale the phrases expanded into utterances: `Metadata.appintents/nlu/` for an app without
/// `.lproj` folders (English), `<locale>.lproj/nlu.appintents/` for every `.lproj` folder of one
/// with them (docs/formats/app-intents.md; `basic`, `training` and `localized` of
/// `.github/scripts/app_intents_experiments.py`). Every form no experiment has shown is refused.
struct AppShortcutsTraining {
    struct Shortcut {
        let identifier: String
        let title: String
        /// The phrases as `extract.actionsdata` writes them (`Open ${note} in ${applicationName}`).
        let templates: [String]
        /// The type of each enum and entity parameter of the intent, by the parameter's name.
        let types: [String: String]
    }

    /// An enum or entity parameter type: its synonyms are its case titles or its displayed type
    /// name, keys of the app's `Localizable` table.
    struct ParameterType {
        let name: String
        let keys: [String]
    }

    /// A locale the training writes.
    struct Locale {
        let name: String
        /// `${+applicationName}`: the locale's `InfoPlist.strings` display name, else the bundle's
        /// (`localized`).
        let applicationName: String
        /// The app's `AppShortcuts` table in the locale, which translates phrases.
        var shortcutPhrases: [String: String] = [:]
        /// The app's `Localizable` table in the locale, which translates enum case titles and entity
        /// names.
        var strings: [String: String] = [:]
        /// The locale's file of `SiriSSUKitModel.framework`'s phrase lists, nil when it has none.
        let lists: String?
    }

    let bundleIdentifier: String
    let shortcuts: [Shortcut]
    /// Xcode writes the parameter types in set order, which changes from run to run; nomac in the
    /// intents' parameter order.
    let parameterTypes: [ParameterType]
    /// Xcode writes the locales in set order too; nomac in the order given.
    let locales: [Locale]

    init(actionsData: [String: Any], bundleIdentifier: String, locales: [Locale]) throws {
        let autoShortcuts = actionsData["autoShortcuts"] as? [[String: Any]] ?? []
        let actions = actionsData["actions"] as? [String: [String: Any]] ?? [:]
        let enums = actionsData["enums"] as? [[String: Any]] ?? []
        let entities = actionsData["entities"] as? [String: [String: Any]] ?? [:]
        var parameterTypes: [ParameterType] = []
        self.shortcuts = try autoShortcuts.map { shortcut in
            guard let identifier = shortcut["actionIdentifier"] as? String, let action = actions[identifier] else {
                throw NomacError("an App Shortcut whose intent extract.actionsdata does not list")
            }
            var types: [String: String] = [:]
            for parameter in action["parameters"] as? [[String: Any]] ?? [] {
                guard let name = parameter["name"] as? String, let valueType = parameter["valueType"] as? [String: Any] else { continue }
                let type: ParameterType
                if let enumeration = (valueType["linkEnumeration"] as? [String: Any])?["wrapper"] as? [String: Any], let id = enumeration["identifier"] as? String {
                    guard let cases = enums.first(where: { $0["identifier"] as? String == id })?["cases"] as? [[String: Any]] else {
                        throw NomacError("the App Shortcut parameter '\(name)' of an enum extract.actionsdata does not list")
                    }
                    type = ParameterType(name: id, keys: try cases.map { try Self.text(($0["displayRepresentation"] as? [String: Any])?["title"]) })
                } else if let entity = (valueType["entity"] as? [String: Any])?["wrapper"] as? [String: Any], let id = entity["typeName"] as? String {
                    type = ParameterType(name: id, keys: [try Self.text(entities[id]?["displayTypeName"])])
                } else if let member = ((valueType["array"] as? [String: Any])?["wrapper"] as? [String: Any])?["memberValueType"] as? [String: Any],
                          member["linkEnumeration"] != nil || member["entity"] != nil {
                    throw NomacError("the App Shortcut parameter '\(name)', an array of enum cases or entities, whose training no experiment has shown (B-159)")
                } else {
                    continue
                }
                types[name] = type.name
                if !parameterTypes.contains(where: { $0.name == type.name }) { parameterTypes.append(type) }
            }
            let templates = try (shortcut["phraseTemplates"] as? [[String: Any]] ?? []).map(Self.text)
            return Shortcut(identifier: identifier, title: try Self.text(action["title"]), templates: templates, types: types)
        }
        self.parameterTypes = parameterTypes
        self.bundleIdentifier = bundleIdentifier
        self.locales = locales
    }

    /// A localized string of `extract.actionsdata`, refused with alternatives no experiment has
    /// shown.
    private static func text(_ value: Any?) throws -> String {
        guard let value = value as? [String: Any], let key = value["key"] as? String, (value["alternatives"] as? [Any])?.isEmpty ?? true else {
            throw NomacError("an App Shortcuts string that is no plain localization key (B-159)")
        }
        return key
    }

    /// A shortcut's phrases in `locale`, as `root.ssu.yaml` writes them: the ones its `AppShortcuts`
    /// table translates, else all of them untranslated (`localized`: `de` translates one of
    /// `Search`'s two phrases and trains only that one), with the application name as
    /// `${+applicationName}` and each parameter as its type (`${Mood}`).
    func phrases(_ shortcut: Shortcut, in locale: Locale) throws -> [String] {
        let translated = shortcut.templates.compactMap { locale.shortcutPhrases[$0] }
        return try (translated.isEmpty ? shortcut.templates : translated).map { try Self.phrase($0, types: shortcut.types) }
    }

    private static func phrase(_ template: String, types: [String: String]) throws -> String {
        guard !template.replacingOccurrences(of: "${", with: "").contains("{") else {
            throw NomacError("the App Shortcut phrase '\(template)', whose training no experiment has shown (B-159)")
        }
        var result = ""
        var rest = Substring(template)
        while let start = rest.range(of: "${") {
            result += rest[..<start.lowerBound]
            guard let end = rest[start.upperBound...].firstIndex(of: "}") else { throw NomacError("the App Shortcut phrase '\(template)' has an unterminated variable") }
            let name = String(rest[start.upperBound..<end])
            if name == "applicationName" {
                result += "${+applicationName}"
            } else if let type = types[name] {
                result += "${\(type)}"
            } else {
                throw NomacError("the App Shortcut phrase '\(template)' names '\(name)', no enum or entity parameter of its intent")
            }
            rest = rest[rest.index(after: end)...]
        }
        return result + rest
    }

    /// A parameter type's synonyms in `locale`: an enum's case titles or an entity's displayed type
    /// name as the locale's `Localizable` table translates them (`localized`: `de`'s `Froh`;
    /// icecubes: `zh-Hans`'s `App 账户` for `AppAccount`).
    func synonyms(_ type: ParameterType, in locale: Locale) -> [String] {
        type.keys.map { locale.strings[$0] ?? $0 }
    }

    /// The type of the enum or entity parameter `phrases` use, with its first synonym in `locale`.
    /// The types of the enum and entity parameters `phrases` use, in the order they first appear,
    /// each with its first synonym in `locale` (`phrases`: Xcode writes them in set order, which
    /// changes from build to build).
    private func parameters(_ phrases: [String], of shortcut: Shortcut, in locale: Locale) -> [(type: String, value: String)] {
        var used: [String] = []
        for phrase in phrases {
            var rest = Substring(phrase)
            while let start = rest.range(of: "${") {
                guard let end = rest[start.upperBound...].firstIndex(of: "}") else { break }
                let name = String(rest[start.upperBound..<end])
                if shortcut.types.values.contains(name), !used.contains(name) { used.append(name) }
                rest = rest[rest.index(after: end)...]
            }
        }
        return used.compactMap { name in parameterTypes.first { $0.name == name }.map { (name, synonyms($0, in: locale).first ?? "") } }
    }

    // MARK: root.ssu.yaml

    /// `root.ssu.yaml`: per intent and per locale its phrases, behind `{${+prefix} }` in a locale
    /// with phrase lists and written plain in one without; the negative intent; and the
    /// variables' definitions per locale, the phrase lists' only for locales that have them.
    var ssuRoot: String {
        get throws {
            guard locales.contains(where: { $0.lists != nil }) else {
                throw NomacError("an App Shortcuts training of no locale with Siri's phrase lists, whose root.ssu.yaml no experiment has shown (B-159)")
            }
            var text = "apiVersion: ssu/v1\nnlu:\n  shortcuts:\n    bundleIdentifier: \(try Self.scalar(bundleIdentifier))\n    intents:\n"
            for (index, shortcut) in shortcuts.enumerated() {
                text += "    - metadata:\n        name: \(shortcut.identifier)_\(index)\n        title: \(try Self.scalar(shortcut.title))\n"
                text += "      corpuses:\n        training:\n"
                for locale in locales {
                    text += "        - locale: \(try Self.scalar(locale.name))\n          utterances:\n"
                    text += try phrases(shortcut, in: locale).map { "          - \(try Self.scalar(locale.lists == nil ? $0 : "{${+prefix} }" + $0))\n" }.joined()
                }
            }
            text += "    - metadata:\n        name: +negative\n      corpuses:\n        training:\n"
            for locale in locales {
                text += "        - locale: \(locale.name)\n          utterances:"
                text += locale.lists == nil ? " []\n" : "\n          - '{${+prefix} }${+standardAppShortcutNegatives}'\n"
            }
            text += "variables:\n"
            let variables = [("+applicationName", "expansion", { (locale: Locale) in [locale.applicationName] })]
                + parameterTypes.map { type in (type.name, "parameter", { (locale: Locale) in self.synonyms(type, in: locale) }) }
            for (name, kind, synonyms) in variables {
                text += "- name: \(try Self.scalar(name))\n  type: ssu/\(kind)\n  definitions:\n"
                for locale in locales {
                    text += "  - locale: \(locale.name)\n    synomyms:\n" + (try synonyms(locale).map { "    - \(try Self.scalar($0))\n" }.joined())
                }
            }
            for list in Self.phraseLists {
                text += "- name: +\(list)\n  type: ssu/expansion\n  definitions:\n"
                for locale in locales {
                    guard let file = locale.lists else { continue }
                    text += "  - locale: \(locale.name)\n    synomyms:\n      $ref: ssu://Resources/\(list)/\(file).yaml\n"
                }
            }
            return text
        }
    }

    /// The phrase lists of Xcode's `SiriSSUKitModel.framework` the utterances expand: the ways to
    /// address Siri, and the requests that must not open the app.
    static let phraseLists = ["prefix", "standardAppShortcutNegatives"]

    /// A YAML scalar as Xcode writes names, titles, synonyms and utterances, by a YAML emitter's
    /// rules (`quoting`, icecubes' `'Anasayfa '`): plain, unless it starts with an indicator
    /// (`- `, `? `, `: `, or one of `#,[]{}&*!|>'"%@` and the backquote), contains `: ` or ` #`,
    /// ends with `:`, starts or ends with a blank, or would read as another YAML type (`123`,
    /// `true`, `null`); then single-quoted, a `'` doubled. A scalar with a line break or another
    /// control character is refused (no experiment has shown its quoting).
    static func scalar(_ value: String) throws -> String {
        guard !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw NomacError("the App Shortcuts text '\(value)', whose quoting nomac has not observed (B-159)")
        }
        return needsQuotes(value) ? "'" + value.replacingOccurrences(of: "'", with: "''") + "'" : value
    }

    private static func needsQuotes(_ value: String) -> Bool {
        guard let first = value.first, let last = value.last else { return true }
        if " \t".contains(first) || " \t".contains(last) || last == ":" { return true }
        if "#,[]{}&*!|>'\"%@`".contains(first) { return true }
        if "-?:".contains(first), value.count == 1 || value.dropFirst().first == " " { return true }
        if value.contains(": ") || value.contains(" #") { return true }
        return implicitTypes.contains { value.wholeMatch(of: $0) != nil }
    }

    /// The plain scalars YAML 1.1 reads as other types than strings: null, Booleans, integers,
    /// floats, timestamps, merge and value keys.
    nonisolated(unsafe) private static let implicitTypes: [Regex<AnyRegexOutput>] = [
        #"~|null|Null|NULL"#,
        #"yes|Yes|YES|no|No|NO|true|True|TRUE|false|False|FALSE|on|On|ON|off|Off|OFF"#,
        #"[-+]?0b[0-1_]+|[-+]?0[0-7_]+|[-+]?(0|[1-9][0-9_]*)|[-+]?0x[0-9a-fA-F_]+|[-+]?[1-9][0-9_]*(:[0-5]?[0-9])+"#,
        #"[-+]?([0-9][0-9_]*)?\.[0-9_]*([eE][-+][0-9]+)?|[-+]?[0-9][0-9_]*(:[0-5]?[0-9])+\.[0-9_]*|[-+]?\.(inf|Inf|INF)|\.(nan|NaN|NAN)"#,
        #"[0-9][0-9][0-9][0-9]-[0-9][0-9]?-[0-9][0-9]?([Tt]|[ \t]+)[0-9][0-9]?:[0-9][0-9]:[0-9][0-9](\.[0-9]*)?(([ \t]*)Z|[-+][0-9][0-9]?(:[0-9][0-9])?)?|[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]"#,
        #"<<|="#,
    ].map { try! Regex($0) }

    /// The file of the phrase lists Xcode trains `locale` with, among `available` (the lists'
    /// locales): the one of its name, or `pt` for `pt-BR`; none for the other observed locales
    /// (`localized`: `en-GB`, `pt-PT`, `zh-Hans`, `zh-HK`, `ca`, `Base`, …). An unobserved locale
    /// of a language that has lists is refused.
    static func lists(for locale: String, available: Set<String>) throws -> String? {
        if available.contains(locale) { return locale }
        if locale == "pt-BR", available.contains("pt") { return "pt" }
        if observedWithoutLists.contains(locale) { return nil }
        let language = String(locale.prefix { $0 != "-" && $0 != "_" })
        guard !available.contains(where: { $0.prefix { $0 != "_" } == language }) else {
            throw NomacError("the locale \(locale), whose App Shortcuts phrase lists no experiment has shown (B-159)")
        }
        return nil
    }

    static let observedWithoutLists: Set<String> = ["en-GB", "en-AU", "de-CH", "es-MX", "fr-CA", "pt-PT", "zh-Hans", "zh-Hant", "zh-HK", "ca", "pl", "uk", "Base"]

    // MARK: nlu

    /// The English utterances of each template: the cartesian product of its parts, the leftmost
    /// varying slowest, an optional part (`{${+prefix} }`) first left out, a variable taking each
    /// of its synonyms in order (`training`: prefix, then phrase, then parameter value).
    static func expand(_ template: String, _ variables: [String: [String]]) throws -> [String] {
        let characters = Array(template)
        var index = 0
        func sequence(until terminator: Character?) throws -> [String] {
            var results = [""]
            var literal = ""
            func append(_ alternatives: [String]) {
                results = results.flatMap { result in alternatives.map { result + $0 } }
            }
            while index < characters.count {
                let character = characters[index]
                if character == terminator {
                    index += 1
                    append([literal])
                    return results
                }
                if character == "$", index + 1 < characters.count, characters[index + 1] == "{" {
                    append([literal])
                    literal = ""
                    guard let end = characters[(index + 2)...].firstIndex(of: "}") else { throw NomacError("an unterminated variable in '\(template)'") }
                    let name = String(characters[(index + 2)..<end])
                    guard let values = variables[name] else { throw NomacError("the variable '\(name)' of '\(template)', which the training does not define") }
                    append(values)
                    index = end + 1
                } else if character == "{" {
                    append([literal])
                    literal = ""
                    index += 1
                    append([""] + (try sequence(until: "}")))
                } else {
                    literal.append(character)
                    index += 1
                }
            }
            guard terminator == nil else { throw NomacError("an unterminated optional part in '\(template)'") }
            append([literal])
            return results
        }
        return try sequence(until: nil)
    }

    /// A synonym's utterances: the training reads it as a template (`quoting`): `{…}` is an
    /// optional part (`{set}`: "" and "set"); a backslash escapes `$`, `|`, `(`, `)`, `{` or `}`,
    /// and a synonym where it escapes another character is left out ("\\ should be followed by
    /// one of the supported escaped chars", `back\\slash`). Unbalanced or empty braces make
    /// Xcode's training fail (no `nlu/`, the build going on); those, alternatives (`|`, `( )`) and
    /// escaped characters are refused, no experiment having shown their utterances.
    static func expandSynonym(_ synonym: String) throws -> [String] {
        let characters = Array(synonym)
        for (index, character) in characters.enumerated() where character == "\\" {
            guard index + 1 < characters.count, "$|(){}".contains(characters[index + 1]) else { return [] }
        }
        let refusal = NomacError("the App Shortcuts synonym '\(synonym)', whose training no experiment has shown (B-159)")
        guard !synonym.contains("\\"), !synonym.contains("|"), !synonym.contains("("), !synonym.contains(")"), !synonym.contains("$") else { throw refusal }
        var depth = 0
        var previous: Character?
        for character in characters {
            if character == "{" {
                guard depth == 0 else { throw refusal }
                depth = 1
            } else if character == "}" {
                guard depth == 1, previous != "{" else { throw refusal }
                depth = 0
            }
            previous = character
        }
        guard depth == 0 else { throw refusal }
        return try expand(synonym, [:])
    }

    /// The entries of a phrase list file of `SiriSSUKitModel.framework` (`- hey Siri`): plain, without
    /// surrounding blanks, or
    /// double-quoted with `\\uXXXX` and `\\xXX` escapes (`- "h\\xE9 Siri"`, the only forms Xcode
    /// 27.0's lists use); others are refused.
    static func phraseList(_ text: String, path: String) throws -> [String] {
        try text.split(whereSeparator: \.isNewline).map { line in
            guard line.hasPrefix("- ") else { throw NomacError("a phrase list entry nomac does not read: \(line)", path: path) }
            let entry = line.dropFirst(2)
            guard entry.hasPrefix("\"") else {
                guard !entry.hasPrefix("'") else { throw NomacError("a phrase list entry nomac does not read: \(line)", path: path) }
                // A plain scalar spans its non-blank characters (`es`, `da`, … have entries ending
                // in a space, `it` and `pt` entries starting with one).
                return entry.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
            }
            guard entry.count >= 2, entry.hasSuffix("\"") else { throw NomacError("a phrase list entry nomac does not read: \(line)", path: path) }
            var scalars = String.UnicodeScalarView()
            var rest = Substring(entry.dropFirst().dropLast())
            while let first = rest.first {
                rest = rest.dropFirst()
                guard first == "\\" else {
                    guard first != "\"" else { throw NomacError("a phrase list entry nomac does not read: \(line)", path: path) }
                    scalars += first.unicodeScalars
                    continue
                }
                let digits = rest.first == "u" ? 4 : rest.first == "x" ? 2 : 0
                guard digits > 0, let value = UInt32(rest.dropFirst().prefix(digits), radix: 16), rest.count > digits, let scalar = Unicode.Scalar(value) else {
                    throw NomacError("a phrase list entry nomac does not read: \(line)", path: path)
                }
                scalars.append(scalar)
                rest = rest.dropFirst(digits + 1)
            }
            return String(scalars)
        }
    }

    /// `nlu.lzfse` of `locale` before its compression: a FlatBuffers buffer whose root holds the
    /// constant 1, a header (`hash`, the training's time in seconds since 1970, an empty vector and
    /// "1.0"), the locale and one group of one bundle: its identifier, its intents (each shortcut as
    /// `<Intent>_<index>` with the parameter its phrases use and its utterances) and the negative
    /// utterances. Objects are written in that order (`basic`, `training`). `lists` are the
    /// locale's phrase lists (prefixes, negatives); without them the utterances have no prefix and
    /// there are no negatives (`localized`: `ca`).
    func nlu(_ locale: Locale, lists: (prefixes: [String], negatives: [String])?, hash: String, time: UInt64) throws -> [UInt8] {
        var variables = ["+applicationName": [locale.applicationName]]
        for type in parameterTypes { variables[type.name] = try synonyms(type, in: locale).flatMap(Self.expandSynonym) }
        variables["+prefix"] = lists?.prefixes ?? []
        variables["+standardAppShortcutNegatives"] = try (lists?.negatives ?? []).flatMap { try Self.expand($0, variables) }
        let prefix = lists == nil ? "" : "{${+prefix} }"
        var builder = FlatBufferBuilder()
        func utterance(_ text: String) -> FlatBufferBuilder.Offset {
            let string = builder.string(text)
            builder.startTable()
            builder.add(0, offset: string)
            let content = builder.endTable()
            builder.startTable()
            builder.add(0, UInt8(1))
            builder.add(1, offset: content)
            return builder.endTable()
        }
        let hashString = builder.string(hash)
        let empty = builder.vector([])
        let version = builder.string("1.0")
        builder.startTable()
        builder.add(0, offset: hashString)
        builder.add(1, time)
        builder.add(2, offset: empty)
        builder.add(3, offset: version)
        let header = builder.endTable()
        let localeName = builder.string(locale.name)
        let identifier = builder.string(bundleIdentifier)
        var intents: [FlatBufferBuilder.Offset] = []
        for (index, shortcut) in shortcuts.enumerated() {
            let name = builder.string("\(shortcut.identifier)_\(index)")
            var parameters: [FlatBufferBuilder.Offset] = []
            let phrases = try phrases(shortcut, in: locale)
            for parameter in self.parameters(phrases, of: shortcut, in: locale) {
                let type = builder.string(parameter.type)
                let value = builder.string(parameter.value)
                builder.startTable()
                builder.add(0, offset: type)
                builder.add(1, offset: value)
                parameters.append(builder.endTable())
            }
            let parameterVector = builder.vector(parameters)
            let utterances = try phrases.flatMap { try Self.expand(prefix + $0, variables) }.map(utterance)
            let utteranceVector = builder.vector(utterances)
            builder.startTable()
            builder.add(0, offset: name)
            builder.add(1, offset: parameterVector)
            builder.add(2, offset: utteranceVector)
            intents.append(builder.endTable())
        }
        let intentVector = builder.vector(intents)
        let negativeVector = builder.vector(lists == nil ? [] : try Self.expand(prefix + "${+standardAppShortcutNegatives}", variables).map(utterance))
        builder.startTable()
        builder.add(0, offset: identifier)
        builder.add(1, offset: intentVector)
        builder.add(2, offset: negativeVector)
        let bundles = builder.vector([builder.endTable()])
        builder.startTable()
        builder.add(1, offset: bundles)
        let groups = builder.vector([builder.endTable()])
        builder.startTable()
        builder.add(0, UInt16(1))
        builder.add(1, offset: header)
        builder.add(2, offset: localeName)
        builder.add(3, offset: groups)
        return builder.finish(builder.endTable())
    }

    /// Where a training buffer's header keeps the digest's characters and the training's time
    /// (the root's second field, a table whose first field is the digest string and second the
    /// time), nil for a buffer of another shape.
    static func header(_ buffer: [UInt8]) -> (digest: Range<Int>, time: Range<Int>)? {
        func integer(_ offset: Int, _ size: Int) -> Int? {
            guard offset >= 0, offset + size <= buffer.count else { return nil }
            return (0..<size).reduce(0) { $0 | Int(buffer[offset + $1]) << (8 * $1) }
        }
        func u32(_ offset: Int) -> Int? { integer(offset, 4) }
        func field(_ table: Int, _ index: Int) -> Int? {
            guard let soffset = u32(table) else { return nil }
            let vtable = table - Int(Int32(truncatingIfNeeded: soffset))
            guard let size = integer(vtable, 2), 6 + 2 * index <= size, let entry = integer(vtable + 4 + 2 * index, 2), entry != 0 else { return nil }
            return table + entry
        }
        guard let root = u32(0), let headerField = field(root, 1), let headerOffset = u32(headerField),
              let digestField = field(headerField + headerOffset, 0), let digestOffset = u32(digestField), let length = u32(digestField + digestOffset),
              let time = field(headerField + headerOffset, 1), time + 8 <= buffer.count, digestField + digestOffset + 4 + length <= buffer.count else { return nil }
        let digest = digestField + digestOffset + 4
        return (digest..<(digest + length), time..<(time + 8))
    }

    /// A training buffer's contents as lines: the locale, the bundle identifier, each intent's
    /// name, parameters (sorted: Xcode writes them in set order, `phrases`) and utterances, and the
    /// negatives; nil for a buffer of another shape.
    static func contents(_ buffer: [UInt8]) -> [String]? {
        func u32(_ offset: Int) -> Int? {
            guard offset >= 0, offset + 4 <= buffer.count else { return nil }
            return (0..<4).reduce(0) { $0 | Int(buffer[offset + $1]) << (8 * $1) }
        }
        func field(_ table: Int, _ index: Int) -> Int? {
            guard let soffset = u32(table) else { return nil }
            let vtable = table - Int(Int32(truncatingIfNeeded: soffset))
            guard let size = u32(vtable).map({ $0 & 0xFFFF }), 6 + 2 * index <= size, let entry = u32(vtable + 4 + 2 * index).map({ $0 & 0xFFFF }), entry != 0,
                  let offset = u32(table + entry) else { return nil }
            return table + entry + offset
        }
        func vector(_ offset: Int?) -> [Int]? {
            guard let offset, let count = u32(offset) else { return nil }
            return (0..<count).map { offset + 4 + 4 * $0 + (u32(offset + 4 + 4 * $0) ?? 0) }
        }
        func string(_ offset: Int?) -> String? {
            guard let offset, let length = u32(offset), offset + 4 + length <= buffer.count else { return nil }
            return String(decoding: buffer[(offset + 4)..<(offset + 4 + length)], as: UTF8.self)
        }
        func utterances(_ offsets: [Int]?) -> [String]? {
            offsets.flatMap { offsets in
                let texts = offsets.map { string(field($0, 1).flatMap { field($0, 0) }) }
                return texts.contains(nil) ? nil : texts.map { "utterance " + $0! }
            }
        }
        guard let root = u32(0), let locale = string(field(root, 2)), let group = vector(field(root, 3))?.first,
              let bundle = vector(field(group, 1))?.first, let identifier = string(field(bundle, 0)),
              let intents = vector(field(bundle, 1)), let negatives = utterances(vector(field(bundle, 2))) else { return nil }
        var lines = ["locale " + locale, "bundle " + identifier]
        for intent in intents {
            guard let name = string(field(intent, 0)), let parameters = vector(field(intent, 1)), let texts = utterances(vector(field(intent, 2))) else { return nil }
            let pairs = parameters.map { "parameter " + (string(field($0, 0)) ?? "") + "=" + (string(field($0, 1)) ?? "") }
            lines += ["intent " + name] + pairs.sorted() + texts
        }
        return lines + negatives.map { "negative " + $0 }
    }

    /// How nomac verify judges two `nlu.lzfse`: equivalent when they differ only in the training's
    /// time, and in the order of an intent's parameters; different with the reason when the
    /// header's digest differs too (its input is not known, B-159) or the utterances do.
    static func compareNLU(_ reference: [UInt8], _ other: [UInt8]) -> BuildProducts.Outcome {
        guard let x = try? LZFSE.decode(reference), let y = try? LZFSE.decode(other), let a = header(x), let b = header(y) else {
            return .different(["not an App Shortcuts training buffer"])
        }
        func masked(_ buffer: [UInt8], _ ranges: [Range<Int>]) -> [UInt8] {
            var buffer = buffer
            for range in ranges { buffer.replaceSubrange(range, with: repeatElement(0, count: range.count)) }
            return buffer
        }
        let time = BuildProducts.documented["appintents.training-time"]!
        if masked(x, [a.time]) == masked(y, [b.time]) { return .equivalent([time]) }
        guard let left = contents(x), left == contents(y) else { return .different(["the training's utterances differ"]) }
        guard x[a.digest] == y[b.digest] else {
            return .different(["the header's digest differs (\(String(decoding: x[a.digest], as: UTF8.self)) in Xcode's), whose input is not known (B-159)"])
        }
        return .equivalent([time, BuildProducts.documented["appintents.set-order"]!])
    }

    /// Writes `root.ssu.yaml` into `temporary` and `metadata`, and each locale's training: into
    /// `metadata`'s `nlu/` for an app without localizations, else into the product's
    /// `<locale>.lproj/nlu.appintents/`, with the phrase lists of `phraseLists`
    /// (`SiriSSUKitModel.framework/Resources`).
    ///
    /// Xcode names the `.version` file and fills the header's hash with a digest of
    /// `root.ssu.yaml` and the locale: it changes with the YAML and only with it (twelve runs), and
    /// from locale to locale, but its input is not known (B-159). nomac uses the MD5 of the
    /// locale's name, a colon and the YAML.
    func write(product: String?, metadata: String, temporary: String, phraseLists: String, time: Date) throws {
        let yaml = try ssuRoot
        for directory in [temporary, metadata] {
            try FileSystem.createDirectory(directory)
            try FileSystem.write(Data(yaml.utf8), to: directory + "/root.ssu.yaml")
        }
        for locale in locales {
            let lists = try locale.lists.map { file in
                let entries = try Self.phraseLists.map { list in
                    let path = phraseLists + "/" + list + "/" + file + ".yaml"
                    guard let data = FileManager.default.contents(atPath: path) else { throw NomacError("Xcode's App Shortcuts phrase list is missing (nomac sdk keeps it)", path: path) }
                    return try Self.phraseList(String(decoding: data, as: UTF8.self), path: path)
                }
                return (prefixes: entries[0], negatives: entries[1])
            }
            let hash = MD5.hex(locale.name + ":" + yaml)
            let buffer = try nlu(locale, lists: lists, hash: hash, time: UInt64(time.timeIntervalSince1970))
            let directory = product.map { $0 + "/" + locale.name + ".lproj/nlu.appintents" } ?? metadata + "/nlu"
            try FileSystem.createDirectory(directory)
            try FileSystem.write(Data(LZFSE.encode(buffer)), to: directory + "/nlu.lzfse")
            try FileSystem.write(Data([0]), to: directory + "/\(hash).version")
        }
    }
}
