import QtQuick

// Mochi: gota negra blanda con ojitos blancos. Mira hacia (lookX, lookY) en [-1, 1].
// El cuerpo es un fluido: al moverlo se queda atrás, se estira y tiembla al soltarlo.
Item {
    id: root

    property string mood: "idle"   // idle, listening, thinking, working, talking, happy, sad
    property bool dragging: false
    property bool falling: false   // cayendo deprisa (cara de susto)
    property bool sleepy: false    // escondido y sin nadie cerca
    property real lookX: 0
    property real lookY: 0
    property bool blinking: false
    property real bob: 0
    property bool light: false     // cuerpo blanco (para fondos oscuros)

    // Colores: cuerpo y detalles se invierten según el fondo
    property color bodyColor: light ? "#f2f1ec" : "#0b0b0b"
    property color ink: light ? "#141414" : "white"

    Behavior on bodyColor {
        ColorAnimation {
            duration: 450
        }
    }
    Behavior on ink {
        ColorAnimation {
            duration: 450
        }
    }

    // Posición global de Mochi: si cambia, el fluido lo nota por inercia
    property real worldX: 0
    property real worldY: 0

    readonly property real u: 1.45                 // escala respecto al Mochi original
    readonly property real rx: 32 * u              // semiejes del cuerpo en reposo
    readonly property real ry: 29 * u

    // Estado de la simulación (lo lee la cara)
    property real ox: 0     // desplazamiento de la masa respecto al punto de agarre
    property real oy: 0
    property real sx: 1     // escala del cuerpo (muelle hacia la de reposo/agarre)
    property real sy: 1

    // Caras: una reacción puntual manda sobre todo lo demás
    property string reaction: ""     // squint, dizzy, happy, surprised
    property string idleExpr: ""     // wink, smile, curious
    readonly property string face: reaction || (dragging ? "held" : falling ? "surprised" : mood !== "idle" ? mood : sleepy ? "sleepy" : idleExpr)

    implicitWidth: 2 * rx + 8
    implicitHeight: 2 * ry + 8

    function poke(): void {
        sim.poke();
        react("happy", 900);
    }

    // Golpe contra el suelo o una pared: se aplasta en esa dirección
    function splat(strength: real, horizontal: bool): void {
        const s = Math.min(strength, 1800) * 0.006;
        if (horizontal) {
            sim.svx -= s;
            sim.svy += s * 0.7;
        } else {
            sim.svy -= s;
            sim.svx += s * 0.7;
        }
    }

    function react(name: string, ms: int): void {
        reaction = name;
        reactionTimer.interval = ms;
        reactionTimer.restart();
    }

    Timer {
        id: reactionTimer

        onTriggered: root.reaction = ""
    }

    QtObject {
        id: sim

        readonly property int n: 16
        property var w: new Array(16).fill(0)       // deformación radial de cada nodo (fracción del radio)
        property var wv: new Array(16).fill(0)
        property real vx: 0
        property real vy: 0
        property real svx: 0
        property real svy: 0
        property real lastX: NaN
        property real lastY: NaN
        property real t: 0

        function step(dt: real): void {
            dt = Math.min(dt, 1 / 30);
            t += dt;

            // Cuánto se ha movido Mochi desde el último frame
            let mx = isNaN(lastX) ? 0 : root.worldX - lastX;
            let my = isNaN(lastY) ? 0 : root.worldY - lastY;
            lastX = root.worldX;
            lastY = root.worldY;
            if (Math.abs(mx) + Math.abs(my) > 400)   // saltos (arranque, cambio de pantalla)
                mx = my = 0;
            mx = Math.max(-25, Math.min(25, mx));
            my = Math.max(-25, Math.min(25, my));

            // Inercia: la masa se queda atrás
            let ox = root.ox - mx * 0.75, oy = root.oy - my * 0.75;

            // Muelle de la masa hacia el centro (poco amortiguado → bambolea)
            const k = 170, c = 9;
            vx += (-k * ox - c * vx) * dt;
            vy += (-k * oy - c * vy) * dt;
            ox += vx * dt;
            oy += vy * dt;
            const lim = root.rx * 0.55, m = Math.hypot(ox, oy);
            if (m > lim) {
                ox *= lim / m;
                oy *= lim / m;
            }

            // Ondas en la superficie: cada nodo es un muelle unido a sus vecinos
            const kw = 260, cw = 7, kc = 140, g = 0.045;
            const fx = Math.max(-12, Math.min(12, mx)), fy = Math.max(-12, Math.min(12, my));
            const nw = w.slice(), nv = wv.slice();
            for (let i = 0; i < n; i++) {
                const a = 2 * Math.PI * i / n;
                const lap = w[(i + 1) % n] + w[(i + n - 1) % n] - 2 * w[i];
                nv[i] += (-kw * w[i] - cw * wv[i] + kc * lap) * dt;
                // El movimiento empuja el fluido hacia atrás: se aplasta delante y se abomba detrás
                nv[i] -= (fx * Math.cos(a) + fy * Math.sin(a)) * g;
                nw[i] = Math.max(-0.35, Math.min(0.35, w[i] + nv[i] * dt));
            }
            w = nw;
            wv = nv;

            // Escala: aplastarse al respirar, estirarse al cogerlo
            const tsx = root.dragging ? 0.93 : 1 + root.bob * 0.04;
            const tsy = root.dragging ? 1.1 : 1 - root.bob * 0.04;
            const ks = 320, cs = 13;
            svx += (-ks * (root.sx - tsx) - cs * svx) * dt;
            svy += (-ks * (root.sy - tsy) - cs * svy) * dt;
            root.sx = Math.max(0.55, Math.min(1.5, root.sx + svx * dt));
            root.sy = Math.max(0.55, Math.min(1.5, root.sy + svy * dt));

            root.ox = ox;
            root.oy = oy;
            canvas.requestPaint();
        }

        // Empujoncito (al hacerle clic)
        function poke(): void {
            for (let i = 0; i < n; i++)
                wv[i] += (Math.random() - 0.5) * 1.2 - 0.6;
            svy -= 2;
            svx += 2;
        }
    }

    FrameAnimation {
        running: root.visible
        onTriggered: sim.step(frameTime)
    }

    SequentialAnimation on bob {
        loops: Animation.Infinite
        running: !root.dragging

        NumberAnimation {
            to: root.mood === "working" ? 1 : 0.6
            duration: root.mood === "working" ? 220 : root.sleepy ? 2200 : 1100
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            to: 0
            duration: root.mood === "working" ? 220 : root.sleepy ? 2200 : 1100
            easing.type: Easing.InOutSine
        }
    }

    // Cuerpo: curva suave que pasa por los nodos. Se aplasta hacia abajo (apoyado en el suelo).
    Canvas {
        id: canvas

        anchors.centerIn: parent
        width: root.width + 2 * root.rx
        height: root.height + 2 * root.rx

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const cx = width / 2, cy = height / 2 + root.ry * (1 - root.sy);
            const n = sim.n, m = Math.hypot(root.ox, root.oy);
            const ux = m > 0.01 ? root.ox / m : 0, uy = m > 0.01 ? root.oy / m : 0;
            const pts = [];
            for (let i = 0; i < n; i++) {
                const a = 2 * Math.PI * i / n;
                const ca = Math.cos(a), sa = Math.sin(a);
                // Ondulación lenta, como una gota de lava
                const idle = 0.012 * Math.sin(sim.t * 1.7 + i * 1.3) + 0.008 * Math.sin(sim.t * 2.9 - i * 2.1);
                const r = 1 + sim.w[i] + idle;
                // La parte de atrás sigue a la masa; la de delante se queda donde la agarras
                const d = ca * ux + sa * uy;
                const back = (1 + d) / 2;
                const thin = 1 - 0.18 * (m / root.rx) * (1 - d * d);   // se adelgaza al estirarse
                pts.push([cx + ca * root.rx * root.sx * r * thin + root.ox * back, cy + sa * root.ry * root.sy * r * thin + root.oy * back]);
            }
            ctx.beginPath();
            const mid = (p, q) => [(p[0] + q[0]) / 2, (p[1] + q[1]) / 2];
            let s = mid(pts[n - 1], pts[0]);
            ctx.moveTo(s[0], s[1]);
            for (let i = 0; i < n; i++) {
                const e = mid(pts[i], pts[(i + 1) % n]);
                ctx.quadraticCurveTo(pts[i][0], pts[i][1], e[0], e[1]);
            }
            ctx.closePath();
            ctx.fillStyle = root.bodyColor;
            ctx.fill();
        }
    }

    // Cara: va con la masa, un poco por detrás
    Item {
        id: face

        // Miradas que no dependen del ratón
        property real autoX: 0
        property real autoY: 0
        property bool autoLook: false

        width: 2 * root.rx * root.sx
        height: 2 * root.ry * root.sy
        x: (root.width - width) / 2 + root.ox * 0.5
        y: (root.height - height) / 2 + root.oy * 0.5 + root.ry * (1 - root.sy)
        rotation: root.face === "curious" ? 9 : root.face === "dizzy" ? 6 * Math.sin(sim.t * 7) : 0

        Behavior on rotation {
            enabled: root.face !== "dizzy"

            NumberAnimation {
                duration: 350
                easing.type: Easing.OutBack
            }
        }

        // Ojos
        Repeater {
            model: [-1, 1]

            Item {
                id: eye

                required property int modelData

                readonly property string f: root.face
                readonly property string shape: ["happy", "squint", "dizzy", "sleepy"].includes(f) ? f : "dot"
                // Tamaño y apertura según la cara
                readonly property real size: f === "surprised" ? 1.4 : f === "held" ? 1.25 : f === "listening" ? 1.12 : f === "sad" ? 0.85 : 1
                readonly property real openTarget: {
                    if (root.blinking || (f === "wink" && modelData < 0))
                        return 0;
                    if (f === "working")
                        return 0.5;
                    if (f === "sad")
                        return 0.7;
                    return 1;
                }
                property real open: openTarget
                property real lx: face.autoLook ? face.autoX : f === "thinking" ? 0.6 : f === "listening" || f === "sad" ? 0 : root.lookX
                property real ly: face.autoLook ? face.autoY : f === "thinking" ? -0.8 : f === "listening" ? -0.5 : f === "sad" ? 0.7 : root.lookY

                x: face.width / 2 + modelData * 11 * root.u - width / 2 + lx * 6 * root.u
                y: face.height * 0.42 - height / 2 + ly * 5 * root.u
                width: 16 * root.u
                height: 16 * root.u

                Behavior on lx {
                    NumberAnimation {
                        duration: 140
                    }
                }
                Behavior on ly {
                    NumberAnimation {
                        duration: 140
                    }
                }
                Behavior on open {
                    NumberAnimation {
                        duration: 70
                    }
                }

                Canvas {
                    id: eyeCanvas

                    property real d: 7 * root.u * eye.size

                    anchors.fill: parent
                    onDChanged: requestPaint()

                    Behavior on d {
                        NumberAnimation {
                            duration: 160
                            easing.type: Easing.OutBack
                        }
                    }

                    // Mareo: la espiral da vueltas
                    RotationAnimation on rotation {
                        running: eye.shape === "dizzy"
                        loops: Animation.Infinite
                        from: 0
                        to: 360 * eye.modelData
                        duration: 700
                    }

                    Connections {
                        target: eye

                        function onShapeChanged(): void {
                            eyeCanvas.rotation = 0;
                            eyeCanvas.requestPaint();
                        }
                        function onOpenChanged(): void {
                            eyeCanvas.requestPaint();
                        }
                    }

                    Connections {
                        target: root

                        function onInkChanged(): void {
                            eyeCanvas.requestPaint();
                        }
                    }

                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        ctx.fillStyle = root.ink;
                        ctx.strokeStyle = root.ink;
                        ctx.lineWidth = 2.2 * root.u;
                        ctx.lineCap = "round";
                        ctx.lineJoin = "round";
                        const cx = width / 2, cy = height / 2, r = d / 2;
                        ctx.beginPath();
                        switch (eye.shape) {
                        case "happy":      // ^
                            ctx.arc(cx, cy + r * 0.6, r * 1.05, Math.PI * 1.15, Math.PI * 1.85);
                            ctx.stroke();
                            break;
                        case "sleepy":     // ‿ ojos cerrados
                            ctx.arc(cx, cy - r * 0.5, r * 1.05, Math.PI * 0.15, Math.PI * 0.85);
                            ctx.stroke();
                            break;
                        case "squint": {   // > <
                            const s = eye.modelData < 0 ? 1 : -1;
                            ctx.moveTo(cx - s * r * 0.8, cy - r * 0.9);
                            ctx.lineTo(cx + s * r * 0.8, cy);
                            ctx.lineTo(cx - s * r * 0.8, cy + r * 0.9);
                            ctx.stroke();
                            break;
                        }
                        case "dizzy":      // @
                            for (let a = 0; a <= Math.PI * 4; a += 0.25) {
                                const rr = r * 1.1 * a / (Math.PI * 4);
                                ctx.lineTo(cx + Math.cos(a) * rr, cy + Math.sin(a) * rr);
                            }
                            ctx.lineWidth = 1.6 * root.u;
                            ctx.stroke();
                            break;
                        default: {         // ● (parpadea aplastándose)
                            const h = Math.max(2.2 * root.u, d * eye.open);
                            ctx.ellipse(cx - r, cy - h / 2, d, h);
                            ctx.fill();
                        }
                        }
                    }
                }
            }
        }

        // Mofletes
        Repeater {
            model: [-1, 1]

            Rectangle {
                required property int modelData

                readonly property bool on: ["happy", "smile", "held"].includes(root.face)

                x: face.width / 2 + modelData * 19 * root.u - width / 2
                y: face.height * 0.56
                width: 8 * root.u
                height: 4.5 * root.u
                radius: height / 2
                color: "#ff7fa3"
                opacity: on ? 0.55 : 0
                scale: on ? 1 : 0.4

                Behavior on opacity {
                    NumberAnimation {
                        duration: 250
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: 250
                        easing.type: Easing.OutBack
                    }
                }
            }
        }

        // Boca
        Item {
            id: mouth

            readonly property string kind: {
                const f = root.face;
                if (f === "talking")
                    return "talk";
                if (f === "surprised" || f === "held" || f === "dizzy")
                    return "o";
                if (f === "happy" || f === "smile")
                    return "smile";
                if (f === "sad")
                    return "frown";
                return "";
            }

            anchors.horizontalCenter: parent.horizontalCenter
            y: face.height * 0.64
            width: 14 * root.u
            height: 8 * root.u

            Rectangle {
                visible: mouth.kind === "talk" || mouth.kind === "o"
                anchors.horizontalCenter: parent.horizontalCenter
                width: (mouth.kind === "o" ? 5 : 7) * root.u
                height: mouth.kind === "o" ? width : 4 * root.u
                radius: width / 2
                color: root.ink

                SequentialAnimation on height {
                    loops: Animation.Infinite
                    running: mouth.kind === "talk"

                    NumberAnimation {
                        to: 6 * root.u
                        duration: 120
                    }
                    NumberAnimation {
                        to: 2 * root.u
                        duration: 120
                    }
                }
            }

            Canvas {
                id: arcMouth

                visible: mouth.kind === "smile" || mouth.kind === "frown"
                anchors.fill: parent

                Connections {
                    target: mouth

                    function onKindChanged(): void {
                        arcMouth.requestPaint();
                    }
                }

                Connections {
                    target: root

                    function onInkChanged(): void {
                        arcMouth.requestPaint();
                    }
                }

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    ctx.strokeStyle = root.ink;
                    ctx.lineWidth = 2 * root.u;
                    ctx.lineCap = "round";
                    ctx.beginPath();
                    const r = 4 * root.u;
                    if (mouth.kind === "smile")
                        ctx.arc(width / 2, 0, r, Math.PI * 0.2, Math.PI * 0.8);
                    else
                        ctx.arc(width / 2, height, r, Math.PI * 1.2, Math.PI * 1.8);
                    ctx.stroke();
                }
            }
        }

        // Zzz mientras duerme escondido
        Text {
            id: zzz

            visible: root.face === "sleepy"
            x: face.width * 0.72
            text: "z"
            font.pixelSize: 11 * root.u
            font.bold: true
            color: root.ink

            NumberAnimation on y {
                loops: Animation.Infinite
                running: zzz.visible
                from: face.height * 0.2
                to: -face.height * 0.15
                duration: 1800
            }
            SequentialAnimation on opacity {
                loops: Animation.Infinite
                running: zzz.visible

                NumberAnimation {
                    from: 0
                    to: 0.9
                    duration: 500
                }
                NumberAnimation {
                    to: 0
                    duration: 1300
                }
            }
        }

        // Puntitos al pensar / trabajar
        Row {
            visible: root.mood === "thinking" || root.mood === "working"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.top
            anchors.bottomMargin: 3
            spacing: 5

            Repeater {
                model: 3

                Rectangle {
                    id: dot

                    required property int index

                    width: 6
                    height: 6
                    radius: 3
                    color: root.ink
                    opacity: 0.2

                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: root.mood === "thinking" || root.mood === "working"

                        PauseAnimation {
                            duration: dot.index * 150
                        }
                        NumberAnimation {
                            to: 1
                            duration: 220
                        }
                        NumberAnimation {
                            to: 0.2
                            duration: 420
                        }
                        PauseAnimation {
                            duration: (2 - dot.index) * 150
                        }
                    }
                }
            }
        }
    }

    // Mirar a un lado y a otro
    SequentialAnimation {
        id: lookAround

        PropertyAction {
            target: face
            property: "autoX"
            value: -0.9
        }
        PropertyAction {
            target: face
            property: "autoLook"
            value: true
        }
        PauseAnimation {
            duration: 650
        }
        PropertyAction {
            target: face
            property: "autoX"
            value: 0.9
        }
        PauseAnimation {
            duration: 650
        }
        PropertyAction {
            target: face
            property: "autoX"
            value: 0
        }
        PauseAnimation {
            duration: 250
        }
        PropertyAction {
            target: face
            property: "autoLook"
            value: false
        }
    }

    // Gestos al azar cuando está tranquilo
    Timer {
        running: root.visible && root.mood === "idle" && !root.dragging && !root.sleepy
        repeat: true
        interval: 6000
        onTriggered: {
            interval = 4000 + Math.random() * 7000;
            const pick = ["lookaround", "wink", "smile", "curious", "doubleblink", "wiggle"][Math.floor(Math.random() * 6)];
            if (pick === "lookaround") {
                lookAround.restart();
            } else if (pick === "doubleblink") {
                root.blinking = true;
                unblink.restart();
                doubleBlink.restart();
            } else if (pick === "wiggle") {
                sim.poke();
            } else {
                root.idleExpr = pick;
                clearIdle.interval = pick === "wink" ? 450 : 1600;
                clearIdle.restart();
            }
        }
    }

    Timer {
        id: clearIdle

        onTriggered: root.idleExpr = ""
    }

    Timer {
        id: doubleBlink

        interval: 260
        onTriggered: {
            root.blinking = true;
            unblink.restart();
        }
    }

    Timer {
        running: root.visible && !root.sleepy
        repeat: true
        interval: 3000
        onTriggered: {
            root.blinking = true;
            unblink.restart();
            interval = 2500 + Math.random() * 3000;
        }
    }

    Timer {
        id: unblink

        interval: 120
        onTriggered: root.blinking = false
    }
}
