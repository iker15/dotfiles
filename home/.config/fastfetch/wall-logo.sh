#!/usr/bin/env bash
# Recorte cuadrado del fondo actual de Caelestia para el logo de fastfetch.
# Solo se regenera si cambia el fondo.
src=$(readlink -f ~/.local/state/caelestia/wallpaper/current)
out=~/.cache/fastfetch/wall.png
stamp=~/.cache/fastfetch/wall.stamp
key="$src $(stat -c %Y "$src" 2>/dev/null | tr '\n' ' ')"
mkdir -p ~/.cache/fastfetch
if [[ ! -f $out || "$(cat "$stamp" 2>/dev/null)" != "$key" ]]; then
    magick "$src" -resize 480x480^ -gravity center -extent 480x480 "$out" && echo "$key" > "$stamp"
fi
