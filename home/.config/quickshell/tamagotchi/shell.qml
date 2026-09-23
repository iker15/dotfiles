import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Mochi: burbujita negra que vive en el escritorio, con Claude Code como cerebro.
// - Tiene gravedad: vive en el suelo de la pantalla, da saltitos y se le puede lanzar.
// - Si no le haces caso en un rato se esconde por debajo del borde (asoma los ojos).
// - Clic (o doble +) para hablarle; la respuesta sale en un bocadillo.
// IPC: qs -c tamagotchi ipc call pet toggle|appear|hide|talk|ask "<texto>"
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

    // Cualquier uso: reinicia la cuenta para esconderse y, si estaba escondido, sale
    function touch(): void {
        idleHide.restart();
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
        savePos();
        checkBg();
        if (hopsLeft > 0)
            hopAgain.restart();
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

        // Paredes (salvo que al otro lado haya otra pantalla)
        if (nx < left && !screenAt(nx - bodyRx, ny)) {
            nx = left;
            if (vx < -300)
                splatted(-vx, true);
            vx = Math.abs(vx) * 0.45;
        } else if (nx > right && !screenAt(nx + bodyRx, ny)) {
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
            if (Brain.busy) {
                shell.bubbleShown = true;
                hideTimer.stop();
            } else {
                shell.showReply();
            }
        }
    }

    // El bocadillo se va solo al rato (más tiempo cuanto más largo)
    Timer {
        id: hideTimer

        interval: Math.min(30000, 6000 + Brain.reply.length * 45)
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
        function state(): string {
            return `${shell.phys} ${Math.round(shell.gx)},${Math.round(shell.gy)} v=${Math.round(shell.vx)},${Math.round(shell.vy)} shown=${shell.shown}`;
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
                    const dx = p.x - shell.gx, dy = p.y - shell.gy;
                    const d = Math.hypot(dx, dy);
                    shell.cursorNear = d < 220;
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
        running: shell.shown && (shell.phys === "air" || shell.phys === "held")
        onTriggered: shell.physStep(frameTime)
    }

    // Paseos: de vez en cuando da unos saltitos por el suelo
    Timer {
        running: shell.shown && shell.phys === "ground" && !shell.asking && !shell.bubbleShown && !shell.voiceWaiting && !Brain.busy
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

    // Si no le haces caso, se esconde bajo el borde de la pantalla
    Timer {
        id: idleHide

        running: shell.shown && shell.phys !== "hidden" && !shell.asking && !shell.bubbleShown && !shell.voiceWaiting && !Brain.busy
        interval: shell.hideAfter
        onTriggered: {
            if (shell.phys !== "ground") {
                restart();
                return;
            }
            const s = shell.nearestScreen(shell.gx, shell.gy);
            shell.hopsLeft = 0;
            shell.phys = "hidden";
            sinkAnim.to = s.y + s.height + shell.bodyRy - 46;   // solo asoman los ojos
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
                item: mochi

                Region {
                    item: bubble.visible ? bubble : null
                }
            }

            Blob {
                id: mochi

                x: shell.gx - win.modelData.x - width / 2
                y: shell.gy - win.modelData.y - height / 2
                mood: shell.mood
                dragging: shell.dragging
                worldX: shell.gx
                worldY: shell.gy
                falling: shell.phys === "air" && shell.vy > 900
                sleepy: shell.phys === "hidden" && !shell.cursorNear
                light: shell.lightBody

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
                        shell.phys = "held";
                        shell.vx = shell.vy = shell.hvx = shell.hvy = 0;
                        shell.prevX = shell.gx;
                        shell.prevY = shell.gy;
                        shell.reversals = 0;
                        shell.lastDir = 0;
                    }
                    onPositionChanged: mouse => {
                        if (!(pressedButtons & Qt.LeftButton))
                            return;
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
                            shell.vx = Math.max(-2600, Math.min(2600, shell.hvx));
                            shell.vy = Math.max(-2600, Math.min(2600, shell.hvy));
                            shell.phys = "air";
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
                visible: !shell.earsOn
                x: mochi.x + mochi.width - 18
                y: mochi.y + mochi.height - 20
                text: "mic_off"
                font.family: Theme.icons
                font.pixelSize: 16
                color: "white"
                style: Text.Outline
                styleColor: "black"
            }

            // Bocadillo: respuesta y/o campo para escribir
            Rectangle {
                id: bubble

                readonly property bool above: mochi.y - height - 22 > 8

                visible: win.here && (shell.asking || shell.voiceWaiting || (shell.bubbleShown && (Brain.reply !== "" || Brain.busy)))
                width: Math.max(input.visible ? 280 : 0, Math.min(320, reply.implicitWidth + 28))
                height: content.height + 20
                x: Math.max(8, Math.min(win.width - width - 8, mochi.x + mochi.width / 2 - width / 2))
                y: above ? mochi.y - height - 22 : mochi.y + mochi.height + 14
                radius: 18
                color: "#f4f4f2"

                // Piquito hacia Mochi
                Rectangle {
                    width: 14
                    height: 14
                    rotation: 45
                    color: parent.color
                    x: Math.max(14, Math.min(bubble.width - 28, mochi.x + mochi.width / 2 - bubble.x - 7))
                    y: bubble.above ? bubble.height - 8 : -6
                    z: -1
                }

                Column {
                    id: content

                    x: 14
                    y: 10
                    width: bubble.width - 28
                    spacing: 8

                    Flickable {
                        visible: reply.text !== ""
                        width: parent.width
                        height: Math.min(reply.implicitHeight, 240)
                        contentHeight: reply.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        onContentHeightChanged: if (Brain.busy) contentY = Math.max(0, contentHeight - height)

                        Text {
                            id: reply

                            width: Math.min(implicitWidth, 292)
                            text: {
                                if (shell.asking)
                                    return "";
                                if (shell.voiceWaiting && !Brain.busy)
                                    return "Te escucho… 👂";
                                if (Brain.busy && !Brain.reply) {
                                    const doing = Brain.mood === "working" && Brain.toolName ? `(${Brain.toolName.toLowerCase()}…)` : "…";
                                    // Si fue por voz, enseñar lo que ha entendido
                                    return shell.heard && Brain.lastPrompt === shell.heard ? `_«${shell.heard}»_\n\n${doing}` : doing;
                                }
                                return Brain.reply;
                            }
                            wrapMode: Text.Wrap
                            textFormat: Text.MarkdownText
                            font.family: Theme.font
                            font.pixelSize: 14
                            color: "#111111"
                            onLinkActivated: link => Qt.openUrlExternally(link)
                        }
                    }

                    TextField {
                        id: input

                        visible: shell.asking
                        width: parent.width
                        background: null
                        padding: 0
                        placeholderText: "Dime algo…"
                        placeholderTextColor: "#8a8a86"
                        color: "#111111"
                        font.family: Theme.font
                        font.pixelSize: 14
                        selectionColor: "#111111"
                        selectedTextColor: "white"

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
                }

                // Clic en la respuesta: cerrarla
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
