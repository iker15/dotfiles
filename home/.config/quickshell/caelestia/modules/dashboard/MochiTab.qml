pragma ComponentBehavior: Bound

import "mochi/Draw.js" as Draw
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// Pestaña de Mochi (~/.config/quickshell/tamagotchi) en el dashboard: su ficha. Cómo está y por
// qué, el cariño que te tiene, su gorro, las últimas conversaciones y botones rápidos. Lee lo
// que él publica en $XDG_RUNTIME_DIR/mochi-state.json y habla con él por IPC.
Item {
    id: root

    property var st: ({})
    property var chat: []

    readonly property int bond: st.bond ?? 0
    readonly property bool sulky: st.sulky ?? false
    readonly property var hatNames: ({
            witch: "sombrero de bruja",
            santa: "gorro de Papá Noel",
            party: "gorrito de fiesta",
            crown: "corona de Reyes"
        })

    function ipc(...args): void {
        Quickshell.execDetached(["qs", "-c", "tamagotchi", "ipc", "call", "pet", ...args]);
    }

    implicitWidth: 840
    implicitHeight: layout.implicitHeight

    FileView {
        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/mochi-state.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.st = JSON.parse(text());
            } catch (e) {}
        }
    }

    // Últimas conversaciones de hoy (~/Documentos/Mochi/AAAA-MM-DD.md)
    FileView {
        path: `${Quickshell.env("HOME")}/Documentos/Mochi/${Qt.formatDate(new Date(), "yyyy-MM-dd")}.md`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const out = [];
            const re = /\*\*(Tú[^*]*|Mochi[^*]*)\*\* · (\d\d:\d\d)\n\n([\s\S]*?)(?=\n\n\*\*|$)/g;
            let m;
            while ((m = re.exec(text())) !== null)
                out.push({
                    who: m[1].startsWith("Tú") ? "Tú" : "Mochi",
                    time: m[2],
                    text: m[3].trim().replace(/\s+/g, " ")
                });
            root.chat = out.slice(-4);
        }
    }

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Tokens.spacing.medium

        // Cabecera: nombre y cómo está
        RowLayout {
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: Tokens.padding.large
            Layout.fillWidth: true

            Column {
                spacing: Tokens.spacing.extraSmall

                StyledText {
                    text: "Mochi"
                    font: Tokens.font.body.builders.large.size(28).weight(Font.DemiBold).build()
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    text: root.st.text ? root.st.text.charAt(0).toUpperCase() + root.st.text.slice(1) : "…"
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }

            Item {
                Layout.fillWidth: true
            }

            Row {
                spacing: Tokens.spacing.largeIncreased

                Stat {
                    icon: root.sulky ? "heart_broken" : "favorite"
                    label: "Cariño"
                    value: `${root.bond} / 100`
                    colour: root.sulky ? Colours.palette.m3outline : Colours.palette.m3error
                }

                Stat {
                    icon: "military_tech"
                    label: root.st.stageName ?? "Nivel"
                    value: `Nivel ${root.st.level ?? 1} · ${(root.st.xp ?? 0) - (root.st.levelStart ?? 0)}/${(root.st.levelEnd ?? 60) - (root.st.levelStart ?? 0)} XP`
                    colour: Colours.palette.m3primary
                }

                Stat {
                    icon: "checkroom"
                    label: "Gorro"
                    value: root.st.hat ? root.hatNames[root.st.hat] ?? root.st.hat : "ninguno"
                    colour: Colours.palette.m3tertiary
                }
            }
        }

        // Retrato grande + cariño
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: 230

            radius: Tokens.rounding.extraLarge * 2
            color: Colours.tPalette.m3surfaceContainer

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.extraLarge
                anchors.rightMargin: Tokens.padding.extraLarge * 2
                spacing: Tokens.spacing.largeIncreased

                // Mochi, vivo: respira, parpadea y mira alrededor
                Canvas {
                    id: portrait

                    property real t: 0
                    property real blink: 0
                    property real lx: 0
                    property real ly: 0
                    property real tlx: 0
                    property real tly: 0

                    Layout.preferredWidth: 230
                    Layout.fillHeight: true

                    onTChanged: requestPaint()

                    FrameAnimation {
                        running: portrait.visible
                        onTriggered: {
                            portrait.t += frameTime;
                            portrait.lx += (portrait.tlx - portrait.lx) * Math.min(1, frameTime * 6);
                            portrait.ly += (portrait.tly - portrait.ly) * Math.min(1, frameTime * 6);
                        }
                    }
                    Timer {
                        running: portrait.visible
                        repeat: true
                        interval: 3500
                        onTriggered: {
                            interval = 2500 + Math.random() * 3500;
                            blinkAnim.restart();
                            if (Math.random() < 0.5) {
                                portrait.tlx = Math.random() * 1.6 - 0.8;
                                portrait.tly = Math.random() * 0.8 - 0.4;
                            }
                        }
                    }
                    SequentialAnimation {
                        id: blinkAnim

                        NumberAnimation {
                            target: portrait
                            property: "blink"
                            to: 1
                            duration: 70
                        }
                        NumberAnimation {
                            target: portrait
                            property: "blink"
                            to: 0
                            duration: 130
                        }
                    }

                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const f = root.st.feeling ?? "normal";
                        Draw.avatar(ctx, {
                            x: width / 2,
                            y: height - 22,
                            s: 70,
                            body: root.st.body ?? "#d0d3d6",
                            ink: root.st.ink ?? "#1c1b1b",
                            face: f,
                            hat: root.st.hat ?? "",
                            melt: root.st.melt ?? 0,
                            snow: root.st.snow ?? 0,
                            stage: root.st.stage ?? 1,
                            blink: f === "asleep" ? 0 : blink,
                            lx: lx,
                            ly: ly,
                            breath: 0.5 + 0.5 * Math.sin(t * (f === "asleep" ? 1.6 : 2.6)),
                            t: t
                        });
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Tokens.spacing.small

                    StyledText {
                        text: root.sulky ? "Está enfurruñado: lleva días sin que le hagas caso" : root.bond >= 75 ? "Te adora" : root.bond >= 50 ? "Te tiene mucho cariño" : root.bond >= 30 ? "Te va cogiendo cariño" : "Aún os estáis conociendo"
                        font: Tokens.font.body.builders.large.weight(Font.DemiBold).build()
                        color: Colours.palette.m3primary
                    }

                    StyledProgressBar {
                        Layout.fillWidth: true
                        implicitHeight: Tokens.padding.small
                        value: root.bond / 100
                        fgColour: root.sulky ? Colours.palette.m3outline : Colours.palette.m3error
                    }

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: root.sulky ? "Háblale o acarícialo: la primera vez te girará la cara, pero si insistes te perdona." : "Sube hablándole, acariciándolo (pasa el ratón de lado a lado por encima) o cogiéndolo; y un poco solo con estar con él."
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    StyledText {
                        visible: !!root.st.nextHat
                        text: {
                            const [h, d] = (root.st.nextHat ?? "|").split("|");
                            return `Próximo gorro: ${root.hatNames[h] ?? h}, el ${new Date(d + "T12:00").toLocaleDateString(Qt.locale(), "d 'de' MMMM")}`;
                        }
                        font: Tokens.font.body.small
                        color: Colours.palette.m3tertiary
                    }
                }
            }
        }

        // Por qué está así
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            DetailCard {
                icon: "device_thermostat"
                label: "Calor del PC"
                value: root.st.cpu ? `${root.st.cpu} °C${(root.st.melt ?? 0) > 0.05 ? " · derritiéndose" : ""}` : "--"
                colour: (root.st.melt ?? 0) > 0.05 ? Colours.palette.m3error : Colours.palette.m3primary
            }
            DetailCard {
                icon: root.st.raining ? "umbrella" : "cloud"
                label: "Fuera"
                value: root.st.outside !== null && root.st.outside !== undefined ? `${root.st.outside} °C${root.st.raining ? " · llueve" : (root.st.snow ?? 0) > 0 ? " · nieva" : ""}` : "--"
                colour: Colours.palette.m3secondary
            }
            DetailCard {
                icon: root.st.caffeine ? "coffee" : "bolt"
                label: "Energía"
                value: root.st.caffeine ? "con café" : (root.st.energy ?? 1) >= 1.1 ? "con ganas" : (root.st.energy ?? 1) >= 0.85 ? "normal" : (root.st.energy ?? 1) >= 0.7 ? "tranquilo" : "con sueño"
                colour: Colours.palette.m3tertiary
            }
            DetailCard {
                icon: root.st.watching ? "smart_display" : root.st.music ? "music_note" : "home"
                label: "Ahora"
                value: root.st.watching ? "viendo un vídeo" : root.st.music ? "escuchando música" : root.st.where === "nest" ? "en su nido" : root.st.where === "dive" ? "buceando" : "paseando"
                colour: Colours.palette.m3primary
            }
        }

        // Últimas conversaciones
        StyledText {
            Layout.topMargin: Tokens.spacing.small
            Layout.leftMargin: Tokens.padding.medium
            text: root.chat.length ? "Hoy habéis hablado de…" : "Hoy aún no habéis hablado"
            font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
            color: Colours.palette.m3onSurface
        }

        Repeater {
            model: root.chat

            StyledRect {
                id: msg

                required property var modelData

                Layout.fillWidth: true
                implicitHeight: msgRow.implicitHeight + Tokens.padding.small * 2
                radius: Tokens.rounding.medium
                color: msg.modelData.who === "Tú" ? Colours.tPalette.m3surfaceContainerHigh : Colours.tPalette.m3surfaceContainer

                RowLayout {
                    id: msgRow

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Tokens.padding.medium
                    anchors.rightMargin: Tokens.padding.medium
                    spacing: Tokens.spacing.medium

                    StyledText {
                        Layout.preferredWidth: 60
                        text: msg.modelData.who
                        font: Tokens.font.body.builders.small.weight(Font.DemiBold).build()
                        color: msg.modelData.who === "Tú" ? Colours.palette.m3secondary : Colours.palette.m3primary
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: msg.modelData.text
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurface
                    }
                    StyledText {
                        text: msg.modelData.time
                        font: Tokens.font.body.small
                        opacity: 0.6
                    }
                }
            }
        }

        // Botones rápidos
        RowLayout {
            Layout.topMargin: Tokens.spacing.small
            Layout.alignment: Qt.AlignHCenter
            spacing: Tokens.spacing.small

            IconTextButton {
                icon: "waving_hand"
                text: "Llamarlo"
                isRound: true
                type: IconTextButton.Tonal
                onClicked: root.ipc("appear")
            }
            IconTextButton {
                icon: "chat"
                text: "Hablarle"
                isRound: true
                type: IconTextButton.Tonal
                onClicked: root.ipc("talk")
            }
            IconTextButton {
                icon: "coffee"
                text: IdleInhibitor.enabled ? "Quitar café" : "Café"
                isRound: true
                type: IconTextButton.Tonal
                onClicked: IdleInhibitor.enabled = !IdleInhibitor.enabled
            }
            IconTextButton {
                icon: "nest_eco_leaf"
                text: "Al nido"
                isRound: true
                type: IconTextButton.Tonal
                onClicked: root.ipc("nest")
            }
            IconTextButton {
                icon: "bedtime"
                text: "A dormir"
                isRound: true
                type: IconTextButton.Tonal
                onClicked: root.ipc("sleep", "doze")
            }
        }
    }

    component Stat: Row {
        id: stat

        property string icon
        property string label
        property string value
        property color colour

        spacing: Tokens.spacing.small

        MaterialIcon {
            text: stat.icon
            fontStyle: Tokens.font.icon.extraLarge
            color: stat.colour
            fill: 1
        }

        Column {
            StyledText {
                text: stat.label
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
            }
            StyledText {
                text: stat.value
                font: Tokens.font.body.builders.small.weight(Font.DemiBold).build()
                color: Colours.palette.m3onSurface
            }
        }
    }

    component DetailCard: StyledRect {
        id: detailRoot

        property string icon
        property string label
        property string value
        property color colour

        Layout.fillWidth: true
        Layout.preferredHeight: 60
        radius: Tokens.rounding.medium
        color: Colours.tPalette.m3surfaceContainer

        Row {
            anchors.centerIn: parent
            spacing: Tokens.spacing.medium

            MaterialIcon {
                text: detailRoot.icon
                color: detailRoot.colour
                fontStyle: Tokens.font.icon.large
                anchors.verticalCenter: parent.verticalCenter
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                StyledText {
                    text: detailRoot.label
                    font: Tokens.font.body.small
                    opacity: 0.7
                }
                StyledText {
                    text: detailRoot.value
                    font: Tokens.font.body.builders.small.weight(Font.DemiBold).build()
                }
            }
        }
    }
}
