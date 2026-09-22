#!/usr/bin/env python3
# Genera una versión OSCURA del esquema actual de Caelestia (mismos colores del
# fondo, pero en modo oscuro) para las apps que queremos siempre oscuras:
#   ~/.local/state/caelestia/dark/scheme.json    -> VS Code, colores de fish, ojo
#   ~/.local/state/caelestia/dark/sequences.txt  -> colores de los terminales
# Lo lanza caelestia-dark.path (systemd) cada vez que cambia scheme.json.
import json, os
from pathlib import Path

from caelestia.utils.paths import scheme_data_dir, wallpaper_thumbnail_path
from caelestia.utils.scheme import Scheme, read_colours_from_file
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
        from caelestia.utils.material import get_colours_for_image
        dark = Scheme({**s, "mode": "dark"})
        colours = get_colours_for_image(wallpaper_thumbnail_path, dark)
    else:
        path = scheme_data_dir / s["name"] / s["flavour"] / "dark.txt"
        if path.exists():
            colours = read_colours_from_file(path)

scheme = json.dumps({**s, "mode": "dark", "colours": colours})
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
