#!/usr/bin/env python3
"""Observe what momc (Xcode 27.0) makes of Core Data models.

Runs on a Mac with Xcode 27.0 (DEVELOPER_DIR). Each experiment model is written here from
scratch as an .xcdatamodel (or an .xcdatamodeld with versions), then compiled with the command
lines an iOS build runs (docs/formats/coredata.md):

    momc --sdkroot <iPhoneOS SDK> --iphoneos-deployment-target 27.0 --module T <model> <output dir>
    momc --action generate --swift-version 5.0 --sdkroot ... --module T <model> <output dir>

Every corpus model found under /tmp/nomac-corpus is compiled too (`corpus:<path>`), and every corpus
mapping model with mapc as a build runs it (`mapping-corpus`: `mapping:<path>`). Outputs go
to <output-dir>/observations.json (base64 file contents, momc's status and messages).

Two more experiments: `version-hashes` builds entities and attributes through Core Data's
public API (a Swift program this script writes and runs) and records their `versionHash`, with
the SHA-256 preimages docs/formats/coredata.md states for entities checked against them; `build`
builds an app with a versioned model to record the build's momc command lines.

Usage: coredata_experiments.py <output-dir> [experiment ...]
"""

import base64
import json
import random
import shutil
import subprocess
import sys
from pathlib import Path

HEADER = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
          '<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" '
          'systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="">\n')


def model(*entities, extra=""):
    return HEADER + "".join(entities) + extra + "</model>\n"


def entity(name, *members, attributes='syncable="YES"', codegen="class"):
    gen = f' codeGenerationType="{codegen}"' if codegen else ""
    return (f'    <entity name="{name}" representedClassName="{name}" {attributes}{gen}>\n'
            + "".join(f"        {member}\n" for member in members) + "    </entity>\n")


def attribute(name, kind, extra='optional="YES"'):
    return f'<attribute name="{name}" {extra} attributeType="{kind}"/>'


TYPES = ["Integer 16", "Integer 32", "Integer 64", "Decimal", "Double", "Float", "String", "Boolean", "Date", "Binary",
         "UUID", "URI", "Transformable", "Object ID"]
SCALAR = {"Integer 16", "Integer 32", "Integer 64", "Double", "Float", "Boolean"}


def typed(kind, name="value", optional=True, scalar=None):
    extra = 'optional="YES"' if optional else ""
    if kind in SCALAR or kind in {"Date", "Decimal"}:
        extra += f' usesScalarValueType="{"YES" if (scalar if scalar is not None else kind in SCALAR) else "NO"}"'
    return attribute(name, kind, extra.strip())


EXPERIMENTS = {
    "empty": model(),
    "one-entity": model(entity("Item")),
    "one-date": model(entity("Item", typed("Date", "timestamp"))),
    "entity-name": model(entity("Thing", typed("Date", "timestamp"))),
    "attribute-name": model(entity("Item", typed("Date", "when"))),
    "two-attributes": model(entity("Item", typed("Date", "timestamp"), typed("String", "title"))),
    "three-attributes": model(entity("Item", typed("Date", "a"), typed("String", "b"), typed("Integer 64", "c"))),
    "two-entities": model(entity("A", typed("String", "a")), entity("B", typed("String", "b"))),
    "no-codegen": model(entity("Item", typed("Date", "timestamp"), codegen=None)),
    "required": model(entity("Item", typed("String", "title", optional=False))),
    **{f"type-{kind.replace(' ', '-').lower()}": model(entity("Item", typed(kind))) for kind in TYPES},
    **{f"type-{kind.replace(' ', '-').lower()}-object": model(entity("Item", typed(kind, scalar=False)))
       for kind in sorted(SCALAR)},
    "defaults": model(entity("Item",
                             attribute("i16", "Integer 16", 'optional="YES" defaultValueString="7" usesScalarValueType="YES"'),
                             attribute("s", "String", 'optional="YES" defaultValueString="hello"'),
                             attribute("b", "Boolean", 'optional="YES" defaultValueString="YES" usesScalarValueType="YES"'),
                             attribute("d", "Double", 'optional="YES" defaultValueString="1.5" usesScalarValueType="YES"'),
                             attribute("t", "Date", 'optional="YES" defaultDateTimeInterval="0" usesScalarValueType="NO"'))),
    "min-max": model(entity("Item",
                            attribute("n", "Integer 32", 'optional="YES" minValueString="1" maxValueString="9" usesScalarValueType="YES"'),
                            attribute("s", "String", 'optional="YES" minValueString="2" maxValueString="5"'))),
    "transient": model(entity("Item", attribute("t", "String", 'optional="YES" transient="YES"'))),
    "indexed": model(entity("Item", attribute("t", "String", 'optional="YES" indexed="YES"'))),
    "external-storage": model(entity("Item", attribute("b", "Binary", 'optional="YES" allowsExternalBinaryDataStorage="YES"'))),
    "transformable-named": model(entity("Item", attribute("t", "Transformable", 'optional="YES" valueTransformerName="NSSecureUnarchiveFromData" customClassName="NSArray"'))),
    "renaming": model(entity("Item", attribute("t", "String", 'optional="YES" elementID="old"'))),
    "to-one": model(entity("A", '<relationship name="b" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="B" inverseName="a" inverseEntity="B"/>'),
                    entity("B", '<relationship name="a" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="A" inverseName="b" inverseEntity="A"/>')),
    "to-many": model(entity("A", '<relationship name="bs" optional="YES" toMany="YES" deletionRule="Cascade" destinationEntity="B" inverseName="a" inverseEntity="B"/>'),
                     entity("B", '<relationship name="a" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="A" inverseName="bs" inverseEntity="A"/>')),
    "ordered": model(entity("A", '<relationship name="bs" optional="YES" toMany="YES" ordered="YES" deletionRule="Deny" destinationEntity="B"/>'),
                     entity("B")),
    "no-inverse": model(entity("A", '<relationship name="b" optional="YES" maxCount="1" deletionRule="No Action" destinationEntity="B"/>'),
                        entity("B")),
    "inheritance": model(entity("Base", typed("String", "name")), entity("Sub", typed("Integer 64", "n"), attributes='parentEntity="Base" syncable="YES"')),
    "abstract": model(entity("Base", typed("String", "name"), attributes='isAbstract="YES" syncable="YES"')),
    "user-info": model(entity("Item", '<attribute name="t" optional="YES" attributeType="String"><userInfo><entry key="k" value="v"/></userInfo></attribute>',
                              '<userInfo><entry key="ek" value="ev"/></userInfo>')),
    "fetch-index": model(entity("Item", typed("String", "t"),
                                '<fetchIndex name="byT"><fetchIndexElement property="t" type="Binary" order="ascending"/></fetchIndex>')),
    "uniqueness": model(entity("Item", typed("String", "t"),
                               '<uniquenessConstraints><uniquenessConstraint><constraint value="t"/></uniquenessConstraint></uniquenessConstraints>')),
    "fetch-request": model(entity("Item", typed("String", "t")),
                           extra='    <fetchRequest name="All" entity="Item"/>\n'),
    "configuration": model(entity("Item", typed("String", "t")),
                           extra='    <configuration name="Cloud"><memberEntity name="Item"/></configuration>\n'),
    "version-hash-modifier": model(entity("Item", typed("String", "t"), attributes='versionHashModifier="v2" syncable="YES"')),
    **{f"attributes-{n}": model(entity("Item", *[typed("String", f"a{i:02}") for i in range(n)])) for n in [4, 5, 6, 7, 8, 12, 13, 16, 19, 20, 21, 22, 23, 24, 30, 40]},
    **{f"entities-{n}": model(*[entity(f"E{i:02}", typed("String", "a")) for i in range(n)]) for n in [3, 4, 6, 8, 12]},
    # Names whose order in the properties dictionary differs for each capacity the 7- and
    # 23-bucket tables might have (docs/formats/foundation-collections.md "Growth").
    "hash-7": model(entity("Item", *[typed("String", n) for n in ['bde', 'hbdxbq', 'ntxcvpdj', 'synocxuv', 'uwxbz', 'vsqrxuwf', 'wutwy']])),
    "hash-23": model(entity("Item", *[typed("String", n) for n in ['dxv', 'eajngwra', 'ernzs', 'ev', 'evnwwb', 'fdadz', 'gbfavmzs', 'gpx', 'gqjexqn', 'ie', 'jmomy', 'jnzml', 'kqykgqpr', 'lhl', 'nb', 'qmmtlfvs', 'qqe', 'tah', 'tzfu', 'ufc', 'vd', 'vipcucnf', 'wahwnv']])),
}


# Indexed attributes under each minimumToolsVersion of the corpus and a few around them.
EXPERIMENTS.update({f"indexed-tools-{v.replace(' ', '-').replace('.', '-').lower()}": EXPERIMENTS["indexed"].replace('minimumToolsVersion="Automatic"', f'minimumToolsVersion="{v}"')
                    for v in ["Xcode 4.1", "Xcode 4.3", "Xcode 7.0", "Xcode 7.3", "Xcode 8.0", "Xcode 9.0", "Xcode 14.0"]})


# Generated files: entities out of name order, class names with and without a module, a category.
EXPERIMENTS["codegen-order"] = model(
    '    <entity name="Zeta" representedClassName="Zeta" syncable="YES" codeGenerationType="class"/>\n',
    '    <entity name="Alpha" representedClassName="MyAlpha" syncable="YES" codeGenerationType="class"/>\n',
    '    <entity name="Mid" representedClassName=".Mid" syncable="YES" codeGenerationType="category"/>\n',
    '    <entity name="Beta" representedClassName="Other.Beta" syncable="YES" codeGenerationType="class"/>\n')
EXPERIMENTS["relationships-several"] = model(
    entity("A", typed("String", "name"),
           '<relationship name="b" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="B"/>',
           '<relationship name="cs" optional="YES" toMany="YES" deletionRule="Nullify" destinationEntity="C"/>',
           '<relationship name="parent" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="A"/>'),
    entity("B"), entity("C"),
    entity("Sub", '<relationship name="items" optional="YES" toMany="YES" ordered="YES" deletionRule="Nullify" destinationEntity="B"/>',
           attributes='parentEntity="A" syncable="YES"'))
# Attributes between relationships, two to-many relationships, and class names that sort differently by case.
EXPERIMENTS["relationships-order"] = model(
    entity("Hub", '<relationship name="z" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Zed"/>',
           attribute("t", "Transformable", 'optional="YES" customClassName="NSValue"'),
           '<relationship name="b" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Yon"/>',
           '<relationship name="c" optional="YES" toMany="YES" deletionRule="Nullify" destinationEntity="Zed"/>',
           typed("String", "m"),
           '<relationship name="d" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Plain"/>',
           '<relationship name="e" optional="YES" toMany="YES" ordered="YES" deletionRule="Nullify" destinationEntity="Low"/>',
           '<relationship name="f" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Mod"/>'),
    entity("Zed"), entity("Yon"), entity("Plain", codegen=None),
    '    <entity name="Low" representedClassName="low" syncable="YES" codeGenerationType="class"/>\n',
    '    <entity name="Mod" representedClassName="Other.Mod" syncable="YES" codeGenerationType="class"/>\n')
# Names whose order differs between case foldings: the warnings print the relationships in momc's order.
EXPERIMENTS["sort-order"] = model(*[
    entity(name, *[f'<relationship name="{r}" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="{name}"/>'
                   for r in ["Ab", "aB", "ab", "aZ", "a_x", "a1", "A2", "a10", "a9"]], codegen=None)
    for name in ["Ez", "E_a", "EZz", "E1", "E10", "E9", "Eb", "EB"]])

# The same models generating Objective-C (moonlight's sourceLanguage).
EXPERIMENTS.update({f"objc-{name}": EXPERIMENTS[name].replace('sourceLanguage="Swift"', 'sourceLanguage="Objective-C"')
                    for name in ["one-entity", "two-entities", "required", "no-codegen", "defaults", "transient", "transformable-named",
                                 "to-one", "to-many", "ordered", "no-inverse", "inheritance", "abstract", "codegen-order",
                                 "relationships-several", "relationships-order", *[n for n in EXPERIMENTS if n.startswith("type-")]]})


# Features the coverage survey's models use (coredata_survey.py, BACKLOG B-257), one at a time.
_ONE = '<relationship name="{0}" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="{1}"{2}/>'


def _to_one(name, destination, extra=""):
    return _ONE.format(name, destination, f" {extra}" if extra else "")


def _tools(text, last=None, minimum=None):
    if last:
        text = text.replace('lastSavedToolsVersion="1"', f'lastSavedToolsVersion="{last}"')
    if minimum:
        text = text.replace('minimumToolsVersion="Automatic"', f'minimumToolsVersion="{minimum}"')
    return text


def _sub(name, parent, *members):
    return entity(name, *members, attributes=f'parentEntity="{parent}" syncable="YES"', codegen=None)


_DECIMALS = ["0", "0.0", "0.00", "00", "1", "1.5", "1.50", "10", "100", "1000", "-1", "-1.5", "1e3", "1E-2", ".5", "5.", "abc", "", " 1", "1 ", "+1",
             "65535", "65536", "4294967296", "123456789012345678901234567890", "0.1", "0.001", "-0", "-0.0", "NaN", "1,5", "12abc", "1.2.3", "0.000001"]
_LEGACY = model(entity("Item", attribute("a", "String", 'optional="YES" indexed="YES"'), _to_one("o", "Other"), codegen=None, attributes=""),
                entity("Other", codegen=None, attributes=""))
_RECIPROCAL_B = entity("B", _to_one("a", "A"), codegen=None)
EXPERIMENTS.update({
    "no-class": model('    <entity name="Item" syncable="YES">\n        <attribute name="a" optional="YES" attributeType="String"/>\n    </entity>\n',
                      '    <entity name="Sub" parentEntity="Item" syncable="YES"/>\n'),
    "no-language": EXPERIMENTS["one-date"].replace(' sourceLanguage="Swift"', ""),
    "version-identifier": EXPERIMENTS["one-date"].replace('userDefinedModelVersionIdentifier=""', 'userDefinedModelVersionIdentifier="2.9"'),
    "model-attributes": EXPERIMENTS["one-date"].replace('<model ', '<model name="Test1.xcdatamodel" usedWithSwiftData="YES" '),
    "decimal-defaults": model(entity("Item", *[attribute(f"a{i:02}", "Decimal", f'optional="YES" defaultValueString="{value}" usesScalarValueType="NO"')
                                               for i, value in enumerate(_DECIMALS)], codegen=None)),
    "decimal-several": model(entity("A", typed("Decimal", "a"), typed("Decimal", "b"), codegen=None), entity("B", typed("Decimal", "a"), codegen=None)),
    "default-ignored": model(entity("Item", attribute("u", "URI", 'optional="YES" defaultValueString="https://x.y"'),
                                    attribute("i", "UUID", 'optional="YES" defaultValueString="F6CDB0E3-3A6B-4B5C-9D4E-1F2A3B4C5D6E"'),
                                    attribute("b", "Binary", 'optional="YES" defaultValueString="abc"'),
                                    attribute("t", "Transformable", 'optional="YES" valueTransformerName="V" defaultValueString="0"'), codegen=None)),
    "tools-automatic-11116": _tools(_LEGACY, last="11116"),
    "tools-automatic-11117": _tools(_LEGACY, last="11117"),
    "tools-automatic-2": _tools(_LEGACY, last="2"),
    "tools-automatic-fraction": _tools(_LEGACY, last="9525.2"),
    "syncable-xcode-10": _tools(_LEGACY, minimum="Xcode 10.0"),
    "syncable-xcode-11": _tools(_LEGACY, minimum="Xcode 11.0"),
    "syncable-no": _tools(_LEGACY, last="5064").replace('indexed="YES"', 'indexed="YES" syncable="NO"').replace('destinationEntity="Other"', 'destinationEntity="Other" syncable="NO"'),
    "syncable-user-info": _tools(model(entity("Item", '<attribute name="a" optional="YES" attributeType="String"><userInfo><entry key="k" value="v"/></userInfo></attribute>',
                                              '<userInfo><entry key="e" value="f"/></userInfo>', codegen=None, attributes="")), last="5064"),
    "property-flags-attribute": model(entity("Item", attribute("a", "String", 'optional="YES" spotlightIndexingEnabled="YES"'),
                                             attribute("b", "String", 'optional="YES" storedInTruthFile="YES"'),
                                             attribute("c", "String", 'optional="YES" allowsCloudEncryption="YES"'),
                                             attribute("d", "String", 'optional="YES" spotlightIndexingEnabled="YES" storedInTruthFile="YES" allowsCloudEncryption="YES"'), codegen=None)),
    "property-flags-relationship": model(entity("Item", _to_one("a", "Other", 'spotlightIndexingEnabled="YES"'), _to_one("b", "Other", 'storedInTruthFile="YES"'),
                                                '<relationship name="c" optional="YES" toMany="YES" ordered="YES" deletionRule="Nullify" destinationEntity="Other" spotlightIndexingEnabled="YES"/>', codegen=None),
                                         entity("Other", codegen=None)),
    "property-flags-transient": model(entity("Item", attribute("a", "String", 'optional="YES" transient="YES" spotlightIndexingEnabled="YES" storedInTruthFile="YES" allowsCloudEncryption="YES"'), codegen=None)),
    "regular-expression": model(entity("Item", attribute("a", "String", 'optional="YES" regularExpressionString="x+"'),
                                       attribute("b", "String", 'optional="YES" regularExpressionString="y+"'),
                                       attribute("c", "String", 'optional="YES" regularExpressionString="z+" minValueString="1"'),
                                       attribute("d", "String", 'optional="YES" regularExpressionString="x+" elementID="old"'),
                                       '<attribute name="e" optional="YES" attributeType="String" regularExpressionString="q+" elementID="old2" minValueString="3"><userInfo><entry key="k" value="v"/></userInfo></attribute>',
                                       attribute("f", "String"), codegen=None)),
    "user-info-validation": model(entity("Item", '<attribute name="a" optional="YES" attributeType="String" minValueString="1" maxValueString="2"><userInfo><entry key="k" value="v"/></userInfo></attribute>', codegen=None)),
    "modifier-attribute": model(entity("Item", attribute("a", "String", 'optional="YES" versionHashModifier="3"'), codegen=None)),
    "modifier-relationship": model(entity("Item", _to_one("o", "Other", 'versionHashModifier="3"'), codegen=None), entity("Other", codegen=None)),
    "modifier-strings": model(entity("Item", attribute("a", "String", 'optional="YES" versionHashModifier="vhm" elementID="old" defaultValueString="def" valueTransformerName="tr"'), codegen=None)),
    "relationship-user-info": model(entity("Item", '<relationship name="o" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Other"><userInfo><entry key="k" value="v"/></userInfo></relationship>', codegen=None), entity("Other", codegen=None)),
    "relationship-indexed": model(entity("Item", _to_one("o", "Other", 'indexed="YES"'), codegen=None), entity("Other", codegen=None)),
    "own-inverse": model(entity("Item", _to_one("s", "Item", 'inverseName="s" inverseEntity="Item"'), codegen=None)),
    "same-name-inverse": model(entity("A", _to_one("x", "B", 'inverseName="x" inverseEntity="B"'), codegen=None), entity("B", _to_one("x", "A", 'inverseName="x" inverseEntity="A"'), codegen=None)),
    "inverse-without": model(entity("A", _to_one("b", "B", 'inverseName="a" inverseEntity="B"'), codegen=None), _RECIPROCAL_B),
    "inverse-missing": model(entity("A", _to_one("b", "B", 'inverseName="zzz" inverseEntity="B"'), codegen=None), entity("B", codegen=None)),
    "inverse-attribute": model(entity("A", _to_one("b", "B", 'inverseName="n" inverseEntity="B"'), codegen=None), entity("B", typed("String", "n"), codegen=None)),
    "inverse-inherited": model(entity("A", _to_one("s", "Sub", 'inverseName="a" inverseEntity="Base"'), codegen=None),
                               entity("Base", _to_one("a", "A", 'inverseName="s" inverseEntity="A"'), codegen=None), _sub("Sub", "Base")),
    # Three subentities whose names collide in small tables: the larger model orders them by another table.
    "subentities-8": model(entity("Item", codegen=None), _sub("BuyableItem", "Item"), _sub("Egg", "BuyableItem"), _sub("Food", "BuyableItem"), _sub("Quest", "BuyableItem"),
                           entity("MetaReward", codegen=None), _sub("InAppReward", "MetaReward"), _sub("Reward", "MetaReward")),
    "subentities-9": model(entity("Item", codegen=None), _sub("BuyableItem", "Item"), _sub("Egg", "BuyableItem"), _sub("Food", "BuyableItem"), _sub("Quest", "BuyableItem"),
                           _sub("HatchingPotion", "Item"), entity("MetaReward", codegen=None), _sub("InAppReward", "MetaReward"), _sub("Reward", "MetaReward")),
    "sibling-keys-two": model(entity("Base", codegen=None), _sub("A", "Base", _to_one("user", "U")), _sub("B", "Base", _to_one("user", "U")), entity("U", codegen=None)),
    "sibling-keys-three": model(entity("Base", codegen=None), _sub("A", "Base"), _sub("A1", "A", _to_one("user", "U")), _sub("B", "Base", _to_one("user", "U")),
                                _sub("C", "Base"), _sub("C1", "C", _to_one("user", "U")), entity("U", codegen=None)),
    "sibling-keys-case": model(entity("Base", codegen=None), _sub("A", "Base", _to_one("user", "U")), _sub("B", "Base", _to_one("USER", "U")), entity("U", codegen=None)),
    "sibling-keys-destination": model(entity("Base", codegen=None), _sub("A", "Base", _to_one("user", "U")), _sub("B", "Base", _to_one("user", "U")), entity("U", codegen=None), _sub("U2", "U")),
    "sibling-keys-ordered": model(entity("Base", codegen=None), _sub("A", "Base", _to_one("user", "U", 'inverseName="as" inverseEntity="U"')), _sub("B", "Base", _to_one("user", "U", 'inverseName="bs" inverseEntity="U"')),
                                  entity("U", '<relationship name="as" optional="YES" toMany="YES" ordered="YES" deletionRule="Nullify" destinationEntity="A" inverseName="user" inverseEntity="A"/>',
                                         '<relationship name="bs" optional="YES" toMany="YES" ordered="YES" deletionRule="Nullify" destinationEntity="B" inverseName="user" inverseEntity="B"/>', codegen=None)),
    "class-in-module": model('    <entity name="Item" representedClassName=".Item" syncable="YES" codeGenerationType="class">\n        <attribute name="a" optional="YES" attributeType="String"/>\n    </entity>\n'),
    "transformable-module": model(entity("Item", attribute("c", "Transformable", 'optional="YES" valueTransformerName="V" customClassName="UIKit.UIColor"'))),
    "two-classes-in-module": model('    <entity name="A" representedClassName=".Same" syncable="YES"/>\n', '    <entity name="B" representedClassName=".Same" syncable="YES"/>\n'),
})
_TWO = (typed("String", "a"), typed("String", "b"))


def _compound(*groups):
    return "<compoundIndexes>" + "".join("<compoundIndex>" + "".join(f'<index value="{v}"/>' for v in group) + "</compoundIndex>" for group in groups) + "</compoundIndexes>"


_A_INDEXED = attribute("a", "String", 'optional="YES" indexed="YES"')
_OLD = "5064"
_CONFIGURED = "".join(entity(f"E{i}", codegen=None) for i in range(9))
_PREDICATE_ENTITIES = (entity("Item", typed("Integer 64", "a"), typed("String", "s"), _to_one("o", "Other"), codegen=None) + entity("Other", typed("String", "name"), codegen=None))


def _predicate(text):
    return model(_PREDICATE_ENTITIES, extra=f'    <fetchRequest name="R" entity="Item" predicateString="{text}"/>\n')


EXPERIMENTS.update({
    "compound-two": model(entity("Item", *_TWO, typed("String", "c"), _compound(["a", "b"], ["b", "c"]), codegen=None)),
    "compound-indexed": model(entity("Item", _A_INDEXED, typed("String", "b"), _compound(["a", "b"]), codegen=None)),
    "compound-single": model(entity("Item", _A_INDEXED, typed("String", "b"), _compound(["a"]), codegen=None)),
    "compound-fetch-index": model(entity("Item", _A_INDEXED, typed("String", "b"), '<fetchIndex name="f"><fetchIndexElement property="b" type="Binary" order="ascending"/></fetchIndex>', _compound(["a", "b"]), codegen=None)),
    "compound-legacy-pair": _tools(model(entity("Item", *_TWO, _compound(["a", "b"]), codegen=None)), last=_OLD),
    "compound-legacy-indexed": _tools(model(entity("Item", _A_INDEXED, typed("String", "b"), _compound(["a", "b"]), codegen=None)), last=_OLD),
    "compound-legacy-single": _tools(model(entity("Item", _A_INDEXED, typed("String", "b"), _compound(["a"]), codegen=None)), last=_OLD),
    "compound-legacy-single-other": _tools(model(entity("Item", _A_INDEXED, typed("String", "b"), _compound(["b"]), codegen=None)), last=_OLD),
    "compound-legacy-mixed": _tools(model(entity("Item", _A_INDEXED, typed("String", "b"), _compound(["a"], ["a", "b"]), codegen=None)), last=_OLD),
    "configuration-all": model(_CONFIGURED, extra='    <configuration name="Cloud">' + "".join(f'<memberEntity name="E{i}"/>' for i in range(9)) + "</configuration>\n"),
    "configuration-order": model(_CONFIGURED, extra='    <configuration name="B"><memberEntity name="E8"/><memberEntity name="E1"/></configuration>\n    <configuration name="A"><memberEntity name="E3"/></configuration>\n'),
    "configuration-four": model(_CONFIGURED, extra="".join(f'    <configuration name="{n}"{" usedWithCloudKit=" + chr(34) + "YES" + chr(34) if n == "Cloud" else ""}><memberEntity name="E{i}"/></configuration>\n' for i, n in enumerate(["Local", "Cloud", "Other", "Zed"]))),
    "predicate-integer": _predicate("a == 0"),
    "predicate-comparisons": _predicate("a &gt;= 1 AND a &lt;= 2 AND a &gt; 3 AND a &lt; 4 AND a != 5"),
    "predicate-string": _predicate("s == &quot;x_y&quot;"),
    "predicate-maximum": _predicate("a == max:(a)"),
    "predicate-variable": _predicate("o.name == $LANGUAGE AND s == &quot;Hi&quot;"),
    "predicate-limit": model(_PREDICATE_ENTITIES, extra='    <fetchRequest name="R" entity="Item" predicateString="a == 0" fetchLimit="5"/>\n    <fetchRequest name="S" entity="Item" fetchLimit="7"/>\n'),
    "fetched-optional": model(entity("Item", typed("String", "a"), '<fetchedProperty name="fp" optional="YES"><fetchRequest name="fpFetchRequest" entity="Other"/></fetchedProperty>', _to_one("o", "Other"), codegen=None), entity("Other", codegen=None)),
    "fetched-required": model(entity("Item", '<fetchedProperty name="fp"><fetchRequest name="fpFetchRequest" entity="Other"/></fetchedProperty>', codegen=None), entity("Other", codegen=None)),
    "fetched-predicate": model(entity("Item", '<fetchedProperty name="fp" optional="YES" elementID="old" versionHashModifier="3"><fetchRequest name="fpFetchRequest" entity="Other" predicateString="name == $FETCH_SOURCE"/></fetchedProperty>', codegen=None), entity("Other", typed("String", "name"), codegen=None)),
    "boolean-defaults": model(entity("Item", *[attribute(f"a{i:02}", "Boolean", f'optional="YES" defaultValueString="{value}" usesScalarValueType="YES"')
                                               for i, value in enumerate(["0.0", "0", "1", "YES", "NO", "true", "false", "T", "y", "n", "2", "abc", "01", "", " 1", "-1", "0.5", "00.1"])], codegen=None)),
    "undefined-transient": model(entity("Item", '<attribute name="u" optional="YES" transient="YES"/>', codegen=None)),
    "swiftdata-warnings": model('    <entity name="A" representedClassName="A" syncable="YES"><attribute name="t" optional="YES" attributeType="Transformable"/><relationship name="bs" optional="YES" toMany="YES" ordered="YES" deletionRule="No Action" destinationEntity="B"/></entity>\n    <entity name="B" representedClassName="B" syncable="YES" isAbstract="YES"/>\n').replace("<model ", '<model usedWithSwiftData="YES" '),
})
SURVEY_MODELS = ["compound-two", "compound-indexed", "compound-single", "compound-fetch-index", "compound-legacy-pair", "compound-legacy-indexed", "compound-legacy-single",
                 "compound-legacy-single-other", "compound-legacy-mixed", "configuration-all", "configuration-order", "configuration-four", "predicate-integer",
                 "predicate-comparisons", "predicate-string", "predicate-maximum", "predicate-variable", "predicate-limit", "fetched-optional", "fetched-required",
                 "fetched-predicate", "boolean-defaults", "undefined-transient", "swiftdata-warnings",
                 "no-class", "version-identifier", "model-attributes", "decimal-defaults", "decimal-several", "default-ignored", "tools-automatic-11116",
                 "tools-automatic-11117", "tools-automatic-2", "tools-automatic-fraction", "syncable-xcode-10", "syncable-xcode-11", "syncable-no", "syncable-user-info",
                 "property-flags-attribute", "property-flags-relationship", "property-flags-transient", "regular-expression", "user-info-validation", "modifier-attribute",
                 "modifier-relationship", "modifier-strings", "relationship-user-info", "relationship-indexed", "own-inverse", "same-name-inverse", "inverse-without",
                 "inverse-missing", "inverse-attribute", "inverse-inherited", "subentities-8", "subentities-9", "sibling-keys-two", "sibling-keys-three", "sibling-keys-case",
                 "sibling-keys-destination", "sibling-keys-ordered"]


def threshold_names(n, seed):
    """n distinct lowercase names, the same on every run for (n, seed)."""
    rng = random.Random(f"{n}-{seed}")
    names = set()
    while len(names) < n:
        names.add("".join(rng.choice("abcdefghijklmnopqrstuvwxyz") for _ in range(rng.randint(3, 9))))
    return sorted(names)


# Whether the 41-bucket (71-bucket) table holds n properties: the seed picks names whose dictionary order
# differs between holding them and growing (docs/formats/foundation-collections.md "Growth").
THRESHOLD_SEEDS_41 = {30: 1, 31: 1, 32: 1, 33: 2, 34: 2, 35: 1, 36: 1, 37: 1, 38: 1, 39: 1, 40: 2, 41: 2}
THRESHOLD_SEEDS_71 = {52: 1, 53: 10, 54: 3, 55: 2}
EXPERIMENTS.update({f"threshold-41-{n}": model(entity("Item", *[typed("String", name) for name in threshold_names(n, seed)]))
                    for n, seed in THRESHOLD_SEEDS_41.items()})
EXPERIMENTS.update({f"threshold-71-{n}": model(entity("Item", *[typed("String", name) for name in threshold_names(n, seed)]))
                    for n, seed in THRESHOLD_SEEDS_71.items()})

# Versioned models: a .xcdatamodeld with these versions; the current one is the last.
VERSIONED = {
    "versioned-one": {"Model": EXPERIMENTS["one-date"]},
    "versioned-two": {"Model": EXPERIMENTS["one-date"], "Model 2": EXPERIMENTS["two-attributes"]},
}
# Versioned models without a current version: no .xccurrentversion, or one with an empty dictionary
# (as cwa's and wikipedia's ArticleData have).
VERSIONED["versioned-no-current"] = {"Model": EXPERIMENTS["one-date"], "Model 2": EXPERIMENTS["two-attributes"], "Other": EXPERIMENTS["inheritance"]}
VERSIONED["versioned-empty-current"] = {"Model": EXPERIMENTS["to-many"], "Model 2": EXPERIMENTS["uniqueness"]}
_UNNAMED = entity("Item", attribute("v", "Transformable"))
VERSIONED.update({
    "warn-transformer-old-version": {"Model": model(_UNNAMED), "Model 2": EXPERIMENTS["one-date"]},
    "warn-transformer-current": {"Model": EXPERIMENTS["one-date"], "Model 2": model(_UNNAMED)},
    "warn-transformer-no-current": {"Model": model(_UNNAMED), "Model 2": EXPERIMENTS["one-date"]},
})
_SHARED_NAMES = ["Application", "Attachment", "Annotation", "Bookmarks", "CacheGroup", "Collection", "Conversation", "Description",
                 "Dictionary", "Attributes", "Components", "Credential", "Configuration", "Environment", "Expression", "Information",
                 "Repository", "Transaction", "Preference", "Permission", "Participant", "DomainBlock", "PollOption", "Notification"]
VERSIONED["version-shared-names"] = {"Model": model(*[entity(n, attribute("t", "String")) for n in _SHARED_NAMES]),
                                     "Model 2": model(*[entity(n, attribute("t", "String")) for n in _SHARED_NAMES])}
NO_CURRENT_VERSION = {"versioned-no-current": None, "warn-transformer-no-current": None,
                      "versioned-empty-current": '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
                                                 '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict/>\n</plist>\n'}

# The survey's features in an .omo, the only version of an .xcdatamodeld that names it current;
# the versions' compile order at the sizes where a copy of its table moves; a warning in two versions.
VERSIONED.update({f"omo-{name}": {"Model": EXPERIMENTS[name]} for name in SURVEY_MODELS})
VERSIONED.update({f"versions-{n}": {f"V{i}": EXPERIMENTS["one-date"] for i in range(n)} for n in [6, 7, 8, 12, 13, 20, 21]})
VERSIONED["warn-repeated"] = {"Model": EXPERIMENTS["no-inverse"], "Model 2": EXPERIMENTS["no-inverse"]}
VERSIONED["versioned-one-no-current"] = {"Model": EXPERIMENTS["one-date"]}
NO_CURRENT_VERSION["versioned-one-no-current"] = None
# Which version momc treats as current without a declared one: no .xccurrentversion, or an empty one.
_CLASS = '<entity name="C{0}" representedClassName="C{0}" syncable="YES" codeGenerationType="class"><attribute name="t" optional="YES" attributeType="Transformable"/></entity>\n'
for _names in (["Item", "Model"], ["Main", "Data"], ["Alpha", "Alpha 2"], ["Zeta", "Zeta 2"], ["Store 2", "Store"], ["V 3", "V 2", "V"]):
    _key = _names[0].replace(" ", "")
    VERSIONED[f"no-current-{_key}"] = {n: model(_CLASS.format(n.replace(" ", ""))) for n in _names}
    NO_CURRENT_VERSION[f"no-current-{_key}"] = None
    VERSIONED[f"no-current-empty-{_key}"] = VERSIONED[f"no-current-{_key}"]
    NO_CURRENT_VERSION[f"no-current-empty-{_key}"] = NO_CURRENT_VERSION["versioned-empty-current"]

# The .omo of a current version, one input varied at a time: each experiment model as the only
# version of an .xcdatamodeld that names it current.
OMO_MODELS = ["empty", "one-entity", "one-date", "entity-name", "attribute-name", "two-attributes", "three-attributes",
              "two-entities", "required", *[f"type-{kind.replace(' ', '-').lower()}" for kind in TYPES if kind != "Object ID"],
              "defaults", "min-max", "transient", "indexed", "external-storage", "transformable-named", "renaming", "to-one",
              "to-many", "ordered", "no-inverse", "inheritance", "abstract", "user-info", "fetch-index", "uniqueness",
              "fetch-request", "version-hash-modifier", "attributes-8", "entities-4", "hash-7"]
VERSIONED.update({f"omo-{name}": {"Model": EXPERIMENTS[name]} for name in OMO_MODELS})

# The order of an .omo's SQL column names (B-256): one attribute of each of many names, the same
# name in other entities, types and models, and orders, subsets and types of 26 one-letter names.
_LETTERS = [chr(c) for c in range(ord("a"), ord("z") + 1)]
OMO_NAME_MODELS = {f"omo-n1-{n}": model(entity("Item", typed("String", n))) for n in _LETTERS + [
    "aa", "ab", "ba", "zz", "name", "title", "timestamp", "value", "date", "id", "uuid", "count", "x1", "x2", "x3",
    "longername", "averyveryverylongattributename"]}
for _entity in ["A", "Thing", "Zebra", "VeryLongEntityName"]:
    OMO_NAME_MODELS.update({f"omo-n1e-{_entity}-{n}": model(entity(_entity, typed("String", n))) for n in ["a", "b"]})
OMO_NAME_MODELS.update({
    "omo-n1t-a-int": model(entity("Item", typed("Integer 64", "a"))),
    "omo-n1t-b-int": model(entity("Item", typed("Integer 64", "b"))),
    "omo-n1x-ab-two-entities": model(entity("A", typed("String", "b")), entity("B", typed("String", "a"))),
    "omo-ord-26": model(entity("Item", *[typed("String", n) for n in _LETTERS])),
    "omo-ord-a-m": model(entity("Item", *[typed("String", n) for n in _LETTERS[:13]])),
    "omo-ord-n-z": model(entity("Item", *[typed("String", n) for n in _LETTERS[13:]])),
    "omo-ord-even": model(entity("Item", *[typed("String", n) for n in _LETTERS[::2]])),
    "omo-ord-odd": model(entity("Item", *[typed("String", n) for n in _LETTERS[1::2]])),
    "omo-ord-abc-rev": model(entity("Item", *[typed("String", n) for n in ["c", "b", "a"]])),
    **{f"omo-ord-{k}": model(entity("Item", *[typed("String", n) for n in _LETTERS[:k]])) for k in (4, 5, 6)},
    "omo-ord-26-int": model(entity("Item", *[typed("Integer 64", n) for n in _LETTERS])),
    "omo-ord-26-rev": model(entity("Item", *[typed("String", n) for n in reversed(_LETTERS)])),
    "omo-ord-26-ent": model(entity("Zzz", *[typed("String", n) for n in _LETTERS])),
    "omo-ord-26-mixed": model(entity("Item", *[typed(["String", "Date", "Integer 16", "Double", "Binary"][i % 5], n)
                                               for i, n in enumerate(_LETTERS)])),
    "omo-ord-26-longent": model(entity("E" + "e" * 52, *[typed("String", n) for n in _LETTERS])),
    "omo-ord-26-other": model(entity("Aaa", typed("String", "z" * 43), typed("Date", "qqq")),
                              entity("Item", *[typed("String", n) for n in _LETTERS])),
})
VERSIONED.update({name: {"Model": contents} for name, contents in OMO_NAME_MODELS.items()})

# Records of the .omo nomac writes (ADR 0230): Date defaults (floored to whole minutes), the
# NSManagedObject class (interned, recorded as none), and every default-value type, transient and
# external attributes, a transformer and both kinds of relationship together.
_DATE_DEFAULTS = ["1000", "1030", "59", "61", "-1000", "1000.7", "3599", "0", "60", "120.9", "-59", "7200", "86399"]
_COVERAGE = """    <entity name="CampSite" representedClassName="CampSite" syncable="YES" codeGenerationType="class">
        <attribute name="number" optional="YES" attributeType="Integer 16" defaultValueString="3" usesScalarValueType="YES"/>
        <relationship name="camper" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Camper" inverseName="site" inverseEntity="Camper"/>
    </entity>
    <entity name="Camper" representedClassName=".Camper" syncable="YES" codeGenerationType="class">
        <attribute name="big" optional="YES" attributeType="Integer 64" defaultValueString="-7" usesScalarValueType="YES"/>
        <attribute name="cached" optional="YES" transient="YES" attributeType="String"/>
        <attribute name="flag" optional="YES" attributeType="Boolean" defaultValueString="YES" usesScalarValueType="YES"/>
        <attribute name="name" attributeType="String" defaultValueString="hello"/>
        <attribute name="photo" optional="YES" attributeType="Binary" allowsExternalBinaryDataStorage="YES"/>
        <attribute name="ratio" optional="YES" attributeType="Double" defaultValueString="0.5" usesScalarValueType="YES"/>
        <attribute name="since" optional="YES" attributeType="Date" defaultDateTimeInterval="1000" usesScalarValueType="NO"/>
        <attribute name="tags" optional="YES" attributeType="Transformable" valueTransformerName="NSSecureUnarchiveFromData" customClassName="[String]"/>
        <attribute name="weight" optional="YES" attributeType="Float" defaultValueString="1.5" usesScalarValueType="YES"/>
        <relationship name="notes" optional="YES" toMany="YES" deletionRule="Cascade" destinationEntity="Note" inverseName="camper" inverseEntity="Note"/>
        <relationship name="site" optional="YES" maxCount="1" deletionRule="No Action" destinationEntity="CampSite" inverseName="camper" inverseEntity="CampSite"/>
    </entity>
    <entity name="Note" representedClassName="NSManagedObject" versionHashModifier="v2" syncable="YES">
        <attribute name="id" optional="YES" attributeType="UUID" usesScalarValueType="NO"/>
        <attribute name="link" optional="YES" attributeType="URI"/>
        <attribute name="text" optional="YES" attributeType="String"/>
        <attribute name="when" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <relationship name="camper" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Camper" inverseName="notes" inverseEntity="Camper"/>
    </entity>
"""
_REL = '<relationship name="{n}" optional="YES" {kind}deletionRule="Nullify" destinationEntity="{d}" inverseName="{i}" inverseEntity="{d}"{extra}/>'
_RENAMING = (entity("Item", attribute("t", "String", 'optional="YES" elementID="oldT"'), attribute("u", "String"),
                    _REL.format(n="tags", kind='toMany="YES" ', d="Tag", i="item", extra=' elementID="oldTags"'),
                    attributes='elementID="OldItem" syncable="YES"')
             + entity("Tag", _REL.format(n="item", kind='maxCount="1" ', d="Item", i="tags", extra=""),
                      attributes='elementID="Tag" versionHashModifier="v2" syncable="YES"'))
EXPERIMENTS.update({
    "renaming-entity": model(entity("Item", attribute("t", "String"), attributes='elementID="OldItem" syncable="YES"')),
    "renaming-relationship": model(entity("A", _REL.format(n="b", kind='maxCount="1" ', d="B", i="a", extra=' elementID="oldB"')),
                                   entity("B", _REL.format(n="a", kind='maxCount="1" ', d="A", i="b", extra=""))),
    "renaming-empty": model(entity("Item", attribute("t", "String", 'optional="YES" elementID=""'), attributes='elementID="" syncable="YES"')),
    "renaming-all": model(_RENAMING),
})
VERSIONED.update({
    "omo-date-defaults": {"Model": model(entity("E", *[attribute(f"d{i:02}", "Date", f'optional="YES" defaultDateTimeInterval="{v}" usesScalarValueType="NO"')
                                                       for i, v in enumerate(_DATE_DEFAULTS)]))},
    "omo-default-class": {"Model": model('    <entity name="Item" representedClassName="NSManagedObject" syncable="YES">\n'
                                         '        <attribute name="a" optional="YES" attributeType="String"/>\n    </entity>\n')},
    "omo-coverage": {"Model": model(_COVERAGE)},
    "omo-renaming": {"Model": model(_RENAMING)},
    "omo-inh-two": {"Model": model(entity("Base", attribute("name", "String")),
                                   entity("SubA", attribute("a", "String"), attributes='parentEntity="Base" syncable="YES"'),
                                   entity("SubB", attribute("b", "String"), attributes='parentEntity="Base" syncable="YES"'))},
    "omo-inh-chain": {"Model": model(entity("Base", attribute("name", "String")),
                                     entity("Mid", attribute("m", "String"), attributes='parentEntity="Base" syncable="YES"'),
                                     entity("Leaf", attribute("l", "String"), attributes='parentEntity="Mid" syncable="YES"'))},
    "omo-inh-members": {"Model": model(entity("Base", attribute("name", "String"), attribute("size", "Integer 32", 'optional="YES" usesScalarValueType="YES"'),
                                              _REL.format(n="tag", kind='maxCount="1" ', d="Tag", i="items", extra="")),
                                       entity("Sub", attribute("extra", "String"), attribute("count", "Integer 64", 'optional="YES" usesScalarValueType="YES"'),
                                              attributes='parentEntity="Base" syncable="YES"'),
                                       entity("Tag", attribute("label", "String"), _REL.format(n="items", kind='toMany="YES" ', d="Base", i="tag", extra="")))},
    "omo-inh-abstract": {"Model": model(entity("Base", attribute("name", "String"), attributes='isAbstract="YES" syncable="YES"'),
                                        entity("Sub", attribute("n", "String"), attributes='parentEntity="Base" syncable="YES"'))},
    "omo-inh-0-1": {"Model": model(entity("Base"), entity("Sub", attribute("c0", "String"), attributes='parentEntity="Base" syncable="YES"'))},
    "omo-inh-1-0": {"Model": model(entity("Base", attribute("p0", "String")), entity("Sub", attributes='parentEntity="Base" syncable="YES"'))},
    "omo-inh-2-0": {"Model": model(entity("Base", attribute("p0", "String"), attribute("p1", "String")), entity("Sub", attributes='parentEntity="Base" syncable="YES"'))},
    "omo-inh-0-2": {"Model": model(entity("Base"), entity("Sub", attribute("c0", "String"), attribute("c1", "String"), attributes='parentEntity="Base" syncable="YES"'))},
    "omo-inh-2-1": {"Model": model(entity("Base", attribute("p0", "String"), attribute("p1", "String")), entity("Sub", attribute("c0", "String"), attributes='parentEntity="Base" syncable="YES"'))},
    "omo-inh-1-2": {"Model": model(entity("Base", attribute("p0", "String")), entity("Sub", attribute("c0", "String"), attribute("c1", "String"), attributes='parentEntity="Base" syncable="YES"'))},
    "omo-inh-rel": {"Model": model(entity("Base", _REL.format(n="tag", kind='maxCount="1" ', d="Tag", i="items", extra="")),
                                   entity("Sub", attributes='parentEntity="Base" syncable="YES"'), entity("Tag", attribute("label", "String"), _REL.format(n="items", kind='toMany="YES" ', d="Base", i="tag", extra="")))},
    "omo-inh-tomany": {"Model": model(entity("Base", _REL.format(n="tags", kind='toMany="YES" ', d="Tag", i="item", extra="")),
                                      entity("Sub", attributes='parentEntity="Base" syncable="YES"'), entity("Tag", attribute("label", "String"), _REL.format(n="item", kind='maxCount="1" ', d="Base", i="tags", extra="")))},
    "omo-inh-rel-attr": {"Model": model(entity("Base", attribute("a", "String"), _REL.format(n="tag", kind='maxCount="1" ', d="Tag", i="items", extra="")),
                                        entity("Sub", attribute("c", "String"), attributes='parentEntity="Base" syncable="YES"'), entity("Tag", attribute("label", "String"), _REL.format(n="items", kind='toMany="YES" ', d="Base", i="tag", extra="")))},
    "omo-inh-transient": {"Model": model(entity("Base", attribute("a", "String"), attribute("t", "String", 'optional="YES" transient="YES"')),
                                         entity("Sub", attributes='parentEntity="Base" syncable="YES"'))},
    "omo-inh-own-rel": {"Model": model(entity("Base", attribute("a", "String")),
                                       entity("Sub", _REL.format(n="tag", kind='maxCount="1" ', d="Tag", i="subs", extra=""), attributes='parentEntity="Base" syncable="YES"'),
                                       entity("Tag", attribute("label", "String"), _REL.format(n="subs", kind='toMany="YES" ', d="Sub", i="tag", extra="")))},
    "omo-inh-rel-own1": {"Model": model(entity("Base", _REL.format(n="tag", kind='maxCount="1" ', d="Tag", i="items", extra="")), entity("Sub", attribute("c", "String"), attributes='parentEntity="Base" syncable="YES"'), entity("Tag", attribute("label", "String"), _REL.format(n="items", kind='toMany="YES" ', d="Base", i="tag", extra="")))},
    "omo-inh-rel-own2": {"Model": model(entity("Base", _REL.format(n="tag", kind='maxCount="1" ', d="Tag", i="items", extra="")), entity("Sub", attribute("c", "String"), attribute("d", "String"), attributes='parentEntity="Base" syncable="YES"'), entity("Tag", attribute("label", "String"), _REL.format(n="items", kind='toMany="YES" ', d="Base", i="tag", extra="")))},
    "omo-inh-attr-rel-own0": {"Model": model(entity("Base", attribute("a", "String"), _REL.format(n="tag", kind='maxCount="1" ', d="Tag", i="items", extra="")), entity("Sub", attributes='parentEntity="Base" syncable="YES"'), entity("Tag", attribute("label", "String"), _REL.format(n="items", kind='toMany="YES" ', d="Base", i="tag", extra="")))},
    "omo-inh-2attr-rel-own0": {"Model": model(entity("Base", attribute("a", "String"), attribute("b", "String"), _REL.format(n="tag", kind='maxCount="1" ', d="Tag", i="items", extra="")), entity("Sub", attributes='parentEntity="Base" syncable="YES"'), entity("Tag", attribute("label", "String"), _REL.format(n="items", kind='toMany="YES" ', d="Base", i="tag", extra="")))},
    "omo-inh-2rel": {"Model": model(entity("Base", _REL.format(n="tag", kind='maxCount="1" ', d="Tag", i="items", extra=""), _REL.format(n="zs", kind='toMany="YES" ', d="Tag", i="z", extra="")),
                                    entity("Sub", attribute("c", "String"), attributes='parentEntity="Base" syncable="YES"'),
                                    entity("Tag", attribute("label", "String"), _REL.format(n="items", kind='toMany="YES" ', d="Base", i="tag", extra=""),
                                           _REL.format(n="z", kind='maxCount="1" ', d="Base", i="zs", extra="")))},
    "omo-inh-off-io": {"Model": model(entity("Aaa", attribute("x", "String"), attribute("y", "String")), entity("Base", attribute("p", "String")), entity("Sub", attribute("c", "String"), attributes='parentEntity="Base" syncable="YES"'))},
    "omo-inh-off-ii": {"Model": model(entity("Aaa", attribute("x", "String"), attribute("y", "String")), entity("Base", attribute("p", "String"), attribute("q", "String")), entity("Sub", attributes='parentEntity="Base" syncable="YES"'))},
    "omo-inh-off-oi": {"Model": model(entity("Aaa", attribute("x", "String"), attribute("y", "String"), _REL.format(n="bs", kind='toMany="YES" ', d="Base", i="r", extra="")), entity("Base", _REL.format(n="r", kind='maxCount="1" ', d="Aaa", i="bs", extra="")),
                                      entity("Sub", attribute("c", "String"), attributes='parentEntity="Base" syncable="YES"'))},
    "omo-inh-off-ir": {"Model": model(entity("Aaa", attribute("x", "String"), attribute("y", "String"), _REL.format(n="bs", kind='toMany="YES" ', d="Base", i="r", extra="")), entity("Base", _REL.format(n="r", kind='maxCount="1" ', d="Aaa", i="bs", extra="")), entity("Sub", attributes='parentEntity="Base" syncable="YES"'))},
    "omo-inh-fk": {"Model": model(entity("Aaa", attribute("x", "String"), _REL.format(n="b", kind='maxCount="1" ', d="Base", i="as", extra="")),
                                  entity("Base", attribute("p", "String"), _REL.format(n="as", kind='toMany="YES" ', d="Aaa", i="b", extra="")),
                                  entity("Sub", attribute("c", "String"), attributes='parentEntity="Base" syncable="YES"'))},
    "omo-inh-fk-sub": {"Model": model(entity("Aaa", attribute("x", "String"), _REL.format(n="s", kind='maxCount="1" ', d="Sub", i="as", extra="")),
                                      entity("Base", attribute("p", "String")),
                                      entity("Sub", attribute("c", "String"), _REL.format(n="as", kind='toMany="YES" ', d="Aaa", i="s", extra=""), attributes='parentEntity="Base" syncable="YES"'))},
    "omo-fr-several": {"Model": model(entity("Alpha", attribute("a", "String")), entity("Beta", attribute("b", "String")),
                                      extra='    <fetchRequest name="zAll" entity="Beta"/>\n    <fetchRequest name="AllAlpha" entity="Alpha"/>\n'
                                            '    <fetchRequest name="Second" entity="Alpha"/>\n')},
    "omo-val-cases": {"Model": model(entity("Item",
        attribute("a", "Integer 16", 'optional="YES" minValueString="-5" usesScalarValueType="YES"'),
        attribute("b", "Integer 64", 'optional="YES" maxValueString="9000000000" usesScalarValueType="YES"'),
        attribute("c", "Double", 'optional="YES" minValueString="0.5" maxValueString="2.25" usesScalarValueType="YES"'),
        attribute("d", "Float", 'optional="YES" minValueString="-1.5" usesScalarValueType="YES"'),
        attribute("e", "String", 'optional="YES" minValueString="3"'),
        attribute("f", "String", 'optional="YES" maxValueString="8" elementID="oldF"'),
        attribute("g", "Integer 32", 'optional="YES" minValueString="0" maxValueString="0" usesScalarValueType="YES"')))},
    "omo-val-float": {"Model": model(entity("Item",
        attribute("a", "Integer 16", 'optional="YES" defaultValueString="3" usesScalarValueType="YES"'),
        attribute("b", "Float", 'optional="YES" minValueString="0.1" usesScalarValueType="YES"'),
        attribute("c", "Integer 16", 'optional="YES" defaultValueString="4" usesScalarValueType="YES"'),
        attribute("d", "Double", 'optional="YES" maxValueString="0.3" usesScalarValueType="YES"'),
        attribute("e", "Integer 32", 'optional="YES" minValueString="7" usesScalarValueType="YES"')))},
    "omo-uq-several": {"Model": model(
        entity("Item", attribute("a", "String"), attribute("b", "String"), attribute("c", "Integer 64", 'optional="YES" usesScalarValueType="YES"'),
               _REL.format(n="tag", kind='maxCount="1" ', d="Tag", i="items", extra=""),
               '<uniquenessConstraints><uniquenessConstraint><constraint value="a"/></uniquenessConstraint>'
               '<uniquenessConstraint><constraint value="b"/><constraint value="c"/></uniquenessConstraint>'
               '<uniquenessConstraint><constraint value="tag"/><constraint value="a"/></uniquenessConstraint></uniquenessConstraints>'),
        entity("Other", attribute("x", "String")),
        entity("Tag", attribute("name", "String"), _REL.format(n="items", kind='toMany="YES" ', d="Item", i="tag", extra=""),
               '<uniquenessConstraints><uniquenessConstraint><constraint value="name"/></uniquenessConstraint></uniquenessConstraints>'))},
    "omo-fi-several": {"Model": model(
        entity("Item", attribute("a", "String"), attribute("b", "Integer 32", 'optional="YES" usesScalarValueType="YES"'),
               _REL.format(n="c", kind='maxCount="1" ', d="Tag", i="items", extra=""),
               '<fetchIndex name="byA"><fetchIndexElement property="a" type="Binary" order="ascending"/></fetchIndex>',
               '<fetchIndex name="byBA"><fetchIndexElement property="b" type="Binary" order="descending"/><fetchIndexElement property="a" type="Binary" order="ascending"/></fetchIndex>',
               '<fetchIndex name="byC"><fetchIndexElement property="c" type="Binary" order="ascending"/></fetchIndex>'),
        entity("Tag", attribute("name", "String"), _REL.format(n="items", kind='toMany="YES" ', d="Item", i="c", extra=""),
               '<fetchIndex name="byName"><fetchIndexElement property="name" type="Binary" order="ascending"/></fetchIndex>'))},
    "omo-fi-class": {"Model": model(
        '    <entity name="Item" representedClassName="StoredItem" syncable="YES">\n'
        '        <attribute name="a" optional="YES" attributeType="String"/>\n'
        '        <fetchIndex name="byA"><fetchIndexElement property="a" type="Binary" order="ascending"/></fetchIndex>\n    </entity>\n')},
    "omo-fi-indexed-compound": {"Model": model(
        entity("Item", attribute("x", "String", 'optional="YES" indexed="YES"'),
               attribute("y", "Integer 16", 'optional="YES" indexed="YES" usesScalarValueType="YES"'), attribute("z", "String"),
               '<compoundIndexes><compoundIndex><index value="y"/><index value="z"/></compoundIndex></compoundIndexes>'))},
    "omo-rel-ordered": {"Model": model(entity("A", _REL.format(n="bs", kind='toMany="YES" ordered="YES" ', d="B", i="a", extra="")),
                                        entity("B", _REL.format(n="a", kind='maxCount="1" ', d="A", i="bs", extra="")))},
    "omo-rel-many-to-many": {"Model": model(entity("A", _REL.format(n="bs", kind='toMany="YES" ', d="B", i="as", extra="")),
                                             entity("B", _REL.format(n="as", kind='toMany="YES" ', d="A", i="bs", extra="")))},
    "omo-rel-ordered-many-to-many": {"Model": model(entity("A", _REL.format(n="bs", kind='toMany="YES" ordered="YES" ', d="B", i="as", extra="")),
                                                     entity("B", _REL.format(n="as", kind='toMany="YES" ', d="A", i="bs", extra="")))},
    "omo-rel-no-inverse": {"Model": model(entity("A", '<relationship name="bs" optional="YES" toMany="YES" deletionRule="Nullify" destinationEntity="B"/>',
                                                 '<relationship name="c" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="B"/>'), entity("B"))},
    "omo-rel-rules": {"Model": model(entity("A", '<relationship name="b" maxCount="1" deletionRule="Deny" destinationEntity="B" inverseName="as" inverseEntity="B"/>',
                                            '<relationship name="cs" optional="YES" toMany="YES" minCount="1" maxCount="5" deletionRule="Cascade" destinationEntity="B" inverseName="a" inverseEntity="B"/>'),
                                     entity("B", '<relationship name="a" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="A" inverseName="cs" inverseEntity="A"/>',
                                            '<relationship name="as" optional="YES" toMany="YES" deletionRule="Deny" destinationEntity="A" inverseName="b" inverseEntity="A"/>'))},
    "omo-rel-transient": {"Model": model(entity("A", '<relationship name="b" optional="YES" maxCount="1" transient="YES" deletionRule="Nullify" destinationEntity="B" inverseName="a" inverseEntity="B"/>'),
                                         entity("B", '<relationship name="a" optional="YES" maxCount="1" transient="YES" deletionRule="Nullify" destinationEntity="A" inverseName="b" inverseEntity="A"/>'))},
    "omo-renaming-cases": {"Model": model(
        entity("A", attribute("a", "String", 'optional="YES" elementID="x"'),
               attribute("b", "Double", 'optional="YES" defaultValueString="1.5" usesScalarValueType="YES" elementID="y"'),
               attribute("c", "String", 'optional="YES" elementID="c"'), attribute("d", "String", 'optional="YES" elementID=""'),
               attribute("e", "Integer 16", 'optional="YES" defaultValueString="3" usesScalarValueType="YES" elementID="x"'),
               attribute("f", "Double", 'optional="YES" defaultValueString="2.5" usesScalarValueType="YES"'),
               attribute("g", "Transformable", 'optional="YES" valueTransformerName="NSSecureUnarchiveFromData" customClassName="[String]" elementID="w"'),
               attribute("h", "String", 'optional="YES" defaultValueString="hi" elementID="v"'),
               _REL.format(n="bs", kind='toMany="YES" ', d="B", i="a", extra=' elementID="bs"'),
               attributes='elementID="" syncable="YES"'),
        entity("B", attribute("k", "Date", 'optional="YES" defaultDateTimeInterval="120" usesScalarValueType="NO" elementID="u"'),
               _REL.format(n="a", kind='maxCount="1" ', d="A", i="bs", extra=' elementID="oldA"'),
               attributes='elementID="x" syncable="YES"'))},
})

# Which strings of VersionInfo.plist are one object: version names of every length, and entity
# names of 9 and 11 characters ending in each letter, digit and underscore (shared between
# versions or not).
ENTITY_NAME_CHARACTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"
VERSION_STRINGS_MODEL = model(*[entity(prefix + c) for prefix in ("Eeeeeeee", "Eeeeeeeeee") for c in ENTITY_NAME_CHARACTERS],
                              entity("Short"), entity("Eeeeeeeeeeee"))
VERSIONED["version-strings"] = {name: VERSION_STRINGS_MODEL for name in
                                ["A", "Ab", "Abc", "Abcd", "Model", "Abcdef", "Model 2", "Abcdefgh", "Abcdefghi",
                                 "Abcdefghij", "eeeeeeeeeee", "Abcdefghijkl", "Wikipedia 2"]}


def write_current_version(path, name):
    """The .xccurrentversion of versioned experiment `name`: its last version, or NO_CURRENT_VERSION's."""
    if name not in NO_CURRENT_VERSION:
        (path / ".xccurrentversion").write_text(current_version(list(VERSIONED[name])[-1]))
    elif NO_CURRENT_VERSION[name] is not None:
        (path / ".xccurrentversion").write_text(NO_CURRENT_VERSION[name])


def current_version(name):
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
            '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n'
            f'\t<key>_XCCurrentVersionName</key>\n\t<string>{name}.xcdatamodel</string>\n</dict>\n</plist>\n')


# version-hashes: (label, property fields), (label, entity fields, property labels) and (label, entity labels).
PROPERTY_PROBES = [
    ("base", {}), ("name-a", {"name": "a"}), ("name-ab", {"name": "ab"}), ("name-nul", {"name": "a\u0000b"}),
    ("name-unicode", {"name": "été"}), ("optional", {"optional": True}), ("transient", {"transient": True}),
    ("optional-transient", {"optional": True, "transient": True}), ("modifier", {"modifier": "m"}),
    ("name-modifier", {"name": "a", "modifier": "b"}), ("modifier-nul", {"modifier": "\u0000"}),
    ("external", {"external": True}), ("history", {"history": True}), ("external-history", {"external": True, "history": True}),
    ("binary-external", {"type": 1000, "external": True}),
    *[(f"type-{t}", {"type": t}) for t in [100, 200, 300, 400, 500, 600, 700, 800, 900, 1000, 1100, 1200, 1800, 2100]],
    ("timestamp", {"name": "timestamp", "type": 900, "optional": True}),
    # Inputs that leave the hash alone.
    ("indexed", {"indexed": True}), ("spotlight", {"spotlight": True}), ("renaming", {"renaming": "x"}),
    ("user-info", {"userInfo": True}), ("transformer", {"transformer": "T"}), ("cloud-encryption", {"cloudEncryption": True}),
    ("default", {"default": True}), ("validation", {"validation": True}), ("value-class", {"type": 1800, "valueClass": "NSArray"}),
    # Relationships.
    ("rel-base", {"kind": "relationship"}), ("rel-name", {"kind": "relationship", "name": "r"}),
    ("rel-optional-transient", {"kind": "relationship", "optional": True, "transient": True}),
    ("rel-modifier", {"kind": "relationship", "modifier": "m"}), ("rel-destination", {"kind": "relationship", "destination": "DE"}),
    ("rel-inverse", {"kind": "relationship", "inverse": "i"}),
    ("rel-destination-inverse", {"kind": "relationship", "destination": "D", "inverse": "i"}),
    ("rel-max", {"kind": "relationship", "max": 1}), ("rel-max-large", {"kind": "relationship", "max": 70000}),
    ("rel-min", {"kind": "relationship", "min": 3}), ("rel-ordered", {"kind": "relationship", "ordered": True}),
    ("rel-ordered-counts", {"kind": "relationship", "ordered": True, "max": 5, "min": 2}),
    ("rel-delete-rule", {"kind": "relationship", "deleteRule": 2}),
]
ENTITY_PROBES = [
    ("empty", {}, []), ("name", {"name": "Item"}, []), ("abstract", {"abstract": True}, []), ("modifier", {"modifier": "m"}, []),
    ("one-property", {"name": "Item"}, ["timestamp"]), ("property-order", {"name": "E"}, ["name-ab", "name-a", "rel-name"]),
    ("transient-property", {"name": "E"}, ["name-a", "transient"]),
    ("uniqueness", {"name": "E", "uniqueness": [["ab"], ["a"]]}, ["name-a", "name-ab"]),
    ("uniqueness-compound", {"name": "E", "uniqueness": [["ab", "a"], ["a"]], "modifier": "m"}, ["name-a", "name-ab"]),
    ("sub", {"name": "S", "super": "one-property"}, ["name-a"]), ("sub-sub", {"name": "T", "super": "sub"}, ["name-ab"]),
    # Inputs that leave the hash alone.
    ("index", {"name": "E", "index": True}, ["name-a"]), ("class-name", {"name": "E", "className": "X"}, ["name-a"]),
    ("entity-renaming", {"name": "E", "renaming": "r"}, ["name-a"]), ("entity-user-info", {"name": "E", "userInfo": True}, ["name-a"]),
]
MODEL_PROBES = [("no-entities", []), ("entities", ["one-property", "property-order"])]
PROBE_SOURCE = r"""
import CoreData
import Foundation
func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }
let spec = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
var propertySpecs: [String: [String: Any]] = [:]
var entitySpecs: [String: [Any]] = [:]
// Entities hold their superentity and destination weakly.
var keptAlive: [AnyObject] = []
func property(_ f: [String: Any]) -> NSPropertyDescription {
    let p: NSPropertyDescription
    if f["kind"] as? String == "relationship" {
        let r = NSRelationshipDescription()
        if let d = f["destination"] as? String { let e = NSEntityDescription(); e.name = d; r.destinationEntity = e; keptAlive.append(e) }
        if let i = f["inverse"] as? String { let v = NSRelationshipDescription(); v.name = i; r.inverseRelationship = v; keptAlive.append(v) }
        r.maxCount = f["max"] as? Int ?? 0
        r.minCount = f["min"] as? Int ?? 0
        r.isOrdered = f["ordered"] as? Bool ?? false
        if let d = f["deleteRule"] as? Int { r.deleteRule = NSDeleteRule(rawValue: UInt(d))! }
        p = r
    } else {
        let a = NSAttributeDescription()
        a.attributeType = NSAttributeType(rawValue: UInt(f["type"] as? Int ?? 0))!
        if f["external"] != nil { a.allowsExternalBinaryDataStorage = true }
        if f["history"] != nil { a.preservesValueInHistoryOnDeletion = true }
        if let t = f["transformer"] as? String { a.valueTransformerName = t }
        if f["default"] != nil { a.defaultValue = 3 }
        if let c = f["valueClass"] as? String { a.attributeValueClassName = c }
        if f["spotlight"] != nil { a.isIndexedBySpotlight = true }
        if f["cloudEncryption"] != nil { a.allowsCloudEncryption = true }
        p = a
    }
    p.name = f["name"] as? String ?? ""
    p.isOptional = f["optional"] as? Bool ?? false
    p.isTransient = f["transient"] as? Bool ?? false
    if f["indexed"] != nil { p.isIndexed = true }
    if let r = f["renaming"] as? String { p.renamingIdentifier = r }
    if f["userInfo"] != nil { p.userInfo = ["k": "v"] }
    if let m = f["modifier"] as? String { p.versionHashModifier = m }
    if f["validation"] != nil { p.setValidationPredicates([NSPredicate(value: true)], withValidationWarnings: ["w"]) }
    return p
}
func entity(_ label: String) -> NSEntityDescription {
    let probe = entitySpecs[label]!
    let f = probe[1] as! [String: Any]
    let e = NSEntityDescription()
    e.name = f["name"] as? String ?? ""
    e.isAbstract = f["abstract"] as? Bool ?? false
    if let m = f["modifier"] as? String { e.versionHashModifier = m }
    e.properties = (probe[2] as! [String]).map { property(propertySpecs[$0]!) }
    if let u = f["uniqueness"] as? [[String]] { e.uniquenessConstraints = u }
    if f["index"] != nil {
        e.indexes = [NSFetchIndexDescription(name: "i", elements: [NSFetchIndexElementDescription(property: e.properties[0], collationType: .binary)])]
    }
    if let c = f["className"] as? String { e.managedObjectClassName = c }
    if let r = f["renaming"] as? String { e.renamingIdentifier = r }
    if f["userInfo"] != nil { e.userInfo = ["k": "v"] }
    if let s = f["super"] as? String { let parent = entity(s); parent.subentities = [e]; keptAlive.append(parent) }
    return e
}
var result: [String: Any] = [:]
for case let probe as [Any] in spec["properties"] as! [Any] {
    propertySpecs[probe[0] as! String] = probe[1] as? [String: Any]
    result["property:" + (probe[0] as! String)] = hex(property(probe[1] as! [String: Any]).versionHash)
}
for case let probe as [Any] in spec["entities"] as! [Any] {
    entitySpecs[probe[0] as! String] = probe
    result["entity:" + (probe[0] as! String)] = hex(entity(probe[0] as! String).versionHash)
}
for case let probe as [Any] in spec["models"] as! [Any] {
    let model = NSManagedObjectModel()
    model.entities = (probe[1] as! [String]).map { entity($0) }
    _ = NSPersistentStoreCoordinator(managedObjectModel: model)
    result["model:" + (probe[0] as! String)] = model.versionChecksum
}
FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]))
"""


def c_string(text):
    """The UTF-8 bytes of `text` up to its first NUL, as the hashes read names (`name-nul`)."""
    return (text or "").encode().split(b"\0")[0]


def property_hash(fields):
    """docs/formats/coredata.md "Version hashes": SHA-256 of the property's own hash and its kind's fields."""
    import hashlib
    import struct
    flags = (1 if fields.get("optional") else 0) | (2 if fields.get("transient") else 0)
    own = hashlib.sha256(c_string(fields.get("name")) + bytes([flags, 0]) + c_string(fields.get("modifier"))).digest()
    if fields.get("kind") == "relationship":
        tail = (c_string(fields.get("destination")) + c_string(fields.get("inverse"))
                + struct.pack("<II", fields.get("max", 0), fields.get("min", 0)) + (b"\1\0" if fields.get("ordered") else b""))
    else:
        tail = struct.pack("<I", fields.get("type", 0)) + b"\1" * (bool(fields.get("external")) + bool(fields.get("history")))
    return hashlib.sha256(own + tail).digest()


def entity_hash(label):
    """SHA-256 of the name, isAbstract, the superentity's hash, the persistent properties' hashes by
    name (inherited ones included), the versionHashModifier and the uniqueness constraints."""
    import hashlib
    _, fields, own = next(p for p in ENTITY_PROBES if p[0] == label)
    properties = dict(PROPERTY_PROBES)
    names = list(own)
    parent = b""
    if "super" in fields:
        parent = entity_hash(fields["super"])
        ancestor = fields["super"]
        while ancestor:
            _, ancestor_fields, ancestor_own = next(p for p in ENTITY_PROBES if p[0] == ancestor)
            names += ancestor_own
            ancestor = ancestor_fields.get("super")
    persistent = sorted((properties[n].get("name", ""), n) for n in names if not properties[n].get("transient"))
    constraints = b"".join(sorted(".".join(group).encode() for group in fields.get("uniqueness", [])))
    return hashlib.sha256(c_string(fields.get("name")) + bytes([1 if fields.get("abstract") else 0]) + parent
                          + b"".join(property_hash(properties[n]) for _, n in persistent) + c_string(fields.get("modifier"))
                          + constraints).digest()


def version_hashes(work):
    """Core Data's own versionHash of each probe and versionChecksum of each model, checked against
    the rules docs/formats/coredata.md states."""
    import hashlib
    work.mkdir(parents=True, exist_ok=True)
    (work / "probe.swift").write_text(PROBE_SOURCE)
    (work / "spec.json").write_text(json.dumps({"properties": PROPERTY_PROBES, "entities": ENTITY_PROBES, "models": MODEL_PROBES}))
    built = subprocess.run(["xcrun", "swiftc", "-O", str(work / "probe.swift"), "-o", str(work / "probe")], capture_output=True)
    if built.returncode != 0:
        return {"status": built.returncode, "stderr": built.stderr.decode(errors="replace")}
    proc = subprocess.run([str(work / "probe"), str(work / "spec.json")], capture_output=True)
    hashes = json.loads(proc.stdout)
    rules = {f"property:{label}": property_hash(fields).hex() == hashes[f"property:{label}"] for label, fields in PROPERTY_PROBES}
    rules.update({f"entity:{label}": entity_hash(label).hex() == hashes[f"entity:{label}"] for label, _, _ in ENTITY_PROBES})
    for label, entities in MODEL_PROBES:
        names = sorted((next(p for p in ENTITY_PROBES if p[0] == e)[1].get("name", ""), e) for e in entities)
        checksum = hashlib.sha256(b"".join(entity_hash(e) for _, e in names)).digest()
        rules[f"model:{label}"] = base64.b64encode(checksum).decode() == hashes[f"model:{label}"]
    return {"status": proc.returncode, "hashes": hashes, "rules hold": rules}


def build_experiment(work):
    """The build's momc command lines, for an app with a versioned model and an unversioned one."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from pif_experiments import write_project
    shutil.rmtree(work, ignore_errors=True)
    files = {"Src/App.swift": "import UIKit\n@main class AppDelegate: UIResponder, UIApplicationDelegate {}\n",
             "Src/Model.xcdatamodeld/Model.xcdatamodel/contents": EXPERIMENTS["one-date"],
             "Src/Model.xcdatamodeld/.xccurrentversion": current_version("Model"),
             "Src/Flat.xcdatamodel/contents": model(entity("Flat", typed("Date", "timestamp")))}
    project = write_project(work, "P", "C00000000000000000000001", "T", [("A00000000000000000000001", "Src")], files)
    proc = subprocess.run(["xcodebuild", "-project", str(project), "-target", "T", "-configuration", "Debug", "-sdk", "iphoneos",
                           "CODE_SIGNING_ALLOWED=NO", "SWIFT_VERSION=5.0", "ALWAYS_SEARCH_USER_PATHS=NO",
                           f"SYMROOT={work}/build/products", f"OBJROOT={work}/build/intermediates", "build"], cwd=work, capture_output=True)
    log = proc.stdout.decode(errors="replace")
    tasks = [line for line in log.splitlines() if line.startswith(("DataModelCompile ", "DataModelCodegen ")) or "/momc " in line]
    return {"status": proc.returncode, "tasks": [line.replace(str(work), "<WORK>") for line in tasks]}


def sdk(platform="iphoneos"):
    return subprocess.run(["xcrun", "--sdk", platform, "--show-sdk-path"], capture_output=True, text=True).stdout.strip()


# `platforms`: momc and mapc as builds for other platforms run them (`--<platform>-deployment-target`,
# CoreData.xcspec), each output compared with the iOS one already observed.
PLATFORMS = [("watchos", "9.0"), ("watchos", "27.0"), ("watchsimulator", "27.0"), ("appletvos", "27.0"), ("macosx", "27.0"),
             ("xros", "27.0"), ("iphonesimulator", "27.0")]


def compile_mapping(path, out, platform=("iphoneos", "27.0")):
    """mapc as a build runs it (MappingModelCompile), with the experiments' module and target."""
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    target = out / (path.stem + ".cdm")
    proc = subprocess.run(["xcrun", "mapc", "--sdkroot", sdk(platform[0]), f"--{platform[0]}-deployment-target", platform[1], "--module", "T",
                           str(path), str(target)], capture_output=True)
    files = {str(p.relative_to(out)): base64.b64encode(p.read_bytes()).decode() for p in sorted(out.rglob("*")) if p.is_file()}
    return {"status": proc.returncode, "stdout": proc.stdout.decode(errors="replace"), "stderr": proc.stderr.decode(errors="replace"),
            "files": files}


def compile_model(path, out, action=None, platform=("iphoneos", "27.0"), dry_run=False):
    args = ["xcrun", "momc"] + (["--dry-run"] if dry_run else [])
    if action == "generate":
        args += ["--action", "generate", "--swift-version", "5.0"]
    args += ["--sdkroot", sdk(platform[0]), f"--{platform[0]}-deployment-target", platform[1], "--module", "T", str(path), str(out)]
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    proc = subprocess.run(args, capture_output=True)
    files = {str(p.relative_to(out)): base64.b64encode(p.read_bytes()).decode() for p in sorted(out.rglob("*")) if p.is_file()}
    return {"status": proc.returncode, "stdout": proc.stdout.decode(errors="replace"), "stderr": proc.stderr.decode(errors="replace"),
            "files": files}


def write_model(work, name):
    """Experiment `name`'s model, written again at the path momc compiles it from."""
    shutil.rmtree(work / name, ignore_errors=True)
    if name in VERSIONED:
        path = work / name / "Model.xcdatamodeld"
        for version, contents in VERSIONED[name].items():
            (path / f"{version}.xcdatamodel").mkdir(parents=True)
            (path / f"{version}.xcdatamodel" / "contents").write_text(contents)
        write_current_version(path, name)
    else:
        path = work / name / "Model.xcdatamodel"
        path.mkdir(parents=True)
        (path / "contents").write_text(EXPERIMENTS[name])
    return path


def platforms(work, observations):
    """Every model observed for iOS compiled, generated and dry-run, and every corpus mapping model
    mapped, for each of PLATFORMS: the outputs that differ from iOS's. Destination paths are left
    out, each .omo's family lists are sorted (ADR 0232), and outputs that differ between two iOS
    runs are counted apart as varying."""
    from coredata_compare import sorting_families

    def outputs(result, out):
        files = {name: (base64.b64encode(sorting_families(base64.b64decode(data))).decode() if name.endswith(".omo") else data)
                 for name, data in result["files"].items()}
        return result["status"], files, result["stderr"].replace(str(out), "<out>"), result["stdout"].replace(str(out), "<out>")

    def run(path, label, action):
        out = work / "platforms" / label / action
        if action == "mapping":
            return outputs(compile_mapping(path, out, platform), out)
        return outputs(compile_model(path, out, None if action == "compile" else "generate", platform, action == "dry-run"), out)

    sources = {}
    for name, record in observations.items():
        if "compile" not in record or name.startswith("mapping:"):
            continue
        if name.startswith("corpus:"):
            sources[name] = Path(name[len("corpus:"):])
        elif name in EXPERIMENTS or name in VERSIONED:
            sources[name] = write_model(work, name)
    jobs = [(name, path, action) for name, path in sources.items() for action in ("compile", "generate", "dry-run")]
    jobs += [(f"mapping:{path}", path, "mapping") for path in sorted(Path("/tmp/nomac-corpus").glob("*/**/*.xcmappingmodel"))]
    platform = ("iphoneos", "27.0")
    ios = {(name, action): (run(path, "ios", action), run(path, "ios-again", action)) for name, path, action in jobs}
    results = {}
    for platform in PLATFORMS:
        label = "-".join(platform)
        compared, varying, differences = 0, 0, []
        for name, path, action in jobs:
            first, second = ios[(name, action)]
            if first != second:
                varying += 1
                continue
            compared += 1
            if run(path, label, action) != first:
                differences.append(f"{name} {action}")
        results[label] = {"compared": compared, "varying": varying, "differences": differences}
    return results


def omo_runs(path, out, runs=2):
    """The .omo files of `runs` more compilations of `path`: which of their bytes momc changes from run to run."""
    return [{file: data for file, data in compile_model(path, out / f"run-{run}")["files"].items() if file.endswith(".omo")}
            for run in range(runs)]


def main():
    out = Path(sys.argv[1]).resolve()
    selected = sys.argv[2:] or [*EXPERIMENTS, *VERSIONED, "corpus", "mapping-corpus", "version-hashes", "build"]
    work = Path("/tmp/nomac-coredata-experiments")
    out.mkdir(parents=True, exist_ok=True)
    recorded = out / "observations.json"
    observations = json.loads(recorded.read_text()) if recorded.exists() else {}
    for name in selected:
        if name == "version-hashes":
            observations[name] = version_hashes(work / name)
            rules = observations[name].get("rules hold", {})
            print(f"[{name}] {sum(rules.values())} / {len(rules)} hashes follow the rules", *[k for k, v in rules.items() if not v], flush=True)
            continue
        if name == "build":
            observations[name] = build_experiment(work / name)
            print(f"[{name}] {observations[name]['status']}", *observations[name]["tasks"], sep="\n    ", flush=True)
            continue
        if name == "dry-runs":
            # What `momc --dry-run --action generate` prints for every model already compiled here.
            for key in [k for k in observations if "compile" in observations[k] and not k.startswith("mapping:")]:
                path = Path(key[len("corpus:"):]) if key.startswith("corpus:") else next(
                    (work / key / f for f in ("Model.xcdatamodeld", "Model.xcdatamodel") if (work / key / f).exists()), None)
                if path is None:
                    continue
                proc = subprocess.run(["xcrun", "momc", "--dry-run", "--action", "generate", "--swift-version", "5.0", "--sdkroot", sdk(),
                                       "--iphoneos-deployment-target", "27.0", "--module", "T", str(path), str(work / "dry-run-out")],
                                      capture_output=True, text=True)
                observations[key]["dry-run"] = {"status": proc.returncode, "stdout": proc.stdout, "stderr": proc.stderr}
            print(f"[{name}] {sum('dry-run' in r for r in observations.values())} models", flush=True)
            continue
        if name == "mapping-corpus":
            for path in sorted(Path("/tmp/nomac-corpus").glob("*/**/*.xcmappingmodel")):
                key = f"mapping:{path}"
                observations[key] = {"compile": compile_mapping(path, work / "mapping" / str(len(observations)))}
                print(f"[{key}] {observations[key]['compile']['status']} {observations[key]['compile']['stderr'].strip()[:200]}", flush=True)
            continue
        if name == "corpus":
            for path in sorted(Path("/tmp/nomac-corpus").glob("*/**/*.xcdatamodeld")) + sorted(
                    p for p in Path("/tmp/nomac-corpus").glob("*/**/*.xcdatamodel") if p.parent.suffix != ".xcdatamodeld"):
                key = f"corpus:{path}"
                observations[key] = {"compile": compile_model(path, work / "corpus" / str(len(observations)) / "compile"),
                                     "generate": compile_model(path, work / "corpus" / str(len(observations)) / "generate", "generate")}
                if any(file.endswith(".omo") for file in observations[key]["compile"]["files"]):
                    observations[key]["omo-runs"] = omo_runs(path, work / "corpus" / "runs")
                print(f"[{key}] {observations[key]['compile']['status']} {sorted(observations[key]['compile']['files'])[:4]}", flush=True)
            continue
        if name == "platforms":
            observations[name] = platforms(work, observations)
            for platform, result in observations[name].items():
                print(f"[{name}] {platform}: {result['compared']} outputs compared ({result['varying']} varying between iOS runs), "
                      f"{len(result['differences'])} different", *result["differences"][:5], flush=True)
            continue
        path = write_model(work, name)
        observations[name] = {"compile": compile_model(path, work / name / "compile"),
                              "generate": compile_model(path, work / name / "generate", "generate")}
        if any(file.endswith(".omo") for file in observations[name]["compile"]["files"]):
            observations[name]["omo-runs"] = omo_runs(path, work / name)
        result = observations[name]["compile"]
        print(f"[{name}] {result['status']} {sorted(result['files'])} {result['stderr'].strip()[:200]}", flush=True)
    recorded.write_text(json.dumps(observations, indent=1) + "\n")


if __name__ == "__main__":
    main()
