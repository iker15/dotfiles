pragma ComponentBehavior: Bound

import "mochi/Draw.js" as Draw
import "mochi/Traits.js" as Traits
import "mochi/Skins.js" as Skins
import "../lock/mochi" as Mochi
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.containers
import qs.services

// Pestaña de Mochi (~/.config/quickshell/tamagotchi) en el dashboard: su ficha. Cómo está y por
// qué, el cariño que te tiene, su nivel, su gorro y botones rápidos. (Ya no es un chat.) Lee lo
// que él publica en $XDG_RUNTIME_DIR/mochi-state.json y habla con él por IPC.
Item {
    id: root

    property var st: ({})
    // Crear a Mochi (si aún no ha nacido) o elegir un rasgo nuevo (si ha desbloqueado un hueco):
    // se muestra el creador en vez de su ficha. Una vez nacido no se retoca: solo empezar de cero.
    property bool editing: false
    property bool confirmReset: false
    readonly property int freeTraits: Traits.slots(st.level ?? 1) - Mochi.Look.traits.length
    readonly property bool creating: Mochi.Look.loaded && (!Mochi.Look.born || editing)

    // Transformaciones: la que has seleccionado entre las 3 que le han salido (antes de confirmar)
    property string skinChoice: ""
    readonly property int skinLevel: Mochi.Wardrobe.pendingLevel
    readonly property int skinNext: Skins.nextAt(st.level ?? 1)
    onSkinLevelChanged: skinChoice = ""

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

    // Tamaños a medida de la pantalla: pensados para 1080 de alto; en pantallas más bajas
    // (1366x768…) todo encoge en proporción para que la ficha quepa entera
    readonly property real screenH: (QsWindow.window as QsWindow)?.screen?.height ?? 1080
    readonly property real k: Math.max(0.6, Math.min(1, screenH / 1080))
    readonly property real maxH: screenH >= 1080 ? 900 : screenH * 0.82   // (con las pestañas y el marco, cabe)

    implicitWidth: Math.round(840 * k)
    implicitHeight: creating ? creatorFlick.height : mainFlick.height

    // El creador, con barra para bajar si no cabe (ancho fijo: todo se reparte en líneas)
    StyledFlickable {
        id: creatorFlick

        visible: root.creating
        width: root.implicitWidth
        height: Math.min(creator.implicitHeight, root.maxH)
        contentWidth: width
        contentHeight: creator.implicitHeight
        flickableDirection: Flickable.VerticalFlick
        clip: true

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: creatorFlick
        }

        MochiCreator {
            id: creator

            width: creatorFlick.width - 16   // (sitio para la barra)
            level: root.st.level ?? 1
            onDone: root.editing = false
        }
    }

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

    // Su ficha, con barra para bajar si no cabe (con las transformaciones puede no caber)
    StyledFlickable {
        id: mainFlick

        visible: !root.creating
        width: root.implicitWidth
        height: Math.min(layout.implicitHeight, root.maxH)
        contentWidth: width
        contentHeight: layout.implicitHeight
        flickableDirection: Flickable.VerticalFlick
        clip: true

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: mainFlick
        }

        ColumnLayout {
            id: layout

            width: mainFlick.width - 16   // (sitio para la barra)
            spacing: Tokens.spacing.medium

            // Cabecera: nombre y cómo está
            RowLayout {
                Layout.leftMargin: Tokens.padding.large
                Layout.rightMargin: Tokens.padding.large
                Layout.fillWidth: true

                Column {
                    spacing: Tokens.spacing.extraSmall

                    Row {
                        spacing: Tokens.spacing.small

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Mochi"
                            font: Tokens.font.body.builders.large.size(28).weight(Font.DemiBold).build()
                            color: Colours.palette.m3onSurface
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !!Mochi.Look.nick
                            text: `«${Mochi.Look.nick}»`
                            font: Tokens.font.body.large
                            color: Colours.palette.m3primary
                        }
                        IconTextButton {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.freeTraits > 0
                            icon: "add"
                            text: "Rasgo nuevo"
                            isRound: true
                            type: IconTextButton.Tonal
                            onClicked: root.editing = true
                        }
                    }

                    StyledText {
                        text: root.st.text ? root.st.text.charAt(0).toUpperCase() + root.st.text.slice(1) : "…"
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    // Su carácter (y si ha desbloqueado un rasgo nuevo, avisa)
                    StyledText {
                        text: Mochi.Look.traits.map(id => Traits.byId(id)?.name).filter(Boolean).join(" · ") + (root.freeTraits > 0 ? "  ·  ¡puede aprender un rasgo nuevo!" : "")
                        font: Tokens.font.body.small
                        color: root.freeTraits > 0 ? Colours.palette.m3tertiary : Colours.palette.m3primary
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
                implicitHeight: 230 * root.k

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

                        Layout.preferredWidth: 230 * root.k
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
                                y: height - 22 * root.k,
                                s: 70 * root.k,
                                body: root.st.body ?? "#d0d3d6",
                                ink: root.st.ink ?? "#1c1b1b",
                                face: f,
                                hat: root.st.hat ?? "",
                                melt: root.st.melt ?? 0,
                                snow: root.st.snow ?? 0,
                                stage: root.st.stage ?? 1,
                                look: Mochi.Look.data(),
                                skin: root.st.skin ?? "",
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

            // Transformaciones: cada 5 niveles le salen 3 y eliges una; luego se la pones cuando quieras
            StyledText {
                Layout.topMargin: Tokens.spacing.small
                Layout.leftMargin: Tokens.padding.medium
                text: "Transformaciones"
                font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
                color: Colours.palette.m3onSurface
            }

            StyledRect {
                Layout.fillWidth: true
                implicitHeight: skinCol.implicitHeight + Tokens.padding.large * 2
                radius: Tokens.rounding.large
                color: Colours.tPalette.m3surfaceContainer

                ColumnLayout {
                    id: skinCol

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    // Le han salido 3: elige una
                    RowLayout {
                        visible: root.skinLevel > 0
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.medium

                        MaterialIcon {
                            text: "auto_awesome"
                            color: Colours.palette.m3tertiary
                            fill: 1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            wrapMode: Text.WordWrap
                            text: `¡Nivel ${root.skinLevel}! Mochi ha aprendido a transformarse. Elige en qué:`
                            font: Tokens.font.body.builders.small.weight(Font.DemiBold).build()
                            color: Colours.palette.m3tertiary
                        }
                    }
                    RowLayout {
                        visible: root.skinLevel > 0
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.medium

                        Repeater {
                            model: root.skinLevel > 0 ? Mochi.Wardrobe.pendingOffer : []

                            SkinTile {
                                required property string modelData

                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                skin: modelData
                                big: true
                                selected: root.skinChoice === modelData
                                onClicked: root.skinChoice = modelData
                            }
                        }
                    }
                    RowLayout {
                        visible: root.skinLevel > 0
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.medium

                        StyledText {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            wrapMode: Text.WordWrap
                            text: root.skinChoice ? "Se transformará en cuanto cierres el dashboard. Las otras dos pueden volver a salirte más adelante." : "Toca una para verla elegida."
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                        IconTextButton {
                            enabled: !!root.skinChoice
                            opacity: enabled ? 1 : 0.5
                            icon: "check"
                            text: root.skinChoice ? `Quedarme con ${Skins.byId(root.skinChoice)?.name ?? ""}` : "Elegir"
                            isRound: true
                            type: IconTextButton.Filled
                            onClicked: {
                                root.ipc("skinPick", String(root.skinLevel), root.skinChoice);
                                root.skinChoice = "";
                            }
                        }
                    }

                    // Las que ya sabe hacer: toca una para que se transforme (o vuelva a ser él)
                    Flow {
                        visible: Mochi.Wardrobe.owned.length > 0
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        spacing: Tokens.spacing.small

                        Repeater {
                            model: [""].concat(Mochi.Wardrobe.owned)

                            SkinTile {
                                required property string modelData

                                width: 104 * root.k
                                skin: modelData
                                selected: Mochi.Wardrobe.wearing === modelData
                                onClicked: root.ipc("skinWear", modelData || "none")
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        wrapMode: Text.WordWrap
                        text: {
                            const lvl = root.st.level ?? 1, xp = root.st.xp ?? 0;
                            const need = Math.max(0, Math.round(60 * Math.pow(root.skinNext - 1, 1.6)) - xp);
                            const all = Mochi.Wardrobe.owned.length + Mochi.Wardrobe.pendingOffer.length >= Skins.list.length;
                            if (all)
                                return "Ya sabe transformarse en todo lo que hay.";
                            const pre = Mochi.Wardrobe.owned.length ? "Toca una para que se transforme. " : "Mochi es un fluido: cada 5 niveles aprende a convertirse en un personaje (Ditto, Tom Nook, Kirby…) y te deja elegir entre 3. ";
                            return pre + `La siguiente, en el nivel ${root.skinNext} (te faltan ${need} XP).`;
                        }
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
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
                    value: root.st.watching ? "viendo un vídeo" : root.st.music ? "escuchando música" : root.st.where === "nest" ? (root.st.waiting ? "esperándote en su nido" : "en su nido") : root.st.where === "dive" ? "buceando" : "paseando"
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
                    onClicked: root.ipc("waitNest")
                }
                IconTextButton {
                    icon: "bedtime"
                    text: "A dormir"
                    isRound: true
                    type: IconTextButton.Tonal
                    onClicked: root.ipc("sleep", "doze")
                }
                IconTextButton {
                    icon: "restart_alt"
                    text: "Empezar de cero"
                    isRound: true
                    type: IconTextButton.Text
                    onClicked: root.confirmReset = true
                }
            }

            // Empezar de cero: avisa de todo lo que se pierde antes de hacerlo
            StyledRect {
                Layout.fillWidth: true
                visible: root.confirmReset
                implicitHeight: resetCol.implicitHeight + Tokens.padding.large * 2
                radius: Tokens.rounding.large
                color: Colours.palette.m3errorContainer

                ColumnLayout {
                    id: resetCol

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.small

                    RowLayout {
                        spacing: Tokens.spacing.medium

                        MaterialIcon {
                            text: "warning"
                            color: Colours.palette.m3onErrorContainer
                        }
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: `¿Empezar de cero? Este Mochi se despedirá y desaparecerá para siempre: su aspecto, su mote, su carácter, su nivel (${root.st.level ?? 1}), sus transformaciones y el cariño que te tiene (${root.bond}/100). No se puede deshacer. Luego podrás crear uno nuevo.`
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onErrorContainer
                        }
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: Tokens.spacing.small

                        IconTextButton {
                            icon: "close"
                            text: "No, me lo quedo"
                            isRound: true
                            type: IconTextButton.Text
                            onClicked: root.confirmReset = false
                        }
                        IconTextButton {
                            icon: "restart_alt"
                            text: "Sí, empezar de cero"
                            isRound: true
                            type: IconTextButton.Filled
                            onClicked: {
                                root.confirmReset = false;
                                root.ipc("resetMochi");
                            }
                        }
                    }
                }
            }
        }
    }

    // Una transformación (o él mismo, skin ""): retrato vivo + nombre
    component SkinTile: StyledRect {
        id: tile

        property string skin
        readonly property real k: Math.max(0.6, Math.min(1, ((QsWindow.window as QsWindow)?.screen?.height ?? 1080) / 1080))
        property bool big: false
        property bool selected: false
        readonly property var def: Skins.byId(skin)
        signal clicked

        implicitHeight: (big ? 212 : 118) * k
        radius: Tokens.rounding.medium
        color: selected ? Colours.palette.m3secondaryContainer : tileHover.hovered ? Colours.tPalette.m3surfaceContainerHigh : "transparent"
        border.width: selected ? 2 : 0
        border.color: Colours.palette.m3primary

        HoverHandler {
            id: tileHover

            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            onTapped: tile.clicked()
        }

        Canvas {
            id: tileArt

            property real t: 0
            property real blink: 0

            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: tile.big ? 4 : 2
            width: (tile.big ? 190 : 100) * tile.k
            height: (tile.big ? 160 : 90) * tile.k

            onTChanged: requestPaint()
            Component.onCompleted: requestPaint()

            // (solo se mueven las grandes, o la que tienes debajo del ratón)
            FrameAnimation {
                running: tileArt.visible && (tile.big || tileHover.hovered || tile.selected)
                onTriggered: {
                    tileArt.t += frameTime;
                    const k = tileArt.t % 3.7;
                    tileArt.blink = k < 0.08 ? k / 0.08 : k < 0.2 ? 1 - (k - 0.08) / 0.12 : 0;
                }
            }

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const f = tile.selected ? "happy" : tileHover.hovered ? "excited" : "normal";
                Draw.avatar(ctx, {
                    x: width / 2,
                    y: height - 8 * tile.k,
                    s: (tile.big ? 46 : 27) * tile.k,
                    body: root.st.body ?? "#d0d3d6",
                    ink: root.st.ink ?? "#1c1b1b",
                    face: f,
                    stage: 1,
                    look: Mochi.Look.data(),
                    skin: tile.skin,
                    blink: f === "normal" ? blink : 0,
                    breath: 0.5 + 0.5 * Math.sin(t * 2.6),
                    t: t
                });
            }
        }

        Column {
            anchors.top: tileArt.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 0

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tile.def?.name ?? "Él mismo"
                font: Tokens.font.body.builders.small.weight(Font.DemiBold).build()
                color: Colours.palette.m3onSurface
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: tile.big
                text: tile.def?.from ?? "Mochi"
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
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

        readonly property real k: Math.max(0.6, Math.min(1, ((QsWindow.window as QsWindow)?.screen?.height ?? 1080) / 1080))

        property string icon
        property string label
        property string value
        property color colour

        Layout.fillWidth: true
        Layout.preferredHeight: 60 * k
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
