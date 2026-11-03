internal import SwiftDiagnostics
import SwiftSyntax
internal import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@Parameter` (TipKit): a tip's property read and written through a `Tips.Parameter` the macro
/// declares next to it, keyed by the property's name, `+` for a static property and `-` for an
/// instance one (docs/formats/macros.md "TipKit"). The name keeps its trailing trivia, as
/// written before the colon.
public struct ParameterMacro: AccessorMacro, PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingAccessorsOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [AccessorDeclSyntax] {
        guard let parameter = try Parameter(node, declaration) else { return [] }
        let storage = "$" + parameter.name
        return [
            """
            get {
                \(raw: storage).wrappedValue
            }
            """,
            """
            set {
                \(raw: storage).wrappedValue = newValue
            }
            """,
        ]
    }

    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let parameter = try Parameter(node, declaration) else { return [] }
        let modifiers = parameter.modifiers.map { $0 + " " }.joined() + (parameter.isStatic ? "static nonisolated(unsafe) " : "")
        let options = (node.arguments?.as(LabeledExprListSyntax.self) ?? []).map { ", " + $0.expression.trimmedDescription }.joined()
        let key = (parameter.isStatic ? "+" : "-") + parameter.name
        return ["\(raw: modifiers)var $\(raw: parameter.name): Tips.Parameter<\(raw: parameter.type)> = Tips.Parameter(Self.self, \(literal: key), \(raw: parameter.value)\(raw: options))"]
    }
}

/// The parts of a variable `@Parameter` expands.
private struct Parameter {
    var name: String
    var type: String
    var value: String
    var modifiers: [String]
    var isStatic: Bool

    /// Throws Xcode's error for a constant, and for a variable without a type, a value or with
    /// accessors (`tipkit-errors`); nil for any other declaration.
    init?(_ node: AttributeSyntax, _ declaration: some DeclSyntaxProtocol) throws {
        guard let variable = declaration.as(VariableDeclSyntax.self) else { return nil }
        guard variable.bindingSpecifier.tokenKind == .keyword(.var) else {
            throw DiagnosticsError(diagnostics: [Diagnostic(node: node, message: TipKitDiagnostic("Unable to expand \(variable.description) using @Parameter."))])
        }
        guard let binding = variable.bindings.first, let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
              let type = binding.typeAnnotation?.type, let value = binding.initializer?.value, binding.accessorBlock == nil else {
            throw DiagnosticsError(diagnostics: [Diagnostic(node: node, message: TipKitDiagnostic("Unable to expand due to missing identifier pattern."))])
        }
        self.name = pattern.description
        self.type = type.trimmedDescription
        self.value = value.trimmedDescription
        self.isStatic = variable.modifiers.contains { $0.name.tokenKind == .keyword(.static) }
        self.modifiers = variable.modifiers.filter { $0.name.tokenKind != .keyword(.static) }.map(\.trimmedDescription)
    }
}

struct TipKitDiagnostic: DiagnosticMessage {
    let message: String
    var diagnosticID: MessageID { MessageID(domain: "TipKitMacros", id: message) }
    var severity: DiagnosticSeverity { .error }

    init(_ message: String) {
        self.message = message
    }
}
