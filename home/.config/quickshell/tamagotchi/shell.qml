//@ pragma Env QT_LOGGING_RULES=quickshell.io.socket.warning=false

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Mochi: burbujita negra que vive en el escritorio, con Claude Code como cerebro.
// - Arrástralo a cualquier sitio (también a otra pantalla).
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

    readonly property string mood: asking && !Brain.busy ? "listening" : Brain.mood

    function screenAt(x: real, y: real): var {
        for (const s of Quickshell.screens)
            if (x >= s.x && x < s.x + s.width && y >= s.y && y < s.y + s.height)
                return s;
        return null;
    }

    // Que no se quede fuera de ninguna pantalla
    function settle(): void {
        let s = screenAt(gx, gy);
        if (!s) {
            // La pantalla más cercana
            let best = Infinity;
            for (const c of Quickshell.screens) {
                const dx = Math.max(c.x - gx, 0, gx - (c.x + c.width));
                const dy = Math.max(c.y - gy, 0, gy - (c.y + c.height));
                if (dx + dy < best) {
                    best = dx + dy;
                    s = c;
                }
            }
        }
        if (!s)
            return;
        gx = Math.max(s.x + 40, Math.min(s.x + s.width - 40, gx));
        gy = Math.max(s.y + 40, Math.min(s.y + s.height - 40, gy));
    }

    function savePos(): void {
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && printf "%s %s" "$2" "$3" > "$1/pos"', "sh", stateDir, Math.round(gx), Math.round(gy)]);
    }

    function openInput(): void {
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

    IpcHandler {
        target: "pet"

        // Doble +: aparece y escucha; si ya escuchaba, se esconde
        function toggle(): void {
            if (shell.shown && shell.asking) {
                shell.asking = false;
                shell.shown = false;
            } else {
                shell.openInput();
            }
        }
        function appear(): void {
            shell.shown = true;
        }
        function hide(): void {
            shell.asking = false;
            shell.shown = false;
        }
        function talk(): void {
            shell.openInput();
        }
        function ask(text: string): void {
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
                lookX: shell.dragging ? 0 : shell.lookX
                lookY: shell.dragging ? 0 : shell.lookY

                MouseArea {
                    property real px
                    property real py
                    property bool moved

                    anchors.fill: parent
                    cursorShape: shell.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

                    onPressed: mouse => {
                        px = mouse.x;
                        py = mouse.y;
                        moved = false;
                    }
                    onPositionChanged: mouse => {
                        if (!pressed)
                            return;
                        if (!moved && Math.hypot(mouse.x - px, mouse.y - py) < 4)
                            return;
                        moved = true;
                        shell.dragging = true;
                        // Al moverse Mochi, el ratón vuelve a quedar en (px, py) relativo a él
                        shell.gx += mouse.x - px;
                        shell.gy += mouse.y - py;
                    }
                    onReleased: {
                        if (moved) {
                            shell.dragging = false;
                            shell.settle();
                            shell.savePos();
                        } else if (shell.asking) {
                            shell.asking = false;
                        } else {
                            shell.openInput();
                        }
                    }
                }
            }

            // Bocadillo: respuesta y/o campo para escribir
            Rectangle {
                id: bubble

                readonly property bool above: mochi.y - height - 22 > 8

                visible: win.here && (shell.asking || (shell.bubbleShown && (Brain.reply !== "" || Brain.busy)))
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
                            text: shell.asking ? "" : Brain.busy && !Brain.reply ? (Brain.mood === "working" && Brain.toolName ? `(${Brain.toolName.toLowerCase()}…)` : "…") : Brain.reply
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
