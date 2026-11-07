"""`old-targets`: image sets at deployment targets before iOS 13. Written as a function that can
join `assets_experiments.py` (`exp_old_targets(root, nomac)`, EXPERIMENTS["old-targets"]). Outputs
stay under `root`; the summary holds observed values only."""
import collections, os, random, shutil, struct, subprocess, sys
from pathlib import Path

import assets_experiments as ae

TARGETS = '3.0 4.0 5.0 6.0 7.0 7.1 8.0 8.1 8.2 8.3 8.4 9.0 9.1 9.2 9.3 10.0 10.1 10.2 10.3 11.0 11.1 11.2 11.3 11.4 12.0 12.1 12.2 12.3 12.4 12.5 13.0'.split()
SVG = '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16"><rect width="16" height="16" fill="#e04020"/></svg>'


def run(cat, target, out, extra=()):
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    args = list(ae.ACTOOL_ARGS)
    args[args.index('--minimum-deployment-target') + 1] = target
    env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode_27.app/Contents/Developer')
    return subprocess.run(['xcrun', 'actool', str(cat), '--compile', str(out), '--output-partial-info-plist', str(out / 'p.plist'), *args, *extra],
                          capture_output=True, text=True, env=env)


def renditions(path):
    blocks, variables = ae.bom(ae.canonical_car(Path(path).read_bytes()))
    names = dict(variables)
    block = blocks[names['KEYFORMAT']]
    keys = list(struct.unpack_from(f"<{struct.unpack_from('<I', block, 8)[0]}I", block, 12))
    out = []
    for value, key in ae.tree_entries(blocks, names['RENDITIONS']):
        csi = blocks[value]
        attributes = {a: v for a, v in zip(keys, struct.unpack_from(f'<{len(keys)}H', blocks[key])) if v}
        length = struct.unpack_from('<I', csi, 168)[0]
        out.append((attributes, csi[24:28][::-1].decode('latin1'), struct.unpack_from('<H', csi, 36)[0], csi[184 + length:]))
    return keys, out


def image(cat, name, width, height, pixel, scale='1x', **entry):
    folder = cat / f'{name}.imageset'
    ae.png(folder / 'i.png', width, height, pixel)
    ae.write_json(folder / 'Contents.json', {'images': [{'filename': 'i.png', 'idiom': 'universal', 'scale': scale, **entry}], **ae.INFO})


def eras(root):
    """One color, a 400 × 300 image, three 24 × 24 2x images, at every minor version."""
    cat = ae.catalog(root / 'eras' / 'A.xcassets', {'Red': ae.red()})
    image(cat, 'Big', 400, 300, lambda x, y: (x % 256, y % 256, (x + y) % 256, 255))
    for i in range(3):
        image(cat, f'S{i}', 24, 24, lambda x, y, i=i: (x * 9, y * 9, i * 60, 255), '2x')
    summary = {}
    for target in TARGETS:
        out = root / 'eras' / target
        done = run(cat, target, out)
        keys, rows = renditions(out / 'Assets.car')
        count = collections.Counter((a.get(25, a.get(5, 0)), lay, struct.unpack_from('<I', p, 8)[0] if p[:4] == b'MLEC' else '') for a, _, lay, p in rows)
        summary[target] = dict(status=done.returncode, keyformat=keys, renditions=sorted(map(str, count.items())), files=sorted(f.name for f in out.iterdir()))
    return summary


def payloads(root):
    """At 8.0 nothing packs, so every size stands alone: sizes around the compression 8 and 10,
    band and 4,096-byte limits, flat, two-color, three-level, noisy, translucent, gray images."""
    r = random.Random(5)
    noise = lambda levels=256, alpha=False, gray=False: lambda x, y: (lambda v: (v, v, v) if gray else (r.randrange(levels) * (255 // (levels - 1)), v, r.randrange(levels) * (255 // (levels - 1))))(r.randrange(levels) * (255 // (levels - 1))) + (r.randrange(256) if alpha else 255,)
    smooth = lambda x, y: ((x * 2 + y) % 256, (y * 2 + x) % 256, (x + y) % 256, 255)
    cat = ae.catalog(root / 'payloads' / 'A.xcassets', {})
    for w, h in [(1, 1), (2, 2), (3, 3), (5, 5), (7, 9), (8, 8), (16, 16), (31, 31), (32, 32), (33, 33), (50, 50), (64, 63), (64, 64), (65, 65), (70, 70), (71, 71), (71, 72), (65, 79), (80, 80), (90, 90), (100, 100), (128, 128), (40, 120), (120, 40), (200, 10), (10, 200), (33, 30), (17, 61)]:
        image(cat, f'sm{w}x{h}', w, h, smooth)
        image(cat, f'no{w}x{h}', w, h, noise())
    for w in (4, 9, 17, 33, 64, 90):
        image(cat, f'fl{w}', w, w, lambda x, y: (10, 20, 30, 255))
        image(cat, f'tw{w}', w, w, lambda x, y: ((x + y) % 2 * 200, 20, 30, 255))
        image(cat, f'al{w}', w, w, noise(alpha=True))
        image(cat, f'gr{w}', w, w, noise(gray=True))
        image(cat, f'ga{w}', w, w, noise(gray=True, alpha=True))
        image(cat, f'q{w}', w, w, noise(3))
    out = root / 'payloads' / 'o'
    run(cat, '8.0', out)
    _, rows = renditions(out / 'Assets.car')
    return dict(collections.Counter(str((a.get(5, 0), struct.unpack_from('<I', p, 8)[0])) for a, _, _, p in rows))


def traits(root):
    """Which entries exist per variant, at each era."""
    cat = ae.catalog(root / 'traits' / 'A.xcassets', {'Red': ae.red()})
    smooth = lambda x, y: ((x * 2 + y) % 256, (y * 2 + x) % 256, (x + y) % 256, 255)
    image(cat, 'Ins', 30, 30, smooth, **{'alignment-insets': {'top': 1, 'bottom': 2, 'left': 3, 'right': 4}})
    image(cat, 'Res', 32, 32, smooth, '2x', resizing={'mode': '9-part', 'center': {'mode': 'stretch', 'width': 1, 'height': 1}, 'cap-insets': {'top': 2, 'bottom': 3, 'left': 4, 'right': 5}})
    image(cat, 'Dir', 34, 34, smooth, '3x', **{'language-direction': 'left-to-right'})
    for name, data, entry in (('Jpg', b'\xff\xd8' + ae.jpeg_file(40, 30), 'j.jpg'), ('Svg', SVG.encode(), 'v.svg')):
        folder = cat / f'{name}.imageset'
        folder.mkdir()
        (folder / entry).write_bytes(data)
        ae.write_json(folder / 'Contents.json', {'images': [{'filename': entry, 'idiom': 'universal'}], **ae.INFO})
    data = cat / 'Blob.dataset'
    data.mkdir()
    (data / 'b.txt').write_bytes(b'hello')
    ae.write_json(data / 'Contents.json', {'data': [{'filename': 'b.txt', 'idiom': 'universal'}], **ae.INFO})
    icons = cat / 'AppIcon.appiconset'
    icons.mkdir()
    entries = []
    for size, scale, idiom in [(20, 2, 'iphone'), (20, 3, 'iphone'), (29, 2, 'iphone'), (29, 3, 'iphone'), (40, 2, 'iphone'), (40, 3, 'iphone'), (60, 2, 'iphone'), (60, 3, 'iphone'), (1024, 1, 'ios-marketing')]:
        ae.png(icons / f'i{size}_{scale}.png', size * scale, size * scale, lambda x, y, s=size: (x % 256, y % 256, s % 256, 255))
        entries.append({'filename': f'i{size}_{scale}.png', 'idiom': idiom, 'scale': f'{scale}x', 'size': f'{size}x{size}'})
    ae.write_json(icons / 'Contents.json', {'images': entries, **ae.INFO})
    summary = {}
    for target in ('13.0', '12.0', '11.0', '10.0', '9.3', '9.0', '8.0', '7.0', '6.1'):
        out = root / 'traits' / target
        done = run(cat, target, out, ('--app-icon', 'AppIcon'))
        summary[target] = dict(status=done.returncode, files=sorted(f.name for f in out.iterdir()))
        if (out / 'Assets.car').exists():
            summary[target]['renditions'] = sorted(map(str, ((a.get(25, a.get(5, 0)), a.get(4, 0), a.get(2), pf, lay) for a, pf, lay, _ in renditions(out / 'Assets.car')[1])))
    return summary


def exp_old_targets(root, nomac=None):
    root = Path(root)
    return dict(eras=eras(root), payloads=payloads(root), traits=traits(root))


if __name__ == '__main__':
    import json
    print(json.dumps(exp_old_targets(sys.argv[1]), indent=1))
