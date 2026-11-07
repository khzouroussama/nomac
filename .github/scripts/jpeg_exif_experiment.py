"""Self-written JPEGs that vary one Exif thing at a time (the `jpeg-exif` experiment's cases)."""
import struct, sys, os
import assets_experiments as ae

BODY = ae.jpeg_file(40, 30)

def segment(marker, body):
    return bytes([0xFF, marker]) + struct.pack(">H", len(body) + 2) + body

def jpeg(*segments):
    return b"\xff\xd8" + b"".join(segments) + BODY

def exif(tiff):
    return segment(0xE1, b"Exif\x00\x00" + tiff)

def num(e, ty, *vs):
    f = {1: 'B', 3: 'H', 4: 'I', 6: 'b', 8: 'h', 9: 'i', 11: 'f', 12: 'd'}
    if ty in (5, 10):
        return b''.join(struct.pack(e + ('II' if ty == 5 else 'ii'), a, b) for a, b in vs)
    return b''.join(struct.pack(e + f[ty], v) for v in vs)

def e(tag, ty, *vs):
    """An entry from numbers: (tag, type, count, value as bytes per byte order)."""
    return ('n', tag, ty, vs)

def s(tag, text):
    b = text.encode() + b'\0'
    return ('r', tag, 2, len(b), b)

def raw(tag, ty, count, data):
    return ('r', tag, ty, count, data)

def sub(tag, name):
    return ('s', tag, name)

def tiff(order='>', ifd0=(), subs=None, nxt=None, thumb=None, trailing=b'', head=None, gap=b''):
    """A TIFF laid out directory, then its values, then the sub directories it names by `sub`,
    then the next directory (`nxt`, entries, or an int written as it is), then `thumb`."""
    E = order
    subs = subs or {}
    out = bytearray((b'MM\0*' if E == '>' else b'II*\0') + struct.pack(E + 'I', 8) if head is None else head)
    out += gap
    if gap:
        out[4:8] = struct.pack(E + 'I', 8 + len(gap))
    fix = []
    def put(entries, nextv=None):
        at = len(out)
        out.extend(struct.pack(E + 'H', len(entries)))
        vals = []
        for x in entries:
            if x[0] == 's':
                fix.append((len(out) + 8, x[2]))
                out.extend(struct.pack(E + 'HHI', x[1], 4, 1) + b'\0\0\0\0')
                continue
            if x[0] == 'n':
                tag, ty, vs = x[1:]
                d = num(E, ty, *vs); c = len(vs)
            else:
                tag, ty, c, d = x[1:]
            out.extend(struct.pack(E + 'HHI', tag, ty, c))
            if len(d) <= 4:
                out.extend(d.ljust(4, b'\0'))
            else:
                vals.append((len(out), d)); out.extend(b'\0\0\0\0')
        nextpos = len(out)
        out.extend(struct.pack(E + 'I', 0 if nextv is None else nextv))
        for p, d in vals:
            out[p:p + 4] = struct.pack(E + 'I', len(out))
            out.extend(d)
            if len(d) % 2: out.append(0)
        return at, nextpos
    _, np0 = put(list(ifd0))
    done = {}
    while fix:
        p, name = fix.pop(0)
        at, _ = put(list(subs[name]))
        out[p:p + 4] = struct.pack(E + 'I', at)
    if isinstance(nxt, int):
        out[np0:np0 + 4] = struct.pack(E + 'I', nxt)
    elif nxt is not None:
        at = len(out)
        out[np0:np0 + 4] = struct.pack(E + 'I', at)
        entries = list(nxt)
        if thumb is not None:
            start = at + 2 + 12 * len(entries) + 4 + sum(8 for x in entries if x[0] == 'n' and x[2] in (5, 10))
            entries = [e(0x0201, 4, start) if x[1] == 0x0201 else e(0x0202, 4, len(thumb)) if x[1] == 0x0202 else x for x in entries]
        put(entries)
        if thumb is not None: out.extend(thumb)
    out += trailing
    return bytes(out)


ORIENT = e(0x0112, 3, 6)
XRES = e(0x011A, 5, (72, 1))
YRES = e(0x011B, 5, (72, 1))
UNIT = e(0x0128, 3, 2)
SOFT = s(0x0131, "nomac exp")
DATE = s(0x0132, "2024:01:02 03:04:05")
COLOR = e(0xA001, 3, 1)
PIXX = e(0xA002, 4, 40)
PIXY = e(0xA003, 4, 30)
THUMB = ae.jpeg_file(8, 8)
THUMB = b"\xff\xd8" + THUMB
IFD1 = [e(0x0103, 3, 6), e(0x011A, 5, (72, 1)), e(0x011B, 5, (72, 1)), e(0x0128, 3, 2), e(0x0201, 4, 0), e(0x0202, 4, 0)]


def values():
    c = {}
    def add(name, *t):
        c[name] = jpeg(*[exif(x) for x in t])
    O = e(0x112, 3, 1)
    def x(*ents): return tiff('>', [O, sub(0x8769, 'x')], {'x': list(ents)})
    for tag, name in ((0x9003, 'orig'), (0x9004, 'dig')):
        for v, b in (('ok', b'2021:02:03 04:05:06\0'), ('dash', b'2021-02-03 04:05:06\0'), ('blank', b'    :  :     :  :  \0'), ('zeros', b'0000:00:00 00:00:00\0'), ('bad', b'not a date at all!!\0'), ('short', b'2021:02:03\0'), ('month13', b'2021:13:03 04:05:06\0')):
            add(f'date-{name}-{v}', x(raw(tag, 2, len(b), b)))
    for v, b in (('ok', b'2021:02:03 04:05:06\0'), ('bad', b'not a date at all!!\0'), ('t', b'2021-02-03T04:05:06\0'), ('short', b'2021:02:03\0')):
        add(f'date-ifd0-{v}', tiff('>', [O, raw(0x132, 2, len(b), b)]))
    for v, b in (('plus', b'+01:00\0'), ('minus', b'-11:30\0'), ('z', b'Z\0'), ('bad', b'abcdef\0'), ('blank', b'      \0'), ('long', b'+01:00:00\0')):
        add(f'offset-{v}', x(raw(0x9010, 2, len(b), b)))
    for v, b in (('ascii', b'ASCII\0\0\0abcd'), ('ascii-odd', b'ASCII\0\0\0abc'), ('unicode', b'UNICODE\0a\0b\0'), ('jis', b'JIS\0\0\0\0\0abcd'), ('undef', b'\0' * 8 + b'abcd'), ('nocode', b'abcdefghijkl'), ('short', b'ASCII\0\0\0'), ('tiny', b'abc'), ('ascii-long', b'ASCII\0\0\0' + b'x' * 40), ('ascii-nul', b'ASCII\0\0\0ab\0cd\0\0')):
        add(f'comment-{v}', x(raw(0x9286, 7, len(b), b)))
    for v, b, ty in (('noterm', b'Maker', 2), ('nul-mid', b'Ma\0ker\0', 2), ('spaces', b'Maker   \0', 2), ('latin1', b'M\xe4ker\0', 2), ('utf8', 'Mäker'.encode() + b'\0', 2), ('empty', b'\0', 2), ('two-nul', b'Maker\0\0\0', 2), ('undefined-type', b'Maker\0', 7), ('byte-type', b'Maker\0', 1)):
        add(f'text-{v}', tiff('>', [O, raw(0x10F, ty, len(b), b)]))
    for o in range(1, 9): add(f'orient-{o}', tiff('>', [e(0x112, 3, o)]))
    for name, ty, v in (('zero-den', 5, (5, 0)), ('zero-num', 5, (0, 7)), ('zero-both', 5, (0, 0)), ('u32max', 5, (0xFFFFFFFF, 1)), ('u32max3', 5, (0xFFFFFFFF, 3)), ('over31', 5, (0x80000001, 2)), ('inv', 5, (1, 0xFFFFFFFF)), ('half', 5, (1, 2)), ('third', 5, (1, 3))):
        add(f'rat-{name}', tiff('>', [O, e(0x11A, ty, v), e(0x11B, 5, (1, 1))]))
    for name, v in (('zero-den', (5, 0)), ('neg-den', (5, -2)), ('both-neg', (-5, -2)), ('min', (-0x80000000, 1)), ('zero', (0, -3))):
        add(f'srat-{name}', x(e(0x9204, 10, v)))
    add('white-two', tiff('>', [O, e(0x13E, 5, (1, 2), (3, 4))]))
    add('prim-six', tiff('>', [O, e(0x13F, 5, (1, 2), (3, 4), (5, 6), (7, 8), (9, 10), (11, 12))]))
    add('transfer-three', tiff('>', [O, e(0x12D, 3, 7, 8, 9)]))
    add('subjloc-two', x(e(0xA214, 3, 7, 8)))
    add('iso-two', x(e(0x8827, 3, 100, 200)))
    add('subjarea-four', x(e(0x9214, 3, 1, 2, 3, 4)))
    add('pix-short', x(e(0xA002, 3, 40), e(0xA003, 3, 30)))
    add('tile-short', tiff('>', [O, e(0x142, 3, 40), e(0x143, 4, 30)]))
    add('uid-33', x(raw(0xA420, 2, 33, b'0123456789abcdef0123456789abcdef\0')))
    # which tags alone keep the segment
    alone = {'photometric': e(0x106, 3, 2), 'docname': s(0x10D, 'doc'), 'desc': s(0x10E, 'desc'), 'make': s(0x10F, 'mk'), 'model': s(0x110, 'md'), 'xres': e(0x11A, 5, (72, 1)), 'yres': e(0x11B, 5, (72, 1)), 'xpos': e(0x11E, 5, (1, 1)), 'ypos': e(0x11F, 5, (1, 1)), 'unit': e(0x128, 3, 2), 'transfer': e(0x12D, 3, 1), 'soft': s(0x131, 'sw'), 'date': raw(0x132, 2, 20, b'2021:02:03 04:05:06\0'), 'artist': s(0x13B, 'ar'), 'host': s(0x13C, 'ho'), 'white': e(0x13E, 5, (1, 2), (3, 4)), 'prim': e(0x13F, 5, (1, 2), (3, 4), (5, 6), (7, 8), (9, 10), (11, 12)), 'tilew': e(0x142, 3, 8), 'tileh': e(0x143, 3, 8), 'copyright': s(0x8298, 'co'), 'orient': e(0x112, 3, 1)}
    for n, x0 in alone.items():
        add(f'alone-{n}', tiff('>', [x0]))
        add(f'alone-{n}-color', tiff('>', [x0, sub(0x8769, 'x')], {'x': [e(0xA001, 3, 1)]}))
    add('alone-soft-date', tiff('>', [alone['soft'], alone['date']]))
    add('alone-soft-date-artist-host', tiff('>', [alone['soft'], alone['date'], alone['artist'], alone['host']]))
    add('alone-exif-color', tiff('>', [sub(0x8769, 'x')], {'x': [e(0xA001, 3, 1)]}))
    add('alone-exif-pix', tiff('>', [sub(0x8769, 'x')], {'x': [e(0xA002, 4, 1)]}))
    add('alone-exif-iso', tiff('>', [sub(0x8769, 'x')], {'x': [e(0x8827, 3, 100)]}))
    add('alone-exif-unknown', tiff('>', [sub(0x8769, 'x')], {'x': [e(0x9999, 3, 100)]}))
    # thumbnails
    T = b'\xff\xd8' + ae.jpeg_file(8, 8)
    def th(*ents, thumb=T, o='>', ifd0=None): return tiff(o, ifd0 or [O], nxt=list(ents), thumb=thumb)
    tag = (e(0x0201, 4, 0), e(0x0202, 4, 0))
    add('thumb-plain', th(e(0x103, 3, 6), e(0x11A, 5, (72, 1)), e(0x11B, 5, (72, 1)), e(0x128, 3, 2), *tag))
    add('thumb-little', th(e(0x103, 3, 6), e(0x11A, 5, (72, 1)), e(0x11B, 5, (72, 1)), e(0x128, 3, 2), *tag, o='<'))
    add('thumb-only-tags', th(*tag))
    add('thumb-compression', th(e(0x103, 3, 6), *tag))
    add('thumb-compression-1', th(e(0x103, 3, 1), *tag))
    add('thumb-orient-3', th(e(0x103, 3, 6), e(0x112, 3, 3), *tag))
    add('thumb-ifd0-orient-6', th(e(0x103, 3, 6), *tag, ifd0=[e(0x112, 3, 6)]))
    add('thumb-ifd0-no-orient', th(e(0x103, 3, 6), *tag, ifd0=[s(0x10F, 'mk')]))
    add('thumb-extra-size', th(e(0x100, 3, 8), e(0x101, 3, 8), e(0x103, 3, 6), *tag))
    add('thumb-extra-unknown', th(e(0x103, 3, 6), e(0x9999, 3, 8), *tag))
    add('thumb-not-jpeg', th(e(0x103, 3, 6), *tag, thumb=b'not a jpeg at all, sixteen+'))
    add('thumb-soi-only', th(e(0x103, 3, 6), *tag, thumb=b'\xff\xd8\xff\xd9'))
    add('thumb-truncated', th(e(0x103, 3, 6), *tag, thumb=T[:30]))
    add('thumb-odd', th(e(0x103, 3, 6), *tag, thumb=T + b'\0'))
    add('thumb-empty', th(e(0x103, 3, 6), *tag, thumb=b''))
    add('thumb-after-exif', tiff('>', [O, sub(0x8769, 'x')], {'x': [e(0xA001, 3, 1)]}, nxt=[e(0x103, 3, 6), *tag], thumb=T))
    add('thumb-gps', tiff('>', [O, sub(0x8825, 'g')], {'g': [e(0, 1, 2, 3, 0, 0)]}, nxt=[e(0x103, 3, 6), *tag], thumb=T))
    add('thumb-only-ifd1', tiff('>', [e(0x213, 3, 1)], nxt=[e(0x103, 3, 6), *tag], thumb=T))
    # sizes
    for n in (250, 253, 254, 255, 256, 257):
        tags = [O] + [e(0xC000 + i, 3, 1) for i in range(n - 1)]
        add(f'dir-{n}', tiff('>', tags))
    return c


def xmp_packet(body):
    return b'http://ns.adobe.com/xap/1.0/\0<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?><x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmlns:exif="http://ns.adobe.com/exif/1.0/" xmlns:tiff="http://ns.adobe.com/tiff/1.0/" xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/" xmlns:dc="http://purl.org/dc/elements/1.1/" ' + body + b'/></rdf:RDF></x:xmpmeta><?xpacket end="w"?>'


def third():
    c = {}
    O = e(0x112, 3, 1)
    base = tiff('>', [O])
    withdig = tiff('>', [O, sub(0x8769, 'x')], {'x': [raw(0x9004, 2, 20, b'2000:01:01 00:00:00\0')]})
    CD = b'xmp:CreateDate="2021-02-03T04:05:06+02:00"'
    def xmp(name, body, *t):
        c[name] = jpeg(*[exif(x) for x in t], segment(0xE1, xmp_packet(body)))
    xmp('xmp-create-with-exif', CD, base)
    xmp('xmp-create-no-exif', CD)
    xmp('xmp-create-has-dig', CD, withdig)
    xmp('xmp-create-empty-exif', CD, tiff('>', []))
    xmp('xmp-create-color', CD, tiff('>', [O, sub(0x8769, 'x')], {'x': [e(0xA001, 3, 1)]}))
    xmp('xmp-create-date-only', b'xmp:CreateDate="2021-02-03"', base)
    xmp('xmp-create-minutes', b'xmp:CreateDate="2021-02-03T04:05"', base)
    xmp('xmp-create-no-zone', b'xmp:CreateDate="2021-02-03T04:05:06"', base)
    xmp('xmp-create-fraction', b'xmp:CreateDate="2021-02-03T04:05:06.25+02:00"', base)
    xmp('xmp-create-z', b'xmp:CreateDate="2021-02-03T04:05:06Z"', base)
    xmp('xmp-create-bad', b'xmp:CreateDate="yesterday"', base)
    xmp('xmp-modify', b'xmp:ModifyDate="2021-02-03T04:05:06+02:00"', base)
    xmp('xmp-metadata', b'xmp:MetadataDate="2021-02-03T04:05:06+02:00"', base)
    xmp('xmp-exif-orig', b'exif:DateTimeOriginal="2021-02-03T04:05:06+02:00"', base)
    xmp('xmp-exif-dig', b'exif:DateTimeDigitized="2021-02-03T04:05:06+02:00"', base)
    xmp('xmp-ps-created', b'photoshop:DateCreated="2021-02-03T04:05:06+02:00"', base)
    xmp('xmp-tiff-orient', b'tiff:Orientation="3"', base)
    xmp('xmp-tiff-orient-no-exif', b'tiff:Orientation="3"')
    xmp('xmp-tiff-make', b'tiff:Make="XmpMake"', base)
    xmp('xmp-tiff-xres', b'tiff:XResolution="300/1"', base)
    xmp('xmp-exif-iso', b'exif:ISOSpeedRatings="100"', base)
    xmp('xmp-exif-time', b'exif:ExposureTime="1/10"', base)
    xmp('xmp-exif-pix', b'exif:PixelXDimension="99"', base)
    xmp('xmp-dc-rights', b'dc:format="image/jpeg"', base)
    xmp('xmp-empty', b'', base)
    c['xmp-before-exif'] = jpeg(segment(0xE1, xmp_packet(CD)), exif(base))
    c['xmp-create-order'] = jpeg(exif(tiff('>', [O, sub(0x8769, 'x')], {'x': [e(0x8827, 3, 100), raw(0x9003, 2, 20, b'2000:01:01 00:00:00\0'), e(0xA001, 3, 1)]})), segment(0xE1, xmp_packet(CD)))
    # maker notes
    def mn(name, b): c[name] = jpeg(exif(tiff('>', [O, sub(0x8769, 'x')], {'x': [e(0xA001, 3, 1), raw(0x927C, 7, len(b), b)]})))
    mn('mn-apple-garbage', b'Apple iOS\0\0\1MM' + b'garbage garbage')
    mn('mn-apple-empty', b'Apple iOS\0\0\1MM\0\0')
    mn('mn-apple-one', b'Apple iOS\0\0\1MM\0\1\0\1\0\x09\0\0\0\1\0\0\0\x0e\0\0\0\0')
    mn('mn-nikon', b'Nikon\0\2\x10\0\0MM\0*\0\0\0\x08\0\1\0\1\0\7\0\0\0\4\0\0\0\0\0\0\0\0')
    mn('mn-canon', b'\0\1\0\1\0\3\0\0\0\1\0\7\0\0\0\0\0\0')
    mn('mn-sony', b'SONY DSC \0\0\0\0\1\0\1\0\3\0\0\0\1\0\7\0\0\0\0\0\0')
    mn('mn-short', b'Ap')
    # misc
    c['transfer-two'] = jpeg(exif(tiff('>', [O, e(0x12D, 3, 7, 8)])))
    c['transfer-768'] = jpeg(exif(tiff('>', [O, e(0x12D, 3, *([5] * 768))])))
    c['dir-exif-255'] = jpeg(exif(tiff('>', [O, sub(0x8769, 'x')], {'x': [e(0xA001, 3, 1)] + [e(0xC000 + i, 3, 1) for i in range(254)]})))
    c['dir-exif-254'] = jpeg(exif(tiff('>', [O, sub(0x8769, 'x')], {'x': [e(0xA001, 3, 1)] + [e(0xC000 + i, 3, 1) for i in range(253)]})))
    c['exif-ptr-short'] = jpeg(exif(tiff('>', [O, raw(0x8769, 3, 1, b'\0\x1a')])))
    c['exif-ptr-bad'] = jpeg(exif(tiff('>', [O, raw(0x8769, 4, 1, b'\0\0\xff\xff')])))
    c['first-zero'] = jpeg(exif(b'MM\0*\0\0\0\0'))
    c['first-two'] = jpeg(exif(b'MM\0*\0\0\0\x02\0\0\0\0'))
    c['date-alnum'] = jpeg(exif(tiff('>', [O, raw(0x132, 2, 20, b'abcd:ef:gh ij:kl:mn\0')])))
    c['date-extra'] = jpeg(exif(tiff('>', [O, raw(0x132, 2, 26, b'2021:02:03 04:05:06 extra\0')])))
    c['date-noterm'] = jpeg(exif(tiff('>', [O, raw(0x132, 2, 19, b'2021:02:03 04:05:06')])))
    c['uid-bad'] = jpeg(exif(tiff('>', [O, sub(0x8769, 'x')], {'x': [raw(0xA420, 2, 33, b'zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz\0')]})))
    c['uid-short'] = jpeg(exif(tiff('>', [O, sub(0x8769, 'x')], {'x': [raw(0xA420, 2, 33, b'abc\0' + b'd' * 29)]})))
    c['srat-den-min'] = jpeg(exif(tiff('>', [O, sub(0x8769, 'x')], {'x': [e(0x9204, 10, (1, -0x80000000))]})))
    # a rewrite that grows past a segment: odd strings written without padding
    strings = [0x10D, 0x10E, 0x10F, 0x110, 0x131, 0x13B, 0x13C, 0x8298]
    each = 8191
    head = b'MM\0*\0\0\0\x08' + struct.pack('>H', len(strings) + 1) + struct.pack('>HHI', 0x112, 3, 1) + b'\0\1\0\0'
    base_ = 8 + 2 + 12 * (len(strings) + 1) + 4
    ents = b''.join(struct.pack('>HHII', t, 2, each, base_ + i * each) for i, t in enumerate(strings))
    grow = head + ents + b'\0\0\0\0' + (b'a' * (each - 1) + b'\0') * len(strings)
    c['grow-past-64k'] = jpeg(exif(grow)) if len(grow) + 8 <= 65535 else b''
    each = 8000
    ents = b''.join(struct.pack('>HHII', t, 2, each, base_ + i * each) for i, t in enumerate(strings))
    return {k: v for k, v in c.items() if v}


def fourth():
    c = {}
    O = e(0x112, 3, 1)
    base = tiff('>', [O])
    def xmp(name, body, *t):
        c[name] = jpeg(*[exif(x) for x in t], segment(0xE1, xmp_packet(body)))
    def el(inner):
        return b'http://ns.adobe.com/xap/1.0/\0<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:exifEX="http://cipa.jp/exif/1.0/" xmlns:aux="http://ns.adobe.com/exif/1.0/aux/" xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/">' + inner + b'</rdf:Description></rdf:RDF></x:xmpmeta>'
    def xe(name, inner, *t):
        c[name] = jpeg(*[exif(x) for x in t], segment(0xE1, el(inner)))
    xe('xe-create', b'<xmp:CreateDate>2021-02-03T04:05:06+02:00</xmp:CreateDate>', base)
    xe('xe-creator', b'<dc:creator><rdf:Seq><rdf:li>Someone</rdf:li></rdf:Seq></dc:creator>', base)
    xe('xe-rights', b'<dc:rights><rdf:Alt><rdf:li xml:lang="x-default">Mine</rdf:li></rdf:Alt></dc:rights>', base)
    xe('xe-description', b'<dc:description><rdf:Alt><rdf:li xml:lang="x-default">Words</rdf:li></rdf:Alt></dc:description>', base)
    xe('xe-title', b'<dc:title><rdf:Alt><rdf:li xml:lang="x-default">Title</rdf:li></rdf:Alt></dc:title>', base)
    xe('xe-tool', b'<xmp:CreatorTool>Tool 1</xmp:CreatorTool>', base)
    xe('xe-rating', b'<xmp:Rating>3</xmp:Rating>', base)
    xe('xe-aux-lens', b'<aux:Lens>A lens</aux:Lens>', base)
    xe('xe-exifex-lens', b'<exifEX:LensModel>A lens</exifEX:LensModel>', base)
    xe('xe-ps-credit', b'<photoshop:Credit>Someone</photoshop:Credit>', base)
    xe('xe-ps-city', b'<photoshop:City>Paris</photoshop:City>', base)
    xmp('xmp-modify-alone', b'xmp:ModifyDate="2021-02-03T04:05:06+02:00"')
    xmp('xmp-both-dig', b'xmp:CreateDate="2021-02-03T04:05:06" exif:DateTimeDigitized="2022-02-03T04:05:06"', base)
    xmp('xmp-both-orig', b'photoshop:DateCreated="2021-02-03T04:05:06" exif:DateTimeOriginal="2022-02-03T04:05:06"', base)
    xmp('xmp-orig-fraction', b'exif:DateTimeOriginal="2021-02-03T04:05:06.5"', base)
    xmp('xmp-modify-fraction', b'xmp:ModifyDate="2021-02-03T04:05:06.5"', base)
    xmp('xmp-create-fraction-3', b'xmp:CreateDate="2021-02-03T04:05:06.125"', base)
    xmp('xmp-create-has-subsec', b'xmp:CreateDate="2021-02-03T04:05:06.125"', tiff('>', [O, sub(0x8769, 'x')], {'x': [s(0x9292, '77')]}))
    xmp('xmp-create-month-only', b'xmp:CreateDate="2021-02"', base)
    xmp('xmp-create-year-only', b'xmp:CreateDate="2021"', base)
    c['two-xmp'] = jpeg(exif(base), segment(0xE1, xmp_packet(b'xmp:CreateDate="2021-02-03T04:05:06"')), segment(0xE1, xmp_packet(b'xmp:ModifyDate="2022-02-03T04:05:06"')))
    # segment growing past 64 KB
    strings = [0x10D, 0x10E, 0x10F, 0x110, 0x131, 0x13B, 0x13C, 0x8298]
    each = 8175
    base_ = 8 + 2 + 12 * (len(strings) + 1) + 4
    head = b'MM\0*\0\0\0\x08' + struct.pack('>H', len(strings) + 1) + struct.pack('>HHI', 0x112, 3, 1) + b'\0\1\0\0'
    ents = b''.join(struct.pack('>HHII', t, 2, each, base_ + i * each) for i, t in enumerate(strings))
    grow = head + ents + b'\0\0\0\0' + (b'a' * (each - 1) + b'\0') * len(strings)
    print('grow', len(grow) + 8, 'unpadded; padded', len(grow) + 8 + len(strings))
    c['grow-past-64k'] = jpeg(exif(grow))
    # APP13 forms
    empty = b'Photoshop 3.0\x008BIM\x04\x04\0\0\0\0\0\0'
    digest = b'8BIM\x04\x25\0\0\0\0\0\x10' + bytes(16)
    def app13(name, b): c[name] = jpeg(segment(0xE1, b'Exif\0\0' + base), segment(0xED, b))
    app13('p-empty', empty)
    app13('p-empty-digest', empty + digest)
    app13('p-other-bytes', b'Adobe_CM\0\1\2\3')
    app13('p-prefix-only', b'Photoshop 3.0\0')
    app13('p-resolution', b'Photoshop 3.0\x008BIM\x03\xed\0\0\0\0\0\x10\0H\0\0\0\1\0\1\0H\0\0\0\1\0\1')
    app13('p-iptc', b'Photoshop 3.0\x008BIM\x04\x04\0\0\0\0\0\x0e\x1c\x02\x78\0\x09A caption')
    app13('p-iptc-digest', b'Photoshop 3.0\x008BIM\x04\x04\0\0\0\0\0\x0e\x1c\x02\x78\0\x09A caption' + digest)
    app13('p-digest-only', b'Photoshop 3.0\0' + digest)
    app13('p-garbage', b'Photoshop 3.0\0garbage')
    return c


def fifth():
    c = {}
    O = e(0x112, 3, 1)
    T = b'\xff\xd8' + ae.jpeg_file(8, 8)
    tag = (e(0x0201, 4, 0), e(0x0202, 4, 0))
    def odd(total):
        # a TIFF of `total` bytes after the Exif prefix, in one even string
        head = 8 + 2 + 12 * 2 + 4
        n = total - head
        return tiff('>', [O, raw(0x10F, 2, n, b'a' * (n - 1) + b'\0')])
    c['size-65527'] = jpeg(exif(odd(65526)))
    c['size-65526'] = jpeg(exif(odd(65524)))
    for n, name in ((65446, 'seg-65534'), (65447, 'seg-65535'), (65448, 'seg-65536')):
        c[name] = jpeg(exif(tiff('>', [O], nxt=[e(0x103, 3, 6), *tag], thumb=b'\xff\xd8' + bytes(n - 2))))
    c['thumb-short-tags'] = jpeg(exif(tiff('>', [O], nxt=[e(0x103, 3, 6), e(0x0201, 3, 80), e(0x0202, 3, len(T))], trailing=T)))
    c['thumb-soi-2'] = jpeg(exif(tiff('>', [O], nxt=[e(0x103, 3, 6), *tag], thumb=b'\xff\xd8')))
    c['thumb-soi-3'] = jpeg(exif(tiff('>', [O], nxt=[e(0x103, 3, 6), *tag], thumb=b'\xff\xd8\xff')))
    c['thumb-ff-1'] = jpeg(exif(tiff('>', [O], nxt=[e(0x103, 3, 6), *tag], thumb=b'\xff')))
    c['thumb-ifd1-own'] = jpeg(exif(tiff('>', [s(0x10F, 'mk')], nxt=[e(0x103, 3, 6), e(0x112, 3, 3), e(0x128, 3, 2), *tag], thumb=T)))
    c['thumb-res-partial'] = jpeg(exif(tiff('>', [O, e(0x11A, 5, (10, 1))], nxt=[e(0x103, 3, 6), *tag], thumb=T)))
    c['thumb-exif-only'] = jpeg(exif(tiff('>', [e(0x213, 3, 1), sub(0x8769, 'x')], {'x': [e(0xA001, 3, 1)]}, nxt=[e(0x103, 3, 6), *tag], thumb=T)))
    return c


def lengths():
    c = {}
    O = e(0x112, 3, 1)
    for n in (9999, 10000, 10001):
        c[f'make-{n}'] = jpeg(exif(tiff('>', [O, raw(0x10F, 2, n, b'a' * (n - 1) + b'\0')])))
    for n in (39, 40, 41):
        c[f'area-{n}'] = jpeg(exif(tiff('>', [O, sub(0x8769, 'x')], {'x': [raw(0x9214, 3, n, b'\0\1' * n)]})))
        c[f'iso-{n}'] = jpeg(exif(tiff('>', [O, sub(0x8769, 'x')], {'x': [raw(0x8827, 3, n, b'\0\1' * n)]})))
    c['comment-65400'] = jpeg(exif(tiff('>', [O, sub(0x8769, 'x')], {'x': [raw(0x9286, 7, 65400, b'ASCII\0\0\0' + b'a' * 65392)]})))
    return c


def experiment():
    """Every case of `jpeg-exif`: name to file."""
    return {**cases(), **values(), **third(), **fourth(), **fifth(), **lengths()}


def cases():
    c = {}
    def add(name, *t):
        c[name] = jpeg(*[exif(x) for x in t])
    for o, n in (('>', 'be'), ('<', 'le')):
        add(f'{n}-orientation', tiff(o, [ORIENT]))
        add(f'{n}-res', tiff(o, [ORIENT, XRES, YRES, UNIT]))
        add(f'{n}-soft-date', tiff(o, [SOFT, DATE]))
        add(f'{n}-exif', tiff(o, [ORIENT, sub(0x8769, 'x')], {'x': [COLOR, PIXX, PIXY]}))
        add(f'{n}-thumb', tiff(o, [ORIENT], nxt=IFD1, thumb=THUMB))
        add(f'{n}-types', tiff(o, [ORIENT, sub(0x8769, 'x')], {'x': [
            e(0x9000, 3, 1, 2, 3, 4, 5), raw(0x9286, 7, 12, b'ASCII\0\0\0abcd'),
            e(0x9201, 10, (-1, 3)), e(0x829A, 5, (1, 50)), e(0xA20E, 11, 1.5), e(0xA20F, 12, 2.5),
            e(0xA301, 1, 1, 2, 3, 4, 5), e(0xA302, 6, 1, 2, 3, 4, 5), e(0xA303, 8, 1, 2, 3), e(0xA304, 9, 1, 2)]}))
    # order of tags
    add('order-ifd0-reversed', tiff('>', [UNIT, YRES, XRES, ORIENT]))
    add('order-exif-reversed', tiff('>', [ORIENT, sub(0x8769, 'x')], {'x': [PIXY, PIXX, COLOR]}))
    add('order-exif-before-orient', tiff('>', [sub(0x8769, 'x'), ORIENT], {'x': [COLOR, PIXX, PIXY]}))
    # one tag at a time
    add('ycbcr-only', tiff('>', [e(0x0213, 3, 1)]))
    add('ycbcr-beside', tiff('>', [ORIENT, e(0x0213, 3, 1)]))
    add('gps-only', tiff('>', [sub(0x8825, 'g')], {'g': [e(0x0000, 1, 2, 3, 0, 0)]}))
    add('gps-beside', tiff('>', [ORIENT, sub(0x8825, 'g')], {'g': [e(0x0000, 1, 2, 3, 0, 0)]}))
    add('soft-only', tiff('>', [SOFT]))
    add('date-only', tiff('>', [DATE]))
    add('soft-res', tiff('>', [XRES, YRES, UNIT, SOFT]))
    add('make', tiff('>', [s(0x010F, "Maker"), s(0x0110, "Model")]))
    add('copyright', tiff('>', [s(0x8298, "Me")]))
    add('artist', tiff('>', [s(0x013B, "Me")]))
    add('unknown-ifd0', tiff('>', [ORIENT, e(0x9999, 3, 7)]))
    add('unknown-exif', tiff('>', [ORIENT, sub(0x8769, 'x')], {'x': [COLOR, e(0x9999, 3, 7)]}))
    add('makernote', tiff('>', [ORIENT, sub(0x8769, 'x')], {'x': [COLOR, raw(0x927C, 7, 10, b'0123456789')]}))
    add('interop', tiff('>', [ORIENT, sub(0x8769, 'x')], {'x': [COLOR, sub(0xA005, 'i')], 'i': [raw(0x0001, 2, 4, b'R98\0'), raw(0x0002, 7, 4, b'0100')]}))
    add('exif-empty', tiff('>', [ORIENT, sub(0x8769, 'x')], {'x': []}))
    add('dup-tag', tiff('>', [ORIENT, e(0x0112, 3, 3)]))
    add('orientation-long', tiff('>', [e(0x0112, 4, 6)]))
    add('orientation-0', tiff('>', [e(0x0112, 3, 0)]))
    add('orientation-9', tiff('>', [e(0x0112, 3, 9)]))
    add('unknown-type-0', tiff('>', [ORIENT, raw(0x9999, 0, 1, b'\1\2\3\4')]))
    add('unknown-type-13', tiff('>', [ORIENT, raw(0x9999, 13, 1, b'\1\2\3\4')]))
    add('unknown-type-99', tiff('>', [ORIENT, raw(0x9999, 99, 1, b'\1\2\3\4')]))
    add('known-tag-unknown-type', tiff('>', [e(0x0112, 3, 6), raw(0x011A, 99, 1, b'\1\2\3\4')]))
    # layout
    add('trailing', tiff('>', [ORIENT], trailing=b'trailing'))
    add('gap', tiff('>', [ORIENT], gap=b'\xAA\xBB\xCC\xDD'))
    add('next-out-of-range', tiff('>', [ORIENT], nxt=9999))
    add('next-to-bare', tiff('>', [ORIENT], nxt=[e(0x0100, 3, 8)]))
    add('next-self', tiff('>', [ORIENT], nxt=8))
    add('thumb-no-tags', tiff('>', [ORIENT], nxt=[XRES, YRES], thumb=None))
    add('thumb-empty-ifd', tiff('>', [ORIENT], nxt=[]))
    # malformed
    add('short-1', b'M')
    add('short-empty', b'')
    add('bad-order', b'XX\0*\0\0\0\x08\0\0\0\0\0\0')
    add('bad-magic', b'MM\0+\0\0\0\x08\0\1\x01\x12\0\3\0\0\0\1\0\6\0\0\0\0\0\0')
    add('first-out-of-range', b'MM\0*\0\0\xff\xff')
    add('count-too-big', b'MM\0*\0\0\0\x08\xff\xff\x01\x12\0\3\0\0\0\1\0\6\0\0\0\0\0\0')
    add('no-next-word', b'MM\0*\0\0\0\x08\0\1\x01\x12\0\3\0\0\0\1\0\6\0\0')
    add('value-out-of-range', tiff('>', [ORIENT, raw(0x0131, 2, 20, b'')]).replace(b'\0\0\0\0\0\0\0\0', b'\0\0\xff\xff\0\0\0\0', 1))
    # several segments
    one, two = tiff('>', [e(0x0112, 3, 3)]), tiff('>', [e(0x0112, 3, 6)])
    add('two-same', one, one)
    add('two-different', one, two)
    add('two-empty-first', tiff('>', []), one)
    add('two-empty-second', one, tiff('>', []))
    return c


def exp_jpeg_exif(root, nomac):
    """Each file in a one-set catalog."""
    reports = []
    for name, data in experiment().items():
        cat = ae.catalog(root / "catalogs" / name / "A.xcassets", {})
        folder = cat / "J.imageset"
        folder.mkdir()
        (folder / "j.jpg").write_bytes(data)
        ae.write_json(folder / "Contents.json", {"images": [{"filename": "j.jpg", "idiom": "universal", "scale": "1x"}], **ae.INFO})
        reports.append(ae.case(root, name, [cat], nomac))
    return reports
