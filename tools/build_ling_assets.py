"""Build the Ling -> Silent skin assets: atlas text, PNG texture, 4.2 JSON skeleton."""
import json
import re
import struct
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import spine41_parse as sp
import spine42_emit as em

try:
    import texture2ddecoder
except ImportError:
    texture2ddecoder = None


def write_png(path, w, h, rgba):
    """Minimal PNG writer (RGBA8, filter 0)."""
    def chunk(tag, data):
        c = struct.pack('>I', len(data)) + tag + data
        return c + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF)
    raw = bytearray()
    stride = w * 4
    for y in range(h):
        raw.append(0)
        raw += rgba[y*stride:(y+1)*stride]
    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(bytes(raw), 6))
           + chunk(b'IEND', b''))
    Path(path).write_bytes(png)


def extract_atlas(uexp_path):
    d = Path(uexp_path).read_bytes()
    if d.find(b'\x00p\x00n\x00g\x00') >= 0:
        # UTF-16 atlas: find a page-name line start (ASCII char + NUL pairs)
        m = re.search(rb'(?:[\x20-\x7e]\x00){3,}\.\x00p\x00n\x00g\x00', d)
        if not m:
            raise ValueError('no utf16 png marker')
        start = m.start()
        text = d[start:].decode('utf-16-le', errors='replace')
    else:
        m = re.search(rb'[\x20-\x7e][\x20-\x7e\-_.]{0,120}\.png\r?\nsize:', d)
        if not m:
            raise ValueError('no atlas text')
        start = m.start()
        while start > 0 and 0x20 <= d[start-1] <= 0x7e:
            start -= 1
        text = d[start:].decode('utf-8', errors='replace')
    # cut trailing serialization junk after the last atlas line
    lines = text.split('\n')
    out = []
    for ln in lines:
        ln = ln.rstrip('\r')
        if not ln:
            out.append(ln)
            continue
        # atlas lines are printable ASCII/CJK; binary junk contains control chars
        if any(ord(c) < 0x20 or 0x7f <= ord(c) < 0x4e00 for c in ln):
            break
        out.append(ln)
    while out and not out[-1].strip():
        out.pop()
    return '\n'.join(out) + '\n'


def decode_astc_texture(uexp_path, out_png=None):
    """Parse the Zulong Texture2D uexp (Noesis parseTexture2D logic) and decode ASTC."""
    d = Path(uexp_path).read_bytes()
    i = d.find(b'PF_')
    if i < 0:
        raise ValueError('no PF_ format string')
    slen = struct.unpack_from('<I', d, i - 4)[0]
    after = i + slen                      # end of format string (incl. NUL)
    cur = after + 4
    test = struct.unpack_from('<I', d, cur + 8)[0]
    if test != 0x48:
        raise ValueError(f'unexpected header mode (Test={test:#x})')
    size = struct.unpack_from('<I', d, cur + 0xC)[0]
    unz = struct.unpack_from('<I', d, cur + 0x10)[0]
    if size != unz:
        raise ValueError('compressed texture not supported')
    px = cur + 0x1C                     # seek(8,REL) after UnzipSize (Noesis path)
    w, h = struct.unpack_from('<II', d, px + size)
    fmt = d[i:i + 11].decode('ascii')     # e.g. PF_ASTC_6x6
    blk = int(fmt.split('_')[-1][0])      # 6 for 6x6
    data = d[px:px + size]
    rgba = texture2ddecoder.decode_astc(data, w, h, blk, blk)
    out = bytes(rgba) if not isinstance(rgba, (bytes, bytearray)) else bytes(rgba)
    # texture2ddecoder returns BGRA - swap to RGBA (project-wide channel fix,
    # iguf 12.48: the missing swap made every extracted PNG red/blue inverted)
    out = bytearray(out)
    out[0::4], out[2::4] = out[2::4], out[0::4]
    out = bytes(out)
    if out_png:
        write_png(out_png, w, h, out)
    return out, w, h, fmt


def main():
    char = Path(sys.argv[1])   # e.g. unpacked/res_models/characters/ling001
    stem = sys.argv[2]         # chr_ling001
    outdir = Path(sys.argv[3])
    outdir.mkdir(parents=True, exist_ok=True)

    # atlas text
    atlas_text = extract_atlas(char / f'{stem}-atlas.uexp')
    (outdir / f'{stem}.atlas').write_text(atlas_text, encoding='utf-8', newline='')
    pages = re.findall(r'[\w\-.]+\.png', atlas_text)
    size_m = re.search(r'size:(\d+),(\d+)', atlas_text)
    scale_m = re.search(r'scale:([\d.]+)', atlas_text)
    W, H = int(size_m.group(1)), int(size_m.group(2))
    print(f"atlas: pages={pages} {W}x{H} scale={scale_m.group(1) if scale_m else '?'}")

    # textures: one uexp per page under textures/
    for pi, page in enumerate(pages):
        name = page[:-4]
        tex = char / 'textures' / f'{name}.uexp'
        if not tex.exists():
            print(f"  MISSING texture uexp for page {page}")
            continue
        _, w, h, fmt = decode_astc_texture(tex, outdir / page)
        print(f"  decoded {page} ({w}x{h}, {fmt})")

    # skeleton 4.1 -> 4.2 JSON
    sys.path.insert(0, str(Path(__file__).parent))
    import az_spine_extract as ase
    uexp = (char / f'{stem}-data.uexp').read_bytes()
    skel_bytes, _info = ase.locate_spine(uexp)
    sk = sp.parse_skeleton(skel_bytes)
    assert sk['leftover'] == 0, sk['leftover']
    rename = {'idle': 'idle_loop', 'hit': 'hurt', 'skill01_1': 'cast'}
    root = em.emit_json(sk, anim_rename=rename, extra_animations={'die': {}})
    tune_for_sts2(root, speed=2.0, root_scale_mult=2.0)
    (outdir / f'{stem}.json').write_text(
        json.dumps(root, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
    print(f"skeleton json: {len(root['animations'])} animations, "
          f"{len(root['bones'])} bones, leftover=0")


def tune_for_sts2(root, speed=1.0, root_scale_mult=1.0):
    """Align a dragon-raja skeleton with STS2 pacing/scale.

    speed: divide every animation frame time by this (2 = play 2x faster).
    root_scale_mult: multiply the root bone's setup scaleX/Y (root must not be
    animated; check `bones[0]` has no timelines before using > 1).
    """
    def walk(o):
        if isinstance(o, dict):
            for k, v in list(o.items()):
                if k == 'time' and isinstance(v, (int, float)):
                    r = round(v / speed, 6)
                    o[k] = int(r) if r == int(r) else r
                elif k == 'curve' and isinstance(v, list) and len(v) == 4 and speed != 1.0:
                    # bezier control points store ABSOLUTE (time, value) pairs;
                    # the time components (idx 0/2) must scale with frame times
                    v[0] = round(v[0] / speed, 6)
                    v[2] = round(v[2] / speed, 6)
                elif k == 'delay' and isinstance(v, (int, float)) and speed != 1.0:
                    o[k] = round(v / speed, 6)
                else:
                    walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)

    if speed != 1.0:
        walk(root['animations'])
    rb = root['bones'][0]
    if root_scale_mult != 1.0:
        rb['scaleX'] = round(rb.get('scaleX', 1) * root_scale_mult, 6)
        rb['scaleY'] = round(rb.get('scaleY', 1) * root_scale_mult, 6)
        # bones with inherit modes that skip parent scale (noScale etc.) keep
        # their setup size when root scales — compensate them so the figure
        # scales uniformly; their children inherit the compensated scale.
        NOSCALE_MODES = ('noScale', 'noScaleOrReflection', 'onlyTranslation')
        comp = [b['name'] for b in root['bones'] if b.get('inherit') in NOSCALE_MODES]
        for b in root['bones']:
            if b['name'] in comp:
                b['scaleX'] = round(b.get('scaleX', 1) * root_scale_mult, 6)
                b['scaleY'] = round(b.get('scaleY', 1) * root_scale_mult, 6)
        for av in root['animations'].values():
            for bn, bt in av.get('bones', {}).items():
                if bn in comp and 'scale' in bt:
                    for fr in bt['scale']:
                        for k in ('x', 'y', 'value'):
                            if k in fr:
                                fr[k] = round(fr[k] * root_scale_mult, 6)


if __name__ == '__main__':
    main()
