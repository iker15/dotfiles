# Siluetas reales de las transformaciones de Mochi: imagen → máscara → contorno normalizado
# (puntos para los retratos) + campo de distancias (PNG para el shader del escritorio).
import json, os, sys
import numpy as np, cv2
from PIL import Image
from scipy import ndimage as ndi

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "src")
OUT = os.path.join(HERE, "out")
os.makedirs(OUT, exist_ok=True)
N = 180            # puntos del contorno
TEX = 256          # campo de distancias: TEX×TEX cubriendo X∈[-2,2], Y∈[-3,1]
RANGE = 0.6        # distancia máxima codificada (en semianchos)


def alpha(name, thr=128):
    return np.array(Image.open(os.path.join(SRC, name)).convert("RGBA"))[:, :, 3] > thr


def upscale(m, target=900):
    h, w = m.shape
    k = target / max(h, w)
    if k <= 1.05:
        return m
    return cv2.resize(m.astype(np.float32), (int(w * k), int(h * k)), interpolation=cv2.INTER_CUBIC) > 0.5


def clean(m, smooth=0.006):
    m = ndi.binary_fill_holes(m)
    lab, n = ndi.label(m)
    if n > 1:
        sizes = ndi.sum(m, lab, range(1, n + 1))
        m = lab == (1 + int(np.argmax(sizes)))
    m = upscale(m)
    s = smooth * max(m.shape)
    if s > 0.3:
        m = cv2.GaussianBlur(m.astype(np.float32), (0, 0), s) > 0.5
    return ndi.binary_fill_holes(m)


def line_head(name):
    """Dibujo de líneas (Baymax): el hueco cerrado de más arriba, con su contorno."""
    lines = alpha(name, 60)
    lines = upscale(lines, 1200)
    outside = ndi.binary_fill_holes(lines) == 0
    inner = ~lines & ~outside
    lab, n = ndi.label(inner)
    best, by = None, 1e9
    for i in range(1, n + 1):
        ys, xs = np.nonzero(lab == i)
        if len(ys) < 0.002 * lines.size:
            continue
        if ys.mean() < by:
            best, by = i, ys.mean()
    head = lab == best
    # (el grosor de la línea: se le suma para que incluya su contorno)
    t = max(2, int(0.013 * lines.shape[1]))
    return ndi.binary_dilation(head, iterations=t)


def sprite(rows, scale=60):
    m = np.array([[c == "X" for c in r] for r in rows], dtype=np.uint8)
    m = np.pad(m, 1)
    return cv2.resize(m, (m.shape[1] * scale, m.shape[0] * scale), interpolation=cv2.INTER_NEAREST) > 0


BLINKY = [
    ".....XXXX.....",
    "...XXXXXXXX...",
    "..XXXXXXXXXX..",
    ".XXXXXXXXXXXX.",
    ".XXXXXXXXXXXX.",
    ".XXXXXXXXXXXX.",
    "XXXXXXXXXXXXXX",
    "XXXXXXXXXXXXXX",
    "XXXXXXXXXXXXXX",
    "XXXXXXXXXXXXXX",
    "XXXXXXXXXXXXXX",
    "XXXXXXXXXXXXXX",
    "XX.XXX..XXX.XX",
    "X...XX..XX...X",
]


def square():
    m = np.zeros((1000, 1000), np.uint8)
    cv2.rectangle(m, (100, 100), (899, 899), 1, -1)
    return m > 0


def contour(m):
    cs, _ = cv2.findContours(m.astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    c = max(cs, key=cv2.contourArea)[:, 0, :].astype(np.float64)
    return c


def resample(c, n):
    seg = np.linalg.norm(np.diff(np.vstack([c, c[:1]]), axis=0), axis=1)
    s = np.concatenate([[0], np.cumsum(seg)])
    t = np.linspace(0, s[-1], n, endpoint=False)
    cc = np.vstack([c, c[:1]])
    return np.stack([np.interp(t, s, cc[:, 0]), np.interp(t, s, cc[:, 1])], axis=1)


def normalize(m, pts):
    ys, xs = np.nonzero(m)
    x0, x1, y1 = xs.min(), xs.max() + 1, ys.max() + 1
    hw = (x1 - x0) / 2
    cx = (x0 + x1) / 2
    X = (pts[:, 0] - cx) / hw
    Y = 1 + (pts[:, 1] - y1) / hw
    P = np.stack([X, Y], axis=1)
    # orden como el contorno de Mochi: desde la derecha y bajando (ángulo creciente, y abajo)
    area = np.sum(P[:, 0] * np.roll(P[:, 1], -1) - np.roll(P[:, 0], -1) * P[:, 1])
    if area < 0:
        P = P[::-1]
    mid = (P[:, 1].min() + P[:, 1].max()) / 2
    score = P[:, 0] - 0.3 * np.abs(P[:, 1] - mid)
    P = np.roll(P, -int(np.argmax(score)), axis=0)
    return P


def sdf(P, res=1024):
    """Campo de distancias del polígono P (en semianchos) en X∈[-2,2], Y∈[-3,1]."""
    k = res / 4.0
    pix = np.round(np.stack([(P[:, 0] + 2) * k, (P[:, 1] + 3) * k], axis=1)).astype(np.int32)
    m = np.zeros((res, res), np.uint8)
    cv2.fillPoly(m, [pix], 1)
    inside = ndi.distance_transform_edt(m)
    outside = ndi.distance_transform_edt(1 - m)
    d = (outside - inside) / k
    d = cv2.resize(d.astype(np.float32), (TEX, TEX), interpolation=cv2.INTER_AREA)
    v = np.clip(0.5 + d / (2 * RANGE), 0, 1)
    return (v * 255 + 0.5).astype(np.uint8), m


SKINS = {
    "ditto": lambda: clean(alpha("ditto.png")),
    "nook": lambda: clean(alpha("nook.png"), 0.008),
    "pikachu": lambda: clean(alpha("pikachu_head.png"), 0.004),
    "kirby": lambda: clean(alpha("kirby_front.png"), 0.01),
    "jigglypuff": lambda: clean(alpha("jigglypuff.png")),
    "gengar": lambda: clean(alpha("gengar.png"), 0.004),
    "snorlax": lambda: clean(alpha("snorlax.png")),
    "boo": lambda: clean(alpha("boo.png")),
    "totoro": lambda: clean(alpha("totoro.png")),
    "calcifer": lambda: clean(alpha("calcifer.png"), 0.004),
    "mcslime": lambda: clean(square(), 0.004),
    "blinky": lambda: clean(sprite(BLINKY), 0.035),
    "baymax": lambda: clean(line_head("baymax_line.png"), 0.006),
    "isabelle": lambda: clean(alpha("isabelle.png"), 0.008),
}

def main():
    res = {}
    only = sys.argv[1:]
    for sid, fn in SKINS.items():
        if only and sid not in only:
            continue
        m = fn()
        P = normalize(m, resample(contour(m), N))
        tex, mask = sdf(P)
        Image.fromarray(tex, "L").save(os.path.join(OUT, f"{sid}.png"))
        # vista previa: la silueta rellena
        Image.fromarray((mask[::4, ::4] * 255).astype(np.uint8), "L").save(os.path.join(OUT, f"{sid}_mask.png"))
        res[sid] = {"pts": [[round(float(x), 3), round(float(y), 3)] for x, y in P], "top": round(float(P[:, 1].min()), 3)}
        print(sid, len(P), "alto", round(1 - float(P[:, 1].min()), 2))
    json.dump(res, open(os.path.join(OUT, "sil.json"), "w"))


if __name__ == "__main__":
    main()
