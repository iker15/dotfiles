#!/usr/bin/env python3
# Colores "estrictos" del fondo: Caelestia saca el color de una miniatura borrosa
# (sale apagado); aquí lo saca matugen de la imagen a resolución completa y se usa
# scheme-fidelity, que conserva la saturación real. Se reescribe scheme.json, así que
# la shell, VS Code y kitty (vía dark-scheme.py) cogen los mismos colores que Zen.
# Lo lanza Caelestia al cambiar de fondo (postHook en cli.json).
# Uso: strict_scheme.py            -> aplica el esquema
#      from strict_scheme import colours  (desde otros scripts)
import json, subprocess
from pathlib import Path

from materialyoucolor.hct import Hct

from caelestia.utils.material.generator import gen_scheme
from caelestia.utils.scheme import Scheme

VARIANT = "fidelity"
state = Path.home() / ".local/state/caelestia"
cache = state / "strict-source.json"


def wallpaper() -> Path:
    return Path((state / "wallpaper/path.txt").read_text().strip())


def source() -> str:
    """Color principal del fondo (#rrggbb), cacheado por ruta y fecha del fondo."""
    wall = wallpaper()
    key = f"{wall}:{wall.stat().st_mtime}"
    try:
        c = json.loads(cache.read_text())
        if c["key"] == key:
            return c["source"]
    except (OSError, ValueError, KeyError):
        pass
    out = subprocess.run(
        ["matugen", "image", str(wall), "-t", "scheme-fidelity", "--source-color-index", "0",
         "--dry-run", "-j", "hex"],
        capture_output=True, text=True, check=True).stdout
    src = json.loads(out)["colors"]["source_color"]["default"]["color"]
    cache.write_text(json.dumps({"key": key, "source": src}))
    return src


def colours(mode: str, flavour: str = "default") -> dict[str, str]:
    scheme = Scheme({"name": "dynamic", "flavour": flavour, "mode": mode,
                     "variant": VARIANT, "colours": {}})
    return gen_scheme(scheme, Hct.from_int(int("ff" + source()[1:], 16)))


if __name__ == "__main__":
    from caelestia.utils.theme import apply_colours

    # Si la pantalla está bloqueada, el esquema del fondo está en scheme.wall.json
    path = state / "scheme.wall.json"
    if not path.exists():
        path = state / "scheme.json"
    s = json.loads(path.read_text())
    if s["name"] != "dynamic":
        raise SystemExit  # esquema fijo (catppuccin, etc.): no tocar

    s.update(variant=VARIANT, colours=colours(s["mode"], s["flavour"]))
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(s))
    tmp.replace(path)
    apply_colours(s["colours"], s["mode"])

    # Zen y demás plantillas de matugen, con el mismo color de origen
    subprocess.run(["matugen", "color", "hex", source(), "-m", s["mode"],
                    "-t", "scheme-fidelity", "-q"])
