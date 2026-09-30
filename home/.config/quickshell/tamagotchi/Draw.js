.pragma library
.import "Hats.js" as Hats
.import "Skins.js" as Skins

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
//   outline: contorno: un color, true (un tono entre el cuerpo y los ojos) o false. Por defecto,
//   solo transformado (si no, sobre un fondo claro la silueta del personaje no se distingue)
//   shadow: sombrita en el suelo (0-1, opcional)
//   stage: evolución por nivel (0 bebé: más pequeño y ojos más grandes · 1 normal · 2 brillante:
//   más brillo y un destello · 3 sabio: + una estrellita que le da vueltas · 4 legendario: + un
//   brillo arcoíris en el borde)
//   look: su aspecto (Look.qml: eyeSize, eyeGap, eyeY, eyeShape, wide; opcional)
//   skin: id de una transformación (Skins.js; opcional) · skinAmt: 0-1 cuánto se ha transformado
//   (transformado va siempre del color de Mochi: los colores del personaje son tonos del suyo)
// }

// Aspecto con valores por defecto
function lookOf(o) {
    const l = o.look || {};
    const n = (v, d) => (typeof v === "number" && !isNaN(v) ? v : d);
    return {
        eyeSize: n(l.eyeSize, 1),
        eyeGap: n(l.eyeGap, 1),
        eyeY: n(l.eyeY, 0),
        eyeShape: n(l.eyeShape, 0),
        wide: n(l.wide, 1)
    };
}

function avatar(ctx, o) {
    // Solo los ojos (p. ej. sobre otra forma hecha de su material: el cuadrado de la terminal):
    // centrados en (x, y), con la cara que toque
    const L = lookOf(o);
    if (o.eyesOnly) {
        const u = o.s / 32, d = 9.5 * u * L.eyeSize, f = o.face || "normal";
        let lx = o.lx || 0;
        if (f === "sulky")
            lx = -0.8;
        const ly = (o.ly || 0) + (f === "curious" ? -0.3 : 0);
        ctx.fillStyle = o.ink;
        ctx.strokeStyle = o.ink;
        ctx.lineCap = "round";
        for (const side of [-1, 1])
            eye(ctx, f, o.x + side * 13 * u * L.eyeGap + lx * 6 * u, o.y + ly * 5 * u + L.eyeY * 6 * u, d, side, o.blink || 0, u, L.eyeShape);
        return;
    }
    const stage = o.stage ?? 1;
    const s = o.s * (stage === 0 ? 0.82 : 1), t = o.t || 0, m = o.melt || 0, b = o.breath || 0;
    const lw = L.wide, lh = 1 / Math.sqrt(L.wide);
    const rx = s * lw * (1 + 0.3 * m + 0.03 * b), ryT = s * lh * (1.0 - 0.34 * m - 0.03 * b), ryB = s * lh * (0.72 - 0.2 * m);
    // (punto del contorno en el ángulo a: cúpula arriba, base más plana)
    const rim = a => {
        const sn = Math.sin(a);
        return [o.x + rx * Math.cos(a), o.y - ryB + (sn < 0 ? ryT : ryB) * sn];
    };
    const cx = o.x, cy = o.y - ryB;
    // Transformado en otro personaje (Skins.js): su silueta, su color, sus ojos y sus detalles
    const skin = o.skin ? Skins.byId(o.skin) : null, amt = skin ? Math.max(0, Math.min(1, o.skinAmt ?? 1)) : 0;
    // (transformado va siempre de su color: los del personaje son tonos del suyo; ver Skins.js)
    const mono = !!skin;
    const bodyCol = o.body;
    const g = {
        x: cx,
        y: cy,
        rx: rx,
        ryT: ryT,
        ryB: ryB,
        t: t,
        face: o.face || "normal",
        amt: amt,
        ink: o.ink,
        body: o.body,
        mono: mono,
        // (para la silueta: el suelo del cuerpo y px por semiancho de la silueta)
        base: o.y,
        k: skin ? rx * skin.sil.size : rx
    };
    // Transformado: la silueta real del personaje (de Mochi a ella según amt)
    const pts = skin ? Skins.outline(skin, g, (i, n) => rim(2 * Math.PI * i / n), amt) : null;
    const bodyPath = c => {
        if (pts) {
            pts.forEach(([px, py], i) => i ? c.lineTo(px, py) : c.moveTo(px, py));
            c.closePath();
            return;
        }
        for (let i = 0; i <= 96; i++) {
            const [px, py] = rim(2 * Math.PI * i / 96);
            if (i)
                c.lineTo(px, py);
            else
                c.moveTo(px, py);
        }
        c.closePath();
    };

    // (el contorno y el borde del blanco de los ojos: un tono entre el cuerpo y sus ojos)
    const edge = Skins.tone(bodyCol, o.ink, 0.55);
    const outline = o.outline === undefined ? (skin ? edge : "") : o.outline === true ? edge : o.outline || "";

    // Sombrita en el suelo
    if (o.shadow > 0) {
        ctx.fillStyle = `rgba(0,0,0,${(0.18 * o.shadow).toFixed(3)})`;
        ctx.beginPath();
        Hats.E(ctx, cx - rx * 0.95, o.y - s * 0.07, rx * 1.9, s * 0.16);
        ctx.fill();
    }
    // Cuerpo: cúpula (arriba) + base más plana, con un brillo arriba a la izquierda (y lo que le
    // salga si está transformado: orejas, bracitos…, del mismo material)
    ctx.fillStyle = bodyCol;
    ctx.beginPath();
    bodyPath(ctx);
    ctx.fill();
    // Brillo arriba a la izquierda, recortado al cuerpo (transformado, en la esquina de SU silueta:
    // con la de Mochi se salía por fuera del personaje)
    ctx.save();
    ctx.beginPath();
    bodyPath(ctx);
    ctx.clip();
    ctx.fillStyle = `rgba(255,255,255,${stage >= 2 ? 0.2 : 0.07})`;
    ctx.beginPath();
    if (pts) {
        let x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9;
        for (const [px, py] of pts) {
            x0 = Math.min(x0, px);
            x1 = Math.max(x1, px);
            y0 = Math.min(y0, py);
            y1 = Math.max(y1, py);
        }
        const w = x1 - x0, h = y1 - y0;
        Hats.E(ctx, x0 + w * 0.16, y0 + h * 0.1, w * 0.32, h * 0.18);
    } else
        Hats.E(ctx, cx - rx * 0.62, cy - ryT * 0.82, rx * 0.7, ryT * 0.42);
    ctx.fill();
    ctx.restore();
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
                const [px, py] = rim(a0 + (a1 - a0) * k / 4);
                if (k)
                    ctx.lineTo(px, py);
                else
                    ctx.moveTo(px, py);
            }
            ctx.stroke();
        }
        ctx.restore();
    }

    // Ojos (transformado: los suyos, a partir de la mitad de la transformación)
    if (skin)
        Skins.drawUnder(ctx, skin, g, bodyPath);   // (en su color: solo la cara, salvo accents)
    // Contorno (encima de los detalles, que llegan hasta el borde)
    if (outline) {
        ctx.save();
        ctx.strokeStyle = outline;
        ctx.lineWidth = Math.max(1.2, s * 0.045);
        ctx.lineJoin = "round";
        ctx.beginPath();
        bodyPath(ctx);
        ctx.stroke();
        ctx.restore();
    }
    const SE = skin && amt > 0.5 ? Skins.eyesOf(skin, L, o.body, o.ink) : null;
    const eyeSize = SE ? SE.eyeSize : L.eyeSize, eyeGap = SE ? SE.eyeGap : L.eyeGap, eyeY = SE ? SE.eyeY : L.eyeY;
    const u = s / 32, f = o.face || "normal";
    // (transformado: en el sitio de los ojos del personaje y de su tamaño)
    const at = SE?.at ?? null;
    const d = at ? at.d * g.k : 9.5 * u * eyeSize * (stage === 0 ? 1.12 : 1);
    let lx = o.lx || 0, ly = o.ly || 0;
    if (f === "sulky")
        lx = -0.8;
    if (f === "curious")
        ly = -0.3;
    const ink = o.ink;
    const eyY = at ? g.base + (at.y - 1) * g.k : cy - 0.12 * ryT + eyeY * 7 * u;
    ctx.fillStyle = ink;
    ctx.strokeStyle = ink;
    ctx.lineCap = "round";
    g.eyes = [];
    const drawn = [];
    for (const side of [-1, 1]) {
        const ex0 = at ? cx + (at.x + side * at.g) * g.k : cx + side * 11.5 * u * eyeGap * Math.max(0.8, rx / s), ex = ex0 + lx * 6 * u;
        // (de tres cuartos, cada ojo a su altura)
        const ey0 = eyY + (at?.dy ? side * at.dy * g.k : 0), ey = ey0 + ly * 5 * u;
        g.eyes.push([ex0 + lx * 3 * u, ey0 + ly * 2.5 * u]);
        if (SE?.white && !["happy", "excited", "love", "asleep", "squint"].includes(f)) {
            // esclerótica: se queda en su sitio y la pupila mira
            const k = SE.whiteScale, sh = SE ? SE.eyeShape : L.eyeShape;
            const ww = d * k * (1 - 0.18 * sh), hh = d * k * (1 + 0.45 * sh) * (1 - 0.9 * (o.blink || 0));
            ctx.fillStyle = SE.white;
            ctx.beginPath();
            Hats.E(ctx, ex0 - ww / 2, ey0 - hh / 2, ww, Math.max(hh, 1.5 * u));
            ctx.fill();
            // (con borde: el blanco del ojo casi no se distingue de un cuerpo claro)
            ctx.strokeStyle = Skins.tone(bodyCol, ink, 0.7);
            ctx.lineWidth = Math.max(1, d * 0.1);
            ctx.stroke();
            ctx.fillStyle = ink;
            ctx.strokeStyle = ink;
        }
        eye(ctx, f, ex, ey, d, side, o.blink || 0, u, SE ? SE.eyeShape : L.eyeShape, SE);
        drawn.push([ex, ey]);
    }
    // Baymax: la raya de un ojo al otro
    if (SE?.link)
        Skins.drawLink(ctx, drawn[0], drawn[1], SE.link * g.k, ink);
    if (skin)
        Skins.drawOver(ctx, skin, g, amt);
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
    if (o.snow > 0.02 && !(skin && amt > 0.5)) {
        const w = rx * (0.5 + 0.45 * o.snow), h = 3 * u + 7 * u * o.snow;
        ctx.fillStyle = "#f6f9ff";
        ctx.beginPath();
        ctx.moveTo(cx - w, top + h * 0.55);
        ctx.bezierCurveTo(cx - w * 0.8, top - h * 0.7, cx + w * 0.8, top - h * 0.7, cx + w, top + h * 0.55);
        ctx.bezierCurveTo(cx + w * 0.4, top + h * 0.2, cx - w * 0.4, top + h * 0.2, cx - w, top + h * 0.55);
        ctx.fill();
        top -= h * 0.35;
    }
    if (o.hat && !(skin && amt > 0.5)) {   // (transformado no lleva gorro: es otro personaje)
        ctx.save();
        ctx.translate(cx, top + 0.16 * s);
        Hats.draw(ctx, o.hat, 0.75 * s, t, Math.sin(t * 1.3) * 0.3);
        ctx.restore();
    }
}

function eye(ctx, f, x, y, d, side, blink, u, shape, SE) {
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
    const sh = shape || 0;
    let w = d * (1 - 0.18 * sh), h = d * (1 + 0.45 * sh) * (1 - 0.9 * blink);
    if (f === "surprised" || f === "excited") {
        w *= 1.3;
        h *= 1.3;
    }
    // Párpado de arriba: recto (sueño) o inclinado hacia fuera (pena, calor, enfado); algunas
    // transformaciones lo traen de serie (Snorlax dormido, Gengar con cara de malo)
    let lid = 0, tilt = 0;
    if (f === "sleepy")
        lid = 0.5;
    else if (f === "hot")
        [lid, tilt] = [0.35, -0.35];
    else if (f === "sad" || f === "sulky")
        [lid, tilt] = [0.25, -0.45];
    else if (f === "angry")   // (el lado de dentro cae: ceño fruncido; los del tirachinas)
        [lid, tilt] = [0.34, 0.6];
    else if (f === "smug")    // (párpados a media asta: los mochis de las estructuras)
        [lid, tilt] = [0.42, 0.12];
    if (SE && SE.lid > lid && f !== "surprised")
        [lid, tilt] = [SE.lid, SE.tilt];
    const round = SE ? SE.round : 1;
    const topY = y - h / 2, r = Math.min(w, h) / 2 * round;
    if (!lid || h < d * 0.3) {
        Hats.RR(ctx, x - w / 2, y - h / 2, w, Math.max(h, 1.8 * u), Math.min(r, Math.max(h, 1.8 * u) / 2));
        ctx.fill();
        if (SE?.shine && h > d * 0.4)
            shine(ctx, x, y, w, h);
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
    if (SE?.shine)
        shine(ctx, x, y, w, h);
    ctx.restore();
}

// Brillito en el ojo (arriba, hacia la izquierda)
function shine(ctx, x, y, w, h) {
    const f = ctx.fillStyle;
    ctx.fillStyle = "rgba(255,255,255,0.92)";
    ctx.beginPath();
    Hats.E(ctx, x - w * 0.34, y - h * 0.4, w * 0.4, Math.min(h * 0.36, w * 0.5));
    ctx.fill();
    ctx.fillStyle = f;
}

// Mezcla de dos colores "#rrggbb" (k = 0 → a, 1 → b)
function mixHex(a, b, k) {
    if (k <= 0 || !/^#[0-9a-f]{6}$/i.test(String(a)))
        return k >= 1 ? b : a;
    if (k >= 1)
        return b;
    const A = parseInt(String(a).slice(1), 16), B = parseInt(String(b).slice(1), 16);
    const ch = sh => Math.round((A >> sh & 255) + ((B >> sh & 255) - (A >> sh & 255)) * k);
    return "#" + ((1 << 24) + (ch(16) << 16) + (ch(8) << 8) + ch(0)).toString(16).slice(1);
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
