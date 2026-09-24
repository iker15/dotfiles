// Generado por integrations/build-web.sh desde Hats.js y Draw.js (no editar)
(function (g) {
const Hats = (function () {

// Accesorios de temporada (los lleva Mochi en la cabeza, y su icono en el nido).
// Portátil: sirve con el Canvas de QML y con el de HTML (la extensión de Zen y la de VSCodium
// usan una copia sin la línea .pragma; ver integrations/build-web.sh).
// Se dibujan con la base en (0, 0) y hacia arriba = -y; s = medio ancho de la cabeza (px),
// sway = cuánto se le balancea la punta (−1…1), t = tiempo (s).

// Qué toca hoy: Halloween, Navidad, Nochevieja, Reyes y el cumple de Mochi (22 de septiembre)
function seasonal(d) {
    const m = d.getMonth() + 1, day = d.getDate();
    if (m === 9 && day === 22)
        return "party";
    if ((m === 10 && day >= 24) || (m === 11 && day <= 1))
        return "witch";
    if ((m === 12 && day === 31) || (m === 1 && day === 1))
        return "party";
    if (m === 1 && (day === 5 || day === 6))
        return "crown";
    if ((m === 12 && day >= 1) || (m === 1 && day <= 7))
        return "santa";
    return "";
}

// Elipse por su caja (x, y, ancho, alto) y rectángulo redondeado, en QML y en HTML
function E(ctx, x, y, w, h) {
    if (ctx.roundedRect) {
        ctx.ellipse(x, y, w, h);
    } else {
        ctx.moveTo(x + w, y + h / 2);
        ctx.ellipse(x + w / 2, y + h / 2, Math.abs(w / 2), Math.abs(h / 2), 0, 0, 2 * Math.PI);
    }
}

function RR(ctx, x, y, w, h, r) {
    if (ctx.roundedRect)
        ctx.roundedRect(x, y, w, h, r, r);
    else
        ctx.roundRect(x, y, w, h, r);
}

function draw(ctx, name, s, t, sway) {
    if (name === "witch")
        witch(ctx, s, sway);
    else if (name === "santa")
        santa(ctx, s, sway);
    else if (name === "party")
        party(ctx, s, sway);
    else if (name === "crown")
        crown(ctx, s, t);
}

// Sombrero de bruja: ala ancha, cono morado con la punta doblada y cinta naranja
function witch(ctx, s, sway) {
    const tipX = s * (0.34 + 0.12 * sway), tipY = -s * 1.12;
    ctx.fillStyle = "#4a2a6a";
    ctx.beginPath();
    ctx.moveTo(-s * 0.42, -s * 0.06);
    ctx.quadraticCurveTo(-s * 0.3, -s * 0.62, -s * 0.02, -s * 0.9);
    ctx.quadraticCurveTo(tipX * 0.6, -s * 1.1, tipX, tipY);
    ctx.quadraticCurveTo(s * 0.12, -s * 0.78, s * 0.2, -s * 0.5);
    ctx.quadraticCurveTo(s * 0.34, -s * 0.24, s * 0.42, -s * 0.06);
    ctx.closePath();
    ctx.fill();
    // cinta
    ctx.fillStyle = "#f2912e";
    ctx.beginPath();
    ctx.moveTo(-s * 0.4, -s * 0.08);
    ctx.lineTo(s * 0.41, -s * 0.08);
    ctx.lineTo(s * 0.36, -s * 0.24);
    ctx.lineTo(-s * 0.35, -s * 0.24);
    ctx.closePath();
    ctx.fill();
    // ala
    ctx.fillStyle = "#3a1f55";
    ctx.beginPath();
    E(ctx, -s * 0.78, -s * 0.13, s * 1.56, s * 0.24);
    ctx.fill();
    // brillo en el cono
    ctx.fillStyle = "rgba(255,255,255,0.12)";
    ctx.beginPath();
    ctx.moveTo(-s * 0.3, -s * 0.28);
    ctx.quadraticCurveTo(-s * 0.2, -s * 0.62, -s * 0.02, -s * 0.84);
    ctx.lineTo(-s * 0.1, -s * 0.5);
    ctx.lineTo(-s * 0.18, -s * 0.28);
    ctx.closePath();
    ctx.fill();
}

// Gorro de Papá Noel: rojo, caído hacia un lado (se balancea), borde y pompón blancos
function santa(ctx, s, sway) {
    const px = s * (0.78 + 0.18 * sway), py = -s * (0.34 - 0.1 * sway);
    ctx.fillStyle = "#d33a36";
    ctx.beginPath();
    ctx.moveTo(-s * 0.62, -s * 0.12);
    ctx.bezierCurveTo(-s * 0.55, -s * 0.9, s * 0.25, -s * 1.02, px, py);
    ctx.bezierCurveTo(s * 0.4, -s * 0.62, s * 0.5, -s * 0.36, s * 0.62, -s * 0.12);
    ctx.closePath();
    ctx.fill();
    ctx.fillStyle = "rgba(0,0,0,0.14)";
    ctx.beginPath();
    ctx.moveTo(s * 0.1, -s * 0.2);
    ctx.bezierCurveTo(s * 0.3, -s * 0.6, s * 0.5, -s * 0.66, px, py);
    ctx.bezierCurveTo(s * 0.4, -s * 0.62, s * 0.5, -s * 0.36, s * 0.62, -s * 0.12);
    ctx.closePath();
    ctx.fill();
    ctx.fillStyle = "#f4f1ec";
    ctx.beginPath();
    RR(ctx, -s * 0.7, -s * 0.28, s * 1.4, s * 0.3, s * 0.15);
    ctx.fill();
    ctx.beginPath();
    E(ctx, px - s * 0.15, py - s * 0.15, s * 0.3, s * 0.3);
    ctx.fill();
}

// Gorrito de fiesta: cono a rayas, algo ladeado, con pompón
function party(ctx, s, sway) {
    ctx.save();
    ctx.translate(s * 0.12, 0);
    ctx.rotate(0.22 + 0.08 * sway);
    ctx.beginPath();
    ctx.moveTo(-s * 0.36, 0);
    ctx.lineTo(0, -s * 0.95);
    ctx.lineTo(s * 0.36, 0);
    ctx.closePath();
    ctx.fillStyle = "#4f8ff0";
    ctx.fill();
    ctx.save();
    ctx.clip();
    ctx.strokeStyle = "#ffcf4a";
    ctx.lineWidth = s * 0.13;
    for (let i = 0; i < 4; i++) {
        const y = -s * (0.1 + 0.24 * i);
        ctx.beginPath();
        ctx.moveTo(-s * 0.5, y + s * 0.12);
        ctx.lineTo(s * 0.5, y - s * 0.12);
        ctx.stroke();
    }
    ctx.restore();
    ctx.fillStyle = "#ff6f91";
    ctx.beginPath();
    E(ctx, -s * 0.14, -s * 1.08, s * 0.28, s * 0.28);
    ctx.fill();
    ctx.restore();
}

// Corona de Reyes: dorada, tres puntas con perlas y piedras que brillan
function crown(ctx, s, t) {
    ctx.fillStyle = "#f2c14e";
    ctx.beginPath();
    ctx.moveTo(-s * 0.5, -s * 0.02);
    ctx.lineTo(-s * 0.55, -s * 0.52);
    ctx.lineTo(-s * 0.26, -s * 0.3);
    ctx.lineTo(0, -s * 0.66);
    ctx.lineTo(s * 0.26, -s * 0.3);
    ctx.lineTo(s * 0.55, -s * 0.52);
    ctx.lineTo(s * 0.5, -s * 0.02);
    ctx.closePath();
    ctx.fill();
    ctx.fillStyle = "#d59e2c";
    ctx.fillRect(-s * 0.5, -s * 0.16, s, s * 0.14);
    ctx.fillStyle = "#fff4cf";
    for (const [x, y] of [[-s * 0.55, -s * 0.55], [0, -s * 0.7], [s * 0.55, -s * 0.55]]) {
        ctx.beginPath();
        E(ctx, x - s * 0.08, y - s * 0.08, s * 0.16, s * 0.16);
        ctx.fill();
    }
    const gems = ["#e0434b", "#3f7de0", "#e0434b"];
    for (let i = 0; i < 3; i++) {
        ctx.fillStyle = gems[i];
        ctx.beginPath();
        E(ctx, -s * 0.3 + i * s * 0.3 - s * 0.06, -s * 0.15, s * 0.12, s * 0.12);
        ctx.fill();
    }
    // destello que va pasando
    const k = (t * 0.5) % 1;
    if (k < 0.3) {
        ctx.fillStyle = `rgba(255,255,255,${(0.5 * Math.sin(k / 0.3 * Math.PI)).toFixed(3)})`;
        ctx.beginPath();
        E(ctx, -s * 0.5 + k / 0.3 * s - s * 0.06, -s * 0.5, s * 0.12, s * 0.4);
        ctx.fill();
    }
}
return { E, RR, draw, seasonal };
})();

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
// }

function avatar(ctx, o) {
    const s = o.s, t = o.t || 0, m = o.melt || 0, b = o.breath || 0;
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
    ctx.fillStyle = "rgba(255,255,255,0.07)";
    ctx.beginPath();
    Hats.E(ctx, cx - rx * 0.62, cy - ryT * 0.82, rx * 0.7, ryT * 0.42);
    ctx.fill();

    // Ojos
    const u = s / 32, d = 9.5 * u, f = o.face || "normal";
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
g.MochiDraw = { avatar };
g.MochiHats = Hats;
})(typeof window !== 'undefined' ? window : globalThis);
