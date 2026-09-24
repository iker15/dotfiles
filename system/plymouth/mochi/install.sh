#!/usr/bin/env bash
# Instala el tema de arranque de Mochi (Plymouth) y lo pone por defecto (reconstruye el
# initramfs). Para volver al de CachyOS: sudo plymouth-set-default-theme -R cachyos-bootanimation
set -e
cd "$(dirname "$(readlink -f "$0")")"
[ -f throbber-00.png ] || ./gen.py
sudo rm -rf /usr/share/plymouth/themes/mochi
sudo install -d /usr/share/plymouth/themes/mochi
sudo install -m 644 mochi.plymouth ./*.png /usr/share/plymouth/themes/mochi/
sudo plymouth-set-default-theme -R mochi
echo "Listo: el próximo arranque sale Mochi."
