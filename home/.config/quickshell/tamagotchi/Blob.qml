import QtQuick

// Mochi: gota blanda con forma de daifuku (cúpula arriba, base plana) y solo dos ojos.
// Toda la expresión va en los ojos: tamaño, párpados (arriba, inclinados, o por abajo en
// media luna), brillo y hacia dónde miran. Los ojos cambian de forma con muelles, así que
// "rebotan" al pasar de una expresión a otra.
// El cuerpo es un fluido: al moverlo se queda atrás, se estira y tiembla al soltarlo.
Item {
    id: root

    property string mood: "idle"   // idle, listening, thinking, working, talking, happy, sad
    property bool dragging: false
    property bool falling: false   // cayendo deprisa (susto)
    property bool hidden: false    // escondido bajo el borde, asomando los ojos
    property bool sleepy: false    // escondido y sin nadie cerca
    property real lookX: 0
    property real lookY: 0
    property real bob: 0
    property real blink: 0         // 0 abierto → 1 cerrado
    property bool light: false     // cuerpo blanco (para fondos oscuros)

    // Colores: cuerpo y ojos se invierten según el fondo
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

    // Estado de la simulación
    property real ox: 0     // desplazamiento de la masa respecto al punto de agarre
    property real oy: 0
    property real sx: 1     // escala del cuerpo (muelle hacia la de reposo/agarre)
    property real sy: 1

    // Expresión: una reacción puntual manda sobre todo lo demás
    property string reaction: ""     // happy, squint, dizzy
    property string idleExpr: ""     // wink, smile, curious, lookaround, roll
    readonly property string face: reaction || (dragging ? "held" : falling ? "surprised" : mood !== "idle" ? mood : sleepy ? "sleepy" : hidden ? "peek" : idleExpr)

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

    function doBlink(): void {
        blinkAnim.restart();
    }

    Timer {
        id: reactionTimer

        onTriggered: root.reaction = ""
    }

    QtObject {
        id: sim

        readonly property int n: 24
        property var w: new Array(24).fill(0)       // deformación radial de cada nodo (fracción del radio)
        property var wv: new Array(24).fill(0)
        property real vx: 0
        property real vy: 0
        property real svx: 0
        property real svy: 0
        property real lastX: NaN
        property real lastY: NaN
        property real t: 0

        // Ojos: forma actual y su velocidad (muelles hacia la forma de la expresión)
        // x, y: desplazamiento (px) · w, h: tamaño relativo · lt: párpado de arriba (0-1)
        // tilt: inclinación del párpado (+ enfadado, − triste) · lb: párpado de abajo (media luna feliz)
        property var eyes: [newEye(), newEye()]
        property real rot: 0
        property real rotV: 0

        function newEye(): var {
            return {
                cur: {
                    x: 0,
                    y: 0,
                    w: 1,
                    h: 1,
                    lt: 0,
                    tilt: 0,
                    lb: 0
                },
                vel: {
                    x: 0,
                    y: 0,
                    w: 0,
                    h: 0,
                    lt: 0,
                    tilt: 0,
                    lb: 0
                }
            };
        }

        // Cómo son los ojos en cada expresión (side: -1 izquierdo, 1 derecho)
        function eyeTarget(side: int): var {
            const e = {
                x: 0,
                y: 0,
                w: 1,
                h: 1,
                lt: 0,
                tilt: 0,
                lb: 0
            };
            let lx = root.lookX, ly = root.lookY;
            switch (root.face) {
            case "happy":       // ^ ^
                e.lb = 0.5;
                e.w = 1.2;
                e.h = 1.1;
                lx *= 0.2;
                ly = -0.3;
                break;
            case "smile":
                e.lb = 0.3;
                e.w = 1.06;
                break;
            case "wink":
                if (side < 0) {
                    e.lb = 0.52;
                    e.w = 1.2;
                    e.h = 1.1;
                } else {
                    e.w = e.h = 1.08;
                }
                break;
            case "surprised":
                e.w = e.h = 1.45;
                lx = 0;
                ly = -0.35;
                break;
            case "held":        // colgando: ojos grandes que se balancean
                e.w = 1.22;
                e.h = 1.3;
                lx = 0.35 * Math.sin(t * 3.2);
                ly = 0.35;
                break;
            case "squint":      // golpe: aprieta los ojos
                e.w = 1.4;
                e.h = 0.22;
                e.tilt = 0.6;
                lx = ly = 0;
                break;
            case "dizzy":       // cada ojo da vueltas en un sentido
                lx = 0.75 * Math.cos(t * 8 * side);
                ly = 0.75 * Math.sin(t * 8 * side);
                e.w = e.h = 0.95 + 0.18 * Math.sin(t * 5 + side);
                break;
            case "sleepy":      // cerrados, respirando
                e.w = 1.2;
                e.h = 0.13;
                lx = 0;
                ly = 0.45 + 0.1 * Math.sin(t * 1.4);
                break;
            case "peek":        // escondido pero alguien se acerca: medio dormido, te mira
                e.lt = 0.42;
                e.w = 1.05;
                break;
            case "listening":
                e.w = 1.12;
                e.h = 1.2;
                lx = 0;
                ly = -0.45;
                break;
            case "thinking":    // mira arriba, un ojo algo entornado, pensando
                lx = 0.55 + 0.3 * Math.sin(t * 1.3);
                ly = -0.8;
                e.lb = side > 0 ? 0.28 : 0.12;
                e.h = side > 0 ? 1.02 : 0.9;
                break;
            case "working":     // concentrado: párpados bajados y la vista recorriendo
                e.lt = 0.4;
                e.tilt = 0.25;
                lx = 0.75 * Math.sin(t * 2.4);
                ly = 0.3;
                break;
            case "talking":     // ojos alegres que botan
                e.lb = 0.24 + 0.08 * Math.sin(t * 11);
                e.h = 1 + 0.07 * Math.sin(t * 11);
                break;
            case "sad":
                e.lt = 0.3;
                e.tilt = -0.45;
                e.w = 1.05;
                lx = 0;
                ly = 0.65;
                break;
            case "curious":     // un ojo grande y otro pequeño
                e.w = e.h = side > 0 ? 1.25 : 0.84;
                break;
            case "lookaround":
                lx = Math.sin(t * 2.2) > 0 ? 0.95 : -0.95;
                ly = 0.1;
                break;
            case "roll":        // pone los ojos en blanco
                lx = 0.85 * Math.cos(t * 5);
                ly = -0.85 * Math.abs(Math.sin(t * 5));
                break;
            }
            e.x = lx * 6 * root.u;
            e.y = ly * 5 * root.u;
            // Perspectiva: el ojo del lado al que mira se ve un poco más grande
            e.w *= 1 + 0.06 * lx * side;
            e.h *= 1 + 0.06 * lx * side;
            return e;
        }

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
            const kw = 260, cw = 7, kc = 200, g = 0.045;
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

            // Ojos: muelle algo bailón hacia la forma de la expresión
            const ke = 340, ce = 20;
            for (let s = 0; s < 2; s++) {
                const tg = eyeTarget(s ? 1 : -1), cur = eyes[s].cur, vel = eyes[s].vel;
                for (const key in tg) {
                    vel[key] += (-ke * (cur[key] - tg[key]) - ce * vel[key]) * dt;
                    cur[key] += vel[key] * dt;
                }
            }
            const trot = root.face === "curious" ? 9 : 0;
            rotV += (-200 * (rot - trot) - 14 * rotV) * dt;
            rot += rotV * dt;

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

    SequentialAnimation {
        id: blinkAnim

        NumberAnimation {
            target: root
            property: "blink"
            to: 1
            duration: 55
            easing.type: Easing.InQuad
        }
        NumberAnimation {
            target: root
            property: "blink"
            to: 0
            duration: 110
            easing.type: Easing.OutQuad
        }
    }

    // Cuerpo y ojos, todo en un lienzo que se repinta cada frame
    Canvas {
        id: canvas

        anchors.centerIn: parent
        width: root.width + 2 * root.rx
        height: root.height + 2 * root.rx

        function drawEye(ctx: var, x: real, y: real, e: var, side: int): void {
            const d = 9.5 * root.u;
            const w = d * e.w, h = Math.max(1.9 * root.u, d * e.h * (1 - 0.92 * root.blink));
            const r = Math.min(w, h) / 2;

            ctx.fillStyle = root.ink;
            ctx.beginPath();
            ctx.roundedRect(x - w / 2, y - h / 2, w, h, r, r);
            ctx.fill();

            // Brillo: le da vida a los ojos
            ctx.fillStyle = root.bodyColor;
            if (h > d * 0.6 && e.lb < 0.3) {
                const hr = Math.min(w, h) * 0.15;
                ctx.globalAlpha = 0.85;
                ctx.beginPath();
                ctx.ellipse(x - w * 0.2 - hr, y - h * 0.22 - hr, 2 * hr, 2 * hr);
                ctx.fill();
                ctx.globalAlpha = 1;
            }

            // Párpado de arriba (recto, inclinado hacia dentro o hacia fuera)
            if (e.lt > 0.01) {
                const top = y - h / 2 + e.lt * h;
                const inner = top + e.tilt * h * 0.4, outer = top - e.tilt * h * 0.4;
                const yl = side < 0 ? outer : inner, yr = side < 0 ? inner : outer;
                ctx.beginPath();
                ctx.moveTo(x - w / 2 - 2, yl);
                ctx.lineTo(x + w / 2 + 2, yr);
                ctx.lineTo(x + w / 2 + 2, y - h);
                ctx.lineTo(x - w / 2 - 2, y - h);
                ctx.closePath();
                ctx.fill();
            } else if (e.tilt > 0.05 && h < d * 0.5) {
                // Ojos apretados: pellizco en la esquina interior
                const inner = x - side * w / 2;
                ctx.beginPath();
                ctx.moveTo(inner, y - h);
                ctx.lineTo(inner + side * w * 0.45 * e.tilt, y - h);
                ctx.lineTo(inner, y + h * 0.1);
                ctx.closePath();
                ctx.fill();
            }

            // Párpado de abajo: mejilla redonda que sube y deja el ojo en media luna ^
            if (e.lb > 0.01) {
                const R = w * 0.62;
                const cut = y + h / 2 - e.lb * h * 1.35;
                ctx.beginPath();
                ctx.ellipse(x - R * 1.1, cut, 2.2 * R, 2 * R);
                ctx.fill();
            }
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const sx = root.sx, sy = root.sy;
            // Forma de mochi: cúpula alta arriba, base más baja, ancha y plana
            const rt = root.ry * 1.06, rb = root.ry * 0.84;
            const cx = width / 2, bottom = height / 2 + root.ry;
            const cy = bottom - rb * sy;
            const n = sim.n, m = Math.hypot(root.ox, root.oy);
            const ux = m > 0.01 ? root.ox / m : 0, uy = m > 0.01 ? root.oy / m : 0;
            const pts = [];
            for (let i = 0; i < n; i++) {
                const a = 2 * Math.PI * i / n;
                const ca = Math.cos(a), sa = Math.sin(a);
                let px = ca * root.rx, py = sa * rt;
                if (sa > 0) {
                    px = Math.sign(ca) * Math.pow(Math.abs(ca), 0.8) * root.rx;
                    py = Math.pow(sa, 0.5) * rb;
                }
                // Ondulación lenta, como una gota de lava
                const idle = 0.012 * Math.sin(sim.t * 1.7 + i * 0.9) + 0.008 * Math.sin(sim.t * 2.9 - i * 1.4);
                const r = 1 + sim.w[i] + idle;
                // La parte de atrás sigue a la masa; la de delante se queda donde la agarras
                const d = ca * ux + sa * uy;
                const back = (1 + d) / 2;
                const thin = 1 - 0.18 * (m / root.rx) * (1 - d * d);   // se adelgaza al estirarse
                pts.push([cx + px * sx * r * thin + root.ox * back, cy + py * sy * r * thin + root.oy * back]);
            }
            ctx.beginPath();
            const mid = (p, q) => [(p[0] + q[0]) / 2, (p[1] + q[1]) / 2];
            const s = mid(pts[n - 1], pts[0]);
            ctx.moveTo(s[0], s[1]);
            for (let i = 0; i < n; i++) {
                const e = mid(pts[i], pts[(i + 1) % n]);
                ctx.quadraticCurveTo(pts[i][0], pts[i][1], e[0], e[1]);
            }
            ctx.closePath();
            ctx.fillStyle = root.bodyColor;
            ctx.fill();

            // Ojos: van con la masa, un poco por detrás
            ctx.save();
            ctx.translate(cx + root.ox * 0.5, cy - rt * 0.1 * sy + root.oy * 0.5);
            ctx.rotate(sim.rot * Math.PI / 180);
            for (let i = 0; i < 2; i++) {
                const side = i ? 1 : -1, e = sim.eyes[i].cur;
                drawEye(ctx, side * 11.5 * root.u * sx + e.x, e.y, e, side);
            }
            ctx.restore();
        }
    }

    // Gestos al azar cuando está tranquilo
    Timer {
        running: root.visible && root.mood === "idle" && !root.dragging && !root.hidden
        repeat: true
        interval: 6000
        onTriggered: {
            interval = 4000 + Math.random() * 7000;
            const pick = ["lookaround", "wink", "smile", "curious", "doubleblink", "wiggle", "roll"][Math.floor(Math.random() * 7)];
            if (pick === "doubleblink") {
                root.doBlink();
                doubleBlink.restart();
            } else if (pick === "wiggle") {
                sim.poke();
            } else {
                root.idleExpr = pick;
                clearIdle.interval = pick === "wink" ? 500 : pick === "roll" ? 1250 : pick === "lookaround" ? 1500 : 1700;
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

        interval: 230
        onTriggered: root.doBlink()
    }

    Timer {
        running: root.visible && !root.sleepy
        repeat: true
        interval: 3000
        onTriggered: {
            root.doBlink();
            interval = 2500 + Math.random() * 3000;
        }
    }
}
