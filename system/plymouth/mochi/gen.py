#!/usr/bin/env python3
# Genera los fotogramas del tema de arranque de Mochi (Plymouth, módulo two-step):
#   throbber-NN.png  → en bucle mientras arranca: Mochi dormido, respirando
#   animation-NN.png → al terminar (una vez): abre los ojos poco a poco, parpadea, mira a los
#                      lados y se pone contento
# Solo cuerpo y ojos, como el Mochi del escritorio. Uso: ./gen.py (en esta carpeta)
import math
from PIL import Image, ImageDraw

SIZE, SS = 300, 4                       # tamaño final y supersampling
BODY = (220, 216, 213, 255)             # color del cuerpo (claro sobre el negro del arranque)
INK = (28, 27, 27, 255)                 # ojos
RX, RY_TOP, RY_BOT = 78, 74, 58         # daifuku: cúpula arriba, base más plana
BASE_Y = 225                            # donde se apoya
U = RX / 32                             # escala respecto al Mochi del escritorio
D = 9.5 * U                             # tamaño del ojo


def ease(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


def frame(breath=0.0, open_=1.0, look=0.0, happy=0.0, hop=0.0, stretch=0.0):
    im = Image.new("RGBA", (SIZE * SS, SIZE * SS), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    s = SS
    sx = 1 + 0.035 * breath - 0.05 * stretch
    sy = 1 - 0.035 * breath + 0.08 * stretch
    base = BASE_Y - hop
    cx = SIZE / 2
    cy = base - RY_BOT * sy
    pts = []
    for i in range(240):
        a = 2 * math.pi * i / 240
        ry = RY_TOP if math.sin(a) < 0 else RY_BOT
        pts.append(((cx + RX * sx * math.cos(a)) * s, (cy + ry * sy * math.sin(a)) * s))
    dr.polygon(pts, fill=BODY)

    ey = cy - 0.12 * RY_TOP * sy
    for side in (-1, 1):
        ex = cx + side * 11.5 * U * sx + look * 6 * U
        if happy > 0.5:
            # ^ ^: media luna hacia arriba
            w = D * 1.25
            box = [(ex - w / 2) * s, (ey - D * 0.35) * s, (ex + w / 2) * s, (ey + D * 0.95) * s]
            dr.arc(box, 200, 340, fill=INK, width=int(D * 0.32 * s))
            continue
        if open_ < 0.08:
            # dormido: una rayita
            w, h = D * 1.2, D * 0.16
            dr.rounded_rectangle([(ex - w / 2) * s, (ey - h / 2 + D * 0.15) * s, (ex + w / 2) * s, (ey + h / 2 + D * 0.15) * s],
                                 radius=h / 2 * s, fill=INK)
            continue
        # abierto (el párpado de arriba baja según open_)
        w, h = D, D
        top = ey - h / 2 + (1 - open_) * h
        r = min(w, ey + h / 2 - top) / 2
        dr.rounded_rectangle([(ex - w / 2) * s, top * s, (ex + w / 2) * s, (ey + h / 2) * s], radius=r * s, fill=INK)
    return im.resize((SIZE, SIZE), Image.LANCZOS)


# Dormido, respirando (bucle de 100 fotogramas)
N = 100
for i in range(N):
    b = 0.5 - 0.5 * math.cos(2 * math.pi * i / N)
    frame(breath=b, open_=0).save(f"throbber-{i:02d}.png")

# Se despierta (90 fotogramas)
frames = []
for i in range(90):
    b = 0.5 - 0.5 * math.cos(2 * math.pi * min(i, 10) / N)
    if i < 10:
        f = dict(breath=b, open_=0)
    elif i < 42:                                   # abre los ojos poco a poco y se estira
        k = ease((i - 10) / 32)
        f = dict(open_=0.1 + 0.9 * k, stretch=math.sin(math.pi * k) * 0.8)
    elif i < 50:                                   # parpadeo
        k = (i - 42) / 8
        f = dict(open_=1 - math.sin(math.pi * k))
    elif i < 66:                                   # mira a un lado y al otro
        k = (i - 50) / 16
        f = dict(open_=1, look=math.sin(2 * math.pi * k) * 0.9)
    else:                                          # contento, con un saltito
        k = (i - 66) / 23
        f = dict(open_=1, happy=1, hop=math.sin(math.pi * min(1, k * 1.6)) * 14 if k < 0.62 else 0)
    frame(**f).save(f"animation-{i:02d}.png")
print("ok")
