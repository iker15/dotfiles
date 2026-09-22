#!/usr/bin/env bash
# Comandos rápidos de Mochi: se resuelven al instante sin pasar por Claude.
# Uso: quick.sh "<frase>"  → imprime la respuesta y sale con 0 si la ha entendido,
#                             sale con 1 (sin imprimir nada) si hay que preguntarle a Claude.
# Para añadir uno: un nuevo `elif` con una regex sobre $t (minúsculas, sin tildes ni signos).

t=$(printf '%s' "$*" | tr '[:upper:]' '[:lower:]' | sed 'y/áéíóúüñ/aeiouun/; s/[¿?¡!.,;:]//g; s/  */ /g; s/^ //; s/ $//')
# Quitar muletillas: "mochi", "oye", "por favor"…
t=$(printf '%s' "$t" | sed -E 's/^(oye |hey |ey |hola )?(mochi )?//; s/ ?por favor$//; s/^(puedes|podrias) //')

num=$(grep -oE '[0-9]+' <<<"$t" | head -1)
ok() { printf '%s\n' "$*"; exit 0; }
shell() { qs -c caelestia ipc call "$@" >/dev/null 2>&1; }

open_app() {
    setsid -f "$@" >/dev/null 2>&1 </dev/null
}

vol() { wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{printf "%d", $2*100}'; }

if [[ $t =~ ^(ayuda|que (sabes|puedes) hacer|comandos)$ ]]; then
    ok "Al instante: hora, fecha, batería, volumen (sube/baja/al 40/silencio), brillo, música (pausa/siguiente/anterior), captura, bloquear, abrir apps (navegador, spotify, terminal, código, archivos). Lo demás se lo pregunto a mi cerebro 🧠"

elif [[ $t =~ (que hora|la hora) ]]; then
    ok "Son las $(date +%H:%M)."

elif [[ $t =~ (que dia|fecha|a que estamos) ]]; then
    ok "Hoy es $(LC_TIME=es_ES.UTF-8 date '+%A %-d de %B de %Y')."

elif [[ $t =~ bateria ]]; then
    b=(/sys/class/power_supply/BAT*)
    cap=$(cat "${b[0]}/capacity") st=$(cat "${b[0]}/status")
    case $st in
        Charging) s="y cargando ⚡" ;; Full) s="y llena" ;; *) s="(sin cargar)" ;;
    esac
    ok "Batería al $cap % $s."

elif [[ $t =~ (silencia|mutea|quita el sonido|silencio) ]]; then
    wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
    wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q MUTED && ok "Silenciado 🤫" || ok "Sonido de vuelta 🔊"

elif [[ $t =~ volumen ]]; then
    if [[ -n $num ]]; then wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ "$num%"
    elif [[ $t =~ (sube|mas|alto) ]]; then wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 10%+
    elif [[ $t =~ (baja|menos|bajo) ]]; then wpctl set-volume @DEFAULT_AUDIO_SINK@ 10%-
    fi
    ok "Volumen al $(vol) %."

elif [[ $t =~ brillo ]]; then
    if [[ -n $num ]]; then brightnessctl -q set "$num%"
    elif [[ $t =~ (sube|mas) ]]; then brightnessctl -q set 10%+
    elif [[ $t =~ (baja|menos) ]]; then brightnessctl -q set 10%-
    fi
    ok "Brillo al $(brightnessctl -m | cut -d, -f4)."

elif [[ $t =~ ^(pausa|para la musica|pon musica|play|reanuda|continua)$ ]]; then
    shell mpris playPause
    ok "Hecho ⏯"

elif [[ $t =~ (siguiente|salta|pasa) ]] && [[ $t =~ (cancion|tema|musica|^siguiente$) ]]; then
    shell mpris next
    ok "Siguiente ⏭"

elif [[ $t =~ (anterior|la de antes) ]]; then
    shell mpris previous
    ok "Anterior ⏮"

elif [[ $t =~ (que (suena|cancion)|que esta sonando) ]]; then
    title=$(qs -c caelestia ipc call mpris getActive trackTitle 2>/dev/null)
    artist=$(qs -c caelestia ipc call mpris getActive trackArtist 2>/dev/null)
    [[ $title == "No active player" ]] && title=""
    [[ $artist == "No active player" ]] && artist=""
    [[ -n $title ]] && ok "Suena «$title»${artist:+ de $artist} 🎵" || ok "No suena nada ahora mismo."

elif [[ $t =~ (captura|pantallazo|screenshot) ]]; then
    dir=$(xdg-user-dir PICTURES)/Screenshots; mkdir -p "$dir"
    f="$dir/mochi-$(date +%Y%m%d-%H%M%S).png"
    if [[ $t =~ (zona|region|trozo|parte) ]]; then
        g=$(slurp) || ok "Cancelado."
        grim -g "$g" "$f"
    else
        sleep 0.3; grim "$f"
    fi
    wl-copy < "$f"
    ok "Captura guardada y copiada 📸"

elif [[ $t =~ ^(bloquea|bloquear)( la pantalla| el pc| el ordenador)?$ ]]; then
    (sleep 0.8; ~/.config/caelestia/lock-face.sh) >/dev/null 2>&1 &
    ok "¡Hasta luego! 🔒"

elif [[ $t =~ ^(abre|abreme|lanza|inicia|pon) ]]; then
    case $t in
        *navegador*|*zen*|*internet*|*firefox*) open_app zen-browser; ok "Abriendo el navegador 🌐" ;;
        *spotify*) open_app spotify; ok "Abriendo Spotify 🎧" ;;
        *terminal*|*kitty*|*consola*) open_app kitty; ok "Abriendo la terminal" ;;
        *codigo*|*code*|*codium*|*editor*) open_app codium; ok "Abriendo VSCodium" ;;
        *archivos*|*carpeta*|*dolphin*|*explorador*) open_app dolphin; ok "Abriendo archivos 📁" ;;
        *discord*|*equibop*) open_app equibop; ok "Abriendo Discord" ;;
    esac
fi

exit 1
