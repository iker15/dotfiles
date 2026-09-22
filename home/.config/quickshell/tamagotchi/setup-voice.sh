#!/usr/bin/env bash
# Prepara el oído de Mochi: entorno de Python con faster-whisper y los modelos (~1 GB).
set -euo pipefail
dir="$HOME/.local/share/mochi"
mkdir -p "$dir"
[ -x "$dir/venv/bin/python" ] || uv venv -q --python 3.12 "$dir/venv"
VIRTUAL_ENV="$dir/venv" uv pip install -q faster-whisper webrtcvad-wheels numpy
"$dir/venv/bin/python" - <<EOF
from faster_whisper import WhisperModel
for m in ("tiny", "small"):
    WhisperModel(m, device="cpu", compute_type="int8", download_root="$dir/models")
print("Oído de Mochi listo")
EOF
