-- Teclado en español
hl.config({
    input = {
        kb_layout = "es",
    },
})

-- Efecto glass
-- Kitty: la transparencia la pone kitty (kitty.conf), así el texto no se atenúa
hl.window_rule({ match = { class = "kitty" }, opaque = true })
-- VS Code: un poco más transparente que el resto (activa / inactiva)
hl.window_rule({ match = { class = "code-oss", fullscreen = false }, opacity = "0.88 override 0.82 override" })

-- CTRL + ALT + P: pausar / seguir la grabación de pantalla (avisa con una notificación)
hl.bind("CTRL + ALT + P", hl.dsp.exec_cmd("~/.local/bin/caelestia-record -p"))

-- SUPER + L: bloquear con los colores de la foto de perfil (~/.face)
hl.bind("SUPER + L", hl.dsp.exec_cmd("~/.config/caelestia/lock-face.sh"))

-- Fondo: lo pinta awww (admite GIF animados y transiciones); el de Caelestia está apagado
-- (wallpaperEnabled en shell.json). Al arrancar recupera el último fondo que tuvo.
hl.on("hyprland.start", function()
    hl.exec_cmd("awww-daemon")
end)

-- Mochi (burbujita con Claude de cerebro): vive en el escritorio desde el inicio.
-- Doble + lo esconde / lo hace aparecer, doble - lo esconde (clic para hablarle); non_consuming: el + se sigue escribiendo en las apps
hl.on("hyprland.start", function()
    hl.exec_cmd("qs -c tamagotchi -n -d --log-rules 'quickshell.io.socket.warning=false;qt.qml.usedbeforedeclared=false'")
end)
for _, k in ipairs({ "plus", "KP_Add" }) do
    hl.bind(k, hl.dsp.exec_cmd("~/.config/quickshell/tamagotchi/toggle.sh plus"), { non_consuming = true })
end
for _, k in ipairs({ "minus", "KP_Subtract" }) do
    hl.bind(k, hl.dsp.exec_cmd("~/.config/quickshell/tamagotchi/toggle.sh minus"), { non_consuming = true })
end
hl.layer_rule({ match = { namespace = "mochi" }, no_anim = true })

-- Pantallas: la disposición la guarda nwg-displays en ~/.config/hypr/monitors.lua
-- (abre "nwg-displays", arrastra las pantallas y pulsa Aplicar)
require("monitors")
