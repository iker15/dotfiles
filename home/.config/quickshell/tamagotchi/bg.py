#!/usr/bin/env python3
# Luminancia media (0-1) del fondo a los lados de Mochi, para elegir si va en negro o en blanco.
# Uso: bg.py cx cy rx ry sx sy sw sh   (centro y radios de Mochi, rectángulo de su pantalla)
import subprocess
import sys

cx, cy, rx, ry, sx, sy, sw, sh = map(float, sys.argv[1:9])

# Franja a la altura del cuerpo, a izquierda y derecha (el bocadillo va arriba y no molesta)
x0, x1 = max(sx, cx - 2.6 * rx), min(sx + sw, cx + 2.6 * rx)
y0, y1 = max(sy, cy - ry), min(sy + sh, cy + ry * 0.8)
w, h = int(x1 - x0), int(y1 - y0)
if w <= 0 or h <= 0:
    sys.exit(1)

ppm = subprocess.run(["grim", "-g", f"{int(x0)},{int(y0)} {w}x{h}", "-t", "ppm", "-"],
                     capture_output=True, check=True).stdout

# Cabecera P6: "P6\nW H\n255\n"
parts = ppm.split(b"\n", 3)
W, H = map(int, parts[1].split())
data = parts[3]
scale = W / w

total = n = 0
for py in range(0, H, 2):
    row = py * W * 3
    for px in range(0, W, 2):
        # Saltarse a Mochi (el centro)
        if abs(x0 + px / scale - cx) < 1.35 * rx:
            continue
        i = row + px * 3
        total += 0.2126 * data[i] + 0.7152 * data[i + 1] + 0.0722 * data[i + 2]
        n += 1

if not n:
    sys.exit(1)
print(f"{total / n / 255:.3f}")
