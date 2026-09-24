import QtQuick
import "Hats.js" as Hats
import "Skins.js" as Skins

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
    property color bodyColor: "#1c1b1b"   // (sin singletons: también lo usa LockPet.qml)
    readonly property real bodyLum: 0.299 * bodyColor.r + 0.587 * bodyColor.g + 0.114 * bodyColor.b
    property color inkOverride: "transparent"   // p. ej. imitando a Clawd: ojos oscuros siempre
    property color ink: inkOverride.a > 0 ? inkOverride : bodyLum > 0.55 ? "#1c1b1b" : "#f4f1f0"

    Behavior on ink {
        ColorAnimation {
            duration: 450
        }
    }

    // Posición global de Mochi: si cambia, el fluido lo nota por inercia
    property real worldX: 0
    property real worldY: 0
    // Color de las ojeras: el del cuerpo más oscuro, tirando a morado
    readonly property color bagColor: Qt.tint(Qt.darker(bodyColor, bodyLum > 0.5 ? 1.32 : 1.9), Qt.rgba(0.4, 0.15, 0.5, 0.22))
    property real drowsy: 0          // 0-1: sueño según la hora (entorna los ojos, ojeras)
    // Sueño: cabezadas (nod: 0 despierto → 1 cabeza caída) y quedarse dormido del todo
    property real nod: 0
    property real nodDir: 1
    property int nods: 0             // cabezadas seguidas
    property bool dozing: false
    property bool eyesOff: false   // buceando: los ojos se quedan bajo el marco
    // Zona donde se pueden ver los ojos (coordenadas de este Item): el interior del marco
    property rect clipRect: Qt.rect(-1e5, -1e5, 2e5, 2e5)

    // Lo que le pasa por fuera: calor (se derrite: más ancho y aplastado, ojos caídos y sudor),
    // una ventana que lo aplasta (press, en el eje de la normal del marco), nieve que se le
    // acumula en la cabeza (snow 0-1) y el gorro de temporada (Hats.js)
    property real melt: 0
    property real affection: 0.3     // cariño (0-1): con mucho, a veces pone ojos de amor
    property bool sulky: false       // enfurruñado: gestos tristes, nada de alegrías
    property real press: 0
    property bool pressVertical: true   // apoyado en suelo/techo (si no, en una pared)
    property real snow: 0
    property string hat: ""
    // Normal del marco donde está apoyado (hacia el marco; 0,0 = en el aire): al aplastarse o
    // derretirse se queda pegado a él en vez de despegarse
    property real anchorNx: 0
    property real anchorNy: 0
    Behavior on anchorNx {
        NumberAnimation {
            duration: 200
        }
    }
    Behavior on anchorNy {
        NumberAnimation {
            duration: 200
        }
    }
    readonly property real shiftX: anchorNx * (rx - bodyRx)
    readonly property real shiftY: anchorNy * (0.95 * ry - bodyRy)

    property real u: 1.45                          // escala respecto al Mochi original (la ficha del bloqueo lo sube: ojos nítidos)
    // Su aspecto (Look.qml: lo eliges al crearlo). Sin singletons aquí: se lo pasa quien lo usa
    property real eyeSize: 1      // tamaño de los ojos
    property real eyeGap: 1       // separación
    property real eyeY: 0         // altura (−1 arriba … 1 abajo)
    property real eyeShape: 0     // −0.6 ovalados anchos · 0 redondos · 1 alargados
    property real wide: 1         // ancho del cuerpo (el alto compensa)
    property real jelly: 1        // blandura: tiembla más y tarda más en calmarse
    property var traits: []       // rasgos de carácter (Traits.js): bailongo, curioso…
    // Transformado (Skins.js): sus detalles (antifaz, mofletes, boca…) y cómo son sus ojos
    // (el cuerpo, su color y lo que le brota los pinta shell.qml con el shader)
    property string skin: ""
    property real skinAmt: 0
    property real skinT: 0
    readonly property var skinDef: Skins.byId(skin)
    // su silueta real (SkinShapes.js) y sus ojos en el sitio de los del personaje; px por semiancho
    // de la silueta (en vertical, como el shader: sigue al cuerpo cuando se aplasta)
    readonly property var silDef: skinDef?.sil ?? null
    readonly property var silEyes: silDef && skinAmt > 0.5 ? silDef.eyes : null
    readonly property real silKx: rx * sx * (silDef?.size ?? 1)
    readonly property real silKy: rx * sy * (silDef?.size ?? 1)
    property real eyeRound: 1                 // 1 redondos · 0 cuadrados (slime de Minecraft)
    property color eyeWhite: "transparent"    // esclerótica (Totoro, Blinky…): la pupila mira dentro
    property real eyeWhiteScale: 1.9
    property bool eyeShine: false             // brillito
    property real baseLid: 0                  // párpado de serie (Snorlax dormido, Gengar malote)
    property real baseTilt: 0
    // Al nacer: charco (1 = aplastado del todo en el suelo, 0 = ya con su forma) y la primera
    // vez que abre los ojos (despacio; mientras, no parpadea solo)
    property real puddle: 0
    property bool firstOpening: false
    readonly property real rx: 32 * u * wide       // semiejes del cuerpo en reposo
    readonly property real ry: 29 * u / Math.sqrt(wide)

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
    readonly property string face: reaction || (dragging ? "held" : falling ? (traits.includes("valiente") ? "excited" : "surprised") : mood !== "idle" ? mood : sleepy || dozing ? "asleep" : hidden ? "peek" : idleExpr)

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

    // Da una cabezada: se le van cerrando los ojos y se le cae la cabeza… y se despierta de golpe
    function startNod(): void {
        if (dozing)
            return;
        nodDir = Math.random() < 0.5 ? -1 : 1;
        nodAnim.restart();
    }

    // Quedarse dormido del todo (tras una última cabezada): antes de que se apague la pantalla
    property bool mustDoze: false
    function dozeOff(): void {
        if (dozing)
            return;
        mustDoze = true;
        startNod();
    }

    function nodEnd(): void {
        nods++;
        // Tras unas cuantas, de madrugada, se queda frito
        if (mustDoze || (nods >= 3 && drowsy > 0.6 && Math.random() < 0.6)) {
            mustDoze = false;
            dozing = true;
            settleNod.restart();
            return;
        }
        // Sobresalto: la cabeza vuelve arriba de golpe, ojos como platos, y parpadea
        nod = 0;
        sim.svy += 2.4;
        sim.svx -= 1;
        sim.rotV -= nodDir * 160;
        react("surprised", 420);
        doubleBlink.interval = 520;
        doubleBlink.restart();
        if (Math.random() < 0.35)
            nodAgain.restart();   // …y al rato vuelve a caer
    }

    // Lo despiertan (le hablas, lo tocas, le pasas el ratón): se sobresalta, se estira y bosteza
    function wake(): void {
        nodAnim.stop();
        nodAgain.stop();
        settleNod.stop();
        mustDoze = false;
        nod = 0;
        nods = 0;
        if (!dozing)
            return;
        dozing = false;
        react("surprised", 380);
        sim.svy += 2.8;
        sim.svx -= 1.2;
        wakeYawn.restart();
    }

    function yawn(): void {
        react("yawn", 1800);
        sim.svy += 1.8;   // se estira
        sim.svx -= 0.9;
    }

    // Golpe de la música de verdad (integrations/beats.py): bailando, bota y se ladea a compás
    property real lastBeatAt: -10
    property real danceSide: 1
    function beat(period: real): void {
        lastBeatAt = sim.t;
        if (face !== "dance")
            return;
        danceSide = -danceSide;
        const k = traits.includes("bailongo") ? 1.45 : 1;
        sim.svy -= 1.7 * k;
        sim.svx += 1.1 * k;
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
        // El gorro se balancea un poco al moverse
        property real hatRot: 0
        property real hatRotV: 0
        // Gota de sudor: posición (0 arriba → 1 abajo; −1 = ninguna) y de qué lado
        property real sweat: -1
        property real sweatSide: 1
        property real sweatWait: 2

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
            // Cabezada: los párpados caen y la mirada se va abajo
            if (root.nod > 0) {
                e.lt = Math.max(e.lt, 0.92 * root.nod);
                ly += 0.5 * root.nod;
                lx *= 1 - root.nod;
            }
            // Con sueño (según la hora), párpados a media asta y mirada algo caída
            if (root.drowsy > 0 && ["", "smile", "peek", "calm", "curious", "lookaround"].includes(root.face)) {
                e.lt = Math.max(e.lt, 0.34 * root.drowsy);
                ly += 0.12 * root.drowsy;
            }
            // Con calor: párpados pesados y caídos hacia fuera, mirada algo baja
            if (root.melt > 0.01) {
                e.lt = Math.max(e.lt, 0.3 * root.melt);
                e.tilt -= 0.3 * root.melt;
                ly += 0.14 * root.melt;
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
            const jl = root.jelly, k = 170, c = 9 / jl;
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
            vx2 += (-90 * ox2 - 6 / jl * vx2) * dt;
            vy2 += (-90 * oy2 - 6 / jl * vy2) * dt;
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
            const kw = 260, cw = 7 / jl, kc = 200, g = 0.045 * Math.sqrt(jl);
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

            // Escala: aplastarse al respirar, estirarse al cogerlo; con calor se desparrama y si le
            // aplasta una ventana se chafa en ese eje (y se ensancha en el otro)
            // (los dos, contra el marco: en el suelo se chafa hacia abajo, en una pared contra ella)
            const sq = root.press + 0.68 * root.melt, pv = root.pressVertical ? sq : 0, ph = root.pressVertical ? 0 : sq;
            let tsx = root.dragging ? 0.93 : 1 + root.bob * 0.04 + root.nod * 0.05 - 0.5 * ph + 0.45 * pv;
            let tsy = root.dragging ? 1.1 : 1 - root.bob * 0.04 - root.nod * 0.07 - 0.5 * pv + 0.45 * ph;
            const ks = 320, cs = 13 / jl;
            // (charco: muy ancho y plano; al recogerse vuelve a su forma con el muelle)
            const pud = root.puddle;
            tsx = tsx * (1 - pud) + 2.3 * pud;
            tsy = tsy * (1 - pud) + 0.24 * pud;
            svx += (-ks * (root.sx - tsx) - cs * svx) * dt;
            svy += (-ks * (root.sy - tsy) - cs * svy) * dt;
            root.sx = Math.max(0.45, Math.min(1.6 + 0.9 * root.puddle, root.sx + svx * dt));
            root.sy = Math.max(0.45 - 0.25 * root.puddle, Math.min(1.6, root.sy + svy * dt));

            hatRotV += (-90 * hatRot - 5 * hatRotV + mx * 60 - rotV * 0.3) * dt;
            hatRot = Math.max(-25, Math.min(25, hatRot + hatRotV * dt));

            if (root.melt > 0.3) {
                if (sweat >= 0) {
                    sweat += dt / 1.6;
                    if (sweat >= 1) {
                        sweat = -1;
                        sweatWait = (2.5 + Math.random() * 4) / (0.5 + root.melt);
                    }
                } else if ((sweatWait -= dt) <= 0) {
                    sweat = 0;
                    sweatSide = Math.random() < 0.5 ? -1 : 1;
                }
            } else {
                sweat = -1;
            }

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
            const synced = t - root.lastBeatAt < 2;   // hay ritmo de verdad
            const trot = (f === "curious" ? 9 : f === "confused" ? -8 : f === "dance" ? (synced ? 8 * root.danceSide : 8 * Math.sin(t * 7.5)) : 0) + root.nod * 8 * root.nodDir;
            // Bailando sin ritmo detectado: un botecito cada 0,42 s
            if (f === "dance" && !synced) {
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
            duration: 55 + 140 * root.drowsy
            easing.type: Easing.InQuad
        }
        NumberAnimation {
            target: root
            property: "blink"
            to: 0
            duration: 110 + 260 * root.drowsy
            easing.type: Easing.OutQuad
        }
    }

    // Ojos (el cuerpo lo dibuja shell.qml)
    Canvas {
        id: canvas

        // (arriba, sitio para el gorro)
        readonly property real padTop: 2.3 * root.rx

        anchors.fill: parent
        anchors.margins: -root.rx
        anchors.topMargin: -padTop
        opacity: root.eyesOff ? 0 : 1

        Behavior on opacity {
            NumberAnimation {
                duration: 180
            }
        }

        function drawEye(ctx: var, x: real, y: real, e: var, side: int, bx: real): void {
            const d = root.silEyes ? root.silEyes.d * root.silKx : 9.5 * root.u * root.eyeSize;
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
            const w = d * e.w * (1 - 0.18 * root.eyeShape), h = Math.max(1.9 * root.u, d * e.h * (1 + 0.45 * root.eyeShape) * (1 - 0.92 * root.blink));
            const r = Math.min(w, h) / 2 * root.eyeRound;

            // Con esclerótica: se queda casi en su sitio y la pupila mira dentro de ella
            if (root.eyeWhite.a > 0 && e.lb < 0.3 && h > d * 0.25) {
                const k = root.eyeWhiteScale, ws = d * k * (1 - 0.18 * root.eyeShape), hs = d * k * (1 + 0.45 * root.eyeShape) * Math.max(0.12, 1 - 0.92 * root.blink) * Math.min(1.15, e.h);
                const sx = bx + (x - bx) * 0.3, sy = y * 0.3;
                ctx.fillStyle = root.eyeWhite;
                ctx.beginPath();
                ctx.ellipse(sx - ws / 2, sy - hs / 2, ws, hs);
                ctx.fill();
                const mx = Math.max(0, (ws - w) / 2 * 0.85), my = Math.max(0, (hs - h) / 2 * 0.85);
                x = sx + Math.max(-mx, Math.min(mx, x - sx));
                y = sy + Math.max(-my, Math.min(my, y - sy));
            }

            ctx.fillStyle = root.ink;
            ctx.beginPath();
            ctx.roundedRect(x - w / 2, y - h / 2, w, h, r, r);
            ctx.fill();
            if (root.eyeShine && h > d * 0.4) {
                ctx.fillStyle = "rgba(255,255,255,0.92)";
                ctx.beginPath();
                ctx.ellipse(x - w * 0.34, y - h * 0.4, w * 0.4, Math.min(h * 0.36, w * 0.5));
                ctx.fill();
            }

            // Los párpados borran el ojo (el cuerpo es translúcido: no se puede tapar pintando)
            ctx.globalCompositeOperation = "destination-out";
            ctx.fillStyle = "black";

            // Párpado de arriba (recto, inclinado hacia dentro o hacia fuera); algunas
            // transformaciones lo traen de serie (salvo con un susto)
            let lt = e.lt, tilt = e.tilt;
            if (root.baseLid > lt && root.face !== "surprised" && root.face !== "falling") {
                lt = root.baseLid;
                tilt = root.baseTilt;
            }
            if (root.eyeWhite.a > 0 && lt > 0.01) {
                // (el párpado tapa también la esclerótica)
                const k = root.eyeWhiteScale;
                ctx.beginPath();
                const top = y - h * k / 2 + lt * h * k;
                ctx.rect(x - w * k, y - h * k * 1.5, w * 2 * k, top - (y - h * k * 1.5));
                ctx.fill();
            }
            if (lt > 0.01) {
                const top = y - h / 2 + lt * h;
                const inner = top + tilt * h * 0.4, outer = top - tilt * h * 0.4;
                const yl = side < 0 ? outer : inner, yr = side < 0 ? inner : outer;
                ctx.beginPath();
                ctx.moveTo(x - w / 2 - 2, yl);
                ctx.lineTo(x + w / 2 + 2, yr);
                ctx.lineTo(x + w / 2 + 2, y - h);
                ctx.lineTo(x - w / 2 - 2, y - h);
                ctx.closePath();
                ctx.fill();
            } else if (tilt > 0.05 && h < d * 0.5) {
                // Ojos apretados: pellizco en la esquina interior
                const inner = x - side * w / 2;
                ctx.beginPath();
                ctx.moveTo(inner, y - h);
                ctx.lineTo(inner + side * w * 0.45 * tilt, y - h);
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

            // Ojeras: una media luna oscura (algo morada) bajo cada ojo, según el sueño
            const bags = Math.max(0, Math.min(1, (root.drowsy - 0.2) / 0.6));
            if (bags > 0.01) {
                const by = y + h / 2 + 2.3 * root.u;
                ctx.globalAlpha = 0.85 * bags;
                ctx.strokeStyle = root.bagColor;
                ctx.lineWidth = 1.5 * root.u;
                ctx.lineCap = "round";
                ctx.beginPath();
                ctx.moveTo(x - w * 0.55, by);
                ctx.quadraticCurveTo(x, by + 2.6 * root.u, x + w * 0.55, by);
                ctx.stroke();
                ctx.globalAlpha = 1;
            }
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const cx = width / 2 + root.shiftX, cy = root.centerY + padTop + root.shiftY;   // + margen del lienzo
            const cr = root.clipRect;
            ctx.save();
            ctx.beginPath();
            ctx.rect(cr.x + root.rx, cr.y + padTop, cr.width, cr.height);
            ctx.clip();
            // Transformado: detalles sobre el cuerpo (recortados a su silueta; los de debajo de los
            // ojos se pintan después, por detrás) y encima (boca, bigotes…)
            const sk = root.skinDef, skA = Math.max(0, Math.min(1, root.skinAmt));
            const g = sk ? {
                x: cx,
                y: cy,
                base: cy + root.bodyRy,
                k: root.silKx,
                ky: root.silKy,
                rx: root.bodyRx,
                t: root.skinT,
                face: root.face,
                amt: skA,
                ink: root.ink
            } : null;
            ctx.save();
            // (transformado: en el sitio de los ojos del personaje)
            const se = root.silEyes;
            const ex0 = cx + (se ? se.x * root.silKx : 0) + root.ox * 0.5;
            const ey0 = (se ? cy + root.bodyRy + (se.y - 1) * root.silKy : cy - root.bodyR * 0.12 + root.eyeY * 7 * root.u) + root.oy * 0.5, rot = sim.rot * Math.PI / 180;
            ctx.translate(ex0, ey0);
            ctx.rotate(rot);
            if (g)
                g.eyes = [];
            for (let i = 0; i < 2; i++) {
                const side = i ? 1 : -1, e = sim.eyes[i].cur;
                const bx = se ? side * se.g * root.silKx : side * 11.5 * root.u * root.eyeGap * Math.max(0.78, root.sx);   // (aplastado de lado, que no se junten)
                drawEye(ctx, bx + e.x, e.y, e, side, bx);
                if (g) {
                    const lx = bx + e.x * 0.3, ly = e.y * 0.3;
                    g.eyes.push([ex0 + lx * Math.cos(rot) - ly * Math.sin(rot), ey0 + lx * Math.sin(rot) + ly * Math.cos(rot)]);
                }
            }
            // Sudor: una gotita que le resbala por la frente
            if (root.melt > 0.3 && sim.sweat >= 0) {
                const k = sim.sweat, x = sim.sweatSide * 17 * root.u * root.sx, y = -root.bodyRy * 0.62 + k * root.bodyRy * 0.55;
                const r = 3.2 * root.u;
                ctx.globalAlpha = Math.min(1, (1 - k) * 3) * Math.min(1, (root.melt - 0.3) * 5);
                ctx.fillStyle = "#8fd0f5";
                ctx.beginPath();
                ctx.moveTo(x, y - r * 2.2);
                ctx.quadraticCurveTo(x + r * 1.1, y - r * 0.4, x + r, y + r * 0.2);
                ctx.arc(x, y + r * 0.2, r, 0, Math.PI);
                ctx.quadraticCurveTo(x - r * 1.1, y - r * 0.4, x, y - r * 2.2);
                ctx.fill();
                ctx.fillStyle = "rgba(255,255,255,0.8)";
                ctx.beginPath();
                ctx.ellipse(x - r * 0.55, y - r * 0.2, r * 0.45, r * 0.7);
                ctx.fill();
                ctx.globalAlpha = 1;
            }
            ctx.restore();
            if (sk && skA > 0) {
                // (por DETRÁS de los ojos ya pintados: donde los párpados han borrado, se ve el
                // detalle que hay debajo, p. ej. la cara crema de Snorlax con los ojos entornados)
                ctx.globalCompositeOperation = "destination-over";
                // (recortados a su silueta, la misma que pinta el shader)
                const rim = (i, n) => [cx + root.bodyRx * Math.cos(2 * Math.PI * i / n), cy + root.bodyRy * Math.sin(2 * Math.PI * i / n)];
                const pts = Skins.outline(sk, g, rim, skA);
                Skins.drawUnder(ctx, sk, g, c => {
                    pts.forEach(([px, py], i) => i ? c.lineTo(px, py) : c.moveTo(px, py));
                    c.closePath();
                });
                ctx.globalCompositeOperation = "source-over";
                Skins.drawOver(ctx, sk, g, skA);
            }

            // Cabeza: lo más alto del cuerpo (la elipse con sus ondas, o la masa si sobresale)
            const wa = root.wobA, wb = root.wobB;
            const wobTop = -wa.x + wa.w + wb.x - wb.w;
            const headY = Math.min(-root.bodyRy * (1 + wobTop), root.oy - root.massR);
            ctx.translate(cx + root.ox * 0.3, cy + headY);
            ctx.rotate((sim.rot * 0.6 + sim.hatRot) * Math.PI / 180);
            // Nieve acumulada en la cabeza (un montoncito blanco que crece)
            if (root.snow > 0.02) {
                const w = root.bodyRx * (0.5 + 0.45 * root.snow), h = 3 * root.u + 7 * root.u * root.snow;
                ctx.fillStyle = "#f6f9ff";
                ctx.beginPath();
                ctx.moveTo(-w, h * 0.55);
                ctx.bezierCurveTo(-w * 0.8, -h * 0.7, w * 0.8, -h * 0.7, w, h * 0.55);
                ctx.bezierCurveTo(w * 0.4, h * 0.2, -w * 0.4, h * 0.2, -w, h * 0.55);
                ctx.fill();
                ctx.strokeStyle = "rgba(110,130,165,0.55)";
                ctx.lineWidth = 1.1;
                ctx.beginPath();
                ctx.moveTo(-w, h * 0.55);
                ctx.bezierCurveTo(-w * 0.8, -h * 0.7, w * 0.8, -h * 0.7, w, h * 0.55);
                ctx.stroke();
                ctx.fillStyle = "rgba(150,180,220,0.35)";
                ctx.beginPath();
                ctx.moveTo(-w * 0.9, h * 0.5);
                ctx.bezierCurveTo(-w * 0.4, h * 0.05, w * 0.4, h * 0.05, w * 0.9, h * 0.5);
                ctx.bezierCurveTo(w * 0.4, h * 0.25, -w * 0.4, h * 0.25, -w * 0.9, h * 0.5);
                ctx.fill();
                ctx.translate(0, -h * 0.35);
            }
            if (root.hat) {
                ctx.translate(0, 0.16 * root.rx);   // encajado en la cabeza
                Hats.draw(ctx, root.hat, 0.75 * root.rx, sim.t, Math.max(-1, Math.min(1, sim.hatRot / 18)));
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
            if (root.dozing || nodAnim.running)
                return;
            // Con sueño, muchas veces lo que le sale es una cabezada, un bostezo o un parpadeo lento
            if (root.drowsy > 0.25 && Math.random() < 0.3 + 0.5 * root.drowsy) {
                const r = Math.random();
                if (r < 0.5)
                    root.startNod();
                else if (r < 0.75)
                    root.yawn();
                else
                    slowBlink.restart();
                return;
            }
            root.nods = 0;
            const pick = root.music && (root.traits.includes("bailongo") || Math.random() < 0.5) ? "dance" : root.traits.includes("curioso") && Math.random() < 0.3 ? "curious" : root.sulky ? ["sorry", "sad", "lookaround", "calm"][Math.floor(Math.random() * 4)] : root.affection > 0.5 && Math.random() < 0.2 * root.affection ? "love" : ["lookaround", "wink", "smile", "curious", "doubleblink", "wiggle", "roll", "calm"][Math.floor(Math.random() * 8)];
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

    SequentialAnimation {
        id: nodAnim

        NumberAnimation {
            target: root
            property: "nod"
            to: 1
            duration: 1800 + Math.random() * 900
            easing.type: Easing.InQuad
        }
        PauseAnimation {
            duration: 350 + Math.random() * 500
        }
        ScriptAction {
            script: root.nodEnd()
        }
    }

    // Dormido: la cabeza se asienta despacio
    NumberAnimation {
        id: settleNod

        target: root
        property: "nod"
        to: 0.25
        duration: 1400
        easing.type: Easing.OutSine
    }

    Timer {
        id: nodAgain

        interval: 1600 + Math.random() * 1400
        onTriggered: root.startNod()
    }

    Timer {
        id: wakeYawn

        interval: 480
        onTriggered: root.yawn()
    }

    SequentialAnimation {
        id: slowBlink

        NumberAnimation {
            target: root
            property: "blink"
            to: 1
            duration: 420
            easing.type: Easing.InOutSine
        }
        PauseAnimation {
            duration: 380
        }
        NumberAnimation {
            target: root
            property: "blink"
            to: 0
            duration: 520
            easing.type: Easing.InOutSine
        }
    }

    // Si pasa algo (le hablas, lo coges…) se le quita el sueño
    onMoodChanged: if (mood !== "idle") wake()
    onDraggingChanged: if (dragging) wake()

    Timer {
        id: clearIdle

        onTriggered: root.idleExpr = ""
    }

    Timer {
        id: doubleBlink

        interval: 230
        onTriggered: root.doBlink()
    }

    // La primera vez que abre los ojos (al nacer): los entreabre despacio, los vuelve a cerrar
    // un momento, los abre del todo y parpadea dos veces
    function firstOpen(): void {
        reactionTimer.stop();
        reaction = "";
        idleExpr = "";
        firstOpening = true;
        blinkAnim.stop();
        blink = 1;
        firstOpenAnim.restart();
    }
    SequentialAnimation {
        id: firstOpenAnim

        NumberAnimation {
            target: root
            property: "blink"
            to: 0.55
            duration: 1400
            easing.type: Easing.InOutSine
        }
        PauseAnimation {
            duration: 450
        }
        NumberAnimation {
            target: root
            property: "blink"
            to: 0.95
            duration: 160
        }
        PauseAnimation {
            duration: 250
        }
        NumberAnimation {
            target: root
            property: "blink"
            to: 0
            duration: 650
            easing.type: Easing.OutQuad
        }
        PauseAnimation {
            duration: 450
        }
        ScriptAction {
            script: {
                root.firstOpening = false;
                root.doBlink();
                doubleBlink.restart();
            }
        }
    }

    Timer {
        running: root.visible && !root.sleepy && !root.firstOpening
        repeat: true
        interval: 3000
        onTriggered: {
            root.doBlink();
            interval = (2500 + Math.random() * 3000) * (1 + 0.6 * root.drowsy);
        }
    }
}
