import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@_PersistedProperty`, which `@Model` puts on each persisted property: storage of an empty type
/// next to it, and accessors that go through the backing data (docs/formats/macros.md "SwiftData").
public struct PersistedPropertyMacro: AccessorMacro, PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        storage(of: declaration)
    }

    public static func expansion(of node: AttributeSyntax, providingAccessorsOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [AccessorDeclSyntax] {
        accessors(of: declaration, attribute: node, value: "Value")
    }

    static func storage(of declaration: some DeclSyntaxProtocol) -> [DeclSyntax] {
        guard let binding = declaration.as(VariableDeclSyntax.self)?.bindings.first,
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.unescapedName else { return [] }
        let type = binding.typeAnnotation?.type
        let optional = type?.is(OptionalTypeSyntax.self) == true ? "?" : type?.is(ImplicitlyUnwrappedOptionalTypeSyntax.self) == true ? "!" : ""
        let value = binding.initializer == nil ? "" : " = _SwiftDataNoType()"
        return ["""
            @Transient
            private var _\(raw: name): _SwiftDataNoType\(raw: optional)\(raw: value)
            """]
    }

    /// The accessors carry the attribute's leading trivia, then two spaces, as Xcode's do.
    static func accessors(of declaration: some DeclSyntaxProtocol, attribute: AttributeSyntax, value: String) -> [AccessorDeclSyntax] {
        guard let variable = declaration.as(VariableDeclSyntax.self),
              let name = variable.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.unescapedName else { return [] }
        var accessors: [AccessorDeclSyntax] = [
            """
            @storageRestrictions(accesses: _$backingData, initializes: _\(raw: name))
            init(initialValue) {
                _$backingData.set\(raw: value)(forKey: \\.\(raw: name), to: initialValue)
                _\(raw: name) = _SwiftDataNoType()
            }
            """,
            """
            get {
                _$observationRegistrar.access(self, keyPath: \\.\(raw: name))
                return self.get\(raw: value)(forKey: \\.\(raw: name))
            }
            """,
        ]
        if variable.bindingSpecifier.tokenKind == .keyword(.var) {
            accessors.append("""
                set {
                    _$observationRegistrar.withMutation(of: self, keyPath: \\.\(raw: name)) {
                        self.set\(raw: value)(forKey: \\.\(raw: name), to: newValue)
                    }
                }
                """)
        }
        return accessors.map { $0.with(\.leadingTrivia, attribute.leadingTrivia + .spaces(2)) }
    }
}

/// `@_TransformablePersistedProperty`: `@_PersistedProperty` for an attribute with `.transformable`,
/// whose accessors use the backing data's transformable values.
public struct TransformablePersistedPropertyMacro: AccessorMacro, PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        PersistedPropertyMacro.storage(of: declaration)
    }

    public static func expansion(of node: AttributeSyntax, providingAccessorsOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [AccessorDeclSyntax] {
        PersistedPropertyMacro.accessors(of: declaration, attribute: node, value: "TransformableValue")
    }
}

/// `@Transient`, `@Attribute` and `@Relationship` add nothing: `@Model` reads them.
public struct TransientPropertyMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        []
    }
}

public struct AttributePropertyMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        []
    }
}

public struct RelationshipPropertyMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        []
    }
}

/// `@Query` (SwiftData with SwiftUI): a `SwiftData.Query` stored next to the property, which reads
/// its results.
public struct QueryMacro: AccessorMacro, PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let binding = declaration.as(VariableDeclSyntax.self)?.bindings.first,
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.unescapedName else { return [] }
        guard let type = binding.typeAnnotation?.type else {
            context.diagnose(Diagnostic(node: binding, message: QueryDiagnostic.missingType))
            return []
        }
        // Sectioned results are queried by their first generic argument, other results by their elements.
        let element = type.as(IdentifierTypeSyntax.self).flatMap { identifier in
            identifier.name.text == "SectionedResults" ? identifier.genericArgumentClause?.arguments.first?.argument.trimmedDescription : nil
        } ?? "\(type.trimmedDescription).Element"
        let arguments = node.arguments?.description ?? ""
        return ["private(set) var _\(raw: name): SwiftData.Query<\(raw: element), \(type.trimmed)> = .init(\(raw: arguments))"]
    }

    public static func expansion(of node: AttributeSyntax, providingAccessorsOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [AccessorDeclSyntax] {
        guard let name = declaration.as(VariableDeclSyntax.self)?.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.unescapedName else { return [] }
        return ["""
            get {
                _\(raw: name).wrappedValue
            }
            """]
    }
}

enum QueryDiagnostic: DiagnosticMessage {
    case missingType

    var message: String {
        switch self {
        case .missingType: "Property missing a type annotation"
        }
    }

    var diagnosticID: MessageID { MessageID(domain: "SwiftDataMacros", id: "\(self)") }

    var severity: DiagnosticSeverity { .error }
}

/// `@ModelActor`: an actor that runs on a model context's serial executor.
public struct PersistentModelActorMacro: MemberMacro, ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        let access = declaration.modifiers.contains { $0.name.tokenKind == .keyword(.public) } ? "public " : ""
        return [
            "\(raw: access)nonisolated let modelExecutor: any SwiftData.ModelExecutor",
            "\(raw: access)nonisolated let modelContainer: SwiftData.ModelContainer",
            """
            \(raw: access)init(modelContainer: SwiftData.ModelContainer) {
                let modelContext = ModelContext(modelContainer)
                self.modelExecutor = DefaultSerialModelExecutor(modelContext: modelContext)
                self.modelContainer = modelContainer
            }
            """,
        ]
    }

    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingExtensionsOf type: some TypeSyntaxProtocol,
                                 conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        let conformance: DeclSyntax = "extension \(type.trimmed): SwiftData.ModelActor {}"
        return [conformance.as(ExtensionDeclSyntax.self)].compactMap { $0 }
    }
}
