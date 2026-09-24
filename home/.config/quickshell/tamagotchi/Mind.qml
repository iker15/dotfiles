pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.UPower

// La "cabeza" de Mochi fuera de Claude: se entera de lo que haces (ventanas, música,
// batería, hora, workspaces) y reacciona con los ojos. No habla por su cuenta (Iker no
// quiere comentarios espontáneos); lo único que dice solo es el aviso de batería baja.
// shell.qml escucha sus señales; Brain usa `context` para que Claude sepa qué pasa.
Singleton {
    id: root

    signal react(string face, int ms)       // gesto con los ojos
    signal say(string text, string face)
    signal glance(real x, real y)           // mirar hacia un punto de la pantalla
    signal dance(int ms)
    signal shape(string name, int ms)       // imitar una forma con el cuerpo
    signal coding()                         // estás escribiendo código en VSCodium

    // Música
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? null
    readonly property bool musicPlaying: player !== null
    property string lastTrack: ""

    // Ventana activa
    readonly property var activeWin: Hyprland.activeToplevel
    readonly property string activeClass: String(activeWin?.lastIpcObject?.class || activeWin?.wayland?.appId || "")
    readonly property string activeTitle: activeWin?.title ?? ""

    // Batería (percentage 0-1)
    readonly property var battery: UPower.displayDevice
    readonly property real batteryLevel: battery?.ready ? battery.percentage : -1
    property bool warnedLow: false
    property bool warnedCritical: false

    property var wsTimes: []

    // Por título de ventana (Hyprland avisa de cada cambio): lo que era cada ventana la última
    // vez, para reaccionar solo al pasar de una cosa a otra
    property var wasClaude: ({})     // dirección → la terminal tenía Claude Code
    property var wasDirty: ({})      // dirección → VSCodium con cambios sin guardar
    property real codingUntil: 0     // (para no repetirlo a cada rato)

    // Claude Code pone en la terminal su símbolo delante del título (✳, ◑, ⠂…)
    function isClaudeTitle(t: string): bool {
        return /^[✳✢✶✻✽·◐◑◒◓◴◵◶◷\u2800-\u28FF]\s/.test(t) && !/— (Zen|Mozilla|Firefox)|Chromium|Brave/.test(t);
    }
    function isCodium(t: string): bool {
        return /(VSCodium|Visual Studio Code)$/.test(t);
    }

    function onTitle(addr: string, title: string): void {
        // Abres Claude en una terminal: se convierte en su destello un momento
        const claude = isClaudeTitle(title);
        if (addr in wasClaude && claude && !wasClaude[addr])
            shape("claude", 3200);
        wasClaude[addr] = claude;
        // VSCodium: pasa a tener cambios sin guardar (estás escribiendo)
        if (isCodium(title)) {
            const dirty = title.startsWith("●");
            if (addr in wasDirty && dirty && !wasDirty[addr] && Date.now() > codingUntil) {
                codingUntil = Date.now() + 90000;
                coding();
            }
            wasDirty[addr] = dirty;
        }
    }

    Component.onCompleted: {
        // (lo que ya estaba abierto no cuenta como "acabo de abrir")
        for (const t of Hyprland.toplevels.values) {
            const addr = t.address, title = t.title ?? "";
            wasClaude[addr] = isClaudeTitle(title);
            if (isCodium(title))
                wasDirty[addr] = title.startsWith("●");
        }
    }

    // Lo que Claude recibe con cada mensaje, para saber qué está pasando
    function context(): string {
        const now = new Date();
        const parts = [`son las ${Qt.formatTime(now, "HH:mm")} del ${Qt.formatDate(now, "dddd d 'de' MMMM")}`];
        if (activeClass)
            parts.push(`ventana activa: ${activeClass} «${activeTitle.slice(0, 80)}»`);
        if (player)
            parts.push(`suena «${player.trackTitle}»${player.trackArtist ? " de " + player.trackArtist : ""}`);
        if (batteryLevel >= 0)
            parts.push(`batería ${Math.round(batteryLevel * 100)}%${UPower.onBattery ? "" : " (enchufado)"}`);
        return parts.join("; ");
    }

    // Qué tipo de app es y qué le parece a Mochi
    readonly property var appKinds: [
        {
            re: /steam_app|^steam$|lutris|heroic|minecraft|prismlauncher|retroarch|gamescope/,
            kind: "game",
            face: "excited"
        },
        {
            re: /codium|^code|zed|jetbrains|neovide/,
            kind: "code",
            face: "focused"
        },
        {
            re: /bambu|orca|prusa|cura|slicer/,
            kind: "print",
            face: "excited"
        },
        {
            re: /blender|freecad|openscad/,
            kind: "model",
            face: "curious"
        },
        {
            re: /discord|vesktop|telegram|whatsapp|signal/,
            kind: "chat",
            face: "playful"
        },
        {
            re: /spotify/,
            kind: "music",
            face: "dance"
        },
        {
            re: /obsidian|libreoffice|onlyoffice|typora/,
            kind: "write",
            face: "focused"
        },
        {
            re: /nautilus|thunar|dolphin|nemo|yazi/,
            kind: "files",
            face: "curious"
        },
        {
            re: /kitty|foot|alacritty|wezterm|ghostty/,
            kind: "term",
            face: "focused"
        },
        {
            re: /zen|firefox|chrom|brave|vivaldi|librewolf/,
            kind: "web",
            face: "curious"
        }
    ]

    function kindOf(cls: string): var {
        cls = cls.toLowerCase();
        return appKinds.find(k => k.re.test(cls)) ?? null;
    }

    // Ventana nueva: la mira y pone cara según lo que sea
    function onWindowOpened(cls: string): void {
        const k = kindOf(cls);
        react(k ? k.face : "curious", 1600);

    }

    Connections {
        target: Hyprland

        function onRawEvent(event: var): void {
            const name = event.name;
            if (name === "windowtitlev2") {
                const [addr, title] = event.parse(2);
                root.onTitle(addr ?? "", title ?? "");
            } else if (name === "openwindow") {
                const [addr, , cls] = event.parse(4);
                root.wasClaude[addr] = false;   // ventana nueva: aún no tiene Claude
                root.wasDirty[addr] = false;
                root.onWindowOpened(cls ?? "");
                glanceLater.restart();
            } else if (name === "workspacev2") {
                // Muchos cambios de workspace seguidos → se marea
                const now = Date.now();
                const times = root.wsTimes.filter(t => now - t < 2500);
                times.push(now);
                root.wsTimes = times;
                if (times.length >= 6) {
                    root.wsTimes = [];
                    root.react("dizzy", 2200);
                }
            } else if (name === "closewindow") {
                root.react("surprised", 450);
            } else if (name === "urgent") {
                root.react("curious", 1500);
            }
        }
    }

    // Mirar hacia la ventana que acaba de aparecer
    Timer {
        id: glanceLater

        interval: 180
        onTriggered: {
            Hyprland.refreshToplevels();
            glanceRead.restart();
        }
    }

    Timer {
        id: glanceRead

        interval: 150
        onTriggered: {
            const o = Hyprland.activeToplevel?.lastIpcObject;
            if (o?.at && o?.size)
                root.glance(o.at[0] + o.size[0] / 2, o.at[1] + o.size[1] / 2);
        }
    }

    // Música: baila un poco cuando empieza una canción
    Connections {
        target: root.player

        function onTrackTitleChanged(): void {
            root.newTrack();
        }
    }

    onPlayerChanged: newTrack()

    function newTrack(): void {
        if (!player || !player.trackTitle || player.trackTitle === lastTrack)
            return;
        lastTrack = player.trackTitle;
        dance(5000);
    }

    // Batería
    onBatteryLevelChanged: {
        if (batteryLevel < 0 || !UPower.onBattery)
            return;
        if (batteryLevel < 0.07 && !warnedCritical) {
            warnedCritical = true;
            say("¡Que me apago! Enchúfame, porfa 🪫", "sad");
        } else if (batteryLevel < 0.15 && !warnedLow) {
            warnedLow = true;
            say("Me estoy quedando sin pilas… ¿me enchufas? 🔋", "sorry");
        }
    }

    Connections {
        target: UPower

        function onOnBatteryChanged(): void {
            if (!UPower.onBattery) {
                root.warnedLow = root.warnedCritical = false;
                root.react("happy", 1500);
            }
        }
    }

    // Hora: si es muy tarde, bosteza de vez en cuando
    Timer {
        running: true
        repeat: true
        interval: 10 * 60000
        onTriggered: {
            const h = new Date().getHours();
            if (h >= 1 && h < 5)
                root.react("yawn", 1800);
        }
    }
}
