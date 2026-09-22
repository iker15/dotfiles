#!/usr/bin/env bash
# Regenera los temas de matugen con los mismos colores que el esquema de Caelestia.
# Lo lanza Caelestia al cambiar de fondo (postHook en ~/.config/caelestia/cli.json).
scheme="$HOME/.local/state/caelestia/scheme.json"
read -r key mode variant < <(python3 -c "
import json; d = json.load(open('$scheme'))
print(d['colours']['primaryPaletteKeyColor'], d['mode'], d['variant'])")

case "$variant" in
    tonalspot)  type=scheme-tonal-spot ;;
    fruitsalad) type=scheme-fruit-salad ;;
    *)          type="scheme-$variant" ;;
esac

exec matugen color hex "#$key" -m "$mode" -t "$type" -q
