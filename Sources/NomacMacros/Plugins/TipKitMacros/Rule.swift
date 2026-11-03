internal import SwiftDiagnostics
import SwiftOperators
import SwiftSyntax
internal import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `#Rule` (TipKit): a `Tips.Rule` of each input and the closure's body as a predicate
/// (docs/formats/macros.md "TipKit"). With one input the closure is translated as
/// swift-foundation 6.3's `#Predicate` translates it (`PredicateMacro.swift` here), on a detached
/// copy, so its errors have no source position, as Xcode's. With several, the body is split at
/// `&&` and `||` into one rule per operand, matched to the inputs in order and combined with
/// `.conjunction` or `.disjunction`.
public struct RuleMacro: SwiftSyntaxMacros.ExpressionMacro {
    public static var formatMode: FormatMode { .disabled }

    public static func expansion(of node: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) throws -> ExprSyntax {
        guard let closure = node.trailingClosure else { throw unobserved(node) }
        if let filter = closure.filterCall {
            throw DiagnosticsError(diagnostics: [Diagnostic(node: filter, message: TipKitDiagnostic("The filter function is not supported in this rule."))])
        }
        let inputs = node.arguments.map(\.expression.trimmedDescription)
        if inputs.count == 1 {
            return "Tips.Rule(\(raw: inputs[0])) \(raw: try translated(closure, in: context))"
        }
        // Parsed again as a closure of the body alone: Xcode's positions in the body are one
        // column further right on its first line only (`tipkit-rule-errors`).
        let parsed = OperatorTable.standardOperators.foldAll(ExprSyntax(stringLiteral: "{" + closure.statements.description + "}")) { _ in }
        guard let body = parsed.as(ClosureExprSyntax.self)?.statements.first?.item.as(ExprSyntax.self) else { throw unobserved(node) }
        guard let infix = body.as(InfixOperatorExprSyntax.self), let op = infix.operator.as(BinaryOperatorExprSyntax.self) else {
            return "\(raw: body.trimmedDescription)"
        }
        guard Part.kinds[op.operator.text] != nil else {
            throw DiagnosticsError(diagnostics: [Diagnostic(node: op, message: TipKitDiagnostic("'\(op.description)' operator is not supported in this rule"))])
        }
        let part = Part(body)
        var leaves = part.leaves.makeIterator()
        var rules: [ExprSyntax: String] = [:]
        for input in inputs.indices {
            guard let leaf = leaves.next() else { break }
            rules[leaf] = "Tips.Rule(\(inputs[input])) " + (try translated(subclosure(of: closure, input: input, body: leaf), in: context))
        }
        if let extra = leaves.next() {
            let inner = DiagnosticsError(diagnostics: [Diagnostic(node: extra, message: TipKitDiagnostic("unable to expand input for \(extra.description)"))])
            throw DiagnosticsError(diagnostics: [Diagnostic(node: body, message: TipKitDiagnostic("failed to expand compound rule: \(inner)"))])
        }
        return "\(raw: part.text(rules))"
    }

    /// A rule without a trailing closure, which the compiler refuses before expanding it, or a
    /// compound rule whose body is not one expression: forms no experiment shows (B-156).
    private static func unobserved(_ node: some FreestandingMacroExpansionSyntax) -> DiagnosticsError {
        DiagnosticsError(diagnostics: [Diagnostic(node: node, message: TipKitDiagnostic("nomac does not know how Xcode expands this form of #Rule"))])
    }

    /// The closure as `#Predicate`'s translation writes it.
    private static func translated(_ closure: ClosureExprSyntax, in context: some MacroExpansionContext) throws -> String {
        let predicate = MacroExpansionExprSyntax(macroName: .identifier("Predicate"), arguments: [], trailingClosure: closure.detached)
        let expansion = try PredicateMacro.expansion(of: predicate, in: context)
        return expansion.as(FunctionCallExprSyntax.self)?.arguments.first?.expression.description ?? expansion.description
    }

    /// The closure of one operand, its operators folded as the compiler folds a macro's
    /// arguments: the input's parameter, `(name) in`, or `$0` for the input's shorthand argument.
    private static func subclosure(of closure: ClosureExprSyntax, input: Int, body: ExprSyntax) -> ClosureExprSyntax {
        let names = closure.signature?.parameterClause?.as(ClosureShorthandParameterListSyntax.self)?.map(\.name.text)
            ?? closure.signature?.parameterClause?.as(ClosureParameterClauseSyntax.self)?.parameters.map(\.firstName.text)
        let text: String
        if let names, input < names.count {
            text = "{ (\(names[input])) in \(body.trimmedDescription) }"
        } else {
            text = "{ \(ShorthandRenamer(index: input).rewrite(body.trimmed).description) }"
        }
        return OperatorTable.standardOperators.foldAll(ExprSyntax(stringLiteral: text)) { _ in }.cast(ClosureExprSyntax.self)
    }
}

/// A compound rule's body split at `&&` and `||`, a chain of one operator kept as one rule.
private indirect enum Part {
    case leaf(ExprSyntax)
    case compound(String, [Part])

    static let kinds = ["&&": "conjunction", "||": "disjunction"]

    init(_ expression: ExprSyntax) {
        var inner = expression
        while let tuple = inner.as(TupleExprSyntax.self), tuple.elements.count == 1, let element = tuple.elements.first, element.label == nil {
            inner = element.expression
        }
        guard let infix = inner.as(InfixOperatorExprSyntax.self), let op = infix.operator.as(BinaryOperatorExprSyntax.self),
              let kind = Self.kinds[op.operator.text] else {
            self = .leaf(expression)
            return
        }
        func operands(_ side: ExprSyntax) -> [Part] {
            if let chained = side.as(InfixOperatorExprSyntax.self), chained.operator.as(BinaryOperatorExprSyntax.self)?.operator.text == op.operator.text {
                return operands(chained.leftOperand) + operands(chained.rightOperand)
            }
            return [Part(side)]
        }
        self = .compound(kind, operands(infix.leftOperand) + operands(infix.rightOperand))
    }

    var leaves: [ExprSyntax] {
        switch self {
        case .leaf(let expression): [expression]
        case .compound(_, let parts): parts.flatMap(\.leaves)
        }
    }

    func text(_ rules: [ExprSyntax: String]) -> String {
        switch self {
        case .leaf(let expression):
            return rules[expression] ?? expression.trimmedDescription
        case .compound(let kind, let parts):
            let items = parts.map { $0.text(rules).split(separator: "\n", omittingEmptySubsequences: false).map { "        " + $0 }.joined(separator: "\n") }
            return "Tips.Rule(.\(kind), [\n" + items.joined(separator: ",\n") + "\n    ])"
        }
    }
}

/// An operand's own shorthand argument as `$0`.
private final class ShorthandRenamer: SyntaxRewriter {
    let name: String

    init(index: Int) {
        name = "$\(index)"
    }

    override func visit(_ token: TokenSyntax) -> TokenSyntax {
        guard case .dollarIdentifier(let text) = token.tokenKind, text == name else { return token }
        return token.with(\.tokenKind, .dollarIdentifier("$0"))
    }
}

private extension ClosureExprSyntax {
    /// The name of the first `.filter` call in the closure, which `#Rule` refuses.
    var filterCall: TokenSyntax? {
        final class Finder: SyntaxVisitor {
            var found: TokenSyntax?

            override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
                if found == nil, let member = node.calledExpression.as(MemberAccessExprSyntax.self), member.declName.baseName.text == "filter" {
                    found = member.declName.baseName
                }
                return .visitChildren
            }
        }
        let finder = Finder(viewMode: .sourceAccurate)
        finder.walk(self)
        return finder.found
    }
}
