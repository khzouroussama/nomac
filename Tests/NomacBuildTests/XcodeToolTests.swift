import Foundation
import Testing
@testable import NomacBuild
import NomacBuildService
import NomacCore
import NomacTestSupport

@Suite struct TAPIStubTests {
    private func stub(_ dylib: SyntheticDylib) throws -> String {
        let tmp = try TemporaryDirectory()
        try dylib.write(to: tmp.path + "/libNomac.dylib")
        try TAPITool.run(["stubify", "-isysroot", "/sdk", "-F/products", "-L/products", tmp.path + "/libNomac.dylib", "-o", tmp.path + "/stub.tbd"])
        return String(decoding: FileManager.default.contents(atPath: tmp.path + "/stub.tbd") ?? Data(), as: UTF8.self)
    }

    /// Every `tapi_experiments.py` variant nomac reproduces, with the TBD Xcode 27.0's tapi wrote
    /// for it, byte for byte.
    static let observed: [(String, SyntheticDylib, String)] = [
        ("function", SyntheticDylib(exports: [.init(name: "_nomac_function", place: .text)]),
         #"{"main_library":{"compatibility_versions":[{"version":"0"}],"current_versions":[{"version":"0"}],"exported_symbols":[{"text":{"global":["_nomac_function"]}}],"flags":[{"attributes":["not_app_extension_safe"]}],"install_names":[{"name":"@rpath/libNomac.dylib"}],"target_info":[{"min_deployment":"15","target":"arm64-ios"}]},"tapi_tbd_version":5}"# + "\n"),
        ("data", SyntheticDylib(exports: [.init(name: "_nomac_constant", place: .constant), .init(name: "_nomac_data", place: .data)]),
         #"{"main_library":{"compatibility_versions":[{"version":"0"}],"current_versions":[{"version":"0"}],"exported_symbols":[{"data":{"global":["_nomac_constant","_nomac_data"]}}],"flags":[{"attributes":["not_app_extension_safe"]}],"install_names":[{"name":"@rpath/libNomac.dylib"}],"target_info":[{"min_deployment":"15","target":"arm64-ios"}]},"tapi_tbd_version":5}"# + "\n"),
        ("function-and-data", SyntheticDylib(exports: [.init(name: "_nomac_function", place: .text), .init(name: "_nomac_constant", place: .constant), .init(name: "_nomac_data", place: .data)]),
         #"{"main_library":{"compatibility_versions":[{"version":"0"}],"current_versions":[{"version":"0"}],"exported_symbols":[{"data":{"global":["_nomac_constant","_nomac_data"]},"text":{"global":["_nomac_function"]}}],"flags":[{"attributes":["not_app_extension_safe"]}],"install_names":[{"name":"@rpath/libNomac.dylib"}],"target_info":[{"min_deployment":"15","target":"arm64-ios"}]},"tapi_tbd_version":5}"# + "\n"),
        ("weak", SyntheticDylib(exports: [.init(name: "_nomac_weak", place: .text, flags: 4)]),
         #"{"main_library":{"compatibility_versions":[{"version":"0"}],"current_versions":[{"version":"0"}],"exported_symbols":[{"text":{"weak":["_nomac_weak"]}}],"flags":[{"attributes":["not_app_extension_safe"]}],"install_names":[{"name":"@rpath/libNomac.dylib"}],"target_info":[{"min_deployment":"15","target":"arm64-ios"}]},"tapi_tbd_version":5}"# + "\n"),
        ("weak-data", SyntheticDylib(exports: [.init(name: "_nomac_weak_data", place: .data, flags: 4)]),
         #"{"main_library":{"compatibility_versions":[{"version":"0"}],"current_versions":[{"version":"0"}],"exported_symbols":[{"data":{"weak":["_nomac_weak_data"]}}],"flags":[{"attributes":["not_app_extension_safe"]}],"install_names":[{"name":"@rpath/libNomac.dylib"}],"target_info":[{"min_deployment":"15","target":"arm64-ios"}]},"tapi_tbd_version":5}"# + "\n"),
        ("thread-local", SyntheticDylib(exports: [.init(name: "_nomac_thread_local", place: .data, flags: 1)]),
         #"{"main_library":{"compatibility_versions":[{"version":"0"}],"current_versions":[{"version":"0"}],"exported_symbols":[{"data":{"thread_local":["_nomac_thread_local"]}}],"flags":[{"attributes":["not_app_extension_safe"]}],"install_names":[{"name":"@rpath/libNomac.dylib"}],"target_info":[{"min_deployment":"15","target":"arm64-ios"}]},"tapi_tbd_version":5}"# + "\n"),
        ("objc-class", SyntheticDylib(exports: [.init(name: "_OBJC_CLASS_$_NomacClass", place: .data), .init(name: "_OBJC_METACLASS_$_NomacClass", place: .data)]),
         #"{"main_library":{"compatibility_versions":[{"version":"0"}],"current_versions":[{"version":"0"}],"exported_symbols":[{"data":{"objc_class":["NomacClass"]}}],"flags":[{"attributes":["not_app_extension_safe"]}],"install_names":[{"name":"@rpath/libNomac.dylib"}],"target_info":[{"min_deployment":"15","target":"arm64-ios"}]},"tapi_tbd_version":5}"# + "\n"),
        ("objc-ivars", SyntheticDylib(exports: ["_OBJC_CLASS_$_NomacIvars", "_OBJC_IVAR_$_NomacIvars._protected", "_OBJC_IVAR_$_NomacIvars._public",
                                                "_OBJC_METACLASS_$_NomacIvars"].map { .init(name: $0, place: .data) }),
         #"{"main_library":{"compatibility_versions":[{"version":"0"}],"current_versions":[{"version":"0"}],"exported_symbols":[{"data":{"objc_class":["NomacIvars"],"objc_ivar":["NomacIvars._protected","NomacIvars._public"]}}],"flags":[{"attributes":["not_app_extension_safe"]}],"install_names":[{"name":"@rpath/libNomac.dylib"}],"target_info":[{"min_deployment":"15","target":"arm64-ios"}]},"tapi_tbd_version":5}"# + "\n"),
        ("objc-exception-type", SyntheticDylib(exports: ["_OBJC_CLASS_$_NomacException", "_OBJC_EHTYPE_$_NomacException",
                                                         "_OBJC_METACLASS_$_NomacException"].map { .init(name: $0, place: .data) }),
         #"{"main_library":{"compatibility_versions":[{"version":"0"}],"current_versions":[{"version":"0"}],"exported_symbols":[{"data":{"objc_class":["NomacException"],"objc_eh_type":["NomacException"]}}],"flags":[{"attributes":["not_app_extension_safe"]}],"install_names":[{"name":"@rpath/libNomac.dylib"}],"target_info":[{"min_deployment":"15","target":"arm64-ios"}]},"tapi_tbd_version":5}"# + "\n"),
        ("no-exports", SyntheticDylib(exports: []),
         #"{"main_library":{"compatibility_versions":[{"version":"0"}],"current_versions":[{"version":"0"}],"flags":[{"attributes":["not_app_extension_safe"]}],"install_names":[{"name":"@rpath/libNomac.dylib"}],"target_info":[{"min_deployment":"15","target":"arm64-ios"}]},"tapi_tbd_version":5}"# + "\n"),
        ("versions", SyntheticDylib(exports: [.init(name: "_nomac_function", place: .text)], currentVersion: 0x0002_0304, compatibilityVersion: 0x0001_0200),
         #"{"main_library":{"compatibility_versions":[{"version":"1.2"}],"current_versions":[{"version":"2.3.4"}],"exported_symbols":[{"text":{"global":["_nomac_function"]}}],"flags":[{"attributes":["not_app_extension_safe"]}],"install_names":[{"name":"@rpath/libNomac.dylib"}],"target_info":[{"min_deployment":"15","target":"arm64-ios"}]},"tapi_tbd_version":5}"# + "\n"),
        ("versions-1.0", SyntheticDylib(exports: [.init(name: "_nomac_function", place: .text)], currentVersion: 0x0001_0000, compatibilityVersion: 0x0001_0000),
         #"{"main_library":{"exported_symbols":[{"text":{"global":["_nomac_function"]}}],"flags":[{"attributes":["not_app_extension_safe"]}],"install_names":[{"name":"@rpath/libNomac.dylib"}],"target_info":[{"min_deployment":"15","target":"arm64-ios"}]},"tapi_tbd_version":5}"# + "\n"),
        ("current-1.0", SyntheticDylib(exports: [.init(name: "_nomac_function", place: .text)], currentVersion: 0x0001_0000, compatibilityVersion: 0x0001_0200),
         #"{"main_library":{"compatibility_versions":[{"version":"1.2"}],"exported_symbols":[{"text":{"global":["_nomac_function"]}}],"flags":[{"attributes":["not_app_extension_safe"]}],"install_names":[{"name":"@rpath/libNomac.dylib"}],"target_info":[{"min_deployment":"15","target":"arm64-ios"}]},"tapi_tbd_version":5}"# + "\n"),
        ("compatibility-1.0", SyntheticDylib(exports: [.init(name: "_nomac_function", place: .text)], currentVersion: 0x0002_0000, compatibilityVersion: 0x0001_0000),
         #"{"main_library":{"current_versions":[{"version":"2"}],"exported_symbols":[{"text":{"global":["_nomac_function"]}}],"flags":[{"attributes":["not_app_extension_safe"]}],"install_names":[{"name":"@rpath/libNomac.dylib"}],"target_info":[{"min_deployment":"15","target":"arm64-ios"}]},"tapi_tbd_version":5}"# + "\n"),
        ("extension-safe", SyntheticDylib(exports: [.init(name: "_nomac_function", place: .text)], flags: MachODylib.appExtensionSafeFlag),
         #"{"main_library":{"compatibility_versions":[{"version":"0"}],"current_versions":[{"version":"0"}],"exported_symbols":[{"text":{"global":["_nomac_function"]}}],"install_names":[{"name":"@rpath/libNomac.dylib"}],"target_info":[{"min_deployment":"15","target":"arm64-ios"}]},"tapi_tbd_version":5}"# + "\n"),
        ("minos-15.4", SyntheticDylib(exports: [.init(name: "_nomac_function", place: .text)], minimumOS: 0x000f_0400),
         #"{"main_library":{"compatibility_versions":[{"version":"0"}],"current_versions":[{"version":"0"}],"exported_symbols":[{"text":{"global":["_nomac_function"]}}],"flags":[{"attributes":["not_app_extension_safe"]}],"install_names":[{"name":"@rpath/libNomac.dylib"}],"target_info":[{"min_deployment":"15.4","target":"arm64-ios"}]},"tapi_tbd_version":5}"# + "\n"),
        ("minos-16.0.1", SyntheticDylib(exports: [.init(name: "_nomac_function", place: .text)], minimumOS: 0x0010_0001),
         #"{"main_library":{"compatibility_versions":[{"version":"0"}],"current_versions":[{"version":"0"}],"exported_symbols":[{"text":{"global":["_nomac_function"]}}],"flags":[{"attributes":["not_app_extension_safe"]}],"install_names":[{"name":"@rpath/libNomac.dylib"}],"target_info":[{"min_deployment":"16.0.1","target":"arm64-ios"}]},"tapi_tbd_version":5}"# + "\n"),
        ("swift-function", SyntheticDylib(exports: [.init(name: "_$s5Nomac13nomacFunctionSiyF", place: .text)], swiftABI: 7),
         #"{"main_library":{"compatibility_versions":[{"version":"0"}],"current_versions":[{"version":"0"}],"exported_symbols":[{"data":{"global":["_$s5Nomac13nomacFunctionSiyF"]}}],"flags":[{"attributes":["not_app_extension_safe"]}],"install_names":[{"name":"@rpath/libNomac.dylib"}],"swift_abi":[{"abi":7}],"target_info":[{"min_deployment":"15","target":"arm64-ios"}]},"tapi_tbd_version":5}"# + "\n"),
        ("swift-and-c", SyntheticDylib(exports: [.init(name: "_$s5Nomac13nomacFunctionSiyF", place: .text), .init(name: "_nomac_constant", place: .constant), .init(name: "_nomac_data", place: .data), .init(name: "_nomac_function", place: .text)], swiftABI: 7),
         #"{"main_library":{"compatibility_versions":[{"version":"0"}],"current_versions":[{"version":"0"}],"exported_symbols":[{"data":{"global":["_$s5Nomac13nomacFunctionSiyF","_nomac_constant","_nomac_data"]},"text":{"global":["_nomac_function"]}}],"flags":[{"attributes":["not_app_extension_safe"]}],"install_names":[{"name":"@rpath/libNomac.dylib"}],"swift_abi":[{"abi":7}],"target_info":[{"min_deployment":"15","target":"arm64-ios"}]},"tapi_tbd_version":5}"# + "\n"),
    ]

    @Test func writesWhatXcodesTapiWroteForEachExperiment() throws {
        for (name, dylib, expected) in Self.observed {
            #expect(try stub(dylib) == expected, "\(name)")
        }
    }

    @Test func refusesWhatNoExperimentCovered() throws {
        // A re-export and a weak thread-local symbol (B-106).
        for exports in [[SyntheticDylib.Export(name: "_reexported", place: .text, flags: 0x8)],
                        [SyntheticDylib.Export(name: "_weak_thread_local", place: .data, flags: 0x5)]] {
            #expect(throws: NomacError.self) { try stub(SyntheticDylib(exports: exports)) }
        }
    }

    /// Swift Build's GenerateTAPI also passes -iframework and --inline-private-frameworks, which
    /// did not change tapi's output (`swift-build-options`).
    @Test func takesSwiftBuildsOptions() throws {
        let tmp = try TemporaryDirectory()
        try SyntheticDylib(exports: [.init(name: "_nomac_function", place: .text)]).write(to: tmp.path + "/libNomac.dylib")
        try TAPITool.run(["stubify", "-isysroot", "/sdk", "-iframework", "/sdk/System/Library/Frameworks", "--inline-private-frameworks",
                          tmp.path + "/libNomac.dylib", "-o", tmp.path + "/stub.tbd"])
        let written = String(decoding: FileManager.default.contents(atPath: tmp.path + "/stub.tbd") ?? Data(), as: UTF8.self)
        #expect(written == Self.observed.first { $0.0 == "function" }?.2)
    }

    @Test func refusesOtherTapiCommands() {
        #expect(throws: NomacError.self) { try TAPITool.run(["installapi", "-o", "/tmp/x.tbd"]) }
    }
}

@Suite struct DSYMInfoPlistTests {
    @Test func takesTheBundleValuesAsDsymutilDoesOnMacOS() throws {
        let tmp = try TemporaryDirectory()
        let framework = tmp.path + "/Engine.framework"
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.charcoaldesign.Engine", "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0"], format: .binary, options: 0)
        try FileSystem.write(plist, to: framework + "/Info.plist")
        try FileSystem.write(Data("binary".utf8), to: framework + "/Engine")
        try DSYMInfoPlist.rewrite(bundleRoot: tmp.path + "/Engine.framework.dSYM", executable: framework + "/Engine", toolchain: nil)
        // Xcode 27.0's dSYM of retro-rampage's Engine (Release).
        let expected = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            \t<dict>
            \t\t<key>CFBundleDevelopmentRegion</key>
            \t\t<string>English</string>
            \t\t<key>CFBundleIdentifier</key>
            \t\t<string>com.apple.xcode.dsym.com.charcoaldesign.Engine</string>
            \t\t<key>CFBundleInfoDictionaryVersion</key>
            \t\t<string>6.0</string>
            \t\t<key>CFBundlePackageType</key>
            \t\t<string>dSYM</string>
            \t\t<key>CFBundleSignature</key>
            \t\t<string>????</string>
            \t\t<key>CFBundleShortVersionString</key>
            \t\t<string>1.0</string>
            \t\t<key>CFBundleVersion</key>
            \t\t<string>1</string>
            \t</dict>
            </plist>

            """
        #expect(String(decoding: FileManager.default.contents(atPath: tmp.path + "/Engine.framework.dSYM/Contents/Info.plist") ?? Data(), as: UTF8.self) == expected)
    }

    /// dsymutil takes the nearest enclosing bundle with an identifier, and its versions.
    @Test func readsTheNearestBundlesIdentifierAndVersions() throws {
        let tmp = try TemporaryDirectory()
        let app = tmp.path + "/App.app"
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.example.App", "CFBundleVersion": "42", "CFBundleShortVersionString": "3.1"], format: .binary, options: 0)
        try FileSystem.write(plist, to: app + "/Info.plist")
        // A directory without an identifier on the way up is passed over.
        try FileSystem.write(try PropertyListSerialization.data(fromPropertyList: ["CFBundleName": "Inner"], format: .binary, options: 0), to: app + "/Inner/Info.plist")
        try FileSystem.write(Data("binary".utf8), to: app + "/Inner/Tool")
        let info = DSYMInfoPlist.bundleInfo(executable: app + "/Inner/Tool")
        #expect(info == DSYMInfoPlist.BundleInfo(identifier: "com.example.App", version: "42", shortVersion: "3.1"))
        let text = DSYMInfoPlist.render(info, bundleRoot: tmp.path + "/Tool.dSYM", toolchain: nil)
        #expect(text.contains("\t\t<key>CFBundleShortVersionString</key>\n\t\t<string>3.1</string>\n\t\t<key>CFBundleVersion</key>\n\t\t<string>42</string>\n"))
    }

    /// The arguments Swift Build gives dsymutil (`<binary> -o <dSYM>`) and the other spellings.
    @Test func findsTheDSYMDsymutilWrote() {
        let plan = DsymutilTool.infoPlist(["/p/Engine.framework/Engine", "-o", "/p/Engine.framework.dSYM"])
        #expect(plan?.bundleRoot == "/p/Engine.framework.dSYM" && plan?.executable == "/p/Engine.framework/Engine" && plan?.toolchain == nil)
        #expect(DsymutilTool.infoPlist(["--out=/o/X.dSYM", "/p/X", "--toolchain", "T"])?.bundleRoot == "/o/X.dSYM")
        #expect(DsymutilTool.infoPlist(["--out=/o/X.dSYM", "/p/X", "--toolchain", "T"])?.toolchain == "T")
        #expect(DsymutilTool.infoPlist(["/p/X"])?.bundleRoot == "/p/X.dSYM")
        #expect(DsymutilTool.infoPlist(["-j", "4", "/p/X", "-o", "/o/X.dSYM"])?.executable == "/p/X")
        #expect(DsymutilTool.infoPlist(["--flat", "/p/X"]) == nil)
        #expect(DsymutilTool.infoPlist(["/p/X", "/p/Y"]) == nil)
    }

    @Test func fallsBackToTheDSYMNameWithoutABundle() {
        let info = DSYMInfoPlist.bundleInfo(executable: "/nonexistent/libNomac.dylib")
        let text = DSYMInfoPlist.render(info, bundleRoot: "/out/libNomac.dylib.dSYM", toolchain: "org.swift.toolchain")
        #expect(text.contains("<string>com.apple.xcode.dsym.libNomac.dylib</string>"))
        #expect(text.contains("\t\t<key>Toolchain</key>\n\t\t<string>org.swift.toolchain</string>\n"))
    }
}

@Suite struct AppIntentsToolsTests {
    @Test func writesTheEmptyStringsDataOfATargetWithoutAppIntents() throws {
        let tmp = try TemporaryDirectory()
        try SyntheticDylib(exports: [.init(name: "_f", place: .text)], loadedLibraries: ["/usr/lib/libSystem.B.dylib"]).write(to: tmp.path + "/Engine")
        try AppIntentsTools.extractMetadata(["--module-name", "Engine", "--binary-file", tmp.path + "/Engine",
                                             "--stringsdata-file", tmp.path + "/ExtractedAppShortcutsMetadata.stringsdata",
                                             "--compile-time-extraction", "--no-app-shortcuts-localization"])
        // retro-rampage's Engine, Xcode 27.0: 86 bytes, no final newline.
        let written = FileManager.default.contents(atPath: tmp.path + "/ExtractedAppShortcutsMetadata.stringsdata") ?? Data()
        #expect(written == Data("{\n  \"source\" : \"ExtractedAppShortcutsMetadata\",\n  \"tables\" : {\n\n  },\n  \"version\" : 2\n}".utf8))
        #expect(written.count == 86)
    }

    @Test func refusesATargetThatUsesAppIntents() throws {
        let tmp = try TemporaryDirectory()
        try SyntheticDylib(exports: [.init(name: "_f", place: .text)], fileType: 2,
                           loadedLibraries: ["/System/Library/Frameworks/AppIntents.framework/AppIntents"]).write(to: tmp.path + "/App")
        #expect(throws: NomacError.self) {
            try AppIntentsTools.extractMetadata(["--binary-file", tmp.path + "/App", "--stringsdata-file", tmp.path + "/out.stringsdata"])
        }
    }

    /// A thin arm64 object whose one load command is an `LC_LINKER_OPTION` with `options`.
    private func object(linkerOptions options: [String]) -> [UInt8] {
        func word(_ value: Int) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) } }
        var strings: [UInt8] = options.flatMap { Array($0.utf8) + [0] }
        while (12 + strings.count) % 8 != 0 { strings.append(0) }
        let command = word(0x2d) + word(12 + strings.count) + word(options.count) + strings
        return word(0xfeed_facf) + word(0x0100_000c) + word(0) + word(1) + word(1) + word(command.count) + word(0) + word(0) + command
    }

    /// A static library of `members`, as `ar` lays them out.
    private func archive(_ members: [(String, [UInt8])]) -> [UInt8] {
        members.reduce(Array("!<arch>\n".utf8)) { bytes, member in
            let field = { (text: String, width: Int) in Array(text.padding(toLength: width, withPad: " ", startingAt: 0).utf8) }
            return bytes + field(member.0, 16) + field("0", 12) + field("0", 6) + field("0", 6) + field("644", 8)
                + field("\(member.1.count)", 10) + Array("`\n".utf8) + member.1
        }
    }

    /// expo-default's 17 pods' static libraries, Xcode 27.0: "Extracted no relevant App Intents
    /// symbols, skipping", and the same strings data as for an image without App Intents.
    @Test func readsTheObjectsOfAStaticLibrary() throws {
        let tmp = try TemporaryDirectory()
        let options = ["--binary-file", tmp.path + "/libExpoDevice.a", "--stringsdata-file", tmp.path + "/out.stringsdata"]
        try FileSystem.write(Data(archive([("Device.o", object(linkerOptions: ["-framework", "UIKit"]))])), to: tmp.path + "/libExpoDevice.a")
        try AppIntentsTools.extractMetadata(options)
        #expect(FileManager.default.contents(atPath: tmp.path + "/out.stringsdata") == Data(AppIntentsTools.emptyStringsData.utf8))
        try FileSystem.write(Data(archive([("Device.o", object(linkerOptions: ["-framework", "UIKit"])),
                                           ("Intents.o", object(linkerOptions: ["-framework", "AppIntents"]))])), to: tmp.path + "/libExpoDevice.a")
        #expect(throws: NomacError.self) { try AppIntentsTools.extractMetadata(options) }
    }

    /// Swift Build lists every bundle dependency's extract.actionsdata whether or not it exists
    /// (Rampage depends on Engine and Renderer, which have none).
    @Test func passesOverListedMetadataThatDoesNotExist() throws {
        let tmp = try TemporaryDirectory()
        let list = tmp.path + "/Rampage.DependencyMetadataFileList"
        try FileSystem.write(Data("\(tmp.path)/Engine.framework/Metadata.appintents/extract.actionsdata\n\(tmp.path)/Renderer.framework/Metadata.appintents/extract.actionsdata\n".utf8), to: list)
        try AppIntentsTools.trainShortcuts(["--metadata-file-list", list, "--extracted-metadata-path", tmp.path + "/Rampage.app/Metadata.appintents"], developerDirectory: nil)
        try SyntheticDylib(exports: [], fileType: 2).write(to: tmp.path + "/Rampage")
        try AppIntentsTools.extractMetadata(["--binary-file", tmp.path + "/Rampage", "--stringsdata-file", tmp.path + "/out.stringsdata",
                                             "--metadata-file-list", list, "--static-metadata-file-list", list])
        #expect(FileManager.default.fileExists(atPath: tmp.path + "/out.stringsdata"))
    }

    /// A dependency's metadata adds nothing to a target that uses none of its types, and trains
    /// nothing without App Shortcuts (`embedded`); a dependency's App Shortcuts are refused, and
    /// a training without the options Xcode's build passes.
    @Test func refusesMetadataItDoesNotReproduce() throws {
        let tmp = try TemporaryDirectory()
        let actions = tmp.path + "/Engine.framework/Metadata.appintents/extract.actionsdata"
        try FileSystem.write(Data("{}".utf8), to: actions)
        try FileSystem.write(Data((actions + "\n").utf8), to: tmp.path + "/list")
        try SyntheticDylib(exports: [], fileType: 2).write(to: tmp.path + "/Rampage")
        try AppIntentsTools.trainShortcuts(["--metadata-file-list", tmp.path + "/list"], developerDirectory: nil)
        try AppIntentsTools.extractMetadata(["--binary-file", tmp.path + "/Rampage", "--stringsdata-file", tmp.path + "/out.stringsdata",
                                             "--metadata-file-list", tmp.path + "/list"])
        try AppIntentsTools.trainShortcuts(["--extracted-metadata-path", tmp.path + "/Engine.framework/Metadata.appintents"], developerDirectory: nil)
        try FileSystem.write(Data(#"{"autoShortcuts":[{"actionIdentifier":"Open"}]}"#.utf8), to: actions)
        #expect(throws: NomacError.self) {
            try AppIntentsTools.trainShortcuts(["--metadata-file-list", tmp.path + "/list"], developerDirectory: nil)
        }
        #expect(throws: NomacError.self) {
            try AppIntentsTools.trainShortcuts(["--extracted-metadata-path", tmp.path + "/Engine.framework/Metadata.appintents"], developerDirectory: nil)
        }
    }

    /// watchOS products are universal, arm64 and arm64_32 (`watch`): their 64-bit slices decide,
    /// a universal file without one is refused.
    @Test func readsUniversalFilesBy64BitSlice() throws {
        func universal(_ slices: [(cpu: UInt32, bytes: [UInt8])]) -> [UInt8] {
            func be32(_ value: UInt32) -> [UInt8] { withUnsafeBytes(of: value.bigEndian) { Array($0) } }
            var header = be32(0xcafe_babe) + be32(UInt32(slices.count))
            var offset = 8 + 20 * slices.count
            var body: [UInt8] = []
            for slice in slices {
                header += be32(slice.cpu) + be32(0) + be32(UInt32(offset)) + be32(UInt32(slice.bytes.count)) + be32(0)
                body += slice.bytes
                offset += slice.bytes.count
            }
            return header + body
        }
        let arm64: [UInt8] = [0xcf, 0xfa, 0xed, 0xfe, 1]
        #expect(try AppIntentsTools.slices(universal([(0x0200_000c, [0xce, 0xfa, 0xed, 0xfe]), (0x0100_000c, arm64)]), path: "x") == [arm64])
        #expect(try AppIntentsTools.slices(arm64, path: "x") == [arm64])
        #expect(throws: NomacError.self) { try AppIntentsTools.slices(universal([(0x0200_000c, [0xce, 0xfa, 0xed, 0xfe])]), path: "x") }
    }

    /// gomap's `Go Map!!` target: Swift Build escapes the constant values list's paths.
    @Test func readsTheEscapedConstantValuesList() {
        #expect(AppIntentsTools.constValuesList("/d/Go\\ Map\\!\\!.build/Go\\ Map\\!\\!-primary.swiftconstvalues\n/d/App.swiftconstvalues\n")
            == ["/d/Go Map!!.build/Go Map!!-primary.swiftconstvalues", "/d/App.swiftconstvalues"])
    }

    @Test func trainsNothingWithoutShortcuts() throws {
        let tmp = try TemporaryDirectory()
        try FileSystem.write(Data(), to: tmp.path + "/Engine.DependencyMetadataFileList")
        try AppIntentsTools.trainShortcuts(["--temp-dir-path", tmp.path + "/ssu", "--extracted-metadata-path", tmp.path + "/Engine.framework/Metadata.appintents",
                                            "--metadata-file-list", tmp.path + "/Engine.DependencyMetadataFileList", "--archive-ssu-assets"], developerDirectory: nil)
        #expect(!FileManager.default.fileExists(atPath: tmp.path + "/ssu"))
    }
}

@Suite struct BuildRequestTests {
    /// What xcodebuild handed Swift Build for retro-rampage's `Engine` scheme (Release, generic
    /// iOS), in the JSON form of its build-request.json.
    @Test func makesXcodebuildsRequest() throws {
        let locations = BuildLocations(derivedDataPath: "/dd", buildProductsPath: "/dd/Build/Products", buildIntermediatesPath: "/dd/Build/Intermediates.noindex",
                                       pchPath: "/dd/Build/Intermediates.noindex/PrecompiledHeaders", indexPCHPath: "/dd/Index.noindex/PrecompiledHeaders")
        let destination = RunDestination(platform: "iphoneos", sdk: "iphoneos", sdkVariant: "iphoneos", targetArchitecture: "undefined_arch",
                                         supportedArchitectures: ["arm64", "arm64e", "armv7", "armv7s"], disableOnlyActiveArch: true)
        let settings = SettingsRequest(configuration: "Release", destination: destination, locations: locations, overrides: ["CODE_SIGNING_ALLOWED": "NO"])
        let request = BuildOperation.buildRequest(.init(targets: [WorkspaceTarget(guid: "G", name: "Engine")], settings: settings, containerPath: "/src/Rampage.xcodeproj"),
                                                  sdkCanonicalName: "iphoneos27.0")
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(json["containerPath"] as? String == "/src/Rampage.xcodeproj")
        #expect(json["generatePrecompiledModulesReport"] == nil)
        #expect(json["useImplicitDependencies"] as? Bool == true && json["useParallelTargets"] as? Bool == true)
        #expect(json["hideShellScriptEnvironment"] as? Bool == false)
        #expect(json["continueBuildingAfterErrors"] as? Bool == false)
        let targets = try #require(json["configuredTargets"] as? [[String: Any]])
        #expect(targets.map { $0["guid"] as? String } == ["G"])
        #expect(targets[0]["parameters"] == nil)
        let parameters = try #require(json["parameters"] as? [String: Any])
        let run = try #require(parameters["activeRunDestination"] as? [String: Any])
        #expect(run["sdk"] as? String == "iphoneos27.0")
        #expect(run["supportedArchitectures"] as? [String] == ["armv4t", "armv5", "armv6", "armv7", "armv7f", "armv7s", "armv7k", "arm64", "arm64e"])
        let arena = try #require(parameters["arenaInfo"] as? [String: Any])
        #expect(arena["indexDataStoreFolderPath"] as? String == "/dd/Index.noindex/DataStore")
        #expect(arena["indexEnableDataStore"] as? Bool == true)
        let overrides = try #require(parameters["overrides"] as? [String: Any])
        #expect((overrides["synthesized"] as? [String: Any])?["table"] as? [String: String] == ["ACTION": "build", "ENABLE_PREVIEWS": "NO", "ENABLE_XOJIT_PREVIEWS": "YES"])
        #expect((overrides["commandLine"] as? [String: Any])?["table"] as? [String: String] == ["CODE_SIGNING_ALLOWED": "NO"])
    }

    /// xcodebuild archive's request (retro-rampage's `Rampage`, nomac's identical to it).
    @Test func makesXcodebuildArchivesRequest() throws {
        let locations = BuildLocations(derivedDataPath: "/dd", buildProductsPath: "/dd/Build/Products", buildIntermediatesPath: "/dd/Build/Intermediates.noindex",
                                       pchPath: "/dd/Build/Intermediates.noindex/PrecompiledHeaders", indexPCHPath: "/dd/Index.noindex/PrecompiledHeaders")
        let settings = SettingsRequest(action: "install", configuration: "Release", destination: nil, locations: locations, overrides: [:])
        let request = BuildOperation.buildRequest(.init(targets: [WorkspaceTarget(guid: "G", name: "Rampage")], settings: settings,
                                                        containerPath: "/src/Rampage.xcodeproj", archivedScheme: "Rampage"),
                                                  sdkCanonicalName: nil)
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(json["schemeCommand"] as? String == "archive")
        #expect((json["buildCommand"] as? [String: Any])?["style"] as? String == "buildAndRun")
        let parameters = try #require(json["parameters"] as? [String: Any])
        #expect(parameters["action"] as? String == "install")
        let archive = "/dd/Build/Intermediates.noindex/ArchiveIntermediates/Rampage"
        let synthesized = (parameters["overrides"] as? [String: Any]).flatMap { ($0["synthesized"] as? [String: Any])?["table"] as? [String: String] }
        #expect(synthesized == [
            "ACTION": "install", "ASSET_PACK_FOLDER_PATH": archive + "/InstallationBuildProductsLocation/OnDemandResources",
            "ASSETCATALOG_COMPILER_FLATTENED_APP_ICON_PATH": archive + "/BuildProductsPath/ProductIcon.png", "DEPLOYMENT_LOCATION": "YES",
            "DEPLOYMENT_POSTPROCESSING": "YES", "DSTROOT": archive + "/InstallationBuildProductsLocation", "EMBED_ASSET_PACKS_IN_PRODUCT_BUNDLE": "NO",
            "ENABLE_PREVIEWS": "NO", "ENABLE_SIGNATURE_AGGREGATION": "YES", "ENABLE_XOJIT_PREVIEWS": "YES", "INDEX_ENABLE_DATA_STORE": "NO",
            "MESSAGES_APPLICATION_EXTENSION_SUPPORT_FOLDER_PATH": archive + "/BuildProductsPath/MessagesApplicationExtensionSupport",
            "MESSAGES_APPLICATION_SUPPORT_FOLDER_PATH": archive + "/BuildProductsPath/MessagesApplicationSupport",
            "OBJROOT": archive + "/IntermediateBuildFilesPath", "SHARED_PRECOMPS_DIR": archive + "/PrecompiledHeaders",
            "SIGNATURE_METADATA_FOLDER_PATH": archive + "/BuildProductsPath/Signatures",
            "SWIFT_STDLIB_TOOL_UNSIGNED_DESTINATION_DIR": archive + "/BuildProductsPath/SwiftSupport", "SYMROOT": archive + "/BuildProductsPath",
            "WATCHKIT_2_SUPPORT_FOLDER_PATH": archive + "/BuildProductsPath/WatchKitSupport2",
        ])
    }

    /// `-IDEBuildingContinueBuildingAfterErrors=YES` changes only `continueBuildingAfterErrors`
    /// (`build_experiments.py` `app-without-packages`; retro-rampage's `Engine`).
    @Test func continuesAfterErrorsAsTheUserDefaultAsks() throws {
        let settings = SettingsRequest(configuration: "Release", destination: nil, locations: nil, overrides: [:])
        let request = BuildOperation.buildRequest(.init(targets: [WorkspaceTarget(guid: "G", name: "Engine")], settings: settings,
                                                        containerPath: "/src/Rampage.xcodeproj", continueBuildingAfterErrors: true),
                                                  sdkCanonicalName: nil)
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(json["continueBuildingAfterErrors"] as? Bool == true)
    }
}
