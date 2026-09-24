import json, os, re, sys
from PIL import Image, ImageDraw
HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, "out/SkinShapes.js")).read()
data = {}
for m in re.finditer(r"^    (\w+): (\{.*\}),$", src, re.M):
    data[m.group(1)] = json.loads(m.group(2))
FILES = {"ditto": "ditto.png", "nook": "nook.png", "pikachu": "pikachu_head.png", "kirby": "kirby_front.png", "jigglypuff": "jigglypuff.png", "gengar": "gengar.png", "snorlax": "snorlax.png", "boo": "boo.png", "totoro": "totoro.png", "calcifer": "calcifer.png", "isabelle": "isabelle.png"}
S = 260
tiles = []
for sid, d in data.items():
    if sys.argv[1:] and sid not in sys.argv[1:]:
        continue
    im = Image.new("RGB", (S, S), (40, 40, 48))
    dr = ImageDraw.Draw(im)
    k = S * 0.3
    T = lambda x, y: (S / 2 + x * k, S * 0.92 + (y - 1) * k)
    pts = d["pts"]
    dr.polygon([T(pts[i], pts[i + 1]) for i in range(0, len(pts), 2)], fill=d["color"])
    for mk in d["marks"]:
        for poly in mk["p"]:
            mm = Image.new("L", (S, S), 0)
            md = ImageDraw.Draw(mm)
            for ri, r in enumerate(poly):
                md.polygon([T(r[i], r[i + 1]) for i in range(0, len(r), 2)], fill=255 if ri == 0 else 0)
            im.paste(Image.new("RGB", (S, S), mk["c"]), (0, 0), mm)
    e = d["eyes"]
    for s in (-1, 1):
        cx, cy = T(e["x"] + s * e["g"], e["y"])
        if e.get("white"):
            rr = e["d"] * e["ws"] * k / 2
            dr.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=e["white"])
        rr = max(e["d"], 0.05) * k / 2
        dr.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=e["ink"])
    ref = Image.new("RGB", (S, S), (40, 40, 48))
    if sid in FILES:
        r = Image.open(os.path.join(HERE, "src", FILES[sid])).convert("RGBA")
        r.thumbnail((S, S))
        ref.paste(r, ((S - r.width) // 2, (S - r.height) // 2), r)
    t = Image.new("RGB", (2 * S, S + 18), (25, 25, 30))
    t.paste(ref, (0, 18)); t.paste(im, (S, 18))
    ImageDraw.Draw(t).text((6, 3), sid, fill=(255, 255, 255))
    tiles.append(t)
cols = 3
W = cols * 2 * S; Hh = ((len(tiles) + cols - 1) // cols) * (S + 18)
sheet = Image.new("RGB", (W, Hh), (25, 25, 30))
for i, t in enumerate(tiles):
    sheet.paste(t, ((i % cols) * 2 * S, (i // cols) * (S + 18)))
sheet.save(os.path.join(HERE, "preview.png"))
