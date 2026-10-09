#!/usr/bin/env python3
"""Decode EVERY UI texture (base ui.png container + hotupdate iguf ui/*) to
PNG, then build labeled contact sheets grouped by directory, so the skin-page
UI backdrop can be located by eye."""
import json
import os
import struct
import sys
import tempfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
import azpack_extract as AZ  # noqa: E402
import iguf_extract_asset as IGA  # noqa: E402
from build_ling_assets import decode_astc_texture  # noqa: E402

OUT = ROOT / 'render_work/ui_all'
OUT.mkdir(parents=True, exist_ok=True)


def norm(name):
    return name.replace(chr(92), '/')


def base_ui_textures():
    data = (ROOT / 'unpacked/apk/assets/res_base/package/ui.png').read_bytes()
    eof = len(data)
    idx_off = struct.unpack_from('<I', data, eof - 0x114)[0] ^ AZ.KEY
    count = struct.unpack_from('<I', data, eof - 0x08)[0]
    pos = idx_off
    out = []
    for _ in range(count):
        zsize = struct.unpack_from('<I', data, pos)[0] ^ AZ.KEY
        blob = zlib.decompress(data[pos + 8:pos + 8 + zsize])
        pos += 8 + zsize
        name = norm(blob[:0x100].split(b'\x00')[0].decode('utf-8', 'replace'))
        f0, offset, f2, size, csize, f5 = struct.unpack_from('<6I', blob, 0x100)
        if name.endswith('.uexp') and '_atlas' not in name:
            out.append((name, offset, size, csize))
    # decode inline
    got = []
    gap_dicts = AZ.load_gap_dicts(data, [(o, o + c) for _, o, _, c in out])
    for name, offset, size, csize in out:
        blob = data[offset:offset + csize]
        try:
            if csize == size:
                raw = blob
            elif blob[:4] == AZ.BLOCK_MAGIC:
                raw = AZ.decode_zstd_block(blob, size, gap_dicts)
            elif blob[:1] == b'\x78':
                raw = zlib.decompress(blob)
            else:
                continue
            dst = OUT / ('base_' + norm(name)[:-5] + '.png')
            dst.parent.mkdir(parents=True, exist_ok=True)
            fd, tmp = tempfile.mkstemp(suffix='.uexp')
            os.close(fd)
            Path(tmp).write_bytes(raw)
            try:
                decode_astc_texture(Path(tmp), dst)
                got.append(str(dst.relative_to(OUT)))
            except Exception:
                pass
            os.remove(tmp)
        except Exception:
            continue
    print(f'base decoded: {len(got)}')
    return got


def hot_ui_textures():
    man = json.load(open(ROOT / 'unpacked/hotupdate_manifest_full.json'))
    units = json.load(open(ROOT / 'unpacked/iguf_units_final.json'))
    targets = [(i, m[0]) for i, m in enumerate(man)
               if m[0].lower().startswith('ui/') and m[0].endswith('.uexp') and '_atlas' not in m[0]]
    print(f'hot targets: {len(targets)}')
    got = []
    fail = 0
    for idx, path in targets:
        rel = norm(path)[:-5]
        dst = OUT / ('hot_' + rel + '.png')
        if dst.exists():
            got.append(str(dst.relative_to(OUT)))
            continue
        dst.parent.mkdir(parents=True, exist_ok=True)
        try:
            vol, pos, stored, total = units[idx]
            data = IGA.read_unit(IGA.IGUF_DIR / f'iguf_{vol:02d}.dat', pos, stored)
            fd, tmp = tempfile.mkstemp(suffix='.uexp')
            os.close(fd)
            Path(tmp).write_bytes(data)
            decode_astc_texture(Path(tmp), dst)
            os.remove(tmp)
            got.append(str(dst.relative_to(OUT)))
        except Exception:
            fail += 1
    print(f'hot decoded: {len(got)} fail={fail}')
    return got


if __name__ == '__main__':
    base_ui_textures()
    hot_ui_textures()
