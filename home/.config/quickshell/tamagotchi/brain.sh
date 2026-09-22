#!/usr/bin/env bash
# Cerebro de la mascota: Claude Code en modo stream-json, reanudando la última
# conversación guardada. La mascota escribe mensajes por stdin y lee eventos por stdout.
state="${XDG_STATE_HOME:-$HOME/.local/state}/tamagotchi"
dir="$(dirname "$(readlink -f "$0")")"
mkdir -p "$state"

args=(-p
    --input-format stream-json
    --output-format stream-json
    --verbose
    --include-partial-messages
    --permission-mode auto
    --strict-mcp-config
    --name "Mochi (tamagotchi)"
    --append-system-prompt "$(cat "$dir/persona.md")")

# La sesión a reanudar la pasa la mascota (MOCHI_SESSION); si no, la del archivo
sid="${MOCHI_SESSION-$(cat "$state/session" 2>/dev/null)}"
[ -n "$sid" ] && args+=(--resume "$sid")

# Desde $HOME para compartir memoria con las sesiones de la terminal
cd "$HOME" || exit 1
exec claude "${args[@]}"
