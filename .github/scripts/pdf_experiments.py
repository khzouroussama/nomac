#!/usr/bin/env python3
"""Observe how Xcode's actool stores PDF image sets, and compare nomac's.

Runs on a Mac with Xcode (DEVELOPER_DIR selects it). Every PDF is written here from scratch.
actool keeps a PDF image set as a vector rendition holding the PDF as Quartz writes it again,
and rasters of it at 1x, 2x and 3x (docs/formats/asset-catalog.md, "PDF images"). Each case is
one image set in one catalog per experiment:

- structure: object numbering and the page's boxes: compressed and plain content, PDF
  versions, an offset, cropped or rotated page, contents split in two streams, an Info
  dictionary, resources inline or indirect.
- info: which entries of the Info dictionary Quartz keeps, one key per case, all of them, and
  producers written as hex, with escapes, in Latin-1, long and empty, and the dates beside
  them in several forms (offsets with and without their apostrophes, a date alone).
- ids: trailer IDs of several forms, with and without an Info dictionary.
- numbers: how coordinates are written again: long decimals, negatives, exponents, large and
  tiny values, integers written as decimals.
- paths: fills of rectangles, lines and curves (`c`, `v`, `y`), even-odd fills, empty paths,
  transformations and nested graphics states, and a path long enough to wrap.
- colors: `rg`, `g`, `k`, `cs`/`sc` in DeviceRGB and DeviceGray, black and white.
- clips: rectangle and even-odd clips, nested in graphics states and transformed.
- number-values to number-values-5: one x coordinate per case, around the rounding and snapping limits
  (number-values-4: where single and double precision decide differently; number-values-5: the limit
  below 1).
- details: when colors and opacities are written again, rectangles drawn as lines, clips
  combined, an empty page, rounding, unbalanced states, comments, marked content and
  settings fills ignore.
- extgstate: fills through an ExtGState with one entry each: overprinting, blend modes, soft masks
  and stroke settings fills ignore.
- state-changes: which changes of opacity, overprinting, smoothness and rendering intent write the
  color again, and their order.
- icc: ICCBased color spaces with profiles written here (sRGB-like, Display P3-like, gray with
  gammas 2.2 and 1.8), uncompressed, without an alternate, two of them, one under two names, next
  to a device color, set with `scn`, and unused; when `cs` is written again: the same space set
  twice, `sc` alone, a device color between, two copies of one profile, DeviceRGB and DeviceGray
  set again.
- xobjects: form XObjects drawn once, transformed (Matrix, cm), clipped by their BBox, twice,
  inheriting the color, with their own resources, nested, after a fill, as transparency groups
  with and without an opacity, inside a clip, and empty.
- strokes: each stroking operator, stroke colors, width, caps, joins, miter limit, dashes,
  transformed strokes, two strokes, rectangles, strokes and fills, ExtGState stroke settings,
  stroke opacity and overprinting.
- groups: transparency group forms (content smaller and larger than the BBox, stroked, with a
  matrix, under a cm, isolated and knockout, with a color space, twice, nested, in a clip, after a
  fill, empty), luminosity and alpha soft masks, a blend mode.
- groups-2: groups drawn with an opacity and setting one, in an ICC space, around a curve, two
  fills, a fill and stroke, a bounding box past the page and one the content misses, rotated,
  with an inherited color, flatness, a clip inside, nested with a matrix, a fill after one,
  within a path clip, a path and a rectangle, an even-odd clip.
- shadings: axial and radial shadings by sh and as pattern colors (fills, a stroke), with
  exponential, stitching, sampled and PostScript functions, without extension, in gray, in a
  clip under a cm, a pattern with a matrix.
- postscript: how Quartz writes a PostScript function again: no-ops, numbers, spacing, nested
  blocks.
- opaque: page-filling fills in gray and RGB and a partial one, for the rasters' opaque flag
  (B-215: actool's flag does not follow the pixels).
- entries: a PDF in the 1x entry, the 2x and 3x ones empty or absent.
- appearances: a PDF per luminosity appearance (any and dark, any, dark and light, the same file
  twice, a dark file alone), colors of several spaces.
- fonts: text in an embedded TrueType font written here (squares and a triangle): unnamed,
  named, with an OS/2 table, several glyphs, colors, runs, TJ, matrices, spacing, rendering
  modes, widths.
- fonts-2: when Quartz keeps a font's codes: MacRoman, WinAnsi or no encoding, a Macintosh or
  Windows cmap, a subset tag, a ToUnicode CMap, a system font's name.
- fonts-3: fonts with glyph names (post format 2): each encoding, a gap in the codes, TJ, the
  Euro, names outside MacRomanEncoding, a named font beside an unnamed one.
- fonts-4: which glyph names Quartz writes with MacRomanEncoding, and which give their Unicode
  value in ToUnicode.
- fonts-5: the descriptor's cap and x heights from glyphs of different heights, with and without
  OS/2 and some letters.
- fonts-6: spaces between glyphs, tiny to large, as Tc, TJ numbers or both, and when Tc is
  reset.
- smasks-2, smasks-3: luminosity soft masks: gray, RGB and ICC group spaces, a group without a
  space, backdrops, transfer functions (Identity, exponential, PostScript, sampled), under a
  matrix, reset, on a stroke and a group.
- strokes-2: stroke adjustment (SA) on strokes and fills, beside smoothness, opacity and intent.
- shadings-2: overprinting, its mode, opacity and smoothness set before sh.
- images-2: an image's rendering intent (set, twice, then a fill), its own /Intent, overprinting.
- groups-4, groups-5, groups-6: what a group is drawn with (overprinting, its mode, a stroke
  opacity), the order of the page's and the group's ExtGStates with patterns and shadings, the
  intent of a shading, an image and a fill inside a group.
- postscript-2: how PostScript functions' numbers are written again, and constants folded.
- cff, cff-2, cff-3: text in an embedded CFF font written here: encodings and Differences,
  glyph names outside MacRomanEncoding, spacing and widths, the box and its growth by units per
  em (16 to 4,096), the Private DICT's stems and default width.

Where a PDF embeds a font, both PDFs are also rendered by Quartz at 50 times their size and
compared pixel by pixel (`rendered` in compare.json): Quartz's font subsets and nomac's differ in
their bytes (ADR 0204) but must draw the same glyphs.
- smasks: alpha soft masks on fills, a group, a stroke, two fills, reset with /None, inside q,
  under a cm, with their own bounding box, matrix, opacity and colors, one without a group.
- images: image XObjects (RGB and gray, Flate, uncompressed and JPEG, a JPEG in an ICC space or
  with a soft mask, a soft mask, ICC,
  /Interpolate, rotated, drawn twice, a stencil mask, /Decode, 1-bit, after a fill, in a clip,
  with an opacity, in a group).
- text: Type 3 fonts (an empty glyph, drawn glyphs, TJ adjustments, character and word spacing
  with horizontal scaling, Tm under a cm, a font matrix, colors in d0 and d1 glyphs, the
  invisible rendering mode, leading and rise, a stroked glyph), BT ET alone.
- groups-3: what a stroke adds to a group's bounding box: widths, miter limits, joins, caps, a
  hairline, a curve, a dash, a rectangle, a scale, a closed path.
- rect-forms: rectangles as clips and fills: even-odd and nonzero, both turning directions, four
  and five points, through a flipping cm.
- opacity: fills through an ExtGState's `ca`.

For each case <out>/<experiment>/actool holds actool's outputs, <case>.pdf the vector
rendition's PDF and <case>.txt its objects with the streams decompressed (the ICC profile by
its length and MD5). With --nomac, nomac's actool runs on the same catalog and compare.json
records, per case, whether its PDF is identical but for the ICC profile stream (ADR 0204), and
for the catalog whether nomac's Assets.car is identical or equivalent under ADR 0204; when nomac
refuses a case, each case is compiled again in a catalog of its own.

Usage: pdf_experiments.py <output-dir> [--nomac <nomac>] [experiment ...]
"""

import ctypes
import ctypes.util
import hashlib
import importlib.util
import json
import re
import shutil
import struct
import subprocess
import sys
import zlib
from pathlib import Path

_spec = importlib.util.spec_from_file_location("assets_experiments", Path(__file__).with_name("assets_experiments.py"))
ae = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ae)


def pdf(content, width=20, height=10, resources=b"", compress=False, version=b"1.4", page_extra=b"", streams=None, info=None,
        indirect_resources=False, trailer_extra=b""):
    """A one-page PDF drawing `content` (or the list `streams`) on a `width` × `height` MediaBox."""
    bodies = streams if streams is not None else [content]
    objects = [b"<< /Type /Catalog /Pages 2 0 R >>", b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>", None]
    contents = []
    for body in bodies:
        data = zlib.compress(body) if compress else body
        contents.append(len(objects) + 1)
        objects.append(b"<< /Length %d%s >>\nstream\n" % (len(data), b" /Filter /FlateDecode" if compress else b"") + data + b"\nendstream")
    resource_ref = b"<< %s >>" % resources
    if indirect_resources:
        objects.append(b"<< %s >>" % resources)
        resource_ref = b"%d 0 R" % len(objects)
    content_ref = b"%d 0 R" % contents[0] if len(contents) == 1 else b"[" + b" ".join(b"%d 0 R" % c for c in contents) + b"]"
    objects[2] = b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %s %s] /Contents %s /Resources %s%s >>" % (
        str(width).encode(), str(height).encode(), content_ref, resource_ref, page_extra)
    if info:
        objects.append(info)
    out = b"%PDF-" + version + b"\n"
    offsets = []
    for index, body in enumerate(objects):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % (index + 1) + body + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objects) + 1) + b"".join(b"%010d 00000 n \n" % o for o in offsets)
    trailer = b"/Size %d /Root 1 0 R" % (len(objects) + 1) + (b" /Info %d 0 R" % len(objects) if info else b"") + trailer_extra
    return out + b"trailer\n<< %s >>\nstartxref\n%d\n%%%%EOF\n" % (trailer, xref)


def icc_profile(space, colorants=None, gamma=None, curve=None, description="nomac experiment"):
    """A version 2 display profile written here: RGB colorants (D50 XYZ) and one curve, or gray."""
    def be(value, size=4):
        return value.to_bytes(size, "big")
    def xyz(x, y, z):
        return b"XYZ \0\0\0\0" + b"".join(be(round(v * 65536) & 0xFFFFFFFF) for v in (x, y, z))
    if curve is not None:
        trc = b"curv\0\0\0\0" + be(len(curve)) + b"".join(be(round(v * 65535), 2) for v in curve)
    else:
        trc = b"curv\0\0\0\0" + be(1) + be(round(gamma * 256), 2)
    text = description.encode() + b"\0"
    tags = [("desc", b"desc\0\0\0\0" + be(len(text)) + text + b"\0" * 78), ("cprt", b"text\0\0\0\0Public domain\0"),
            ("wtpt", xyz(0.9642, 1.0, 0.8249))]
    if space == b"RGB ":
        tags += [("rXYZ", xyz(*colorants[0])), ("gXYZ", xyz(*colorants[1])), ("bXYZ", xyz(*colorants[2])),
                 ("rTRC", trc), ("gTRC", trc), ("bTRC", trc)]
    else:
        tags += [("kTRC", trc)]
    table, body, offset = be(len(tags)), b"", 128 + 4 + 12 * len(tags)
    for signature, data in tags:
        data += b"\0" * (-len(data) % 4)
        table += signature.encode() + be(offset) + be(len(data))
        body += data
        offset += len(data)
    header = be(128 + len(table) + len(body)) + b"none" + b"\x02\x10\0\0" + b"mntr" + space + b"XYZ " + b"\0" * 12 + b"acsp" + b"\0" * 32
    header += xyz(0.9642, 1.0, 0.8249)[8:]
    return header + b"\0" * (128 - len(header)) + table + body


SRGB_CURVE = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in (i / 1023 for i in range(1024))]
SRGB_LIKE = icc_profile(b"RGB ", [(0.4361, 0.2225, 0.0139), (0.3851, 0.7169, 0.0971), (0.1431, 0.0606, 0.7141)], curve=SRGB_CURVE)
P3 = icc_profile(b"RGB ", [(0.5151, 0.2412, -0.0011), (0.2920, 0.6922, 0.0419), (0.1571, 0.0666, 0.7841)], curve=SRGB_CURVE, description="P3")
GRAY22 = icc_profile(b"GRAY", gamma=2.2, description="gray 2.2")
GRAY18 = icc_profile(b"GRAY", gamma=1.8, description="gray 1.8")


def icc_pdf(content, profiles, compress=True, alternate=True, names=None):
    """A page whose color spaces are ICCBased: `profiles` [(profile, components)], each named
    /CsN (or as `names` give, several names for one profile)."""
    width, height = 20, 10
    objects = [b"<< /Type /Catalog /Pages 2 0 R >>", b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>", None, None]
    spaces = []
    for profile, components in profiles:
        data = zlib.compress(profile) if compress else profile
        alt = {1: b" /Alternate /DeviceGray", 3: b" /Alternate /DeviceRGB", 4: b" /Alternate /DeviceCMYK"}[components] if alternate else b""
        objects.append(b"<< /N %d%s /Length %d%s >>\nstream\n" % (components, alt, len(data), b" /Filter /FlateDecode" if compress else b"") + data + b"\nendstream")
        objects.append(b"[/ICCBased %d 0 R]" % len(objects))
        spaces.append(len(objects))
    names = names or [(b"Cs%d" % (i + 1), i) for i in range(len(spaces))]
    resources = b"/ColorSpace << " + b" ".join(b"/%s %d 0 R" % (name, spaces[i]) for name, i in names) + b" >>"
    objects[2] = b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %d %d] /Contents 4 0 R /Resources << %s >> >>" % (width, height, resources)
    objects[3] = b"<< /Length %d >>\nstream\n" % len(content) + content + b"\nendstream"
    out, offsets = b"%PDF-1.4\n", []
    for index, body in enumerate(objects):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % (index + 1) + body + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objects) + 1) + b"".join(b"%010d 00000 n \n" % o for o in offsets)
    return out + b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objects) + 1, xref)


def objects_pdf(content, extra, resources, width=20, height=10):
    """A page drawing `content` with `resources`, `extra` objects numbered from 5 (each written as
    given: a stream with its dictionary or any other object)."""
    objects = [b"<< /Type /Catalog /Pages 2 0 R >>", b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
               b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %d %d] /Contents 4 0 R /Resources << %s >> >>" % (width, height, resources),
               b"<< /Length %d >>\nstream\n" % len(content) + content + b"\nendstream"] + list(extra)
    out, offsets = b"%PDF-1.4\n", []
    for index, body in enumerate(objects):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % (index + 1) + body + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objects) + 1) + b"".join(b"%010d 00000 n \n" % o for o in offsets)
    return out + b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objects) + 1, xref)


def form(content, bbox=b"0 0 20 10", extra=b""):
    return b"<< /Type /XObject /Subtype /Form /BBox [%s]%s /Length %d >>\nstream\n" % (bbox, extra, len(content)) + content + b"\nendstream"


RED = b"1 0 0 rg "


def stream(content):
    return b"<< /Length %d >>\nstream\n" % len(content) + content + b"\nendstream"


def image(data, width, height, space=b"/DeviceRGB", bits=8, extra=b"", compress=True):
    """An image XObject of `data`, Flate-compressed unless `compress` is false or `extra` names
    a filter."""
    if compress and b"/Filter" not in extra:
        data, extra = zlib.compress(data), extra + b" /Filter /FlateDecode"
    head = b"<< /Type /XObject /Subtype /Image /Width %d /Height %d /BitsPerComponent %d" % (width, height, bits)
    if space is not None:
        head += b" /ColorSpace " + space
    return head + extra + b" /Length %d >>\nstream\n" % len(data) + data + b"\nendstream"


RGB4 = bytes([255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0])
GRAY4 = bytes([0, 85, 170, 255])


def truetype_font(glyphs, postscript_name=None, os2=None, ascent=1000, descent=0, mac_cmap=False, names=None):
    """A TrueType font of 1,000 units per em written here: `glyphs` maps a character to its
    contours, each a list of on-curve points, every advance 1,000, glyph 0 empty; a name table
    with `postscript_name` and an OS/2 table with `os2` (cap height, x height) when given;
    `ascent` and `descent` in hhea; a Windows Unicode cmap, or a Macintosh one with `mac_cmap`;
    glyph names (post format 2) when `names` maps each character to one."""
    def pack(fields):
        return b"".join(struct.pack(">" + f, v) for f, v in fields)
    order = sorted(glyphs)
    outlines = [b""]
    for char in order:
        contours = glyphs[char]
        points = [p for c in contours for p in c]
        xs, ys = [p[0] for p in points], [p[1] for p in points]
        data = struct.pack(">hhhhh", len(contours), min(xs), min(ys), max(xs), max(ys))
        end = -1
        for c in contours:
            end += len(c)
            data += struct.pack(">H", end)
        data += struct.pack(">H", 0) + bytes([1] * len(points))
        for values in (xs, ys):
            last = 0
            for v in values:
                data += struct.pack(">h", v - last)
                last = v
        outlines.append(data + b"\0" * (-len(data) % 4))
    offsets = [0]
    for o in outlines:
        offsets.append(offsets[-1] + len(o))
    count = len(outlines)
    segments = [(ord(c), 1 + i) for i, c in enumerate(order)] + [(0xFFFF, 0)]
    n = len(segments)
    body = struct.pack(">HHHH", 2 * n, 2, 0, 0) + b"".join(struct.pack(">H", c) for c, _ in segments) + b"\0\0"
    body += b"".join(struct.pack(">H", c) for c, _ in segments)
    body += b"".join(struct.pack(">H", (g - c) % 65536 if g else 1) for c, g in segments) + b"\0\0" * n
    cmap = struct.pack(">HHHHI", 0, 1, 3, 1, 12) + struct.pack(">HHH", 4, 6 + len(body), 0) + body
    if mac_cmap:
        first = ord(order[0])
        codes = [order.index(chr(c)) + 1 if chr(c) in order else 0 for c in range(first, ord(order[-1]) + 1)]
        cmap = struct.pack(">HHHHI", 0, 1, 1, 0, 12) + struct.pack(">HHHHH", 6, 10 + 2 * len(codes), 0, first, len(codes))
        cmap += b"".join(struct.pack(">H", g) for g in codes)
    tables = {
        b"cmap": cmap,
        b"glyf": b"".join(outlines),
        b"head": pack([("I", 0x10000), ("I", 0x10000), ("I", 0), ("I", 0x5F0F3CF5), ("H", 0), ("H", 1000), ("Q", 0), ("Q", 0),
                       ("h", 0), ("h", 0), ("h", 1000), ("h", 1000), ("H", 0), ("H", 8), ("h", 2), ("h", 1), ("h", 0)]),
        b"hhea": pack([("I", 0x10000), ("h", ascent), ("h", descent), ("h", 0), ("H", 1000), ("h", 0), ("h", 0), ("h", 1000), ("h", 1), ("h", 0),
                       ("h", 0)] + [("h", 0)] * 4 + [("h", 0), ("H", count)]),
        b"hmtx": b"".join(struct.pack(">Hh", 1000, 0) for _ in range(count)),
        b"loca": b"".join(struct.pack(">I", o) for o in offsets),
        b"maxp": pack([("I", 0x10000), ("H", count)] + [("H", 64)] * 13),
        b"post": pack([("I", 0x30000), ("I", 0), ("h", 0), ("h", 0), ("I", 0)] + [("I", 0)] * 4),
    }
    if names:
        strings = [names[c].encode() for c in order]
        tables[b"post"] = (pack([("I", 0x20000), ("I", 0), ("h", 0), ("h", 0), ("I", 0)] + [("I", 0)] * 4) + struct.pack(">H", count)
                           + struct.pack(">H", 0) + b"".join(struct.pack(">H", 258 + i) for i in range(len(strings)))
                           + b"".join(bytes([len(n)]) + n for n in strings))
    if postscript_name:
        text = postscript_name.encode("utf-16-be")
        tables[b"name"] = struct.pack(">HHH", 0, 1, 18) + struct.pack(">HHHHHH", 3, 1, 0x409, 6, len(text), 0) + text
    else:
        tables[b"name"] = struct.pack(">HHH", 0, 0, 6)
    if os2:
        cap, x = os2
        tables[b"OS/2"] = pack([("H", 2), ("h", 1000), ("H", 400), ("H", 5), ("H", 0)] + [("h", 0)] * 11 + [("10s", b"\0" * 10)]
                               + [("I", 0)] * 4 + [("4s", b"none"), ("H", 0x40), ("H", 0x20), ("H", 0xFFFF), ("h", 1000), ("h", 0),
                                                   ("h", 0), ("H", 1000), ("H", 0), ("I", 1), ("I", 0), ("h", x), ("h", cap), ("H", 0),
                                                   ("H", 32), ("H", 0)])
    out = struct.pack(">IHHHH", 0x10000, len(tables), 128, 3, len(tables) * 16 - 128)
    offset, data = 12 + 16 * len(tables), b""
    for tag in sorted(tables):
        t = tables[tag] + b"\0" * (-len(tables[tag]) % 4)
        out += tag + struct.pack(">III", sum(struct.unpack(">%dI" % (len(t) // 4), t)) & 0xFFFFFFFF, offset + len(data), len(tables[tag]))
        data += t
    return out + data


def cff_number(value, dictionary=False):
    """A number in a CFF DICT (`dictionary`) or Type 2 charstring."""
    if -107 <= value <= 107:
        return bytes([value + 139])
    if 108 <= value <= 1131:
        return bytes([247 + (value - 108) // 256, (value - 108) % 256])
    if -1131 <= value <= -108:
        return bytes([251 + (-value - 108) // 256, (-value - 108) % 256])
    return bytes([28]) + struct.pack(">h", value)


def cff_index(items):
    if not items:
        return b"\0\0"
    offsets = [1]
    for item in items:
        offsets.append(offsets[-1] + len(item))
    return struct.pack(">HB", len(items), 4) + b"".join(struct.pack(">I", o) for o in offsets) + b"".join(items)


def cff_font(glyphs, name="SquareSans-Bold", bbox=(0, 0, 1000, 1000), units=1000, names=None, widths=None, private=()):
    """A CFF font written here: `glyphs` maps a character to contours of on-curve points drawn
    with lines, each named by `names` (the character itself by default), advance `widths` (the
    em by default), glyph 0 empty, the standard encoding, a `units`-per-em font matrix, and
    `private` (operator, value) entries before the widths in the Private DICT."""
    order = sorted(glyphs)
    names = names or {c: c for c in order}
    widths = widths or {}

    def charstring(char):
        out, x, y = cff_number(widths.get(char, units)), 0, 0
        for contour in glyphs[char]:
            first = True
            for px, py in contour:
                out += cff_number(px - x) + cff_number(py - y) + bytes([21 if first else 5])
                x, y, first = px, py, False
        return out + bytes([14])
    strings = [names[c].encode() for c in order] + [name.encode()]
    charset = b"\0" + b"".join(struct.pack(">H", 391 + i) for i in range(len(order)))
    charstrings = cff_index([cff_number(units) + bytes([14])] + [charstring(c) for c in order])
    private = b"".join(cff_number(v, True) + bytes([op]) for op, v in private) + cff_number(0, True) + bytes([20]) + cff_number(0, True) + bytes([21])

    def top(charset_at, charstrings_at, private_at):
        out = cff_number(391 + len(order), True) + bytes([2])
        if units != 1000:
            out += b"\x1e\x1f" + b"".join(cff_number(0, True) for _ in range(2))  # placeholder replaced below
        out += b"".join(cff_number(v, True) for v in bbox) + bytes([5])
        out += bytes([29]) + struct.pack(">i", charset_at) + bytes([15]) + bytes([29]) + struct.pack(">i", charstrings_at) + bytes([17])
        out += bytes([29]) + struct.pack(">i", len(private)) + bytes([29]) + struct.pack(">i", private_at) + bytes([18])
        return out
    if units != 1000:
        scale = ("%.10f" % (1 / units)).rstrip("0")

        def real(text):
            nibbles = [int(c) if c.isdigit() else 0xA for c in text.lstrip("0")] + [0xF]
            if len(nibbles) % 2:
                nibbles.append(0xF)
            return bytes([0x1E]) + bytes(nibbles[i] << 4 | nibbles[i + 1] for i in range(0, len(nibbles), 2))
        matrix = real(scale) + cff_number(0, True) + cff_number(0, True) + real(scale) + cff_number(0, True) + cff_number(0, True) + b"\x0c\x07"
        base_top = top
        top = lambda a, b, c: base_top(a, b, c).replace(b"\x1e\x1f" + cff_number(0, True) * 2, matrix)
    head = bytes([1, 0, 4, 4]) + cff_index([name.encode()])
    rest_before = cff_index(strings) + cff_index([])
    size = len(top(0, 0, 0))
    charset_at = len(head) + len(cff_index([b"\0" * size])) + len(rest_before)
    charstrings_at = charset_at + len(charset)
    private_at = charstrings_at + len(charstrings)
    return head + cff_index([top(charset_at, charstrings_at, private_at)]) + rest_before + charset + charstrings + private


def cff_pdf(content, font, first=65, widths=(1000, 1000, 1000), encoding=None, name=b"Square", descriptor=b"", flags=32):
    """A page showing `content` with the CFF `font` embedded as /F1 (FontFile3 /Type1C)."""
    encoding_entry = b" /Encoding " + encoding if encoding else b""
    return objects_pdf(content, [
        b"<< /Type /Font /Subtype /Type1 /BaseFont /%s /FirstChar %d /LastChar %d /Widths [%s] /FontDescriptor 6 0 R%s >>"
        % (name, first, first + len(widths) - 1, b" ".join(b"%d" % w for w in widths), encoding_entry),
        b"<< /Type /FontDescriptor /FontName /%s /Flags %d /FontBBox [0 0 1000 1000] /ItalicAngle 0 /Ascent 1000 /Descent 0 /CapHeight 700 "
        b"/StemV 80%s /FontFile3 7 0 R >>" % (name, flags, descriptor),
        b"<< /Subtype /Type1C /Length %d >>\nstream\n" % len(font) + font + b"\nendstream"], b"/Font << /F1 5 0 R >>")


SQUARES = {"A": [[(100, 0), (100, 700), (900, 700), (900, 0)]], "B": [[(0, 0), (0, 1000), (500, 1000), (500, 0)]],
           "C": [[(100, 100), (500, 900), (900, 100)]]}
NAMES = {"A": "A", "B": "B", "C": "C"}
HEIGHTS = {c: [[(100, -h // 20), (100, h), (900, h), (900, -h // 20)]] for c, h in
           {"A": 610, "H": 620, "I": 630, "O": 640, "E": 650, "x": 410, "v": 420, "o": 430, "z": 440, "u": 450}.items()}
OTHER_NAMES = ["Euro", "Scaron", "onehalf", "multiply", "brokenbar", "Lslash", "minus", "uni0416", "afii10017", "Gbreve", "dcroat", "fi.alt",
               "f_f", "u1F600"]
MAC_NAMES = ['notequal', 'infinity', 'lessequal', 'greaterequal', 'partialdiff', 'summation', 'product', 'pi', 'integral', 'Omega', 'radical', 'approxequal', 'Delta', 'lozenge', 'apple', 'currency', 'space', 'nonbreakingspace', 'nbspace', 'quotesingle', 'grave', 'Euro', 'minus']


def truetype_pdf(content, font, first=65, widths=(1000, 1000, 1000), encoding=b"/WinAnsiEncoding", name=b"Square", extra=b"", flags=32):
    """A page showing `content` with the TrueType `font` embedded as /F1, without /Encoding when
    `encoding` is None."""
    widths_text = b" ".join(b"%d" % w for w in widths)
    encoding_entry = b" /Encoding " + encoding if encoding else b""
    return objects_pdf(content, [
        b"<< /Type /Font /Subtype /TrueType /BaseFont /%s /FirstChar %d /LastChar %d /Widths [%s] /FontDescriptor 6 0 R%s%s >>"
        % (name, first, first + len(widths) - 1, widths_text, encoding_entry, extra),
        b"<< /Type /FontDescriptor /FontName /%s /Flags %d /FontBBox [0 0 1000 1000] /ItalicAngle 0 /Ascent 1000 /Descent 0 /CapHeight 700 "
        b"/StemV 80 /FontFile2 7 0 R >>" % (name, flags),
        b"<< /Length %d /Length1 %d >>\nstream\n" % (len(font), len(font)) + font + b"\nendstream"], b"/Font << /F1 5 0 R >>")


GS = b"/ExtGState << /G1 << /ca 0.5 >> >>"
GROUP = b" /Group << /S /Transparency >>"

EXPERIMENT_CASES = {
    "structure": {
        "plain": pdf(RED + b"2 2 16 6 re f"),
        "compressed": pdf(RED + b"2 2 16 6 re f", compress=True),
        "version13": pdf(RED + b"2 2 16 6 re f", version=b"1.3"),
        "version17": pdf(RED + b"2 2 16 6 re f", version=b"1.7"),
        "offset": pdf(RED + b"7 7 16 6 re f", page_extra=b" /MediaBox [5 5 25 15]"),
        "cropped": pdf(RED + b"2 2 16 6 re f", page_extra=b" /CropBox [1 1 19 9]"),
        "rotated": pdf(RED + b"2 2 16 6 re f", page_extra=b" /Rotate 90"),
        "two-streams": pdf(None, streams=[RED + b"2 2 8 6 re f", b"0 0 1 rg 10 2 8 6 re f"]),
        "info": pdf(RED + b"2 2 16 6 re f", info=b"<< /Producer (nomac) /Title (T) >>"),
        "indirect-resources": pdf(b"/G1 gs " + RED + b"2 2 16 6 re f", resources=GS, indirect_resources=True),
        "unused-resources": pdf(RED + b"2 2 16 6 re f", resources=GS),
        "size-fraction": pdf(RED + b"1 1 10 5 re f", width=12.5, height=7.25),
    },
    "info": {
        **{f"key-{key.lower()}": pdf(RED + b"2 2 16 6 re f", info=b"<< /%s (Value of %s) >>" % (key.encode(), key.encode()))
           for key in ["Producer", "Creator", "Title", "Author", "Subject", "Keywords", "CreationDate", "ModDate", "Trapped", "Custom"]},
        "all": pdf(RED + b"2 2 16 6 re f", info=b"<< /Title (T) /Author (A) /Subject (S) /Keywords (K) /Creator (C) /Producer (P) "
                   b"/CreationDate (D:20240101000000Z) /ModDate (D:20240102000000Z) >>"),
        "producer-hex": pdf(RED + b"2 2 16 6 re f", info=b"<< /Producer <FEFF004E00F600F7> >>"),
        "producer-escapes": pdf(RED + b"2 2 16 6 re f", info=b"<< /Producer (a\\(b\\)c\\\\d\\ne) >>"),
        "producer-latin1": pdf(RED + b"2 2 16 6 re f", info=b"<< /Producer (Caf\xe9) >>"),
        "producer-long": pdf(RED + b"2 2 16 6 re f", info=b"<< /Producer (" + b"x" * 90 + b") >>"),
        "producer-empty": pdf(RED + b"2 2 16 6 re f", info=b"<< /Producer () >>"),
        "producer-created": pdf(RED + b"2 2 16 6 re f", info=b"<< /Producer (P) /CreationDate (D:20240101000000Z) >>"),
        "producer-modified": pdf(RED + b"2 2 16 6 re f", info=b"<< /Producer (P) /ModDate (D:20240102000000Z) >>"),
        "created-modified": pdf(RED + b"2 2 16 6 re f", info=b"<< /CreationDate (D:20240101000000Z) /ModDate (D:20240102000000Z) >>"),
        "creator-created": pdf(RED + b"2 2 16 6 re f", info=b"<< /Creator (C) /CreationDate (D:20240101000000Z) >>"),
        "title-created": pdf(RED + b"2 2 16 6 re f", info=b"<< /Title (T) /CreationDate (D:20240101000000Z) >>"),
        "date-offset": pdf(RED + b"2 2 16 6 re f", info=b"<< /Producer (P) /CreationDate (D:20240615123456+02'00') >>"),
        "date-short": pdf(RED + b"2 2 16 6 re f", info=b"<< /Producer (P) /CreationDate (D:2024) >>"),
        "date-local": pdf(RED + b"2 2 16 6 re f", info=b"<< /Producer (P) /CreationDate (D:20240615123456) >>"),
        "date-negative": pdf(RED + b"2 2 16 6 re f", info=b"<< /Producer (P) /CreationDate (D:20240615123456-05'30') >>"),
        "date-offset-open": pdf(RED + b"2 2 16 6 re f", info=b"<< /Producer (P) /CreationDate (D:20240615123456+02'00) >>"),
        "date-offset-hours": pdf(RED + b"2 2 16 6 re f", info=b"<< /Producer (P) /CreationDate (D:20240615123456+02) >>"),
        "date-offset-bare": pdf(RED + b"2 2 16 6 re f", info=b"<< /Producer (P) /CreationDate (D:20240615123456+0200) >>"),
        "date-offset-hours-quote": pdf(RED + b"2 2 16 6 re f", info=b"<< /Producer (P) /CreationDate (D:20240615123456+02') >>"),
        "date-only": pdf(RED + b"2 2 16 6 re f", info=b"<< /CreationDate (D:20240615123456Z) >>"),
    },
    "ids": {
        "literal": pdf(RED + b"2 2 16 6 re f", trailer_extra=b" /ID [(some) (id)]"),
        "literal-same": pdf(RED + b"2 2 16 6 re f", trailer_extra=b" /ID [(some) (some)]"),
        "literal-other": pdf(RED + b"2 2 16 6 re f", trailer_extra=b" /ID [(other) (id)]"),
        "hex": pdf(RED + b"2 2 16 6 re f", trailer_extra=b" /ID [<0123456789abcdef0123456789abcdef> <fedcba9876543210fedcba9876543210>]"),
        "hex-same-first": pdf(RED + b"2 2 16 6 re f", trailer_extra=b" /ID [<0123456789abcdef0123456789abcdef> <00000000000000000000000000000000>]"),
        "short-hex": pdf(RED + b"2 2 16 6 re f", trailer_extra=b" /ID [<01> <02>]"),
        "empty": pdf(RED + b"2 2 16 6 re f", trailer_extra=b" /ID [() ()]"),
        "hex-equal": pdf(RED + b"2 2 16 6 re f", trailer_extra=b" /ID [<46A1F0C603F8C598D240D4432B8F620C><46A1F0C603F8C598D240D4432B8F620C>]"),
        "hex-equal-info": pdf(RED + b"2 2 16 6 re f", info=b"<< /Producer (P) >>",
                              trailer_extra=b" /ID [<46A1F0C603F8C598D240D4432B8F620C><46A1F0C603F8C598D240D4432B8F620C>]"),
        "hex-different-info": pdf(RED + b"2 2 16 6 re f", info=b"<< /Producer (P) >>",
                                  trailer_extra=b" /ID [<0123456789abcdef0123456789abcdef> <fedcba9876543210fedcba9876543210>]"),
        "info-title": pdf(RED + b"2 2 16 6 re f", info=b"<< /Title (T) >>",
                          trailer_extra=b" /ID [<0123456789abcdef0123456789abcdef> <fedcba9876543210fedcba9876543210>]"),
        "info-empty": pdf(RED + b"2 2 16 6 re f", info=b"<< >>",
                          trailer_extra=b" /ID [<0123456789abcdef0123456789abcdef> <fedcba9876543210fedcba9876543210>]"),
        "info-literal": pdf(RED + b"2 2 16 6 re f", info=b"<< /Producer (P) >>", trailer_extra=b" /ID [(some) (id)]"),
        "info-short": pdf(RED + b"2 2 16 6 re f", info=b"<< /Producer (P) >>", trailer_extra=b" /ID [<01> <0203>]"),
        "version17-equal": pdf(RED + b"2 2 16 6 re f", version=b"1.7",
                               trailer_extra=b" /ID [<46A1F0C603F8C598D240D4432B8F620C><46A1F0C603F8C598D240D4432B8F620C>]"),
    },
    "numbers": {
        "long": pdf(RED + b"0.1234567891 1.5 m 18.0000001 1.5 l 9 9.87654321 l h f"),
        "negative": pdf(RED + b"1 0 0 1 10 5 cm -5 -3 m 5 -3 l 0 3 l h f"),
        "exponent": pdf(RED + b"2 2 m 18 2 l 18 1e1 l h f"),
        "large": pdf(RED + b"-1234567.891 -1 m 1234567.891 -1 l 0 9 l h f"),
        "tiny": pdf(RED + b"0.000001 0.0000049 m 18 0.0000051 l 9 9 l h f"),
        "decimals": pdf(RED + b"2.0 2.50 m 18.000 2.5 l 9.10 9 l h f"),
        "thirds": pdf(RED + b"0.3333333333 0.6666666667 m 17.333333333 1 l 9 9.1111111 l h f"),
    },
    "paths": {
        "rect": pdf(RED + b"2 2 16 6 re f"),
        "lines": pdf(RED + b"2 2 m 18 2 l 10 9 l h f"),
        "curve-c": pdf(RED + b"2 2 m 6 9 14 9 18 2 c h f"),
        "curve-v": pdf(RED + b"2 2 m 10 9 18 2 v h f"),
        "curve-y": pdf(RED + b"2 2 m 10 9 18 2 y h f"),
        "even-odd": pdf(RED + b"2 2 16 6 re 6 4 8 2 re f*"),
        "fill-F": pdf(RED + b"2 2 16 6 re F"),
        "open": pdf(RED + b"2 2 m 18 2 l 10 9 l f"),
        "two-subpaths": pdf(RED + b"2 2 m 8 2 l 5 8 l h 12 2 m 18 2 l 15 8 l h f"),
        "empty-path": pdf(RED + b"2 2 m n 2 2 16 6 re f"),
        "translate": pdf(b"q 1 0 0 1 3 1 cm " + RED + b"0 0 10 5 re f Q"),
        "scale": pdf(b"q 2 0 0 2 0 0 cm " + RED + b"1 1 8 3 re f Q"),
        "rotate": pdf(b"q 0 1 -1 0 15 2 cm " + RED + b"0 0 6 4 re f Q"),
        "skew": pdf(b"q 1 0 0.5 1 0 0 cm " + RED + b"2 2 10 6 re f Q"),
        "nested": pdf(b"q " + RED + b"q 0 0 1 rg 2 2 4 4 re f Q 10 2 4 4 re f Q"),
        "nested-cm": pdf(b"q 1 0 0 1 2 0 cm q 1 0 0 1 0 2 cm " + RED + b"0 0 4 4 re f Q 8 0 4 4 re f Q"),
        "two-fills": pdf(RED + b"2 2 6 6 re f 0 0 1 rg 10 2 6 6 re f"),
        "long-path": pdf(RED + b"1 1 m " + b" ".join(b"%d.25 %d.75 l" % (1 + i % 18, 1 + (i * 7) % 8) for i in range(40)) + b" h f"),
    },
    "colors": {
        "rg": pdf(b"0.2 0.4 0.6 rg 2 2 16 6 re f"),
        "gray": pdf(b"0.5 g 2 2 16 6 re f"),
        "cmyk": pdf(b"0.1 0.2 0.3 0.4 k 2 2 16 6 re f"),
        "cs-rgb": pdf(b"/DeviceRGB cs 0.2 0.4 0.6 sc 2 2 16 6 re f"),
        "cs-gray": pdf(b"/DeviceGray cs 0.5 sc 2 2 16 6 re f"),
        "scn-rgb": pdf(b"/DeviceRGB cs 0.2 0.4 0.6 scn 2 2 16 6 re f"),
        "black": pdf(b"0 0 0 rg 2 2 16 6 re f"),
        "white": pdf(b"1 1 1 rg 2 2 16 6 re f"),
        "default": pdf(b"2 2 16 6 re f"),
        "two-colors": pdf(b"0.2 0.4 0.6 rg 2 2 6 6 re f 0.5 g 10 2 6 6 re f"),
    },
    "clips": {
        "rect": pdf(b"q 4 2 12 6 re W n " + RED + b"0 0 20 10 re f Q"),
        "even-odd": pdf(b"q 2 1 16 8 re 6 3 8 4 re W* n " + RED + b"0 0 20 10 re f Q"),
        "curve": pdf(b"q 2 2 m 6 9 14 9 18 2 c h W n " + RED + b"0 0 20 10 re f Q"),
        "unclipped-after": pdf(b"q 4 2 12 6 re W n " + RED + b"0 0 20 10 re f Q 0 0 1 rg 0 0 3 3 re f"),
        "two-clips": pdf(b"q 2 2 12 6 re W n 6 0 12 10 re W n " + RED + b"0 0 20 10 re f Q"),
        "transformed": pdf(b"q 1 0 0 1 3 1 cm 0 0 8 4 re W n " + RED + b"0 0 20 10 re f Q"),
        "clip-fill": pdf(b"q 4 2 12 6 re W " + RED + b"f Q"),
    },
    "number-values-2": {
        "w0": pdf(RED + b"0.1000001 1 m 18 1 l 9 9 l h f"),
        "w1": pdf(RED + b"0.1000002 1 m 18 1 l 9 9 l h f"),
        "w2": pdf(RED + b"0.1000004 1 m 18 1 l 9 9 l h f"),
        "w3": pdf(RED + b"0.1000005 1 m 18 1 l 9 9 l h f"),
        "w4": pdf(RED + b"0.1000006 1 m 18 1 l 9 9 l h f"),
        "w5": pdf(RED + b"0.1000009 1 m 18 1 l 9 9 l h f"),
        "w6": pdf(RED + b"0.2000003 1 m 18 1 l 9 9 l h f"),
        "w7": pdf(RED + b"0.5000004 1 m 18 1 l 9 9 l h f"),
        "w8": pdf(RED + b"0.0100001 1 m 18 1 l 9 9 l h f"),
        "w9": pdf(RED + b"0.0100002 1 m 18 1 l 9 9 l h f"),
        "w10": pdf(RED + b"0.0100005 1 m 18 1 l 9 9 l h f"),
        "w11": pdf(RED + b"1.1000001 1 m 18 1 l 9 9 l h f"),
        "w12": pdf(RED + b"1.1000004 1 m 18 1 l 9 9 l h f"),
        "w13": pdf(RED + b"1.1000006 1 m 18 1 l 9 9 l h f"),
        "w14": pdf(RED + b"0.3000001 1 m 18 1 l 9 9 l h f"),
        "w15": pdf(RED + b"0.0010001 1 m 18 1 l 9 9 l h f"),
        "w16": pdf(RED + b"0.0001001 1 m 18 1 l 9 9 l h f"),
        "w17": pdf(RED + b"0.00010001 1 m 18 1 l 9 9 l h f"),
        "w18": pdf(RED + b"0.2500001 1 m 18 1 l 9 9 l h f"),
        "w19": pdf(RED + b"0.12345671 1 m 18 1 l 9 9 l h f"),
        "w20": pdf(RED + b"0.12345674 1 m 18 1 l 9 9 l h f"),
        "w21": pdf(RED + b"0.12345676 1 m 18 1 l 9 9 l h f"),
        "w22": pdf(RED + b"10.1000001 1 m 18 1 l 9 9 l h f"),
        "w23": pdf(RED + b"10.100001 1 m 18 1 l 9 9 l h f"),
        "w24": pdf(RED + b"0.0000101 1 m 18 1 l 9 9 l h f"),
    },
    "number-values-3": {
        "x0": pdf(RED + b"0.1200001 1 m 18 1 l 9 9 l h f"),
        "x1": pdf(RED + b"0.1230001 1 m 18 1 l 9 9 l h f"),
        "x2": pdf(RED + b"0.1234001 1 m 18 1 l 9 9 l h f"),
        "x3": pdf(RED + b"0.1234501 1 m 18 1 l 9 9 l h f"),
        "x4": pdf(RED + b"0.1234561 1 m 18 1 l 9 9 l h f"),
        "x5": pdf(RED + b"0.1234567 1 m 18 1 l 9 9 l h f"),
        "x6": pdf(RED + b"0.1000010 1 m 18 1 l 9 9 l h f"),
        "x7": pdf(RED + b"0.1000100 1 m 18 1 l 9 9 l h f"),
        "x8": pdf(RED + b"0.1001000 1 m 18 1 l 9 9 l h f"),
        "x9": pdf(RED + b"0.9000001 1 m 18 1 l 9 9 l h f"),
        "x10": pdf(RED + b"0.9900001 1 m 18 1 l 9 9 l h f"),
        "x11": pdf(RED + b"0.5000005 1 m 18 1 l 9 9 l h f"),
        "x12": pdf(RED + b"0.01000001 1 m 18 1 l 9 9 l h f"),
        "x13": pdf(RED + b"0.01200001 1 m 18 1 l 9 9 l h f"),
        "x14": pdf(RED + b"0.0123401 1 m 18 1 l 9 9 l h f"),
        "x15": pdf(RED + b"1.1200001 1 m 18 1 l 9 9 l h f"),
        "x16": pdf(RED + b"1.2300001 1 m 18 1 l 9 9 l h f"),
        "x17": pdf(RED + b"0.1200005 1 m 18 1 l 9 9 l h f"),
        "x18": pdf(RED + b"0.12000049 1 m 18 1 l 9 9 l h f"),
        "x19": pdf(RED + b"0.1000003 1 m 18 1 l 9 9 l h f"),
        "x20": pdf(RED + b"0.4000002 1 m 18 1 l 9 9 l h f"),
        "x21": pdf(RED + b"0.7500001 1 m 18 1 l 9 9 l h f"),
        "x22": pdf(RED + b"0.12500001 1 m 18 1 l 9 9 l h f"),
        "x23": pdf(RED + b"0.1250001 1 m 18 1 l 9 9 l h f"),
        "x24": pdf(RED + b"0.3000009 1 m 18 1 l 9 9 l h f"),
    },
    "number-values-4": {
        "y0": pdf(RED + b"0.056000056 1 m 18 1 l 9 9 l h f"),
        "y1": pdf(RED + b"0.41999958 1 m 18 1 l 9 9 l h f"),
        "y2": pdf(RED + b"0.077000077 1 m 18 1 l 9 9 l h f"),
        "y3": pdf(RED + b"0.0072999927 1 m 18 1 l 9 9 l h f"),
        "y4": pdf(RED + b"0.0031999968 1 m 18 1 l 9 9 l h f"),
        "y5": pdf(RED + b"0.0075000075 1 m 18 1 l 9 9 l h f"),
        "y6": pdf(RED + b"0.85000085 1 m 18 1 l 9 9 l h f"),
        "y7": pdf(RED + b"0.061000061 1 m 18 1 l 9 9 l h f"),
        "y8": pdf(RED + b"0.048999951 1 m 18 1 l 9 9 l h f"),
        "y9": pdf(RED + b"0.0073000073 1 m 18 1 l 9 9 l h f"),
        "y10": pdf(RED + b"0.0073999926 1 m 18 1 l 9 9 l h f"),
        "y11": pdf(RED + b"0.0016999983 1 m 18 1 l 9 9 l h f"),
        "y12": pdf(RED + b"0.0700007 1 m 18 1 l 9 9 l h f"),
        "y13": pdf(RED + b"0.0064000064 1 m 18 1 l 9 9 l h f"),
        "y14": pdf(RED + b"0.025000025 1 m 18 1 l 9 9 l h f"),
        "y15": pdf(RED + b"0.0022999977 1 m 18 1 l 9 9 l h f"),
        "y16": pdf(RED + b"0.0028000028 1 m 18 1 l 9 9 l h f"),
        "y17": pdf(RED + b"0.74999925 1 m 18 1 l 9 9 l h f"),
        "y18": pdf(RED + b"0.095999904 1 m 18 1 l 9 9 l h f"),
        "y19": pdf(RED + b"0.0096999903 1 m 18 1 l 9 9 l h f"),
        "y20": pdf(RED + b"0.099000099 1 m 18 1 l 9 9 l h f"),
        "y21": pdf(RED + b"0.21999978 1 m 18 1 l 9 9 l h f"),
        "y22": pdf(RED + b"0.0043000043 1 m 18 1 l 9 9 l h f"),
        "y23": pdf(RED + b"0.0075999924 1 m 18 1 l 9 9 l h f"),
        "y24": pdf(RED + b"0.36000036 1 m 18 1 l 9 9 l h f"),
        "y25": pdf(RED + b"0.71999928 1 m 18 1 l 9 9 l h f"),
        "y26": pdf(RED + b"0.0084000084 1 m 18 1 l 9 9 l h f"),
        "y27": pdf(RED + b"0.098000098 1 m 18 1 l 9 9 l h f"),
        "y28": pdf(RED + b"0.0068000068 1 m 18 1 l 9 9 l h f"),
        "y29": pdf(RED + b"0.0499995 1 m 18 1 l 9 9 l h f"),
    },
    "number-values-5": {
        "z0": pdf(RED + b"0.0200001 1 m 18 1 l 9 9 l h f"),
        "z1": pdf(RED + b"0.0300001 1 m 18 1 l 9 9 l h f"),
        "z2": pdf(RED + b"0.0500001 1 m 18 1 l 9 9 l h f"),
        "z3": pdf(RED + b"0.0900001 1 m 18 1 l 9 9 l h f"),
        "z4": pdf(RED + b"0.00100001 1 m 18 1 l 9 9 l h f"),
        "z5": pdf(RED + b"0.00200001 1 m 18 1 l 9 9 l h f"),
        "z6": pdf(RED + b"0.000100001 1 m 18 1 l 9 9 l h f"),
        "z7": pdf(RED + b"0.1000011 1 m 18 1 l 9 9 l h f"),
        "z8": pdf(RED + b"0.1000012 1 m 18 1 l 9 9 l h f"),
        "z9": pdf(RED + b"0.1000015 1 m 18 1 l 9 9 l h f"),
        "z10": pdf(RED + b"0.1000019 1 m 18 1 l 9 9 l h f"),
        "z11": pdf(RED + b"0.12000015 1 m 18 1 l 9 9 l h f"),
        "z12": pdf(RED + b"0.2000001 1 m 18 1 l 9 9 l h f"),
    },
    "details": {
        "same-color": pdf(RED + b"2 2 6 6 re f 10 2 6 6 re f"),
        "same-color-q": pdf(b"q " + RED + b"2 2 6 6 re f Q q " + RED + b"10 2 6 6 re f Q"),
        "same-color-clips": pdf(b"q 0 0 10 10 re W n " + RED + b"2 2 6 6 re f Q q 10 0 10 10 re W n " + RED + b"10 2 6 6 re f Q"),
        "same-color-after-clip": pdf(RED + b"q 0 0 10 10 re W n 2 2 6 6 re f Q 10 2 6 6 re f"),
        "ca-repeat": pdf(b"q /G1 gs " + RED + b"1 1 4 4 re f Q q /G2 gs " + RED + b"7 1 4 4 re f Q q /G1 gs " + RED + b"13 1 4 4 re f Q",
                         resources=b"/ExtGState << /G1 << /ca 0.5 >> /G2 << /ca 0.25 >> >>"),
        "rect-as-lines": pdf(RED + b"2 2 m 18 2 l 18 8 l 2 8 l h f"),
        "rect-as-lines-open": pdf(RED + b"2 2 m 18 2 l 18 8 l 2 8 l f"),
        "rect-reversed": pdf(RED + b"2 2 m 2 8 l 18 8 l 18 2 l h f"),
        "rect-negative": pdf(RED + b"18 8 -16 -6 re f"),
        "two-rects": pdf(RED + b"2 2 6 6 re 10 2 6 6 re f"),
        "empty": pdf(b""),
        "clip-page": pdf(b"q -5 -5 30 20 re W n " + RED + b"2 2 16 6 re f Q"),
        "clip-rect-curve": pdf(b"q 2 1 16 8 re W n 2 2 m 6 9 14 9 18 2 c h W n " + RED + b"0 0 20 10 re f Q"),
        "clip-nested-restore": pdf(b"q 2 1 16 8 re W n q 6 0 4 10 re W n " + RED + b"0 0 20 10 re f Q 0 0 1 rg 0 0 20 10 re f Q"),
        "clip-no-fill": pdf(b"q 2 1 16 8 re W n Q " + RED + b"2 2 16 6 re f"),
        "numbers-small": pdf(RED + b"0.00000001 0.000000123456789 m 18 -0.0 l 9 9 l h f"),
        "numbers-round": pdf(RED + b"1.99999999 2.00000005 m 17.9999996 2 l 9.99999949 9 l h f"),
        "unbalanced-q": pdf(b"q q " + RED + b"2 2 16 6 re f Q"),
        "extra-Q": pdf(RED + b"2 2 16 6 re f Q Q"),
        "comment": pdf(b"% a comment\n" + RED + b"2 2 16 6 re f % trailing\n"),
        "marked-content": pdf(b"/Artifact BMC " + RED + b"2 2 16 6 re f EMC"),
        "stroke-settings": pdf(b"2 w 1 J 1 j 4 M [2 1] 0 d " + RED + b"2 2 16 6 re f"),
        "ri-i": pdf(b"/Perceptual ri 1 i " + RED + b"2 2 16 6 re f"),
    },
    "number-values": {
        "v0": pdf(RED + b"0.000001 1 m 18 1 l 9 9 l h f"),
        "v1": pdf(RED + b"0.0000009 1 m 18 1 l 9 9 l h f"),
        "v2": pdf(RED + b"0.00000099 1 m 18 1 l 9 9 l h f"),
        "v3": pdf(RED + b"0.0000011 1 m 18 1 l 9 9 l h f"),
        "v4": pdf(RED + b"0.0000012345678 1 m 18 1 l 9 9 l h f"),
        "v5": pdf(RED + b"0.00001234567 1 m 18 1 l 9 9 l h f"),
        "v6": pdf(RED + b"0.0000005 1 m 18 1 l 9 9 l h f"),
        "v7": pdf(RED + b"0.00000051 1 m 18 1 l 9 9 l h f"),
        "v8": pdf(RED + b"5.0000009 1 m 18 1 l 9 9 l h f"),
        "v9": pdf(RED + b"5.000001 1 m 18 1 l 9 9 l h f"),
        "v10": pdf(RED + b"5.0000011 1 m 18 1 l 9 9 l h f"),
        "v11": pdf(RED + b"5.0000015 1 m 18 1 l 9 9 l h f"),
        "v12": pdf(RED + b"4.9999991 1 m 18 1 l 9 9 l h f"),
        "v13": pdf(RED + b"4.999999 1 m 18 1 l 9 9 l h f"),
        "v14": pdf(RED + b"123.4567891 1 m 18 1 l 9 9 l h f"),
        "v15": pdf(RED + b"1234567.4 1 m 18 1 l 9 9 l h f"),
        "v16": pdf(RED + b"1000000.6 1 m 18 1 l 9 9 l h f"),
        "v17": pdf(RED + b"12345678.9 1 m 18 1 l 9 9 l h f"),
        "v18": pdf(RED + b"0.1000001 1 m 18 1 l 9 9 l h f"),
        "v19": pdf(RED + b"0.10000005 1 m 18 1 l 9 9 l h f"),
        "v20": pdf(RED + b"-0.0000049 1 m 18 1 l 9 9 l h f"),
        "v21": pdf(RED + b"-3.0000004 1 m 18 1 l 9 9 l h f"),
        "v22": pdf(RED + b"7.123456789 1 m 18 1 l 9 9 l h f"),
        "v23": pdf(RED + b"99999.9999 1 m 18 1 l 9 9 l h f"),
        "v24": pdf(RED + b"0.99999951 1 m 18 1 l 9 9 l h f"),
    },
    "extgstate": {
        "opm1": pdf(b"/G1 gs " + RED + b"2 2 16 6 re f", resources=b"/ExtGState << /G1 << /OPM 1 >> >>"),
        "opm0": pdf(b"/G1 gs " + RED + b"2 2 16 6 re f", resources=b"/ExtGState << /G1 << /OPM 0 >> >>"),
        "op-true": pdf(b"/G1 gs " + RED + b"2 2 16 6 re f", resources=b"/ExtGState << /G1 << /op true >> >>"),
        "stroke-overprint": pdf(b"/G1 gs " + RED + b"2 2 16 6 re f", resources=b"/ExtGState << /G1 << /OP true >> >>"),
        "op-OP-opm": pdf(b"/G1 gs " + RED + b"2 2 16 6 re f", resources=b"/ExtGState << /G1 << /op true /OP true /OPM 1 >> >>"),
        "bm-normal": pdf(b"/G1 gs " + RED + b"2 2 16 6 re f", resources=b"/ExtGState << /G1 << /BM /Normal >> >>"),
        "bm-compatible": pdf(b"/G1 gs " + RED + b"2 2 16 6 re f", resources=b"/ExtGState << /G1 << /BM /Compatible >> >>"),
        "smask-none": pdf(b"/G1 gs " + RED + b"2 2 16 6 re f", resources=b"/ExtGState << /G1 << /SMask /None >> >>"),
        "ais-false": pdf(b"/G1 gs " + RED + b"2 2 16 6 re f", resources=b"/ExtGState << /G1 << /AIS false >> >>"),
        "sa": pdf(b"/G1 gs " + RED + b"2 2 16 6 re f", resources=b"/ExtGState << /G1 << /SA true >> >>"),
        "sm": pdf(b"/G1 gs " + RED + b"2 2 16 6 re f", resources=b"/ExtGState << /G1 << /SM 0.02 >> >>"),
        "lw": pdf(b"/G1 gs " + RED + b"2 2 16 6 re f", resources=b"/ExtGState << /G1 << /LW 3 >> >>"),
        "stroke-alpha": pdf(b"/G1 gs " + RED + b"2 2 16 6 re f", resources=b"/ExtGState << /G1 << /CA 0.5 >> >>"),
        "fl": pdf(b"/G1 gs " + RED + b"2 2 16 6 re f", resources=b"/ExtGState << /G1 << /FL 1 >> >>"),
        "ca-opm": pdf(b"/G1 gs " + RED + b"2 2 16 6 re f", resources=b"/ExtGState << /G1 << /ca 0.5 /OPM 1 >> >>"),
        "type-only": pdf(b"/G1 gs " + RED + b"2 2 16 6 re f", resources=b"/ExtGState << /G1 << /Type /ExtGState >> >>"),
        "rendering-intent": pdf(b"/G1 gs " + RED + b"2 2 16 6 re f", resources=b"/ExtGState << /G1 << /RI /Perceptual >> >>"),
    },
    "state-changes": {
        "toggle-opm": pdf(b"q /M gs " + RED + b"1 1 4 4 re f Q q " + RED + b"7 1 4 4 re f Q q /M gs " + RED + b"13 1 4 4 re f Q", resources=b"/ExtGState << /A << /ca 0.5 >> /O << /op true >> /M << /OPM 1 >> /S << /SM 0.02 >> /Z << /OPM 0 >> >>"),
        "toggle-op": pdf(b"q /O gs " + RED + b"1 1 4 4 re f Q q " + RED + b"7 1 4 4 re f Q", resources=b"/ExtGState << /A << /ca 0.5 >> /O << /op true >> /M << /OPM 1 >> /S << /SM 0.02 >> /Z << /OPM 0 >> >>"),
        "toggle-sm": pdf(b"q /S gs " + RED + b"1 1 4 4 re f Q q " + RED + b"7 1 4 4 re f Q", resources=b"/ExtGState << /A << /ca 0.5 >> /O << /op true >> /M << /OPM 1 >> /S << /SM 0.02 >> /Z << /OPM 0 >> >>"),
        "toggle-ri": pdf(b"q /Perceptual ri " + RED + b"1 1 4 4 re f Q q " + RED + b"7 1 4 4 re f Q", resources=b"/ExtGState << /A << /ca 0.5 >> /O << /op true >> /M << /OPM 1 >> /S << /SM 0.02 >> /Z << /OPM 0 >> >>"),
        "all-four": pdf(b"/S gs /M gs /O gs /A gs " + RED + b"1 1 4 4 re f", resources=b"/ExtGState << /A << /ca 0.5 >> /O << /op true >> /M << /OPM 1 >> /S << /SM 0.02 >> /Z << /OPM 0 >> >>"),
        "ca-op": pdf(b"/O gs /A gs " + RED + b"1 1 4 4 re f", resources=b"/ExtGState << /A << /ca 0.5 >> /O << /op true >> /M << /OPM 1 >> /S << /SM 0.02 >> /Z << /OPM 0 >> >>"),
        "opm-off": pdf(b"/M gs " + RED + b"1 1 4 4 re f /Z gs 7 1 4 4 re f", resources=b"/ExtGState << /A << /ca 0.5 >> /O << /op true >> /M << /OPM 1 >> /S << /SM 0.02 >> /Z << /OPM 0 >> >>"),
    },
    "icc": {
        "srgb-like": icc_pdf(b"/Cs1 cs 1 0 0 sc 2 2 16 6 re f", [(SRGB_LIKE, 3)]),
        "p3": icc_pdf(b"/Cs1 cs 1 0 0 sc 2 2 16 6 re f", [(P3, 3)]),
        "gray22": icc_pdf(b"/Cs1 cs 0.5 sc 2 2 16 6 re f", [(GRAY22, 1)]),
        "gray18": icc_pdf(b"/Cs1 cs 0.5 sc 2 2 16 6 re f", [(GRAY18, 1)]),
        "uncompressed": icc_pdf(b"/Cs1 cs 1 0 0 sc 2 2 16 6 re f", [(P3, 3)], compress=False),
        "no-alternate": icc_pdf(b"/Cs1 cs 1 0 0 sc 2 2 16 6 re f", [(P3, 3)], alternate=False),
        "two-profiles": icc_pdf(b"/Cs1 cs 1 0 0 sc 2 2 6 6 re f /Cs2 cs 0.5 sc 10 2 6 6 re f", [(P3, 3), (GRAY22, 1)]),
        "two-names": icc_pdf(b"/A cs 1 0 0 sc 2 2 6 6 re f /B cs 0 0 1 sc 10 2 6 6 re f", [(P3, 3)], names=[(b"A", 0), (b"B", 0)]),
        "with-device": icc_pdf(b"/Cs1 cs 1 0 0 sc 2 2 6 6 re f 0 0 1 rg 10 2 6 6 re f", [(P3, 3)]),
        "scn": icc_pdf(b"/Cs1 cs 0.2 0.4 0.6 scn 2 2 16 6 re f", [(P3, 3)]),
        "unused": icc_pdf(b"1 0 0 rg 2 2 16 6 re f", [(P3, 3)]),
        "same-twice": icc_pdf(b"/Cs1 cs 1 0 0 sc 2 2 6 6 re f /Cs1 cs 0 0 1 sc 10 2 6 6 re f", [(P3, 3)]),
        "sc-only": icc_pdf(b"/Cs1 cs 1 0 0 sc 2 2 6 6 re f 0 0 1 sc 10 2 6 6 re f", [(P3, 3)]),
        "same-color-twice": icc_pdf(b"/Cs1 cs 1 0 0 sc 2 2 6 6 re f /Cs1 cs 1 0 0 sc 10 2 6 6 re f", [(P3, 3)]),
        "icc-device-icc": icc_pdf(b"/Cs1 cs 1 0 0 sc 2 2 4 4 re f 0 0 1 rg 8 2 4 4 re f /Cs1 cs 0 1 0 sc 14 2 4 4 re f", [(P3, 3)]),
        "copies": icc_pdf(b"/Cs1 cs 1 0 0 sc 2 2 6 6 re f /Cs2 cs 0 0 1 sc 10 2 6 6 re f", [(P3, 3), (P3, 3)]),
        "device-cs-twice": pdf(b"/DeviceRGB cs 1 0 0 sc 2 2 6 6 re f /DeviceRGB cs 0 0 1 sc 10 2 6 6 re f"),
        "device-sc-only": pdf(b"/DeviceRGB cs 1 0 0 sc 2 2 6 6 re f 0 0 1 sc 10 2 6 6 re f"),
        "rg-then-sc": pdf(b"1 0 0 rg 2 2 6 6 re f 0 0 1 sc 10 2 6 6 re f"),
        "gray-twice": pdf(b"0.5 g 2 2 6 6 re f 0.25 g 10 2 6 6 re f"),
    },
    "xobjects": {
        "form": objects_pdf(b"/X1 Do", [form(RED + b"2 2 16 6 re f")], b"/XObject << /X1 5 0 R >>"),
        "form-matrix": objects_pdf(b"/X1 Do", [form(RED + b"0 0 8 4 re f", extra=b" /Matrix [2 0 0 2 1 1]")], b"/XObject << /X1 5 0 R >>"),
        "form-cm": objects_pdf(b"q 1 0 0 1 3 2 cm /X1 Do Q", [form(RED + b"0 0 8 4 re f")], b"/XObject << /X1 5 0 R >>"),
        "form-bbox-clip": objects_pdf(b"/X1 Do", [form(RED + b"0 0 20 10 re f", bbox=b"2 2 10 6")], b"/XObject << /X1 5 0 R >>"),
        "form-twice": objects_pdf(b"/X1 Do q 1 0 0 1 10 0 cm /X1 Do Q", [form(RED + b"1 1 6 6 re f", bbox=b"0 0 10 10")], b"/XObject << /X1 5 0 R >>"),
        "form-color-inherit": objects_pdf(b"0 0 1 rg /X1 Do", [form(b"2 2 16 6 re f")], b"/XObject << /X1 5 0 R >>"),
        "form-resources": objects_pdf(b"/X1 Do", [form(b"/G1 gs " + RED + b"2 2 16 6 re f", extra=b" /Resources << /ExtGState << /G1 << /ca 0.5 >> >> >>")],
                                      b"/XObject << /X1 5 0 R >>"),
        "form-nested": objects_pdf(b"/X1 Do", [form(b"/X2 Do", extra=b" /Resources << /XObject << /X2 6 0 R >> >>"), form(RED + b"2 2 16 6 re f")],
                                   b"/XObject << /X1 5 0 R >>"),
        "form-after-fill": objects_pdf(b"0 0 1 rg 0 0 4 4 re f /X1 Do", [form(RED + b"6 2 12 6 re f")], b"/XObject << /X1 5 0 R >>"),
        "form-group": objects_pdf(b"/X1 Do", [form(RED + b"2 2 16 6 re f", extra=b" /Group << /S /Transparency >>")], b"/XObject << /X1 5 0 R >>"),
        "form-group-ca": objects_pdf(b"/G1 gs /X1 Do", [form(RED + b"2 2 8 6 re f 0 0 1 rg 6 2 8 6 re f", extra=b" /Group << /S /Transparency >>")],
                                     b"/XObject << /X1 5 0 R >> /ExtGState << /G1 << /ca 0.5 >> >>"),
        "form-in-clip": objects_pdf(b"q 0 0 10 10 re W n /X1 Do Q", [form(RED + b"2 2 16 6 re f")], b"/XObject << /X1 5 0 R >>"),
        "form-empty": objects_pdf(b"/X1 Do", [form(b"")], b"/XObject << /X1 5 0 R >>"),
    },
    "strokes": {
        "stroke": pdf(b"0 0 1 RG 2 w 3 3 m 17 7 l S"),
        "close-stroke": pdf(b"0 0 1 RG 2 w 3 3 m 17 3 l 10 8 l s"),
        "fill-stroke": pdf(RED + b"0 0 1 RG 2 w 3 3 14 4 re B"),
        "fill-stroke-even-odd": pdf(RED + b"0 0 1 RG 2 w 3 3 14 4 re 6 4 8 2 re B*"),
        "close-fill-stroke": pdf(RED + b"0 0 1 RG 2 w 3 3 m 17 3 l 10 8 l b"),
        "default-width": pdf(b"0 0 1 RG 3 3 m 17 7 l S"),
        "default-color": pdf(b"2 w 3 3 m 17 7 l S"),
        "gray-K": pdf(b"0.5 G 2 w 3 3 m 17 7 l S" + b" 0.1 0.2 0.3 0.4 K 3 7 m 17 3 l S"),
        "cs-SC": pdf(b"/DeviceRGB CS 0.2 0.4 0.6 SC 2 w 3 3 m 17 7 l S"),
        "caps-joins": pdf(b"0 0 1 RG 2 w 1 J 1 j 3 3 m 10 8 l 17 3 l S"),
        "cap-square-miter": pdf(b"0 0 1 RG 2 w 2 J 0 j 3 M 3 3 m 10 8 l 17 3 l S"),
        "join-bevel": pdf(b"0 0 1 RG 2 w 2 j 3 3 m 10 8 l 17 3 l S"),
        "dash": pdf(b"0 0 1 RG 1 w [2 1] 0 d 3 3 m 17 7 l S"),
        "dash-phase": pdf(b"0 0 1 RG 1 w [3 2 1] 1.5 d 3 3 m 17 7 l S"),
        "scaled": pdf(b"q 2 0 0 2 0 0 cm 0 0 1 RG 1 w 1 1 m 9 4 l S Q"),
        "translated": pdf(b"q 1 0 0 1 3 2 cm 0 0 1 RG 1 w 0 0 m 10 5 l S Q"),
        "rotated": pdf(b"q 0 1 -1 0 15 2 cm 0 0 1 RG 1 w 0 0 m 6 4 l S Q"),
        "two-strokes": pdf(b"0 0 1 RG 1 w 3 3 m 17 3 l S 2 w 3 7 m 17 7 l S"),
        "same-twice": pdf(b"0 0 1 RG 1 w 3 3 m 17 3 l S 3 7 m 17 7 l S"),
        "rect-stroke": pdf(b"0 0 1 RG 1 w 3 3 14 4 re S"),
        "stroke-then-fill": pdf(b"0 0 1 RG 1 w 3 3 m 17 3 l S " + RED + b"2 5 16 3 re f"),
        "zero-width": pdf(b"0 0 1 RG 0 w 3 3 m 17 7 l S"),
        "miter-default": pdf(b"0 0 1 RG 2 w 10 M 3 3 m 10 8 l 17 3 l S"),
        "stroke-alpha": pdf(b"/G1 gs 0 0 1 RG 2 w 3 3 m 17 7 l S", resources=b"/ExtGState << /G1 << /CA 0.5 >> >>"),
        "both-alphas": pdf(b"/G1 gs " + RED + b"0 0 1 RG 2 w 3 3 14 4 re B", resources=b"/ExtGState << /G1 << /CA 0.5 /ca 0.25 >> >>"),
        "stroke-overprint": pdf(b"/G1 gs 0 0 1 RG 2 w 3 3 m 17 7 l S", resources=b"/ExtGState << /G1 << /OP true >> >>"),
        "fill-stroke-scaled": pdf(b"q 2 0 0 2 0 0 cm " + RED + b"0 0 1 RG 1 w 1 1 7 3 re B Q"),
        "fill-scaled-then-stroke": pdf(b"q 2 0 0 2 0 0 cm " + RED + b"1 1 3 3 re f 0 0 1 RG 1 w 5 1 m 9 4 l S Q"),
        "two-scaled-strokes": pdf(b"q 2 0 0 2 0 0 cm 0 0 1 RG 1 w 1 1 m 9 1 l S 1 4 m 9 4 l S Q"),
        "scaled-strokes-two-groups": pdf(b"q 2 0 0 2 0 0 cm 0 0 1 RG 1 w 1 1 m 9 1 l S Q q 2 0 0 2 0 0 cm 0 0 1 RG 1 w 1 4 m 9 4 l S Q"),
        "stroke-in-clip": pdf(b"q 2 2 10 6 re W n 0 0 1 RG 2 w 0 0 m 20 10 l S Q"),
        "order-ri-sm-width": pdf(b"/Perceptual ri /G1 gs 2 w 0 0 1 RG 3 3 m 17 7 l S", resources=b"/ExtGState << /G1 << /SM 0.02 >> >>"),
        "explicit-overprints": pdf(b"/G1 gs 0 0 1 RG 2 w 3 3 m 17 7 l S", resources=b"/ExtGState << /G1 << /OP true /op false >> >>"),
        "fill-overprint-stroke": pdf(b"/G1 gs " + RED + b"0 0 1 RG 2 w 3 3 14 4 re B", resources=b"/ExtGState << /G1 << /op true >> >>"),
        "LW-gs": pdf(b"/G1 gs 0 0 1 RG 3 3 m 17 7 l S", resources=b"/ExtGState << /G1 << /LW 3 /LC 1 /LJ 1 /ML 4 /D [[2 1] 0] >> >>"),
    },
    "groups": {
        "content-smaller": objects_pdf(b"/X1 Do", [form(RED + b"4 3 6 2 re f", extra=b" /Group << /S /Transparency >>")], b"/XObject << /X1 5 0 R >>"),
        "content-larger": objects_pdf(b"/X1 Do", [form(RED + b"0 0 20 10 re f", bbox=b"2 2 10 6", extra=b" /Group << /S /Transparency >>")], b"/XObject << /X1 5 0 R >>"),
        "stroked": objects_pdf(b"/X1 Do", [form(b"0 0 1 RG 2 w 4 3 m 16 7 l S", extra=b" /Group << /S /Transparency >>")], b"/XObject << /X1 5 0 R >>"),
        "matrix": objects_pdf(b"/X1 Do", [form(RED + b"0 0 4 2 re f", extra=b" /Matrix [2 0 0 2 1 1] /Group << /S /Transparency >>")], b"/XObject << /X1 5 0 R >>"),
        "cm": objects_pdf(b"q 1 0 0 1 3 2 cm /X1 Do Q", [form(RED + b"0 0 4 2 re f", extra=b" /Group << /S /Transparency >>")], b"/XObject << /X1 5 0 R >>"),
        "isolated-knockout": objects_pdf(b"/X1 Do", [form(RED + b"2 2 16 6 re f", extra=b" /Group << /S /Transparency /I true /K true >>")], b"/XObject << /X1 5 0 R >>"),
        "group-cs": objects_pdf(b"/X1 Do", [form(RED + b"2 2 16 6 re f", extra=b" /Group << /S /Transparency /CS /DeviceRGB >>")], b"/XObject << /X1 5 0 R >>"),
        "twice": objects_pdf(b"/X1 Do q 1 0 0 1 10 0 cm /X1 Do Q", [form(RED + b"1 1 6 6 re f", bbox=b"0 0 10 10", extra=b" /Group << /S /Transparency >>")], b"/XObject << /X1 5 0 R >>"),
        "nested": objects_pdf(b"/X1 Do", [form(b"/X2 Do", extra=b" /Group << /S /Transparency >> /Resources << /XObject << /X2 6 0 R >> >>"), form(RED + b"2 2 16 6 re f", extra=b" /Group << /S /Transparency >>")], b"/XObject << /X1 5 0 R >>"),
        "in-clip": objects_pdf(b"q 0 0 10 10 re W n /X1 Do Q", [form(RED + b"2 2 16 6 re f", extra=b" /Group << /S /Transparency >>")], b"/XObject << /X1 5 0 R >>"),
        "after-fill": objects_pdf(b"0 0 1 rg 0 0 4 4 re f /X1 Do", [form(RED + b"6 2 12 6 re f", extra=b" /Group << /S /Transparency >>")], b"/XObject << /X1 5 0 R >>"),
        "empty": objects_pdf(b"/X1 Do", [form(b"", extra=b" /Group << /S /Transparency >>")], b"/XObject << /X1 5 0 R >>"),
        "smask-luminosity": objects_pdf(b"/G1 gs " + RED + b"0 0 20 10 re f", [form(b"1 g 4 2 12 6 re f", extra=b" /Group << /S /Transparency /CS /DeviceGray >>")], b"/ExtGState << /G1 << /SMask << /S /Luminosity /G 5 0 R >> >> >>"),
        "smask-alpha": objects_pdf(b"/G1 gs " + RED + b"0 0 20 10 re f", [form(b"0 g 4 2 12 6 re f", extra=b" /Group << /S /Transparency >>")], b"/ExtGState << /G1 << /SMask << /S /Alpha /G 5 0 R >> >> >>"),
        "blend-multiply": pdf(b"/G1 gs " + RED + b"2 2 16 6 re f", resources=b"/ExtGState << /G1 << /BM /Multiply >> >>"),
    },
    "entries": {
        "scale-1x": (pdf(RED + b"2 2 16 6 re f"), [{"idiom": "universal", "scale": "1x"}, {"idiom": "universal", "scale": "2x"},
                                                   {"idiom": "universal", "scale": "3x"}]),
        "scale-1x-only": (pdf(RED + b"2 2 16 6 re f"), [{"idiom": "universal", "scale": "1x"}]),
    },
    "shadings": {
        "axial-fn2": objects_pdf(b"/Sh1 sh", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                             b"<< /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >>"], b"/Shading << /Sh1 5 0 R >>"),
        "axial-noextend": objects_pdf(b"/Sh1 sh", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R >>",
                                                  b"<< /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >>"], b"/Shading << /Sh1 5 0 R >>"),
        "radial-fn2": objects_pdf(b"/Sh1 sh", [b"<< /ShadingType 3 /ColorSpace /DeviceRGB /Coords [10 5 0 10 5 6] /Function 6 0 R /Extend [true true] >>",
                                              b"<< /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >>"], b"/Shading << /Sh1 5 0 R >>"),
        "axial-fn3": objects_pdf(b"/Sh1 sh", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                             b"<< /FunctionType 3 /Domain [0 1] /Functions [7 0 R 8 0 R] /Bounds [0.3] /Encode [0 1 0 1] >>",
                                             b"<< /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 1 0] /N 1 >>",
                                             b"<< /FunctionType 2 /Domain [0 1] /C0 [0 1 0] /C1 [0 0 1] /N 1 >>"], b"/Shading << /Sh1 5 0 R >>"),
        "axial-fn4": objects_pdf(b"/Sh1 sh", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                             stream(b"{ dup 1 exch sub exch 0 exch }")[:-len(b"\nendstream")].replace(b"<< /Length", b"<< /FunctionType 4 /Domain [0 1] /Range [0 1 0 1 0 1] /Length") + b"\nendstream"],
                                 b"/Shading << /Sh1 5 0 R >>"),
        "axial-fn0": objects_pdf(b"/Sh1 sh", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                             b"<< /FunctionType 0 /Domain [0 1] /Range [0 1 0 1 0 1] /Size [2] /BitsPerSample 8 /Length 6 >>\nstream\n\xff\x00\x00\x00\x00\xff\nendstream"],
                                 b"/Shading << /Sh1 5 0 R >>"),
        "pattern-fill": objects_pdf(b"/Pattern cs /P1 scn 2 2 16 6 re f", [b"<< /PatternType 2 /Shading 6 0 R >>",
                                    b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 7 0 R /Extend [true true] >>",
                                    b"<< /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >>"], b"/Pattern << /P1 5 0 R >>"),
        "pattern-matrix": objects_pdf(b"/Pattern cs /P1 scn 2 2 16 6 re f", [b"<< /PatternType 2 /Shading 6 0 R /Matrix [1 0 0 1 2 0] >>",
                                      b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 16 0] /Function 7 0 R /Extend [true true] >>",
                                      b"<< /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >>"], b"/Pattern << /P1 5 0 R >>"),
        "sh-in-clip-cm": objects_pdf(b"q 2 2 16 6 re W n 1 0 0 1 1 0 cm /Sh1 sh Q", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                       b"<< /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >>"], b"/Shading << /Sh1 5 0 R >>"),
        "pattern-stroke": objects_pdf(b"/Pattern CS /P1 SCN 2 w 2 5 m 18 5 l S", [b"<< /PatternType 2 /Shading 6 0 R >>",
                                      b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 7 0 R /Extend [true true] >>",
                                      b"<< /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >>"], b"/Pattern << /P1 5 0 R >>"),
        "gray-sh": objects_pdf(b"/Sh1 sh", [b"<< /ShadingType 2 /ColorSpace /DeviceGray /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                        b"<< /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 1 >>"], b"/Shading << /Sh1 5 0 R >>"),
    },
    "opaque": {
        "gray-full": pdf(b"0.5 g 0 0 20 10 re f"),
        "rgb-full": pdf(RED + b"0 0 20 10 re f"),
        "rgb-gray-full": pdf(b"0.5 0.5 0.5 rg 0 0 20 10 re f"),
        "gray-part": pdf(b"0.5 g 0 0 10 10 re f"),
        "black-full": pdf(b"0 0 20 10 re f"),
    },
    "appearances": {
        "red-blue": (pdf(RED + b"2 2 16 6 re f"), [{"idiom": "universal"}, {"idiom": "universal", "appearances": [{"appearance": "luminosity", "value": "dark"}], "data": pdf(b"0 0 1 rg 2 2 16 6 re f")}]),
        "colors": (pdf(b"0.749 0.059 0.176 rg 1 1 4 4 re f 0.5 g 6 1 4 4 re f 0.2 0.4 0.6 rg 11 1 4 4 re f 0.3 0.6 0.9 RG 1 w 1 7 m 18 7 l S"),
                   [{"idiom": "universal"}, {"idiom": "universal", "appearances": [{"appearance": "luminosity", "value": "dark"}], "data": pdf(b"0.1 0.2 0.3 rg 2 2 16 6 re f")}]),
        "same-file": (pdf(RED + b"2 2 16 6 re f"), [{"idiom": "universal"}, {"idiom": "universal", "appearances": [{"appearance": "luminosity", "value": "dark"}], "data": pdf(RED + b"2 2 16 6 re f")}]),
        "any-dark-light": (pdf(RED + b"2 2 16 6 re f"), [{"idiom": "universal"}, {"idiom": "universal", "appearances": [{"appearance": "luminosity", "value": "dark"}], "data": pdf(b"0 0 1 rg 2 2 16 6 re f")},
                           {"idiom": "universal", "appearances": [{"appearance": "luminosity", "value": "light"}], "data": pdf(b"0 1 0 rg 2 2 16 6 re f")}]),
        "dark-only-file": (pdf(RED + b"2 2 16 6 re f"), [{"idiom": "universal", "appearances": [{"appearance": "luminosity", "value": "dark"}]}]),
    },
    "postscript": {
        "noops": objects_pdf(b"/Sh1 sh", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                    b"<< /FunctionType 4 /Domain [0 1] /Range [0 1 0 1 0 1] /Length %d >>\nstream\n" % len(b'{ 0 add 0 sub 1 mul 1 div 0.000000 add dup 2 mul exch pop 0 exch 1 exch }') + b'{ 0 add 0 sub 1 mul 1 div 0.000000 add dup 2 mul exch pop 0 exch 1 exch }' + b"\nendstream"],
                          b"/Shading << /Sh1 5 0 R >>"),
        "numbers": objects_pdf(b"/Sh1 sh", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                    b"<< /FunctionType 4 /Domain [0 1] /Range [0 1 0 1 0 1] /Length %d >>\nstream\n" % len(b'{ 0.500000 mul 1.000000 exch 0.1234567891 exch 2 exch }') + b'{ 0.500000 mul 1.000000 exch 0.1234567891 exch 2 exch }' + b"\nendstream"],
                          b"/Shading << /Sh1 5 0 R >>"),
        "spacing": objects_pdf(b"/Sh1 sh", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                    b"<< /FunctionType 4 /Domain [0 1] /Range [0 1 0 1 0 1] /Length %d >>\nstream\n" % len(b'{\n  dup\t1  exch   sub\nexch 0 exch }\n') + b'{\n  dup\t1  exch   sub\nexch 0 exch }\n' + b"\nendstream"],
                          b"/Shading << /Sh1 5 0 R >>"),
        "neg-zero": objects_pdf(b"/Sh1 sh", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                    b"<< /FunctionType 4 /Domain [0 1] /Range [0 1 0 1 0 1] /Length %d >>\nstream\n" % len(b'{ -0.000000 add 1 exch -0.5 add 0.5 exch }') + b'{ -0.000000 add 1 exch -0.5 add 0.5 exch }' + b"\nendstream"],
                          b"/Shading << /Sh1 5 0 R >>"),
        "nested": objects_pdf(b"/Sh1 sh", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                    b"<< /FunctionType 4 /Domain [0 1] /Range [0 1 0 1 0 1] /Length %d >>\nstream\n" % len(b'{ dup 0.5 gt { 1 sub 2 mul } { 2 mul } ifelse 0 exch 1 exch }') + b'{ dup 0.5 gt { 1 sub 2 mul } { 2 mul } ifelse 0 exch 1 exch }' + b"\nendstream"],
                          b"/Shading << /Sh1 5 0 R >>"),
        "ops": objects_pdf(b"/Sh1 sh", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                    b"<< /FunctionType 4 /Domain [0 1] /Range [0 1 0 1 0 1] /Length %d >>\nstream\n" % len(b'{ dup 0 add 1 exch 0.5 mul 0 sub 1 mul 0 exch }') + b'{ dup 0 add 1 exch 0.5 mul 0 sub 1 mul 0 exch }' + b"\nendstream"],
                          b"/Shading << /Sh1 5 0 R >>"),
        "integers": objects_pdf(b"/Sh1 sh", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                    b"<< /FunctionType 4 /Domain [0 1] /Range [0 1 0 1 0 1] /Length %d >>\nstream\n" % len(b'{ 1 exch 0 exch 2 div }') + b'{ 1 exch 0 exch 2 div }' + b"\nendstream"],
                          b"/Shading << /Sh1 5 0 R >>"),
    },
    "fonts": {
        "unnamed": truetype_pdf(RED + b"BT /F1 8 Tf 2 2 Td (A) Tj ET", truetype_font(SQUARES)),
        "named": truetype_pdf(RED + b"BT /F1 8 Tf 2 2 Td (A) Tj ET", truetype_font(SQUARES, "SquareSans-Bold")),
        "named-os2": truetype_pdf(RED + b"BT /F1 8 Tf 2 2 Td (A) Tj ET", truetype_font(SQUARES, "SquareSans-Bold", (700, 500))),
        "three": truetype_pdf(RED + b"BT /F1 6 Tf 1 2 Td (CAB) Tj ET", truetype_font(SQUARES, "SquareSans-Bold")),
        "twice": truetype_pdf(RED + b"BT /F1 6 Tf 1 2 Td (A) Tj 0 0 1 rg (BA) Tj ET", truetype_font(SQUARES, "SquareSans-Bold")),
        "two-runs": truetype_pdf(RED + b"BT /F1 6 Tf 1 2 Td (A) Tj ET BT /F1 4 Tf 10 2 Td (B) Tj ET", truetype_font(SQUARES, "SquareSans-Bold")),
        "tj": truetype_pdf(RED + b"BT /F1 4 Tf 1 2 Td [(A) -500 (B)] TJ ET", truetype_font(SQUARES, "SquareSans-Bold")),
        "matrix": truetype_pdf(RED + b"q 1 0 0 1 2 1 cm BT 2 0 0 2 1 1 Tm /F1 3 Tf (AB) Tj ET Q", truetype_font(SQUARES, "SquareSans-Bold")),
        "spacing": truetype_pdf(RED + b"BT /F1 4 Tf 1 Tc 50 Tz 1 2 Td (AB) Tj ET", truetype_font(SQUARES, "SquareSans-Bold")),
        "stroke-mode": truetype_pdf(RED + b"0 0 1 RG BT 1 Tr /F1 8 Tf 2 2 Td (A) Tj ET", truetype_font(SQUARES, "SquareSans-Bold")),
        "invisible": truetype_pdf(RED + b"BT 3 Tr /F1 8 Tf 2 2 Td (A) Tj ET 1 1 2 2 re f", truetype_font(SQUARES, "SquareSans-Bold")),
        "ascent-800": truetype_pdf(RED + b"BT /F1 8 Tf 2 2 Td (A) Tj ET", truetype_font(SQUARES, "SquareSans-Bold", ascent=800, descent=-200)),
        "uneven": truetype_pdf(RED + b"BT /F1 4 Tf 1 2 Td [(A) -500 (B) -200 (C)] TJ ET", truetype_font(SQUARES, "SquareSans-Bold")),
        "word-spacing": truetype_pdf(RED + b"BT /F1 2 Tf 3 Tw 1 2 Td (A A) Tj ET", truetype_font(dict(SQUARES, **{" ": [[(0, 0), (0, 1), (1, 1), (1, 0)]]}),
                                     "SquareSans-Bold"), first=32, widths=(1000,) + (0,) * 32 + (1000, 1000, 1000)),
        "two-fonts": objects_pdf(RED + b"BT /F1 4 Tf 1 2 Td (A) Tj /F2 4 Tf (B) Tj ET", [
            b"<< /Type /Font /Subtype /TrueType /BaseFont /Square /FirstChar 65 /LastChar 67 /Widths [1000 1000 1000] /FontDescriptor 6 0 R "
            b"/Encoding /WinAnsiEncoding >>",
            b"<< /Type /FontDescriptor /FontName /Square /Flags 32 /FontBBox [0 0 1000 1000] /ItalicAngle 0 /Ascent 1000 /Descent 0 "
            b"/CapHeight 700 /StemV 80 /FontFile2 7 0 R >>",
            (lambda f: b"<< /Length %d >>\nstream\n" % len(f) + f + b"\nendstream")(truetype_font(SQUARES, "SquareSans-Bold")),
            b"<< /Type /Font /Subtype /TrueType /BaseFont /Other /FirstChar 65 /LastChar 67 /Widths [1000 1000 1000] /FontDescriptor 9 0 R "
            b"/Encoding /WinAnsiEncoding >>",
            b"<< /Type /FontDescriptor /FontName /Other /Flags 32 /FontBBox [0 0 1000 1000] /ItalicAngle 0 /Ascent 1000 /Descent 0 "
            b"/CapHeight 700 /StemV 80 /FontFile2 10 0 R >>",
            (lambda f: b"<< /Length %d >>\nstream\n" % len(f) + f + b"\nendstream")(truetype_font(SQUARES, "SquareSerif-Regular"))],
            b"/Font << /F1 5 0 R /F2 8 0 R >>"),
        "widths": truetype_pdf(RED + b"BT /F1 4 Tf 1 2 Td (AB) Tj ET", truetype_font(SQUARES, "SquareSans-Bold"), widths=(600, 800, 1000)),
    },
    "fonts-2": {
        "macroman": truetype_pdf(RED + b"BT /F1 8 Tf 2 2 Td (A) Tj ET", truetype_font(SQUARES, "SquareSans-Bold"), encoding=b"/MacRomanEncoding"),
        "macroman-mac-cmap": truetype_pdf(RED + b"BT /F1 6 Tf 1 2 Td (BA) Tj ET", truetype_font(SQUARES, "SquareSans-Bold", mac_cmap=True),
                                          encoding=b"/MacRomanEncoding"),
        "winansi-mac-cmap": truetype_pdf(RED + b"BT /F1 6 Tf 1 2 Td (BA) Tj ET", truetype_font(SQUARES, "SquareSans-Bold", mac_cmap=True)),
        "none-mac-cmap": truetype_pdf(RED + b"BT /F1 6 Tf 1 2 Td (BA) Tj ET", truetype_font(SQUARES, "SquareSans-Bold", mac_cmap=True),
                                      encoding=None, flags=4),
        "none": truetype_pdf(RED + b"BT /F1 6 Tf 1 2 Td (BA) Tj ET", truetype_font(SQUARES, "SquareSans-Bold"), encoding=None, flags=4),
        "tagged": truetype_pdf(RED + b"BT /F1 6 Tf 1 2 Td (BA) Tj ET", truetype_font(SQUARES, "AAAAAB+Square", mac_cmap=True),
                               encoding=b"/MacRomanEncoding", name=b"AAAAAB+Square"),
        "tounicode": objects_pdf(RED + b"BT /F1 6 Tf 1 2 Td (BA) Tj ET", [
            b"<< /Type /Font /Subtype /TrueType /BaseFont /Square /FirstChar 65 /LastChar 67 /Widths [1000 1000 1000] /FontDescriptor 6 0 R "
            b"/Encoding /MacRomanEncoding /ToUnicode 8 0 R >>",
            b"<< /Type /FontDescriptor /FontName /Square /Flags 32 /FontBBox [0 0 1000 1000] /ItalicAngle 0 /Ascent 1000 /Descent 0 "
            b"/CapHeight 700 /StemV 80 /FontFile2 7 0 R >>",
            (lambda f: b"<< /Length %d >>\nstream\n" % len(f) + f + b"\nendstream")(truetype_font(SQUARES, "SquareSans-Bold", mac_cmap=True)),
            stream(b"/CIDInit /ProcSet findresource begin 12 dict begin begincmap /CMapName /X def 1 begincodespacerange <00> <FF> "
                   b"endcodespacerange 2 beginbfchar <41> <0058> <42> <0059> endbfchar endcmap CMapName currentdict /CMap defineresource pop "
                   b"end end")],
            b"/Font << /F1 5 0 R >>"),
        "system-name": truetype_pdf(RED + b"BT /F1 6 Tf 1 2 Td (BA) Tj ET", truetype_font(SQUARES, "Helvetica", mac_cmap=True),
                                    encoding=b"/MacRomanEncoding", name=b"AAAAAB+Helvetica"),
        "system-name-winansi": truetype_pdf(RED + b"BT /F1 6 Tf 1 2 Td (BA) Tj ET", truetype_font(SQUARES, "Helvetica"), name=b"Helvetica"),
        "system-name-only-pdf": truetype_pdf(RED + b"BT /F1 6 Tf 1 2 Td (BA) Tj ET", truetype_font(SQUARES, "SquareSans-Bold", mac_cmap=True),
                                             encoding=b"/MacRomanEncoding", name=b"AAAAAB+Helvetica"),
    },
    "fonts-3": {
        "named-macroman": truetype_pdf(RED + b"BT /F1 6 Tf 1 2 Td (BA) Tj ET", truetype_font(SQUARES, "SquareSans-Bold", names=NAMES),
                                       encoding=b"/MacRomanEncoding"),
        "named-winansi": truetype_pdf(RED + b"BT /F1 6 Tf 1 2 Td (BA) Tj ET", truetype_font(SQUARES, "SquareSans-Bold", names=NAMES)),
        "named-none": truetype_pdf(RED + b"BT /F1 6 Tf 1 2 Td (BA) Tj ET", truetype_font(SQUARES, "SquareSans-Bold", mac_cmap=True, names=NAMES),
                                   encoding=None, flags=4),
        "named-gap": truetype_pdf(RED + b"BT /F1 6 Tf 1 2 Td (CA) Tj ET", truetype_font(SQUARES, "SquareSans-Bold", names=NAMES),
                                  encoding=b"/MacRomanEncoding", widths=(600, 800, 900)),
        "named-tj": truetype_pdf(RED + b"BT /F1 4 Tf 1 2 Td [(A) -500 (B) -200 (C)] TJ ET", truetype_font(SQUARES, "SquareSans-Bold", names=NAMES),
                                 encoding=b"/MacRomanEncoding"),
        "named-euro": truetype_pdf(RED + b"BT /F1 6 Tf 1 2 Td (\200) Tj ET", truetype_font({"\u20ac": SQUARES["A"]}, "SquareSans-Bold",
                                                                                          names={"\u20ac": "Euro"}), first=128, widths=(1000,)),
        "named-odd": truetype_pdf(RED + b"BT /F1 6 Tf 1 2 Td (BA) Tj ET", truetype_font(SQUARES, "SquareSans-Bold",
                                                                                        names={"A": "square", "B": "bar", "C": "triangle"}),
                                  encoding=b"/MacRomanEncoding"),
        "named-and-unnamed": objects_pdf(RED + b"BT /F1 4 Tf 1 2 Td (A) Tj /F2 4 Tf (B) Tj /F1 4 Tf (B) Tj ET", [
            b"<< /Type /Font /Subtype /TrueType /BaseFont /Square /FirstChar 65 /LastChar 67 /Widths [1000 1000 1000] /FontDescriptor 6 0 R "
            b"/Encoding /MacRomanEncoding >>",
            b"<< /Type /FontDescriptor /FontName /Square /Flags 32 /FontBBox [0 0 1000 1000] /ItalicAngle 0 /Ascent 1000 /Descent 0 "
            b"/CapHeight 700 /StemV 80 /FontFile2 7 0 R >>",
            (lambda f: b"<< /Length %d >>\nstream\n" % len(f) + f + b"\nendstream")(truetype_font(SQUARES, "SquareSans-Bold", names=NAMES)),
            b"<< /Type /Font /Subtype /TrueType /BaseFont /Other /FirstChar 65 /LastChar 67 /Widths [1000 1000 1000] /FontDescriptor 9 0 R "
            b"/Encoding /MacRomanEncoding >>",
            b"<< /Type /FontDescriptor /FontName /Other /Flags 32 /FontBBox [0 0 1000 1000] /ItalicAngle 0 /Ascent 1000 /Descent 0 "
            b"/CapHeight 700 /StemV 80 /FontFile2 10 0 R >>",
            (lambda f: b"<< /Length %d >>\nstream\n" % len(f) + f + b"\nendstream")(truetype_font(SQUARES, "SquareSerif-Regular"))],
            b"/Font << /F1 5 0 R /F2 8 0 R >>"),
    },
    "fonts-4": {
        # Which glyph names Quartz writes with MacRomanEncoding, and at which codes.
        "mac-names": truetype_pdf(RED + b"BT /F1 1 Tf 0 2 Td (%s) Tj ET" % bytes(range(68, 68 + len(MAC_NAMES))),
                                  truetype_font({chr(68 + i): SQUARES["A"] for i in range(len(MAC_NAMES))}, "SquareSans-Bold",
                                                names={chr(68 + i): n for i, n in enumerate(MAC_NAMES)}),
                                  first=68, widths=(1000,) * len(MAC_NAMES)),
        # Which glyph names outside MacRomanEncoding give their Unicode value in ToUnicode.
        "other-names": truetype_pdf(RED + b"BT /F1 1 Tf 0 2 Td (%s) Tj ET" % bytes(range(68, 68 + len(OTHER_NAMES))),
                                    truetype_font({chr(68 + i): SQUARES["A"] for i in range(len(OTHER_NAMES))}, "SquareSans-Bold",
                                                  names={chr(68 + i): n for i, n in enumerate(OTHER_NAMES)}),
                                    first=68, widths=(1000,) * len(OTHER_NAMES)),
    },
    "fonts-5": {
        # Where the descriptor's cap and x heights come from: glyphs of different heights.
        "heights": truetype_pdf(RED + b"BT /F1 1 Tf 0 2 Td (A) Tj ET", truetype_font(HEIGHTS, "SquareSans-Bold")),
        "heights-os2": truetype_pdf(RED + b"BT /F1 1 Tf 0 2 Td (A) Tj ET", truetype_font(HEIGHTS, "SquareSans-Bold", (700, 500))),
        "heights-no-h": truetype_pdf(RED + b"BT /F1 1 Tf 0 2 Td (A) Tj ET",
                                     truetype_font({k: v for k, v in HEIGHTS.items() if k not in "Hx"}, "SquareSans-Bold")),
        "heights-no-hi": truetype_pdf(RED + b"BT /F1 1 Tf 0 2 Td (A) Tj ET",
                                      truetype_font({k: v for k, v in HEIGHTS.items() if k not in "HIxv"}, "SquareSans-Bold")),
    },
    "cff": {
        "basic": cff_pdf(RED + b"BT /F1 6 Tf 1 2 Td (BA) Tj ET", cff_font(SQUARES)),
        "bbox": cff_pdf(RED + b"BT /F1 6 Tf 1 2 Td (BA) Tj ET", cff_font(SQUARES, bbox=(-100, -200, 900, 800))),
        "descriptor": cff_pdf(RED + b"BT /F1 6 Tf 1 2 Td (BA) Tj ET", cff_font(SQUARES), descriptor=b" /StemH 40 /AvgWidth 500 /MaxWidth 1200 /XHeight 400"),
        "units-2048": cff_pdf(RED + b"BT /F1 6 Tf 1 2 Td (BA) Tj ET",
                              cff_font({c: [[(2 * x, 2 * y) for x, y in contour] for contour in v] for c, v in SQUARES.items()},
                                       bbox=(-201, -403, 2049, 2050), units=2048)),
        "odd-names": cff_pdf(RED + b"BT /F1 6 Tf 1 2 Td (BA) Tj ET", cff_font(SQUARES, names={"A": "square", "B": "bar", "C": "triangle"})),
        "winansi": cff_pdf(RED + b"BT /F1 6 Tf 1 2 Td (BA) Tj ET", cff_font(SQUARES), encoding=b"/WinAnsiEncoding"),
        "tj": cff_pdf(RED + b"BT /F1 4 Tf 1 2 Td [(A) -500 (B) -200 (C)] TJ ET", cff_font(SQUARES)),
        "widths": cff_pdf(RED + b"BT /F1 4 Tf 1 2 Td (AB) Tj ET", cff_font(SQUARES, widths={"A": 600, "B": 800}), widths=(500, 800, 1000)),
        "symbolic": cff_pdf(RED + b"BT /F1 6 Tf 1 2 Td (BA) Tj ET", cff_font(SQUARES), flags=4),
    },
    "cff-2": {
        "private": cff_pdf(RED + b"BT /F1 6 Tf 1 2 Td (BA) Tj ET", cff_font(SQUARES, private=((10, 30), (11, 60)))),
        "default-width": cff_pdf(RED + b"BT /F1 6 Tf 1 2 Td (BA) Tj ET", cff_font(SQUARES, private=((10, 30), (11, 60))).replace(
            cff_number(0, True) + bytes([20]), cff_number(500, True) + bytes([20]))),
        "differences": cff_pdf(RED + b"BT /F1 6 Tf 1 2 Td (BA) Tj ET", cff_font(SQUARES, names={"A": "square", "B": "bar", "C": "triangle"}),
                               encoding=b"<< /Type /Encoding /Differences [65 /square /bar /triangle] >>"),
        "differences-mac": cff_pdf(RED + b"BT /F1 6 Tf 1 2 Td (BA) Tj ET", cff_font(SQUARES), encoding=b"<< /Differences [65 /B /A] >>"),
        "units-500": cff_pdf(RED + b"BT /F1 6 Tf 1 2 Td (BA) Tj ET",
                             cff_font({c: [[(x // 2, y // 2) for x, y in contour] for contour in v] for c, v in SQUARES.items()},
                                      bbox=(0, 0, 500, 500), units=500)),
        "heights": cff_pdf(RED + b"BT /F1 1 Tf 0 2 Td (A) Tj ET", cff_font(HEIGHTS)),
    },
    "cff-3": {
        # How much Quartz grows a CFF font's box, by units per em.
        "units-16": cff_pdf(RED + b"BT /F1 6 Tf 1 2 Td (A) Tj ET", cff_font({"A": [[(0, 0), (0, 16), (16, 16), (16, 0)]]}, bbox=(0, 0, 16, 16),
                                                                                units=16)),
        "units-100": cff_pdf(RED + b"BT /F1 6 Tf 1 2 Td (A) Tj ET", cff_font({"A": [[(0, 0), (0, 100), (100, 100), (100, 0)]]}, bbox=(0, 0, 100, 100),
                                                                                units=100)),
        "units-250": cff_pdf(RED + b"BT /F1 6 Tf 1 2 Td (A) Tj ET", cff_font({"A": [[(0, 0), (0, 250), (250, 250), (250, 0)]]}, bbox=(0, 0, 250, 250),
                                                                                units=250)),
        "units-256": cff_pdf(RED + b"BT /F1 6 Tf 1 2 Td (A) Tj ET", cff_font({"A": [[(0, 0), (0, 256), (256, 256), (256, 0)]]}, bbox=(0, 0, 256, 256),
                                                                                units=256)),
        "units-512": cff_pdf(RED + b"BT /F1 6 Tf 1 2 Td (A) Tj ET", cff_font({"A": [[(0, 0), (0, 512), (512, 512), (512, 0)]]}, bbox=(0, 0, 512, 512),
                                                                                units=512)),
        "units-1024": cff_pdf(RED + b"BT /F1 6 Tf 1 2 Td (A) Tj ET", cff_font({"A": [[(0, 0), (0, 1024), (1024, 1024), (1024, 0)]]}, bbox=(0, 0, 1024, 1024),
                                                                                units=1024)),
        "units-2000": cff_pdf(RED + b"BT /F1 6 Tf 1 2 Td (A) Tj ET", cff_font({"A": [[(0, 0), (0, 2000), (2000, 2000), (2000, 0)]]}, bbox=(0, 0, 2000, 2000),
                                                                                units=2000)),
        "units-4096": cff_pdf(RED + b"BT /F1 6 Tf 1 2 Td (A) Tj ET", cff_font({"A": [[(0, 0), (0, 4096), (4096, 4096), (4096, 0)]]}, bbox=(0, 0, 4096, 4096),
                                                                                units=4096)),
    },
    "fonts-6": {
        # When Quartz writes the space between glyphs as Tc, TJ numbers or neither, and resets Tc.
        "zero-then-tiny": truetype_pdf(RED + b"BT 4 0 0 4 1 2 Tm /F1 1 Tf [(AB) -0.1 (C)] TJ ET", truetype_font(SQUARES, "SquareSans-Bold")),
        "tiny-then-zero": truetype_pdf(RED + b"BT 4 0 0 4 1 2 Tm /F1 1 Tf [(A) -0.1 (BC)] TJ ET", truetype_font(SQUARES, "SquareSans-Bold")),
        "big-then-small": truetype_pdf(RED + b"BT 4 0 0 4 1 2 Tm /F1 1 Tf [(A) -0.4 (B) -0.1 (C)] TJ ET", truetype_font(SQUARES, "SquareSans-Bold")),
        "scaled-1": truetype_pdf(RED + b"BT 4 0 0 4 1 2 Tm /F1 1 Tf [(A) -1 (B) -4 (C)] TJ ET", truetype_font(SQUARES, "SquareSans-Bold")),
        "scaled-10": truetype_pdf(RED + b"BT 4 0 0 4 1 2 Tm /F1 1 Tf [(A) -10 (B) -40 (C)] TJ ET", truetype_font(SQUARES, "SquareSans-Bold")),
        "scaled-100": truetype_pdf(RED + b"BT 4 0 0 4 1 2 Tm /F1 1 Tf [(A) -100 (B) -400 (C)] TJ ET", truetype_font(SQUARES, "SquareSans-Bold")),
        "tiny-then-big": truetype_pdf(RED + b"BT 4 0 0 4 1 2 Tm /F1 1 Tf [(A) -0.1 (B) -10 (C)] TJ ET", truetype_font(SQUARES, "SquareSans-Bold")),
        "half": truetype_pdf(RED + b"BT 4 0 0 4 1 2 Tm /F1 1 Tf [(A) -0.5 (B) -1 (C)] TJ ET", truetype_font(SQUARES, "SquareSans-Bold")),
        "three-gaps": truetype_pdf(RED + b"BT 4 0 0 4 1 2 Tm /F1 1 Tf [(A) -500 (B) -200 (C) -200 (A)] TJ ET", truetype_font(SQUARES, "SquareSans-Bold")),
        "three-gaps-2": truetype_pdf(RED + b"BT 4 0 0 4 1 2 Tm /F1 1 Tf [(A) -200 (B) -500 (C) -500 (A)] TJ ET", truetype_font(SQUARES, "SquareSans-Bold")),
        "tiny-tc": truetype_pdf(RED + b"BT 4 0 0 4 1 2 Tm /F1 1 Tf 0.0002 Tc (AB) Tj ET", truetype_font(SQUARES, "SquareSans-Bold")),
        "tiny-tc-3": truetype_pdf(RED + b"BT 4 0 0 4 1 2 Tm /F1 1 Tf 0.0002 Tc (ABC) Tj ET", truetype_font(SQUARES, "SquareSans-Bold")),
        "large-tc": truetype_pdf(RED + b"BT 4 0 0 4 1 2 Tm /F1 1 Tf 0.5 Tc (AB) Tj ET", truetype_font(SQUARES, "SquareSans-Bold")),
        "medium-tc": truetype_pdf(RED + b"BT 4 0 0 4 1 2 Tm /F1 1 Tf 0.01 Tc (AB) Tj ET", truetype_font(SQUARES, "SquareSans-Bold")),
        "tiny-tj": truetype_pdf(RED + b"BT 4 0 0 4 1 2 Tm /F1 1 Tf [(A) -0.1 (B) -0.4 (C)] TJ ET", truetype_font(SQUARES, "SquareSans-Bold")),
        "tiny-tj-2": truetype_pdf(RED + b"BT 4 0 0 4 1 2 Tm /F1 1 Tf [(A) -0.1 (B)] TJ ET", truetype_font(SQUARES, "SquareSans-Bold")),
        "large-tj": truetype_pdf(RED + b"BT 4 0 0 4 1 2 Tm /F1 1 Tf [(A) -500 (B)] TJ ET", truetype_font(SQUARES, "SquareSans-Bold")),
        "tc-and-tj": truetype_pdf(RED + b"BT 4 0 0 4 1 2 Tm /F1 1 Tf 0.0005 Tc [(A) 1 (B)] TJ ET", truetype_font(SQUARES, "SquareSans-Bold")),
        "tc-and-large-tj": truetype_pdf(RED + b"BT 4 0 0 4 1 2 Tm /F1 1 Tf 0.5 Tc [(A) 100 (B)] TJ ET", truetype_font(SQUARES, "SquareSans-Bold")),
        "medium-tj": truetype_pdf(RED + b"BT 4 0 0 4 1 2 Tm /F1 1 Tf [(A) -10 (B)] TJ ET", truetype_font(SQUARES, "SquareSans-Bold")),
        "tj-1": truetype_pdf(RED + b"BT 4 0 0 4 1 2 Tm /F1 1 Tf [(A) -1 (B)] TJ ET", truetype_font(SQUARES, "SquareSans-Bold")),
        "tj-1-first-zero": truetype_pdf(RED + b"BT 4 0 0 4 1 2 Tm /F1 1 Tf [(AB) -1 (C)] TJ ET", truetype_font(SQUARES, "SquareSans-Bold")),
        "tj-mixed": truetype_pdf(RED + b"BT 4 0 0 4 1 2 Tm /F1 1 Tf [(A) -500 (B) (C)] TJ ET", truetype_font(SQUARES, "SquareSans-Bold")),
    },
    "smasks": {
        "fill": objects_pdf(b"/G1 gs " + RED + b"0 0 20 10 re f", [form(b"0 0 0 rg 4 2 12 6 re f", extra=GROUP + b"")], b"/ExtGState << /G1 << /SMask << /S /Alpha /G 5 0 R >> >> >>"),
        "group-do": objects_pdf(b"/G1 gs /X1 Do", [form(b"0 0 0 rg 4 2 12 6 re f", extra=GROUP), form(RED + b"0 0 20 10 re f", extra=GROUP)],
                                b"/ExtGState << /G1 << /SMask << /S /Alpha /G 5 0 R >> >> >> /XObject << /X1 6 0 R >>"),
        "mask-red": objects_pdf(b"/G1 gs " + RED + b"0 0 20 10 re f", [form(b"1 0 0 rg 4 2 12 6 re f", extra=GROUP + b"")], b"/ExtGState << /G1 << /SMask << /S /Alpha /G 5 0 R >> >> >>"),
        "two-fills": objects_pdf(b"/G1 gs " + RED + b"0 0 8 10 re f 0 0 1 rg 10 0 10 10 re f", [form(b"0 0 0 rg 4 2 12 6 re f", extra=GROUP + b"")], b"/ExtGState << /G1 << /SMask << /S /Alpha /G 5 0 R >> >> >>"),
        "reset": objects_pdf(b"/G1 gs " + RED + b"0 0 8 10 re f /G2 gs 10 0 10 10 re f", [form(b"0 0 0 rg 4 2 12 6 re f", extra=GROUP + b"")], b"/ExtGState << /G1 << /SMask << /S /Alpha /G 5 0 R >> >> /G2 << /SMask /None >> >>"),
        "in-q": objects_pdf(b"q /G1 gs " + RED + b"0 0 8 10 re f Q 10 0 10 10 re f", [form(b"0 0 0 rg 4 2 12 6 re f", extra=GROUP + b"")], b"/ExtGState << /G1 << /SMask << /S /Alpha /G 5 0 R >> >> >>"),
        "mask-bbox": objects_pdf(b"/G1 gs " + RED + b"0 0 20 10 re f", [form(b"0 0 0 rg 4 2 12 6 re f", bbox=b"0 0 10 10", extra=GROUP)], b"/ExtGState << /G1 << /SMask << /S /Alpha /G 5 0 R >> >> >>"),
        "mask-matrix": objects_pdf(b"/G1 gs " + RED + b"0 0 20 10 re f", [form(b"0 0 0 rg 4 2 12 6 re f", extra=GROUP + b" /Matrix [1 0 0 1 2 0]")], b"/ExtGState << /G1 << /SMask << /S /Alpha /G 5 0 R >> >> >>"),
        "mask-ca": objects_pdf(b"/G1 gs " + RED + b"0 0 20 10 re f", [form(b"/A1 gs 0 0 0 rg 4 2 12 6 re f", extra=GROUP + b" /Resources << /ExtGState << /A1 << /ca 0.5 >> >> >>")], b"/ExtGState << /G1 << /SMask << /S /Alpha /G 5 0 R >> >> >>"),
        "under-cm": objects_pdf(b"q 1 0 0 1 2 0 cm /G1 gs " + RED + b"0 0 16 10 re f Q", [form(b"0 0 0 rg 4 2 12 6 re f", extra=GROUP + b"")], b"/ExtGState << /G1 << /SMask << /S /Alpha /G 5 0 R >> >> >>"),
        "stroke": objects_pdf(b"/G1 gs 0 0 1 RG 2 w 1 5 m 19 5 l S", [form(b"0 0 0 rg 4 2 12 6 re f", extra=GROUP + b"")], b"/ExtGState << /G1 << /SMask << /S /Alpha /G 5 0 R >> >> >>"),
        "no-group": objects_pdf(b"/G1 gs " + RED + b"0 0 20 10 re f", [form(b"0 0 0 rg 4 2 12 6 re f")], b"/ExtGState << /G1 << /SMask << /S /Alpha /G 5 0 R >> >> >>"),
        "after-fill": objects_pdf(b"0 0 1 rg 0 0 3 3 re f /G1 gs " + RED + b"4 0 16 10 re f", [form(b"0 0 0 rg 4 2 12 6 re f", extra=GROUP + b"")], b"/ExtGState << /G1 << /SMask << /S /Alpha /G 5 0 R >> >> >>"),
    },
    "shadings-2": {
        # What an ExtGState set before sh carries: overprinting, its mode, opacity, smoothness.
        "opm": objects_pdf(b"/G1 gs /Sh1 sh", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                  b"<< /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >>"], b"/Shading << /Sh1 5 0 R >> /ExtGState << /G1 << /OPM 1 >> >>"),
        "op": objects_pdf(b"/G1 gs /Sh1 sh", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                  b"<< /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >>"], b"/Shading << /Sh1 5 0 R >> /ExtGState << /G1 << /op true >> >>"),
        "op-opm": objects_pdf(b"/G1 gs /Sh1 sh", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                  b"<< /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >>"], b"/Shading << /Sh1 5 0 R >> /ExtGState << /G1 << /op true /OPM 1 >> >>"),
        "opm-ca": objects_pdf(b"/G1 gs /Sh1 sh", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                  b"<< /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >>"], b"/Shading << /Sh1 5 0 R >> /ExtGState << /G1 << /OPM 1 /ca 0.5 >> >>"),
        "opm-sm": objects_pdf(b"/G1 gs /Sh1 sh", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                  b"<< /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >>"], b"/Shading << /Sh1 5 0 R >> /ExtGState << /G1 << /OPM 1 /SM 0.5 >> >>"),
        "opm-off": objects_pdf(b"/G1 gs /Sh1 sh", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                  b"<< /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >>"], b"/Shading << /Sh1 5 0 R >> /ExtGState << /G1 << /OPM 0 >> >>"),
        "big-op": objects_pdf(b"/G1 gs /Sh1 sh", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                  b"<< /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >>"], b"/Shading << /Sh1 5 0 R >> /ExtGState << /G1 << /OP true >> >>"),
        "opm-then-fill": objects_pdf(b"/G1 gs /Sh1 sh 1 0 0 rg 0 0 2 2 re f", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                  b"<< /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >>"], b"/Shading << /Sh1 5 0 R >> /ExtGState << /G1 << /OPM 1 >> >>"),
    },
    "postscript-2": {
        # How Quartz writes a PostScript function's numbers again, and which constants it folds.
        "large": objects_pdf(b"/Sh1 sh", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                    b"<< /FunctionType 4 /Domain [0 1] /Range [0 1 0 1 0 1] /Length %d >>\nstream\n" % len(b'{ 123.4567891 mul 12345678.5 add 0.0000004 add 0.0000006 add 1 exch 0 exch }') + b'{ 123.4567891 mul 12345678.5 add 0.0000004 add 0.0000006 add 1 exch 0 exch }' + b"\nendstream"],
                          b"/Shading << /Sh1 5 0 R >>"),
        "fold-add": objects_pdf(b"/Sh1 sh", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                    b"<< /FunctionType 4 /Domain [0 1] /Range [0 1 0 1 0 1] /Length %d >>\nstream\n" % len(b'{ pop 0 1 add 0 0.5 add 2 1 add }') + b'{ pop 0 1 add 0 0.5 add 2 1 add }' + b"\nendstream"],
                          b"/Shading << /Sh1 5 0 R >>"),
        "fold-other": objects_pdf(b"/Sh1 sh", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                    b"<< /FunctionType 4 /Domain [0 1] /Range [0 1 0 1 0 1] /Length %d >>\nstream\n" % len(b'{ pop 0 1 sub 0 2 mul 1 0 add }') + b'{ pop 0 1 sub 0 2 mul 1 0 add }' + b"\nendstream"],
                          b"/Shading << /Sh1 5 0 R >>"),
        "fold-input": objects_pdf(b"/Sh1 sh", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                    b"<< /FunctionType 4 /Domain [0 1] /Range [0 1 0 1 0 1] /Length %d >>\nstream\n" % len(b'{ 0 exch add 1 exch 0 1 add exch }') + b'{ 0 exch add 1 exch 0 1 add exch }' + b"\nendstream"],
                          b"/Shading << /Sh1 5 0 R >>"),
        "decimals": objects_pdf(b"/Sh1 sh", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                    b"<< /FunctionType 4 /Domain [0 1] /Range [0 1 0 1 0 1] /Length %d >>\nstream\n" % len(b'{ pop 1.25 0.1234565 0.1234575 }') + b'{ pop 1.25 0.1234565 0.1234575 }' + b"\nendstream"],
                          b"/Shading << /Sh1 5 0 R >>"),
        "zero-mul": objects_pdf(b"/Sh1 sh", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                    b"<< /FunctionType 4 /Domain [0 1] /Range [0 1 0 1 0 1] /Length %d >>\nstream\n" % len(b'{ 0 mul 1 add 0 exch 0 exch }') + b'{ 0 mul 1 add 0 exch 0 exch }' + b"\nendstream"],
                          b"/Shading << /Sh1 5 0 R >>"),
        "dup-zero-mul": objects_pdf(b"/Sh1 sh", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                    b"<< /FunctionType 4 /Domain [0 1] /Range [0 1 0 1 0 1] /Length %d >>\nstream\n" % len(b'{ dup 0 mul pop 1 exch 0 exch }') + b'{ dup 0 mul pop 1 exch 0 exch }' + b"\nendstream"],
                          b"/Shading << /Sh1 5 0 R >>"),
        "dup-pop": objects_pdf(b"/Sh1 sh", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                    b"<< /FunctionType 4 /Domain [0 1] /Range [0 1 0 1 0 1] /Length %d >>\nstream\n" % len(b'{ dup pop 1 exch 0 exch }') + b'{ dup pop 1 exch 0 exch }' + b"\nendstream"],
                          b"/Shading << /Sh1 5 0 R >>"),
        "mul-zero-mul": objects_pdf(b"/Sh1 sh", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                    b"<< /FunctionType 4 /Domain [0 1] /Range [0 1 0 1 0 1] /Length %d >>\nstream\n" % len(b'{ 2 mul 0 mul 0.5 add 0 exch 0 exch }') + b'{ 2 mul 0 mul 0.5 add 0 exch 0 exch }' + b"\nendstream"],
                          b"/Shading << /Sh1 5 0 R >>"),
        "zero-mul-sub": objects_pdf(b"/Sh1 sh", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                    b"<< /FunctionType 4 /Domain [0 1] /Range [0 1 0 1 0 1] /Length %d >>\nstream\n" % len(b'{ 0.17 sub 0 mul 1 add 0 exch 0 exch }') + b'{ 0.17 sub 0 mul 1 add 0 exch 0 exch }' + b"\nendstream"],
                          b"/Shading << /Sh1 5 0 R >>"),
        "exponents": objects_pdf(b"/Sh1 sh", [b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function 6 0 R /Extend [true true] >>",
                                    b"<< /FunctionType 4 /Domain [0 1] /Range [0 1 0 1 0 1] /Length %d >>\nstream\n" % len(b'{ pop 1000000.25 0.000000 99.9999996 }') + b'{ pop 1000000.25 0.000000 99.9999996 }' + b"\nendstream"],
                          b"/Shading << /Sh1 5 0 R >>"),
    },
    "images-2": {
        # What an image is drawn with besides its matrix: the rendering intent, overprinting.
        "ri": objects_pdf(b'/Perceptual ri q 16 0 0 8 2 1 cm /Im1 Do Q', [image(RGB4, 2, 2)], b"/XObject << /Im1 5 0 R >> /ExtGState << /G1 << /ca 0.5 >> /G2 << /OPM 1 /op true >> >>"),
        "ri-ca": objects_pdf(b'/Perceptual ri /G1 gs q 16 0 0 8 2 1 cm /Im1 Do Q', [image(RGB4, 2, 2)], b"/XObject << /Im1 5 0 R >> /ExtGState << /G1 << /ca 0.5 >> /G2 << /OPM 1 /op true >> >>"),
        "ri-twice": objects_pdf(b'/Perceptual ri q 16 0 0 8 2 1 cm /Im1 Do Q q 8 0 0 4 2 1 cm /Im1 Do Q', [image(RGB4, 2, 2)], b"/XObject << /Im1 5 0 R >> /ExtGState << /G1 << /ca 0.5 >> /G2 << /OPM 1 /op true >> >>"),
        "ri-then-fill": objects_pdf(b'/Saturation ri q 16 0 0 8 2 1 cm /Im1 Do Q 1 0 0 rg 0 0 2 2 re f', [image(RGB4, 2, 2)], b"/XObject << /Im1 5 0 R >> /ExtGState << /G1 << /ca 0.5 >> /G2 << /OPM 1 /op true >> >>"),
        "intent-entry": objects_pdf(b'q 16 0 0 8 2 1 cm /Im1 Do Q', [image(RGB4, 2, 2, extra=b" /Intent /Perceptual")], b"/XObject << /Im1 5 0 R >> /ExtGState << /G1 << /ca 0.5 >> /G2 << /OPM 1 /op true >> >>"),
        "opm": objects_pdf(b'/G2 gs q 16 0 0 8 2 1 cm /Im1 Do Q', [image(RGB4, 2, 2)], b"/XObject << /Im1 5 0 R >> /ExtGState << /G1 << /ca 0.5 >> /G2 << /OPM 1 /op true >> >>"),
    },
    "groups-4": {
        # What a transparency group is drawn with besides its opacity: overprinting, its mode, a stroke opacity.
        "opm": objects_pdf(b"/G1 gs /X1 Do", [form(RED + b"2 2 16 6 re f", extra=GROUP)], b"/XObject << /X1 5 0 R >> /ExtGState << /G1 << /OPM 1 >> >>"),
        "op": objects_pdf(b"/G1 gs /X1 Do", [form(RED + b"2 2 16 6 re f", extra=GROUP)], b"/XObject << /X1 5 0 R >> /ExtGState << /G1 << /op true >> >>"),
        "op-opm": objects_pdf(b"/G1 gs /X1 Do", [form(RED + b"2 2 16 6 re f", extra=GROUP)], b"/XObject << /X1 5 0 R >> /ExtGState << /G1 << /op true /OPM 1 >> >>"),
        "ca-opm": objects_pdf(b"/G1 gs /X1 Do", [form(RED + b"2 2 16 6 re f", extra=GROUP)], b"/XObject << /X1 5 0 R >> /ExtGState << /G1 << /ca 0.5 /OPM 1 >> >>"),
        "stroke-ca": objects_pdf(b"/G1 gs /X1 Do", [form(RED + b"2 2 16 6 re f", extra=GROUP)], b"/XObject << /X1 5 0 R >> /ExtGState << /G1 << /CA 0.5 >> >>"),
        "stroke-op": objects_pdf(b"/G1 gs /X1 Do", [form(RED + b"2 2 16 6 re f", extra=GROUP)], b"/XObject << /X1 5 0 R >> /ExtGState << /G1 << /OP true >> >>"),
        "stroke-ca-fill-ca": objects_pdf(b"/G1 gs /X1 Do", [form(RED + b"2 2 16 6 re f", extra=GROUP)], b"/XObject << /X1 5 0 R >> /ExtGState << /G1 << /CA 0.5 /ca 0.25 >> >>"),
        "stroke-op-false": objects_pdf(b"/G1 gs /X1 Do", [form(RED + b"2 2 16 6 re f", extra=GROUP)], b"/XObject << /X1 5 0 R >> /ExtGState << /G1 << /OP true /op false >> >>"),
        "stroke-ca-stroke": objects_pdf(b"/G1 gs /X1 Do", [form(b"0 0 1 RG 2 w 2 5 m 18 5 l S", extra=GROUP)], b"/XObject << /X1 5 0 R >> /ExtGState << /G1 << /CA 0.5 >> >>"),
        "opm-then-fill": objects_pdf(b"/G1 gs /X1 Do 0 0 1 rg 0 0 2 2 re f", [form(RED + b"2 2 16 6 re f", extra=GROUP)], b"/XObject << /X1 5 0 R >> /ExtGState << /G1 << /OPM 1 >> >>"),
    },
    "groups-5": {
        # Where a group's patterns and shadings go among the ExtGStates of the page and the group.
        "plain": objects_pdf(b"/G1 gs /X1 Do", [form(b'/G2 gs 1 0 0 rg 2 2 16 6 re f', extra=GROUP + b' /Resources << /ExtGState << /G2 << /ca 0.25 >> >>  >>')], b"/XObject << /X1 5 0 R >> /ExtGState << /G1 << /ca 0.5 >> >>"),
        "pattern": objects_pdf(b"/G1 gs /X1 Do", [form(b'/Pattern cs /P1 scn /G2 gs 2 2 16 6 re f', extra=GROUP + b' /Resources << /ExtGState << /G2 << /ca 0.25 >> >> /Pattern << /P1 << /Type /Pattern /PatternType 2 /Shading << /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >> /Extend [true true] >> >> >> >>')], b"/XObject << /X1 5 0 R >> /ExtGState << /G1 << /ca 0.5 >> >>"),
        "pattern-before-gs": objects_pdf(b"/G1 gs /X1 Do", [form(b'/G2 gs /Pattern cs /P1 scn 2 2 16 6 re f', extra=GROUP + b' /Resources << /ExtGState << /G2 << /ca 0.25 >> >> /Pattern << /P1 << /Type /Pattern /PatternType 2 /Shading << /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >> /Extend [true true] >> >> >> >>')], b"/XObject << /X1 5 0 R >> /ExtGState << /G1 << /ca 0.5 >> >>"),
        "shading": objects_pdf(b"/G1 gs /X1 Do", [form(b'/G2 gs /Sh1 sh', extra=GROUP + b' /Resources << /ExtGState << /G2 << /ca 0.25 >> >> /Shading << /Sh1 << /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >> /Extend [true true] >> >> >>')], b"/XObject << /X1 5 0 R >> /ExtGState << /G1 << /ca 0.5 >> >>"),
    },
    "groups-6": {
        # The rendering intent Quartz writes inside a group: shadings, images, fills.
        "sh-plain-group": objects_pdf(b'/X1 Do', [form(b'/Sh1 sh', extra=b' /Group << /S /Transparency >> /Resources << /Shading << /Sh1 << /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >> /Extend [true true] >> >> >>')], b"/XObject << /X1 5 0 R >>"),
        "sh-no-group": objects_pdf(b'/X1 Do', [form(b'/Sh1 sh', extra=b' /Resources << /Shading << /Sh1 << /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >> /Extend [true true] >> >> >>')], b"/XObject << /X1 5 0 R >>"),
        "sh-ri-set": objects_pdf(b'/X1 Do', [form(b'/RelativeColorimetric ri /Sh1 sh', extra=b' /Group << /S /Transparency >> /Resources << /Shading << /Sh1 << /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >> /Extend [true true] >> >> >>')], b"/XObject << /X1 5 0 R >>"),
        "sh-page-ri": objects_pdf(b'/Saturation ri /X1 Do', [form(b'/Sh1 sh', extra=b' /Group << /S /Transparency >> /Resources << /Shading << /Sh1 << /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >> /Extend [true true] >> >> >>')], b"/XObject << /X1 5 0 R >>"),
        "fill-then-sh": objects_pdf(b'/X1 Do', [form(b'1 0 0 rg 0 0 2 2 re f /Sh1 sh', extra=b' /Group << /S /Transparency >> /Resources << /Shading << /Sh1 << /ShadingType 2 /ColorSpace /DeviceRGB /Coords [2 0 18 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >> /Extend [true true] >> >> >>')], b"/XObject << /X1 5 0 R >>"),
        "image-in-group": objects_pdf(b'/X1 Do', [form(b'q 16 0 0 8 2 1 cm /Im1 Do Q', extra=b' /Group << /S /Transparency >> /Resources << /XObject << /Im1 6 0 R >> >>'), image(RGB4, 2, 2)], b"/XObject << /X1 5 0 R >>"),
    },
    "strokes-2": {
        # Stroke adjustment (SA): which drawings write it, and where among their settings.
        "sa-stroke": objects_pdf(b'/G1 gs 0 0 1 RG 2 w 1 5 m 19 5 l S', [], b"/ExtGState << /G1 << /SA true >> >>"),
        "sa-false-stroke": objects_pdf(b'/G1 gs 0 0 1 RG 2 w 1 5 m 19 5 l S', [], b"/ExtGState << /G1 << /SA false >> >>"),
        "sa-fill": objects_pdf(b'/G1 gs 1 0 0 rg 2 2 16 6 re f', [], b"/ExtGState << /G1 << /SA true >> >>"),
        "sa-sm": objects_pdf(b'/G1 gs 0 0 1 RG 2 w 1 5 m 19 5 l S', [], b"/ExtGState << /G1 << /SA true /SM 0.5 >> >>"),
        "sa-ca": objects_pdf(b'/G1 gs 0 0 1 RG 2 w 1 5 m 19 5 l S', [], b"/ExtGState << /G1 << /SA true /CA 0.5 >> >>"),
        "sa-then-fill": objects_pdf(b'/G1 gs 0 0 1 RG 2 w 1 5 m 19 5 l S 1 0 0 rg 2 2 4 4 re f', [], b"/ExtGState << /G1 << /SA true >> >>"),
        "sa-fill-stroke": objects_pdf(b'/G1 gs 0 0 1 RG 1 0 0 rg 2 w 2 2 16 6 re B', [], b"/ExtGState << /G1 << /SA true >> >>"),
        "sa-ri": objects_pdf(b'/G1 gs /Perceptual ri 0 0 1 RG 2 w 1 5 m 19 5 l S', [], b"/ExtGState << /G1 << /SA true >> >>"),
    },
    "smasks-3": {
        # Transfer functions Quartz may keep (PostScript, sampled) and luminosity groups in ICC spaces.
        "alpha-tr-postscript": objects_pdf(b"/G1 gs " + RED + b"0 0 20 10 re f", [form(b"0 g 4 2 12 6 re f", extra=GROUP), stream(b"{ 1 exch sub }")[:2]
                                           + b" /FunctionType 4 /Domain [0 1] /Range [0 1]" + stream(b"{ 1 exch sub }")[2:]],
                                           b"/ExtGState << /G1 << /SMask << /S /Alpha /G 5 0 R /TR 6 0 R >> >> >>"),
        "lum-tr-postscript": objects_pdf(b"/G1 gs " + RED + b"0 0 20 10 re f",
                                         [form(b"0.5 g 4 2 12 6 re f", extra=b" /Group << /S /Transparency /CS /DeviceGray >>"),
                                          stream(b"{ 1 exch sub }")[:2] + b" /FunctionType 4 /Domain [0 1] /Range [0 1]" + stream(b"{ 1 exch sub }")[2:]],
                                         b"/ExtGState << /G1 << /SMask << /S /Luminosity /G 5 0 R /TR 6 0 R >> >> >>"),
        "alpha-tr-sampled": objects_pdf(b"/G1 gs " + RED + b"0 0 20 10 re f", [form(b"0 g 4 2 12 6 re f", extra=GROUP),
                                        b"<< /FunctionType 0 /Domain [0 1] /Range [0 1] /Size [2] /BitsPerSample 8 /Length 2 >>\nstream\n\xff\x00\nendstream"],
                                        b"/ExtGState << /G1 << /SMask << /S /Alpha /G 5 0 R /TR 6 0 R >> >> >>"),
        "lum-icc-gray": objects_pdf(b"/G1 gs " + RED + b"0 0 20 10 re f",
                                    [form(b"0.5 g 4 2 12 6 re f", extra=b" /Group << /S /Transparency /CS [/ICCBased 6 0 R] >>"),
                                     b"<< /N 1 /Alternate /DeviceGray /Length %d >>\nstream\n" % len(GRAY22) + GRAY22 + b"\nendstream"],
                                    b"/ExtGState << /G1 << /SMask << /S /Luminosity /G 5 0 R >> >> >>"),
        "lum-icc-gray-ref": objects_pdf(b"/G1 gs " + RED + b"0 0 20 10 re f",
                                        [form(b"0.5 g 4 2 12 6 re f", extra=b" /Group << /S /Transparency /CS 7 0 R >>"),
                                         b"<< /N 1 /Alternate /DeviceGray /Length %d >>\nstream\n" % len(GRAY22) + GRAY22 + b"\nendstream",
                                         b"[/ICCBased 6 0 R]"],
                                        b"/ExtGState << /G1 << /SMask << /S /Luminosity /G 5 0 R >> >> >>"),
        "lum-icc-gray-own": objects_pdf(b"/G1 gs " + RED + b"0 0 20 10 re f",
                                        [form(b"/C0 cs 0.5 sc 4 2 12 6 re f", extra=b" /Group << /S /Transparency /CS 7 0 R >> /Resources << /ColorSpace << /C0 7 0 R >> >>"),
                                         b"<< /N 1 /Alternate /DeviceGray /Length %d >>\nstream\n" % len(GRAY22) + GRAY22 + b"\nendstream",
                                         b"[/ICCBased 6 0 R]"],
                                        b"/ExtGState << /G1 << /SMask << /S /Luminosity /G 5 0 R >> >> >>"),
        "lum-icc-rgb-gray": objects_pdf(b"/G1 gs " + RED + b"0 0 20 10 re f",
                                        [form(b"0.5 g 4 2 12 6 re f", extra=b" /Group << /S /Transparency /CS [/ICCBased 6 0 R] >>"),
                                         b"<< /N 3 /Alternate /DeviceRGB /Length %d >>\nstream\n" % len(P3) + P3 + b"\nendstream"],
                                        b"/ExtGState << /G1 << /SMask << /S /Luminosity /G 5 0 R >> >> >>"),
        "lum-rgb-gray": objects_pdf(b"/G1 gs " + RED + b"0 0 20 10 re f",
                                    [form(b"0.5 g 4 2 12 6 re f", extra=b" /Group << /S /Transparency /CS /DeviceRGB >>")],
                                    b"/ExtGState << /G1 << /SMask << /S /Luminosity /G 5 0 R >> >> >>"),
        "lum-gray-rgb": objects_pdf(b"/G1 gs " + RED + b"0 0 20 10 re f",
                                    [form(b"0 0 1 rg 4 2 12 6 re f 0.5 g 0 0 2 2 re f", extra=b" /Group << /S /Transparency /CS /DeviceGray >>")],
                                    b"/ExtGState << /G1 << /SMask << /S /Luminosity /G 5 0 R >> >> >>"),
        "lum-icc-rgb": objects_pdf(b"/G1 gs " + RED + b"0 0 20 10 re f",
                                   [form(b"0 0 1 rg 4 2 12 6 re f", extra=b" /Group << /S /Transparency /CS [/ICCBased 6 0 R] >>"),
                                    b"<< /N 3 /Alternate /DeviceRGB /Length %d >>\nstream\n" % len(P3) + P3 + b"\nendstream"],
                                   b"/ExtGState << /G1 << /SMask << /S /Luminosity /G 5 0 R >> >> >>"),
    },
    "smasks-2": {
        # Luminosity soft masks: gray, RGB and unnamed group spaces, backdrops, transfer functions.
        "gray": objects_pdf(b'/G1 gs 1 0 0 rg 0 0 20 10 re f', [form(b'0.5 g 4 2 12 6 re f', extra=b' /Group << /S /Transparency /CS /DeviceGray >>')], b'/ExtGState << /G1 << /SMask << /S /Luminosity /G 5 0 R >> >> /G2 << /SMask /None >> >>'),
        "white-black": objects_pdf(b'/G1 gs 1 0 0 rg 0 0 20 10 re f', [form(b'1 g 0 0 10 10 re f 0 g 10 0 10 10 re f', extra=b' /Group << /S /Transparency /CS /DeviceGray >>')], b'/ExtGState << /G1 << /SMask << /S /Luminosity /G 5 0 R >> >> /G2 << /SMask /None >> >>'),
        "rgb": objects_pdf(b'/G1 gs 1 0 0 rg 0 0 20 10 re f', [form(b'1 0 0 rg 4 2 12 6 re f', extra=b' /Group << /S /Transparency /CS /DeviceRGB >>')], b'/ExtGState << /G1 << /SMask << /S /Luminosity /G 5 0 R >> >> /G2 << /SMask /None >> >>'),
        "no-cs": objects_pdf(b'/G1 gs 1 0 0 rg 0 0 20 10 re f', [form(b'0.5 g 4 2 12 6 re f', extra=b' /Group << /S /Transparency >>')], b'/ExtGState << /G1 << /SMask << /S /Luminosity /G 5 0 R >> >> /G2 << /SMask /None >> >>'),
        "bc": objects_pdf(b'/G1 gs 1 0 0 rg 0 0 20 10 re f', [form(b'0.5 g 4 2 12 6 re f', extra=b' /Group << /S /Transparency /CS /DeviceGray >>')], b'/ExtGState << /G1 << /SMask << /S /Luminosity /G 5 0 R /BC [0.5] >> >> /G2 << /SMask /None >> >>'),
        "bc-rgb": objects_pdf(b'/G1 gs 1 0 0 rg 0 0 20 10 re f', [form(b'0 0 1 rg 4 2 12 6 re f', extra=b' /Group << /S /Transparency /CS /DeviceRGB >>')], b'/ExtGState << /G1 << /SMask << /S /Luminosity /G 5 0 R /BC [1 0 0] >> >> /G2 << /SMask /None >> >>'),
        "tr-identity": objects_pdf(b'/G1 gs 1 0 0 rg 0 0 20 10 re f', [form(b'0.5 g 4 2 12 6 re f', extra=b' /Group << /S /Transparency /CS /DeviceGray >>')], b'/ExtGState << /G1 << /SMask << /S /Luminosity /G 5 0 R /TR /Identity >> >> /G2 << /SMask /None >> >>'),
        "tr-function": objects_pdf(b'/G1 gs 1 0 0 rg 0 0 20 10 re f', [form(b'0.5 g 4 2 12 6 re f', extra=b' /Group << /S /Transparency /CS /DeviceGray >>'), b'<< /FunctionType 2 /Domain [0 1] /C0 [1] /C1 [0] /N 1 >>'], b'/ExtGState << /G1 << /SMask << /S /Luminosity /G 5 0 R /TR 6 0 R >> >> /G2 << /SMask /None >> >>'),
        "alpha-tr": objects_pdf(b'/G1 gs 1 0 0 rg 0 0 20 10 re f', [form(b'0 g 4 2 12 6 re f', extra=b' /Group << /S /Transparency /CS /DeviceGray >>'), b'<< /FunctionType 2 /Domain [0 1] /C0 [1] /C1 [0] /N 1 >>'], b'/ExtGState << /G1 << /SMask << /S /Alpha /G 5 0 R /TR 6 0 R >> >> /G2 << /SMask /None >> >>'),
        "matrix": objects_pdf(b'/G1 gs 1 0 0 rg 0 0 20 10 re f', [form(b'0.5 g 4 2 12 6 re f', extra=b' /Group << /S /Transparency /CS /DeviceGray >> /Matrix [1 0 0 1 2 0]')], b'/ExtGState << /G1 << /SMask << /S /Luminosity /G 5 0 R >> >> /G2 << /SMask /None >> >>'),
        "reset": objects_pdf(b'/G1 gs 1 0 0 rg 0 0 8 10 re f /G2 gs 10 0 10 10 re f', [form(b'0.5 g 4 2 12 6 re f', extra=b' /Group << /S /Transparency /CS /DeviceGray >>')], b'/ExtGState << /G1 << /SMask << /S /Luminosity /G 5 0 R >> >> /G2 << /SMask /None >> >>'),
        "shading": objects_pdf(b'/G1 gs 1 0 0 rg 0 0 20 10 re f', [form(b'/Sh1 sh', extra=b' /Group << /S /Transparency /CS /DeviceGray >> /Resources << /Shading << /Sh1 << /ShadingType 2 /ColorSpace /DeviceGray /Coords [0 0 20 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 1 >> /Extend [true true] >> >> >>')], b'/ExtGState << /G1 << /SMask << /S /Luminosity /G 5 0 R >> >> /G2 << /SMask /None >> >>'),
        "stroke": objects_pdf(b'/G1 gs 0 0 1 RG 2 w 1 5 m 19 5 l S', [form(b'0.5 g 4 2 12 6 re f', extra=b' /Group << /S /Transparency /CS /DeviceGray >>')], b'/ExtGState << /G1 << /SMask << /S /Luminosity /G 5 0 R >> >> /G2 << /SMask /None >> >>'),
        "group-do": objects_pdf(b'/G1 gs /X1 Do', [form(b'0.5 g 4 2 12 6 re f', extra=b' /Group << /S /Transparency /CS /DeviceGray >>'), form(RED + b"0 0 20 10 re f", extra=GROUP)], b'/ExtGState << /G1 << /SMask << /S /Luminosity /G 5 0 R >> >> /G2 << /SMask /None >> >> /XObject << /X1 6 0 R >>'),
    },
    "images": {
        "rgb-flate": objects_pdf(b"q 16 0 0 8 2 1 cm /Im1 Do Q", [image(RGB4, 2, 2)], b"/XObject << /Im1 5 0 R >>"),
        "rgb-raw": objects_pdf(b"q 16 0 0 8 2 1 cm /Im1 Do Q", [image(RGB4, 2, 2, compress=False)], b"/XObject << /Im1 5 0 R >>"),
        "gray-flate": objects_pdf(b"q 16 0 0 8 2 1 cm /Im1 Do Q", [image(GRAY4, 2, 2, b"/DeviceGray")], b"/XObject << /Im1 5 0 R >>"),
        "rgb-smask": objects_pdf(b"q 16 0 0 8 2 1 cm /Im1 Do Q", [image(RGB4, 2, 2, extra=b" /SMask 6 0 R"), image(GRAY4, 2, 2, b"/DeviceGray")], b"/XObject << /Im1 5 0 R >>"),
        "jpeg-gray": objects_pdf(b"q 16 0 0 8 2 1 cm /Im1 Do Q", [image(b"\xff\xd8" + ae.jpeg_file(16, 8), 16, 8, b"/DeviceGray", extra=b" /Filter /DCTDecode")], b"/XObject << /Im1 5 0 R >>"),
        "jpeg-icc": objects_pdf(b"q 16 0 0 8 2 1 cm /Im1 Do Q", [image(b"\xff\xd8" + ae.jpeg_file(16, 8), 16, 8, b"[/ICCBased 6 0 R]", extra=b" /Filter /DCTDecode"),
                                                             b"<< /N 1 /Alternate /DeviceGray /Length %d >>\nstream\n" % len(GRAY22) + GRAY22 + b"\nendstream"],
                              b"/XObject << /Im1 5 0 R >>"),
        "jpeg-smask": objects_pdf(b"q 16 0 0 8 2 1 cm /Im1 Do Q", [image(b"\xff\xd8" + ae.jpeg_file(16, 8), 16, 8, b"/DeviceGray", extra=b" /Filter /DCTDecode /SMask 6 0 R"),
                                                               image(bytes(range(0, 256, 2)), 16, 8, b"/DeviceGray")], b"/XObject << /Im1 5 0 R >>"),
        "interpolate": objects_pdf(b"q 16 0 0 8 2 1 cm /Im1 Do Q", [image(RGB4, 2, 2, extra=b" /Interpolate true")], b"/XObject << /Im1 5 0 R >>"),
        "icc": objects_pdf(b"q 16 0 0 8 2 1 cm /Im1 Do Q", [image(RGB4, 2, 2, b"[/ICCBased 6 0 R]"),
                                   b"<< /N 3 /Alternate /DeviceRGB /Length %d >>\nstream\n" % len(P3) + P3 + b"\nendstream"], b"/XObject << /Im1 5 0 R >>"),
        "rotated": objects_pdf(b"q 0 8 -16 0 18 1 cm /Im1 Do Q", [image(RGB4, 2, 2)], b"/XObject << /Im1 5 0 R >>"),
        "twice": objects_pdf(b"q 8 0 0 8 1 1 cm /Im1 Do Q q 8 0 0 8 11 1 cm /Im1 Do Q", [image(RGB4, 2, 2)], b"/XObject << /Im1 5 0 R >>"),
        "stencil": objects_pdf(b"0 0 1 rg " + b"q 16 0 0 8 2 1 cm /Im1 Do Q", [image(bytes([0x40, 0x80]), 2, 2, None, 1, b" /ImageMask true")], b"/XObject << /Im1 5 0 R >>"),
        "decode": objects_pdf(b"q 16 0 0 8 2 1 cm /Im1 Do Q", [image(RGB4, 2, 2, extra=b" /Decode [1 0 1 0 1 0]")], b"/XObject << /Im1 5 0 R >>"),
        "gray-1bit": objects_pdf(b"q 16 0 0 8 2 1 cm /Im1 Do Q", [image(bytes([0x40, 0x80]), 2, 2, b"/DeviceGray", 1)], b"/XObject << /Im1 5 0 R >>"),
        "with-fill": objects_pdf(RED + b"0 0 2 2 re f " + b"q 16 0 0 8 2 1 cm /Im1 Do Q", [image(RGB4, 2, 2)], b"/XObject << /Im1 5 0 R >>"),
        "in-clip": objects_pdf(b"q 0 0 10 10 re W n " + b"q 16 0 0 8 2 1 cm /Im1 Do Q" + b" Q", [image(RGB4, 2, 2)], b"/XObject << /Im1 5 0 R >>"),
        "alpha": objects_pdf(b"/G1 gs " + b"q 16 0 0 8 2 1 cm /Im1 Do Q", [image(RGB4, 2, 2)], b"/XObject << /Im1 5 0 R >>" + b" " + GS),
        "in-group": objects_pdf(b"/X1 Do", [form(b"q 12 0 0 6 3 2 cm /Im1 Do Q", extra=GROUP + b" /Resources << /XObject << /Im1 6 0 R >> >>"),
                                             image(RGB4, 2, 2)], b"/XObject << /X1 5 0 R >>"),
    },
    "text": {
        "type3-empty": objects_pdf(RED + b"2 2 6 6 re f BT /F1 10 Tf 10 2 Td (\\000) Tj ET",
                                   [stream(b"1 0 0 0 1 1 d1"),
                                    b"<< /Type /Font /Subtype /Type3 /FontBBox [0 0 1 1] /FontMatrix [1 0 0 1 0 0] /CharProcs << /C0 5 0 R >> "
                                    b"/Encoding << /Type /Encoding /Differences [0 /C0] >> /FirstChar 0 /LastChar 0 /Widths [1] >>"],
                                   b"/Font << /F1 6 0 R >>"),
        "type3-drawn": objects_pdf(RED + b"BT /F1 6 Tf 10 2 Td (\\000) Tj ET",
                                   [stream(b"1 0 d0 0 0 1 1 re f"),
                                    b"<< /Type /Font /Subtype /Type3 /FontBBox [0 0 1 1] /FontMatrix [1 0 0 1 0 0] /CharProcs << /C0 5 0 R >> "
                                    b"/Encoding << /Type /Encoding /Differences [0 /C0] >> /FirstChar 0 /LastChar 0 /Widths [1] >>"],
                                   b"/Font << /F1 6 0 R >>"),
        "type3-tj": objects_pdf(RED + b"BT /F1 4 Tf 2 2 Td [(\\000) -500 (\\000)] TJ ET", [stream(b"1 0 d0 0 0 1 1 re f"),
            b"<< /Type /Font /Subtype /Type3 /FontBBox [0 0 1 1] /FontMatrix [1 0 0 1 0 0] /CharProcs << /C0 5 0 R >> "
            b"/Encoding << /Type /Encoding /Differences [0 /C0 32 /C0] >> /FirstChar 0 /LastChar 32 /Widths [1" + b" 0" * 31 + b" 1] >>"], b"/Font << /F1 6 0 R >>"),
        "type3-tc-tw-tz": objects_pdf(RED + b"BT /F1 2 Tf 1 Tc 3 Tw 50 Tz 2 2 Td (\\000\\040\\000) Tj ET", [stream(b"1 0 d0 0 0 1 1 re f"),
            b"<< /Type /Font /Subtype /Type3 /FontBBox [0 0 1 1] /FontMatrix [1 0 0 1 0 0] /CharProcs << /C0 5 0 R >> "
            b"/Encoding << /Type /Encoding /Differences [0 /C0 32 /C0] >> /FirstChar 0 /LastChar 32 /Widths [1" + b" 0" * 31 + b" 1] >>"], b"/Font << /F1 6 0 R >>"),
        "type3-tm-cm": objects_pdf(RED + b"q 1 0 0 1 2 0 cm BT 2 0 0 2 3 1 Tm /F1 2 Tf (\\000\\000) Tj ET Q", [stream(b"1 0 d0 0 0 1 1 re f"),
            b"<< /Type /Font /Subtype /Type3 /FontBBox [0 0 1 1] /FontMatrix [1 0 0 1 0 0] /CharProcs << /C0 5 0 R >> "
            b"/Encoding << /Type /Encoding /Differences [0 /C0 32 /C0] >> /FirstChar 0 /LastChar 32 /Widths [1" + b" 0" * 31 + b" 1] >>"], b"/Font << /F1 6 0 R >>"),
        "type3-fontmatrix": objects_pdf(RED + b"BT /F1 4 Tf 2 2 Td (\\000\\000) Tj ET", [stream(b"1000 0 d0 0 0 1000 1000 re f"),
            b"<< /Type /Font /Subtype /Type3 /FontBBox [0 0 1 1] /FontMatrix [0.001 0 0 0.001 0 0] /CharProcs << /C0 5 0 R >> "
            b"/Encoding << /Type /Encoding /Differences [0 /C0 32 /C0] >> /FirstChar 0 /LastChar 32 /Widths [1000" + b" 0" * 31 + b" 1000] >>"], b"/Font << /F1 6 0 R >>"),
        "type3-d0-color": objects_pdf(RED + b"BT /F1 4 Tf 2 2 Td (\\000) Tj ET", [stream(b"1 0 d0 0 0 1 rg 0 0 1 1 re f"),
            b"<< /Type /Font /Subtype /Type3 /FontBBox [0 0 1 1] /FontMatrix [1 0 0 1 0 0] /CharProcs << /C0 5 0 R >> "
            b"/Encoding << /Type /Encoding /Differences [0 /C0 32 /C0] >> /FirstChar 0 /LastChar 32 /Widths [1" + b" 0" * 31 + b" 1] >>"], b"/Font << /F1 6 0 R >>"),
        "type3-d1-color": objects_pdf(RED + b"BT /F1 4 Tf 2 2 Td (\\000) Tj ET", [stream(b"1 0 0 0 1 1 d1 0 0 1 rg 0 0 1 1 re f"),
            b"<< /Type /Font /Subtype /Type3 /FontBBox [0 0 1 1] /FontMatrix [1 0 0 1 0 0] /CharProcs << /C0 5 0 R >> "
            b"/Encoding << /Type /Encoding /Differences [0 /C0 32 /C0] >> /FirstChar 0 /LastChar 32 /Widths [1" + b" 0" * 31 + b" 1] >>"], b"/Font << /F1 6 0 R >>"),
        "type3-invisible": objects_pdf(RED + b"BT 3 Tr /F1 4 Tf 2 2 Td (\\000) Tj ET 2 6 2 2 re f", [stream(b"1 0 d0 0 0 1 1 re f"),
            b"<< /Type /Font /Subtype /Type3 /FontBBox [0 0 1 1] /FontMatrix [1 0 0 1 0 0] /CharProcs << /C0 5 0 R >> "
            b"/Encoding << /Type /Encoding /Differences [0 /C0 32 /C0] >> /FirstChar 0 /LastChar 32 /Widths [1" + b" 0" * 31 + b" 1] >>"], b"/Font << /F1 6 0 R >>"),
        "type3-leading-rise": objects_pdf(RED + b"BT /F1 2 Tf 3 TL 1 6 Td (\\000) Tj T* (\\000) Tj 1 Ts (\\000) Tj ET", [stream(b"1 0 d0 0 0 1 1 re f"),
            b"<< /Type /Font /Subtype /Type3 /FontBBox [0 0 1 1] /FontMatrix [1 0 0 1 0 0] /CharProcs << /C0 5 0 R >> "
            b"/Encoding << /Type /Encoding /Differences [0 /C0 32 /C0] >> /FirstChar 0 /LastChar 32 /Widths [1" + b" 0" * 31 + b" 1] >>"], b"/Font << /F1 6 0 R >>"),
        "type3-stroke-glyph": objects_pdf(RED + b"BT /F1 4 Tf 2 2 Td (\\000) Tj ET", [stream(b"1 0 d0 0.1 w 0 0 1 1 re S"),
            b"<< /Type /Font /Subtype /Type3 /FontBBox [0 0 1 1] /FontMatrix [1 0 0 1 0 0] /CharProcs << /C0 5 0 R >> "
            b"/Encoding << /Type /Encoding /Differences [0 /C0 32 /C0] >> /FirstChar 0 /LastChar 32 /Widths [1" + b" 0" * 31 + b" 1] >>"], b"/Font << /F1 6 0 R >>"),
        "empty-text": objects_pdf(RED + b"2 2 6 6 re f BT ET", [], b""),
        "fill-only": objects_pdf(RED + b"2 2 6 6 re f", [], b""),
    },
    "groups-3": {
        "w2": objects_pdf(b"/X1 Do", [form(b"0 0 1 RG 2 w 5 5 m 15 5 l S", bbox=b"-100 -100 200 200", extra=GROUP)], b"/XObject << /X1 5 0 R >>"),
        "w2-M2": objects_pdf(b"/X1 Do", [form(b"0 0 1 RG 2 w 2 M 5 5 m 15 5 l S", bbox=b"-100 -100 200 200", extra=GROUP)], b"/XObject << /X1 5 0 R >>"),
        "w2-M1": objects_pdf(b"/X1 Do", [form(b"0 0 1 RG 2 w 1 M 5 5 m 15 5 l S", bbox=b"-100 -100 200 200", extra=GROUP)], b"/XObject << /X1 5 0 R >>"),
        "w2-round": objects_pdf(b"/X1 Do", [form(b"0 0 1 RG 2 w 1 j 5 5 m 15 5 l S", bbox=b"-100 -100 200 200", extra=GROUP)], b"/XObject << /X1 5 0 R >>"),
        "w2-bevel": objects_pdf(b"/X1 Do", [form(b"0 0 1 RG 2 w 2 j 5 5 m 15 5 l S", bbox=b"-100 -100 200 200", extra=GROUP)], b"/XObject << /X1 5 0 R >>"),
        "w2-square-round": objects_pdf(b"/X1 Do", [form(b"0 0 1 RG 2 w 2 J 1 j 5 5 m 15 5 l S", bbox=b"-100 -100 200 200", extra=GROUP)], b"/XObject << /X1 5 0 R >>"),
        "w0": objects_pdf(b"/X1 Do", [form(b"0 0 1 RG 0 w 5 5 m 15 5 l S", bbox=b"-100 -100 200 200", extra=GROUP)], b"/XObject << /X1 5 0 R >>"),
        "w4-M3": objects_pdf(b"/X1 Do", [form(b"0 0 1 RG 4 w 3 M 5 5 m 15 5 l S", bbox=b"-100 -100 200 200", extra=GROUP)], b"/XObject << /X1 5 0 R >>"),
        "curve-M1": objects_pdf(b"/X1 Do", [form(b"0 0 1 RG 2 w 1 M 5 5 m 5 15 15 15 15 5 c S", bbox=b"-100 -100 200 200", extra=GROUP)], b"/XObject << /X1 5 0 R >>"),
        "dashed-M1": objects_pdf(b"/X1 Do", [form(b"0 0 1 RG 2 w 1 M [2 1] 0 d 5 5 m 15 5 l S", bbox=b"-100 -100 200 200", extra=GROUP)], b"/XObject << /X1 5 0 R >>"),
        "rect-M1": objects_pdf(b"/X1 Do", [form(b"0 0 1 RG 2 w 1 M 5 3 10 4 re S", bbox=b"-100 -100 200 200", extra=GROUP)], b"/XObject << /X1 5 0 R >>"),
        "scaled-M1": objects_pdf(b"/X1 Do", [form(b"0 0 1 RG 1 w 1 M q 2 0 0 2 0 0 cm 5 3 m 8 3 l S Q", bbox=b"-100 -100 200 200", extra=GROUP)], b"/XObject << /X1 5 0 R >>"),
        "closed-M1": objects_pdf(b"/X1 Do", [form(b"0 0 1 RG 2 w 1 M 5 5 m 15 5 l 10 8 l h S", bbox=b"-100 -100 200 200", extra=GROUP)], b"/XObject << /X1 5 0 R >>"),
    },
    "groups-2": {
        "ca-on-do": objects_pdf(b"/G1 gs /X1 Do", [form(RED + b"2 2 16 6 re f", extra=GROUP)], b"/XObject << /X1 5 0 R >> " + GS),
        "ca-inside": objects_pdf(b"/X1 Do", [form(b"/G1 gs " + RED + b"2 2 16 6 re f", extra=GROUP + b" /Resources << " + GS + b" >>")],
                                 b"/XObject << /X1 5 0 R >>"),
        "icc-cs": objects_pdf(b"/X1 Do", [form(RED + b"2 2 16 6 re f", extra=b" /Group << /S /Transparency /CS [/ICCBased 6 0 R] >>"),
                                          b"<< /N 3 /Alternate /DeviceRGB /Length %d >>\nstream\n" % len(P3) + P3 + b"\nendstream"],
                              b"/XObject << /X1 5 0 R >>"),
        "curve-bounds": objects_pdf(b"/X1 Do", [form(RED + b"2 2 m 2 12 18 12 18 2 c f", bbox=b"0 0 20 20", extra=GROUP)], b"/XObject << /X1 5 0 R >>"),
        "two-fills": objects_pdf(b"/X1 Do", [form(RED + b"1 1 3 3 re f 12 5 4 4 re f", extra=GROUP)], b"/XObject << /X1 5 0 R >>"),
        "fill-stroke": objects_pdf(b"/X1 Do", [form(b"0 0 1 RG 2 w " + RED + b"4 3 6 2 re B", extra=GROUP)], b"/XObject << /X1 5 0 R >>"),
        "bbox-beyond-page": objects_pdf(b"/X1 Do", [form(RED + b"2 2 16 6 re f", bbox=b"-5 -5 30 15", extra=GROUP)], b"/XObject << /X1 5 0 R >>"),
        "outside-bbox": objects_pdf(b"/X1 Do", [form(RED + b"10 2 4 4 re f", bbox=b"0 0 5 5", extra=GROUP)], b"/XObject << /X1 5 0 R >>"),
        "rotated": objects_pdf(b"q 0 1 -1 0 15 0 cm /X1 Do Q", [form(b"0 0 1 RG 2 w 1 1 m 8 4 l S " + RED + b"1 6 4 2 re f", extra=GROUP)],
                               b"/XObject << /X1 5 0 R >>"),
        "inherited-color": objects_pdf(b"0 0 1 rg /X1 Do", [form(b"2 2 16 6 re f", extra=GROUP)], b"/XObject << /X1 5 0 R >>"),
        "flatness": objects_pdf(b"/X1 Do", [form(b"0.6 i " + RED + b"2 2 16 6 re f", extra=GROUP)], b"/XObject << /X1 5 0 R >>"),
        "clip-inside": objects_pdf(b"/X1 Do", [form(b"4 0 8 10 re W n " + RED + b"2 2 16 6 re f", extra=GROUP)], b"/XObject << /X1 5 0 R >>"),
        "nested-matrix": objects_pdf(b"/X1 Do", [form(b"/X2 Do", extra=GROUP + b" /Resources << /XObject << /X2 6 0 R >> >>"),
                                                 form(RED + b"0 0 4 2 re f", extra=b" /Matrix [2 0 0 2 1 1]" + GROUP)], b"/XObject << /X1 5 0 R >>"),
        "in-path-clip": objects_pdf(b"q 2 2 m 10 2 l 6 8 l h W n /X1 Do Q", [form(RED + b"0 0 20 10 re f", extra=GROUP)], b"/XObject << /X1 5 0 R >>"),
        "in-two-clips": objects_pdf(b"q 2 2 m 10 2 l 6 8 l h W n 4 0 10 10 re W n /X1 Do Q", [form(RED + b"0 0 20 10 re f", extra=GROUP)],
                                    b"/XObject << /X1 5 0 R >>"),
        "in-evenodd-clip": objects_pdf(b"q 1 1 m 12 1 l 12 9 l 1 9 l h 3 3 m 9 3 l 9 7 l 3 7 l h W* n /X1 Do Q", [form(RED + b"0 0 20 10 re f", extra=GROUP)],
                                       b"/XObject << /X1 5 0 R >>"),
        "after-group": objects_pdf(b"/X1 Do 0 0 1 rg 0 0 4 4 re f", [form(RED + b"6 2 12 6 re f", extra=GROUP)], b"/XObject << /X1 5 0 R >>"),
    },
    "rect-forms": {
        "evenodd-re": pdf(b"q 2 2 12 6 re W* n " + RED + b"0 0 20 10 re f Q"),
        "evenodd-re-flipped": pdf(b"q 1 0 0 -1 0 10 cm 2 2 12 6 re W* n 1 0 0 -1 0 10 cm " + RED + b"0 0 20 10 re f Q"),
        "evenodd-4-ccw": pdf(b"q 2 2 m 14 2 l 14 8 l 2 8 l h W* n " + RED + b"0 0 20 10 re f Q"),
        "evenodd-4-cw": pdf(b"q 2 8 m 14 8 l 14 2 l 2 2 l h W* n " + RED + b"0 0 20 10 re f Q"),
        "evenodd-5-ccw": pdf(b"q 2 2 m 14 2 l 14 8 l 2 8 l 2 2 l h W* n " + RED + b"0 0 20 10 re f Q"),
        "evenodd-5-cw": pdf(b"q 2 8 m 14 8 l 14 2 l 2 2 l 2 8 l h W* n " + RED + b"0 0 20 10 re f Q"),
        "nonzero-4-cw": pdf(b"q 2 8 m 14 8 l 14 2 l 2 2 l h W n " + RED + b"0 0 20 10 re f Q"),
        "nonzero-5-cw": pdf(b"q 2 8 m 14 8 l 14 2 l 2 2 l 2 8 l h W n " + RED + b"0 0 20 10 re f Q"),
        "nonzero-re-flipped": pdf(b"q 1 0 0 -1 0 10 cm 2 2 12 6 re W n 1 0 0 -1 0 10 cm " + RED + b"0 0 20 10 re f Q"),
        "fill-5-ccw": pdf(RED + b"2 2 m 14 2 l 14 8 l 2 8 l 2 2 l h f"),
        "fill-5-cw": pdf(RED + b"2 8 m 14 8 l 14 2 l 2 2 l 2 8 l h f"),
        "fill-5-open": pdf(RED + b"2 2 m 14 2 l 14 8 l 2 8 l 2 2 l f"),
        "fill-re-flipped": pdf(b"1 0 0 -1 0 10 cm " + RED + b"2 2 12 6 re f"),
        "fill-evenodd-4-cw": pdf(RED + b"2 8 m 14 8 l 14 2 l 2 2 l h f*"),
    },
    "opacity": {
        "ca": pdf(b"/G1 gs " + RED + b"2 2 16 6 re f", resources=GS),
        "ca-nested": pdf(b"q /G1 gs " + RED + b"2 2 8 6 re f Q 0 0 1 rg 10 2 8 6 re f", resources=GS),
        "ca-one": pdf(b"/G1 gs " + RED + b"2 2 16 6 re f", resources=b"/ExtGState << /G1 << /ca 1 >> >>"),
    },
}


def write_catalog(root, cases):
    cat = root / "A.xcassets"
    shutil.rmtree(cat, ignore_errors=True)
    cat.mkdir(parents=True)
    ae.write_json(cat / "Contents.json", ae.INFO)
    for name, data in cases.items():
        folder = cat / f"{name}.imageset"
        folder.mkdir()
        # A case is the PDF, or the PDF and the image set's other entries (beside the PDF's own);
        # an entry with "data" is a file of its own, named after the case and its position.
        data, entries = data if isinstance(data, tuple) else (data, [{"idiom": "universal"}])
        (folder / f"{name}.pdf").write_bytes(data)
        images = [{"filename": f"{name}.pdf", **entries[0]}]
        for index, entry in enumerate(entries[1:], 1):
            entry = dict(entry)
            if "data" in entry:
                (folder / f"{name}-{index}.pdf").write_bytes(entry.pop("data"))
                entry["filename"] = f"{name}-{index}.pdf"
            images.append(entry)
        ae.write_json(folder / "Contents.json", {**ae.INFO, "images": images})
    return cat


def lzfse_decode(data):
    return subprocess.run(["compression_tool", "-decode", "-a", "lzfse"], input=data, capture_output=True, check=True).stdout


def vector_pdfs(car):
    """{file name: PDF} of the `PDF ` vector renditions of an Assets.car."""
    blocks, _ = ae.bom(car)
    found = {}
    for block in blocks:
        if block[:4] != b"ISTC" or block[24:28] != b" FDP":
            continue
        payload = block[184 + struct.unpack_from("<I", block, 168)[0]:]
        flag, length = struct.unpack_from("<II", payload, 4)
        data = payload[12:12 + length]
        found[block[40:168].split(b"\0")[0].decode()] = lzfse_decode(data) if flag == 1 else data
    return found


STREAM = re.compile(rb"(\d+) 0 obj\n(.*?)\nendobj\n", re.S)


def describe(document):
    """The PDF's text, each stream decompressed (an ICC profile by its length and MD5)."""
    def stream(match):
        header, body = match.group(1), match.group(2)
        data = zlib.decompress(body) if b"/FlateDecode" in header else body
        if b"/N " in header and b"/Alternate" in header:
            return header + b"\nstream\n<ICC profile, %d bytes, md5 %s>\nendstream" % (len(data), hashlib.md5(data).hexdigest().encode())
        return header + b"\nstream\n" + data + b"\nendstream"
    return re.sub(rb"(<<[^\n]*>>)\nstream\n(.*?)\nendstream", stream, document, flags=re.S).decode("latin1")


def without_profile(document):
    """The PDF with each ICC profile stream's and font program's bytes and lengths, the names
    Quartz gives fonts without a PostScript name, and the byte offsets (xref and startxref) put
    aside: what ADR 0204 lets differ in a PDF vector rendition."""
    text = re.sub(rb"(/N \d /Alternate /\w+ /Length )\d+( /Filter /FlateDecode >>\nstream\n).*?\nendstream", rb"\1#\2#\nendstream", document, flags=re.S)
    text = re.sub(rb"<< /(Length1 \d+|Subtype /Type1C) /Length \d+ /Filter /FlateDecode >>\nstream\n.*?\nendstream", b"<< /FontFile # >>\nstream\n#\nendstream",
                  text, flags=re.S)
    text = re.sub(rb"\+font[0-9a-f]{16}", b"+font#", text)
    text = re.sub(rb"\n\d{10} 00000 n ", b"\n# n ", text)
    return re.sub(rb"startxref\n\d+", b"startxref\n#", text)


class _Rect(ctypes.Structure):
    _fields_ = [("x", ctypes.c_double), ("y", ctypes.c_double), ("width", ctypes.c_double), ("height", ctypes.c_double)]


def render(document, scale=50):
    """The PDF's first page drawn by Quartz (CoreGraphics) `scale` times its size: RGBA bytes."""
    cg = ctypes.cdll.LoadLibrary(ctypes.util.find_library("CoreGraphics"))
    cf = ctypes.cdll.LoadLibrary(ctypes.util.find_library("CoreFoundation"))
    for name, result, args in [
        ("CFDataCreate", ctypes.c_void_p, [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_long]),
        ("CGDataProviderCreateWithCFData", ctypes.c_void_p, [ctypes.c_void_p]),
        ("CGPDFDocumentCreateWithProvider", ctypes.c_void_p, [ctypes.c_void_p]),
        ("CGPDFDocumentGetPage", ctypes.c_void_p, [ctypes.c_void_p, ctypes.c_size_t]),
        ("CGPDFPageGetBoxRect", _Rect, [ctypes.c_void_p, ctypes.c_int]),
        ("CGColorSpaceCreateWithName", ctypes.c_void_p, [ctypes.c_void_p]),
        ("CGBitmapContextCreate", ctypes.c_void_p, [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_size_t, ctypes.c_size_t, ctypes.c_size_t,
                                                    ctypes.c_void_p, ctypes.c_uint32]),
        ("CGContextScaleCTM", None, [ctypes.c_void_p, ctypes.c_double, ctypes.c_double]),
        ("CGContextTranslateCTM", None, [ctypes.c_void_p, ctypes.c_double, ctypes.c_double]),
        ("CGContextDrawPDFPage", None, [ctypes.c_void_p, ctypes.c_void_p]),
        ("CGContextRelease", None, [ctypes.c_void_p]),
        ("CGPDFDocumentRelease", None, [ctypes.c_void_p]),
    ]:
        function = getattr(cf if name.startswith("CFData") else cg, name)
        function.restype, function.argtypes = result, args
    cf.CFRelease.argtypes = [ctypes.c_void_p]
    data = cf.CFDataCreate(None, document, len(document))
    provider = cg.CGDataProviderCreateWithCFData(data)
    pdf = cg.CGPDFDocumentCreateWithProvider(provider)
    page = cg.CGPDFDocumentGetPage(pdf, 1)
    box = cg.CGPDFPageGetBoxRect(page, 0)
    width, height = round(box.width * scale), round(box.height * scale)
    pixels = ctypes.create_string_buffer(width * height * 4)
    space = cg.CGColorSpaceCreateWithName(ctypes.c_void_p.in_dll(cg, "kCGColorSpaceSRGB"))
    context = cg.CGBitmapContextCreate(pixels, width, height, 8, width * 4, space, 1)
    cg.CGContextScaleCTM(context, scale, scale)
    cg.CGContextTranslateCTM(context, -box.x, -box.y)
    cg.CGContextDrawPDFPage(context, page)
    cg.CGContextRelease(context)
    cg.CGPDFDocumentRelease(pdf)
    for value in (space, provider, data):
        cf.CFRelease(value)
    return pixels.raw


def rendered_alike(x, y):
    """Whether Quartz draws the two PDFs the same at 50 times their size, and how many pixels differ."""
    a, b = render(x), render(y)
    differing = sum(1 for index in range(0, len(a), 4) if a[index:index + 4] != b[index:index + 4])
    return differing == 0, differing


def pdf_payload(block):
    props = struct.unpack_from("<I", block, 168)[0]
    payload = block[184 + props:]
    flag, length = struct.unpack_from("<II", payload, 4)
    data = payload[12:12 + length]
    return lzfse_decode(data) if flag == 1 else data


def compare_car(x, y):
    """ADR 0204: the Assets.car files with each PDF vector rendition of nomac's that differs from
    actool's only in its color profiles (the same CSI header and properties) taken as actool's,
    then compared as the assets experiments compare rasterized images."""
    a, va = ae.bom(ae.canonical_car(x))
    b, vb = ae.bom(ae.canonical_car(y))
    profiles = False
    if len(a) == len(b):
        for index, (p, q) in enumerate(zip(a, b)):
            if p == q or p[:4] != b"ISTC" or p[24:28] != b" FDP" or p[:180] != q[:180]:
                continue
            props = struct.unpack_from("<I", p, 168)[0]
            # The payload's storage must match: actool keeps a PDF as it is (flag 0).
            if p[184:184 + props + 8] == q[184:184 + props + 8] and without_profile(pdf_payload(p)) == without_profile(pdf_payload(q)):
                b[index] = p
                profiles = True
    result = ae.compare_pixel_car(ae.serialize(a, va), ae.serialize(b, vb), frozenset())
    return "equivalent" if profiles and result == "identical" else result


def run(root, nomac, cases):
    cat = write_catalog(root, cases)
    actool = ae.run_actool([cat], root / "actool")
    pdfs = vector_pdfs((actool / "Assets.car").read_bytes()) if (actool / "Assets.car").exists() else {}
    for name, document in pdfs.items():
        stem = Path(name).stem
        (root / f"{stem}.pdf").write_bytes(document)
        (root / f"{stem}.txt").write_text(describe(document))
    result = {"cases": len(cases), "vector renditions": len(pdfs), "actool status": (actool / "status").read_text()}
    if nomac:
        ours = ae.run_nomac(nomac, [cat], root / "nomac")
        theirs = vector_pdfs((ours / "Assets.car").read_bytes()) if (ours / "Assets.car").exists() else {}
        refused = {}
        if (ours / "status").read_text() != "0":
            # One case nomac refuses stops the catalog: each case again in a catalog of its own.
            for name, data in cases.items():
                single = root / "single" / name
                one = ae.run_nomac(nomac, [write_catalog(single, {name: data})], single / "nomac")
                if (one / "Assets.car").exists():
                    theirs.update(vector_pdfs((one / "Assets.car").read_bytes()))
                else:
                    refused[f"{name}.pdf"] = (one / "stderr.txt").read_text().strip().splitlines()[-1:]
        compare = {}
        rendered = {}
        for name, document in pdfs.items():
            mine = theirs.get(name)
            if mine is None:
                compare[name] = "refused: " + " ".join(refused.get(name, [])) if name in refused else "missing"
            elif mine == document:
                compare[name] = "identical"
            else:
                compare[name] = "equivalent" if without_profile(mine) == without_profile(document) else "different"
                (root / f"{Path(name).stem}.nomac.txt").write_text(describe(mine))
                if b"/FontFile" in document:
                    alike, differing = rendered_alike(document, mine)
                    rendered[name] = "alike" if alike else f"{differing} pixels differ"
        if (ours / "Assets.car").exists() and (actool / "Assets.car").exists():
            compare["Assets.car"] = compare_car((actool / "Assets.car").read_bytes(), (ours / "Assets.car").read_bytes())
            result["Assets.car"] = compare["Assets.car"]
        ae.write_json(root / "compare.json", dict(compare, rendered=rendered) if rendered else compare)
        if rendered:
            result["rendered alike"] = f"{sum(1 for v in rendered.values() if v == 'alike')} of {len(rendered)}"
        result["nomac status"] = (ours / "status").read_text()
        result["compare"] = {kind: sum(1 for v in compare.values() if v.startswith(kind)) for kind in ("identical", "equivalent", "different", "refused", "missing")}
    return result


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    out = Path(args.pop(0)).resolve()
    nomac = None
    if args[:1] == ["--nomac"]:
        nomac = str(Path(args[1]).resolve())
        args = args[2:]
    names = args or list(EXPERIMENT_CASES)
    summary = {}
    for name in names:
        root = out / name
        shutil.rmtree(root, ignore_errors=True)
        root.mkdir(parents=True)
        summary[name] = run(root, nomac, EXPERIMENT_CASES[name])
        print(name, json.dumps(summary[name]))
    ae.write_json(out / "summary.json", summary)


if __name__ == "__main__":
    main()
