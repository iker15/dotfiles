#!/usr/bin/env bash
# Monta la animación de la terminal (fastfetch) con los fotogramas que pinta Mochi: $1 = archivo
# con un PNG en base64 por línea. Sale ~/.cache/mochi/fetch.gif (una sola vuelta: se queda en
# el último fotograma, con la cara que pone).
set -e
src=$1
out=~/.cache/mochi/fetch.gif
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
i=0
while IFS= read -r line; do
    [[ -n $line ]] || continue
    printf %s "$line" | base64 -d > "$tmp/f$(printf %03d $i).png"
    i=$((i + 1))
done < "$src"
(( i > 0 )) || exit 1
# 25 fps; transparencia a 1 bit (las esquinas redondeadas del cuadrado)
# (fotogramas completos: kitty no anima bien los GIF "optimizados" de ImageMagick)
magick -delay 4 -dispose Background "$tmp"/f*.png -channel A -threshold 50% +channel -loop 1 "$tmp/out.gif"
mv "$tmp/out.gif" "$out"
# (y los fotogramas tal cual, con transparencia suave: los usa ~/.config/fastfetch/kitty-anim.py)
cp "$src" ~/.cache/mochi/fetch.b64.tmp && mv ~/.cache/mochi/fetch.b64.tmp ~/.cache/mochi/fetch.b64
