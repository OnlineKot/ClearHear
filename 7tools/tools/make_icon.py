#!/usr/bin/env python3
# Ikona: lufa jak z filmow o agencie (pierscien, nacięcia) i zlota siodemka. Rysuje tez ikony na strone.
# Uzycie: python3 tools/make_icon.py  (z folderu 7tools; strone zapisuje do ../../FastLink/7tools/icons jesli istnieje)

import math
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

SIZE = 1024
SCALE = 3
S = SIZE * SCALE
GOLD = (224, 184, 77)

img = Image.new("RGB", (S, S), (0, 0, 0))
glow = Image.new("RGB", (S, S), (0, 0, 0))
d = ImageDraw.Draw(img)
g = ImageDraw.Draw(glow)
c = S / 2
R = S * 0.40

def ring(draw, r, w, col):
    draw.ellipse((c - r, c - r, c + r, c + r), outline=col, width=int(w))

ring(g, R, S * 0.02, GOLD)
glow = glow.filter(ImageFilter.GaussianBlur(S * 0.018))
img = Image.blend(img, glow, 0.0)
img.paste(glow, (0, 0), glow.convert("L"))
d = ImageDraw.Draw(img)

ring(d, R, S * 0.014, (255, 255, 255))
ring(d, R * 0.86, S * 0.004, (255, 255, 255))
# nacięcia gwintu
for i in range(14):
    a = i / 14 * 2 * math.pi
    x0, y0 = c + math.cos(a) * R * 0.2, c + math.sin(a) * R * 0.2
    x1, y1 = c + math.cos(a + 0.5) * R * 0.84, c + math.sin(a + 0.5) * R * 0.84
    d.line((x0, y0, x1, y1), fill=(80, 80, 80), width=int(S * 0.0035))

# siodemka
font = None
for name in ("DejaVuSans-Bold.ttf", "Arial Bold.ttf", "Helvetica.ttc"):
    try:
        font = ImageFont.truetype(name, int(S * 0.5))
        break
    except OSError:
        continue
if font is None:
    font = ImageFont.load_default()
bbox = d.textbbox((0, 0), "7", font=font)
w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
d.text((c - w / 2 - bbox[0], c - h / 2 - bbox[1]), "7", font=font, fill=GOLD)

root = Path(__file__).resolve().parent.parent
big = img.resize((SIZE, SIZE), Image.LANCZOS)
out = root / "SevenTools/Assets.xcassets/AppIcon.appiconset/icon.png"
big.save(out)
print("zapisano", out)

site = Path(sys.argv[1]) if len(sys.argv) > 1 else None
if site:
    site.mkdir(parents=True, exist_ok=True)
    for name, px in (("icon-512.png", 512), ("icon-192.png", 192), ("apple-touch-icon.png", 180)):
        big.resize((px, px), Image.LANCZOS).save(site / name)
        print("zapisano", site / name)
