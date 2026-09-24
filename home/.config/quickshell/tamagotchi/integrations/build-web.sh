#!/usr/bin/env bash
# Copia web (sin .pragma/.import de QML) de Hats.js + SkinShapes.js + Skins.js + Draw.js para la extensión de Zen
# y la de VSCodium: define window.MochiDraw = { avatar }, MochiHats y MochiSkins.
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
    echo "const Shapes = (function () {"
    grep -v '^\.pragma\|^\.import' "$root/SkinShapes.js"
    echo "return { get };"
    echo "})();"
    echo "const Skins = (function () {"
    grep -v '^\.pragma\|^\.import' "$root/Skins.js"
    echo "return { list, byId, milestones, nextAt, roll, outline, drawUnder, drawOver, eyesOf, rgb };"
    echo "})();"
    grep -v '^\.pragma\|^\.import' "$root/Draw.js"
    echo "g.MochiDraw = { avatar };"
    echo "g.MochiHats = Hats;"
    echo "g.MochiSkins = Skins;"
    echo "})(typeof window !== 'undefined' ? window : globalThis);"
}
for out in "$here/zen/extension/mochi-draw.js" "$here/vscodium/extension/media/mochi-draw.js"; do
    mkdir -p "$(dirname "$out")"
    bundle > "$out"
done
