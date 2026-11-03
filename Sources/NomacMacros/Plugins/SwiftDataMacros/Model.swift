import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// A property `@Model` persists: the first binding of a stored, non-static `var` or `let` that is
/// not `@Transient` (docs/formats/macros.md "SwiftData").
struct PersistedProperty {
    let name: String
    let value: ExprSyntax?
    /// `@Attribute` or `@Relationship`, which the schema's metadata repeats.
    let schemaAttribute: AttributeSyntax?

    init?(_ member: some DeclSyntaxProtocol) {
        guard let variable = member.as(VariableDeclSyntax.self),
              !variable.modifiers.contains(where: { [.keyword(.static), .keyword(.class)].contains($0.name.tokenKind) }),
              variable.attribute(named: "Transient") == nil,
              let binding = variable.bindings.first, binding.isStored,
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.unescapedName else { return nil }
        self.name = name
        value = binding.initializer?.value
        schemaAttribute = variable.attribute(named: "Attribute") ?? variable.attribute(named: "Relationship")
    }

    /// Whether `@Attribute`'s options include `.transformable(by:)`.
    var isTransformable: Bool {
        guard let schemaAttribute, schemaAttribute.attributeName.trimmedDescription == "Attribute",
              case .argumentList(let arguments) = schemaAttribute.arguments else { return false }
        return arguments.contains {
            $0.expression.as(FunctionCallExprSyntax.self)?.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "transformable"
        }
    }

    /// The schema's entry; the attribute's name keeps its trailing space when it has no arguments
    /// (`@Attribute var` gives `SwiftData.Schema.Attribute ()`).
    func metadata(of type: String) -> String {
        let metadata = schemaAttribute.map { attribute in
            let arguments = attribute.arguments.map { $0.trimmedDescription } ?? ""
            return "SwiftData.Schema.\(attribute.attributeName.description)(\(arguments))"
        } ?? "nil"
        return "SwiftData.Schema.PropertyMetadata(name: \"\(name)\", keypath: \\\(type).\(name), defaultValue: \(value?.trimmedDescription ?? "nil"), metadata: \(metadata))"
    }
}

extension VariableDeclSyntax {
    func attribute(named name: String) -> AttributeSyntax? {
        attributes.lazy.compactMap { $0.as(AttributeSyntax.self) }.first { $0.attributeName.trimmedDescription == name }
    }
}

extension PatternBindingSyntax {
    /// Whether the binding stores its value: no accessors, or only observers.
    var isStored: Bool {
        guard let accessors = accessorBlock?.accessors else { return true }
        guard case .accessors(let accessors) = accessors else { return false }
        return accessors.allSatisfy { [.keyword(.willSet), .keyword(.didSet)].contains($0.accessorSpecifier.tokenKind) }
    }
}

extension TokenSyntax {
    /// The identifier without the backticks that escape it (`` `default` `` gives `default`).
    var unescapedName: String {
        identifier?.name ?? text
    }
}

/// `@Model` (SwiftData): a class whose stored properties are read and written through its backing
/// data, observable, with the schema's metadata (docs/formats/macros.md "SwiftData").
public struct PersistentModelMacro: MemberMacro, MemberAttributeMacro, ExtensionMacro {
    /// The kinds of declaration the error names when `@Model` is not on a class.
    static let kinds: [SyntaxKind: String] = [.structDecl: "struct", .enumDecl: "enumeration", .actorDecl: "actor"]

    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let name = declaration.asProtocol(NamedDeclSyntax.self)?.name.text else { return [] }
        if let kind = kinds[declaration.kind] {
            context.diagnose(Diagnostic(node: node, message: ModelDiagnostic.notAClass(kind: kind, name: name)))
        }
        // The compiler lists no conformance to add when a @Model superclass has them.
        let isSubclass = protocols.isEmpty
        let isPublic = declaration.modifiers.contains { $0.name.tokenKind == .keyword(.public) }
        let isFinal = declaration.is(ClassDeclSyntax.self) && declaration.modifiers.contains { $0.name.tokenKind == .keyword(.final) }
        var properties: [PersistedProperty] = []
        var constraints: [String: MacroExpansionDeclSyntax] = [:]
        for member in declaration.memberBlock.members.map(\.decl) {
            if let property = PersistedProperty(member) {
                properties.append(property)
            } else if let variable = member.as(VariableDeclSyntax.self), variable.attribute(named: "Transient") != nil,
                      let binding = variable.bindings.first, binding.initializer == nil, !binding.isOptional,
                      let property = binding.pattern.as(IdentifierPatternSyntax.self) {
                context.diagnose(Diagnostic(node: variable, message: ModelDiagnostic.transientValue(property.identifier.text)))
            } else if let constraint = member.as(MacroExpansionDeclSyntax.self), ["Unique", "Index"].contains(constraint.macroName.text) {
                if constraints[constraint.macroName.text] == nil {
                    constraints[constraint.macroName.text] = constraint
                } else {
                    context.diagnose(Diagnostic(node: constraint, message: ModelDiagnostic.constraintTwice(constraint.macroName.text)))
                }
            }
        }
        if !declaration.memberBlock.members.contains(where: { $0.decl.is(InitializerDeclSyntax.self) }) {
            context.diagnose(Diagnostic(node: declaration, message: ModelDiagnostic.initializer(name)))
        }
        if isSubclass && !declaration.attributes.contains(where: \.specifiesPlatformVersion) {
            context.diagnose(Diagnostic(node: declaration, message: ModelDiagnostic.subclassAvailability))
        }

        let access = isPublic ? "public " : ""
        var members: [DeclSyntax] = ["""
            @Transient
            private var _$backingData: any SwiftData.BackingData<\(raw: name)> = \(raw: name).createBackingData()
            """]
        if !isSubclass {
            members.append("""
                public var persistentBackingData: any SwiftData.BackingData<\(raw: name)> {
                    get {
                        return _$backingData
                    }
                    set {
                        _$backingData = newValue
                    }
                }
                """)
        }
        let entries = properties.map { $0.metadata(of: name) }.joined(separator: ",\n    ")
        let schema = "\(isSubclass ? "override " : "")\(access)class var schemaMetadata: [SwiftData.Schema.PropertyMetadata] {"
        if constraints.isEmpty {
            members.append("""
                \(raw: schema)
                  return [
                    \(raw: entries)
                  ]
                }
                """)
        } else {
            let blocks = ["Index", "Unique"].map { kind in
                constraints[kind].map { constraint in
                    let metadata = "SwiftData.Schema.\(kind)\(constraint.genericArgumentClause?.trimmedDescription ?? "")(\(constraint.arguments.trimmedDescription))"
                    return """
                        if #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) {
                            otherProperties.append(
                              SwiftData.Schema.PropertyMetadata(name: "SwiftData.Schema.\(kind)", keypath: \\SwiftData.Schema.encodingVersion, defaultValue: nil, metadata: \(metadata)))
                          }
                        """
                } ?? ""
            }
            members.append("""
                \(raw: schema)
                  let storedProperties = [
                    \(raw: entries)
                  ]
                  var otherProperties = [SwiftData.Schema.PropertyMetadata]()
                  \(raw: blocks[0])
                  \(raw: blocks[1])
                  return storedProperties + otherProperties
                }
                """)
        }
        let assignments = properties.map { "_\($0.name) = _SwiftDataNoType()" }.joined(separator: "\n  ")
        let required = isSubclass || !isFinal ? "required " : ""
        if isSubclass {
            members.append("""
                \(raw: required)\(raw: access)init(backingData: any SwiftData.BackingData<Root>) {
                  \(raw: assignments)
                  _$backingData = backingData._generateCurrentClassBackingData()
                  super.init(backingData: backingData._superClassBackingData(of: \(raw: name).self))
                }
                """)
        } else {
            members.append("""
                \(raw: required)\(raw: access)init(backingData: any SwiftData.BackingData<\(raw: name)>) {
                  \(raw: assignments)
                  self.persistentBackingData = backingData
                }
                """)
        }
        return members + [
            "@Transient private let _$observationRegistrar = Observation.ObservationRegistrar()",
            """
            internal nonisolated func access<_M>(
                keyPath: KeyPath<\(raw: name), _M>
            ) {
              _$observationRegistrar.access(self, keyPath: keyPath)
            }
            """,
            """
            internal nonisolated func withMutation<_M, _MR>(
              keyPath: KeyPath<\(raw: name), _M>,
              _ mutation: () throws -> _MR
            ) rethrows -> _MR {
              try _$observationRegistrar.withMutation(of: self, keyPath: keyPath, mutation)
            }
            """,
            "struct _SwiftDataNoType {}",
        ]
    }

    /// `@_PersistedProperty`, or `@_TransformablePersistedProperty` for a `.transformable` attribute,
    /// carrying the property's own leading trivia (its documentation comment).
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingAttributesFor member: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [AttributeSyntax] {
        guard let property = PersistedProperty(member) else { return [] }
        let name = property.isTransformable ? "_TransformablePersistedProperty" : "_PersistedProperty"
        return [AttributeSyntax(attributeName: IdentifierTypeSyntax(name: .identifier(name))).with(\.leadingTrivia, member.leadingTrivia)]
    }

    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingExtensionsOf type: some TypeSyntaxProtocol,
                                 conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        guard !protocols.isEmpty else { return [] }
        let type = type.trimmedDescription
        let message = StringLiteralExprSyntax(content: "PersistentModels are not Sendable, consider utilizing a ModelActor or use \(type)'s persistentModelID instead")
        let extensions: [DeclSyntax] = [
            "extension \(raw: type): nonisolated SwiftData.PersistentModel {}",
            "extension \(raw: type): nonisolated Observation.Observable {}",
            """
            @available(swift, deprecated: 5.9, message: \(message))
            @available(*, unavailable, message: \(message))
            extension \(raw: type): Sendable {}
            """,
        ]
        return extensions.compactMap { $0.as(ExtensionDeclSyntax.self) }
    }
}

extension PatternBindingSyntax {
    var isOptional: Bool {
        guard let type = typeAnnotation?.type else { return false }
        return type.is(OptionalTypeSyntax.self) || type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
    }
}

extension AttributeListSyntax.Element {
    /// An `@available` with a platform and version (`iOS 26`), as a model subclass needs.
    var specifiesPlatformVersion: Bool {
        guard case .attribute(let attribute) = self, case .availability(let arguments) = attribute.arguments else { return false }
        return arguments.contains { if case .availabilityVersionRestriction = $0.argument { true } else { false } }
    }
}

/// `#Unique` and `#Index` declare nothing: `@Model` reads them into the schema's metadata.
public struct UniqueConstraintsMacro: DeclarationMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        []
    }
}

public struct IndexMacro: DeclarationMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        []
    }
}

enum ModelDiagnostic: DiagnosticMessage {
    case notAClass(kind: String, name: String)
    case initializer(String)
    case subclassAvailability
    case transientValue(String)
    case constraintTwice(String)

    var message: String {
        switch self {
        case .notAClass(let kind, let name): "'@Model' cannot be applied to \(kind) type '\(name)'"
        case .initializer(let name): "@Model requires an initializer be provided for '\(name)'"
        case .subclassAvailability: "A PersistentModel Subclass is required to have platform availability specified"
        case .transientValue(let name): "@Transient requires non-optional property '\(name)' to have a default value"
        case .constraintTwice(let name): "#\(name) can only be used once per PersistentModel"
        }
    }

    var diagnosticID: MessageID { MessageID(domain: "SwiftDataMacros", id: "\(self)") }

    var severity: DiagnosticSeverity { .error }
}
