#!/usr/bin/env python3
# Convierte el ojo del pin a Braille (puntos) + tono por carácter (0-9).
# Uso: eye_prep.py imagen.jpg [columnas]   ->  ~/.config/fish/art/eye.map
import sys, os
from PIL import Image, ImageOps, ImageFilter

src = sys.argv[1]
COLS = int(sys.argv[2]) if len(sys.argv) > 2 else 72
im = Image.open(src).convert("L")
W0 = im.width
im = im.crop(tuple(round(v * W0 / 700) for v in (42, 108, 658, 404)))   # panel del ojo
im = im.filter(ImageFilter.GaussianBlur(1.6))                          # quita la trama original
dw = COLS * 2
dh = round(im.height * dw / im.width / 4) * 4
im = ImageOps.autocontrast(im.resize((dw, dh), Image.LANCZOS), cutoff=0.5)
im = im.point(lambda v: round(255 * (v / 255) ** 1.35))            # más contraste: iris y párpado más oscuros
tone_src = im.copy()
dots = im.convert("1").load()                                           # semitono (Floyd–Steinberg)
lum = tone_src.load()

BITS = [(0, 0, 0x01), (0, 1, 0x02), (0, 2, 0x04), (1, 0, 0x08),
        (1, 1, 0x10), (1, 2, 0x20), (0, 3, 0x40), (1, 3, 0x80)]
lines = []
for r in range(dh // 4):
    chars, tones = "", ""
    for c in range(COLS):
        v = sum(b for dx, dy, b in BITS if dots[c * 2 + dx, r * 4 + dy])
        m = sum(lum[c * 2 + dx, r * 4 + dy] for dx, dy, _ in BITS) / 8
        chars += chr(0x2800 + v)
        tones += str(min(9, int(m * 10 / 256)))
    lines.append(chars + "\t" + tones)
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "eye.map")
open(out, "w").write("\n".join(lines) + "\n")
print(COLS, "x", len(lines))
