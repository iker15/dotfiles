#!/usr/bin/env bash
# Lo lanza Caelestia al cambiar de fondo (postHook en cli.json). El fondo lo pinta
# awww (Caelestia tiene el suyo apagado), así que aquí se le pasa la imagen y luego
# se sacan los colores. Si el cambio viene de waypaper, awww ya la tiene puesta.
[ -n "$WAYPAPER" ] || awww img "$WALLPAPER_PATH"
exec "$HOME/.config/caelestia/strict_scheme.py"
