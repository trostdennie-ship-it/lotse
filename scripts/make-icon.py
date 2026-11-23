#!/usr/bin/env python3
"""Zeichnet das App-Symbol von Lotse (Pixel-Segelboot auf Graphit) und baut daraus Resources/Lotse.icns.
Aufruf: python3 scripts/make-icon.py   (braucht Pillow und das macOS-Werkzeug iconutil)"""
import os, subprocess, shutil, sys
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOAT = ["......S.....",
        "......SS....",
        "......SSS...",
        "...s..SSSS..",
        "..ss..SSSSS.",
        ".sss..SSSSS.",
        "......M.....",
        "HHHHHHHHHHHH",
        ".HHHHHHHHHH.",
        "..hhhhhhhh..",
        "............",
        "w.ww.ww.ww.w"]
COLORS = {"S": (255, 240, 214), "s": (247, 190, 110), "M": (214, 204, 190),
          "H": (240, 160, 64), "h": (196, 118, 40), "w": (120, 132, 150)}

def icon(n=1024):
    k = 4                                   # überabgetastet zeichnen, dann verkleinern: glatte Kanten am Rahmen
    N = n * k
    im = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    side, r = int(N * 824 / 1024), int(N * 185 / 1024)
    x0 = (N - side) // 2
    # Fläche: Graphit-Verlauf von oben nach unten
    grad = Image.new("RGBA", (side, side))
    px = ImageDraw.Draw(grad)
    top, bottom = (58, 55, 52), (20, 19, 18)
    for y in range(side):
        t = y / (side - 1)
        px.line([(0, y), (side, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,))
    # warmer Schein hinter dem Boot
    glow = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([side * 0.18, side * 0.34, side * 0.82, side * 0.98], fill=(240, 160, 64, 70))
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
    cell = int(side * 0.062)
    gap = max(1, cell // 9)
    bx = (N - cols * cell) // 2
    by = (N - rows * cell) // 2 + int(cell * 0.2)
    for y, line in enumerate(BOAT):
        for x, c in enumerate(line):
            if c in COLORS:
                d.rounded_rectangle([bx + x * cell + gap, by + y * cell + gap, bx + (x + 1) * cell - gap, by + (y + 1) * cell - gap],
                                    radius=cell // 7, fill=COLORS[c] + (255,))
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
