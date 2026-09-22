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

-- Mochi (mascota con Claude): doble + para mostrar/ocultar.
-- non_consuming: el + se sigue escribiendo normal en las apps
hl.bind("plus", hl.dsp.exec_cmd("~/.config/quickshell/tamagotchi/toggle.sh"), { non_consuming = true })
hl.layer_rule({ match = { namespace = "tamagotchi" }, animation = "fade", blur = true, ignore_alpha = 0.5 })
