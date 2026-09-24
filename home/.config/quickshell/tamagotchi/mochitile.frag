#version 440
// Mochi en la pantalla de bloqueo: una ficha (cuadrado de bordes redondeados, como las demás de
// la tarjeta) que se va transformando en cosas: un reloj con sus manecillas (la hora de verdad),
// un candado, una pila con la batería que queda, un sol o una luna. Pasa de una forma a otra
// mezclando sus distancias (fluido, como es él) y con un poco de gelatina (`squash`).
// Formas: 0 ficha · 1 reloj · 2 candado · 3 pila · 4 sol · 5 luna
// Compilar: /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o mochitile.frag.qsb mochitile.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;       // tamaño del item (px)
    vec4 morph;      // forma de la que viene, forma a la que va, mezcla 0-1, radio de la ficha (px)
    vec4 info;       // ángulo de la aguja de las horas, de los minutos (rad), batería 0-1, tiempo (s)
    vec2 squash;     // escala de gelatina (x, y)
    vec4 color;      // material (con su transparencia; premultiplicado)
    float inset;     // margen alrededor de la ficha dentro del item (para la gelatina)
};

float sdBox(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sdRoundBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float sdSegment(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// (unidades: 1 = S, algo menos de la mitad del item; arriba = +y)
float sdClock(vec2 p) {
    float face = length(p) - 0.95;
    vec2 hd = vec2(sin(info.x), cos(info.x)), md = vec2(sin(info.y), cos(info.y));
    float hands = min(sdSegment(p, vec2(0.0), hd * 0.46) - 0.075, sdSegment(p, vec2(0.0), md * 0.7) - 0.05);
    float ticks = 1e5;
    for (int i = 0; i < 12; i++) {
        float a = float(i) * 0.5235988;
        vec2 dir = vec2(sin(a), cos(a));
        float big = (i % 3 == 0) ? 1.0 : 0.0;
        ticks = min(ticks, sdSegment(p, dir * (0.8 - 0.06 * big), dir * 0.86) - (0.028 + 0.012 * big));
    }
    return max(face, -min(hands, ticks));
}

float sdPadlock(vec2 p) {
    float body = sdRoundBox(p - vec2(0.0, -0.3), vec2(0.72, 0.56), 0.16);
    vec2 c = vec2(0.0, 0.26);
    float ring = abs(length(p - c) - 0.44) - 0.12;
    ring = max(ring, -(p.y - c.y));   // solo la mitad de arriba
    float legs = sdBox(vec2(abs(p.x) - 0.44, p.y - 0.13), vec2(0.12, 0.14));
    return min(body, min(ring, legs));
}

float sdBattery(vec2 p) {
    float outer = sdRoundBox(p - vec2(0.0, -0.06), vec2(0.5, 0.84), 0.14);
    float inner = sdRoundBox(p - vec2(0.0, -0.06), vec2(0.37, 0.71), 0.07);
    float nub = sdRoundBox(p - vec2(0.0, 0.84), vec2(0.2, 0.08), 0.04);
    float lvl = clamp(info.z, 0.04, 1.0);
    float h = 1.3 * lvl;
    float fill = sdRoundBox(p - vec2(0.0, -0.71 - 0.06 + h * 0.5 + 0.06), vec2(0.28, h * 0.5), 0.05);
    return min(min(max(outer, -inner), nub), fill);
}

float sdSun(vec2 p) {
    float d = length(p) - 0.52;
    float a = atan(p.x, p.y) + info.w * 0.25;   // los rayos giran despacio
    float k = floor(a / 0.7853982 + 0.5);
    float ra = k * 0.7853982 - info.w * 0.25;
    vec2 dir = vec2(sin(ra), cos(ra));
    return min(d, sdSegment(p, dir * 0.7, dir * 0.93) - 0.07);
}

float sdMoon(vec2 p) {
    float a = length(p) - 0.82;
    float b = length(p - vec2(0.42, 0.3)) - 0.7;
    return max(a, -b);
}

// Distancia en px a la forma n (px: coordenadas desde el centro, arriba = +y)
float shapeSd(float n, vec2 px) {
    vec2 tile = size - 2.0 * inset;
    float S = min(tile.x, tile.y) * 0.46;
    vec2 p = px / S;
    if (n < 0.5)
        return sdRoundBox(px, tile * 0.5, morph.w);
    float d;
    if (n < 1.5)
        d = sdClock(p);
    else if (n < 2.5)
        d = sdPadlock(p);
    else if (n < 3.5)
        d = sdBattery(p);
    else if (n < 4.5)
        d = sdSun(p);
    else
        d = sdMoon(p);
    return d * S;
}

void main() {
    vec2 px = (qt_TexCoord0 - 0.5) * size;
    px.y = -px.y;
    px /= squash;
    float t = morph.z;
    float d = mix(shapeSd(morph.x, px), shapeSd(morph.y, px), t);
    // (a mitad del cambio, un poco más blandito: se funde de una forma a la otra)
    d -= sin(3.1416 * t) * 4.0;
    float alpha = clamp(0.5 - d * min(squash.x, squash.y), 0.0, 1.0);
    fragColor = color * alpha * qt_Opacity;   // (Qt ya lo pasa premultiplicado)
}
