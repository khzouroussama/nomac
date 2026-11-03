import Foundation
import Testing
@testable import NomacStrings

/// strings-experiments `generate-symbols`: xcstringstool writes symbols only for strings added by
/// hand, and empty files for a catalog without any.
@Suite struct StringSymbolsTests {
    func decode(_ strings: String) throws -> StringCatalog {
        try JSONDecoder().decode(StringCatalog.self, from: Data(#"{"sourceLanguage": "en", "strings": {\#(strings)}, "version": "1.0"}"#.utf8))
    }

    /// Of the extraction states, only `manual` gets a symbol (icecubes: 441 symbols for its 441
    /// manual strings; mastodon's `Localizable`: 149 for 149 manual and 678 migrated ones).
    @Test func onlyManualStringsAreEligible() throws {
        let catalog = try decode("""
            "absent": {}, "stale": {"extractionState": "stale"}, "migrated": {"extractionState": "migrated"},
            "with-value": {"extractionState": "extracted_with_value"}, "b": {"extractionState": "manual"},
            "a": {"extractionState": "manual"}
            """)
        #expect(StringSymbols.eligibleKeys(catalog) == ["a", "b"])
        #expect(StringSymbols.eligibleKeys(try decode(#""Hello": {"localizations": {}}"#)).isEmpty)
    }

    @Test func filesAreNamedAfterTheCatalog() {
        #expect(StringSymbols.fileNames(catalogName: "Localizable", language: .swift) == ["GeneratedStringSymbols_Localizable.swift"])
        #expect(StringSymbols.fileNames(catalogName: "InfoPlist", language: .objc)
            == ["SCGeneratedStringSymbols_InfoPlist.h", "SCGeneratedStringSymbols_InfoPlist.m"])
    }
}
