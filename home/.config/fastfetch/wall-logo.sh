#!/usr/bin/env bash
# Recorte cuadrado del fondo actual de Caelestia para el logo de fastfetch, con marco del color del tema.
# Solo se regenera si cambia el fondo o el esquema de colores.
src=$(readlink -f ~/.local/state/caelestia/wallpaper/current)
scheme=~/.local/state/caelestia/scheme.json
out=~/.cache/fastfetch/wall.png
stamp=~/.cache/fastfetch/wall.stamp
key="$src $(stat -c %Y "$src" "$scheme" 2>/dev/null | tr '\n' ' ')"
mkdir -p ~/.cache/fastfetch
if [[ ! -f $out || "$(cat "$stamp" 2>/dev/null)" != "$key" ]]; then
    colour=$(grep -oP '"primary":\s*"\K[0-9a-fA-F]{6}' "$scheme" 2>/dev/null | head -1)
    magick "$src" -resize 480x480^ -gravity center -extent 480x480 \
        -bordercolor "#${colour:-cccccc}" -border 10 "$out" && echo "$key" > "$stamp"
fi
