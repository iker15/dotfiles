# Genera SkinShapes.js (siluetas, ojos y detalles reales de cada transformación) y los campos de
# distancias para el shader, a partir de las imágenes de referencia (src/) y los grupos de color
# de clusters.py (clus/*.npy).
import json, os, sys
import numpy as np, cv2
from PIL import Image
from scipy import ndimage as ndi

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import extract as X

HERE = os.path.dirname(os.path.abspath(__file__))
CL = os.path.join(HERE, "clus")
OUT = os.path.join(HERE, "out")

# Por personaje: talla (ancho en rx), grupos de cuerpo, tinta (líneas), detalles de color y ojos
# (grupos del ojo + dónde están, en fracción de la imagen; sclera = grupo del blanco del ojo)
CFG = {
    "ditto": dict(size=1.3, body=[0, 2, 4, 6, 7], color=0, ink=[],
                  marks=[dict(k=[8, 1, 3, 5], face=True, stroke=True, box=(0.36, 0.19, 0.66, 0.34))],
                  eyes=dict(k=[1], at=[(0.44, 0.22), (0.59, 0.25)])),
    "nook": dict(size=1.08, body=[2], color=2, ink=[],
                 marks=[dict(k=[8]), dict(k=[3]), dict(k=[6]), dict(k=[1, 4])],
                 eyes=dict(k=[7], sclera=[0], at=[(0.33, 0.50), (0.68, 0.50)], lid=0.42)),
    "kirby": dict(size=1.3, body=[0, 3, 8, 6], color=0, ink=[7],
                  marks=[dict(k=[1])],
                  eyes=dict(k=[2, 5, 7, 4], at=[(0.596, 0.414), (0.779, 0.393)], shine=True)),
    "jigglypuff": dict(size=1.2, body=[0, 3, 7], color=0, ink=[6],
                       marks=[dict(k=[1, 8])],
                       eyes=dict(k=[5, 2], sclera=[4], at=[(0.28, 0.49), (0.625, 0.57)], shine=True)),
    "gengar": dict(size=1.45, body=[0, 1, 2, 5], color=2, ink=[4, 8],
                   marks=[dict(k=[6, 3], face=True)],
                   eyes=dict(k=[4, 8], plates=[7], at=[(0.33, 0.46), (0.56, 0.51)], d=0.08)),
    "boo": dict(size=1.25, body=[0, 8, 5, 3], color=0, ink=[1, 4, 7],
                marks=[dict(k=[2, 6], face=True)],
                eyes=dict(k=[1, 4], at=[(0.41, 0.38), (0.55, 0.37)], split=5)),
    "totoro": dict(size=1.1, body=[0, 7, 8], color=0, ink=[2, 5],
                   marks=[dict(k=[1, 6, 4])],
                   eyes=dict(k=[2, 5], sclera=[3], at=[(0.33, 0.30), (0.67, 0.30)])),
    "isabelle": dict(size=1.2, body=[1], color=1, ink=[4, 7],
                     marks=[dict(k=[0, 8]), dict(k=[2]), dict(k=[6]), dict(k=[5])],
                     eyes=dict(k=[3], at=[(0.385, 0.61), (0.635, 0.61)], shine=True)),
}
SIZES = {"mcslime": 0.92, "blinky": 1.0, "baymax": 1.15}


def hexc(c):
    return "#%02x%02x%02x" % tuple(int(v) for v in c)


def rings(mask):
    """Contornos de una máscara: [[exterior, agujeros…], …] en píxeles (exterior + / agujero −)."""
    cs, hier = cv2.findContours(mask.astype(np.uint8), cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
    out = []
    if hier is None:
        return out
    hier = hier[0]
    for i, c in enumerate(cs):
        if hier[i][3] != -1:
            continue
        comp = [c[:, 0, :]]
        j = hier[i][2]
        while j != -1:
            comp.append(cs[j][:, 0, :])
            j = hier[j][0]
        out.append(comp)
    return out


def simplify(r, eps):
    a = cv2.approxPolyDP(r.reshape(-1, 1, 2).astype(np.int32), eps, True)[:, 0, :]
    return a.astype(np.float64)


def orient(P, positive):
    area = np.sum(P[:, 0] * np.roll(P[:, 1], -1) - np.roll(P[:, 0], -1) * P[:, 1])
    return P if (area > 0) == positive else P[::-1]


def flat(P):
    return [round(float(v), 3) for v in P.reshape(-1)]


def lum(hx):
    n = int(hx[1:], 16)
    return (0.299 * (n >> 16 & 255) + 0.587 * (n >> 8 & 255) + 0.114 * (n & 255)) / 255


def tone_marks(body, marks):
    """Cada detalle, en el color de Mochi: las líneas y lo muy oscuro de la cara en el color de
    sus ojos (i) y el resto en un tono más oscuro de su cuerpo (t: 0 = cuerpo … 1 = ojos), según
    lo claro u oscuro que es en el personaje, y separados para que se distingan."""
    lb = lum(body)
    for mk in marks:
        lm = lum(mk["c"])
        if mk.get("ink") or (mk["f"] and lm < 0.4 and not mk.get("plate")):
            mk["i"] = 1
            continue
        t = 0.16 + 0.62 * max(0.0, lb - lm) + 0.22 * max(0.0, lm - lb)
        if mk.get("plate"):
            t = max(t, 0.3)
        mk["t"] = min(0.72, t)
    # (colores distintos del personaje → tonos que se distinguen)
    tonal = sorted([mk for mk in marks if "t" in mk], key=lambda m: m["t"])
    for a, b in zip(tonal, tonal[1:]):
        if b["c"] != a["c"] and b["t"] - a["t"] < 0.09:
            b["t"] = min(0.8, a["t"] + 0.09)
    for mk in marks:
        mk.pop("ink", None)
        mk.pop("plate", None)
        if "t" in mk:
            mk["t"] = round(mk["t"], 3)
    return marks


def stroke_of(mask, N, hw):
    """Una línea (la boca de Ditto) como trazo limpio: su línea central, suavizada, y su grosor."""
    ys, xs = np.nonzero(mask)
    cols_ = {}
    for x, y in zip(xs, ys):
        cols_.setdefault(x, []).append(y)
    X = np.array(sorted(cols_))
    Y = np.array([np.mean(cols_[x]) for x in X])
    th = float(np.median([max(cols_[x]) - min(cols_[x]) + 1 for x in X]))
    k = 5
    Ys = np.convolve(np.pad(Y, k, mode="edge"), np.ones(2 * k + 1) / (2 * k + 1), mode="same")[k:-k]
    idx = np.linspace(0, len(X) - 1, 16).round().astype(int)
    P = N(np.stack([X[idx] + 0.5, Ys[idx] + 0.5], axis=1).astype(float))
    return flat(P), round(th / hw, 3)


def norm_fn(mask):
    ys, xs = np.nonzero(mask)
    x0, x1, y1 = xs.min(), xs.max() + 1, ys.max() + 1
    hw, cx = (x1 - x0) / 2, (x0 + x1) / 2
    return lambda P: np.stack([(P[:, 0] - cx) / hw, 1 + (P[:, 1] - y1) / hw], axis=1), hw


def build(sid, c):
    full = np.load(os.path.join(CL, f"{sid}.npy"))
    cols = np.load(os.path.join(CL, f"{sid}_cols.npy"))
    m = full >= 0
    m = ndi.binary_fill_holes(m)
    lab, n = ndi.label(m)
    if n > 1:
        m = lab == (1 + int(np.argmax(ndi.sum(m, lab, range(1, n + 1)))))
    H, W = m.shape
    N, hw = norm_fn(m)
    band = max(2.0, 0.012 * max(H, W))
    edge = ndi.distance_transform_edt(m)
    isin = lambda ks: np.isin(full, ks) & m
    area = m.sum()

    # ── Ojos: el trozo de sus grupos que hay en cada sitio indicado ──
    e = c["eyes"]
    eyemask = np.zeros_like(m)
    eyes = []
    eyes_wh = []
    plates = []
    ek = ndi.binary_closing(isin(e["k"]), iterations=2) & (edge > band * 0.5)
    elab, _ = ndi.label(ek)
    er = ndi.binary_erosion(ek, iterations=e.get("split", 2))
    erlab, _ = ndi.label(er)

    def nearest(lab_, px, py):
        ys, xs = np.nonzero(lab_)
        if not len(xs):
            return None, 1e9
        j = int(np.argmin((xs - px) ** 2 + (ys - py) ** 2))
        return lab_ == lab_[ys[j], xs[j]], np.hypot(xs[j] - px, ys[j] - py)

    for fx, fy in e["at"]:
        px, py = int(fx * W), int(fy * H)
        # (el trozo más cercano a ese punto; si va pegado a otra cosa por un hilo —los ojos de
        # Boo a sus cejas— se separa adelgazando y se recupera su forma)
        comp, _ = nearest(elab, px, py)
        seed, dist = nearest(erlab, px, py)
        if seed is not None and dist < 8 and seed.sum() < 0.7 * comp.sum():
            comp = comp & ndi.binary_dilation(seed, iterations=e.get("split", 2) + 1)
        cy_, cx_ = ndi.center_of_mass(comp)
        cys, cxs = np.nonzero(comp)
        ew, eh = cxs.max() - cxs.min() + 1, cys.max() - cys.min() + 1
        dia = max(ew, 2 * np.sqrt(comp.sum() / np.pi))
        eyes_wh.append((ew, eh))
        sc = None
        if e.get("sclera"):
            s = isin(e["sclera"]) | comp
            slab, _ = ndi.label(ndi.binary_closing(s, iterations=2))
            sc = slab == slab[int(cy_), int(cx_)]
            if slab[int(cy_), int(cx_)] == 0:
                sc = None
        region = sc if sc is not None else comp
        if e.get("plates"):
            # la forma real de su ojo (la de Gengar, de malo): un detalle de otro tono con su
            # contorno de tinta; la pupila de Mochi, donde tiene la suya (una rendija por dentro)
            pl, _ = nearest(ndi.label(isin(e["plates"]))[0], px, py)
            filled = ndi.binary_fill_holes(ndi.binary_closing(pl, iterations=2))
            pupil = ndi.binary_erosion(filled, iterations=2) & isin(e["k"])
            cy_, cx_ = ndi.center_of_mass(pupil if pupil.sum() > 3 else filled)
            plates.append(filled)
        else:
            eyemask |= ndi.binary_dilation(region, iterations=int(band) + 1)
        sd = None
        if sc is not None:
            ss = np.nonzero(sc)
            sd = max(ss[1].max() - ss[1].min(), ss[0].max() - ss[0].min()) + 1
        eyes.append((cx_, cy_, dia, sd))
    (ax, ay, ad, asd), (bx, by, bd, bsd) = eyes
    E = N(np.array([[ax, ay], [bx, by]]))
    eyedef = {
        "x": round(float(E[:, 0].mean()), 3), "y": round(float(E[:, 1].mean()), 3),
        "g": round(float(abs(E[1, 0] - E[0, 0]) / 2), 3),
        # (de tres cuartos: cada ojo a su altura; el derecho baja dy y el izquierdo sube dy)
        "dy": round(float((E[1, 1] - E[0, 1]) / 2), 3),
        "d": round(float((ad + bd) / 2 / hw), 3),
    }
    # ojos alargados u ovalados (Kirby, Boo): la forma de Mochi (−0.6 anchos … 1 alargados)
    if not e.get("lid"):
        r = float(np.mean([h / max(w, 1) for w, h in eyes_wh]))
        sh = max(-0.6, min(1.0, (r - 1) / (0.45 + 0.18 * r)))
        if abs(sh) > 0.12:
            eyedef["shape"] = round(sh, 2)
            w = float(np.mean([w for w, h in eyes_wh]))
            eyedef["d"] = round(w / (1 - 0.18 * sh) / hw, 3)
    eyedef["d"] = round(float(e.get("d", max(eyedef["d"], 0.05))), 3)
    if abs(eyedef["dy"]) < 0.015:
        del eyedef["dy"]
    if asd and bsd:
        eyedef["sclera"] = 1
        eyedef["ws"] = round(float((asd + bsd) / (ad + bd)), 2)
    for k in ("lid", "tilt", "shine"):
        if k in e:
            eyedef[k] = e[k]

    # ── Detalles: de color (accesorios) y de tinta (boca, nariz, líneas del dibujo) ──
    marks = []
    eps = 0.0035 * max(H, W)

    def add(mask, colr, face, thin=False, ink=False, plate=False):
        if not plate:
            mask = mask & ~eyemask
        if not thin:
            mask = ndi.binary_opening(mask, iterations=1)
        lab2, n2 = ndi.label(mask)
        keep = np.zeros_like(mask)
        for i in range(1, n2 + 1):
            comp = lab2 == i
            if comp.sum() >= (0.00025 if thin else 0.0006) * area:
                keep |= comp
        if not keep.any():
            return
        polys = []
        for comp in rings(keep):
            rr = []
            for ri, r in enumerate(comp):
                if len(r) < 3:
                    continue
                s = simplify(r, eps)
                if len(s) < 3:
                    continue
                rr.append(flat(orient(N(s), ri == 0)))
            if rr:
                polys.append(rr)
        if polys:
            marks.append({"c": colr, "f": 1 if face else 0, "p": polys, "ink": ink, "plate": plate})

    for pl in plates:
        add(pl, hexc(cols[e["plates"][0]]), True, plate=True)
    for mk in c["marks"]:
        mask = isin(mk["k"])
        if mk.get("box"):
            x0, y0, x1, y1 = mk["box"]
            bx_ = np.zeros_like(mask)
            bx_[int(y0 * H):int(y1 * H), int(x0 * W):int(x1 * W)] = True
            mask &= bx_ & ~eyemask
        if mk.get("stroke"):
            pts, wdt = stroke_of(mask, N, hw)
            marks.append({"c": hexc(cols[mk["k"][0]]), "f": 1, "s": pts, "w": wdt, "ink": True})
            continue
        add(mask, hexc(cols[mk["k"][0]]), mk.get("face", False))
    if c["ink"]:
        ink = isin(c["ink"])
        core = ink & (edge > band)
        # (lo que toca el borde se recupera solo si sigue a un trozo de dentro: las puntas de las
        # orejas de Pikachu sí, el contorno del dibujo no)
        grown = ink & ndi.binary_dilation(core, iterations=int(band) + 2)
        lab3, n3 = ndi.label(grown)
        edgey = np.zeros_like(grown)
        for i in range(1, n3 + 1):
            comp = lab3 == i
            frac = (comp & (edge <= band)).sum() / comp.sum()
            if frac > 0.55:
                grown &= ~comp   # el contorno del dibujo: fuera (el borde lo pone el marco)
            elif frac > 0.25:
                edgey |= comp    # lo que sale del borde hacia dentro: puntas de las orejas…
        # (las líneas finas, algo más gordas: al tamaño de Mochi si no, no se ven)
        add(ndi.binary_dilation(grown & ~edgey, iterations=1) & m, hexc(cols[c["ink"][0]]), True, thin=True, ink=True)
        add(edgey, hexc(cols[c["ink"][0]]), False, thin=True)
    body = hexc(cols[c["color"]])
    return {"color": body, "eyes": eyedef, "marks": tone_marks(body, marks)}


def manual():
    """Los que no salen de una ilustración: el slime de Minecraft, Blinky y la cara de Baymax."""
    res = {}
    # Slime de Minecraft (de frente, un cubo): la cara de la textura original (8×8): cubo de dentro,
    # ojos de 2×2 y la boca de 1 píxel
    q = lambda x0, y0, x1, y1: [flat(orient(np.array([[x0, y0], [x1, y0], [x1, y1], [x0, y1]], float), True))]
    px = lambda i: -1 + 2 * i / 8   # columna/fila de la textura → semiancho
    py = lambda j: -1 + 2 * j / 8
    res["mcslime"] = {"color": "#79c35c", "eyes": {"x": 0.0, "y": round(py(3), 3), "g": 0.5, "d": 0.25, "round": 0},
                      "marks": tone_marks("#79c35c", [{"c": "#5ea244", "f": 0, "p": [q(px(1), py(1), px(7), py(7))]},
                                                      {"c": "#1c3a12", "f": 1, "p": [q(px(4), py(5), px(5), py(6))], "ink": True}])}
    # Blinky (sprite de la recreativa: ojos blancos de 4×5 con la pupila azul de 2×2)
    res["blinky"] = {"color": "#ff0000", "eyes": {"x": 0.0, "y": -0.29, "g": 0.43, "d": 0.3, "sclera": 1, "ws": 1.9},
                     "marks": []}
    # Baymax: los dos puntos negros unidos por una raya (link: la raya va de ojo a ojo, se muevan
    # como se muevan)
    res["baymax"] = {"color": "#f4f4f2", "eyes": {"x": 0.0, "y": 0.2, "g": 0.4, "d": 0.17, "link": 0.04},
                     "marks": []}
    return res


def main():
    sil = json.load(open(os.path.join(OUT, "sil.json")))
    data = manual()
    for sid, c in CFG.items():
        data[sid] = build(sid, c)
        data[sid]["size"] = c["size"]
    for sid, s in SIZES.items():
        data[sid]["size"] = s
    order = ["ditto", "nook", "kirby", "jigglypuff", "gengar", "boo", "totoro", "mcslime", "blinky", "baymax", "isabelle"]
    lines = [".pragma library", "",
             "// Siluetas REALES de las transformaciones (generado a partir de ilustraciones de cada",
             "// personaje: contorno, color del cuerpo, dónde tiene los ojos y sus detalles —mofletes, boca,",
             "// antifaz…— como polígonos). No editar a mano: lo genera el script de siluetas.",
             "// Coordenadas en semianchos de la silueta: x −1…1, y hacia abajo con la base en y = 1.",
             "//   size  ancho de la silueta en rx de Mochi · pts contorno (x, y, x, y…)",
             "//   eyes  x, y centro entre los ojos · g media separación · d diámetro · sclera/ws (blanco del ojo)",
             "//         dy (de tres cuartos: el ojo derecho más abajo dy, el izquierdo más arriba)",
             "//         shape/round/lid/tilt/shine · link (raya de ojo a ojo, grosor: Baymax)",
             "// Todo va del color de Mochi: color es el del personaje (referencia) y cada detalle lleva",
             "//   marks [{c color original, f 1 = de la cara, i 1 = en el color de sus ojos | t tono (0 cuerpo … 1 ojos),",
             "//           p [[anillo exterior, agujeros…]] | s trazo (x, y…) con w grosor}]",
             "const shapes = {"]
    for sid in order:
        d = data[sid]
        d["pts"] = [v for p in sil[sid]["pts"] for v in p]
        lines.append(f"    {sid}: {json.dumps(d, separators=(',', ':'))},")
    lines += ["};", "", "function get(id) {", "    return shapes[id] || null;", "}", ""]
    open(os.path.join(OUT, "SkinShapes.js"), "w").write("\n".join(lines))
    for sid in order:
        d = data[sid]
        print(sid, "ojos", d["eyes"], "detalles", [("i" if mk.get("i") else mk.get("t")) for mk in d["marks"]])
    print("KB", os.path.getsize(os.path.join(OUT, "SkinShapes.js")) // 1024)


if __name__ == "__main__":
    main()
