import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `#Preview` with a SwiftUI view (SwiftUI's `Preview(_:traits:body:)`).
public struct SwiftUIView: DeclarationMacro {
    public static var propagateFreestandingMacroAttributes: Bool { false }
    public static var propagateFreestandingMacroModifiers: Bool { false }

    public static func expansion(of node: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        try PreviewRegistry.expansion(of: node, in: context) { closure in
            let previewables = closure.statements.prefix { Previewable.isPreviewable($0) }
            if let misplaced = closure.statements.dropFirst(previewables.count).first(where: { Previewable.isPreviewable($0) }) {
                throw DiagnosticsError(diagnostics: [Previewable.orderDiagnostic(closure, misplaced: misplaced)])
            }
            guard !previewables.isEmpty else {
                return ExprSyntax("""
                    {
                        func __b_buildView(@SwiftUI.ViewBuilder body: () -> any SwiftUI.View) -> any SwiftUI.View {
                            body()
                        }
                        \(StmtSyntax("return __b_buildView \(closure.trimmed)"))
                    }
                    """).cast(ClosureExprSyntax.self)
            }
            let properties = previewables.map { Previewable.property($0) }.joined(separator: "\n\n        ")
            var statements = CodeBlockItemListSyntax(closure.statements.dropFirst(previewables.count))
            if let first = statements.first?.firstToken(viewMode: .sourceAccurate) {
                statements = statements.with(\.leadingTrivia, Trivia(pieces: first.leadingTrivia.drop(while: \.isNewline)))
            }
            return ExprSyntax("""
                {
                    struct __P_Previewable_Transform_Wrapper: SwiftUI.View {
                        \(raw: properties)

                        var body: some SwiftUI.View {
                        \(statements)
                        }
                    }
                    return __P_Previewable_Transform_Wrapper()
                }
                """).cast(ClosureExprSyntax.self)
        }
    }
}

/// `#Preview` with a UIKit or AppKit view or view controller.
public struct KitViewMacro: DeclarationMacro {
    public static var propagateFreestandingMacroAttributes: Bool { false }
    public static var propagateFreestandingMacroModifiers: Bool { false }

    public static func expansion(of node: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        try PreviewRegistry.expansion(of: node, in: context) { closure in
            ExprSyntax("""
                {
                    @resultBuilder struct __B_Builder<Content> {
                        static func buildBlock(_ content: Content) -> Content { content }
                    }
                    func __b_buildContent<Content>(@__B_Builder<Content> build: () -> Content) -> Content {
                        build()
                    }
                    \(StmtSyntax("return __b_buildContent \(closure.trimmed)"))
                }
                """).cast(ClosureExprSyntax.self)
        }
    }
}

/// `#Preview` with `arguments:`, whose closure takes each argument (SwiftUI).
public struct SwiftUIViewGroup_1: DeclarationMacro {
    public static var propagateFreestandingMacroAttributes: Bool { false }
    public static var propagateFreestandingMacroModifiers: Bool { false }

    public static func expansion(of node: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        try PreviewRegistry.expansion(of: node, in: context) { $0 }
    }
}

/// `#Preview` with `arguments:` (UIKit and AppKit).
public struct PreviewCommonGroup: DeclarationMacro {
    public static var propagateFreestandingMacroAttributes: Bool { false }
    public static var propagateFreestandingMacroModifiers: Bool { false }

    public static func expansion(of node: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        try PreviewRegistry.expansion(of: node, in: context) { $0 }
    }
}

/// WidgetKit's `#Preview`s (widgets with timelines, timeline providers, relevances, Live Activities).
public struct Common: DeclarationMacro {
    public static var propagateFreestandingMacroAttributes: Bool { false }
    public static var propagateFreestandingMacroModifiers: Bool { false }

    public static func expansion(of node: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        try PreviewRegistry.expansion(of: node, in: context) { $0 }
    }
}

/// `@Previewable`: the leading declarations of a SwiftUI `#Preview`'s closure, which `SwiftUIView`
/// turns into properties of a view; anywhere else it is an error.
public struct Previewable: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        throw DiagnosticsError(diagnostics: [Diagnostic(node: node, message: PreviewDiagnostic.previewableOutside, highlights: [Syntax(node)])])
    }

    static func isPreviewable(_ item: CodeBlockItemSyntax) -> Bool {
        guard case .decl(let declaration) = item.item, let variable = declaration.as(VariableDeclSyntax.self) else { return false }
        return variable.attributes.contains { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "Previewable" }
    }

    /// The declaration without its `@Previewable` attribute, its comments and the indentation of
    /// its line, with the template's indentation (8 spaces) on its other lines.
    static func property(_ item: CodeBlockItemSyntax) -> String {
        var variable = item.item.cast(VariableDeclSyntax.self)
        let indentation = variable.leadingTrivia.pieces.reversed().prefix { $0.isSpaceOrTab }.reversed().map { Trivia(pieces: [$0]).description }.joined()
        variable.attributes = variable.attributes.filter { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription != "Previewable" }
        return variable.trimmedDescription.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map { index, line in
            guard index > 0 else { return String(line) }
            return "        " + (line.hasPrefix(indentation) ? String(line.dropFirst(indentation.count)) : String(line))
        }.joined(separator: "\n")
    }

    static func orderDiagnostic(_ closure: ClosureExprSyntax, misplaced: CodeBlockItemSyntax) -> Diagnostic {
        let previewables = closure.statements.filter(isPreviewable)
        let others = closure.statements.filter { !isPreviewable($0) }
        let reordered = CodeBlockItemListSyntax(Array(previewables) + Array(others))
        return Diagnostic(node: misplaced, message: PreviewDiagnostic.previewableOrder, highlights: [],
                          fixIt: FixIt(message: PreviewFixIt.movePreviewable, changes: [.replace(oldNode: Syntax(closure.statements), newNode: Syntax(reordered))]))
    }
}
