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
// qué, el cariño que te tiene, su nivel, su gorro y botones rápidos. (Ya no es un chat.) Lee lo
// que él publica en $XDG_RUNTIME_DIR/mochi-state.json y habla con él por IPC.
Item {
    id: root

    property var st: ({})

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

    // «Pegar código»: lee el portapapeles y se une como vecino
    Process {
        id: pasteCode

        command: ["wl-paste", "--no-newline"]
        stdout: StdioCollector {
            onStreamFinished: {
                const code = text.trim();
                if (code.startsWith("mochi:"))
                    root.ipc("vecJoin", code);
            }
        }
    }

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
                    colour: root.sulky ? Colours.palette.m3outline : Colours.palette.m3onSurface   // (corazones del color de Mochi, sin rojo)
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
                        fgColour: root.sulky ? Colours.palette.m3outline : Colours.palette.m3onSurface
                    }

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: root.sulky ? "Acarícialo o cógelo: la primera vez te girará la cara, pero si insistes te perdona." : "Sube acariciándolo (pasa el ratón de lado a lado por encima) o cogiéndolo; y un poco solo con estar con él."
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

        // Vecindario: mandar a tu Mochi de visita a casa de otra persona (y recibir el suyo)
        StyledText {
            Layout.topMargin: Tokens.spacing.small
            Layout.leftMargin: Tokens.padding.medium
            text: "Vecindario"
            font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
            color: Colours.palette.m3onSurface
        }

        StyledRect {
            Layout.fillWidth: true
            implicitHeight: vecCol.implicitHeight + Tokens.padding.medium * 2
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer

            ColumnLayout {
                id: vecCol

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.small

                // dónde está tu Mochi y quién te visita
                StyledText {
                    visible: !!root.st.away
                    Layout.fillWidth: true
                    text: root.st.away ? `Tu Mochi está de visita en casa de ${root.st.away.to} (desde las ${Qt.formatTime(new Date(root.st.away.since), "HH:mm")})` : ""
                    font: Tokens.font.body.builders.small.weight(Font.DemiBold).build()
                    color: Colours.palette.m3primary
                    wrapMode: Text.WordWrap
                }
                Repeater {
                    model: root.st.guests ?? []

                    RowLayout {
                        id: guestRow

                        required property string modelData

                        Layout.fillWidth: true

                        MaterialIcon {
                            text: "pets"
                            color: Colours.palette.m3tertiary
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: `Te visita el Mochi de ${guestRow.modelData}`
                            font: Tokens.font.body.small
                        }
                        IconTextButton {
                            icon: "home"
                            text: "Devolverlo"
                            isRound: true
                            type: IconTextButton.Tonal
                            onClicked: root.ipc("vecGuestHome", guestRow.modelData)
                        }
                    }
                }

                // tus vecinos
                StyledText {
                    visible: !(root.st.neighbours ?? []).length
                    Layout.fillWidth: true
                    text: "Aún no tienes vecinos. Invita a alguien (tiene que tener Mochi): te dará un código para mandarle; él lo copia y pulsa «Pegar código» en su dashboard."
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                    wrapMode: Text.WordWrap
                }
                Repeater {
                    model: root.st.neighbours ?? []

                    RowLayout {
                        id: nRow

                        required property var modelData
                        readonly property bool hereNow: root.st.away?.to === modelData.name

                        Layout.fillWidth: true
                        spacing: Tokens.spacing.medium

                        MaterialIcon {
                            text: nRow.modelData.side === "right" ? "arrow_forward" : "arrow_back"
                            color: Colours.palette.m3secondary
                        }
                        StyledRect {
                            implicitWidth: 8
                            implicitHeight: 8
                            radius: 4
                            color: nRow.modelData.online ? Colours.palette.m3primary : Colours.palette.m3outline
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: `${nRow.modelData.name} · ${nRow.modelData.online ? "conectado" : "desconectado"} · a tu ${nRow.modelData.side === "right" ? "derecha" : "izquierda"}`
                            font: Tokens.font.body.small
                        }
                        IconTextButton {
                            visible: !root.st.away
                            icon: "send"
                            text: "Mandarle a Mochi"
                            isRound: true
                            type: IconTextButton.Tonal
                            onClicked: root.ipc("vecSend", nRow.modelData.name)
                        }
                        IconTextButton {
                            visible: nRow.hereNow
                            icon: "undo"
                            text: "Llamarlo"
                            isRound: true
                            type: IconTextButton.Tonal
                            onClicked: root.ipc("vecRecall")
                        }
                    }
                }

                StyledText {
                    visible: !!root.st.invite
                    Layout.fillWidth: true
                    text: "Código de invitación copiado: pégaselo a tu amigo (en WhatsApp, por ejemplo). Él lo copia y pulsa «Pegar código» en su dashboard."
                    font: Tokens.font.body.small
                    color: Colours.palette.m3tertiary
                    wrapMode: Text.WordWrap
                }
                StyledText {
                    visible: !!root.st.neighbourMsg
                    Layout.fillWidth: true
                    text: root.st.neighbourMsg ?? ""
                    font: Tokens.font.body.small
                    color: Colours.palette.m3error
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    spacing: Tokens.spacing.small

                    IconTextButton {
                        icon: "arrow_forward"
                        text: "Invitar (a mi derecha)"
                        isRound: true
                        type: IconTextButton.Tonal
                        onClicked: root.ipc("vecInvite", "right")
                    }
                    IconTextButton {
                        icon: "arrow_back"
                        text: "Invitar (a mi izquierda)"
                        isRound: true
                        type: IconTextButton.Tonal
                        onClicked: root.ipc("vecInvite", "left")
                    }
                    IconTextButton {
                        icon: "content_paste"
                        text: "Pegar código"
                        isRound: true
                        type: IconTextButton.Tonal
                        onClicked: pasteCode.running = true
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
