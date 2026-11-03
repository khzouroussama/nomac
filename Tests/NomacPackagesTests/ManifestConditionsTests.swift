import Testing
@testable import NomacPackages

@Suite struct ManifestConditionsTests {
    static func rewrite(_ source: String) -> ManifestConditions.Result {
        ManifestConditions.rewrite(source, host: .mac)
    }

    @Test func answersHostConditionsAsAMac() {
        let source = """
        // swift-tools-version: 6.1
        #if os(Linux)
        let traits = ["Linux"]
        #elseif os(macOS) && canImport(Darwin)
        let traits = ["Mac"]
        #else
        let traits: [String] = []
        #endif
        """
        let result = Self.rewrite(source)
        #expect(result.source == """
        // swift-tools-version: 6.1
        #if false
        let traits = ["Linux"]
        #elseif true && true
        let traits = ["Mac"]
        #else
        let traits: [String] = []
        #endif
        """)
        #expect(result.unanswered.isEmpty)
    }

    /// package-experiments `conditions`: firebase-ios-sdk (nextcloud) adds its Gemini targets
    /// with `canImport(FoundationModels)`.
    /// kickstarter: facebook-ios-sdk imports `Darwin.C` on the Mac's branch, for `getenv`.
    @Test func importsTheMachinesCLibraryForDarwin() {
        let source = #"""
        import Foundation
        #if os(Linux)
        import Glibc
        #else
        import Darwin.C
        #endif
          import Darwin
        import DarwinFoundation
        // import Darwin
        let text = """
        import Darwin
        """
        """#
        #expect(ManifestConditions.rewrite(source, host: .mac, cLibrary: "Glibc").source == #"""
        import Foundation
        #if false
        import Glibc
        #else
        import Glibc
        #endif
          import Glibc
        import DarwinFoundation
        // import Darwin
        let text = """
        import Darwin
        """
        """#)
        #expect(ManifestConditions.rewrite(source, host: .mac, cLibrary: nil).source.contains("#else\nimport Darwin.C\n"))
    }

    @Test func answersTheModulesOfAMac() {
        let source = "#if compiler(>=6.4) && canImport(FoundationModels)\n#elseif canImport(MobileCoreServices) || canImport(Darwin.C)\n#endif\n"
        #expect(Self.rewrite(source).source == "#if compiler(>=6.4) && true\n#elseif false || true\n#endif\n")
    }

    @Test func leavesCompilerConditionsToTheCompiler() {
        let source = "#if swift(>=6.0) && !canImport(Glibc) && compiler(<7) && DEBUG\n#endif\n"
        #expect(Self.rewrite(source).source == "#if swift(>=6.0) && !false && compiler(<7) && DEBUG\n#endif\n")
    }

    @Test func coversEveryKindOfHostCondition() {
        let source = "#if arch(arm64) || arch(x86_64) || targetEnvironment(simulator) || _endian(little) || _pointerBitWidth(_64) || _runtime(_ObjC) || os(Windows)\n#endif"
        #expect(Self.rewrite(source).source == "#if true || false || false || true || true || true || false\n#endif")
    }

    @Test func reportsModulesItCannotAnswer() {
        let result = Self.rewrite("#if canImport(SomeVendorKit)\n#endif\n")
        #expect(result.source == "#if canImport(SomeVendorKit)\n#endif\n")
        #expect(result.unanswered == ["canImport(SomeVendorKit)"])
    }

    @Test func aMissingModuleFailsAVersionCheckToo() {
        #expect(Self.rewrite("#if canImport(Glibc, _version: 2.0)\n#endif").source == "#if false\n#endif")
        #expect(Self.rewrite("#if canImport(Foundation, _version: 2.0)\n#endif").unanswered == ["canImport(Foundation, _version: 2.0)"])
    }

    @Test func skipsCommentsAndStringLiterals() {
        let source = ##"""
        let a = "#if os(Linux)"
        let b = #"\#(x) " #if os(Linux)"#
        let c = """
        #if os(Linux)
        """
        let d = "\(f("#if os(Linux)"))"
        /* #if os(Linux) /* nested */ #if os(Linux) */
        // #if os(Linux)
        #if os(Linux) // os(Linux) in a comment
        #endif
        """##
        let expected = source.replacingOccurrences(of: "#if os(Linux) // os(Linux) in a comment", with: "#if false // os(Linux) in a comment")
        #expect(Self.rewrite(source).source == expected)
    }

    @Test func onlyRewritesDirectivesAtTheStartOfALine() {
        let source = "    #if os(Linux)\nfoo(#if)\nlet os = os(Linux)\n#endif\n"
        #expect(Self.rewrite(source).source == "    #if false\nfoo(#if)\nlet os = os(Linux)\n#endif\n")
    }

    @Test func followsAConditionAcrossLinesWhileParenthesesAreOpen() {
        let source = "#if (os(Linux) ||\n     os(Android))\n#endif\n"
        #expect(Self.rewrite(source).source == "#if (false ||\n     false)\n#endif\n")
    }

    @Test func keepsIdentifiersThatMerelyContainAKind() {
        #expect(Self.rewrite("#if myos(Linux) || os (Linux)\n#endif").source == "#if myos(Linux) || false\n#endif")
    }
}
