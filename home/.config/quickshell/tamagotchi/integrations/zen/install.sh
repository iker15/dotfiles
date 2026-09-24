#!/usr/bin/env bash
# Instala la integración de Mochi en Zen: la extensión (sin firmar: Zen lo permite con
# xpinstall.signatures.required=false) y el host nativo que la conecta con Mochi.
# Después hay que reiniciar Zen.
set -e
here=$(cd "$(dirname "$0")" && pwd)
"$here/../build-web.sh"

# Host nativo (Zen lo busca como Firefox). ¡NUNCA crear ~/.zen!: si esa carpeta existe, Zen la
# usa como perfil (la ruta antigua) y arranca con un perfil vacío, sin tus pestañas.
host="$here/mochi_host.py"
chmod +x "$host"
for d in ~/.mozilla/native-messaging-hosts ~/.config/zen/native-messaging-hosts; do
    mkdir -p "$d"
    cat > "$d/mochi.json" <<JSON
{
    "name": "mochi",
    "description": "Mochi (Quickshell) ↔ Zen",
    "path": "$host",
    "type": "stdio",
    "allowed_extensions": ["mochi@iker"]
}
JSON
done

# La extensión, en los perfiles de Zen
xpi=$(mktemp -u /tmp/mochi-XXXX.xpi)
python3 -c "import shutil,sys; shutil.make_archive(sys.argv[1][:-4], 'zip', sys.argv[2]); import os; os.replace(sys.argv[1][:-4] + '.zip', sys.argv[1])" "$xpi" "$here/extension"
for p in ~/.config/zen/*/; do
    [[ -f "$p/prefs.js" ]] || continue
    mkdir -p "$p/extensions"
    cp "$xpi" "$p/extensions/mochi@iker.xpi"
    # extensiones sin firmar, y que las que están en el perfil se activen sin preguntar
    touch "$p/user.js"
    grep -q 'xpinstall.signatures.required' "$p/user.js" || echo 'user_pref("xpinstall.signatures.required", false);' >> "$p/user.js"
    grep -q 'extensions.autoDisableScopes' "$p/user.js" || echo 'user_pref("extensions.autoDisableScopes", 14);' >> "$p/user.js"
    # Colores del fondo de pantalla (matugen escribe ~/.config/zen/matugen.css): enlazado en su
    # chrome/ e importado desde userChrome.css
    grep -q 'toolkit.legacyUserProfileCustomizations.stylesheets' "$p/user.js" || echo 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' >> "$p/user.js"
    mkdir -p "$p/chrome"
    if [[ -f "$p/chrome/matugen.css" && ! -L "$p/chrome/matugen.css" ]]; then
        [[ -f ~/.config/zen/matugen.css ]] || cp "$p/chrome/matugen.css" ~/.config/zen/matugen.css
        rm -f "$p/chrome/matugen.css"
    fi
    touch ~/.config/zen/matugen.css
    ln -sfn ~/.config/zen/matugen.css "$p/chrome/matugen.css"
    touch "$p/chrome/userChrome.css"
    grep -q 'matugen.css' "$p/chrome/userChrome.css" || sed -i '1i @import url("matugen.css");' "$p/chrome/userChrome.css"
    [[ -s "$p/chrome/userChrome.css" ]] || echo '@import url("matugen.css");' > "$p/chrome/userChrome.css"
    echo "Instalada en $p"
done
rm -f "$xpi"
echo "Reinicia Zen para cargarla."
