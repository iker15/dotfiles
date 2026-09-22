function fish_greeting
    # Ojo del pin en puntos Braille, con los colores del fondo actual
    echo
    python3 ~/.config/fish/art/eye.py

    # Para volver a la araña del Genei Ryodan, cambia lo de arriba por:
    #   string replace '#' 4 < ~/.config/fish/ryodan.txt | string replace -r '^' '  '

    # Tira con la paleta del fondo
    echo -n '  '
    for c in 16 17 18 1 2 3 4 5 6
        echo -n \e"[38;5;$c""m● "
    end
    set_color normal
    echo
end
