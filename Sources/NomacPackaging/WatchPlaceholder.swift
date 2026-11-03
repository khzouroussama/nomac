import Foundation
import NomacCore
import NomacPlist

/// What an iPhone variant has in place of its watch app (docs/formats/ipa.md "App thinning",
/// `thinning` `watch`): `com.apple.WatchPlaceholder/<name>.app/Info.plist`, the watch app's
/// Info.plist with `CFBundleExecutable` `Executable`, then `MIPlaceholderArchitectures` (each
/// slice's `CPUType` and `CPUSubtype`, in the file's order) and `CF_MIPlaceholderConstructorVersion`
/// (the exporting Mac's build, whatever the watch app's `BuildMachineOSBuild`, `watch-build`)
/// inserted, as Foundation writes it: each dictionary of the file in the order of one created
/// with its keys in the file's order, the two keys inserted into the top one afterwards.
enum WatchPlaceholder {
    static func write(watch: String, slices: [AppThinning.Slice], into app: String, constructorVersion: String = HostOperatingSystem.macBuild) throws {
        let source = watch + "/Info.plist"
        guard let data = FileManager.default.contents(atPath: source) else { throw NomacError("could not read file", path: source) }
        let bytes = [UInt8](data)
        guard case .dictionary(var entries) = try BinaryPropertyList.value(from: bytes, path: source) else {
            throw NomacError("the watch app's Info.plist is not a dictionary", path: source)
        }
        let (objects, top) = try BinaryPropertyList.objects(from: bytes, path: source)
        var orders: [Set<String>: [String]] = [:]
        for (index, object) in objects.enumerated() {
            guard case .dictionary(let keys, _) = object else { continue }
            let names = keys.compactMap { key -> String? in if case .string(let name) = objects[key] { name } else { nil } }
            var table = try FoundationHashTable.created(with: names)
            if index == top {
                for key in ["MIPlaceholderArchitectures", "CF_MIPlaceholderConstructorVersion"] { try table.insert(key) }
            }
            orders[Set(table.keys)] = table.keys
        }
        let architecture = try FoundationHashTable.created(with: ["CPUType", "CPUSubtype"]).keys
        orders[Set(architecture)] = architecture
        entries["CFBundleExecutable"] = .string("Executable")
        entries["MIPlaceholderArchitectures"] = .array(slices.map { .dictionary(["CPUType": .integer($0.cpuType), "CPUSubtype": .integer($0.cpuSubtype)]) })
        entries["CF_MIPlaceholderConstructorVersion"] = .string(constructorVersion)
        let folder = app + "/com.apple.WatchPlaceholder/" + (watch as NSString).lastPathComponent
        try FileSystem.createDirectory(folder)
        try FileSystem.write(try BinaryPropertyList.foundationData(.dictionary(entries)) { keys in
            guard let order = orders[Set(keys)] else { throw NomacError("a dictionary the watch app's Info.plist does not have", path: source) }
            return order
        }, to: folder + "/Info.plist")
    }
}
