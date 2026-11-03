import Foundation

/// What `xcstringstool generate-symbols` writes for a string catalog (the GenerateStringSymbols task,
/// strings-experiments `generate-symbols`, docs/formats/strings.md "Generated symbols").
public enum StringSymbols {
    public enum Language: String, CaseIterable, Sendable {
        case swift, objc
    }

    /// The files written for `language`, named after the catalog.
    public static func fileNames(catalogName: String, language: Language) -> [String] {
        switch language {
        case .swift: ["GeneratedStringSymbols_\(catalogName).swift"]
        case .objc: ["SCGeneratedStringSymbols_\(catalogName).h", "SCGeneratedStringSymbols_\(catalogName).m"]
        }
    }

    /// The keys that get symbols, in key order: the strings added by hand (`extractionState` manual).
    /// Without any, every file is empty.
    public static func eligibleKeys(_ catalog: StringCatalog) -> [String] {
        catalog.strings.filter { $0.value.extractionState == "manual" }.keys.sorted()
    }
}
