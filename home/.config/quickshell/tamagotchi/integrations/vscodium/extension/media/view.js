// El panel de Mochi (abajo a la izquierda del explorador): Mochi en la esquina, con su nivel y
// la barra de experiencia. Cuando el Mochi del escritorio se mete en el editor, aparece aquí
// saltando desde abajo; cuando se va, se hunde y queda un aviso de que está fuera.
const vscode = acquireVsCodeApi();
const cv = document.getElementById("c"), ctx = cv.getContext("2d");
const W = 150, H = 130;
const dpr = window.devicePixelRatio || 1;
cv.width = W * dpr;
cv.height = H * dpr;
cv.style.width = W + "px";
cv.style.height = H + "px";
ctx.scale(dpr, dpr);

let st = null, langs = "", lang = "", face = "normal", blink = 0, mx = 0, my = 0, lx = 0, ly = 0;
let here = 0, hereTarget = 0;          // 0 fuera → 1 dentro del editor (animado)
let squash = 0, squashV = 0;           // muelle al llegar o al celebrar
let celebrateUntil = 0, celebrateFace = "excited";
const pops = [];                       // "+10 XP" que suben y se desvanecen
const t0 = performance.now();

window.addEventListener("message", e => {
    const m = e.data;
    if (m.type === "state") {
        st = m.state;
        face = m.face;
        langs = m.langs || "";
        lang = m.lang || "";
        const inApp = st?.where === "app";
        // (si Mochi no está en marcha, se queda aquí igualmente)
        hereTarget = inApp || !st ? 1 : 0;
        info();
    } else if (m.type === "blink") {
        doBlink();
    } else if (m.type === "xp") {
        pops.push({ text: `+${m.n} XP`, t: performance.now(), why: m.why });
        squashV -= 2;
    } else if (m.type === "levelUp") {
        celebrateUntil = performance.now() + 3000;
        celebrateFace = m.evolved ? "love" : "excited";
        pops.push({ text: m.evolved ? `¡Evoluciona! ${m.stageName}` : `¡Nivel ${m.level}!`, t: performance.now(), big: true });
        squashV -= 5;
    }
});

function info() {
    const lvl = st?.level ?? 1, a = st?.levelStart ?? 0, b = st?.levelEnd ?? 60, xp = st?.xp ?? 0;
    document.getElementById("name").textContent = st?.stageName ?? "Mochi";
    document.getElementById("lvl").textContent = `Nivel ${lvl} · ${xp - a} / ${b - a} XP`;
    document.getElementById("fill").style.width = `${Math.max(0, Math.min(100, 100 * (xp - a) / Math.max(1, b - a)))}%`;
    document.getElementById("mood").textContent = st ? `♥ ${st.bond} · ${st.text}` : "";
    document.getElementById("mood").title = langs ? `Programado: ${langs}` : "";
    document.getElementById("langs").textContent = langs;
    const away = document.getElementById("away");
    away.style.display = hereTarget < 0.5 ? "block" : "none";
    away.textContent = `Mochi está fuera, paseando por el escritorio · nivel ${lvl}. Vuelve cuando entres al editor.`;
    document.getElementById("info").style.display = hereTarget < 0.5 ? "none" : "block";
}

document.addEventListener("mousemove", e => {
    const r = cv.getBoundingClientRect();
    mx = e.clientX - (r.x + r.width / 2);
    my = e.clientY - (r.y + r.height * 0.6);
});
cv.addEventListener("click", () => {
    squashV -= 3;
    pops.push({ heart: true, t: performance.now() });   // corazoncito blanco
    vscode.postMessage({ type: "poke" });
});

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

let last = performance.now();
function frame(now) {
    const dt = Math.min(0.05, (now - last) / 1000);
    last = now;
    const t = (now - t0) / 1000, d = Math.hypot(mx, my);
    lx += ((d < 15 ? 0 : mx / (d + 80)) - lx) * 0.12;
    ly += ((d < 15 ? 0 : my / (d + 80)) - ly) * 0.12;
    // llegar / irse: sube desde abajo con un rebote
    const wasHere = here;
    here += (hereTarget - here) * Math.min(1, dt * 5);
    if (wasHere < 0.5 && here >= 0.5)
        squashV -= 6;
    squashV += (-120 * squash - 9 * squashV) * dt;
    squash += squashV * dt;

    ctx.clearRect(0, 0, W, H);
    if (here > 0.02 && st?.born !== false) {
        const f = now < celebrateUntil ? celebrateFace : face;
        const hop = now < celebrateUntil ? Math.abs(Math.sin((now - celebrateUntil) / 180)) * 10 : 0;
        ctx.save();
        const baseY = H - 6 + (1 - here) * 110 - hop;
        ctx.translate(62, baseY);
        ctx.scale(1 - squash * 0.05, 1 + squash * 0.07);
        ctx.translate(-62, -baseY);
        MochiDraw.avatar(ctx, {
            x: 62,
            y: baseY,
            s: 40,
            body: st?.body ?? "#d0d3d6",
            ink: st?.ink ?? "#1c1b1b",
            face: f,
            hat: st?.hat ?? "",
            melt: st?.melt ?? 0,
            snow: st?.snow ?? 0,
            stage: st?.stage ?? 0,
            look: st?.look,
            blink: f === "asleep" ? 0 : blink,
            lx: lx,
            ly: ly,
            breath: 0.5 + 0.5 * Math.sin(t * (f === "asleep" ? 1.6 : 2.6)),
            t: t
        });
        ctx.restore();
    }
    // "+XP" que suben
    for (let i = pops.length - 1; i >= 0; i--) {
        const p = pops[i], k = (now - p.t) / (p.big ? 2600 : 1400);
        if (k >= 1) {
            pops.splice(i, 1);
            continue;
        }
        if (p.heart) {
            const x = 62, y = 60 - k * 40, s = 8 * Math.min(1, 0.4 + k * 3);
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
        ctx.globalAlpha = 1 - k * k;
        ctx.fillStyle = getComputedStyle(document.body).getPropertyValue("--vscode-charts-yellow") || "#e5c07b";
        ctx.font = `${p.big ? "bold 13px" : "600 12px"} ${getComputedStyle(document.body).fontFamily}`;
        ctx.textAlign = "center";
        ctx.fillText(p.text, p.big ? 75 : 100, 34 - k * 26);
        ctx.globalAlpha = 1;
    }
    requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
