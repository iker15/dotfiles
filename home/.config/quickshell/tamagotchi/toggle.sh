#!/usr/bin/env bash
# Llamado en cada pulsación de +: si hay dos seguidas (< 300 ms) muestra/oculta a Mochi.
stamp="${XDG_RUNTIME_DIR:-/tmp}/tamagotchi-plus"
now=$(date +%s%3N)
last=$(cat "$stamp" 2>/dev/null || echo 0)

if (( now - last < 300 )); then
    rm -f "$stamp"
    if ! qs -c tamagotchi ipc call pet toggle 2>/dev/null; then
        # No estaba arrancada: arrancarla y mostrarla
        qs -c tamagotchi -n -d
        for _ in $(seq 20); do
            sleep 0.1
            qs -c tamagotchi ipc call pet show 2>/dev/null && break
        done
    fi
else
    echo "$now" > "$stamp"
fi
