#!/usr/bin/env python3
"""Extract an asset out of the iguf hot-update volumes by package path.

Usage:
  python iguf_extract_asset.py <pkg/path> [-o OUT] [--png]

Resolves <pkg/path> through unpacked/hotupdate_manifest_full.json +
unpacked/iguf_units_final.json (index-aligned), reads the unit from
com.zulong.drc.gw/files/ingameupdate/iguf_0N.dat and decompresses it.

Unit layout (iguf 记录 §4/§10.1): [58af5a00][u32 span=decompressed][body].
Body = 4D25EDBC: [u16 ver][u32 total][u32 chunk][u32 dd][u32 dc];
  dd==0: [K u32 frame sizes][zstd frames]; dd>0: dict frame + table + frames.
BKHD/RIFF/bare units are stored raw.

--png: for Texture2D uexp payloads, additionally decode ASTC -> PNG next to
the output using build_ling_assets.decode_astc_texture (channel-order fixed).
"""
import json
import struct
import sys
from pathlib import Path

import zstandard

ROOT = Path(__file__).resolve().parent.parent
IGUF_DIR = ROOT / "com.zulong.drc.gw/files/ingameupdate"
MANIFEST = ROOT / "unpacked/hotupdate_manifest_full.json"
UNITS = ROOT / "unpacked/iguf_units_final.json"


def read_unit(vol_path, pos, stored):
    f = open(vol_path, "rb")
    f.seek(pos)
    head = f.read(8)
    if len(head) < 8:
        raise ValueError(f"short read at {pos}")
    magic, span = struct.unpack("<II", head)
    body = f.read(stored - 8)
    if magic == 0x005AAF58:
        # 4D25EDBC zstd block / bare stored unit share the [prefix][span] head;
        # bare units: body IS the data (span == len(body)).
        if body[:4] == bytes.fromhex("4d25edbc"):
            ver, total, chunk, dd, dc = struct.unpack("<HIIII", body[4:22])
            off = 22
            dctx = zstandard.ZstdDecompressor()
            out = bytearray()
            if dd:
                dict_frame = body[off:off + dc]
                dd2 = dctx.decompressobj().decompress(dict_frame)
                d = zstandard.ZstdDecompressor(
                    dict_data=zstandard.ZstdCompressionDict(dd2))
                off += dc
                n = (total + chunk - 1) // chunk
                table = struct.unpack(f"<{n}I", body[off:off + 4 * n])
                off += 4 * n
                for csz in table:
                    out += d.decompressobj().decompress(body[off:off + csz])
                    off += csz
            else:
                # dd==0: [K u32 sizes of frames 1..K][frame0 (dc bytes)][frames 1..K],
                # K = ceil(total/chunk) - 1 (iguf 记录 §10.1)
                K = (total + chunk - 1) // chunk - 1
                table = struct.unpack(f"<{K}I", body[off:off + 4 * K]) if K else ()
                off += 4 * K
                out += dctx.decompressobj().decompress(body[off:off + dc])
                off += dc
                for csz in table:
                    out += dctx.decompressobj().decompress(body[off:off + csz])
                    off += csz
            if len(out) != total:
                raise ValueError(f"decompressed {len(out)} != {total}")
            return bytes(out)
        return bytes(body)  # bare stored unit
    # WWise bank: no 58af5a00 prefix at pos per §4.2? Units are uniform here,
    # so reaching this branch means a bad (pos, stored) pair.
    raise ValueError(f"bad magic {magic:#x} at {pos}")


def main():
    pkg_path = sys.argv[1]
    out = None
    want_png = False
    args = sys.argv[2:]
    if "-o" in args:
        out = Path(args[args.index("-o") + 1])
    want_png = "--png" in args

    man = json.load(open(MANIFEST))
    idx = next((i for i, m in enumerate(man) if m[0] == pkg_path), None)
    if idx is None:
        raise SystemExit(f"{pkg_path} not in manifest")
    _path, stored = man[idx]
    vol, pos, stored_u, total = json.load(open(UNITS))[idx]
    if stored_u != stored:
        print(f"warn: manifest stored {stored} != unit stored {stored_u}")

    vol_path = IGUF_DIR / f"iguf_{vol:02d}.dat"
    data = read_unit(vol_path, pos, stored)
    print(f"{pkg_path}: vol={vol} pos={pos} stored={stored} -> {len(data)} B")

    if out is None:
        out = ROOT / "unpacked/iguf_out" / pkg_path.replace("/", "_")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(data)
    print(f"written {out}")

    if want_png:
        sys.path.insert(0, str(ROOT / "tools"))
        import os
        import tempfile
        from build_ling_assets import decode_astc_texture
        fd, tmp_name = tempfile.mkstemp(suffix=".uexp")
        os.close(fd)
        tmp = Path(tmp_name)
        tmp.write_bytes(data)
        _rgba, w, h, fmt = decode_astc_texture(tmp, out.with_suffix(".png"))
        tmp.unlink()
        print(f"png: {out.with_suffix('.png')} ({w}x{h}, {fmt})")


if __name__ == "__main__":
    main()
