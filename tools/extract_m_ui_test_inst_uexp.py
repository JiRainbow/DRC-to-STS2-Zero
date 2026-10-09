#!/usr/bin/env python3
"""One-shot: cut m_ui_test_inst.uexp out of iguf_00.dat (unit f0 pos=105855574).

Unit layout (iguf 记录 §12): [58af5a00][u32 span=decompressed][body].
Body = 4D25EDBC: [u16 ver][u32 total][u32 chunk][u32 dd][u32 dc]...
  dd==0: [K u32 frame sizes][zstd frames];  dd>0: dict frame + table + frames.
"""
import os
import struct

import zstandard

VOL = r"D:\项目\dragonraja\com.zulong.drc.gw\files\ingameupdate\iguf_00.dat"
OUT = r"D:\项目\dragonraja\unpacked\spinemats\m_ui_test_inst.uexp"
POS = 105855574
STORED = 5963

f = open(VOL, "rb")
f.seek(POS)
magic, span = struct.unpack("<II", f.read(8))
assert magic == 0x005AAF58, f"bad magic {magic:#x}"
body = f.read(STORED - 8)
assert body[:4] == bytes.fromhex("4d25edbc"), "expected 4D25EDBC block"
ver, total, chunk, dd, dc = struct.unpack("<HIIII", body[4:22])
print(f"block ver={ver} total={total} chunk={chunk} dd={dd} dc={dc} (span={span})")
off = 22
dctx = zstandard.ZstdDecompressor()
if dd:
    dict_frame = body[off:off + dc]
    dd2 = dctx.decompressobj().decompress(dict_frame)
    d = zstandard.ZstdDecompressor(dict_data=zstandard.ZstdCompressionDict(dd2))
    off += dc
    n = (total + chunk - 1) // chunk
    table = struct.unpack(f"<{n}I", body[off:off + 4 * n])
    off += 4 * n
    out_buf = bytearray()
    for csz in table:
        out_buf += d.decompressobj().decompress(body[off:off + csz])
        off += csz
else:
    out_buf = bytearray()
    out_buf += dctx.decompressobj().decompress(body[off:off + dc])
    off += dc
assert len(out_buf) == total, f"decompressed {len(out_buf)} != {total}"
with open(OUT, "wb") as w:
    w.write(out_buf)
print(f"written {OUT} ({len(out_buf)} B)")
