/// The Swift names `xcstringstool generate-symbols` derives from string keys, substitution names
/// and table names (docs/formats/strings.md "Generated symbols"; strings-experiments
/// `generate-symbols`).
enum SwiftSymbolName {
    enum Failure: Error, Equatable {
        case empty
        case onlyInvalidCharacters
        case reservedKeyword
    }

    /// Keywords a symbol takes in backquotes.
    static let escapedKeywords: Set<String> = [
        "_", "Any", "Self", "as", "associatedtype", "await", "borrowing", "break", "case", "catch",
        "class", "consuming", "continue", "default", "defer", "deinit", "do", "else", "enum",
        "extension", "fallthrough", "false", "fileprivate", "for", "func", "guard", "if", "import",
        "in", "init", "inout", "internal", "is", "let", "nil", "nonisolated", "open", "operator",
        "precedencegroup", "private", "protocol", "public", "repeat", "rethrows", "return", "static",
        "struct", "subscript", "super", "switch", "throw", "throws", "true", "try", "typealias", "var",
        "where", "while",
    ]

    /// Names no symbol can have, even in backquotes.
    static let reservedKeywords: Set<String> = ["self", "Type", "Protocol"]

    /// A static member's name: words in lower camel case.
    static func member(_ text: String) -> Result<String, Failure> {
        derive(text, isType: false)
    }

    /// A namespace's name: words in upper camel case.
    static func type(_ text: String) -> Result<String, Failure> {
        derive(text, isType: true)
    }

    private static func derive(_ text: String, isType: Bool) -> Result<String, Failure> {
        if escapedKeywords.contains(text) {
            return .success("`\(text)`")
        }
        if reservedKeywords.contains(text) {
            return .failure(.reservedKeyword)
        }
        if text.isEmpty {
            return .failure(.empty)
        }
        let (prefix, words) = words(text)
        var name = prefix
        for (index, word) in words.enumerated() {
            if isType {
                name += word.prefix(1).uppercased() + word.dropFirst()
            } else if index == 0, prefix.isEmpty {
                name += lowercasingLeadingUppercase(word)
            } else if isUnchangedByUppercasing(word.first!) {
                name += word.prefix(1) + lowercasingLeadingUppercase(String(word.dropFirst()))
            } else if word.first!.isLowercase {
                name += word.prefix(1).uppercased() + word.dropFirst()
            } else {
                name += word
            }
        }
        if name.isEmpty {
            return .failure(.onlyInvalidCharacters)
        }
        if !isIdentifierHead(name.unicodeScalars.first!) {
            name = "_" + name
        }
        if escapedKeywords.contains(name) {
            return .success("`\(name)`")
        }
        if reservedKeywords.contains(name) {
            return .failure(.reservedKeyword)
        }
        return .success(name)
    }

    /// The words of `text`, and the separator kept before them. Format specifiers separate words
    /// (`count %lld items` is `count`, `items`), but for `%2$#@name@`, which leaves `2$`, and
    /// variables are numbered first. So do characters a Swift identifier cannot hold, `_` and
    /// U+200B; the first separator that is an identifier character, when it comes before any
    /// word, is kept as a prefix (`-_x` is `_`, `x`), after which every word is capitalized. An
    /// apostrophe (`'` or `’`) between two other characters is dropped (`don't` is one word), and a
    /// word ends after a character that is neither uppercase nor lowercase (`a1b` is `a1`, `b`).
    private static func words(_ text: String) -> (prefix: String, words: [String]) {
        var text = numberingVariables(text)
        for specifier in FormatSpecifier.all(in: text).reversed() where specifier.variable == nil || specifier.position == nil {
            text.replaceSubrange(specifier.range, with: " ")
        }
        let characters = Array(text)
        var prefix: String?
        var words: [String] = []
        var word = ""
        func isKept(_ index: Int) -> Bool {
            guard characters.indices.contains(index) else { return false }
            let character = characters[index]
            return !wordSeparators.contains(character) && !isApostrophe(character)
                && character.unicodeScalars.allSatisfy(isIdentifierCharacter)
        }
        for index in characters.indices {
            let character = characters[index]
            if isApostrophe(character), isKept(index - 1), isKept(index + 1) {
                continue
            }
            guard isKept(index) else {
                if wordSeparators.contains(character), prefix == nil, words.isEmpty, word.isEmpty {
                    prefix = String(character)
                }
                if !word.isEmpty {
                    words.append(word)
                    word = ""
                }
                continue
            }
            word.append(character)
            if !character.isUppercase, !character.isLowercase {
                words.append(word)
                word = ""
            }
        }
        if !word.isEmpty {
            words.append(word)
        }
        return (prefix ?? "", words)
    }

    /// `text` with each `%#@name@` given its argument number (`%@ %#@x@` is `%@ %2$#@x@`), unless
    /// a specifier written with that number has it (strings-experiments `symbols-key-specifiers`).
    private static func numberingVariables(_ text: String) -> String {
        let written = Set(FormatSpecifier.all(in: text).compactMap(\.position))
        var result = ""
        var index = text.startIndex
        for (argument, specifier) in FormatSpecifier.numbered(in: text) {
            result += text[index..<specifier.range.lowerBound]
            let numbered = specifier.variable != nil && specifier.position == nil && !written.contains(argument)
            result += numbered ? specifier.written(in: text, argument: argument) : String(text[specifier.range])
            index = specifier.range.upperBound
        }
        return result + text[index...]
    }

    /// Identifier characters that separate words (strings-experiments `symbols-separators`).
    private static let wordSeparators: Set<Character> = ["_", "\u{200B}"]

    private static func isApostrophe(_ character: Character) -> Bool {
        character == "'" || character == "\u{2019}"
    }

    /// `word` with its leading run of characters that uppercasing leaves unchanged lowercased:
    /// uppercase letters, and lowercase ones without an uppercase form (`ꜰZZa` is `ꜰzza`;
    /// strings-experiments `symbols-case`).
    private static func lowercasingLeadingUppercase(_ word: String) -> String {
        let run = word.prefix(while: isUnchangedByUppercasing)
        return run.lowercased() + word.dropFirst(run.count)
    }

    private static func isUnchangedByUppercasing(_ character: Character) -> Bool {
        character.uppercased() == String(character)
    }

    /// The Swift grammar's `identifier-head` (The Swift Programming Language, "Identifiers").
    static func isIdentifierHead(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        if scalar.isASCII {
            return scalar == "_" || ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
        }
        return identifierHeadRanges.contains { $0.contains(value) }
    }

    /// The grammar's `identifier-character`, and `$`, which Swift also accepts after the head.
    static func isIdentifierCharacter(_ scalar: Unicode.Scalar) -> Bool {
        if ("0"..."9").contains(scalar) || scalar == "$" {
            return true
        }
        let value = scalar.value
        return [0x0300...0x036F, 0x1DC0...0x1DFF, 0x20D0...0x20FF, 0xFE20...0xFE2F].contains { $0.contains(value) }
            || isIdentifierHead(scalar)
    }

    private static let identifierHeadRanges: [ClosedRange<UInt32>] = [
        0x00A8...0x00A8, 0x00AA...0x00AA, 0x00AD...0x00AD, 0x00AF...0x00AF, 0x00B2...0x00B5,
        0x00B7...0x00BA, 0x00BC...0x00BE, 0x00C0...0x00D6, 0x00D8...0x00F6, 0x00F8...0x00FF,
        0x0100...0x02FF, 0x0370...0x167F, 0x1681...0x180D, 0x180F...0x1DBF, 0x1E00...0x1FFF,
        0x200B...0x200D, 0x202A...0x202E, 0x203F...0x2040, 0x2054...0x2054, 0x2060...0x206F,
        0x2070...0x20CF, 0x2100...0x218F, 0x2460...0x24FF, 0x2776...0x2793, 0x2C00...0x2DFF,
        0x2E80...0x2FFF, 0x3004...0x3007, 0x3021...0x302F, 0x3031...0x303F, 0x3040...0xD7FF,
        0xF900...0xFD3D, 0xFD40...0xFDCF, 0xFDF0...0xFE1F, 0xFE30...0xFE44, 0xFE47...0xFFFD,
        0x10000...0x1FFFD, 0x20000...0x2FFFD, 0x30000...0x3FFFD, 0x40000...0x4FFFD,
        0x50000...0x5FFFD, 0x60000...0x6FFFD, 0x70000...0x7FFFD, 0x80000...0x8FFFD,
        0x90000...0x9FFFD, 0xA0000...0xAFFFD, 0xB0000...0xBFFFD, 0xC0000...0xCFFFD,
        0xD0000...0xDFFFD, 0xE0000...0xEFFFD,
    ]
}
