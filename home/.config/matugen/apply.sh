#!/usr/bin/env bash
# Regenera los temas de matugen a partir del fondo de Caelestia.
# Lo lanza Caelestia al cambiar de fondo (postHook en ~/.config/caelestia/cli.json).
# Usa la imagen a resolución completa (Caelestia usa una miniatura borrosa que apaga
# los colores) y scheme-fidelity, que conserva la saturación real del color del fondo.
state="$HOME/.local/state/caelestia"
wall=$(<"$state/wallpaper/path.txt")
read -r key mode < <(python3 -c "
import json; d = json.load(open('$state/scheme.json'))
print(d['colours']['primaryPaletteKeyColor'], d['mode'])")

matugen image "$wall" -m "$mode" -t scheme-fidelity --source-color-index 0 -q ||
    exec matugen color hex "#$key" -m "$mode" -t scheme-fidelity -q
