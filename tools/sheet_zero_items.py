#!/usr/bin/env python3
"""Contact sheets for the decoded ui/icon/items icons (96px cells, filename
labels) so Zero's partner-fragment icon can be located by eye."""
from pathlib import Path
from PIL import Image, ImageDraw

SRC = Path(__file__).resolve().parent.parent / 'render_work/zero_ui/items'
OUT = Path(__file__).resolve().parent.parent / 'render_work/zero_ui'
CELL = 110
COLS = 12
ROWS = 9

files = sorted(SRC.glob('*.png'))
print('icons:', len(files))
per_sheet = COLS * ROWS
for si in range(0, len(files), per_sheet):
    batch = files[si:si + per_sheet]
    sheet = Image.new('RGB', (COLS * CELL, ROWS * (CELL + 14)), (24, 24, 24))
    d = ImageDraw.Draw(sheet)
    for i, f in enumerate(batch):
        x = (i % COLS) * CELL
        y = (i // COLS) * (CELL + 14)
        try:
            im = Image.open(f).convert('RGBA')
            im.thumbnail((CELL - 4, CELL - 4))
            sheet.paste(im, (x + 2, y + 2), im)
        except Exception as e:
            d.text((x + 4, y + 40), 'ERR', fill='red')
        d.text((x + 3, y + CELL + 1), f.stem[:16], fill=(255, 255, 120))
    dst = OUT / f'items_sheet_{si // per_sheet + 1}.png'
    sheet.save(dst)
    print('saved', dst.name, len(batch))
