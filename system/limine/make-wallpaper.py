#!/usr/bin/env python3
# Fondo del menú de arranque (Limine): negro como el splash de Plymouth, con Mochi dormido
# abajo a la derecha (el mismo dibujo que el tema de arranque). Uso: ./make-wallpaper.py [salida]
import os, sys
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "plymouth", "mochi"))
import gen  # noqa: E402

W, H = 1920, 1080
bg = Image.new("RGB", (W, H), (10, 10, 12))
# luz muy suave donde duerme
glow = Image.new("L", (W, H), 0)
ImageDraw.Draw(glow).ellipse([1300, 640, 1860, 1120], fill=38)
glow = glow.filter(ImageFilter.GaussianBlur(120))
bg = Image.composite(Image.new("RGB", (W, H), (40, 40, 48)), bg, glow)
# sombrita en el suelo
sh = Image.new("L", (W, H), 0)
ImageDraw.Draw(sh).ellipse([1580 - 120, 1000, 1580 + 120, 1030], fill=150)
sh = sh.filter(ImageFilter.GaussianBlur(10))
bg = Image.composite(Image.new("RGB", (W, H), (4, 4, 5)), bg, sh)
m = gen.frame(breath=0.3, open_=0.0)            # dormido
m = m.resize((330, 330), Image.LANCZOS)
base = 225 * 330 / 300                           # donde se apoya, en el dibujo
bg.paste(m, (1580 - 165, int(1016 - base)), m)
out = sys.argv[1] if len(sys.argv) > 1 else "mochi-limine.png"
bg.save(out)
print(out)
