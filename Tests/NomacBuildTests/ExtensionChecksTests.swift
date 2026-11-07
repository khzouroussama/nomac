import Foundation
import NomacCore
import NomacSigning
import NomacTestSupport
import NomacVerify
import Testing
@testable import NomacBuild

/// `nomac verify --build`'s `extension` checks (docs/VERIFICATION.md "Extension checks").
@Suite struct ExtensionChecksTests {
    @Test func findsTheInnermostNestedProduct() {
        let product = ExtensionChecks.nestedProduct(of:)
        #expect(product("Release-iphoneos/App.app/PlugIns/Share.appex/Info.plist") == "Release-iphoneos/App.app/PlugIns/Share.appex")
        #expect(product("Release-iphoneos/App.app/Extensions/Intents.appex/Intents") == "Release-iphoneos/App.app/Extensions/Intents.appex")
        #expect(product("Products/Applications/App.app/AppClips/Clip.app/Clip") == "Products/Applications/App.app/AppClips/Clip.app")
        #expect(product("Payload/App.app/Watch/Watch.app/Info.plist") == "Payload/App.app/Watch/Watch.app")
        #expect(product("Payload/App.app/Watch/Watch.app/PlugIns/Widget.appex/Widget") == "Payload/App.app/Watch/Watch.app/PlugIns/Widget.appex")
        #expect(product("dSYMs/Share.appex.dSYM/Contents/Info.plist") == "dSYMs/Share.appex.dSYM")
        #expect(product("dSYMs/Widget.appex 1.dSYM/Contents/Info.plist") == "dSYMs/Widget.appex 1.dSYM")
    }

    @Test func leavesOutWhatIsNotNested() {
        let product = ExtensionChecks.nestedProduct(of:)
        #expect(product("Release-iphoneos/App.app/App") == nil)
        #expect(product("Release-iphoneos/Share.appex/Share") == nil)
        #expect(product("Release-iphoneos/App.app/Frameworks/Kit.framework/Kit") == nil)
        #expect(product("Release-iphoneos/App.app/PlugIns/Readme.txt") == nil)
        #expect(product("Release-watchos/Watch.app/PlugIns/Widget.appex/Widget") == nil)
        #expect(product("dSYMs/App.app.dSYM/Contents/Info.plist") == nil)
    }

    @Test func aProductPassesByItsFiles() {
        let share = "Release-iphoneos/App.app/PlugIns/Share.appex"
        let action = "Release-iphoneos/App.app/PlugIns/Action.appex"
        let clip = "Release-iphoneos/App.app/AppClips/Clip.app"
        let checks = ExtensionChecks.checks([
            .init(path: "Release-iphoneos/App.app/App", outcome: .different(["not nested"])),
            .init(path: action + "/Action", outcome: .equivalent(["compiled"])),
            .init(path: action + "/Info.plist", outcome: .identical),
            .init(path: clip + "/Info.plist", outcome: .missing),
            .init(path: share + "/Info.plist", outcome: .identical),
        ], stage: "build", detailLimit: 10)
        #expect(checks.map(\.kind) == ["extension", "extension", "extension"])
        #expect(checks.map(\.name) == ["build " + clip, "build " + action, "build " + share])
        #expect(checks.map(\.status) == [.different, .equivalent, .identical])
        #expect(checks[0].detail == ["missing \(clip)/Info.plist"])
    }

    /// A bundle holding a bundle, its `CodeResources` recording `files2`.
    private func bundles(in root: String, executable: [UInt8], sealed: [String: Any]) throws {
        let product = root + "/App.app/PlugIns/Share.appex"
        try FileSystem.createDirectory(product)
        try FileSystem.createDirectory(root + "/App.app/_CodeSignature")
        try FileSystem.write(Data(executable), to: product + "/Share")
        try FileSystem.write(try PropertyListSerialization.data(fromPropertyList: ["CFBundleExecutable": "Share"], format: .xml, options: 0), to: product + "/Info.plist")
        try FileSystem.write(try PropertyListSerialization.data(fromPropertyList: ["files2": sealed], format: .xml, options: 0),
                             to: root + "/App.app/_CodeSignature/CodeResources")
    }

    /// What an app's `CodeResources` holds for an extension: each file's `hash2` (the `widget` experiment).
    private func sealedFiles(_ executable: [UInt8]) -> [String: Any] {
        ["PlugIns/Share.appex/Share": ["hash2": Data(SealedHashes.file(contents: executable))] as [String: Any]]
    }

    private static let code = Array("signed".utf8)
    private static let earlier = Array("signed earlier".utf8)

    @Test func aParentSealsTheFilesItsExtensionEndedUpWith() throws {
        let tmp = try TemporaryDirectory()
        try bundles(in: tmp.path + "/good", executable: Self.code, sealed: sealedFiles(Self.code))
        #expect(ExtensionChecks.sealProblem(root: tmp.path + "/good", product: "App.app/PlugIns/Share.appex") == nil)

        try bundles(in: tmp.path + "/stale", executable: Self.code, sealed: sealedFiles(Self.earlier))
        let problem = try #require(ExtensionChecks.sealProblem(root: tmp.path + "/stale", product: "App.app/PlugIns/Share.appex"))
        #expect(problem.contains("signed before it"))

        try bundles(in: tmp.path + "/absent", executable: Self.code, sealed: [:])
        let absent = try #require(ExtensionChecks.sealProblem(root: tmp.path + "/absent", product: "App.app/PlugIns/Share.appex"))
        #expect(absent.contains("does not seal"))
    }

    @Test func aStaleSealFailsTheCheckUnlessXcodesHasTheSameProblem() throws {
        let tmp = try TemporaryDirectory()
        try bundles(in: tmp.path + "/xcode", executable: Self.code, sealed: sealedFiles(Self.code))
        try bundles(in: tmp.path + "/nomac", executable: Self.code, sealed: sealedFiles(Self.earlier))
        let results = [BuildProducts.FileResult(path: "App.app/PlugIns/Share.appex/Share", outcome: .equivalent(["compiled"]))]
        let failed = ExtensionChecks.checks(results, stage: "ipa", seals: (tmp.path + "/xcode", tmp.path + "/nomac"), detailLimit: 10)
        #expect(failed.map(\.status) == [.different])
        let same = ExtensionChecks.checks(results, stage: "ipa", seals: (tmp.path + "/nomac", tmp.path + "/nomac"), detailLimit: 10)
        #expect(same.map(\.status) == [.equivalent])
    }
}
