"""Generate the muzzle streak texture (soft horizontal beam) for the
attack FX port. UE original: Mi_Ling_Skill additive + ma_412_UV mask,
PSA_Velocity-aligned 50x150 stretched sprite. A soft white-core beam with
cyan-ish falloff reproduces the look without the base-pak texture.
"""
from PIL import Image
import math

W, H = 192, 48
img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
px = img.load()
for x in range(W):
    # longitudinal: sharp attack near the muzzle, long soft tail
    t = x / (W - 1)
    lon = (1.0 - t) ** 1.6
    for y in range(H):
        v = (y / (H - 1) - 0.5) * 2.0
        lat = math.exp(-(v * v) * 7.0)
        a = 255 * lon * lat
        # bluish-white core
        r = int(235 * lon * lat + 20 * (1 - lon))
        g = int(245 * lon * lat)
        b = 255
        px[x, y] = (min(r, 255), min(g, 255), min(b, 255), int(a))
img.save(r"D:/项目/dragonraja/sts2_work/DRCSpineDye/pcksrc/drc_dye/profiles/ling/animations/characters/silent/fx_streak.png")
print("fx_streak.png written")
