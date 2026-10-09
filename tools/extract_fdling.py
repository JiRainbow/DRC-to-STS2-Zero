#!/usr/bin/env python3
"""Extract + decode all fd_ling00N fightdrawing (皮肤展示画) packages from
the hotupdate iguf: data/atlas for reference, textures as PNG pages."""
import json
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
import iguf_extract_asset as IGA
from build_ling_assets import decode_astc_texture, extract_atlas

man = json.load(open(ROOT / 'unpacked/hotupdate_manifest_full.json'))
out = ROOT / 'render_work/zero_ui/fd'
units = json.load(open(IGA.UNITS))

targets = [(i, m[0]) for i, m in enumerate(man)
           if '/fd_ling' in m[0].replace('\\', '/').lower() and m[0].endswith('.uexp')]
print('targets:', len(targets))

from collections import defaultdict
groups = defaultdict(list)
for idx, path in targets:
    rel = path.replace('\\', '/')
    key = rel.split('/')[2]  # fd_ling00N
    groups[key].append((idx, rel))

for key, items in sorted(groups.items()):
    for idx, rel in items:
        vol, pos, stored, total = units[idx]
        data = IGA.read_unit(IGA.IGUF_DIR / f'iguf_{vol:02d}.dat', pos, stored)
        dst = out / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(data)
    print(key, 'extracted', len(items))

# decode textures + dump atlas text per group
for key, items in sorted(groups.items()):
    for idx, rel in items:
        p = out / rel
        if '/textures/' in rel:
            png = p.with_suffix('.png')
            try:
                _, w, h, fmt = decode_astc_texture(p, png)
                print(f'  {rel}: {w}x{h} {fmt}')
            except Exception as e:
                print(f'  {rel}: decode fail {e}')
        elif rel.endswith('-atlas.uexp'):
            try:
                t = extract_atlas(p)
                (p.with_suffix('.atlas.txt')).write_text(t, encoding='utf-8')
            except Exception as e:
                print(f'  {rel}: atlas fail {e}')
