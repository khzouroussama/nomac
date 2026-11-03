import Foundation
import Testing
import NomacCore
@testable import NomacPIF
import NomacTestSupport

/// File types of synchronized-folder members, from the Swift Build specifications installed
/// next to the test runner. Expected values are the types Xcode 27 reported for the same
/// kinds of files in netnewswire and icecubes (docs/formats/pif.md).
@Suite struct FileTypeRegistryTests {
    let registry: FileTypeRegistry
    let directory: TemporaryDirectory

    init() throws {
        registry = try FileTypeRegistry.installed()
        directory = try TemporaryDirectory()
    }

    func type(of name: String, contents: String = "", bytes: [UInt8]? = nil) throws -> String? {
        let path = directory.path + "/" + name
        try FileSystem.write(bytes.map { Data($0) } ?? Data(contents.utf8), to: path)
        return registry.fileType(atPath: path, isDirectory: false)
    }

    func type(ofDirectory name: String, containing files: [String] = []) throws -> String? {
        let path = directory.path + "/" + name
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        for file in files { try FileSystem.write(Data(), to: path + "/" + file) }
        return registry.fileType(atPath: path, isDirectory: true)
    }

    @Test func extensionsFromTheSpecifications() throws {
        #expect(try type(of: "a.swift") == "sourcecode.swift")
        #expect(try type(of: "a.m") == "sourcecode.c.objc")
        #expect(try type(of: "a.h") == "sourcecode.c.h")
        #expect(try type(of: "a.xib") == "file.xib")
        #expect(try type(of: "a.storyboard") == "file.storyboard")
        #expect(try type(of: "a.xcstrings") == "text.json.xcstrings")
        #expect(try type(of: "a.md") == "net.daringfireball.markdown")
        #expect(try type(of: "a.entitlements") == "text.plist.entitlements")
        #expect(try type(of: "a.xcconfig") == "text.xcconfig")
        #expect(try type(of: "a.js") == "sourcecode.javascript")
    }

    @Test func extensionsMatchCaseSensitivelyFirst() throws {
        #expect(try type(of: "b.H") == "sourcecode.cpp.h")
        #expect(try type(of: "b.M") == "sourcecode.cpp.objcpp")
        #expect(try type(of: "b.SWIFT") == "sourcecode.swift")
    }

    /// `pif-experiments` untyped-duplicates and untyped-folders: of two types that claim an
    /// extension the last one keeps it, and a file named like a folder is typed by its contents.
    @Test func extensionsTwoTypesClaimAndFolderExtensionsOnFiles() throws {
        #expect(try type(of: "text.o", contents: "x\n") == "compiled.object-library")
        #expect(try type(of: "x.ll", contents: "x\n") == "sourcecode.asm.llvm")
        #expect(try type(ofDirectory: "Y.appex") == "wrapper.extensionkit-extension")
        #expect(try type(of: "P.framework", contents: "x\n") == "text")
        #expect(try type(of: "P.bundle", bytes: machO(1)) == "compiled.mach-o.objfile")
        #expect(try type(of: "P.xcdatamodeld", contents: "x\n") == "text")
        #expect(try type(of: "P.xcdatamodel", contents: "x\n") == "wrapper.xcdatamodel")
        #expect(try type(of: "P.storyboardc", contents: "x\n") == "wrapper.storyboardc")
    }

    /// `pif-experiments` untyped-macho: a Mach-O or archive header types a file whose extension
    /// names a Mach-O type, and no other.
    @Test func machOHeadersDecideMachOExtensions() throws {
        #expect(try type(of: "object.dylib", bytes: machO(1)) == "compiled.mach-o.objfile")
        #expect(try type(of: "bundle.dylib", bytes: machO(8)) == "compiled.mach-o.bundle")
        #expect(try type(of: "archive.o", bytes: Array("!<arch>\n".utf8)) == "archive.ar")
        #expect(try type(of: "text.dylib", contents: "x\n") == "compiled.mach-o.dylib")
        #expect(try type(of: "sh.o", contents: "#!/bin/sh\n") == "compiled.object-library")
        #expect(try type(of: "object.png", bytes: machO(1)) == "image.png")
        #expect(try type(of: "object.a", bytes: machO(1)) == "archive.ar")
        #expect(try type(of: "object.tbd", bytes: machO(1)) == "sourcecode.text-based-dylib-definition")
    }

    func machO(_ fileType: UInt8) -> [UInt8] {
        [0xCF, 0xFA, 0xED, 0xFE, 0x0C, 0, 0, 1, 0, 0, 0, 0, fileType, 0, 0, 0] + [UInt8](repeating: 0, count: 16)
    }

    @Test func propertyListsByContents() throws {
        #expect(try type(of: "x.plist", contents: "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\"><dict/></plist>\n") == "text.plist.xml")
        #expect(try type(of: "y.plist", contents: "<plist version=\"1.0\"><dict/></plist>\n") == "text.plist.xml")
        #expect(try type(of: "z.plist", bytes: Array("bplist00".utf8) + [0, 1]) == "text.plist.binary")
    }

    @Test func unclaimedExtensionsByContents() throws {
        #expect(try type(of: "Feeds.opml", contents: "<?xml version=\"1.0\"?>\n<opml/>\n") == "text.xml")
        #expect(try type(of: "PrivacyInfo.xcprivacy", contents: "\u{FEFF}<?xml version=\"1.0\"?><plist/>") == "text.xml")
        #expect(try type(of: "App.provisionprofile", bytes: [0x30, 0x82, 0x01, 0x00]) == "file")
        #expect(try type(of: "notes.zzz", contents: "hello\n") == "text")
        #expect(try type(of: "indented.zzz", contents: "  <?xml version=\"1.0\"?><a/>") == "text")
    }

    /// nextcloud's `.tx/config` and the `pif-experiments` untyped files.
    @Test func unclaimedFilesByNameAndContents() throws {
        #expect(try type(of: "config", contents: "[main]\nhost = https://www.transifex.com\n") == "text")
        #expect(try type(of: "empty") == "text")
        #expect(try type(of: "latin1", bytes: Array("caf".utf8) + [0xE9, 0x0A]) == "text")
        #expect(try type(of: "utf16", bytes: [0xFF, 0xFE, 0x61, 0x00, 0x01, 0x00]) == "text")
        #expect(try type(of: "nul", bytes: [0x61, 0x00, 0x62]) == "file")
        #expect(try type(of: "late-nul", bytes: [UInt8](repeating: 0x61, count: 1024) + [0x00]) == "text")
        #expect(try type(of: "ten-percent", bytes: [UInt8](repeating: 0x01, count: 10) + [UInt8](repeating: 0x61, count: 90)) == "text")
        #expect(try type(of: "eleven-percent", bytes: [UInt8](repeating: 0x01, count: 11) + [UInt8](repeating: 0x61, count: 89)) == "file")
        #expect(try type(of: "Makefile", contents: "bplist00") == "sourcecode.make")
        #expect(try type(of: "AppIntents.vocabulary", bytes: [0x00]) == "text.plist.vocabulary")
        #expect(try type(of: "script", contents: "#!/bin/sh\necho hi\n") == "text.script.sh")
        #expect(try type(of: "env-script", contents: "#!/usr/bin/env bash\n") == "text")
        #expect(try type(of: "data", contents: "bplist00 hello") == "file.bplist")
        #expect(try type(of: "tool", bytes: machO(2)) == "compiled.mach-o.executable")
        #expect(try type(of: "object", bytes: machO(1)) == "compiled.mach-o.objfile")
        #expect(try type(of: "other", bytes: machO(10)) == "compiled.mach-o")
        #expect(try type(of: "library", bytes: Array("!<arch>\n".utf8)) == "archive.ar")
        #expect(registry.fileType(atPath: directory.path + "/missing", isDirectory: false) == "text")
        #expect(registry.fileType(atPath: directory.path + "/missing.zzz", isDirectory: false) == "file")
        #expect(registry.fileType(atPath: directory.path + "/Makefile.missing/Makefile", isDirectory: false) == "text")
        #expect(registry.fileType(atPath: directory.path + "/missing.txt", isDirectory: false) == "text")
        #expect(registry.fileType(atPath: directory.path + "/Missing.framework", isDirectory: false) == "wrapper.framework")
    }

    @Test func directories() throws {
        #expect(try type(ofDirectory: "Assets.xcassets", containing: ["Contents.json"]) == "folder.assetcatalog")
        #expect(try type(ofDirectory: "AppIcon.icon") == "folder.iconcomposer.icon")
        #expect(try type(ofDirectory: "Kit.framework") == "wrapper.framework")
        #expect(try type(ofDirectory: "Model.xcdatamodeld") == "wrapper.xcdatamodeld")
        #expect(try type(ofDirectory: "Account", containing: ["Package.swift"]) == "wrapper")
        #expect(try type(ofDirectory: "Views") == nil)
    }

    /// `pif-experiments` untyped-folders: a folder takes its extension's type unless it is a text
    /// type; of the extensions no type claims, those the Mac registers as packages are wrappers.
    @Test func foldersWithOtherExtensions() throws {
        #expect(try type(ofDirectory: "X.a") == "archive.ar")
        #expect(try type(ofDirectory: "X.png") == "image.png")
        #expect(try type(ofDirectory: "X.o") == "compiled.object-library")
        #expect(try type(ofDirectory: "X.xib") == "file.xib")
        #expect(try type(ofDirectory: "X.xcmappingmodel") == "wrapper.xcmappingmodel")
        #expect(try type(ofDirectory: "X.swift") == nil)
        #expect(try type(ofDirectory: "X.json") == nil)
        #expect(try type(ofDirectory: "X.mlmodel") == nil)
        #expect(try type(ofDirectory: "X.mlmodelc") == "wrapper")
        #expect(try type(ofDirectory: "X.plugin") == "wrapper")
        #expect(try type(ofDirectory: "X.rcproject") == nil)
        #expect(try type(ofDirectory: "X.zzz") == nil)
    }

    @Test func flagsFollowBasedOn() {
        #expect(registry.lineage(of: "sourcecode.swift").contains("sourcecode"))
        #expect(registry.isFolderType("folder.assetcatalog"))
        #expect(registry.isFolderType("wrapper.framework"))
        #expect(!registry.isFolderType("wrapper.storyboardc"))
        #expect(registry.isTextType("sourcecode.swift"))
        #expect(!registry.isTextType("wrapper.xcdatamodel"))
    }
}

/// The types Xcode 27.0 gave file references with neither `lastKnownFileType` nor
/// `explicitFileType` (envelope-experiments `file-type-none`), written again here.
@Suite struct UntypedReferenceTests {
    let registry: FileTypeRegistry
    let directory: TemporaryDirectory

    init() throws {
        registry = try FileTypeRegistry.installed()
        directory = try TemporaryDirectory()
    }

    func type(of name: String, _ contents: [UInt8]?, directory isDirectory: Bool = false) throws -> String {
        let path = directory.path + "/" + name
        if isDirectory {
            try FileSystem.write(Data(), to: path + "/Contents.json")
        } else if let contents {
            try FileSystem.write(Data(contents), to: path)
        }
        return registry.referenceType(name: name, at: path)
    }

    @Test func theExtensionDecidesOnDiskOrNot() throws {
        #expect(try type(of: "Helper.swift", Array("struct Helper {}\n".utf8)) == "sourcecode.swift")
        #expect(try type(of: "Missing.swift", nil) == "sourcecode.swift")
        #expect(try type(of: "Picture.png", []) == "image.png")
        #expect(try type(of: "Missing.png", nil) == "image.png")
        #expect(try type(of: "Readme.md", Array("# App\n".utf8)) == "net.daringfireball.markdown")
        #expect(try type(of: "Upper.H", []) == "sourcecode.cpp.h")
        #expect(try type(of: "Script.SH", []) == "text.script.sh")
        #expect(try type(of: "Missing.bundle", nil) == "wrapper.plug-in")
        #expect(registry.referenceType(name: "Built.json", at: nil) == "text.json")
    }

    @Test func foldersAreTheirWrapperTypeOrFolder() throws {
        #expect(try type(of: "Images.xcassets", nil, directory: true) == "folder.assetcatalog")
        #expect(try type(of: "Resources.bundle", nil, directory: true) == "wrapper.plug-in")
        #expect(try type(of: "Folder", nil, directory: true) == "folder")
        #expect(try type(of: "Thing.stuff", nil, directory: true) == "folder")
        #expect(try type(of: "Lproj.lproj", nil, directory: true) == "folder")
    }

    @Test func contentsDecideWithoutAKnownExtension() throws {
        #expect(try type(of: "Missing", nil) == "text")
        #expect(try type(of: "Missing.xyz", nil) == "file")
        #expect(try type(of: "Notes", Array("notes\n".utf8)) == "text")
        #expect(try type(of: "Empty.xyz", []) == "text")
        #expect(try type(of: "Latin", [0x63, 0x61, 0x66, 0xE9, 0x0A]) == "text")
        #expect(try type(of: "Blob.xyz", Array(0...255)) == "file")
        #expect(try type(of: "Layout.xyz", Array("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<root/>\n".utf8)) == "text.xml")
        #expect(try type(of: "Shell.xyz", Array("#!/bin/sh\necho\n".utf8)) == "text.script.sh")
        #expect(try type(of: "Zsh", Array("#!/bin/zsh\necho\n".utf8)) == "text.script.sh")
        #expect(try type(of: "Ruby", Array("#!/usr/bin/ruby\nputs\n".utf8)) == "text.script.ruby")
        #expect(try type(of: "Perl", Array("#!/usr/bin/perl\nprint;\n".utf8)) == "text.script.perl")
        #expect(try type(of: "Python", Array("#!/usr/bin/env python3\nprint()\n".utf8)) == "text")
        #expect(try type(of: "Settings.plist", Array("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\"><dict/></plist>\n".utf8)) == "text.plist.xml")
        #expect(try type(of: "Binary.plist", Array("bplist00".utf8) + [0xD0, 0x08]) == "file.bplist")
        #expect(try type(of: "Old.plist", Array("{\n    key = value;\n}\n".utf8)) == "text.plist")
    }

    /// The first 1024 bytes count: byte order marks, control bytes, binary property lists and
    /// the interpreters of `#!` lines at the very start.
    @Test func contentsAreReadInTheirFirstKilobyte() throws {
        #expect(try type(of: "Late1023", Array(repeating: 0x61, count: 1023) + [0, 0x0A]) == "file")
        #expect(try type(of: "Late1024", Array(repeating: 0x61, count: 1024) + [0, 0x0A]) == "text")
        #expect(try type(of: "Escape", Array("text\u{1B}[0m\n".utf8)) == "file")
        #expect(try type(of: "Backspace", [0x74, 0x08, 0x0A]) == "file")
        #expect(try type(of: "Whitespace", [0x61, 0x09, 0x0B, 0x0C, 0x0D, 0x0A, 0x7F, 0xE9]) == "text")
        #expect(try type(of: "Bplist.data", Array("bplist00".utf8) + [0xD0, 0x08]) == "file.bplist")
        #expect(try type(of: "Utf16", [0xFF, 0xFE] + Array("<?xml version=\"1.0\"?>".utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })) == "text.xml")
        #expect(try type(of: "Utf16Shell", [0xFF, 0xFE] + Array("#!/bin/sh\n".utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })) == "text")
        #expect(try type(of: "Utf16NoMark", Array("text\n".utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })) == "file")
        #expect(try type(of: "BomShell", [0xEF, 0xBB, 0xBF] + Array("#!/bin/sh\n".utf8)) == "text")
        #expect(try type(of: "Tcsh", Array("#!/bin/tcsh\n".utf8)) == "text.script.csh")
        #expect(try type(of: "Python", Array("#!/usr/bin/python3\n".utf8)) == "text.script.python")
        #expect(try type(of: "Spaced", Array("#! /bin/sh -e\n".utf8)) == "text.script.sh")
        #expect(try type(of: "Dash", Array("#!/bin/dash\n".utf8)) == "text")
        #expect(try type(of: "EnvRuby", Array("#!/usr/bin/env ruby\n".utf8)) == "text")
    }
}
