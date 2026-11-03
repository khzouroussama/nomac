import Foundation
import Testing
@testable import NomacVerify

/// The tool checks against a reference built in a temporary folder: Xcode's log and outputs as a
/// capture keeps them, and a stand-in for nomac whose ibtool writes what Xcode's did.
@Suite struct ToolVerificationTests {
    let root: String
    var reference: String { root + "/reference" }
    var source: String { root + "/src" }
    var derivedData: String { root + "/DD" }
    var developer: String { root + "/Xcode.app/Contents/Developer" }
    var intermediates: String { "/Build/Intermediates.noindex/App.build/Release-iphoneos/App.build" }
    var compiled: String { intermediates + "/Base.lproj" }
    var product: String { "/Build/Products/Release-iphoneos/App.app" }

    init() throws {
        root = NSTemporaryDirectory() + "nomac-tool-verification-" + UUID().uuidString
        try write("<document/>", to: source + "/Base.lproj/Main.storyboard")
        try write("{\"path\": \"\(source)\"}", to: reference + "/source.json")
        try write("{\"developerDirectory\": \"\(developer)\"}", to: reference + "/host.json")
        try write("{\"argv\": [\"xcodebuild\", \"-derivedDataPath\", \"\(derivedData)\", \"build\"], \"exitStatus\": 1}", to: reference + "/build/build.log.cmd")
        try write("""
            CompileStoryboard \(source)/Base.lproj/Main.storyboard (in target 'App' from project 'App')
                cd \(source)
                \(developer)/usr/bin/ibtool --errors --module App --output-partial-info-plist \(derivedData + compiled)/Main-SBPartialInfo.plist --target-device iphone --minimum-deployment-target 15.0 \(source)/Base.lproj/Main.storyboard --compilation-directory \(derivedData + compiled)

            LinkStoryboards (in target 'App' from project 'App')
                cd \(source)
                \(developer)/usr/bin/ibtool --errors --module App --link \(derivedData + product) \(derivedData + compiled)/Main.storyboardc

            CopyStringsFile \(derivedData + product)/en.lproj/Localizable.strings \(source)/en.lproj/Localizable.strings (in target 'App' from project 'App')
                cd \(source)
                builtin-copyStrings --validate --outputencoding binary --outdir \(derivedData + product)/en.lproj -- \(source)/en.lproj/Localizable.strings

            CpResource \(derivedData + product)/Levels.json \(source)/Levels.json (in target 'App' from project 'App')
                cd \(source)
                builtin-copy -resolve-src-symlinks \(source)/Levels.json \(derivedData + product)

            GenerateAssetSymbols \(source)/Assets.xcassets (in target 'App' from project 'App')
                cd \(source)
                \(developer)/usr/bin/actool \(source)/Assets.xcassets --compile \(derivedData + product) --notices --export-dependency-info \(derivedData + intermediates)/assetcatalog_dependencies --generate-swift-asset-symbols \(derivedData + intermediates)/DerivedSources/GeneratedAssetSymbols.swift
            /* com.apple.actool.compilation-results */
            \(derivedData + intermediates)/DerivedSources/GeneratedAssetSymbols.swift

            CompileXIB \(source)/Cell.xib (in target 'App' from project 'App')
                cd \(source)
                \(developer)/usr/bin/ibtool --errors --compile \(derivedData + product)/Cell.nib \(source)/Cell.xib

            """, to: reference + "/build/build.log")
        try write("The following build commands failed:\n\tCompileXIB \(source)/Cell.xib (in target 'App' from project 'App')\n", to: reference + "/build/build.stderr")
        for folder in ["/build/Intermediates/App.build/Release-iphoneos/App.build/Base.lproj", "/build/Products/Release-iphoneos/App.app/Base.lproj"] {
            try write("nib", to: reference + folder + "/Main.storyboardc/view.nib")
            try write("compiled in \(derivedData + compiled)", to: reference + folder + "/Main.storyboardc/Info.plist")
        }
        try write("plist", to: reference + "/build/Intermediates/App.build/Release-iphoneos/App.build/Base.lproj/Main-SBPartialInfo.plist")
        try write("enum symbols", to: reference + "/build/Intermediates/App.build/Release-iphoneos/App.build/DerivedSources/GeneratedAssetSymbols.swift")
        // LinkAssetCatalog's copy of the thinned dependency info, at the path the symbols task names.
        try write("dependencies", to: reference + "/build/Intermediates/App.build/Release-iphoneos/App.build/assetcatalog_dependencies")
        // nomac's ibtool, as far as these tests need it; any other tool refuses.
        try write("""
            #!/bin/sh
            tool=$1; shift
            if [ "$tool" = actool ]; then
              while [ $# -gt 0 ]; do [ "$1" = --generate-swift-asset-symbols ] && printf 'enum symbols' > "$2"; shift; done
              exit 0
            fi
            [ "$tool" = ibtool ] || { echo "\(source)/en.lproj/Localizable.strings: error: nomac does not copy these yet (BACKLOG B-999)" >&2; exit 1; }
            while [ $# -gt 0 ]; do
              case "$1" in
                --link) link=$2; shift 2;;
                --compilation-directory) directory=$2; shift 2;;
                --output-partial-info-plist) plist=$2; shift 2;;
                --errors) shift;;
                --*) shift 2;;
                *) inputs="$inputs $1"; shift;;
              esac
            done
            if [ -n "$link" ]; then
              for input in $inputs; do mkdir -p "$link/Base.lproj" && cp -R "$input" "$link/Base.lproj/"; done
              exit 0
            fi
            mkdir -p "$directory/Main.storyboardc"
            printf nib > "$directory/Main.storyboardc/view.nib"
            printf 'compiled in %s' "$directory" > "$directory/Main.storyboardc/Info.plist"
            printf plist > "$plist"
            """, to: root + "/nomac")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root + "/nomac")
    }

    func write(_ text: String, to path: String) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: URL(fileURLWithPath: path))
    }

    func checks() throws -> [VerificationReport.Check] {
        defer { try? FileManager.default.removeItem(atPath: root + "/scratch") }
        return try ToolVerification(referenceDirectory: reference, sourceRoot: source, developerDirectory: developer,
                                    nomacExecutable: root + "/nomac", scratchDirectory: root + "/scratch").checks()
    }

    @Test func comparesEachToolTaskWithXcodesOutputs() throws {
        defer { try? FileManager.default.removeItem(atPath: root) }
        let checks = try checks()
        #expect(checks.map(\.name) == [
            "App CompileStoryboard <SOURCE_ROOT>/Base.lproj/Main.storyboard",
            "App LinkStoryboards",
            "App CopyStringsFile <SOURCE_ROOT>/en.lproj/Localizable.strings",
            "App GenerateAssetSymbols <SOURCE_ROOT>/Assets.xcassets",
            "App CompileXIB <SOURCE_ROOT>/Cell.xib",
        ])
        #expect(checks.map(\.kind) == ["nib", "nib", "strings", "assets", "nib"])
        #expect(checks.map(\.status) == [.identical, .identical, .refused, .identical, .referenceFailed])
        #expect(checks[2].detail == ["nomac builtin-copyStrings exited with status 1",
                                     "<SOURCE_ROOT>/en.lproj/Localizable.strings: error: nomac does not copy these yet (BACKLOG B-999)"])
    }

    @Test func listsDifferentMissingAndExtraFiles() throws {
        defer { try? FileManager.default.removeItem(atPath: root) }
        let storyboard = reference + "/build/Intermediates/App.build/Release-iphoneos/App.build/Base.lproj/Main.storyboardc"
        try write("nib, as Xcode sized it", to: storyboard + "/view.nib")
        try write("another scene", to: storyboard + "/scene.nib")
        try FileManager.default.removeItem(atPath: storyboard + "/Info.plist")
        let check = try checks()[0]
        #expect(check.status == .different)
        #expect(check.detail == [
            "extra <DERIVED_DATA>\(compiled)/Main.storyboardc/Info.plist",
            "missing <DERIVED_DATA>\(compiled)/Main.storyboardc/scene.nib",
            "different <DERIVED_DATA>\(compiled)/Main.storyboardc/view.nib",
        ])
    }

    @Test func assetSymbolsSharingANameMayComeInAnyOrder() {
        let header = { (blocks: [String]) in Data(blocks.joined(separator: "\n\n").utf8) }
        let path = "/DerivedSources/GeneratedAssetSymbols.h"
        let xcode = ToolVerification.assetSymbolEntries(path, header(["#import <Foundation/Foundation.h>", "/// A/background", "/// B/background"]))
        #expect(xcode == ToolVerification.assetSymbolEntries(path, header(["#import <Foundation/Foundation.h>", "/// B/background", "/// A/background"])))
        #expect(xcode != ToolVerification.assetSymbolEntries(path, header(["#import <Foundation/Foundation.h>", "/// A/background", "/// C/background"])))
        let index = { (paths: [String]) in
            Data(("<plist version=\"1.0\"><dict><key>colors</key><array>"
                + paths.map { "<dict><key>relativePath</key><string>\($0)</string></dict>" }.joined() + "</array></dict></plist>").utf8)
        }
        let indexPath = "/DerivedSources/GeneratedAssetSymbols-Index.plist"
        #expect(ToolVerification.assetSymbolEntries(indexPath, index(["./A/background.colorset", "./B/background.colorset"]))
            == ToolVerification.assetSymbolEntries(indexPath, index(["./B/background.colorset", "./A/background.colorset"])))
        #expect(ToolVerification.assetSymbolEntries("/DerivedSources/GeneratedAssetSymbols.swift", Data()) == nil)
    }

    @Test func aReferenceWithoutABuildHasNoToolChecks() throws {
        defer { try? FileManager.default.removeItem(atPath: root) }
        try FileManager.default.removeItem(atPath: reference + "/build")
        #expect(try checks().isEmpty)
    }
}
