.pragma library
.import "Hats.js" as Hats

// Mochi en pequeño, "de retrato", para fuera del escritorio: la imagen de fastfetch, la pestaña
// del dashboard de Caelestia, la nueva pestaña de Zen y el panel de VSCodium. Solo cuerpo
// (daifuku: cúpula arriba, base más plana) y ojos, como el de verdad, más el gorro de temporada.
// Portátil (Canvas de QML y de HTML): las integraciones web usan una copia sin .pragma/.import.
//
// avatar(ctx, o) con o = {
//   x, y: centro de la base (donde se apoya) · s: semiancho del cuerpo (px)
//   body, ink: colores (cuerpo y ojos) · face: normal | happy | love | sad | sulky | asleep |
//   sleepy | surprised | squint | hot | curious | excited
//   lx, ly: hacia dónde mira (−1…1) · blink: 0 abierto → 1 cerrado · t: tiempo (s)
//   breath: 0-1 (respira) · melt: 0-1 · hat: "" | witch | santa | party | crown · snow: 0-1
//   stage: evolución por nivel (0 bebé: más pequeño y ojos más grandes · 1 normal · 2 brillante:
//   más brillo y un destello · 3 sabio: + una estrellita que le da vueltas · 4 legendario: + un
//   brillo arcoíris en el borde)
// }

function avatar(ctx, o) {
    const stage = o.stage ?? 1;
    const s = o.s * (stage === 0 ? 0.82 : 1), t = o.t || 0, m = o.melt || 0, b = o.breath || 0;
    const rx = s * (1 + 0.3 * m + 0.03 * b), ryT = s * (1.0 - 0.34 * m - 0.03 * b), ryB = s * (0.72 - 0.2 * m);
    const cx = o.x, cy = o.y - ryB;

    // Cuerpo: cúpula (arriba) + base más plana, con un brillo arriba a la izquierda
    ctx.fillStyle = o.body;
    ctx.beginPath();
    for (let i = 0; i <= 64; i++) {
        const a = 2 * Math.PI * i / 64, sn = Math.sin(a);
        const px = cx + rx * Math.cos(a), py = cy + (sn < 0 ? ryT : ryB) * sn;
        if (i)
            ctx.lineTo(px, py);
        else
            ctx.moveTo(px, py);
    }
    ctx.closePath();
    ctx.fill();
    ctx.fillStyle = `rgba(255,255,255,${stage >= 2 ? 0.2 : 0.07})`;
    ctx.beginPath();
    Hats.E(ctx, cx - rx * 0.62, cy - ryT * 0.82, rx * 0.7, ryT * 0.42);
    ctx.fill();
    // Legendario: un brillo arcoíris que recorre el borde
    if (stage >= 4) {
        ctx.save();
        ctx.lineWidth = s * 0.06;
        for (let i = 0; i < 24; i++) {
            const a0 = 2 * Math.PI * i / 24, a1 = 2 * Math.PI * (i + 1) / 24;
            const hue = (i * 15 + t * 90) % 360;
            ctx.strokeStyle = `hsla(${hue}, 90%, 65%, 0.55)`;
            ctx.beginPath();
            for (let k = 0; k <= 4; k++) {
                const a = a0 + (a1 - a0) * k / 4, sn = Math.sin(a);
                const px = cx + rx * Math.cos(a), py = cy + (sn < 0 ? ryT : ryB) * sn;
                if (k)
                    ctx.lineTo(px, py);
                else
                    ctx.moveTo(px, py);
            }
            ctx.stroke();
        }
        ctx.restore();
    }

    // Ojos
    const u = s / 32, d = 9.5 * u * (stage === 0 ? 1.12 : 1), f = o.face || "normal";
    let lx = o.lx || 0, ly = o.ly || 0;
    if (f === "sulky")
        lx = -0.8;
    if (f === "curious")
        ly = -0.3;
    const ey = cy - 0.12 * ryT + ly * 5 * u;
    ctx.fillStyle = o.ink;
    ctx.strokeStyle = o.ink;
    ctx.lineCap = "round";
    for (const side of [-1, 1]) {
        const ex = cx + side * 11.5 * u * Math.max(0.8, rx / s) + lx * 6 * u;
        eye(ctx, f, ex, ey, d, side, o.blink || 0, u);
    }
    // Sudor (calor)
    if (f === "hot" || m > 0.3) {
        const k = (t * 0.6) % 1, x = cx + 17 * u, y = cy - ryT * 0.6 + k * ryT * 0.5, r = 3.2 * u;
        ctx.globalAlpha = Math.min(1, (1 - k) * 3);
        ctx.fillStyle = "#8fd0f5";
        ctx.beginPath();
        ctx.moveTo(x, y - r * 2.2);
        ctx.quadraticCurveTo(x + r * 1.1, y - r * 0.4, x + r, y + r * 0.2);
        ctx.arc(x, y + r * 0.2, r, 0, Math.PI);
        ctx.quadraticCurveTo(x - r * 1.1, y - r * 0.4, x, y - r * 2.2);
        ctx.fill();
        ctx.globalAlpha = 1;
    }

    // Brillante en adelante: un destello que aparece y se va; sabio: una estrellita que le da vueltas
    if (stage >= 2) {
        const k = (t * 0.45) % 1;
        if (k < 0.4)
            sparkle(ctx, cx + rx * 0.72, cy - ryT * 0.72, s * 0.12 * Math.sin(k / 0.4 * Math.PI), "#fff6c8");
    }
    if (stage >= 3) {
        const a = t * 1.3;
        const x = cx + Math.cos(a) * rx * 1.25, y = cy - ryT * 0.35 + Math.sin(a) * ryT * 0.35;
        // (por detrás de la cabeza se ve más pequeña)
        sparkle(ctx, x, y, s * (Math.sin(a) > 0 ? 0.1 : 0.07), "#ffd84a");
    }

    // Nieve y gorro, en lo alto de la cabeza
    let top = cy - ryT;
    if (o.snow > 0.02) {
        const w = rx * (0.5 + 0.45 * o.snow), h = 3 * u + 7 * u * o.snow;
        ctx.fillStyle = "#f6f9ff";
        ctx.beginPath();
        ctx.moveTo(cx - w, top + h * 0.55);
        ctx.bezierCurveTo(cx - w * 0.8, top - h * 0.7, cx + w * 0.8, top - h * 0.7, cx + w, top + h * 0.55);
        ctx.bezierCurveTo(cx + w * 0.4, top + h * 0.2, cx - w * 0.4, top + h * 0.2, cx - w, top + h * 0.55);
        ctx.fill();
        top -= h * 0.35;
    }
    if (o.hat) {
        ctx.save();
        ctx.translate(cx, top + 0.16 * s);
        Hats.draw(ctx, o.hat, 0.75 * s, t, Math.sin(t * 1.3) * 0.3);
        ctx.restore();
    }
}

function eye(ctx, f, x, y, d, side, blink, u) {
    ctx.beginPath();
    if (f === "happy" || f === "excited") {
        // ^ ^
        ctx.lineWidth = d * 0.3;
        ctx.moveTo(x - d * 0.55, y + d * 0.3);
        ctx.quadraticCurveTo(x, y - d * 0.55, x + d * 0.55, y + d * 0.3);
        ctx.stroke();
        return;
    }
    if (f === "love") {
        const h = d * 0.62;
        ctx.moveTo(x, y + h * 0.8);
        ctx.bezierCurveTo(x - h * 1.25, y - h * 0.05, x - h * 0.7, y - h * 1.05, x, y - h * 0.4);
        ctx.bezierCurveTo(x + h * 0.7, y - h * 1.05, x + h * 1.25, y - h * 0.05, x, y + h * 0.8);
        ctx.fill();
        return;
    }
    if (f === "asleep") {
        Hats.RR(ctx, x - d * 0.6, y + d * 0.1, d * 1.2, d * 0.18, d * 0.09);
        ctx.fill();
        return;
    }
    if (f === "squint") {
        ctx.lineWidth = d * 0.26;
        ctx.moveTo(x - side * d * 0.45, y - d * 0.4);
        ctx.lineTo(x + side * d * 0.35, y);
        ctx.lineTo(x - side * d * 0.45, y + d * 0.4);
        ctx.stroke();
        return;
    }
    let w = d, h = d * (1 - 0.9 * blink);
    if (f === "surprised" || f === "excited") {
        w *= 1.3;
        h *= 1.3;
    }
    // Párpado de arriba: recto (sueño) o inclinado hacia fuera (pena, calor, enfado)
    let lid = 0, tilt = 0;
    if (f === "sleepy")
        lid = 0.5;
    else if (f === "hot")
        [lid, tilt] = [0.35, -0.35];
    else if (f === "sad" || f === "sulky")
        [lid, tilt] = [0.25, -0.45];
    const topY = y - h / 2, r = Math.min(w, h) / 2;
    if (!lid || h < d * 0.3) {
        Hats.RR(ctx, x - w / 2, y - h / 2, w, Math.max(h, 1.8 * u), Math.min(r, Math.max(h, 1.8 * u) / 2));
        ctx.fill();
        return;
    }
    // ojo con la parte de arriba cortada en diagonal
    const cut = topY + lid * h, inner = cut + tilt * h * 0.4, outer = cut - tilt * h * 0.4;   // (tilt < 0: el lado de fuera cae → pena)
    const yl = side < 0 ? outer : inner, yr = side < 0 ? inner : outer;
    ctx.save();
    ctx.beginPath();
    ctx.moveTo(x - w, yl + (yl - yr) / 2);
    ctx.lineTo(x + w, yr - (yl - yr) / 2);
    ctx.lineTo(x + w, y + h);
    ctx.lineTo(x - w, y + h);
    ctx.closePath();
    ctx.clip();
    ctx.beginPath();
    Hats.RR(ctx, x - w / 2, y - h / 2, w, h, r);
    ctx.fill();
    ctx.restore();
}

// Estrellita de cuatro puntas
function sparkle(ctx, x, y, r, color) {
    if (r <= 0.3)
        return;
    ctx.save();
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.moveTo(x, y - r);
    ctx.quadraticCurveTo(x, y, x + r, y);
    ctx.quadraticCurveTo(x, y, x, y + r);
    ctx.quadraticCurveTo(x, y, x - r, y);
    ctx.quadraticCurveTo(x, y, x, y - r);
    ctx.fill();
    ctx.restore();
}
