#!/usr/bin/env python3
# Mira la pantalla alrededor de Mochi y escribe dos cosas:
#   1. la luminancia media (0-1) del fondo a sus lados (para el color de los subtítulos)
#   2. el color real del marco de Caelestia en el lado más cercano (#rrggbb), para que Mochi
#      sea exactamente del mismo color que la barra/borde que tiene al lado
# Uso: bg.py cx cy rx ry sx sy sw sh barw frame   (centro y radios de Mochi, rectángulo de su
#      pantalla, ancho de la barra y grosor del borde)
import subprocess
import sys

cx, cy, rx, ry, sx, sy, sw, sh, barw, frame = map(float, sys.argv[1:11])


def grab(x0, y0, x1, y1):
    x0, x1 = max(sx, x0), min(sx + sw, x1)
    y0, y1 = max(sy, y0), min(sy + sh, y1)
    w, h = int(x1 - x0), int(y1 - y0)
    if w <= 0 or h <= 0:
        return None
    ppm = subprocess.run(["grim", "-g", f"{int(x0)},{int(y0)} {w}x{h}", "-t", "ppm", "-"],
                         capture_output=True, check=True).stdout
    parts = ppm.split(b"\n", 3)          # cabecera P6: "P6\nW H\n255\n"
    W, H = map(int, parts[1].split())
    return x0, y0, W, H, w / W if W else 1, parts[3]


# 1. Fondo a izquierda y derecha, a la altura del cuerpo (saltándose a Mochi)
lum = ""
g = grab(cx - 2.6 * rx, cy - ry, cx + 2.6 * rx, cy + ry * 0.8)
if g:
    x0, _, W, H, inv, data = g
    total = n = 0
    for py in range(0, H, 2):
        row = py * W * 3
        for px in range(0, W, 2):
            if abs(x0 + px * inv - cx) < 1.35 * rx:
                continue
            i = row + px * 3
            total += 0.2126 * data[i] + 0.7152 * data[i + 1] + 0.0722 * data[i + 2]
            n += 1
    if n:
        lum = f"{total / n / 255:.3f}"

# 2. Color del marco en el lado más cercano (mediana, en mitad del grosor del borde)
dist = {
    "left": cx - (sx + barw),
    "right": sx + sw - frame - cx,
    "top": cy - (sy + frame),
    "bottom": sy + sh - frame - cy,
}
side = min(dist, key=dist.get)
m = frame * 0.3
box = {
    "bottom": (cx - 60, sy + sh - frame + m, cx + 60, sy + sh - m),
    "top": (cx - 60, sy + m, cx + 60, sy + frame - m),
    "right": (sx + sw - frame + m, cy - 60, sx + sw - m, cy + 60),
    "left": (sx + 2, cy - 60, sx + 8, cy + 60),   # borde exterior de la barra (sin iconos)
}[side]
col = ""
g = grab(*box)
if g:
    _, _, W, H, _, data = g
    px = [tuple(data[i:i + 3]) for i in range(0, W * H * 3, 3)]
    if px:
        mid = len(px) // 2
        col = "#" + "".join(f"{sorted(c[k] for c in px)[mid]:02x}" for k in range(3))

print(lum, col)
