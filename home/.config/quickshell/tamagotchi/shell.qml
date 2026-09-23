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
    property real swimPhase: 0
    property real ceilingTime: 0
    property real hideX: 0
    property real hideY: 0
    property bool cursorNear: false
    property bool lightBody: false      // fondo oscuro → subtítulos claros
    property color frameColor: Theme.surface   // color real del marco a su lado (lo mide bg.py)

    Behavior on frameColor {
        ColorAnimation {
            duration: 400
        }
    }
    readonly property real bodyRx: 32 * 1.45          // semiejes del cuerpo (como en Blob)
    readonly property real bodyRy: 29 * 1.45 * 0.95
    readonly property real embed: 12                  // cuánto va hundido en el marco al nadar
    readonly property int hideAfter: 180000    // ms sin usarlo hasta que se esconde

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

    // Un sitio del marco lejos del ratón, mejor en las paredes o en las esquinas de abajo (el
    // centro de abajo suele tener cosas: reproductores, barras…) y no en el techo
    function spotD(s: var, tr: var): real {
        const onScreen = cursorX >= s.x && cursorX < s.x + s.width && cursorY >= s.y && cursorY < s.y + s.height;
        let best = 0, bestScore = -Infinity;
        for (let i = 0; i < 24; i++) {
            const d = tr.len * i / 24, p = pointAt(tr, d);
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

    // Llega al workspace en el que estás: sale nadando de la barra (o del borde derecho) por el
    // lado del que viene y va a un sitio tranquilo
    function arrive(): void {
        const ws = Hyprland.focusedWorkspace;
        if (!ws)
            return;
        const s = screenOfMonitor(Hyprland.focusedMonitor), tr = track(s);
        const fromLeft = mochiWs >= 0 && mochiWs < ws.id;
        mochiWs = ws.id;
        hopsLeft = 0;
        entering = false;
        const y = tr.T + (tr.B - tr.T) * 0.7;
        swimD = nearestD(tr, fromLeft ? tr.L : tr.R, y);
        swimV = 0;
        swimTarget = spotD(s, tr);
        gx = fromLeft ? tr.L - 80 : tr.R + 80;   // empieza dentro del marco
        gy = y;
        phys = "swim";
        reacted("excited", 1300);
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
        if (mochiWs < 0 || phys === "held") {   // si lo llevas agarrado, viene contigo
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
        idleHide.restart();
        if (!present) {
            summon();
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
        vx = hopDir * (big ? 260 : 120 + Math.random() * 120);
        vy = big ? -950 : -(430 + Math.random() * 180);
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
        bgProc.command = [Quickshell.shellDir + "/bg.py", gx, gy, bodyRx, bodyRy, s.x, s.y, s.width, s.height, barW, frame].map(String);
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
        // Se queda en el workspace de la pantalla donde ha caído
        const id = Hyprland.monitorFor(nearestScreen(gx, gy))?.activeWorkspace?.id;
        if (id !== undefined && id > 0)
            mochiWs = id;
        if (hopsLeft > 0)
            hopAgain.restart();
    }

    function physStep(dt: real): void {
        dt = Math.min(dt, 1 / 30);
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

        if (phys === "hidden") {
            const k = Math.min(1, dt * 2.5);
            gx += (hideX - gx) * k;
            gy += (hideY - gy) * k;
            return;
        }

        if (phys === "swim") {
            const here = pointAt(tr, swimD);
            let want = 0;
            if (!isNaN(swimTarget)) {
                // Nada hacia el sitio elegido, a brazadas
                const diff = trackDiff(tr, swimD, swimTarget);
                if (Math.abs(diff) < 6) {
                    swimTarget = NaN;
                    savePos();
                    checkBg();
                } else {
                    swimPhase += dt * 7;
                    want = Math.sign(diff) * Math.min(280, Math.abs(diff) * 2 + 40) * (0.55 + 0.45 * Math.max(0, Math.sin(swimPhase)));
                }
            } else if (Math.abs(here.nx) > 0.9) {
                // En una pared: la gravedad lo va bajando despacio
                want = here.nx > 0 ? -22 : 22;
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
            swimV += (want - swimV) * Math.min(1, dt * 4);
            swimD = ((swimD + swimV * dt) % tr.len + tr.len) % tr.len;
            // Sigue el recorrido con suavidad (al salir del marco, al pegarse…)
            const p = pointAt(tr, swimD), k = Math.min(1, dt * 10);
            gx += (p.x - gx) * k;
            gy += (p.y - gy) * k;
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
            if (shell.present && !Brain.busy && !shell.asking && !shell.dragging && shell.phys !== "hidden")
                shell.reacted(face, ms);
        }
        function onDance(ms: int): void {
            if (shell.present && !Brain.busy && !shell.asking && !shell.dragging && shell.phys !== "hidden")
                shell.reacted("dance", ms);
        }
        function onGlance(x: real, y: real): void {
            shell.glanceX = x;
            shell.glanceY = y;
            shell.glanceUntil = Date.now() + 1400;
        }
        function onSay(text: string, face: string): void {
            if (!shell.shown || Brain.busy || shell.asking || shell.voiceWaiting || shell.dragging || (shell.bubbleShown && !shell.remark))
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
        onTriggered: if (shell.earsOn) ears.running = true
    }

    Process {
        id: ears

        command: [Quickshell.shellDir + "/ears.sh"]
        running: shell.earsOn

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
            if (shell.earsOn)
                earsRestart.restart();
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
        // Dar un saltito (para probar el movimiento)
        function jump(): void {
            shell.hopsLeft = 1;
            shell.hop();
        }
        function state(): string {
            return `${shell.phys} ${Math.round(shell.gx)},${Math.round(shell.gy)} v=${Math.round(shell.vx)},${Math.round(shell.vy)} ws=${shell.mochiWs} present=${shell.present} shown=${shell.shown}`;
        }
        function ask(text: string): void {
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
                    const glancing = Date.now() < shell.glanceUntil;
                    const dx = (glancing ? shell.glanceX : p.x) - shell.gx, dy = (glancing ? shell.glanceY : p.y) - shell.gy;
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
        running: shell.shown && shell.present && !shell.fsHide && shell.phys === "swim" && isNaN(shell.swimTarget) && !shell.asking && !shell.bubbleShown && !shell.voiceWaiting && !Brain.busy
        repeat: true
        interval: 9000
        onTriggered: {
            interval = 7000 + Math.random() * 11000;
            const s = shell.nearestScreen(shell.gx, shell.gy), tr = shell.track(s), p = shell.pointAt(tr, shell.swimD);
            const r = Math.random();
            if (r < 0.45) {
                // A otro sitio (no muy lejos, y que no sea junto al ratón)
                for (let i = 0; i < 6; i++) {
                    const d = shell.swimD + (Math.random() * 2 - 1) * 700, q = shell.pointAt(tr, d);
                    if (Math.hypot(q.x - shell.cursorX, q.y - shell.cursorY) > 300 && q.ny > -0.9) {
                        shell.swimTarget = ((d % tr.len) + tr.len) % tr.len;
                        break;
                    }
                }
            } else if (r < 0.65 && p.ny > 0.9) {
                shell.hopsLeft = 1 + Math.floor(Math.random() * 3);
                shell.hopDir = Math.random() < 0.5 ? -1 : 1;
                shell.hop();
            } else if (r < 0.75 && Math.abs(p.nx) > 0.9) {
                shell.pushOff();
            }
        }
    }

    Timer {
        id: hopAgain

        interval: 160
        onTriggered: shell.hop()
    }

    // Si no le haces caso, se hunde en el marco (solo asoman los ojos)
    Timer {
        id: idleHide

        running: shell.shown && shell.present && shell.phys !== "hidden" && !shell.asking && !shell.bubbleShown && !shell.voiceWaiting && !Brain.busy
        interval: shell.hideAfter
        onTriggered: {
            if (shell.phys !== "swim") {
                restart();
                return;
            }
            shell.hideAway();
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            required property ShellScreen modelData

            readonly property bool here: shell.screenAt(shell.gx, shell.gy) === modelData

            screen: modelData
            visible: shell.shown
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "mochi"
            WlrLayershell.keyboardFocus: shell.asking && here ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            // Solo Mochi y su bocadillo reciben clics; el resto del escritorio pasa de largo
            mask: Region {
                item: mochi.visible ? mochi : null

                Region {
                    item: bubble.visible ? bubble : null
                }
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
                        id: body

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
                        property vector4d frame: Qt.vector4d(shell.barW - x, shell.frame - y, win.width - shell.frame - x, win.height - shell.frame - y)
                        property color color: shell.frameColor   // sólido, del color que se ve el marco
                        property real blobK: 26
                        property real frameK: shell.frameSmoothing

                        fragmentShader: Qt.resolvedUrl("mochi.frag.qsb")
                    }
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
                sleepy: shell.phys === "hidden" && !shell.cursorNear
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
                }
                lookX: shell.dragging ? 0 : shell.lookX
                lookY: shell.dragging ? 0 : shell.lookY

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
                    onContainsMouseChanged: if (containsMouse && shell.phys === "hidden") shell.touch()

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
                        shell.touch();
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
                        shell.phys = wasPhys === "swim" ? "swim" : "air";
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
