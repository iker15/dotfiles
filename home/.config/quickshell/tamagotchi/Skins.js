.pragma library
.import "Hats.js" as Hats
.import "SkinShapes.js" as Shapes

// Transformaciones de Mochi (skins). No son accesorios: Mochi es un fluido y SE CONVIERTE en
// otro personaje (como Ditto). Cada 5 niveles desbloquea una: le salen 3 al azar y eliges una.
// Portátil (Canvas de QML y de HTML; integrations/build-web.sh hace una copia sin .pragma).
//
// La forma de cada una es la SILUETA REAL del personaje (SkinShapes.js, sacada de ilustraciones
// suyas: el contorno, el color del cuerpo, dónde tiene los ojos y sus detalles —mofletes, boca,
// antifaz, puntas de las orejas…— como polígonos). Si el personaje no es «tipo blob» (Pikachu,
// Tom Nook, Canela, Baymax) es solo su cabeza/cara. En el escritorio el shader convierte el
// fluido en esa silueta con su campo de distancias (siluetas/<id>.png); aquí se dibuja con los
// puntos. Sus ojos son los de Mochi (se mueven, parpadean, ponen caras) en el sitio de los suyos.
//
// g (geometría que reciben los dibujos) = { x: centro · base: suelo del cuerpo · k: px por
// semiancho de la silueta · amt: cuánto se ha transformado · accents / mono / ink }

const list = [
    {
        id: "ditto",
        name: "Ditto",
        from: "Pokémon"
    },
    {
        id: "nook",
        name: "Tom Nook",
        from: "Animal Crossing"
    },
    {
        id: "pikachu",
        name: "Pikachu",
        from: "Pokémon"
    },
    {
        id: "kirby",
        name: "Kirby",
        from: "Kirby"
    },
    {
        id: "jigglypuff",
        name: "Jigglypuff",
        from: "Pokémon"
    },
    {
        id: "gengar",
        name: "Gengar",
        from: "Pokémon"
    },
    {
        id: "snorlax",
        name: "Snorlax",
        from: "Pokémon"
    },
    {
        id: "boo",
        name: "Boo",
        from: "Super Mario"
    },
    {
        id: "totoro",
        name: "Totoro",
        from: "Mi vecino Totoro"
    },
    {
        id: "calcifer",
        name: "Calcifer",
        from: "El castillo ambulante"
    },
    {
        id: "mcslime",
        name: "Slime",
        from: "Minecraft"
    },
    {
        id: "blinky",
        name: "Blinky",
        from: "Pac-Man"
    },
    {
        id: "baymax",
        name: "Baymax",
        from: "Big Hero 6"
    },
    {
        id: "isabelle",
        name: "Canela",
        from: "Animal Crossing"
    }
].map(s => {
    s.sil = Shapes.get(s.id);
    s.color = s.sil.color;
    return s;
});

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

// Punto de la silueta (semianchos; y hacia abajo, base en y = 1) → px
function S(g, x, y) {
    return [g.x + x * g.k, g.base + (y - 1) * (g.ky || g.k)];
}

// Contorno del cuerpo a medio transformar: de Mochi (rim(i, n): punto i de n de su elipse, en px,
// empezando por la derecha y bajando) a la silueta del personaje
function outline(skin, g, rim, amt) {
    const p = skin.sil.pts, n = p.length / 2, a = Math.max(0, Math.min(1, amt)), out = [];
    for (let i = 0; i < n; i++) {
        const [sx, sy] = S(g, p[2 * i], p[2 * i + 1]);
        if (a >= 1) {
            out.push([sx, sy]);
            continue;
        }
        const [ex, ey] = rim(i, n);
        out.push([ex + (sx - ex) * a, ey + (sy - ey) * a]);
    }
    return out;
}

// Ojos de la skin (en el sitio de los suyos), mezclados con los de Mochi (look = Look.data())
function eyesOf(skin, look) {
    const e = skin?.sil?.eyes || {};
    return {
        eyeSize: look?.eyeSize ?? 1,
        eyeGap: look?.eyeGap ?? 1,
        eyeY: look?.eyeY ?? 0,
        eyeShape: e.shape ?? 0,
        ink: e.ink || null,
        round: e.round ?? 1,
        white: e.white || "",
        whiteScale: e.ws ?? 1.9,
        shine: !!e.shine,
        lid: e.lid ?? 0,
        tilt: e.tilt ?? 0,
        // dónde (centro entre los dos, media separación, diámetro: en semianchos de la silueta)
        at: skin?.sil ? {
            x: e.x,
            y: e.y,
            g: e.g,
            d: e.d,
            size: skin.sil.size
        } : null
    };
}

// (los detalles aparecen a partir de media transformación)
function fade(amt) {
    const k = Math.max(0, Math.min(1, (amt - 0.35) / 0.65));
    return k * k * (3 - 2 * k);
}

// Sus detalles (mofletes, boca, antifaz, puntas de las orejas…), recortados a la silueta
// (`path` la dibuja). Con su color de siempre (mono) solo la cara, en el color de sus ojos.
function drawUnder(ctx, skin, g, path) {
    const f = fade(g.amt ?? 1);
    if (!skin?.sil || f <= 0)
        return;
    ctx.save();
    ctx.globalAlpha *= f;
    ctx.beginPath();
    path(ctx);
    ctx.clip();
    ctx.lineJoin = "round";
    for (const mk of skin.sil.marks) {
        if (!mk.f && g.accents === false)
            continue;
        const col = mk.f && g.mono ? g.ink : mk.c;
        ctx.fillStyle = col;
        ctx.beginPath();
        for (const poly of mk.p)
            for (const r of poly) {
                for (let i = 0; i < r.length; i += 2) {
                    const [x, y] = S(g, r[i], r[i + 1]);
                    if (i)
                        ctx.lineTo(x, y);
                    else
                        ctx.moveTo(x, y);
                }
                ctx.closePath();
            }
        ctx.fill();
        // (las líneas de la cara, con un trazo: en pequeño, si no, casi no se ven)
        if (mk.f) {
            ctx.strokeStyle = col;
            ctx.lineWidth = Math.max(0.7, 0.014 * g.k);
            ctx.stroke();
        }
    }
    ctx.restore();
}

// (antes pintaba boca y bigotes encima de los ojos; ahora todo va en drawUnder)
function drawOver(ctx, skin, g, amt) {
    g.amt = amt;
}

// Color hex → [r, g, b] 0-1 (para el shader)
function rgb(hex) {
    const n = parseInt(String(hex).slice(1), 16);
    return [(n >> 16 & 255) / 255, (n >> 8 & 255) / 255, (n & 255) / 255];
}
