#!/usr/bin/env python3
"""Self-written cases behind rule.md, in the shape of `.github/scripts/assets_experiments.py`
experiments: paste the functions there and add them to EXPERIMENTS (or run this file with
`PYTHONPATH=.github/scripts DEVELOPER_DIR=... python3 cases.py <out> [experiment ...]`)."""

import json
import shutil
import sys
from pathlib import Path

from assets_experiments import (INFO, SYMBOL_FILES, ACTOOL_ARGS, case, catalog, data_set, icon, image_set, png, png_rgb, red, run_symbols,
                                sticker_catalog, write_json)


def exp_same_name_icons(root, nomac):
    """Family 1, for exp_alternate_app_icons: an Icon Composer icon and an app icon set of one
    name, as primary and as alternate, the set's catalog before and after the icons, and a set
    with an image of the wrong size under an icon."""
    def single(d, shade):
        d.mkdir(parents=True)
        png_rgb(d / "icon.png", 1024, 1024, lambda x, y: (shade, (x // 4) % 256, (y // 4) % 256))
        write_json(d / "Contents.json", {**INFO, "images": [{"filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}]})
    dot = {"dot.svg": '<svg width="100" height="100" viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg"><circle cx="50" cy="50" r="30" fill="#ffffff"/></svg>\n'}
    doc = lambda c: {"fill": {"solid": f"srgb:{c},0.00000,0.00000,1.00000"}, "groups": [{"layers": [{"image-name": "dot.svg", "name": "dot"}]}]}
    main, alt = icon(root / "catalogs" / "icons", "Main", doc("1.00000"), dot), icon(root / "catalogs" / "icons", "Alt", doc("0.50000"), dot)
    cat = catalog(root / "catalogs" / "sets" / "A.xcassets", {})
    for name, shade in [("Main", 10), ("Alt", 120), ("Other", 200)]:
        single(cat / f"{name}.appiconset", shade)
    odd = catalog(root / "catalogs" / "odd" / "A.xcassets", {})
    single(odd / "Main.appiconset", 10)
    single(odd / "Alt.appiconset", 120)
    png_rgb(odd / "Alt.appiconset" / "odd.png", 100, 100, lambda x, y: (9, 9, 9))
    contents = json.loads((odd / "Alt.appiconset" / "Contents.json").read_text())
    contents["images"].append({"filename": "odd.png", "idiom": "iphone", "size": "60x60", "scale": "2x"})
    write_json(odd / "Alt.appiconset" / "Contents.json", contents)
    primary = ["--app-icon", "Main"]
    return [
        case(root, "primary-both", [main, cat], nomac, primary), case(root, "primary-icon", [main], nomac, primary), case(root, "primary-set", [cat], nomac, primary),
        case(root, "all-both", [main, alt, cat], nomac, [*primary, "--include-all-app-icons"]),
        case(root, "set-first", [cat, main, alt], nomac, [*primary, "--include-all-app-icons"]),
        case(root, "named-alternate", [main, alt, cat], nomac, [*primary, "--alternate-app-icon", "Alt"]),
        case(root, "set-primary-icon-alternate", [alt, cat], nomac, [*primary, "--include-all-app-icons"]),
        case(root, "set-under-icon-warns", [odd, main, alt], nomac, [*primary, "--include-all-app-icons"]),
    ]


def exp_sticker_options(root, nomac):
    """Family 2: one option at a time on one sticker catalog, stickers beside other assets, with
    several packs and several icon sets, without a pack or an icon set, a list entry with no
    folder, a folder not listed, an app icon set named, and a name nothing has."""
    args = [a for a in ACTOOL_ARGS if a != "--notices"]
    icon_set = "iMessage App Icon"
    name, include, role = ["--app-icon", icon_set], ["--include-sticker-content"], ["--stickers-icon-role", "extension"]
    prefix = ["--sticker-pack-identifier-prefix", "org.example.Stickers.sticker-pack."]
    full = [*name, *include, *role, *prefix]
    def base(tag, suffix="xcassets"):
        return sticker_catalog(root / "catalogs" / tag / f"S.{suffix}")
    plain = base("plain")
    reports = [case(root, f"options-{tag}", [plain], nomac, extra, args=args) for tag, extra in {
        "none": [], "include": include, "include-prefix": [*include, *prefix], "role": role, "include-role-prefix": [*include, *role, *prefix],
        "name": name, "name-include-prefix": [*name, *include, *prefix], "name-role": [*name, *role], "full": full,
        "host-app": [*name, *include, *prefix, "--stickers-icon-role", "host-app"], "host-app-alone": [*name, "--stickers-icon-role", "host-app"],
        "nosuch": ["--app-icon", "Nope"], "nosuch-role": ["--app-icon", "Nope", *role], "nosuch-include": ["--app-icon", "Nope", *include, *prefix],
        "nosuch-include-role": ["--app-icon", "Nope", *include, *role, *prefix],
    }.items()]
    xc = base("xcstickers", "xcstickers")
    reports.append(case(root, "xcstickers-no-name", [xc], nomac, [*include, *role, *prefix], args=args))
    beside = base("beside")
    write_json(beside / "Red.colorset" / "Contents.json", {"colors": red(), **INFO})
    image_set(beside, "pic", lambda p: png(p, 20, 20, lambda x, y: (200, 30, 30, 255)))
    data_set(beside, "D", "blob.txt", b"hello")
    reports += [case(root, "beside-full", [beside], nomac, full, args=args), case(root, "beside-none", [beside], nomac, [], args=args)]
    packs = base("three-packs")
    shutil.move(str(packs / "Sticker Pack.stickerpack"), str(packs / "Zed.stickerpack"))
    for other in ("Mid", "Abe"):
        shutil.copytree(packs / "Zed.stickerpack", packs / f"{other}.stickerpack")
    reports.append(case(root, "three-packs", [packs], nomac, full, args=args))
    no_icon = base("no-icon-set")
    shutil.rmtree(no_icon / f"{icon_set}.stickersiconset")
    reports += [case(root, "pack-without-icon-set", [no_icon], nomac, full, args=args), case(root, "pack-no-name", [no_icon], nomac, [*include, *role, *prefix], args=args)]
    no_pack = base("no-pack")
    shutil.rmtree(no_pack / "Sticker Pack.stickerpack")
    reports.append(case(root, "icon-set-without-pack", [no_pack], nomac, full, args=args))
    icons = base("two-icon-sets")
    shutil.copytree(icons / f"{icon_set}.stickersiconset", icons / "Second.stickersiconset")
    reports.append(case(root, "two-icon-sets", [icons], nomac, full, args=args))
    app_icon = base("app-icon")
    d = app_icon / "Main.appiconset"
    d.mkdir()
    png_rgb(d / "icon.png", 1024, 1024, lambda x, y: (9, (x // 4) % 256, (y // 4) % 256))
    write_json(d / "Contents.json", {**INFO, "images": [{"filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}]})
    reports += [case(root, "app-icon-named-pack", [app_icon], nomac, ["--app-icon", "Main", *include, *role, *prefix], args=args),
                case(root, "app-icon-named-alone", [app_icon], nomac, ["--app-icon", "Main"], args=args)]
    missing = base("list-missing")
    listing = json.loads((missing / "Sticker Pack.stickerpack" / "Contents.json").read_text())
    listing["stickers"].insert(1, {"filename": "gone.sticker"})
    write_json(missing / "Sticker Pack.stickerpack" / "Contents.json", listing)
    reports.append(case(root, "list-entry-without-folder", [missing], nomac, full, args=args))
    unlisted = base("unlisted")
    listing = json.loads((unlisted / "Sticker Pack.stickerpack" / "Contents.json").read_text())
    listing["stickers"] = listing["stickers"][1:]
    write_json(unlisted / "Sticker Pack.stickerpack" / "Contents.json", listing)
    reports.append(case(root, "folder-not-listed", [unlisted], nomac, full, args=args))
    reports.append(case(root, "without-compress-pngs", [plain], nomac, full, args=[a for a in args if a != "--compress-pngs"]))
    return reports


def exp_icon_stacks(root, nomac):
    """Family 3: visionOS icon stacks on iOS: which layers are checked, how many layers, which
    size fills the stack, by idiom and scale, and entries with no file or folder."""
    def layer(stack, name, images):
        folder = stack / f"{name}.solidimagestacklayer"
        write_json(folder / "Contents.json", INFO)
        entries = []
        for filename, width, height, idiom, scale in images:
            entry = {"idiom": idiom}
            if scale:
                entry["scale"] = scale
            if filename:
                if width:
                    png(folder / "Content.imageset" / filename, width, height, lambda x, y: (40, 80, 120, 255))
                entry["filename"] = filename
            entries.append(entry)
        write_json(folder / "Content.imageset" / "Contents.json", {"images": entries, **INFO})
    fill = lambda w=1024, h=1024, idiom="vision", scale="2x": [("l.png", w, h, idiom, scale)]
    empty = [(None, 0, 0, "vision", "2x")]
    cases = {
        "base": [("Front", fill()), ("Back", fill())], "no-content": [("Front", empty), ("Middle", empty), ("Back", empty)],
        "front-only": [("Front", fill()), ("Back", empty)], "back-only": [("Front", empty), ("Back", fill())],
        "front-small": [("Front", fill(484, 512)), ("Middle", empty), ("Back", fill())], "back-small": [("Front", fill()), ("Back", fill(484, 512))],
        "only-small": [("Front", fill(484, 512)), ("Back", empty)], "half-points": [("Front", fill()), ("Back", fill(485, 513))],
        "reality": [("Front", fill(idiom="reality")), ("Back", fill(idiom="reality"))], "universal": [("Front", fill(idiom="universal")), ("Back", fill(idiom="universal"))],
        "iphone": [("Front", fill(idiom="iphone")), ("Back", fill(idiom="iphone"))], "reality-small": [("Front", fill()), ("Back", fill(100, 100, idiom="reality"))],
        "universal-small": [("Front", fill()), ("Back", fill(100, 100, idiom="universal"))], "iphone-small": [("Front", fill()), ("Back", fill(100, 100, idiom="iphone"))],
        "1x-1024": [("Front", fill(scale="1x")), ("Back", fill(scale="1x"))], "1x-512": [("Front", fill(512, 512, scale="1x")), ("Back", fill(512, 512, scale="1x"))],
        "no-scale-1024": [("Front", fill(scale=None)), ("Back", fill(scale=None))], "no-scale-512": [("Front", fill(512, 512, scale=None)), ("Back", fill(512, 512, scale=None))],
        "large": [("Front", fill()), ("Back", fill(2048, 2048))], "one-good": [("Back", fill())], "one-empty": [("Back", empty)], "one-small": [("Back", fill(100, 100))], "zero": [],
        "four": [(n, fill()) for n in "ABCD"], "four-empty": [(n, empty) for n in "ABCD"],
        "two-images-small-first": [("Front", fill()), ("Back", [("a.png", 100, 100, "vision", "2x"), ("b.png", 1024, 1024, "universal", "2x")])],
        "two-images-large-first": [("Front", fill()), ("Back", [("a.png", 1024, 1024, "vision", "2x"), ("b.png", 100, 100, "universal", "2x")])],
        "two-entries-of-scales": [("Front", fill()), ("Back", [("a.png", 512, 512, "vision", "1x"), ("b.png", 1024, 1024, "vision", "2x")])],
        "missing-file": [("Front", fill()), ("Back", [("gone.png", 0, 0, "vision", "2x")])], "missing-layer-folder": [("Front", fill()), ("Back", None)],
    }
    reports = []
    for tag, layers in cases.items():
        cat = catalog(root / "catalogs" / tag / "S.xcassets", {"Red": red()})
        stack = cat / "Icon.solidimagestack"
        write_json(stack / "Contents.json", {"layers": [{"filename": f"{n}.solidimagestacklayer"} for n, _ in layers], **INFO})
        for layer_name, images in layers:
            if images is not None:
                layer(stack, layer_name, images)
        reports.append(case(root, tag, [cat], nomac))
    small = root / "catalogs" / "back-small" / "S.xcassets"
    run_symbols(["xcrun", "actool"], [small], root / "symbols-back-small", "17.0", None)
    return reports


def exp_system_color_platforms(root, nomac):
    """Family 4, for exp_colors: every name of the table for every platform, the names real
    catalogs use, UIKit's and AppKit's other public names for iOS."""
    from assets_experiments import IOS_SYSTEM_COLORS, SYSTEM_COLORS
    names = SYSTEM_COLORS + IOS_SYSTEM_COLORS + ["groupTableViewBackgroundColor"]
    other = ("tableCellGroupedBackgroundColor tableCellPlainBackgroundColor sectionIndexBackgroundColor underPageBackgroundColor viewFlipsideBackgroundColor "
             "scrollViewTexturedBackgroundColor tableBackgroundColor systemExtraLightGrayColor systemGrayTintColor systemWhiteColor systemBlackColor systemMidGrayColor "
             "systemDarkGrayColor systemLightGrayColor alternatingContentBackgroundColor controlBackgroundColor controlColor controlTextColor disabledControlTextColor "
             "gridColor headerTextColor highlightColor knobColor selectedControlColor selectedTextColor shadowColor textBackgroundColor groupTableViewCellBackgroundColor "
             "groupTableViewHeaderFooterColor bogusColor").split()
    def ref(platform, name, dark=False):
        color = {"reference": name}
        if platform:
            color["platform"] = platform
        e = {"color": color, "idiom": "universal"}
        if dark:
            e["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
        return e
    colors = {f"{p}-{n}": [ref(p, n), ref(p, n, True)] for p in ("ios", "universal", "osx", "tvos", "watchos", "xros", "visionos", None) for n in names}
    colors.update({f"other-{n}": [ref("ios", n), ref("ios", n, True)] for n in other})
    return [case(root, "platforms", [catalog(root / "catalogs" / "platforms" / "A.xcassets", colors)], None)]


def exp_image_entry_scales(root, nomac):
    """Family 5, for exp_symbols: an image entry of every idiom and scale, with and without a
    file, for each target device: what actool calls an unassigned child and what it lists."""
    def entry(cat, name, idiom, scale, file=True):
        d = cat / f"{name}.imageset"
        e = {"idiom": idiom}
        if scale:
            e["scale"] = scale
        d.mkdir(parents=True)
        if file:
            png_rgb(d / "p.png", 8, 8, lambda x, y: (1, 2, 3))
            e["filename"] = "p.png"
        write_json(d / "Contents.json", {"images": [e], **INFO})
    matrix = catalog(root / "catalogs" / "matrix" / "M.xcassets", {})
    for idiom in ("car", "watch", "vision", "ios-marketing", "tv", "mac", "iphone", "ipad", "universal"):
        for scale in (None, "1x", "2x", "3x"):
            entry(matrix, f"{idiom.replace('-', '')}{scale or 'none'}", idiom, scale)
    no_files = catalog(root / "catalogs" / "no-files" / "N.xcassets", {})
    for idiom, scale in (("car", "1x"), ("ios-marketing", "1x"), ("vision", "1x"), ("watch", "3x"), ("ipad", "3x"), ("mac", "3x"), ("tv", "3x")):
        entry(no_files, f"{idiom.replace('-', '')}{scale}", idiom, scale, file=False)
    for tag, cat in (("matrix", matrix), ("no-files", no_files)):
        for devices in (("iphone", "ipad"), ("iphone",), ("ipad",)):
            run_symbols(["xcrun", "actool"], [cat], root / f"{tag}-{'-'.join(devices)}", "17.0", None, devices=devices)
    run_symbols(["xcrun", "actool"], [matrix], root / "matrix-watch", "10.0", None, devices=("watch",), platform="watchos")
    stickers = sticker_catalog(root / "catalogs" / "stickers" / "S.xcassets")
    run_symbols(["xcrun", "actool"], [stickers], root / "stickers", "17.0", None)
    return [{"index": json.loads(json.dumps(sorted(str(p) for p in root.glob(f"*/derived/{SYMBOL_FILES[2]}"))))}]


def exp_car_entries(root, nomac):
    """Family 5, for the compile: `car` entries of image sets at each scale, of color sets and of
    data sets, for each target device."""
    cat = catalog(root / "catalogs" / "car" / "A.xcassets", {"carColor": [{"color": red()[0]["color"], "idiom": "car"}],
                                                             "uniCar": [red()[0], {"color": red()[0]["color"], "idiom": "car"}]})
    for name, scale in (("c2", "2x"), ("c3", "3x"), ("cn", None)):
        d = cat / f"{name}.imageset"
        d.mkdir()
        png_rgb(d / "p.png", 8, 8, lambda x, y: (1, 2, 3))
        write_json(d / "Contents.json", {"images": [{"idiom": "car", "filename": "p.png", **({"scale": scale} if scale else {})}], **INFO})
    data_set(cat, "dcar", "b.txt", b"x")
    write_json(cat / "dcar.dataset" / "Contents.json", {"data": [{"idiom": "car", "filename": "b.txt"}], **INFO})
    def devices(*names):
        return [a for i, a in enumerate(ACTOOL_ARGS) if not (a == "--target-device" and ACTOOL_ARGS[i + 1] not in names or a in ("iphone", "ipad") and a not in names)]
    return [case(root, "-".join(names), [cat], nomac, args=devices(*names)) for names in (("iphone", "ipad"), ("iphone",), ("ipad",))]


def exp_dynamic_identifiers(root, nomac):
    """Family 6, for exp_data: extensions of every letter, digit and length, in every case, with
    the characters a dynamic identifier escapes, non-ASCII ones, several dots, a space, none."""
    import random
    import string
    random.seed(7)
    exts = [*string.ascii_lowercase, *string.digits, "db", "dat", "data", "meta", "sqlite", "woff", "woff2", "none", "xyzzy", "abcdefghijkl", "a" * 32]
    exts += ["".join(random.choice(string.ascii_lowercase) for _ in range(n)) + "q" for n in range(1, 12) for _ in range(2)]
    exts += ["DB", "Db", "META", "XyZ", "PNG", "Json", "TXT", "Mp3", "ZIP", "HEIC", "C", "a-b", "a_b", "a+b", "a~b", "a=b", "a,b", "a b", "a'b", "a:b", "a%b", "a?b", "a\\b",
             "é", "Éa", "ÉA", "ß", "İ", "日本"]
    cat = catalog(root / "catalogs" / "extensions" / "A.xcassets", {})
    for i, e in enumerate(exts):
        data_set(cat, f"D{i}", f"f.{e}", b"x")
    for tag, filename in (("noext", "noext"), ("dots", "a.png.meta"), ("trailing", "trailing."), ("hidden", ".hidden"), ("dotsc", "a.b.C")):
        data_set(cat, "D" + tag, filename, b"x")
    return [case(root, "extensions", [cat], None)]


def exp_type_identifier_table(root, nomac, extensions_file=None):
    """Family 6, the table: every extension `lsregister -dump` declares for a type of macOS or
    Xcode, one data set each. The identifiers come from actool's output, not from the dump."""
    extensions = json.loads(Path(extensions_file).read_text())
    cat = catalog(root / "catalogs" / "table" / "A.xcassets", {})
    for i, e in enumerate(extensions):
        data_set(cat, f"D{i}", f"f.{e}", b"x")
    return [case(root, "table", [cat], None)]


EXPERIMENTS = {
    "same-name-icons": exp_same_name_icons, "sticker-options": exp_sticker_options, "icon-stacks": exp_icon_stacks,
    "system-color-platforms": exp_system_color_platforms, "image-entry-scales": exp_image_entry_scales, "car-entries": exp_car_entries, "dynamic-identifiers": exp_dynamic_identifiers,
}
