import Foundation
import Testing
@testable import NomacVerify

/// Synthetic BOM stores shaped like actool's `Assets.car` for a catalog with an Icon Composer
/// icon (docs/formats/asset-catalog.md), with the run-to-run variations of ADR 0203 and the
/// rendered pixels of ADR 0204 changed one at a time.
@Suite struct AssetCatalogComparisonTests {
    struct Catalog {
        var appearances = ["UIAppearanceAny", "UIAppearanceDark"]
        var facetPart: UInt16 = 220
        var suffix = "0EBCBAA0-A398-4A7B-8538-212B0B9137E2-37630-00000926D44A8D13"
        var width: UInt32 = 1024
        var pixels: [UInt8] = [1, 2, 3, 4]
        var stack = true
        var color: UInt8 = 0
        var photo: [UInt8]?

        func csi(_ name: String, width: UInt32, payload: [UInt8]) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: 184)
            bytes.replaceSubrange(0..<4, with: Array("ISTC".utf8))
            bytes.replaceSubrange(12..<16, with: withUnsafeBytes(of: width.littleEndian, Array.init))
            bytes.replaceSubrange(40..<40 + name.utf8.count, with: Array(name.utf8))
            bytes.replaceSubrange(180..<184, with: withUnsafeBytes(of: UInt32(payload.count).littleEndian, Array.init))
            return bytes + payload
        }

        func key(part: UInt16, identifier: UInt16) -> [UInt8] {
            [part, identifier].flatMap { withUnsafeBytes(of: $0.littleEndian, Array.init) }
        }

        var data: Data {
            var blocks: [[UInt8]] = [[]]
            var variables: [AssetCatalogComparison.Store.Variable] = []
            func add(_ bytes: [UInt8]) -> Int {
                blocks.append(bytes)
                return blocks.count - 1
            }
            func tree(_ name: String, _ entries: [([UInt8], [UInt8])]) {
                var leaf: [UInt8] = [0, 1] + withUnsafeBytes(of: UInt16(entries.count).bigEndian, Array.init) + [UInt8](repeating: 0, count: 8)
                for (key, value) in entries {
                    let k = add(key), v = add(value)
                    leaf += withUnsafeBytes(of: UInt32(v).bigEndian, Array.init) + withUnsafeBytes(of: UInt32(k).bigEndian, Array.init)
                }
                let page = add(leaf)
                let header = Array("tree".utf8) + [0, 0, 0, 1] + withUnsafeBytes(of: UInt32(page).bigEndian, Array.init)
                variables.append(.init(name: name, block: add(header)))
            }
            variables.append(.init(name: "KEYFORMAT", block: add(Array("tmfk".utf8) + [0, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0, 17, 0, 0, 0])))
            tree("APPEARANCEKEYS", appearances.map { (Array($0.utf8), [$0.hasSuffix("Dark") ? 1 : 0, 0]) })
            tree("FACETKEYS", [(Array("expo".utf8), [0, 0, 0, 0, 2, 0, 2, 0] + withUnsafeBytes(of: facetPart.littleEndian, Array.init) + [17, 0, 0, 0]),
                               (Array("Photos/Photo".utf8), [0, 0, 0, 0, 2, 0, 2, 0, 181, 0, 17, 0, 2, 0])])
            let celm = Array("MLEC".utf8) + [3, 0, 0, 0, 4, 0, 0, 0]
            var renditions = [
                (key(part: 220, identifier: 0), csi("expo1024x1024_UIAppearanceAny_\(suffix).png", width: width, payload: celm + pixels)),
                (key(part: 217, identifier: 1), csi("Color", width: 0, payload: [color])),
            ]
            if stack { renditions.append((key(part: 245, identifier: 0), csi("expo.iconstack", width: 1024, payload: []))) }
            if let photo { renditions.append((key(part: 181, identifier: 2), csi("photo.png", width: 4, payload: celm + photo))) }
            tree("RENDITIONS", renditions)
            return Data(AssetCatalogComparison.Store(blocks: blocks, variables: variables).serialized())
        }
    }

    func png(width: UInt8 = 120, idat: [UInt8], secondHalf: UInt8) -> Data {
        func chunk(_ type: String, _ data: [UInt8]) -> [UInt8] {
            withUnsafeBytes(of: UInt32(data.count).bigEndian, Array.init) + Array(type.utf8) + data + [0, 0, 0, 0]
        }
        let header: [UInt8] = [0, 0, 0, width, 0, 0, 0, width, 8, 6, 0, 0, 0]
        let dot = [0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 60, 0, 0, 0, 40, 0, 0, 0, 60, 0, 0, 0, 60, 0, 0, 0x1b, secondHalf] as [UInt8]
        let bytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + chunk("CgBI", [0x50, 0, 0x20, 6]) + chunk("IHDR", header)
            + chunk("iDOT", dot) + chunk("IDAT", idat) + chunk("IDAT", idat.reversed()) + chunk("IEND", [])
        return Data(bytes)
    }

    @Test func theDocumentedLayoutIsReadBack() throws {
        let data = Catalog().data
        let store = try #require(AssetCatalogComparison.Store(Array(data)))
        #expect(store.serialized() == Array(data))
        #expect(AssetCatalogComparison.renderedIconNames(data) == ["expo"])
        // Without a stack, a set whose app icon images are all 1,024 pixels wide is a single-size set.
        #expect(AssetCatalogComparison.renderedIconNames(Catalog(stack: false).data) == ["expo"])
        #expect(AssetCatalogComparison.renderedIconNames(Catalog(width: 120, stack: false).data).isEmpty)
    }

    @Test func actoolsRunToRunVariationsAreEquivalent() {
        let xcode = Catalog(appearances: ["UIAppearanceDark", "UIAppearanceAny"], facetPart: 245, suffix: "A52597A6-0C17-48AA-B6DA-E9292B23BA7E-981-00000926D4CEE76A").data
        #expect(AssetCatalogComparison.compareCatalogs(xcode, Catalog().data) == .equivalent([
            AssetCatalogComparison.appearanceOrder, AssetCatalogComparison.facetPart, AssetCatalogComparison.renderedNames,
        ]))
        #expect(AssetCatalogComparison.compareCatalogs(Catalog().data, Catalog().data) == .identical)
    }

    @Test func renderedPixelsAreEquivalent() {
        #expect(AssetCatalogComparison.compareCatalogs(Catalog(pixels: [9, 9, 9, 9, 9, 9]).data, Catalog().data)
            == .equivalent([AssetCatalogComparison.renderedPixels]))
    }

    @Test func everythingElseDiffers() {
        let plain = Catalog().data
        #expect(AssetCatalogComparison.compareCatalogs(Catalog(width: 512).data, plain) != .identical)
        if case .equivalent = AssetCatalogComparison.compareCatalogs(Catalog(width: 512).data, plain) { Issue.record("a rendered image's header differs") }
        if case .equivalent = AssetCatalogComparison.compareCatalogs(Catalog(color: 1).data, plain) { Issue.record("a color differs") }
        if case .equivalent = AssetCatalogComparison.compareCatalogs(Catalog(suffix: "not-a-uuid").data, plain) { Issue.record("a name differs") }
        if case .equivalent = AssetCatalogComparison.compareCatalogs(Catalog(pixels: [5], stack: false).data, Catalog(stack: false).data) {
            Issue.record("an image without an icon stack is not rendered")
        }
        if case .equivalent = AssetCatalogComparison.compareCatalogs(Catalog(facetPart: 181).data, plain) { Issue.record("a facet differs") }
        var moved = Array(plain)
        moved.insert(0, at: 600)
        if case .equivalent = AssetCatalogComparison.compareCatalogs(Data(moved), plain) { Issue.record("the layout differs") }
    }

    @Test func convertedImagesMayDifferInTheirPixelsOnly() {
        let xcode = Catalog(photo: [1, 2, 3]).data, nomac = Catalog(photo: [1, 2, 4, 5]).data
        let converted: Set<AssetCatalogComparison.ConvertedImage> = [.init(set: "Photo", file: "photo.png")]
        #expect(AssetCatalogComparison.compareCatalogs(xcode, nomac, converted: converted) == .equivalent([AssetCatalogComparison.convertedPixels]))
        if case .equivalent = AssetCatalogComparison.compareCatalogs(xcode, nomac) { Issue.record("an image not converted") }
        if case .equivalent = AssetCatalogComparison.compareCatalogs(xcode, nomac, converted: [.init(set: "Other", file: "photo.png")]) {
            Issue.record("another set's image")
        }
    }

    @Test func iconPNGsDrawnFromAnIconAreComparedByStructure() {
        let catalog = Catalog().data
        let xcode = png(idat: [1, 2, 3], secondHalf: 0xc8)
        let compare = { (name: String, nomac: Data) in
            AssetCatalogComparison.compare(fileName: name, xcode: xcode, nomac: nomac, xcodeCatalog: catalog)
        }
        #expect(compare("expo60x60@2x.png", png(idat: [4, 5, 6, 7], secondHalf: 0xc9)) == .equivalent([AssetCatalogComparison.renderedPixels]))
        #expect(compare("expo76x76@2x~ipad.png", png(idat: [4], secondHalf: 0xc8)) == .equivalent([AssetCatalogComparison.renderedPixels]))
        if case .equivalent = compare("expo60x60@2x.png", png(width: 152, idat: [1, 2, 3], secondHalf: 0xc8)) { Issue.record("the header differs") }
        #expect(compare("other60x60@2x.png", png(idat: [4], secondHalf: 0xc8)) == nil)
        #expect(compare("expo.png", png(idat: [4], secondHalf: 0xc8)) == nil)
        #expect(AssetCatalogComparison.compare(fileName: "expo60x60@2x.png", xcode: xcode, nomac: png(idat: [4], secondHalf: 0xc8), xcodeCatalog: Catalog(width: 120, stack: false).data) == nil)
    }
}
