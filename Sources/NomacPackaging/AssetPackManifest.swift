import Foundation
import NomacCore
import NomacPlist

/// The `AssetPackManifest.plist` an export writes into an app with on-demand resources (`odr`
/// and `odr-three` experiments, `AppStoreExportTests`; docs/formats/ipa.md): the build's
/// `AssetPackManifestTemplate.plist` as Foundation writes again the objects it read, with each
/// resource's `URL` the pack's path in the app (`OnDemandResources/<pack>`, `isStreamable` 0)
/// or under the export's base URL (`isStreamable` 1); the template is removed.
///
/// The objects keep the template's sharing: one read object stays one, two equal ones stay two
/// (Swift Build writes `isStreamable` once per resource, a self-written template once); the new
/// strings are objects of their own, integers are shared by value, and every dictionary's keys
/// take Foundation's order.
enum AssetPackManifest {
    /// Writes the manifest of `app` with its packs under `base` (nil: in the app), and returns it.
    @discardableResult
    static func write(in app: String, base: String?) throws -> Data {
        let template = app + "/AssetPackManifestTemplate.plist"
        guard let data = FileManager.default.contents(atPath: template) else { throw NomacError("could not read file", path: template) }
        let (objects, top) = try BinaryPropertyList.objects(from: [UInt8](data), path: template)
        var rewrite = Rewrite(template: objects, path: template, base: base)
        _ = try rewrite.copy(top, resources: false)
        let manifest = BinaryPropertyList.data(objects: rewrite.output)
        try FileSystem.write(manifest, to: app + "/AssetPackManifest.plist")
        try FileManager.default.removeItem(atPath: template)
        return manifest
    }

    struct Rewrite {
        let template: [BinaryPropertyList.Object]
        let path: String
        let base: String?
        var output: [BinaryPropertyList.Object] = []
        var copied: [Int: Int] = [:]
        var integers: [Int: Int] = [:]

        init(template: [BinaryPropertyList.Object], path: String, base: String?) {
            self.template = template
            self.path = path
            self.base = base
        }

        mutating func append(_ object: BinaryPropertyList.Object) -> Int {
            output.append(object)
            return output.count - 1
        }

        mutating func integer(_ value: Int) -> Int {
            if let index = integers[value] { return index }
            integers[value] = output.count
            return append(.integer(value))
        }

        /// Copies template object `index`; the dictionaries of the `resources` array get their
        /// new `URL` and `isStreamable`.
        mutating func copy(_ index: Int, resources isResource: Bool) throws -> Int {
            guard template.indices.contains(index) else { throw NomacError("malformed asset pack manifest template", path: path) }
            switch template[index] {
            case .integer(let value):
                return integer(value)
            case .array(let elements):
                let copy = append(.array([]))
                var references: [Int] = []
                for element in elements { references.append(try self.copy(element, resources: isResource)) }
                output[copy] = .array(references)
                return copy
            case .dictionary(let keys, let values):
                let names = try keys.map { key -> String in
                    guard template.indices.contains(key), case .string(let name) = template[key] else {
                        throw NomacError("malformed asset pack manifest template", path: path)
                    }
                    return name
                }
                let copy = append(.dictionary(keys: [], values: []))
                let order = try FoundationHashTable.created(with: names.sorted()).keys
                var keyReferences: [Int] = []
                for name in order { keyReferences.append(try self.copy(keys[names.firstIndex(of: name)!], resources: false)) }
                var valueReferences: [Int] = []
                for name in order {
                    let value = values[names.firstIndex(of: name)!]
                    if isResource, name == "URL", case .string(let url) = template[value] {
                        // A base URL ending in `/` gets no second one (signing experiments
                        // `odr-shapes`, `release-testing-base-slash`).
                        let folder = base ?? "OnDemandResources"
                        valueReferences.append(append(.string(folder + (folder.hasSuffix("/") ? "" : "/") + (url as NSString).lastPathComponent)))
                    } else if isResource, name == "isStreamable" {
                        valueReferences.append(integer(base == nil ? 0 : 1))
                    } else {
                        valueReferences.append(try self.copy(value, resources: name == "resources"))
                    }
                }
                output[copy] = .dictionary(keys: keyReferences, values: valueReferences)
                return copy
            default:
                if let copy = copied[index] { return copy }
                let copy = append(template[index])
                copied[index] = copy
                return copy
            }
        }
    }
}
