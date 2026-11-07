#!/usr/bin/env python3
"""Observe what ibtool (Xcode 27.0) makes of iOS xibs and storyboards.

Runs on a Mac with Xcode 27.0 (DEVELOPER_DIR). Each experiment is a document written here from
scratch, compiled with the command lines an iOS build runs (docs/formats/nib.md):

    ibtool --errors --warnings --notices --module T --output-partial-info-plist <plist>
        --auto-activate-custom-fonts --target-device iphone --minimum-deployment-target 27.0
        --output-format human-readable-text --compile <out>.nib <in>.xib
    ibtool ... <in>.storyboard --compilation-directory <dir>, then ibtool ... --link <dir> <storyboardc>

ibtool resolves relative paths against its daemon's directory, so every path is absolute.
Outputs go to <output-dir>/observations.json (base64 file contents, status and messages).

Besides the xibs of EXPERIMENTS: each of STORYBOARDS (`storyboard` and its variants) is compiled
into a compilation directory and linked; `missing-file` compiles a document that does not exist
(the error format); `link-lproj` links storyboards compiled into two `.lproj` folders and a
plain one in one call; `stable` compiles `view` twice; `build` builds an app with a xib and a
storyboard and records the build's ibtool tasks; `corpus` (not run by default) compiles every
storyboard and xib of the corpus checkouts at /tmp/nomac-corpus where they are, recorded under
`corpus:<path>`.

Usage: nib_experiments.py <output-dir> [experiment ...]
"""

import base64
import json
import re
import random
import shutil
import subprocess
import sys
from pathlib import Path

XIB_HEAD = ('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB" version="3.0" toolsVersion="23504" '
            'targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" '
            'colorMatched="YES">\n'
            '    <device id="retina6_12" orientation="portrait" appearance="light"/>\n'
            '    <dependencies>\n'
            '        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>\n'
            '        <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>\n'
            '    </dependencies>\n'
            '    <objects>\n'
            '        <placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File\'s Owner"/>\n'
            '        <placeholder placeholderIdentifier="IBFirstResponder" id="-2" customClass="UIResponder"/>\n')
XIB_TAIL = '    </objects>\n</document>\n'


def view(attributes="", children="", frame=(0, 0, 393, 852), mask='widthSizable="YES" heightSizable="YES"', tag="view",
         identifier="iN0-l3-epB", extra=""):
    x, y, w, h = frame
    mask_element = f'            <autoresizingMask key="autoresizingMask" {mask}/>\n' if mask is not None else ""
    return (f'        <{tag} contentMode="scaleToFill" {attributes} id="{identifier}">\n'
            f'            <rect key="frame" x="{x}" y="{y}" width="{w}" height="{h}"/>\n'
            + mask_element + extra + children +
            '            <point key="canvasLocation" x="0" y="0"/>\n'
            f'        </{tag}>\n')


def xib(*objects):
    return XIB_HEAD + "".join(objects) + XIB_TAIL


EXPERIMENTS = {
    "view": xib(view()),
    "view-frame": xib(view(frame=(10, 20, 100, 50))),
    "view-fractional": xib(view(frame=(0.5, 1.25, 100.5, 50.75))),
    "view-no-mask": xib(view(mask=None)),
    "view-mask-flexible-all": xib(view(mask='flexibleMinX="YES" widthSizable="YES" flexibleMaxX="YES" flexibleMinY="YES" heightSizable="YES" flexibleMaxY="YES"')),
    "view-opaque-no": xib(view('opaque="NO"')),
    "view-clips": xib(view('clipsSubviews="YES"')),
    "view-hidden": xib(view('hidden="YES"')),
    "view-alpha": xib(view('alpha="0.5"')),
    "view-tag": xib(view('tag="7"')),
    "view-no-interaction": xib(view('userInteractionEnabled="NO"')),
    "view-multitouch": xib(view('multipleTouchEnabled="YES"')),
    "view-content-mode": xib(view().replace('contentMode="scaleToFill"', 'contentMode="center"')),
    "view-no-autoresize-subviews": xib(view('autoresizesSubviews="NO"')),
    "view-translates-no": xib(view('translatesAutoresizingMaskIntoConstraints="NO"')),
    "view-background-white": xib(view(extra='            <color key="backgroundColor" white="1" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>\n')),
    "view-background-rgb": xib(view(extra='            <color key="backgroundColor" red="1" green="0.5" blue="0.25" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>\n')),
    "view-semantic": xib(view('semanticContentAttribute="forceRightToLeft"')),
    "view-custom-class": xib(view('customClass="MyView"')),
    "view-custom-class-module": xib(view('customClass="MyView" customModule="T" customModuleProvider="target"')),
    "two-views": xib(view(), view(identifier="abc-de-fgh", frame=(0, 0, 10, 10))),
    "subview": xib(view(children='            <subviews>\n'
                        + view(identifier="sub-vi-ew1", frame=(10, 10, 50, 50)).replace('        ', '                ', 1)
                        .replace('<point key="canvasLocation" x="0" y="0"/>\n', '')
                        + '            </subviews>\n')),
    # Round 2: the order of the optional UIView keys, and masks.
    "view-flags-1": xib(view('opaque="YES" hidden="YES" tag="3" userInteractionEnabled="NO" multipleTouchEnabled="YES" clipsSubviews="YES" alpha="0.5"').replace('contentMode="scaleToFill"', 'contentMode="center"')),
    "view-flags-2": xib(view('hidden="YES" multipleTouchEnabled="YES" translatesAutoresizingMaskIntoConstraints="NO" alpha="0.25"').replace('contentMode="scaleToFill"', 'contentMode="redraw"')),
    "view-flags-3": xib(view('tag="1" userInteractionEnabled="NO" clipsSubviews="YES" semanticContentAttribute="playback"').replace('contentMode="scaleToFill"', 'contentMode="bottomRight"')),
    "view-mask-none": xib(view(mask="")),
    "view-mask-left": xib(view(mask='flexibleMinX="YES"')),
    "view-background-and-subview": xib(view(children='            <subviews>\n'
                        + view(identifier="sub-vi-ew1", frame=(10, 10, 50, 50)).replace('<point key="canvasLocation" x="0" y="0"/>\n', '')
                        + '            </subviews>\n',
                        extra='            <color key="backgroundColor" red="1" green="0.5" blue="0.25" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>\n')),
    "nested-subviews": xib(view(children='            <subviews>\n'
                        + view(identifier="sub-vi-ew1", frame=(10, 10, 50, 50), children='            <subviews>\n'
                               + view(identifier="sub-vi-ew2", frame=(1, 2, 3, 4)).replace('<point key="canvasLocation" x="0" y="0"/>\n', '')
                               + '            </subviews>\n').replace('<point key="canvasLocation" x="0" y="0"/>\n', '')
                        + view(identifier="sub-vi-ew3", frame=(5, 6, 7, 8)).replace('<point key="canvasLocation" x="0" y="0"/>\n', '')
                        + '            </subviews>\n')),
    "custom-class-subview": xib(view('customClass="Outer"', children='            <subviews>\n'
                        + view('customClass="Inner" customModule="T"', identifier="sub-vi-ew1", frame=(10, 10, 50, 50)).replace('<point key="canvasLocation" x="0" y="0"/>\n', '')
                        + '            </subviews>\n')),
    # Round 3: which strings are one object; placeholders with classes.
    "same-custom-class": xib(view(children='            <subviews>\n'
                        + view('customClass="Same"', identifier="sub-vi-ew1", frame=(10, 10, 50, 50)).replace('<point key="canvasLocation" x="0" y="0"/>\n', '')
                        + view('customClass="Same"', identifier="sub-vi-ew2", frame=(1, 2, 3, 4)).replace('<point key="canvasLocation" x="0" y="0"/>\n', '')
                        + '            </subviews>\n')),
    "owner-custom-class": xib(view()).replace('placeholderIdentifier="IBFilesOwner" id="-1"', 'placeholderIdentifier="IBFilesOwner" id="-1" customClass="Owner"'),
    "no-first-responder-class": xib(view()).replace(' customClass="UIResponder"', ''),
    # Round 4: several arrays of subviews alive one after the other.
    "sibling-subviews": xib(
        view(children='            <subviews>\n' + view(identifier="aaa-aa-aaa", frame=(1, 1, 10, 10)).replace('<point key="canvasLocation" x="0" y="0"/>\n', '')
             + '            </subviews>\n'),
        view(identifier="vv2-vv-vv2", frame=(0, 0, 100, 100),
             children='            <subviews>\n' + view(identifier="bbb-bb-bbb", frame=(2, 2, 20, 20)).replace('<point key="canvasLocation" x="0" y="0"/>\n', '')
             + '            </subviews>\n')),
    "nested-siblings": xib(view(children='            <subviews>\n'
        + view(identifier="ss1-ss-ss1", frame=(10, 10, 50, 50),
               children='            <subviews>\n' + view(identifier="xxx-xx-xxx", frame=(1, 1, 5, 5)).replace('<point key="canvasLocation" x="0" y="0"/>\n', '')
               + '            </subviews>\n').replace('<point key="canvasLocation" x="0" y="0"/>\n', '')
        + view(identifier="ss2-ss-ss2", frame=(60, 60, 50, 50),
               children='            <subviews>\n' + view(identifier="yyy-yy-yyy", frame=(2, 2, 6, 6)).replace('<point key="canvasLocation" x="0" y="0"/>\n', '')
               + '            </subviews>\n').replace('<point key="canvasLocation" x="0" y="0"/>\n', '')
        + '            </subviews>\n')),
    # Round 5: which module a custom class gets with customModuleProvider="target".
    "provider-target-other-module": xib(view('customClass="MyView" customModule="Other" customModuleProvider="target"')),
    "provider-target-no-module": xib(view('customClass="MyView" customModuleProvider="target"')),
    "module-without-provider-other": xib(view('customClass="MyView" customModule="Other"')),
    "provider-target-other-module-zed": xib(view('customClass="MyView" customModule="Other" customModuleProvider="target"')),
    "provider-target-no-module-zed": xib(view('customClass="MyView" customModuleProvider="target"')),
    "module-without-provider-zed": xib(view('customClass="MyView" customModule="Other"')),
}

# Round 6: the document's header, device and dependencies, one change each to `view`, and the
# deployment targets and target devices builds pass (the values the corpus projects use).
BASE = EXPERIMENTS["view"]
HEADER_VARIANTS = {
    "tools-version-21507": ('toolsVersion="23504"', 'toolsVersion="21507"'),
    "tools-version-17701": ('toolsVersion="23504"', 'toolsVersion="17701"'),
    "use-safe-areas": ('colorMatched="YES">', 'useSafeAreas="YES" colorMatched="YES">'),
    "no-trait-collections": (' useTraitCollections="YES"', ''),
    "launch-screen": ('colorMatched="YES">', 'launchScreen="YES" colorMatched="YES">'),
    "device-retina6_1": ('id="retina6_12"', 'id="retina6_1"'),
    "device-retina4_7-no-appearance": ('<device id="retina6_12" orientation="portrait" appearance="light"/>', '<device id="retina4_7" orientation="portrait"/>'),
    "device-dark": ('appearance="light"', 'appearance="dark"'),
    "device-landscape": ('<device id="retina6_12" orientation="portrait"', '<device id="retina5_9" orientation="landscape"'),
    "device-retina3_5": ('id="retina6_12"', 'id="retina3_5"'),
    "device-retina4_0": ('id="retina6_12"', 'id="retina4_0"'),
    "device-retina6_0": ('id="retina6_12"', 'id="retina6_0"'),
    "device-retina6_5": ('id="retina6_12"', 'id="retina6_5"'),
    "device-retina6_7": ('id="retina6_12"', 'id="retina6_7"'),
    "owner-module-target": ('id="-1" userLabel', 'id="-1" customClass="Owner" customModule="T" customModuleProvider="target" userLabel'),
    "owner-module": ('id="-1" userLabel', 'id="-1" customClass="Owner" customModule="Other" userLabel'),
    "plugin-version": ('version="23506"', 'version="21505"'),
    "deployment-ios": ('        <plugIn', '        <deployment identifier="iOS"/>\n        <plugIn'),
    "capabilities": ('        <capability name="documents saved', '        <capability name="Safe area layout guides" minToolsVersion="9.0"/>\n'
                     '        <capability name="System colors in document resources" minToolsVersion="11.0"/>\n'
                     '        <capability name="Named colors" minToolsVersion="9.0"/>\n'
                     '        <capability name="Constraints to layout margins" minToolsVersion="6.0"/>\n'
                     '        <capability name="documents saved'),
}
# Round 11: the header items of the corpus's documents nomac had not observed, one each.
DEVICE = '<device id="retina6_12" orientation="portrait" appearance="light"/>'
HEADER_VARIANTS.update({
    "system-version-15C50": ('colorMatched="YES">', 'systemVersion="15C50" colorMatched="YES">'),
    "system-version-22A380": ('colorMatched="YES">', 'systemVersion="22A380" colorMatched="YES">'),
    "device-adaptation": (DEVICE, '<device id="retina4_7" orientation="portrait">\n        <adaptation id="fullscreen"/>\n    </device>'),
    "device-adaptation-appearance": (DEVICE, '<device id="retina6_1" orientation="portrait" appearance="light">\n        <adaptation id="fullscreen"/>\n    </device>'),
    "device-layout-fullscreen": (DEVICE, '<device id="retina4_7" orientation="portrait" layout="fullscreen" appearance="light"/>'),
    "no-device": ('    ' + DEVICE + '\n', ''),
    **{f"device-{device}": ('id="retina6_12"', f'id="{device}"') for device in
       ["retina5_5", "retina6_3", "retina6_9", "ipad9_7", "ipad11_0rounded", "ipad12_9rounded"]},
    "capabilities-more": ('        <capability name="documents saved', '        <capability name="Image references" minToolsVersion="12.0"/>\n'
                          '        <capability name="Aspect ratio constraints" minToolsVersion="5.1"/>\n'
                          '        <capability name="Stack View standard spacing" minToolsVersion="9.0"/>\n'
                          '        <capability name="collection view cell content view" minToolsVersion="11.0"/>\n'
                          '        <capability name="documents saved'),
})
EXPERIMENTS.update({name: BASE.replace(old_text, new_text) for name, (old_text, new_text) in HEADER_VARIANTS.items()})
DEPLOYMENT_TARGETS = ["7.0", "8.0", "9.0", "10.0", "11.0", "12.0", "12.1", "12.4", "12.5", "13.0", "13.2", "14.0", "14.2", "15.0",
                      "15.2", "16.0", "16.4", "16.6", "17.0", "17.6", "18.0", "18.5", "18.6"]
EXPERIMENTS.update({f"deployment-{target}": BASE for target in DEPLOYMENT_TARGETS})
EXPERIMENTS.update({"devices-ipad": BASE, "devices-iphone-ipad": BASE, "devices-ipad-custom-class": EXPERIMENTS["view-custom-class"]})
# Integers of every size and sign, as a view's tag.
TAGS = [127, 128, 200, 255, 256, -1, -128, -129, 32767, 32768, 70000, 2147483647, 2147483648, 5000000000, -5000000000]
EXPERIMENTS.update({f"tag-{tag}": xib(view(f'tag="{tag}"')) for tag in TAGS})

# The options ibtool runs with, when not --module T, --minimum-deployment-target 27.0 and
# --target-device iphone.
OPTIONS = {
    **{name: {"module": "Zed"} for name in EXPERIMENTS if name.endswith("-zed")},
    **{f"deployment-{target}": {"deployment": target} for target in DEPLOYMENT_TARGETS},
    "devices-ipad": {"devices": ["ipad"]},
    "devices-iphone-ipad": {"devices": ["iphone", "ipad"]},
    "devices-ipad-custom-class": {"devices": ["ipad"]},
}


def options(name):
    """The module, deployment target and target devices of an experiment."""
    chosen = OPTIONS.get(name, {})
    return chosen.get("module", "T"), chosen.get("deployment", "27.0"), chosen.get("devices", ["iphone"])


STORYBOARD = """<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23504" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" useTraitCollections="YES" colorMatched="YES" initialViewController="BYZ-38-t0r">
    <device id="retina6_12" orientation="portrait" appearance="light"/>
    <dependencies>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23506"/>
        <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
    </dependencies>
    <scenes>
        <scene sceneID="tne-QT-ifu">
            <objects>
                <viewController id="BYZ-38-t0r" sceneMemberID="viewController">
                    <view key="view" contentMode="scaleToFill" id="8bC-Xf-vdC">
                        <rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
                        <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
                    </view>
                </viewController>
                <placeholder placeholderIdentifier="IBFirstResponder" id="dkx-z0-nzr" sceneMemberID="firstResponder"/>
            </objects>
            <point key="canvasLocation" x="0" y="0"/>
        </scene>
    </scenes>
</document>
"""

IBTOOL = ["xcrun", "ibtool", "--errors", "--warnings", "--notices", "--module", "T"]
COMMON = ["--auto-activate-custom-fonts", "--target-device", "iphone", "--minimum-deployment-target", "27.0",
          "--output-format", "human-readable-text"]


def files_under(directory):
    return {str(p.relative_to(directory)): base64.b64encode(p.read_bytes()).decode() for p in sorted(directory.rglob("*")) if p.is_file()}


def storyboard_experiment(work, document, name):
    source = work / ("Base.lproj/Main.storyboard" if name in LPROJ_STORYBOARDS else "Main.storyboard")
    source.parent.mkdir(parents=True)
    source.write_text(document)
    module, deployment, devices = options(name)
    common = ["--auto-activate-custom-fonts", *[argument for device in devices for argument in ("--target-device", device)],
              "--minimum-deployment-target", deployment, "--output-format", "human-readable-text"]
    ibtool = ["xcrun", "ibtool", "--errors", "--warnings", "--notices", "--module", module]
    compiled = run([*ibtool, "--output-partial-info-plist", str(work / "Main-SBPartialInfo.plist"), *common, str(source),
                    "--compilation-directory", str(work / "compiled")])
    linked = run([*ibtool, *common, "--link", str(work / "linked"), str(work / "compiled/Main.storyboardc")])
    return {"compile": {"status": compiled.returncode, "stdout": compiled.stdout.decode(errors="replace"), "files": files_under(work / "compiled")},
            "link": {"status": linked.returncode, "stdout": linked.stdout.decode(errors="replace"), "files": files_under(work / "linked")},
            "partial Info.plist": (work / "Main-SBPartialInfo.plist").read_text() if (work / "Main-SBPartialInfo.plist").exists() else None}


CORPUS = Path("/tmp/nomac-corpus")
SKIPPED = {"Pods", "node_modules", ".build", "DerivedData", "Carthage"}


def corpus_documents():
    """Every storyboard and xib of the corpus checkouts, outside dependency folders."""
    found = []
    for path in sorted(CORPUS.rglob("*")):
        if path.suffix in (".storyboard", ".xib") and path.is_file() and not SKIPPED & set(path.relative_to(CORPUS).parts):
            found.append(path)
    return found


def corpus_experiment(work):
    """Each corpus document compiled where it is checked out, with the options of the others; a
    storyboard into a compilation directory (outputs under `work`, never in the checkout)."""
    observations = {}
    for index, path in enumerate(corpus_documents()):
        out = work / f"{index:04}"
        out.mkdir(parents=True)
        if path.suffix == ".storyboard":
            proc = run([*IBTOOL, "--output-partial-info-plist", str(out / "SBPartialInfo.plist"), *COMMON, str(path),
                        "--compilation-directory", str(out / "compiled")])
            files = files_under(out / "compiled") if (out / "compiled").exists() else {}
        else:
            proc = run([*IBTOOL, "--output-partial-info-plist", str(out / "PartialInfo.plist"), *COMMON,
                        "--compile", str(out / (path.stem + ".nib")), str(path)])
            files = {name: data for name, data in files_under(out).items() if name.endswith(".nib") or "/" in name}
        observations[str(path)] = {"status": proc.returncode, "stdout": proc.stdout.decode(errors="replace"), "files": files}
        print(f"[corpus {index}] {proc.returncode} {path.relative_to(CORPUS)}", flush=True)
    return observations


def link_lproj_experiment(work):
    """STORYBOARD compiled into Base.lproj, fr.lproj and a plain folder, then linked in one call, as
    LinkStoryboards links all of a target's compiled storyboards."""
    work.mkdir(parents=True)
    source = work / "Main.storyboard"
    source.write_text(STORYBOARD)
    folders = ["Base.lproj", "fr.lproj", "plain"]
    for folder in folders:
        run([*IBTOOL, *COMMON, str(source), "--compilation-directory", str(work / "compiled" / folder)])
    linked = run([*IBTOOL, *COMMON, "--link", str(work / "app"), *[str(work / "compiled" / folder / "Main.storyboardc") for folder in folders]])
    return {"status": linked.returncode, "stdout": linked.stdout.decode(errors="replace"), "files": files_under(work / "app")}


def build_experiment(work):
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from pif_experiments import write_project
    files = {"Src/App.swift": "import UIKit\n@main class AppDelegate: UIResponder, UIApplicationDelegate {}\n",
             "Src/View.xib": EXPERIMENTS["view"], "Src/Base.lproj/Main.storyboard": STORYBOARD}
    project = write_project(work, "P", "C00000000000000000000001", "T", [("A00000000000000000000001", "Src")], files)
    proc = run(["xcodebuild", "-project", str(project), "-target", "T", "-configuration", "Debug", "-sdk", "iphoneos",
                "CODE_SIGNING_ALLOWED=NO", "SWIFT_VERSION=5.0", "ALWAYS_SEARCH_USER_PATHS=NO",
                f"SYMROOT={work}/build/products", f"OBJROOT={work}/build/intermediates", "build"])
    lines = proc.stdout.decode(errors="replace").splitlines()
    tasks = [line for i, line in enumerate(lines) if line.startswith(("CompileXIB ", "CompileStoryboard ", "LinkStoryboards"))
             or (i and lines[i - 2].startswith(("CompileXIB ", "CompileStoryboard ", "LinkStoryboards")) and "/ibtool " in line)]
    return {"status": proc.returncode, "tasks": [line.replace(str(work), "<WORK>") for line in tasks]}


def colored(color, resources=""):
    document = xib(view(extra=f"            {color}\n"))
    if resources:
        document = document.replace("    </objects>\n", f"    </objects>\n    <resources>\n{resources}    </resources>\n")
    return document


def gray(white, alpha, space="custom", custom="genericGamma22GrayColorSpace"):
    extra = f' customColorSpace="{custom}"' if space == "custom" else ""
    return f'<color key="backgroundColor" white="{white}" alpha="{alpha}" colorSpace="{space}"{extra}/>'


def rgb(red, green, blue, alpha, space="custom", custom="sRGB"):
    extra = f' customColorSpace="{custom}"' if space == "custom" else ""
    return f'<color key="backgroundColor" red="{red}" green="{green}" blue="{blue}" alpha="{alpha}" colorSpace="{space}"{extra}/>'


def system_color(name, definition):
    color = definition.replace(' key="backgroundColor"', "")
    return f"        <systemColor name=\"{name}\">\n            {color}\n        </systemColor>\n"


# Round 7: colors, as backgroundColor of the base view.
EXPERIMENTS.update({
    **{f"gray-{white}-{alpha}": colored(gray(white, alpha)) for white, alpha in
       [(0, 1), (1, 0), (0.5, 1), (0.5, 0.5), (0.33333333333333331, 1), (0.66666666666666663, 0.25), (1, 0.5), (0, 0), (1, 0.59999999999999998),
        (1, 1)]},
    **{f"rgb-{r}-{g}-{b}-{a}": colored(rgb(r, g, b, a)) for r, g, b, a in
       [(1, 0, 0, 1), (0, 0, 0, 1), (1, 1, 1, 1), (0.2, 0.4, 0.6, 1), (0.12345678901234568, 0.5, 0.98765432098765427, 0.80000000000000004), (0, 0, 0, 0)]},
    "calibrated-white": colored(gray(0.5, 1, "calibratedWhite")),
    "calibrated-white-custom": colored(gray(0.5, 1, "custom", "calibratedWhite")),
    "calibrated-rgb": colored(rgb(0.2, 0.4, 0.6, 1, "calibratedRGB")),
    "device-rgb": colored(rgb(0.2, 0.4, 0.6, 1, "deviceRGB")),
    "display-p3": colored(rgb(1, 0, 0, 1, "custom", "displayP3")),
    "system-background": colored('<color key="backgroundColor" systemColor="systemBackgroundColor"/>',
                                 system_color("systemBackgroundColor", gray(1, 1))),
    "system-label": colored('<color key="backgroundColor" systemColor="labelColor"/>',
                            system_color("labelColor", gray(0, 1))),
    "system-red": colored('<color key="backgroundColor" systemColor="systemRedColor"/>',
                          system_color("systemRedColor", rgb(1, 0.23137254901960785, 0.18823529411764706, 1))),
    "cocoa-white": colored('<color key="backgroundColor" cocoaTouchSystemColor="whiteColor"/>'),
    "cocoa-dark-text": colored('<color key="backgroundColor" cocoaTouchSystemColor="darkTextColor"/>'),
    "cocoa-group-background": colored('<color key="backgroundColor" cocoaTouchSystemColor="groupTableViewBackgroundColor"/>'),
    "named-color": colored('<color key="backgroundColor" name="Brand"/>',
                           '        <namedColor name="Brand">\n            <color red="0.2" green="0.4" blue="0.6" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>\n        </namedColor>\n'),
})


# Round 8: the values IB gives system colors (its own, not the document's definitions), and which
# colors are one object.
SYSTEM_COLORS = ["darkTextColor", "groupTableViewBackgroundColor", "labelColor", "lightTextColor", "linkColor",
                 "opaqueSeparatorColor", "placeholderTextColor", "scrollViewTexturedBackgroundColor", "secondaryLabelColor",
                 "secondarySystemBackgroundColor", "secondarySystemFillColor", "secondarySystemGroupedBackgroundColor",
                 "separatorColor", "systemBackgroundColor", "systemBlueColor", "systemBrownColor", "systemFillColor",
                 "systemGray2Color", "systemGray3Color", "systemGray4Color", "systemGray5Color", "systemGray6Color",
                 "systemGrayColor", "systemGroupedBackgroundColor", "systemIndigoColor", "systemPinkColor", "systemRedColor",
                 "systemYellowColor", "tertiaryLabelColor", "tertiarySystemBackgroundColor", "tintColor", "systemGreenColor",
                 "systemOrangeColor", "systemPurpleColor", "systemTealColor", "systemCyanColor", "systemMintColor",
                 "tertiarySystemFillColor", "quaternarySystemFillColor", "quaternaryLabelColor",
                 "tertiarySystemGroupedBackgroundColor", "whiteColor", "blackColor", "clearColor"]
COCOA_COLORS = ["whiteColor", "darkTextColor", "groupTableViewBackgroundColor", "lightTextColor", "clearColor",
                "scrollViewTexturedBackgroundColor", "viewFlipsideBackgroundColor", "blackColor", "grayColor", "redColor"]
EXPERIMENTS.update({
    **{f"systemColor-{name}": colored(f'<color key="backgroundColor" systemColor="{name}"/>', system_color(name, gray(0, 1)))
       for name in SYSTEM_COLORS},
    **{f"cocoaTouchSystemColor-{name}": colored(f'<color key="backgroundColor" cocoaTouchSystemColor="{name}"/>') for name in COCOA_COLORS},
    "same-color-twice": xib(view(children='            <subviews>\n'
                        + view(identifier="sub-vi-ew1", frame=(10, 10, 50, 50), extra=f"            {rgb(0.2, 0.4, 0.6, 1)}\n").replace('<point key="canvasLocation" x="0" y="0"/>\n', '')
                        + '            </subviews>\n', extra=f"            {rgb(0.2, 0.4, 0.6, 1)}\n")),
    "same-system-color-twice": xib(view(children='            <subviews>\n'
                        + view(identifier="sub-vi-ew1", frame=(10, 10, 50, 50), extra='            <color key="backgroundColor" systemColor="systemRedColor"/>\n').replace('<point key="canvasLocation" x="0" y="0"/>\n', '')
                        + '            </subviews>\n', extra='            <color key="backgroundColor" systemColor="systemRedColor"/>\n')).replace(
                        "    </objects>\n", "    </objects>\n    <resources>\n" + system_color("systemRedColor", gray(0, 1)) + "    </resources>\n"),
})


# Round 9: the key a color holds in the key table while it is encoded (BACKLOG B-262). The color
# starts after a subview with the first `count` of COLOR_KEY_FLAGS (each adds one key), with the
# table at 13, 23 or 41 buckets: as the outer view's color, or as a second subview's. `alpha` has
# an alpha a float does not hold, so `UIAlpha-Double` follows `UIAlpha`.
COLOR_KEY_FLAGS = ['hidden="YES"', 'alpha="0.5"', 'tag="7"', 'clipsSubviews="YES"', 'userInteractionEnabled="NO"',
                   'multipleTouchEnabled="YES"', 'translatesAutoresizingMaskIntoConstraints="NO"', 'customClass="Sub"',
                   'contentMode="center"']
COLOR_KEY_COLORS = {"rgb": (rgb(0.2, 0.4, 0.6, 1), ""), "gray": (gray(0.5, 1), ""), "alpha": (rgb(1, 0.5, 0.25, 0.80000000000000004), ""),
                    "system": ('<color key="backgroundColor" systemColor="systemBlueColor"/>', system_color("systemBlueColor", gray(0, 1)))}


def color_key(count, rotation, color, placement):
    flags = (COLOR_KEY_FLAGS[rotation:] + COLOR_KEY_FLAGS[:rotation])[:count]
    attributes = " ".join(flag for flag in flags if not flag.startswith("contentMode"))
    content = "center" if 'contentMode="center"' in flags else "scaleToFill"
    definition, resources = COLOR_KEY_COLORS[color]
    flagged = view(attributes, identifier="sub-vi-ew1", frame=(10, 10, 50, 50)).replace('contentMode="scaleToFill"', f'contentMode="{content}"')
    if placement == "outer":
        subviews = flagged
        outer_extra = f"            {definition}\n"
    else:
        subviews = flagged + view(identifier="sub-vi-ew2", frame=(1, 2, 3, 4), extra=f"            {definition}\n")
        outer_extra = ""
    subviews = subviews.replace('<point key="canvasLocation" x="0" y="0"/>\n', "")
    document = xib(view(children="            <subviews>\n" + subviews + "            </subviews>\n", extra=outer_extra))
    if resources:
        document = document.replace("    </objects>\n", f"    </objects>\n    <resources>\n{resources}    </resources>\n")
    return document


EXPERIMENTS.update({f"color-key-{placement}-{color}-{count}-{rotation}": color_key(count, rotation, color, placement)
                    for placement in ("outer", "sibling") for color in COLOR_KEY_COLORS for count in range(len(COLOR_KEY_FLAGS) + 1)
                    for rotation in (0, 4) if count or not rotation})


# Round 10: several colors in one nib, each written while UIAlphaComponent is held around its alpha.
def colors_in_views(outer, subviews, resources=""):
    children = "".join(view(identifier=f"sub-vi-ew{index}", frame=(index, index, 10, 10), extra=f"            {color}\n" if color else "")
                       .replace('<point key="canvasLocation" x="0" y="0"/>\n', "") for index, color in enumerate(subviews, 1))
    document = xib(view(children="            <subviews>\n" + children + "            </subviews>\n", extra=f"            {outer}\n" if outer else ""))
    if resources:
        document = document.replace("    </objects>\n", f"    </objects>\n    <resources>\n{resources}    </resources>\n")
    return document


SYSTEM_BLUE = '<color key="backgroundColor" systemColor="systemBlueColor"/>'
EXPERIMENTS.update({
    "two-colors-gray-rgb": colors_in_views(gray(0.5, 1), [rgb(0.2, 0.4, 0.6, 1)]),
    "two-colors-rgb-gray": colors_in_views(rgb(1, 0.5, 0.25, 1), [gray(0.25, 0.5)]),
    "two-colors-subviews": colors_in_views(None, [rgb(0.2, 0.4, 0.6, 1), gray(1, 0.80000000000000004)]),
    "three-colors": colors_in_views(SYSTEM_BLUE, [rgb(0.2, 0.4, 0.6, 1), gray(0.5, 1)], system_color("systemBlueColor", gray(0, 1))),
    "two-system-colors": colors_in_views(SYSTEM_BLUE, ['<color key="backgroundColor" systemColor="systemRedColor"/>'],
                                         system_color("systemBlueColor", gray(0, 1)) + system_color("systemRedColor", gray(0, 1))),
    "rgb-then-same-gray": colors_in_views(None, [rgb(1, 0, 0, 1), gray(0.5, 1), gray(0.5, 1)]),
})


def storyboard(*scenes, initial="BYZ-38-t0r", attributes="", resources="", capabilities=""):
    initial_attribute = f' initialViewController="{initial}"' if initial else ""
    document = (STORYBOARD.split("    <scenes>\n")[0].replace(' initialViewController="BYZ-38-t0r"', initial_attribute + attributes)
                + "    <scenes>\n" + "".join(scenes) + "    </scenes>\n")
    if capabilities:
        document = document.replace("    </dependencies>\n", capabilities + "    </dependencies>\n")
    if resources:
        document += f"    <resources>\n{resources}    </resources>\n"
    return document + "</document>\n"


def scene(controller="BYZ-38-t0r", view_id="8bC-Xf-vdC", scene_id="tne-QT-ifu", responder="dkx-z0-nzr", attributes="", guides="",
          view_attributes="", view_extra="", tag="viewController"):
    return (f'        <scene sceneID="{scene_id}">\n            <objects>\n'
            f'                <{tag} id="{controller}"{attributes} sceneMemberID="viewController">\n{guides}'
            f'                    <view key="view" contentMode="scaleToFill"{view_attributes} id="{view_id}">\n'
            '                        <rect key="frame" x="0.0" y="0.0" width="393" height="852"/>\n'
            '                        <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>\n'
            f'{view_extra}                    </view>\n                </{tag}>\n'
            f'                <placeholder placeholderIdentifier="IBFirstResponder" id="{responder}" sceneMemberID="firstResponder"/>\n'
            '            </objects>\n            <point key="canvasLocation" x="0" y="0"/>\n        </scene>\n')


LAYOUT_GUIDES = ('                    <layoutGuides>\n                        <viewControllerLayoutGuide type="top" id="Llm-lL-Icb"/>\n'
                 '                        <viewControllerLayoutGuide type="bottom" id="xb3-aO-Qok"/>\n                    </layoutGuides>\n')
SAFE_AREA = '                        <viewLayoutGuide key="safeArea" id="6Tk-OE-BBY"/>\n'
SAFE_AREA_CAPABILITY = '        <capability name="Safe area layout guides" minToolsVersion="9.0"/>\n'
SUBVIEW = ('                        <subviews>\n                            <view contentMode="scaleToFill" id="sub-vi-ew1">\n'
           '                                <rect key="frame" x="10" y="10" width="50" height="50"/>\n'
           '                                <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>\n'
           '                            </view>\n                        </subviews>\n')
SECOND = dict(controller="abc-de-fgh", view_id="ijk-lm-nop", scene_id="qrs-tu-vwx", responder="yza-bc-def")

# Storyboards, each compiled into a compilation directory and linked: `storyboard`, then one change
# each, and the shapes of the corpus's simplest storyboards (a launch screen, a custom controller
# with a safe area and a color).
STORYBOARDS = {
    "storyboard": STORYBOARD,
    "sb-no-initial": storyboard(scene(), initial=None),
    "sb-custom-class": storyboard(scene(attributes=' customClass="ViewController" customModule="T" customModuleProvider="target"')),
    "sb-custom-class-plain": storyboard(scene(attributes=' customClass="ViewController"')),
    "sb-identifier": storyboard(scene(attributes=' storyboardIdentifier="Detail"')),
    "sb-two-scenes": storyboard(scene(), scene(**SECOND)),
    "sb-two-scenes-second-initial": storyboard(scene(), scene(**SECOND), initial="abc-de-fgh"),
    "sb-layout-guides": storyboard(scene(guides=LAYOUT_GUIDES)),
    "sb-safe-area": storyboard(scene(view_extra=SAFE_AREA), attributes=' useSafeAreas="YES"', capabilities=SAFE_AREA_CAPABILITY),
    "sb-launch-screen": storyboard(scene(), attributes=' launchScreen="YES"'),
    "sb-background-rgb": storyboard(scene(view_extra='                        ' + rgb(0, 0, 0, 1) + "\n")),
    "sb-background-system": storyboard(scene(view_extra='                        <color key="backgroundColor" systemColor="systemBackgroundColor"/>\n'),
                                       resources=system_color("systemBackgroundColor", gray(1, 1))),
    "sb-subview": storyboard(scene(view_extra=SUBVIEW)),
    "sb-view-custom-class": storyboard(scene(view_attributes=' customClass="SKView"')),
    "sb-view-multitouch": storyboard(scene(view_attributes=' multipleTouchEnabled="YES"')),
    "sb-system-version": storyboard(scene(), attributes=' systemVersion="15C50"'),
    "sb-adaptation": storyboard(scene()).replace('<device id="retina6_12" orientation="portrait" appearance="light"/>',
                                                 '<device id="retina4_7" orientation="portrait">\n        <adaptation id="fullscreen"/>\n    </device>'),
    **{f"sb-device-{device}": storyboard(scene()).replace('id="retina6_12"', f'id="{device}"') for device in
       ["retina3_5", "retina4_0", "retina4_7", "retina5_5", "retina5_9", "retina6_0", "retina6_1", "retina6_3", "retina6_5",
        "retina6_7", "retina6_9", "ipad9_7", "ipad11_0rounded", "ipad12_9rounded"]},
    "sb-no-device": storyboard(scene()).replace('    <device id="retina6_12" orientation="portrait" appearance="light"/>\n', ''),
    "sb-landscape": storyboard(scene()).replace('orientation="portrait"', 'orientation="landscape"'),
    "sb-device-subview": storyboard(scene(view_extra=SUBVIEW.replace('flexibleMaxX="YES" flexibleMaxY="YES"', 'widthSizable="YES" flexibleMaxY="YES"')))
    .replace('id="retina6_12"', 'id="retina4_7"'),
    "sb-device-subview-fixed": storyboard(scene(view_extra=SUBVIEW)).replace('id="retina6_12"', 'id="retina4_7"'),
    "sb-no-device-frame": storyboard(scene()).replace('    <device id="retina6_12" orientation="portrait" appearance="light"/>\n', '')
    .replace('width="393" height="852"', 'width="320" height="480"'),
    "sb-device-retina3_5-frame": storyboard(scene()).replace('id="retina6_12"', 'id="retina3_5"').replace('width="393" height="852"', 'width="320" height="480"'),
    "sb-device-frame": storyboard(scene()).replace('width="393" height="852"', 'width="320" height="480"'),
    "sb-device-subview-both": storyboard(scene(view_extra=SUBVIEW.replace('flexibleMaxX="YES" flexibleMaxY="YES"',
                                                                          'flexibleMinX="YES" widthSizable="YES" flexibleMaxY="YES"')))
    .replace('id="retina6_12"', 'id="retina4_7"'),
    "sb-device-subview-fraction": storyboard(scene(view_extra=SUBVIEW.replace('flexibleMaxX="YES" flexibleMaxY="YES"',
                                                                              'flexibleMinX="YES" widthSizable="YES" flexibleMaxY="YES"')
                                                   .replace('width="50" height="50"', 'width="40" height="50"')))
    .replace('id="retina6_12"', 'id="retina4_7"'),
    "sb-dark": storyboard(scene()).replace('appearance="light"', 'appearance="dark"'),
    # The target devices: a scene's size with --target-device iphone, ipad or both, the document
    # declaring no device (its frame 375 x 667, as retro-rampage's), a phone or a tablet, each way.
    **{f"sb-targets-{targets}-{variant}": document for targets in ("iphone", "ipad", "both") for variant, document in {
        "no-device": storyboard(scene()).replace('    <device id="retina6_12" orientation="portrait" appearance="light"/>\n', '')
        .replace('width="393" height="852"', 'width="375" height="667"'),
        "no-device-320": storyboard(scene()).replace('    <device id="retina6_12" orientation="portrait" appearance="light"/>\n', '')
        .replace('width="393" height="852"', 'width="320" height="480"'),
        "retina4_7": storyboard(scene()).replace('id="retina6_12"', 'id="retina4_7"'),
        "retina4_7-landscape": storyboard(scene()).replace('id="retina6_12"', 'id="retina4_7"').replace('orientation="portrait"', 'orientation="landscape"'),
        "ipad9_7": storyboard(scene()).replace('id="retina6_12"', 'id="ipad9_7"'),
        "safe-area-subview": storyboard(scene(view_extra=SUBVIEW.replace('flexibleMaxX="YES" flexibleMaxY="YES"', 'widthSizable="YES" flexibleMaxY="YES"')
                                              + SAFE_AREA), attributes=' useSafeAreas="YES"', capabilities=SAFE_AREA_CAPABILITY)
        .replace('    <device id="retina6_12" orientation="portrait" appearance="light"/>\n', '').replace('width="393" height="852"', 'width="375" height="667"'),
    }.items()},
    "sb-game": storyboard(scene(attributes=' customClass="GameViewController" customModule="T" customModuleProvider="target"',
                                view_attributes=' multipleTouchEnabled="YES" customClass="SKView"',
                                view_extra='                        ' + rgb(0, 0, 0, 1) + "\n" + SAFE_AREA),
                          attributes=' useSafeAreas="YES"', capabilities=SAFE_AREA_CAPABILITY),
}
OPTIONS.update({name: {"devices": {"iphone": ["iphone"], "ipad": ["ipad"], "both": ["iphone", "ipad"]}[name.split("-")[2]]}
                for name in STORYBOARDS if name.startswith("sb-targets-")})
# The deployment target: a scene with no device (its frame 375 x 667) and one on retina4_7, at
# every deployment target of the xibs' `deployment-*`.
STORYBOARDS.update({f"sb-deployment-{target}-{variant}": STORYBOARDS[f"sb-targets-iphone-{variant}"]
                    for target in DEPLOYMENT_TARGETS for variant in ("no-device", "retina4_7")})
STORYBOARDS["sb-deployment-11.0-safe-area-subview"] = STORYBOARDS["sb-targets-iphone-safe-area-subview"]
OPTIONS.update({f"sb-deployment-{target}-{variant}": {"deployment": target} for target in DEPLOYMENT_TARGETS
                for variant in ("no-device", "retina4_7", "safe-area-subview")})


# Round 12: key-table thresholds (docs/formats/nib.md "Encoding"). A base view of UIKit controls with
# B keys, then the same view with a stepper carrying its first k optional attributes, each adding one
# key, last or first among the subviews; the long ladders then add a progress view without and with
# its style. The bases (random controls, options, flags and colors, seeded) were picked for their key
# counts, so the ladders cross 33/34, 53/54, 86/87 and 119/120 keys one key at a time.
# Each control: (tag, base attributes, children, frame size, optional attributes in the order they are added).
CONTROLS = {
    'label': ('label', 'opaque="NO" userInteractionEnabled="NO" contentMode="left" text="Label" lineBreakMode="tailTruncation" '
              'baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO"',
              '<fontDescription key="fontDescription" type="system" pointSize="17"/>\n<nil key="textColor"/>\n<nil key="highlightedColor"/>\n',
              (42, 21), ['textAlignment="center"', 'numberOfLines="3"', 'enabled="NO"', 'highlighted="YES"', 'minimumScaleFactor="0.5"',
                         'preferredMaxLayoutWidth="100"', 'adjustsLetterSpacingToFitWidth="YES"']),
    'button': ('button', 'opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" '
               'buttonType="system" lineBreakMode="middleTruncation"', '<state key="normal" title="Button"/>\n', (46, 30),
               ['enabled="NO"', 'selected="YES"', 'highlighted="YES"', 'showsTouchWhenHighlighted="YES"', 'adjustsImageWhenHighlighted="NO"',
                'reversesTitleShadowWhenHighlighted="YES"']),
    'textField': ('textField', 'opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="left" contentVerticalAlignment="center" '
                  'borderStyle="roundedRect" textAlignment="natural" minimumFontSize="17"',
                  '<fontDescription key="fontDescription" type="system" pointSize="14"/>\n<textInputTraits key="textInputTraits"/>\n', (97, 34),
                  ['text="Hello"', 'placeholder="Name"', 'clearsOnBeginEditing="YES"', 'adjustsFontSizeToFit="NO"', 'clearButtonMode="always"']),
    'switch': ('switch', 'opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center"', '',
               (51, 31), ['on="YES"', 'enabled="NO"']),
    'slider': ('slider', 'opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" '
               'value="0.5" minValue="0.0" maxValue="1"', '', (118, 31), ['continuous="NO"', 'enabled="NO"']),
    'stepper': ('stepper', 'opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" '
                'maximumValue="100"', '', (94, 32), ['value="5"', 'stepValue="2"', 'wraps="YES"', 'autorepeat="NO"', 'continuous="NO"']),
    'segmentedControl': ('segmentedControl', 'opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="left" contentVerticalAlignment="top" '
                         'segmentControlStyle="plain" selectedSegmentIndex="0"',
                         '<segments>\n<segment title="First"/>\n<segment title="Second"/>\n</segments>\n', (121, 32),
                         ['momentary="YES"', 'apportionsSegmentWidthsByContent="YES"', 'enabled="NO"']),
    'imageView': ('imageView', 'clipsSubviews="YES" userInteractionEnabled="NO" contentMode="scaleAspectFit"', '', (240, 128),
                  ['highlighted="YES"', 'adjustsImageSizeForAccessibilityContentSizeCategory="YES"']),
    'activity': ('activityIndicatorView', 'opaque="NO" contentMode="scaleToFill" style="medium"', '', (20, 20),
                 ['animating="YES"', 'hidesWhenStopped="NO"']),
    'progress': ('progressView', 'opaque="NO" contentMode="scaleToFill" progress="0.5"', '', (150, 4), ['progressViewStyle="bar"']),
    'pageControl': ('pageControl', 'opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" '
                    'numberOfPages="3"', '', (39, 37), ['currentPage="1"', 'hidesForSinglePage="YES"']),
    'stackView': ('stackView', 'opaque="NO" contentMode="scaleToFill"', '', (240, 128),
                  ['axis="vertical"', 'distribution="fillEqually"', 'alignment="center"', 'spacing="8"', 'baselineRelativeArrangement="YES"',
                   'layoutMarginsFollowReadableWidth="YES"']),
    'scrollView': ('scrollView', 'clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="scaleToFill"', '', (240, 128),
                   ['bounces="NO"', 'pagingEnabled="YES"', 'showsHorizontalScrollIndicator="NO"', 'showsVerticalScrollIndicator="NO"',
                    'bouncesZoom="NO"', 'directionalLockEnabled="YES"', 'keyboardDismissMode="onDrag"']),
    'view': ('view', 'contentMode="scaleToFill"', '', (50, 50), []),
}

# View attributes, each adding one key to a plain view (COLOR_KEY_FLAGS without contentMode).
VIEW_FLAGS = ['hidden="YES"', 'alpha="0.5"', 'tag="7"', 'clipsSubviews="YES"', 'userInteractionEnabled="NO"', 'multipleTouchEnabled="YES"',
              'translatesAutoresizingMaskIntoConstraints="NO"', 'customClass="Sub"']


def element(kind, index, options=(), flags=(), frame=None):
    tag, base, children, (w, h), _ = CONTROLS[kind]
    x, y = (index % 7) * 10, index * 3
    names = set()
    parts = []
    for part in [*base.split('" '), *options, *flags]:
        part = part if part.endswith('"') else part + '"'
        name = part.split('=')[0].strip()
        if name not in names: names.add(name); parts.append(part.strip())
    attributes = " ".join(parts)
    ident = f"e{index:02d}-bt-x{index:02d}"
    body = f'<rect key="frame" x="{x}" y="{y}" width="{w}" height="{h}"/>\n' + children
    indent = '                '
    return (f'{indent}<{tag} {attributes} id="{ident}">\n'
            + "".join(f'{indent}    {line}\n' for line in body.splitlines())
            + f'{indent}</{tag}>\n')


def control_document(elements, outer_flags=(), outer_extra=""):
    attributes = " ".join(outer_flags)
    subviews = ('            <subviews>\n' + "".join(elements) + '            </subviews>\n') if elements else ""
    return (XIB_HEAD
            + f'        <view contentMode="scaleToFill" {attributes} id="iN0-l3-epB">\n'
            '            <rect key="frame" x="0" y="0" width="393" height="852"/>\n'
            '            <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>\n'
            + outer_extra + subviews +
            '            <point key="canvasLocation" x="0" y="0"/>\n'
            '        </view>\n' + XIB_TAIL)


COLORS = ['<color key="backgroundColor" red="0.2" green="0.4" blue="0.6" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>',
          '<color key="backgroundColor" white="0.5" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>',
          '<color key="backgroundColor" red="1" green="0.5" blue="0.25" alpha="0.80000000000000004" colorSpace="custom" customColorSpace="sRGB"/>',
          '<color key="backgroundColor" white="0.25" alpha="0.5" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>']


BASE_KINDS = ["label", "button", "textField", "segmentedControl", "activity", "imageView", "progress", "pageControl", "stackView",
              "scrollView", "view"]
LONG_KINDS = [kind for kind in BASE_KINDS if kind != "progress"]


def base_elements(rng, n, kinds=BASE_KINDS):
    elements = []
    for i in range(n):
        kind = rng.choice(kinds)
        options = [option for option in CONTROLS[kind][4] if rng.random() < 0.6]
        flags = [flag for flag in VIEW_FLAGS if rng.random() < 0.3 and not (kind != "view" and flag.startswith("customClass"))]
        el = element(kind, i + 2, options, flags)
        if rng.random() < 0.3:
            tag = CONTROLS[kind][0]
            el = el.replace(f"                </{tag}>\n", "                    " + rng.choice(COLORS) + f"\n                </{tag}>\n", 1)
        elements.append(el)
    return elements


def ladder(name, elements, longer=False):
    stepper_options = CONTROLS["stepper"][4]
    documents = {f"{name}-none": control_document(elements)}
    steps = [[element("stepper", 1, stepper_options[:k])] for k in range(len(stepper_options) + 1)]
    if longer:
        full = element("stepper", 1, stepper_options)
        steps += [[full, element("progress", 90)], [full, element("progress", 90, CONTROLS["progress"][4])]]
    for k, extra in enumerate(steps):
        documents[f"{name}-end-{k}"] = control_document(elements + extra)
        documents[f"{name}-front-{k}"] = control_document(extra + elements)
    return documents


LADDERS = {}
for low, seed in [(28, 13), (48, 53), (81, 4)]:
    rng = random.Random(f"base{seed}")
    LADDERS.update(ladder(f"ladder{low}-b{seed}", base_elements(rng, rng.randint(1, 9))))
for low, seed in [(80, 20), (112, 3)]:
    rng = random.Random(f"longbase{seed}")
    LADDERS.update(ladder(f"ladderlong{low}-b{seed}", base_elements(rng, rng.randint(6, 18), LONG_KINDS), longer=True))
EXPERIMENTS.update(LADDERS)


# Round 13: the corpus's calibratedWhite values and Xcode 11 system colors, one each, as a view's
# background in a xib and in a storyboard; a storyboard First Responder with a class.
CALIBRATED_WHITES = [("1", "1"), ("0.0", "0.0"), ("0.0", "1"), ("0.66666666666666663", "1"), ("0.33333333333333331", "1"),
                     ("0.96999999999999997", "1"), ("0.95999999999999996", "1")]
CORPUS_COLORS = {
    **{f"cw-{white}-{alpha}": f'<color key="backgroundColor" white="{white}" alpha="{alpha}" colorSpace="calibratedWhite"/>'
       for white, alpha in CALIBRATED_WHITES},
    "cw-custom-1-1": '<color key="backgroundColor" white="1" alpha="1" colorSpace="custom" customColorSpace="calibratedWhite"/>',
    "x11-system-background": '<color key="backgroundColor" xcode11CocoaTouchSystemColor="systemBackgroundColor" cocoaTouchSystemColor="whiteColor"/>',
}
EXPERIMENTS.update({name: colored(color) for name, color in CORPUS_COLORS.items()})
STORYBOARDS.update({f"sb-{name}": storyboard(scene(view_extra=f"                        {color}\n")) for name, color in CORPUS_COLORS.items()})
STORYBOARDS["sb-first-responder-class"] = storyboard(scene()).replace(
    'placeholderIdentifier="IBFirstResponder" id="dkx-z0-nzr"', 'placeholderIdentifier="IBFirstResponder" id="dkx-z0-nzr" customClass="UIResponder"')


# Round 14: colors in documents without colorMatched="YES" (the corpus's flutter storyboards).
UNMATCHED_COLORS = {
    "cw-1": '<color key="backgroundColor" white="1" alpha="1" colorSpace="custom" customColorSpace="calibratedWhite"/>',
    "cw-0.5": '<color key="backgroundColor" white="0.5" alpha="1" colorSpace="custom" customColorSpace="calibratedWhite"/>',
    "cw-0-0": '<color key="backgroundColor" white="0.0" alpha="0.0" colorSpace="calibratedWhite"/>',
    "gray-1": gray(1, 1), "gray-0.5": gray(0.5, 1), "rgb": rgb(0.2, 0.4, 0.6, 1),
    "system-red": '<color key="backgroundColor" systemColor="systemRedColor"/>',
    "cocoa-white": '<color key="backgroundColor" cocoaTouchSystemColor="whiteColor"/>',
}
UNMATCHED_RESOURCES = {"system-red": system_color("systemRedColor", gray(0, 1))}
for name, color in UNMATCHED_COLORS.items():
    EXPERIMENTS[f"unmatched-{name}"] = colored(color, UNMATCHED_RESOURCES.get(name, "")).replace(' colorMatched="YES"', "")
    STORYBOARDS[f"sb-unmatched-{name}"] = storyboard(scene(view_extra=f"                        {color}\n"),
                                                     resources=UNMATCHED_RESOURCES.get(name, "")).replace(' colorMatched="YES"', "")


# Round 15: constraints (their keys, and the order of a view's constraints: by attribute, by item and
# by the items' frames), image views and their `<image>` resources, views without frames, and safe
# area layout guides in xibs. A root view of one or more subviews that do not translate their masks.
ATTRIBUTES = ["left", "right", "top", "bottom", "leading", "trailing", "width", "height", "centerX", "centerY"]
EDGES = ["top", "bottom", "leading", "trailing"]
ROOT = "iN0-l3-epB"
SAFE_GUIDE = "vUN-kp-3ea"


def subview(identifier, frame=(10, 20, 100, 50), tag="view", attributes="", constraints="", rect=True):
    x, y, w, h = frame
    inner = f'                    <constraints>\n{constraints}                    </constraints>\n' if constraints else ""
    rect_element = f'                    <rect key="frame" x="{x}" y="{y}" width="{w}" height="{h}"/>\n' if rect else ""
    mode = "" if "contentMode=" in attributes else ' contentMode="scaleToFill"'
    return (f'                <{tag}{mode}{attributes} translatesAutoresizingMaskIntoConstraints="NO" id="{identifier}">\n'
            f'{rect_element}{inner}                </{tag}>\n')


def constraint(number, first, first_attribute, second=None, second_attribute=None, extra="", indent=16):
    first_item = f' firstItem="{first}"' if first else ""
    second_item = f' secondItem="{second}" secondAttribute="{second_attribute}"' if second else ""
    return f'{" " * indent}<constraint{first_item} firstAttribute="{first_attribute}"{second_item}{extra} id="c{number:02d}-aa-aaa"/>\n'


def constrained(subviews, constraints, safe=False, resources="", root_rect=True):
    guide = f'            <viewLayoutGuide key="safeArea" id="{SAFE_GUIDE}"/>\n' if safe else ""
    rect_element = '            <rect key="frame" x="0" y="0" width="393" height="852"/>\n' if root_rect else ""
    constraint_elements = f"            <constraints>\n{constraints}            </constraints>\n" if constraints else ""
    text = xib(f'        <view contentMode="scaleToFill" id="{ROOT}">\n{rect_element}'
               '            <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>\n'
               f'            <subviews>\n{subviews}            </subviews>\n{guide}{constraint_elements}'
               '            <point key="canvasLocation" x="0" y="0"/>\n        </view>\n')
    if safe:
        text = text.replace(' colorMatched="YES"', ' useSafeAreas="YES" colorMatched="YES"').replace(
            '        <capability name="documents saved', SAFE_AREA_CAPABILITY + '        <capability name="documents saved')
    if resources:
        text = text.replace("    </objects>\n", f"    </objects>\n    <resources>\n{resources}    </resources>\n")
    return text


def pinned(item, first_number, other=ROOT):
    return "".join(constraint(first_number + k, item, a, other, a) for k, a in enumerate(EDGES))


CONSTRAINTS = {}
for order, numbers in {"ids": list(range(10)), "reversed": list(range(9, -1, -1)), "shuffled": [8, 3, 1, 4, 7, 0, 9, 6, 2, 5]}.items():
    CONSTRAINTS[f"order-sub-root-{order}"] = constrained(subview("sss-ss-ss1"), "".join(
        constraint(n, "sss-ss-ss1", a, ROOT, a) for n, a in zip(numbers, ATTRIBUTES)))
    CONSTRAINTS[f"order-root-sub-{order}"] = constrained(subview("sss-ss-ss1"), "".join(
        constraint(n, None, a, "sss-ss-ss1", a) for n, a in zip(numbers, ATTRIBUTES)))
CONSTRAINTS["order-document-shuffled"] = constrained(subview("sss-ss-ss1"), "".join(
    constraint(k, "sss-ss-ss1", a, ROOT, a) for k, a in sorted(enumerate(ATTRIBUTES), key=lambda pair: (pair[0] * 7) % 10)))
CONSTRAINTS["order-alternating"] = constrained(subview("sss-ss-ss1"), "".join(
    constraint(k, "sss-ss-ss1", a, ROOT, a) if k % 2 else constraint(k, None, a, "sss-ss-ss1", a) for k, a in enumerate(ATTRIBUTES)))
CONSTRAINTS["order-sub-safe"] = constrained(subview("sss-ss-ss1"), "".join(
    constraint(k, "sss-ss-ss1", a, SAFE_GUIDE, a) for k, a in enumerate(ATTRIBUTES)), safe=True)
CONSTRAINTS["order-safe-sub"] = constrained(subview("sss-ss-ss1"), "".join(
    constraint(k, SAFE_GUIDE, a, "sss-ss-ss1", a) for k, a in enumerate(ATTRIBUTES)), safe=True)
for i, a in enumerate(ATTRIBUTES):
    for b in ATTRIBUTES[i + 1:]:
        CONSTRAINTS[f"order-pair-{a}-{b}"] = constrained(subview("sss-ss-ss1"), constraint(0, "sss-ss-ss1", a, ROOT, a)
                                                         + constraint(1, "sss-ss-ss1", b, ROOT, b))
        CONSTRAINTS[f"order-pair-safe-{a}-{b}"] = constrained(subview("sss-ss-ss1"), constraint(0, "sss-ss-ss1", a, SAFE_GUIDE, a)
                                                              + constraint(1, "sss-ss-ss1", b, SAFE_GUIDE, b), safe=True)
# Each edge to the root view or to the safe area, top and leading from the subview, bottom and
# trailing from the other item; and the same with the subview at the root's origin.
for mask in range(16):
    lines = ""
    for k, a in enumerate(EDGES):
        other = SAFE_GUIDE if mask >> k & 1 else ROOT
        lines += constraint(k, "sss-ss-ss1", a, other, a) if a in ("top", "leading") else constraint(k, other, a, "sss-ss-ss1", a)
    CONSTRAINTS[f"order-edges-safe-{mask:02d}"] = constrained(subview("sss-ss-ss1"), lines, safe=True)
    CONSTRAINTS[f"order-edges-safe-{mask:02d}-origin"] = constrained(subview("sss-ss-ss1", (0, 0, 393, 852)), lines, safe=True)
CONSTRAINTS["order-twice"] = constrained(subview("sss-ss-ss1"),
    constraint(0, "sss-ss-ss1", "top", ROOT, "top", ' constant="20"')
    + constraint(1, "sss-ss-ss1", "top", ROOT, "top", ' relation="greaterThanOrEqual" constant="10"')
    + constraint(2, "sss-ss-ss1", "top", ROOT, "top", ' constant="30" priority="250"')
    + constraint(3, "sss-ss-ss1", "top", ROOT, "top", ' relation="lessThanOrEqual" constant="40"')
    + constraint(4, "sss-ss-ss1", "leading", ROOT, "leading", ' constant="5"')
    + constraint(5, "sss-ss-ss1", "leading", ROOT, "trailing", ' constant="-5"'))
CONSTRAINTS["order-cross"] = constrained(subview("sss-ss-ss1"), "".join(
    constraint(k, "sss-ss-ss1", a, ROOT, b) for k, (a, b) in enumerate([("top", "bottom"), ("leading", "trailing"), ("bottom", "top"),
        ("trailing", "leading"), ("centerX", "leading"), ("width", "height"), ("height", "width"), ("centerY", "top")])))
SIZE_CONSTRAINTS = {
    "width-height": constraint(0, None, "width", extra=' constant="100"', indent=24) + constraint(1, None, "height", extra=' constant="50"', indent=24),
    "height-width": constraint(1, None, "width", extra=' constant="100"', indent=24) + constraint(0, None, "height", extra=' constant="50"', indent=24),
    "aspect": constraint(0, None, "width", extra=' constant="100"', indent=24)
              + constraint(1, "sss-ss-ss1", "width", "sss-ss-ss1", "height", ' multiplier="2:1"', indent=24),
    "relations": constraint(0, None, "height", extra=' relation="greaterThanOrEqual" constant="10"', indent=24)
                 + constraint(1, None, "height", extra=' relation="lessThanOrEqual" constant="90"', indent=24)
                 + constraint(2, None, "height", extra=' constant="50"', indent=24),
}
for name, inner in SIZE_CONSTRAINTS.items():
    CONSTRAINTS[f"order-size-{name}"] = constrained(subview("sss-ss-ss1", constraints=inner),
        constraint(5, "sss-ss-ss1", "centerX", ROOT, "centerX") + constraint(6, "sss-ss-ss1", "centerY", ROOT, "centerY"))
# Two and three subviews pinned to the root: groups by item, in the order of their frames.
FRAME_PAIRS = {
    "above": ((10, 20, 100, 50), (10, 200, 100, 50)), "below": ((10, 200, 100, 50), (10, 20, 100, 50)),
    "right": ((200, 20, 100, 50), (10, 20, 100, 50)), "same": ((10, 20, 100, 50), (10, 20, 100, 50)),
    "diagonal": ((10, 200, 100, 50), (200, 20, 100, 50)), "full-center": ((0, 0, 393, 852), (100, 400, 100, 50)),
    "center-full": ((100, 400, 100, 50), (0, 0, 393, 852)), "overlap": ((0, 0, 100, 100), (-1, -1, 102, 102)),
    "contain": ((10, 10, 300, 300), (50, 50, 10, 10)), "contain-reversed": ((50, 50, 10, 10), (10, 10, 300, 300)),
    "same-y-tall": ((300, 20, 50, 500), (10, 20, 50, 50)), "overlap-y": ((300, 20, 50, 100), (10, 60, 50, 100)),
}
for label, (first_frame, second_frame) in FRAME_PAIRS.items():
    for a, b in (("aaa-aa-aa1", "bbb-bb-bb1"), ("bbb-bb-bb1", "aaa-aa-aa1")):
        CONSTRAINTS[f"order-two-{label}-{a[0]}{b[0]}"] = constrained(subview(a, first_frame) + subview(b, second_frame),
                                                                    pinned(a, 0) + pinned(b, 4))
        CONSTRAINTS[f"order-two-{label}-{a[0]}{b[0]}-second-first"] = constrained(subview(a, first_frame) + subview(b, second_frame),
                                                                                 pinned(b, 0) + pinned(a, 4))
THREE = ["aaa-aa-aa1", "bbb-bb-bb1", "ccc-cc-cc1"]
for permutation in ([0, 1, 2], [1, 2, 0], [2, 1, 0]):
    CONSTRAINTS["order-three-" + "".join(map(str, permutation))] = constrained(
        "".join(subview(n, (10, 20 + 100 * k, 100, 50)) for k, n in enumerate(THREE)),
        "".join(pinned(THREE[i], 4 * k) for k, i in enumerate(permutation)))
CONSTRAINTS["order-guide-and-two"] = constrained(subview("aaa-aa-aa1") + subview("bbb-bb-bb1", (10, 200, 100, 50)),
    pinned("aaa-aa-aa1", 0) + constraint(4, SAFE_GUIDE, "bottom", "bbb-bb-bb1", "bottom") + constraint(5, "bbb-bb-bb1", "top", SAFE_GUIDE, "top"), safe=True)
CONSTRAINTS["order-sibling"] = constrained(subview("aaa-aa-aa1") + subview("bbb-bb-bb1", (10, 200, 100, 50)),
    pinned("aaa-aa-aa1", 0) + constraint(4, "bbb-bb-bb1", "top", "aaa-aa-aa1", "bottom", ' constant="8"'))
# A constraint's keys: constants, relations, multipliers, priorities, identifiers, placeholders.
for name, extra in {"constant": ' constant="10"', "negative": ' constant="-10"', "fraction": ' constant="10.5"',
                    "third": ' constant="0.33333333333333331"', "less": ' relation="lessThanOrEqual"',
                    "greater": ' relation="greaterThanOrEqual" constant="4"', "multiplier": ' multiplier="0.5"',
                    "multiplier-ratio": ' multiplier="3:2"', "priority-250": ' priority="250"', "priority-999": ' priority="999"',
                    "identifier": ' identifier="top-spacing"', "placeholder": ' placeholder="YES"',
                    "all": ' relation="greaterThanOrEqual" constant="12" multiplier="2" priority="750"'}.items():
    CONSTRAINTS[f"constraint-{name}"] = constrained(subview("sss-ss-ss1"), constraint(0, "sss-ss-ss1", "top", ROOT, "top", extra))
CONSTRAINTS["constraint-self-width"] = constrained(subview("sss-ss-ss1", constraints=constraint(0, None, "width", extra=' constant="100"', indent=24)), "")
CONSTRAINTS["constraint-root-height"] = constrained(subview("sss-ss-ss1"), constraint(0, None, "height", extra=' constant="852"'))
CONSTRAINTS["constraint-to-safe-area"] = constrained(subview("sss-ss-ss1"), constraint(0, "sss-ss-ss1", "top", SAFE_GUIDE, "top"), safe=True)
CONSTRAINTS["safe-area"] = constrained(subview("sss-ss-ss1"), "", safe=True)
CONSTRAINTS["safe-area-no-subview"] = constrained("", "", safe=True).replace("            <subviews>\n            </subviews>\n", "")
# Image views and `<image>` resources.
LOGO = '        <image name="Logo" width="168" height="185"/>\n'
IMAGE_VIEWS = {
    "plain": ('image="Logo"', LOGO),
    "flutter": (' opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" image="Logo"', LOGO),
    "common": (' userInteractionEnabled="NO" horizontalHuggingPriority="251" verticalHuggingPriority="251" image="Logo"', LOGO),
    "clears": (' clearsContextBeforeDrawing="NO" userInteractionEnabled="NO" contentMode="scaleAspectFit" horizontalHuggingPriority="251" verticalHuggingPriority="251" image="Logo"', LOGO),
    "aspect-fill": (' contentMode="scaleAspectFill" image="Logo"', LOGO),
    "hugging-252": (' horizontalHuggingPriority="252" verticalHuggingPriority="252" image="Logo"', LOGO),
    "hugging-horizontal": (' horizontalHuggingPriority="251" image="Logo"', LOGO),
    "hugging-vertical": (' verticalHuggingPriority="251" image="Logo"', LOGO),
    "size-1": ('image="Logo"', '        <image name="Logo" width="1" height="1"/>\n'),
    "size-fraction": ('image="Logo"', '        <image name="Logo" width="292.5" height="61"/>\n'),
    "name-png": ('image="982-food-toolbar.png"', '        <image name="982-food-toolbar.png" width="22" height="18"/>\n'),
    "no-image": ("", ""),
    "two": ('image="Logo"', LOGO),
    "two-hugging": (' horizontalHuggingPriority="251" verticalHuggingPriority="251" image="Logo"', LOGO),
}
for name, (attributes, resources) in IMAGE_VIEWS.items():
    attributes = attributes if attributes.startswith(" ") or not attributes else " " + attributes
    views = subview("iii-ii-ii1", (112, 333, 168, 185), "imageView", attributes)
    if name.startswith("two"):
        views += subview("iii-ii-ii2", (10, 20, 168, 185), "imageView", attributes)
    CONSTRAINTS[f"image-view-{name}"] = constrained(views, "", resources=resources)
CONSTRAINTS["image-view-no-rect"] = constrained(subview("iii-ii-ii1", tag="imageView", attributes=' image="Logo"', rect=False), "", resources=LOGO)
CONSTRAINTS["image-view-centered"] = constrained(subview("iii-ii-ii1", (112, 333, 168, 185), "imageView", ' image="Logo"'),
    constraint(0, "iii-ii-ii1", "centerX", ROOT, "centerX") + constraint(1, "iii-ii-ii1", "centerY", ROOT, "centerY"), resources=LOGO)
CONSTRAINTS["view-no-rect"] = constrained(subview("sss-ss-ss1", rect=False), "", root_rect=False)
# Components written with 17 digits: n/255 values and others, in xibs and storyboards, with and
# without launchScreen (the corpus's nextcloud launch screen keeps 10 digits of its double).
PRECISE_COLORS = {"n255": rgb("0.0", "0.50980392156862742", "0.78823529411764703", 1),
                  "n255-other": rgb("0.30196078431372547", "0.96078431372549022", "0.058823529411764705", 1),
                  "arbitrary": rgb("0.12345678901234567", "0.98765432109876543", "0.33333333333333331", 1)}
for name, color in PRECISE_COLORS.items():
    CONSTRAINTS[f"precise-{name}"] = colored(color)
    CONSTRAINTS[f"precise-{name}-launch"] = colored(color).replace(' colorMatched="YES"', ' launchScreen="YES" colorMatched="YES"')
    STORYBOARDS[f"sb-precise-{name}"] = storyboard(scene(view_extra=f"                        {color}\n"))
    STORYBOARDS[f"sb-precise-{name}-launch"] = storyboard(scene(view_extra=f"                        {color}\n"), attributes=' launchScreen="YES"')
EXPERIMENTS.update(CONSTRAINTS)

# Launch-screen storyboards of the corpus's shapes: an image view centered in the scene's view with
# legacy layout guides or a safe area, and flutter's (no device, no frames) at the deployment
# targets and devices builds pass.
IMAGE_SCENE = ('                        <subviews>\n'
               '                            <imageView opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" image="LaunchImage" translatesAutoresizingMaskIntoConstraints="NO" id="YRO-k0-Ey4">\n'
               '{rect}                            </imageView>\n                        </subviews>\n'
               '                        <color key="backgroundColor" red="1" green="1" blue="1" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>\n'
               '{guide}                        <constraints>\n'
               '                            <constraint firstItem="YRO-k0-Ey4" firstAttribute="centerX" secondItem="{other}" secondAttribute="centerX" id="1a2-6s-vTC"/>\n'
               '                            <constraint firstItem="YRO-k0-Ey4" firstAttribute="centerY" secondItem="{other}" secondAttribute="centerY" id="4X2-HB-R7a"/>\n'
               '                        </constraints>\n')
IMAGE_RECT = '                                <rect key="frame" x="112.5" y="333.5" width="168" height="185"/>\n'
LAUNCH_IMAGE = '        <image name="LaunchImage" width="168" height="185"/>\n'
STORYBOARDS["sb-image-view"] = storyboard(scene(guides=LAYOUT_GUIDES, view_extra=IMAGE_SCENE.format(rect=IMAGE_RECT, guide="", other="8bC-Xf-vdC")),
                                          resources=LAUNCH_IMAGE)
STORYBOARDS["sb-image-view-safe-area"] = storyboard(
    scene(view_extra=IMAGE_SCENE.format(rect=IMAGE_RECT, guide=SAFE_AREA, other="6Tk-OE-BBY")), resources=LAUNCH_IMAGE,
    attributes=' useSafeAreas="YES"', capabilities=SAFE_AREA_CAPABILITY)
FLUTTER_LAUNCH = storyboard(scene(guides=LAYOUT_GUIDES, view_extra=IMAGE_SCENE.format(rect="", guide="", other="8bC-Xf-vdC")),
                            resources=LAUNCH_IMAGE).replace(
    '    <device id="retina6_12" orientation="portrait" appearance="light"/>\n', "").replace(
    '                        <rect key="frame" x="0.0" y="0.0" width="393" height="852"/>\n', "")
for target in ("15.0", "16.0", "17.0", "27.0"):
    for devices in ("iphone", "both"):
        STORYBOARDS[f"sb-flutter-launch-{target}-{devices}"] = FLUTTER_LAUNCH
        OPTIONS[f"sb-flutter-launch-{target}-{devices}"] = {"deployment": target, "devices": ["iphone", "ipad"] if devices == "both" else ["iphone"]}
# Without useTraitCollections, as the corpus's flutter launch screens are written.
for target in ("11.0", "15.0", "27.0"):
    for variant, document in (("flutter-launch", FLUTTER_LAUNCH), ("image-view", STORYBOARDS["sb-image-view"].replace(
            '    <device id="retina6_12" orientation="portrait" appearance="light"/>\n', ""))):
        name = f"sb-no-traits-{variant}-{target}"
        STORYBOARDS[name] = document.replace(' useTraitCollections="YES"', "")
        OPTIONS[name] = {"deployment": target, "devices": ["iphone", "ipad"]}
STORYBOARDS["sb-no-traits-device"] = STORYBOARDS["sb-image-view"].replace(' useTraitCollections="YES"', "").replace("retina6_12", "retina4_7")
STORYBOARDS["sb-safe-area-layout-guides"] = storyboard(
    scene(guides=LAYOUT_GUIDES, view_extra=IMAGE_SCENE.format(rect=IMAGE_RECT, guide=SAFE_AREA, other="8bC-Xf-vdC")), resources=LAUNCH_IMAGE,
    attributes=' useSafeAreas="YES"', capabilities=SAFE_AREA_CAPABILITY)
STORYBOARDS["sb-no-rect-device"] = FLUTTER_LAUNCH.replace("    <dependencies>\n", '    <device id="retina6_12" orientation="portrait" appearance="light"/>\n    <dependencies>\n')
STORYBOARDS["sb-image-view-resized"] = STORYBOARDS["sb-image-view"].replace('    <device id="retina6_12" orientation="portrait" appearance="light"/>\n', "")
OPTIONS["sb-image-view-resized"] = {"deployment": "15.0"}


# Round 16: outlets, from File's Owner and from views, to views and placeholders: the order of the
# connections (by name, ties, case), shared names, and a storyboard controller's outlets.
def outlet(prop, destination, number):
    return f'                <outlet property="{prop}" destination="{destination}" id="o{number:02d}-aa-aaa"/>\n'


def with_outlets(owner_outlets, view_outlets="", view_class=' customClass="Root"', subviews=2):
    views = "".join(subview(f"sub-vi-ew{k}", (10, 20 + 100 * k, 100, 50)) for k in range(1, subviews + 1))
    connections = f"            <connections>\n{view_outlets}            </connections>\n" if view_outlets else ""
    text = constrained(views, "").replace(f'        <view contentMode="scaleToFill" id="{ROOT}">\n',
                                          f'        <view contentMode="scaleToFill"{view_class} id="{ROOT}">\n')
    text = text.replace('            <point key="canvasLocation"', connections + '            <point key="canvasLocation"')
    owner = ('        <placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File\'s Owner" customClass="Owner">\n'
             f'            <connections>\n{owner_outlets}            </connections>\n        </placeholder>\n')
    return text.replace('        <placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File\'s Owner"/>\n', owner if owner_outlets else
                        '        <placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File\'s Owner" customClass="Owner"/>\n')


OUTLETS = {
    "outlet-view": with_outlets(outlet("view", ROOT, 0), view_class=""),
    "outlet-two": with_outlets(outlet("zeta", "sub-vi-ew1", 0) + outlet("alpha", "sub-vi-ew2", 1), view_class=""),
    "outlet-two-ids": with_outlets(outlet("zeta", "sub-vi-ew1", 1) + outlet("alpha", "sub-vi-ew2", 0), view_class=""),
    "outlet-names": with_outlets("".join(outlet(name, "sub-vi-ew1" if k % 2 else "sub-vi-ew2", k) for k, name in
                                         enumerate(["beta", "Beta", "alpha", "_under", "a1", "A2", "a10", "a2", "view"])), view_class=""),
    "outlet-from-view": with_outlets("", outlet("titleLabel", "sub-vi-ew1", 0)),
    "outlet-from-both": with_outlets(outlet("view", ROOT, 0) + outlet("label", "sub-vi-ew1", 1), outlet("label", "sub-vi-ew2", 2) + outlet("delegate", "-1", 3)),
    "outlet-same-name-ids": with_outlets(outlet("view", ROOT, 2) + outlet("label", "sub-vi-ew1", 3), outlet("label", "sub-vi-ew2", 0) + outlet("delegate", "-1", 1)),
    "outlet-same-name-subviews": with_outlets(outlet("label", "sub-vi-ew2", 0), outlet("label", "sub-vi-ew1", 1)),
    "outlet-to-owner": with_outlets("", outlet("delegate", "-1", 0)),
    "outlet-to-first-responder": with_outlets("", outlet("responder", "-2", 0)),
    "outlet-subview-class": with_outlets("", "", view_class="").replace(
        'translatesAutoresizingMaskIntoConstraints="NO" id="sub-vi-ew1">',
        'customClass="Inner" translatesAutoresizingMaskIntoConstraints="NO" id="sub-vi-ew1">').replace(
        '                </view>\n                <view', '                    <connections>\n'
        '                        <outlet property="sibling" destination="sub-vi-ew2" id="o00-aa-aaa"/>\n'
        '                        <outlet property="owner" destination="-1" id="o01-aa-aaa"/>\n'
        '                    </connections>\n                </view>\n                <view', 1),
    "outlet-collection": with_outlets(outlet("view", ROOT, 0) + '                <outletCollection property="views" destination="sub-vi-ew1" collectionClass="NSMutableArray" id="o01-aa-aaa"/>\n'
                                      '                <outletCollection property="views" destination="sub-vi-ew2" collectionClass="NSMutableArray" id="o02-aa-aaa"/>\n', view_class=""),
    "outlet-same-name-two-views": with_outlets("", outlet("label", "sub-vi-ew2", 0)).replace(
        'translatesAutoresizingMaskIntoConstraints="NO" id="sub-vi-ew1">',
        'customClass="Inner" translatesAutoresizingMaskIntoConstraints="NO" id="sub-vi-ew1">').replace(
        '                </view>\n                <view', '                    <connections>\n'
        '                        <outlet property="label" destination="sub-vi-ew2" id="o01-aa-aaa"/>\n'
        '                    </connections>\n                </view>\n                <view', 1),
}
EXPERIMENTS.update(OUTLETS)
CONTROLLER_OUTLETS = ('                    <connections>\n'
                      '                        <outlet property="titleLabel" destination="sub-vi-ew1" id="o00-aa-aaa"/>\n'
                      '                        <outlet property="button" destination="sub-vi-ew1" id="o01-aa-aaa"/>\n'
                      '                    </connections>\n')
STORYBOARDS["sb-controller-outlets"] = storyboard(scene(attributes=' customClass="Controller" customModule="T" customModuleProvider="target"',
                                                        view_extra=SUBVIEW)).replace(
    '                    </view>\n                </viewController>', '                    </view>\n' + CONTROLLER_OUTLETS + '                </viewController>')


# Round 17: design-time settings of views and view controllers (simulated metrics, a freeform
# size) and clearsContextBeforeDrawing on views.
SIMULATED_NILS = ('            <nil key="simulatedTopBarMetrics"/>\n            <nil key="simulatedBottomBarMetrics"/>\n'
                  '            <nil key="simulatedStatusBarMetrics"/>\n')
FREEFORM = '            <freeformSimulatedSizeMetrics key="simulatedDestinationMetrics"/>\n'
EXPERIMENTS.update({
    "view-clears-no": xib(view('clearsContextBeforeDrawing="NO"')),
    "subview-clears-no": constrained(subview("sss-ss-ss1", attributes=' clearsContextBeforeDrawing="NO"'), ""),
    "view-freeform": xib(view(extra=FREEFORM)),
    "view-simulated-nils": xib(view(extra=SIMULATED_NILS)),
    "view-freeform-frame": xib(view(frame=(0, 0, 320, 100), extra=FREEFORM)),
})
SCENE_FREEFORM = ('                    <freeformSimulatedSizeMetrics key="simulatedDestinationMetrics"/>\n'
                  '                    <size key="freeformSize" width="320" height="500"/>\n')
SCENE_NILS = ('                    <nil key="simulatedTopBarMetrics"/>\n                    <nil key="simulatedBottomBarMetrics"/>\n'
              '                    <nil key="simulatedStatusBarMetrics"/>\n')
for name, extra in {"freeform": SCENE_FREEFORM, "simulated-nils": SCENE_NILS}.items():
    for variant, document in {"": storyboard(scene(view_extra=SUBVIEW)),
                              "-no-device": storyboard(scene(view_extra=SUBVIEW)).replace('    <device id="retina6_12" orientation="portrait" appearance="light"/>\n', "")}.items():
        text = document.replace('                    </view>\n                </viewController>', '                    </view>\n' + extra + '                </viewController>')
        STORYBOARDS[f"sb-{name}{variant}"] = text.replace('width="393" height="852"/>\n                        <autoresizingMask',
                                                          'width="320" height="500"/>\n                        <autoresizingMask') if name == "freeform" else text
OPTIONS["sb-freeform-no-device"] = {"deployment": "15.0"}
STORYBOARDS["sb-view-clears-no"] = storyboard(scene(view_attributes=' clearsContextBeforeDrawing="NO"'))


# Round 18: labels. Every font description of the corpus's documents (106), a sweep of sizes and
# weights, the label attributes the corpus's documents use, and text colors.
CORPUS_FONTS = [
    {"pointSize": "17", "type": "system"},
    {"pointSize": "13", "type": "system"},
    {"pointSize": "14", "type": "system"},
    {"style": "UICTFontTextStyleBody"},
    {"style": "UICTFontTextStyleHeadline"},
    {"style": "UICTFontTextStyleSubhead"},
    {"style": "UICTFontTextStyleCallout"},
    {"pointSize": "11", "type": "system"},
    {"pointSize": "20", "type": "boldSystem"},
    {"pointSize": "16", "type": "system"},
    {"pointSize": "12", "type": "system"},
    {"style": "UICTFontTextStyleFootnote"},
    {"pointSize": "15", "type": "system"},
    {"style": "UICTFontTextStyleCaption1"},
    {"style": "UICTFontTextStyleTitle2"},
    {"pointSize": "10", "type": "system"},
    {"pointSize": "36", "type": "boldSystem"},
    {"pointSize": "17", "type": "boldSystem"},
    {"pointSize": "20", "type": "system"},
    {"pointSize": "15", "type": "boldSystem"},
    {"pointSize": "18", "type": "system"},
    {"style": "UICTFontTextStyleTitle3"},
    {"pointSize": "12", "type": "boldSystem"},
    {"style": "UICTFontTextStyleTitle1"},
    {"pointSize": "18", "type": "system", "weight": "semibold"},
    {"pointSize": "18", "type": "boldSystem"},
    {"pointSize": "15", "type": "system", "weight": "medium"},
    {"pointSize": "70", "type": "system"},
    {"pointSize": "13", "type": "boldSystem"},
    {"pointSize": "22", "type": "boldSystem"},
    {"pointSize": "12", "type": "system", "weight": "semibold"},
    {"pointSize": "16", "type": "system", "weight": "medium"},
    {"pointSize": "10", "type": "boldSystem"},
    {"pointSize": "14", "type": "system", "weight": "medium"},
    {"pointSize": "11", "type": "boldSystem"},
    {"pointSize": "13", "type": "system", "weight": "semibold"},
    {"pointSize": "45", "type": "system"},
    {"pointSize": "16", "type": "boldSystem"},
    {"pointSize": "20", "type": "system", "weight": "semibold"},
    {"pointSize": "18", "type": "system", "weight": "medium"},
    {"pointSize": "23", "type": "system"},
    {"pointSize": "14", "type": "boldSystem"},
    {"family": "Futura", "name": "Futura-Medium", "pointSize": "74"},
    {"pointSize": "25", "type": "system"},
    {"pointSize": "38", "type": "system"},
    {"style": "UICTFontTextStyleCaption2"},
    {"pointSize": "35", "type": "system"},
    {"family": "Futura", "name": "Futura-Medium", "pointSize": "54"},
    {"style": "UICTFontTextStyleTitle0"},
    {"pointSize": "15", "type": "system", "weight": "semibold"},
    {"pointSize": "11", "type": "system", "weight": "semibold"},
    {"pointSize": "19", "type": "system", "weight": "semibold"},
    {"pointSize": "14", "type": "system", "weight": "semibold"},
    {"family": ".AppleSystemUIFont", "name": ".AppleSystemUIFont", "pointSize": "14"},
    {"pointSize": "30", "type": "system"},
    {"pointSize": "16", "type": "italicSystem"},
    {"pointSize": "24", "type": "system"},
    {"pointSize": "17", "type": "system", "weight": "semibold"},
    {"pointSize": "13", "type": "system", "weight": "medium"},
    {"pointSize": "19", "type": "boldSystem"},
    {"family": "DIN Alternate", "name": "DINAlternate-Bold", "pointSize": "17"},
    {"pointSize": "38", "type": "system", "weight": "light"},
    {"family": "Courier", "name": "Courier", "pointSize": "12"},
    {"family": "Helvetica Neue", "name": "HelveticaNeue", "pointSize": "700"},
    {"family": ".AppleSystemUIFont", "name": ".AppleSystemUIFont", "pointSize": "13"},
    {"pointSize": "17", "type": "system", "weight": "medium"},
    {"family": "Helvetica Neue", "name": "HelveticaNeue", "pointSize": "14"},
    {"size": "button", "type": "boldSystem"},
    {"family": "Courier New", "name": "CourierNewPS-BoldMT", "pointSize": "30"},
    {"family": "Avenir Next", "name": "AvenirNext-Regular", "pointSize": "18"},
    {"family": "Avenir Next", "name": "AvenirNext-Regular", "pointSize": "16"},
    {"family": "Avenir Next", "name": "AvenirNext-Regular", "pointSize": "20"},
    {"pointSize": "15", "type": "italicSystem"},
    {"pointSize": "23", "type": "boldSystem"},
    {"family": "Futura", "name": "Futura-CondensedMedium", "pointSize": "54"},
    {"pointSize": "33", "type": "boldSystem"},
    {"pointSize": "11", "type": "system", "weight": "medium"},
    {"style": "UICTFontTextStyleSubheadline"},
    {"pointSize": "12", "type": "system", "weight": "medium"},
    {"pointSize": "33", "type": "system"},
    {"family": "Helvetica Neue", "name": "HelveticaNeue", "pointSize": "15"},
    {"pointSize": "44", "type": "system", "weight": "thin"},
    {"pointSize": "36", "type": "system", "weight": "ultraLight"},
    {"pointSize": "28", "type": "system"},
    {"family": "Georgia", "name": "Georgia", "pointSize": "17"},
    {"pointSize": "24", "type": "system", "weight": "medium"},
    {"pointSize": "42", "type": "system"},
    {"family": "Helvetica Neue", "name": "HelveticaNeue-Bold", "pointSize": "13"},
    {"pointSize": "24", "type": "boldSystem"},
    {"family": "Arial Rounded MT Bold", "name": "ArialRoundedMTBold", "pointSize": "96"},
    {"pointSize": "33", "type": "system", "weight": "heavy"},
    {"pointSize": "31", "type": "system", "weight": "heavy"},
    {"family": ".AppleSystemUIFont", "name": ".SFNS-Regular", "pointSize": "16"},
    {"family": "Futura", "name": "Futura-Medium", "pointSize": "34"},
    {"family": "Futura", "name": "Futura-Medium", "pointSize": "18"},
    {"family": "Avenir Next", "name": "AvenirNext-DemiBold", "pointSize": "11"},
    {"pointSize": "16", "type": "system", "weight": "semibold"},
    {"pointSize": "22", "type": "system", "weight": "medium"},
    {"pointSize": "60", "type": "system", "weight": "light"},
    {"pointSize": "36", "type": "system"},
    {"family": "Courier", "name": "Courier-Bold", "pointSize": "17"},
    {"family": "Helvetica Neue", "name": "HelveticaNeue-UltraLight", "pointSize": "50"},
    {"family": "Gill Sans", "name": "GillSans-Bold", "pointSize": "112"},
    {"pointSize": "31", "type": "system"},
    {"pointSize": "40", "type": "system", "weight": "heavy"},
    {"pointSize": "6", "type": "system"}
]


def font_description(attributes):
    return "<fontDescription key=\"fontDescription\" " + " ".join(f'{key}="{value}"' for key, value in sorted(attributes.items())) + "/>"


LABEL_ATTRIBUTES = ('opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" '
                    'text="Label" textAlignment="natural" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" '
                    'adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO"')
SYSTEM_17 = font_description({"type": "system", "pointSize": "17"})


def label(attributes=LABEL_ATTRIBUTES, font=SYSTEM_17, colors='<nil key="textColor"/>\n<nil key="highlightedColor"/>\n', extra="",
          identifier="lll-ll-ll1", frame=(20, 40, 42, 21)):
    x, y, w, h = frame
    return (f'                <label {attributes} id="{identifier}">\n'
            f'                    <rect key="frame" x="{x}" y="{y}" width="{w}" height="{h}"/>\n'
            f'                    {font}\n{colors}{extra}                </label>\n')


LABELS = {f"label-font-{index:03d}": constrained(label(font=font_description(font)), "") for index, font in enumerate(CORPUS_FONTS)}
for size in (8, 10, 17, 19, 20, 21, 28, 34, 48, 72):
    for kind, attributes in {"system": {"type": "system"}, "bold": {"type": "boldSystem"}, "semibold": {"type": "system", "weight": "semibold"},
                             "light": {"type": "system", "weight": "light"}}.items():
        LABELS[f"label-size-{kind}-{size}"] = constrained(label(font=font_description({**attributes, "pointSize": str(size)})), "")
for weight in ("ultraLight", "thin", "light", "regular", "medium", "semibold", "bold", "heavy", "black"):
    LABELS[f"label-weight-{weight}"] = constrained(label(font=font_description({"type": "system", "weight": weight, "pointSize": "17"})), "")
for style in ("UICTFontTextStyleBody", "UICTFontTextStyleHeadline", "UICTFontTextStyleCaption2", "UICTFontTextStyleTitle0"):
    LABELS[f"label-style-{style[17:]}-adjusts"] = constrained(label(LABEL_ATTRIBUTES + ' adjustsFontForContentSizeCategory="YES"',
                                                                   font=font_description({"style": style})), "")
LABEL_VARIANTS = {
    "plain": LABEL_ATTRIBUTES, "minimal": 'text="Label"', "no-text": LABEL_ATTRIBUTES.replace('text="Label" ', ""),
    "empty-text": LABEL_ATTRIBUTES.replace('text="Label"', 'text=""'), "unicode-text": LABEL_ATTRIBUTES.replace('text="Label"', 'text="Café ☕️ &amp; &lt;b&gt;"'),
    "center": LABEL_ATTRIBUTES.replace('textAlignment="natural"', 'textAlignment="center"'),
    "right": LABEL_ATTRIBUTES.replace('textAlignment="natural"', 'textAlignment="right"'),
    "left": LABEL_ATTRIBUTES.replace('textAlignment="natural"', 'textAlignment="left"'),
    "justified": LABEL_ATTRIBUTES.replace('textAlignment="natural"', 'textAlignment="justified"'),
    "no-alignment": LABEL_ATTRIBUTES.replace(' textAlignment="natural"', ""),
    "word-wrap": LABEL_ATTRIBUTES.replace('tailTruncation', 'wordWrap'), "middle": LABEL_ATTRIBUTES.replace('tailTruncation', 'middleTruncation'),
    "head": LABEL_ATTRIBUTES.replace('tailTruncation', 'headTruncation'), "character-wrap": LABEL_ATTRIBUTES.replace('tailTruncation', 'characterWrap'),
    "clip": LABEL_ATTRIBUTES.replace('tailTruncation', 'clip'),
    "lines-0": LABEL_ATTRIBUTES + ' numberOfLines="0"', "lines-2": LABEL_ATTRIBUTES + ' numberOfLines="2"',
    "adjusts-size": LABEL_ATTRIBUTES.replace('adjustsFontSizeToFit="NO"', 'minimumScaleFactor="0.5"'),
    "adjusts-size-yes": LABEL_ATTRIBUTES.replace('adjustsFontSizeToFit="NO"', 'adjustsFontSizeToFit="YES" minimumScaleFactor="0.5"'),
    "no-adjusts": LABEL_ATTRIBUTES.replace(' adjustsFontSizeToFit="NO"', ""),
    "letter-spacing": LABEL_ATTRIBUTES + ' adjustsLetterSpacingToFitWidth="YES"',
    "baseline-centers": LABEL_ATTRIBUTES.replace('alignBaselines', 'alignCenters'), "baseline-none": LABEL_ATTRIBUTES.replace('alignBaselines', 'none'),
    "no-baseline": LABEL_ATTRIBUTES.replace(' baselineAdjustment="alignBaselines"', ""),
    "hidden": LABEL_ATTRIBUTES + ' hidden="YES"', "disabled": LABEL_ATTRIBUTES + ' enabled="NO"', "highlighted": LABEL_ATTRIBUTES + ' highlighted="YES"',
    "preferred-width": LABEL_ATTRIBUTES + ' preferredMaxLayoutWidth="200"',
    "compression-1000": LABEL_ATTRIBUTES + ' horizontalCompressionResistancePriority="1000" verticalCompressionResistancePriority="1000"',
    "compression-751": LABEL_ATTRIBUTES + ' horizontalCompressionResistancePriority="751"',
    "compression-vertical-749": LABEL_ATTRIBUTES + ' verticalCompressionResistancePriority="749"',
    "hugging-1000": LABEL_ATTRIBUTES.replace('horizontalHuggingPriority="251" verticalHuggingPriority="251"', 'horizontalHuggingPriority="1000" verticalHuggingPriority="1000"'),
    "no-hugging": LABEL_ATTRIBUTES.replace(' horizontalHuggingPriority="251" verticalHuggingPriority="251"', ""),
    "fixed-frame": LABEL_ATTRIBUTES + ' fixedFrame="YES"', "ambiguous": LABEL_ATTRIBUTES + ' ambiguous="YES"',
    "insets-safe-area-no": LABEL_ATTRIBUTES + ' insetsLayoutMarginsFromSafeArea="NO"',
    "placeholder-height": LABEL_ATTRIBUTES + ' placeholderIntrinsicWidth="42" placeholderIntrinsicHeight="20.5"',
    "multitouch": LABEL_ATTRIBUTES + ' multipleTouchEnabled="YES"', "clips": LABEL_ATTRIBUTES + ' clipsSubviews="YES"', "tag": LABEL_ATTRIBUTES + ' tag="101"',
    "translates": LABEL_ATTRIBUTES.replace(' translatesAutoresizingMaskIntoConstraints="NO"', ""),
    "user-label": LABEL_ATTRIBUTES + ' userLabel="Title"',
}
LABELS.update({f"label-{name}": constrained(label(attributes), "") for name, attributes in LABEL_VARIANTS.items()})
LABEL_COLORS = {
    "text-rgb": '<color key="textColor" red="0.2" green="0.4" blue="0.6" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>\n<nil key="highlightedColor"/>\n',
    "text-gray": '<color key="textColor" white="0.5" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>\n<nil key="highlightedColor"/>\n',
    "text-system": '<color key="textColor" systemColor="secondaryLabelColor"/>\n<nil key="highlightedColor"/>\n',
    "text-cw": '<color key="textColor" white="0.33333333333333331" alpha="1" colorSpace="calibratedWhite"/>\n<nil key="highlightedColor"/>\n',
    "highlighted-system": '<nil key="textColor"/>\n<color key="highlightedColor" systemColor="systemRedColor"/>\n',
    "no-colors": "", "background": '<nil key="textColor"/>\n<nil key="highlightedColor"/>\n'
                  '<color key="backgroundColor" white="1" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>\n',
}
SYSTEM_RESOURCES = {"text-system": system_color("secondaryLabelColor", gray(0, 1)), "highlighted-system": system_color("systemRedColor", gray(0, 1))}
for name, colors in LABEL_COLORS.items():
    LABELS[f"label-{name}"] = constrained(label(colors=colors), "", resources=SYSTEM_RESOURCES.get(name, ""))
LABELS["label-two"] = constrained(label() + label(identifier="lll-ll-ll2", frame=(20, 80, 42, 21)), "")
LABELS["label-text-child"] = constrained(label(LABEL_ATTRIBUTES.replace('text="Label" ', ""), extra='                    <string key="text">Two\nlines</string>\n'), "")
LABELS["label-constrained"] = constrained(label(), constraint(0, "lll-ll-ll1", "centerX", ROOT, "centerX") + constraint(1, "lll-ll-ll1", "centerY", ROOT, "centerY"))
LABELS["label-two-sizes"] = constrained(label() + label(font=font_description({"type": "system", "pointSize": "14"}), identifier="lll-ll-ll2",
                                                     frame=(20, 80, 42, 21)), "")
LABELS["label-two-texts"] = constrained(label() + label(LABEL_ATTRIBUTES.replace('text="Label"', 'text="Other"'), identifier="lll-ll-ll2",
                                                        frame=(20, 80, 42, 21)), "")
LABELS["label-all-options"] = constrained(label(
    LABEL_ATTRIBUTES.replace('textAlignment="natural"', 'textAlignment="center"').replace('tailTruncation', 'wordWrap')
    .replace('alignBaselines', 'alignCenters').replace('adjustsFontSizeToFit="NO"', 'adjustsFontSizeToFit="YES" minimumScaleFactor="0.5"')
    + ' hidden="YES" tag="7" alpha="0.5" clipsSubviews="YES" numberOfLines="2" enabled="NO" adjustsLetterSpacingToFitWidth="YES"'
      ' preferredMaxLayoutWidth="200" horizontalCompressionResistancePriority="751" insetsLayoutMarginsFromSafeArea="NO"'
      ' adjustsFontForContentSizeCategory="YES"', font=font_description({"style": "UICTFontTextStyleBody"}),
    colors='<color key="textColor" red="0.2" green="0.4" blue="0.6" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>\n'
           '<color key="highlightedColor" white="0.5" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>\n'
           '<color key="backgroundColor" white="1" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>\n'),
    constraint(0, "lll-ll-ll1", "centerX", ROOT, "centerX"))
LABELS["label-all-options-2"] = constrained(label(
    LABEL_ATTRIBUTES.replace('alignBaselines', 'none').replace('adjustsFontSizeToFit="NO"', 'adjustsFontSizeToFit="YES" minimumScaleFactor="0.25"')
    + ' numberOfLines="0" verticalCompressionResistancePriority="749" insetsLayoutMarginsFromSafeArea="NO" enabled="NO" preferredMaxLayoutWidth="120"'),
    "")
LABELS["label-minimum-font-size"] = constrained(label(LABEL_ATTRIBUTES.replace('adjustsFontSizeToFit="NO"', 'minimumFontSize="10"')), "")
# Which equal strings are one object: label texts equal to an outlet name, an image name and a class
# name, and equal hugging and compression resistance priorities.
LABELS["strings-shared"] = with_outlets(outlet("view", "lll-ll-ll1", 0), view_class=' customClass="Root"').replace(
    '            <subviews>\n', '            <subviews>\n'
    + label(LABEL_ATTRIBUTES.replace('text="Label"', 'text="view"') + ' horizontalCompressionResistancePriority="251" verticalCompressionResistancePriority="251"')
    + label(LABEL_ATTRIBUTES.replace('text="Label"', 'text="Logo"'), identifier="lll-ll-ll2", frame=(20, 80, 42, 21))
    + label(LABEL_ATTRIBUTES.replace('text="Label"', 'text="Root"'), identifier="lll-ll-ll3", frame=(20, 120, 42, 21))
    + subview("iii-ii-ii1", (112, 333, 168, 185), "imageView", ' image="Logo"'), 1).replace(
    "    </objects>\n", "    </objects>\n    <resources>\n" + LOGO + "    </resources>\n")
EXPERIMENTS.update(LABELS)


# Round 19: localizable texts and size-class variations. A label in a storyboard and in a xib of
# Base.lproj; variations of a label's font, of a constraint's constant, and of which subviews and
# constraints a size class includes, in xibs and storyboards.
LPROJ_XIBS = {"label-lproj", "variation-font-lproj"}
# Storyboards compiled from Base.lproj, as the corpus's localized storyboards are.
LPROJ_STORYBOARDS = set()
REGULAR = "heightClass=regular-widthClass=regular"
COMPACT = "heightClass=regular-widthClass=compact"
FONT_VARIATIONS = (f'                    <variation key="{COMPACT}">\n                        {font_description({"type": "system", "pointSize": "16"})}\n'
                   f'                    </variation>\n                    <variation key="{REGULAR}">\n'
                   f'                        {font_description({"type": "system", "pointSize": "20"})}\n                    </variation>\n')
ONE_FONT_VARIATION = (f'                    <variation key="{REGULAR}">\n                        {font_description({"type": "system", "pointSize": "20"})}\n'
                      '                    </variation>\n')
CONSTANT_VARIATION = (f'                <constraint firstItem="lll-ll-ll1" firstAttribute="top" secondItem="{ROOT}" secondAttribute="top" constant="120" id="c00-aa-aaa">\n'
                      f'                    <variation key="{REGULAR}" constant="250"/>\n                </constraint>\n')
MASKS = (f'            <variation key="default">\n                <mask key="subviews">\n                    <exclude reference="lll-ll-ll1"/>\n'
         '                </mask>\n                <mask key="constraints">\n                    <exclude reference="c00-aa-aaa"/>\n                </mask>\n'
         f'            </variation>\n            <variation key="{COMPACT}">\n                <mask key="subviews">\n                    <include reference="lll-ll-ll1"/>\n'
         '                </mask>\n                <mask key="constraints">\n                    <include reference="c00-aa-aaa"/>\n                </mask>\n            </variation>\n')
VARIATIONS = {
    "label-lproj": constrained(label(), ""),
    "variation-font": constrained(label(extra=FONT_VARIATIONS), ""),
    "variation-font-one": constrained(label(extra=ONE_FONT_VARIATION), ""),
    "variation-font-lproj": constrained(label(extra=FONT_VARIATIONS), ""),
    "variation-constant": constrained(label(), CONSTANT_VARIATION),
    "variation-masks": constrained(label(), constraint(0, "lll-ll-ll1", "top", ROOT, "top")).replace(
        '            <point key="canvasLocation"', MASKS + '            <point key="canvasLocation"'),
    "variation-font-and-constant": constrained(label(extra=FONT_VARIATIONS), CONSTANT_VARIATION),
}
EXPERIMENTS.update(VARIATIONS)
SB_LABEL = ('                        <subviews>\n' + label().replace('                ', '                            ', 1) + '                        </subviews>\n')
STORYBOARDS["sb-label"] = storyboard(scene(view_extra=SB_LABEL))
STORYBOARDS["sb-label-two"] = storyboard(scene(view_extra=SB_LABEL.replace('</subviews>', label(identifier="lll-ll-ll2", frame=(20, 80, 42, 21)) + '                        </subviews>')))
STORYBOARDS["sb-variation-font"] = storyboard(scene(view_extra=SB_LABEL.replace('<nil key="highlightedColor"/>\n', '<nil key="highlightedColor"/>\n' + FONT_VARIATIONS)))
STORYBOARDS["sb-variation-constant"] = storyboard(scene(view_extra=SB_LABEL + '                        <constraints>\n'
    + CONSTANT_VARIATION.replace(ROOT, "8bC-Xf-vdC") + '                        </constraints>\n'))


# Round 20: launch screens as React Native's and Expo's app templates write them (labels without a
# text color, a constraint to a third of the view's bottom, `symbolic`; an image view centered on its
# view, `true`/`false` booleans, a named color with `alpha="1.000"`, IDs of any shape), at the
# deployment targets they use and every other iOS release's, then one change at a time.
LAUNCH_RN = """<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="15702" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" launchScreen="YES" useTraitCollections="YES" useSafeAreas="YES" colorMatched="YES" initialViewController="Lc1-aa-aaa">
    <device id="retina4_7" orientation="portrait" appearance="light"/>
    <dependencies>
        <deployment identifier="iOS"/>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="15704"/>
        <capability name="Safe area layout guides" minToolsVersion="9.0"/>
        <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
    </dependencies>
    <scenes>
        <!--View Controller-->
        <scene sceneID="Ls1-aa-aaa">
            <objects>
                <viewController id="Lc1-aa-aaa" sceneMemberID="viewController">
                    <view key="view" contentMode="scaleToFill" id="Lv1-aa-aaa">
                        <rect key="frame" x="0.0" y="0.0" width="375" height="667"/>
                        <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
                        <subviews>
                            <label opaque="NO" clipsSubviews="YES" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" text="Sample" textAlignment="center" lineBreakMode="middleTruncation" baselineAdjustment="alignBaselines" minimumFontSize="18" translatesAutoresizingMaskIntoConstraints="NO" id="Ll1-aa-aaa">
                                <rect key="frame" x="0.0" y="202" width="375" height="43"/>
                                <fontDescription key="fontDescription" type="boldSystem" pointSize="36"/>
                                <nil key="highlightedColor"/>
                            </label>
                            <label opaque="NO" clipsSubviews="YES" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" text="Made with a template" textAlignment="center" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" minimumFontSize="9" translatesAutoresizingMaskIntoConstraints="NO" id="Ll2-aa-aaa">
                                <rect key="frame" x="0.0" y="626" width="375" height="21"/>
                                <fontDescription key="fontDescription" type="system" pointSize="17"/>
                                <nil key="highlightedColor"/>
                            </label>
                        </subviews>
                        <color key="backgroundColor" systemColor="systemBackgroundColor" cocoaTouchSystemColor="whiteColor"/>
                        <constraints>
                            <constraint firstItem="Lg1-aa-aaa" firstAttribute="bottom" secondItem="Ll2-aa-aaa" secondAttribute="bottom" constant="20" id="Lk1-aa-aaa"/>
                            <constraint firstItem="Lg1-aa-aaa" firstAttribute="centerX" secondItem="Ll1-aa-aaa" secondAttribute="centerX" id="Lk2-aa-aaa"/>
                            <constraint firstItem="Ll2-aa-aaa" firstAttribute="centerX" secondItem="Lg1-aa-aaa" secondAttribute="centerX" id="Lk3-aa-aaa"/>
                            <constraint firstItem="Ll2-aa-aaa" firstAttribute="leading" secondItem="Lg1-aa-aaa" secondAttribute="leading" id="Lk4-aa-aaa"/>
                            <constraint firstItem="Ll1-aa-aaa" firstAttribute="centerY" secondItem="Lv1-aa-aaa" secondAttribute="bottom" multiplier="1/3" constant="1" id="Lk5-aa-aaa"/>
                            <constraint firstItem="Ll1-aa-aaa" firstAttribute="leading" secondItem="Lg1-aa-aaa" secondAttribute="leading" symbolic="YES" id="Lk6-aa-aaa"/>
                        </constraints>
                        <viewLayoutGuide key="safeArea" id="Lg1-aa-aaa"/>
                    </view>
                </viewController>
                <placeholder placeholderIdentifier="IBFirstResponder" id="Lr1-aa-aaa" userLabel="First Responder" sceneMemberID="firstResponder"/>
            </objects>
            <point key="canvasLocation" x="52.173913043478265" y="375"/>
        </scene>
    </scenes>
</document>
"""
LAUNCH_EXPO = """<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="24093.7" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" launchScreen="YES" useTraitCollections="YES" useSafeAreas="YES" colorMatched="YES" initialViewController="SAMPLE-CONTROLLER-1">
    <device id="retina6_12" orientation="portrait" appearance="light"/>
    <dependencies>
        <deployment identifier="iOS"/>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="24053.1"/>
        <capability name="Named colors" minToolsVersion="9.0"/>
        <capability name="Safe area layout guides" minToolsVersion="9.0"/>
        <capability name="System colors in document resources" minToolsVersion="11.0"/>
        <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
    </dependencies>
    <scenes>
        <scene sceneID="SAMPLE-SCENE-1">
            <objects>
                <viewController storyboardIdentifier="LaunchController" id="SAMPLE-CONTROLLER-1" sceneMemberID="viewController">
                    <view key="view" userInteractionEnabled="NO" contentMode="scaleToFill" insetsLayoutMarginsFromSafeArea="NO" id="SAMPLE-Container" userLabel="Container">
                        <rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
                        <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
                        <subviews>
                            <imageView id="SAMPLE-Logo" userLabel="Logo" image="LaunchLogo" contentMode="scaleAspectFit" clipsSubviews="true" userInteractionEnabled="false" translatesAutoresizingMaskIntoConstraints="false">
                                <rect key="frame" x="158.5" y="388" width="76" height="76"/>
                            </imageView>
                        </subviews>
                        <viewLayoutGuide key="safeArea" id="Sg1-aa-aaa"/>
                        <constraints>
                            <constraint firstItem="SAMPLE-Logo" firstAttribute="centerX" secondItem="SAMPLE-Container" secondAttribute="centerX" id="0f3a9c1d2b4e5f60718293a4b5c6d7e8f9012345"/>
                            <constraint firstItem="SAMPLE-Logo" firstAttribute="centerY" secondItem="SAMPLE-Container" secondAttribute="centerY" id="9e8d7c6b5a4f3e2d1c0b9a8f7e6d5c4b3a291807"/>
                        </constraints>
                        <color key="backgroundColor" name="LaunchBackground"/>
                    </view>
                </viewController>
                <placeholder placeholderIdentifier="IBFirstResponder" id="SAMPLE-PLACEHOLDER-1" userLabel="First Responder" sceneMemberID="firstResponder"/>
            </objects>
            <point key="canvasLocation" x="0.0" y="0.0"/>
        </scene>
    </scenes>
    <resources>
        <image name="LaunchLogo" width="76" height="76"/>
        <systemColor name="systemBackgroundColor">
            <color white="1" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>
        </systemColor>
        <namedColor name="LaunchBackground">
            <color alpha="1.000" blue="0.937254901960784" green="0.541176470588235" red="0.125490196078431" customColorSpace="sRGB" colorSpace="custom"/>
        </namedColor>
    </resources>
</document>
"""
LAUNCH_RN_CONSTRAINTS = LAUNCH_RN[LAUNCH_RN.index("                        <constraints>\n"):LAUNCH_RN.index("                        <viewLayoutGuide")]
EXPO_LOGO_ATTRIBUTES = 'clipsSubviews="true" userInteractionEnabled="false" translatesAutoresizingMaskIntoConstraints="false"'
LAUNCHES = {
    "sb-launch-rn": LAUNCH_RN,
    "sb-launch-rn-labels": LAUNCH_RN.replace(LAUNCH_RN_CONSTRAINTS, ""),
    "sb-launch-rn-no-multiplier": LAUNCH_RN.replace(' multiplier="1/3" constant="1"', ''),
    "sb-launch-rn-no-symbolic": LAUNCH_RN.replace(' symbolic="YES"', ''),
    "sb-launch-rn-text-colors": LAUNCH_RN.replace('<nil key="highlightedColor"/>', '<nil key="textColor"/>\n<nil key="highlightedColor"/>'),
    "sb-launch-rn-no-device": LAUNCH_RN.replace('    <device id="retina4_7" orientation="portrait" appearance="light"/>\n', ''),
    "sb-launch-expo": LAUNCH_EXPO,
    "sb-launch-expo-yes-no": LAUNCH_EXPO.replace(EXPO_LOGO_ATTRIBUTES, 'clipsSubviews="YES" userInteractionEnabled="NO" translatesAutoresizingMaskIntoConstraints="NO"'),
    "sb-launch-expo-no-user-labels": LAUNCH_EXPO.replace(' userLabel="Container"', '').replace(' userLabel="Logo"', ''),
    "sb-launch-expo-alpha-1": LAUNCH_EXPO.replace('alpha="1.000"', 'alpha="1"'),
    "sb-launch-expo-short-ids": LAUNCH_EXPO.replace("0f3a9c1d2b4e5f60718293a4b5c6d7e8f9012345", "Sk1-aa-aaa")
    .replace("9e8d7c6b5a4f3e2d1c0b9a8f7e6d5c4b3a291807", "Sk2-aa-aaa"),
    "sb-launch-expo-no-device": LAUNCH_EXPO.replace('    <device id="retina6_12" orientation="portrait" appearance="light"/>\n', ''),
}
STORYBOARDS.update(LAUNCHES)
OPTIONS.update({name: {"deployment": "15.1", "devices": ["iphone", "ipad"]} for name in LAUNCHES if name.startswith("sb-launch-rn")})
OPTIONS.update({name: {"deployment": "16.4"} for name in LAUNCHES if name.startswith("sb-launch-expo")})
STORYBOARDS.update({"sb-launch-rn-27.0": LAUNCH_RN, "sb-launch-expo-27.0": LAUNCH_EXPO})
# Every iOS release's deployment target from 8.0 that `deployment-*` did not try, for a xib and for
# the two launch screens (the RN one on both devices), and for a storyboard without a device.
RELEASES = {8: 4, 9: 3, 10: 3, 11: 4, 12: 5, 13: 7, 14: 8, 15: 8, 16: 7, 17: 7, 18: 7, 26: 2}
MORE_TARGETS = [f"{major}.{minor}" for major, last in RELEASES.items() for minor in range(last + 1)
                if f"{major}.{minor}" not in DEPLOYMENT_TARGETS]
EXPERIMENTS.update({f"deployment-{target}": BASE for target in MORE_TARGETS})
OPTIONS.update({f"deployment-{target}": {"deployment": target} for target in MORE_TARGETS})
for target in DEPLOYMENT_TARGETS[1:] + MORE_TARGETS:
    STORYBOARDS[f"sb-launch-rn-at-{target}"] = LAUNCH_RN
    STORYBOARDS[f"sb-launch-expo-at-{target}"] = LAUNCH_EXPO
    OPTIONS[f"sb-launch-rn-at-{target}"] = {"deployment": target, "devices": ["iphone", "ipad"]}
    OPTIONS[f"sb-launch-expo-at-{target}"] = {"deployment": target}
for target in MORE_TARGETS:
    STORYBOARDS[f"sb-deployment-{target}-no-device"] = STORYBOARDS["sb-targets-iphone-no-device"]
    OPTIONS[f"sb-deployment-{target}-no-device"] = {"deployment": target}
# Labels without a text color or a highlighted color element, and booleans written true/false.
LABELS_ABSENT = {"label-text-absent": '<nil key="highlightedColor"/>\n', "label-highlighted-absent": '<nil key="textColor"/>\n'}
EXPERIMENTS.update({name: constrained(label(colors=colors), "") for name, colors in LABELS_ABSENT.items()})
EXPERIMENTS["label-text-absent-minimum-font-size"] = constrained(label(
    LABEL_ATTRIBUTES.replace('adjustsFontSizeToFit="NO"', 'minimumFontSize="9"'), colors='<nil key="highlightedColor"/>\n'), "")
EXPERIMENTS["label-text-absent-middle"] = constrained(label(
    LABEL_ATTRIBUTES.replace('tailTruncation', 'middleTruncation').replace('textAlignment="natural"', 'textAlignment="center"')
    .replace('adjustsFontSizeToFit="NO"', 'minimumFontSize="18" clipsSubviews="YES"'), font=font_description({"type": "boldSystem", "pointSize": "36"}),
    colors='<nil key="highlightedColor"/>\n'), "")
BOOLEANS = {"hidden": ("true", "false", "yes", "no", "1", "0"), "clipsSubviews": ("true", "false"), "userInteractionEnabled": ("true", "false"),
            "opaque": ("true", "false"), "multipleTouchEnabled": ("true", "false")}
EXPERIMENTS.update({f"bool-{name}-{value}": xib(view(f'{name}="{value}"')) for name, values in BOOLEANS.items() for value in values})
EXPERIMENTS.update({f"bool-translates-{value}": constrained(subview("sss-ss-ss1").replace('translatesAutoresizingMaskIntoConstraints="NO"',
                                                                                         f'translatesAutoresizingMaskIntoConstraints="{value}"'),
                                                            constraint(0, "sss-ss-ss1", "top", ROOT, "top")) for value in ("false", "no")})
EXPERIMENTS.update({f"alpha-{text}": xib(view(f'alpha="{text}"')) for text in ("1.000", "0.500", "1.0", ".5")})
EXPERIMENTS["named-color-alpha-1.000"] = colored('<color key="backgroundColor" name="Brand"/>').replace(
    "    </objects>\n", '    </objects>\n    <resources>\n        <namedColor name="Brand">\n'
    '            <color alpha="1.000" blue="0.937254901960784" green="0.541176470588235" red="0.125490196078431" customColorSpace="sRGB" colorSpace="custom"/>\n'
    '        </namedColor>\n    </resources>\n').replace('        <capability name="documents saved',
                                                          '        <capability name="Named colors" minToolsVersion="9.0"/>\n        <capability name="documents saved')
EXPERIMENTS["constraint-third-of-bottom"] = constrained(subview("sss-ss-ss1"), constraint(0, "sss-ss-ss1", "centerY", ROOT, "bottom", ' multiplier="1/3" constant="1"'))
EXPERIMENTS["color-system-and-cocoa-touch"] = colored('<color key="backgroundColor" systemColor="systemBackgroundColor" cocoaTouchSystemColor="whiteColor"/>')
EXPERIMENTS["color-system-and-cocoa-touch-resource"] = colored('<color key="backgroundColor" systemColor="systemBackgroundColor" cocoaTouchSystemColor="whiteColor"/>',
                                                               system_color("systemBackgroundColor", gray(1, 1)))
EXPERIMENTS.update({f"constraint-multiplier-{name}": constrained(subview("sss-ss-ss1"), constraint(0, "sss-ss-ss1", "centerY", ROOT, "bottom", f' multiplier="{text}"'))
                    for name, text in {"1:3": "1:3", "16:9": "16:9", "16-slash-9": "16/9", "third-decimal": "0.33333333333333331", "0.3": "0.3"}.items()})
EXPERIMENTS["constraint-symbolic"] = constrained(subview("sss-ss-ss1"), constraint(0, "sss-ss-ss1", "leading", ROOT, "leading", ' symbolic="YES"'))



# Round 21: the launch screens Expo's splash-screen config plugin writes (expo-splash-screen 58):
# `resizeMode` contain or cover, `imageWidth` (the image centered on the view), the legacy full-screen
# image pinned to the view's edges, and background colors, each component k/255 written with 15
# significant digits (`toPrecision(15)`): every k, three per document, as named colors of a xib.
def expo_splash(width=76, mode="scaleAspectFit", full=False, color=("0.125490196078431", "0.541176470588235", "0.937254901960784")):
    image_width, image_height = (414, 736) if full else (width, width)
    x, y = (0, 0) if full else ((393 - width) / 2, (852 - width) / 2)
    number = lambda value: f"{value:g}" if value != int(value) else str(int(value))
    document = LAUNCH_EXPO.replace('contentMode="scaleAspectFit"', f'contentMode="{mode}"').replace(
        '<rect key="frame" x="158.5" y="388" width="76" height="76"/>',
        f'<rect key="frame" x="{number(x)}" y="{number(y)}" width="{image_width}" height="{image_height}"/>').replace(
        '<image name="LaunchLogo" width="76" height="76"/>', f'<image name="LaunchLogo" width="{image_width}" height="{image_height}"/>').replace(
        'blue="0.937254901960784" green="0.541176470588235" red="0.125490196078431"', f'blue="{color[2]}" green="{color[1]}" red="{color[0]}"')
    if full:
        edges = "".join(f'                            <constraint firstItem="SAMPLE-Logo" firstAttribute="{edge}" secondItem="SAMPLE-Container" '
                        f'secondAttribute="{edge}" id="{index:040x}"/>\n' for index, edge in enumerate(["top", "leading", "trailing", "bottom"]))
        start = document.index("                            <constraint ")
        end = document.index("                        </constraints>")
        document = document[:start] + edges + document[end:]
    return document


def precision15(k):
    return f"{k / 255:.15g}" if k % 255 else f"{k // 255}.{'0' * 14}"


EXPO_SPLASHES = {
    "sb-expo-cover": expo_splash(mode="scaleAspectFill"),
    "sb-expo-full-screen": expo_splash(full=True),
    "sb-expo-full-screen-cover": expo_splash(full=True, mode="scaleAspectFill"),
    **{f"sb-expo-width-{width}": expo_splash(width) for width in (100, 150, 200, 201, 288)},
    "sb-expo-width-200-cover": expo_splash(200, "scaleAspectFill"),
    **{f"sb-expo-color-{name}": expo_splash(200, color=tuple(precision15(int(name[i:i + 2], 16)) for i in (0, 2, 4)))
       for name in ("ffffff", "000000", "232323", "25292e", "e6f4fe", "808080")},
}
STORYBOARDS.update(EXPO_SPLASHES)
OPTIONS.update({name: {"deployment": "15.1"} for name in EXPO_SPLASHES})
for first in range(0, 256, 3):
    red, green, blue = (precision15(min(first + offset, 255)) for offset in range(3))
    EXPERIMENTS[f"named-color-255-{first:03d}"] = colored('<color key="backgroundColor" name="Brand"/>').replace(
        "    </objects>\n", '    </objects>\n    <resources>\n        <namedColor name="Brand">\n'
        f'            <color alpha="1.000" blue="{blue}" green="{green}" red="{red}" customColorSpace="sRGB" colorSpace="custom"/>\n'
        '        </namedColor>\n    </resources>\n').replace('        <capability name="documents saved',
                                                              '        <capability name="Named colors" minToolsVersion="9.0"/>\n        <capability name="documents saved')


# Round 22: the order of size-class variations (docs/formats/nib.md "Variations"): the records of a
# label's font by their keys and their document order, the traits storages and descendants of two or
# three labels by id, frame and document order, constraints' constants, and labels with constraints.
def font_variations(*keys, sizes=None):
    sizes = sizes or [16 + index for index in range(len(keys))]
    return "".join(f'                    <variation key="{key}">\n                        {font_description({"type": "system", "pointSize": str(size)})}\n'
                   '                    </variation>\n' for key, size in zip(keys, sizes))


def constant_variation(number, item, attribute, constant, varied, keys=(REGULAR,)):
    variations = "".join(f'                    <variation key="{key}" constant="{varied + index}"/>\n' for index, key in enumerate(keys))
    return (f'                <constraint firstItem="{item}" firstAttribute="{attribute}" secondItem="{ROOT}" secondAttribute="{attribute}" '
            f'constant="{constant}" id="c{number:02d}-aa-aaa">\n{variations}                </constraint>\n')


SIZE_CLASS_KEYS = {"hc": "heightClass=compact", "hr": "heightClass=regular", "wc": "widthClass=compact", "wr": "widthClass=regular",
                   "rc": COMPACT, "rr": REGULAR, "cc": "heightClass=compact-widthClass=compact", "cr": "heightClass=compact-widthClass=regular"}
ORDER_VARIATIONS = {
    "vo-font-rr-rc": [REGULAR, COMPACT],
    **{f"vo-font-{name}": [key] for name, key in SIZE_CLASS_KEYS.items()},
    "vo-font-all": list(SIZE_CLASS_KEYS.values()),
    "vo-font-all-reversed": list(SIZE_CLASS_KEYS.values())[::-1],
    "vo-font-hc-wr": ["heightClass=compact", "widthClass=regular"],
    "vo-font-wr-hc": ["widthClass=regular", "heightClass=compact"],
}
EXPERIMENTS.update({name: constrained(label(extra=font_variations(*keys)), "") for name, keys in ORDER_VARIATIONS.items()})
TWO_LABELS = {
    "vo-two-labels": (("lll-ll-ll1", 40), ("lll-ll-ll2", 80)),
    "vo-two-labels-ids-swapped": (("lll-ll-ll2", 40), ("lll-ll-ll1", 80)),
    "vo-two-labels-document-swapped": (("lll-ll-ll2", 80), ("lll-ll-ll1", 40)),
    "vo-two-labels-frames-swapped": (("lll-ll-ll1", 80), ("lll-ll-ll2", 40)),
    "vo-three-labels": (("lll-ll-ll1", 40), ("lll-ll-ll2", 80), ("lll-ll-ll3", 120)),
    "vo-three-labels-shuffled": (("lll-ll-ll3", 40), ("lll-ll-ll1", 80), ("lll-ll-ll2", 120)),
}
EXPERIMENTS.update({name: constrained("".join(label(extra=font_variations(REGULAR, sizes=[20 + index]), identifier=identifier, frame=(20, y, 42, 21))
                                              for index, (identifier, y) in enumerate(labels)), "") for name, labels in TWO_LABELS.items()})
EXPERIMENTS.update({
    "vo-label-one-varied": constrained(label(extra=font_variations(REGULAR)) + label(identifier="lll-ll-ll2", frame=(20, 80, 42, 21)), ""),
    "vo-label-second-varied": constrained(label() + label(extra=font_variations(REGULAR), identifier="lll-ll-ll2", frame=(20, 80, 42, 21)), ""),
    "vo-constant-two-keys": constrained(label(), constant_variation(0, "lll-ll-ll1", "top", 120, 250, (COMPACT, REGULAR))),
    "vo-constant-hc": constrained(label(), constant_variation(0, "lll-ll-ll1", "top", 120, 250, ("heightClass=compact",))),
    "vo-two-constants": constrained(label(), constant_variation(0, "lll-ll-ll1", "top", 120, 250) + constant_variation(1, "lll-ll-ll1", "leading", 20, 40)),
    "vo-two-constants-swapped": constrained(label(), constant_variation(1, "lll-ll-ll1", "top", 120, 250) + constant_variation(0, "lll-ll-ll1", "leading", 20, 40)),
    "vo-two-constants-document-swapped": constrained(label(), constant_variation(1, "lll-ll-ll1", "leading", 20, 40) + constant_variation(0, "lll-ll-ll1", "top", 120, 250)),
    "vo-constant-and-plain": constrained(label(), constraint(0, "lll-ll-ll1", "leading", ROOT, "leading", ' constant="20"') + constant_variation(1, "lll-ll-ll1", "top", 120, 250)),
    "vo-two-labels-constant": constrained(label(extra=font_variations(REGULAR)) + label(extra=font_variations(REGULAR, sizes=[22]), identifier="lll-ll-ll2", frame=(20, 80, 42, 21)),
                                          constant_variation(0, "lll-ll-ll2", "top", 80, 200)),
    "vo-font-same-size": constrained(label(extra=font_variations(REGULAR, sizes=[17])), ""),
})
# Which variation a storyboard's label and constraint take for their own font and constant: every
# key at once (fonts 16 to 23 and constants 101 to 108 in SIZE_CLASS_KEYS order), on each device.
SB_ALL_VARIATIONS = storyboard(scene(view_extra=SB_LABEL.replace('<nil key="highlightedColor"/>\n', '<nil key="highlightedColor"/>\n'
                                                               + font_variations(*SIZE_CLASS_KEYS.values()))
                                     + '                        <constraints>\n'
                                     + constant_variation(0, "lll-ll-ll1", "top", 120, 101, tuple(SIZE_CLASS_KEYS.values())).replace(ROOT, "8bC-Xf-vdC")
                                     + '                        </constraints>\n'))
SB_VARIATION_DEVICES = {"retina6_12": ("retina6_12", "portrait"), "retina6_12-landscape": ("retina6_12", "landscape"),
                        "retina6_7-landscape": ("retina6_7", "landscape"), "retina5_9": ("retina5_9", "portrait"),
                        "retina4_7-landscape": ("retina4_7", "landscape"), "ipad9_7": ("ipad9_7", "portrait"),
                        "ipad9_7-landscape": ("ipad9_7", "landscape"), "ipad12_9rounded": ("ipad12_9rounded", "portrait")}
STORYBOARDS.update({f"sb-vo-all-{name}": SB_ALL_VARIATIONS.replace('<device id="retina6_12" orientation="portrait"',
                                                                   f'<device id="{device}" orientation="{orientation}"')
                    for name, (device, orientation) in SB_VARIATION_DEVICES.items()})
STORYBOARDS["sb-vo-all-no-device"] = SB_ALL_VARIATIONS.replace('    <device id="retina6_12" orientation="portrait" appearance="light"/>\n', '')
STORYBOARDS["sb-vo-all-adaptation"] = SB_ALL_VARIATIONS.replace('<device id="retina6_12" orientation="portrait" appearance="light"/>',
                                                                '<device id="retina5_9" orientation="portrait" appearance="light">\n        <adaptation id="fullscreen"/>\n    </device>')
STORYBOARDS["sb-vo-rc-rr"] = storyboard(scene(view_extra=SB_LABEL.replace('<nil key="highlightedColor"/>\n', '<nil key="highlightedColor"/>\n'
                                                                        + font_variations(COMPACT, REGULAR, sizes=[16, 20]))))
STORYBOARDS["sb-vo-rr-only"] = storyboard(scene(view_extra=SB_LABEL.replace('<nil key="highlightedColor"/>\n', '<nil key="highlightedColor"/>\n'
                                                                          + font_variations(REGULAR, sizes=[20]))))
STORYBOARDS.update({f"sb-vo-all-{device}-landscape": SB_ALL_VARIATIONS.replace('<device id="retina6_12" orientation="portrait"',
                                                                               f'<device id="{device}" orientation="landscape"')
                    for device in ("retina3_5", "retina4_0", "retina5_5", "retina5_9", "retina6_0", "retina6_1", "retina6_3", "retina6_5",
                                   "retina6_9", "ipad11_0rounded", "ipad12_9rounded")})
STORYBOARDS.update({f"sb-vo-all-{device}": SB_ALL_VARIATIONS.replace('<device id="retina6_12"', f'<device id="{device}"')
                    for device in ("retina3_5", "retina4_0", "retina4_7", "retina5_5", "retina6_0", "retina6_1", "retina6_3", "retina6_5",
                                   "retina6_7", "retina6_9", "ipad11_0rounded")})
for name, keys in {"wc": ["widthClass=compact"], "hr": ["heightClass=regular"], "hr-wc": ["heightClass=regular", "widthClass=compact"],
                   "rr-hr": [REGULAR, "heightClass=regular"], "wr-hc": ["widthClass=regular", "heightClass=compact"]}.items():
    STORYBOARDS[f"sb-vo-partial-{name}"] = storyboard(scene(view_extra=SB_LABEL.replace(
        '<nil key="highlightedColor"/>\n', '<nil key="highlightedColor"/>\n' + font_variations(*keys, sizes=[30 + i for i in range(len(keys))]))
        + '                        <constraints>\n' + constant_variation(0, "lll-ll-ll1", "top", 120, 201, tuple(keys)).replace(ROOT, "8bC-Xf-vdC")
        + '                        </constraints>\n'))


# Round 23: colors ibtool converts by color management (calibratedRGB, deviceRGB, deviceWhite), many
# per document as the background colors of subviews: grays, each channel alone, and a fixed random
# sample, to find the conversion.
def color_sweep(space, colors):
    subviews = "".join(subview(f"swp-{index:03d}-aa", (0, index, 10, 1), attributes="").replace(
        "</view>", f'    <color key="backgroundColor" red="{red}" green="{green}" blue="{blue}" alpha="1" colorSpace="{space}"/>\n                </view>')
        for index, (red, green, blue) in enumerate(colors))
    return constrained(subviews, "")


SWEEP_RANDOM = random.Random(23)
SWEEP_COLORS = ([(k / 255, k / 255, k / 255) for k in range(256)] + [(k / 255, 0, 0) for k in range(0, 256, 5)]
                + [(0, k / 255, 0) for k in range(0, 256, 5)] + [(0, 0, k / 255) for k in range(0, 256, 5)]
                + [tuple(round(SWEEP_RANDOM.random(), 4) for _ in range(3)) for _ in range(200)])
for space in ("calibratedRGB", "deviceRGB"):
    for start in range(0, len(SWEEP_COLORS), 100):
        EXPERIMENTS[f"sweep-{space}-{start:03d}"] = color_sweep(space, [tuple(repr(c) for c in color) for color in SWEEP_COLORS[start:start + 100]])


# Round 24: scenes and navigation, as tofu's storyboard uses them: several identified scenes, a
# navigation controller and its root view controller, navigation items, bar button items with
# actions, show and presentation segues (identified or not), one feature at a time.
def controller_scene(number, attributes="", after_view="", connections="", view_extra=""):
    ids = dict(controller=f"vc{number}-aa-aaa", view_id=f"vw{number}-aa-aaa", scene_id=f"sc{number}-aa-aaa", responder=f"fr{number}-aa-aaa")
    text = scene(attributes=attributes, view_extra=view_extra, **ids)
    extra = after_view + (f"                    <connections>\n{connections}                    </connections>\n" if connections else "")
    return text.replace("                    </view>\n                </viewController>\n",
                        "                    </view>\n" + extra + "                </viewController>\n")


def navigation_scene(root, attributes="", bar_attributes="", extra=""):
    return ('        <scene sceneID="nvs-aa-aaa">\n            <objects>\n'
            f'                <navigationController id="nvc-aa-aaa"{attributes} sceneMemberID="viewController">\n{extra}'
            f'                    <navigationBar key="navigationBar" contentMode="scaleToFill"{bar_attributes} id="nvb-aa-aaa">\n'
            '                        <rect key="frame" x="0.0" y="59" width="393" height="44"/>\n'
            '                        <autoresizingMask key="autoresizingMask"/>\n                    </navigationBar>\n'
            '                    <connections>\n'
            f'                        <segue destination="{root}" kind="relationship" relationship="rootViewController" id="rel-aa-aaa"/>\n'
            '                    </connections>\n                </navigationController>\n'
            '                <placeholder placeholderIdentifier="IBFirstResponder" id="nfr-aa-aaa" sceneMemberID="firstResponder"/>\n'
            '            </objects>\n            <point key="canvasLocation" x="-400" y="0"/>\n        </scene>\n')


def navigation_item(title="Title", items="", attributes=""):
    if not items:
        return f'                    <navigationItem key="navigationItem" title="{title}"{attributes} id="nvi-aa-aaa"/>\n'
    return (f'                    <navigationItem key="navigationItem" title="{title}"{attributes} id="nvi-aa-aaa">\n{items}'
            '                    </navigationItem>\n')


def bar_item(key, system, number, action=None, attributes="", target="vc1-aa-aaa"):
    if action is None:
        return f'                        <barButtonItem key="{key}" systemItem="{system}"{attributes} id="bbi-aa-aa{number}"/>\n'
    return (f'                        <barButtonItem key="{key}" systemItem="{system}"{attributes} id="bbi-aa-aa{number}">\n'
            '                            <connections>\n'
            f'                                <action selector="{action}" destination="{target}" id="act-aa-aa{number}"/>\n'
            '                            </connections>\n                        </barButtonItem>\n')


def segue(destination, kind, number, identifier=None):
    named = f' identifier="{identifier}"' if identifier else ""
    return f'                        <segue destination="{destination}" kind="{kind}"{named} id="seg-aa-aa{number}"/>\n'


NAMED = ' storyboardIdentifier="Second"'
SCENES = {
    "sb-scenes-two-identified": storyboard(controller_scene(1), controller_scene(2, NAMED), initial="vc1-aa-aaa"),
    "sb-scenes-two-identified-both": storyboard(controller_scene(1, ' storyboardIdentifier="First"'), controller_scene(2, NAMED), initial="vc1-aa-aaa"),
    "sb-scenes-three-identified": storyboard(controller_scene(1), controller_scene(2, NAMED), controller_scene(3, ' storyboardIdentifier="Third"'),
                                             initial="vc1-aa-aaa"),
    "sb-scenes-no-initial-identified": storyboard(controller_scene(1, ' storyboardIdentifier="First"'), initial=None),
    "sb-nav": storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1), initial="nvc-aa-aaa"),
    "sb-nav-tofu": storyboard(navigation_scene("vc1-aa-aaa", ' automaticallyAdjustsScrollViewInsets="NO"', ' largeTitles="YES"',
                                               '                    <toolbarItems/>\n').replace(
        '                    <connections>\n                        <segue destination="vc1-aa-aaa" kind="relationship"',
        '                    <nil name="viewControllers"/>\n                    <connections>\n                        <segue destination="vc1-aa-aaa" kind="relationship"'),
                              controller_scene(1), initial="nvc-aa-aaa"),
    "sb-nav-item-title": storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, after_view=navigation_item()), initial="nvc-aa-aaa"),
    "sb-nav-item-large-never": storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, after_view=navigation_item(attributes=' largeTitleDisplayMode="never"')),
                                          initial="nvc-aa-aaa"),
    "sb-nav-item-no-nav": storyboard(controller_scene(1, after_view=navigation_item()), initial="vc1-aa-aaa"),
    "sb-bar-add": storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, after_view=navigation_item(
        items=bar_item("rightBarButtonItem", "add", 1, "addThing:"))), initial="nvc-aa-aaa"),
    "sb-bar-add-no-action": storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, after_view=navigation_item(
        items=bar_item("rightBarButtonItem", "add", 1))), initial="nvc-aa-aaa"),
    "sb-bar-cancel-done": storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, after_view=navigation_item(
        items=bar_item("leftBarButtonItem", "cancel", 1, "didPressCancel:") + bar_item("rightBarButtonItem", "done", 2, "didPressDone:", ' enabled="NO"'))),
        initial="nvc-aa-aaa"),
    "sb-bar-cancel-outlet": storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, after_view=navigation_item(
        items=bar_item("leftBarButtonItem", "cancel", 1, "didPressCancel:")), connections='                        <outlet property="cancelItem" destination="bbi-aa-aa1" id="out-aa-aa1"/>\n'),
        initial="nvc-aa-aaa"),
    "sb-segue-show": storyboard(controller_scene(1, connections=segue("vc2-aa-aaa", "show", 1, "Detail")), controller_scene(2), initial="vc1-aa-aaa"),
    "sb-segue-show-unnamed": storyboard(controller_scene(1, connections=segue("vc2-aa-aaa", "show", 1)), controller_scene(2), initial="vc1-aa-aaa"),
    "sb-segue-present": storyboard(controller_scene(1, connections=segue("vc2-aa-aaa", "presentation", 1, "Present")), controller_scene(2), initial="vc1-aa-aaa"),
    "sb-segue-two": storyboard(controller_scene(1, connections=segue("vc2-aa-aaa", "show", 1, "Detail") + segue("vc3-aa-aaa", "presentation", 2, "Present")),
                               controller_scene(2), controller_scene(3), initial="vc1-aa-aaa"),
    "sb-segue-to-identified": storyboard(controller_scene(1, connections=segue("vc2-aa-aaa", "show", 1, "Detail")), controller_scene(2, NAMED), initial="vc1-aa-aaa"),
    "sb-segue-present-nav": storyboard(controller_scene(1, connections=segue("nvc-aa-aaa", "presentation", 1, "Present")),
                                       navigation_scene("vc2-aa-aaa"), controller_scene(2, after_view=navigation_item()), initial="vc1-aa-aaa"),
    "sb-nav-show": storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, after_view=navigation_item(), connections=segue("vc2-aa-aaa", "show", 1, "Detail")),
                              controller_scene(2, after_view=navigation_item("Detail").replace("nvi-aa-aaa", "nvi-aa-aa2")), initial="nvc-aa-aaa"),
}
SUBVIEW_OUTLET = SUBVIEW.replace("sub-vi-ew1", "sbv-aa-aaa")
SCENES.update({
    "sb-segue-from-identified": storyboard(controller_scene(1, ' storyboardIdentifier="First"', connections=segue("vc2-aa-aaa", "show", 1, "Detail")),
                                           controller_scene(2), initial="vc1-aa-aaa"),
    "sb-segue-custom-class": storyboard(controller_scene(1, ' customClass="ListController" customModule="T" customModuleProvider="target"',
                                                         connections=segue("vc2-aa-aaa", "show", 1, "Detail")), controller_scene(2), initial="vc1-aa-aaa"),
    "sb-segue-and-outlet": storyboard(controller_scene(1, ' customClass="ListController" customModule="T" customModuleProvider="target"', view_extra=SUBVIEW_OUTLET,
                                                       connections='                        <outlet property="box" destination="sbv-aa-aaa" id="out-aa-aa1"/>\n'
                                                       + segue("vc2-aa-aaa", "show", 1, "Detail")), controller_scene(2), initial="vc1-aa-aaa"),
    "sb-segue-chain": storyboard(controller_scene(1, connections=segue("vc2-aa-aaa", "show", 1, "Next")),
                                 controller_scene(2, connections=segue("vc3-aa-aaa", "presentation", 2, "Last")), controller_scene(3), initial="vc1-aa-aaa"),
    "sb-segue-back": storyboard(controller_scene(1, connections=segue("vc2-aa-aaa", "show", 1, "Next")),
                                controller_scene(2, connections=segue("vc1-aa-aaa", "presentation", 2, "Back")), initial="vc1-aa-aaa"),
    "sb-segue-to-custom-class": storyboard(controller_scene(1, connections=segue("vc2-aa-aaa", "show", 1, "Detail")),
                                           controller_scene(2, ' customClass="DetailController" customModule="T" customModuleProvider="target"'), initial="vc1-aa-aaa"),
    "sb-segue-to-custom-class-plain": storyboard(controller_scene(1, connections=segue("vc2-aa-aaa", "show", 1, "Detail")),
                                                 controller_scene(2, ' customClass="DetailController"'), initial="vc1-aa-aaa"),
    "sb-segue-unreached-source": storyboard(controller_scene(1), controller_scene(2, connections=segue("vc3-aa-aaa", "show", 1, "Next")),
                                            controller_scene(3), initial="vc1-aa-aaa"),
})
# The navigation bar's geometry, which IB computes: on each device and orientation, with large titles,
# and without a device.
NAV = storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1), initial="nvc-aa-aaa")
NAV_LARGE = storyboard(navigation_scene("vc1-aa-aaa", bar_attributes=' largeTitles="YES"'), controller_scene(1), initial="nvc-aa-aaa")
for device in ("retina4_7", "retina5_9", "retina6_1", "retina6_9", "ipad9_7", "ipad12_9rounded"):
    for orientation in ("portrait", "landscape"):
        SCENES[f"sb-nav-bar-{device}-{orientation}"] = NAV.replace('<device id="retina6_12" orientation="portrait"', f'<device id="{device}" orientation="{orientation}"')
        SCENES[f"sb-nav-bar-large-{device}-{orientation}"] = NAV_LARGE.replace('<device id="retina6_12" orientation="portrait"',
                                                                               f'<device id="{device}" orientation="{orientation}"')
SCENES["sb-nav-bar-large"] = NAV_LARGE
SCENES["sb-nav-bar-no-device"] = NAV.replace('    <device id="retina6_12" orientation="portrait" appearance="light"/>\n', '')
SCENES["sb-nav-bar-frame"] = NAV.replace('<rect key="frame" x="0.0" y="59" width="393" height="44"/>', '<rect key="frame" x="0.0" y="20" width="375" height="96"/>')
NAMES = ["Accounts", "Edit", "Scan", "Manual", "Algorithms", "Search", "Settings", "About", "Help"]
SCENES.update({f"sb-scenes-{count}-identified": storyboard(*(controller_scene(index + 1, f' storyboardIdentifier="{name}"')
                                                             for index, name in enumerate(NAMES[:count])), initial="vc1-aa-aaa")
               for count in range(4, 10)})
SCENES.update({f"sb-scenes-{count}-identified-reversed": storyboard(*(controller_scene(index + 1, f' storyboardIdentifier="{name}"')
                                                                      for index, name in reversed(list(enumerate(NAMES[:count])))),
                                                                    initial="vc1-aa-aaa") for count in (5, 9)})
STORYBOARDS.update(SCENES)


# Round 25: the colors of the corpus's documents that ibtool converts by color management
# (calibratedRGB, displayP3, deviceRGB: space, red, green, blue, alpha as the documents write them),
# as subviews' background colors of one xib and one storyboard per space.
CORPUS_CONVERTED = [
    ('calibratedRGB', '0.0', '0.0', '0.0', '0.69999999999999996'),
    ('calibratedRGB', '0.0', '0.0', '0.0', '1'),
    ('calibratedRGB', '0.01176470588', '0.66274509800000003', '0.95686274510000002', '1'),
    ('calibratedRGB', '0.011764705882352941', '0.66274509803921566', '0.95686274509803915', '1'),
    ('calibratedRGB', '0.1450980392', '0.79607843140000001', '0.40784313729999999', '1'),
    ('calibratedRGB', '0.16078431372549018', '0.16862745098039217', '0.1803921568627451', '0.84705882352941175'),
    ('calibratedRGB', '0.20000000000000001', '0.40000000000000002', '0.80000000000000004', '1'),
    ('calibratedRGB', '0.270588249', '0.78823530669999997', '0.3843137324', '1'),
    ('calibratedRGB', '0.29803922770000002', '0.29803922770000002', '0.29803922770000002', '1'),
    ('calibratedRGB', '0.33333333329999998', '0.33333333329999998', '0.33333333329999998', '1'),
    ('calibratedRGB', '0.33333333333333331', '0.33333333333333331', '0.33333333333333331', '1'),
    ('calibratedRGB', '0.3803921569', '0.31764705879999999', '0.28627450980000002', '1'),
    ('calibratedRGB', '0.38431372549019605', '0.0', '0.93333333333333335', '0.84705882352941175'),
    ('calibratedRGB', '0.44705882352941173', '0.46666666666666667', '0.49019607843137253', '1'),
    ('calibratedRGB', '0.47058823529411764', '0.83529411764705885', '0.28627450980392155', '1'),
    ('calibratedRGB', '0.56078431370000004', '0.59215686270000001', '0.64313725489999995', '0.84705882349999995'),
    ('calibratedRGB', '0.56078431370000004', '0.59215686270000001', '0.64313725489999995', '1'),
    ('calibratedRGB', '0.5607843137254902', '0.59215686274509804', '0.64313725490196072', '0.84705882352941175'),
    ('calibratedRGB', '0.5607843137254902', '0.59215686274509804', '0.64313725490196072', '1'),
    ('calibratedRGB', '0.59999999999999998', '0.59999999999999998', '0.59999999999999998', '1'),
    ('calibratedRGB', '0.60392156862745094', '0.62745098039215685', '0.65490196078431373', '1'),
    ('calibratedRGB', '0.72156862745098038', '0.76470588235294112', '0.78823529411764703', '1'),
    ('calibratedRGB', '0.72156862749999995', '0.76470588240000004', '0.78823529410000004', '1'),
    ('calibratedRGB', '0.80000000000000004', '0.80000000000000004', '0.80000000000000004', '1'),
    ('calibratedRGB', '0.87843137250000003', '0.87843137250000003', '0.87843137250000003', '1'),
    ('calibratedRGB', '0.8784313725490196', '0.90196078431372551', '0.91764705882352937', '1'),
    ('calibratedRGB', '0.89411764705882346', '0.89411764705882346', '0.89411764705882346', '1'),
    ('calibratedRGB', '0.90008913589999995', '0.0', '0.0', '1'),
    ('calibratedRGB', '0.90980392160000001', '0.90980392160000001', '0.90980392160000001', '1'),
    ('calibratedRGB', '0.91764705882352937', '0.92549019607843142', '0.94117647058823528', '1'),
    ('calibratedRGB', '0.94117647059999998', '0.91764705879999997', '0.85490196080000003', '1'),
    ('calibratedRGB', '0.95294117647058818', '0.92549019607843142', '0.94117647058823528', '1'),
    ('calibratedRGB', '0.95294117649999999', '0.92549019610000005', '0.94117647059999998', '1'),
    ('calibratedRGB', '0.97254901959999995', '0.94509803920000002', '0.90588235289999997', '1'),
    ('calibratedRGB', '0.98431372549999996', '0.98431372549999996', '0.98039215690000003', '1'),
    ('calibratedRGB', '1', '0.0', '0.0', '1'),
    ('calibratedRGB', '1', '0.2780970982', '1', '1'),
    ('calibratedRGB', '1', '0.5', '0.0', '1'),
    ('calibratedRGB', '1', '1', '1', '0.070000000000000007'),
    ('calibratedRGB', '1', '1', '1', '0.5'),
    ('calibratedRGB', '1', '1', '1', '0.69999999999999996'),
    ('calibratedRGB', '1', '1', '1', '1'),
    ('deviceRGB', '0.14901961389999999', '0.14901961389999999', '0.14901961389999999', '1'),
    ('displayP3', '0.0', '0.0', '0.0', '0.5'),
    ('displayP3', '0.0', '0.65745162960000003', '0.95673888920000005', '1'),
    ('displayP3', '0.035672488410000001', '1', '0.0', '1'),
    ('displayP3', '0.11764705882352941', '0.12156862745098039', '0.11764705882352941', '1'),
    ('displayP3', '0.18413844704627991', '0.11385995894670486', '0.023501332849264145', '1'),
    ('displayP3', '0.20784313725490194', '0.21176470588235294', '0.20784313725490194', '1'),
    ('displayP3', '0.27818405628204346', '0.16882148385047913', '0.043081961572170258', '1'),
    ('displayP3', '0.27818405629999998', '0.16882148390000001', '0.043081961570000001', '1'),
    ('displayP3', '0.3333357871', '0.33332890269999998', '0.33333355190000002', '1'),
    ('displayP3', '0.388265207', '0.96620899439999997', '0.53839670080000002', '1'),
    ('displayP3', '0.41960784309999999', '0.33743089440000001', '0.2274220586', '1'),
    ('displayP3', '0.41960784313725491', '0.33743089437484741', '0.22742205858230591', '1'),
    ('displayP3', '0.45803546909999998', '0.83982247109999997', '0.28705134989999997', '0.97139084509999996'),
    ('displayP3', '0.45803546909999998', '0.83982247109999997', '0.28705134989999997', '1'),
    ('displayP3', '0.49809366464614868', '0.5019572377204895', '0.5019567608833313', '0.23999999999999999'),
    ('displayP3', '0.53333333329999999', '0.53333333329999999', '0.53333333329999999', '1'),
    ('displayP3', '0.56470588235294117', '0.59215686274509804', '0.63921568627450975', '1'),
    ('displayP3', '0.60835868120000003', '0.8194983602', '0.82352894539999999', '1'),
    ('displayP3', '0.6350919008', '0.58443516490000003', '0.50978493690000004', '1'),
    ('displayP3', '0.63509190082550049', '0.58443516492843628', '0.50978493690490723', '1'),
    ('displayP3', '0.65881043683914675', '0.97104707468358964', '0.61889116059296578', '1'),
    ('displayP3', '0.92475664615631104', '0.57313865423202515', '0.21551844477653503', '1'),
    ('displayP3', '0.95686274510000002', '0.24313725489999999', '0.2156862745', '1'),
    ('displayP3', '1', '1', '1', '0.59999999999999998'),
    ('displayP3', '1', '1', '1', '1'),
]


def converted_subviews(colors, indent=""):
    return "".join(subview(f"cnv-{index:03d}-aa", (0, index, 10, 1)).replace(
        "</view>", f'    <color key="backgroundColor" red="{red}" green="{green}" blue="{blue}" alpha="{alpha}" ' +
        (f'colorSpace="custom" customColorSpace="{space}"' if space == "displayP3" else f'colorSpace="{space}"') + '/>\n                </view>')
        for index, (space, red, green, blue, alpha) in enumerate(colors))


# Round 61: ColorSync's conversion of calibratedRGB and displayP3 colors to extended sRGB, over a
# grid of 6 levels per channel and ramps of 21 levels per channel and gray, to find its pipeline
# instead of listing the corpus's colors.
_LEVELS = [f"{n / 5:g}" for n in range(6)]
_RAMP = [f"{n / 20:g}" for n in range(21)]


def color_grid(space):
    colors = [(space, r, g, b, "1") for r in _LEVELS for g in _LEVELS for b in _LEVELS]
    colors += [(space, v, "0", "0", "1") for v in _RAMP] + [(space, "0", v, "0", "1") for v in _RAMP]
    colors += [(space, "0", "0", v, "1") for v in _RAMP] + [(space, v, v, v, "1") for v in _RAMP]
    return colors


for _space in ("calibratedRGB", "displayP3"):
    EXPERIMENTS[f"color-grid-{_space}"] = constrained(converted_subviews(color_grid(_space)), "")


for space in ("calibratedRGB", "displayP3", "deviceRGB"):
    chosen = [color for color in CORPUS_CONVERTED if color[0] == space]
    EXPERIMENTS[f"converted-{space}"] = constrained(converted_subviews(chosen), "")
    STORYBOARDS[f"sb-converted-{space}"] = storyboard(scene(view_extra='                        <subviews>\n'
                                                             + converted_subviews(chosen).replace('                ', '                            ')
                                                             + '                        </subviews>\n'))


# Round 26: constraints between two subviews (BACKLOG B-265). A above B (`aaa-aa-aa1` at y 20, `bbb-bb-bb1`
# at y 200): two sibling constraints of every pair of attributes; one sibling and one view
# constraint of every pair; which item a sibling constraint groups under, written either way;
# and a sibling constraint alone.
SIB_A, SIB_B = "aaa-aa-aa1", "bbb-bb-bb1"


def siblings(constraints, a_frame=(10, 20, 100, 50), b_frame=(10, 200, 100, 50)):
    return constrained(subview(SIB_A, a_frame) + subview(SIB_B, b_frame), constraints)


SIBLINGS = {}
for i, a in enumerate(ATTRIBUTES):
    for b in ATTRIBUTES[i + 1:]:
        SIBLINGS[f"sib-pair-{a}-{b}"] = siblings(constraint(0, SIB_B, a, SIB_A, a) + constraint(1, SIB_B, b, SIB_A, b))
for a in ATTRIBUTES:
    for b in ATTRIBUTES:
        SIBLINGS[f"sib-mix-{a}-{b}"] = siblings(constraint(0, SIB_B, a, SIB_A, a) + constraint(1, SIB_B, b, ROOT, b))
for a, b in (("top", "bottom"), ("leading", "trailing"), ("centerX", "centerX"), ("centerY", "centerY"), ("width", "width")):
    SIBLINGS[f"sib-alone-b-{a}-{b}"] = siblings(constraint(0, SIB_B, a, SIB_A, b))
    SIBLINGS[f"sib-alone-a-{b}-{a}"] = siblings(constraint(0, SIB_A, b, SIB_B, a))
    SIBLINGS[f"sib-with-a-b-{a}-{b}"] = siblings(constraint(0, SIB_B, a, SIB_A, b) + constraint(1, SIB_A, "leading", ROOT, "leading"))
    SIBLINGS[f"sib-with-a-a-{b}-{a}"] = siblings(constraint(0, SIB_A, b, SIB_B, a) + constraint(1, SIB_A, "leading", ROOT, "leading"))
    SIBLINGS[f"sib-with-b-b-{a}-{b}"] = siblings(constraint(0, SIB_B, a, SIB_A, b) + constraint(1, SIB_B, "leading", ROOT, "leading"))
    SIBLINGS[f"sib-with-b-a-{b}-{a}"] = siblings(constraint(0, SIB_A, b, SIB_B, a) + constraint(1, SIB_B, "leading", ROOT, "leading"))
    SIBLINGS[f"sib-with-both-b-{a}-{b}"] = siblings(constraint(0, SIB_B, a, SIB_A, b) + constraint(1, SIB_A, "leading", ROOT, "leading")
                                                    + constraint(2, SIB_B, "leading", ROOT, "leading"))
    SIBLINGS[f"sib-with-both-a-{b}-{a}"] = siblings(constraint(0, SIB_A, b, SIB_B, a) + constraint(1, SIB_A, "leading", ROOT, "leading")
                                                    + constraint(2, SIB_B, "leading", ROOT, "leading"))
EXPERIMENTS.update(SIBLINGS)
# The order of two subviews' groups when their x and y orders differ: A lower left at (10, 200), B
# higher and to the right, their horizontal ranges apart, touching or overlapping, their vertical
# ones too; each with A's or B's id first.
for x_name, bx in (("x-apart", 200), ("x-touching", 110), ("x-overlap", 60)):
    for y_name, by in (("y-apart", 20), ("y-touching", 150), ("y-overlap", 180)):
        for ids in ("ab", "ba"):
            a, b = (SIB_A, SIB_B) if ids == "ab" else (SIB_B, SIB_A)
            SIBLINGS[f"sib-frames-{x_name}-{y_name}-{ids}"] = constrained(subview(a, (10, 200, 100, 50)) + subview(b, (bx, by, 100, 50)),
                                                                         pinned(a, 0) + pinned(b, 4))
EXPERIMENTS.update(SIBLINGS)


# Round 27: table view cells in xibs, as Xcode's "Cocoa Touch Class with XIB" template writes them,
# then one change at a time: the cell's attributes, a label in the content view, constraints to the
# content view's edges and margins, outlets, sizes, and the safe area.
CELL = "KGk-i7-Jjw"
CONTENT = "H2p-sc-9uM"


def cell_xib(cell_attributes=' customClass="Cell" customModule="T" customModuleProvider="target"', content="", cell_extra="",
             size=(320, 44), safe=True, content_attributes="", cell_mask=""):
    w, h = size
    guide = '            <viewLayoutGuide key="safeArea" id="njF-e1-oar"/>\n' if safe else ""
    text = xib(f'        <tableViewCell contentMode="scaleToFill" selectionStyle="default" indentationWidth="10"{cell_attributes} id="{CELL}">\n'
               f'            <rect key="frame" x="0.0" y="0.0" width="{w}" height="{h}"/>\n'
               f'            <autoresizingMask key="autoresizingMask"{cell_mask}/>\n'
               f'            <tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center"{content_attributes} tableViewCell="{CELL}" id="{CONTENT}">\n'
               f'                <rect key="frame" x="0.0" y="0.0" width="{w}" height="{h}"/>\n'
               '                <autoresizingMask key="autoresizingMask"/>\n'
               f'{content}            </tableViewCellContentView>\n{guide}{cell_extra}'
               '            <point key="canvasLocation" x="0" y="0"/>\n        </tableViewCell>\n')
    if safe:
        text = text.replace(' colorMatched="YES"', ' useSafeAreas="YES" colorMatched="YES"').replace(
            '        <capability name="documents saved', SAFE_AREA_CAPABILITY + '        <capability name="documents saved')
    return text


def cell_label(identifier="lbl-aa-aa1", frame=(20, 11, 280, 21), text="Title"):
    x, y, w, h = frame
    return (f'                    <label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" text="{text}" '
            f'textAlignment="natural" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="{identifier}">\n'
            f'                        <rect key="frame" x="{x}" y="{y}" width="{w}" height="{h}"/>\n'
            f'                        <fontDescription key="fontDescription" type="system" pointSize="17"/>\n'
            '                        <nil key="textColor"/>\n                        <nil key="highlightedColor"/>\n                    </label>\n')


def content(subviews, constraints=""):
    inner = f"                <subviews>\n{subviews}                </subviews>\n"
    if constraints:
        inner += f"                <constraints>\n{constraints}                </constraints>\n"
    return inner


def cell_constraint(number, first, first_attribute, second, second_attribute, extra=""):
    first_item = f' firstItem="{first}"' if first else ""
    return f'                    <constraint{first_item} firstAttribute="{first_attribute}" secondItem="{second}" secondAttribute="{second_attribute}"{extra} id="cc{number}-aa-aaa"/>\n'


EDGES_TO_CONTENT = "".join(cell_constraint(k, "lbl-aa-aa1", a, CONTENT, a) for k, a in enumerate(EDGES))
EDGES_TO_MARGINS = (cell_constraint(0, "lbl-aa-aa1", "top", CONTENT, "topMargin") + cell_constraint(1, None, "trailingMargin", "lbl-aa-aa1", "trailing")
                    + cell_constraint(2, "lbl-aa-aa1", "leading", CONTENT, "leadingMargin") + cell_constraint(3, None, "bottomMargin", "lbl-aa-aa1", "bottom"))
CELLS = {
    "cell-template": cell_xib(),
    "cell-plain": cell_xib(""),
    "cell-no-safe-area": cell_xib(safe=False),
    "cell-reuse": cell_xib(' reuseIdentifier="Cell" customClass="Cell" customModule="T" customModuleProvider="target"'),
    "cell-row-height": cell_xib(' rowHeight="80" customClass="Cell" customModule="T" customModuleProvider="target"', size=(320, 80)),
    "cell-size": cell_xib(size=(414, 80)),
    "cell-mask": cell_xib(cell_mask=' flexibleMaxX="YES" flexibleMaxY="YES"'),
    "cell-selection-none": cell_xib(' customClass="Cell" customModule="T" customModuleProvider="target"').replace('selectionStyle="default"', 'selectionStyle="none"'),
    "cell-selection-blue": cell_xib().replace('selectionStyle="default"', 'selectionStyle="blue"'),
    "cell-selection-gray": cell_xib().replace('selectionStyle="default"', 'selectionStyle="gray"'),
    "cell-accessory": cell_xib(' accessoryType="disclosureIndicator" customClass="Cell" customModule="T" customModuleProvider="target"'),
    "cell-accessory-checkmark": cell_xib(' accessoryType="checkmark" customClass="Cell" customModule="T" customModuleProvider="target"'),
    "cell-restoration": cell_xib(' restorationIdentifier="Cell" customClass="Cell" customModule="T" customModuleProvider="target"'),
    "cell-clips": cell_xib(' clipsSubviews="YES" customClass="Cell" customModule="T" customModuleProvider="target"'),
    "cell-preserves-margins": cell_xib(' preservesSuperviewLayoutMargins="YES" customClass="Cell" customModule="T" customModuleProvider="target"',
                                      content_attributes=' preservesSuperviewLayoutMargins="YES"'),
    "cell-content-insets-no": cell_xib(content_attributes=' insetsLayoutMarginsFromSafeArea="NO"'),
    "cell-indentation": cell_xib(' indentationLevel="1" customClass="Cell" customModule="T" customModuleProvider="target"'),
    "cell-hides-accessory-no": cell_xib(' hidesAccessoryWhenEditing="NO" customClass="Cell" customModule="T" customModuleProvider="target"'),
    "cell-background": cell_xib(cell_extra='            ' + rgb(0.2, 0.4, 0.6, 1) + "\n"),
    "cell-content-background": cell_xib(content='                ' + rgb(0.2, 0.4, 0.6, 1) + "\n"),
    "cell-label": cell_xib(content=content(cell_label())),
    "cell-label-edges": cell_xib(content=content(cell_label(), EDGES_TO_CONTENT)),
    "cell-label-margins": cell_xib(content=content(cell_label(), EDGES_TO_MARGINS)),
    "cell-label-outlet": cell_xib(content=content(cell_label(), EDGES_TO_CONTENT),
                                  cell_extra='            <connections>\n                <outlet property="titleLabel" destination="lbl-aa-aa1" id="out-aa-aa1"/>\n            </connections>\n'),
    "cell-two-labels": cell_xib(content=content(cell_label() + cell_label("lbl-aa-aa2", (20, 40, 280, 21), "Detail"),
                                                cell_constraint(0, "lbl-aa-aa1", "leading", CONTENT, "leading", ' constant="20"')
                                                + cell_constraint(1, "lbl-aa-aa2", "top", "lbl-aa-aa1", "bottom", ' constant="8"')
                                                + cell_constraint(2, "lbl-aa-aa2", "leading", "lbl-aa-aa1", "leading")), size=(320, 80)),
}
EXPERIMENTS.update(CELLS)


# Round 28: constraints to layout margins: a label constrained to its container's margin, for each
# margin attribute, with and without a constant, in a xib's root view, a xib's subview, a cell's
# content view, and a storyboard scene's view on several devices; and margin attributes sorted with
# plain ones.
MARGIN_ATTRIBUTES = {"leading": "leadingMargin", "trailing": "trailingMargin", "top": "topMargin", "bottom": "bottomMargin",
                     "left": "leftMargin", "right": "rightMargin", "centerX": "centerXWithinMargins", "centerY": "centerYWithinMargins"}


def margin_constraint(attribute, container, constant, label="lbl-aa-aa1", reversed_=False):
    extra = f' constant="{constant}"' if constant else ""
    if reversed_:
        return f'<constraint firstAttribute="{MARGIN_ATTRIBUTES[attribute]}" secondItem="{label}" secondAttribute="{attribute}"{extra} id="mc0-aa-aaa"/>\n'
    return f'<constraint firstItem="{label}" firstAttribute="{attribute}" secondItem="{container}" secondAttribute="{MARGIN_ATTRIBUTES[attribute]}"{extra} id="mc0-aa-aaa"/>\n'


MARGINS = {}
for attribute in MARGIN_ATTRIBUTES:
    for constant in (0, 10):
        for reversed_ in (False, True):
            suffix = f"{attribute}-{constant}" + ("-reversed" if reversed_ else "")
            line = margin_constraint(attribute, ROOT, constant, label="lll-ll-ll1", reversed_=reversed_)
            MARGINS[f"margin-root-{suffix}"] = constrained(label(), "                " + line)
            MARGINS[f"margin-cell-{suffix}"] = cell_xib(content=content(cell_label(), "                    " + margin_constraint(attribute, CONTENT, constant, reversed_=reversed_)
                                                                          .replace('firstAttribute="', 'firstItem="H2p-sc-9uM" firstAttribute="', 1) if reversed_ else
                                                                          "                    " + margin_constraint(attribute, CONTENT, constant)))
CONTAINER = ('                <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="box-aa-aaa">\n'
             '                    <rect key="frame" x="20" y="100" width="300" height="200"/>\n                    <subviews>\n{label}'
             '                    </subviews>\n                    <constraints>\n                        {constraint}                    </constraints>\n'
             '                </view>\n')
for attribute in ("leading", "top", "trailing", "bottom"):
    MARGINS[f"margin-sub-{attribute}"] = constrained(CONTAINER.format(label=label().replace("                ", "                        "),
                                                                      constraint=margin_constraint(attribute, "box-aa-aaa", 0, label="lll-ll-ll1")), "")
    MARGINS[f"margin-sub-preserves-{attribute}"] = MARGINS[f"margin-sub-{attribute}"].replace(
        'translatesAutoresizingMaskIntoConstraints="NO" id="box-aa-aaa"', 'preservesSuperviewLayoutMargins="YES" translatesAutoresizingMaskIntoConstraints="NO" id="box-aa-aaa"')
    for device in ("retina6_12", "retina4_7", "ipad9_7", "no-device"):
        document = storyboard(scene(view_extra=SB_LABEL + '                        <constraints>\n                            '
                                    + margin_constraint(attribute, "8bC-Xf-vdC", 0, label="lll-ll-ll1") + '                        </constraints>\n'))
        document = (document.replace('    <device id="retina6_12" orientation="portrait" appearance="light"/>\n', '') if device == "no-device"
                    else document.replace('id="retina6_12"', f'id="{device}"'))
        STORYBOARDS[f"sb-margin-{device}-{attribute}"] = document
for first, second in (("leading", "leadingMargin"), ("leadingMargin", "leading"), ("top", "topMargin"), ("trailingMargin", "centerX")):
    lines = "".join(f'                <constraint firstItem="lll-ll-ll1" firstAttribute="{a.replace("Margin", "")}" secondItem="{ROOT}" secondAttribute="{a}" id="mo{k}-aa-aaa"/>\n'
                    for k, a in enumerate((first, second)))
    MARGINS[f"margin-order-{first}-{second}"] = constrained(label(), lines)
# The order of two subviews' groups inside a cell's content view, as `sib-frames-*` in a view, with the
# A frame's horizontal range inside B's or apart.
def cell_pair(a_frame, b_frame, ids="ab"):
    a, b = ("aaa-aa-aa1", "bbb-bb-bb1") if ids == "ab" else ("bbb-bb-bb1", "aaa-aa-aa1")
    views = "".join(f'                    <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="{i}">\n'
                    f'                        <rect key="frame" x="{f[0]}" y="{f[1]}" width="{f[2]}" height="{f[3]}"/>\n                    </view>\n'
                    for i, f in ((a, a_frame), (b, b_frame)))
    lines = "".join(cell_constraint(f"{k}{n}", i, e, CONTENT, e) for k, i in enumerate((a, b)) for n, e in enumerate(EDGES))
    return cell_xib(content=content(views, lines), size=(320, 300))


for x_name, bx in (("x-apart", 200), ("x-touching", 110), ("x-overlap", 60)):
    for y_name, by in (("y-apart", 20), ("y-touching", 150), ("y-overlap", 180)):
        for ids in ("ab", "ba"):
            MARGINS[f"cell-frames-{x_name}-{y_name}-{ids}"] = cell_pair((10, 200, 100, 50), (bx, by, 100, 50), ids)
for name, (a_frame, b_frame) in {"inside-above": ((141, 7, 37, 22), (0, 34, 320, 1)), "inside-below": ((141, 40, 37, 22), (0, 4, 320, 1)),
                                 "wide-above": ((0, 7, 320, 22), (141, 34, 37, 1)), "partial-above": ((100, 7, 150, 22), (0, 34, 200, 1))}.items():
    MARGINS[f"cell-frames-{name}"] = cell_pair(a_frame, b_frame)
    MARGINS[f"view-frames-{name}"] = constrained(subview("aaa-aa-aa1", a_frame) + subview("bbb-bb-bb1", b_frame), pinned("aaa-aa-aa1", 0) + pinned("bbb-bb-bb1", 4))
EXPERIMENTS.update(MARGINS)


# Round 29: a table view inside a xib's view, as the corpus's view controllers' xibs hold them: its
# style, separator style, row and section heights, outlets to File's Owner, then one change at a time.
TABLE_ATTRIBUTES = ('clipsSubviews="YES" contentMode="scaleToFill" alwaysBounceVertical="YES" style="plain" separatorStyle="default" rowHeight="-1" '
                    'estimatedRowHeight="-1" sectionHeaderHeight="28" sectionFooterHeight="28" translatesAutoresizingMaskIntoConstraints="NO"')
TABLE_OUTLETS = ('                    <connections>\n                        <outlet property="dataSource" destination="-1" id="tds-aa-aaa"/>\n'
                 '                        <outlet property="delegate" destination="-1" id="tdl-aa-aaa"/>\n                    </connections>\n')


def table_xib(attributes=TABLE_ATTRIBUTES, extra="", custom=""):
    table = (f'                <tableView {attributes}{custom} id="tbl-aa-aaa">\n'
             '                    <rect key="frame" x="0.0" y="0.0" width="393" height="852"/>\n'
             f'{extra}                </tableView>\n')
    return constrained(table, "".join(constraint(k, "tbl-aa-aaa", a, ROOT, a) for k, a in enumerate(EDGES)))


TABLES = {
    "table-plain": table_xib(),
    "table-grouped": table_xib(TABLE_ATTRIBUTES.replace('style="plain"', 'style="grouped"').replace('"28"', '"18"')),
    "table-inset-grouped": table_xib(TABLE_ATTRIBUTES.replace('style="plain"', 'style="insetGrouped"').replace('"28"', '"18"')),
    "table-separator-none": table_xib(TABLE_ATTRIBUTES.replace('separatorStyle="default"', 'separatorStyle="none"')),
    "table-separator-etched": table_xib(TABLE_ATTRIBUTES.replace('separatorStyle="default"', 'separatorStyle="singleLineEtched"')),
    "table-row-44": table_xib(TABLE_ATTRIBUTES.replace('rowHeight="-1"', 'rowHeight="44"')),
    "table-estimated-80": table_xib(TABLE_ATTRIBUTES.replace('estimatedRowHeight="-1"', 'estimatedRowHeight="80"')),
    "table-no-estimated": table_xib(TABLE_ATTRIBUTES.replace(' estimatedRowHeight="-1"', '')),
    "table-sections-18": table_xib(TABLE_ATTRIBUTES.replace('"28"', '"18"')),
    "table-outlets": table_xib(extra=TABLE_OUTLETS),
    "table-custom": table_xib(custom=' customClass="ListView" customModule="T" customModuleProvider="target"'),
    "table-indicators": table_xib(TABLE_ATTRIBUTES + ' showsHorizontalScrollIndicator="NO" showsVerticalScrollIndicator="NO"'),
    "table-keyboard-drag": table_xib(TABLE_ATTRIBUTES + ' keyboardDismissMode="onDrag"'),
    "table-indicator-white": table_xib(TABLE_ATTRIBUTES + ' indicatorStyle="white"'),
    "table-editing-selection": table_xib(TABLE_ATTRIBUTES + ' allowsSelectionDuringEditing="YES"'),
    "table-background": table_xib(extra='                    ' + rgb(0.2, 0.4, 0.6, 1) + "\n"),
    "table-grouped-outlets-custom": table_xib(TABLE_ATTRIBUTES.replace('style="plain"', 'style="grouped"').replace('"28"', '"18"'), TABLE_OUTLETS,
                                              ' customClass="ListView" customModule="T" customModuleProvider="target"'),
}
for name, color in {"white": gray(1, 1), "black": gray(0, 1), "clear": gray(0, 0), "gray": gray(0.5, 1), "white-rgb": rgb(1, 1, 1, 1),
                    "white-system": '<color key="backgroundColor" systemColor="systemBackgroundColor"/>'}.items():
    TABLES[f"table-background-{name}"] = table_xib(extra='                    ' + color + "\n")
    TABLES[f"table-grouped-background-{name}"] = table_xib(TABLE_ATTRIBUTES.replace('style="plain"', 'style="grouped"').replace('"28"', '"18"'),
                                                           extra='                    ' + color + "\n")
EXPERIMENTS.update(TABLES)


# Round 32: buttons, as IB writes them: a system button with a title, then one change at a time
# (types, alignments, line breaks, fonts, states' titles, colors and images, flags, insets, colors).
BUTTON_ATTRIBUTES = ('opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" '
                     'buttonType="system" lineBreakMode="middleTruncation"')
BUTTON_STATE = '<state key="normal" title="Button"/>\n'


def button(attributes=BUTTON_ATTRIBUTES, children=BUTTON_STATE, identifier="bbb-bb-bb1", frame=(20, 40, 75, 35)):
    x, y, w, h = frame
    body = f'<rect key="frame" x="{x}" y="{y}" width="{w}" height="{h}"/>\n' + children
    return (f'                <button {attributes} translatesAutoresizingMaskIntoConstraints="NO" id="{identifier}">\n'
            + "".join(f'                    {line}\n' for line in body.splitlines()) + '                </button>\n')


def button_state(key="normal", title="Button", extra="", attributes=""):
    title_attribute = f' title="{title}"' if title is not None else ""
    if not extra:
        return f'<state key="{key}"{title_attribute}{attributes}/>\n'
    return f'<state key="{key}"{title_attribute}{attributes}>\n' + "".join(f'    {line}\n' for line in extra.splitlines()) + '</state>\n'


SYSTEM_15 = font_description({"type": "system", "pointSize": "15"})
BUTTON_IMAGE = '        <image name="Logo" width="168" height="185"/>\n'
BUTTON_SYMBOL = ('        <image name="plus" catalog="system" width="128" height="113"/>\n')
BUTTONS = {
    "button": constrained(button(), ""),
    "button-no-state": constrained(button(children=""), ""),
    "button-no-title": constrained(button(children=button_state(title=None)), ""),
    "button-font-15": constrained(button(children=SYSTEM_15 + "\n" + BUTTON_STATE), ""),
    "button-font-bold": constrained(button(children=font_description({"type": "boldSystem", "pointSize": "17"}) + "\n" + BUTTON_STATE), ""),
    "button-font-body": constrained(button(children=font_description({"style": "UICTFontTextStyleBody"}) + "\n" + BUTTON_STATE), ""),
    "button-font-named": constrained(button(children=font_description({"name": "HelveticaNeue", "family": "Helvetica Neue", "pointSize": "17"})
                                            + "\n" + BUTTON_STATE), ""),
    "button-title-color": constrained(button(children=button_state(extra=rgb(1, 0.5, 0.25, 1).replace("backgroundColor", "titleColor"))), ""),
    "button-title-color-system": constrained(button(children=button_state(extra='<color key="titleColor" systemColor="systemRedColor"/>')), "",
                                             resources=system_color("systemRedColor", gray(0, 1))),
    "button-title-shadow-color": constrained(button(children=button_state(extra=gray(0.5, 1).replace("backgroundColor", "titleShadowColor"))), ""),
    "button-title-colors": constrained(button(children=button_state(extra=gray(1, 1).replace("backgroundColor", "titleColor") + "\n"
                                                                    + gray(0.5, 1).replace("backgroundColor", "titleShadowColor"))), ""),
    "button-highlighted-title": constrained(button(children=BUTTON_STATE + button_state("highlighted", "Pressed")), ""),
    "button-selected-title": constrained(button(children=BUTTON_STATE + button_state("selected", "Chosen")), ""),
    "button-highlighted-color": constrained(button(children=BUTTON_STATE + button_state(
        "highlighted", None, gray(0.5, 1).replace("backgroundColor", "titleColor"))), ""),
    "button-image": constrained(button(children=button_state(title=None, attributes=' image="Logo"')), "", resources=BUTTON_IMAGE),
    "button-image-title": constrained(button(children=button_state(attributes=' image="Logo"')), "", resources=BUTTON_IMAGE),
    "button-image-symbol": constrained(button(children=button_state(title=None, attributes=' image="plus" catalog="system"')), "",
                                       resources=BUTTON_SYMBOL),
    "button-two": constrained(button() + button(identifier="bbb-bb-bb2", frame=(20, 100, 75, 35)), ""),
    "button-two-titles": constrained(button() + button(children=button_state(title="Other"), identifier="bbb-bb-bb2", frame=(20, 100, 75, 35)), ""),
    "button-custom-class": constrained(button(BUTTON_ATTRIBUTES + ' customClass="MyButton"'), ""),
    "button-custom-class-module": constrained(button(BUTTON_ATTRIBUTES + ' customClass="MyButton" customModule="T" customModuleProvider="target"'), ""),
    "button-background-color": constrained(button(children=BUTTON_STATE + rgb(0.2, 0.4, 0.6, 1)), ""),
    "button-tint-color": constrained(button(children=BUTTON_STATE + rgb(0.2, 0.4, 0.6, 1).replace("backgroundColor", "tintColor")), ""),
    "button-tint-and-background": constrained(button(children=BUTTON_STATE + gray(0.5, 1) + "\n"
                                                     + rgb(0.2, 0.4, 0.6, 1).replace("backgroundColor", "tintColor")), ""),
    "button-unconstrained": constrained(button().replace(' translatesAutoresizingMaskIntoConstraints="NO"', ''), ""),
}
for value in ("roundedRect", "infoLight", "infoDark", "contactAdd", "detailDisclosure"):
    BUTTONS[f"button-type-{value}"] = constrained(button(BUTTON_ATTRIBUTES.replace('"system"', f'"{value}"')), "")
BUTTONS["button-type-custom"] = constrained(button(BUTTON_ATTRIBUTES.replace(' buttonType="system"', '')), "")
for value in ("leading", "left", "right", "trailing", "fill"):
    BUTTONS[f"button-halign-{value}"] = constrained(button(BUTTON_ATTRIBUTES.replace('contentHorizontalAlignment="center"',
                                                                                       f'contentHorizontalAlignment="{value}"')), "")
for value in ("top", "bottom", "fill"):
    BUTTONS[f"button-valign-{value}"] = constrained(button(BUTTON_ATTRIBUTES.replace('contentVerticalAlignment="center"',
                                                                                     f'contentVerticalAlignment="{value}"')), "")
BUTTONS["button-no-alignments"] = constrained(button(BUTTON_ATTRIBUTES.replace(' contentHorizontalAlignment="center" contentVerticalAlignment="center"', '')), "")
for value in ("wordWrap", "characterWrap", "clip", "headTruncation", "tailTruncation"):
    BUTTONS[f"button-break-{value}"] = constrained(button(BUTTON_ATTRIBUTES.replace('"middleTruncation"', f'"{value}"')), "")
BUTTONS["button-no-line-break"] = constrained(button(BUTTON_ATTRIBUTES.replace(' lineBreakMode="middleTruncation"', '')), "")
for flag in ('enabled="NO"', 'selected="YES"', 'highlighted="YES"', 'showsTouchWhenHighlighted="YES"', 'adjustsImageWhenHighlighted="NO"',
             'adjustsImageWhenDisabled="NO"', 'reversesTitleShadowWhenHighlighted="YES"', 'pointerInteraction="YES"',
             'changesSelectionAsPrimaryAction="YES"', 'adjustsImageSizeForAccessibilityContentSizeCategory="YES"', 'role="primary"',
             'menu="NO"', 'springLoaded="YES"', 'hidden="YES"', 'clipsSubviews="YES"', 'tag="1"'):
    BUTTONS[f"button-flag-{flag.split('=')[0]}"] = constrained(button(f"{BUTTON_ATTRIBUTES} {flag}"), "")
for key, values in {"imageEdgeInsets": ("0.0", "0.0", "2.2250738585072014e-308", "0.0"), "contentEdgeInsets": ("40", "20", "40", "20"),
                    "titleEdgeInsets": ("14", "10", "14", "10")}.items():
    inset = '<inset key="{}" minX="{}" minY="{}" maxX="{}" maxY="{}"/>\n'.format(key, *values)
    BUTTONS[f"button-{key}"] = constrained(button(children=inset + BUTTON_STATE), "")
BUTTONS["button-content-insets-asymmetric"] = constrained(button(children='<inset key="contentEdgeInsets" minX="1" minY="2" maxX="3" maxY="4"/>\n'
                                                                 + BUTTON_STATE), "")
BUTTONS["button-all-insets"] = constrained(button(children='<inset key="contentEdgeInsets" minX="16" minY="0.0" maxX="16" maxY="0.0"/>\n'
                                                  '<inset key="titleEdgeInsets" minX="6" minY="4" maxX="6" maxY="4"/>\n'
                                                  '<inset key="imageEdgeInsets" minX="0.0" minY="0.0" maxX="8" maxY="0.0"/>\n' + BUTTON_STATE), "")
for style in ("plain", "gray", "tinted", "filled", "borderless", "borderedProminent"):
    BUTTONS[f"button-configuration-{style}"] = constrained(button(children=BUTTON_STATE + f'<buttonConfiguration key="configuration" style="{style}" title="Button"/>\n'), "")
BUTTONS["button-configuration-no-title"] = constrained(button(children=BUTTON_STATE + '<buttonConfiguration key="configuration" style="plain"/>\n'), "")
BUTTONS["button-configuration-image"] = constrained(button(children=BUTTON_STATE + '<buttonConfiguration key="configuration" style="plain" image="Logo"/>\n'),
                                                    "", resources=BUTTON_IMAGE)
BUTTONS["button-control-flags"] = constrained(button(BUTTON_ATTRIBUTES.replace('"center"', '"leading"', 1).replace('"center"', '"top"', 1)
                                                      + ' enabled="NO" selected="YES" highlighted="YES" pointerInteraction="YES" hidden="YES" tag="3"',
                                                      BUTTON_STATE + gray(0.5, 1) + "\n" + rgb(0.2, 0.4, 0.6, 1).replace("backgroundColor", "tintColor")), "")
BUTTONS["button-button-flags"] = constrained(button(BUTTON_ATTRIBUTES.replace('"middleTruncation"', '"wordWrap"')
                                                    + ' showsTouchWhenHighlighted="YES" reversesTitleShadowWhenHighlighted="YES" adjustsImageWhenHighlighted="NO"'
                                                    ' adjustsImageWhenDisabled="NO" adjustsImageSizeForAccessibilityContentSizeCategory="YES" role="primary"'
                                                    ' springLoaded="YES" changesSelectionAsPrimaryAction="YES"',
                                                    SYSTEM_15 + "\n" + '<inset key="contentEdgeInsets" minX="1" minY="2" maxX="3" maxY="4"/>\n'
                                                    '<inset key="titleEdgeInsets" minX="5" minY="6" maxX="7" maxY="8"/>\n'
                                                    '<inset key="imageEdgeInsets" minX="9" minY="10" maxX="11" maxY="12"/>\n' + BUTTON_STATE), "")
STATES = {"normal": BUTTON_STATE, "highlighted": button_state("highlighted", "H"), "selected": button_state("selected", "S"),
          "disabled": button_state("disabled", "D")}
for name, keys in {"all": ["normal", "highlighted", "selected", "disabled"], "all-reversed": ["disabled", "selected", "highlighted", "normal"],
                   "disabled": ["normal", "disabled"], "highlighted-selected": ["highlighted", "selected"],
                   "selected-disabled": ["normal", "selected", "disabled"], "highlighted-disabled": ["normal", "highlighted", "disabled"]}.items():
    BUTTONS[f"button-states-{name}"] = constrained(button(children="".join(STATES[key] for key in keys)), "")
BUTTONS["button-state-content"] = constrained(button(children=button_state(
    attributes=' image="Logo" backgroundImage="Logo"', extra=gray(1, 1).replace("backgroundColor", "titleColor") + "\n"
    + gray(0.5, 1).replace("backgroundColor", "titleShadowColor"))), "", resources=BUTTON_IMAGE)
BUTTONS["button-state-background-image"] = constrained(button(children=button_state(attributes=' backgroundImage="Logo"')), "", resources=BUTTON_IMAGE)
BUTTONS["button-zero-insets"] = constrained(button(children='<inset key="contentEdgeInsets" minX="0.0" minY="0.0" maxX="0.0" maxY="0.0"/>\n'
                                                   + BUTTON_STATE), "")
BUTTONS["button-tint-view-flags"] = constrained(button(BUTTON_ATTRIBUTES.replace('scaleToFill', 'center') + ' alpha="0.5" clipsSubviews="YES"'
                                                       ' userInteractionEnabled="NO" multipleTouchEnabled="YES"',
                                                       BUTTON_STATE + rgb(0.2, 0.4, 0.6, 1).replace("backgroundColor", "tintColor")), "")
BUTTONS["view-tint-color"] = constrained(subview("sss-ss-ss1").replace("                </view>", "                    " + rgb(0.2, 0.4, 0.6, 1).replace(
    "backgroundColor", "tintColor") + "\n                </view>"), "")
TINT = rgb(0.2, 0.4, 0.6, 1).replace("backgroundColor", "tintColor")
BUTTONS["view-tint-top-level"] = xib(view('translatesAutoresizingMaskIntoConstraints="NO" horizontalHuggingPriority="251"', extra="            " + TINT + "\n"))
BUTTONS["button-tint-width"] = constrained(button(children=BUTTON_STATE + TINT + "\n" + '<constraints>\n'
                                                  + constraint(0, None, "width", extra=' constant="75"', indent=4) + '</constraints>\n'), "")
BUTTONS["button-lproj"] = constrained(button(children=BUTTON_STATE + button_state("highlighted", "Pressed")), "")
LPROJ_XIBS.add("button-lproj")
BUTTONS["image-view-symbol"] = constrained(subview("iii-ii-ii1", (112, 333, 168, 185), "imageView", ' image="plus" catalog="system"'), "",
                                           resources=BUTTON_SYMBOL)
BUTTONS["button-image-symbol-and-view"] = constrained(button(children=button_state(title=None, attributes=' image="plus" catalog="system"'))
                                                      + subview("iii-ii-ii1", (112, 333, 168, 185), "imageView", ' image="plus" catalog="system"'), "",
                                                      resources=BUTTON_SYMBOL)
for value in ("infoLight", "infoDark", "contactAdd", "detailDisclosure"):
    BUTTONS[f"button-type-{value}-untitled"] = constrained(button(BUTTON_ATTRIBUTES.replace('"system"', f'"{value}"'), ""), "")
BUTTONS["button-type-infoLight-hugging"] = constrained(button(BUTTON_ATTRIBUTES.replace('"system"', '"infoLight"') + ' horizontalHuggingPriority="251"', ""), "")
BUTTONS["button-type-infoLight-font"] = constrained(button(BUTTON_ATTRIBUTES.replace('"system"', '"infoLight"'), SYSTEM_15), "")
BUTTONS["button-type-infoLight-color"] = constrained(button(BUTTON_ATTRIBUTES.replace('"system"', '"infoLight"'), button_state(
    title=None, extra=gray(0.5, 1).replace("backgroundColor", "titleColor"))), "")
SB_BUTTON = ('                        <subviews>\n' + button().replace('                ', '                            ')
             + '                        </subviews>\n')
STORYBOARDS["sb-button"] = storyboard(scene(view_extra=SB_BUTTON))
STORYBOARDS["sb-button-image"] = storyboard(scene(view_extra=SB_BUTTON.replace('<state key="normal" title="Button"/>',
                                                                                 '<state key="normal" image="plus" catalog="system"/>')),
                                            resources=BUTTON_SYMBOL)
EXPERIMENTS.update(BUTTONS)


# Round 33: stack views, as IB writes them: a horizontal stack of two labels pinned to nothing, then
# one change at a time (axis, distributions, alignments, spacing, flags, arranged subviews of other
# kinds, nesting, constraints, margins).
STACK_ATTRIBUTES = 'opaque="NO" contentMode="scaleToFill"'


def stack_label(identifier, frame, text="Label"):
    x, y, w, h = frame
    return (f'<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" '
            f'text="{text}" textAlignment="natural" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" '
            f'translatesAutoresizingMaskIntoConstraints="NO" id="{identifier}">\n'
            f'    <rect key="frame" x="{x}" y="{y}" width="{w}" height="{h}"/>\n'
            f'    {SYSTEM_17}\n    <nil key="textColor"/>\n    <nil key="highlightedColor"/>\n</label>\n')


TWO_LABELS = stack_label("lab-aa-aa1", (0, 0, 42, 21)) + stack_label("lab-aa-aa2", (50, 0, 42, 21), "Other")


def stack(attributes=STACK_ATTRIBUTES, arranged=TWO_LABELS, extra="", identifier="stk-aa-aa1", frame=(20, 40, 92, 21), indent=16):
    x, y, w, h = frame
    body = f'<rect key="frame" x="{x}" y="{y}" width="{w}" height="{h}"/>\n'
    if arranged is not None:
        body += '<subviews>\n' + "".join(f'    {line}\n' for line in arranged.splitlines()) + '</subviews>\n'
    body += extra
    pad = " " * indent
    return (f'{pad}<stackView {attributes} translatesAutoresizingMaskIntoConstraints="NO" id="{identifier}">\n'
            + "".join(f'{pad}    {line}\n' for line in body.splitlines()) + f'{pad}</stackView>\n')


VERTICAL_LABELS = stack_label("lab-aa-aa1", (0, 0, 42, 21)) + stack_label("lab-aa-aa2", (0, 29, 42, 21), "Other")
STACKS = {
    "stack": constrained(stack(), ""),
    "stack-vertical": constrained(stack(STACK_ATTRIBUTES + ' axis="vertical"', VERTICAL_LABELS, frame=(20, 40, 42, 50)), ""),
    "stack-empty": constrained(stack(arranged=None, frame=(20, 40, 100, 50)), ""),
    "stack-one": constrained(stack(arranged=stack_label("lab-aa-aa1", (0, 0, 42, 21)), frame=(20, 40, 42, 21)), ""),
    "stack-three": constrained(stack(arranged=TWO_LABELS + stack_label("lab-aa-aa3", (100, 0, 42, 21), "Third"), frame=(20, 40, 142, 21)), ""),
    "stack-views": constrained(stack(arranged='<view contentMode="scaleToFill" id="vvv-aa-aa1">\n    <rect key="frame" x="0.0" y="0.0" width="40" height="21"/>\n</view>\n'
                                     '<view contentMode="scaleToFill" id="vvv-aa-aa2">\n    <rect key="frame" x="50" y="0.0" width="42" height="21"/>\n</view>\n'), ""),
    "stack-button": constrained(stack(arranged=button(frame=(0, 0, 46, 21)).replace(' ' * 16, '', 1) + stack_label("lab-aa-aa2", (50, 0, 42, 21))), ""),
    "stack-custom-class": constrained(stack(STACK_ATTRIBUTES + ' customClass="MyStack" customModule="T" customModuleProvider="target"'), ""),
    "stack-background": constrained(stack(extra=gray(0.5, 1) + "\n"), ""),
    "stack-hidden-arranged": constrained(stack(arranged=stack_label("lab-aa-aa1", (0, 0, 42, 21))
                                               + stack_label("lab-aa-aa2", (50, 0, 42, 21), "Other").replace('opaque="NO"', 'hidden="YES" opaque="NO"', 1)), ""),
    "stack-pinned": constrained(stack(), pinned("stk-aa-aa1", 0)),
    "stack-centered": constrained(stack(), constraint(0, "stk-aa-aa1", "centerX", ROOT, "centerX") + constraint(1, "stk-aa-aa1", "centerY", ROOT, "centerY")),
    "stack-width": constrained(stack(extra='<constraints>\n' + constraint(0, None, "width", extra=' constant="92"', indent=4) + '</constraints>\n'), ""),
    "stack-arranged-width": constrained(stack(extra='<constraints>\n' + constraint(0, "lab-aa-aa1", "width", "lab-aa-aa2", "width", indent=4)
                                              + '</constraints>\n'), ""),
    "stack-nested": constrained(stack(STACK_ATTRIBUTES + ' axis="vertical"', stack(identifier="stk-aa-aa2", frame=(0, 0, 92, 21), indent=0)
                                      + stack_label("lab-aa-aa3", (0, 29, 42, 21), "Third"), frame=(20, 40, 92, 50)), ""),
    "stack-margins-relative": constrained(stack(STACK_ATTRIBUTES + ' layoutMarginsFollowReadableWidth="YES"'), ""),
    "stack-baseline-relative": constrained(stack(STACK_ATTRIBUTES + ' baselineRelativeArrangement="YES"'), ""),
    "stack-directional-margins": constrained(stack(STACK_ATTRIBUTES,
                                                   extra='<directionalEdgeInsets key="directionalLayoutMargins" top="8" leading="16" bottom="8" trailing="16"/>\n'), ""),
    "stack-edge-margins": constrained(stack(STACK_ATTRIBUTES,
                                            extra='<edgeInsets key="layoutMargins" top="8" left="16" bottom="8" right="16"/>\n'), ""),
    "stack-spacing-type-standard": constrained(stack(STACK_ATTRIBUTES + ' spacingType="standard"'), ""),
    "stack-insets-safe-area-no": constrained(stack(STACK_ATTRIBUTES + ' insetsLayoutMarginsFromSafeArea="NO"'), ""),
    "stack-preserves-margins": constrained(stack(STACK_ATTRIBUTES + ' preservesSuperviewLayoutMargins="YES"'), ""),
    "stack-hugging": constrained(stack(STACK_ATTRIBUTES + ' verticalHuggingPriority="1000" verticalCompressionResistancePriority="1000"'), ""),
}
for spacing in ("8", "12", "0.0", "4.5", "-8"):
    STACKS[f"stack-spacing-{spacing}"] = constrained(stack(STACK_ATTRIBUTES + f' spacing="{spacing}"'), "")
for distribution in ("fill", "fillEqually", "fillProportionally", "equalSpacing", "equalCentering"):
    STACKS[f"stack-distribution-{distribution}"] = constrained(stack(STACK_ATTRIBUTES + f' distribution="{distribution}"'), "")
for alignment in ("fill", "top", "center", "bottom", "firstBaseline", "lastBaseline", "centerY"):
    STACKS[f"stack-alignment-{alignment}"] = constrained(stack(STACK_ATTRIBUTES + f' alignment="{alignment}"'), "")
for alignment in ("leading", "center", "trailing", "centerX"):
    STACKS[f"stack-vertical-alignment-{alignment}"] = constrained(stack(STACK_ATTRIBUTES + f' axis="vertical" alignment="{alignment}"',
                                                                         VERTICAL_LABELS, frame=(20, 40, 42, 50)), "")
STACKS["stack-all"] = constrained(stack(STACK_ATTRIBUTES + ' axis="vertical" distribution="equalSpacing" alignment="center" spacing="12"'
                                        ' baselineRelativeArrangement="YES"', VERTICAL_LABELS,
                                        frame=(20, 40, 42, 50)), "")
STACKS["stack-arranged-mask"] = constrained(stack(arranged=stack_label("lab-aa-aa1", (0, 0, 42, 21)).replace(
    "    <rect", '    <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>\n    <rect') + stack_label("lab-aa-aa2", (50, 0, 42, 21))), "")
STACKS["stack-arranged-image-mask"] = constrained(stack(arranged='<imageView userInteractionEnabled="NO" contentMode="scaleAspectFill" horizontalHuggingPriority="251" '
    'verticalHuggingPriority="251" image="plus" catalog="system" translatesAutoresizingMaskIntoConstraints="NO" id="img-aa-aa1">\n'
    '    <rect key="frame" x="0.0" y="0.5" width="20" height="19"/>\n    <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>\n'
    '</imageView>\n' + stack_label("lab-aa-aa2", (28, 0, 42, 21))), "", resources=BUTTON_SYMBOL)
EDGE_MARGINS = '<edgeInsets key="layoutMargins" top="1" left="2" bottom="3" right="4"/>\n'
DIRECTIONAL_MARGINS = '<directionalEdgeInsets key="directionalLayoutMargins" top="1" leading="2" bottom="3" trailing="4"/>\n'
STACKS["stack-edge-margins-zero"] = constrained(stack(extra='<edgeInsets key="layoutMargins" top="0.0" left="0.0" bottom="0.0" right="0.0"/>\n'), "")
STACKS["stack-margins-flags"] = constrained(stack(STACK_ATTRIBUTES + ' insetsLayoutMarginsFromSafeArea="NO" preservesSuperviewLayoutMargins="YES"'
                                                  ' layoutMarginsFollowReadableWidth="YES"', extra=DIRECTIONAL_MARGINS), "")
STACKS["stack-margins-hugging-constraints"] = constrained(stack(STACK_ATTRIBUTES + ' verticalHuggingPriority="1000" verticalCompressionResistancePriority="1000"',
                                                                extra=EDGE_MARGINS + '<constraints>\n' + constraint(0, None, "width", extra=' constant="92"', indent=4)
                                                                + '</constraints>\n'), "")
for name, margins in {"edge": EDGE_MARGINS, "directional": DIRECTIONAL_MARGINS,
                      "edge-zero": '<edgeInsets key="layoutMargins" top="0.0" left="0.0" bottom="0.0" right="0.0"/>\n',
                      "edge-8": '<edgeInsets key="layoutMargins" top="8" left="8" bottom="8" right="8"/>\n'}.items():
    STACKS[f"view-margins-{name}"] = constrained(subview("sss-ss-ss1").replace("                </view>", "                    " + margins + "                </view>"), "")
STACKS["view-margins-flags"] = constrained(subview("sss-ss-ss1", attributes=' insetsLayoutMarginsFromSafeArea="NO" preservesSuperviewLayoutMargins="YES"'
                                                   ' layoutMarginsFollowReadableWidth="YES"').replace("                </view>", "                    " + DIRECTIONAL_MARGINS
                                                                                                      + "                </view>"), "")
STACKS["view-insets-preserves"] = constrained(subview("sss-ss-ss1", attributes=' insetsLayoutMarginsFromSafeArea="NO" preservesSuperviewLayoutMargins="YES"'), "")
STACKS["view-readable-width"] = constrained(subview("sss-ss-ss1", attributes=' layoutMarginsFollowReadableWidth="YES"'), "")
STACKS["view-margins-top-level"] = xib(view('translatesAutoresizingMaskIntoConstraints="NO"', extra="            " + EDGE_MARGINS))
STORYBOARDS["sb-stack"] = storyboard(scene(view_extra='                        <subviews>\n' + stack(indent=28) + '                        </subviews>\n'))
STACKS["label-custom-class"] = constrained(label(LABEL_ATTRIBUTES + ' customClass="MyLabel"'), "")
STACKS["label-custom-class-module"] = constrained(label(LABEL_ATTRIBUTES + ' customClass="MyLabel" customModule="T" customModuleProvider="target"'), "")
STACKS["label-custom-class-other-module"] = constrained(label(LABEL_ATTRIBUTES + ' customClass="MyLabel" customModule="Other"'), "")
STACKS["image-view-custom-class-module"] = constrained(subview("iii-ii-ii1", (112, 333, 168, 185), "imageView",
                                                               ' image="Logo" customClass="MyImage" customModule="T" customModuleProvider="target"'), "", resources=LOGO)
EXPERIMENTS.update(STACKS)


# Round 34: scroll views, as IB writes them: an empty scroll view, then one change at a time (layout
# guides, subviews, constraints, the scroll view's attributes).
SCROLL_ATTRIBUTES = 'clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="scaleToFill"'
SCROLL_GUIDES = ('<viewLayoutGuide key="contentLayoutGuide" id="cnt-aa-aa1"/>\n'
                 '<viewLayoutGuide key="frameLayoutGuide" id="frm-aa-aa1"/>\n')


def scroll(attributes=SCROLL_ATTRIBUTES, children="", identifier="scr-aa-aa1", frame=(0, 0, 393, 852), indent=16):
    x, y, w, h = frame
    body = f'<rect key="frame" x="{x}" y="{y}" width="{w}" height="{h}"/>\n' + children
    pad = " " * indent
    return (f'{pad}<scrollView {attributes} translatesAutoresizingMaskIntoConstraints="NO" id="{identifier}">\n'
            + "".join(f'{pad}    {line}\n' for line in body.splitlines()) + f'{pad}</scrollView>\n')


SCROLL_CONTENT = ('<subviews>\n    <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="cnv-aa-aa1">\n'
                  '        <rect key="frame" x="0.0" y="0.0" width="393" height="1000"/>\n    </view>\n</subviews>\n')
SCROLLS = {
    "scroll": constrained(scroll(), ""),
    "scroll-guides": constrained(scroll(children=SCROLL_GUIDES), ""),
    "scroll-pinned": constrained(scroll(), pinned("scr-aa-aa1", 0)),
    "scroll-subview": constrained(scroll(children=SCROLL_CONTENT), ""),
    "scroll-subview-guides": constrained(scroll(children=SCROLL_CONTENT + SCROLL_GUIDES), ""),
    "scroll-content-pinned": constrained(scroll(children=SCROLL_CONTENT + '<constraints>\n'
                                                + "".join(constraint(10 + k, "cnv-aa-aa1", a, "scr-aa-aa1", a, indent=4) for k, a in enumerate(EDGES))
                                                + constraint(14, "cnv-aa-aa1", "width", "scr-aa-aa1", "width", indent=4) + '</constraints>\n'),
                                         pinned("scr-aa-aa1", 0)),
    "scroll-content-guides-pinned": constrained(scroll(children=SCROLL_CONTENT + SCROLL_GUIDES + '<constraints>\n'
                                                       + "".join(constraint(10 + k, "cnv-aa-aa1", a, "cnt-aa-aa1", a, indent=4) for k, a in enumerate(EDGES))
                                                       + constraint(14, "cnv-aa-aa1", "width", "frm-aa-aa1", "width", indent=4) + '</constraints>\n'),
                                                pinned("scr-aa-aa1", 0)),
    "scroll-custom-class": constrained(scroll(SCROLL_ATTRIBUTES + ' customClass="MyScroll" customModule="T" customModuleProvider="target"'), ""),
    "scroll-background": constrained(scroll(children=gray(0.5, 1) + "\n"), ""),
}
for flag in ('showsHorizontalScrollIndicator="NO"', 'showsVerticalScrollIndicator="NO"', 'alwaysBounceVertical="YES"', 'alwaysBounceHorizontal="YES"',
             'directionalLockEnabled="YES"', 'keyboardDismissMode="interactive"', 'keyboardDismissMode="onDrag"', 'delaysContentTouches="NO"',
             'canCancelContentTouches="NO"', 'pagingEnabled="YES"', 'bounces="NO"', 'bouncesZoom="NO"', 'scrollEnabled="NO"',
             'contentInsetAdjustmentBehavior="never"', 'contentInsetAdjustmentBehavior="always"', 'contentInsetAdjustmentBehavior="scrollableAxes"',
             'indicatorStyle="white"', 'indicatorStyle="black"', 'minimumZoomScale="0.5"', 'maximumZoomScale="3"', 'insetsLayoutMarginsFromSafeArea="NO"',
             'automaticallyAdjustsScrollIndicatorInsets="NO"', 'scrollsToTop="NO"'):
    name, value = flag.split("=")
    SCROLLS[f"scroll-{name}-{value.strip(chr(34))}"] = constrained(scroll(f"{SCROLL_ATTRIBUTES} {flag}"), "")
SCROLLS["scroll-flags"] = constrained(scroll(SCROLL_ATTRIBUTES + ' showsHorizontalScrollIndicator="NO" showsVerticalScrollIndicator="NO" alwaysBounceVertical="YES"'
                                             ' alwaysBounceHorizontal="YES" directionalLockEnabled="YES" keyboardDismissMode="interactive"'
                                             ' delaysContentTouches="NO" canCancelContentTouches="NO" pagingEnabled="YES" bounces="NO" bouncesZoom="NO"'
                                             ' scrollEnabled="NO" contentInsetAdjustmentBehavior="never" indicatorStyle="white" minimumZoomScale="0.5"'
                                             ' maximumZoomScale="3"'), "")
SCROLLS["scroll-guides-constraints"] = constrained(scroll(children=SCROLL_CONTENT + SCROLL_GUIDES + '<constraints>\n'
                                                     + "".join(constraint(10 + k, "cnv-aa-aa1", a, "scr-aa-aa1", a, indent=4) for k, a in enumerate(EDGES))
                                                     + '</constraints>\n'), pinned("scr-aa-aa1", 0))
STORYBOARDS["sb-scroll"] = storyboard(scene(view_extra='                        <subviews>\n' + scroll(children=SCROLL_CONTENT + SCROLL_GUIDES, indent=28)
                                            + '                        </subviews>\n'))
EXPERIMENTS.update(SCROLLS)


# Round 35: collection view cells and reusable views in xibs, as Xcode's templates write them (the
# content view element of Xcode 12 on, and the plain `view` before it with a custom size and a safe
# area), then one change at a time: subviews, constraints in the content view or in the cell,
# reuse identifiers, colors, classes, outlets.
CV_CELL = "gTV-IL-0wX"
CV_CONTENT = "ZTg-uK-7eu"
CV_CLASS = ' customClass="Cell" customModule="T" customModuleProvider="target"'


def cv_cell(content="", cell_extra="", attributes=CV_CLASS, old=False, size=(50, 50), content_attributes=' insetsLayoutMarginsFromSafeArea="NO"'):
    w, h = size
    if old:
        content_element = (f'            <view key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center">\n'
                           f'                <rect key="frame" x="0.0" y="0.0" width="{w}" height="{h}"/>\n'
                           '                <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>\n'
                           f'{content}            </view>\n')
    else:
        content_element = (f'            <collectionViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" '
                           f'contentMode="center"{content_attributes} id="{CV_CONTENT}">\n'
                           f'                <rect key="frame" x="0.0" y="0.0" width="{w}" height="{h}"/>\n'
                           '                <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>\n'
                           f'{content}            </collectionViewCellContentView>\n')
    return xib(f'        <collectionViewCell opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center"{attributes} id="{CV_CELL}">\n'
               f'            <rect key="frame" x="0.0" y="0.0" width="{w}" height="{h}"/>\n'
               '            <autoresizingMask key="autoresizingMask"/>\n'
               f'{content_element}{cell_extra}'
               '            <point key="canvasLocation" x="0" y="0"/>\n        </collectionViewCell>\n')


CV_LABEL = ('                <subviews>\n' + label(frame=(4, 14, 42, 21)).replace('                ', '                    ') + '                </subviews>\n')
OLD_EXTRA = (f'            <viewLayoutGuide key="safeArea" id="sfa-aa-aa1"/>\n'
             '            <size key="customSize" width="50" height="50"/>\n')


def cv_constraints(container, indent=12):
    pad = " " * indent
    return (f'{pad}<constraints>\n' + "".join(constraint(k, "lll-ll-ll1" if a in ("top", "leading") else container, a,
                                                          container if a in ("top", "leading") else "lll-ll-ll1", a, indent=indent + 4)
                                              for k, a in enumerate(EDGES)) + f'{pad}</constraints>\n')


CV_OUTLET = '            <connections>\n                <outlet property="title" destination="lll-ll-ll1" id="out-aa-aa1"/>\n            </connections>\n'
CV_CELLS = {
    "cvcell": cv_cell(),
    "cvcell-no-class": cv_cell(attributes=""),
    "cvcell-reuse": cv_cell(attributes=' reuseIdentifier="Cell"' + CV_CLASS),
    "cvcell-size": cv_cell(size=(120, 80)),
    "cvcell-background": cv_cell(cell_extra="            " + gray(0.5, 1) + "\n"),
    "cvcell-content-background": cv_cell(content="                " + gray(0.5, 1) + "\n"),
    "cvcell-content-insets": cv_cell(content_attributes=""),
    "cvcell-label": cv_cell(CV_LABEL),
    "cvcell-label-content-constraints": cv_cell(CV_LABEL + cv_constraints(CV_CONTENT, 16)),
    "cvcell-label-cell-constraints": cv_cell(CV_LABEL, cv_constraints(CV_CELL)),
    "cvcell-outlet": cv_cell(CV_LABEL, CV_OUTLET),
    "cvcell-safe-area": cv_cell(cell_extra='            <viewLayoutGuide key="safeArea" id="sfa-aa-aa1"/>\n'),
    "cvcell-old": cv_cell(old=True, cell_extra=OLD_EXTRA),
    "cvcell-old-no-size": cv_cell(old=True),
    "cvcell-old-label": cv_cell(CV_LABEL, OLD_EXTRA, old=True),
    "cvcell-old-label-cell-constraints": cv_cell(CV_LABEL, OLD_EXTRA + cv_constraints(CV_CELL), old=True),
    "cvcell-old-outlet": cv_cell(CV_LABEL, OLD_EXTRA + CV_OUTLET, old=True),
}
CV_CELLS["cvcell-old-label-cell-constraints"] = CV_CELLS["cvcell-old-label-cell-constraints"].replace(
    ' useTraitCollections="YES"', ' useTraitCollections="YES" useSafeAreas="YES"').replace(
    '        <capability name="documents saved', SAFE_AREA_CAPABILITY + '        <capability name="documents saved')
CV_CELLS["cvcell-content-mask-empty"] = cv_cell(CV_LABEL + cv_constraints(CV_CONTENT, 16)).replace(
    '<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>', '<autoresizingMask key="autoresizingMask"/>', 1)
CV_CELLS["cvcell-old-content-mask-empty"] = cv_cell(CV_LABEL, '            <size key="customSize" width="50" height="50"/>\n', old=True).replace(
    '<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>', '<autoresizingMask key="autoresizingMask"/>', 1)
CV_CELLS["cvcell-old-content-mask-width"] = cv_cell("", old=True).replace(
    '<autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>', '<autoresizingMask key="autoresizingMask" widthSizable="YES"/>', 1)
CV_CELLS["cvcell-old-label-no-safe-area"] = cv_cell(CV_LABEL, '            <size key="customSize" width="50" height="50"/>\n', old=True)
CV_CELLS["cvcell-old-label-cell-constraints-no-safe-area"] = cv_cell(CV_LABEL, '            <size key="customSize" width="50" height="50"/>\n'
                                                                     + cv_constraints(CV_CELL), old=True)
CV_CELLS["cvcell-old-height"] = cv_cell("", OLD_EXTRA + '            <constraints>\n' + constraint(0, None, "height", extra=' constant="50"', indent=16)
                                        + '            </constraints>\n', old=True)
CV_CELLS["cvcell-safe-area-label"] = cv_cell(CV_LABEL + cv_constraints(CV_CONTENT, 16), '            <viewLayoutGuide key="safeArea" id="sfa-aa-aa1"/>\n')
CV_CELLS["cvcell-old-two-labels"] = cv_cell(CV_LABEL.replace("                </subviews>\n", label(identifier="lll-ll-ll2", frame=(4, 0, 42, 10)).replace(
    '                ', '                    ') + "                </subviews>\n"), OLD_EXTRA + cv_constraints(CV_CELL), old=True)
for name in ("cvcell-safe-area", "cvcell-old", "cvcell-old-label", "cvcell-old-outlet", "cvcell-old-height", "cvcell-safe-area-label", "cvcell-old-two-labels"):
    CV_CELLS[name] = CV_CELLS[name].replace(' useTraitCollections="YES"', ' useTraitCollections="YES" useSafeAreas="YES"').replace(
        '        <capability name="documents saved', SAFE_AREA_CAPABILITY + '        <capability name="documents saved')


def reusable(content="", extra="", attributes=' customClass="Header" customModule="T" customModuleProvider="target"'):
    return xib(f'        <collectionReusableView opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center"{attributes} id="U6b-Vx-4bR">\n'
               '            <rect key="frame" x="0.0" y="0.0" width="320" height="50"/>\n'
               '            <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>\n'
               f'{content.replace("                    ", "                ")}{extra}'
               '            <point key="canvasLocation" x="0" y="0"/>\n        </collectionReusableView>\n')


CV_CELLS.update({
    "reusable": reusable(),
    "reusable-no-class": reusable(attributes=""),
    "reusable-reuse": reusable(attributes=' reuseIdentifier="Header" customClass="Header" customModule="T" customModuleProvider="target"'),
    "reusable-label": reusable(CV_LABEL),
    "reusable-label-constraints": reusable(CV_LABEL, cv_constraints("U6b-Vx-4bR")),
    "reusable-background": reusable(extra="            " + gray(0.5, 1) + "\n"),
})
EXPERIMENTS.update(CV_CELLS)


# Round 36: activity indicators, segmented controls, progress views, page controls and sliders, as
# IB writes them, then one change at a time.
def control(tag, attributes, children="", identifier="ctl-aa-aa1", frame=(20, 40, 100, 30)):
    x, y, w, h = frame
    body = f'<rect key="frame" x="{x}" y="{y}" width="{w}" height="{h}"/>\n' + children
    return (f'                <{tag} {attributes} translatesAutoresizingMaskIntoConstraints="NO" id="{identifier}">\n'
            + "".join(f'                    {line}\n' for line in body.splitlines()) + f'                </{tag}>\n')


ACTIVITY = 'opaque="NO" contentMode="scaleToFill" horizontalHuggingPriority="750" verticalHuggingPriority="750" style="medium"'
SEGMENTED = ('opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="left" contentVerticalAlignment="top" segmentControlStyle="plain" '
             'selectedSegmentIndex="0"')
SEGMENTS = '<segments>\n    <segment title="First"/>\n    <segment title="Second"/>\n</segments>\n'
PROGRESS = 'opaque="NO" contentMode="scaleToFill" verticalHuggingPriority="750" progress="0.5"'
PAGE = 'opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" numberOfPages="3"'
SLIDER = 'opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" value="0.5" minValue="0.0" maxValue="1"'
CONTROLS2 = {
    "activity": constrained(control("activityIndicatorView", ACTIVITY, frame=(20, 40, 20, 20)), ""),
    "activity-custom-class": constrained(control("activityIndicatorView", ACTIVITY + ' customClass="Spinner" customModule="T" customModuleProvider="target"',
                                                 frame=(20, 40, 20, 20)), ""),
    "activity-color": constrained(control("activityIndicatorView", ACTIVITY, rgb(1, 0.5, 0.25, 1).replace("backgroundColor", "color") + "\n",
                                          frame=(20, 40, 20, 20)), ""),
    "activity-flags": constrained(control("activityIndicatorView", ACTIVITY.replace('style="medium"', 'hidesWhenStopped="YES" animating="YES" style="medium"')
                                          + ' hidden="YES"', frame=(20, 40, 20, 20)), ""),
    "segmented": constrained(control("segmentedControl", SEGMENTED, SEGMENTS, frame=(20, 40, 121, 32)), ""),
    "segmented-three": constrained(control("segmentedControl", SEGMENTED.replace('"0"', '"1"'), SEGMENTS.replace(
        '</segments>', '    <segment title="Third"/>\n</segments>'), frame=(20, 40, 180, 32)), ""),
    "segmented-tints": constrained(control("segmentedControl", SEGMENTED, SEGMENTS + rgb(0.2, 0.4, 0.6, 1).replace("backgroundColor", "tintColor") + "\n"
                                           + gray(1, 1).replace("backgroundColor", "selectedSegmentTintColor") + "\n", frame=(20, 40, 121, 32)), ""),
    "segmented-apportions": constrained(control("segmentedControl", SEGMENTED + ' apportionsSegmentWidthsByContent="YES"', SEGMENTS,
                                                frame=(20, 40, 121, 32)), ""),
    "segmented-momentary": constrained(control("segmentedControl", SEGMENTED.replace(' selectedSegmentIndex="0"', '') + ' momentary="YES"', SEGMENTS,
                                               frame=(20, 40, 121, 32)), ""),
    "segmented-no-selection": constrained(control("segmentedControl", SEGMENTED.replace(' selectedSegmentIndex="0"', ''), SEGMENTS,
                                                  frame=(20, 40, 121, 32)), ""),
    "segmented-selected": constrained(control("segmentedControl", SEGMENTED + ' selected="YES"', SEGMENTS, frame=(20, 40, 121, 32)), ""),
    "segmented-enabled-no": constrained(control("segmentedControl", SEGMENTED, '<segments>\n    <segment title="First"/>\n    <segment title="Second" enabled="NO"/>\n'
                                                '</segments>\n', frame=(20, 40, 121, 32)), ""),
    "segmented-width": constrained(control("segmentedControl", SEGMENTED, '<segments>\n    <segment title="First" width="80"/>\n    <segment title="Second"/>\n'
                                           '</segments>\n', frame=(20, 40, 160, 32)), ""),
    "progress": constrained(control("progressView", PROGRESS, frame=(20, 40, 150, 4)), ""),
    "progress-bar": constrained(control("progressView", PROGRESS + ' progressViewStyle="bar"', frame=(20, 40, 150, 2.5)), ""),
    "progress-tints": constrained(control("progressView", PROGRESS, rgb(0.2, 0.4, 0.6, 1).replace("backgroundColor", "progressTintColor") + "\n"
                                          + gray(0.5, 1).replace("backgroundColor", "trackTintColor") + "\n", frame=(20, 40, 150, 4)), ""),
    "progress-zero": constrained(control("progressView", PROGRESS.replace(' progress="0.5"', ''), frame=(20, 40, 150, 4)), ""),
    "page": constrained(control("pageControl", PAGE, frame=(20, 40, 115, 26)), ""),
    "page-current": constrained(control("pageControl", PAGE + ' currentPage="1"', frame=(20, 40, 115, 26)), ""),
    "page-hides": constrained(control("pageControl", PAGE + ' hidesForSinglePage="YES"', frame=(20, 40, 115, 26)), ""),
    "page-tints": constrained(control("pageControl", PAGE, gray(0.5, 1).replace("backgroundColor", "pageIndicatorTintColor") + "\n"
                                      + rgb(0.2, 0.4, 0.6, 1).replace("backgroundColor", "currentPageIndicatorTintColor") + "\n", frame=(20, 40, 115, 26)), ""),
    "slider": constrained(control("slider", SLIDER, frame=(20, 40, 118, 31)), ""),
    "slider-range": constrained(control("slider", SLIDER.replace('value="0.5" minValue="0.0" maxValue="1"', 'value="20" minValue="1" maxValue="100"'),
                                        frame=(20, 40, 118, 31)), ""),
    "slider-continuous-no": constrained(control("slider", SLIDER + ' continuous="NO"', frame=(20, 40, 118, 31)), ""),
    "slider-tints": constrained(control("slider", SLIDER, rgb(0.2, 0.4, 0.6, 1).replace("backgroundColor", "tintColor") + "\n"
                                        + gray(0.5, 1).replace("backgroundColor", "thumbTintColor") + "\n", frame=(20, 40, 118, 31)), ""),
    "slider-image": constrained(control("slider", SLIDER + ' minimumValueImage="Logo"', frame=(20, 40, 118, 31)), "", resources=BUTTON_IMAGE),
}
CONTROLS2["activity-animating-shows"] = constrained(control("activityIndicatorView", ACTIVITY.replace('style="medium"', 'hidesWhenStopped="NO" animating="YES" style="medium"'),
                                                     frame=(20, 40, 20, 20)), "")
CONTROLS2["activity-white-color"] = constrained(control("activityIndicatorView", ACTIVITY.replace('"medium"', '"whiteLarge"'),
                                                        rgb(1, 0.5, 0.25, 1).replace("backgroundColor", "color") + "\n", frame=(20, 40, 37, 37)), "")
CONTROLS2["activity-hugging"] = constrained(control("activityIndicatorView", ACTIVITY.replace('horizontalHuggingPriority="750"', 'horizontalHuggingPriority="765"'),
                                                    frame=(20, 40, 20, 20)), "")
CONTROLS2["activity-no-hugging"] = constrained(control("activityIndicatorView", ACTIVITY.replace(' horizontalHuggingPriority="750" verticalHuggingPriority="750"', ''),
                                                       frame=(20, 40, 20, 20)), "")
CONTROLS2["progress-no-hugging"] = constrained(control("progressView", PROGRESS.replace(' verticalHuggingPriority="750"', ''), frame=(20, 40, 150, 4)), "")
CONTROLS2["segmented-one"] = constrained(control("segmentedControl", SEGMENTED, '<segments>\n    <segment title="First"/>\n</segments>\n', frame=(20, 40, 60, 32)), "")
CONTROLS2["segmented-four-last"] = constrained(control("segmentedControl", SEGMENTED.replace('"0"', '"3"'), SEGMENTS.replace(
    '</segments>', '    <segment title="Third"/>\n    <segment title="Fourth"/>\n</segments>'), frame=(20, 40, 240, 32)), "")
CONTROLS2["slider-all"] = constrained(control("slider", SLIDER.replace('value="0.5" minValue="0.0" maxValue="1"', 'value="20" minValue="1" maxValue="100"')
                                              + ' continuous="NO" minimumValueImage="Logo" maximumValueImage="Logo"',
                                              rgb(0.2, 0.4, 0.6, 1).replace("backgroundColor", "minimumTrackTintColor") + "\n"
                                              + gray(0.5, 1).replace("backgroundColor", "maximumTrackTintColor") + "\n"
                                              + gray(1, 1).replace("backgroundColor", "thumbTintColor") + "\n", frame=(20, 40, 118, 31)), "", resources=BUTTON_IMAGE)
CONTROLS2["page-all"] = constrained(control("pageControl", PAGE + ' currentPage="2" hidesForSinglePage="YES" defersCurrentPageDisplay="YES"',
                                            gray(0.5, 1).replace("backgroundColor", "pageIndicatorTintColor") + "\n"
                                            + rgb(0.2, 0.4, 0.6, 1).replace("backgroundColor", "currentPageIndicatorTintColor") + "\n", frame=(20, 40, 115, 26)), "")
for height in (1, 2, 3, 3.5, 4.5, 5, 6, 7, 8, 10, 12, 20):
    CONTROLS2[f"progress-height-{height}"] = constrained(control("progressView", PROGRESS, frame=(20, 40, 150, height)), "")
    CONTROLS2[f"progress-bar-height-{height}"] = constrained(control("progressView", PROGRESS + ' progressViewStyle="bar"', frame=(20, 40, 150, height)), "")
for height in (20, 28, 31, 33, 42, 60):
    CONTROLS2[f"segmented-height-{height}"] = constrained(control("segmentedControl", SEGMENTED, SEGMENTS, frame=(20, 40, 121, height)), "")
NAMES6 = ["S0", "S1", "S2", "S3", "S4", "S5"]
for count in range(2, 7):
    for selected in sorted({-1, 0, count // 2, count - 1}):
        segments = "<segments>\n" + "".join(f'    <segment title="{name}"/>\n' for name in NAMES6[:count]) + "</segments>\n"
        attributes = SEGMENTED.replace(' selectedSegmentIndex="0"', '' if selected < 0 else f' selectedSegmentIndex="{selected}"')
        CONTROLS2[f"segmented-positions-{count}-{selected}"] = constrained(control("segmentedControl", attributes, segments, frame=(20, 40, 60 * count, 32)), "")
for style in ("large", "white", "whiteLarge", "gray"):
    CONTROLS2[f"activity-style-{style}"] = constrained(control("activityIndicatorView", ACTIVITY.replace('"medium"', f'"{style}"'), frame=(20, 40, 37, 37)), "")
EXPERIMENTS.update(CONTROLS2)


# Round 37: header features of the corpus's documents: customObjectInstantitationMethod, inferred
# metrics tie breakers naming segues.
HEADERS2 = {
    "header-instantiation-direct": BASE.replace(' colorMatched="YES">', ' customObjectInstantitationMethod="direct" colorMatched="YES">'),
}
TIE_BREAKERS = '    <inferredMetricsTieBreakers>\n        <segue reference="seg-aa-aa1"/>\n    </inferredMetricsTieBreakers>\n'
STORYBOARDS["sb-instantiation-direct"] = STORYBOARD.replace(' colorMatched="YES"', ' customObjectInstantitationMethod="direct" colorMatched="YES"', 1)
STORYBOARDS["sb-tie-breakers"] = STORYBOARDS["sb-segue-show"].replace("</document>\n", "") + TIE_BREAKERS + "</document>\n"
SUB_SAFE = '                    <viewLayoutGuide key="safeArea" id="ssa-aa-aa1"/>\n'
INNER = ('                    <subviews>\n                        <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="inn-aa-aa1">\n'
         '                            <rect key="frame" x="10" y="10" width="50" height="20"/>\n                        </view>\n                    </subviews>\n')
HEADERS2["subview-safe-area"] = constrained(subview("sss-ss-ss1").replace("                </view>", SUB_SAFE + "                </view>"), "", safe=True)
HEADERS2["subview-safe-area-inner"] = constrained(subview("sss-ss-ss1").replace("                </view>", INNER + SUB_SAFE + "                </view>"), "", safe=True)
HEADERS2["subview-safe-area-constrained"] = constrained(subview("sss-ss-ss1").replace(
    "                </view>", INNER + SUB_SAFE + '                    <constraints>\n'
    + constraint(10, "inn-aa-aa1", "top", "ssa-aa-aa1", "top", ' constant="10"', indent=24)
    + constraint(11, "inn-aa-aa1", "leading", "ssa-aa-aa1", "leading", ' constant="10"', indent=24) + '                    </constraints>\n                </view>'), "", safe=True)
HEADERS2["cvcell-old-content-insets"] = CV_CELLS["cvcell-old"].replace('contentMode="center">\n                <rect', 'contentMode="center" insetsLayoutMarginsFromSafeArea="NO">\n                <rect', 1)
HEADERS2["cvcell-old-content-insets-label"] = CV_CELLS["cvcell-old-label"].replace('contentMode="center">\n                <rect', 'contentMode="center" insetsLayoutMarginsFromSafeArea="NO">\n                <rect', 1)
HEADERS2["cvcell-insets"] = CV_CELLS["cvcell"].replace('contentMode="center" customClass', 'contentMode="center" insetsLayoutMarginsFromSafeArea="NO" customClass', 1)
STORYBOARDS["sb-subview-safe-area"] = storyboard(scene(view_extra=SUBVIEW.replace(
    "                            </view>", '                                <viewLayoutGuide key="safeArea" id="ssa-aa-aa1"/>\n                            </view>')
    + SAFE_AREA), attributes=' useSafeAreas="YES"', capabilities=SAFE_AREA_CAPABILITY)
EXPERIMENTS.update(HEADERS2)


# Round 38: visual effect views, as IB writes them: a blur with its content view, then one change at
# a time (blur styles, subviews and constraints in the content view, colors, classes).
def effect_view(effect='<blurEffect style="regular"/>', content="", attributes='contentMode="scaleToFill"', content_attributes="", frame=(20, 40, 200, 100)):
    x, y, w, h = frame
    return (f'                <visualEffectView {attributes} translatesAutoresizingMaskIntoConstraints="NO" id="vev-aa-aa1">\n'
            f'                    <rect key="frame" x="{x}" y="{y}" width="{w}" height="{h}"/>\n'
            f'                    <view key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center"{content_attributes} id="vec-aa-aa1">\n'
            f'                        <rect key="frame" x="0.0" y="0.0" width="{w}" height="{h}"/>\n'
            '                        <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>\n'
            f'{content}                    </view>\n                    {effect}\n                </visualEffectView>\n')


EFFECT_LABEL = ('                        <subviews>\n' + label(frame=(10, 10, 42, 21)).replace('                ', '                            ')
                + '                        </subviews>\n')
EFFECTS = {
    "effect": constrained(effect_view(), ""),
    "effect-pinned": constrained(effect_view(), pinned("vev-aa-aa1", 0)),
    "effect-label": constrained(effect_view(content=EFFECT_LABEL), ""),
    "effect-label-constraints": constrained(effect_view(content=EFFECT_LABEL + '                        <constraints>\n'
                                                        + constraint(10, "lll-ll-ll1", "top", "vec-aa-aa1", "top", ' constant="10"', indent=28)
                                                        + constraint(11, "lll-ll-ll1", "leading", "vec-aa-aa1", "leading", ' constant="10"', indent=28)
                                                        + '                        </constraints>\n'), ""),
    "effect-flags": constrained(effect_view(attributes='userInteractionEnabled="NO" contentMode="scaleAspectFill"'), ""),
    "effect-custom-class": constrained(effect_view(attributes='contentMode="scaleToFill" customClass="Footer" customModule="T" customModuleProvider="target"'), ""),
    "effect-content-margins": constrained(effect_view(content='                        <edgeInsets key="layoutMargins" top="8" left="8" bottom="8" right="8"/>\n'), ""),
    "effect-vibrancy": constrained(effect_view(effect='<vibrancyEffect>\n                        <blurEffect style="regular"/>\n                    </vibrancyEffect>'), ""),
}
for style in ("extraLight", "light", "dark", "prominent", "systemMaterial", "systemThinMaterial", "systemUltraThinMaterial", "systemChromeMaterial",
              "systemThickMaterial", "systemMaterialDark"):
    EFFECTS[f"effect-style-{style}"] = constrained(effect_view(f'<blurEffect style="{style}"/>'), "")
EXPERIMENTS.update(EFFECTS)


# Round 39: user-defined runtime attributes, of each type the corpus uses, on views, labels, buttons
# and image views; several on one object and on several objects; key paths with dots.
def runtime(*attributes):
    return '<userDefinedRuntimeAttributes>\n' + "".join(f'    {a}\n' for a in attributes) + '</userDefinedRuntimeAttributes>\n'


def udra(key_path, kind, value=None, child=None):
    value_attribute = f' value="{value}"' if value is not None else ""
    if child is None:
        return f'<userDefinedRuntimeAttribute type="{kind}" keyPath="{key_path}"{value_attribute}/>'
    return f'<userDefinedRuntimeAttribute type="{kind}" keyPath="{key_path}"{value_attribute}>\n        {child}\n    </userDefinedRuntimeAttribute>'


def with_runtime(attributes, identifier="sss-ss-ss1", tag="view", subview_attributes=""):
    return subview(identifier, tag=tag, attributes=subview_attributes).replace(f"                </{tag}>", "".join(
        f"                    {line}\n" for line in attributes.splitlines()) + f"                </{tag}>")


RADIUS = udra("layer.cornerRadius", "number", child='<integer key="value" value="8"/>')
UDRAS = {
    "udra-integer": constrained(with_runtime(runtime(RADIUS)), ""),
    "udra-real": constrained(with_runtime(runtime(udra("layer.cornerRadius", "number", child='<real key="value" value="0.5"/>'))), ""),
    "udra-real-whole": constrained(with_runtime(runtime(udra("layer.cornerRadius", "number", child='<real key="value" value="4"/>'))), ""),
    "udra-integer-large": constrained(with_runtime(runtime(udra("count", "number", child='<integer key="value" value="70000"/>'))), ""),
    "udra-integer-negative": constrained(with_runtime(runtime(udra("count", "number", child='<integer key="value" value="-3"/>'))), ""),
    "udra-string": constrained(with_runtime(runtime(udra("ibEnaStyle", "string", "title1"))), ""),
    "udra-string-empty": constrained(with_runtime(runtime(udra("ibEnaStyle", "string", ""))), ""),
    "udra-boolean-yes": constrained(with_runtime(runtime(udra("layer.masksToBounds", "boolean", "YES"))), ""),
    "udra-boolean-no": constrained(with_runtime(runtime(udra("layer.masksToBounds", "boolean", "NO"))), ""),
    "udra-color": constrained(with_runtime(runtime(udra("borderColor", "color", child=rgb(1, 0.5, 0.25, 1).replace("backgroundColor", "value")))), ""),
    "udra-color-system": constrained(with_runtime(runtime(udra("borderColor", "color", child='<color key="value" systemColor="systemRedColor"/>'))), "",
                                     resources=system_color("systemRedColor", gray(0, 1))),
    "udra-color-gray": constrained(with_runtime(runtime(udra("borderColor", "color", child=gray(0.5, 1).replace("backgroundColor", "value")))), ""),
    "udra-size": constrained(with_runtime(runtime(udra("shadowOffset", "size", child='<size key="value" width="0.0" height="2"/>'))), ""),
    "udra-image": constrained(with_runtime(runtime(udra("imageNormal", "image", "Logo"))), "", resources=BUTTON_IMAGE),
    "udra-image-symbol": constrained(with_runtime(runtime(udra("imageNormal", "image", "plus").replace('/>', ' catalog="system"/>'))), "", resources=BUTTON_SYMBOL),
    "udra-three": constrained(with_runtime(runtime(RADIUS, udra("layer.masksToBounds", "boolean", "YES"),
                                                   udra("borderWidth", "number", child='<real key="value" value="1.5"/>'))), ""),
    "udra-three-reversed": constrained(with_runtime(runtime(udra("borderWidth", "number", child='<real key="value" value="1.5"/>'),
                                                            udra("layer.masksToBounds", "boolean", "YES"), RADIUS)), ""),
    "udra-two-views": constrained(with_runtime(runtime(RADIUS)) + with_runtime(runtime(udra("ibEnaStyle", "string", "body")), "sss-ss-ss2"), ""),
    "udra-two-views-same": constrained(with_runtime(runtime(RADIUS)) + with_runtime(runtime(RADIUS), "sss-ss-ss2"), ""),
    "udra-root": constrained("", "").replace('            <point key="canvasLocation"', "".join(
        f"            {line}\n" for line in runtime(RADIUS).splitlines()) + '            <point key="canvasLocation"'),
    "udra-label": constrained(label(extra=runtime(udra("ibEnaStyle", "string", "title1"))), ""),
    "udra-button": constrained(button(children=BUTTON_STATE + runtime(RADIUS)), ""),
    "udra-image-view": constrained(with_runtime(runtime(RADIUS), "iii-ii-ii1", "imageView", ' image="Logo"'), "", resources=BUTTON_IMAGE),
    "udra-with-outlet": with_outlets(outlet("view", ROOT, 0)).replace('            <point key="canvasLocation"', "".join(
        f"            {line}\n" for line in runtime(RADIUS).splitlines()) + '            <point key="canvasLocation"', 1),
    "udra-owner": constrained(with_runtime(runtime(RADIUS)), "").replace(
        'userLabel="File\'s Owner"/>', 'userLabel="File\'s Owner">\n            ' + runtime(udra("title", "string", "Hi")).replace("\n", "\n            ").rstrip() + '\n        </placeholder>'),
}
UDRAS["udra-bool-int-one"] = constrained(with_runtime(runtime(udra("a", "boolean", "YES"), udra("b", "number", child='<integer key="value" value="1"/>'),
                                                           udra("c", "number", child='<real key="value" value="1"/>'))), "")
UDRAS["udra-label-real-17"] = constrained(label(extra=runtime(udra("size", "number", child='<real key="value" value="17"/>'))), "")
UDRAS["udra-button-int-zero"] = constrained(button(children=BUTTON_STATE + runtime(udra("index", "number", child='<integer key="value" value="0"/>'))), "")
UDRAS["udra-same-string"] = constrained(with_runtime(runtime(udra("ibEnaStyle", "string", "ibEnaStyle"))), "")
UDRAS["udra-parent-child"] = constrained(with_runtime(runtime(udra("child", "string", "c"))), "").replace('            <point key="canvasLocation"', "".join(
    f"            {line}\n" for line in runtime(udra("parent", "string", "p")).splitlines()) + '            <point key="canvasLocation"')
UDRAS["udra-siblings-nested"] = constrained(with_runtime(runtime(udra("first", "string", "a"))).replace(
    '                    <userDefinedRuntimeAttributes>', '                    <subviews>\n                        <view contentMode="scaleToFill" id="nst-aa-aa1">\n'
    '                            <rect key="frame" x="0" y="0" width="10" height="10"/>\n                            <userDefinedRuntimeAttributes>\n'
    '                                <userDefinedRuntimeAttribute type="string" keyPath="nested" value="n"/>\n                            </userDefinedRuntimeAttributes>\n'
    '                        </view>\n                    </subviews>\n                    <userDefinedRuntimeAttributes>')
    + with_runtime(runtime(udra("second", "string", "b")), "sss-ss-ss2"), "")
UDRAS["udra-lproj"] = UDRAS["udra-string"]
LPROJ_XIBS.add("udra-lproj")
STORYBOARDS["sb-udra"] = storyboard(scene(view_extra=SUBVIEW.replace("                            </view>", "".join(
    f"                                {line}\n" for line in runtime(RADIUS).splitlines()) + "                            </view>")))
STORYBOARDS["sb-udra-controller"] = storyboard(scene(attributes=' customClass="ViewController" customModule="T" customModuleProvider="target"').replace(
    '                    <view key="view"', "".join(f"                    {line}\n" for line in runtime(udra("title2", "string", "Hi")).splitlines())
    + '                    <view key="view"'))
EXPERIMENTS.update(UDRAS)


# Round 40: accessibility configurations, as IB writes them: labels, hints, identifiers, isElement
# and traits, on views, labels, buttons and image views, one or several objects.
def accessibility(attributes="", children=""):
    head = f'<accessibility key="accessibilityConfiguration"{attributes}'
    if not children:
        return head + '/>\n'
    return head + '>\n' + "".join(f'    {line}\n' for line in children.splitlines()) + '</accessibility>\n'


ELEMENT_YES = '<bool key="isElement" value="YES"/>\n'
ACCESSIBILITY = {
    "a11y-label": constrained(with_runtime(accessibility(' label="Close"')), ""),
    "a11y-hint": constrained(with_runtime(accessibility(' hint="Closes the player"')), ""),
    "a11y-identifier": constrained(with_runtime(accessibility(' identifier="close"')), ""),
    "a11y-all": constrained(with_runtime(accessibility(' identifier="close" label="Close" hint="Closes"', ELEMENT_YES
                                                       + '<accessibilityTraits key="traits" button="YES"/>\n')), ""),
    "a11y-element-yes": constrained(with_runtime(accessibility("", ELEMENT_YES)), ""),
    "a11y-element-no": constrained(with_runtime(accessibility("", '<bool key="isElement" value="NO"/>\n')), ""),
    "a11y-empty": constrained(with_runtime(accessibility()), ""),
    "a11y-label-element": constrained(label(extra=accessibility(' label="Title"', ELEMENT_YES)), ""),
    "a11y-button": constrained(button(children=BUTTON_STATE + accessibility(' label="Play"')), ""),
    "a11y-image-view": constrained(with_runtime(accessibility(' label="Logo"', ELEMENT_YES + '<accessibilityTraits key="traits" image="YES"/>\n'),
                                                "iii-ii-ii1", "imageView", ' image="Logo"'), "", resources=BUTTON_IMAGE),
    "a11y-two": constrained(with_runtime(accessibility(' label="A"')) + with_runtime(accessibility(' label="B"'), "sss-ss-ss2"), ""),
    "a11y-parent-child": constrained(with_runtime(accessibility(' label="child"')), "").replace('            <point key="canvasLocation"',
                                     "".join(f"            {line}\n" for line in accessibility(' label="parent"').splitlines()) + '            <point key="canvasLocation"'),
    "a11y-with-udra": constrained(with_runtime(runtime(RADIUS) + accessibility(' label="Close"')), ""),
    "a11y-same-label": constrained(with_runtime(accessibility(' label="Close" identifier="Close"')), ""),
}
for traits in ('button="YES"', 'notEnabled="YES"', 'summaryElement="YES"', 'image="YES" notEnabled="YES"', 'adjustable="YES"', 'link="YES"',
               'none="YES"', 'header="YES"', 'selected="YES"', 'staticText="YES"'):
    ACCESSIBILITY["a11y-traits-" + traits.replace('="YES"', '').replace(' ', '-')] = constrained(with_runtime(accessibility(
        "", f'<accessibilityTraits key="traits" {traits}/>\n')), "")
ACCESSIBILITY["a11y-lproj"] = ACCESSIBILITY["a11y-all"]
LPROJ_XIBS.add("a11y-lproj")
STORYBOARDS["sb-a11y"] = storyboard(scene(view_extra=SUBVIEW.replace("                            </view>", "".join(
    f"                                {line}\n" for line in accessibility(' label="Close"', ELEMENT_YES).splitlines()) + "                            </view>")))
EXPERIMENTS.update(ACCESSIBILITY)


# Round 41: designables, IB's record of a custom view's intrinsic content size, in xibs and storyboards.
DESIGNABLE = '    <designables>\n        <designable name="sss-ss-ss1">\n            <size key="intrinsicContentSize" width="41.5" height="20.5"/>\n        </designable>\n    </designables>\n'
DESIGNABLE_VIEW = subview("sss-ss-ss1", attributes=' customClass="MyView" customModule="T" customModuleProvider="target"')
DESIGNABLES = {
    "designable": constrained(DESIGNABLE_VIEW, "").replace("</document>\n", DESIGNABLE + "</document>\n"),
    "designable-resources": constrained(DESIGNABLE_VIEW, "", resources=BUTTON_IMAGE).replace("</document>\n", DESIGNABLE + "</document>\n"),
    "designable-empty": constrained(DESIGNABLE_VIEW, "").replace("</document>\n", '    <designables>\n        <designable name="sss-ss-ss1"/>\n    </designables>\n</document>\n'),
}
STORYBOARDS["sb-designable"] = storyboard(scene(view_extra=SUBVIEW.replace('id="sub-vi-ew1"', 'customClass="MyView" id="sub-vi-ew1"'))).replace(
    "</document>\n", DESIGNABLE.replace("sss-ss-ss1", "sub-vi-ew1") + "</document>\n")
EXPERIMENTS.update(DESIGNABLES)


# Round 42: symbolic (standard spacing) constraints with the constants IB writes, to the superview and
# between siblings, with relations.
SYMBOLIC = {}
for constant in ("20", "8", "12", "6", "10", "16.5"):
    SYMBOLIC[f"symbolic-leading-{constant}"] = constrained(subview("sss-ss-ss1"), constraint(0, "sss-ss-ss1", "leading", ROOT, "leading",
                                                                                                f' constant="{constant}" symbolic="YES"'))
SYMBOLIC["symbolic-trailing-20"] = constrained(subview("sss-ss-ss1"), constraint(0, None, "trailing", "sss-ss-ss1", "trailing", ' constant="20" symbolic="YES"'))
SYMBOLIC["symbolic-trailing-ge-20"] = constrained(subview("sss-ss-ss1"), constraint(0, None, "trailing", "sss-ss-ss1", "trailing",
                                                                                        ' relation="greaterThanOrEqual" constant="20" symbolic="YES"'))
SYMBOLIC["symbolic-top-20"] = constrained(subview("sss-ss-ss1"), constraint(0, "sss-ss-ss1", "top", ROOT, "top", ' constant="20" symbolic="YES"'))
SYMBOLIC["symbolic-negative"] = constrained(subview("sss-ss-ss1"), constraint(0, "sss-ss-ss1", "leading", ROOT, "leading", ' constant="-8" symbolic="YES"'))
SYMBOLIC["symbolic-sibling-8"] = constrained(subview("aaa-aa-aa1", (10, 20, 100, 50)) + subview("bbb-bb-bb1", (10, 200, 100, 50)),
                                             constraint(0, "bbb-bb-bb1", "top", "aaa-aa-aa1", "bottom", ' constant="8" symbolic="YES"'))
SYMBOLIC["symbolic-sibling-ge-8"] = constrained(subview("aaa-aa-aa1", (10, 20, 100, 50)) + subview("bbb-bb-bb1", (200, 20, 100, 50)),
                                                constraint(0, "bbb-bb-bb1", "leading", "aaa-aa-aa1", "trailing", ' relation="greaterThanOrEqual" constant="8" symbolic="YES"'))
SYMBOLIC["symbolic-two"] = constrained(subview("sss-ss-ss1"), constraint(0, "sss-ss-ss1", "leading", ROOT, "leading", ' constant="20" symbolic="YES"')
                                       + constraint(1, None, "trailing", "sss-ss-ss1", "trailing", ' constant="20" symbolic="YES"'))
SYMBOLIC["symbolic-priority"] = constrained(subview("sss-ss-ss1"), constraint(0, "sss-ss-ss1", "leading", ROOT, "leading", ' constant="20" symbolic="YES" priority="750"'))
SYMBOLIC["symbolic-width"] = constrained(subview("sss-ss-ss1"), constraint(0, "sss-ss-ss1", "width", None, None, ' constant="20" symbolic="YES"'))
STORYBOARDS["sb-symbolic"] = storyboard(scene(view_extra=SUBVIEW.replace('<view contentMode="scaleToFill" id="sub-vi-ew1">',
                                                                          '<view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="sub-vi-ew1">')
                                              .replace('                                <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>\n', '')
                                              + '                        <constraints>\n'
                                              + constraint(0, "sub-vi-ew1", "leading", "8bC-Xf-vdC", "leading", ' constant="20" symbolic="YES"', indent=28)
                                              + '                        </constraints>\n'))
MARGIN_BOX = ('                <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="box-aa-aa1">\n'
              '                    <rect key="frame" x="10" y="20" width="200" height="100"/>\n'
              '                    <subviews>\n                        <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="inn-aa-aa1">\n'
              '                            <rect key="frame" x="2" y="1" width="194" height="96"/>\n                        </view>\n                    </subviews>\n'
              '{margins}                    <constraints>\n{constraints}                    </constraints>\n                </view>\n')
MARGIN_PINS = (constraint(10, "inn-aa-aa1", "leading", "box-aa-aa1", "leadingMargin", indent=24) + constraint(11, "box-aa-aa1", "trailingMargin", "inn-aa-aa1", "trailing", indent=24)
               + constraint(12, "inn-aa-aa1", "top", "box-aa-aa1", "topMargin", indent=24) + constraint(13, "box-aa-aa1", "bottomMargin", "inn-aa-aa1", "bottom", indent=24))
for name, margins in {"edge": '<edgeInsets key="layoutMargins" top="1" left="2" bottom="3" right="4"/>', "directional":
                      '<directionalEdgeInsets key="directionalLayoutMargins" top="1" leading="2" bottom="3" trailing="4"/>',
                      "zero": '<edgeInsets key="layoutMargins" top="0.0" left="0.0" bottom="0.0" right="0.0"/>', "none": None}.items():
    SYMBOLIC[f"margin-custom-{name}"] = constrained(MARGIN_BOX.format(margins=f"                    {margins}\n" if margins else "", constraints=MARGIN_PINS), "")
SYMBOLIC["margin-custom-left-right"] = constrained(MARGIN_BOX.format(margins='                    <edgeInsets key="layoutMargins" top="1" left="2" bottom="3" right="4"/>\n',
    constraints=constraint(10, "inn-aa-aa1", "left", "box-aa-aa1", "leftMargin", indent=24) + constraint(11, "box-aa-aa1", "rightMargin", "inn-aa-aa1", "right", indent=24)), "")
EXPERIMENTS.update(SYMBOLIC)


# Round 43: the order of key-value pairs, probing the corpus's cwa HomeListItemView (two labels of a
# stack with one runtime attribute each, written in reverse): ids, stacks, values swapped one at a time.
STYLE = udra("ibEnaStyle", "string", "subheadline")


def ordered_pair(ids, in_stack=True, values=("subheadline", "subheadline")):
    labels = "".join(stack_label(identifier, (25 * k, 0, 20, 21)).replace("</label>\n", runtime(udra("ibEnaStyle", "string", value)) + "</label>\n")
                     for k, (identifier, value) in enumerate(zip(ids, values)))
    if in_stack:
        return constrained(stack(arranged=labels, frame=(20, 40, 45, 21)), "")
    return constrained("".join("                " + line + "\n" for line in labels.splitlines()), "")


ORDERS = {
    "udra-order-stack": ordered_pair(("0UH-8p-hUr", "aQT-KO-jfY")),
    "udra-order-stack-swapped": ordered_pair(("aQT-KO-jfY", "0UH-8p-hUr")),
    "udra-order-plain": ordered_pair(("0UH-8p-hUr", "aQT-KO-jfY"), in_stack=False),
    "udra-order-plain-swapped": ordered_pair(("aQT-KO-jfY", "0UH-8p-hUr"), in_stack=False),
    "udra-order-stack-values": ordered_pair(("0UH-8p-hUr", "aQT-KO-jfY"), values=("a", "b")),
    "udra-order-stack-plain-ids": ordered_pair(("aaa-aa-aa1", "bbb-bb-bb1")),
    "udra-order-plain-plain-ids": ordered_pair(("aaa-aa-aa1", "bbb-bb-bb1"), in_stack=False),
}
ORDERS["udra-order-stack-pinned"] = ordered_pair(("0UH-8p-hUr", "aQT-KO-jfY")).replace("            <point key", "            <constraints>\n"
    + pinned("stk-aa-aa1", 0).replace("                <", "                <", 4) + "            </constraints>\n            <point key")
def pinned_stack(labels, constraints=EDGES, attributes=STACK_ATTRIBUTES, tag="stackView"):
    arranged = "".join(stack_label(identifier, (25 * k, 0, 20, 21)).replace("</label>\n", runtime(udra("k", "string", identifier)) + "</label>\n")
                       for k, identifier in enumerate(labels))
    container = stack(attributes, arranged, frame=(20, 40, 25 * len(labels), 21))
    if tag == "view":
        container = container.replace("<stackView " + attributes, '<view contentMode="scaleToFill"').replace("</stackView>", "</view>")
    edges = "".join(constraint(k, "stk-aa-aa1", a, ROOT, a) for k, a in enumerate(constraints))
    return constrained(container, edges)


ORDERS["udra-order-stack3-pinned"] = pinned_stack(["l01-aa-aa1", "l02-aa-aa1", "l03-aa-aa1"])
ORDERS["udra-order-stack4-pinned"] = pinned_stack(["l01-aa-aa1", "l02-aa-aa1", "l03-aa-aa1", "l04-aa-aa1"])
ORDERS["udra-order-stack2-pinned"] = pinned_stack(["l01-aa-aa1", "l02-aa-aa1"])
ORDERS["udra-order-stack2-top-leading"] = pinned_stack(["l01-aa-aa1", "l02-aa-aa1"], ["top", "leading"])
ORDERS["udra-order-stack2-three-edges"] = pinned_stack(["l01-aa-aa1", "l02-aa-aa1"], ["top", "leading", "trailing"])
ORDERS["udra-order-view2-pinned"] = pinned_stack(["l01-aa-aa1", "l02-aa-aa1"], tag="view")
ORDERS["udra-order-stack2-vertical-pinned"] = pinned_stack(["l01-aa-aa1", "l02-aa-aa1"], attributes=STACK_ATTRIBUTES + ' axis="vertical"')
def placed_view(frames, constraints=EDGES):
    labels = "".join(stack_label(f"l0{k + 1}-aa-aa1", frame).replace("</label>\n", runtime(udra("k", "string", f"l0{k + 1}")) + "</label>\n")
                     for k, frame in enumerate(frames))
    container = stack(STACK_ATTRIBUTES, labels, frame=(20, 40, 200, 100)).replace("<stackView " + STACK_ATTRIBUTES, '<view contentMode="scaleToFill"').replace(
        "</stackView>", "</view>")
    return constrained(container, "".join(constraint(k, "stk-aa-aa1", a, ROOT, a) for k, a in enumerate(constraints)))


for name, frames in {"offset": [(5, 0, 20, 21), (30, 0, 20, 21), (55, 0, 20, 21)], "third-origin": [(25, 0, 20, 21), (50, 0, 20, 21), (0, 0, 20, 21)],
                     "diagonal": [(0, 0, 20, 21), (30, 30, 20, 21), (60, 60, 20, 21)], "reverse-x": [(60, 0, 20, 21), (30, 0, 20, 21), (0, 0, 20, 21)],
                     "rows": [(0, 50, 20, 21), (0, 0, 20, 21), (0, 25, 20, 21)], "same-origin": [(0, 0, 20, 21), (0, 0, 20, 21), (30, 0, 20, 21)]}.items():
    ORDERS[f"udra-order-placed-{name}"] = placed_view(frames)
    ORDERS[f"udra-order-placed-{name}-unpinned"] = placed_view(frames, [])
THREE_FRAMES = [(0, 0, 20, 21), (25, 0, 20, 21), (50, 0, 20, 21)]
ORDERS["udra-order-placed-bottom-trailing"] = placed_view(THREE_FRAMES, ["bottom", "trailing"])
ORDERS["udra-order-placed-four-widths-root"] = placed_view(THREE_FRAMES, []).replace("            <point key", "            <constraints>\n" + "".join(
    constraint(40 + k, None, "width", extra=f' constant="{300 + k}"') for k in range(4)) + "            </constraints>\n            <point key")
def many_pairs(count, plain=0, every=1):
    views = "".join(subview(f"m{k:02d}-aa-aa1", (k, k, 10, 10)) for k in range(plain))
    views += "".join(with_runtime(runtime(udra("k", "string", f"v{k:02d}")), f"v{k:02d}-aa-aa1") if k % every == 0 else subview(f"v{k:02d}-aa-aa1", (k, k, 10, 10))
                     for k in range(count))
    return constrained(views, "")


for count in (6, 8, 10, 12, 16, 20, 30, 40):
    ORDERS[f"udra-order-many-{count}"] = many_pairs(count)
for plain in (3, 5, 8, 13, 20):
    ORDERS[f"udra-order-many-6-after-{plain}"] = many_pairs(6, plain)
ORDERS["udra-order-many-40-every-3"] = many_pairs(40, every=3)
for count in (8, 12, 30):
    ORDERS[f"a11y-order-many-{count}"] = constrained("".join(with_runtime(accessibility(f' label="v{k:02d}"'), f"v{k:02d}-aa-aa1") for k in range(count)), "")
ORDERS["udra-order-many-36"] = many_pairs(36)
ORDERS["udra-order-many-37"] = many_pairs(37)
for count in (8, 12, 20):
    ORDERS[f"udra-order-labels-{count}"] = constrained("".join(label(extra=runtime(udra("k", "string", f"v{k:02d}")), identifier=f"v{k:02d}-aa-aa1",
                                                                  frame=(k, 30 * k, 42, 21)) for k in range(count)), "")
    ORDERS[f"udra-order-buttons-{count}"] = constrained("".join(button(children=BUTTON_STATE + runtime(udra("k", "string", f"v{k:02d}")), identifier=f"v{k:02d}-aa-aa1",
                                                                   frame=(k, 30 * k, 75, 35)) for k in range(count)), "")
for count in (1, 2, 3, 4, 5, 6, 8, 12):
    ORDERS[f"udra-order-widths-{count}"] = constrained(with_runtime(runtime(udra("k", "string", "a"))) + with_runtime(runtime(udra("k", "string", "b")), "sss-ss-ss2")
                                                       + subview("www-ww-ww1", constraints="".join(constraint(20 + k, None, "width", extra=f' constant="{10 + k}"', indent=24)
                                                                                                   for k in range(count))), "")
EXPERIMENTS.update(ORDERS)


# Round 44: sibling constraints among safe-area constraints (the corpus's pocket-casts
# WhatsNewViewController): the sibling's first attribute against the safe area's, which item is first.
def sib_safe(constraints):
    return constrained(subview(SIB_A, (10, 20, 100, 50)) + subview(SIB_B, (10, 200, 100, 50)), constraints, safe=True)


SAFE_SIBS = {
    "sib-safe-whatsnew": sib_safe(constraint(0, SIB_A, "trailing", SAFE_GUIDE, "trailing") + constraint(1, SIB_A, "leading", SAFE_GUIDE, "leading")
                                  + constraint(2, SIB_A, "top", SAFE_GUIDE, "top") + constraint(3, SIB_A, "bottom", SIB_B, "top")),
    "sib-safe-guide-first": sib_safe(constraint(0, SAFE_GUIDE, "trailing", SIB_A, "trailing") + constraint(1, SIB_A, "leading", SAFE_GUIDE, "leading")
                                     + constraint(2, SAFE_GUIDE, "top", SIB_A, "top") + constraint(3, SIB_A, "bottom", SIB_B, "top")),
    "sib-safe-and-view": sib_safe(constraint(0, SIB_A, "trailing", SAFE_GUIDE, "trailing") + constraint(1, SIB_A, "leading", ROOT, "leading")
                                  + constraint(2, SIB_A, "top", SAFE_GUIDE, "top") + constraint(3, SIB_A, "bottom", SIB_B, "top")),
    "sib-safe-b-first": sib_safe(constraint(0, SIB_A, "trailing", SAFE_GUIDE, "trailing") + constraint(1, SIB_A, "top", SAFE_GUIDE, "top")
                                 + constraint(2, SIB_B, "top", SIB_A, "bottom")),
}
for attribute in ("leading", "trailing", "top", "bottom", "centerX", "width", "height", "centerY"):
    other = {"leading": "trailing", "trailing": "leading", "top": "bottom", "bottom": "top"}.get(attribute, attribute)
    SAFE_SIBS[f"sib-safe-attr-{attribute}"] = sib_safe(constraint(0, SIB_A, "trailing", SAFE_GUIDE, "trailing") + constraint(1, SIB_A, "leading", SAFE_GUIDE, "leading")
                                                       + constraint(2, SIB_A, "top", SAFE_GUIDE, "top") + constraint(3, SIB_A, "bottom", SAFE_GUIDE, "bottom")
                                                       + constraint(4, SIB_A, attribute, SIB_B, other))
EXPERIMENTS.update(SAFE_SIBS)


# Round 45: collection views in xibs, as IB writes them (no prototypes): a flow layout, then one change
# at a time (layout sizes and insets, direction, custom layouts, scroll attributes, outlets, classes).
FLOW = ('<collectionViewFlowLayout key="collectionViewLayout" minimumLineSpacing="10" minimumInteritemSpacing="10" id="flw-aa-aa1">\n'
        '    <size key="itemSize" width="128" height="128"/>\n    <size key="headerReferenceSize" width="0.0" height="0.0"/>\n'
        '    <size key="footerReferenceSize" width="0.0" height="0.0"/>\n    <inset key="sectionInset" minX="0.0" minY="0.0" maxX="0.0" maxY="0.0"/>\n'
        '</collectionViewFlowLayout>\n')
CV_ATTRIBUTES = 'clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="scaleToFill" dataMode="none"'


def collection(attributes=CV_ATTRIBUTES, layout=FLOW, extra="", frame=(0, 0, 393, 852)):
    x, y, w, h = frame
    body = f'<rect key="frame" x="{x}" y="{y}" width="{w}" height="{h}"/>\n' + extra + layout
    return (f'                <collectionView {attributes} translatesAutoresizingMaskIntoConstraints="NO" id="cvw-aa-aa1">\n'
            + "".join(f'                    {line}\n' for line in body.splitlines()) + '                </collectionView>\n')


CV_OUTLETS = ('<connections>\n    <outlet property="dataSource" destination="-1" id="cds-aa-aa1"/>\n'
              '    <outlet property="delegate" destination="-1" id="cdl-aa-aa1"/>\n</connections>\n')
COLLECTIONS = {
    "collection": constrained(collection(), ""),
    "collection-pinned": constrained(collection(), pinned("cvw-aa-aa1", 0)),
    "collection-outlets": constrained(collection(layout=FLOW + CV_OUTLETS), ""),
    "collection-background": constrained(collection(extra=gray(1, 1) + "\n"), ""),
    "collection-background-system": constrained(collection(extra='<color key="backgroundColor" systemColor="systemBackgroundColor"/>\n'), "",
                                                resources=system_color("systemBackgroundColor", gray(1, 1))),
    "collection-custom-class": constrained(collection(CV_ATTRIBUTES + ' customClass="Grid" customModule="T" customModuleProvider="target"'), ""),
    "collection-custom-layout": constrained(collection(layout='<collectionViewLayout key="collectionViewLayout" id="lay-aa-aa1" customClass="GridLayout" customModule="T" customModuleProvider="target"/>\n'), ""),
    "collection-flow-zero": constrained(collection(layout=FLOW.replace('minimumLineSpacing="10" minimumInteritemSpacing="10"', 'minimumLineSpacing="0.0" minimumInteritemSpacing="0.0"')), ""),
    "collection-flow-sizes": constrained(collection(layout=FLOW.replace('width="128" height="128"', 'width="300" height="250"').replace(
        '<size key="headerReferenceSize" width="0.0" height="0.0"/>', '<size key="headerReferenceSize" width="50" height="50"/>').replace(
        '<size key="footerReferenceSize" width="0.0" height="0.0"/>', '<size key="footerReferenceSize" width="20" height="30"/>')), ""),
    "collection-flow-insets": constrained(collection(layout=FLOW.replace('minX="0.0" minY="0.0" maxX="0.0" maxY="0.0"', 'minX="1" minY="2" maxX="3" maxY="4"')), ""),
    "collection-flow-horizontal": constrained(collection(layout=FLOW.replace(' id="flw-aa-aa1"', ' scrollDirection="horizontal" id="flw-aa-aa1"')), ""),
    "collection-flow-estimated": constrained(collection(layout=FLOW.replace(' id="flw-aa-aa1"', ' automaticEstimatedItemSize="YES" id="flw-aa-aa1"')), ""),
    "collection-flow-safe-area": constrained(collection(layout=FLOW.replace(' id="flw-aa-aa1"', ' sectionInsetReference="safeArea" id="flw-aa-aa1"')), ""),
    "collection-flow-custom-class": constrained(collection(layout=FLOW.replace(' id="flw-aa-aa1"', ' id="flw-aa-aa1" customClass="Flow" customModule="T" customModuleProvider="target"')), ""),
    "collection-prototypes-mode": constrained(collection(CV_ATTRIBUTES.replace('dataMode="none"', 'dataMode="prototypes"')), ""),
}
for flag in ('showsHorizontalScrollIndicator="NO"', 'showsVerticalScrollIndicator="NO"', 'pagingEnabled="YES"', 'alwaysBounceVertical="YES"',
             'prefetchingEnabled="NO"', 'scrollEnabled="NO"', 'indicatorStyle="black"', 'insetsLayoutMarginsFromSafeArea="NO"'):
    name, value = flag.split("=")
    COLLECTIONS[f"collection-{name}-{value.strip(chr(34))}"] = constrained(collection(f"{CV_ATTRIBUTES} {flag}"), "")
COLLECTIONS["collection-flow-all"] = constrained(collection(layout=FLOW.replace('minimumLineSpacing="10" minimumInteritemSpacing="10"', 'minimumLineSpacing="5" minimumInteritemSpacing="6"')
    .replace(' id="flw-aa-aa1"', ' scrollDirection="horizontal" automaticEstimatedItemSize="YES" sectionInsetReference="safeArea" id="flw-aa-aa1"')
    .replace('<size key="headerReferenceSize" width="0.0" height="0.0"/>', '<size key="headerReferenceSize" width="50" height="50"/>')
    .replace('<size key="footerReferenceSize" width="0.0" height="0.0"/>', '<size key="footerReferenceSize" width="20" height="30"/>')
    .replace('minX="0.0" minY="0.0" maxX="0.0" maxY="0.0"', 'minX="1" minY="2" maxX="3" maxY="4"')), "")
for name, color in {"white-rgb": rgb(1, 1, 1, 1), "clear": gray(0, 0), "gray": gray(0.5, 1), "black": gray(0, 1)}.items():
    COLLECTIONS[f"collection-background-{name}"] = constrained(collection(extra=color + "\n"), "")
COLLECTIONS["collection-height"] = constrained(collection(extra='<constraints>\n    <constraint firstAttribute="height" constant="193" id="cvh-aa-aa1"/>\n</constraints>\n'), "")
COLLECTIONS["collection-flow-spacing-line"] = constrained(collection(layout=FLOW.replace('minimumLineSpacing="10"', 'minimumLineSpacing="0.0"')), "")
COLLECTIONS["collection-flow-item-50"] = constrained(collection(layout=FLOW.replace('width="128" height="128"', 'width="50" height="50"')), "")
EXPERIMENTS.update(COLLECTIONS)


# Round 46: view controllers' attributes in storyboards, one at a time, then together; with a custom
# class and in a navigation controller.
CONTROLLER_FLAGS = ['title="Detail"', 'extendedLayoutIncludesOpaqueBars="YES"', 'automaticallyAdjustsScrollViewInsets="NO"',
                    'hidesBottomBarWhenPushed="YES"', 'modalPresentationStyle="overCurrentContext"', 'modalPresentationStyle="currentContext"',
                    'modalPresentationStyle="fullScreen"', 'modalPresentationStyle="overFullScreen"', 'modalPresentationStyle="pageSheet"',
                    'modalPresentationStyle="formSheet"', 'modalTransitionStyle="crossDissolve"', 'modalTransitionStyle="flipHorizontal"',
                    'modalTransitionStyle="coverVertical"', 'restorationIdentifier="Restore"']
VC_FLAGS = {}
for flag in CONTROLLER_FLAGS:
    name, value = flag.split("=")
    VC_FLAGS[f"sb-vc-{name}-{value.strip(chr(34))}"] = storyboard(controller_scene(1, " " + flag), initial="vc1-aa-aaa")
VC_FLAGS["sb-vc-all"] = storyboard(controller_scene(1, ' title="Detail" extendedLayoutIncludesOpaqueBars="YES" automaticallyAdjustsScrollViewInsets="NO"'
                                                      ' hidesBottomBarWhenPushed="YES" modalPresentationStyle="overCurrentContext" modalTransitionStyle="crossDissolve"'
                                                      ' restorationIdentifier="Restore"'), initial="vc1-aa-aaa")
VC_FLAGS["sb-vc-all-custom"] = VC_FLAGS["sb-vc-all"].replace(' title="Detail"', ' title="Detail" customClass="DetailController" customModule="T" customModuleProvider="target"')
VC_FLAGS["sb-vc-restoration-storyboard-id"] = storyboard(controller_scene(1, ' storyboardIdentifier="Second" useStoryboardIdentifierAsRestorationIdentifier="YES"'),
                                                         initial="vc1-aa-aaa")
VC_FLAGS["sb-vc-title-nav"] = storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, ' title="Detail"'), initial="nvc-aa-aaa")
VC_FLAGS["sb-vc-all-segue"] = storyboard(controller_scene(1, ' title="Detail" extendedLayoutIncludesOpaqueBars="YES" automaticallyAdjustsScrollViewInsets="NO"'
                                                            ' hidesBottomBarWhenPushed="YES" modalPresentationStyle="overCurrentContext" modalTransitionStyle="crossDissolve"'
                                                            ' restorationIdentifier="Restore" storyboardIdentifier="First"', connections=segue("vc2-aa-aaa", "show", 1, "Detail")),
                                         controller_scene(2), initial="vc1-aa-aaa")
VC_FLAGS["sb-vc-all-defines"] = VC_FLAGS["sb-vc-all-segue"].replace(' title="Detail"', ' title="Detail" definesPresentationContext="YES"')
STORYBOARDS.update(VC_FLAGS)


# Round 47: restoration identifiers on views and cells, cells' opacity, a document's custom fonts.
GEORGIA = font_description({"name": "Georgia", "family": "Georgia", "pointSize": "17"})
CUSTOM_FONTS = '    <customFonts key="customFonts">\n        <array key="Georgia.ttf">\n            <string>Georgia</string>\n        </array>\n    </customFonts>\n'
RESTORATION = {
    "restoration-view": constrained(subview("sss-ss-ss1", attributes=' restorationIdentifier="Box"'), ""),
    "restoration-root": xib(view('restorationIdentifier="Root"')),
    "restoration-label": constrained(label(LABEL_ATTRIBUTES + ' restorationIdentifier="Title"'), ""),
    "restoration-button": constrained(button(BUTTON_ATTRIBUTES + ' restorationIdentifier="Go"'), ""),
    "restoration-same-text": constrained(label(LABEL_ATTRIBUTES.replace('text="Label"', 'text="Title"') + ' restorationIdentifier="Title"'), ""),
    "restoration-cell": cell_xib(' restorationIdentifier="Cell" customClass="Cell" customModule="T" customModuleProvider="target"'),
    "cell-opaque-no": cell_xib(' opaque="NO" customClass="Cell" customModule="T" customModuleProvider="target"'),
    "cell-opaque-yes": cell_xib(' opaque="YES" customClass="Cell" customModule="T" customModuleProvider="target"'),
    "custom-fonts": constrained(label(font=GEORGIA), "").replace("    <objects>\n", CUSTOM_FONTS + "    <objects>\n"),
    "custom-fonts-unused": constrained(label(), "").replace("    <objects>\n", CUSTOM_FONTS + "    <objects>\n"),
}
STORYBOARDS["sb-custom-fonts"] = STORYBOARD.replace("    <scenes>\n", CUSTOM_FONTS + "    <scenes>\n")
STORYBOARDS["sb-restoration-view"] = storyboard(scene(view_extra=SUBVIEW.replace('id="sub-vi-ew1"', 'restorationIdentifier="Box" id="sub-vi-ew1"')))
RESTORATION["restoration-margins"] = constrained(subview("sss-ss-ss1", attributes=' restorationIdentifier="Box" insetsLayoutMarginsFromSafeArea="NO"'
                                                         ' preservesSuperviewLayoutMargins="YES" layoutMarginsFollowReadableWidth="YES"').replace(
    "                </view>", '                    <edgeInsets key="layoutMargins" top="1" left="2" bottom="3" right="4"/>\n                </view>'), "")
EXPERIMENTS.update(RESTORATION)


# Round 48: collection views in storyboards (dataMode="prototypes"): no cells, an empty <cells/>, one and
# two prototype cells (the older content view template, as the corpus's), outlets to the controller.
def sb_cv_cell(identifier, reuse, x=0, label=""):
    return (f'<collectionViewCell opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" reuseIdentifier="{reuse}" id="{identifier}">\n'
            f'    <rect key="frame" x="{x}" y="0.0" width="128" height="128"/>\n'
            '    <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>\n'
            '    <view key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center">\n'
            '        <rect key="frame" x="0.0" y="0.0" width="128" height="128"/>\n'
            '        <autoresizingMask key="autoresizingMask"/>\n'
            + label + '    </view>\n</collectionViewCell>\n')


def sb_collection(cells=None, outlets=False):
    cells_element = "" if cells is None else ("<cells/>\n" if cells == "" else "<cells>\n" + "".join(f"    {line}\n" for line in cells.splitlines()) + "</cells>\n")
    connections = ('<connections>\n    <outlet property="dataSource" destination="BYZ-38-t0r" id="cds-aa-aa1"/>\n'
                   '    <outlet property="delegate" destination="BYZ-38-t0r" id="cdl-aa-aa1"/>\n</connections>\n') if outlets else ""
    body = ('<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>\n' + FLOW + cells_element + connections)
    element = ('<collectionView clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="scaleToFill" dataMode="prototypes" '
               'translatesAutoresizingMaskIntoConstraints="NO" id="cvw-aa-aa1">\n' + "".join(f"    {line}\n" for line in body.splitlines()) + '</collectionView>\n')
    return storyboard(scene(view_extra='                        <subviews>\n' + "".join(f"                            {line}\n" for line in element.splitlines())
                            + '                        </subviews>\n'))


SB_CV_LABEL = ('        <subviews>\n            <label opaque="NO" userInteractionEnabled="NO" contentMode="left" text="Label" textAlignment="natural" '
               'lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="cvl-aa-aa1">\n'
               '                <rect key="frame" x="10" y="10" width="42" height="21"/>\n'
               f'                {SYSTEM_17}\n                <nil key="textColor"/>\n                <nil key="highlightedColor"/>\n            </label>\n        </subviews>\n')
SB_COLLECTIONS = {
    "sb-collection-no-cells": sb_collection(),
    "sb-collection-empty-cells": sb_collection(""),
    "sb-collection-outlets": sb_collection("", outlets=True),
    "sb-collection-cell": sb_collection(sb_cv_cell("cel-aa-aa1", "Cell")),
    "sb-collection-cell-label": sb_collection(sb_cv_cell("cel-aa-aa1", "Cell", label=SB_CV_LABEL)),
    "sb-collection-two-cells": sb_collection(sb_cv_cell("cel-aa-aa1", "Second") + sb_cv_cell("cel-aa-aa2", "First", x=138)),
    "sb-collection-cell-outlets": sb_collection(sb_cv_cell("cel-aa-aa1", "Cell"), outlets=True),
}
STORYBOARDS.update(SB_COLLECTIONS)


# Round 49: image views' adjustsImageSizeForAccessibilityContentSizeCategory, with an image, a symbol, a tint.
IMAGE_VIEWS2 = {
    "image-view-adjusts": constrained(subview("iii-ii-ii1", (112, 333, 168, 185), "imageView", ' image="Logo" adjustsImageSizeForAccessibilityContentSizeCategory="YES"'),
                                      "", resources=LOGO),
    "image-view-adjusts-symbol": constrained(subview("iii-ii-ii1", (112, 333, 168, 185), "imageView", ' image="plus" catalog="system"'
                                                     ' adjustsImageSizeForAccessibilityContentSizeCategory="YES"'), "", resources=BUTTON_SYMBOL),
    "image-view-adjusts-tint": constrained(subview("iii-ii-ii1", (112, 333, 168, 185), "imageView", ' image="Logo" adjustsImageSizeForAccessibilityContentSizeCategory="YES"'
                                                   ' restorationIdentifier="Img"').replace("                </imageView>", "                    " + TINT + "\n                </imageView>"),
                                           "", resources=LOGO),
}
EXPERIMENTS.update(IMAGE_VIEWS2)


# Round 50: gesture recognizers in xibs: a top-level recognizer with an action to File's Owner, attached
# to a subview by its gestureRecognizers outlet collection; kinds and attributes one at a time.
def gestures(recognizers, attach=(("sss-ss-ss1", "tap-aa-aa1"),)):
    view = subview("sss-ss-ss1")
    for owner, recognizer in attach:
        view = view.replace("                </view>", f'                    <connections>\n                        <outletCollection property="gestureRecognizers" '
                            f'destination="{recognizer}" appends="YES" id="gr{recognizer[:3]}-aa-aa1"/>\n                    </connections>\n                </view>', 1)
    text = constrained(view, "")
    return text.replace(XIB_TAIL, recognizers + XIB_TAIL)


def recognizer(tag="tapGestureRecognizer", identifier="tap-aa-aa1", attributes="", action=True):
    if not action:
        return f'        <{tag}{attributes} id="{identifier}"/>\n'
    return (f'        <{tag}{attributes} id="{identifier}">\n            <connections>\n'
            f'                <action selector="tapped:" destination="-1" id="act-{identifier[:3]}-aa1"/>\n            </connections>\n        </{tag}>\n')


GESTURES = {
    "gesture-tap": gestures(recognizer()),
    "gesture-tap-no-action": gestures(recognizer(action=False)),
    "gesture-tap-unattached": gestures(recognizer(), attach=()),
    "gesture-tap-two-taps": gestures(recognizer(attributes=' numberOfTapsRequired="2" numberOfTouchesRequired="2"')),
    "gesture-swipe-right": gestures(recognizer("swipeGestureRecognizer", "swp-aa-aa1", ' direction="right"'), attach=(("sss-ss-ss1", "swp-aa-aa1"),)),
    "gesture-swipe-left-disabled": gestures(recognizer("swipeGestureRecognizer", "swp-aa-aa1", ' enabled="NO" direction="left"'), attach=(("sss-ss-ss1", "swp-aa-aa1"),)),
    "gesture-pan": gestures(recognizer("panGestureRecognizer", "pan-aa-aa1", ' minimumNumberOfTouches="1"'), attach=(("sss-ss-ss1", "pan-aa-aa1"),)),
    "gesture-two": gestures(recognizer() + recognizer("swipeGestureRecognizer", "swp-aa-aa1", ' direction="right"'),
                            attach=(("sss-ss-ss1", "tap-aa-aa1"), ("sss-ss-ss1", "swp-aa-aa1"))),
}
GESTURES["gesture-two-swapped"] = gestures(recognizer("swipeGestureRecognizer", "swp-aa-aa1", ' direction="right"') + recognizer(),
                                          attach=(("sss-ss-ss1", "swp-aa-aa1"), ("sss-ss-ss1", "tap-aa-aa1")))
GESTURES["gesture-two-unattached"] = gestures(recognizer() + recognizer("swipeGestureRecognizer", "swp-aa-aa1", ' direction="right"'), attach=())
GESTURES["gesture-three-unattached"] = gestures(recognizer() + recognizer("swipeGestureRecognizer", "swp-aa-aa1", ' direction="right"')
                                                + recognizer("panGestureRecognizer", "pan-aa-aa1"), attach=())
EXPERIMENTS.update(GESTURES)


# Round 51: text views, as IB writes them: a scrolling, editable text view with a text, then one change at
# a time (editable, selectable, scrolling, texts, colors, alignment, input traits, data detectors, classes).
TV_ATTRIBUTES = 'clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="scaleToFill" textAlignment="natural"'
TV_TEXT = '<string key="text">Lorem ipsum</string>\n'
TV_FONT = font_description({"type": "system", "pointSize": "14"}) + "\n"
TV_TRAITS = '<textInputTraits key="textInputTraits" autocapitalizationType="sentences"/>\n'
TV_BACKGROUND = '<color key="backgroundColor" systemColor="systemBackgroundColor"/>\n'


def text_view(attributes=TV_ATTRIBUTES, children=TV_BACKGROUND + TV_TEXT + TV_FONT + TV_TRAITS, frame=(16, 40, 240, 128)):
    x, y, w, h = frame
    body = f'<rect key="frame" x="{x}" y="{y}" width="{w}" height="{h}"/>\n' + children
    return (f'                <textView {attributes} translatesAutoresizingMaskIntoConstraints="NO" id="txv-aa-aa1">\n'
            + "".join(f'                    {line}\n' for line in body.splitlines()) + '                </textView>\n')


TVR = system_color("systemBackgroundColor", gray(1, 1))
TEXT_VIEWS = {
    "text-view": constrained(text_view(), "", resources=TVR),
    "text-view-no-text": constrained(text_view(children=TV_BACKGROUND + TV_FONT + TV_TRAITS), "", resources=TVR),
    "text-view-text-attribute": constrained(text_view(TV_ATTRIBUTES + ' text="Lorem ipsum"', TV_BACKGROUND + TV_FONT + TV_TRAITS), "", resources=TVR),
    "text-view-no-background": constrained(text_view(children=TV_TEXT + TV_FONT + TV_TRAITS), ""),
    "text-view-white": constrained(text_view(children=gray(1, 1) + "\n" + TV_TEXT + TV_FONT + TV_TRAITS), ""),
    "text-view-text-color": constrained(text_view(children=TV_BACKGROUND + TV_TEXT + gray(0.5, 1).replace("backgroundColor", "textColor") + "\n" + TV_FONT + TV_TRAITS),
                                        "", resources=TVR),
    "text-view-traits-empty": constrained(text_view(children=TV_BACKGROUND + TV_TEXT + TV_FONT + '<textInputTraits key="textInputTraits"/>\n'), "", resources=TVR),
    "text-view-font-17": constrained(text_view(children=TV_BACKGROUND + TV_TEXT + SYSTEM_17 + "\n" + TV_TRAITS), "", resources=TVR),
    "text-view-center": constrained(text_view(TV_ATTRIBUTES.replace('"natural"', '"center"')), "", resources=TVR),
    "text-view-custom-class": constrained(text_view(TV_ATTRIBUTES + ' customClass="Notes" customModule="T" customModuleProvider="target"'), "", resources=TVR),
    "text-view-detectors": constrained(text_view(children=TV_BACKGROUND + TV_TEXT + TV_FONT + TV_TRAITS
                                                 + '<dataDetectorType key="dataDetectorTypes" phoneNumber="YES" link="YES"/>\n'), "", resources=TVR),
}
for flag in ('editable="NO"', 'selectable="NO"', 'scrollEnabled="NO"', 'showsHorizontalScrollIndicator="NO"', 'showsVerticalScrollIndicator="NO"',
             'bounces="NO"', 'bouncesZoom="NO"', 'canCancelContentTouches="NO"', 'delaysContentTouches="NO"', 'contentInsetAdjustmentBehavior="never"'):
    name, value = flag.split("=")
    TEXT_VIEWS[f"text-view-{name}-{value.strip(chr(34))}"] = constrained(text_view(f"{TV_ATTRIBUTES} {flag}"), "", resources=TVR)
TEXT_VIEWS["text-view-static"] = constrained(text_view(TV_ATTRIBUTES.replace(' textAlignment', ' scrollEnabled="NO" editable="NO" textAlignment')), "", resources=TVR)
TV_DETECTORS = '<dataDetectorType key="dataDetectorTypes" phoneNumber="YES" link="YES" address="YES"/>\n'
TV_LABEL_COLOR = '<color key="textColor" systemColor="labelColor"/>\n'
TEXT_VIEWS.update({
    "text-view-all-flags": constrained(text_view(TV_ATTRIBUTES + ' editable="NO" selectable="NO"', TV_BACKGROUND + TV_TEXT + TV_FONT
                                                 + '<textInputTraits key="textInputTraits"/>\n' + TV_DETECTORS), "", resources=TVR),
    "text-view-detectors-link": constrained(text_view(TV_ATTRIBUTES + ' editable="NO"', TV_BACKGROUND + TV_TEXT + TV_FONT + TV_TRAITS
                                                      + '<dataDetectorType key="dataDetectorTypes" link="YES"/>\n'), "", resources=TVR),
    "text-view-label-color": constrained(text_view(children=TV_BACKGROUND + TV_TEXT + TV_LABEL_COLOR + TV_FONT + TV_TRAITS),
                                         "", resources=TVR + system_color("labelColor", gray(0, 1))),
    "text-view-traits-smart": constrained(text_view(children=TV_BACKGROUND + TV_TEXT + TV_FONT + '<textInputTraits key="textInputTraits" autocorrectionType="no" '
                                                    'spellCheckingType="no" smartDashesType="no" smartInsertDeleteType="no" smartQuotesType="no"/>\n'),
                                          "", resources=TVR),
    "text-view-traits-yes": constrained(text_view(children=TV_BACKGROUND + TV_TEXT + TV_FONT + '<textInputTraits key="textInputTraits" '
                                                  'autocapitalizationType="sentences" autocorrectionType="yes" spellCheckingType="yes"/>\n'), "", resources=TVR),
    "text-view-traits-alert": constrained(text_view(children=TV_BACKGROUND + TV_TEXT + TV_FONT + '<textInputTraits key="textInputTraits" '
                                                    'autocorrectionType="no" spellCheckingType="no" keyboardAppearance="alert"/>\n'), "", resources=TVR),
    "text-view-traits-url": constrained(text_view(children=TV_BACKGROUND + TV_TEXT + TV_FONT + '<textInputTraits key="textInputTraits" '
                                                  'autocapitalizationType="sentences" textContentType="url"/>\n'), "", resources=TVR),
    "text-view-traits-all": constrained(text_view(children=TV_BACKGROUND + TV_TEXT + TV_FONT + '<textInputTraits key="textInputTraits" '
                                                  'autocapitalizationType="words" autocorrectionType="no" spellCheckingType="no" keyboardType="URL" '
                                                  'keyboardAppearance="alert" returnKeyType="done" enablesReturnKeyAutomatically="YES" smartDashesType="no" '
                                                  'smartInsertDeleteType="no" smartQuotesType="no" textContentType="url"/>\n'), "", resources=TVR),
    "text-view-keyboardDismissMode-interactive": constrained(text_view(TV_ATTRIBUTES + ' keyboardDismissMode="interactive"'), "", resources=TVR),
    "text-view-no-font": constrained(text_view(children=TV_BACKGROUND + TV_TEXT + TV_TRAITS), "", resources=TVR),
    "text-view-text-color-no-text": constrained(text_view(children=TV_BACKGROUND + TV_LABEL_COLOR + TV_FONT + TV_TRAITS),
                                                "", resources=TVR + system_color("labelColor", gray(0, 1))),
})
TEXT_VIEWS["text-view-no-alignment"] = constrained(text_view(TV_ATTRIBUTES.replace(' textAlignment="natural"', '')), "", resources=TVR)
TEXT_VIEWS["text-view-no-traits"] = constrained(text_view(children=TV_BACKGROUND + TV_TEXT + TV_FONT), "", resources=TVR)
TEXT_VIEWS["text-view-lproj"] = TEXT_VIEWS["text-view"]
LPROJ_XIBS.add("text-view-lproj")
EXPERIMENTS.update(TEXT_VIEWS)


# Round 52: gesture recognizers in storyboards: recognizers in a scene's objects after First Responder,
# attached to subviews or the root view, with an action to the controller or a segue, and IB's empty
# <gestureRecognizers/> element.
def sb_subview(identifier, y=10, recognizers=(), empty=True):
    attached = "".join(f'                                    <outletCollection property="gestureRecognizers" destination="{r}" appends="YES" id="o{r[:2]}-aa-aa1"/>\n'
                       for r in recognizers)
    return (f'                            <view contentMode="scaleToFill" id="{identifier}">\n'
            f'                                <rect key="frame" x="10" y="{y}" width="50" height="50"/>\n'
            '                                <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>\n'
            + ('                                <gestureRecognizers/>\n' if empty else "")
            + (f'                                <connections>\n{attached}                                </connections>\n' if attached else "")
            + '                            </view>\n')


def sb_recognizer(identifier, tag="tapGestureRecognizer", selector="tapped:", destination="BYZ-38-t0r", connections=None):
    body = connections if connections is not None else f'                        <action selector="{selector}" destination="{destination}" id="a{identifier[:2]}-aa-aa1"/>\n'
    if not body:
        return f'                <{tag} id="{identifier}"/>\n'
    return f'                <{tag} id="{identifier}">\n                    <connections>\n{body}                    </connections>\n                </{tag}>\n'


def sb_gestures(subviews, recognizers, attributes="", root_extra="", second=""):
    responder = '                <placeholder placeholderIdentifier="IBFirstResponder" id="dkx-z0-nzr" sceneMemberID="firstResponder"/>\n'
    first = scene(attributes=attributes, view_extra=root_extra + "                        <subviews>\n" + "".join(subviews) + "                        </subviews>\n")
    return storyboard(first.replace(responder, responder + "".join(recognizers)) + second)


SB_GESTURES = {
    "sb-gesture": sb_gestures([sb_subview("sub-vi-ew1", recognizers=["tap-aa-aa1"])], [sb_recognizer("tap-aa-aa1")]),
    "sb-gesture-empty-element": sb_gestures([sb_subview("sub-vi-ew1")], []),
    "sb-gesture-no-empty-element": sb_gestures([sb_subview("sub-vi-ew1", recognizers=["tap-aa-aa1"], empty=False)], [sb_recognizer("tap-aa-aa1")]),
    "sb-gesture-no-action": sb_gestures([sb_subview("sub-vi-ew1", recognizers=["tap-aa-aa1"])], [sb_recognizer("tap-aa-aa1", connections="")]),
    "sb-gesture-custom-controller": sb_gestures([sb_subview("sub-vi-ew1", recognizers=["tap-aa-aa1"])], [sb_recognizer("tap-aa-aa1")],
                                                attributes=' customClass="ViewController" customModule="T" customModuleProvider="target"'),
    "sb-gesture-root": sb_gestures([sb_subview("sub-vi-ew1")], [sb_recognizer("tap-aa-aa1")],
                                   root_extra='                        <gestureRecognizers/>\n                        <connections>\n'
                                              '                            <outletCollection property="gestureRecognizers" destination="tap-aa-aa1" appends="YES" id="ota-aa-aa1"/>\n'
                                              '                        </connections>\n'),
    "sb-gesture-three": sb_gestures([sb_subview("sub-vi-ew1", 10, ["zzz-aa-aa1"]), sb_subview("sub-vi-ew2", 70, ["qqq-aa-aa1"]), sb_subview("sub-vi-ew3", 130, ["mmm-aa-aa1"])],
                                    [sb_recognizer("zzz-aa-aa1", selector="first"), sb_recognizer("qqq-aa-aa1", selector="second"),
                                     sb_recognizer("mmm-aa-aa1", selector="third")]),
    "sb-gesture-three-swapped": sb_gestures([sb_subview("sub-vi-ew1", 10, ["zzz-aa-aa1"]), sb_subview("sub-vi-ew2", 70, ["qqq-aa-aa1"]), sb_subview("sub-vi-ew3", 130, ["mmm-aa-aa1"])],
                                            [sb_recognizer("mmm-aa-aa1", selector="third"), sb_recognizer("zzz-aa-aa1", selector="first"),
                                             sb_recognizer("qqq-aa-aa1", selector="second")]),
    "sb-gesture-swipe": sb_gestures([sb_subview("sub-vi-ew1", recognizers=["swp-aa-aa1"])],
                                    [sb_recognizer("swp-aa-aa1", tag="swipeGestureRecognizer").replace('id="swp-aa-aa1"', 'direction="right" id="swp-aa-aa1"')]),
    "sb-gesture-segue": sb_gestures([sb_subview("sub-vi-ew1", recognizers=["tap-aa-aa1"])],
                                    [sb_recognizer("tap-aa-aa1", connections='                        <segue destination="abc-de-fgh" kind="presentation" identifier="Show" id="seg-aa-aa1"/>\n')],
                                    second=scene(**SECOND)),
}
SB_GESTURES["sb-gesture-three-attach-permuted"] = sb_gestures(
    [sb_subview("sub-vi-ew1", 10, ["qqq-aa-aa1"]), sb_subview("sub-vi-ew2", 70, ["zzz-aa-aa1"]), sb_subview("sub-vi-ew3", 130, ["mmm-aa-aa1"])],
    [sb_recognizer("zzz-aa-aa1", selector="b"), sb_recognizer("mmm-aa-aa1", selector="a"), sb_recognizer("qqq-aa-aa1", selector="c")])
SB_GESTURES["sb-gesture-and-controller"] = sb_gestures(
    [sb_subview("sub-vi-ew1", 10, ["tap-aa-aa1"]),
     sb_subview("sub-vi-ew2", 70, empty=False).replace('id="sub-vi-ew2">', 'customClass="Box" customModule="T" customModuleProvider="target" id="sub-vi-ew2">').replace(
         "                            </view>\n", '                                <connections>\n                                    <outlet property="owner" destination="BYZ-38-t0r" id="own-aa-aa1"/>\n'
         "                                </connections>\n                            </view>\n")],
    [sb_recognizer("tap-aa-aa1")])
SB_GESTURES["sb-gesture-nested"] = sb_gestures(
    [sb_subview("sub-vi-ew1", 10, ["kaa-aa-aa1"]).replace("                                <gestureRecognizers/>\n",
        "                                <subviews>\n" + "".join("    " + line + "\n" for line in sb_subview("sub-vi-ew2", 5, ["kbb-aa-aa1"]).splitlines())
        + "                                </subviews>\n                                <gestureRecognizers/>\n"),
     sb_subview("sub-vi-ew3", 130, ["kcc-aa-aa1"])],
    [sb_recognizer("kaa-aa-aa1", selector="a"), sb_recognizer("kbb-aa-aa1", selector="b"), sb_recognizer("kcc-aa-aa1", selector="c")])
SB_GESTURES["sb-gesture-predict"] = sb_gestures(
    [sb_subview("sub-vi-ew1", 10, ["kdd-aa-aa1", "kbb-aa-aa1"]),
     sb_subview("sub-vi-ew2", 70, empty=False).replace('id="sub-vi-ew2">', 'customClass="Box" customModule="T" customModuleProvider="target" id="sub-vi-ew2">').replace(
         "                            </view>\n", '                                <connections>\n                                    <outlet property="owner" destination="BYZ-38-t0r" id="own-aa-aa1"/>\n'
         "                                </connections>\n                            </view>\n")],
    [sb_recognizer("kaa-aa-aa1", selector="a"), sb_recognizer("kbb-aa-aa1", selector="b"), sb_recognizer("kdd-aa-aa1", selector="d")],
    root_extra='                        <gestureRecognizers/>\n                        <connections>\n'
               '                            <outletCollection property="gestureRecognizers" destination="kaa-aa-aa1" appends="YES" id="oka-aa-aa1"/>\n'
               '                        </connections>\n').replace(
    '                </viewController>', '                    <connections>\n                        <outlet property="box" destination="sub-vi-ew2" id="box-aa-aa1"/>\n'
    '                    </connections>\n                </viewController>', 1)
SB_GESTURES["sb-vc-restoration-equal-storyboard-id"] = storyboard(controller_scene(1, ' restorationIdentifier="Second" storyboardIdentifier="Second"'),
                                                                  initial="vc1-aa-aaa")
STORYBOARDS.update(SB_GESTURES)


# Round 53: the order of connections of one name from sources of different classes (the corpus's
# pocket-casts SharePublishViewController, wikipedia WMFImageGalleryDetailOverlayView), and outlet
# collections of several names.
def connected(tag, identifier, y, connections, attributes=""):
    view = subview(identifier, (10, y, 100, 50), tag, attributes)
    return view.replace(f"                </{tag}>\n", f"                    <connections>\n{connections}                    </connections>\n                </{tag}>\n", 1)


def owner_outlet(prop, number, kind="outlet", extra=""):
    return f'                        <{kind} property="{prop}" destination="-1"{extra} id="c{number:02d}-aa-aaa"/>\n'


COLLECTION = ' collectionClass="NSMutableArray"'
CLASS_ORDER = {
    "oc-class-view-image": constrained(connected("view", "sub-vi-ew1", 20, owner_outlet("delegate", 1))
                                       + connected("imageView", "sub-vi-ew2", 120, owner_outlet("delegate", 2)), ""),
    "oc-class-image-view": constrained(connected("imageView", "sub-vi-ew1", 20, owner_outlet("delegate", 1))
                                       + connected("view", "sub-vi-ew2", 120, owner_outlet("delegate", 2)), ""),
    "oc-class-custom": constrained(connected("view", "sub-vi-ew1", 20, owner_outlet("delegate", 1), ' customClass="Aaa" customModule="T" customModuleProvider="target"')
                                   + connected("imageView", "sub-vi-ew2", 120, owner_outlet("delegate", 2)), ""),
    "oc-class-three": constrained(connected("view", "sub-vi-ew1", 20, owner_outlet("delegate", 1))
                                  + connected("scrollView", "sub-vi-ew2", 120, owner_outlet("delegate", 2))
                                  + connected("imageView", "sub-vi-ew3", 220, owner_outlet("delegate", 3)), ""),
    "oc-class-collections": constrained(connected("view", "sub-vi-ew1", 20, owner_outlet("others", 1, "outletCollection", COLLECTION))
                                        + connected("imageView", "sub-vi-ew2", 120, owner_outlet("others", 2, "outletCollection", COLLECTION)), ""),
    "oc-names": with_outlets(owner_outlet("zeta", 1, "outletCollection", COLLECTION).replace('destination="-1"', 'destination="sub-vi-ew1"')
                             + owner_outlet("alpha", 2, "outletCollection", COLLECTION).replace('destination="-1"', 'destination="sub-vi-ew2"')),
    "oc-names-shared": with_outlets(owner_outlet("zeta", 1, "outletCollection", COLLECTION).replace('destination="-1"', 'destination="sub-vi-ew1"')
                                    + owner_outlet("alpha", 2, "outletCollection", COLLECTION).replace('destination="-1"', 'destination="sub-vi-ew2"')
                                    + owner_outlet("alpha", 3, "outletCollection", COLLECTION).replace('destination="-1"', 'destination="sub-vi-ew1"')
                                    + owner_outlet("view", 4).replace('destination="-1"', f'destination="{ROOT}"')),
    "oc-names-two-sources": with_outlets(owner_outlet("items", 1, "outletCollection", COLLECTION).replace('destination="-1"', 'destination="sub-vi-ew1"'),
                                         owner_outlet("items", 2, "outletCollection", COLLECTION).replace('destination="-1"', 'destination="sub-vi-ew2"')),
}
CLASS_ORDER["oc-class-owner-image"] = with_outlets(owner_outlet("label", 1).replace('destination="-1"', 'destination="sub-vi-ew2"')).replace(
    '<view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="sub-vi-ew1">',
    '<imageView contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="sub-vi-ew1">', 1).replace(
    '                </view>\n                <view', '                    <connections>\n' + owner_outlet("label", 2).replace('destination="-1"', 'destination="sub-vi-ew2"')
    + '                    </connections>\n                </imageView>\n                <view', 1)
CLASS_ORDER["oc-class-owner-plain-image"] = CLASS_ORDER["oc-class-owner-image"].replace(' userLabel="File\'s Owner" customClass="Owner">', ' userLabel="File\'s Owner">')
CLASS_ORDER["oc-class-zowner-image"] = CLASS_ORDER["oc-class-owner-image"].replace(' userLabel="File\'s Owner" customClass="Owner">', ' userLabel="File\'s Owner" customClass="ZOwner">')
EXPERIMENTS.update(CLASS_ORDER)


# Round 54: button configurations (UIButton.Configuration, Xcode 13's buttons): IB's plain button with
# a title, then one change at a time (style, title, image, font, padding, placement, colors).
def configuration(attributes='style="plain" title="Button"', children=""):
    if not children:
        return f'<buttonConfiguration key="configuration" {attributes}/>\n'
    return f'<buttonConfiguration key="configuration" {attributes}>\n' + "".join(f"    {line}\n" for line in children.splitlines()) + "</buttonConfiguration>\n"


def configured(conf=None, state=BUTTON_STATE, resources=""):
    return constrained(button(children=state + (conf if conf is not None else configuration())), "", resources=resources)


CONFIGURATIONS = {
    "bc-plain-title": configured(),
    "bc-plain": configured(configuration('style="plain"')),
    "bc-plain-other-title": configured(configuration('style="plain" title="Done"')),
    "bc-no-state": configured(state=""),
    "bc-filled-title": configured(configuration('style="filled" title="Button"')),
    "bc-filled": configured(configuration('style="filled"')),
    "bc-gray-title": configured(configuration('style="gray" title="Button"')),
    "bc-tinted-title": configured(configuration('style="tinted" title="Button"')),
    "bc-image-symbol": configured(configuration('style="plain" image="plus" catalog="system"'), resources=BUTTON_SYMBOL),
    "bc-image-asset": configured(configuration('style="plain" image="Logo"'), resources=BUTTON_IMAGE),
    "bc-title-font": configured(configuration(children=font_description({"type": "system", "pointSize": "12"}).replace('key="fontDescription"', 'key="titleFontDescription"'))),
    "bc-title-font-style": configured(configuration(children=font_description({"style": "UICTFontTextStyleHeadline"}).replace('key="fontDescription"', 'key="titleFontDescription"'))),
    "bc-image-padding": configured(configuration('style="filled" image="plus" catalog="system" title="Button" imagePadding="8"'), resources=BUTTON_SYMBOL),
    "bc-image-leading": configured(configuration('style="filled" image="plus" catalog="system" imagePlacement="leading" title="Button" imagePadding="8"'), resources=BUTTON_SYMBOL),
    "bc-image-trailing": configured(configuration('style="plain" image="plus" catalog="system" imagePlacement="trailing" title="Button" imagePadding="5"'), resources=BUTTON_SYMBOL),
    "bc-base-foreground": configured(configuration(children='<color key="baseForegroundColor" systemColor="systemRedColor"/>'),
                                     resources=system_color("systemRedColor", rgb(1, 0.23137254901960785, 0.18823529411764706, 1))),
    "bc-symbol-scale": configured(configuration('style="plain" title="Button"', '<imageReference key="image" image="plus" catalog="system" symbolScale="large"/>\n'
                                                '<preferredSymbolConfiguration key="preferredSymbolConfigurationForImage" scale="large"/>'), resources=BUTTON_SYMBOL),
}
CONFIGURATIONS["bc-two"] = constrained(button(children=BUTTON_STATE + configuration()) + button(children=BUTTON_STATE + configuration('style="filled" title="Go"'),
                                                                                                identifier="bbb-bb-bb2", frame=(20, 100, 75, 35)), "")
for scale in ("default", "small", "medium"):
    CONFIGURATIONS[f"bc-symbol-scale-{scale}"] = configured(configuration('style="plain" title="Button"', f'<imageReference key="image" image="plus" catalog="system" symbolScale="{scale}"/>\n'
                                                                       f'<preferredSymbolConfiguration key="preferredSymbolConfigurationForImage" scale="{scale}"/>'), resources=BUTTON_SYMBOL)
CONFIGURATIONS["bc-symbol-point-size"] = configured(configuration('style="plain" title="Button"', '<imageReference key="image" image="plus" catalog="system" symbolScale="small"/>\n'
    '<preferredSymbolConfiguration key="preferredSymbolConfigurationForImage" configurationType="pointSize" pointSize="8" scale="small"/>'), resources=BUTTON_SYMBOL)
CONFIGURATIONS["bc-image-reference-only"] = configured(configuration('style="plain" title="Button"', '<imageReference key="image" image="plus" catalog="system" symbolScale="medium"/>'),
                                                       resources=BUTTON_SYMBOL)
CONFIGURATIONS["bc-label-foreground"] = configured(configuration(children='<color key="baseForegroundColor" systemColor="labelColor"/>'),
                                                   resources=system_color("labelColor", gray(0, 1)))
CONFIGURATIONS["bc-image-symbol-titled"] = configured(configuration('style="plain" image="plus" catalog="system" title="Button"'), resources=BUTTON_SYMBOL)
CONFIGURATIONS["bc-font-on-button"] = configured(state=font_description({"type": "system", "pointSize": "12"}) + "\n" + BUTTON_STATE)
EXPERIMENTS.update(CONFIGURATIONS)


# Round 55: attributed labels (usesAttributedText="YES"): fragments with fonts, colors and paragraph
# styles, as the corpus's pocket-casts and gomap documents have them.
ATTRIBUTED_LABEL = LABEL_ATTRIBUTES.replace('text="Label" textAlignment="natural"', 'usesAttributedText="YES"')
PARAGRAPH_15 = ('<paragraphStyle key="NSParagraphStyle" alignment="left" lineBreakMode="wordWrapping" baseWritingDirection="natural" '
                'lineHeightMultiple="1.2" tighteningFactorForTruncation="0.0"/>')
TEXT_COLOR_CATALOG = '<color key="NSColor" name="textColor" catalog="System" colorSpace="catalog"/>'


def attributed(*fragments):
    if not fragments:
        return '<attributedString key="attributedText"/>\n'
    body = "".join(f'    <fragment content="{content}">\n        <attributes>\n' + "".join(f"            {a}\n" for a in attributes)
                   + '        </attributes>\n    </fragment>\n' for content, attributes in fragments)
    return '<attributedString key="attributedText">\n' + body + '</attributedString>\n'


def attributed_label(*fragments, attributes=ATTRIBUTED_LABEL):
    return constrained(label(attributes=attributes, font="", colors='<nil key="highlightedColor"/>\n', extra=attributed(*fragments)).replace("                    \n", ""), "")


SYSTEM_15_META = '<font key="NSFont" metaFont="system" size="15"/>'
ATTRIBUTED_LABELS = {
    "al-empty": attributed_label(),
    "al-system-15": attributed_label(("Hello", [SYSTEM_15_META, PARAGRAPH_15])),
    "al-system-15-text-color": attributed_label(("Hello", [TEXT_COLOR_CATALOG, SYSTEM_15_META, PARAGRAPH_15])),
    "al-font-only": attributed_label(("Hello", ['<font key="NSFont" metaFont="system" size="17"/>'])),
    "al-paragraph-plain": attributed_label(("Hello", [SYSTEM_15_META, '<paragraphStyle key="NSParagraphStyle" alignment="left" lineBreakMode="wordWrapping" '
                                                                     'baseWritingDirection="natural" tighteningFactorForTruncation="0.0"/>'])),
    "al-gomap": attributed_label(("Go Map!!", ['<color key="NSColor" red="1" green="0.8057073951" blue="0.0" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>',
                                               '<font key="NSFont" size="36" name="HelveticaNeue-BoldItalic"/>',
                                               '<font key="NSOriginalFont" size="36" name="HelveticaNeue-BoldItalic"/>',
                                               '<paragraphStyle key="NSParagraphStyle" alignment="center" lineBreakMode="truncatingTail" baseWritingDirection="natural"/>'])),
    "al-named-font": attributed_label(("Hello", ['<font key="NSFont" size="17" name="CourierNewPSMT"/>'])),
    "al-two-fragments": attributed_label(("Hello ", [SYSTEM_15_META]), ("world", ['<font key="NSFont" metaFont="system" size="17"/>'])),
    "al-gray-color": attributed_label(("Hello", ['<color key="NSColor" white="0.33333333333333331" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>',
                                                 SYSTEM_15_META])),
}
ATTRIBUTED_LABELS["al-system-15-lproj"] = ATTRIBUTED_LABELS["al-system-15"]
LPROJ_XIBS.add("al-system-15-lproj")
ATTRIBUTED_LABELS["al-gomap-label"] = attributed_label(*[("Go Map!!", ['<color key="NSColor" red="1" green="0.8057073951" blue="0.0" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>',
    '<font key="NSFont" size="36" name="HelveticaNeue-BoldItalic"/>', '<font key="NSOriginalFont" size="36" name="HelveticaNeue-BoldItalic"/>',
    '<paragraphStyle key="NSParagraphStyle" alignment="center" lineBreakMode="truncatingTail" baseWritingDirection="natural"/>'])],
    attributes='opaque="NO" clipsSubviews="YES" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" '
               'usesAttributedText="YES" lineBreakMode="middleTruncation" baselineAdjustment="alignBaselines" minimumScaleFactor="0.5" translatesAutoresizingMaskIntoConstraints="NO"')
ATTRIBUTED_LABELS["al-pocket-label"] = attributed_label(("Description goes here ", [TEXT_COLOR_CATALOG, SYSTEM_15_META, PARAGRAPH_15]),
    attributes='opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" usesAttributedText="YES" '
               'lineBreakMode="tailTruncation" numberOfLines="0" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO"')
EXPERIMENTS.update(ATTRIBUTED_LABELS)


# Round 56: minimum scale factors of labels of text styles, which have no point size.
STYLE_SCALES = {}
for style, factor in (("Body", "0.5"), ("Subhead", "0.5"), ("Title2", "0.5"), ("Title0", "0.5"), ("Caption1", "0.5"), ("Body", "0.8"), ("Body", "0.65"),
                      ("Headline", "0.7")):
    STYLE_SCALES[f"label-style-scale-{style}-{factor}"] = constrained(label(
        attributes=LABEL_ATTRIBUTES.replace('adjustsFontSizeToFit="NO"', f'minimumScaleFactor="{factor}"'),
        font=font_description({"style": f"UICTFontTextStyle{style}"})), "")
for style in ("Callout", "Footnote", "Caption2", "Title1", "Title3"):
    STYLE_SCALES[f"label-style-scale-{style}-0.5"] = constrained(label(
        attributes=LABEL_ATTRIBUTES.replace('adjustsFontSizeToFit="NO"', 'minimumScaleFactor="0.5"'),
        font=font_description({"style": f"UICTFontTextStyle{style}"})), "")
for factor in ("0.8", "0.7", "0.65", "0.75", "0.25"):
    STYLE_SCALES[f"label-system-scale-{factor}"] = constrained(label(attributes=LABEL_ATTRIBUTES.replace('adjustsFontSizeToFit="NO"', f'minimumScaleFactor="{factor}"')), "")
EXPERIMENTS.update(STYLE_SCALES)


# Round 57: IB's accessibility overrides (a dynamic type preview), in xibs and storyboards, with text
# styles that could depend on it.
def overridden(document, attributes):
    return document.replace("    <dependencies>\n", f"    <accessibilityOverrides {attributes}/>\n    <dependencies>\n", 1)


OVERRIDES = {
    "a11y-overrides-3": overridden(EXPERIMENTS["view"], 'isEnabled="YES" dynamicTypePreference="3"'),
    "a11y-overrides-11": overridden(EXPERIMENTS["view"], 'isEnabled="YES" dynamicTypePreference="11"'),
    "a11y-overrides-disabled-9": overridden(EXPERIMENTS["view"], 'dynamicTypePreference="9"'),
    "a11y-overrides-style": overridden(STYLE_SCALES["label-style-scale-Body-0.5"], 'isEnabled="YES" dynamicTypePreference="11"'),
}
EXPERIMENTS.update(OVERRIDES)

# Round 58: container views of xibs, which have no embed segue, against views of the same attributes.
CONTAINERS = {}
for name, attributes in (("plain", ' opaque="NO"'), ("panel", ' opaque="NO" clearsContextBeforeDrawing="NO" userInteractionEnabled="NO"'),
                         ("clips", ' opaque="NO" clipsSubviews="YES" clearsContextBeforeDrawing="NO"')):
    for tag in ("containerView", "view"):
        CONTAINERS[f"container-{name}-{tag}"] = constrained(subview("ccc-cc-cc1", tag=tag, attributes=attributes), "")
CONTAINERS["container-background-containerView"] = constrained(subview("ccc-cc-cc1", tag="containerView", attributes=' opaque="NO"').replace(
    "                </containerView>", '                    <color key="backgroundColor" white="0.0" alpha="0.0" colorSpace="calibratedWhite"/>\n                </containerView>'), "")
CONTAINERS["container-background-view"] = CONTAINERS["container-background-containerView"].replace("containerView", "view")
EXPERIMENTS.update(CONTAINERS)

# Round 59: IB's misplaced flag (a frame its constraints disagree with), and image views of system
# symbols given by an image reference with a scale and a preferred symbol configuration.
MISPLACED = {
    "misplaced-view": constrained(subview("ccc-cc-cc1", attributes=' misplaced="YES"'), ""),
    "misplaced-label": constrained(label(attributes=LABEL_ATTRIBUTES.replace(' translatesAutoresizing', ' misplaced="YES" translatesAutoresizing')), ""),
    "misplaced-scroll": constrained(subview("ccc-cc-cc1", tag="scrollView", attributes=' misplaced="YES"'), ""),
    "misplaced-text-view": constrained(text_view(TV_ATTRIBUTES + ' misplaced="YES"'), "", resources=TVR),
}
MISPLACED["misplaced-scroll-plain"] = MISPLACED["misplaced-scroll"].replace(' misplaced="YES"', "")
SYMBOL_VIEW = subview("iii-ii-ii1", (112, 333, 168, 185), "imageView")
for name, children in (("reference", '<imageReference key="image" image="plus" catalog="system" symbolScale="small"/>'),
                       ("reference-preferred", '<imageReference key="image" image="plus" catalog="system" symbolScale="small"/>\n'
                                               '                    <preferredSymbolConfiguration key="preferredSymbolConfiguration" scale="small"/>'),
                       ("reference-large", '<imageReference key="image" image="plus" catalog="system" symbolScale="large"/>'),
                       ("preferred-medium", '<imageReference key="image" image="plus" catalog="system" symbolScale="default"/>\n'
                                            '                    <preferredSymbolConfiguration key="preferredSymbolConfiguration" scale="medium"/>')):
    MISPLACED[f"image-view-symbol-{name}"] = constrained(SYMBOL_VIEW.replace("                </imageView>", f"                    {children}\n                </imageView>"),
                                                          "", resources=BUTTON_SYMBOL)
MISPLACED["image-view-symbol-preferred-only"] = constrained(subview("iii-ii-ii1", (112, 333, 168, 185), "imageView", ' image="plus" catalog="system"').replace(
    "                </imageView>", '                    <preferredSymbolConfiguration key="preferredSymbolConfiguration" scale="small"/>\n                </imageView>'),
    "", resources=BUTTON_SYMBOL)
MISPLACED["segmented-lproj"] = EXPERIMENTS["segmented"]
LPROJ_XIBS.add("segmented-lproj")
EXPERIMENTS.update(MISPLACED)

# Round 60: symbol images' variable values, hierarchical rendering and preferred configurations of
# weights, point sizes and fonts, in image views and in buttons' states.
HIERARCHICAL = ('<hierarchicalColors>\n    <color systemColor="labelColor"/>\n    <color systemColor="secondaryLabelColor"/>\n'
                '    <color systemColor="tertiaryLabelColor"/>\n</hierarchicalColors>\n')
SYMBOL_COLORS = (system_color("labelColor", gray(0, 1)) + system_color("secondaryLabelColor", rgb(0.23529411759999999, 0.23529411759999999, 0.26274509800000001, 0.59999999999999998))
                 + system_color("tertiaryLabelColor", rgb(0.23529411759999999, 0.23529411759999999, 0.26274509800000001, 0.29999999999999999)))


def symbol_reference(attributes, colors=False):
    if not colors:
        return f'<imageReference key="image" image="plus" catalog="system"{attributes}/>\n'
    return f'<imageReference key="image" image="plus" catalog="system"{attributes}>\n' + "".join(f"    {l}\n" for l in HIERARCHICAL.splitlines()) + "</imageReference>\n"


def symbol_view(children, attributes=""):
    body = "".join(f"                    {l}\n" for l in children.splitlines())
    return constrained(subview("iii-ii-ii1", (112, 333, 168, 185), "imageView", attributes).replace("                </imageView>", body + "                </imageView>"),
                       "", resources=BUTTON_SYMBOL + SYMBOL_COLORS)


CUSTOM_BUTTON = 'opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" lineBreakMode="middleTruncation"'


def symbol_button(state_children):
    state = '<state key="normal">\n' + "".join(f"    {l}\n" for l in state_children.splitlines()) + "</state>\n"
    return constrained(button(CUSTOM_BUTTON, state, frame=(20, 40, 23, 23)), "", resources=BUTTON_SYMBOL + SYMBOL_COLORS)


def preferred_symbol(attributes, children=""):
    if not children:
        return f'<preferredSymbolConfiguration key="preferredSymbolConfiguration"{attributes}/>\n'
    return f'<preferredSymbolConfiguration key="preferredSymbolConfiguration"{attributes}>\n    {children}\n</preferredSymbolConfiguration>\n'


SYMBOLS = {
    "symbol-view-variable-0": symbol_view(symbol_reference(' symbolScale="large" variableValue="0.0"') + preferred_symbol(' scale="large"')),
    "symbol-view-variable-08": symbol_view(symbol_reference(' variableValue="0.80000000000000004"')),
    "symbol-view-hierarchical": symbol_view(symbol_reference(' renderingMode="hierarchical"', colors=True)),
    "symbol-view-hierarchical-variable": symbol_view(symbol_reference(' renderingMode="hierarchical" variableValue="1"', colors=True)),
    "symbol-view-hierarchical-scale": symbol_view(symbol_reference(' symbolScale="large" renderingMode="hierarchical"', colors=True)),
    "symbol-view-font": symbol_view(preferred_symbol(' configurationType="font"', font_description({"style": "UICTFontTextStyleHeadline"})), ' image="plus" catalog="system"'),
    "symbol-view-weight-light": symbol_view(preferred_symbol(' weight="light"'), ' image="plus" catalog="system"'),
    "symbol-view-weight-bold": symbol_view(preferred_symbol(' weight="bold"'), ' image="plus" catalog="system"'),
    "symbol-view-scale-weight": symbol_view(preferred_symbol(' scale="small" weight="regular"'), ' image="plus" catalog="system"'),
    "symbol-view-preferred-empty": symbol_view(preferred_symbol(""), ' image="plus" catalog="system"'),
    "symbol-view-point-size": symbol_view(preferred_symbol(' configurationType="pointSize" pointSize="12"'), ' image="plus" catalog="system"'),
    "symbol-button-hierarchical": symbol_button(symbol_reference(' renderingMode="hierarchical"', colors=True)),
    "symbol-button-hierarchical-light": symbol_button(symbol_reference(' renderingMode="hierarchical" variableValue="1"', colors=True) + preferred_symbol(' weight="light"')),
    "symbol-button-scale": symbol_button(symbol_reference(' symbolScale="large"')),
}
EXPERIMENTS.update(SYMBOLS)

# Round 61: toolbars as subviews, without items, as the corpus's wikipedia and uncloudnotes documents
# have them.
TOOLBAR_ATTRIBUTES = ' opaque="NO" clearsContextBeforeDrawing="NO" contentMode="scaleToFill"'


def toolbar(frame=(0, 0, 393, 49), items="<items/>", extra="", constraints=""):
    view = subview("tbr-aa-aa1", frame, "toolbar", TOOLBAR_ATTRIBUTES, constraints=constraints)
    inner = "".join(f"                    {l}\n" for l in (items + extra).splitlines())
    return view.replace("                </toolbar>", inner + "                </toolbar>")


TOOLBARS = {
    "toolbar-empty": constrained(toolbar(), ""),
    "toolbar-44": constrained(toolbar(frame=(0, 808, 393, 44)), ""),
    "toolbar-no-items": constrained(toolbar(items=""), ""),
    "toolbar-height-constraint": constrained(toolbar(frame=(0, 808, 393, 44), constraints='                        <constraint firstAttribute="height" constant="44" id="tbh-aa-aa1"/>\n'), ""),
    "toolbar-negative-x": constrained(toolbar(frame=(-8, 0, 423, 49)), ""),
    "toolbar-flexible-item": constrained(toolbar(items='<items>\n    <barButtonItem style="plain" systemItem="flexibleSpace" id="flx-aa-aa1"/>\n</items>'), ""),
}
STORYBOARDS["sb-toolbar"] = storyboard(scene(view_extra="                        <subviews>\n" + toolbar(frame=(0, 808, 393, 44)).replace("                ", "                            ", 1) + "                        </subviews>\n"))
EXPERIMENTS.update(TOOLBARS)

# Round 62: WebKit views, with IB's web view configuration.
def web_view(attributes="", preferences="<wkPreferences key=\"preferences\"/>", extra=""):
    body = (extra + '<wkWebViewConfiguration key="configuration">\n    <audiovisualMediaTypes key="mediaTypesRequiringUserActionForPlayback" none="YES"/>\n'
            f'    {preferences}\n</wkWebViewConfiguration>\n')
    view = subview("wkw-aa-aa1", (16, 118, 361, 587), "wkWebView", attributes)
    return view.replace("                </wkWebView>", "".join(f"                    {l}\n" for l in body.splitlines()) + "                </wkWebView>")


WEB_VIEWS = {
    "web-view": constrained(web_view(), ""),
    "web-view-clear": constrained(web_view(extra='<color key="backgroundColor" white="0.0" alpha="0.0" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>\n'), ""),
    "web-view-minimum-font": constrained(web_view(preferences='<wkPreferences key="preferences" minimumFontSize="6"/>'), ""),
    "web-view-custom-class": constrained(web_view(' customClass="HTMLView" customModule="T" customModuleProvider="target"'), ""),
}
STORYBOARDS["sb-web-view"] = storyboard(scene(view_extra="                        <subviews>\n" + web_view().replace("                ", "                            ", 1) + "                        </subviews>\n"))
EXPERIMENTS.update(WEB_VIEWS)

# Round 63 (B-290): whether the order of several objects' runtime attributes past the 9th object moves
# with changes that leave the nib as it is (IB's labels, unused resources, attribute order).
B290 = {"b290-base": ORDERS["udra-order-many-12"]}
B290["b290-label-one"] = B290["b290-base"].replace('id="v05-aa-aa1"', 'userLabel="Fifth" id="v05-aa-aa1"', 1)
B290["b290-labels-long"] = re.sub(r'id="(v\d\d)-aa-aa1"', lambda m: f'userLabel="{"x" * 200}{m.group(1)}" id="{m.group(1)}-aa-aa1"', B290["b290-base"])
B290["b290-resources"] = B290["b290-base"].replace("</document>", "    <resources>\n" + "".join(f'        <image name="Unused{k}" width="10" height="10"/>\n' for k in range(40))
                                                    + "    </resources>\n</document>")
B290["b290-attribute-order"] = re.sub(r'<view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="(v\d\d-aa-aa1)">',
                                      r'<view id="\1" translatesAutoresizingMaskIntoConstraints="NO" contentMode="scaleToFill">', B290["b290-base"])
B290["b290-placeholder-constraints"] = B290["b290-base"].replace('id="v00-aa-aa1">', 'id="v00-aa-aa1">\n                    <constraints>\n' + "".join(
    f'                        <constraint firstAttribute="width" constant="{10 + k}" placeholder="YES" id="ph{k}-aa-aa1"/>\n' for k in range(5)) + '                    </constraints>', 1)
B290["b290-placeholder-constraints-late"] = B290["b290-base"].replace('id="v11-aa-aa1">', 'id="v11-aa-aa1">\n                    <constraints>\n' + "".join(
    f'                        <constraint firstAttribute="width" constant="{10 + k}" placeholder="YES" id="ph{k}-aa-aa1"/>\n' for k in range(5)) + '                    </constraints>', 1)
EXPERIMENTS.update(B290)

# Round 64: navigation bars among subviews (not a navigation controller's): items of one navigation
# item, as the corpus's uncloudnotes launch screens and gomap's display settings have them.
def sub_nav_bar(item='<navigationItem id="nvi-aa-aa1"/>', attributes="", frame=(0, 0, 393, 64), constraints=""):
    view = subview("nvb-aa-aa1", frame, "navigationBar", attributes, constraints=constraints)
    body = "<items>\n" + "".join(f"    {l}\n" for l in item.splitlines()) + "</items>\n"
    return view.replace("                </navigationBar>", "".join(f"                    {l}\n" for l in body.splitlines()) + "                </navigationBar>")


SUB_NAV_BARS = {
    "nav-bar-sub-empty-item": constrained(sub_nav_bar(constraints='                        <constraint firstAttribute="height" constant="64" id="nbh-aa-aa1"/>\n'), ""),
    "nav-bar-sub-unconstrained": constrained(sub_nav_bar(), ""),
    "nav-bar-sub-title": constrained(sub_nav_bar('<navigationItem title="Hello" id="nvi-aa-aa1"/>'), ""),
    "nav-bar-sub-opaque": constrained(sub_nav_bar(attributes=' translucent="NO"', frame=(0, 48, 393, 54)), ""),
    "nav-bar-sub-done": constrained(sub_nav_bar('<navigationItem title="Hello" id="nvi-aa-aa1">\n    <barButtonItem key="rightBarButtonItem" style="done" systemItem="done" id="dne-aa-aa1"/>\n</navigationItem>'), ""),
}
STORYBOARDS["sb-nav-bar-sub"] = storyboard(scene(view_extra="                        <subviews>\n" + sub_nav_bar(constraints='                        <constraint firstAttribute="height" constant="64" id="nbh-aa-aa1"/>\n').replace("                ", "                            ", 1) + "                        </subviews>\n"))
EXPERIMENTS.update(SUB_NAV_BARS)

# Round 65: IB's comments on a view, a text view with editable text attributes and no text, date
# pickers and picker views, as the corpus's gomap, cwa and kickstarter documents have them.
PICKERS = {
    "user-comments-label": constrained(label(extra='<attributedString key="userComments">\n    <fragment content="Placeholder - Do not translate"/>\n</attributedString>\n'), ""),
    "text-view-editing-attributes": constrained(text_view('clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="scaleToFill" scrollEnabled="NO" '
        'showsHorizontalScrollIndicator="NO" showsVerticalScrollIndicator="NO" contentInsetAdjustmentBehavior="never" editable="NO" allowsEditingTextAttributes="YES"',
        TV_BACKGROUND + '<nil key="text"/>\n' + font_description({"type": "system", "pointSize": "17"}) + "\n"
        + '<textInputTraits key="textInputTraits" autocapitalizationType="sentences" textContentType="url"/>\n<dataDetectorType key="dataDetectorTypes" link="YES"/>\n'),
        "", resources=TVR),
    "text-view-nil-text": constrained(text_view(children=TV_BACKGROUND + '<nil key="text"/>\n' + TV_FONT + TV_TRAITS), "", resources=TVR),
    "date-picker-countdown": constrained(subview("dpk-aa-aa1", (0, 0, 350, 216), "datePicker", ' contentHorizontalAlignment="center" contentVerticalAlignment="center" '
                                                 'datePickerMode="countDownTimer" minuteInterval="1" useCurrentDate="NO"'), ""),
    "date-picker-date-and-time": constrained(subview("dpk-aa-aa1", (0, 0, 350, 216), "datePicker", ' contentHorizontalAlignment="center" contentVerticalAlignment="center" '
                                                     'datePickerMode="dateAndTime" minuteInterval="1"'), ""),
    "picker-view": constrained(subview("pkv-aa-aa1", (0, 359, 393, 216), "pickerView"), ""),
    "picker-view-background": constrained(subview("pkv-aa-aa1", (0, 359, 393, 216), "pickerView").replace("                </pickerView>",
        '                    <color key="backgroundColor" systemColor="secondarySystemBackgroundColor"/>\n                </pickerView>'), "",
        resources=system_color("secondarySystemBackgroundColor", rgb(0.94901960780000005, 0.94901960780000005, 0.96862745100000003, 1))),
    "picker-view-margins": constrained(subview("pkv-aa-aa1", (0, 0, 165, 80), "pickerView", ' preservesSuperviewLayoutMargins="YES"'), ""),
}
EXPERIMENTS.update(PICKERS)
STORYBOARDS["sb-a11y-overrides"] = overridden(STORYBOARDS["storyboard"], 'isEnabled="YES" dynamicTypePreference="5"')
EXPERIMENTS["cvcell-gesture-element"] = CV_CELLS["cvcell"].replace("            </collectionViewCellContentView>\n",
                                                                 "            </collectionViewCellContentView>\n            <gestureRecognizers/>\n", 1)
EXPERIMENTS["gesture-empty-element"] = EXPERIMENTS["gesture-tap"].replace('<connections>\n                        <outletCollection', '<gestureRecognizers/>\n                    <connections>\n                        <outletCollection', 1)
EXPERIMENTS["gesture-empty-element-only"] = constrained(subview("sss-ss-ss1").replace("                </view>", "                    <gestureRecognizers/>\n                </view>", 1), "")


# Round 30: table view controllers in storyboards, as tofu's and Xcode's templates write them: empty,
# with prototype cells (empty, with a label, two, a custom class), static sections, in a navigation
# controller, with a custom class, grouped; one change at a time.
def tvc_cell(number, y=28, height=44, content_subviews="", attributes=' reuseIdentifier="Cell"', style=""):
    cell_id, content_id = f"cel-aa-aa{number}", f"ccv-aa-aa{number}"
    return (f'                            <tableViewCell clipsSubviews="YES" contentMode="scaleToFill" selectionStyle="default" indentationWidth="10"{attributes}{style} id="{cell_id}">\n'
            f'                                <rect key="frame" x="0.0" y="{y}" width="393" height="{height}"/>\n'
            '                                <autoresizingMask key="autoresizingMask"/>\n'
            '                                <tableViewCellContentView key="contentView" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" '
            f'tableViewCell="{cell_id}" id="{content_id}">\n'
            f'                                    <rect key="frame" x="0.0" y="0.0" width="393" height="{height}"/>\n'
            f'                                    <autoresizingMask key="autoresizingMask"/>\n{content_subviews}'
            '                                </tableViewCellContentView>\n                            </tableViewCell>\n')


def tvc_scene(body="", attributes="", table_attributes=TABLE_ATTRIBUTES.replace(' translatesAutoresizingMaskIntoConstraints="NO"', ''), outlets=True,
              after_view="", data_mode="prototypes", extra=""):
    connections = ('                        <connections>\n'
                   '                            <outlet property="dataSource" destination="tvc-aa-aaa" id="tds-aa-aaa"/>\n'
                   '                            <outlet property="delegate" destination="tvc-aa-aaa" id="tdl-aa-aaa"/>\n'
                   '                        </connections>\n') if outlets else ""
    mode = f' dataMode="{data_mode}"' if data_mode else ""
    return ('        <scene sceneID="tvs-aa-aaa">\n            <objects>\n'
            f'                <tableViewController id="tvc-aa-aaa"{attributes} sceneMemberID="viewController">\n'
            f'                    <tableView key="view" {table_attributes.replace(" style=", mode + " style=")} id="tbv-aa-aaa">\n'
            '                        <rect key="frame" x="0.0" y="0.0" width="393" height="852"/>\n'
            f'                        <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>\n{extra}{body}{connections}'
            f'                    </tableView>\n{after_view}                </tableViewController>\n'
            '                <placeholder placeholderIdentifier="IBFirstResponder" id="tfr-aa-aaa" sceneMemberID="firstResponder"/>\n'
            '            </objects>\n            <point key="canvasLocation" x="0" y="0"/>\n        </scene>\n')


def prototypes(*cells):
    return "                        <prototypes>\n" + "".join(cells) + "                        </prototypes>\n"


def tvc_label(identifier="tlb-aa-aa1", frame=(20, 11, 353, 21), text="Title", extra_attributes=' translatesAutoresizingMaskIntoConstraints="NO"'):
    x, y, w, h = frame
    return ('                                    <subviews>\n'
            f'                                        <label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" '
            f'text="{text}" textAlignment="natural" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO"{extra_attributes} id="{identifier}">\n'
            f'                                            <rect key="frame" x="{x}" y="{y}" width="{w}" height="{h}"/>\n'
            '                                            <fontDescription key="fontDescription" type="system" pointSize="17"/>\n'
            '                                            <nil key="textColor"/>\n                                            <nil key="highlightedColor"/>\n'
            '                                        </label>\n                                    </subviews>\n')


LABEL_MARGINS = ('                                    <constraints>\n'
                 '                                        <constraint firstItem="tlb-aa-aa1" firstAttribute="leading" secondItem="ccv-aa-aa1" secondAttribute="leadingMargin" id="tl1-aa-aaa"/>\n'
                 '                                        <constraint firstItem="tlb-aa-aa1" firstAttribute="centerY" secondItem="ccv-aa-aa1" secondAttribute="centerY" id="tl2-aa-aaa"/>\n'
                 '                                    </constraints>\n')
STATIC = ('                        <sections>\n                            <tableViewSection{header} id="sec-aa-aa1">\n                                <cells>\n{cells}'
          '                                </cells>\n                            </tableViewSection>\n                        </sections>\n')
TVC_CUSTOM = ' customClass="ListController" customModule="T" customModuleProvider="target"'
TVCS = {
    "sb-tvc-empty": storyboard(tvc_scene(), initial="tvc-aa-aaa"),
    "sb-tvc-no-outlets": storyboard(tvc_scene(outlets=False), initial="tvc-aa-aaa"),
    "sb-tvc-no-data-mode": storyboard(tvc_scene(data_mode=None), initial="tvc-aa-aaa"),
    "sb-tvc-custom": storyboard(tvc_scene(attributes=TVC_CUSTOM), initial="tvc-aa-aaa"),
    "sb-tvc-grouped": storyboard(tvc_scene(table_attributes=TABLE_ATTRIBUTES.replace(' translatesAutoresizingMaskIntoConstraints="NO"', '')
                                           .replace('style="plain"', 'style="grouped"').replace('"28"', '"18"')), initial="tvc-aa-aaa"),
    "sb-tvc-background-system": storyboard(tvc_scene(extra='                        <color key="backgroundColor" systemColor="systemBackgroundColor"/>\n'),
                                           initial="tvc-aa-aaa", resources=system_color("systemBackgroundColor", gray(1, 1))),
    "sb-tvc-prototype": storyboard(tvc_scene(prototypes(tvc_cell(1))), initial="tvc-aa-aaa"),
    "sb-tvc-prototype-no-reuse": storyboard(tvc_scene(prototypes(tvc_cell(1, attributes=""))), initial="tvc-aa-aaa"),
    "sb-tvc-prototype-label": storyboard(tvc_scene(prototypes(tvc_cell(1, content_subviews=tvc_label() + LABEL_MARGINS))), initial="tvc-aa-aaa"),
    "sb-tvc-prototype-two": storyboard(tvc_scene(prototypes(tvc_cell(1), tvc_cell(2, y=72, attributes=' reuseIdentifier="Other"'))), initial="tvc-aa-aaa"),
    "sb-tvc-prototype-custom-cell": storyboard(tvc_scene(prototypes(tvc_cell(1, attributes=' reuseIdentifier="Cell" customClass="ItemCell" customModule="T" customModuleProvider="target"'))),
                                               initial="tvc-aa-aaa"),
    "sb-tvc-prototype-cell-outlet": storyboard(tvc_scene(prototypes(tvc_cell(1, attributes=' reuseIdentifier="Cell" customClass="ItemCell" customModule="T" customModuleProvider="target"',
                                                                             content_subviews=tvc_label() + LABEL_MARGINS).replace(
        '                            </tableViewCell>\n', '                                <connections>\n'
        '                                    <outlet property="titleLabel" destination="tlb-aa-aa1" id="col-aa-aaa"/>\n                                </connections>\n'
        '                            </tableViewCell>\n'))), initial="tvc-aa-aaa"),
    "sb-tvc-in-nav": storyboard(navigation_scene("tvc-aa-aaa"), tvc_scene(prototypes(tvc_cell(1)), after_view=navigation_item()), initial="nvc-aa-aaa"),
    "sb-tvc-static": storyboard(tvc_scene(STATIC.format(header="", cells=tvc_cell(1, y=0, attributes="", content_subviews=tvc_label())), data_mode="static"),
                                initial="tvc-aa-aaa"),
    "sb-tvc-static-header": storyboard(tvc_scene(STATIC.format(header=' headerTitle="Display"', cells=tvc_cell(1, y=0, attributes="")), data_mode="static"),
                                       initial="tvc-aa-aaa"),
    "sb-tvc-static-two-cells": storyboard(tvc_scene(STATIC.format(header="", cells=tvc_cell(1, y=0, attributes="") + tvc_cell(2, y=44, attributes="")),
                                                    data_mode="static"), initial="tvc-aa-aaa"),
}
TVCS["sb-tvc-prototype-three"] = storyboard(tvc_scene(prototypes(tvc_cell(1, attributes=' reuseIdentifier="Zeta"'),
                                                                 tvc_cell(2, y=72, attributes=' reuseIdentifier="Alpha"'),
                                                                 tvc_cell(3, y=116, attributes=' reuseIdentifier="Mid"'))), initial="tvc-aa-aaa")
TVCS["sb-tvc-prototype-five"] = storyboard(tvc_scene(prototypes(*(tvc_cell(k + 1, y=28 + 44 * k, attributes=f' reuseIdentifier="{name}"')
                                                                    for k, name in enumerate(["Zeta", "Alpha", "Mid", "Beta", "Cell"])))), initial="tvc-aa-aaa")
TVCS["sb-tvc-in-nav-custom"] = storyboard(navigation_scene("tvc-aa-aaa", ' automaticallyAdjustsScrollViewInsets="NO"', ' largeTitles="YES"'),
                                          tvc_scene(prototypes(tvc_cell(1)), attributes=TVC_CUSTOM, after_view=navigation_item()), initial="nvc-aa-aaa")
TVCS["sb-nav-root-outlet"] = storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, ' customClass="RootController" customModule="T" customModuleProvider="target"',
                                                                                         after_view=navigation_item(), view_extra=SUBVIEW_OUTLET,
                                                                                         connections='                        <outlet property="box" destination="sbv-aa-aaa" id="out-aa-aa1"/>\n'),
                                        initial="nvc-aa-aaa")
TVCS["sb-nav-root-custom"] = storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, ' customClass="RootController" customModule="T" customModuleProvider="target"',
                                                                                         after_view=navigation_item()), initial="nvc-aa-aaa")
STORYBOARDS.update(TVCS)


# Round 31: segues a table view cell triggers, as tofu's account creation does: from a static cell and
# from a prototype cell, show and presentation, with and without an identifier, to a plain controller.
def cell_segue(kind, identifier=None):
    named = f' identifier="{identifier}"' if identifier else ""
    return ('                                <connections>\n'
            f'                                    <segue destination="vc2-aa-aaa" kind="{kind}"{named} id="csg-aa-aaa"/>\n'
            '                                </connections>\n')


def with_cell_connections(cell, connections):
    return cell.replace('                            </tableViewCell>\n', connections + '                            </tableViewCell>\n')


CELL_SEGUES = {}
for kind in ("show", "presentation"):
    for identifier in (None, "Pick"):
        suffix = f"{kind}" + ("-named" if identifier else "")
        CELL_SEGUES[f"sb-cellseg-static-{suffix}"] = storyboard(
            tvc_scene(STATIC.format(header="", cells=with_cell_connections(tvc_cell(1, y=0, attributes=""), cell_segue(kind, identifier))), data_mode="static"),
            controller_scene(2), initial="tvc-aa-aaa")
        CELL_SEGUES[f"sb-cellseg-prototype-{suffix}"] = storyboard(
            tvc_scene(prototypes(with_cell_connections(tvc_cell(1), cell_segue(kind, identifier)))), controller_scene(2), initial="tvc-aa-aaa")
CELL_SEGUES["sb-cellseg-static-two"] = storyboard(
    tvc_scene(STATIC.format(header="", cells=with_cell_connections(tvc_cell(1, y=0, attributes=""), cell_segue("show"))
                            + with_cell_connections(tvc_cell(2, y=44, attributes=""), cell_segue("show", "Second").replace("csg-aa-aaa", "csg-aa-aa2"))),
              data_mode="static"), controller_scene(2), initial="tvc-aa-aaa")
CELL_SEGUES["sb-cellseg-static-and-controller"] = storyboard(
    tvc_scene(STATIC.format(header="", cells=with_cell_connections(tvc_cell(1, y=0, attributes=""), cell_segue("show"))), data_mode="static",
              after_view='                    <connections>\n                        <segue destination="vc2-aa-aaa" kind="presentation" identifier="Edit" id="tsg-aa-aaa"/>\n'
                         '                    </connections>\n'),
    controller_scene(2), initial="tvc-aa-aaa")
# The order of several segues' templates, their viewController outlets and upstream placeholders: ids
# whose document, alphabetical and hash orders differ, on the controller, on cells, and both.
SEGUE_IDS = ["Qx4-pp-k2L", "a1B-zz-9Yt", "M0n-ee-T7c", "z9Z-aa-1Ab"]
CELL_SEGUES["sb-segorder-controller"] = storyboard(controller_scene(1, connections="".join(
    f'                        <segue destination="vc2-aa-aaa" kind="show" identifier="S{k}" id="{i}"/>\n' for k, i in enumerate(SEGUE_IDS))),
    controller_scene(2), initial="vc1-aa-aaa")
CELL_SEGUES["sb-segorder-cells"] = storyboard(tvc_scene(STATIC.format(header="", cells="".join(
    with_cell_connections(tvc_cell(k + 1, y=44 * k, attributes=""), cell_segue("show").replace("csg-aa-aaa", i)) for k, i in enumerate(SEGUE_IDS))),
    data_mode="static"), controller_scene(2), initial="tvc-aa-aaa")
CELL_SEGUES["sb-segorder-mixed"] = storyboard(tvc_scene(STATIC.format(header="", cells="".join(
    with_cell_connections(tvc_cell(k + 1, y=44 * k, attributes=""), cell_segue("show").replace("csg-aa-aaa", i)) for k, i in enumerate(SEGUE_IDS[:2]))),
    data_mode="static", after_view='                    <connections>\n' + "".join(
        f'                        <segue destination="vc2-aa-aaa" kind="presentation" identifier="P{k}" id="{i}"/>\n' for k, i in enumerate(SEGUE_IDS[2:]))
    + '                    </connections>\n'), controller_scene(2), initial="tvc-aa-aaa")
CELL_SEGUES["sb-cellseg-nav-root"] = storyboard(navigation_scene("tvc-aa-aaa"), tvc_scene(
    STATIC.format(header="", cells=with_cell_connections(tvc_cell(1, y=0, attributes=""), cell_segue("show")) + tvc_cell(2, y=44, attributes="")),
    data_mode="static", attributes=TVC_CUSTOM, after_view=navigation_item() + '                    <connections>\n'
    '                        <segue destination="vc2-aa-aaa" kind="presentation" identifier="Edit" id="tsg-aa-aaa"/>\n                    </connections>\n'),
    controller_scene(2), initial="nvc-aa-aaa")
# Round 69: segues a cell's accessory button triggers (trigger="accessoryAction"), as the corpus's
# uncloudnotes EmployeeDirectory and gomap display settings have them, and the detail button accessory.
ACCESSORY = ' reuseIdentifier="Cell" accessoryType="detailButton"'
ACCESSORY_SEGUE = '                                    <segue destination="vc2-aa-aaa" kind="show" identifier="Details" trigger="accessoryAction" id="asg-aa-aaa"/>\n'
CELL_SEGUES["sb-cell-detail-button"] = storyboard(tvc_scene(prototypes(tvc_cell(1, attributes=ACCESSORY))), initial="tvc-aa-aaa")
CELL_SEGUES["sb-cellseg-accessory"] = storyboard(tvc_scene(prototypes(with_cell_connections(tvc_cell(1, attributes=ACCESSORY),
    '                                <connections>\n' + ACCESSORY_SEGUE + '                                </connections>\n'))), controller_scene(2), initial="tvc-aa-aaa")
CELL_SEGUES["sb-cellseg-accessory-unnamed"] = CELL_SEGUES["sb-cellseg-accessory"].replace(' identifier="Details"', "")
CELL_SEGUES["sb-cellseg-accessory-and-selection"] = storyboard(tvc_scene(prototypes(with_cell_connections(tvc_cell(1, attributes=ACCESSORY),
    '                                <connections>\n                                    <segue destination="vc2-aa-aaa" kind="show" identifier="Pick" id="csg-aa-aaa"/>\n'
    + ACCESSORY_SEGUE + '                                </connections>\n'))), controller_scene(2), initial="tvc-aa-aaa")
CELL_SEGUES["sb-cellseg-accessory-static"] = storyboard(tvc_scene(STATIC.format(header="", cells=with_cell_connections(tvc_cell(1, y=0, attributes=' accessoryType="detailButton"'),
    '                                <connections>\n' + ACCESSORY_SEGUE + '                                </connections>\n')), data_mode="static"), controller_scene(2), initial="tvc-aa-aaa")
# Round 70: collection view controllers, whose view is their collection view, as the corpus's
# netnewswire storyboards have them: bare, with a prototype cell, a custom class and identifier, and
# without clearing the selection.
def cvc_scene(cells="", attributes="", outlets=True):
    connections = ('<connections>\n    <outlet property="dataSource" destination="cvc-aa-aaa" id="cds-aa-aa1"/>\n'
                   '    <outlet property="delegate" destination="cvc-aa-aaa" id="cdl-aa-aa1"/>\n</connections>\n') if outlets else ""
    cells_element = "<cells>\n" + "".join(f"    {line}\n" for line in cells.splitlines()) + "</cells>\n" if cells else ""
    body = ('<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>\n<autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>\n'
            + FLOW.replace(' id="flw', ' id="cfl') + cells_element + connections)
    return ('        <scene sceneID="cvs-aa-aaa">\n            <objects>\n'
            f'                <collectionViewController id="cvc-aa-aaa"{attributes} sceneMemberID="viewController">\n'
            '                    <collectionView key="view" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="scaleToFill" dataMode="prototypes" id="cvv-aa-aaa">\n'
            + "".join(f"                        {line}\n" for line in body.splitlines())
            + '                    </collectionView>\n                </collectionViewController>\n'
            '                <placeholder placeholderIdentifier="IBFirstResponder" id="cfr-aa-aaa" sceneMemberID="firstResponder"/>\n'
            '            </objects>\n            <point key="canvasLocation" x="0" y="0"/>\n        </scene>\n')


CVCS = {
    "sb-cvc": storyboard(cvc_scene(), initial="cvc-aa-aaa"),
    "sb-cvc-no-outlets": storyboard(cvc_scene(outlets=False), initial="cvc-aa-aaa"),
    "sb-cvc-cell": storyboard(cvc_scene(sb_cv_cell("cel-aa-aa1", "Cell")), initial="cvc-aa-aaa"),
    "sb-cvc-custom": storyboard(cvc_scene(attributes=' storyboardIdentifier="Grid" customClass="GridController" customModule="T" customModuleProvider="target"'),
                                initial="cvc-aa-aaa"),
    "sb-cvc-keeps-selection": storyboard(cvc_scene(attributes=' clearsSelectionOnViewWillAppear="NO"'), initial="cvc-aa-aaa"),
}
CVCS["sb-cvc-netnewswire"] = storyboard(cvc_scene(attributes=' storyboardIdentifier="Feeds" title="Feeds" useStoryboardIdentifierAsRestorationIdentifier="YES" '
                                                             'clearsSelectionOnViewWillAppear="NO"'), initial="cvc-aa-aaa")
CVCS["sb-tvc-keeps-selection"] = storyboard(tvc_scene(attributes=' clearsSelectionOnViewWillAppear="NO"'), initial="tvc-aa-aaa")
CVCS["sb-cvc-keeps-selection-segue"] = storyboard(cvc_scene(attributes=' clearsSelectionOnViewWillAppear="NO"').replace(
    '                    </collectionView>\n', '                    </collectionView>\n                    <connections>\n'
    '                        <segue destination="vc2-aa-aaa" kind="show" identifier="Open" id="cvg-aa-aaa"/>\n                    </connections>\n'),
    controller_scene(2), initial="cvc-aa-aaa")
CELL_SEGUES.update(CVCS)

# Round 71: split view controllers, as Xcode's master-detail template and the corpus's uncloudnotes
# storyboards have them: a master and a detail relationship, a title, toolbar items, a navigation
# controller as master.
def split_scene(master="vc1-aa-aaa", detail="vc2-aa-aaa", attributes="", extra=""):
    return ('        <scene sceneID="sps-aa-aaa">\n            <objects>\n'
            f'                <splitViewController id="spl-aa-aaa"{attributes} sceneMemberID="viewController">\n{extra}'
            '                    <connections>\n'
            f'                        <segue destination="{master}" kind="relationship" relationship="masterViewController" id="spm-aa-aaa"/>\n'
            f'                        <segue destination="{detail}" kind="relationship" relationship="detailViewController" id="spd-aa-aaa"/>\n'
            '                    </connections>\n                </splitViewController>\n'
            '                <placeholder placeholderIdentifier="IBFirstResponder" id="sfr-aa-aaa" sceneMemberID="firstResponder"/>\n'
            '            </objects>\n            <point key="canvasLocation" x="-800" y="0"/>\n        </scene>\n')


SPLITS = {
    "sb-split-plain": storyboard(split_scene(), controller_scene(1), controller_scene(2), initial="spl-aa-aaa"),
    "sb-split-title": storyboard(split_scene(attributes=' title="Notes"'), controller_scene(1), controller_scene(2), initial="spl-aa-aaa"),
    "sb-split-toolbar-items": storyboard(split_scene(extra="                    <toolbarItems/>\n"), controller_scene(1), controller_scene(2), initial="spl-aa-aaa"),
    "sb-split-nav-master": storyboard(split_scene(master="nvc-aa-aaa"), navigation_scene("vc1-aa-aaa"), controller_scene(1), controller_scene(2), initial="spl-aa-aaa"),
    "sb-split-swapped": storyboard(split_scene().replace('relationship="masterViewController" id="spm', 'relationship="XX" id="spm').replace(
        'relationship="detailViewController" id="spd', 'relationship="masterViewController" id="spd').replace('relationship="XX"', 'relationship="detailViewController"'),
        controller_scene(1), controller_scene(2), initial="spl-aa-aaa"),
}
SPLITS["sb-split-scene-order"] = storyboard(split_scene(), controller_scene(2), controller_scene(1), initial="spl-aa-aaa")
SPLITS["sb-split-segue-order"] = storyboard(split_scene(master="vc2-aa-aaa", detail="vc1-aa-aaa"), controller_scene(1), controller_scene(2), initial="spl-aa-aaa")
CELL_SEGUES.update(SPLITS)

# Round 72: tab bar controllers, as Xcode's tab bar template and the corpus's nextcloud, kickstarter
# and gomap storyboards have them: children by viewControllers relationships, their tab bar items.
def tab_scene(children=("vc1-aa-aaa", "vc2-aa-aaa"), attributes="", bar_extra=""):
    segues = "".join(f'                        <segue destination="{c}" kind="relationship" relationship="viewControllers" id="tb{k}-aa-aaa"/>\n'
                     for k, c in enumerate(children))
    return ('        <scene sceneID="tbs-aa-aaa">\n            <objects>\n'
            f'                <tabBarController id="tab-aa-aaa"{attributes} sceneMemberID="viewController">\n'
            '                    <tabBar key="tabBar" contentMode="scaleToFill" id="tbr-aa-aaa">\n'
            '                        <rect key="frame" x="0.0" y="0.0" width="1000" height="1000"/>\n'
            f'                        <autoresizingMask key="autoresizingMask"/>\n{bar_extra}                    </tabBar>\n'
            f'                    <connections>\n{segues}                    </connections>\n                </tabBarController>\n'
            '                <placeholder placeholderIdentifier="IBFirstResponder" id="tfr-bb-aaa" sceneMemberID="firstResponder"/>\n'
            '            </objects>\n            <point key="canvasLocation" x="-800" y="0"/>\n        </scene>\n')


SQUARE_CIRCLE = ('        <image name="square" catalog="system" width="128" height="114"/>\n'
                 '        <image name="circle" catalog="system" width="128" height="121"/>\n')


def tab_item(number, attributes):
    return f'                    <tabBarItem key="tabBarItem"{attributes} id="tbi-aa-aa{number}"/>\n'


TABS = {
    "sb-tab-plain": storyboard(tab_scene(), controller_scene(1), controller_scene(2), initial="tab-aa-aaa"),
    "sb-tab-items": storyboard(tab_scene(), controller_scene(1, after_view=tab_item(1, ' title="First" image="square" catalog="system"')),
                               controller_scene(2, after_view=tab_item(2, ' title="Second" image="circle" catalog="system"')), initial="tab-aa-aaa", resources=SQUARE_CIRCLE),
    "sb-tab-item-titles": storyboard(tab_scene(), controller_scene(1, after_view=tab_item(1, ' title="First"')),
                                     controller_scene(2, after_view=tab_item(2, ' title="Second"')), initial="tab-aa-aaa"),
    "sb-tab-item-asset": storyboard(tab_scene(), controller_scene(1, after_view=tab_item(1, ' title="First" image="Logo"')), controller_scene(2),
                                    initial="tab-aa-aaa", resources=LOGO),
    "sb-tab-order": storyboard(tab_scene(children=("vc2-aa-aaa", "vc1-aa-aaa")), controller_scene(1), controller_scene(2), initial="tab-aa-aaa"),
    "sb-tab-three": storyboard(tab_scene(children=("vc1-aa-aaa", "vc2-aa-aaa", "vc3-aa-aaa")), controller_scene(1), controller_scene(2), controller_scene(3),
                               initial="tab-aa-aaa"),
    "sb-tab-nav-child": storyboard(tab_scene(children=("nvc-aa-aaa", "vc2-aa-aaa")), navigation_scene("vc1-aa-aaa"), controller_scene(1), controller_scene(2),
                                   initial="tab-aa-aaa"),
    "sb-tab-bar-background": storyboard(tab_scene(bar_extra='                        ' + gray(0, 0) + '\n'), controller_scene(1), controller_scene(2), initial="tab-aa-aaa"),
    "sb-tab-custom": storyboard(tab_scene(attributes=' customClass="MainTabs" customModule="T" customModuleProvider="target"'), controller_scene(1), controller_scene(2),
                                initial="tab-aa-aaa"),
}

# Round 73: tab bar controllers' navigation children as apps have them: the navigation controller's
# own tab bar item, its root's navigation item, two navigation children, a storyboard identifier.
def nav_child(letter, root, item=""):
    return navigation_scene(root, extra=item).replace("nvs-aa-aaa", f"nvs-{letter}-aaa").replace("nvc-aa-aaa", f"nvc-{letter}-aaa").replace(
        "nvb-aa-aaa", f"nvb-{letter}-aaa").replace("nfr-aa-aaa", f"nfr-{letter}-aaa").replace("rel-aa-aaa", f"rel-{letter}-aaa")


TABS.update({
    "sb-tab-nav-item": storyboard(tab_scene(children=("nvc-aa-aaa", "vc2-aa-aaa")), nav_child("aa", "vc1-aa-aaa", tab_item(1, ' title="Home" image="square" catalog="system"')),
                                  controller_scene(1), controller_scene(2), initial="tab-aa-aaa", resources=SQUARE_CIRCLE),
    "sb-tab-nav-root-title": storyboard(tab_scene(children=("nvc-aa-aaa", "vc2-aa-aaa")), nav_child("aa", "vc1-aa-aaa"),
                                        controller_scene(1, after_view=navigation_item("Home")), controller_scene(2), initial="tab-aa-aaa"),
    "sb-tab-nav-two": storyboard(tab_scene(children=("nvc-aa-aaa", "nvc-bb-aaa")), nav_child("aa", "vc1-aa-aaa", tab_item(1, ' title="First"')),
                                 nav_child("bb", "vc2-aa-aaa", tab_item(2, ' title="Second"')), controller_scene(1, after_view=navigation_item("One")),
                                 controller_scene(2, after_view=navigation_item("Two").replace("nvi-aa-aaa", "nvi-aa-aa2")), initial="tab-aa-aaa"),
    "sb-tab-nav-large": storyboard(tab_scene(children=("nvc-aa-aaa", "vc2-aa-aaa")),
                                   nav_child("aa", "vc1-aa-aaa").replace('contentMode="scaleToFill" id="nvb', 'contentMode="scaleToFill" largeTitles="YES" id="nvb'),
                                   controller_scene(1), controller_scene(2), initial="tab-aa-aaa"),
    "sb-tab-plain-then-nav": storyboard(tab_scene(children=("vc2-aa-aaa", "nvc-aa-aaa")), nav_child("aa", "vc1-aa-aaa"), controller_scene(1),
                                        controller_scene(2), initial="tab-aa-aaa"),
    "sb-tab-identifier": storyboard(tab_scene(attributes=' storyboardIdentifier="Tabs"'), controller_scene(1), controller_scene(2), initial="tab-aa-aaa"),
    "sb-tab-child-title": storyboard(tab_scene(), controller_scene(1, attributes=' title="One"'), controller_scene(2), initial="tab-aa-aaa"),
})
CELL_SEGUES.update(TABS)

# Round 74: split view controllers as uncloudnotes has them, a localized title, navigation masters
# and details.
SPLITS2 = {
    "sb-split-title-lproj": SPLITS["sb-split-title"],
    "sb-split-nav-both": storyboard(split_scene(master="nvc-aa-aaa", detail="nvc-bb-aaa"), nav_child("aa", "vc1-aa-aaa"), nav_child("bb", "vc2-aa-aaa"),
                                    controller_scene(1, after_view=navigation_item("Notes")),
                                    controller_scene(2, after_view=navigation_item("Detail").replace("nvi-aa-aaa", "nvi-aa-aa2")), initial="spl-aa-aaa"),
    "sb-split-nav-detail": storyboard(split_scene(detail="nvc-aa-aaa"), nav_child("aa", "vc2-aa-aaa"), controller_scene(1), controller_scene(2),
                                      initial="spl-aa-aaa"),
    "sb-split-custom": storyboard(split_scene(attributes=' customClass="Splits" customModule="T" customModuleProvider="target"'), controller_scene(1),
                                  controller_scene(2), initial="spl-aa-aaa"),
    "sb-split-identifier": storyboard(split_scene(attributes=' storyboardIdentifier="Root"'), controller_scene(1), controller_scene(2), initial="spl-aa-aaa"),
    "sb-split-identifier-title": storyboard(split_scene(attributes=' title="Notes" storyboardIdentifier="Root"'), controller_scene(1), controller_scene(2),
                                            initial="spl-aa-aaa"),
}
LPROJ_STORYBOARDS.add("sb-split-title-lproj")
CELL_SEGUES.update(SPLITS2)

# Round 76: showDetail segues, as uncloudnotes' split storyboards have them: from cells and from a
# controller, a table view controller root of a split view controller's navigation master, its
# cell's showDetail segue to the split view controller's detail; container children's segues.
def proto_with_segue(kind, identifier=None, destination="vc2-aa-aaa"):
    return prototypes(with_cell_connections(tvc_cell(1), cell_segue(kind, identifier).replace("vc2-aa-aaa", destination)))


SEGUES3 = {
    "sb-cellseg-prototype-showDetail": storyboard(tvc_scene(proto_with_segue("showDetail")), controller_scene(2), initial="tvc-aa-aaa"),
    "sb-cellseg-prototype-showDetail-named": storyboard(tvc_scene(proto_with_segue("showDetail", "showDetail")), controller_scene(2), initial="tvc-aa-aaa"),
    "sb-segue-showDetail": storyboard(controller_scene(1, connections='                        <segue destination="vc2-aa-aaa" kind="showDetail" identifier="Open" id="sdg-aa-aaa"/>\n'),
                                      controller_scene(2), initial="vc1-aa-aaa"),
    "sb-split-tvc-master": storyboard(split_scene(master="nvc-aa-aaa"), nav_child("aa", "tvc-aa-aaa"), tvc_scene(prototypes(tvc_cell(1)), after_view=navigation_item("Notes")),
                                      controller_scene(2), initial="spl-aa-aaa"),
    "sb-split-showdetail": storyboard(split_scene(master="nvc-aa-aaa"), nav_child("aa", "tvc-aa-aaa"),
                                      tvc_scene(proto_with_segue("showDetail", "showDetail"), after_view=navigation_item("Notes")), controller_scene(2), initial="spl-aa-aaa"),
    "sb-split-showdetail-nav": storyboard(split_scene(master="nvc-aa-aaa", detail="nvc-bb-aaa"), nav_child("aa", "tvc-aa-aaa"), nav_child("bb", "vc2-aa-aaa"),
                                          tvc_scene(proto_with_segue("showDetail", "showDetail", "nvc-bb-aaa"), after_view=navigation_item("Notes")),
                                          controller_scene(2, after_view=navigation_item("Detail").replace("nvi-aa-aaa", "nvi-aa-aa2")), initial="spl-aa-aaa"),
    "sb-tab-child-show": storyboard(tab_scene(), controller_scene(1, connections='                        <segue destination="vc3-aa-aaa" kind="show" identifier="Open" id="tsh-aa-aaa"/>\n'),
                                    controller_scene(2), controller_scene(3), initial="tab-aa-aaa"),
    "sb-tab-nav-root-show": storyboard(tab_scene(children=("nvc-aa-aaa", "vc2-aa-aaa")), nav_child("aa", "vc1-aa-aaa"),
                                       controller_scene(1, connections='                        <segue destination="vc3-aa-aaa" kind="show" identifier="Open" id="tsh-aa-aaa"/>\n'),
                                       controller_scene(2), controller_scene(3), initial="tab-aa-aaa"),
    "sb-tab-two-show": storyboard(tab_scene(), controller_scene(1, connections='                        <segue destination="vc3-aa-aaa" kind="show" identifier="Open" id="tsh-aa-aaa"/>\n'),
                                  controller_scene(2, connections='                        <segue destination="vc3-aa-aaa" kind="show" identifier="Two" id="tsh-aa-aa2"/>\n'),
                                  controller_scene(3), initial="tab-aa-aaa"),
    "sb-tab-child-show-item": storyboard(tab_scene(), controller_scene(1, after_view=tab_item(1, ' title="First"'),
                                                       connections='                        <segue destination="vc3-aa-aaa" kind="show" identifier="Open" id="tsh-aa-aaa"/>\n'),
                                         controller_scene(2), controller_scene(3), initial="tab-aa-aaa"),
}
CELL_SEGUES.update(SEGUES3)

# Round 77: segues controls trigger, unwind segues to a scene's exit, popover presentations, as the
# corpus's uncloudnotes, kickstarter and wikipedia storyboards have them; a navigation root with
# its own storyboard identifier.
def segue_button(segue, number=1):
    return ('                        <subviews>\n'
            f'                            <button opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" '
            f'buttonType="system" lineBreakMode="middleTruncation" id="btn-aa-aa{number}">\n'
            '                                <rect key="frame" x="20" y="100" width="120" height="44"/>\n'
            '                                <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>\n'
            '                                <state key="normal" title="Go"/>\n'
            f'                                <connections>\n                                    {segue}\n                                </connections>\n'
            '                            </button>\n                        </subviews>\n')


def exit_scene(number, view_extra="", after_view="", exit_id="ext-aa-aaa"):
    return controller_scene(number, view_extra=view_extra, after_view=after_view).replace(
        f'                <placeholder placeholderIdentifier="IBFirstResponder" id="fr{number}-aa-aaa" sceneMemberID="firstResponder"/>\n',
        f'                <placeholder placeholderIdentifier="IBFirstResponder" id="fr{number}-aa-aaa" sceneMemberID="firstResponder"/>\n'
        f'                <exit id="{exit_id}" userLabel="Exit" sceneMemberID="exit"/>\n')


UNWIND = '<segue destination="ext-aa-aaa" kind="unwind" unwindAction="back:" id="uws-aa-aaa"/>'
ARROWS = '                            <popoverArrowDirection key="popoverArrowDirection" up="YES" down="YES" left="YES" right="YES"/>\n'
POPOVER_BAR = navigation_item("Notes", '                        <barButtonItem key="rightBarButtonItem" systemItem="add" id="bbi-aa-aa1">\n'
                              '                            <connections>\n'
                              '                                <segue destination="vc2-aa-aaa" kind="popoverPresentation" identifier="create" popoverAnchorBarButtonItem="bbi-aa-aa1" id="pop-aa-aaa">\n'
                              '    ' + ARROWS + '                                </segue>\n'
                              '                            </connections>\n                        </barButtonItem>\n')
SEGUES4 = {
    "sb-button-show": storyboard(controller_scene(1, view_extra=segue_button('<segue destination="vc2-aa-aaa" kind="show" id="bsg-aa-aaa"/>')),
                                 controller_scene(2), initial="vc1-aa-aaa"),
    "sb-button-show-named": storyboard(controller_scene(1, view_extra=segue_button('<segue destination="vc2-aa-aaa" kind="show" identifier="Go" id="bsg-aa-aaa"/>')),
                                       controller_scene(2), initial="vc1-aa-aaa"),
    "sb-button-present": storyboard(controller_scene(1, view_extra=segue_button('<segue destination="vc2-aa-aaa" kind="presentation" id="bsg-aa-aaa"/>')),
                                    controller_scene(2), initial="vc1-aa-aaa"),
    "sb-segue-show-unnamed-controller": storyboard(controller_scene(1, connections='                        <segue destination="vc2-aa-aaa" kind="show" id="csg-aa-aa9"/>\n'),
                                                   controller_scene(2), initial="vc1-aa-aaa"),
    "sb-unwind-button": storyboard(controller_scene(1, connections='                        <segue destination="vc2-aa-aaa" kind="presentation" identifier="Open" id="osg-aa-aaa"/>\n'),
                                   exit_scene(2, view_extra=segue_button(UNWIND)), initial="vc1-aa-aaa"),
    "sb-unwind-button-named": storyboard(controller_scene(1, connections='                        <segue destination="vc2-aa-aaa" kind="presentation" identifier="Open" id="osg-aa-aaa"/>\n'),
                                         exit_scene(2, view_extra=segue_button(UNWIND.replace('unwindAction', 'identifier="unwindBack" unwindAction'))), initial="vc1-aa-aaa"),
    "sb-unwind-controller": storyboard(controller_scene(1, connections='                        <segue destination="vc2-aa-aaa" kind="presentation" identifier="Open" id="osg-aa-aaa"/>\n'),
                                       exit_scene(2, after_view='                    <connections>\n                        '
                                                  + UNWIND.replace('unwindAction', 'identifier="unwindBack" unwindAction') + '\n                    </connections>\n'),
                                       initial="vc1-aa-aaa"),
    "sb-unwind-bar-item": storyboard(controller_scene(1, connections='                        <segue destination="nvc-aa-aaa" kind="presentation" identifier="Open" id="osg-aa-aaa"/>\n'),
                                     navigation_scene("vc2-aa-aaa"),
                                     exit_scene(2, after_view=navigation_item("Create", '                        <barButtonItem key="leftBarButtonItem" title="Cancel" id="bbi-aa-aa2">\n'
                                                                          '                            <connections>\n                                '
                                                                          + UNWIND.replace('unwindAction', 'identifier="unwindBack" unwindAction')
                                                                          + '\n                            </connections>\n                        </barButtonItem>\n')),
                                     initial="vc1-aa-aaa"),
    "sb-popover-bar-item": storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, after_view=POPOVER_BAR), controller_scene(2), initial="nvc-aa-aaa"),
    "sb-popover-button": storyboard(controller_scene(1, view_extra=segue_button(
        '<segue destination="vc2-aa-aaa" kind="popoverPresentation" identifier="pick" popoverAnchorView="btn-aa-aa1" id="pop-aa-aaa">\n'
        + ARROWS.replace('                            ', '                                        ') + '                                    </segue>')),
        controller_scene(2), initial="vc1-aa-aaa"),
    "sb-popover-arrow-up": storyboard(controller_scene(1, view_extra=segue_button(
        '<segue destination="vc2-aa-aaa" kind="popoverPresentation" identifier="pick" popoverAnchorView="btn-aa-aa1" id="pop-aa-aaa">\n'
        '                                        <popoverArrowDirection key="popoverArrowDirection" up="YES"/>\n                                    </segue>')),
        controller_scene(2), initial="vc1-aa-aaa"),
    "sb-nav-root-identifier": storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, attributes=' storyboardIdentifier="Root"', after_view=navigation_item("Root")),
                                         initial="nvc-aa-aaa"),
}
TWO_BUTTONS = segue_button('<segue destination="vc2-aa-aaa" kind="show" identifier="A" id="Qx4-pp-k2L"/>').replace("                        </subviews>\n", "") + segue_button(
    '<segue destination="vc2-aa-aaa" kind="presentation" identifier="B" id="a1B-zz-9Yt"/>', 2).replace("                        <subviews>\n", "").replace(
    'x="20" y="100"', 'x="20" y="200"')
SEGUES4.update({
    "sb-button-two": storyboard(controller_scene(1, view_extra=TWO_BUTTONS), controller_scene(2), initial="vc1-aa-aaa"),
    "sb-button-outlet": storyboard(controller_scene(1, view_extra=segue_button('<segue destination="vc2-aa-aaa" kind="show" id="bsg-aa-aaa"/>'),
                                                    connections='                        <outlet property="go" destination="btn-aa-aa1" id="out-aa-aaa"/>\n'),
                                   controller_scene(2), initial="vc1-aa-aaa"),
    "sb-button-action": storyboard(controller_scene(1, view_extra=segue_button('<segue destination="vc2-aa-aaa" kind="show" id="bsg-aa-aaa"/>\n'
                                                                               '                                    <action selector="tapped:" destination="vc1-aa-aaa" eventType="touchUpInside" id="act-aa-aaa"/>')),
                                   controller_scene(2), initial="vc1-aa-aaa"),
    "sb-button-and-controller": storyboard(controller_scene(1, view_extra=segue_button('<segue destination="vc2-aa-aaa" kind="show" identifier="A" id="bsg-aa-aaa"/>'),
                                                            connections='                        <segue destination="vc2-aa-aaa" kind="presentation" identifier="P" id="csg-aa-aaa"/>\n'),
                                           controller_scene(2), initial="vc1-aa-aaa"),
    "sb-bar-items-two": storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, after_view=navigation_item("Notes",
        '                        <barButtonItem key="leftBarButtonItem" title="Back" id="bbi-aa-aa2">\n                            <connections>\n'
        '                                <action selector="cancel:" destination="vc1-aa-aaa" id="act-aa-aa2"/>\n                            </connections>\n                        </barButtonItem>\n'
        + POPOVER_BAR.split("\n", 1)[1].rsplit("                    </navigationItem>", 1)[0])), controller_scene(2), initial="nvc-aa-aaa"),
    "sb-button-two-swapped-ids": storyboard(controller_scene(1, view_extra=TWO_BUTTONS.replace("Qx4-pp-k2L", "z9Z-aa-1Ab").replace("a1B-zz-9Yt", "M0n-ee-T7c")),
                                            controller_scene(2), initial="vc1-aa-aaa"),
    "sb-button-two-swapped-buttons": storyboard(controller_scene(1, view_extra=TWO_BUTTONS.replace("btn-aa-aa1", "btn-zz-zz9").replace("btn-aa-aa2", "btn-aa-aa1")),
                                                controller_scene(2), initial="vc1-aa-aaa"),
    "sb-button-action-first": storyboard(controller_scene(1, view_extra=segue_button(
        '<action selector="tapped:" destination="vc1-aa-aaa" eventType="touchUpInside" id="act-aa-aaa"/>\n'
        '                                    <segue destination="vc2-aa-aaa" kind="show" id="bsg-aa-aaa"/>')), controller_scene(2), initial="vc1-aa-aaa"),
    "sb-bar-segue-then-action": storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, after_view=navigation_item("Notes",
        '                        <barButtonItem key="leftBarButtonItem" systemItem="done" id="bbi-aa-aa2">\n                            <connections>\n'
        '                                <segue destination="vc2-aa-aaa" kind="show" identifier="Next" id="bsg-aa-aa2"/>\n                            </connections>\n'
        '                        </barButtonItem>\n                        <barButtonItem key="rightBarButtonItem" systemItem="add" id="bbi-aa-aa1">\n'
        '                            <connections>\n                                <action selector="abc:" destination="vc1-aa-aaa" id="act-aa-aa1"/>\n'
        '                            </connections>\n                        </barButtonItem>\n')), controller_scene(2), initial="nvc-aa-aaa"),
    "sb-bar-popover-and-cell": storyboard(navigation_scene("tvc-aa-aaa"), tvc_scene(proto_with_segue("showDetail", "showDetail"), after_view=POPOVER_BAR),
                                          controller_scene(2), initial="nvc-aa-aaa"),
    "sb-bar-title-lproj": storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, after_view=navigation_item("Notes",
        '                        <barButtonItem key="leftBarButtonItem" title="Cancel" id="bbi-aa-aa2">\n                            <connections>\n'
        '                                <action selector="cancel:" destination="vc1-aa-aaa" id="act-aa-aa2"/>\n                            </connections>\n'
        '                        </barButtonItem>\n')), initial="nvc-aa-aaa"),
})
SEGUES4["sb-bar-segue-then-zzz"] = SEGUES4["sb-bar-segue-then-action"].replace('selector="abc:"', 'selector="zzz:"')
LPROJ_STORYBOARDS.add("sb-bar-title-lproj")
CELL_SEGUES.update(SEGUES4)

# Round 78: navigation controllers with identifiers and a toolbar, as react-native-image-crop-picker's
# QBImagePicker storyboard has them; bar button items of a controller outside a navigation
# controller, as uncloudnotes' CreateNoteViewController has them.
NAV_TOOLBAR = ('                    <toolbar key="toolbar" opaque="NO" clearsContextBeforeDrawing="NO" contentMode="scaleToFill" id="tbr-aa-aaa">\n'
               '                        <autoresizingMask key="autoresizingMask"/>\n                    </toolbar>\n')
STANDALONE_ITEMS = navigation_item("Create",
    '                        <barButtonItem key="leftBarButtonItem" title="Cancel" id="bbi-aa-aa2">\n                            <connections>\n'
    '                                <segue destination="ext-aa-aaa" kind="unwind" identifier="unwindBack" unwindAction="back:" id="uws-aa-aaa"/>\n'
    '                            </connections>\n                        </barButtonItem>\n'
    '                        <barButtonItem key="rightBarButtonItem" title="Create" id="bbi-aa-aa1">\n                            <connections>\n'
    '                                <action selector="save" destination="vc2-aa-aaa" id="act-aa-aa1"/>\n                            </connections>\n'
    '                        </barButtonItem>\n')
SEGUES5 = {
    "sb-nav-identifier": storyboard(navigation_scene("vc1-aa-aaa", ' storyboardIdentifier="Nav"'), controller_scene(1, after_view=navigation_item("Root")),
                                    initial="nvc-aa-aaa"),
    "sb-nav-identifier-not-initial": storyboard(controller_scene(2), navigation_scene("vc1-aa-aaa", ' storyboardIdentifier="Nav"'),
                                                controller_scene(1, after_view=navigation_item("Root")), initial="vc2-aa-aaa"),
    "sb-nav-toolbar": storyboard(navigation_scene("vc1-aa-aaa", extra="                    <toolbarItems/>\n").replace(
        "                    <connections>\n                        <segue destination=\"vc1-aa-aaa\" kind=\"relationship\"",
        NAV_TOOLBAR + "                    <connections>\n                        <segue destination=\"vc1-aa-aaa\" kind=\"relationship\""),
        controller_scene(1, after_view=navigation_item("Root")), initial="nvc-aa-aaa"),
    "sb-standalone-bar-items": storyboard(controller_scene(1), exit_scene(2, after_view=STANDALONE_ITEMS).replace(
        'id="vc2-aa-aaa"', 'storyboardIdentifier="Create" id="vc2-aa-aaa"'), initial="vc1-aa-aaa"),
    "sb-standalone-bar-system": storyboard(controller_scene(1, after_view=navigation_item("Notes",
        '                        <barButtonItem key="rightBarButtonItem" systemItem="add" id="bbi-aa-aa1">\n                            <connections>\n'
        '                                <action selector="add:" destination="vc1-aa-aaa" id="act-aa-aa1"/>\n                            </connections>\n'
        '                        </barButtonItem>\n')), initial="vc1-aa-aaa"),
}
CELL_SEGUES.update(SEGUES5)

# Round 79: Xcode's Master-Detail template, as uncloudnotes' CampgroundManager has it: navigation
# roots with titles, the master table view controller keeping its selection.
TEMPLATE_MASTER = tvc_scene(proto_with_segue("showDetail", "showDetail", "nvc-bb-aaa"), after_view=navigation_item("Camp Sites"),
                            attributes=' title="Master" clearsSelectionOnViewWillAppear="NO"')
SEGUES6 = {
    "sb-split-template": storyboard(split_scene(master="nvc-aa-aaa", detail="nvc-bb-aaa"), nav_child("aa", "tvc-aa-aaa"), nav_child("bb", "vc2-aa-aaa"),
                                    TEMPLATE_MASTER, controller_scene(2, attributes=' title="Detail"',
                                                                      after_view=navigation_item("Detail").replace("nvi-aa-aaa", "nvi-aa-aa2")),
                                    initial="spl-aa-aaa"),
    "sb-nav-root-title": storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, attributes=' title="Detail"', after_view=navigation_item("Detail")),
                                    initial="nvc-aa-aaa"),
    "sb-nav-root-tvc-keeps-selection": storyboard(navigation_scene("tvc-aa-aaa"), tvc_scene(prototypes(tvc_cell(1)), after_view=navigation_item("List"),
                                                                                           attributes=' clearsSelectionOnViewWillAppear="NO"'),
                                                  initial="nvc-aa-aaa"),
}
SEGUES6["sb-split-template-lproj"] = SEGUES6["sb-split-template"]
SEGUES6["sb-nav-root-toolbar-items"] = storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, attributes=' title="Detail"', after_view="                    <toolbarItems/>\n"
                                                                                                    + navigation_item("Detail")), initial="nvc-aa-aaa")
SEGUES6["sb-vc-toolbar-items"] = storyboard(controller_scene(1, after_view="                    <toolbarItems/>\n"), initial="vc1-aa-aaa")
SEGUES6["sb-split-detail-outlet"] = storyboard(split_scene(master="vc1-aa-aaa", detail="nvc-bb-aaa"), controller_scene(1), nav_child("bb", "vc2-aa-aaa"),
                                               controller_scene(2, view_extra=SUBVIEW, after_view=navigation_item("Detail").replace("nvi-aa-aaa", "nvi-aa-aa2"),
                                                                connections='                        <outlet property="box" destination="sub-vi-ew1" id="out-aa-aaa"/>\n'),
                                               initial="spl-aa-aaa")
SEGUES6["sb-tab-child-outlet"] = storyboard(tab_scene(), controller_scene(1, view_extra=SUBVIEW,
                                                                         connections='                        <outlet property="box" destination="sub-vi-ew1" id="out-aa-aaa"/>\n'),
                                            controller_scene(2), initial="tab-aa-aaa")
SEGUES6["sb-tvc-empty-sections"] = storyboard(tvc_scene(prototypes(tvc_cell(1)) + "                        <sections/>\n"), initial="tvc-aa-aaa")
LPROJ_STORYBOARDS.add("sb-split-template-lproj")
CELL_SEGUES.update(SEGUES6)
STORYBOARDS.update(CELL_SEGUES)


# Round 32: what tofu's storyboard uses beyond cells: text fields with input traits, switches, their
# actions, cells of the built-in styles, an image view without an image, table and cell attributes,
# `<mask>` variations, and a symbolic constraint with a constant; one change at a time in xibs.
TEXT_FIELD = ('opaque="NO" clipsSubviews="YES" contentMode="scaleToFill" contentHorizontalAlignment="left" contentVerticalAlignment="center" '
              'placeholder="Name" textAlignment="natural" minimumFontSize="17" translatesAutoresizingMaskIntoConstraints="NO"')


def text_field(attributes=TEXT_FIELD, traits="", connections=""):
    return (f'                <textField {attributes} id="txf-aa-aaa">\n'
            '                    <rect key="frame" x="16" y="100" width="359" height="44"/>\n'
            '                    <fontDescription key="fontDescription" type="system" pointSize="17"/>\n'
            f'                    <textInputTraits key="textInputTraits"{traits}/>\n{connections}'
            '                </textField>\n')


SWITCH = ('opaque="NO" contentMode="scaleToFill" horizontalHuggingPriority="750" verticalHuggingPriority="750" contentHorizontalAlignment="center" '
          'contentVerticalAlignment="center" translatesAutoresizingMaskIntoConstraints="NO"')


def switch(attributes=SWITCH, connections=""):
    return (f'                <switch {attributes} id="swt-aa-aaa">\n                    <rect key="frame" x="302" y="100" width="51" height="31"/>\n'
            f'{connections}                </switch>\n')


def action(selector, event):
    return ('                    <connections>\n'
            f'                        <action selector="{selector}" destination="-1" eventType="{event}" id="act-aa-aaa"/>\n                    </connections>\n')


PIN_FIELD = constraint(0, "txf-aa-aaa", "leading", ROOT, "leading", ' constant="16"') + constraint(1, "txf-aa-aaa", "top", ROOT, "top", ' constant="100"')
PIN_SWITCH = constraint(0, "swt-aa-aaa", "leading", ROOT, "leading", ' constant="302"') + constraint(1, "swt-aa-aaa", "top", ROOT, "top", ' constant="100"')
STYLE_LABEL = ('                    <subviews>\n'
               '                        <label opaque="NO" multipleTouchEnabled="YES" contentMode="left" text="{text}" textAlignment="{alignment}" lineBreakMode="tailTruncation" '
               'baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" id="{id}">\n'
               '                            <rect key="frame" x="{x}" y="{y}" width="{w}" height="{h}"/>\n'
               '                            <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>\n'
               '                            <fontDescription key="fontDescription" type="system" pointSize="{size}"/>\n{color}'
               '                            <nil key="highlightedColor"/>\n                        </label>\n                    </subviews>\n')


def style_label(identifier, text, frame, size=16, alignment="natural", color='                            <nil key="textColor"/>\n'):
    x, y, w, h = frame
    return STYLE_LABEL.format(id=identifier, text=text, x=x, y=y, w=w, h=h, size=size, alignment=alignment, color=color)


def styled_cell(style, labels, label_ids, accessory=""):
    names = ' '.join(f'{key}="{value}"' for key, value in label_ids.items())
    content_subviews = "".join(labels).replace('                    </subviews>\n                    <subviews>\n', '')
    return cell_xib(f'{accessory} {names} style="{style}"', content=content_subviews)


DETAIL_COLOR = '                            <color key="textColor" red="0.55686274509803924" green="0.55686274509803924" blue="0.57647058823529407" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>\n'
MASK_VARIATION = ('            <variation key="default">\n                <mask key="constraints">\n                    <exclude reference="c02-aa-aaa"/>\n'
                  '                </mask>\n            </variation>\n')
TOFU = {
    "tf-template": constrained(text_field(), PIN_FIELD),
    "tf-text": constrained(text_field(TEXT_FIELD.replace('placeholder="Name"', 'text="test@example.com" placeholder="Name"')), PIN_FIELD),
    "tf-no-placeholder": constrained(text_field(TEXT_FIELD.replace(' placeholder="Name"', '')), PIN_FIELD),
    "tf-border-rounded": constrained(text_field(TEXT_FIELD.replace('textAlignment="natural"', 'borderStyle="roundedRect" textAlignment="natural"')), PIN_FIELD),
    "tf-traits-no-correction": constrained(text_field(traits=' autocorrectionType="no" spellCheckingType="no"'), PIN_FIELD),
    "tf-keyboard-alphabet": constrained(text_field(traits=' keyboardType="alphabet"'), PIN_FIELD),
    "tf-keyboard-number-pad": constrained(text_field(traits=' keyboardType="numberPad"'), PIN_FIELD),
    "tf-action": constrained(text_field(connections=action("editingChanged:", "editingChanged")), PIN_FIELD),
    "sw-template": constrained(switch(), PIN_SWITCH),
    "sw-on": constrained(switch(SWITCH + ' on="YES"'), PIN_SWITCH),
    "sw-action": constrained(switch(connections=action("toggled", "valueChanged")), PIN_SWITCH),
    "cell-style-default": styled_cell("IBUITableViewCellStyleDefault", [style_label("tlb-aa-aa1", "Title", (16, 0, 288, 44))], {"textLabel": "tlb-aa-aa1"}),
    "cell-style-value1": styled_cell("IBUITableViewCellStyleValue1", [style_label("tlb-aa-aa1", "Algorithm", (16, 13, 70.5, 19.5)),
                                                                     style_label("dlb-aa-aa1", "SHA1", (265.5, 13, 38.5, 19.5), alignment="right", color=DETAIL_COLOR)],
                                     {"textLabel": "tlb-aa-aa1", "detailTextLabel": "dlb-aa-aa1"}),
    "cell-style-value1-accessory": styled_cell("IBUITableViewCellStyleValue1", [style_label("tlb-aa-aa1", "Algorithm", (16, 13, 70.5, 19.5)),
                                                                               style_label("dlb-aa-aa1", "SHA1", (238.5, 13, 38.5, 19.5), alignment="right", color=DETAIL_COLOR)],
                                               {"textLabel": "tlb-aa-aa1", "detailTextLabel": "dlb-aa-aa1"}, ' accessoryType="disclosureIndicator"'),
    "cell-style-subtitle": styled_cell("IBUITableViewCellStyleSubtitle", [style_label("tlb-aa-aa1", "Title", (16, 5, 33, 20.5), size=17),
                                                                         style_label("dlb-aa-aa1", "Subtitle", (16, 25.5, 44, 14.5), size=12)],
                                       {"textLabel": "tlb-aa-aa1", "detailTextLabel": "dlb-aa-aa1"}),
    "cell-reorder": cell_xib(' showsReorderControl="YES"' + ' customClass="Cell" customModule="T" customModuleProvider="target"'),
    "cell-editing-accessory": cell_xib(' editingAccessoryType="disclosureIndicator" customClass="Cell" customModule="T" customModuleProvider="target"'),
    "table-no-selection": table_xib(TABLE_ATTRIBUTES + ' allowsSelection="NO"'),
    "image-view-no-image": constrained(subview("img-aa-aaa", (16, 10, 64, 64), "imageView", ' userInteractionEnabled="NO" horizontalHuggingPriority="251" verticalHuggingPriority="251"',
                                               constraint(5, None, "height", extra=' constant="64"', indent=24) + constraint(6, None, "width", extra=' constant="64"', indent=24)),
                                       constraint(0, "img-aa-aaa", "leading", ROOT, "leading", ' constant="16"') + constraint(1, "img-aa-aaa", "top", ROOT, "top", ' constant="10"')),
    "mask-exclude-constraint": constrained(subview("sss-ss-ss1"), constraint(0, "sss-ss-ss1", "leading", ROOT, "leading") + constraint(1, "sss-ss-ss1", "top", ROOT, "top")
                                           + constraint(2, "sss-ss-ss1", "leading", ROOT, "leading", ' constant="8"')).replace(
        '            <point key="canvasLocation"', MASK_VARIATION + '            <point key="canvasLocation"'),
    "symbolic-constant": constrained(subview("aaa-aa-aa1") + subview("bbb-bb-bb1", (200, 20, 100, 50)),
                                     constraint(0, "bbb-bb-bb1", "leading", "aaa-aa-aa1", "trailing", ' constant="8" symbolic="YES"')),
    "symbolic-constant-root": constrained(subview("sss-ss-ss1"), constraint(0, "sss-ss-ss1", "leading", ROOT, "leading", ' constant="20" symbolic="YES"')),
}
STORYBOARDS["sb-tvc-defines-presentation"] = storyboard(tvc_scene(attributes=' definesPresentationContext="YES"'), initial="tvc-aa-aaa")
TOFU["cell-all-keys"] = cell_xib(' showsReorderControl="YES" reuseIdentifier="Cell" editingAccessoryType="disclosureIndicator" accessoryType="disclosureIndicator" '
                                 'indentationLevel="1" customClass="Cell" customModule="T" customModuleProvider="target"').replace('selectionStyle="default"', 'selectionStyle="none"')
TOFU["cell-style-value1-reuse"] = styled_cell("IBUITableViewCellStyleValue1", [style_label("tlb-aa-aa1", "Algorithm", (16, 13, 70.5, 19.5)),
                                                                              style_label("dlb-aa-aa1", "SHA1", (265.5, 13, 38.5, 19.5), alignment="right", color=DETAIL_COLOR)],
                                          {"textLabel": "tlb-aa-aa1", "detailTextLabel": "dlb-aa-aa1"}, ' reuseIdentifier="Cell" accessoryType="disclosureIndicator"').replace(
    'selectionStyle="default"', 'selectionStyle="none"')
TOFU["cell-style-reorder-indent"] = styled_cell("IBUITableViewCellStyleValue1", [style_label("tlb-aa-aa1", "Algorithm", (16, 13, 70.5, 19.5)),
                                                                                style_label("dlb-aa-aa1", "SHA1", (265.5, 13, 38.5, 19.5), alignment="right", color=DETAIL_COLOR)],
                                            {"textLabel": "tlb-aa-aa1", "detailTextLabel": "dlb-aa-aa1"}, ' showsReorderControl="YES" indentationLevel="1"')
TOFU["table-selection-flags"] = table_xib(TABLE_ATTRIBUTES + ' allowsSelectionDuringEditing="YES" allowsSelection="NO"')
TOFU["tf-traits-all"] = constrained(text_field(TEXT_FIELD.replace('placeholder="Name"', 'text="x" placeholder="Name"'),
                                               traits=' autocorrectionType="no" spellCheckingType="no" keyboardType="numberPad"'), PIN_FIELD)
STORYBOARDS["sb-tvc-defines-presentation-segue"] = storyboard(tvc_scene(attributes=' definesPresentationContext="YES"', after_view=
    '                    <connections>\n                        <segue destination="vc2-aa-aaa" kind="show" identifier="Next" id="tsg-aa-aaa"/>\n'
    '                    </connections>\n'), controller_scene(2), initial="tvc-aa-aaa")
STORYBOARDS["sb-tvc-in-nav-defines-presentation"] = storyboard(
    navigation_scene("tvc-aa-aaa"), tvc_scene(prototypes(tvc_cell(1)), attributes=' definesPresentationContext="YES"' + TVC_CUSTOM, after_view=navigation_item()
                                              + '                    <connections>\n                        <segue destination="vc2-aa-aaa" kind="show" identifier="Next" id="tsg-aa-aaa"/>\n'
                                              '                    </connections>\n'), controller_scene(2), initial="nvc-aa-aaa")


def actions(*pairs):
    return ('                    <connections>\n' + "".join(
        f'                        <action selector="{selector}" destination="-1" eventType="{event}" id="ac{selector[0]}-{k}a-aaa"/>\n' for k, (selector, event) in enumerate(pairs))
        + '                    </connections>\n')


def field(number, y, connections):
    return text_field(connections=connections).replace("txf-aa-aaa", f"tf{number}-aa-aaa").replace('y="100"', f'y="{y}"')


def pin(identifier, number, x, y):
    return (constraint(2 * number, identifier, "leading", ROOT, "leading", f' constant="{x}"')
            + constraint(2 * number + 1, identifier, "top", ROOT, "top", f' constant="{y}"'))


# The order of actions' event connections: by selector, event mask or source.
TOFU["ev-fields-selectors-reversed"] = constrained(field(1, 100, actions(("zeta:", "editingChanged"))) + field(2, 200, actions(("alpha:", "editingChanged"))),
                                                   pin("tf1-aa-aaa", 0, 16, 100) + pin("tf2-aa-aaa", 1, 16, 200))
TOFU["ev-switch-alpha-field-zeta"] = constrained(switch(connections=actions(("alpha", "valueChanged"))) + field(1, 200, actions(("zeta:", "editingChanged"))),
                                                 PIN_SWITCH + pin("tf1-aa-aaa", 1, 16, 200))
TOFU["ev-field-alpha-switch-zeta"] = constrained(field(1, 200, actions(("alpha:", "editingChanged"))) + switch(connections=actions(("zeta", "valueChanged"))),
                                                 PIN_SWITCH + pin("tf1-aa-aaa", 1, 16, 200))
TOFU["ev-field-two-events"] = constrained(field(1, 200, actions(("alpha:", "editingDidEnd"), ("beta:", "editingChanged"))), pin("tf1-aa-aaa", 0, 16, 200))


def extra_view(number, subview=True):
    inner = ('                    <subviews>\n'
             f'                        <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="xs{number}-aa-aaa">\n'
             '                            <rect key="frame" x="16" y="21" width="208" height="86"/>\n                        </view>\n'
             '                    </subviews>\n                    <constraints>\n'
             f'                        <constraint firstItem="xs{number}-aa-aaa" firstAttribute="leading" secondItem="xv{number}-aa-aaa" secondAttribute="leadingMargin" id="xc{number}-aa-aaa"/>\n'
             f'                        <constraint firstItem="xs{number}-aa-aaa" firstAttribute="centerY" secondItem="xv{number}-aa-aaa" secondAttribute="centerY" id="xd{number}-aa-aaa"/>\n'
             '                    </constraints>\n') if subview else ""
    return (f'                <view contentMode="scaleToFill" id="xv{number}-aa-aaa">\n'
            '                    <rect key="frame" x="0.0" y="0.0" width="240" height="128"/>\n'
            '                    <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>\n'
            f'{inner}                </view>\n')


def with_extra_views(scene_text, *views):
    return scene_text.replace("            </objects>\n", "".join(views) + "            </objects>\n")


def extra_outlet(number, name="emptyView"):
    return f'                        <outlet property="{name}{number}" destination="xv{number}-aa-aaa" id="xo{number}-aa-aaa"/>\n'


# Views beside a scene's controller (tofu's empty views): which nib holds them, how the controller
# keeps them, where its outlets to them go.
EXTRA_VIEWS = {
    "sb-extra-view": storyboard(with_extra_views(controller_scene(1, TVC_CUSTOM.replace("ListController", "VC"), connections=extra_outlet(1)), extra_view(1)),
                                initial="vc1-aa-aaa"),
    "sb-extra-view-no-outlet": storyboard(with_extra_views(controller_scene(1), extra_view(1, subview=False)), initial="vc1-aa-aaa"),
    "sb-extra-view-two": storyboard(with_extra_views(controller_scene(1, TVC_CUSTOM.replace("ListController", "VC"), connections=extra_outlet(2) + extra_outlet(1)),
                                                     extra_view(1), extra_view(2, subview=False)), initial="vc1-aa-aaa"),
    "sb-extra-view-identified-segue": storyboard(with_extra_views(controller_scene(
        1, ' storyboardIdentifier="First" definesPresentationContext="YES"' + TVC_CUSTOM.replace("ListController", "VC"),
        connections=extra_outlet(1) + '                        <segue destination="vc2-aa-aaa" kind="show" identifier="Next" id="sg1-aa-aaa"/>\n'), extra_view(1)),
        controller_scene(2), initial="vc1-aa-aaa"),
    "sb-extra-view-nav-root": storyboard(
        navigation_scene("tvc-aa-aaa"), with_extra_views(tvc_scene(prototypes(tvc_cell(1)), attributes=' definesPresentationContext="YES"' + TVC_CUSTOM,
                                                                   after_view=navigation_item() + '                    <connections>\n' + extra_outlet(1)
                                                                   + '                        <segue destination="vc2-aa-aaa" kind="show" identifier="Next" id="tsg-aa-aaa"/>\n'
                                                                   '                    </connections>\n'), extra_view(1)),
        controller_scene(2), initial="nvc-aa-aaa"),
}
ORDER_VIEW_IDS = ["Qx4-pp-k2L", "a1B-zz-9Yt", "M0n-ee-T7c", "z9Z-aa-1Ab", "hT8-ZY-D3A", "jac-9u-ovS"]
for suffix, controller in [("a", "vc1-aa-aaa"), ("b", "Kd2-Lm-90p")]:
    EXTRA_VIEWS[f"sb-extra-view-order-{suffix}"] = storyboard(with_extra_views(
        controller_scene(1).replace("vc1-aa-aaa", controller),
        *[extra_view(1, subview=False).replace("xv1-aa-aaa", identifier).replace('contentMode="scaleToFill"', f'contentMode="scaleToFill" tag="{k + 1}"')
          for k, identifier in enumerate(ORDER_VIEW_IDS)]), initial=controller)
EXTRA_VIEWS["sb-extra-view-order-tvc"] = storyboard(with_extra_views(
    tvc_scene(prototypes(tvc_cell(1))),
    *[extra_view(1, subview=False).replace("xv1-aa-aaa", identifier).replace('contentMode="scaleToFill"', f'contentMode="scaleToFill" tag="{k + 1}"')
      for k, identifier in enumerate(ORDER_VIEW_IDS)]), initial="tvc-aa-aaa")
EXTRA_VIEWS["sb-extra-view-order-nav-root"] = storyboard(navigation_scene("vc1-aa-aaa"), with_extra_views(
    controller_scene(1, after_view=navigation_item()),
    *[extra_view(1, subview=False).replace("xv1-aa-aaa", identifier).replace('contentMode="scaleToFill"', f'contentMode="scaleToFill" tag="{k + 1}"')
      for k, identifier in enumerate(ORDER_VIEW_IDS)]), initial="nvc-aa-aaa")
EXTRA_VIEWS["sb-extra-view-tvc"] = storyboard(with_extra_views(tvc_scene(prototypes(tvc_cell(1)), attributes=TVC_CUSTOM, after_view=
    '                    <connections>\n' + extra_outlet(1) + '                    </connections>\n'), extra_view(1)), initial="tvc-aa-aaa")
EXTRA_VIEWS["sb-action-other-scene"] = storyboard(controller_scene(1, view_extra='                        <subviews>\n' + text_field(connections=actions(("changed:", "editingChanged")).replace('"-1"', '"vc2-aa-aaa"')).replace(
    "                ", "                            ") + '                        </subviews>\n', connections='                        <segue destination="vc2-aa-aaa" kind="show" identifier="Next" id="sg1-aa-aaa"/>\n'),
    controller_scene(2), initial="vc1-aa-aaa")
# The order the Info.plist's map takes its names in: scenes reached from the entry point by segues
# and identified scenes no segue reaches, written in neither order (ids picked so that
# breadth-first, depth-first and document orders give different hash tables).
GRAPH_IDS = {1: "CsM-eh-GAk", 2: "Wvj-7F-Ac9", 3: "QeW-JK-Y40", 4: "uvS-wM-FLZ", 5: "Ee5-aa-aaa", 6: "Ff6-aa-aaa"}


def graph_scene(number, attributes="", segues=()):
    text = controller_scene(number, attributes, connections="".join(
        f'                        <segue destination="{GRAPH_IDS[to]}" kind="{kind}" identifier="S{number}{to}" id="g{number}{to}-aa-aaa"/>\n' for to, kind in segues))
    return text.replace(f"vc{number}-aa-aaa", GRAPH_IDS[number])


EXTRA_VIEWS["sb-info-order-graph"] = storyboard(
    graph_scene(4), graph_scene(6, ' storyboardIdentifier="Six"'), graph_scene(2, segues=[(4, "show")]), graph_scene(5, ' storyboardIdentifier="Five"'),
    graph_scene(1, segues=[(2, "show"), (3, "show")]), graph_scene(3, segues=[(5, "presentation")]), initial=GRAPH_IDS[1])
STORYBOARDS.update(EXTRA_VIEWS)


# `<mask key="constraints">` variations as tofu's cells have them: a view whose default excludes
# some of its constraints, the view a subview of the root, the root, or in a cell's content view.
def mask_variation(excluded, indent=20):
    pad = " " * indent
    return (f'{pad}<variation key="default">\n{pad}    <mask key="constraints">\n'
            + "".join(f'{pad}        <exclude reference="c{number:02d}-aa-aaa"/>\n' for number in excluded)
            + f'{pad}    </mask>\n{pad}</variation>\n')


MASK_GROUP_CONSTRAINTS = [(10, "sss-aa-aaa", "top", "kkk-aa-aaa", "bottom", ' constant="-4"'), (11, "kkk-aa-aaa", "top", "own-aa-aaa", "top", ' constant="-4"'),
                          (12, "kkk-aa-aaa", "top", "sss-aa-aaa", "bottom", ""), (13, None, "bottom", "sss-aa-aaa", "bottom", ""),
                          (14, "sss-aa-aaa", "leading", "own-aa-aaa", "leading", ' constant="1"'), (15, None, "trailing", "sss-aa-aaa", "trailing", ""),
                          (16, "kkk-aa-aaa", "top", "sss-aa-aaa", "bottom", ""), (17, "kkk-aa-aaa", "leading", "own-aa-aaa", "leading", ""),
                          (18, "sss-aa-aaa", "top", "kkk-aa-aaa", "top", ""), (19, None, "trailing", "kkk-aa-aaa", "trailing", "")]


def mask_group(excluded, frame=(90, 10.5, 259, 63)):
    x, y, w, h = frame
    inner = (subview("kkk-aa-aaa", (0, -4, 259, 53)) + subview("sss-aa-aaa", (1, 45, 258, 18))).replace("                ", "                        ")
    constraints = "".join(constraint(n, a, aa, b, ba, extra, indent=24) for n, a, aa, b, ba, extra in MASK_GROUP_CONSTRAINTS)
    return ('                <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="own-aa-aaa">\n'
            f'                    <rect key="frame" x="{x}" y="{y}" width="{w}" height="{h}"/>\n'
            f'                    <subviews>\n{inner}                    </subviews>\n'
            f'                    <constraints>\n{constraints}                    </constraints>\n{mask_variation(excluded) if excluded else ""}'
            '                </view>\n')


PIN_GROUP = constraint(0, "own-aa-aaa", "leading", ROOT, "leading", ' constant="90"') + constraint(1, "own-aa-aaa", "top", ROOT, "top", ' constant="10.5"')
TOFU["mask-group-none"] = constrained(mask_group([]), PIN_GROUP)
TOFU["mask-group-one"] = constrained(mask_group([12]), PIN_GROUP)
TOFU["mask-group-tofu"] = constrained(mask_group([12, 16, 18]), PIN_GROUP)
TOFU["mask-root-two"] = constrained(subview("sss-ss-ss1"), constraint(0, "sss-ss-ss1", "leading", ROOT, "leading") + constraint(1, "sss-ss-ss1", "top", ROOT, "top")
                                    + constraint(2, "sss-ss-ss1", "leading", ROOT, "leading", ' constant="8"') + constraint(3, "sss-ss-ss1", "top", ROOT, "top", ' constant="8"')
                                    ).replace('            <point key="canvasLocation"', mask_variation([2, 3], 12) + '            <point key="canvasLocation"')
TOFU["mask-root-margin"] = constrained(subview("sss-ss-ss1"), constraint(0, "sss-ss-ss1", "leading", ROOT, "leadingMargin") + constraint(1, "sss-ss-ss1", "top", ROOT, "top")
                                       + constraint(2, "sss-ss-ss1", "leading", ROOT, "leadingMargin", ' constant="8"')
                                       ).replace('            <point key="canvasLocation"', mask_variation([2], 12) + '            <point key="canvasLocation"')
TOFU["mask-cell-group"] = cell_xib(content='                    <subviews>\n' + mask_group([12, 16, 18]).replace("\n                ", "\n                    ").replace("                <view", "                    <view", 1)
                                   + '                    </subviews>\n                    <constraints>\n'
                                   + constraint(0, "own-aa-aaa", "leading", CONTENT, "leading", ' constant="90"', indent=24)
                                   + constraint(1, "own-aa-aaa", "top", CONTENT, "top", ' constant="10.5"', indent=24) + '                    </constraints>\n',
                                   size=(375, 84))
TOFU["mask-cell-content"] = cell_xib(content='                    <subviews>\n' + subview("sss-ss-ss1", (16, 11, 100, 22)).replace("                ", "                    ")
                                     + '                    </subviews>\n                    <constraints>\n'
                                     + constraint(0, "sss-ss-ss1", "leading", CONTENT, "leadingMargin", indent=24) + constraint(1, "sss-ss-ss1", "top", CONTENT, "top", ' constant="11"', indent=24)
                                     + constraint(2, "sss-ss-ss1", "leading", CONTENT, "leadingMargin", ' constant="8"', indent=24) + '                    </constraints>\n'
                                     + mask_variation([2]), size=(375, 44))
# Group order of subviews partly outside their superview, and constraints differing only in their
# constants written in either order.
TOFU["frames-outside-left"] = constrained(subview("aaa-aa-aa1", (-20, 30, 100, 20)) + subview("bbb-bb-bb1", (10, 5, 100, 20)),
                                          pin("aaa-aa-aa1", 0, -20, 30) + pin("bbb-bb-bb1", 1, 10, 5))
TOFU["frames-outside-bottom"] = constrained(subview("aaa-aa-aa1", (0, 840, 100, 30)) + subview("bbb-bb-bb1", (30, 30, 100, 20)),
                                            pin("aaa-aa-aa1", 0, 0, 840) + pin("bbb-bb-bb1", 1, 30, 30))
TOFU["tie-constant-reversed"] = constrained(subview("sss-ss-ss1"), constraint(0, "sss-ss-ss1", "leading", ROOT, "leading", ' constant="8"')
                                            + constraint(1, "sss-ss-ss1", "leading", ROOT, "leading") + constraint(2, "sss-ss-ss1", "top", ROOT, "top")
                                            + constraint(3, "sss-ss-ss1", "top", ROOT, "top", ' constant="-4"'))
EXPERIMENTS.update(TOFU)


# Round 33: control actions as the corpus has them: every event type it uses, an action without
# one, actions of a custom control (a `<view>` of a UIControl subclass), to a view and to a cell,
# and in a storyboard scene to the controller.
EVENTS = [("began:", "editingDidBegin"), ("exit:", "editingDidEndOnExit"), ("primary:", "primaryActionTriggered"), ("touched:", "touchUpInside"),
          ("value:", "valueChanged"), ("ended:", "editingDidEnd"), ("changed:", "editingChanged")]
DIAL = ' customClass="Dial" customModule="T" customModuleProvider="target"'


def control_view(identifier="ctl-aa-aaa", connections=""):
    return (f'                <view contentMode="scaleToFill"{DIAL} translatesAutoresizingMaskIntoConstraints="NO" id="{identifier}">\n'
            f'                    <rect key="frame" x="10" y="20" width="100" height="50"/>\n{connections}                </view>\n')


def to(connections, destination):
    return connections.replace('destination="-1"', f'destination="{destination}"')


ACTIONS = {
    "act-field-all-events": constrained(field(1, 100, actions(*EVENTS)), pin("tf1-aa-aaa", 0, 16, 100)),
    "act-field-no-event": constrained(field(1, 100, actions(("changed:", "editingChanged")).replace(' eventType="editingChanged"', '')), pin("tf1-aa-aaa", 0, 16, 100)),
    "act-control-touch": constrained(control_view(connections=actions(("tapped:", "touchUpInside"))), pin("ctl-aa-aaa", 0, 10, 20)),
    "act-control-value": constrained(control_view(connections=actions(("moved:", "valueChanged"))), pin("ctl-aa-aaa", 0, 10, 20)),
    "act-control-no-event": constrained(control_view(connections=actions(("tapped:", "touchUpInside")).replace(' eventType="touchUpInside"', '')), pin("ctl-aa-aaa", 0, 10, 20)),
    "act-to-root-view": constrained(field(1, 100, to(actions(("changed:", "editingChanged")), ROOT)), pin("tf1-aa-aaa", 0, 16, 100)),
    "act-to-subview": constrained(control_view() + field(1, 100, to(actions(("changed:", "editingChanged")), "ctl-aa-aaa")),
                                  pin("ctl-aa-aaa", 0, 10, 20) + pin("tf1-aa-aaa", 1, 16, 100)),
    "act-with-outlets": constrained(field(1, 100, actions(("changed:", "editingChanged"))) + field(2, 200, actions(("alpha:", "editingChanged"))),
                                    pin("tf1-aa-aaa", 0, 16, 100) + pin("tf2-aa-aaa", 1, 16, 200)).replace(
        '<placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File\'s Owner"/>',
        '<placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File\'s Owner">\n            <connections>\n'
        '                <outlet property="zeta" destination="tf1-aa-aaa" id="ou1-aa-aaa"/>\n                <outlet property="beta" destination="tf2-aa-aaa" id="ou2-aa-aaa"/>\n'
        '            </connections>\n        </placeholder>'),
    "act-to-cell": cell_xib(content='                    <subviews>\n' + field(1, 0, to(actions(("changed:", "editingChanged")), CELL)).replace("                ", "                    ")
                            + '                    </subviews>\n                    <constraints>\n'
                            + constraint(0, "tf1-aa-aaa", "leading", CONTENT, "leading", ' constant="16"', indent=24)
                            + constraint(1, "tf1-aa-aaa", "top", CONTENT, "top", indent=24) + '                    </constraints>\n', size=(375, 44)),
}
ACTIONS["act-field-mixed-no-event"] = constrained(field(1, 100, actions(("zeta:", "none"), ("alpha:", "editingChanged"), ("mid:", "touchUpInside"), ("beta:", "none")).replace(
    ' eventType="none"', '')), pin("tf1-aa-aaa", 0, 16, 100))
EXPERIMENTS.update(ACTIONS)


def with_actions(name, tag, *pairs):
    """An experiment of round 34 or later with actions on its first `tag`."""
    text = EXPERIMENTS[name]
    end = text.index(f"</{tag}>")
    block = "".join(f'                        <action selector="{selector}" destination="-1"' + (f' eventType="{event}"' if event else "")
                    + f' id="ab{k}-aa-aaa"/>\n' for k, (selector, event) in enumerate(pairs))
    return text[:end] + "    <connections>\n" + block + "                    </connections>\n                " + text[end:]


ACTIONS_MORE = {
    "act-button-touch": with_actions("button-no-title", "button", ("tapped:", "touchUpInside")),
    "act-button-no-event": with_actions("button-no-title", "button", ("tapped:", None)),
    "act-button-primary": with_actions("button-no-title", "button", ("primary:", "primaryActionTriggered"), ("tapped:", "touchUpInside")),
    "act-segmented-value": with_actions("segmented", "segmentedControl", ("picked:", "valueChanged")),
    "act-slider-value": with_actions("slider", "slider", ("slid:", "valueChanged")),
    "act-page-value": with_actions("page", "pageControl", ("paged:", "valueChanged")),
}
EXPERIMENTS.update(ACTIONS_MORE)
STORYBOARDS["sb-act-controller"] = storyboard(controller_scene(1, TVC_CUSTOM.replace("ListController", "VC"), view_extra='                        <subviews>\n' + (
    field(1, 100, to(actions(("changed:", "editingChanged")), "vc1-aa-aaa")) + control_view(connections=to(actions(("tapped:", "touchUpInside")), "vc1-aa-aaa"))).replace(
    "                ", "                            ") + '                        </subviews>\n',
    connections='                        <outlet property="field" destination="tf1-aa-aaa" id="ou1-aa-aaa"/>\n'), initial="vc1-aa-aaa")



# Round 34: what corpus cells add (pocket-casts', wikipedia's): their userLabel, an ambiguous content
# view, the cell's and the content view's layout margins, plain and directional, a margin
# constraint inside custom margins, and separator insets.
CELL_LABEL_SUBVIEW = ('                    <subviews>\n' + subview("sss-ss-ss1", (24, 11, 100, 22)).replace("                ", "                        ")
                      + '                    </subviews>\n')
CELL_MARGIN_CONSTRAINTS = ('                    <constraints>\n'
                           + constraint(0, "sss-ss-ss1", "leading", CONTENT, "leadingMargin", indent=24)
                           + constraint(1, "sss-ss-ss1", "top", CONTENT, "topMargin", indent=24) + '                    </constraints>\n')
CONTENT_MARGINS = '                    <edgeInsets key="layoutMargins" top="16" left="16" bottom="16" right="16"/>\n'
CONTENT_DIRECTIONAL = '                    <directionalEdgeInsets key="directionalLayoutMargins" top="8" leading="32" bottom="8" trailing="32"/>\n'
CELL_DIRECTIONAL = '            <directionalEdgeInsets key="directionalLayoutMargins" top="8" leading="24" bottom="8" trailing="24"/>\n'
CELL_ROUND = {
    "cell-user-label": cell_xib(' userLabel="Row" customClass="Cell" customModule="T" customModuleProvider="target"'),
    "cell-content-ambiguous": cell_xib(content_attributes=' ambiguous="YES"'),
    "cell-content-margins": cell_xib(content=CONTENT_MARGINS),
    "cell-content-margins-constraint": cell_xib(content=CELL_LABEL_SUBVIEW + CELL_MARGIN_CONSTRAINTS + CONTENT_MARGINS, size=(320, 60)),
    "cell-content-directional": cell_xib(content=CONTENT_DIRECTIONAL),
    "cell-content-directional-constraint": cell_xib(content=CELL_LABEL_SUBVIEW + CELL_MARGIN_CONSTRAINTS + CONTENT_DIRECTIONAL, size=(320, 60)),
    "cell-directional": cell_xib(cell_extra=CELL_DIRECTIONAL),
    "cell-directional-both": cell_xib(content=CONTENT_DIRECTIONAL, cell_extra=CELL_DIRECTIONAL),
    "cell-separator-inset-15": cell_xib(cell_extra='            <inset key="separatorInset" minX="15" minY="0.0" maxX="0.0" maxY="0.0"/>\n'),
    "cell-separator-inset-60": cell_xib(cell_extra='            <inset key="separatorInset" minX="60" minY="0.0" maxX="0.0" maxY="0.0"/>\n'),
    "cell-separator-inset-both": cell_xib(cell_extra='            <inset key="separatorInset" minX="20" minY="0.0" maxX="30" maxY="0.0"/>\n'),
}
for height in ["44.25", "44.5", "44.75", "44.1"]:
    CELL_ROUND[f"cell-selection-none-height-{height}"] = cell_xib(size=(320, height)).replace('selectionStyle="default"', 'selectionStyle="none"')
EXPERIMENTS.update(CELL_ROUND)


# Round 35: constraints of one item and attribute to different second items (the corpus's cwa,
# kickstarter): which of document order, the second items' frames, their subview order or ids
# orders them.
def tie_document(frames, subview_order, constraint_order, ids=("aaa-aa-aa1", "bbb-bb-bb1"), extra=' relation="greaterThanOrEqual" constant="12"'):
    views = {"A": subview(ids[0], frames["A"]), "B": subview(ids[1], frames["B"]), "X": subview("xxx-xx-xx1", (0, 300, 100, 50))}
    pins = pin(ids[0], 0, int(frames["A"][0]), int(frames["A"][1])) + pin(ids[1], 1, int(frames["B"][0]), int(frames["B"][1])) + pin("xxx-xx-xx1", 2, 0, 300)
    ties = {"A": constraint(10, "xxx-xx-xx1", "top", ids[0], "bottom", extra), "B": constraint(11, "xxx-xx-xx1", "top", ids[1], "bottom", extra)}
    return constrained("".join(views[k] for k in subview_order + "X"), pins + "".join(ties[k] for k in constraint_order))


NEAR, FAR = (0, 0, 100, 50), (0, 100, 100, 50)
TIES = {
    "tie-second-items": tie_document({"A": NEAR, "B": FAR}, "AB", "AB"),
    "tie-second-items-constraints-reversed": tie_document({"A": NEAR, "B": FAR}, "AB", "BA"),
    "tie-second-items-frames-reversed": tie_document({"A": FAR, "B": NEAR}, "AB", "AB"),
    "tie-second-items-subviews-reversed": tie_document({"A": NEAR, "B": FAR}, "BA", "AB"),
    "tie-second-items-ids-reversed": tie_document({"A": NEAR, "B": FAR}, "AB", "AB", ids=("bbb-bb-bb1", "aaa-aa-aa1")),
    "tie-second-items-constants": tie_document({"A": NEAR, "B": FAR}, "AB", "AB", extra="").replace(
        'secondAttribute="bottom" id="c11', 'secondAttribute="bottom" constant="6" id="c11'),
    "tie-second-items-constants-reversed": tie_document({"A": NEAR, "B": FAR}, "AB", "BA", extra="").replace(
        'secondAttribute="bottom" id="c11', 'secondAttribute="bottom" constant="6" id="c11'),
    "tie-identical-normalized": constrained(subview("sss-ss-ss1"), constraint(0, "sss-ss-ss1", "leading", ROOT, "leading") + constraint(1, "sss-ss-ss1", "top", ROOT, "top")
                                            + constraint(2, None, "trailing", "sss-ss-ss1", "trailing", ' constant="5"') + constraint(3, None, "trailing", "sss-ss-ss1", "trailing", ' constant="5"')),
}
TIES["tie-second-items-near-constant"] = tie_document({"A": NEAR, "B": FAR}, "AB", "AB", extra="").replace(
    'secondAttribute="bottom" id="c10', 'secondAttribute="bottom" constant="6" id="c10')
EXPERIMENTS.update(TIES)



# Round 36: navigation shapes the corpus has (wikipedia's, uncloudnotes'): simulated navigation-bar
# metrics, items without a title, a navigation controller's title and user label, bar attributes.
SIM_NAV = '                    <simulatedNavigationBarMetrics key="simulatedTopBarMetrics" prompted="NO"/>\n'
NAV_ROUND = {
    "sb-sim-nav-controller": storyboard(controller_scene(1, after_view=SIM_NAV), initial="vc1-aa-aaa"),
    "sb-sim-nav-view": storyboard(controller_scene(1).replace('heightSizable="YES"/>\n', 'heightSizable="YES"/>\n'
                                                               '                        <simulatedNavigationBarMetrics key="simulatedTopBarMetrics" prompted="NO" translucent="NO"/>\n', 1),
                                  initial="vc1-aa-aaa"),
    "sb-nav-item-no-title": storyboard(navigation_scene("vc1-aa-aaa"),
                                       controller_scene(1, after_view='                    <navigationItem key="navigationItem" id="nvi-aa-aaa"/>\n'), initial="nvc-aa-aaa"),
    "sb-nav-item-no-title-add": storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, after_view=
        '                    <navigationItem key="navigationItem" id="nvi-aa-aaa">\n'
        '                        <barButtonItem key="rightBarButtonItem" systemItem="add" id="bbi-aa-aa1"/>\n                    </navigationItem>\n'), initial="nvc-aa-aaa"),
    "sb-nav-title": storyboard(navigation_scene("vc1-aa-aaa", ' title="Accounts"'), controller_scene(1, after_view=navigation_item()), initial="nvc-aa-aaa"),
    "sb-nav-user-label": storyboard(navigation_scene("vc1-aa-aaa", ' userLabel="Main Nav"'), controller_scene(1, after_view=navigation_item()), initial="nvc-aa-aaa"),
    "sb-nav-bar-insets-no": storyboard(navigation_scene("vc1-aa-aaa", bar_attributes=' insetsLayoutMarginsFromSafeArea="NO"'),
                                       controller_scene(1, after_view=navigation_item()), initial="nvc-aa-aaa"),
    "sb-nav-bar-flags": storyboard(navigation_scene("vc1-aa-aaa", bar_attributes=' opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES"'),
                                   controller_scene(1, after_view=navigation_item()), initial="nvc-aa-aaa"),
}
STORYBOARDS.update(NAV_ROUND)



# Round 37: what corpus documents still need from constraints and text fields (pocket-casts',
# nextcloud's, wikipedia's): a constraint's userLabel, baseline attributes between siblings, and a
# text field's enablesReturnKeyAutomatically.
def baseline_siblings(attribute, order):
    pins = pin("xxx-xx-xx1", 0, 10, 20) + pin("yyy-yy-yy1", 1, 150, 20)
    ties = "".join(constraint(10 + k, "xxx-xx-xx1", name, "yyy-yy-yy1", name) for k, name in enumerate(order))
    return constrained(subview("xxx-xx-xx1") + subview("yyy-yy-yy1", (150, 20, 100, 50)), pins + ties)


SMALL_ROUND = {
    "constraint-user-label": constrained(subview("sss-ss-ss1"), constraint(0, "sss-ss-ss1", "leading", ROOT, "leading", ' userLabel="Leading"')
                                         + constraint(1, "sss-ss-ss1", "top", ROOT, "top")),
    "tf-enables-return-key": constrained(text_field(traits=' enablesReturnKeyAutomatically="YES"'), PIN_FIELD),
    "tf-enables-return-key-all": constrained(text_field(traits=' autocorrectionType="no" spellCheckingType="no" keyboardType="numberPad" enablesReturnKeyAutomatically="YES"'),
                                             PIN_FIELD),
}
for attribute in ["firstBaseline", "lastBaseline"]:
    SMALL_ROUND[f"baseline-{attribute}-siblings"] = baseline_siblings(attribute, ["centerX", "leading", "centerY", "bottom", attribute, "top", "height"])
    SMALL_ROUND[f"baseline-{attribute}-alone"] = baseline_siblings(attribute, [attribute])
SMALL_ROUND["tf-adjusts-content-size"] = constrained(text_field(TEXT_FIELD.replace(' minimumFontSize', ' adjustsFontForContentSizeCategory="YES" minimumFontSize')), PIN_FIELD)
SMALL_ROUND["tf-no-alignment"] = constrained(text_field(TEXT_FIELD.replace(' textAlignment="natural"', '')), PIN_FIELD)
SWITCH_COLOR = '                    <color key="{key}" red="0.2" green="0.4" blue="0.6" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>\n'
SMALL_ROUND["sw-on-tint"] = constrained(switch(connections=SWITCH_COLOR.format(key="onTintColor")), PIN_SWITCH)
SMALL_ROUND["sw-thumb-tint"] = constrained(switch(connections=SWITCH_COLOR.format(key="thumbTintColor")), PIN_SWITCH)
SMALL_ROUND["sw-both-tints"] = constrained(switch(connections=SWITCH_COLOR.format(key="onTintColor") + SWITCH_COLOR.format(key="thumbTintColor").replace("0.2", "0.8")),
                                           PIN_SWITCH)
SMALL_ROUND["sw-on-both-tints"] = constrained(switch(SWITCH + ' on="YES"', connections=SWITCH_COLOR.format(key="onTintColor")
                                                     + SWITCH_COLOR.format(key="thumbTintColor").replace("0.2", "0.8")), PIN_SWITCH)
SMALL_ROUND["table-scroll-disabled"] = table_xib(TABLE_ATTRIBUTES + ' scrollEnabled="NO"')
for name, color in [("srgb", '<color key="backgroundColor" red="0.2" green="0.4" blue="0.6" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>'),
                    ("system", '<color key="backgroundColor" systemColor="systemBackgroundColor"/>')]:
    for style in ["none", "gray"]:
        SMALL_ROUND[f"cell-selection-{style}-background-{name}"] = cell_xib(cell_extra=f"            {color}\n").replace(
            'selectionStyle="default"', f'selectionStyle="{style}"')
# Constraints between a view and a subview on different attributes (cwa's contact diary cells).
SMALL_ROUND["cross-attribute-group"] = constrained(subview("sss-ss-ss1"), constraint(0, None, "trailing", "sss-ss-ss1", "trailing")
                                                   + constraint(1, "sss-ss-ss1", "leading", ROOT, "leading") + constraint(2, "sss-ss-ss1", "bottom", ROOT, "centerY")
                                                   + constraint(3, "sss-ss-ss1", "top", ROOT, "top"))
SMALL_ROUND["cross-attribute-normalized"] = constrained(subview("sss-ss-ss1"), constraint(0, None, "trailing", "sss-ss-ss1", "trailing")
                                                        + constraint(1, "sss-ss-ss1", "leading", ROOT, "leading") + constraint(2, None, "bottom", "sss-ss-ss1", "bottom")
                                                        + constraint(3, None, "centerY", "sss-ss-ss1", "top"))
SMALL_ROUND["cross-attribute-two"] = constrained(subview("sss-ss-ss1"), constraint(0, "sss-ss-ss1", "leading", ROOT, "centerX")
                                                 + constraint(1, "sss-ss-ss1", "bottom", ROOT, "centerY") + constraint(2, "sss-ss-ss1", "top", ROOT, "top")
                                                 + constraint(3, None, "trailing", "sss-ss-ss1", "trailing"))
for name, extra in [("constant", ' constant="1"'), ("multiplier", ' multiplier="1/3"')]:
    SMALL_ROUND[f"cross-attribute-{name}"] = constrained(subview("sss-ss-ss1"), constraint(0, "sss-ss-ss1", "centerX", ROOT, "centerX")
                                                         + constraint(1, "sss-ss-ss1", "centerY", ROOT, "bottom", extra))
EXPERIMENTS.update(SMALL_ROUND)



# Round 38: `<mask key="subviews">` defaults (nextcloud's NCShareUserCell): a view's subview left out
# by default, constrained or not, in a view and in a cell's content view.
def subview_mask(excluded, indent=12):
    pad = " " * indent
    return (f'{pad}<variation key="default">\n{pad}    <mask key="subviews">\n'
            + "".join(f'{pad}        <exclude reference="{ref}"/>\n' for ref in excluded) + f'{pad}    </mask>\n{pad}</variation>\n')


SUBVIEW_MASKS = {
    "mask-subviews-root": constrained(subview("aaa-aa-aa1") + subview("bbb-bb-bb1", (150, 20, 100, 50)), pin("aaa-aa-aa1", 0, 10, 20)).replace(
        '            <point key="canvasLocation"', subview_mask(["bbb-bb-bb1"]) + '            <point key="canvasLocation"'),
    "mask-subviews-root-constrained": constrained(subview("aaa-aa-aa1") + subview("bbb-bb-bb1", (150, 20, 100, 50)),
                                                  pin("aaa-aa-aa1", 0, 10, 20) + pin("bbb-bb-bb1", 1, 150, 20)).replace(
        '            <point key="canvasLocation"', subview_mask(["bbb-bb-bb1"]) + '            <point key="canvasLocation"'),
    "mask-subviews-cell": cell_xib(content='                    <subviews>\n' + (subview("aaa-aa-aa1", (10, 5, 100, 30)) + subview("bbb-bb-bb1", (150, 5, 100, 30))).replace(
        "                ", "                    ") + '                    </subviews>\n                    <constraints>\n'
        + constraint(0, "aaa-aa-aa1", "leading", CONTENT, "leading", ' constant="10"', indent=24) + constraint(1, "aaa-aa-aa1", "top", CONTENT, "top", ' constant="5"', indent=24)
        + '                    </constraints>\n' + subview_mask(["bbb-bb-bb1"], 20)),
}
EXPERIMENTS.update(SUBVIEW_MASKS)



# Round 39: constraints whose items are deeper than the view's subviews (the corpus's pocket-casts,
# nextcloud, wikipedia): a grandchild constrained by its grandparent, its group's place by its own
# frame or its frame in the grandparent, and a cell's own constraints to its content view's subviews.
def nested(outer_frame, inner_frame, sibling_frame=None, constraints=""):
    inner = subview("ggg-gg-gg1", inner_frame).replace("                ", "                        ")
    outer = subview("aaa-aa-aa1", outer_frame).replace("</view>\n", "", 1).rstrip() + "\n"
    outer = (f'                <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="aaa-aa-aa1">\n'
             f'                    <rect key="frame" x="{outer_frame[0]}" y="{outer_frame[1]}" width="{outer_frame[2]}" height="{outer_frame[3]}"/>\n'
             f'                    <subviews>\n{inner}                    </subviews>\n                </view>\n')
    sibling = subview("bbb-bb-bb1", sibling_frame) if sibling_frame else ""
    pins = pin("aaa-aa-aa1", 0, int(outer_frame[0]), int(outer_frame[1])) + (pin("bbb-bb-bb1", 1, int(sibling_frame[0]), int(sibling_frame[1])) if sibling_frame else "")
    return constrained(outer + sibling, pins + constraints)


GRAND = constraint(10, "ggg-gg-gg1", "leading", ROOT, "leading", ' constant="105"') + constraint(11, "ggg-gg-gg1", "top", ROOT, "top", ' constant="105"')
DEEP = {
    "deep-grandchild": nested((100, 100, 200, 200), (5, 5, 50, 50), constraints=GRAND),
    "deep-grandchild-sibling-near": nested((100, 100, 200, 200), (5, 5, 50, 50), (50, 50, 20, 20), GRAND),
    "deep-grandchild-sibling-mid": nested((100, 100, 200, 200), (5, 5, 50, 50), (2, 2, 20, 20), GRAND),
    "deep-grandchild-to-child": nested((100, 100, 200, 200), (5, 5, 50, 50), (50, 50, 20, 20),
                                       constraint(10, "ggg-gg-gg1", "leading", "bbb-bb-bb1", "trailing") + constraint(11, "ggg-gg-gg1", "top", "bbb-bb-bb1", "bottom")),
    "deep-cell-content-subview": cell_xib(content='                    <subviews>\n' + subview("sss-ss-ss1", (16, 11, 100, 22)).replace("                ", "                    ")
                                          + '                    </subviews>\n', cell_extra='            <constraints>\n'
                                          + constraint(0, "sss-ss-ss1", "leading", CELL, "leading", ' constant="16"', indent=16)
                                          + constraint(1, "sss-ss-ss1", "top", CELL, "top", ' constant="11"', indent=16) + '            </constraints>\n'),
}
DEEP["deep-grandchild-absolute-near"] = nested((0, 0, 200, 200), (5, 5, 50, 50), (50, 50, 20, 20),
                                               constraint(10, "ggg-gg-gg1", "leading", ROOT, "leading", ' constant="5"') + constraint(11, "ggg-gg-gg1", "top", ROOT, "top", ' constant="5"'))
DEEP["deep-cell-both"] = cell_xib(content='                    <subviews>\n' + (subview("sss-ss-ss1", (16, 11, 100, 22)) + subview("ttt-tt-tt1", (200, 11, 50, 22))).replace("                ", "                    ")
                                  + '                    </subviews>\n                    <constraints>\n'
                                  + constraint(2, "ttt-tt-tt1", "leading", CONTENT, "leading", ' constant="200"', indent=24)
                                  + constraint(3, "ttt-tt-tt1", "top", CONTENT, "top", ' constant="11"', indent=24) + '                    </constraints>\n',
                                  cell_extra='            <constraints>\n' + constraint(0, "sss-ss-ss1", "leading", CELL, "leading", ' constant="16"', indent=16)
                                  + constraint(1, "sss-ss-ss1", "top", CELL, "top", ' constant="11"', indent=16) + '            </constraints>\n')
# Constraints of one item listed by its superview: installed on the item or where listed.
DEEP["deep-width-listed-in-parent"] = constrained(subview("sss-ss-ss1"), pin("sss-ss-ss1", 0, 10, 20) + constraint(5, "sss-ss-ss1", "width", extra=' constant="100"'))
DEEP["deep-width-listed-in-parent-symbolic"] = constrained(subview("sss-ss-ss1"), pin("sss-ss-ss1", 0, 10, 20) + constraint(5, "sss-ss-ss1", "width", extra=' constant="20" symbolic="YES"'))
def stack_with(children, frame=(0, 0, 200, 200)):
    x, y, w, h = frame
    return (f'                <stackView opaque="NO" contentMode="scaleToFill" axis="vertical" spacing="10" translatesAutoresizingMaskIntoConstraints="NO" id="stk-aa-aa1">\n'
            f'                    <rect key="frame" x="{x}" y="{y}" width="{w}" height="{h}"/>\n                    <subviews>\n'
            + children.replace("                ", "                        ") + '                    </subviews>\n                </stackView>\n')


# A view constrained to a stack view's arranged subview: the arranged subview's frame moved by the stack's.
DEEP["deep-through-stack"] = constrained(stack_with(subview("ar1-aa-aa1", (0, 0, 200, 95)) + subview("ar2-aa-aa1", (0, 105, 200, 95)), (0, 60, 200, 200))
                                         + subview("bbb-bb-bb1", (100, 100, 20, 20)),
                                         pin("stk-aa-aa1", 0, 0, 60) + pin("bbb-bb-bb1", 1, 100, 100)
                                         + constraint(10, "ar2-aa-aa1", "trailing", ROOT, "trailing", ' constant="-193"'))
EXPERIMENTS.update(DEEP)



# Round 40: masks per size class (wikipedia's WelcomeContainerViewController, PageHistoryCountsView):
# constraints a default leaves out and size classes put back, or size classes leave out, and a
# subview a size class puts back.
def size_class_masks(entries, indent=12):
    pad = " " * indent
    text = ""
    for key, mask_key, verb, refs in entries:
        text += (f'{pad}<variation key="{key}">\n{pad}    <mask key="{mask_key}">\n'
                 + "".join(f'{pad}        <{verb} reference="{ref}"/>\n' for ref in refs) + f'{pad}    </mask>\n{pad}</variation>\n')
    return text


RC, CC, CR = "heightClass=regular-widthClass=compact", "heightClass=compact-widthClass=compact", "heightClass=compact-widthClass=regular"
SC_CONSTRAINTS = (constraint(0, "sss-ss-ss1", "leading", ROOT, "leading") + constraint(1, "sss-ss-ss1", "top", ROOT, "top")
                  + constraint(2, "sss-ss-ss1", "trailing", ROOT, "trailing") + constraint(3, "sss-ss-ss1", "bottom", ROOT, "bottom"))


def sc_document(entries, subviews=None, constraints=SC_CONSTRAINTS):
    return constrained(subviews or subview("sss-ss-ss1"), constraints).replace(
        '            <point key="canvasLocation"', size_class_masks(entries) + '            <point key="canvasLocation"')


SC_MASKS = {
    "sc-mask-include-one": sc_document([("default", "constraints", "exclude", ["c02-aa-aaa"]), (RC, "constraints", "include", ["c02-aa-aaa"])]),
    "sc-mask-include-two": sc_document([("default", "constraints", "exclude", ["c02-aa-aaa", "c03-aa-aaa"]), (RC, "constraints", "include", ["c02-aa-aaa"]),
                                        (CC, "constraints", "include", ["c03-aa-aaa"])]),
    "sc-mask-include-two-reversed": sc_document([("default", "constraints", "exclude", ["c02-aa-aaa", "c03-aa-aaa"]), (CC, "constraints", "include", ["c03-aa-aaa"]),
                                                 (RC, "constraints", "include", ["c02-aa-aaa"])]),
    "sc-mask-exclude-only": sc_document([(RC, "constraints", "exclude", ["c02-aa-aaa"])]),
    "sc-mask-include-and-exclude": sc_document([("default", "constraints", "exclude", ["c02-aa-aaa"]), (RC, "constraints", "include", ["c02-aa-aaa"]),
                                                (CR, "constraints", "exclude", ["c03-aa-aaa"])]),
    "sc-mask-subview-include": sc_document([("default", "subviews", "exclude", ["bbb-bb-bb1"]), (RC, "subviews", "include", ["bbb-bb-bb1"])],
                                           subview("sss-ss-ss1") + subview("bbb-bb-bb1", (150, 20, 100, 50))),
}
STORYBOARDS["sb-sc-mask-include-two"] = storyboard(scene(view_extra='                        <subviews>\n' + subview("sss-ss-ss1").replace("                ", "                            ")
                                                         + '                        </subviews>\n                        <constraints>\n'
                                                         + SC_CONSTRAINTS.replace(ROOT, "8bC-Xf-vdC").replace("                <", "                            <")
                                                         + '                        </constraints>\n'
                                                         + size_class_masks([("default", "constraints", "exclude", ["c02-aa-aaa", "c03-aa-aaa"]),
                                                                             (RC, "constraints", "include", ["c02-aa-aaa"]), (CC, "constraints", "include", ["c03-aa-aaa"])], 24)))
EXPERIMENTS.update(SC_MASKS)

# Round 41: the order of a storage's records over every size class and single classes, and of a
# record's removed objects.
RR, HC, HR, WC, WR = ("heightClass=regular-widthClass=regular", "heightClass=compact", "heightClass=regular", "widthClass=compact",
                      "widthClass=regular")
SC_ALL = [RR, RC, CR, CC, HC, HR, WC, WR]
SC_ORDER = {
    "sc-mask-order-all": sc_document([("default", "constraints", "exclude", ["c02-aa-aaa"])] + [(key, "constraints", "include", ["c02-aa-aaa"]) for key in SC_ALL]),
    "sc-mask-order-all-reversed": sc_document([("default", "constraints", "exclude", ["c02-aa-aaa"])]
                                              + [(key, "constraints", "include", ["c02-aa-aaa"]) for key in reversed(SC_ALL)]),
    "sc-mask-removed-four": sc_document([("default", "constraints", "exclude", ["c03-aa-aaa", "c01-aa-aaa", "c00-aa-aaa", "c02-aa-aaa"]),
                                         (RC, "constraints", "include", ["c00-aa-aaa", "c01-aa-aaa", "c02-aa-aaa", "c03-aa-aaa"])]),
    "sc-mask-removed-three": sc_document([("default", "constraints", "exclude", ["c00-aa-aaa", "c02-aa-aaa", "c03-aa-aaa"]),
                                          (CC, "constraints", "include", ["c03-aa-aaa", "c00-aa-aaa"])]),
}
EXPERIMENTS.update(SC_ORDER)
SC_SET_PROBE = {f"sc-mask-set-probe-{count}": sc_document([("default", "constraints", "exclude", ["c03-aa-aaa", "c01-aa-aaa", "c00-aa-aaa", "c02-aa-aaa"]),
                                                             (RC, "constraints", "include", ["c00-aa-aaa", "c01-aa-aaa", "c02-aa-aaa", "c03-aa-aaa"])],
                                                            subview("sss-ss-ss1") + "".join(subview(f"x{n:02}-xx-xxx", (300, 20 + 10 * n, 10, 10)) for n in range(count)))
                for count in (1, 2, 3, 5, 8)}
EXPERIMENTS.update(SC_SET_PROBE)


# Round 42: a subview's constraints to views deeper than the subviews, in a group with its
# constraints to the view, to siblings and to the safe area (the corpus's cwa
# ExposureDetectionViewController: a table's top to a grandchild, a button's leading to a
# great-grandchild).
def deep_other(constraints, safe=False, great=False, second_grandchild=False):
    deepest = subview("hhh-hh-hh1", (2, 2, 10, 10)).replace("                ", "                            ") if great else ""
    inner = (f'                        <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="ggg-gg-gg1">\n'
             f'                            <rect key="frame" x="5" y="5" width="50" height="50"/>\n'
             + (f'                            <subviews>\n{deepest}                            </subviews>\n' if great else "")
             + '                        </view>\n')
    if second_grandchild:
        inner += subview("gg2-gg-gg2", (100, 100, 50, 50)).replace("                ", "                        ")
    outer = (f'                <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="aaa-aa-aa1">\n'
             f'                    <rect key="frame" x="100" y="100" width="200" height="200"/>\n'
             f'                    <subviews>\n{inner}                    </subviews>\n                </view>\n')
    return constrained(outer + subview("bbb-bb-bb1", (320, 320, 20, 20)), pin("aaa-aa-aa1", 0, 100, 100) + constraints, safe=safe)


B_PINS = (constraint(2, "bbb-bb-bb1", "leading", ROOT, "leading", ' constant="320"') + constraint(3, "bbb-bb-bb1", "top", ROOT, "top", ' constant="320"'))
DEEP_OTHER = {
    "deep-other-leading": deep_other(B_PINS + constraint(10, "bbb-bb-bb1", "leading", "ggg-gg-gg1", "trailing", ' constant="165"')),
    "deep-other-leading-first": deep_other(constraint(10, "bbb-bb-bb1", "leading", "ggg-gg-gg1", "trailing", ' constant="165"') + B_PINS),
    "deep-other-top": deep_other(B_PINS + constraint(10, "bbb-bb-bb1", "top", "ggg-gg-gg1", "bottom", ' constant="165"')),
    "deep-other-two": deep_other(B_PINS + constraint(10, "bbb-bb-bb1", "top", "ggg-gg-gg1", "bottom", ' constant="165"')
                                 + constraint(11, "bbb-bb-bb1", "leading", "ggg-gg-gg1", "trailing", ' constant="165"')),
    "deep-other-sibling": deep_other(B_PINS + constraint(10, "bbb-bb-bb1", "top", "aaa-aa-aa1", "bottom", ' constant="20"')
                                     + constraint(11, "bbb-bb-bb1", "leading", "ggg-gg-gg1", "trailing", ' constant="165"')),
    "deep-other-great": deep_other(B_PINS + constraint(10, "bbb-bb-bb1", "leading", "hhh-hh-hh1", "trailing", ' constant="203"'), great=True),
    "deep-other-great-and-grand": deep_other(B_PINS + constraint(10, "bbb-bb-bb1", "top", "ggg-gg-gg1", "bottom", ' constant="165"')
                                             + constraint(11, "bbb-bb-bb1", "leading", "hhh-hh-hh1", "trailing", ' constant="203"'), great=True),
    "deep-other-safe": deep_other(constraint(2, "bbb-bb-bb1", "leading", ROOT, "leading", ' constant="320"')
                                  + constraint(3, "bbb-bb-bb1", "top", SAFE_GUIDE, "top", ' constant="320"')
                                  + constraint(10, "bbb-bb-bb1", "leading", "ggg-gg-gg1", "trailing", ' constant="165"'), safe=True),
    "deep-other-trailing-view": deep_other(constraint(2, None, "trailing", "bbb-bb-bb1", "trailing", ' constant="53"')
                                           + constraint(3, "bbb-bb-bb1", "top", ROOT, "top", ' constant="320"')
                                           + constraint(10, "bbb-bb-bb1", "top", "ggg-gg-gg1", "bottom", ' constant="165"')),
}
EXPERIMENTS.update(DEEP_OTHER)
DEEP_OTHER_ORDER = {
    "deep-other-great-top-grand-leading": deep_other(B_PINS + constraint(10, "bbb-bb-bb1", "top", "hhh-hh-hh1", "bottom", ' constant="203"')
                                                     + constraint(11, "bbb-bb-bb1", "leading", "ggg-gg-gg1", "trailing", ' constant="165"'), great=True),
    "deep-other-trailing-leading": deep_other(B_PINS + constraint(10, "bbb-bb-bb1", "leading", "ggg-gg-gg1", "trailing", ' constant="165"')
                                              + constraint(11, "bbb-bb-bb1", "trailing", "ggg-gg-gg1", "trailing", ' constant="185"')),
    "deep-other-center-bottom": deep_other(B_PINS + constraint(10, "bbb-bb-bb1", "bottom", "ggg-gg-gg1", "bottom", ' constant="185"')
                                           + constraint(11, "bbb-bb-bb1", "centerX", "ggg-gg-gg1", "centerX", ' constant="300"')),
}
EXPERIMENTS.update(DEEP_OTHER_ORDER)
DEEP_OTHER_TWO = {
    "deep-other-grand-top-grand2-leading": deep_other(B_PINS + constraint(10, "bbb-bb-bb1", "top", "ggg-gg-gg1", "bottom", ' constant="165"')
                                                      + constraint(11, "bbb-bb-bb1", "leading", "gg2-gg-gg2", "trailing", ' constant="70"'), second_grandchild=True),
    "deep-other-grand2-top-grand-leading": deep_other(B_PINS + constraint(10, "bbb-bb-bb1", "top", "gg2-gg-gg2", "bottom", ' constant="70"')
                                                      + constraint(11, "bbb-bb-bb1", "leading", "ggg-gg-gg1", "trailing", ' constant="165"'), second_grandchild=True),
    "deep-other-great-leading-grand-trailing": deep_other(B_PINS + constraint(10, "bbb-bb-bb1", "trailing", "ggg-gg-gg1", "trailing", ' constant="185"')
                                                          + constraint(11, "bbb-bb-bb1", "leading", "hhh-hh-hh1", "trailing", ' constant="203"'), great=True),
}
EXPERIMENTS.update(DEEP_OTHER_TWO)


# Round 43: where all objects list an effect view's content subviews, against a sibling view's own
# subview (the corpus's cwa ExposureDetectionViewController).
NESTED_SIBLING = ('                <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="nsv-aa-aa1">\n'
                  '                    <rect key="frame" x="20" y="300" width="200" height="100"/>\n                    <subviews>\n'
                  + subview("nsw-aa-aa1", (10, 10, 50, 50)).replace("                ", "                        ") + '                    </subviews>\n                </view>\n')
EFFECT_ORDER = {
    "effect-label-sibling-after": constrained(effect_view(content=EFFECT_LABEL) + NESTED_SIBLING, ""),
    "effect-label-sibling-before": constrained(NESTED_SIBLING + effect_view(content=EFFECT_LABEL), ""),
    "effect-label-constraints-sibling": constrained(effect_view(content=EFFECT_LABEL + '                        <constraints>\n'
                                                                + constraint(10, "lll-ll-ll1", "top", "vec-aa-aa1", "top", ' constant="10"', indent=28)
                                                                + constraint(11, "lll-ll-ll1", "leading", "vec-aa-aa1", "leading", ' constant="10"', indent=28)
                                                                + '                        </constraints>\n') + NESTED_SIBLING, ""),
}
EXPERIMENTS.update(EFFECT_ORDER)


# Round 44: the order of a nib's trait storages when several views have masks, beside constants
# varied by size class (wikipedia's ShareViewController, PageHistoryCountsViewController,
# WelcomeContainerViewController).
def mask_constraints(owner, refs, indent, key="default", verb="exclude"):
    pad = " " * indent
    return (f'{pad}<variation key="{key}">\n{pad}    <mask key="constraints">\n'
            + "".join(f'{pad}        <{verb} reference="{ref}"/>\n' for ref in refs) + f'{pad}    </mask>\n{pad}</variation>\n')


def masked(identifier, frame, inner="", extra_constraints="", indent=16, mask=True, tag="view"):
    """A view holding one subview pinned by its leading and top, the top excluded by default."""
    pad = " " * indent
    child = identifier[:3] + "c-cc-cc1"
    x, y, w, h = frame
    constraints = (f'{pad}        <constraint firstItem="{child}" firstAttribute="leading" secondItem="{identifier}" secondAttribute="leading" constant="5" id="{identifier[:3]}l-ll-ll1"/>\n'
                   f'{pad}        <constraint firstItem="{child}" firstAttribute="top" secondItem="{identifier}" secondAttribute="top" constant="5" id="{identifier[:3]}t-tt-tt1"/>\n'
                   + extra_constraints)
    return (f'{pad}<{tag} contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="{identifier}">\n'
            f'{pad}    <rect key="frame" x="{x}" y="{y}" width="{w}" height="{h}"/>\n{pad}    <subviews>\n'
            + subview(child, (5, 5, 20, 20)).replace("                ", pad + "        ") + inner
            + f'{pad}    </subviews>\n{pad}    <constraints>\n{constraints}{pad}    </constraints>\n'
            + (mask_constraints(identifier, [identifier[:3] + "t-tt-tt1"], indent + 4) if mask else "") + f'{pad}</{tag}>\n')


def root_masked(subviews, constraints, excluded=(), variations=""):
    text = constrained(subviews, constraints)
    if excluded:
        variations = mask_constraints(ROOT, excluded, 12) + variations
    return text.replace('            <point key="canvasLocation"', variations + '            <point key="canvasLocation"')


RR_CONSTANT = '\n                    <variation key="heightClass=regular-widthClass=regular" constant="40"/>\n                </constraint>\n'


def varied(number, first, attribute, second, second_attribute, constant):
    return constraint(number, first, attribute, second, second_attribute, f' constant="{constant}"').replace("/>\n", ">" + RR_CONSTANT)


PINS_AB = pin("aaa-aa-aa1", 0, 20, 40) + pin("bbb-bb-bb1", 1, 20, 200)
MULTI_MASKS = {
    "masks-two-siblings": constrained(masked("aaa-aa-aa1", (20, 40, 100, 100)) + masked("bbb-bb-bb1", (20, 200, 100, 100)), PINS_AB),
    "masks-two-siblings-reversed": constrained(masked("bbb-bb-bb1", (20, 200, 100, 100)) + masked("aaa-aa-aa1", (20, 40, 100, 100)), PINS_AB),
    "masks-root-and-sibling": root_masked(masked("aaa-aa-aa1", (20, 40, 100, 100)) + masked("bbb-bb-bb1", (20, 200, 100, 100), mask=False), PINS_AB, ["c03-aa-aaa"]),
    "masks-nested": constrained(masked("aaa-aa-aa1", (20, 40, 200, 200), inner=masked("ggg-gg-gg1", (50, 50, 100, 100), indent=24)), pin("aaa-aa-aa1", 0, 20, 40)),
    "masks-constants-root-excluded": root_masked(subview("sss-ss-ss1", (20, 40, 100, 100)),
                                                 varied(0, "sss-ss-ss1", "leading", ROOT, "leading", 20) + varied(1, "sss-ss-ss1", "top", ROOT, "top", 40)
                                                 + varied(2, "sss-ss-ss1", "trailing", ROOT, "trailing", 273) + constraint(3, "sss-ss-ss1", "bottom", ROOT, "bottom", ' constant="712"'),
                                                 ["c02-aa-aaa"]),
    "masks-constants-and-subview-mask": constrained(masked("aaa-aa-aa1", (20, 40, 100, 100)),
                                                    varied(0, "aaa-aa-aa1", "leading", ROOT, "leading", 20) + varied(1, "aaa-aa-aa1", "top", ROOT, "top", 40)),
    "masks-constant-in-masked-view": constrained(masked("aaa-aa-aa1", (20, 40, 100, 100), mask=True,
                                                        extra_constraints=varied(9, "aaac-cc-cc1", "width", None, None, 20)), pin("aaa-aa-aa1", 0, 20, 40)),
    "masks-stack-arranged": constrained(stack_with(masked("ar1-aa-aa1", (0, 0, 200, 95)) + masked("ar2-aa-aa1", (0, 105, 200, 95)), (20, 40, 200, 200)),
                                        pin("stk-aa-aa1", 0, 20, 40)),
    "masks-root-to-grandchild": root_masked(masked("aaa-aa-aa1", (20, 40, 200, 200), mask=False, inner=masked("ggg-gg-gg1", (50, 50, 100, 100), indent=24)),
                                            pin("aaa-aa-aa1", 0, 20, 40) + constraint(5, "ggg-gg-gg1", "width", ROOT, "width", ' multiplier="0.25"'), ["c01-aa-aaa"]),
}
EXPERIMENTS.update(MULTI_MASKS)
MULTI_MASKS_WALK = {
    "masks-walk-order": constrained(masked("aaa-aa-aa1", (20, 40, 200, 200), inner=masked("ggg-gg-gg1", (50, 50, 100, 100), indent=24))
                                    + masked("bbb-bb-bb1", (20, 300, 100, 100)), pin("aaa-aa-aa1", 0, 20, 40) + pin("bbb-bb-bb1", 1, 20, 300)),
    "masks-deep-no-root-mask": constrained(masked("aaa-aa-aa1", (20, 40, 200, 200), mask=False, inner=masked("ggg-gg-gg1", (50, 50, 100, 100), indent=24)),
                                           pin("aaa-aa-aa1", 0, 20, 40) + constraint(5, "ggg-gg-gg1", "width", ROOT, "width", ' multiplier="0.25"')),
    "masks-subviews-and-constraints": constrained(masked("aaa-aa-aa1", (20, 40, 200, 200), inner=subview("xxx-xx-xx1", (100, 100, 20, 20)).replace("                ", "                        ")
                                                         ).replace('                    <variation key="default">\n                        <mask key="constraints">',
                                                                   '                    <variation key="default">\n                        <mask key="subviews">\n'
                                                                   '                            <exclude reference="xxx-xx-xx1"/>\n                        </mask>\n'
                                                                   '                        <mask key="constraints">'),
                                                  pin("aaa-aa-aa1", 0, 20, 40)),
    "masks-deep-from-sibling-mask": constrained(masked("aaa-aa-aa1", (20, 40, 200, 200), mask=False, inner=masked("ggg-gg-gg1", (50, 50, 100, 100), indent=24))
                                                + masked("bbb-bb-bb1", (20, 300, 100, 100)),
                                                pin("aaa-aa-aa1", 0, 20, 40) + pin("bbb-bb-bb1", 1, 20, 300) + constraint(5, "bbb-bb-bb1", "width", "ggg-gg-gg1", "width")),
}
# Round 54: how often a masked grandchild named by the root's constraints is walked (wikipedia's
# WelcomeContainerViewController walks a stack view's masked arranged subview once before the
# subviews though four root constraints name it).
GRAND_MASKED = masked("ggg-gg-gg1", (50, 50, 100, 100), indent=24)


def grand_walk(container_tag, constraints, excluded=()):
    holder = masked("aaa-aa-aa1", (20, 40, 200, 200), mask=False, inner=GRAND_MASKED, tag=container_tag)
    if container_tag == "stackView":
        holder = holder.replace('<stackView contentMode="scaleToFill"', '<stackView opaque="NO" contentMode="scaleToFill" axis="vertical"', 1)
    return root_masked(holder, pin("aaa-aa-aa1", 0, 20, 40) + constraints, list(excluded))


MULTI_MASKS_WALK.update({
    "masks-walk-stack-one": grand_walk("stackView", constraint(5, "ggg-gg-gg1", "width", ROOT, "width", ' multiplier="0.25"')),
    "masks-walk-plain-one": grand_walk("view", constraint(5, "ggg-gg-gg1", "width", ROOT, "width", ' multiplier="0.25"')),
    "masks-walk-plain-two": grand_walk("view", constraint(5, "ggg-gg-gg1", "width", ROOT, "width", ' multiplier="0.25"')
                                       + constraint(6, "ggg-gg-gg1", "height", ROOT, "height", ' multiplier="0.117"')),
    "masks-walk-plain-two-one-excluded": grand_walk("view", constraint(5, "ggg-gg-gg1", "width", ROOT, "width", ' multiplier="0.25"')
                                                    + constraint(6, "ggg-gg-gg1", "height", ROOT, "height", ' multiplier="0.117"'), ["c06-aa-aaa"]),
    "masks-walk-plain-one-excluded": grand_walk("view", constraint(5, "ggg-gg-gg1", "width", ROOT, "width", ' multiplier="0.25"'), ["c05-aa-aaa"]),
})
MULTI_MASKS_WALK["masks-walk-size-class-excluded"] = grand_walk("view", constraint(5, "ggg-gg-gg1", "width", ROOT, "width", ' multiplier="0.25"')).replace(
    '            <point key="canvasLocation"', mask_constraints(ROOT, ["c05-aa-aaa"], 12, key="heightClass=compact") + '            <point key="canvasLocation"')
MULTI_MASKS_WALK["masks-walk-size-class-excluded-constant"] = constrained(subview("sss-ss-ss1", (20, 40, 100, 100)),
    varied(0, "sss-ss-ss1", "leading", ROOT, "leading", 20) + varied(1, "sss-ss-ss1", "top", ROOT, "top", 40)).replace(
    '            <point key="canvasLocation"', mask_constraints(ROOT, ["c01-aa-aaa"], 12, key="heightClass=compact") + '            <point key="canvasLocation"')
MULTI_MASKS_WALK["masks-walk-plain-two-first-excluded"] = grand_walk("view", constraint(5, "ggg-gg-gg1", "width", ROOT, "width", ' multiplier="0.25"')
                                                                   + constraint(6, "ggg-gg-gg1", "height", ROOT, "height", ' multiplier="0.117"'), ["c05-aa-aaa"])
EXPERIMENTS.update(MULTI_MASKS_WALK)


# Round 45: constraints to a scene's top and bottom layout guides (uncloudnotes' UnCloudNotes):
# a subview below the top guide, above the bottom guide, both, with a standard spacing, and two
# subviews.
TOP_GUIDE, BOTTOM_GUIDE, SCENE_VIEW = "Llm-lL-Icb", "xb3-aO-Qok", "8bC-Xf-vdC"


def guide_scene(subviews, constraints):
    def pad(text, by):
        return "".join(" " * by + line + "\n" for line in text.splitlines())
    return storyboard(scene(guides=LAYOUT_GUIDES, view_extra='                        <subviews>\n' + pad(subviews, 12)
                            + '                        </subviews>\n                        <constraints>\n' + pad(constraints, 12)
                            + '                        </constraints>\n'))


def guide_sub(identifier="gsb-aa-aa1", frame=(20, 40, 100, 100)):
    return subview(identifier, frame)


GUIDE_LEADING = constraint(0, "gsb-aa-aa1", "leading", SCENE_VIEW, "leading", ' constant="20"')
GUIDE_STORYBOARDS = {
    "sb-guide-top": guide_scene(guide_sub(), GUIDE_LEADING + constraint(1, "gsb-aa-aa1", "top", TOP_GUIDE, "bottom", ' constant="20"')),
    "sb-guide-top-symbolic": guide_scene(guide_sub(), GUIDE_LEADING + constraint(1, "gsb-aa-aa1", "top", TOP_GUIDE, "bottom", ' constant="20" symbolic="YES"')),
    "sb-guide-bottom": guide_scene(guide_sub("gsb-aa-aa1", (20, 744, 100, 100)), GUIDE_LEADING
                                   + constraint(1, BOTTOM_GUIDE, "top", "gsb-aa-aa1", "bottom", ' constant="8"')),
    "sb-guide-both": guide_scene(guide_sub("gsb-aa-aa1", (20, 40, 100, 804)), GUIDE_LEADING + constraint(1, "gsb-aa-aa1", "top", TOP_GUIDE, "bottom", ' constant="20"')
                                 + constraint(2, BOTTOM_GUIDE, "top", "gsb-aa-aa1", "bottom", ' constant="8"')),
    "sb-guide-both-reversed": guide_scene(guide_sub("gsb-aa-aa1", (20, 40, 100, 804)), constraint(2, BOTTOM_GUIDE, "top", "gsb-aa-aa1", "bottom", ' constant="8"')
                                          + constraint(1, "gsb-aa-aa1", "top", TOP_GUIDE, "bottom", ' constant="20"') + GUIDE_LEADING),
    "sb-guide-two-subviews": guide_scene(guide_sub() + guide_sub("gs2-aa-aa1", (200, 744, 100, 100)),
                                         GUIDE_LEADING + constraint(1, "gsb-aa-aa1", "top", TOP_GUIDE, "bottom", ' constant="20"')
                                         + constraint(3, "gs2-aa-aa1", "leading", SCENE_VIEW, "leading", ' constant="200"')
                                         + constraint(4, BOTTOM_GUIDE, "top", "gs2-aa-aa1", "bottom", ' constant="8"')),
    "sb-guide-top-to-top": guide_scene(guide_sub("gsb-aa-aa1", (20, 0, 100, 100)), GUIDE_LEADING + constraint(1, "gsb-aa-aa1", "top", TOP_GUIDE, "top")),
}
STORYBOARDS.update(GUIDE_STORYBOARDS)
GUIDE_GROUPS = {
    "sb-guide-bottom-group": guide_scene(guide_sub("gsb-aa-aa1", (20, 744, 100, 100)) + guide_sub("gs2-aa-aa1", (0, 800, 20, 20)),
                                         GUIDE_LEADING + constraint(1, BOTTOM_GUIDE, "top", "gsb-aa-aa1", "bottom", ' constant="8"')
                                         + constraint(3, "gs2-aa-aa1", "leading", SCENE_VIEW, "leading") + constraint(4, "gs2-aa-aa1", "top", SCENE_VIEW, "top", ' constant="800"')),
    "sb-guide-top-and-height": guide_scene(guide_sub(), GUIDE_LEADING + constraint(1, "gsb-aa-aa1", "top", TOP_GUIDE, "bottom", ' constant="20"')
                                           + constraint(2, "gsb-aa-aa1", "height", SCENE_VIEW, "height", ' multiplier="0.117"')),
    "sb-guide-bottom-and-height": guide_scene(guide_sub("gsb-aa-aa1", (20, 744, 100, 100)), GUIDE_LEADING
                                              + constraint(1, BOTTOM_GUIDE, "top", "gsb-aa-aa1", "bottom", ' constant="8"')
                                              + constraint(2, "gsb-aa-aa1", "height", SCENE_VIEW, "height", ' multiplier="0.117"')),
    "sb-guide-top-group": guide_scene(guide_sub("gsb-aa-aa1", (300, 300, 50, 50)) + guide_sub("gs2-aa-aa1", (10, 10, 20, 20)),
                                      constraint(0, "gsb-aa-aa1", "leading", SCENE_VIEW, "leading", ' constant="300"')
                                      + constraint(1, "gsb-aa-aa1", "top", TOP_GUIDE, "bottom", ' constant="300"')
                                      + constraint(3, "gs2-aa-aa1", "leading", SCENE_VIEW, "leading", ' constant="10"') + constraint(4, "gs2-aa-aa1", "top", SCENE_VIEW, "top", ' constant="10"')),
}
STORYBOARDS.update(GUIDE_GROUPS)
# Round 46: when a text view's text is an NSMutableString (wikipedia's LibrariesUsed storyboard):
# the same text cut to lengths around powers of two, in the element and in the attribute.
LOREM = ("Lorem ipsum dolor sit er elit lamet, consectetaur cillium adipisicing pecu, sed do eiusmod tempor incididunt ut labore et dolore "
         "magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute "
         "irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non "
         "proident, sunt in culpa qui officia deserunt mollit anim id est laborum. Nam liber te conscient to factor tum poen legum odioque civiuda.")
TEXT_LENGTHS = {f"text-view-length-{n}": constrained(text_view(children=TV_BACKGROUND + f'<string key="text">{LOREM[:n]}</string>\n' + TV_FONT + TV_TRAITS), "",
                                                      resources=TVR)
                for n in (15, 16, 31, 32, 63, 64, 127, 128, 255, 256, 257, 300, 384, 448, 500, 511, 512, 513, 529)}
TEXT_LENGTHS["text-view-length-attribute-256"] = constrained(text_view(attributes=TV_ATTRIBUTES + f' text="{LOREM[:256]}"', children=TV_BACKGROUND + TV_FONT + TV_TRAITS),
                                                             "", resources=TVR)
TEXT_LENGTHS["text-view-length-attribute-529"] = constrained(text_view(attributes=TV_ATTRIBUTES + f' text="{LOREM}"', children=TV_BACKGROUND + TV_FONT + TV_TRAITS),
                                                             "", resources=TVR)
TEXT_LENGTHS["label-length-529"] = constrained(label(LABEL_ATTRIBUTES.replace('text="Label" ', ""), extra=f'                    <string key="text">{LOREM}</string>\n'), "")
TEXT_LENGTHS["label-length-attribute-529"] = constrained(label(LABEL_ATTRIBUTES.replace('text="Label"', f'text="{LOREM}"')), "")
EXPERIMENTS.update(TEXT_LENGTHS)
# Round 47: constraints written from the view to a subview's edges at the view's margins
# (kickstarter's Friends storyboard: a stack view held by its view's top and bottom margins).
def norm(number, view_attribute, sub_attribute, extra=""):
    return constraint(number, None, view_attribute, "sss-ss-ss1", sub_attribute, extra)


NORM_SUB = subview("sss-ss-ss1", (8, 8, 100, 100))
NORM_MARGINS = {
    "norm-margin-top-bottom": constrained(NORM_SUB, constraint(0, "sss-ss-ss1", "leading", ROOT, "leading", ' constant="8"')
                                          + norm(1, "topMargin", "top") + norm(2, "bottomMargin", "bottom", ' constant="736"')),
    "norm-margin-bottom-top": constrained(NORM_SUB, constraint(0, "sss-ss-ss1", "leading", ROOT, "leading", ' constant="8"')
                                          + norm(2, "bottomMargin", "bottom", ' constant="736"') + norm(1, "topMargin", "top")),
    "norm-plain-top-bottom": constrained(NORM_SUB, constraint(0, "sss-ss-ss1", "leading", ROOT, "leading", ' constant="8"')
                                         + norm(1, "top", "top", ' constant="-8"') + norm(2, "bottom", "bottom", ' constant="744"')),
    "norm-margin-leading-trailing": constrained(NORM_SUB, constraint(0, "sss-ss-ss1", "top", ROOT, "top", ' constant="8"')
                                                + norm(1, "leadingMargin", "leading") + norm(2, "trailingMargin", "trailing", ' constant="277"')),
    "norm-margin-top-plain-bottom": constrained(NORM_SUB, constraint(0, "sss-ss-ss1", "leading", ROOT, "leading", ' constant="8"')
                                                + norm(1, "topMargin", "top") + norm(2, "bottom", "bottom", ' constant="744"')),
    "norm-margin-friends": constrained(NORM_SUB, constraint(0, "sss-ss-ss1", "leading", ROOT, "leadingMargin")
                                       + constraint(1, "sss-ss-ss1", "trailing", ROOT, "trailingMargin", ' constant="-277"')
                                       + norm(2, "topMargin", "top") + norm(3, "bottomMargin", "bottom", ' constant="736"')),
    "norm-margin-all-four": constrained(NORM_SUB, norm(0, "leadingMargin", "leading") + norm(1, "trailingMargin", "trailing", ' constant="277"')
                                        + norm(2, "topMargin", "top") + norm(3, "bottomMargin", "bottom", ' constant="736"')),
}
NORM_ALL = [("leftMargin", "left"), ("rightMargin", "right"), ("topMargin", "top"), ("bottomMargin", "bottom"), ("leadingMargin", "leading"),
            ("trailingMargin", "trailing"), ("centerXWithinMargins", "centerX"), ("centerYWithinMargins", "centerY"), ("left", "left"), ("right", "right"),
            ("top", "top"), ("bottom", "bottom"), ("leading", "leading"), ("trailing", "trailing"), ("centerX", "centerX"), ("centerY", "centerY"),
            ("width", "width"), ("height", "height")]
NORM_MARGINS["norm-all"] = constrained(NORM_SUB, "".join(norm(k, a, b) for k, (a, b) in enumerate(NORM_ALL)))
NORM_MARGINS["norm-all-reversed"] = constrained(NORM_SUB, "".join(norm(k, a, b) for k, (a, b) in reversed(list(enumerate(NORM_ALL)))))
NORM_MARGINS["sub-first-all"] = constrained(NORM_SUB, "".join(constraint(k, "sss-ss-ss1", b, ROOT, a) for k, (a, b) in enumerate(NORM_ALL)))
NORM_MARGINS["norm-all-ids-reversed"] = constrained(NORM_SUB, "".join(norm(len(NORM_ALL) - 1 - k, a, b) for k, (a, b) in enumerate(NORM_ALL)))
# Round 50: a constraint from the view to a subview's center, or from a view's edge to a
# subview's other edge (cwa's HomeExposureLoggingTableViewCell: the view's trailing margin to an
# icon's centerX), and identified constraints with a constant and a priority.
NORM_MARGINS["norm-cross-trailing-center"] = constrained(NORM_SUB, constraint(0, "sss-ss-ss1", "top", ROOT, "top", ' constant="8"')
                                                        + norm(1, "trailing", "centerX", ' constant="327"')
                                                        + constraint(2, "sss-ss-ss1", "centerY", ROOT, "centerY", ' constant="-368"'))
NORM_MARGINS["norm-cross-margin-center"] = constrained(NORM_SUB, constraint(0, "sss-ss-ss1", "top", ROOT, "top", ' constant="8"')
                                                      + norm(1, "trailingMargin", "centerX", ' constant="319"')
                                                      + constraint(2, "sss-ss-ss1", "centerY", ROOT, "centerY", ' constant="-368"'))
NORM_MARGINS["norm-cross-top-center"] = constrained(NORM_SUB, constraint(0, "sss-ss-ss1", "leading", ROOT, "leading", ' constant="8"')
                                                   + norm(1, "top", "centerY", ' constant="-58"'))
NORM_MARGINS["norm-cross-top-bottom"] = constrained(NORM_SUB, constraint(0, "sss-ss-ss1", "leading", ROOT, "leading", ' constant="8"')
                                                   + norm(1, "top", "bottom", ' constant="-108"') + constraint(2, "sss-ss-ss1", "top", ROOT, "topMargin"))
NORM_MARGINS["identified-constant-priority"] = constrained(NORM_SUB, constraint(0, "sss-ss-ss1", "leading", ROOT, "leading", ' priority="999" constant="8" identifier="a.leading"')
                                                          + constraint(1, "sss-ss-ss1", "top", ROOT, "top", ' constant="8" identifier="a.top"')
                                                          + constraint(2, "sss-ss-ss1", "width", None, None, ' priority="250" constant="100" identifier="a.width"')
                                                          + constraint(3, "sss-ss-ss1", "height", None, None, ' relation="greaterThanOrEqual" priority="750" constant="100" identifier="a.height"'))
# A view constrained to a scroll view's subview (wikipedia's EditLinkViewController): the subview's
# frame moved by the scroll view's.
NORM_MARGINS["deep-through-scroll"] = constrained(
    scroll(children='                    <subviews>\n' + subview("ins-aa-aa1", (10, 10, 100, 50)).replace("                ", "                        ")
           + '                    </subviews>\n', frame=(0, 60, 393, 400)) + subview("bbb-bb-bb1", (100, 500, 20, 20)),
    pin("scr-aa-aa1", 0, 0, 60) + pin("bbb-bb-bb1", 1, 100, 500) + constraint(10, "ins-aa-aa1", "trailing", ROOT, "trailing", ' constant="-283"'))
EXPERIMENTS.update(NORM_MARGINS)


# Round 51: constraints to a scroll view's content and frame layout guides, as IB writes them
# (pocket-casts' ChangeEmailViewController, SleepTimerViewController; wikipedia's
# ScrollableEducationPanelView): guides first and second, both guides in one list.
def scroll_guides(subviews, constraints):
    return constrained(scroll(children='<subviews>\n' + subviews + '</subviews>\n' + SCROLL_GUIDES + '<constraints>\n' + constraints + '</constraints>\n'),
                       constraint(0, "scr-aa-aa1", "top", ROOT, "top") + constraint(1, "scr-aa-aa1", "bottom", ROOT, "bottom")
                       + constraint(2, "scr-aa-aa1", "leading", ROOT, "leading") + constraint(3, "scr-aa-aa1", "trailing", ROOT, "trailing"))


def scv(identifier, frame):
    return subview(identifier, frame).replace("                ", "    ")


def sc(number, first, first_attribute, second, second_attribute, extra=""):
    return constraint(number, first, first_attribute, second, second_attribute, extra, indent=4)


SCROLL_GUIDE_EXPERIMENTS = {
    "scroll-guides-ib": scroll_guides(scv("cnv-aa-aa1", (0, 0, 393, 1000)),
                                      sc(10, "cnv-aa-aa1", "top", "cnt-aa-aa1", "top") + sc(11, "cnt-aa-aa1", "bottom", "cnv-aa-aa1", "bottom")
                                      + sc(12, "cnv-aa-aa1", "leading", "cnt-aa-aa1", "leading") + sc(13, "cnt-aa-aa1", "trailing", "cnv-aa-aa1", "trailing")
                                      + sc(14, "cnv-aa-aa1", "width", "frm-aa-aa1", "width")),
    "scroll-guides-frame-first": scroll_guides(scv("cnv-aa-aa1", (20, 20, 353, 1000)) + scv("btn-aa-aa1", (20, 700, 353, 100)),
                                               sc(10, "cnv-aa-aa1", "top", "cnt-aa-aa1", "top", ' constant="20"')
                                               + sc(11, "cnt-aa-aa1", "bottom", "cnv-aa-aa1", "bottom", ' constant="20"')
                                               + sc(12, "cnv-aa-aa1", "leading", "cnt-aa-aa1", "leading", ' constant="20"')
                                               + sc(13, "cnt-aa-aa1", "trailing", "cnv-aa-aa1", "trailing", ' constant="20"')
                                               + sc(14, "cnv-aa-aa1", "width", "frm-aa-aa1", "width", ' constant="-40"')
                                               + sc(15, "frm-aa-aa1", "trailing", "btn-aa-aa1", "trailing", ' constant="20"')
                                               + sc(16, "frm-aa-aa1", "bottom", "btn-aa-aa1", "bottom", ' constant="52"')
                                               + sc(17, "btn-aa-aa1", "leading", "frm-aa-aa1", "leading", ' constant="20"')
                                               + sc(18, "btn-aa-aa1", "height", "frm-aa-aa1", "height", ' priority="250" constant="-752"')),
    "scroll-guides-frame-first-roles-swapped": None,
}
SCROLL_GUIDE_EXPERIMENTS["scroll-guides-frame-first-roles-swapped"] = SCROLL_GUIDE_EXPERIMENTS["scroll-guides-frame-first"].replace(
    'id="cnt-aa-aa1"/>\n', 'id="cnt-x-aa1"/>\n').replace('id="frm-aa-aa1"/>\n', 'id="cnt-aa-aa1"/>\n').replace('id="cnt-x-aa1"/>\n', 'id="frm-aa-aa1"/>\n')
EXPERIMENTS.update(SCROLL_GUIDE_EXPERIMENTS)
# Round 48: whether ties of one first item to two second items follow memory addresses, as a mask's
# sets do (ADR 0252): the same tie with 0 to 8 unrelated subviews before it.
TIE_PROBES = {f"tie-probe-{count}": tie_document({"A": NEAR, "B": FAR}, "AB", "AB").replace(
    '                <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="aaa-aa-aa1">',
    "".join(subview(f"p{n:02}-pp-ppp", (300, 20 + 10 * n, 5, 5)) for n in range(count))
    + '                <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="aaa-aa-aa1">', 1)
    for count in (0, 1, 2, 3, 5, 8)}
EXPERIMENTS.update(TIE_PROBES)


# Round 49: a safe area's ties to two subviews (wikipedia's FocusNavigationView: the safe area's
# trailing to a line view's and a button's), one factor changed at a time.
LINE, BUTTON = (0, 49, 375, 1), (330, 8, 30, 34)


def safe_tie(frames, constants, order="AB", attribute="trailing"):
    views = {"A": subview("aaa-aa-aa1", frames[0]), "B": subview("bbb-bb-bb1", frames[1])}
    pins = (constraint(0, "aaa-aa-aa1", "leading", SAFE_GUIDE, "leading", f' constant="{int(frames[0][0])}"')
            + constraint(1, "aaa-aa-aa1", "top", SAFE_GUIDE, "top", f' constant="{int(frames[0][1])}"')
            + constraint(2, "bbb-bb-bb1", "top", SAFE_GUIDE, "top", f' constant="{int(frames[1][1])}"'))
    ties = {"A": constraint(10, SAFE_GUIDE, attribute, "aaa-aa-aa1", attribute, f' constant="{constants[0]}"'),
            "B": constraint(11, SAFE_GUIDE, attribute, "bbb-bb-bb1", attribute, f' constant="{constants[1]}"')}
    return constrained(views["A"] + views["B"], pins + "".join(ties[k] for k in order), safe=True)


SAFE_TIES = {
    "safe-tie-focus": safe_tie((LINE, BUTTON), (0, 15)),
    "safe-tie-focus-reversed": safe_tie((LINE, BUTTON), (0, 15), order="BA"),
    "safe-tie-same-constants": safe_tie((LINE, BUTTON), (0, 0)),
    "safe-tie-constants-swapped": safe_tie((LINE, BUTTON), (15, 0)),
    "safe-tie-frames-swapped": safe_tie((BUTTON, LINE), (0, 15)),
    "safe-tie-near-far": safe_tie(((0, 20, 100, 50), (0, 200, 100, 50)), (0, 0)),
    "safe-tie-far-near": safe_tie(((0, 200, 100, 50), (0, 20, 100, 50)), (0, 0)),
}
SAFE_TIES["safe-tie-leading"] = safe_tie(((50, 20, 100, 50), (20, 200, 100, 50)), (0, 0), attribute="leading")
SAFE_TIES["safe-tie-top"] = safe_tie(((300, 60, 50, 50), (20, 20, 50, 50)), (0, 0), attribute="top")
SAFE_TIES["safe-tie-bottom"] = safe_tie(((20, 600, 50, 100), (300, 200, 50, 100)), (0, 0), attribute="bottom")
SAFE_TIES["sub-tie-bottom"] = (lambda: constrained(subview("aaa-aa-aa1", (0, 300, 100, 50)) + subview("bbb-bb-bb1", (150, 400, 100, 50)) + subview("xxx-xx-xx1", (0, 100, 100, 50)),
    pin("aaa-aa-aa1", 0, 0, 300) + pin("bbb-bb-bb1", 1, 150, 400) + pin("xxx-xx-xx1", 2, 0, 100)
    + constraint(10, "xxx-xx-xx1", "bottom", "aaa-aa-aa1", "top", ' relation="lessThanOrEqual" constant="-150"')
    + constraint(11, "xxx-xx-xx1", "bottom", "bbb-bb-bb1", "top", ' relation="lessThanOrEqual" constant="-250"')))()
SAFE_TIES["sub-tie-bottom-unequal"] = SAFE_TIES["sub-tie-bottom"].replace('constant="-250"', 'constant="-200"')
EXPERIMENTS.update(SAFE_TIES)
# Round 52: subviews wholly outside their superview or of no width or height, against a subview
# just nearer and just farther from the origin (pocket-casts' UserEpisodeDetailViewController,
# CheckboxSubtitleCell; kickstarter's pickers at the bottom edge).
def outside(frame_a, frame_b):
    return constrained(subview("aaa-aa-aa1", frame_a) + subview("bbb-bb-bb1", frame_b),
                       pin("aaa-aa-aa1", 0, int(frame_a[0]), int(frame_a[1])) + pin("bbb-bb-bb1", 1, int(frame_b[0]), int(frame_b[1])))


OUTSIDE = {
    "outside-above-near": outside((16, -108, 343, 100), (0, 50, 20, 20)),
    "outside-above-far": outside((16, -108, 343, 100), (0, 120, 20, 20)),
    "outside-left-near": outside((-150, 30, 100, 20), (0, 100, 20, 20)),
    "outside-left-far": outside((-150, 30, 100, 20), (0, 200, 20, 20)),
    "outside-right-edge-near": outside((393, 0, 5, 852), (0, 300, 20, 20)),
    "outside-right-edge-far": outside((393, 0, 5, 852), (0, 500, 20, 20)),
    "outside-bottom-edge-near": outside((0, 852, 393, 50), (0, 800, 20, 20)),
    "outside-bottom-edge-far": outside((0, 852, 393, 50), (300, 800, 20, 20)),
    "outside-zero-height-near": outside((224, 0, 40, 0), (0, 200, 20, 20)),
    "outside-zero-height-far": outside((224, 0, 40, 0), (0, 250, 20, 20)),
    "outside-zero-width-origin": outside((0, 0, 0, 113), (10, 10, 20, 20)),
}
EXPERIMENTS.update(OUTSIDE)


# Round 53: a view deeper than the subviews constrained to the safe area beside the view
# (pocket-casts' FilterSettingsOverlayController: a button in a panel, its leading to the safe
# area's, the view's bottom to its bottom).
def deep_safe(constraints):
    return nested((100, 100, 200, 200), (5, 5, 50, 50), constraints=constraints).replace(
        "            <constraints>", f'            <viewLayoutGuide key="safeArea" id="{SAFE_GUIDE}"/>\n            <constraints>', 1).replace(
        ' colorMatched="YES"', ' useSafeAreas="YES" colorMatched="YES"').replace(
        '        <capability name="documents saved', SAFE_AREA_CAPABILITY + '        <capability name="documents saved')


DEEP_SAFE = {
    "deep-safe-leading-bottom": deep_safe(constraint(10, "ggg-gg-gg1", "leading", SAFE_GUIDE, "leading", ' constant="105"')
                                          + constraint(11, None, "bottom", "ggg-gg-gg1", "bottom", ' constant="697"')),
    "deep-safe-top-leading": deep_safe(constraint(10, "ggg-gg-gg1", "top", SAFE_GUIDE, "top", ' constant="46"')
                                       + constraint(11, "ggg-gg-gg1", "leading", ROOT, "leading", ' constant="105"')),
    "deep-safe-first-trailing": deep_safe(constraint(10, SAFE_GUIDE, "trailing", "ggg-gg-gg1", "trailing", ' constant="238"')
                                          + constraint(11, "ggg-gg-gg1", "top", ROOT, "top", ' constant="105"')),
    "deep-safe-two-and-view": deep_safe(constraint(10, "ggg-gg-gg1", "top", SAFE_GUIDE, "top", ' constant="46"')
                                        + constraint(11, "ggg-gg-gg1", "leading", SAFE_GUIDE, "leading", ' constant="105"')
                                        + constraint(12, "ggg-gg-gg1", "width", ROOT, "width", ' multiplier="0.127"')),
}
# Round 55: a grandchild whose absolute frame lies nearer the origin than its parent's (cwa's
# OnboardingInfoViewController: an image view at -16 in a stack view's arranged view).
GRAND_NEAR = constraint(10, "ggg-gg-gg1", "leading", ROOT, "leading", ' constant="10"') + constraint(11, "ggg-gg-gg1", "top", ROOT, "top", ' constant="10"')
DEEP_SAFE.update({
    "deep-negative-offset": nested((100, 100, 200, 200), (-90, -90, 50, 50), constraints=GRAND_NEAR),
    "deep-negative-offset-sibling": nested((100, 100, 200, 200), (-90, -90, 50, 50), (50, 50, 20, 20), GRAND_NEAR),
    "deep-negative-offset-sibling-far": nested((100, 100, 200, 200), (-90, -90, 50, 50), (300, 300, 20, 20), GRAND_NEAR),
})
EXPERIMENTS.update(DEEP_SAFE)


def moved_view(root_constraints, own_constraints=""):
    inner = subview("ggg-gg-gg1", (5, 5, 50, 50)).replace("                ", "                        ")
    own = f'                    <constraints>\n{own_constraints}                    </constraints>\n' if own_constraints else ""
    holder = ('                <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="aaa-aa-aa1">\n'
              '                    <rect key="frame" x="100" y="100" width="200" height="200"/>\n'
              f'                    <subviews>\n{inner}                    </subviews>\n{own}                </view>\n')
    return constrained(holder + subview("bbb-bb-bb1", (300, 300, 20, 20)),
                       pin("aaa-aa-aa1", 0, 100, 100) + pin("bbb-bb-bb1", 1, 300, 300) + root_constraints)


# Round 56: constraints ibtool installs on a descendant of the view that lists them, their items'
# nearest common ancestor (pocket-casts' FilterNameCell: a cell's constraints between its content
# view and that view's labels; VideoViewController: a view's constraint between a subview and its
# button).
CELL_LABELS = (subview("sss-ss-ss1", (16, 11, 100, 22)) + subview("ttt-tt-tt1", (200, 11, 50, 22))).replace("                ", "                    ")


def moved_cell(cell_constraints, content_constraints=""):
    content = '                    <subviews>\n' + CELL_LABELS + '                    </subviews>\n'
    if content_constraints:
        content += '                    <constraints>\n' + content_constraints + '                    </constraints>\n'
    return cell_xib(content=content, cell_extra='            <constraints>\n' + cell_constraints + '            </constraints>\n')


MOVED = {
    "moved-cell-content-trailing": moved_cell(constraint(0, CONTENT, "trailing", "ttt-tt-tt1", "trailing", ' constant="70"', indent=16),
                                              constraint(2, "ttt-tt-tt1", "top", CONTENT, "top", ' constant="11"', indent=24)
                                              + constraint(3, "sss-ss-ss1", "leading", CONTENT, "leading", ' constant="16"', indent=24)
                                              + constraint(4, "sss-ss-ss1", "top", CONTENT, "top", ' constant="11"', indent=24)),
    "moved-cell-labels": moved_cell(constraint(0, "ttt-tt-tt1", "leading", "sss-ss-ss1", "trailing", ' constant="84"', indent=16),
                                    constraint(2, "ttt-tt-tt1", "top", CONTENT, "top", ' constant="11"', indent=24)
                                    + constraint(3, "sss-ss-ss1", "leading", CONTENT, "leading", ' constant="16"', indent=24)
                                    + constraint(4, "sss-ss-ss1", "top", CONTENT, "top", ' constant="11"', indent=24)),
    "moved-cell-only": moved_cell(constraint(0, "sss-ss-ss1", "leading", CONTENT, "leading", ' constant="16"', indent=16)
                                  + constraint(1, "sss-ss-ss1", "top", CONTENT, "top", ' constant="11"', indent=16)
                                  + constraint(2, "ttt-tt-tt1", "leading", "sss-ss-ss1", "trailing", ' constant="84"', indent=16)
                                  + constraint(3, "ttt-tt-tt1", "top", CONTENT, "top", ' constant="11"', indent=16)),
    "moved-view-button": moved_view(constraint(10, "ggg-gg-gg1", "leading", "aaa-aa-aa1", "trailing", ' constant="-195"')),
    "moved-view-with-own": moved_view(constraint(10, "ggg-gg-gg1", "leading", "aaa-aa-aa1", "leading", ' constant="5"'),
                                      constraint(11, "ggg-gg-gg1", "top", "aaa-aa-aa1", "top", ' constant="5"', indent=24)
                                      + constraint(12, "ggg-gg-gg1", "width", "aaa-aa-aa1", "width", ' multiplier="0.25"', indent=24)),
    "moved-view-two": moved_view(constraint(10, None, "trailing", "ggg-gg-gg1", "trailing", ' constant="145"')
                                 + constraint(13, "ggg-gg-gg1", "bottom", "aaa-aa-aa1", "bottom", ' constant="-145"'),
                                 constraint(11, "ggg-gg-gg1", "top", "aaa-aa-aa1", "top", ' constant="5"', indent=24)),
}
MOVED["moved-cell-mixed"] = moved_cell(constraint(0, "ttt-tt-tt1", "top", "sss-ss-ss1", "top", indent=16)
                                        + constraint(1, "sss-ss-ss1", "leading", CELL, "leading", ' constant="16"', indent=16)
                                        + constraint(2, "ttt-tt-tt1", "leading", "sss-ss-ss1", "trailing", ' constant="84"', indent=16),
                                        constraint(3, "sss-ss-ss1", "top", CONTENT, "top", ' constant="11"', indent=24))
EXPERIMENTS.update(MOVED)


# Round 57: subviews whose different frames lie as far from their superview's origin, in both
# document orders and with their ids swapped.
def same_distance(frame_a, frame_b, order="AB", ids=("aaa-aa-aa1", "bbb-bb-bb1")):
    views = {"A": subview(ids[0], frame_a), "B": subview(ids[1], frame_b)}
    pins = {"A": pin(ids[0], 0, int(frame_a[0]), int(frame_a[1])), "B": pin(ids[1], 1, int(frame_b[0]), int(frame_b[1]))}
    return constrained("".join(views[k] for k in order), "".join(pins[k] for k in order))


SAME_DISTANCE = {
    "same-distance-axes": same_distance((100, 0, 20, 20), (0, 100, 20, 20)),
    "same-distance-axes-reversed": same_distance((100, 0, 20, 20), (0, 100, 20, 20), order="BA"),
    "same-distance-axes-ids-swapped": same_distance((100, 0, 20, 20), (0, 100, 20, 20), ids=("bbb-bb-bb1", "aaa-aa-aa1")),
    "same-distance-345": same_distance((30, 40, 20, 20), (40, 30, 20, 20)),
    "same-distance-345-reversed": same_distance((30, 40, 20, 20), (40, 30, 20, 20), order="BA"),
    "same-distance-345-ids-swapped": same_distance((30, 40, 20, 20), (40, 30, 20, 20), ids=("bbb-bb-bb1", "aaa-aa-aa1")),
    "same-distance-sizes": same_distance((100, 0, 50, 10), (0, 100, 10, 50)),
}
SAME_DISTANCE.update({
    "same-distance-same-y": same_distance((30, 40, 20, 20), (-30, 40, 20, 20)),
    "same-distance-same-x": same_distance((30, -40, 20, 20), (30, 40, 20, 20)),
    "same-distance-diagonal": same_distance((-40, -30, 20, 20), (40, 30, 20, 20)),
})
EXPERIMENTS.update(SAME_DISTANCE)


# Round 59: a safe area's ties to two subviews of equal constants, each attribute against the
# subviews' relative places (round 49 left the rule open; 32 corpus, holdout and sweep documents).
SAFE_TIE_PLACES = {"above": ((100, 100, 50, 50), (100, 400, 50, 50)), "below": ((100, 400, 50, 50), (100, 100, 50, 50)),
                   "left": ((50, 300, 50, 50), (250, 300, 50, 50)), "right": ((250, 300, 50, 50), (50, 300, 50, 50))}
for _attribute in ("top", "bottom", "leading", "trailing"):
    for _place, _frames in SAFE_TIE_PLACES.items():
        EXPERIMENTS[f"safe-tie-grid-{_attribute}-{_place}"] = safe_tie(_frames, (0, 0), attribute=_attribute)


# Round 60: what orders a safe area's ties of the same constant and perpendicular coordinate (ids,
# subview order, which subview has more constraints), and a subview's ties to two siblings: the
# position each implies for the subview's attribute, measured from that attribute's side.
_below = SAFE_TIE_PLACES["below"]
EXPERIMENTS["safe-tie-grid-top-below-ids-swapped"] = safe_tie(_below, (0, 0), attribute="top").replace("aaa-aa-aa1", "zzz-zz-zz9").replace("bbb-bb-bb1", "aaa-aa-aa1").replace(
    "zzz-zz-zz9", "bbb-bb-bb1")
EXPERIMENTS["safe-tie-grid-top-below-order-swapped"] = safe_tie(_below, (0, 0), order="BA", attribute="top")
EXPERIMENTS["safe-tie-grid-top-below-subviews-swapped"] = (lambda text: text.replace(
    subview("aaa-aa-aa1", _below[0]) + subview("bbb-bb-bb1", _below[1]), subview("bbb-bb-bb1", _below[1]) + subview("aaa-aa-aa1", _below[0])))(
    safe_tie(_below, (0, 0), attribute="top"))


def sub_tie(frame_a, frame_b, attribute, other_attribute, constants=(0, 0), relation="", x_frame=(0, 400, 50, 50)):
    extra = f' relation="{relation}"' if relation else ""
    return constrained(subview("aaa-aa-aa1", frame_a) + subview("bbb-bb-bb1", frame_b) + subview("xxx-xx-xx1", x_frame),
                       pin("aaa-aa-aa1", 0, int(frame_a[0]), int(frame_a[1])) + pin("bbb-bb-bb1", 1, int(frame_b[0]), int(frame_b[1]))
                       + pin("xxx-xx-xx1", 2, int(x_frame[0]), int(x_frame[1]))
                       + constraint(10, "xxx-xx-xx1", attribute, "aaa-aa-aa1", other_attribute, f'{extra} constant="{constants[0]}"')
                       + constraint(11, "xxx-xx-xx1", attribute, "bbb-bb-bb1", other_attribute, f'{extra} constant="{constants[1]}"'))


SUB_TIES = {
    "sub-tie-leading-trailing": sub_tie((0, 0, 100, 50), (0, 100, 150, 50), "leading", "trailing"),
    "sub-tie-leading-trailing-frames-swapped": sub_tie((0, 0, 150, 50), (0, 100, 100, 50), "leading", "trailing"),
    "sub-tie-leading-trailing-equal": sub_tie((0, 0, 100, 50), (0, 100, 150, 50), "leading", "trailing", (60, 10)),
    "sub-tie-leading-trailing-ge": sub_tie((0, 0, 100, 50), (0, 100, 150, 50), "leading", "trailing", (8, 8), "greaterThanOrEqual"),
    "sub-tie-trailing-leading": sub_tie((200, 0, 100, 50), (250, 100, 100, 50), "trailing", "leading", (-20, -20), x_frame=(0, 400, 150, 50)),
    "sub-tie-trailing-leading-frames-swapped": sub_tie((250, 0, 100, 50), (200, 100, 100, 50), "trailing", "leading", (-20, -20), x_frame=(0, 400, 150, 50)),
    "sub-tie-top-bottom": sub_tie((0, 0, 50, 100), (100, 0, 50, 150), "top", "bottom", (8, 8)),
    "sub-tie-top-bottom-equal": sub_tie((0, 0, 50, 100), (100, 0, 50, 150), "top", "bottom", (58, 8)),
    "sub-tie-center-y": sub_tie((0, 100, 50, 50), (100, 300, 50, 50), "centerY", "centerY", x_frame=(200, 0, 50, 50)),
    "sub-tie-center-y-frames-swapped": sub_tie((0, 300, 50, 50), (100, 100, 50, 50), "centerY", "centerY", x_frame=(200, 0, 50, 50)),
    "sub-tie-center-x": sub_tie((100, 0, 50, 50), (300, 100, 50, 50), "centerX", "centerX"),
    "sub-tie-leading-leading": sub_tie((50, 0, 50, 50), (20, 100, 50, 50), "leading", "leading"),
}
_left, _above = SAFE_TIE_PLACES["left"], SAFE_TIE_PLACES["above"]
EXPERIMENTS["safe-tie-grid-top-left-constants"] = safe_tie(_left, (10, 0), attribute="top")
EXPERIMENTS["safe-tie-grid-top-left-constants-other"] = safe_tie(_left, (0, 10), attribute="top")
EXPERIMENTS["safe-tie-grid-top-above-constants"] = safe_tie(_above, (0, 10), attribute="top")
EXPERIMENTS["safe-tie-grid-top-below-pins-swapped"] = safe_tie((_below[1], _below[0]), (0, 0), attribute="top").replace(
    "aaa-aa-aa1", "zzz-zz-zz9").replace("bbb-bb-bb1", "aaa-aa-aa1").replace("zzz-zz-zz9", "bbb-bb-bb1")
EXPERIMENTS["safe-tie-grid-top-below-mention-vs-count"] = constrained(
    subview("aaa-aa-aa1", _below[0]) + subview("bbb-bb-bb1", _below[1]),
    constraint(0, "aaa-aa-aa1", "top", SAFE_GUIDE, "top", ' constant="400"')
    + constraint(1, "bbb-bb-bb1", "leading", SAFE_GUIDE, "leading", ' constant="100"') + constraint(2, "bbb-bb-bb1", "top", SAFE_GUIDE, "top", ' constant="100"')
    + constraint(10, SAFE_GUIDE, "top", "aaa-aa-aa1", "top", ' constant="0"') + constraint(11, SAFE_GUIDE, "top", "bbb-bb-bb1", "top", ' constant="0"'), safe=True)
EXPERIMENTS["safe-tie-trailing-origin-vs-center"] = safe_tie(((0, 100, 100, 300), (150, 200, 100, 50)), (0, 0))
EXPERIMENTS["safe-tie-trailing-origin-vs-end"] = safe_tie(((0, 100, 100, 120), (150, 200, 100, 50)), (0, 0))
EXPERIMENTS["safe-tie-trailing-center-vs-end"] = safe_tie(((0, 100, 100, 300), (150, 240, 100, 40)), (0, 0))
EXPERIMENTS.update(SUB_TIES)
# Round 58: a xib's and a storyboard's `<deployment version>` (IB's deployment target, iOS major x
# 256 + minor x 16), from 7.0 to 27.0, at the default target and at one below and above it.
DOCUMENT_VERSIONS = {"7.0": 1792, "8.0": 2048, "8.4": 2112, "9.0": 2304, "15.0": 3840, "17.0": 4352, "18.0": 4608, "18.6": 4704, "18.7": 4720, "19.0": 4864, "21.0": 5376, "22.0": 5632, "22.15.15": 5887, "23.0": 5888, "24.0": 6144, "25.0": 6400, "26.0": 6656, "27.0": 6912}
for _label, _version in DOCUMENT_VERSIONS.items():
    EXPERIMENTS[f"document-version-{_label}"] = BASE.replace('        <plugIn', f'        <deployment version="{_version}" identifier="iOS"/>\n        <plugIn', 1)
    STORYBOARDS[f"sb-document-version-{_label}"] = STORYBOARD.replace('        <plugIn', f'        <deployment version="{_version}" identifier="iOS"/>\n        <plugIn', 1)
for _label in ("17.0", "9.0"):
    EXPERIMENTS[f"document-version-{_label}-target-15.0"] = EXPERIMENTS[f"document-version-{_label}"]
    OPTIONS[f"document-version-{_label}-target-15.0"] = {"deployment": "15.0"}
    STORYBOARDS[f"sb-document-version-{_label}-target-15.0"] = STORYBOARDS[f"sb-document-version-{_label}"]
    OPTIONS[f"sb-document-version-{_label}-target-15.0"] = {"deployment": "15.0"}


# Round 62: Xcode 8's `<simulatedMetricsContainer key="defaultSimulatedMetrics">` in storyboards
# without and with a `<device>` (RxSwift's example storyboards): its screen type against the scene
# frame and the device's.
def metrics_container(screen):
    return ('    <simulatedMetricsContainer key="defaultSimulatedMetrics">\n        <simulatedStatusBarMetrics key="statusBar"/>\n'
            '        <simulatedOrientationMetrics key="orientation"/>\n'
            f'        <simulatedScreenMetrics key="destination" type="{screen}"/>\n    </simulatedMetricsContainer>\n')


_NO_DEVICE = STORYBOARD.replace('    <device id="retina6_12" orientation="portrait" appearance="light"/>\n', "")
for _screen, _size in (("retina4_7.fullscreen", ("375", "667")), ("retina4", ("320", "568"))):
    _matching = _NO_DEVICE.replace('width="393" height="852"', f'width="{_size[0]}" height="{_size[1]}"')
    STORYBOARDS[f"sb-metrics-{_screen}"] = _matching.replace("</document>", metrics_container(_screen) + "</document>")
    STORYBOARDS[f"sb-metrics-{_screen}-frame-393"] = _NO_DEVICE.replace("</document>", metrics_container(_screen) + "</document>")
    STORYBOARDS[f"sb-metrics-{_screen}-device"] = STORYBOARD.replace("</document>", metrics_container(_screen) + "</document>")
STORYBOARDS["sb-no-device-375"] = _NO_DEVICE.replace('width="393" height="852"', 'width="375" height="667"')
# Round 63: a scene's view below an opaque simulated navigation bar, at y 64 (RxSwift's example
# storyboards, with Xcode 8's metrics container).
_OPAQUE_BAR = '                    <simulatedNavigationBarMetrics key="simulatedTopBarMetrics" translucent="NO" prompted="NO"/>\n'
for _height in ("603", "667"):
    STORYBOARDS[f"sb-view-at-64-{_height}"] = _NO_DEVICE.replace('x="0.0" y="0.0" width="393" height="852"', f'x="0.0" y="64" width="375" height="{_height}"').replace(
        "                </viewController>", _OPAQUE_BAR + "                </viewController>").replace("</document>", metrics_container("retina4_7.fullscreen") + "</document>")
STORYBOARDS["sb-view-at-64-device"] = STORYBOARD.replace('x="0.0" y="0.0" width="393" height="852"', 'x="0.0" y="64" width="393" height="788"').replace(
    "                </viewController>", _OPAQUE_BAR + "                </viewController>")
STORYBOARDS["sb-view-at-20-device"] = STORYBOARD.replace('x="0.0" y="0.0" width="393" height="852"', 'x="0.0" y="20" width="393" height="832"')
STORYBOARDS["sb-view-at-10-20"] = _NO_DEVICE.replace('x="0.0" y="0.0" width="393" height="852"', 'x="10" y="20" width="375" height="647"')
# Old documents' headers: Xcode 5's `<development>` and the multipliers capability.
EXPERIMENTS["development-xcode-5100"] = BASE.replace('        <plugIn', '        <development version="5100" identifier="xcode"/>\n        <plugIn', 1)
EXPERIMENTS["capability-multipliers"] = BASE.replace('        <plugIn', '        <capability name="Constraints with non-1.0 multipliers" minToolsVersion="5.1"/>\n        <plugIn', 1)
STORYBOARDS["sb-development-xcode-5100"] = STORYBOARD.replace('        <plugIn', '        <development version="5100" identifier="xcode"/>\n        <plugIn', 1)
# Round 64: a subview that does not translate its autoresizing mask into constraints and has a mask,
# constrained or not, by mask.
_MASKS = {"flexible": 'flexibleMaxX="YES" flexibleMaxY="YES"', "sizable": 'widthSizable="YES" heightSizable="YES"', "empty": "",
          "all": 'flexibleMinX="YES" widthSizable="YES" flexibleMaxX="YES" flexibleMinY="YES" heightSizable="YES" flexibleMaxY="YES"'}


def masked_subview(mask):
    bits = f" {_MASKS[mask]}" if _MASKS[mask] else ""
    return subview("sss-ss-ss1", (20, 40, 100, 50)).replace('<rect key="frame" x="20" y="40" width="100" height="50"/>\n',
                                                         f'<rect key="frame" x="20" y="40" width="100" height="50"/>\n'
                                                         f'                    <autoresizingMask key="autoresizingMask"{bits}/>\n')


for _mask in _MASKS:
    EXPERIMENTS[f"no-translate-mask-{_mask}"] = constrained(masked_subview(_mask), pin("sss-ss-ss1", 0, 20, 40))
    EXPERIMENTS[f"no-translate-mask-{_mask}-unconstrained"] = constrained(masked_subview(_mask), "")
STORYBOARDS["sb-no-translate-mask-flexible"] = storyboard(scene(view_extra='                        <subviews>\n'
    + masked_subview("flexible").replace("                ", "                            ") + '                        </subviews>\n'
    + '                        <constraints>\n' + pin("sss-ss-ss1", 0, 20, 40).replace(ROOT, "8bC-Xf-vdC").replace("                <", "                            <")
    + '                        </constraints>\n'))
STORYBOARDS["sb-view-opaque-bar-at-0"] = _NO_DEVICE.replace('x="0.0" y="0.0" width="393" height="852"', 'x="0.0" y="0.0" width="375" height="603"').replace(
    "                </viewController>", _OPAQUE_BAR + "                </viewController>").replace("</document>", metrics_container("retina4_7.fullscreen") + "</document>")
STORYBOARDS["sb-guide-bottom-position"] = guide_scene(
    guide_sub("gsb-aa-aa1", (20, 600, 100, 100)) + guide_sub("gs2-aa-aa1", (100, 845, 5, 5)) + guide_sub("gs3-aa-aa1", (200, 830, 5, 5)),
    GUIDE_LEADING + constraint(1, BOTTOM_GUIDE, "top", "gsb-aa-aa1", "bottom", ' constant="152"')
    + constraint(3, "gs2-aa-aa1", "leading", SCENE_VIEW, "leading", ' constant="100"') + constraint(4, "gs2-aa-aa1", "top", SCENE_VIEW, "top", ' constant="845"')
    + constraint(5, "gs3-aa-aa1", "leading", SCENE_VIEW, "leading", ' constant="200"') + constraint(6, "gs3-aa-aa1", "top", SCENE_VIEW, "top", ' constant="830"'))


def run(args):
    return subprocess.run(args, capture_output=True)


def compile_xib(path, out, name):
    out.mkdir(parents=True, exist_ok=True)
    module, deployment, devices = options(name)
    proc = run(["xcrun", "ibtool", "--errors", "--warnings", "--notices", "--module", module, "--output-partial-info-plist",
                str(out / "PartialInfo.plist"), "--auto-activate-custom-fonts",
                *[argument for device in devices for argument in ("--target-device", device)],
                "--minimum-deployment-target", deployment, "--output-format", "human-readable-text",
                "--compile", str(out / (path.stem + ".nib")), str(path)])
    files = {str(p.relative_to(out)): base64.b64encode(p.read_bytes()).decode() for p in sorted(out.rglob("*")) if p.is_file()}
    return {"status": proc.returncode, "stdout": proc.stdout.decode(errors="replace"), "stderr": proc.stderr.decode(errors="replace"),
            "files": files}


# Round 66: text fields' clear button modes, alone and with a rounded border.
CLEAR_BUTTONS = {f"tf-clear-{mode}": constrained(text_field(TEXT_FIELD.replace(' translatesAutoresizing', f' clearButtonMode="{mode}" translatesAutoresizing')), "")
                 for mode in ("never", "whileEditing", "unlessEditing", "always")}
CLEAR_BUTTONS["tf-clear-whileEditing-rounded"] = constrained(text_field(TEXT_FIELD.replace(' translatesAutoresizing', ' borderStyle="roundedRect" clearButtonMode="whileEditing" translatesAutoresizing')), "")
EXPERIMENTS.update(CLEAR_BUTTONS)

# Round 67: text fields' other attributes, colors and input traits, as the corpus has them.
def tf_with(attributes="", traits="", children=""):
    field = text_field(TEXT_FIELD.replace(' translatesAutoresizing', attributes + ' translatesAutoresizing'), traits)
    return constrained(field.replace("                </textField>", "".join(f"                    {l}\n" for l in children.splitlines()) + "                </textField>"), "")


TEXT_FIELDS2 = {
    "tf-traits-every": tf_with(traits=' autocapitalizationType="words" autocorrectionType="no" spellCheckingType="no" keyboardType="emailAddress" returnKeyType="next" '
                                    'enablesReturnKeyAutomatically="YES" secureTextEntry="YES" smartDashesType="no" smartInsertDeleteType="no" smartQuotesType="no" '
                                    'textContentType="username"'),
    "tf-secure": tf_with(traits=' secureTextEntry="YES"'),
    "tf-autocap-sentences": tf_with(traits=' autocapitalizationType="sentences"'),
    "tf-adjusts-NO": tf_with(' adjustsFontSizeToFit="NO"'),
    "tf-clears-on-begin": tf_with(' clearsOnBeginEditing="YES"'),
    "tf-border-line": tf_with(' borderStyle="line"'),
    "tf-nil-text-color": tf_with(children='<nil key="textColor"/>'),
    "tf-text-color": tf_with(children=gray(0.5, 1).replace("backgroundColor", "textColor")),
    "tf-placeholder-string": tf_with(children='<string key="placeholder">Name</string>').replace(' placeholder="Name"', "", 1),
    "tf-valign-bottom": tf_with().replace('contentVerticalAlignment="center"', 'contentVerticalAlignment="bottom"', 1),
}
for value in ("done", "search", "go"):
    TEXT_FIELDS2[f"tf-return-{value}"] = tf_with(traits=f' returnKeyType="{value}"')
for value in ("numbersAndPunctuation", "URL"):
    TEXT_FIELDS2[f"tf-keyboard-{value}"] = tf_with(traits=f' keyboardType="{value}"')
for value in ("password", "email"):
    TEXT_FIELDS2[f"tf-content-{value}"] = tf_with(traits=f' textContentType="{value}"')
for value in ("center", "right"):
    TEXT_FIELDS2[f"tf-align-{value}"] = tf_with().replace('textAlignment="natural"', f'textAlignment="{value}"', 1)
for value in ("right", "trailing"):
    TEXT_FIELDS2[f"tf-halign-{value}"] = tf_with().replace('contentHorizontalAlignment="left"', f'contentHorizontalAlignment="{value}"', 1)
TEXT_FIELDS2["tf-clears-rounded-text"] = tf_with(' borderStyle="roundedRect" clearsOnBeginEditing="YES"').replace('placeholder="Name"', 'text="x" placeholder="Name"', 1)
TEXT_FIELDS2["segmented-control-disabled"] = EXPERIMENTS["segmented"].replace('segmentControlStyle="plain"', 'segmentControlStyle="plain" enabled="NO"', 1)
TEXT_FIELDS2["segmented-control-disabled-alpha"] = EXPERIMENTS["segmented"].replace('segmentControlStyle="plain"', 'segmentControlStyle="plain" enabled="NO" alpha="0.80000000000000004"', 1)
for stops in ("NO", "YES"):
    for animating in ("NO", "YES"):
        TEXT_FIELDS2[f"activity-hidden-stops-{stops}-animating-{animating}"] = constrained(control("activityIndicatorView", 'opaque="NO" contentMode="scaleToFill" '
            f'style="medium" hidesWhenStopped="{stops}" animating="{animating}" hidden="YES"', frame=(10, 24, 20, 20)), "")
EXPERIMENTS.update(TEXT_FIELDS2)

# Round 68: table views' other attributes and elements, as the corpus has them.
def table_with(attribute="", extra=""):
    return table_xib(TABLE_ATTRIBUTES.replace(' translatesAutoresizing', attribute + ' translatesAutoresizing'), extra)


TABLES2 = {
    "table-estimated-section-heights": table_with(' estimatedSectionHeaderHeight="44" estimatedSectionFooterHeight="12"'),
    "table-estimated-section-header": table_with(' estimatedSectionHeaderHeight="-1"'),
    "table-scroll-flags": table_with(' showsHorizontalScrollIndicator="NO" showsVerticalScrollIndicator="NO" bounces="NO" bouncesZoom="NO" '
                                     'canCancelContentTouches="NO" delaysContentTouches="NO"'),
    "table-vertical-indicator-NO": table_with(' showsVerticalScrollIndicator="NO"'),
    "table-multiple-selection": table_with(' allowsMultipleSelection="YES" allowsMultipleSelectionDuringEditing="YES"'),
    "table-multiple-selection-editing": table_with(' allowsMultipleSelectionDuringEditing="YES"'),
    "table-content-insets-NO": table_with(' contentViewInsetsToSafeArea="NO"'),
    "table-keyboard-interactive": table_with(' keyboardDismissMode="interactive"'),
    "table-separator-inset": table_with(extra='                    <inset key="separatorInset" minX="15" minY="0.0" maxX="0.0" maxY="0.0"/>\n'),
    "table-separator-color": table_with(extra='                    ' + gray(0.5, 1).replace("backgroundColor", "separatorColor") + '\n'),
    "table-section-index-background": table_with(extra='                    ' + gray(0.5, 1).replace("backgroundColor", "sectionIndexBackgroundColor") + '\n'),
}
TABLES2["table-everything"] = table_with(' scrollEnabled="NO" indicatorStyle="white" showsHorizontalScrollIndicator="NO" bounces="NO" bouncesZoom="NO" '
    'canCancelContentTouches="NO" delaysContentTouches="NO" keyboardDismissMode="interactive" allowsSelection="NO" allowsSelectionDuringEditing="YES" '
    'allowsMultipleSelection="YES" allowsMultipleSelectionDuringEditing="YES" contentViewInsetsToSafeArea="NO" estimatedSectionHeaderHeight="44"',
    '                    <inset key="separatorInset" minX="15" minY="0.0" maxX="0.0" maxY="0.0"/>\n                    '
    + gray(0.5, 1).replace("backgroundColor", "separatorColor") + '\n                    ' + gray(0.25, 1).replace("backgroundColor", "sectionIndexBackgroundColor") + '\n')
EXPERIMENTS.update(TABLES2)


# Round 75: a constraints mask on a view whose constraints refer to its safe area, as the corpus's
# pocket-casts ShelfActionsViewController has it; the mask's descendants name the safe area.
EXPERIMENTS.update({
    "mask-safe-area": constrained(subview("sss-ss-ss1"), constraint(0, "sss-ss-ss1", "leading", SAFE_GUIDE, "leading", ' constant="20"')
                                  + constraint(1, "sss-ss-ss1", "top", SAFE_GUIDE, "top") + constraint(2, "sss-ss-ss1", "leading", ROOT, "leading", ' constant="8"'),
                                  safe=True).replace('            <point key="canvasLocation"', MASK_VARIATION + '            <point key="canvasLocation"'),
    "mask-safe-area-trailing": constrained(subview("sss-ss-ss1"), constraint(0, SAFE_GUIDE, "trailing", "sss-ss-ss1", "trailing", ' constant="20"')
                                           + constraint(1, "sss-ss-ss1", "top", ROOT, "top") + constraint(2, "sss-ss-ss1", "leading", ROOT, "leading", ' constant="8"'),
                                           safe=True).replace('            <point key="canvasLocation"', MASK_VARIATION + '            <point key="canvasLocation"'),
})


# Round 80: a localizable text view's text of more than 512 characters, as uncloudnotes'
# CreateNoteViewController has it; around the limit, in the element and the attribute.
TEXT_LENGTHS_LPROJ = {f"{name}-lproj": TEXT_LENGTHS[name] for name in ("text-view-length-512", "text-view-length-513", "text-view-length-529",
                                                                        "text-view-length-attribute-529", "label-length-529")}
EXPERIMENTS.update(TEXT_LENGTHS_LPROJ)
# An empty text in an .lproj folder (uncloudnotes' NoteDetailViewController's label).
EXPERIMENTS["label-empty-lproj"] = constrained(label(LABEL_ATTRIBUTES.replace('text="Label"', 'text=""')), "")
EXPERIMENTS["button-empty-title-lproj"] = EXPERIMENTS["button-lproj"].replace('title="Pressed"', 'title=""')
LPROJ_XIBS.update({"label-empty-lproj", "button-empty-title-lproj"})
LPROJ_XIBS.update(TEXT_LENGTHS_LPROJ)


# Round 81: a cell content view's frame as Xcode 8 wrote it, a <frame key="frameInset"> of a width
# and height (uncloudnotes' NotesListViewController); its rect equivalent beside it.
FRAME_INSET_CELL = tvc_cell(1).replace('height="44"/>\n                                <autoresizingMask key="autoresizingMask"/>\n                                <tableViewCellContentView',
                                       'height="80"/>\n                                <autoresizingMask key="autoresizingMask"/>\n                                <tableViewCellContentView')
FRAME_INSETS = {
    "sb-cell-frame-inset": storyboard(tvc_scene(prototypes(FRAME_INSET_CELL.replace('<rect key="frame" x="0.0" y="0.0" width="393" height="44"/>',
                                                                                     '<frame key="frameInset" width="393" height="79.5"/>'))), initial="tvc-aa-aaa"),
    "sb-cell-frame-rect": storyboard(tvc_scene(prototypes(FRAME_INSET_CELL.replace('<rect key="frame" x="0.0" y="0.0" width="393" height="44"/>',
                                                                                    '<rect key="frame" x="0.0" y="0.0" width="393" height="79.5"/>'))), initial="tvc-aa-aaa"),
}
FRAME_INSETS["sb-split-bar-popover"] = storyboard(split_scene(master="nvc-aa-aaa", detail="nvc-bb-aaa"), nav_child("aa", "tvc-aa-aaa"), nav_child("bb", "vc2-aa-aaa"),
                                                 tvc_scene(proto_with_segue("showDetail", "showDetail", "nvc-bb-aaa"), after_view=POPOVER_BAR.replace("vc2-aa-aaa", "vc3-aa-aaa")),
                                                 controller_scene(2, after_view=navigation_item("Detail").replace("nvi-aa-aaa", "nvi-aa-aa2")), controller_scene(3),
                                                 initial="spl-aa-aaa")
FRAME_INSETS["sb-split-bar-action"] = storyboard(split_scene(master="nvc-aa-aaa", detail="vc2-aa-aaa"), nav_child("aa", "vc1-aa-aaa"),
                                                 controller_scene(1, after_view=navigation_item("Notes", '                        <barButtonItem key="rightBarButtonItem" systemItem="add" id="bbi-aa-aa1">\n'
                                                     '                            <connections>\n                                <action selector="add:" destination="vc1-aa-aaa" id="act-aa-aa1"/>\n'
                                                     '                            </connections>\n                        </barButtonItem>\n')),
                                                 controller_scene(2), initial="spl-aa-aaa")
FRAME_INSETS["sb-split-detail-modal"] = storyboard(split_scene(), controller_scene(1),
                                                  controller_scene(2, attributes=' modalPresentationStyle="overCurrentContext"',
                                                                   connections='                        <segue destination="vc3-aa-aaa" kind="show" identifier="Open" id="tsh-aa-aaa"/>\n'),
                                                  controller_scene(3), initial="spl-aa-aaa")
FRAME_INSETS["sb-nav-root-modal"] = storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, attributes=' modalPresentationStyle="formSheet" hidesBottomBarWhenPushed="YES"',
                                                                                              after_view=navigation_item("Root"),
                                                                                              connections='                        <segue destination="vc2-aa-aaa" kind="show" identifier="Open" id="tsh-aa-aaa"/>\n'),
                                               controller_scene(2), initial="nvc-aa-aaa")
FRAME_INSETS["sb-tab-nav-root-modal"] = storyboard(tab_scene(children=("nvc-aa-aaa", "vc2-aa-aaa")), nav_child("aa", "vc1-aa-aaa"),
                                                   controller_scene(1, attributes=' hidesBottomBarWhenPushed="YES"'), controller_scene(2, attributes=' modalTransitionStyle="crossDissolve"'),
                                                   initial="tab-aa-aaa")
FRAME_INSETS["sb-vc-user-label"] = storyboard(controller_scene(1, attributes=' userLabel="Create Note"'), initial="vc1-aa-aaa")
FRAME_INSETS["sb-nav-root-user-label"] = storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, attributes=' storyboardIdentifier="Root" userLabel="Create Note"',
                                                                                                   after_view=navigation_item("Root")), initial="nvc-aa-aaa")
FRAME_INSETS["sb-nav-root-button-show"] = storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, view_extra=segue_button(
    '<segue destination="vc2-aa-aaa" kind="show" identifier="Attach" id="bsg-aa-aaa"/>'), after_view=navigation_item("Root")), controller_scene(2), initial="nvc-aa-aaa")
FRAME_INSETS["sb-nav-root-button-bar-outlet"] = storyboard(controller_scene(3, connections='                        <segue destination="nvc-aa-aaa" kind="presentation" identifier="Open" id="osg-aa-aaa"/>\n'),
    navigation_scene("vc1-aa-aaa"), exit_scene(1, view_extra=segue_button('<segue destination="vc2-aa-aaa" kind="show" identifier="Attach" id="bsg-aa-aaa"/>'),
        after_view=STANDALONE_ITEMS.replace("vc2-aa-aaa", "vc1-aa-aaa") + '                    <connections>\n'
        '                        <outlet property="attach" destination="btn-aa-aa1" id="out-aa-aaa"/>\n                    </connections>\n'),
    controller_scene(2), initial="vc3-aa-aaa")
CELL_SEGUES.update(FRAME_INSETS)
STORYBOARDS.update(FRAME_INSETS)


# Round 82: stack views' size-class variations of spacing, axis and distribution, as wikipedia's
# WelcomeContainerViewController, InsertMediaImageInfoView and WMFEditorToolbarExpandingView have them.
def stack_variation(variations, attributes=STACK_ATTRIBUTES + ' spacing="8"'):
    return constrained(stack(attributes, extra="".join(f'<variation key="{key}"{values}/>\n' for key, values in variations)), "")


STACK_VARIATIONS = {
    "stack-vary-spacing": stack_variation([("heightClass=compact", ' spacing="1"')]),
    "stack-vary-spacing-default": stack_variation([("heightClass=compact", ' spacing="1"')], STACK_ATTRIBUTES),
    "stack-vary-axis-spacing": stack_variation([("heightClass=compact", ' axis="horizontal" spacing="20"')], STACK_ATTRIBUTES + ' axis="vertical" spacing="8"'),
    "stack-vary-axis": stack_variation([("heightClass=compact", ' axis="vertical"')]),
    "stack-vary-distribution-spacing": stack_variation([("heightClass=compact-widthClass=compact", ' distribution="fillEqually" spacing="20"'),
                                                        ("heightClass=compact-widthClass=regular", ' distribution="fillEqually" spacing="20"'),
                                                        ("heightClass=regular-widthClass=regular", ' distribution="fillEqually" spacing="20"')]),
    "stack-vary-spacing-two": stack_variation([("widthClass=regular", ' spacing="30"'), ("heightClass=compact", ' spacing="1"')]),
}
EXPERIMENTS.update(STACK_VARIATIONS)


# Round 83: page view controllers, as wikipedia's DescriptionWelcome and nextcloud's NCIntro
# storyboards have them: scroll or page curl, either orientation, spacing, custom classes.
def page_scene(attributes=' transitionStyle="scroll" navigationOrientation="horizontal" spineLocation="none"', extra=""):
    return ('        <scene sceneID="pgs-aa-aaa">\n            <objects>\n'
            f'                <pageViewController{extra} autoresizesArchivedViewToFullSize="NO"{attributes} id="pvc-aa-aaa" sceneMemberID="viewController"/>\n'
            '                <placeholder placeholderIdentifier="IBFirstResponder" id="pfr-aa-aaa" sceneMemberID="firstResponder"/>\n'
            '            </objects>\n            <point key="canvasLocation" x="0" y="0"/>\n        </scene>\n')


PAGES = {
    "sb-page-scroll": storyboard(page_scene(), initial="pvc-aa-aaa"),
    "sb-page-identifier": storyboard(controller_scene(1), page_scene(extra=' storyboardIdentifier="Pages"'), initial="vc1-aa-aaa"),
    "sb-page-vertical": storyboard(page_scene(' transitionStyle="scroll" navigationOrientation="vertical" spineLocation="none"'), initial="pvc-aa-aaa"),
    "sb-page-spacing": storyboard(page_scene(' transitionStyle="scroll" pageSpacing="16" navigationOrientation="horizontal" spineLocation="none"'), initial="pvc-aa-aaa"),
    "sb-page-curl": storyboard(page_scene(' transitionStyle="pageCurl" navigationOrientation="horizontal" spineLocation="min"'), initial="pvc-aa-aaa"),
    "sb-page-curl-mid": storyboard(page_scene(' transitionStyle="pageCurl" navigationOrientation="vertical" spineLocation="mid"'), initial="pvc-aa-aaa"),
    "sb-page-custom": storyboard(page_scene(extra=' storyboardIdentifier="Pages"').replace('id="pvc-aa-aaa"', 'id="pvc-aa-aaa" customClass="Pages" customModule="T" customModuleProvider="target"'),
                                 initial="pvc-aa-aaa"),
    "sb-page-presented": storyboard(controller_scene(1, connections='                        <segue destination="pvc-aa-aaa" kind="presentation" identifier="Pages" id="psg-aa-aaa"/>\n'),
                                    page_scene(), initial="vc1-aa-aaa"),
}
CELL_SEGUES.update(PAGES)
STORYBOARDS.update(PAGES)


# Round 84: storyboard container views and their embed segues, as wikipedia's DescriptionWelcome,
# kickstarter's Discovery and nextcloud's NCShare storyboards have them.
def container_view(segue, number=1, frame=(20, 100, 200, 300)):
    x, y, w, h = frame
    return ('                        <subviews>\n'
            f'                            <containerView opaque="NO" contentMode="scaleToFill" id="cnt-aa-aa{number}">\n'
            f'                                <rect key="frame" x="{x}" y="{y}" width="{w}" height="{h}"/>\n'
            '                                <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>\n'
            f'                                <connections>\n                                    {segue}\n                                </connections>\n'
            '                            </containerView>\n                        </subviews>\n')


EMBED = '<segue destination="vc2-aa-aaa" kind="embed" id="emb-aa-aaa"/>'
EMBEDS = {
    "sb-embed": storyboard(controller_scene(1, view_extra=container_view(EMBED)), controller_scene(2), initial="vc1-aa-aaa"),
    "sb-embed-named": storyboard(controller_scene(1, view_extra=container_view(EMBED.replace('kind="embed"', 'kind="embed" identifier="Child"'))),
                                 controller_scene(2), initial="vc1-aa-aaa"),
    "sb-embed-two": storyboard(controller_scene(1, view_extra=container_view(EMBED).replace("                        </subviews>\n", "")
                                                + container_view(EMBED.replace("vc2", "vc3").replace("emb-aa-aaa", "emb-aa-aa2"), 2, (20, 420, 200, 100))
                                                .replace("                        <subviews>\n", "")),
                               controller_scene(2), controller_scene(3), initial="vc1-aa-aaa"),
    "sb-embed-nav": storyboard(controller_scene(1, view_extra=container_view(EMBED.replace("vc2-aa-aaa", "nvc-aa-aaa"))), navigation_scene("vc2-aa-aaa"),
                               controller_scene(2, after_view=navigation_item("Child")), initial="vc1-aa-aaa"),
    "sb-embed-page": storyboard(controller_scene(1, view_extra=container_view(EMBED.replace("vc2-aa-aaa", "pvc-aa-aaa"))), page_scene(), initial="vc1-aa-aaa"),
    "sb-embed-outlet": storyboard(controller_scene(1, view_extra=container_view(EMBED),
                                                   connections='                        <outlet property="box" destination="cnt-aa-aa1" id="out-aa-aaa"/>\n'),
                                  controller_scene(2), initial="vc1-aa-aaa"),
    "sb-embed-identified-child": storyboard(controller_scene(1, view_extra=container_view(EMBED)), controller_scene(2, attributes=' storyboardIdentifier="Child"'),
                                            initial="vc1-aa-aaa"),
}
EMBEDS["sb-container-empty"] = storyboard(controller_scene(1, view_extra=container_view(EMBED).replace(
    "                                <connections>\n                                    " + EMBED + "\n                                </connections>\n", "")), initial="vc1-aa-aaa")
CELL_SEGUES.update(EMBEDS)
STORYBOARDS.update(EMBEDS)


# Round 85: a cell's background color beside its separator inset, as cwa's ErrorReportHistoryCell
# has them, the order of their keys.
CELL_BG = '            <color key="backgroundColor" white="0.0" alpha="0.0" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>\n'
CELL_SEP = '            <inset key="separatorInset" minX="15" minY="0.0" maxX="0.0" maxY="0.0"/>\n'
CELL_ORDERS = {
    "cell-bg-sep": cell_xib(cell_extra=CELL_BG + CELL_SEP),
    "cell-bg-sep-none": cell_xib(cell_extra=CELL_BG + CELL_SEP).replace('selectionStyle="default"', 'selectionStyle="none"'),
    "cell-bg-sep-preserve": cell_xib(cell_extra=CELL_BG + CELL_SEP).replace('<tableViewCell ', '<tableViewCell preservesSuperviewLayoutMargins="YES" '),
}
EXPERIMENTS.update(CELL_ORDERS)
# An info button's hugging, as cwa's HomeLinkCardView has it.
INFO_BUTTON = ('<button opaque="NO" contentMode="scaleToFill" horizontalHuggingPriority="750" verticalHuggingPriority="750" contentHorizontalAlignment="center" '
               'contentVerticalAlignment="center" buttonType="infoLight" showsTouchWhenHighlighted="YES" lineBreakMode="middleTruncation" id="bbb-bb-bb1">\n'
               '<rect key="frame" x="20" y="40" width="22" height="22"/>\n</button>\n')
EXPERIMENTS["button-info-hugging-750"] = constrained(INFO_BUTTON, "")
EXPERIMENTS["button-info-hugging-250"] = constrained(INFO_BUTTON.replace('horizontalHuggingPriority="750" verticalHuggingPriority="750" ', ''), "")


# Round 86: Xcode 5's push and modal segues and custom segues, as gomap's and moonlight's
# storyboards have them, from controllers, cells and buttons.
LEGACY_SEGUES = {
    "sb-segue-push": storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, connections='                        <segue destination="vc2-aa-aaa" kind="push" identifier="Next" id="lsg-aa-aaa"/>\n'),
                                controller_scene(2), initial="nvc-aa-aaa"),
    "sb-segue-modal": storyboard(controller_scene(1, connections='                        <segue destination="vc2-aa-aaa" kind="modal" identifier="Next" id="lsg-aa-aaa"/>\n'),
                                 controller_scene(2), initial="vc1-aa-aaa"),
    "sb-button-push": storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, view_extra=segue_button('<segue destination="vc2-aa-aaa" kind="push" id="bsg-aa-aaa"/>')),
                                 controller_scene(2), initial="nvc-aa-aaa"),
    "sb-button-modal": storyboard(controller_scene(1, view_extra=segue_button('<segue destination="vc2-aa-aaa" kind="modal" id="bsg-aa-aaa"/>')),
                                  controller_scene(2), initial="vc1-aa-aaa"),
    "sb-cellseg-prototype-push": storyboard(navigation_scene("tvc-aa-aaa"), tvc_scene(proto_with_segue("push")), controller_scene(2), initial="nvc-aa-aaa"),
    "sb-segue-custom": storyboard(controller_scene(1, connections='                        <segue destination="vc2-aa-aaa" kind="custom" identifier="Next" '
                                                                  'customClass="Reveal" customModule="T" customModuleProvider="target" id="lsg-aa-aaa"/>\n'),
                                  controller_scene(2), initial="vc1-aa-aaa"),
    "sb-segue-custom-no-module": storyboard(controller_scene(1, connections='                        <segue destination="vc2-aa-aaa" kind="custom" identifier="Next" '
                                                                            'customClass="SWRevealViewControllerSegueSetController" id="lsg-aa-aaa"/>\n'),
                                            controller_scene(2), initial="vc1-aa-aaa"),
}
LEGACY_SEGUES["sb-segue-push-two"] = storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, connections=
    '                        <segue destination="vc2-aa-aaa" kind="push" identifier="B" id="zzz-aa-aaa"/>\n'
    '                        <segue destination="vc2-aa-aaa" kind="push" identifier="A" id="aaa-zz-zzz"/>\n'), controller_scene(2), initial="nvc-aa-aaa")
LEGACY_SEGUES["sb-segue-modal-push"] = storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, connections=
    '                        <segue destination="vc2-aa-aaa" kind="modal" identifier="B" id="aaa-zz-zzz"/>\n'
    '                        <segue destination="vc2-aa-aaa" kind="push" identifier="A" id="zzz-aa-aaa"/>\n'), controller_scene(2), initial="nvc-aa-aaa")
LEGACY_SEGUES["sb-segue-push-three"] = storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, connections="".join(
    f'                        <segue destination="vc2-aa-aaa" kind="push" identifier="{i}" id="{i}"/>\n' for i in ("Mmm-aa-aaa", "zzz-aa-aaa", "aaa-zz-zzz", "Qx4-pp-k2L"))),
    controller_scene(2), initial="nvc-aa-aaa")
CELL_SEGUES.update(LEGACY_SEGUES)
STORYBOARDS.update(LEGACY_SEGUES)


# Round 87: table and collection view controllers without a safe area guide in a document using
# safe areas, as kickstarter's, netnewswire's and nextcloud's settings storyboards have them.
SAFE_TVCS = {
    "sb-tvc-safe-areas-no-guide": storyboard(tvc_scene(prototypes(tvc_cell(1))), initial="tvc-aa-aaa", attributes=' useSafeAreas="YES"',
                                             capabilities=SAFE_AREA_CAPABILITY),
    "sb-tvc-safe-areas-static": storyboard(tvc_scene(STATIC.format(header="", cells=tvc_cell(1, y=0, attributes="")), data_mode="static"),
                                           initial="tvc-aa-aaa", attributes=' useSafeAreas="YES"', capabilities=SAFE_AREA_CAPABILITY),
    "sb-cvc-safe-areas-no-guide": storyboard(cvc_scene(), initial="cvc-aa-aaa", attributes=' useSafeAreas="YES"', capabilities=SAFE_AREA_CAPABILITY),
}
def freeform_scene(size, frame):
    return controller_scene(1, after_view=f'                    <size key="freeformSize" width="{size[0]}" height="{size[1]}"/>\n').replace(
        '<rect key="frame" x="0.0" y="0.0" width="393" height="852"/>', f'<rect key="frame" x="0.0" y="0.0" width="{frame[0]}" height="{frame[1]}"/>')


SAFE_TVCS.update({
    "sb-freeform-size-only": storyboard(freeform_scene((375, 60), (375, 60)), initial="vc1-aa-aaa"),
    "sb-freeform-size-only-device-frame": storyboard(freeform_scene((375, 60), (393, 852)), initial="vc1-aa-aaa"),
    "sb-embed-freeform": storyboard(controller_scene(1, view_extra=container_view(EMBED)),
                                    freeform_scene((145, 145), (145, 145)).replace("vc1-aa-aaa", "vc2-aa-aaa").replace("vw1-aa-aaa", "vw2-aa-aaa")
                                    .replace("sc1-aa-aaa", "sc2-aa-aaa").replace("fr1-aa-aaa", "fr2-aa-aaa"), initial="vc1-aa-aaa"),
})
CELL_SEGUES.update(SAFE_TVCS)
STORYBOARDS.update(SAFE_TVCS)


# Round 88: edges for extended layout, as gomap's and nextcloud's share extensions and
# kickstarter's BackerDashboard have them.
EDGES = {
    "sb-edges-none": storyboard(controller_scene(1, after_view='                    <extendedEdge key="edgesForExtendedLayout"/>\n'), initial="vc1-aa-aaa"),
    "sb-edges-bottom": storyboard(controller_scene(1, after_view='                    <extendedEdge key="edgesForExtendedLayout" bottom="YES"/>\n'), initial="vc1-aa-aaa"),
    "sb-edges-top-left": storyboard(controller_scene(1, after_view='                    <extendedEdge key="edgesForExtendedLayout" top="YES" left="YES"/>\n'), initial="vc1-aa-aaa"),
    "sb-edges-none-settings": storyboard(controller_scene(1, attributes=' modalPresentationStyle="formSheet" extendedLayoutIncludesOpaqueBars="YES"',
                                                          after_view='                    <extendedEdge key="edgesForExtendedLayout"/>\n'), initial="vc1-aa-aaa"),
    "sb-edges-nav-root": storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, after_view='                    <extendedEdge key="edgesForExtendedLayout"/>\n'
                                                                                               + navigation_item("Root")), initial="nvc-aa-aaa"),
}
EDGES["sb-edges-hides-bottom"] = storyboard(controller_scene(1, attributes=' hidesBottomBarWhenPushed="YES" automaticallyAdjustsScrollViewInsets="NO"',
                                                             after_view='                    <extendedEdge key="edgesForExtendedLayout" bottom="YES"/>\n'), initial="vc1-aa-aaa")
CELL_SEGUES.update(EDGES)
STORYBOARDS.update(EDGES)


# Round 89: navigation items' bar button items as the corpus has them: back items, the done style,
# more system items, image items.
def nav_items(items):
    return storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, after_view=navigation_item("Root", items)), initial="nvc-aa-aaa")


BAR_ITEMS = {
    "sb-bar-back-title": nav_items('                        <barButtonItem key="backBarButtonItem" title="Back" id="bbi-aa-aa3"/>\n'),
    "sb-bar-done-style": nav_items('                        <barButtonItem key="rightBarButtonItem" style="done" systemItem="done" id="bbi-aa-aa1"/>\n'),
    "sb-bar-done-style-disabled": nav_items('                        <barButtonItem key="rightBarButtonItem" enabled="NO" style="done" systemItem="done" id="bbi-aa-aa1"/>\n'),
    "sb-bar-image": nav_items('                        <barButtonItem key="rightBarButtonItem" title="Item" image="square" catalog="system" id="bbi-aa-aa1"/>\n').replace(
        "    </scenes>\n", "    </scenes>\n    <resources>\n        <image name=\"square\" catalog=\"system\" width=\"128\" height=\"114\"/>\n    </resources>\n"),
    "sb-bar-title-done": nav_items('                        <barButtonItem key="rightBarButtonItem" title="Save" style="done" id="bbi-aa-aa1"/>\n'),
}
for system in ("save", "edit", "action", "bookmarks", "trash", "refresh", "compose", "search", "play", "camera", "reply", "organize", "stop"):
    BAR_ITEMS[f"sb-bar-system-{system}"] = nav_items(f'                        <barButtonItem key="rightBarButtonItem" systemItem="{system}" id="bbi-aa-aa1"/>\n')
CELL_SEGUES.update(BAR_ITEMS)
STORYBOARDS.update(BAR_ITEMS)


# Round 90: the extension templates' controller (pocket-casts' notification content, wikipedia's
# widget): a view simulating the notification center, nil simulated bars, a freeform size.
EXTENSION_METRICS = ('                    <nil key="simulatedStatusBarMetrics"/>\n                    <nil key="simulatedTopBarMetrics"/>\n'
                     '                    <nil key="simulatedBottomBarMetrics"/>\n'
                     '                    <freeformSimulatedSizeMetrics key="simulatedDestinationMetrics"/>\n'
                     '                    <size key="freeformSize" width="320" height="200"/>\n')
def extension_scene(context=' simulatedAppContext="notificationCenter"'):
    return scene(controller="vc1-aa-aaa", view_id="vw1-aa-aaa", scene_id="sc1-aa-aaa", responder="fr1-aa-aaa", guides=LAYOUT_GUIDES,
                 view_attributes=context).replace('width="393" height="852"', 'width="320" height="200"').replace(
        "                    </view>\n                </viewController>\n", "                    </view>\n" + EXTENSION_METRICS + "                </viewController>\n")


APP_CONTEXTS = {
    "sb-app-context": storyboard(extension_scene(), initial="vc1-aa-aaa"),
    "sb-app-context-plain": storyboard(extension_scene(""), initial="vc1-aa-aaa"),
}
APP_CONTEXTS.update({
    "sb-popover-content-size": storyboard(controller_scene(1, after_view='                    <value key="contentSizeForViewInPopover" type="size" width="300" height="300"/>\n'),
                                          initial="vc1-aa-aaa"),
    "sb-vc-no-view": storyboard('        <scene sceneID="sc1-aa-aaa">\n            <objects>\n'
                                '                <viewController title="Image" id="vc1-aa-aaa" sceneMemberID="viewController">\n'
                                '                    <freeformSimulatedSizeMetrics key="simulatedDestinationMetrics"/>\n'
                                '                    <size key="freeformSize" width="320" height="528"/>\n                </viewController>\n'
                                '                <placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>\n'
                                '            </objects>\n            <point key="canvasLocation" x="0" y="0"/>\n        </scene>\n', initial="vc1-aa-aaa"),
    "sb-vc-no-view-plain": storyboard('        <scene sceneID="sc1-aa-aaa">\n            <objects>\n'
                                      '                <viewController id="vc1-aa-aaa" sceneMemberID="viewController"/>\n'
                                      '                <placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa" sceneMemberID="firstResponder"/>\n'
                                      '            </objects>\n            <point key="canvasLocation" x="0" y="0"/>\n        </scene>\n', initial="vc1-aa-aaa"),
})
APP_CONTEXTS["sb-popover-content-size-all"] = storyboard(controller_scene(1, attributes=' storyboardIdentifier="Share" modalPresentationStyle="formSheet"',
    after_view='                    <extendedEdge key="edgesForExtendedLayout"/>\n'
               '                    <value key="contentSizeForViewInPopover" type="size" width="300" height="300"/>\n',
    connections='                        <segue destination="vc2-aa-aaa" kind="show" identifier="Next" id="csg-aa-aa9"/>\n'), controller_scene(2), initial="vc1-aa-aaa")
CELL_SEGUES.update(APP_CONTEXTS)
STORYBOARDS.update(APP_CONTEXTS)


# Round 91: cells' accessory segues beside selection segues: their numbering in a cell and across
# cells, as gomap's Display storyboard and kickstarter's have them.
def both_segues(number, accessory_first=False, y=28):
    selection = f'                                    <segue destination="vc2-aa-aaa" kind="show" identifier="Pick{number}" id="cs{number}-aa-aaa"/>\n'
    accessory = ACCESSORY_SEGUE.replace('identifier="Details"', f'identifier="Details{number}"').replace('id="asg-aa-aaa"', f'id="as{number}-aa-aaa"')
    body = accessory + selection if accessory_first else selection + accessory
    return with_cell_connections(tvc_cell(number, y=y, attributes=ACCESSORY.replace('reuseIdentifier="Cell"', f'reuseIdentifier="Cell{number}"')),
                                 '                                <connections>\n' + body + '                                </connections>\n')


ACCESSORY_ROUND = {
    "sb-cellseg-accessory-first": storyboard(tvc_scene(prototypes(both_segues(1, accessory_first=True))), controller_scene(2), initial="tvc-aa-aaa"),
    "sb-cellseg-accessory-two-cells": storyboard(tvc_scene(prototypes(both_segues(1) + both_segues(2, y=72))), controller_scene(2), initial="tvc-aa-aaa"),
    "sb-cellseg-accessory-static-both": storyboard(tvc_scene(STATIC.format(header="", cells=both_segues(1, y=0).replace(' reuseIdentifier="Cell1"', '')), data_mode="static"),
                                                   controller_scene(2), initial="tvc-aa-aaa"),
}
ACCESSORY_ROUND["sb-cellseg-prototypes-reversed-ids"] = storyboard(tvc_scene(prototypes(
    both_segues(1).replace('reuseIdentifier="Cell1"', 'reuseIdentifier="Zeta"') + both_segues(2, y=72).replace('reuseIdentifier="Cell2"', 'reuseIdentifier="Alpha"'))),
    controller_scene(2), initial="tvc-aa-aaa")
ACCESSORY_ROUND["sb-cellseg-static-two-both"] = storyboard(tvc_scene(STATIC.format(header="", cells=both_segues(1, y=0).replace(' reuseIdentifier="Cell1"', '')
                                                                                 + both_segues(2, y=44).replace(' reuseIdentifier="Cell2"', '')), data_mode="static"),
                                                     controller_scene(2), initial="tvc-aa-aaa")
CELL_SEGUES.update(ACCESSORY_ROUND)
STORYBOARDS.update(ACCESSORY_ROUND)


# Round 92: controllers no entry point, identifier or segue reaches, which ibtool skips with a
# warning naming them, as nextcloud's NCLogin, kickstarter's Help and flutter's storyboards have them.
UNREACHED = {
    "sb-unreached-vc": storyboard(controller_scene(1), controller_scene(2), initial="vc1-aa-aaa"),
    "sb-unreached-nav": storyboard(controller_scene(1), navigation_scene("vc2-aa-aaa"), controller_scene(2), initial="vc1-aa-aaa"),
    "sb-unreached-title": storyboard(controller_scene(1), controller_scene(2, attributes=' title="Settings"'), initial="vc1-aa-aaa"),
    "sb-unreached-custom": storyboard(controller_scene(1), controller_scene(2, attributes=' customClass="LoginViewController" customModule="T" customModuleProvider="target"'),
                                      initial="vc1-aa-aaa"),
    "sb-unreached-label": storyboard(controller_scene(1), controller_scene(2, attributes=' userLabel="Login"'), initial="vc1-aa-aaa"),
    "sb-unreached-tvc": storyboard(controller_scene(1), tvc_scene(prototypes(tvc_cell(1))), initial="vc1-aa-aaa"),
    "sb-unreached-three": storyboard(controller_scene(1), controller_scene(2), controller_scene(3, attributes=' title="Third"'), controller_scene(4, attributes=' customClass="Fourth"'),
                                     initial="vc1-aa-aaa"),
}
CELL_SEGUES.update(UNREACHED)
STORYBOARDS.update(UNREACHED)


# Round 93: search bars, as gomap's, nextcloud's and wikipedia's documents have them.
def search_bar(attributes="", children='<textInputTraits key="textInputTraits"/>\n'):
    return (f'<searchBar contentMode="redraw"{attributes} translatesAutoresizingMaskIntoConstraints="NO" id="sbr-aa-aa1">\n'
            '<rect key="frame" x="0.0" y="40" width="393" height="56"/>\n' + children + '</searchBar>\n')


SEARCH_BARS = {
    "search-bar": constrained(search_bar(), ""),
    "search-bar-minimal": constrained(search_bar(' searchBarStyle="minimal"'), ""),
    "search-bar-placeholder": constrained(search_bar(' searchBarStyle="minimal" placeholder="Search for a place or address"'), ""),
    "search-bar-traits": constrained(search_bar(' placeholder="Niagara Falls"', '<textInputTraits key="textInputTraits" autocorrectionType="no"/>\n'), ""),
    "search-bar-opaque-hugging": constrained(search_bar(' opaque="NO" horizontalHuggingPriority="249" searchBarStyle="minimal"'), ""),
    "search-bar-text": constrained(search_bar(' text="" placeholder="Repository search"'), ""),
}
EXPERIMENTS.update(SEARCH_BARS)


# Round 94: a text style IB does not offer, as pocket-casts' ProfileViewController has it.
EXPERIMENTS["label-style-subheadline"] = constrained(label(font='<fontDescription key="fontDescription" style="UICTFontTextStyleSubheadline"/>'), "")
EXPERIMENTS["label-style-made-up"] = constrained(label(font='<fontDescription key="fontDescription" style="UICTFontTextStyleMadeUp"/>'), "")
EXPERIMENTS["label-style-subhead"] = constrained(label(font='<fontDescription key="fontDescription" style="UICTFontTextStyleSubhead"/>'), "")


# Round 95: outlet collections of several names from File's Owner and a view together (the corpus's
# wikipedia DescriptionHelpViewController, EditLinkViewController, EditSaveViewController): where the
# view's collection falls among File's Owner's.
def collection_to(prop, number, destination):
    return owner_outlet(prop, number, "outletCollection", COLLECTION).replace('destination="-1"', f'destination="{destination}"')


def owner_collections(names, numbers=None):
    return "".join(collection_to(name, number, f"sub-vi-ew{1 + k % 2}") for k, (name, number) in enumerate(zip(names, numbers or range(1, len(names) + 1))))


MIXED_COLLECTIONS = {
    "oc-mix-a": with_outlets(owner_collections(["zeta", "alpha"]), collection_to("items", 9, "sub-vi-ew1")),
    "oc-mix-b": with_outlets(owner_collections(["alpha", "zeta"]), collection_to("items", 9, "sub-vi-ew1")),
    "oc-mix-c": with_outlets(owner_collections(["pa", "pb", "pc", "pd"]), collection_to("items", 9, "sub-vi-ew1")),
    "oc-mix-d": with_outlets(owner_collections(["pa", "pb", "pc", "pd"]), collection_to("items", 0, "sub-vi-ew1")),
    "oc-mix-e": with_outlets(owner_collections(["pa", "pb", "pc", "pd"]), collection_to("aaa", 9, "sub-vi-ew1")),
    "oc-mix-f": with_outlets(owner_collections(["pa", "pb", "pc", "pd"], [4, 3, 2, 1]), collection_to("items", 9, "sub-vi-ew1")),
    "oc-mix-g": with_outlets(owner_collections(["pa", "pb", "pc", "pd"]), collection_to("zzz", 9, "sub-vi-ew2")),
    "oc-mix-h": with_outlets(owner_collections(["pa", "pb", "pc", "pd"]), collection_to("zz", 9, "sub-vi-ew1") + collection_to("aa", 10, "sub-vi-ew2")),
    "oc-mix-i": with_outlets("", collection_to("zeta", 9, "sub-vi-ew1") + collection_to("alpha", 10, "sub-vi-ew2")),
    "oc-mix-j": with_outlets(owner_collections(["pd", "pc", "pb", "pa"]), collection_to("pe", 9, "sub-vi-ew1")),
    "oc-mix-k": with_outlets(owner_collections(["pd", "pc", "pb", "pa"]), collection_to("pbb", 9, "sub-vi-ew1")),
    "oc-mix-l": with_outlets(owner_collections(["pa", "pb", "pc", "pd"]), collection_to("pcc", 9, "sub-vi-ew1")).replace(
        '                </view>\n                <view', '                    <connections>\n' + collection_to("pbb", 10, "sub-vi-ew2")
        + '                    </connections>\n                </view>\n                <view', 1),
    "oc-mix-m": with_outlets(owner_collections(["pa", "pb", "pc", "pd", "pe", "pf", "pg"]), collection_to("pdd", 9, "sub-vi-ew1")
                             + collection_to("pbb", 10, "sub-vi-ew2") + collection_to("pff", 11, "sub-vi-ew1")),
    "oc-names-seven": with_outlets(owner_collections(["q", "b", "x", "b", "a", "m", "q", "z", "c"])),
    "oc-names-root-seven": with_outlets("", owner_collections(["q", "b", "x", "b", "a", "m", "q", "z", "c"], range(11, 20))),
}
EXPERIMENTS.update(MIXED_COLLECTIONS)


# Round 96: storyboard references (`<viewControllerPlaceholder>`) as segue and tab destinations, as
# the corpus's gomap and nextcloud storyboards have them.
def reference_scene(number, attributes=' storyboardName="Other" referencedIdentifier="Ref"', item=False):
    element = f'                <viewControllerPlaceholder{attributes} id="ref-aa-aa{number}" sceneMemberID="viewController"'
    element += (f'>\n                    <navigationItem key="navigationItem" id="rni-aa-aa{number}"/>\n                </viewControllerPlaceholder>\n'
                if item else '/>\n')
    return (f'        <scene sceneID="rsc-aa-aa{number}">\n            <objects>\n{element}'
            f'                <placeholder placeholderIdentifier="IBFirstResponder" id="rfr-aa-aa{number}" sceneMemberID="firstResponder"/>\n'
            f'            </objects>\n            <point key="canvasLocation" x="{400 * number}" y="400"/>\n        </scene>\n')


def to_reference(kind, identifier="", number=1):
    return f'<segue destination="ref-aa-aa{number}" kind="{kind}"{identifier} id="rsg-aa-aa{number}"/>'


REFERENCES = {
    "sb-ref-show": storyboard(controller_scene(1, view_extra=segue_button(to_reference("show"))), reference_scene(1), initial="vc1-aa-aaa"),
    "sb-ref-show-name-only": storyboard(controller_scene(1, view_extra=segue_button(to_reference("show"))),
                                        reference_scene(1, ' storyboardName="Other"'), initial="vc1-aa-aaa"),
    "sb-ref-present-named": storyboard(controller_scene(1, view_extra=segue_button(to_reference("presentation", ' identifier="Go"'))),
                                       reference_scene(1), initial="vc1-aa-aaa"),
    "sb-ref-modal": storyboard(controller_scene(1, view_extra=segue_button(to_reference("modal", ' identifier="Go"'))), reference_scene(1, item=True),
                               initial="vc1-aa-aaa"),
    "sb-ref-show-item": storyboard(controller_scene(1, view_extra=segue_button(to_reference("show"))), reference_scene(1, item=True), initial="vc1-aa-aaa"),
    "sb-ref-push": storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, view_extra=segue_button(to_reference("push", ' identifier="Go"'))),
                              reference_scene(1, item=True), initial="nvc-aa-aaa"),
    "sb-ref-controller-segue": storyboard(controller_scene(1, connections="                        " + to_reference("show", ' identifier="Go"') + "\n"),
                                          reference_scene(1), initial="vc1-aa-aaa"),
    "sb-ref-tab": storyboard(tab_scene(("vc1-aa-aaa", "ref-aa-aa1")), controller_scene(1), reference_scene(1, item=True), initial="tab-aa-aaa"),
    "sb-ref-tab-two": storyboard(tab_scene(("ref-aa-aa1", "ref-aa-aa2")), reference_scene(1, item=True),
                                 reference_scene(2, ' storyboardName="Third" referencedIdentifier="Three"', item=True), initial="tab-aa-aaa"),
    "sb-ref-unreached": storyboard(controller_scene(1), reference_scene(1), initial="vc1-aa-aaa"),
    "sb-ref-nav-root": storyboard(navigation_scene("ref-aa-aa1"), reference_scene(1, item=True), initial="nvc-aa-aaa"),
    "sb-ref-tab-nav-root": storyboard(tab_scene(children=("nvc-aa-aaa", "vc2-aa-aaa")), nav_child("aa", "ref-aa-aa1", tab_item(1, ' title="Files"')),
                                      reference_scene(1, item=True), controller_scene(2), initial="tab-aa-aaa"),
    "sb-ref-cell-push": storyboard(navigation_scene("tvc-aa-aaa"), tvc_scene(proto_with_segue("push", destination="ref-aa-aa1")), reference_scene(1, item=True),
                                   initial="nvc-aa-aaa"),
    "sb-ref-cell-show": storyboard(tvc_scene(proto_with_segue("show", "Open", destination="ref-aa-aa1")), reference_scene(1), initial="tvc-aa-aaa"),
    "sb-ref-no-entry": storyboard(controller_scene(1, ' storyboardIdentifier="First"', view_extra=segue_button(to_reference("show"))), reference_scene(1),
                                  initial=None),
}
STORYBOARDS.update(REFERENCES)



# Round 97: a view's content stretch (`<rect key="contentStretch">`) and a table view cell's
# clearsContextBeforeDrawing, as older documents have them.
def stretch(x, y, w, h):
    return f'                    <rect key="contentStretch" x="{x}" y="{y}" width="{w}" height="{h}"/>\n'


def stretched(tag, rect, attributes=""):
    return subview("sub-vi-ew1", (10, 20, 100, 50), tag, attributes).replace(
        '                    <rect key="frame" x="10" y="20" width="100" height="50"/>\n',
        '                    <rect key="frame" x="10" y="20" width="100" height="50"/>\n' + rect)


STRETCH = {
    "view-stretch": constrained(stretched("view", stretch("0.10000000000000001", "0.20000000000000001", "0.5", "0.69999999999999996")), ""),
    "view-stretch-center": constrained(stretched("view", stretch("0.5", "0.5", "0.0", "0.0")), ""),
    "view-stretch-default": constrained(stretched("view", stretch("0.0", "0.0", "1", "1")), ""),
    "view-stretch-x": constrained(stretched("view", stretch("0.25", "0.0", "1", "1")), ""),
    "image-view-stretch": constrained(stretched("imageView", stretch("0.5", "0.5", "0.0", "0.0")), ""),
    "label-stretch": constrained(stretched("label", stretch("0.5", "0.5", "0.0", "0.0"), ' opaque="NO" userInteractionEnabled="NO" text="Label"').replace(
        "                </label>\n", '                    <fontDescription key="fontDescription" type="system" pointSize="17"/>\n'
        '                    <nil key="textColor"/>\n                    <nil key="highlightedColor"/>\n                </label>\n'), ""),
    "button-stretch": constrained(stretched("button", stretch("0.5", "0.5", "0.0", "0.0"), ' opaque="NO" contentHorizontalAlignment="center" contentVerticalAlignment="center" buttonType="system" lineBreakMode="middleTruncation"').replace(
        "                </button>\n", '                    <state key="normal" title="Go"/>\n                </button>\n'), ""),
    "cell-clears-no": cell_xib(' clearsContextBeforeDrawing="NO"'),
    "cell-clears-yes": cell_xib(' clearsContextBeforeDrawing="YES"'),
    "cell-clears-no-content": cell_xib(' clearsContextBeforeDrawing="NO"', content_attributes=' clearsContextBeforeDrawing="NO"'),
    "cell-content-clears-no": cell_xib("", content_attributes=' clearsContextBeforeDrawing="NO"'),
    "cell-clears-no-opaque": cell_xib(' clearsContextBeforeDrawing="NO" opaque="NO"'),
    "cell-stretch": cell_xib(' clearsContextBeforeDrawing="NO"', cell_extra=stretch("0.0", "0.0", "1", "1").replace("                    ", "            ")),
    "view-stretch-flags": constrained(stretched("view", stretch("0.5", "0.5", "0.0", "0.0"),
                                                ' clipsSubviews="YES" clearsContextBeforeDrawing="NO" contentMode="center" tag="3" hidden="YES"'), ""),
    "view-stretch-alpha": constrained(stretched("view", stretch("0.5", "0.5", "0.0", "0.0"), ' alpha="0.5" contentMode="center" clipsSubviews="YES"'), ""),
    "view-stretch-third": constrained(stretched("view", stretch("0.33333333333333331", "0.0", "0.33333333333333337", "1")), ""),
    "cell-stretch-center": cell_xib(' clearsContextBeforeDrawing="NO"', cell_extra=stretch("0.5", "0.5", "0.0", "0.0").replace("                    ", "            ")),
}
EXPERIMENTS.update(STRETCH)



# Round 98: constraints' identifiers beside outlets and other strings of the same text: which
# strings a nib shares.
def pinned_views(owner_outlets="", identifiers=("pin", None, None, None), sub_attributes="", sub_extra=""):
    sub = subview("sub-vi-ew1", (10, 20, 100, 50), attributes=sub_attributes).replace("                </view>\n", sub_extra + "                </view>\n")
    attributes = [("leading", "leading"), ("trailing", "trailing"), ("top", "top"), ("bottom", "bottom")]
    constraints = "".join(constraint(k, "sub-vi-ew1" if k % 2 == 0 else ROOT, a, ROOT if k % 2 == 0 else "sub-vi-ew1", b,
                                     extra=f' identifier="{identifiers[k]}"' if identifiers[k] else "", indent=12)
                          for k, (a, b) in enumerate(attributes))
    text = constrained(sub, constraints).replace(f'        <view contentMode="scaleToFill" id="{ROOT}">\n',
                                                 f'        <view contentMode="scaleToFill" customClass="Root" id="{ROOT}">\n')
    owner = ('        <placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File\'s Owner" customClass="Owner">\n'
             f'            <connections>\n{owner_outlets}            </connections>\n        </placeholder>\n') if owner_outlets else \
        '        <placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File\'s Owner" customClass="Owner"/>\n'
    return text.replace('        <placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File\'s Owner"/>\n', owner)


def owner_to(prop, destination="sub-vi-ew1", number=1):
    return f'                <outlet property="{prop}" destination="{destination}" id="o{number:02d}-aa-aaa"/>\n'


IDENTIFIERS = {
    "cid-plain": pinned_views(),
    "cid-outlet": pinned_views(owner_to("pin")),
    "cid-outlet-other": pinned_views(owner_to("box")),
    "cid-two-same": pinned_views(identifiers=("pin", None, "pin", None)),
    "cid-two-same-outlet": pinned_views(owner_to("pin"), identifiers=("pin", None, "pin", None)),
    "cid-two-differ": pinned_views(identifiers=("pin", None, "pan", None)),
    "cid-restoration": pinned_views(sub_attributes=' restorationIdentifier="pin"'),
    "cid-a11y": pinned_views(sub_extra='                    <accessibility key="accessibilityConfiguration" identifier="pin"/>\n'),
    "cid-label": pinned_views(owner_to("pin"), identifiers=("Label", None, None, None)).replace(
        '            </subviews>\n', '                <label opaque="NO" userInteractionEnabled="NO" contentMode="left" text="Label" translatesAutoresizingMaskIntoConstraints="NO" id="lbl-aa-aa1">\n'
        '                    <rect key="frame" x="10" y="200" width="42" height="21"/>\n'
        '                    <fontDescription key="fontDescription" type="system" pointSize="17"/>\n'
        '                    <nil key="textColor"/>\n                    <nil key="highlightedColor"/>\n                </label>\n            </subviews>\n'),
    "cid-outlet-no-id": pinned_views(owner_to("box").replace(' id="o01-aa-aaa"', '')),
    "cid-outlet-no-id-two": pinned_views(owner_to("box").replace(' id="o01-aa-aaa"', '') + owner_to("view", ROOT, 2)),
    "conn-no-id-collection": pinned_views('                <outletCollection property="boxes" destination="sub-vi-ew1" collectionClass="NSMutableArray"/>\n'
                                          + owner_to("view", ROOT, 2)),
    "conn-no-id-view-outlet": pinned_views(owner_to("view", ROOT, 2), sub_extra='                    <connections>\n'
                                           '                        <outlet property="owner" destination="-1"/>\n                    </connections>\n'),
    "conn-no-id-action": pinned_views(owner_to("view", ROOT, 2)).replace(
        '            </subviews>\n', '                <button opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" '
        'buttonType="system" lineBreakMode="middleTruncation" translatesAutoresizingMaskIntoConstraints="NO" id="btn-aa-aa1">\n'
        '                    <rect key="frame" x="10" y="200" width="60" height="30"/>\n                    <state key="normal" title="Go"/>\n'
        '                    <connections>\n                        <action selector="go:" destination="-1" eventType="touchUpInside"/>\n'
        '                    </connections>\n                </button>\n            </subviews>\n'),
    "conn-id-action": pinned_views(owner_to("view", ROOT, 2)).replace(
        '            </subviews>\n', '                <button opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" '
        'buttonType="system" lineBreakMode="middleTruncation" translatesAutoresizingMaskIntoConstraints="NO" id="btn-aa-aa1">\n'
        '                    <rect key="frame" x="10" y="200" width="60" height="30"/>\n                    <state key="normal" title="Go"/>\n'
        '                    <connections>\n                        <action selector="go:" destination="-1" eventType="touchUpInside" id="act-aa-aa1"/>\n'
        '                    </connections>\n                </button>\n            </subviews>\n'),
}
EXPERIMENTS.update(IDENTIFIERS)
STORYBOARDS["sb-conn-no-id"] = storyboard(controller_scene(1, connections='                        <outlet property="box" destination="vw1-aa-aaa"/>\n'),
                                          initial="vc1-aa-aaa")
STORYBOARDS["sb-conn-plain"] = storyboard(controller_scene(1), initial="vc1-aa-aaa")



# Round 99: a top-level view without freeform simulated metrics: when ibtool sizes it to the
# document's device.
FREEFORM = '            <freeformSimulatedSizeMetrics key="simulatedDestinationMetrics"/>\n'


def top_level(owner="", freeform=False, root_class="", frame=(0, 0, 320, 100)):
    text = xib(view(root_class, frame=frame, extra=FREEFORM if freeform else ""))
    placeholder = '        <placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File\'s Owner"/>\n'
    if owner:
        text = text.replace(placeholder, '        <placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File\'s Owner" customClass="Owner">\n'
                            f'            <connections>\n                <outlet property="{owner}" destination="iN0-l3-epB" id="o01-aa-aaa"/>\n'
                            '            </connections>\n        </placeholder>\n')
    return text


TOP_LEVEL = {
    "tl-plain": top_level(),
    "tl-owner-view": top_level("view"),
    "tl-owner-view-freeform": top_level("view", freeform=True),
    "tl-owner-other": top_level("box"),
    "tl-custom-class": top_level(root_class='customClass="Banner" customModule="T" customModuleProvider="target"'),
    "tl-custom-class-freeform": top_level(root_class='customClass="Banner" customModule="T" customModuleProvider="target"', freeform=True),
    "tl-owner-view-origin": top_level("view", frame=(10, 20, 320, 100)),
    "tl-owner-view-ipad": top_level("view"),
    "tl-plain-ipad": top_level(),
}
OPTIONS.update({"tl-owner-view-ipad": {"module": "X", "deployment": "15.0", "devices": ["iphone", "ipad"]},
                "tl-plain-ipad": {"module": "X", "deployment": "15.0", "devices": ["iphone", "ipad"]}})
TOP_LEVEL.update({"tl-both-27": top_level(), "tl-ipad-27": top_level(), "tl-iphone-15": top_level(), "tl-freeform-both-15": top_level(freeform=True),
                  "tl-origin-both-15": top_level(frame=(10, 20, 320, 100)), "tl-iphone-17": top_level(), "tl-iphone-16": top_level(),
                  "tl-retina4_7-both-15": top_level().replace('<device id="retina6_12"', '<device id="retina4_7"')})
OPTIONS.update({"tl-both-27": {"devices": ["iphone", "ipad"]}, "tl-ipad-27": {"devices": ["ipad"]}, "tl-iphone-15": {"deployment": "15.0"},
                "tl-freeform-both-15": {"deployment": "15.0", "devices": ["iphone", "ipad"]},
                "tl-origin-both-15": {"deployment": "15.0", "devices": ["iphone", "ipad"]}, "tl-iphone-17": {"deployment": "17.0"},
                "tl-iphone-16": {"deployment": "16.0"}, "tl-retina4_7-both-15": {"deployment": "15.0", "devices": ["iphone", "ipad"]}})
TOP_LEVEL.update({
    "tl-no-device-15": top_level().replace('    <device id="retina6_12" orientation="portrait" appearance="light"/>\n', ''),
    "tl-landscape-15": top_level().replace('<device id="retina6_12" orientation="portrait"', '<device id="retina6_12" orientation="landscape"'),
    "tl-two-views-15": xib(view(frame=(0, 0, 320, 100)), view(frame=(0, 0, 200, 50), identifier="two-vi-ew2")),
    "tl-cell-15": cell_xib(""),
    "tl-label-15": xib('        <label opaque="NO" userInteractionEnabled="NO" contentMode="left" text="Label" id="iN0-l3-epB">\n'
                       '            <rect key="frame" x="0.0" y="0.0" width="42" height="21"/>\n'
                       '            <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>\n'
                       '            <fontDescription key="fontDescription" type="system" pointSize="17"/>\n'
                       '            <nil key="textColor"/>\n            <nil key="highlightedColor"/>\n'
                       '            <point key="canvasLocation" x="0" y="0"/>\n        </label>\n'),
    "tl-subview-15": xib(view(frame=(0, 0, 320, 100), children='            <subviews>\n'
                              + view(frame=(10, 10, 50, 50), identifier="sub-vi-ew1").replace('            <point key="canvasLocation" x="0" y="0"/>\n', '')
                              .replace('        ', '                ') + '            </subviews>\n')),
})
OPTIONS.update({name: {"deployment": "15.0"} for name in ["tl-no-device-15", "tl-landscape-15", "tl-two-views-15", "tl-cell-15", "tl-label-15", "tl-subview-15"]})
TOP_LEVEL.update({
    "tl-pinned-15": pinned_views(owner_to("pin"), identifiers=(None, None, None, None)).replace(
        '<rect key="frame" x="0" y="0" width="393" height="852"/>', '<rect key="frame" x="0" y="0" width="320" height="100"/>'),
    "tl-pinned-27": pinned_views(owner_to("pin"), identifiers=(None, None, None, None)).replace(
        '<rect key="frame" x="0" y="0" width="393" height="852"/>', '<rect key="frame" x="0" y="0" width="320" height="100"/>'),
})
OPTIONS.update({"tl-pinned-15": {"deployment": "15.0"}})
EXPERIMENTS.update(TOP_LEVEL)



# Round 100: user-defined runtime attributes of cells, their content views, reusable views and
# controls, and of the point type.
def runtime_lines(indent, *attributes):
    return "".join(f"{indent}{line}\n" for line in runtime(*attributes).splitlines())


TEXT_KEY = udra("name", "string", value="Card")
RUNTIME_HOLDERS = {
    "udra-tv-cell": cell_xib("", cell_extra=runtime_lines("            ", RADIUS)),
    "udra-tv-cell-two": cell_xib("", cell_extra=runtime_lines("            ", RADIUS, TEXT_KEY)),
    "udra-tv-content": cell_xib("", content=runtime_lines("                ", RADIUS)),
    "udra-tv-cell-and-content": cell_xib("", content=runtime_lines("                ", TEXT_KEY), cell_extra=runtime_lines("            ", RADIUS)),
    "udra-cv-cell": cv_cell(cell_extra=runtime_lines("            ", RADIUS)),
    "udra-cv-content": cv_cell(content=runtime_lines("                ", RADIUS)),
    "udra-reusable": reusable(extra=runtime_lines("            ", RADIUS)),
    "udra-switch": constrained(switch().replace("                </switch>\n", runtime_lines("                    ", RADIUS) + "                </switch>\n"), PIN_SWITCH),
    "udra-slider": constrained(control("slider", SLIDER, runtime(RADIUS), frame=(20, 40, 118, 31)), ""),
    "udra-progress": constrained(control("progressView", PROGRESS, runtime(RADIUS), frame=(20, 40, 150, 4)), ""),
    "udra-point": constrained(with_runtime(runtime(udra("startPoint", "point", child='<point key="value" x="0.5" y="0.0"/>'))), ""),
    "udra-point-whole": constrained(with_runtime(runtime(udra("startPoint", "point", child='<point key="value" x="1" y="2"/>'))), ""),
    "udra-rect": constrained(with_runtime(runtime(udra("box", "rect", child='<rect key="value" x="1" y="2" width="3" height="4"/>'))), ""),
    "udra-range": constrained(with_runtime(runtime(udra("span", "range", child='<range key="value" location="1" length="2"/>'))), ""),
    "udra-nil": constrained(with_runtime(runtime(udra("thing", "nil"))), ""),
    "udra-localized": constrained(with_runtime(runtime(udra("title", "localizedString", value="Hello"))), ""),
}
EXPERIMENTS.update(RUNTIME_HOLDERS)



# Round 101: user-defined runtime attributes of bar button items, navigation bars, container
# views and flow layouts, as the corpus's netnewswire, wikipedia and the holdout's habitica and ish
# have them.
ACC_LABEL = udra("accLabelText", "string", value="Add")
RUNTIME_BARS = {
    "sb-udra-bar-item": storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, after_view=navigation_item(
        "Title", bar_item("rightBarButtonItem", "add", 1).replace('/>\n', '>\n' + runtime_lines("                            ", ACC_LABEL)
                                                                  + '                        </barButtonItem>\n'))), initial="nvc-aa-aaa"),
    "sb-udra-bar-item-two": storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, after_view=navigation_item(
        "Title", bar_item("rightBarButtonItem", "add", 1).replace('/>\n', '>\n' + runtime_lines("                            ", ACC_LABEL, udra("accEnabled", "boolean", value="YES"))
                                                                  + '                        </barButtonItem>\n'))), initial="nvc-aa-aaa"),
    "sb-udra-nav-bar": storyboard(navigation_scene("vc1-aa-aaa").replace('                        <autoresizingMask key="autoresizingMask"/>\n                    </navigationBar>\n',
        '                        <autoresizingMask key="autoresizingMask"/>\n' + runtime_lines("                        ", RADIUS) + '                    </navigationBar>\n'),
        controller_scene(1), initial="nvc-aa-aaa"),
    "sb-udra-container": storyboard(controller_scene(1, view_extra=container_view(EMBED).replace('                                <connections>\n',
        runtime_lines("                                ", RADIUS) + '                                <connections>\n')), controller_scene(2), initial="vc1-aa-aaa"),
    "udra-flow-layout": constrained(collection(layout=FLOW.replace('</collectionViewFlowLayout>\n', runtime_lines("    ", udra("sectionFootersPinToVisibleBounds", "boolean", value="YES"))
                                                                    + '</collectionViewFlowLayout>\n')), ""),
}
EXPERIMENTS.update({k: v for k, v in RUNTIME_BARS.items() if not k.startswith("sb-")})
STORYBOARDS.update({k: v for k, v in RUNTIME_BARS.items() if k.startswith("sb-")})



# Round 102: a storyboard's global tint (`<color key="tintColor">` of the document), as the
# holdout's habitica and keepassium storyboards have it.
GLOBAL_TINT = '    <color key="tintColor" red="0.2" green="0.4" blue="0.6" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>\n'


def tinted(document, tint=GLOBAL_TINT):
    return document.replace("</document>\n", tint + "</document>\n")


GLOBAL_TINTS = {
    "sb-tint-plain": tinted(storyboard(controller_scene(1), initial="vc1-aa-aaa")),
    "sb-tint-two": tinted(storyboard(controller_scene(1), controller_scene(2, ' storyboardIdentifier="Two"'), initial="vc1-aa-aaa")),
    "sb-tint-nav": tinted(storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1), initial="nvc-aa-aaa")),
    "sb-tint-tab": tinted(storyboard(tab_scene(), controller_scene(1), controller_scene(2), initial="tab-aa-aaa")),
    "sb-tint-view-tint": tinted(storyboard(controller_scene(1, view_extra='                        <color key="tintColor" white="0.5" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>\n'),
                                           initial="vc1-aa-aaa")),
    "sb-tint-button": tinted(storyboard(controller_scene(1, view_extra=segue_button('<segue destination="vc2-aa-aaa" kind="show" id="bsg-aa-aaa"/>')),
                                        controller_scene(2), initial="vc1-aa-aaa")),
}
GLOBAL_TINTS["sb-tint-tab-nav"] = tinted(storyboard(tab_scene(children=("nvc-aa-aaa", "vc2-aa-aaa")), nav_child("aa", "vc1-aa-aaa"), controller_scene(1),
                                                  controller_scene(2), initial="tab-aa-aaa"))
GLOBAL_TINTS["sb-tint-gray"] = tinted(storyboard(controller_scene(1), initial="vc1-aa-aaa"), '    <color key="tintColor" white="0.25" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>\n')
STORYBOARDS.update(GLOBAL_TINTS)
STORYBOARDS.update({name.replace("sb-tint-", "sb-untinted-"): document.replace(GLOBAL_TINT, "") for name, document in GLOBAL_TINTS.items()
                    if GLOBAL_TINT in document})



# Round 103: table view cells' and their content views' layoutMarginsFollowReadableWidth, as the
# holdout's storyboards and xibs have them; a view's for reference.
READABLE = {
    "cell-readable": cell_xib(' layoutMarginsFollowReadableWidth="YES"'),
    "cell-readable-no": cell_xib(' layoutMarginsFollowReadableWidth="NO"'),
    "cell-content-readable": cell_xib("", content_attributes=' layoutMarginsFollowReadableWidth="YES"'),
    "cell-readable-both": cell_xib(' layoutMarginsFollowReadableWidth="YES"', content_attributes=' layoutMarginsFollowReadableWidth="YES"'),
    "cell-readable-preserves": cell_xib(' layoutMarginsFollowReadableWidth="YES" preservesSuperviewLayoutMargins="YES"'),
    "view-readable": constrained(subview("sub-vi-ew1", attributes=' layoutMarginsFollowReadableWidth="YES"'), ""),
}
EXPERIMENTS.update(READABLE)



# Round 104: what the holdout's documents stop at next: segues' presentation and transition styles,
# text views adjusting their font to the content size category, all data detectors, top-level stack
# and table views, and table view cells' accessibility.
def presenting(extra):
    return storyboard(controller_scene(1, view_extra=segue_button(f'<segue destination="vc2-aa-aaa" kind="presentation"{extra} id="bsg-aa-aaa"/>')),
                      controller_scene(2), initial="vc1-aa-aaa")


SEGUE_STYLES = {f"sb-segue-style-{style}": presenting(f' modalPresentationStyle="{style}"')
                for style in ["fullScreen", "pageSheet", "formSheet", "currentContext", "overFullScreen", "overCurrentContext", "automatic", "popover"]}
SEGUE_STYLES.update({f"sb-segue-transition-{style}": presenting(f' modalTransitionStyle="{style}"')
                     for style in ["coverVertical", "crossDissolve", "flipHorizontal", "partialCurl"]})
SEGUE_STYLES["sb-segue-style-both"] = presenting(' modalPresentationStyle="overFullScreen" modalTransitionStyle="crossDissolve"')
SEGUE_STYLES["sb-segue-style-controller"] = storyboard(controller_scene(1, connections='                        <segue destination="vc2-aa-aaa" kind="presentation" '
                                                       'identifier="Go" modalPresentationStyle="fullScreen" id="csg-aa-aa1"/>\n'),
                                                       controller_scene(2), initial="vc1-aa-aaa")
STORYBOARDS.update(SEGUE_STYLES)

TV_STYLE_FONT = '<fontDescription key="fontDescription" style="UICTFontTextStyleBody"/>\n'
HOLDOUT_KINDS = {
    "text-view-adjusts": constrained(text_view(TV_ATTRIBUTES + ' adjustsFontForContentSizeCategory="YES"', TV_BACKGROUND + TV_TEXT + TV_STYLE_FONT + TV_TRAITS), "",
                                     resources=TVR),
    "text-view-adjusts-no": constrained(text_view(TV_ATTRIBUTES + ' adjustsFontForContentSizeCategory="NO"', TV_BACKGROUND + TV_TEXT + TV_STYLE_FONT + TV_TRAITS), "",
                                        resources=TVR),
    "text-view-detect-all": constrained(text_view(children=TV_BACKGROUND + TV_TEXT + TV_FONT + TV_TRAITS
        + '<dataDetectorType key="dataDetectorTypes" phoneNumber="YES" link="YES" address="YES" calendarEvent="YES"/>\n'), "", resources=TVR),
    "text-view-detect-calendar": constrained(text_view(children=TV_BACKGROUND + TV_TEXT + TV_FONT + TV_TRAITS
        + '<dataDetectorType key="dataDetectorTypes" calendarEvent="YES"/>\n'), "", resources=TVR),
    "tl-stack": xib('        <stackView opaque="NO" contentMode="scaleToFill" axis="vertical" id="iN0-l3-epB">\n'
                    '            <rect key="frame" x="0.0" y="0.0" width="200" height="100"/>\n'
                    '            <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>\n'
                    '            <point key="canvasLocation" x="0" y="0"/>\n        </stackView>\n'),
    "cell-a11y": cell_xib("", cell_extra='            <accessibility key="accessibilityConfiguration" identifier="cell"/>\n'),
    "cell-a11y-label": cell_xib("", cell_extra='            <accessibility key="accessibilityConfiguration" label="Row">\n'
                                '                <bool key="isElement" value="YES"/>\n            </accessibility>\n'),
}
HOLDOUT_KINDS["tl-stack-15"] = HOLDOUT_KINDS["tl-stack"]
HOLDOUT_KINDS["tl-stack-arranged"] = HOLDOUT_KINDS["tl-stack"].replace(
    '            <point key="canvasLocation"', '            <subviews>\n' + label(frame=(0, 0, 200, 50)).replace('                ', '                ', 1)
    + label(frame=(0, 50, 200, 50), identifier="lbl-aa-aa2") + '            </subviews>\n            <point key="canvasLocation"')
OPTIONS["tl-stack-15"] = {"deployment": "15.0"}
EXPERIMENTS.update(HOLDOUT_KINDS)



# Round 105: controls' actions of every event, a date picker's action, and long press recognizers.
MORE_EVENTS = ["touchDown", "touchDownRepeat", "touchDragInside", "touchDragOutside", "touchDragEnter", "touchDragExit", "touchUpOutside",
               "touchCancel", "menuActionTriggered"]
CONTROL_EVENTS = {f"act-control-{event}": constrained(control_view(connections=actions(("acted:", event))), pin("ctl-aa-aaa", 0, 10, 20))
                  for event in MORE_EVENTS}
CONTROL_EVENTS["act-control-every-event"] = constrained(control_view(connections=actions(*[(f"{event}:", event) for event in MORE_EVENTS + ["touchUpInside", "valueChanged"]])),
                                                        pin("ctl-aa-aaa", 0, 10, 20))
CONTROL_EVENTS["act-date-picker"] = constrained(subview("dpk-aa-aa1", (0, 0, 350, 216), "datePicker", ' contentHorizontalAlignment="center" contentVerticalAlignment="center" '
                                                        'datePickerMode="countDownTimer" minuteInterval="1" useCurrentDate="NO"').replace(
    "                </datePicker>\n", actions(("picked:", "valueChanged")) + "                </datePicker>\n"), "")
CONTROL_EVENTS["gesture-long-press"] = gestures(recognizer("pongPressGestureRecognizer", "lpr-aa-aa1", ' allowableMovement="10" minimumPressDuration="0.5"'),
                                                attach=(("sss-ss-ss1", "lpr-aa-aa1"),))
CONTROL_EVENTS["gesture-long-press-long"] = gestures(recognizer("pongPressGestureRecognizer", "lpr-aa-aa1", ' allowableMovement="20" minimumPressDuration="5"'),
                                                     attach=(("sss-ss-ss1", "lpr-aa-aa1"),))
CONTROL_EVENTS["gesture-pinch"] = gestures(recognizer("pinchGestureRecognizer", "pnc-aa-aa1"), attach=(("sss-ss-ss1", "pnc-aa-aa1"),))
CONTROL_EVENTS["gesture-rotation"] = gestures(recognizer("rotationGestureRecognizer", "rot-aa-aa1"), attach=(("sss-ss-ss1", "rot-aa-aa1"),))
CONTROL_EVENTS["gesture-edge-pan"] = gestures(recognizer("screenEdgePanGestureRecognizer", "edg-aa-aa1", ' minimumNumberOfTouches="1"'), attach=(("sss-ss-ss1", "edg-aa-aa1"),))
EXPERIMENTS.update(CONTROL_EVENTS)
STORYBOARDS["sb-gesture-long-press"] = sb_gestures([sb_subview("sub-vi-ew1", 10, ["lpr-aa-aa1"])],
                                                  [sb_recognizer("lpr-aa-aa1", "pongPressGestureRecognizer").replace(' id="lpr-aa-aa1"', ' minimumPressDuration="1" id="lpr-aa-aa1"', 1)])
STORYBOARDS["sb-gesture-pinch"] = sb_gestures([sb_subview("sub-vi-ew1", 10, ["pnc-aa-aa1"])], [sb_recognizer("pnc-aa-aa1", "pinchGestureRecognizer")])



# Round 106: two text views: which of their attributed texts' objects a nib shares.
def second_text_view(document_view):
    return document_view.replace('id="txv-aa-aa1"', 'id="txv-aa-aa2"').replace('<rect key="frame" x="16" y="40"', '<rect key="frame" x="16" y="200"')


TWO_TEXT_VIEWS = {
    "text-view-two-same": constrained(text_view() + second_text_view(text_view()), "", resources=TVR),
    "text-view-two-other-text": constrained(text_view() + second_text_view(text_view(children=TV_BACKGROUND + '<string key="text">Other</string>\n' + TV_FONT + TV_TRAITS)), "",
                                            resources=TVR),
    "text-view-two-other-font": constrained(text_view() + second_text_view(text_view(children=TV_BACKGROUND + TV_TEXT + font_description({"type": "system", "pointSize": "17"})
                                                                                      + "\n" + TV_TRAITS)), "", resources=TVR),
    "text-view-two-other-alignment": constrained(text_view() + second_text_view(text_view(TV_ATTRIBUTES.replace('textAlignment="natural"', 'textAlignment="center"'))), "",
                                                 resources=TVR),
    "text-view-two-style": constrained(text_view(children=TV_BACKGROUND + TV_TEXT + TV_STYLE_FONT + TV_TRAITS)
                                       + second_text_view(text_view(children=TV_BACKGROUND + TV_TEXT + TV_STYLE_FONT + TV_TRAITS)), "", resources=TVR),
}
EXPERIMENTS.update(TWO_TEXT_VIEWS)



# Round 107: a scene's recognizer beside a controller whose own outlets reach its view, as the
# corpus's wikipedia EditSaveViewController has them: which upstream placeholder comes first.
def controller_connections(lines):
    return ('                    <connections>\n' + "".join(f"                        {line}\n" for line in lines) + '                    </connections>\n')


def gesture_scene(lines, owner=False):
    subviews = [sb_subview("sub-vi-ew1", 10, ["tap-aa-aa1"]), sb_subview("sub-vi-ew2", 70, empty=False)]
    if owner:
        subviews[1] = subviews[1].replace('id="sub-vi-ew2">', 'customClass="Box" customModule="T" customModuleProvider="target" id="sub-vi-ew2">').replace(
            "                            </view>\n", '                                <connections>\n                                    <outlet property="owner" destination="BYZ-38-t0r" id="own-aa-aa1"/>\n'
            "                                </connections>\n                            </view>\n")
    document = sb_gestures(subviews, [sb_recognizer("tap-aa-aa1")])
    return document.replace("                </viewController>", controller_connections(lines) + "                </viewController>", 1) if lines else document


GESTURE_SOURCES = {
    "sb-gesture-controller-outlet": gesture_scene(['<outlet property="box" destination="sub-vi-ew2" id="box-aa-aa1"/>']),
    "sb-gesture-controller-collection": gesture_scene(['<outletCollection property="boxes" destination="sub-vi-ew2" collectionClass="NSMutableArray" id="bxs-aa-aa1"/>']),
    "sb-gesture-controller-outlet-and-owner": gesture_scene(['<outlet property="box" destination="sub-vi-ew2" id="box-aa-aa1"/>'], owner=True),
    "sb-gesture-controller-outlet-to-view": gesture_scene(['<outlet property="root" destination="8bC-Xf-vdC" id="rot-aa-aa1"/>']),
}
GESTURE_SOURCES["sb-gesture-controller-collection-zzz"] = gesture_scene(['<outletCollection property="zzz" destination="sub-vi-ew2" collectionClass="NSMutableArray" id="bxs-aa-aa1"/>'])
STORYBOARDS.update(GESTURE_SOURCES)



# Round 108: the content modes of the corners in IB's spellings and others: `TopLeft`, capitalized,
# against `topLeft`, and the other corners in both cases.
def mode_case(mode):
    return mode.lower() + ("-capital" if mode[0].isupper() else "")


CONTENT_MODE_CASES = {
    "label-mode-topleft-capital": constrained(label(LABEL_ATTRIBUTES.replace('contentMode="left"', 'contentMode="TopLeft"')), ""),
    "label-mode-topleft": constrained(label(LABEL_ATTRIBUTES.replace('contentMode="left"', 'contentMode="topLeft"')), ""),
}
CONTENT_MODE_CASES.update({f"image-view-mode-{mode_case(mode)}": constrained(subview("img-aa-aa1", tag="imageView", attributes=f' contentMode="{mode}"'), "")
                           for mode in ["TopLeft", "topLeft", "TopRight", "BottomLeft", "BottomRight", "topRight", "bottomLeft", "bottomRight"]})
EXPERIMENTS.update(CONTENT_MODE_CASES)



# Round 109: table view controllers' refresh controls, as IB writes them, with an action and an
# outlet.
def refresh_control(attributes="", connections=""):
    body = '                        <autoresizingMask key="autoresizingMask"/>\n' + connections
    return ('                    <refreshControl key="refreshControl" opaque="NO" multipleTouchEnabled="YES" contentMode="center"' + attributes
            + ' enabled="NO" contentHorizontalAlignment="center" contentVerticalAlignment="center" id="rfc-aa-aa1">\n' + body + '                    </refreshControl>\n')


REFRESH_ACTION = ('                        <connections>\n                            <action selector="refresh:" destination="tvc-aa-aaa" eventType="valueChanged" '
                  'id="rfa-aa-aa1"/>\n                        </connections>\n')
REFRESH = {
    "sb-tvc-refresh": storyboard(tvc_scene(prototypes(tvc_cell(1)), after_view=refresh_control()), initial="tvc-aa-aaa"),
    "sb-tvc-refresh-margins": storyboard(tvc_scene(prototypes(tvc_cell(1)), after_view=refresh_control(' insetsLayoutMarginsFromSafeArea="NO"')), initial="tvc-aa-aaa"),
    "sb-tvc-refresh-action": storyboard(tvc_scene(prototypes(tvc_cell(1)), after_view=refresh_control(connections=REFRESH_ACTION)), initial="tvc-aa-aaa"),
    "sb-tvc-refresh-nav": storyboard(navigation_scene("tvc-aa-aaa"), tvc_scene(prototypes(tvc_cell(1)), after_view=navigation_item() + refresh_control(connections=REFRESH_ACTION)),
                                     initial="nvc-aa-aaa"),
    "sb-tvc-refresh-enabled": storyboard(tvc_scene(prototypes(tvc_cell(1)), after_view=refresh_control().replace(' enabled="NO"', '')), initial="tvc-aa-aaa"),
}
STORYBOARDS.update(REFRESH)



# Round 110: what documents' headers still stop at: the retina6_72 device, the capability of
# constraints with non-1.0 multipliers, an old <development> element.
DEVICE_LINE = '<device id="retina6_12" orientation="portrait" appearance="light"/>'
HEADERS = {
    "device-retina6_72": xib(view()).replace(DEVICE_LINE, '<device id="retina6_72" orientation="portrait" appearance="light"/>'),
    "header-capability-multipliers": xib(view()).replace('        <capability name="documents saved',
                                                         '        <capability name="Constraints with non-1.0 multipliers" minToolsVersion="5.1"/>\n        <capability name="documents saved'),
    "header-development-5100": xib(view()).replace('    <dependencies>\n', '    <dependencies>\n        <development version="5100" identifier="xcode"/>\n'),
}
EXPERIMENTS.update(HEADERS)
STORYBOARDS["sb-device-retina6_72"] = storyboard(controller_scene(1), initial="vc1-aa-aaa").replace(DEVICE_LINE, '<device id="retina6_72" orientation="portrait" appearance="light"/>')
STORYBOARDS["sb-device-retina6_72-landscape"] = storyboard(controller_scene(1), initial="vc1-aa-aaa").replace(DEVICE_LINE, '<device id="retina6_72" orientation="landscape" appearance="light"/>')



# Round 111: navigation controllers' roots that are also the storyboard's initial controller or
# that segues reach, as the corpus's wikipedia Places, gomap QuestSolver and uncloudnotes have them.
SHOW_TO_1 = '                        <segue destination="vc1-aa-aaa" kind="show" identifier="Back" id="bck-aa-aaa"/>\n'
NAV_ROOTS = {
    "sb-nav-root-initial": storyboard(navigation_scene("vc1-aa-aaa", ' storyboardIdentifier="Nav"'), controller_scene(1), initial="vc1-aa-aaa"),
    "sb-nav-root-reached": storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, connections='                        <segue destination="vc2-aa-aaa" kind="show" identifier="Go" id="gog-aa-aaa"/>\n'),
                                      controller_scene(2, connections=SHOW_TO_1), initial="nvc-aa-aaa"),
    "sb-nav-root-reached-identifier": storyboard(navigation_scene("vc1-aa-aaa"),
                                                 controller_scene(1, ' storyboardIdentifier="One"', connections='                        <segue destination="vc2-aa-aaa" kind="show" identifier="Go" id="gog-aa-aaa"/>\n'),
                                                 controller_scene(2, connections=SHOW_TO_1), initial="nvc-aa-aaa"),
    "sb-nav-root-initial-titled": storyboard(navigation_scene("vc1-aa-aaa", ' storyboardIdentifier="Nav"'), controller_scene(1, after_view=navigation_item("Home")), initial="vc1-aa-aaa"),
}
STORYBOARDS.update(NAV_ROOTS)



# Round 112: simulated bar metrics of controllers, IB's design-time bars: whether they change a
# nib.
def simulated(element):
    return f"                    {element}\n"


SIMULATED_BARS = {
    "sb-sim-tab-bar": storyboard(controller_scene(1, after_view=simulated('<simulatedTabBarMetrics key="simulatedBottomBarMetrics"/>')), initial="vc1-aa-aaa"),
    "sb-sim-toolbar": storyboard(controller_scene(1, after_view=simulated('<simulatedToolbarMetrics key="simulatedBottomBarMetrics"/>')), initial="vc1-aa-aaa"),
    "sb-sim-toolbar-opaque": storyboard(controller_scene(1, after_view=simulated('<simulatedToolbarMetrics key="simulatedBottomBarMetrics" translucent="NO"/>')),
                                        initial="vc1-aa-aaa"),
    "sb-sim-nav-opaque": storyboard(controller_scene(1, after_view=simulated('<simulatedNavigationBarMetrics key="simulatedTopBarMetrics" translucent="NO" prompted="NO"/>')),
                                    initial="vc1-aa-aaa"),
    "sb-sim-nav-black": storyboard(controller_scene(1, after_view=simulated('<simulatedNavigationBarMetrics key="simulatedTopBarMetrics" barStyle="black" prompted="NO"/>')),
                                   initial="vc1-aa-aaa"),
    "sb-sim-tvc-toolbar": storyboard(tvc_scene(prototypes(tvc_cell(1)), after_view=simulated('<simulatedToolbarMetrics key="simulatedBottomBarMetrics"/>')), initial="tvc-aa-aaa"),
    "sb-sim-tvc-plain": storyboard(tvc_scene(prototypes(tvc_cell(1))), initial="tvc-aa-aaa"),
    "sb-sim-plain": storyboard(controller_scene(1), initial="vc1-aa-aaa"),
}
STORYBOARDS.update(SIMULATED_BARS)



# Round 113: accessibility of a table view cell's content view, and of prototype cells in
# storyboards.
A11Y_CELL = '<accessibility key="accessibilityConfiguration" label="Row" identifier="row">\n    <bool key="isElement" value="YES"/>\n</accessibility>\n'


def indented(text, indent):
    return "".join(indent + line + "\n" for line in text.splitlines())


CELL_A11Y = {
    "cell-content-a11y": cell_xib("", content=indented(A11Y_CELL, "                ")),
    "cell-content-a11y-id": cell_xib("", content='                <accessibility key="accessibilityConfiguration" identifier="content"/>\n'),
    "cell-both-a11y": cell_xib("", content='                <accessibility key="accessibilityConfiguration" identifier="content"/>\n',
                               cell_extra=indented(A11Y_CELL, "            ")),
}
EXPERIMENTS.update(CELL_A11Y)
STORYBOARDS["sb-cell-a11y"] = storyboard(tvc_scene(prototypes(tvc_cell(1).replace("                            </tableViewCell>",
    indented(A11Y_CELL, "                                ") + "                            </tableViewCell>"))), initial="tvc-aa-aaa")
STORYBOARDS["sb-cell-content-a11y"] = storyboard(tvc_scene(prototypes(tvc_cell(1).replace("                                </tableViewCellContentView>",
    indented(A11Y_CELL, "                                    ") + "                                </tableViewCellContentView>"))), initial="tvc-aa-aaa")


# Round 114: outlets to objects of a controller's own nib: a controller's bar button items and
# navigation item, standing alone and as a navigation controller's root; from a view of its scene;
# and, in xibs, to a navigation bar's and a toolbar's items.
def controller_connections(*outlets):
    return ('                    <connections>\n' + "".join(f'                        <outlet property="{name}" destination="{destination}" id="out-aa-aa{number}"/>\n'
                                                            for number, (name, destination) in enumerate(outlets, 1))
            + '                    </connections>\n')


DONE_OUTLET = controller_connections(("doneButton", "bbi-aa-aa1"))
CUSTOM_CONTROLLER = ' customClass="Controller" customModule="T" customModuleProvider="target"'


def done_bar(target, action="done:", key="rightBarButtonItem", system="done", number=1):
    return navigation_item(items=bar_item(key, system, number, action, target=target)).replace("nvi-aa-aaa", f"nvi-aa-aa{number}" if number > 1 else "nvi-aa-aaa")


def tvc_outlets(after_view, attributes=""):
    return tvc_scene(prototypes(tvc_cell(1)), attributes=attributes, after_view=after_view)


def cvc_outlets(after_view, attributes=""):
    return cvc_scene(attributes=attributes).replace("                    </collectionView>\n", "                    </collectionView>\n" + after_view)


TWO_BARS = navigation_item(items=bar_item("leftBarButtonItem", "cancel", 2, "cancel:", target="tvc-aa-aaa") + bar_item("rightBarButtonItem", "done", 1, "done:", target="tvc-aa-aaa"))
OUTLET_DESTINATIONS = {
    "sb-outlet-bar-tvc": storyboard(tvc_outlets(done_bar("tvc-aa-aaa") + DONE_OUTLET), initial="tvc-aa-aaa"),
    "sb-outlet-bar-tvc-custom": storyboard(tvc_outlets(done_bar("tvc-aa-aaa") + DONE_OUTLET, CUSTOM_CONTROLLER), initial="tvc-aa-aaa"),
    "sb-outlet-bar-tvc-no-action": storyboard(tvc_outlets(done_bar("tvc-aa-aaa", action=None) + DONE_OUTLET), initial="tvc-aa-aaa"),
    "sb-outlet-bar-tvc-two": storyboard(tvc_outlets(TWO_BARS + controller_connections(("doneButton", "bbi-aa-aa1"), ("cancelButton", "bbi-aa-aa2"))), initial="tvc-aa-aaa"),
    "sb-outlet-bar-tvc-identifier": storyboard(tvc_outlets(done_bar("tvc-aa-aaa") + DONE_OUTLET, CUSTOM_CONTROLLER + ' storyboardIdentifier="Table"'), initial="tvc-aa-aaa"),
    "sb-outlet-bar-tvc-nav": storyboard(navigation_scene("tvc-aa-aaa"), tvc_outlets(done_bar("tvc-aa-aaa") + DONE_OUTLET, CUSTOM_CONTROLLER), initial="nvc-aa-aaa"),
    "sb-outlet-item-tvc": storyboard(tvc_outlets(navigation_item() + controller_connections(("item", "nvi-aa-aaa"))), initial="tvc-aa-aaa"),
    "sb-outlet-item-tvc-nav": storyboard(navigation_scene("tvc-aa-aaa"), tvc_outlets(navigation_item() + controller_connections(("item", "nvi-aa-aaa"))), initial="nvc-aa-aaa"),
    "sb-outlet-item-and-bar-tvc": storyboard(tvc_outlets(done_bar("tvc-aa-aaa") + controller_connections(("doneButton", "bbi-aa-aa1"), ("item", "nvi-aa-aaa"))), initial="tvc-aa-aaa"),
    "sb-outlet-bar-cvc": storyboard(cvc_outlets(done_bar("cvc-aa-aaa") + DONE_OUTLET), initial="cvc-aa-aaa"),
    "sb-outlet-bar-cvc-custom": storyboard(cvc_outlets(done_bar("cvc-aa-aaa") + DONE_OUTLET, CUSTOM_CONTROLLER), initial="cvc-aa-aaa"),
    "sb-outlet-bar-cvc-nav": storyboard(navigation_scene("cvc-aa-aaa"), cvc_outlets(done_bar("cvc-aa-aaa") + DONE_OUTLET, CUSTOM_CONTROLLER), initial="nvc-aa-aaa"),
    "sb-outlet-bar-vc": storyboard(controller_scene(1, after_view=done_bar("vc1-aa-aaa"), connections='                        <outlet property="doneButton" destination="bbi-aa-aa1" id="out-aa-aa1"/>\n'), initial="vc1-aa-aaa"),
    "sb-outlet-bar-vc-custom": storyboard(controller_scene(1, attributes=CUSTOM_CONTROLLER, after_view=done_bar("vc1-aa-aaa"), connections='                        <outlet property="doneButton" destination="bbi-aa-aa1" id="out-aa-aa1"/>\n'), initial="vc1-aa-aaa"),
    "sb-outlet-bar-vc-and-view": storyboard(controller_scene(1, attributes=CUSTOM_CONTROLLER, after_view=done_bar("vc1-aa-aaa"), connections='                        <outlet property="doneButton" destination="bbi-aa-aa1" id="out-aa-aa1"/>\n'
                                                             '                        <outlet property="zzz" destination="vw1-aa-aaa" id="out-aa-aa2"/>\n'), initial="vc1-aa-aaa"),
    "sb-outlet-bar-vc-segue": storyboard(controller_scene(1, after_view=done_bar("vc1-aa-aaa"), connections='                        <outlet property="doneButton" destination="bbi-aa-aa1" id="out-aa-aa1"/>\n' + segue("vc2-aa-aaa", "show", 1, "Detail")),
                                         controller_scene(2), initial="vc1-aa-aaa"),
}
BAR_VIEW = ('                        <subviews>\n                            <view contentMode="scaleToFill" customClass="Holder" customModule="T" customModuleProvider="target" id="hld-aa-aa1">\n'
            '                                <rect key="frame" x="0.0" y="100" width="100" height="100"/>\n'
            '                                <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>\n'
            '                                <connections>\n                                    <outlet property="doneButton" destination="bbi-aa-aa1" id="out-aa-aa1"/>\n'
            '                                </connections>\n                            </view>\n                        </subviews>\n')
OUTLET_DESTINATIONS["sb-outlet-bar-from-view"] = storyboard(controller_scene(1, after_view=done_bar("vc1-aa-aaa"), view_extra=BAR_VIEW), initial="vc1-aa-aaa")
OUTLET_DESTINATIONS["sb-outlet-bar-from-view-nav"] = storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, after_view=done_bar("vc1-aa-aaa"), view_extra=BAR_VIEW), initial="nvc-aa-aaa")
STORYBOARDS.update(OUTLET_DESTINATIONS)


def holder_view(*outlets, identifier="hld-aa-aa1", y=100):
    connections = "".join(f'                                    <outlet property="{name}" destination="{destination}" id="{identifier[:3]}-ou-t{number}"/>\n'
                          for number, (name, destination) in enumerate(outlets, 1))
    return (f'                            <view contentMode="scaleToFill" customClass="Holder" customModule="T" customModuleProvider="target" id="{identifier}">\n'
            f'                                <rect key="frame" x="0.0" y="{y}" width="100" height="100"/>\n'
            '                                <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>\n'
            f'                                <connections>\n{connections}                                </connections>\n                            </view>\n')


def holders(*views):
    return "                        <subviews>\n" + "".join(views) + "                        </subviews>\n"


VC_TWO_BARS = navigation_item(items=bar_item("leftBarButtonItem", "cancel", 2, "cancel:") + bar_item("rightBarButtonItem", "done", 1, "done:"))
OUTLET_FROM_VIEW = {
    "sb-outlet-bar-from-view-and-controller": storyboard(controller_scene(1, after_view=done_bar("vc1-aa-aaa"), view_extra=holders(holder_view(("doneButton", "bbi-aa-aa1"), ("owner", "vc1-aa-aaa")))), initial="vc1-aa-aaa"),
    "sb-outlet-bar-from-view-controller-first": storyboard(controller_scene(1, after_view=done_bar("vc1-aa-aaa"), view_extra=holders(holder_view(("doneButton", "bbi-aa-aa1"), ("aaa", "vc1-aa-aaa")))), initial="vc1-aa-aaa"),
    "sb-outlet-two-bars-from-view": storyboard(controller_scene(1, after_view=VC_TWO_BARS, view_extra=holders(holder_view(("doneButton", "bbi-aa-aa1"), ("cancelButton", "bbi-aa-aa2")))), initial="vc1-aa-aaa"),
    "sb-outlet-two-bars-from-view-names-swapped": storyboard(controller_scene(1, after_view=VC_TWO_BARS, view_extra=holders(holder_view(("aaa", "bbi-aa-aa1"), ("zzz", "bbi-aa-aa2")))), initial="vc1-aa-aaa"),
    "sb-outlet-item-from-view": storyboard(controller_scene(1, after_view=done_bar("vc1-aa-aaa"), view_extra=holders(holder_view(("item", "nvi-aa-aaa")))), initial="vc1-aa-aaa"),
    "sb-outlet-item-and-bar-from-view": storyboard(controller_scene(1, after_view=done_bar("vc1-aa-aaa"), view_extra=holders(holder_view(("item", "nvi-aa-aaa"), ("doneButton", "bbi-aa-aa1")))), initial="vc1-aa-aaa"),
    "sb-outlet-bar-from-two-views": storyboard(controller_scene(1, after_view=done_bar("vc1-aa-aaa"), view_extra=holders(holder_view(("doneButton", "bbi-aa-aa1")), holder_view(("doneButton", "bbi-aa-aa1"), identifier="hl2-aa-aa1", y=300))), initial="vc1-aa-aaa"),
    "sb-outlet-bar-from-view-root-outlet": storyboard(controller_scene(1, after_view=done_bar("vc1-aa-aaa"), connections='                        <outlet property="zzz" destination="bbi-aa-aa1" id="out-aa-aa9"/>\n', view_extra=holders(holder_view(("doneButton", "bbi-aa-aa1")))), initial="vc1-aa-aaa"),
    "sb-outlet-bar-tvc-from-cell": storyboard(tvc_scene(prototypes(tvc_cell(1).replace('</tableViewCell>', '    <connections>\n    <outlet property="doneButton" destination="bbi-aa-aa1" id="clo-aa-aa1"/>\n</connections>\n</tableViewCell>')), after_view=done_bar("tvc-aa-aaa")), initial="tvc-aa-aaa"),
    "sb-outlet-bar-tab-nav": storyboard(tab_scene(["nvc-aa-aaa"]), navigation_scene("vc1-aa-aaa"), controller_scene(1, after_view=done_bar("vc1-aa-aaa"), connections='                        <outlet property="doneButton" destination="bbi-aa-aa1" id="out-aa-aa1"/>\n'), initial="tab-aa-aaa"),
}
SECOND_NAV = navigation_scene("vc2-aa-aaa").replace("nvs-aa-aaa", "nvs-aa-aab").replace("nvc-aa-aaa", "nvc-aa-aab").replace("nvb-aa-aaa", "nvb-aa-aab").replace("rel-aa-aaa", "rel-aa-aab").replace("nfr-aa-aaa", "nfr-aa-aab")
OUTLET_FROM_VIEW["sb-outlet-bar-tab-two-navs"] = storyboard(tab_scene(["nvc-aa-aaa", "nvc-aa-aab"]), navigation_scene("vc1-aa-aaa"), SECOND_NAV,
    controller_scene(1, after_view=done_bar("vc1-aa-aaa"), connections='                        <outlet property="zzz" destination="bbi-aa-aa1" id="out-aa-aa1"/>\n'),
    controller_scene(2, after_view=done_bar("vc2-aa-aaa", number=2), connections='                        <outlet property="aaa" destination="bbi-aa-aa2" id="out-aa-aa2"/>\n'), initial="tab-aa-aaa")
OUTLET_FROM_VIEW["sb-outlet-extra-from-view"] = storyboard(controller_scene(1, view_extra=holders(holder_view(("extra", "xtr-aa-aa1")))).replace(
    '                <placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa"',
    '                <view contentMode="scaleToFill" id="xtr-aa-aa1">\n                    <rect key="frame" x="0.0" y="0.0" width="100" height="100"/>\n'
    '                    <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>\n                </view>\n'
    '                <placeholder placeholderIdentifier="IBFirstResponder" id="fr1-aa-aaa"'), initial="vc1-aa-aaa")
OUTLET_FROM_VIEW["sb-outlet-bar-tab-two-navs-actions"] = storyboard(tab_scene(["nvc-aa-aaa", "nvc-aa-aab"]), navigation_scene("vc1-aa-aaa"), SECOND_NAV,
    controller_scene(1, after_view=done_bar("vc1-aa-aaa", action="zzz:")), controller_scene(2, after_view=done_bar("vc2-aa-aaa", action="aaa:", number=2)), initial="tab-aa-aaa")
OUTLET_FROM_VIEW["sb-bar-same-selector"] = storyboard(controller_scene(1, after_view=navigation_item(items=bar_item("leftBarButtonItem", "cancel", 2, "done:") + bar_item("rightBarButtonItem", "done", 1, "done:"))), initial="vc1-aa-aaa")
OUTLET_FROM_VIEW["sb-bar-same-selector-right-first"] = storyboard(controller_scene(1, after_view=navigation_item(items=bar_item("rightBarButtonItem", "done", 1, "done:") + bar_item("leftBarButtonItem", "cancel", 2, "done:"))), initial="vc1-aa-aaa")
OUTLET_FROM_VIEW["sb-bar-same-selector-ids-swapped"] = storyboard(controller_scene(1, after_view=navigation_item(items=bar_item("leftBarButtonItem", "cancel", 1, "done:") + bar_item("rightBarButtonItem", "done", 2, "done:"))), initial="vc1-aa-aaa")
OUTLET_FROM_VIEW["sb-bar-same-selector-left-done"] = storyboard(controller_scene(1, after_view=navigation_item(items=bar_item("leftBarButtonItem", "done", 1, "done:") + bar_item("rightBarButtonItem", "cancel", 2, "done:"))), initial="vc1-aa-aaa")
STORYBOARDS.update(OUTLET_FROM_VIEW)


def owner_outlets(document, *outlets):
    connections = ('            <connections>\n' + "".join(f'                <outlet property="{name}" destination="{destination}" id="out-aa-aa{number}"/>\n'
                                                           for number, (name, destination) in enumerate(outlets, 1)) + '            </connections>\n')
    return document.replace('<placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File\'s Owner"/>\n',
                            '<placeholder placeholderIdentifier="IBFilesOwner" id="-1" userLabel="File\'s Owner" customClass="Owner">\n' + connections + '        </placeholder>\n')


DONE_ITEM = '<navigationItem title="Hello" id="nvi-aa-aa1">\n    <barButtonItem key="rightBarButtonItem" style="done" systemItem="done" id="dne-aa-aa1"/>\n</navigationItem>'
XIB_OUTLET_DESTINATIONS = {
    "outlet-nav-bar-button": owner_outlets(constrained(sub_nav_bar(DONE_ITEM), ""), ("doneButton", "dne-aa-aa1")),
    "outlet-nav-bar-item": owner_outlets(constrained(sub_nav_bar(DONE_ITEM), ""), ("item", "nvi-aa-aa1")),
    "outlet-toolbar-button": owner_outlets(constrained(toolbar(items='<items>\n    <barButtonItem style="plain" systemItem="flexibleSpace" id="flx-aa-aa1"/>\n</items>'), ""), ("space", "flx-aa-aa1")),
}
EXPERIMENTS.update(XIB_OUTLET_DESTINATIONS)


# Round 115: a collection view's section header and footer views in prototypes mode: empty, with
# subviews and constraints, a custom class, an outlet to the controller, in a collection view
# controller, without a reuse identifier; the flow layout has reference sizes.
def section_view(key="sectionFooterView", identifier="sfv-aa-aa1", reuse="Footer", y=128, content="", attributes=""):
    reuse_attribute = f' reuseIdentifier="{reuse}"' if reuse else ""
    return (f'<collectionReusableView key="{key}" opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center"{reuse_attribute}{attributes} id="{identifier}">\n'
            f'    <rect key="frame" x="0.0" y="{y}" width="393" height="50"/>\n'
            '    <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>\n'
            f'{content}</collectionReusableView>\n')


SECTION_LABEL = ('    <subviews>\n        <label opaque="NO" userInteractionEnabled="NO" contentMode="left" text="Label" textAlignment="natural" '
                 'lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="sfl-aa-aa1">\n'
                 '            <rect key="frame" x="10" y="10" width="42" height="21"/>\n'
                 f'            {SYSTEM_17}\n            <nil key="textColor"/>\n            <nil key="highlightedColor"/>\n        </label>\n    </subviews>\n')
SECTION_CONSTRAINTS = ('    <constraints>\n        <constraint firstItem="sfl-aa-aa1" firstAttribute="leading" secondItem="sfv-aa-aa1" secondAttribute="leading" constant="10" id="sfc-aa-aa1"/>\n'
                       '        <constraint firstItem="sfl-aa-aa1" firstAttribute="top" secondItem="sfv-aa-aa1" secondAttribute="top" constant="10" id="sfc-aa-aa2"/>\n    </constraints>\n')
SECTION_HOLDER_OUTLET = '    <connections>\n        <outlet property="owner" destination="BYZ-38-t0r" id="sfo-aa-aa1"/>\n    </connections>\n'


def sb_sections(*views, outlets=False, sizes=True):
    document = sb_collection(sb_cv_cell("cel-aa-aa1", "Cell"), outlets=outlets)
    inner = "".join(f"                                {line}\n" for line in "".join(views).splitlines())
    document = document.replace("                                </cells>\n", "                                </cells>\n" + inner, 1)
    if sizes:
        for size in ("header", "footer"):
            document = document.replace(f'<size key="{size}ReferenceSize" width="0.0" height="0.0"/>', f'<size key="{size}ReferenceSize" width="50" height="50"/>')
    return document


SECTION_VIEWS = {
    "sb-section-footer": sb_sections(section_view()),
    "sb-section-footer-no-sizes": sb_sections(section_view(), sizes=False),
    "sb-section-header": sb_sections(section_view("sectionHeaderView", reuse="Header", y=0)),
    "sb-section-header-footer": sb_sections(section_view("sectionHeaderView", "shv-aa-aa1", "Header", 0), section_view()),
    "sb-section-footer-reversed": sb_sections(section_view("sectionHeaderView", "shv-aa-aa1", "Zzz", 0), section_view(reuse="Aaa")),
    "sb-section-footer-same-reuse": sb_sections(section_view("sectionHeaderView", "shv-aa-aa1", "Same", 0), section_view(reuse="Same")),
    "sb-section-footer-label": sb_sections(section_view(content=SECTION_LABEL)),
    "sb-section-footer-constraints": sb_sections(section_view(content=SECTION_LABEL + SECTION_CONSTRAINTS)),
    "sb-section-footer-custom": sb_sections(section_view(attributes=' customClass="Footer" customModule="T" customModuleProvider="target"', content=SECTION_LABEL + SECTION_CONSTRAINTS)),
    "sb-section-footer-no-reuse": sb_sections(section_view(reuse=None)),
    "sb-section-footer-outlet": sb_sections(section_view(attributes=' customClass="Footer" customModule="T" customModuleProvider="target"', content=SECTION_HOLDER_OUTLET), outlets=True),
    "sb-section-footer-outlets": sb_sections(section_view(), outlets=True),
    "sb-section-footer-background": sb_sections(section_view(content='    ' + gray(0.5, 1) + '\n')),
}
SECTION_VIEWS["sb-section-footer-no-cells"] = sb_collection("").replace("<cells/>\n", section_view().replace("\n", "\n                                ").rstrip(" "), 1)
SECTION_VIEWS["sb-section-footer-outlet-only"] = sb_sections(section_view(attributes=' customClass="Footer" customModule="T" customModuleProvider="target"', content=SECTION_HOLDER_OUTLET))
def cvc_sections(*views):
    inner = "".join(f"    {line}\n" for line in "".join(views).splitlines())
    return storyboard(cvc_scene(sb_cv_cell("cel-aa-aa1", "Cell")).replace("</cells>\n", "</cells>\n" + inner), initial="cvc-aa-aaa")


SECTION_VIEWS["sb-cvc-section-footer"] = cvc_sections(section_view())
SECTION_VIEWS["sb-cvc-section-footer-constraints"] = cvc_sections(section_view(content=SECTION_LABEL + SECTION_CONSTRAINTS))
SECTION_VIEWS["sb-cvc-section-header-footer"] = cvc_sections(section_view("sectionHeaderView", "shv-aa-aa1", "Header", 0), section_view())
SECTION_VIEWS["sb-cvc-section-footer-outlet"] = cvc_sections(section_view(attributes=' customClass="Footer" customModule="T" customModuleProvider="target"',
                                                                          content=SECTION_HOLDER_OUTLET.replace("BYZ-38-t0r", "cvc-aa-aaa")))
STORYBOARDS.update(SECTION_VIEWS)


# Round 116: masks in a collection view cell: on the cell, whose constraints an old cell's content view
# takes; on a current cell's content view; by size class; of subviews; in a prototype cell.
def cv_mask_constraints(container, indent=12):
    pad = " " * indent
    return (f'{pad}<constraints>\n' + constraint(0, "lll-ll-ll1", "leading", container, "leading", ' constant="4"', indent=indent + 4)
            + constraint(1, "lll-ll-ll1", "top", container, "top", ' constant="14"', indent=indent + 4)
            + constraint(2, container, "trailing", "lll-ll-ll1", "trailing", ' constant="4"', indent=indent + 4)
            + constraint(3, container, "bottom", "lll-ll-ll1", "bottom", ' constant="15"', indent=indent + 4) + f'{pad}</constraints>\n')


def cv_mask(excluded=(), key="default", verb="exclude", mask="constraints", indent=12):
    pad = " " * indent
    return (f'{pad}<variation key="{key}">\n{pad}    <mask key="{mask}">\n' + "".join(f'{pad}        <{verb} reference="{reference}"/>\n' for reference in excluded)
            + f'{pad}    </mask>\n{pad}</variation>\n')


CV_MASKS = {
    "cvmask-old-one": cv_cell(CV_LABEL, OLD_EXTRA + cv_mask_constraints(CV_CELL) + cv_mask(["c02-aa-aaa"]), old=True),
    "cvmask-old-two": cv_cell(CV_LABEL, OLD_EXTRA + cv_mask_constraints(CV_CELL) + cv_mask(["c01-aa-aaa", "c02-aa-aaa"]), old=True),
    "cvmask-old-all": cv_cell(CV_LABEL, OLD_EXTRA + cv_mask_constraints(CV_CELL) + cv_mask(["c00-aa-aaa", "c01-aa-aaa", "c02-aa-aaa", "c03-aa-aaa"]), old=True),
    "cvmask-old-no-guide": cv_cell(CV_LABEL, cv_mask_constraints(CV_CELL) + cv_mask(["c02-aa-aaa"]), old=True),
    "cvmask-old-size-class": cv_cell(CV_LABEL, OLD_EXTRA + cv_mask_constraints(CV_CELL) + cv_mask(["c02-aa-aaa"]) + cv_mask(["c02-aa-aaa"], "heightClass=regular-widthClass=compact", "include"), old=True),
    "cvmask-old-size-class-only": cv_cell(CV_LABEL, OLD_EXTRA + cv_mask_constraints(CV_CELL) + cv_mask(["c02-aa-aaa"], "heightClass=compact"), old=True),
    "cvmask-old-subviews": cv_cell(CV_LABEL, OLD_EXTRA + cv_mask(["lll-ll-ll1"], mask="subviews"), old=True),
    "cvmask-old-empty": cv_cell(CV_LABEL, OLD_EXTRA + cv_mask_constraints(CV_CELL) + cv_mask([]), old=True),
    "cvmask-new-content": cv_cell(CV_LABEL + cv_mask_constraints(CV_CONTENT, 16) + cv_mask(["c02-aa-aaa"], indent=16)),
    "cvmask-new-content-size-class": cv_cell(CV_LABEL + cv_mask_constraints(CV_CONTENT, 16) + cv_mask(["c02-aa-aaa"], indent=16) + cv_mask(["c02-aa-aaa"], "heightClass=regular-widthClass=compact", "include", indent=16)),
    "cvmask-new-on-cell": cv_cell(CV_LABEL + cv_mask_constraints(CV_CONTENT, 16), cv_mask(["c02-aa-aaa"])),
    "cvmask-new-cell-constraints": cv_cell(CV_LABEL, cv_mask_constraints(CV_CELL) + cv_mask(["c02-aa-aaa"])),
    "cvmask-new-subviews": cv_cell(CV_LABEL + cv_mask(["lll-ll-ll1"], mask="subviews", indent=16)),
}
for name, document in CV_MASKS.items():
    if name.startswith("cvmask-old-") and "no-guide" not in name:
        CV_MASKS[name] = document.replace(' useTraitCollections="YES"', ' useTraitCollections="YES" useSafeAreas="YES"').replace(
            '        <capability name="documents saved', SAFE_AREA_CAPABILITY + '        <capability name="documents saved')
CV_MASKS["mask-empty-default"] = constrained(subview("bbb-bb-bb1", (10, 10, 100, 50)), constraint(0, "bbb-bb-bb1", "leading", ROOT, "leading", ' constant="10"') + constraint(1, "bbb-bb-bb1", "top", ROOT, "top", ' constant="10"')).replace(
    '<point key="canvasLocation"', '<variation key="default">\n<mask key="constraints"/>\n</variation>\n<point key="canvasLocation"')
CV_MASKS["mask-empty-subviews"] = constrained(subview("bbb-bb-bb1", (10, 10, 100, 50)), "").replace(
    '<point key="canvasLocation"', '<variation key="default">\n<mask key="subviews"/>\n</variation>\n<point key="canvasLocation"')
CV_MASKS["mask-empty-size-class"] = constrained(subview("bbb-bb-bb1", (10, 10, 100, 50)), constraint(0, "bbb-bb-bb1", "leading", ROOT, "leading", ' constant="10"') + constraint(1, "bbb-bb-bb1", "top", ROOT, "top", ' constant="10"')).replace(
    '<point key="canvasLocation"', '<variation key="heightClass=compact">\n<mask key="constraints"/>\n</variation>\n<point key="canvasLocation"')
EXPERIMENTS.update(CV_MASKS)
SB_CV_CONSTRAINTS = ('    <constraints>\n        <constraint firstItem="cvl-aa-aa1" firstAttribute="leading" secondItem="cel-aa-aa1" secondAttribute="leading" constant="10" id="c00-aa-aaa"/>\n'
                     '        <constraint firstItem="cvl-aa-aa1" firstAttribute="top" secondItem="cel-aa-aa1" secondAttribute="top" constant="10" id="c01-aa-aaa"/>\n'
                     '        <constraint firstItem="cvl-aa-aa1" firstAttribute="trailing" secondItem="cel-aa-aa1" secondAttribute="trailing" constant="76" id="c02-aa-aaa"/>\n    </constraints>\n')


def sb_mask_cell(*variations):
    cell = sb_cv_cell("cel-aa-aa1", "Cell", label=SB_CV_LABEL)
    return sb_collection(cell.replace("</collectionViewCell>\n", SB_CV_CONSTRAINTS + "".join(variations) + "</collectionViewCell>\n"), outlets=True)


SB_CV_MASKS = {
    "sb-cvmask-one": sb_mask_cell(cv_mask(["c02-aa-aaa"], indent=4)),
    "sb-cvmask-two": sb_mask_cell(cv_mask(["c01-aa-aaa", "c02-aa-aaa"], indent=4)),
    "sb-cvmask-size-class": sb_mask_cell(cv_mask(["c02-aa-aaa"], indent=4), cv_mask(["c02-aa-aaa"], "heightClass=regular-widthClass=compact", "include", indent=4)),
    "sb-cvmask-none": sb_mask_cell(),
}
SB_CV_OWN_CONSTRAINT = SB_CV_LABEL.replace('                <rect key="frame" x="10" y="10" width="42" height="21"/>\n',
                                           '                <rect key="frame" x="10" y="10" width="42" height="21"/>\n                <constraints>\n'
                                           '                    <constraint firstAttribute="width" constant="42" id="c09-aa-aaa"/>\n                </constraints>\n')
SB_CV_HOLDER = ('        <subviews>\n            <view contentMode="scaleToFill" translatesAutoresizingMaskIntoConstraints="NO" id="hol-aa-aa1">\n'
                '                <rect key="frame" x="0.0" y="0.0" width="100" height="100"/>\n'
                + SB_CV_LABEL.replace("        <", "                <", 1).replace("        </subviews>", "                </subviews>")
                + '                <constraints>\n                    <constraint firstItem="cvl-aa-aa1" firstAttribute="leading" secondItem="hol-aa-aa1" secondAttribute="leading" constant="10" id="c08-aa-aaa"/>\n'
                '                </constraints>\n            </view>\n        </subviews>\n')
SB_CV_MASKS["sb-cvmask-own-constraint"] = sb_collection(sb_cv_cell("cel-aa-aa1", "Cell", label=SB_CV_OWN_CONSTRAINT), outlets=True)
SB_CV_MASKS["sb-cvmask-holder-constraint"] = sb_collection(sb_cv_cell("cel-aa-aa1", "Cell", label=SB_CV_HOLDER), outlets=True)
SB_CV_MASKS["sb-cvmask-holder-mask"] = sb_collection(sb_cv_cell("cel-aa-aa1", "Cell", label=SB_CV_HOLDER.replace(
    '            </view>\n        </subviews>\n', cv_mask(["c08-aa-aaa"], indent=16) + '            </view>\n        </subviews>\n')), outlets=True)
def cvc_mask_cell(*variations):
    cell = sb_mask_cell(*variations)
    start, end = cell.index("<collectionViewCell "), cell.index("</collectionViewCell>") + len("</collectionViewCell>\n")
    return storyboard(cvc_scene(cell[start:end]), initial="cvc-aa-aaa")


SB_CV_MASKS["sb-cvc-cvmask-none"] = cvc_mask_cell()
SB_CV_MASKS["sb-cvc-cvmask-one"] = cvc_mask_cell(cv_mask(["c02-aa-aaa"], indent=4))
SB_CV_MASKS["sb-cvc-cvmask-size-class"] = cvc_mask_cell(cv_mask(["c02-aa-aaa"], indent=4), cv_mask(["c02-aa-aaa"], "heightClass=regular-widthClass=compact", "include", indent=4))
STORYBOARDS.update(SB_CV_MASKS)

# Round 114: a web view's configuration, each attribute one at a time, its media types, data
# detectors and preferences, and the web view's own attributes.
def web_configured(attributes="", media='none="YES"', preferences='<wkPreferences key="preferences"/>', children="", view_attributes=""):
    return constrained(web_view(view_attributes, preferences=preferences + children).replace(
        '<wkWebViewConfiguration key="configuration">', f'<wkWebViewConfiguration key="configuration"{attributes}>').replace(
        '<audiovisualMediaTypes key="mediaTypesRequiringUserActionForPlayback" none="YES"/>',
        f'<audiovisualMediaTypes key="mediaTypesRequiringUserActionForPlayback" {media}/>'), "")


WEB_DETECTORS = ["phoneNumber", "link", "address", "calendarEvent", "trackingNumber", "flightNumber", "lookupSuggestion"]
WEB_CONFIGURATIONS = {
    "web-config-inline": web_configured(' allowsInlineMediaPlayback="YES"'),
    "web-config-inline-no": web_configured(' allowsInlineMediaPlayback="NO"'),
    "web-config-airplay-no": web_configured(' allowsAirPlayForMediaPlayback="NO"'),
    "web-config-pip-no": web_configured(' allowsPictureInPictureMediaPlayback="NO"'),
    "web-config-airplay-pip-no": web_configured(' allowsAirPlayForMediaPlayback="NO" allowsPictureInPictureMediaPlayback="NO"'),
    "web-config-incremental": web_configured(' suppressesIncrementalRendering="YES"'),
    "web-config-app-name": web_configured(' applicationNameForUserAgent="Tester"'),
    "web-config-viewport": web_configured(' ignoresViewportScaleLimits="YES"'),
    "web-config-granularity": web_configured(' selectionGranularity="character"'),
    "web-config-all": web_configured(' allowsInlineMediaPlayback="YES" allowsAirPlayForMediaPlayback="NO" allowsPictureInPictureMediaPlayback="NO" suppressesIncrementalRendering="YES"'),
    "web-media-audio": web_configured(media='audio="YES"'),
    "web-media-video": web_configured(media='video="YES"'),
    "web-media-both": web_configured(media='audio="YES" video="YES"'),
    "web-media-absent": web_configured().replace('<audiovisualMediaTypes key="mediaTypesRequiringUserActionForPlayback" none="YES"/>', ''),
    "web-detect-none": web_configured(children='\n    <dataDetectorTypes key="dataDetectorTypes" none="YES"/>'),
    "web-detect-all": web_configured(children='\n    <dataDetectorTypes key="dataDetectorTypes" ' + " ".join(f'{name}="YES"' for name in WEB_DETECTORS) + '/>'),
    "web-prefs-popups": web_configured(preferences='<wkPreferences key="preferences" javaScriptCanOpenWindowsAutomatically="YES"/>'),
    "web-prefs-no-js": web_configured(preferences='<wkPreferences key="preferences" javaScriptEnabled="NO"/>'),
    "web-prefs-font-popups": web_configured(preferences='<wkPreferences key="preferences" minimumFontSize="6" javaScriptCanOpenWindowsAutomatically="YES"/>'),
    "web-view-gestures": web_configured(view_attributes=' allowsBackForwardNavigationGestures="YES"'),
    "web-view-no-preview": web_configured(view_attributes=' allowsLinkPreview="NO"'),
    "web-view-agent": web_configured(view_attributes=' customUserAgent="Agent"'),
    "web-view-agent-and-name": web_configured(' applicationNameForUserAgent="Tester"', view_attributes=' customUserAgent="Agent"'),
}
WEB_CONFIGURATIONS.update({f"web-detect-{name.lower()}": web_configured(children=f'\n    <dataDetectorTypes key="dataDetectorTypes" {name}="YES"/>') for name in WEB_DETECTORS})
WEB_MORE = {
    "web-config-granularity-dynamic": web_configured(' selectionGranularity="dynamic"'),
    "web-config-airplay-yes": web_configured(' allowsAirPlayForMediaPlayback="YES"'),
    "web-config-pip-yes": web_configured(' allowsPictureInPictureMediaPlayback="YES"'),
    "web-config-incremental-no": web_configured(' suppressesIncrementalRendering="NO"'),
    "web-config-viewport-no": web_configured(' ignoresViewportScaleLimits="NO"'),
    "web-config-app-name-empty": web_configured(' applicationNameForUserAgent=""'),
    "web-prefs-js-yes": web_configured(preferences='<wkPreferences key="preferences" javaScriptEnabled="YES"/>'),
    "web-prefs-popups-no": web_configured(preferences='<wkPreferences key="preferences" javaScriptCanOpenWindowsAutomatically="NO"/>'),
    "web-view-agent-empty": web_configured(view_attributes=' customUserAgent=""'),
    "web-view-gestures-no": web_configured(view_attributes=' allowsBackForwardNavigationGestures="NO"'),
    "web-view-preview-yes": web_configured(view_attributes=' allowsLinkPreview="YES"'),
    "web-detect-two": web_configured(children='\n    <dataDetectorTypes key="dataDetectorTypes" phoneNumber="YES" link="YES"/>'),
    "web-detect-element-empty": web_configured(children='\n    <dataDetectorTypes key="dataDetectorTypes"/>'),
    "web-same-agent-and-name": web_configured(' applicationNameForUserAgent="Same"', view_attributes=' customUserAgent="Same"'),
}
WEB_CONFIGURATIONS.update(WEB_MORE)
EXPERIMENTS.update(WEB_CONFIGURATIONS)



# Round 115: labels' shadow offsets and colors, minimum font sizes with adjustsFontSizeToFit="NO", and
# named fonts: every family iOS ships, an unknown font and a family not the font's.
def shadowed(offset=None, color=""):
    size = f'<size key="shadowOffset" width="{offset[0]}" height="{offset[1]}"/>\n' if offset else ""
    return constrained(label(extra=color + size), "")


SHADOW_WHITE = '<color key="shadowColor" white="1" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>\n'
LABEL_NO_FIT = LABEL_ATTRIBUTES.replace(' adjustsFontSizeToFit="NO"', "")
LABEL_SHADOWS = {
    "label-shadow-0-1": shadowed(("0.0", "1")),
    "label-shadow-0-0": shadowed(("0.0", "0.0")),
    "label-shadow-0-minus-1": shadowed(("0.0", "-1")),
    "label-shadow-minus-1": shadowed(("-1", "-1")),
    "label-shadow-0-2": shadowed(("0.0", "2")),
    "label-shadow-fraction": shadowed(("1.5", "2.5")),
    "label-shadow-color": shadowed(color=SHADOW_WHITE),
    "label-shadow-color-offset": shadowed(("0.0", "1"), SHADOW_WHITE),
    "label-min-20-no": constrained(label(LABEL_ATTRIBUTES + ' minimumFontSize="20"'), ""),
    "label-min-10-no": constrained(label(LABEL_ATTRIBUTES + ' minimumFontSize="10"'), ""),
    "label-min-0-no": constrained(label(LABEL_ATTRIBUTES + ' minimumFontSize="0.0"'), ""),
    "label-min-12-5-no": constrained(label(LABEL_ATTRIBUTES + ' minimumFontSize="12.5"'), ""),
    "label-min-20-yes": constrained(label(LABEL_ATTRIBUTES.replace('adjustsFontSizeToFit="NO"', 'adjustsFontSizeToFit="YES"') + ' minimumFontSize="20"'), ""),
    "label-min-20-absent": constrained(label(LABEL_NO_FIT + ' minimumFontSize="20"'), ""),
    "label-min-20-no-style": constrained(label(LABEL_ATTRIBUTES + ' minimumFontSize="20"', font='<fontDescription key="fontDescription" style="UICTFontTextStyleBody"/>'), ""),
    "label-min-20-yes-style": constrained(label(LABEL_ATTRIBUTES.replace('adjustsFontSizeToFit="NO"', 'adjustsFontSizeToFit="YES"') + ' minimumFontSize="20"',
                                                font='<fontDescription key="fontDescription" style="UICTFontTextStyleBody"/>'), ""),
    "label-scale-half-no": constrained(label(LABEL_ATTRIBUTES + ' minimumScaleFactor="0.5"'), ""),
    "label-min-and-scale-no": constrained(label(LABEL_ATTRIBUTES + ' minimumFontSize="10" minimumScaleFactor="0.5"'), ""),
    "label-min-and-scale-yes": constrained(label(LABEL_NO_FIT + ' minimumFontSize="10" minimumScaleFactor="0.5"'), ""),
}
LABEL_SHADOWS.update({
    "label-min-17-yes": constrained(label(LABEL_NO_FIT + ' minimumFontSize="17"'), ""),
    "label-min-20-two": constrained(label(LABEL_NO_FIT + ' minimumFontSize="20"') + label(LABEL_NO_FIT + ' minimumFontSize="20"', identifier="zzz-zz-zz2", frame=(20, 80, 42, 21))
                                    + label(LABEL_NO_FIT + ' minimumFontSize="30"', identifier="mmm-mm-mm3", frame=(20, 120, 42, 21)), ""),
    "label-min-20-old-document": constrained(label(LABEL_NO_FIT + ' minimumFontSize="20"'), "").replace('<deployment identifier="iOS"/>', '<deployment version="5376" identifier="iOS"/>'),
    "label-scale-over-one": constrained(label(LABEL_NO_FIT + ' minimumScaleFactor="1.5"'), ""),
})
EXPERIMENTS.update(LABEL_SHADOWS)
STORYBOARDS["sb-label-min-20"] = storyboard(controller_scene(1, view_extra="                        <subviews>\n" + label(LABEL_NO_FIT + ' minimumFontSize="20"').replace("                ", "                            ")
                                                             + "                        </subviews>\n"), initial="vc1-aa-aaa")
STORYBOARDS["sb-label-min-20-and-push"] = storyboard(navigation_scene("vc1-aa-aaa"), controller_scene(1, connections='                        <segue destination="vc2-aa-aaa" kind="push" identifier="Go" id="psh-aa-aa1"/>\n',
                                                     view_extra="                        <subviews>\n" + label(LABEL_NO_FIT + ' minimumFontSize="20"').replace("                ", "                            ")
                                                     + "                        </subviews>\n"), controller_scene(2), initial="nvc-aa-aaa")
IOS_FONTS = """AcademyEngravedLetPlain AlNile AlNile-Bold AmericanTypewriter AmericanTypewriter-Bold AmericanTypewriter-Condensed AmericanTypewriter-CondensedBold
AmericanTypewriter-CondensedLight AmericanTypewriter-Light AmericanTypewriter-Semibold AppleColorEmoji AppleSDGothicNeo-Bold AppleSDGothicNeo-Light AppleSDGothicNeo-Medium
AppleSDGothicNeo-Regular AppleSDGothicNeo-SemiBold AppleSDGothicNeo-Thin AppleSDGothicNeo-UltraLight Arial-BoldItalicMT Arial-BoldMT Arial-ItalicMT ArialHebrew ArialHebrew-Bold
ArialHebrew-Light ArialMT ArialRoundedMTBold Avenir-Black Avenir-BlackOblique Avenir-Book Avenir-BookOblique Avenir-Heavy Avenir-HeavyOblique Avenir-Light Avenir-LightOblique
Avenir-Medium Avenir-MediumOblique Avenir-Oblique Avenir-Roman AvenirNext-Bold AvenirNext-BoldItalic AvenirNext-DemiBold AvenirNext-DemiBoldItalic AvenirNext-Heavy
AvenirNext-HeavyItalic AvenirNext-Italic AvenirNext-Medium AvenirNext-MediumItalic AvenirNext-Regular AvenirNext-UltraLight AvenirNext-UltraLightItalic AvenirNextCondensed-Bold
AvenirNextCondensed-BoldItalic AvenirNextCondensed-DemiBold AvenirNextCondensed-Heavy AvenirNextCondensed-Italic AvenirNextCondensed-Medium AvenirNextCondensed-Regular
AvenirNextCondensed-UltraLight Baskerville Baskerville-Bold Baskerville-BoldItalic Baskerville-Italic Baskerville-SemiBold Baskerville-SemiBoldItalic BodoniOrnamentsITCTT
BodoniSvtyTwoITCTT-Bold BodoniSvtyTwoITCTT-Book BodoniSvtyTwoITCTT-BookIta BodoniSvtyTwoOSITCTT-Bold BodoniSvtyTwoOSITCTT-Book BodoniSvtyTwoSCITCTT-Book BradleyHandITCTT-Bold
ChalkboardSE-Bold ChalkboardSE-Light ChalkboardSE-Regular Chalkduster Cochin Cochin-Bold Cochin-BoldItalic Cochin-Italic Copperplate Copperplate-Bold Copperplate-Light Courier
Courier-Bold Courier-BoldOblique Courier-Oblique CourierNewPS-BoldItalicMT CourierNewPS-BoldMT CourierNewPS-ItalicMT CourierNewPSMT DINAlternate-Bold DINCondensed-Bold Damascus
DamascusBold DamascusLight DamascusMedium DamascusSemiBold DevanagariSangamMN DevanagariSangamMN-Bold Didot Didot-Bold Didot-Italic DiwanMishafi EuphemiaUCAS EuphemiaUCAS-Bold
EuphemiaUCAS-Italic Farah Futura-Bold Futura-CondensedExtraBold Futura-CondensedMedium Futura-Medium Futura-MediumItalic GeezaPro GeezaPro-Bold Georgia Georgia-Bold
Georgia-BoldItalic Georgia-Italic GillSans GillSans-Bold GillSans-BoldItalic GillSans-Italic GillSans-Light GillSans-LightItalic GillSans-SemiBold GillSans-SemiBoldItalic
GillSans-UltraBold GujaratiSangamMN GujaratiSangamMN-Bold GurmukhiMN GurmukhiMN-Bold Helvetica Helvetica-Bold Helvetica-BoldOblique Helvetica-Light Helvetica-LightOblique
Helvetica-Oblique HelveticaNeue HelveticaNeue-Bold HelveticaNeue-BoldItalic HelveticaNeue-CondensedBlack HelveticaNeue-CondensedBold HelveticaNeue-Italic HelveticaNeue-Light
HelveticaNeue-LightItalic HelveticaNeue-Medium HelveticaNeue-MediumItalic HelveticaNeue-Thin HelveticaNeue-ThinItalic HelveticaNeue-UltraLight HelveticaNeue-UltraLightItalic
HiraMaruProN-W4 HiraMinProN-W3 HiraMinProN-W6 HiraginoSans-W3 HiraginoSans-W6 HiraginoSans-W7 HoeflerText-Black HoeflerText-BlackItalic HoeflerText-Italic HoeflerText-Regular
Kailasa Kailasa-Bold KannadaSangamMN KannadaSangamMN-Bold KhmerSangamMN KohinoorBangla-Light KohinoorBangla-Regular KohinoorBangla-Semibold KohinoorDevanagari-Light
KohinoorDevanagari-Regular KohinoorDevanagari-Semibold KohinoorTelugu-Light KohinoorTelugu-Medium KohinoorTelugu-Regular LaoSangamMN MalayalamSangamMN MalayalamSangamMN-Bold
MarkerFelt-Thin MarkerFelt-Wide Menlo-Bold Menlo-BoldItalic Menlo-Italic Menlo-Regular MuktaMahee-Bold MuktaMahee-Light MuktaMahee-Regular NotoNastaliqUrdu NotoNastaliqUrdu-Bold
NotoSansKannada-Regular NotoSansMyanmar-Regular NotoSansOriya Noteworthy-Bold Noteworthy-Light Optima-Bold Optima-BoldItalic Optima-ExtraBlack Optima-Italic Optima-Regular
OriyaSangamMN Palatino-Bold Palatino-BoldItalic Palatino-Italic Palatino-Roman Papyrus Papyrus-Condensed PartyLetPlain PingFangHK-Regular PingFangSC-Light PingFangSC-Medium
PingFangSC-Regular PingFangSC-Semibold PingFangSC-Thin PingFangSC-Ultralight PingFangTC-Regular Rockwell-Bold Rockwell-BoldItalic Rockwell-Italic Rockwell-Regular SavoyeLetPlain
SinhalaSangamMN SinhalaSangamMN-Bold SnellRoundhand SnellRoundhand-Black SnellRoundhand-Bold Symbol TamilSangamMN TamilSangamMN-Bold TeluguSangamMN Thonburi Thonburi-Bold
Thonburi-Light TimesNewRomanPS-BoldItalicMT TimesNewRomanPS-BoldMT TimesNewRomanPS-ItalicMT TimesNewRomanPSMT Trebuchet-BoldItalic TrebuchetMS TrebuchetMS-Bold TrebuchetMS-Italic
Verdana Verdana-Bold Verdana-BoldItalic Verdana-Italic ZapfDingbatsITC Zapfino
.SFUI-Regular .SFUI-RegularItalic .SFUI-Semibold AppleSymbols AvenirNextCondensed-DemiBoldItalic AvenirNextCondensed-HeavyItalic AvenirNextCondensed-MediumItalic
AvenirNextCondensed-UltraLightItalic BodoniSvtyTwoOSITCTT-BookIt Charter-Black Charter-BlackItalic Charter-Bold Charter-BoldItalic Charter-Italic Charter-Roman Galvji
Galvji-Bold GranthaSangamMN-Bold GranthaSangamMN-Regular HiraKakuProN-W3 HiraginoSans-W4 HiraginoSans-W5 HiraginoSans-W8 Impact KefaIII-Bold KefaIII-ExtraBold
KefaIII-Light KefaIII-Regular KohinoorGujarati-Bold KohinoorGujarati-Light KohinoorGujarati-Regular MyanmarSangamMN MyanmarSangamMN-Bold NotoSansKannada-Bold
NotoSansKannada-Light NotoSansMyanmar-Bold NotoSansMyanmar-Light NotoSansOriya-Bold NotoSansSyriac-Regular NotoSansSyriac-Regular_Black NotoSansSyriac-Regular_Bold
NotoSansSyriac-Regular_ExtraBold NotoSansSyriac-Regular_ExtraLight NotoSansSyriac-Regular_Light NotoSansSyriac-Regular_Medium NotoSansSyriac-Regular_SemiBold
NotoSansSyriac-Regular_Thin PingFangHK-Light PingFangHK-Medium PingFangHK-Semibold PingFangHK-Thin PingFangHK-Ultralight PingFangMO-Light PingFangMO-Medium
PingFangMO-Regular PingFangMO-Semibold PingFangMO-Thin PingFangMO-Ultralight PingFangTC-Light PingFangTC-Medium PingFangTC-Semibold PingFangTC-Thin PingFangTC-Ultralight
STHeitiSC-Light STIXTwoMath-Regular STIXTwoText STIXTwoText-Italic STIXTwoText-Italic_Bold-Italic STIXTwoText-Italic_Medium-Italic STIXTwoText-Italic_SemiBold-Italic
STIXTwoText_Bold STIXTwoText_Medium STIXTwoText_SemiBold""".split()


def named_font(name, family=None, size="16"):
    return f'<fontDescription key="fontDescription" name="{name}" family="{family or name.split("-")[0]}" pointSize="{size}"/>'


NAMED_FONTS = {f"label-named-{name.lower()}": constrained(label(font=named_font(name)), "") for name in IOS_FONTS}
NAMED_FONTS.update({
    "label-named-helvetica-size-17": constrained(label(font=named_font("Helvetica", "Helvetica", "17")), ""),
    "label-named-helvetica-size-fraction": constrained(label(font=named_font("Helvetica", "Helvetica", "16.5")), ""),
    "label-named-helvetica-wrong-family": constrained(label(font=named_font("Helvetica", "Arial")), ""),
    "label-named-helvetica-15": constrained(label(font=named_font("Helvetica")), ""),
    "label-named-unknown-15": constrained(label(font=named_font("NotAFont-Regular", "NotAFont")), ""),
    "label-named-sfns": constrained(label(font=named_font(".SFNS-Regular", ".SF NS")), ""),
    "label-named-unknown": constrained(label(font=named_font("NotAFont-Regular", "NotAFont")), ""),
    "label-named-stheitisc-medium-alias": constrained(label(font=named_font("STHeitiSC-Medium")), ""),
    "label-named-stheititc-light-alias": constrained(label(font=named_font("STHeitiTC-Light")), ""),
    "label-named-stheititc-medium-alias": constrained(label(font=named_font("STHeitiTC-Medium")), ""),
    "label-named-lowercase": constrained(label(font=named_font("helvetica")), ""),
    "label-named-display-name": constrained(label(font=named_font("Helvetica Neue", "Helvetica Neue")), ""),
    "label-named-display-name-bold": constrained(label(font=named_font("Helvetica Neue Bold", "Helvetica Neue")), ""),
    "label-named-times-new-roman": constrained(label(font=named_font("Times New Roman", "Times New Roman")), ""),
    "label-named-arial-family": constrained(label(font=named_font("Arial", "Arial")), ""),
    "label-named-unknown-bold": constrained(label(font=named_font("NotAFont-Bold", "NotAFont")), ""),
    "label-named-two-sizes": constrained(label(font=named_font("Helvetica")) + label(font=named_font("Helvetica", "Helvetica", "18"), identifier="lll-ll-ll2", frame=(20, 80, 42, 21)), ""),
})
NAMED_FONTS["label-named-custom-listed"] = constrained(label(font=named_font("MyApp-Bold", "MyApp")), "").replace(
    "<objects>", '<customFonts key="customFonts">\n<array key="MyApp-Bold.ttf">\n<string>MyApp-Bold</string>\n</array>\n</customFonts>\n<objects>', 1)
OPTIONS.update({"label-named-helvetica-15": {"deployment": "15.0", "devices": ["iphone", "ipad"]}, "label-named-unknown-15": {"deployment": "15.0", "devices": ["iphone", "ipad"]}})
EXPERIMENTS.update(NAMED_FONTS)


# Round 117 (B-290): the objects holding runtime attributes against the decimal strings of their
# places in all objects plus one, with the root, File's Owner and first responder's neighbors beside
# deep objects, and past 2, 3 and 4 digits.
def root_pairs(document):
    return document.replace('            <point key="canvasLocation"', "".join(
        f"            {line}\n" for line in runtime(udra("root", "string", "r")).splitlines()) + '            <point key="canvasLocation"', 1)


def owner_pairs(document):
    return document.replace('userLabel="File\'s Owner"/>', 'userLabel="File\'s Owner">\n            '
                            + runtime(udra("owner", "string", "o")).replace("\n", "\n            ").rstrip() + '\n        </placeholder>')


for count in (2, 8, 9, 10, 11, 20, 28, 29, 30, 40, 120):
    EXPERIMENTS[f"udra-order-root-many-{count}"] = root_pairs(many_pairs(count))
for count in (2, 10, 20, 120):
    EXPERIMENTS[f"udra-order-owner-many-{count}"] = owner_pairs(many_pairs(count))
    EXPERIMENTS[f"udra-order-owner-root-many-{count}"] = owner_pairs(root_pairs(many_pairs(count)))
for count, every in ((97, 1), (98, 1), (99, 1), (100, 1), (120, 1), (200, 7), (1100, 37)):
    EXPERIMENTS[f"udra-order-many-{count}" + (f"-every-{every}" if every > 1 else "")] = many_pairs(count, every=every)


# Round 118: actions of one selector and event from several controls: what orders them, of the
# document's order, the controls' ids and frames and the actions' ids.
def same_selector(*buttons, selector="tapped:", event="touchUpInside"):
    """Buttons of (id, x, action id), in document order."""
    views = ""
    for identifier, x, action in buttons:
        views += subview(identifier, (x, 20, 50, 30), tag="button", attributes=' opaque="NO" contentHorizontalAlignment="center" contentVerticalAlignment="center" '
                         'buttonType="system" lineBreakMode="middleTruncation"').replace("                </button>", (
                             f'                    <connections>\n                        <action selector="{selector}" destination="-1" eventType="{event}" id="{action}"/>\n'
                             "                    </connections>\n                </button>"))
    return constrained(views, "")


SAME_SELECTOR = {
    "act-same-plain": same_selector(("aaa-aa-aa1", 0, "ac1-aa-aa1"), ("bbb-bb-bb1", 60, "ac2-aa-aa1")),
    "act-same-action-ids-swapped": same_selector(("aaa-aa-aa1", 0, "ac2-aa-aa1"), ("bbb-bb-bb1", 60, "ac1-aa-aa1")),
    "act-same-button-ids-swapped": same_selector(("bbb-bb-bb1", 0, "ac1-aa-aa1"), ("aaa-aa-aa1", 60, "ac2-aa-aa1")),
    "act-same-frames-swapped": same_selector(("aaa-aa-aa1", 60, "ac1-aa-aa1"), ("bbb-bb-bb1", 0, "ac2-aa-aa1")),
    "act-same-three": same_selector(("aaa-aa-aa1", 0, "ac1-aa-aa1"), ("bbb-bb-bb1", 60, "ac2-aa-aa1"), ("ccc-cc-cc1", 120, "ac3-aa-aa1")),
    "act-same-three-a": same_selector(("aaa-aa-aa1", 0, "ac3-aa-aa1"), ("bbb-bb-bb1", 60, "ac1-aa-aa1"), ("ccc-cc-cc1", 120, "ac2-aa-aa1")),
    "act-same-three-b": same_selector(("aaa-aa-aa1", 0, "ac2-aa-aa1"), ("bbb-bb-bb1", 60, "ac3-aa-aa1"), ("ccc-cc-cc1", 120, "ac1-aa-aa1")),
    "act-same-three-ids": same_selector(("ccc-cc-cc1", 0, "ac1-aa-aa1"), ("aaa-aa-aa1", 60, "ac2-aa-aa1"), ("bbb-bb-bb1", 120, "ac3-aa-aa1")),
    "act-same-three-upper": same_selector(("aaa-aa-aa1", 0, "zzz-aa-aa1"), ("bbb-bb-bb1", 60, "ZZZ-aa-aa1"), ("ccc-cc-cc1", 120, "000-aa-aa1")),
    "act-same-seven": same_selector(*[(f"b{k}k-aa-aa1", 50 * k, f"{'qwertyu'[k]}c{k}-aa-aa1") for k in range(7)]),
    "act-same-twelve": same_selector(*[(f"b{k:02d}-aa-aa1", 20 * k, f"{'qwertyuiopas'[k]}c{k % 10}-aa-aa1") for k in range(12)]),
}
EXPERIMENTS.update(SAME_SELECTOR)


def same_nested(*containers, constraints=""):
    """Containers of (id, y, [buttons]) of (id, x) buttons, each with one action of one selector, in document order."""
    views = ""
    for identifier, y, buttons in containers:
        inner = ""
        for button_id, x in buttons:
            inner += ("    " + subview(button_id, (x, 5, 50, 30), tag="button", attributes=' opaque="NO" contentHorizontalAlignment="center" contentVerticalAlignment="center" '
                                       'buttonType="system" lineBreakMode="middleTruncation"').replace("                </button>", (
                                           '                    <connections>\n                        <action selector="tapped:" destination="-1" eventType="touchUpInside" '
                                           f'id="a{button_id[:2]}-aa-aa1"/>\n                    </connections>\n                </button>')))
        views += subview(identifier, (0, y, 300, 50)).replace("                </view>", f"                    <subviews>\n{inner}                    </subviews>\n                </view>")
    return constrained(views, constraints)


SAME_NESTED = {
    "act-same-nested-three": same_nested(("c1c-aa-aa1", 0, [("b1b-aa-aa1", 0)]), ("c2c-aa-aa1", 60, [("b2b-aa-aa1", 0)]), ("c3c-aa-aa1", 120, [("b3b-aa-aa1", 0)])),
    "act-same-nested-two": same_nested(("c1c-aa-aa1", 0, [("b1b-aa-aa1", 0)]), ("c2c-aa-aa1", 60, [("b2b-aa-aa1", 0)])),
    "act-same-nested-three-two-each": same_nested(("c1c-aa-aa1", 0, [("b1b-aa-aa1", 0), ("b4b-aa-aa1", 60)]), ("c2c-aa-aa1", 60, [("b2b-aa-aa1", 0), ("b5b-aa-aa1", 60)]),
                                                  ("c3c-aa-aa1", 120, [("b3b-aa-aa1", 0), ("b6b-aa-aa1", 60)])),
    "act-same-nested-three-y-reversed": same_nested(("c1c-aa-aa1", 120, [("b1b-aa-aa1", 0)]), ("c2c-aa-aa1", 60, [("b2b-aa-aa1", 0)]), ("c3c-aa-aa1", 0, [("b3b-aa-aa1", 0)])),
}
SAME_NESTED["act-same-nested-three-pinned"] = same_nested(("c1c-aa-aa1", 0, [("b1b-aa-aa1", 0)]), ("c2c-aa-aa1", 60, [("b2b-aa-aa1", 0)]), ("c3c-aa-aa1", 120, [("b3b-aa-aa1", 0)]),
                                                          constraints="".join(constraint(k, f"c{k}c-aa-aa1", "top", "iN0-l3-epB", "top", f' constant="{(k - 1) * 60}"') for k in (1, 2, 3)))
EXPERIMENTS.update(SAME_NESTED)


CONTROL_TAGS = {"button": ' opaque="NO" contentHorizontalAlignment="center" contentVerticalAlignment="center" buttonType="system" lineBreakMode="middleTruncation"',
                "slider": ' opaque="NO" contentHorizontalAlignment="center" contentVerticalAlignment="center" value="0.5" minValue="0.0" maxValue="1"',
                "switch": ' opaque="NO" contentHorizontalAlignment="center" contentVerticalAlignment="center" on="YES"',
                "view": ""}


def mixed_control(tag, number, x, custom=None, selector="tapped:", event="valueChanged"):
    classes = f' customClass="{custom}" customModule="T" customModuleProvider="target"' if custom else ""
    return subview(f"c{number}c-aa-aa1", (x, 20, 50, 30), tag=tag, attributes=CONTROL_TAGS[tag] + classes).replace(f"                </{tag}>", (
        f'                    <connections>\n                        <action selector="{selector}" destination="-1" eventType="{event}" id="a{number}a-aa-aa1"/>\n'
        f"                    </connections>\n                </{tag}>"))


# Of one selector and event, by class first? Controls of several classes, in both document orders,
# and custom classes whose mangled names sort apart from their original classes'.
SAME_CLASSES = {
    "act-same-classes-button-slider": constrained(mixed_control("button", 1, 0) + mixed_control("slider", 2, 60), ""),
    "act-same-classes-slider-button": constrained(mixed_control("slider", 1, 0) + mixed_control("button", 2, 60), ""),
    "act-same-classes-switch-slider-button": constrained(mixed_control("switch", 1, 0) + mixed_control("slider", 2, 60) + mixed_control("button", 3, 120), ""),
    "act-same-classes-custom-plain": constrained(mixed_control("button", 1, 0, "Zed") + mixed_control("button", 2, 60), ""),
    "act-same-classes-plain-custom": constrained(mixed_control("button", 1, 0) + mixed_control("button", 2, 60, "Zed"), ""),
    "act-same-classes-custom-slider": constrained(mixed_control("slider", 1, 0) + mixed_control("button", 2, 60, "Zed"), ""),
    "act-same-classes-view-button": constrained(mixed_control("view", 1, 0, "Pad") + mixed_control("button", 2, 60), ""),
    "act-same-classes-button-view": constrained(mixed_control("button", 1, 0) + mixed_control("view", 2, 60, "Pad"), ""),
}
EXPERIMENTS.update(SAME_CLASSES)


def same_scene(subviews):
    """A storyboard scene of the given subviews, whose actions go to its controller."""
    return storyboard(scene(view_extra="                        <subviews>\n" + subviews.replace('destination="-1"', 'destination="BYZ-38-t0r"')
                            + "                        </subviews>\n"))


def same_tree(children, prefix="n", event="touchUpInside", selector="tapped:"):
    """A tree of containers and buttons: a child is a button's number, or a list of children of a container."""
    text = ""
    for index, child in enumerate(children):
        if isinstance(child, int):
            text += mixed_control("button", child, 10 * index, event=event, selector=selector).replace(f"c{child}c-aa-aa1", f"b{child:02d}-aa-aa1").replace(
                f"a{child}a-aa-aa1", f"a{child:02d}-aa-aa1")
        else:
            identifier = f"{prefix}{index}" + "x" * (3 - len(prefix) - 1) if len(prefix) < 3 else f"{prefix[:2]}{index}"
            text += subview(f"{identifier}-aa-aa1", (0, 60 * index, 300, 50)).replace(
                "                </view>", "                    <subviews>\n" + same_tree(child, prefix + str(index), event, selector) + "                    </subviews>\n                </view>")
    return text


TREES = {"flat": [1, 2, 3], "nested": [[1], [2], [3]], "button-then-nested": [1, [2], 3], "nested-then-button": [[1], 2], "deep": [[[1], [2]], [[3], [4]]],
         "mixed": [[1, [2, 3], 4], 5, [[6], 7], 8], "shallow-after": [[[1]], 2, [3]], "wide": [[1, 2, 3], [4, 5, 6], [7, 8, 9]]}
for name, tree in TREES.items():
    STORYBOARDS[f"sb-act-same-{name}"] = same_scene(same_tree(tree))
    EXPERIMENTS[f"act-same-tree-{name}"] = constrained(same_tree(tree), "")
for name, controls in {"button-slider": mixed_control("button", 1, 0) + mixed_control("slider", 2, 60),
                       "slider-button": mixed_control("slider", 1, 0) + mixed_control("button", 2, 60),
                       "custom-plain": mixed_control("button", 1, 0, "Zed") + mixed_control("button", 2, 60),
                       "plain-custom": mixed_control("button", 1, 0) + mixed_control("button", 2, 60, "Zed")}.items():
    STORYBOARDS[f"sb-act-same-classes-{name}"] = same_scene(controls)


# Round 119: the same walk for outlets of one name, top-level objects, and recognizers of one class.
for name, tree in TREES.items():
    outlets = re.sub(r'<action selector="tapped:" destination="-1" eventType="touchUpInside" id="(a\d\d-aa-aa1)"/>', r'<outlet property="delegate" destination="-1" id="\1"/>', same_tree(tree))
    EXPERIMENTS[f"outlet-same-tree-{name}"] = constrained(outlets, "")
    STORYBOARDS[f"sb-outlet-same-tree-{name}"] = same_scene(outlets)


def top_views(*trees):
    roots = ""
    for number, tree in enumerate(trees):
        roots += (f'        <view contentMode="scaleToFill" id="rt{number}-aa-aa1">\n            <rect key="frame" x="0" y="0" width="393" height="852"/>\n'
                  f'            <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>\n            <subviews>\n{tree}            </subviews>\n'
                  '            <point key="canvasLocation" x="0" y="0"/>\n        </view>\n')
    return xib(roots)


EXPERIMENTS["act-same-top-two"] = top_views(mixed_control("button", 1, 0, event="touchUpInside"), mixed_control("button", 2, 0, event="touchUpInside"))
EXPERIMENTS["act-same-top-three"] = top_views(mixed_control("button", 1, 0, event="touchUpInside"), mixed_control("button", 2, 0, event="touchUpInside"),
                                              mixed_control("button", 3, 0, event="touchUpInside"))
EXPERIMENTS["act-same-top-nested"] = top_views(same_tree([[1], 2]), same_tree([3, [4]]))
GESTURE_TWO_TAPS = gestures(recognizer() + recognizer(identifier="tbp-aa-aa1").replace("act-tbp-aa1", "act-tbp-aa2"), attach=())
EXPERIMENTS["gesture-two-taps"] = GESTURE_TWO_TAPS
EXPERIMENTS["gesture-three-taps"] = gestures(recognizer() + recognizer(identifier="tbp-aa-aa1") + recognizer(identifier="tcp-aa-aa1"), attach=())
EXPERIMENTS["gesture-two-one-connections"] = gestures(recognizer() + recognizer(identifier="tbp-aa-aa1"), attach=(("sss-ss-ss1", "tap-aa-aa1"),)).replace(
    '<outletCollection property="gestureRecognizers" destination="tap-aa-aa1" appends="YES" id="grtap-aa-aa1"/>',
    '<outletCollection property="gestureRecognizers" destination="tap-aa-aa1" appends="YES" id="grtap-aa-aa1"/>\n'
    '                        <outletCollection property="gestureRecognizers" destination="tbp-aa-aa1" appends="YES" id="grtbp-aa-aa1"/>')
EXPERIMENTS["gesture-two-one-connections-reversed"] = gestures(recognizer() + recognizer(identifier="tbp-aa-aa1"), attach=(("sss-ss-ss1", "tbp-aa-aa1"),)).replace(
    '<outletCollection property="gestureRecognizers" destination="tbp-aa-aa1" appends="YES" id="grtbp-aa-aa1"/>',
    '<outletCollection property="gestureRecognizers" destination="tbp-aa-aa1" appends="YES" id="grtbp-aa-aa1"/>\n'
    '                        <outletCollection property="gestureRecognizers" destination="tap-aa-aa1" appends="YES" id="grtap-aa-aa1"/>')
EXPERIMENTS["gesture-two-taps-attached"] = gestures(recognizer() + recognizer(identifier="tbp-aa-aa1"), attach=(("sss-ss-ss1", "tap-aa-aa1"), ("sss-ss-ss1", "tbp-aa-aa1")))
# Colors in documents without colorMatched, and system colors that also write components: the color
# spaces' grids and ramps, how ibtool converts each (BACKLOG B-281).
def custom_space(space):
    return f'colorSpace="{space}"' if space in ("calibratedRGB", "deviceRGB", "calibratedWhite", "deviceWhite") else f'colorSpace="custom" customColorSpace="{space}"'


def color_subviews(colors):
    return "".join(subview(f"cnv-{index:03d}-aa", (0, index, 10, 1)).replace("</view>", f'    <color key="backgroundColor" {color}/>\n                </view>')
                   for index, color in enumerate(colors))


def rgb_grid(space):
    return [f'red="{r}" green="{g}" blue="{b}" alpha="1" {custom_space(space)}' for _, r, g, b, _ in color_grid(space)]


_WHITE_RAMP = [f'{n / 20:g}' for n in range(21)] + ["0.33333333333333331", "0.66666666666666663", "0.96999999999999997", "0.1234567"]
WHITE_SPACES = ("calibratedWhite", "deviceWhite", "genericGamma22GrayColorSpace")
COLOR_ROUTES = {f"unmatched-grid-{space}": constrained(color_subviews(rgb_grid(space)), "").replace(' colorMatched="YES"', "")
                for space in ("calibratedRGB", "sRGB", "displayP3", "deviceRGB")}
for _space in WHITE_SPACES:
    _ramp = [f'white="{w}" alpha="1" {custom_space(_space)}' for w in _WHITE_RAMP] + [f'white="0.25" alpha="{a}" {custom_space(_space)}' for a in ("0", "0.25", "0.5", "0.75")]
    COLOR_ROUTES[f"unmatched-ramp-{_space}"] = constrained(color_subviews(_ramp), "").replace(' colorMatched="YES"', "")
    COLOR_ROUTES[f"matched-ramp-{_space}"] = constrained(color_subviews(_ramp), "")
COLOR_ROUTES["unmatched-alpha-calibratedRGB"] = constrained(color_subviews(
    [f'red="0.25" green="0.5" blue="0.75" alpha="{a}" colorSpace="calibratedRGB"' for a in ("0", "0.25", "0.5", "0.75", "1")]), "").replace(' colorMatched="YES"', "")
for _name, _attributes in {
    "secondary-srgb": 'systemColor="secondaryLabelColor" red="0.2" green="0.4" blue="0.6" alpha="0.7" colorSpace="custom" customColorSpace="sRGB"',
    "secondary-srgb-other": 'systemColor="secondaryLabelColor" red="0.9" green="0.1" blue="0.3" alpha="0.5" colorSpace="custom" customColorSpace="sRGB"',
    "gray-srgb": 'systemColor="systemGrayColor" red="0.55686274509999997" green="0.55686274509999997" blue="0.57647058819999997" alpha="1" colorSpace="custom" customColorSpace="sRGB"',
    "blue-srgb": 'systemColor="systemBlueColor" red="0" green="0.47843137254901957" blue="1" alpha="1" colorSpace="custom" customColorSpace="sRGB"',
    "separator-srgb": 'systemColor="separatorColor" red="0.23529411759999999" green="0.23529411759999999" blue="0.26274509800000001" alpha="0.28999999999999998" colorSpace="custom" customColorSpace="sRGB"',
    "background-srgb": 'systemColor="secondarySystemBackgroundColor" red="0.94901960780000005" green="0.94901960780000005" blue="0.96862745100000003" alpha="1" colorSpace="custom" customColorSpace="sRGB"',
    "label-white": 'systemColor="labelColor" white="0" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"',
    "secondary-calibrated": 'systemColor="secondaryLabelColor" red="0.2" green="0.4" blue="0.6" alpha="0.7" colorSpace="calibratedRGB"',
}.items():
    COLOR_ROUTES[f"system-components-{_name}"] = constrained(color_subviews([_attributes]), "")
for _name in ("black", "darkText", "lightText", "white", "clear", "groupTableViewBackground", "viewFlipsideBackground", "scrollViewTexturedBackground", "underPageBackground"):
    COLOR_ROUTES[f"unmatched-cocoa-{_name}"] = constrained(color_subviews([f'cocoaTouchSystemColor="{_name}Color"']), "").replace(' colorMatched="YES"', "")
_DIGITS = 'red="0.12345678901234567" green="0.40000000000000002" blue="0.87654321098765432" alpha="0.33333333333333331" colorSpace="calibratedRGB"'
COLOR_ROUTES["unmatched-rgb-digits"] = constrained(color_subviews([_DIGITS]), "").replace(' colorMatched="YES"', "")
COLOR_ROUTES["unmatched-white-digits"] = constrained(color_subviews(['white="0.12345678901234567" alpha="0.33333333333333331" colorSpace="calibratedWhite"']), "").replace(' colorMatched="YES"', "")
EXPERIMENTS.update(COLOR_ROUTES)
for _name, _color in {
    "rgb-digits": _DIGITS, "rgb-short": 'red="0.2" green="0.4" blue="0.6" alpha="1" colorSpace="calibratedRGB"',
    "white-digits": 'white="0.12345678901234567" alpha="0.33333333333333331" colorSpace="calibratedWhite"', "white-short": 'white="0.3" alpha="1" colorSpace="calibratedWhite"',
    "dark-text": 'cocoaTouchSystemColor="darkTextColor"', "group-table": 'cocoaTouchSystemColor="groupTableViewBackgroundColor"',
    "cocoa-black": 'cocoaTouchSystemColor="blackColor"', "cocoa-light-text": 'cocoaTouchSystemColor="lightTextColor"', "cocoa-clear": 'cocoaTouchSystemColor="clearColor"',
    "cocoa-flipside": 'cocoaTouchSystemColor="viewFlipsideBackgroundColor"', "cocoa-textured": 'cocoaTouchSystemColor="scrollViewTexturedBackgroundColor"',
}.items():
    STORYBOARDS[f"sb-color-unmatched-{_name}"] = storyboard(scene(view_extra=f'                        <color key="backgroundColor" {_color}/>\n')).replace(' colorMatched="YES"', "")


def main():
    out = Path(sys.argv[1]).resolve()
    selected = sys.argv[2:] or [*EXPERIMENTS, *STORYBOARDS, "link-lproj", "missing-file", "stable", "build"]
    work = Path("/tmp/nomac-nib-experiments")
    out.mkdir(parents=True, exist_ok=True)
    recorded = out / "observations.json"
    observations = json.loads(recorded.read_text()) if recorded.exists() else {}
    for name in selected:
        shutil.rmtree(work / name, ignore_errors=True)
        if name == "corpus":
            observations.update({f"corpus:{path}": result for path, result in corpus_experiment(work / name).items()})
            continue
        if name == "link-lproj":
            observations[name] = link_lproj_experiment(work / name)
            print(f"[{name}] {observations[name]['status']} {sorted(observations[name]['files'])}", flush=True)
            continue
        if name in STORYBOARDS or name in ("missing-file", "stable", "build"):
            if name in STORYBOARDS:
                observations[name] = storyboard_experiment(work / name, STORYBOARDS[name], name)
            elif name == "missing-file":
                (work / name).mkdir(parents=True)
                observations[name] = compile_xib(work / name / "Missing.xib", work / name / "out", name)
            elif name == "stable":
                (work / name).mkdir(parents=True)
                (work / name / "View.xib").write_text(EXPERIMENTS["view"])
                first = compile_xib(work / name / "View.xib", work / name / "first", name)
                second = compile_xib(work / name / "View.xib", work / name / "second", name)
                observations[name] = {"identical": first["files"] == second["files"], "files": sorted(first["files"])}
            else:
                observations[name] = build_experiment(work / name)
            print(f"[{name}] {json.dumps(observations[name])[:300]}", flush=True)
            continue
        source = work / name / ("Base.lproj/View.xib" if name in LPROJ_XIBS else "View.xib")
        source.parent.mkdir(parents=True)
        source.write_text(EXPERIMENTS[name])
        observations[name] = compile_xib(source, work / name / "out", name)
        result = observations[name]
        print(f"[{name}] {result['status']} {sorted(result['files'])} {result['stdout'].strip()[:200]}", flush=True)
    recorded.write_text(json.dumps(observations, indent=1) + "\n")


if __name__ == "__main__":
    main()

