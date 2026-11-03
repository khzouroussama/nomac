import Foundation
import NomacCore
import NomacVerify

/// Xcode's build products and nomac's, file by file (ADR 0101, docs/VERIFICATION.md "Build
/// products"). A file is identical when its bytes are. A compiled file is equivalent when its
/// structure matches and every difference is one of ``documented``, each observed on
/// retro-rampage's `Engine` built on Linux against Xcode 27.0's build at the same paths. Every
/// other file must be identical.
public enum BuildProducts {
    public enum Outcome: Equatable, Sendable {
        case identical
        /// The documented causes of the differences.
        case equivalent([String])
        /// The differences no cause explains.
        case different([String])
        case missing
        case extra
    }

    public struct FileResult: Equatable, Sendable {
        public var path: String
        public var outcome: Outcome
    }

    /// The differences between Xcode's compiled files and nomac's that ADR 0101 accepts, by
    /// ``MachOStructure/Difference`` key (a key ending in `*` stands for every key it begins),
    /// with their causes.
    static let documented: [String: String] = [
        "mach-o.contents": "section contents, sizes and addresses follow the compiler's code (ADR 0101)",
        "command.order": "lld lays out load commands in another order (ADR 0102)",
        "command.missing.LC_SOURCE_VERSION": "lld writes no LC_SOURCE_VERSION (ADR 0102)",
        "build-version.tools": "LC_BUILD_VERSION names the linker that wrote the file, which nomac never fakes (ADR 0101, ADR 0102)",
        "section.extra.__TEXT,__literals": "lld adds __TEXT,__literals (ADR 0102)",
        "section.extra.__DATA,__objc_clsrolist": "lld adds __DATA,__objc_clsrolist (ADR 0102)",
        "section.missing.__TEXT,__objc_methlist": "Xcode's ld makes Swift classes' method lists relative, in __TEXT,__objc_methlist, from iOS 14.0; lld only clang's (ADR 0102)",
        "section.missing.__TEXT,__objc_stubs": "Xcode's compiler calls Objective-C methods through selector stubs, which the linker writes into __TEXT,__objc_stubs; open-source Swift calls objc_msgSend (ADR 0101)",
        "section.extra.__DATA,__objc_data": "lld keeps a Swift class's Objective-C method list (an actor's @objc methods) in __DATA,__objc_data, which Xcode's ld makes relative in __TEXT,__objc_methlist (ADR 0102)",
        "section.order": "lld lays out sections in another order (ADR 0102)",
        "library.order": "lld loads the libraries in another order; imports are compared by library name (ADR 0102)",
        "import.missing.___chkstk_darwin": "Xcode's compiler adds stack checks, which open-source Swift does not have (ADR 0101)",
        "command.missing.LC_LINKER_OPTIMIZATION_HINT": "the object's only linker optimization hints were its stack checks' adrp and ldr pairs (expo-default's Debug Swift objects), which open-source Swift does not emit (ADR 0101)",
        "import.weak-definition": "lld marks imports of weak definitions N_REF_TO_WEAK, Xcode's ld does not (lld/MachO/SyntheticSections.cpp)",
        "import.missing._objc_msgSend$*": "Xcode's compiler calls Objective-C methods through selector stubs (-fobjc-msgsend-selector-stubs), open-source Swift through objc_msgSend and __objc_selrefs (ADR 0101)",
        "import.extra._objc_msgSend": "Xcode's compiler calls Objective-C methods through selector stubs (-fobjc-msgsend-selector-stubs), open-source Swift through objc_msgSend and __objc_selrefs (ADR 0101)",
        "section.extra.__DATA,__objc_selrefs": "Xcode's compiler calls Objective-C methods through selector stubs (-fobjc-msgsend-selector-stubs), open-source Swift through objc_msgSend and __objc_selrefs (ADR 0101)",
        "section.extra.__TEXT,__objc_methname": "Xcode's compilers call Objective-C methods through selector stubs (-fobjc-msgsend-selector-stubs), open-source Swift and clang load the selector's name from __objc_selrefs (ADR 0101)",
        "command.extra.LC_LINKER_OPTIMIZATION_HINT": "the object's linker optimization hints are its __objc_selrefs loads, which Xcode's selector stubs make unneeded (Xcode's clang with -fno-objc-msgsend-selector-stubs writes both, ADR 0101)",
        "import.extra._objc_retain": "Xcode's compilers call the register-specific ARC entry points objc_retain_xN and objc_release_xN, open-source Swift and clang objc_retain and objc_release (ADR 0101)",
        "import.extra._objc_release": "Xcode's compilers call the register-specific ARC entry points objc_retain_xN and objc_release_xN, open-source Swift and clang objc_retain and objc_release (ADR 0101)",
        "import.missing.___NSArray0__struct": "Xcode's clang names the empty array and dictionary constants ___NSArray0__struct and ___NSDictionary0__struct, open-source clang ___NSArray0__ and ___NSDictionary0__ (ADR 0101)",
        "import.extra.___NSArray0__": "Xcode's clang names the empty array and dictionary constants ___NSArray0__struct and ___NSDictionary0__struct, open-source clang ___NSArray0__ and ___NSDictionary0__ (ADR 0101)",
        "import.missing.___NSDictionary0__struct": "Xcode's clang names the empty array and dictionary constants ___NSArray0__struct and ___NSDictionary0__struct, open-source clang ___NSArray0__ and ___NSDictionary0__ (ADR 0101)",
        "import.missing._objc_opt_class": "Xcode's clang calls the Objective-C runtime's entry points for +class, -isKindOfClass: and +new and refers to @NO as ___kCFBooleanFalse; open-source clang sends objc_msgSend, whatever -fobjc-runtime (ADR 0101)",
        "import.missing._objc_opt_isKindOfClass": "Xcode's clang calls the Objective-C runtime's entry points for +class, -isKindOfClass: and +new and refers to @NO as ___kCFBooleanFalse; open-source clang sends objc_msgSend, whatever -fobjc-runtime (ADR 0101)",
        "import.missing._objc_opt_new": "Xcode's clang calls the Objective-C runtime's entry points for +class, -isKindOfClass: and +new and refers to @NO as ___kCFBooleanFalse; open-source clang sends objc_msgSend, whatever -fobjc-runtime (ADR 0101)",
        "import.missing.___kCFBooleanFalse": "Xcode's clang calls the Objective-C runtime's entry points for +class, -isKindOfClass: and +new and refers to @NO as ___kCFBooleanFalse; open-source clang sends objc_msgSend, whatever -fobjc-runtime (ADR 0101)",
        "import.extra.___NSDictionary0__": "Xcode's clang names the empty array and dictionary constants ___NSArray0__struct and ___NSDictionary0__struct, open-source clang ___NSArray0__ and ___NSDictionary0__ (ADR 0101)",
        "import.missing._objc_retain_x*": "the register-specific ARC entry points a compiled member imports (objc_retain_xN, objc_release_xN) follow the compiler's register allocation (expo-default's Swift pods on the Mac, ADR 0101)",
        "import.extra._objc_retain_x*": "the register-specific ARC entry points a compiled member imports (objc_retain_xN, objc_release_xN) follow the compiler's register allocation (expo-default's Swift pods on the Mac, ADR 0101)",
        "import.missing._objc_release_x*": "the register-specific ARC entry points a compiled member imports (objc_retain_xN, objc_release_xN) follow the compiler's register allocation (expo-default's Swift pods on the Mac, ADR 0101)",
        "import.extra._objc_release_x*": "the register-specific ARC entry points a compiled member imports (objc_retain_xN, objc_release_xN) follow the compiler's register allocation (expo-default's Swift pods on the Mac, ADR 0101)",
        "import.missing._swift_retain_x*": "Xcode's Swift compiler calls the register-specific entry points swift_retain_xN and swift_release_xN from iOS 17.0, open-source Swift swift_retain and swift_release (ADR 0101)",
        "import.missing._swift_release_x*": "Xcode's Swift compiler calls the register-specific entry points swift_retain_xN and swift_release_xN from iOS 17.0, open-source Swift swift_retain and swift_release (ADR 0101)",
        "import.extra._swift_retain": "Xcode's Swift compiler calls the register-specific entry points swift_retain_xN and swift_release_xN from iOS 17.0, open-source Swift swift_retain and swift_release (ADR 0101)",
        "import.extra._swift_release": "Xcode's Swift compiler calls the register-specific entry points swift_retain_xN and swift_release_xN from iOS 17.0, open-source Swift swift_retain and swift_release (ADR 0101)",
        "import.missing._swift_conformsToProtocol2": "Xcode's Swift compiler checks protocol conformances with swift_conformsToProtocol2 from iOS 17.0, open-source Swift with swift_conformsToProtocol (ADR 0101)",
        "import.extra._swift_conformsToProtocol": "Xcode's Swift compiler checks protocol conformances with swift_conformsToProtocol2 from iOS 17.0, open-source Swift with swift_conformsToProtocol (ADR 0101)",
        "import.extra.dyld_stub_binder": "lld imports dyld_stub_binder whenever libSystem exports it (referenceStubBinder, lld/MachO/Driver.cpp)",
        "swift.compiler-version": "the control block records the compiler's version (ADR 0101)",
        "swift.source-times": "the source files' modification times, which the checkout and the build set (emitFileListRecord, swift's lib/Serialization/SerializeDoc.cpp)",
        "swift.source-path-case": "source paths the project spells in another case than the disk, which a build on a case-sensitive file system gives the compiler as the disk spells them (BACKLOG B-062; nomac build --case-aliases keeps the project's)",
        "swift.binary-module": "a binary module records the compiler's version, its Clang modules' hashes and its search and plugin paths; its interface is compared through its .abi.json, identical (ADR 0101)",
        "swift.generated-header": "the generated header's first comment names the compiler (ADR 0101)",
        "dsym.relocations": "the debug map's relocations follow the compiler's code; their header is identical (ADR 0101)",
        "archive.symbol-offsets": "the ranlib table records each symbol's member by offset, which follows the compiled members' sizes",
        "appintents.set-order": "Xcode's App Intents tool writes each parameter's resolvable input types, root.ssu.yaml's parameter variables and locales, and extract.packagedata's keys in set order, which changes from build to build (docs/formats/app-intents.md)",
        "appintents.training-time": "the App Shortcuts training writes its time into nlu.lzfse's header (docs/formats/app-intents.md)",
        "archive.private-externals": "the ranlib table also names the members' private external symbols, which follow the compiler's code (ADR 0101)",
    ]

    /// Every file under `reference` and `other` (the two `Build/Products` folders), in path order.
    /// `sources` are searched, the first time an asset catalog output differs, for the PNGs whose
    /// colors actool converts (`AssetCatalogComparison.convertedImages`).
    public static func compare(reference: String, other: String, sources: [String] = []) throws -> [FileResult] {
        let referenceFiles = try files(under: reference)
        let otherFiles = try files(under: other)
        var converted: Set<AssetCatalogComparison.ConvertedImage>?
        let convertedImages = {
            if converted == nil { converted = AssetCatalogComparison.convertedImages(under: sources) }
            return converted!
        }
        return try referenceFiles.union(otherFiles).sorted().map { path in
            guard referenceFiles.contains(path) else { return FileResult(path: path, outcome: .extra) }
            guard otherFiles.contains(path) else { return FileResult(path: path, outcome: .missing) }
            return FileResult(path: path, outcome: try compareFile(reference + "/" + path, other + "/" + path, convertedImages: convertedImages))
        }
    }

    /// The files and symbolic links under `root`, relative to it; symbolic links are not followed.
    static func files(under root: String) throws -> Set<String> {
        guard FileSystem.isDirectory(root) else { return [] }
        var result = Set<String>()
        var pending = [""]
        while let directory = pending.popLast() {
            for name in try FileSystem.sortedContents(of: root + "/" + directory) {
                let path = directory.isEmpty ? name : directory + "/" + name
                let attributes = try FileManager.default.attributesOfItem(atPath: root + "/" + path)
                if attributes[.type] as? FileAttributeType == .typeDirectory {
                    pending.append(path)
                } else {
                    result.insert(path)
                }
            }
        }
        return result
    }

    static func compareFile(_ reference: String, _ other: String, convertedImages: () -> Set<AssetCatalogComparison.ConvertedImage> = { [] }) throws -> Outcome {
        let referenceLink = try? FileManager.default.destinationOfSymbolicLink(atPath: reference)
        let otherLink = try? FileManager.default.destinationOfSymbolicLink(atPath: other)
        if referenceLink != nil || otherLink != nil {
            return referenceLink == otherLink ? .identical
                : .different(["symbolic link to \(referenceLink ?? "nothing") in Xcode's, \(otherLink ?? "nothing") in nomac's"])
        }
        guard let a = FileManager.default.contents(atPath: reference), let b = FileManager.default.contents(atPath: other) else {
            throw NomacError("cannot read the file", path: FileManager.default.isReadableFile(atPath: reference) ? other : reference)
        }
        if a == b { return .identical }
        let name = (reference as NSString).lastPathComponent
        if StaticArchive.isArchive(path: reference) && StaticArchive.isArchive(path: other) {
            return try compareArchives(try StaticArchive(path: reference), try StaticArchive(path: other))
        }
        if MachOStructure.isMachO(path: reference) && MachOStructure.isMachO(path: other) {
            return judge(MachOStructure.differences(try MachOStructure(path: reference), try MachOStructure(path: other)))
        }
        let catalog = FileManager.default.contents(atPath: (reference as NSString).deletingLastPathComponent + "/Assets.car")
        let converted = ["car", "png"].contains((name as NSString).pathExtension) ? convertedImages() : []
        switch AssetCatalogComparison.compare(fileName: name, xcode: a, nomac: b, xcodeCatalog: catalog, converted: converted) {
        case .identical?: return .identical
        case .equivalent(let causes)?: return .equivalent(causes)
        case .different(let reasons)?: return .different(reasons)
        case nil: break
        }
        switch (name as NSString).pathExtension {
        case "swiftdoc", "swiftsourceinfo":
            return try compareBitstreams(reference, other)
        case "swiftmodule":
            let interface = (reference as NSString).deletingPathExtension + ".abi.json"
            let otherInterface = (other as NSString).deletingPathExtension + ".abi.json"
            guard let x = FileManager.default.contents(atPath: interface), let y = FileManager.default.contents(atPath: otherInterface) else {
                return .different(["no .abi.json beside the binary module to compare its interface with"])
            }
            return x == y ? .equivalent([documented["swift.binary-module"]!]) : .different(["its .abi.json differs"])
        default:
            break
        }
        let referenceText = String(decoding: a, as: UTF8.self)
        let otherText = String(decoding: b, as: UTF8.self)
        if name.hasSuffix("-Swift.h") {
            return compareLines(referenceText, otherText, documentedPrefix: "// Generated by ", cause: documented["swift.generated-header"]!)
        }
        if reference.contains(".dSYM/Contents/Resources/Relocations/"), name.hasSuffix(".yml") {
            let header = { (text: String) in text.components(separatedBy: "\n").prefix { $0 != "relocations:" } }
            return header(referenceText) == header(otherText) && referenceText.contains("\nrelocations:")
                ? .equivalent([documented["dsym.relocations"]!]) : .different(["the relocation map's header differs"])
        }
        if name == "nlu.lzfse", reference.contains("/Metadata.appintents/nlu/") || reference.contains(".lproj/nlu.appintents/") {
            return AppShortcutsTraining.compareNLU([UInt8](a), [UInt8](b))
        }
        if reference.contains("/Metadata.appintents/"), AppIntentsMetadata.sameButForSetOrder(name, referenceText, otherText) {
            return .equivalent([documented["appintents.set-order"]!])
        }
        return .different(["the bytes differ"])
    }

    /// Equivalent when every structural difference is documented: the bytes differ, so the
    /// contents do.
    static func judge(_ differences: [MachOStructure.Difference]) -> Outcome {
        let withoutStackChecks = differences.contains { $0.key == "import.missing.___chkstk_darwin" }
        let withSelectorReferences = differences.contains { $0.key == "section.extra.__DATA,__objc_selrefs" }
        let withoutRelativeMethodLists = differences.contains { $0.key == "section.missing.__TEXT,__objc_methlist" }
        let unexplained = differences.filter {
            cause(of: $0.key) == nil || ($0.key == "command.missing.LC_LINKER_OPTIMIZATION_HINT" && !withoutStackChecks)
                || ($0.key == "command.extra.LC_LINKER_OPTIMIZATION_HINT" && !withSelectorReferences)
                || ($0.key == "section.extra.__DATA,__objc_data" && !withoutRelativeMethodLists)
        }
        guard unexplained.isEmpty else { return .different(unexplained.map(\.description)) }
        var causes = [documented["mach-o.contents"]!]
        for difference in differences where !causes.contains(cause(of: difference.key)!) {
            causes.append(cause(of: difference.key)!)
        }
        return .equivalent(causes)
    }

    /// The same members in the same order with the same header fields (sizes aside), each Mach-O
    /// member judged as a file is, every other member identical, and then the ranlib table naming
    /// the same symbols in the same members: a member's difference explains the table's.
    static func compareArchives(_ reference: StaticArchive, _ other: StaticArchive) throws -> Outcome {
        guard reference.members.map(\.name) == other.members.map(\.name) else {
            return .different(["members \(reference.members.map(\.name)) in Xcode's, \(other.members.map(\.name)) in nomac's"])
        }
        var causes: [String] = []
        let pairs = zip(reference.members, other.members).filter { $0 != $1 }
        for (x, y) in pairs.filter({ !StaticArchive.isSymbolTable($0.0) }) + pairs.filter({ StaticArchive.isSymbolTable($0.0) }) {
            guard x.attributes == y.attributes else { return .different(["member \(x.name)'s header differs"]) }
            guard x.contents != y.contents else { continue }
            let outcome: Outcome
            if StaticArchive.isSymbolTable(x) {
                outcome = try compareSymbolTables(reference, x, other, y)
            } else if x.contents.starts(with: [0xcf, 0xfa, 0xed, 0xfe]), y.contents.starts(with: [0xcf, 0xfa, 0xed, 0xfe]) {
                outcome = judge(MachOStructure.differences(try MachOStructure(file: MachOReader(bytes: x.contents, path: x.name)),
                                                           try MachOStructure(file: MachOReader(bytes: y.contents, path: y.name))))
            } else {
                outcome = .different(["the bytes differ"])
            }
            switch outcome {
            case .equivalent(let found):
                causes += found.filter { !causes.contains($0) }
            case .different(let found):
                return .different(found.map { "member \(x.name): \($0)" })
            default:
                break
            }
        }
        return .equivalent(causes)
    }

    /// The ranlib tables, once the members are known to be identical or equivalent: the same
    /// entries, or the same once those of the members' private external symbols are left out
    /// (expo-default's `libExpoKeepAwake.a`: Swift metadata caches `…GMR`, `…GMd` in Xcode's,
    /// `…GMD` in swift.org's, weak private externals that the member comparison leaves out).
    static func compareSymbolTables(_ reference: StaticArchive, _ x: StaticArchive.Member, _ other: StaticArchive, _ y: StaticArchive.Member) throws -> Outcome {
        let a = try reference.symbols(of: x)
        let b = try other.symbols(of: y)
        guard a != b else { return .equivalent([documented["archive.symbol-offsets"]!]) }
        func visible(_ entries: [StaticArchive.Entry], _ archive: StaticArchive) throws -> [StaticArchive.Entry] {
            let hidden = try archive.privateExternals()
            return entries.filter { !(hidden[$0.member]?.contains($0.symbol) ?? false) }
        }
        return try visible(a, reference) == visible(b, other)
            ? .equivalent([documented["archive.private-externals"]!]) : .different(["the ranlib table names other symbols"])
    }

    /// The documented cause of the difference `key`.
    static func cause(of key: String) -> String? {
        documented[key] ?? documented.keys.sorted().first { $0.hasSuffix("*") && key.hasPrefix($0.dropLast()) }.map { documented[$0]! }
    }

    /// The same records, but for the compiler's version in the control block and the source
    /// files' modification times.
    private static func compareBitstreams(_ reference: String, _ other: String) throws -> Outcome {
        let a = try SwiftBitstream(path: reference).records
        let b = try SwiftBitstream(path: other).records
        guard a.count == b.count else { return .different(["\(a.count) bitstream records in Xcode's, \(b.count) in nomac's"]) }
        var causes: [String] = []
        for (index, (x, y)) in zip(a, b).enumerated() where x != y {
            guard let cause = bitstreamCause(x, y) else { return .different(["bitstream record \(index) (blocks \(x.blocks), code \(x.code)) differs"]) }
            if !causes.contains(cause) { causes.append(cause) }
        }
        return .equivalent(causes)
    }

    /// The documented cause of a difference between two bitstream records, if it has one.
    static func bitstreamCause(_ x: SwiftBitstream.Record, _ y: SwiftBitstream.Record) -> String? {
        guard x.blocks == y.blocks, x.code == y.code, x.fields == y.fields else { return nil }
        if SwiftBitstream.isCompilerVersion(x) { return documented["swift.compiler-version"] }
        guard let first = x.blob, let second = y.blob else { return nil }
        if SwiftBitstream.isSourceFileList(x), SwiftBitstream.sameSourceFiles(first, second) { return documented["swift.source-times"] }
        if SwiftBitstream.isSourcePathText(x), first.count == second.count,
           zip(first, second).allSatisfy({ $0 == $1 || asciiLowercase($0) == asciiLowercase($1) }) {
            return documented["swift.source-path-case"]
        }
        return nil
    }

    private static func asciiLowercase(_ byte: UInt8) -> UInt8 {
        (65...90).contains(byte) ? byte + 32 : byte
    }

    /// The same lines, but for those that start with `documentedPrefix` on both sides.
    private static func compareLines(_ reference: String, _ other: String, documentedPrefix: String, cause: String) -> Outcome {
        let a = reference.components(separatedBy: "\n")
        let b = other.components(separatedBy: "\n")
        guard a.count == b.count else { return .different(["\(a.count) lines in Xcode's, \(b.count) in nomac's"]) }
        for (index, (x, y)) in zip(a, b).enumerated() where x != y && !(x.hasPrefix(documentedPrefix) && y.hasPrefix(documentedPrefix)) {
            return .different(["line \(index + 1) differs"])
        }
        return .equivalent([cause])
    }
}
