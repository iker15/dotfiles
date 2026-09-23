#!/usr/bin/env python3
# Mira la pantalla alrededor de Mochi y escribe dos cosas:
#   1. la luminancia media (0-1) del fondo a sus lados (para el color de los subtítulos)
#   2. el color real del marco de Caelestia junto a Mochi (#rrggbb), para elegir el color de ojos
# y guarda en OUT (ppm) el color del marco a lo largo de sus cuatro lados, para el shader.
# Uso: bg.py cx cy rx ry sx sy sw sh barw frame rounding [OUT]   (centro y radios de Mochi,
#      rectángulo de su pantalla, ancho de la barra, grosor y redondeo del borde)
import subprocess
import sys

cx, cy, rx, ry, sx, sy, sw, sh, barw, frame, rounding = map(float, sys.argv[1:12])
out = sys.argv[12] if len(sys.argv) > 12 else ""


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

# 2. El marco visto justo en la unión con el interior, a lo largo de los cuatro lados.
#    Se guarda como imagen de 4 filas (abajo, derecha, arriba, izquierda) que el shader usa
#    para pintar a Mochi exactamente del color del marco que tiene al lado (el marco es
#    cristal translúcido: su color cambia con el fondo).
#    Mochi está en una capa por encima de la de Caelestia, así que aquí no sale reflejado.
L, R, T, B = sx + barw, sx + sw - frame, sy + frame, sy + sh - frame
W = int(max(sw, sh))
depth = (3, 7)   # px dentro del marco (sin el antialiasing del borde)
strips = {
    0: ("h", sx, B + depth[0], sx + sw, B + depth[1]),   # abajo
    1: ("v", R + depth[0], sy, R + depth[1], sy + sh),   # derecha
    2: ("h", sx, T - depth[1], sx + sw, T - depth[0]),   # arriba
    3: ("v", L - depth[1], sy, L - depth[0], sy + sh),   # izquierda
}
lo = {0: L + rounding, 1: T + rounding, 2: L + rounding, 3: T + rounding}
hi = {0: R - rounding, 1: B - rounding, 2: R - rounding, 3: B - rounding}
rows = []
for k in range(4):
    kind, *box = strips[k]
    g = grab(*box)
    row = [(0, 0, 0)] * W
    if g:
        x0, y0, gw, gh, inv, data = g
        n = gw if kind == "h" else gh
        # un color por posición a lo largo del lado (media sobre el grosor)
        line = []
        for i in range(n):
            acc = [0, 0, 0]
            m = gh if kind == "h" else gw
            for j in range(m):
                o = ((j * gw + i) if kind == "h" else (i * gw + j)) * 3
                acc[0] += data[o]; acc[1] += data[o + 1]; acc[2] += data[o + 2]
            line.append([a / m for a in acc])
        # mediana móvil a lo largo (quita ojos, iconos sueltos…) y suavizado
        h = 12
        med = []
        for i in range(n):
            win = line[max(0, i - h):i + h + 1]
            med.append([sorted(c[ch] for c in win)[len(win) // 2] for ch in range(3)])
        base = (x0 - sx) if kind == "h" else (y0 - sy)
        first = sx if kind == "h" else sy
        for i in range(W):
            # en las esquinas redondeadas del marco se usa el color donde acaba la curva
            pos = min(max(first + i, lo[k]), hi[k])
            idx = int(min(max((pos - first) / inv - base / inv if inv else 0, 0), n - 1))
            row[i] = tuple(int(round(c)) for c in med[idx])
    rows.append(row)

if out:
    tmp = out + ".tmp"
    with open(tmp, "wb") as f:
        f.write(b"P6\n%d 4\n255\n" % W)
        for row in rows:
            f.write(bytes(v for c in row for v in c))
    import os
    os.replace(tmp, out)

# Color del marco junto a Mochi (para elegir ojos claros u oscuros)
dist = {0: B - cy, 1: R - cx, 2: cy - T, 3: cx - L}
side = min(dist, key=dist.get)
along = (cx - sx) if side in (0, 2) else (cy - sy)
seg = rows[side][int(max(0, along - rx)):int(min(W, along + rx)) + 1] or [(0, 0, 0)]
col = "#" + "".join(f"{sorted(c[ch] for c in seg)[len(seg) // 2]:02x}" for ch in range(3))

print(lum, col)
