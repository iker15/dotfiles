import QtQuick

// Mochi: gota blanda con forma de daifuku (cúpula arriba, base plana) y solo dos ojos.
// El cuerpo NO se dibuja aquí: lo dibuja shell.qml con los blobs de Caelestia (mismo material
// que la barra y el borde, y se funde con ellos). Aquí van la simulación, la geometría del
// cuerpo (body*/mass*) y los ojos.
// Toda la expresión va en los ojos: tamaño, párpados (arriba, inclinados, o por abajo en
// media luna) y hacia dónde miran. Los ojos cambian de forma con muelles, así que
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
    property bool talking: false   // escribiendo una respuesta: los ojos botan
    property bool music: false     // suena música: a veces baila

    // Color del cuerpo (el del marco) y ojos que contrasten con él
    property color bodyColor: Theme.surface
    readonly property real bodyLum: 0.299 * bodyColor.r + 0.587 * bodyColor.g + 0.114 * bodyColor.b
    property color ink: bodyLum > 0.55 ? "#1c1b1b" : "#f4f1f0"

    Behavior on ink {
        ColorAnimation {
            duration: 450
        }
    }

    // Posición global de Mochi: si cambia, el fluido lo nota por inercia
    property real worldX: 0
    property real worldY: 0
    property bool eyesOff: false   // buceando por dentro del marco: no se le ven los ojos

    readonly property real u: 1.45                 // escala respecto al Mochi original
    readonly property real rx: 32 * u              // semiejes del cuerpo en reposo
    readonly property real ry: 29 * u

    // Estado de la simulación
    property real ox: 0     // desplazamiento de la masa respecto al punto de agarre
    property real oy: 0
    property real sx: 1     // escala del cuerpo (muelle hacia la de reposo/agarre)
    property real sy: 1

    // Geometría del cuerpo (coordenadas de este Item), apoyado por abajo. Todo son círculos
    // que se funden entre sí (metaballs), así nunca se ve una caja:
    // - dos círculos del cuerpo, separados en horizontal (más cuanto más se aplasta)
    // - la masa, que se queda atrás al moverlo, y la cola, que se queda aún más atrás
    property real ox2: 0
    property real oy2: 0
    // El cuerpo es una elipse centrada en el Item (semiejes bodyRx/bodyRy) con ondas
    // en la superficie (wobA/wobB: armónicos 2-5, los usa mochi.frag)
    readonly property real bodyRx: rx * sx
    readonly property real bodyRy: 0.95 * ry * sy
    readonly property real bodyR: bodyRy
    readonly property real centerY: height / 2
    property vector4d wobA: Qt.vector4d(0, 0, 0, 0)
    property vector4d wobB: Qt.vector4d(0, 0, 0, 0)
    readonly property real massR: bodyR * 0.8
    readonly property real massX: width / 2 + ox
    readonly property real massY: centerY + oy
    readonly property real tailR: bodyR * 0.55
    readonly property real tailX: width / 2 + ox2
    readonly property real tailY: centerY + oy2

    // Expresión: una reacción puntual manda sobre todo lo demás
    property string reaction: ""     // cualquier cara, durante un rato (react)
    property string idleExpr: ""     // gestos sueltos cuando está tranquilo
    readonly property string face: reaction || (dragging ? "held" : falling ? "surprised" : mood !== "idle" ? mood : sleepy ? "asleep" : hidden ? "peek" : idleExpr)

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

    // Empujón a la forma: ancho (ax) y alto (ay); positivo estira, negativo encoge. Para la
    // marcha: se encoge antes de arrancar, se estira al lanzarse, se aplasta al frenar
    function kick(ax: real, ay: real): void {
        sim.svx += ax;
        sim.svy += ay;
    }

    // Inclinar los ojos un momento (grados/s), como quien se echa hacia delante
    function lean(v: real): void {
        sim.rotV += v;
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

        readonly property int n: 16
        property var w: new Array(16).fill(0)       // deformación radial de cada punto del borde
        property var wv: new Array(16).fill(0)
        property real vx: 0
        property real vy: 0
        property real vx2: 0
        property real vy2: 0
        property real svx: 0
        property real svy: 0
        property real lastX: NaN
        property real lastY: NaN
        property real t: 0

        // Ojos: forma actual y su velocidad (muelles hacia la forma de la expresión)
        // x, y: desplazamiento (px) · w, h: tamaño relativo · lt: párpado de arriba (0-1)
        // tilt: inclinación del párpado (+ enfadado, − triste) · lb: párpado de abajo (media luna feliz)
        // heart: >0.5 → ojo de corazón
        property var eyes: [newEye(), newEye()]
        property real rot: 0
        property real rotV: 0
        property int lastBeat: 0

        function newEye(): var {
            return {
                cur: {
                    x: 0,
                    y: 0,
                    w: 1,
                    h: 1,
                    lt: 0,
                    tilt: 0,
                    lb: 0,
                    heart: 0
                },
                vel: {
                    x: 0,
                    y: 0,
                    w: 0,
                    h: 0,
                    lt: 0,
                    tilt: 0,
                    lb: 0,
                    heart: 0
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
                lb: 0,
                heart: 0
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
            case "asleep":      // cerrados, respirando
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
            case "excited":     // grandes, brillantes, dando botes
                e.w = e.h = 1.3;
                e.lb = 0.12;
                lx = 0;
                ly = -0.35 - 0.3 * Math.abs(Math.sin(t * 9));
                break;
            case "love":        // ojos de corazón que laten
                e.heart = 1;
                e.w = e.h = 1.25 + 0.1 * Math.max(0, Math.sin(t * 7));
                lx = 0;
                ly = -0.2;
                break;
            case "proud":       // media luna y barbilla arriba
                e.lb = 0.45;
                e.w = 1.15;
                lx = 0;
                ly = -0.6;
                break;
            case "confused":    // un ojo entornado y otro abierto
                if (side < 0) {
                    e.lt = 0.4;
                    e.tilt = -0.35;
                    e.h = 0.92;
                } else {
                    e.w = e.h = 1.15;
                }
                lx = 0.25 * Math.sin(t * 1.5);
                ly = -0.2;
                break;
            case "sorry":       // pequeños, cejas tristes, apartando la mirada
                e.lt = 0.28;
                e.tilt = -0.6;
                e.w = e.h = 0.9;
                lx = -0.35;
                ly = 0.55;
                break;
            case "playful":     // guiño
                if (side < 0) {
                    e.lb = 0.52;
                    e.w = 1.2;
                    e.h = 1.1;
                } else {
                    e.w = e.h = 1.1;
                }
                ly = -0.1;
                break;
            case "sleepy":      // párpados pesados
                e.lt = 0.5;
                e.lb = 0.12;
                e.w = 1.1;
                ly = 0.3;
                lx = 0;
                break;
            case "yawn":        // bostezo: aprieta los ojos y los abre despacio
                e.w = 1.3;
                e.h = 0.16;
                e.tilt = 0.4;
                lx = 0;
                ly = -0.2;
                break;
            case "focused":     // serio, a trabajar
                e.lt = 0.35;
                e.tilt = 0.3;
                lx = 0.2 * Math.sin(t * 0.9);
                ly = 0.1;
                break;
            case "reading": {   // lee línea a línea: barre a la derecha y vuelve de golpe
                const ph = (t * 0.8) % 1;
                e.lt = 0.22;
                lx = ph < 0.85 ? -0.8 + 1.6 * ph / 0.85 : 0.8 - 1.6 * (ph - 0.85) / 0.15;
                ly = 0.25 + 0.2 * (Math.floor(t * 0.8) % 3) / 2;
                break;
            }
            case "searching":   // buscando por ahí
                e.w = e.h = 1.1;
                lx = 0.9 * Math.sin(t * 3.2);
                ly = -0.2 + 0.35 * Math.sin(t * 1.7);
                break;
            case "calm":
                e.lt = 0.2;
                e.lb = 0.2;
                break;
            case "dance":       // bailando al ritmo
                e.lb = 0.45;
                e.w = 1.15;
                lx = 0.6 * Math.sin(t * 7.5);
                ly = -0.2;
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
            // Mientras escribe la respuesta, los ojos botan un poco
            if (root.talking) {
                e.h *= 1 + 0.07 * Math.sin(t * 11);
                ly -= 0.12 * Math.abs(Math.sin(t * 5.5));
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

            // La cola: más blanda y más rezagada (estira el cuerpo como una gota)
            let ox2 = root.ox2 - mx * 0.95, oy2 = root.oy2 - my * 0.95;
            vx2 += (-90 * ox2 - 6 * vx2) * dt;
            vy2 += (-90 * oy2 - 6 * vy2) * dt;
            ox2 += vx2 * dt;
            oy2 += vy2 * dt;
            const lim2 = root.rx * 0.95, m2 = Math.hypot(ox2, oy2);
            if (m2 > lim2) {
                ox2 *= lim2 / m2;
                oy2 *= lim2 / m2;
            }
            root.ox2 = ox2;
            root.oy2 = oy2;

            // Ondas en la superficie: cada punto del borde es un muelle unido a sus vecinos,
            // y el movimiento empuja el fluido hacia atrás
            const kw = 260, cw = 7, kc = 200, g = 0.045;
            const fx = Math.max(-12, Math.min(12, mx)), fy = Math.max(-12, Math.min(12, my));
            const nw = w.slice(), nv = wv.slice();
            for (let i = 0; i < n; i++) {
                const a = 2 * Math.PI * i / n;
                const lap = w[(i + 1) % n] + w[(i + n - 1) % n] - 2 * w[i];
                nv[i] += (-kw * w[i] - cw * wv[i] + kc * lap) * dt;
                nv[i] -= (fx * Math.cos(a) + fy * Math.sin(a)) * g;
                nw[i] = Math.max(-0.3, Math.min(0.3, w[i] + nv[i] * dt));
            }
            w = nw;
            wv = nv;
            // A armónicos para el shader (+ una ondulación lenta, como una gota de lava)
            const hc = [0, 0, 0, 0, 0, 0, 0, 0];
            for (let i = 0; i < n; i++) {
                const a = 2 * Math.PI * i / n;
                for (let k = 2; k <= 5; k++) {
                    hc[(k - 2) * 2] += w[i] * Math.cos(k * a) * 2 / n;
                    hc[(k - 2) * 2 + 1] += w[i] * Math.sin(k * a) * 2 / n;
                }
            }
            hc[0] += 0.012 * Math.sin(t * 1.7);
            hc[3] += 0.008 * Math.sin(t * 2.3);
            hc[4] += 0.006 * Math.sin(t * 2.9);
            root.wobA = Qt.vector4d(hc[0], hc[1], hc[2], hc[3]);
            root.wobB = Qt.vector4d(hc[4], hc[5], hc[6], hc[7]);

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
            const f = root.face;
            const trot = f === "curious" ? 9 : f === "confused" ? -8 : f === "dance" ? 8 * Math.sin(t * 7.5) : 0;
            // Bailando: un botecito en cada golpe
            if (f === "dance") {
                const beat = Math.floor(t / 0.42);
                if (beat !== lastBeat) {
                    lastBeat = beat;
                    svy -= 1.7;
                    svx += 1.1;
                }
            }
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

    // Ojos (el cuerpo lo dibuja shell.qml)
    Canvas {
        id: canvas

        anchors.fill: parent
        anchors.margins: -root.rx
        opacity: root.eyesOff ? 0 : 1

        Behavior on opacity {
            NumberAnimation {
                duration: 160
            }
        }

        function drawEye(ctx: var, x: real, y: real, e: var, side: int): void {
            const d = 9.5 * root.u;
            if (e.heart > 0.5) {
                const hs = d * e.w * 0.62;
                ctx.fillStyle = root.ink;
                ctx.beginPath();
                ctx.moveTo(x, y + hs * 0.8);
                ctx.bezierCurveTo(x - hs * 1.25, y - hs * 0.05, x - hs * 0.7, y - hs * 1.05, x, y - hs * 0.4);
                ctx.bezierCurveTo(x + hs * 0.7, y - hs * 1.05, x + hs * 1.25, y - hs * 0.05, x, y + hs * 0.8);
                ctx.fill();
                return;
            }
            const w = d * e.w, h = Math.max(1.9 * root.u, d * e.h * (1 - 0.92 * root.blink));
            const r = Math.min(w, h) / 2;

            ctx.fillStyle = root.ink;
            ctx.beginPath();
            ctx.roundedRect(x - w / 2, y - h / 2, w, h, r, r);
            ctx.fill();

            // Los párpados borran el ojo (el cuerpo es translúcido: no se puede tapar pintando)
            ctx.globalCompositeOperation = "destination-out";
            ctx.fillStyle = "black";

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
            ctx.globalCompositeOperation = "source-over";
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const cx = width / 2, cy = root.centerY + root.rx;   // + margen del lienzo
            ctx.save();
            ctx.translate(cx + root.ox * 0.5, cy - root.bodyR * 0.12 + root.oy * 0.5);
            ctx.rotate(sim.rot * Math.PI / 180);
            for (let i = 0; i < 2; i++) {
                const side = i ? 1 : -1, e = sim.eyes[i].cur;
                drawEye(ctx, side * 11.5 * root.u * root.sx + e.x, e.y, e, side);
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
            const pick = root.music && Math.random() < 0.5 ? "dance" : ["lookaround", "wink", "smile", "curious", "doubleblink", "wiggle", "roll", "calm"][Math.floor(Math.random() * 8)];
            if (pick === "doubleblink") {
                root.doBlink();
                doubleBlink.restart();
            } else if (pick === "wiggle") {
                sim.poke();
            } else {
                root.idleExpr = pick;
                clearIdle.interval = pick === "wink" ? 500 : pick === "roll" ? 1250 : pick === "lookaround" ? 1500 : pick === "dance" ? 4000 : 1700;
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
