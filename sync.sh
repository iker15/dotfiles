#!/usr/bin/env bash
# Refresca las listas de paquetes y sube los cambios a GitHub.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

log() { printf '\n\033[1;35m==> %s\033[0m\n' "$*"; }

# Las listas se FUSIONAN, no se sobrescriben. Antes esto era `pacman -Qqen > pkglist.txt` y
# se perdía lo que hubiera declarado la otra máquina por dos motivos: cada PC tiene paquetes
# propios, y sobre todo `-Qqen` sólo lista los EXPLÍCITOS — un paquete que aquí entró como
# dependencia de otro desaparecía de la lista aunque la configuración lo necesite. Medido en
# el sobremesa el 2026-10-08: se perdían 37, entre ellos fish, curl, pipewire, bat, eza y jq
# (fish lo arrastran cachyos-fish-config y caelestia-shell, así que no es explícito... e
# install.sh termina con `chsh -s /bin/fish`).
#
# El precio de fusionar: desinstalar algo ya no lo quita de la lista. Para eso está el aviso
# del final.
log "Fusionando las listas de paquetes con lo que hay en este PC"
antes_pkg=$(wc -l < pkglist.txt)
antes_aur=$(wc -l < aurlist.txt)
# (sort lee toda la entrada antes de escribir, así que -o sobre el propio fichero es seguro)
sort -u pkglist.txt <(pacman -Qqen) -o pkglist.txt
sort -u aurlist.txt <(pacman -Qqem) -o aurlist.txt
printf '  pkglist: %s -> %s\n  aurlist: %s -> %s\n' \
    "$antes_pkg" "$(wc -l < pkglist.txt)" "$antes_aur" "$(wc -l < aurlist.txt)"

# Lo que está en la lista pero no instalado aquí: puede ser del otro PC (normal) o algo que
# desinstalaste y la fusión ya no quita (hay que borrarlo a mano).
pacman -Qq | sort -u > /tmp/dotfiles-sync-have.txt
sobra=$(comm -23 <(sort -u pkglist.txt aurlist.txt) /tmp/dotfiles-sync-have.txt | tr '\n' ' ')
if [[ -n ${sobra// /} ]]; then
    log "En la lista pero no instalado en este PC"
    printf '  %s\n' "$sobra" | fold -s -w 76 | sed 's/^/  /'
    echo "  (si ya no los quieres en ningún PC, bórralos a mano de pkglist.txt/aurlist.txt)"
fi

git add -A
if git diff --cached --quiet; then
    echo "Sin cambios."
    exit 0
fi
git commit -m "${1:-Actualizar dotfiles $(date +%F)}"
git push
