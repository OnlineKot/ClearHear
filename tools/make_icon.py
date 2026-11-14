#!/usr/bin/env python3
# Ikona: siedem bialych slupkow (fala glosu) na czarnym tle, srodkowy w kolorze apki.
# Zapisuje tez ikony na strone (hearnow/icons).
# Uzycie: python3 tools/make_icon.py  (z folderu hearnow-ios)

from pathlib import Path
from PIL import Image, ImageDraw

SIZE = 1024
SCALE = 4  # rysujemy 4x wiekszy i zmniejszamy, zeby krawedzie byly gladkie
S = SIZE * SCALE

img = Image.new("RGB", (S, S), (0, 0, 0))
d = ImageDraw.Draw(img)

heights = [0.18, 0.34, 0.54, 0.74, 0.54, 0.34, 0.18]   # dzwon, srodek najwyzszy
bar_w = S * 0.085
gap = S * 0.045
total = len(heights) * bar_w + (len(heights) - 1) * gap
x = (S - total) / 2
for i, h in enumerate(heights):
    bh = S * h * 0.78
    top = (S - bh) / 2
    color = (10, 132, 255) if i == 3 else (255, 255, 255)
    d.rounded_rectangle((x, top, x + bar_w, top + bh), radius=bar_w / 2, fill=color)
    x += bar_w + gap

root = Path(__file__).resolve().parent.parent
out = root / "HearNow/Assets.xcassets/AppIcon.appiconset/icon.png"
big = img.resize((SIZE, SIZE), Image.LANCZOS)
big.save(out)
print("zapisano", out)

site = root.parent / "hearnow/icons"
site.mkdir(parents=True, exist_ok=True)
for name, px in (("icon-512.png", 512), ("icon-192.png", 192), ("apple-touch-icon.png", 180)):
    big.resize((px, px), Image.LANCZOS).save(site / name)
    print("zapisano", site / name)
