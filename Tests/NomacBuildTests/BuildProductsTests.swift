import Foundation
import Testing
@testable import NomacBuild
import NomacCore
import NomacTestSupport
import NomacVerify

/// ADR 0101's comparison of build products, on self-written files shaped as the differences
/// observed between Xcode 27.0's retro-rampage and nomac's.
@Suite struct BuildProductsTests {
    private func compare(_ reference: [UInt8], _ other: [UInt8], name: String = "Engine") throws -> BuildProducts.Outcome {
        let tmp = try TemporaryDirectory()
        try FileSystem.write(Data(reference), to: tmp.path + "/xcode/" + name)
        try FileSystem.write(Data(other), to: tmp.path + "/nomac/" + name)
        return try BuildProducts.compareFile(tmp.path + "/xcode/" + name, tmp.path + "/nomac/" + name)
    }

    private static let contents = "section contents, sizes and addresses follow the compiler's code (ADR 0101)"

    /// Xcode's `ld` and lld on Engine: lld's sections, layout and stub binder, no stack checks.
    static let linkedByLD = SyntheticDylib(
        exports: [.init(name: "_engine", place: .text)], loadedLibraries: ["/usr/lib/libSystem.B.dylib", "/usr/lib/libc++.1.dylib"],
        imports: [.init(name: "___chkstk_darwin"), .init(name: "__Znwm", library: 2)], sourceVersion: 0, tools: [(3, 0x699d_0100)])
    static let linkedByLLD = SyntheticDylib(
        exports: [.init(name: "_engine", place: .text)], loadedLibraries: ["/usr/lib/libc++.1.dylib", "/usr/lib/libSystem.B.dylib"],
        imports: [.init(name: "dyld_stub_binder", library: 2), .init(name: "__Znwm", refersToWeakDefinition: true)], extraTextSections: ["__literals"],
        tools: [(4, 0x0015_0106)], payload: 1)

    @Test func identicalBytesAreIdentical() throws {
        let bytes = Self.linkedByLD.bytes()
        #expect(try compare(bytes, bytes) == .identical)
    }

    @Test func machOFilesWithTheSameStructureAreEquivalent() throws {
        var other = Self.linkedByLD
        other.payload = 1
        #expect(try compare(Self.linkedByLD.bytes(), other.bytes()) == .equivalent([Self.contents]))
    }

    @Test func lldsDocumentedDifferencesAreEquivalent() throws {
        #expect(try compare(Self.linkedByLD.bytes(), Self.linkedByLLD.bytes()) == .equivalent([
            Self.contents,
            "lld writes no LC_SOURCE_VERSION (ADR 0102)",
            "lld adds __TEXT,__literals (ADR 0102)",
            "lld loads the libraries in another order; imports are compared by library name (ADR 0102)",
            "LC_BUILD_VERSION names the linker that wrote the file, which nomac never fakes (ADR 0101, ADR 0102)",
            "Xcode's compiler adds stack checks, which open-source Swift does not have (ADR 0101)",
            "lld imports dyld_stub_binder whenever libSystem exports it (referenceStubBinder, lld/MachO/Driver.cpp)",
            "lld marks imports of weak definitions N_REF_TO_WEAK, Xcode's ld does not (lld/MachO/SyntheticSections.cpp)",
        ]))
    }

    /// lld's libswiftDarwin versions on Engine (B-116), and other undocumented differences.
    @Test func undocumentedDifferencesAreDifferent() throws {
        var other = Self.linkedByLLD
        other.libraryVersions = ["/usr/lib/libc++.1.dylib": 0]
        other.imports[1].isWeak = true
        #expect(try compare(Self.linkedByLD.bytes(), other.bytes()) == .different([
            "/usr/lib/libc++.1.dylib: Xcode 1.0.0 (compatibility 1.0.0), nomac 0.0.0 (compatibility 1.0.0)",
            "import __Znwm: strong in Xcode's, weak in nomac's",
        ]))
        var renamed = Self.linkedByLD
        renamed.exports[0].name = "_engine2"
        renamed.imports[1].library = 1
        #expect(try compare(Self.linkedByLD.bytes(), renamed.bytes()) == .different([
            "export _engine only in Xcode's", "export _engine2 only in nomac's",
            "import __Znwm: from /usr/lib/libc++.1.dylib in Xcode's, /usr/lib/libSystem.B.dylib in nomac's",
        ]))
    }

    /// SwiftSoup's relocatable object (icecubes' `Models`), linked by Xcode's `ld` and by `ld64`.
    @Test func selectorStubsAreTheCompilers() {
        let stubs = "Xcode's compiler calls Objective-C methods through selector stubs (-fobjc-msgsend-selector-stubs), open-source Swift through objc_msgSend and __objc_selrefs (ADR 0101)"
        let differences = ["section.extra.__DATA,__objc_selrefs", "import.missing._objc_msgSend$closeFile", "import.missing._objc_msgSend$init",
                           "import.extra._objc_msgSend"].map { MachOStructure.Difference(key: $0, description: $0) }
        #expect(BuildProducts.judge(differences) == .equivalent([Self.contents, stubs]))
        #expect(BuildProducts.judge([.init(key: "import.missing._objc_msgSendSuper", description: "super")]) == .different(["super"]))
    }

    @Test func registerSpecificARCEntryPointsFollowRegisterAllocation() {
        let differences = ["import.missing._objc_release_x23", "import.extra._objc_release_x22", "import.missing._objc_retain_x25",
                           "import.extra._objc_retain_x26"].map { MachOStructure.Difference(key: $0, description: $0) }
        #expect(BuildProducts.judge(differences) == .equivalent([
            Self.contents,
            "the register-specific ARC entry points a compiled member imports (objc_retain_xN, objc_release_xN) follow the compiler's register allocation (expo-default's Swift pods on the Mac, ADR 0101)",
        ]))
        #expect(BuildProducts.judge([.init(key: "import.missing._objc_release", description: "release")]) == .different(["release"]))
    }

    /// Objects compiled on Linux (expo-default): selector loads where Xcode's compilers use stubs,
    /// with their linker optimization hints, the general ARC entry points and the empty
    /// collection constants' other names.
    @Test func openSourceCompilersObjectiveCCalls() {
        let hints = MachOStructure.Difference(key: "command.extra.LC_LINKER_OPTIMIZATION_HINT", description: "LC_LINKER_OPTIMIZATION_HINT only in nomac's")
        let differences = [hints] + ["section.extra.__DATA,__objc_selrefs", "section.extra.__TEXT,__objc_methname", "import.extra._objc_msgSend",
                                     "import.extra._objc_retain", "import.extra._objc_release", "import.missing.___NSDictionary0__struct",
                                     "import.extra.___NSDictionary0__", "import.missing.___NSArray0__struct", "import.extra.___NSArray0__"]
            .map { MachOStructure.Difference(key: $0, description: $0) }
        guard case .equivalent(let causes) = BuildProducts.judge(differences) else {
            Issue.record("not equivalent")
            return
        }
        #expect(causes.count == 6)
        let runtime = ["import.missing._objc_opt_class", "import.missing._objc_opt_isKindOfClass", "import.missing._objc_opt_new",
                       "import.missing.___kCFBooleanFalse", "import.extra._objc_msgSend"].map { MachOStructure.Difference(key: $0, description: $0) }
        guard case .equivalent = BuildProducts.judge(runtime) else {
            Issue.record("the runtime's entry points are not documented")
            return
        }
        #expect(BuildProducts.judge([hints]) == .different(["LC_LINKER_OPTIMIZATION_HINT only in nomac's"]))
    }

    /// expo-default's Debug Swift objects: every linker optimization hint Xcode's compiler writes
    /// is a stack check's `adrp` and `ldr`, so without stack checks the command is missing.
    @Test func optimizationHintsMayBeTheStackChecks() {
        let hints = MachOStructure.Difference(key: "command.missing.LC_LINKER_OPTIMIZATION_HINT", description: "LC_LINKER_OPTIMIZATION_HINT only in Xcode's")
        let stackChecks = MachOStructure.Difference(key: "import.missing.___chkstk_darwin", description: "import ___chkstk_darwin only in Xcode's")
        #expect(BuildProducts.judge([hints, stackChecks]) == .equivalent([
            Self.contents,
            "the object's only linker optimization hints were its stack checks' adrp and ldr pairs (expo-default's Debug Swift objects), which open-source Swift does not emit (ADR 0101)",
            "Xcode's compiler adds stack checks, which open-source Swift does not have (ADR 0101)",
        ]))
        #expect(BuildProducts.judge([hints]) == .different(["LC_LINKER_OPTIMIZATION_HINT only in Xcode's"]))
    }

    /// netnewswire's ErrorLog: an actor's `@objc` method list, relative in Xcode's
    /// `__objc_methlist`, is the only content of lld's `__objc_data`.
    @Test func objectiveCDataMayBeAMethodListLLDKeeps() {
        let data = MachOStructure.Difference(key: "section.extra.__DATA,__objc_data", description: "section __DATA,__objc_data only in nomac's")
        let methodLists = MachOStructure.Difference(key: "section.missing.__TEXT,__objc_methlist", description: "section __TEXT,__objc_methlist only in Xcode's")
        guard case .equivalent = BuildProducts.judge([data, methodLists]) else {
            Issue.record("expected the method list to explain __objc_data")
            return
        }
        #expect(BuildProducts.judge([data]) == .different(["section __DATA,__objc_data only in nomac's"]))
    }

    @Test func sectionsNameTheirOwnSegments() throws {
        let tmp = try TemporaryDirectory()
        var object = Self.linkedByLD
        object.unnamedSegments = true
        try object.write(to: tmp.path + "/a.o")
        #expect(try MachOStructure(path: tmp.path + "/a.o").sections == ["__TEXT,__text", "__TEXT,__const", "__DATA,__objc_imageinfo", "__DATA,__data"])
    }

    @Test func generatedHeadersMayNameAnotherCompiler() throws {
        let xcode = "// header\n\n// Generated by Apple Swift version 6.4 effective-5.10 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)\n#ifndef ENGINE\n"
        let nomac = "// header\n\n// Generated by Swift version 6.4 (swift-6.4-RELEASE)\n#ifndef ENGINE\n"
        #expect(try compare(Array(xcode.utf8), Array(nomac.utf8), name: "Engine-Swift.h")
            == .equivalent(["the generated header's first comment names the compiler (ADR 0101)"]))
        #expect(try compare(Array(xcode.utf8), Array(nomac.replacingOccurrences(of: "ENGINE", with: "OTHER").utf8), name: "Engine-Swift.h")
            == .different(["line 4 differs"]))
    }

    @Test func relocationMapsCompareTheirHeader() throws {
        let header = "---\ntriple:          'arm64-apple-darwin'\nbinary-path:     '/dd/Engine.framework/Engine'\nrelocations:\n"
        let path = "Engine.framework.dSYM/Contents/Resources/Relocations/aarch64/Engine.yml"
        #expect(try compare(Array((header + "  - { offset: 0x1 }\n").utf8), Array((header + "  - { offset: 0x2 }\n").utf8), name: path)
            == .equivalent(["the debug map's relocations follow the compiler's code; their header is identical (ADR 0101)"]))
        let moved = header.replacingOccurrences(of: "/dd/", with: "/other/")
        #expect(try compare(Array((header + "  - { offset: 0x1 }\n").utf8), Array((moved + "  - { offset: 0x1 }\n").utf8), name: path)
            == .different(["the relocation map's header differs"]))
    }

    @Test func binaryModulesCompareTheirABIDescriptor() throws {
        let tmp = try TemporaryDirectory()
        for side in ["xcode", "nomac"] {
            try FileSystem.write(Data(side.utf8), to: tmp.path + "/\(side)/arm64-apple-ios.swiftmodule")
            try FileSystem.write(Data("{}".utf8), to: tmp.path + "/\(side)/arm64-apple-ios.abi.json")
        }
        let module = { (side: String) in tmp.path + "/\(side)/arm64-apple-ios.swiftmodule" }
        #expect(try BuildProducts.compareFile(module("xcode"), module("nomac")) == .equivalent([
            "a binary module records the compiler's version, its Clang modules' hashes and its search and plugin paths; its interface is compared through its .abi.json, identical (ADR 0101)",
        ]))
        try FileSystem.write(Data("{ }".utf8), to: tmp.path + "/nomac/arm64-apple-ios.abi.json")
        #expect(try BuildProducts.compareFile(module("xcode"), module("nomac")) == .different(["its .abi.json differs"]))
        try FileManager.default.removeItem(atPath: tmp.path + "/nomac/arm64-apple-ios.abi.json")
        #expect(try BuildProducts.compareFile(module("xcode"), module("nomac"))
            == .different(["no .abi.json beside the binary module to compare its interface with"]))
    }

    /// A static library laid out as Xcode 27.0's `libtool -static` writes expo-default's
    /// `libExpoDevice.a`: `#1/<length>` names padded with NULs, zero dates and owners, and the
    /// ranlib table first, each entry's offset that of its member's header.
    private static func archive(_ members: [(name: String, contents: [UInt8])], symbols: [(name: String, member: Int)]) -> [UInt8] {
        func header(_ name: String, _ size: Int, mode: String) -> [UInt8] {
            let padded = (name.utf8.count + 4) / 4 * 4
            let field = { (text: String, width: Int) in Array(text.padding(toLength: width, withPad: " ", startingAt: 0).utf8) }
            return field("#1/\(padded)", 16) + field("0", 12) + field("0", 6) + field("0", 6) + field(mode, 8) + field("\(padded + size)", 10)
                + Array("`\n".utf8) + Array(name.utf8) + [UInt8](repeating: 0, count: padded - name.utf8.count)
        }
        var strings: [UInt8] = symbols.flatMap { Array($0.name.utf8) + [0] }
        while strings.count % 8 != 0 { strings.append(0) }
        func uint32(_ value: Int) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) } }
        let tableSize = 4 + 8 * symbols.count + 4 + strings.count
        var offsets: [Int] = []
        var offset = 8 + header("__.SYMDEF", tableSize, mode: "100644").count + tableSize
        for member in members {
            offsets.append(offset)
            offset += header(member.name, member.contents.count, mode: "644").count + member.contents.count
        }
        var table = uint32(8 * symbols.count)
        var stringOffset = 0
        for symbol in symbols {
            table += uint32(stringOffset) + uint32(offsets[symbol.member])
            stringOffset += symbol.name.utf8.count + 1
        }
        table += uint32(strings.count) + strings
        return Array("!<arch>\n".utf8) + header("__.SYMDEF", tableSize, mode: "100644") + table
            + members.flatMap { header($0.name, $0.contents.count, mode: "644") + $0.contents }
    }

    @Test func archivesCompareTheirMembers() throws {
        let dummy = Array("dummy.o\n".utf8)
        let module = Array("module.o".utf8)
        func library(_ object: [UInt8], dummy: [UInt8] = dummy, objectName: String = "UIDevice.o", symbolMember: Int = 1) -> [UInt8] {
            Self.archive([("ExpoDevice-dummy.o", dummy), (objectName, object), ("DeviceModule.o", module)],
                         symbols: [("_engine", symbolMember), ("_module", 2)])
        }
        let xcode = library(Self.linkedByLD.bytes())
        #expect(try compare(xcode, xcode, name: "libExpoDevice.a") == .identical)
        var recompiled = Self.linkedByLD
        recompiled.payload = 1
        #expect(try compare(xcode, library(recompiled.bytes() + [UInt8](repeating: 0, count: 8)), name: "libExpoDevice.a") == .equivalent([
            Self.contents,
            "the ranlib table records each symbol's member by offset, which follows the compiled members' sizes",
        ]))
        recompiled.extraTextSections = ["__padding"]
        #expect(try compare(xcode, library(recompiled.bytes()), name: "libExpoDevice.a")
            == .different(["member UIDevice.o: section __TEXT,__padding only in nomac's"]))
        // The table may also name the members' private externals, which follow the compiler's code
        // (expo-default's libExpoKeepAwake.a on Linux: Swift's metadata caches).
        var cachesXcode = Self.linkedByLD
        cachesXcode.privateExternals = ["_$s4Expo8DefinitionCyS2SSbGMR"]
        var cachesNomac = Self.linkedByLD
        cachesNomac.privateExternals = ["_$s4Expo8DefinitionCyS2SSbGMD"]
        func caches(_ object: SyntheticDylib, _ cache: String) -> [UInt8] {
            Self.archive([("ExpoDevice-dummy.o", dummy), ("UIDevice.o", object.bytes()), ("DeviceModule.o", module)],
                         symbols: [("_engine", 1), (cache, 1), ("_module", 2)])
        }
        #expect(try compare(caches(cachesXcode, "_$s4Expo8DefinitionCyS2SSbGMR"), caches(cachesNomac, "_$s4Expo8DefinitionCyS2SSbGMD"), name: "libExpoDevice.a")
            == .equivalent([Self.contents, "the ranlib table also names the members' private external symbols, which follow the compiler's code (ADR 0101)"]))
        #expect(try compare(caches(cachesXcode, "_$s4Expo8DefinitionCyS2SSbGMR"), caches(cachesXcode, "_other"), name: "libExpoDevice.a")
            == .different(["member __.SYMDEF: the ranlib table names other symbols"]))
        // A member's difference explains the table's: it is the one reported.
        #expect(try compare(xcode, library(recompiled.bytes(), symbolMember: 0), name: "libExpoDevice.a")
            == .different(["member UIDevice.o: section __TEXT,__padding only in nomac's"]))
        #expect(try compare(xcode, library(Self.linkedByLD.bytes(), symbolMember: 0), name: "libExpoDevice.a")
            == .different(["member __.SYMDEF: the ranlib table names other symbols"]))
        #expect(try compare(xcode, library(Self.linkedByLD.bytes(), dummy: Array("dummx.o\n".utf8)), name: "libExpoDevice.a")
            == .different(["member ExpoDevice-dummy.o: the bytes differ"]))
        #expect(try compare(xcode, library(Self.linkedByLD.bytes(), objectName: "Device.o"), name: "libExpoDevice.a") == .different([
            "members [\"__.SYMDEF\", \"ExpoDevice-dummy.o\", \"UIDevice.o\", \"DeviceModule.o\"] in Xcode's, "
                + "[\"__.SYMDEF\", \"ExpoDevice-dummy.o\", \"Device.o\", \"DeviceModule.o\"] in nomac's",
        ]))
    }

    /// A `.swiftsourceinfo`-shaped bitstream: a `BLOCKINFO` abbreviation for the declaration
    /// locations block, a control block with the compiler's version, and a source file list.
    private static func bitstream(version: String, other: UInt64 = 7, modified: UInt64 = 1, size: UInt64 = 100) -> [UInt8] {
        var bits = BitWriter()
        for byte in [0xf0, 0x9f, 0x8f, 0x8e] as [UInt64] { bits.write(byte, 8) }
        func enter(_ id: UInt64, width: Int = 3, outer: Int) {
            bits.write(1, outer)
            bits.vbr(id, 8)
            bits.vbr(UInt64(width), 4)
            bits.align()
            bits.write(0, 32)
        }
        func blobAbbreviation(code: UInt64, fixed: Int?) {
            bits.write(2, 3)
            bits.vbr(fixed == nil ? 2 : 3, 5)
            bits.write(1, 1)
            bits.vbr(code, 8)
            if let fixed {
                bits.write(0, 1)
                bits.write(1, 3)
                bits.vbr(UInt64(fixed), 5)
            }
            bits.write(0, 1)
            bits.write(5, 3)
        }
        func blob(_ bytes: [UInt8]) {
            bits.vbr(UInt64(bytes.count), 6)
            bits.align()
            for byte in bytes { bits.write(UInt64(byte), 8) }
            bits.align()
        }
        func end() {
            bits.write(0, 3)
            bits.align()
        }
        enter(0, outer: 2)
        bits.write(3, 3)
        bits.vbr(1, 6)
        bits.vbr(1, 6)
        bits.vbr(193, 6)
        blobAbbreviation(code: 5, fixed: nil)
        end()
        enter(192, outer: 2)
        enter(9, outer: 3)
        blobAbbreviation(code: 1, fixed: 16)
        bits.write(4, 3)
        bits.write(3, 16)
        blob(Array(version.utf8))
        bits.write(3, 3)
        bits.vbr(2, 6)
        bits.vbr(1, 6)
        bits.vbr(other, 6)
        end()
        enter(193, outer: 3)
        bits.write(4, 3)
        var entry = SyntheticMachO.words([0]) + Array(String(repeating: "0", count: 64).utf8)
        entry += SyntheticMachO.quads([modified, size])
        blob(entry)
        end()
        end()
        return bits.bytes
    }

    @Test func swiftFilesMayRecordAnotherCompilerAndOtherTimes() throws {
        let xcode = Self.bitstream(version: "Apple Swift version 6.4 effective-5.10 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)")
        let records = try { () throws -> [SwiftBitstream.Record] in
            let tmp = try TemporaryDirectory()
            try FileSystem.write(Data(xcode), to: tmp.path + "/a.swiftsourceinfo")
            return try SwiftBitstream(path: tmp.path + "/a.swiftsourceinfo").records
        }()
        #expect(records.map(\.blocks) == [[0], [192, 9], [192, 9], [192, 193]])
        #expect(records[1].fields == [3] && records[2].fields == [7] && records[3].blob?.count == 84)
        #expect(SwiftBitstream.isCompilerVersion(records[1]) && SwiftBitstream.isSourceFileList(records[3]))

        let version = "the control block records the compiler's version (ADR 0101)"
        let times = "the source files' modification times, which the checkout and the build set (emitFileListRecord, swift's lib/Serialization/SerializeDoc.cpp)"
        let nomac = "Swift version 6.4 (swift-6.4-RELEASE)"
        #expect(try compare(xcode, Self.bitstream(version: nomac), name: "a.swiftsourceinfo") == .equivalent([version]))
        #expect(try compare(xcode, Self.bitstream(version: nomac, modified: 2), name: "a.swiftdoc") == .equivalent([version, times]))
        #expect(try compare(xcode, Self.bitstream(version: nomac, size: 101), name: "a.swiftsourceinfo")
            == .different(["bitstream record 3 (blocks [192, 193], code 5) differs"]))
        #expect(try compare(xcode, Self.bitstream(version: nomac, other: 8), name: "a.swiftsourceinfo")
            == .different(["bitstream record 2 (blocks [192, 9], code 2) differs"]))
    }

    /// cwa's ENA.swiftsourceinfo: the project spells `PDFGeneration`, a Linux build the disk's
    /// `PdfGeneration` (BACKLOG B-062).
    @Test func sourcePathsMayDifferInCaseOnly() {
        func record(_ text: String, code: UInt64 = 3) -> SwiftBitstream.Record {
            SwiftBitstream.Record(blocks: [192, 193], code: code, fields: [], blob: Array(text.utf8))
        }
        let xcode = "/c/PDFGeneration/A.swift\0/c/PdfGeneration/B.swift\0"
        #expect(BuildProducts.bitstreamCause(record(xcode), record("/c/PdfGeneration/A.swift\0/c/PdfGeneration/B.swift\0"))
            == "source paths the project spells in another case than the disk, which a build on a case-sensitive file system gives the compiler as the disk spells them (BACKLOG B-062; nomac build --case-aliases keeps the project's)")
        #expect(BuildProducts.bitstreamCause(record(xcode), record("/c/PDFGeneration/A.swift\0/c/PdfGeneration/C.swift\0")) == nil)
        #expect(BuildProducts.bitstreamCause(record(xcode), record("/c/PDFGeneration/A.swift\0")) == nil)
        #expect(BuildProducts.bitstreamCause(record(xcode, code: 1), record("/c/PdfGeneration/A.swift\0/c/PdfGeneration/B.swift\0", code: 1)) == nil)
    }

    @Test func otherFilesMustBeIdentical() throws {
        #expect(try compare(Array("<plist/>".utf8), Array("<plist />".utf8), name: "Info.plist") == .different(["the bytes differ"]))
    }

    @Test func treesAreComparedFileByFileAndLinksByDestination() throws {
        let tmp = try TemporaryDirectory()
        for side in ["xcode", "nomac"] {
            try FileSystem.write(Data("same".utf8), to: tmp.path + "/\(side)/Release-iphoneos/App.app/Info.plist")
            try FileManager.default.createSymbolicLink(atPath: tmp.path + "/\(side)/Release-iphoneos/Link",
                                                       withDestinationPath: side == "xcode" ? "App.app" : "Other.app")
        }
        try FileSystem.write(Data(), to: tmp.path + "/xcode/Release-iphoneos/App.app/Missing")
        try FileSystem.write(Data(), to: tmp.path + "/nomac/Release-iphoneos/App.app/Extra")
        let results = try BuildProducts.compare(reference: tmp.path + "/xcode", other: tmp.path + "/nomac")
        #expect(results == [
            .init(path: "Release-iphoneos/App.app/Extra", outcome: .extra),
            .init(path: "Release-iphoneos/App.app/Info.plist", outcome: .identical),
            .init(path: "Release-iphoneos/App.app/Missing", outcome: .missing),
            .init(path: "Release-iphoneos/Link", outcome: .different(["symbolic link to App.app in Xcode's, Other.app in nomac's"])),
        ])
    }
}

@Suite struct BuildVerificationTests {
    typealias Check = VerificationReport.Check

    @Test func theCapturedCommandRunsAtTheCheckout() {
        let argv = ["xcodebuild", "-project", "/ci/app/App.xcodeproj", "-scheme", "App", "-derivedDataPath", "/ci/app-DerivedData",
                    "CODE_SIGN_IDENTITY=", "build"]
        #expect(BuildVerification.arguments(argv, referenceSource: "/ci/app", sourceRoot: "/local/app")
            == ["-project", "/local/app/App.xcodeproj", "-scheme", "App", "-derivedDataPath", "/ci/app-DerivedData", "CODE_SIGN_IDENTITY=", "build"])
        #expect(BuildVerification.arguments(argv, referenceSource: "/ci/app", sourceRoot: "/ci/app") == Array(argv.dropFirst()))
        // An offline capture's argv starts with the sandbox.
        #expect(BuildVerification.arguments(["sandbox-exec", "-p", "(version 1)"] + argv, referenceSource: "/ci/app", sourceRoot: "/ci/app")
                == Array(argv.dropFirst()))
    }

    @Test func aFailedBuildReportsXcodebuildsSummary() {
        let log = "CompileSwift normal arm64\n\n** BUILD FAILED **\n\n\nThe following build commands failed:\n\tLd Engine\n(1 failure)\n"
        #expect(BuildVerification.failureSummary(log) == ["The following build commands failed:", "\tLd Engine", "(1 failure)"])
    }

    /// Off macOS the macro packages and other host tools build for Linux: the reference's macOS
    /// folder and nomac's Linux one are left out, the platform's products compared (swiftfin).
    @Test func leavesOutTheProductsOfEachBuildMachine() {
        let results: [BuildProducts.FileResult] = [
            .init(path: "Release/SwiftSyntax.o", outcome: .missing),
            .init(path: "Release/SwiftfinMacrosPlugin", outcome: .missing),
            .init(path: "Release-iphoneos/App.app/App", outcome: .missing),
            .init(path: "Release-linux-aarch64/SwiftSyntax.o", outcome: .extra),
            .init(path: "Release-iphoneos/App.app/Info.plist", outcome: .identical),
        ]
        let (compared, note) = BuildVerification.excludingBuildMachineProducts(results)
        #expect(compared.map(\.path) == ["Release-iphoneos/App.app/App", "Release-iphoneos/App.app/Info.plist"])
        #expect(note == ["Release (2 files): the reference's products for its Mac, not compared",
                         "Release-linux-aarch64 (1 files): built for this Linux build machine, not compared"])
    }

    @Test func eachProductIsOneCheck() {
        let results: [BuildProducts.FileResult] = [
            .init(path: "Release-iphoneos/App.app/App", outcome: .equivalent(["code"])),
            .init(path: "Release-iphoneos/App.app/Info.plist", outcome: .identical),
            .init(path: "Release-iphoneos/Kit.framework/Info.plist", outcome: .different(["the bytes differ"])),
            .init(path: "Release-iphoneos/Kit.framework/Kit", outcome: .missing),
            .init(path: "Release-iphoneos/libKit.a", outcome: .identical),
        ]
        #expect(BuildVerification.productChecks(results, detailLimit: 1) == [
            Check(kind: "build", name: "Release-iphoneos/App.app", status: .equivalent, detail: ["equivalent Release-iphoneos/App.app/App: code"]),
            Check(kind: "build", name: "Release-iphoneos/Kit.framework", status: .different,
                  detail: ["different Release-iphoneos/Kit.framework/Info.plist: the bytes differ", "... 1 more files"]),
            Check(kind: "build", name: "Release-iphoneos/libKit.a", status: .identical, detail: []),
        ])
    }

    /// The checkout as the capture leaves it after a build (capture_reference.py's `restore`): what
    /// the build changed is checked out and what it wrote is removed, what was there before stays.
    @Test func undoesWhatTheBuildChangedInTheCheckout() throws {
        let tmp = try TemporaryDirectory()
        let git = try #require(Subprocess.locate("git"))
        try tmp.writeExactly("debug\n", to: "Pods/A/flavour")
        try tmp.writeExactly("one\n", to: "edited.txt")
        try tmp.writeExactly("ignored/\n", to: ".gitignore")
        for arguments in [["init", "-q"], ["add", "."], ["-c", "user.name=nomac", "-c", "user.email=nomac@example.invalid", "commit", "-q", "-m", "1"]] {
            #expect(try Subprocess.run(git, arguments, currentDirectory: tmp.path).exitStatus == 0)
        }
        try tmp.writeExactly("two\n", to: "edited.txt")
        try tmp.writeExactly("", to: "keep.txt")
        try tmp.writeExactly("", to: "ignored/kept.o")

        let checkout = try #require(try BuildVerification.Checkout(tmp.path + "/Pods"))
        let before = try checkout.status()
        try tmp.writeExactly("release\n", to: "Pods/A/flavour")
        try tmp.writeExactly("", to: "Pods/A/new/stamp")
        try tmp.writeExactly("", to: "ignored/out.o")

        #expect(try checkout.restore(since: before) == [
            "restored Pods/A/flavour, which the build changed in the checkout",
            "removed Pods/A/new/stamp, which the build wrote into the checkout",
            "removed ignored/out.o, which the build wrote into the checkout",
        ])
        #expect(FileSystem.contents(atPath: tmp.path + "/Pods/A/flavour") == Data("debug\n".utf8))
        #expect(FileSystem.contents(atPath: tmp.path + "/edited.txt") == Data("two\n".utf8))
        #expect(!FileSystem.exists(tmp.path + "/Pods/A/new/stamp"))
        #expect(!FileSystem.exists(tmp.path + "/ignored/out.o"))
        #expect(FileSystem.exists(tmp.path + "/keep.txt"))
        #expect(FileSystem.exists(tmp.path + "/ignored/kept.o"))
    }

    @Test func aFolderOutsideGitHasNoCheckout() throws {
        let tmp = try TemporaryDirectory()
        #expect(try BuildVerification.Checkout(tmp.path) == nil)
    }
}

/// LLVM bitstream bits, least significant first.
private struct BitWriter {
    var bytes: [UInt8] = []
    var count = 0

    mutating func write(_ value: UInt64, _ width: Int) {
        for bit in 0..<width {
            if count % 8 == 0 { bytes.append(0) }
            if (value >> UInt64(bit)) & 1 == 1 { bytes[bytes.count - 1] |= 1 << UInt8(count % 8) }
            count += 1
        }
    }

    mutating func vbr(_ value: UInt64, _ width: Int) {
        let high = UInt64(1) << UInt64(width - 1)
        var value = value
        while value >= high {
            write(value & (high - 1) | high, width)
            value >>= UInt64(width - 1)
        }
        write(value, width)
    }

    mutating func align() {
        while count % 32 != 0 { write(0, 1) }
    }
}
