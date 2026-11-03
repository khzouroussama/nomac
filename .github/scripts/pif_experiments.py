#!/usr/bin/env python3
"""Observe how Xcode identifies and orders synchronized-folder members in the PIF.

Runs on a macOS machine with Xcode installed (the `pif-experiments` workflow). Each experiment
is a small project written here from scratch: one PBXFileSystemSynchronizedRootGroup per
folder, one application target. Experiments differ from the base in exactly one input (an
object ID, a folder or file name, file contents, the project name, the list order of roots in
a target), so comparing their PIFs shows which inputs a member's GUID and a build phase's
order depend on. `xcodebuild -dumpPIF` runs once per experiment; observations.json records,
for each experiment, every synchronized node (path, GUID) and every build phase (member paths
in order, with build-file and file-reference GUIDs).

No Xcode output other than the PIFs of these self-written projects is kept.

Usage: pif_experiments.py <output-dir> [experiment ...]

Without experiment names, every experiment runs and the output directory is recreated; with
names, only those run and only their outputs are replaced.
"""

import json
import re
import shutil
import struct
import subprocess
import sys
from pathlib import Path

PROJECT_TEMPLATE = """// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 77;
	objects = {{

/* Begin PBXFileSystemSynchronizedRootGroup section */
{roots}
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFileReference section */
		F00000000000000000000001 /* {target}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {target}.app; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */
{extra_objects}

/* Begin PBXGroup section */
		F00000000000000000000002 = {{
			isa = PBXGroup;
			children = (
{root_refs}{own_refs}				F00000000000000000000003 /* Products */,
			);
			sourceTree = "<group>";
		}};
		F00000000000000000000003 /* Products */ = {{
			isa = PBXGroup;
			children = (
				F00000000000000000000001 /* {target}.app */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{target_id} /* {target} */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = F00000000000000000000010 /* Build configuration list for PBXNativeTarget "{target}" */;
			buildPhases = (
				F00000000000000000000004 /* Sources */,
				F00000000000000000000005 /* Resources */,
{frameworks_ref}			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
{target_roots}			);
			name = {target};
			productName = {target};
			productReference = F00000000000000000000001 /* {target}.app */;
			productType = "com.apple.product-type.application";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		F00000000000000000000006 /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 2700;
				LastUpgradeCheck = 2700;
			}};
			buildConfigurationList = F00000000000000000000011 /* Build configuration list for PBXProject "{name}" */;
			developmentRegion = {development_region};
			hasScannedForEncodings = 0;
			knownRegions = (
{known_regions}			);
			mainGroup = F00000000000000000000002;
			minimizedProjectReferenceProxies = 1;
			preferredProjectObjectVersion = 77;
			productRefGroup = F00000000000000000000003 /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{target_id} /* {target} */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
{frameworks_phase}		F00000000000000000000005 /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		F00000000000000000000004 /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{own_build_files}			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		F00000000000000000000007 /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				SDKROOT = iphoneos;
			}};
			name = Debug;
		}};
		F00000000000000000000008 /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				SDKROOT = iphoneos;
			}};
			name = Release;
		}};
		F00000000000000000000012 /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				GENERATE_INFOPLIST_FILE = YES;
				PRODUCT_BUNDLE_IDENTIFIER = org.nomac.experiment;
				PRODUCT_NAME = "$(TARGET_NAME)";
{debug_settings}			}};
			name = Debug;
		}};
		F00000000000000000000013 /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				GENERATE_INFOPLIST_FILE = YES;
				PRODUCT_BUNDLE_IDENTIFIER = org.nomac.experiment;
				PRODUCT_NAME = "$(TARGET_NAME)";
{release_settings}			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		F00000000000000000000010 /* Build configuration list for PBXNativeTarget "{target}" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				F00000000000000000000012 /* Debug */,
				F00000000000000000000013 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		F00000000000000000000011 /* Build configuration list for PBXProject "{name}" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				F00000000000000000000007 /* Debug */,
				F00000000000000000000008 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */
	}};
	rootObject = F00000000000000000000006 /* Project object */;
}}
"""

ROOT_A = "A00000000000000000000001"
ROOT_B = "B00000000000000000000001"
TARGET = "C00000000000000000000001"
BASE_FILES = {"Src/a.swift": "let a = 1\n"}

# name: (project name, target id, target name, roots [(object id, folder)], files {path: contents})
EXPERIMENTS = {
    "base": ("P", TARGET, "T", [(ROOT_A, "Src")], BASE_FILES),
    "root-id": ("P", TARGET, "T", [("A00000000000000000000002", "Src")], BASE_FILES),
    "root-folder": ("P", TARGET, "T", [(ROOT_A, "Other")], {"Other/a.swift": "let a = 1\n"}),
    "file-name": ("P", TARGET, "T", [(ROOT_A, "Src")], {"Src/b.swift": "let a = 1\n"}),
    "file-contents": ("P", TARGET, "T", [(ROOT_A, "Src")], {"Src/a.swift": "let a = 2\n"}),
    "project-name": ("Q", TARGET, "T", [(ROOT_A, "Src")], BASE_FILES),
    "target-id": ("P", "C00000000000000000000002", "T", [(ROOT_A, "Src")], BASE_FILES),
    "target-name": ("P", TARGET, "U", [(ROOT_A, "Src")], BASE_FILES),
    "subfolder": ("P", TARGET, "T", [(ROOT_A, "Src")], {"Src/d/a.swift": "let a = 1\n"}),
    "two-files": ("P", TARGET, "T", [(ROOT_A, "Src")], {"Src/a.swift": "let a = 1\n", "Src/b.swift": "let b = 1\n"}),
    "empty-name-a": ("P", TARGET, "T", [(ROOT_A, "Src")], {"Src/a": "x\n"}),
    "order-two-roots": ("P", TARGET, "T", [(ROOT_A, "Alpha"), (ROOT_B, "Beta")], {
        **{f"Alpha/a{i}.swift": f"let a{i} = 1\n" for i in range(1, 7)},
        **{f"Beta/b{i}.swift": f"let b{i} = 1\n" for i in range(1, 4)},
        "Alpha/g/a7.swift": "let a7 = 1\n", "Beta/h/b4.swift": "let b4 = 1\n"}),
    "order-two-roots-swapped": ("P", TARGET, "T", [(ROOT_B, "Beta"), (ROOT_A, "Alpha")], {
        **{f"Alpha/a{i}.swift": f"let a{i} = 1\n" for i in range(1, 7)},
        **{f"Beta/b{i}.swift": f"let b{i} = 1\n" for i in range(1, 4)},
        "Alpha/g/a7.swift": "let a7 = 1\n", "Beta/h/b4.swift": "let b4 = 1\n"}),
    "order-two-roots-ids-swapped": ("P", TARGET, "T", [(ROOT_B, "Alpha"), (ROOT_A, "Beta")], {
        **{f"Alpha/a{i}.swift": f"let a{i} = 1\n" for i in range(1, 7)},
        **{f"Beta/b{i}.swift": f"let b{i} = 1\n" for i in range(1, 4)},
        "Alpha/g/a7.swift": "let a7 = 1\n", "Beta/h/b4.swift": "let b4 = 1\n"}),
    "order-same-names": ("P", TARGET, "T", [(ROOT_A, "Alpha"), (ROOT_B, "Beta")], {
        **{f"Alpha/f{i}.swift": f"let a{i} = 1\n" for i in range(1, 6)},
        **{f"Beta/f{i}x.swift": f"let b{i} = 1\n" for i in range(1, 6)}}),
    # Round 2: which language wins a tie in predominantSourceCodeLanguage (icecubes' action
    # extension, one .js resource and one .swift source, reports JavaScript).
    "language-tie-js-first-in-tree": ("P", TARGET, "T", [(ROOT_A, "Src")], {
        "Src/Action.js": "var a = 1;\n", "Src/ActionRequestHandler.swift": "let a = 1\n"}),
    "language-tie-swift-first-in-tree": ("P", TARGET, "T", [(ROOT_A, "Src")], {
        "Src/a.swift": "let a = 1\n", "Src/b.js": "var b = 1;\n"}),
    "language-two-js-one-swift": ("P", TARGET, "T", [(ROOT_A, "Src")], {
        "Src/a.swift": "let a = 1\n", "Src/b.js": "var b = 1;\n", "Src/c.js": "var c = 1;\n"}),
    # Round 2: where the second root's members go in a phase.
    "order-flat-7-4": ("P", TARGET, "T", [(ROOT_A, "Alpha"), (ROOT_B, "Beta")], {
        **{f"Alpha/a{i}.swift": f"let a{i} = 1\n" for i in range(1, 8)},
        **{f"Beta/b{i}.swift": f"let b{i} = 1\n" for i in range(1, 5)}}),
    "order-subfolder-in-first": ("P", TARGET, "T", [(ROOT_A, "Alpha"), (ROOT_B, "Beta")], {
        **{f"Alpha/a{i}.swift": f"let a{i} = 1\n" for i in range(1, 7)}, "Alpha/g/a7.swift": "let a7 = 1\n",
        **{f"Beta/b{i}.swift": f"let b{i} = 1\n" for i in range(1, 5)}}),
    "order-subfolder-in-second": ("P", TARGET, "T", [(ROOT_A, "Alpha"), (ROOT_B, "Beta")], {
        **{f"Alpha/a{i}.swift": f"let a{i} = 1\n" for i in range(1, 8)},
        **{f"Beta/b{i}.swift": f"let b{i} = 1\n" for i in range(1, 4)}, "Beta/h/b4.swift": "let b4 = 1\n"}),
    "order-one-each": ("P", TARGET, "T", [(ROOT_A, "Alpha"), (ROOT_B, "Beta")], {
        "Alpha/a1.swift": "let a1 = 1\n", "Beta/b1.swift": "let b1 = 1\n"}),
    "order-three-roots": ("P", TARGET, "T", [(ROOT_A, "Alpha"), (ROOT_B, "Beta"), ("D00000000000000000000001", "Gamma")], {
        **{f"Alpha/a{i}.swift": f"let a{i} = 1\n" for i in range(1, 4)},
        **{f"Beta/b{i}.swift": f"let b{i} = 1\n" for i in range(1, 4)},
        **{f"Gamma/c{i}.swift": f"let c{i} = 1\n" for i in range(1, 4)}}),
    "order-deep-first": ("P", TARGET, "T", [(ROOT_A, "Alpha"), (ROOT_B, "Beta")], {
        "Alpha/x/y/a1.swift": "let a1 = 1\n", "Alpha/x/a2.swift": "let a2 = 1\n", "Alpha/a3.swift": "let a3 = 1\n",
        "Beta/b1.swift": "let b1 = 1\n", "Beta/b2.swift": "let b2 = 1\n"}),
}

# Round 3 (BACKLOG B-007): where each folder's members go in a phase, for every pair of folder
# sizes from 1 to 10 and every triple from 1 to 3. Names are zero-padded so that each folder's
# own order is plain name order.
ROOT_C = "B00000000000000000000002"


def sized_roots(sizes):
    roots, files = [], {}
    for (root_id, folder, prefix), size in zip([(ROOT_A, "Alpha", "a"), (ROOT_B, "Beta", "b"), (ROOT_C, "Gamma", "c")], sizes):
        roots.append((root_id, folder))
        files.update({f"{folder}/{prefix}{i:02}.swift": f"let {prefix}{i:02} = 1\n" for i in range(1, size + 1)})
    return roots, files


for first in range(1, 11):
    for second in range(1, 11):
        roots, files = sized_roots([first, second])
        EXPERIMENTS[f"grid-{first}-{second}"] = ("P", TARGET, "T", roots, files)
for sizes in [(a, b, c) for a in range(1, 4) for b in range(1, 4) for c in range(1, 4)]:
    roots, files = sized_roots(sizes)
    EXPERIMENTS[f"grid3-{sizes[0]}-{sizes[1]}-{sizes[2]}"] = ("P", TARGET, "T", roots, files)

# Round 4 (BACKLOG B-007): each folder's members go in as one block at h % (n + 1), h folding
# h * 33 + NSString hash over item names. Each experiment checks one part of what h covers and
# what the list starts with, on Alpha (a01-a05) and Beta (b01-b03).
ROOTS, FILES = sized_roots([5, 3])
EXPERIMENTS.update({
    # An item the target's exception set removes from a folder it lists still counts.
    "order-excluded-counts": ("P", TARGET, "T", ROOTS, {**FILES, "Beta/b00.swift": "let b00 = 1\n"}, {"exceptions": {ROOT_B: ["b00.swift"]}}),
    # Items of other kinds (resources) do not count for the Sources phase, and the other way round.
    "order-other-kinds": ("P", TARGET, "T", ROOTS, {**FILES, "Alpha/a.json": "{}\n", "Beta/r1.json": "{}\n", "Beta/r2.json": "{}\n"}),
    # A folder the target does not list: only the items its exception set names count.
    "order-unlisted-folder": ("P", TARGET, "T", ROOTS, FILES, {"target_roots": [ROOT_A], "exceptions": {ROOT_B: ["b02.swift", "b03.swift"]}}),
    # The phase's own build files are the list the first folder goes into.
    "order-own-files": ("P", TARGET, "T", [(ROOT_A, "Alpha")], {f"Alpha/a{i:02}.swift": f"let a{i:02} = 1\n" for i in range(1, 4)},
                        {"own_sources": ["o1.swift", "o2.swift", "o3.swift", "o4.swift"]}),
    # Folders go in in group-tree order, whatever order the target lists them in.
    "order-target-lists-second-first": ("P", TARGET, "T", ROOTS, FILES, {"target_roots": [ROOT_B, ROOT_A]}),
    # Items in subfolders count by name; the subfolders themselves do not.
    "order-nested-names": ("P", TARGET, "T", ROOTS,
                           {**{f"Alpha/a{i:02}.swift": f"let a{i:02} = 1\n" for i in range(1, 6)},
                            "Beta/s/b01.swift": "let b01 = 1\n", "Beta/s/t/b02.swift": "let b02 = 1\n", "Beta/b03.swift": "let b03 = 1\n"}),
})

# Round 5: swiftfin's XcodeConfig folder has a DevelopmentTeam.xcconfig in Xcode's group tree,
# a file its exception sets name but that is not on disk.
EXPERIMENTS.update({
    # Missing paths an exception set of a listed folder names: a file, one in a subfolder, an xcconfig.
    "missing-excepted-listed": ("P", TARGET, "T", [(ROOT_A, "Alpha")], {"Alpha/a01.swift": "let a01 = 1\n"},
                                {"exceptions": {ROOT_A: ["gone.swift", "sub/gone.swift", "gone.xcconfig"]}}),
    # A missing path the exception set of a folder the target does not list names, next to a present one.
    "missing-excepted-unlisted": ("P", TARGET, "T", [(ROOT_A, "Alpha"), (ROOT_B, "Beta")],
                                  {"Alpha/a01.swift": "let a01 = 1\n", "Beta/b01.swift": "let b01 = 1\n"},
                                  {"target_roots": [ROOT_A], "exceptions": {ROOT_B: ["b01.swift", "gone.swift"]}}),
})

# Round 6: swiftfin's Translations folder holds an af.lproj whose region knownRegions lacks, and
# the PIF's knownRegions ends with "af". Which .lproj folders add a region, and in which order.
STRINGS = '"key" = "value";\n'
EXPERIMENTS.update({
    # One folder: a region knownRegions has (en), new ones out of name order, one in a subfolder.
    "regions-one-folder": ("P", TARGET, "T", [(ROOT_A, "Alpha")],
                           {"Alpha/a01.swift": "let a01 = 1\n", "Alpha/sub/ja.lproj/L.strings": STRINGS,
                            **{f"Alpha/{region}.lproj/L.strings": STRINGS for region in ["zu", "en", "fr", "af", "zh-Hans"]}}),
    # Two folders: the first in the group tree holds the region that sorts last.
    "regions-two-folders": ("P", TARGET, "T", [(ROOT_A, "Alpha"), (ROOT_B, "Beta")],
                            {"Alpha/zu.lproj/L.strings": STRINGS, "Beta/af.lproj/L.strings": STRINGS}),
    # A folder the target does not list.
    "regions-unlisted-folder": ("P", TARGET, "T", [(ROOT_A, "Alpha"), (ROOT_B, "Beta")],
                                {"Alpha/a01.swift": "let a01 = 1\n", "Beta/fr.lproj/L.strings": STRINGS}, {"target_roots": [ROOT_A]}),
    # Two localized files in one folder, each in one region: one variant group per file.
    "regions-two-files": ("P", TARGET, "T", [(ROOT_A, "Alpha")], {"Alpha/af.lproj/A.strings": STRINGS, "Alpha/zu.lproj/B.strings": STRINGS}),
    "regions-two-files-swapped": ("P", TARGET, "T", [(ROOT_A, "Alpha")], {"Alpha/zu.lproj/A.strings": STRINGS, "Alpha/af.lproj/B.strings": STRINGS}),
    # netnewswire's mul.lproj string catalogs add no region: the mul region, or a string catalog.
    "regions-mul": ("P", TARGET, "T", [(ROOT_A, "Alpha")], {"Alpha/mul.lproj/L.strings": STRINGS, "Alpha/de.lproj/L.strings": STRINGS}),
    "regions-xcstrings": ("P", TARGET, "T", [(ROOT_A, "Alpha")], {"Alpha/de.lproj/X.xcstrings": '{"sourceLanguage": "en", "strings": {}, "version": "1.0"}\n'}),
})

# Round 7: nextcloud's iOSClient/.tx/config, an executable text file without an extension, is
# `text` in Xcode's group tree. Each file here differs in its name or its first bytes, for the
# type Xcode gives a member whose extension no type claims.
INI = "[main]\nhost = https://www.transifex.com\n"
XML = '<?xml version="1.0" encoding="UTF-8"?>\n<a/>\n'
PLIST = ('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
         '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict/></plist>\n')


def control_file(length, count, offset=0):
    """`length` bytes of `a` with `count` 0x01 bytes from `offset`."""
    return b"a" * offset + b"\x01" * count + b"a" * (length - offset - count)


def mach_o_header(filetype, magic=0xFEEDFACF):
    return struct.pack("<IiiI", magic, 0x0100000C, 0, filetype) + bytes(16)


UNTYPED_CONTENTS = {
    "ini": INI, "ascii": "hello\n", "empty": b"", "utf8": "héllo wörld ✓\n",
    "utf8-bom": b"\xef\xbb\xbfhello\n", "utf16le-bom": "﻿hello\n".encode("utf-16-le"),
    "utf16be-bom": "﻿hello\n".encode("utf-16-be"), "utf16le-nobom": "hello\n".encode("utf-16-le"),
    "latin1": b"caf\xe9\n", "nul-2": b"ab\x00cd\n", "nul-1000": b"a" * 1000 + b"\x00\n",
    "nul-5000": b"a" * 5000 + b"\x00\n", "nul-70000": b"a" * 70000 + b"\x00\n",
    "ctrl-01": b"a\x01b\n", "ctrl-1b": b"a\x1bb\n", "ctrl-7f": b"a\x7fb\n", "formfeed": b"a\x0cb\n",
    "crlf": b"a\r\nb\r\n", "cr": b"a\rb\r", "long-line": "x = " + "a" * 500 + "\n",
    "binary": bytes(range(256)), "high-bytes": bytes(range(128, 256)),
    "bplist": b"bplist00" + bytes(32), "macho": b"\xcf\xfa\xed\xfe\x0c\x00\x00\x01" + bytes(56),
    "png": b"\x89PNG\r\n\x1a\n" + bytes(32), "pdf": "%PDF-1.4\n%%EOF\n", "zip": b"PK\x03\x04" + bytes(26),
    "xml": XML, "xml-indented": "  " + XML, "plist-xml": PLIST, "html": "<html><body></body></html>\n",
    "json": '{"a": 1}\n', "sh": "#!/bin/sh\necho hi\n", "env-bash": "#!/usr/bin/env bash\necho hi\n",
    "python": "#!/usr/bin/python\nprint(1)\n", "perl": "#!/usr/bin/perl\nprint 1;\n",
}
UNTYPED_FILES = {"Src/a.swift": "let a = 1\n", **{f"Src/{name}": contents for name, contents in UNTYPED_CONTENTS.items()}}
UNTYPED_FILES.update({f"Src/{name}.zzz": UNTYPED_CONTENTS[name] for name in
                      ["ascii", "empty", "utf8", "latin1", "nul-2", "binary", "bplist", "png", "macho", "sh", "xml", "json"]})
UNTYPED_FILES.update({
    "Src/known/ascii-xml.txt": XML, "Src/known/binary.txt": bytes(range(256)), "Src/known/sh.txt": "#!/bin/sh\n",
    "Src/known/binary.json": bytes(range(256)), "Src/known/trailing.": "hello\n",
    "Src/names/Makefile": "all:\n\ttrue\n", "Src/names/lower/makefile": "all:\n\ttrue\n", "Src/names/GNUmakefile": "all:\n",
    "Src/names/Podfile": "platform :ios\n", "Src/names/Gemfile": "source 'https://rubygems.org'\n",
    "Src/names/Fastfile": "lane :x do\nend\n", "Src/names/Dockerfile": "FROM x\n", "Src/names/LICENSE": "MIT\n",
    "Src/names/README": "read me\n", "Src/names/CODEOWNERS": "* @a\n", "Src/names/project.pbxproj": "// !$*UTF8*$!\n{}\n",
    "Src/names/Info.plist": PLIST, "Src/names/AppInfo.plist": PLIST, "Src/names/Info-Debug.plist": PLIST,
    "Src/names/AppIntents.vocabulary": PLIST,
})
# Which bytes count as binary, how far Xcode reads, Mach-O headers, and what wins over what.
UNTYPED_BYTES = {f"Src/ctrl/c{value:02x}": b"a" + bytes([value]) + b"b\n" for value in list(range(0, 32)) + [0x7F, 0x80, 0xFF]}
UNTYPED_BYTES.update({f"Src/window/nul-at-{offset:05d}": b"a" * offset + b"\x00\n"
                      for offset in [255, 256, 511, 512, 1023, 1024, 1025, 2047, 2048, 4095, 4096]})
UNTYPED_BYTES.update({f"Src/window/ctrl01-at-{offset:05d}": b"a" * offset + b"\x01\n" for offset in [1023, 1024]})
UNTYPED_BYTES.update({
    "Src/bom/utf16le-ctrl": b"\xff\xfe" + "a\x01b".encode("utf-16-le"), "Src/bom/utf16be-ctrl": b"\xfe\xff" + "a\x01b".encode("utf-16-be"),
    "Src/bom/utf8-ctrl": b"\xef\xbb\xbfa\x01b", "Src/bom/utf8-xml": b"\xef\xbb\xbf" + XML.encode(),
    "Src/bom/utf16le-xml": b"\xff\xfe" + XML.encode("utf-16-le"), "Src/bom/utf32le": "﻿hi".encode("utf-32-le"),
    "Src/bom/nul-first": b"\x00abc\n",
    "Src/macho/object": mach_o_header(1), "Src/macho/execute": mach_o_header(2), "Src/macho/dylib": mach_o_header(6),
    "Src/macho/bundle": mach_o_header(8), "Src/macho/thirty-two": mach_o_header(2, 0xFEEDFACE),
    "Src/macho/fat": struct.pack(">II", 0xCAFEBABE, 1) + bytes(24), "Src/macho/ar": b"!<arch>\n" + bytes(8),
    "Src/precedence/Makefile": b"bplist00" + bytes(8), "Src/precedence/sub/Makefile": XML,
    "Src/precedence/AppIntents.vocabulary": bytes(range(256)), "Src/precedence/sh-binary": b"#!/bin/sh\n\x00\x01",
    "Src/precedence/xml-binary": b"<?xml\x00\x01", "Src/precedence/bplist-text": "bplist00 hello\n",
})
# How many control bytes make a file binary: counted in the first 1,024 bytes.
UNTYPED_RATIOS = {f"Src/l0100/k{count:03d}": control_file(100, count) for count in range(1, 41)}
UNTYPED_RATIOS.update({f"Src/l0010/k{count:03d}": control_file(10, count) for count in range(1, 6)})
UNTYPED_RATIOS.update({f"Src/l0020/k{count:03d}": control_file(20, count) for count in range(1, 9)})
UNTYPED_RATIOS.update({f"Src/l1024/k{count:04d}": control_file(1024, count) for count in
                       [10, 50, 100, 101, 102, 103, 104, 150, 200, 204, 205, 206, 300, 340, 341, 342, 343, 400, 512]})
UNTYPED_RATIOS.update({f"Src/l4096/k{count:04d}": control_file(4096, count) for count in [102, 103, 205, 206, 341, 342, 410, 411, 1024]})
UNTYPED_RATIOS.update({"Src/late/l2048-k1024-at1024": control_file(2048, 1024, 1024), "Src/late/l2048-k512-at512": control_file(2048, 512, 512)})
UNTYPED_RATIOS.update({f"Src/pos/l1025-at{offset:04d}": control_file(1025, 1, offset) for offset in [1, 2, 10, 100, 500, 1000]})
UNTYPED_RATIOS.update({f"Src/macho/filetype{filetype:02d}": mach_o_header(filetype) for filetype in [3, 4, 5, 7, 9, 10, 11, 12]})
EXPERIMENTS.update({
    "untyped-files": ("P", TARGET, "T", [(ROOT_A, "Src")], UNTYPED_FILES),
    # nextcloud's own case: the same text, executable or not, in a folder named `.tx`.
    "untyped-dot-folder": ("P", TARGET, "T", [(ROOT_A, ".tx")], {".tx/config": INI, ".tx/config-plain": INI},
                           {"executable": [".tx/config"]}),
    "untyped-executable": ("P", TARGET, "T", [(ROOT_A, "Src")],
                           {"Src/a.swift": "let a = 1\n", **{f"Src/{n}": UNTYPED_CONTENTS[n] for n in ["ini", "empty", "binary", "ascii"]}},
                           {"executable": ["Src/ini", "Src/empty", "Src/binary", "Src/ascii"]}),
    "untyped-bytes": ("P", TARGET, "T", [(ROOT_A, "Src")], {"Src/a.swift": "let a = 1\n", **UNTYPED_BYTES}),
    "untyped-ratios": ("P", TARGET, "T", [(ROOT_A, "Src")], {"Src/a.swift": "let a = 1\n", **UNTYPED_RATIOS}),
    # Mach-O objects, dylibs and archives join Frameworks, with or without an extension.
    "untyped-frameworks": ("P", TARGET, "T", [(ROOT_A, "Src")], {
        "Src/a.swift": "let a = 1\n", "Src/object": mach_o_header(1), "Src/object.o": mach_o_header(1), "Src/dylib": mach_o_header(6),
        "Src/execute": mach_o_header(2), "Src/bundle": mach_o_header(8), "Src/ar": b"!<arch>\n" + bytes(8), "Src/text": "hello\n"},
        {"frameworks_phase": True}),
    # Paths an exception set names that are not on disk.
    "untyped-missing": ("P", TARGET, "T", [(ROOT_A, "Alpha")], {"Alpha/a01.swift": "let a01 = 1\n"},
                        {"exceptions": {ROOT_A: ["gone", "gone.zzz", "Makefile", "gone.txt"]}}),
    # Folders whose extension no folder type claims, and plain files named like folders.
    "untyped-folders": ("P", TARGET, "T", [(ROOT_A, "Src")], {
        "Src/a.swift": "let a = 1\n", **{f"Src/X.{extension}/inner.swift": "let i = 1\n" for extension in ["zzz", "swift", "a", "mlmodelc", "plist", "txt"]},
        **{f"Src/P.{extension}": "x\n" for extension in ["framework", "bundle", "xcassets", "xcdatamodel", "app", "docc", "mlmodelc"]}}),
    "untyped-folders-2": ("P", TARGET, "T", [(ROOT_A, "Src")], {
        "Src/a.swift": "let a = 1\n", **{f"Src/X.{extension}/inner.swift": "let i = 1\n" for extension in [
            "png", "o", "zip", "mp3", "json", "xib", "storyboard", "pdf", "mlmodel", "dylib", "tbd", "xcdatamodeld", "xcmappingmodel",
            "md", "h", "c", "strings", "ttf", "caf", "html", "xcconfig", "entitlements", "sh", "jar", "tar", "gz", "pbxproj",
            "intentdefinition", "usdz", "reality", "metal", "rcproject", "pages", "key", "plugin", "kext", "rtfd", "photoslibrary",
            "bplist", "xcstrings", "mov", "scn", "sks", "car", "nib", "lib", "exe", "dll", "so", "jpg", "heic", "svg"]},
        **{f"Src/P.{extension}": "x\n" for extension in ["rkassets", "storyboardc", "xcmappingmodel", "xcdatamodeld", "scnassets", "rtfd",
                                                       "kext", "xcframework", "appex", "playground", "icon", "iconset", "nib", "pkg"]}}),
    # Extensions two types claim (o, ll, appex): files with and without a Mach-O header, and folders.
    "untyped-duplicates": ("P", TARGET, "T", [(ROOT_A, "Src")], {
        "Src/a.swift": "let a = 1\n", "Src/text.o": "x\n", "Src/object.o": mach_o_header(1), "Src/dylib.o": mach_o_header(6),
        "Src/x.ll": "x\n", "Src/Y.ll/inner.swift": "let i = 1\n", "Src/Y.appex/inner.swift": "let i = 1\n"}),
    # Which claimed extensions a Mach-O header or an archive header overrides.
    "untyped-macho": ("P", TARGET, "T", [(ROOT_A, "Src")], {
        "Src/a.swift": "let a = 1\n", **{f"Src/object.{extension}": mach_o_header(1) for extension in
                                         ["png", "swift", "txt", "dylib", "a", "json", "bundle", "framework", "tbd", "zzz"]},
        "Src/dylib.dylib": mach_o_header(6), "Src/bundle.dylib": mach_o_header(8), "Src/execute.a": mach_o_header(2),
        "Src/archive.o": b"!<arch>\n" + bytes(8), "Src/archive.dylib": b"!<arch>\n" + bytes(8), "Src/text.dylib": "x\n",
        "Src/text.a": "x\n", "Src/bplist.o": b"bplist00" + bytes(8), "Src/sh.o": "#!/bin/sh\n"}, {"frameworks_phase": True}),
})

# Round 8: in nextcloud's triage, a synchronized variant group listed Base before the development
# region. The order of each variant group's children, with and without Base, `mul` or the
# development region, and with another development region.
STORYBOARD = '<?xml version="1.0" encoding="UTF-8"?>\n<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0"/>\n'
VARIANT_FILES = {
    "Alpha/a01.swift": "let a01 = 1\n",
    **{f"Alpha/{region}.lproj/Main.{'storyboard' if region == 'Base' else 'strings'}": STORYBOARD if region == "Base" else STRINGS
       for region in ["Base", "en", "ar", "fr", "zu", "af"]},
    **{f"Alpha/{region}.lproj/L.strings": STRINGS for region in ["Base", "en", "ab", "zu", "mul"]},
    **{f"Alpha/{region}.lproj/N.strings": STRINGS for region in ["zu", "en", "ab"]},
    **{f"Alpha/{region}.lproj/B.strings": STRINGS for region in ["zu", "Base", "ab"]},
    **{f"Alpha/{region}.lproj/M.strings": STRINGS for region in ["mul", "Base", "en"]},
    **{f"Alpha/{region}.lproj/R.strings": STRINGS for region in ["fr", "de", "ab", "en-GB", "Base", "en"]},
}
EXPERIMENTS.update({
    "variants-order": ("P", TARGET, "T", [(ROOT_A, "Alpha")], VARIANT_FILES),
    "variants-order-fr": ("P", TARGET, "T", [(ROOT_A, "Alpha")], VARIANT_FILES,
                          {"development_region": "fr", "known_regions": ["fr", "en", "Base"]}),
})

# Round 9: in nextcloud's triage, Xcode set LIBRARY_SEARCH_PATHS = "$(inherited) $(PROJECT_DIR)/Src"
# in both target configurations of a target whose synchronized folder holds libraries. Which
# members add a search path, which path, in which order, and next to a setting the target has.
ARCHIVE = b"!<arch>\n" + bytes(8)
TBD = "--- !tapi-tbd\ntbd-version: 4\ntargets: [ arm64-ios ]\ninstall-name: /usr/lib/libD.dylib\n...\n"
FRAMEWORK_PLIST = PLIST.replace("<dict/>", "<dict><key>CFBundlePackageType</key><string>FMWK</string></dict>")
LIBRARY_BASE = {"Src/a.swift": "let a = 1\n"}
EXPERIMENTS.update({
    "libraries-archive": ("P", TARGET, "T", [(ROOT_A, "Src")], {**LIBRARY_BASE, "Src/libA.a": ARCHIVE}, {"frameworks_phase": True}),
    "libraries-dylib": ("P", TARGET, "T", [(ROOT_A, "Src")], {**LIBRARY_BASE, "Src/libB.dylib": mach_o_header(6)}, {"frameworks_phase": True}),
    "libraries-object": ("P", TARGET, "T", [(ROOT_A, "Src")], {**LIBRARY_BASE, "Src/c.o": mach_o_header(1)}, {"frameworks_phase": True}),
    "libraries-tbd": ("P", TARGET, "T", [(ROOT_A, "Src")], {**LIBRARY_BASE, "Src/libD.tbd": TBD}, {"frameworks_phase": True}),
    "libraries-framework": ("P", TARGET, "T", [(ROOT_A, "Src")],
                            {**LIBRARY_BASE, "Src/E.framework/E": mach_o_header(6), "Src/E.framework/Info.plist": FRAMEWORK_PLIST},
                            {"frameworks_phase": True}),
    "libraries-xcframework": ("P", TARGET, "T", [(ROOT_A, "Src")], {**LIBRARY_BASE, "Src/F.xcframework/Info.plist": PLIST},
                              {"frameworks_phase": True}),
    # Without a Frameworks phase the libraries join no phase.
    "libraries-no-phase": ("P", TARGET, "T", [(ROOT_A, "Src")], {**LIBRARY_BASE, "Src/libA.a": ARCHIVE}),
    # Libraries in subfolders, several in one folder, in two folders, in a folder whose path has a
    # slash or a space.
    "libraries-nested": ("P", TARGET, "T", [(ROOT_A, "Src")], {
        **LIBRARY_BASE, "Src/zeta/libZ.a": ARCHIVE, "Src/sub/deeper/libB.a": ARCHIVE, "Src/sub/libC.dylib": mach_o_header(6),
        "Src/libA.a": ARCHIVE, "Src/libA2.a": ARCHIVE}, {"frameworks_phase": True}),
    "libraries-two-folders": ("P", TARGET, "T", [(ROOT_A, "Alpha"), (ROOT_B, "Beta")], {
        "Alpha/a.swift": "let a = 1\n", "Alpha/libA.a": ARCHIVE, "Beta/libB.a": ARCHIVE}, {"frameworks_phase": True}),
    "libraries-folder-paths": ("P", TARGET, "T", [(ROOT_A, "Outer/Libs"), (ROOT_B, "My Libs")], {
        "Outer/Libs/a.swift": "let a = 1\n", "Outer/Libs/libA.a": ARCHIVE, "My Libs/libB.a": ARCHIVE}, {"frameworks_phase": True}),
    # A library the target's exception set removes, and one a folder the target does not list adds.
    "libraries-excluded": ("P", TARGET, "T", [(ROOT_A, "Src")], {**LIBRARY_BASE, "Src/libA.a": ARCHIVE},
                           {"frameworks_phase": True, "exceptions": {ROOT_A: ["libA.a"]}}),
    "libraries-unlisted-folder": ("P", TARGET, "T", [(ROOT_A, "Alpha"), (ROOT_B, "Beta")], {
        "Alpha/a.swift": "let a = 1\n", "Beta/libB.a": ARCHIVE, "Beta/libC.a": ARCHIVE},
        {"frameworks_phase": True, "target_roots": [ROOT_A], "exceptions": {ROOT_B: ["libB.a"]}}),
    # The target sets LIBRARY_SEARCH_PATHS itself, in Debug only.
    "libraries-existing-setting": ("P", TARGET, "T", [(ROOT_A, "Src")], {**LIBRARY_BASE, "Src/libA.a": ARCHIVE},
                                   {"frameworks_phase": True, "settings": {"Debug": {"LIBRARY_SEARCH_PATHS": '"/opt/lib"'}}}),
    # The target already names the folder, as a list in Debug and a string in Release.
    "libraries-setting-names-folder": ("P", TARGET, "T", [(ROOT_A, "Src")], {**LIBRARY_BASE, "Src/libA.a": ARCHIVE},
                                       {"frameworks_phase": True, "settings": {
                                           "Debug": {"LIBRARY_SEARCH_PATHS": '(\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"$(PROJECT_DIR)/Src",\n\t\t\t\t)'},
                                           "Release": {"LIBRARY_SEARCH_PATHS": '"$(PROJECT_DIR)/Src"'}}}),
    # A framework and a library in subfolders, and a folder outside the project's folder.
    "libraries-framework-and-library": ("P", TARGET, "T", [(ROOT_A, "Src")], {
        **LIBRARY_BASE, "Src/sub/E.framework/E": mach_o_header(6), "Src/sub/E.framework/Info.plist": FRAMEWORK_PLIST,
        "Src/lib/libA.a": ARCHIVE}, {"frameworks_phase": True}),
    "libraries-outside": ("P", TARGET, "T", [(ROOT_A, "Src"), (ROOT_B, "../libraries-outside-Libs")], {
        **LIBRARY_BASE, "../libraries-outside-Libs/libA.a": ARCHIVE}, {"frameworks_phase": True}),
    "libraries-elsewhere": ("P", TARGET, "T", [(ROOT_A, "Src"), (ROOT_B, "../zz-elsewhere/Libs")], {
        **LIBRARY_BASE, "../zz-elsewhere/Libs/libA.a": ARCHIVE}, {"frameworks_phase": True}),
    # Whether the file type or the name decides: one member each, typed by its contents.
    **{f"libraries-member-{name.replace('.', '-')}": ("P", TARGET, "T", [(ROOT_A, "Src")], {**LIBRARY_BASE, f"Src/{name}": contents},
                                                      {"frameworks_phase": True})
       for name, contents in [("object.framework", mach_o_header(1)), ("object.bundle", mach_o_header(1)), ("object.zzz", mach_o_header(1)),
                              ("text.framework", "x\n"), ("object.dylib", mach_o_header(1)), ("archive.o", ARCHIVE),
                              ("dylib", mach_o_header(6)), ("archive", ARCHIVE)]},
})

# Types a synchronized folder's explicitFileTypes gives its items: unknown ones, `file`, and a
# known type on another extension.
EXPERIMENTS.update({
    "explicit-types": ("P", TARGET, "T", [(ROOT_A, "Src")], {
        "Src/a.swift": "let a = 1\n", "Src/unknown.swift": "let u = 1\n", "Src/file.swift": "let f = 1\n",
        "Src/static.swift": "let s = 1\n", "Src/known.zzz": "let k = 1\n", "Src/Unknown.mlmodelc": "x\n"},
        {"explicit_types": {ROOT_A: {"unknown.swift": "nomac.unknown", "file.swift": "file", "static.swift": "wrapper.framework.static",
                                     "known.zzz": "sourcecode.swift", "Unknown.mlmodelc": "wrapper.mlmodelc"}}}),
})

# Round 10: what the synchronized-folder rounds above left open. In loader-experiments
# codegen-members, a variant group of a Base intent definition and an en string table has a second
# Resources build file for its Base variant; synchronized-headers and untyped-folders-2 list `X.h`
# before the other names of its stem; the differential fuzzer saw dot files in Xcode's group tree.
BASE_VARIANTS = {"Src/a.swift": "let a = 1\n"}
for stem, base, sibling in [("I", "intentdefinition", "strings"), ("S", "storyboard", "strings"), ("X", "xib", "strings"),
                            ("L", "strings", "strings"), ("W", "swift", "swift"), ("M", "mlmodel", "strings"), ("J", "json", "json"),
                            ("H", "h", "strings"), ("O", "m", "strings"), ("N", "mlpackage", "strings"), ("A", "intentdefinition", None),
                            ("T", "txt", None)]:
    BASE_VARIANTS[f"Src/Base.lproj/{stem}.{base}" + ("/x" if base == "mlpackage" else "")] = PLIST if base != "swift" else "let w = 1\n"
    if sibling:
        BASE_VARIANTS[f"Src/en.lproj/{stem}.{sibling}"] = STRINGS if sibling == "strings" else PLIST
BASE_VARIANTS.update({"Src/en.lproj/E.intentdefinition": PLIST, "Src/fr.lproj/E.strings": STRINGS,
                      "Src/fr.lproj/F.intentdefinition": PLIST, "Src/de.lproj/F.strings": STRINGS})
SAME_STEM = {"Src/a.swift": "let a = 1\n",
             **{f"Src/X.{extension}": "x\n" for extension in ["h", "c", "m", "a", "hpp", "hh", "hxx", "h++", "pch", "ipp", "inl", "tpp", "hp",
                                                             "swift", "txt", "png", "bplist", "mm", "cpp", "modulemap", "def", "g"]},
             **{f"Src/{name}": "x\n" for name in ["Y-1.c", "Y.c", "Y.h", "Y_1.c", "Y 1.c", "Ya.c", "Y.m", "Z.c", "Z.H2", "Zh.c", "Z.hh", "b.c",
                                                 "B.h", "K.H", "k.c", "V.c.h", "V.c", "V.h.c", "Q.h.txt", "Q.c.txt"]},
             **{f"Src/{name}/inner.swift": "let i = 1\n" for name in ["G.c", "G.h", "G.hpp", "G.a"]}, "Src/G.h.m": "x\n"}
DOT_FILES = {"Src/a.swift": "let a = 1\n", "Src/.gitkeep": "", "Src/.hidden.swift": "let h = 1\n", "Src/.DS_Store": bytes(16),
             "Src/.git/HEAD": "ref: refs/heads/main\n", "Src/.hiddendir/inner.swift": "let i = 1\n", "Src/sub/.keep": "",
             "Src/.env": "A=1\n", "Src/..double": "x\n", "Src/en.lproj/.hidden.strings": STRINGS, "Src/en.lproj/V.strings": STRINGS,
             "Src/.lproj/W.strings": STRINGS, "Src/.svn/entries": "x\n", "Src/.xcassets/Contents.json": "{}\n", "Src/sub/.DS_Store": bytes(16)}
EXPERIMENTS.update({
    "base-variants": ("P", TARGET, "T", [(ROOT_A, "Src")], BASE_VARIANTS),
    "same-stem": ("P", TARGET, "T", [(ROOT_A, "Src")], SAME_STEM),
    "dot-files": ("P", TARGET, "T", [(ROOT_A, "Src")], DOT_FILES),
    # Regions that differ from knownRegions, or from each other, in case (APFS is case-insensitive,
    # so each spelling is in its own folder).
    "regions-case-sync": ("P", TARGET, "T", [(ROOT_A, "Alpha"), (ROOT_B, "Beta")], {
        "Alpha/a.swift": "let a = 1\n", "Alpha/IT.lproj/S.strings": STRINGS, "Alpha/De.lproj/T.strings": STRINGS,
        "Alpha/EN.lproj/U.strings": STRINGS, "Alpha/BASE.lproj/V.strings": STRINGS, "Alpha/MUL.lproj/W.strings": STRINGS,
        "Alpha/PT-BR.lproj/Q.strings": STRINGS, "Beta/de.lproj/T.strings": STRINGS, "Beta/it.lproj/S.strings": STRINGS,
        "Beta/pt-br.lproj/P.strings": STRINGS}, {"known_regions": ["en", "Base", "it"]}),
})

# Round 11: the edges round 10 left. Which Base types string tables join (`.stringsdict`,
# `.xcstrings`, Base string tables), which types get a second build file (metal libraries share
# intent definitions' fallback phase), two intent-definition variants; which header extensions
# sort first in other cases; which other dot names are left out.
BASE_VARIANTS_2 = {"Src/a.swift": "let a = 1\n"}
for stem, variants in {"K": [("Base", "metallib"), ("en", "strings")], "D": [("Base", "intentdefinition"), ("en", "intentdefinition"), ("fr", "strings")],
                       "P": [("Base", "json"), ("en", "strings")], "Q": [("Base", "txt"), ("en", "strings")],
                       "R": [("Base", "nib"), ("en", "strings")], "U": [("Base", "storyboard"), ("en", "stringsdict"), ("fr", "xcstrings")],
                       "V": [("Base", "png"), ("en", "strings")], "Y": [("Base", "plist"), ("en", "strings")],
                       "B2": [("Base", "strings"), ("en", "stringsdict")], "C2": [("Base", "xib"), ("en", "xib"), ("fr", "strings")],
                       "E2": [("Base", "strings"), ("en", "storyboard")], "F2": [("Base", "storyboard"), ("Base", "strings"), ("en", "strings")],
                       "G2": [("de", "xib"), ("en", "strings")], "H2": [("en", "storyboard"), ("fr", "strings")]}.items():
    for region, extension in variants:
        BASE_VARIANTS_2[f"Src/{region}.lproj/{stem}.{extension}"] = STRINGS if extension in ("strings", "stringsdict") else PLIST
SAME_STEM_2 = {"Src/a.swift": "let a = 1\n", **{f"Src/{name}": "x\n" for name in [
    "U.H", "U.c", "U2.HPP", "U2.c", "U3.pch++", "U3.c", "U4.Hh", "U4.c", "N2.c", "N10.h", "N10.c", "N2.h", "w.c", "W.h", "M.h.h", "M.h"]}}
DOT_FILES_2 = {"Src/a.swift": "let a = 1\n", **{f"Src/{name}": "x\n" for name in [
    ".hg/x", "CVS/x", ".bzr/x", "_darcs/x", ".Trashes/x", ".localized", ".fseventsd/x", ".Spotlight-V100/x", ".TemporaryItems/x",
    ".idea/x", ".vscode/x", ".swiftpm/x", ".build/x", ".gitignore", ".gitattributes", "sub/.git", "deep/.svn", ".DS_Store.txt",
    "a.swift~", ".#lock", ".AppleDouble/x", "._a.swift", "xcuserdata/x", "Thumbs.db", ".gitmodules", ".git-blame-ignore-revs"]}}
# The order and identity of the second build files when several variants are intent definitions or
# metal libraries: with Base, with the development region only, with neither.
BASE_VARIANTS_3 = {"Src/a.swift": "let a = 1\n",
                   **{f"Src/{region}.lproj/T3.intentdefinition": PLIST for region in ["Base", "en", "fr", "de"]},
                   **{f"Src/{region}.lproj/T4.intentdefinition": PLIST for region in ["fr", "en"]},
                   **{f"Src/{region}.lproj/T5.intentdefinition": PLIST for region in ["fr", "de"]},
                   **{f"Src/{region}.lproj/T6.metallib": PLIST for region in ["de", "Base"]}}
EXPERIMENTS.update({
    "base-variants-2": ("P", TARGET, "T", [(ROOT_A, "Src")], BASE_VARIANTS_2),
    "base-variants-3": ("P", TARGET, "T", [(ROOT_A, "Src")], BASE_VARIANTS_3),
    "same-stem-2": ("P", TARGET, "T", [(ROOT_A, "Src")], SAME_STEM_2),
    "dot-files-2": ("P", TARGET, "T", [(ROOT_A, "Src")], DOT_FILES_2),
})

FRAMEWORKS_PHASE = """		F00000000000000000000009 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
"""


def quoted(text):
    """`text` as a project-file string, quoted when it needs to be."""
    return text if re.fullmatch(r"[A-Za-z0-9_./]+", text) else '"' + text + '"'


# Round 7 (BACKLOG B-016): firefox's ActionExtension folder holds InfoPlist.strings in 67 regions,
# neither its development region en-US nor Base among them; Xcode gives that variant group, and
# its Resources build file, a hex GUID. Each experiment differs from hexguid-base in one input;
# hexguid-copy is hexguid-base in another folder, and hexguid-en a control with the development
# region.
HEX_FILES = {"Alpha/fr.lproj/L.strings": STRINGS, "Alpha/de.lproj/L.strings": STRINGS}
EXPERIMENTS.update({
    "hexguid-base": ("P", TARGET, "T", [(ROOT_A, "Alpha")], HEX_FILES),
    "hexguid-copy": ("P", TARGET, "T", [(ROOT_A, "Alpha")], HEX_FILES),
    "hexguid-en": ("P", TARGET, "T", [(ROOT_A, "Alpha")], {**HEX_FILES, "Alpha/en.lproj/L.strings": STRINGS}),
    "hexguid-root-id": ("P", TARGET, "T", [("A00000000000000000000009", "Alpha")], HEX_FILES),
    "hexguid-folder": ("P", TARGET, "T", [(ROOT_A, "Beta")], {path.replace("Alpha", "Beta"): text for path, text in HEX_FILES.items()}),
    "hexguid-file-name": ("P", TARGET, "T", [(ROOT_A, "Alpha")], {path.replace("L.", "M."): text for path, text in HEX_FILES.items()}),
    "hexguid-file-type": ("P", TARGET, "T", [(ROOT_A, "Alpha")], {path.replace("L.strings", "L.json"): "{}\n" for path in HEX_FILES}),
    "hexguid-contents": ("P", TARGET, "T", [(ROOT_A, "Alpha")], {path: '"other" = "value";\n' for path in HEX_FILES}),
    "hexguid-one-region": ("P", TARGET, "T", [(ROOT_A, "Alpha")], {"Alpha/fr.lproj/L.strings": STRINGS}),
    "hexguid-other-regions": ("P", TARGET, "T", [(ROOT_A, "Alpha")], {"Alpha/it.lproj/L.strings": STRINGS, "Alpha/ja.lproj/L.strings": STRINGS}),
    "hexguid-subfolder": ("P", TARGET, "T", [(ROOT_A, "Alpha")], {path.replace("Alpha/", "Alpha/sub/"): text for path, text in HEX_FILES.items()}),
    "hexguid-two-groups": ("P", TARGET, "T", [(ROOT_A, "Alpha")], {**HEX_FILES, **{path.replace("L.", "M."): text for path, text in HEX_FILES.items()}}),
    "hexguid-other-file": ("P", TARGET, "T", [(ROOT_A, "Alpha")], {**HEX_FILES, "Alpha/a.swift": "let a = 1\n"}),
    "hexguid-project-name": ("Q", TARGET, "T", [(ROOT_A, "Alpha")], HEX_FILES),
    "hexguid-target": ("P", "C00000000000000000000009", "U", [(ROOT_A, "Alpha")], HEX_FILES),
    "hexguid-unlisted": ("P", TARGET, "T", [(ROOT_A, "Alpha")], HEX_FILES, {"target_roots": []}),
    "hexguid-two-roots": ("P", TARGET, "T", [(ROOT_A, "Alpha"), (ROOT_B, "Beta")],
                          {**HEX_FILES, **{path.replace("Alpha", "Beta"): text for path, text in HEX_FILES.items()}}),
})

def write_project(directory, name, target_id, target, roots, files, options=None):
    """Writes the project. `options` may hold `target_roots` (the object IDs the target lists,
    when not all roots in group-tree order), `exceptions` ({root ID: paths the root's exception
    set names for the target}), `own_sources` (file names the Sources phase holds itself),
    `executable` (paths made executable), `frameworks_phase` (the target gets an empty
    Frameworks phase), `settings` ({configuration name: more settings of the target's
    configuration}), `explicit_types` ({root ID: the root's explicitFileTypes}),
    `development_region` and `known_regions`. File contents are text or bytes."""
    options = options or {}
    directory.mkdir(parents=True)
    for relative, contents in files.items():
        path = directory / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(contents, bytes):
            path.write_bytes(contents)
        else:
            path.write_text(contents)
    for relative in options.get("executable", []):
        (directory / relative).chmod(0o755)
    for _, folder in roots:
        (directory / folder).mkdir(parents=True, exist_ok=True)
    exceptions = options.get("exceptions", {})
    extra = ""
    root_objects = ""
    explicit_types = options.get("explicit_types", {})
    for index, (oid, folder) in enumerate(roots, 1):
        exception = ""
        if oid in explicit_types:
            types = "".join(f"\t\t\t\t{quoted(path)} = {file_type};\n" for path, file_type in explicit_types[oid].items())
            exception += f"\t\t\texplicitFileTypes = {{\n{types}\t\t\t}};\n"
        if oid in exceptions:
            set_id = f"E{index:023d}"
            exception += f"\t\t\texceptions = (\n\t\t\t\t{set_id},\n\t\t\t);\n"
            paths = "".join(f"\t\t\t\t{path},\n" for path in exceptions[oid])
            extra += (f"\t\t{set_id} = {{\n\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;\n"
                      f"\t\t\tmembershipExceptions = (\n{paths}\t\t\t);\n\t\t\ttarget = {target_id};\n\t\t}};\n")
        root_objects += (f"\t\t{oid} /* {folder} */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n{exception}"
                         f"\t\t\tpath = {quoted(folder)};\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
    own_refs, own_build_files = "", ""
    for index, file_name in enumerate(options.get("own_sources", []), 1):
        reference, build_file = f"O{index:023d}", f"Q{index:023d}"
        (directory / file_name).write_text(f"let own{index} = 1\n")
        extra += (f"\t\t{reference} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {file_name}; sourceTree = \"<group>\"; }};\n"
                  f"\t\t{build_file} = {{isa = PBXBuildFile; fileRef = {reference}; }};\n")
        own_refs += f"\t\t\t\t{reference},\n"
        own_build_files += f"\t\t\t\t{build_file},\n"
    references = "".join(f"\t\t\t\t{oid} /* {folder} */,\n" for oid, folder in roots)
    folders = dict(roots)
    target_roots = "".join(f"\t\t\t\t{oid} /* {folders[oid]} */,\n" for oid in options.get("target_roots", [oid for oid, _ in roots]))
    project = directory / f"{name}.xcodeproj"
    project.mkdir()
    (project / "project.pbxproj").write_text(PROJECT_TEMPLATE.format(
        name=name, target=target, target_id=target_id, roots=root_objects.rstrip("\n"),
        root_refs=references, target_roots=target_roots, extra_objects=extra, own_refs=own_refs, own_build_files=own_build_files,
        frameworks_ref="\t\t\t\tF00000000000000000000009 /* Frameworks */,\n" if options.get("frameworks_phase") else "",
        frameworks_phase=FRAMEWORKS_PHASE if options.get("frameworks_phase") else "",
        debug_settings="".join(f"\t\t\t\t{key} = {value};\n" for key, value in options.get("settings", {}).get("Debug", {}).items()),
        release_settings="".join(f"\t\t\t\t{key} = {value};\n" for key, value in options.get("settings", {}).get("Release", {}).items()),
        development_region=options.get("development_region", "en"),
        known_regions="".join(f"\t\t\t\t{region},\n" for region in options.get("known_regions", ["en", "Base"]))))
    return project


def observe(pif_path, project_name):
    objects = json.loads(Path(pif_path).read_text())
    project = next(o["contents"] for o in objects if o["type"] == "project")
    nodes, labels = [], {}

    def walk(node, prefix):
        for child in node.get("children", []) or []:
            path = prefix + "/" + (child.get("path") or "")
            labels[child["guid"]] = path
            nodes.append({"path": path, "type": child["type"], "guid": child["guid"],
                          "fileType": child.get("fileType")})
            walk(child, path)

    walk(project["groupTree"], "")
    phases = []
    for obj in objects:
        if obj["type"] != "target":
            continue
        for phase in obj["contents"].get("buildPhases", []):
            phases.append({"target": obj["contents"]["name"], "targetGUID": obj["contents"]["guid"],
                           "phase": phase["type"], "phaseGUID": phase["guid"],
                           "files": [{"path": labels.get(f.get("fileReference"), f.get("fileReference")),
                                      "guid": f["guid"], "fileReference": f.get("fileReference")}
                                     for f in phase.get("buildFiles", [])]})
    settings = {obj["contents"]["name"]: {c["name"]: c["buildSettings"] for c in obj["contents"]["buildConfigurations"]}
                for obj in objects if obj["type"] == "target"}
    return {"projectGUID": project["guid"], "groupTreeGUID": project["groupTree"]["guid"],
            "knownRegions": project.get("knownRegions"), "nodes": nodes, "phases": phases, "targetSettings": settings}


def main():
    out = Path(sys.argv[1]).resolve()
    selected = sys.argv[2:] or list(EXPERIMENTS)
    if not sys.argv[2:] and out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True, exist_ok=True)
    work = Path("/tmp/nomac-pif-experiments")
    recorded = out / "observations.json"
    observations = json.loads(recorded.read_text()) if recorded.exists() else {}
    for name in selected:
        project_name, target_id, target, roots, files, *options = EXPERIMENTS[name]
        shutil.rmtree(work / name, ignore_errors=True)
        project = write_project(work / name, project_name, target_id, target, roots, files, *options)
        pif = out / f"{name}.pif"
        proc = subprocess.run(["xcodebuild", "-dumpPIF", str(pif), "-project", str(project)],
                              cwd=project.parent, capture_output=True, text=True)
        if proc.returncode != 0:
            observations[name] = {"error": proc.stderr[-2000:]}
            print(f"[{name}] xcodebuild failed:\n{proc.stderr[-2000:]}", flush=True)
            continue
        observations[name] = observe(pif, project_name)
        print(f"[{name}] " + json.dumps({n["path"]: n["guid"] for n in observations[name]["nodes"]}), flush=True)
        for phase in observations[name]["phases"]:
            if phase["files"]:
                print(f"    {phase['phase']}: " + ", ".join(f["path"] for f in phase["files"]), flush=True)
    recorded.write_text(json.dumps(observations, indent=2) + "\n")


if __name__ == "__main__":
    main()
