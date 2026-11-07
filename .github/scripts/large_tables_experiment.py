#!/usr/bin/env python3
"""The catalogs of the `large-tables` experiment (BACKLOG B-201): tables past one BOM leaf.

Written to become `exp_large_tables` in assets_experiments.py: it only uses that script's helpers.
"""
import random
import sys
from pathlib import Path

sys.dont_write_bytecode = True
from assets_experiments import catalog, data_set, entry, numbered_images, red, rgb  # noqa: E402

LIGHT = [{"appearance": "luminosity", "value": "light"}]
DARK = [{"appearance": "luminosity", "value": "dark"}]
IDIOMS = ["universal", "iphone", "ipad", "mac", "tv", "watch"]


def fixed_names(n, seed=1, length=8):
    rng = random.Random(seed)
    names = {}
    while len(names) < n:
        names["r" + "".join(rng.choice("abcdefghij") for _ in range(length))] = None
    return list(names)


def mixed_names(n, seed=2):
    rng = random.Random(seed)
    names = {}
    while len(names) < n:
        names["m" + "".join(rng.choice("abcdefghij") for _ in range(rng.randrange(4, 13)))] = None
    return list(names)


def three_appearances():
    return [entry(rgb("1.000", "0.000", "0.000")), entry(rgb("0.000", "1.000", "0.000"), appearances=LIGHT),
            entry(rgb("0.000", "0.000", "1.000"), appearances=DARK)]


def two_appearances():
    return [entry(rgb("1.000", "0.000", "0.000")), entry(rgb("0.000", "0.000", "1.000"), appearances=DARK)]


def six_idioms():
    return [entry(rgb("1.000", "0.000", "0.000"), idiom=i) for i in IDIOMS]


def gamuts_and_appearances():
    return [entry(rgb("1.000", "0.000", "0.000"), **{"display-gamut": gamut}, **extra)
            for gamut in ("sRGB", "display-P3") for extra in ({}, {"appearances": LIGHT}, {"appearances": DARK})]


def data_catalog(path, names):
    catalog(path, {})
    for name in names:
        data_set(path, name, "blob.txt", name.encode())
    return path


def image_catalog_of(path, count, width=8, height=8):
    catalog(path, {})
    numbered_images(path, [(width, height, count, False)])
    return path


def mixed_kinds(path, color_count, data_count, image_count):
    colors(path, fixed_names(color_count))
    for name in fixed_names(data_count, seed=4):
        data_set(path, "d" + name, "blob.txt", name.encode())
    numbered_images(path, [(8, 8, image_count, False)])
    return path


def colors(path, names, entries=red):
    return catalog(path, {name: entries() for name in names})


# (name, writer of the catalog at a path); one thing varies at a time.
def large_table_cases():
    cases = []
    def add(name, write):
        cases.append((name, write))
    for n in (510, 511, 512, 513, 600, 700, 1000, 1021, 1022, 1500, 3000):
        add(f"names-{n}", lambda p, n=n: colors(p, fixed_names(n)))
    add("names-short-1200", lambda p: colors(p, fixed_names(1200, seed=3, length=5)))
    add("names-other-seed-1300", lambda p: colors(p, fixed_names(1300, seed=7)))
    add("sequential-1200", lambda p: colors(p, [f"c{i:05d}" for i in range(1200)]))
    add("mixed-520", lambda p: colors(p, mixed_names(520)))
    add("mixed-1100", lambda p: colors(p, mixed_names(1100)))
    for n in (170, 171, 200, 400, 1000):
        add(f"appearances3-{n}", lambda p, n=n: colors(p, fixed_names(n), three_appearances))
    for n in (255, 256, 300):
        add(f"appearances2-{n}", lambda p, n=n: colors(p, fixed_names(n), two_appearances))
    # actool keeps three of the six idioms for iPhone and iPad targets: 171 names make 513 renditions.
    for n in (85, 86, 100, 170, 171, 300, 400):
        add(f"idioms6-{n}", lambda p, n=n: colors(p, fixed_names(n), six_idioms))
    add("gamuts-appearances-150", lambda p: colors(p, fixed_names(150), gamuts_and_appearances))
    add("data-600", lambda p: data_catalog(p, fixed_names(600)))
    add("images-600", lambda p: image_catalog_of(p, 600))
    add("images-40px-540", lambda p: image_catalog_of(p, 540, 40, 40))
    add("colors-data-images-520", lambda p: mixed_kinds(p, 300, 120, 100))
    # The hash table's growth points, then past BITMAPKEYS' first branch overflow, then a branch
    # under the root overflowing (about 19,000 identifiers).
    for n in (672, 673, 1065, 1066, 1732, 1733, 2000, 2795, 2796, 4543, 4544, 7391, 7392, 12000, 24000):
        add(f"names-{n}", lambda p, n=n: colors(p, fixed_names(n)))
    return cases


def exp_large_tables(root, nomac):
    from assets_experiments import case
    reports = []
    for name, write in large_table_cases():
        cat = write(root / "catalogs" / name / "A.xcassets")
        reports.append(case(root, name, [cat], nomac))
    return reports
