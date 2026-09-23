import QtQuick

// Mochi: gota negra blanda con ojos blancos. Mira hacia (lookX, lookY) en [-1, 1].
// El cuerpo es un fluido: al moverlo se queda atrás, se estira y tiembla al soltarlo.
Item {
    id: root

    property string mood: "idle"   // idle, listening, thinking, working, talking, happy, sad
    property bool dragging: false
    property real lookX: 0
    property real lookY: 0
    property bool blinking: false
    property real bob: 0

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

    implicitWidth: 2 * rx + 8
    implicitHeight: 2 * ry + 8

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
            const nw = w.slice(), nv = wv.slice();
            for (let i = 0; i < n; i++) {
                const a = 2 * Math.PI * i / n;
                const lap = w[(i + 1) % n] + w[(i + n - 1) % n] - 2 * w[i];
                nv[i] += (-kw * w[i] - cw * wv[i] + kc * lap) * dt;
                // El movimiento empuja el fluido hacia atrás: se aplasta delante y se abomba detrás
                nv[i] -= (mx * Math.cos(a) + my * Math.sin(a)) * g;
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
            root.sx += svx * dt;
            root.sy += svy * dt;

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

    function poke(): void {
        sim.poke();
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
            duration: root.mood === "working" ? 220 : 1100
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            to: 0
            duration: root.mood === "working" ? 220 : 1100
            easing.type: Easing.InOutSine
        }
    }

    // Cuerpo: curva suave que pasa por los nodos
    Canvas {
        id: canvas

        anchors.centerIn: parent
        width: root.width + 2 * root.rx
        height: root.height + 2 * root.rx

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const cx = width / 2, cy = height / 2;
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
            ctx.fillStyle = "#0b0b0b";
            ctx.fill();
        }
    }

    // Cara: va con la masa, un poco por detrás
    Item {
        id: face

        width: 2 * root.rx * root.sx
        height: 2 * root.ry * root.sy
        x: (root.width - width) / 2 + root.ox * 0.5
        y: (root.height - height) / 2 + root.oy * 0.5

        // Ojos
        Repeater {
            model: [-1, 1]

            Item {
                id: eye

                required property int modelData

                readonly property bool happy: root.mood === "happy"
                property real lx: root.mood === "thinking" ? 0.6 : root.mood === "listening" ? 0 : root.lookX
                property real ly: root.mood === "thinking" ? -0.8 : root.mood === "listening" ? -0.5 : root.lookY

                x: face.width / 2 + modelData * 12 * root.u - width / 2 + lx * 6 * root.u
                y: face.height * 0.42 - height / 2 + ly * 5 * root.u
                width: 12 * root.u
                height: 18 * root.u

                Behavior on lx {
                    NumberAnimation {
                        duration: 120
                    }
                }
                Behavior on ly {
                    NumberAnimation {
                        duration: 120
                    }
                }

                Rectangle {
                    visible: !eye.happy
                    anchors.centerIn: parent
                    width: (root.dragging ? 12 : 10) * root.u
                    height: (root.blinking ? 2 : root.dragging ? 16 : root.mood === "working" ? 7 : root.mood === "sad" ? 9 : 15) * root.u
                    radius: width / 2
                    color: "white"

                    Behavior on height {
                        NumberAnimation {
                            duration: 70
                        }
                    }
                }

                // ^ ^
                Text {
                    visible: eye.happy
                    anchors.centerIn: parent
                    text: "^"
                    font.pixelSize: 22 * root.u
                    font.bold: true
                    color: "white"
                }
            }
        }

        // Boca pequeña solo al hablar
        Rectangle {
            visible: root.mood === "talking"
            anchors.horizontalCenter: parent.horizontalCenter
            y: face.height * 0.68
            width: 7 * root.u
            radius: width / 2
            color: "white"

            SequentialAnimation on height {
                loops: Animation.Infinite
                running: root.mood === "talking"

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
                    color: "white"
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

    Timer {
        running: root.visible
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
