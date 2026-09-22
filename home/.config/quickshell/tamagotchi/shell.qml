//@ pragma UseQApplication

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Mochi: mascota flotante con Claude Code como cerebro.
// Se muestra/oculta con `qs -c tamagotchi ipc call pet toggle` (doble + en Hyprland).
ShellRoot {
    id: shell

    property bool shown: false

    IpcHandler {
        target: "pet"

        function toggle(): void {
            shell.shown = !shell.shown;
        }
        function show(): void {
            shell.shown = true;
        }
        function hide(): void {
            shell.shown = false;
        }
        function ask(text: string): void {
            shell.shown = true;
            Brain.send(text);
        }
    }

    PanelWindow {
        id: win

        visible: shell.shown
        anchors.bottom: true
        anchors.right: true
        margins.bottom: 20
        margins.right: 20
        implicitWidth: 420
        implicitHeight: 620
        exclusiveZone: 0
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "tamagotchi"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        onVisibleChanged: {
            if (visible) {
                card.scale = 0.85;
                card.opacity = 0;
                appear.restart();
                input.forceActiveFocus();
            }
        }

        ParallelAnimation {
            id: appear

            NumberAnimation {
                target: card
                property: "scale"
                to: 1
                duration: 260
                easing.type: Easing.OutBack
            }
            NumberAnimation {
                target: card
                property: "opacity"
                to: 1
                duration: 180
            }
        }

        Rectangle {
            id: card

            anchors.fill: parent
            transformOrigin: Item.BottomRight
            radius: 28
            color: Qt.alpha(Theme.surface, 0.92)
            border.width: 1
            border.color: Qt.alpha(Theme.outlineVariant, 0.6)

            Keys.onEscapePressed: shell.shown = false

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // Cabecera: Mochi, estado y botones
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Blob {
                        mood: Brain.mood
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: "Mochi"
                            font.family: Theme.font
                            font.pixelSize: 20
                            font.bold: true
                            color: Theme.primary
                        }

                        Text {
                            Layout.fillWidth: true
                            text: Brain.status
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: 13
                            color: Theme.onSurfaceVariant
                        }
                    }

                    IconButton {
                        icon: "add_comment"
                        tip: "Conversación nueva"
                        onClicked: Brain.reset()
                    }

                    IconButton {
                        icon: "close"
                        tip: "Ocultar (Esc)"
                        onClicked: shell.shown = false
                    }
                }

                // Chat
                ListView {
                    id: chat

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 8
                    model: Brain.messages
                    boundsBehavior: Flickable.StopAtBounds

                    onCountChanged: Qt.callLater(positionViewAtEnd)
                    onContentHeightChanged: if (Brain.busy) Qt.callLater(positionViewAtEnd)

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                    }

                    Text {
                        visible: chat.count === 0
                        anchors.centerIn: parent
                        width: parent.width * 0.8
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: "Pídeme lo que quieras: cambiar tu config, mirar algo del sistema, instalar cosas…\n\nEnter envía · Esc oculta · /nuevo empieza de cero"
                        font.family: Theme.font
                        font.pixelSize: 13
                        color: Theme.onSurfaceVariant
                    }

                    delegate: Item {
                        id: msg

                        required property string role
                        required property string text

                        readonly property bool mine: role === "user"
                        readonly property bool small: role === "tool" || role === "info"

                        width: chat.width - 8
                        height: small ? note.implicitHeight : bubble.height

                        Rectangle {
                            id: bubble

                            visible: !msg.small
                            anchors.right: msg.mine ? parent.right : undefined
                            width: msg.mine ? Math.min(label.contentWidth, label.width) + 24 : parent.width
                            height: (msg.mine ? label.contentHeight : parts.height) + 18
                            radius: 16
                            color: msg.mine ? Theme.primaryContainer : Theme.surfaceContainerHigh

                            // Mensajes míos: texto plano
                            TextEdit {
                                id: label

                                visible: msg.mine
                                x: 12
                                y: 9
                                width: chat.width * 0.82 - 24
                                readOnly: true
                                selectByMouse: true
                                wrapMode: TextEdit.Wrap
                                text: msg.text
                                font.family: Theme.font
                                font.pixelSize: 14
                                color: Theme.onPrimaryContainer
                                selectionColor: Theme.primary
                                selectedTextColor: Theme.onPrimary
                            }

                            // Mensajes de Mochi: markdown, con los bloques de código aparte
                            // para que se partan en líneas en vez de salirse de la burbuja
                            Column {
                                id: parts

                                visible: !msg.mine
                                x: 12
                                y: 9
                                width: bubble.width - 24
                                spacing: 6

                                Repeater {
                                    model: msg.mine ? [] : shell.splitCode(msg.text || "…")

                                    Rectangle {
                                        id: part

                                        required property var modelData

                                        width: parts.width
                                        height: partText.contentHeight + (modelData.code ? 14 : 0)
                                        radius: 10
                                        color: modelData.code ? Theme.surfaceContainerHighest : "transparent"

                                        TextEdit {
                                            id: partText

                                            x: part.modelData.code ? 8 : 0
                                            y: part.modelData.code ? 7 : 0
                                            width: parent.width - x * 2
                                            readOnly: true
                                            selectByMouse: true
                                            wrapMode: part.modelData.code ? TextEdit.WrapAnywhere : TextEdit.Wrap
                                            textFormat: part.modelData.code ? TextEdit.PlainText : TextEdit.MarkdownText
                                            text: part.modelData.text
                                            font.family: part.modelData.code ? Theme.mono : Theme.font
                                            font.pixelSize: part.modelData.code ? 12 : 14
                                            color: Theme.onSurface
                                            selectionColor: Theme.primary
                                            selectedTextColor: Theme.onPrimary
                                            onLinkActivated: link => Qt.openUrlExternally(link)
                                        }
                                    }
                                }
                            }
                        }

                        // Herramientas y avisos: una línea pequeña
                        Text {
                            id: note

                            visible: msg.small
                            width: parent.width
                            leftPadding: 4
                            text: msg.role === "tool" ? "⚙ " + msg.text.replace(/\s+/g, " ") : msg.text
                            elide: Text.ElideRight
                            maximumLineCount: msg.role === "tool" ? 1 : 4
                            wrapMode: Text.Wrap
                            font.family: msg.role === "tool" ? Theme.mono : Theme.font
                            font.pixelSize: 11
                            font.italic: msg.role === "info"
                            color: Theme.onSurfaceVariant
                        }
                    }
                }

                // Entrada
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 48
                    radius: 24
                    color: Theme.surfaceContainerHigh

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 6
                        spacing: 6

                        TextField {
                            id: input

                            Layout.fillWidth: true
                            background: null
                            placeholderText: Brain.busy ? "Mochi está en ello…" : "Háblame…"
                            placeholderTextColor: Theme.onSurfaceVariant
                            color: Theme.onSurface
                            font.family: Theme.font
                            font.pixelSize: 14
                            selectionColor: Theme.primary

                            Keys.onEscapePressed: shell.shown = false
                            onAccepted: {
                                if (Brain.busy || !text.trim())
                                    return;
                                Brain.send(text);
                                text = "";
                            }
                        }

                        IconButton {
                            icon: Brain.busy ? "stop" : "arrow_upward"
                            filled: true
                            tip: Brain.busy ? "Parar" : "Enviar"
                            onClicked: {
                                if (Brain.busy) {
                                    Brain.stop();
                                } else {
                                    input.accepted();
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Parte un mensaje en trozos de texto y bloques ```código``` (también si el bloque está a medio escribir)
    function splitCode(text: string): var {
        const out = [];
        const chunks = text.split(/^```[^\n]*\n?/m);
        for (let i = 0; i < chunks.length; i++) {
            const t = i % 2 ? chunks[i].replace(/\n$/, "") : chunks[i].trim();
            if (t)
                out.push({ code: i % 2 === 1, text: t });
        }
        return out.length ? out : [{ code: false, text: "…" }];
    }

    component IconButton: Rectangle {
        id: btn

        property string icon
        property string tip
        property bool filled: false
        signal clicked

        implicitWidth: 36
        implicitHeight: 36
        radius: 18
        color: filled ? Theme.primary : area.containsMouse ? Theme.surfaceContainerHighest : "transparent"

        Text {
            anchors.centerIn: parent
            text: btn.icon
            font.family: Theme.icons
            font.pixelSize: 20
            color: btn.filled ? Theme.onPrimary : Theme.onSurfaceVariant
        }

        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }

        ToolTip.visible: area.containsMouse && tip
        ToolTip.text: tip
        ToolTip.delay: 600
    }
}
