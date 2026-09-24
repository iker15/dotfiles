#!/usr/bin/env bash
# Recorte cuadrado del fondo actual de Caelestia para el logo de fastfetch, con Mochi sentado
# abajo (su retrato de ahora: cara, gorro de temporada… lo pinta Mochi en ~/.cache/mochi).
# Solo se regenera si cambia el fondo o el retrato.
src=$(readlink -f ~/.local/state/caelestia/wallpaper/current)
mochi=~/.cache/mochi/avatar.png
out=~/.cache/fastfetch/wall.png
stamp=~/.cache/fastfetch/wall.stamp
key="$src $(stat -c %Y "$src" "$mochi" 2>/dev/null | tr '\n' ' ')"
mkdir -p ~/.cache/fastfetch
if [[ ! -f $out || "$(cat "$stamp" 2>/dev/null)" != "$key" ]]; then
    if [[ -f $mochi ]]; then
        magick "$src" -resize 480x480^ -gravity center -extent 480x480 \
            \( "$mochi" -resize 230x230 \( +clone -background black -shadow 50x6+0+4 \) +swap -background none -layers merge +repage \) \
            -gravity south -geometry +0+2 -composite "$out"
    else
        magick "$src" -resize 480x480^ -gravity center -extent 480x480 "$out"
    fi && echo "$key" > "$stamp"
fi
