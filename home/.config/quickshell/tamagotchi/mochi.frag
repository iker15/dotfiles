#version 440
// Cuerpo de Mochi: metaballs (campos de distancia que se funden con suavidad).
// El cuerpo es una elipse con ondas en la superficie; la masa y la cola son círculos que
// se quedan atrás al moverlo; y todo se funde con el marco de Caelestia (barra y bordes).
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
    vec4 color;
    float blobK;     // suavizado entre las partes de Mochi
    float frameK;    // suavizado con el marco (el de Caelestia)
};

float smin(float a, float b, float k) {
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

void main() {
    vec2 p = qt_TexCoord0 * size;

    // Fuera del interior del marco no se pinta (el marco ya lo dibuja Caelestia)
    float inside = min(min(p.x - frame.x, frame.z - p.x), min(p.y - frame.y, frame.w - p.y));
    if (inside < 0.0) {
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

    // Fundirse con el marco
    d = smin(d, inside, frameK);

    float alpha = clamp(0.5 - d, 0.0, 1.0);
    fragColor = vec4(color.rgb, 1.0) * alpha * qt_Opacity;
}
