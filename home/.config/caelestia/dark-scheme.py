#!/usr/bin/env python3
# Genera una versión OSCURA del esquema actual de Caelestia (mismos colores del
# fondo, pero en modo oscuro) para las apps que queremos siempre oscuras:
#   ~/.local/state/caelestia/dark/scheme.json    -> VS Code, colores de fish, ojo
#   ~/.local/state/caelestia/dark/sequences.txt  -> colores de los terminales
# Lo lanza caelestia-dark.path (systemd) cada vez que cambia scheme.json.
import json, os
from pathlib import Path

from caelestia.utils.paths import scheme_data_dir
from caelestia.utils.scheme import read_colours_from_file
from caelestia.utils.theme import gen_sequences

state = Path.home() / ".local/state/caelestia"
out_dir = state / "dark"

# Si la pantalla está bloqueada, scheme.json tiene los colores de la foto de
# perfil; el esquema real está guardado en scheme.wall.json
src = state / "scheme.wall.json"
if not src.exists():
    src = state / "scheme.json"
s = json.loads(src.read_text())

colours = s["colours"]
if s["mode"] != "dark":
    if s["name"] == "dynamic":
        from strict_scheme import colours as strict_colours  # mismo color que la shell
        colours = strict_colours("dark", s["flavour"])
    else:
        path = scheme_data_dir / s["name"] / s["flavour"] / "dark.txt"
        if path.exists():
            colours = read_colours_from_file(path)

# Fondos casi neutros: con fondos de pantalla muy coloridos el editor de VS Code
# quedaba teñido y costaba leer. Se limita la saturación (croma HCT) de los fondos,
# los acentos y el texto no se tocan.
from materialyoucolor.hct import Hct

MAX_CHROMA = 4
FONDOS = {"background", "base", "mantle", "crust", "surface0", "surface1", "surface2",
          "surfaceVariant", "outlineVariant", "term0"}
colours = dict(colours)
for k, v in colours.items():
    if k in FONDOS or (k.startswith("surface") and k != "surfaceTint"):
        c = Hct.from_int(int("ff" + v, 16))
        if c.chroma > MAX_CHROMA:
            colours[k] = f"{Hct.from_hct(c.hue, MAX_CHROMA, c.tone).to_int() & 0xffffff:06x}"

scheme =json.dumps({**s, "mode": "dark", "colours": colours})
sequences = gen_sequences(colours)

out_dir.mkdir(parents=True, exist_ok=True)
old = out_dir / "scheme.json"
if old.exists() and old.read_text() == scheme:
    raise SystemExit  # sin cambios

tmp = out_dir / "scheme.json.tmp"
tmp.write_text(scheme)
tmp.replace(old)
(out_dir / "sequences.txt").write_text(sequences)

# Aplicar a los terminales abiertos (igual que hace Caelestia)
for pt in Path("/dev/pts").iterdir():
    if pt.name.isdigit():
        try:
            fd = os.open(pt, os.O_WRONLY | os.O_NONBLOCK | os.O_NOCTTY)
            try:
                os.write(fd, sequences.encode())
            finally:
                os.close(fd)
        except OSError:
            pass
