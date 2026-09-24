#!/usr/bin/env bash
# Copia web (sin .pragma/.import de QML) de Hats.js + Draw.js para la extensión de Zen y la de
# VSCodium: define window.MochiDraw = { avatar, E, RR } y MochiHats.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
bundle() {
    echo "// Generado por integrations/build-web.sh desde Hats.js y Draw.js (no editar)"
    echo "(function (g) {"
    echo "const Hats = (function () {"
    grep -v '^\.pragma\|^\.import' "$root/Hats.js"
    echo "return { E, RR, draw, seasonal };"
    echo "})();"
    grep -v '^\.pragma\|^\.import' "$root/Draw.js"
    echo "g.MochiDraw = { avatar };"
    echo "g.MochiHats = Hats;"
    echo "})(typeof window !== 'undefined' ? window : globalThis);"
}
for out in "$here/zen/extension/mochi-draw.js" "$here/vscodium/extension/media/mochi-draw.js"; do
    mkdir -p "$(dirname "$out")"
    bundle > "$out"
done
