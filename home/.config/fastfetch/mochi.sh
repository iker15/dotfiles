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
            rm -f "$XDG_RUNTIME_DIR/mochi-term-eta"
            (qs -c tamagotchi ipc call pet enterTerm "$off" >/dev/null 2>&1 &)
        fi
    fi
    ;;
play)
    gif=~/.cache/mochi/fetch.gif
    [[ -n $KITTY_WINDOW_ID && -f $gif ]] || exit 0
    # Mochi viene a su ritmo: dice cuándo llega (ms) en mochi-term-eta. El fluido empieza a
    # asomar en el fotograma 22 (0,88 s): se arranca la animación para que coincida. Sin
    # bloquear el prompt (en segundo plano).
    eta_file=$XDG_RUNTIME_DIR/mochi-term-eta
    for _ in $(seq 15); do [[ -s $eta_file ]] && break; sleep 0.1; done
    delay=0
    if [[ -s $eta_file ]]; then
        eta=$(<"$eta_file")
        now=$(date +%s%3N)
        (( eta - now - 880 > 0 )) && delay=$(awk -v d=$(( eta - now - 880 )) 'BEGIN { printf "%.2f", d / 1000 }')
    fi
    (
        sleep "$delay"
        printf '\e7'
        kitten icat --transfer-mode=stream --place "22x10@2x${2:-1}" --loop 1 --scale-up "$gif" 2>/dev/null </dev/tty
        printf '\e8'
    ) >/dev/tty 2>/dev/null &
    disown
    ;;
esac
