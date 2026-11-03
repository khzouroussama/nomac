import Foundation
import Testing
import NomacCore
import NomacPlist
@testable import NomacStrings

/// What `xcstringstool compile` (Xcode 27.0) writes for self-written catalogs
/// (`.github/scripts/strings_experiments.py`, experiment `xcstrings`).
@Suite struct StringCatalogCompilerTests {
    func compile(_ json: String, languages: [String]? = nil, format: StringCatalogCompiler.Format = .stringsAndStringsdict)
        throws -> (files: [String: [String: PropertyListValue]], diagnostics: [String]) {
        let catalog = try JSONDecoder().decode(StringCatalog.self, from: Data(json.utf8))
        let (outputs, diagnostics) = try StringCatalogCompiler(catalog: catalog, languages: languages, format: format).compile()
        var files: [String: [String: PropertyListValue]] = [:]
        for output in outputs {
            files[output.relativePath(catalogName: "Catalog")] = output.table
        }
        return (files, diagnostics.map { "\($0.severity.rawValue): \($0.message) (\($0.context))" })
    }

    func unit(_ value: String, _ state: String = "translated") -> String {
        #"{ "stringUnit" : { "state" : "\#(state)", "value" : "\#(value)" } }"#
    }

    func catalog(_ strings: String, source: String = "en") -> String {
        #"{ "sourceLanguage" : "\#(source)", "strings" : { \#(strings) }, "version" : "1.0" }"#
    }

    func plural(_ forms: [(String, String)]) -> String {
        let cases = forms.map { #""\#($0.0)" : \#(unit($0.1))"# }.joined(separator: ", ")
        return #"{ "variations" : { "plural" : { \#(cases) } } }"#
    }

    func pluralRule(_ formatKey: String, _ type: String, _ forms: [String: String]) -> PropertyListValue {
        var variable: [String: PropertyListValue] = [
            "NSStringFormatSpecTypeKey": .string("NSStringPluralRuleType"),
            "NSStringFormatValueTypeKey": .string(type),
        ]
        for (form, value) in forms {
            variable[form] = .string(value)
        }
        return .dictionary(["NSStringLocalizedFormatKey": .string(formatKey), "value": .dictionary(variable)])
    }

    @Test func eachLanguageGetsItsTranslations() throws {
        let result = try compile(catalog(#""Hello" : { "localizations" : { "fr" : \#(unit("Bonjour")), "de" : \#(unit("Hallo")) } }"#))
        #expect(result.files == [
            "de.lproj/Catalog.strings": ["Hello": .string("Hallo")],
            "fr.lproj/Catalog.strings": ["Hello": .string("Bonjour")],
        ])
    }

    /// `source-matrix`: in the source language, strings extracted from code get an entry only
    /// for a source unit that is not `new`; manual and migrated strings always get one, their
    /// key when they have no source unit. Other languages get every unit, whatever its state.
    @Test(arguments: [
        (nil as String?, ["same": "same", "differs": "Other", "review": "Other"]),
        ("stale", ["same": "same", "differs": "Other", "review": "Other"]),
        ("extracted_with_value", ["same": "same", "differs": "Other", "review": "Other"]),
        ("manual", ["none": "none", "same": "same", "differs": "Other", "new": "Other", "new-same": "new-same", "review": "Other"]),
        ("migrated", ["none": "none", "same": "same", "differs": "Other", "new": "Other", "new-same": "new-same", "review": "Other"]),
    ])
    func sourceLanguageEntries(extractionState: String?, expected: [String: String]) throws {
        let units = ["none": nil, "same": ("translated", "same"), "differs": ("translated", "Other"),
                     "new": ("new", "Other"), "new-same": ("new", "new-same"), "review": ("needs_review", "Other")]
        let state = extractionState.map { "\"extractionState\" : \"\($0)\", " } ?? ""
        let strings = units.map { key, source in
            let en = source.map { #""en" : \#(unit($0.1, $0.0)), "# } ?? ""
            return #""\#(key)" : { \#(state)"localizations" : { \#(en)"fr" : \#(unit(key + "-fr", "new")) } }"#
        }.joined(separator: ", ")
        let result = try compile(catalog(strings))
        #expect(result.files["en.lproj/Catalog.strings"] == expected.mapValues { .string($0) })
        #expect(result.files["fr.lproj/Catalog.strings"]?.count == units.count)
    }

    /// `plural-source`, `plural-translated`: one variable, `value`, typed by the number's
    /// length modifier and conversion.
    @Test func pluralsBecomeStringsdictRules() throws {
        let result = try compile(catalog(#"""
            "%lld apples" : { "localizations" : {
              "en" : \#(plural([("one", "%lld apple"), ("other", "%lld apples")])),
              "ru" : \#(plural([("one", "%lld a"), ("few", "%lld b"), ("many", "%lld c"), ("other", "%lld d")])) } }
            """#))
        #expect(result.files == [
            "en.lproj/Catalog.stringsdict": ["%lld apples": pluralRule("%#@value@", "lld", ["one": "%lld apple", "other": "%lld apples"])],
            "ru.lproj/Catalog.stringsdict": ["%lld apples": pluralRule("%#@value@", "lld", ["one": "%lld a", "few": "%lld b", "many": "%lld c", "other": "%lld d"])],
        ])
    }

    /// Plural specifiers: the type keeps the length modifier and conversion and drops flags,
    /// width and precision; a number that is not the first argument is named in the format
    /// key, and every specifier of the forms gets its position.
    @Test(arguments: [
        ("%-3d x", "%#@value@", "d", "%-3d x"),
        ("%5lld x", "%#@value@", "lld", "%5lld x"),
        ("%.2f x", "%#@value@", "f", "%.2f x"),
        ("%qd x", "%#@value@", "qd", "%qd x"),
        ("%zd x", "%#@value@", "zd", "%zd x"),
        ("%1$lld x", "%#@value@", "lld", "%1$lld x"),
        ("%@ has %lld x", "%2$#@value@", "lld", "%1$@ has %2$lld x"),
        ("%2$lld x %1$@", "%2$#@value@", "lld", "%2$lld x %1$@"),
        ("%lld %% x", "%#@value@", "lld", "%lld %% x"),
    ])
    func pluralSpecifiers(form: String, formatKey: String, type: String, written: String) throws {
        let result = try compile(catalog(#""k" : { "localizations" : { "en" : \#(plural([("other", form)])) } }"#))
        #expect(result.files == ["en.lproj/Catalog.stringsdict": ["k": pluralRule(formatKey, type, ["other": written])]])
    }

    /// strings-experiments `specifier-*` (docs/formats/strings.md "Format specifiers"): only these are specifiers, so
    /// only they count as the number and lose their argument names.
    @Test(arguments: [
        ("%-d", true), ("%+d", true), ("%0d", true), ("%jd", true), ("%td", true), ("%zd", true), ("%hhd", true),
        ("%qd", true), ("%Lf", true), ("%lf", true), ("%a", true), ("%5.2f", true), ("%2$d", true), ("%1$(x)d", true),
        ("% d", false), ("%#x", false), ("%'d", false), ("%*d", false), ("%.*f", false), ("%Ld", false), ("%n", false),
        ("%k", false), ("%(x) d", false), ("%(x)1$d", false), ("%1", false),
    ])
    func numericSpecifiers(candidate: String, isNumeric: Bool) {
        #expect(FormatSpecifier.all(in: candidate).first?.isNumeric ?? false == isNumeric)
    }

    @Test(arguments: [
        ("%-5@", true), ("%.3@", true), ("%(x)@", true), ("%c", true), ("%C", true), ("%s", true), ("%S", true), ("%p", true),
        ("%l@", false), ("%ll@", false), ("%z@", false), ("%ls", false), ("%hs", false), ("%lc", false), ("%%", false),
    ])
    func otherSpecifiers(candidate: String, isSpecifier: Bool) {
        let specifier = FormatSpecifier.all(in: candidate).first
        #expect((specifier != nil && !specifier!.isNumeric) == isSpecifier)
    }

    /// `named-arguments`: argument names are left out of every compiled string, keys keep them.
    @Test func namedArguments() throws {
        let result = try compile(catalog(#"""
            "plain %(count)lld" : { "localizations" : { "fr" : \#(unit("%(count)lld et %1$(name)@ %(x) d")) } },
            "second %(count)lld" : { "localizations" : { "fr" : \#(plural([("one", "%(name)@ %(count)lld x"), ("other", "%(name)@ %(count)lld xs")])) } }
            """#))
        #expect(result.files == [
            "fr.lproj/Catalog.strings": ["plain %(count)lld": .string("%lld et %1$@ %(x) d")],
            "fr.lproj/Catalog.stringsdict": ["second %(count)lld": pluralRule("%2$#@value@", "lld", ["one": "%1$@ %2$lld x", "other": "%1$@ %2$lld xs"])],
        ])
    }

    /// `plural-inference-*`: the `other` form decides, then the other forms, then the source
    /// language's value; the forms are written as they are.
    @Test(arguments: [
        ("%lld x", [("one", "%@ %d y"), ("other", "%@ %d ys")], "%2$#@value@", "d", ["one": "%1$@ %2$d y", "other": "%1$@ %2$d ys"]),
        ("%@ %lld x", [("one", "y"), ("other", "ys")], "%2$#@value@", "lld", ["one": "y", "other": "ys"]),
        ("%lld x", [("one", "%d %d y"), ("other", "%d ys")], "%#@value@", "d", ["one": "%d %d y", "other": "%d ys"]),
        ("%lld x", [("one", "%d y"), ("other", "%lld ys")], "%#@value@", "lld", ["one": "%d y", "other": "%lld ys"]),
        ("%lld x", [("one", "%(n)lld y"), ("other", "%(n) ys")], "%#@value@", "lld", ["one": "%lld y", "other": "%(n) ys"]),
    ] as [(String, [(String, String)], String, String, [String: String])])
    func pluralNumberInference(source: String, forms: [(String, String)], formatKey: String, type: String, written: [String: String]) throws {
        let result = try compile(catalog(#""k" : { "localizations" : { "en" : \#(unit(source)), "fr" : \#(plural(forms)) } }"#))
        #expect(result.diagnostics.isEmpty)
        #expect(result.files["fr.lproj/Catalog.stringsdict"] == ["k": pluralRule(formatKey, type, written)])
    }

    @Test func twoNumberTypesInAFormAreAnError() throws {
        let result = try compile(catalog(#""k" : { "localizations" : { "en" : \#(plural([("other", "%(a)@ %-d %(n)lld")])) } }"#))
        #expect(result.diagnostics == ["error: Cannot infer format specifier for string group because more than one numerical specifier was found (en: k)"])
    }

    /// `unlocalized-variations`: a manual string whose source value is a plural or has
    /// substitutions gets its key in the languages that have no unit for it.
    @Test func manualPluralsFillOtherLanguages() throws {
        let result = try compile(catalog(#"""
            "manual-plural %lld" : { "extractionState" : "manual", "localizations" : { "en" : \#(plural([("other", "%lld xs")])) } },
            "migrated-plural %lld" : { "extractionState" : "migrated", "localizations" : { "en" : \#(plural([("other", "%lld xs")])) } },
            "manual-plain" : { "extractionState" : "manual", "localizations" : { "en" : \#(unit("Plain")) } },
            "other" : { "localizations" : { "fr" : \#(unit("autre")) } }
            """#))
        #expect(result.files["fr.lproj/Catalog.strings"] == ["manual-plural %lld": .string("manual-plural %lld"), "other": .string("autre")])
    }

    /// `substitution-precision`: the value type drops flags, width and precision, the forms
    /// keep them; a substitution without `argNum` has no position.
    @Test func substitutionSpecifiers() throws {
        let result = try compile(catalog(#"""
            "%.1f m" : { "localizations" : { "fr" : {
              "stringUnit" : { "state" : "translated", "value" : "%#@m@ %#@n@" },
              "substitutions" : {
                "m" : { "argNum" : 1, "formatSpecifier" : ".1f", "variations" : { "plural" : { "other" : \#(unit("%arg ms")) } } },
                "n" : { "formatSpecifier" : "-3ld", "variations" : { "plural" : { "other" : \#(unit("%arg ns")) } } } } } } }
            """#))
        #expect(result.files["fr.lproj/Catalog.stringsdict"] == ["%.1f m": .dictionary([
            "NSStringLocalizedFormatKey": .string("%1$#@m@ %#@n@"),
            "m": .dictionary(["NSStringFormatSpecTypeKey": .string("NSStringPluralRuleType"), "NSStringFormatValueTypeKey": .string("f"), "other": .string("%1$.1f ms")]),
            "n": .dictionary(["NSStringFormatSpecTypeKey": .string("NSStringPluralRuleType"), "NSStringFormatValueTypeKey": .string("ld"), "other": .string("%-3ld ns")]),
        ])])
    }

    /// `language-codes`.
    @Test(arguments: [
        ("kmr-TR", "ku-TR"), ("kmr", "ku"), ("iw", "he"), ("in", "id"), ("ji", "yi"), ("no", "nb"), ("tl", "fil"),
        ("i-klingon", "tlh"), ("art-lojban", "jbo"), ("sr-Cyrl", "sr"), ("Base", "base"), ("x-test", "x-Test"),
        ("EN-gb", "en-GB"), ("de-at", "de-AT"), ("DE", "de"), ("en-US-POSIX", "en-US-posix"), ("de-CH-1996", "de-CH-1996"),
        ("es-419", "es-419"), ("zh-Hans", "zh-Hans"), ("yue-Hant", "yue-Hant"), ("uz-Cyrl", "uz-Cyrl"), ("ckb-IR", "ckb-IR"),
        ("en_AU", "en_AU"), ("es_419", "es_419"), ("az_Cyrl", "az-Cyrl"), ("uz_Latn", "uz"), ("zh_Hans_SG", "zh_SG"),
    ])
    func languageFolders(language: String, folder: String) {
        #expect(LanguageIdentifier.folderName(language) == folder)
    }

    @Test func pluralWithoutNumberIsAnError() throws {
        let result = try compile(catalog(#""%@ at" : { "localizations" : { "en" : \#(plural([("one", "%@ x"), ("other", "%@ xs")])) } }"#))
        #expect(result.diagnostics == ["error: Plural variation requires referencing the number in the string. To maintain grammatical correctness for strings that do not reference the number of items, use separate top-level strings for one and greater than one. (en: %@ at)"])
    }

    @Test func numberInSeveralPositionsIsAWarning() throws {
        let result = try compile(catalog(#""two numbers" : { "localizations" : { "en" : \#(plural([("one", "%lld of %lld"), ("other", "%lld of %lld s")])) } }"#))
        #expect(result.diagnostics == ["warning: Cannot reliably infer argument number for plural variation because %lld is used in multiple positions. Use an explicit substitution instead. (en: two numbers)"])
        #expect(result.files["en.lproj/Catalog.stringsdict"] == ["two numbers": pluralRule("%#@value@", "lld", ["one": "%lld of %lld", "other": "%lld of %lld s"])])
    }

    /// `substitutions`: each `%#@name@` gets the substitution's argument number, and `%arg`
    /// becomes `%<argNum>$<formatSpecifier>`.
    @Test func substitutions() throws {
        let result = try compile(catalog(#"""
            "%lld files in %lld folders" : { "localizations" : { "en" : {
              "stringUnit" : { "state" : "translated", "value" : "%#@files@ in %#@folders@" },
              "substitutions" : {
                "files" : { "argNum" : 1, "formatSpecifier" : "lld", "variations" : { "plural" : { "one" : \#(unit("%arg file")), "other" : \#(unit("%arg files")) } } },
                "folders" : { "argNum" : 2, "formatSpecifier" : "lld", "variations" : { "plural" : { "one" : \#(unit("%arg folder")), "other" : \#(unit("%arg folders")) } } } } } } }
            """#))
        func variable(_ forms: [String: String]) -> PropertyListValue {
            .dictionary(["NSStringFormatSpecTypeKey": .string("NSStringPluralRuleType"), "NSStringFormatValueTypeKey": .string("lld")]
                .merging(forms.mapValues { .string($0) }) { $1 })
        }
        #expect(result.files == ["en.lproj/Catalog.stringsdict": ["%lld files in %lld folders": .dictionary([
            "NSStringLocalizedFormatKey": .string("%1$#@files@ in %2$#@folders@"),
            "files": variable(["one": "%1$lld file", "other": "%1$lld files"]),
            "folders": variable(["one": "%2$lld folder", "other": "%2$lld folders"]),
        ])]])
    }

    /// `device`, `device-nested-plural`: the `other` device is the plain string; the others
    /// are a device rule, with plural rules inline.
    @Test func deviceVariations() throws {
        let result = try compile(catalog(#"""
            "Tap" : { "localizations" : { "en" : { "variations" : { "device" : { "iphone" : \#(unit("Tap")), "mac" : \#(unit("Click")), "other" : \#(unit("Select")) } } } } },
            "%lld taps" : { "localizations" : { "en" : { "variations" : { "device" : {
              "iphone" : \#(plural([("one", "%lld tap"), ("other", "%lld taps")])), "other" : \#(unit("%lld clicks")) } } } } }
            """#))
        #expect(result.files == [
            "en.lproj/Catalog.strings": ["Tap": .string("Select"), "%lld taps": .string("%lld clicks")],
            "en.lproj/Catalog.stringsdict": [
                "Tap": .dictionary(["NSStringDeviceSpecificRuleType": .dictionary(["iphone": .string("Tap"), "mac": .string("Click")])]),
                "%lld taps": .dictionary(["NSStringDeviceSpecificRuleType": .dictionary([
                    "iphone": pluralRule("%#@value@", "lld", ["one": "%lld tap", "other": "%lld taps"])])]),
            ],
        ])
    }

    @Test func deviceFallbackErrors() throws {
        let nested = try compile(catalog(#""%lld taps" : { "localizations" : { "en" : { "variations" : { "device" : { "other" : \#(plural([("one", "%lld"), ("other", "%lld s")])) } } } } }"#))
        #expect(nested.diagnostics == ["error: Fallback value cannot be further varied (en: %lld taps|==|device.other)"])
        let stringsdictOnly = try compile(catalog(#""Tap" : { "localizations" : { "en" : { "variations" : { "device" : { "other" : \#(unit("Select")) } } } } }"#), format: .stringsdictOnly)
        #expect(stringsdictOnly.diagnostics == ["error: Fallback value must be written to .strings file, which is not possible in stringsdictOnly mode (en: Tap|==|device.other)"])
    }

    /// `width-plural`: a width case that varies by plural is a top-level rule of its own.
    @Test func widthVariations() throws {
        let result = try compile(catalog(#"""
            "Title" : { "localizations" : { "en" : { "variations" : { "width" : { "1" : \#(unit("T")), "20" : \#(plural([("other", "%lld ws")])) } } } } }
            """#))
        #expect(result.files == ["en.lproj/Catalog.stringsdict": [
            "Title": .dictionary(["NSStringVariableWidthRuleType": .dictionary(["1": .string("T"), "20": .string("Title|==|width.20")])]),
            "Title|==|width.20": pluralRule("%#@value@", "lld", ["other": "%lld ws"]),
        ]])
    }

    /// B-264: substitutions nothing observed has.
    @Test(arguments: [
        (#"{ "argNum" : 1, "variations" : { "plural" : { "other" : { "stringUnit" : { "state" : "translated", "value" : "%arg" } } } } }"#, "which has no formatSpecifier"),
        (#"{ "argNum" : 1, "formatSpecifier" : "lld", "variations" : { "device" : { "other" : { "stringUnit" : { "state" : "translated", "value" : "%arg" } } } } }"#, "which does not vary by plural"),
    ])
    func refusesUnobservedSubstitutions(substitution: String, what: String) throws {
        let json = catalog(#""k" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "%#@s@" }, "substitutions" : { "s" : \#(substitution) } } } }"#)
        #expect(throws: NomacError("nomac does not compile the substitution s of k, \(what), yet (BACKLOG B-264)")) {
            try compile(json)
        }
    }

    /// `key-order` and `stringsdict-key-order`: `.strings` keys in UTF-16 order, `.stringsdict`
    /// keys in Swift's (U+FF01 before U+1F600 there, after it here).
    @Test func outputsSortTheirKeys() throws {
        let keys = ["\u{FF01}", "\u{1F600}", "z", "\u{E9}"]
        let plain = keys.map { #""\#($0)" : { "localizations" : { "fr" : \#(unit($0)) } }"# }
        let plurals = keys.map { #""\#($0) %lld" : { "localizations" : { "fr" : \#(plural([("other", "%lld")])) } }"# }
        let decoded = try JSONDecoder().decode(StringCatalog.self, from: Data(catalog((plain + plurals).joined(separator: ", ")).utf8))
        func written(_ output: StringCatalogCompiler.Output) -> [String] {
            String(decoding: XMLPropertyList.data(.dictionary(output.table), keyOrder: output.keyOrder), as: UTF8.self)
                .components(separatedBy: "\n").filter { $0.hasPrefix("\t<key>") }.map { String($0.dropFirst(6).dropLast(6)) }
        }
        let outputs = try StringCatalogCompiler(catalog: decoded).compile().outputs
        #expect(written(outputs.first { $0.fileExtension == "strings" }!) == ["z", "\u{E9}", "\u{1F600}", "\u{FF01}"])
        #expect(written(outputs.first { $0.fileExtension == "stringsdict" }!) == ["z %lld", "\u{E9} %lld", "\u{FF01} %lld", "\u{1F600} %lld"])
    }

    @Test func stringSets() throws {
        let result = try compile(catalog(#""Phrase" : { "localizations" : { "en" : { "stringSet" : { "state" : "translated", "values" : [ "a", "b" ] } } } }"#))
        #expect(result.files == ["en.lproj/Catalog.strings": ["#!SET#!_Phrase[0]": .string("a"), "#!SET#!_Phrase[1]": .string("b")]])
    }

    /// `mixed` with `--format stringsdictOnly` and `-l fr`.
    @Test func formatAndLanguageOptions() throws {
        let mixed = catalog(#"""
            "Hello" : { "localizations" : { "fr" : \#(unit("Bonjour")), "de" : \#(unit("Hallo")) } },
            "%lld apples" : { "localizations" : { "fr" : \#(plural([("other", "%lld pommes")])) } }
            """#)
        let only = try compile(mixed, format: .stringsdictOnly)
        #expect(only.files["fr.lproj/Catalog.stringsdict"] == [
            "Hello": .string("Bonjour"), "%lld apples": pluralRule("%#@value@", "lld", ["other": "%lld pommes"]),
        ])
        #expect(try compile(mixed, languages: ["fr"]).files.keys.sorted() == ["fr.lproj/Catalog.strings", "fr.lproj/Catalog.stringsdict"])
    }

    @Test func emptyCatalogsCompileToNothing() throws {
        #expect(try compile(catalog("")).files.isEmpty)
        #expect(try compile(catalog(#""Hello" : { }"#)).files.isEmpty)
    }
}
