#!/usr/bin/env bash
# Refresca las listas de paquetes y sube los cambios a GitHub.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

pacman -Qqen > pkglist.txt
pacman -Qqem > aurlist.txt

git add -A
if git diff --cached --quiet; then
    echo "Sin cambios."
    exit 0
fi
git commit -m "${1:-Actualizar dotfiles $(date +%F)}"
git push
