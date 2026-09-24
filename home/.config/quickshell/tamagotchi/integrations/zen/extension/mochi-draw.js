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
const Skins = (function () {

// Transformaciones de Mochi (skins). No son accesorios: Mochi es un fluido y SE CONVIERTE en
// otro personaje (como Ditto). Cada 5 niveles desbloquea una: le salen 3 al azar y eliges una.
// Portátil (Canvas de QML y de HTML; integrations/build-web.sh hace una copia sin .pragma).
//
// Cada skin:
//   color   cuerpo (el fluido entero se tiñe; junto al marco sigue siendo marco)
//   form    silueta del cuerpo: square (cubo), flame (llamas arriba), skirt (fantasma: base
//           ondulada), spikes (pinchos arriba), 0-1
//   parts   trozos de su mismo material que le salen del cuerpo (orejas, bracitos, pico…):
//           cápsulas de a → b con radio ra → rb. Coordenadas relativas al centro del cuerpo en
//           semiejes (x · rx, y · ry; y hacia abajo); radios en rx. Los pinta mochi.frag en el
//           escritorio y partPath() en los retratos.
//   eyes    sus ojos (en las unidades de Look: size, gap, y, shape) + ink (color), round (1
//           redondos, 0 cuadrados), white (esclerótica: color y escala), shine (brillito),
//           lid/tilt (párpado de base: dormido, enfadado…)
//   under   detalles pintados SOBRE el cuerpo y BAJO los ojos (antifaz, barriga, mofletes);
//           recortados a la silueta del cuerpo
//   over    detalles por encima de los ojos (boca, bigotes, puntas de las orejas, patas)
//
// g (geometría que recibe under/over) = { x, y: centro del cuerpo · rx, ryT, ryB: semiejes
// (arriba/abajo) · t: tiempo (s) · face · eyes: [[x, y], [x, y]] centros de los ojos }

const list = [
    {
        id: "ditto",
        name: "Ditto",
        from: "Pokémon",
        color: "#c39bd3",
        form: {},
        parts: [
            {
                a: [-0.8, -0.1],
                b: [-1.1, -0.34],
                ra: 0.27,
                rb: 0.15
            },
            {
                a: [0.8, -0.1],
                b: [1.1, -0.34],
                ra: 0.27,
                rb: 0.15
            }
        ],
        eyes: {
            ink: "#241a2a",
            size: 0.42,
            gap: 0.78,
            y: -0.6
        },
        over(ctx, g) {
            // su boquita: una raya fina, un poco ondulada
            const [x0, y0] = P(g, -0.36, 0.1), [x1, y1] = P(g, 0.36, 0.1);
            ctx.strokeStyle = "#241a2a";
            ctx.lineWidth = g.rx * 0.035;
            ctx.lineCap = "round";
            ctx.beginPath();
            ctx.moveTo(x0, y0);
            ctx.bezierCurveTo(x0 + (x1 - x0) * 0.3, y0 + g.ryB * 0.09, x0 + (x1 - x0) * 0.7, y0 - g.ryB * 0.02, x1, y1 - g.ryB * 0.03);
            ctx.stroke();
        }
    },
    {
        id: "nook",
        name: "Tom Nook",
        from: "Animal Crossing",
        color: "#a47b55",
        form: {},
        parts: [
            {
                a: [-0.62, -0.8],
                b: [-0.66, -0.9],
                ra: 0.27,
                rb: 0.27
            },
            {
                a: [0.62, -0.8],
                b: [0.66, -0.9],
                ra: 0.27,
                rb: 0.27
            }
        ],
        eyes: {
            ink: "#1c130c",
            size: 0.5,
            gap: 0.74,
            y: -0.3,
            shine: true
        },
        under(ctx, g) {
            // tripa y hocico clarito
            ctx.fillStyle = "#f0dbb6";
            oval(ctx, g, 0, 0.36, 0.78, 0.52);
            oval(ctx, g, 0, 0.9, 1.1, 0.55);
            // antifaz de mapache alrededor de los ojos
            ctx.fillStyle = "#5e432d";
            ctx.beginPath();
            for (const s of [-1, 1]) {
                const [x, y] = P(g, s * 0.34, -0.3);
                Hats.E(ctx, x - g.rx * 0.3, y - g.rx * 0.21, g.rx * 0.6, g.rx * 0.4);
            }
            ctx.fill();
            ctx.fillRect(P(g, -0.1, 0)[0], P(g, 0, -0.34)[1], g.rx * 0.2, g.rx * 0.1);
        },
        over(ctx, g) {
            // dentro de las orejas
            ctx.fillStyle = "#6b4c33";
            for (const s of [-1, 1])
                circle(ctx, g, s * 0.66 * g.grow, -0.9 * g.grow, 0.14 * g.amt);
            // nariz
            ctx.fillStyle = "#2d1f15";
            oval(ctx, g, 0, 0.02, 0.2, 0.13);
            // boquita
            smile(ctx, g, 0, 0.2, 0.13, "#5e432d", 0.03);
        }
    },
    {
        id: "pikachu",
        name: "Pikachu",
        from: "Pokémon",
        color: "#f6d23b",
        form: {},
        parts: [
            {
                a: [-0.42, -0.72],
                b: [-0.98, -1.72],
                ra: 0.2,
                rb: 0.07,
                tip: "#2a2118",
                tipFrom: 0.62
            },
            {
                a: [0.42, -0.72],
                b: [0.98, -1.72],
                ra: 0.2,
                rb: 0.07,
                tip: "#2a2118",
                tipFrom: 0.62
            }
        ],
        eyes: {
            ink: "#1d1712",
            size: 0.95,
            gap: 1,
            y: -0.35,
            shine: true
        },
        under(ctx, g) {
            ctx.fillStyle = "#e5483b";
            for (const s of [-1, 1])
                circle(ctx, g, s * 0.68, 0.14, 0.17);
        },
        over(ctx, g) {
            ctx.fillStyle = g.ink || "#1d1712";
            oval(ctx, g, 0, -0.02, 0.06, 0.04);
            // boca "ω"
            ctx.strokeStyle = g.ink || "#1d1712";
            ctx.lineWidth = g.rx * 0.03;
            ctx.lineCap = "round";
            ctx.beginPath();
            const [x, y] = P(g, 0, 0.1), w = g.rx * 0.1;
            ctx.moveTo(x - 2 * w, y - w * 0.3);
            ctx.quadraticCurveTo(x - w, y + w * 1.1, x, y);
            ctx.quadraticCurveTo(x + w, y + w * 1.1, x + 2 * w, y - w * 0.3);
            ctx.stroke();
        }
    },
    {
        id: "kirby",
        name: "Kirby",
        from: "Kirby",
        color: "#f6a6c1",
        form: {},
        parts: [
            {
                a: [-0.82, 0.08],
                b: [-1.1, -0.04],
                ra: 0.3,
                rb: 0.22
            },
            {
                a: [0.82, 0.08],
                b: [1.1, -0.04],
                ra: 0.3,
                rb: 0.22
            }
        ],
        eyes: {
            ink: "#15204e",
            size: 0.95,
            gap: 0.6,
            y: -0.5,
            shape: 1,
            shine: true
        },
        under(ctx, g) {
            ctx.fillStyle = "#f2789a";
            for (const s of [-1, 1])
                oval(ctx, g, s * 0.58, 0.14, 0.3, 0.14);
        },
        over(ctx, g) {
            // boquita y los zapatos rojos
            ctx.fillStyle = "#9c2340";
            const [x, y] = P(g, 0, 0.14), w = g.rx * 0.07;
            ctx.beginPath();
            ctx.moveTo(x - w, y - w * 0.4);
            ctx.quadraticCurveTo(x, y - w * 0.1, x + w, y - w * 0.4);
            ctx.quadraticCurveTo(x, y + w * 1.6, x - w, y - w * 0.4);
            ctx.fill();
            ctx.fillStyle = "#d8304e";
            for (const s of [-1, 1])
                oval(ctx, g, s * 0.5, 0.94, 0.62, 0.3);
        }
    },
    {
        id: "jigglypuff",
        name: "Jigglypuff",
        from: "Pokémon",
        color: "#f7b9cd",
        form: {},
        parts: [
            {
                a: [-0.55, -0.72],
                b: [-0.86, -1.14],
                ra: 0.3,
                rb: 0.05
            },
            {
                a: [0.55, -0.72],
                b: [0.86, -1.14],
                ra: 0.3,
                rb: 0.05
            },
            {
                a: [0.02, -0.88],
                b: [0.16, -1.1],
                ra: 0.2,
                rb: 0.11
            }
        ],
        eyes: {
            ink: "#2e82c2",
            size: 1.35,
            gap: 1.02,
            y: -0.1,
            white: "#ffffff",
            whiteScale: 1.28,
            shine: true
        },
        under(ctx, g) {
            ctx.fillStyle = "#f29ab5";
            for (const s of [-1, 1])
                oval(ctx, g, s * 0.66, 0.22, 0.2, 0.1);
        },
        over(ctx, g) {
            // dentro de las orejas
            ctx.fillStyle = "#3c2c33";
            for (const s of [-1, 1])
                capsule(ctx, g, [s * 0.6 * g.grow, -0.8 * g.grow], [s * 0.82 * g.grow, -1.08 * g.grow], 0.13 * g.amt, 0.03 * g.amt);
            // el tupé enroscado
            ctx.strokeStyle = "#e58fab";
            ctx.lineWidth = g.rx * 0.045;
            ctx.lineCap = "round";
            ctx.beginPath();
            const [x, y] = P(g, 0.07 * g.grow, -0.93 * g.grow), r = g.rx * 0.13 * g.amt;
            for (let i = 0; i <= 24; i++) {
                const a = -Math.PI / 2 + i / 24 * Math.PI * 1.7, rr = r * (1 - i / 34);
                const px = x + Math.cos(a) * rr, py = y + Math.sin(a) * rr;
                if (i)
                    ctx.lineTo(px, py);
                else
                    ctx.moveTo(px, py);
            }
            ctx.stroke();
            smile(ctx, g, 0, 0.3, 0.1, "#9c3f5c", 0.03);
        }
    },
    {
        id: "gengar",
        name: "Gengar",
        from: "Pokémon",
        color: "#6d4b9c",
        form: {
            spikes: 1
        },
        parts: [
            {
                a: [-0.58, -0.7],
                b: [-0.98, -1.28],
                ra: 0.23,
                rb: 0.03
            },
            {
                a: [0.58, -0.7],
                b: [0.98, -1.28],
                ra: 0.23,
                rb: 0.03
            }
        ],
        eyes: {
            ink: "#ff3a3f",
            size: 1.05,
            gap: 0.95,
            y: -0.45,
            shape: -0.35,
            lid: 0.34,
            tilt: 0.55
        },
        over(ctx, g) {
            // sonrisa enorme con dientes
            const [x0, y0] = P(g, -0.62, 0.12), [x1] = P(g, 0.62, 0.12), [, yb] = P(g, 0, 0.52);
            ctx.fillStyle = "#f7f4f8";
            ctx.beginPath();
            ctx.moveTo(x0, y0);
            ctx.quadraticCurveTo((x0 + x1) / 2, y0 + g.ryB * 0.12, x1, y0);
            ctx.quadraticCurveTo((x0 + x1) / 2, yb + g.ryB * 0.22, x0, y0);
            ctx.fill();
            ctx.strokeStyle = "#4b2f70";
            ctx.lineWidth = g.rx * 0.022;
            ctx.beginPath();
            ctx.moveTo(x0 + g.rx * 0.08, y0 + g.ryB * 0.14);
            ctx.quadraticCurveTo((x0 + x1) / 2, y0 + g.ryB * 0.34, x1 - g.rx * 0.08, y0 + g.ryB * 0.14);
            for (let i = 1; i < 6; i++) {
                const x = x0 + (x1 - x0) * i / 6, dip = Math.sin(Math.PI * i / 6);
                ctx.moveTo(x, y0 + g.ryB * (0.04 + 0.07 * dip));
                ctx.lineTo(x, y0 + g.ryB * (0.12 + 0.3 * dip));
            }
            ctx.stroke();
        }
    },
    {
        id: "snorlax",
        name: "Snorlax",
        from: "Pokémon",
        color: "#2f6479",
        form: {},
        parts: [
            {
                a: [-0.5, -0.82],
                b: [-0.66, -1.14],
                ra: 0.17,
                rb: 0.04
            },
            {
                a: [0.5, -0.82],
                b: [0.66, -1.14],
                ra: 0.17,
                rb: 0.04
            }
        ],
        eyes: {
            ink: "#1b2a31",
            size: 1.05,
            gap: 0.82,
            y: -0.2,
            lid: 0.78
        },
        under(ctx, g) {
            // cara y barriga color crema (la cara con el "flequillo" en punta)
            ctx.fillStyle = "#efe0bf";
            oval(ctx, g, 0, 1.0, 1.7, 1.0);
            ctx.beginPath();
            const [x, y] = P(g, 0, -0.14), w = g.rx * 0.72, h = g.ryT * 0.5;
            ctx.moveTo(x - w, y + h * 0.35);
            ctx.quadraticCurveTo(x - w * 0.95, y - h * 0.75, x - w * 0.45, y - h * 0.62);
            ctx.lineTo(x - w * 0.25, y - h * 0.3);
            ctx.lineTo(x, y - h * 0.85);
            ctx.lineTo(x + w * 0.25, y - h * 0.3);
            ctx.lineTo(x + w * 0.45, y - h * 0.62);
            ctx.quadraticCurveTo(x + w * 0.95, y - h * 0.75, x + w, y + h * 0.35);
            ctx.quadraticCurveTo(x + w * 0.9, y + h * 1.25, x, y + h * 1.3);
            ctx.quadraticCurveTo(x - w * 0.9, y + h * 1.25, x - w, y + h * 0.35);
            ctx.fill();
        },
        over(ctx, g) {
            // boca con dos colmillitos
            const [x0, y] = P(g, -0.32, 0.14), [x1] = P(g, 0.32, 0.14);
            ctx.strokeStyle = "#1b2a31";
            ctx.lineWidth = g.rx * 0.03;
            ctx.lineCap = "round";
            ctx.beginPath();
            ctx.moveTo(x0, y);
            ctx.quadraticCurveTo((x0 + x1) / 2, y + g.ryB * 0.06, x1, y);
            ctx.stroke();
            ctx.fillStyle = "#ffffff";
            for (const s of [-1, 1]) {
                const fx = (x0 + x1) / 2 + s * g.rx * 0.17;
                ctx.beginPath();
                ctx.moveTo(fx - g.rx * 0.045, y + g.ryB * 0.035);
                ctx.lineTo(fx + g.rx * 0.045, y + g.ryB * 0.035);
                ctx.lineTo(fx, y - g.ryB * 0.09);
                ctx.fill();
            }
        }
    },
    {
        id: "boo",
        name: "Boo",
        from: "Super Mario",
        color: "#f3f2ef",
        form: {},
        parts: [
            {
                a: [-0.82, 0.1],
                b: [-1.06, 0.26],
                ra: 0.21,
                rb: 0.14
            },
            {
                a: [0.82, 0.1],
                b: [1.06, 0.26],
                ra: 0.21,
                rb: 0.14
            }
        ],
        eyes: {
            ink: "#15151a",
            size: 1,
            gap: 0.7,
            y: -0.7,
            shape: 0.9
        },
        under(ctx, g) {
            ctx.fillStyle = "#f6b3c3";
            for (const s of [-1, 1])
                oval(ctx, g, s * 0.56, 0.02, 0.26, 0.12);
        },
        over(ctx, g) {
            // bocaza abierta con la lengua fuera
            const [x, y] = P(g, 0, 0.26), w = g.rx * 0.3, h = g.ryB * 0.3;
            ctx.fillStyle = "#2d1c26";
            ctx.beginPath();
            ctx.moveTo(x - w, y - h * 0.5);
            ctx.quadraticCurveTo(x, y - h * 0.8, x + w, y - h * 0.5);
            ctx.quadraticCurveTo(x + w * 0.9, y + h, x, y + h);
            ctx.quadraticCurveTo(x - w * 0.9, y + h, x - w, y - h * 0.5);
            ctx.fill();
            ctx.fillStyle = "#ec6d8d";
            ctx.beginPath();
            Hats.E(ctx, x - w * 0.5, y + h * 0.2, w, h * 1.2);
            ctx.fill();
            ctx.fillStyle = "#ffffff";
            for (const s of [-1, 1]) {
                ctx.beginPath();
                ctx.moveTo(x + s * w * 0.75, y - h * 0.55);
                ctx.lineTo(x + s * w * 0.5, y - h * 0.6);
                ctx.lineTo(x + s * w * 0.6, y - h * 0.1);
                ctx.fill();
            }
        }
    },
    {
        id: "totoro",
        name: "Totoro",
        from: "Mi vecino Totoro",
        color: "#7c7e86",
        form: {},
        parts: [
            {
                a: [-0.42, -0.8],
                b: [-0.5, -1.42],
                ra: 0.17,
                rb: 0.06
            },
            {
                a: [0.42, -0.8],
                b: [0.5, -1.42],
                ra: 0.17,
                rb: 0.06
            }
        ],
        eyes: {
            ink: "#141414",
            size: 0.5,
            gap: 1.02,
            y: -0.8,
            white: "#fbfaf2",
            whiteScale: 2.2
        },
        under(ctx, g) {
            // barriga clara con sus marcas en V
            ctx.fillStyle = "#e9e1c7";
            oval(ctx, g, 0, 0.62, 1.5, 1.15);
            ctx.strokeStyle = "#72747b";
            ctx.lineWidth = g.rx * 0.04;
            ctx.lineCap = "round";
            for (const [cx, cy] of [[-0.3, 0.26], [0, 0.2], [0.3, 0.26], [-0.15, 0.42], [0.15, 0.42]]) {
                const [x, y] = P(g, cx, cy), w = g.rx * 0.07;
                ctx.beginPath();
                ctx.moveTo(x - w, y + w * 0.6);
                ctx.lineTo(x, y);
                ctx.lineTo(x + w, y + w * 0.6);
                ctx.stroke();
            }
        },
        over(ctx, g) {
            // nariz y bigotes
            ctx.fillStyle = "#2a2a2e";
            const [x, y] = P(g, 0, -0.34), w = g.rx * 0.1;
            ctx.beginPath();
            ctx.moveTo(x - w, y - w * 0.3);
            ctx.lineTo(x + w, y - w * 0.3);
            ctx.lineTo(x, y + w * 0.35);
            ctx.fill();
            ctx.strokeStyle = "#3a3b40";
            ctx.lineWidth = g.rx * 0.018;
            for (const s of [-1, 1])
                for (let i = -1; i <= 1; i++) {
                    const [x0, y0] = P(g, s * 0.5, -0.02 + i * 0.07);
                    ctx.beginPath();
                    ctx.moveTo(x0, y0);
                    ctx.lineTo(x0 + s * g.rx * 0.38, y0 + i * g.ryT * 0.08 - g.ryT * 0.02);
                    ctx.stroke();
                }
        }
    },
    {
        id: "calcifer",
        name: "Calcifer",
        from: "El castillo ambulante",
        color: "#ff8526",
        form: {
            flame: 1
        },
        parts: [],
        eyes: {
            ink: "#2a160c",
            size: 0.55,
            gap: 0.9,
            y: -0.35,
            white: "#fff3c9",
            whiteScale: 2.2
        },
        under(ctx, g) {
            // corazón del fuego, más claro, que parpadea
            const k = 0.85 + 0.15 * Math.sin(g.t * 9) * Math.sin(g.t * 5.3);
            ctx.fillStyle = "rgba(255, 216, 92, 0.85)";
            oval(ctx, g, 0, 0.3, 1.25 * k, 1.1 * k);
            ctx.fillStyle = "rgba(255, 244, 190, 0.7)";
            oval(ctx, g, 0, 0.5, 0.7 * k, 0.6 * k);
        },
        over(ctx, g) {
            // bocaza de fuego
            const [x, y] = P(g, 0, 0.3), w = g.rx * 0.4, h = g.ryB * (0.22 + 0.04 * Math.sin(g.t * 7));
            ctx.fillStyle = "#b8410f";
            ctx.beginPath();
            ctx.moveTo(x - w, y - h * 0.3);
            ctx.quadraticCurveTo(x, y + h * 0.1, x + w, y - h * 0.3);
            ctx.quadraticCurveTo(x, y + h * 1.4, x - w, y - h * 0.3);
            ctx.fill();
        }
    },
    {
        id: "slime",
        name: "Slime",
        from: "Dragon Quest",
        color: "#3a8ce4",
        form: {},
        parts: [
            {
                a: [0, -0.76],
                b: [0.12, -1.32],
                ra: 0.34,
                rb: 0.05
            }
        ],
        eyes: {
            ink: "#121418",
            size: 0.52,
            gap: 0.78,
            y: -0.35,
            white: "#ffffff",
            whiteScale: 2
        },
        under(ctx, g) {
            ctx.fillStyle = "rgba(255,255,255,0.45)";
            oval(ctx, g, -0.5, -0.55, 0.32, 0.2);
        },
        over(ctx, g) {
            // sonrisa grande con la lengua
            const [x0, y0] = P(g, -0.44, 0.12), [x1] = P(g, 0.44, 0.12), cx = (x0 + x1) / 2, h = g.ryB * 0.42;
            ctx.fillStyle = "#7c1a28";
            ctx.beginPath();
            ctx.moveTo(x0, y0);
            ctx.quadraticCurveTo(cx, y0 + h * 0.25, x1, y0);
            ctx.quadraticCurveTo(cx, y0 + h * 1.8, x0, y0);
            ctx.fill();
            ctx.fillStyle = "#e3576c";
            ctx.beginPath();
            Hats.E(ctx, cx - g.rx * 0.2, y0 + h * 0.5, g.rx * 0.4, h * 0.45);
            ctx.fill();
        }
    },
    {
        id: "mcslime",
        name: "Slime",
        from: "Minecraft",
        color: "#79c35c",
        form: {
            square: 1
        },
        parts: [],
        eyes: {
            ink: "#27491f",
            size: 1.15,
            gap: 0.82,
            y: -0.4,
            round: 0.12
        },
        under(ctx, g) {
            // el cubo de dentro, más oscuro
            ctx.fillStyle = "rgba(60, 130, 45, 0.55)";
            const [x0, y0] = P(g, -0.55, -0.5), [x1, y1] = P(g, 0.55, 0.62);
            ctx.fillRect(x0, y0, x1 - x0, y1 - y0);
            ctx.fillStyle = "rgba(210, 255, 190, 0.35)";
            const [hx, hy] = P(g, -0.78, -0.8);
            ctx.fillRect(hx, hy, g.rx * 0.22, g.rx * 0.12);
        },
        over(ctx, g) {
            ctx.fillStyle = "#27491f";
            const [x, y] = P(g, 0.12, 0.22);
            ctx.fillRect(x, y, g.rx * 0.18, g.rx * 0.14);
        }
    },
    {
        id: "blinky",
        name: "Blinky",
        from: "Pac-Man",
        color: "#ea2e2c",
        form: {
            skirt: 1
        },
        parts: [],
        eyes: {
            ink: "#2334d4",
            size: 0.62,
            gap: 0.9,
            y: -0.45,
            shape: 0.3,
            white: "#ffffff",
            whiteScale: 1.75
        }
    },
    {
        id: "baymax",
        name: "Baymax",
        from: "Big Hero 6",
        color: "#f6f6f3",
        form: {},
        parts: [],
        eyes: {
            ink: "#141414",
            size: 0.6,
            gap: 1.05,
            y: -0.55
        },
        over(ctx, g) {
            if (!g.eyes)
                return;
            ctx.strokeStyle = "#141414";
            ctx.lineWidth = g.rx * 0.035;
            ctx.beginPath();
            ctx.moveTo(g.eyes[0][0], g.eyes[0][1]);
            ctx.lineTo(g.eyes[1][0], g.eyes[1][1]);
            ctx.stroke();
        }
    },
    {
        id: "isabelle",
        name: "Canela",
        from: "Animal Crossing",
        color: "#f5d67b",
        form: {},
        parts: [
            {
                a: [-0.66, -0.72],
                b: [-1.04, -0.06],
                ra: 0.2,
                rb: 0.25
            },
            {
                a: [0.66, -0.72],
                b: [1.04, -0.06],
                ra: 0.2,
                rb: 0.25
            },
            {
                a: [0, -0.84],
                b: [0.04, -1.2],
                ra: 0.22,
                rb: 0.1
            }
        ],
        eyes: {
            ink: "#1f1712",
            size: 0.62,
            gap: 0.8,
            y: -0.3,
            shine: true
        },
        under(ctx, g) {
            ctx.fillStyle = "#fff5dc";
            oval(ctx, g, 0, 0.22, 0.72, 0.44);
            ctx.fillStyle = "#f4a8a0";
            for (const s of [-1, 1])
                oval(ctx, g, s * 0.62, 0.1, 0.22, 0.1);
        },
        over(ctx, g) {
            ctx.fillStyle = "#3a2a20";
            oval(ctx, g, 0, 0.1, 0.13, 0.09);
            smile(ctx, g, 0, 0.26, 0.1, "#3a2a20", 0.025);
            // coletero rojo del tupé
            ctx.fillStyle = "#e2453d";
            circle(ctx, g, 0.02 * g.grow, -0.98 * g.grow, 0.09 * g.amt);
        }
    }
];

function byId(id) {
    return list.find(s => s.id === id) || null;
}

// ── Desbloqueo: cada 5 niveles una (te salen 3 y eliges) ──
const every = 5;

// Niveles que dan una transformación hasta `level` (5, 10, 15…)
function milestones(level) {
    const out = [];
    for (let l = every; l <= level; l += every)
        out.push(l);
    return out;
}

function nextAt(level) {
    return (Math.floor(level / every) + 1) * every;
}

// 3 al azar entre las que no tienes (ni te están ofreciendo ya en otro nivel)
function roll(taken) {
    const pool = list.map(s => s.id).filter(id => !taken.includes(id));
    for (let i = pool.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [pool[i], pool[j]] = [pool[j], pool[i]];
    }
    return pool.slice(0, 3);
}

// ── Dibujo ──

// Punto en unidades del cuerpo → px (arriba usa el semieje de arriba y abajo el de abajo)
function P(g, x, y) {
    return [g.x + x * g.rx, g.y + y * (y < 0 ? g.ryT : g.ryB)];
}

function circle(ctx, g, x, y, r) {
    const [px, py] = P(g, x, y);
    ctx.beginPath();
    ctx.arc(px, py, r * g.rx, 0, 2 * Math.PI);
    ctx.fill();
}

// Óvalo centrado en (x, y) de ancho w y alto h (en rx)
function oval(ctx, g, x, y, w, h) {
    const [px, py] = P(g, x, y);
    ctx.beginPath();
    Hats.E(ctx, px - w * g.rx / 2, py - h * g.rx / 2, w * g.rx, h * g.rx);
    ctx.fill();
}

function smile(ctx, g, x, y, w, color, lw) {
    const [px, py] = P(g, x, y);
    ctx.strokeStyle = color;
    ctx.lineWidth = g.rx * lw;
    ctx.lineCap = "round";
    ctx.beginPath();
    ctx.moveTo(px - w * g.rx, py);
    ctx.quadraticCurveTo(px, py + w * g.rx * 0.9, px + w * g.rx, py);
    ctx.stroke();
}

// Cápsula que se afina (a → b, radios ra → rb), rellena
function capsule(ctx, g, a, b, ra, rb) {
    const [ax, ay] = P(g, a[0], a[1]), [bx, by] = P(g, b[0], b[1]);
    const Ra = ra * g.rx, Rb = rb * g.rx;
    const dx = bx - ax, dy = by - ay, L = Math.hypot(dx, dy) || 1, ang = Math.atan2(dy, dx);
    // tangentes exteriores de dos círculos
    const k = Math.asin(Math.max(-1, Math.min(1, (Ra - Rb) / L)));
    ctx.beginPath();
    ctx.arc(ax, ay, Ra, ang + Math.PI / 2 + k, ang + 3 * Math.PI / 2 - k);
    ctx.arc(bx, by, Rb, ang - Math.PI / 2 - k, ang + Math.PI / 2 + k);
    ctx.closePath();
    ctx.fill();
    // (L = distancia; si un círculo contiene al otro basta con el grande)
    if (L < Math.abs(Ra - Rb)) {
        ctx.beginPath();
        ctx.arc(Ra > Rb ? ax : bx, Ra > Rb ? ay : by, Math.max(Ra, Rb), 0, 2 * Math.PI);
        ctx.fill();
    }
}

// Partes a medio salir (amt 0-1): brotan del centro del cuerpo, como en el escritorio
function grown(p, amt) {
    const k = 0.55 + 0.45 * amt;
    return {
        a: [p.a[0] * k, p.a[1] * k],
        b: [p.b[0] * k, p.b[1] * k],
        ra: p.ra * amt,
        rb: p.rb * amt
    };
}

// Trozos que le salen (del color del cuerpo), para los retratos (en el escritorio los pinta el shader)
function drawParts(ctx, skin, g, color, amt) {
    ctx.fillStyle = color;
    for (const p of skin.parts || []) {
        const q = grown(p, amt);
        if (q.ra > 0.005)
            capsule(ctx, g, q.a, q.b, q.ra, q.rb);
    }
}

// Puntas de otro color (las orejas de Pikachu)
function drawTips(ctx, skin, g, amt) {
    for (const p of skin.parts || []) {
        if (!p.tip)
            continue;
        const q = grown(p, amt), f = p.tipFrom ?? 0.6;
        const m = [q.a[0] + (q.b[0] - q.a[0]) * f, q.a[1] + (q.b[1] - q.a[1]) * f];
        ctx.fillStyle = p.tip;
        capsule(ctx, g, m, q.b, q.ra + (q.rb - q.ra) * f, q.rb);
    }
}

// Silueta del cuerpo según su forma: radio relativo en el ángulo a (0 = derecha, y hacia abajo)
// para el retrato. `base(a)` da el punto normal [x, y] en unidades; se deforma encima.
function formPoint(skin, a, t, amt) {
    const f = skin.form || {}, c = Math.cos(a), s = Math.sin(a);
    let x = c, y = s;
    if (f.square) {
        // superelipse: casi un cubo con las esquinas algo redondas
        const n = 2 + 8 * f.square * amt, e = 2 / n;
        x = Math.sign(c) * Math.pow(Math.abs(c), e);
        y = Math.sign(s) * Math.pow(Math.abs(s), e);
    }
    if (f.skirt && s > 0) {
        // fantasma: de la mitad para abajo, recto y con tres "patitas" onduladas
        const k = f.skirt * amt;
        const sx = Math.sign(c) * Math.min(1, Math.abs(c) * 1.6);
        x += (sx - x) * k;
        y += (skirtEdge(sx, t) * Math.min(1, s * 1.4) - y) * k;
    }
    const up = Math.max(0, -s);
    if (f.spikes)
        y -= f.spikes * amt * spikeH(c) * Math.pow(up, 1.5);
    if (f.flame)
        y -= f.flame * amt * flameH(c, t) * Math.pow(up, 1.2);
    return [x, y];
}

// (las mismas cuentas que mochi.frag; x = posición horizontal −1…1)
function skirtEdge(x, t) {
    return 0.8 + 0.2 * Math.abs(Math.sin(1.5 * Math.PI * (x + 1) + 0.25 * Math.sin(t * 4)));
}
function spikeH(x) {
    // tres pinchos en lo alto de la cabeza/espalda
    return 0.3 * Math.pow(Math.max(0, Math.cos(x * 2.6 * Math.PI)), 6) * (Math.abs(x) < 0.85 ? 1 : 0);
}
function flameH(x, t) {
    // lenguas de fuego que suben y bailan, con una más alta en medio
    return 0.22 + 0.5 * Math.pow(0.5 + 0.5 * Math.cos(x * 3.3 * Math.PI - t * 3), 3) + 0.35 * Math.exp(-x * x * 7);
}

// Ojos de la skin, mezclados con los de Mochi (look = Look.data())
function eyesOf(skin, look) {
    const e = skin?.eyes || {};
    return {
        eyeSize: e.size ?? look?.eyeSize ?? 1,
        eyeGap: e.gap ?? look?.eyeGap ?? 1,
        eyeY: e.y ?? look?.eyeY ?? 0,
        eyeShape: e.shape ?? 0,
        ink: e.ink || null,
        round: e.round ?? 1,
        white: e.white || "",
        whiteScale: e.whiteScale ?? 1.9,
        shine: !!e.shine,
        lid: e.lid ?? 0,
        tilt: e.tilt ?? 0
    };
}

// Detalles bajo los ojos, recortados a la silueta (`path` dibuja la silueta del cuerpo)
function fade(amt) {
    const k = Math.max(0, Math.min(1, (amt - 0.35) / 0.65));
    return k * k * (3 - 2 * k);
}

function drawUnder(ctx, skin, g, path) {
    if (!skin?.under || fade(g.amt ?? 1) <= 0)
        return;
    ctx.save();
    ctx.globalAlpha *= fade(g.amt ?? 1);
    ctx.beginPath();
    path(ctx);
    ctx.clip();
    skin.under(ctx, g);
    ctx.restore();
}

function drawOver(ctx, skin, g, amt) {
    // (las partes que salen del cuerpo van a medio salir durante la transformación)
    g.amt = amt;
    g.grow = 0.55 + 0.45 * amt;
    if (fade(amt) <= 0)
        return;
    ctx.save();
    ctx.globalAlpha *= fade(amt);
    if (g.accents !== false)
        drawTips(ctx, skin, g, amt);
    if (skin?.over)
        skin.over(ctx, g);
    ctx.restore();
}

// Color hex → [r, g, b] 0-1 (para el shader)
function rgb(hex) {
    const n = parseInt(String(hex).slice(1), 16);
    return [(n >> 16 & 255) / 255, (n >> 8 & 255) / 255, (n & 255) / 255];
}
return { list, byId, milestones, nextAt, roll, formPoint, grown, capsule, drawParts, drawUnder, drawOver, eyesOf, rgb };
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
//   outline: color del contorno (opcional; p. ej. sobre un fondo casi del mismo color)
//   shadow: sombrita en el suelo (0-1, opcional)
//   stage: evolución por nivel (0 bebé: más pequeño y ojos más grandes · 1 normal · 2 brillante:
//   más brillo y un destello · 3 sabio: + una estrellita que le da vueltas · 4 legendario: + un
//   brillo arcoíris en el borde)
//   look: su aspecto (Look.qml: eyeSize, eyeGap, eyeY, eyeShape, wide; opcional)
//   skin: id de una transformación (Skins.js; opcional) · skinAmt: 0-1 cuánto se ha transformado
//   skinMono: con su color de siempre (solo la forma y la cara) · skinAccents: aun así, los
//   toques de color (mofletes, puntas de las orejas…)
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
    const mono = !!(skin && o.skinMono);
    const bodyCol = skin && !mono ? mixHex(o.body, skin.color, amt) : o.body;
    const g = {
        x: cx,
        y: cy,
        rx: rx,
        ryT: ryT,
        ryB: ryB,
        t: t,
        face: o.face || "normal",
        amt: amt,
        ink: mono ? o.ink : "",
        mono: mono,
        accents: !mono || !!o.skinAccents
    };
    const rimOf = skin ? (a => {
            const [fx, fy] = Skins.formPoint(skin, a, t, amt);
            return [cx + rx * fx, cy + (fy < 0 ? ryT : ryB) * fy];
        }) : rim;
    const bodyPath = c => {
        for (let i = 0; i <= 96; i++) {
            const [px, py] = rimOf(2 * Math.PI * i / 96);
            if (i)
                c.lineTo(px, py);
            else
                c.moveTo(px, py);
        }
        c.closePath();
    };

    // Sombrita en el suelo
    if (o.shadow > 0) {
        ctx.fillStyle = `rgba(0,0,0,${(0.18 * o.shadow).toFixed(3)})`;
        ctx.beginPath();
        Hats.E(ctx, cx - rx * 0.95, o.y - s * 0.07, rx * 1.9, s * 0.16);
        ctx.fill();
    }
    // Cuerpo: cúpula (arriba) + base más plana, con un brillo arriba a la izquierda (y lo que le
    // salga si está transformado: orejas, bracitos…, del mismo material)
    if (skin && o.outline) {
        // (el contorno también alrededor de las orejas: se pintan un poco más gordas debajo)
        ctx.save();
        ctx.fillStyle = o.outline;
        for (const p of skin.parts || []) {
            const q = Skins.grown(p, amt), k = Math.max(1, s * 0.035) / rx;
            if (q.ra > 0.005)
                Skins.capsule(ctx, g, q.a, q.b, q.ra + k, q.rb + k);
        }
        ctx.restore();
    }
    ctx.fillStyle = bodyCol;
    ctx.beginPath();
    bodyPath(ctx);
    ctx.fill();
    if (o.outline) {
        ctx.strokeStyle = o.outline;
        ctx.lineWidth = Math.max(1, s * 0.035);
        ctx.stroke();
    }
    if (skin)
        Skins.drawParts(ctx, skin, g, bodyCol, amt);   // (encima: tapan el contorno en la unión)
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
    if (skin && g.accents)
        Skins.drawUnder(ctx, skin, g, bodyPath);
    const SE = skin && amt > 0.5 ? Skins.eyesOf(skin, L) : null;
    const eyeSize = SE ? SE.eyeSize : L.eyeSize, eyeGap = SE ? SE.eyeGap : L.eyeGap, eyeY = SE ? SE.eyeY : L.eyeY;
    const u = s / 32, d = 9.5 * u * eyeSize * (stage === 0 ? 1.12 : 1), f = o.face || "normal";
    let lx = o.lx || 0, ly = o.ly || 0;
    if (f === "sulky")
        lx = -0.8;
    if (f === "curious")
        ly = -0.3;
    const ink = mono ? o.ink : SE?.ink || o.ink;
    const ey0 = cy - 0.12 * ryT + eyeY * 7 * u, ey = ey0 + ly * 5 * u;
    ctx.fillStyle = ink;
    ctx.strokeStyle = ink;
    ctx.lineCap = "round";
    g.eyes = [];
    for (const side of [-1, 1]) {
        const ex0 = cx + side * 11.5 * u * eyeGap * Math.max(0.8, rx / s), ex = ex0 + lx * 6 * u;
        g.eyes.push([ex0 + lx * 3 * u, ey0 + ly * 2.5 * u]);
        if (SE?.white && !["happy", "excited", "love", "asleep", "squint"].includes(f)) {
            // esclerótica: se queda en su sitio y la pupila mira
            const k = SE.whiteScale, sh = SE ? SE.eyeShape : L.eyeShape;
            const ww = d * k * (1 - 0.18 * sh), hh = d * k * (1 + 0.45 * sh) * (1 - 0.9 * (o.blink || 0));
            ctx.fillStyle = SE.white;
            ctx.beginPath();
            Hats.E(ctx, ex0 - ww / 2, ey0 - hh / 2, ww, Math.max(hh, 1.5 * u));
            ctx.fill();
            ctx.fillStyle = ink;
        }
        eye(ctx, f, ex, ey, d, side, o.blink || 0, u, SE ? SE.eyeShape : L.eyeShape, SE);
    }
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
g.MochiDraw = { avatar };
g.MochiHats = Hats;
g.MochiSkins = Skins;
})(typeof window !== 'undefined' ? window : globalThis);
