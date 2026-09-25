#version 440
// Cuerpo de Mochi: metaballs (campos de distancia que se funden con suavidad).
// El cuerpo es una elipse con ondas en la superficie; la masa y la cola son círculos que
// se quedan atrás al moverlo; y todo se funde con el marco de Caelestia (barra y bordes).
// El color sale de `edge`: el marco visto justo en la unión, a lo largo de cada lado (bg.py),
// así que en la unión Mochi es del mismo color que el marco, píxel a píxel.
// Puede imitar formas (engranaje, Clawd —el bichito naranja de Claude Code—, corazón,
// estrella, flecha): `shape` mezcla el cuerpo con la silueta y `shapeTint` le da su color.
// Y sacar un bracito (`arm`) de su propio material, p. ej. para sujetar la taza de café.
// Transformaciones (Skins.js): `skinTint` tiñe el fluido, `skinForm` cambia la silueta (cubo,
// llamas, fantasma, pinchos) y le brotan hasta 6 trozos (`pa*`/`pr*`: orejas, bracitos…).
// Compilar: /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o mochi.frag.qsb mochi.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;       // tamaño de este item (px)
    vec4 body;       // centro x, y, semiejes x, y
    vec4 mass;       // centro x, y, radio
    vec4 tail;       // centro x, y, radio
    vec4 wobA;       // ondas: cos 2θ, sin 2θ, cos 3θ, sin 3θ
    vec4 wobB;       //        cos 4θ, sin 4θ, cos 5θ, sin 5θ
    vec4 frame;      // interior del marco: izquierda, arriba, derecha, abajo
    vec4 color;      // color de reserva (si aún no hay textura del marco)
    vec4 view;       // posición de este item en su pantalla (x, y), ancho de `edge`, ¿hay edge?
    float blobK;     // suavizado entre las partes de Mochi
    float frameK;    // suavizado con el marco (el de Caelestia)
    float bandOnly;  // 1 = pintar solo la franja sobre el borde del marco (pasada sin sombra)
    vec4 shape;      // forma: id (0 ninguna, 1 engranaje, 2 Clawd, 3 corazón, 4 estrella, 5 flecha),
                     //        mezcla 0-1, giro (rad; en Clawd, el tiempo de su animación), tamaño (px)
    vec4 shapeTint;  // color de la forma (rgb) y cuánto (a); junto al marco sigue siendo marco
    vec4 rainbow;    // arcoíris: cuánto (x, 0-1), tiempo (y, s)
    vec4 arm;        // bracito: punta x, y (px), cuánto ha salido (0-1), grosor de la punta (px)
    vec4 skinTint;   // transformación: color (rgb) y cuánto se ha transformado (a, 0-1)
    vec4 skinForm;   // silueta: cubo, llamas, fantasma, pinchos (0-1)
    vec4 skinMisc;   // tiempo (s)
    vec4 pa0; vec4 pa1; vec4 pa2; vec4 pa3; vec4 pa4; vec4 pa5;   // trozos: a.x, a.y, b.x, b.y (en semiejes)
    vec4 pr0; vec4 pr1; vec4 pr2; vec4 pr3; vec4 pr4; vec4 pr5;   // radios en a y en b (en rx)
    vec4 silInfo;    // silueta real del personaje (siluetas/<id>.png): cuánto (x, 0-1), px por semiancho
                     // de la silueta en horizontal (y) y en vertical (z; sigue al aplastarse), y cuánto
                     // ha crecido (w: 0→1 al transformarse, pasa de 1 en el rebote; 0 = entero)
};

layout(binding = 1) uniform sampler2D edge;   // filas: abajo, derecha, arriba, izquierda
// Campo de distancias de la silueta: X −2…2, Y −3…1 en semianchos (base en Y = 1); 0.5 = borde,
// ±0.6 semianchos en 0…1
layout(binding = 2) uniform sampler2D silTex;

vec3 edgeAt(float along, float row) {
    return texture(edge, vec2((along + 0.5) / view.z, (row + 0.5) / 4.0)).rgb;
}

float dot2(vec2 v) {
    return dot(v, v);
}

float sdBox(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// (Las formas van en unidades del tamaño, y hacia arriba = +y)
float sdHeart(vec2 p) {
    p.x = abs(p.x);
    if (p.y + p.x > 1.0)
        return sqrt(dot2(p - vec2(0.25, 0.75))) - sqrt(2.0) / 4.0;
    return sqrt(min(dot2(p - vec2(0.0, 1.0)), dot2(p - 0.5 * max(p.x + p.y, 0.0)))) * sign(p.x - p.y);
}

float sdStar5(vec2 p, float r, float rf) {
    const vec2 k1 = vec2(0.809016994375, -0.587785252292);
    const vec2 k2 = vec2(-k1.x, k1.y);
    p.x = abs(p.x);
    p -= 2.0 * max(dot(k1, p), 0.0) * k1;
    p -= 2.0 * max(dot(k2, p), 0.0) * k2;
    p.x = abs(p.x);
    p.y -= r;
    vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0.0, 1.0);
    float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
    return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

// Formas "polares" (radio según el ángulo): distancia corregida con la pendiente
float gearR(float a) {
    return 0.76 + 0.24 * smoothstep(0.3, 0.7, 0.5 + 0.5 * cos(8.0 * a));
}

// Clawd, el bichito de Claude Code (▐▛███▜▌ / ▝▜█████▛▘ / ▘▘ ▝▝): un bloque con los ojos,
// una franja más ancha que son los brazos y cuatro patitas. `t` anima: patas alternas (camina
// en el sitio) y brazos que se balancean.
float clawdSd(vec2 p, float t) {
    p.y += 0.16;   // (los ojos de Mochi quedan en medio de la cabeza)
    float body = sdBox(p - vec2(0.0, 0.2), vec2(0.8, 0.36));
    float arms = sdBox(p - vec2(0.0, -0.26 + 0.035 * sin(t * 4.0)), vec2(1.08, 0.16));
    float d = min(body, arms);
    for (int i = 0; i < 4; i++) {
        float x = (i < 2 ? -1.0 : 1.0) * (i == 0 || i == 3 ? 0.58 : 0.3);
        float lift = 0.09 * max(0.0, sin(t * 8.0 + (i == 0 || i == 2 ? 0.0 : 3.1416)));
        d = min(d, sdBox(p - vec2(x, -0.55 + lift), vec2(0.075, 0.15)));
    }
    return d - 0.035;
}

float polarSd(vec2 p, float id) {
    float r = length(p), a = atan(p.y, p.x), e = 0.004;
    float f = gearR(a);
    float df = (gearR(a + e) - gearR(a - e)) / (2.0 * e);
    return (r - f) / sqrt(1.0 + (df / max(r, 0.05)) * (df / max(r, 0.05)));
}

float sdArrow(vec2 p) {
    // punta arriba (triángulo) + mástil, redondeados
    // (la base de la punta, ancha, queda a la altura de los ojos)
    vec2 t = vec2(abs(p.x), p.y - 0.98);
    vec2 n = normalize(vec2(1.2, 0.95));
    float head = max(dot(t, n), -(p.y + 0.3));
    float shaft = sdBox(p - vec2(0.0, -0.66), vec2(0.3, 0.38));
    return min(head, shaft) - 0.06;
}

float shapeSd(vec2 q) {
    float c = cos(shape.z), s = sin(shape.z);
    vec2 p = vec2(c * q.x + s * q.y, -s * q.x + c * q.y) / shape.w;
    p.y = -p.y;   // arriba = +y
    float id = shape.x, d;
    if (id < 1.5)
        d = polarSd(p, id);
    else if (id < 2.5)
        d = clawdSd(vec2(q.x, -q.y) / shape.w, shape.z);   // (sin girar: z es su tiempo)
    else if (id < 3.5)
        d = sdHeart(p * 0.84 + vec2(0.0, 0.72)) / 0.84;   // (los ojos, en los lóbulos)
    else if (id < 4.5)
        d = sdStar5(p, 1.0, 0.46) - 0.07;
    else
        d = sdArrow(p);
    return d * shape.w;
}

float smin(float a, float b, float k) {
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

// ── Transformaciones (las mismas cuentas que Skins.js) ──
float skirtEdge(float x, float t) {
    return 0.8 + 0.2 * abs(sin(1.5 * 3.14159265 * (x + 1.0) + 0.25 * sin(t * 4.0)));
}
float spikeH(float x) {
    return 0.3 * pow(max(0.0, cos(x * 2.6 * 3.14159265)), 6.0) * step(abs(x), 0.85);
}
float flameH(float x, float t) {
    return 0.22 + 0.5 * pow(0.5 + 0.5 * cos(x * 3.3 * 3.14159265 - t * 3.0), 3.0) + 0.35 * exp(-x * x * 7.0);
}

// Trozo que le brota (cápsula que se afina de a a b)
float partSd(vec2 p, vec4 ab, vec4 r, float amt) {
    if (r.x * amt < 0.004)
        return 1e5;
    float k = 0.55 + 0.45 * amt;
    vec2 a = body.xy + ab.xy * body.zw * k, b = body.xy + ab.zw * body.zw * k;
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-3), 0.0, 1.0);
    return length(pa - ba * h) - mix(r.x, r.y, h) * body.z * amt;
}

// La silueta del cuerpo (elipse con ondas, distancia d) convertida en la de la skin
float skinBody(float d, vec2 q, float amt) {
    vec2 u = q / body.zw;
    float R = min(body.z, body.w), t = skinMisc.x;
    if (skinForm.x > 0.0) {
        float rr = 0.22 * R;
        d = mix(d, sdBox(q, body.zw * 0.96 - rr) - rr, skinForm.x * amt);
    }
    if (skinForm.z > 0.0 && u.y > 0.0) {
        float xe = clamp(u.x, -1.0, 1.0);
        float dg = max(abs(u.x) - 1.0, u.y - skirtEdge(xe, t)) * R;
        d = mix(d, dg, skinForm.z * amt * smoothstep(0.0, 0.25, u.y));
    }
    float up = max(0.0, -u.y / max(length(u), 1e-3));
    float xc = clamp(u.x, -1.0, 1.0);
    if (skinForm.w > 0.0)
        d -= skinForm.w * amt * spikeH(xc) * pow(up, 1.5) * body.w;
    if (skinForm.y > 0.0)
        d -= skinForm.y * amt * flameH(xc, t) * pow(up, 1.2) * body.w;
    return d;
}

void main() {
    vec2 p = qt_TexCoord0 * size;

    // Fuera del interior del marco no se pinta (el marco ya lo dibuja Caelestia), salvo una
    // franja de 6 px junto a Mochi: el borde del marco está suavizado (semitransparente) y
    // tiene un filo de otro tono; junto a su cuerpo se veía como una rayita
    float inside = min(min(p.x - frame.x, frame.z - p.x), min(p.y - frame.y, frame.w - p.y));
    if (inside < -6.0 || (bandOnly > 0.5 && inside >= 0.0)) {
        fragColor = vec4(0.0);
        return;
    }

    // Elipse con ondas
    vec2 q = p - body.xy;
    float a = atan(q.y, q.x);
    float wob = wobA.x * cos(2.0 * a) + wobA.y * sin(2.0 * a) + wobA.z * cos(3.0 * a) + wobA.w * sin(3.0 * a)
              + wobB.x * cos(4.0 * a) + wobB.y * sin(4.0 * a) + wobB.z * cos(5.0 * a) + wobB.w * sin(5.0 * a);
    float d = (length(q / body.zw) - (1.0 + wob)) * min(body.z, body.w);
    // Transformado: su silueta y lo que le brota (orejas, bracitos…), del mismo material
    // (los trozos usan skinMisc.y: sin recortar, así rebotan un poco al brotar)
    float amt = skinTint.a, amtP = skinMisc.y;
    if (amt > 0.001) {
        d = skinBody(d, q, amt);
        d = smin(d, partSd(p, pa0, pr0, amtP), 10.0);
        d = smin(d, partSd(p, pa1, pr1, amtP), 10.0);
        d = smin(d, partSd(p, pa2, pr2, amtP), 10.0);
        d = smin(d, partSd(p, pa3, pr3, amtP), 10.0);
        d = smin(d, partSd(p, pa4, pr4, amtP), 10.0);
        d = smin(d, partSd(p, pa5, pr5, amtP), 10.0);
    }

    // Transformado en un personaje: el fluido toma su silueta real (y sigue temblando).
    // Al transformarse, la silueta le CRECE desde los pies (empieza pequeñita dentro de él, sale
    // del cuerpo fundida con él y se pasa un poco en el rebote) mientras lo redondo se deshace
    // en ella; a medio camino el borde hierve un poco (es un fluido cambiando de forma)
    float dsil = 1e5;
    if (silInfo.x > 0.001) {
        float grow = silInfo.w > 0.0 ? 0.55 + 0.45 * silInfo.w : 1.0;   // (del 55 %, casi su tamaño, a entero)
        float kx = silInfo.y * grow, ky = silInfo.z * grow;
        vec2 s = vec2(q.x / kx, 1.0 + (q.y - body.w) / ky);
        vec2 uv = vec2((s.x + 2.0) * 0.25, (s.y + 3.0) * 0.25);
        float ds;
        if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0)
            ds = (texture(silTex, uv).r - 0.5) * 1.2;
        else
            ds = 0.6 + length(max(abs(s - vec2(0.0, -1.0)) - vec2(2.0), 0.0));
        ds = ds * min(kx, ky) - wob * min(body.z, body.w) * 0.5;
        float t = clamp(silInfo.x, 0.0, 1.0), boil = 4.0 * t * (1.0 - t);
        ds -= boil * 2.6 * sin(5.0 * a + skinMisc.x * 9.0) * sin(3.0 * a - skinMisc.x * 6.0);
        dsil = ds;
        d = mix(smin(d, ds, 16.0 * (1.0 - t) + 0.5), ds, smoothstep(0.25, 1.0, t));
    }

    // La masa y la cola (inercia): transformado, solo pueden salirse un poco de su silueta
    // (si no, en las siluetas bajitas asomaban por encima y la redondeaban)
    float dmass = length(p - mass.xy) - mass.z, dtail = length(p - tail.xy) - tail.z;
    if (silInfo.x > 0.001) {
        float t = clamp(silInfo.x, 0.0, 1.0);
        dmass = mix(dmass, max(dmass, dsil - 5.0), t);
        dtail = mix(dtail, max(dtail, dsil - 5.0), t);
    }
    d = smin(d, dmass, blobK);
    d = smin(d, dtail, blobK);
    // Bracito: sale del centro y se va afinando hasta la punta
    if (arm.z > 0.001) {
        vec2 pa = p - body.xy, ba = (arm.xy - body.xy) * arm.z;
        float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1.0), 0.0, 1.0);
        d = smin(d, length(pa - ba * h) - mix(0.42 * min(body.z, body.w), arm.w, h), 16.0);
    }
    // Imitando una forma: el cuerpo se convierte en su silueta
    if (shape.y > 0.001)
        d = mix(d, shapeSd(q), shape.y);
    float dm = d;   // solo Mochi, sin el marco

    // Fundirse con el marco
    d = smin(d, inside, frameK);

    float alpha = clamp(0.5 - d, 0.0, 1.0);
    if (inside < 0.0)   // en la franja del borde: solo donde Mochi está pegado, fundiéndose
        // (y difuminada hacia dentro del marco, para que su tono pase al de Mochi sin escalón)
        alpha = clamp((frameK * 0.6 - dm) / (frameK * 0.3), 0.0, 1.0) * smoothstep(-6.0, -1.5, inside);
    if (alpha <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    // Color: el del marco en el punto de la unión más cercano, mezclando lados cerca de las esquinas
    vec3 col = color.rgb;
    if (view.w > 0.5) {
        vec2 s = p + view.xy;   // coordenadas en la pantalla
        vec4 dist = max(vec4(frame.w - p.y, frame.z - p.x, p.y - frame.y, p.x - frame.x), 0.0);
        vec4 w = 1.0 / pow(dist + 4.0, vec4(4.0));
        col = (edgeAt(s.x, 0.0) * w.x + edgeAt(s.y, 1.0) * w.y + edgeAt(s.x, 2.0) * w.z + edgeAt(s.y, 3.0) * w.w)
            / (w.x + w.y + w.z + w.w);
    }
    // Color de la transformación (junto al marco sigue siendo marco: es el mismo fluido)
    if (amt > 0.001)
        col = mix(col, skinTint.rgb, amt * smoothstep(4.0, 22.0, inside));
    // Color de la forma (p. ej. el naranja de Clawd), salvo junto al marco: ahí sigue siendo
    // marco, como si el material se transformara en él
    if (shapeTint.a > 0.0 && shape.y > 0.0)
        col = mix(col, shapeTint.rgb, shapeTint.a * clamp(shape.y, 0.0, 1.0) * smoothstep(4.0, 22.0, inside));
    // Arcoíris: bandas de color que recorren el cuerpo en diagonal (junto al marco, marco)
    if (rainbow.x > 0.0) {
        float h = fract((p.x + p.y) / 160.0 - rainbow.y * 0.7);
        vec3 rgb = clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
        col = mix(col, mix(vec3(1.0), rgb, 0.8), rainbow.x * smoothstep(4.0, 22.0, inside));
    }
    fragColor = vec4(col, 1.0) * alpha * qt_Opacity;
}
