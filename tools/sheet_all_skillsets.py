#!/usr/bin/env python3
"""Decode the FIRST icon of every 3-icon skill set in ui/icon/skill and build
a labeled contact sheet - to locate base Zero's set (精准射击 pistol style)."""
import json
import os
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
import iguf_extract_asset as IGA
from build_ling_assets import decode_astc_texture
from PIL import Image, ImageDraw

man = json.load(open(IGA.MANIFEST))
units = json.load(open(IGA.UNITS))
by_path = {m[0]: i for i, m in enumerate(man)}

sets = {}
for i, m in enumerate(man):
    p = m[0]
    if not p.startswith('ui/icon/skill/') or not p.endswith('.uexp'):
        continue
    stem = Path(p).stem
    mm = re.match(r'([a-z_]+?)(\d+)$', stem)
    if not mm:
        continue
    sets.setdefault(mm.group(1), []).append((int(mm.group(2)), i, p))

CELL = 132
COLS = 10
out = ROOT / 'render_work/zero_ui/skillsets'
out.mkdir(parents=True, exist_ok=True)

keys = sorted(k for k, v in sets.items() if len(v) >= 3)
print('sets >=3 icons:', len(keys))
per_sheet = COLS * 8
for si in range(0, len(keys), per_sheet):
    batch = keys[si:si + per_sheet]
    sheet = Image.new('RGB', (COLS * CELL, 8 * (CELL + 14)), (24, 24, 24))
    d = ImageDraw.Draw(sheet)
    for i, k in enumerate(batch):
        first = min(sets[k])
        idx, p = first[1], first[2]
        x = (i % COLS) * CELL
        y = (i // COLS) * (CELL + 14)
        try:
            vol, pos, stored, total = units[idx]
            data = IGA.read_unit(IGA.IGUF_DIR / f'iguf_{vol:02d}.dat', pos, stored)
            fd, tmp = tempfile.mkstemp(suffix='.uexp')
            os.close(fd)
            Path(tmp).write_bytes(data)
            dst = out / f'{k}.png'
            decode_astc_texture(Path(tmp), dst)
            os.remove(tmp)
            im = Image.open(dst).convert('RGBA')
            im.thumbnail((CELL - 4, CELL - 4))
            sheet.paste(im, (x + 2, y + 2), im)
        except Exception as e:
            d.text((x + 4, y + 50), 'ERR', fill='red')
        d.text((x + 3, y + CELL + 1), k, fill=(255, 255, 120))
    dst = out / f'skillsets_sheet_{si // per_sheet + 1}.png'
    sheet.save(dst)
    print('saved', dst.name, len(batch))
