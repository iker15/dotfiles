.pragma library

// Accesorios de temporada (los lleva Mochi en la cabeza, y su icono en el nido).
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
    ctx.ellipse(-s * 0.78, -s * 0.13, s * 1.56, s * 0.24);
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
    ctx.roundedRect(-s * 0.7, -s * 0.28, s * 1.4, s * 0.3, s * 0.15, s * 0.15);
    ctx.fill();
    ctx.beginPath();
    ctx.ellipse(px - s * 0.15, py - s * 0.15, s * 0.3, s * 0.3);
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
    ctx.ellipse(-s * 0.14, -s * 1.08, s * 0.28, s * 0.28);
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
        ctx.ellipse(x - s * 0.08, y - s * 0.08, s * 0.16, s * 0.16);
        ctx.fill();
    }
    const gems = ["#e0434b", "#3f7de0", "#e0434b"];
    for (let i = 0; i < 3; i++) {
        ctx.fillStyle = gems[i];
        ctx.beginPath();
        ctx.ellipse(-s * 0.3 + i * s * 0.3 - s * 0.06, -s * 0.15, s * 0.12, s * 0.12);
        ctx.fill();
    }
    // destello que va pasando
    const k = (t * 0.5) % 1;
    if (k < 0.3) {
        ctx.fillStyle = `rgba(255,255,255,${(0.5 * Math.sin(k / 0.3 * Math.PI)).toFixed(3)})`;
        ctx.beginPath();
        ctx.ellipse(-s * 0.5 + k / 0.3 * s - s * 0.06, -s * 0.5, s * 0.12, s * 0.4);
        ctx.fill();
    }
}
