pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "Traits.js" as Traits

// Cómo es TU Mochi (lo creas en su pestaña del dashboard de Caelestia antes de que nazca).
// Siempre es una gotita blanda con dos ojos; aquí van los detalles: ojos (tamaño, separación,
// altura y forma), cuerpo (proporción y blandura; la silueta es siempre su blob), su carácter
// (rasgos de Traits.js: 3 al principio, más al subir de nivel) y un mote. Se llama Mochi siempre.
// Vive en ~/.local/state/tamagotchi/look.json (no en los dotfiles: cada persona crea el suyo).
// Sin ese fichero Mochi aún no ha nacido y no aparece en ningún sitio.
// (Lo usan el escritorio, la ficha del bloqueo y el dashboard: cada uno con su copia.)
Singleton {
    id: root

    readonly property string path: `${Quickshell.env("HOME")}/.local/state/tamagotchi/look.json`
    property bool loaded: false
    property bool born: false
    signal bornNow   // acaba de nacer (no al arrancar si ya existía)

    readonly property string name: "Mochi"
    property string nick: ""     // mote (opcional)
    property var traits: []      // ids de Traits.js
    property real eyeSize: 1     // 0.7-1.45
    property real eyeGap: 1      // 0.75-1.3 (separación)
    property real eyeY: 0        // −1 (arriba) … 1 (abajo)
    property real eyeShape: 0    // −0.6 ovalados anchos · 0 redondos · 1 alargados
    property real wide: 1        // 0.85 alto y estrecho … 1.2 ancho y bajito
    property real jelly: 1       // 0.5 firme … 1.6 gelatina

    readonly property var ranges: ({
            eyeSize: [0.7, 1.45, 1],
            eyeGap: [0.75, 1.3, 1],
            eyeY: [-1, 1, 0],
            eyeShape: [-0.6, 1, 0],
            wide: [0.85, 1.2, 1],
            jelly: [0.5, 1.6, 1]
        })

    function clean(o: var): var {
        const r = {
            nick: String(o?.nick ?? "").slice(0, 16),
            traits: Traits.clean(o?.traits, 6)
        };
        for (const k in ranges) {
            const [lo, hi, def] = ranges[k];
            const v = Number(o?.[k]);
            r[k] = isNaN(v) ? def : Math.max(lo, Math.min(hi, v));
        }
        return r;
    }

    function data(): var {
        const o = {
            nick: nick,
            traits: traits.slice()
        };
        for (const k in ranges)
            o[k] = root[k];
        return o;
    }

    function apply(o: var): void {
        const c = clean(o);
        for (const k in c)
            root[k] = c[k];
    }

    // ¿Tiene este rasgo?
    function has(id: string): bool {
        return traits.includes(id);
    }

    // (lo usa el creador del dashboard) escribe el fichero; con born = false lo borra
    function save(o: var, isBorn: bool): void {
        if (!isBorn) {
            Quickshell.execDetached(["rm", "-f", path]);
            return;
        }
        const c = clean(o);
        c.born = true;
        c.created = o?.created ?? new Date().toISOString();
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf "%s" "$2" > "$1.tmp" && mv "$1.tmp" "$1"', "sh", path, JSON.stringify(c)]);
    }

    FileView {
        id: file

        path: root.path
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let o = null;
            try {
                o = JSON.parse(text());
            } catch (e) {}
            if (!o) {
                root.born = false;
                root.loaded = true;
                return;
            }
            root.apply(o);
            const was = root.born, first = !root.loaded;
            root.born = o.born !== false;
            root.loaded = true;
            if (root.born && !was && !first)
                root.bornNow();
        }
        onLoadFailed: {
            root.born = false;
            root.loaded = true;
        }
    }

    // Si aún no existe, FileView no se entera de cuándo aparece: se mira cada poco
    Timer {
        running: root.loaded && !root.born
        repeat: true
        interval: 1200
        onTriggered: file.reload()
    }
}
