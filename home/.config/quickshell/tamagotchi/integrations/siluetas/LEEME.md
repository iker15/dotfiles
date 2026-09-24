# Siluetas reales de las transformaciones de Mochi

Generan `tamagotchi/SkinShapes.js` (contorno, color, ojos y detalles de cada personaje) y
`tamagotchi/siluetas/<id>.png` (campo de distancias para `mochi.frag`) a partir de ilustraciones
reales de cada personaje. Las imágenes NO están en el repo (tienen derechos): se bajan a `src/`.

    uv venv .venv && uv pip install --python .venv/bin/python numpy pillow scipy opencv-python-headless
    .venv/bin/python extract.py      # siluetas (out/sil.json + out/<id>.png)
    .venv/bin/python clusters.py     # grupos de color de cada referencia (clus/<id>.png para mirarlos)
    .venv/bin/python build.py        # out/SkinShapes.js (config por personaje en CFG)
    .venv/bin/python preview.py      # preview.png: referencia al lado de lo reconstruido

Ojo: los grupos de color salen al azar en cada `clusters.py`, así que tras volver a lanzarlo hay
que revisar los números de grupo de `CFG` en build.py mirando clus/<id>.png.

Referencias usadas (src/):
- Pokémon (ditto, pikachu*, jigglypuff, gengar, snorlax): arte oficial, PokeAPI sprites
  `other/official-artwork/<n>.png`; pikachu_head.png: cabeza de frente (pngall.com
  «Pikachu-Head-Cheeks-Pointed-Ears»)
- kirby_front.png: WiKirby «KSA Kirby model.png»
- boo.png: Super Mario Wiki «Boo front vector art.svg» (rsvg-convert -w 800)
- nook.png, isabelle.png: Nookipedia «Tom Nook / Isabelle NH Character Icon.png»
- totoro.png, calcifer.png, baymax_line.png (dibujo de líneas: se usa la cabeza): pngall.com
- Blinky: el sprite de la recreativa (en extract.py) · slime de Minecraft: cubo de frente con la
  cara de su textura (en build.py)
