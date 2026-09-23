import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// Mochi en la pantalla de bloqueo (lo carga caelestia/modules/lock/LockSurface.qml).
// Asoma por el borde de abajo, donde se metió el Mochi del escritorio al bloquear, hecho del
// mismo material que la tarjeta del bloqueo. Solo ojos y cuerpo; aquí no escucha ni obedece.
// - Mientras escribes la contraseña aprieta los ojos y se agacha: no mira.
// - Con Bloq Mayús activado se alarma y da botes, mirando al campo de la contraseña.
// - Si fallas, se pone triste y se sacude; si aciertas, se alegra y se lanza al escritorio.
// - De madrugada tiene sueño (cabezadas, se queda frito); mover el ratón lo despierta.
// - Con poca batería mira preocupado al indicador de batería de vez en cuando.
Item {
    id: root

    // Lo que le pasa la pantalla de bloqueo
    property var pam                     // buffer de la contraseña
    property int failState: 0            // 0 bien · 1 contraseña mal · 2 demasiados intentos
    property bool capsLock: false
    property bool unlocking: false
    property bool ready: false           // ya ha terminado la animación de entrada del bloqueo
    property color bodyColor: "#1c1b1b"  // material de la tarjeta del bloqueo
    property real bodyOpacity: 1
    property color shadowColor: "#000000"
    property real smoothing: 32
    property point fieldPos: Qt.point(width / 2, height / 2)     // campo de la contraseña
    property point batteryPos: Qt.point(width * 0.8, height / 2) // indicador de batería

    // Posición y sueño que dejó el Mochi del escritorio al bloquear
    property real homeX: width * 0.7
    property real drowsy: 0

    readonly property real u: 1.45
    readonly property real ry: 29 * u * 0.95
    // Cuánto asoma: 0 = escondido bajo el borde, 1 = como en el escritorio
    property real rise: -0.4
    property real riseV: 0
    property real riseTarget: -0.4
    property real cx: homeX
    property real lookX: 0
    property real lookY: 0

    readonly property bool typing: (pam?.buffer?.length ?? 0) > 0 && typingRecent.running
    readonly property bool lowBattery: UPower.displayDevice.isLaptopBattery && UPower.displayDevice.percentage < 0.15 && UPower.displayDevice.state !== UPowerDeviceState.Charging

    anchors.fill: parent

    FileView {
        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/mochi-lock.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.homeX = d.x;
                root.cx = d.x;
                root.drowsy = d.drowsy ?? 0;
                if (d.dozing)
                    mochi.dozing = true;
            } catch (e) {}
        }
    }

    // ---- Postura: muelle hacia riseTarget (con sus rebotes)
    function updateTarget(): void {
        if (unlocking)
            return;
        if (!ready)
            riseTarget = -0.4;
        else if (capsLock)
            riseTarget = 1.12;
        else if (typing)
            riseTarget = 0.78;   // se agacha y aprieta los ojos: no mira
        else
            riseTarget = 1;
    }

    onReadyChanged: {
        updateTarget();
        if (ready && !mochi.dozing) {
            mochi.kick(-1.4, 3.2);
            mochi.react(drowsy > 0.6 ? "yawn" : "excited", 1300);
        }
    }
    onCapsLockChanged: {
        updateTarget();
        if (capsLock) {
            mochi.wake();
            mochi.react("surprised", 900);
            mochi.kick(-1, 2.6);
        }
    }
    onTypingChanged: updateTarget()

    Connections {
        target: root.pam ?? null
        ignoreUnknownSignals: true

        function onBufferChanged(): void {
            typingRecent.restart();
            mochi.wake();
        }
    }

    // Contraseña mal: triste y se sacude
    onFailStateChanged: {
        if (failState > 0) {
            mochi.wake();
            mochi.react(failState === 2 ? "dizzy" : "sad", 1800);
            shake.restart();
        }
    }

    // Contraseña bien: se alegra, da un bote y se lanza hacia abajo (sale en el escritorio)
    onUnlockingChanged: {
        if (!unlocking)
            return;
        mochi.wake();
        mochi.react("happy", 900);
        riseTarget = 1.3;
        diveAway.restart();
    }

    Timer {
        id: typingRecent

        interval: 1600
    }

    Timer {
        id: diveAway

        interval: 260
        onTriggered: {
            root.riseTarget = -0.5;
            mochi.kick(1.6, -1.6);
        }
    }

    // Sacudida (no): unos meneos de lado a lado
    SequentialAnimation {
        id: shake

        loops: 3

        NumberAnimation {
            target: root
            property: "cx"
            to: root.homeX - 9
            duration: 70
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: root
            property: "cx"
            to: root.homeX + 9
            duration: 110
            easing.type: Easing.InOutQuad
        }
        NumberAnimation {
            target: root
            property: "cx"
            to: root.homeX
            duration: 70
            easing.type: Easing.InQuad
        }
    }

    // Bloq Mayús: da botecitos para que lo veas
    Timer {
        running: root.capsLock && root.ready
        repeat: true
        interval: 1300
        onTriggered: {
            mochi.kick(-0.8, 2.2);
            root.riseV += 2.2;
            mochi.react("surprised", 700);
        }
    }

    // Poca batería: mira preocupado al indicador de batería de vez en cuando
    Timer {
        running: root.lowBattery && root.ready && !root.typing
        repeat: true
        interval: 9000
        triggeredOnStart: true
        onTriggered: {
            mochi.wake();
            mochi.react("sorry", 2200);
            glance.restart();
        }
    }

    Timer {
        id: glance

        interval: 2200
    }

    FrameAnimation {
        running: root.visible
        onTriggered: {
            const dt = Math.min(frameTime, 1 / 30);
            root.riseV += (-90 * (root.rise - root.riseTarget) - 11 * root.riseV) * dt;
            root.rise += root.riseV * dt;
        }
    }

    // ---- Mirada: al ratón; escribiendo, hacia otro lado; con Bloq Mayús, al campo
    HoverHandler {
        id: hover

        onPointChanged: mochi.wake()
    }

    function aim(tx: real, ty: real): void {
        const dx = tx - cx, dy = ty - mochi.centerWorldY, d = Math.hypot(dx, dy);
        lookX = d < 20 ? 0 : dx / (d + 60);
        lookY = d < 20 ? 0 : dy / (d + 60);
    }

    Timer {
        running: root.visible
        repeat: true
        interval: 60
        onTriggered: {
            if (root.capsLock)
                root.aim(root.fieldPos.x, root.fieldPos.y);
            else if (glance.running)
                root.aim(root.batteryPos.x, root.batteryPos.y);
            else if (hover.hovered)
                root.aim(hover.point.position.x, hover.point.position.y);
            else
                root.aim(root.cx, root.height * 0.3);
        }
    }

    // ---- Cuerpo: mismo shader que en el escritorio, fundido con el borde de abajo de la pantalla
    Item {
        anchors.fill: parent
        opacity: root.bodyOpacity
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            blurMax: 15
            shadowColor: Qt.alpha(root.shadowColor, 0.7)
        }

        ShaderEffect {
            id: bodyFx

            readonly property real half: 140

            x: mochi.x + mochi.width / 2 - half
            y: mochi.y + mochi.height / 2 - half
            width: 2 * half
            height: 2 * half

            property vector2d size: Qt.vector2d(width, height)
            property vector4d body: Qt.vector4d(half, half, mochi.bodyRx, mochi.bodyRy)
            property vector4d mass: Qt.vector4d(half + mochi.massX - mochi.width / 2, half + mochi.massY - mochi.height / 2, mochi.massR, 0)
            property vector4d tail: Qt.vector4d(half + mochi.tailX - mochi.width / 2, half + mochi.tailY - mochi.height / 2, mochi.tailR, 0)
            property vector4d wobA: mochi.wobA
            property vector4d wobB: mochi.wobB
            // "interior" = la pantalla entera: se funde con su borde de abajo
            property vector4d frame: Qt.vector4d(-x, -y, root.width - x, root.height - y)
            property color color: root.bodyColor
            property vector4d view: Qt.vector4d(x, y, 1, 0)   // sin textura del marco
            property var edge: noEdge
            property real blobK: 26
            property real frameK: root.smoothing
            property real bandOnly: 0

            fragmentShader: Qt.resolvedUrl("mochi.frag.qsb")
        }
    }

    // (el shader pide una textura del marco; aquí no hay marco)
    Rectangle {
        id: noEdge

        width: 1
        height: 1
        visible: false
        layer.enabled: true
    }

    Blob {
        id: mochi

        // centro: asoma (2·ry − 12)·rise px por encima del borde de abajo
        readonly property real centerWorldY: root.height - (2 * root.ry - 12) * root.rise + root.ry

        x: root.cx - width / 2
        y: centerWorldY - height / 2
        worldX: root.cx
        worldY: centerWorldY
        bodyColor: root.bodyColor
        drowsy: root.drowsy
        mood: root.typing && !root.capsLock ? "squint" : "idle"
        lookX: root.lookX
        lookY: root.lookY
        clipRect: Qt.rect(-x, -y, root.width, root.height)
    }
}
