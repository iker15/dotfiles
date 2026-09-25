// El panel de Mochi (abajo a la izquierda del explorador): Mochi en la esquina, con su ficha (nivel,
// experiencia, lo de hoy). Cuando el Mochi del escritorio se mete en el editor, aparece aquí
// saltando desde abajo; cuando se va, se hunde y queda un aviso de dónde está.
//
// Dentro: mientras escribes mira hacia el código (el editor está a su derecha) y se menea un
// poco con cada ráfaga; si lo dejas solo le entra sueño y se duerme (se despierta sobresaltado
// cuando vuelves); con muchos errores suda; celebra commits y subidas de nivel; si se transforma,
// la forma nueva le crece como en el escritorio. Se escala para caber entero en el panel.
const vscode = acquireVsCodeApi();
const cv = document.getElementById("c"), ctx = cv.getContext("2d");
const $ = id => document.getElementById(id);
const Skins = window.MochiSkins;

let W = 300, H = 150, dpr = 1, mochiW = 150;
let st = null, alive = true, isHere = false, hostFace = "normal", errors = 0, todayStats = null, langs = "", lang = "";
let blink = 0, mx = 0, my = 0, lx = 0, ly = 0, mouseIn = false;
let here = 0;                          // 0 fuera → 1 dentro del editor (animado)
let squash = 0, squashV = 0;           // muelle al llegar, al tocarlo o al celebrar
let celebrateUntil = 0, celebrateFace = "excited", hopUntil = 0;
let lastActive = performance.now(), lastTyping = -1e9, wokeUntil = 0;
let skinShown = "", skinAmt = 0, skinAnim = null;
let geo = { x: 75, y: 140, s: 40, top: 70 };
const pops = [];                       // "+10 XP" y corazones que suben y se desvanecen
const t0 = performance.now();
let accent = "#e5c07b", font = "sans-serif", fg = "#ccc";

function readTheme() {
    const cs = getComputedStyle(document.body);
    accent = cs.getPropertyValue("--vscode-charts-yellow").trim() || "#e5c07b";
    font = cs.fontFamily || "sans-serif";
    fg = cs.color || "#ccc";
}
// (el tema del editor cambia la clase de <body>)
new MutationObserver(readTheme).observe(document.body, { attributes: true, attributeFilter: ["class"] });
readTheme();

// ── Tamaño: el lienzo ocupa todo el panel; él cabe entero (también transformado) ──
function bounds(skin) {
    // alto y ancho en unidades de su tamaño (s), y el centro en x de la silueta
    const wide = st?.look?.wide ?? 1, lh = 1 / Math.sqrt(wide);
    let h = 1.72 * lh, w = 2 * wide, c = 0;
    const def = skin && Skins ? Skins.byId(skin) : null;
    if (def?.sil) {
        const p = def.sil.pts, k = wide * def.sil.size;
        let top = 1, x0 = 1e9, x1 = -1e9;
        for (let i = 0; i < p.length; i += 2) {
            top = Math.min(top, p[i + 1]);
            x0 = Math.min(x0, p[i]);
            x1 = Math.max(x1, p[i]);
        }
        h = Math.max(h, (1 - top) * k);
        w = Math.max(w, (x1 - x0) * k);
        c = (x0 + x1) / 2 * k;
    }
    return { h, w, c };
}
function layout() {
    W = window.innerWidth;
    H = window.innerHeight;
    dpr = window.devicePixelRatio || 1;
    cv.width = Math.round(W * dpr);
    cv.height = Math.round(H * dpr);
    cv.style.width = W + "px";
    cv.style.height = H + "px";
    const narrow = W < 250, short = H < 125;
    document.body.classList.toggle("narrow", narrow);
    document.body.classList.toggle("short", short);
    mochiW = narrow ? W : Math.max(110, Math.min(170, W * 0.42));
    document.body.style.setProperty("--info-left", `${Math.round(mochiW)}px`);
    fitInfo();
    place();
}
function place() {
    // (mientras se transforma, el tamaño de la más grande de las dos: que no dé saltos)
    const b = bounds(skinShown), b0 = skinAnim ? bounds(skinAnim.to) : b;
    const hf = Math.max(b.h, b0.h), wf = Math.max(b.w, b0.w);
    const infoH = document.body.classList.contains("narrow") && isHere ? $("info").offsetHeight + 14 : 0;
    const room = H - infoH - 18;   // (y sitio para saltar)
    const s = Math.max(14, Math.min(44, room / hf, (mochiW - 16) / wf));
    geo.s = s;
    geo.x = mochiW / 2 - (skinAmt > 0.5 ? b.c : 0) * s;
    geo.y = H - 6;
    geo.top = geo.y - hf * s;
}
new ResizeObserver(layout).observe(document.body);

// ── Mensajes del editor ──
window.addEventListener("message", e => {
    const m = e.data;
    if (m.type === "state") {
        st = m.state;
        alive = m.alive;
        isHere = !!m.here;
        hostFace = m.face;
        errors = m.errors ?? 0;
        todayStats = m.today;
        langs = m.langs || "";
        lang = m.lang || "";
        const skin = st?.skin ?? "";
        if (skin !== (skinAnim ? skinAnim.to : skinShown))
            transform(skin);
        info();
    } else if (m.type === "blink") {
        doBlink();
        squashV -= 1.2;
    } else if (m.type === "typing") {
        active(true);
    } else if (m.type === "active") {
        active(false);
    } else if (m.type === "xp") {
        pops.push({ text: `+${m.n} XP`, t: performance.now() });
        squashV -= 2;
    } else if (m.type === "hop") {
        hopUntil = performance.now() + 900;
        squashV -= 4;
    } else if (m.type === "say") {
        say(m.text, m.ms);
    } else if (m.type === "levelUp") {
        celebrateUntil = performance.now() + 3000;
        celebrateFace = m.evolved ? "love" : "excited";
        pops.push({ text: m.evolved ? `¡Evoluciona! ${m.stageName}` : `¡Nivel ${m.level}!`, t: performance.now(), big: true });
        squashV -= 5;
    }
});

function info() {
    const lvl = st?.level ?? 1, a = st?.levelStart ?? 0, b = st?.levelEnd ?? 60, xp = st?.xp ?? 0;
    const nick = st?.look?.nick;
    // (con mote: «Bolita  Mochi bebé»; sin mote, solo su etapa: «Mochi bebé»)
    $("nick").textContent = nick || st?.stageName || "Mochi";
    $("stage").textContent = nick ? st?.stageName ?? "" : "";
    $("lvlN").textContent = `Nivel ${lvl}`;
    $("lvlXp").textContent = `${xp - a} / ${b - a} XP`;
    $("fill").style.width = `${Math.max(0, Math.min(100, 100 * (xp - a) / Math.max(1, b - a)))}%`;
    const t = todayStats;
    $("today").textContent = t ? `Hoy ${fmtMin(t.minutes)} · +${t.xp} XP${lang ? ` · ${lang}` : ""}` : "";
    $("mood").textContent = st ? `♥ ${st.bond} · ${st.text}` : "";
    $("langs").textContent = langs;
    $("langs").title = langs ? `Programado: ${langs}` : "";
    const errs = $("errs");
    errs.classList.toggle("on", errors > 0);
    errs.textContent = `⚠ ${errors} ${errors === 1 ? "error" : "errores"}`;

    document.body.classList.toggle("here", isHere);
    document.body.classList.toggle("gone", !isHere);
    $("awayText").textContent = awayText(lvl);
    fitInfo();
    place();
}
// Que la ficha quepa: quita líneas (lenguajes, ánimo, lo de hoy) hasta que entre
function fitInfo() {
    const b = document.body, el = $("info");
    b.classList.remove("fit1", "fit2", "fit3");
    if (!isHere)
        return;
    const room = b.classList.contains("narrow") ? H * 0.5 : H - 16;
    for (const c of ["fit1", "fit2", "fit3"]) {
        if (el.offsetHeight <= room)
            break;
        b.classList.add(c);
    }
}
function awayText(lvl) {
    if (!st || !alive)
        return "Mochi no está en marcha ahora mismo.";
    if (st.born === false || st.where === "unborn")
        return "Mochi aún no ha nacido: créalo en su pestaña del dashboard.";
    if (st.where === "away")
        return `Mochi está de visita en casa de ${st.away?.to ?? "un vecino"}. Llámalo desde el dashboard para que vuelva.`;
    if (st.where === "app")
        return "Mochi está en otra ventana del editor.";
    if (st.dnd)
        return "Mochi está durmiendo (No molestar).";
    if (st.waiting)
        return "Mochi está esperando en su nido: sácalo de ahí y entrará al editor.";
    return `Mochi está paseando por el escritorio · nivel ${lvl}. Entrará en cuanto vuelvas al editor.`;
}
function fmtMin(n) {
    return n >= 60 ? `${Math.floor(n / 60)} h${n % 60 ? ` ${n % 60} min` : ""}` : `${n} min`;
}

// Actividad: al escribir mira hacia el código; si estaba dormido, se despierta sobresaltado
function active(typing) {
    const now = performance.now();
    if (typing) {
        if (now - lastActive > 15 * 60000 && isHere) {
            wokeUntil = now + 900;
            squashV -= 5;
        }
        lastTyping = now;
        squashV -= 0.6;
    }
    lastActive = now;
}

// Bocadillo encima de él
let bubbleTimer = 0;
function say(text, ms) {
    if (!text || !isHere)
        return;
    const b = $("bubble");
    b.textContent = text;
    b.classList.add("on");
    clearTimeout(bubbleTimer);
    bubbleTimer = setTimeout(() => b.classList.remove("on"), ms || 2600);
}

// Transformación: la vieja se le encoge, y la nueva le crece hasta pasarse un poco y se asienta
// (los mismos tiempos que en el escritorio)
function transform(to) {
    const keys = [];
    if (skinShown && skinAmt > 0)
        keys.push({ to: 0, ms: 500, ease: io });
    keys.push({ swap: true });
    if (to)
        keys.push({ to: 0.3, ms: 500, ease: io }, { to: 1.12, ms: 950, ease: io }, { to: 0.95, ms: 260, ease: io }, { to: 1, ms: 240, ease: k => Math.sin(k * Math.PI / 2) });
    // (si no está a la vista, sin animación)
    if (!isHere || document.hidden) {
        skinShown = to;
        skinAmt = to ? 1 : 0;
        skinAnim = null;
        place();
        return;
    }
    skinAnim = { to, keys, i: 0, from: skinAmt, t: performance.now() };
    squashV -= 3;
    place();
}
function io(k) {
    return 0.5 - 0.5 * Math.cos(Math.PI * k);
}
function stepSkin(now) {
    const a = skinAnim;
    if (!a)
        return;
    while (a.i < a.keys.length) {
        const k = a.keys[a.i];
        if (k.swap) {
            skinShown = a.to;
            a.i++;
            a.from = skinAmt;
            a.t = now;
            squashV -= 4;   // se estira y…
            place();
            continue;
        }
        const u = Math.min(1, (now - a.t) / k.ms);
        skinAmt = a.from + (k.to - a.from) * k.ease(u);
        if (u < 1)
            return;
        a.i++;
        a.from = skinAmt;
        a.t = now;
    }
    skinAnim = null;
    celebrateUntil = now + 1400;
    celebrateFace = skinShown ? "excited" : "happy";
    place();
}

// ── Ratón y clics ──
document.addEventListener("mousemove", e => {
    mx = e.clientX - geo.x;
    my = e.clientY - (geo.y + geo.top) / 2;
    mouseIn = true;
    lastActive = performance.now();
});
document.addEventListener("mouseleave", () => (mouseIn = false));
cv.addEventListener("click", e => {
    if (!isHere)
        return;
    // (solo si le das a él)
    if (Math.abs(e.clientX - geo.x) > geo.s * 1.4 || e.clientY < geo.top - 6)
        return;
    squashV -= 3;
    pops.push({ heart: true, t: performance.now() });   // corazoncito blanco
    lastActive = performance.now();
    vscode.postMessage({ type: "poke" });
});
cv.addEventListener("mousemove", e => {
    cv.style.cursor = isHere && Math.abs(e.clientX - geo.x) < geo.s * 1.4 && e.clientY > geo.top - 6 ? "pointer" : "default";
});
$("out").addEventListener("click", () => vscode.postMessage({ type: "call" }));
$("errs").addEventListener("click", () => vscode.postMessage({ type: "problems" }));

// Parpadeo
function doBlink() {
    const s = performance.now();
    const step = now => {
        const k = (now - s) / 200;
        blink = k < 0.35 ? k / 0.35 : Math.max(0, 1 - (k - 0.35) / 0.65);
        if (k < 1)
            requestAnimationFrame(step);
        else
            blink = 0;
    };
    requestAnimationFrame(step);
}
(function loop() {
    doBlink();
    setTimeout(loop, 2500 + Math.random() * 3500);
})();

// La cara: la de las reacciones del editor manda; si no, le entra sueño si lo dejas solo
function faceNow(now) {
    if (now < wokeUntil)
        return "surprised";
    if (now < celebrateUntil)
        return celebrateFace;
    const calm = hostFace === "normal" || hostFace === "love" || hostFace === "happy" || hostFace === "curious";
    const idle = now - lastActive;
    if (calm && idle > 15 * 60000)
        return "asleep";
    if (calm && idle > 5 * 60000)
        return "sleepy";
    return hostFace;
}

// ── Dibujo (a 30 fps: es un panel pequeño, no hace falta más) ──
let last = performance.now(), lastDraw = 0;
function frame(now) {
    requestAnimationFrame(frame);
    if (now - lastDraw < 32)
        return;
    lastDraw = now;
    const dt = Math.min(0.05, (now - last) / 1000);
    last = now;
    const t = (now - t0) / 1000;
    stepSkin(now);

    const f = faceNow(now);
    // hacia dónde mira: el ratón si está en el panel; escribiendo, al código (a su derecha)
    let tx = 0, ty = 0;
    if (mouseIn) {
        const d = Math.hypot(mx, my);
        tx = d < 15 ? 0 : mx / (d + 80);
        ty = d < 15 ? 0 : my / (d + 80);
    } else if (now - lastTyping < 2500) {
        tx = 0.75;
        ty = -0.15;
    }
    lx += (tx - lx) * 0.18;
    ly += (ty - ly) * 0.18;

    // llegar / irse: sube desde abajo con un rebote
    const wasHere = here;
    here += ((isHere ? 1 : 0) - here) * Math.min(1, dt * 5);
    if (wasHere < 0.5 && here >= 0.5)
        squashV -= 6;
    squashV += (-120 * squash - 9 * squashV) * dt;
    squash += squashV * dt;

    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, W, H);
    if (here > 0.02 && st && st.born !== false) {
        const celebrating = now < celebrateUntil || now < hopUntil;
        const hop = celebrating ? Math.abs(Math.sin((now - t0) / 180)) * Math.min(12, geo.s * 0.3) : 0;
        const baseY = geo.y + (1 - here) * (geo.y - geo.top + 20) - hop;
        ctx.save();
        ctx.translate(geo.x, baseY);
        ctx.scale(1 - squash * 0.05, 1 + squash * 0.07);
        ctx.translate(-geo.x, -baseY);
        MochiDraw.avatar(ctx, {
            x: geo.x,
            y: baseY,
            s: geo.s,
            body: st.body ?? "#d0d3d6",
            ink: st.ink ?? "#1c1b1b",
            face: f,
            hat: st.hat ?? "",
            melt: st.melt ?? 0,
            snow: st.snow ?? 0,
            stage: st.stage ?? 0,
            look: st.look,
            skin: skinShown,
            skinAmt: Math.max(0, skinAmt),
            blink: f === "asleep" ? 0 : blink,
            lx: lx,
            ly: ly,
            breath: 0.5 + 0.5 * Math.sin(t * (f === "asleep" ? 1.6 : 2.6)),
            t: t
        });
        ctx.restore();
        const top = baseY - (geo.y - geo.top);
        // sudor con muchos errores
        if (errors >= 3 && f !== "asleep")
            drop(geo.x + geo.s * 0.62, top + geo.s * 0.35 + ((t * 0.6) % 1) * geo.s * 0.5, geo.s / 40, 1 - ((t * 0.6) % 1));
        // dormido: zetas que suben
        if (f === "asleep")
            for (let i = 0; i < 3; i++) {
                const k = (t * 0.35 + i / 3) % 1;
                ctx.globalAlpha = Math.sin(k * Math.PI) * 0.8;
                ctx.fillStyle = fg;
                ctx.font = `600 ${Math.round(9 + k * 6)}px ${font}`;
                ctx.fillText("z", geo.x + geo.s * 0.5 + k * 14, top + 4 - k * 22);
                ctx.globalAlpha = 1;
            }
        // el bocadillo, sobre su cabeza
        const bub = $("bubble");
        bub.style.left = `${Math.max(4, Math.min(W - bub.offsetWidth - 4, geo.x - 22))}px`;
        bub.style.bottom = `${Math.round(H - top + 8)}px`;
    }
    // "+XP" y corazones que suben
    for (let i = pops.length - 1; i >= 0; i--) {
        const p = pops[i], k = (now - p.t) / (p.big ? 2600 : 1400);
        if (k >= 1) {
            pops.splice(i, 1);
            continue;
        }
        if (p.heart) {
            const x = geo.x, y = geo.top + 10 - k * 36, s = geo.s / 5 * Math.min(1, 0.4 + k * 3);
            ctx.globalAlpha = 1 - Math.max(0, k - 0.55) / 0.45;
            ctx.beginPath();
            ctx.moveTo(x, y + s * 0.9);
            ctx.bezierCurveTo(x - s * 1.4, y, x - s * 0.8, y - s * 1.1, x, y - s * 0.4);
            ctx.bezierCurveTo(x + s * 0.8, y - s * 1.1, x + s * 1.4, y, x, y + s * 0.9);
            ctx.fillStyle = "#ffffff";
            ctx.fill();
            ctx.lineWidth = 1.5;
            ctx.strokeStyle = st?.ink ?? "#1c1b1b";
            ctx.stroke();
            ctx.globalAlpha = 1;
            continue;
        }
        if (!isHere)
            continue;
        ctx.globalAlpha = 1 - k * k;
        ctx.fillStyle = accent;
        ctx.font = `${p.big ? "bold 13px" : "600 12px"} ${font}`;
        ctx.textAlign = "center";
        ctx.fillText(p.text, p.big ? geo.x + 8 : geo.x + geo.s * 1.1, Math.max(14, geo.top + 4 - k * 24));
        ctx.textAlign = "start";
        ctx.globalAlpha = 1;
    }
}
function drop(x, y, k, a) {
    ctx.globalAlpha = Math.max(0, a);
    ctx.fillStyle = "#8fd0f5";
    ctx.beginPath();
    ctx.moveTo(x, y - 5 * k);
    ctx.quadraticCurveTo(x + 3.2 * k, y, x, y + 3 * k);
    ctx.quadraticCurveTo(x - 3.2 * k, y, x, y - 5 * k);
    ctx.fill();
    ctx.globalAlpha = 1;
}

layout();
requestAnimationFrame(frame);
vscode.postMessage({ type: "ready" });   // (ya puede recibir el estado)
