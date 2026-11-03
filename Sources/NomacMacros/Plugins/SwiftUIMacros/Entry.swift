import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@Entry` (SwiftUI): a property of `EnvironmentValues`, `Transaction`, `ContainerValues` or
/// `FocusedValues` reads and writes a key the macro declares next to it (docs/formats/macros.md
/// "SwiftUI entries"). Its expansions are not formatted: the value keeps its spelling (`0..<1`).
public struct EntryMacro: AccessorMacro, PeerMacro {
    public static var formatMode: FormatMode { .disabled }

    /// The key protocol of each container the macro accepts.
    static let keys = [
        "EnvironmentValues": "SwiftUICore.EnvironmentKey",
        "Transaction": "SwiftUICore.TransactionKey",
        "ContainerValues": "SwiftUICore.ContainerValueKey",
        "FocusedValues": "SwiftUI.FocusedValueKey",
    ]

    public static func expansion(of node: AttributeSyntax, providingAccessorsOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [AccessorDeclSyntax] {
        guard let variable = declaration.as(VariableDeclSyntax.self) else { return [] }
        if let diagnostic = specifierDiagnostic(variable) {
            context.diagnose(diagnostic)
            return []
        }
        if let modifier = variable.modifiers.first(where: { $0.name.tokenKind == .keyword(.static) }) {
            var withoutStatic = variable
            withoutStatic.modifiers = variable.modifiers.filter { $0.name.tokenKind != .keyword(.static) }
            context.diagnose(Diagnostic(node: modifier, message: EntryDiagnostic.staticMember,
                                        fixIt: FixIt(message: EntryFixIt.removeStatic, changes: [.replace(oldNode: Syntax(variable), newNode: Syntax(withoutStatic))])))
            return []
        }
        guard let name = variable.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { return [] }
        let key = "self[__Key_\(name).self]"
        // Not formatted, so indented here as Xcode's are within the braces swift-syntax adds.
        return [
            """
                get {
                    \(raw: key)
                }
            """,
            """
                set {
                    \(raw: key) = newValue
                }
            """,
            """
                _modify {
                    yield &\(raw: key)
                }
            """,
        ]
    }

    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let container = context.lexicalContext.first?.as(ExtensionDeclSyntax.self)?.extendedType.trimmedDescription.split(separator: ".").last,
              let key = keys[String(container)] else {
            context.diagnose(Diagnostic(node: declaration, message: EntryDiagnostic.container))
            return []
        }
        guard let variable = declaration.as(VariableDeclSyntax.self), let binding = variable.bindings.first,
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { return [] }
        if let diagnostic = specifierDiagnostic(variable) {
            context.diagnose(diagnostic)
            return []
        }
        let type = binding.typeAnnotation?.type
        let optional = type?.as(OptionalTypeSyntax.self)
        if container == "FocusedValues" {
            guard let type else {
                let annotation = TypeAnnotationSyntax(colon: .colonToken(trailingTrivia: .space), type: TypeSyntax("<#Type#>").with(\.trailingTrivia, .space))
                context.diagnose(Diagnostic(node: binding, message: EntryDiagnostic.missingType,
                                            fixIt: FixIt(message: EntryFixIt.addType, changes: [.replace(oldNode: Syntax(binding), newNode: Syntax(binding.with(\.typeAnnotation, annotation)))])))
                return []
            }
            guard let optional else {
                context.diagnose(Diagnostic(node: type, message: EntryDiagnostic.focusedOptional,
                                            fixIt: FixIt(message: EntryFixIt.optional, changes: [.replace(oldNode: Syntax(type), newNode: Syntax(OptionalTypeSyntax(wrappedType: type)))])))
                return []
            }
            if let value = binding.initializer?.value, !value.is(NilLiteralExprSyntax.self) {
                context.diagnose(Diagnostic(node: value, message: EntryDiagnostic.focusedNil, fixIts: [
                    FixIt(message: EntryFixIt.removeValue, changes: [.replace(oldNode: Syntax(binding), newNode: Syntax(binding.with(\.initializer, nil)))]),
                    FixIt(message: EntryFixIt.nilValue, changes: [.replace(oldNode: Syntax(value), newNode: Syntax(NilLiteralExprSyntax()))]),
                ]))
            }
            return ["""
                private struct __Key_\(raw: name): \(raw: key) {
                    typealias Value = \(optional.wrappedType.trimmed)
                }
                """]
        }
        let written = binding.initializer?.value
        let value: ExprSyntax
        if let written {
            value = written.trimmed
        } else if optional != nil {
            value = "nil"
        } else {
            let placeholder = InitializerClauseSyntax(equal: .equalToken(leadingTrivia: .space, trailingTrivia: .space),
                                                      value: ExprSyntax("<#T##default value##\(raw: type?.trimmedDescription ?? "")#>"))
            context.diagnose(Diagnostic(node: binding, message: EntryDiagnostic.missingValue,
                                        fixIt: FixIt(message: EntryFixIt.provideValue, changes: [.replace(oldNode: Syntax(binding), newNode: Syntax(binding.with(\.initializer, placeholder)))])))
            return []
        }
        if isClosure(type) || value.is(ClosureExprSyntax.self) {
            context.diagnose(Diagnostic(node: Syntax(type) ?? Syntax(written!), message: EntryDiagnostic.closure(name)))
        }
        let annotation = type.map { ": \($0.trimmedDescription)" } ?? ""
        guard value.is(FunctionCallExprSyntax.self) else {
            return ["""
                private struct __Key_\(raw: name): \(raw: key) {
                    @SwiftUICore.__EntryDefaultValue
                    static var defaultValue\(raw: annotation) = \(value)
                }
                """]
        }
        let location = context.location(of: variable.bindingSpecifier, at: .afterLeadingTrivia, filePathMode: .fileID)!
        return ["""
            private struct __Key_\(raw: name): \(raw: key) {
                @SwiftUICore.__EntryDefaultValue
                static var defaultValue\(raw: annotation) = \(value)
                #sourceLocation(file: \(location.file), line: \(location.line))
                private static let _typeCheck: Void = #_SwiftUIEntryTypeCheck(Value.self, macroName: "Entry", propertyName: \(literal: name))
                #sourceLocation()
            }
            """]
    }

    private static func specifierDiagnostic(_ variable: VariableDeclSyntax) -> Diagnostic? {
        guard variable.bindingSpecifier.tokenKind == .keyword(.let) else { return nil }
        return Diagnostic(node: variable, message: EntryDiagnostic.letDeclaration,
                          fixIt: FixIt(message: EntryFixIt.var, changes: [.replace(oldNode: Syntax(variable.bindingSpecifier), newNode: Syntax(TokenSyntax.keyword(.var)))]))
    }

    /// Whether a type is a function type, written alone, in parentheses or optional.
    private static func isClosure(_ type: TypeSyntax?) -> Bool {
        guard let type else { return false }
        if type.is(FunctionTypeSyntax.self) { return true }
        if let optional = type.as(OptionalTypeSyntax.self) { return isClosure(optional.wrappedType) }
        if let tuple = type.as(TupleTypeSyntax.self), tuple.elements.count == 1 { return isClosure(tuple.elements.first?.type) }
        if let attributed = type.as(AttributedTypeSyntax.self) { return isClosure(attributed.baseType) }
        return false
    }
}

/// `@__EntryDefaultValue` on a key's `defaultValue`: a getter that returns the value written.
public struct EntryDefaultValueMacro: AccessorMacro {
    public static func expansion(of node: AttributeSyntax, providingAccessorsOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [AccessorDeclSyntax] {
        guard let value = declaration.as(VariableDeclSyntax.self)?.bindings.first?.initializer?.value else { return [] }
        return ["""
            get {
                \(value.trimmed)
            }
            """]
    }
}

/// `#_SwiftUIEntryTypeCheck` for a value type: nothing to check.
public struct EntryTypeCheckMacro: ExpressionMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) throws -> ExprSyntax {
        "()"
    }
}

/// `#_SwiftUIEntryTypeCheck` for a class: warns that the default value is made on every access.
public struct EntryTypeCheckClassMacro: ExpressionMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) throws -> ExprSyntax {
        let argument = { (label: String) in
            node.arguments.first(where: { $0.label?.text == label })?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue ?? ""
        }
        context.diagnose(Diagnostic(node: node, message: EntryDiagnostic.classType(macro: argument("macroName"), property: argument("propertyName"))))
        return "()"
    }
}

enum EntryDiagnostic: DiagnosticMessage {
    case container
    case letDeclaration
    case staticMember
    case missingValue
    case missingType
    case focusedOptional
    case focusedNil
    case closure(String)
    case classType(macro: String, property: String)

    var message: String {
        switch self {
        case .container: "'@Entry' macro can only attach to var declarations inside extensions of EnvironmentValues, ContainerValues, Transaction, or FocusedValues"
        case .letDeclaration: "'@Entry' can only be applied to a 'var' declaration"
        case .staticMember: "'@Entry' cannot be applied to a static member"
        case .missingValue: "Property missing a default value"
        case .missingType: "Property missing a type annotation"
        case .focusedOptional: "custom 'FocusedValues' entry must be Optional"
        case .focusedNil: "default value for custom 'FocusedValues' entry must be 'nil'"
        case .closure(let name): "Storing a closure in '@Entry var \(name)' may invalidate dependents on every update because closures may not be comparable."
        case .classType(let macro, let property):
            "Storing a class type in '@\(macro) var \(property)' may invalidate dependents on every update because the default value is reallocated on every access. Initialize the default value elsewhere and reference it from the '@\(macro)' declaration."
        }
    }

    var diagnosticID: MessageID { MessageID(domain: "SwiftUIMacros", id: "\(self)") }

    var severity: DiagnosticSeverity {
        switch self {
        case .closure, .classType: .warning
        default: .error
        }
    }
}

enum EntryFixIt: FixItMessage {
    case `var`
    case removeStatic
    case provideValue
    case addType
    case optional
    case removeValue
    case nilValue

    var message: String {
        switch self {
        case .var: "Replace 'let' with 'var'"
        case .removeStatic: "Remove 'static'"
        case .provideValue: "Provide default value"
        case .addType: "Add type annotation"
        case .optional: "Change type to be Optional"
        case .removeValue: "Remove default value"
        case .nilValue: "Change default value to 'nil'"
        }
    }

    var fixItID: MessageID { MessageID(domain: "SwiftUIMacros", id: "\(self)") }
}
