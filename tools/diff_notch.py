"""Diff baseline vs each hidden-layer render; visualize each layer's actual
pixel contribution; zoom on the notch cell and report coverage inside it."""
from PIL import Image
import numpy as np
from pathlib import Path

D = Path('render_work/pdling_diff')
base = np.array(Image.open(D / 'f_00_baseline.png').convert('RGB')).astype(np.int16)
H, W = base.shape[:2]
# 缺口区域（渲染帧坐标，之前推算的缺口中心区域，放宽一点）
NX0, NX1, NY0, NY1 = 190, 330, 200, 330

vis = np.full((H, W, 3), 255, np.uint8)
colors = {'curtain': (255, 0, 0), 'silk_2': (0, 150, 0), 'silk_1': (0, 0, 255),
          'silk_1_BR': (255, 128, 0), 'silk_1_BL': (160, 0, 200),
          'windows_1': (0, 200, 200), 'windows_2': (200, 200, 0),
          'line': (255, 0, 255), 'air': (128, 128, 0), 'post_R_air': (0, 255, 255),
          'post_R': (100, 50, 0)}
print(f'notch cell = px x[{NX0},{NX1}] y[{NY0},{NY1}]  ({(NX1-NX0)*(NY1-NY0)} px)')
report = {}
f_base = Path(D / 'f_00_baseline.png')
for i, name in enumerate(colors):
    p = D / f'f_{i+1:02d}_{name}.png'
    if not p.exists():
        continue
    im = np.array(Image.open(p).convert('RGB')).astype(np.int16)
    diff = np.abs(im - base).sum(axis=2)
    contrib = diff > 24
    vis[contrib] = colors[name]
    innotch = int(contrib[NY0:NY1, NX0:NX1].sum())
    cell = (NX1 - NX0) * (NY1 - NY0)
    report[name] = innotch
    print(f'{name:12s} contribution in notch cell: {innotch:5d}/{cell} px ({innotch/cell:.0%})')
# 标缺口框
vis[NY0:NY1, NX0] = 0
vis[NY0:NY1, NX1-1] = 0
vis[NY0, NX0:NX1] = 0
vis[NY1-1, NX0:NX1] = 0
Image.fromarray(vis).save(D / 'layers_contribution.png')
print('saved layers_contribution.png')
