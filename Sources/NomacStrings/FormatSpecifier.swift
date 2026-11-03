/// A `printf`-style specifier in a localized string, as the string catalog compiler reads them
/// to build plural rules (docs/formats/strings.md "Values" and "Format specifiers").
struct FormatSpecifier: Equatable {
    /// The specifier's characters in the string, `%` included.
    var range: Range<String.Index>
    /// The explicit argument number (`%2$lld`), if any.
    var position: Int?
    /// The argument name of `%(name)lld` or `%1$(name)lld`, which compiled strings leave out.
    var name: Range<String.Index>?
    /// The length modifier and conversion (`lld`, `d`, `@`), or `#@name@` for a variable.
    var type: String

    /// The specifiers `xcstringstool` recognizes (strings-experiments, the specifier grammar
    /// probe in docs/formats/strings.md): integer conversions with `hh`, `h`, `l`, `ll`, `q`,
    /// `j`, `t` or `z`, floating-point ones with `l` or `L`, and the others with no length.
    static let integerConversions: Set<Character> = ["d", "i", "o", "u", "x", "X", "D", "O", "U"]
    static let floatConversions: Set<Character> = ["e", "E", "f", "F", "g", "G", "a", "A"]
    static let otherConversions: Set<Character> = ["@", "c", "C", "s", "S", "p"]
    static let integerLengths = ["hh", "ll", "h", "l", "q", "j", "t", "z"]
    static let floatLengths = ["l", "L"]
    /// Only these flags; ` `, `#` and `'` end a specifier, as do `*` widths and precisions.
    static let flags: Set<Character> = ["-", "+", "0"]

    /// Whether the specifier formats a number, the argument a plural rule chooses by.
    var isNumeric: Bool {
        guard let conversion = type.last, !type.hasPrefix("#@") else { return false }
        return Self.integerConversions.contains(conversion) || Self.floatConversions.contains(conversion)
    }

    /// The variable name of a `%#@name@` reference.
    var variable: String? {
        guard type.hasPrefix("#@"), type.count > 2 else { return nil }
        return String(type.dropFirst(2).dropLast())
    }

    /// Every specifier in `string`, in order; `%%` is not a specifier.
    static func all(in string: String) -> [FormatSpecifier] {
        var result: [FormatSpecifier] = []
        var index = string.startIndex
        while let percent = string[index...].firstIndex(of: "%") {
            let next = string.index(after: percent)
            guard next < string.endIndex else { break }
            if string[next] == "%" {
                index = string.index(after: next)
            } else if let specifier = parse(string, percent: percent) {
                result.append(specifier)
                index = specifier.range.upperBound
            } else {
                index = next
            }
        }
        return result
    }

    private static func parse(_ string: String, percent: String.Index) -> FormatSpecifier? {
        var cursor = string.index(after: percent)
        func skip(while predicate: (Character) -> Bool) {
            while cursor < string.endIndex, predicate(string[cursor]) {
                cursor = string.index(after: cursor)
            }
        }
        func isDigit(_ character: Character) -> Bool { character.isASCII && character.isNumber }

        var position: Int?
        let digitsStart = cursor
        skip(while: isDigit)
        if cursor > digitsStart, cursor < string.endIndex, string[cursor] == "$" {
            position = Int(string[digitsStart..<cursor])
            cursor = string.index(after: cursor)
        } else {
            cursor = digitsStart
        }
        var name: Range<String.Index>?
        if cursor < string.endIndex, string[cursor] == "(", let close = string[cursor...].firstIndex(of: ")") {
            name = cursor..<string.index(after: close)
            cursor = string.index(after: close)
        }
        if string[cursor...].hasPrefix("#@"), let close = string[string.index(cursor, offsetBy: 2)...].firstIndex(of: "@") {
            let end = string.index(after: close)
            return FormatSpecifier(range: percent..<end, position: position, name: name, type: String(string[cursor..<end]))
        }
        skip(while: flags.contains)
        skip(while: isDigit)
        if cursor < string.endIndex, string[cursor] == "." {
            cursor = string.index(after: cursor)
            skip(while: isDigit)
        }
        let typeStart = cursor
        let rest = string[cursor...]
        let length = (integerLengths + floatLengths).filter { rest.hasPrefix($0) }.max { $0.count < $1.count } ?? ""
        for candidate in [length, ""] {
            let conversionIndex = string.index(cursor, offsetBy: candidate.count)
            guard conversionIndex < string.endIndex else { continue }
            let conversion = string[conversionIndex]
            let valid = (integerConversions.contains(conversion) && (candidate.isEmpty || integerLengths.contains(candidate)))
                || (floatConversions.contains(conversion) && (candidate.isEmpty || floatLengths.contains(candidate)))
                || (otherConversions.contains(conversion) && candidate.isEmpty)
            if valid {
                let end = string.index(after: conversionIndex)
                return FormatSpecifier(range: percent..<end, position: position, name: name, type: String(string[typeStart..<end]))
            }
        }
        return nil
    }

    /// The specifiers of `string` paired with their argument numbers: explicit positions, or
    /// the next number for each specifier without one.
    static func numbered(in string: String) -> [(argument: Int, specifier: FormatSpecifier)] {
        var next = 1
        return all(in: string).map { specifier in
            if let position = specifier.position {
                return (position, specifier)
            }
            defer { next += 1 }
            return (next, specifier)
        }
    }

    /// The specifier as compiled strings write it: without its argument name, and with
    /// `argument` as its explicit number when it has none.
    func written(in string: String, argument: Int? = nil) -> String {
        let afterPercent = string.index(after: range.lowerBound)
        let prefix = string[afterPercent..<(name?.lowerBound ?? afterPercent)]
        let rest = string[(name?.upperBound ?? afterPercent)..<range.upperBound]
        if let argument, position == nil {
            return "%\(argument)$" + rest
        }
        return "%" + prefix + rest
    }

    /// `string` as compiled strings write it: argument names left out (strings-experiments
    /// `named-arguments`), and, when `positional`, every specifier given its argument number.
    static func compiled(_ string: String, positional: Bool = false) -> String {
        var result = ""
        var index = string.startIndex
        for (argument, specifier) in numbered(in: string) {
            result += string[index..<specifier.range.lowerBound]
            result += specifier.written(in: string, argument: positional ? argument : nil)
            index = specifier.range.upperBound
        }
        return result + string[index...]
    }

    /// The length modifier and conversion of a substitution's `formatSpecifier` (`.1f` is `f`).
    static func valueType(of formatSpecifier: String) -> String {
        all(in: "%" + formatSpecifier).first?.type ?? formatSpecifier
    }
}
