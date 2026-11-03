import NomacCore
import Testing
@testable import NomacSigning

@Suite struct CodesignArgumentsTests {
    /// A CodeSign task of Swift Build re-signing an embedded framework (Xcode 27.0's build log).
    @Test func readsSwiftBuildsCodeSignTask() throws {
        let requests = try CodesignArguments.parse([
            "--force", "--sign", "-", "--preserve-metadata=identifier,entitlements,flags", "--generate-entitlement-der", "App.app/Frameworks/Kit.framework",
        ])
        #expect(requests == [CodeSigner.Request(path: "App.app/Frameworks/Kit.framework", identity: "-", force: true,
                                                preservedMetadata: ["identifier", "entitlements", "flags"])])
    }

    /// The codesign invocation of `xcodebuild -exportArchive` (its Packaging.log).
    @Test func readsTheArchiveExportInvocation() throws {
        let requests = try CodesignArguments.parse([
            "-f", "-s", "-", "--entitlements", "/tmp/entitlements", "--preserve-metadata=identifier,flags,runtime,launch-constraints,library-constraints",
            "--generate-entitlement-der", "--strip-disallowed-xattrs", "-vvv", "Payload/App.app",
        ])
        #expect(requests == [CodeSigner.Request(path: "Payload/App.app", identity: "-", force: true, entitlementsPath: "/tmp/entitlements",
                                                preservedMetadata: ["identifier", "flags", "runtime", "launch-constraints", "library-constraints"],
                                                verbose: true)])
    }

    @Test func rejectsOptionsItDoesNotImplement() {
        #expect(throws: NomacError("unsupported codesign option --deep")) { try CodesignArguments.parse(["--deep", "-s", "-", "x"]) }
        #expect(throws: NomacError("secure timestamps are not supported (--timestamp=none only)")) {
            try CodesignArguments.parse(["--timestamp", "-s", "-", "x"])
        }
    }

    /// A script phase's `codesign --sign` without `--keychain` takes Swift Build's
    /// `CODE_SIGN_KEYCHAIN` from its environment; `--keychain` wins.
    @Test func keychainFromTheEnvironment() throws {
        let environment = ["CODE_SIGN_KEYCHAIN": "/identity.pem"]
        #expect(try CodesignArguments.parse(["--force", "--sign", "ABC", "Kit.framework"], environment: environment).first?.keychain == "/identity.pem")
        #expect(try CodesignArguments.parse(["--sign", "ABC", "--keychain", "/other.pem", "x"], environment: environment).first?.keychain == "/other.pem")
        #expect(try CodesignArguments.parse(["--sign", "ABC", "x"], environment: ["CODE_SIGN_KEYCHAIN": ""]).first?.keychain == nil)
    }
}
