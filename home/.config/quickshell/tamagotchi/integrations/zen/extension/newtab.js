// Nueva pestaña: Mochi vivo en el centro (respira, parpadea, te sigue con los ojos y se alegra
// si lo tocas), con su estado de verdad (cara, gorro, cariño) y los colores de Caelestia.
const cv = document.getElementById("mochi"), ctx = cv.getContext("2d");
const dpr = window.devicePixelRatio || 1;
cv.width = 360 * dpr;
cv.height = 300 * dpr;
ctx.scale(dpr, dpr);

let st = null, blink = 0, reaction = "", reactionUntil = 0, mx = 0, my = 0, lx = 0, ly = 0, t0 = performance.now();

function apply(msg) {
    if (!msg)
        return;
    st = msg.state;
    const c = msg.colours || {}, r = document.documentElement.style;
    if (c.surface) {
        r.setProperty("--bg", c.surface);
        r.setProperty("--fg", c.onSurface);
        r.setProperty("--muted", c.onSurfaceVariant);
        r.setProperty("--primary", c.primary);
        r.setProperty("--container", c.surfaceContainer);
    }
    document.getElementById("status").textContent = st ? `${st.stageName ?? "Mochi"} · nivel ${st.level ?? 1} · ♥ ${st.bond} · ${st.text}` : "";
}
browser.runtime.sendMessage({ type: "getState" }).then(apply);
browser.runtime.onMessage.addListener(msg => {
    if (msg.type === "state")
        apply(msg);
});

function clock() {
    const d = new Date();
    document.getElementById("clock").textContent = d.toLocaleTimeString("es-ES", { hour: "2-digit", minute: "2-digit" });
    document.getElementById("date").textContent = d.toLocaleDateString("es-ES", { weekday: "long", day: "numeric", month: "long" });
}
clock();
setInterval(clock, 1000);

// Parpadeo
(function blinkLoop() {
    const start = performance.now();
    const step = now => {
        const k = (now - start) / 200;
        blink = k < 0.35 ? k / 0.35 : Math.max(0, 1 - (k - 0.35) / 0.65);
        if (k < 1)
            requestAnimationFrame(step);
        else
            blink = 0;
    };
    requestAnimationFrame(step);
    setTimeout(blinkLoop, 2500 + Math.random() * 3500);
})();

document.addEventListener("mousemove", e => {
    const r = cv.getBoundingClientRect();
    mx = e.clientX - (r.x + r.width / 2);
    my = e.clientY - (r.y + r.height * 0.6);
});
// Clic: se alegra y sale un corazoncito blanco (con el borde del color de sus ojos)
const pops = [];
cv.addEventListener("click", e => {
    reaction = Math.random() < 0.5 ? "happy" : "love";
    reactionUntil = performance.now() + 1400;
    const r = cv.getBoundingClientRect();
    pops.push({ x: e.clientX - r.x, t: performance.now() });
});
function drawPops(now) {
    for (let i = pops.length - 1; i >= 0; i--) {
        const p = pops[i], k = (now - p.t) / 1100;
        if (k >= 1) {
            pops.splice(i, 1);
            continue;
        }
        heart(ctx, Math.min(330, Math.max(30, p.x)), 120 - k * 60, 11 * Math.min(1, 0.4 + k * 3), 1 - Math.max(0, k - 0.55) / 0.45);
    }
}
function heart(ctx, x, y, s, alpha) {
    ctx.save();
    ctx.globalAlpha = alpha;
    ctx.beginPath();
    ctx.moveTo(x, y + s * 0.9);
    ctx.bezierCurveTo(x - s * 1.4, y, x - s * 0.8, y - s * 1.1, x, y - s * 0.4);
    ctx.bezierCurveTo(x + s * 0.8, y - s * 1.1, x + s * 1.4, y, x, y + s * 0.9);
    ctx.fillStyle = "#ffffff";
    ctx.fill();
    ctx.lineWidth = 2;
    ctx.strokeStyle = st?.ink ?? "#1c1b1b";
    ctx.stroke();
    ctx.restore();
}

function frame(now) {
    const t = (now - t0) / 1000;
    const d = Math.hypot(mx, my);
    const tx = d < 20 ? 0 : mx / (d + 120), ty = d < 20 ? 0 : my / (d + 120);
    lx += (tx - lx) * 0.12;
    ly += (ty - ly) * 0.12;
    const face = now < reactionUntil ? reaction : st?.feeling ?? "normal";
    const bodyCss = getComputedStyle(document.documentElement);
    ctx.clearRect(0, 0, 360, 300);
    if (st?.born !== false) MochiDraw.avatar(ctx, {
        x: 180,
        y: 285,
        s: 88,
        body: st?.body ?? bodyCss.getPropertyValue("--container"),
        ink: st?.ink ?? "#1c1b1b",
        face: face,
        hat: st?.hat ?? "",
        melt: st?.melt ?? 0,
        snow: st?.snow ?? 0,
        stage: st?.stage ?? 1,
        look: st?.look,
        skin: st?.skin ?? "",
        blink: face === "asleep" ? 0 : blink,
        lx: lx,
        ly: ly,
        breath: 0.5 + 0.5 * Math.sin(t * (face === "asleep" ? 1.6 : 2.6)),
        t: t
    });
    drawPops(now);
    requestAnimationFrame(frame);
}
requestAnimationFrame(frame);

document.getElementById("search").addEventListener("submit", e => {
    e.preventDefault();
    const q = document.getElementById("q").value.trim();
    if (q)
        browser.runtime.sendMessage({ type: "search", query: q });
});
