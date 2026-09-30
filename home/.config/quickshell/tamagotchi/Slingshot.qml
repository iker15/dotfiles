import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Planck.js" as P
import "Draw.js" as Draw

// Modo tirachinas ("Angry Mochis"): en un lado de la pantalla sale una estructura aleatoria de
// madera, piedra y hielo con mochis dentro (los "cerdos": chulitos, con casco o con corona), y
// en el otro Mochi con su tirachinas y una fila de mochis enfadados (los "pájaros"). Todos son
// del color de Mochi (el del marco): solo cambian la cara y lo que llevan puesto.
//   normal · rápido (cinta: clic en el aire = acelerón, rompe madera) · triple (gorro de fiesta:
//   clic = se parte en tres, rompe hielo) · bomba (mecha: clic o al rato de chocar = explota,
//   rompe piedra)
// Física: planck.js (Box2D, Planck.js), en metros con y hacia abajo; el suelo es el borde de
// abajo del marco y las paredes, los de los lados. Lo abre shell.qml (pet angry).
// Niveles: ganar desbloquea el siguiente (ver diff más abajo); se guardan en
// ~/.local/state/tamagotchi/angry.json.
PanelWindow {
    id: game

    property string bodyCol: "#d0d3d6"
    property string inkCol: "#1c1b1b"
    property string hat: ""
    property real frame: 10
    property real bar: 60        // la barra de Caelestia, a la izquierda
    signal finished
    signal won(int stars)

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "mochi-slingshot"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // ── Unidades (metros; ppm = px por metro) ──
    // (el tamaño de la pantalla: el de la ventana aún es 0 al abrirse)
    readonly property real sw: screen?.width ?? 1920
    readonly property real sh: screen?.height ?? 1080
    readonly property real ppm: Math.max(30, 50 * sh / 1080)
    readonly property real groundY: (sh - frame) / ppm
    readonly property real leftX: bar / ppm
    readonly property real rightX: (sw - frame) / ppm
    readonly property real slingX: leftX + Math.max(7.4, (rightX - leftX) * 0.18)
    readonly property real anchorX: slingX
    readonly property real anchorY: groundY - 2.6   // donde descansa el mochi cargado
    readonly property real maxDrag: 2.1
    readonly property real power: 11.5    // m/s por metro estirado
    readonly property real gravity: 12
    readonly property real step: 1 / 60

    readonly property var mats: ({
            wood: {
                density: 0.9,
                friction: 0.7,
                hp: 9,
                thr: 1.4,
                pts: 500,
                bit: "#b07b45"
            },
            stone: {
                density: 2.4,
                friction: 0.85,
                hp: 30,
                thr: 2.8,
                pts: 800,
                bit: "#8a8f94"
            },
            ice: {
                density: 0.7,
                friction: 0.25,
                hp: 4,
                thr: 0.8,
                pts: 300,
                bit: "#bfe6fa"
            }
        })
    // Contra qué es bueno cada uno (multiplica el daño de sus golpes)
    readonly property var birdVs: ({
            normal: {
                wood: 1,
                stone: 1,
                ice: 1,
                pig: 1.6
            },
            fast: {
                wood: 2.6,
                stone: 0.7,
                ice: 1,
                pig: 1.6
            },
            triple: {
                wood: 0.8,
                stone: 0.5,
                ice: 3.2,
                pig: 1.6
            },
            bomb: {
                wood: 1,
                stone: 1.4,
                ice: 1,
                pig: 1.6
            }
        })
    readonly property var birdR: ({
            normal: 0.42,
            fast: 0.4,
            triple: 0.34,
            bomb: 0.5
        })
    readonly property var birdDensity: ({
            normal: 4,
            fast: 3.5,
            triple: 4,
            bomb: 5
        })

    // ── Estado ──
    property string phase: "load"   // load | aim | fly | settle | won | lost
    property int score: 0
    property int pigsLeft: 0
    property int birdsLeft: 0
    property real pouchX: anchorX * ppm
    property real pouchY: anchorY * ppm
    property bool aiming: false
    property var aimPts: []
    property real loadT: 0
    property bool hint: true
    property string meFace: "curious"
    property real meLx: 0.6
    property real meLy: 0
    property real clock: 0
    property bool showCard: false
    property int stars: 0

    // ── Niveles ──
    // La dificultad sube hasta el 12 (de ahí en adelante se queda al máximo, con estructuras
    // nuevas cada vez): estructuras más anchas y altas, más piedra y menos hielo, más mochis con
    // casco y rey (y más duros), menos tiros de sobra, la guía de tiro se acorta y, desde el 3,
    // rocas que no se rompen: pedestales, montículos delante y columnas con un mochi encima
    property int level: 1
    property int maxLevel: 1
    property var best: ({})    // mejores estrellas por nivel
    readonly property real hard: Math.min(1, (level - 1) / 11)
    readonly property int spare: level <= 2 ? 1 : level <= 7 ? 0 : -1   // tiros de más sobre los mochis
    readonly property int aimDots: level <= 1 ? 16 : Math.max(3, 16 - 3 * (level - 1))
    readonly property var news: ({
            2: "La guía de tiro se acorta",
            3: "Rocas que no se rompen · ya no sobran tiros",
            5: "Columnas de roca con un mochi encima",
            8: "Menos tiros que mochis: aprovecha los derrumbes",
            12: "Dificultad máxima"
        })
    FileView {
        id: saveFile

        path: `${Quickshell.env("HOME")}/.local/state/tamagotchi/angry.json`
        atomicWrites: true
        printErrors: false
        blockLoading: true
    }
    function loadSave(): void {
        try {
            const d = JSON.parse(saveFile.text() || "{}");
            maxLevel = Math.max(1, d.max ?? 1);
            level = Math.max(1, Math.min(maxLevel, d.level ?? maxLevel));
            best = d.best ?? {};
        } catch (e) {}
    }
    function save(): void {
        saveFile.setText(JSON.stringify({
            level: level,
            max: maxLevel,
            best: best
        }));
    }
    function goLevel(n: int): void {
        level = Math.max(1, n);
        save();
        newLevel(false);
    }

    QtObject {
        id: sim

        property var world: null
        property var spec: null
        property var ents: []        // bloques y mochis de la estructura
        property var birds: []       // los que están volando
        property var queue: []       // {type, item} de los que esperan (el primero, el siguiente)
        property var loaded: null    // el que está en el tirachinas
        property var dead: []
        property var parts: []       // trocitos y polvo
        property bool armed: false
        property real acc: 0
        property real settleT: 0
        property real quiet: 0
        property real trailT: 0
        property real endT: 0
        property real laughT: 0
        property real reactUntil: 0
        property int tries: 0
    }

    // ── Piezas del dibujo ──
    // Un mochi (Draw.avatar, del color de Mochi) centrado en el canvas, que gira con su cuerpo
    component MochiSprite: Canvas {
        id: ms

        property real s: 24
        property string face: "normal"
        property string variant: ""
        property real lx: 0
        property real ly: 0
        property real blink: 0
        property var look: null
        property string hatName: ""
        property string skin: ""
        property int stage: 1
        property real t: 0
        property real hop: 0
        property string bodyCol: "#d0d3d6"
        property string inkCol: "#1c1b1b"
        property color bandCol: "#e05050"

        width: Math.ceil(s * 3.4)
        height: Math.ceil(s * 4.6)
        onFaceChanged: requestPaint()
        onLxChanged: requestPaint()
        onLyChanged: requestPaint()
        onBlinkChanged: requestPaint()
        onTChanged: requestPaint()
        onHatNameChanged: requestPaint()
        onAvailableChanged: if (available) requestPaint()
        transform: Translate {
            y: -ms.hop
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const cx = width / 2, base = height / 2 + 0.86 * s;
            Draw.avatar(ctx, {
                look: look,
                x: cx,
                y: base,
                s: s,
                body: bodyCol,
                ink: inkCol,
                face: face,
                lx: lx,
                ly: ly,
                blink: blink,
                hat: hatName,
                skin: skin,
                stage: stage,
                t: t
            });
            const lh = 1 / Math.sqrt(look?.wide ?? 1), top = base - 1.72 * s * lh;
            ctx.lineCap = "round";
            if (variant === "bomb") {
                // mecha con chispa
                ctx.fillStyle = "#3a3a3e";
                ctx.beginPath();
                ctx.ellipse(cx - 0.16 * s, top - 0.1 * s, 0.32 * s, 0.2 * s);
                ctx.fill();
                ctx.strokeStyle = "#8a6a44";
                ctx.lineWidth = 0.09 * s;
                ctx.beginPath();
                ctx.moveTo(cx, top - 0.02 * s);
                ctx.quadraticCurveTo(cx + 0.05 * s, top - 0.45 * s, cx + 0.38 * s, top - 0.5 * s);
                ctx.stroke();
                const k = 0.7 + 0.3 * Math.sin(t * 40), x = cx + 0.4 * s, y = top - 0.52 * s;
                ctx.fillStyle = "#ffb13b";
                ctx.beginPath();
                for (let i = 0; i < 10; i++) {
                    const a = i * Math.PI / 5, r = (i % 2 ? 0.08 : 0.2) * s * k;
                    ctx.lineTo(x + r * Math.cos(a), y + r * Math.sin(a));
                }
                ctx.closePath();
                ctx.fill();
                ctx.fillStyle = "#fff4c2";
                ctx.beginPath();
                ctx.arc(x, y, 0.05 * s, 0, 2 * Math.PI);
                ctx.fill();
            } else if (variant === "fast") {
                // cinta en la frente, con las puntas al viento
                const y = top + 0.42 * s * lh, hw = 0.84 * s;
                ctx.strokeStyle = bandCol;
                ctx.lineWidth = 0.17 * s;
                ctx.beginPath();
                ctx.moveTo(cx - hw, y + 0.04 * s);
                ctx.quadraticCurveTo(cx, y - 0.1 * s, cx + hw, y + 0.04 * s);
                ctx.stroke();
                ctx.lineWidth = 0.1 * s;
                for (const k of [0, 1]) {
                    ctx.beginPath();
                    ctx.moveTo(cx - hw, y + 0.04 * s);
                    ctx.quadraticCurveTo(cx - hw - 0.3 * s, y + (k ? 0.3 : -0.1) * s + 0.08 * s * Math.sin(t * 9 + k), cx - hw - 0.55 * s, y + (k ? 0.36 : 0.02) * s);
                    ctx.stroke();
                }
            } else if (variant === "helmet") {
                // casco de obra
                ctx.fillStyle = "#c3c8cf";
                ctx.beginPath();
                ctx.moveTo(cx - 0.8 * s, top + 0.5 * s);
                ctx.bezierCurveTo(cx - 0.78 * s, top - 0.3 * s, cx + 0.78 * s, top - 0.3 * s, cx + 0.8 * s, top + 0.5 * s);
                ctx.closePath();
                ctx.fill();
                ctx.fillStyle = "#9aa1aa";
                ctx.beginPath();
                ctx.roundedRect(cx - 0.98 * s, top + 0.4 * s, 1.96 * s, 0.17 * s, 0.08 * s, 0.08 * s);
                ctx.fill();
                ctx.fillStyle = "rgba(255,255,255,0.45)";
                ctx.beginPath();
                ctx.ellipse(cx - 0.45 * s, top + 0.02 * s, 0.3 * s, 0.14 * s);
                ctx.fill();
            }
        }

        Timer {
            running: ms.visible
            repeat: true
            interval: 2200 + Math.random() * 3800
            onTriggered: {
                ms.blink = 1;
                unblink.restart();
                interval = 2200 + Math.random() * 3800;
            }
        }
        Timer {
            id: unblink

            interval: 110
            onTriggered: ms.blink = 0
        }
    }

    // Un bloque (madera, piedra o hielo; caja o triángulo), con grietas según el daño
    component BlockSprite: Canvas {
        id: bs

        property string mat: "wood"
        property bool tri: false
        property real bw: 20
        property real bh: 20
        property int crack: 0
        property real seed: Math.random() * 1000

        width: Math.ceil(bw) + 4
        height: Math.ceil(bh) + 4
        onCrackChanged: requestPaint()
        onAvailableChanged: if (available) requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.translate(width / 2, height / 2);
            let n = seed;
            const rnd = () => {
                n = (n * 9301 + 49297) % 233280;
                return n / 233280;
            };
            const w = bw, h = bh, r = Math.min(4, Math.min(w, h) * 0.2);
            const path = () => {
                ctx.beginPath();
                if (tri) {
                    ctx.moveTo(-w / 2, h / 2);
                    ctx.lineTo(w / 2, h / 2);
                    ctx.lineTo(0, -h / 2);
                    ctx.closePath();
                } else
                    ctx.roundedRect(-w / 2, -h / 2, w, h, r, r);
            };
            const fill = {
                wood: "#c8955c",
                stone: "#a1a6ab",
                ice: "rgba(178,226,250,0.6)",
                rock: "#5d5752"
            }[mat], edge = {
                wood: "#7d5431",
                stone: "#5e6368",
                ice: "#7cc0e8",
                rock: "#35312d"
            }[mat];
            path();
            ctx.fillStyle = fill;
            ctx.fill();
            ctx.save();
            path();
            ctx.clip();
            if (mat === "wood") {
                // vetas a lo largo
                ctx.strokeStyle = "rgba(125,84,49,0.45)";
                ctx.lineWidth = 1.2;
                const long = w >= h;
                for (let i = 1; i < 4; i++) {
                    const k = i / 4 + (rnd() - 0.5) * 0.08;
                    ctx.beginPath();
                    if (long) {
                        ctx.moveTo(-w / 2, -h / 2 + k * h);
                        ctx.bezierCurveTo(-w / 6, -h / 2 + (k + 0.08) * h, w / 6, -h / 2 + (k - 0.08) * h, w / 2, -h / 2 + k * h);
                    } else {
                        ctx.moveTo(-w / 2 + k * w, -h / 2);
                        ctx.bezierCurveTo(-w / 2 + (k + 0.08) * w, -h / 6, -w / 2 + (k - 0.08) * w, h / 6, -w / 2 + k * w, h / 2);
                    }
                    ctx.stroke();
                }
            } else if (mat === "stone" || mat === "rock") {
                ctx.fillStyle = mat === "rock" ? "rgba(30,26,24,0.3)" : "rgba(70,74,80,0.22)";
                for (let i = 0; i < Math.max(3, w * h / 500); i++) {
                    ctx.beginPath();
                    ctx.ellipse(-w / 2 + rnd() * w, -h / 2 + rnd() * h, 3 + rnd() * 6, 2 + rnd() * 4);
                    ctx.fill();
                }
                ctx.fillStyle = "rgba(255,255,255,0.18)";
                ctx.fillRect(-w / 2, -h / 2, w, Math.min(4, h * 0.2));
            } else {
                // brillos del hielo
                ctx.strokeStyle = "rgba(255,255,255,0.7)";
                ctx.lineWidth = 2;
                for (let i = 0; i < 2; i++) {
                    const x = -w / 2 + (0.2 + 0.35 * i + rnd() * 0.1) * w;
                    ctx.beginPath();
                    ctx.moveTo(x, -h / 2 + 3);
                    ctx.lineTo(x - Math.min(10, h * 0.5), -h / 2 + 3 + Math.min(14, h * 0.7));
                    ctx.stroke();
                }
            }
            // grietas
            if (crack > 0) {
                ctx.strokeStyle = mat === "ice" ? "rgba(255,255,255,0.9)" : "rgba(40,28,20,0.6)";
                ctx.lineWidth = 1.4;
                for (let c = 0; c < crack * 2; c++) {
                    let x = -w / 2 + rnd() * w, y = -h / 2 + rnd() * h;
                    ctx.beginPath();
                    ctx.moveTo(x, y);
                    for (let i = 0; i < 4; i++) {
                        x += (rnd() - 0.5) * Math.min(w, 26);
                        y += (rnd() - 0.5) * Math.min(h, 26);
                        ctx.lineTo(x, y);
                    }
                    ctx.stroke();
                }
            }
            ctx.restore();
            path();
            ctx.strokeStyle = edge;
            ctx.lineWidth = 2;
            ctx.stroke();
        }
    }

    component Bit: Rectangle {
        property real vx: 0
        property real vy: 0
        property real life: 1
        property real max: 1
        property real spin: 0
        property bool fall: true
    }

    component PopText: Text {
        id: pt

        font.family: Theme.font
        font.pixelSize: 22
        font.bold: true
        color: "#ffffff"
        style: Text.Outline
        styleColor: "#40000000"
        Component.onCompleted: popAnim.start()

        ParallelAnimation {
            id: popAnim

            onFinished: pt.destroy()

            NumberAnimation {
                target: pt
                property: "y"
                to: pt.y - 60
                duration: 1100
                easing.type: Easing.OutCubic
            }
            SequentialAnimation {
                PauseAnimation {
                    duration: 650
                }
                NumberAnimation {
                    target: pt
                    property: "opacity"
                    to: 0
                    duration: 450
                }
            }
        }
    }

    component Ring: Rectangle {
        id: rg

        color: "transparent"
        border.width: 6
        border.color: "#ffd27a"
        radius: width / 2
        Component.onCompleted: ringAnim.start()

        ParallelAnimation {
            id: ringAnim

            onFinished: rg.destroy()

            NumberAnimation {
                target: rg
                property: "scale"
                from: 0.2
                to: 1
                duration: 380
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: rg
                property: "opacity"
                from: 1
                to: 0
                duration: 420
            }
        }
    }

    readonly property color bandCol: Theme.error

    Component {
        id: mochiComp

        MochiSprite {
            bodyCol: game.bodyCol
            inkCol: game.inkCol
            bandCol: game.bandCol
        }
    }
    Component {
        id: blockComp

        BlockSprite {}
    }
    Component {
        id: bitComp

        Bit {}
    }
    Component {
        id: popComp

        PopText {}
    }
    Component {
        id: ringComp

        Ring {}
    }

    // ── Generador de estructuras ──
    function pick(a: var): var {
        return a[Math.floor(Math.random() * a.length)];
    }
    // (con el nivel, más piedra y menos hielo)
    function pickMat(): string {
        const r = Math.random(), st = 0.15 + 0.35 * hard, ic = 0.35 - 0.2 * hard;
        return r < st ? "stone" : r < st + ic ? "ice" : "wood";
    }
    function randLook(): var {
        const r = (a, b) => a + Math.random() * (b - a);
        return {
            eyeSize: r(0.8, 1.3),
            eyeGap: r(0.8, 1.2),
            eyeY: r(-0.6, 0.6),
            eyeShape: r(-0.5, 0.8),
            wide: r(0.95, 1.12)
        };
    }
    function pigS(v: string): real {
        return v === "king" ? 0.66 : 0.5;
    }
    function genSpec(): var {
        const P_ = [], t = 0.3, gap = 0.004;
        const k_ = hard, S_ = pick([2.1, 2.4, 2.7]);
        // (nivel 1: 2-3 columnas y 2-3 pisos; al máximo, 3-5 columnas y 3-5 pisos)
        let n = Math.min(5, 2 + Math.floor(Math.random() * (2 + 2 * k_) + k_));
        const room = rightX - slingX - 6;
        while (n > 1 && n * S_ + 1 > room * 0.55)
            n--;
        const x0 = rightX - 1.2 + 0.4 * k_ - Math.random() * (2.8 - 1.6 * k_) - n * S_;
        let levels = 2 + Math.floor(Math.random() * (2 + k_) + k_);
        const maxH = groundY * (0.6 + 0.12 * k_);
        let a = 0, b = n - 1, y = groundY;
        const pig = (x, f, v) => {
            v = v ?? (Math.random() < 0.15 + 0.4 * k_ ? "helmet" : "normal");
            const s = pigS(v);
            P_.push({
                k: "pig",
                v: v,
                x: x,
                y: f - 0.835 * s - gap,
                look: randLook()
            });
        };
        const box = (mat, x, yc, w, h, tri) => P_.push({
                k: tri ? "tri" : "box",
                mat: mat,
                x: x,
                y: yc,
                w: w,
                h: h
            });
        // (desde el nivel 3, a veces sobre un pedestal de roca)
        if (level >= 3 && Math.random() < 0.25 + 0.35 * k_) {
            const ph = 0.8 + Math.random() * (0.8 + 1.4 * k_);
            box("rock", x0 + n * S_ / 2, groundY - ph / 2, n * S_ + 0.8, ph);
            y -= ph;
        }
        // (a veces, sobre una base de piedra)
        if (Math.random() < 0.3) {
            box("stone", x0 + n * S_ / 2, y - 0.25 - gap, n * S_ + 0.5, 0.5);
            y -= 0.5 + 2 * gap;
        }
        for (let k = 0; k < levels; k++) {
            const h = pick([1.5, 1.9, 2.3]);
            if (groundY - (y - h - t) > maxH)
                break;
            const pm = pickMat(), bm = Math.random() < 0.6 ? pm : pickMat();
            for (let i = a; i <= b + 1; i++)
                box(pm, x0 + i * S_, y - h / 2 - gap, t, h);
            for (let j = a; j <= b; j++) {
                const cx = x0 + (j + 0.5) * S_, r = Math.random();
                if (r < 0.55)
                    pig(cx, y);
                else if (r < 0.78) {
                    const m = pickMat(), c = h > 1.7 && Math.random() < 0.5 ? 2 : 1;
                    for (let i = 0; i < c; i++)
                        box(m, cx, y - 0.4 - i * 0.8 - gap * (2 * i + 1), 0.8, 0.8);
                }
            }
            y -= h + 2 * gap;
            for (let j = a; j <= b; j++) {
                const l = x0 + j * S_ - (j === a ? t / 2 : 0), r = x0 + (j + 1) * S_ + (j === b ? t / 2 : 0);
                box(bm, (l + r) / 2, y - t / 2 - gap, r - l - 0.01, t);
            }
            y -= t + 2 * gap;
            if (k < levels - 1) {
                if (b > a && Math.random() < 0.45)
                    a++;
                if (b > a && Math.random() < 0.45)
                    b--;
            }
        }
        // arriba del todo: el rey, tejados, más mochis
        const kingAt = a + Math.floor(Math.random() * (b - a + 1));
        for (let j = a; j <= b; j++) {
            const cx = x0 + (j + 0.5) * S_, r = Math.random();
            if (j === kingAt && Math.random() < 0.4 + 0.5 * k_)
                pig(cx, y, "king");
            else if (r < 0.4)
                pig(cx, y);
            else if (r < 0.75) {
                const w = Math.min(S_ * 0.85, 2.1);
                box(pickMat(), cx, y - 0.5 - gap, w, 1.0, true);
            } else {
                const m = pickMat();
                box(m, cx, y - 0.4 - gap, 0.8, 0.8);
                pig(cx, y - 0.8 - 2 * gap);
            }
        }
        // delante: una columna de roca con un mochi encima (nivel 5+), un montículo de roca que
        // tapa los tiros rasos (nivel 3+), una torrecita suelta o un mochi en el suelo
        const tx = x0 - 2.3, fr = Math.random();
        const mh = 1.2 + Math.random() * (0.6 + 1.2 * k_), mw = 2.6 + mh * 0.6;
        if (level >= 5 && fr < 0.2 + 0.3 * k_ && x0 - 2.6 > slingX + 7) {
            const ch = 2.6 + Math.random() * (1.2 + 2 * k_), cx = x0 - 2.6;
            box("rock", cx, groundY - ch / 2, 1.0, ch);
            pig(cx, groundY - ch);
        } else if (level >= 3 && fr < 0.45 + 0.25 * k_ && x0 - 0.5 - mw > slingX + 5)
            box("rock", x0 - 0.5 - mw / 2, groundY - mh / 2, mw, mh, true);
        else if (Math.random() < 0.55 && tx > slingX + 7) {
            const m = pickMat(), c = 2 + Math.floor(Math.random() * 3);
            for (let i = 0; i < c; i++)
                box(m, tx, groundY - 0.4 - i * 0.8 - gap * (2 * i + 1), 0.8, 0.8);
            pig(tx, groundY - c * 0.8 - 2 * c * gap);
        } else if (Math.random() < 0.5 && x0 - 1.4 > slingX + 6)
            pig(x0 - 1.4, groundY);
        // (al menos dos, cuatro al máximo nivel; como mucho ocho)
        let pigs = P_.filter(p => p.k === "pig");
        while (pigs.length < 2 + Math.round(2 * k_)) {
            const plank = P_.filter(p => p.k === "box" && p.mat !== "rock" && p.w > 1.5 && p.y < groundY - 1 && !P_.some(q => q !== p && Math.abs(q.x - p.x) < 0.8 && q.y < p.y && q.y > p.y - 1.5));
            if (plank.length) {
                const pl = plank[plank.length - 1];
                pig(pl.x, pl.y - pl.h / 2);
            } else if (!P_.some(p => p.mat === "rock" && p.x < x0))
                pig(x0 - 1.4 - pigs.length * 1.3, groundY);
            else
                break;
            pigs = P_.filter(p => p.k === "pig");
        }
        while (pigs.length > 8) {
            P_.splice(P_.indexOf(pigs.pop()), 1);
        }
        // los del tirachinas: uno por mochi de la estructura, más los de sobra del nivel (que
        // pueden ser negativos); con el nivel, menos bombas. El primero, normal
        const nb = Math.max(2, Math.min(6, pigs.length + spare)), birds = ["normal"];
        const pool = ["normal", "fast", "fast", "triple", "triple", "bomb"].concat(hard < 0.5 ? ["bomb"] : ["normal"]);
        while (birds.length < nb)
            birds.push(pick(pool));
        return {
            pieces: P_,
            birds: birds
        };
    }

    // ── Mundo ──
    function pigVerts(s: real): var {
        const pl = P.planck;
        return [20, 75, 105, 160, 205, 245, 295, 335].map(d => {
            const a = d * Math.PI / 180, sn = Math.sin(a);
            return pl.Vec2(s * Math.cos(a), s * (0.14 + (sn < 0 ? 1.0 : 0.72) * sn));
        });
    }
    function clearWorld(): void {
        for (const e of sim.ents.concat(sim.birds))
            e.item?.destroy();
        for (const q of sim.queue)
            q.item?.destroy();
        sim.loaded?.item?.destroy();
        for (const p of sim.parts)
            p.item.destroy();
        sim.ents = [];
        sim.birds = [];
        sim.queue = [];
        sim.loaded = null;
        sim.parts = [];
        sim.dead = [];
        sim.world = null;
        trail.clear();
    }
    function build(spec: var): void {
        clearWorld();
        const pl = P.planck;
        const w = new pl.World({
            gravity: pl.Vec2(0, gravity)
        });
        const g = w.createBody();
        g.createFixture(pl.Edge(pl.Vec2(leftX - 10, groundY), pl.Vec2(rightX + 10, groundY)), {
            friction: 0.9
        });
        g.createFixture(pl.Edge(pl.Vec2(leftX, groundY), pl.Vec2(leftX, -80)), {
            friction: 0.3
        });
        g.createFixture(pl.Edge(pl.Vec2(rightX, groundY), pl.Vec2(rightX, -80)), {
            friction: 0.3
        });
        w.on("post-solve", onImpact);
        sim.world = w;
        sim.armed = false;
        const ents = [];
        for (const d of spec.pieces) {
            const rock = d.mat === "rock";
            const b = w.createBody({
                type: rock ? "static" : "dynamic",
                position: pl.Vec2(d.x, d.y)
            });
            const e = {
                d: d,
                body: b,
                kind: d.k === "pig" ? "pig" : rock ? "rock" : "block",
                item: null,
                gone: false
            };
            if (e.kind === "pig") {
                const s = pigS(d.v);
                b.createFixture(pl.Polygon(pigVerts(s)), {
                    density: 0.8,
                    friction: 0.8,
                    restitution: 0.05
                });
                b.setAngularDamping(0.4);
                e.hp = e.hp0 = (d.v === "king" ? 8 : d.v === "helmet" ? 6 : 2.6) * (1 + 0.8 * hard);
                e.thr = 0.9;
            } else if (rock) {
                const shape = d.k === "tri" ? pl.Polygon([pl.Vec2(-d.w / 2, d.h / 2), pl.Vec2(d.w / 2, d.h / 2), pl.Vec2(0, -d.h / 2)]) : pl.Box(d.w / 2, d.h / 2);
                b.createFixture(shape, {
                    friction: 0.9,
                    restitution: 0.05
                });
                e.mat = "rock";
            } else {
                const m = mats[d.mat];
                const shape = d.k === "tri" ? pl.Polygon([pl.Vec2(-d.w / 2, d.h / 2), pl.Vec2(d.w / 2, d.h / 2), pl.Vec2(0, -d.h / 2)]) : pl.Box(d.w / 2, d.h / 2);
                b.createFixture(shape, {
                    density: m.density,
                    friction: m.friction,
                    restitution: 0.02
                });
                e.mat = d.mat;
                e.hp = e.hp0 = m.hp * Math.max(0.6, Math.min(1.6, d.w * d.h / 0.7)) * (1 + 0.5 * hard);
                e.thr = m.thr;
            }
            b.setUserData(e);
            ents.push(e);
        }
        sim.ents = ents;
    }
    // (deja que se asiente sin romper nada; lo que más se ha movido: si pasa de 0.3, no vale)
    function settles(): real {
        for (let i = 0; i < 240; i++)
            sim.world.step(step, 8, 3);
        let m = 0;
        for (const e of sim.ents) {
            const p = e.body.getPosition();
            m = Math.max(m, Math.hypot(p.x - e.d.x, p.y - e.d.y), Math.abs(e.body.getAngle()));
        }
        return m;
    }
    function makeItems(): void {
        for (const e of sim.ents) {
            const d = e.d;
            if (e.kind === "pig")
                e.item = mochiComp.createObject(world2d, {
                    s: pigS(d.v) * ppm,
                    face: "smug",
                    look: d.look,
                    variant: d.v,
                    hatName: d.v === "king" ? "crown" : "",
                    z: 2
                });
            else
                e.item = blockComp.createObject(world2d, {
                    mat: d.mat,
                    tri: d.k === "tri",
                    bw: d.w * ppm,
                    bh: d.h * ppm,
                    z: 2
                });
            e.body.setAwake(true);
        }
        sync();
    }
    function newLevel(retry: bool): void {
        // (las grandes fallan más: hasta 16 intentos y, si ninguno se tiene en pie, la más estable)
        let spec = retry ? sim.spec : null, bestSpec = null, bestM = 1e9;
        sim.tries = 0;
        for (let tries = 0; tries < 16; tries++) {
            if (!retry)
                spec = genSpec();
            build(spec);
            sim.tries++;
            const m = settles();
            if (m <= 0.3 || retry)
                break;
            if (m < bestM) {
                bestM = m;
                bestSpec = spec;
            }
            if (tries === 15) {
                spec = bestSpec;
                build(spec);
                settles();
            }
        }
        sim.spec = spec;
        makeItems();
        sim.armed = true;
        score = 0;
        pigsLeft = sim.ents.filter(e => e.kind === "pig").length;
        // la fila de mochis del tirachinas
        sim.queue = spec.birds.map((type, i) => ({
                    type: type,
                    item: mochiComp.createObject(world2d, {
                        s: birdR[type] * 1.05 * ppm,
                        face: "angry",
                        look: Look.data(),
                        variant: type,
                        hatName: type === "triple" ? "party" : "",
                        z: 3
                    })
                }));
        placeQueue(false);
        birdsLeft = sim.queue.length;
        showCard = false;
        meFace = "curious";
        phase = "load";
        world2d.opacity = 0;
        appear.restart();
        bannerAnim.restart();
        nextTimer.interval = 700;
        nextTimer.restart();
    }
    // (si son muchos, más juntitos para que no se metan debajo de la barra)
    function slotX(i: int): real {
        const n = sim.queue.length;
        return slingX - 2.6 - i * (n > 1 ? Math.min(1.0, (slingX - 2.6 - leftX - 0.7) / (n - 1)) : 1.0);
    }
    function placeQueue(anim: bool): void {
        sim.queue.forEach((q, i) => {
            const it = q.item, r = birdR[q.type];
            it.x = slotX(i) * ppm - it.width / 2;
            it.y = (groundY - 0.86 * r * 1.05) * ppm - it.height / 2;
        });
    }

    // Golpes: cada contacto reparte su impulso; si pasa del umbral, hace daño
    function onImpact(c: var, imp: var): void {
        const ua = c.getFixtureA().getBody().getUserData(), ub = c.getFixtureB().getBody().getUserData();
        let n = 0;
        for (let i = 0; i < imp.normalImpulses.length; i++)
            n = Math.max(n, imp.normalImpulses[i] || 0);
        if (ua)
            hurt(ua, n, ub);
        if (ub)
            hurt(ub, n, ua);
    }
    function hurt(e: var, n: real, other: var): void {
        if (e.gone)
            return;
        if (e.kind === "rock")
            return;
        if (e.kind === "bird") {
            if (n > 0.3 && !e.touched) {
                e.touched = true;
                e.touchAge = e.age;
                e.item.face = "squint";
                // (al chocar ya no vuela: frena rodando en vez de irse al otro lado)
                e.body.setLinearDamping(0.5);
                e.body.setAngularDamping(3);
            }
            return;
        }
        if (!sim.armed || n <= e.thr)
            return;
        let d = n - e.thr;
        if (other?.kind === "bird")
            d *= birdVs[other.type][e.kind === "pig" ? "pig" : e.mat];
        damage(e, d);
    }
    function damage(e: var, d: real): void {
        if (e.gone || e.kind === "rock")
            return;
        e.hp -= d;
        if (e.hp <= 0) {
            e.gone = true;
            sim.dead.push(e);
            return;
        }
        const k = 1 - e.hp / e.hp0;
        if (e.kind === "block")
            e.item.crack = k > 0.66 ? 2 : k > 0.3 ? 1 : 0;
        else if (k > 0.35)
            e.hurt = true;
    }
    function reap(): void {
        if (!sim.dead.length)
            return;
        const dead = sim.dead;
        sim.dead = [];
        for (const e of dead) {
            const p = e.body.getPosition();
            sim.world.destroyBody(e.body);
            if (e.kind === "pig") {
                burst(p.x, p.y, bodyCol, 14, 1.2, true);
                popup(p.x, p.y - 0.6, "5000", false);
                score += 5000;
                pigsLeft--;
                meReact("happy", 900);
            } else if (e.kind === "block") {
                burst(p.x, p.y, mats[e.mat].bit, 10, Math.min(1.4, Math.max(e.d.w, e.d.h) / 2), false);
                score += mats[e.mat].pts;
                popup(p.x, p.y - 0.3, String(mats[e.mat].pts), true);
            } else
                burst(p.x, p.y, bodyCol, 8, 0.6, true);
            e.item?.destroy();
            e.item = null;
        }
        sim.ents = sim.ents.filter(e => !e.gone);
        sim.birds = sim.birds.filter(e => !e.gone);
    }

    // ── Efectos ──
    function burst(x: real, y: real, col: string, count: int, spread: real, round: bool): void {
        for (let i = 0; i < count; i++) {
            const sz = (round ? 0.14 + Math.random() * 0.2 : 0.08 + Math.random() * 0.18) * ppm, a = Math.random() * 2 * Math.PI, v = 2 + Math.random() * 5;
            const it = bitComp.createObject(world2d, {
                width: sz,
                height: round ? sz : sz * 0.6,
                radius: round ? sz / 2 : 1,
                color: col,
                x: (x + Math.cos(a) * spread * 0.4) * ppm,
                y: (y + Math.sin(a) * spread * 0.4) * ppm,
                z: 4
            });
            sim.parts.push({
                item: it,
                vx: Math.cos(a) * v,
                vy: Math.sin(a) * v - 3,
                life: 0.7 + Math.random() * 0.5,
                max: 1.2,
                spin: (Math.random() - 0.5) * 720,
                fall: !round
            });
        }
    }
    function popup(x: real, y: real, txt: string, small: bool): void {
        const it = popComp.createObject(world2d, {
            text: txt,
            z: 6
        });
        it.font.pixelSize = small ? 16 : 24;
        it.x = x * ppm - it.implicitWidth / 2;
        it.y = y * ppm;
    }
    function tickParts(dt: real): void {
        const keep = [];
        for (const p of sim.parts) {
            p.life -= dt;
            if (p.life <= 0) {
                p.item.destroy();
                continue;
            }
            p.vy += (p.fall ? gravity : -1.5) * dt;
            p.vx *= p.fall ? 1 : 0.94;
            p.item.x += p.vx * ppm * dt;
            p.item.y += p.vy * ppm * dt;
            p.item.rotation += p.spin * dt;
            p.item.opacity = Math.min(1, p.life * 2.5);
            keep.push(p);
        }
        sim.parts = keep;
    }

    // ── El tirachinas ──
    function loadNext(): void {
        if (!sim.queue.length)
            return;
        snapBack.stop();
        pouchX = anchorX * ppm;
        pouchY = anchorY * ppm;
        sim.loaded = sim.queue.shift();
        const it = sim.loaded.item;
        sim.loaded.fromX = it.x + it.width / 2;
        sim.loaded.fromY = it.y + it.height / 2;
        birdsLeft = sim.queue.length + 1;
        placeQueue(true);
        phase = "load";
        loadT = 0;
        loadAnim.restart();
    }
    onLoadTChanged: {
        const L = sim.loaded;
        if (!L || phase !== "load")
            return;
        const k = loadT, x = L.fromX + (pouchX - L.fromX) * k, y = L.fromY + (pouchY - L.fromY) * k - Math.sin(k * Math.PI) * 1.6 * ppm;
        L.item.x = x - L.item.width / 2;
        L.item.y = y - L.item.height / 2;
        L.item.rotation = k * 360;
    }
    NumberAnimation {
        id: loadAnim

        target: game
        property: "loadT"
        from: 0
        to: 1
        duration: 520
        easing.type: Easing.InOutQuad
        onFinished: {
            game.phase = "aim";
            game.syncLoaded();
        }
    }
    function syncLoaded(): void {
        const L = sim.loaded;
        if (!L || phase !== "aim")
            return;
        L.item.x = pouchX - L.item.width / 2;
        L.item.y = pouchY - L.item.height / 2;
        L.item.rotation = aiming ? Math.atan2(anchorY * ppm - pouchY, anchorX * ppm - pouchX) * 180 / Math.PI : 0;
    }
    onPouchXChanged: {
        syncLoaded();
        bandsBack.requestPaint();
        bandsFront.requestPaint();
    }
    onPouchYChanged: {
        syncLoaded();
        bandsBack.requestPaint();
        bandsFront.requestPaint();
    }
    function dragTo(mx: real, my: real): void {
        let dx = mx / ppm - anchorX, dy = my / ppm - anchorY;
        const r = birdR[sim.loaded.type], l = Math.hypot(dx, dy);
        if (l > maxDrag) {
            dx *= maxDrag / l;
            dy *= maxDrag / l;
        }
        dy = Math.min(dy, groundY - r - anchorY);
        pouchX = (anchorX + dx) * ppm;
        pouchY = (anchorY + dy) * ppm;
        // por dónde irá (el primer tramo; más corto cuanto más alto el nivel)
        const vx = -dx * power, vy = -dy * power, pts = [];
        if (Math.hypot(dx, dy) > 0.3)
            for (let i = 1; i <= aimDots; i++) {
                const t = i * 0.055;
                pts.push({
                    x: (anchorX + dx + vx * t) * ppm,
                    y: (anchorY + dy + vy * t + 0.5 * gravity * t * t) * ppm,
                    k: 1 - i / (aimDots + 1)
                });
            }
        aimPts = pts;
        meLx = Math.max(-1, Math.min(1, (pouchX - meX()) / 80));
        meLy = Math.max(-1, Math.min(1, (pouchY - meY()) / 80));
    }
    function launch(): void {
        const pl = P.planck, L = sim.loaded, dx = pouchX / ppm - anchorX, dy = pouchY / ppm - anchorY;
        aimPts = [];
        if (Math.hypot(dx, dy) < 0.35) {
            snapBack.restart();
            return;
        }
        sim.loaded = null;
        const r = birdR[L.type];
        const b = sim.world.createBody({
            type: "dynamic",
            position: pl.Vec2(pouchX / ppm, pouchY / ppm),
            bullet: true
        });
        b.createFixture(pl.Circle(r), {
            density: birdDensity[L.type],
            friction: 0.6,
            restitution: 0.25
        });
        b.setAngularDamping(0.8);
        b.setLinearVelocity(pl.Vec2(-dx * power, -dy * power));
        const e = {
            kind: "bird",
            type: L.type,
            body: b,
            item: L.item,
            touched: false,
            used: false,
            age: 0,
            slow: 0,
            fuse: 0,
            gone: false
        };
        b.setUserData(e);
        sim.birds = [e];
        birdsLeft = sim.queue.length;
        trail.clear();
        sim.trailT = 0;
        hint = false;
        phase = "fly";
        meReact("excited", 1400);
        snapBack.restart();
    }
    ParallelAnimation {
        id: snapBack

        NumberAnimation {
            target: game
            property: "pouchX"
            to: game.anchorX * game.ppm
            duration: 420
            easing.type: Easing.OutElastic
            easing.amplitude: 1.2
            easing.period: 0.4
        }
        NumberAnimation {
            target: game
            property: "pouchY"
            to: game.anchorY * game.ppm
            duration: 420
            easing.type: Easing.OutElastic
            easing.amplitude: 1.2
            easing.period: 0.4
        }
    }
    // Clic en el aire: la habilidad de cada uno (una vez)
    function ability(): void {
        const e = sim.birds.find(b => !b.gone && !b.used);
        if (!e || e.type === "normal")
            return;
        const pl = P.planck, v = e.body.getLinearVelocity(), p = e.body.getPosition();
        if (e.type === "bomb") {
            explode(e);
            return;
        }
        if (e.touched)
            return;
        e.used = true;
        if (e.type === "fast") {
            const sp = Math.hypot(v.x, v.y) || 1, to = Math.max(sp * 2, 26);
            e.body.setLinearVelocity(pl.Vec2(v.x / sp * to, v.y / sp * to));
            burst(p.x, p.y, "#ffffff", 8, 0.5, true);
        } else if (e.type === "triple") {
            burst(p.x, p.y, "#ffffff", 8, 0.5, true);
            for (const da of [-0.2, 0.2]) {
                const c = Math.cos(da), s = Math.sin(da);
                const b = sim.world.createBody({
                    type: "dynamic",
                    position: pl.Vec2(p.x, p.y + da * 1.6),
                    bullet: true
                });
                b.createFixture(pl.Circle(birdR.triple), {
                    density: birdDensity.triple,
                    friction: 0.6,
                    restitution: 0.25
                });
                b.setLinearVelocity(pl.Vec2(v.x * c - v.y * s, v.x * s + v.y * c));
                const n = {
                    kind: "bird",
                    type: "triple",
                    body: b,
                    item: mochiComp.createObject(world2d, {
                        s: birdR.triple * 1.05 * ppm,
                        face: "angry",
                        look: Look.data(),
                        variant: "triple",
                        hatName: "party",
                        z: 3
                    }),
                    touched: false,
                    used: true,
                    age: e.age,
                    slow: 0,
                    fuse: 0,
                    gone: false
                };
                b.setUserData(n);
                sim.birds.push(n);
            }
        }
    }
    function explode(e: var): void {
        if (e.gone)
            return;
        const pl = P.planck, c = e.body.getPosition(), R = 3.4;
        for (const o of sim.ents) {
            if (o.gone || o.kind === "rock")
                continue;
            const p = o.body.getWorldCenter(), dx = p.x - c.x, dy = p.y - c.y, d = Math.max(0.2, Math.hypot(dx, dy));
            if (d > R)
                continue;
            const f = 1 - d / R, m = o.body.getMass(), imp = f * 15 * Math.pow(m, 0.8);
            o.body.applyLinearImpulse(pl.Vec2(dx / d * imp, dy / d * imp - imp * 0.25), p, true);
            damage(o, f * (o.kind === "pig" ? 8 : o.mat === "stone" ? 40 : 14));
        }
        const it = ringComp.createObject(world2d, {
            width: R * 2 * ppm,
            height: R * 2 * ppm,
            x: (c.x - R) * ppm,
            y: (c.y - R) * ppm,
            z: 5
        });
        burst(c.x, c.y, "#ffb13b", 14, 1.4, true);
        burst(c.x, c.y, "#6b6b70", 10, 1.4, true);
        e.gone = true;
        sim.dead.push(e);
    }

    // ── Bucle ──
    FrameAnimation {
        running: game.visible && sim.world !== null
        onTriggered: game.tick(Math.min(frameTime, 0.05))
    }
    function tick(dt: real): void {
        clock += dt;
        sim.acc += dt;
        let n = 0;
        while (sim.acc >= step && n < 4) {
            sim.world.step(step, 8, 3);
            sim.acc -= step;
            n++;
            reap();
            bounds();
        }
        if (n === 4)
            sim.acc = 0;
        sync();
        tickParts(dt);
        logic(dt);
        faces();
    }
    function sync(): void {
        for (const e of sim.ents.concat(sim.birds)) {
            if (!e.item || (!e.body.isAwake() && e.synced))
                continue;
            const p = e.body.getPosition();
            e.item.x = p.x * ppm - e.item.width / 2;
            e.item.y = p.y * ppm - e.item.height / 2;
            e.item.rotation = e.body.getAngle() * 180 / Math.PI;
            e.synced = true;
        }
    }
    // (lo que se sale de la pantalla, fuera)
    function bounds(): void {
        for (const e of sim.ents.concat(sim.birds)) {
            if (e.gone)
                continue;
            const p = e.body.getPosition();
            if (p.y > groundY + 3 || p.x < leftX - 3 || p.x > rightX + 3 || p.y < -60) {
                e.gone = true;
                sim.dead.push(e);
            }
        }
        reap();
    }
    function maxSpeed(): real {
        let m = 0;
        for (const e of sim.ents) {
            if (!e.body.isAwake())
                continue;
            const v = e.body.getLinearVelocity();
            m = Math.max(m, Math.hypot(v.x, v.y));
        }
        return m;
    }
    function logic(dt: real): void {
        if (phase === "fly") {
            let live = 0;
            for (const b of sim.birds) {
                if (b.gone)
                    continue;
                b.age += dt;
                const v = b.body.getLinearVelocity(), sp = Math.hypot(v.x, v.y), p = b.body.getPosition();
                b.slow = b.touched && sp < 0.5 ? b.slow + dt : 0;
                if (b.type === "bomb" && b.touched && !b.gone) {
                    b.fuse += dt;
                    if (b.fuse > 1.4)
                        explode(b);
                }
                if (!b.touched && b === sim.birds[0]) {
                    sim.trailT -= dt;
                    if (sim.trailT <= 0) {
                        sim.trailT = 0.045;
                        trail.append({
                            px: p.x * ppm,
                            py: p.y * ppm,
                            r: (trail.count % 3 === 0 ? 7 : 4)
                        });
                    }
                }
                if (b.slow > 0.7 || b.age > 10 || (b.touched && b.age - b.touchAge > 4.5) || (pigsLeft === 0 && b.age > 1.5)) {
                    b.gone = true;
                    sim.dead.push(b);
                    continue;
                }
                live++;
            }
            reap();
            if (!live) {
                phase = "settle";
                sim.settleT = 0;
                sim.quiet = 0;
            }
        } else if (phase === "settle") {
            sim.settleT += dt;
            sim.quiet = maxSpeed() < 0.25 ? sim.quiet + dt : 0;
            if (sim.quiet > 0.4 || sim.settleT > 4.5 || (pigsLeft === 0 && sim.settleT > 0.8))
                decide();
        } else if (phase === "aim" && pigsLeft === 0) {
            decide();
        } else if (phase === "lost" && pigsLeft === 0) {
            // (el último se ha caído solo después: al final sí)
            showCard = false;
            win();
        } else if (phase === "lost") {
            // se ríen de ti: saltitos
            sim.laughT -= dt;
            if (sim.laughT <= 0) {
                sim.laughT = 0.9;
                const pl = P.planck;
                for (const e of sim.ents)
                    if (e.kind === "pig" && Math.random() < 0.7) {
                        e.body.setAwake(true);
                        e.body.applyLinearImpulse(pl.Vec2(0, -e.body.getMass() * (3 + Math.random() * 1.5)), e.body.getWorldCenter(), true);
                    }
            }
        }
    }
    function decide(): void {
        if (pigsLeft === 0)
            win();
        else if (sim.queue.length)
            loadNext();
        else
            lose();
    }
    function win(): void {
        phase = "won";
        const left = sim.queue.length + (sim.loaded ? 1 : 0);
        sim.queue.concat(sim.loaded ? [sim.loaded] : []).forEach((q, i) => {
            const it = q.item;
            it.face = "happy";
            popup((it.x + it.width / 2) / ppm, it.y / ppm, "10000", false);
            score += 10000;
        });
        // (cuando no sobran tiros, ganar con uno de sobra ya son tres estrellas)
        stars = 1 + Math.min(2, left + (spare <= 0 ? 1 : 0));
        meFace = "love";
        birdsLeft = 0;
        const b = Object.assign({}, best);
        b[level] = Math.max(b[level] ?? 0, stars);
        best = b;
        maxLevel = Math.max(maxLevel, level + 1);
        save();
        cardTimer.restart();
        game.won(stars);
    }
    function lose(): void {
        phase = "lost";
        stars = 0;
        meFace = "sad";
        sim.laughT = 0.3;
        cardTimer.restart();
    }
    Timer {
        id: cardTimer

        interval: 900
        onTriggered: game.showCard = true
    }
    Timer {
        id: nextTimer

        onTriggered: game.loadNext()
    }
    Timer {
        id: meTimer

        onTriggered: if (game.phase !== "won" && game.phase !== "lost") game.meFace = "curious"
    }
    function meReact(f: string, ms: int): void {
        if (phase === "won" || phase === "lost")
            return;
        meFace = f;
        meTimer.interval = ms;
        meTimer.restart();
    }
    function meX(): real {
        return (slingX - 1.3) * ppm;
    }
    function meY(): real {
        return (groundY - 0.86 * 0.62) * ppm;
    }
    // Caras: los de la estructura miran al que vuela (o al tirachinas)
    function faces(): void {
        const b = sim.birds.find(x => !x.gone);
        const tx = b ? b.body.getPosition().x * ppm : pouchX, ty = b ? b.body.getPosition().y * ppm : pouchY;
        const q = v => Math.round(Math.max(-1, Math.min(1, v)) * 5) / 5;
        for (const e of sim.ents) {
            if (e.kind !== "pig" || !e.item)
                continue;
            const it = e.item, cx = it.x + it.width / 2, cy = it.y + it.height / 2;
            const a = -e.body.getAngle(), dx = tx - cx, dy = ty - cy, d = Math.hypot(dx, dy) || 1;
            it.lx = q((dx * Math.cos(a) - dy * Math.sin(a)) / d);
            it.ly = q((dx * Math.sin(a) + dy * Math.cos(a)) / d * 0.8);
            it.face = phase === "lost" ? "happy" : e.hurt ? "sad" : b && d < 5 * ppm ? "surprised" : "smug";
        }
        for (const x of sim.birds)
            if (!x.gone && x.type === "bomb")
                x.item.t = clock;
        if (sim.loaded?.type === "bomb")
            sim.loaded.item.t = clock;
        if (b) {
            meLx = q((tx - meX()) / 300);
            meLy = q((ty - meY()) / 300);
        } else if (!aiming && phase !== "won" && phase !== "lost") {
            meLx = 0.6;
            meLy = -0.2;
        }
        me.t = clock;
    }

    // ── Empezar y terminar ──
    property bool started: false
    readonly property bool sized: sw > 200 && sh > 200
    onSizedChanged: start()
    Component.onCompleted: start()
    function start(): void {
        if (started || !sized)
            return;
        started = true;
        loadSave();
        newLevel(false);
    }
    function quit(): void {
        fadeOut.restart();
    }
    NumberAnimation {
        id: appear

        target: world2d
        property: "opacity"
        from: 0
        to: 1
        duration: 450
    }
    NumberAnimation {
        id: fadeOut

        target: root
        property: "opacity"
        to: 0
        duration: 260
        onFinished: {
            game.clearWorld();
            game.finished();
        }
    }

    // ── Escena ──
    Item {
        id: root

        anchors.fill: parent
        focus: true
        opacity: 0
        Component.onCompleted: {
            forceActiveFocus();
            fadeIn.start();
        }
        NumberAnimation {
            id: fadeIn

            target: root
            property: "opacity"
            to: 1
            duration: 300
        }
        Keys.onPressed: ev => {
            if (ev.key === Qt.Key_Escape || ev.key === Qt.Key_Q)
                game.quit();
            else if (ev.key === Qt.Key_R)
                game.newLevel(true);
            else if (ev.key === Qt.Key_N)
                game.newLevel(false);
            else if (ev.key === Qt.Key_Left && game.level > 1)
                game.goLevel(game.level - 1);
            else if (ev.key === Qt.Key_Right && game.level < game.maxLevel)
                game.goLevel(game.level + 1);
            else if (ev.key === Qt.Key_Space && game.phase === "fly")
                game.ability();
            ev.accepted = true;
        }

        // velo para que se vea bien encima de cualquier fondo
        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: 0.32
        }

        // estela del último tiro
        Repeater {
            model: ListModel {
                id: trail
            }
            Rectangle {
                required property real px
                required property real py
                required property real r

                x: px - r
                y: py - r
                width: r * 2
                height: r * 2
                radius: r
                color: "#ffffff"
                opacity: 0.55
            }
        }

        // por dónde irá
        Repeater {
            model: game.aimPts
            Rectangle {
                required property var modelData

                x: modelData.x - 3
                y: modelData.y - 3
                width: 6
                height: 6
                radius: 3
                color: "#ffffff"
                opacity: 0.2 + 0.6 * modelData.k
            }
        }

        // tirachinas, por detrás (brazo y goma de atrás, y el bolsillo)
        Canvas {
            id: bandsBack

            readonly property real ox: (game.anchorX - 3.4) * game.ppm
            readonly property real oy: (game.anchorY - 3) * game.ppm
            x: ox
            y: oy
            z: 1
            width: 5.2 * game.ppm
            height: (game.groundY - game.anchorY + 3.2) * game.ppm
            onAvailableChanged: if (available) requestPaint()
            onPaint: {
                const ctx = getContext("2d"), k = game.ppm;
                ctx.reset();
                ctx.translate(-ox, -oy);
                const fx = game.slingX * k, fy = (game.groundY - 1.45) * k;
                const bt = [(game.slingX - 0.3) * k, (game.anchorY - 0.1) * k];
                ctx.lineCap = "round";
                ctx.strokeStyle = "#6e4527";
                ctx.lineWidth = 0.2 * k;
                ctx.beginPath();
                ctx.moveTo(fx, fy);
                ctx.quadraticCurveTo(fx - 0.25 * k, fy - 0.4 * k, bt[0], bt[1]);
                ctx.stroke();
                const px = game.pouchX, py = game.pouchY, r = (game.loadedR() || 0.42) * k;
                ctx.strokeStyle = "#3b2416";
                ctx.lineWidth = 0.13 * k;
                ctx.beginPath();
                ctx.moveTo(bt[0], bt[1]);
                ctx.lineTo(px - r * 0.3, py);
                ctx.stroke();
                // bolsillo de cuero (detrás del que va cargado)
                ctx.fillStyle = "#4a2f1d";
                ctx.beginPath();
                ctx.ellipse(px - r * 1.05, py - r * 0.75, r * 0.9, r * 1.5);
                ctx.fill();
            }
        }

        Item {
            id: world2d

            anchors.fill: parent
            z: 2
        }

        // Mochi, al lado de su tirachinas
        MochiSprite {
            id: me

            z: 3
            bodyCol: game.bodyCol
            inkCol: game.inkCol
            s: 0.62 * game.ppm
            x: game.meX() - width / 2
            y: game.meY() - height / 2
            face: game.meFace
            lx: game.meLx
            ly: game.meLy
            look: Look.data()
            hatName: game.hat
            skin: Wardrobe.wearing
            stage: Bond.stage
        }

        // tirachinas, por delante (tronco, brazo y goma de delante)
        Canvas {
            id: bandsFront

            readonly property real ox: (game.anchorX - 3.4) * game.ppm
            readonly property real oy: (game.anchorY - 3) * game.ppm
            x: ox
            y: oy
            z: 4
            width: 5.2 * game.ppm
            height: (game.groundY - game.anchorY + 3.2) * game.ppm
            onAvailableChanged: if (available) requestPaint()
            onPaint: {
                const ctx = getContext("2d"), k = game.ppm;
                ctx.reset();
                ctx.translate(-ox, -oy);
                const gx = game.slingX * k, gy = game.groundY * k, fx = gx, fy = (game.groundY - 1.45) * k;
                const ft = [(game.slingX + 0.28) * k, (game.anchorY - 0.05) * k];
                const px = game.pouchX, py = game.pouchY, r = (game.loadedR() || 0.42) * k;
                ctx.lineCap = "round";
                // goma de delante (va por delante del que está cargado)
                ctx.strokeStyle = "#4a2d1b";
                ctx.lineWidth = 0.15 * k;
                ctx.beginPath();
                ctx.moveTo(ft[0], ft[1]);
                ctx.lineTo(px - r * 0.7, py + r * 0.15);
                ctx.stroke();
                // tronco y brazo de delante
                ctx.strokeStyle = "#8a5a35";
                ctx.lineWidth = 0.28 * k;
                ctx.beginPath();
                ctx.moveTo(gx, gy);
                ctx.lineTo(fx, fy);
                ctx.stroke();
                ctx.lineWidth = 0.21 * k;
                ctx.beginPath();
                ctx.moveTo(fx, fy);
                ctx.quadraticCurveTo(fx + 0.25 * k, fy - 0.45 * k, ft[0], ft[1]);
                ctx.stroke();
                ctx.strokeStyle = "rgba(255,255,255,0.18)";
                ctx.lineWidth = 0.06 * k;
                ctx.beginPath();
                ctx.moveTo(gx - 0.06 * k, gy - 0.1 * k);
                ctx.lineTo(fx - 0.06 * k, fy);
                ctx.stroke();
            }
        }

        MouseArea {
            anchors.fill: parent
            z: 10
            cursorShape: game.aiming ? Qt.ClosedHandCursor : Qt.ArrowCursor
            onPressed: m => {
                if (game.phase === "aim" && sim.loaded && Math.hypot(m.x - game.pouchX, m.y - game.pouchY) < 1.4 * game.ppm) {
                    snapBack.stop();
                    game.aiming = true;
                    game.dragTo(m.x, m.y);
                } else if (game.phase === "fly")
                    game.ability();
            }
            onPositionChanged: m => {
                if (game.aiming)
                    game.dragTo(m.x, m.y);
            }
            onReleased: {
                if (!game.aiming)
                    return;
                game.aiming = false;
                game.launch();
            }
        }

        // ── Marcador ──
        Rectangle {
            id: hud

            z: 11
            anchors.horizontalCenter: parent.horizontalCenter
            y: game.frame + 18
            height: 44
            width: hudRow.implicitWidth + 36
            radius: 22
            color: Qt.alpha(Theme.surfaceContainer, 0.92)

            Row {
                id: hudRow

                anchors.centerIn: parent
                spacing: 18

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Angry Mochis"
                    font.family: Theme.font
                    font.pixelSize: 17
                    font.bold: true
                    color: Theme.primary
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: `Nivel ${game.level}` + (game.best[game.level] ? "  " + "★".repeat(game.best[game.level]) : "")
                    font.family: Theme.font
                    font.pixelSize: 15
                    font.bold: true
                    color: Theme.onSurface
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: `${game.pigsLeft} ${game.pigsLeft === 1 ? "mochi" : "mochis"} por derribar`
                    font.family: Theme.font
                    font.pixelSize: 15
                    color: Theme.onSurface
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: `${game.birdsLeft} ${game.birdsLeft === 1 ? "tiro" : "tiros"}`
                    font.family: Theme.font
                    font.pixelSize: 15
                    color: Theme.onSurface
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: game.score.toLocaleString(Qt.locale("es_ES"), "f", 0) + " pts"
                    font.family: Theme.font
                    font.pixelSize: 15
                    font.bold: true
                    color: Theme.onSurface
                }
            }
        }
        Row {
            z: 11
            anchors.right: parent.right
            anchors.rightMargin: game.frame + 18
            y: game.frame + 18
            spacing: 8

            Repeater {
                model: [
                    {
                        icon: "replay",
                        act: "retry"
                    },
                    {
                        icon: "casino",
                        act: "new"
                    },
                    {
                        icon: "close",
                        act: "quit"
                    }
                ]
                Rectangle {
                    required property var modelData

                    width: 44
                    height: 44
                    radius: 22
                    color: hb.containsMouse ? Qt.alpha(Theme.primaryContainer, 0.95) : Qt.alpha(Theme.surfaceContainer, 0.92)

                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData.icon
                        font.family: Theme.icons
                        font.pixelSize: 22
                        color: Theme.onSurface
                    }
                    MouseArea {
                        id: hb

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: game.act(parent.modelData.act)
                    }
                }
            }
        }
        Text {
            z: 11
            visible: game.hint
            anchors.horizontalCenter: parent.horizontalCenter
            y: hud.y + hud.height + 12
            text: "Arrastra hacia atrás al mochi del tirachinas y suelta · clic en el aire: su habilidad · R repetir · N otra estructura · ← → cambiar de nivel · Esc salir"
            font.family: Theme.font
            font.pixelSize: 14
            color: "#ffffff"
            style: Text.Outline
            styleColor: "#60000000"
        }

        // ── Cartel al empezar cada nivel ──
        Column {
            id: banner

            z: 11
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -parent.height * 0.18
            spacing: 6
            opacity: 0

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: `Nivel ${game.level}`
                font.family: Theme.font
                font.pixelSize: 54
                font.bold: true
                color: "#ffffff"
                style: Text.Outline
                styleColor: "#60000000"
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: `${game.pigsLeft} mochis · ${game.birdsLeft} tiros`
                font.family: Theme.font
                font.pixelSize: 18
                color: "#ffffff"
                style: Text.Outline
                styleColor: "#60000000"
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: text !== ""
                text: game.news[game.level] ?? ""
                font.family: Theme.font
                font.pixelSize: 18
                font.bold: true
                color: "#ffc93c"
                style: Text.Outline
                styleColor: "#60000000"
            }
        }
        SequentialAnimation {
            id: bannerAnim

            NumberAnimation {
                target: banner
                property: "opacity"
                from: 0
                to: 1
                duration: 250
            }
            PauseAnimation {
                duration: 1500
            }
            NumberAnimation {
                target: banner
                property: "opacity"
                to: 0
                duration: 450
            }
        }

        // ── Resultado ──
        Rectangle {
            z: 12
            visible: game.showCard
            anchors.centerIn: parent
            width: 420
            height: cardCol.implicitHeight + 48
            radius: 28
            color: Qt.alpha(Theme.surfaceContainer, 0.97)
            scale: visible ? 1 : 0.8
            Behavior on scale {
                NumberAnimation {
                    duration: 260
                    easing.type: Easing.OutBack
                }
            }

            Column {
                id: cardCol

                anchors.centerIn: parent
                spacing: 14

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: game.phase === "won" ? `¡Nivel ${game.level} superado!` : "Se te han acabado los tiros"
                    font.family: Theme.font
                    font.pixelSize: 24
                    font.bold: true
                    color: Theme.onSurface
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: game.phase === "won"
                    text: "★".repeat(game.stars) + "☆".repeat(3 - game.stars)
                    font.pixelSize: 40
                    color: "#ffc93c"
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: game.phase === "won" ? game.score.toLocaleString(Qt.locale("es_ES"), "f", 0) + " puntos" : `Quedan ${game.pigsLeft} mochis riéndose de ti`
                    font.family: Theme.font
                    font.pixelSize: 16
                    color: Theme.onSurfaceVariant
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10

                    // (el del medio es el principal: siguiente nivel si ganas, repetir si pierdes)
                    Repeater {
                        model: game.phase === "won" ? [
                            {
                                text: "Repetir",
                                act: "retry"
                            },
                            {
                                text: "Siguiente nivel",
                                act: "next"
                            },
                            {
                                text: "Salir",
                                act: "quit"
                            }
                        ] : [
                            {
                                text: "Otra estructura",
                                act: "new"
                            },
                            {
                                text: "Repetir",
                                act: "retry"
                            },
                            {
                                text: "Salir",
                                act: "quit"
                            }
                        ]
                        Rectangle {
                            required property var modelData
                            required property int index

                            width: bl.implicitWidth + 32
                            height: 40
                            radius: 20
                            color: index === 1 ? (cb.containsMouse ? Qt.lighter(Theme.primary, 1.1) : Theme.primary) : (cb.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)

                            Text {
                                id: bl

                                anchors.centerIn: parent
                                text: parent.modelData.text
                                font.family: Theme.font
                                font.pixelSize: 15
                                color: parent.index === 1 ? Theme.onPrimary : Theme.onSurface
                            }
                            MouseArea {
                                id: cb

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: game.act(parent.modelData.act)
                            }
                        }
                    }
                }
            }
        }
    }

    function loadedR(): real {
        return sim.loaded ? birdR[sim.loaded.type] : 0;
    }
    function act(a: string): void {
        if (a === "quit")
            quit();
        else if (a === "next")
            goLevel(level + 1);
        else
            newLevel(a === "retry");
    }
    // Para probar sin ratón: tira con este ángulo (grados, 0 = derecha, 45 = hacia arriba) y
    // fuerza (0-1); con abilityMs > 0, usa su habilidad a los tantos ms
    Timer {
        id: abilityTest

        onTriggered: game.ability()
    }
    function status(): string {
        return `nivel ${level} (máx. ${maxLevel}) · ${phase} · ${pigsLeft} por derribar · ${birdsLeft} tiros · ${score} pts · ${sim.ents.length} piezas (${sim.ents.filter(e => e.kind === "rock").length} rocas, ${sim.tries} intentos)`;
    }
    function autoShot(deg: real, pow: real, abilityMs: int): string {
        if (abilityMs > 0) {
            abilityTest.interval = abilityMs;
            abilityTest.restart();
        }
        if (phase !== "aim" || !sim.loaded)
            return `ahora no (${phase})`;
        const a = deg * Math.PI / 180, l = maxDrag * Math.max(0, Math.min(1, pow));
        aiming = true;
        dragTo((anchorX - Math.cos(a) * l) * ppm, (anchorY + Math.sin(a) * l) * ppm);
        aiming = false;
        launch();
        return `${sim.birds[0]?.type ?? "?"} lanzado`;
    }
}
