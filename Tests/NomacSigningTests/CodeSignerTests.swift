import Foundation
import NomacCore
import NomacTestSupport
import Testing
@testable import NomacSigning

/// Signing self-authored inputs (``SyntheticBundle``) gives byte for byte what Xcode 27.0's
/// codesign gave for the same inputs and arguments: the expected values are the SHA-256 of
/// every file codesign left (observed with `signing_experiments.py synthetic`).
@Suite struct CodeSignerTests {
    /// Entitlements with every value type codesign accepts, keys out of order and odd spacing
    /// (kept byte for byte in the XML blob).
    static let entitlements = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>zeta</key>       <string>last</string>
    	<key>application-identifier</key>
    	<string>ABCDE12345.org.nomac.signing</string>
    	<key>get-task-allow</key>
    	<true/>
    	<key>keychain-access-groups</key>
    	<array>
    		<string>ABCDE12345.*</string>
    	</array>
    	<key>number</key>
    	<integer>300</integer>
    	<key>negative</key>
    	<integer>-129</integer>
    	<key>off</key>
    	<false/>
    	<key>nested</key>
    	<dict>
    		<key>b</key>
    		<string>é</string>
    		<key>a</key>
    		<array/>
    	</dict>
    	<key>Upper</key>
    	<string>&lt;&amp;&gt;</string>
    </dict>
    </plist>

    """

    /// Signs `input` (made in a new directory) with codesign `arguments`; returns the digests of
    /// the result.
    static func sign(_ name: String, _ input: (URL) throws -> URL, _ arguments: [String], entitlements: String? = nil) throws -> [String: String] {
        let temporary = try TemporaryDirectory(prefix: "nomac-signing")
        let directory = URL(fileURLWithPath: temporary.path)
        let product = try input(directory)
        var arguments = arguments
        var entitlementsURL: URL?
        if let entitlements {
            entitlementsURL = directory.appendingPathComponent("entitlements.plist")
            try Data(entitlements.utf8).write(to: entitlementsURL!)
            arguments += ["--entitlements", entitlementsURL!.path]
        }
        try SyntheticBundle.observe(product, named: name, arguments: arguments, entitlements: entitlementsURL)
        for request in try CodesignArguments.parse(arguments + [product.path]) {
            _ = try CodeSigner.sign(request)
        }
        return try SyntheticBundle.digests(of: product)
    }

    static func file(_ bytes: [UInt8], named name: String) -> (URL) throws -> URL {
        { directory in
            let url = directory.appendingPathComponent(name)
            try Data(bytes).write(to: url)
            return url
        }
    }

    /// A bundle without an executable gets a detached signature in `_CodeSignature`, with the
    /// arguments an export signs an asset pack with (`odr` experiment).
    @Test func signsABundleWithoutCode() throws {
        let digests = try Self.sign("asset-pack", SyntheticBundle.assetPack, [
            "-f", "-s", "-", "--preserve-metadata=entitlements,identifier,flags,runtime,launch-constraints,library-constraints",
            "--generate-entitlement-der", "--strip-disallowed-xattrs", "-vvv",
        ])
        #expect(digests == [
            "Info.plist": "0e575ff0a25c95ae7332714ec840b0c835189d40346239f409ba8ba566a8ed2b",
            "_CodeSignature/CodeDirectory": "ef58e217642a1e6c53ba605040945a7b4d061a52782d1cfd1a3086087c820742",
            "_CodeSignature/CodeRequirements": "987920904eab650e75788c054aa0b0524e6a80bfc71aa32df8d237a61743f986",
            "_CodeSignature/CodeResources": "f5ebf05b87c4ce4d1e38c3779c40023f6f0267a59c38d03f2a0ad58d01ab5968",
            "_CodeSignature/CodeSignature": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            "level1.txt": "52be3bfe29c225617ca9306a9fda54d3ecee5571cc3eedcf374492402d07e7b2",
        ])
    }

    /// A bundle whose binary is not Mach-O (a static framework's `ar` archive) gets a detached
    /// signature with the binary as its code; with `--generate-pre-encrypt-hashes`, as Swift
    /// Build signs static frameworks, a version 0x20500 code directory (signing experiments
    /// `framework-static`).
    @Test func signsAStaticFramework() throws {
        let plain = try Self.sign("static-framework", SyntheticBundle.staticFramework, ["--force", "--sign", "-", "--generate-entitlement-der"])
        let preEncrypt = try Self.sign("static-framework-pre-encrypt", SyntheticBundle.staticFramework,
                                       ["--generate-pre-encrypt-hashes", "--force", "--sign", "-", "--generate-entitlement-der"])
        let shared = [
            "Headers/Kit.h": plain["Headers/Kit.h"] ?? "",
            "Info.plist": "31a18ed81a45a7508a433f66f359b308a4705f9129a2a0526ab7e1a61c50d7a9",
            "Kit": "631ced0724ec14b9694c5683e842ef3596c9f645371f0ba71914cd429258b6e8",
            "_CodeSignature/CodeRequirements": "987920904eab650e75788c054aa0b0524e6a80bfc71aa32df8d237a61743f986",
            "_CodeSignature/CodeResources": "6f2b17be07a1af376e787f45f75bd0f91ad00260b14f352211129842814d92c7",
            "_CodeSignature/CodeSignature": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        ]
        #expect(plain == shared.merging(["_CodeSignature/CodeDirectory": "2f5d64b6015efeb3ea30ab08b272f2bd3931d5fcb00cbd8934b4cb1dbd30f8da"]) { a, _ in a })
        #expect(preEncrypt == shared.merging(["_CodeSignature/CodeDirectory": "fe8249568c4373fd335152b87b64d323fb3a388516bf843d3112bb60804cfc1a"]) { a, _ in a })
    }

    /// Without CFBundleIdentifier or CFBundleName, codesign names a bundle after its folder and a
    /// hash: the Mach-O identification of a file signed alone, or the SHA-1 of a detached
    /// signature's code (B-303).
    @Test func identifiesBundlesWithoutCFBundleIdentifier() throws {
        let app = try Self.sign("app-without-identifier", SyntheticBundle.removing(["CFBundleIdentifier"], from: SyntheticBundle.application),
                                ["--force", "--sign", "-", "--generate-entitlement-der"])
        let framework = try Self.sign("static-without-identifier", SyntheticBundle.removing(["CFBundleIdentifier"], from: SyntheticBundle.staticFramework),
                                      ["--force", "--sign", "-", "--generate-entitlement-der"])
        #expect(app["Foo"] == "d685833d68e3d5cbbc9b3286406d4aba85ef3827d73e2ee80a42317082d86ee8")
        #expect(framework["_CodeSignature/CodeDirectory"] == "dfc7e23e3e861c6ba61827b78a24a42f8139c6f2cf28c692cb4472cc2c8af89e")
    }

    @Test func signsAnExecutable() throws {
        let digests = try Self.sign("executable", Self.file(SyntheticMachO.machO(), named: "tool.bin"), ["--force", "--sign", "-"])
        #expect(digests == ["": "cb03fe2ab0e95bb62051ca5f6237d2dd885d38d2227df7ba30cb784733cb61e7"])
    }

    @Test func signsALibraryWithAnIdentifier() throws {
        let digests = try Self.sign("library", Self.file(SyntheticMachO.machO(executable: false, seed: 3), named: "libKit.dylib"),
                                    ["--force", "--sign", "-", "-i", "org.nomac.kit"])
        #expect(digests == ["": "693cda9afb8482113cfecc4214ef7fe00ce1717c54355ce4171810dce03f6004"])
    }

    /// codesign gave the same library with `--entitlements` the same bytes as without.
    @Test func leavesEntitlementsOutOfLibraries() throws {
        let digests = try Self.sign("library-entitlements", Self.file(SyntheticMachO.machO(executable: false, seed: 3), named: "libKit.dylib"),
                                    ["--force", "--sign", "-", "-i", "org.nomac.kit"], entitlements: Self.entitlements)
        #expect(digests == ["": "693cda9afb8482113cfecc4214ef7fe00ce1717c54355ce4171810dce03f6004"])
    }

    @Test func alignsTheSignatureAfterAnUnalignedLinkEditSegment() throws {
        let digests = try Self.sign("unaligned", Self.file(SyntheticMachO.machO(linkEditSize: 0x104, seed: 4), named: "odd.dylib"),
                                    ["--force", "--sign", "-"])
        #expect(digests == ["": "f35c0468094b58847a48d4fd845032c9a96b9103427cb6765b1a686dc9945c90"])
    }

    @Test func embedsEntitlementsInXMLAndDER() throws {
        let digests = try Self.sign("entitlements", Self.file(SyntheticMachO.machO(seed: 5), named: "ent"),
                                    ["--force", "--sign", "-", "--generate-entitlement-der"], entitlements: Self.entitlements)
        #expect(digests == ["": "0729b0bd9760dfd8f5e99cd0bafdb83c6a22b722acd12bda7c19b577fe038abf"])
    }

    /// The entitlements that set code directory `execSegFlags` (and two that set none).
    @Test func setsExecutableSegmentFlagsForEntitlements() throws {
        let entitlements = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>com.apple.private.amfi.can-execute-cdhash</key>
        \t<true/>
        \t<key>com.apple.private.amfi.can-load-cdhash</key>
        \t<true/>
        \t<key>com.apple.private.skip-library-validation</key>
        \t<true/>
        \t<key>com.apple.security.cs.allow-jit</key>
        \t<true/>
        \t<key>com.apple.security.cs.debugger</key>
        \t<true/>
        \t<key>dynamic-codesigning</key>
        \t<true/>
        </dict>
        </plist>

        """
        let digests = try Self.sign("entitlement-flags", Self.file(SyntheticMachO.machO(seed: 8), named: "flags"),
                                    ["--force", "--sign", "-", "--generate-entitlement-der"], entitlements: entitlements)
        #expect(digests == ["": "f07dfec5c525564b1a72d0d00b244892912e7d8e06f11ca4ae3677c251778469"])
    }

    /// The integers of `DERTests`, and a key of 200 bytes for the long length form.
    @Test func encodesEntitlementIntegersAsCodesignDoes() throws {
        let values = [0, 42, 128, 300, -1, -129, Int64.max, Int64.min]
        let entries = values.enumerated().map { "\t<key>i\($0.offset)</key>\n\t<integer>\($0.element)</integer>\n" }.joined()
        let entitlements = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \(entries)\t<key>\(String(repeating: "k", count: 200))</key>
        \t<true/>
        </dict>
        </plist>

        """
        let digests = try Self.sign("entitlement-integers", Self.file(SyntheticMachO.machO(seed: 12), named: "numbers"),
                                    ["--force", "--sign", "-", "--generate-entitlement-der"], entitlements: entitlements)
        #expect(digests == ["": "46fb7910c4c9eae5ac595f49f1c6aba3f93446d224a3dc50f599efdd252d9d6c"])
    }

    /// The DER blob is written without `--generate-entitlement-der` too: the same bytes as
    /// `embedsEntitlementsInXMLAndDER`.
    @Test func embedsDEREntitlementsWithoutTheOption() throws {
        let digests = try Self.sign("entitlements-no-der-option", Self.file(SyntheticMachO.machO(seed: 5), named: "ent"),
                                    ["--force", "--sign", "-"], entitlements: Self.entitlements)
        #expect(digests == ["": "0729b0bd9760dfd8f5e99cd0bafdb83c6a22b722acd12bda7c19b577fe038abf"])
    }

    @Test func leavesEntitlementsOutOfLoadableBundles() throws {
        let digests = try Self.sign("loadable-bundle-entitlements", Self.file(SyntheticMachO.machO(executable: false, fileType: 8, seed: 9),
                                                                             named: "plugin.so"),
                                    ["--force", "--sign", "-", "--generate-entitlement-der"], entitlements: Self.entitlements)
        #expect(digests == ["": "291f082b843c1b5df9c0eba67aa1f530a1ba9bbbd6c8c72cdd44808c543a7b4f"])
    }

    @Test func namesFilesAfterTheirStem() throws {
        let hidden = try Self.sign("identifier-hidden", Self.file(SyntheticMachO.machO(seed: 10), named: ".hidden"), ["--force", "--sign", "-"])
        #expect(hidden == ["": "9b1d2807544a442912d28a4e6b552d212fa176ff231b672e601278f3603db5b4"])
        let dots = try Self.sign("identifier-dots", Self.file(SyntheticMachO.machO(seed: 10), named: "a.b.c"), ["--force", "--sign", "-"])
        #expect(dots == ["": "98d2914de01f7642f941d61cc36a398e7762afdc46ebd942494798d943fefa48"])
    }

    @Test func signsAFileWithoutUUIDWithAnIdentifier() throws {
        let digests = try Self.sign("no-uuid-identifier", Self.file(SyntheticMachO.machO(uuid: false, seed: 11), named: "tool"),
                                    ["--force", "--sign", "-", "--identifier", "org.nomac.tool"])
        #expect(digests == ["": "567b4bf5e300ee1d0eb2b48e97d3c9a086f92a12921cb6d2b81a097e6c76a868"])
    }

    @Test func signsAFileWithoutUUID() throws {
        let digests = try Self.sign("no-uuid", Self.file(SyntheticMachO.machO(uuid: false, seed: 11), named: "tool"), ["--force", "--sign", "-"])
        #expect(digests == ["": "8597ddab867093556b0db79f2b8dd34b23392200e838c852dff32c789f920de3"])
    }

    /// Each slice signed as a thin file with the identifier of the arm64e slice.
    @Test func signsAUniversalFile() throws {
        let file = SyntheticMachO.universal([SyntheticMachO.machO(seed: 13), SyntheticMachO.machO(cpuSubtype: 0x8000_0002, seed: 14)])
        let digests = try Self.sign("universal", Self.file(file, named: "tool"), ["--force", "--sign", "-"])
        #expect(digests == ["": "f724d242f42f97b15e39f4b43759179a5310a8a03099d60871b965bbcc86379c"])
    }

    /// Code hashed in 4 KB pages, as for iOS below 16.0.
    @Test func hashesSmallerPagesBelowiOS16() throws {
        let digests = try Self.sign("ios15", Self.file(SyntheticMachO.machO(executable: false, minimumOS: 15 << 16, seed: 17), named: "lib15.dylib"),
                                    ["--force", "--sign", "-"])
        #expect(digests == ["": "8956f83a32f1b9a1f97115a4c265f217bb794d76a482a0f5ad311e9bacc9a053"])
    }

    /// A watch app's executable: arm64 for watchOS 26 and arm64_32 for watchOS 11, both with a
    /// SHA-1 code directory beside the SHA-256 one, since one slice is below watchOS 12.
    @Test func signsAWatchExecutable() throws {
        let file = SyntheticMachO.universal([SyntheticMachO.machO(platform: 4, minimumOS: 26 << 16, seed: 19),
                                             SyntheticMachO.machO(arm64_32: true, platform: 4, minimumOS: 11 << 16, seed: 20)])
        let digests = try Self.sign("watch", Self.file(file, named: "Watch"), ["--force", "--sign", "-", "--generate-entitlement-der"],
                                    entitlements: Self.entitlements)
        #expect(digests == ["": "12f2a44f5f641e2a986b52e017e3d8a47962babe0835a8ba70b3df20860cad57"])
    }

    /// 4 KB pages below watchOS 9.0.
    @Test func hashesSmallerPagesBelowWatchOS9() throws {
        let digests = try Self.sign("watch8", Self.file(SyntheticMachO.machO(arm64_32: true, platform: 4, minimumOS: 8 << 16, seed: 21), named: "old"),
                                    ["--force", "--sign", "-"])
        #expect(digests == ["": "fb94c05cadb1a61deaab4a53dbe10047611d7ff2b05eef6f2dc81c4e8b3eab87"])
    }

    static let embeddedInfo = Array("""
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
    	<key>CFBundleIdentifier</key>
    	<string>org.nomac.embedded</string>
    </dict>
    </plist>

    """.utf8)

    /// A library with its Info.plist linked in, as Swift's back-deployment libraries are.
    @Test func signsALibraryWithAnEmbeddedInfoPlist() throws {
        let file = SyntheticMachO.universal([SyntheticMachO.machO(executable: false, infoPlist: Self.embeddedInfo, seed: 15),
                                             SyntheticMachO.machO(executable: false, cpuSubtype: 0x8000_0002, infoPlist: Self.embeddedInfo, seed: 16)])
        let digests = try Self.sign("embedded-info-plist", Self.file(file, named: "libswiftThing.dylib"), ["--force", "--sign", "-", "--verbose"])
        #expect(digests == ["": "95483661037232b9e64f515a0b0d308abc61f686957159ec794eb7ee9c5b4e4b"])
        let temporary = try TemporaryDirectory(prefix: "nomac-signing")
        let url = try Self.file(file, named: "libswiftThing.dylib")(URL(fileURLWithPath: temporary.path))
        #expect(try CodeSigner.sign(CodeSigner.Request(path: url.path, identity: "-", verbose: true))
            == ["\(url.path): signed Mach-O universal (arm64e arm64) [org.nomac.embedded]"])
    }

    @Test func resignsKeepingIdentifierEntitlementsAndFlags() throws {
        let signed: (URL) throws -> URL = { directory in
            let url = try Self.file(SyntheticMachO.machO(seed: 6), named: "again.dylib")(directory)
            let entitlements = directory.appendingPathComponent("first.plist")
            try Data(Self.entitlements.utf8).write(to: entitlements)
            _ = try CodeSigner.sign(CodeSigner.Request(path: url.path, identity: "-", entitlementsPath: entitlements.path, identifier: "org.nomac.first"))
            return url
        }
        let digests = try Self.sign("resign", signed, ["--force", "--sign", "-", "--preserve-metadata=identifier,entitlements,flags",
                                                       "--generate-entitlement-der"])
        #expect(digests == ["": "209b1ffd87812565915b4985a62bd68e5670a360c95926367a71d5e298a813b6"])
    }

    @Test func signsABundle() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-signing")
        var expected = try SyntheticBundle.digests(of: try SyntheticBundle.application(in: URL(fileURLWithPath: temporary.path)))
        expected["Foo"] = "5b466b1ccef1b32b9a2c6f6610bcfb95e30a1986b00406b0c1a25084dc19c643"
        expected["_CodeSignature/CodeResources"] = "85c39ab86b5db6f8b3c61038f60b2a2aaef04d7b8234ec3ada549681dd2400b6"
        let digests = try Self.sign("bundle", SyntheticBundle.application, ["--force", "--sign", "-", "--generate-entitlement-der"])
        #expect(digests == expected)
    }

    @Test func refusesToReplaceASignatureWithoutForce() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-signing")
        let url = try Self.file(SyntheticMachO.machO(), named: "twice")(URL(fileURLWithPath: temporary.path))
        let request = CodeSigner.Request(path: url.path, identity: "-")
        #expect(try CodeSigner.sign(request) == [])
        #expect(throws: NomacError("is already signed", path: url.path)) { try CodeSigner.sign(request) }
        var forced = request
        forced.force = true
        forced.verbose = true
        let name = "twice-555549440112233445566778899aabbccddeef00"
        #expect(try CodeSigner.sign(forced) == ["\(url.path): replacing existing signature", "\(url.path): signed Mach-O thin (arm64) [\(name)]"])
    }
}
