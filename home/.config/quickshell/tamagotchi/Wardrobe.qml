pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "Skins.js" as Skins

// Transformaciones de Mochi (Skins.js): las que ha aprendido, la que lleva y las que le
// quedan por elegir. Cada 5 niveles le salen 3 al azar y eliges una (las otras dos pueden volver
// a salir más adelante). Se guarda en ~/.local/state/tamagotchi/skins.json (no en los dotfiles).
// Solo escribe el Mochi del escritorio (`writer`); el dashboard lo lee y le pide cosas por IPC.
Singleton {
    id: root

    property bool writer: false
    property bool loaded: false
    property var owned: []          // ids aprendidas, en orden
    property string wearing: ""     // la que lleva puesta ("" = él mismo)
    property var picks: ({})        // nivel → { offer: [3 ids], chosen: id | "" }

    // Primer nivel con una elección pendiente (0 = ninguna)
    readonly property int pendingLevel: {
        const ls = Object.keys(picks).map(Number).filter(l => !picks[l].chosen).sort((a, b) => a - b);
        return ls.length ? ls[0] : 0;
    }
    readonly property var pendingOffer: pendingLevel ? picks[pendingLevel].offer : []

    signal unlocked(int level)   // (escritorio) le acaban de salir opciones nuevas

    function data(): var {
        return {
            owned: owned,
            wearing: wearing,
            picks: picks
        };
    }

    // (escritorio) al subir de nivel: prepara las opciones de cada múltiplo de 5 alcanzado
    function sync(level: int): void {
        if (!writer || !loaded)
            return;
        let changed = false, fresh = 0;
        const p = Object.assign({}, picks);
        for (const l of Skins.milestones(level)) {
            if (p[l])
                continue;
            // (no repite las que ya tiene ni las que le están ofreciendo en otro nivel)
            const taken = owned.slice();
            for (const k in p)
                if (!p[k].chosen)
                    taken.push(...p[k].offer);
            const offer = Skins.roll(taken);
            if (!offer.length)
                break;   // ya las tiene todas
            p[l] = {
                offer: offer,
                chosen: ""
            };
            changed = true;
            fresh = l;
        }
        if (changed) {
            picks = p;
            save();
            unlocked(fresh);
        }
    }

    function pick(level: int, id: string): bool {
        const e = picks[level];
        if (!writer || !e || e.chosen || !e.offer.includes(id))
            return false;
        const p = Object.assign({}, picks);
        p[level] = {
            offer: e.offer,
            chosen: id
        };
        picks = p;
        if (!owned.includes(id))
            owned = owned.concat([id]);
        save();
        return true;
    }

    function wear(id: string): bool {
        if (!writer || (id && !owned.includes(id)))
            return false;
        wearing = id;
        save();
        return true;
    }

    // Empezar de cero: un Mochi nuevo no sabe transformarse
    function reset(): void {
        owned = [];
        wearing = "";
        picks = {};
        save();
    }

    function save(): void {
        if (writer)
            file.setText(JSON.stringify(data()));
    }

    function apply(o: var): void {
        owned = (o?.owned ?? []).filter(id => !!Skins.byId(id));
        wearing = owned.includes(o?.wearing) ? o.wearing : "";
        const p = {};
        for (const k in (o?.picks ?? {})) {
            const e = o.picks[k];
            if (e && Array.isArray(e.offer))
                p[k] = {
                    offer: e.offer.filter(id => !!Skins.byId(id)),
                    chosen: e.chosen || ""
                };
        }
        picks = p;
    }

    FileView {
        id: file

        path: `${Quickshell.env("HOME")}/.local/state/tamagotchi/skins.json`
        atomicWrites: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.apply(JSON.parse(text()));
            } catch (e) {}
            root.loaded = true;
        }
        onLoadFailed: {
            root.apply({});
            root.loaded = true;
        }
    }
}
