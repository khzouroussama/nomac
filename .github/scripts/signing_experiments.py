#!/usr/bin/env python3
"""Observe how Xcode signs and packages an iOS app, for nomac's signing and IPA writers.

Runs on a macOS machine with Xcode 27.0 (docs/VERIFICATION.md "Without CI"). Every project is
written here from scratch:

- adhoc: an app with resources (a plain file, a localized strings file, a folder reference),
  an embedded framework and a share extension that links it, archived with ad-hoc signing
  (`CODE_SIGN_IDENTITY=-`) with every codesign step captured (`CODESIGN_WRAPPER`), then
  exported with `xcodebuild -exportArchive` for the methods `debugging`, `release-testing`,
  `enterprise` and `app-store-connect`.
- nested: the same with three frameworks and two extensions, embedded in an order that is
  neither alphabetical nor APFS order, for the order in which the export signs them.
- symbols: the adhoc app with C, Objective-C and C++ sources besides Swift (among them eight C
  files with a static function of one name), for the `Symbols/*.symbols` files of
  app-store-connect exports, also exported without symbols.
- span: the adhoc app whose code uses `Span`'s type metadata, which below iOS 26 the compiler
  takes from the back-deployment library `@rpath/libswiftCompatibilitySpan.dylib` (toolchain
  `usr/lib/swift-6.2/iphoneos`), for how the archive embeds and signs it and how each export
  method packages it. span-framework: the app and Kit use it; span-kit: only Kit does;
  span-26: the app uses it with iOS 26.0 as deployment target, where it is not needed;
  span-nested and span-order (a framework named in lower case), for where the library falls
  in the export's signing order.
- odr-shapes: the odr app's archive exported with the on-demand resources shapes B-312 lists
  (a base URL ending in `/`, a base URL with embedding, a manifest for app-store-connect, and
  asset packs with a 0600 file, a link or an XML Info.plist).
- names: the app alone with files of UNICODE_NAMES in its Content folder, archived ad hoc and
  exported (`debugging`, `app-store-connect`), for the order of non-ASCII names in
  CodeResources and the IPA (B-304).
- framework-static: the app with Kit as a static framework (`MACH_O_TYPE` `staticlib`, as
  CocoaPods' `use_frameworks! :linkage => :static` makes); framework-codeless: the app with Kit
  and a framework without sources, `Assets`; both archived ad hoc and exported for `debugging`,
  for `--generate-pre-encrypt-hashes`, which Swift Build adds for static and codeless frameworks.
- entitlements-groups, entitlements-push, entitlements-keychain: the app alone with an
  entitlements file holding an app group, `aps-environment` or a keychain group, archived ad hoc
  and exported for `debugging`, for what Xcode signs (or refuses) under ad hoc (B-114).
- refusals: the adhoc app's archive exported without a team, and after signing the app again
  with entitlements: both exports xcodebuild refuses.
- umask: the adhoc app archived and exported (`debugging`, `app-store-connect`) with the file mode creation mask
  002, for which modes follow the umask (`compare` and `compare-export` run nomac with the
  same mask).
- archive-names: the adhoc app whose product is named Shop, archived by its scheme App (not
  exported), for the archive's names; archive-nodsym: the adhoc app archived without dSYMs
  (`DEBUG_INFORMATION_FORMAT=dwarf`); archive-nested-dsyms: the app with Kit whose last phase
  puts dSYMs in subfolders of the products folder (NESTED_DSYMS_SCRIPT), for which the archive
  collects.
- watch: the app with Kit embedding a single-target SwiftUI watchOS app in `Watch/`; appclip:
  the app with Kit embedding an App Clip in `AppClips/`; watch-appclip: both with Kit and
  Share, for the signing order of nested apps and the watch binaries' signatures. Xcode refuses
  to archive an App Clip with ad-hoc signing: appclip, watch-appclip, appclip-entitlements
  (with `parent-application-identifiers`) and appclip-no-entitlements (`ENTITLEMENTS_ALLOWED`
  NO) stop with "requires a provisioning profile", appclip-unsigned with "Embedded binary is
  not signed with the same certificate as the parent app". appclip-script and
  watch-appclip-script sign the clip ad hoc in a script phase instead, for what the exports
  do with an archive holding an App Clip.

For each experiment the products, the build logs and the exit status are kept under
`<output-dir>/<name>`. No Xcode output other than for these self-written projects is kept.

Usage: signing_experiments.py <output-dir> [experiment ...]
       signing_experiments.py compare <output-dir> <nomac>
       signing_experiments.py synthetic <observe-dir>
       signing_experiments.py compare-export <output-dir> <nomac>
       signing_experiments.py synthetic-export <observe-dir>
       signing_experiments.py compare-symbols <output-dir> <nomac>
       signing_experiments.py compare-archive <output-dir> <nomac>

`compare` replays every captured signing step with `nomac codesign` (the same arguments, on a
copy of the product as it was before codesign ran) and compares the result with codesign's,
file by file: names, types, permissions, symbolic link targets and contents, and what it
printed on standard output (the requirement `-r- --display` shows).

`synthetic` signs the self-authored inputs the NomacSigning tests leave in <observe-dir> when
run with `NOMAC_SIGNING_OBSERVE=<observe-dir>`, with the codesign arguments each test uses, and
prints the SHA-256 of every file codesign leaves: the values those tests expect (and converts
the property lists they leave with `plutil -convert xml1`). Certificate
cases sign with the test's identity file imported into a throwaway keychain (openssl and
security), which is on the user's keychain search list only while codesign runs and deleted
afterwards; they also print the signing time.

`synthetic-export` exports the archive the NomacPackaging tests leave in <observe-dir>/export
(run with `NOMAC_PACKAGING_OBSERVE=<observe-dir>`) with xcodebuild and prints the SHA-256 of each
file of the export (the IPA with its entry times and owner ids cleared), the same for the archive
with an App Clip in <observe-dir>/clip and for the app-store-connect export of
<observe-dir>/appstore (binary Info.plists, SwiftSupport, no symbols), <observe-dir>/nodsyms
(an archive without dSYMs), the OTA manifests of <observe-dir>/manifest and
<observe-dir>/manifest-app-url and the on-demand resources of <observe-dir>/odr, odr-appstore and
odr-hosted (the files of subfolders by path, hosted asset packs as zips also without their central
extra fields), and the SHA-256 of each `.symbols` file of the
app-store-connect exports of <observe-dir>/symbols and <observe-dir>/watch (a watch app with a
universal dSYM): the values those tests expect.

`compare-export` runs `nomac export` on each experiment's archive with the options of each of
Xcode's exports and compares the folders: the plists byte for byte, the IPA byte for byte after
setting aside what each entry records of the clock and the machine (DOS time and date, the "UX"
extra field's times and owner ids); for the exports xcodebuild refused, it compares nomac's exit
status and error messages with xcodebuild's.

`compare-symbols` runs `nomac symbols` on the dSYMs of each experiment's archive and compares
its `.symbols` files with those of the app-store-connect export, byte for byte.

`compare-archive` assembles each experiment's archive again with `nomac xcarchive`, from the
build's `BuildProductsPath` (kept beside the archive) and the archive's `Products`, and compares
it with xcodebuild's file by file, modification times included, `Info.plist`'s `CreationDate`
aside.

xcodebuild runs without network access (`OFFLINE`); the experiments' apps use no Swift macros, which
cannot expand under sandbox-exec (docs/VERIFICATION.md "Signing and export checks").
"""

import contextlib
import hashlib
import io
import json
import os
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

HEADER = """// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 77;
	objects = {{
{objects}	}};
	rootObject = {root} /* Project object */;
}}
"""

BASE_SETTINGS = {
    "SDKROOT": "iphoneos",
    "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
    "SWIFT_VERSION": "5.0",
    "CODE_SIGN_STYLE": "Manual",
    "TARGETED_DEVICE_FAMILY": '"1,2"',
    "ALWAYS_SEARCH_USER_PATHS": "NO",
}

# iOS refuses ad-hoc signing ("Ad Hoc code signing is not allowed with SDK 'iOS 27.0'", and
# "requires a provisioning profile") unless both checks are turned off.
ADHOC = ["CODE_SIGN_IDENTITY=-", "AD_HOC_CODE_SIGNING_ALLOWED=YES", "PROVISIONING_PROFILE_REQUIRED=NO"]


class Project:
    """A project file built from explicit objects, with sequential object identifiers."""

    def __init__(self):
        self.objects = []
        self.counter = 0
        self.main_children = []
        self.products = []
        self.targets = []
        self.package_references = []

    def identifier(self):
        self.counter += 1
        return f"A{self.counter:023X}"

    def add(self, text):
        self.objects.append(text)

    def file(self, path, file_type, name=None, group=True):
        identifier = self.identifier()
        name_text = f" name = {quote(name)};" if name else ""
        self.add(f"\t\t{identifier} = {{isa = PBXFileReference; lastKnownFileType = {quote(file_type)};{name_text} "
                 f"path = {quote(path)}; sourceTree = \"<group>\"; }};\n")
        if group:
            self.main_children.append(identifier)
        return identifier

    def variant_group(self, folder, name, regions, file_type):
        children = []
        for region in regions:
            identifier = self.identifier()
            self.add(f"\t\t{identifier} = {{isa = PBXFileReference; lastKnownFileType = {quote(file_type)}; name = {region}; "
                     f"path = {quote(f'{folder}/{region}.lproj/{name}')}; sourceTree = \"<group>\"; }};\n")
            children.append(identifier)
        group = self.identifier()
        listed = "".join(f"\t\t\t\t{child},\n" for child in children)
        self.add(f"\t\t{group} = {{\n\t\t\tisa = PBXVariantGroup;\n\t\t\tchildren = (\n{listed}\t\t\t);\n"
                 f"\t\t\tname = {quote(name)};\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
        self.main_children.append(group)
        return group

    def build_file(self, reference, attributes=None, asset_tags=None):
        identifier = self.identifier()
        settings = []
        if attributes:
            settings.append(f"ATTRIBUTES = ({', '.join(attributes)}, ); ")
        if asset_tags:
            settings.append(f"ASSET_TAGS = ({', '.join(asset_tags)}, ); ")
        settings_text = f" settings = {{{''.join(settings)}}};" if settings else ""
        self.add(f"\t\t{identifier} = {{isa = PBXBuildFile; fileRef = {reference};{settings_text} }};\n")
        return identifier

    def local_package(self, path):
        """An XCLocalSwiftPackageReference to the package folder `path`."""
        identifier = self.identifier()
        self.add(f"\t\t{identifier} = {{isa = XCLocalSwiftPackageReference; relativePath = {quote(path)}; }};\n")
        self.package_references.append(identifier)
        return identifier

    def package_product(self, package, name, attributes=None):
        """An XCSwiftPackageProductDependency and the PBXBuildFile that links it."""
        dependency = self.identifier()
        self.add(f"\t\t{dependency} = {{isa = XCSwiftPackageProductDependency; package = {package}; productName = {quote(name)}; }};\n")
        return dependency, self.product_build_file(dependency, attributes)

    def product_build_file(self, dependency, attributes=None):
        """A PBXBuildFile of a package product, as the frameworks phase or Embed Frameworks has it."""
        build_file = self.identifier()
        settings = f" settings = {{ATTRIBUTES = ({', '.join(attributes)}, ); }};" if attributes else ""
        self.add(f"\t\t{build_file} = {{isa = PBXBuildFile; productRef = {dependency};{settings} }};\n")
        return build_file

    def phase(self, isa, files, extra=""):
        identifier = self.identifier()
        listed = "".join(f"\t\t\t\t{f},\n" for f in files)
        self.add(f"\t\t{identifier} = {{\n\t\t\tisa = {isa};\n\t\t\tbuildActionMask = 2147483647;\n{extra}"
                 f"\t\t\tfiles = (\n{listed}\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
        return identifier

    def copy_phase(self, name, subfolder, files, path=""):
        return self.phase("PBXCopyFilesBuildPhase", files,
                          f"\t\t\tdstPath = {quote(path)};\n\t\t\tdstSubfolderSpec = {subfolder};\n\t\t\tname = {quote(name)};\n")

    def script_phase(self, name, script):
        identifier = self.identifier()
        self.add(f"\t\t{identifier} = {{\n\t\t\tisa = PBXShellScriptBuildPhase;\n\t\t\talwaysOutOfDate = 1;\n"
                 f"\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\tinputPaths = (\n\t\t\t);\n"
                 f"\t\t\tname = {quote(name)};\n\t\t\toutputPaths = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
                 f"\t\t\tshellPath = /bin/sh;\n\t\t\tshellScript = {quote(script)};\n\t\t}};\n")
        return identifier

    def configurations(self, settings):
        debug, release, configuration_list = self.identifier(), self.identifier(), self.identifier()
        for identifier, name in ((debug, "Debug"), (release, "Release")):
            body = "".join(f"\t\t\t\t{key} = {value};\n" for key, value in settings.items())
            self.add(f"\t\t{identifier} = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n{body}\t\t\t}};\n"
                     f"\t\t\tname = {name};\n\t\t}};\n")
        self.add(f"\t\t{configuration_list} = {{\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n"
                 f"\t\t\t\t{debug},\n\t\t\t\t{release},\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n"
                 f"\t\t\tdefaultConfigurationName = Release;\n\t\t}};\n")
        return configuration_list

    def target(self, name, product_type, product_path, file_type, phases, settings, dependencies=(), package_products=()):
        product = self.identifier()
        self.add(f"\t\t{product} = {{isa = PBXFileReference; explicitFileType = {quote(file_type)}; includeInIndex = 0; "
                 f"path = {quote(product_path)}; sourceTree = BUILT_PRODUCTS_DIR; }};\n")
        self.products.append(product)
        target = self.identifier()
        configuration_list = self.configurations(settings)
        dependency_ids = []
        for dependency_target, dependency_name in dependencies:
            proxy, dependency = self.identifier(), self.identifier()
            self.add(f"\t\t{proxy} = {{\n\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = {ROOT};\n\t\t\tproxyType = 1;\n"
                     f"\t\t\tremoteGlobalIDString = {dependency_target};\n\t\t\tremoteInfo = {quote(dependency_name)};\n\t\t}};\n")
            self.add(f"\t\t{dependency} = {{\n\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = {dependency_target};\n"
                     f"\t\t\ttargetProxy = {proxy};\n\t\t}};\n")
            dependency_ids.append(dependency)
        phase_list = "".join(f"\t\t\t\t{p},\n" for p in phases)
        dependency_list = "".join(f"\t\t\t\t{d},\n" for d in dependency_ids)
        self.add(f"\t\t{target} = {{\n\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = {configuration_list};\n"
                 f"\t\t\tbuildPhases = (\n{phase_list}\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n"
                 f"\t\t\tdependencies = (\n{dependency_list}\t\t\t);\n\t\t\tname = {quote(name)};\n"
                 + (f"\t\t\tpackageProductDependencies = ({''.join(f'{p}, ' for p in package_products)});\n" if package_products else "")
                 + f"\t\t\tproductName = {quote(name)};\n\t\t\tproductReference = {product};\n"
                 f"\t\t\tproductType = \"{product_type}\";\n\t\t}};\n")
        self.targets.append(target)
        return target, product

    def aggregate(self, name, dependencies):
        """A PBXAggregateTarget building `dependencies` (target, name) pairs."""
        target, configuration_list = self.identifier(), self.configurations({"PRODUCT_NAME": '"$(TARGET_NAME)"'})
        dependency_ids = []
        for dependency_target, dependency_name in dependencies:
            proxy, dependency = self.identifier(), self.identifier()
            self.add(f"\t\t{proxy} = {{\n\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = {ROOT};\n\t\t\tproxyType = 1;\n"
                     f"\t\t\tremoteGlobalIDString = {dependency_target};\n\t\t\tremoteInfo = {quote(dependency_name)};\n\t\t}};\n")
            self.add(f"\t\t{dependency} = {{\n\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = {dependency_target};\n"
                     f"\t\t\ttargetProxy = {proxy};\n\t\t}};\n")
            dependency_ids.append(dependency)
        dependency_list = "".join(f"\t\t\t\t{d},\n" for d in dependency_ids)
        self.add(f"\t\t{target} = {{\n\t\t\tisa = PBXAggregateTarget;\n\t\t\tbuildConfigurationList = {configuration_list};\n"
                 f"\t\t\tbuildPhases = (\n\t\t\t);\n\t\t\tdependencies = (\n{dependency_list}\t\t\t);\n"
                 f"\t\t\tname = {quote(name)};\n\t\t\tproductName = {quote(name)};\n\t\t}};\n")
        self.targets.append(target)
        return target

    def text(self):
        root, main_group, products_group = ROOT, self.identifier(), self.identifier()
        products = "".join(f"\t\t\t\t{p},\n" for p in self.products)
        children = "".join(f"\t\t\t\t{c},\n" for c in self.main_children + [products_group])
        self.add(f"\t\t{products_group} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n{products}\t\t\t);\n"
                 f"\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
        self.add(f"\t\t{main_group} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n{children}\t\t\t);\n"
                 f"\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
        configuration_list = self.configurations({"SDKROOT": "iphoneos"})
        targets = "".join(f"\t\t\t\t{t},\n" for t in self.targets)
        self.add(f"\t\t{root} /* Project object */ = {{\n\t\t\tisa = PBXProject;\n\t\t\tattributes = {{\n"
                 f"\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastUpgradeCheck = 2700;\n\t\t\t}};\n"
                 f"\t\t\tbuildConfigurationList = {configuration_list};\n\t\t\tdevelopmentRegion = en;\n"
                 f"\t\t\thasScannedForEncodings = 0;\n\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t\tfr,\n\t\t\t);\n"
                 f"\t\t\tmainGroup = {main_group};\n\t\t\tminimizedProjectReferenceProxies = 1;\n"
                 + (f"\t\t\tpackageReferences = ({''.join(f'{p}, ' for p in self.package_references)});\n" if self.package_references else "")
                 + f"\t\t\tpreferredProjectObjectVersion = 77;\n\t\t\tproductRefGroup = {products_group};\n"
                 f"\t\t\tprojectDirPath = \"\";\n\t\t\tprojectRoot = \"\";\n\t\t\ttargets = (\n{targets}\t\t\t);\n\t\t}};\n")
        return HEADER.format(objects="".join(self.objects), root=root)


ROOT = "F00000000000000000000001"


def quote(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


APP_SOURCE = """import UIKit
import Kit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        let controller = UIViewController()
        controller.title = Greeting.text
        window?.rootViewController = controller
        window?.makeKeyAndVisible()
        return true
    }
}
"""

KIT_SOURCE = """public enum Greeting {
    public static let text = "Hello from Kit"
}
"""

SHARE_SOURCE = """import UIKit
import Kit

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = Greeting.text
    }
}
"""

SHARE_INFO = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionAttributes</key>
		<dict>
			<key>NSExtensionActivationRule</key>
			<string>TRUEPREDICATE</string>
		</dict>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.share-services</string>
		<key>NSExtensionPrincipalClass</key>
		<string>$(PRODUCT_MODULE_NAME).ShareViewController</string>
	</dict>
</dict>
</plist>
"""


# Code of several languages for the `.symbols` files of app-store-connect exports: generic and
# closure-taking Swift, two C files with a static function of the same name, a forced-inline C
# function, an Objective-C class with instance and class methods and a block, and C++ templates
# in a namespace.
NATIVE_APP_SOURCE = """import UIKit
import Kit

struct Box<T> {
    var value: T
    func map<U>(_ transform: (T) -> U) -> Box<U> { Box<U>(value: transform(value)) }
}

protocol Shape { func area() -> Int }

struct Square: Shape {
    let side: Int
    func area() -> Int { side * side }
}

@inline(never) func total(_ shapes: [any Shape]) -> Int {
    shapes.reduce(0) { $0 + $1.area() }
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        let controller = UIViewController()
        let box = Box(value: 21).map { $0 * 2 }
        let sum = total([Square(side: 3), Square(side: Int(plain_value(4)))]) + Int(other_value(5))
            + Int(shapes_area(2, 3)) + Native.shared().twice(box.value)
        controller.title = Greeting.text + String(sum)
        window?.rootViewController = controller
        window?.makeKeyAndVisible()
        return true
    }
}
"""

# Static functions of one name in several files, kept by `used` callers: symbols that share a name.
DUPLICATES = {f"App/Dup{i}.c": (f"static __attribute__((noinline)) int helper(int x) {{ return x * {i + 2}; }}\n"
                                f"__attribute__((used)) int dup{i}(int x) {{ return helper(x); }}\n", "sourcecode.c.c") for i in range(8)}

NATIVE_SOURCES = {
    "App/Bridge.h": ("""#import <Foundation/Foundation.h>

int plain_value(int x);
int other_value(int x);
int shapes_area(int width, int height);

@interface Native : NSObject
+ (instancetype)shared;
- (NSInteger)twice:(NSInteger)value;
@end
""", "sourcecode.c.h"),
    "App/Plain.c": ("""static inline __attribute__((always_inline)) int add(int a, int b) { return a + b; }

static __attribute__((noinline)) int helper(int x) { return add(x, 3) * 2; }

int plain_value(int x) { return helper(x) + add(x, 2); }
""", "sourcecode.c.c"),
    "App/Other.c": ("""static __attribute__((noinline)) int helper(int x) { return x * 5 + 1; }

int other_value(int x) { return helper(x) - 1; }
""", "sourcecode.c.c"),
    "App/Native.m": ("""#import "Bridge.h"

static NSInteger doubled(NSInteger value) { return value * 2; }

@implementation Native
+ (instancetype)shared {
    static Native *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[Native alloc] init]; });
    return shared;
}
- (NSInteger)twice:(NSInteger)value {
    NSInteger (^apply)(NSInteger) = ^NSInteger(NSInteger v) { return doubled(v); };
    return apply(value);
}
@end
""", "sourcecode.c.objc"),
    "App/Shapes.cpp": ("""namespace shapes {
template <typename T> struct Rect {
    T width, height;
    T area() const { return width * height; }
};

template <typename T> __attribute__((noinline)) T area(T width, T height) { return Rect<T>{width, height}.area(); }
}

extern "C" int shapes_area(int width, int height) { return shapes::area<int>(width, height) + (int)shapes::area<long>(width, 1); }
""", "sourcecode.cpp.cpp"),
    **DUPLICATES,
}


# `Array.span` needs iOS 26; `Span(_unsafeElements:)` and `Span<Int>.self` compile for iOS 18
# and reference `$ss4SpanVMn`, which the compiler links from libswiftCompatibilitySpan.dylib.
SPAN_USE = """        [1, 2, 3].withUnsafeBufferPointer { buffer in
            let span = Span(_unsafeElements: buffer)
            print(span.count, Span<Int>.self)
        }
"""

WATCH_SOURCE = """import SwiftUI

@main
struct WatchApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Hello from the watch")
        }
    }
}
"""

WATCH_INFO = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>WKApplication</key>
	<true/>
</dict>
</plist>
"""

CLIP_SOURCE = """import UIKit

@main
final class ClipDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = UIViewController()
        window?.makeKeyAndVisible()
        return true
    }
}
"""

CLIP_INFO = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSAppClip</key>
	<dict>
		<key>NSAppClipRequestEphemeralUserNotification</key>
		<false/>
		<key>NSAppClipRequestLocationConfirmation</key>
		<false/>
	</dict>
</dict>
</plist>
"""

EMPTY_ENTITLEMENTS = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
"""

def entitlements_file(entries):
    """An entitlements file holding `entries` (XML lines for a dictionary's keys and values)."""
    return EMPTY_ENTITLEMENTS.replace("<dict/>", "<dict>\n" + entries + "</dict>")


# File names whose orders differ by encoding (B-304): a precomposed and a decomposed accent, a
# folder with accents, a character above U+FFFF (UTF-16 surrogates sort it before U+E000 and
# U+FF21, UTF-8 after), a private-use one, a fullwidth one, and lower and upper case.
UNICODE_NAMES = ["caf\u00e9.txt", "cafe\u0301x.txt", "\U0001F600.txt", "\ue000.txt", "\uff21.txt", "z.txt", "B.txt",
                 "\u00c9t\u00e9/inner.txt", "\u00e9t\u00e9-lower.txt"]

# Entitlements an app may hold, for what Xcode does with them under ad-hoc signing (B-114).
GROUPS_ENTITLEMENTS = entitlements_file(
    "\t<key>com.apple.security.application-groups</key>\n\t<array>\n\t\t<string>group.org.nomac.signing</string>\n\t</array>\n")
PUSH_ENTITLEMENTS = entitlements_file("\t<key>aps-environment</key>\n\t<string>development</string>\n")
KEYCHAIN_ENTITLEMENTS = entitlements_file(
    "\t<key>keychain-access-groups</key>\n\t<array>\n\t\t<string>$(AppIdentifierPrefix)org.nomac.signing</string>\n\t</array>\n")

CLIP_ENTITLEMENTS = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.parent-application-identifiers</key>
	<array>
		<string>$(AppIdentifierPrefix)org.nomac.signing</string>
	</array>
</dict>
</plist>
"""

# An App Clip's product type adds the entitlement com.apple.developer.on-demand-install-capable,
# so Xcode refuses to sign it ad hoc ("requires a provisioning profile"); its app refuses an
# unsigned one ("Embedded binary is not signed with the same certificate as the parent app").
CLIP_SIGN_SCRIPT = ('"${CODESIGN}" --force --sign - --timestamp=none --generate-entitlement-der '
                    '"${TARGET_BUILD_DIR}/${WRAPPER_NAME}"')

STORE_SOURCE = """public struct Store {
    public static func count(_ items: [Int]) -> Int { items.reduce(0, +) }
}
"""

PLUGIN_SOURCE = """import Foundation

@objc(Plugin) public final class Plugin: NSObject {
    @objc public static func name() -> String { "plugin" }
}
"""


INTENTS_SOURCE = """import AppIntents

@main
struct IntentsExtension: AppIntentsExtension {}

struct Hello: AppIntent {
    static let title: LocalizedStringResource = "Hello"

    func perform() async throws -> some IntentResult { .result() }
}
"""

INTENTS_INFO = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>EXAppExtensionAttributes</key>
	<dict>
		<key>EXExtensionPointIdentifier</key>
		<string>com.apple.appintents-extension</string>
	</dict>
</dict>
</plist>
"""

HELPER_SOURCE = """import Foundation

let listener = NSXPCListener.service()
listener.resume()
"""

HELPER_INFO = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>XPCService</key>
	<dict>
		<key>ServiceType</key>
		<string>Application</string>
	</dict>
</dict>
</plist>
"""

PACKAGE_MANIFEST = """// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pack",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "Pack", type: .dynamic, targets: ["Pack"]),
        .library(name: "Static", targets: ["Static"]),
    ],
    targets: [.target(name: "Pack"), .target(name: "Static")]
)
"""


def products_project(package=False, extensionkit=False, xpc=False, combined=False, tool_path=None):
    """The adhoc app (App, with Kit and the loadable bundle Plugin in its resources) beside a
    second app App2, a static library Store, a command-line tool Tool and the aggregate target
    Apps building App and App2: each kind of product an archive can hold, archived by scheme
    (B-311). With `package`, App links a local package's dynamic product Pack and static
    product Static; with `extensionkit`, it embeds the App Intents extension Intents
    (ExtensionKit) in `Extensions/`; with `xpc`, the XPC service Helper in `XPCServices/`; with
    `combined`, the aggregates AppTool and AppStore build App with Tool or with Store, Tool
    installed in `tool_path` when given."""
    project = Project()
    settings = {**BASE_SETTINGS, "PRODUCT_NAME": '"$(TARGET_NAME)"', "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "1.0"}
    files = {"App/AppDelegate.swift": APP_SOURCE, "App2/AppDelegate.swift": APP_SOURCE.replace("import Kit\n", "").replace("Greeting.text", '"App2"'),
             "Kit/Kit.swift": KIT_SOURCE, "Store/Store.swift": STORE_SOURCE, "Tool/main.swift": 'print("tool")\n',
             "Plugin/Plugin.swift": PLUGIN_SOURCE}
    sources = {name: project.file(path, "sourcecode.swift") for name, path in
               (("App", "App/AppDelegate.swift"), ("App2", "App2/AppDelegate.swift"), ("Kit", "Kit/Kit.swift"),
                ("Store", "Store/Store.swift"), ("Tool", "Tool/main.swift"), ("Plugin", "Plugin/Plugin.swift"))}

    def phases(name, frameworks=(), resources=(), embeds=()):
        return [project.phase("PBXSourcesBuildPhase", [project.build_file(sources[name])]),
                project.phase("PBXFrameworksBuildPhase", [project.build_file(f) for f in frameworks]),
                project.phase("PBXResourcesBuildPhase", [project.build_file(r) for r in resources]), *embeds]

    kit, kit_product = project.target("Kit", "com.apple.product-type.framework", "Kit.framework", "wrapper.framework", phases("Kit"),
                                      {**settings, "PRODUCT_BUNDLE_IDENTIFIER": "org.nomac.signing.Kit", "GENERATE_INFOPLIST_FILE": "YES",
                                       "DEFINES_MODULE": "YES", "SKIP_INSTALL": "YES", "DYLIB_INSTALL_NAME_BASE": '"@rpath"',
                                       "INSTALL_PATH": '"$(LOCAL_LIBRARY_DIR)/Frameworks"', "VERSIONING_SYSTEM": '"apple-generic"',
                                       "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks")'})
    store, _ = project.target("Store", "com.apple.product-type.library.static", "libStore.a", "archive.ar", phases("Store"),
                              {**settings, "SKIP_INSTALL": "NO"})
    tool, _ = project.target("Tool", "com.apple.product-type.tool", "Tool", "compiled.mach-o.executable", phases("Tool"),
                             {**settings, "SKIP_INSTALL": "NO", **({"INSTALL_PATH": tool_path} if tool_path else {})})
    plugin, plugin_product = project.target("Plugin", "com.apple.product-type.bundle", "Plugin.bundle", "wrapper.cfbundle", phases("Plugin"),
                                            {**settings, "PRODUCT_BUNDLE_IDENTIFIER": "org.nomac.signing.Plugin", "GENERATE_INFOPLIST_FILE": "YES",
                                             "SKIP_INSTALL": "YES", "WRAPPER_EXTENSION": "bundle"})
    app_settings = {**settings, "GENERATE_INFOPLIST_FILE": "YES", "INFOPLIST_KEY_UILaunchStoryboardName": '""',
                    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
                    "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks")'}
    embeds = [project.copy_phase("Embed Frameworks", 10, [project.build_file(kit_product, ["CodeSignOnCopy", "RemoveHeadersOnCopy"])])]
    dependencies, package_products, linked = [(kit, "Kit"), (plugin, "Plugin")], [], [kit_product]
    extra_linked = []
    if package:
        files["Pack/Package.swift"] = PACKAGE_MANIFEST
        files["Pack/Sources/Pack/Pack.swift"] = 'public enum Pack { public static let name = "Pack" }\n'
        files["Pack/Sources/Static/Static.swift"] = 'public enum Static { public static let name = "Static" }\n'
        reference = project.local_package("Pack")
        for product in ("Pack", "Static"):
            dependency, build_file = project.package_product(reference, product)
            package_products.append(dependency)
            extra_linked.append(build_file)
        # Embed & Sign, as Xcode adds a dynamic product to the Embed Frameworks phase.
        embed_pack = project.product_build_file(package_products[0], ["CodeSignOnCopy"])
        project.objects = [o.replace("\t\t\tdstSubfolderSpec = 10;\n\t\t\tname = \"Embed Frameworks\";\n\t\t\tfiles = (\n",
                                     f"\t\t\tdstSubfolderSpec = 10;\n\t\t\tname = \"Embed Frameworks\";\n\t\t\tfiles = (\n\t\t\t\t{embed_pack},\n")
                           for o in project.objects]
    for wanted, name, product_type, extension, file_type, source_name, source, info, folder, subfolder in (
            (extensionkit, "Intents", "com.apple.product-type.extensionkit-extension", "appex", "wrapper.extensionkit-extension",
             "Intents.swift", INTENTS_SOURCE, INTENTS_INFO, "Embed ExtensionKit Extensions", "$(EXTENSIONS_FOLDER_PATH)"),
            (xpc, "Helper", "com.apple.product-type.xpc-service", "xpc", "wrapper.xpc-service",
             "main.swift", HELPER_SOURCE, HELPER_INFO, "Embed XPC Services", "$(CONTENTS_FOLDER_PATH)/XPCServices")):
        if not wanted:
            continue
        files[f"{name}/{source_name}"] = source
        files[f"{name}/Info.plist"] = info
        sources[name] = project.file(f"{name}/{source_name}", "sourcecode.swift")
        project.file(f"{name}/Info.plist", "text.plist.xml")
        target, product = project.target(name, product_type, f"{name}.{extension}", file_type, phases(name),
                                         {**settings, "PRODUCT_BUNDLE_IDENTIFIER": f"org.nomac.signing.{name}", "GENERATE_INFOPLIST_FILE": "YES",
                                          "INFOPLIST_FILE": f"{name}/Info.plist", "SKIP_INSTALL": "YES",
                                          "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks")'})
        dependencies.append((target, name))
        embeds.append(project.copy_phase(folder, 16, [project.build_file(product, ["RemoveHeadersOnCopy"])], subfolder))
    app_phases = phases("App", linked, [plugin_product], embeds)
    if extra_linked:
        frameworks_phase = app_phases[1]
        project.objects = [o.replace(f"\t\t{frameworks_phase} = {{\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n",
                                     f"\t\t{frameworks_phase} = {{\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n"
                                     + "".join(f"\t\t\t\t{f},\n" for f in extra_linked)) for o in project.objects]
    app, _ = project.target("App", "com.apple.product-type.application", "App.app", "wrapper.application", app_phases,
                            {**app_settings, "PRODUCT_BUNDLE_IDENTIFIER": "org.nomac.signing"}, dependencies, package_products)
    app2, _ = project.target("App2", "com.apple.product-type.application", "App2.app", "wrapper.application", phases("App2"),
                             {**app_settings, "PRODUCT_BUNDLE_IDENTIFIER": "org.nomac.signing.two"})
    project.aggregate("Apps", [(app, "App"), (app2, "App2")])
    if combined:
        project.aggregate("AppTool", [(app, "App"), (tool, "Tool")])
        project.aggregate("AppStore", [(app, "App"), (store, "Store")])
    files["Signing.xcodeproj/project.pbxproj"] = project.text()
    return files


APP_ALONE_SOURCE = APP_SOURCE.replace("import Kit\n", "").replace("Greeting.text", '"App"')
APP_SPAN_SOURCE = APP_SOURCE.replace("        return true\n", SPAN_USE + "        return true\n")

KIT_SPAN_SOURCE = KIT_SOURCE.replace("}\n", f"""
    public static func count() {{
{SPAN_USE}    }}
}}
""")


def app_project(frameworks, extensions, native=False, app_source=None, kit_source=KIT_SOURCE, deployment="18.0",
                watch=False, watch_deployment="11.0", clip=False, clip_entitlements=None, clip_settings=None,
                clip_script_signed=False, app_name=None, odr=0, app_entitlements=None, framework_settings=None,
                codeless=(), app_script=None):
    """An app with resources of several kinds, embedding `frameworks` and the share extensions
    `extensions` in list order; the app and every extension link the first framework, if any. With
    `native`, the app also compiles the C, Objective-C and C++ sources of NATIVE_SOURCES;
    `app_source`, `kit_source` and `deployment` replace the app's and Kit's code and the
    deployment target. With `watch`, the app embeds a single-target SwiftUI watchOS app in
    `Watch/` (Xcode 16's template, `watch_deployment` its deployment target); with `clip`, an
    App Clip in `AppClips/`, signed with `clip_entitlements` when given, `clip_settings` added to
    its build settings. With `clip_script_signed`, Xcode does not sign the clip
    (`CODE_SIGNING_ALLOWED` NO) and a script phase signs it ad hoc through `$(CODESIGN)` with
    the arguments Xcode uses for the app, without entitlements (CLIP_SIGN_SCRIPT), and is not
    stripped (stripping runs after the script phases and would break that signature).
    `app_name` names the app's product other than its target and scheme. With `odr` (a count),
    that many resources of the app are on-demand resources, tagged `level1`, `level2` and
    `level3` (`ENABLE_ON_DEMAND_RESOURCES`). With `app_entitlements`, the app is signed with them.
    `framework_settings` are added to every framework target's settings (`MACH_O_TYPE` `staticlib`
    for static frameworks); the frameworks named in `codeless` have no sources, so no binary.
    `app_script` is the app's last build phase, a script run outside the sandbox."""
    project = Project()
    base_settings = {**BASE_SETTINGS, "IPHONEOS_DEPLOYMENT_TARGET": deployment}
    files = {
        "App/AppDelegate.swift": app_source or (NATIVE_APP_SOURCE if native else APP_SOURCE),
        "App/data.json": '{"name": "nomac"}\n',
        "App/en.lproj/Localizable.strings": '"greeting" = "Hello";\n',
        "App/fr.lproj/Localizable.strings": '"greeting" = "Bonjour";\n',
        "App/Content/a.txt": "a\n",
        "App/Content/Sub/b.txt": "b\n",
    }
    app_source = project.file("App/AppDelegate.swift", "sourcecode.swift")
    app_sources = [project.build_file(app_source)]
    app_settings = {"PRODUCT_NAME": app_name} if app_name else {}
    if app_entitlements:
        files["App/App.entitlements"] = app_entitlements
        app_settings["CODE_SIGN_ENTITLEMENTS"] = "App/App.entitlements"
    if native:
        for path, (text, file_type) in NATIVE_SOURCES.items():
            files[path] = text
            reference = project.file(path, file_type)
            if file_type != "sourcecode.c.h":
                app_sources.append(project.build_file(reference))
        app_settings["SWIFT_OBJC_BRIDGING_HEADER"] = '"App/Bridge.h"'
    data = project.file("App/data.json", "text.json")
    content = project.file("App/Content", "folder")
    strings = project.variant_group("App", "Localizable.strings", ["en", "fr"], "text.plist.strings")

    framework_targets = []
    for name in frameworks:
        sources = []
        if name not in codeless:
            files[f"{name}/{name}.swift"] = kit_source if name == "Kit" else f"public enum {name} {{ public static let text = \"{name}\" }}\n"
            sources = [project.build_file(project.file(f"{name}/{name}.swift", "sourcecode.swift"))]
        framework_targets.append(project.target(
            name, "com.apple.product-type.framework", f"{name}.framework", "wrapper.framework",
            [project.phase("PBXSourcesBuildPhase", sources),
             project.phase("PBXFrameworksBuildPhase", []),
             project.phase("PBXResourcesBuildPhase", [])],
            {**base_settings, "PRODUCT_NAME": '"$(TARGET_NAME)"', "PRODUCT_BUNDLE_IDENTIFIER": f"org.nomac.signing.{name}",
             "GENERATE_INFOPLIST_FILE": "YES", "DEFINES_MODULE": "YES", "SKIP_INSTALL": "YES",
             "APPLICATION_EXTENSION_API_ONLY": "YES", "DYLIB_INSTALL_NAME_BASE": '"@rpath"',
             "INSTALL_PATH": '"$(LOCAL_LIBRARY_DIR)/Frameworks"',
             "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks")',
             "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "1.0", "VERSIONING_SYSTEM": '"apple-generic"',
             **(framework_settings or {})}))
    kit_target, kit_product = framework_targets[0] if framework_targets else (None, None)
    kit_links = [project.build_file(kit_product)] if kit_product else []

    extension_targets = []
    for name in extensions:
        files[f"{name}/ShareViewController.swift"] = SHARE_SOURCE
        files[f"{name}/Info.plist"] = SHARE_INFO
        source = project.file(f"{name}/ShareViewController.swift", "sourcecode.swift")
        project.file(f"{name}/Info.plist", "text.plist.xml")
        extension_targets.append(project.target(
            name, "com.apple.product-type.app-extension", f"{name}.appex", "wrapper.app-extension",
            [project.phase("PBXSourcesBuildPhase", [project.build_file(source)]),
             project.phase("PBXFrameworksBuildPhase", kit_links),
             project.phase("PBXResourcesBuildPhase", [])],
            {**base_settings, "PRODUCT_NAME": '"$(TARGET_NAME)"', "PRODUCT_BUNDLE_IDENTIFIER": f"org.nomac.signing.{name}",
             "GENERATE_INFOPLIST_FILE": "YES", "INFOPLIST_FILE": f"{name}/Info.plist", "SKIP_INSTALL": "YES",
             "INFOPLIST_KEY_CFBundleDisplayName": name,
             "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks")',
             "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "1.0"},
            [(kit_target, "Kit")]))

    dependencies = [(target, name) for (target, _), name in zip(framework_targets + extension_targets, frameworks + extensions)]
    embeds = [project.copy_phase("Embed Frameworks", 10, [project.build_file(product, ["CodeSignOnCopy", "RemoveHeadersOnCopy"])
                                                          for _, product in framework_targets]),
              project.copy_phase("Embed Foundation Extensions", 13, [project.build_file(product, ["RemoveHeadersOnCopy"])
                                                                     for _, product in extension_targets])]
    if watch:
        files["Watch/WatchApp.swift"] = WATCH_SOURCE
        files["Watch/Info.plist"] = WATCH_INFO
        source = project.file("Watch/WatchApp.swift", "sourcecode.swift")
        project.file("Watch/Info.plist", "text.plist.xml")
        watch_target, watch_product = project.target(
            "Watch", "com.apple.product-type.application", "Watch.app", "wrapper.application",
            [project.phase("PBXSourcesBuildPhase", [project.build_file(source)]),
             project.phase("PBXFrameworksBuildPhase", []),
             project.phase("PBXResourcesBuildPhase", [])],
            {"SDKROOT": "watchos", "WATCHOS_DEPLOYMENT_TARGET": watch_deployment, "TARGETED_DEVICE_FAMILY": "4",
             "SWIFT_VERSION": "5.0", "CODE_SIGN_STYLE": "Manual", "ALWAYS_SEARCH_USER_PATHS": "NO",
             "PRODUCT_NAME": '"$(TARGET_NAME)"', "PRODUCT_BUNDLE_IDENTIFIER": "org.nomac.signing.watchkitapp",
             "GENERATE_INFOPLIST_FILE": "YES", "INFOPLIST_FILE": "Watch/Info.plist", "SKIP_INSTALL": "YES",
             "INFOPLIST_KEY_CFBundleDisplayName": "Watch", "INFOPLIST_KEY_WKCompanionAppBundleIdentifier": "org.nomac.signing",
             "INFOPLIST_KEY_UISupportedInterfaceOrientations": '"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown"',
             "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks")',
             "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "1.0"})
        dependencies.append((watch_target, "Watch"))
        embeds.append(project.copy_phase("Embed Watch Content", 16, [project.build_file(watch_product, ["RemoveHeadersOnCopy"])],
                                         "$(CONTENTS_FOLDER_PATH)/Watch"))
    if clip:
        files["Clip/ClipDelegate.swift"] = CLIP_SOURCE
        files["Clip/Info.plist"] = CLIP_INFO
        source = project.file("Clip/ClipDelegate.swift", "sourcecode.swift")
        project.file("Clip/Info.plist", "text.plist.xml")
        clip_settings = dict(clip_settings or {})
        if clip_entitlements:
            files["Clip/Clip.entitlements"] = clip_entitlements
            project.file("Clip/Clip.entitlements", "text.plist.entitlements")
            clip_settings["CODE_SIGN_ENTITLEMENTS"] = "Clip/Clip.entitlements"
        clip_phases = [project.phase("PBXSourcesBuildPhase", [project.build_file(source)]),
                       project.phase("PBXFrameworksBuildPhase", []),
                       project.phase("PBXResourcesBuildPhase", [])]
        if clip_script_signed:
            clip_phases.append(project.script_phase("Sign Ad Hoc", CLIP_SIGN_SCRIPT))
            clip_settings.update({"CODE_SIGNING_ALLOWED": "NO", "ENABLE_USER_SCRIPT_SANDBOXING": "NO", "STRIP_INSTALLED_PRODUCT": "NO"})
        clip_target, clip_product = project.target(
            "Clip", "com.apple.product-type.application.on-demand-install-capable", "Clip.app", "wrapper.application",
            clip_phases,
            {**base_settings, "PRODUCT_NAME": '"$(TARGET_NAME)"', "PRODUCT_BUNDLE_IDENTIFIER": "org.nomac.signing.Clip",
             "GENERATE_INFOPLIST_FILE": "YES", "INFOPLIST_FILE": "Clip/Info.plist", "SKIP_INSTALL": "YES",
             "INFOPLIST_KEY_UILaunchStoryboardName": '""', "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
             "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks")',
             "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "1.0", **clip_settings})
        dependencies.append((clip_target, "Clip"))
        embeds.append(project.copy_phase("Embed App Clips", 16, [project.build_file(clip_product, ["RemoveHeadersOnCopy"])],
                                         "$(CONTENTS_FOLDER_PATH)/AppClips"))

    tagged = []
    if odr:
        for tag in ("level1", "level2", "level3")[:odr]:
            files[f"App/{tag}.txt"] = f"{tag}\n"
            tagged.append(project.build_file(project.file(f"App/{tag}.txt", "text"), asset_tags=[tag]))
        app_settings["ENABLE_ON_DEMAND_RESOURCES"] = "YES"
    project.target(
        "App", "com.apple.product-type.application", "App.app", "wrapper.application",
        [project.phase("PBXSourcesBuildPhase", app_sources),
         project.phase("PBXFrameworksBuildPhase", kit_links),
         project.phase("PBXResourcesBuildPhase", [project.build_file(data), project.build_file(strings),
                                                  project.build_file(content), *tagged]),
         *embeds, *([project.script_phase("Script", app_script)] if app_script else [])],
        {**base_settings, "PRODUCT_NAME": '"$(TARGET_NAME)"', "PRODUCT_BUNDLE_IDENTIFIER": "org.nomac.signing",
         **({"ENABLE_USER_SCRIPT_SANDBOXING": "NO"} if app_script else {}),
         "GENERATE_INFOPLIST_FILE": "YES",
         "INFOPLIST_KEY_UILaunchStoryboardName": '""', "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
         "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks")',
         "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "1.0", **app_settings},
        dependencies)

    files["Signing.xcodeproj/project.pbxproj"] = project.text()
    return files


# Swift Build runs `$(CODESIGN)` for every CodeSign task and for the Swift libraries it embeds
# (CodeSign.swift, EmbedSwiftStdLibTaskAction.swift), so a wrapper there sees each signing step:
# it keeps the arguments, the entitlements file and the product before and after codesign.
CODESIGN_WRAPPER = """#!/bin/sh
dir=$(/usr/bin/mktemp -d "{capture}/sign.XXXXXX")
/usr/bin/perl -MTime::HiRes -e 'printf "%.6f\\n", Time::HiRes::time()' > "$dir/time"
printf '%s\\n' "$@" > "$dir/arguments"
previous=""
for argument; do
    if [ "$previous" = "--entitlements" ]; then /bin/cp "$argument" "$dir/entitlements"; fi
    previous="$argument"
done
product="$argument"
/usr/bin/ditto "$product" "$dir/before/$(/usr/bin/basename "$product")"
/usr/bin/codesign "$@" > "$dir/stdout"
status=$?
/bin/cat "$dir/stdout"
/usr/bin/ditto "$product" "$dir/after/$(/usr/bin/basename "$product")"
echo "$status" > "$dir/status"
exit "$status"
"""


def codesign_wrapper(output):
    """Writes the wrapper for captures under `output/captures`; returns the CODESIGN override."""
    capture = output / "captures"
    capture.mkdir(parents=True, exist_ok=True)
    wrapper = output / "codesign-wrapper.sh"
    wrapper.write_text(CODESIGN_WRAPPER.format(capture=capture))
    wrapper.chmod(0o755)
    return f"CODESIGN={wrapper}"


def observe_adhoc(directory, output, umask=None, methods=("debugging", "release-testing", "enterprise", "app-store-connect"), settings=(),
                  scheme="App"):
    common = ["xcodebuild", "-project", "Signing.xcodeproj", "-scheme", scheme, "-destination", "generic/platform=iOS", "-jobs", "4"]
    signed = run(output, "archive-adhoc", [*common, "archive", "-archivePath", str(output / "adhoc.xcarchive"),
                                           "-derivedDataPath", str(output / "dd"), *ADHOC, *settings, codesign_wrapper(output)],
                 directory, umask)
    # The build's products stay for `compare-archive`; xcodebuild moved the installed ones into
    # the archive.
    built = output / f"dd/Build/Intermediates.noindex/ArchiveIntermediates/{scheme}/BuildProductsPath"
    if built.is_dir():
        shutil.move(str(built), str(output / "BuildProductsPath"))
    shutil.rmtree(output / "dd", ignore_errors=True)
    if signed == 0:
        for method in methods:
            export(output, "adhoc.xcarchive", method, umask=umask)
    return signed


def export(output, archive, method, team="NOMAC00000", label=None, extra="", umask=None):
    """`xcodebuild -exportArchive` with ad-hoc signing. Without a team in the archive the export
    stops ("No Team Found in Archive"); any team identifier lets it continue. `extra` adds
    options (property list keys and values) under the name `export-<label>`."""
    label = label or method
    options = output / f"export-{label}.plist"
    team_entry = f"\t<key>teamID</key>\n\t<string>{team}</string>\n" if team else ""
    options.write_text(EXPORT_OPTIONS.format(method=method, team=team_entry, extra=extra))
    run(output, f"export-{label}", ["xcodebuild", "-exportArchive", "-archivePath", str(output / archive),
                                    "-exportPath", str(output / f"export-{label}"), "-exportOptionsPlist", str(options)],
        output, umask)


MANIFEST = """\t<key>manifest</key>
\t<dict>
\t\t<key>appURL</key>
\t\t<string>https://example.com/nomac/App.ipa</string>
\t\t<key>displayImageURL</key>
\t\t<string>https://example.com/nomac/display.png</string>
\t\t<key>fullSizeImageURL</key>
\t\t<string>https://example.com/nomac/full-size.png</string>
\t</dict>
"""


def observe_manifest(directory, output):
    """The adhoc app exported with an OTA install manifest (`manifest` export option)."""
    if observe_adhoc(directory, output, methods=()) == 0:
        for method in ("release-testing", "enterprise", "debugging"):
            export(output, "adhoc.xcarchive", method, label=f"{method}-manifest", extra=MANIFEST)


def observe_odr(directory, output):
    """An app with on-demand resources, exported for every method, with a manifest, and with
    its asset packs hosted (`onDemandResourcesAssetPacksBaseURL`) or embedded."""
    if observe_adhoc(directory, output) == 0:
        export(output, "adhoc.xcarchive", "release-testing", label="release-testing-manifest", extra=MANIFEST)
        export(output, "adhoc.xcarchive", "release-testing", label="release-testing-hosted",
               extra="\t<key>onDemandResourcesAssetPacksBaseURL</key>\n\t<string>https://example.com/nomac/packs</string>\n")
        export(output, "adhoc.xcarchive", "release-testing", label="release-testing-embedded",
               extra="\t<key>embedOnDemandResourcesAssetPacksInBundle</key>\n\t<true/>\n")


def observe_odr_shapes(directory, output):
    """The on-demand resources shapes B-312 lists, from the `odr` app's archive: exports with a
    base URL ending in `/`, with a base URL and `embedOnDemandResourcesAssetPacksInBundle` true,
    and app-store-connect with a manifest; and hosted and app-store-connect exports of archive
    copies whose first asset pack has a file of mode 0600, a symbolic link, or an XML
    Info.plist (the packs are signed again by the export)."""
    if observe_adhoc(directory, output, methods=()) != 0:
        return
    base = "\t<key>onDemandResourcesAssetPacksBaseURL</key>\n\t<string>https://example.com/nomac/packs{}</string>\n"
    export(output, "adhoc.xcarchive", "release-testing", label="release-testing-base-slash", extra=base.format("/"))
    export(output, "adhoc.xcarchive", "release-testing", label="release-testing-hosted-embedded",
           extra=base.format("") + "\t<key>embedOnDemandResourcesAssetPacksInBundle</key>\n\t<true/>\n")
    export(output, "adhoc.xcarchive", "app-store-connect", label="app-store-connect-manifest", extra=MANIFEST)
    for shape in ("mode", "link", "xml"):
        archive = f"{shape}.xcarchive"
        shutil.copytree(output / "adhoc.xcarchive", output / archive, symlinks=True)
        pack = sorted((output / archive / "Products/OnDemandResources").iterdir())[0]
        if shape == "mode":
            (pack / "private.txt").write_text("private\n")
            (pack / "private.txt").chmod(0o600)
        elif shape == "link":
            os.symlink(next(path.name for path in pack.iterdir() if path.suffix == ".txt"), pack / "link.txt")
        else:
            subprocess.run(["plutil", "-convert", "xml1", str(pack / "Info.plist")], check=True)
        export(output, archive, "release-testing", label=f"release-testing-hosted-{shape}", extra=base.format(""))
        export(output, archive, "app-store-connect", label=f"app-store-connect-{shape}")


def observe_refusals(directory, output):
    """Exports xcodebuild refuses: without a team, and of an app signed again with entitlements."""
    observe_adhoc(directory, output, methods=())
    if not (output / "adhoc.xcarchive").exists():
        return
    export(output, "adhoc.xcarchive", "debugging", team=None, label="debugging-no-team")
    shutil.copytree(output / "adhoc.xcarchive", output / "entitlements.xcarchive", symlinks=True)
    entitlements = output / "app.entitlements"
    entitlements.write_text(ENTITLEMENTS)
    run(output, "resign-entitlements", ["codesign", "-f", "-s", "-", "--entitlements", str(entitlements),
                                        str(output / "entitlements.xcarchive/Products/Applications/App.app")], output)
    export(output, "entitlements.xcarchive", "debugging", label="debugging-entitlements")


ENTITLEMENTS = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>get-task-allow</key>
	<true/>
</dict>
</plist>
"""


def observe_symbols(directory, output):
    """The adhoc observation, plus an app-store-connect export without symbols."""
    observe_adhoc(directory, output)
    if (output / "adhoc.xcarchive").exists():
        export(output, "adhoc.xcarchive", "app-store-connect", label="app-store-connect-nosymbols",
               extra="\t<key>uploadSymbols</key>\n\t<false/>\n")


EXPORT_OPTIONS = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>{method}</string>
	<key>signingCertificate</key>
	<string>-</string>
	<key>signingStyle</key>
	<string>manual</string>
{team}{extra}</dict>
</plist>
"""


# dSYMs a script puts where CocoaPods' `[CP] Copy XCFrameworks` puts a prebuilt pod's
# (`XCFrameworkIntermediates/<pod>/` and `<pod>/dSYMs/`), deeper, through links to a dSYM and to
# a folder, inside a bundle and inside a dSYM, outside the products folder, two copies named as a
# top-level one (with marker files: one listed before it, one after), a dSYM of a binary no
# product holds, an empty one and a file named `.dSYM`.
NESTED_DSYMS_SCRIPT = r"""set -e
B="$BUILT_PRODUCTS_DIR"
X="$B/XCFrameworkIntermediates"
mkdir -p "$X/Pod" "$X/Pod2/dSYMs" "$B/a/b/c" "$X/Lone/dSYMs" "$X/Empty/dSYMs/Empty.framework.dSYM" "$B/Wrapper.bundle" \
    "$X/Dup/dSYMs" "$B/link" "$TARGET_TEMP_DIR/Outside"
for destination in "$X/Pod/Pod.framework.dSYM" "$X/Pod2/dSYMs/Pod2.framework.dSYM" "$B/a/b/c/Deep.framework.dSYM" \
    "$B/Wrapper.bundle/Inner.framework.dSYM" "$X/Dup/dSYMs/Kit.framework.dSYM" "$B/a/Kit.framework.dSYM" \
    "$X/Pod/Pod.framework.dSYM/Contents/Nested.framework.dSYM" "$TARGET_TEMP_DIR/Outside/Outside.framework.dSYM"; do
  /usr/bin/ditto "$B/Kit.framework.dSYM" "$destination"
done
touch "$X/Dup/dSYMs/Kit.framework.dSYM/Contents/Resources/marker-xcframeworks" "$B/a/Kit.framework.dSYM/Contents/Resources/marker-a"
ln -sfn ../XCFrameworkIntermediates/Pod/Pod.framework.dSYM "$B/link/Linked.framework.dSYM"
ln -sfn XCFrameworkIntermediates/Pod2 "$B/linkdir"
touch "$X/Pod/File.dSYM"
printf 'int lone(void) { return 1; }\n' > "$TARGET_TEMP_DIR/lone.c"
xcrun clang -g -target arm64-apple-ios18.0 -isysroot "$SDKROOT" -dynamiclib -o "$TARGET_TEMP_DIR/Lone" "$TARGET_TEMP_DIR/lone.c"
xcrun dsymutil "$TARGET_TEMP_DIR/Lone" -o "$X/Lone/dSYMs/Lone.framework.dSYM"
"""

EXPERIMENTS = {
    "adhoc": (lambda: app_project(["Kit"], ["Share"]), observe_adhoc),
    "nested": (lambda: app_project(["Kit", "Alpha", "Zed"], ["Share", "Action"]), observe_adhoc),
    "alone": (lambda: app_project([], [], app_source=APP_ALONE_SOURCE), observe_adhoc),
    "entitlements-empty": (lambda: app_project([], [], app_source=APP_ALONE_SOURCE, app_entitlements=EMPTY_ENTITLEMENTS), observe_adhoc),
    "names": (lambda: {**app_project([], [], app_source=APP_ALONE_SOURCE), **{f"App/Content/{name}": name + "\n" for name in UNICODE_NAMES}},
              lambda directory, output: observe_adhoc(directory, output, methods=("debugging", "app-store-connect"))),
    "framework-static": (lambda: app_project(["Kit"], [], framework_settings={"MACH_O_TYPE": "staticlib"}),
                         lambda directory, output: observe_adhoc(directory, output, methods=("debugging",))),
    "framework-codeless": (lambda: app_project(["Kit", "Assets"], [], codeless=("Assets",)),
                           lambda directory, output: observe_adhoc(directory, output, methods=("debugging",))),
    "entitlements-groups": (lambda: app_project([], [], app_source=APP_ALONE_SOURCE, app_entitlements=GROUPS_ENTITLEMENTS),
                            lambda directory, output: observe_adhoc(directory, output, methods=("debugging",))),
    "entitlements-push": (lambda: app_project([], [], app_source=APP_ALONE_SOURCE, app_entitlements=PUSH_ENTITLEMENTS),
                          lambda directory, output: observe_adhoc(directory, output, methods=("debugging",))),
    "entitlements-keychain": (lambda: app_project([], [], app_source=APP_ALONE_SOURCE, app_entitlements=KEYCHAIN_ENTITLEMENTS),
                              lambda directory, output: observe_adhoc(directory, output, methods=("debugging",))),
    "symbols": (lambda: app_project(["Kit"], ["Share"], native=True), observe_symbols),
    "span": (lambda: app_project(["Kit"], ["Share"], app_source=APP_SPAN_SOURCE), observe_adhoc),
    "span-framework": (lambda: app_project(["Kit"], ["Share"], app_source=APP_SPAN_SOURCE, kit_source=KIT_SPAN_SOURCE), observe_adhoc),
    "span-kit": (lambda: app_project(["Kit"], ["Share"], kit_source=KIT_SPAN_SOURCE), observe_adhoc),
    "span-26": (lambda: app_project(["Kit"], ["Share"], app_source=APP_SPAN_SOURCE, deployment="26.0"), observe_adhoc),
    "span-nested": (lambda: app_project(["Kit", "Alpha", "Zed"], ["Share", "Action"], app_source=APP_SPAN_SOURCE), observe_adhoc),
    "span-order": (lambda: app_project(["Kit", "zeta"], ["Share"], app_source=APP_SPAN_SOURCE), observe_adhoc),
    "refusals": (lambda: app_project(["Kit"], ["Share"]), observe_refusals),
    "umask": (lambda: app_project(["Kit"], ["Share"]), lambda directory, output: observe_adhoc(directory, output, 0o002, ("debugging", "app-store-connect"))),
    "archive-names": (lambda: app_project(["Kit"], ["Share"], app_name="Shop"), lambda directory, output: observe_adhoc(directory, output, methods=())),
    "archive-nested-dsyms": (lambda: app_project(["Kit"], [], app_script=NESTED_DSYMS_SCRIPT),
                             lambda directory, output: observe_adhoc(directory, output, methods=())),
    "archive-nodsym": (lambda: app_project(["Kit"], ["Share"]),
                       lambda directory, output: observe_adhoc(directory, output, methods=(), settings=("DEBUG_INFORMATION_FORMAT=dwarf",))),
    "archive-products-app": (products_project, lambda directory, output: observe_adhoc(directory, output, methods=())),
    "archive-products-apps": (products_project, lambda directory, output: observe_adhoc(directory, output, methods=(), scheme="Apps")),
    "archive-products-framework": (products_project,
                                   lambda directory, output: observe_adhoc(directory, output, methods=(), scheme="Kit", settings=("SKIP_INSTALL=NO",))),
    "archive-products-library": (products_project, lambda directory, output: observe_adhoc(directory, output, methods=(), scheme="Store")),
    "archive-products-tool": (products_project, lambda directory, output: observe_adhoc(directory, output, methods=(), scheme="Tool")),
    "archive-products-installs-framework": (products_project, lambda directory, output: observe_adhoc(
        directory, output, methods=(), settings=("SKIP_INSTALL=NO",))),
    "archive-products-nothing": (products_project, lambda directory, output: observe_adhoc(directory, output, methods=(), scheme="Kit")),
    "archive-products-app-tool": (lambda: products_project(combined=True),
                                  lambda directory, output: observe_adhoc(directory, output, methods=(), scheme="AppTool")),
    "archive-products-app-library": (lambda: products_project(combined=True),
                                     lambda directory, output: observe_adhoc(directory, output, methods=(), scheme="AppStore")),
    "archive-products-app-tool-opt": (lambda: products_project(combined=True, tool_path="/opt/nomac"),
                                      lambda directory, output: observe_adhoc(directory, output, methods=(), scheme="AppTool")),
    # SwiftPM's own manifest sandbox cannot nest in OFFLINE's; the outer one still keeps the
    # network out.
    "archive-package": (lambda: products_project(package=True),
                        lambda directory, output: observe_adhoc(directory, output, methods=("debugging", "app-store-connect"),
                                                                settings=("-IDEPackageSupportDisableManifestSandbox=YES",))),
    "archive-extensionkit": (lambda: products_project(extensionkit=True),
                             lambda directory, output: observe_adhoc(directory, output, methods=("debugging", "app-store-connect"))),
    "archive-xpc": (lambda: products_project(xpc=True), lambda directory, output: observe_adhoc(directory, output, methods=("debugging",))),
    "manifest": (lambda: app_project(["Kit"], ["Share"]), observe_manifest),
    "odr": (lambda: app_project(["Kit"], [], odr=2), observe_odr),
    "odr-shapes": (lambda: app_project(["Kit"], [], odr=2), observe_odr_shapes),
    "odr-three": (lambda: app_project(["Kit"], [], odr=3), lambda directory, output: observe_adhoc(directory, output, methods=("release-testing",))),
    "watch": (lambda: app_project(["Kit"], [], watch=True), observe_adhoc),
    "appclip": (lambda: app_project(["Kit"], [], clip=True), observe_adhoc),
    "watch-appclip": (lambda: app_project(["Kit"], ["Share"], watch=True, clip=True), observe_adhoc),
    "appclip-entitlements": (lambda: app_project(["Kit"], [], clip=True, clip_entitlements=CLIP_ENTITLEMENTS), observe_adhoc),
    "appclip-unsigned": (lambda: app_project(["Kit"], [], clip=True, clip_settings={"CODE_SIGNING_ALLOWED": "NO"}), observe_adhoc),
    "appclip-no-entitlements": (lambda: app_project(["Kit"], [], clip=True, clip_settings={"ENTITLEMENTS_ALLOWED": "NO"}), observe_adhoc),
    "appclip-script": (lambda: app_project(["Kit"], [], clip=True, clip_script_signed=True), observe_adhoc),
    "watch-appclip-script": (lambda: app_project(["Kit"], ["Share"], watch=True, clip=True, clip_script_signed=True), observe_adhoc),
}


# With an Apple account in Xcode, app-store-connect exports ask Apple's developer services about
# the team (observed: viewDeveloper.action); xcodebuild runs without network access instead,
# which changes nothing in what it writes.
OFFLINE = ["sandbox-exec", "-p", '(version 1)(allow default)(deny network-outbound (remote ip))'
           '(deny network-outbound (remote unix-socket (path-literal "/private/var/run/mDNSResponder")))']


def run(output, label, argv, directory, umask=None):
    command = OFFLINE + argv if argv[0] == "xcodebuild" else argv
    completed = subprocess.run(command, cwd=directory, capture_output=True, text=True, preexec_fn=with_umask(umask))
    (output / f"{label}.log").write_text(completed.stdout + completed.stderr)
    record = {"argv": argv, "exitStatus": completed.returncode, **({"umask": umask} if umask is not None else {})}
    (output / f"{label}.json").write_text(json.dumps(record, indent=2) + "\n")
    print(f"{output.name}: {label} exit {completed.returncode}")
    return completed.returncode


def with_umask(umask):
    """A `preexec_fn` that sets the file mode creation mask, or None to keep the script's."""
    return None if umask is None else (lambda: os.umask(umask))


def recorded_umask(record):
    """The umask an experiment step ran with (`run`), or None."""
    return json.loads(record.read_text()).get("umask") if record.exists() else None


def compare(output, nomac):
    """Replays the captures under `output/*/captures`; returns the number of differing steps."""
    failures = 0
    for capture in sorted(output.glob("*/captures/sign.*"), key=lambda c: float((c / "time").read_text())):
        arguments = (capture / "arguments").read_text().splitlines()
        product = arguments[-1]
        with tempfile.TemporaryDirectory(prefix="nomac-pack-") as work:
            copy = Path(work) / Path(product).name
            subprocess.run(["ditto", str(capture / "before" / copy.name), str(copy)], check=True)
            replayed = [str(copy) if a == product else a for a in arguments]
            if "--entitlements" in replayed:
                replayed[replayed.index("--entitlements") + 1] = str(capture / "entitlements")
            umask = recorded_umask(capture.parent.parent / "archive-adhoc.json")
            completed = subprocess.run([nomac, "codesign", *replayed], capture_output=True, text=True, preexec_fn=with_umask(umask))
            differences = tree_differences(capture / "after" / copy.name, copy)
            if (capture / "stdout").exists() and completed.stdout != (capture / "stdout").read_text():
                differences.append(f"standard output {completed.stdout!r} != {(capture / 'stdout').read_text()!r}")
            if completed.returncode != int((capture / "status").read_text()):
                differences.insert(0, f"exit status {completed.returncode}: {completed.stderr.strip()}")
        label = f"{capture.parent.parent.name}/{capture.name} {Path(product).name} {' '.join(arguments[:-1])}"
        print(f"{'identical' if not differences else 'DIFFERENT'}: {label}")
        for difference in differences:
            print(f"    {difference}")
        failures += bool(differences)
    return failures


def synthetic(directory):
    for case in sorted(path for path in directory.iterdir() if (path / "input.plist").exists()):
        converted = case / "plutil.plist"
        subprocess.run(["plutil", "-convert", "xml1", "-o", str(converted), str(case / "input.plist")], check=True)
        print(f'{case.name}: plutil -convert xml1\n    "": "{hashlib.sha256(converted.read_bytes()).hexdigest()}",')
    for case in sorted(path for path in directory.iterdir() if (path / "arguments").exists()):
        arguments = (case / "arguments").read_text().splitlines()
        product = case / "output" / arguments[-1]
        shutil.rmtree(case / "output", ignore_errors=True)
        (case / "output").mkdir()
        subprocess.run(["ditto", str(case / "input" / arguments[-1]), str(product)], check=True)
        if "--entitlements" in arguments:
            arguments[arguments.index("--entitlements") + 1] = str(case / "entitlements.plist")
        keychain = "--keychain" in arguments
        with case_keychain(case if keychain else None) as path:
            if keychain:
                arguments[arguments.index("--keychain") + 1] = path
            completed = subprocess.run(["codesign", *arguments[:-1], str(product)], capture_output=True, text=True)
        print(f"{case.name}: exit {completed.returncode} {completed.stderr.strip()!r}")
        if keychain and completed.returncode == 0:
            # A detached signature keeps its CMS in _CodeSignature/CodeSignature.
            detached = product / "_CodeSignature/CodeSignature"
            if product.is_dir() and detached.exists() and detached.stat().st_size:
                signed = detached
            else:
                signed = product if product.is_file() else product / plistlib.loads((product / "Info.plist").read_bytes())["CFBundleExecutable"]
            print(f"    signing time: {signing_time(signed.read_bytes())}")
        paths = [product] if product.is_file() else sorted(product.rglob("*"))
        for path in paths:
            name = "" if path == product else str(path.relative_to(product))
            if path.is_symlink():
                print(f'    "{name}": "-> {os.readlink(path)}",')
            elif path.is_file():
                print(f'    "{name}": "{hashlib.sha256(path.read_bytes()).hexdigest()}",')


NOMAC_EXPORT_METHODS = ("debugging", "release-testing", "enterprise", "app-store-connect")


def synthetic_export(directory):
    for name in ("export", "alone", "empty-entitlements", "symbols", "clip", "watch", "appstore", "nodsyms", "manifest", "manifest-app-url", "odr", "odr-appstore", "odr-hosted", "options"):
        case = directory / name
        if not case.exists():
            continue
        shutil.rmtree(case / "out", ignore_errors=True)
        completed = subprocess.run([*OFFLINE, "xcodebuild", "-exportArchive", "-archivePath", str(case / "App.xcarchive"), "-exportPath",
                                    str(case / "out"), "-exportOptionsPlist", str(case / "options.plist")], capture_output=True, text=True)
        print(f"{name}: exit {completed.returncode}")
        for path in sorted(p for p in (case / "out").iterdir() if p.is_file()):
            data = path.read_bytes()
            if name in ("symbols", "watch") and path.suffix == ".ipa":
                with zipfile.ZipFile(io.BytesIO(data)) as archive:
                    for entry in sorted(e for e in archive.namelist() if e.endswith(".symbols")):
                        print(f'    "{entry}": "{hashlib.sha256(archive.read(entry)).hexdigest()}",')
            elif name not in ("symbols", "watch") and path.name != "Packaging.log":
                print(f'    "{path.name}": "{hashlib.sha256(without_times(data) if path.suffix == ".ipa" else data).hexdigest()}",')
        for path in sorted(p for p in (case / "out").rglob("*/*") if p.is_file()):
            data = path.read_bytes()
            digest = hashlib.sha256(without_times(without_central_extras(data)) if path.suffix == ".assetpack" else data).hexdigest()
            print(f'    "{path.relative_to(case / "out")}": "{digest}",')


def refusal_lines(text, notes_prefix):
    """The `error:` lines of an output and the note lines after each, without their prefixes."""
    lines, inside = [], False
    for line in text.splitlines():
        if line.startswith("error: "):
            lines.append(line.removeprefix("error: ")); inside = True
        elif inside and line.startswith(notes_prefix):
            lines.append(line.removeprefix(notes_prefix).strip())
        else:
            inside = False
    return lines


def compare_symbols(output, nomac):
    """Runs `nomac symbols` on each dSYM of every experiment's archive and compares the files with
    the `Symbols/*.symbols` of its app-store-connect export."""
    failures = 0
    for ipa in sorted(output.glob("*/export-app-store-connect/*.ipa")):
        experiment = ipa.parent.parent
        with zipfile.ZipFile(ipa) as archive, tempfile.TemporaryDirectory(prefix="nomac-pack-symbols-") as work:
            for dsym in sorted(next(experiment.glob("*.xcarchive")).glob("dSYMs/*.dSYM")):
                subprocess.run([nomac, "symbols", str(dsym), "-o", work], check=True)
            for entry in sorted(e for e in archive.namelist() if e.endswith(".symbols")):
                ours = Path(work) / Path(entry).name
                same = ours.exists() and ours.read_bytes() == archive.read(entry)
                print(f"{'identical' if same else 'DIFFERENT'}: {experiment.name} {entry}")
                failures += not same
    return failures


def compare_archive(output, nomac):
    """Assembles each experiment's archive again with `nomac xcarchive`, from the build's
    products kept beside it and the archive's `Products` (which xcodebuild moved out of the
    build), and compares it with xcodebuild's: names, types, modes, symbolic link targets,
    contents and the modification times of files; `Info.plist` with its
    `CreationDate` taken from xcodebuild's."""
    failures = 0
    for built in sorted(output.glob("*/BuildProductsPath")):
        experiment = built.parent
        archive = experiment / "adhoc.xcarchive"
        if not archive.is_dir() or not (experiment / "archive-adhoc.json").is_file():
            continue
        with tempfile.TemporaryDirectory(prefix="nomac-pack-archive-") as work:
            intermediates, ours = Path(work) / "App", Path(work) / "adhoc.xcarchive"
            subprocess.run(["ditto", str(built), str(intermediates / "BuildProductsPath")], check=True)
            subprocess.run(["ditto", str(archive / "Products"), str(intermediates / "InstallationBuildProductsLocation")], check=True)
            argv = json.loads((experiment / "archive-adhoc.json").read_text())["argv"]
            scheme = argv[argv.index("-scheme") + 1]
            completed = subprocess.run([nomac, "xcarchive", "--intermediates", str(intermediates), "-archivePath", str(ours), "-scheme", scheme],
                                       capture_output=True, text=True)
            differences = [] if completed.returncode == 0 else [f"exit status {completed.returncode}: {completed.stderr.strip()}"]
            if completed.returncode == 0:
                date = re.search(rb"<date>[^<]*</date>", (archive / "Info.plist").read_bytes()).group(0)
                (ours / "Info.plist").write_bytes(re.sub(rb"<date>[^<]*</date>", date, (ours / "Info.plist").read_bytes()))
                differences += tree_differences(archive, ours)
                for path in sorted(archive.rglob("*")):
                    other = ours / path.relative_to(archive)
                    if path.is_symlink() or not path.is_file() or path == archive / "Info.plist" or not other.is_file():
                        continue
                    if int(path.stat().st_mtime) != int(other.stat().st_mtime):
                        differences.append(f"{path.relative_to(archive)}: modification time differs")
        print(f"{'identical' if not differences else 'DIFFERENT'}: {experiment.name} archive")
        for difference in differences:
            print(f"    {difference}")
        failures += bool(differences)
    return failures


def compare_refusals(output, nomac):
    """Runs `nomac export` for every export xcodebuild refused; compares the status and messages."""
    failures = 0
    for record in sorted(output.glob("*/export-*.json")):
        recorded = json.loads(record.read_text())
        if recorded["exitStatus"] == 0:
            continue
        argv = recorded["argv"]
        archive, options = argv[argv.index("-archivePath") + 1], argv[argv.index("-exportOptionsPlist") + 1]
        with tempfile.TemporaryDirectory(prefix="nomac-pack-export-") as work:
            completed = subprocess.run([nomac, "export", "-archivePath", archive, "-exportPath", str(Path(work) / "export"),
                                        "-exportOptionsPlist", options], capture_output=True, text=True)
        expected = refusal_lines(record.with_suffix(".log").read_text(), "  ")
        actual = refusal_lines(completed.stderr, "note: ")
        differences = [] if completed.returncode == recorded["exitStatus"] else [f"exit status {completed.returncode}, not {recorded['exitStatus']}"]
        if expected != actual:
            differences.append(f"messages {actual} != {expected}")
        print(f"{'identical' if not differences else 'DIFFERENT'}: {record.parent.name} {record.stem} (refused)")
        for difference in differences:
            print(f"    {difference}")
        failures += bool(differences)
    return failures


def compare_export(output, nomac):
    failures = compare_refusals(output, nomac)
    for xcode in sorted(output.glob("*/export-*")):
        label, experiment = xcode.name.removeprefix("export-"), xcode.parent
        if not xcode.is_dir() or plistlib.loads((experiment / f"export-{label}.plist").read_bytes())["method"] not in NOMAC_EXPORT_METHODS:
            continue
        if (xcode / "app-thinning.plist").exists():
            # Variants are named at random: distribution_experiments.py compare-thinning.
            continue
        with tempfile.TemporaryDirectory(prefix="nomac-pack-export-") as work:
            ours = Path(work) / "export"
            umask = recorded_umask(experiment / f"export-{label}.json")
            # The archive xcodebuild exported (experiments may export several).
            argv = json.loads((experiment / f"export-{label}.json").read_text())["argv"]
            completed = subprocess.run([nomac, "export", "-archivePath", argv[argv.index("-archivePath") + 1],
                                        "-exportPath", str(ours), "-exportOptionsPlist", str(experiment / f"export-{label}.plist")],
                                       capture_output=True, text=True, preexec_fn=with_umask(umask))
            differences = [] if completed.returncode == 0 else [f"exit status {completed.returncode}: {completed.stderr.strip()}"]
            for name in sorted(p.name for p in xcode.iterdir() if p.name != "Packaging.log"):
                if (xcode / name).is_dir():
                    # Hosted asset packs: zips, compared as the IPA is; the manifest byte for byte.
                    if not (ours / name).is_dir():
                        differences.append(f"{name}: missing")
                        continue
                    listed = [sorted(p.name for p in (xcode / name).iterdir()), sorted(p.name for p in (ours / name).iterdir())]
                    if listed[0] != listed[1]:
                        differences.append(f"{name}: files differ: {listed[0]} != {listed[1]}")
                        continue
                    for item in listed[0]:
                        left, right = (xcode / name / item).read_bytes(), (ours / name / item).read_bytes()
                        found = (zip_differences(without_central_extras(left), without_central_extras(right)) if item.endswith(".assetpack")
                                 else [] if left == right else ["contents differ"])
                        differences += [f"{name}/{item}: {d}" for d in found]
                    continue
                expected, actual = (xcode / name).read_bytes(), (ours / name).read_bytes() if (ours / name).exists() else None
                if actual is None:
                    differences.append(f"{name}: missing")
                elif name.endswith(".ipa"):
                    differences += [f"{name}: {d}" for d in zip_differences(expected, actual)]
                elif expected != actual:
                    differences.append(f"{name}: contents differ")
        print(f"{'identical' if not differences else 'DIFFERENT'}: {experiment.name} {label}")
        for difference in differences:
            print(f"    {difference}")
        failures += bool(differences)
    return failures


def zip_differences(expected, actual):
    """The differences between two zip archives other than their entry times."""
    left, right = without_times(expected), without_times(actual)
    if left == right:
        return []
    names = [zip_names(expected), zip_names(actual)]
    if names[0] != names[1]:
        return [f"entries differ: {names[0]} != {names[1]}"]
    offset = next((i for i in range(min(len(left), len(right))) if left[i] != right[i]), min(len(left), len(right)))
    return [f"bytes differ at {offset:#x} ({len(left)} and {len(right)} bytes)"]


def zip_names(raw):
    return [info.filename for info in zipfile.ZipFile(io.BytesIO(raw)).infolist()]


def without_times(raw):
    """`raw` with the DOS time and date and the "UX" field (times, owner ids) of every header
    zeroed, and the mode of `Payload/`, which follows the umask, cleared."""
    data = bytearray(raw)

    def clear_extra(start, length):
        end = start + length
        while start + 4 <= end:
            tag, size = struct.unpack_from("<HH", data, start)
            if tag == 0x5855:
                data[start + 4:start + 4 + size] = bytes(size)
            start += 4 + size

    end = data.rindex(b"PK\x05\x06")
    count, central = struct.unpack_from("<H", data, end + 10)[0], struct.unpack_from("<I", data, end + 16)[0]
    for _ in range(count):
        name_length, extra_length, comment_length = struct.unpack_from("<HHH", data, central + 28)
        local = struct.unpack_from("<I", data, central + 42)[0]
        data[central + 12:central + 16] = bytes(4)
        if data[central + 46:central + 46 + name_length] == b"Payload/":
            data[central + 38:central + 42] = bytes(4)
        clear_extra(central + 46 + name_length, extra_length)
        local_name, local_extra = struct.unpack_from("<HH", data, local + 26)
        data[local + 10:local + 14] = bytes(4)
        clear_extra(local + 30 + local_name, local_extra)
        central += 46 + name_length + extra_length + comment_length
    return bytes(data)


def without_central_extras(raw):
    """`raw` with the central directory's extra fields left out: an asset pack's zip has one only
    for a file whose access time is not its modification time, which depends on the machine."""
    data = bytes(raw)
    end = data.rindex(b"PK\x05\x06")
    count, _, start = struct.unpack_from("<HII", data, end + 10)
    central, position = b"", start
    for _ in range(count):
        name_length, extra_length, comment_length = struct.unpack_from("<HHH", data, position + 28)
        header = bytearray(data[position:position + 46])
        header[30:32] = bytes(2)
        name_end = position + 46 + name_length
        central += bytes(header) + data[position + 46:name_end] + data[name_end + extra_length:name_end + extra_length + comment_length]
        position = name_end + extra_length + comment_length
    record = bytearray(data[end:])
    struct.pack_into("<I", record, 12, len(central))
    return data[:start] + central + bytes(record)


@contextlib.contextmanager
def case_keychain(case):
    """A throwaway keychain holding the identities and certificates of `case/identity.pem`, in
    the file's order (codesign's keychain order decides its ambiguity message), on the user's
    keychain search list while codesign runs, so that it finds the chain there; the list is
    restored and the keychain deleted afterwards. Yields its path."""
    if case is None:
        yield None
        return
    text = (case / "identity.pem").read_text()
    blocks = [(m.group(1), m.group(0) + "\n") for m in re.finditer(r"-----BEGIN ([A-Z ]+)-----\n.*?-----END \1-----", text, re.S)]
    with tempfile.TemporaryDirectory(prefix="nomac-keychain-") as work:
        work = Path(work)
        key = work / "key.pem"
        key.write_text(next(block for label, block in blocks if label.endswith("PRIVATE KEY")))
        public = subprocess.run(["openssl", "pkey", "-in", str(key), "-pubout"], capture_output=True, text=True, check=True).stdout
        keychain = work / "case.keychain-db"
        subprocess.run(["security", "create-keychain", "-p", "nomac", str(keychain)], check=True)
        before = [line.strip().strip('"') for line in subprocess.run(["security", "list-keychains", "-d", "user"], capture_output=True,
                                                                      text=True, check=True).stdout.splitlines()]
        try:
            subprocess.run(["security", "unlock-keychain", "-p", "nomac", str(keychain)], check=True)
            for index, (label, block) in enumerate(blocks):
                if label != "CERTIFICATE":
                    continue
                certificate = work / f"{index}.pem"
                certificate.write_text(block)
                item = certificate
                if subprocess.run(["openssl", "x509", "-in", str(certificate), "-noout", "-pubkey"], capture_output=True, text=True).stdout == public:
                    item = work / f"{index}.p12"
                    export = ["openssl", "pkcs12", "-export", "-inkey", str(key), "-in", str(certificate), "-out", str(item), "-passout", "pass:nomac"]
                    if subprocess.run([*export, "-legacy"], capture_output=True).returncode != 0:
                        subprocess.run(export, check=True, capture_output=True)
                subprocess.run(["security", "import", str(item), "-k", str(keychain), "-P", "nomac", "-T", "/usr/bin/codesign"],
                               check=True, capture_output=True)
            subprocess.run(["security", "list-keychains", "-d", "user", "-s", *before, str(keychain)], check=True)
            yield str(keychain)
        finally:
            subprocess.run(["security", "list-keychains", "-d", "user", "-s", *before], check=True)
            subprocess.run(["security", "delete-keychain", str(keychain)], capture_output=True)


def signing_time(executable):
    """The CMS signing time in the code signature of a thin Mach-O file, as ISO 8601."""
    marker = bytes.fromhex("06092a864886f70d010905310f170d")
    start = executable.index(marker) + len(marker)
    text = executable[start:start + 12].decode()
    return f"20{text[0:2]}-{text[2:4]}-{text[4:6]}T{text[6:8]}:{text[8:10]}:{text[10:12]}Z"


def tree_differences(expected, actual):
    def entries(root):
        found = {}
        for path in [root, *sorted(root.rglob("*"))]:
            info = path.lstat()
            kind = "link" if path.is_symlink() else "dir" if path.is_dir() else "file"
            found[str(path.relative_to(root))] = (kind, oct(info.st_mode & 0o7777), path)
        return found
    left, right = entries(expected), entries(actual)
    differences = [f"only in codesign's output: {name}" for name in left.keys() - right.keys()]
    differences += [f"only in nomac's output: {name}" for name in right.keys() - left.keys()]
    for name in sorted(left.keys() & right.keys()):
        (kind, mode, path), (other_kind, other_mode, other_path) = left[name], right[name]
        if (kind, mode) != (other_kind, other_mode):
            differences.append(f"{name}: {kind} {mode} != {other_kind} {other_mode}")
        elif kind == "link" and os.readlink(path) != os.readlink(other_path):
            differences.append(f"{name}: link target differs")
        elif kind == "file":
            a, b = path.read_bytes(), other_path.read_bytes()
            if a != b:
                offset = next((i for i in range(min(len(a), len(b))) if a[i] != b[i]), min(len(a), len(b)))
                differences.append(f"{name}: contents differ at byte {offset:#x} ({len(a)} and {len(b)} bytes)")
    return differences


def main():
    if sys.argv[1] == "synthetic":
        return synthetic(Path(sys.argv[2]).resolve())
    if sys.argv[1] == "synthetic-export":
        return synthetic_export(Path(sys.argv[2]).resolve())
    if sys.argv[1] == "compare-export":
        sys.exit(1 if compare_export(Path(sys.argv[2]).resolve(), str(Path(sys.argv[3]).resolve())) else 0)
    if sys.argv[1] == "compare-archive":
        sys.exit(1 if compare_archive(Path(sys.argv[2]).resolve(), str(Path(sys.argv[3]).resolve())) else 0)
    if sys.argv[1] == "compare-symbols":
        sys.exit(1 if compare_symbols(Path(sys.argv[2]).resolve(), str(Path(sys.argv[3]).resolve())) else 0)
    if sys.argv[1] == "compare":
        sys.exit(1 if compare(Path(sys.argv[2]).resolve(), str(Path(sys.argv[3]).resolve())) else 0)
    output = Path(sys.argv[1]).resolve()
    selected = sys.argv[2:] or list(EXPERIMENTS)
    for name in selected:
        files, observe = EXPERIMENTS[name]
        experiment = output / name
        shutil.rmtree(experiment, ignore_errors=True)
        source = experiment / "source"
        for path, text in files().items():
            target = source / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)
        observe(source, experiment)


if __name__ == "__main__":
    main()
