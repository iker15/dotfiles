#!/usr/bin/env bash
# Lanza ears.py con su entorno (si no está instalado, no hace nada)
py="$HOME/.local/share/mochi/venv/bin/python"
[ -x "$py" ] || { echo "error:sin-instalar"; exit 1; }
export HF_HUB_OFFLINE=1
exec "$py" -u "$(dirname "$(readlink -f "$0")")/ears.py"
