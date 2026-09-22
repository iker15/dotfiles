#!/usr/bin/env bash
# Bloquea la pantalla con colores sacados de la foto de perfil (~/.face) en vez
# del fondo. Mientras está bloqueada solo se ve la pantalla de bloqueo, así que
# se cambia el esquema de la shell y se restaura al desbloquear.
state="$HOME/.local/state/caelestia"
scheme="$state/scheme.json"
backup="$state/scheme.wall.json"
face="$HOME/.face"
mode="light"                                # light o dark
cache="$state/scheme.face.$mode.json"

locked() { [ "$(qs -c caelestia ipc call lock isLocked 2>/dev/null)" = "true" ]; }
restore() { [ -f "$backup" ] && mv -f "$backup" "$scheme"; }

locked && exit 0
restore                                     # por si quedó algo de un bloqueo anterior

if [ -f "$face" ]; then
    # Regenerar el esquema de la foto solo si ha cambiado
    if [ ! -s "$cache" ] || [ "$face" -nt "$cache" ]; then
        "$HOME/.config/caelestia/face-scheme.py" "$mode" > "$cache.tmp" 2>/dev/null && mv -f "$cache.tmp" "$cache"
    fi
    if [ -s "$cache" ]; then
        cp -f "$scheme" "$backup"
        cp -f "$cache" "$scheme.tmp" && mv -f "$scheme.tmp" "$scheme"
        trap restore EXIT
        sleep 0.2                           # que la shell cargue los colores
    fi
fi

qs -c caelestia ipc call lock lock
sleep 1
while locked; do sleep 0.5; done
