#!/usr/bin/env bash
# Mochi en el hueco del logo de fastfetch (solo en kitty): la animación la genera Mochi en
# ~/.cache/mochi/fetch.gif (se mete de un salto en el cuadrado y pone una cara).
#   mochi.sh row        → fila del cursor ahora (1 = arriba), antes de fastfetch
#   mochi.sh play FILA  → pone la animación en el hueco (columna 2, fila de debajo, 22×10)
case $1 in
row)
    IFS='[;' read -rs -d R -t 1 -p $'\e[6n' _ r _ </dev/tty 2>/dev/tty
    echo "${r:-1}"
    ;;
play)
    gif=~/.cache/mochi/fetch.gif
    [[ -n $KITTY_WINDOW_ID && -f $gif ]] || exit 0
    printf '\e7'
    kitten icat --transfer-mode=stream --place "22x10@2x${2:-1}" --loop 1 --scale-up "$gif" 2>/dev/null
    printf '\e8'
    ;;
esac
