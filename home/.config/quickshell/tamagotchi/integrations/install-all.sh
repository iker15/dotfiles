#!/usr/bin/env bash
# Instala todas las integraciones de Mochi que no necesitan sudo: extensión de Zen (+ host
# nativo), extensión de VSCodium y paquete de texturas de Minecraft. (El fondo de Limine va
# aparte: ~/dotfiles/system/limine/install.sh, con sudo.)
here=$(cd "$(dirname "$0")" && pwd)
"$here/build-web.sh"
[[ -d ~/.config/zen ]] && "$here/zen/install.sh"
command -v codium >/dev/null && "$here/vscodium/install.sh"
"$here/minecraft/install.sh"
exit 0
