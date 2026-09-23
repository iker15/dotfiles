import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// Mochi en la pantalla de bloqueo (lo carga caelestia/modules/lock/LockSurface.qml).
// Llega por el borde de abajo, donde se metió el Mochi del escritorio al bloquear, y salta a la
// tarjeta del bloqueo, que aquí es su medio: se queda colgando de su borde de abajo, bajo la
// contraseña, y a ratos se pasea por su contorno. Pegado a la tarjeta, su cuerpo lo dibuja
// LockBody.qml dentro de la capa de la propia tarjeta (mismo material y una sola sombra).
// Solo ojos y cuerpo; aquí no escucha ni obedece.
// - Mientras escribes la contraseña se mete en la tarjeta y aprieta los ojos: no mira.
// - Con Bloq Mayús se convierte en una flecha ⇪ y da botes, mirando al campo.
// - Si fallas, se pone triste y se sacude; si aciertas, se hace un corazón, se descuelga, cae
//   al borde de abajo y se va buceando al escritorio.
// - De madrugada tiene sueño (cabezadas, se queda frito abajo); mover el ratón lo despierta.
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
    property rect card: Qt.rect(width / 2 - 300, height / 2 - 170, 600, 340)
    property real cardRadius: 40
    property point fieldPos: Qt.point(width / 2, height / 2)     // campo de la contraseña
    property point batteryPos: Qt.point(width * 0.8, height / 2) // indicador de batería

    // Posición y sueño que dejó el Mochi del escritorio al bloquear
    property real homeX: width * 0.7
    property real drowsy: 0

    readonly property real rx: 32 * 1.45
    readonly property real ry: 29 * 1.45 * 0.95
    readonly property real embed: 12

    // Fases: bottom (asomando por el borde de abajo) · jump (saltando a la tarjeta) · card
    // (pegado a la tarjeta) · drop (cayendo al desbloquear)
    property string phase: "bottom"
    readonly property bool glued: phase === "card"

    // Posición del centro de Mochi (coordenadas de la pantalla)
    property real cx: homeX
    property real cy: height + 2 * ry
    property real vy: 0

    // Cuánto asoma de su medio: 0 = nada, 1 = como en el escritorio (muelle con rebotes)
    property real vis: -0.4
    property real visV: 0
    property real visTarget: -0.4

    // En la tarjeta: sitio a lo largo de su contorno (px), y a dónde va
    property real t: 0
    property real tFrom: 0
    property real tTo: 0
    property real tU: 1
    property real tDur: 1
    property real shake: 0               // meneo de lado a lado (no)

    // Forma que imita (ver mochi.frag): "" · gear · claude · heart · star · arrow
    readonly property string shapeName: capsLock && ready && !unlocking ? "arrow" : heartShape.running ? "heart" : ""
    readonly property int shapeId: ({
            "gear": 1,
            "claude": 2,
            "heart": 3,
            "star": 4,
            "arrow": 5
        })[shapeName] ?? 0
    property int lastShape: 0
    property real morph: shapeId ? 1 : 0
    onShapeIdChanged: if (shapeId) lastShape = shapeId
    Behavior on morph {
        NumberAnimation {
            duration: 380
            easing.type: Easing.OutBack
        }
    }

    property real lookX: 0
    property real lookY: 0

    readonly property bool typing: (pam?.buffer?.length ?? 0) > 0 && typingRecent.running
    readonly property bool lowBattery: UPower.displayDevice.isLaptopBattery && UPower.displayDevice.percentage < 0.15 && UPower.displayDevice.state !== UPowerDeviceState.Charging

    // Lo que usa LockBody (el cuerpo dentro de la capa de la tarjeta)
    readonly property alias blob: mochi
    readonly property alias noEdgeTex: noEdge
    readonly property vector4d shapeVec: Qt.vector4d(lastShape, Math.max(0, morph), 0, 44)

    anchors.fill: parent

    // ---- Contorno de la tarjeta: punto y normal hacia fuera a una distancia t (desde la
    // esquina de abajo a la izquierda, hacia la derecha por abajo y en sentido antihorario)
    function cardTrack(): var {
        const R = Math.min(cardRadius, card.width / 2, card.height / 2);
        const w = card.width - 2 * R, h = card.height - 2 * R, q = R * Math.PI / 2;
        return {
            R: R,
            w: w,
            h: h,
            q: q,
            len: 2 * w + 2 * h + 4 * q
        };
    }

    function cardPoint(d: real): var {
        const k = cardTrack(), X = card.x, Y = card.y, W = card.width, H = card.height, R = k.R;
        d = ((d % k.len) + k.len) % k.len;
        const arc = (ax, ay, a) => ({
                    x: ax + R * Math.cos(a),
                    y: ay + R * Math.sin(a),
                    nx: Math.cos(a),
                    ny: Math.sin(a)
                });
        if (d < k.w)
            return {
                x: X + R + d,
                y: Y + H,
                nx: 0,
                ny: 1
            };
        d -= k.w;
        if (d < k.q)
            return arc(X + W - R, Y + H - R, Math.PI / 2 - d / R);
        d -= k.q;
        if (d < k.h)
            return {
                x: X + W,
                y: Y + H - R - d,
                nx: 1,
                ny: 0
            };
        d -= k.h;
        if (d < k.q)
            return arc(X + W - R, Y + R, -d / R);
        d -= k.q;
        if (d < k.w)
            return {
                x: X + W - R - d,
                y: Y,
                nx: 0,
                ny: -1
            };
        d -= k.w;
        if (d < k.q)
            return arc(X + R, Y + R, -Math.PI / 2 - d / R);
        d -= k.q;
        if (d < k.h)
            return {
                x: X,
                y: Y + R + d,
                nx: -1,
                ny: 0
            };
        d -= k.h;
        return arc(X + R, Y + H - R, Math.PI - d / R);
    }

    // Su sitio: colgando del borde de abajo de la tarjeta, bajo la contraseña (algo a la derecha)
    function homeT(): real {
        return card.width * 0.66 - cardTrack().R;
    }

    function smooth(x: real): real {
        x = Math.max(0, Math.min(1, x));
        return x * x * x * (x * (6 * x - 15) + 10);
    }

    // Va (deslizándose, fluido: es su medio) a otro punto del contorno
    function glideTo(d: real): void {
        const k = cardTrack();
        let diff = ((d - t) % k.len + k.len) % k.len;
        if (diff > k.len / 2)
            diff -= k.len;
        tFrom = t;
        tTo = t + diff;
        tU = 0;
        tDur = 0.9 + Math.abs(diff) / 260;
        const n = cardPoint(t);
        if (n.ny !== 0)
            mochi.kick(1.8, -1.2);
        else
            mochi.kick(-1.2, 1.8);
    }

    // ---- Estado que dejó el Mochi del escritorio
    FileView {
        id: stateFile

        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/mochi-lock.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            if (root.phase !== "bottom" || root.ready)
                return;
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

    // Al irse, deja dicho dónde cae (para que el del escritorio salga justo ahí)
    function tellDesktop(): void {
        stateFile.setText(JSON.stringify({
            x: Math.round(cx),
            drowsy: drowsy,
            dozing: false
        }));
    }

    // ---- Qué quiere hacer según lo que pasa
    function updateTarget(): void {
        if (unlocking || phase === "drop" || phase === "jump")
            return;
        if (!ready)
            visTarget = -0.4;
        else if (capsLock)
            visTarget = 1.12;
        else if (typing)
            visTarget = phase === "card" ? 0.3 : 0.78;   // se mete en la tarjeta / se agacha
        else
            visTarget = 1;
    }

    onReadyChanged: {
        updateTarget();
        if (!ready)
            return;
        if (!mochi.dozing) {
            mochi.kick(-1.4, 3.2);
            mochi.react(drowsy > 0.6 ? "yawn" : "excited", 1300);
        }
        toCard.restart();
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
    onPhaseChanged: updateTarget()

    Connections {
        target: root.pam ?? null
        ignoreUnknownSignals: true

        function onBufferChanged(): void {
            typingRecent.restart();
            mochi.wake();
        }
    }

    onFailStateChanged: {
        if (failState > 0) {
            mochi.wake();
            mochi.react(failState === 2 ? "dizzy" : "sad", 1800);
            shakeAnim.restart();
        }
    }

    // Contraseña bien: corazón, y se descuelga (o, si estaba abajo, se zambulle)
    onUnlockingChanged: {
        if (!unlocking)
            return;
        mochi.wake();
        mochi.react("happy", 900);
        heartShape.restart();
        if (phase === "card" || phase === "jump") {
            const n = cardPoint(t);
            phase = "drop";
            vy = n.ny < 0 ? -300 : 0;   // desde arriba, un saltito antes de caer
        } else {
            visTarget = 1.3;
            diveAway.restart();
        }
        tellDesktop();
    }

    Timer {
        id: typingRecent

        interval: 1600
    }

    Timer {
        id: heartShape

        interval: 650
    }

    // De abajo a la tarjeta al poco de llegar (si está frito, cuando lo despiertes)
    Timer {
        id: toCard

        interval: 1500
        onTriggered: {
            if (root.phase !== "bottom" || !root.ready || root.unlocking)
                return;
            if (mochi.dozing) {
                restart();
                return;
            }
            root.jump();
        }
    }

    Timer {
        id: diveAway

        interval: 260
        onTriggered: {
            root.visTarget = -0.5;
            mochi.kick(1.6, -1.6);
        }
    }

    // Paseos por el contorno de la tarjeta (y vuelta a su sitio)
    Timer {
        running: root.glued && !root.typing && !root.capsLock && !root.unlocking && !mochi.dozing
        repeat: true
        interval: 16000
        onTriggered: {
            interval = 12000 + Math.random() * 14000;
            const k = root.cardTrack(), home = root.homeT();
            const away = Math.abs(root.t - home) > 5;
            root.glideTo(away ? home : home + (Math.random() < 0.5 ? -1 : 1) * (0.25 + Math.random() * 0.45) * k.len * 0.5);
        }
    }

    NumberAnimation {
        id: shakeAnim

        target: root
        property: "shake"
        from: 0
        to: 1
        duration: 700
    }

    // Bloq Mayús: botecitos para que lo veas
    Timer {
        running: root.capsLock && root.ready && !root.unlocking
        repeat: true
        interval: 1300
        onTriggered: {
            mochi.kick(-0.8, 2.2);
            root.visV += 2.2;
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

    // ---- Salto de abajo a la tarjeta
    property real jx0: 0
    property real jy0: 0
    property real jx1: 0
    property real jy1: 0
    property real jU: 0

    function jump(): void {
        t = homeT();
        tU = 1;
        const p = cardPoint(t);
        jx0 = cx;
        jy0 = cy;
        jx1 = p.x;
        jy1 = p.y + (ry - embed);   // colgando, asomando del todo
        jU = 0;
        mochi.kick(-1.2, 2.8);      // coge impulso
        phase = "jump";
    }

    FrameAnimation {
        running: root.visible
        onTriggered: {
            const dt = Math.min(frameTime, 1 / 30);
            // muelle de cuánto asoma
            root.visV += (-90 * (root.vis - root.visTarget) - 11 * root.visV) * dt;
            root.vis += root.visV * dt;
            const sh = Math.sin(root.shake * Math.PI * 6) * 9 * (1 - root.shake);

            if (root.phase === "bottom") {
                // centro: asoma (2·ry − 12)·vis px por encima del borde de abajo (con forma, entero)
                const v = (2 * root.ry - root.embed) * root.vis * (1 - root.morph) + (root.ry + 50) * root.morph;
                root.cy = root.height - v + root.ry;
                root.cx = root.homeX + sh;
            } else if (root.phase === "jump") {
                root.jU = Math.min(1, root.jU + dt / 0.55);
                const u = root.jU, e = 1 - Math.pow(1 - u, 3);
                root.cx = root.jx0 + (root.jx1 - root.jx0) * root.smooth(u);
                root.cy = root.jy0 + (root.jy1 - root.jy0) * e - Math.sin(Math.PI * u) * 40;
                if (u >= 1) {
                    root.vis = 1;
                    root.visV = 0;
                    root.phase = "card";
                    mochi.kick(2.4, -2.2);   // se aplasta contra la tarjeta y se pega
                    mochi.react("happy", 700);
                }
            } else if (root.phase === "card") {
                if (root.tU < 1) {
                    root.tU = Math.min(1, root.tU + dt / root.tDur);
                    root.t = root.tFrom + (root.tTo - root.tFrom) * root.smooth(root.tU);
                }
                const p = root.cardPoint(root.t), rn = Math.abs(p.nx) * root.rx + Math.abs(p.ny) * root.ry;
                // con forma, se separa lo justo para que se vea entera
                const v = (2 * rn - root.embed) * root.vis * (1 - root.morph) + (rn + 50) * root.morph;
                root.cx = p.x + p.nx * (v - rn) - p.ny * sh;
                root.cy = p.y + p.ny * (v - rn) + p.nx * sh;
            } else if (root.phase === "drop") {
                root.vy += 2600 * dt;
                root.cy += root.vy * dt;
                const floorY = root.height - (2 * root.ry - root.embed) + root.ry;
                if (root.cy >= floorY) {
                    root.cy = floorY;
                    root.homeX = root.cx;
                    root.vis = 1;
                    root.visV = 0;
                    root.phase = "bottom";
                    mochi.splat(900, false);
                    root.tellDesktop();
                    diveAway.restart();
                }
            }
        }
    }

    // ---- Mirada: al ratón; con Bloq Mayús o escribiendo, al campo; con poca batería, a la batería
    HoverHandler {
        id: hover

        onPointChanged: mochi.wake()
    }

    function aim(tx: real, ty: real): void {
        const dx = tx - cx, dy = ty - cy, d = Math.hypot(dx, dy);
        lookX = d < 20 ? 0 : dx / (d + 60);
        lookY = d < 20 ? 0 : dy / (d + 60);
    }

    Timer {
        running: root.visible
        repeat: true
        interval: 60
        onTriggered: {
            if (root.capsLock || (root.glued && root.typing))
                root.aim(root.fieldPos.x, root.fieldPos.y);
            else if (glance.running)
                root.aim(root.batteryPos.x, root.batteryPos.y);
            else if (hover.hovered)
                root.aim(hover.point.position.x, hover.point.position.y);
            else
                root.aim(root.cx, root.height * 0.3);
        }
    }

    // ---- Cuerpo cuando no está pegado a la tarjeta: su propia capa, fundido con el borde de
    // abajo de la pantalla (mismo material que la tarjeta)
    Item {
        anchors.fill: parent
        visible: !root.glued
        opacity: root.bodyOpacity
        layer.enabled: visible
        layer.effect: MultiEffect {
            shadowEnabled: true
            blurMax: 15
            shadowColor: Qt.alpha(root.shadowColor, 0.7)
        }

        ShaderEffect {
            readonly property real half: 140

            x: root.cx - half
            y: root.cy - half
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
            property vector4d shape: root.shapeVec
            property vector4d card: Qt.vector4d(0, 0, 0, 0)
            property real cardR: 0
            property real cardOn: 0
            property real baseAlpha: 1

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

        x: root.cx - width / 2
        y: root.cy - height / 2
        worldX: root.cx
        worldY: root.cy
        bodyColor: root.bodyColor
        drowsy: root.drowsy
        mood: root.typing && !root.capsLock ? "squint" : "idle"
        lookX: root.lookX
        lookY: root.lookY
        clipRect: Qt.rect(-x, -y, root.width, root.height)
    }
}
