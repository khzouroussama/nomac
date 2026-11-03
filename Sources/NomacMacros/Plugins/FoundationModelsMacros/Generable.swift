import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@Generable` (FoundationModels): a struct's or an enum's generation schema, generated content
/// and, for a struct and an enum with associated values, its partially generated form, and the
/// conformance with its initializer from generated content (docs/formats/macros.md
/// "FoundationModels"). The expansions are written as Xcode's are, unformatted; the guides are
/// formatted.
public struct GenerableMacro: MemberMacro, ExtensionMacro {
    public static var formatMode: FormatMode { .disabled }

    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        let options = Options(node, declaration)
        if let structure = declaration.as(StructDeclSyntax.self) {
            let properties = Property.all(in: structure.memberBlock)
            return [
                "\(raw: schema(options, properties))",
                "\(raw: generatedContent(explicitNil: options.explicitNil, properties: properties, modifier: options.modifier))",
                "\(raw: partiallyGenerated(options, properties))",
            ]
        }
        guard let enumeration = declaration.as(EnumDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: node, message: FoundationModelsDiagnostic.structsAndEnums, highlights: [Syntax(node)]))
            return []
        }
        let cases = Case.all(in: enumeration)
        if cases.contains(where: { $0.values != nil }) {
            return [
                "\(raw: partialEnumeration(cases, modifier: options.modifier))",
                "\(raw: discriminatedSchema(cases, modifier: options.modifier))",
            ] + cases.map { "\(raw: discriminated($0))" } + ["\(raw: discriminatedContent(cases, modifier: options.modifier))"]
        }
        let raw = enumeration.inheritanceClause?.inheritedTypes.contains { $0.type.trimmedDescription == "String" } ?? false
        let values = cases.map { raw ? $0.name + ".rawValue" : "\"\($0.name)\"" }
        let description = options.description.map { ", description: " + $0 } ?? ""
        let content = raw ? "    rawValue.generatedContent" : "    switch self {\n" + cases.map { "    case .\($0.name):\n        \"\($0.name)\".generatedContent\n" }.joined() + "    }"
        return [
            """
            nonisolated\(raw: options.modifier) static var generationSchema: FoundationModels.GenerationSchema {
                FoundationModels.GenerationSchema(type: Self.self\(raw: description), anyOf: [\(raw: values.joined(separator: ", "))])
            }
            """,
            """
            nonisolated\(raw: options.modifier) var generatedContent: GeneratedContent {
            \(raw: content)
            }
            """,
        ]
    }

    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        let options = Options(node, declaration)
        let body: String
        if let structure = declaration.as(StructDeclSyntax.self) {
            body = Property.all(in: structure.memberBlock).map { "        self.\($0.name) = try content.value(forProperty: \"\($0.name)\")\n" }.joined()
        } else if let enumeration = declaration.as(EnumDeclSyntax.self) {
            let cases = Case.all(in: enumeration)
            if cases.contains(where: { $0.values != nil }) {
                body = discriminatedInitializerBody(cases)
            } else if enumeration.inheritanceClause?.inheritedTypes.contains(where: { $0.type.trimmedDescription == "String" }) ?? false {
                body = "        let rawValue = try content.value(String.self)\n        if let value = Self(rawValue: rawValue) {\n            self = value\n        } else {\n"
                    + unexpected("rawValue", "rawValue", indent: "            ") + "\n        }\n"
            } else {
                body = "        let rawValue = try content.value(String.self)\n        switch rawValue {\n"
                    + cases.map { "        case \"\($0.name)\":\n            self = .\($0.name)\n" }.joined()
                    + "        default:\n" + unexpected("value", "rawValue", indent: "            ") + "\n        }\n"
            }
        } else {
            return []
        }
        let attributes = declaration.attributes.compactMap { $0.as(AttributeSyntax.self) }
            .filter { $0.attributeName.trimmedDescription == "available" }.map { $0.trimmedDescription + "\n" }.joined()
        let text = """
            \(attributes)extension \(type.trimmedDescription): nonisolated FoundationModels.Generable {
                nonisolated\(options.modifier) init(_ content: FoundationModels.GeneratedContent) throws {
            \(body)    }
            }
            """
        return [DeclSyntax(stringLiteral: text).cast(ExtensionDeclSyntax.self)]
    }

    /// A struct's `generationSchema`.
    private static func schema(_ options: Options, _ properties: [Property], indent: String = "") -> String {
        var arguments = [options.name.map { "name: " + $0 } ?? "type: Self.self"]
        if let description = options.description { arguments.append("description: " + description) }
        if let explicit = options.explicitNilArgument { arguments.append("representNilExplicitlyInGeneratedContent: " + explicit) }
        let lines = properties.map { "            " + $0.schemaLine }.joined(separator: ",\n")
        return """
            nonisolated\(options.modifier) static var generationSchema: FoundationModels.GenerationSchema {
                FoundationModels.GenerationSchema(
                    \(arguments.joined(separator: ",\n        ")),
                    properties: [
            \(lines)
                    ]
                )
            }
            """.indented(indent)
    }

    /// A struct's `generatedContent`, with its two `addProperty` functions as Xcode writes them.
    private static func generatedContent(explicitNil: String, properties: [Property], modifier: String, indent: String = "") -> String {
        let additions = properties.map { "    addProperty(name: \"\($0.name)\", value: self.\($0.name))\n" }.joined()
        return """
            nonisolated\(modifier) var generatedContent: GeneratedContent {
                let explicitNil = \(explicitNil)
                var properties = [(name: String, value: any ConvertibleToGeneratedContent)]()
            \(additions)    return GeneratedContent(
                    properties: properties,
                    uniquingKeysWith: { _, second in
                        second
                    }
                )
                func addProperty(name: String, value: some Generable) {
                  properties.append((name: name, value: value))
                }
                func addProperty(name: String, value: (some Generable)?) {
                  if explicitNil || value != nil {
                    properties.append((name: name, value: value))
                  }
                }
            }
            """.indented(indent)
    }

    private static func partiallyGenerated(_ options: Options, _ properties: [Property]) -> String {
        let variables = properties.map { "    \($0.modifiers)var \($0.name): \($0.type).PartiallyGenerated?\n" }.joined()
        let assignments = properties.map { "        self.\($0.name) = try content.value(forProperty: \"\($0.name)\")\n" }.joined()
        let member = options.modifier.isEmpty ? "" : String(options.modifier.dropFirst()) + " "
        return """
            nonisolated\(options.modifier) struct PartiallyGenerated: Identifiable, nonisolated FoundationModels.ConvertibleFromGeneratedContent {
                \(member)var id: GenerationID
            \(variables)    nonisolated\(options.modifier) init(_ content: FoundationModels.GeneratedContent) throws {
                    self.id = content.id ?? GenerationID()
            \(assignments)    }
            }
            """
    }

    /// The two throws of an unexpected value, `if #available` of the newer one first.
    private static func unexpected(_ what: String, _ variable: String, indent: String) -> String {
        let description = "debugDescription: \"Unexpected \(what) \\\"\\(\(variable))\\\" for \\(Self.self)\""
        return """
            if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
                throw FoundationModels.GeneratedContent.ParsingError(rawContent: content.jsonString, \(description))
            } else {
                throw FoundationModels.LanguageModelSession.GenerationError.decodingFailure(FoundationModels.LanguageModelSession.GenerationError.Context(\(description)))
            }
            """.indented(indent)
    }

    // MARK: Enums with associated values

    private static func discriminatedInitializerBody(_ cases: [Case]) -> String {
        var body = "        let type: String = try content.value(forProperty: \"type\")\n        switch type {\n"
        for item in cases {
            body += "        case \"\(item.name)\":\n"
            switch item.values?.count {
            case nil, 0:
                body += "            self = .\(item.name)\n"
            case 1 where item.values?.first?.label == nil:
                body += "            self = .\(item.name)(try content.value(forProperty: \"value\"))\n"
            default:
                let arguments = (item.values ?? []).map { "                \($0.label ?? $0.name): try content.value(forProperty: \"\($0.name)\")" }
                body += "            self = .\(item.name)(\n" + arguments.joined(separator: ",\n") + "\n            )\n"
            }
        }
        return body + "        default:\n" + unexpected("type", "type", indent: "            ") + "\n        }\n"
    }

    private static func partialEnumeration(_ cases: [Case], modifier: String) -> String {
        let declarations = cases.map { item -> String in
            guard let values = item.values, !values.isEmpty else { return "    case \(item.name)\n" }
            let parameters = values.map { ($0.label.map { $0 + ": " } ?? "") + $0.type + ".PartiallyGenerated?" }
            return "    case \(item.name)(\(parameters.joined(separator: ", ")))\n"
        }.joined()
        return """
            nonisolated\(modifier) enum PartiallyGenerated: nonisolated FoundationModels.ConvertibleFromGeneratedContent {
            \(declarations)    nonisolated\(modifier) init(_ content: FoundationModels.GeneratedContent) throws {
            \(discriminatedInitializerBody(cases))    }
            }
            """
    }

    private static func discriminatedSchema(_ cases: [Case], modifier: String) -> String {
        """
        nonisolated\(modifier) static var generationSchema: FoundationModels.GenerationSchema {
            FoundationModels.GenerationSchema(
                type: Self.self,
                anyOf: [
                    \(cases.map { $0.discriminatedName + ".self" }.joined(separator: ",\n            "))
                ]
            )
        }
        """
    }

    /// The struct a case's values are generated as, with a constant `type` guide.
    private static func discriminated(_ item: Case) -> String {
        let properties = [Property(name: "type", type: "String", modifiers: "", description: nil, guides: [".constant(\"\(item.name)\")"])]
            + (item.values ?? []).map { Property(name: $0.name, type: $0.type, modifiers: "", description: nil, guides: []) }
        let declarations = properties.map { ($0.name == "type" ? "    @Guide(.constant(\"\(item.name)\"))\n" : "") + "    let \($0.name): \($0.type)\n" }.joined()
        let assignments = properties.map { "        self.\($0.name) = try content.value(forProperty: \"\($0.name)\")\n" }.joined()
        return """
            private nonisolated struct \(item.discriminatedName): nonisolated FoundationModels.Generable {
            \(declarations)    nonisolated init(_ content: FoundationModels.GeneratedContent) throws {
            \(assignments)    }
            \(schema(Options(), properties, indent: "    "))
            \(generatedContent(explicitNil: "false", properties: properties, modifier: "", indent: "    "))
            }
            """
    }

    private static func discriminatedContent(_ cases: [Case], modifier: String) -> String {
        let branches = cases.map { item -> String in
            let values = item.values ?? []
            let pattern = values.isEmpty ? "" : "(" + values.map { "let " + $0.name }.joined(separator: ", ") + ")"
            let entries = values.map { "                \"\($0.name)\": \($0.name)" }.joined(separator: ",\n")
            return """
                    case .\(item.name)\(pattern):
                        GeneratedContent(
                            properties: [
                                "type": "\(item.name)",
                \(entries)
                            ]
                        )

                """
        }.joined()
        return "nonisolated\(modifier) var generatedContent: GeneratedContent {\n    switch self {\n" + branches + "    }\n}"
    }
}

/// `@Guide` (FoundationModels): read by `@Generable`; expands to nothing.
public struct GuideMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        []
    }
}

/// The macro's arguments, and the access level its members get: `public` only.
private struct Options {
    var name: String?
    var description: String?
    var explicitNilArgument: String?
    var modifier = ""

    init() {}

    init(_ node: AttributeSyntax, _ declaration: some DeclGroupSyntax) {
        for argument in node.arguments?.as(LabeledExprListSyntax.self) ?? [] {
            switch argument.label?.text {
            case "name": name = argument.expression.trimmedDescription
            case "description": description = argument.expression.trimmedDescription
            case "representNilExplicitlyInGeneratedContent": explicitNilArgument = argument.expression.trimmedDescription
            default: break
            }
        }
        if declaration.modifiers.contains(where: { $0.name.tokenKind == .keyword(.public) }) { modifier = " public" }
    }

    var explicitNil: String { explicitNilArgument ?? "false" }
}

/// A stored instance property with a type, and its `@Guide`.
private struct Property {
    var name: String
    var type: String
    var modifiers: String
    var description: String?
    var guides: [String]

    static let accessLevels: Set<Keyword> = [.private, .fileprivate, .internal, .package, .public, .open]

    static func all(in members: MemberBlockSyntax) -> [Property] {
        members.members.compactMap { member -> Property? in
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  !variable.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class) }),
                  let binding = variable.bindings.first, binding.accessorBlock == nil,
                  let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.trimmedDescription,
                  let type = binding.typeAnnotation?.type.trimmedDescription else { return nil }
            var description: String?
            var guides: [String] = []
            let guide = variable.attributes.compactMap { $0.as(AttributeSyntax.self) }.first { $0.attributeName.trimmedDescription == "Guide" }
            for argument in guide?.arguments?.as(LabeledExprListSyntax.self) ?? [] {
                if argument.label?.text == "description" {
                    description = argument.expression.trimmedDescription
                } else {
                    guides.append(argument.expression.trimmed.formatted().description)
                }
            }
            let modifiers = variable.modifiers.filter {
                if case .keyword(let keyword) = $0.name.tokenKind { return accessLevels.contains(keyword) }
                return false
            }.map { $0.trimmedDescription + " " }.joined()
            return Property(name: name, type: type, modifiers: modifiers, description: description, guides: guides)
        }
    }

    var schemaLine: String {
        var arguments = ["name: \"\(name)\""]
        if let description { arguments.append("description: " + description) }
        arguments.append("type: \(type).self")
        if !guides.isEmpty { arguments.append("guides: [" + guides.joined(separator: ", ") + "]") }
        return "FoundationModels.GenerationSchema.Property(" + arguments.joined(separator: ", ") + ")"
    }
}

/// An enum case and its associated values, a single unlabeled one named `value`.
private struct Case {
    struct Value {
        var label: String?
        var name: String
        var type: String
    }

    var name: String
    var values: [Value]?

    var discriminatedName: String { "Discriminated" + name.prefix(1).uppercased() + name.dropFirst() }

    static func all(in enumeration: EnumDeclSyntax) -> [Case] {
        enumeration.memberBlock.members.compactMap { $0.decl.as(EnumCaseDeclSyntax.self) }.flatMap(\.elements).map { element in
            let values = element.parameterClause?.parameters.map { parameter in
                let label = parameter.firstName?.text
                return Value(label: label, name: label ?? "value", type: parameter.type.trimmedDescription)
            }
            return Case(name: element.name.text, values: values)
        }
    }
}

private enum FoundationModelsDiagnostic: String, DiagnosticMessage {
    case structsAndEnums = "'@Generable' can only be used on structs and enums."

    var message: String { rawValue }
    var diagnosticID: MessageID { MessageID(domain: "FoundationModelsMacros", id: "\(self)") }
    var severity: DiagnosticSeverity { .error }
}

private extension String {
    /// Every line indented by `indent`.
    func indented(_ indent: String) -> String {
        indent.isEmpty ? self : split(separator: "\n", omittingEmptySubsequences: false).map { indent + $0 }.joined(separator: "\n")
    }
}
