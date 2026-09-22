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

-- SUPER + L: bloquear con los colores de la foto de perfil (~/.face)
hl.bind("SUPER + L", hl.dsp.exec_cmd("~/.config/caelestia/lock-face.sh"))

-- Mochi (burbujita con Claude de cerebro): vive en el escritorio desde el inicio.
-- Doble + lo esconde / lo hace aparecer, doble - lo esconde (clic para hablarle); non_consuming: el + se sigue escribiendo en las apps
hl.on("hyprland.start", function()
    hl.exec_cmd("qs -c tamagotchi -n -d --log-rules 'quickshell.io.socket.warning=false'")
end)
for _, k in ipairs({ "plus", "KP_Add" }) do
    hl.bind(k, hl.dsp.exec_cmd("~/.config/quickshell/tamagotchi/toggle.sh plus"), { non_consuming = true })
end
for _, k in ipairs({ "minus", "KP_Subtract" }) do
    hl.bind(k, hl.dsp.exec_cmd("~/.config/quickshell/tamagotchi/toggle.sh minus"), { non_consuming = true })
end
hl.layer_rule({ match = { namespace = "mochi" }, no_anim = true })
