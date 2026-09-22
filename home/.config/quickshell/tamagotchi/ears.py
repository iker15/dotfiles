#!/usr/bin/env python3
"""Oído de Mochi: escucha el micro en local y avisa cuando oye su nombre.

Todo se procesa en el PC (Whisper con faster-whisper, sin internet).
Escribe eventos por stdout, una línea cada uno, que lee shell.qml:
    ready             listo para escuchar
    wake              ha oído "Mochi" solo: espera la orden
    hearing           está oyendo la orden
    text:<frase>      orden transcrita
    idle              no ha llegado ninguna orden
"""

import collections
import os
import re
import subprocess
import sys
import time
import unicodedata

import numpy as np
import webrtcvad
from faster_whisper import WhisperModel

RATE = 16000
FRAME_MS = 30
FRAME_BYTES = RATE * FRAME_MS // 1000 * 2  # s16 mono
MODELS = os.path.expanduser("~/.local/share/mochi/models")

# Modelo rápido para detectar el nombre y otro mejor para transcribir la orden
WAKE_MODEL = os.environ.get("MOCHI_WAKE_MODEL", "tiny")
CMD_MODEL = os.environ.get("MOCHI_CMD_MODEL", "small")
# Sesga a Whisper para que escriba bien el nombre. Solo para la orden: en la
# detección haría que se inventara "Mochi" al oír ruido.
PROMPT = "Mochi, "

# Variantes con las que Whisper suele oír "Mochi"
WAKE_RE = re.compile(r"\b(mochi|mochis|mochy|mochie|motchi|moshi|moch|mo chi|muchi|mochii)\b")


def emit(msg: str) -> None:
    print(msg, flush=True)


def norm(text: str) -> str:
    text = unicodedata.normalize("NFKD", text.lower())
    text = "".join(c for c in text if not unicodedata.combining(c))
    return re.sub(r"[^\w\s]", " ", text).strip()


def transcribe(model: WhisperModel, pcm: bytes, max_tokens: int = 100, prompt: str | None = PROMPT) -> str:
    audio = np.frombuffer(pcm, dtype=np.int16).astype(np.float32) / 32768.0
    # Sin reintentos a otras temperaturas y con tope de tokens: si es ruido, que falle rápido
    segments, _ = model.transcribe(
        audio, language="es", beam_size=1, initial_prompt=prompt, temperature=0.0,
        condition_on_previous_text=False, vad_filter=False, without_timestamps=True,
        max_new_tokens=max_tokens,
    )
    return " ".join(s.text for s in segments).strip()


def strip_wake(raw: str) -> str | None:
    """Si la frase empieza (casi) por "Mochi", devuelve lo que va detrás."""
    words = norm(raw).split()
    head = " ".join(words[:4])
    m = WAKE_RE.search(head)
    if not m:
        return None
    # Cortar la frase original justo después del nombre (conservando tildes y signos)
    n_before = len(head[: m.end()].split())
    rest = raw.split()[n_before:]
    return " ".join(rest).strip(" ,.;:!¡?¿-")


class Segmenter:
    """Corta el audio en frases usando el detector de voz de WebRTC."""

    def __init__(self, silence_ms: int):
        self.vad = webrtcvad.Vad(2)
        self.silence_frames = silence_ms // FRAME_MS
        self.pre = collections.deque(maxlen=10)  # 300 ms antes de empezar a hablar
        self.buf: list[bytes] = []
        self.speaking = False
        self.silent = 0

    def feed(self, frame: bytes) -> bytes | None:
        voiced = self.vad.is_speech(frame, RATE)
        if not self.speaking:
            self.pre.append((frame, voiced))
            if sum(v for _, v in self.pre) >= 6:
                self.speaking = True
                self.buf = [f for f, _ in self.pre]
                self.pre.clear()
                self.silent = 0
            return None
        self.buf.append(frame)
        self.silent = 0 if voiced else self.silent + 1
        too_long = len(self.buf) * FRAME_MS > 15000
        if self.silent >= self.silence_frames or too_long:
            pcm = b"".join(self.buf)
            self.speaking = False
            self.buf = []
            # Descartar ruiditos cortos (< 0,5 s)
            return pcm if len(pcm) > RATE else None
        return None


def main() -> None:
    wake_model = WhisperModel(WAKE_MODEL, device="cpu", compute_type="int8",
                              download_root=MODELS, cpu_threads=16)
    cmd_model = WhisperModel(CMD_MODEL, device="cpu", compute_type="int8",
                             download_root=MODELS, cpu_threads=16)

    rec = subprocess.Popen(
        ["pw-record", "--rate", str(RATE), "--channels", "1", "--format", "s16",
         "--media-role", "Communication", "-"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    )
    emit("ready")

    listen = Segmenter(silence_ms=600)
    waiting_until = 0.0  # tras un "Mochi" a secas, hasta cuándo esperar la orden

    while True:
        frame = rec.stdout.read(FRAME_BYTES)
        if len(frame) < FRAME_BYTES:
            break

        if waiting_until and not listen.speaking and time.monotonic() > waiting_until:
            waiting_until = 0.0
            emit("idle")

        was_speaking = listen.speaking
        pcm = listen.feed(frame)
        if waiting_until and listen.speaking and not was_speaking:
            emit("hearing")
        if pcm is None:
            continue

        if waiting_until:
            # Es la orden que va después de "Mochi"
            waiting_until = 0.0
            text = transcribe(cmd_model, pcm)
            rest = strip_wake(text)
            text = rest if rest is not None else text
            emit(f"text:{text}" if text.strip(" .") else "idle")
            continue

        # ¿Ha dicho "Mochi"? Primero con el modelo rápido
        if strip_wake(transcribe(wake_model, pcm[: RATE * 2 * 3], max_tokens=12, prompt=None)) is None:
            continue
        # Sí: transcribir bien toda la frase con el modelo bueno
        rest = strip_wake(transcribe(cmd_model, pcm))
        if rest and len(rest) > 2:
            emit(f"text:{rest}")
        else:
            emit("wake")
            waiting_until = time.monotonic() + 7


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
    sys.exit(0)
