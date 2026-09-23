#version 440
// Cuerpo de Mochi: metaballs (campos de distancia que se funden con suavidad).
// El cuerpo es una elipse con ondas en la superficie; la masa y la cola son círculos que
// se quedan atrás al moverlo; y todo se funde con el marco de Caelestia (barra y bordes).
// El color sale de `edge`: el marco visto justo en la unión, a lo largo de cada lado (bg.py),
// así que en la unión Mochi es del mismo color que el marco, píxel a píxel.
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
};

layout(binding = 1) uniform sampler2D edge;   // filas: abajo, derecha, arriba, izquierda

vec3 edgeAt(float along, float row) {
    return texture(edge, vec2((along + 0.5) / view.z, (row + 0.5) / 4.0)).rgb;
}

float smin(float a, float b, float k) {
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

void main() {
    vec2 p = qt_TexCoord0 * size;

    // Fuera del interior del marco no se pinta (el marco ya lo dibuja Caelestia), salvo una
    // franja de 3 px junto a Mochi: el borde del marco está suavizado (semitransparente) y
    // encima de su cuerpo se veía como una rayita
    float inside = min(min(p.x - frame.x, frame.z - p.x), min(p.y - frame.y, frame.w - p.y));
    if (inside < -3.0) {
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
    float dm = d;   // solo Mochi, sin el marco

    // Fundirse con el marco
    d = smin(d, inside, frameK);

    float alpha = clamp(0.5 - d, 0.0, 1.0);
    if (inside < 0.0)   // en la franja del borde: solo donde Mochi está pegado, fundiéndose
        alpha = clamp((frameK * 0.6 - dm) / (frameK * 0.3), 0.0, 1.0);
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
