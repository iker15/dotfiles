#!/usr/bin/env python3
# Esquema de colores de la foto de perfil (~/.face) para la pantalla de bloqueo.
# Uso: face-scheme.py [light|dark]  -> imprime el JSON del esquema
import json, sys
from pathlib import Path
from caelestia.utils.paths import wallpapers_cache_dir
from caelestia.utils.scheme import Scheme, get_scheme
from caelestia.utils.wallpaper import compute_hash, get_colours_for_image, get_smart_opts, get_thumb

mode = sys.argv[1] if len(sys.argv) > 1 else "light"
face = Path.home() / ".face"
cache = wallpapers_cache_dir / compute_hash(face)
variant = get_smart_opts(face, cache)["variant"]
base = get_scheme()
scheme = Scheme({"name": "dynamic", "flavour": base.flavour, "mode": mode,
                 "variant": variant, "colours": base.colours})
print(json.dumps({"name": "dynamic", "flavour": base.flavour, "mode": mode, "variant": variant,
                  "colours": get_colours_for_image(get_thumb(face, cache), scheme)}))
