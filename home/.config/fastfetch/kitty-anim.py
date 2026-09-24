#!/usr/bin/env python3
# Pone la animación de Mochi en kitty con su protocolo de imágenes (sin kitten icat ni GIF):
# fotogramas PNG con transparencia suave (el GIF solo tiene todo-o-nada y los bordes salían a
# escalones). Se reproduce una vez y se queda en el último fotograma.
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
    frames = [l.strip() for l in open(path) if l.strip()]
    if not frames:
        return
    img = 1000 + os.getpid() % 100000   # id propio (varias kittys a la vez)
    with open("/dev/tty", "w") as out:
        out.write("\x1b7")                            # guardar el cursor
        out.write(f"\x1b[{row + 1};{col + 1}H")       # ir a la esquina del hueco
        # 1.º fotograma: transmitir y mostrar (q=2: sin respuestas; C=1: no mover el cursor;
        # c: ancho en celdas, el alto sale solo manteniendo la proporción)
        cmd(out, f"a=T,f=100,i={img},q=2,C=1,c={cols}", frames[0])
        for fr in frames[1:]:
            cmd(out, f"a=f,f=100,i={img},q=2,z={GAP}", fr)
        cmd(out, f"a=a,i={img},q=2,r=1,z={GAP}")     # hueco del primer fotograma
        out.write("\x1b8")                            # volver a dejar el cursor donde estaba
        out.flush()
        # esperar al momento justo y a reproducir una sola vez (v=2: una vuelta)
        wait = start - time.time()
        if wait > 0:
            time.sleep(min(wait, 15))
        cmd(out, f"a=a,i={img},q=2,s=3,v=2")
        out.flush()


if __name__ == "__main__":
    main()
