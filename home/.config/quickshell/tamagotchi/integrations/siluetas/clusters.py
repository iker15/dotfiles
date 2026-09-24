# Agrupa los colores de cada referencia (dentro de la silueta) para ver qué regiones hay.
import os, sys
import numpy as np, cv2
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "src")
OUT = os.path.join(HERE, "clus")
os.makedirs(OUT, exist_ok=True)
FILES = {"ditto": "ditto.png", "nook": "nook.png", "pikachu": "pikachu_head.png", "kirby": "kirby_front.png",
         "jigglypuff": "jigglypuff.png", "gengar": "gengar.png", "snorlax": "snorlax.png", "boo": "boo.png",
         "totoro": "totoro.png", "calcifer": "calcifer.png", "isabelle": "isabelle.png"}
K = int(os.environ.get("K", 9))
for sid, f in FILES.items():
    if sys.argv[1:] and sid not in sys.argv[1:]:
        continue
    im = np.array(Image.open(os.path.join(SRC, f)).convert("RGBA"))
    h, w = im.shape[:2]
    s = 520 / max(h, w)
    im = cv2.resize(im, (int(w * s), int(h * s)), interpolation=cv2.INTER_AREA)
    m = im[:, :, 3] > 128
    rgb = im[:, :, :3]
    lab = cv2.cvtColor(rgb, cv2.COLOR_RGB2LAB).reshape(-1, 3).astype(np.float32)
    sel = m.reshape(-1)
    crit = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 50, 0.5)
    _, labels, centers = cv2.kmeans(lab[sel], K, None, crit, 4, cv2.KMEANS_PP_CENTERS)
    full = np.full(sel.shape, -1)
    full[sel] = labels[:, 0]
    full = full.reshape(m.shape)
    cols = cv2.cvtColor(centers.astype(np.uint8).reshape(-1, 1, 3), cv2.COLOR_LAB2RGB).reshape(-1, 3)
    # imagen: cada grupo con su color medio + leyenda con su número
    out = np.full((*m.shape, 3), 90, np.uint8)
    for i in range(K):
        out[full == i] = cols[i]
    img = Image.fromarray(np.hstack([np.where(m[..., None], rgb, 90), out]))
    d = ImageDraw.Draw(img)
    for i in range(K):
        n = int((full == i).sum())
        d.rectangle([4, 4 + i * 22, 22, 22 + i * 22], fill=tuple(int(c) for c in cols[i]), outline=(255, 255, 255))
        d.text((28, 6 + i * 22), f"{i} {'#%02x%02x%02x' % tuple(cols[i])} {100 * n / m.sum():.1f}%", fill=(255, 255, 255))
        ys, xs = np.nonzero(full == i)
        if len(xs):
            d.text((m.shape[1] + int(np.median(xs)), int(np.median(ys))), str(i), fill=(255, 0, 255))
    img.save(os.path.join(OUT, f"{sid}.png"))
    np.save(os.path.join(OUT, f"{sid}.npy"), full)
    np.save(os.path.join(OUT, f"{sid}_cols.npy"), cols)
print("ok")
