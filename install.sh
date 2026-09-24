#!/usr/bin/env bash
# Instala los dotfiles de iker en una CachyOS recién instalada (la tuya o la de un amigo).
# Uso: bash bootstrap.sh (lo clona en ~/dotfiles y ejecuta esto), o
#      git clone <repo> ~/dotfiles && ~/dotfiles/install.sh
set -euo pipefail

DOTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"

log() { printf '\n\033[1;35m==> %s\033[0m\n' "$*"; }

# --- 1. Paquetes -------------------------------------------------------------
log "Actualizando sistema e instalando paquetes oficiales"
sudo pacman -Syu --needed --noconfirm base-devel git
# Solo los paquetes que existen en los repos (evita fallos por paquetes renombrados), y sin los
# de hardware (drivers NVIDIA/Intel, microcódigo, kernels): esos ya los pone el instalador de
# CachyOS según el PC de cada uno
HW='^(nvidia.*|lib32-nvidia.*|opencl-nvidia|lib32-opencl-nvidia|libva-nvidia-driver|linux-cachyos.*|linux-.*-headers|intel-ucode|amd-ucode|intel-lpmd|intel-media-driver|vulkan-intel|lib32-vulkan-intel|vulkan-radeon|lib32-vulkan-radeon|xf86-video-.*)$'
# Tampoco lo que depende de cómo se instaló cada CachyOS (gestor de arranque, copias de
# seguridad, escritorio elegido en el instalador): eso se queda como lo tenga cada uno
SYS='^(limine.*|grub.*|refind.*|os-prober|efibootmgr|mkinitcpio.*|dracut|chwd.*|cachyos-.*-settings|cachyos-snapper-support|snapper|snap-pac|btrfs-assistant|timeshift.*|sddm.*|plasma.*|kate|kwrite|dolphin|konsole|spectacle|ark|gwenview|okular|phonon-.*)$'
comm -12 <(sort "$DOTS/pkglist.txt") <(pacman -Slq | sort -u) \
    | grep -vE "$HW" | grep -vE "$SYS" > /tmp/dotfiles-pkgs.txt
# Y fuera los que chocan con algo que ya tiene instalado (se queda con lo suyo): con
# --noconfirm pacman no puede preguntar qué quitar y se para con "conflictos sin resolver"
pacman -Qq | sort -u > /tmp/dotfiles-have.txt
LC_ALL=C pacman -Si $(cat /tmp/dotfiles-pkgs.txt) 2>/dev/null | awk -F' *: ' '
    /^Name/ { n = $2 }
    /^Conflicts With/ && $2 != "None" { split($2, c, / +/); for (i in c) { sub(/[<>=].*/, "", c[i]); print n, c[i] } }' \
    | while read -r pkg other; do
        if [[ "$pkg" != "$other" ]] && grep -qx "$other" /tmp/dotfiles-have.txt; then
            echo "$pkg"
            echo "  (me salto $pkg: choca con $other, que ya tienes)" >&2
        fi
    done | sort -u > /tmp/dotfiles-skip.txt
grep -vxF -f /tmp/dotfiles-skip.txt /tmp/dotfiles-pkgs.txt \
    | sudo pacman -S --needed --noconfirm -

if ! command -v paru >/dev/null; then
    log "Instalando paru"
    sudo pacman -S --needed --noconfirm paru || {
        tmp=$(mktemp -d)
        git clone https://aur.archlinux.org/paru-bin.git "$tmp/paru"
        (cd "$tmp/paru" && makepkg -si --noconfirm)
    }
fi

log "Instalando paquetes del AUR"
# Otros Quickshell (el de Noctalia, que trae la edición Hyprland de CachyOS) dicen ser
# quickshell-git pero no lo son y Caelestia no arranca con ellos: fuera
for fake in $(pacman -Qq 2>/dev/null | grep -xE 'noctalia-qs|quickshell'); do
    log "Quitando $fake (Caelestia necesita quickshell-git)"
    sudo pacman -Rdd --noconfirm "$fake"
done
# (uno a uno: si alguno falla o choca, sigue con los demás. Ojo: `pacman -Q nombre` también
# acepta paquetes que solo "proveen" ese nombre, así que se mira el nombre exacto)
pacman -Qq > /tmp/dotfiles-have.txt
while read -r pkg; do
    [[ -z "$pkg" ]] && continue
    grep -qx "$pkg" /tmp/dotfiles-have.txt && continue
    paru -S --needed --noconfirm "$pkg" || echo "  (no se pudo instalar $pkg del AUR: sigue sin él)"
done < "$DOTS/aurlist.txt"

# --- 2. Symlinks -------------------------------------------------------------
log "Enlazando configuración (lo que ya exista se guarda en $BACKUP)"
cd "$DOTS/home"
# Enlaza cada entrada de primer nivel de .config (y ficheros sueltos fuera de ella)
link() {
    local rel="$1" src="$DOTS/home/$1" dst="$HOME/$1"
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then return; fi
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        mkdir -p "$BACKUP/$(dirname "$rel")"
        mv "$dst" "$BACKUP/$rel"
    fi
    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
    echo "  $dst"
}
for f in .config/*; do
    [ "$f" = ".config/VSCodium" ] || [ "$f" = ".config/Code - OSS" ] && continue
    link "$f"
done
link .config/VSCodium/User/settings.json
link .config/VSCodium/User/keybindings.json
link ".config/Code - OSS/User/settings.json"
for f in .[!.]*; do
    [ "$f" = ".config" ] || [ "$f" = ".local" ] && continue
    link "$f"
done
for f in .local/bin/*; do
    [ -e "$f" ] && link "$f"
done

# Teclado: el que se eligió al instalar CachyOS (en el repo está "us", el que usa iker a propósito)
kb=$(localectl status 2>/dev/null | awk -F': *' '/X11 Layout/ {print $2}' | cut -d, -f1)
if [[ -n $kb && $kb != us && $USER != iker ]]; then
    log "Teclado: $kb"
    sed -i "s/kb_layout *= *\"[^\"]*\"/kb_layout          = \"$kb\"/" "$DOTS/home/.config/hypr/hyprland/input.lua"
fi

# --- 3. Servicios ------------------------------------------------------------
log "Activando servicios"
sudo systemctl enable --now NetworkManager bluetooth ufw fstrim.timer 2>/dev/null || true
systemctl --user daemon-reload
systemctl --user enable --now caelestia-dark.path pipewire.socket pipewire-pulse.socket wireplumber 2>/dev/null || true

# --- 4. Mochi: oído (voz local con Whisper, ~1 GB) ----------------------------
log "Preparando el oído de Mochi"
"$HOME/.config/quickshell/tamagotchi/setup-voice.sh" || echo "  (sin voz: ejecuta setup-voice.sh más tarde)"

# --- 4b. Mochi: pantalla de arranque (Plymouth) -----------------------------
log "Poniendo a Mochi en el arranque"
"$DOTS/system/plymouth/mochi/install.sh" || echo "  (sin tema de arranque: ejecuta system/plymouth/mochi/install.sh más tarde)"
"$DOTS/system/limine/install.sh" || echo "  (sin fondo de Limine: ejecuta system/limine/install.sh más tarde)"

# --- 4c. Mochi en las apps (Zen, VSCodium, Minecraft) ------------------------
# (y basedpyright: errores de Python en el editor, para que Mochi los vea)
command -v codium >/dev/null && codium --install-extension detachhead.basedpyright >/dev/null 2>&1 || true
log "Integrando a Mochi en las apps"
"$HOME/.config/quickshell/tamagotchi/integrations/install-all.sh" || echo "  (ejecuta ~/.config/quickshell/tamagotchi/integrations/install-all.sh más tarde)"

# --- 5. Shell ----------------------------------------------------------------
if [ "$(getent passwd "$USER" | cut -d: -f7)" != "/bin/fish" ]; then
    log "Poniendo fish como shell"
    chsh -s /bin/fish
fi

log "Listo. Reinicia la sesión y entra en Hyprland."
[ -d "$BACKUP" ] && echo "Configs antiguas guardadas en $BACKUP"
