#!/usr/bin/env bash
# Paquete de texturas Mochi (slimes → Mochis) en todas las instancias de Prism y ~/.minecraft,
# y lo activa en options.txt (solo si el juego no está abierto: si no, actívalo en el juego).
set -e
here=$(cd "$(dirname "$0")" && pwd)
dirs=(~/.local/share/PrismLauncher/instances/*/minecraft ~/.local/share/PrismLauncher/instances/*/.minecraft ~/.minecraft)
running=$(pgrep -a java 2>/dev/null | grep -qE "minecraft|KnotClient" && echo 1 || true)
for d in "${dirs[@]}"; do
    [[ -d $d ]] || continue
    mkdir -p "$d/resourcepacks"
    "$here/make-pack.py" "$d/resourcepacks/Mochi.zip" >/dev/null
    opt="$d/options.txt"
    if [[ -z $running && -f $opt ]] && ! grep -q '"file/Mochi.zip"' "$opt"; then
        python3 - "$opt" <<'PY'
import json, re, sys
p = sys.argv[1]
s = open(p).read()
m = re.search(r'^resourcePacks:(.*)$', s, re.M)
packs = json.loads(m.group(1)) if m else []
if "vanilla" not in packs:
    packs.insert(0, "vanilla")
packs.append("file/Mochi.zip")
line = "resourcePacks:" + json.dumps(packs, separators=(",", ":"))
s = s.replace(m.group(0), line) if m else s + line + "\n"
open(p, "w").write(s)
PY
    fi
    echo "Mochi.zip → $d/resourcepacks"
done
[[ -n $running ]] && echo "Minecraft está abierto: actívalo en Opciones → Paquetes de recursos."
exit 0
