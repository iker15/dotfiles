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
        cols=$(tput cols 2>/dev/null </dev/tty)
        w=${size%x*} h=${size#*x}
        if [[ $h =~ ^[0-9]+$ && $w =~ ^[0-9]+$ && $rows -gt 0 && $cols -gt 0 ]]; then
            # Mochi calcula dónde queda la animación (22×10 celdas en la columna 2, fila r; la
            # imagen se alinea arriba a la izquierda) con esto y el tamaño real de la ventana
            rm -f "$XDG_RUNTIME_DIR/mochi-term-eta"
            (qs -c tamagotchi ipc call pet enterTerm "$r" "$cols" "$rows" "$w" "$h" >/dev/null 2>&1 &)
        fi
    fi
    ;;
play)
    gif=~/.cache/mochi/fetch.gif
    [[ -n $KITTY_WINDOW_ID && -f $gif ]] || exit 0
    # Mochi viene a su ritmo y deja caer una gota desde el marco (por encima de todo, en el
    # escritorio): dice en mochi-term-eta cuándo llega esa gota al cuadrado (ms). En el GIF entra
    # en el fotograma 22 (0,88 s): se arranca para que coincida. Sin bloquear el prompt.
    eta_file=$XDG_RUNTIME_DIR/mochi-term-eta
    for _ in $(seq 15); do [[ -s $eta_file ]] && break; sleep 0.1; done
    start=0
    [[ -s $eta_file ]] && start=$(( $(<"$eta_file") - 880 ))   # el fotograma 22, cuando toca
    (
        if [[ -f ~/.cache/mochi/fetch.b64 ]]; then
            # fotogramas con transparencia suave, por el protocolo de kitty; manda todo ya y
            # arranca justo cuando toca
            python3 ~/.config/fastfetch/kitty-anim.py ~/.cache/mochi/fetch.b64 2 "${2:-1}" 22 "$start"
        else
            now=$(date +%s%3N)
            (( start > now )) && sleep "$(awk -v d=$(( start - now )) 'BEGIN { printf "%.2f", d / 1000 }')"
            printf '\e7'
            kitten icat --transfer-mode=stream --place "22x10@2x${2:-1}" --loop 1 --scale-up "$gif" 2>/dev/null </dev/tty
            printf '\e8'
        fi
    ) >/dev/tty 2>/dev/null &
    disown
    ;;
esac
