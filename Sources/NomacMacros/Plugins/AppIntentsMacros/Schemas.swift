import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@AppEntity(schema:)`, `@AppIntent(schema:)` and `@AppEnum(schema:)` (AppIntents): the schema's
/// members marked `@Property` or `@Parameter`, and the conformances with the schema's name
/// (docs/formats/macros.md "AppIntents").
public struct AppEntityMacro: MemberAttributeMacro, ExtensionMacro {
    public static var formatMode: FormatMode { .disabled }

    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingAttributesFor member: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [AttributeSyntax] {
        SchemaMacro.entity.attributes(node, member)
    }

    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        SchemaMacro.entity.extensions(node, declaration, type, protocols, context)
    }
}

public struct AppIntentMacro: MemberAttributeMacro, ExtensionMacro {
    public static var formatMode: FormatMode { .disabled }

    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingAttributesFor member: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [AttributeSyntax] {
        SchemaMacro.intent.attributes(node, member)
    }

    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        SchemaMacro.intent.extensions(node, declaration, type, protocols, context)
    }
}

public struct AppEnumMacro: ExtensionMacro {
    public static var formatMode: FormatMode { .disabled }

    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        SchemaMacro.enumeration.extensions(node, declaration, type, protocols, context)
    }
}

private struct SchemaMacro {
    /// The protocol naming the schema, its static member, the kind's own protocol, the
    /// attribute of a schema's member and the members by schema.
    var assistant: String
    var member: String
    var conformance: String
    var attribute: String?
    var members: [String: [String: String]]

    static let entity = SchemaMacro(assistant: "AssistantSchemaEntity", member: "__appSchemaEntity", conformance: "AppEntity", attribute: "Property", members: entityMembers)
    static let intent = SchemaMacro(assistant: "AssistantSchemaIntent", member: "__appSchemaIntent", conformance: "AppIntent", attribute: "Parameter", members: intentMembers)
    static let enumeration = SchemaMacro(assistant: "AssistantSchemaEnum", member: "__appSchemaEnum", conformance: "AppEnum", attribute: nil, members: [:])

    /// Xcode's availability of the schema's extension for a type without `@available`.
    static let defaultAvailability = "@available(iOS 27.0, macOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)"

    /// The schema as its name is written, `.calendar.event` giving `calendar.event`.
    static func schema(_ node: AttributeSyntax) -> String? {
        node.arguments?.as(LabeledExprListSyntax.self)?.first { $0.label?.text == "schema" }.map {
            String($0.expression.trimmedDescription.drop { $0 == "." })
        }
    }

    /// An instance variable the schema has gets the kind's attribute, unless it has one.
    func attributes(_ node: AttributeSyntax, _ member: some DeclSyntaxProtocol) -> [AttributeSyntax] {
        guard let attribute, let schema = Self.schema(node), let names = members[schema],
              let variable = member.as(VariableDeclSyntax.self),
              !variable.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }),
              !variable.attributes.contains(where: { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == attribute }),
              let name = variable.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
              let text = names[name] else { return [] }
        return ["\(raw: text)"]
    }

    func extensions(_ node: AttributeSyntax, _ declaration: some DeclGroupSyntax, _ type: some TypeSyntaxProtocol, _ protocols: [TypeSyntax],
                    _ context: some MacroExpansionContext) -> [ExtensionDeclSyntax] {
        guard let schema = Self.schema(node) else { return [] }
        if attribute != nil, members[schema] == nil {
            context.diagnose(Diagnostic(node: node, message: AppIntentsDiagnostic.unknownSchema(schema)))
        }
        let names = Set(protocols.map(\.trimmedDescription))
        let availability = AvailabilityAttributes(declaration)
        let access = declaration.modifiers.contains { $0.name.tokenKind == .keyword(.public) } ? "public " : ""
        var extensions: [String] = []
        if names.contains(assistant) {
            extensions.append("""
                \(availability.text ?? Self.defaultAvailability)
                extension \(type.trimmedDescription): \(assistant) {
                    \(access)static let \(member) = "\(schema)"
                }
                """)
        }
        if names.contains(conformance) {
            extensions.append((availability.text.map { $0 + "\n" } ?? "") + "extension \(type.trimmedDescription): \(conformance) {\n}")
        }
        for extra in extraConformances[schema] ?? [] where names.contains(extra) {
            extensions.append("\(availability.text ?? Self.defaultAvailability)\nextension \(type.trimmedDescription): \(extra) {\n}")
        }
        return extensions.map { DeclSyntax(stringLiteral: $0).cast(ExtensionDeclSyntax.self) }
    }
}

/// The type's `@available` attributes as written, with the documentation before them (their
/// leading trivia), which the extensions repeat.
struct AvailabilityAttributes {
    var text: String?

    init(_ declaration: some DeclGroupSyntax) {
        let attributes = declaration.attributes.compactMap { $0.as(AttributeSyntax.self) }.filter { $0.attributeName.trimmedDescription == "available" }
        guard !attributes.isEmpty else { return }
        text = attributes.map { attribute in
            let written = attribute.description.drop { $0.isNewline || $0 == " " }
            return String(written.reversed().drop { $0 == " " }.reversed())
        }.joined(separator: "\n")
    }
}

enum AppIntentsDiagnostic: DiagnosticMessage {
    case unknownSchema(String)
    case unionCases

    var message: String {
        switch self {
        case .unknownSchema(let schema): "nomac does not know which members the schema \(schema) marks: no experiment has shown them (B-158)"
        case .unionCases: "@UnionValue requires that each enum case have exactly one associated value"
        }
    }

    var diagnosticID: MessageID { MessageID(domain: "AppIntentsMacros", id: "\(self)") }
    var severity: DiagnosticSeverity { .error }
}
