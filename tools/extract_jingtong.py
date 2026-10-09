#!/usr/bin/env python3
"""Extract + decode the jingtong (镜瞳, Zero's exclusive qiling) card assets
from the hotupdate iguf, plus Zero's skill icons (urling001-004)."""
import json
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
import iguf_extract_asset as IGA
from build_ling_assets import decode_astc_texture

OUT = ROOT / 'render_work/zero_ui/final'
OUT.mkdir(parents=True, exist_ok=True)

man = __import__('json').load(open(IGA.MANIFEST))
targets = []
for i, m in enumerate(man):
    p = m[0].lower()
    if ('jingtong' in p and any(k in p for k in ('exclusive_card', 'exclusive_items'))) or \
       (p.startswith('ui/icon/skill/urling00') and p.endswith('.uexp')):
        targets.append((i, m[0]))
print(f'targets: {len(targets)}')

ok, fail = 0, 0
for idx, path in targets:
    vol, pos, stored, total = json.load(open(IGA.UNITS))[idx]
    try:
        data = IGA.read_unit(IGA.IGUF_DIR / f'iguf_{vol:02d}.dat', pos, stored)
        rel = path.replace('\\', '/').split('/')[-1]  # jingtong_color.uexp
        if path.endswith('-data.uexp') or path.endswith('.uexp'):
            kind = 'item'
        fd, tmp = tempfile.mkstemp(suffix='.uexp')
        os.close(fd)
        Path(tmp).write_bytes(data)
        # name: <set>_<variant>.png (set = exclusive_card/card_fight/items)
        parts = path.lower().split('/')
        setname = parts[2] if parts[1] == 'icon' else parts[1]
        base = Path(path).stem  # jingtong_color
        dst = OUT / f'启灵卡_{setname}_{base}.png'
        _, w, h, fmt = decode_astc_texture(Path(tmp), dst)
        os.remove(tmp)
        print(f'{dst.name} {w}x{h}')
        ok += 1
    except Exception as e:
        fail += 1
        print(f'  FAIL {path}: {e}')
print(f'ok={ok} fail={fail}')
