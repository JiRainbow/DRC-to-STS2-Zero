#!/usr/bin/env python3
"""Batch-extract + decode + contact-sheet the hotupdate ui/icon/items icons,
to locate Zero's partner-fragment item texture by eye."""
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
import iguf_extract_asset as IGA

MAN = json.load(open(ROOT / 'unpacked/hotupdate_manifest_full.json'))


def read_unit(vol_path, pos, stored):
    import zstandard
    data = open(vol_path, 'rb').read()
    magic = struct.unpack_from('<I', data, pos)[0]
    assert magic == 0x58af5a00, hex(magic)
    total = struct.unpack_from('<I', data, pos + 4)[0]
    body = data[pos + 8:pos + stored]
    dctx = zstandard.ZstdDecompressor()
    if struct.unpack_from('<I', body, 0)[0] == 0x34D25EDB:  # 4D25EDBC header
        ver, total_, chunk, dd, dc = struct.unpack_from('<HHIII', body, 4)
        off = 20
        out = b''
        if dd > 0:
            dd_len = struct.unpack_from('<I', body, off)[0]
            dctx.decompressobj().decompress(body[off + 4:off + 4 + dd_len])
            off += 4 + dd_len
            for _ in range(2):
                t_len = struct.unpack_from('<I', body, off)[0]
                off += 4 + t_len
            dctx2 = zstandard.ZstdDecompressor()
        else:
            K = (total_ + chunk - 1) // chunk - 1
            table = struct.unpack_from(f'<{K}I', body, off)[:K]
            off += 4 * K
            out += dctx.decompressobj().decompress(body[off:off + dc])
            off += dc
            for csz in table:
                out += dctx.decompressobj().decompress(body[off:off + csz])
                off += csz
        if len(out) != total_:
            raise ValueError(f'{len(out)} != {total_}')
        return out
    return body


def main():
    outdir = ROOT / 'render_work/zero_ui/items'
    outdir.mkdir(parents=True, exist_ok=True)
    targets = [(i, m[0]) for i, m in enumerate(MAN)
               if m[0].lower().startswith('ui/icon/items/') and m[0].endswith('.uexp')]
    print(f'targets: {len(targets)}')
    import tempfile
    sys.path.insert(0, str(ROOT / 'tools'))
    from build_ling_assets import decode_astc_texture
    ok, fail = 0, 0
    for idx, path in targets:
        name = Path(path).stem
        vol, pos, stored, total = json.load(open(IGA.UNITS))[idx]
        try:
            data = IGA.read_unit(IGA.IGUF_DIR / f'iguf_{vol:02d}.dat', pos, stored)
            fd, tmp = tempfile.mkstemp(suffix='.uexp')
            os.close(fd)
            Path(tmp).write_bytes(data)
            decode_astc_texture(Path(tmp), outdir / f'{name}.png')
            os.remove(tmp)
            ok += 1
        except Exception as e:
            fail += 1
            if fail <= 3:
                print(f'  fail {path}: {e}')
    print(f'decoded ok={ok} fail={fail}')


if __name__ == '__main__':
    main()
