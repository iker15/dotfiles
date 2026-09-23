import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

// Mochi: burbujita negra que vive en el escritorio, con Claude Code como cerebro.
// - Tiene gravedad: vive en el suelo de la pantalla, da saltitos y se le puede lanzar.
// - Si no le haces caso en un rato se esconde por debajo del borde (asoma los ojos).
// - Clic (o doble +) para hablarle; lo que escribes y su respuesta salen como subtítulos encima.
// - Vive en un workspace: si cambias de workspace, al rato viene detrás de ti (sin ponerse
//   bajo el ratón). Lanzándolo contra un lado atraviesa el borde y sigue su trayectoria por los
//   workspaces de ese lado hasta que se le acaba el impulso.
// - Mind.qml le hace reaccionar (con los ojos) a lo que haces; acariciarlo (pasar el ratón de lado a lado) le encanta.
// IPC: qs -c tamagotchi ipc call pet toggle|appear|hide|talk|ask "<texto>"|face <cara>|state
ShellRoot {
    id: shell

    readonly property string stateDir: Brain.stateDir

    property bool shown: true
    property bool asking: false        // campo de texto abierto
    property bool bubbleShown: false   // bocadillo con la respuesta
    property bool dragging: false

    // Centro de Mochi en coordenadas globales (todas las pantallas)
    property real gx: -1
    property real gy: -1

    property real lookX: 0
    property real lookY: 0

    // Voz: ears.py escucha el micro y avisa al oír "Mochi"
    property bool earsOn: true
    property bool earsReady: false
    property bool voiceWaiting: false  // ha oído "Mochi" y espera la orden
    property string heard: ""          // última orden dictada (se enseña mientras piensa)

    // Física: held (agarrado), air (volando/cayendo), ground (en el suelo), hidden (escondido)
    property string phys: "air"
    property real vx: 0
    property real vy: 0
    property real hvx: 0          // velocidad del ratón al arrastrar (para lanzarlo)
    property real hvy: 0
    property real prevX: 0
    property real prevY: 0
    property int reversals: 0     // sacudidas al arrastrar → mareo
    property int lastDir: 0
    property int hopsLeft: 0
    property int hopDir: 1
    property bool cursorNear: false
    property bool lightBody: false      // fondo oscuro → Mochi blanco
    readonly property real bodyRx: 32 * 1.45   // igual que Blob.rx / Blob.ry
    readonly property real bodyRy: 29 * 1.45
    readonly property int hideAfter: 180000    // ms sin usarlo hasta que se esconde

    // Workspaces
    property int mochiWs: -1              // workspace donde vive
    property bool entering: false         // entrando por un lado de la pantalla (sin paredes)
    property bool thrown: false           // lanzado a mano: puede cruzar a otro workspace
    property bool flung: false            // ha cruzado a otro workspace en este lanzamiento
    property real targetX: NaN            // sitio al que va dando saltos
    property real sulkUntil: 0            // tras lanzarlo a otro workspace, se queda allí un rato
    readonly property bool present: mochiWs < 0 || Hyprland.monitors.values.some(m => m.activeWorkspace?.id === mochiWs)
    readonly property bool fsHide: Hyprland.workspaces.values.find(w => w.id === mochiWs)?.hasFullscreen ?? false

    property real cursorX: 0
    property real cursorY: 0
    property real glanceX: 0              // mirar a otro sitio un momento (ventana nueva…)
    property real glanceY: 0
    property real glanceUntil: 0
    property string remark: ""            // comentario espontáneo en el bocadillo

    signal splatted(real strength, bool horizontal)
    signal reacted(string name, int ms)

    readonly property string mood: (asking || voiceWaiting) && !Brain.busy ? "listening" : Brain.mood

    function screenAt(x: real, y: real): var {
        for (const s of Quickshell.screens)
            if (x >= s.x && x < s.x + s.width && y >= s.y && y < s.y + s.height)
                return s;
        return null;
    }

    function nearestScreen(x: real, y: real): var {
        let s = screenAt(x, y);
        if (s)
            return s;
        let best = Infinity;
        for (const c of Quickshell.screens) {
            const dx = Math.max(c.x - x, 0, x - (c.x + c.width));
            const dy = Math.max(c.y - y, 0, y - (c.y + c.height));
            if (dx + dy < best) {
                best = dx + dy;
                s = c;
            }
        }
        return s;
    }

    // Que no se quede fuera de ninguna pantalla
    function settle(): void {
        const s = nearestScreen(gx, gy);
        if (!s)
            return;
        gx = Math.max(s.x + 55, Math.min(s.x + s.width - 55, gx));
        gy = Math.max(s.y + 55, Math.min(s.y + s.height - 55, gy));
    }

    function savePos(): void {
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && printf "%s %s" "$2" "$3" > "$1/pos"', "sh", stateDir, Math.round(gx), Math.round(gy)]);
    }

    function screenOfMonitor(m: var): var {
        return Quickshell.screens.find(q => q.name === m?.name) ?? Quickshell.screens[0];
    }

    // Un sitio en el suelo lejos del ratón y mejor hacia los lados (el centro de abajo suele
    // tener cosas: reproductores, barras…), para no taparte lo que estás mirando
    function spotFor(s: var): real {
        const onScreen = cursorX >= s.x && cursorX < s.x + s.width;
        let best = s.x + s.width * 0.08, bestScore = -1;
        for (const f of [0.06, 0.14, 0.3, 0.7, 0.86, 0.94]) {
            const x = s.x + s.width * f;
            const score = (onScreen ? Math.abs(x - cursorX) : 500) + 500 * Math.abs(f - 0.5) + Math.random() * 200;
            if (score > bestScore) {
                bestScore = score;
                best = x;
            }
        }
        return best;
    }

    // Llega al workspace en el que estás: entra saltando por el lado del que viene
    function arrive(): void {
        const ws = Hyprland.focusedWorkspace;
        if (!ws)
            return;
        const s = screenOfMonitor(Hyprland.focusedMonitor);
        const fromLeft = mochiWs >= 0 && mochiWs < ws.id;
        mochiWs = ws.id;
        sinkAnim.stop();
        hopsLeft = 0;
        targetX = spotFor(s);
        entering = true;
        gx = fromLeft ? s.x - bodyRx : s.x + s.width + bodyRx;
        gy = s.y + s.height - bodyRy - 80;
        vx = fromLeft ? 560 : -560;
        vy = -560;
        phys = "air";
        reacted("excited", 1300);
    }

    // Lo has llamado (++, voz, clic…) y no está aquí: sale de un salto desde abajo
    function summon(): void {
        const ws = Hyprland.focusedWorkspace;
        if (!ws)
            return;
        const s = screenOfMonitor(Hyprland.focusedMonitor);
        mochiWs = ws.id;
        sinkAnim.stop();
        hopsLeft = 0;
        targetX = NaN;
        entering = false;
        gx = spotFor(s);
        gy = s.y + s.height + bodyRy;
        vx = 0;
        vy = -1150;
        phys = "air";
        reacted("happy", 900);
    }

    // Has cambiado de workspace: si no está a la vista, al rato viene detrás de ti
    function wsChanged(): void {
        const ws = Hyprland.focusedWorkspace;
        if (!ws)
            return;
        if (mochiWs < 0 || phys === "held") {   // si lo llevas agarrado, viene contigo
            mochiWs = ws.id;
            return;
        }
        if (mochiWs === ws.id)
            return;
        // (si sigue a la vista en otro monitor, followTimer no hace nada)
        const now = Date.now();
        followTimer.interval = Brain.busy || bubbleShown ? 700 : now < sulkUntil ? sulkUntil - now : 2500 + Math.random() * 5000;
        followTimer.restart();
    }

    // Lanzado contra un lado con fuerza: atraviesa el borde y sigue volando por el
    // workspace de ese lado (si hay). Si al llegar al otro borde aún va rápido, pasa al
    // siguiente, y así hasta que se le acabe el impulso.
    function crossToWs(dir: int, s: var): bool {
        const ids = Hyprland.workspaces.values.map(w => w.id).filter(id => id > 0).sort((a, b) => a - b);
        const next = dir > 0 ? ids.find(id => id > mochiWs) : ids.filter(id => id < mochiWs).pop();
        if (next === undefined)
            return false;
        mochiWs = next;
        flung = true;
        entering = true;
        targetX = NaN;
        gx = dir > 0 ? s.x - bodyRx * 0.5 : s.x + s.width + bodyRx * 0.5;
        vx *= 0.9;
        return true;
    }

    // Acariciarlo con el ratón
    function pet(): void {
        touch();
        reacted("love", 2400);
        splatted(420, false);
    }

    // Cualquier uso: reinicia la cuenta para esconderse y, si estaba escondido o en otro
    // workspace, viene
    function touch(): void {
        idleHide.restart();
        if (!present) {
            summon();
            return;
        }
        if (phys === "hidden") {
            sinkAnim.stop();
            phys = "air";
            vx = 0;
            vy = -780;
            reacted("happy", 800);
        }
    }

    function hop(): void {
        const s = nearestScreen(gx, gy);
        if (!s || phys !== "ground")
            return;
        // Cerca de una pared, dar la vuelta
        if (gx - s.x < 180)
            hopDir = 1;
        else if (s.x + s.width - gx < 180)
            hopDir = -1;
        else if (cursorY > s.y + s.height - 300 && Math.abs(cursorX - gx) < 350)
            hopDir = cursorX > gx ? -1 : 1;   // no ir hacia el ratón
        const big = Math.random() < 0.15;
        vx = hopDir * (big ? 260 : 120 + Math.random() * 120);
        vy = big ? -950 : -(430 + Math.random() * 180);
        hopsLeft--;
        phys = "air";
    }

    function checkBg(): void {
        const s = nearestScreen(gx, gy);
        if (!s || bgProc.running)
            return;
        bgProc.command = [Quickshell.shellDir + "/bg.py", gx, gy, bodyRx, bodyRy, s.x, s.y, s.width, s.height].map(String);
        bgProc.running = true;
    }

    function landed(): void {
        thrown = false;
        // Ha acabado en otro workspace: se queda allí un par de minutos y luego vuelve contigo
        if (flung) {
            flung = false;
            if (!present) {
                sulkUntil = Date.now() + 120000;
                followTimer.interval = 120000;
                followTimer.restart();
                return;
            }
        }
        if (!present)
            return;
        savePos();
        checkBg();
        // Se queda en el workspace de la pantalla donde ha caído
        const id = Hyprland.monitorFor(nearestScreen(gx, gy))?.activeWorkspace?.id;
        if (id !== undefined && id > 0)
            mochiWs = id;
        if (!isNaN(targetX)) {
            if (Math.abs(targetX - gx) > 50) {
                travelAgain.restart();
                return;
            }
            targetX = NaN;
        }
        if (hopsLeft > 0)
            hopAgain.restart();
    }

    // Saltito hacia targetX
    function travelHop(): void {
        if (phys !== "ground" || isNaN(targetX))
            return;
        vx = Math.max(-480, Math.min(480, (targetX - gx) / 0.5));
        vy = -520;
        phys = "air";
    }

    function physStep(dt: real): void {
        dt = Math.min(dt, 1 / 30);
        if (phys === "held") {
            // Velocidad del arrastre (suavizada) y sacudidas
            hvx = hvx * 0.6 + (gx - prevX) / dt * 0.4;
            hvy = hvy * 0.6 + (gy - prevY) / dt * 0.4;
            prevX = gx;
            prevY = gy;
            if (Math.abs(hvx) > 700 && Math.sign(hvx) !== lastDir) {
                if (lastDir !== 0)
                    reversals++;
                lastDir = Math.sign(hvx);
            }
            return;
        }

        const s = nearestScreen(gx, gy);
        if (!s)
            return;
        vy += 2600 * dt;
        vx *= 1 - 0.25 * dt;
        let nx = gx + vx * dt, ny = gy + vy * dt;
        const left = s.x + bodyRx, right = s.x + s.width - bodyRx;
        const top = s.y + bodyRy, floor = s.y + s.height - bodyRy;

        // Paredes (salvo que al otro lado haya otra pantalla, o esté entrando)
        if (entering) {
            if (nx >= left && nx <= right)
                entering = false;
        } else if (nx < left && !screenAt(nx - bodyRx, ny)) {
            if (thrown && vx < -1100 && crossToWs(-1, s))
                return;
            nx = left;
            if (vx < -300)
                splatted(-vx, true);
            vx = Math.abs(vx) * 0.45;
        } else if (nx > right && !screenAt(nx + bodyRx, ny)) {
            if (thrown && vx > 1100 && crossToWs(1, s))
                return;
            nx = right;
            if (vx > 300)
                splatted(vx, true);
            vx = -Math.abs(vx) * 0.45;
        }
        if (ny < top && vy < 0 && !screenAt(nx, ny - bodyRy)) {
            ny = top;
            vy = Math.abs(vy) * 0.3;
        }
        // Suelo: rebota un poco y se aplasta
        if (ny > floor && vy > 0 && !screenAt(nx, ny + bodyRy)) {
            ny = floor;
            if (vy > 1300)
                reacted("squint", 500);
            if (vy > 250)
                splatted(vy, false);
            if (vy > 480) {
                vy = -vy * 0.32;
                vx *= 0.7;
            } else {
                vx = 0;
                vy = 0;
                phys = "ground";
                landed();
            }
        }
        gx = nx;
        gy = ny;
    }

    function openInput(): void {
        touch();
        shown = true;
        asking = true;
        bubbleShown = false;
    }

    function showReply(): void {
        bubbleShown = true;
        hideTimer.restart();
    }

    Component.onCompleted: {
        mochiWs = Hyprland.focusedWorkspace?.id ?? -1;
        const s = Quickshell.screens[0];
        if (gx < 0 && s) {
            gx = s.x + s.width - 120;
            gy = s.y + s.height - 140;
        }
    }

    FileView {
        path: shell.stateDir + "/pos"
        onLoaded: {
            const [x, y] = text().trim().split(" ").map(Number);
            if (!isNaN(x) && !isNaN(y)) {
                shell.gx = x;
                shell.gy = y;
                shell.settle();
            }
        }
    }

    Connections {
        target: Brain

        function onBusyChanged(): void {
            shell.touch();
            shell.remark = "";
            if (Brain.busy) {
                shell.bubbleShown = true;
                hideTimer.stop();
            } else {
                shell.showReply();
            }
        }
    }

    Connections {
        target: Hyprland

        function onFocusedWorkspaceChanged(): void {
            shell.wsChanged();
        }
    }

    Timer {
        id: followTimer

        onTriggered: if (shell.shown && !shell.present && shell.phys !== "hidden") shell.arrive()
    }

    // Lo que hace Mind: gestos, y solo habla para avisar de la batería (nunca interrumpe)
    Connections {
        target: Mind

        function onReact(face: string, ms: int): void {
            if (shell.present && !Brain.busy && !shell.asking && !shell.dragging && shell.phys !== "hidden")
                shell.reacted(face, ms);
        }
        function onDance(ms: int): void {
            if (shell.present && !Brain.busy && !shell.asking && !shell.dragging && shell.phys !== "hidden")
                shell.reacted("dance", ms);
        }
        function onGlance(x: real, y: real): void {
            shell.glanceX = x;
            shell.glanceY = y;
            shell.glanceUntil = Date.now() + 1400;
        }
        function onSay(text: string, face: string): void {
            if (!shell.shown || Brain.busy || shell.asking || shell.voiceWaiting || shell.dragging || (shell.bubbleShown && !shell.remark))
                return;
            if (!shell.present || shell.phys === "hidden")
                shell.touch();
            shell.remark = text;
            shell.bubbleShown = true;
            hideTimer.restart();
            shell.reacted(face, 2500);
        }
    }

    onBubbleShownChanged: if (!bubbleShown) remark = ""
    onAskingChanged: if (asking) remark = ""

    // El bocadillo se va solo al rato (más tiempo cuanto más largo)
    Timer {
        id: hideTimer

        interval: shell.remark ? 5500 : Math.min(30000, 6000 + Brain.reply.length * 45)
        onTriggered: if (!Brain.busy) shell.bubbleShown = false
    }

    // Si el oído se cae, volver a lanzarlo
    Timer {
        id: earsRestart

        interval: 2000
        onTriggered: if (shell.earsOn) ears.running = true
    }

    Process {
        id: ears

        command: [Quickshell.shellDir + "/ears.sh"]
        running: shell.earsOn

        stdout: SplitParser {
            onRead: line => {
                if (line === "ready") {
                    shell.earsReady = true;
                } else if (line === "wake" || line === "hearing") {
                    shell.touch();
                    shell.shown = true;
                    shell.asking = false;
                    shell.voiceWaiting = true;
                    shell.bubbleShown = false;
                } else if (line.startsWith("text:")) {
                    shell.voiceWaiting = false;
                    shell.shown = true;
                    shell.asking = false;
                    shell.heard = line.slice(5).trim();
                    Brain.send(shell.heard, true);
                } else if (line === "idle") {
                    shell.voiceWaiting = false;
                } else if (line.startsWith("error:")) {
                    console.warn("ears:", line);
                    shell.earsOn = false;
                }
            }
        }

        onExited: {
            shell.earsReady = false;
            shell.voiceWaiting = false;
            if (shell.earsOn)
                earsRestart.restart();
        }
    }

    IpcHandler {
        target: "pet"

        // Doble +: si está a la vista se esconde; si no, aparece y escucha
        function toggle(): void {
            if (shell.shown) {
                shell.asking = false;
                shell.shown = false;
            } else {
                shell.openInput();
            }
        }
        function appear(): void {
            shell.touch();
            shell.shown = true;
        }
        function hide(): void {
            shell.asking = false;
            shell.shown = false;
        }
        function talk(): void {
            shell.openInput();
        }
        function ears(): void {
            shell.earsOn = !shell.earsOn;
        }
        function history(): void {
            Qt.openUrlExternally("file://" + Brain.historyDir);
        }
        // Probar una expresión (ver eyeTarget en Blob.qml)
        function face(name: string): void {
            shell.reacted(name, 2500);
        }
        function state(): string {
            return `${shell.phys} ${Math.round(shell.gx)},${Math.round(shell.gy)} v=${Math.round(shell.vx)},${Math.round(shell.vy)} ws=${shell.mochiWs} present=${shell.present} shown=${shell.shown}`;
        }
        function ask(text: string): void {
            shell.touch();
            shell.shown = true;
            shell.asking = false;
            Brain.send(text);
        }
    }

    // Posición del cursor (para que Mochi te mire), preguntando a Hyprland por su socket
    Socket {
        id: hypr

        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/hypr/${Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")}/.socket.sock`

        onConnectedChanged: {
            if (connected) {
                write("j/cursorpos");
                flush();
            }
        }

        parser: SplitParser {
            splitMarker: "}"
            onRead: data => {
                try {
                    const p = JSON.parse(data + "}");
                    shell.cursorX = p.x;
                    shell.cursorY = p.y;
                    // Mira al ratón, salvo que algo le haya llamado la atención
                    const glancing = Date.now() < shell.glanceUntil;
                    const dx = (glancing ? shell.glanceX : p.x) - shell.gx, dy = (glancing ? shell.glanceY : p.y) - shell.gy;
                    const d = Math.hypot(dx, dy);
                    shell.cursorNear = Math.hypot(p.x - shell.gx, p.y - shell.gy) < 220;
                    shell.lookX = d < 20 ? 0 : dx / (d + 60);
                    shell.lookY = d < 20 ? 0 : dy / (d + 60);
                } catch (e) {}
            }
        }
    }

    Timer {
        running: shell.shown && !shell.dragging
        repeat: true
        interval: 90
        onTriggered: if (!hypr.connected) hypr.connected = true
    }

    // Mirar el fondo alrededor: si es oscuro, Mochi se vuelve blanco (con margen para no parpadear)
    Process {
        id: bgProc

        stdout: SplitParser {
            onRead: line => {
                const lum = parseFloat(line);
                if (lum < 0.4)
                    shell.lightBody = true;
                else if (lum > 0.5)
                    shell.lightBody = false;
            }
        }
    }

    Timer {
        running: shell.shown && shell.phys !== "held"
        repeat: true
        triggeredOnStart: true
        interval: 2000
        onTriggered: shell.checkBg()
    }

    FrameAnimation {
        running: shell.shown && (shell.phys === "air" || shell.phys === "held")   // también volando por otro workspace
        onTriggered: shell.physStep(frameTime)
    }

    // Paseos: de vez en cuando da unos saltitos por el suelo
    Timer {
        running: shell.shown && shell.present && !shell.fsHide && shell.phys === "ground" && isNaN(shell.targetX) && !shell.asking && !shell.bubbleShown && !shell.voiceWaiting && !Brain.busy
        repeat: true
        interval: 9000
        onTriggered: {
            interval = 7000 + Math.random() * 12000;
            if (Math.random() < 0.6) {
                shell.hopsLeft = 1 + Math.floor(Math.random() * 3);
                shell.hopDir = Math.random() < 0.5 ? -1 : 1;
                shell.hop();
            }
        }
    }

    Timer {
        id: hopAgain

        interval: 160
        onTriggered: shell.hop()
    }

    Timer {
        id: travelAgain

        interval: 120
        onTriggered: shell.travelHop()
    }

    // Si no le haces caso, se esconde bajo el borde de la pantalla
    Timer {
        id: idleHide

        running: shell.shown && shell.present && shell.phys !== "hidden" && !shell.asking && !shell.bubbleShown && !shell.voiceWaiting && !Brain.busy
        interval: shell.hideAfter
        onTriggered: {
            if (shell.phys !== "ground") {
                restart();
                return;
            }
            const s = shell.nearestScreen(shell.gx, shell.gy);
            shell.hopsLeft = 0;
            shell.phys = "hidden";
            sinkAnim.to = s.y + s.height + shell.bodyRy - 52;   // solo asoman los ojos
            sinkAnim.restart();
        }
    }

    NumberAnimation {
        id: sinkAnim

        target: shell
        property: "gy"
        duration: 1600
        easing.type: Easing.InOutSine
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            required property ShellScreen modelData

            readonly property bool here: shell.screenAt(shell.gx, shell.gy) === modelData

            screen: modelData
            visible: shell.shown
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "mochi"
            WlrLayershell.keyboardFocus: shell.asking && here ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            // Solo Mochi y su bocadillo reciben clics; el resto del escritorio pasa de largo
            mask: Region {
                item: mochi.visible ? mochi : null

                Region {
                    item: bubble.visible ? bubble : null
                }
            }

            Blob {
                id: mochi

                // Solo en el workspace donde vive, y se aparta si hay algo a pantalla completa
                visible: shell.present && !shell.fsHide
                x: shell.gx - win.modelData.x - width / 2
                y: shell.gy - win.modelData.y - height / 2
                mood: shell.mood
                dragging: shell.dragging
                worldX: shell.gx
                worldY: shell.gy
                falling: shell.phys === "air" && shell.vy > 900
                hidden: shell.phys === "hidden"
                sleepy: shell.phys === "hidden" && !shell.cursorNear
                light: shell.lightBody
                talking: Brain.talking
                music: Mind.musicPlaying

                Connections {
                    target: shell

                    function onSplatted(strength: real, horizontal: bool): void {
                        mochi.splat(strength, horizontal);
                    }
                    function onReacted(name: string, ms: int): void {
                        mochi.react(name, ms);
                    }
                }
                lookX: shell.dragging ? 0 : shell.lookX
                lookY: shell.dragging ? 0 : shell.lookY

                MouseArea {
                    property real px
                    property real py
                    property bool moved
                    property string wasPhys
                    // Caricias: pasar el ratón de lado a lado por encima
                    property int petCount
                    property int petDir
                    property real petLastX
                    property real petStart

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    cursorShape: shell.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

                    // Pasar por encima lo despierta si estaba escondido
                    onContainsMouseChanged: if (containsMouse && shell.phys === "hidden") shell.touch()

                    // Clic derecho: historial · clic central: activar/silenciar el micro
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton)
                            Qt.openUrlExternally("file://" + Brain.historyDir);
                        else if (mouse.button === Qt.MiddleButton)
                            shell.earsOn = !shell.earsOn;
                    }

                    onPressed: mouse => {
                        if (mouse.button !== Qt.LeftButton)
                            return;
                        px = mouse.x;
                        py = mouse.y;
                        moved = false;
                        wasPhys = shell.phys;
                        shell.touch();
                        // Agarrado (también en el aire)
                        sinkAnim.stop();
                        hopAgain.stop();
                        shell.hopsLeft = 0;
                        shell.targetX = NaN;
                        shell.entering = false;
                        shell.flung = false;
                        shell.phys = "held";
                        shell.vx = shell.vy = shell.hvx = shell.hvy = 0;
                        shell.prevX = shell.gx;
                        shell.prevY = shell.gy;
                        shell.reversals = 0;
                        shell.lastDir = 0;
                    }
                    onPositionChanged: mouse => {
                        if (!(pressedButtons & Qt.LeftButton)) {
                            const now = Date.now();
                            if (now - petStart > 1800) {
                                petStart = now;
                                petCount = 0;
                            }
                            const dir = Math.sign(mouse.x - petLastX);
                            if (dir && dir !== petDir && Math.abs(mouse.x - petLastX) > 2) {
                                petCount++;
                                petDir = dir;
                            }
                            petLastX = mouse.x;
                            if (petCount >= 5) {
                                petCount = 0;
                                petStart = now;
                                shell.pet();
                            }
                            return;
                        }
                        if (!moved && Math.hypot(mouse.x - px, mouse.y - py) < 4)
                            return;
                        moved = true;
                        shell.dragging = true;
                        // Al moverse Mochi, el ratón vuelve a quedar en (px, py) relativo a él
                        shell.gx += mouse.x - px;
                        shell.gy += mouse.y - py;
                    }
                    onReleased: mouse => {
                        if (mouse.button !== Qt.LeftButton)
                            return;
                        if (moved) {
                            // Soltarlo: sale lanzado con la velocidad del ratón y cae
                            shell.dragging = false;
                            shell.vx = Math.max(-4500, Math.min(4500, shell.hvx));
                            shell.vy = Math.max(-2600, Math.min(2600, shell.hvy));
                            shell.phys = "air";
                            shell.thrown = true;
                            if (shell.reversals >= 4)
                                shell.reacted("dizzy", 2400);
                            return;
                        }
                        shell.phys = wasPhys === "ground" ? "ground" : "air";
                        if (shell.asking) {
                            mochi.poke();
                            shell.asking = false;
                        } else {
                            mochi.poke();
                            shell.openInput();
                        }
                    }
                }
            }

            // Micro silenciado
            Text {
                visible: !shell.earsOn && mochi.visible
                x: mochi.x + mochi.width - 18
                y: mochi.y + mochi.height - 20
                text: "mic_off"
                font.family: Theme.icons
                font.pixelSize: 16
                color: "white"
                style: Text.Outline
                styleColor: "black"
            }

            // Subtítulos: lo que escribes y lo que contesta flotan sobre Mochi, sin caja.
            // Texto con halo suave; claro u oscuro según el fondo (igual que el cuerpo).
            Item {
                id: bubble

                readonly property bool above: mochi.y - height - 14 > 8
                readonly property color ink: shell.lightBody ? "#fbfaf6" : "#141414"
                readonly property color halo: shell.lightBody ? "#000000" : "#ffffff"
                readonly property bool showing: win.here && mochi.visible && (shell.asking || shell.voiceWaiting || (shell.bubbleShown && (shell.remark !== "" || Brain.reply !== "" || Brain.busy)))
                readonly property string fullText: {
                    if (shell.asking)
                        return "";
                    if (shell.remark && !Brain.busy)
                        return shell.remark;
                    return Brain.reply;
                }
                // Estado mientras no hay respuesta todavía
                readonly property string status: {
                    if (shell.voiceWaiting && !Brain.busy)
                        return "te escucho…";
                    if (!Brain.busy || Brain.reply)
                        return "";
                    switch (Brain.mood) {
                    case "reading":
                        return "leyendo…";
                    case "searching":
                        return "buscando…";
                    case "focused":
                        return "editando…";
                    case "working":
                        return "trabajando…";
                    default:
                        return "pensando…";
                    }
                }
                // Lo que has dicho (por escrito o por voz), en pequeño encima de la respuesta
                readonly property string said: !shell.asking && !shell.remark && (Brain.busy || Brain.reply) ? Brain.lastPrompt : ""
                property int revealed: 0     // la respuesta aparece palabra a palabra

                visible: opacity > 0.01
                opacity: showing ? 1 : 0
                width: Math.max(shell.asking ? 320 : 0, Math.min(460, Math.max(reply.implicitWidth, saidText.implicitWidth, statusText.implicitWidth) + 8))
                height: content.implicitHeight
                x: Math.max(12, Math.min(win.width - width - 12, mochi.x + mochi.width / 2 - width / 2))
                y: above ? mochi.y - height - 14 : mochi.y + mochi.height + 12

                onFullTextChanged: {
                    // Respuesta nueva (no la continuación de la anterior): empezar desde el principio
                    if (!fullText || revealed > fullText.length)
                        revealed = 0;
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: 260
                        easing.type: Easing.OutCubic
                    }
                }

                Timer {
                    running: bubble.revealed < bubble.fullText.length
                    repeat: true
                    interval: 38
                    onTriggered: {
                        const i = bubble.fullText.indexOf(" ", bubble.revealed + 1);
                        bubble.revealed = i < 0 ? bubble.fullText.length : i;
                    }
                }

                // Penumbra difuminada detrás del texto (sin bordes) para que se lea sobre cualquier fondo
                Rectangle {
                    id: scrim

                    anchors.fill: content
                    anchors.margins: -16
                    radius: 28
                    color: bubble.halo
                    visible: false
                    layer.enabled: true
                }

                MultiEffect {
                    anchors.fill: scrim
                    source: scrim
                    blurEnabled: true
                    blur: 1
                    blurMax: 48
                    opacity: 0.5
                }

                Column {
                    id: content

                    width: parent.width
                    spacing: 6

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: bubble.halo
                        shadowOpacity: 1
                        shadowBlur: 0.8
                        shadowVerticalOffset: 0
                        blurMax: 16
                    }

                    Text {
                        id: saidText

                        visible: text !== ""
                        width: parent.width
                        text: bubble.said ? `«${bubble.said}»` : ""
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 13
                        font.italic: true
                        color: bubble.ink
                        opacity: 0.6
                    }

                    Text {
                        id: statusText

                        visible: text !== ""
                        width: parent.width
                        text: bubble.status
                        horizontalAlignment: Text.AlignHCenter
                        font.family: Theme.font
                        font.pixelSize: 13
                        font.letterSpacing: 0.5
                        color: bubble.ink

                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            running: statusText.visible

                            NumberAnimation {
                                to: 0.35
                                duration: 700
                                easing.type: Easing.InOutSine
                            }
                            NumberAnimation {
                                to: 0.85
                                duration: 700
                                easing.type: Easing.InOutSine
                            }
                        }
                    }

                    Flickable {
                        visible: reply.text !== ""
                        width: parent.width
                        height: Math.min(reply.implicitHeight, 280)
                        contentHeight: reply.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        onContentHeightChanged: if (Brain.busy || bubble.revealed < bubble.fullText.length) contentY = Math.max(0, contentHeight - height)

                        Text {
                            id: reply

                            width: parent.width
                            text: bubble.fullText.slice(0, bubble.revealed)
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            textFormat: Text.MarkdownText
                            lineHeight: 1.08
                            font.family: Theme.font
                            font.pixelSize: 16
                            font.weight: Font.Medium
                            color: bubble.ink
                            linkColor: bubble.ink
                            onLinkActivated: link => Qt.openUrlExternally(link)
                        }
                    }

                    // Lo que escribes, suelto y centrado
                    Item {
                        visible: shell.asking
                        width: parent.width
                        height: input.implicitHeight

                        TextInput {
                            id: input

                            anchors.fill: parent
                            horizontalAlignment: TextInput.AlignHCenter
                            color: bubble.ink
                            font.family: Theme.font
                            font.pixelSize: 18
                            font.weight: Font.Medium
                            selectionColor: bubble.ink
                            selectedTextColor: bubble.halo
                            selectByMouse: true
                            clip: true

                            cursorDelegate: Rectangle {
                                width: 2
                                color: bubble.ink
                                visible: input.text !== ""   // vacío: el cursor va delante del texto de ayuda

                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite
                                    running: input.activeFocus

                                    NumberAnimation {
                                        to: 0
                                        duration: 450
                                        easing.type: Easing.InOutSine
                                    }
                                    NumberAnimation {
                                        to: 1
                                        duration: 450
                                        easing.type: Easing.InOutSine
                                    }
                                }
                            }

                            onVisibleChanged: {
                                if (visible) {
                                    text = "";
                                    forceActiveFocus();
                                }
                            }
                            Keys.onEscapePressed: shell.asking = false
                            onAccepted: {
                                if (!text.trim())
                                    return;
                                Brain.send(text);
                                shell.asking = false;
                            }
                        }

                        Row {
                            anchors.centerIn: parent
                            visible: !input.text
                            spacing: 3

                            Rectangle {
                                width: 2
                                height: hint.implicitHeight
                                color: bubble.ink

                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite
                                    running: shell.asking

                                    NumberAnimation {
                                        to: 0
                                        duration: 450
                                        easing.type: Easing.InOutSine
                                    }
                                    NumberAnimation {
                                        to: 1
                                        duration: 450
                                        easing.type: Easing.InOutSine
                                    }
                                }
                            }

                            Text {
                                id: hint

                                text: "Escríbele a Mochi…"
                                font: input.font
                                color: bubble.ink
                                opacity: 0.55
                            }
                        }
                    }
                }

                // Clic en la respuesta: cerrarla · encima: no se va mientras la lees
                MouseArea {
                    anchors.fill: parent
                    enabled: !shell.asking
                    hoverEnabled: true
                    onClicked: shell.bubbleShown = false
                    onContainsMouseChanged: {
                        if (containsMouse)
                            hideTimer.stop();
                        else if (!Brain.busy && shell.bubbleShown)
                            hideTimer.restart();
                    }
                }
            }
        }
    }
}
