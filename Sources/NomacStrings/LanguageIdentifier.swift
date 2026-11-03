/// The `.lproj` folder `xcstringstool compile` writes a catalog language to
/// (docs/formats/strings.md "Language folders"; strings-experiments `language-codes`).
enum LanguageIdentifier {
    /// Whole identifiers Xcode replaces.
    static let replacedIdentifiers = ["i-klingon": "tlh", "art-lojban": "jbo", "sr-Cyrl": "sr"]
    /// Deprecated language subtags Xcode replaces, keeping the other subtags.
    static let replacedLanguages = ["iw": "he", "in": "id", "ji": "yi", "no": "nb", "tl": "fil", "kmr": "ku"]
    /// Scripts an identifier written with `_` loses (`uz_Latn` is `uz`, `zh_Hans_SG` is `zh_SG`).
    static let defaultScripts = ["uz": "Latn", "zh": "Hans"]

    /// The folder name of `language`.
    static func folderName(_ language: String) -> String {
        if let replacement = replacedIdentifiers[language] {
            return replacement
        }
        if language.contains("_") {
            return underscoredFolderName(language)
        }
        var subtags = language.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        subtags[0] = subtags[0].lowercased()
        subtags[0] = replacedLanguages[subtags[0]] ?? subtags[0]
        for index in subtags.indices.dropFirst() {
            subtags[index] = cased(subtags[index])
        }
        return subtags.joined(separator: "-")
    }

    /// Subtag case after the language: a four-letter subtag is a script, titlecase
    /// (`x-test` is `x-Test`); a two-letter one a region, uppercase; others lowercase
    /// (`en-US-POSIX` is `en-US-posix`, `es-419` and `de-CH-1996` stay).
    private static func cased(_ subtag: String) -> String {
        if subtag.count == 4, subtag.allSatisfy(\.isLetter) {
            return subtag.prefix(1).uppercased() + subtag.dropFirst().lowercased()
        }
        return subtag.count == 2 ? subtag.uppercased() : subtag.lowercased()
    }

    /// `en_AU`, `pt_PT` and `es_419` stay as they are; a script is dropped when it is the
    /// language's default, and otherwise makes the identifier hyphenated (`az_Cyrl` is `az-Cyrl`).
    private static func underscoredFolderName(_ language: String) -> String {
        let subtags = language.split(separator: "_").map(String.init)
        guard subtags.count > 1, subtags[1].count == 4, subtags[1].allSatisfy(\.isLetter) else { return language }
        if defaultScripts[subtags[0]] == subtags[1] {
            return ([subtags[0]] + subtags.dropFirst(2)).joined(separator: "_")
        }
        return subtags.joined(separator: "-")
    }
}
