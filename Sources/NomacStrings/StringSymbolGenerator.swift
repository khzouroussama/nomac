import Foundation

/// The Swift source `xcstringstool generate-symbols --language swift` writes for a string
/// catalog in Xcode 27.0: a `LocalizedStringResource` member for each manually added string
/// (docs/formats/strings.md "Generated symbols"; strings-experiments `generate-symbols` and the
/// corpus catalogs).
public struct StringSymbolGenerator: Sendable {
    public typealias Diagnostic = StringCatalogCompiler.Diagnostic

    public struct Output: Sendable {
        /// The file's contents, empty when no manual string gets a symbol.
        public var source: String
        public var diagnostics: [Diagnostic]
        /// The error xcstringstool exits with after the diagnostics, if any.
        public var failure: String?
    }

    public var catalog: StringCatalog
    /// The catalog's file name without `.xcstrings`.
    public var tableName: String

    public init(catalog: StringCatalog, tableName: String) {
        self.catalog = catalog
        self.tableName = tableName
    }

    public func generate() -> Output {
        let keys = StringSymbols.eligibleKeys(catalog)
        guard !keys.isEmpty else {
            return Output(source: "", diagnostics: [])
        }
        var diagnostics: [Diagnostic] = []
        var names: [String: String] = [:]
        var members: [String: [Argument]] = [:]
        for key in keys {
            switch SwiftSymbolName.member(key) {
            case .success(let name):
                names[key] = name
            case .failure(let failure):
                diagnostics.append(error(Self.keyMessage(failure), key: key))
                continue
            }
            var analysis = ArgumentAnalysis(catalog: catalog, key: key)
            if let arguments = analysis.run() {
                members[key] = arguments
            }
            diagnostics += analysis.diagnostics
        }
        // Overloads are not collisions: a property and a function, or functions whose labels or
        // types differ, may share a name (strings-experiments `symbols-collisions`).
        func signature(_ key: String) -> String {
            names[key]! + (members[key]!.isEmpty ? "" : "(" + members[key]!.map { "\($0.label ?? "_"):\($0.type)" }.joined(separator: ",") + ")")
        }
        let keysBySignature = Dictionary(grouping: members.keys, by: signature)
        for key in keys {
            guard members[key] != nil, let others = keysBySignature[signature(key)]?.filter({ $0 != key }).sorted(), !others.isEmpty else { continue }
            members[key] = nil
            diagnostics.append(error("This string key would generate the same symbol as \(Self.list(others)). Please change the key or disable symbol generation for this string.", key: key))
        }
        var namespace: String?
        if tableName != "Localizable" {
            switch SwiftSymbolName.type(tableName) {
            case .success(let name):
                namespace = name
            case .failure:
                return Output(source: "", diagnostics: diagnostics,
                              failure: "error: This table name is too close to a reserved keyword in Swift. Please rename the file.")
            }
        }
        let rendered = keys.compactMap { key in members[key].map { render(key: key, name: names[key]!, arguments: $0, indent: namespace == nil ? 4 : 8) } }
        guard !rendered.isEmpty else {
            return Output(source: "", diagnostics: diagnostics)
        }
        var body = rendered.joined(separator: "\n\n")
        if let namespace {
            body = "    /// Namespace for strings in file “\(tableName).xcstrings”.\n    enum \(namespace) {\n\(body)\n    }"
        }
        return Output(source: header + body + "\n}", diagnostics: diagnostics)
    }

    private var header: String {
        """
        // \n\
        // \(StringSymbols.fileNames(catalogName: tableName, language: .swift)[0])
        // Auto-Generated symbols for localized strings defined in “\(tableName).xcstrings”.
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

        """
    }

    private func render(key: String, name: String, arguments: [Argument], indent: Int) -> String {
        let pad = String(repeating: " ", count: indent)
        var lines = ["\(pad)/**"]
        if let comment = catalog.strings[key]?.comment {
            let text = comment.replacingOccurrences(of: "*/", with: "* /").replacingOccurrences(of: "/*", with: "/ *")
            lines += ["\(pad) \(text)", "\(pad) "]
        }
        lines += ["\(pad) Localized string for key “\(key)” in table “\(tableName).xcstrings”.", "\(pad) */"]
        let table = "table: \(Self.literal(tableName)), bundle: resourceBundleDescription"
        if arguments.isEmpty {
            lines += ["\(pad)static var \(name): LocalizedStringResource {",
                      "\(pad)    LocalizedStringResource(\(Self.literal(key)), \(table))"]
        } else {
            let parameters = arguments.enumerated().map { index, argument in
                argument.label.map { "\($0): \(argument.type)" } ?? "_ arg\(index + 1): \(argument.type)"
            }
            let interpolations = arguments.enumerated().map { index, argument in
                let value = argument.label ?? "arg\(index + 1)"
                return argument.specifier.map { "\\(\(value), specifier: \(Self.literal($0)))" } ?? "\\(\(value))"
            }
            lines += ["\(pad)static func \(name)(\(parameters.joined(separator: ", "))) -> LocalizedStringResource {",
                      "\(pad)    LocalizedStringResource(\(Self.literal(key)), defaultValue: \"\(interpolations.joined())\", \(table))"]
        }
        lines.append("\(pad)}")
        return lines.joined(separator: "\n")
    }

    private func error(_ message: String, key: String) -> Diagnostic {
        Diagnostic(severity: .error, message: message, context: "allLocales: \(key)")
    }

    static func keyMessage(_ failure: SwiftSymbolName.Failure) -> String {
        switch failure {
        case .empty: "Unable to derive a symbol name from this key."
        case .onlyInvalidCharacters: "Unable to derive a symbol name from this key. It only contains characters that are invalid in Swift."
        case .reservedKeyword: "This key is too close to a reserved keyword in Swift. Please rename the key."
        }
    }

    /// `“a”`, `“a” and “b”`, `“a”, “b”, and “c”`.
    static func list(_ keys: [String]) -> String {
        let quoted = keys.map { "“\($0)”" }
        guard quoted.count > 2 else { return quoted.joined(separator: " and ") }
        return quoted.dropLast().joined(separator: ", ") + ", and " + quoted.last!
    }

    /// A Swift string literal: `\0`, `\t`, `\n`, `\r`, `\"` and `\\`, then `\u{…}` for other
    /// control and format characters; everything else as it is (`'`, U+2028, private use).
    static func literal(_ string: String) -> String {
        var result = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\0": result += "\\0"
            case "\t": result += "\\t"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            default:
                switch scalar.properties.generalCategory {
                case .control, .format: result += "\\u{\(String(scalar.value, radix: 16, uppercase: true))}"
                default: result.unicodeScalars.append(scalar)
                }
            }
        }
        return result + "\""
    }
}

/// A generated function's parameter.
struct Argument {
    var label: String?
    var type: String
    /// The interpolation's `specifier:`, none for `%@`.
    var specifier: String?
}

/// The arguments of a manual string, from its localizations' format specifiers.
///
/// In each localization, `%#@name@` is a specifier named after its substitution, with the
/// substitution's format specifier, at its own position, else the substitution's `argNum`, else
/// the next one; each later `%#@name@` is the same argument. In the substitution's forms, `%arg`
/// is an unlabeled argument of that type at the `argNum`, and specifiers without a position
/// count from the substitution's position. Arguments at one position with different types, or
/// with different `%(name)` names, are an error, as is one name at two positions; the other
/// specifiers of a form only fill positions nothing else gives, and must agree within their
/// form. Across localizations, each position takes the source language's argument, else that of
/// the last other language in case-insensitive order. `%#@name@` and `%(name)lld` arguments are
/// labeled with the name.
struct ArgumentAnalysis {
    let catalog: StringCatalog
    let key: String
    var diagnostics: [StringCatalogCompiler.Diagnostic] = []

    init(catalog: StringCatalog, key: String) {
        self.catalog = catalog
        self.key = key
    }

    struct Slot {
        /// The specifier as xcstringstool names it in diagnostics, position left out.
        var display: String
        /// Length and conversion.
        var conversion: String
        var specifier: String
        /// The name of a `%(name)lld` specifier: one name, one position.
        var name: String?
        var label: String?
    }

    static let swiftTypes = [
        "@": "String", "d": "Int32", "u": "UInt32", "f": "Float", "g": "Double",
        "ld": "Int", "lu": "UInt", "lf": "Double", "lld": "Int", "llu": "UInt",
    ]

    mutating func run() -> [Argument]? {
        let entry = catalog.strings[key]!
        var localizations = entry.localizations ?? [:]
        let source = localizations.removeValue(forKey: catalog.sourceLanguage)
        let others = localizations.keys.sorted { ($0.lowercased(), $0) < ($1.lowercased(), $1) }
        var merged: [Int: Slot] = [:]
        var warnings: [StringCatalogCompiler.Diagnostic] = []
        let ordered: [(String, StringCatalog.Localization?)] = others.map { ($0, localizations[$0]) } + [(catalog.sourceLanguage, source)]
        for (language, localization) in ordered {
            let lenient = localization == nil
            let localization = localization ?? StringCatalog.Localization(stringUnit: StringCatalog.StringUnit(state: nil, value: key))
            guard let slots = slots(of: localization, language: language, lenient: lenient, warnings: &warnings) else { return nil }
            merged.merge(slots) { $1 }
        }
        // Label warnings stand unless a localization is inconsistent (strings-experiments `symbols-warnings`).
        diagnostics += warnings
        guard merged.keys.max() ?? 0 == merged.count else {
            fail("Some argument numbers were skipped. Make sure that each argument number is referenced in the translation of at least one language.")
            return nil
        }
        var arguments: [Argument] = []
        for position in merged.keys.sorted() {
            let slot = merged[position]!
            guard let type = Self.swiftTypes[slot.conversion] else {
                fail("Unable to create a Swift type from the format specifier “\(slot.display)”.")
                return nil
            }
            arguments.append(Argument(label: slot.label, type: type, specifier: slot.conversion == "@" ? nil : slot.specifier))
        }
        return arguments
    }

    /// The arguments of one localization. The key, standing for a source localization the entry
    /// lacks, is `lenient`: the last specifier at a position wins, and nothing is inconsistent.
    private mutating func slots(of localization: StringCatalog.Localization, language: String, lenient: Bool,
                                warnings: inout [StringCatalogCompiler.Diagnostic]) -> [Int: Slot]? {
        let substitutions = localization.substitutions ?? [:]
        var declared: [Int: Slot] = [:]
        var filled: [Int: Slot] = [:]
        var namedPositions: [String: Int] = [:]
        var consistent = true
        func declare(_ position: Int, _ slot: Slot) {
            if lenient {
                declared[position] = slot
                return
            }
            if let name = slot.name {
                consistent = consistent && namedPositions[name, default: position] == position
                namedPositions[name] = position
            }
            guard let existing = declared[position] else {
                declared[position] = slot
                return
            }
            if existing.conversion != slot.conversion || existing.name != slot.name {
                consistent = false
            } else if existing.label == nil {
                declared[position]!.label = slot.label
            }
        }
        var substitutionPositions: [String: Int] = [:]
        for value in Self.leaves(localization) {
            var next = 1
            for specifier in FormatSpecifier.all(in: value) {
                let variable = specifier.variable
                let position: Int
                if let variable, let known = substitutionPositions[variable] {
                    position = known
                } else if let explicit = specifier.position {
                    position = explicit
                } else if let variable, let argNum = substitutions[variable]?.argNum {
                    position = argNum
                } else {
                    position = next
                    next += 1
                }
                guard let variable else {
                    declare(position, Self.slot(specifier, in: value))
                    continue
                }
                guard let substitution = substitutions[variable] else { continue }
                substitutionPositions[variable] = position
                guard let slot = substitutionSlot(variable, substitution, language: language, warnings: &warnings) else { return nil }
                declare(position, slot)
            }
        }
        for name in substitutions.keys.sorted() {
            let substitution = substitutions[name]!
            guard let formatSpecifier = substitution.formatSpecifier else {
                fail("Unable to create a Swift type from the format specifier “%arg”.")
                return nil
            }
            let marker = "%" + (substitution.argNum.map { "\($0)$" } ?? "") + "(\(name))" + formatSpecifier
            for form in Self.leaves(variations: substitution.variations) {
                let value = form.replacingOccurrences(of: "%arg", with: marker)
                var next = substitutionPositions[name] ?? substitution.argNum ?? 1
                var conversions: [Int: String] = [:]
                for specifier in FormatSpecifier.all(in: value) where specifier.variable == nil {
                    let position = specifier.position ?? next
                    if specifier.position == nil {
                        next += 1
                    }
                    consistent = consistent && conversions[position, default: specifier.type] == specifier.type
                    conversions[position] = specifier.type
                    var slot = Self.slot(specifier, in: value)
                    if slot.name == name {
                        slot.display = "%(\(name))" + formatSpecifier
                        slot.specifier = "%" + formatSpecifier
                        slot.name = nil
                        slot.label = nil
                        declare(position, slot)
                    } else if filled[position] == nil {
                        filled[position] = slot
                    }
                }
            }
        }
        guard consistent else {
            fail("A symbol cannot be generated for this string because format specifiers are inconsistent.")
            return nil
        }
        return filled.merging(declared) { $1 }
    }

    /// `%#@name@`'s argument: `%(name)<formatSpecifier>`, labeled with the name.
    private mutating func substitutionSlot(_ name: String, _ substitution: StringCatalog.Substitution, language: String,
                                           warnings: inout [StringCatalogCompiler.Diagnostic]) -> Slot? {
        guard let formatSpecifier = substitution.formatSpecifier else {
            fail("Unable to create a Swift type from the format specifier “%arg”.")
            return nil
        }
        let display = "%(\(name))" + formatSpecifier
        let parsed = FormatSpecifier.all(in: display)
        let conversion = parsed.count == 1 && parsed[0].range == display.startIndex..<display.endIndex ? parsed[0].type : display
        var label: String?
        switch SwiftSymbolName.member(name) {
        case .success(let derived):
            label = derived
        case .failure(.reservedKeyword):
            warnings.append(.init(severity: .warning,
                                  message: "The format specifier label “\(name)” is too close to a reserved keyword in Swift. Please rename it.",
                                  context: "\(LanguageIdentifier.folderName(language)): \(key)|==|substitutions.\(name)"))
        case .failure:
            break
        }
        return Slot(display: display, conversion: conversion, specifier: "%" + formatSpecifier, name: nil, label: label)
    }

    /// A plain specifier: its text without the argument position.
    private static func slot(_ specifier: FormatSpecifier, in string: String) -> Slot {
        var text = string[specifier.range].dropFirst()
        if specifier.position != nil, let dollar = text.firstIndex(of: "$") {
            text = text[text.index(after: dollar)...]
        }
        var plain = text
        var name: String?
        if let range = specifier.name {
            plain.removeSubrange(range)
            name = String(string[range].dropFirst().dropLast())
        }
        return Slot(display: "%" + text, conversion: specifier.type, specifier: "%" + plain, name: name,
                    label: name.flatMap { try? SwiftSymbolName.member($0).get() })
    }

    private static func leaves(_ localization: StringCatalog.Localization) -> [String] {
        (localization.stringUnit.map { [$0.value] } ?? []) + leaves(variations: localization.variations)
    }

    private static func leaves(variations: StringCatalog.Variations?) -> [String] {
        guard let variations else { return [] }
        return [variations.plural, variations.device, variations.width].flatMap { cases in
            (cases ?? [:]).keys.sorted().flatMap { leaves(cases![$0]!) }
        }
    }

    private mutating func fail(_ message: String) {
        diagnostics.append(.init(severity: .error, message: message, context: "allLocales: \(key)"))
    }
}
