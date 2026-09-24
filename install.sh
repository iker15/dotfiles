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
comm -12 <(sort "$DOTS/pkglist.txt") <(pacman -Slq | sort -u) \
    | grep -vE "$HW" \
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
paru -S --needed --noconfirm - < "$DOTS/aurlist.txt"

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
