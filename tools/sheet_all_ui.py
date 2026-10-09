#!/usr/bin/env python3
"""Contact sheets for ALL decoded UI textures, grouped by directory.
Priority set: filenames containing 'bg' (most likely to hold the skin-page
backdrop). Sheets: 110px cells, 12x9, labeled with short file path."""
import os
from pathlib import Path
from PIL import Image, ImageDraw

SRC = Path(__file__).resolve().parent.parent / 'render_work/ui_all'
OUT = Path(__file__).resolve().parent.parent / 'render_work/ui_all_sheets'
OUT.mkdir(parents=True, exist_ok=True)
CELL = 110
COLS = 12
ROWS = 9


def sheet(files, name):
    files = sorted(files)
    per = COLS * ROWS
    made = 0
    for si in range(0, len(files), per):
        batch = files[si:si + per]
        img = Image.new('RGB', (COLS * CELL, ROWS * (CELL + 13)), (24, 24, 24))
        d = ImageDraw.Draw(img)
        for i, f in enumerate(batch):
            x = (i % COLS) * CELL
            y = (i // COLS) * (CELL + 13)
            try:
                im = Image.open(f).convert('RGBA')
                im.thumbnail((CELL - 4, CELL - 4))
                img.paste(im, (x + 2, y + 2), im)
            except Exception:
                d.text((x + 4, y + 40), 'ERR', fill='red')
            rel = str(f.relative_to(SRC)).replace('/', '_')
            d.text((x + 3, y + CELL), rel[-24:], fill=(255, 255, 120))
        dst = OUT / f'{name}_{si // per + 1:02}.png'
        img.save(dst)
        made += 1
    print(f'{name}: {len(files)} icons -> {made} sheets')


def main():
    all_png = [p for p in SRC.rglob('*.png')]
    print('total decoded:', len(all_png))
    bg = [p for p in all_png if 'bg' in p.name.lower()]
    sheet(bg, 'bg_priority')
    # the rest grouped by grandparent dir
    rest = [p for p in all_png if p not in bg]
    groups = {}
    for p in rest:
        rel = p.relative_to(SRC)
        parts = rel.parts[:-1]
        key = '_'.join(parts[:3])[:40] or 'root'
        groups.setdefault(key, []).append(p)
    for key, files in sorted(groups.items()):
        if len(files) < 6:
            continue
        sheet(files, 'grp_' + key)


if __name__ == '__main__':
    main()
