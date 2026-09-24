// El Mochi pequeñito del panel: respira, parpadea, te sigue con los ojos y cambia de cara.
const vscode = acquireVsCodeApi();
const cv = document.getElementById("c"), ctx = cv.getContext("2d");
const dpr = window.devicePixelRatio || 1;
cv.width = 220 * dpr;
cv.height = 150 * dpr;
cv.style.width = "220px";
cv.style.height = "150px";
ctx.scale(dpr, dpr);
let st = null, face = "normal", blink = 0, mx = 0, my = 0, lx = 0, ly = 0;
const t0 = performance.now();

window.addEventListener("message", e => {
    const m = e.data;
    if (m.type === "state") {
        st = m.state;
        face = m.face;
        document.getElementById("s").textContent = st ? `❤ ${st.bond} · ${st.text}` : "";
    } else if (m.type === "blink") {
        doBlink();
    }
});
document.addEventListener("mousemove", e => {
    const r = cv.getBoundingClientRect();
    mx = e.clientX - (r.x + r.width / 2);
    my = e.clientY - (r.y + r.height * 0.6);
});
cv.addEventListener("click", () => vscode.postMessage({ type: "poke" }));

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

function frame(now) {
    const t = (now - t0) / 1000, d = Math.hypot(mx, my);
    lx += ((d < 15 ? 0 : mx / (d + 80)) - lx) * 0.12;
    ly += ((d < 15 ? 0 : my / (d + 80)) - ly) * 0.12;
    const css = getComputedStyle(document.body);
    ctx.clearRect(0, 0, 220, 150);
    MochiDraw.avatar(ctx, {
        x: 110,
        y: 142,
        s: 44,
        body: st?.body ?? css.getPropertyValue("--vscode-editorWidget-background") ?? "#ccc",
        ink: st?.ink ?? "#1c1b1b",
        face: face,
        hat: st?.hat ?? "",
        melt: st?.melt ?? 0,
        snow: st?.snow ?? 0,
        blink: face === "asleep" ? 0 : blink,
        lx: lx,
        ly: ly,
        breath: 0.5 + 0.5 * Math.sin(t * (face === "asleep" ? 1.6 : 2.6)),
        t: t
    });
    requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
