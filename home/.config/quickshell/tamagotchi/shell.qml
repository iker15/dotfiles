import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Caelestia.Config
import "Hats.js" as Hats
import "Draw.js" as Draw

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

    // Decisión (2026-09-24): Mochi es una mascota integrada en el sistema, NO un chat. No se le
    // escribe (clic = solo reacciona) y la voz está apagada. Se deja todo preparado para más
    // adelante (controlarlo por voz y que ejecute cosas): encender voiceEnabled (y Brain.enabled).
    readonly property bool chatEnabled: false
    readonly property bool voiceEnabled: false

    // Voz: ears.py escucha el micro y avisa al oír "Mochi"
    property bool earsOn: voiceEnabled
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

    // ── El mundo de fuera ──
    // Normal del marco donde nada (hacia el marco; 0,0 fuera del marco): el cuerpo se queda
    // pegado a él aunque se aplaste o se derrita
    property real nX: 0
    property real nY: 0

    // Calor del portátil (CPU, y la GPU solo si ya está despierta): se va derritiendo. La media
    // es lenta (~20 s) para que un pico corto no lo derrita. También si fuera hace mucho calor.
    property real cpuTemp: 0
    property real gpuTemp: 0
    property real heatT: 50
    property real heatTest: NaN      // (IPC `pet heat <grados>`, 0 = quitar)
    readonly property real heatNow: isNaN(heatTest) ? Math.max(cpuTemp, gpuTemp) : heatTest
    property real melt: Math.max(meltExtra, Math.max(0, Math.min(1, (heatT - 72) / 20)), (isNaN(weatherTemp) ? 0 : 0.5 * Math.max(0, Math.min(1, (weatherTemp - 30) / 10))))
    Behavior on melt {
        NumberAnimation {
            duration: 2500
            easing.type: Easing.InOutSine
        }
    }

    // El tiempo de verdad (Caelestia → MochiBridge; código WMO de open-meteo)
    property int weatherCode: -1
    property real weatherTemp: NaN
    readonly property bool raining: (weatherCode >= 51 && weatherCode <= 67) || (weatherCode >= 80 && weatherCode <= 82) || weatherCode >= 95
    readonly property bool snowing: (weatherCode >= 71 && weatherCode <= 77) || weatherCode === 85 || weatherCode === 86
    readonly property bool storm: weatherCode >= 95
    readonly property bool cold: weatherTemp < 6
    property var weatherTest: null   // (IPC `pet weather <código> <grados>`; código −2 = quitar)
    function setWeather(w: var): void {
        const v = weatherTest ?? w;
        weatherCode = v?.code ?? -1;
        weatherTemp = v?.tempC ?? NaN;
    }
    property var lastWeather: null

    // Lloviendo saca un paraguas (con el bracito); con el café en la mano, no
    readonly property bool umbrellaOn: raining && present && !fsHide && !locked && (phys === "swim" || phys === "air" || phys === "held") && nY > -0.5 && cupAmt < 0.01
    property real umbAmt: umbrellaOn ? 1 : 0
    Behavior on umbAmt {
        NumberAnimation {
            duration: 550
            easing.type: Easing.OutBack
        }
    }
    // (en una pared lo sujeta del lado de fuera; en el suelo, hacia el centro de la pantalla)
    readonly property real umbSide: Math.abs(nX) > 0.5 ? -Math.sign(nX) : (gx < (nearestScreen(gx, gy)?.x ?? 0) + (nearestScreen(gx, gy)?.width ?? 0) / 2 ? 1 : -1)
    readonly property var umbGeom: {
        const hx = gx + umbSide * (bodyRx + 22), hy = gy - bodyRy * 0.62;
        const k = 0.3 + 0.7 * Math.max(0, umbAmt);
        const tx = gx + umbSide * 2, ty = gy - bodyRy - 42 * k;   // centro de la tela
        return {
            hx: gx + (hx - gx) * k,
            hy: gy + (hy - gy) * k,
            tx: tx,
            ty: ty,
            ang: Math.atan2(tx - hx, hy - ty)   // inclinación del mango (rad)
        };
    }
    // Punta del bracito: la taza, o el paraguas
    readonly property var armTip: cupAmt > 0.01 ? Qt.vector3d(cupGeom.hx, cupGeom.hy, cupAmt) : Qt.vector3d(umbGeom.hx, umbGeom.hy, umbAmt)
    property real rainT: 0
    readonly property bool snowFx: snowing && present && !fsHide && !locked && (phys === "swim" || phys === "air" || phys === "held") && nY > -0.5
    NumberAnimation on rainT {
        running: shell.umbAmt > 0 || shell.snowFx
        from: 0
        to: 1000
        duration: 1000000
        loops: Animation.Infinite
    }

    // Nevando se le acumula la nieve en la cabeza; de vez en cuando se sacude
    property real snowAmt: 0

    // Ventanas flotantes que se le ponen encima: se chafa y se escurre por un lado
    property real press: 0
    property real underSince: 0
    property bool squeezing: false
    property var winTest: null       // (IPC `pet window x y w h ms`)
    function checkWindow(r: var): void {
        let p = 0;
        if (r && present && phys === "swim" && !dnd && !locked) {
            const x1 = r[0], y1 = r[1], x2 = x1 + r[2], y2 = y1 + r[3];
            const L = gx - bodyRx, R = gx + bodyRx, T = gy - bodyRy, B = gy + bodyRy;
            if (Math.min(R, x2) - Math.max(L, x1) > 6 && Math.min(B, y2) - Math.max(T, y1) > 6) {
                // cuánto ha entrado, en la dirección de la normal (desde dentro de la pantalla)
                const pen = Math.abs(nY) >= Math.abs(nX) ? (nY >= 0 ? y2 - T : B - y1) : (nX > 0 ? x2 - L : R - x1);
                const vis = 2 * normalRadius({
                    nx: nX,
                    ny: nY
                }) - embed;
                p = Math.max(0, Math.min(1, pen / vis));
            }
        }
        press = p;
        if (p > 0) {
            const now = Date.now();
            if (!underSince) {
                underSince = now;
                reacted("squint", 900);
            }
            if (!squeezing && (p > 0.45 || now - underSince > 1400))
                squeezeOut(r);
        } else {
            underSince = 0;
        }
    }
    function squeezeOut(r: var): void {
        const s = nearestScreen(gx, gy), tr = track(s), m = bodyRx + 24;
        const x1 = r[0] - m, y1 = r[1] - m, x2 = r[0] + r[2] + m, y2 = r[1] + r[3] + m;
        let best = NaN, bestD = Infinity;
        for (let i = 0; i < 96; i++) {
            const d = tr.len * i / 96, p = pointAt(tr, d);
            if (p.ny < -0.9 || inPanel(p.x, p.y, bodyRx + 40) || (p.x > x1 && p.x < x2 && p.y > y1 && p.y < y2))
                continue;
            const dist = Math.abs(trackDiff(tr, swimD, d));
            if (dist < bestD) {
                bestD = dist;
                best = d;
            }
        }
        squeezing = true;
        squeezeDone.restart();
        reacted("surprised", 600);
        kicked(-1.8, 2.4);   // ¡plop! sale disparado como pasta de dientes
        if (isNaN(best)) {
            goNest();
            return;
        }
        if (bestD > 450) {
            dive(trackDiff(tr, swimD, best), "hidden", false, 2.2);
        } else {
            energy = 2.6;
            swimTarget = best;
        }
        // …y luego mira mal a la ventana
        glanceX = r[0] + r[2] / 2;
        glanceY = r[1] + r[3] / 2;
        afterSqueeze.restart();
    }

    // Gorro de temporada (Hats.js) o el que le pongas por IPC (`pet hat witch|santa|party|crown|none|auto`)
    property var today: new Date()
    property string hatChoice: "auto"
    readonly property string hat: hatChoice === "auto" ? Hats.seasonal(today) : hatChoice === "none" ? "" : hatChoice

    // Se duerme antes de que se apague/bloquee la pantalla por inactividad (el primer aviso de
    // Caelestia: general.idle.timeouts en shell.json; por defecto, bloquear a los 180 s)
    property int idleFirst: 180
    FileView {
        path: `${Quickshell.env("HOME")}/.config/caelestia/shell.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const t = (JSON.parse(text()).general?.idle?.timeouts ?? []).filter(x => x.enabled ?? true).map(x => x.timeout);
                shell.idleFirst = t.length ? Math.min(...t) : 180;
            } catch (e) {
                shell.idleFirst = 180;
            }
        }
    }
    // (con música no se duerme: Caelestia tampoco apaga la pantalla)
    IdleMonitor {
        enabled: !Mind.player && !shell.locked
        respectInhibitors: true
        timeout: Math.max(30, shell.idleFirst - 60)
        onIsIdleChanged: {
            if (isIdle) {
                shell.idleDrowsy = true;
                shell.sleepTest("yawn");
            } else {
                shell.idleDrowsy = false;
                shell.woke();
            }
        }
    }
    IdleMonitor {
        enabled: !Mind.player && !shell.locked
        respectInhibitors: true
        timeout: Math.max(40, shell.idleFirst - 25)
        onIsIdleChanged: if (isIdle) shell.sleepTest("doze")
    }
    property bool idleDrowsy: false

    // ── Cariño (Bond.qml) ──
    // Con mucho cariño te busca (se pone cerca del ratón, sin taparlo); enfurruñado te gira
    // la cara y se va antes al nido. Te saluda al volver (arranque o desbloqueo tras un rato).
    readonly property real seekYou: Bond.sulky ? 0 : Math.max(0, Math.min(1, (Bond.level - 0.6) / 0.4))
    readonly property real nestFactor: Bond.sulky ? 0.4 : Bond.level < 0.3 ? 0.6 : Bond.level > 0.7 ? 1.5 : 1
    property real lockedAt: 0
    // Clic: sale un corazoncito blanco que sube y se desvanece
    signal heartPop()

    // Dejando el ratón encima un momento se ve un corazoncito con su cariño (lleno = 100)
    property bool heartShown: false
    Connections {
        target: Bond

        function onPouted(): void {
            shell.reacted("sad", 1800);
            shell.glanceX = shell.gx + (shell.gx < shell.cursorX ? -600 : 600);   // mira hacia el otro lado
            shell.glanceY = shell.gy - 40;
            shell.glanceUntil = Date.now() + 1800;
            shell.leaned(shell.gx < shell.cursorX ? -120 : 120);
        }
        function onReconciled(): void {
            shell.reacted("love", 2600);
            shell.kicked(-1.4, 2.6);
        }
        function onLoadedChanged(): void {
            if (Bond.loaded && Bond.awayHours > 0.5)
                greetTimer.restart();
        }
    }
    function greet(): void {
        if (locked || dnd || !shown)
            return;
        if (Bond.sulky) {
            // no sale: se queda en su sitio mirando mal
            reacted("sad", 2000);
            return;
        }
        if (Bond.level > 0.45) {
            touch();
            reacted("love", 2400);
            kicked(-1.6, 2.8);
        } else {
            reacted("happy", 1200);
        }
    }
    Timer {
        id: greetTimer

        interval: 3500
        onTriggered: shell.greet()
    }
    // Estar en el PC con él a la vista (sin estar ausente) también cuenta, un poco
    IdleMonitor {
        id: awayMonitor

        timeout: 300
        respectInhibitors: false
    }
    Timer {
        running: Bond.loaded && !shell.locked
        repeat: true
        interval: 600000
        onTriggered: if (!awayMonitor.isIdle && shell.present && !shell.dnd) Bond.gain("presence")
    }

    // ── Para las integraciones (fastfetch, dashboard, Zen, VSCodium) ──
    // Cómo está, en resumen: una cara y una frase. Se publica en $XDG_RUNTIME_DIR/mochi-state.json
    // y su retrato en ~/.cache/mochi/avatar.png (solo cuando cambia).
    readonly property string feeling: dnd || dozing ? "asleep" : Bond.sulky ? "sulky" : melt > 0.4 ? "hot" : (drowsy > 0.6 || idleDrowsy) && !caffeine ? "sleepy" : watching ? "curious" : caffeine ? "excited" : Mind.musicPlaying ? "happy" : Bond.level > 0.75 ? "love" : "normal"
    readonly property string feelingText: {
        const parts = [];
        parts.push({
            asleep: "durmiendo",
            sulky: "enfurruñado contigo",
            hot: "derritiéndose de calor",
            sleepy: "con sueño",
            curious: watchingGame ? "viéndote jugar" : "viendo un vídeo contigo",
            excited: "a tope de café",
            happy: "bailando",
            love: "muy contento contigo",
            normal: "tranquilo"
        }[feeling]);
        if (raining)
            parts.push("con paraguas");
        else if (snowing)
            parts.push("cogiendo nieve");
        else if (cold)
            parts.push("tiritando");
        return parts.join(", ");
    }
    function hex(c: color): string {
        const h = v => Math.round(v * 255).toString(16).padStart(2, "0");
        return "#" + h(c.r) + h(c.g) + h(c.b);
    }
    readonly property string avatarBody: hex(frameColor)
    readonly property string avatarInk: 0.299 * frameColor.r + 0.587 * frameColor.g + 0.114 * frameColor.b > 0.55 ? "#1c1b1b" : "#f4f1f0"
    readonly property string stateJson: JSON.stringify({
        feeling: feeling,
        text: feelingText,
        bond: Math.round(Bond.bond),
        sulky: Bond.sulky,
        hat: hat,
        body: avatarBody,
        ink: avatarInk,
        melt: Math.round(melt * 100) / 100,
        snow: Math.round(snowAmt * 10) / 10,
        raining: raining,
        caffeine: caffeine,
        watching: watching,
        music: Mind.musicPlaying,
        dnd: dnd,
        cpu: Math.round(heatT),
        outside: isNaN(weatherTemp) ? null : Math.round(weatherTemp),
        energy: Math.round(dayEnergy * 100) / 100,
        drowsy: Math.round(drowsy * 100) / 100,
        where: inApp ? "app" : phys,
        nextHat: nextHat,
        xp: Math.round(Bond.xp),
        level: Bond.lvl,
        levelStart: Bond.lvlStart,
        levelEnd: Bond.lvlEnd,
        stage: Bond.stage,
        stageName: Bond.stageNames[Bond.stage]
    })
    // El próximo gorro (para el dashboard): cuál y cuándo
    readonly property string nextHat: {
        const d = new Date(today);
        for (let i = 1; i < 400; i++) {
            d.setDate(d.getDate() + 1);
            const h = Hats.seasonal(d);
            if (h && h !== hat)
                return `${h}|${d.toISOString().slice(0, 10)}`;
        }
        return "";
    }
    onStateJsonChanged: stateSave.restart()
    Timer {
        id: stateSave

        interval: 400
        onTriggered: stateFile.setText(shell.stateJson)
    }
    FileView {
        id: stateFile

        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/mochi-state.json`
        atomicWrites: true
        printErrors: false
    }
    // El retrato: se repinta si cambia la cara, el gorro o el color (con calma: el color del
    // marco va variando)
    readonly property string avatarKey: [feeling, hat, avatarBody, avatarInk, Math.round(melt * 4), Math.round(snowAmt * 3), Bond.stage].join("|")
    onAvatarKeyChanged: avatarRedraw.restart()
    Timer {
        id: avatarRedraw

        interval: 2500
        onTriggered: shell.avatarPaint()
    }
    signal avatarPaint()
    Component.onDestruction: {}

    // ── Minecraft (integrations/minecraft/mc-watch.py sigue el log mientras juegas) ──
    // Qué hace con cada cosa (muertes según cómo, logros, chat, jugadores…) lo dicen las reglas
    // de integrations/minecraft/reacciones.jsonc. Si el juego está a pantalla completa (Mochi
    // escondido), asoma un momento por la esquina de abajo con esa cara. Y mientras juegas en
    // ventana, se pone debajo a verte jugar (como con los vídeos).
    property string peekFace: ""
    property real peekAmt: 0
    Behavior on peekAmt {
        NumberAnimation {
            duration: 380
            easing.type: Easing.OutBack
        }
    }
    // Una reacción (de integrations/minecraft/reacciones.jsonc): cara, cosas que hace y, si la
    // regla lo pide, una frase
    function gameEvent(ev: var, forcePeek: bool): void {
        if (locked || dnd)
            return;
        if (ev.ev === "error") {
            console.warn("mochi minecraft:", ev.text);
            return;
        }
        const face = ev.cara || "", ms = ev.ms || 2000, todo = ev.hacer ?? [];
        if (fsHide || !present || forcePeek) {
            if (!face)
                return;
            peekFace = face;
            peekAmt = 1;
            peekHide.interval = ms + 400;
            peekHide.restart();
            return;
        }
        // un susto primero (y luego la cara)
        if (todo.includes("susto")) {
            reacted("surprised", 450);
            kicked(1.8, -2.2);
            if (face) {
                laterFace.face = face;
                laterFace.ms = ms;
                laterFace.restart();
            }
        } else if (face) {
            reacted(face, ms);
        }
        for (const a of todo) {
            if (a === "salto" || a === "saltos") {
                if (phys === "swim") {
                    hopsLeft = a === "saltos" ? 3 : 1;
                    hop();
                } else {
                    kicked(-1.4, 2.4);
                }
            } else if (a === "aplastar") {
                kicked(2.4, -2.8);
                splatted(900, false);
            } else if (a === "estirar") {
                kicked(-1.8, 2.8);
            } else if (a === "arcoiris") {
                rainbow(Math.max(ms, 3000));
            } else if (a === "baile") {
                reacted("dance", Math.max(ms, 3000));
            } else if (a === "derretir") {
                meltExtra = 0.75;
                meltExtraEnd.interval = Math.max(ms, 4000);
                meltExtraEnd.restart();
            } else if (a === "tiritar") {
                jitter.restart();
            } else if (a === "corazon" || a === "estrella") {
                if (phys === "swim")
                    shapeShift(a === "corazon" ? "heart" : "star", Math.max(ms, 2000));
            } else if (a === "mirar") {
                const o = Hyprland.activeToplevel?.lastIpcObject;
                if (o?.at) {
                    glanceX = o.at[0] + o.size[0] / 2;
                    glanceY = o.at[1] + o.size[1] / 2;
                    glanceUntil = Date.now() + 1600;
                }
            }
        }
        if (ev.decir)
            Mind.say(ev.decir, face || "happy");
    }
    // Derretirse un rato (morir en lava, entrar al Nether…), aparte del calor de verdad
    property real meltExtra: 0
    Timer {
        id: meltExtraEnd

        onTriggered: shell.meltExtra = 0
    }
    Timer {
        id: laterFace

        property string face
        property int ms

        interval: 450
        onTriggered: shell.reacted(face, ms)
    }
    Timer {
        id: mcRestart

        interval: 5000
        onTriggered: mcWatch.running = true
    }
    Timer {
        id: peekHide

        onTriggered: shell.peekAmt = 0
    }
    Process {
        id: mcWatch

        running: shell.shown
        // (si se muere por lo que sea, vuelve a arrancar)
        onExited: if (shell.shown) mcRestart.restart()
        command: ["python3", Quickshell.shellDir + "/integrations/minecraft/mc-watch.py"]
        stdout: SplitParser {
            onRead: data => {
                try {
                    shell.gameEvent(JSON.parse(data), false);
                } catch (e) {}
            }
        }
    }

    // ── Dentro del editor (Code - OSS / VSCodium) ──
    // Cuando el editor es la ventana activa en su workspace, bucea por el marco hasta la esquina
    // de abajo a la izquierda del editor y "se mete": se queda sumergido ahí y aparece en su panel
    // de la extensión (integrations/vscodium). Al salir del editor, vuelve a salir por esa esquina.
    // Mientras programas gana experiencia (la manda la extensión: `pet codeXp <n>`).
    readonly property bool codeActive: /^(code-oss|codium|vscodium|code|code-url-handler)$/i.test(Hyprland.activeToplevel?.wayland?.appId ?? "") && Hyprland.activeToplevel?.workspace?.id === mochiWs
    property bool inApp: false
    property var appSpot: null        // punto del marco por el que se ha metido
    property bool appOptOut: false    // lo has sacado tú (le has hablado…): no vuelve a entrar hasta que salgas del editor
    // Ventana en la que está metido (el editor, o la kitty cuyo cuadrado ha rellenado): sale en
    // cuanto dejas de usarla
    property string appHost: ""
    readonly property string activeAddr: Hyprland.activeToplevel?.address ?? ""
    onActiveAddrChanged: {
        if (inApp && activeAddr !== appHost)
            appLeave.restart();
        else
            appLeave.stop();
    }
    onCodeActiveChanged: if (!codeActive) appOptOut = false
    // (lo va intentando: si acaba de llegar buceando, o estaba haciendo otra cosa, entra luego)
    Timer {
        running: shell.codeActive && !shell.inApp && !shell.appOptOut
        repeat: true
        interval: 1200
        onTriggered: {
            Hyprland.refreshToplevels();
            shell.enterApp();
        }
    }
    Timer {
        id: appLeave

        interval: 700
        onTriggered: shell.leaveApp(false)
    }
    function enterApp(): void {
        if (inApp || !codeActive || locked || dnd || !present || asking || Brain.busy || (phys !== "swim" && phys !== "nest"))
            return;
        const o = Hyprland.activeToplevel?.lastIpcObject;
        if (!o?.at || o.fullscreen)
            return;
        const s = nearestScreen(o.at[0] + 10, o.at[1] + o.size[1] - 10), tr = track(s);
        if (phys === "nest") {
            phys = "swim";
            bodyOffX = 0;
            swimD = nearestD(tr, tr.L, gy);
        }
        const target = nearestD(tr, o.at[0] + 40, o.at[1] + o.size[1]);
        appSpot = pointAt(tr, target);
        appHost = Hyprland.activeToplevel?.address ?? "";
        inApp = true;
        reacted("curious", 900);
        dive(trackDiff(tr, swimD, target), "hidden", false, 1.8);
        diveToNest = false;
        diveStay = true;   // se queda dentro
    }
    function leaveApp(force: bool): void {
        if (!inApp || (!force && activeAddr === appHost && appHost !== ""))
            return;
        inApp = false;
        diveStay = false;
        if (!present || locked)
            return;   // (si te has ido a otro workspace, ya vendrá detrás de ti)
        const s = nearestScreen(appSpot?.x ?? gx, appSpot?.y ?? gy), tr = track(s);
        swimD = nearestD(tr, appSpot?.x ?? gx, appSpot?.y ?? gy);
        const p = pointAt(tr, swimD), rn = normalRadius(p), deep = 2 * rn - embed - diveVisible("hidden", rn);
        gx = p.x + p.nx * deep;
        gy = p.y + p.ny * deep;
        dive(0, "hidden", true, 1.8);
        reacted("happy", 1200);
    }
    // Abres kitty: su fluido rellena el cuadrado del saludo (fastfetch). Mira la ventana nueva,
    // bucea a su ritmo por el marco hasta el borde de arriba, justo encima del cuadrado, y desde
    // ahí cae; se queda dentro mientras uses esa kitty. Lo llama ~/.config/fastfetch/mochi.sh con
    // dónde está el centro del cuadrado (px desde la esquina de la ventana).
    property real termOffX: 0
    property real termTop: 0
    property real termOffY: 0
    property int termTries: 0
    function enterTerm(offX: real, offY: real, top: real): void {
        if (locked || dnd || asking || dragging || !shown)
            return;
        termOffX = offX;
        termOffY = offY;
        termTop = top > 0 ? top : offY - 100;
        termTries = 0;
        termWin.running = true;
    }
    // La ventana activa, preguntada a Hyprland en el momento (lastIpcObject puede ir atrasado:
    // p. ej. con la posición de antes de reorganizarse las ventanas)
    Process {
        id: termWin

        command: ["hyprctl", "-j", "activewindow"]
        stdout: StdioCollector {
            onStreamFinished: {
                let o = null;
                try {
                    o = JSON.parse(text);
                } catch (e) {}
                if (!shell.doEnterTerm(o) && ++shell.termTries < 6)
                    termTimer.restart();
            }
        }
    }
    Timer {
        id: termTimer

        interval: 150
        onTriggered: termWin.running = true
    }
    function doEnterTerm(o: var): bool {
        if (!o?.at || !/kitty/i.test(o.class ?? "") || o.fullscreen)
            return false;
        const tl = Hyprland.toplevels.values.find(w => "0x" + w.address === o.address || w.address === o.address) ?? Hyprland.activeToplevel;
        // (por el borde de ARRIBA, justo encima del cuadrado: el fluido cae desde ahí)
        const s = nearestScreen(o.at[0] + termOffX, o.at[1] + termOffY), tr = track(s);
        const target = nearestD(tr, o.at[0] + termOffX, tr.T);
        // por dónde cae su fluido: del borde de arriba del marco al cuadrado (en la pantalla)
        pourX = o.at[0] + termOffX;
        pourTop = s.y + frame;
        pourBottom = o.at[1] + termTop;
        appLeave.stop();
        appHost = tl?.address ?? "";
        appSpot = pointAt(tr, target);
        const wasIn = inApp;
        inApp = true;
        diveToNest = false;
        if (!present || phys === "hidden") {
            // no estaba a la vista: aparece ya dentro
            mochiWs = o.workspace?.id ?? Hyprland.focusedWorkspace?.id ?? mochiWs;
            swimD = target;
            const p = appSpot, rn = normalRadius(p), deep = 2 * rn - embed - diveVisible("hidden", rn);
            gx = p.x + p.nx * deep;
            gy = p.y + p.ny * deep;
            dive(0, "hidden", true, 3);
            diveStay = true;
            schedulePour(300);
            return true;
        }
        if (phys === "nest") {
            phys = "swim";
            bodyOffX = 0;
            swimD = nearestD(tr, tr.L, gy);
        }
        if (phys !== "swim" && phys !== "dive")
            return false;
        if (wasIn || phys === "dive") {
            // ya estaba sumergido (en otra ventana): va por dentro, sin asomarse
            const dist = trackDiff(tr, swimD, target);
            dive(dist, "hidden", true, 1.2 * dayEnergy);
            diveStay = true;
            schedulePour(diveDur * 1000);
            return true;
        }
        // Se da cuenta de la ventana nueva: la mira con curiosidad un momento…
        reacted("curious", 1100);
        glanceX = o.at[0] + o.size[0] / 2;
        glanceY = o.at[1] + o.size[1] / 3;
        glanceUntil = Date.now() + 900;
        kicked(-0.8, 1.2);
        termTarget = target;
        termGo.restart();
        // (llegará cuando acabe de mirar y bucee hasta allí: se calcula ya para el cuadrado)
        const dist = trackDiff(tr, swimD, target), sp = termSpeed();
        schedulePour(termGo.interval + (1 + Math.abs(dist) / (Math.abs(dist) > 1200 ? 620 : 380)) / sp * 1000);
        return true;
    }
    // …y va buceando a su ritmo, asomando la cabeza, y al llegar se hunde del todo
    property real termTarget: 0
    function termSpeed(): real {
        return Math.max(0.8, Math.min(1.4, 1.1 * dayEnergy));
    }
    Timer {
        id: termGo

        interval: 700
        onTriggered: {
            if (!shell.inApp)
                return;
            if (shell.phys === "air" || shell.phys === "held") {
                restart();   // (estaba dando un saltito: en cuanto aterrice)
                return;
            }
            if (shell.phys !== "swim")
                return;
            const tr = shell.track(shell.nearestScreen(shell.gx, shell.gy)), dist = shell.trackDiff(tr, shell.swimD, shell.termTarget);
            // (lejos: por dentro, más rápido; cerca: asomando la cabeza)
            shell.dive(dist, Math.abs(dist) > 1200 ? "hidden" : "peek", false, shell.termSpeed());
            shell.diveStay = true;
        }
    }
    // La gota que cae del marco al cuadrado (por encima de todo, en el escritorio): al llegar
    // (etaMs) se hincha una gota en el borde de arriba (0,5 s), cae con gravedad hasta el cuadrado
    // y le sigue un chorro fino que se va afinando al ritmo del GIF (que sigue dentro de kitty).
    property real pourX: 0
    property real pourTop: 0
    property real pourBottom: 0
    property real pourAt: 0        // cuándo empieza a hincharse la gota (ms de época)
    property real pourFall: 0.3    // s que tarda en caer
    property bool pouring: false
    readonly property real pourG: 1600
    function schedulePour(etaMs: real): void {
        pourAt = Date.now() + etaMs;
        pourFall = Math.sqrt(2 * Math.max(10, pourBottom - pourTop - 20) / pourG);
        publishEta(etaMs + 500 + pourFall * 1000);   // cuándo llega al cuadrado
        pouring = true;
        pourEnd.interval = etaMs + 500 + pourFall * 1000 + 3000;
        pourEnd.restart();
    }
    Timer {
        id: pourEnd

        onTriggered: shell.pouring = false
    }
    // Cuándo llega la gota al cuadrado (ms de época): lo lee mochi.sh para arrancar el GIF a tiempo
    function publishEta(ms: real): void {
        termEta.setText(String(Math.round(Date.now() + ms)));
    }
    FileView {
        id: termEta

        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/mochi-term-eta`
        printErrors: false
    }

    // Sube de nivel: lo celebra (si está en el editor, lo celebra el del panel)
    Connections {
        target: Bond

        function onLevelUp(level: int, evolved: bool): void {
            if (shell.inApp || !shell.present || shell.locked)
                return;
            shell.reacted(evolved ? "love" : "excited", 2600);
            shell.kicked(-1.8, 2.8);
            if (evolved)
                shell.rainbow(4000);
            if (shell.phys === "swim") {
                shell.hopsLeft = evolved ? 3 : 1;
                shell.hop();
            }
        }
    }

    // ── Ritmo de la música (integrations/beats.py): solo con música de verdad sonando ──
    signal beatHit(real period)
    Process {
        running: Mind.musicPlaying && shell.present && !shell.fsHide && !shell.dnd && !shell.locked && shell.phys !== "nest"
        command: [Quickshell.env("HOME") + "/.local/share/mochi/venv/bin/python", Quickshell.shellDir + "/integrations/beats.py"]
        stdout: SplitParser {
            onRead: data => {
                const p = Number(data.split(" ")[1]);
                if (p > 0)
                    shell.beatHit(p);
            }
        }
    }

    // ── Ver vídeos contigo ──
    // Si estás viendo un vídeo (YouTube, Twitch…; no música) en la pestaña visible, le pica la
    // curiosidad: se acerca por el borde de abajo, se queda debajo mirándolo y reacciona de vez
    // en cuando (y a veces te mira, como "¿has visto eso?"). Si lo pausas, te mira a ti.
    property bool watching: false
    property var videoRect: null
    function isVideo(p: var): bool {
        const url = String(p?.metadata?.["xesam:url"] ?? "");
        return /youtube\.com\/(watch|shorts|live)|youtu\.be\/|twitch\.tv\/|vimeo\.com\/|netflix\.com\/watch|primevideo|disneyplus|max\.com|crunchyroll|dailymotion/.test(url);
    }
    // La ventana del navegador con esa pestaña delante (su título lleva el del vídeo)
    property var videoTest: null   // (IPC `pet watchTest <ms>`: finge un vídeo en la ventana activa)
    property bool watchingGame: false
    readonly property bool gameActive: /minecraft/i.test(Hyprland.activeToplevel?.lastIpcObject?.class ?? "")
    // Lo que cuenta la extensión de Zen (integrations/zen): dónde está el vídeo de verdad, si va,
    // si es un anuncio y los momentos más vistos (YouTube)
    property var browserVideo: null
    property bool videoExact: false
    readonly property bool browserFresh: browserVideo?.type === "video" && Date.now() - (browserVideo?.ts ?? 0) < 3000
    FileView {
        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/mochi-browser.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                shell.browserVideo = JSON.parse(text());
            } catch (e) {}
        }
    }
    function browserRect(): var {
        const b = browserVideo;
        if (!b || b.type !== "video" || Date.now() - b.ts > 3000 || !b.visible || b.fullscreen || (!b.playing && !b.ad))
            return null;
        const key = (b.title ?? "").slice(0, 40);
        const tl = Hyprland.toplevels.values.find(w => key && (w.title ?? "").includes(key));
        const o = tl?.lastIpcObject;
        if (!o?.at || !o?.size || tl.workspace?.id !== mochiWs || o.fullscreen)
            return null;
        const k = o.size[0] / (b.outer?.[0] || o.size[0]);
        return [o.at[0] + (b.inner[0] + b.rect[0]) * k, o.at[1] + (b.inner[1] + b.rect[1]) * k, b.rect[2] * k, b.rect[3] * k];
    }
    function findVideo(): var {
        if (videoTest)
            return videoTest;
        const br = browserRect();
        videoExact = br !== null;
        if (br)
            return br;
        // jugando a Minecraft (ventana activa en su workspace, sin pantalla completa): te mira jugar
        const g = Hyprland.activeToplevel, go = g?.lastIpcObject;
        watchingGame = !!go?.at && /minecraft/i.test(go.class ?? "") && g.workspace?.id === mochiWs && !go.fullscreen;
        if (watchingGame) {
            videoExact = true;
            return [go.at[0], go.at[1], go.size[0], go.size[1]];
        }
        const p = Mind.player;
        if (!p || Mind.musicPlaying || !isVideo(p) || !p.trackTitle)
            return null;
        const t = p.trackTitle.slice(0, 40);
        const tl = Hyprland.toplevels.values.find(w => (w.title ?? "").includes(t));
        const o = tl?.lastIpcObject;
        if (!o?.at || !o?.size || tl.workspace?.id !== mochiWs || o.fullscreen)
            return null;
        return [o.at[0], o.at[1], o.size[0], o.size[1]];
    }
    // Dónde estará el vídeo en la página (aprox.: arriba a la izquierda en YouTube, o
    // centrado si la ventana es estrecha/shorts)
    function videoCenter(r: var): var {
        if (videoExact)
            return {
                x: r[0] + r[2] / 2,
                y: r[1] + r[3] / 2
            };
        const shorts = /shorts/.test(String(Mind.player?.metadata?.["xesam:url"] ?? ""));
        const wide = r[2] > 1100 && !shorts;
        const vw = wide ? r[2] * 0.64 : r[2] * 0.9;
        return {
            x: wide ? r[0] + r[2] * 0.035 + vw / 2 : r[0] + r[2] / 2,
            y: r[1] + 150 + (shorts ? 280 : vw * 9 / 32)
        };
    }
    function watchStep(): void {
        Hyprland.refreshToplevels();
        const r = present && !dnd && !locked && !asking && !Brain.busy ? findVideo() : null;
        if (!r) {
            if (watching) {
                watching = false;
                videoRect = null;
                if (present && !locked)
                    reacted("curious", 1400);   // ¿ya no lo vemos?
            }
            return;
        }
        videoRect = r;
        const c = videoCenter(r);
        if (!watching) {
            if (phys !== "swim" && phys !== "nest" && phys !== "hidden")
                return;
            watching = true;
            if (phys !== "swim")
                touch();
            reacted("curious", 1800);
            watchPlace.restart();
        }
        focusX = c.x;
        focusY = c.y;
        if (Date.now() > lookAtYouUntil)
            focusUntil = Date.now() + 2500;
        videoMoments();
    }
    // Anuncios (se aburre) y momentos más vistos (se inclina hacia delante antes, y ¡oh!)
    property bool inAd: false
    property var peaksSeen: ({})
    function videoMoments(): void {
        const b = browserVideo;
        if (!browserFresh || !videoExact)
            return;
        if (b.ad !== inAd) {
            inAd = b.ad;
            if (inAd) {
                reacted("roll", 1300);   // pff, un anuncio
                adBored.restart();
            } else {
                adBored.stop();
                reacted("happy", 900);   // ¡por fin!
            }
        }
        if (inAd || !b.playing)
            return;
        for (const p of b.peaks ?? []) {
            const key = `${b.url}|${p}`, dt = p - b.time;
            if (dt > 0 && dt < 3 && peaksSeen[key] !== 1) {
                peaksSeen[key] = 1;
                reacted("curious", 2400);   // algo va a pasar…
                leaned(-60);
                kicked(0.8, -0.8);
            } else if (dt <= 0 && dt > -2 && peaksSeen[key] !== 2) {
                peaksSeen[key] = 2;
                reacted(Math.random() < 0.5 ? "surprised" : "excited", 1600);
                kicked(-1.6, 2.4);
            }
        }
    }
    Timer {
        id: adBored

        interval: 3500
        repeat: true
        onTriggered: shell.reacted(Math.random() < 0.5 ? "sleepy" : "roll", 1800)
    }
    property real lookAtYouUntil: 0
    // Se pone debajo del vídeo (en el suelo), un poco a un lado para no tapar los controles
    function goWatch(): void {
        if (!watching || !videoRect || phys !== "swim")
            return;
        const c = videoCenter(videoRect), s = nearestScreen(c.x, c.y), tr = track(s);
        // (en un juego, bien a un lado: en el centro de abajo está la barra de objetos)
        const aside = watchingGame ? videoRect[2] * 0.36 : 60;
        const x = Math.max(tr.L + tr.c, Math.min(tr.R - tr.c, c.x + (c.x > s.x + s.width / 2 ? -1 : 1) * aside));
        const d = nearestD(tr, x, tr.B);
        const dist = trackDiff(tr, swimD, d);
        if (Math.abs(dist) > 900)
            dive(dist, "peek", false, 1.6);
        else if (Math.abs(dist) > 20) {
            energy = 1.5;
            swimTarget = d;
        }
    }
    Timer {
        id: heartHide

        interval: 3000
        onTriggered: shell.heartShown = false
    }
    Timer {
        id: heartDelay

        interval: 900
        onTriggered: shell.heartShown = !shell.dragging && shell.phys !== "nest" && shell.phys !== "dive"
    }
    Timer {
        id: watchTestEnd

        onTriggered: shell.videoTest = null
    }
    Timer {
        id: watchPlace

        interval: 700
        onTriggered: shell.goWatch()
    }
    Timer {
        running: Mind.player !== null || shell.watching || shell.videoTest !== null || shell.browserVideo?.type === "video" || shell.gameActive
        repeat: true
        interval: 700
        onTriggered: shell.watchStep()
    }
    // Viendo el vídeo: alguna reacción de vez en cuando, y a veces te mira a ti
    Timer {
        running: shell.watching && shell.phys === "swim"
        repeat: true
        interval: 15000
        onTriggered: {
            interval = 12000 + Math.random() * 25000;
            const r = Math.random();
            if (r < 0.3) {
                shell.lookAtYouUntil = Date.now() + 1600;
                shell.focusUntil = 0;
                shell.reacted(Bond.level > 0.6 ? "happy" : "curious", 1400);
            } else {
                const faces = shell.watchingGame ? ["focused", "curious", "happy", "surprised"] : ["surprised", "happy", "curious", "excited", "confused"];
                if (Bond.level > 0.6)
                    faces.push("love");
                shell.reacted(faces[Math.floor(Math.random() * faces.length)], 1300);
                if (Math.random() < 0.4)
                    shell.kicked(-0.9, 1.3);
            }
        }
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
            lockedAt = Date.now();
        else if (lockedAt && Date.now() - lockedAt > 30 * 60000)
            greetTimer.restart();
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
            // (con mucho cariño prefiere estar a media distancia del ratón, no lejos)
            const dc = Math.hypot(p.x - cursorX, p.y - cursorY);
            let score = (onScreen ? (1 - seekYou) * Math.min(900, dc) + seekYou * (800 - 2 * Math.abs(dc - 280)) : 500) + Math.random() * 250;
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
        inApp = false;
        diveStay = false;
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
        // (si se queda dentro, al final se hunde del todo aunque viajara asomando la cabeza)
        if (diveStay) {
            const sinkEnd = smooth((u - 0.82) / 0.18);
            vis = vis * (1 - sinkEnd) + diveVisible("hidden", rn) * sinkEnd;
        }
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
        if (data.weather !== undefined) {
            lastWeather = data.weather;
            setWeather(data.weather);
        }
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
        inApp = false;
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
        Bond.gain("pet");
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
        if (inApp) {
            appOptOut = true;
            leaveApp(true);   // lo llamas o lo tocas: sale del editor / la terminal
            return;
        }
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
        if (phys !== "swim" && (nX || nY)) {
            nX = 0;
            nY = 0;
        }
        // el engranaje gira; Clawd usa esto como el tiempo de su animación (patas y brazos)
        if (morph > 0.01)
            shapeRot += dt * (lastShape === 1 ? 1.3 : lastShape === 2 ? 1 : 0);
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
            nX = p.nx;
            nY = p.ny;
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
        if (locked || !chatEnabled)
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
                Bond.gain("talk");
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
        running: shell.voiceEnabled && shell.earsOn && !shell.locked && !shell.earsCooling

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

        // Doble +: si está a la vista se esconde; si no, aparece
        function toggle(): void {
            if (shell.shown) {
                shell.asking = false;
                shell.shown = false;
            } else {
                shell.touch();
                shell.shown = true;
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
            if (shell.voiceEnabled)
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
        // Pruebas del mundo de fuera: calor (grados; 0 = el real), tiempo (código WMO y grados;
        // código −2 = el real), una ventana encima durante ms, y el gorro
        function heat(c: real): void {
            shell.heatTest = c > 0 ? c : NaN;
            shell.heatT = c > 0 ? c : Math.max(shell.cpuTemp, shell.gpuTemp);
        }
        function weather(code: int, c: real): void {
            shell.weatherTest = code === -2 ? null : {
                code: code,
                tempC: c
            };
            shell.setWeather(shell.lastWeather);
        }
        function window(x: int, y: int, w: int, h: int, ms: int): void {
            shell.winTest = [x, y, w, h];
            winTestEnd.interval = ms > 0 ? ms : 2000;
            winTestEnd.restart();
        }
        function hat(name: string): void {
            shell.hatChoice = name || "auto";
        }
        // Cariño: ver/poner (0-100, −1 = solo ver) y simular días sin hacerle caso
        function bond(v: real): string {
            if (v >= 0)
                Bond.bond = Math.min(100, v);
            return `cariño ${Bond.bond.toFixed(1)} · hoy +${Bond.gainedToday.toFixed(1)} (estar cerca +${Bond.presenceToday.toFixed(2)}) · sin caso ${((Date.now() - Bond.lastTouch) / 3600000).toFixed(1)} h · enfurruñado ${Bond.sulky} · viendo vídeo ${shell.watching}`;
        }
        function ignoreDays(days: real): void {
            Bond.lastTouch = Date.now() - days * 86400000;
            Bond.now = Date.now();
        }
        function greet(): void {
            shell.greet();
        }
        // Prueba de un evento de juego: join | death | advancement | kill | mention
        function game(ev: string, peek: bool): void {
            const faces = {
                entrar: ["happy", ["salto", "mirar"]],
                muerte: ["sad", ["susto"]],
                lava: ["sad", ["susto", "derretir"]],
                logro: ["excited", ["salto"]],
                diamantes: ["excited", ["saltos", "estrella"]],
                reto: ["love", ["saltos", "arcoiris"]],
                matar: ["proud", ["estirar"]],
                mencion: ["curious", ["mirar"]]
            }[ev] ?? ["happy", []];
            shell.gameEvent({
                ev: ev,
                cara: faces[0],
                ms: 2400,
                hacer: faces[1]
            }, peek);
        }
        // Experiencia por programar (la manda la extensión del editor)
        function codeXp(n: real): string {
            Bond.addXp(n);
            return `nivel ${Bond.lvl} · ${Math.round(Bond.xp)} XP (siguiente nivel: ${Bond.lvlEnd})`;
        }
        function pop(): void {
            shell.heartPop();
        }
        function enterTerm(offX: real, offY: real, top: real): void {
            shell.enterTerm(offX, offY, top);
        }
        function heart(): void {
            shell.heartShown = true;
            heartHide.restart();
        }
        function watchTest(ms: int): void {
            const o = Hyprland.activeToplevel?.lastIpcObject;
            shell.videoTest = o?.at ? [o.at[0], o.at[1], o.size[0], o.size[1]] : null;
            watchTestEnd.interval = ms > 0 ? ms : 20000;
            watchTestEnd.restart();
        }
        function world(): string {
            return `cpu ${shell.cpuTemp}° gpu ${shell.gpuTemp}° media ${shell.heatT.toFixed(1)}° derretido ${shell.melt.toFixed(2)} · tiempo ${shell.weatherCode} ${shell.weatherTemp}° lluvia ${shell.raining} nieve ${shell.snowing} (${shell.snowAmt.toFixed(2)}) frío ${shell.cold} · aplastado ${shell.press.toFixed(2)} · gorro «${shell.hat}» · reposo ${shell.idleFirst} s · ventana activa ${JSON.stringify(Hyprland.activeToplevel?.lastIpcObject?.at)} ${JSON.stringify(Hyprland.activeToplevel?.lastIpcObject?.size)} flotante ${Hyprland.activeToplevel?.lastIpcObject?.floating}`;
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
                    // enfurruñado no te mira (salvo que algo le llame la atención)
                    const away = Bond.sulky && !focusing && !glancing ? -0.8 : 1;
                    shell.lookX = d < 20 ? 0 : away * dx / (d + 60);
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
        running: shell.shown && shell.present && !shell.fsHide && !shell.dozing && !shell.dnd && shell.phys === "swim" && isNaN(shell.swimTarget) && !shell.sipping && !shell.watching && shell.melt < 0.6 && !shell.asking && !shell.bubbleShown && !shell.voiceWaiting && !Brain.busy
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
                // A otro sitio (no muy lejos, y que no sea junto al ratón… salvo que te quiera
                // mucho: entonces a veces se te acerca, sin ponerse debajo)
                if (Math.random() < shell.seekYou * 0.6) {
                    const d = shell.nearestD(tr, shell.cursorX + (Math.random() < 0.5 ? -1 : 1) * (170 + Math.random() * 120), shell.cursorY), q = shell.pointAt(tr, d);
                    if (q.ny > -0.9 && !shell.inPanel(q.x, q.y, shell.bodyRx + 60) && Math.hypot(q.x - shell.cursorX, q.y - shell.cursorY) > 140) {
                        shell.energy = (0.9 + Math.random() * 0.4) * shell.dayEnergy;
                        shell.swimTarget = d;
                        return;
                    }
                }
                for (let i = 0; i < 6; i++) {
                    const d = shell.swimD + (Math.random() * 2 - 1) * 700, q = shell.pointAt(tr, d);
                    if (Math.hypot(q.x - shell.cursorX, q.y - shell.cursorY) > 300 * (1 - 0.5 * shell.seekYou) && q.ny > -0.9 && !shell.inPanel(q.x, q.y, shell.bodyRx + 60)) {
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
            shell.today = d;
        }
    }

    // Temperaturas (cada 4 s): coretemp, y la NVIDIA solo si no está dormida (no despertarla)
    Process {
        id: heatProc

        command: ["sh", "-c", 'for h in /sys/class/hwmon/hwmon*; do [ "$(cat $h/name)" = coretemp ] && echo "cpu $(cat $h/temp1_input)"; done; for d in /sys/bus/pci/devices/*; do [ "$(cat $d/vendor)" = 0x10de ] && [ "$(cat $d/class)" = 0x030000 ] && [ "$(cat $d/power/runtime_status)" = active ] && echo "gpu $(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null)000"; done']
        stdout: StdioCollector {
            onStreamFinished: {
                let cpu = 0, gpu = 0;
                for (const l of text.split("\n")) {
                    const [k, v] = l.split(" ");
                    if (k === "cpu")
                        cpu = Number(v) / 1000 || 0;
                    else if (k === "gpu")
                        gpu = Number(v) / 1000 || 0;
                }
                shell.cpuTemp = cpu;
                shell.gpuTemp = gpu;
                shell.heatT += (shell.heatNow - shell.heatT) * (1 - Math.exp(-4 / 20));
            }
        }
    }
    Timer {
        running: shell.shown
        repeat: true
        triggeredOnStart: true
        interval: 4000
        onTriggered: heatProc.running = true
    }

    // Ventana activa (si es flotante) por si se le pone encima
    Timer {
        running: (shell.present && shell.phys === "swim" && !shell.locked) || shell.press > 0
        repeat: true
        interval: 140
        onTriggered: {
            if (shell.winTest) {
                shell.checkWindow(shell.winTest);
                return;
            }
            Hyprland.refreshToplevels();
            const o = Hyprland.activeToplevel?.lastIpcObject;
            shell.checkWindow(o?.floating && !o?.fullscreen && o?.at && o?.size ? [o.at[0], o.at[1], o.size[0], o.size[1]] : null);
        }
    }
    Timer {
        id: squeezeDone

        interval: 1600
        onTriggered: shell.squeezing = false
    }
    Timer {
        id: afterSqueeze

        interval: 900
        onTriggered: {
            shell.glanceUntil = Date.now() + 1600;
            shell.reacted("confused", 1500);
        }
    }
    Timer {
        id: winTestEnd

        onTriggered: shell.winTest = null
    }

    // Nieve: se le va acumulando en la cabeza (≈2 min); se sacude de vez en cuando. Si se
    // zambulle o se esconde, se le va.
    Timer {
        running: shell.present || shell.snowAmt > 0
        repeat: true
        interval: 1000
        onTriggered: {
            const out = shell.phys === "swim" || shell.phys === "air" || shell.phys === "held";
            if (shell.snowing && out && !shell.fsHide && !shell.locked && shell.nY > -0.5) {
                shell.snowAmt = Math.min(1, shell.snowAmt + 1 / 120);
                if (shell.snowAmt > 0.55 && shell.phys === "swim" && !shell.sipping && Math.random() < 0.025) {
                    shell.reacted("squint", 700);
                    jitter.restart();
                    shell.snowAmt = 0;
                }
            } else if (!out) {
                shell.snowAmt = 0;
            } else if (!shell.snowing && shell.snowAmt > 0) {
                shell.snowAmt = Math.max(0, shell.snowAmt - 1 / 40);   // se derrite
            }
        }
    }

    // Frío fuera: tirita de vez en cuando
    Timer {
        running: shell.cold && shell.present && !shell.dnd && !shell.locked && shell.phys === "swim" && !shell.sipping && !shell.dozing
        repeat: true
        interval: 8000
        onTriggered: {
            interval = 5000 + Math.random() * 9000;
            shell.reacted("squint", 650);
            jitter.restart();
        }
    }

    // Tormenta: algún trueno le da un susto
    Timer {
        running: shell.storm && shell.present && !shell.dnd && !shell.locked && !shell.dozing
        repeat: true
        interval: 40000
        onTriggered: {
            interval = 25000 + Math.random() * 50000;
            shell.reacted("surprised", 900);
            shell.kicked(1.6, -2);
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

        running: shell.shown && shell.present && shell.phys !== "hidden" && shell.phys !== "nest" && shell.phys !== "dive" && !shell.watching && !shell.asking && !shell.bubbleShown && !shell.voiceWaiting && !Brain.busy
        interval: shell.hideAfter * Math.max(0.5, Math.min(1.3, shell.dayEnergy)) * shell.nestFactor
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
                        // (desplazado hacia el marco lo que encoge al aplastarse/derretirse: sigue pegado)
                        readonly property real cx: half + mochi.shiftX
                        readonly property real cy: half + mochi.shiftY
                        property vector4d body: Qt.vector4d(cx, cy, mochi.bodyRx, mochi.bodyRy)
                        property vector4d mass: Qt.vector4d(cx + mochi.massX - mochi.width / 2, cy + mochi.massY - mochi.height / 2, mochi.massR, 0)
                        property vector4d tail: Qt.vector4d(cx + mochi.tailX - mochi.width / 2, cy + mochi.tailY - mochi.height / 2, mochi.tailR, 0)
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
                        // bracito hasta el asa de la taza (o el mango del paraguas)
                        property vector4d arm: Qt.vector4d(shell.armTip.x - win.modelData.x - x, shell.armTip.y - win.modelData.y - y, Math.max(0, shell.armTip.z), 6)

                        fragmentShader: Qt.resolvedUrl("mochi.frag.qsb")
                    }

                    // Corazoncitos del clic (blancos, con el borde del color de sus ojos)
                    Item {
                        id: pops

                        anchors.fill: parent

                        Connections {
                            target: shell

                            function onHeartPop(): void {
                                if (mochi.visible)
                                    popHeart.createObject(pops, {
                                        x: shell.gx - win.modelData.x - 11 + (Math.random() * 30 - 15),
                                        y: shell.gy - win.modelData.y - shell.bodyRy - 26
                                    });
                            }
                        }
                        Component {
                            id: popHeart

                            Text {
                                id: ph

                                text: "♥"
                                color: "#ffffff"
                                style: Text.Outline
                                styleColor: "#1c1b1b"
                                font.pixelSize: 24
                                transformOrigin: Item.Bottom
                                scale: 0.4

                                ParallelAnimation {
                                    running: true
                                    onFinished: ph.destroy()

                                    NumberAnimation {
                                        target: ph
                                        property: "y"
                                        to: ph.y - 55
                                        duration: 1100
                                        easing.type: Easing.OutQuad
                                    }
                                    NumberAnimation {
                                        target: ph
                                        property: "scale"
                                        to: 1.1
                                        duration: 350
                                        easing.type: Easing.OutBack
                                    }
                                    SequentialAnimation {
                                        PauseAnimation {
                                            duration: 600
                                        }
                                        NumberAnimation {
                                            target: ph
                                            property: "opacity"
                                            to: 0
                                            duration: 500
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Corazoncito de cariño (encima de la cabeza, al dejar el ratón encima)
                    Canvas {
                        id: heart

                        readonly property real level: Bond.level
                        readonly property bool sulky: Bond.sulky
                        onLevelChanged: requestPaint()
                        onSulkyChanged: requestPaint()

                        visible: mochi.visible && opacity > 0
                        opacity: shell.heartShown && !shell.dragging ? 1 : 0
                        scale: 0.6 + 0.4 * opacity
                        width: 30
                        height: 28
                        x: shell.gx - win.modelData.x - width / 2
                        y: shell.gy - win.modelData.y - shell.bodyRy - (shell.hat ? 78 : 44) - height / 2

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 250
                            }
                        }

                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            const path = () => {
                                ctx.beginPath();
                                ctx.moveTo(15, 25);
                                ctx.bezierCurveTo(-2, 14, 3, 1, 15, 8);
                                ctx.bezierCurveTo(27, 1, 32, 14, 15, 25);
                            };
                            // relleno de abajo arriba según el cariño
                            path();
                            ctx.fillStyle = "rgba(255,255,255,0.25)";   // (vacío: blanco muy suave)
                            ctx.fill();
                            ctx.save();
                            path();
                            ctx.clip();
                            ctx.fillStyle = sulky ? "#b9bcc4" : "#ffffff";   // blanco, como él
                            const top = 26 - level * 22;
                            ctx.fillRect(0, top, 30, 30);
                            ctx.restore();
                            path();
                            ctx.lineWidth = 1.8;
                            ctx.strokeStyle = "#1c1b1b";   // borde del color de sus ojos (se ve en fondo claro)
                            ctx.stroke();
                        }
                    }

                    // El paraguas (lloviendo de verdad) y la lluvia a su alrededor; o copos si nieva
                    Canvas {
                        id: umbrella

                        readonly property real t: shell.rainT
                        readonly property var g: shell.umbGeom
                        readonly property real amt: Math.max(0, shell.umbAmt)
                        readonly property bool snow: shell.snowFx

                        visible: mochi.visible && (amt > 0.01 || snow)
                        width: 300
                        height: 300
                        x: shell.gx - win.modelData.x - width / 2
                        y: shell.gy - win.modelData.y - 190
                        onTChanged: requestPaint()
                        onGChanged: requestPaint()

                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            const ox = shell.gx - win.modelData.x - x, oy = shell.gy - win.modelData.y - y;   // Mochi en el lienzo
                            const hx = g.hx - shell.gx + ox, hy = g.hy - shell.gy + oy, tx = g.tx - shell.gx + ox, ty = g.ty - shell.gy + oy;
                            // Copos: bajan despacio haciendo eses (con un borde para que se vean sobre claro)
                            if (snow) {
                                for (let i = 0; i < 16; i++) {
                                    const fx = (i * 0.6180339) % 1, sp = 38 + (i * 13) % 30, r = 2 + (i % 3) * 0.8;
                                    const py = ((t * sp + i * 71) % (oy + 60)) - 20;
                                    const px = 20 + fx * (width - 40) + 7 * Math.sin(t * 1.3 + i * 1.7);
                                    if (Math.abs(px - ox) < shell.bodyRx * 0.85 && py > oy - shell.bodyRy)
                                        continue;
                                    ctx.fillStyle = "#ffffff";
                                    ctx.strokeStyle = "rgba(110,130,165,0.55)";
                                    ctx.lineWidth = 0.9;
                                    ctx.beginPath();
                                    ctx.ellipse(px - r, py - r, 2 * r, 2 * r);
                                    ctx.fill();
                                    ctx.stroke();
                                }
                            }
                            if (amt <= 0.01)
                                return;
                            const W = 62 * amt, H = 30 * amt;   // semiancho y alto de la tela (se abre)
                            // Lluvia: rayitas que caen; las que dan en la tela se quedan ahí
                            ctx.lineCap = "round";
                            ctx.lineWidth = 1.4;
                            ctx.strokeStyle = `rgba(150,185,230,${(0.6 * amt).toFixed(3)})`;
                            ctx.beginPath();
                            for (let i = 0; i < 26; i++) {
                                const fx = ((i * 0.6180339) % 1), sp = 520 + (i * 37) % 140;
                                const px = 20 + fx * (width - 40), py = ((t * sp + i * 97) % (oy + 70)) - 30;
                                const under = Math.abs(px - tx) < W && py > ty - H * (1 - Math.pow((px - tx) / W, 2)) - 4;
                                const onBody = Math.abs(px - ox) < shell.bodyRx * 0.9 && py > oy - shell.bodyRy;
                                if (under || onBody)
                                    continue;
                                ctx.moveTo(px - 1.5, py - 9);
                                ctx.lineTo(px, py);
                            }
                            ctx.stroke();
                            // Mango (de la mano a la tela) y el gancho
                            ctx.strokeStyle = "#3b3b44";
                            ctx.lineWidth = 2.6;
                            ctx.beginPath();
                            ctx.moveTo(hx, hy + 6);
                            ctx.lineTo(tx, ty - H * 0.9);
                            ctx.stroke();
                            ctx.beginPath();
                            ctx.arc(hx - shell.umbSide * 4, hy + 6, 4, 0, Math.PI, shell.umbSide < 0);
                            ctx.stroke();
                            // Tela: gajos azules alternos, festoneada por abajo, un poco inclinada
                            ctx.save();
                            ctx.translate(tx, ty);
                            ctx.rotate(g.ang * 0.4);
                            const n = 4;
                            for (let i = 0; i < n; i++) {
                                const a0 = -W + 2 * W * i / n, a1 = -W + 2 * W * (i + 1) / n;
                                ctx.fillStyle = i % 2 ? "#4f8fe0" : "#3572c4";
                                ctx.beginPath();
                                ctx.moveTo(0, -H);
                                ctx.quadraticCurveTo(a0 * 0.9, -H * 0.95, a0, 0);
                                ctx.quadraticCurveTo((a0 + a1) / 2, -H * 0.28, a1, 0);
                                ctx.quadraticCurveTo(a1 * 0.9, -H * 0.95, 0, -H);
                                ctx.fill();
                            }
                            ctx.fillStyle = "#3b3b44";
                            ctx.beginPath();
                            ctx.ellipse(-2.2, -H - 5, 4.4, 6);
                            ctx.fill();
                            // gotas que resbalan por las puntas
                            ctx.fillStyle = `rgba(150,185,230,${(0.8 * amt).toFixed(3)})`;
                            for (const sgn of [-1, 1]) {
                                const k = (t * 1.3 + (sgn > 0 ? 0.5 : 0)) % 1;
                                ctx.beginPath();
                                ctx.ellipse(sgn * W - 1.6, k * 40 - 1.6, 3.2, 3.8);
                                ctx.fill();
                            }
                            ctx.restore();
                        }
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
                readonly property real hatRoom: 14   // sitio para el gorro
                readonly property string hat: shell.hat
                onHatChanged: requestPaint()

                width: 30
                height: 28 + hatRoom
                x: shell.barW / 2 - width / 2
                y: shell.gy - win.modelData.y - (height - hatRoom) / 2 - 2 - hatRoom

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
                    ctx.translate(0, hatRoom);
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
                    // Gorro de temporada, en pequeñito
                    if (hat) {
                        ctx.translate(15, 5.2 + 1.3 * b + 1.5 * nod);
                        ctx.rotate(nod * 0.13 * mochi.nodDir);
                        Hats.draw(ctx, hat, 9, 0, 0);
                    }
                }
            }

            // La gota y el chorro que caen del marco al cuadrado de kitty (ver schedulePour)
            Canvas {
                id: pourFx

                property real t: -1

                visible: shell.pouring && shell.pourX >= win.modelData.x && shell.pourX < win.modelData.x + win.modelData.width
                x: shell.pourX - win.modelData.x - 30
                y: shell.pourTop - win.modelData.y - 4
                width: 60
                height: Math.max(10, shell.pourBottom - shell.pourTop + 14)
                onTChanged: requestPaint()

                FrameAnimation {
                    running: pourFx.visible
                    onTriggered: pourFx.t = (Date.now() - shell.pourAt) / 1000
                }
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    if (t < 0)
                        return;
                    const cx = 30, top = 4, bottom = height - 10, g = shell.pourG, fall = shell.pourFall;
                    const arrive = 0.5 + fall;
                    ctx.fillStyle = shell.frameColor;
                    // se hincha una gota colgando del marco
                    if (t < 0.5) {
                        const k = t / 0.5, r = 15 * (1 - Math.pow(1 - k, 2));
                        ctx.beginPath();
                        ctx.moveTo(cx - r * 1.4, top - 4);
                        ctx.quadraticCurveTo(cx - r, top, cx - r, top + r * 0.9);
                        ctx.arc(cx, top + r * 0.9, r, Math.PI, 0, true);
                        ctx.quadraticCurveTo(cx + r, top, cx + r * 1.4, top - 4);
                        ctx.closePath();
                        ctx.fill();
                        return;
                    }
                    // cae (y detrás, el chorro)
                    const tf = t - 0.5, head = Math.min(bottom, top + 14 + 0.5 * g * tf * tf);
                    // grosor del chorro: como en el GIF (se afina a partir de ~0,36 s de llegar, hasta ~2,2 s)
                    const ta = t - arrive, w = ta < 0.36 ? 22 : 22 * Math.max(0, 1 - Math.pow((ta - 0.36) / 1.52, 1.3));
                    if (w > 0.5) {
                        ctx.beginPath();
                        Hats.RR(ctx, cx - w / 2, top - 4, w, Math.max(w, head - top + 8), w / 2);
                        ctx.fill();
                        // unión suave con el marco
                        ctx.beginPath();
                        ctx.moveTo(cx - w * 1.2, top - 4);
                        ctx.quadraticCurveTo(cx - w / 2, top, cx - w / 2, top + w);
                        ctx.lineTo(cx + w / 2, top + w);
                        ctx.quadraticCurveTo(cx + w / 2, top, cx + w * 1.2, top - 4);
                        ctx.closePath();
                        ctx.fill();
                    }
                    if (ta < 0) {
                        // la gota de delante, alargada al caer
                        const r = 17, st = 1 + Math.min(0.5, tf * 2);
                        ctx.beginPath();
                        Hats.E(ctx, cx - r / st, head - r * st, 2 * r / st, 2 * r * st);
                        ctx.fill();
                    }
                }
            }

            // Asomándose por la esquina de abajo (juego a pantalla completa): solo en la pantalla
            // con el foco
            Canvas {
                id: cornerPeek

                readonly property real amt: Math.max(0, shell.peekAmt)
                property real t: 0

                visible: amt > 0.01 && win.modelData.name === Hyprland.focusedMonitor?.name
                width: 170
                height: 150
                x: win.modelData.width - width - 40
                y: win.modelData.height - 122 * amt   // (asoma hasta un poco por debajo de los ojos)
                onTChanged: requestPaint()

                FrameAnimation {
                    running: cornerPeek.visible
                    onTriggered: cornerPeek.t += frameTime
                }
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    Draw.avatar(ctx, {
                        x: 85,
                        y: 150,
                        s: 58,
                        body: shell.avatarBody,
                        ink: shell.avatarInk,
                        face: shell.peekFace,
                        hat: shell.hat,
                        stage: Bond.stage,
                        breath: 0.5 + 0.5 * Math.sin(t * 3),
                        ly: -0.4,
                        t: t
                    });
                }
            }

            // Retrato para las integraciones (solo en la primera pantalla; fuera de la vista)
            Canvas {
                id: avatarCanvas

                visible: win.modelData === Quickshell.screens[0]
                x: -300
                y: 0
                width: 256
                height: 256

                Connections {
                    target: shell

                    function onAvatarPaint(): void {
                        if (avatarCanvas.visible)
                            avatarCanvas.requestPaint();
                    }
                }
                Component.onCompleted: {
                    Quickshell.execDetached(["mkdir", "-p", `${Quickshell.env("HOME")}/.cache/mochi`]);
                    shell.avatarPaint();
                }
                // (toDataURL vuelve a emitir painted: se exporta una sola vez por repintado)
                property bool pending: false
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    Draw.avatar(ctx, {
                        x: 128,
                        y: 240,
                        s: 78,
                        body: shell.avatarBody,
                        ink: shell.avatarInk,
                        face: shell.feeling,
                        hat: shell.hat,
                        melt: shell.melt,
                        snow: shell.snowAmt,
                        stage: Bond.stage,
                        t: 0.3
                    });
                    pending = true;
                }
                onPainted: {
                    if (!pending)
                        return;
                    pending = false;
                    // (Canvas.save() no funciona aquí: se pasa como PNG en base64)
                    const url = toDataURL("image/png"), b64 = url.slice(url.indexOf(",") + 1);
                    if (b64.length > 100)
                        avatarB64.setText(b64);   // (y al guardarse, se decodifica a PNG)
                }
                onAvailableChanged: if (available) requestPaint()

                FileView {
                    id: avatarB64

                    path: `${Quickshell.env("XDG_RUNTIME_DIR")}/mochi-avatar.b64`
                    printErrors: false
                    onSaved: Quickshell.execDetached(["sh", "-c", 'base64 -d "$1" > "$2.$$" && mv "$2.$$" "$2"', "sh", path, `${Quickshell.env("HOME")}/.cache/mochi/avatar.png`])
                }
            }

            // Animación de la terminal (fastfetch, ver ~/.config/fish/functions/fish_greeting.fish):
            // Mochi es un fluido: cae un chorro de su material, salpica y va llenando el cuadrado
            // (con la superficie ondulando) hasta que el cuadrado ES él; tiembla como gelatina, abre
            // los ojos, mira a los lados, parpadea y pone una cara (según cómo esté).
            // 80 fotogramas a 25 fps → integrations/fetch-gif.sh → ~/.cache/mochi/fetch.gif
            Canvas {
                id: fetchCanvas

                readonly property int count: 131
                property int frame: -1
                property var frames: []
                property string face: "happy"
                property bool pending: false
                // (los colores se fijan al empezar: el del marco va cambiando mientras pinta)
                property string body: "#d0d3d6"
                property string ink: "#1c1b1b"

                visible: win.modelData === Quickshell.screens[0]
                x: -600
                y: 0
                width: 240
                height: 240

                function start(): void {
                    if (frame >= 0 || !available)
                        return;
                    const f = shell.feeling;
                    face = f === "asleep" || f === "sulky" || f === "hot" || f === "sleepy" ? f : Bond.level > 0.6 && Math.random() < 0.5 ? "love" : ["happy", "excited", "happy"][Math.floor(Math.random() * 3)];
                    body = shell.avatarBody;
                    ink = shell.avatarInk;
                    frames = [];
                    frame = 0;
                    requestPaint();
                }
                Connections {
                    target: shell

                    function onAvatarPaint(): void {
                        if (fetchCanvas.visible)
                            fetchCanvas.start();
                    }
                }
                onAvailableChanged: if (available) start()

                // El cuadrado (con sitio arriba para el gorro)
                readonly property real sx: 16
                readonly property real sy: 38
                readonly property real sw: 208
                readonly property real sh: 194
                readonly property real sr: 46

                function squarePath(ctx: var): void {
                    ctx.beginPath();
                    Hats.RR(ctx, sx, sy, sw, sh, sr);
                }

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    if (frame < 0)
                        return;
                    // Línea de tiempo (25 fps): 0-21 margen · 22 llega la gota que cae del marco (la
                    // dibuja el escritorio hasta aquí) · 31 toca el fondo · 31-75 llena · luego
                    // gelatina, abre los ojos, mira a los lados, parpadea y cara
                    const f = frame, cx = sx + sw / 2, T0 = 22, T1 = 31, T2 = 75;
                    const E0 = T2 + 6, EL = E0 + 7, ER = EL + 10, EB = ER + 10, EF = EB + 5;   // ojos: abre, izq., der., parpadeo, cara
                    const ease = x => 1 - Math.pow(1 - Math.max(0, Math.min(1, x)), 2.2);
                    const fill = f < T1 ? 0 : ease((f - T1) / (T2 - T1));
                    const k = f - T2, jel = f >= T2 ? 0.07 * Math.exp(-k / 4) * Math.cos(k * 0.95) : 0;
                    const hop = f >= EF && f < EF + 7 ? Math.sin((f - EF) / 7 * Math.PI) : 0;
                    const hopSq = f >= EF + 7 ? 0.05 * Math.exp(-(f - EF - 7) / 2.5) * Math.cos((f - EF - 7) * 1.1) : 0;

                    ctx.save();
                    const base = sy + sh;
                    ctx.translate(cx, base - hop * 10);
                    ctx.scale(1 + (jel + hopSq) * 0.8, 1 - jel - hopSq);
                    ctx.translate(-cx, -base);
                    ctx.fillStyle = body;
                    const surfY = sy + sh * (1 - fill);

                    // Cae desde arriba (de donde está él, en el borde): una gota que se descuelga
                    // despacio, se estira y cae con gravedad, y detrás el chorro, cada vez más fino
                    if (f >= T0 && f < T2 - 6) {
                        // (llega ya cayendo: viene del marco, por encima del escritorio)
                        const hang = 1, tf = f - T0;
                        const headY = Math.min(surfY - 4, -20 + 9 * tf + 0.5 * 4.2 * tf * tf);
                        const w = 24 * (1 - Math.pow(Math.max(0, (f - T1) / (T2 - 6 - T1)), 1.3)) * (0.6 + 0.4 * hang);
                        ctx.fillStyle = body;
                        ctx.beginPath();
                        Hats.RR(ctx, cx - w / 2, -12, w, Math.max(w, headY + 12), w / 2);
                        ctx.fill();
                        if (f < T1) {
                            // la gota de delante, algo más gorda y alargada al caer
                            const r = 15 + 5 * hang, st = 1 + Math.min(0.5, tf * 0.06);
                            ctx.beginPath();
                            Hats.E(ctx, cx - r / st, headY - r * st, 2 * r / st, 2 * r * st);
                            ctx.fill();
                        }
                    }

                    // El fluido dentro del cuadrado, con la superficie ondulando
                    if (fill > 0) {
                        ctx.save();
                        squarePath(ctx);
                        ctx.clip();
                        const amp = 12 * (1 - fill) + (f >= T2 ? 0 : 3);
                        ctx.beginPath();
                        ctx.moveTo(sx - 2, sy + sh + 2);
                        for (let x = sx - 2; x <= sx + sw + 2; x += 6) {
                            const y = surfY + amp * Math.sin(x * 0.045 + f * 0.55) + amp * 0.5 * Math.sin(x * 0.11 - f * 0.35)
                                    - (f < T2 - 6 ? 14 * (1 - fill) * Math.exp(-Math.pow((x - cx) / 26, 2)) : 0);   // bulto donde cae el chorro
                            ctx.lineTo(x, y);
                        }
                        ctx.lineTo(sx + sw + 2, sy + sh + 2);
                        ctx.closePath();
                        ctx.fill();
                        if (fill > 0.8) {
                            ctx.fillStyle = `rgba(255,255,255,${(0.1 * (fill - 0.8) / 0.2).toFixed(3)})`;
                            ctx.beginPath();
                            Hats.E(ctx, sx + 22, sy + 16, sw * 0.42, sh * 0.2);
                            ctx.fill();
                        }
                        ctx.restore();
                    }
                    // Salpicaduras al caer la gota
                    if (f >= T1 && f < T1 + 11) {
                        const t = (f - T1) / 11;
                        ctx.fillStyle = body;
                        for (const [dx, v] of [[-1, 1], [1, 0.8], [-0.5, 1.3], [0.6, 1.2]]) {
                            const px = cx + dx * 70 * t, py = sy + sh - 20 - v * 110 * t + 150 * t * t, r = 7 * (1 - t) + 2;
                            ctx.beginPath();
                            Hats.E(ctx, px - r, py - r, 2 * r, 2 * r);
                            ctx.fill();
                        }
                    }
                    if (fill >= 1) {
                        squarePath(ctx);
                        ctx.strokeStyle = "rgba(0,0,0,0.13)";
                        ctx.lineWidth = 2.4;
                        ctx.stroke();
                    }

                    // Ojos: se abren, mira a un lado y a otro, parpadea y pone la cara
                    if (f >= E0) {
                        let fc = "normal", lx = 0, blink = 0;
                        if (f < EL)
                            blink = 1 - (f - E0) / (EL - E0);   // abre los ojos despacio
                        else if (f < ER)
                            lx = -0.75;
                        else if (f < EB)
                            lx = 0.75;
                        else if (f < EF)
                            blink = [0.5, 1, 1, 0.6, 0.2][f - EB];
                        else
                            fc = this.face;
                        Draw.avatar(ctx, {
                            eyesOnly: true,
                            x: cx,
                            y: sy + sh * 0.5,
                            s: 76,
                            ink: ink,
                            face: fc === "asleep" && f < EF ? "normal" : fc,
                            lx: lx,
                            blink: blink
                        });
                        if (shell.hat) {
                            ctx.save();
                            ctx.translate(cx, sy + 12);
                            Hats.draw(ctx, shell.hat, 44, f / 25, 0);
                            ctx.restore();
                        }
                    }
                    ctx.restore();
                    pending = true;
                }
                onPainted: {
                    // (toDataURL vuelve a emitir painted: solo una vez por fotograma)
                    if (!pending || frame < 0)
                        return;
                    pending = false;
                    const url = toDataURL("image/png");
                    frames.push(url.slice(url.indexOf(",") + 1));
                    frame++;
                    if (frame < count) {
                        Qt.callLater(requestPaint);
                    } else {
                        frame = -1;
                        fetchB64.setText(frames.join("\n"));
                        frames = [];
                    }
                }

                FileView {
                    id: fetchB64

                    path: `${Quickshell.env("XDG_RUNTIME_DIR")}/mochi-fetch.b64`
                    printErrors: false
                    onSaved: Quickshell.execDetached([Quickshell.shellDir + "/integrations/fetch-gif.sh", path])
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
                drowsy: shell.caffeine ? 0 : Math.max(shell.drowsy, shell.idleDrowsy ? 0.8 : 0)
                melt: shell.melt
                affection: Bond.level
                sulky: Bond.sulky
                press: shell.press
                pressVertical: Math.abs(shell.nY) >= Math.abs(shell.nX)
                snow: shell.snowAmt
                hat: shell.phys === "nest" && shell.nestPeek < 0.4 ? "" : shell.hat
                anchorNx: shell.nX
                anchorNy: shell.nY
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
                    function onBeatHit(period: real): void {
                        mochi.beat(period);
                    }
                    function onSleepTest(what: string): void {
                        if (what === "nod")
                            mochi.startNod();
                        else if (what === "yawn")
                            mochi.yawn();
                        else if (what === "doze")
                            mochi.dozeOff();
                        else if (what === "wake")
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
                            heartDelay.restart();
                        } else {
                            nestLeave.restart();
                            heartDelay.stop();
                            shell.heartShown = false;
                        }
                        if (containsMouse && shell.phys === "hidden")
                            shell.touch();
                    }

                    // Clic derecho: historial · clic central: activar/silenciar el micro
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton && shell.chatEnabled)
                            Qt.openUrlExternally("file://" + Brain.historyDir);
                        else if (mouse.button === Qt.MiddleButton && shell.voiceEnabled)
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
                        if (!moved)
                            Bond.gain("hold");
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
                            mochi.poke();   // toquecito: se menea contento (y cuenta como cariño)
                            Bond.gain("poke");
                            shell.heartPop();
                            shell.openInput();   // (no hace nada: ya no es un chat)
                        }
                    }
                }
            }

            // Micro silenciado
            Text {
                visible: shell.voiceEnabled && !shell.earsOn && mochi.visible
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
