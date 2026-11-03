import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// A `@State` property as Xcode 27.0's `StateMacro` reads it (docs/formats/macros.md "SwiftUI state").
struct StateProperty {
    var name: String
    var type: TypeSyntax?
    /// The initial value written in the declaration or the attribute (`initialValue:`, `wrappedValue:`).
    var written: ExprSyntax?
    /// The modifier that sets the property's access, as written.
    var access: String?
    var inClass: Bool
    var inActor: Bool
    /// Whether the property's type is declared in a function, closure or property, not in a type.
    var inLocalType: Bool
    /// The view `@Previewable` declares its state in (``PreviewMacro``'s wrapper), which its
    /// preview makes without arguments.
    var inPreviewableWrapper: Bool
    var observers: [AccessorDeclSyntax]

    init?(_ declaration: some DeclSyntaxProtocol, attribute: AttributeSyntax, in context: some MacroExpansionContext) {
        guard let variable = declaration.as(VariableDeclSyntax.self), let binding = variable.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { return nil }
        name = identifier.identifier.text
        type = binding.typeAnnotation?.type.trimmed
        written = binding.initializer?.value.trimmed
            ?? attribute.arguments?.as(LabeledExprListSyntax.self)?.first(where: { ["initialValue", "wrappedValue"].contains($0.label?.text) })?.expression.trimmed
        // The access of the property itself: a setter's (`private(set)`) does not count.
        access = variable.modifiers.first(where: { ["private", "fileprivate", "internal", "package", "public", "open"].contains($0.name.text) && $0.detail == nil })?.name.text
        inClass = context.lexicalContext.first?.is(ClassDeclSyntax.self) ?? false
        inActor = context.lexicalContext.first?.is(ActorDeclSyntax.self) ?? false
        inLocalType = context.lexicalContext.dropFirst().contains { scope in
            ![.structDecl, .classDecl, .enumDecl, .actorDecl, .protocolDecl, .extensionDecl].contains(scope.kind)
        }
        inPreviewableWrapper = inLocalType && context.lexicalContext.first?.as(StructDeclSyntax.self)?.name.text == "__P_Previewable_Transform_Wrapper"
        if case .accessors(let accessors)? = binding.accessorBlock?.accessors {
            observers = Array(accessors)
        } else {
            observers = []
        }
    }

    var isOptional: Bool { type?.is(OptionalTypeSyntax.self) ?? false }

    /// The initial value, `nil` for an optional without one.
    var value: ExprSyntax? { written ?? (isOptional ? "nil" : nil) }

    /// Private state with an initial value is made on first use, from a static copy of its value.
    var isLazy: Bool { !inLocalType && (access == "private" || access == "fileprivate") && value != nil }

    var storage: String { prefixed(isLazy ? "__" : "_", name) }

    /// The storage's modifiers: a class or an actor keeps it internal.
    var storageAccess: String { inClass || inActor ? "" : "private " }

    var generic: String { type.map { "<\($0.description)>" } ?? "" }

    var projectedAccess: String { access.map { $0 + " " } ?? "" }
}

/// `@State` (SwiftUI): the property becomes computed, over storage the macro declares next to it.
public struct StateMacro: AccessorMacro, PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let property = StateProperty(declaration, attribute: node, in: context) else { return [] }
        let name = property.name
        if property.inLocalType {
            return localTypePeers(property)
        }
        guard let value = property.value else {
            guard let type = property.type else { return [] }
            return [
                "\(raw: property.storageAccess)var \(raw: prefixed("_", name)): SwiftUICore.State<\(type)>",
                """
                \(raw: property.projectedAccess)var \(raw: prefixed("$", name)): SwiftUICore.Binding<\(type)> {
                    \(raw: prefixed("_", name)).projectedValue
                }
                """,
            ]
        }
        guard property.isLazy else {
            return [
                "\(raw: property.storageAccess)var \(raw: prefixed("_", name)) = SwiftUICore.State\(raw: property.generic)(initialValue: \(value))",
                """
                @SwiftUICore._PropertyWrapperProjectedValue
                \(raw: property.projectedAccess)var \(raw: prefixed("$", name)) = SwiftUICore.State\(raw: property.generic)(initialValue: \(value)).projectedValue
                """,
            ]
        }
        let storedValue = context.makeUniqueName("_initialStoredValue_")
        let storage: ExprSyntax
        let initialStoredValue: ExprSyntax
        if let type = property.type {
            storage = "SwiftUICore.State._makeStorage(({ let value: \(type) = \(value)\nreturn value }))"
            initialStoredValue = "SwiftUICore.State._makeStorage(initialValue: { let x: \(type) = \(value)\nreturn x }())"
        } else {
            storage = "SwiftUICore.State._makeStorage({ \(value) })"
            initialStoredValue = "SwiftUICore.State._makeStorage(initialValue: \(value))"
        }
        let source = property.written == nil ? initialStoredValue : storage
        return [
            "\(raw: property.storageAccess)var \(raw: prefixed("__", name)) = \(storage)",
            """
            @SwiftUICore._StatePropertyWrapperStorage(initialValue: \(literal: Base64.encode(storedValue.text)))
            \(raw: property.storageAccess)var \(raw: prefixed("_", name)): SwiftUICore.State<_>! = SwiftUICore._stateNil(of: { SwiftUICore.State\(raw: property.generic)(initialValue: \(value)) })
            """,
            """
            @SwiftUICore._StateProjectedValue
            \(raw: property.projectedAccess)var \(raw: prefixed("$", name)) = SwiftUICore.State\(raw: property.generic)(initialValue: \(value)).projectedValue
            """,
            """
            @SwiftUICore._StateInitialStoredValue(\(literal: Base64.encode(source.description)))
            private static var \(storedValue) = (\(initialStoredValue))
            """,
        ]
    }

    public static func expansion(of node: AttributeSyntax, providingAccessorsOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [AccessorDeclSyntax] {
        guard let property = StateProperty(declaration, attribute: node, in: context) else { return [] }
        let storage = property.storage
        var accessors: [AccessorDeclSyntax] = []
        // The init accessor the memberwise initializer needs makes swift.org's compiler, and
        // Xcode's, check the access to the storage dynamically in a type local to a closure; the
        // property wrapper Xcode's compiler applies there does not. A view that is only ever made
        // without arguments needs no init accessor (`preview-previewable`).
        if (!property.isLazy || property.written == nil) && !(property.inPreviewableWrapper && property.value != nil) {
            let initial = property.inLocalType ? "SwiftUICore.State(wrappedValue: initialValue)"
                : property.isLazy ? "SwiftUICore.State._makeStorage(initialValue: initialValue)" : "SwiftUICore.State(initialValue: initialValue)"
            accessors.append("""
                @storageRestrictions(initializes: \(raw: storage))
                init(initialValue) {
                    \(raw: storage) = \(raw: initial)
                }
                """)
        }
        accessors.append("""
            get {
                \(raw: storage).wrappedValue
            }
            """)
        // The setter's statements are joined by newlines: only the first takes the template's
        // indentation, the others are placed by swift-syntax's formatting.
        var statements: [String] = []
        let willSet = property.observers.first { $0.accessorSpecifier.tokenKind == .keyword(.willSet) }
        let didSet = property.observers.first { $0.accessorSpecifier.tokenKind == .keyword(.didSet) }
        let oldValue = didSet.flatMap { $0.parameters != nil || uses("oldValue", in: $0) ? context.makeUniqueName("_oldValue_").text : nil }
        if let oldValue {
            statements.append("let \(oldValue) = \(storage).wrappedValue")
        }
        if let willSet {
            statements.append(observerCall(willSet, parameter: willSet.parameters?.name.text ?? "newValue", argument: "newValue"))
        }
        statements.append("\(storage).wrappedValue = newValue")
        if let didSet {
            statements.append(observerCall(didSet, parameter: oldValue.map { _ in didSet.parameters?.name.text ?? "oldValue" }, argument: oldValue ?? ""))
        }
        accessors.append("""
            \(raw: property.inClass && !property.inLocalType ? "" : "nonmutating ")set {
                \(raw: statements.joined(separator: "\n"))
            }
            """)
        return accessors
    }

    /// State in a local type, to which Xcode 27.0's compiler applies the `State` property wrapper
    /// instead of this macro (B-153): the code the property wrapper gives (SE-0258), a private
    /// `State` made with `init(wrappedValue:)` and a projection reading its `projectedValue`.
    private static func localTypePeers(_ property: StateProperty) -> [DeclSyntax] {
        let name = property.name
        guard let value = property.value else {
            guard let type = property.type else { return [] }
            return [
                "private var \(raw: prefixed("_", name)): SwiftUICore.State<\(type)>",
                """
                \(raw: property.projectedAccess)var \(raw: prefixed("$", name)): SwiftUICore.Binding<\(type)> {
                    \(raw: prefixed("_", name)).projectedValue
                }
                """,
            ]
        }
        return [
            "private var \(raw: prefixed("_", name)) = SwiftUICore.State\(raw: property.generic)(wrappedValue: \(value))",
            """
            @SwiftUICore._PropertyWrapperProjectedValue
            \(raw: property.projectedAccess)var \(raw: prefixed("$", name)) = SwiftUICore.State\(raw: property.generic)(wrappedValue: \(value)).projectedValue
            """,
        ]
    }

    /// An observer's body as a closure called in the setter, with its parameter if it has one.
    private static func observerCall(_ observer: AccessorDeclSyntax, parameter: String?, argument: String) -> String {
        let body = observer.body?.statements.trimmedDescription ?? ""
        return "({\(parameter.map { " \($0) in" } ?? "")\n    \(body)\n})(\(argument))"
    }

    private static func uses(_ name: String, in observer: AccessorDeclSyntax) -> Bool {
        observer.body?.tokens(viewMode: .sourceAccurate).contains { $0.tokenKind == .identifier(name) } ?? false
    }
}

/// `@_PropertyWrapperProjectedValue` on `$name`: reads `_name`'s projected value.
public struct ProjectedValueMacro: AccessorMacro {
    public static func expansion(of node: AttributeSyntax, providingAccessorsOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [AccessorDeclSyntax] {
        guard let name = projectedName(declaration) else { return [] }
        return ["""
            get {
                \(raw: prefixed("_", name)).projectedValue
            }
            """]
    }
}

/// `@_StateProjectedValue` on `$name` of lazily stored state: reads `__name`'s projected value.
public struct StateProjectedValueMacro: AccessorMacro {
    public static func expansion(of node: AttributeSyntax, providingAccessorsOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [AccessorDeclSyntax] {
        guard let name = projectedName(declaration) else { return [] }
        return ["""
            get {
                \(raw: prefixed("__", name)).projectedValue
            }
            """]
    }
}

/// `@_StatePropertyWrapperStorage(initialValue:)` on `_name` of lazily stored state: a `State` made
/// from `__name`, whose initial value is the static property the argument names in base64.
public struct StatePropertyWrapperStorageMacro: AccessorMacro {
    public static func expansion(of node: AttributeSyntax, providingAccessorsOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [AccessorDeclSyntax] {
        guard let name = variableName(declaration), let storedValue = base64Argument(node) else { return [] }
        let storage = prefixed("_", name)
        return [
            """
            @storageRestrictions(initializes: \(raw: storage))
            init(initialValue) {
                if initialValue == nil {
                    \(raw: storage) = Self.\(raw: storedValue)
                } else {
                    \(raw: storage) = SwiftUICore.State._makeStorage(initialValue: initialValue.wrappedValue)
                }
            }
            """,
            """
            get {
                SwiftUICore.State(initialValue: \(raw: storage).wrappedValue)
            }
            """,
            """
            set {
                if newValue != nil {
                    \(raw: storage) = SwiftUICore.State._makeStorage(initialValue: newValue.wrappedValue)
                }
            }
            """,
        ]
    }
}

/// `@_StateInitialStoredValue(_:)` on the static copy of lazily stored state: returns the
/// expression the argument holds in base64.
public struct StateInitialStoredValueMacro: AccessorMacro {
    public static func expansion(of node: AttributeSyntax, providingAccessorsOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [AccessorDeclSyntax] {
        guard let source = base64Argument(node) else { return [] }
        return ["""
            get {
                \(raw: source)
            }
            """]
    }
}

private func variableName(_ declaration: some DeclSyntaxProtocol) -> String? {
    declaration.as(VariableDeclSyntax.self)?.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
}

/// The name of the property `$name` projects (`` `$default` `` projects `` `default` ``).
private func projectedName(_ declaration: some DeclSyntaxProtocol) -> String? {
    variableName(declaration).map { $0.hasPrefix("`") ? "`" + $0.dropFirst(2) : String($0.dropFirst()) }
}

/// A name made from a property's with `prefix` before it: inside the backticks of a backticked
/// name, which Xcode keeps around the whole name (`state-keywords`: `` `__default` ``,
/// `` `_default` ``, `` `$default` ``, for a keyword or not).
private func prefixed(_ prefix: String, _ name: String) -> String {
    guard name.count > 1, name.hasPrefix("`"), name.hasSuffix("`") else { return prefix + name }
    return "`" + prefix + name.dropFirst()
}

private func base64Argument(_ node: AttributeSyntax) -> String? {
    guard let argument = node.arguments?.as(LabeledExprListSyntax.self)?.first?.expression.as(StringLiteralExprSyntax.self),
          let encoded = argument.representedLiteralValue else { return nil }
    return Base64.decode(encoded)
}
