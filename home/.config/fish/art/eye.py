#!/usr/bin/env python3
# Pinta eye.map con los colores del esquema actual de Caelestia:
# cada carácter Braille en un tono entre el fondo (surface) y el primario.
import json, os

here = os.path.dirname(os.path.abspath(__file__))
try:
    c = json.load(open(os.path.expanduser("~/.local/state/caelestia/dark/scheme.json")))["colours"]
    bg, fg = c["surface"], c["primary"]
except Exception:
    bg, fg = "0a0f0f", "9bd0cc"
bg = [int(bg[i:i + 2], 16) for i in (0, 2, 4)]
fg = [int(fg[i:i + 2], 16) for i in (0, 2, 4)]
pal = [";".join(str(round(b + (f - b) * (0.25 + 0.75 * t / 9))) for b, f in zip(bg, fg)) for t in range(10)]

for line in open(os.path.join(here, "eye.map")).read().splitlines():
    chars, tones = line.split("\t")
    s, cur = "  ", None
    for ch, t in zip(chars, tones):
        if ch != "⠀" and t != cur:
            s += f"\x1b[38;2;{pal[int(t)]}m"; cur = t
        s += ch if ch != "⠀" else " "
    print(s.rstrip() + "\x1b[0m")
