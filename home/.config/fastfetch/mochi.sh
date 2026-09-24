#!/usr/bin/env bash
# Mochi en el hueco del logo de fastfetch (solo en kitty): la animación la genera Mochi en
# ~/.cache/mochi/fetch.gif (se mete de un salto en el cuadrado y pone una cara).
#   mochi.sh row        → fila del cursor ahora (1 = arriba), antes de fastfetch; y llama al
#                         Mochi del escritorio para que venga a rellenar el cuadrado (enterTerm)
#   mochi.sh play FILA  → pone la animación en el hueco (columna 2, fila de debajo, 22×10)
case $1 in
row)
    IFS='[;' read -rs -d R -t 1 -p $'\e[6n' _ r _ </dev/tty 2>/dev/tty
    r=${r:-1}
    echo "$r"
    # Llama al Mochi del escritorio: que venga buceando y se meta en el cuadrado (le dice a
    # cuántos px del borde de arriba de la ventana queda el centro del cuadrado)
    if [[ -n $KITTY_WINDOW_ID ]]; then
        size=$(kitten icat --print-window-size 2>/dev/null </dev/tty)   # "ANCHOxALTO" en px
        rows=$(tput lines 2>/dev/null </dev/tty)
        h=${size#*x}
        if [[ $h =~ ^[0-9]+$ && $rows =~ ^[0-9]+$ && $rows -gt 0 ]]; then
            off=$(( (r + 5) * h / rows + 8 ))
            (qs -c tamagotchi ipc call pet enterTerm "$off" >/dev/null 2>&1 &)
        fi
    fi
    ;;
play)
    gif=~/.cache/mochi/fetch.gif
    [[ -n $KITTY_WINDOW_ID && -f $gif ]] || exit 0
    printf '\e7'
    kitten icat --transfer-mode=stream --place "22x10@2x${2:-1}" --loop 1 --scale-up "$gif" 2>/dev/null
    printf '\e8'
    ;;
esac
