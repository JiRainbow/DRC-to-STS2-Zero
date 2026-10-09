#!/usr/bin/env python3
"""Find the compiled GLSL of RTGlobalShadowMat: slide the uexp bytes, take
20-byte windows, and match them against the shadercode library file names
(the Zulong material->shader binding method, same as the dissolution
material work). Then dump the matched GLSL sources.
"""
import os
import sys
from pathlib import Path

UEXP = Path('unpacked/res_parentmaterials/materialmasters/rtglobalshadowmat.uexp')
ROOT = 'unpacked/res_shadercode/shadercode-afile-glsl_es3_1_android'
OUT = Path('render_work/rtshadow_shaders')
OUT.mkdir(parents=True, exist_ok=True)

uexp = UEXP.read_bytes()
print(f"uexp: {len(uexp)} B")

# the shadercode library: .ushaderbytecode filenames = <40-hex hash>; the
# GLSL dumps are unique_uNNNNNN.glsl keyed by shaders_index.csv
names = {}
import csv
with open('unpacked/reversed/shaders/shaders_index.csv', newline='', encoding='utf-8') as f:
    for row in csv.DictReader(f):
        stem = Path(row['file']).stem  # <40-hex>
        names[stem] = (row['unique_id'], row['kind'], row['file'])
print(f"shadercode entries: {len(names)}")

hits = []
uexp_hex = uexp.hex()
W = 40  # 20 bytes = 40 hex chars
for i in range(0, len(uexp) - W):
    seg = uexp_hex[i * 2:i * 2 + W]
    if seg in names:
        hits.append((i, seg, names[seg]))

print(f"name matches: {len(hits)}")
for i, h, (uid, kind, file) in hits:
    print(f"  @uexp+{i:#x} {h} -> {uid} {kind}")

seen = set()
for i, h, (uid, kind, file) in hits:
    glsl = Path('unpacked/reversed/shaders/unique') / f"{uid}.glsl"
    out = glsl.read_bytes()
    if out in seen:
        continue
    seen.add(out)
    dst = OUT / f"{uid}_{kind}.glsl"
    dst.write_bytes(out)
    print(f"  dumped {dst} ({len(out)} B)")
