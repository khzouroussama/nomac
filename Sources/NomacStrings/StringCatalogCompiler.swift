import Foundation
import NomacCore
import NomacPlist

/// Compiles a string catalog into per-language `.strings` and `.stringsdict` tables, as
/// `xcstringstool compile` does in Xcode 27.0 (docs/formats/strings.md "String catalogs";
/// strings-experiments `xcstrings` and the corpus catalogs).
public struct StringCatalogCompiler: Sendable {
    /// `--format`: where plain strings go.
    public enum Format: String, Sendable, CaseIterable {
        case stringsAndStringsdict
        case stringsdictOnly
    }

    /// A message `xcstringstool` prints as `<catalog path>: <severity>: <message> (<context>)`.
    public struct Diagnostic: Equatable, Sendable {
        public enum Severity: String, Sendable {
            case warning
            case error
        }

        public var severity: Severity
        public var message: String
        /// `<language>: <key>`, then `|==|<variation>.<case>` for each variation it is in.
        public var context: String

        public func rendered(path: String) -> String {
            "\(path): \(severity.rawValue): \(message) (\(context))"
        }
    }

    /// One compiled file: `<language>.lproj/<catalog name>.<fileExtension>`.
    public struct Output: Equatable, Sendable {
        public var language: String
        public var fileExtension: String
        public var table: [String: PropertyListValue]

        public func relativePath(catalogName: String) -> String {
            "\(LanguageIdentifier.folderName(language)).lproj/\(catalogName).\(fileExtension)"
        }

        /// `.strings` keys sort by UTF-16 code units, `.stringsdict` keys as Swift compares
        /// strings (strings-experiments `key-order`, `stringsdict-key-order`).
        public var keyOrder: XMLPropertyList.KeyOrder {
            fileExtension == "strings" ? .utf16CodeUnits : .swiftString
        }
    }

    public var catalog: StringCatalog
    /// `-l`: the languages to compile; every language of the catalog when nil.
    public var languages: [String]?
    public var format: Format

    public init(catalog: StringCatalog, languages: [String]? = nil, format: Format = .stringsAndStringsdict) {
        self.catalog = catalog
        self.languages = languages
        self.format = format
    }

    /// The files the catalog compiles to, in language order with `.strings` first, and the
    /// diagnostics. Xcode writes no file when there is an error.
    public func compile() throws -> (outputs: [Output], diagnostics: [Diagnostic]) {
        try refuseUnobserved()
        var diagnostics: [Diagnostic] = []
        var outputs: [Output] = []
        let withArguments = Set(catalog.strings.keys.filter { key in
            var analysis = ArgumentAnalysis(catalog: catalog, key: key)
            return catalog.strings[key]!.extractionState == "manual" && !(analysis.run() ?? []).isEmpty
        })
        for language in compiledLanguages() {
            var tables = Tables()
            for key in catalog.strings.keys.sorted() {
                guard let localization = localization(of: key, in: language, hasArguments: withArguments.contains(key)) else { continue }
                var emitter = Emitter(format: format, language: language, source: sourceForms(of: key))
                emitter.emit(key: key, localization: localization, into: &tables)
                diagnostics += emitter.diagnostics
            }
            if !tables.plain.isEmpty {
                outputs.append(Output(language: language, fileExtension: "strings", table: tables.plain))
            }
            if !tables.rules.isEmpty {
                outputs.append(Output(language: language, fileExtension: "stringsdict", table: tables.rules))
            }
        }
        return (outputs, diagnostics)
    }

    /// Every substitution observed (691 in the corpus, all in the experiments) has a
    /// `formatSpecifier` and plural variations; nomac refuses the others (BACKLOG B-264).
    private func refuseUnobserved() throws {
        func check(_ localization: StringCatalog.Localization, _ key: String) throws {
            for (name, substitution) in localization.substitutions ?? [:] {
                guard substitution.formatSpecifier != nil else {
                    throw NomacError("nomac does not compile the substitution \(name) of \(key), which has no formatSpecifier, yet (BACKLOG B-264)")
                }
                guard let variations = substitution.variations, variations.plural != nil, variations.device == nil, variations.width == nil else {
                    throw NomacError("nomac does not compile the substitution \(name) of \(key), which does not vary by plural, yet (BACKLOG B-264)")
                }
            }
            for nested in [localization.variations?.plural, localization.variations?.device, localization.variations?.width] {
                for child in (nested ?? [:]).values {
                    try check(child, key)
                }
            }
        }
        for (key, entry) in catalog.strings {
            for localization in (entry.localizations ?? [:]).values {
                try check(localization, key)
            }
        }
    }

    private func compiledLanguages() -> [String] {
        var all = Set([catalog.sourceLanguage])
        for entry in catalog.strings.values {
            if let localized = entry.localizations?.keys {
                all.formUnion(localized)
            }
        }
        if let languages {
            all.formIntersection(languages)
        }
        return all.sorted()
    }

    /// What `key` compiles to in `language`. In the source language, a string extracted from
    /// code (any extraction state but `manual` and `migrated`) has its value in the code: it gets
    /// no entry unless it has a source unit that is not `new`. Manual and migrated strings get
    /// their key when they have no source unit (strings-experiments `source-matrix`). In the other
    /// languages, a manual string gets its key when its symbol would take arguments: the
    /// generated-symbols analysis of its localizations succeeds with at least one argument
    /// (`unlocalized-variations`, `unlocalized-specifiers`; owncloud's `%@ is not available for
    /// this item.`).
    private func localization(of key: String, in language: String, hasArguments: Bool) -> StringCatalog.Localization? {
        let entry = catalog.strings[key]!
        let isManual = entry.extractionState == "manual" || entry.extractionState == "migrated"
        if let localization = entry.localizations?[language] {
            if language == catalog.sourceLanguage, !isManual, localization.variations == nil,
               localization.stringUnit?.state == "new" {
                return nil
            }
            return localization
        }
        if language == catalog.sourceLanguage ? isManual : hasArguments {
            return StringCatalog.Localization(stringUnit: StringCatalog.StringUnit(state: nil, value: key))
        }
        return nil
    }

    private func sourceForms(of key: String) -> [String: String] {
        guard let localization = catalog.strings[key]?.localizations?[catalog.sourceLanguage] else { return [:] }
        if let unit = localization.stringUnit {
            return ["other": unit.value]
        }
        return (localization.variations?.plural ?? [:]).compactMapValues(\.stringUnit?.value)
    }
}

struct Tables {
    var plain: [String: PropertyListValue] = [:]
    var rules: [String: PropertyListValue] = [:]
}

private struct Emitter {
    let format: StringCatalogCompiler.Format
    let language: String
    /// The source language's value of the key, by plural form (`other` for a plain string):
    /// a plural whose forms format no number takes it from there.
    let source: [String: String]
    var diagnostics: [StringCatalogCompiler.Diagnostic] = []

    mutating func emit(key: String, localization: StringCatalog.Localization, into tables: inout Tables) {
        if let set = localization.stringSet {
            for (index, value) in set.values.enumerated() {
                addPlain("#!SET#!_\(key)[\(index)]", value, into: &tables)
            }
        } else if let variations = localization.variations {
            if let plural = variations.plural {
                // A plural without a number is reported alone; one with a number cannot name a
                // variable (strings-experiments `specifier-68-*`, `diagnostic-variable-in-plural`).
                if let rule = pluralRule(plural, path: key) {
                    for form in plural.keys.sorted() {
                        for name in referencedVariables(plural[form]!) {
                            error("Cannot reference substitution '\(name)' from here because it is not a plain string", path: "\(key)|==|plural.\(form)")
                        }
                    }
                    tables.rules[key] = .dictionary(rule)
                }
            } else if let devices = variations.device {
                emitDevices(key: key, devices, into: &tables)
            } else if let widths = variations.width {
                emitWidths(key: key, widths, into: &tables)
            }
        } else if let unit = localization.stringUnit {
            if let substitutions = localization.substitutions, !substitutions.isEmpty {
                tables.rules[key] = .dictionary(substitutionRule(unit.value, substitutions))
            } else {
                addPlain(key, unit.value, into: &tables)
            }
        }
    }

    private func referencedVariables(_ localization: StringCatalog.Localization) -> [String] {
        FormatSpecifier.all(in: localization.stringUnit?.value ?? "").compactMap(\.variable)
    }

    private func addPlain(_ key: String, _ value: String, into tables: inout Tables) {
        let compiled = PropertyListValue.string(FormatSpecifier.compiled(value))
        switch format {
        case .stringsAndStringsdict: tables.plain[key] = compiled
        case .stringsdictOnly: tables.rules[key] = compiled
        }
    }

    /// `NSStringDeviceSpecificRuleType`, with the `other` case as the plain string.
    private mutating func emitDevices(key: String, _ devices: [String: StringCatalog.Localization], into tables: inout Tables) {
        var rule: [String: PropertyListValue] = [:]
        for name in devices.keys.sorted() {
            let device = devices[name]!
            let path = "\(key)|==|device.\(name)"
            if name == "other" {
                guard device.variations == nil, let unit = device.stringUnit else {
                    error("Fallback value cannot be further varied", path: path)
                    continue
                }
                guard format == .stringsAndStringsdict else {
                    error("Fallback value must be written to .strings file, which is not possible in stringsdictOnly mode", path: path)
                    continue
                }
                tables.plain[key] = .string(FormatSpecifier.compiled(unit.value))
            } else if let plural = device.variations?.plural {
                if let nested = pluralRule(plural, path: path) {
                    rule[name] = .dictionary(nested)
                }
            } else if let unit = device.stringUnit {
                rule[name] = .string(FormatSpecifier.compiled(unit.value))
            }
        }
        tables.rules[key] = .dictionary(["NSStringDeviceSpecificRuleType": .dictionary(rule)])
    }

    /// `NSStringVariableWidthRuleType`; a width case that varies by plural is its own
    /// top-level rule, `<key>|==|width.<width>`, which the width case names.
    private mutating func emitWidths(key: String, _ widths: [String: StringCatalog.Localization], into tables: inout Tables) {
        var rule: [String: PropertyListValue] = [:]
        for (name, width) in widths {
            if let plural = width.variations?.plural {
                let reference = "\(key)|==|width.\(name)"
                if let nested = pluralRule(plural, path: reference) {
                    rule[name] = .string(reference)
                    tables.rules[reference] = .dictionary(nested)
                }
            } else if let unit = width.stringUnit {
                rule[name] = .string(FormatSpecifier.compiled(unit.value))
            }
        }
        tables.rules[key] = .dictionary(["NSStringVariableWidthRuleType": .dictionary(rule)])
    }

    /// The rule of a plural variation: one variable, `value`, for the number the forms format.
    /// When that number is not the first argument, the format key names its position and every
    /// specifier of the forms is given one.
    private mutating func pluralRule(_ forms: [String: StringCatalog.Localization], path: String) -> [String: PropertyListValue]? {
        var values: [String: String] = [:]
        for (form, localization) in forms {
            guard let unit = localization.stringUnit else { continue }
            values[form] = unit.value
        }
        guard let (argument, type) = pluralNumber(values, path: path) ?? pluralNumber(source, path: path) else {
            error("Plural variation requires referencing the number in the string. To maintain grammatical correctness for strings that do not reference the number of items, use separate top-level strings for one and greater than one.", path: path)
            return nil
        }
        var variable: [String: PropertyListValue] = [
            "NSStringFormatSpecTypeKey": .string("NSStringPluralRuleType"),
            "NSStringFormatValueTypeKey": .string(type),
        ]
        for (form, value) in values {
            variable[form] = .string(FormatSpecifier.compiled(value, positional: argument != 1))
        }
        return [
            "NSStringLocalizedFormatKey": .string(argument == 1 ? "%#@value@" : "%\(argument)$#@value@"),
            "value": .dictionary(variable),
        ]
    }

    /// The number of a plural variation: that of the first form, `other` first, that formats a
    /// number (strings-experiments `plural-inference-*`, `diagnostic-*`). A form that formats numbers of two
    /// types is an error; one type in two positions is a warning, and the first position is
    /// the number.
    private mutating func pluralNumber(_ forms: [String: String], path: String) -> (argument: Int, type: String)? {
        for form in Self.formOrder where forms[form] != nil {
            let numbers = FormatSpecifier.numbered(in: forms[form]!).filter(\.specifier.isNumeric)
            guard let first = numbers.min(by: { $0.argument < $1.argument }) else { continue }
            if Set(numbers.map(\.specifier.type)).count > 1 {
                error("Cannot infer format specifier for string group because more than one numerical specifier was found", path: path)
            } else if Set(numbers.map(\.argument)).count > 1 {
                warning("Cannot reliably infer argument number for plural variation because %\(first.specifier.type) is used in multiple positions. Use an explicit substitution instead.", path: path)
            }
            return (first.argument, first.specifier.type)
        }
        return nil
    }

    static let formOrder = ["other", "zero", "one", "two", "few", "many"]

    /// A string with substitutions: each `%#@name@` gets the substitution's argument number,
    /// and each substitution's forms format `%arg` as `%<argNum>$<formatSpecifier>`.
    private func substitutionRule(_ format: String, _ substitutions: [String: StringCatalog.Substitution]) -> [String: PropertyListValue] {
        var key = ""
        var index = format.startIndex
        for specifier in FormatSpecifier.all(in: format) {
            key += format[index..<specifier.range.lowerBound]
            key += specifier.written(in: format, argument: specifier.variable.flatMap { substitutions[$0]?.argNum })
            index = specifier.range.upperBound
        }
        key += format[index...]
        var rule: [String: PropertyListValue] = ["NSStringLocalizedFormatKey": .string(key)]
        for (name, substitution) in substitutions {
            let specifier = substitution.formatSpecifier!
            let argument = (substitution.argNum.map { "%\($0)$" } ?? "%") + specifier
            var variable: [String: PropertyListValue] = [
                "NSStringFormatSpecTypeKey": .string("NSStringPluralRuleType"),
                "NSStringFormatValueTypeKey": .string(FormatSpecifier.valueType(of: specifier)),
            ]
            for (form, localization) in substitution.variations!.plural! {
                guard let unit = localization.stringUnit else { continue }
                variable[form] = .string(FormatSpecifier.compiled(unit.value.replacingOccurrences(of: "%arg", with: argument)))
            }
            rule[name] = .dictionary(variable)
        }
        return rule
    }

    private mutating func error(_ message: String, path: String) {
        diagnostics.append(.init(severity: .error, message: message, context: "\(language): \(path)"))
    }

    private mutating func warning(_ message: String, path: String) {
        diagnostics.append(.init(severity: .warning, message: message, context: "\(language): \(path)"))
    }
}
