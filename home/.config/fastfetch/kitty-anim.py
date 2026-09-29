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
# MOCHI_SHELL_PGRP: grupo de procesos de la fish del saludo. Si antes de acabar la terminal pasa a
# otro programa (p. ej. escribes `claude` rápido), se para y borra el cuadrado: si no, seguiría
# pintando fotogramas en esa fila por encima del programa nuevo.
# Si cierras la terminal antes (la tty cuelga), igual: se para y avisa a Mochi.
import os, signal, subprocess, sys, time

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
    ours = {os.getpgrp()}   # (mochi.sh, que aún puede estar en primer plano un momento)
    if os.environ.get("MOCHI_SHELL_PGRP", "").isdigit():
        ours.add(int(os.environ["MOCHI_SHELL_PGRP"]))
    with open("/dev/tty", "w") as out:
        def busy():
            """¿La terminal ya es de otro programa?"""
            if len(ours) < 2:
                return False
            try:
                return os.tcgetpgrp(out.fileno()) not in ours
            except OSError:
                return True

        def abort(placed):
            if placed:   # quita el cuadrado (y la imagen) de donde estaba
                try:
                    out.write(f"\x1b_Ga=d,d=I,i={img},q=2\x1b\\")
                    out.flush()
                except OSError:
                    pass   # (la terminal ya no está)
            # y el Mochi del escritorio no deja caer la gota sobre el programa nuevo
            subprocess.Popen(["qs", "-c", "tamagotchi", "ipc", "call", "pet", "cancelTerm"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        signal.signal(signal.SIGHUP, lambda *_: (abort(False), os._exit(0)))

        # esperar al momento justo (mirando si mientras tanto se lanza otra cosa)
        end = time.time() + min(max(start - time.time(), 0), 15)
        while time.time() < end:
            if busy():
                return abort(False)
            time.sleep(min(0.05, max(0, end - time.time())))
        # Fotograma a fotograma (25 fps): cada uno sustituye al anterior en el mismo sitio
        # (mismo id de imagen y de colocación). Con las animaciones del protocolo, kitty se
        # atascaba a mitad; así no depende de ellas. Se queda el último.
        t0 = time.time()
        for n, p in enumerate(pngs):
            if busy():
                return abort(n > 0)
            try:
                out.write("\x1b7" + f"\x1b[{row + 1};{col + 1}H")
                cmd(out, f"a=T,f=100,i={img},p=1,q=2,C=1,c={cols}", p)
                out.write("\x1b8")
                out.flush()
            except OSError:
                return abort(False)
            ahead = t0 + (n + 1) * GAP / 1000 - time.time()
            if ahead > 0:
                time.sleep(ahead)

if __name__ == "__main__":
    main()
