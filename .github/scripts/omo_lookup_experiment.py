#!/usr/bin/env python3
"""Whether Core Data minds which byte position an .omo's lookup tables dispatch on (B-256).

momc's lookup tables (docs/formats/coredata.md "`.omo`", K) dispatch each group of keys on one
byte position, recorded in the node; nomac's rule picks momc's position for 152 of 159 observed
groups. This builds a generic app with xcodebuild for each model given (by default wikipedia's
WMFData and mastodon's models, whose tables nomac splits elsewhere, and coredata-experiments
`version-shared-names`), then installs it three ways:

- `X`: as built, with momc's .omo;
- `N`: with the .omo `nomac momc` writes for the same model;
- `K`: a control, momc's .omo with every dispatch node moved to another byte position;
- `NR`: a control, nomac's .omo with its first entity's name changed in its C strings, which
  shows Core Data loads nomac's file rather than falling back to the .mom (ADR 0230).

The app looks up every entity and property by name in `entitiesByName`, `propertiesByName`,
`attributesByName` and `relationshipsByName`, and names one character off; inserts an object of
each entity through key-value coding, saves it to a SQLite store, fetches every entity and counts
matches of a predicate on each string attribute. X and N must print the same, on their own stores
and on each other's; K and NR must not. Models are copied with their `codeGenerationType`s removed, so
the app needs no generated classes; nothing else changes. Outputs stay in <work>.

Usage: omo_lookup_experiment.py <work-dir> <simulator-udid> <nomac> [model.xcdatamodeld ...]
"""

import re
import shutil
import struct
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from coredata_experiments import VERSIONED, current_version  # noqa: E402
from pif_experiments import write_project  # noqa: E402

MODELS = ["/tmp/nomac-corpus/wikipedia/WMFData/Sources/WMFData/Resources/WMFData.xcdatamodeld",
          "/tmp/nomac-corpus/mastodon/MastodonSDK/Sources/CoreDataStack/CoreData.xcdatamodeld",
          "version-shared-names"]
MAIN = r'''import Foundation
import CoreData

let arguments = ProcessInfo.processInfo.arguments
let model = NSManagedObjectModel(contentsOf: Bundle.main.url(forResource: "Model", withExtension: "momd")!)!
var lines: [String] = []
func near(_ name: String) -> [String] {
    let scalars = Array(name.unicodeScalars)
    var names = [name + "x", String(name.dropLast())]
    for index in scalars.indices {
        for replacement in "aZ_0".unicodeScalars {
            var copy = scalars
            copy[index] = replacement
            names.append(String(String.UnicodeScalarView(copy)))
        }
    }
    return names
}
// Looked up as Core Data's own dictionaries (`objectForKey:`), not bridged to Swift dictionaries,
// which would copy them by enumeration and look keys up with Swift's hashing.
func table(_ object: NSObject, _ key: String) -> NSDictionary { object.value(forKey: key) as! NSDictionary }
func describe(_ property: Any?) -> String {
    guard let property = property as? NSPropertyDescription else { return "-" }
    return property.name + (property is NSAttributeDescription ? ":a" : property is NSRelationshipDescription ? ":r" : ":o")
}
func sample(_ attribute: NSAttributeDescription) -> Any? {
    switch attribute.attributeType {
    case .integer16AttributeType, .integer32AttributeType, .integer64AttributeType: return 7
    case .doubleAttributeType, .floatAttributeType: return 1.5
    case .decimalAttributeType: return NSDecimalNumber(string: "2.5")
    case .stringAttributeType: return "s-" + attribute.name
    case .booleanAttributeType: return true
    case .dateAttributeType: return Date(timeIntervalSince1970: 1_000_000)
    case .binaryDataAttributeType: return Data([1, 2, 3])
    case .UUIDAttributeType: return UUID(uuidString: "11111111-2222-3333-4444-555555555555")
    case .URIAttributeType: return URL(string: "https://example.org/" + attribute.name)
    default: return nil
    }
}
let entities = model.entities.sorted { $0.name! < $1.name! }
let entitiesByName = table(model, "entitiesByName")
for entity in entities {
    let name = entity.name!
    lines.append("E \(name) \(entitiesByName.object(forKey: name) as AnyObject === entity) "
        + near(name).map { (entitiesByName.object(forKey: $0) as? NSEntityDescription)?.name ?? "-" }.joined(separator: ","))
    let properties = table(entity, "propertiesByName"), attributes = table(entity, "attributesByName"), relationships = table(entity, "relationshipsByName")
    for property in entity.properties.sorted(by: { $0.name < $1.name }) {
        let key = property.name
        lines.append("P \(name).\(key) \(describe(properties.object(forKey: key))) \(describe(attributes.object(forKey: key))) "
            + "\(describe(relationships.object(forKey: key))) " + near(key).map { describe(properties.object(forKey: $0)) }.joined(separator: ","))
    }
}
let container = NSPersistentContainer(name: "Proof", managedObjectModel: model)
let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
container.persistentStoreDescriptions = [NSPersistentStoreDescription(url: directory.appendingPathComponent("Proof.sqlite"))]
var failure: Error?
container.loadPersistentStores { _, error in failure = error }
if let failure { lines.append("S error \((failure as NSError).code)") }
let context = container.viewContext
let concrete = entities.filter { !$0.isAbstract }
if failure == nil, arguments.contains("-write") {
    for entity in concrete {
        let object = NSManagedObject(entity: entity, insertInto: context)
        for (key, attribute) in entity.attributesByName.sorted(by: { $0.key < $1.key }) where !attribute.isTransient {
            if let value = sample(attribute) { object.setValue(value, forKey: key) }
        }
        do {
            try context.save()
            lines.append("W \(entity.name!) saved")
        } catch {
            context.rollback()
            lines.append("W \(entity.name!) error \((error as NSError).code)")
        }
    }
}
if failure == nil {
    for entity in concrete {
        let objects = (try? context.fetch(NSFetchRequest<NSManagedObject>(entityName: entity.name!))) ?? []
        let keys = entity.attributesByName.keys.sorted()
        let values = objects.map { object in keys.map { "\($0)=\(object.value(forKey: $0).map { "\($0)" } ?? "nil")" }.joined(separator: " ") }
        lines.append("R \(entity.name!) \(objects.count) " + values.sorted().joined(separator: " | "))
        for (key, attribute) in entity.attributesByName.sorted(by: { $0.key < $1.key }) where attribute.attributeType == .stringAttributeType && !attribute.isTransient {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity.name!)
            request.predicate = NSPredicate(format: "%K == %@", key, "s-" + key)
            lines.append("Q \(entity.name!).\(key) \((try? context.count(for: request)) ?? -1)")
        }
    }
}
try? (lines.joined(separator: "\n") + "\n").write(to: directory.appendingPathComponent("proof.txt"), atomically: true, encoding: .utf8)
print("PROOF done \(lines.count)")
fflush(stdout)
exit(0)
'''
BUNDLE = "org.nomac.omolookup"


def run(arguments, **options):
    return subprocess.run(arguments, capture_output=True, text=True, **options)


def copy_model(source, destination):
    """The model's versions and current version, without code generation."""
    if not Path(source).exists():
        for version, contents in VERSIONED[source].items():
            (destination / f"{version}.xcdatamodel").mkdir(parents=True)
            (destination / f"{version}.xcdatamodel" / "contents").write_text(re.sub(r' codeGenerationType="[^"]*"', "", contents))
        (destination / ".xccurrentversion").write_text(current_version(list(VERSIONED[source])[-1]))
        return
    shutil.copytree(source, destination)
    for contents in destination.glob("*.xcdatamodel/contents"):
        contents.write_text(re.sub(r' codeGenerationType="[^"]*"', "", contents.read_text()))


def build(work, label, source):
    directory = work / label
    shutil.rmtree(directory, ignore_errors=True)
    project = write_project(directory, "P", "C00000000000000000000001", "Proof", [("A00000000000000000000001", "Src")], {"Src/main.swift": MAIN})
    copy_model(source, directory / "Src/Model.xcdatamodeld")
    proc = run(["xcodebuild", "-project", str(project), "-target", "Proof", "-configuration", "Debug", "-sdk", "iphonesimulator",
                "CODE_SIGN_IDENTITY=-", "SWIFT_VERSION=5.0", "GENERATE_INFOPLIST_FILE=YES", f"PRODUCT_BUNDLE_IDENTIFIER={BUNDLE}",
                f"SYMROOT={directory}/build/products", f"OBJROOT={directory}/build/obj", "build"])
    if proc.returncode:
        sys.exit(f"{label} did not build:\n{proc.stdout[-2000:]}")
    return directory, directory / "build/products/Debug-iphonesimulator/Proof.app"


def dispatch_nodes(data):
    """The offsets of the kind words of every node that dispatches on a byte position."""
    def u32(offset):
        return struct.unpack(">I", data[offset:offset + 4])[0]
    offset = (u32(64 + 40) + 3) // 4 * 4
    tables = u32(offset)
    offset += 4
    found = []
    for _ in range(tables):
        offset = (offset + 7) // 8 * 8 + 40
        keys, nodes = u32(offset), u32(offset + 4)
        offset += 8 + 8 * nodes
        for _ in range(nodes - 1):
            if u32(offset) & 0x1FFF == 9:
                found.append(offset)
            low, high = struct.unpack(">HH", data[offset + 8:offset + 10] + data[offset + 12:offset + 14])
            size = max(high - low + 1, 0)
            offset += 16 + 2 * (size + (4 - size % 4) % 4)
        offset += 8 * keys
    return found


def renamed_entity(data):
    """The .omo with the first byte of its third C string (the first entity's name) changed."""
    data = bytearray(data)
    offset = (struct.unpack(">I", data[64 + 64:68 + 64])[0] + 3) // 4 * 4 + 4
    for _ in range(2):
        offset = (offset + 7) // 8 * 8
        offset += 24 + struct.unpack(">I", data[offset + 12:offset + 16])[0] + 1
    offset = (offset + 7) // 8 * 8 + 24
    data[offset] = ord("Q") if data[offset] != ord("Q") else ord("R")
    return bytes(data)


def moved(data):
    data = bytearray(data)
    for offset in dispatch_nodes(bytes(data)):
        kind = struct.unpack(">I", data[offset:offset + 4])[0]
        position = 0 if kind >> 13 else 1
        data[offset:offset + 4] = struct.pack(">I", position << 13 | 9)
    return bytes(data)


def variant(work, label, app, contents):
    copy = work / "variants" / f"{label}.app"
    shutil.rmtree(copy, ignore_errors=True)
    shutil.copytree(app, copy, symlinks=True)
    next((copy / "Model.momd").glob("*.omo")).write_bytes(contents)
    run(["codesign", "-f", "-s", "-", str(copy)])
    return copy


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    work, device, nomac = Path(sys.argv[1]).resolve(), sys.argv[2], str(Path(sys.argv[3]).resolve())
    (work / "variants").mkdir(parents=True, exist_ok=True)
    run(["xcrun", "simctl", "boot", device])
    run(["xcrun", "simctl", "bootstatus", device, "-b"])

    def fresh():
        run(["xcrun", "simctl", "uninstall", device, BUNDLE])

    def launch(app, *arguments):
        run(["xcrun", "simctl", "install", device, str(app)], check=True)
        proc = run(["xcrun", "simctl", "launch", "--console-pty", "--terminate-running-process", device, BUNDLE, *arguments])
        if "PROOF done" not in proc.stdout:
            return ["crashed"]
        container = run(["xcrun", "simctl", "get_app_container", device, BUNDLE, "data"]).stdout.strip()
        return (Path(container) / "Library/Application Support/proof.txt").read_text().splitlines()

    failed = False
    for index, source in enumerate(sys.argv[4:] or MODELS):
        label = f"model{index}"
        directory, app = build(work, label, source)
        momc = next((app / "Model.momd").glob("*.omo"))
        out = directory / "nomac"
        shutil.rmtree(out, ignore_errors=True)
        proc = run([nomac, "momc", "--sdkroot", "/SDK", "--iphoneos-deployment-target", "27.0", "--module", "Proof",
                    str(directory / "Src/Model.xcdatamodeld"), str(out)])
        if proc.returncode:
            sys.exit(f"{label}: nomac momc failed: {proc.stderr[-500:]}")
        ours = (out / "Model.momd" / momc.name).read_bytes()
        same_mom = all((out / "Model.momd" / mom.name).read_bytes() == mom.read_bytes() for mom in (app / "Model.momd").glob("*.mom"))
        nodes = dispatch_nodes(momc.read_bytes())
        apps = {"X": app, "N": variant(work, label + "N", app, ours), "K": variant(work, label + "K", app, moved(momc.read_bytes())),
                "NR": variant(work, label + "NR", app, renamed_entity(ours))}
        dumps = {}
        for name in apps:
            fresh()
            dumps[name] = launch(apps[name], "-write")
        fresh()
        launch(apps["X"], "-write")
        n_reads_x = launch(apps["N"])
        x_reads_x = launch(apps["X"])
        fresh()
        launch(apps["N"], "-write")
        x_reads_n = launch(apps["X"])
        n_reads_n = launch(apps["N"])
        fresh()
        lookups = sum(line[0] in "EP" for line in dumps["X"])
        writes = sum(line.startswith("W ") and line.endswith("saved") for line in dumps["X"])
        ok = dumps["X"] == dumps["N"] and n_reads_x == x_reads_x and x_reads_n == n_reads_n and dumps["X"] != ["crashed"]
        sensitive = dumps["K"] != dumps["X"] and dumps["NR"] != dumps["N"]
        failed = failed or not ok or not sensitive
        print(f"[{source}] .omo {'identical' if ours == momc.read_bytes() else 'different'}, .mom {'identical' if same_mom else 'DIFFERENT'}; "
              f"{len(nodes)} dispatch nodes, {lookups} entities and properties, {writes} entities saved; "
              f"X and N {'print the same' if ok else 'DIFFER'} (own stores and each other's); "
              f"controls {'differ' if sensitive else 'DO NOT DIFFER'} (K: {len(dumps['K'])} lines, NR: {len(dumps['NR'])} lines, "
              f"{sum(a != b for a, b in zip(dumps['NR'], dumps['N']))} of them changed)")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
