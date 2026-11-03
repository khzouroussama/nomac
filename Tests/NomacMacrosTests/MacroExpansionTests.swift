import Foundation
import NomacCore
@testable import NomacMacros
import Testing

/// Every use of a macro in the experiments of `.github/scripts/macro_experiments.py`, sent to nomac's
/// plugins through the `swift-plugin-server` of the toolchain running the tests as Xcode 27.0's
/// compiler sent it: each answer's digest must be that of the answer of Xcode's plugins. The inputs
/// are the experiments' self-written sources and where the compiler addressed each use in them
/// (`ObservedExpansions.swift`, from `macro_experiments.py facts`); expansions that are inputs of
/// later ones are nomac's own answers, as the compiler would pass them.
@Suite(.serialized) struct MacroExpansionTests {
    /// The plugins, built once with the test toolchain as `nomac toolchain install` builds them.
    static let plugins: Result<(toolchain: String, directory: String), NomacError> = {
        do {
            let toolchain = try PluginServer.hostToolchain()
            let directory = NSTemporaryDirectory() + "/nomac-macro-plugins-test-" + UUID().uuidString
            _ = try MacroPlugins.build(toolchain: toolchain, into: directory, runPaths: [toolchain + "/lib/swift/host"])
            return .success((toolchain, directory))
        } catch let error as NomacError {
            return .failure(error)
        } catch {
            return .failure(NomacError("\(error)"))
        }
    }()

    struct ObservedCase: Sendable, CustomTestStringConvertible {
        var name: String
        var source: String
        var expansions: [Observed]
        var testDescription: String { name }

        init(_ name: String, source: String, expansions: [Observed]) {
            self.name = name
            self.source = source
            self.expansions = expansions
        }
    }

    /// A use of a macro: `Module.Type:name`, its role, the compiler's discriminator when the answer
    /// depends on it, its syntax nodes (a freestanding expansion's, or an attribute and its
    /// declaration), its lexical context, and the SHA-256 digest of Xcode's answer (`canonical`).
    /// A member attribute macro also gets the declaration's parent; member and extension macros the
    /// conformances the compiler still lacks, and an extension macro the type it extends.
    struct Observed: Sendable {
        var macro: String
        var role: String
        var discriminator: String?
        var nodes: [Node]
        var context: [Scope]
        var digest: String
        var parent: Node?
        var conformances: [String]?
        var extendedType: String?
    }

    /// A declaration of the lexical context, as the compiler renders it: written in the case's
    /// source, or made by an earlier expansion: its text up to its first brace, then `}`, from the
    /// expansion's start or from a byte offset in it, or a slice of it.
    enum Scope: Sendable {
        case text(String, String)
        case head(String, Int)
        case headAt(String, Int, Int)
        case slice(String, Int, Int, Int)
    }

    /// Where a syntax node is: a slice of the case's source, or of an earlier expansion's.
    struct Node: Sendable {
        enum Origin: Sendable {
            case file
            case expansion(Int)
        }

        var kind: String
        var origin: Origin
        var offset: Int
        var length: Int
    }

    static func O(_ macro: String, _ role: String, _ discriminator: String?, _ nodes: [Node], _ context: [Scope], _ digest: String,
                  parent: Node? = nil, conformances: [String]? = nil, extendedType: String? = nil) -> Observed {
        Observed(macro: macro, role: role, discriminator: discriminator, nodes: nodes, context: context, digest: digest,
                 parent: parent, conformances: conformances, extendedType: extendedType)
    }

    static func N(_ kind: String, _ origin: Node.Origin, _ offset: Int, _ length: Int) -> Node {
        Node(kind: kind, origin: origin, offset: offset, length: length)
    }

    /// The text digested for a plugin's answer: the expansion, then each diagnostic's fields
    /// (`macro_experiments.py`'s `canonical`).
    static func canonical(_ answer: [String: Any]) -> String {
        func span(_ range: Any?) -> String {
            let range = range as? [String: Any] ?? [:]
            return "\(range["fileName"] ?? "")@\(range["startOffset"] ?? "")-\(range["endOffset"] ?? "")"
        }
        var lines = [(answer["expandedSource"] as? String).map { "source:" + $0 } ?? "nil"]
        for diagnostic in answer["diagnostics"] as? [[String: Any]] ?? [] {
            let position = diagnostic["position"] as? [String: Any] ?? [:]
            let highlights = (diagnostic["highlights"] as? [Any] ?? []).map(span).joined(separator: ",")
            let notes = (diagnostic["notes"] as? [[String: Any]] ?? []).map { note in
                let at = note["position"] as? [String: Any] ?? [:]
                return "\(at["fileName"] ?? "")@\(at["offset"] ?? ""):\(note["message"] ?? "")"
            }.joined(separator: ";")
            let fixIts = (diagnostic["fixIts"] as? [[String: Any]] ?? []).map { fixIt in
                let changes = (fixIt["changes"] as? [[String: Any]] ?? []).map { "\(span($0["range"])):\($0["newText"] ?? "")" }
                return "\(fixIt["message"] ?? "")=" + changes.joined(separator: ",")
            }.joined(separator: ";")
            lines.append([diagnostic["severity"] as? String ?? "", diagnostic["message"] as? String ?? "",
                          "\(position["fileName"] ?? "")@\(position["offset"] ?? "")", highlights, notes, fixIts].joined(separator: "|"))
        }
        return lines.joined(separator: "\n")
    }

    /// The build configuration the compiler sends with each request, as JSON; Foundation's
    /// `#bundle` reads its custom conditions. Written for the tests: an iOS arm64 target without
    /// custom conditions, as the experiments were compiled.
    static let buildConfiguration: String = #"{"attributes":[],"compilerVersion":{"components":[6,4]},"customConditions":[],"endianness":"little","features":[],"languageMode":{"components":[5,10]},"targetArchitectures":["arm64"],"targetAtomicBitWidths":[128,64,32,16,8],"targetEnvironments":[],"targetOSs":["iOS"],"targetObjectFileFormats":["MachO"],"targetPointerAuthenticationSchemes":["_none"],"targetPointerBitWidth":64,"targetRuntimes":["_multithreaded","_ObjC"]}"#

    @Test func everyPluginModuleHasObservedExpansions() throws {
        let modules = try MacroPlugins.modules()
        #expect(modules == ["AppIntentsMacros", "FoundationMacros", "FoundationModelsMacros", "PreviewsMacros", "SwiftDataMacros", "SwiftUIMacros", "TipKitMacros"])
        let observed = Set(Self.observedCases.flatMap { $0.expansions.map { String($0.macro.prefix { $0 != "." }) } })
        #expect(observed == Set(modules))
    }

    @Test(arguments: observedCases) func expandsAsXcode(_ observed: ObservedCase) throws {
        let (toolchain, directory) = try Self.plugins.get()
        let server = try PluginServer(toolchain: toolchain)
        defer { server.close() }
        for module in try MacroPlugins.modules() {
            let loaded = try server.send(["loadPluginLibrary": ["libraryPath": directory + "/lib" + module + MacroPlugins.libraryExtension, "moduleName": module]])
            #expect((loaded["loadPluginLibraryResult"] as? [String: Any])?["loaded"] as? Bool == true, "\(loaded)")
        }
        var answers: [String] = []
        for (index, expansion) in observed.expansions.enumerated() {
            func syntax(_ node: Node) throws -> [String: Any] {
                let text: String
                let fileName: String
                switch node.origin {
                case .file:
                    (text, fileName) = (observed.source, observed.name + ".swift")
                case .expansion(let parent):
                    let discriminator = try #require(observed.expansions[parent].discriminator)
                    (text, fileName) = (answers[parent], "@__swiftmacro_" + discriminator.dropFirst(2) + ".swift")
                }
                let bytes = Array(text.utf8)
                let before = bytes[..<node.offset]
                let line = before.count { $0 == UInt8(ascii: "\n") } + 1
                let column = node.offset - (before.lastIndex(of: UInt8(ascii: "\n")).map { $0 + 1 } ?? 0) + 1
                let location: [String: Any] = ["fileID": "M/" + fileName, "fileName": fileName, "offset": node.offset, "line": line, "column": column]
                return ["kind": node.kind, "location": location, "source": String(decoding: bytes[node.offset..<(node.offset + node.length)], as: UTF8.self)]
            }
            // Where the compiler places the syntax it renders itself, outside any file.
            let nowhere: [String: Any] = ["fileID": "", "fileName": "", "offset": 0, "line": 0, "column": 0]
            let parts = expansion.macro.split(separator: ":", maxSplits: 1)
            let names = parts[0].split(separator: ".", maxSplits: 1)
            var request: [String: Any] = [
                "macro": ["moduleName": String(names[0]), "typeName": String(names[1]), "name": String(parts[1])],
                "macroRole": expansion.role,
                "discriminator": expansion.discriminator ?? "$s1M4testfMa_",
                "lexicalContext": expansion.context.map { scope -> [String: Any] in
                    let (kind, source): (String, String)
                    switch scope {
                    case .text(let written, let text):
                        (kind, source) = (written, text)
                    case .head(let written, let earlier):
                        let answer = answers[earlier]
                        (kind, source) = (written, String(answer[...(answer.firstIndex(of: "{") ?? answer.startIndex)]) + "}")
                    case .headAt(let written, let earlier, let offset):
                        let rest = Array(answers[earlier].utf8)[offset...]
                        let brace = rest.firstIndex(of: UInt8(ascii: "{")) ?? rest.startIndex
                        (kind, source) = (written, String(decoding: rest[...brace], as: UTF8.self) + "}")
                    case .slice(let written, let earlier, let offset, let length):
                        (kind, source) = (written, String(decoding: Array(answers[earlier].utf8)[offset..<(offset + length)], as: UTF8.self))
                    }
                    return ["kind": kind, "source": source, "location": nowhere]
                },
            ]
            if names[0] == "FoundationMacros" {
                request["staticBuildConfiguration"] = Self.buildConfiguration
            }
            let message: [String: Any]
            if expansion.nodes.count == 1 {
                request["syntax"] = try syntax(expansion.nodes[0])
                message = ["expandFreestandingMacro": request]
            } else {
                request["attributeSyntax"] = try syntax(expansion.nodes[0])
                request["declSyntax"] = try syntax(expansion.nodes[1])
                if let parent = expansion.parent {
                    request["parentDeclSyntax"] = try syntax(parent)
                }
                if let conformances = expansion.conformances {
                    request["conformanceListSyntax"] = ["kind": "declaration", "location": nowhere,
                                                        "source": "struct Placeholder: \(conformances.joined(separator: ", ")) {}"]
                }
                if let extendedType = expansion.extendedType {
                    request["extendedTypeSyntax"] = ["kind": "type", "location": nowhere, "source": extendedType]
                }
                message = ["expandAttachedMacro": request]
            }
            let answer = try #require(server.send(message)["expandMacroResult"] as? [String: Any])
            answers.append(answer["expandedSource"] as? String ?? "")
            #expect(SHA256.hex(Self.canonical(answer)) == expansion.digest, "\(observed.name), expansion \(index) (\(expansion.macro), \(expansion.role)):\n\(Self.canonical(answer))")
        }
    }

    /// State in a type declared in a function. Observed (`state-local`): Xcode 27.0's compiler
    /// gives it the `State` property wrapper and never asks the plugin, and its object makes the
    /// state with `State.init(wrappedValue:)`, stored as is, with a memberwise initializer taking the
    /// value. swift.org's compiler asks the plugin, whose expansion must therefore make the state
    /// with `init(wrappedValue:)`, store no lazy storage, and let the memberwise initializer set it
    /// (B-153).
    @Test func stateInALocalTypeIsMadeAsThePropertyWrapperMakesIt() throws {
        let (toolchain, directory) = try Self.plugins.get()
        let server = try PluginServer(toolchain: toolchain)
        defer { server.close() }
        _ = try server.send(["loadPluginLibrary": ["libraryPath": directory + "/libSwiftUIMacros" + MacroPlugins.libraryExtension, "moduleName": "SwiftUIMacros"]])
        let location: [String: Any] = ["column": 9, "fileID": "M/local.swift", "fileName": "local.swift", "line": 3, "offset": 60]
        let lexicalContext: [[String: Any]] = [
            ["kind": "declaration", "location": location, "source": "struct Local: View {}"],
            ["kind": "declaration", "location": location, "source": "func make() -> some View"],
        ]
        func expand(_ role: String) throws -> String {
            let request: [String: Any] = ["expandAttachedMacro": [
                "macro": ["moduleName": "SwiftUIMacros", "name": "State", "typeName": "StateMacro"], "macroRole": role,
                "discriminator": "$s1M4makeQryF5LocalL_V6hidden5StatefMp_",
                "attributeSyntax": ["kind": "attribute", "location": location, "source": "@State"],
                "declSyntax": ["kind": "declaration", "location": location, "source": "@State private var hidden = 1"],
                "lexicalContext": lexicalContext,
            ]]
            return try #require((server.send(request)["expandMacroResult"] as? [String: Any])?["expandedSource"] as? String)
        }
        let peers = try expand("peer")
        #expect(peers.contains("var _hidden = SwiftUICore.State(wrappedValue: 1)"))
        #expect(!peers.contains("_makeStorage") && !peers.contains("__hidden") && !peers.contains("initialValue:"))
        let accessors = try expand("accessor")
        #expect(accessors.contains("@storageRestrictions(initializes: _hidden)"))
        #expect(accessors.contains("_hidden = SwiftUICore.State(wrappedValue: initialValue)"))
        #expect(accessors.contains("_hidden.wrappedValue = newValue"))
    }

    /// `@Previewable`'s state, in the view the Previews macro declares in the preview's closure and
    /// makes without arguments: no init accessor, whose dynamic access check (swift.org's and
    /// Xcode's compilers, in a type local to a closure) the property wrapper Xcode applies there
    /// does not have (`preview-previewable`'s objects).
    @Test func previewableStateHasNoInitAccessor() throws {
        let (toolchain, directory) = try Self.plugins.get()
        let server = try PluginServer(toolchain: toolchain)
        defer { server.close() }
        _ = try server.send(["loadPluginLibrary": ["libraryPath": directory + "/libSwiftUIMacros" + MacroPlugins.libraryExtension, "moduleName": "SwiftUIMacros"]])
        let location: [String: Any] = ["column": 9, "fileID": "M/preview.swift", "fileName": "preview.swift", "line": 3, "offset": 60]
        let request: [String: Any] = ["expandAttachedMacro": [
            "macro": ["moduleName": "SwiftUIMacros", "name": "State", "typeName": "StateMacro"], "macroRole": "accessor",
            "discriminator": "$s1M4makeQryF5LocalL_V5count5StatefMa_",
            "attributeSyntax": ["kind": "attribute", "location": location, "source": "@State"],
            "declSyntax": ["kind": "declaration", "location": location, "source": "@State var count = 0"],
            "lexicalContext": [
                ["kind": "declaration", "location": location, "source": "struct __P_Previewable_Transform_Wrapper: SwiftUI.View {}"],
                ["kind": "expression", "location": location, "source": "{ }"],
            ],
        ]]
        let accessors = try #require((server.send(request)["expandMacroResult"] as? [String: Any])?["expandedSource"] as? String)
        #expect(!accessors.contains("init(initialValue)"))
        #expect(accessors.contains("_count.wrappedValue = newValue"))
    }
}

/// A `swift-plugin-server` the tests talk to as the compiler does: messages are JSON objects, each
/// preceded by its size as a 64-bit little-endian integer.
final class PluginServer {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()

    /// The `usr` directory of the toolchain running the tests: the selected Xcode's on a Mac
    /// (`DEVELOPER_DIR`, else `xcode-select`'s), else the one of the `swiftc` on `PATH`.
    static func hostToolchain() throws -> String {
        #if os(macOS)
        let developer = try ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
            ?? Subprocess.run("/usr/bin/xcode-select", ["-p"]).outputString.trimmingCharacters(in: .whitespacesAndNewlines)
        return developer + "/Toolchains/XcodeDefault.xctoolchain/usr"
        #else
        guard let swiftc = Subprocess.locate("swiftc") else { throw NomacError("no swiftc on PATH") }
        return ((FileSystem.resolvingSymbolicLinks(swiftc) as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
        #endif
    }

    init(toolchain: String) throws {
        process.executableURL = URL(fileURLWithPath: toolchain + "/bin/swift-plugin-server")
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        let capability = try send(["getCapability": ["capability": ["protocolVersion": 8]]])
        guard capability["getCapabilityResult"] != nil else { throw NomacError("unexpected answer from swift-plugin-server: \(capability)") }
    }

    func send(_ message: [String: Any]) throws -> [String: Any] {
        let payload = try JSONSerialization.data(withJSONObject: message)
        var size = UInt64(payload.count).littleEndian
        input.fileHandleForWriting.write(Data(bytes: &size, count: 8) + payload)
        let header = try read(8)
        let length = header.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }.littleEndian
        guard let answer = try JSONSerialization.jsonObject(with: read(Int(length))) as? [String: Any] else {
            throw NomacError("swift-plugin-server answered something other than a JSON object")
        }
        return answer
    }

    func close() {
        try? input.fileHandleForWriting.close()
        process.waitUntilExit()
    }

    private func read(_ count: Int) throws -> Data {
        var data = Data()
        while data.count < count {
            guard let chunk = try output.fileHandleForReading.read(upToCount: count - data.count), !chunk.isEmpty else {
                throw NomacError("swift-plugin-server stopped answering")
            }
            data += chunk
        }
        return data
    }
}
