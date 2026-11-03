import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// What every `#Preview` expands to in Xcode 27.0: a `DeveloperToolsSupport.PreviewRegistry` struct
/// whose `makePreview()` calls `DeveloperToolsSupport.Preview` with the macro's own arguments and
/// closures (docs/formats/macros.md "Previews"). The templates are indented as Xcode's are, so
/// that swift-syntax's formatting of the expansion places the closures' own lines as Xcode does.
enum PreviewRegistry {
    /// Expands a `#Preview`, `body` rewriting the closure that makes the preview's content.
    static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext,
        body: (ClosureExprSyntax) throws -> ClosureExprSyntax
    ) throws -> [DeclSyntax] {
        let attributes = node.as(MacroExpansionDeclSyntax.self)?.attributes ?? []
        let modifiers = node.as(MacroExpansionDeclSyntax.self)?.modifiers ?? []
        var diagnostics: [Diagnostic] = []
        var availableAttributes: [AttributeSyntax] = []
        for element in attributes {
            guard case .attribute(let attribute) = element, attribute.attributeName.trimmedDescription == "available" else {
                diagnostics.append(Diagnostic(node: element, message: PreviewDiagnostic.attribute(element.trimmedDescription), highlights: [],
                                              fixIt: FixIt(message: PreviewFixIt.removeAttribute, changes: [.replace(oldNode: Syntax(element), newNode: Syntax(AttributeListSyntax([])))])))
                continue
            }
            availableAttributes.append(attribute)
        }
        for modifier in modifiers {
            diagnostics.append(Diagnostic(node: modifier, message: PreviewDiagnostic.modifier(modifier.name.text), highlights: [],
                                          fixIt: FixIt(message: PreviewFixIt.removeModifier(modifier.name.text), changes: [.replace(oldNode: Syntax(modifier), newNode: Syntax(DeclModifierListSyntax([])))])))
        }
        guard diagnostics.isEmpty else { throw DiagnosticsError(diagnostics: diagnostics) }

        var call = FunctionCallExprSyntax(
            calledExpression: ExprSyntax("DeveloperToolsSupport.Preview"),
            leftParen: node.leftParen,
            arguments: node.arguments,
            rightParen: node.rightParen,
            additionalTrailingClosures: node.additionalTrailingClosures
        )
        if let closure = node.trailingClosure {
            call.rightParen = call.rightParen?.with(\.trailingTrivia, [])
            call.trailingClosure = try body(closure)
        } else if let index = node.arguments.firstIndex(where: { $0.label?.text == "body" }),
                  let closure = node.arguments[index].expression.as(ClosureExprSyntax.self) {
            call.arguments[index].expression = ExprSyntax(try body(closure))
        }

        let location = context.location(of: node.pound, at: .afterLeadingTrivia, filePathMode: .fileID)!
        let availability = Availability(availableAttributes)
        return ["""
            @available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, watchOS 10.0, *)\(raw: availability.deprecations.map { "\n" + $0 }.joined())
            nonisolated struct \(context.makeUniqueName("PreviewRegistry")): DeveloperToolsSupport.PreviewRegistry {
                static var fileID: String {
                    \(location.file)
                }
                static var line: Int {
                    \(location.line)
                }
                static var column: Int {
                    \(location.column)
                }

                @MainActor static func makePreview() throws -> DeveloperToolsSupport.Preview {
                    \(availability.guarding(ExprSyntax(call)))
                }
            }
            """]
    }
}

/// What a preview's `@available` attributes change: the platforms they raise above the registry's
/// versions guard the preview with `if #available`, the platforms they make unavailable with
/// `#if os`, and their deprecations are copied to the registry.
struct Availability {
    /// The platform versions of the registry's `@available` attribute.
    static let registryVersions: [String: [Int]] = ["iOS": [17, 0], "macOS": [14, 0], "tvOS": [17, 0], "visionOS": [1, 0], "watchOS": [10, 0]]

    var introduced: [String: [Int]] = [:]
    var unavailable: Set<String> = []
    var deprecations: [String] = []

    init(_ attributes: [AttributeSyntax]) {
        for attribute in attributes {
            guard case .availability(let arguments)? = attribute.arguments else { continue }
            var platform: String?
            for argument in arguments {
                switch argument.argument {
                case .availabilityVersionRestriction(let restriction):
                    if let version = restriction.version {
                        introduce(restriction.platform.text, version)
                    }
                case .token(let token):
                    if token.text == "unavailable", let platform {
                        unavailable.insert(platform)
                    } else if token.text == "deprecated" {
                        deprecations.append("@available(\(platform ?? "*"), deprecated)")
                    } else if platform == nil {
                        platform = token.text
                    }
                case .availabilityLabeledArgument(let labeled):
                    guard let platform, case .version(let version) = labeled.value else { continue }
                    if labeled.label.text == "introduced" {
                        introduce(platform, version)
                    } else if labeled.label.text == "deprecated" {
                        deprecations.append("@available(\(platform), deprecated: \(Self.text(version)))")
                    }
                @unknown default:
                    continue
                }
            }
        }
    }

    /// The preview call, or the statements that guard it.
    func guarding(_ call: ExprSyntax) -> CodeBlockItemListSyntax {
        var statements: CodeBlockItemListSyntax = "\(call)"
        let raised = introduced.filter { platform, version in
            !unavailable.contains(platform) && Self.registryVersions[platform].map { Self.compare(version, $0) > 0 } ?? true
        }
        if !raised.isEmpty {
            let platforms = raised.keys.sorted().map { "\($0) \(raised[$0]!.map(String.init).joined(separator: "."))" }.joined(separator: ", ")
            statements = """
                if #available(\(raw: platforms), *) {
                    \(statements)
                } else {
                    throw DeveloperToolsSupport.PreviewUnavailable()
                }
                """
        }
        if !unavailable.isEmpty {
            statements = """
                #if \(raw: unavailable.sorted().map { "os(\($0))" }.joined(separator: " || "))
                throw DeveloperToolsSupport.PreviewUnavailable()
                #else
                \(statements)
                #endif
                """
        }
        return statements
    }

    private mutating func introduce(_ platform: String, _ tuple: VersionTupleSyntax) {
        let version = Self.components(tuple)
        if let current = introduced[platform], Self.compare(current, version) >= 0 { return }
        introduced[platform] = version
    }

    /// A version's components, with a minor version of 0 when it has only a major one.
    private static func components(_ tuple: VersionTupleSyntax) -> [Int] {
        let components = [Int(tuple.major.text) ?? 0] + tuple.components.map { Int($0.number.text) ?? 0 }
        return components.count == 1 ? components + [0] : components
    }

    private static func text(_ tuple: VersionTupleSyntax) -> String {
        components(tuple).map(String.init).joined(separator: ".")
    }

    private static func compare(_ left: [Int], _ right: [Int]) -> Int {
        for index in 0..<max(left.count, right.count) {
            let difference = (index < left.count ? left[index] : 0) - (index < right.count ? right[index] : 0)
            if difference != 0 { return difference }
        }
        return 0
    }
}

enum PreviewDiagnostic: DiagnosticMessage {
    case attribute(String)
    case modifier(String)
    case previewableOrder
    case previewableOutside

    var message: String {
        switch self {
        case .attribute(let attribute): "'\(attribute)' attribute cannot be applied to a preview"
        case .modifier(let modifier): "'\(modifier)' cannot be applied to a preview"
        case .previewableOrder: "'@Previewable' items must be at the beginning of the preview block"
        case .previewableOutside: "'@Previewable' can only be used in a SwiftUI #Preview body closure"
        }
    }

    var diagnosticID: MessageID { MessageID(domain: "PreviewsMacros", id: "\(self)") }
    var severity: DiagnosticSeverity { .error }
}

enum PreviewFixIt: FixItMessage {
    case removeAttribute
    case removeModifier(String)
    case movePreviewable

    var message: String {
        switch self {
        case .removeAttribute: "Remove the attribute"
        case .removeModifier(let modifier): "Remove '\(modifier)'"
        case .movePreviewable: "Move the '@Previewable' item"
        }
    }

    var fixItID: MessageID { MessageID(domain: "PreviewsMacros", id: "\(self)") }
}
