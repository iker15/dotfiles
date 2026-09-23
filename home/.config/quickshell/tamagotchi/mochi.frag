#version 440
// Cuerpo de Mochi: metaballs (campos de distancia que se funden con suavidad).
// El cuerpo es una elipse con ondas en la superficie; la masa y la cola son círculos que
// se quedan atrás al moverlo; y todo se funde con el marco de Caelestia (barra y bordes).
// El color sale de `edge`: el marco visto justo en la unión, a lo largo de cada lado (bg.py),
// así que en la unión Mochi es del mismo color que el marco, píxel a píxel.
// Puede imitar formas (engranaje, el destello de Claude, corazón, estrella, flecha): `shape`
// mezcla el cuerpo con la silueta. En la pantalla de bloqueo se funde con la tarjeta (`card`),
// que es translúcida: ahí solo pinta fuera de ella, repartiendo el borde para que no se note.
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
    vec4 shape;      // forma: id (0 ninguna, 1 engranaje, 2 Claude, 3 corazón, 4 estrella, 5 flecha),
                     //        mezcla 0-1, giro (rad), tamaño (px)
    vec4 card;       // tarjeta del bloqueo (x, y, ancho, alto en este item)
    float cardR;     // su radio de esquina
    float cardOn;    // 1 = hay tarjeta (Mochi en otra capa: solo pinta fuera de ella)
                     // 2 = Mochi va dentro de la capa de la tarjeta: se pinta la unión entera
    float baseAlpha; // opacidad del material (la tarjeta y Mochi)
};

layout(binding = 1) uniform sampler2D edge;   // filas: abajo, derecha, arriba, izquierda

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

float sdRoundBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
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

float claudeR(float a) {
    const float n = 11.0;
    float k = floor(a * n / 6.2831853 + 0.5);
    float len = 0.8 + 0.2 * fract(sin(k * 12.9898 + 4.1) * 43758.5453);
    float spike = pow(0.5 + 0.5 * cos(n * a), 7.0);
    return 0.36 + 0.64 * spike * len;
}

// El destello de Claude: un núcleo redondo y 11 rayos gruesos de punta redondeada, de largos
// algo distintos
float claudeSd(vec2 p) {
    const float n = 11.0, tau = 6.2831853;
    float r = length(p), a = atan(p.y, p.x);
    float k = floor(a * n / tau + 0.5);
    float da = a - k * tau / n;                 // ángulo al rayo más cercano
    float len = 0.92 + 0.2 * fract(sin(k * 12.9898 + 4.1) * 43758.5453);
    vec2 q = vec2(r * cos(da), abs(r * sin(da)));
    float ray = (q.x > len ? length(q - vec2(len, 0.0)) : q.y) - 0.13;
    float core = r - 0.64;   // (que quepan los ojos)
    // (con el rayo vecino, por si está más cerca)
    float k2 = k + (da > 0.0 ? 1.0 : -1.0);
    float da2 = a - k2 * tau / n;
    float len2 = 0.92 + 0.2 * fract(sin(k2 * 12.9898 + 4.1) * 43758.5453);
    vec2 q2 = vec2(r * cos(da2), abs(r * sin(da2)));
    float ray2 = (q2.x > len2 ? length(q2 - vec2(len2, 0.0)) : q2.y) - 0.13;
    return min(core, min(ray, ray2));
}

float polarSd(vec2 p, float id) {
    float r = length(p), a = atan(p.y, p.x), e = 0.004;
    float f = id < 1.5 ? gearR(a) : claudeR(a);
    float df = ((id < 1.5 ? gearR(a + e) : claudeR(a + e)) - (id < 1.5 ? gearR(a - e) : claudeR(a - e))) / (2.0 * e);
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
        d = claudeSd(p);
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

    d = smin(d, length(p - mass.xy) - mass.z, blobK);
    d = smin(d, length(p - tail.xy) - tail.z, blobK);
    // Imitando una forma: el cuerpo se convierte en su silueta
    if (shape.y > 0.001)
        d = mix(d, shapeSd(q), shape.y);
    float dm = d;   // solo Mochi, sin el marco

    // La tarjeta del bloqueo: se funde con ella por fuera
    float cardCov = 0.0;
    if (cardOn > 0.5) {
        float dc = sdRoundBox(p - (card.xy + card.zw * 0.5), card.zw * 0.5, cardR);
        d = smin(d, dc, frameK);
        cardCov = clamp(0.5 - dc, 0.0, 1.0);
    }

    // Fundirse con el marco
    d = smin(d, inside, frameK);

    float alpha = clamp(0.5 - d, 0.0, 1.0);
    if (inside < 0.0)   // en la franja del borde: solo donde Mochi está pegado, fundiéndose
        // (y difuminada hacia dentro del marco, para que su tono pase al de Mochi sin escalón)
        alpha = clamp((frameK * 0.6 - dm) / (frameK * 0.3), 0.0, 1.0) * smoothstep(-6.0, -1.5, inside);
    // Sobre la tarjeta no pinta (ya está ella); en su borde suavizado pone justo lo que falta
    // para que las dos capas juntas den la misma opacidad que el material
    if (cardCov > 0.0 && cardOn < 1.5)
        alpha *= (1.0 - cardCov) / max(1.0 - baseAlpha * cardCov, 0.001);
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
    fragColor = vec4(col, 1.0) * alpha * qt_Opacity;
}
