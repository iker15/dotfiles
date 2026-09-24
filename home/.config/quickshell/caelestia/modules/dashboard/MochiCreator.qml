pragma ComponentBehavior: Bound

import "mochi/Draw.js" as Draw
import "mochi/Traits.js" as Traits
import "../lock/mochi" as Mochi
import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// Crear a tu Mochi antes de que nazca. Siempre es un blob blandito con dos ojos y siempre se llama
// Mochi: aquí eliges los detalles (Mochi.Look), un mote y su carácter (rasgos de Traits.js: 3).
// Al nacer es para siempre: no se puede retocar (solo empezar de cero, desde su ficha). Lo único
// que se puede hacer después es elegir un rasgo nuevo cuando se desbloquea un hueco (niveles 10,
// 20 y 35): entonces este creador solo enseña los rasgos (traitsOnly).
Item {
    id: root

    readonly property var look: Mochi.Look
    readonly property bool born: look.born
    property int level: 1                        // su nivel (de mochi-state.json)
    readonly property int slots: Traits.slots(level)
    property var draft: look.data()
    property var original: look.data()
    property var locked: []                      // rasgos que ya tenía (no se quitan)
    property string face: "normal"
    property string hint: ""                     // descripción del rasgo bajo el ratón
    readonly property var chosen: draft.traits ?? []
    readonly property bool traitsOnly: born
    readonly property bool ready: traitsOnly ? chosen.length > locked.length : chosen.length >= Math.min(3, slots)
    property bool confirming: false              // segundo clic: «¿seguro? es para siempre»

    signal done

    readonly property var nicks: ["Gordi", "Bolita", "Mochito", "Pompón", "Blandi", "Nubecita", "Chiqui", "Bichito", "Tofu", "Dango", "Peque", "Gelatín", "Blub", "Moti", "Gominola", "Flan", "Bombón", "Pelotilla"]
    readonly property var presets: [
        {
            label: "Clásico",
            icon: "circle",
            v: {}
        },
        {
            label: "Bolita",
            icon: "radio_button_unchecked",
            v: {
                wide: 0.9,
                eyeSize: 0.95,
                eyeGap: 0.9,
                eyeY: 0.3,
                jelly: 1.2
            }
        },
        {
            label: "Ojazos",
            icon: "visibility",
            v: {
                eyeSize: 1.4,
                eyeShape: 0.35,
                eyeGap: 1.12,
                wide: 1.08
            }
        },
        {
            label: "Soñoliento",
            icon: "bedtime",
            v: {
                eyeShape: -0.55,
                eyeSize: 0.85,
                eyeY: 0.45,
                wide: 1.18,
                jelly: 1.1
            }
        },
        {
            label: "Gelatina",
            icon: "bubble_chart",
            v: {
                jelly: 1.6,
                wide: 1.12,
                eyeGap: 0.85
            }
        }
    ]

    function reset(): void {
        original = look.data();
        draft = born ? look.data() : look.clean({});
        locked = born ? (look.traits ?? []).slice() : [];
        hint = "";
        confirming = false;
        face = "happy";
        faceBack.restart();
    }

    function changed(d: var, k: real): void {
        draft = d;
        confirming = false;
        jiggle(k);
    }

    function set(key: string, v: real): void {
        const d = Object.assign({}, draft);
        d[key] = v;
        changed(d, 0.6);
    }

    // Solo el aspecto (el mote y el carácter se quedan)
    function applyPreset(v: var): void {
        changed(look.clean(Object.assign({
            nick: draft.nick,
            traits: draft.traits
        }, v)), 1.4);
        face = "excited";
        faceBack.restart();
    }

    function randomize(): void {
        const d = {
            nick: draft.nick,
            traits: draft.traits
        };
        for (const k in look.ranges) {
            const [lo, hi] = look.ranges[k];
            const r = (Math.random() + Math.random()) / 2;   // (hacia el centro: casi siempre mono)
            d[k] = lo + (hi - lo) * r;
        }
        // (sin nacer, también un carácter al azar)
        if (!born) {
            const pool = Traits.list.map(t => t.id).sort(() => Math.random() - 0.5);
            d.traits = Traits.clean(pool, 3);
        }
        changed(look.clean(d), 1.6);
        face = "surprised";
        faceBack.restart();
    }

    function otherNick(): void {
        let n = draft.nick;
        while (n === draft.nick)
            n = nicks[Math.floor(Math.random() * nicks.length)];
        const d = Object.assign({}, draft);
        d.nick = n;
        changed(d, 0.8);
    }

    function clearNick(): void {
        const d = Object.assign({}, draft);
        d.nick = "";
        changed(d, 0.4);
    }

    function toggleTrait(id: string): void {
        const cur = chosen.slice(), i = cur.indexOf(id);
        if (i >= 0) {
            if (locked.includes(id))
                return;   // ya es parte de él
            cur.splice(i, 1);
        } else {
            if (cur.length >= slots || Traits.clashes(id, cur))
                return;
            cur.push(id);
        }
        const d = Object.assign({}, draft);
        d.traits = cur;
        changed(d, 1);
        face = i >= 0 ? "normal" : "happy";
        faceBack.restart();
    }

    function jiggle(k: real): void {
        preview.sqV -= 5 * k * (draft.jelly ?? 1);
    }

    function commit(): void {
        if (!confirming) {
            confirming = true;   // primero avisa: es para siempre
            return;
        }
        // (ya nacido: solo se añaden los rasgos nuevos; lo demás no se toca)
        look.save(traitsOnly ? Object.assign(look.data(), {
            traits: chosen
        }) : draft, true);
        done();
    }

    function cancel(): void {
        done();
    }

    Component.onCompleted: reset()
    onVisibleChanged: if (visible) reset()

    implicitWidth: 840
    implicitHeight: col.implicitHeight

    Timer {
        id: faceBack

        interval: 1100
        onTriggered: root.face = "normal"
    }

    ColumnLayout {
        id: col

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Tokens.spacing.medium

        // Cabecera
        Column {
            Layout.leftMargin: Tokens.padding.large
            spacing: Tokens.spacing.extraSmall

            StyledText {
                text: root.traitsOnly ? "Un rasgo nuevo para Mochi" : "Crea a tu Mochi"
                font: Tokens.font.body.builders.large.size(28).weight(Font.DemiBold).build()
                color: Colours.palette.m3onSurface
            }
            StyledText {
                text: root.traitsOnly ? "Ha crecido y puede aprender algo más de carácter. Su aspecto y su mote ya son suyos." : "Aún no ha nacido. Siempre será un blob blandito: tú decides los detalles y su carácter. Piénsalo bien: al nacer ya no se puede cambiar."
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            // Vista previa, viva
            StyledRect {
                Layout.preferredWidth: 280
                Layout.fillWidth: root.traitsOnly
                Layout.fillHeight: true
                Layout.minimumHeight: root.traitsOnly ? 230 : 330
                radius: Tokens.rounding.extraLarge * 2
                color: Colours.tPalette.m3surfaceContainer

                Canvas {
                    id: preview

                    property real t: 0
                    property real blink: 0
                    property real lx: 0
                    property real ly: 0
                    property real tlx: 0
                    property real tly: 0
                    property real sq: 0      // squash (muelle, más blando cuanta más gelatina)
                    property real sqV: 0
                    readonly property var faces: ["normal", "happy", "love", "surprised", "sleepy", "curious", "sad"]
                    property int faceIdx: 0
                    // ritmo según su carácter
                    readonly property real pace: root.chosen.includes("inquieto") ? 1.25 : root.chosen.includes("dormilon") ? 0.75 : 1

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: nickRow.top

                    onTChanged: requestPaint()

                    FrameAnimation {
                        running: preview.visible
                        onTriggered: {
                            const dt = Math.min(frameTime, 1 / 30), jl = root.draft.jelly ?? 1;
                            preview.t += dt;
                            preview.sqV += (-140 * preview.sq - 9 / jl * preview.sqV) * dt;
                            preview.sq += preview.sqV * dt;
                            preview.lx += (preview.tlx - preview.lx) * Math.min(1, dt * 6);
                            preview.ly += (preview.tly - preview.ly) * Math.min(1, dt * 6);
                        }
                    }
                    Timer {
                        running: preview.visible
                        repeat: true
                        interval: 3000
                        onTriggered: {
                            interval = (2200 + Math.random() * 3000) / preview.pace;
                            blinkAnim.restart();
                            if (Math.random() < 0.6) {
                                preview.tlx = Math.random() * 1.6 - 0.8;
                                preview.tly = Math.random() * 0.8 - 0.4;
                            }
                        }
                    }
                    SequentialAnimation {
                        id: blinkAnim

                        NumberAnimation {
                            target: preview
                            property: "blink"
                            to: 1
                            duration: 70
                        }
                        NumberAnimation {
                            target: preview
                            property: "blink"
                            to: 0
                            duration: 130
                        }
                    }

                    // Clic: prueba otra cara
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            preview.faceIdx = (preview.faceIdx + 1) % preview.faces.length;
                            root.face = preview.faces[preview.faceIdx];
                            faceBack.stop();
                            root.jiggle(1);
                        }
                    }

                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const f = root.face;
                        const x = width / 2, y = height - 26;
                        // aplastado/estirado desde la base
                        ctx.translate(x, y);
                        ctx.scale(1 + sq * 0.05, 1 - sq * 0.07);
                        ctx.translate(-x, -y);
                        Draw.avatar(ctx, {
                            x: x,
                            y: y,
                            s: 70,
                            body: Colours.palette.m3surfaceContainerHighest,
                            ink: Colours.palette.m3onSurface,
                            face: f,
                            look: root.draft,
                            blink: f === "sleepy" ? 0.3 : blink,
                            lx: lx,
                            ly: ly,
                            breath: 0.5 + 0.5 * Math.sin(t * 2.6 * pace),
                            shadow: 1,
                            t: t
                        });
                    }
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: Tokens.padding.medium
                    text: "clic: otra cara"
                    font: Tokens.font.body.small
                    color: Colours.palette.m3outline
                }

                // Siempre es Mochi; el mote, a dados (el dashboard no recibe teclado)
                Column {
                    id: nickRow

                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Tokens.padding.large
                    spacing: 0

                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Mochi"
                        font: Tokens.font.body.builders.large.weight(Font.DemiBold).build()
                        color: Colours.palette.m3onSurface
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Tokens.spacing.extraSmall

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.draft.nick ? `«${root.draft.nick}»` : root.traitsOnly ? "" : "sin mote"
                            font: Tokens.font.body.small
                            color: root.draft.nick ? Colours.palette.m3primary : Colours.palette.m3outline
                        }
                        IconButton {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !root.traitsOnly
                            icon: "casino"
                            type: IconButton.Text
                            onClicked: root.otherNick()
                        }
                        IconButton {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !!root.draft.nick && !root.traitsOnly
                            icon: "close"
                            type: IconButton.Text
                            onClicked: root.clearNick()
                        }
                    }
                }
            }

            // Controles de aspecto (solo antes de nacer)
            ColumnLayout {
                visible: !root.traitsOnly
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: Tokens.spacing.small

                Section {
                    title: "Ojos"
                    icon: "visibility"

                    LookSlider {
                        key: "eyeSize"
                        label: "Tamaño"
                        words: ["pequeñitos", "normales", "enormes"]
                    }
                    LookSlider {
                        key: "eyeGap"
                        label: "Separación"
                        words: ["juntitos", "normal", "separados"]
                    }
                    LookSlider {
                        key: "eyeY"
                        label: "Altura"
                        words: ["arriba", "en medio", "abajo"]
                    }
                    LookSlider {
                        key: "eyeShape"
                        label: "Forma"
                        words: ["ovalados", "redondos", "alargados"]
                    }
                }

                Section {
                    title: "Cuerpo"
                    icon: "bubble_chart"

                    LookSlider {
                        key: "wide"
                        label: "Proporción"
                        words: ["alto", "normal", "achuchable"]
                    }
                    LookSlider {
                        key: "jelly"
                        label: "Blandura"
                        words: ["firme", "blandito", "gelatina"]
                    }
                }

                // Estilos rápidos (solo el aspecto)
                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacing.extraSmall
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: root.presets

                        IconTextButton {
                            required property var modelData

                            icon: modelData.icon
                            text: modelData.label
                            isRound: true
                            type: IconTextButton.Tonal
                            onClicked: root.applyPreset(modelData.v)
                        }
                    }
                    IconTextButton {
                        icon: "shuffle"
                        text: "Al azar"
                        isRound: true
                        type: IconTextButton.Tonal
                        onClicked: root.randomize()
                    }
                }
            }
        }

        // Carácter: rasgos
        RowLayout {
            Layout.leftMargin: Tokens.padding.small
            Layout.rightMargin: Tokens.padding.large
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "mood"
                color: Colours.palette.m3primary
            }
            StyledText {
                text: "Carácter"
                font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
                color: Colours.palette.m3onSurface
            }
            StyledText {
                Layout.fillWidth: true
                text: {
                    const n = root.chosen.length, next = Traits.nextSlotAt(root.level);
                    const more = next ? ` · otro hueco en el nivel ${next}` : "";
                    if (!root.born)
                        return `elige ${root.slots} rasgos (${n}/${root.slots})${more}`;
                    if (n < root.slots)
                        return `¡tienes ${root.slots - n} ${root.slots - n === 1 ? "rasgo nuevo" : "rasgos nuevos"} para elegir! (${n}/${root.slots})${more}`;
                    return `${n}/${root.slots} rasgos${more}`;
                }
                font: Tokens.font.body.small
                color: root.born && root.chosen.length < root.slots ? Colours.palette.m3tertiary : Colours.palette.m3onSurfaceVariant
            }
        }

        StyledRect {
            Layout.fillWidth: true
            implicitHeight: traitCol.implicitHeight + Tokens.padding.medium * 2
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer

            ColumnLayout {
                id: traitCol

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.large
                anchors.rightMargin: Tokens.padding.large
                spacing: Tokens.spacing.small

                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: Traits.list

                        TraitChip {}
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: root.hint || "Pasa el ratón por un rasgo para ver qué hace. Cambian de verdad cómo se comporta, y los que elijas serán parte de él para siempre."
                    font: Tokens.font.body.small
                    color: root.hint ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                }
            }
        }

        // Aviso antes de confirmar: es para siempre
        StyledRect {
            Layout.fillWidth: true
            visible: root.confirming
            implicitHeight: warn.implicitHeight + Tokens.padding.medium * 2
            radius: Tokens.rounding.large
            color: Colours.palette.m3tertiaryContainer

            RowLayout {
                id: warn

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: "warning"
                    color: Colours.palette.m3onTertiaryContainer
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: root.traitsOnly ? "Este rasgo será parte de Mochi para siempre: luego no se puede quitar." : "Cuando nazca será así para siempre: no podrás cambiar su aspecto, su mote ni su carácter. La única forma de cambiarlo será empezar de cero, y perderías su nivel y el cariño que te tenga."
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onTertiaryContainer
                }
            }
        }

        // Nacer / guardar
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Tokens.spacing.small
            spacing: Tokens.spacing.small

            IconTextButton {
                visible: root.born || root.confirming
                icon: root.confirming ? "arrow_back" : "close"
                text: root.confirming ? "Pensármelo" : "Cancelar"
                isRound: true
                type: IconTextButton.Text
                onClicked: root.confirming ? root.confirming = false : root.cancel()
            }
            IconTextButton {
                enabled: root.ready
                opacity: enabled ? 1 : 0.5
                icon: root.confirming ? "check" : root.traitsOnly ? "add" : "egg"
                text: {
                    if (!root.ready)
                        return root.traitsOnly ? "Elige un rasgo nuevo" : `Elige ${Math.min(3, root.slots) - root.chosen.length} ${Math.min(3, root.slots) - root.chosen.length === 1 ? "rasgo más" : "rasgos más"}`;
                    if (root.confirming)
                        return root.traitsOnly ? "Sí, que lo aprenda" : "Sí, que nazca así";
                    return root.traitsOnly ? "Aprender rasgo" : "¡Que nazca Mochi!";
                }
                isRound: true
                type: IconTextButton.Filled
                onClicked: root.commit()
            }
        }
    }

    component TraitChip: StyledRect {
        id: chip

        required property var modelData
        readonly property bool on: root.chosen.includes(modelData.id)
        readonly property bool fixed: on && root.locked.includes(modelData.id)
        readonly property bool blocked: !on && (root.chosen.length >= root.slots || Traits.clashes(modelData.id, root.chosen))

        implicitWidth: chipRow.implicitWidth + Tokens.padding.medium * 2
        implicitHeight: chipRow.implicitHeight + Tokens.padding.small * 2
        radius: Tokens.rounding.full
        color: on ? Colours.palette.m3primary : Colours.palette.m3secondaryContainer
        opacity: blocked ? 0.45 : 1

        Row {
            id: chipRow

            anchors.centerIn: parent
            spacing: Tokens.spacing.extraSmall

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.fixed ? "lock" : chip.modelData.icon
                fill: chip.on ? 1 : 0
                color: chip.on ? Colours.palette.m3onPrimary : Colours.palette.m3onSecondaryContainer
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.modelData.name
                font: Tokens.font.body.small
                color: chip.on ? Colours.palette.m3onPrimary : Colours.palette.m3onSecondaryContainer
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: chip.blocked || chip.fixed ? Qt.ArrowCursor : Qt.PointingHandCursor
            onEntered: {
                const vs = chip.modelData.vs.map(v => Traits.byId(v)?.name).filter(Boolean);
                root.hint = `${chip.modelData.name}: ${chip.modelData.desc}${vs.length ? ` (no va con ${vs.join(" ni ")})` : ""}${chip.fixed ? " · ya es parte de él" : ""}`;
            }
            onExited: root.hint = ""
            onClicked: root.toggleTrait(chip.modelData.id)
        }
    }

    component Section: ColumnLayout {
        id: sec

        property string title
        property string icon
        default property alias rows: body.data

        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        RowLayout {
            Layout.leftMargin: Tokens.padding.small
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: sec.icon
                color: Colours.palette.m3primary
            }
            StyledText {
                text: sec.title
                font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
                color: Colours.palette.m3onSurface
            }
        }

        StyledRect {
            Layout.fillWidth: true
            implicitHeight: body.implicitHeight + Tokens.padding.medium * 2
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer

            ColumnLayout {
                id: body

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.large
                anchors.rightMargin: Tokens.padding.large
                spacing: Tokens.spacing.small
            }
        }
    }

    component LookSlider: RowLayout {
        id: ls

        property string key
        property string label
        property var words: []
        readonly property var range: root.look.ranges[key] ?? [0, 1, 0.5]
        readonly property real val: root.draft[key] ?? range[2]
        readonly property real frac: (val - range[0]) / (range[1] - range[0])

        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        StyledText {
            Layout.preferredWidth: 90
            text: ls.label
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurface
        }
        StyledSlider {
            Layout.fillWidth: true
            implicitHeight: 14
            value: ls.frac
            onInteraction: v => root.set(ls.key, ls.range[0] + (ls.range[1] - ls.range[0]) * v)
        }
        StyledText {
            Layout.preferredWidth: 96
            horizontalAlignment: Text.AlignRight
            // la palabra según dónde esté respecto al valor por defecto
            text: {
                const [lo, hi, def] = ls.range, v = ls.val;
                if (Math.abs(v - def) < (hi - lo) * 0.08)
                    return ls.words[1];
                return v < def ? ls.words[0] : ls.words[2];
            }
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurfaceVariant
        }
    }
}
