"""Extract the full hologram shader family (FS with pc2_h / 3 samplers, and
their VS) from the Zulong shadercode package - the authoritative sources for
the 1:1 gdshader port. Layout: [u32 unzipped][u8][u32 zipped][LZ4 @9]."""
import os
import re
from pathlib import Path

import lz4.block

ROOT = 'unpacked/res_shadercode/shadercode-afile-glsl_es3_1_android'
OUT = Path('render_work/holo_shaders')
OUT.mkdir(parents=True, exist_ok=True)

fs_hits = []   # fragment shaders with pc2_h
vs_hits = []   # vertex shaders with ORIGINAL_POSITION
n = 0
for sub in sorted(os.listdir(ROOT)):
    d0 = os.path.join(ROOT, sub)
    for fn in sorted(os.listdir(d0)):
        p = os.path.join(d0, fn)
        n += 1
        raw = open(p, 'rb').read()
        if len(raw) < 9 or len(raw) > 400000:
            continue
        try:
            out = lz4.block.decompress(raw[9:], uncompressed_size=800000)
        except Exception:
            continue
        if b'gl_Position' in out:
            if b'ORIGINAL_POSITION' in out:
                vs_hits.append((p, out))
        elif b'pc2_h' in out:
            fs_hits.append((p, out))
print(f"scanned {n}: fs(pc2_h)={len(fs_hits)} vs(ORIGINAL_POSITION)={len(vs_hits)}")

# group FS by uniform signature, dedupe identical sources
seen = {}
for p, out in fs_hits:
    key = out
    seen.setdefault(key, []).append(p)
print(f"unique FS: {len(seen)}")
for i, (key, ps) in enumerate(sorted(seen.items(), key=lambda kv: -len(kv[1]))):
    (OUT / f'holo_fs_{i:02d}.glsl').write_bytes(key)
    if i < 12:
        unis = re.findall(rb'uniform \w+ \w+\[\d+\];', key)
        texs = re.findall(rb'uniform \w+ sampler2D (\w+);', key)
        print(f"  holo_fs_{i:02d}: copies={len(ps)} size={len(key)} tex={texs} unis={unis}")

vseen = {}
for p, out in vs_hits:
    vseen.setdefault(out, []).append(p)
print(f"unique VS(ORIGINAL): {len(vseen)}")
for i, (key, ps) in enumerate(sorted(vseen.items(), key=lambda kv: -len(kv[1]))[:10]):
    (OUT / f'holo_vs_{i:02d}.glsl').write_bytes(key)
    if i < 10:
        unis = re.findall(rb'uniform \w+ \w+\[\d+\];', key)
        print(f"  holo_vs_{i:02d}: copies={len(ps)} size={len(key)} unis={unis}")
