#!/usr/bin/env bash
# Llamado en cada pulsación de + o - (también los del teclado numérico).
# Doble + (< 400 ms): esconde a Mochi si está visible, o lo hace aparecer. Doble -: lo esconde.
key="${1:-plus}"
stamp="${XDG_RUNTIME_DIR:-/tmp}/tamagotchi-$key"
now=$(date +%s%3N)
last=$(cat "$stamp" 2>/dev/null || echo 0)
echo "$now $key" >> "${XDG_RUNTIME_DIR:-/tmp}/tamagotchi-keys.log"

if (( now - last < 400 )); then
    rm -f "$stamp"
    if [[ $key == minus ]]; then
        qs -c tamagotchi ipc call pet hide 2>/dev/null
    elif ! qs -c tamagotchi ipc call pet toggle 2>/dev/null; then
        # No estaba arrancada: arrancarla y mostrarla
        qs -c tamagotchi -n -d --log-rules "quickshell.io.socket.warning=false"
        for _ in $(seq 20); do
            sleep 0.1
            qs -c tamagotchi ipc call pet talk 2>/dev/null && break
        done
    fi
else
    echo "$now" > "$stamp"
fi
