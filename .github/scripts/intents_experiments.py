#!/usr/bin/env python3
"""Observe what Xcode's intentbuilderc makes of intent definitions (.intentdefinition).

Runs on a Mac with Xcode 27.0 (DEVELOPER_DIR). Every definition below is written here from
scratch; the corpus's and the holdout's own definitions are read where they are checked out
(/tmp/nomac-corpus, /tmp/nomac-holdout). For each definition and each option variant the
build passes (`-classPrefix`, `-language`, `-swiftVersion`, `-visibility`, `-moduleName`), it
records `intentbuilderc generate -dryRun` (the paths Swift Build plans with), `intentbuilderc
generate` (the classes it writes) and, once per definition, `intentbuilderc compile`.

Outputs go to <output-dir>/intents/observations.json (base64 file contents). Nothing here is
Xcode's own content: only its outputs for these inputs.

Usage: intents_experiments.py <output-dir>
"""

import base64
import json
import plistlib
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

WORK = Path("/tmp/nomac-intents-experiments")
CHECKOUTS = [Path("/tmp/nomac-corpus"), Path("/tmp/nomac-holdout")]


def intent_response(codes=None, parameters=None, last_tag=None):
    result = {"INIntentResponseCodes": codes or [{"INIntentResponseCodeName": "success", "INIntentResponseCodeSuccess": True},
                                                 {"INIntentResponseCodeName": "failure"}]}
    if parameters is not None:
        result["INIntentResponseParameters"] = parameters
        result["INIntentResponseLastParameterTag"] = last_tag if last_tag is not None else len(parameters)
    return result


def intent(name, parameters=(), response=None, **fields):
    entry = {"INIntentCategory": "information", "INIntentDescription": f"{name} description", "INIntentDescriptionID": "dEsC01",
             "INIntentName": name, "INIntentTitle": name, "INIntentTitleID": "tItL01", "INIntentType": "Custom",
             "INIntentVerb": "View", "INIntentLastParameterTag": len(parameters), "INIntentParameters": list(parameters),
             "INIntentResponse": response or intent_response()}
    entry.update(fields)
    return entry


def parameter(name, kind, tag=1, **fields):
    entry = {"INIntentParameterName": name, "INIntentParameterType": kind, "INIntentParameterTag": tag,
             "INIntentParameterDisplayPriority": tag, "INIntentParameterDisplayName": name.capitalize(),
             "INIntentParameterDisplayNameID": f"pRm{tag:03}"}
    entry.update(fields)
    return entry


def response_parameter(name, kind, tag=1, **fields):
    entry = {"INIntentResponseParameterName": name, "INIntentResponseParameterType": kind, "INIntentResponseParameterTag": tag,
             "INIntentResponseParameterDisplayPriority": tag}
    entry.update(fields)
    return entry


def enum(name, values, **fields):
    entry = {"INEnumName": name, "INEnumDisplayName": name, "INEnumDisplayNameID": "eNuM01", "INEnumGeneratesHeader": True,
             "INEnumType": "Regular",
             "INEnumValues": [{"INEnumValueName": value, "INEnumValueDisplayName": value, "INEnumValueDisplayNameID": f"vAl{index:03}",
                               **({"INEnumValueIndex": index} if index else {})} for index, value in enumerate(values)]}
    entry.update(fields)
    return entry


def custom_type(name, properties=(), **fields):
    defaults = [("identifier", "String"), ("displayString", "String"), ("pronunciationHint", "String"),
                ("alternativeSpeakableMatches", "SpeakableString")]
    entries = [{"INTypePropertyDefault": True, "INTypePropertyDisplayPriority": index + 1, "INTypePropertyName": prop,
                "INTypePropertyTag": index + 1, "INTypePropertyType": kind,
                **({"INTypePropertySupportsMultipleValues": True} if prop == "alternativeSpeakableMatches" else {})}
               for index, (prop, kind) in enumerate(defaults)]
    for index, (prop, kind, extra) in enumerate(properties):
        entries.append({"INTypePropertyDisplayPriority": 5 + index, "INTypePropertyName": prop, "INTypePropertyTag": 100 + index,
                        "INTypePropertyType": kind, "INTypePropertyDisplayName": prop.capitalize(),
                        "INTypePropertyDisplayNameID": f"tPr{index:03}", **extra})
    entry = {"INTypeName": name, "INTypeDisplayName": name, "INTypeDisplayNameID": "tYpE01",
             "INTypeLastPropertyTag": 100 + len(properties), "INTypeProperties": entries}
    entry.update(fields)
    return entry


def definition(intents=(), enums=(), types=()):
    return {"INEnums": list(enums), "INIntentDefinitionModelVersion": "1.2", "INIntentDefinitionNamespace": "nAmEsP",
            "INIntentDefinitionSystemVersion": "22A380", "INIntentDefinitionToolsBuildVersion": "14A309",
            "INIntentDefinitionToolsVersion": "14.0", "INIntents": list(intents), "INTypes": list(types)}


TYPES = ["String", "Integer", "Decimal", "Boolean", "Duration", "DateComponents", "Date", "CurrencyAmount", "Placemark", "Location",
         "Person", "PaymentMethod", "URL", "File", "Distance", "Mass", "Volume", "Temperature", "Speed", "Energy", "Object",
         "Double", "Data", "Image", "SpeakableString", "Unknown"]
FLAGS = {"multiple": {"INIntentParameterSupportsMultipleValues": True},
         "configurable": {"INIntentParameterConfigurable": True},
         "dynamic": {"INIntentParameterConfigurable": True, "INIntentParameterSupportsDynamicEnumeration": True},
         "resolution": {"INIntentParameterSupportsResolution": True},
         "search": {"INIntentParameterConfigurable": True, "INIntentParameterSupportsDynamicEnumeration": True,
                    "INIntentParameterSupportsSearch": True},
         "multiple-dynamic": {"INIntentParameterSupportsMultipleValues": True, "INIntentParameterConfigurable": True,
                              "INIntentParameterSupportsDynamicEnumeration": True},
         "multiple-resolution": {"INIntentParameterSupportsMultipleValues": True, "INIntentParameterSupportsResolution": True},
         "disambiguation": {"INIntentParameterSupportsResolution": True, "INIntentParameterCustomDisambiguation": True}}
OBJECT = {"INIntentParameterObjectType": "Thing", "INIntentParameterObjectTypeNamespace": "nAmEsP"}
ENUM_PARAMETER = {"INIntentParameterEnumType": "Color", "INIntentParameterEnumTypeNamespace": "nAmEsP"}
THING = custom_type("Thing")
COLOR = enum("Color", ["unknown", "red", "green"])

DEFINITIONS = {}
for kind in TYPES:
    extra = OBJECT if kind == "Object" else {}
    DEFINITIONS[f"type-{kind}"] = definition([intent("Probe", [parameter("value", kind, **extra)])], types=[THING])
    for flag, fields in FLAGS.items():
        DEFINITIONS[f"type-{kind}-{flag}"] = definition([intent("Probe", [parameter("value", kind, **extra, **fields)])],
                                                        types=[THING])
    DEFINITIONS[f"response-{kind}"] = definition([intent("Probe", response=intent_response(parameters=[
        response_parameter("result", kind, **({"INIntentResponseParameterObjectType": "Thing",
                                               "INIntentResponseParameterObjectTypeNamespace": "nAmEsP"} if kind == "Object" else {}))]))],
        types=[THING])
    DEFINITIONS[f"response-{kind}-multiple"] = definition([intent("Probe", response=intent_response(parameters=[
        response_parameter("result", kind, INIntentResponseParameterSupportsMultipleValues=True,
                           **({"INIntentResponseParameterObjectType": "Thing",
                               "INIntentResponseParameterObjectTypeNamespace": "nAmEsP"} if kind == "Object" else {}))]))],
        types=[THING])
    DEFINITIONS[f"property-{kind}"] = definition([intent("Probe", [parameter("thing", "Object", **OBJECT)])],
                                                 types=[custom_type("Thing", [("extra", kind, {})])])
    DEFINITIONS[f"property-{kind}-multiple"] = definition([intent("Probe", [parameter("thing", "Object", **OBJECT)])],
                                                          types=[custom_type("Thing", [("extra", kind, {"INTypePropertySupportsMultipleValues": True})])])

DEFINITIONS.update({
    "empty": definition(),
    "no-parameters": definition([intent("Plain")]),
    "two-intents": definition([intent("Zeta", [parameter("b", "String")]), intent("Alpha", [parameter("a", "Integer")])]),
    "parameter-order": definition([intent("Probe", [parameter("zulu", "String", 1), parameter("alpha", "Integer", 2),
                                                    parameter("mike", "Boolean", 3, INIntentParameterDisplayPriority=0)])]),
    "enum-parameter": definition([intent("Probe", [parameter("color", "Integer", **ENUM_PARAMETER)])], enums=[COLOR]),
    "enum-parameter-flags": definition([intent("Probe", [parameter("color", "Integer", **ENUM_PARAMETER, **FLAGS["resolution"]),
                                                         parameter("colors", "Integer", 2, **ENUM_PARAMETER, **FLAGS["multiple"]),
                                                         parameter("pick", "Integer", 3, **ENUM_PARAMETER, **FLAGS["dynamic"])])],
                                       enums=[COLOR]),
    "enum-no-header": definition([intent("Probe", [parameter("color", "Integer", **ENUM_PARAMETER)])],
                                 enums=[enum("Color", ["unknown", "red"], INEnumGeneratesHeader=False)]),
    "enum-indices": definition(enums=[enum("Shade", ["unknown", "dark", "light"], INEnumValues=[
        {"INEnumValueName": "unknown", "INEnumValueDisplayName": "unknown", "INEnumValueDisplayNameID": "a"},
        {"INEnumValueName": "dark", "INEnumValueDisplayName": "dark", "INEnumValueDisplayNameID": "b", "INEnumValueIndex": 5},
        {"INEnumValueName": "light", "INEnumValueDisplayName": "light", "INEnumValueDisplayNameID": "c", "INEnumValueIndex": 2}])]),
    "enum-class-name": definition(enums=[enum("Shade", ["unknown", "dark"], INEnumClassName="XYShade")]),
    "enum-only": definition(enums=[COLOR, enum("Alpha", ["unknown", "one"])]),
    "type-only": definition(types=[THING, custom_type("Gadget", [("size", "Integer", {}), ("tags", "String", {"INTypePropertySupportsMultipleValues": True}),
                                                               ("shade", "Integer", {"INTypePropertyEnumType": "Color",
                                                                                     "INTypePropertyEnumTypeNamespace": "nAmEsP"})])],
                            enums=[COLOR]),
    "type-class-name": definition(types=[custom_type("Thing", INTypeClassName="XYThing", INTypeClassPrefix="XY")]),
    "type-referencing-type": definition([intent("Probe", [parameter("box", "Object", INIntentParameterObjectType="Box",
                                                                    INIntentParameterObjectTypeNamespace="nAmEsP")])],
                                        types=[THING, custom_type("Box", [("content", "Object", {"INTypePropertyObjectType": "Thing",
                                                                                                "INTypePropertyObjectTypeNamespace": "nAmEsP"})])]),
    "system-object": definition([intent("Probe", [parameter("item", "Object", INIntentParameterObjectType="MediaItem",
                                                            INIntentParameterObjectTypeNamespace="System", **FLAGS["multiple-resolution"])])]),
    "system-intent": definition([intent("PlayMedia", INIntentType="System", INIntentCategory="media", INIntentVerb="Play")]),
    "response-codes": definition([intent("Probe", [parameter("name", "String")], response=intent_response(codes=[
        {"INIntentResponseCodeName": "success", "INIntentResponseCodeSuccess": True, "INIntentResponseCodeFormatString": "Done ${result}",
         "INIntentResponseCodeFormatStringID": "f1"},
        {"INIntentResponseCodeName": "failure", "INIntentResponseCodeFormatString": "Failed", "INIntentResponseCodeFormatStringID": "f2"},
        {"INIntentResponseCodeName": "notFound", "INIntentResponseCodeFormatString": "No ${result} for ${count}",
         "INIntentResponseCodeFormatStringID": "f3"},
        {"INIntentResponseCodeName": "partly", "INIntentResponseCodeSuccess": True,
         "INIntentResponseCodeConciseFormatString": "Partly ${count}", "INIntentResponseCodeConciseFormatStringID": "f4"}],
        parameters=[response_parameter("result", "String"), response_parameter("count", "Integer", 2)]))]),
    "intent-options": definition([intent("Probe", [parameter("name", "String", INIntentParameterConfigurable=True)],
                                         INIntentConfigurable=True, INIntentEligibleForWidgets=True, INIntentIneligibleForSuggestions=True,
                                         INIntentUserConfirmationRequired=True, INIntentKeyParameter="name",
                                         INIntentInput="name", INIntentRestrictions=0)]),
    "intent-class-name": definition([intent("Probe", INIntentClassName="XYProbeIntent", INIntentClassPrefix="XY")]),
    "names": definition([intent("lowerCase", [parameter("URL", "String"), parameter("x2", "Integer", 2), parameter("self", "String", 3)]),
                         intent("Has Space"), intent("ünïcode")]),
})

VARIANTS = {
    "swift": ["-classPrefix", "", "-language", "Swift", "-swiftVersion", "5.0", "-visibility", "public"],
    "swift6": ["-classPrefix", "", "-language", "Swift", "-swiftVersion", "6.0", "-visibility", "public"],
    "swift-private": ["-classPrefix", "", "-language", "Swift", "-swiftVersion", "5.0", "-visibility", "private"],
    "swift-project": ["-classPrefix", "", "-language", "Swift", "-swiftVersion", "5.0", "-visibility", "project"],
    "swift-prefix": ["-classPrefix", "XY", "-language", "Swift", "-swiftVersion", "5.0", "-visibility", "public"],
    "swift-module": ["-classPrefix", "", "-language", "Swift", "-swiftVersion", "5.0", "-visibility", "public", "-moduleName", "Mod"],
    "objc": ["-classPrefix", "", "-language", "Objective-C", "-visibility", "public"],
}


def b64(data):
    return base64.b64encode(data).decode()


def files_under(directory):
    return {str(p.relative_to(directory)): b64(p.read_bytes()) for p in sorted(directory.rglob("*")) if p.is_file()}


def run(arguments):
    return subprocess.run(["xcrun", "intentbuilderc"] + arguments, capture_output=True, text=True)


def observe(name, path):
    record = {"compile": {}, "generate": {}}
    out = WORK / "out" / name.replace("/", "_")
    compiled = out / "compile"
    compiled.mkdir(parents=True)
    proc = run(["compile", "-input", str(path), "-output", str(compiled) + "/", "-classPrefix", ""])
    record["compile"] = {"status": proc.returncode, "output": (proc.stdout + proc.stderr).replace(str(path), "<INPUT>"),
                         "files": files_under(compiled)}
    for variant, options in VARIANTS.items():
        generated = out / variant / path.stem
        dry = run(["generate", "-dryRun", "-input", str(path), "-output", str(generated)] + options)
        real = run(["generate", "-input", str(path), "-output", str(generated)] + options)
        record["generate"][variant] = {
            "dryRunStatus": dry.returncode, "dryRun": dry.stdout.replace(str(generated), "<OUT>"),
            "status": real.returncode, "output": (real.stdout + real.stderr).replace(str(path), "<INPUT>"),
            "files": files_under(generated) if generated.exists() else {}}
    return record


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    out = Path(sys.argv[1]).resolve() / "intents"
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    shutil.rmtree(WORK, ignore_errors=True)
    inputs = {}
    for name, contents in DEFINITIONS.items():
        path = WORK / "in" / name / "Probe.intentdefinition"
        path.parent.mkdir(parents=True)
        path.write_bytes(plistlib.dumps(contents))
        inputs[name] = path
    for root in CHECKOUTS:
        if root.exists():
            for path in sorted(root.glob("*/**/*.intentdefinition")):
                if "DerivedData" not in str(path) and "/Pods/" not in str(path):
                    inputs[f"corpus:{path}"] = path
    observations = {}
    with ThreadPoolExecutor(6) as pool:
        for name, record in zip(inputs, pool.map(lambda item: observe(*item), inputs.items())):
            observations[name] = record
            print(f"[intents {name}] {len(record['generate']['swift']['files'])} Swift files", flush=True)
    (out / "observations.json").write_text(json.dumps(observations, indent=1, ensure_ascii=False) + "\n")
    shutil.rmtree(WORK, ignore_errors=True)


if __name__ == "__main__":
    main()
