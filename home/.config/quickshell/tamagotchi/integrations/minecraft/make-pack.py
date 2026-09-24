#!/usr/bin/env python3
# Paquete de texturas "Mochi": los slimes se vuelven Mochis (cubo blandito color daifuku con sus
# dos ojos, sin boca). Textura HD (×16) sobre el patrón del slime de vanilla:
#   capa de fuera 8×8×8 en (0,0) → opaca, con los ojos pintados en la cara de delante
#   cubo de dentro, ojos y boca de vanilla → transparentes (no se ven)
# Uso: ./make-pack.py [salida.zip]
import io, json, sys, zipfile
from PIL import Image, ImageDraw, ImageFilter

S = 16                                   # escala (64×32 → 1024×512)
BODY = (232, 228, 223)                   # color daifuku
INK = (28, 27, 27)


def face(w, h, light, eyes=False):
    """Una cara del cubo: color con los bordes algo más oscuros (parece más blandito)."""
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    base = tuple(max(0, min(255, int(c * light))) for c in BODY)
    im.paste(base + (255,), (0, 0, w, h))
    # viñeta suave: bordes más oscuros
    shade = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(shade)
    m = max(2, w // 7)
    d.rectangle([m, m, w - m, h - m], fill=255)
    shade = shade.filter(ImageFilter.GaussianBlur(m * 0.8))
    dark = Image.new("RGBA", (w, h), tuple(int(c * 0.82) for c in base) + (255,))
    im = Image.composite(im, dark, shade)
    if eyes:
        d = ImageDraw.Draw(im)
        u = w / 8                      # un "píxel" de la cara de 8×8
        ew, eh = 1.5 * u, 1.6 * u
        for cx in (w / 2 - 1.45 * u, w / 2 + 1.45 * u):
            cy = h * 0.46
            d.rounded_rectangle([cx - ew / 2, cy - eh / 2, cx + ew / 2, cy + eh / 2], radius=ew * 0.45, fill=INK + (255,))
        # brillo arriba a la izquierda
        hl = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        ImageDraw.Draw(hl).ellipse([w * 0.12, h * 0.1, w * 0.45, h * 0.3], fill=(255, 255, 255, 40))
        im = Image.alpha_composite(im, hl.filter(ImageFilter.GaussianBlur(u * 0.4)))
    return im


def texture():
    tex = Image.new("RGBA", (64 * S, 32 * S), (0, 0, 0, 0))
    F = 8 * S
    # capa de fuera: arriba, abajo / derecha, delante, izquierda, detrás
    tex.paste(face(F, F, 1.06), (8 * S, 0))
    tex.paste(face(F, F, 0.8), (16 * S, 0))
    tex.paste(face(F, F, 0.92), (0, 8 * S))
    tex.paste(face(F, F, 1.0, eyes=True), (8 * S, 8 * S))
    tex.paste(face(F, F, 0.92), (16 * S, 8 * S))
    tex.paste(face(F, F, 0.9), (24 * S, 8 * S))
    return tex


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "Mochi.zip"
    buf = io.BytesIO()
    texture().save(buf, "PNG")
    icon = io.BytesIO()
    ic = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    ic.paste(face(112, 112, 1.0, eyes=True), (8, 8))
    ic.save(icon, "PNG")
    meta = {"pack": {"description": "Los slimes son Mochis", "min_format": 65, "max_format": 999}}
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("pack.mcmeta", json.dumps(meta, indent=2))
        z.writestr("pack.png", icon.getvalue())
        z.writestr("assets/minecraft/textures/entity/slime/slime.png", buf.getvalue())
    print(out)


if __name__ == "__main__":
    main()
