pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Cariño: lo que te quiere Mochi (0-100). Sube al hablarle, acariciarlo, cogerlo y, un poco,
// solo con estar en el PC con él cerca (con tope diario, para que no se pueda "farmear").
// Si pasas días sin hacerle caso baja y se enfurruña (sulky) hasta que te reconcilias con él.
// Se guarda en ~/.local/state/tamagotchi/bond.json.
Singleton {
    id: root

    property real bond: 30
    property real lastTouch: Date.now()   // última vez que le hiciste caso de verdad (ms)
    property real lastDecay: Date.now()
    property real lastSeen: Date.now()    // última vez que estuvo en marcha (para saludarte al volver)
    property string day: ""
    property real gainedToday: 0
    property real presenceToday: 0
    property bool loaded: false
    // Al arrancar: cuánto hacía que no te veía (h)
    property real awayHours: 0

    readonly property real level: bond / 100
    property real now: Date.now()
    readonly property bool sulky: loaded && now - lastTouch > 2 * 86400000

    signal reconciled()   // estaba enfurruñado y le has hecho caso (la segunda vez)
    signal pouted()       // estaba enfurruñado y le haces caso: la primera vez te gira la cara
    property real poutAt: 0

    readonly property var gains: ({
            talk: 2,
            pet: 1.5,
            hold: 0.5,
            presence: 0.25
        })
    readonly property var cooldown: ({
            talk: 20000,
            pet: 30000,
            hold: 20000,
            presence: 0
        })
    property var lastGain: ({})

    function gain(kind: string): void {
        if (!loaded)
            return;
        const t = Date.now();
        rollDay();
        if (kind !== "presence") {
            if (sulky) {
                // primero se hace el ofendido; si insistes (al rato), te perdona
                if (!poutAt || t - poutAt > 120000) {
                    poutAt = t;
                    pouted();
                    return;
                }
                if (t - poutAt < 2500)
                    return;
                poutAt = 0;
                lastTouch = t;
                now = t;
                reconciled();
            } else {
                lastTouch = t;
                now = t;
            }
        }
        if (t - (lastGain[kind] ?? 0) < cooldown[kind])
            return;
        lastGain[kind] = t;
        let g = Math.min(gains[kind], 14 - gainedToday);   // tope diario
        if (kind === "presence")
            g = Math.min(g, 3 - presenceToday);            // estar cerca cuenta, pero poco
        if (g <= 0)
            return;
        bond = Math.min(100, bond + g);
        gainedToday += g;
        if (kind === "presence")
            presenceToday += g;
        save.restart();
    }

    function rollDay(): void {
        const d = Qt.formatDate(new Date(), "yyyy-MM-dd");
        if (d !== day) {
            day = d;
            gainedToday = 0;
            presenceToday = 0;
        }
    }

    // Echarte de menos: tras 2 días sin hacerle caso, −5 por día
    function decay(): void {
        const t = Date.now(), from = Math.max(lastDecay, lastTouch + 2 * 86400000);
        if (t > from) {
            bond = Math.max(0, bond - 5 * (t - from) / 86400000);
            save.restart();
        }
        lastDecay = t;
    }

    Timer {
        running: root.loaded
        repeat: true
        interval: 60000
        onTriggered: {
            root.now = Date.now();
            root.lastSeen = root.now;
            root.decay();
            save.restart();
        }
    }

    Timer {
        id: save

        interval: 500
        onTriggered: file.setText(JSON.stringify({
                bond: Math.round(root.bond * 100) / 100,
                lastTouch: root.lastTouch,
                lastDecay: root.lastDecay,
                lastSeen: root.lastSeen,
                day: root.day,
                gainedToday: root.gainedToday,
                presenceToday: root.presenceToday
            }))
    }

    FileView {
        id: file

        path: `${Quickshell.env("HOME")}/.local/state/tamagotchi/bond.json`
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.bond = d.bond ?? 30;
                root.lastTouch = d.lastTouch ?? Date.now();
                root.lastDecay = d.lastDecay ?? Date.now();
                root.lastSeen = d.lastSeen ?? Date.now();
                root.day = d.day ?? "";
                root.gainedToday = d.gainedToday ?? 0;
                root.presenceToday = d.presenceToday ?? 0;
            } catch (e) {}
            root.start();
        }
        onLoadFailed: root.start()   // (primera vez)
    }

    function start(): void {
        if (loaded)
            return;
        const t = Date.now();
        awayHours = (t - lastSeen) / 3600000;
        lastSeen = t;
        now = t;
        rollDay();
        loaded = true;
        decay();
        save.restart();
    }
}
