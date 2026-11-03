import Foundation
import Testing
@testable import NomacStrings

/// What `xcstringstool generate-symbols --language swift` (Xcode 27.0) writes for manual strings
/// (`.github/scripts/strings_experiments.py`, experiment `generate-symbols`, the `symbols-*` catalogs).
@Suite struct StringSymbolGeneratorTests {
    func generate(_ strings: [String: Any], table: String = "Localizable") throws -> StringSymbolGenerator.Output {
        let json = try JSONSerialization.data(withJSONObject: ["sourceLanguage": "en", "strings": strings, "version": "1.0"])
        return StringSymbolGenerator(catalog: try JSONDecoder().decode(StringCatalog.self, from: json), tableName: table).generate()
    }

    func manual(_ localizations: [String: Any]? = nil, comment: String? = nil) -> [String: Any] {
        var entry: [String: Any] = ["extractionState": "manual"]
        entry["localizations"] = localizations
        entry["comment"] = comment
        return entry
    }

    func unit(_ value: String) -> [String: Any] {
        ["stringUnit": ["state": "translated", "value": value]]
    }

    func substituted(_ value: String, _ name: String, _ specifier: String = "lld", argNum: Int? = nil, form: String = "%arg") -> [String: Any] {
        var substitution: [String: Any] = ["formatSpecifier": specifier, "variations": ["plural": ["other": unit(form)]]]
        substitution["argNum"] = argNum
        return ["stringUnit": ["state": "translated", "value": value], "substitutions": [name: substitution]]
    }

    /// The `static var` or `static func` line of each member, by key order.
    func declarations(_ output: StringSymbolGenerator.Output) -> [String] {
        output.source.split(separator: "\n").filter { $0.contains("static var ") || $0.contains("static func ") }
            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " -> LocalizedStringResource {", with: "")
                .replacingOccurrences(of: ": LocalizedStringResource {", with: "") }
    }

    func errors(_ output: StringSymbolGenerator.Output) -> [String] {
        output.diagnostics.filter { $0.severity == .error }.map { "\($0.message) (\($0.context))" }.sorted()
    }

    @Test func memberNamesFollowObservedRules() throws {
        let expected = [
            "URL loader": "urlLoader", "the URL": "theUrl", "x URLLoader": "xUrlloader", "MyURL": "myURL", "x aBC": "xABC",
            "x iOS": "xIOS", "ABcDef": "abcDef", "1 apple": "_1Apple", "ab12cd": "ab12Cd", "a1b2": "a1B2", "x 2nd": "x2Nd",
            "__COLUMN__": "_Column", "-_x": "_X", "$money": "_$Money", "a$b": "a$B", "a·b": "a·B", "İstanbul": "i̇stanbul",
            "x ǆemal": "xǄemal", "x ǅZ": "xǅZ", "x ßZ": "xSSZ", "x ꜰZZa": "xꜰzza", "ꜰZZa y": "ꜰzzaY", "日本語": "日本語",
            "a日b": "a日B", "it's": "its", "a''b": "aB", "a‘b": "aB", "x\u{200B}y": "xY", "\u{200B}ab": "\u{200B}Ab",
            "x %lld items": "xItems", "a%#@x@b": "a1$XB", "%1$@%#@x@b": "b", "class": "`class`", "Init": "`init`",
            "Any": "`Any`", "Self": "`Self`", "#if": "`if`", "package": "package", "__": "`_`",
        ]
        for (key, name) in expected {
            #expect(SwiftSymbolName.member(key) == .success(name), "\(key)")
        }
        #expect(SwiftSymbolName.member("") == .failure(.empty))
        #expect(SwiftSymbolName.member(" ") == .failure(.onlyInvalidCharacters))
        for key in ["self", "SELF", "Type", "Protocol"] {
            #expect(SwiftSymbolName.member(key) == .failure(.reservedKeyword))
        }
    }

    @Test func typeNamesCapitalizeEachWord() {
        for (table, name) in ["My Strings": "MyStrings", "x URL ABC def": "XURLABCDef", "LOCALIZABLE": "LOCALIZABLE", "1abc": "_1Abc",
                              "__x": "_X", "class": "`class`"] {
            #expect(SwiftSymbolName.type(table) == .success(name), "\(table)")
        }
        #expect(SwiftSymbolName.type("Type") == .failure(.reservedKeyword))
    }

    @Test func onlyManualStringsGetSymbols() throws {
        let output = try generate(["b": manual(), "a": manual(), "stale": ["extractionState": "stale"], "plain": [:]])
        #expect(declarations(output) == ["static var a", "static var b"])
        #expect(try generate(["plain": [:]]).source.isEmpty)
        #expect(try generate(["self": manual()]).source.isEmpty)
    }

    @Test func wholeFile() throws {
        let output = try generate(["Hi %@": manual(comment: "A */ greeting"), "a": manual()])
        #expect(output.source == """
            // \n\
            // GeneratedStringSymbols_Localizable.swift
            // Auto-Generated symbols for localized strings defined in “Localizable.xcstrings”.
            // \n\

            import Foundation

            #if SWIFT_PACKAGE
            private nonisolated let resourceBundle = Foundation.Bundle.module
            @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
            private nonisolated let resourceBundleDescription = LocalizedStringResource.BundleDescription.atURL(resourceBundle.bundleURL)
            #else

            private class ResourceBundleClass {}
            @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
            private nonisolated let resourceBundleDescription = LocalizedStringResource.BundleDescription.forClass(ResourceBundleClass.self)
            #endif

            @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
            nonisolated extension LocalizedStringResource {
                /**
                 A * / greeting
                 \n\
                 Localized string for key “Hi %@” in table “Localizable.xcstrings”.
                 */
                static func hi(_ arg1: String) -> LocalizedStringResource {
                    LocalizedStringResource("Hi %@", defaultValue: "\\(arg1)", table: "Localizable", bundle: resourceBundleDescription)
                }

                /**
                 Localized string for key “a” in table “Localizable.xcstrings”.
                 */
                static var a: LocalizedStringResource {
                    LocalizedStringResource("a", table: "Localizable", bundle: resourceBundleDescription)
                }
            }
            """)
    }

    @Test func otherTablesGetANamespace() throws {
        let source = try generate(["k": manual()], table: "My Strings").source
        #expect(source.contains("""
                /// Namespace for strings in file “My Strings.xcstrings”.
                enum MyStrings {
                    /**
                     Localized string for key “k” in table “My Strings.xcstrings”.
                     */
                    static var k: LocalizedStringResource {
                        LocalizedStringResource("k", table: "My Strings", bundle: resourceBundleDescription)
                    }
                }
            }
            """))
        let failed = try generate(["k": manual()], table: "Type")
        #expect(failed.source.isEmpty)
        #expect(failed.failure == "error: This table name is too close to a reserved keyword in Swift. Please rename the file.")
    }

    @Test func literalsEscapeControlAndFormatCharacters() {
        #expect(StringSymbolGenerator.literal("a\"b\\c\n\t\r\0'\u{7}\u{AD}\u{200B}\u{2028}é") == #""a\"b\\c\n\t\r\0'\u{7}\u{AD}\u{200B}"# + "\u{2028}é\"")
    }

    @Test func argumentTypesComeFromSpecifiers() throws {
        let output = try generate([
            "k1": manual(["en": unit("%@ %d %u %f %g %ld %lu %lf %lld %llu")]),
            "k2": manual(["en": unit("%.2f %-3@")]),
            "k3": manual(["en": unit("%i")]),
            "k4 %lld": manual(["en": unit("no arguments")]),
            "k5 %lld": manual(),
        ])
        #expect(declarations(output) == [
            "static func k1(_ arg1: String, _ arg2: Int32, _ arg3: UInt32, _ arg4: Float, _ arg5: Double, _ arg6: Int, _ arg7: UInt, _ arg8: Double, _ arg9: Int, _ arg10: UInt)",
            "static func k2(_ arg1: Float, _ arg2: String)",
            "static var k4",
            "static func k5(_ arg1: Int)",
        ])
        #expect(output.source.contains(#"defaultValue: "\(arg1, specifier: "%.2f")\(arg2)""#))
        #expect(errors(output) == ["Unable to create a Swift type from the format specifier “%i”. (allLocales: k3)"])
    }

    @Test func labelsAndPositions() throws {
        let output = try generate([
            "s1": manual(["en": substituted("%@ has %#@apples@", "apples", argNum: 2)]),
            "s2": manual(["en": substituted("%#@x y@", "x y")]),
            "s3": manual(["en": substituted("%#@n@", "n", form: "%@ %arg")]),
            "s4": manual(["en": substituted("%2$#@x@ %1$@", "x", form: "%arg %@")]),
            "s5": manual(["en": unit("%(used)lld of %(limit)lld")]),
            "s6": manual(["en": substituted("%#@self@", "self")]),
            "m1": manual(["fr": unit("%@"), "de": unit("%lld")]),
            "m2": manual(["en": unit("x"), "de": substituted("%#@del@", "del"), "fr": unit("%2$@")]),
        ])
        #expect(declarations(output) == [
            "static func m1(_ arg1: String)",
            "static func m2(del: Int, _ arg2: String)",
            "static func s1(_ arg1: String, apples: Int)",
            "static func s2(xY: Int)",
            "static func s3(n: Int, _ arg2: Int)",
            "static func s4(_ arg1: String, x: Int, _ arg3: String)",
            "static func s5(used: Int, limit: Int)",
            "static func s6(_ arg1: Int)",
        ])
        #expect(output.diagnostics.map(\.context) == ["en: s6|==|substitutions.self"])
    }

    @Test func inconsistentAndSkippedArguments() throws {
        let output = try generate([
            "a": manual(["en": unit("%1$@ %1$lld")]),
            "b": manual(["en": unit("%(n)lld %(n)lld")]),
            "c": manual(["en": unit("%3$@")]),
            "d %1$@ %1$lld": manual(),
            "e": manual(["en": substituted("%#@self@", "self"), "de": unit("%1$@ %1$lld")]),
        ])
        #expect(errors(output) == [
            "A symbol cannot be generated for this string because format specifiers are inconsistent. (allLocales: a)",
            "A symbol cannot be generated for this string because format specifiers are inconsistent. (allLocales: b)",
            "A symbol cannot be generated for this string because format specifiers are inconsistent. (allLocales: e)",
            "Some argument numbers were skipped. Make sure that each argument number is referenced in the translation of at least one language. (allLocales: c)",
        ])
        #expect(declarations(output) == ["static func d(_ arg1: Int)"])
        #expect(output.diagnostics.allSatisfy { $0.severity == .error })
    }

    @Test func collisionsAreSameSignatures() throws {
        let output = try generate(["a": manual(), "a %@": manual(), "b %@": manual(), "b-%@": manual(), "c %@": manual(), "c %lld": manual()])
        #expect(declarations(output) == ["static var a", "static func a(_ arg1: String)", "static func c(_ arg1: String)", "static func c(_ arg1: Int)"])
        #expect(errors(output) == [
            "This string key would generate the same symbol as “b %@”. Please change the key or disable symbol generation for this string. (allLocales: b-%@)",
            "This string key would generate the same symbol as “b-%@”. Please change the key or disable symbol generation for this string. (allLocales: b %@)",
        ])
        #expect(StringSymbolGenerator.list(["a", "b", "c"]) == "“a”, “b”, and “c”")
    }
}
