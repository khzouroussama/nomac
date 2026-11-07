import Foundation
import NomacCore
import NomacSigning
import NomacVerify

/// `nomac verify --build`'s `extension` checks (docs/VERIFICATION.md "Extension checks"): one for
/// each product nested in an app (an extension in `PlugIns` or `Extensions`, an App Clip in
/// `AppClips`, a watch app in `Watch`, and what those nest in turn) at each stage that has it, the
/// unsigned build, the archive and the IPA. A nested product passes when each of its files does by
/// the rules of the stage's own comparison (where it is embedded, its `Info.plist`, its signature's
/// entitlements and other fields), and, once signed, when the bundle holding it sealed the signature
/// it ended up with, which a parent signed before its nested code would not have.
enum ExtensionChecks {
    typealias Check = VerificationReport.Check

    /// The folders of an app whose bundles are nested code it embeds (docs/formats/extensions.md).
    static let nestingFolders: Set<String> = ["PlugIns", "Extensions", "AppClips", "Watch"]

    /// The innermost nested product holding `path`: the bundle in a nesting folder of an `.app`, or
    /// an extension's dSYM in an archive's `dSYMs`. nil for what is not part of one, the products of
    /// a watch configuration's folder too, which the iOS app's copy counts.
    static func nestedProduct(of path: String) -> String? {
        let components = path.split(separator: "/").map(String.init)
        // Xcode tells two products of one name apart with a number (`Widget.appex 1.dSYM`, `all`).
        if components.count >= 2, components[0] == "dSYMs", components[1].contains(".appex"), components[1].hasSuffix(".dSYM") {
            return components[0...1].joined(separator: "/")
        }
        guard let first = components.first, !first.hasSuffix("-watchos") else { return nil }
        let bundle = components.indices.dropFirst(2).last { index in
            components[index - 2].hasSuffix(".app") && nestingFolders.contains(components[index - 1])
                && (components[index].hasSuffix(".appex") || components[index].hasSuffix(".app"))
        }
        return bundle.map { components[...$0].joined(separator: "/") }
    }

    /// The checks of the nested products among `results`, named `<stage> <product>`. `seals` gives
    /// the trees the results' paths are relative to at a signed stage.
    static func checks(_ results: [BuildProducts.FileResult], stage: String, seals: (reference: String, other: String)? = nil, detailLimit: Int) -> [Check] {
        var products: [String: [BuildProducts.FileResult]] = [:]
        for result in results {
            if let product = nestedProduct(of: result.path) { products[product, default: []].append(result) }
        }
        return products.keys.sorted().map { product in
            var check = BuildVerification.productCheck(name: "\(stage) \(product)", results: products[product]!, kind: "extension", detailLimit: detailLimit)
            if let seals, sealProblem(root: seals.reference, product: product) == nil, let problem = sealProblem(root: seals.other, product: product) {
                check.status = .different
                check.detail.insert(problem, at: 0)
            }
            return check
        }
    }

    /// What is wrong with how the bundle holding `product` under `root` sealed it, or nil. Its
    /// `CodeResources` records the hash of each file of what it nests, the signature's among them
    /// (`hash2`, for every kind of nested product: docs/formats/extensions.md). A product that is
    /// missing, or in an unsigned parent, is the file comparison's to report.
    static func sealProblem(root: String, product: String) -> String? {
        let components = product.split(separator: "/").map(String.init)
        guard components.count >= 3, components[0] != "dSYMs" else { return nil }
        let nested = components.suffix(2).joined(separator: "/")
        let parent = root + "/" + components.dropLast(2).joined(separator: "/")
        guard let sealed = propertyList(parent + "/_CodeSignature/CodeResources")?["files2"] as? [String: Any], FileSystem.isDirectory(root + "/" + product) else { return nil }
        let files = sealed.filter { $0.key.hasPrefix(nested + "/") }
        guard !files.isEmpty else { return "the bundle holding it does not seal \(nested)" }
        for (name, entry) in files.sorted(by: { $0.key < $1.key }) {
            guard let recorded = (entry as? [String: Any])?["hash2"] as? Data else { continue }
            guard let contents = FileSystem.contents(atPath: parent + "/" + name), SealedHashes.file(contents: [UInt8](contents)) == [UInt8](recorded) else {
                return "the bundle holding it sealed another \(name): signed before it"
            }
        }
        return nil
    }

    private static func propertyList(_ path: String) -> [String: Any]? {
        FileSystem.contents(atPath: path).flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
    }
}
