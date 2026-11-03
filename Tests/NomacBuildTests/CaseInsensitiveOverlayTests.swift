import Foundation
import Testing
@testable import NomacBuild
@testable import NomacPIF

/// The overlay that gives clang and the Swift compiler a Mac's case-insensitive lookups on Linux
/// (BACKLOG B-062).
@Suite struct CaseInsensitiveOverlayTests {
    @Test func listsHeadersAndRemapsBuiltFrameworks() throws {
        let root = FileManager.default.temporaryDirectory.path + "/nomac-overlay-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: root) }
        for name in ["Frameworks/OpenSSL.framework/Headers/evp.h", "Sources/App.swift", "Sources/Bridge.H", "Empty/notes.txt"] {
            try FileManager.default.createDirectory(atPath: root + "/" + (name as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try Data().write(to: URL(fileURLWithPath: root + "/" + name))
        }
        let data = try CaseInsensitiveOverlay.document(sourceRoots: [root], frameworks: ["Kit.framework"], productFolders: ["/products"])
        let file = { (name: String, path: String) in #"{"external-contents":"\#(root)/\#(path)","name":"\#(name)","type":"file"}"# }
        let folder = { (name: String, contents: String) in #"{"contents":[\#(contents)],"name":"\#(name)","type":"directory"}"# }
        let headers = folder("Frameworks", folder("OpenSSL.framework", folder("Headers", file("evp.h", "Frameworks/OpenSSL.framework/Headers/evp.h"))))
            + "," + folder("Sources", file("Bridge.H", "Sources/Bridge.H"))
        #expect(String(decoding: data, as: UTF8.self) == #"{"case-sensitive":"false","roots":[{"contents":[\#(headers)],"name":"\#(root)","type":"directory"},"#
            + #"{"external-contents":"/products/Kit.framework","name":"/products/Kit.framework","type":"directory-remap"}],"version":0}"#)
    }

    @Test func namesFrameworkProductsAndXCFrameworksFrameworks() throws {
        let root = FileManager.default.temporaryDirectory.path + "/nomac-overlay-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: root) }
        for folder in ["Vendor/X.xcframework/ios-arm64/X.framework/Headers", "Plain/Y.framework/Headers"] {
            try FileManager.default.createDirectory(atPath: root + "/" + folder, withIntermediateDirectories: true)
        }
        func target(_ product: String) -> PIFDocument.Object {
            .init(type: "target", signature: product, contents: .object(["productReference": .object(["name": .string(product)])]))
        }
        let document = PIFDocument(objects: [target("Kit.framework"), target("$(PRODUCT_NAME).framework"), target("App.app")])
        #expect(CaseInsensitiveOverlay.frameworkNames(document: document, roots: [root]) == ["Kit.framework", "X.framework"])
    }
}
