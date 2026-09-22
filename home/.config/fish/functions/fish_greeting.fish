function fish_greeting
    # Fetch con el fondo de pantalla actual a la izquierda (recorte cuadrado, se actualiza solo al cambiar de fondo)
    ~/.config/fastfetch/wall-logo.sh
    fastfetch

    # Para volver al ojo del pin en Braille, cambia lo de arriba por:
    #   echo; python3 ~/.config/fish/art/eye.py
    #   echo -n '  '; for c in 16 17 18 1 2 3 4 5 6; echo -n \e"[38;5;$c""m● "; end; set_color normal; echo
    # Y para la araña del Genei Ryodan:
    #   string replace '#' 4 < ~/.config/fish/ryodan.txt | string replace -r '^' '  '
end
