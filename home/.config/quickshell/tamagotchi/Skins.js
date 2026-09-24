.pragma library
.import "Hats.js" as Hats

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
