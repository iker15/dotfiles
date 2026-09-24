import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// Mochi en la pantalla de bloqueo: una ficha más de la tarjeta (en el sitio de la foto de
// perfil), con sus ojos, que de vez en cuando se transforma en cosas y vuelve a ser ficha:
// un reloj con manecillas (la hora de verdad), un candado, una pila con la batería que queda y
// un sol o una luna según la hora. La forma la dibuja mochitile.frag; los ojos, Blob.qml.
// Lo carga caelestia/modules/lock/Center.qml. Aquí no escucha ni obedece.
// - Mientras escribes la contraseña vuelve a ser ficha y aprieta los ojos: no mira.
// - Con Bloq Mayús se sorprende; si fallas, se pone triste y se sacude; al acertar, contento.
// - De madrugada tiene sueño (lo que dejó dicho el Mochi del escritorio al bloquear).
Item {
    id: root

    property var pam                     // buffer de la contraseña
    property int failState: 0            // 0 bien · 1 contraseña mal · 2 demasiados intentos
    property bool capsLock: false
    property bool unlocking: false
    property color tileColor: "#80808080"   // el de las demás fichas (con su transparencia)
    property real radius: 24

    property real drowsy: 0

    // Formas: 0 ficha · 1 reloj · 2 candado · 3 pila · 4 sol · 5 luna
    property int shapeFrom: 0
    property int shapeTo: 0
    property real mix: 1
    readonly property int shape: mix < 0.5 ? shapeFrom : shapeTo
    property int step: 1   // (la primera transformación es el reloj)

    readonly property bool typing: (pam?.buffer?.length ?? 0) > 0 && typingRecent.running
    readonly property real battery: UPower.displayDevice.isLaptopBattery ? UPower.displayDevice.percentage : 1

    property real hourAngle: 0
    property real minuteAngle: 0
    property real time: 0
    property real shake: 0

    // Dónde van los ojos en cada forma (fracción del tamaño, desde el centro; +y abajo)
    function eyeSpot(n: int): point {
        switch (n) {
        case 1:
            return Qt.point(0, -0.2);    // reloj: en la mitad de arriba
        case 2:
            return Qt.point(0, 0.13);    // candado: en el cuerpo
        case 3:
            return Qt.point(0, 0.05);    // pila
        case 5:
            return Qt.point(-0.12, 0.02); // luna: en la parte gruesa
        default:
            return Qt.point(0, 0);
        }
    }
    readonly property point eyes: {
        const a = eyeSpot(shapeFrom), b = eyeSpot(shapeTo), k = Math.max(0, Math.min(1, mix));
        return Qt.point(a.x + (b.x - a.x) * k, a.y + (b.y - a.y) * k);
    }

    function morphTo(n: int): void {
        if (n === shapeTo && mix >= 1)
            return;
        shapeFrom = shape;
        shapeTo = n;
        mix = 0;
        morphAnim.restart();
        mochi.kick(-0.7, 1.2);   // un poco de gelatina al transformarse
    }

    // Lo que sigue en la ronda: ficha → cosa → ficha → otra cosa…
    function nextShape(): int {
        step++;
        if (step % 2 === 1)
            return 0;
        const h = new Date().getHours();
        const sky = h >= 7 && h < 20 ? 4 : 5;
        return [1, 2, 3, sky][(step / 2 - 1) % 4];
    }

    NumberAnimation {
        id: morphAnim

        target: root
        property: "mix"
        from: 0
        to: 1
        duration: 2400                 // poco a poco
        easing.type: Easing.InOutSine
    }

    Timer {
        running: root.visible && !root.typing && !root.capsLock && !root.unlocking && !mochi.dozing
        repeat: true
        interval: 9000
        onTriggered: {
            const n = root.nextShape();
            root.morphTo(n);
            interval = n === 0 ? 12000 + Math.random() * 6000 : 9000;
        }
    }

    // Escribiendo o con Bloq Mayús: vuelve a ser ficha (y a mirar/no mirar)
    onTypingChanged: if (typing) morphTo(0)
    onCapsLockChanged: {
        if (capsLock) {
            morphTo(0);
            mochi.wake();
            mochi.react("surprised", 1200);
            mochi.kick(-1, 2.6);
        }
    }
    onFailStateChanged: {
        if (failState > 0) {
            morphTo(0);
            mochi.wake();
            mochi.react(failState === 2 ? "dizzy" : "sad", 1800);
            shakeAnim.restart();
        }
    }
    onUnlockingChanged: {
        if (unlocking) {
            mochi.wake();
            mochi.react("happy", 1200);
            mochi.kick(-1.6, 3);
        }
    }

    Connections {
        target: root.pam ?? null
        ignoreUnknownSignals: true

        function onBufferChanged(): void {
            typingRecent.restart();
            mochi.wake();
        }
    }

    Timer {
        id: typingRecent

        interval: 1600
    }

    NumberAnimation {
        id: shakeAnim

        target: root
        property: "shake"
        from: 0
        to: 1
        duration: 700
    }

    // Hora (agujas) y tiempo (animaciones de las formas)
    FrameAnimation {
        running: root.visible
        onTriggered: {
            root.time += Math.min(frameTime, 1 / 30);
            const d = new Date(), m = d.getMinutes() + d.getSeconds() / 60;
            root.minuteAngle = m / 60 * 2 * Math.PI;
            root.hourAngle = ((d.getHours() % 12) + m / 60) / 12 * 2 * Math.PI;
        }
    }

    // Sueño: lo que dejó dicho el Mochi del escritorio al bloquear
    FileView {
        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/mochi-lock.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.drowsy = d.drowsy ?? 0;
                if (d.dozing)
                    mochi.dozing = true;
            } catch (e) {}
        }
    }

    // Mover el ratón lo despierta
    HoverHandler {
        onPointChanged: mochi.wake()
    }

    ShaderEffect {
        anchors.fill: parent
        anchors.margins: -12   // (sitio para la gelatina y las formas que sobresalen un poco)

        property vector2d size: Qt.vector2d(width, height)
        property vector4d morph: Qt.vector4d(root.shapeFrom, root.shapeTo, Math.max(0, Math.min(1, root.mix)), root.radius)
        property vector4d info: Qt.vector4d(root.hourAngle, root.minuteAngle, root.battery, root.time)
        property vector2d squash: Qt.vector2d(mochi.sx, mochi.sy)
        property color color: root.tileColor

        // (la ficha ocupa el item; el ShaderEffect tiene 12 px de margen alrededor)
        property real inset: 12
        fragmentShader: Qt.resolvedUrl("mochitile.frag.qsb")
    }

    Blob {
        id: mochi

        x: root.width * (0.5 + root.eyes.x) - width / 2 + Math.sin(root.shake * Math.PI * 6) * 8 * (1 - root.shake)
        y: root.height * (0.5 + root.eyes.y) - height / 2
        u: 1.45 * root.width / 105   // ojos más grandes, dibujados a su tamaño (nítidos)
        worldX: 0
        worldY: 0
        bodyColor: Qt.alpha(root.tileColor, 1)
        drowsy: root.drowsy
        mood: root.typing && !root.capsLock ? "squint" : "idle"
    }
}
