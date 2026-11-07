import NomacCore

/// A fetch request's `predicateString`, for the forms whose archive is observed
/// (coredata-experiments `predicates`): comparisons of a key path with an integer, a string, a
/// variable or `max:(keyPath)`, joined by `AND`. Anything else is refused with BACKLOG B-257.
indirect enum PredicateSyntax: Sendable {
    case comparison(keyPath: String, comparison: Comparison, value: Value)
    case and([PredicateSyntax])

    /// `NSPredicateOperatorType`.
    enum Comparison: Int, Sendable {
        case lessThan = 0, lessThanOrEqual = 1, greaterThan = 2, greaterThanOrEqual = 3, equal = 4, notEqual = 5
    }

    enum Value: Sendable {
        case integer(Int)
        case string(String)
        case variable(String)
        case maximum(keyPath: String)
    }

    init(_ text: String) throws {
        func refuse() -> NomacError {
            NomacError("the predicate \"\(text)\" has a form whose archive is not observed yet (BACKLOG B-257)")
        }
        var parts: [PredicateSyntax] = []
        for clause in try Self.clauses(text, refuse) {
            guard clause.count == 3, Self.isKeyPath(clause[0]), let comparison = Self.comparison(clause[1]), let value = Self.value(clause[2]) else {
                throw refuse()
            }
            parts.append(.comparison(keyPath: clause[0], comparison: comparison, value: value))
        }
        guard let first = parts.first else { throw refuse() }
        self = parts.count == 1 ? first : .and(parts)
    }

    /// The tokens of each clause between `AND`s, quoted strings kept with their quotes.
    private static func clauses(_ text: String, _ refuse: () -> NomacError) throws -> [[String]] {
        var clauses: [[String]] = [[]]
        var token = ""
        var quoted = false
        func finish() {
            guard !token.isEmpty else { return }
            if token == "AND" { clauses.append([]) } else { clauses[clauses.count - 1].append(token) }
            token = ""
        }
        for character in text {
            if character == "\\" { throw refuse() }
            if character == "\"" { quoted.toggle() }
            if character == " ", !quoted { finish() } else { token.append(character) }
        }
        guard !quoted else { throw refuse() }
        finish()
        return clauses
    }

    private static func isKeyPath(_ token: String) -> Bool {
        guard let first = token.first, first.isLetter || first == "_", !["nil", "NIL", "NULL", "SELF", "TRUE", "FALSE", "YES", "NO", "IN", "OR", "NOT"].contains(token) else { return false }
        return token.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == ".") } && !token.hasSuffix(".") && !token.contains("..")
    }

    private static func comparison(_ token: String) -> Comparison? {
        switch token {
        case "==", "=": .equal
        case "!=", "<>": .notEqual
        case "<": .lessThan
        case "<=", "=<": .lessThanOrEqual
        case ">": .greaterThan
        case ">=", "=>": .greaterThanOrEqual
        default: nil
        }
    }

    private static func value(_ token: String) -> Value? {
        if token.count >= 2, token.hasPrefix("\""), token.hasSuffix("\"") {
            return .string(String(token.dropFirst().dropLast()))
        }
        if let integer = Int(token), !token.hasPrefix("+") {
            return .integer(integer)
        }
        if token.hasPrefix("$"), isKeyPath(String(token.dropFirst())), !token.contains(".") {
            return .variable(String(token.dropFirst()))
        }
        if token.hasPrefix("max:("), token.hasSuffix(")"), isKeyPath(String(token.dropFirst(5).dropLast())) {
            return .maximum(keyPath: String(token.dropFirst(5).dropLast()))
        }
        return nil
    }
}
