import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@UnionValue` (AppIntents): an enum whose cases each hold one value is an intent value of any
/// of their types, resolved by one resolver per case (docs/formats/macros.md "AppIntents").
public struct _UnionValueMacro: ExtensionMacro {
    public static var formatMode: FormatMode { .disabled }

    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        guard let enumeration = declaration.as(EnumDeclSyntax.self) else { return [] }
        let elements = enumeration.memberBlock.members.compactMap { $0.decl.as(EnumCaseDeclSyntax.self) }.flatMap(\.elements)
        let cases = elements.compactMap { element -> (name: String, type: String)? in
            guard let parameters = element.parameterClause?.parameters, parameters.count == 1, let parameter = parameters.first else { return nil }
            return (element.name.text, parameter.type.trimmedDescription)
        }
        guard cases.count == elements.count else {
            throw DiagnosticsError(diagnostics: [Diagnostic(node: node, message: AppIntentsDiagnostic.unionCases, highlights: [Syntax(node)])])
        }
        let name = type.trimmedDescription
        let access = declaration.modifiers.contains { $0.name.tokenKind == .keyword(.public) } ? "public " : ""
        let availability = AvailabilityAttributes(declaration).text.map { $0 + "\n" } ?? ""
        let resolvers = cases.map { item in
            """
                struct \(item.type)Resolver: AppIntents.Resolver {
                    func resolve(from input: \(item.type), context: IntentParameterContext<\(name)>) async throws -> \(name)? {
                        .\(item.name)(input)
                    }
                }
            """
        }
        let representable = """
            \(availability)nonisolated extension \(name): _IntentValueRepresentable {
                \(access)static var allIntentValueTypes: [any _IntentValue.Type] {
                    [\(cases.map { $0.type + ".self" }.joined(separator: ", "))]
                }
                \(access)var asIntentValue: any _IntentValue {
                    switch self {
            \(cases.map { "        case let .\($0.name)(_1):\n            return _1\n" }.joined())        }
                }
                @ResolverSpecificationBuilder<Self> \(access)static var defaultResolverSpecification: some ResolverSpecification {
            \(cases.map { "        \($0.type)Resolver()\n" }.joined())    }
            \(resolvers.joined(separator: "\n"))
            }
            """
        let union = """
            @available(macOS 27.0, *) @available(iOS 27.0, *) @available(watchOS 27.0, *) @available(tvOS 27.0, *) @available(visionOS 27.0, *) nonisolated extension \(name): AppUnionValue {
                \(access)typealias Cases = \(enumeration.name.text)Cases
                \(access)enum \(enumeration.name.text)Cases: String, AppUnionValueCasesProviding {
                    \(access)typealias UnionValue = \(name)
            \(cases.map { "        case `\($0.name)`\n" }.joined())    }
            }
            """
        return [representable, union].map { DeclSyntax(stringLiteral: $0).cast(ExtensionDeclSyntax.self) }
    }
}
