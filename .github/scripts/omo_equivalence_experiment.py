#!/usr/bin/env python3
"""Whether the order of an .omo's SQL column-name lists matters to Core Data (ADR 0230, B-256).

Runs on a Mac with Xcode 27.0 (DEVELOPER_DIR) and an iOS 27 Simulator. It builds a self-written
app twice with xcodebuild, with a Core Data model of one version (v1) and of two (v1, v2: an added
attribute and entity, a lightweight migration), then makes copies of the built apps whose
current version's .omo is changed:

- `N1`, `N2`: each entity's column-name list reversed (the only bytes that change);
- `S2`: the lists shuffled;
- controls: `C2` the .omo corrupted, `O2` no .omo, `R2` one attribute renamed in the .omo.

Each app opens a SQLite store in its data container, optionally inserts objects, and prints every
object it reads. Installing one app over another keeps the store, so the scenarios run one app
after another on one store: stores made by Xcode's apps opened by the reordered ones and the
reverse, lightweight migrations from v1 to v2 both ways, and the schema each app creates. The
self-written project and every output stay in <work>.

Usage: omo_equivalence_experiment.py <work-dir> <simulator-udid>
"""

import random
import shutil
import struct
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pif_experiments import write_project  # noqa: E402

HEAD = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<model type="com.apple.IDECoreDataModeler.DataModel" '
        'documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="1" minimumToolsVersion="Automatic" '
        'sourceLanguage="Swift" userDefinedModelVersionIdentifier="">\n')
ITEM = '''    <entity name="Item" representedClassName="NSManagedObject" syncable="YES">
        <attribute name="count" optional="YES" attributeType="Integer 64" defaultValueString="0" usesScalarValueType="YES"/>
{flag}        <attribute name="label" optional="YES" attributeType="String"/>
        <attribute name="when" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <relationship name="notes" optional="YES" toMany="YES" deletionRule="Cascade" destinationEntity="Note" inverseName="item" inverseEntity="Note"/>
    </entity>
    <entity name="Note" representedClassName="NSManagedObject" syncable="YES">
        <attribute name="text" optional="YES" attributeType="String"/>
        <relationship name="item" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Item" inverseName="notes" inverseEntity="Item"/>
    </entity>
'''
FLAG = '        <attribute name="flag" optional="YES" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>\n'
TAG = '''    <entity name="Tag" representedClassName="NSManagedObject" syncable="YES">
        <attribute name="name" optional="YES" attributeType="String"/>
    </entity>
'''
MODELS = {"v1": HEAD + ITEM.format(flag="") + "</model>\n", "v2": HEAD + ITEM.format(flag=FLAG) + TAG + "</model>\n"}
CURRENT = ('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
           '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n\t<key>_XCCurrentVersionName</key>\n'
           '\t<string>{}.xcdatamodel</string>\n</dict>\n</plist>\n')
MAIN = r'''import Foundation
import CoreData

let arguments = ProcessInfo.processInfo.arguments
let model = NSManagedObjectModel(contentsOf: Bundle.main.url(forResource: "Model", withExtension: "momd")!)!
let container = NSPersistentContainer(name: "Proof", managedObjectModel: model)
let description = NSPersistentStoreDescription(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Proof.sqlite"))
description.shouldMigrateStoreAutomatically = true
description.shouldInferMappingModelAutomatically = true
container.persistentStoreDescriptions = [description]
var failure: Error?
container.loadPersistentStores { _, error in failure = error }
if let failure { print("PROOF error", failure); exit(1) }
let context = container.viewContext
let entities = model.entities.map { $0.name! }.sorted()
if let index = arguments.firstIndex(of: "-write") {
    let label = arguments[index + 1]
    let item = NSEntityDescription.insertNewObject(forEntityName: "Item", into: context)
    item.setValue(label, forKey: "label")
    item.setValue(Int64(label.count), forKey: "count")
    item.setValue(Date(timeIntervalSince1970: 1_000_000), forKey: "when")
    if entities.contains("Tag") {
        item.setValue(true, forKey: "flag")
        NSEntityDescription.insertNewObject(forEntityName: "Tag", into: context).setValue("tag-" + label, forKey: "name")
    }
    let note = NSEntityDescription.insertNewObject(forEntityName: "Note", into: context)
    note.setValue("note of " + label, forKey: "text")
    note.setValue(item, forKey: "item")
    do { try context.save() } catch { print("PROOF error", error); exit(1) }
}
let request = NSFetchRequest<NSManagedObject>(entityName: "Item")
request.sortDescriptors = [NSSortDescriptor(key: "label", ascending: true)]
var lines = ["PROOF entities " + entities.joined(separator: ",")]
for item in (try? context.fetch(request)) ?? [] {
    let notes = ((item.value(forKey: "notes") as? Set<NSManagedObject>) ?? []).compactMap { $0.value(forKey: "text") as? String }.sorted()
    let flag = entities.contains("Tag") ? " flag=\(item.value(forKey: "flag") ?? "nil")" : ""
    lines.append("PROOF item \(item.value(forKey: "label")!) count=\(item.value(forKey: "count")!) when=\(item.value(forKey: "when")!)\(flag) notes=\(notes)")
}
if entities.contains("Tag") {
    let tags = ((try? context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Tag"))) ?? []).compactMap { $0.value(forKey: "name") as? String }.sorted()
    lines.append("PROOF tags \(tags)")
}
print(lines.joined(separator: "\n"))
fflush(stdout)
exit(0)
'''
BUNDLE = "org.nomac.omoproof"


def run(arguments, **options):
    return subprocess.run(arguments, capture_output=True, text=True, **options)


def build(work, name, versions):
    directory = work / name
    shutil.rmtree(directory, ignore_errors=True)
    files = {"Src/main.swift": MAIN, "Src/Model.xcdatamodeld/.xccurrentversion": CURRENT.format(versions[-1])}
    for version in versions:
        files[f"Src/Model.xcdatamodeld/{version}.xcdatamodel/contents"] = MODELS[version]
    project = write_project(directory, "P", "C00000000000000000000001", "Proof", [("A00000000000000000000001", "Src")], files)
    proc = run(["xcodebuild", "-project", str(project), "-target", "Proof", "-configuration", "Debug", "-sdk", "iphonesimulator",
                "CODE_SIGN_IDENTITY=-", "SWIFT_VERSION=5.0", "GENERATE_INFOPLIST_FILE=YES", f"PRODUCT_BUNDLE_IDENTIFIER={BUNDLE}",
                f"SYMROOT={directory}/build/products", f"OBJROOT={directory}/build/obj", "build"])
    if proc.returncode:
        sys.exit(f"{name} did not build:\n{proc.stdout[-2000:]}")
    return directory / "build/products/Debug-iphonesimulator/Proof.app"


def column_lists(data):
    """(offset, count) of each SQL entity's column-name list (docs/formats/coredata.md "`.omo`")."""
    def u32(offset):
        return struct.unpack(">I", data[offset:offset + 4])[0]
    offset = (u32(64) + 3) // 4 * 4
    entities = u32(offset + 40)
    offset = (offset + 44 + 7) // 8 * 8 + 8 * entities + 32
    offset = (offset + 7) // 8 * 8 + 8 * entities
    lists = []
    for _ in range(entities):
        offset += 20
        count = u32(offset)
        offset = (offset + 4 + 7) // 8 * 8
        lists.append((offset, count))
        offset += 8 * count
    return lists


def reorder(data, how):
    data = bytearray(data)
    shuffler = random.Random(11)
    for offset, count in column_lists(bytes(data)):
        words = [bytes(data[offset + 8 * i:offset + 8 * i + 8]) for i in range(count)]
        words = list(reversed(words)) if how == "reverse" else shuffler.sample(words, count)
        for index, word in enumerate(words):
            data[offset + 8 * index:offset + 8 * index + 8] = word
    return bytes(data)


def variant(work, name, app, change):
    copy = work / "variants" / f"{name}.app"
    shutil.rmtree(copy, ignore_errors=True)
    shutil.copytree(app, copy, symlinks=True)
    omo = next((copy / "Model.momd").glob("*.omo"))
    change(omo)
    run(["codesign", "-f", "-s", "-", str(copy)])
    return copy


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    work, device = Path(sys.argv[1]).resolve(), sys.argv[2]
    (work / "variants").mkdir(parents=True, exist_ok=True)
    one, two = build(work, "app1", ["v1"]), build(work, "app2", ["v1", "v2"])
    apps = {"X1": one, "X2": two}
    apps["N1"] = variant(work, "N1", one, lambda p: p.write_bytes(reorder(p.read_bytes(), "reverse")))
    apps["N2"] = variant(work, "N2", two, lambda p: p.write_bytes(reorder(p.read_bytes(), "reverse")))
    apps["S2"] = variant(work, "S2", two, lambda p: p.write_bytes(reorder(p.read_bytes(), "shuffle")))
    apps["C2"] = variant(work, "C2", two, lambda p: p.write_bytes(bytes(b ^ 0x5A if i >= 200 and i % 7 == 4 else b for i, b in enumerate(p.read_bytes()))))
    apps["O2"] = variant(work, "O2", two, lambda p: p.unlink())
    apps["R2"] = variant(work, "R2", two, lambda p: p.write_bytes(p.read_bytes().replace(b"label", b"lxbel")))
    run(["xcrun", "simctl", "boot", device])
    run(["xcrun", "simctl", "bootstatus", device, "-b"])

    def launch(name, *arguments):
        run(["xcrun", "simctl", "install", device, str(apps[name])], check=True)
        proc = run(["xcrun", "simctl", "launch", "--console-pty", "--terminate-running-process", device, BUNDLE, *arguments])
        return [line for line in proc.stdout.splitlines() if line.startswith("PROOF")]

    def fresh():
        run(["xcrun", "simctl", "uninstall", device, BUNDLE])

    scenarios = {
        "xcode-store-reordered-app": [("X2", "A"), ("N2", "B"), ("X2", None)],
        "reordered-store-xcode-app": [("N2", "A"), ("X2", "B"), ("N2", None)],
        "migration-xcode-v1-reordered-v2": [("X1", "A"), ("N2", "B"), ("X2", None)],
        "migration-reordered-v1-xcode-v2": [("N1", "A"), ("X2", "B"), ("N2", None)],
        "shuffled": [("X2", "A"), ("S2", "B"), ("X2", None)],
    }
    failed = False
    for name, steps in scenarios.items():
        fresh()
        outputs = [launch(app, *(["-write", label] if label else [])) for app, label in steps]
        # The last app reads back every object the others wrote, with their values.
        expected = sorted({label for _, label in steps if label})
        read = [line.split()[2] for line in outputs[-1] if line.startswith("PROOF item")]
        ok = read == expected and all(lines and not lines[0].startswith("PROOF error") for lines in outputs)
        failed = failed or not ok
        print(f"[{name}] {'ok' if ok else 'FAILED'}: " + " | ".join("; ".join(lines) for lines in outputs))
    schemas = {}
    for name in ["X2", "N2", "S2"]:
        fresh()
        launch(name, "-write", "A")
        container = run(["xcrun", "simctl", "get_app_container", device, BUNDLE, "data"]).stdout.strip()
        schemas[name] = run(["sqlite3", f"{container}/Library/Application Support/Proof.sqlite", ".schema"]).stdout
    print(f"[schemas] {'identical' if len(set(schemas.values())) == 1 else 'DIFFERENT'} for {', '.join(schemas)}")
    for name in ["C2", "O2", "R2"]:
        fresh()
        lines = launch(name, "-write", "A")
        print(f"[control {name}] {'reads and writes' if lines else 'fails'}")
    fresh()
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
