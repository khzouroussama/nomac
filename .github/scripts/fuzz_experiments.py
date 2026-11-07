#!/usr/bin/env python3
"""Differential fuzzing of nomac's loader against Xcode.

Runs on a Mac with Xcode 27.0 at /Applications/Xcode_27.app (docs/VERIFICATION.md "Without
CI"). Each case is a project written here from a seed: groups and synchronized folders with
odd names and many file types, targets of most product types with their dependencies, build
phases and rules, configurations, xcconfig files, conditional and macro settings, shared, user
and autocreated schemes, test plans, workspaces of several projects, project references and
local Swift packages. For each case:

  1. xcodebuild writes `-dumpPIF`, `-list` (text and `-json`) and `-showBuildSettings` (text and
     `-json`, for a sample of targets and schemes) in capture_reference.py's reference layout;
  2. `nomac verify` compares nomac with that reference, and `nomac list` with the `-list` text;
  3. every difference gets a class: the first differing PIF path, `-list` entry or setting. A
     case whose only differences `nomac verify` reports as equivalent (outputs xcodebuild itself
     changes from one run to the next) counts as equivalent, not different.

Classes are ranked in FINDINGS.md with their smallest case, minimized by removing parts of the
generator's output (projects, targets, files, settings, ...) while the class still shows.
Hypotheses written in `<output>/hypotheses.json` (class key -> text) are added to FINDINGS.md.
Generated projects and Xcode's outputs stay under the output directory, never in the
repository; passing cases keep only their spec and result.

Usage:
  fuzz_experiments.py run [--out DIR] [--cases N] [--start S] [--focus F,...] [--jobs 4]
                          [--nomac PATH] [--no-minimize] [--budget N] [--max-classes N] [--keep]
  fuzz_experiments.py case SEED [--focus F,...] [--out DIR] [--nomac PATH]
  fuzz_experiments.py minimize [--out DIR] [--jobs 4] [--budget N] [--max-classes N]
  fuzz_experiments.py findings [--out DIR]

Features for --focus: see FEATURES.
"""

import argparse
import collections
import concurrent.futures
import difflib
import hashlib
import html
import importlib.util
import json
import os
import plistlib
import pwd
import random
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
import unicodedata
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEVELOPER_DIR = os.environ.get("DEVELOPER_DIR", "/Applications/Xcode_27.app/Contents/Developer")
DEFAULT_OUT = Path.home() / "nomac-out" / "fuzz"
DEFAULT_NOMAC = Path.home() / "nomac-out" / "bin" / "wip1" / "nomac"
DERIVED_DATA = Path.home() / "Library" / "Developer" / "Xcode" / "DerivedData"
MIN_FREE_BYTES = 4 * 1024 ** 3
BUDGET_BYTES = 1024 ** 3
COMMAND_TIMEOUT = 600


def load_capture_module():
    spec = importlib.util.spec_from_file_location("capture_reference", REPO_ROOT / "corpus" / "scripts" / "capture_reference.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


capture = load_capture_module()

# ---------------------------------------------------------------------------------------------
# Generator: a seed gives a spec, a JSON tree of plain choices that render() writes to disk.
# References between parts are by spec ID, so removing any part leaves a renderable spec.

FEATURES = {
    "workspace": 0.2, "packages": 0.2, "cross-project": 0.08, "sync": 0.45, "sync-exceptions": 0.5,
    "sync-phase-exceptions": 0.05, "odd-names": 0.35, "file-types": 0.5, "missing-files": 0.2,
    "localization": 0.3, "frameworks": 0.4, "tests": 0.5, "extensions": 0.3, "watch": 0.1, "macos": 0.12,
    "phases": 0.4, "rules": 0.12, "configs": 0.3, "xcconfig": 0.35, "conditional": 0.35, "macros": 0.3,
    "schemes": 0.45, "user-schemes": 0.15, "test-plans": 0.25, "legacy-format": 0.25, "aggregate": 0.1,
    "untyped-files": 0.15,
    # Shapes of the survey's real projects (~/nomac-out/survey): keys Xcode writes that the parts above leave out.
    "real-project-keys": 0.7, "real-editor-keys": 0.3, "real-file-types": 0.4, "real-missing": 0.35, "real-workspace-files": 0.5,
    "real-phases": 0.25, "real-signing": 0.3, "real-scheme-keys": 0.6, "real-test-plan-keys": 0.5, "real-packages": 0.5, "real-ids": 0.13,
    "remote-packages": 0.35,
}
FOCUS_PROBABILITY = 0.9

PLAIN_WORDS = ["Core", "Model", "Views", "Utilities", "Support", "Network", "Storage", "Feature", "Helpers",
               "Services", "Store", "Common", "Screens", "Components", "Extensions", "Resources", "Sources"]
ODD_WORDS = ["My Group", "Ünïcödé", "日本語", "Café", "Cafe\u0301", "mixedCase", "UPPER", "with-dash", "with.dot",
             "a+b", "R&D", "Item (1)", "Item 10", "Item 2", "_underscore", "1Leading", "zeta", "Ångström",
             "Rocket 🚀", "Straße", "ÄÖÜ", "Ελληνικά", "two  spaces", "it's", "x@y", "Ⅻ", "Zürich", "ñ"]
TARGET_STEMS = {"app": ["App", "Fuzz", "Main"], "macapp": ["MacApp", "Desktop"], "framework": ["Kit", "Core", "UIKitExtras", "Engine"],
                "static": ["Static", "Legacy", "Vendor"], "dylib": ["Dynamic"], "bundle": ["Resources", "Assets"],
                "appex": ["Widget", "Share", "Notification Service", "Intents"], "exkit": ["ExtensionKit", "Generic Ext"],
                "clip": ["Clip"], "stickers": ["Stickers"], "watchapp": ["Watch"], "watchapp2": ["WatchKit App"],
                "watchext": ["WatchKit Extension"], "watchcontainer": ["Watch Container"], "unit": ["Tests", "UnitTests"],
                "ui": ["UITests"], "tool": ["tool", "cli"], "xpc": ["Service"], "aggregate": ["Aggregate", "Lint"],
                "legacy": ["Make", "External"]}
ODD_TARGET_NAMES = ["My App", "Café", "App-Dev", "ÜberApp", "lowercase", "App 2", "Widget Ext", "日本", "R&D", "A+B", "Ünï Kit"]
CONFIG_EXTRAS = ["Staging", "Beta Testing", "AppStore", "QA", "Debug-Dev", "Release Prod", "Profile", "Ad Hoc"]
REGIONS = ["en", "fr", "de", "ja", "zh-Hans", "pt-BR", "es-419", "ar"]
EXTENSION_POINTS = ["com.apple.widgetkit-extension", "com.apple.share-services", "com.apple.usernotifications.service",
                    "com.apple.usernotifications.content-extension", "com.apple.Safari.web-extension", "com.apple.Safari.extension",
                    "com.apple.intents-service", "com.apple.fileprovider-nonui", "com.apple.keyboard-service",
                    "com.apple.photo-editing", "com.apple.networkextension.packet-tunnel", "org.nomac.unknown-point"]

APP_KINDS = {"app", "macapp", "watchapp", "watchapp2", "clip", "tool", "watchcontainer"}
PRODUCTS = {
    "app": ("application", "wrapper.application", "{}.app"),
    "macapp": ("application", "wrapper.application", "{}.app"),
    "watchapp": ("application", "wrapper.application", "{}.app"),
    "watchapp2": ("application.watchapp2", "wrapper.application", "{}.app"),
    "watchext": ("watchkit2-extension", "wrapper.app-extension", "{}.appex"),
    "watchcontainer": ("application.watchapp2-container", "wrapper.application", "{}.app"),
    "framework": ("framework", "wrapper.framework", "{}.framework"),
    "static": ("library.static", "archive.ar", "lib{}.a"),
    "dylib": ("library.dynamic", "compiled.mach-o.dylib", "lib{}.dylib"),
    "bundle": ("bundle", "wrapper.cfbundle", "{}.bundle"),
    "appex": ("app-extension", "wrapper.app-extension", "{}.appex"),
    "exkit": ("extensionkit-extension", "wrapper.extensionkit-extension", "{}.appex"),
    "clip": ("application.on-demand-install-capable", "wrapper.application", "{}.app"),
    "stickers": ("app-extension.messages-sticker-pack", "wrapper.app-extension", "{}.appex"),
    "unit": ("bundle.unit-test", "wrapper.cfbundle", "{}.xctest"),
    "ui": ("bundle.ui-testing", "wrapper.cfbundle", "{}.xctest"),
    "tool": ("tool", "compiled.mach-o.executable", "{}"),
    "xpc": ("xpc-service", "wrapper.xpc-service", "{}.xpc"),
}
SDK_OF = {"macapp": "macosx", "tool": "macosx", "xpc": "macosx", "dylib": "macosx",
          "watchapp": "watchos", "watchapp2": "watchos", "watchext": "watchos"}

SOURCE_EXTS = {"proto", "swift", "m", "mm", "c", "cpp", "cc", "s", "metal", "intentdefinition", "mlmodel", "docc", "l", "y",
               "applescript", "xcdatamodeld", "fuzz", "r", "iig"}
HEADER_EXTS = {"h", "hpp", "H", "hh"}
FRAMEWORK_EXTS = {"framework", "xcframework", "a", "tbd", "dylib"}
UNBUILT_EXTS = {"entitlements", "modulemap", "xctestplan", "pch", "xcconfig", "md", ""}
DIRECTORY_TYPES = {"xcassets", "docc", "bundle", "framework", "xcframework", "scnassets", "icon", "mlpackage", "xcstickers",
                   "playground", "xcdatamodeld", "xcmappingmodel"}
BINARY_TYPES = {"png", "PNG", "jpg", "pdf", "ttf", "otf", "mp3", "mov", "mlmodel", "sks", "usdz", "a", "dylib", "heic",
                "wav", "caf", "zip", "scn"}
EXTRA_EXTS = (["swift"] * 8 + ["m", "h", "mm", "c", "cpp", "hpp", "H", "s", "metal", "l", "y", "iig", "pch", "modulemap"]
              + ["png", "PNG", "jpg", "pdf", "json", "txt", "md", "html", "css", "ttf", "otf", "mp3", "mov", "plist",
                 "strings", "stringsdict", "xcstrings", "storyboard", "xib", "xcassets", "sks", "scnassets", "bundle",
                 "gpx", "geojson", "rtf", "usdz", "xcprivacy", "icon", "opml", "sdef", "fuzzdata", "xcconfig", "sh",
                 "py", "csv", "xml", "svg", "heic", "wav", "js", "ts", "docc", "xcdatamodeld", "intentdefinition",
                 "mlmodel", "framework", "xcframework", "a", "tbd", "entitlements", "applescript", "zip", "",
                 "rb", "gif", "yml", "icns", "bplist", "aiff", "mk", "proto", "vsh", "bin", "playground", "xcmappingmodel"])
KNOWN_TYPES = {
    "swift": "sourcecode.swift", "m": "sourcecode.c.objc", "mm": "sourcecode.cpp.objcpp", "c": "sourcecode.c.c",
    "cpp": "sourcecode.cpp.cpp", "cc": "sourcecode.cpp.cpp", "h": "sourcecode.c.h", "hpp": "sourcecode.cpp.h",
    "s": "sourcecode.asm", "metal": "sourcecode.metal", "storyboard": "file.storyboard", "xib": "file.xib",
    "xcassets": "folder.assetcatalog", "strings": "text.plist.strings", "stringsdict": "text.plist.stringsdict",
    "xcstrings": "text.json.xcstrings", "plist": "text.plist.xml", "json": "text.json", "png": "image.png",
    "jpg": "image.jpeg", "pdf": "image.pdf", "entitlements": "text.plist.entitlements",
    "intentdefinition": "file.intentdefinition", "mlmodel": "file.mlmodel", "docc": "folder.documentationcatalog",
    "js": "sourcecode.javascript", "txt": "text", "md": "net.daringfireball.markdown", "html": "text.html",
    "css": "text.css", "framework": "wrapper.framework", "xcframework": "wrapper.xcframework", "a": "archive.ar",
    "tbd": "sourcecode.text-based-dylib-definition", "xcconfig": "text.xcconfig", "sh": "text.script.sh",
    "py": "text.script.python", "mp3": "audio.mp3", "mov": "video.quicktime", "xcprivacy": "text.xml",
    "modulemap": "sourcecode.module-map", "scnassets": "wrapper.scnassets", "sks": "file.sks", "rtf": "text.rtf",
    "icon": "folder.iconcomposer.icon", "bundle": "wrapper.plug-in", "ttf": "file", "xcdatamodeld": "wrapper.xcdatamodeld",
    # Types Xcode 27.0 gives these files when the project names none (the first fuzz runs' PIFs).
    "": "text", "H": "sourcecode.cpp.h", "PNG": "image.png", "applescript": "sourcecode.applescript", "csv": "text",
    "fuzz": "text", "fuzzdata": "text", "geojson": "text", "gpx": "text.xml", "heic": "file", "iig": "sourcecode.iig",
    "l": "sourcecode.lex", "y": "sourcecode.yacc", "opml": "text.xml", "otf": "file", "pch": "sourcecode.c.h",
    "sdef": "text.xml", "svg": "text.xml", "ts": "sourcecode.typescript", "usdz": "file", "wav": "audio.wav",
    "xcstickers": "folder.stickers", "xml": "text.xml", "zip": "archive.zip",
    "rb": "text.script.ruby", "gif": "image.gif", "yml": "text.yaml", "icns": "image.icns", "bplist": "file.bplist", "aiff": "audio.aiff",
    "mk": "sourcecode.make", "proto": "sourcecode.protobuf", "vsh": "sourcecode.glsl", "xcmappingmodel": "wrapper.xcmappingmodel",
}
# Other types real projects name for these files (the survey's `PBXFileReference.fileType`).
DECLARED_TYPES = {"modulemap": ["sourcecode.module"], "plist": ["text.plist"], "bin": ["archive.macbinary"], "playground": ["file.playground"],
                  "txt": ["undefined"], "json": ["text"], "swift": ["text"], "png": ["file"]}
TEXT_ENCODINGS = [4, 4, 4, 9, 10, 30, 12, 2483028224]
CONDITIONAL = [
    ("OTHER_LDFLAGS[sdk=iphoneos*]", ["$(inherited)", "-ObjC"]),
    ("EXCLUDED_ARCHS[sdk=iphonesimulator*]", "arm64"),
    ("CODE_SIGN_IDENTITY[sdk=iphoneos*]", "iPhone Developer"),
    ("CODE_SIGN_IDENTITY[sdk=macosx*]", "-"),
    ("OTHER_SWIFT_FLAGS[sdk=iphoneos*][arch=arm64]", "$(inherited) -DDEVICE_ARM64"),
    ("SWIFT_ACTIVE_COMPILATION_CONDITIONS[arch=arm64]", "$(inherited) ARM"),
    ("PRODUCT_BUNDLE_IDENTIFIER[sdk=macosx*]", "org.nomac.fuzz.mac"),
    ("LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]", ["$(inherited)", "@executable_path/../Frameworks"]),
    ("ARCHS[sdk=iphoneos*]", "arm64"),
    ("CODE_SIGN_STYLE[sdk=iphoneos*]", "Manual"),
    ("DEVELOPMENT_TEAM[sdk=iphoneos*]", "FUZZ123456"),
    ("GCC_PREPROCESSOR_DEFINITIONS[arch=*]", ["$(inherited)", "ANYARCH=1"]),
    ("INFOPLIST_KEY_CFBundleDisplayName[sdk=iphoneos*]", "Fuzz Device"),
    ("FUZZ_VALUE[sdk=iphonesimulator*][arch=x86_64]", "sim-x86"),
    ("HEADER_SEARCH_PATHS[variant=normal]", "$(inherited) /opt/fuzz"),
    ("SDKROOT[arch=arm64]", "iphoneos"),
    ("IPHONEOS_DEPLOYMENT_TARGET[sdk=iphoneos*]", "17.0"),
    ("PROVISIONING_PROFILE[sdk=iphoneos*]", "0a1b2c3d-1111-2222-3333-444455556666"),
    ("PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]", "Fuzz Profile"),
    ("PROVISIONING_PROFILE_SPECIFIER[sdk=macosx*]", ""),
]
WORKSPACE_SETTINGS = [{"PreviewsEnabled": False}, {"PreviewsEnabled": False}, {"BuildSystemType": "Latest"}, {"BuildSystemType": "Original"},
                      {"IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded": False}, {"IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded": True},
                      {"DisableBuildSystemDeprecationDiagnostic": True}]
USER_WORKSPACE_SETTINGS = [{"BuildLocationStyle": "UseAppPreferences", "CustomBuildLocationType": "RelativeToDerivedData",
                            "DerivedDataLocationStyle": "Default", "EnabledFullIndexStoreVisibility": False,
                            "IssueFilterStyle": "ShowActiveSchemeOnly", "LiveSourceIssuesEnabled": True},
                           {"HasAskedToTakeAutomaticSafetyMeasures": True, "ShowSharedSchemesAutomaticallyEnabled": True},
                           {"DerivedDataLocationStyle": "WorkspaceRelativePath", "DerivedDataCustomLocation": "DerivedData"},
                           {"BuildLocationStyle": "UseTargetSettings"}]
SCRIPTS = ["echo \"fuzz\"\n", "if which swiftlint >/dev/null; then\n  swiftlint\nfi\n",
           "cp \"${SRCROOT}/a b.txt\" \"${BUILT_PRODUCTS_DIR}/\" # $(TARGET_NAME)\n", "exit 0", "print('ünï')\n"]


def nfc_key(text):
    return unicodedata.normalize("NFC", text).casefold()


def slug(text):
    ascii_text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    return re.sub(r"[^A-Za-z0-9]+", "-", ascii_text).strip("-").lower() or "x"


def extension(name):
    base = name.rsplit("/", 1)[-1]
    return base.rsplit(".", 1)[1] if "." in base.lstrip(".") else ""


GENERATOR_VERSION = 2


class Generator:
    def __init__(self, seed, focus=()):
        self.seed = seed
        self.focus = set(focus)
        self.random = random.Random(f"nomac-fuzz/{seed}/{','.join(sorted(self.focus))}")
        self.counter = 0
        self.features = set()
        self.odd = False
        self.untyped = False
        self.regions = ["en"]
        self.editor = self.real_types = self.real_missing = self.real_phases = self.real_signing = self.real_schemes = False

    def chance(self, feature, probability=None):
        p = FEATURES[feature] if probability is None else probability
        if feature in self.focus:
            p = max(p, FOCUS_PROBABILITY)
        hit = self.random.random() < p
        if hit:
            self.features.add(feature)
        return hit

    def maybe(self, probability):
        return self.random.random() < probability

    def file_type(self, ext):
        if self.untyped and self.maybe(0.3):
            return None
        if self.real_types and ext in DECLARED_TYPES and self.maybe(0.4):
            return self.random.choice(DECLARED_TYPES[ext])
        return KNOWN_TYPES.get(ext)

    def ident(self, prefix):
        self.counter += 1
        return f"{prefix}{self.counter}"

    def unique(self, used, candidate):
        base, number = candidate, 2
        while nfc_key(candidate) in used:
            stem, dot, ext = base.rpartition(".") if "." in base.rsplit("/", 1)[-1].lstrip(".") else (base, "", "")
            candidate = f"{stem}{number}{dot}{ext}" if dot else f"{base}{number}"
            number += 1
        used.add(nfc_key(candidate))
        return candidate

    def word(self):
        if self.odd and self.maybe(0.45):
            self.features.add("odd-names")
            return self.random.choice(ODD_WORDS)
        return self.random.choice(PLAIN_WORDS)

    def stem(self):
        word = self.word()
        if self.maybe(0.25):
            word += str(self.random.choice([1, 2, 10, 11, 100]))
        return word

    def generate(self):
        spec = {"seed": self.seed, "focus": sorted(self.focus), "workspace": None, "projects": [], "packages": []}
        workspace = self.chance("workspace")
        self.odd = self.chance("odd-names")
        self.untyped = self.chance("untyped-files")
        self.editor = self.chance("real-editor-keys")
        self.real_types = self.chance("real-file-types")
        self.real_missing = self.chance("real-missing")
        self.real_phases = self.chance("real-phases")
        self.real_signing = self.chance("real-signing")
        self.real_schemes = self.chance("real-scheme-keys")
        if self.chance("packages"):
            spec["packages"] = self.packages()
        count = self.random.choice([1, 2, 2, 3]) if workspace else 1
        used_dirs = set()
        for index in range(count):
            spec["projects"].append(self.project(index, workspace, used_dirs))
        if self.chance("cross-project"):
            if len(spec["projects"]) == 1:
                spec["projects"].append(self.project(1, workspace, used_dirs, secondary=True))
            self.project_reference(spec["projects"][0], spec["projects"][1])
        if spec["packages"]:
            self.package_usage(spec, workspace)
        if workspace:
            spec["workspace"] = self.workspace(spec)
        spec["features"] = sorted(self.features)
        spec["generator"] = GENERATOR_VERSION
        return spec

    # Packages -----------------------------------------------------------------------------

    def packages(self):
        packages, used = [], set()
        for index in range(self.random.choice([1, 1, 2])):
            name = self.unique(used, self.random.choice(["Kit", "Networking", "DesignSystem", "Utils", "Models"]))
            folder = self.random.choice(["Packages", "LocalPackages", "Modules/Swift"])
            targets = [{"name": name, "kind": "library", "deps": [], "product_deps": [], "resources": self.maybe(0.3)}]
            products = [{"name": name, "kind": self.random.choice(["library", "library", "dynamic"]), "targets": [name]}]
            if self.maybe(0.4):
                targets.append({"name": f"{name}Extras", "kind": "library", "deps": [name], "product_deps": [], "resources": False})
                products.append({"name": f"{name}Extras", "kind": "library", "targets": [f"{name}Extras"]})
            if self.maybe(0.25):
                targets.append({"name": f"{name.lower()}-cli", "kind": "executable", "deps": [name], "product_deps": [], "resources": False})
                products.append({"name": f"{name.lower()}-cli", "kind": "executable", "targets": [f"{name.lower()}-cli"]})
            if self.maybe(0.6):
                targets.append({"name": f"{name}Tests", "kind": "test", "deps": [name], "product_deps": [], "resources": False})
            package = {"id": f"k{index}", "name": name, "dir": f"{folder}/{name}",
                       "tools": self.random.choice(["5.9", "5.10", "6.0"]),
                       "platforms": self.random.choice([[".iOS(.v16)", ".macOS(.v13)"], [".iOS(.v17)"], []]),
                       "products": products, "targets": targets, "deps": [], "schemes": []}
            if self.chance("real-packages"):
                package["tools"] = self.random.choice(["5.9", "6.0", "6.2"])
                package["default_localization"] = self.maybe(0.3)
                if self.maybe(0.3):
                    package["platforms"] = self.random.choice([[".iOS(.v16)", ".watchOS(.v9)", ".tvOS(.v16)"], [".iOS(.v17)", ".visionOS(.v1)"]])
                library = targets[0]
                library["exclude"] = self.maybe(0.2)
                library["copy"] = library["resources"] and self.maybe(0.5)
                library["swift_settings"] = [option for option, rate in [('.define("FUZZ")', 0.3), ('.define("FUZZ_IOS", .when(platforms: [.iOS]))', 0.15),
                                                                         ('.unsafeFlags(["-Onone"])', 0.1), ('.enableUpcomingFeature("ExistentialAny")', 0.1)]
                                             if self.maybe(rate)]
            if packages and self.maybe(0.4):
                other = self.random.choice(packages)
                package["deps"].append(other["id"])
                targets[0]["product_deps"].append({"package": other["id"], "product": other["products"][0]["name"]})
            if self.maybe(0.15):
                package["schemes"].append({"id": self.ident("sc"), "name": name, "user": False,
                                           "build": [{"package": package["id"], "product": name, "running": True}],
                                           "tests": [], "launch": None, "profile": None, "coverage": self.maybe(0.5),
                                           "plans": [], "configs": {}})
            packages.append(package)
        used_by_others = {dep for package in packages for dep in package["deps"]}
        for package in packages:
            if not package["deps"] and package["id"] not in used_by_others and self.chance("remote-packages"):
                package["dir"] = f".remotes/{package['name']}"
                package["remote"] = self.random.choice([{"kind": "upToNextMajorVersion", "minimumVersion": "1.0.0"}, {"kind": "upToNextMajorVersion", "minimumVersion": "1.0.0"},
                                                        {"kind": "upToNextMinorVersion", "minimumVersion": "1.0.0"}, {"kind": "exactVersion", "version": "1.0.0"},
                                                        {"kind": "branch", "branch": "main"}, {"kind": "revision"}])
                package["schemes"] = []
        return packages

    def package_usage(self, spec, workspace):
        project = spec["projects"][0]
        app = next((t for t in project["targets"] if t["kind"] in ("app", "macapp")), None)
        for package in spec["packages"]:
            if any(package["id"] in other["deps"] for other in spec["packages"]) and self.maybe(0.3):
                continue
            if package.get("remote"):
                project["package_refs"].append({"id": self.ident("r"), "package": package["id"]})
            elif workspace and self.maybe(0.35):
                package["in_workspace"] = True
            elif project["object_version"] >= 60 and self.maybe(0.7):
                project["package_refs"].append({"id": self.ident("r"), "package": package["id"]})
            else:
                project["tree"].append({"id": self.ident("n"), "kind": "package", "package": package["id"]})
            if app and self.maybe(0.85):
                product = self.random.choice([p for p in package["products"] if p["kind"] != "executable"])
                dependency = {"id": self.ident("d"), "package": package["id"], "product": product["name"]}
                app["package_products"].append(dependency)
                self.phase(app, "frameworks")["files"].append({"id": self.ident("b"), "ref": f"pkg:{dependency['id']}"})

    # Projects -----------------------------------------------------------------------------

    def project(self, index, workspace, used_dirs, secondary=False):
        pid = f"p{index}" + ("~obj" if self.chance("real-ids") else "")
        if index == 0:
            name = self.random.choice(ODD_TARGET_NAMES) if self.odd and self.maybe(0.4) else self.random.choice(["App", "Fuzz", "Sample"])
            directory = "" if not workspace or self.maybe(0.6) else self.random.choice(["App", "Apps/Main"])
        else:
            name = self.random.choice(["Kit", "Core", "Shared UI", "Ünï Lib"] if self.odd else ["Kit", "Core", "Shared"])
            directory = self.random.choice(["Libs", "Modules", "Sub Dir", "Frameworks/Ñ" if self.odd else "Frameworks/Inner"])
        key = nfc_key(f"{directory}/{name}")
        while key in used_dirs:
            directory = f"{directory}/More" if directory else "More"
            key = nfc_key(f"{directory}/{name}")
        used_dirs.add(key)
        legacy = self.chance("legacy-format")
        version = self.random.choice([45, 46, 47, 48, 50, 51, 52, 54, 55, 56, 60, 63, 70]) if legacy else 77
        configs = ["Debug", "Release"]
        if self.chance("configs"):
            extras = self.random.sample(CONFIG_EXTRAS, self.random.choice([1, 1, 2]))
            shape = self.random.random()
            if shape < 0.15:
                configs = ["Release", "Debug"] + extras
            elif shape < 0.25:
                configs = extras + ["Production"]
            elif shape < 0.5:
                configs = ["Debug"] + extras + ["Release"]
            else:
                configs = configs + extras
        default = "Release" if "Release" in configs and self.maybe(0.85) else self.random.choice(configs)
        regions = ["en", "Base"]
        if self.chance("localization"):
            regions += self.random.sample(REGIONS[1:], self.random.choice([1, 2, 3]))
        self.regions = [r for r in regions if r != "Base"]
        project = {"id": pid, "name": name, "dir": directory, "object_version": version,
                   "development_region": "en" if self.maybe(0.9) else "fr", "regions": regions,
                   "class_prefix": "FZ" if self.maybe(0.1) else None,
                   "settings": {}, "configs": [{"name": c, "settings": {}, "base": None} for c in configs],
                   "default_config": default, "xcconfigs": [], "tree": [], "targets": [], "schemes": [],
                   "user_schemes": [], "other_user_schemes": [], "scheme_management": None, "test_plans": [],
                   "package_refs": [], "project_refs": [], "disk_files": [], "embedded_workspace": self.maybe(0.5),
                   "attributes": {"BuildIndependentTargetsInParallel": "1"} if self.maybe(0.7) else {},
                   "workspace_files": self.workspace_files()}
        self.dirs = set()
        self.config_folder = None
        self.project_settings(project)
        if self.chance("xcconfig"):
            self.xcconfigs(project)
        self.targets(project, secondary)
        if self.chance("real-project-keys"):
            self.project_keys(project)
        self.shared_files(project)
        self.frameworks_group(project)
        if self.real_missing:
            self.missing_parts(project)
        self.schemes(project)
        return project

    def workspace_files(self):
        if not self.chance("real-workspace-files"):
            return None
        return {"checks": self.maybe(0.8),
                "settings": self.random.choice(WORKSPACE_SETTINGS) if self.maybe(0.3) else None,
                "user_settings": self.random.choice(USER_WORKSPACE_SETTINGS) if self.maybe(0.15) else None,
                "resolved": self.random.choice([1, 2, 3]) if self.maybe(0.3) else None}

    def project_keys(self, project):
        attributes = project["attributes"]
        if self.maybe(0.9):
            attributes["ORGANIZATIONNAME"] = self.random.choice(["Fuzz Inc.", "Ünï GmbH", "org.nomac"])
        if self.maybe(0.1):
            attributes["LastSwiftMigration"] = "1600"
        if self.maybe(0.03):
            attributes["LastTestingUpgradeCheck"] = "0700"
        if self.maybe(0.03):
            attributes["DefaultBuildSystemTypeForWorkspace"] = self.random.choice(["Latest", "Original"])
        if self.maybe(0.02):
            attributes["KnownAssetTags"] = ["Level1", "Level 2"]
        for target in project["targets"]:
            if self.maybe(0.5):
                target["attributes"]["DevelopmentTeam"] = "FUZZ123456"
            if self.maybe(0.03):
                target["attributes"]["DevelopmentTeamName"] = "Fuzz Team (Personal Team)"
            if self.maybe(0.3):
                target["attributes"]["SystemCapabilities"] = {"com.apple.Push": {"enabled": 1}, "com.apple.BackgroundModes": {"enabled": self.random.choice([0, 1])}}
            if self.maybe(0.1):
                target["attributes"]["LastSwiftMigration"] = "1600"

    def missing_parts(self, project):
        """What a real project's checkout lacks: CocoaPods' xcconfigs and subprojects it never fetched."""
        targets = [t for t in project["targets"] if t["kind"] in PRODUCTS]
        if targets and self.maybe(0.5):
            target = self.random.choice(targets)
            folder = f"Pods/Target Support Files/Pods-{slug(target['name'])}"
            children = []
            for config in project["configs"]:
                xcconfig = {"id": self.ident("x"), "path": f"{folder}/Pods-{slug(target['name'])}.{slug(config['name'])}.xcconfig", "lines": [], "on_disk": False}
                project["xcconfigs"].append(xcconfig)
                children.append({"id": self.ident("n"), "kind": "file", "path": Path(xcconfig["path"]).name, "name": None, "xcconfig": xcconfig["id"],
                                 "type": "text.xcconfig", "on_disk": False, "source_tree": "<group>"})
                target["bases"][config["name"]] = xcconfig["id"]
            project["tree"].append({"id": self.ident("n"), "kind": "group", "name": "Pods", "path": None, "children": children})
        if targets and project["object_version"] >= 46 and self.maybe(0.3):
            node = {"id": self.ident("n"), "kind": "file", "path": "Vendor/Gone/Gone.xcodeproj", "name": "Gone.xcodeproj", "type": "wrapper.pb-project", "on_disk": False}
            project["tree"].append(node)
            reference = {"id": self.ident("pr"), "node": node["id"], "missing": True,
                         "products": [{"path": "libGone.a", "type": "archive.ar"}, {"path": "Gone.framework", "type": "wrapper.framework"}]}
            project["project_refs"].append(reference)
            host = self.random.choice(targets)
            host["deps"].append({"gone": reference["id"], "name": "Gone"})
            self.phase(host, "frameworks")["files"].append({"id": self.ident("b"), "ref": f"gone:{reference['id']}:{self.random.randrange(2)}"})

    def editor_keys(self, group=False):
        if not self.editor or not self.maybe(0.25):
            return None
        keys = {}
        if self.maybe(0.5):
            keys["indentWidth"] = self.random.choice([2, 4, 8])
        if self.maybe(0.5):
            keys["tabWidth"] = self.random.choice([2, 4, 8])
        if self.maybe(0.4):
            keys["usesTabs"] = self.random.choice([0, 1])
        if self.maybe(0.2):
            keys["wrapsLines"] = self.random.choice([0, 1])
        if not group:
            if self.maybe(0.4):
                keys["lineEnding"] = self.random.choice([0, 1, 2])
            if self.maybe(0.5):
                keys["xcLanguageSpecificationIdentifier"] = self.random.choice(["xcode.lang.swift", "xcode.lang.objc", "xcode.lang.ruby", "xcode.lang.sh"])
            if self.maybe(0.1):
                keys["plistStructureDefinitionIdentifier"] = "com.apple.xcode.plist.structure-definition.iphone.info-plist"
        return keys or None

    def project_settings(self, project):
        candidates = {"ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
                      "COPY_PHASE_STRIP": "NO", "ENABLE_STRICT_OBJC_MSGSEND": "YES", "GCC_C_LANGUAGE_STANDARD": "gnu17",
                      "GCC_NO_COMMON_BLOCKS": "YES", "MTL_FAST_MATH": "YES", "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
                      "ENABLE_USER_SCRIPT_SANDBOXING": "YES", "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20",
                      "SWIFT_EMIT_LOC_STRINGS": "YES", "DEAD_CODE_STRIPPING": "YES",
                      "IPHONEOS_DEPLOYMENT_TARGET": self.random.choice(["15.0", "16.0", "17.0", "18.0", "26.0"]),
                      "SWIFT_VERSION": self.random.choice(["5.0", "6.0"])}
        settings = {key: value for key, value in candidates.items() if self.maybe(0.6)}
        if self.maybe(0.9):
            settings["SDKROOT"] = "iphoneos" if self.maybe(0.9) else self.random.choice(["auto", "macosx"])
        if self.chance("macros", 0.15):
            settings["FUZZ_SIGN_STYLE"] = self.random.choice(["Manual", "Automatic"])
        if self.chance("conditional", 0.2):
            key, value = self.random.choice(CONDITIONAL)
            settings[key] = value
        project["settings"] = settings
        for config in project["configs"]:
            debug_like = config["name"] in ("Debug", "Debug-Dev", "QA") or (config["name"] not in ("Release", "Production") and self.maybe(0.4))
            values = ({"DEBUG_INFORMATION_FORMAT": "dwarf", "ONLY_ACTIVE_ARCH": "YES", "ENABLE_TESTABILITY": "YES",
                       "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)", "GCC_OPTIMIZATION_LEVEL": "0",
                       "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"], "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
                       "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE"} if debug_like else
                      {"DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym", "VALIDATE_PRODUCT": "YES", "ENABLE_NS_ASSERTIONS": "NO",
                       "SWIFT_COMPILATION_MODE": "wholemodule", "MTL_ENABLE_DEBUG_INFO": "NO"})
            config["settings"] = {key: value for key, value in values.items() if self.maybe(0.75)}
            if "FUZZ_SIGN_STYLE" in settings and self.maybe(0.5):
                config["settings"]["FUZZ_SIGN_STYLE"] = "Automatic" if debug_like else "Manual"
            if config["name"] not in ("Debug", "Release") and self.maybe(0.5):
                config["settings"]["FUZZ_ENVIRONMENT"] = config["name"]

    def xcconfigs(self, project):
        used = set()
        folder = self.unique(self.dirs, self.random.choice(["Config", "Configuration", "Build Settings" if self.odd else "Settings"]))
        shared = {"id": self.ident("x"), "path": f"{folder}/Shared/Common.xcconfig", "lines": [
            {"comment": "Shared"}, {"set": "FUZZ_COMMON", "value": "common $(inherited)"},
            {"set": "SWIFT_VERSION", "value": self.random.choice(["5.0", "6.0"])}]}
        if self.chance("conditional", 0.4):
            shared["lines"].append({"set": "OTHER_LDFLAGS[sdk=iphoneos*][config=Release]", "value": "$(inherited) -dead_strip"})
        base = {"id": self.ident("x"), "path": f"{folder}/Base.xcconfig", "lines": [
            {"include": shared["id"], "optional": False},
            {"set": "OTHER_SWIFT_FLAGS", "value": "$(inherited) -DXCCONFIG"}]}
        if self.maybe(0.4):
            base["lines"].append({"include_path": "Local.xcconfig", "optional": True})
        if self.maybe(0.3):
            base["lines"].append({"set": "PRODUCT_BUNDLE_IDENTIFIER_PREFIX", "value": "org.nomac.fuzz"})
        if self.chance("macros", 0.4):
            base["lines"].append({"set": "FUZZ_SIGN_STYLE", "value": self.random.choice(["Manual", "Automatic"])})
            base["lines"].append({"set": "CODE_SIGN_STYLE", "value": "$(FUZZ_SIGN_STYLE)"})
        if self.real_missing and self.maybe(0.3):
            base["lines"].append({"include_path": "../Pods/Target Support Files/Gone.xcconfig", "optional": False})
        if self.real_signing:
            for key, value, probability in [("CODE_SIGN_IDENTITY", "Apple Development", 0.4), ("PRODUCT_NAME", "$(TARGET_NAME)", 0.3),
                                            ("PROVISIONING_PROFILE_SPECIFIER", "Fuzz Profile", 0.3),
                                            ("CODE_SIGN_IDENTITY[sdk=iphoneos*]", "iPhone Developer", 0.2)]:
                if self.maybe(probability):
                    base["lines"].append({"set": key, "value": value})
        project["xcconfigs"] = [shared, base]
        used.update({nfc_key(shared["path"]), nfc_key(base["path"])})
        per_config = {}
        for config in project["configs"]:
            if self.maybe(0.5):
                xcconfig = {"id": self.ident("x"), "path": f"{folder}/{config['name']}.xcconfig",
                            "lines": [{"include": base["id"], "optional": False}, {"set": "FUZZ_CONFIG", "value": config["name"]}]}
                if nfc_key(xcconfig["path"]) not in used:
                    used.add(nfc_key(xcconfig["path"]))
                    project["xcconfigs"].append(xcconfig)
                    per_config[config["name"]] = xcconfig["id"]
            config["base"] = per_config.get(config["name"], base["id"] if self.maybe(0.7) else None)
        if project["object_version"] >= 77 and self.chance("sync", 0.3):
            node = {"id": self.ident("n"), "kind": "sync", "path": folder, "name": None, "items": [], "empty_dirs": [],
                    "hidden": [], "exceptions": [], "explicit_types": {}, "explicit_folders": []}
        else:
            children = [{"id": self.ident("n"), "kind": "file", "path": Path(x["path"]).name, "xcconfig": x["id"],
                         "type": self.file_type("xcconfig")} for x in project["xcconfigs"] if x is not shared]
            if self.maybe(0.6):
                children.append({"id": self.ident("n"), "kind": "group", "name": None, "path": "Shared", "children": [
                    {"id": self.ident("n"), "kind": "file", "path": "Common.xcconfig", "xcconfig": shared["id"], "type": self.file_type("xcconfig")}]})
            node = {"id": self.ident("n"), "kind": "group", "name": None, "path": folder, "children": children}
        project["tree"].append(node)
        self.config_folder = {"path": folder, "base": base["id"], "node": node}

    # Targets ------------------------------------------------------------------------------

    def targets(self, project, secondary):
        if secondary:
            kinds = [self.random.choice(["framework", "framework", "static", "app"])]
        elif self.chance("macos", 0.06):
            kinds = [self.random.choice(["macapp", "tool"])]
        else:
            kinds = ["app"]
        if self.chance("frameworks"):
            kinds += self.random.choice([["framework"], ["static"], ["framework", "static"], ["bundle"], ["framework", "framework"]])
        if self.chance("extensions"):
            kinds += self.random.sample(["appex", "appex", "exkit", "clip", "stickers"], self.random.choice([1, 1, 2]))
        if self.chance("watch"):
            kinds += self.random.choice([["watchapp"], ["watchapp2", "watchext"], ["watchcontainer", "watchapp2", "watchext"]])
        if self.chance("macos"):
            kinds += self.random.choice([["macapp"], ["tool"], ["xpc"], ["dylib"]])
        if self.chance("tests"):
            kinds += self.random.choice([["unit"], ["unit", "ui"], ["unit", "unit"], ["ui"]])
        if self.chance("aggregate"):
            kinds += self.random.choice([["aggregate"], ["legacy"], ["aggregate", "legacy"]])
        if self.maybe(0.15):
            self.random.shuffle(kinds)
        names = set()
        for kind in kinds:
            project["targets"].append(self.target(project, kind, names))
        self.wire(project)

    def target_name(self, kind, names):
        if self.odd and self.maybe(0.3):
            self.features.add("odd-names")
            candidate = self.random.choice(ODD_TARGET_NAMES)
        else:
            candidate = self.random.choice(TARGET_STEMS[kind])
        return self.unique(names, candidate)

    def target(self, project, kind, names):
        name = self.target_name(kind, names)
        target = {"id": self.ident("t"), "name": name, "kind": kind, "product_name": None, "settings": {},
                  "config_settings": {}, "bases": {}, "phases": [], "sync": [], "deps": [], "package_products": [],
                  "rules": [], "attributes": {}}
        if kind in ("aggregate", "legacy"):
            if kind == "legacy":
                target["legacy"] = {"tool": self.random.choice(["/usr/bin/make", "/bin/sh"]), "arguments": "$(ACTION)",
                                    "directory": self.random.choice(["", "$(SRCROOT)/Scripts"]), "pass": self.maybe(0.7)}
            else:
                target["phases"].append(self.script_phase())
            target["settings"] = {"PRODUCT_NAME": "$(TARGET_NAME)"} if self.maybe(0.6) else {}
            return target
        if kind in ("app", "framework", "macapp") and self.maybe(0.08):
            target["product_name"] = self.random.choice(["Fancy Name", "Ünï Product", "prod"])
        directory = self.unique(self.dirs, name if self.maybe(0.8) else f"{name} Sources")
        files = self.files_for(kind, name)
        plist = self.info_plist(target, directory)
        if plist:
            files.append("Info.plist")
        sync = project["object_version"] >= 77 and self.chance("sync")
        if sync:
            node = self.sync_folder(directory, files, target, plist)
            target["sync"].append(node["id"])
            for phase_kind in ["sources", "frameworks", "resources"] if kind not in ("watchcontainer", "stickers") else ["resources"]:
                if self.maybe(0.9):
                    target["phases"].append({"id": self.ident("ph"), "kind": phase_kind, "files": []})
            if kind in ("framework", "static") and self.maybe(0.7):
                target["phases"].insert(0, {"id": self.ident("ph"), "kind": "headers", "files": []})
        else:
            node = self.group_folder(directory, files, target, plist)
        project["tree"].append(node)
        self.target_settings(project, target, directory, plist, files)
        if self.chance("phases", 0.35):
            self.extra_phases(target)
        if self.chance("rules"):
            self.rules(target, node)
        if self.maybe(0.75):
            target["attributes"]["CreatedOnToolsVersion"] = self.random.choice(["15.0", "16.0", "26.0"])
        if self.maybe(0.2):
            target["attributes"]["LastSwiftMigration"] = "1600"
        return target

    def files_for(self, kind, name):
        base = {
            "app": ["AppMain.swift", "ContentView.swift", "Assets.xcassets"],
            "macapp": ["AppDelegate.swift", "MainMenu.xib", "Assets.xcassets"],
            "framework": [f"{slug(name).title()}.h", "Public.swift", "Internal.h", "Impl.m"],
            "static": ["Library.m", "Library.h"], "dylib": ["Lib.c", "Lib.h"],
            "bundle": ["Data.json", "Image.png"], "appex": ["Extension.swift"], "exkit": ["Extension.swift"],
            "clip": ["ClipApp.swift", "Assets.xcassets"], "stickers": ["Stickers.xcstickers"],
            "watchapp": ["WatchApp.swift", "Assets.xcassets"], "watchapp2": ["Interface.storyboard", "Assets.xcassets"],
            "watchext": ["ExtensionDelegate.swift", "InterfaceController.swift"], "watchcontainer": [],
            "unit": ["UnitTests.swift"], "ui": ["UITests.swift", "UITestsLaunchTests.swift"], "tool": ["main.swift"],
            "xpc": ["main.m", "Service.h", "Service.m"],
        }[kind]
        files = list(base)
        used = {nfc_key(f) for f in files}
        if kind in ("app", "macapp", "clip") and self.maybe(0.4):
            files.append(self.unique(used, f"{name}.entitlements"))
        if kind == "app" and self.maybe(0.3):
            files.append(self.unique(used, "Preview Content/Preview Assets.xcassets"))
        if self.chance("localization", 0.5) and kind in ("app", "macapp", "framework", "appex"):
            languages = list(self.regions)
            if self.chance("localization", 0.15):
                languages.append("it")
            files += ["Base.lproj/Main.storyboard"] + [f"{r}.lproj/Main.strings" for r in languages[1:3]]
            files += [f"{r}.lproj/Localizable.strings" for r in languages[:3]]
            if self.maybe(0.15):
                files.append("mul.lproj/Localizable.xcstrings")
            used.update(nfc_key(f) for f in files)
        if self.chance("file-types", 0.6):
            for _ in range(self.random.choice([1, 2, 3, 5, 8])):
                ext = self.random.choice(EXTRA_EXTS)
                stem = self.stem() if ext else self.random.choice(["LICENSE", "Makefile", "README", "Brewfile"])
                sub = ""
                if self.maybe(0.3):
                    sub = "/".join(self.word() for _ in range(self.random.choice([1, 1, 2, 3]))) + "/"
                files.append(self.unique(used, f"{sub}{stem}.{ext}" if ext else f"{sub}{stem}"))
        return files

    def info_plist(self, target, directory):
        kind = target["kind"]
        if kind in ("static", "dylib", "tool", "watchcontainer"):
            return None
        wants = self.maybe(0.85) if kind in ("appex", "exkit", "watchext") else self.maybe(0.4)
        if not wants:
            return None
        values = {}
        identifier = self.random.random()
        if identifier < 0.6:
            values["CFBundleIdentifier"] = "$(PRODUCT_BUNDLE_IDENTIFIER)"
        elif identifier < 0.8:
            values["CFBundleIdentifier"] = f"org.nomac.fuzz.plist.{slug(target['name'])}"
        values["CFBundleExecutable"] = "$(EXECUTABLE_NAME)"
        if kind == "appex":
            point = self.random.choice(EXTENSION_POINTS)
            values["NSExtension"] = {"NSExtensionPointIdentifier": point, "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).Handler"}
        elif kind == "exkit":
            values["EXAppExtensionAttributes"] = {"EXExtensionPointIdentifier": self.random.choice(EXTENSION_POINTS)}
        plist = {"path": f"{directory}/Info.plist", "values": values,
                 "corrupt": self.chance("missing-files", 0.05), "on_disk": not self.chance("missing-files", 0.08)}
        return plist

    def sync_folder(self, directory, files, target, plist):
        node = {"id": self.ident("n"), "kind": "sync", "path": directory, "name": None, "items": [], "empty_dirs": [],
                "hidden": [], "exceptions": [], "explicit_types": {}, "explicit_folders": []}
        node["items"] = [path for path in files if path != "Info.plist"]
        if self.maybe(0.2):
            node["hidden"].append(self.random.choice([".gitkeep", ".DS_Store", ".hidden.swift"]))
        if self.maybe(0.1):
            node["empty_dirs"].append(self.word())
        if self.chance("sync-exceptions"):
            membership = []
            if plist and self.maybe(0.85):
                membership.append("Info.plist")
            candidates = [p for p in node["items"] if p != "Info.plist"]
            if candidates and self.maybe(0.5):
                membership += self.random.sample(candidates, min(len(candidates), self.random.choice([1, 2])))
            if self.chance("missing-files", 0.3):
                membership.append(self.random.choice(["Gone.swift", "Removed/Old.m", f"{self.word()}/Missing.png"]))
            folders = sorted({p.rsplit("/", 1)[0] for p in node["items"] if "/" in p and ".lproj/" not in p})
            if folders and self.maybe(0.2):
                membership.append(self.random.choice(folders))
            exception = {"id": self.ident("e"), "kind": "build-file", "target": target["id"], "membership": sorted(set(membership)),
                         "public": [], "private": [], "flags": {}, "attributes": {}, "platform_filters": {}}
            headers = [p for p in node["items"] if extension(p) in HEADER_EXTS]
            if target["kind"] == "framework" and headers:
                for header in headers:
                    roll = self.random.random()
                    if roll < 0.5:
                        exception["public"].append(header)
                    elif roll < 0.7:
                        exception["private"].append(header)
            for path in node["items"]:
                if extension(path) in ("m", "c", "mm") and self.maybe(0.3):
                    exception["flags"][path] = self.random.choice(["-fno-objc-arc", "-Wno-everything -DNAME=\\\"x\\\""])
                if extension(path) in ("framework", "xcframework") and self.maybe(0.5):
                    exception["attributes"][path] = self.random.choice([["CodeSignOnCopy", "RemoveHeadersOnCopy"], ["Weak"]])
                if extension(path) == "intentdefinition" and self.maybe(0.5):
                    exception["attributes"][path] = ["no_codegen"]
                if self.chance("sync-phase-exceptions", 0.02):
                    exception["platform_filters"][path] = self.random.choice([["ios"], ["macos"], ["ios", "maccatalyst"]])
            node["exceptions"].append(exception)
        if self.maybe(0.05):
            sample = self.random.choice(node["items"]) if node["items"] else None
            if sample:
                node["explicit_types"][sample] = self.random.choice(["text", "sourcecode.swift", "text.json", "file"])
        folders = sorted({p.split("/", 1)[0] for p in node["items"] if "/" in p and ".lproj/" not in p})
        if folders and self.maybe(0.08):
            node["explicit_folders"].append(self.random.choice(folders))
        return node

    def group_folder(self, directory, files, target, plist):
        root = {"id": self.ident("n"), "kind": "group", "name": None, "path": directory, "children": []}
        if self.maybe(0.1):
            root["name"], root["path"] = directory, None
            if self.maybe(0.5):
                root["name"], root["path"] = f"{directory} (virtual)", None
        groups = {"": root}
        variants = {}
        kind = target["kind"]
        headers_phase = kind in ("framework", "static") and self.maybe(0.8)
        phases = {"sources": [], "headers": [], "frameworks": [], "resources": []}

        def group_for(folder):
            if folder in groups:
                return groups[folder]
            parent_folder, _, last = folder.rpartition("/")
            parent = group_for(parent_folder)
            group = {"id": self.ident("n"), "kind": "group", "name": None, "path": last, "children": [], "extras": self.editor_keys(group=True)}
            if self.maybe(0.1):
                group["name"] = f"{last} Group"
            parent["children"].append(group)
            groups[folder] = group
            return group

        for path in files:
            folder, _, name = path.rpartition("/")
            if folder.endswith(".lproj"):
                region = folder.rsplit("/", 1)[-1][:-len(".lproj")]
                parent_folder = folder.rpartition("/")[0]
                stem = name.rsplit(".", 1)[0]
                key = (parent_folder, stem) if extension(name) in ("storyboard", "xib", "strings") else (parent_folder, name)
                if key not in variants:
                    variant = {"id": self.ident("n"), "kind": "variant", "name": name, "children": []}
                    if self.real_types and self.maybe(0.1):
                        variant["path"] = "Localized"
                    variants[key] = variant
                    group_for(parent_folder)["children"].append(variant)
                    phases["resources"].append(variant["id"])
                variants[key]["children"].append({"id": self.ident("n"), "region": region, "path": f"{region}.lproj/{name}",
                                                  "on_disk": True})
                continue
            ext = extension(name)
            missing = path != "Info.plist" and self.chance("missing-files", 0.08)
            node = {"id": self.ident("n"), "kind": "version" if ext == "xcdatamodeld" else "file", "path": name,
                    "name": None, "type": self.file_type(ext), "on_disk": not missing}
            if path == "Info.plist":
                node["on_disk"] = False
                if not plist or not plist["on_disk"]:
                    continue
            if node["kind"] == "version":
                node["versions"] = ["Model", "Model 2"] if self.maybe(0.5) else ["Model"]
            if self.maybe(0.08):
                node["name"] = name
            node["extras"] = self.editor_keys()
            if self.maybe(0.15) and ext not in DIRECTORY_TYPES:
                node["encoding"] = self.random.choice(TEXT_ENCODINGS)
            if self.maybe(0.03):
                node["explicit"] = True
                node["type"] = node["type"] or "text"
            group_for(folder)["children"].append(node)
            phase = phase_for(ext, name, headers_phase)
            if phase and kind not in ("watchcontainer",):
                phases[phase].append(node["id"])
        if self.real_types and root["path"] and self.maybe(0.1):
            root["source_tree"] = "SOURCE_ROOT"
        if self.real_types and self.maybe(0.2):
            folder_node = {"id": self.ident("n"), "kind": "file", "path": self.random.choice(["Blue Folder", "web", "Bundled Data"]), "name": None,
                           "type": "folder", "on_disk": not self.chance("missing-files", 0.1), "folder_items": ["a.txt", "sub/b.json"]}
            root["children"].append(folder_node)
            phases["resources"].append(folder_node["id"])
        if self.real_missing and self.maybe(0.1):
            absolute = {"id": self.ident("n"), "kind": "file", "path": "/Users/nobody/Vendor/Gone.m", "name": "Gone.m", "type": "sourcecode.c.objc",
                        "on_disk": False, "source_tree": "<absolute>"}
            root["children"].append(absolute)
            phases["sources"].append(absolute["id"])
        if headers_phase:
            target["phases"].append({"id": self.ident("ph"), "kind": "headers", "files": [self.header_file(ref) for ref in phases["headers"]]})
        for phase_kind in ["sources", "frameworks", "resources"]:
            if phases[phase_kind] or self.maybe(0.7):
                build_files = []
                for ref in phases[phase_kind]:
                    build_file = {"id": self.ident("b"), "ref": ref}
                    if phase_kind == "sources" and self.maybe(0.08):
                        build_file["flags"] = self.random.choice(["-fno-objc-arc", "-DFUZZ=1 -Wall"])
                    if self.maybe(0.04):
                        build_file["platforms"] = self.random.choice([["ios"], ["macos"], ["ios", "maccatalyst"]])
                    elif self.real_phases and self.maybe(0.05):
                        build_file["platform"] = self.random.choice(["ios", "macos", "maccatalyst"])
                    if phase_kind == "resources" and self.real_phases and self.maybe(0.1):
                        build_file["asset_tags"] = ["Level1"]
                    build_files.append(build_file)
                target["phases"].append({"id": self.ident("ph"), "kind": phase_kind, "files": build_files})
        return root

    def header_file(self, ref):
        build_file = {"id": self.ident("b"), "ref": ref}
        roll = self.random.random()
        if roll < 0.5:
            build_file["attributes"] = ["Public"]
        elif roll < 0.7:
            build_file["attributes"] = ["Private"]
        elif roll < 0.85 and self.real_phases:
            build_file["attributes"] = ["Project"]
        return build_file

    def target_settings(self, project, target, directory, plist, files):
        kind = target["kind"]
        settings = {"PRODUCT_NAME": target["product_name"] or "$(TARGET_NAME)"}
        if kind not in ("static", "dylib", "tool"):
            settings["PRODUCT_BUNDLE_IDENTIFIER"] = f"org.nomac.fuzz.{slug(target['name'])}"
        for key, value, probability in [("CODE_SIGN_STYLE", "Automatic", 0.6), ("DEVELOPMENT_TEAM", "FUZZ123456", 0.3),
                                        ("CURRENT_PROJECT_VERSION", "1", 0.5), ("MARKETING_VERSION", "1.0", 0.5),
                                        ("SWIFT_VERSION", self.random.choice(["5.0", "6.0"]), 0.4),
                                        ("SWIFT_EMIT_LOC_STRINGS", "YES", 0.3)]:
            if self.maybe(probability):
                settings[key] = value
        if self.real_signing:
            for key, value, probability in [("PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]", "Fuzz Profile", 0.2),
                                            ("PROVISIONING_PROFILE_SPECIFIER", self.random.choice(["", "Plain Profile", "$(FUZZ_PROFILE)"]), 0.2),
                                            ("PROVISIONING_PROFILE[sdk=iphoneos*]", "0a1b2c3d-1111-2222-3333-444455556666", 0.2),
                                            ("PROVISIONING_PROFILE", "", 0.2)]:
                if self.maybe(probability):
                    settings[key] = value
        sdk = SDK_OF.get(kind)
        if sdk == "macosx":
            settings["SDKROOT"] = "macosx"
            settings["MACOSX_DEPLOYMENT_TARGET"] = self.random.choice(["14.0", "15.0", "26.0"])
        elif sdk == "watchos":
            settings["SDKROOT"] = "watchos"
            settings["WATCHOS_DEPLOYMENT_TARGET"] = self.random.choice(["10.0", "11.0", "26.0"])
            settings["TARGETED_DEVICE_FAMILY"] = "4"
        else:
            if self.maybe(0.6):
                settings["TARGETED_DEVICE_FAMILY"] = self.random.choice(["1,2", "1", "2", "1,2,6"])
            if self.chance("macos", 0.08):
                settings["SUPPORTED_PLATFORMS"] = "iphoneos iphonesimulator macosx"
                settings["SDKROOT"] = "auto"
                settings["SUPPORTS_MACCATALYST"] = "YES"
            elif self.maybe(0.1):
                settings["SDKROOT"] = "iphoneos"
        if plist:
            settings["INFOPLIST_FILE"] = self.plist_setting(project, target, directory, plist)
            if self.maybe(0.3):
                settings["GENERATE_INFOPLIST_FILE"] = "YES"
            project["disk_files"].append({"path": plist["path"], "kind": "plist", "values": plist["values"],
                                          "corrupt": plist["corrupt"], "on_disk": plist["on_disk"]})
        elif kind not in ("static", "dylib", "tool", "watchcontainer"):
            settings["GENERATE_INFOPLIST_FILE"] = "YES"
            if kind in ("app", "clip", "watchapp"):
                settings["INFOPLIST_KEY_UILaunchScreen_Generation"] = "YES"
                if self.maybe(0.3):
                    settings["INFOPLIST_KEY_CFBundleDisplayName"] = target["name"]
        if kind in ("app", "clip", "macapp", "watchapp"):
            settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
            if self.maybe(0.5):
                settings["ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME"] = "AccentColor"
            settings["LD_RUNPATH_SEARCH_PATHS"] = ["$(inherited)", "@executable_path/Frameworks"]
            if self.maybe(0.4):
                settings["ENABLE_PREVIEWS"] = "YES"
                settings["DEVELOPMENT_ASSET_PATHS"] = f'"{directory}/Preview Content"'
        if kind == "framework":
            settings.update({"DEFINES_MODULE": "YES", "DYLIB_INSTALL_NAME_BASE": "@rpath", "SKIP_INSTALL": "YES",
                             "INSTALL_PATH": "$(LOCAL_LIBRARY_DIR)/Frameworks", "VERSIONING_SYSTEM": "apple-generic"})
        if kind == "static":
            settings.update({"OTHER_LDFLAGS": "-ObjC", "SKIP_INSTALL": "YES"})
        if kind in ("appex", "exkit", "stickers", "watchext"):
            settings["SKIP_INSTALL"] = "YES"
            settings["LD_RUNPATH_SEARCH_PATHS"] = ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"]
        entitlements = next((f for f in files if f.endswith(".entitlements")), None)
        if entitlements:
            settings["CODE_SIGN_ENTITLEMENTS"] = f"{directory}/{entitlements}"
        if self.maybe(0.2):
            settings["FUZZ_FLAG"] = "$(TARGET_NAME)-$(CONFIGURATION)"
        if self.maybe(0.15):
            settings["HEADER_SEARCH_PATHS"] = ["$(inherited)", '"$(SRCROOT)/Vendor Dir/include"', "$(PROJECT_DIR)/Libs/**"]
        if self.maybe(0.1):
            settings["GCC_PREPROCESSOR_DEFINITIONS"] = ["$(inherited)", "FUZZ=1", 'NAME=\\"x y\\"']
        if self.chance("conditional"):
            for key, value in self.random.sample(CONDITIONAL, self.random.choice([1, 2, 3])):
                settings[key] = value
        if self.chance("macros", 0.5):
            if "FUZZ_SIGN_STYLE" in project["settings"] or self.maybe(0.5):
                settings["CODE_SIGN_STYLE"] = "$(FUZZ_SIGN_STYLE)"
                if "FUZZ_SIGN_STYLE" not in project["settings"]:
                    settings["FUZZ_SIGN_STYLE"] = self.random.choice(["Manual", "Automatic", "manual"])
            elif self.maybe(0.5):
                target["attributes"]["ProvisioningStyle"] = self.random.choice(["Manual", "Automatic"])
        elif self.maybe(0.1):
            target["attributes"]["ProvisioningStyle"] = self.random.choice(["Manual", "Automatic"])
        target["settings"] = settings
        for config in project["configs"]:
            values = {}
            if config["name"] == "Release" and self.maybe(0.2):
                values.update({"CODE_SIGN_STYLE": "Manual", "PROVISIONING_PROFILE_SPECIFIER": "Fuzz Profile",
                               "CODE_SIGN_IDENTITY": "Apple Distribution"})
            if config["name"] not in ("Debug", "Release") and self.maybe(0.4) and "PRODUCT_BUNDLE_IDENTIFIER" in settings:
                values["PRODUCT_BUNDLE_IDENTIFIER"] = f"{settings['PRODUCT_BUNDLE_IDENTIFIER']}.{slug(config['name'])}"
            if self.maybe(0.15):
                values["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "$(inherited) TARGET_FLAG"
            if values:
                target["config_settings"].setdefault(config["name"], {}).update(values)
        if self.config_folder and self.maybe(0.25):
            xcconfig = {"id": self.ident("x"), "path": f"{self.config_folder['path']}/{slug(target['name'])}.xcconfig",
                        "lines": [{"include": self.config_folder["base"], "optional": False},
                                  {"set": "FUZZ_TARGET_SETTING", "value": "$(TARGET_NAME)"}]}
            if plist and self.maybe(0.5):
                xcconfig["lines"].append({"set": "INFOPLIST_FILE", "value": plist["path"]})
                target["settings"].pop("INFOPLIST_FILE", None)
            project["xcconfigs"].append(xcconfig)
            if self.config_folder["node"]["kind"] == "group":
                self.config_folder["node"]["children"].append({"id": self.ident("n"), "kind": "file", "path": Path(xcconfig["path"]).name,
                                                               "xcconfig": xcconfig["id"], "type": self.file_type("xcconfig")})
            for config in project["configs"]:
                if self.maybe(0.8):
                    target["bases"][config["name"]] = xcconfig["id"]

    def plist_setting(self, project, target, directory, plist):
        if not self.chance("macros", 0.6):
            return plist["path"]
        choices = [f"$(SRCROOT)/{plist['path']}", f"${{SRCROOT}}/{plist['path']}", f"$(PROJECT_DIR)/{plist['path']}"]
        if directory == target["name"]:
            choices.append("$(TARGET_NAME)/Info.plist")
        if target["product_name"] is None and directory == target["name"]:
            choices.append("$(PRODUCT_NAME)/Info.plist")
        roll = self.random.random()
        if roll < 0.2:
            target_settings_root = f"$(SRCROOT)/{directory}"
            target.setdefault("pending", {})["FUZZ_PLIST_ROOT"] = target_settings_root
            return "$(FUZZ_PLIST_ROOT)/Info.plist"
        if roll < 0.35 and project["configs"]:
            config = project["configs"][0]["name"]
            debug_plist = f"{directory}/Info-{slug(config)}.plist"
            project["disk_files"].append({"path": debug_plist, "kind": "plist", "corrupt": False, "on_disk": True,
                                          "values": {**plist["values"], "CFBundleIdentifier": f"org.nomac.fuzz.{slug(config)}"}})
            target["config_settings"].setdefault(config, {})["INFOPLIST_FILE"] = debug_plist
        if roll > 0.9:
            device_plist = f"{directory}/Info-Device.plist"
            project["disk_files"].append({"path": device_plist, "kind": "plist", "corrupt": False, "on_disk": True,
                                          "values": {**plist["values"], "CFBundleIdentifier": "org.nomac.fuzz.device"}})
            target.setdefault("pending", {})["INFOPLIST_FILE[sdk=iphoneos*]"] = device_plist
        return self.random.choice(choices)

    def phase(self, target, kind):
        for phase in target["phases"]:
            if phase["kind"] == kind:
                return phase
        phase = {"id": self.ident("ph"), "kind": kind, "files": []}
        target["phases"].append(phase)
        return phase

    def script_phase(self):
        return {"id": self.ident("ph"), "kind": "script", "files": [],
                "name": self.random.choice(["Run Script", "SwiftLint", 'Copy "Settings"', "Ünïcode Phase", None]),
                "shell": self.random.choice(["/bin/sh", "/bin/zsh", "/usr/bin/env python3"]),
                "script": self.random.choice(SCRIPTS),
                "inputs": self.random.choice([[], ["$(SRCROOT)/Input File.txt"], ["$(DERIVED_FILE_DIR)/in", "${PROJECT_DIR}/x"]]),
                "outputs": self.random.choice([[], ["$(DERIVED_FILE_DIR)/out.swift"]]),
                "input_lists": self.random.choice([[], ["$(SRCROOT)/inputs.xcfilelist"]]),
                "output_lists": self.random.choice([[], [], ["$(SRCROOT)/outputs.xcfilelist"]]),
                "always": self.maybe(0.3), "env": self.maybe(0.3), "deployment": self.maybe(0.1),
                "dependency_file": "$(DERIVED_FILE_DIR)/fuzz.d" if self.maybe(0.1) else None,
                "mask": self.random.choice([8, 12]) if self.real_phases and self.maybe(0.2) else None}

    def extra_phases(self, target):
        target["phases"].insert(self.random.randint(0, len(target["phases"])), self.script_phase())
        if self.maybe(0.4):
            spec = self.random.choice([(0, "/tmp/fuzz"), (1, ""), (6, ""), (7, "Fonts"), (10, ""), (12, "Support"),
                                       (13, ""), (16, "$(CONTENTS_FOLDER_PATH)/Library/LoginItems"), (15, "")])
            target["phases"].append({"id": self.ident("ph"), "kind": "copy", "dst_spec": spec[0], "dst_path": spec[1],
                                     "name": self.random.choice(["Copy Files", "Embed Fonts", None]), "files": [],
                                     "deployment": self.maybe(0.2),
                                     "mask": self.random.choice([8, 12]) if self.real_phases and self.maybe(0.2) else None,
                                     "dst_subfolder": self.random.choice(["PlugIns", "Frameworks", "Resources"]) if self.real_phases and self.maybe(0.15) else None})
        if self.maybe(0.15):
            target["phases"].append({"id": self.ident("ph"), "kind": "resources", "files": []})
        if self.maybe(0.1):
            self.random.shuffle(target["phases"])

    def rules(self, target, node):
        style = self.random.random()
        if style < 0.5:
            rule = {"id": self.ident("rl"), "name": None if self.maybe(0.5) else "Fuzz Rule", "file_type": "pattern.proxy",
                    "patterns": self.random.choice(["*.fuzz", "*.fuzz *.FUZZ", "Data*.fuzz"]),
                    "compiler": "com.apple.compilers.proxy.script", "script": 'cp "$INPUT_FILE_PATH" "$SCRIPT_OUTPUT_FILE_0"\n',
                    "outputs": ["$(DERIVED_FILE_DIR)/$(INPUT_FILE_BASE).swift"]}
        elif style < 0.8:
            rule = {"id": self.ident("rl"), "name": None, "file_type": self.random.choice(["sourcecode.c.c", "sourcecode.metal", "text.plist.strings", "file.xib"]),
                    "patterns": None, "compiler": "com.apple.compilers.proxy.script", "script": "true\n", "outputs": []}
        else:
            rule = {"id": self.ident("rl"), "name": None, "file_type": "sourcecode.c.objc", "patterns": None,
                    "compiler": self.random.choice(["com.apple.compilers.llvm.clang.1_0", "com.apple.compilers.gcc"]), "script": None, "outputs": []}
        target["rules"].append(rule)
        if node["kind"] == "sync":
            node["items"].append("Data.fuzz")
        else:
            file_node = {"id": self.ident("n"), "kind": "file", "path": "Data.fuzz", "name": None, "type": self.file_type("fuzz"), "on_disk": True}
            node["children"].append(file_node)
            self.phase(target, "sources")["files"].append({"id": self.ident("b"), "ref": file_node["id"]})

    def shared_files(self, project):
        users = [t for t in project["targets"] if t["kind"] not in ("aggregate", "legacy", "watchcontainer", "stickers")]
        if len(users) < 2 or not self.maybe(0.3):
            return
        chosen = self.random.sample(users, 2)
        name = self.unique(self.dirs, self.random.choice(["Shared", "Common Code"]))
        files = ["Constants.swift", "Shared.xcassets", f"{self.stem()}.swift"]
        if project["object_version"] >= 77 and self.chance("sync"):
            node = {"id": self.ident("n"), "kind": "sync", "path": name, "name": None, "items": files, "empty_dirs": [],
                    "hidden": [], "exceptions": [], "explicit_types": {}, "explicit_folders": []}
            owner, guest = chosen
            owner["sync"].append(node["id"])
            if self.maybe(0.5):
                guest["sync"].append(node["id"])
                if self.chance("sync-exceptions"):
                    node["exceptions"].append({"id": self.ident("e"), "kind": "build-file", "target": guest["id"],
                                               "membership": ["Shared.xcassets"], "public": [], "private": [], "flags": {},
                                               "attributes": {}, "platform_filters": {}})
            else:
                node["exceptions"].append({"id": self.ident("e"), "kind": "build-file", "target": guest["id"],
                                           "membership": ["Constants.swift"] + (["Gone.swift"] if self.chance("missing-files", 0.3) else []),
                                           "public": [], "private": [], "flags": {}, "attributes": {}, "platform_filters": {}})
                self.features.add("sync-exceptions")
            if self.chance("sync-phase-exceptions"):
                phase = self.phase(guest, "copy") if self.maybe(0.5) else self.phase(guest, "resources")
                if phase["kind"] == "copy":
                    phase.setdefault("dst_spec", 7)
                    phase.setdefault("dst_path", "")
                    phase.setdefault("name", "Copy Shared")
                    phase.setdefault("deployment", False)
                node["exceptions"].append({"id": self.ident("e"), "kind": "phase", "phase": phase["id"], "target": guest["id"],
                                           "membership": ["Constants.swift"], "attributes": {}})
            project["tree"].append(node)
        else:
            group = {"id": self.ident("n"), "kind": "group", "name": None, "path": name, "children": []}
            for file in files:
                ext = extension(file)
                node = {"id": self.ident("n"), "kind": "file", "path": file, "name": None, "type": self.file_type(ext), "on_disk": True}
                if self.maybe(0.15):
                    node["source_tree"] = "SOURCE_ROOT"
                    node["path"] = f"{name}/{file}"
                group["children"].append(node)
                for target in chosen:
                    phase = phase_for(ext, file, False)
                    if phase:
                        self.phase(target, phase)["files"].append({"id": self.ident("b"), "ref": node["id"]})
            project["tree"].append(group)

    def frameworks_group(self, project):
        if not self.maybe(0.35):
            return
        group = {"id": self.ident("n"), "kind": "group", "name": "Frameworks", "path": None, "children": []}
        for name, path, file_type in [("UIKit.framework", "System/Library/Frameworks/UIKit.framework", "wrapper.framework"),
                                      ("libz.tbd", "usr/lib/libz.tbd", "sourcecode.text-based-dylib-definition"),
                                      ("XCTest.framework", "Platforms/iPhoneOS.platform/Developer/Library/Frameworks/XCTest.framework", "wrapper.framework")]:
            if self.maybe(0.6):
                tree = "DEVELOPER_DIR" if name == "XCTest.framework" else "SDKROOT"
                node = {"id": self.ident("n"), "kind": "file", "path": path, "name": name, "type": file_type, "on_disk": False, "source_tree": tree}
                group["children"].append(node)
                users = [t for t in project["targets"] if t["kind"] in ("app", "framework", "unit")]
                if users:
                    build_file = {"id": self.ident("b"), "ref": node["id"]}
                    if self.maybe(0.3):
                        build_file["attributes"] = [self.random.choice(["Weak", "Required"]) if self.real_phases else "Weak"]
                    self.phase(self.random.choice(users), "frameworks")["files"].append(build_file)
        project["tree"].append(group)

    # Relationships ------------------------------------------------------------------------

    def embed(self, host, target, dst_spec, dst_path, name):
        phase = next((p for p in host["phases"] if p["kind"] == "copy" and p.get("dst_spec") == dst_spec and p.get("dst_path") == dst_path), None)
        if phase is None:
            phase = {"id": self.ident("ph"), "kind": "copy", "dst_spec": dst_spec, "dst_path": dst_path, "name": name, "files": [],
                     "deployment": False}
            host["phases"].append(phase)
        build_file = {"id": self.ident("b"), "ref": f"product:{target['id']}"}
        if self.maybe(0.8):
            build_file["attributes"] = ["RemoveHeadersOnCopy"] if target["kind"] in ("appex", "exkit", "clip", "watchapp", "watchapp2", "watchext", "stickers") else ["CodeSignOnCopy", "RemoveHeadersOnCopy"]
        if self.maybe(0.05):
            build_file["platforms"] = ["ios"]
        phase["files"].append(build_file)

    def depend(self, host, target):
        dependency = {"target": target["id"]}
        if self.maybe(0.04):
            dependency["platforms"] = self.random.choice([["ios"], ["ios", "maccatalyst"]])
        elif self.real_phases and self.maybe(0.05):
            dependency["platform"] = "ios"
        host["deps"].append(dependency)
        if self.real_phases and self.maybe(0.08):
            host["deps"].append({"target": target["id"], "duplicate": True})

    def wire(self, project):
        targets = project["targets"]
        ios_apps = [t for t in targets if t["kind"] == "app"]
        apps = [t for t in targets if t["kind"] in ("app", "macapp")]
        for target in targets:
            kind = target["kind"]
            target.setdefault("pending", {})
            if kind in ("framework", "static", "bundle", "dylib") and apps and self.maybe(0.85):
                host = self.random.choice(apps)
                self.depend(host, target)
                if kind in ("framework", "static", "dylib"):
                    self.phase(host, "frameworks")["files"].append({"id": self.ident("b"), "ref": f"product:{target['id']}"})
                if kind == "framework" and self.maybe(0.8):
                    self.embed(host, target, 10, "", "Embed Frameworks")
                if kind == "bundle":
                    self.phase(host, "resources")["files"].append({"id": self.ident("b"), "ref": f"product:{target['id']}"})
            elif kind in ("appex", "stickers") and ios_apps:
                host = self.random.choice(ios_apps)
                self.depend(host, target)
                self.embed(host, target, 13, "", "Embed Foundation Extensions")
            elif kind == "exkit" and ios_apps:
                host = self.random.choice(ios_apps)
                self.depend(host, target)
                self.embed(host, target, 16, "$(EXTENSIONS_FOLDER_PATH)", "Embed ExtensionKit Extensions")
            elif kind == "clip" and ios_apps:
                host = self.random.choice(ios_apps)
                self.depend(host, target)
                self.embed(host, target, 16, "$(CONTENTS_FOLDER_PATH)/AppClips", "Embed App Clips")
            elif kind == "watchapp" and ios_apps:
                host = ios_apps[0]
                self.depend(host, target)
                self.embed(host, target, 16, "$(CONTENTS_FOLDER_PATH)/Watch", "Embed Watch Content")
                target["settings_extra"] = {"INFOPLIST_KEY_WKCompanionAppBundleIdentifier": "org.nomac.fuzz.app"}
            elif kind == "watchext":
                host = next((t for t in targets if t["kind"] == "watchapp2"), None)
                if host:
                    self.depend(host, target)
                    self.embed(host, target, 13, "", "Embed App Extensions")
            elif kind == "watchapp2":
                host = next((t for t in targets if t["kind"] == "watchcontainer"), None) or (ios_apps[0] if ios_apps else None)
                if host:
                    self.depend(host, target)
                    self.embed(host, target, 16, "$(CONTENTS_FOLDER_PATH)/Watch", "Embed Watch Content")
            elif kind == "unit":
                hosts = [t for t in targets if t["kind"] in ("app", "macapp", "framework")]
                host = self.random.choice(hosts) if hosts else None
                if host is not None:
                    self.depend(target, host)
                    if host["kind"] in ("app", "macapp") and self.maybe(0.85):
                        product = host["product_name"] or host["name"]
                        variants = [f"$(BUILT_PRODUCTS_DIR)/{product}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/{product}",
                                    f"$(BUILT_PRODUCTS_DIR)/{product}.app/{product}", f"$(BUILT_PRODUCTS_DIR)/{product}.app",
                                    f"$(BUILT_PRODUCTS_DIR)/{product}.app/Contents/MacOS/{product}"]
                        weights = [4, 4, 1, 1] if host["kind"] == "app" else [3, 1, 1, 4]
                        test_host = self.random.choices(variants, weights)[0]
                        if self.maybe(0.15) and project["configs"]:
                            target["config_settings"].setdefault(project["configs"][0]["name"], {})["TEST_HOST"] = test_host
                        else:
                            target["settings"]["TEST_HOST"] = test_host
                        if self.maybe(0.8):
                            target["settings"]["BUNDLE_LOADER"] = "$(TEST_HOST)"
                    if self.maybe(0.7):
                        target["attributes"]["TestTargetID"] = host["id"]
            elif kind == "ui":
                host = self.random.choice(apps) if apps else None
                if host is not None:
                    self.depend(target, host)
                    target["settings"]["TEST_TARGET_NAME"] = host["name"]
                    if self.maybe(0.85):
                        target["attributes"]["TestTargetID"] = host["id"]
            elif kind == "aggregate":
                others = [t for t in targets if t is not target and t["kind"] not in ("aggregate",)]
                for other in self.random.sample(others, min(len(others), self.random.choice([0, 1, 2]))):
                    self.depend(target, other)
        for target in targets:
            target["settings"].update(target.pop("pending", {}))
            target["settings"].update(target.pop("settings_extra", {}))

    def project_reference(self, project, other):
        node = {"id": self.ident("n"), "kind": "project-ref", "project": other["id"]}
        project["tree"].append(node)
        reference = {"id": self.ident("pr"), "project": other["id"], "node": node["id"]}
        project["project_refs"].append(reference)
        frameworks = [t for t in other["targets"] if t["kind"] in ("framework", "static")]
        app = next((t for t in project["targets"] if t["kind"] in ("app", "macapp")), None)
        if frameworks and app:
            framework = frameworks[0]
            app["deps"].append({"target": framework["id"], "project": other["id"], "via": reference["id"]})
            self.phase(app, "frameworks")["files"].append({"id": self.ident("b"), "ref": f"proxy:{reference['id']}:{framework['id']}"})
            if framework["kind"] == "framework" and self.maybe(0.7):
                phase = next((p for p in app["phases"] if p["kind"] == "copy" and p.get("dst_spec") == 10), None)
                if phase is None:
                    phase = {"id": self.ident("ph"), "kind": "copy", "dst_spec": 10, "dst_path": "", "name": "Embed Frameworks",
                             "files": [], "deployment": False}
                    app["phases"].append(phase)
                phase["files"].append({"id": self.ident("b"), "ref": f"proxy:{reference['id']}:{framework['id']}",
                                       "attributes": ["CodeSignOnCopy", "RemoveHeadersOnCopy"]})
        self.features.add("cross-project")

    # Schemes ------------------------------------------------------------------------------

    def configs_for(self, project):
        names = [c["name"] for c in project["configs"]]
        debug = "Debug" if "Debug" in names else names[0]
        release = "Release" if "Release" in names else names[-1]
        launch = debug if self.maybe(0.8) else self.random.choice(names)
        if self.maybe(0.03):
            launch = "Missing Config"
        return {"test": launch if self.maybe(0.8) else debug, "launch": launch, "profile": release, "analyze": debug, "archive": release}

    def scheme(self, project, name, build=(), tests=(), launch=None, profile=None, launch_kind="product"):
        pid = project["id"]
        scheme = {"id": self.ident("sc"), "name": name, "user": False,
                  "build": [{"project": pid, "target": t["id"], "running": running} for t, running in build],
                  "tests": [{"project": pid, "target": t["id"], "skipped": self.maybe(0.1)} for t in tests],
                  "launch": {"project": pid, "target": launch["id"], "kind": launch_kind} if launch else None,
                  "profile": {"project": pid, "target": profile["id"], "kind": "product"} if profile else None,
                  "coverage": self.maybe(0.4), "plans": [], "configs": self.configs_for(project), "ask": False, "keys": self.scheme_keys()}
        return scheme

    def scheme_keys(self):
        if not self.real_schemes:
            return None
        return {"version": self.random.choice(["1.3", "1.3", "1.7", "1.8", "2.0"]), "extension": self.maybe(0.1), "analyze_no": self.maybe(0.1),
                "testing_no": self.maybe(0.03), "parallelize_no": self.maybe(0.05), "architectures": self.maybe(0.1), "actions": self.maybe(0.06),
                "test_macro": self.maybe(0.4), "args_env_no": self.maybe(0.05), "autocreate_plan": self.maybe(0.1), "coverage_targets": self.maybe(0.05),
                "parallelizable": self.random.choice([None, None, None, "YES", "NO"]), "ordering": self.maybe(0.03), "skipped": self.maybe(0.05),
                "options": self.maybe(0.3), "language": self.maybe(0.08), "lldb": self.maybe(0.03), "launch_flags": self.maybe(0.1),
                "custom_archive": self.maybe(0.02), "substyle": self.maybe(0.1), "remote_buildable": self.maybe(0.5)}

    def schemes(self, project):
        targets = project["targets"]
        apps = [t for t in targets if t["kind"] in APP_KINDS and t["kind"] != "watchcontainer"]
        tests = [t for t in targets if t["kind"] in ("unit", "ui")]
        others = [t for t in targets if t["kind"] not in APP_KINDS and t["kind"] not in ("unit", "ui")]
        used = set()
        result = []
        if self.chance("schemes"):
            for app in apps[:2]:
                if not self.maybe(0.8):
                    continue
                name = self.unique(used, app["name"] if self.maybe(0.8) else f"{app['name']} {self.random.choice(['Dev', 'Ünï', 'Prod'])}")
                build = [(app, True)] + [(t, self.maybe(0.5)) for t in others if self.maybe(0.2)]
                if self.maybe(0.15):
                    build = build[1:]
                hosted = [t for t in tests if self.maybe(0.8)]
                launch = app if self.maybe(0.85) else None
                scheme = self.scheme(project, name, build, hosted, launch, app if self.maybe(0.7) else None)
                if launch is None and self.maybe(0.5):
                    scheme["launch"] = {"project": project["id"], "target": app["id"], "kind": self.random.choice(["remote", "path"])}
                result.append(scheme)
            for other in others:
                if self.maybe(0.25):
                    host = apps[0] if apps else None
                    build = [(other, True)] + ([(host, True)] if host and self.maybe(0.6) else [])
                    launch_kind = "remote" if other["kind"] in ("appex", "exkit") and self.maybe(0.5) else "product"
                    launch = host if launch_kind == "product" and host and self.maybe(0.5) else (other if launch_kind == "remote" else None)
                    scheme = self.scheme(project, self.unique(used, other["name"]), build, [], launch, None, launch_kind)
                    scheme["ask"] = other["kind"] in ("appex", "exkit") and self.maybe(0.5)
                    result.append(scheme)
            if tests and self.maybe(0.3):
                result.append(self.scheme(project, self.unique(used, f"{tests[0]['name']} Only"), [], tests))
            if apps and self.maybe(0.1):
                result.append(self.scheme(project, self.unique(used, "BuildForTesting"), [(apps[0], False)], []))
            if apps and self.maybe(0.08):
                result.append(self.scheme(project, self.unique(used, "ProfileOnly"), [], [], None, apps[0]))
            if self.maybe(0.05):
                broken = self.scheme(project, self.unique(used, "Broken"))
                broken["build"].append({"project": project["id"], "target": "t-missing", "running": True})
                result.append(broken)
        if tests and result and self.chance("test-plans"):
            self.test_plans(project, result, tests)
        project["schemes"] = result
        if self.chance("user-schemes"):
            user = []
            for app in apps[:1] + others[:1]:
                scheme = self.scheme(project, self.unique(used, f"{app['name']}" if self.maybe(0.5) else f"{app['name']} (User)"),
                                     [(app, True)], [t for t in tests if self.maybe(0.5)], app if app["kind"] in APP_KINDS else None)
                scheme["user"] = True
                user.append(scheme)
            project["user_schemes"] = user
            if apps and self.maybe(0.3):
                other_user = self.scheme(project, self.unique(used, "Someone Else"), [(apps[0], True)], [], apps[0])
                other_user["user"] = True
                project["other_user_schemes"] = [other_user]
            if self.maybe(0.6):
                project["scheme_management"] = {"suppress": [t["id"] for t in targets if self.maybe(0.3)],
                                                "order": [s["name"] for s in result + user]}

    def test_plans(self, project, schemes, tests):
        folder = self.random.choice(["", "TestPlans/", "Tests Plans/" if self.odd else "Plans/"])
        plans = []
        for index in range(self.random.choice([1, 1, 2])):
            plans.append({"id": self.ident("tp"), "path": f"{folder}{project['name']}{'Tests' if index == 0 else 'More'}.xctestplan",
                          "tests": [{"project": project["id"], "target": t["id"]} for t in tests if self.maybe(0.8)],
                          "coverage": self.random.choice([None, True, False, "targets"]), "valid": not self.maybe(0.1),
                          "on_disk": not self.chance("missing-files", 0.1),
                          "keys": {key: self.maybe(rate) for key, rate in [("expansion", 0.3), ("environment", 0.2), ("arguments", 0.1), ("timeouts", 0.15), ("repetition", 0.1),
                                                                           ("language", 0.1), ("ordering", 0.1), ("skipped", 0.2), ("selected", 0.1), ("parallelizable", 0.2),
                                                                           ("disabled", 0.1)]} if self.chance("real-test-plan-keys") else None})
        project["test_plans"] = plans
        scheme = schemes[0]
        default_index = self.random.randrange(len(plans))
        scheme["plans"] = [{"plan": plan["id"], "default": index == default_index and self.maybe(0.9)} for index, plan in enumerate(plans)]
        if self.maybe(0.3):
            scheme["tests"] = []

    def workspace(self, spec):
        name = self.random.choice(["Workspace", "Fuzz", "All Projects" if self.odd else "AllProjects", spec["projects"][0]["name"]])
        items = [{"kind": "project", "project": p["id"], "group": "Libs" if index and self.maybe(0.3) else None}
                 for index, p in enumerate(spec["projects"])]
        if self.maybe(0.2):
            self.random.shuffle(items)
        for package in spec["packages"]:
            if package.pop("in_workspace", False):
                items.append({"kind": "package", "package": package["id"], "group": None})
        if self.real_missing and self.maybe(0.5):
            items.append({"kind": "raw", "location": "group:Pods/Pods.xcodeproj", "group": None})
        if self.real_types:
            if self.maybe(0.2):
                items.append({"kind": "raw", "location": "group:Podfile", "content": "platform :ios, '15.0'\n", "group": None})
            if self.maybe(0.1):
                items.append({"kind": "raw", "location": "group:Sandbox.playground", "playground": True, "group": "Docs"})
            for item in items:
                if item["kind"] == "project" and self.maybe(0.15):
                    item["scheme"] = "container"
        schemes = []
        if self.chance("schemes"):
            buildable = [(p, t) for p in spec["projects"] for t in p["targets"] if t["kind"] not in ("aggregate", "legacy")]
            if buildable:
                chosen = self.random.sample(buildable, min(len(buildable), self.random.choice([1, 2, 3])))
                launch = next(((p, t) for p, t in chosen if t["kind"] in ("app", "macapp")), None)
                scheme = {"id": self.ident("sc"), "name": self.random.choice(["Everything", "All", name]), "user": False,
                          "build": [{"project": p["id"], "target": t["id"], "running": True} for p, t in chosen],
                          "tests": [{"project": p["id"], "target": t["id"], "skipped": False} for p, t in buildable
                                    if t["kind"] in ("unit", "ui") and self.maybe(0.5)],
                          "launch": {"project": launch[0]["id"], "target": launch[1]["id"], "kind": "product"} if launch else None,
                          "profile": None, "coverage": self.maybe(0.5), "plans": [],
                          "configs": self.configs_for(spec["projects"][0]), "ask": False, "keys": self.scheme_keys()}
                if spec["packages"] and self.maybe(0.3):
                    package = spec["packages"][0]
                    scheme["build"].append({"package": package["id"], "product": package["products"][0]["name"], "running": True})
                schemes.append(scheme)
        return {"name": name, "items": items, "schemes": schemes, "files": self.workspace_files(), "group_location": "group:" if self.real_types and self.maybe(0.2) else "container:"}


def phase_for(ext, name, headers_phase):
    if name == "Info.plist":
        return None
    if ext in SOURCE_EXTS:
        return "sources"
    if ext in HEADER_EXTS:
        return "headers" if headers_phase else None
    if ext in FRAMEWORK_EXTS:
        return "frameworks"
    if ext in UNBUILT_EXTS:
        return None
    return "resources"


# ---------------------------------------------------------------------------------------------
# Renderer: writes a spec's projects, workspace, packages and files under a directory.

SAFE_STRING = re.compile(r"^[A-Za-z0-9_$/:.\-]+$")


def pbx_quote(value):
    text = str(value)
    if SAFE_STRING.match(text) and "//" not in text and "___" not in text:
        return text
    escaped = text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")
    return f'"{escaped}"'


def pbx_value(value, depth):
    tabs = "\t" * depth
    if isinstance(value, dict):
        inner = "".join(f"{tabs}\t{pbx_quote(key)} = {pbx_value(item, depth + 1)};\n" for key, item in value.items())
        return "{\n" + inner + tabs + "}"
    if isinstance(value, list):
        inner = "".join(f"{tabs}\t{pbx_value(item, depth + 1)},\n" for item in value)
        return "(\n" + inner + tabs + ")"
    return pbx_quote(value)


def object_id(owner, key):
    digest = hashlib.md5(f"{owner}/{key}".encode()).hexdigest()
    return f"OBJ_{int(digest[:8], 16)}" if owner.endswith("~obj") else digest[:24].upper()


def identifier(text):
    ascii_text = re.sub(r"\W", "_", unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode())
    return ("_" + ascii_text) if not ascii_text or ascii_text[0].isdigit() else ascii_text


def plist_bytes(values):
    return plistlib.dumps(values, sort_keys=False)


XML_DOCUMENT = '<?xml version="1.0" encoding="UTF-8"?>\n<root/>\n'
IB_DOCUMENT = ('<?xml version="1.0" encoding="UTF-8"?>\n<document type="com.apple.InterfaceBuilder3.CocoaTouch.{}.XIB" '
               'version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch"/>\n')


def file_bytes(name):
    ext = extension(name)
    stem = name.rsplit("/", 1)[-1].rsplit(".", 1)[0]
    if ext == "swift":
        return f"import Foundation\n\nenum {identifier(stem)} {{}}\n".encode()
    if ext in ("m", "mm"):
        return b"#import <Foundation/Foundation.h>\n"
    if ext in ("c", "cpp", "cc", "l", "y", "iig"):
        return b"int fuzz(void) { return 0; }\n"
    if ext in HEADER_EXTS or ext == "pch":
        return b"#pragma once\n"
    if ext == "metal":
        return b"#include <metal_stdlib>\n"
    if ext in ("storyboard", "xib"):
        return IB_DOCUMENT.format("Storyboard" if ext == "storyboard" else "").encode()
    if ext == "strings":
        return b'"key" = "value";\n'
    if ext in ("stringsdict", "plist", "entitlements", "intentdefinition", "xcprivacy"):
        return plist_bytes({"FuzzKey": stem})
    if ext in ("xcstrings",):
        return b'{\n  "sourceLanguage" : "en",\n  "strings" : {},\n  "version" : "1.0"\n}\n'
    if ext in ("json", "geojson"):
        return b"{}\n"
    if ext in ("opml", "sdef", "xml", "svg", "gpx"):
        return XML_DOCUMENT.encode()
    if ext in BINARY_TYPES:
        return b"\x89FUZZ\x00" + name.encode()
    if ext == "html":
        return b"<html></html>\n"
    if ext == "xcconfig":
        return b"FUZZ_RESOURCE_XCCONFIG = YES\n"
    return f"{name}\n".encode()


def directory_contents(ext, stem):
    contents = '{\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n'
    return {
        "xcassets": {"Contents.json": contents, "AccentColor.colorset/Contents.json": contents, "AppIcon.appiconset/Contents.json": contents},
        "docc": {f"{stem}.md": f"# ``{stem}``\n"},
        "bundle": {"Info.plist": plist_bytes({"CFBundleIdentifier": "org.nomac.bundle"}), "data.txt": "data\n"},
        "framework": {"Info.plist": plist_bytes({"CFBundleIdentifier": "org.nomac.framework"}), "Headers/Fuzz.h": "#pragma once\n"},
        "xcframework": {"Info.plist": plist_bytes({"XCFrameworkFormatVersion": "1.0", "AvailableLibraries": []})},
        "scnassets": {"model.scn": b"\x89FUZZ"},
        "icon": {"icon.json": "{}\n"},
        "mlpackage": {"Manifest.json": "{}\n"},
        "xcstickers": {"Contents.json": contents, "Sticker Pack.stickerpack/Contents.json": contents},
        "playground": {"contents.xcplayground": XML_DOCUMENT, "Contents.swift": "import Foundation\n"},
        "xcdatamodeld": {"Model.xcdatamodel/contents": XML_DOCUMENT},
        "xcmappingmodel": {"xcmapping.xml": XML_DOCUMENT},
    }[ext]


def write_item(path, versions=None):
    ext = extension(path.name)
    if ext in DIRECTORY_TYPES:
        path.mkdir(parents=True, exist_ok=True)
        contents = directory_contents(ext, path.name.rsplit(".", 1)[0])
        if ext == "xcdatamodeld" and versions:
            contents = {f"{version}.xcdatamodel/contents": XML_DOCUMENT for version in versions}
            contents[".xccurrentversion"] = plist_bytes({"_XCCurrentVersionName": f"{versions[-1]}.xcdatamodel"})
        for relative, data in contents.items():
            target = path / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data if isinstance(data, bytes) else data.encode())
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(file_bytes(path.name))


def xcconfig_text(xcconfig, by_id, project_dir):
    lines = []
    here = (project_dir / xcconfig["path"]).parent
    for line in xcconfig["lines"]:
        if "comment" in line:
            lines.append(f"// {line['comment']}")
        elif "include" in line:
            other = by_id.get(line["include"])
            if other:
                lines.append(f'#include{"?" if line["optional"] else ""} "{os.path.relpath(project_dir / other["path"], here)}"')
        elif "include_path" in line:
            lines.append(f'#include{"?" if line["optional"] else ""} "{line["include_path"]}"')
        else:
            value = line["value"]
            lines.append(f"{line['set']} = {' '.join(value) if isinstance(value, list) else value}")
    return "\n".join(lines) + "\n"


def product_file(target):
    _, file_type, pattern = PRODUCTS[target["kind"]]
    return file_type, pattern.format(target["product_name"] or target["name"])


def find_project(spec, pid):
    return next((p for p in spec["projects"] if p["id"] == pid), None)


def find_target(project, tid):
    return next((t for t in project["targets"] if t["id"] == tid), None) if project else None


class ProjectRenderer:
    def __init__(self, spec, project, root, user):
        self.spec = spec
        self.project = project
        self.root = root
        self.user = user
        self.dir = root / project["dir"] if project["dir"] else root
        self.objects = {}
        self.nodes = {}
        self.node_dirs = {}
        self.xcconfig_nodes = {}
        self.targets = {t["id"]: t for t in project["targets"]}
        self.packages = {k["id"]: k for k in spec["packages"]}
        self.xcconfigs = {x["id"]: x for x in project["xcconfigs"]}

    def oid(self, key):
        return object_id(self.project["id"], key)

    def add(self, key, fields):
        identifier_ = self.oid(key)
        self.objects[identifier_] = fields
        return identifier_

    def render(self):
        self.dir.mkdir(parents=True, exist_ok=True)
        for xcconfig in self.project["xcconfigs"]:
            if not xcconfig.get("on_disk", True):
                continue
            path = self.dir / xcconfig["path"]
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(xcconfig_text(xcconfig, self.xcconfigs, self.dir))
        for disk_file in self.project["disk_files"]:
            if not disk_file.get("on_disk", True):
                continue
            path = self.dir / disk_file["path"]
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"<?xml version=\"1.0\"?><plist><dict><key>broken" if disk_file.get("corrupt") else plist_bytes(disk_file["values"]))
        children = [c for c in (self.node(node, self.dir) for node in self.project["tree"]) if c]
        products = [self.product_reference(t) for t in self.project["targets"] if t["kind"] in PRODUCTS]
        products_group = self.add("products-group", {"isa": "PBXGroup", "children": products, "name": "Products", "sourceTree": "<group>"})
        main = self.add("main-group", {"isa": "PBXGroup", "children": children + [products_group], "sourceTree": "<group>"})
        targets = [self.target(t) for t in self.project["targets"]]
        project_fields = self.project_object(main, products_group, targets)
        self.objects[self.oid("project")] = project_fields
        path = self.dir / f"{self.project['name']}.xcodeproj"
        path.mkdir(parents=True, exist_ok=True)
        (path / "project.pbxproj").write_text(self.serialize(), encoding="utf-8")
        if self.project["embedded_workspace"]:
            embedded = path / "project.xcworkspace"
            embedded.mkdir(exist_ok=True)
            (embedded / "contents.xcworkspacedata").write_text(
                '<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n   <FileRef\n      location = "self:">\n   </FileRef>\n</Workspace>\n')
        write_workspace_files(path / "project.xcworkspace", self.project.get("workspace_files"), self.user)
        self.write_schemes(path)
        self.write_test_plans()
        return path

    def serialize(self):
        sections = collections.defaultdict(list)
        for key, fields in self.objects.items():
            sections[fields["isa"]].append((key, fields))
        body = ""
        for isa in sorted(sections):
            body += f"\n/* Begin {isa} section */\n"
            for key, fields in sorted(sections[isa]):
                ordered = {"isa": fields["isa"], **{k: fields[k] for k in sorted(fields) if k != "isa"}}
                body += f"\t\t{key} = {pbx_value(ordered, 2)};\n"
            body += f"/* End {isa} section */\n"
        return (f"// !$*UTF8*$!\n{{\n\tarchiveVersion = 1;\n\tclasses = {{\n\t}};\n\tobjectVersion = {self.project['object_version']};\n"
                f"\tobjects = {{\n{body}\t}};\n\trootObject = {self.oid('project')};\n}}\n")

    def file_node_fields(self, node):
        fields = {"isa": "PBXFileReference", "path": node["path"], "sourceTree": node.get("source_tree", "<group>")}
        if node.get("type"):
            fields["explicitFileType" if node.get("explicit") else "lastKnownFileType"] = node["type"]
        if node.get("name"):
            fields["name"] = node["name"]
        if node.get("encoding"):
            fields["fileEncoding"] = node["encoding"]
        if node.get("explicit"):
            fields["includeInIndex"] = 0
        fields.update(node.get("extras") or {})
        return fields

    def node(self, node, group_dir):
        kind = node["kind"]
        if kind == "group":
            if node.get("source_tree") == "SOURCE_ROOT":
                directory = self.dir / (node.get("path") or "")
            else:
                directory = group_dir / node["path"] if node.get("path") else group_dir
            children = [c for c in (self.node(child, directory) for child in node["children"]) if c]
            fields = {"isa": "PBXGroup", "children": children, "sourceTree": node.get("source_tree", "<group>")}
            if node.get("name"):
                fields["name"] = node["name"]
            if node.get("path"):
                fields["path"] = node["path"]
            fields.update(node.get("extras") or {})
        elif kind == "file":
            fields = self.file_node_fields(node)
            tree = node.get("source_tree", "<group>")
            disk = group_dir / node["path"] if tree == "<group>" else (self.dir / node["path"] if tree == "SOURCE_ROOT" else None)
            if node.get("xcconfig"):
                xcconfig = self.xcconfigs.get(node["xcconfig"])
                if xcconfig is None:
                    return None
                fields["path"] = os.path.relpath(self.dir / xcconfig["path"], group_dir)
            elif disk is not None and node.get("on_disk", True):
                if "folder_items" in node:
                    for item in node["folder_items"]:
                        write_item(disk / item)
                else:
                    write_item(disk)
        elif kind == "version":
            versions = node.get("versions") or ["Model"]
            path = group_dir / node["path"]
            if node.get("on_disk", True):
                write_item(path, versions)
            version_ids = [self.add(f"{node['id']}/{v}", {"isa": "PBXFileReference", "lastKnownFileType": "wrapper.xcdatamodel",
                                                          "path": f"{v}.xcdatamodel", "sourceTree": "<group>"}) for v in versions]
            fields = {"isa": "XCVersionGroup", "children": version_ids, "currentVersion": version_ids[-1], "path": node["path"],
                      "sourceTree": "<group>", "versionGroupType": "wrapper.xcdatamodel"}
            if node.get("name"):
                fields["name"] = node["name"]
        elif kind == "variant":
            children = []
            variant_dir = group_dir / node["path"] if node.get("path") else group_dir
            for child in node["children"]:
                if child.get("on_disk", True):
                    write_item(variant_dir / child["path"])
                children.append(self.add(child["id"], {"isa": "PBXFileReference", "name": child["region"], "path": child["path"],
                                                       "sourceTree": "<group>", "lastKnownFileType": KNOWN_TYPES.get(extension(child["path"]), "text")}))
            if not children:
                return None
            fields = {"isa": "PBXVariantGroup", "children": children, "name": node["name"], "sourceTree": "<group>"}
            if node.get("path"):
                fields["path"] = node["path"]
        elif kind == "sync":
            fields = self.sync_node(node, group_dir)
        elif kind == "package":
            package = self.packages.get(node["package"])
            if package is None:
                return None
            fields = {"isa": "PBXFileReference", "lastKnownFileType": "wrapper", "name": package["name"],
                      "path": os.path.relpath(self.root / package["dir"], group_dir), "sourceTree": "<group>"}
        elif kind == "project-ref":
            other = find_project(self.spec, node["project"])
            if other is None:
                return None
            other_dir = self.root / other["dir"] if other["dir"] else self.root
            fields = {"isa": "PBXFileReference", "lastKnownFileType": "wrapper.pb-project", "name": f"{other['name']}.xcodeproj",
                      "path": os.path.relpath(other_dir / f"{other['name']}.xcodeproj", group_dir), "sourceTree": "<group>"}
        else:
            raise ValueError(f"unknown node kind {kind}")
        self.nodes[node["id"]] = self.add(node["id"], fields)
        if node.get("xcconfig"):
            self.xcconfig_nodes[node["xcconfig"]] = self.nodes[node["id"]]
        return self.nodes[node["id"]]

    def sync_node(self, node, group_dir):
        directory = group_dir / node["path"]
        self.node_dirs[node["id"]] = directory
        directory.mkdir(parents=True, exist_ok=True)
        for item in node["items"]:
            write_item(directory / item)
        for folder in node["empty_dirs"]:
            (directory / folder).mkdir(parents=True, exist_ok=True)
        for hidden in node["hidden"]:
            (directory / hidden).write_text("hidden\n")
        exceptions = []
        for exception in node["exceptions"]:
            if exception["target"] not in self.targets:
                continue
            if exception["kind"] == "phase":
                target = self.targets[exception["target"]]
                if not any(p["id"] == exception["phase"] for p in target["phases"]):
                    continue
                fields = {"isa": "PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet",
                          "buildPhase": self.oid(exception["phase"]), "membershipExceptions": exception["membership"]}
                if exception.get("attributes"):
                    fields["attributesByRelativePath"] = exception["attributes"]
            else:
                fields = {"isa": "PBXFileSystemSynchronizedBuildFileExceptionSet", "target": self.oid(exception["target"])}
                for key, name in [("membership", "membershipExceptions"), ("public", "publicHeaders"), ("private", "privateHeaders"),
                                  ("flags", "additionalCompilerFlagsByRelativePath"), ("attributes", "attributesByRelativePath"),
                                  ("platform_filters", "platformFiltersByRelativePath")]:
                    if exception.get(key):
                        fields[name] = exception[key]
                if len(fields) == 2:
                    continue
            exceptions.append(self.add(exception["id"], fields))
        fields = {"isa": "PBXFileSystemSynchronizedRootGroup", "path": node["path"], "sourceTree": "<group>"}
        if exceptions:
            fields["exceptions"] = exceptions
        if node.get("name"):
            fields["name"] = node["name"]
        if node["explicit_types"]:
            fields["explicitFileTypes"] = node["explicit_types"]
        if node["explicit_folders"]:
            fields["explicitFolders"] = node["explicit_folders"]
        return fields

    def product_reference(self, target):
        file_type, name = product_file(target)
        return self.add(f"product:{target['id']}", {"isa": "PBXFileReference", "explicitFileType": file_type, "includeInIndex": 0,
                                                    "path": name, "sourceTree": "BUILT_PRODUCTS_DIR"})

    def configuration_list(self, owner, common, per_config, bases, default):
        identifiers = []
        names = [c["name"] for c in self.project["configs"]]
        for config in self.project["configs"]:
            values = dict(common)
            values.update(per_config(config))
            fields = {"isa": "XCBuildConfiguration", "buildSettings": values, "name": config["name"]}
            base = self.xcconfigs.get(bases.get(config["name"]))
            if base and base["id"] in self.xcconfig_nodes:
                fields["baseConfigurationReference"] = self.xcconfig_nodes[base["id"]]
            elif base:
                anchor = next((node for node, directory in self.node_dirs.items() if (self.dir / base["path"]).is_relative_to(directory)), None)
                if anchor:
                    fields["baseConfigurationReferenceAnchor"] = self.nodes[anchor]
                    fields["baseConfigurationReferenceRelativePath"] = os.path.relpath(self.dir / base["path"], self.node_dirs[anchor])
            identifiers.append(self.add(f"{owner}/config/{config['name']}", fields))
        return self.add(f"{owner}/configurations", {"isa": "XCConfigurationList", "buildConfigurations": identifiers,
                                                    "defaultConfigurationIsVisible": 0,
                                                    "defaultConfigurationName": default if default in names else names[0]})

    def build_file(self, target, build_file):
        ref = build_file["ref"]
        fields = {"isa": "PBXBuildFile"}
        if ref.startswith("product:"):
            other = self.targets.get(ref[len("product:"):])
            if other is None or other["kind"] not in PRODUCTS:
                return None
            fields["fileRef"] = self.oid(ref)
        elif ref.startswith("pkg:"):
            dependency = next((d for d in target["package_products"] if d["id"] == ref[4:]), None)
            if dependency is None or dependency["package"] not in self.packages:
                return None
            fields["productRef"] = self.oid(dependency["id"])
        elif ref.startswith("gone:"):
            _, reference_id, index = ref.split(":")
            reference = next((r for r in self.project["project_refs"] if r["id"] == reference_id), None)
            if reference is None or reference["node"] not in self.nodes:
                return None
            fields["fileRef"] = self.oid(f"{reference_id}/proxy/{index}")
        elif ref.startswith("proxy:"):
            _, reference_id, tid = ref.split(":")
            reference = next((r for r in self.project["project_refs"] if r["id"] == reference_id), None)
            other = find_project(self.spec, reference["project"]) if reference else None
            if not find_target(other, tid) or reference["node"] not in self.nodes:
                return None
            fields["fileRef"] = self.oid(f"{reference_id}/proxy/{tid}")
        else:
            if ref not in self.nodes:
                return None
            fields["fileRef"] = self.nodes[ref]
        settings = {}
        if build_file.get("attributes"):
            settings["ATTRIBUTES"] = build_file["attributes"]
        if build_file.get("flags"):
            settings["COMPILER_FLAGS"] = build_file["flags"]
        if build_file.get("asset_tags"):
            settings["ASSET_TAGS"] = build_file["asset_tags"]
        if settings:
            fields["settings"] = settings
        if build_file.get("platforms"):
            fields["platformFilters"] = build_file["platforms"]
        if build_file.get("platform"):
            fields["platformFilter"] = build_file["platform"]
        return self.add(build_file["id"], fields)

    def phase(self, target, phase):
        files = [f for f in (self.build_file(target, b) for b in phase["files"]) if f]
        common = {"buildActionMask": phase.get("mask") or 2147483647, "files": files, "runOnlyForDeploymentPostprocessing": 1 if phase.get("deployment") else 0}
        kind = phase["kind"]
        if kind == "copy":
            fields = {"isa": "PBXCopyFilesBuildPhase", **common, "dstPath": phase.get("dst_path", "")}
            if phase.get("dst_subfolder"):
                fields["dstSubfolder"] = phase["dst_subfolder"]
            else:
                fields["dstSubfolderSpec"] = phase.get("dst_spec", 7)
            if phase.get("name"):
                fields["name"] = phase["name"]
        elif kind == "script":
            fields = {"isa": "PBXShellScriptBuildPhase", **common, "inputFileListPaths": phase["input_lists"], "inputPaths": phase["inputs"],
                      "outputFileListPaths": phase["output_lists"], "outputPaths": phase["outputs"], "shellPath": phase["shell"],
                      "shellScript": phase["script"]}
            if phase.get("name"):
                fields["name"] = phase["name"]
            if phase.get("always"):
                fields["alwaysOutOfDate"] = 1
            if phase.get("env"):
                fields["showEnvVarsInLog"] = 0
            if phase.get("dependency_file"):
                fields["dependencyFile"] = phase["dependency_file"]
        else:
            isa = {"sources": "PBXSourcesBuildPhase", "frameworks": "PBXFrameworksBuildPhase", "resources": "PBXResourcesBuildPhase",
                   "headers": "PBXHeadersBuildPhase"}[kind]
            fields = {"isa": isa, **common}
        return self.add(phase["id"], fields)

    def dependency(self, target, dependency):
        if dependency.get("gone"):
            reference = next((r for r in self.project["project_refs"] if r["id"] == dependency["gone"]), None)
            if reference is None or reference["node"] not in self.nodes:
                return None
            proxy = self.add(f"{target['id']}/proxy/{dependency['gone']}", {
                "isa": "PBXContainerItemProxy", "containerPortal": self.nodes[reference["node"]], "proxyType": 1,
                "remoteGlobalIDString": object_id(dependency["gone"], "gone-target"), "remoteInfo": dependency["name"]})
            return self.add(f"{target['id']}/dependency/{dependency['gone']}", {"isa": "PBXTargetDependency", "name": dependency["name"], "targetProxy": proxy})
        if dependency.get("project"):
            reference = next((r for r in self.project["project_refs"] if r["id"] == dependency.get("via")), None)
            other = find_project(self.spec, dependency["project"])
            remote = find_target(other, dependency["target"])
            if reference is None or remote is None or reference["node"] not in self.nodes:
                return None
            proxy = self.add(f"{target['id']}/proxy/{dependency['target']}", {
                "isa": "PBXContainerItemProxy", "containerPortal": self.nodes[reference["node"]], "proxyType": 1,
                "remoteGlobalIDString": object_id(other["id"], remote["id"]), "remoteInfo": remote["name"]})
            return self.add(f"{target['id']}/dependency/{dependency['target']}", {"isa": "PBXTargetDependency", "name": remote["name"], "targetProxy": proxy})
        other = self.targets.get(dependency["target"])
        if other is None or other is target:
            return None
        suffix = "/duplicate" if dependency.get("duplicate") else ""
        proxy = self.add(f"{target['id']}/proxy/{other['id']}{suffix}", {
            "isa": "PBXContainerItemProxy", "containerPortal": self.oid("project"), "proxyType": 1,
            "remoteGlobalIDString": self.oid(other["id"]), "remoteInfo": other["name"]})
        fields = {"isa": "PBXTargetDependency", "target": self.oid(other["id"]), "targetProxy": proxy}
        if dependency.get("platforms"):
            fields["platformFilters"] = dependency["platforms"]
        if dependency.get("platform"):
            fields["platformFilter"] = dependency["platform"]
        return self.add(f"{target['id']}/dependency/{other['id']}{suffix}", fields)

    def rule(self, rule):
        fields = {"isa": "PBXBuildRule", "compilerSpec": rule["compiler"], "fileType": rule["file_type"], "inputFiles": [],
                  "isEditable": 1, "outputFiles": rule["outputs"]}
        if rule.get("patterns"):
            fields["filePatterns"] = rule["patterns"]
        if rule.get("name"):
            fields["name"] = rule["name"]
        if rule.get("script") is not None:
            fields["script"] = rule["script"]
        return self.add(rule["id"], fields)

    def target(self, target):
        kind = target["kind"]
        configurations = self.configuration_list(target["id"], target["settings"],
                                                 lambda config: target["config_settings"].get(config["name"], {}),
                                                 target["bases"], target.get("default_config", self.project["default_config"]))
        phases = [self.phase(target, p) for p in target["phases"]]
        dependencies = [d for d in (self.dependency(target, d) for d in target["deps"]) if d]
        if kind == "aggregate":
            fields = {"isa": "PBXAggregateTarget", "buildConfigurationList": configurations, "buildPhases": phases,
                      "dependencies": dependencies, "name": target["name"], "productName": target["name"]}
        elif kind == "legacy":
            legacy = target.get("legacy") or {"tool": "/usr/bin/make", "arguments": "$(ACTION)", "directory": "", "pass": True}
            fields = {"isa": "PBXLegacyTarget", "buildArgumentsString": legacy["arguments"], "buildConfigurationList": configurations,
                      "buildPhases": [], "buildToolPath": legacy["tool"], "buildWorkingDirectory": legacy["directory"],
                      "dependencies": dependencies, "name": target["name"], "passBuildSettingsInEnvironment": 1 if legacy["pass"] else 0,
                      "productName": target["name"]}
        else:
            products = []
            for dependency in target["package_products"]:
                package = self.packages.get(dependency["package"])
                if package is None:
                    continue
                fields = {"isa": "XCSwiftPackageProductDependency", "productName": dependency["product"]}
                reference = next((r for r in self.project["package_refs"] if r["package"] == package["id"]), None)
                if reference:
                    fields["package"] = self.oid(reference["id"])
                products.append(self.add(dependency["id"], fields))
            fields = {"isa": "PBXNativeTarget", "buildConfigurationList": configurations, "buildPhases": phases,
                      "buildRules": [self.rule(r) for r in target["rules"]], "dependencies": dependencies, "name": target["name"],
                      "productName": target["product_name"] or target["name"], "productReference": self.oid(f"product:{target['id']}"),
                      "productType": f"com.apple.product-type.{PRODUCTS[kind][0]}"}
            synchronized = [self.nodes[s] for s in target["sync"] if s in self.nodes]
            if synchronized and self.project["object_version"] >= 70:
                fields["fileSystemSynchronizedGroups"] = synchronized
            if products:
                fields["packageProductDependencies"] = products
        return self.add(target["id"], fields)

    def project_object(self, main, products_group, targets):
        project = self.project
        attributes = dict(project["attributes"])
        attributes["LastUpgradeCheck"] = "1600"
        attributes["LastSwiftUpdateCheck"] = "1600"
        if project.get("class_prefix"):
            attributes["CLASSPREFIX"] = project["class_prefix"]
        target_attributes = {}
        for target in project["targets"]:
            values = dict(target["attributes"])
            if "TestTargetID" in values:
                if values["TestTargetID"] in self.targets:
                    values["TestTargetID"] = self.oid(values["TestTargetID"])
                else:
                    del values["TestTargetID"]
            if values:
                target_attributes[self.oid(target["id"])] = values
        if target_attributes:
            attributes["TargetAttributes"] = target_attributes
        configurations = self.configuration_list("project", project["settings"], lambda config: config["settings"],
                                                 {c["name"]: c["base"] for c in project["configs"]}, project["default_config"])
        fields = {"isa": "PBXProject", "attributes": attributes, "buildConfigurationList": configurations,
                  "developmentRegion": project["development_region"], "hasScannedForEncodings": 0,
                  "knownRegions": project["regions"], "mainGroup": main, "productRefGroup": products_group,
                  "projectDirPath": "", "projectRoot": "", "targets": targets}
        if project["object_version"] >= 77:
            fields["minimizedProjectReferenceProxies"] = 1
            fields["preferredProjectObjectVersion"] = 77
        else:
            fields["compatibilityVersion"] = "Xcode 3.2" if project["object_version"] <= 46 else "Xcode 14.0"
        references = []
        for reference in project["package_refs"]:
            package = self.packages.get(reference["package"])
            if package and package.get("remote"):
                requirement = dict(package["remote"], **({"revision": package["revision"]} if package["remote"]["kind"] == "revision" else {}))
                references.append(self.add(reference["id"], {"isa": "XCRemoteSwiftPackageReference", "repositoryURL": f"file://{self.root / package['dir']}",
                                                             "requirement": requirement}))
            elif package:
                references.append(self.add(reference["id"], {"isa": "XCLocalSwiftPackageReference",
                                                             "relativePath": os.path.relpath(self.root / package["dir"], self.dir)}))
        if references:
            fields["packageReferences"] = references
        project_references = []
        for reference in project["project_refs"]:
            if reference.get("missing"):
                if reference["node"] not in self.nodes:
                    continue
                proxies = []
                for index, product in enumerate(reference["products"]):
                    item = self.add(f"{reference['id']}/remote/{index}", {
                        "isa": "PBXContainerItemProxy", "containerPortal": self.nodes[reference["node"]], "proxyType": 2,
                        "remoteGlobalIDString": object_id(reference["id"], f"gone-{index}"), "remoteInfo": Path(product["path"]).stem})
                    proxies.append(self.add(f"{reference['id']}/proxy/{index}", {
                        "isa": "PBXReferenceProxy", "fileType": product["type"], "path": product["path"], "remoteRef": item, "sourceTree": "BUILT_PRODUCTS_DIR"}))
                group = self.add(f"{reference['id']}/products", {"isa": "PBXGroup", "children": proxies, "name": "Products", "sourceTree": "<group>"})
                project_references.append({"ProductGroup": group, "ProjectRef": self.nodes[reference["node"]]})
                continue
            other = find_project(self.spec, reference["project"])
            if other is None or reference["node"] not in self.nodes:
                continue
            proxies = []
            for remote in other["targets"]:
                if remote["kind"] not in PRODUCTS:
                    continue
                file_type, name = product_file(remote)
                item = self.add(f"{reference['id']}/remote/{remote['id']}", {
                    "isa": "PBXContainerItemProxy", "containerPortal": self.nodes[reference["node"]], "proxyType": 2,
                    "remoteGlobalIDString": object_id(other["id"], f"product:{remote['id']}"), "remoteInfo": remote["name"]})
                proxies.append(self.add(f"{reference['id']}/proxy/{remote['id']}", {
                    "isa": "PBXReferenceProxy", "fileType": file_type, "path": name, "remoteRef": item, "sourceTree": "BUILT_PRODUCTS_DIR"}))
            group = self.add(f"{reference['id']}/products", {"isa": "PBXGroup", "children": proxies, "name": "Products", "sourceTree": "<group>"})
            project_references.append({"ProductGroup": group, "ProjectRef": self.nodes[reference["node"]]})
        if project_references:
            fields["projectReferences"] = project_references
        return fields

    def buildable(self, entry, container_dir):
        if "package" in entry:
            package = self.packages.get(entry["package"])
            if package is None:
                return None
            name = entry["product"]
            return (name, name, name, "container:" + os.path.relpath(self.root / package["dir"], container_dir))
        project = find_project(self.spec, entry["project"])
        if project is None:
            return None
        target = find_target(project, entry["target"])
        project_dir = self.root / project["dir"] if project["dir"] else self.root
        container = "container:" + os.path.relpath(project_dir / f"{project['name']}.xcodeproj", container_dir)
        if target is None:
            if entry["target"] == "t-missing":
                return ("0123456789ABCDEF01234567", "Missing.app", "Missing", container)
            return None
        name = product_file(target)[1] if target["kind"] in PRODUCTS else target["name"]
        return (object_id(project["id"], target["id"]), name, target["name"], container)

    def write_schemes(self, path):
        directories = [(path / "xcshareddata" / "xcschemes", self.project["schemes"]),
                       (path / "xcuserdata" / f"{self.user}.xcuserdatad" / "xcschemes", self.project["user_schemes"]),
                       (path / "xcuserdata" / "fuzzbot.xcuserdatad" / "xcschemes", self.project["other_user_schemes"])]
        for directory, schemes in directories:
            for scheme in schemes:
                directory.mkdir(parents=True, exist_ok=True)
                (directory / f"{scheme['name']}.xcscheme").write_text(scheme_xml(scheme, lambda e: self.buildable(e, self.dir), self.plan_reference))
        management = self.project.get("scheme_management")
        if management:
            directory = path / "xcuserdata" / f"{self.user}.xcuserdatad" / "xcschemes"
            directory.mkdir(parents=True, exist_ok=True)
            state = {}
            shared = {s["name"] for s in self.project["schemes"]}
            for index, name in enumerate(management["order"]):
                state[f"{name}.xcscheme_^#shared#^_" if name in shared else f"{name}.xcscheme"] = {"orderHint": index}
            values = {"SchemeUserState": state}
            suppressed = {self.oid(t): {"primary": True} for t in management["suppress"] if t in self.targets}
            if suppressed:
                values["SuppressBuildableAutocreation"] = suppressed
            (directory / "xcschememanagement.plist").write_bytes(plist_bytes(values))

    def plan_reference(self, plan_id):
        plan = next((p for p in self.project["test_plans"] if p["id"] == plan_id), None)
        return f"container:{plan['path']}" if plan else None

    def write_test_plans(self):
        for plan in self.project["test_plans"]:
            if not plan.get("on_disk", True):
                continue
            keys = plan.get("keys") or {}
            targets = []
            for entry in plan["tests"]:
                found = self.buildable(entry, self.dir)
                if found:
                    item = {"target": {"containerPath": found[3], "identifier": found[0], "name": found[2]}}
                    if keys.get("skipped"):
                        item["skippedTests"] = ["FuzzTests/testNothing()"]
                    elif keys.get("selected"):
                        item["selectedTests"] = ["FuzzTests/testNothing()"]
                    if keys.get("parallelizable"):
                        item["parallelizable"] = True
                    if keys.get("disabled"):
                        item["enabled"] = False
                    targets.append(item)
            options = {}
            if plan["coverage"] is True:
                options["codeCoverage"] = True
            elif plan["coverage"] is False:
                options["codeCoverage"] = False
            elif plan["coverage"] == "targets":
                options["codeCoverage"] = {"targets": [t["target"] for t in targets[:1]]}
            if keys.get("expansion") and targets:
                options["targetForVariableExpansion"] = targets[0]["target"]
            if keys.get("environment"):
                options["environmentVariableEntries"] = [{"key": "FUZZ", "value": "1"}]
            if keys.get("arguments"):
                options["commandLineArgumentEntries"] = [{"argument": "-fuzz"}]
            if keys.get("timeouts"):
                options["testTimeoutsEnabled"] = True
            if keys.get("repetition"):
                options["testRepetitionMode"] = "retryOnFailure"
            if keys.get("language"):
                options["language"] = "fr"
                options["region"] = "FR"
            if keys.get("ordering"):
                options["testExecutionOrdering"] = "random"
            document = {"configurations": [{"id": "8D7C5E1A-0F3B-4C2D-9E6F-1A2B3C4D5E6F" if plan["valid"] else "not-a-uuid",
                                            "name": "Test Scheme Action", "options": {}}],
                        "defaultOptions": options, "testTargets": targets, "version": 1}
            path = self.dir / plan["path"]
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(document, indent=2, ensure_ascii=False) + "\n")


def write_workspace_files(path, files, user):
    """A workspace's data files: IDEWorkspaceChecks.plist, its shared and per-user settings and an empty Package.resolved."""
    if not files:
        return
    shared = path / "xcshareddata"
    if files.get("checks"):
        shared.mkdir(parents=True, exist_ok=True)
        (shared / "IDEWorkspaceChecks.plist").write_bytes(plist_bytes({"IDEDidComputeMac32BitWarning": True}))
    if files.get("settings"):
        shared.mkdir(parents=True, exist_ok=True)
        (shared / "WorkspaceSettings.xcsettings").write_bytes(plist_bytes(files["settings"]))
    if files.get("user_settings"):
        folder = path / "xcuserdata" / f"{user}.xcuserdatad"
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "WorkspaceSettings.xcsettings").write_bytes(plist_bytes(files["user_settings"]))
    if files.get("resolved"):
        folder = shared / "swiftpm"
        folder.mkdir(parents=True, exist_ok=True)
        document = {"object": {"pins": []}, "version": 1} if files["resolved"] == 1 else {"pins": [], "version": files["resolved"]}
        (folder / "Package.resolved").write_text(json.dumps(document, indent=2) + "\n")


def scheme_xml(scheme, buildable, plan_reference):
    keys = scheme.get("keys") or {}

    def reference(found, indent):
        pad = " " * indent
        blueprint, buildable_name, blueprint_name, container = (html.escape(str(v)) for v in found)
        return (f'{pad}<BuildableReference\n{pad}   BuildableIdentifier = "primary"\n{pad}   BlueprintIdentifier = "{blueprint}"\n'
                f'{pad}   BuildableName = "{buildable_name}"\n{pad}   BlueprintName = "{blueprint_name}"\n'
                f'{pad}   ReferencedContainer = "{container}">\n{pad}</BuildableReference>\n')

    def runnable(entry):
        if entry is None:
            return ""
        found = buildable(entry)
        if found is None:
            return ""
        if entry["kind"] == "remote":
            inner = reference(found, 9) if keys.get("remote_buildable") else ""
            mode = "2" if keys.get("remote_buildable") else "1"
            return (f'      <RemoteRunnable\n         runnableDebuggingMode = "{mode}"\n         BundleIdentifier = "com.apple.springboard"\n'
                    f'         RemotePath = "/System/Library/CoreServices/SpringBoard.app">\n{inner}      </RemoteRunnable>\n'
                    '      <MacroExpansion>\n' + reference(found, 9) + '      </MacroExpansion>\n')
        if entry["kind"] == "path":
            return ('      <PathRunnable\n         runnableDebuggingMode = "0"\n         FilePath = "/Applications/Safari.app">\n'
                    '      </PathRunnable>\n')
        return '      <BuildableProductRunnable\n         runnableDebuggingMode = "0">\n' + reference(found, 9) + '      </BuildableProductRunnable>\n'

    configs = scheme.get("configs") or {}
    entries = ""
    for entry in scheme["build"]:
        found = buildable(entry)
        if found is None:
            continue
        flag = "YES" if entry["running"] else "NO"
        entries += (f'         <BuildActionEntry\n            buildForTesting = "{"NO" if keys.get("testing_no") else "YES"}"\n'
                    f'            buildForRunning = "{flag}"\n            buildForProfiling = "{flag}"\n'
                    f'            buildForArchiving = "{flag}"\n            buildForAnalyzing = "{"NO" if keys.get("analyze_no") else "YES"}">\n'
                    + reference(found, 12) + "         </BuildActionEntry>\n")
    build = f"      <BuildActionEntries>\n{entries}      </BuildActionEntries>\n" if entries else ""
    first_build = next((found for found in (buildable(entry) for entry in scheme["build"]) if found), None)
    if keys.get("actions"):
        environment = f"               <EnvironmentBuildable>\n{reference(first_build, 18)}               </EnvironmentBuildable>\n" if first_build else ""
        action = ('         <ExecutionAction\n            ActionType = "Xcode.IDEStandardExecutionActionsCore.ExecutionActionType.ShellScriptAction">\n'
                  '            <ActionContent\n               title = "Run Script"\n               scriptText = "echo fuzz&#10;">\n'
                  f'{environment}            </ActionContent>\n         </ExecutionAction>\n')
        build = f"      <PreActions>\n{action}      </PreActions>\n      <PostActions>\n{action}      </PostActions>\n" + build
    plans = ""
    for plan in scheme["plans"]:
        location = plan_reference(plan["plan"])
        if location:
            default = '\n            default = "YES"' if plan["default"] else ""
            plans += f'         <TestPlanReference\n            reference = "{html.escape(location)}"{default}>\n         </TestPlanReference>\n'
    testables = ""
    for test in scheme["tests"]:
        found = buildable(test)
        if found:
            parallel = f'\n            parallelizable = "{keys["parallelizable"]}"' if keys.get("parallelizable") else ""
            ordering = '\n            testExecutionOrdering = "random"' if keys.get("ordering") else ""
            skipped = '            <SkippedTests>\n               <Test\n                  Identifier = "FuzzTests/testNothing()">\n               </Test>\n            </SkippedTests>\n' if keys.get("skipped") else ""
            testables += (f'         <TestableReference\n            skipped = "{"YES" if test.get("skipped") else "NO"}"{parallel}{ordering}>\n'
                          + reference(found, 12) + skipped + "         </TestableReference>\n")
    test_body = (f"      <TestPlans>\n{plans}      </TestPlans>\n" if plans else "") + (f"      <Testables>\n{testables}      </Testables>\n" if testables else "")
    coverage = '\n      codeCoverageEnabled = "YES"' if scheme.get("coverage") else ""
    ask = '\n      askForAppToLaunch = "Yes"\n      launchAutomaticallySubstyle = "2"' if scheme.get("ask") else ""
    build_keys = '\n      buildArchitectures = "Automatic"' if keys.get("architectures") else ""
    version = keys.get("version", "1.7")
    extension_key = '\n   wasCreatedForAppExtension = "YES"' if keys.get("extension") else ""
    test_keys, test_after, launch_keys, launch_after = "", "", "", ""
    if keys.get("autocreate_plan"):
        test_keys += '\n      shouldAutocreateTestPlan = "YES"'
    if keys.get("language"):
        test_keys += '\n      language = "fr"\n      region = "FR"'
        launch_keys += '\n      language = "fr"\n      region = "FR"'
    if keys.get("lldb"):
        test_keys += '\n      customLLDBInitFile = "$(SRCROOT)/.lldbinit"'
        launch_keys += '\n      customLLDBInitFile = "$(SRCROOT)/.lldbinit"'
    if keys.get("launch_flags"):
        launch_keys += ('\n      enableGPUValidationMode = "1"\n      queueDebuggingEnabled = "No"\n      disableMainThreadChecker = "YES"'
                        '\n      viewDebuggingEnabled = "No"\n      showNonLocalizedStrings = "YES"\n      debugXPCServices = "NO"')
    if keys.get("test_macro") and first_build:
        test_after += "      <MacroExpansion>\n" + reference(first_build, 9) + "      </MacroExpansion>\n"
    if keys.get("coverage_targets") and first_build:
        test_keys += '\n      onlyGenerateCoverageForSpecifiedTargets = "YES"'
        test_after += "      <CodeCoverageTargets>\n" + reference(first_build, 9) + "      </CodeCoverageTargets>\n"
    if keys.get("options"):
        options = ('      <CommandLineArguments>\n         <CommandLineArgument\n            argument = "-fuzz"\n            isEnabled = "YES">\n'
                   '         </CommandLineArgument>\n         <CommandLineArgument\n            argument = "-off"\n            isEnabled = "NO">\n'
                   '         </CommandLineArgument>\n      </CommandLineArguments>\n'
                   '      <EnvironmentVariables>\n         <EnvironmentVariable\n            key = "FUZZ"\n            value = "YES"\n            isEnabled = "NO">\n'
                   '         </EnvironmentVariable>\n         <EnvironmentVariable\n            key = "FUZZ_ON"\n            value = "1"\n            isEnabled = "YES">\n'
                   '         </EnvironmentVariable>\n      </EnvironmentVariables>\n'
                   '      <AdditionalOptions>\n         <AdditionalOption\n            key = "NSZombieEnabled"\n            value = "YES"\n            isEnabled = "YES">\n'
                   '         </AdditionalOption>\n      </AdditionalOptions>\n')
        launch_after += options
        test_after += options
    profile_keys = '\n      launchAutomaticallySubstyle = "2"\n      askForAppToLaunch = "Yes"' if keys.get("substyle") else ""
    profile_after = "      <MacroExpansion>\n" + reference(first_build, 9) + "      </MacroExpansion>\n" if keys.get("test_macro") and first_build and not scheme.get("profile") else ""
    if keys.get("launch_flags"):
        launch_after += ('      <StoreKitConfigurationFileReference\n         identifier = "../Fuzz.storekit">\n      </StoreKitConfigurationFileReference>\n'
                         '      <LocationScenarioReference\n         identifier = "London, England"\n         referenceType = "1">\n      </LocationScenarioReference>\n')
    archive_keys = '\n      customArchiveName = "Fuzz Archive"' if keys.get("custom_archive") else ""
    parallelize = "NO" if keys.get("parallelize_no") else "YES"
    use_launch = "NO" if keys.get("args_env_no") else "YES"
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"{extension_key}
   version = "{version}">
   <BuildAction
      parallelizeBuildables = "{parallelize}"
      buildImplicitDependencies = "YES"{build_keys}>
{build}   </BuildAction>
   <TestAction
      buildConfiguration = "{html.escape(configs.get('test', 'Debug'))}"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "{use_launch}"{coverage}{test_keys}>
{test_after}{test_body}   </TestAction>
   <LaunchAction
      buildConfiguration = "{html.escape(configs.get('launch', 'Debug'))}"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES"{ask}{launch_keys}>
{runnable(scheme.get('launch'))}{launch_after}   </LaunchAction>
   <ProfileAction
      buildConfiguration = "{html.escape(configs.get('profile', 'Release'))}"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES"{profile_keys}>
{runnable(scheme.get('profile'))}{profile_after}   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "{html.escape(configs.get('analyze', 'Debug'))}">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "{html.escape(configs.get('archive', 'Release'))}"
      revealArchiveInOrganizer = "YES"{archive_keys}>
   </ArchiveAction>
</Scheme>
"""


def package_manifest(package, packages, root):
    by_id = {k["id"]: k for k in packages}
    products = []
    for product in package["products"]:
        names = ", ".join(f'"{t}"' for t in product["targets"])
        if product["kind"] == "executable":
            products.append(f'.executable(name: "{product["name"]}", targets: [{names}])')
        elif product["kind"] == "dynamic":
            products.append(f'.library(name: "{product["name"]}", type: .dynamic, targets: [{names}])')
        else:
            products.append(f'.library(name: "{product["name"]}", targets: [{names}])')
    dependencies = [f'.package(path: "{os.path.relpath(root / by_id[d]["dir"], root / package["dir"])}")' for d in package["deps"] if d in by_id]
    targets = []
    for target in package["targets"]:
        deps = [f'"{d}"' for d in target["deps"]]
        deps += [f'.product(name: "{d["product"]}", package: "{Path(by_id[d["package"]]["dir"]).name}")'
                 for d in target["product_deps"] if d["package"] in by_id and d["package"] in package["deps"]]
        function = {"library": "target", "executable": "executableTarget", "test": "testTarget"}[target["kind"]]
        exclude = ', exclude: ["notes.txt"]' if target.get("exclude") else ""
        resources = (', resources: [.copy("Resources/data.json")]' if target.get("copy") else ', resources: [.process("Resources")]') if target["resources"] else ""
        settings = f', swiftSettings: [{", ".join(target["swift_settings"])}]' if target.get("swift_settings") else ""
        targets.append(f'.{function}(name: "{target["name"]}", dependencies: [{", ".join(deps)}]{exclude}{resources}{settings})')
    platforms = f"    platforms: [{', '.join(package['platforms'])}],\n" if package["platforms"] else ""
    localization = '    defaultLocalization: "en",\n' if package.get("default_localization") else ""
    return (f"// swift-tools-version: {package['tools']}\nimport PackageDescription\n\nlet package = Package(\n"
            f'    name: "{package["name"]}",\n{localization}{platforms}    products: [{", ".join(products)}],\n'
            f"    dependencies: [{', '.join(dependencies)}],\n    targets: [{', '.join(targets)}]\n)\n")


def render_package(package, packages, root):
    directory = root / package["dir"]
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "Package.swift").write_text(package_manifest(package, packages, root))
    for target in package["targets"]:
        folder = directory / ("Tests" if target["kind"] == "test" else "Sources") / target["name"]
        folder.mkdir(parents=True, exist_ok=True)
        source = {"library": f"public enum {identifier(target['name'])} {{}}\n", "executable": 'print("fuzz")\n',
                  "test": "import XCTest\n\nfinal class FuzzTests: XCTestCase {}\n"}[target["kind"]]
        (folder / ("main.swift" if target["kind"] == "executable" else f"{target['name']}.swift")).write_text(source)
        if target.get("exclude"):
            (folder / "notes.txt").write_text("notes\n")
        if target["resources"]:
            (folder / "Resources").mkdir(exist_ok=True)
            (folder / "Resources" / "data.json").write_text("{}\n")
    for scheme in package.get("schemes", []):
        folder = directory / ".swiftpm" / "xcode" / "xcshareddata" / "xcschemes"
        folder.mkdir(parents=True, exist_ok=True)

        def buildable(entry):
            return (entry["product"], entry["product"], entry["product"], "container:") if "product" in entry else None
        (folder / f"{scheme['name']}.xcscheme").write_text(scheme_xml(scheme, buildable, lambda _: None))


def publish_package(package, root):
    """Makes a remote package's folder a git repository with a tag, for its `file:` URL."""
    directory = root / package["dir"]
    identity = {"GIT_AUTHOR_NAME": "fuzz", "GIT_AUTHOR_EMAIL": "fuzz@nomac.invalid", "GIT_COMMITTER_NAME": "fuzz", "GIT_COMMITTER_EMAIL": "fuzz@nomac.invalid",
                "GIT_AUTHOR_DATE": "2026-01-01T00:00:00Z", "GIT_COMMITTER_DATE": "2026-01-01T00:00:00Z"}
    for command in (["init", "-q", "-b", "main"], ["add", "-A"], ["commit", "-q", "-m", "fuzz"], ["tag", "1.0.0"]):
        subprocess.run(["git", *command], cwd=directory, env={**os.environ, **identity}, check=True, capture_output=True)
    package["revision"] = subprocess.run(["git", "rev-parse", "HEAD"], cwd=directory, check=True, capture_output=True, text=True).stdout.strip()


def render(spec, root, user):
    """Writes `spec` under `root`; returns the container path relative to `root`."""
    root.mkdir(parents=True, exist_ok=True)
    for package in spec["packages"]:
        render_package(package, spec["packages"], root)
        if package.get("remote"):
            publish_package(package, root)
    containers = [ProjectRenderer(spec, project, root, user).render() for project in spec["projects"]]
    workspace = spec.get("workspace")
    if not workspace:
        return str(containers[0].relative_to(root))
    path = root / f"{workspace['name']}.xcworkspace"
    path.mkdir(parents=True, exist_ok=True)
    body = ""
    groups = collections.OrderedDict()
    for item in workspace["items"]:
        if item["kind"] == "raw":
            scheme, _, location = item["location"].partition(":")
            if item.get("content"):
                (root / location).write_text(item["content"])
            if item.get("playground"):
                write_item(root / location)
            groups.setdefault(item.get("group"), []).append(f"{scheme}:{location}")
            continue
        if item["kind"] == "project":
            project = find_project(spec, item["project"])
            if project is None:
                continue
            location = os.path.join(project["dir"], f"{project['name']}.xcodeproj")
        else:
            package = next((k for k in spec["packages"] if k["id"] == item["package"]), None)
            if package is None:
                continue
            location = package["dir"]
        groups.setdefault(item.get("group"), []).append(f'{item.get("scheme", "group")}:{location}')
    for group, locations in groups.items():
        refs = "".join(f'{"   " if group else ""}   <FileRef\n{"   " if group else ""}      location = "{html.escape(location)}">\n'
                       f'{"   " if group else ""}   </FileRef>\n' for location in locations)
        body += f'   <Group\n      location = "{workspace.get("group_location", "container:")}"\n      name = "{group}">\n{refs}   </Group>\n' if group else refs
    (path / "contents.xcworkspacedata").write_text(f'<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n{body}</Workspace>\n')
    write_workspace_files(path, workspace.get("files"), user)
    if workspace["schemes"]:
        renderer = ProjectRenderer(spec, spec["projects"][0], root, user)
        folder = path / "xcshareddata" / "xcschemes"
        folder.mkdir(parents=True, exist_ok=True)
        for scheme in workspace["schemes"]:
            (folder / f"{scheme['name']}.xcscheme").write_text(scheme_xml(scheme, lambda e: renderer.buildable(e, root), lambda _: None))
    return str(path.relative_to(root))


# ---------------------------------------------------------------------------------------------
# Running Xcode and nomac on a case, and classifying the differences.

def folder_hash(path):
    """DerivedData's folder hash (Sources/NomacInspect/DerivedData.swift folderHash)."""
    digest = hashlib.md5(str(path).encode()).digest()

    def base26(chunk):
        value = int.from_bytes(chunk, "big")
        letters = []
        for _ in range(14):
            letters.append(chr(97 + value % 26))
            value //= 26
        return "".join(reversed(letters))
    return base26(digest[:8]) + base26(digest[8:])


def spec_size(value):
    if isinstance(value, dict):
        return sum(spec_size(v) for v in value.values()) + len(value)
    if isinstance(value, list):
        return sum(spec_size(v) for v in value) + len(value)
    return 1


def tail(data, lines=6):
    text = data.decode(errors="replace") if isinstance(data, bytes) else data
    return [line for line in text.strip().splitlines() if line.strip()][-lines:]


def scheme_origins(spec):
    origins = collections.defaultdict(set)
    for project in spec["projects"]:
        for scheme in project["schemes"]:
            origins[scheme["name"]].add("shared scheme")
        for scheme in project["user_schemes"]:
            origins[scheme["name"]].add("user scheme")
        for scheme in project["other_user_schemes"]:
            origins[scheme["name"]].add("other user's scheme")
        for target in project["targets"]:
            origins[target["name"]].add(f"{target['kind']} target")
    if spec.get("workspace"):
        for scheme in spec["workspace"]["schemes"]:
            origins[scheme["name"]].add("workspace scheme")
    for package in spec["packages"]:
        for product in package["products"]:
            origins[product["name"]].add(f"package {product['kind']} product")
        for target in package["targets"]:
            if target["kind"] == "test":
                origins[target["name"]].add("package test target")
        for scheme in package.get("schemes", []):
            origins[scheme["name"]].add("package scheme")
        origins[f"{package['name']}-Package"].add("package")
    return origins


def normalize_message(message, src):
    text = message.replace(str(src), "<SRC>")
    text = re.sub(r"\b[0-9A-F]{24}\b", "<ID>", text)
    text = re.sub(r"'[^']*'", "'…'", text)
    text = re.sub(r'"[^"]*"', '"…"', text)
    return text[:160]


def random_guids(objects, synchronized):
    """The GUIDs Xcode draws at random, which `nomac verify` replaces too (PIFComparison
    canonicalizeRandomGUIDs, ADR 0009): a variant group whose GUID is not a synchronized
    member's while its children's are, and the build files that name one."""
    drawn = set()

    def visit(node):
        children = node.get("children", [])
        if node.get("type") == "variantGroup" and children and not synchronized.match(node.get("guid", "")) \
                and all(synchronized.match(child.get("guid", "")) for child in children):
            drawn.add(node.get("guid"))
        for child in children:
            visit(child)
    for item in objects:
        tree = item.get("contents", {}).get("groupTree")
        if isinstance(tree, dict):
            visit(tree)
    for item in objects:
        for phase in item.get("contents", {}).get("buildPhases", []):
            for build_file in phase.get("buildFiles", []):
                if build_file.get("fileReference") in drawn:
                    drawn.add(build_file.get("guid"))
    return drawn


def canonical_pif(text):
    objects = json.loads(text)
    projects, current = [], None
    head = objects[:1] if objects and objects[0].get("type") == "workspace" else []
    for item in objects[len(head):]:
        if item.get("type") == "project" or current is None:
            current = [item]
            projects.append(current)
        else:
            current.append(item)
    own = [g for g in projects if g[0].get("contents", {}).get("projectIsPackage") != "true"]
    packages = sorted((g for g in projects if g[0].get("contents", {}).get("projectIsPackage") == "true"),
                      key=lambda g: g[0].get("contents", {}).get("guid", ""))
    ordered = head + [o for g in own + packages for o in g]
    signatures = {o.get("signature"): f"<{o.get('type', '').upper()}-{i}>" for i, o in enumerate(ordered)}
    guid = re.compile(r"^[A-Za-z0-9+/]{43}=$")
    drawn = random_guids(ordered, guid)

    def walk(value):
        if isinstance(value, dict):
            return {k: walk(v) for k, v in value.items()}
        if isinstance(value, list):
            return [walk(v) for v in value]
        if isinstance(value, str):
            if value in signatures:
                return signatures[value]
            if guid.match(value) or value in drawn:
                return "<SYNCHRONIZED>"
        return value
    result = [walk(o) for o in ordered]
    if head and isinstance(result[0].get("contents"), dict) and "projects" in result[0]["contents"]:
        result[0]["contents"]["projects"] = [signatures.get(o.get("signature")) for o in ordered if o.get("type") == "project"]
    return result


def identity(element):
    """What identifies a list element across both PIFs: its type and path or name (in NFC, so a
    name in another normalization still pairs up), else a GUID that is not a synchronized one."""
    if not isinstance(element, dict):
        return None
    key = tuple(unicodedata.normalize("NFC", value) if isinstance(value, str) else value
                for value in (element.get(k) for k in ("type", "path", "name", "configurationName", "regionVariantName")))
    if any(value is not None for value in key[1:]):
        return key
    guid = element.get("guid")
    return ("guid", guid) if isinstance(guid, str) and not guid.startswith("<") else None


def element_label(element):
    if isinstance(element, dict):
        kind = element.get("type")
        if isinstance(kind, str):
            return f"[{kind.rsplit('.', 1)[-1]}]"
    return "[]"


def differences(a, b, path, context, found, limit=12):
    """Appends (path, kind, Xcode value, nomac value, context) for each difference of `a` and `b`."""
    if len(found) >= limit:
        return
    if type(a) is not type(b):
        found.append((path, "type", a, b, context))
        return
    if isinstance(a, dict):
        here = context
        for name_key in ("name", "path"):
            if isinstance(a.get(name_key), str) and a.get(name_key):
                here = context + [f"{a.get('type', '')} {a[name_key]!r}".strip()]
                break
        for key in a:
            if key not in b:
                found.append((path + [key], "missing in nomac", a[key], None, here))
            else:
                differences(a[key], b[key], path + [key], here, found, limit)
        for key in b:
            if key not in a:
                found.append((path + [key], "only in nomac", None, b[key], here))
        return
    if isinstance(a, list):
        if a == b:
            return
        left_ids, right_ids = [identity(x) for x in a], [identity(x) for x in b]
        if all(left_ids) and all(right_ids) and len(set(left_ids)) == len(a) and len(set(right_ids)) == len(b):
            right_index = {key: index for index, key in enumerate(right_ids)}
            shared = [key for key in left_ids if key in right_index]
            if [key for key in right_ids if key in set(left_ids)] != shared:
                found.append((path + ["[]"], "order", [k[1] or k[2] for k in left_ids], [k[1] or k[2] for k in right_ids], context))
            for key, item in zip(left_ids, a):
                if key in right_index:
                    differences(item, b[right_index[key]], path + [element_label(item)], context, found, limit)
                else:
                    found.append((path + [element_label(item)], "element missing in nomac", item, None, context))
            for key, item in zip(right_ids, b):
                if key not in set(left_ids):
                    found.append((path + [element_label(item)], "element only in nomac", None, item, context))
            return
        left = [json.dumps(x, sort_keys=True, ensure_ascii=False) for x in a]
        right = [json.dumps(x, sort_keys=True, ensure_ascii=False) for x in b]
        if sorted(left) == sorted(right):
            found.append((path + ["[]"], "order", a, b, context))
            return
        for operation, i1, i2, j1, j2 in difflib.SequenceMatcher(a=left, b=right, autojunk=False).get_opcodes():
            if operation == "equal":
                continue
            pairs = min(i2 - i1, j2 - j1) if operation == "replace" else 0
            for k in range(pairs):
                differences(a[i1 + k], b[j1 + k], path + [element_label(a[i1 + k])], context, found, limit)
            for item in a[i1 + pairs:i2]:
                found.append((path + [element_label(item)], "element missing in nomac", item, None, context))
            for item in b[j1 + pairs:j2]:
                found.append((path + [element_label(item)], "element only in nomac", None, item, context))
        return
    if a != b:
        found.append((path, "value", a, b, context))


def path_text(path):
    text = ""
    for segment in path:
        if segment.startswith("["):
            text += segment
        elif segment != "contents":
            text += ("." if text else "") + segment
    text = re.sub(r"(?:\.children\[[^\]]*\])+", lambda m: ".children*" + re.findall(r"\[[^\]]*\]", m.group(0))[-1], text)
    return text.lstrip(".")


def short(value, limit=240):
    text = json.dumps(value, ensure_ascii=False, sort_keys=True) if not isinstance(value, str) else value
    return text if len(text) <= limit else text[:limit] + "…"


SETTINGS_PATTERNS = [
    (re.compile(r"^xcodebuild exited with status (\d+); nomac printed"), lambda m, k: f"settings/{k}: xcodebuild fails ({m.group(1)}), nomac succeeds"),
    (re.compile(r"^target (.+): block missing from nomac's output$"), lambda m, k: f"settings/{k}: block missing in nomac"),
    (re.compile(r"^target (.+): block present only in nomac's output$"), lambda m, k: f"settings/{k}: block only in nomac"),
    (re.compile(r"^target order differs"), lambda m, k: f"settings/{k}: block order"),
    (re.compile(r"^target [^\n]+?: missing ([A-Za-z0-9_]+) = "), lambda m, k: f"settings: {m.group(1)} missing in nomac"),
    (re.compile(r"^target [^\n]+?: extra ([A-Za-z0-9_]+) = "), lambda m, k: f"settings: {m.group(1)} only in nomac"),
    (re.compile(r"^target [^\n]+?: ([A-Za-z0-9_]+)\n"), lambda m, k: f"settings: {m.group(1)} differs"),
]


def json_class(detail, kind):
    """The class of a `-json` capture that differs while its text capture matches."""
    first = detail[0] if detail else ""
    if first.startswith("xcodebuild exited with status"):
        status = re.search(r"status (-?\d+)", first).group(1)
        nomac = re.search(r"nomac failed with status (\d+)", " ".join(detail))
        return f"settings-json/{kind}: xcodebuild {status}, nomac {nomac.group(1) if nomac else 'succeeds'}"
    xcode_line = next((d[len("Xcode: "):] for d in detail if d.startswith("Xcode: ")), "")
    match = re.search(r'"([A-Za-z0-9_]+)" :', xcode_line)
    return f"settings-json: {match.group(1)}" if match else "settings-json: " + re.sub(r'"[^"]*"', '"…"', xcode_line.strip())[:60]


def capture_kind(arguments):
    if "-scheme" in arguments:
        return "scheme-config" if "-configuration" in arguments else "scheme"
    if "-alltargets" in arguments:
        return "alltargets"
    return "target" if "-target" in arguments else "default"


class Runner:
    def __init__(self, out, nomac, keep=False):
        self.out = out
        self.nomac = str(nomac)
        self.keep = keep
        self.env = capture.reference_environment(DEVELOPER_DIR)
        self.user = pwd.getpwuid(os.getuid()).pw_name
        self.stop = threading.Event()
        self.stop_reason = None
        self.lock = threading.Lock()
        out.mkdir(parents=True, exist_ok=True)
        host_path = out / "host.json"
        if host_path.exists():
            self.host = json.loads(host_path.read_text())
        else:
            self.host = capture.host_identity(DEVELOPER_DIR, self.env)
            expected = capture.expected_xcode_build(json.loads((REPO_ROOT / "corpus" / "corpus.json").read_text()))
            if self.host["xcodeBuild"] != expected:
                sys.exit(f"error: Xcode at {DEVELOPER_DIR} is {self.host['xcodeBuild']}, corpus expects {expected}")
            host_path.write_text(json.dumps(self.host, indent=2, sort_keys=True) + "\n")

    def check_disk(self):
        free = shutil.disk_usage(Path.home()).free
        if free < MIN_FREE_BYTES:
            self.halt(f"host free space is {free / 1024 ** 3:.1f} GB, under 4 GB")
        used = int(subprocess.run(["du", "-sk", str(self.out)], capture_output=True, text=True).stdout.split()[0]) * 1024
        if used > BUDGET_BYTES:
            self.halt(f"{self.out} uses {used / 1024 ** 3:.2f} GB, over the 1 GB budget")

    def halt(self, reason):
        with self.lock:
            if not self.stop.is_set():
                self.stop_reason = reason
                print(f"[fuzz] stopping: {reason}", flush=True)
                self.stop.set()

    def xcodebuild(self, args, cwd, out_path=None):
        argv = ["xcodebuild"] + args
        started = time.time()
        for _ in range(3):
            try:
                proc = subprocess.run(argv, cwd=cwd, env=self.env, capture_output=True, timeout=COMMAND_TIMEOUT)
            except subprocess.TimeoutExpired:
                proc = subprocess.CompletedProcess(argv, 124, b"", b"timeout")
            if proc.returncode != -signal.SIGKILL:
                break
        if out_path is not None:
            Path(out_path).write_bytes(proc.stdout)
            Path(str(out_path) + ".cmd").write_text(json.dumps({"argv": argv, "cwd": str(cwd), "exitStatus": proc.returncode,
                                                                "seconds": round(time.time() - started, 1)}, indent=2) + "\n")
        return proc

    def nomac_run(self, args, home):
        env = dict(self.env, NOMAC_HOME=str(home))
        try:
            return subprocess.run([self.nomac] + args, env=env, capture_output=True, timeout=COMMAND_TIMEOUT)
        except subprocess.TimeoutExpired:
            return subprocess.CompletedProcess(args, 124, b"", b"nomac timed out")

    def clean_derived_data(self, container):
        """Removes the DerivedData folder of `container`, whose hash Xcode takes over the path's
        decomposed (file-system) form."""
        for form in ("NFD", "NFC"):
            suffix = "-" + folder_hash(unicodedata.normalize(form, str(container)))
            for entry in DERIVED_DATA.glob("*" + suffix):
                if entry.is_dir() and entry.name.endswith(suffix):
                    shutil.rmtree(entry, ignore_errors=True)

    def clean_stale_derived_data(self):
        """Removes DerivedData folders of every container under the output directory, which an
        interrupted run leaves behind."""
        ledger = self.out / "containers.log"
        containers = set(ledger.read_text().splitlines()) if ledger.exists() else set()
        for pattern in ("*.xcodeproj", "*.xcworkspace"):
            containers.update(str(path) for path in self.out.rglob(pattern))
        hashes = {folder_hash(unicodedata.normalize(form, container)) for container in containers for form in ("NFD", "NFC")}
        removed = 0
        for entry in DERIVED_DATA.iterdir() if DERIVED_DATA.exists() else []:
            if entry.is_dir() and entry.name.rsplit("-", 1)[-1] in hashes:
                shutil.rmtree(entry, ignore_errors=True)
                removed += 1
        return removed

    def plan_captures(self, spec, listing):
        rng = random.Random(f"captures/{spec['seed']}/{','.join(spec['focus'])}")
        body = listing.get("project") or listing.get("workspace") or {}
        is_project = "project" in listing
        targets, schemes, configurations = body.get("targets", []), body.get("schemes", []), body.get("configurations", [])
        captures, names = [], set()

        def add(name, args):
            name = capture.unique_name(capture.safe_name(name), names)
            captures.append({"name": name, "arguments": args, "json": rng.random() < 0.5})
        if is_project:
            add("default", [])
            for target in rng.sample(targets, min(len(targets), 5)):
                config = rng.choice(configurations) if configurations else None
                add(f"target-{target}-{config}", ["-target", target] + (["-configuration", config] if config else []))
            if rng.random() < 0.3:
                add("alltargets", ["-alltargets"])
            if targets and rng.random() < 0.3:
                target = rng.choice(targets)
                add(f"target-{target}", ["-target", target])
        for scheme in sorted(set(rng.sample(schemes, min(len(schemes), 6))), key=schemes.index):
            add(f"scheme-{scheme}-iphoneos", ["-scheme", scheme, "-destination", "generic/platform=iOS"])
            if configurations and rng.random() < 0.4:
                config = rng.choice(configurations)
                add(f"scheme-{scheme}-{config}-iphoneos", ["-scheme", scheme, "-configuration", config, "-destination", "generic/platform=iOS"])
        return captures

    def evaluate(self, spec, case_dir, only=None):
        """Runs Xcode and nomac on `spec` in `case_dir`. `only` restricts the run to one check
        (minimization): {"check": "pif" | "list" | "list-text" | "settings" | "nomac", "capture": {...}}."""
        started = time.time()
        if case_dir.exists():
            shutil.rmtree(case_dir)
        src, ref, work = case_dir / "src", case_dir / "ref", case_dir / "nomac"
        for directory in (ref / "pif", ref / "settings", work / "home"):
            directory.mkdir(parents=True)
        (case_dir / "spec.json").write_text(json.dumps(spec, indent=1, ensure_ascii=False) + "\n")
        result = {"seed": spec["seed"], "focus": spec["focus"], "features": spec.get("features", []), "size": spec_size(spec),
                  "status": None, "classes": [], "captures": 0}
        container = src / render(spec, src, self.user)
        with self.lock, open(self.out / "containers.log", "a") as ledger:
            ledger.write(f"{container}\n")
        result["container"] = str(container.relative_to(case_dir))
        flag = "-workspace" if container.suffix == ".xcworkspace" else "-project"
        base = [flag, str(container)]
        try:
            (ref / "app.json").write_text(json.dumps({"id": case_dir.name, "container": str(container.relative_to(src))}) + "\n")
            (ref / "source.json").write_text(json.dumps({"path": str(src)}) + "\n")
            (ref / "host.json").write_text(json.dumps(self.host, indent=2, sort_keys=True) + "\n")
            dump = self.xcodebuild(["-dumpPIF", str(ref / "pif" / "workspace.pif")] + base, src, ref / "pif" / "dumpPIF.stdout")
            if dump.returncode != 0 or not (ref / "pif" / "workspace.pif").exists():
                result.update(status="invalid", reason=tail(dump.stderr) + tail(dump.stdout))
                return result
            check = only["check"] if only else None
            listing = None
            if check in (None, "list", "list-text"):
                listed = self.xcodebuild(base + ["-list", "-json"], src, ref / "xcodebuild-list.json")
                text = self.xcodebuild(base + ["-list"], src, ref / "xcodebuild-list.txt")
                if listed.returncode != 0 or text.returncode != 0:
                    result.update(status="invalid", reason=["xcodebuild -list failed"] + tail(listed.stderr))
                    return result
                listing = json.loads(listed.stdout)
            if check is None:
                captures = self.plan_captures(spec, listing)
            elif check == "settings":
                captures = [only["capture"]]
            else:
                captures = []
            index, kinds = [], {}
            for item in captures:
                text = self.xcodebuild(base + ["-showBuildSettings"] + item["arguments"], src, ref / "settings" / f"{item['name']}.txt")
                if item["json"]:
                    self.xcodebuild(base + ["-showBuildSettings", "-json"] + item["arguments"], src, ref / "settings" / f"{item['name']}.json")
                index.append({"name": item["name"], "arguments": item["arguments"], "exitStatus": text.returncode})
                kinds[item["name"]] = item
            (ref / "settings" / "index.json").write_text(json.dumps(index, indent=2) + "\n")
            result["captures"] = len(index)
            if check == "list-text":
                (ref / "xcodebuild-list.json").unlink()
            verify = self.nomac_run(["verify", str(ref), "--source", str(src), "--developer-dir", DEVELOPER_DIR,
                                     "--report", str(work / "report.json")], work / "home")
            (work / "verify.log").write_bytes(verify.stdout + b"\n--- stderr\n" + verify.stderr)
            result["classes"] = self.classify(spec, src, ref, work, container, flag, verify, kinds, check)
            report_path = work / "report.json"
            checks = json.loads(report_path.read_text())["checks"] if report_path.exists() else []
            result["equivalent"] = [c["name"] for c in checks if c["status"] == "equivalent"]
            result["status"] = "different" if result["classes"] else "equivalent" if result["equivalent"] else "identical"
            return result
        finally:
            self.clean_derived_data(container)
            shutil.rmtree(work / "home", ignore_errors=True)
            result["seconds"] = round(time.time() - started, 1)
            (case_dir / "result.json").write_text(json.dumps(result, indent=1, ensure_ascii=False) + "\n")

    def classify(self, spec, src, ref, work, container, flag, verify, kinds, check):
        classes = []

        def add(key, source, detail, sample=None):
            if not any(c["key"] == key for c in classes):
                classes.append({"key": key, "check": source, "detail": [d[:600] for d in detail][:12], "sample": sample})
        report_path = work / "report.json"
        if not report_path.exists():
            message = next((line for line in reversed(tail(verify.stderr, 20)) if "error" in line.lower()), None) or (tail(verify.stderr) or ["(no output)"])[-1]
            add("nomac-error: " + normalize_message(message, src), "nomac", tail(verify.stderr, 8))
            return classes
        report = json.loads(report_path.read_text())
        text_status = {c["name"]: c["status"] for c in report["checks"] if c["kind"] == "settings" and not c["name"].endswith(".json")}
        list_differs = False
        for item in report["checks"]:
            if item["status"] in ("identical", "equivalent"):
                continue
            kind, name, detail = item["kind"], item["name"], item.get("detail", [])
            if kind == "pif":
                if check not in (None, "pif", "nomac"):
                    continue
                for key, source, lines, sample in self.classify_pif(ref, work, container, detail):
                    add(key, source, lines, sample)
            elif kind == "list":
                list_differs = True
                if check not in (None, "list"):
                    continue
                for key, lines in self.classify_list(spec, src, ref, work, container, flag, detail):
                    add(key, "list", lines, lines[0] if lines and lines[0].startswith("scheme ") else None)
            elif kind == "settings":
                if check not in (None, "settings"):
                    continue
                if name.endswith(".json"):
                    if text_status.get(name[:-5]) not in ("identical", "equivalent"):
                        continue
                    add(json_class(detail, capture_kind(kinds.get(name[:-5], {}).get("arguments", []))), f"settings:{name[:-5]}", detail)
                    continue
                kind_of_capture = capture_kind(kinds.get(name, {}).get("arguments", []))
                first = detail[0] if detail else ""
                key = None
                for pattern, make in SETTINGS_PATTERNS:
                    match = pattern.match(first)
                    if match:
                        key = make(match, kind_of_capture)
                        break
                if key is None and first.startswith("xcodebuild exited with status"):
                    nomac_status = re.search(r"nomac failed with status (\d+)", " ".join(detail))
                    status = re.search(r"status (\d+)", first).group(1)
                    key = f"settings/{kind_of_capture}: xcodebuild {status}, nomac {nomac_status.group(1) if nomac_status else '?'}"
                if key is None:
                    key = f"settings/{kind_of_capture}: {item['status']}" + (f" ({short(first, 80)})" if first else "")
                sample = short(re.sub(r"^target .+?: ", "", first).replace("\n    ", " "), 160) if first else None
                add(key, f"settings:{name}", [f"capture {name}: xcodebuild {' '.join(kinds.get(name, {}).get('arguments', []))}"] + detail, sample)
        if check in (None, "list-text") and not list_differs:
            for key, lines in self.classify_list_text(src, ref, work, container, flag):
                add(key, "list-text", lines)
        return classes

    def classify_pif(self, ref, work, container, detail):
        output = work / "nomac.pif"
        proc = self.nomac_run(["pif", str(container), "-o", str(output), "--developer-dir", DEVELOPER_DIR], work / "home")
        if proc.returncode != 0 or not output.exists():
            return [("pif: nomac pif fails", "pif", detail + tail(proc.stderr), None)]
        try:
            expected = canonical_pif((ref / "pif" / "workspace.pif").read_text())
            actual = canonical_pif(output.read_text())
        except (json.JSONDecodeError, KeyError, AttributeError) as error:
            return [("pif: unreadable", "pif", detail + [str(error)], None)]
        found = []
        actual_by_guid = {(o.get("type"), o.get("contents", {}).get("guid")): o for o in actual}
        expected_keys = {(o.get("type"), o.get("contents", {}).get("guid")) for o in expected}
        for item in expected:
            other = actual_by_guid.get((item.get("type"), item.get("contents", {}).get("guid")))
            if other is None:
                found.append(([element_label(item)], "object missing in nomac", item.get("contents", {}).get("path") or item.get("contents", {}).get("name"), None, []))
            else:
                differences(item, other, [element_label(item)], [], found)
        for item in actual:
            if (item.get("type"), item.get("contents", {}).get("guid")) not in expected_keys:
                found.append(([element_label(item)], "object only in nomac", None, item.get("contents", {}).get("path") or item.get("contents", {}).get("name"), []))
        if not found:
            return [("pif: synchronized GUIDs or signatures", "pif", detail, None)]
        classes = []
        for path, kind, xcode, nomac, context in found:
            lines = [f"at {path_text(path)}", f"in {' / '.join(context[-3:])}" if context else "", f"Xcode: {short(xcode)}", f"nomac: {short(nomac)}"]
            qualifier = f"; nomac {nomac!r}" if path[-1:] == ["fileType"] and kind == "value" else ""
            sample = f"{context[-1] if context else path_text(path)}: {short(xcode, 70)} -> {short(nomac, 70)}"
            classes.append((f"pif: {path_text(path)} ({kind}{qualifier})", "pif", [line for line in lines if line], sample))
        return classes

    def classify_list(self, spec, src, ref, work, container, flag, detail):
        proc = self.nomac_run(["list", flag, str(container), "-json", "--developer-dir", DEVELOPER_DIR], work / "home")
        (work / "list.json").write_bytes(proc.stdout)
        if proc.returncode != 0:
            return [("list: nomac list fails: " + normalize_message((tail(proc.stderr) or [""])[-1], src), tail(proc.stderr))]
        try:
            expected = json.loads((ref / "xcodebuild-list.json").read_text())
            actual = json.loads(proc.stdout)
        except json.JSONDecodeError:
            return [("list: json format", detail)]
        kind = "project" if "project" in expected else "workspace"
        a, b = expected.get(kind, {}), actual.get(kind, {})
        if set(expected) != set(actual):
            return [("list: container kind", detail)]
        result = []
        origins = scheme_origins(spec)
        for field in ("name", "configurations", "targets", "schemes"):
            if a.get(field) == b.get(field):
                continue
            if field != "schemes":
                result.append((f"list: {field}", [f"Xcode: {short(a.get(field))}", f"nomac: {short(b.get(field))}"]))
                continue
            missing = collections.Counter(a.get(field, [])) - collections.Counter(b.get(field, []))
            extra = collections.Counter(b.get(field, [])) - collections.Counter(a.get(field, []))
            for name in missing:
                result.append((f"list: scheme missing in nomac ({' + '.join(sorted(origins.get(name, {'unknown origin'})))})",
                               [f"scheme {name!r}", f"Xcode: {short(a.get(field))}", f"nomac: {short(b.get(field))}"]))
            for name in extra:
                result.append((f"list: scheme only in nomac ({' + '.join(sorted(origins.get(name, {'unknown origin'})))})",
                               [f"scheme {name!r}", f"Xcode: {short(a.get(field))}", f"nomac: {short(b.get(field))}"]))
            if not missing and not extra:
                result.append(("list: scheme order", [f"Xcode: {short(a.get(field))}", f"nomac: {short(b.get(field))}"]))
        return result or [("list: formatting", detail)]

    def classify_list_text(self, src, ref, work, container, flag):
        proc = self.nomac_run(["list", flag, str(container), "--developer-dir", DEVELOPER_DIR], work / "home")
        (work / "list.txt").write_bytes(proc.stdout)
        if proc.returncode != 0:
            return [("list-text: nomac list fails: " + normalize_message((tail(proc.stderr) or [""])[-1], src), tail(proc.stderr))]

        def sections(text):
            lines = text.splitlines()
            if lines and lines[0].startswith("Command line invocation:"):
                lines = lines[3:]
            packages = sorted(line for line in lines if line.startswith("  ") and not line.startswith("    ") and ": " in line)
            start = next((i for i, line in enumerate(lines) if line.startswith("Information about")), len(lines))
            return packages, lines[start:]
        expected = sections((ref / "xcodebuild-list.txt").read_text(errors="replace"))
        actual = sections(proc.stdout.decode(errors="replace"))
        if expected == actual:
            return []
        if expected[0] != actual[0]:
            return [("list-text: resolved packages", [f"Xcode: {short(expected[0])}", f"nomac: {short(actual[0])}"])]
        a, b = expected[1], actual[1]
        index = next((i for i in range(min(len(a), len(b))) if a[i] != b[i]), min(len(a), len(b)))
        header = next((a[i].strip() for i in range(min(index, len(a) - 1), -1, -1) if a[i].strip().endswith(":") or a[i].startswith("Information")), "")
        header = re.sub(r'"[^"]*"', '"…"', header)
        return [(f"list-text: {header or 'start'}", [f"line {index + 1}", f"Xcode: {a[index] if index < len(a) else '(end)'}",
                                                      f"nomac: {b[index] if index < len(b) else '(end)'}"])]


# ---------------------------------------------------------------------------------------------
# Minimization: remove parts of a spec while its class still shows.

NOT_SHRUNK = {"focus", "features", "regions"}
AT_LEAST_ONE = {"configs", "projects", "versions"}
DICT_SHRUNK = {"settings", "config_settings", "attributes", "flags", "explicit_types", "platform_filters", "values", "bases"}
NAME_KEYS = {"name", "path"}


def element_id(element):
    if isinstance(element, dict) and "id" in element:
        return element["id"]
    return hashlib.md5(json.dumps(element, sort_keys=True, ensure_ascii=False).encode()).hexdigest()[:8]


def shrink_candidates(spec):
    candidates = []

    def visit(value, path, depth):
        if isinstance(value, dict):
            parent_key = path[-1] if path else None
            if isinstance(parent_key, str) and parent_key in DICT_SHRUNK and value:
                keys = list(value)
                if len(keys) > 3:
                    for half in (keys[:len(keys) // 2], keys[len(keys) // 2:]):
                        candidates.append((depth, -len(half), f"{'/'.join(map(str, path))}-{{{','.join(half)}}}", path, ("keys", half)))
                for key in keys:
                    candidates.append((depth, -1, f"{'/'.join(map(str, path))}-{{{key}}}", path, ("keys", [key])))
            for key, item in value.items():
                if key in NOT_SHRUNK:
                    continue
                visit(item, path + [key], depth + 1)
        elif isinstance(value, list):
            key = path[-1] if path else None
            minimum = 1 if key in AT_LEAST_ONE else 0
            if len(value) > minimum:
                ids = [element_id(e) for e in value]
                if len(value) > 3 and len(value) - len(value) // 2 >= minimum:
                    for half in (ids[:len(ids) // 2], ids[len(ids) // 2:]):
                        candidates.append((depth, -len(half), f"{'/'.join(map(str, path))}-[{','.join(half)}]", path, ("items", half)))
                for element, ident in zip(value, ids):
                    candidates.append((depth, -spec_size(element), f"{'/'.join(map(str, path))}-[{ident}]", path, ("items", [ident])))
            for index, item in enumerate(value):
                visit(item, path + [index], depth + 1)
    visit(spec, [], 0)
    if spec.get("workspace") and len(spec["projects"]) == 1:
        candidates.insert(0, (0, -100, "workspace-none", ["workspace"], ("set", None)))
    candidates.sort(key=lambda c: (c[0], c[1]))
    for _, _, description, path, operation in candidates:
        yield description, apply_shrink(spec, path, operation)
    for description, candidate in rename_candidates(spec):
        yield description, candidate


def resolve(spec, path):
    value = spec
    for segment in path:
        value = value[segment]
    return value


def apply_shrink(spec, path, operation):
    copy = json.loads(json.dumps(spec))
    kind, payload = operation
    if kind == "set":
        resolve(copy, path[:-1])[path[-1]] = payload
        return copy
    target = resolve(copy, path)
    if kind == "keys":
        for key in payload:
            target.pop(key, None)
    else:
        target[:] = [e for e in target if element_id(e) not in set(payload)]
    return copy


def rename_candidates(spec):
    found = []

    def visit(value, path):
        if isinstance(value, dict):
            for key, item in value.items():
                if key in NAME_KEYS and isinstance(item, str) and item and not re.fullmatch(r"[A-Za-z0-9_./-]+", item):
                    found.append((path + [key], item))
                elif key not in NOT_SHRUNK:
                    visit(item, path + [key])
        elif isinstance(value, list):
            for index, item in enumerate(value):
                visit(item, path + [index])
    visit(spec, [])
    for index, (path, old) in enumerate(found):
        parts = old.split("/")
        plain = "/".join(re.sub(r"[^A-Za-z0-9_.]+", "", unicodedata.normalize("NFKD", part).encode("ascii", "ignore").decode()) or f"N{index}" for part in parts)
        if plain == old:
            continue
        copy = json.loads(json.dumps(spec))
        resolve(copy, path[:-1])[path[-1]] = plain
        yield f"rename {'/'.join(map(str, path))}", copy


def class_slug(key):
    return re.sub(r"[^A-Za-z0-9]+", "-", key).strip("-")[:70] + "-" + hashlib.md5(key.encode()).hexdigest()[:6]


def describe(spec):
    parts = []
    if spec.get("workspace"):
        parts.append(f"workspace {spec['workspace']['name']!r} with {len(spec['workspace']['items'])} items")
    for project in spec["projects"]:
        targets = ", ".join(f"{t['name']} ({t['kind']}{', synchronized' if t['sync'] else ''})" for t in project["targets"])
        extras = []
        for key in ("schemes", "user_schemes", "test_plans", "xcconfigs", "package_refs", "project_refs"):
            if project.get(key):
                extras.append(f"{len(project[key])} {key.replace('_', ' ')}")
        configs = ", ".join(c["name"] for c in project["configs"])
        parts.append(f"project {project['name']!r} (objectVersion {project['object_version']}; configurations {configs}; "
                     f"targets: {targets or 'none'}{'; ' + ', '.join(extras) if extras else ''})")
    if spec["packages"]:
        parts.append("packages: " + ", ".join(k["name"] for k in spec["packages"]))
    return "; ".join(parts)


class Minimizer:
    def __init__(self, runner, budget):
        self.runner = runner
        self.budget = budget

    def only_for(self, entry, case_dir):
        source = entry["check"]
        if source.startswith("settings:"):
            name = source.split(":", 1)[1]
            index = json.loads((case_dir / "ref" / "settings" / "index.json").read_text()) if (case_dir / "ref" / "settings" / "index.json").exists() else []
            item = next((i for i in index if i["name"] == name), None)
            if item is None:
                return None
            return {"check": "settings", "capture": {"name": name, "arguments": item["arguments"],
                                                     "json": (case_dir / "ref" / "settings" / f"{name}.json.cmd").exists()}}
        return {"check": source}

    def run(self, key, case_name):
        out = self.runner.out
        case_dir = out / "cases" / case_name
        spec = json.loads((case_dir / "spec.json").read_text())
        destination = out / "min" / class_slug(key)
        if destination.exists():
            shutil.rmtree(destination)
        destination.mkdir(parents=True)
        reproduce = self.runner.evaluate(spec, destination / "try")
        entry = next((c for c in reproduce["classes"] if c["key"] == key), None)
        log = [f"class: {key}", f"from case {case_name}, size {spec_size(spec)}"]
        if entry is None:
            log.append("the class did not show again on a fresh run")
            (destination / "minimize.log").write_text("\n".join(log) + "\n")
            shutil.rmtree(destination / "try", ignore_errors=True)
            return {"key": key, "reproduced": False}
        only = self.only_for(entry, destination / "try")
        current, evaluations, failed = spec, 1, set()
        progress = True
        while progress and evaluations < self.budget and not self.runner.stop.is_set():
            progress = False
            for description, candidate in shrink_candidates(current):
                if description in failed:
                    continue
                if evaluations >= self.budget or self.runner.stop.is_set():
                    break
                evaluations += 1
                result = self.runner.evaluate(candidate, destination / "try", only)
                if any(c["key"] == key for c in result["classes"]):
                    current = candidate
                    progress = True
                    log.append(f"kept: {description} (size {spec_size(current)})")
                    break
                failed.add(description)
        shutil.rmtree(destination / "try", ignore_errors=True)
        final = self.runner.evaluate(current, destination / "case", only)
        holds = any(c["key"] == key for c in final["classes"])
        log.append(f"{evaluations} evaluations; minimal size {spec_size(current)}; class {'shows' if holds else 'does not show'} on the last run")
        (destination / "minimize.log").write_text("\n".join(log) + "\n")
        summary = {"key": key, "reproduced": True, "from": case_name, "evaluations": evaluations, "size": spec_size(current),
                   "holds": holds, "description": describe(current), "case": str(destination / "case"),
                   "container": final.get("container"),
                   "entry": next((c for c in final["classes"] if c["key"] == key), entry)}
        (destination / "summary.json").write_text(json.dumps(summary, indent=1, ensure_ascii=False) + "\n")
        return summary


# ---------------------------------------------------------------------------------------------
# Findings.

def load_results(out):
    results = {}
    for path in sorted((out / "cases").glob("*/result.json")):
        try:
            results[path.parent.name] = json.loads(path.read_text())
        except json.JSONDecodeError:
            continue
    return results


def class_table(results):
    classes = collections.defaultdict(list)
    for name, result in results.items():
        for entry in result.get("classes", []):
            classes[entry["key"]].append(name)
    return sorted(classes.items(), key=lambda item: (-len(item[1]), item[0]))


def summary_text(results):
    statuses = collections.Counter(r["status"] for r in results.values())
    table = class_table(results)
    lines = [f"cases: {len(results)} ({statuses.get('identical', 0)} identical, {statuses.get('equivalent', 0)} equivalent, {statuses.get('different', 0)} different, "
             f"{statuses.get('invalid', 0)} rejected by Xcode, {statuses.get(None, 0)} incomplete); {len(table)} classes"]
    for key, cases in table[:15]:
        lines.append(f"  {len(cases):4d}  {key}")
    return "\n".join(lines)


def write_findings(out):
    results = load_results(out)
    valid = {n: r for n, r in results.items() if r["status"] in ("identical", "equivalent", "different")}
    table = class_table(results)
    hypotheses = json.loads((out / "hypotheses.json").read_text()) if (out / "hypotheses.json").exists() else {}
    feature_rate = collections.Counter(f for r in valid.values() for f in r.get("features", []))
    lines = ["# nomac differential fuzzing: findings", "",
             f"Generated by `.github/scripts/fuzz_experiments.py` on {time.strftime('%Y-%m-%d %H:%M')} against Xcode "
             f"{json.loads((out / 'host.json').read_text())['xcodeBuild'] if (out / 'host.json').exists() else '?'}.", "",
             "```", summary_text(results), "```", ""]
    invalid = [n for n, r in results.items() if r["status"] == "invalid"]
    if invalid:
        lines += [f"Cases Xcode rejected (generator limits, not nomac): {', '.join(invalid[:10])}{' …' if len(invalid) > 10 else ''}", ""]
    lines += ["A class is a differing PIF path (every one of a case's PIF, list indices folded), a `-list` entry, or the first "
              "differing setting of a `-showBuildSettings` capture. Rerun a case with `fuzz_experiments.py case <seed> "
              "--focus <features>`; a minimal case's project is in its `src`.", ""]
    for rank, (key, cases) in enumerate(table, 1):
        minimal = out / "min" / class_slug(key) / "summary.json"
        summary = json.loads(minimal.read_text()) if minimal.exists() else None
        representative = min(cases, key=lambda n: results[n]["size"])
        result = results[representative]
        entry = next(c for c in result["classes"] if c["key"] == key)
        lift = []
        for feature in sorted({f for n in cases for f in results[n].get("features", [])}):
            share = sum(feature in results[n].get("features", []) for n in cases) / len(cases)
            base = feature_rate[feature] / max(len(valid), 1)
            if share >= 0.6 and share > base * 1.3:
                lift.append(f"{feature} {share:.0%} (all cases {base:.0%})")
        together = collections.Counter(c["key"] for n in cases for c in results[n]["classes"] if c["key"] != key)
        lines += [f"## {rank}. `{key}`", "",
                  f"- Cases: {len(cases)} ({len(cases) / max(len(valid), 1):.0%} of valid cases); smallest: `{representative}` "
                  f"(seed {result['seed']}{', focus ' + ','.join(result['focus']) if result['focus'] else ''})"]
        if summary and summary.get("reproduced"):
            lines.append(f"- Minimal case: `{summary['case']}/src` (container `{summary.get('container')}`), size {summary['size']} "
                         f"after {summary['evaluations']} runs{'' if summary['holds'] else ' (class did not show on its last run)'}: "
                         f"{summary['description']}")
            entry = summary["entry"]
        elif summary:
            lines.append("- Minimal case: none, the class did not show again on a fresh run (flaky or order-dependent)")
        else:
            lines.append(f"- Minimal case: not minimized; smallest case `{out / 'cases' / representative}`")
        if lift:
            lines.append(f"- Features over-represented: {'; '.join(lift)}")
        if together:
            lines.append("- Often with: " + "; ".join(f"`{k}` ({v})" for k, v in together.most_common(3)))
        samples = []
        for name in cases:
            sample = next((c.get("sample") for c in results[name]["classes"] if c["key"] == key), None)
            if sample and sample not in samples:
                samples.append(sample)
        if len(samples) > 1:
            lines.append(f"- Distinct instances ({len(samples)}): " + "; ".join(f"`{s}`" for s in samples[:12]) + (" …" if len(samples) > 12 else ""))
        lines += ["- Diff excerpt:", "", "```"] + [d for d in entry["detail"][:10]] + ["```", ""]
        lines += [f"Hypothesis: {hypotheses.get(key, 'not analysed yet')}", ""]
    (out / "FINDINGS.md").write_text("\n".join(lines) + "\n")
    return out / "FINDINGS.md"


# ---------------------------------------------------------------------------------------------
# Commands.

def case_name(seed, focus):
    return f"{'+'.join(sorted(focus)) or 'all'}-{seed:05d}"


def prune_case(case_dir):
    for name in ("src", "ref"):
        shutil.rmtree(case_dir / name, ignore_errors=True)
    for path in (case_dir / "nomac").glob("*.pif"):
        path.unlink()


def run_cases(runner, seeds, focus, jobs):
    results = {}
    total = len(seeds)

    def one(seed):
        if runner.stop.is_set():
            return seed, None
        runner.check_disk()
        if runner.stop.is_set():
            return seed, None
        spec = Generator(seed, focus).generate()
        case_dir = runner.out / "cases" / case_name(seed, focus)
        try:
            result = runner.evaluate(spec, case_dir)
        except Exception as error:
            result = {"seed": seed, "focus": sorted(focus), "status": None, "classes": [], "error": repr(error)}
            (case_dir / "result.json").write_text(json.dumps(result) + "\n")
        if result["status"] in ("identical", "equivalent") and not runner.keep:
            prune_case(case_dir)
        return seed, result

    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        for done, future in enumerate(concurrent.futures.as_completed([pool.submit(one, s) for s in seeds]), 1):
            seed, result = future.result()
            if result is None:
                continue
            results[seed] = result
            keys = "; ".join(c["key"] for c in result["classes"][:3]) + (" …" if len(result["classes"]) > 3 else "")
            print(f"[{done}/{total}] {case_name(seed, focus)}: {result['status']} {result.get('seconds', '')}s {keys or result.get('reason', '') or result.get('error', '')}", flush=True)
    return results


def minimize_classes(runner, jobs, budget, max_classes):
    results = load_results(runner.out)
    work = []
    for key, cases in class_table(results)[:max_classes]:
        if (runner.out / "min" / class_slug(key) / "summary.json").exists():
            continue
        representative = min(cases, key=lambda n: results[n]["size"])
        if not (runner.out / "cases" / representative / "spec.json").exists():
            continue
        work.append((key, representative))
    minimizer = Minimizer(runner, budget)
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        futures = {pool.submit(minimizer.run, key, case): key for key, case in work}
        for future in concurrent.futures.as_completed(futures):
            key = futures[future]
            try:
                summary = future.result()
                print(f"[minimize] {key}: size {summary.get('size', '-')} ({summary.get('evaluations', 0)} runs)", flush=True)
            except Exception as error:
                print(f"[minimize] {key}: failed: {error!r}", flush=True)


def prune_nonrepresentatives(out):
    results = load_results(out)
    keep = {min(cases, key=lambda n: results[n]["size"]) for _, cases in class_table(results)}
    for name in results:
        if name not in keep:
            prune_case(out / "cases" / name)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("run", "case", "minimize", "findings"):
        command = sub.add_parser(name)
        command.add_argument("--out", type=Path, default=DEFAULT_OUT)
        command.add_argument("--nomac", type=Path, default=DEFAULT_NOMAC)
        command.add_argument("--jobs", type=int, default=4)
        command.add_argument("--budget", type=int, default=40, help="runs per minimization")
        command.add_argument("--max-classes", type=int, default=30, help="minimize at most this many classes, most frequent first")
        command.add_argument("--focus", default="", help="comma-separated features to force (see FEATURES)")
        if name == "run":
            command.add_argument("--cases", type=int, default=100)
            command.add_argument("--start", type=int, default=1)
            command.add_argument("--no-minimize", action="store_true")
            command.add_argument("--keep", action="store_true", help="keep the files of identical cases")
        if name == "case":
            command.add_argument("seed", type=int)
    args = parser.parse_args()
    focus = [f for f in args.focus.split(",") if f]
    unknown = [f for f in focus if f not in FEATURES]
    if unknown:
        sys.exit(f"error: unknown features {unknown}; known: {', '.join(FEATURES)}")
    out = args.out.expanduser().resolve()
    if args.command == "findings":
        print(write_findings(out))
        return
    if not Path(args.nomac).exists():
        sys.exit(f"error: no nomac at {args.nomac}")
    runner = Runner(out, args.nomac.expanduser().resolve(), keep=getattr(args, "keep", False) or args.command == "case")
    if args.command == "case":
        spec = Generator(args.seed, focus).generate()
        result = runner.evaluate(spec, out / "cases" / case_name(args.seed, focus))
        print(json.dumps(result, indent=1, ensure_ascii=False))
        return
    started = time.time()
    runner.clean_stale_derived_data()
    if args.command == "run":
        run_cases(runner, list(range(args.start, args.start + args.cases)), focus, args.jobs)
        if not args.no_minimize and not runner.stop.is_set():
            minimize_classes(runner, args.jobs, args.budget, args.max_classes)
    else:
        minimize_classes(runner, args.jobs, args.budget, args.max_classes)
    runner.clean_stale_derived_data()
    prune_nonrepresentatives(out)
    write_findings(out)
    print(summary_text(load_results(out)))
    print(f"[fuzz] {time.time() - started:.0f}s{'; stopped: ' + runner.stop_reason if runner.stop_reason else ''}; findings: {out / 'FINDINGS.md'}")


if __name__ == "__main__":
    main()
