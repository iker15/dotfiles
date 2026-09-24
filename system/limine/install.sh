#!/usr/bin/env bash
# Pone a Mochi dormido de fondo en el menú de arranque (Limine). Necesita sudo: ejecútalo en
# una terminal. Copia el fondo a la ESP, pone "wallpaper:" en las opciones globales de
# limine.conf (arriba, antes de las entradas; limine-entry-tool no las toca) y vuelve a
# registrar el hash de la config (limine-enroll-config), que si no Limine no arranca con ella.
# Deshacer: sudo sed -i '/^wallpaper/d' /boot/limine.conf && sudo limine-enroll-config
set -e
here=$(cd "$(dirname "$0")" && pwd)
esp=$(. /etc/default/limine 2>/dev/null; echo "${ESP_PATH:-/boot}")
conf="$esp/limine.conf"
[[ -f $here/mochi-limine.png ]] || "$here/make-wallpaper.py" "$here/mochi-limine.png"
sudo test -f "$conf" || { echo "No encuentro $conf"; exit 1; }
sudo cp "$here/mochi-limine.png" "$esp/mochi-limine.png"
sudo cp "$conf" "$conf.bak-mochi"
sudo python3 - "$conf" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
s = re.sub(r"(?m)^wallpaper(_style)?:.*\n", "", s)
opts = "wallpaper: boot():/mochi-limine.png\nwallpaper_style: stretched\n"
# opciones globales: antes de la primera entrada ("/…")
m = re.search(r"(?m)^/", s)
s = s[:m.start()] + opts + "\n" + s[m.start():] if m else opts + s
open(p, "w").write(s)
PY
command -v limine-enroll-config >/dev/null && sudo limine-enroll-config
echo "Listo: Mochi dormido en el menú de Limine (copia de seguridad: $conf.bak-mochi)"
