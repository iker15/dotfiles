import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Caelestia.Config

// Mochi: burbujita negra que vive en el escritorio, con Claude Code como cerebro.
// - Tiene gravedad: vive en el suelo de la pantalla, da saltitos y se le puede lanzar.
// - Si no le haces caso en un rato se esconde por debajo del borde (asoma los ojos).
// - Clic (o doble +) para hablarle; lo que escribes y su respuesta salen como subtítulos encima.
// - Vive en un workspace: si cambias de workspace, al rato viene detrás de ti (sin ponerse
//   bajo el ratón). Lanzándolo contra un lado atraviesa el borde y sigue su trayectoria por los
//   workspaces de ese lado hasta que se le acaba el impulso.
// - Mind.qml le hace reaccionar (con los ojos) a lo que haces; acariciarlo (pasar el ratón de lado a lado) le encanta.
// IPC: qs -c tamagotchi ipc call pet toggle|appear|hide|talk|ask "<texto>"|face <cara>|state
ShellRoot {
    id: shell

    readonly property string stateDir: Brain.stateDir

    property bool shown: true
    property bool asking: false        // campo de texto abierto
    property bool bubbleShown: false   // bocadillo con la respuesta
    property bool dragging: false

    // Centro de Mochi en coordenadas globales (todas las pantallas)
    property real gx: -1
    property real gy: -1

    property real lookX: 0
    property real lookY: 0

    // Voz: ears.py escucha el micro y avisa al oír "Mochi"
    property bool earsOn: true
    property bool earsReady: false
    property bool earsCooling: false   // se ha caído: espera un poco antes de relanzarlo
    property bool voiceWaiting: false  // ha oído "Mochi" y espera la orden
    property string heard: ""          // última orden dictada (se enseña mientras piensa)

    // Física: held (agarrado), air (volando/cayendo), swim (nadando por el marco, que es su
    // medio), hidden (hundido en el marco, asomando los ojos)
    property string phys: "air"
    property real vx: 0
    property real vy: 0
    property real hvx: 0          // velocidad del ratón al arrastrar (para lanzarlo)
    property real hvy: 0
    property real prevX: 0
    property real prevY: 0
    property int reversals: 0     // sacudidas al arrastrar → mareo
    property int lastDir: 0
    property int hopsLeft: 0
    property int hopDir: 1
    // Nado: posición a lo largo del recorrido (px desde la esquina de abajo a la izquierda,
    // en sentido antihorario visto en pantalla: abajo → derecha → arriba → izquierda)
    property real swimD: 0
    property real swimV: 0
    property real swimTarget: NaN
    property real ceilingTime: 0
    // Marcha: no va a velocidad constante, sino a zancadas (se encoge, se lanza estirándose,
    // se pasa un poco y se recoloca) con pausas irregulares. `energy` > 1 = con ganas.
    property real energy: 1
    property real gT: -1          // tiempo dentro de la zancada (-1 = parado entre zancadas)
    property real gDur: 0
    property real gLen: 0         // largo de la zancada (con signo, a lo largo del recorrido)
    property real gProg: 0
    property real gRest: 0        // pausa que le queda antes de la siguiente
    property bool gLunged: false
    property bool gHoriz: true    // la zancada va en horizontal (suelo/techo) o en vertical
    property bool slipping: false // resbalón por una pared (no cuenta como viaje)
    property real slipIn: 2
    // Buceo: se sumerge en el marco (su medio: lo domina), nada por dentro y sale más
    // adelante. "hidden" = no se le ve nada; "peek" = asoma un poco la cabeza (sin ojos).
    property string diveMode: ""
    property real diveFrom: 0         // swimD al empezar
    property real diveDist: 0         // recorrido (con signo, a lo largo del marco)
    property real diveT: 0
    property real diveDur: 1
    property bool diveFromDeep: false // (al llegar de otro workspace) ya empieza sumergido
    property real diveStage: 0        // 0 coge aire · 0.5 zambulléndose · 1 dentro · 2 saliendo
    property real sink: 0             // cuánto va hundido respecto a nadar en la superficie
    property real diveUnder: 0        // 0-1: cuánto está dentro (los ojos no se ven)
    property bool diveToNest: false   // el buceo acaba en el nido (no sale a la superficie)
    property bool diveStay: false     // el buceo acaba sumergido (se ha ido a la pantalla de bloqueo)
    // Nido: fundido del todo en la barra de la izquierda, en el hueco libre del medio (donde
    // antes salía la ventana activa). Solo se le ven los ojos; al pasar el ratón se asoma un
    // poco, y arrastrándolo se le saca. Vuelve ahí cuando no le haces caso.
    readonly property real nestFrac: 0.53     // altura del hueco (fracción de la pantalla)
    property bool nestHover: false
    property real nestPeek: 0                 // 0 = solo ojos · 1 = asomado
    // El cuerpo puede ir desplazado respecto a los ojos (en el nido: hundido en la barra
    // mientras los ojos quedan a la vista); fuera del nido vuelve a 0
    property real bodyOffX: 0
    property real bodyOffY: 0

    // Formas que imita con el cuerpo (ver mochi.frag): un rato (tempShape) o mientras Claude
    // trabaja ("claude" = Clawd, el bichito naranja de Claude Code, caminando en el sitio). Al tomar forma se separa del marco lo justo para verse entera.
    property string tempShape: ""
    readonly property string shapeName: (phys === "swim" || phys === "air" || phys === "held") && present ? (tempShape || (Brain.busy ? "claude" : "")) : ""
    readonly property int shapeId: ({
            "gear": 1,
            "claude": 2,
            "heart": 3,
            "star": 4,
            "arrow": 5
        })[shapeName] ?? 0
    property int lastShape: 0
    property real morph: shapeId ? 1 : 0
    property real shapeRot: 0
    onShapeIdChanged: {
        if (shapeId) {
            lastShape = shapeId;
            kicked(-1.6, 2.6);   // se estira al transformarse
        } else {
            kicked(1.4, -1.8);
        }
    }
    Behavior on morph {
        NumberAnimation {
            duration: 420
            easing.type: Easing.OutBack
        }
    }

    // Arcoíris durante ms (0 = 5 s)
    property real rainbowAmt: 0
    property real rainbowT: 0
    Behavior on rainbowAmt {
        NumberAnimation {
            duration: 400
        }
    }
    NumberAnimation on rainbowT {
        running: shell.rainbowAmt > 0
        from: 0
        to: 1000
        duration: 1000000
        loops: Animation.Infinite
    }
    function rainbow(ms: int): void {
        rainbowAmt = 1;
        rainbowTimer.interval = ms > 0 ? ms : 5000;
        rainbowTimer.restart();
    }

    // Café (cafeína): saca un bracito de su material, con una tacita en la punta, y le da un par
    // de sorbos. La taza va a un lado (hacia donde hay más sitio), a lo largo del marco.
    property real cupAmt: 0      // 0-1: bracito y taza fuera
    property real sip: 0         // 0 taza a un lado → 1 junto a la cara, inclinada
    property real cupT: 0        // (vapor)
    property real cupSide: 1
    property real cupNx: 0       // normal del marco donde se lo toma (hacia el marco)
    property real cupNy: 1
    readonly property bool sipping: coffeeSeq.running
    NumberAnimation on cupT {
        running: shell.cupAmt > 0
        from: 0
        to: 1000
        duration: 1000000
        loops: Animation.Infinite
    }
    // Dónde está la taza (global): centro, giro (grados) y la punta del bracito (en el asa)
    readonly property var cupGeom: {
        const tx = cupNy * cupSide, ty = -cupNx * cupSide, ux = -cupNx, uy = -cupNy;   // a lo largo, arriba
        const a = (1 - sip) * (bodyRx + 32) + sip * (bodyRx + 9), b = 2 + sip * 12 + 10 * Math.sin(Math.PI * sip);
        const k = 0.35 + 0.65 * cupAmt;   // sale del cuerpo
        const cx = gx + (tx * a + ux * b) * k, cy = gy + (ty * a + uy * b) * k;
        // se inclina hacia él al beber
        const rot = Math.atan2(ux, -uy) - cupSide * 1.15 * Math.max(0, sip - 0.4) / 0.6;
        // el asa, del lado de Mochi (en la taza: x = -lado)
        const hx = -cupSide * 17 * cupAmt, hy = 1;
        return {
            x: cx,
            y: cy,
            rot: rot * 180 / Math.PI,
            hx: cx + Math.cos(rot) * hx - Math.sin(rot) * hy,
            hy: cy + Math.sin(rot) * hx + Math.cos(rot) * hy
        };
    }
    function coffee(): void {
        if (phys !== "swim" || !present)
            return;
        const s = nearestScreen(gx, gy), p = pointAt(track(s), swimD);
        cupNx = p.nx;
        cupNy = p.ny;
        // hacia donde haya más sitio (el centro de la pantalla)
        cupSide = (s.x + s.width / 2 - gx) * p.ny - (s.y + s.height / 2 - gy) * p.nx >= 0 ? 1 : -1;
        swimTarget = NaN;
        coffeeSeq.restart();
    }
    function lookAtCup(ms: int): void {
        focusX = cupGeom.x;
        focusY = cupGeom.y;
        focusUntil = Date.now() + ms;
    }
    onPhysChanged: if (sipping && phys !== "swim") {
        coffeeSeq.stop();
        cupAway.restart();
    }

    function shapeShift(name: string, ms: int): void {
        tempShape = name;
        tempShapeTimer.interval = ms > 0 ? ms : 2500;
        tempShapeTimer.restart();
    }

    // Paneles abiertos de Caelestia (los publica caelestia/modules/drawers/MochiBridge.qml):
    // pantalla → [[x, y, w, h], …] en coordenadas globales. No se queda debajo de ellos.
    property var panels: ({})

    // También de Caelestia (MochiBridge): notificaciones, No molestar y cafeína
    property bool dnd: false           // No molestar: se va a dormir a su nido y no reacciona a nada
    property bool caffeine: false      // cafeína: se toma un café y se queda bien despierto
    property var notifSeen: ({})       // pantalla → id de la última notificación vista
    // Mirar fijamente algo un rato (la notificación): manda sobre el ratón y los vistazos
    property real focusX: 0
    property real focusY: 0
    property real focusUntil: 0

    // Humor según la hora: por la mañana con ganas, bajón después de comer, tranquilo por la
    // tarde-noche y dormilón de madrugada. Multiplica sus ganas de moverse; `drowsy` le
    // entorna los ojos.
    property real dayEnergy: 1
    readonly property real drowsy: Math.max(0, Math.min(1, (0.95 - dayEnergy) / 0.4))
    property real hideX: 0
    property real hideY: 0
    property bool cursorNear: false
    property bool lightBody: false      // fondo oscuro → subtítulos claros
    property color frameColor: Theme.surface   // color real del marco a su lado (lo mide bg.py)
    // El marco visto justo en la unión, a lo largo de sus lados (imagen que escribe bg.py y
    // usa el shader para pintar el cuerpo): se alternan dos ficheros para que la imagen recargue
    property string edgeFile: ""
    property string edgeScreen: ""
    property int edgeGen: 0

    Behavior on frameColor {
        ColorAnimation {
            duration: 400
        }
    }
    readonly property real bodyRx: 32 * 1.45          // semiejes del cuerpo (como en Blob)
    readonly property real bodyRy: 29 * 1.45 * 0.95
    readonly property real embed: 12                  // cuánto va hundido en el marco al nadar
    readonly property int hideAfter: 90000     // ms sin usarlo hasta que vuelve al nido

    // Marco de Caelestia (barra a la izquierda y borde alrededor): Mochi vive dentro,
    // está hecho del mismo material y se funde con él al tocarlo
    readonly property real barW: 60            // ancho de la barra de Caelestia (medido)
    readonly property real frame: cfg.Config.border.thickness
    readonly property real frameRounding: cfg.Config.border.rounding
    readonly property real frameSmoothing: cfg.Config.border.smoothing

    // Workspaces
    property int mochiWs: -1              // workspace donde vive
    property bool entering: false         // entrando por un lado de la pantalla (sin paredes)
    property bool thrown: false           // lanzado a mano: puede cruzar a otro workspace
    property bool flung: false            // ha cruzado a otro workspace en este lanzamiento
    property real sulkUntil: 0            // tras lanzarlo a otro workspace, se queda allí un rato
    readonly property bool present: mochiWs < 0 || Hyprland.monitors.values.some(m => m.activeWorkspace?.id === mochiWs)
    readonly property bool fsHide: Hyprland.workspaces.values.find(w => w.id === mochiWs)?.hasFullscreen ?? false

    property real cursorX: 0
    property real cursorY: 0
    property real glanceX: 0              // mirar a otro sitio un momento (ventana nueva…)
    property real glanceY: 0
    property real glanceUntil: 0
    property string remark: ""            // comentario espontáneo en el bocadillo

    signal splatted(real strength, bool horizontal)
    signal kicked(real ax, real ay)
    signal woke()                     // cualquier uso: se le quita el sueño
    signal sleepTest(string what)

    // Escribiendo código en VSCodium: la forma que imita (la está pensando Iker; mientras
    // tanto, solo pone ojos de concentrado)
    property string codeShape: ""
    property bool dozing: false       // se ha quedado dormido (no pasea)

    // Pantalla de bloqueo (la avisa caelestia/modules/lock/Lock.qml): mientras está bloqueada
    // no escucha ni obedece, y se va a la pantalla de bloqueo (LockPet.qml, que dibuja Caelestia)
    // saliendo por el borde de abajo; al desbloquear vuelve por ahí mismo a su sitio
    property bool locked: false
    property var preLock: null         // dónde estaba antes de bloquear
    onDndChanged: {
        if (dnd) {
            asking = false;
            if (present && phys === "swim")
                goNest();   // se va a dormir a su nido
        } else {
            woke();
        }
    }

    // Cafeína: sale (si estaba en el nido), se toma un café y se queda despierto del todo
    onCaffeineChanged: {
        const d = new Date();
        dayEnergy = caffeine ? Math.max(1.2, energyAt(d.getHours() + d.getMinutes() / 60)) : energyAt(d.getHours() + d.getMinutes() / 60);
        if (!caffeine || dnd || locked)
            return;
        woke();
        if (!present)
            return;
        if (phys === "nest")
            leaveNest();
        coffeeTimer.restart();
    }

    onLockedChanged: {
        Brain.locked = locked;
        if (locked)
            goLock();
        else
            backFromLock();
    }
    signal leaned(real v)
    signal reacted(string name, int ms)

    readonly property string mood: (asking || voiceWaiting) && !Brain.busy ? "listening" : Brain.mood

    function screenAt(x: real, y: real): var {
        for (const s of Quickshell.screens)
            if (x >= s.x && x < s.x + s.width && y >= s.y && y < s.y + s.height)
                return s;
        return null;
    }

    function nearestScreen(x: real, y: real): var {
        let s = screenAt(x, y);
        if (s)
            return s;
        let best = Infinity;
        for (const c of Quickshell.screens) {
            const dx = Math.max(c.x - x, 0, x - (c.x + c.width));
            const dy = Math.max(c.y - y, 0, y - (c.y + c.height));
            if (dx + dy < best) {
                best = dx + dy;
                s = c;
            }
        }
        return s;
    }

    // Que no se quede fuera de ninguna pantalla
    function settle(): void {
        const s = nearestScreen(gx, gy);
        if (!s)
            return;
        gx = Math.max(s.x + 55, Math.min(s.x + s.width - 55, gx));
        gy = Math.max(s.y + 55, Math.min(s.y + s.height - 55, gy));
    }

    function savePos(): void {
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && printf "%s %s" "$2" "$3" > "$1/pos"', "sh", stateDir, Math.round(gx), Math.round(gy)]);
    }

    function screenOfMonitor(m: var): var {
        return Quickshell.screens.find(q => q.name === m?.name) ?? Quickshell.screens[0];
    }

    // El recorrido por el que nada: un rectángulo de esquinas redondeadas por dentro del marco
    // (los puntos son el centro de Mochi, que va algo hundido en el marco)
    function track(s: var): var {
        const L = s.x + barW + bodyRx - embed, R = s.x + s.width - frame - bodyRx + embed;
        const T = s.y + frame + bodyRy - embed, B = s.y + s.height - frame - bodyRy + embed;
        const c = 45, w = R - L - 2 * c, h = B - T - 2 * c, q = c * Math.PI / 2;
        return {
            L: L,
            R: R,
            T: T,
            B: B,
            c: c,
            w: w,
            h: h,
            q: q,
            len: 2 * w + 2 * h + 4 * q
        };
    }

    // Punto del recorrido y su normal hacia fuera (hacia el marco)
    function pointAt(tr: var, d: real): var {
        d = ((d % tr.len) + tr.len) % tr.len;
        const arc = (cx, cy, a) => ({
                    x: cx + tr.c * Math.cos(a),
                    y: cy + tr.c * Math.sin(a),
                    nx: Math.cos(a),
                    ny: Math.sin(a)
                });
        if (d < tr.w)
            return {
                x: tr.L + tr.c + d,
                y: tr.B,
                nx: 0,
                ny: 1
            };
        d -= tr.w;
        if (d < tr.q)
            return arc(tr.R - tr.c, tr.B - tr.c, Math.PI / 2 - d / tr.c);
        d -= tr.q;
        if (d < tr.h)
            return {
                x: tr.R,
                y: tr.B - tr.c - d,
                nx: 1,
                ny: 0
            };
        d -= tr.h;
        if (d < tr.q)
            return arc(tr.R - tr.c, tr.T + tr.c, -d / tr.c);
        d -= tr.q;
        if (d < tr.w)
            return {
                x: tr.R - tr.c - d,
                y: tr.T,
                nx: 0,
                ny: -1
            };
        d -= tr.w;
        if (d < tr.q)
            return arc(tr.L + tr.c, tr.T + tr.c, -Math.PI / 2 - d / tr.c);
        d -= tr.q;
        if (d < tr.h)
            return {
                x: tr.L,
                y: tr.T + tr.c + d,
                nx: -1,
                ny: 0
            };
        d -= tr.h;
        return arc(tr.L + tr.c, tr.B - tr.c, Math.PI - d / tr.c);
    }

    // El punto del recorrido más cercano a (x, y)
    function nearestD(tr: var, x: real, y: real): real {
        let best = 0, bestDist = Infinity;
        for (let d = 0; d < tr.len; d += 8) {
            const p = pointAt(tr, d), dist = Math.hypot(p.x - x, p.y - y);
            if (dist < bestDist) {
                bestDist = dist;
                best = d;
            }
        }
        for (let d = best - 8; d <= best + 8; d += 1) {
            const p = pointAt(tr, d), dist = Math.hypot(p.x - x, p.y - y);
            if (dist < bestDist) {
                bestDist = dist;
                best = d;
            }
        }
        return ((best % tr.len) + tr.len) % tr.len;
    }

    // Distancia más corta (con signo) a lo largo del recorrido
    function trackDiff(tr: var, from: real, to: real): real {
        let d = ((to - from) % tr.len + tr.len) % tr.len;
        return d > tr.len / 2 ? d - tr.len : d;
    }

    // Curva de una zancada: coge impulso hacia atrás, se lanza, se pasa un pelín y vuelve
    function strideEase(u: real): real {
        const c = 0.6 * 1.525;
        return u < 0.5 ? Math.pow(2 * u, 2) * ((c + 1) * 2 * u - c) / 2 : (Math.pow(2 * u - 2, 2) * ((c + 1) * (2 * u - 2) + c) + 2) / 2;
    }

    // Empujón a la forma en el sentido de la marcha (along) y perpendicular (perp)
    function kickAlong(along: real, perp: real): void {
        if (gHoriz)
            kicked(along, perp);
        else
            kicked(perp, along);
    }

    // Avanza la marcha: devuelve cuánto moverse este frame hacia `diff`, o NaN si ya ha llegado
    function gait(diff: real, dt: real, horiz: bool, ahead: var): real {
        if (gT < 0) {
            if (gRest > 0) {
                gRest -= dt;
                return 0;
            }
            if (Math.abs(diff) < 3)
                return NaN;
            let len = Math.min(Math.abs(diff), (60 + Math.random() * 110) * energy);
            if (Math.abs(diff) - len < 45)
                len = Math.abs(diff);   // el último tramo, de una
            gLen = Math.sign(diff) * len;
            gProg = 0;
            gT = 0;
            gDur = (0.34 + len * 0.0022 + Math.random() * 0.1) / Math.sqrt(energy);
            gLunged = false;
            gHoriz = horiz;
            // Se encoge para coger impulso y mira hacia donde va
            kickAlong(-1.1 - 0.4 * energy, 0.8);
            if (ahead) {
                glanceX = ahead.x;
                glanceY = ahead.y;
                glanceUntil = Date.now() + (gDur + 0.3) * 1000;
            }
        }
        gT += dt;
        const u = Math.min(1, gT / gDur), e = strideEase(u);
        const step = gLen * e - gProg;
        gProg = gLen * e;
        if (!gLunged && u > 0.3) {
            // Se lanza: se estira hacia delante y los ojos se echan hacia allí
            gLunged = true;
            kickAlong(1.5 + 0.8 * energy, -1.2);
            leaned(Math.sign(gLen) * (gHoriz ? 1 : 0.5) * 90);
        }
        if (u >= 1) {
            gT = -1;
            // Frena: se aplasta un poco contra el sentido de la marcha
            kickAlong(-0.8, 0.5);
            const r = Math.random();
            gRest = (r < 0.1 ? 0.7 + Math.random() * 0.6 : 0.03 + Math.random() * 0.12) / energy;
            // En las pausas largas se para a mirar (atrás, o a ti)
            if (r < 0.1) {
                const back = Math.random() < 0.5;
                glanceX = back ? gx - Math.sign(gLen) * (gHoriz ? 400 : 0) : cursorX;
                glanceY = back ? gy - Math.sign(gLen) * (gHoriz ? 0 : 400) : cursorY;
                glanceUntil = Date.now() + gRest * 1000;
            }
        }
        return step;
    }

    // Empieza un viaje nuevo: un momentito para decidirse antes de la primera zancada
    function startTrip(): void {
        gT = -1;
        gRest = (0.12 + Math.random() * 0.25) / energy;
    }

    // Un sitio del marco lejos del ratón, mejor en las paredes o en las esquinas de abajo (el
    // centro de abajo suele tener cosas: reproductores, barras…) y no en el techo
    function spotD(s: var, tr: var, accept: var): real {
        const onScreen = cursorX >= s.x && cursorX < s.x + s.width && cursorY >= s.y && cursorY < s.y + s.height;
        let best = 0, bestScore = -Infinity;
        for (let i = 0; i < 24; i++) {
            const d = tr.len * i / 24, p = pointAt(tr, d);
            if ((accept && !accept(d)) || inPanel(p.x, p.y, bodyRx + 60))
                continue;
            let score = (onScreen ? Math.min(900, Math.hypot(p.x - cursorX, p.y - cursorY)) : 500) + Math.random() * 250;
            if (p.nx !== 0 && Math.abs(p.ny) < 0.5)
                score += 250 + 150 * (p.y - tr.T) / (tr.B - tr.T);   // paredes, mejor abajo
            else if (p.ny > 0.5)
                score += 400 * Math.abs((p.x - tr.L) / (tr.R - tr.L) - 0.5);   // suelo, mejor a los lados
            else
                score -= 300;   // techo
            if (score > bestScore) {
                bestScore = score;
                best = d;
            }
        }
        return best;
    }

    // Llega al workspace en el que estás buceando por el borde de abajo: entra sumergido por
    // la esquina del lado del que viene, asomando un poco la cabeza, y sale en un sitio tranquilo más
    // allá (en el suelo o subiendo por la pared del otro lado)
    function arrive(): void {
        const ws = Hyprland.focusedWorkspace;
        if (!ws)
            return;
        const s = screenOfMonitor(Hyprland.focusedMonitor), tr = track(s);
        const fromLeft = mochiWs >= 0 && mochiWs < ws.id;
        mochiWs = ws.id;
        hopsLeft = 0;
        entering = false;
        swimTarget = NaN;
        swimV = 0;
        const dir = fromLeft ? 1 : -1;
        const d0 = fromLeft ? tr.len - tr.q * 0.5 : tr.w + tr.q * 0.5;   // en la esquina de abajo
        const ahead = d => ((d - d0) * dir % tr.len + tr.len) % tr.len;
        const spot = spotD(s, tr, d => ahead(d) > 250 && ahead(d) < tr.w + tr.q + tr.h * 0.75);
        swimD = d0;
        const p = pointAt(tr, d0), rn = normalRadius(p), deep = 2 * rn - embed - diveVisible("hidden", rn);
        gx = p.x + p.nx * deep;
        gy = p.y + p.ny * deep;
        dive(dir * ahead(spot), "peek", true, 1);
    }

    // Radio del cuerpo en la dirección de la normal (hacia el marco)
    function normalRadius(p: var): real {
        return Math.abs(p.nx) * bodyRx + Math.abs(p.ny) * bodyRy;
    }

    // Cuánto asoma del marco (px) en cada modo; negativo = hundido de más (ni el remolino
    // que hace al fundirse con el marco se ve)
    function diveVisible(mode: string, rn: real): real {
        return mode === "peek" ? 24 : -(0.35 * rn + frameSmoothing * 0.3 + 8);
    }

    // Velocidad suave: acelera, va de crucero y frena, sin tirones (dentro del marco se
    // mueve como pez en el agua)
    function glide(u: real): real {
        const a = 0.22, S = 1 - a;
        const ramp = x => x / 2 - a / (2 * Math.PI) * Math.sin(Math.PI * x / a);
        if (u < a)
            return ramp(u) / S;
        if (u > 1 - a)
            return (S - ramp(1 - u)) / S;
        return (a / 2 + u - a) / S;
    }

    function smooth(x: real): real {
        x = Math.max(0, Math.min(1, x));
        return x * x * x * (x * (6 * x - 15) + 10);
    }

    // Se zambulle en el marco, bucea `dist` px a lo largo de él y sale
    function dive(dist: real, mode: string, fromDeep: bool, speed: real): void {
        diveMode = mode;
        diveFrom = swimD;
        diveDist = dist;
        diveT = 0;
        diveDur = (1 + Math.abs(dist) / (mode === "peek" ? 380 : 620)) / (speed > 0 ? speed : 1);
        diveFromDeep = fromDeep;
        diveStage = fromDeep ? 1 : 0;
        swimTarget = NaN;
        hopsLeft = 0;
        phys = "dive";
    }

    function diveStep(tr: var, dt: real): void {
        diveT += dt;
        const u = Math.min(1, diveT / diveDur);
        swimD = ((diveFrom + diveDist * glide(u)) % tr.len + tr.len) % tr.len;
        const p = pointAt(tr, swimD), rn = normalRadius(p);
        const surface = 2 * rn - embed, mid = diveVisible(diveMode, rn);
        const down = smooth((u - 0.05) / 0.2), up = diveToNest || diveStay ? 0 : smooth((u - 0.78) / 0.2);
        let vis = (diveFromDeep ? diveVisible("hidden", rn) : surface) * (1 - down) + mid * down;
        vis = vis * (1 - up) + surface * up;
        if (!diveFromDeep && u < 0.06)
            vis += 5 * Math.sin(Math.PI * u / 0.06);   // coge aire: se estira hacia arriba antes
        const under = down * (1 - up);
        diveUnder = under;
        if (diveMode === "peek")
            vis += 2.5 * Math.sin(diveT * 8) * under;   // ondula al nadar
        sink = surface - vis;
        const k = Math.min(1, dt * 14);
        gx += (p.x + p.nx * sink - gx) * k;
        gy += (p.y + p.ny * sink - gy) * k;

        // Forma: se estira hacia arriba al coger aire, se alarga al zambullirse y al salir
        // se estira hacia fuera y se sacude
        gHoriz = Math.abs(p.ny) > 0.5;
        if (diveStage === 0 && u > 0.01) {
            diveStage = 0.5;
            kickAlong(-1.0, 2.2);
        } else if (diveStage < 1 && down > 0.35) {
            diveStage = 1;
            kickAlong(2.2, -1.8);
            leaned(Math.sign(diveDist) * 110);
        } else if (diveStage === 1 && up > 0.25) {
            diveStage = 2;
            kickAlong(-1.4, 3.4);
            splatted(380, !gHoriz);
            reacted(diveFromDeep ? "excited" : "happy", 900);
        }

        // (los ojos se hunden con él: se recortan al interior del marco, como el cuerpo)
        // mira hacia donde va
        const ahead = pointAt(tr, swimD + Math.sign(diveDist) * 300);
        glanceX = ahead.x;
        glanceY = ahead.y;
        glanceUntil = Date.now() + 200;

        if (u >= 1 && diveToNest) {
            enterNest(nearestScreen(gx, gy));
            return;
        }
        if (u >= 1 && diveStay) {
            diveT = diveDur;   // se queda ahí abajo hasta que se desbloquee
            return;
        }
        if (u >= 1) {
            phys = "swim";
            diveMode = "";
            diveUnder = 0;
            sink = 0;
            swimV = 0;
            energy = 1;
            savePos();
            checkBg();
            avoidPanels();
        }
    }

    // Energía según la hora (interpolando entre puntos del día)
    function energyAt(h: real): real {
        const pts = [[0, 0.55], [6, 0.5], [8, 1.2], [12, 1.25], [14, 1.05], [15.5, 0.85], [17, 1], [20, 1], [23, 0.7], [24, 0.55]];
        for (let i = 1; i < pts.length; i++)
            if (h <= pts[i][0]) {
                const [h0, e0] = pts[i - 1], [h1, e1] = pts[i];
                return e0 + (e1 - e0) * (h - h0) / (h1 - h0);
            }
        return 1;
    }

    function setPanels(name: string, text: string): void {
        const s = Quickshell.screens.find(q => q.name === name);
        const ox = s?.x ?? 0, oy = s?.y ?? 0;
        let data = {};
        try {
            data = JSON.parse(text);
        } catch (e) {}
        const all = Object.assign({}, panels);
        all[name] = (data.rects ?? []).map(r => [r[0] + ox, r[1] + oy, r[2], r[3]]);
        panels = all;
        if (data.dnd !== undefined)
            dnd = data.dnd;
        if (data.caffeine !== undefined)
            caffeine = data.caffeine;
        // Notificación nueva (la primera lectura no cuenta: puede ser de antes)
        const id = data.notif?.id ?? "";
        const seen = name in notifSeen;
        if (id && notifSeen[name] !== id) {
            notifSeen[name] = id;
            if (seen) {
                const r = data.notif.rect;
                lookAtNotif(r[0] + ox, r[1] + oy, r[2], r[3], data.notif.urgent);
            }
        } else if (!seen) {
            notifSeen[name] = id;
        }
        avoidPanels();
    }

    // Llega una notificación: se acerca nadando hasta su lado (sin ponerse debajo) y la mira un
    // rato; si es urgente, con cara de susto
    function lookAtNotif(x: real, y: real, w: real, h: real, urgent: bool): void {
        if (dnd || !present || asking || dragging || Brain.busy)
            return;
        const cx = x + w / 2, cy = y + h / 2;
        focusX = cx;
        focusY = cy;
        focusUntil = Date.now() + 5000;
        reacted(urgent ? "surprised" : "curious", urgent ? 1800 : 1500);
        if (urgent)
            kicked(-1.2, 2.4);
        if (phys !== "swim")
            return;   // (en el nido, el icono la mira desde la barra)
        const s = nearestScreen(gx, gy), tr = track(s);
        let best = NaN, bestDist = Infinity;
        for (let i = 0; i < 96; i++) {
            const d = tr.len * i / 96, p = pointAt(tr, d);
            if (inPanel(p.x, p.y, bodyRx + 40))
                continue;
            const dist = Math.hypot(p.x - cx, p.y - cy);
            if (dist < bestDist) {
                bestDist = dist;
                best = d;
            }
        }
        if (isNaN(best))
            return;
        const dist = trackDiff(tr, swimD, best);
        focusUntil = Date.now() + 5000 + Math.abs(dist) * 2;
        if (Math.abs(dist) > 320)
            dive(dist, "peek", false, 1.6);
        else if (Math.abs(dist) > 10) {
            energy = 1.6;
            swimTarget = best;
        }
    }

    // ¿El punto (x, y) cae sobre algún panel abierto (con margen m)?
    function inPanel(x: real, y: real, m: real): bool {
        for (const name in panels)
            for (const r of panels[name])
                if (x > r[0] - m && x < r[0] + r[2] + m && y > r[1] - m && y < r[1] + r[3] + m)
                    return true;
        return false;
    }

    // Si un panel le ha caído encima, se va buceando (rápido y sin que se le vea) al sitio libre
    // más cercano; si no hay ninguno, a su nido de la barra
    function avoidPanels(): void {
        if (!present || (phys !== "swim" && phys !== "hidden"))
            return;
        if (!inPanel(gx, gy, Math.max(bodyRx, bodyRy) + 10))
            return;
        const s = nearestScreen(gx, gy), tr = track(s);
        let best = NaN, bestScore = -Infinity;
        for (let i = 0; i < 64; i++) {
            const d = tr.len * i / 64, p = pointAt(tr, d);
            if (p.ny < -0.9 || inPanel(p.x, p.y, bodyRx + 70))
                continue;
            const score = -Math.abs(trackDiff(tr, swimD, d)) + Math.min(400, Math.hypot(p.x - cursorX, p.y - cursorY)) * 0.5;
            if (score > bestScore) {
                bestScore = score;
                best = d;
            }
        }
        reacted("surprised", 500);
        if (isNaN(best)) {
            goNest();
            return;
        }
        phys = "swim";
        dive(trackDiff(tr, swimD, best), "hidden", false, 2.2);
    }

    // Se bloquea la pantalla: se hunde en el borde de abajo (en su x) y le cuenta a la pantalla de
    // bloqueo dónde está y cuánto sueño tiene
    function goLock(): void {
        asking = false;
        voiceWaiting = false;
        const s = present ? nearestScreen(gx, gy) : screenOfMonitor(Hyprland.focusedMonitor);
        if (!s)
            return;
        const tr = track(s);
        preLock = {
            nest: phys === "nest",
            d: swimD,
            ws: mochiWs
        };
        const x = Math.max(tr.L + tr.c, Math.min(tr.R - tr.c, phys === "nest" ? s.x + s.width * 0.2 : gx));
        lockState.setText(JSON.stringify({
            screen: s.name,
            x: Math.round(x - s.x),
            drowsy: drowsy,
            dozing: dozing
        }));
        if (present && (phys === "swim" || phys === "nest")) {
            if (phys === "nest") {
                phys = "swim";
                swimD = nearestD(tr, tr.L, gy);
            }
            dive(trackDiff(tr, swimD, nearestD(tr, x, tr.B)), "hidden", false, 2.5);
            diveToNest = false;
            diveStay = true;   // se queda abajo
        }
    }

    // Se desbloquea: sale del borde de abajo donde estaba en la pantalla de bloqueo, contento, y
    // al rato vuelve a donde estaba
    function backFromLock(): void {
        const s = screenOfMonitor(Hyprland.focusedMonitor);
        if (!s)
            return;
        const tr = track(s);
        let x = s.x + s.width * 0.7;
        try {
            x = s.x + JSON.parse(lockState.text()).x;
        } catch (e) {}
        mochiWs = Hyprland.focusedWorkspace?.id ?? mochiWs;
        diveStay = false;
        diveToNest = false;
        hopsLeft = 0;
        swimTarget = NaN;
        swimD = nearestD(tr, x, tr.B);
        const p = pointAt(tr, swimD), rn = normalRadius(p), deep = 2 * rn - embed - diveVisible("hidden", rn);
        gx = p.x;
        gy = p.y + deep;
        dive(0, "hidden", true, 2);
        backHome.restart();
    }

    // Punto del nido y del recorrido junto a él
    function nestPoint(s: var): var {
        return {
            x: s.x + barW / 2,
            y: s.y + s.height * nestFrac
        };
    }

    // Vuelve al nido buceando por el marco (sin que se le vea); si no está a la vista, aparece
    // directamente allí
    function goNest(): void {
        const s = present ? nearestScreen(gx, gy) : screenOfMonitor(Hyprland.focusedMonitor);
        if (!s)
            return;
        const tr = track(s), n = nestPoint(s);
        const target = nearestD(tr, tr.L, n.y);
        if (!present || phys !== "swim") {
            mochiWs = Hyprland.focusedWorkspace?.id ?? mochiWs;
            enterNest(s);
            return;
        }
        diveToNest = true;
        dive(trackDiff(tr, swimD, target), "hidden", false, Math.max(0.7, dayEnergy));
    }

    function enterNest(s: var): void {
        const n = nestPoint(s);
        hopsLeft = 0;
        swimTarget = NaN;
        diveMode = "";
        diveToNest = false;
        diveUnder = 0;
        nestPeek = 0;
        nestHover = false;
        // los ojos van al centro de la barra; el cuerpo, hundido en ella
        const bodyX = s.x + barW - bodyRx + diveVisible("hidden", bodyRx);
        bodyOffX = bodyX - n.x;
        bodyOffY = 0;
        gx = n.x;
        gy = n.y;
        phys = "nest";
        savePos();
    }

    // Sale del nido al interior (lo has llamado, le has hecho clic…)
    function leaveNest(): void {
        const s = nearestScreen(gx, gy), tr = track(s);
        swimD = nearestD(tr, tr.L, gy);
        swimV = 0;
        nestHover = false;
        phys = "swim";
        kicked(3, -1.5);   // sale estirándose hacia dentro
        reacted("happy", 900);
    }

    function nestStep(s: var, dt: real): void {
        const n = nestPoint(s);
        nestPeek += ((nestHover ? 1 : 0) - nestPeek) * Math.min(1, dt * 7);
        // Ojos: del centro de la barra a su borde; cuerpo: de hundido a asomar media cara
        const eyeX = n.x + (s.x + barW + 12 - n.x) * nestPeek;
        const vis = diveVisible("hidden", bodyRx) * (1 - nestPeek) + 48 * nestPeek;
        const bodyX = s.x + barW - bodyRx + vis;
        const k = Math.min(1, dt * 12);
        gx += (eyeX - gx) * k;
        gy += (n.y - gy) * k;
        bodyOffX = bodyX - gx;
        bodyOffY = 0;
        mochiWs = Hyprland.focusedWorkspace?.id ?? mochiWs;   // la barra está en todos
    }

    // Lo has llamado (++, voz, clic…) y no está aquí: sale del borde de abajo
    function summon(): void {
        const ws = Hyprland.focusedWorkspace;
        if (!ws)
            return;
        const s = screenOfMonitor(Hyprland.focusedMonitor), tr = track(s);
        mochiWs = ws.id;
        hopsLeft = 0;
        entering = false;
        swimTarget = NaN;
        swimV = 0;
        const x = s.x + s.width * (cursorX - s.x < s.width / 2 ? 0.8 : 0.2);   // lejos del ratón
        swimD = nearestD(tr, x, tr.B);
        gx = x;
        gy = tr.B + 70;
        phys = "swim";
        reacted("happy", 900);
    }

    // Has cambiado de workspace: si no está a la vista, al rato viene detrás de ti
    function wsChanged(): void {
        const ws = Hyprland.focusedWorkspace;
        if (!ws)
            return;
        if (mochiWs < 0 || phys === "held" || phys === "nest") {   // agarrado o en el nido: está contigo
            mochiWs = ws.id;
            return;
        }
        if (mochiWs === ws.id)
            return;
        // (si sigue a la vista en otro monitor, followTimer no hace nada)
        const now = Date.now();
        followTimer.interval = Brain.busy || bubbleShown ? 700 : now < sulkUntil ? sulkUntil - now : 2500 + Math.random() * 5000;
        followTimer.restart();
    }

    // Lanzado contra un lado con fuerza: atraviesa el borde y sigue volando por el
    // workspace de ese lado (si hay). Si al llegar al otro borde aún va rápido, pasa al
    // siguiente, y así hasta que se le acabe el impulso.
    function crossToWs(dir: int, s: var): bool {
        const ids = Hyprland.workspaces.values.map(w => w.id).filter(id => id > 0).sort((a, b) => a - b);
        const next = dir > 0 ? ids.find(id => id > mochiWs) : ids.filter(id => id < mochiWs).pop();
        if (next === undefined)
            return false;
        mochiWs = next;
        flung = true;
        entering = true;
        const tr = track(s);
        gx = dir > 0 ? tr.L - bodyRx : tr.R + bodyRx;
        vx *= 0.9;
        return true;
    }

    // Acariciarlo con el ratón
    function pet(): void {
        if (phys === "nest")
            idleHide.restart();
        else
            touch();
        reacted("love", 2400);
        splatted(420, false);
    }

    // Se hunde en el marco (donde esté) dejando solo los ojos fuera
    function hideAway(): void {
        const s = nearestScreen(gx, gy), p = pointAt(track(s), swimD);
        const depth = Math.abs(p.ny) > 0.5 ? 26 : 14;   // en las paredes, menos (los ojos van de lado)
        hideX = p.x + p.nx * depth;
        hideY = p.y + p.ny * depth;
        hopsLeft = 0;
        swimTarget = NaN;
        phys = "hidden";
    }

    // Cualquier uso: reinicia la cuenta para esconderse y, si estaba escondido o en otro
    // workspace, viene
    function touch(): void {
        if (locked)
            return;
        idleHide.restart();
        woke();
        if (!present) {
            summon();
            return;
        }
        if (phys === "nest") {
            leaveNest();
            return;
        }
        if (phys === "hidden") {
            phys = "swim";   // vuelve a asomar entero
            swimV = 0;
            reacted("happy", 800);
        }
    }

    // Saltito desde el suelo (la gravedad hace el resto)
    function hop(): void {
        const s = nearestScreen(gx, gy);
        if (!s || phys !== "swim")
            return;
        const tr = track(s), p = pointAt(tr, swimD);
        if (p.ny < 0.9) {   // solo desde el suelo
            hopsLeft = 0;
            return;
        }
        if (gx - tr.L < 150)
            hopDir = 1;
        else if (tr.R - gx < 150)
            hopDir = -1;
        else if (Math.hypot(cursorX - gx, cursorY - gy) < 400)
            hopDir = cursorX > gx ? -1 : 1;   // no ir hacia el ratón
        const big = Math.random() < 0.15;
        const e = 0.75 + 0.25 * dayEnergy;
        vx = hopDir * (big ? 260 : 120 + Math.random() * 120) * e;
        vy = (big && dayEnergy > 0.9 ? -950 : -(430 + Math.random() * 180)) * e;
        hopsLeft--;
        phys = "air";
    }

    // Se impulsa desde una pared hacia dentro y cae (vuelve al marco donde caiga)
    function pushOff(): void {
        const s = nearestScreen(gx, gy);
        if (!s || phys !== "swim")
            return;
        const p = pointAt(track(s), swimD);
        vx = -p.nx * (300 + Math.random() * 250);
        vy = -p.ny * 300 - 250;
        phys = "air";
    }

    function checkBg(): void {
        const s = nearestScreen(gx, gy);
        if (!s || bgProc.running)
            return;
        // (escondido o buceando asoman los ojos por el marco: no se mide entonces)
        const edge = phys === "swim" || phys === "air" ? `${Quickshell.env("XDG_RUNTIME_DIR")}/mochi-edge-${s.name}-${edgeGen % 2}.ppm` : "";
        bgProc.edgeOut = edge;
        bgProc.edgeFor = s.name;
        bgProc.command = [Quickshell.shellDir + "/bg.py", gx, gy, bodyRx, bodyRy, s.x, s.y, s.width, s.height, barW, frame, frameRounding, edge].map(String);
        bgProc.running = true;
    }

    // Toca el marco: se funde con él y se queda nadando ahí (sin rebotar: es un fluido)
    function attach(s: var, impact: real, horizontal: bool): void {
        const tr = track(s);
        swimD = nearestD(tr, gx, gy);
        const p = pointAt(tr, swimD);
        swimV = (vx * p.ny - vy * p.nx) * 0.45;   // conserva algo de la velocidad a lo largo
        vx = vy = 0;
        if (impact > 1300)
            reacted("squint", 500);
        if (impact > 250)
            splatted(impact, horizontal);
        phys = "swim";
        attached();
    }

    function attached(): void {
        thrown = false;
        entering = false;
        // Ha acabado en otro workspace: se queda allí un par de minutos y luego vuelve contigo
        if (flung) {
            flung = false;
            if (!present) {
                sulkUntil = Date.now() + 120000;
                followTimer.interval = 120000;
                followTimer.restart();
                return;
            }
        }
        if (!present)
            return;
        savePos();
        checkBg();
        avoidPanels();
        // Se queda en el workspace de la pantalla donde ha caído
        const id = Hyprland.monitorFor(nearestScreen(gx, gy))?.activeWorkspace?.id;
        if (id !== undefined && id > 0)
            mochiWs = id;
        if (hopsLeft > 0)
            hopAgain.restart();
    }

    function physStep(dt: real): void {
        dt = Math.min(dt, 1 / 30);
        // el engranaje gira; Clawd usa esto como el tiempo de su animación (patas y brazos)
        if (morph > 0.01)
            shapeRot += dt * (lastShape === 1 ? 1.3 : lastShape === 2 || lastShape === 6 ? 1 : 0);
        else
            shapeRot = 0;
        if (phys !== "nest" && (bodyOffX || bodyOffY)) {
            // (al sacarlo del nido, el cuerpo sale de la barra detrás de los ojos)
            const f = Math.exp(-9 * dt);
            bodyOffX = Math.abs(bodyOffX) < 0.3 ? 0 : bodyOffX * f;
            bodyOffY = Math.abs(bodyOffY) < 0.3 ? 0 : bodyOffY * f;
        }
        if (phys === "held") {
            // Velocidad del arrastre (suavizada) y sacudidas
            hvx = hvx * 0.6 + (gx - prevX) / dt * 0.4;
            hvy = hvy * 0.6 + (gy - prevY) / dt * 0.4;
            prevX = gx;
            prevY = gy;
            if (Math.abs(hvx) > 700 && Math.sign(hvx) !== lastDir) {
                if (lastDir !== 0)
                    reversals++;
                lastDir = Math.sign(hvx);
            }
            return;
        }

        const s = nearestScreen(gx, gy);
        if (!s)
            return;
        const tr = track(s);

        if (phys === "dive") {
            diveStep(tr, dt);
            return;
        }
        if (phys === "nest") {
            nestStep(s, dt);
            return;
        }

        if (phys === "hidden") {
            const k = Math.min(1, dt * 2.5);
            gx += (hideX - gx) * k;
            gy += (hideY - gy) * k;
            return;
        }

        if (phys === "swim") {
            const here = pointAt(tr, swimD);
            let moved = false;
            if (!isNaN(swimTarget)) {
                // Va hacia el sitio elegido a zancadas
                const diff = trackDiff(tr, swimD, swimTarget);
                const ahead = pointAt(tr, swimD + Math.sign(diff) * 300);
                const step = gait(diff, dt, Math.abs(here.ny) > 0.5, slipping ? null : ahead);
                if (isNaN(step)) {
                    const wasSlip = slipping;
                    swimTarget = NaN;
                    swimV = 0;
                    energy = 1;
                    if (!wasSlip) {
                        savePos();
                        checkBg();
                    }
                } else {
                    swimD = ((swimD + step) % tr.len + tr.len) % tr.len;
                    swimV = step / dt;
                    moved = true;
                }
            } else if (Math.abs(here.nx) > 0.9) {
                // En una pared la gravedad puede más que él: se aguanta y de vez en cuando
                // resbala un poco, a tirones, como una gota en un cristal
                slipIn -= dt;
                if (slipIn <= 0) {
                    slipIn = 0.8 + Math.random() * 2.6;
                    slipping = true;
                    energy = 2.2;
                    gT = -1;
                    gRest = 0;
                    swimTarget = ((swimD + (here.nx > 0 ? -1 : 1) * (8 + Math.random() * 26)) % tr.len + tr.len) % tr.len;
                }
            }
            // En el techo no aguanta mucho: se suelta y cae como una gota
            if (here.ny < -0.9 && isNaN(swimTarget)) {
                ceilingTime += dt;
                if (ceilingTime > 3 + Math.random() * 3) {
                    ceilingTime = 0;
                    vx = 0;
                    vy = 60;
                    gy += 14;
                    phys = "air";
                    reacted("surprised", 700);
                    return;
                }
            } else {
                ceilingTime = 0;
            }
            if (!moved) {
                // La inercia que traiga (al pegarse volando…) se va frenando
                swimV *= Math.exp(-4 * dt);
                swimD = ((swimD + swimV * dt) % tr.len + tr.len) % tr.len;
            }
            // Sigue el recorrido con suavidad (al salir del marco, al pegarse…); con forma, se
            // separa del marco lo justo para que se vea entera
            const p = pointAt(tr, swimD), k = Math.min(1, dt * 14);
            const lift = Math.max(0, morph) * Math.max(0, (lastShape === 2 ? 66 : 54) - normalRadius(p) + embed);   // (Clawd, con las patas enteras)
            gx += (p.x - p.nx * lift - gx) * k;
            gy += (p.y - p.ny * lift - gy) * k;
            return;
        }

        // En el aire: gravedad
        vy += 2600 * dt;
        vx *= 1 - 0.25 * dt;
        let nx = gx + vx * dt, ny = gy + vy * dt;

        if (entering) {
            if (nx >= tr.L && nx <= tr.R)
                entering = false;
            gx = nx;
            gy = Math.min(ny, tr.B);
            return;
        }
        // Paredes (salvo que al otro lado haya otra pantalla): se pega, o si va muy rápido
        // atraviesa al workspace de ese lado
        if (nx < tr.L && !screenAt(nx - bodyRx - barW, ny)) {
            if (thrown && vx < -1100 && crossToWs(-1, s))
                return;
            gx = tr.L;
            gy = Math.max(tr.T, Math.min(tr.B, ny));
            attach(s, -vx, true);
            return;
        }
        if (nx > tr.R && !screenAt(nx + bodyRx + frame, ny)) {
            if (thrown && vx > 1100 && crossToWs(1, s))
                return;
            gx = tr.R;
            gy = Math.max(tr.T, Math.min(tr.B, ny));
            attach(s, vx, true);
            return;
        }
        if (ny < tr.T && vy < 0 && !screenAt(nx, ny - bodyRy - frame)) {
            gx = nx;
            gy = tr.T;
            attach(s, -vy, false);
            return;
        }
        if (ny > tr.B && vy > 0 && !screenAt(nx, ny + bodyRy + frame)) {
            gx = nx;
            gy = tr.B;
            attach(s, vy, false);
            return;
        }
        gx = nx;
        gy = ny;
    }

    function openInput(): void {
        if (locked)
            return;
        touch();
        shown = true;
        asking = true;
        bubbleShown = false;
    }

    function showReply(): void {
        bubbleShown = true;
        hideTimer.restart();
    }

    // Para leer la configuración de Caelestia (propiedad adjunta Config)
    Item {
        id: cfg
    }

    Component.onCompleted: {
        mochiWs = Hyprland.focusedWorkspace?.id ?? -1;
        const s = Quickshell.screens[0];
        if (gx < 0 && s) {
            gx = s.x + s.width - 120;
            gy = s.y + s.height - 140;
        }
    }

    FileView {
        path: shell.stateDir + "/pos"
        onLoaded: {
            const [x, y] = text().trim().split(" ").map(Number);
            if (!isNaN(x) && !isNaN(y)) {
                // Estaba en el nido (dentro de la barra): vuelve a él
                const s = shell.nearestScreen(x, y);
                if (s && x < s.x + shell.barW) {
                    shell.enterNest(s);
                    return;
                }
                shell.gx = x;
                shell.gy = y;
                shell.settle();
            }
        }
    }

    Connections {
        target: Brain

        function onBusyChanged(): void {
            shell.touch();
            shell.remark = "";
            if (Brain.busy) {
                shell.bubbleShown = true;
                hideTimer.stop();
            } else {
                shell.showReply();
            }
        }
    }

    Connections {
        target: Hyprland

        function onFocusedWorkspaceChanged(): void {
            shell.wsChanged();
        }
    }

    Timer {
        id: followTimer

        onTriggered: if (shell.shown && !shell.present && shell.phys !== "hidden") shell.arrive()
    }

    // Lo que hace Mind: gestos, y solo habla para avisar de la batería (nunca interrumpe)
    Connections {
        target: Mind

        function onReact(face: string, ms: int): void {
            if (!shell.dnd && shell.present && !Brain.busy && !shell.asking && !shell.dragging && shell.phys !== "hidden")
                shell.reacted(face, ms);
        }
        function onDance(ms: int): void {
            if (!shell.dnd && shell.present && !Brain.busy && !shell.asking && !shell.dragging && shell.phys !== "hidden")
                shell.reacted("dance", ms);
        }
        function onShape(name: string, ms: int): void {
            if (!shell.dnd && shell.present && !shell.asking && !shell.dragging && shell.phys === "swim")
                shell.shapeShift(name, ms);
        }
        function onCoding(): void {
            if (shell.dnd || !shell.present || shell.asking || shell.dragging || Brain.busy)
                return;
            if (shell.codeShape && shell.phys === "swim")
                shell.shapeShift(shell.codeShape, 3000);
            else
                shell.reacted("focused", 1800);
        }
        function onGlance(x: real, y: real): void {
            shell.glanceX = x;
            shell.glanceY = y;
            shell.glanceUntil = Date.now() + 1400;
        }
        function onSay(text: string, face: string): void {
            if (shell.dnd || !shell.shown || Brain.busy || shell.asking || shell.voiceWaiting || shell.dragging || (shell.bubbleShown && !shell.remark))
                return;
            if (!shell.present || shell.phys === "hidden")
                shell.touch();
            shell.remark = text;
            shell.bubbleShown = true;
            hideTimer.restart();
            shell.reacted(face, 2500);
        }
    }

    onBubbleShownChanged: if (!bubbleShown) remark = ""
    onSwimTargetChanged: {
        if (isNaN(swimTarget))
            slipping = false;
        else if (!slipping)
            startTrip();
    }
    onAskingChanged: if (asking) remark = ""

    // El bocadillo se va solo al rato (más tiempo cuanto más largo)
    Timer {
        id: hideTimer

        interval: shell.remark ? 5500 : Math.min(30000, 6000 + Brain.reply.length * 45)
        onTriggered: if (!Brain.busy) shell.bubbleShown = false
    }

    // Si el oído se cae, volver a lanzarlo
    Timer {
        id: earsRestart

        interval: 2000
        onTriggered: shell.earsCooling = false
    }

    Process {
        id: ears

        command: [Quickshell.shellDir + "/ears.sh"]
        // (nunca con la pantalla bloqueada; el relanzamiento también pasa por aquí: asignar
        // `running` a mano rompía este enlace y lo volvía a encender estando bloqueado)
        running: shell.earsOn && !shell.locked && !shell.earsCooling

        stdout: SplitParser {
            onRead: line => {
                if (line === "ready") {
                    shell.earsReady = true;
                } else if (line === "wake" || line === "hearing") {
                    shell.touch();
                    shell.shown = true;
                    shell.asking = false;
                    shell.voiceWaiting = true;
                    shell.bubbleShown = false;
                } else if (line.startsWith("text:")) {
                    shell.voiceWaiting = false;
                    shell.shown = true;
                    shell.asking = false;
                    shell.heard = line.slice(5).trim();
                    Brain.send(shell.heard, true);
                } else if (line === "idle") {
                    shell.voiceWaiting = false;
                } else if (line.startsWith("error:")) {
                    console.warn("ears:", line);
                    shell.earsOn = false;
                }
            }
        }

        onExited: {
            shell.earsReady = false;
            shell.voiceWaiting = false;
            if (shell.earsOn && !shell.locked) {
                shell.earsCooling = true;
                earsRestart.restart();
            }
        }
    }

    IpcHandler {
        target: "pet"

        // Doble +: si está a la vista se esconde; si no, aparece y escucha
        function toggle(): void {
            if (shell.shown) {
                shell.asking = false;
                shell.shown = false;
            } else {
                shell.openInput();
            }
        }
        function appear(): void {
            shell.touch();
            shell.shown = true;
        }
        function hide(): void {
            shell.asking = false;
            shell.shown = false;
        }
        function talk(): void {
            shell.openInput();
        }
        function ears(): void {
            shell.earsOn = !shell.earsOn;
        }
        function history(): void {
            Qt.openUrlExternally("file://" + Brain.historyDir);
        }
        // Probar una expresión (ver eyeTarget en Blob.qml)
        function face(name: string): void {
            shell.reacted(name, 2500);
        }
        // Probar la marcha: ir px a lo largo del marco (+ = antihorario), con ganas `energy`
        function walk(px: real, energy: real): void {
            if (shell.phys !== "swim")
                return;
            shell.energy = energy > 0 ? energy : 1;
            const tr = shell.track(shell.nearestScreen(shell.gx, shell.gy));
            shell.swimTarget = ((shell.swimD + px) % tr.len + tr.len) % tr.len;
        }
        // Probar el buceo: px a lo largo del marco, mode hidden|peek
        function dive(px: real, mode: string): void {
            if (shell.phys === "swim")
                shell.dive(px, mode === "peek" ? "peek" : "hidden", false, 1);
        }
        // Probar la llegada buceando por el borde de abajo ("left": como si vinieras de la izquierda)
        function nest(): void {
            shell.goNest();
        }
        // Imitar una forma: gear | claude | heart | star | arrow (ms, 0 = 2,5 s)
        function shape(name: string, ms: int): void {
            shell.shapeShift(name, ms);
        }
        // Qué suena y si cuenta como música (solo con música baila)
        function music(): string {
            const p = Mind.player;
            return p ? `${Mind.musicPlaying ? "música" : "no música"}: ${p.identity} «${p.trackTitle}» de ${p.trackArtist} ${p.metadata?.["xesam:url"] ?? ""}` : "nada";
        }
        // Se toma un café (lo que hace al activar la cafeína)
        function coffee(): void {
            shell.coffee();
        }
        // Arcoíris durante ms (0 = 5 s)
        function rainbow(ms: int): void {
            shell.rainbow(ms);
        }
        // Probar el sueño: nod | yawn | doze | wake
        function sleep(what: string): void {
            shell.sleepTest(what);
        }
        // Probar el humor de una hora (energía 0.5-1.25; se recalcula al minuto)
        function energy(e: real): void {
            shell.dayEnergy = e;
        }
        // Probar el asomo del nido (como si pasaras el ratón por encima)
        function nestPeek(on: bool): void {
            shell.nestHover = on;
        }
        function arrive(from: string): void {
            const id = Hyprland.focusedWorkspace?.id ?? 1;
            shell.mochiWs = from === "left" ? id - 1 : id + 1;
            shell.arrive();
        }
        // Dar un saltito (para probar el movimiento)
        function jump(): void {
            shell.hopsLeft = 1;
            shell.hop();
        }
        function state(): string {
            return `${shell.phys} ${Math.round(shell.gx)},${Math.round(shell.gy)} v=${Math.round(shell.vx)},${Math.round(shell.vy)} ws=${shell.mochiWs} present=${shell.present} shown=${shell.shown}`;
        }
        function ask(text: string): void {
            if (shell.locked)
                return;
            shell.touch();
            shell.shown = true;
            shell.asking = false;
            Brain.send(text);
        }
    }

    // Posición del cursor (para que Mochi te mire), preguntando a Hyprland por su socket
    Socket {
        id: hypr

        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/hypr/${Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")}/.socket.sock`

        onConnectedChanged: {
            if (connected) {
                write("j/cursorpos");
                flush();
            }
        }

        parser: SplitParser {
            splitMarker: "}"
            onRead: data => {
                try {
                    const p = JSON.parse(data + "}");
                    shell.cursorX = p.x;
                    shell.cursorY = p.y;
                    // Mira al ratón, salvo que algo le haya llamado la atención
                    const now = Date.now(), focusing = now < shell.focusUntil, glancing = now < shell.glanceUntil;
                    const tx = focusing ? shell.focusX : glancing ? shell.glanceX : p.x;
                    const ty = focusing ? shell.focusY : glancing ? shell.glanceY : p.y;
                    const dx = tx - shell.gx, dy = ty - shell.gy;
                    const d = Math.hypot(dx, dy);
                    shell.cursorNear = Math.hypot(p.x - shell.gx, p.y - shell.gy) < 220;
                    shell.lookX = d < 20 ? 0 : dx / (d + 60);
                    shell.lookY = d < 20 ? 0 : dy / (d + 60);
                } catch (e) {}
            }
        }
    }

    Timer {
        running: shell.shown && !shell.dragging
        repeat: true
        interval: 90
        onTriggered: if (!hypr.connected) hypr.connected = true
    }

    // Mirar el fondo alrededor: si es oscuro, Mochi se vuelve blanco (con margen para no parpadear)
    Process {
        id: bgProc

        property string edgeOut
        property string edgeFor

        onExited: code => {
            if (code === 0 && edgeOut) {
                shell.edgeScreen = edgeFor;
                shell.edgeFile = edgeOut;
                shell.edgeGen++;
            }
        }

        stdout: SplitParser {
            onRead: line => {
                const [l, col] = line.trim().split(" ");
                const lum = parseFloat(l);
                if (lum < 0.4)
                    shell.lightBody = true;
                else if (lum > 0.5)
                    shell.lightBody = false;
                if (col && col.startsWith("#"))
                    shell.frameColor = col;
            }
        }
    }

    Timer {
        running: shell.shown && shell.phys !== "held"
        repeat: true
        triggeredOnStart: true
        interval: 2000
        onTriggered: shell.checkBg()
    }

    FrameAnimation {
        // (también volando por otro workspace, aunque no se vea)
        running: shell.shown && (shell.present || shell.phys === "air" || shell.phys === "held")
        onTriggered: shell.physStep(frameTime)
    }

    // Paseos: de vez en cuando nada a otro sitio del marco, da saltitos por el suelo o se
    // impulsa desde una pared (y la gravedad lo devuelve al marco)
    Timer {
        running: shell.shown && shell.present && !shell.fsHide && !shell.dozing && !shell.dnd && shell.phys === "swim" && isNaN(shell.swimTarget) && !shell.sipping && !shell.asking && !shell.bubbleShown && !shell.voiceWaiting && !Brain.busy
        repeat: true
        interval: 9000
        onTriggered: {
            interval = (7000 + Math.random() * 11000) / shell.dayEnergy;
            const s = shell.nearestScreen(shell.gx, shell.gy), tr = shell.track(s), p = shell.pointAt(tr, shell.swimD);
            const r = Math.random();
            if (r >= 0.38 && r < 0.62) {
                // Se zambulle y sale más allá (a veces sin que se le vea nada, a veces asomando)
                for (let i = 0; i < 6; i++) {
                    const dist = (Math.random() < 0.5 ? -1 : 1) * (350 + Math.random() * 700), q = shell.pointAt(tr, shell.swimD + dist);
                    if (Math.hypot(q.x - shell.cursorX, q.y - shell.cursorY) > 300 && q.ny > -0.9 && !shell.inPanel(q.x, q.y, shell.bodyRx + 60)) {
                        shell.dive(dist, Math.random() < 0.5 ? "hidden" : "peek", false, shell.dayEnergy);
                        return;
                    }
                }
            }
            if (r < 0.38) {
                // A otro sitio (no muy lejos, y que no sea junto al ratón)
                for (let i = 0; i < 6; i++) {
                    const d = shell.swimD + (Math.random() * 2 - 1) * 700, q = shell.pointAt(tr, d);
                    if (Math.hypot(q.x - shell.cursorX, q.y - shell.cursorY) > 300 && q.ny > -0.9 && !shell.inPanel(q.x, q.y, shell.bodyRx + 60)) {
                        shell.energy = (0.75 + Math.random() * 0.6) * shell.dayEnergy;
                        shell.swimTarget = ((d % tr.len) + tr.len) % tr.len;
                        break;
                    }
                }
            } else if (r < 0.8 && p.ny > 0.9) {
                shell.hopsLeft = 1 + Math.floor(Math.random() * 3);
                shell.hopDir = Math.random() < 0.5 ? -1 : 1;
                shell.hop();
            } else if (r < 0.9 && Math.abs(p.nx) > 0.9) {
                shell.pushOff();
            }
        }
    }

    Timer {
        running: true
        repeat: true
        triggeredOnStart: true
        interval: 60000
        onTriggered: {
            const d = new Date();
            const e = shell.energyAt(d.getHours() + d.getMinutes() / 60);
            shell.dayEnergy = shell.caffeine ? Math.max(1.2, e) : e;
        }
    }

    // Estado de bloqueo (lo escribe Caelestia) y lo que le cuenta a la pantalla de bloqueo
    FileView {
        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/caelestia-locked`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: shell.locked = text().trim() === "1"
    }

    FileView {
        id: lockState

        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/mochi-lock.json`
        printErrors: false
        blockLoading: true
    }

    // Tras volver del bloqueo, a su sitio de antes (o a su nido)
    Timer {
        id: backHome

        interval: 1800
        onTriggered: {
            const pre = shell.preLock;
            shell.preLock = null;
            if (!pre || shell.phys !== "swim")
                return;
            if (pre.nest) {
                shell.goNest();
                return;
            }
            const tr = shell.track(shell.nearestScreen(shell.gx, shell.gy));
            const dist = shell.trackDiff(tr, shell.swimD, pre.d);
            if (Math.abs(dist) > 250)
                shell.dive(dist, "hidden", false, 1.3);
            else if (Math.abs(dist) > 10)
                shell.swimTarget = pre.d;
        }
    }

    Timer {
        id: tempShapeTimer

        onTriggered: shell.tempShape = ""
    }

    Timer {
        id: rainbowTimer

        onTriggered: shell.rainbowAmt = 0
    }

    Timer {
        id: coffeeTimer

        interval: 700
        onTriggered: shell.coffee()
    }

    // Saca la taza, mira el café, sorbo (ojitos felices), la baja, otro sorbo más largo, la
    // guarda… y subidón
    SequentialAnimation {
        id: coffeeSeq

        ScriptAction {
            script: {
                shell.sip = 0;
                shell.kicked(-0.8, 1.2);
            }
        }
        NumberAnimation {
            target: shell
            property: "cupAmt"
            from: 0
            to: 1
            duration: 650
            easing.type: Easing.OutBack
        }
        ScriptAction {
            script: shell.lookAtCup(1400)
        }
        PauseAnimation {
            duration: 700
        }
        ScriptAction {
            script: shell.reacted("happy", 1900)
        }
        NumberAnimation {
            target: shell
            property: "sip"
            to: 1
            duration: 700
            easing.type: Easing.InOutSine
        }
        ScriptAction {
            script: shell.kicked(0.5, -0.7)   // glup
        }
        PauseAnimation {
            duration: 700
        }
        ScriptAction {
            script: shell.kicked(0.5, -0.7)
        }
        PauseAnimation {
            duration: 350
        }
        NumberAnimation {
            target: shell
            property: "sip"
            to: 0
            duration: 550
            easing.type: Easing.InOutSine
        }
        ScriptAction {
            script: {
                shell.lookAtCup(1200);
                shell.reacted("smile", 1100);
            }
        }
        PauseAnimation {
            duration: 1000
        }
        ScriptAction {
            script: shell.reacted("happy", 2300)
        }
        NumberAnimation {
            target: shell
            property: "sip"
            to: 1
            duration: 650
            easing.type: Easing.InOutSine
        }
        ScriptAction {
            script: shell.kicked(0.5, -0.7)
        }
        PauseAnimation {
            duration: 600
        }
        ScriptAction {
            script: shell.kicked(0.5, -0.7)
        }
        PauseAnimation {
            duration: 600
        }
        ScriptAction {
            script: shell.kicked(0.6, -0.8)
        }
        PauseAnimation {
            duration: 400
        }
        NumberAnimation {
            target: shell
            property: "sip"
            to: 0
            duration: 550
            easing.type: Easing.InOutSine
        }
        PauseAnimation {
            duration: 250
        }
        NumberAnimation {
            target: shell
            property: "cupAmt"
            to: 0
            duration: 450
            easing.type: Easing.InBack
        }
        ScriptAction {
            script: {
                shell.reacted("excited", 1600);
                shell.kicked(-1.4, 2.8);
            }
        }
    }

    // (si le interrumpen: la guarda deprisa)
    ParallelAnimation {
        id: cupAway

        NumberAnimation {
            target: shell
            property: "cupAmt"
            to: 0
            duration: 250
        }
        NumberAnimation {
            target: shell
            property: "sip"
            to: 0
            duration: 250
        }
    }

    // Con cafeína, de vez en cuando le da un subidón: tiembla un momento con los ojos como platos
    Timer {
        running: shell.caffeine && shell.present && !shell.dnd && shell.phys === "swim" && !shell.sipping && !shell.asking && !Brain.busy
        repeat: true
        interval: 7000
        onTriggered: {
            interval = 6000 + Math.random() * 8000;
            shell.reacted("surprised", 700);
            jitter.restart();
        }
    }

    SequentialAnimation {
        id: jitter

        loops: 6

        ScriptAction {
            script: shell.kicked(0.9, -0.9)
        }
        PauseAnimation {
            duration: 45
        }
        ScriptAction {
            script: shell.kicked(-0.9, 0.9)
        }
        PauseAnimation {
            duration: 45
        }
    }

    // Te vas de encima del nido: se vuelve a meter al rato
    Timer {
        id: nestLeave

        interval: 600
        onTriggered: shell.nestHover = false
    }

    Timer {
        id: hopAgain

        interval: 160
        onTriggered: shell.hop()
    }

    // Si no le haces caso, se hunde en el marco (solo asoman los ojos)
    Timer {
        id: idleHide

        running: shell.shown && shell.present && shell.phys !== "hidden" && shell.phys !== "nest" && shell.phys !== "dive" && !shell.asking && !shell.bubbleShown && !shell.voiceWaiting && !Brain.busy
        interval: shell.hideAfter * Math.max(0.5, Math.min(1.3, shell.dayEnergy))
        onTriggered: {
            if (shell.phys !== "swim") {
                restart();
                return;
            }
            shell.goNest();
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            required property ShellScreen modelData

            readonly property bool here: shell.screenAt(shell.gx, shell.gy) === modelData
            readonly property bool hasEdge: shell.edgeScreen === modelData.name && edgeImg.status === Image.Ready

            screen: modelData
            visible: shell.shown
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            // Por encima de la capa de Caelestia: si no, la sombra del marco le cae encima y el
            // cristal del marco (con blur) se aclara con él debajo → se nota la unión
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "mochi"
            WlrLayershell.keyboardFocus: shell.asking && here ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            // Solo Mochi y su bocadillo reciben clics; el resto del escritorio pasa de largo
            mask: Region {
                item: mochi.visible ? mochi : null

                Region {
                    item: bubble.visible ? bubble : null
                }
            }

            // Paneles abiertos de Caelestia en esta pantalla
            FileView {
                path: `${Quickshell.env("XDG_RUNTIME_DIR")}/caelestia-panels-${win.modelData.name}.json`
                watchChanges: true
                printErrors: false
                onFileChanged: reload()
                onLoaded: shell.setPanels(win.modelData.name, text())
            }

            Image {
                id: edgeImg

                visible: false
                cache: false
                asynchronous: false
                smooth: true
                source: shell.edgeScreen === win.modelData.name && shell.edgeFile ? "file://" + shell.edgeFile : ""
            }

            // Cuerpo de Mochi: mismo color, transparencia y sombra que el marco de Caelestia.
            // Se recorta al interior del marco (el marco ya lo pinta Caelestia) y el shader lo
            // funde con él al tocarlo.
            Item {
                id: interior

                visible: mochi.visible
                x: shell.barW
                y: shell.frame
                width: win.width - shell.barW - shell.frame
                height: win.height - 2 * shell.frame
                clip: true

                Item {
                    x: -interior.x
                    y: -interior.y
                    width: win.width
                    height: win.height
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        blurMax: 15
                        shadowColor: Qt.alpha(Theme.shadow, 0.7)
                    }

                    // El cuerpo: metaballs en un shader (mochi.frag). Solo se calcula en una caja
                    // alrededor de Mochi.
                    ShaderEffect {
                        id: bodyFx

                        readonly property real half: 140

                        x: mochi.x + mochi.width / 2 - half + shell.bodyOffX
                        y: mochi.y + mochi.height / 2 - half + shell.bodyOffY
                        width: 2 * half
                        height: 2 * half

                        property vector2d size: Qt.vector2d(width, height)
                        property vector4d body: Qt.vector4d(half, half, mochi.bodyRx, mochi.bodyRy)
                        property vector4d mass: Qt.vector4d(half + mochi.massX - mochi.width / 2, half + mochi.massY - mochi.height / 2, mochi.massR, 0)
                        property vector4d tail: Qt.vector4d(half + mochi.tailX - mochi.width / 2, half + mochi.tailY - mochi.height / 2, mochi.tailR, 0)
                        property vector4d wobA: mochi.wobA
                        property vector4d wobB: mochi.wobB
                        property vector4d frame: Qt.vector4d(shell.barW - x, shell.frame - y, win.width - shell.frame - x, win.height - shell.frame - y)
                        property color color: shell.frameColor   // de reserva, sin textura del marco
                        property vector4d view: Qt.vector4d(x, y, edgeImg.sourceSize.width, win.hasEdge ? 1 : 0)
                        property var edge: edgeImg
                        property real blobK: 26
                        property real frameK: shell.frameSmoothing
                        property real bandOnly: 0
                        property vector4d shape: Qt.vector4d(shell.lastShape, Math.max(0, shell.morph), shell.shapeRot, 44)
                        // Clawd es naranja (el de Claude)
                        property vector4d shapeTint: shell.lastShape === 2 ? Qt.vector4d(0.851, 0.467, 0.341, 1) : Qt.vector4d(0, 0, 0, 0)
                        property vector4d rainbow: Qt.vector4d(shell.rainbowAmt, shell.rainbowT, 0, 0)
                        // bracito hasta el asa de la taza
                        property vector4d arm: Qt.vector4d(shell.cupGeom.hx - win.modelData.x - x, shell.cupGeom.hy - win.modelData.y - y, Math.max(0, shell.cupAmt), 6)

                        fragmentShader: Qt.resolvedUrl("mochi.frag.qsb")
                    }

                    // La taza de café (con la misma sombra que el cuerpo)
                    Canvas {
                        id: cup

                        readonly property real t: shell.cupT
                        readonly property real steam: Math.max(0, 1 - 2.2 * shell.sip)
                        readonly property real side: shell.cupSide
                        readonly property color mug: "#d4704f"   // taza de barro
                        readonly property color mugShade: "#a9543a"

                        visible: mochi.visible && shell.cupAmt > 0.01
                        width: 64
                        height: 76
                        x: shell.cupGeom.x - win.modelData.x - width / 2
                        y: shell.cupGeom.y - win.modelData.y - height / 2
                        rotation: shell.cupGeom.rot
                        scale: Math.max(0, shell.cupAmt)
                        onTChanged: requestPaint()
                        onSideChanged: requestPaint()
                        onMugChanged: requestPaint()

                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            ctx.translate(32, 38);   // centro de la taza; arriba = -y
                            const hs = -side;          // el asa, hacia Mochi
                            // Asa
                            ctx.strokeStyle = mugShade;
                            ctx.lineWidth = 3.4;
                            ctx.beginPath();
                            ctx.arc(hs * 10.5, 0.5, 6.2, hs > 0 ? -Math.PI / 2 : Math.PI / 2, hs > 0 ? Math.PI / 2 : 3 * Math.PI / 2);
                            ctx.stroke();
                            // Cuerpo (algo más estrecho abajo)
                            ctx.fillStyle = mug;
                            ctx.beginPath();
                            ctx.moveTo(-11.5, -11);
                            ctx.lineTo(11.5, -11);
                            ctx.lineTo(10, 9);
                            ctx.quadraticCurveTo(9.6, 12.5, 6, 12.5);
                            ctx.lineTo(-6, 12.5);
                            ctx.quadraticCurveTo(-9.6, 12.5, -10, 9);
                            ctx.closePath();
                            ctx.fill();
                            // Sombra de un lado, para que tenga volumen
                            ctx.fillStyle = Qt.rgba(0, 0, 0, 0.13);
                            ctx.beginPath();
                            ctx.moveTo(4.5, -11);
                            ctx.lineTo(11.5, -11);
                            ctx.lineTo(10, 9);
                            ctx.quadraticCurveTo(9.6, 12.5, 6, 12.5);
                            ctx.lineTo(3.5, 12.5);
                            ctx.closePath();
                            ctx.fill();
                            // Boca: el borde y el café
                            ctx.fillStyle = mugShade;
                            ctx.beginPath();
                            ctx.ellipse(-11.5, -13.6, 23, 5.2);
                            ctx.fill();
                            ctx.fillStyle = "#4a2c1f";
                            ctx.beginPath();
                            ctx.ellipse(-9.6, -13, 19.2, 3.8);
                            ctx.fill();
                            ctx.fillStyle = Qt.rgba(1, 0.85, 0.7, 0.25);
                            ctx.beginPath();
                            ctx.ellipse(-4, -12.6, 6, 1.4);
                            ctx.fill();
                            // Vapor: dos hilos que suben ondulando (se va al beber)
                            if (steam > 0) {
                                ctx.lineCap = "round";
                                for (let i = 0; i < 2; i++) {
                                    const x0 = i ? 4 : -4;
                                    ctx.beginPath();
                                    for (let j = 0; j <= 12; j++) {
                                        const f = j / 12, y = -17 - f * 20;
                                        const x = x0 + 2.6 * Math.sin(f * 7 - t * 4 + i * 2.2) * (0.4 + f);
                                        if (j)
                                            ctx.lineTo(x, y);
                                        else
                                            ctx.moveTo(x, y);
                                    }
                                    const g = ctx.createLinearGradient(0, -17, 0, -37);
                                    const rgb = "160,155,150";   // gris: se ve sobre fondo claro y oscuro
                                    g.addColorStop(0, `rgba(${rgb},${(0.75 * steam).toFixed(3)})`);
                                    g.addColorStop(1, `rgba(${rgb},0)`);
                                    ctx.strokeStyle = g;
                                    ctx.lineWidth = 2.2;
                                    ctx.stroke();
                                }
                            }
                        }
                    }
                }
            }

            // Segunda pasada, sin sombra: solo la franja de 6 px que tapa el borde suavizado del
            // marco junto a Mochi (con la sombra, esa franja oscurecía el marco)
            ShaderEffect {
                visible: mochi.visible
                x: bodyFx.x
                y: bodyFx.y
                width: bodyFx.width
                height: bodyFx.height

                property vector2d size: bodyFx.size
                property vector4d body: bodyFx.body
                property vector4d mass: bodyFx.mass
                property vector4d tail: bodyFx.tail
                property vector4d wobA: bodyFx.wobA
                property vector4d wobB: bodyFx.wobB
                property vector4d frame: bodyFx.frame
                property color color: bodyFx.color
                property vector4d view: bodyFx.view
                property var edge: edgeImg
                property real blobK: bodyFx.blobK
                property real frameK: bodyFx.frameK
                property real bandOnly: 1
                property vector4d shape: bodyFx.shape
                property vector4d shapeTint: bodyFx.shapeTint
                property vector4d rainbow: bodyFx.rainbow
                property vector4d arm: bodyFx.arm

                fragmentShader: Qt.resolvedUrl("mochi.frag.qsb")
            }

            // En el nido, Mochi es un icono más de la barra: su silueta del color de los iconos
            // de Caelestia, con los ojos como huecos (parpadea, mira un poco, respira)
            Canvas {
                id: nestIcon

                readonly property real blink: mochi.blink
                readonly property real lx: shell.lookX
                readonly property real ly: shell.lookY
                readonly property string face: mochi.face
                // de madrugada, si no andas cerca, duerme (ojos cerrados y respira más despacio)
                readonly property bool asleep: shell.dnd || (!shell.caffeine && (mochi.dozing || (shell.drowsy > 0.8 && !shell.cursorNear)))
                readonly property real nod: mochi.nod
                onNodChanged: requestPaint()
                onAsleepChanged: requestPaint()
                readonly property color ink: Theme.secondary
                property real breath: 0

                visible: mochi.visible && shell.phys === "nest" && opacity > 0
                opacity: Math.max(0, 1 - shell.nestPeek * 2.5)
                width: 30
                height: 28
                x: shell.barW / 2 - width / 2
                y: shell.gy - win.modelData.y - height / 2 - 2

                onBlinkChanged: requestPaint()
                onLxChanged: requestPaint()
                onLyChanged: requestPaint()
                onFaceChanged: requestPaint()
                onInkChanged: requestPaint()
                onBreathChanged: requestPaint()

                SequentialAnimation on breath {
                    running: nestIcon.visible
                    loops: Animation.Infinite

                    NumberAnimation {
                        to: 1
                        duration: nestIcon.asleep ? 2800 : 1800
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        to: 0
                        duration: nestIcon.asleep ? 2800 : 1800
                        easing.type: Easing.InOutSine
                    }
                }

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    // Respira: un pelín más ancho y bajo, apoyado en la base
                    const b = breath, sx = 1 + 0.035 * b, sy = 1 - 0.045 * b;
                    ctx.save();
                    ctx.translate(15, 24);
                    ctx.rotate(nod * 0.13 * mochi.nodDir);   // cabezada: se ladea
                    ctx.scale(sx, sy * (1 - 0.06 * nod));
                    ctx.translate(-15, -24);
                    ctx.fillStyle = ink;
                    ctx.beginPath();
                    ctx.moveTo(4.2, 20.5);
                    ctx.bezierCurveTo(2.6, 8.5, 9, 3, 15, 3);
                    ctx.bezierCurveTo(21, 3, 27.4, 8.5, 25.8, 20.5);
                    ctx.quadraticCurveTo(25.6, 24, 22.4, 24);
                    ctx.lineTo(7.6, 24);
                    ctx.quadraticCurveTo(4.4, 24, 4.2, 20.5);
                    ctx.fill();
                    ctx.restore();

                    // Ojos: huecos en la silueta
                    ctx.globalCompositeOperation = "destination-out";
                    const ex = lx * 1.6 * (1 - nod), ey = ly * 1.3 + 1.2 * b + 1.6 * nod;
                    const happy = ["happy", "love", "excited", "dance", "proud"].includes(face);
                    for (const cx of [11, 19]) {
                        const x = cx + ex, y = 14 + ey;
                        if (asleep) {
                            // dormido: rayitas
                            ctx.fillStyle = "black";
                            ctx.beginPath();
                            ctx.roundedRect(x - 2.1, y + 0.6, 4.2, 1.3, 0.65, 0.65);
                            ctx.fill();
                        } else if (happy) {
                            // ^ ^
                            ctx.lineWidth = 1.7;
                            ctx.lineCap = "round";
                            ctx.beginPath();
                            ctx.moveTo(x - 2.1, y + 1.2);
                            ctx.quadraticCurveTo(x, y - 2.2, x + 2.1, y + 1.2);
                            ctx.stroke();
                        } else {
                            const w = 3.5, h = Math.max(0.9, 4.7 * (1 - 0.85 * Math.max(blink, 0.9 * nod, 0.35 * shell.drowsy)));
                            ctx.fillStyle = "black";
                            ctx.beginPath();
                            ctx.roundedRect(x - w / 2, y - h / 2, w, h, Math.min(w, h) / 2, Math.min(w, h) / 2);
                            ctx.fill();
                        }
                    }
                    ctx.globalCompositeOperation = "source-over";
                }
            }

            Blob {
                id: mochi

                // Solo en el workspace donde vive, y se aparta si hay algo a pantalla completa
                visible: shell.present && !shell.fsHide
                x: shell.gx - win.modelData.x - width / 2
                y: shell.gy - win.modelData.y - height / 2
                mood: shell.mood
                dragging: shell.dragging
                worldX: shell.gx
                worldY: shell.gy
                falling: shell.phys === "air" && shell.vy > 900
                bodyColor: shell.frameColor
                hidden: shell.phys === "hidden"
                // (en el nido, en reposo, lo que se ve es su icono en la barra; los ojos de
                // verdad salen al asomarse)
                drowsy: shell.caffeine ? 0 : shell.drowsy
                onDozingChanged: if (visible) shell.dozing = dozing
                inkOverride: shell.lastShape === 2 && shell.morph > 0.5 ? "#1c1b1b" : "transparent"   // Clawd: ojos oscuros
                eyesOff: (shell.phys === "dive" && shell.diveUnder > 0.4) || (shell.phys === "nest" && shell.nestPeek < 0.4)
                // los ojos se recortan al interior del marco, como el cuerpo (así se sumergen),
                // salvo por la barra de la izquierda (el nido)
                clipRect: Qt.rect(-x, shell.frame - y, win.width - shell.frame, win.height - 2 * shell.frame)
                sleepy: shell.dnd || (shell.phys === "hidden" && !shell.cursorNear)
                talking: Brain.talking
                music: Mind.musicPlaying

                Connections {
                    target: shell

                    function onSplatted(strength: real, horizontal: bool): void {
                        mochi.splat(strength, horizontal);
                    }
                    function onReacted(name: string, ms: int): void {
                        mochi.react(name, ms);
                    }
                    function onKicked(ax: real, ay: real): void {
                        mochi.kick(ax, ay);
                    }
                    function onLeaned(v: real): void {
                        mochi.lean(v);
                    }
                    function onWoke(): void {
                        mochi.wake();
                    }
                    function onSleepTest(what: string): void {
                        if (what === "nod")
                            mochi.startNod();
                        else if (what === "yawn")
                            mochi.yawn();
                        else if (what === "doze") {
                            mochi.nods = 3;
                            mochi.startNod();
                        } else if (what === "wake")
                            mochi.wake();
                    }
                }
                // (en el nido la barra es estrecha: mira moviendo poco los ojos, salvo asomado)
                readonly property real lookScale: shell.phys === "nest" ? 0.25 + 0.75 * shell.nestPeek : 1
                lookX: shell.dragging ? 0 : shell.lookX * lookScale
                lookY: shell.dragging ? 0 : shell.lookY * lookScale

                MouseArea {
                    property real px
                    property real py
                    property bool moved
                    property string wasPhys
                    // Caricias: pasar el ratón de lado a lado por encima
                    property int petCount
                    property int petDir
                    property real petLastX
                    property real petStart

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    cursorShape: shell.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

                    // Pasar por encima lo despierta si estaba escondido
                    onContainsMouseChanged: {
                        // En el nido se asoma al pasar por encima, y se vuelve a meter al rato de irte
                        if (containsMouse) {
                            mochi.wake();   // pasarle el ratón lo despierta
                            shell.nestHover = true;
                            nestLeave.stop();
                        } else {
                            nestLeave.restart();
                        }
                        if (containsMouse && shell.phys === "hidden")
                            shell.touch();
                    }

                    // Clic derecho: historial · clic central: activar/silenciar el micro
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton)
                            Qt.openUrlExternally("file://" + Brain.historyDir);
                        else if (mouse.button === Qt.MiddleButton)
                            shell.earsOn = !shell.earsOn;
                    }

                    onPressed: mouse => {
                        if (mouse.button !== Qt.LeftButton)
                            return;
                        px = mouse.x;
                        py = mouse.y;
                        moved = false;
                        wasPhys = shell.phys;
                        if (wasPhys !== "nest")
                            shell.touch();
                        else
                            idleHide.restart();
                        // Agarrado (también en el aire)
                        hopAgain.stop();
                        shell.hopsLeft = 0;
                        shell.swimTarget = NaN;
                        shell.entering = false;
                        shell.flung = false;
                        shell.phys = "held";
                        shell.vx = shell.vy = shell.hvx = shell.hvy = 0;
                        shell.prevX = shell.gx;
                        shell.prevY = shell.gy;
                        shell.reversals = 0;
                        shell.lastDir = 0;
                    }
                    onPositionChanged: mouse => {
                        if (!(pressedButtons & Qt.LeftButton)) {
                            const now = Date.now();
                            if (now - petStart > 1800) {
                                petStart = now;
                                petCount = 0;
                            }
                            const dir = Math.sign(mouse.x - petLastX);
                            if (dir && dir !== petDir && Math.abs(mouse.x - petLastX) > 2) {
                                petCount++;
                                petDir = dir;
                            }
                            petLastX = mouse.x;
                            if (petCount >= 5) {
                                petCount = 0;
                                petStart = now;
                                shell.pet();
                            }
                            return;
                        }
                        if (!moved && Math.hypot(mouse.x - px, mouse.y - py) < 4)
                            return;
                        moved = true;
                        shell.dragging = true;
                        // Al moverse Mochi, el ratón vuelve a quedar en (px, py) relativo a él
                        shell.gx += mouse.x - px;
                        shell.gy += mouse.y - py;
                    }
                    onReleased: mouse => {
                        if (mouse.button !== Qt.LeftButton)
                            return;
                        if (moved) {
                            // Soltarlo: sale lanzado con la velocidad del ratón y cae
                            shell.dragging = false;
                            shell.vx = Math.max(-4500, Math.min(4500, shell.hvx));
                            shell.vy = Math.max(-2600, Math.min(2600, shell.hvy));
                            shell.phys = "air";
                            shell.thrown = true;
                            if (shell.reversals >= 4)
                                shell.reacted("dizzy", 2400);
                            return;
                        }
                        if (wasPhys === "nest") {
                            shell.phys = "nest";
                            shell.leaveNest();
                        } else {
                            shell.phys = wasPhys === "swim" ? "swim" : "air";
                        }
                        if (shell.asking) {
                            mochi.poke();
                            shell.asking = false;
                        } else {
                            mochi.poke();
                            shell.openInput();
                        }
                    }
                }
            }

            // Micro silenciado
            Text {
                visible: !shell.earsOn && mochi.visible
                x: mochi.x + mochi.width - 18
                y: mochi.y + mochi.height - 20
                text: "mic_off"
                font.family: Theme.icons
                font.pixelSize: 16
                color: "white"
                style: Text.Outline
                styleColor: "black"
            }

            // Subtítulos: lo que escribes y lo que contesta flotan sobre Mochi, sin caja.
            // Texto con halo suave; claro u oscuro según el fondo (igual que el cuerpo).
            Item {
                id: bubble

                readonly property bool above: mochi.y - height - 14 > 8
                readonly property color ink: shell.lightBody ? "#fbfaf6" : "#141414"
                readonly property color halo: shell.lightBody ? "#000000" : "#ffffff"
                readonly property bool showing: win.here && mochi.visible && (shell.asking || shell.voiceWaiting || (shell.bubbleShown && (shell.remark !== "" || Brain.reply !== "" || Brain.busy)))
                readonly property string fullText: {
                    if (shell.asking)
                        return "";
                    if (shell.remark && !Brain.busy)
                        return shell.remark;
                    return Brain.reply;
                }
                // Lo que has dicho (por escrito o por voz), en pequeño encima de la respuesta
                readonly property string said: !shell.asking && !shell.remark && (Brain.busy || Brain.reply) ? Brain.lastPrompt : ""
                property int revealed: 0     // la respuesta aparece palabra a palabra

                visible: opacity > 0.01
                opacity: showing ? 1 : 0
                width: Math.max(shell.asking ? 320 : 0, Math.min(460, Math.max(reply.implicitWidth, saidText.implicitWidth) + 8))
                height: content.implicitHeight
                x: Math.max(12, Math.min(win.width - width - 12, mochi.x + mochi.width / 2 - width / 2))
                y: above ? mochi.y - height - 14 : mochi.y + mochi.height + 12

                onFullTextChanged: {
                    // Respuesta nueva (no la continuación de la anterior): empezar desde el principio
                    if (!fullText || revealed > fullText.length)
                        revealed = 0;
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: 260
                        easing.type: Easing.OutCubic
                    }
                }

                Timer {
                    running: bubble.revealed < bubble.fullText.length
                    repeat: true
                    interval: 38
                    onTriggered: {
                        const i = bubble.fullText.indexOf(" ", bubble.revealed + 1);
                        bubble.revealed = i < 0 ? bubble.fullText.length : i;
                    }
                }

                // Penumbra difuminada detrás del texto (sin bordes) para que se lea sobre cualquier fondo
                Rectangle {
                    id: scrim

                    anchors.fill: content
                    anchors.margins: -16
                    radius: 28
                    color: bubble.halo
                    visible: false
                    layer.enabled: true
                }

                MultiEffect {
                    anchors.fill: scrim
                    source: scrim
                    blurEnabled: true
                    blur: 1
                    blurMax: 48
                    opacity: 0.5
                }

                Column {
                    id: content

                    width: parent.width
                    spacing: 6

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: bubble.halo
                        shadowOpacity: 1
                        shadowBlur: 0.8
                        shadowVerticalOffset: 0
                        blurMax: 16
                    }

                    Text {
                        id: saidText

                        visible: text !== ""
                        width: parent.width
                        text: bubble.said ? `«${bubble.said}»` : ""
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 13
                        font.italic: true
                        color: bubble.ink
                        opacity: 0.6
                    }

                    Flickable {
                        visible: reply.text !== ""
                        width: parent.width
                        height: Math.min(reply.implicitHeight, 280)
                        contentHeight: reply.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        onContentHeightChanged: if (Brain.busy || bubble.revealed < bubble.fullText.length) contentY = Math.max(0, contentHeight - height)

                        Text {
                            id: reply

                            width: parent.width
                            text: bubble.fullText.slice(0, bubble.revealed)
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            textFormat: Text.MarkdownText
                            lineHeight: 1.08
                            font.family: Theme.font
                            font.pixelSize: 16
                            font.weight: Font.Medium
                            color: bubble.ink
                            linkColor: bubble.ink
                            onLinkActivated: link => Qt.openUrlExternally(link)
                        }
                    }

                    // Lo que escribes, suelto y centrado
                    Item {
                        visible: shell.asking
                        width: parent.width
                        height: input.implicitHeight

                        TextInput {
                            id: input

                            anchors.fill: parent
                            horizontalAlignment: TextInput.AlignHCenter
                            color: bubble.ink
                            font.family: Theme.font
                            font.pixelSize: 18
                            font.weight: Font.Medium
                            selectionColor: bubble.ink
                            selectedTextColor: bubble.halo
                            selectByMouse: true
                            clip: true

                            cursorDelegate: Rectangle {
                                width: 2
                                color: bubble.ink
                                visible: input.text !== ""   // vacío: solo el cursor de abajo, centrado

                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite
                                    running: input.activeFocus

                                    NumberAnimation {
                                        to: 0
                                        duration: 450
                                        easing.type: Easing.InOutSine
                                    }
                                    NumberAnimation {
                                        to: 1
                                        duration: 450
                                        easing.type: Easing.InOutSine
                                    }
                                }
                            }

                            onVisibleChanged: {
                                if (visible) {
                                    text = "";
                                    forceActiveFocus();
                                }
                            }
                            Keys.onEscapePressed: shell.asking = false
                            onAccepted: {
                                if (!text.trim())
                                    return;
                                Brain.send(text);
                                shell.asking = false;
                            }
                        }

                        Row {
                            anchors.centerIn: parent
                            visible: !input.text
                            spacing: 3

                            Rectangle {
                                width: 2
                                height: input.implicitHeight
                                color: bubble.ink

                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite
                                    running: shell.asking

                                    NumberAnimation {
                                        to: 0
                                        duration: 450
                                        easing.type: Easing.InOutSine
                                    }
                                    NumberAnimation {
                                        to: 1
                                        duration: 450
                                        easing.type: Easing.InOutSine
                                    }
                                }
                            }

                        }
                    }
                }

                // Clic en la respuesta: cerrarla · encima: no se va mientras la lees
                MouseArea {
                    anchors.fill: parent
                    enabled: !shell.asking
                    hoverEnabled: true
                    onClicked: shell.bubbleShown = false
                    onContainsMouseChanged: {
                        if (containsMouse)
                            hideTimer.stop();
                        else if (!Brain.busy && shell.bubbleShown)
                            hideTimer.restart();
                    }
                }
            }
        }
    }
}
