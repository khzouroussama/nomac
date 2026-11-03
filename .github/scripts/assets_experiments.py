#!/usr/bin/env python3
"""Observe what Xcode's actool writes for self-written asset catalogs, and compare nomac's.

Runs on a Mac with Xcode (DEVELOPER_DIR selects it; docs/VERIFICATION.md "Without CI"). Every
catalog is written here from scratch; each experiment isolates one feature of the `.car`
format (docs/formats/asset-catalog.md):

- app-build: a self-written SwiftUI app built with xcodebuild, for the actool command lines
  Swift Build runs (the build log is kept).
- colors: color sets: one color, eight names, every color space, appearance, idiom, display
  gamut and component spelling, an accent color that exists and one that does not, a
  catalog without renditions, folders with and without a namespace, and a color for the dark
  appearance only.
- data: data sets: text, 25,000 bytes, an explicit type identifier, data next to colors, and
  one data set per file extension for the type identifier actool records.
- identifiers: one catalog per name, so no two names collide, for the name identifier
  function: single characters, every position of names up to 12 characters, names whose
  ×33 polynomials are equal or differ by 2^16, 2^32 and 2^64, and non-ASCII names.
- collisions: catalogs whose names collide, for which name keeps its identifier and what
  the other one gets.
- bitmap-order: catalogs of 1 to 12 and of 119 to 128 random names, for the order of the
  BITMAPKEYS values and the size at which that table's leaf splits.
- appearance-order: the color-variants catalog compiled six times, for the order of the
  appearance keys (it changes from run to run).
- app-icons: an app icon set without image files, with and without --app-icon and next to a
  color, and --app-icon naming no set (actool reports an error and exits with 1).
- packing: small opaque images (1 to 20 equal squares, a square and a strip, a wide image and 1
  to 10 squares) with deployment target 18.0, for how actool packs images into atlases; where it
  makes one atlas, the documented packer is checked against it.
- images: image sets with deployment targets 13.0, 15.0 and 18.0: smooth, flat, noisy and
  translucent images, palette and RGB PNGs, an odd width, an image taller than one band and one
  wide enough for several mode-2 chunks; a single small image; small opaque images beside
  translucent ones, ones with binary alpha, a single one with alpha, and a mix (which images
  actool packs together and how it numbers the atlases); a visionOS icon stack, which an iOS
  build compiles nothing from.
- symbols: asset symbol generation (the --generate-* options of Swift Build's GenerateAssetSymbols
  task): 233 names as color and image sets, names stored decomposed, every member of the
  extended types that a name could shadow, namespaces, sets sharing a name across namespaces
  and catalogs (compiled three times: their order in the header and the index changes from run
  to run), a catalog of colors, images, data, a launch image, folders and sprite atlases with
  deployment targets 15.0, 16.4 and 17.0 and extensions YES, NO or not passed, sets without
  Contents.json, symbol sets and an Icon Composer icon with --alternate-app-icon, which sets are
  listed for iPhone, iPad and both and which are thinnable (idioms, image files, color values),
  and an empty catalog.

- icons: Icon Composer icons (`.icon`): an expo-like icon (automatic gradient, a white SVG
  glyph moved by a fraction of a point, a gray PNG grid, a group with a shadow and translucency)
  with --app-icon for iPhone, iPad, both and no device and without --app-icon, with alternate
  icons (--alternate-app-icon, --include-all-app-icons, an icon no option names); a composite
  icon compiled twice for actool's run-to-run variations; a composite icon (two groups, layer fills and
  specializations, blend modes, glass, group lighting, blur, opacity and position); batches of
  icons for fills and their specializations, group and layer properties, the other
  specializations, group names, untagged Display P3 colors, PNG layers' opacity, layer positions
  and sizes, SVG gradients, clip paths, style sheets and Display P3 colors, and SVG colors around
  the lightness that makes a layer white.

- vector-images: SVG image sets (six fractional sizes, with and without
  preserves-vector-representation) and JPEG image sets (each kind of segment, three scales).
- profiles: PNGs with ICC profiles written here from the ICC specification (Display P3, an
  Adobe RGB-like profile with a curv gamma, sRGB primaries with a 256-entry table curve and with
  a para gamma of 2.2, an sRGB-like v4 profile) for a million colors and Display P3 for colors
  inside sRGB, opaque and translucent, a palette PNG and a gray one, as an app icon's 1,024-pixel
  image and in an image set; the share of the million colors
  nomac converts exactly as actool does is recorded.

For each case the catalog, actool's outputs and its standard output are kept under
<output-dir>/<experiment>/<case>. With --nomac, nomac's `actool` runs on the same catalog and
compare.json records, per output, whether nomac's is identical (for Assets.car after putting
the appearance keys in name order, the one difference actool's own runs show; for catalogs with
an Icon Composer icon, ADR 0203's variations put aside and ADR 0204's rendered pixels called
"equivalent").

Usage: assets_experiments.py <output-dir> [--nomac <nomac>] [experiment ...]
"""

import collections
import json
import os
import random
import re
import shutil
import string
import struct
import subprocess
import sys
import unicodedata
from pathlib import Path

INFO = {"info": {"author": "xcode", "version": 1}}
ACTOOL_ARGS = [
    "--output-format", "human-readable-text", "--notices", "--warnings", "--compress-pngs",
    "--enable-on-demand-resources", "YES", "--development-region", "en",
    "--target-device", "iphone", "--target-device", "ipad",
    "--minimum-deployment-target", "18.0", "--platform", "iphoneos",
]


def write_json(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, indent=2))


def rgb(r, g, b, a="1.000", space="srgb"):
    return {"color-space": space, "components": {"red": r, "green": g, "blue": b, "alpha": a}}


def entry(color, idiom="universal", **extra):
    e = {"color": color, "idiom": idiom}
    e.update(extra)
    return e


def catalog(root, colors):
    """Writes a catalog of color sets: {name: [color entries]}."""
    if root.exists():
        shutil.rmtree(root)
    write_json(root / "Contents.json", INFO)
    for name, entries in colors.items():
        write_json(root / f"{name}.colorset" / "Contents.json", {"colors": entries, **INFO})
    return root


def red():
    return [entry(rgb("1.000", "0.000", "0.000"))]


def run_actool(catalogs, out, extra=(), args=ACTOOL_ARGS):
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    cmd = ["xcrun", "actool", *map(str, catalogs), "--compile", str(out),
           "--export-dependency-info", str(out / "deps"),
           "--output-partial-info-plist", str(out / "partial.plist"), *args, *extra]
    p = subprocess.run(cmd, capture_output=True, text=True)
    (out / "stdout.txt").write_text(p.stdout)
    (out / "stderr.txt").write_text(p.stderr)
    (out / "status").write_text(str(p.returncode))
    return out


def run_nomac(nomac, catalogs, out, extra=(), args=ACTOOL_ARGS):
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    cmd = [nomac, "actool", *map(str, catalogs), "--compile", str(out),
           "--export-dependency-info", str(out / "deps"),
           "--output-partial-info-plist", str(out / "partial.plist"), *args, *extra]
    p = subprocess.run(cmd, capture_output=True, text=True)
    (out / "stdout.txt").write_text(p.stdout)
    (out / "stderr.txt").write_text(p.stderr)
    (out / "status").write_text(str(p.returncode))
    return out


# BOM reading, enough to list blocks, variables and tree entries.

def bom(data):
    assert data[:8] == b"BOMStore"
    _, nblocks, ioff, _, voff, _ = struct.unpack_from(">6I", data, 8)
    blocks = [struct.unpack_from(">II", data, ioff + 4 + 8 * i) for i in range(nblocks + 1)]
    nv = struct.unpack_from(">I", data, voff)[0]
    variables, o = [], voff + 4
    for _ in range(nv):
        idx, ln = struct.unpack_from(">IB", data, o)
        variables.append((data[o + 5:o + 5 + ln].decode(), idx))
        o += 5 + ln
    return [data[a:a + n] for a, n in blocks], variables


def serialize(blocks, variables):
    out = bytearray(512)
    addrs = [(0, 0)]
    for blk in blocks[1:]:
        out += bytes((-len(out)) % 16)
        addrs.append((len(out), len(blk)))
        out += blk
    out += bytes((-len(out)) % 16)
    voff = len(out)
    out += struct.pack(">I", len(variables))
    for name, idx in variables:
        out += struct.pack(">IB", idx, len(name)) + name.encode()
    vlen = len(out) - voff
    out += bytes((-len(out)) % 16)
    ioff = len(out)
    cap = max(256, (len(addrs) + 7) // 8 * 8)
    out += struct.pack(">I", cap)
    for i in range(cap):
        out += struct.pack(">II", *(addrs[i] if i < len(addrs) else (0, 0)))
    out += struct.pack(">I", 0) + bytes(16)
    out[0:32] = b"BOMStore" + struct.pack(">6I", 1, len(blocks) - 1, ioff, len(out) - ioff, voff, vlen)
    return bytes(out)


def leaf_entries(blocks, tree_index):
    leaf_index = struct.unpack_from(">I", blocks[tree_index], 8)[0]
    leaf = blocks[leaf_index]
    is_leaf, count = struct.unpack_from(">HH", leaf, 0)
    return leaf_index, is_leaf, [struct.unpack_from(">II", leaf, 12 + 8 * k) for k in range(count)]


def canonical_car(data):
    """actool's car with its appearance-key blocks in name order, laid out again."""
    blocks, variables = bom(data)
    assert serialize(blocks, variables) == data, "BOM layout differs from the documented one"
    if "APPEARANCEKEYS" not in dict(variables):
        return data
    leaf_index, _, entries = leaf_entries(blocks, dict(variables)["APPEARANCEKEYS"])
    pairs = sorted((blocks[k], blocks[v]) for v, k in entries)
    first = min(min(v, k) for v, k in entries)
    leaf = bytearray(blocks[leaf_index])
    for j, (key, value) in enumerate(pairs):
        blocks[first + 2 * j], blocks[first + 2 * j + 1] = key, value
        struct.pack_into(">II", leaf, 12 + 8 * j, first + 2 * j + 1, first + 2 * j)
    blocks[leaf_index] = bytes(leaf)
    return serialize(blocks, variables)


def facet_identifiers(data):
    blocks, variables = bom(data)
    _, _, entries = leaf_entries(blocks, dict(variables)["FACETKEYS"])
    result = {}
    for value, key in entries:
        token = blocks[value]
        count = struct.unpack_from("<H", token, 4)[0]
        attrs = dict(struct.unpack_from("<HH", token, 6 + 4 * i) for i in range(count))
        result[blocks[key].decode()] = attrs.get(17, 0)
    return result


def bitmap_value_order(data):
    """Identifiers of BITMAPKEYS in the order their value blocks were created."""
    blocks, variables = bom(data)
    _, is_leaf, entries = leaf_entries(blocks, dict(variables)["BITMAPKEYS"])
    return [k for v, k in sorted(entries)] if is_leaf else None


RENDERED_NAME = re.compile(rb"_[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}-[0-9]+-[0-9A-F]{16}\.png")


def icon_blocks(data):
    """The blocks of an Assets.car with ADR 0203's variations put aside (appearance keys in name
    order, icon facets with part 220, rendered names masked), the variables and the value blocks
    of rendered renditions."""
    blocks, variables = bom(canonical_car(data))
    names = dict(variables)
    fmt_block = blocks[names["KEYFORMAT"]]
    fmt = list(struct.unpack_from(f"<{struct.unpack_from('<I', fmt_block, 8)[0]}I", fmt_block, 12))
    keys = []
    for value, key in tree_entries(blocks, names["RENDITIONS"]):
        k = dict(zip(fmt, struct.unpack_from(f"<{len(fmt)}H", blocks[key])))
        keys.append((k, value))
    stacks = {k.get(17) for k, _ in keys if k.get(2) == 245}
    for value, key in tree_entries(blocks, names["FACETKEYS"]):
        token = bytearray(blocks[value])
        count = struct.unpack_from("<H", token, 4)[0]
        attrs = dict(struct.unpack_from("<HH", token, 6 + 4 * i) for i in range(count))
        if attrs.get(17) in stacks:
            for i in range(count):
                if struct.unpack_from("<HH", token, 6 + 4 * i) == (2, 245):
                    struct.pack_into("<HH", token, 6 + 4 * i, 2, 220)
            blocks[value] = bytes(token)
    rendered = set()
    for k, value in keys:
        csi = blocks[value]
        if k.get(2) == 220 and k.get(17) in stacks and RENDERED_NAME.search(csi[40:168]):
            name = RENDERED_NAME.sub(b"_X.png", csi[40:168].rstrip(b"\0")).ljust(128, b"\0")
            blocks[value] = csi[:40] + name + csi[168:]
            rendered.add(value)
    return blocks, variables, rendered


def tree_entries(blocks, tree):
    """Every (value, key) of a BOM tree, leaf by leaf."""
    out = []
    def visit(page):
        leaf, count = struct.unpack_from(">HH", blocks[page], 0)
        entries = [struct.unpack_from(">II", blocks[page], 12 + 8 * i) for i in range(count)]
        if leaf:
            out.extend(entries)
        else:
            for value, _ in entries:
                visit(value)
            visit(struct.unpack_from(">I", blocks[page], 12 + 8 * count)[0])
    visit(struct.unpack_from(">I", blocks[tree], 8)[0])
    return out


def compare_icon_car(x, y):
    """ADR 0203 and 0204: "identical" after the run-to-run variations, "equivalent" when only
    rendered renditions' lengths and pixels differ, else "different"."""
    if serialize(*bom(x)) != x or serialize(*bom(y)) != y:
        return "different"
    a, va, ra = icon_blocks(x)
    b, vb, rb = icon_blocks(y)
    if va != vb or len(a) != len(b):
        return "different"
    pixels = False
    for i, (p, q) in enumerate(zip(a, b)):
        if p == q:
            continue
        if i in ra and i in rb and p[:180] == q[:180]:
            props = struct.unpack_from("<I", p, 168)[0]
            if p[184:184 + props + 12] == q[184:184 + props + 12]:
                pixels = True
                continue
        return "different"
    return "equivalent" if pixels else "identical"


def png_chunks(data):
    out, o = [], 8
    while o < len(data):
        n, kind = struct.unpack_from(">I4s", data, o)
        body = data[o + 8:o + 8 + n]
        if not (kind == b"IDAT" and out and out[-1][0] == b"IDAT"):
            out.append((kind, body[:24] if kind == b"iDOT" else (b"" if kind == b"IDAT" else body)))
        o += 12 + n
    return out


def converted_files(catalogs):
    """(set, file) of the PNGs under catalogs whose iCCP profile is not sRGB IEC61966-2.1."""
    import hashlib, zlib
    found = set()
    for cat in catalogs:
        for p in Path(cat).glob("**/*.png"):
            if p.parent.suffix not in (".imageset", ".appiconset"):
                continue
            data, o, profile = p.read_bytes(), 8, None
            while o < len(data):
                n, t = struct.unpack_from(">I4s", data, o)
                if t == b"iCCP":
                    body = data[o + 8:o + 8 + n]
                    profile = zlib.decompress(body[body.index(0) + 2:])
                o += 12 + n
            if profile and hashlib.sha256(profile[128:]).hexdigest() != SRGB_BODY:
                found.add((p.parent.stem, p.name))
    return found


SRGB_BODY = "2c4d46e1e255995e1d2592fecec4d8bf7e1dc78179a1cbf2d607301debc630b3"


def compare_pixel_car(x, y, converted):
    """ADR 0204 for converted and rasterized images: blocks may differ only in the payloads of
    renditions named for a converted PNG of a set named like their facet, of image or link
    renditions with CSI flag 0x4 (rasterized from a vector file), and of the atlases their link
    renditions point to."""
    if serialize(*bom(x)) != x or serialize(*bom(y)) != y:
        return "different"
    a, va = bom(canonical_car(x)); b, vb = bom(canonical_car(y))
    if va != vb or len(a) != len(b):
        return "different"
    names = dict(va)
    facets = {}
    for value, key in tree_entries(a, names["FACETKEYS"]):
        token = a[value]
        count = struct.unpack_from("<H", token, 4)[0]
        attrs = dict(struct.unpack_from("<HH", token, 6 + 4 * i) for i in range(count))
        facets[attrs.get(17)] = a[key].decode().split("/")[-1]
    fmt_block = a[names["KEYFORMAT"]]
    fmt = list(struct.unpack_from(f"<{struct.unpack_from('<I', fmt_block, 8)[0]}I", fmt_block, 12))
    keys = [(dict(zip(fmt, struct.unpack_from(f"<{len(fmt)}H", a[key]))), value) for value, key in tree_entries(a, names["RENDITIONS"])]
    allowed, atlases = set(), []
    for k, value in keys:
        csi = a[value]
        rasterized = struct.unpack_from("<I", csi, 8)[0] & 4 and struct.unpack_from("<H", csi, 36)[0] in (0, 12, 1003)
        if not rasterized and (facets.get(k.get(17)), csi[40:168].rstrip(b"\0").decode()) not in converted:
            continue
        allowed.add(value)
        o, end = 184, 184 + struct.unpack_from("<I", csi, 168)[0]
        while o + 8 <= end:
            kind, length = struct.unpack_from("<II", csi, o)
            if kind == 1010:
                count = struct.unpack_from("<H", csi, o + 8 + 26)[0] // 4
                atlases.append({p: q for p, q in (struct.unpack_from("<HH", csi, o + 8 + 30 + 4 * n) for n in range(count)) if p})
            o += 8 + length
    allowed |= {value for k, value in keys if {p: q for p, q in k.items() if q} in atlases}
    pixels = False
    for i, (p, q) in enumerate(zip(a, b)):
        if p == q:
            continue
        props = struct.unpack_from("<I", p, 168)[0] if len(p) > 184 else 0
        if i in allowed and p[:180] == q[:180] and p[184:184 + props + 12] == q[184:184 + props + 12]:
            pixels = True
            continue
        return "different"
    return "equivalent" if pixels else "identical"


def compare(actool_out, nomac_out, converted=frozenset(), resized=False):
    result = {}
    pngs = sorted({p.name for d in (actool_out, nomac_out) if d.exists() for p in d.glob("*.png")})
    packs = sorted({f"{p.parent.name}/{p.name}" for d in (actool_out, nomac_out) if d.exists() for p in d.glob("*.stickerpack/*")})
    for name in ("Assets.car", "partial.plist", "deps", "stdout.txt", *pngs, *packs):
        a, n = actool_out / name, nomac_out / name
        if not a.exists() and not n.exists():
            continue
        if not a.exists() or not n.exists():
            result[name] = "missing in " + ("actool" if not a.exists() else "nomac")
            continue
        x, y = a.read_bytes(), n.read_bytes()
        if name in ("deps", "stdout.txt"):
            x = x.replace(str(actool_out).encode(), b"OUT")
            y = y.replace(str(nomac_out).encode(), b"OUT")
        if name == "Assets.car" and x != y:
            result[name] = compare_icon_car(x, y) if b"iconstack" in x else compare_pixel_car(x, y, converted)
            continue
        if name.endswith(".png") and x != y and (converted or resized or b"iconstack" in (actool_out / "Assets.car").read_bytes()):
            result[name] = "equivalent" if png_chunks(x) == png_chunks(y) else "different"
            continue
        result[name] = "identical" if x == y else "different"
    return result


def case(root, name, catalogs, nomac, extra=(), runs=1, args=ACTOOL_ARGS, resized=False):
    d = root / name
    for i in range(runs):
        out = run_actool(catalogs, d / ("actool" if runs == 1 else f"actool-{i}"), extra, args)
    report = {"case": name}
    if nomac:
        n = run_nomac(nomac, catalogs, d / "nomac", extra, args)
        report["compare"] = compare(out, n, converted_files(c for c in catalogs if str(c).endswith(".xcassets")), resized)
    return report


def exp_app_build(root, nomac):
    app = root / "Demo"
    write_json(app / "App" / "Assets.xcassets" / "Contents.json", INFO)
    write_json(app / "App" / "Assets.xcassets" / "AccentColor.colorset" / "Contents.json",
               {"colors": [entry(rgb("0.000", "0.478", "1.000"))], **INFO})
    (app / "App" / "App.swift").write_text(
        "import SwiftUI\n\n@main\nstruct DemoApp: App {\n    var body: some Scene {\n"
        "        WindowGroup { Text(\"Hi\") }\n    }\n}\n")
    settings = ("ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor; CODE_SIGNING_ALLOWED = NO; "
                "GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_UILaunchScreen_Generation = YES; "
                "PRODUCT_BUNDLE_IDENTIFIER = org.nomac.demo; PRODUCT_NAME = \"$(TARGET_NAME)\"; "
                "SWIFT_VERSION = 5.0; TARGETED_DEVICE_FAMILY = \"1,2\";")
    objects = f"""
		A1 /* Demo.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Demo.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		A2 /* App */ = {{isa = PBXFileSystemSynchronizedRootGroup; path = App; sourceTree = "<group>"; }};
		A3 = {{isa = PBXGroup; children = (A2, A4); sourceTree = "<group>"; }};
		A4 /* Products */ = {{isa = PBXGroup; children = (A1); name = Products; sourceTree = "<group>"; }};
		A5 = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};
		A6 = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};
		A7 = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};
		A8 /* Demo */ = {{isa = PBXNativeTarget; buildConfigurationList = B0; buildPhases = (A5, A6, A7); buildRules = (); dependencies = (); fileSystemSynchronizedGroups = (A2); name = Demo; productName = Demo; productReference = A1; productType = "com.apple.product-type.application"; }};
		A9 /* Project object */ = {{isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = 1; LastUpgradeCheck = 2700; }}; buildConfigurationList = B3; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = A3; minimizedProjectReferenceProxies = 1; preferredProjectObjectVersion = 77; productRefGroup = A4; projectDirPath = ""; projectRoot = ""; targets = (A8); }};
		B0 = {{isa = XCConfigurationList; buildConfigurations = (B1, B2); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};
		B1 = {{isa = XCBuildConfiguration; buildSettings = {{{settings}}}; name = Debug; }};
		B2 = {{isa = XCBuildConfiguration; buildSettings = {{{settings}}}; name = Release; }};
		B3 = {{isa = XCConfigurationList; buildConfigurations = (B4, B5); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};
		B4 = {{isa = XCBuildConfiguration; buildSettings = {{IPHONEOS_DEPLOYMENT_TARGET = 18.0; SDKROOT = iphoneos; }}; name = Debug; }};
		B5 = {{isa = XCBuildConfiguration; buildSettings = {{IPHONEOS_DEPLOYMENT_TARGET = 18.0; SDKROOT = iphoneos; }}; name = Release; }};
"""
    pbx = app / "Demo.xcodeproj" / "project.pbxproj"
    pbx.parent.mkdir(parents=True, exist_ok=True)
    pbx.write_text("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 77;\n"
                   f"\tobjects = {{{objects}\t}};\n\trootObject = A9 /* Project object */;\n}}\n")
    p = subprocess.run(["xcodebuild", "-project", str(app / "Demo.xcodeproj"), "-scheme", "Demo",
                        "-configuration", "Release", "-destination", "generic/platform=iOS",
                        "-derivedDataPath", str(app / "DerivedData"), "build"],
                       capture_output=True, text=True)
    (root / "build.log").write_text(p.stdout + p.stderr)
    lines = [line.strip() for line in p.stdout.splitlines() if "/actool " in line or "LinkAssetCatalog" in line]
    (root / "actool-commands.txt").write_text("\n".join(lines) + "\n")
    return [{"case": "app-build", "status": p.returncode, "actool-commands": len(lines)}]


def exp_colors(root, nomac):
    dark = {"appearances": [{"appearance": "luminosity", "value": "dark"}]}
    light = {"appearances": [{"appearance": "luminosity", "value": "light"}]}
    contrast = {"appearances": [{"appearance": "contrast", "value": "high"}]}
    variants = {
        "P3": [entry(rgb("0.200", "0.400", "0.600", "0.500", "display-p3"))],
        "ExtSRGB": [entry(rgb("1.200", "-0.100", "0.500", space="extended-srgb"))],
        "ExtLinear": [entry(rgb("0.200", "0.300", "0.400", space="extended-linear-srgb"))],
        "Gray": [entry({"color-space": "gray-gamma-22", "components": {"white": "0.500", "alpha": "1.000"}})],
        "ExtGray": [entry({"color-space": "extended-gray", "components": {"white": "0.250", "alpha": "0.750"}})],
        "Ints": [entry(rgb("255", "128", "0"))],
        "Hex": [entry(rgb("0xFF", "0x80", "0x00"))],
        "Dark": [entry(rgb("1.000", "1.000", "1.000")), entry(rgb("0.000", "0.000", "0.000"), **dark)],
        "LightDark": [entry(rgb("1.000", "0.000", "0.000")), entry(rgb("0.000", "1.000", "0.000"), **light),
                      entry(rgb("0.000", "0.000", "1.000"), **dark)],
        "Contrast": [entry(rgb("1.000", "0.000", "0.000")), entry(rgb("0.000", "1.000", "0.000"), **contrast)],
        "Idioms": [entry(rgb(f"{(i + 1) / 10:.3f}", "0.000", "0.000"), idiom=idiom)
                   for i, idiom in enumerate(["universal", "iphone", "ipad", "mac", "tv", "watch"])],
        "Gamut": [entry(rgb("1.000", "0.000", "0.000"), **{"display-gamut": "sRGB"}),
                  entry(rgb("1.000", "0.000", "0.000", space="display-p3"), **{"display-gamut": "display-P3"})],
        "Empty": [{"idiom": "universal"}],
    }
    components = {
        "c1": [entry(rgb("1", "0", "2", "1"))],
        "c2": [entry(rgb("0.5", "1.0", "128.0", "0.25"))],
        "c3": [entry(rgb("0.123456789", "0.1", "0.3333333333", "0.7"))],
        "c4": [entry(rgb("0xff", "0X10", "0x1", "0.5"))],
        "c5": [entry(rgb("254", "1.5", "-0.5", "2"))],
        "c6": [entry(rgb(".5", "1e-1", "  0.5", "1.000000001"))],
    }
    cats = root / "catalogs"
    return [
        case(root, "one-color", [catalog(cats / "one" / "A.xcassets", {"Red": red()})], nomac),
        case(root, "eight-colors", [catalog(cats / "eight" / "A.xcassets",
                                            {n: red() for n in ["a", "b", "c", "Red", "Blue", "Zebra", "aa", "ab"]})], nomac),
        case(root, "variants", [catalog(cats / "variants" / "A.xcassets", variants)], nomac, ["--accent-color", "P3"]),
        case(root, "components", [catalog(cats / "components" / "A.xcassets", components)], nomac),
        case(root, "accent-missing", [catalog(cats / "missing" / "A.xcassets", {"Red": red()})], nomac, ["--accent-color", "Nope"]),
        case(root, "no-renditions", [catalog(cats / "empty" / "A.xcassets", {"AccentColor": [{"idiom": "universal"}]})], nomac),
        case(root, "namespace", [namespaced(cats / "namespace" / "A.xcassets")], nomac),
        case(root, "dark-only", [catalog(cats / "dark" / "A.xcassets", {"D": [entry(rgb("1.000", "0.000", "0.000"), **dark)]})], nomac),
        case(root, "system-colors", [system_colors(cats / "system" / "A.xcassets")], nomac),
        case(root, "widget-background", [catalog(cats / "widget" / "A.xcassets", {"WidgetBackground": red(), "AccentColor": red()})], nomac,
             ["--widget-background-color", "WidgetBackground", "--accent-color", "AccentColor"]),
        case(root, "widget-background-missing", [catalog(cats / "widget-missing" / "A.xcassets", {"Other": red()})], nomac,
             ["--widget-background-color", "W", "--accent-color", "A"]),
        case(root, "standalone-icon-behavior-all", [catalog(cats / "standalone" / "A.xcassets", {"Red": red()})], nomac,
             ["--standalone-icon-behavior", "all"]),
        case(root, "standalone-icon-behavior-none", [catalog(cats / "standalone" / "A.xcassets", {"Red": red()})], nomac,
             ["--standalone-icon-behavior", "none"]),
    ]


SYSTEM_COLORS = [
    "systemRedColor", "systemGreenColor", "systemBlueColor", "systemOrangeColor", "systemYellowColor", "systemPinkColor",
    "systemPurpleColor", "systemTealColor", "systemIndigoColor", "systemBrownColor", "systemMintColor", "systemCyanColor",
    "systemGrayColor", "labelColor", "secondaryLabelColor", "tertiaryLabelColor", "quaternaryLabelColor",
]
IOS_SYSTEM_COLORS = [
    "systemGray2Color", "systemGray3Color", "systemGray4Color", "systemGray5Color", "systemGray6Color", "linkColor",
    "placeholderTextColor", "separatorColor", "opaqueSeparatorColor", "systemBackgroundColor", "secondarySystemBackgroundColor",
    "tertiarySystemBackgroundColor", "systemGroupedBackgroundColor", "secondarySystemGroupedBackgroundColor",
    "tertiarySystemGroupedBackgroundColor", "systemFillColor", "secondarySystemFillColor", "tertiarySystemFillColor",
    "quaternarySystemFillColor", "lightTextColor", "darkTextColor", "tintColor",
]


def system_colors(root):
    """Every system color actool knows, light and dark, for ios and (where it does not warn)
    universal, and one with an idiom and a display gamut."""
    def ref(platform, name, **extra):
        return {"color": {"platform": platform, "reference": name}, "idiom": "universal", **extra}
    dark = {"appearances": [{"appearance": "luminosity", "value": "dark"}]}
    colors = {}
    for platform, names in [("ios", SYSTEM_COLORS + IOS_SYSTEM_COLORS), ("universal", SYSTEM_COLORS)]:
        for name in names:
            colors[f"{platform}-{name}"] = [ref(platform, name), ref(platform, name, **dark)]
    colors["variants"] = [ref("ios", "systemBlueColor", idiom="iphone"), ref("ios", "systemBlueColor", **{"display-gamut": "display-P3"})]
    return catalog(root, colors)


def namespaced(root):
    """A color in a folder that provides a namespace, one in a plain folder, one at the top."""
    catalog(root, {"Red": red()})
    write_json(root / "F" / "Contents.json", {**INFO, "properties": {"provides-namespace": True}})
    write_json(root / "F" / "Red.colorset" / "Contents.json", {"colors": red(), **INFO})
    write_json(root / "G" / "Contents.json", INFO)
    write_json(root / "G" / "Blue.colorset" / "Contents.json", {"colors": red(), **INFO})
    return root


def data_set(root, name, filename, content, uti=None):
    item = {"filename": filename, "idiom": "universal"}
    if uti:
        item["universal-type-identifier"] = uti
    (root / f"{name}.dataset").mkdir(parents=True, exist_ok=True)
    (root / f"{name}.dataset" / filename).write_bytes(content)
    write_json(root / f"{name}.dataset" / "Contents.json", {"data": [item], **INFO})


def big_data():
    """25,000 bytes, the first 5,000 varied: no compression would leave this as it is."""
    return bytes((i * 7 + i // 3) & 0xFF for i in range(5000)) + b"A" * 20000


EXTENSIONS = ["txt", "json", "bin", "plist", "xml", "png", "jpg", "jpeg", "gif", "pdf", "mp3", "m4a", "wav",
              "caf", "aiff", "mov", "mp4", "csv", "html", "htm", "js", "css", "zip", "gz", "tar", "strings",
              "md", "rtf", "svg", "ttf", "otf", "mlmodel", "mlmodelc", "obj", "usdz", "scn", "glb", "gltf",
              "yaml", "yml", "dat", "data", "db", "sqlite", "woff", "woff2", "none", "xyzzy"]


def exp_data(root, nomac):
    cats = root / "catalogs"
    small = catalog(cats / "small" / "A.xcassets", {})
    data_set(small, "Small", "blob.txt", b"hello")
    data_set(small, "Big", "big.bin", big_data())
    data_set(small, "Json", "data.json", b'{"a": [1, 2, 3]}', "public.json")
    mixed = namespaced(cats / "mixed" / "A.xcassets")
    data_set(mixed, "Hello", "blob.txt", b"hello")
    types = catalog(cats / "types" / "A.xcassets", {})
    for ext in EXTENSIONS:
        data_set(types, "D" + ext, "f." + ext, b"x")
    data_set(types, "Dnoext", "noext", b"x")
    known = catalog(cats / "known-types" / "A.xcassets", {})
    for ext in EXTENSIONS[:EXTENSIONS.index("dat")]:
        data_set(known, "D" + ext, "f." + ext, b"x")
    reports = [case(root, "data-only", [small], nomac), case(root, "data-and-colors", [mixed], nomac),
               case(root, "known-types", [known], nomac), case(root, "types", [types], None)]
    blocks, variables = bom((root / "types" / "actool" / "Assets.car").read_bytes())
    utis = {}
    for value, key in leaf_entries(blocks, dict(variables)["RENDITIONS"])[2]:
        csi = blocks[value]
        length, offset = struct.unpack_from("<I", csi, 168)[0], 184
        while offset < 184 + length:
            kind, size = struct.unpack_from("<II", csi, offset)
            if kind == 1005:
                utis[struct.unpack_from("<H", blocks[key], 10)[0]] = csi[offset + 16:offset + 8 + size].rstrip(b"\0").decode()
            offset += 8 + size
    identifiers = facet_identifiers((root / "types" / "actool" / "Assets.car").read_bytes())
    reports[-1]["type-identifiers"] = {name[1:]: utis[identifier] for name, identifier in identifiers.items()}
    return reports


def balanced_digits(value, n):
    digits = []
    for _ in range(n):
        r = value % 33
        if r > 16:
            r -= 33
        digits.append(r)
        value = (value - r) // 33
    return digits[::-1] if value == 0 else None


def exp_identifiers(root, nomac):
    names = list(string.ascii_lowercase + string.digits)
    for length in range(1, 13):
        base = "a" * length
        names.append(base)
        names += [base[:p] + c + base[p + 1:] for p in range(length) for c in "bcq"]
    names += [c + "aaa" for c in string.ascii_lowercase + string.digits + "-_+=,;!@#$%^&()[]{}~ "]
    names += ["aaaa", "b@aa", "aaaaaaaa", "b@aaaaaa", "ab@aaaaa", "é", "Ünïcödé", "日本", "Emoji😀"]
    for bits, n in ((16, 12), (32, 12), (64, 14)):
        names += ["m" * n, "".join(chr(ord("m") + d) for d in balanced_digits(1 << bits, n))]
    random.seed(1)
    names += ["".join(random.choice(string.ascii_lowercase) for _ in range(8)) for _ in range(120)]
    names += ["".join(random.choice(string.ascii_lowercase) for _ in range(14)) for _ in range(120)]
    names = list(dict.fromkeys(names))
    table, facets_not_nfd = {}, {}
    for i, name in enumerate(names):
        d = root / "names" / f"{i:04d}"
        out = run_actool([catalog(d / "A.xcassets", {name: red()})], d / "actool")
        (facet, identifier), = facet_identifiers((out / "Assets.car").read_bytes()).items()
        table[name] = identifier
        if facet != unicodedata.normalize("NFD", name):
            facets_not_nfd[name] = facet
        shutil.rmtree(d)
    write_json(root / "identifiers.json", table)
    wrong = {n: f"{v:04x}" for n, v in table.items() if documented_identifier(n) != v}
    return [{"case": "identifiers", "names": len(table), "not-matching-the-documented-rule": wrong,
             "facet-names-not-in-nfd": facets_not_nfd}]


def documented_identifier(name):
    """The rule of docs/formats/asset-catalog.md, "Name identifiers"."""
    h = 100823
    units = name.encode("utf-16-le")
    for i in range(0, len(units), 2):
        h = (h * 33 + (units[i] | units[i + 1] << 8)) & (2 ** 64 - 1)
    result = 0
    for shift in (0, 16, 32, 48):
        result = (result * 33 + (h >> shift & 0xFFFF)) & 0xFFFF
    return result


def exp_collisions(root, nomac):
    pairs = []
    for c in string.ascii_lowercase:
        pairs += ["a" + c, "b" + chr(ord(c) - 33), "xa" + c, "xb" + chr(ord(c) - 33)]
    cats = root / "catalogs"
    reports = [case(root, "pairs", [catalog(cats / "pairs" / "A.xcassets", {n: red() for n in pairs})], nomac)]
    for i, group in enumerate([["ac", "bB"], ["cZ", "b{"], ["aac", "abB"], ["ac", "bB", "bC"]]):
        reports.append(case(root, f"group-{i}", [catalog(cats / f"group-{i}" / "A.xcassets", {n: red() for n in group})], nomac))
    for r in reports:
        car = root / r["case"] / "actool" / "Assets.car"
        r["identifiers"] = {k: f"{v:04x}" for k, v in facet_identifiers(car.read_bytes()).items()}
    return reports


def exp_bitmap_order(root, nomac):
    random.seed(9)
    reports = []
    sizes = list(range(1, 13)) * 3 + list(range(119, 129)) + [140, 200, 253, 254, 300, 400, 510]
    for i, n in enumerate(sizes):
        names = ["r" + "".join(random.choice("abcdefghij") for _ in range(5)) for _ in range(n)]
        cat = catalog(root / "catalogs" / f"{i:03d}" / "A.xcassets", {name: red() for name in dict.fromkeys(names)})
        r = case(root, f"{i:03d}-n{n}", [cat], nomac)
        r["order"] = bitmap_value_order((root / r["case"] / "actool" / "Assets.car").read_bytes())
        reports.append(r)
    return reports


def exp_appearance_order(root, nomac):
    dark = {"appearances": [{"appearance": "luminosity", "value": "dark"}]}
    light = {"appearances": [{"appearance": "luminosity", "value": "light"}]}
    contrast = {"appearances": [{"appearance": "contrast", "value": "high"}]}
    cat = catalog(root / "catalogs" / "A.xcassets", {
        "LightDark": [entry(rgb("1.000", "0.000", "0.000")), entry(rgb("0.000", "1.000", "0.000"), **light),
                      entry(rgb("0.000", "0.000", "1.000"), **dark)],
        "Contrast": [entry(rgb("1.000", "0.000", "0.000")), entry(rgb("0.000", "1.000", "0.000"), **contrast)],
    })
    report = case(root, "runs", [cat], nomac, runs=6)
    orders = []
    for i in range(6):
        blocks, variables = bom((root / "runs" / f"actool-{i}" / "Assets.car").read_bytes())
        _, _, entries = leaf_entries(blocks, dict(variables)["APPEARANCEKEYS"])
        orders.append([blocks[k].decode() for v, k in sorted(entries, key=lambda e: e[1])])
    report["orders"] = orders
    return [report]


def png(path, width, height, pixel):
    """An 8-bit RGBA PNG whose pixel (x, y) is pixel(x, y)."""
    import zlib
    rows = b"".join(b"\0" + bytes(c for x in range(width) for c in pixel(x, y)) for y in range(height))
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b""))


def image_catalog(root, images):
    """images: (name, width, height, RGBA color)."""
    if root.exists():
        shutil.rmtree(root)
    write_json(root / "Contents.json", INFO)
    for name, width, height, color in images:
        png(root / f"{name}.imageset" / f"{name}.png", width, height, lambda x, y, c=color: c)
        write_json(root / f"{name}.imageset" / "Contents.json",
                   {"images": [{"filename": f"{name}.png", "idiom": "universal", "scale": "1x"}], **INFO})
    return root


def tree(blocks, tree_index):
    """Every (key, value) of a BOM tree, following branch nodes."""
    out = []
    def walk(index):
        node = blocks[index]
        is_leaf, count = struct.unpack_from(">HH", node, 0)
        entries = [struct.unpack_from(">II", node, 12 + 8 * k) for k in range(count)]
        if is_leaf:
            out.extend((k, v) for v, k in entries)
        else:
            for v, k in entries:
                walk(v)
            walk(struct.unpack_from(">I", node, 12 + 8 * count)[0])
    walk(struct.unpack_from(">I", blocks[tree_index], 8)[0])
    return out


def atlas_layout(data):
    """{atlas number: (width, height)} and {image: (atlas number, x, y)} from the link properties."""
    blocks, variables = bom(data)
    atlases, places = {}, {}
    for key, value in tree(blocks, dict(variables)["RENDITIONS"]):
        csi = blocks[value]
        width, height = struct.unpack_from("<II", csi, 12)
        layout = struct.unpack_from("<H", csi, 36)[0]
        name = csi[40:168].rstrip(b"\0").decode()
        length, offset, links = struct.unpack_from("<I", csi, 168)[0], 184, None
        while offset < 184 + length:
            kind, size = struct.unpack_from("<II", csi, offset)
            if kind == 1010:
                links = csi[offset + 8:offset + 8 + size]
            offset += 8 + size
        if name.startswith("ZZZZPackedAsset"):
            fmt_blocks = blocks[dict(variables)["KEYFORMAT"]]
            attributes = struct.unpack_from(f"<{struct.unpack_from('<I', fmt_blocks, 8)[0]}I", fmt_blocks, 12)
            values = dict(zip(attributes, struct.unpack_from(f"<{len(attributes)}H", blocks[key], 0)))
            atlases[values.get(8, 0)] = (width, height)
        elif layout == 1003 and links:
            x, y = struct.unpack_from("<II", links, 8)
            pairs = struct.unpack_from(f"<{(len(links) - 24) // 2}H", links, 24)
            places[name.rsplit(".", 1)[0]] = (dict(zip(pairs[3::2], pairs[4::2])).get(8, 0), x, y)
    return atlases, places


def documented_packing(images, identifiers):
    """docs/formats/asset-catalog.md "Packing": positions and atlas size for one atlas."""
    order = sorted(images, key=lambda i: (-i[1] * i[2], identifiers[i[0]]))
    def node(x, y, w, h):
        return {"x": x, "y": y, "w": w, "h": h, "used": False}
    def find(n, w, h):
        if n is None:
            return None
        if n["used"]:
            return find(n.get("right"), w, h) or find(n.get("down"), w, h)
        return n if w <= n["w"] and h <= n["h"] else None
    root, out = None, {}
    for name, iw, ih, _ in order:
        w, h = iw + 2, ih + 2
        root = root or node(0, 0, w, h)
        n = find(root, w, h)
        if n is None:
            can_up, can_right = w <= root["w"], h <= root["h"]
            should_right = can_right and root["h"] >= root["w"] + w
            should_up = can_up and root["w"] >= root["h"] + h
            if should_right or (not should_up and can_right):
                root = {"used": True, "x": 0, "y": 0, "w": root["w"] + w, "h": root["h"], "down": root,
                        "right": node(root["w"], 0, w, root["h"])}
            else:
                root = {"used": True, "x": 0, "y": 0, "w": root["w"], "h": root["h"] + h,
                        "down": node(0, root["h"], root["w"], h), "right": root}
            n = find(root, w, h)
        n.update(used=True, down=node(n["x"], n["y"] + h, n["w"], n["h"] - h), right=node(n["x"] + w, n["y"], n["w"] - w, h))
        out[name] = (n["x"] + 2, n["y"] + 2)
    return out, (root["w"] + 2, root["h"] + 2)


def exp_packing(root, nomac):
    """Small opaque images: equal squares, a square with strips, a wide image with squares."""
    sets = {}
    for n in range(1, 21):
        sets[f"squares-{n}"] = [(f"img{i:02d}", 16, 16, ((i * 37) % 256, (i * 91) % 256, (i * 53 + 7) % 256, 255)) for i in range(n)]
    for width, height in [(148, 6), (100, 6), (60, 6), (30, 6), (60, 20), (60, 30), (40, 30)]:
        sets[f"strip-{width}x{height}"] = [("big", 32, 32, (200, 30, 30, 255)), ("strip", width, height, (30, 30, 200, 255))]
    for width in (176, 240):
        for k in range(1, 11):
            sets[f"wide-{width}-{k}"] = [("aWide", width, 64, (200, 30, 30, 255))] + [
                (f"sq{i:02d}", 32, 32, (30, 30 + i * 10, 200, 255)) for i in range(k)]
    reports = []
    for name, images in sets.items():
        out = run_actool([image_catalog(root / "catalogs" / name / "A.xcassets", images)], root / name / "actool")
        atlases, places = atlas_layout((out / "Assets.car").read_bytes())
        report = {"case": name, "atlases": {str(k): v for k, v in sorted(atlases.items())}}
        if len(atlases) == 1:
            identifiers = facet_identifiers((out / "Assets.car").read_bytes())
            expected, size = documented_packing(images, identifiers)
            report["documented-packing"] = "matches" if expected == {k: v[1:] for k, v in places.items()} and (size == atlases[0]) else "differs"
        reports.append(report)
    return reports


def sprite_member(cat, atlas, name, width, height, box, color, scale="1x"):
    """A sprite atlas's image set: color inside box = (x0, y0, x1, y1), transparent elsewhere."""
    x0, y0, x1, y1 = box
    folder = cat / f"{atlas}.spriteatlas" / f"{name}.imageset"
    png(folder / f"{name}.png", width, height, lambda x, y: color if x0 <= x < x1 and y0 <= y < y1 else (0, 0, 0, 0))
    write_json(folder / "Contents.json", {"images": [{"filename": f"{name}.png", "idiom": "universal", "scale": scale}], **INFO})


def numbered_images(cat, groups, seed=1):
    """Image sets of the given (width, height, count, gray) groups, opaque but for two corner
    pixels, each image a random color."""
    rng = random.Random(seed)
    n = 0
    for width, height, count, gray in groups:
        for _ in range(count):
            v = rng.randrange(256)
            color = (v, v, v) if gray else (v, rng.randrange(256), rng.randrange(256))
            name = f"i{n:03d}"
            n += 1
            image_set(cat, name, lambda p, c=color, w=width, h=height: png(
                p, w, h, lambda x, y: (0, 0, 0, 0) if (x, y) in ((0, 0), (w - 1, 0)) else c + (255,)))


def exp_sprites(root, nomac):
    """Sprite atlases (trimming, classes, sizes, 2x) and image classes of more than ten atlases,
    which actool numbers in the order of their indices as decimal strings."""
    red, gray = (200, 30, 60, 255), (90, 90, 90, 255)
    atlases = {
        "trim": [("a", 40, 30, (3, 5, 35, 27), red), ("b", 20, 20, (0, 0, 20, 20), red)],
        "trim-corners": [("a", 40, 30, (0, 0, 35, 27), red), ("b", 20, 20, (2, 0, 20, 19), red)],
        "opaque": [("a", 30, 20, (0, 0, 30, 20), red), ("b", 10, 12, (0, 0, 10, 12), red)],
        "gray": [("a", 30, 20, (2, 2, 28, 18), gray), ("b", 10, 12, (0, 0, 10, 12), (40, 40, 40, 255))],
        "mixed": [("a", 30, 20, (2, 2, 28, 18), gray), ("b", 10, 12, (0, 0, 10, 12), (200, 40, 40, 128))],
        "three": [("a", 50, 40, (1, 0, 50, 40), red), ("b", 30, 60, (0, 1, 30, 59), red), ("c", 25, 25, (5, 5, 20, 20), red)],
        "over-area-limit": [(f"m{i}", 120, 100, (0, 0, 120, 100), (i * 40, 100, 200, 255)) for i in range(4)],
        "single": [("a", 30, 20, (1, 1, 29, 19), red)],
    }
    reports = []
    for name, members in atlases.items():
        cat = catalog(root / "catalogs" / name / "A.xcassets", {})
        write_json(cat / "S.spriteatlas" / "Contents.json", INFO)
        for member in members:
            sprite_member(cat, "S", *member)
        reports.append(case(root, name, [cat], nomac))
    cat = catalog(root / "catalogs" / "scale2" / "A.xcassets", {})
    write_json(cat / "S.spriteatlas" / "Contents.json", INFO)
    sprite_member(cat, "S", "a", 30, 20, (1, 1, 29, 19), red, "2x")
    sprite_member(cat, "S", "b", 10, 12, (0, 0, 10, 12), red, "2x")
    reports.append(case(root, "scale2", [cat], nomac))
    for name, groups in [("atlases-12", [(190, 49, 16, False), (190, 45, 12, False)]),
                         ("atlases-14", [(100, 100, 4, False), (190, 49, 16, False), (190, 45, 12, False)]),
                         ("atlases-9-and-3-gray", [(190, 49, 18, False), (190, 49, 6, True)])]:
        cat = catalog(root / "catalogs" / name / "A.xcassets", {})
        numbered_images(cat, groups)
        reports.append(case(root, name, [cat], nomac))
    return reports


STICKER_ICONS = [("iphone", "29x29", "2x", None), ("iphone", "29x29", "3x", None), ("iphone", "60x45", "2x", None), ("iphone", "60x45", "3x", None),
                 ("ipad", "29x29", "2x", None), ("ipad", "67x50", "2x", None), ("ipad", "74x55", "2x", None), ("universal", "27x20", "2x", "ios"),
                 ("universal", "27x20", "3x", "ios"), ("universal", "32x24", "2x", "ios"), ("universal", "32x24", "3x", "ios"),
                 ("ios-marketing", "1024x768", "1x", "ios"), ("ios-marketing", "1024x1024", "1x", None)]
GIF = b"GIF89a\x01\x00\x01\x00\x80\x00\x00\x00\x00\x00\xff\xff\xff!\xf9\x04\x01\x00\x00\x00\x00,\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;"


def sticker_catalog(path, icons=STICKER_ICONS, grid="regular", gray=False):
    """A stickers icon set of the given entries and a sticker pack of a PNG, a renamed PNG with
    an accessibility label and a GIF with an empty one."""
    if path.exists():
        shutil.rmtree(path)
    write_json(path / "Contents.json", INFO)
    images = []
    for n, (idiom, size, scale, platform) in enumerate(icons):
        width, height = (int(v) * int(scale[0]) for v in size.split("x"))
        name = f"icon{n}.png"
        if gray:
            png_form(path / "iMessage App Icon.stickersiconset" / name, width, height, 8, 0, lambda x, y, n=n: ((x + n) % 256,))
        else:
            png(path / "iMessage App Icon.stickersiconset" / name, width, height, lambda x, y, n=n: ((x + n) % 256, (y * 3) % 256, 90, 255))
        images.append({"filename": name, "idiom": idiom, "scale": scale, "size": size, **({"platform": platform} if platform else {})})
    write_json(path / "iMessage App Icon.stickersiconset" / "Contents.json", {"images": images, **INFO})
    pack = path / "Sticker Pack.stickerpack"
    stickers = [("b", "b.png", None), ("a", "other name.png", "An A"), ("g", "anim.gif", "")]
    for name, filename, label in stickers:
        if filename.endswith(".gif"):
            (pack / f"{name}.sticker").mkdir(parents=True, exist_ok=True)
            (pack / f"{name}.sticker" / filename).write_bytes(GIF)
        else:
            png(pack / f"{name}.sticker" / filename, 300, 300, lambda x, y: (x % 256, 40, 200, 255))
        write_json(pack / f"{name}.sticker" / "Contents.json",
                   {"properties": {"filename": filename, **({"accessibility-label": label} if label is not None else {})}, **INFO})
    write_json(pack / "Contents.json", {"stickers": [{"filename": f"{name}.sticker"} for name, _, _ in stickers],
                                        "properties": {"grid-size": grid}, **INFO})
    return path


def exp_stickers(root, nomac):
    """Sticker catalogs as firefox's and wikipedia's are compiled: the Messages App Store icon in
    Assets.car, the other icon sizes as PNGs, the sticker pack folder and the Info.plist keys."""
    args = ["--output-format", "human-readable-text", "--notices", "--warnings", "--app-icon", "iMessage App Icon", "--compress-pngs",
            "--enable-on-demand-resources", "NO", "--include-sticker-content", "--stickers-icon-role", "extension",
            "--sticker-pack-identifier-prefix", "org.example.Stickers.sticker-pack.", "--development-region", "en",
            "--target-device", "iphone", "--target-device", "ipad", "--minimum-deployment-target", "15.0", "--platform", "iphoneos"]
    cats = root / "catalogs"
    cases = {
        "base": sticker_catalog(cats / "base" / "S.xcstickers"),
        "icons-reversed": sticker_catalog(cats / "reversed" / "S.xcstickers", icons=list(reversed(STICKER_ICONS))),
        "grid-small": sticker_catalog(cats / "small" / "S.xcstickers", grid="small"),
        "grid-large": sticker_catalog(cats / "large" / "S.xcstickers", grid="large"),
        "xcassets": sticker_catalog(cats / "xcassets" / "S.xcassets", icons=[i for i in STICKER_ICONS if i[1] not in ("29x29", "1024x1024")]),
        "gray-icons": sticker_catalog(cats / "gray" / "S.xcstickers", gray=True),
    }
    return [case(root, name, [cat], nomac, args=args) for name, cat in cases.items()]


def exp_app_icons(root, nomac):
    """An app icon set that lists sizes but has no image files, as new projects and retro-rampage
    have, with and without --app-icon, next to a color, with --standalone-icon-behavior, and an
    --app-icon naming no set."""
    sizes = [{"idiom": idiom, "scale": scale, "size": size} for idiom, size, scale in [
        ("iphone", "20x20", "2x"), ("iphone", "60x60", "3x"), ("ipad", "76x76", "2x"), ("ios-marketing", "1024x1024", "1x")]]
    cats = root / "catalogs"
    alone = catalog(cats / "alone" / "A.xcassets", {})
    write_json(alone / "AppIcon.appiconset" / "Contents.json", {"images": sizes, **INFO})
    with_color = catalog(cats / "with-color" / "A.xcassets", {"Red": red()})
    write_json(with_color / "AppIcon.appiconset" / "Contents.json", {"images": sizes, **INFO})
    return [case(root, "empty-set", [alone], nomac, ["--app-icon", "AppIcon"]),
            case(root, "empty-set-not-named", [alone], nomac),
            case(root, "empty-set-and-color", [with_color], nomac, ["--app-icon", "AppIcon"]),
            case(root, "missing-name", [with_color], nomac, ["--app-icon", "Missing"]),
            case(root, "empty-set-standalone-all", [with_color], nomac, ["--app-icon", "AppIcon", "--standalone-icon-behavior", "all"]),
            *multi_size_icons(root, nomac)]


ICON_SIZES = {
    "iphone": [("20x20", "2x"), ("20x20", "3x"), ("29x29", "2x"), ("29x29", "3x"), ("40x40", "2x"), ("40x40", "3x"),
               ("60x60", "2x"), ("60x60", "3x")],
    "ipad": [("20x20", "1x"), ("20x20", "2x"), ("29x29", "1x"), ("29x29", "2x"), ("40x40", "1x"), ("40x40", "2x"),
             ("76x76", "1x"), ("76x76", "2x"), ("83.5x83.5", "2x")],
    "legacy": [("iphone", "29x29", "1x"), ("iphone", "57x57", "1x"), ("iphone", "57x57", "2x"), ("ipad", "50x50", "1x"),
               ("ipad", "50x50", "2x"), ("ipad", "72x72", "1x"), ("ipad", "72x72", "2x")],
}


def icon_set(root, idioms, legacy=False, form="rgba", alpha=255, launch=False, chunks60=()):
    """A multi-size app icon set: every size of the idioms and an App Store icon, each image a
    distinct gradient; form rgba, rgb (color type 2), gray (gray pixels in RGBA), srgb (an sRGB
    chunk) or text (a tEXt chunk); optionally a launch image set whose entries have no files, and
    ancillary chunks on the iPhone 60 pt 2x icon."""
    cat = catalog(root, {})
    entries = [(idiom, size, scale) for idiom in idioms for size, scale in ICON_SIZES[idiom]]
    entries += ICON_SIZES["legacy"] if legacy else []
    entries.append(("ios-marketing", "1024x1024", "1x"))
    images = []
    for n, (idiom, size, scale) in enumerate(entries):
        side = round(float(size.split("x")[0]) * int(scale[0]))
        name = f"{idiom}-{size}@{scale}.png"
        path = cat / "AppIcon.appiconset" / name
        if form == "gray-type-0":
            png_form(path, side, side, 8, 0, lambda x, y, n=n: ((x * 3 + n) % 256,), chunks=[(b"sRGB", b"\0")])
        elif form == "gray-type-4":
            png_form(path, side, side, 8, 4, lambda x, y, n=n: ((x * 3 + n) % 256, 128 if y % 3 else 255))
        elif form == "gray":
            png(path, side, side, lambda x, y, n=n: ((x * 3 + n) % 256,) * 3 + (255 if y % 3 or alpha == 255 else alpha,))
        elif form == "rgb":
            png_rgb(path, side, side, lambda x, y, n=n: ((x + n) % 256, (x * 7 + y) % 256, (y * 5 + n) % 256))
        else:
            chunks = {"srgb": [(b"sRGB", b"\0")], "text": [(b"tEXt", b"Software\0nomac experiments")]}.get(form, [])
            if (idiom, size, scale) == ("iphone", "60x60", "2x"):
                chunks = list(chunks60) or chunks
            png_form(path, side, side, 8, 6, lambda x, y, n=n: ((x + n) % 256, (x * 7 + y) % 256, (y * 5 + n) % 256, alpha),
                     chunks=chunks)
        images.append({"filename": name, "idiom": idiom, "scale": scale, "size": size})
    write_json(cat / "AppIcon.appiconset" / "Contents.json", {"images": images, **INFO})
    if launch:
        write_json(cat / "LaunchImage.launchimage" / "Contents.json", {"images": [
            {"orientation": orientation, "idiom": "iphone", "extent": "full-screen", "minimum-system-version": "8.0",
             "subtype": "736h", "scale": "3x"} for orientation in ("portrait", "landscape")], **INFO})
    return cat


def multi_size_icons(root, nomac):
    """Multi-size app icon sets (`AppIconSet`): the part-218 size tables, part-220 images, icon
    PNGs (CgBI) and Info.plist keys, per --standalone-icon-behavior, target device and PNG form."""
    cats = root / "catalogs"
    ipad = ACTOOL_ARGS.index("ipad")
    iphone_only = ACTOOL_ARGS[:ipad - 1] + ACTOOL_ARGS[ipad + 1:]
    icon = ["--app-icon", "AppIcon"]
    both = icon_set(cats / "both" / "A.xcassets", ["iphone", "ipad"])
    legacy = icon_set(cats / "legacy" / "A.xcassets", ["iphone", "ipad"], legacy=True)
    return [case(root, "icons-iphone", [icon_set(cats / "iphone" / "A.xcassets", ["iphone"], launch=True)], nomac, icon, args=iphone_only),
            case(root, "icons-both", [both], nomac, icon),
            case(root, "icons-both-target-iphone", [both], nomac, icon, args=iphone_only),
            case(root, "icons-both-all", [both], nomac, [*icon, "--standalone-icon-behavior", "all"]),
            case(root, "icons-both-none", [both], nomac, [*icon, "--standalone-icon-behavior", "none"]),
            case(root, "icons-legacy-all", [legacy], nomac, [*icon, "--standalone-icon-behavior", "all"]),
            *[case(root, f"icons-{form}", [icon_set(cats / form / "A.xcassets", ["iphone", "ipad"], form=form, alpha=alpha)], nomac,
                   [*icon, "--standalone-icon-behavior", "all"])
              for form, alpha in (("rgb", 255), ("gray", 128), ("srgb", 255), ("text", 255), ("translucent", 200))],
            case(root, "icons-gray-opaque", [icon_set(cats / "gray-opaque" / "A.xcassets", ["iphone", "ipad"], form="gray")], nomac, icon),
            *[case(root, f"icon-chunks-{name}", [icon_set(cats / f"chunks-{name}" / "A.xcassets", ["iphone"], chunks60=[(k.encode(), ICON_CHUNKS[k]) for k in kinds])],
                   nomac, icon, args=iphone_only)
              for name, kinds in [("text-srgb", ["tEXt", "sRGB"]), ("all", ["sRGB", "eXIf", "pHYs", "iTXt", "tEXt"]), ("phys", ["pHYs"]),
                                  ("gama", ["gAMA"]), ("phys-srgb-gama", ["pHYs", "sRGB", "gAMA"]), ("exif", ["eXIf"]), ("itxt", ["iTXt"]),
                                  ("gama-chrm", ["gAMA", "cHRM"]), ("text-exif-itxt", ["tEXt", "eXIf", "iTXt"])]],
            *[case(root, f"icon-gray-type-{ct}", [icon_set(cats / f"gray-type-{ct}" / "A.xcassets", ["iphone"], form=f"gray-type-{ct}")], nomac, icon, args=iphone_only)
              for ct in (0, 4)],
            case(root, "icons-other-set-named", [with_other_set(cats / "other-set", both)], nomac, icon),
            case(root, "icons-not-named", [with_other_set(cats / "other-set-none", both)], nomac),
            case(root, "icon-chunks-two-texts", [icon_set(cats / "chunks-two-texts" / "A.xcassets", ["iphone"],
                                                          chunks60=[(b"tEXt", b"Software\0nomac"), (b"tEXt", b"Comment\0hello")])], nomac, icon, args=iphone_only)]


def with_other_set(root, catalog):
    """A copy of the catalog with its icon set also as `Other`."""
    copy = root / catalog.name
    if copy.exists():
        shutil.rmtree(copy)
    shutil.copytree(catalog, copy)
    shutil.copytree(copy / "AppIcon.appiconset", copy / "Other.appiconset")
    return copy


ICON_CHUNKS = {
    "sRGB": b"\0", "gAMA": struct.pack(">I", 45455), "cHRM": struct.pack(">8I", 31270, 32900, 64000, 33000, 30000, 60000, 15000, 6000),
    "pHYs": struct.pack(">IIB", 5669, 5669, 1), "tEXt": b"Software\0nomac",
    "eXIf": b"MM\x00\x2a\x00\x00\x00\x08\x00\x01\x01\x12\x00\x03\x00\x00\x00\x01\x00\x01\x00\x00\x00\x00\x00\x00",
    "iTXt": b"XML:com.adobe.xmp\0\0\0\0\0<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"></x:xmpmeta>",
}


def png_palette(path, width, height, palette, transparency, index):
    """An 8-bit palette PNG (color type 3) with a tRNS chunk; pixel (x, y) is palette[index(x, y)]."""
    import zlib
    rows = b"".join(b"\0" + bytes(index(x, y) for x in range(width)) for y in range(height))
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 3, 0, 0, 0))
                     + chunk(b"PLTE", bytes(c for color in palette for c in color)) + chunk(b"tRNS", bytes(transparency))
                     + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b""))


def png_rgb(path, width, height, pixel):
    """An 8-bit RGB PNG (color type 2)."""
    import zlib
    rows = b"".join(b"\0" + bytes(c for x in range(width) for c in pixel(x, y)) for y in range(height))
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b""))


ADAM7 = [(0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2)]


def png_form(path, width, height, depth, color_type, sample, palette=None, transparency=None, interlace=False, chunks=()):
    """A PNG of any bit depth up to 8 and color type: sample(x, y) gives the pixel's samples;
    rows filtered with filter 0, Adam7 passes when interlaced."""
    import zlib
    def row(y, xs):
        values = [v for x in xs for v in sample(x, y)]
        if depth == 8:
            return b"\0" + bytes(values)
        bits = "".join(format(v, f"0{depth}b") for v in values)
        bits += "0" * (-len(bits) % 8)
        return b"\0" + bytes(int(bits[i:i + 8], 2) for i in range(0, len(bits), 8))
    passes = ADAM7 if interlace else [(0, 0, 1, 1)]
    raw = b""
    for x0, y0, dx, dy in passes:
        xs = range(x0, width, dx)
        if len(xs):
            raw += b"".join(row(y, xs) for y in range(y0, height, dy))
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    out = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, depth, color_type, 0, 0, int(interlace)))
    for kind, data in chunks:
        out += chunk(kind, data)
    if palette is not None:
        out += chunk(b"PLTE", bytes(c for color in palette for c in color))
    if transparency is not None:
        out += chunk(b"tRNS", bytes(transparency))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(out + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def png_forms(root):
    """Gray, gray and alpha, palettes and gray of 1, 2 and 4 bits, tRNS keys, Adam7 interlacing and
    the gAMA values actool ignores, each the only image of its set."""
    rng = random.Random(5)
    noise = [rng.randrange(256) for _ in range(64 * 48 * 4)]
    def at(x, y, k=0):
        return noise[((y * 64 + x) * 4 + k) % len(noise)]
    gamma = [(b"gAMA", (45455).to_bytes(4, "big"))]
    palette16 = [(at(i, 0), at(i, 1), at(i, 2)) for i in range(16)]
    forms = {
        "gray8": dict(depth=8, color_type=0, sample=lambda x, y: (at(x, y),)),
        "gray8-key": dict(depth=8, color_type=0, sample=lambda x, y: (at(x, y) % 4 * 60,), transparency=[0, 120]),
        "gray-alpha8": dict(depth=8, color_type=4, sample=lambda x, y: (at(x, y), at(x, y, 1))),
        "rgb8-key": dict(depth=8, color_type=2, sample=lambda x, y: (at(x, y) % 2 * 200, 30, 40), transparency=[0, 200, 0, 30, 0, 40]),
        "rgba8-interlaced": dict(depth=8, color_type=6, sample=lambda x, y: (at(x, y), at(x, y, 1), at(x, y, 2), at(x, y, 3)), interlace=True),
        "rgb8-interlaced-gamma": dict(depth=8, color_type=2, sample=lambda x, y: (at(x, y), at(x, y, 1), at(x, y, 2)), interlace=True, chunks=gamma),
        "gray8-interlaced": dict(depth=8, color_type=0, sample=lambda x, y: (at(x, y),), interlace=True),
        "palette4-interlaced": dict(depth=4, color_type=3, sample=lambda x, y: (at(x, y) % 16,), palette=palette16,
                                    transparency=[at(i, 3) for i in range(16)], interlace=True),
    }
    for bits in (1, 2, 4):
        forms[f"gray{bits}"] = dict(depth=bits, color_type=0, sample=lambda x, y, b=bits: (at(x, y) % (1 << b),))
        forms[f"gray{bits}-key"] = dict(depth=bits, color_type=0, sample=lambda x, y, b=bits: (at(x, y) % (1 << b),), transparency=[0, 1])
        forms[f"palette{bits}"] = dict(depth=bits, color_type=3, sample=lambda x, y, b=bits: (at(x, y) % (1 << b),),
                                       palette=palette16[:1 << bits], transparency=[at(i, 3) for i in range((1 << bits) - 1)])
    root = fresh_catalog(root)
    for name, form in forms.items():
        png_form(root / f"{name}.imageset" / f"{name}.png", 64, 48, **form)
        write_json(root / f"{name}.imageset" / "Contents.json", {"images": [{"filename": f"{name}.png", "idiom": "universal", "scale": "1x"}], **INFO})
    return root


def image_set(root, name, write):
    """An image set with one universal 1x PNG written by write(path)."""
    write(root / f"{name}.imageset" / f"{name}.png")
    write_json(root / f"{name}.imageset" / "Contents.json",
               {"images": [{"filename": f"{name}.png", "idiom": "universal", "scale": "1x"},
                           {"idiom": "universal", "scale": "2x"}, {"idiom": "universal", "scale": "3x"}], **INFO})


def exp_images(root, nomac):
    rng = random.Random(7)
    noise = [rng.randrange(256) for _ in range(160 * 120 * 3)]
    def smooth(x, y):
        return (x * 255 // 300, y * 255 // 200, (x + y) * 255 // 500, 255)
    images = {
        "gradient": lambda p: png(p, 300, 200, smooth),
        "flat": lambda p: png(p, 200, 200, lambda x, y: [(200, 30, 30, 255), (30, 200, 30, 255), (30, 30, 200, 255), (250, 250, 20, 255)][(x // 100) + 2 * (y // 100)]),
        "noise": lambda p: png(p, 160, 120, lambda x, y: (*noise[(y * 160 + x) * 3:(y * 160 + x) * 3 + 3], 255)),
        "translucent": lambda p: png(p, 200, 100, lambda x, y: (240, 120, x, y * 255 // 99)),
        "palette": lambda p: png_palette(p, 190, 100, [(255, 0, 0), (0, 255, 0), (0, 0, 255), (9, 9, 9)], [255, 128, 0],
                                         lambda x, y: (x // 50 + y // 25) % 4),
        "rgb": lambda p: png_rgb(p, 180, 110, lambda x, y: (x, y * 2, 77)),
        "mode3-chunks": lambda p: png(p, 1001, 600, lambda x, y: (*noise[((x + 7 * y) % 4096) * 3:((x + 7 * y) % 4096) * 3 + 3], 255)),
        "odd": lambda p: png(p, 61, 333, lambda x, y: ((x * 7) % 256, (y * 3) % 256, 128, 255)),
        "tall": lambda p: png(p, 1024, 1100, lambda x, y: (x % 256, y % 256, (x ^ y) % 256, 255)),
        "wide": lambda p: png(p, 1500, 800, lambda x, y: (x * 255 // 1499, y * 255 // 799, 90, 255)),
    }
    cats = root / "catalogs"
    big = cats / "standalone" / "Images.xcassets"
    if big.exists():
        shutil.rmtree(big)
    write_json(big / "Contents.json", INFO)
    for name, write in images.items():
        image_set(big, name, write)
    reports = [case(root, f"standalone-{target}", [big], nomac, ["--minimum-deployment-target", target]) for target in ["13.0", "15.0", "18.0"]]

    levels = [rng.randrange(256) for _ in range(160 * 150)]
    def gray(value, alpha=255):
        return (value, value, value, alpha)
    def grain(width):
        return lambda x, y: gray((x * 3 + y * 5 + levels[(y * width + x) % len(levels)] % 9) % 256)
    grays = {
        "gray-noise": lambda p: png(p, 160, 120, lambda x, y: gray(levels[y * 160 + x])),
        "gray-levels": lambda p: png(p, 150, 150, lambda x, y: gray(levels[y * 150 + x] // 64 * 85)),
        "gray-translucent": lambda p: png(p, 150, 150, lambda x, y: gray(levels[y * 150 + x] % 16 * 16, (64, 128, 255, 0)[levels[x * 150 + y] % 4])),
        "gray-ramp": lambda p: png(p, 160, 120, lambda x, y: gray((x * 3 + y * 5 + levels[y * 160 + x] % 9) % 256, (x * 7 + y) % 256)),
        "gray-chunks": lambda p: png(p, 1024, 800, grain(1024)),
        "gray-bands": lambda p: png(p, 2000, 600, grain(2000)),
    }
    gray_catalog = cats / "gray" / "Gray.xcassets"
    if gray_catalog.exists():
        shutil.rmtree(gray_catalog)
    write_json(gray_catalog / "Contents.json", INFO)
    for name, write in grays.items():
        image_set(gray_catalog, name, write)
    reports.append(case(root, "gray", [gray_catalog], nomac, ["--minimum-deployment-target", "15.0"]))

    single = image_catalog(cats / "single" / "S.xcassets", [("only", 20, 20, (10, 200, 30, 255))])
    reports.append(case(root, "single-small", [single], nomac, ["--minimum-deployment-target", "15.0"]))
    def binary(color):
        return lambda x, y: color if (x + y) % 2 else (0, 0, 0, 0)
    opaque = [("o1", 30, 30, (10, 20, 30, 255)), ("o2", 20, 20, (40, 50, 60, 255)), ("o3", 10, 10, (70, 80, 90, 255))]
    classes = {
        "translucent": opaque + [("t1", 12, 12, (1, 2, 3, 100)), ("t2", 14, 14, (4, 5, 6, 200)), ("t3", 9, 9, (250, 8, 9, 1))],
        "binary-alpha": opaque + [("b1", 12, 12, binary((1, 2, 3, 255))), ("b2", 14, 14, binary((4, 5, 6, 255))), ("b3", 9, 9, binary((7, 8, 9, 255)))],
        "one-binary-alpha": opaque + [("b1", 12, 12, binary((1, 2, 3, 255)))],
        "one-translucent": opaque + [("t1", 12, 12, (1, 2, 3, 100))],
        "mixed-alpha": opaque[:2] + [("b1", 12, 12, binary((1, 2, 3, 255))), ("b2", 14, 14, binary((4, 5, 6, 255))), ("t1", 11, 11, (1, 2, 3, 100))],
        "gray": opaque[:2] + [("g1", 30, 30, lambda x, y: gray(x * 8)), ("g2", 20, 20, lambda x, y: gray(y * 9)),
                              ("t1", 10, 10, lambda x, y: gray(x * 20, 128)), ("t2", 12, 12, lambda x, y: gray(40, x * 20 % 256)),
                              ("t3", 8, 3, lambda x, y: gray(levels[y * 8 + x], levels[y * 8 + x + 100]))],
    }
    for name, members in classes.items():
        cat = cats / "classes" / name / "A.xcassets"
        if cat.exists():
            shutil.rmtree(cat)
        write_json(cat / "Contents.json", INFO)
        for image, width, height, color in members:
            image_set(cat, image, lambda p, w=width, h=height, c=color: png(p, w, h, c if callable(c) else (lambda x, y: c)))
        reports.append(case(root, f"classes-{name}", [cat], nomac, ["--minimum-deployment-target", "15.0"]))

    reports += scale_cases(root, cats, nomac)
    reports.append(case(root, "png-forms", [png_forms(cats / "png-forms" / "Forms.xcassets")], nomac, ["--minimum-deployment-target", "15.0"]))
    intents = fresh_catalog(cats / "intents" / "A.xcassets")
    for name, width, height, color, intent in [("a", 20, 20, (200, 30, 30, 255), None), ("b", 20, 20, (200, 30, 30, 255), "template"),
                                               ("c", 20, 20, (200, 30, 30, 255), "original"), ("d", 30, 10, (90, 90, 90, 200), "template"),
                                               ("e", 300, 200, (200, 30, 30, 255), "template")]:
        image_set(intents, name, lambda p, w=width, h=height, c=color: png(p, w, h, lambda x, y: c))
        if intent:
            contents = json.loads((intents / f"{name}.imageset" / "Contents.json").read_text())
            write_json(intents / f"{name}.imageset" / "Contents.json", {**contents, "properties": {"template-rendering-intent": intent}})
    reports.append(case(root, "intents", [intents], nomac, ["--minimum-deployment-target", "15.0"]))
    no_contents = fresh_catalog(cats / "no-contents" / "A.xcassets")
    image_set(no_contents, "a", lambda p: png(p, 20, 20, lambda x, y: (200, 30, 30, 255)))
    (no_contents / "G" / "P.imageset").mkdir(parents=True)
    shutil.copy(no_contents / "a.imageset" / "a.png", no_contents / "G" / "P.imageset" / "G")
    reports.append(case(root, "no-contents", [no_contents], nomac, ["--minimum-deployment-target", "15.0"]))

    stack = catalog(cats / "icon-stack" / "S.xcassets", {"Red": red()})
    write_json(stack / "Icon.solidimagestack" / "Contents.json",
               {"layers": [{"filename": "Front.solidimagestacklayer"}, {"filename": "Back.solidimagestacklayer"}], **INFO})
    for layer, color in [("Front", (255, 0, 0, 255)), ("Back", (0, 0, 255, 255))]:
        folder = stack / "Icon.solidimagestack" / f"{layer}.solidimagestacklayer"
        write_json(folder / "Contents.json", INFO)
        png(folder / "Content.imageset" / "l.png", 1024, 1024, lambda x, y, c=color: c)
        write_json(folder / "Content.imageset" / "Contents.json", {"images": [{"filename": "l.png", "idiom": "vision", "scale": "2x"}], **INFO})
    reports.append(case(root, "visionos-icon-stack", [stack], nomac, ["--minimum-deployment-target", "18.0"]))
    return reports


def scaled_set(root, name, entries):
    """An image set of PNGs: entries are (file name, idiom, scale, width, height, pixel or RGBA color)."""
    images = []
    for filename, idiom, scale, width, height, pixel in entries:
        png(root / f"{name}.imageset" / filename, width, height, pixel if callable(pixel) else (lambda x, y, c=pixel: c))
        images.append({"filename": filename, "idiom": idiom, "scale": scale})
    write_json(root / f"{name}.imageset" / "Contents.json", {"images": images, **INFO})


def fresh_catalog(path):
    if path.exists():
        shutil.rmtree(path)
    write_json(path / "Contents.json", INFO)
    return path


def scale_cases(root, cats, nomac):
    """Sets of several scales and idioms: renditions per scale and idiom, atlases per scale and
    idiom, the packing limit of 18,050 pixels times the scale, splits at 2x and 3x."""
    rng = random.Random(11)
    def noise(x, y):
        return (rng.randrange(256), rng.randrange(256), 90, 255)
    def half(color):
        return lambda x, y: color if (x + y) % 2 else (0, 0, 0, 0)
    reports = []
    cat = fresh_catalog(cats / "scales" / "Scales.xcassets")
    scaled_set(cat, "big", [("b1.png", "universal", "1x", 150, 130, noise), ("b2.png", "universal", "2x", 300, 260, noise),
                            ("b3.png", "universal", "3x", 450, 390, noise)])
    for name, side, color in [("a", 10, (200, 0, 0, 255)), ("b", 11, half((0, 200, 0, 255))), ("c", 12, (0, 0, 200, 255)),
                              ("d", 13, half((0, 50, 200, 255))), ("e", 14, (90, 90, 90, 255))]:
        scaled_set(cat, name, [(f"{name}{scale}.png", "universal", f"{scale}x", side * scale, side * scale, color) for scale in (1, 2, 3)])
    scaled_set(cat, "only2x", [("o2.png", "universal", "2x", 16, 16, (0, 0, 200, 255))])
    scaled_set(cat, "only3x", [("p3.png", "universal", "3x", 14, 14, (0, 90, 200, 255))])
    scaled_set(cat, "f", [("f2.png", "universal", "2x", 28, 28, (40, 40, 40, 255))])
    scaled_set(cat, "g", [("g2.png", "universal", "2x", 120, 120, (1, 2, 3, 255)), ("g3.png", "universal", "3x", 134, 134, (1, 2, 3, 255))])
    reports.append(case(root, "scales", [cat], nomac, ["--minimum-deployment-target", "15.0"]))

    for scale, width, height in [(2, 191, 189), (2, 190, 190), (3, 173, 313), (3, 190, 285), (1, 95, 190), (1, 7, 2578), (1, 33, 547)]:
        cat = fresh_catalog(cats / "scale-limits" / f"{scale}-{width}-{height}" / "L.xcassets")
        scaled_set(cat, "probe", [("p.png", "universal", f"{scale}x", width, height, (10, 20, 30, 255))])
        scaled_set(cat, "mate", [("m.png", "universal", f"{scale}x", 8, 8, (40, 20, 30, 255))])
        reports.append(case(root, f"scale-limit-{scale}x-{width}x{height}", [cat], nomac, ["--minimum-deployment-target", "15.0"]))

    for scale, side, count in [(2, 45, 30), (2, 38, 30), (3, 38, 40), (2, 64, 20)]:
        cat = fresh_catalog(cats / "scale-splits" / f"{scale}-{side}-{count}" / "S.xcassets")
        for i in range(count):
            scaled_set(cat, f"s{i}", [(f"s{i}.png", "universal", f"{scale}x", side, side, (i, 20, 30, 255))])
        reports.append(case(root, f"scale-split-{scale}x-{count}x{side}", [cat], nomac, ["--minimum-deployment-target", "15.0"]))
    cat = fresh_catalog(cats / "scale-splits" / "first-at-limit" / "S.xcassets")
    scaled_set(cat, "big", [("big.png", "universal", "2x", 191, 189, (1, 20, 30, 255))])
    for i in range(10):
        scaled_set(cat, f"s{i}", [(f"s{i}.png", "universal", "2x", 10, 10, (i, 20, 30, 255))])
    reports.append(case(root, "scale-split-first-at-limit", [cat], nomac, ["--minimum-deployment-target", "15.0"]))

    cat = fresh_catalog(cats / "idioms" / "Idioms.xcassets")
    scaled_set(cat, "a", [("a1.png", "universal", "1x", 10, 10, (200, 0, 0, 255)), ("a2p.png", "iphone", "2x", 20, 20, (201, 0, 0, 255)),
                          ("a3p.png", "iphone", "3x", 30, 30, (202, 0, 0, 255)), ("a1i.png", "ipad", "1x", 11, 11, (203, 0, 0, 255)),
                          ("a2i.png", "ipad", "2x", 22, 22, (204, 0, 0, 255))])
    scaled_set(cat, "b", [("b2p.png", "iphone", "2x", 24, 24, (0, 200, 0, 255)), ("b2i.png", "ipad", "2x", 26, 26, (0, 201, 0, 255)),
                          ("b2u.png", "universal", "2x", 28, 28, (0, 202, 0, 255))])
    scaled_set(cat, "c", [("c2i.png", "ipad", "2x", 26, 26, (0, 0, 201, 255))])
    scaled_set(cat, "d", [("d1p.png", "iphone", "1x", 15, 15, (9, 0, 201, 255))])
    write_json(cat / "n.imageset" / "Contents.json", {"images": [{"filename": "n.png", "idiom": "universal"}], **INFO})
    png(cat / "n.imageset" / "n.png", 12, 12, lambda x, y: (0, 201, 9, 255))
    reports.append(case(root, "idioms", [cat], nomac, ["--minimum-deployment-target", "15.0"]))
    ipad = ACTOOL_ARGS.index("ipad")
    iphone = ACTOOL_ARGS[:ipad - 1] + ACTOOL_ARGS[ipad + 1:]
    reports.append(case(root, "idioms-iphone", [cat], nomac, ["--minimum-deployment-target", "15.0"], args=iphone))
    return reports


SYMBOL_FILES = ["GeneratedAssetSymbols.swift", "GeneratedAssetSymbols.h", "GeneratedAssetSymbols-Index.plist"]


def run_symbols(tool, catalogs, out, deployment_target, extensions, devices=("iphone", "ipad"), extra=(), platform="iphoneos"):
    """actool as Swift Build's GenerateAssetSymbols task runs it (the app-build log)."""
    if out.exists():
        shutil.rmtree(out)
    (out / "derived").mkdir(parents=True)
    extensions_args = [] if extensions is None else ["--generate-swift-asset-symbol-extensions", extensions]
    cmd = [*tool, *map(str, catalogs), "--compile", str(out / "app"), "--output-format", "human-readable-text",
           "--notices", "--warnings", "--export-dependency-info", str(out / "deps"),
           "--output-partial-info-plist", str(out / "partial.plist"), "--app-icon", "AppIcon", "--compress-pngs",
           "--enable-on-demand-resources", "YES", "--development-region", "en",
           *(a for d in devices for a in ("--target-device", d)), "--minimum-deployment-target", deployment_target,
           "--platform", platform, "--bundle-identifier", "org.nomac.symbols", *extra, *extensions_args,
           "--generate-swift-asset-symbols", str(out / "derived" / SYMBOL_FILES[0]),
           "--generate-objc-asset-symbols", str(out / "derived" / SYMBOL_FILES[1]),
           "--generate-asset-symbol-index", str(out / "derived" / SYMBOL_FILES[2])]
    p = subprocess.run(cmd, capture_output=True, text=True)
    (out / "stdout.txt").write_text(p.stdout)
    (out / "stderr.txt").write_text(p.stderr)
    (out / "status").write_text(str(p.returncode))
    return out


def unordered(name, data):
    """The header's declarations or the index's entries, ignoring their order."""
    if name.endswith(".h"):
        return sorted(data.decode().split("\n\n"))
    import plistlib
    return {kind: sorted(map(repr, entries)) for kind, entries in plistlib.loads(data).items()}


def compare_symbols(actool_out, nomac_out, ties):
    result = {}
    for name in ["stdout.txt", "status", *(f"derived/{n}" for n in SYMBOL_FILES)]:
        a, n = actool_out / name, nomac_out / name
        if not a.exists() or not n.exists():
            result[name] = "missing in " + ("actool" if not a.exists() else "nomac")
            continue
        x, y = a.read_bytes(), n.read_bytes()
        if name == "stdout.txt":
            x, y = x.replace(str(actool_out).encode(), b"OUT"), y.replace(str(nomac_out).encode(), b"OUT")
        if x == y:
            result[name] = "identical"
        elif ties and not name.endswith(".swift") and unordered(name, x) == unordered(name, y):
            result[name] = "identical but for the order of sets sharing a name"
        else:
            result[name] = "different"
    written = sorted(str(p.relative_to(nomac_out)) for p in nomac_out.rglob("*") if p.is_file())
    expected = sorted(["stdout.txt", "stderr.txt", "status", *(f"derived/{n}" for n in SYMBOL_FILES)])
    result["nothing else written"] = written == expected and not (actool_out / "app").exists() and not (actool_out / "deps").exists()
    return result


def symbols_case(root, name, catalogs, nomac, deployment_target="15.0", extensions="YES", runs=1, ties=False,
                 devices=("iphone", "ipad"), extra=(), platform="iphoneos"):
    d = root / name
    outs = [run_symbols(["xcrun", "actool"], catalogs, d / ("actool" if runs == 1 else f"actool-{i}"), deployment_target, extensions,
                        devices, extra, platform) for i in range(runs)]
    report = {"case": name}
    if runs > 1:
        report["actool runs identical"] = {f: len({(o / "derived" / f).read_bytes() for o in outs}) == 1 for f in SYMBOL_FILES}
    if nomac:
        n = run_symbols([nomac, "actool"], catalogs, d / "nomac", deployment_target, extensions, devices, extra, platform)
        report["compare"] = compare_symbols(outs[0], n, ties)
    return report


def exp_symbol_extensions(root, nomac):
    """A catalog's `generate-swift-asset-symbol-extensions` property (home-assistant's
    Colors.xcassets: `enabled` with `--generate-swift-asset-symbol-extensions NO`): each value
    with each option, a catalog with the property beside one without, the property on a
    namespace folder, at iOS 15.0 and 17.0."""
    reports = []
    def make(name, value, images=True, folder_value=None):
        cat = catalog(root / "catalogs" / "symbol-extensions" / name, {f"{name.split('.')[0].lower()}Tint": red()})
        if value is not None:
            write_json(cat / "Contents.json", {**INFO, "properties": {"generate-swift-asset-symbol-extensions": value}})
        if images:
            d = cat / f"{name.split('.')[0].lower()}Pic.imageset"
            d.mkdir()
            png_rgb(d / "p.png", 8, 8, lambda x, y: (1, 2, 3))
            write_json(d / "Contents.json", {"images": [{"filename": "p.png", "idiom": "universal", "scale": "1x"}], **INFO})
        if folder_value is not None:
            f = cat / "Group"
            f.mkdir()
            write_json(f / "Contents.json", {**INFO, "properties": {"provides-namespace": True, "generate-swift-asset-symbol-extensions": folder_value}})
            (f / "inner.colorset").mkdir()
            write_json(f / "inner.colorset" / "Contents.json", {"colors": red(), **INFO})
        return cat
    enabled, disabled, plain = make("Enabled.xcassets", "enabled"), make("Disabled.xcassets", "disabled"), make("Plain.xcassets", None)
    other = make("Other.xcassets", "maybe", images=False)
    folder = make("Folder.xcassets", None, images=False, folder_value="enabled")
    for target in ("15.0", "17.0"):
        for option in ("NO", "YES"):
            for label, cats in (("enabled", [enabled]), ("disabled", [disabled]), ("mixed", [enabled, plain])):
                reports.append(symbols_case(root, f"{label}-{option}-{target}", cats, nomac, target, option))
    reports.append(symbols_case(root, "unknown-NO-15.0", [other], nomac, "15.0", "NO"))
    reports.append(symbols_case(root, "folder-NO-15.0", [folder], nomac, "15.0", "NO"))
    return reports


SYMBOL_NAMES = [
    "red", "redColor", "red color", "red-color", "red_color", "red.color", "AccentColor", "Accent", "backgroundImage",
    "heroImage", "Image", "Color", "colorful", "ImageView", "DNSimple", "IDme", "CyDIS", "TETR.IO", "ABC", "ABC.DEF",
    "ABC_def", "URLString", "myURL", "myURLString", "HTTPSConnection", "iOS", "iPhone", "iPhone12", "17thShard", "4K",
    "42", "_private", "__double", "trailing_", "a", "x1", "Time4VPS", "camelCase", "PascalCase", "snake_case_name",
    "kebab-case-name", "dot.case.name", "space case name", "mixed_Case-Name.Here", "default", "class", "self", "Type",
    "init", "true", "nil", "func", "let", "var", "in", "is", "as", "Any", "Protocol", "some", "café", "naïve", "Ünïcödé",
    "日本", "emoji😀", "plus+sign", "at@sign", "hash#sign", "paren(1)", "comma,name", "apostrophe's", 'quote"name',
    "dollar$", "percent%", "amp&", "tilde~", "caret^", "equals=name", "brackets[1]", "braces{1}", "semi;colon",
    "X1", "A", "RED", "R2D2", "A_B", "A1B2", "HELLO WORLD", "ÉTÉ", "4k", "a1b", "ab1cd", "abc123def", "123abc",
    "iPhone12pro", "SF_Symbol", "V2", "v2Beta", "my2ndCar", "HTML5", "html5Parser", "MP3Player", "3D", "x", "_", "__",
    "-", "a_", "_a2", "aB", "Ab", "ABc", "ABCd", "ColorColor", "redColorImage", "redImageColor", "Colors", "myColor",
    "MyCOLOR", "redcolor", "green_Color", "blue_color_", "redColour", "redIcon", "redSymbol", "redImg", "redUIColor",
    "back\\slash", "Self", "Type2", "super", "where", "while", "repeat", "guard", "defer", "do", "catch", "throw",
    "throws", "rethrows", "try", "await", "async", "fallthrough", "break", "continue", "return", "switch", "case", "if",
    "else", "for", "import", "static", "struct", "enum", "extension", "subscript", "typealias", "deinit", "inout",
    "public", "internal", "fileprivate", "open", "false", "operator", "precedencegroup", "associatedtype", "borrowing",
    "consuming", "nonisolated", "package", "macro", "each", "sending", "convenience", "dynamic", "final", "lazy",
    "mutating", "nonmutating", "optional", "override", "required", "unowned", "weak", "willSet", "didSet", "get", "set",
    "indirect", "infix", "prefix", "postfix", "none", "actor", "isolated", "copy", "discard", "then", "yield",
    "Ελληνικά", "ǅungla", "ßtraße", "İstanbul", "ﬁx", "Ⅻ", "١٢٣", "½", "x²", "a·b", "A😀B", "a😀b", "😀", "e2e", "ID",
    "IDs", "UIColor", "NSImage", "Image2", "imageImage", "COLOR", "Color_", "_Color", "HELLO_COLOR", "日本Color", "aÉb",
    "ÉTÉColor", "Ab日", "日Ab", "x½y",
]

# Every class member of NSColor, UIColor, SwiftUI's Color, NSImage and UIImage whose Swift name a
# set name can produce, from the SDK's headers and interfaces, and members of other kinds.
SYMBOL_COLOR_MEMBERS = [
    "black", "darkGray", "lightGray", "white", "gray", "red", "green", "blue", "cyan", "yellow", "magenta", "orange",
    "purple", "brown", "clear", "pink", "indigo", "mint", "teal", "primary", "secondary", "tertiary", "quaternary",
    "quinary", "accent", "foreground", "background", "selection", "separator", "tint", "placeholder", "link", "fill",
    "windowBackground", "systemRed", "systemGreen", "systemBlue", "systemOrange", "systemYellow", "systemPink",
    "systemPurple", "systemTeal", "systemIndigo", "systemBrown", "systemMint", "systemCyan", "systemGray",
    "systemGray2", "systemGray3", "systemGray4", "systemGray5", "systemGray6", "label", "secondaryLabel",
    "tertiaryLabel", "quaternaryLabel", "quinaryLabel", "placeholderText", "opaqueSeparator", "systemBackground",
    "secondarySystemBackground", "tertiarySystemBackground", "systemGroupedBackground",
    "secondarySystemGroupedBackground", "tertiarySystemGroupedBackground", "systemFill", "secondarySystemFill",
    "tertiarySystemFill", "quaternarySystemFill", "quinarySystemFill", "lightText", "darkText",
    "groupTableViewBackground", "viewFlipsideBackground", "scrollViewTexturedBackground", "underPageBackground",
    "controlAccent", "control", "controlBackground", "text", "textBackground", "windowFrame", "grid", "header",
    "highlight", "shadow", "scrubberTexturedBackground", "textInsertionPoint", "findHighlight", "description",
    "debugDescription", "hash", "hashValue", "cgColor", "ciColor", "components", "resolve", "opacity", "mix",
    "gradient", "shared", "named", "alloc", "new", "superclass", "supportsSecureCoding", "colorSpace", "redComponent",
    "alpha", "alternatingContentBackgroundColors", "controlAlternatingRowBackgroundColors", "currentControlTint",
    "ignoresAlpha", "elements",
]
SYMBOL_IMAGE_MEMBERS = [
    "add", "remove", "actions", "checkmark", "strokedCheckmark", "imageTypes", "imageUnfilteredTypes",
    "imageFileTypes", "imageUnfilteredFileTypes", "imagePasteboardTypes", "imageUnfilteredPasteboardTypes",
    "description", "hash", "new", "alloc", "superclass", "empty", "none", "symbol", "system", "named", "size", "cgImage",
    "scale", "images", "duration", "renderingMode", "template", "baseline", "red", "primary",
    *(f"{n}Name" for n in [
        "actionTemplate", "addTemplate", "advanced", "applicationIcon", "bluetoothTemplate", "bonjour",
        "bookmarksTemplate", "caution", "colorPanel", "columnViewTemplate", "computer", "dotMac",
        "enterFullScreenTemplate", "everyone", "exitFullScreenTemplate", "flowViewTemplate", "folder",
        "folderBurnable", "folderSmart", "followLinkFreestandingTemplate", "fontPanel", "goBackTemplate",
        "goForwardTemplate", "goLeftTemplate", "goRightTemplate", "homeTemplate", "iChatTheaterTemplate",
        "iconViewTemplate", "info", "invalidDataFreestandingTemplate", "leftFacingTriangleTemplate",
        "listViewTemplate", "lockLockedTemplate", "lockUnlockedTemplate", "menuMixedStateTemplate",
        "menuOnStateTemplate", "mobileMe", "multipleDocuments", "network", "pathTemplate", "preferencesGeneral",
        "quickLookTemplate", "refreshFreestandingTemplate", "refreshTemplate", "removeTemplate",
        "revealFreestandingTemplate", "rightFacingTriangleTemplate", "shareTemplate", "slideshowTemplate",
        "smartBadgeTemplate", "statusAvailable", "statusNone", "statusPartiallyAvailable", "statusUnavailable",
        "stopProgressFreestandingTemplate", "stopProgressTemplate", "touchBarAddDetailTemplate",
        "touchBarAddTemplate", "touchBarAlarmTemplate", "touchBarColorPickerFill", "touchBarPlayTemplate",
        "touchBarVolumeUpTemplate", "trashEmpty", "trashFull", "userAccounts", "userGroup", "userGuest", "user"]),
]


def symbol_set(root, kind, name, contents=True, idiom="universal", file=True):
    """A color, image or symbol set; symbol mode reads only whether an image file exists."""
    folder = root / f"{name}.{ {'color': 'colorset', 'image': 'imageset', 'symbol': 'symbolset'}[kind]}"
    folder.mkdir(parents=True, exist_ok=True)
    if not contents:
        return
    if kind == "color":
        write_json(folder / "Contents.json", {"colors": [entry(rgb("1.000", "0.000", "0.000"), idiom)], **INFO})
        return
    filename = "i.svg" if kind == "symbol" else "i.png"
    if file and kind == "symbol":
        (folder / filename).write_text('<svg xmlns="http://www.w3.org/2000/svg"/>')
    elif file:
        png(folder / filename, 1, 1, lambda x, y: (255, 0, 0, 255))
    key = "symbols" if kind == "symbol" else "images"
    write_json(folder / "Contents.json", {key: [{"filename": filename, "idiom": idiom, "scale": "1x"}], **INFO})


def symbol_folder(root, name, namespace=True, properties=None):
    props = {"provides-namespace": True} if namespace else {}
    write_json(root / name / "Contents.json", {**INFO, **({"properties": {**props, **(properties or {})}} if props or properties else {})})
    return root / name


def symbol_catalogs(root, kind, names):
    """One catalog per group of names that differ even ignoring case and normalization, as on macOS."""
    groups = []
    for name in names:
        key = unicodedata.normalize("NFD", name).casefold()
        for group in groups:
            if key not in group:
                group[key] = name
                break
        else:
            groups.append({key: name})
    catalogs = []
    for i, group in enumerate(groups):
        cat = root / f"{kind}{i}" / "Names.xcassets"
        if cat.exists():
            shutil.rmtree(cat)
        write_json(cat / "Contents.json", INFO)
        for name in group.values():
            symbol_set(cat, kind, name)
        catalogs.append(cat)
    return catalogs


def exp_symbols(root, nomac):
    cats = root / "catalogs"
    reports = []
    for kind in ["color", "image"]:
        for i, cat in enumerate(symbol_catalogs(cats / "names", kind, SYMBOL_NAMES)):
            reports.append(symbols_case(root, f"names-{kind}s-{i}", [cat], nomac))
        reports.append(symbols_case(root, f"names-{kind}s-0-17.0", [cats / "names" / f"{kind}0" / "Names.xcassets"], nomac, "17.0"))
        decomposed = [unicodedata.normalize("NFD", n) for n in ["ÉTÉColor", "ÉTÉ", "café", "naïve", "Ünïcödé", "aÉb", "éa", "f"]]
        reports.append(symbols_case(root, f"names-{kind}s-decomposed", symbol_catalogs(cats / "decomposed", kind, decomposed), nomac))
        members = SYMBOL_COLOR_MEMBERS if kind == "color" else SYMBOL_IMAGE_MEMBERS
        reports.append(symbols_case(root, f"members-{kind}s", symbol_catalogs(cats / "members", kind, members), nomac))

    namespaces = cats / "namespaces" / "P.xcassets"
    if namespaces.exists():
        shutil.rmtree(namespaces)
    write_json(namespaces / "Contents.json", INFO)
    for i, name in enumerate(["my folder", "icons_v2", "UI", "lower", "Colors", "3D", "class", "Ns-A", "ns_b", "NsB", "😀",
                              "redColor", "ABC.DEF"]):
        folder = symbol_folder(namespaces, name)
        symbol_set(folder, "color", f"c{i}")
        symbol_set(folder, "image", f"i{i}")
    symbol_set(symbol_folder(namespaces, "Space"), "image", "x")
    symbol_set(namespaces, "image", "Space")
    symbol_set(symbol_folder(namespaces, "Folder", namespace=False), "image", "zeta")
    symbol_set(namespaces, "image", "zeta2")
    inner = symbol_folder(symbol_folder(namespaces, "Outer"), "Mid")
    symbol_set(inner, "image", "leaf")
    symbol_set(inner, "color", "leafColor")
    conflicts = symbol_folder(namespaces, "Conf")
    symbol_set(conflicts, "color", "red")
    symbol_set(conflicts, "image", "add")
    reports.append(symbols_case(root, "namespaces", [namespaces], nomac))

    first, second = cats / "ties" / "A.xcassets", cats / "ties" / "B.xcassets"
    for cat in [first, second]:
        if cat.exists():
            shutil.rmtree(cat)
        write_json(cat / "Contents.json", INFO)
    for name in ["One", "Two", "Three"]:
        symbol_set(symbol_folder(first, name), "image", "icon")
        symbol_set(symbol_folder(first, name), "color", "tint")
    symbol_set(second, "image", "icon")
    symbol_set(second, "color", "tint")
    reports.append(symbols_case(root, "ties", [first, second], nomac, runs=3, ties=True))

    mixed, other = cats / "mixed" / "M.xcassets", cats / "mixed" / "N.xcassets"
    for cat in [mixed, other]:
        if cat.exists():
            shutil.rmtree(cat)
        write_json(cat / "Contents.json", INFO)
    for kind, name in [("color", "brandColor"), ("color", "Accent"), ("image", "logo"), ("image", "heroImage")]:
        symbol_set(mixed, kind, name)
    for name in ["blob", "config"]:
        data_set(mixed, name, "d.txt", b"hi")
    plain = symbol_folder(mixed, "Plain", namespace=False)
    symbol_set(plain, "color", "plainColor")
    symbol_set(plain, "image", "plainImage")
    space = symbol_folder(mixed, "Space")
    symbol_set(space, "color", "spaceColor")
    symbol_set(space, "image", "space_icon")
    symbol_set(symbol_folder(space, "Inner"), "image", "deep")
    symbol_set(symbol_folder(mixed, "Sprites.spriteatlas", namespace=False), "image", "sprite1")
    symbol_set(symbol_folder(mixed, "Atlas.spriteatlas"), "image", "inAtlas")
    write_json(mixed / "LaunchImage.launchimage" / "Contents.json", {"images": [
        {"orientation": "portrait", "idiom": "iphone", "extent": "full-screen", "minimum-system-version": "7.0", "scale": "2x"}], **INFO})
    symbol_set(mixed, "image", "Empty", contents=False)
    symbol_set(mixed, "color", "NoContents", contents=False)
    data_set(symbol_folder(mixed, "OnlyData"), "blob2", "d.txt", b"hi")
    symbol_folder(mixed, "EmptyNamespace")
    symbol_set(other, "image", "other")
    symbol_set(other, "color", "otherColor")
    shared = symbol_folder(other, "Space")
    symbol_set(shared, "color", "fromOther")
    for target, extensions in [("15.0", "YES"), ("15.0", "NO"), ("15.0", None), ("16.4", "YES"), ("17.0", "YES"), ("17.0", "NO")]:
        reports.append(symbols_case(root, f"mixed-{target}-{extensions or 'not-passed'}", [mixed, other], nomac, target, extensions))

    symbols = cats / "symbol-sets" / "S.xcassets"
    if symbols.exists():
        shutil.rmtree(symbols)
    write_json(symbols / "Contents.json", INFO)
    for kind, name in [("image", "alpha"), ("symbol", "beta"), ("image", "gamma"), ("image", "same"), ("symbol", "same")]:
        symbol_set(symbols, kind, name)
    symbol_set(symbol_folder(symbols, "Group"), "symbol", "moon")
    icon = cats / "symbol-sets" / "AppIcon.icon"
    write_json(icon / "icon.json", {"groups": [{"layers": [{"image-name": "g.png", "name": "g"}]}], "supported-platforms": {"squares": "shared"}})
    png(icon / "Assets" / "g.png", 4, 4, lambda x, y: (255, 0, 0, 255))
    reports.append(symbols_case(root, "symbol-sets-and-icon", [icon, symbols], nomac, "18.0", None,
                                extra=["--app-icon", "AppIcon", "--alternate-app-icon", "Other"]))

    listing = cats / "listing" / "L.xcassets"
    if listing.exists():
        shutil.rmtree(listing)
    write_json(listing / "Contents.json", INFO)
    # Idioms actool accepts without a warning in each kind of set.
    for idiom in ["iphone", "ipad", "mac", "tv"]:
        symbol_set(listing, "image", f"img-{idiom}", idiom=idiom)
    for idiom in ["iphone", "ipad", "mac", "tv", "watch", "car", "vision"]:
        symbol_set(listing, "color", f"col-{idiom}", idiom=idiom)
        symbol_set(listing, "symbol", f"sym-{idiom}", idiom=idiom)
    write_json(listing / "template.colorset" / "Contents.json", {"colors": [{"idiom": "universal"}], **INFO})
    write_json(listing / "noColorsKey.colorset" / "Contents.json", INFO)
    write_json(listing / "noImages.imageset" / "Contents.json", {"images": [{"idiom": "universal", "scale": "1x"}], **INFO})
    for devices in [("iphone",), ("ipad",), ("iphone", "ipad")]:
        reports.append(symbols_case(root, f"listing-{'-'.join(devices)}", [listing], nomac, devices=devices))
    reports.append(symbols_case(root, "listing-iphone-ipad-17.0", [listing], nomac, "17.0"))

    empty = catalog(cats / "empty" / "E.xcassets", {})
    reports.append(symbols_case(root, "empty", [empty], nomac, extensions="NO"))
    images_only = image_catalog(cats / "images-only" / "I.xcassets", [("one", 1, 1, (0, 0, 255, 255))])
    reports.append(symbols_case(root, "images-only", [images_only], nomac))
    colors_only = catalog(cats / "colors-only" / "C.xcassets", {"Red": red()})
    reports.append(symbols_case(root, "colors-only", [colors_only], nomac))
    return reports


GLYPH_SVG = ('<svg width="300" height="280" viewBox="0 0 300 280" fill="none" xmlns="http://www.w3.org/2000/svg">\n'
             '<path d="M150 0C170 0 185 10 195 30L295 230C305 250 290 280 265 280C250 280 240 272 232 258L150 110'
             'L68 258C60 272 50 280 35 280C10 280 -5 250 5 230L105 30C115 10 130 0 150 0Z" fill="white"/>\n</svg>\n')
DOT_SVG = '<svg width="100" height="100" viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg"><circle cx="50" cy="50" r="40" fill="#e04020"/></svg>\n'
SQUARE_SVG = '<svg width="100" height="100" viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg"><rect x="10" y="10" width="80" height="80" fill="{}"/></svg>\n'
WIDE_SVG = '<svg width="200" height="150" viewBox="0 0 200 150" xmlns="http://www.w3.org/2000/svg"><rect x="0" y="0" width="200" height="150" fill="#00ff00"/></svg>\n'


GRADIENTS_SVG = ('<svg width="200" height="100" viewBox="0 0 200 100" xmlns="http://www.w3.org/2000/svg"><defs>'
                 '<linearGradient id="a" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ff0000"/><stop offset="100%" stop-color="#0000ff" stop-opacity="0.5"/></linearGradient>'
                 '<radialGradient id="b" cx="150" cy="50" r="40" gradientUnits="userSpaceOnUse" gradientTransform="translate(5 0)"><stop offset="0" stop-color="white"/><stop offset="1" stop-color="#202020"/></radialGradient>'
                 '<linearGradient id="c" href="#a" x2="0"/></defs>'
                 '<rect width="90" height="90" fill="url(#a)"/><circle cx="150" cy="50" r="40" fill="url(#b)"/><rect y="92" width="200" height="8" fill="url(#c)"/></svg>\n')
CLIPPED_SVG = ('<svg width="100" height="100" viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg"><defs><clipPath id="k"><circle cx="50" cy="50" r="30"/></clipPath></defs>'
               '<g clip-path="url(#k)"><rect width="100" height="100" fill="#3080ff"/></g><path d="M0 0L20 0L0 20Z" fill="inherit" transform="skewX(10)"/></svg>\n')
STYLED_SVG = ('<svg width="100" height="100" viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg"><defs><style>.w { fill: #fff; } rect { fill-opacity: 0.8 }</style></defs>'
              '<rect class="w" x="10" y="10" width="80" height="80"/></svg>\n')
P3_WHITE_SVG = '<svg width="100" height="100" viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg"><rect width="100" height="100" fill="color(display-p3 0.9 0.9 0.95)"/></svg>\n'


def grid_pixel(x, y):
    """A gray, translucent grid: lines every 16 pixels, crosses every 64."""
    if x % 64 in (31, 32) and abs(y % 64 - 32) < 6 or y % 64 in (31, 32) and abs(x % 64 - 32) < 6:
        return (255, 255, 255, 200)
    return (255, 255, 255, 40) if x % 16 == 0 or y % 16 == 0 else (0, 0, 0, 0)


def icon(root, name, obj, assets):
    """An Icon Composer icon folder: icon.json and its Assets."""
    path = root / f"{name}.icon"
    if path.exists():
        shutil.rmtree(path)
    (path / "Assets").mkdir(parents=True)
    write_json(path / "icon.json", obj)
    for file, content in assets.items():
        if callable(content):
            content(path / "Assets" / file)
        else:
            (path / "Assets" / file).write_text(content)
    return path


def expo_like(root, name="Glyph"):
    return icon(root, name, {
        "fill": {"automatic-gradient": "extended-srgb:0.00000,0.47843,1.00000,1.00000"},
        "groups": [{"layers": [
            {"image-name": "glyph.svg", "name": "glyph", "position": {"scale": 1, "translation-in-points": [1.25e-05, -16.046875]}},
            {"image-name": "grid.png", "name": "grid"}],
            "shadow": {"kind": "neutral", "opacity": 0.5}, "translucency": {"enabled": True, "value": 0.5}}],
        "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
    }, {"glyph.svg": GLYPH_SVG, "grid.png": lambda path: png(path, 256, 256, grid_pixel)})


COMPOSITE = {
    "fill": {"linear-gradient": ["srgb:0.20000,0.40000,0.60000,1.00000", "display-p3:0.90000,0.30000,0.10000,1.00000"],
             "orientation": {"start": {"x": 0.1, "y": 0.2}, "stop": {"x": 0.8, "y": 0.9}}},
    "groups": [
        {"layers": [
            {"image-name": "glyph.svg", "name": "glyph", "position": {"scale": 0.5, "translation-in-points": [10.25, -20.5]}},
            {"image-name": "grid.png", "name": "grid", "opacity": 0.5, "fill": {"solid": "gray:0.25000,0.50000"}}],
         "shadow": {"kind": "layer-color", "opacity": 0.7}, "translucency": {"enabled": True, "value": 0.6}},
        {"layers": [
            {"image-name": "dot.svg", "name": "dot", "blend-mode": "multiply", "glass": False,
             "fill-specializations": [{"appearance": "dark", "value": {"linear-gradient": ["srgb:1.00000,0.00000,0.00000,1.00000", "gray:0.50000,1.00000"]}}]},
            {"image-name": "glyph.svg", "name": "copy", "hidden-specializations": [{"value": True}, {"appearance": "dark", "value": False}]}],
         "lighting": "combined", "specular": False, "blur-material": 0.25, "opacity": 0.8,
         "position": {"scale": 1.25, "translation-in-points": [3, 4]}},
        {"layers": [{"image-name": "dot.svg", "name": "gone"}], "hidden": True},
    ],
}


def exp_icons(root, nomac):
    icons = root / "icons"
    assets = {"glyph.svg": GLYPH_SVG, "dot.svg": DOT_SVG, "wide.svg": WIDE_SVG, "grid.png": lambda path: png(path, 64, 64, grid_pixel),
              "gradients.svg": GRADIENTS_SVG, "clipped.svg": CLIPPED_SVG, "styled.svg": STYLED_SVG, "p3white.svg": P3_WHITE_SVG}
    expo = expo_like(icons / "expo")
    composite = icon(icons / "composite", "Composite", COMPOSITE, assets)
    reports = [case(root, f"expo-{target or 'none'}", [expo], nomac, ["--app-icon", "Glyph"] + (["--target-device", target] if target else []),
                    args=[a for a in ACTOOL_ARGS if a not in ("--target-device", "iphone", "ipad")])
               for target in ("iphone", "ipad", None)]
    reports.append(case(root, "expo-both", [expo], nomac, ["--app-icon", "Glyph"]))
    reports.append(case(root, "expo-not-named", [expo], nomac))
    alt = icon(icons / "alternates", "Alt", {"fill": {"solid": "srgb:1.00000,0.00000,0.00000,1.00000"}, "groups": [{"layers": [{"image-name": "dot.svg", "name": "dot"}]}]}, assets)
    other = icon(icons / "alternates", "Other", {"groups": [{"layers": [{"image-name": "dot.svg", "name": "dot"}]}]}, assets)
    colors = catalog(icons / "alternates" / "A.xcassets", {"Red": red()})
    iphone = [a for i, a in enumerate(ACTOOL_ARGS) if a != "ipad" and not (a == "--target-device" and ACTOOL_ARGS[i + 1] == "ipad")]
    for name, inputs, extra, args in [
        ("alternate", [expo, alt], ["--app-icon", "Glyph", "--alternate-app-icon", "Alt"], ACTOOL_ARGS),
        ("alternates-two", [expo, alt, other], ["--app-icon", "Glyph", "--alternate-app-icon", "Other", "--alternate-app-icon", "Alt"], ACTOOL_ARGS),
        ("alternates-all", [expo, alt, other, colors], ["--app-icon", "Glyph", "--include-all-app-icons", "--standalone-icon-behavior", "all"], ACTOOL_ARGS),
        ("alternate-only", [expo, alt], ["--alternate-app-icon", "Alt"], ACTOOL_ARGS),
        ("alternate-iphone", [expo, alt], ["--app-icon", "Glyph", "--alternate-app-icon", "Alt"], iphone),
        ("alternate-not-named", [expo, alt], ["--app-icon", "Glyph"], ACTOOL_ARGS),
    ]:
        reports.append(case(root, name, inputs, nomac, extra, args=args))
    runs = case(root, "composite-runs", [composite], nomac, ["--app-icon", "Composite"], runs=2)
    a, b = (root / "composite-runs" / f"actool-{i}" / "Assets.car" for i in (0, 1))
    runs["actool-runs"] = compare_icon_car(a.read_bytes(), b.read_bytes())
    reports.append(runs)

    def batch(name, cases):
        folder = icons / name
        paths = [icon(folder, key, obj, assets) for key, obj in cases.items()]
        return case(root, name, paths, nomac)

    R, B, G = "srgb:1.00000,0.00000,0.00000,1.00000", "srgb:0.00000,0.00000,1.00000,1.00000", "srgb:0.00000,1.00000,0.00000,1.00000"
    layer = lambda image="dot.svg", **kw: dict({"image-name": image, "name": image.split(".")[0]}, **kw)
    group = lambda layers=None, **kw: dict({"layers": layers or [layer()]}, **kw)
    spec = lambda key, *pairs: {key + "-specializations": [dict(({"appearance": a} if a else {}), value=v) for a, v in pairs]}
    reports.append(batch("fills", {
        "F01": {"groups": [group()]},
        "F02": {"fill": {"solid": R}, "groups": [group([layer(fill={"solid": R})])]},
        "F03": {"fill": {"linear-gradient": [R, B]}, "groups": [group()]},
        "F04": {"fill": "automatic", "groups": [group()]},
        "F05": {"fill": "system-dark", "groups": [group()]},
        "F06": {"fill": "none", "groups": [group()]},
        "F07": {"fill": {"automatic-gradient": "gray:0.50000,1.00000", "orientation": {"start": {"x": 0.1, "y": 0.2}, "stop": {"x": 0.3, "y": 0.4}}}, "groups": [group()]},
        "F08": {"fill": {"solid": "srgb:0.12345,0.12350,0.12450,0.00050"}, "groups": [group()]},
        "F09": {**spec("fill", (None, {"solid": R}), ("dark", {"solid": B}), ("tinted", {"solid": G})), "groups": [group()]},
        "F10": {**spec("fill", ("dark", "system-light")), "groups": [group()]},
        "F11": {**spec("fill", (None, "automatic"), ("dark", {"solid": B})), "groups": [group()]},
        "F12": {"fill": {"solid": R}, **spec("fill", ("dark", {"solid": B})), "groups": [group()]},
        "F13": {"groups": [group([layer(**spec("fill", ("light", {"solid": R})))]), group([layer("wide.svg", **spec("fill", (None, {"solid": R}), ("tinted", "none")))])]},
        "F14": {"groups": [group([layer(fill={"solid": "extended-srgb:1.20000,-0.10000,0.50000,1.00000"}), layer("wide.svg", fill={"solid": "extended-gray:0.50000,1.00000"})])]},
    }))
    reports.append(batch("groups", {
        "G01": {"groups": [group(), group([layer("wide.svg")])]},
        "G02": {"groups": [group(shadow={"kind": "none", "opacity": 0.5}, translucency={"enabled": False, "value": 0.5})]},
        "G03": {"groups": [group(specular=False, lighting="combined", opacity=0.6, **{"blur-material": 0.5})]},
        "G04": {"groups": [group(), group([layer("wide.svg")], hidden=True), group([layer("wide.svg")])]},
        "G05": {"groups": [group([layer(opacity=0.5), layer("wide.svg", **{"blend-mode": "plus-lighter"}), layer("grid.png", glass=False)])]},
        "G06": {"groups": [group([layer(hidden=True), layer("wide.svg")])]},
        "G07": {"groups": [group([layer(**spec("hidden", (None, True), ("dark", False))), layer("wide.svg")])]},
        "G08": {"groups": [group([layer(**spec("hidden", ("light", True), ("dark", True), ("tinted", True))), layer("wide.svg")])]},
    }))
    pos = lambda s, x, y: {"position": {"scale": s, "translation-in-points": [x, y]}}
    reports.append(batch("positions", {
        "P01": {"groups": [group([layer(**pos(0.33, 0.5, 0.25))])]},
        "P02": {"groups": [group([layer(**pos(1.5, -0.5, -0.75))])]},
        "P03": {"groups": [group([layer(**pos(0.5, 10, 20))], **pos(2, 30, -40))]},
        "P04": {"groups": [group([layer(**pos(1, 0.4999, 0.5001))])]},
        "P05": {"groups": [group([layer("wide.svg", **pos(1.24, 1.5, 2.5))])]},
        "P06": {"groups": [group([layer("grid.png", **pos(0.7, 3, 3))])]},
        "P07": {"groups": [group([layer("glyph.svg", **pos(0.25, -96.51953125, 186.1796875))])]},
    }))
    assets["opaque.png"] = lambda path: png(path, 32, 32, lambda x, y: (x * 8, y * 8, 128, 255))
    assets["palette.png"] = lambda path: tagged_png(path, 32, 32, lambda x, y: ((x + y) % 4,), b"", 3, bytes([255, 0, 0, 0, 255, 0, 0, 0, 255, 9, 9, 9]))
    reports.append(batch("specializations", {
        "S01": {"groups": [group([layer(**spec("opacity", ("light", 0.3)))])]},
        "S02": {"groups": [group([layer(**spec("opacity", (None, 0.5), ("tinted", 0.2)))])]},
        "S03": {"groups": [group([layer(opacity=0.7, **spec("opacity", ("dark", 0.4)))])]},
        "S04": {"groups": [group([layer(**spec("blend-mode", ("light", "multiply")), **spec("glass", (None, True), ("dark", False)))])]},
        "S05": {"groups": [group(**spec("translucency", ("light", {"enabled": True, "value": 0.6})), **spec("shadow", ("dark", {"kind": "layer-color", "opacity": 0.8})))]},
        "S06": {"groups": [group(**spec("hidden", ("dark", True))), group([layer("wide.svg")], **spec("blend-mode", (None, "multiply"), ("tinted", "normal")))]},
        "S07": {"groups": [group([layer(**spec("position", (None, {"scale": 1, "translation-in-points": [10, 0]}), ("dark", {"scale": 2, "translation-in-points": [0, 10]})))],
                                 **spec("lighting", ("dark", "combined")), **spec("blur-material", (None, 0.2), ("tinted", 0.9)))]},
        "S08": {"groups": [group([layer(**spec("fill", ("dark", "automatic"), ("tinted", {"solid": B}))), layer("wide.svg", **spec("fill", (None, {"solid": R}), ("tinted", "automatic")))])]},
        "S09": {"fill": {"automatic-gradient": G}, "groups": [group([layer("glyph.svg", **spec("fill", ("dark", "none")))])]},
        "S10": {"groups": [group(name="Front"), group([layer("wide.svg")], name="Front"), group([layer("wide.svg")]), group(name="A/B")]},
        "S11": {"color-space-for-untagged-svg-colors": "display-p3", "groups": [group([layer("glyph.svg")])]},
        "S12": {"groups": [group([layer("grid.png"), layer("opaque.png"), layer("palette.png")])]},
    }))
    reports.append(batch("svg", {
        "V01": {"groups": [group([layer("gradients.svg")])]},
        "V02": {"groups": [group([layer("clipped.svg")])]},
        "V03": {"fill": {"automatic-gradient": G}, "groups": [group([layer("styled.svg")])]},
        "V04": {"fill": {"automatic-gradient": G}, "groups": [group([layer("p3white.svg")])]},
    }))
    colors = ["#FFFFFF", "#D9D9D9", "#D8D8D8", "#FFC0C0", "#FFB6B6", "#B0FFB0", "#C8E8C8", "#E8C8C8", "#E2D2D2", "#EAC3F0", "#808080"]
    for i, color in enumerate(colors):
        assets[f"c{i}.svg"] = SQUARE_SVG.format(color)
    reports.append(batch("white", {f"W{i:02d}": {"fill": {"automatic-gradient": "srgb:0.20000,0.40000,0.60000,1.00000"}, "groups": [group([layer(f"c{i}.svg")])]}
                                   for i in range(len(colors))}))
    return reports


def icc_profile(name, primaries, curve, version=4, gray=False):
    """A matrix/TRC (or gray TRC) ICC profile written from ICC.1:2010: D65 primaries adapted to
    D50 with Bradford, s15Fixed16 colorants, one curve for every channel."""
    import numpy as np
    d50 = np.array([0.9642, 1.0, 0.8249])
    xyz = lambda x, y: np.array([x / y, 1.0, (1 - x - y) / y])
    bradford = np.array([[0.8951, 0.2664, -0.1614], [-0.7502, 1.7135, 0.0367], [0.0389, -0.0685, 1.0296]])
    white = xyz(0.3127, 0.3290)
    adapt = np.linalg.inv(bradford) @ np.diag((bradford @ d50) / (bradford @ white)) @ bradford
    s15 = lambda v: struct.pack(">i", int(round(v * 65536)))
    xyz_tag = lambda v: b"XYZ " + bytes(4) + b"".join(s15(c) for c in v)
    text = name.encode("utf-16-be")
    desc = b"mluc" + bytes(4) + struct.pack(">II", 1, 12) + b"enUS" + struct.pack(">II", len(text), 28) + text
    if version == 2:
        desc = b"desc" + bytes(4) + struct.pack(">I", len(name) + 1) + name.encode() + bytes(1) + bytes(79)
    tags = [(b"desc", desc), (b"wtpt", xyz_tag(d50))]
    if gray:
        tags.append((b"kTRC", curve))
    else:
        p = np.stack([xyz(*c) for c in primaries], 1)
        m = adapt @ (p * np.linalg.solve(p, white))
        tags += [(b"rXYZ", xyz_tag(m[:, 0])), (b"gXYZ", xyz_tag(m[:, 1])), (b"bXYZ", xyz_tag(m[:, 2])),
                 (b"rTRC", curve), (b"gTRC", curve), (b"bTRC", curve)]
    tags.append((b"cprt", desc))
    offset = 128 + 4 + 12 * len(tags)
    table, body, placed = b"", b"", {}
    for sig, data in tags:
        if data not in placed:
            pad = (-offset) % 4
            body += bytes(pad)
            offset += pad
            placed[data] = offset
            body += data
            offset += len(data)
        table += sig + struct.pack(">II", placed[data], len(data))
    size = 128 + 4 + 12 * len(tags) + len(body)
    header = (struct.pack(">I", size) + b"none" + (b"\x04\x30\0\0" if version == 4 else b"\x02\x10\0\0") + b"mntr"
              + (b"GRAY" if gray else b"RGB ") + b"XYZ " + struct.pack(">6H", 2026, 10, 30, 0, 0, 0) + b"acspAPPL" + bytes(20)
              + bytes(4) + b"".join(s15(c) for c in d50) + b"none" + bytes(44))
    return header + struct.pack(">I", len(tags)) + table + body


def para(*values):
    s15 = lambda v: struct.pack(">i", int(round(v * 65536)))
    return b"para" + bytes(4) + struct.pack(">H", 0 if len(values) == 1 else 3) + bytes(2) + b"".join(s15(v) for v in values)


def tagged_png(path, width, height, pixel, profile, color_type=2, palette=None):
    import zlib
    channels = {0: 1, 2: 3, 3: 1, 6: 4}[color_type]
    rows = b"".join(b"\0" + bytes(c for x in range(width) for c in pixel(x, y)[:channels]) for y in range(height))
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, color_type, 0, 0, 0))
                     + (chunk(b"iCCP", b"icc\0\0" + zlib.compress(profile)) if profile else b"") + (chunk(b"PLTE", palette) if palette else b"")
                     + chunk(b"IDAT", zlib.compress(rows, 6)) + chunk(b"IEND", b""))


def cube(x, y):
    """A million colors: red and green from x and y, sixteen blues within each 4 × 4 block."""
    return (x // 4, y // 4, ((x % 4) * 4 + (y % 4)) * 17, 255)


def app_icon_pixels(car):
    """The 1,024-pixel app icon image's RGB values, from its LZFSE bands (libcompression)."""
    import ctypes
    lib = ctypes.CDLL("/usr/lib/libcompression.dylib")
    lib.compression_decode_buffer.restype = ctypes.c_size_t
    lib.compression_decode_buffer.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_int]
    blocks, variables = bom(car)
    for value, _ in tree_entries(blocks, dict(variables)["RENDITIONS"]):
        csi = blocks[value]
        if csi[:4] != b"ISTC" or struct.unpack_from("<I", csi, 12)[0] != 1024 or struct.unpack_from("<H", csi, 36)[0] != 12:
            continue
        payload = csi[184 + struct.unpack_from("<I", csi, 168)[0]:]
        if payload[8:12] != b"\x04\0\0\0":
            continue
        count, o, out = struct.unpack_from("<I", payload, 12)[0], 16, b""
        for _ in range(count):
            rows, length = struct.unpack_from("<II", payload, o + 12)
            dst = ctypes.create_string_buffer(rows * 4096 + 64)
            src = ctypes.create_string_buffer(payload[o + 20:o + 20 + length], length)
            n = lib.compression_decode_buffer(dst, len(dst), src, length, None, 0x801 if payload[o + 20:o + 23] == b"bvx" else 0x900)
            out += dst.raw[:min(n, rows * 4096)]
            o += 20 + length
        return [(out[i + 2], out[i + 1], out[i]) for i in range(0, len(out), 4)]
    return None


def exp_profiles(root, nomac):
    srgb_curve = para(2.4, 1 / 1.055, 0.055 / 1.055, 1 / 12.92, 0.04045)
    srgb, p3, adobe = [(0.64, 0.33), (0.30, 0.60), (0.15, 0.06)], [(0.680, 0.320), (0.265, 0.690), (0.150, 0.060)], [(0.64, 0.33), (0.21, 0.71), (0.15, 0.06)]
    table = b"curv" + bytes(4) + struct.pack(">I", 256) + b"".join(struct.pack(">H", int(round(65535 * (i / 255) ** 1.8))) for i in range(256))
    profiles = {
        "p3": icc_profile("Display P3 (nomac)", p3, srgb_curve),
        "srgb-like": icc_profile("sRGB built-in (nomac)", srgb, srgb_curve),
        "adobe-like": icc_profile("Adobe RGB-like (nomac)", adobe, b"curv" + bytes(4) + struct.pack(">IH", 1, 563), version=2),
        "table18": icc_profile("Table 1.8 (nomac)", srgb, table, version=2),
        "gamma22": icc_profile("Gamma 2.2 (nomac)", srgb, para(2.2)),
    }
    reports = []
    muted = lambda x, y: (100 + x % 50, 100 + y % 50, 120 + (x + y) % 40, 255)
    for name, profile, pixel in [(n, p, cube) for n, p in profiles.items()] + [("p3-muted", profiles["p3"], muted)]:
        for alpha in (255, 128):
            cat = catalog(root / "catalogs" / f"{name}-{alpha}" / "A.xcassets", {})
            icons = cat / "AppIcon.appiconset"
            tagged_png(icons / "big.png", 1024, 1024, lambda x, y: pixel(x, y)[:3] + (alpha,), profile, 2 if alpha == 255 else 6)
            tagged_png(icons / "small.png", 120, 120, lambda x, y: pixel(x * 8, y * 8)[:3] + (alpha,), profile, 2 if alpha == 255 else 6)
            write_json(icons / "Contents.json", {"images": [{"filename": "small.png", "idiom": "iphone", "scale": "2x", "size": "60x60"},
                                                            {"filename": "big.png", "idiom": "ios-marketing", "scale": "1x", "size": "1024x1024"}], **INFO})
            tagged_png(cat / "Photo.imageset" / "photo.png", 300, 200, lambda x, y: pixel(x * 3, y * 5)[:3] + (alpha,), profile, 2 if alpha == 255 else 6)
            write_json(cat / "Photo.imageset" / "Contents.json", {"images": [{"filename": "photo.png", "idiom": "universal", "scale": "1x"}], **INFO})
            iphone = [a for i, a in enumerate(ACTOOL_ARGS) if a != "ipad" and not (a == "--target-device" and ACTOOL_ARGS[i + 1] == "ipad")]
            report = case(root, f"{name}-{alpha}", [cat], nomac, ["--app-icon", "AppIcon"], args=iphone)
            cars = [root / f"{name}-{alpha}" / side / "Assets.car" for side in ("actool", "nomac")]
            if nomac and all(car.exists() for car in cars):
                a, n = (app_icon_pixels(car.read_bytes()) for car in cars)
                if a and n:
                    report["exact-pixels"] = round(sum(p == q for p, q in zip(a, n)) / len(a), 4)
                    report["within-1"] = round(sum(max(abs(i - j) for i, j in zip(p, q)) <= 1 for p, q in zip(a, n)) / len(a), 4)
            reports.append(report)
    cat = catalog(root / "catalogs" / "forms" / "A.xcassets", {})
    gray = icc_profile("Gray 2.2 (nomac)", None, para(2.2), gray=True)
    tagged_png(cat / "Gray.imageset" / "gray.png", 64, 64, lambda x, y: ((x * 4 + y) % 256,), gray, 0)
    write_json(cat / "Gray.imageset" / "Contents.json", {"images": [{"filename": "gray.png", "idiom": "universal", "scale": "1x"}], **INFO})
    palette = bytes(c for i in range(16) for c in (i * 16, 255 - i * 16, (i * 37) % 256))
    tagged_png(cat / "Palette.imageset" / "palette.png", 64, 64, lambda x, y: ((x + y) % 16,), profiles["p3"], 3, palette)
    write_json(cat / "Palette.imageset" / "Contents.json", {"images": [{"filename": "palette.png", "idiom": "universal", "scale": "1x"}], **INFO})
    reports.append(case(root, "gray-and-palette", [cat], nomac))
    # A wide image (gets its display-gamut-1 rendition, never packed) packed beside plain ones,
    # and a wide single-size app icon (its rendition in the plain payload).
    cat = catalog(root / "catalogs" / "wide" / "A.xcassets", {})
    tagged_png(cat / "Wide.imageset" / "wide.png", 8, 8, lambda x, y: (255, 10 * x, 0, 255 - 20 * y), profiles["p3"], 6)
    write_json(cat / "Wide.imageset" / "Contents.json", {"images": [{"filename": "wide.png", "idiom": "universal", "scale": "1x"}], **INFO})
    for name, shade in (("Plain", 100), ("Plain2", 10)):
        png_rgb(cat / f"{name}.imageset" / f"{name.lower()}.png", 8, 8, lambda x, y, s=shade: (s, 10 * x, 30 * y))
        write_json(cat / f"{name}.imageset" / "Contents.json", {"images": [{"filename": f"{name.lower()}.png", "idiom": "universal", "scale": "1x"}], **INFO})
    tagged_png(cat / "AppIcon.appiconset" / "icon.png", 1024, 1024, lambda x, y: (255, (x // 4) % 256, 0), profiles["p3"], 2)
    write_json(cat / "AppIcon.appiconset" / "Contents.json", {**INFO, "images": [{"filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}]})
    # The threshold: Display P3 colors just outside sRGB, below 0 and above 1 in linear sRGB
    # (−0.0006, −0.0012, −0.0017, −0.0024; 1.0063, 1.0073, 1.0083, 1.0095).
    for name, color in {"under-6": (102, 15, 34), "under-12": (147, 39, 17), "under-17": (6, 36, 187), "under-24": (27, 75, 136),
                        "over-63": (237, 255, 170), "over-73": (234, 255, 255), "over-83": (231, 255, 85), "over-95": (204, 252, 255)}.items():
        tagged_png(cat / f"T-{name}.imageset" / "t.png", 2, 2, lambda x, y, c=color: c + (255,), profiles["p3"], 2)
        write_json(cat / f"T-{name}.imageset" / "Contents.json", {"images": [{"filename": "t.png", "idiom": "universal", "scale": "1x"}], **INFO})
    # 16-bit PNGs with a Display P3 profile (icecubes' icons): converted, a wide one with its
    # RGBW rendition; untagged 16-bit PNGs, which actool dithers, stop nomac.
    def png16(path, width, height, color_type, pixel):
        import zlib
        rows = b"".join(b"\0" + b"".join(struct.pack(f">{len(pixel(x, y))}H", *pixel(x, y)) for x in range(width)) for y in range(height))
        def chunk(kind, data):
            return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
        iccp = b"Display P3\0\0" + zlib.compress(profiles["p3"])
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 16, color_type, 0, 0, 0)) + chunk(b"iCCP", iccp)
                         + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))
    png16(cat / "Deep.imageset" / "deep.png", 8, 4, 6, lambda x, y: (65535, x * 2000, 0, 40000 + 3000 * x))
    png16(cat / "Muted.imageset" / "muted.png", 8, 4, 2, lambda x, y: (30000 + x * 100, 30000, 31000))
    for name in ("Deep", "Muted"):
        write_json(cat / f"{name}.imageset" / "Contents.json", {"images": [{"filename": f"{name.lower()}.png", "idiom": "universal", "scale": "1x"}], **INFO})
    report = case(root, "wide", [cat], nomac, ["--app-icon", "AppIcon"])
    if nomac:
        report["compare"] = compare(root / "wide" / "actool", root / "wide" / "nomac", converted_files([cat]), resized=True)
    reports.append(report)
    return reports


def exp_vector_images(root, nomac):
    """SVG image sets (with and without preserves-vector-representation, fractional sizes, the
    file in a 1x, 2x or 3x entry) and
    JPEG image sets (each kind of segment, several scales)."""
    import zlib as _zlib
    cats = root / "catalogs"
    svg = catalog(cats / "svg" / "A.xcassets", {})
    sizes = [(10.5, 7.25), (10.25, 7.75), (10.75, 7.5), (9.4, 6.6), (12.5, 12.5), (40.2, 30.6)]
    for i, (w, h) in enumerate(sizes):
        for props in ({}, {"preserves-vector-representation": True}):
            name = f"S{i}{'v' if props else ''}"
            d = svg / f"{name}.imageset"
            d.mkdir(parents=True)
            (d / f"{name.lower()}.svg").write_text(f'<svg width="{w}" height="{h}" viewBox="0 0 {w * 2} {h * 2}" xmlns="http://www.w3.org/2000/svg">'
                                                   f'<rect x="1" y="1" width="{w * 2 - 2}" height="{h * 2 - 2}" fill="#e04020"/></svg>\n')
            write_json(d / "Contents.json", {"images": [{"filename": f"{name.lower()}.svg", "idiom": "universal"}], **INFO, **({"properties": props} if props else {})})
    for slot in ("1x", "2x", "3x"):
        for props in ({}, {"preserves-vector-representation": True}):
            name = f"Slot{slot}{'v' if props else ''}"
            d = svg / f"{name}.imageset"
            d.mkdir(parents=True)
            (d / f"{name.lower()}.svg").write_text('<svg width="10.5" height="7.25" viewBox="0 0 21 14.5" xmlns="http://www.w3.org/2000/svg">'
                                                   '<rect x="1" y="1" width="19" height="12.5" fill="#e04020"/></svg>\n')
            images = [dict({"idiom": "universal", "scale": scale}, **({"filename": f"{name.lower()}.svg"} if scale == slot else {})) for scale in ("1x", "2x", "3x")]
            write_json(d / "Contents.json", {"images": images, **INFO, **({"properties": props} if props else {})})
    # Rasters that fill their image, stored alone: their payload is opaque (CELM flag 2, opaque
    # gray rows), their flags and packing class translucent.
    for name, fill in (("Opaque", "#e04020"), ("OpaqueGray", "#808080")):
        d = svg / f"{name}.imageset"
        d.mkdir(parents=True)
        (d / f"{name.lower()}.svg").write_text(f'<svg width="200" height="200" viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg"><rect width="200" height="200" fill="{fill}"/></svg>\n')
        write_json(d / "Contents.json", {"images": [{"filename": f"{name.lower()}.svg", "idiom": "universal"}], **INFO})
    d = svg / "Bitmap.imageset"
    d.mkdir(parents=True)
    png_rgb(d / "bitmap.png", 12, 9, lambda x, y: (40, 20 * x % 256, 30 * y % 256))
    write_json(d / "Contents.json", {"images": [{"filename": "bitmap.png", "idiom": "universal"}], **INFO, "properties": {"preserves-vector-representation": True}})
    jpg = catalog(cats / "jpg" / "A.xcassets", {})
    base = jpeg_file(40, 30)
    def segment(marker, body):
        return bytes([0xFF, marker]) + struct.pack(">H", len(body) + 2) + body
    jfif = segment(0xE0, b"JFIF\x00\x01\x01\x00\x00H\x00H\x00\x00")
    variants = {
        "bare": b"", "jfif": jfif, "exif": segment(0xE1, b"Exif\x00\x00MM\x00*\x00\x00\x00\x08\x00\x00\x00\x00\x00\x00"),
        "xmp": segment(0xE1, b"http://ns.adobe.com/xap/1.0/\x00<x:xmpmeta/>"), "icc": segment(0xE2, b"ICC_PROFILE\x00\x01\x01" + b"\x00" * 128),
        "photoshop": segment(0xED, b"Photoshop 3.0\x008BIM\x04\x04\x00\x00\x00\x00\x00\x00"), "adobe": segment(0xEE, b"Adobe\x00\x64\x00\x00\x00\x00\x01"),
        "comment": segment(0xFE, b"hello"), "app12": segment(0xEC, b"Ducky\x00\x01\x00\x04\x00\x00\x00\x3c\x00\x00"), "app9": segment(0xE9, b"xyz"),
    }
    for name, extra in variants.items():
        d = jpg / f"{name}.imageset"
        d.mkdir(parents=True)
        (d / f"{name}.jpg").write_bytes(b"\xff\xd8" + (jfif if name not in ("bare", "jfif") else b"") + extra + base)
        write_json(d / "Contents.json", {"images": [{"filename": f"{name}.jpg", "idiom": "universal", "scale": "1x"}], **INFO})
    d = jpg / "Scales.imageset"
    d.mkdir(parents=True)
    for scale in ("1x", "2x", "3x"):
        (d / f"p{scale}.jpg").write_bytes(b"\xff\xd8" + jfif + base)
    write_json(d / "Contents.json", {"images": [{"filename": f"p{s}.jpg", "idiom": "universal", "scale": s} for s in ("1x", "2x", "3x")], **INFO})
    return [case(root, "svg", [svg], nomac), case(root, "jpeg", [jpg], nomac)]


def symbol_template(version="3.0", guide="line", stroked=False, stroke_width=None, glyph_extra="", glyph_transform=None, style="", path_class=None,
                    v1=False):
    """A symbol template written from the SF Symbols template's documented layout: baseline and
    capline guides per size, margin guides and Ultralight/Regular/Black-S glyphs (or, `v1`, one
    Regular-M glyph, the version in a tspan and margins as rectangles whose widths are the margins)."""
    sizes = {"S": 696, "M": 1126, "L": 1556}
    def line(id, x1, y1, x2, y2):
        if guide == "path":
            return f'<path id="{id}" d="M{x1},{y1} l{x2 - x1},{y2 - y1}"/>'
        return f'<line id="{id}" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="{x1}" x2="{x2}" y1="{y1}" y2="{y2}"/>'
    def shape(t):
        return f"M{10 - t} 0L{50 + t} 0C{60 + t} 0 {60 + t} -70 {50 + t} -70L{10 - t} -70C{-t} -70 {-t} 0 {10 - t} 0Z"
    width = (' stroke="#27AAE1"' if stroked else "") + (f' stroke-width="{stroke_width}"' if stroke_width is not None else "")
    guides = "".join(line(f"Baseline-{k}", 263, y, 3036, y) + line(f"Capline-{k}", 263, round(y - 70.459, 3), 3036, round(y - 70.459, 3)) for k, y in sizes.items())
    cls = f' class="{path_class}"' if path_class else ""
    if v1:
        return (f'<svg version="1.1" xmlns="http://www.w3.org/2000/svg" width="3300" height="2200"><g id="Notes"><text><tspan x="3036" y="1933">Template v.1.0</tspan></text></g>'
                f'<g id="Guides" transform="translate(263, 625)">{guides.replace("263", "0")}'
                f'<rect id="left-margin" x="1128.3" y="405.79" width="8.74023" height="119.336"/><rect id="right-margin" x="1236.65" y="405.79" width="12.5" height="119.336"/></g>'
                f'<g id="Symbols" transform="translate(1399, 1016)"><g id="Regular-M" transform="translate(1, 110)"><path{cls} d="{shape(0)}"/>{glyph_extra}</g></g></svg>\n')
    margins, glyphs = "", ""
    for name, x, t in (("Ultralight-S", 515.649, -2), ("Regular-S", 1403.58, 0), ("Black-S", 2291.51, 3)):
        margins += line(f"left-margin-{name}", x, 600.785, x, 720.121) + line(f"right-margin-{name}", x + 60 + 2 * abs(t) + 7, 600.785, x + 60 + 2 * abs(t) + 7, 720.121)
        transform = glyph_transform or f"matrix(1 0 0 1 {x} 696)"
        glyphs += f'<g id="{name}" transform="{transform}"><path{cls} d="{shape(t)}"/>{glyph_extra}</g>'
    return (f'<svg version="1.1" xmlns="http://www.w3.org/2000/svg" width="3300" height="2200">'
            f'<style>{style}</style><g id="Notes"><text id="template-version">Template v.{version}</text></g>'
            f'<g id="Guides"{width}>{guides}{margins}</g><g id="Symbols">{glyphs}</g></svg>\n')


def exp_symbol_sets(root, nomac):
    """Symbol sets: guides as lines or paths (a path margin sits half its stroke width left of its
    start), stroke widths, rendering intents (property 1019), nested and stroked glyph groups,
    glyph scaling, style-sheet strokes and vendor properties, and template 1's layout."""
    wireframe = ".monochrome-0 {-sfsymbols-motion-group:1;opacity:1.0} .SFSymbolsPreviewWireframe {fill:none;opacity:1.0;stroke:black;stroke-width:0.5}"
    arrow = '<g id="Arrow" transform="translate(20, -30) scale(1, -1)" stroke="#000000" stroke-width="0.2"><path d="M0 0L10 -10L20 0Z" id="Shape" sodipodi:nodetypes="ccc"/></g>'
    cases = {
        "lines": ({}, {}), "paths": ({"guide": "path"}, {}), "paths-2": ({"guide": "path", "stroke_width": 2}, {}),
        "paths-stroked": ({"guide": "path", "stroked": True}, {}), "paths-stroked-2": ({"guide": "path", "stroked": True, "stroke_width": 2}, {}),
        "template": ({}, {"symbol-rendering-intent": "template"}), "multicolor": ({}, {"symbol-rendering-intent": "multicolor"}),
        "hierarchical": ({}, {"symbol-rendering-intent": "hierarchical"}), "original": ({}, {"symbol-rendering-intent": "original"}),
        "nested": ({"glyph_extra": arrow, "version": "4.0"}, {}),
        "scaled": ({"glyph_transform": "matrix(1.02,0,0,0.98,1400,700)"}, {}),
        "wireframe": ({"style": wireframe, "path_class": "monochrome-0 SFSymbolsPreviewWireframe", "version": "5.0"}, {}),
        "v1": ({"v1": True}, {}),
    }
    reports = []
    for name, (template, properties) in cases.items():
        cat = catalog(root / "catalogs" / name / "A.xcassets", {})
        d = cat / f"{name}.symbolset"
        d.mkdir(parents=True)
        (d / f"{name}.svg").write_text(symbol_template(**template).replace("<svg ", '<svg xmlns:sodipodi="http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd" ', 1))
        write_json(d / "Contents.json", {**INFO, "symbols": [{"filename": f"{name}.svg", "idiom": "universal"}], **({"properties": properties} if properties else {})})
        reports.append(case(root, name, [cat], nomac))
    return reports


def watch_args(target="9.0"):
    """ACTOOL_ARGS for a watchOS app: --target-device watch, --platform watchos."""
    args = [a for i, a in enumerate(ACTOOL_ARGS) if a not in ("iphone", "ipad") and not (a == "--target-device" and ACTOOL_ARGS[i + 1] in ("iphone", "ipad"))]
    args[args.index("18.0")] = target
    args[args.index("iphoneos")] = "watchos"
    return args[:-2] + ["--target-device", "watch"] + args[-2:]


# A complication role's image size in pixels at 2x for the 38mm, 40mm, 42mm and 44mm screen
# widths (actool's size warnings, pocket-casts' images); None: the graphic roles' 38mm and 42mm
# entries, which Xcode's template leaves empty.
DARK = [{"appearance": "luminosity", "value": "dark"}]
LIGHT = [{"appearance": "luminosity", "value": "light"}]


def exp_image_appearances(root, nomac):
    """Image sets with luminosity appearances (home-assistant's, mastodon's, mattermost's and
    pocket-casts' widget images): PNG entries at each scale and without one, light and dark, an
    empty dark entry, any with light and dark, dark alone, SVG and JPEG pairs, images too big to
    pack, gray and opaque ones, and a high-contrast entry."""
    reports = []
    cat = catalog(root / "catalogs" / "image-appearances" / "A.xcassets", {})
    def image_set(name, entries):
        d = cat / f"{name}.imageset"
        d.mkdir()
        images = []
        for i, (appearances, scale, size, kind) in enumerate(entries):
            entry = {"idiom": "universal", **({"scale": scale} if scale else {}), **({"appearances": appearances} if appearances else {})}
            if kind:
                w, h = size
                file = f"{name.lower()}-{i}.{'jpg' if kind == 'jpeg' else 'svg' if kind == 'svg' else 'png'}"
                dark = appearances == DARK
                if kind == "jpeg":
                    (d / file).write_bytes(b"\xff\xd8" + jpeg_file(w, h))
                elif kind == "svg":
                    color = "#202040" if dark else "#e0c020"
                    (d / file).write_text(f'<svg width="{w}" height="{h}" viewBox="0 0 {w} {h}" xmlns="http://www.w3.org/2000/svg"><circle cx="{w / 2}" cy="{h / 2}" r="{min(w, h) / 3}" fill="{color}"/></svg>\n')
                elif kind == "gray":
                    png_form(d / file, w, h, 8, 4, lambda x, y, dark=dark: (40 if dark else 220, (x * 9) % 256))
                elif kind == "opaque":
                    png_rgb(d / file, w, h, lambda x, y, dark=dark, i=i: (20 if dark else 230, x % 256, (y + i * 30) % 256))
                else:
                    png_form(d / file, w, h, 8, 6, lambda x, y, dark=dark, i=i: (10 if dark else 240, x % 256, i * 40, 255 if (x + y) % 5 else 0))
                entry["filename"] = file
            images.append(entry)
        write_json(d / "Contents.json", {"images": images, **INFO})
    scaled = lambda kind="png": [(a, f"{k}x", (12 * k, 10 * k), kind) for k in (1, 2, 3) for a in (None, DARK)]
    image_set("Scaled", scaled())
    image_set("Gray", scaled("gray"))
    image_set("Opaque", scaled("opaque"))
    image_set("Unscaled", [(None, None, (30, 20), "png"), (DARK, None, (30, 20), "png")])
    image_set("EmptyDark", [(None, "1x", (14, 14), "png"), (DARK, "1x", None, None), (None, "2x", (28, 28), "png"), (DARK, "2x", (28, 28), "png")])
    image_set("AnyLightDark", [(a, "2x", (16, 16), "png") for a in (None, LIGHT, DARK)])
    image_set("DarkOnly", [(DARK, "2x", (18, 16), "png")])
    image_set("Big", [(a, "2x", (700, 600), "png") for a in (None, DARK)])
    image_set("Vector", [(None, None, (20, 16), "svg"), (DARK, None, (20, 16), "svg")])
    image_set("Photo", [(a, "2x", (40, 30), "jpeg") for a in (None, DARK)])
    reports.append(case(root, "image-appearances", [cat], nomac))
    reports.append(case(root, "image-appearances-watch", [cat], nomac, args=watch_args("9.0")))
    contrast = catalog(root / "catalogs" / "image-contrast" / "A.xcassets", {
        "Shade": [entry(rgb("0.900", "0.900", "0.900")), entry(rgb("0.100", "0.100", "0.100"), appearances=DARK),
                  entry(rgb("1.000", "1.000", "1.000"), appearances=LIGHT), entry(rgb("0.000", "0.000", "0.000"), appearances=[{"appearance": "contrast", "value": "high"}])]})
    cat = contrast
    image_set("Contrast", [(None, "2x", (16, 16), "png"), ([{"appearance": "contrast", "value": "high"}], "2x", (16, 16), "png")])
    image_set("Lit", [(None, "2x", (16, 16), "png"), (LIGHT, "2x", (16, 16), "png"), (DARK, "2x", (16, 16), "png")])
    reports.append(case(root, "image-contrast", [contrast], nomac))
    reports.append(case(root, "image-contrast-watch", [contrast], nomac, args=watch_args("9.0")))
    return reports


COMPLICATION_ROLES = (("circular", "Circular", True, [(32, 32), (36, 36), (36, 36), (40, 40)]),
                      ("extra-large", "Extra Large", True, [(182, 182), (203, 203), (203, 203), (224, 224)]),
                      ("graphic-bezel", "Graphic Bezel", False, [None, (84, 84), None, (94, 94)]),
                      ("graphic-circular", "Graphic Circular", False, [None, (84, 84), None, (94, 94)]),
                      ("graphic-corner", "Graphic Corner", False, [None, (40, 40), None, (44, 44)]),
                      ("graphic-extra-large", "Graphic Extra Large", False, [(206, 206), (240, 240), (240, 240), (264, 264)]),
                      ("graphic-large-rectangular", "Graphic Large Rectangular", False, [None, (300, 94), None, (342, 108)]),
                      ("modular", "Modular", True, [(52, 52), (58, 58), (58, 58), (64, 64)]),
                      ("utilitarian", "Utilitarian", True, [(40, 40), (44, 44), (44, 44), (50, 50)]))


def complication_set(cat, name, roles=COMPLICATION_ROLES, unlisted=(), listed=(), grow=0):
    """A complication set as Xcode's watch template makes it: an image set per role, idiom watch
    at 2x for each screen width, gray images for the classic roles and RGBA ones for the graphic
    roles; `grow` pixels added to the first image's size."""
    d = cat / f"{name}.complicationset"
    d.mkdir()
    assets = []
    for role, folder, gray, sizes in roles:
        s = d / f"{folder}.imageset"
        s.mkdir()
        images = []
        for i, (width, size) in enumerate(zip(("<=145", ">161", ">145", ">183"), sizes)):
            entry = {"idiom": "watch", "scale": "2x", "screen-width": width}
            if size is None:
                images.append(entry)
                continue
            w, h = size[0] + (grow if not images else 0), size[1]
            file = f"{folder.lower().replace(' ', '-')}-{i}.png"
            if gray:
                png_form(s / file, w, h, 8, 4, lambda x, y, i=i: (255, (x * 9 + i * 40) % 256))
            else:
                png_form(s / file, w, h, 8, 6, lambda x, y, i=i: (x * 5 % 256, y * 3 % 256, i * 60, 255 if (x + y) % 7 else 0))
            images.append({**entry, "filename": file})
        write_json(s / "Contents.json", {"images": images, **INFO})
        assets.append({"filename": f"{folder}.imageset", "idiom": "watch", "role": role})
    for folder in unlisted:
        s = d / f"{folder}.imageset"
        s.mkdir()
        png_rgb(s / "u.png", 20, 20, lambda x, y: (x * 9, y * 9, 30))
        write_json(s / "Contents.json", {"images": [{"filename": "u.png", "idiom": "watch", "scale": "2x"}], **INFO})
    write_json(d / "Contents.json", {"assets": assets + list(listed), **INFO})


def exp_complications(root, nomac):
    """Complication sets (pocket-casts' watch app, B-204): Xcode's template with every role, with
    `--complication` naming it, naming nothing in the catalog, or left out; with an image of
    another size, an image set its list leaves out, an entry for a missing folder, an unknown
    role; image sets outside one with each screen width Xcode offers and others."""
    reports = []
    cat = catalog(root / "catalogs" / "complication" / "A.xcassets", {"AccentColor": red(), "WatchTint": [entry(rgb("0.100", "0.700", "0.300"), idiom="watch")]})
    complication_set(cat, "Complication")
    d = cat / "Plain.imageset"
    d.mkdir()
    png_rgb(d / "p.png", 20, 16, lambda x, y: (200, x * 9, y * 9))
    write_json(d / "Contents.json", {"images": [{"filename": "p.png", "idiom": "watch", "scale": "2x"}], **INFO})
    for name, extra in (("complication", ["--complication", "Complication"]), ("complication-missing", ["--complication", "Other"]),
                        ("complication-none", [])):
        reports.append(case(root, name, [cat], nomac, ["--accent-color", "AccentColor", *extra], args=watch_args("10.0")))
    for name, extra in (("symbols-complication", ["--complication", "Complication"]), ("symbols-complication-none", [])):
        reports.append(symbols_case(root, name, [cat], nomac, "10.0", "NO", devices=("watch",), extra=extra, platform="watchos"))
    two = COMPLICATION_ROLES[:2]
    for name, kwargs in (("size", {"roles": two[1:], "grow": 2}), ("unlisted", {"roles": two, "unlisted": ("Unlisted",)}),
                         ("gone", {"roles": two, "listed": ({"filename": "Gone.imageset", "idiom": "watch", "role": "modular"},)}),
                         ("role", {"roles": two, "unlisted": ("Odd",), "listed": ({"filename": "Odd.imageset", "idiom": "watch", "role": "bogus"},)})):
        odd = catalog(root / "catalogs" / f"complication-{name}" / "A.xcassets", {})
        complication_set(odd, "Complication", **kwargs)
        reports.append(case(root, f"complication-{name}", [odd], nomac, ["--complication", "Complication"], args=watch_args("10.0")))
    two_sets = catalog(root / "catalogs" / "complication-two" / "A.xcassets", {})
    complication_set(two_sets, "Complication", roles=two[:1])
    complication_set(two_sets, "Second", roles=two[1:])
    reports.append(case(root, "complication-two", [two_sets], nomac, ["--complication", "Second"], args=watch_args("10.0")))
    widths = catalog(root / "catalogs" / "screen-widths" / "A.xcassets", {})
    for i, width in enumerate(("<=145", ">145", ">161", ">183")):
        d = widths / f"W{i}.imageset"
        d.mkdir()
        png_rgb(d / "w.png", 20 + i, 20, lambda x, y, i=i: (i * 19, x * 7 % 256, y * 9))
        write_json(d / "Contents.json", {"images": [{"filename": "w.png", "idiom": "watch", "scale": "2x", "screen-width": width}], **INFO})
    reports.append(case(root, "screen-widths", [widths], nomac, args=watch_args("10.0")))
    unknown = catalog(root / "catalogs" / "screen-width-unknown" / "A.xcassets", {})
    d = unknown / "W.imageset"
    d.mkdir()
    png_rgb(d / "w.png", 20, 20, lambda x, y: (9, x * 7 % 256, y * 9))
    write_json(d / "Contents.json", {"images": [{"filename": "w.png", "idiom": "watch", "scale": "2x", "screen-width": ">176"}], **INFO})
    reports.append(case(root, "screen-width-unknown", [unknown], nomac, args=watch_args("10.0")))
    return reports


def exp_heic(root, nomac):
    """HEIC image sets (icecubes, pocket-casts), files written by macOS's sips: opaque ones across
    the 64-pixel ftyp rule and the plain payload's 4,096-byte bands, a cropped (clap) one, a 2x
    entry; ones with alpha whose `jpeg-lzfse` payload takes clearly less or more than a byte per
    pixel (plain LZFSE, run-length and raw then); beside packed PNGs. The decoded pixels may differ
    (ADR 0204); the HEIF renditions, and the alpha planes and JPEG headers, must not."""
    cat = catalog(root / "catalogs" / "heic" / "A.xcassets", {})
    sources = root / "sources"
    sources.mkdir(parents=True, exist_ok=True)
    for name, width, height, scale in (("Small", 40, 30, "1x"), ("Square", 64, 64, "1x"), ("Odd", 61, 61, "1x"), ("Big", 600, 400, "1x"),
                                       ("Tall", 40, 31, "1x"), ("Two", 40, 30, "2x")):
        png = sources / f"{name}.png"
        png_rgb(png, width, height, lambda x, y: (x * 7 % 256, y * 5 % 256, 120))
        d = cat / f"{name}.imageset"
        d.mkdir()
        subprocess.run(["sips", "-s", "format", "heic", str(png), "--out", str(d / f"{name.lower()}.heic")], check=True, capture_output=True)
        write_json(d / "Contents.json", {"images": [{"filename": f"{name.lower()}.heic", "idiom": "universal", "scale": scale}], **INFO})
    for name, width, height, scale, color in (("AlphaBig", 300, 200, "1x", lambda x, y: (x * 7 % 256, y * 5 % 256, 120, 255 if x < 150 else 90)),
                                              ("AlphaFlat", 120, 100, "2x", lambda x, y: (10, 130, 240, 255 if y < 50 else 60)),
                                              ("AlphaSmall", 40, 30, "1x", lambda x, y: (x * 7 % 256, y * 5 % 256, 120, 255 if x < 20 else 90)),
                                              ("AlphaRuns", 42, 16, "1x", lambda x, y: (x * 7 % 256, y * 5 % 256, 120, 255 if x < 21 else 90)),
                                              ("AlphaTiny", 16, 16, "1x", lambda x, y: (x * 9, y * 9, 120, 200))):
        png = sources / f"{name}.png"
        png_form(png, width, height, 8, 6, color)
        d = cat / f"{name}.imageset"
        d.mkdir()
        subprocess.run(["sips", "-s", "format", "heic", str(png), "--out", str(d / f"{name.lower()}.heic")], check=True, capture_output=True)
        write_json(d / "Contents.json", {"images": [{"filename": f"{name.lower()}.heic", "idiom": "universal", "scale": scale}], **INFO})
    for name in ("Png1", "Png2"):
        d = cat / f"{name}.imageset"
        d.mkdir()
        png_rgb(d / "p.png", 40, 30, lambda x, y: (10, x, y))
        write_json(d / "Contents.json", {"images": [{"filename": "p.png", "idiom": "universal", "scale": "1x"}], **INFO})
    report = case(root, "heic", [cat], nomac)
    if nomac:
        heic = frozenset((p.parent.stem, p.name) for p in cat.glob("*.imageset/*.heic"))
        report["compare"] = compare(root / "heic" / "actool", root / "heic" / "nomac", heic)
        def heifs(car):
            blocks, _ = bom(car.read_bytes())
            return {b[40:72].rstrip(b"\0"): b for b in blocks if b[:4] == b"ISTC" and b[24:28] == b"FIEH"}
        a, n = heifs(root / "heic" / "actool" / "Assets.car"), heifs(root / "heic" / "nomac" / "Assets.car")
        report["heif-identical"] = f"{sum(a[k] == n.get(k) for k in a)} of {len(a)}"
        def argb(car):
            blocks, _ = bom(car.read_bytes())
            out = {}
            for b in blocks:
                if b[:4] == b"ISTC" and b[24:28] == b"BGRA" and b[40:72].rstrip(b"\0").endswith(b".heic"):
                    payload = b[184 + struct.unpack_from("<I", b, 168)[0]:]
                    out[b[40:72].rstrip(b"\0")] = payload
            return out
        a, n = argb(root / "heic" / "actool" / "Assets.car"), argb(root / "heic" / "nomac" / "Assets.car")
        report["argb-compression"] = {k.decode(): [struct.unpack_from("<I", a[k], 8)[0], struct.unpack_from("<I", n[k], 8)[0] if k in n else None] for k in a}
        def jpeg_lzfse(payload):
            alpha = struct.unpack_from("<I", payload, 24)[0]
            jpeg = payload[36 + alpha:]
            return payload[16:28], payload[36:36 + alpha], jpeg[:jpeg.index(b"\xff\xda") + 14]
        both = [k for k in a if k in n and a[k][8] == n[k][8] == 5]
        report["jpeg-lzfse-alpha-and-header-identical"] = f"{sum(jpeg_lzfse(a[k]) == jpeg_lzfse(n[k]) for k in both)} of {len(both)}"
    return [report]


def exp_watchos(root, nomac):
    """watchOS catalogs (home-assistant's and pocket-casts' watch targets): colors, PNG image sets
    at 1x, 2x and 3x (3x is left out), SVG and JPEG image sets, a data set, a symbol set (its
    metrics 0.94634 times iOS's, one raster at 17 points, 2x), a single-size watchOS app icon
    (idiom watch, no PNG), for watchOS 9.0 and 6.0."""
    cat = catalog(root / "catalogs" / "watch" / "A.xcassets", {"AccentColor": red(), "Tint": [entry(rgb("0.200", "0.400", "0.800"))]})
    for name, scales in (("One", ["1x"]), ("Two", ["2x"]), ("Three", ["1x", "2x", "3x"])):
        d = cat / f"{name}.imageset"
        d.mkdir()
        images = []
        for scale in scales:
            k = int(scale[0])
            png_rgb(d / f"{name}{scale}.png", 10 * k, 8 * k, lambda x, y: (200, x * 5 % 256, y * 7 % 256))
            images.append({"filename": f"{name}{scale}.png", "idiom": "universal", "scale": scale})
        write_json(d / "Contents.json", {"images": images, **INFO})
    d = cat / "Vector.imageset"
    d.mkdir()
    (d / "v.svg").write_text('<svg width="10.5" height="7.25" viewBox="0 0 21 14.5" xmlns="http://www.w3.org/2000/svg"><rect x="1" y="1" width="19" height="12.5" fill="#e04020"/></svg>\n')
    write_json(d / "Contents.json", {"images": [{"filename": "v.svg", "idiom": "universal"}], **INFO})
    d = cat / "Photo.imageset"
    d.mkdir()
    (d / "p.jpg").write_bytes(b"\xff\xd8" + jpeg_file(40, 30))
    write_json(d / "Contents.json", {"images": [{"filename": "p.jpg", "idiom": "universal", "scale": "2x"}], **INFO})
    data_set(cat, "Blob", "blob.bin", b"watch data")
    d = cat / "Glyph.symbolset"
    d.mkdir()
    (d / "glyph.svg").write_text(symbol_template())
    write_json(d / "Contents.json", {**INFO, "symbols": [{"filename": "glyph.svg", "idiom": "universal"}]})
    d = cat / "AppIcon.appiconset"
    d.mkdir()
    png_rgb(d / "icon.png", 1024, 1024, lambda x, y: (10, (x // 4) % 256, (y // 4) % 256))
    write_json(d / "Contents.json", {"images": [{"filename": "icon.png", "idiom": "universal", "platform": "watchos", "size": "1024x1024"}], **INFO})
    extra = ["--app-icon", "AppIcon", "--accent-color", "AccentColor"]
    reports = [case(root, f"watch-{target}", [cat], nomac, extra, args=watch_args(target), resized=True) for target in ("9.0", "6.0")]
    # A multi-size watch icon set, every role and case size of Xcode's watch template.
    multi = catalog(root / "catalogs" / "watch-multi" / "A.xcassets", {})
    d = multi / "AppIcon.appiconset"
    d.mkdir()
    entries = [("notificationCenter", "24x24", "38mm", "2x"), ("notificationCenter", "27.5x27.5", "42mm", "2x"), ("notificationCenter", "33x33", "45mm", "2x"),
               ("companionSettings", "29x29", None, "2x"), ("companionSettings", "29x29", None, "3x"),
               ("appLauncher", "40x40", "38mm", "2x"), ("appLauncher", "44x44", "40mm", "2x"), ("appLauncher", "46x46", "41mm", "2x"),
               ("appLauncher", "50x50", "44mm", "2x"), ("appLauncher", "51x51", "45mm", "2x"), ("appLauncher", "54x54", "49mm", "2x"),
               ("quickLook", "86x86", "38mm", "2x"), ("quickLook", "98x98", "42mm", "2x"), ("quickLook", "108x108", "44mm", "2x"),
               ("quickLook", "117x117", "45mm", "2x"), ("quickLook", "129x129", "49mm", "2x")]
    images = []
    for i, (role, size, subtype, scale) in enumerate(entries):
        pixels = int(float(size.split("x")[0]) * int(scale[0]))
        png_rgb(d / f"i{i}.png", pixels, pixels, lambda x, y, i=i: (i * 15 % 256, x % 256, y % 256))
        images.append({"filename": f"i{i}.png", "idiom": "watch", "size": size, "scale": scale, "role": role, **({"subtype": subtype} if subtype else {})})
    png_rgb(d / "m.png", 1024, 1024, lambda x, y: (1, x % 256, y % 256))
    images.append({"filename": "m.png", "idiom": "watch-marketing", "size": "1024x1024", "scale": "1x"})
    write_json(d / "Contents.json", {"images": images, **INFO})
    reports.append(case(root, "watch-multi", [multi], nomac, ["--app-icon", "AppIcon"], args=watch_args("9.0")))
    return reports


def exp_alternate_app_icons(root, nomac):
    """App icon sets as alternate icons (--include-all-app-icons, --alternate-app-icon): single-
    and multi-size alternates beside single- and multi-size primary sets, for iPhone, iPad or both."""
    def single(d, shade):
        d.mkdir(parents=True)
        png_rgb(d / "icon.png", 1024, 1024, lambda x, y: (shade, (x // 4) % 256, (y // 4) % 256))
        write_json(d / "Contents.json", {**INFO, "images": [{"filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}]})
    def multi(d, shade, ipad=True):
        d.mkdir(parents=True)
        images = []
        for idiom, size, scale in [("iphone", 60, 2), ("iphone", 60, 3)] + ([("ipad", 76, 2), ("ipad", 83.5, 2)] if ipad else []) + [("ios-marketing", 1024, 1)]:
            name = f"{idiom}{size}{scale}.png"
            png_rgb(d / name, int(size * scale), int(size * scale), lambda x, y: (shade, x % 256, y % 256))
            images.append({"filename": name, "idiom": idiom, "size": f"{size:g}x{size:g}", "scale": f"{scale}x"})
        write_json(d / "Contents.json", {**INFO, "images": images})
    layouts = {
        "single-singles": lambda c: (single(c / "AppIcon.appiconset", 10), single(c / "AltB.appiconset", 120), single(c / "AltA.appiconset", 230)),
        "single-multi": lambda c: (single(c / "AppIcon.appiconset", 10), multi(c / "AltMulti.appiconset", 200)),
        "single-multi-iphone": lambda c: (single(c / "AppIcon.appiconset", 10), multi(c / "AltPhone.appiconset", 200, ipad=False)),
        "multi-single": lambda c: (multi(c / "AppIcon.appiconset", 10), single(c / "AltA.appiconset", 230)),
    }
    def devices_args(devices):
        return [a for i, a in enumerate(ACTOOL_ARGS) if not (a == "--target-device" and ACTOOL_ARGS[i + 1] not in devices or a not in devices and ACTOOL_ARGS[i - 1] == "--target-device")]
    reports = []
    for name, build in layouts.items():
        cat = catalog(root / "catalogs" / name / "A.xcassets", {})
        build(cat)
        for devices in (("iphone", "ipad"), ("iphone",), ("ipad",)):
            reports.append(case(root, f"{name}-all-{'-'.join(devices)}", [cat], nomac, ["--app-icon", "AppIcon", "--include-all-app-icons"],
                                args=devices_args(devices), resized=True))
    cat = root / "catalogs" / "single-singles" / "A.xcassets"
    reports.append(case(root, "single-singles-named", [cat], nomac, ["--app-icon", "AppIcon", "--alternate-app-icon", "AltA"], resized=True))
    # An iOS set with Mac sizes (flutter, netnewswire, home-assistant): actool leaves them out.
    cat = catalog(root / "catalogs" / "with-mac" / "A.xcassets", {})
    multi(cat / "AppIcon.appiconset", 40)
    contents = json.loads((cat / "AppIcon.appiconset" / "Contents.json").read_text())
    for size in ("16x16", "32x32", "512x512"):
        for scale in (1, 2):
            pixels = int(size.split("x")[0]) * scale
            png_rgb(cat / "AppIcon.appiconset" / f"mac{size}{scale}.png", pixels, pixels, lambda x, y: (90, x % 256, y % 256))
            contents["images"].append({"filename": f"mac{size}{scale}.png", "idiom": "mac", "size": size, "scale": f"{scale}x"})
    write_json(cat / "AppIcon.appiconset" / "Contents.json", contents)
    reports.append(case(root, "with-mac", [cat], nomac, ["--app-icon", "AppIcon"]))
    # Icon Composer icons and app icon sets as alternates together (icecubes' catalog): an icon
    # alternate beside set alternates, with a set or an icon as the primary icon.
    dot = {"dot.svg": '<svg width="100" height="100" viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg"><circle cx="50" cy="50" r="30" fill="#ffffff"/></svg>\n'}
    icons = root / "catalogs" / "mixed-icons"
    alt = icon(icons, "AltIcon", {"fill": {"solid": "srgb:1.00000,0.00000,0.00000,1.00000"}, "groups": [{"layers": [{"image-name": "dot.svg", "name": "dot"}]}]}, dot)
    primary = icon(icons, "MainIcon", {"fill": {"solid": "srgb:0.00000,0.40000,1.00000,1.00000"}, "groups": [{"layers": [{"image-name": "dot.svg", "name": "dot"}]}]}, dot)
    cat = root / "catalogs" / "single-singles" / "A.xcassets"
    for devices in (("iphone", "ipad"), ("iphone",)):
        reports.append(case(root, f"mixed-set-primary-{'-'.join(devices)}", [cat, alt], nomac, ["--app-icon", "AppIcon", "--include-all-app-icons"],
                            args=devices_args(devices), resized=True))
        reports.append(case(root, f"mixed-icon-primary-{'-'.join(devices)}", [primary, cat, alt], nomac, ["--app-icon", "MainIcon", "--include-all-app-icons"],
                            args=devices_args(devices), resized=True))
    return reports


def exp_svg_colors(root, nomac):
    """SVG paints CoreSVG reads (names, #rgb, #rrggbb, rgb(), rgba() with its alpha,
    currentColor from the color property) and the ones it drops for the inherited value
    (#rrggbbaa, #rgba, unknown words): an unreadable fill paints black, an unreadable stroke
    nothing, a fill inherited from a group stays."""
    head = '<svg width="20" height="20" viewBox="0 0 20 20" xmlns="http://www.w3.org/2000/svg">'
    green = '<rect width="20" height="20" fill="#00ff00"/>'
    cases = {
        "hex8-clear": '<rect width="20" height="20" fill="#FF000000"/>', "hex8-over-green": green + '<rect width="20" height="20" fill="#FF0000FF"/>',
        "hex8-half": green + '<rect width="10" height="20" fill="#FF0000FF"/>', "hex4-over-green": green + '<rect width="20" height="20" fill="#F00F"/>',
        "bogus-stroke": green + '<rect x="2" y="2" width="16" height="16" fill="none" stroke="notacolor" stroke-width="20"/>',
        "inherited-red": '<g fill="red"><rect width="20" height="20" fill="#FF0000FF"/></g>',
        "rgba-clear": '<rect width="20" height="20" fill="rgba(255,0,0,0)"/>', "rgba-half": '<rect width="20" height="20" fill="rgba(255,0,0,0.5)"/>',
        "current-default": '<rect width="20" height="20" fill="currentColor"/>', "current-group": '<g color="red"><rect width="20" height="20" fill="currentColor"/></g>',
        "current-style": '<rect width="20" height="20" style="color:#00f" fill="currentColor"/>', "named": '<rect width="20" height="20" fill="cornflowerblue"/>',
    }
    cat = catalog(root / "catalogs" / "svg" / "A.xcassets", {})
    for name, body in cases.items():
        d = cat / f"{name}.imageset"
        d.mkdir(parents=True)
        (d / f"{name}.svg").write_text(head + body + "</svg>\n")
        write_json(d / "Contents.json", {"images": [{"filename": f"{name}.svg", "idiom": "universal"}], **INFO})
    return [case(root, "svg", [cat], nomac)]


def exp_svg_masks_strokes(root, nomac):
    """SVG image sets with strokes (caps, joins, miter limits, opacity, gradients, closed and
    open subpaths, lines) and masks (by luminance even with mask-type alpha, maskUnits and
    maskContentUnits, on shapes and groups): the rasters' pixels are nomac's (ADR 0204), every header byte actool's."""
    head = '<svg width="20" height="20" viewBox="0 0 40 40" xmlns="http://www.w3.org/2000/svg">'
    gradient = '<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#e04020"/><stop offset="1" stop-color="#2040e0"/></linearGradient></defs>'
    cases = {
        "line-round": '<line x1="6" y1="20" x2="34" y2="20" stroke="#202020" stroke-width="6" stroke-linecap="round"/>',
        "line-square": '<line x1="6" y1="10" x2="34" y2="30" stroke="#e04020" stroke-width="4" stroke-linecap="square"/>',
        "miter": '<polyline points="6,34 20,6 34,34" fill="none" stroke="#2040e0" stroke-width="5"/>',
        "miter-limit": '<polyline points="6,34 20,4 34,34" fill="none" stroke="#2040e0" stroke-width="5" stroke-miterlimit="1.5"/>',
        "bevel": '<path d="M6 34 L20 6 L34 34" fill="none" stroke="#20a040" stroke-width="5" stroke-linejoin="bevel"/>',
        "round-join": '<path d="M6 34 L20 6 L34 34" fill="none" stroke="#20a040" stroke-width="5" stroke-linejoin="round" stroke-linecap="round"/>',
        "closed-fill-stroke": '<rect x="8" y="8" width="24" height="24" rx="4" fill="#f0c020" stroke="#202020" stroke-width="3"/>',
        "stroke-opacity": '<circle cx="20" cy="20" r="12" fill="none" stroke="#e04020" stroke-width="6" stroke-opacity="0.5"/>',
        "stroke-gradient": gradient + '<circle cx="20" cy="20" r="12" fill="none" stroke="url(#g)" stroke-width="6"/>',
        "black-stroke": '<path d="M8 8 C 20 0 30 40 32 32" fill="none" stroke="black" stroke-width="3"/>',
        "mask-luminance": '<defs><mask id="m"><rect x="0" y="0" width="40" height="40" fill="white"/><circle cx="20" cy="20" r="8" fill="black"/></mask></defs>'
                          '<rect x="4" y="4" width="32" height="32" fill="#2040e0" mask="url(#m)"/>',
        "mask-alpha": '<defs><mask id="m" mask-type="alpha" maskUnits="userSpaceOnUse" x="0" y="0" width="40" height="40">'
                      '<circle cx="20" cy="20" r="14" fill="#000" fill-opacity="0.6"/></mask></defs><rect x="4" y="4" width="32" height="32" fill="#e04020" mask="url(#m)"/>',
        "mask-alpha-white": '<defs><mask id="m" mask-type="alpha"><circle cx="20" cy="20" r="14" fill="white" fill-opacity="0.6"/></mask></defs>'
                            '<rect x="4" y="4" width="32" height="32" fill="#e04020" mask="url(#m)"/>',
        "mask-content-bbox": '<defs><mask id="m" maskContentUnits="objectBoundingBox"><rect x="0" y="0" width="0.5" height="1" fill="white"/></mask></defs>'
                             '<circle cx="20" cy="20" r="14" fill="#20a040" mask="url(#m)"/>',
        "mask-group": '<defs><mask id="m"><rect x="-5" y="-5" width="50" height="50" fill="#808080"/></mask></defs>'
                      '<g mask="url(#m)"><rect x="4" y="4" width="16" height="32" fill="#e04020"/><rect x="20" y="4" width="16" height="32" fill="#2040e0"/></g>',
    }
    cat = catalog(root / "catalogs" / "svg" / "A.xcassets", {})
    for name, body in cases.items():
        d = cat / f"{name}.imageset"
        d.mkdir(parents=True)
        (d / f"{name}.svg").write_text(head + body + "</svg>\n")
        write_json(d / "Contents.json", {"images": [{"filename": f"{name}.svg", "idiom": "universal"}], **INFO})
    return [case(root, "svg", [cat], nomac)]


def exp_single_size_icons(root, nomac):
    """Single-size iOS app icons: each PNG form and chunk set (the resized icon PNGs are RGBA
    with gAMA, sRGB, cHRM and an eXIf, whatever the input), dark and tinted appearances,
    iPhone, iPad or both as target devices, --standalone-icon-behavior all and none, iOS 15.0."""
    phys = (b"pHYs", struct.pack(">IIB", 5669, 5669, 1))
    text = [(b"tEXt", b"Software\0x"), (b"iTXt", b"XML:com.adobe.xmp\0\0\0\0\0<x/>")]
    srgb = [(b"sRGB", b"\0"), (b"gAMA", struct.pack(">I", 45455))]
    palette = [(i, 255 - i, (i * 3) % 256) for i in range(256)]
    def rgb(x, y): return (x % 256, y % 256, 90)
    forms = {
        "rgb": (2, rgb, {}), "rgba": (6, lambda x, y: (x % 256, y % 256, 90, 128 + x % 128), {}),
        "gray": (0, lambda x, y: ((x + y) % 256,), {}), "gray-alpha": (4, lambda x, y: ((x + y) % 256, 200), {}),
        "palette": (3, lambda x, y: ((x // 4) % 256,), {"palette": palette}),
        "palette-trns": (3, lambda x, y: ((x // 4) % 256,), {"palette": palette, "transparency": [255] * 128 + [100] * 128}),
        "rgb-phys": (2, rgb, {"chunks": [phys]}), "rgb-text": (2, rgb, {"chunks": text}), "rgb-srgb": (2, rgb, {"chunks": srgb}),
        "appearances": (2, rgb, {}),
    }
    reports = []
    for name, (color_type, sample, extra) in forms.items():
        cat = catalog(root / "catalogs" / name / "A.xcassets", {})
        d = cat / "AppIcon.appiconset"
        d.mkdir(parents=True)
        appearances = [None, "dark", "tinted"] if name == "appearances" else [None]
        images = []
        for i, appearance in enumerate(appearances):
            png_form(d / f"icon{i}.png", 1024, 1024, 8, color_type, lambda x, y, i=i: tuple((v + 70 * i) % 256 for v in sample(x, y)), **extra)
            entry = {"filename": f"icon{i}.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}
            if appearance:
                entry["appearances"] = [{"appearance": "luminosity", "value": appearance}]
            images.append(entry)
        write_json(d / "Contents.json", {**INFO, "images": images})
        for devices in (("iphone", "ipad"), ("iphone",), ("ipad",)):
            args = [a for i, a in enumerate(ACTOOL_ARGS) if not (a == "--target-device" and ACTOOL_ARGS[i + 1] not in devices or a not in devices and ACTOOL_ARGS[i - 1] == "--target-device")]
            reports.append(case(root, f"{name}-{'-'.join(devices)}", [cat], nomac, ["--app-icon", "AppIcon"], args=args, resized=True))
    cat = root / "catalogs" / "rgb" / "A.xcassets"
    for behavior in ("all", "none"):
        reports.append(case(root, f"standalone-{behavior}", [cat], nomac, ["--app-icon", "AppIcon", "--standalone-icon-behavior", behavior], resized=True))
    earlier = [("15.0" if a == "18.0" else a) for a in ACTOOL_ARGS]
    reports.append(case(root, "deployment-15", [cat], nomac, ["--app-icon", "AppIcon", "--standalone-icon-behavior", "all"], args=earlier, resized=True))
    return reports


def exp_copypng(root, nomac):
    """Xcode's copypng (loose PNGs in a bundle): RGB, RGBA, gray and gray-alpha PNGs of sizes
    around the zlib window thresholds and the halving limit, with and without text chunks,
    for each option set; nomac's output must be the same bytes."""
    random.seed(7)
    text = [(b"tEXt", b"Software\0experiment"), (b"iTXt", b"Comment\0\0\0\0\0hello")]
    inputs = root / "inputs"
    files = []
    for width, height in ((8, 8), (16, 15), (20, 13), (30, 20), (50, 40), (60, 60), (81, 60), (200, 100)):
        for color_type, channels in ((2, 3), (6, 4), (0, 1), (4, 2)):
            for chunks in ((), text):
                path = inputs / f"c{color_type}-{width}x{height}{'-text' if chunks else ''}.png"
                pixels = {(x, y): tuple(random.randrange(256) if (x + c) % 3 == 0 else (x * 7 + y * 3 + c * 50) % 256 for c in range(channels))
                          for x in range(width) for y in range(height)}
                png_form(path, width, height, 8, color_type, lambda x, y, p=pixels: p[(x, y)], chunks=chunks)
                files.append(path)
    report = {}
    for options in ((), ("-compress",), ("-strip-PNG-text",), ("-compress", "-strip-PNG-text")):
        key = " ".join(options) or "none"
        outcome = collections.Counter()
        for path in files:
            # Folder names without dashes: copypng takes any argument containing an option's name for it.
            out = root / ("_".join(o.split("-")[1] for o in options) or "none") / path.name
            out.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(["xcrun", "copypng", *options, str(path), str(out)], check=True, capture_output=True)
            if nomac:
                mine = out.with_suffix(".nomac.png")
                status = subprocess.run([nomac, "copypng", *options, str(path), str(mine)], capture_output=True).returncode
                outcome["refused" if status else "identical" if mine.read_bytes() == out.read_bytes() else "different"] += 1
        report[key] = dict(outcome)
    return [report]


def jpeg_file(width, height):
    """A baseline JPEG of one gray 8-bit component, every 8 × 8 block a flat mid gray, without
    the start-of-image marker: quantization and Huffman tables, the frame, the scan."""
    def segment(marker, body):
        return bytes([0xFF, marker]) + struct.pack(">H", len(body) + 2) + body
    dqt = segment(0xDB, b"\x00" + bytes([1] * 64))
    sof = segment(0xC0, struct.pack(">BHHB", 8, height, width, 1) + b"\x01\x11\x00")
    dc = segment(0xC4, b"\x00" + bytes([1] + [0] * 15) + b"\x00")
    ac = segment(0xC4, b"\x10" + bytes([1] + [0] * 15) + b"\x00")
    sos = segment(0xDA, b"\x01\x01\x00\x00\x3f\x00")
    blocks = ((width + 7) // 8) * ((height + 7) // 8)
    bits = "00" * blocks
    bits += "1" * (-len(bits) % 8)
    data = bytes(int(bits[i:i + 8], 2) for i in range(0, len(bits), 8))
    return dqt + sof + dc + ac + sos + data + b"\xff\xd9"


EXPERIMENTS = {
    "app-build": exp_app_build,
    "colors": exp_colors,
    "data": exp_data,
    "identifiers": exp_identifiers,
    "collisions": exp_collisions,
    "bitmap-order": exp_bitmap_order,
    "appearance-order": exp_appearance_order,
    "packing": exp_packing,
    "images": exp_images,
    "app-icons": exp_app_icons,
    "sprites": exp_sprites,
    "stickers": exp_stickers,
    "symbols": exp_symbols,
    "icons": exp_icons,
    "profiles": exp_profiles,
    "vector-images": exp_vector_images,
    "symbol-sets": exp_symbol_sets,
    "copypng": exp_copypng,
    "single-size-icons": exp_single_size_icons,
    "svg-masks-strokes": exp_svg_masks_strokes,
    "svg-colors": exp_svg_colors,
    "alternate-app-icons": exp_alternate_app_icons,
    "watchos": exp_watchos,
    "heic": exp_heic,
    "complications": exp_complications,
    "image-appearances": exp_image_appearances,
    "symbol-extensions": exp_symbol_extensions,
}


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    out = Path(args.pop(0)).resolve()
    nomac = None
    if args[:1] == ["--nomac"]:
        nomac = str(Path(args[1]).resolve())
        args = args[2:]
    names = args or list(EXPERIMENTS)
    unknown = [n for n in names if n not in EXPERIMENTS]
    if unknown:
        sys.exit(f"unknown experiments: {unknown}")
    if not args and out.exists():
        shutil.rmtree(out)
    summary = {}
    for name in names:
        root = out / name
        if root.exists():
            shutil.rmtree(root)
        root.mkdir(parents=True)
        summary[name] = EXPERIMENTS[name](root, nomac)
        print(name, json.dumps(summary[name])[:2000])
    previous = json.loads((out / "summary.json").read_text()) if (out / "summary.json").exists() else {}
    previous.update(summary)
    write_json(out / "summary.json", previous)


if __name__ == "__main__":
    main()
