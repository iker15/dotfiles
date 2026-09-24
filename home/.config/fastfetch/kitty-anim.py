#!/usr/bin/env python3
# Pone la animación de Mochi en kitty con su protocolo de imágenes (sin kitten icat ni GIF):
# fotogramas PNG con transparencia suave (el GIF solo tiene todo-o-nada y los bordes salían a
# escalones). Se reproduce una vez y se queda en el último fotograma. Los fotogramas se van
# poniendo uno a uno desde aquí (en segundo plano), sustituyendo al anterior.
#   kitty-anim.py FOTOGRAMAS COL FILA [COLUMNAS] [EMPEZAR]
# EMPEZAR: momento (ms de época) en que debe arrancar; primero se mandan todos los fotogramas
# (tarda un poco) y se espera hasta entonces, para que vaya a la par con Mochi.
# FOTOGRAMAS: un PNG en base64 por línea (los pinta Mochi: ~/.cache/mochi/fetch.b64).
# COL/FILA: celda de arriba a la izquierda (0 = primera). COLUMNAS: ancho (22).
import os, sys, time

GAP = 40   # ms por fotograma (25 fps)


def cmd(out, keys, payload=""):
    """Un comando del protocolo, partido en trozos de 4096 como pide kitty."""
    if not payload:
        out.write(f"\x1b_G{keys}\x1b\\")
        return
    chunks = [payload[i:i + 4096] for i in range(0, len(payload), 4096)]
    for n, c in enumerate(chunks):
        more = 1 if n < len(chunks) - 1 else 0
        out.write(f"\x1b_G{keys if n == 0 else ''}{',' if n == 0 else ''}m={more};{c}\x1b\\")


def main():
    path, col, row = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    cols = int(sys.argv[4]) if len(sys.argv) > 4 else 22
    start = float(sys.argv[5]) / 1000 if len(sys.argv) > 5 else 0
    pngs = [l.strip() for l in open(path) if l.strip()]
    if not pngs:
        return
    img = 1000 + os.getpid() % 100000   # id propio (varias kittys a la vez)
    with open("/dev/tty", "w") as out:
        # esperar al momento justo
        wait = start - time.time()
        if wait > 0:
            time.sleep(min(wait, 15))
        # Fotograma a fotograma (25 fps): cada uno sustituye al anterior en el mismo sitio
        # (mismo id de imagen y de colocación). Con las animaciones del protocolo, kitty se
        # atascaba a mitad; así no depende de ellas. Se queda el último.
        t0 = time.time()
        for n, p in enumerate(pngs):
            out.write("\x1b7" + f"\x1b[{row + 1};{col + 1}H")
            cmd(out, f"a=T,f=100,i={img},p=1,q=2,C=1,c={cols}", p)
            out.write("\x1b8")
            out.flush()
            ahead = t0 + (n + 1) * GAP / 1000 - time.time()
            if ahead > 0:
                time.sleep(ahead)

if __name__ == "__main__":
    main()
