#!/usr/bin/env python3
"""Zeichnet das App-Symbol von Lotse (Pixel-Segelboot im Feinraster auf Tiefsee-Blau) und baut daraus Resources/Lotse.icns.
Aufruf: python3 scripts/make-icon.py   (braucht Pillow und das macOS-Werkzeug iconutil)"""
import os, subprocess, shutil, sys
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def boat():
    """Das Boot im Feinraster, 24 Spalten: Großsegel rechts vom Mast, Vorsegel links, Rumpf, zwei Reihen Wellen."""
    g = [["."] * 24 for _ in range(22)]
    for r in range(1, 13):                                  # Großsegel
        for c in range(12, 12 + max(1, round(r * 8 / 12))): g[r][c] = "S"
    for r in range(5, 13):                                  # Vorsegel
        for c in range(11 - min(6, r - 4), 11): g[r][c] = "s"
    for r in range(14):                                     # Mast
        g[r][11] = "M"
    for r, (a, b) in zip(range(14, 18), ((2, 21), (3, 20), (4, 19), (6, 17))):
        for c in range(a, b + 1): g[r][c] = "h" if r == 17 else "H"
    for c in range(24):                                     # Wellen
        g[20 if c % 3 == 1 else 21][c] = "w"
    return ["".join(row) for row in g]

BOAT = boat()
COLORS = {"S": (255, 255, 255), "s": (170, 230, 225), "M": (200, 215, 230),
          "H": (255, 186, 96), "h": (240, 140, 70), "w": (120, 200, 215)}

def icon(n=1024):
    k = 4                                   # überabgetastet zeichnen, dann verkleinern: glatte Kanten am Rahmen
    N = n * k
    im = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    side, r = int(N * 824 / 1024), int(N * 185 / 1024)
    x0 = (N - side) // 2
    # Fläche: Verlauf von Nachtblau oben zu Petrol unten („Tiefsee")
    grad = Image.new("RGBA", (side, side))
    px = ImageDraw.Draw(grad)
    top, bottom = (30, 36, 96), (8, 92, 110)
    for y in range(side):
        t = y / (side - 1)
        px.line([(0, y), (side, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,))
    # heller Schein im Wasser unter dem Boot
    glow = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([side * 0.18, side * 0.34, side * 0.82, side * 0.98], fill=(60, 220, 200, 80))
    grad = Image.alpha_composite(grad, glow.filter(ImageFilter.GaussianBlur(side * 0.11)))
    mask = Image.new("L", (side, side), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, side - 1, side - 1], radius=r, fill=255)
    # weicher Schatten unter der Fläche
    shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 110), (x0, x0 + int(N * 0.012)), mask)
    im = Image.alpha_composite(im, shadow.filter(ImageFilter.GaussianBlur(N * 0.012)))
    im.paste(grad, (x0, x0), mask)
    # feine helle Kante oben
    edge = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle([x0, x0, x0 + side - 1, x0 + side - 1], radius=r, outline=(255, 255, 255, 38), width=max(2, N // 512))
    im = Image.alpha_composite(im, edge)
    # das Boot, Punkt für Punkt
    d = ImageDraw.Draw(im)
    cols, rows = len(BOAT[0]), len(BOAT)
    cell = int(side * 0.0376)
    gap = max(1, round(cell * 0.145))
    bx = (N - cols * cell) // 2
    by = (N - rows * cell) // 2 + int(cell * 0.3)
    for y, line in enumerate(BOAT):
        for x, c in enumerate(line):
            if c in COLORS:
                d.rounded_rectangle([bx + x * cell + gap, by + y * cell + gap, bx + (x + 1) * cell - gap, by + (y + 1) * cell - gap],
                                    radius=cell // 6, fill=COLORS[c] + (255,))
    return im.resize((n, n), Image.LANCZOS)

def main():
    out = os.path.join(ROOT, "Resources")
    os.makedirs(out, exist_ok=True)
    big = icon()
    big.save(os.path.join(out, "Lotse-Symbol.png"))
    iconset = os.path.join(out, "Lotse.iconset")
    shutil.rmtree(iconset, ignore_errors=True)
    os.makedirs(iconset)
    for size in (16, 32, 128, 256, 512):
        big.resize((size, size), Image.LANCZOS).save(os.path.join(iconset, f"icon_{size}x{size}.png"))
        big.resize((size * 2, size * 2), Image.LANCZOS).save(os.path.join(iconset, f"icon_{size}x{size}@2x.png"))
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", os.path.join(out, "Lotse.icns")], check=True)
    shutil.rmtree(iconset)
    print("Geschrieben:", os.path.join(out, "Lotse.icns"))

if __name__ == "__main__":
    main()
